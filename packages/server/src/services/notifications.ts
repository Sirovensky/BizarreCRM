import { sendSmsTenant } from './smsProvider.js';
import { sendEmail, isEmailConfigured } from './email.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('notifications');

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
export function enqueueRetry(
  db: any,
  phone: string,
  message: string,
  entityType: string | null,
  entityId: number | null,
  tenantSlug: string | null,
  errorMsg: string,
): void {
  try {
    db.prepare(`
      INSERT INTO notification_retry_queue (recipient_phone, message, entity_type, entity_id, tenant_slug, retry_count, max_retries, next_retry_at, last_error)
      VALUES (?, ?, ?, ?, ?, 0, 3, datetime('now', '+5 minutes'), ?)
    `).run(phone, message, entityType, entityId, tenantSlug, errorMsg);
  } catch (err) {
    logger.error('Failed to enqueue retry', {
      phone,
      entityType,
      entityId,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * Process the retry queue: attempt to resend failed notifications.
 * Called periodically from the cron in index.ts.
 */
export async function processRetryQueue(db: any, tenantSlug: string | null): Promise<void> {
  const pending = db.prepare(`
    SELECT * FROM notification_retry_queue
    WHERE retry_count < max_retries AND next_retry_at <= datetime('now')
    ORDER BY next_retry_at ASC LIMIT 10
  `).all() as AnyRow[];

  if (pending.length === 0) return;

  for (const item of pending) {
    try {
      await sendSmsTenant(db, tenantSlug, item.recipient_phone, item.message);
      // Success — remove from retry queue
      db.prepare('DELETE FROM notification_retry_queue WHERE id = ?').run(item.id);
      logger.info('Retry succeeded', {
        retryAttempt: item.retry_count + 1,
        phone: item.recipient_phone,
      });
    } catch (err) {
      const newRetryCount = item.retry_count + 1;
      const errorMessage = err instanceof Error ? err.message : String(err);
      if (newRetryCount >= item.max_retries) {
        // Max retries exceeded — remove and log
        db.prepare('DELETE FROM notification_retry_queue WHERE id = ?').run(item.id);
        logger.error('Retry permanently failed', {
          retryCount: newRetryCount,
          phone: item.recipient_phone,
          error: errorMessage,
        });
      } else {
        // Exponential backoff: 5^(retryCount+1) minutes
        const backoffMinutes = Math.pow(5, newRetryCount);
        db.prepare(`
          UPDATE notification_retry_queue
          SET retry_count = ?, next_retry_at = datetime('now', '+' || ? || ' minutes'), last_error = ?
          WHERE id = ?
        `).run(newRetryCount, backoffMinutes, errorMessage, item.id);
        logger.warn('Retry failed, scheduled next attempt', {
          retryCount: newRetryCount,
          phone: item.recipient_phone,
          nextInMinutes: backoffMinutes,
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
 * Check if a customer (by phone) has received an auto-SMS recently.
 * Returns true if sending is allowed (no recent auto-SMS), false if rate-limited.
 */
export function isAutoSmsAllowed(db: any, phone: string): boolean {
  if (!phone) return false;
  const convPhone = phone.replace(/\D/g, '').replace(/^1/, '');
  const recent = db.prepare(`
    SELECT id FROM sms_messages
    WHERE conv_phone = ?
      AND provider = 'auto'
      AND direction = 'outbound'
      AND created_at > datetime('now', ? || ' hours')
    LIMIT 1
  `).get(convPhone, `-${AUTO_SMS_COOLDOWN_HOURS}`) as any;

  return !recent;
}

/**
 * Send auto-notifications (SMS/email) when a ticket status changes.
 * Looks up the notification template matching the status, substitutes variables, and sends.
 */
export async function sendTicketStatusNotification(db: any, ctx: NotifyContext): Promise<void> {
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
  //   sms_opt_in (migration 001)              → global customer opt-in
  //   sms_consent_transactional (migration 063) → per-channel consent for transactional SMS
  // Both must be truthy for us to auto-send a status update.
  if (ticket.customer_id != null) {
    const customer = db
      .prepare('SELECT sms_opt_in, sms_consent_transactional FROM customers WHERE id = ?')
      .get(ticket.customer_id) as AnyRow | undefined;
    if (customer && (Number(customer.sms_opt_in) === 0 || Number(customer.sms_consent_transactional) === 0)) {
      logger.info('SMS skipped: customer opted out', {
        customerId: ticket.customer_id,
        ticketId: ctx.ticketId,
        smsOptIn: customer.sms_opt_in,
        smsConsentTransactional: customer.sms_consent_transactional,
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

  // Fallback: use a generic status_change template if no specific one is mapped
  if (!template) {
    template = templates.find(t => t.event_key === 'status_change');
  }

  if (!template || !template.sms_body) return;

  // Get store info for template variables
  const storeConfig = db.prepare("SELECT key, value FROM store_config WHERE key IN ('store_name', 'store_phone')").all() as AnyRow[];
  const configMap: Record<string, string> = {};
  for (const row of storeConfig) configMap[row.key] = row.value;

  // Substitute variables
  const body = (template.sms_body as string)
    .replace(/\{customer_name\}/g, ticket.customer_name || 'Customer')
    .replace(/\{ticket_id\}/g, ticket.order_id || `T-${ctx.ticketId}`)
    .replace(/\{device_name\}/g, ticket.device_name || 'your device')
    .replace(/\{store_name\}/g, configMap.store_name || 'our store')
    .replace(/\{store_phone\}/g, configMap.store_phone || '');

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
    const subject = (template.subject || `Ticket ${ticket.order_id} Update`)
      .replace(/\{customer_name\}/g, ticket.customer_name || 'Customer')
      .replace(/\{ticket_id\}/g, ticket.order_id || '')
      .replace(/\{device_name\}/g, ticket.device_name || 'your device');

    const emailBody = (template.email_body || body)
      .replace(/\{customer_name\}/g, ticket.customer_name || 'Customer')
      .replace(/\{ticket_id\}/g, ticket.order_id || '')
      .replace(/\{device_name\}/g, ticket.device_name || 'your device')
      .replace(/\{store_name\}/g, configMap.store_name || 'our store')
      .replace(/\{store_phone\}/g, configMap.store_phone || '');

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
