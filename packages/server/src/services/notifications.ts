import { db } from '../db/connection.js';
import { sendSms } from './smsProvider.js';
import { sendEmail, isEmailConfigured } from './email.js';

type AnyRow = Record<string, any>;

interface NotifyContext {
  ticketId: number;
  statusName?: string;
}

/**
 * Send auto-notifications (SMS/email) when a ticket status changes.
 * Looks up the notification template matching the status, substitutes variables, and sends.
 */
export async function sendTicketStatusNotification(ctx: NotifyContext): Promise<void> {
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

  try {
    await sendSms(phone, body);
    // Store the sent message in sms_messages for thread visibility
    db.prepare(`
      INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, entity_type, entity_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, 'sent', 'outbound', 'auto', 'ticket', ?, datetime('now'), datetime('now'))
    `).run(configMap.store_phone || '', phone, phone.replace(/\D/g, '').replace(/^1/, ''), body, ctx.ticketId);

    console.log(`[Notification] Sent SMS to ${phone} for ticket ${ticket.order_id} — status: ${ctx.statusName}`);
  } catch (err) {
    console.error(`[Notification] Failed to send SMS to ${phone}:`, err);
  }

  // Send email if configured and template has send_email_auto enabled
  if (isEmailConfigured() && template.send_email_auto && ticket.customer_email) {
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

    await sendEmail({ to: ticket.customer_email, subject, html: emailBody }).catch(() => {});
  }
}
