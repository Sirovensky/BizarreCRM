import type Database from 'better-sqlite3';
import { sendSmsTenant } from './smsProvider.js';
import { sendEmail, isEmailConfigured } from './email.js';
import { createLogger } from '../utils/logger.js';
import { escapeHtml, stripSmsControlChars } from '../utils/escape.js';
import type { AsyncDb } from '../db/async-db.js';
import {
  writeLoyaltyPoints,
  computeEarnedPoints,
  type LoyaltyReferenceType,
} from '../utils/loyalty.js';

const logger = createLogger('notifications');

// ---------------------------------------------------------------------------
// Loyalty accrual hook (#18)
// ---------------------------------------------------------------------------
//
// This is the ONLY loyalty-related addition to notifications.ts. We keep the
// logic out of the existing TCPA/opt-in send paths and expose a single
// idempotent helper that the invoices / refunds / portal routes can call
// after a payment or refund has been recorded.
//
// The helper reads the tenant's store_config once, short-circuits if loyalty
// is disabled, and delegates the actual ledger write to utils/loyalty.ts
// which owns all invariants (integer points, non-negative balance, etc).

export interface AccruePaymentPointsInput {
  adb: AsyncDb;
  customerId: number | null | undefined;
  invoiceId: number;
  paymentAmount: number;
  /** Optional override — defaults to 'Payment on invoice #<invoiceId>'. */
  reason?: string;
}

/**
 * Accrue loyalty points for a recorded payment. No-op (and non-throwing)
 * when loyalty is disabled, the customer is missing, or the computed point
 * total rounds to zero. Never aborts the payment flow — the caller treats
 * loyalty as a best-effort side effect.
 *
 * Returns the number of points written (0 if the hook did nothing).
 */
export async function accruePaymentPoints(
  input: AccruePaymentPointsInput,
): Promise<number> {
  const { adb, customerId, invoiceId, paymentAmount, reason } = input;
  if (!customerId || customerId <= 0) return 0;
  if (!Number.isFinite(paymentAmount) || paymentAmount <= 0) return 0;

  try {
    const rows = await adb.all<{ key: string; value: string }>(
      `SELECT key, value FROM store_config
        WHERE key IN ('portal_loyalty_enabled', 'portal_loyalty_rate')`,
    );
    const config: Record<string, string> = {};
    for (const row of rows) config[row.key] = row.value;

    // Default: loyalty ENABLED unless an operator explicitly turned it off.
    // This mirrors the read-side default in portal-enrich.routes.ts.
    const enabled = (config.portal_loyalty_enabled || 'true') === 'true';
    if (!enabled) return 0;

    const rate = Number.parseFloat(config.portal_loyalty_rate || '1');
    const points = computeEarnedPoints(paymentAmount, rate);
    if (points <= 0) return 0;

    await writeLoyaltyPoints(adb, {
      customer_id: customerId,
      points,
      reason: reason || `Payment on invoice #${invoiceId}`,
      reference_type: 'invoice',
      reference_id: invoiceId,
    });
    return points;
  } catch (err) {
    // Loyalty is best-effort. Log the failure but never propagate — the
    // underlying payment has already been recorded and the shop owner
    // should not see a 500 just because a ledger row couldn't be written.
    logger.error('Loyalty accrual failed', {
      customerId,
      invoiceId,
      paymentAmount,
      error: err instanceof Error ? err.message : String(err),
    });
    return 0;
  }
}

export interface ReversePointsInput {
  adb: AsyncDb;
  customerId: number;
  /** Absolute number of points to remove. Caller supplies the positive value. */
  points: number;
  referenceType: LoyaltyReferenceType;
  referenceId: number;
  reason: string;
}

/**
 * Reverse previously-earned loyalty points (e.g. on a refund). This writes
 * a NEGATIVE row to the ledger. If the customer's current balance is
 * smaller than the reversal amount (because they already spent the points
 * they earned), the reversal is CLAMPED to the available balance so the
 * ledger never goes negative — the missing points are audited instead of
 * silently dropped.
 *
 * Returns the actual number of points reversed (may be less than `points`
 * when clamped, or 0 if there was nothing to reverse).
 */
export async function reverseLoyaltyPoints(
  input: ReversePointsInput,
): Promise<number> {
  const { adb, customerId, points, referenceType, referenceId, reason } = input;
  if (!customerId || customerId <= 0) return 0;
  if (!Number.isFinite(points) || points <= 0) return 0;

  try {
    const balanceRow = await adb.get<{ balance: number | null }>(
      `SELECT COALESCE(SUM(points), 0) AS balance
         FROM loyalty_points
        WHERE customer_id = ?`,
      customerId,
    );
    const current = Number(balanceRow?.balance ?? 0);
    if (current <= 0) {
      logger.info('Loyalty reversal skipped — customer balance already zero', {
        customerId,
        requested: points,
        referenceType,
        referenceId,
      });
      return 0;
    }
    const toReverse = Math.min(current, Math.floor(points));
    if (toReverse <= 0) return 0;

    await writeLoyaltyPoints(adb, {
      customer_id: customerId,
      points: -toReverse,
      reason,
      reference_type: referenceType,
      reference_id: referenceId,
    });

    if (toReverse < points) {
      logger.warn('Loyalty reversal clamped to available balance', {
        customerId,
        requested: points,
        actual: toReverse,
        referenceType,
        referenceId,
      });
    }
    return toReverse;
  } catch (err) {
    logger.error('Loyalty reversal failed', {
      customerId,
      points,
      referenceType,
      referenceId,
      error: err instanceof Error ? err.message : String(err),
    });
    return 0;
  }
}

type AnyRow = Record<string, any>;

// ---------------------------------------------------------------------------
// AU7: SMS length / fragmentation helper
// ---------------------------------------------------------------------------
// GSM-7 single-part limit is 160, concatenated parts are 153 chars each.
// Messages containing non-GSM characters (Unicode) use 70 / 67 instead.
// We keep the detection coarse — this is an advisory warning, not a gate.
const SMS_GSM7_SINGLE_LIMIT = 160;
const SMS_GSM7_PART_LIMIT = 153;

function estimateSmsParts(body: string): number {
  if (body.length <= SMS_GSM7_SINGLE_LIMIT) return 1;
  return Math.ceil(body.length / SMS_GSM7_PART_LIMIT);
}

// ---------------------------------------------------------------------------
// ENR-A4: Notification retry queue helpers
// ---------------------------------------------------------------------------

/**
 * Insert a failed notification into the retry queue with exponential backoff.
 * First retry in 5 minutes, then 25 min, then 125 min (5^retryCount minutes).
 */
// Caps on queued notification fields. Without these a runaway template could
// write megabytes per row and bloat notification_retry_queue over time.
const RETRY_MESSAGE_MAX = 1600; // 10 SMS segments — above any real use case.
const RETRY_PHONE_MAX = 32;     // E.164 is ≤15; pad for leading 00 + formatting.
const RETRY_ERROR_MAX = 500;

export function enqueueRetry(
  db: Database.Database,
  phone: string,
  message: string,
  entityType: string | null,
  entityId: number | null,
  tenantSlug: string | null,
  errorMsg: string,
): void {
  try {
    const cappedPhone = typeof phone === 'string' ? phone.slice(0, RETRY_PHONE_MAX) : '';
    const cappedMessage = typeof message === 'string' ? message.slice(0, RETRY_MESSAGE_MAX) : '';
    const cappedError = typeof errorMsg === 'string' ? errorMsg.slice(0, RETRY_ERROR_MAX) : '';
    db.prepare(`
      INSERT INTO notification_retry_queue (recipient_phone, message, entity_type, entity_id, tenant_slug, retry_count, max_retries, next_retry_at, last_error)
      VALUES (?, ?, ?, ?, ?, 0, 3, datetime('now', '+5 minutes'), ?)
    `).run(cappedPhone, cappedMessage, entityType, entityId, tenantSlug, cappedError);
  } catch (err) {
    logger.error('Failed to enqueue retry', {
      phone,
      entityType,
      entityId,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

// SEC-H69: Backoff jitter cap in seconds. Added to every next_retry_at
// calculation so concurrent workers spread their retry waves across a
// window rather than stampeding at the same instant.
const RETRY_JITTER_MAX_SECONDS = 60;

/** Returns a random integer in [0, RETRY_JITTER_MAX_SECONDS). */
function retryJitterSeconds(): number {
  return Math.floor(Math.random() * RETRY_JITTER_MAX_SECONDS);
}

/**
 * Process the retry queue: attempt to resend failed notifications.
 * Called periodically from the cron in index.ts.
 *
 * SEC-H69: Atomic claim via compare-and-swap on retry_count.
 * We SELECT candidates then immediately try to UPDATE WHERE id=? AND
 * retry_count=<seen value>. If another worker already incremented
 * retry_count the UPDATE affects 0 rows (changes===0) and we skip the
 * item — eliminating the double-processing race.
 */
export async function processRetryQueue(db: Database.Database, tenantSlug: string | null): Promise<void> {
  const candidates = db.prepare(`
    SELECT * FROM notification_retry_queue
    WHERE retry_count < max_retries AND next_retry_at <= datetime('now')
    ORDER BY next_retry_at ASC LIMIT 10
  `).all() as AnyRow[];

  if (candidates.length === 0) return;

  for (const item of candidates) {
    // SEC-H69: Atomic claim — increment retry_count only if it still matches
    // the value we read. If another worker already processed this row its
    // retry_count will differ and changes===0, so we skip safely.
    // Use the backoff schedule for the claim update too, so that a crash
    // between claim and send doesn't cause the item to re-fire after just
    // the jitter window (which burns a retry attempt prematurely).
    const claimedCount = item.retry_count + 1;
    const claimBackoffSeconds = Math.pow(5, claimedCount) * 60 + retryJitterSeconds();
    // SCAN-1135: claim UPDATE previously matched only on `retry_count = ?`
    // but not the `retry_count < max_retries` bound. If a row raced past
    // its cap (e.g. manual UPDATE, or enqueue with max_retries decreased
    // after enqueue), the initial SELECT filtered it out but a subsequent
    // enqueue-then-process cycle could still claim it and overflow the
    // cap. Add the upper-bound check to the WHERE so over-cap rows fall
    // through to `changes===0` and get skipped for dead-letter handling.
    const claimResult = db.prepare(`
      UPDATE notification_retry_queue
      SET retry_count = retry_count + 1,
          next_retry_at = datetime('now', '+' || ? || ' seconds'),
          last_error = 'processing'
      WHERE id = ? AND retry_count = ? AND retry_count < max_retries
    `).run(claimBackoffSeconds, item.id, item.retry_count) as { changes: number };

    if (claimResult.changes === 0) {
      // Another worker claimed this row — skip without processing.
      logger.info('Retry row already claimed by another worker, skipping', {
        id: item.id,
        phone: item.recipient_phone,
      });
      continue;
    }

    try {
      await sendSmsTenant(db, tenantSlug, item.recipient_phone, item.message);
      // Success — remove from retry queue (dead-letter never triggered)
      db.prepare('DELETE FROM notification_retry_queue WHERE id = ?').run(item.id);
      logger.info('Retry succeeded', {
        retryAttempt: claimedCount,
        phone: item.recipient_phone,
      });
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      if (claimedCount >= item.max_retries) {
        // SEC-H69: Dead-letter: max attempts exhausted — delete (logged below).
        db.prepare('DELETE FROM notification_retry_queue WHERE id = ?').run(item.id);
        logger.error('Retry permanently failed — dead-lettered', {
          retryCount: claimedCount,
          phone: item.recipient_phone,
          error: errorMessage,
        });
      } else {
        // Exponential backoff (5^retryCount minutes) + jitter seconds.
        const backoffMinutes = Math.pow(5, claimedCount);
        const backoffSeconds = backoffMinutes * 60 + retryJitterSeconds();
        db.prepare(`
          UPDATE notification_retry_queue
          SET next_retry_at = datetime('now', '+' || ? || ' seconds'), last_error = ?
          WHERE id = ?
        `).run(backoffSeconds, errorMessage, item.id);
        logger.warn('Retry failed, scheduled next attempt', {
          retryCount: claimedCount,
          phone: item.recipient_phone,
          nextInSeconds: backoffSeconds,
          error: errorMessage,
        });
      }
    }
  }
}

interface NotifyContext {
  ticketId: number;
  statusName?: string;
  tenantSlug?: string | null;
}

// ---------------------------------------------------------------------------
// ENR-A5: Rate limiting for auto-notifications
// Prevents flooding a customer with multiple auto-SMS in a short window.
// Checks if the same customer received an auto-SMS in the last 4 hours.
// ---------------------------------------------------------------------------
const AUTO_SMS_COOLDOWN_HOURS = 4;

/**
 * Atomically claim an auto-SMS slot for a phone number.
 * Inserts a placeholder row (provider='auto-claim') only if no auto SMS was sent
 * in the last 4 hours, using INSERT...SELECT WHERE NOT EXISTS so the check and
 * claim happen in a single serialized write — eliminating the TOCTOU race where
 * two concurrent calls could both pass a read-only check and both fire.
 *
 * Returns true if the slot was claimed (sending is allowed), false if rate-limited.
 * The placeholder row is intentionally left in place on send failure: it acts as a
 * conservative cooldown guard so a failed attempt doesn't open a retry flood.
 * Callers that successfully send will insert a second row with provider='auto' and
 * status='sent' via their normal path — that row is what future checks will see.
 */
export function isAutoSmsAllowed(db: Database.Database, phone: string): boolean {
  if (!phone) return false;
  const convPhone = phone.replace(/\D/g, '').replace(/^1/, '');
  const result = db.prepare(`
    INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, created_at, updated_at)
    SELECT '', ?, ?, '', 'rate-limit-claim', 'outbound', 'auto-claim', datetime('now'), datetime('now')
    WHERE NOT EXISTS (
      SELECT 1 FROM sms_messages
      WHERE conv_phone = ?
        AND provider IN ('auto', 'auto-claim')
        AND direction = 'outbound'
        AND created_at > datetime('now', ? || ' hours')
    )
  `).run(phone, convPhone, convPhone, `-${AUTO_SMS_COOLDOWN_HOURS}`);

  return (result.changes as number) > 0;
}

/**
 * Send auto-notifications (SMS/email) when a ticket status changes.
 * Looks up the notification template matching the status, substitutes variables, and sends.
 */
export async function sendTicketStatusNotification(db: Database.Database, ctx: NotifyContext): Promise<void> {
  const ticket = db.prepare(`
    SELECT t.id, t.order_id, t.customer_id,
      c.first_name AS customer_name, c.mobile AS customer_phone, c.phone AS customer_phone2, c.email AS customer_email,
      (SELECT td.device_name FROM ticket_devices td WHERE td.ticket_id = t.id ORDER BY td.id ASC LIMIT 1) AS device_name
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    WHERE t.id = ?
  `).get(ctx.ticketId) as AnyRow | undefined;

  if (!ticket) return;

  const phone = ticket.customer_phone || ticket.customer_phone2;
  if (!phone) return; // No phone to send to

  // AU4: Respect customer opt-in flags BEFORE doing any work.
  //   sms_opt_in (migration 001)              → global customer opt-in (DEFAULT 0 = opted-out)
  //   sms_consent_transactional (migration 063) → per-channel consent for transactional SMS
  //                                              (DEFAULT 1 = opted-in)
  //
  // Only block when a flag is EXPLICITLY set to 0 (opted-out). NULL means the
  // column did not exist at customer creation time (pre-migration rows) — treat
  // as opted-in rather than silently dropping every notification for legacy data.
  // Using Number(null) === 0 was the original bug: it blocked all customers whose
  // sms_opt_in was NULL even though they never clicked "opt out".
  if (ticket.customer_id != null) {
    const customer = db
      .prepare('SELECT sms_opt_in, sms_consent_transactional FROM customers WHERE id = ?')
      .get(ticket.customer_id) as AnyRow | undefined;
    const optedOut =
      customer != null &&
      (customer.sms_opt_in === 0 || customer.sms_consent_transactional === 0);
    if (optedOut) {
      logger.info('SMS skipped: customer opted out', {
        customerId: ticket.customer_id,
        ticketId: ctx.ticketId,
        smsOptIn: customer!.sms_opt_in,
        smsConsentTransactional: customer!.sms_consent_transactional,
      });
      return;
    }
  }

  // Check if this status has notify_customer enabled
  const status = db.prepare(
    'SELECT notify_customer, notification_template FROM ticket_statuses WHERE name = ?'
  ).get(ctx.statusName) as AnyRow | undefined;

  if (!status?.notify_customer) return; // Status doesn't trigger customer notification

  // Find matching template via the status's notification_template field
  const templates = db.prepare(
    'SELECT * FROM notification_templates WHERE send_sms_auto = 1'
  ).all() as AnyRow[];

  let template: AnyRow | undefined;
  if (status.notification_template) {
    template = templates.find(t => t.event_key === status.notification_template);
  }

  // Fallback: use a generic status_changed template if no specific one is mapped.
  // The seeded event key (migration 012) is 'status_changed', not 'status_change'.
  if (!template) {
    template = templates.find(t => t.event_key === 'status_changed');
  }

  if (!template || !template.sms_body) return;

  // Get store info for template variables
  const storeConfig = db.prepare("SELECT key, value FROM store_config WHERE key IN ('store_name', 'store_phone')").all() as AnyRow[];
  const configMap: Record<string, string> = {};
  for (const row of storeConfig) configMap[row.key] = row.value;

  // AU3 (rerun §24): Strip control chars from any customer-controlled values
  // before interpolating into the SMS body. This keeps NUL/BEL bytes out of
  // provider payloads and prevents a malformed first_name from bricking a send.
  const smsVars = {
    customer_name: stripSmsControlChars(ticket.customer_name || 'Customer'),
    ticket_id: stripSmsControlChars(ticket.order_id || `T-${ctx.ticketId}`),
    device_name: stripSmsControlChars(ticket.device_name || 'your device'),
    store_name: stripSmsControlChars(configMap.store_name || 'our store'),
    store_phone: stripSmsControlChars(configMap.store_phone || ''),
  };
  const body = (template.sms_body as string)
    .replace(/\{customer_name\}/g, smsVars.customer_name)
    .replace(/\{ticket_id\}/g, smsVars.ticket_id)
    .replace(/\{device_name\}/g, smsVars.device_name)
    .replace(/\{store_name\}/g, smsVars.store_name)
    .replace(/\{store_phone\}/g, smsVars.store_phone);

  // AU7: Warn (don't reject) when the rendered body exceeds one SMS part.
  // Carriers will concatenate into multi-part SMS / MMS automatically, but the
  // shop owner should know they're about to get charged for N segments per send.
  const parts = estimateSmsParts(body);
  if (parts > 1) {
    logger.warn('SMS template will fragment into N parts', {
      templateId: template.id,
      templateEvent: template.event_key,
      length: body.length,
      parts,
      ticketId: ctx.ticketId,
    });
  }

  // ENR-A5: Rate limit auto-SMS — skip if customer received one in the last 4 hours
  if (!isAutoSmsAllowed(db, phone)) {
    logger.info('Auto-SMS rate-limited', {
      phone,
      ticketId: ctx.ticketId,
      ticketOrderId: ticket.order_id,
      cooldownHours: AUTO_SMS_COOLDOWN_HOURS,
    });
    return;
  }

  try {
    await sendSmsTenant(db, ctx.tenantSlug ?? null, phone, body);
    // Store the sent message in sms_messages for thread visibility
    db.prepare(`
      INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, entity_type, entity_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, 'sent', 'outbound', 'auto', 'ticket', ?, datetime('now'), datetime('now'))
    `).run(configMap.store_phone || '', phone, phone.replace(/\D/g, '').replace(/^1/, ''), body, ctx.ticketId);

    logger.info('Auto-SMS sent for ticket status change', {
      phone,
      ticketId: ctx.ticketId,
      ticketOrderId: ticket.order_id,
      statusName: ctx.statusName,
    });
  } catch (err) {
    // L8: never swallow silently. Log structured AND enqueue for retry.
    const errorMessage = err instanceof Error ? err.message : String(err);
    logger.error('Failed to dispatch auto-SMS; enqueuing for retry', {
      phone,
      ticketId: ctx.ticketId,
      ticketOrderId: ticket.order_id,
      statusName: ctx.statusName,
      error: errorMessage,
    });
    enqueueRetry(db, phone, body, 'ticket', ctx.ticketId, ctx.tenantSlug ?? null, errorMessage);
  }

  // Send email if configured and template has send_email_auto enabled
  if (isEmailConfigured(db) && template.send_email_auto && ticket.customer_email) {
    // AU3 (rerun §24): HTML-escape every customer-controlled value before
    // interpolating it into the HTML email body / subject. A customer named
    // `<script>alert(1)</script>` previously flowed straight into the sent
    // mail. The subject gets escaped even though mail clients do not render
    // it as HTML — consistency + defense in depth.
    const htmlVars = {
      customer_name: escapeHtml(ticket.customer_name || 'Customer'),
      ticket_id: escapeHtml(ticket.order_id || ''),
      device_name: escapeHtml(ticket.device_name || 'your device'),
      store_name: escapeHtml(configMap.store_name || 'our store'),
      store_phone: escapeHtml(configMap.store_phone || ''),
    };
    const subject = (template.subject || `Ticket ${ticket.order_id} Update`)
      .replace(/\{customer_name\}/g, htmlVars.customer_name)
      .replace(/\{ticket_id\}/g, htmlVars.ticket_id)
      .replace(/\{device_name\}/g, htmlVars.device_name);

    const emailBody = (template.email_body || body)
      .replace(/\{customer_name\}/g, htmlVars.customer_name)
      .replace(/\{ticket_id\}/g, htmlVars.ticket_id)
      .replace(/\{device_name\}/g, htmlVars.device_name)
      .replace(/\{store_name\}/g, htmlVars.store_name)
      .replace(/\{store_phone\}/g, htmlVars.store_phone);

    // T12: Replace silent `.catch(() => {})` with structured error logging so SMTP
    // failures surface in logs instead of being dropped.
    try {
      const sent = await sendEmail(db, { to: ticket.customer_email, subject, html: emailBody });
      if (!sent) {
        logger.error('Auto email send returned false', {
          ticketId: ctx.ticketId,
          ticketOrderId: ticket.order_id,
          to: ticket.customer_email,
        });
      }
    } catch (err) {
      logger.error('Auto email send threw', {
        ticketId: ctx.ticketId,
        ticketOrderId: ticket.order_id,
        to: ticket.customer_email,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
}
