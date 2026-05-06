import { WS_EVENTS } from '@bizarre-crm/shared';
import { broadcast } from '../ws/server.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('smsFollowupReminders');

type ReminderRow = {
  id: number;
  conv_phone: string;
  phone: string;
  customer_id: number | null;
  label: string;
  note: string | null;
  due_at: string;
  created_by: number;
  customer_name: string | null;
};

function displayPhone(convPhone: string, phone: string): string {
  if (phone.startsWith('+')) return phone;
  if (convPhone.length === 10) return `(${convPhone.slice(0, 3)}) ${convPhone.slice(3, 6)}-${convPhone.slice(6)}`;
  return phone || convPhone;
}

function reminderMessage(row: ReminderRow): string {
  const who = row.customer_name || displayPhone(row.conv_phone, row.phone);
  const note = row.note ? ` Note: ${row.note}` : '';
  return `Follow up with ${who}: ${row.label}.${note}`;
}

export async function processDueSmsFollowupReminders(db: any, tenantSlug?: string | null): Promise<void> {
  const due = db.prepare(`
    SELECT r.*,
           TRIM(COALESCE(c.first_name, '') || ' ' || COALESCE(c.last_name, '')) AS customer_name
    FROM sms_followup_reminders r
    LEFT JOIN customers c ON c.id = r.customer_id
    WHERE r.status = 'pending'
      AND r.notified_at IS NULL
      AND r.due_at <= datetime('now')
    ORDER BY r.due_at ASC
    LIMIT 50
  `).all() as ReminderRow[];

  if (due.length === 0) return;

  const claim = db.prepare(`
    UPDATE sms_followup_reminders
    SET notified_at = datetime('now'), updated_at = datetime('now')
    WHERE id = ?
      AND status = 'pending'
      AND notified_at IS NULL
      AND due_at <= datetime('now')
  `);
  const insertNotification = db.prepare(`
    INSERT INTO notifications (user_id, type, title, message, entity_type, entity_id, created_at, updated_at)
    VALUES (?, 'sms_followup_reminder', 'SMS follow-up due', ?, 'sms_reminder', ?, datetime('now'), datetime('now'))
  `);

  for (const row of due) {
    const claimed = claim.run(row.id) as { changes: number };
    if (claimed.changes !== 1) continue;

    const result = insertNotification.run(row.created_by, reminderMessage(row), row.id) as { lastInsertRowid: number | bigint };
    const notification = db.prepare('SELECT * FROM notifications WHERE id = ?').get(result.lastInsertRowid);
    broadcast(WS_EVENTS.NOTIFICATION_NEW, { notification }, tenantSlug ?? null);
    logger.info('sms follow-up reminder notified', {
      tenantSlug: tenantSlug ?? null,
      reminderId: row.id,
      userId: row.created_by,
    });
  }
}
