import { sendEmail } from './email.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('notificationDigest');

type QueueRow = {
  id: number;
  recipient: string;
  subject: string | null;
  body: string;
  retry_count: number;
  max_retries: number;
  created_at: string;
};

type DigestMode = 'immediate' | 'hourly' | 'daily';

function readConfig(db: any, key: string): string | null {
  try {
    const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value?: string } | undefined;
    return row?.value ?? null;
  } catch {
    return null;
  }
}

function upsertConfig(db: any, key: string, value: string): void {
  db.prepare(`
    INSERT INTO store_config (key, value)
    VALUES (?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value
  `).run(key, value);
}

function digestMode(db: any): DigestMode {
  const raw = (readConfig(db, 'notification_digest_mode') || 'immediate').toLowerCase();
  if (raw === 'hourly' || raw === 'daily') return raw;
  return 'immediate';
}

function digestHour(db: any): number {
  const raw = Number(readConfig(db, 'notification_digest_hour') || 9);
  if (!Number.isFinite(raw)) return 9;
  return Math.max(0, Math.min(23, Math.trunc(raw)));
}

function tenantTimezone(db: any): string {
  return readConfig(db, 'store_timezone') || readConfig(db, 'timezone') || 'UTC';
}

function localDateHour(db: any, date = new Date()): { day: string; hour: number; hourStamp: string } {
  const tz = tenantTimezone(db);
  try {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: tz,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      hour12: false,
    })
      .formatToParts(date)
      .reduce<Record<string, string>>((acc, part) => {
        if (part.type !== 'literal') acc[part.type] = part.value;
        return acc;
      }, {});
    const day = `${parts.year}-${parts.month}-${parts.day}`;
    const hour = Math.max(0, Math.min(23, Number(parts.hour || 0)));
    return { day, hour, hourStamp: `${day}T${String(hour).padStart(2, '0')}` };
  } catch {
    const day = date.toISOString().slice(0, 10);
    const hour = date.getUTCHours();
    return { day, hour, hourStamp: `${day}T${String(hour).padStart(2, '0')}` };
  }
}

function sqliteDateTime(date: Date): string {
  return date.toISOString().slice(0, 19).replace('T', ' ');
}

function sqliteCurrentHourCutoff(date: Date): string {
  const cutoff = new Date(date);
  cutoff.setUTCMinutes(0, 0, 0);
  return sqliteDateTime(cutoff);
}

function htmlEscape(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function stripHtml(value: string): string {
  return value
    .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
    .replace(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function buildDigestHtml(recipient: string, items: QueueRow[]): string {
  const rows = items.map((item) => {
    const subject = item.subject || 'Notification';
    const body = stripHtml(item.body).slice(0, 1000);
    return `
      <li style="margin-bottom:16px">
        <p style="margin:0 0 4px;font-weight:600">${htmlEscape(subject)}</p>
        <p style="margin:0;color:#475569">${htmlEscape(body)}</p>
      </li>`;
  }).join('');

  return `
    <div style="font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;line-height:1.5;color:#0f172a">
      <p style="margin:0 0 16px">You have ${items.length} CRM notification${items.length === 1 ? '' : 's'} for ${htmlEscape(recipient)}.</p>
      <ul style="padding-left:20px;margin:0">${rows}</ul>
    </div>`;
}

function shouldRunHourly(db: any, now: Date): boolean {
  return readConfig(db, 'notification_digest_last_hourly_at') !== localDateHour(db, now).hourStamp;
}

function shouldRunDaily(db: any, now: Date): boolean {
  const local = localDateHour(db, now);
  if (local.hour !== digestHour(db)) return false;
  return readConfig(db, 'notification_digest_last_daily_at') !== local.day;
}

function markSent(db: any, ids: number[]): void {
  if (ids.length === 0) return;
  const placeholders = ids.map(() => '?').join(',');
  db.prepare(`
    UPDATE notification_queue
    SET status = 'sent', sent_at = datetime('now'), error = NULL
    WHERE id IN (${placeholders})
  `).run(...ids);
}

function markFailed(db: any, items: QueueRow[], error: string): void {
  const update = db.prepare(`
    UPDATE notification_queue
    SET status = CASE WHEN ? >= max_retries THEN 'failed' ELSE 'pending' END,
        retry_count = ?,
        error = ?,
        scheduled_at = CASE WHEN ? >= max_retries THEN scheduled_at ELSE datetime('now', '+15 minutes') END
    WHERE id = ?
  `);
  for (const item of items) {
    const retryCount = (item.retry_count || 0) + 1;
    update.run(retryCount, retryCount, error, retryCount, item.id);
  }
}

export async function processNotificationDigests(db: any, tenantSlug?: string | null): Promise<void> {
  const mode = digestMode(db);
  if (mode === 'immediate') return;

  const now = new Date();
  const due = mode === 'hourly' ? shouldRunHourly(db, now) : shouldRunDaily(db, now);
  if (!due) return;

  const cutoff = mode === 'hourly'
    ? sqliteCurrentHourCutoff(now)
    : sqliteDateTime(now);

  const rows = db.prepare(`
    SELECT id, recipient, subject, body, retry_count, max_retries, created_at
    FROM notification_queue
    WHERE type = 'email'
      AND status = 'pending'
      AND (scheduled_at IS NULL OR scheduled_at <= datetime('now'))
      AND created_at < ?
    ORDER BY recipient ASC, created_at ASC
    LIMIT 200
  `).all(cutoff) as QueueRow[];

  if (rows.length === 0) {
    const local = localDateHour(db, now);
    upsertConfig(db, mode === 'hourly' ? 'notification_digest_last_hourly_at' : 'notification_digest_last_daily_at', mode === 'hourly' ? local.hourStamp : local.day);
    return;
  }

  const byRecipient = new Map<string, QueueRow[]>();
  for (const row of rows) {
    const list = byRecipient.get(row.recipient) || [];
    list.push(row);
    byRecipient.set(row.recipient, list);
  }

  for (const [recipient, items] of byRecipient) {
    const claimedIds: number[] = [];
    const claim = db.prepare("UPDATE notification_queue SET status = 'processing' WHERE id = ? AND status = 'pending'");
    for (const item of items) {
      const result = claim.run(item.id) as { changes: number };
      if (result.changes === 1) claimedIds.push(item.id);
    }
    if (claimedIds.length === 0) continue;

    const claimed = items.filter((item) => claimedIds.includes(item.id));
    // BUGHUNT-2026-05-17 [CAN-SPAM]: split the "email sent" decision from
    // the "mark sent" DB write so a markSent failure (DB lock, disk full,
    // statement-prepare error) cannot run the catch path and reset the
    // claimed rows to 'pending' — which would cause the next tick to
    // re-send the same digest, duplicating outbound to the customer.
    let sendResult: { ok: boolean; reason: string | null };
    try {
      const sent = await sendEmail(db, {
        to: recipient,
        subject: `CRM notification digest (${claimed.length})`,
        html: buildDigestHtml(recipient, claimed),
      });
      sendResult = sent ? { ok: true, reason: null } : { ok: false, reason: 'Digest email send returned false' };
    } catch (err) {
      sendResult = { ok: false, reason: err instanceof Error ? err.message : String(err) };
    }

    if (sendResult.ok) {
      // Email has been handed to SMTP — past this point we MUST mark sent.
      // A failure to UPDATE means duplicate-send risk on next tick, so log
      // loudly but do NOT throw it into the failure path.
      try {
        markSent(db, claimedIds);
      } catch (markErr) {
        logger.error('digest markSent failed AFTER successful email send — duplicate-send risk', {
          tenantSlug: tenantSlug ?? null,
          recipient,
          claimedIds,
          err: markErr instanceof Error ? markErr.message : String(markErr),
        });
      }
      const atIdx = recipient.lastIndexOf('@');
      logger.info('digest sent', { tenantSlug: tenantSlug ?? null, recipientDomain: atIdx > 0 ? recipient.slice(atIdx + 1) : 'unknown', count: claimed.length, mode });
    } else {
      markFailed(db, claimed, sendResult.reason ?? 'unknown');
    }
  }

  const local = localDateHour(db, now);
  upsertConfig(db, mode === 'hourly' ? 'notification_digest_last_hourly_at' : 'notification_digest_last_daily_at', mode === 'hourly' ? local.hourStamp : local.day);
}

export function shouldSendEmailImmediately(db: any): boolean {
  return digestMode(db) === 'immediate';
}
