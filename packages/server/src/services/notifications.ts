import { sendSmsTenant } from './smsProvider.js';
import { sendEmail, isEmailConfigured } from './email.js';

type AnyRow = Record<string, any>;

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
    console.error('[NotificationRetry] Failed to enqueue retry:', err);
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
      console.log(`[NotificationRetry] Succeeded on retry #${item.retry_count + 1} for ${item.recipient_phone}`);
    } catch (err) {
      const newRetryCount = item.retry_count + 1;
      if (newRetryCount >= item.max_retries) {
        // Max retries exceeded — remove and log
        db.prepare('DELETE FROM notification_retry_queue WHERE id = ?').run(item.id);
        console.error(`[NotificationRetry] Permanently failed after ${newRetryCount} retries for ${item.recipient_phone}: ${(err as Error).message}`);
      } else {
        // Exponential backoff: 5^(retryCount+1) minutes
        const backoffMinutes = Math.pow(5, newRetryCount);
        db.prepare(`
          UPDATE notification_retry_queue
          SET retry_count = ?, next_retry_at = datetime('now', '+' || ? || ' minutes'), last_error = ?
          WHERE id = ?
        `).run(newRetryCount, backoffMinutes, (err as Error).message, item.id);
        console.log(`[NotificationRetry] Retry #${newRetryCount} failed for ${item.recipient_phone}, next in ${backoffMinutes}m`);
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
    SELECT t.id, t.order_id,
      c.first_name AS customer_name, c.mobile AS customer_phone, c.phone AS customer_phone2, c.email AS customer_email,
      (SELECT td.device_name FROM ticket_devices td WHERE td.ticket_id = t.id ORDER BY td.id ASC LIMIT 1) AS device_name
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    WHERE t.id = ?
  `).get(ctx.ticketId) as AnyRow | undefined;

  if (!ticket) return;

  const phone = ticket.customer_phone || ticket.customer_phone2;
  if (!phone) return; // No phone to send to

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
  const body = template.sms_body
    .replace(/\{customer_name\}/g, ticket.customer_name || 'Customer')
    .replace(/\{ticket_id\}/g, ticket.order_id || `T-${ctx.ticketId}`)
    .replace(/\{device_name\}/g, ticket.device_name || 'your device')
    .replace(/\{store_name\}/g, configMap.store_name || 'our store')
    .replace(/\{store_phone\}/g, configMap.store_phone || '');

  // ENR-A5: Rate limit auto-SMS — skip if customer received one in the last 4 hours
  if (!isAutoSmsAllowed(db, phone)) {
    console.log(`[Notification] Rate-limited: skipping SMS to ${phone} for ticket ${ticket.order_id} (auto-SMS sent within ${AUTO_SMS_COOLDOWN_HOURS}h)`);
    return;
  }

  try {
    await sendSmsTenant(db, ctx.tenantSlug ?? null, phone, body);
    // Store the sent message in sms_messages for thread visibility
    db.prepare(`
      INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, entity_type, entity_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, 'sent', 'outbound', 'auto', 'ticket', ?, datetime('now'), datetime('now'))
    `).run(configMap.store_phone || '', phone, phone.replace(/\D/g, '').replace(/^1/, ''), body, ctx.ticketId);

    console.log(`[Notification] Sent SMS to ${phone} for ticket ${ticket.order_id} — status: ${ctx.statusName}`);
  } catch (err) {
    console.error(`[Notification] Failed to send SMS to ${phone}:`, err);
    // ENR-A4: Queue for retry instead of silently dropping
    enqueueRetry(db, phone, body, 'ticket', ctx.ticketId, ctx.tenantSlug ?? null, (err as Error).message);
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

    await sendEmail(db, { to: ticket.customer_email, subject, html: emailBody }).catch(() => {});
  }
}
