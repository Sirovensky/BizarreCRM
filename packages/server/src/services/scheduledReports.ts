/**
 * Scheduled report email service.
 * Generates a daily summary and emails it to configured recipients.
 * Only runs if SMTP is configured and scheduled_report_email setting is set.
 */

import { sendEmail, isEmailConfigured } from './email.js';
import { createLogger } from '../utils/logger.js';

const log = createLogger('scheduled-reports');

const DEFAULT_TIMEZONE = 'America/Denver';

interface DailySummary {
  date: string;
  tickets_created: number;
  tickets_closed: number;
  revenue: number;
  new_customers: number;
  open_tickets: number;
  overdue_invoices: number;
  low_stock_items: number;
}

/**
 * Read the tenant's configured timezone from `store_config` (key: `store_timezone`).
 * Falls back to `America/Denver` when unset or on lookup failure.
 * TZ3/TZ6 fix: used to compute "today" and "yesterday" in tenant-local time rather
 * than UTC, so positive-offset tenants don't see invoices/reports off by a day.
 */
function getTenantTimezone(db: any): string {
  try {
    const row = db
      .prepare("SELECT value FROM store_config WHERE key = 'store_timezone'")
      .get() as { value?: string } | undefined;
    const tz = row?.value;
    return tz && tz.trim() ? tz : DEFAULT_TIMEZONE;
  } catch (err) {
    log.warn('Failed to read store_timezone, falling back to default', {
      error: String(err),
      default: DEFAULT_TIMEZONE,
    });
    return DEFAULT_TIMEZONE;
  }
}

/**
 * Return the current date in the given IANA timezone, formatted as `YYYY-MM-DD`.
 * Uses `Intl.DateTimeFormat` (no luxon dependency) so day extraction is correct
 * regardless of the host OS timezone.
 */
function getLocalTodayIsoDate(tz: string): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })
    .formatToParts(new Date())
    .reduce<Record<string, string>>((acc, p) => {
      if (p.type !== 'literal') acc[p.type] = p.value;
      return acc;
    }, {});
  return `${parts.year}-${parts.month}-${parts.day}`;
}

/**
 * Return "yesterday" in the given IANA timezone, formatted as `YYYY-MM-DD`.
 * TZ6 fix: previously used `Date.now() - 86400_000` which is UTC-based and
 * included today's data for tenants ahead of UTC.
 */
function getLocalYesterdayIsoDate(tz: string): string {
  const todayStr = getLocalTodayIsoDate(tz);
  // Anchor today's date at UTC midnight, then subtract one UTC day. Since we
  // only care about the Y-M-D result (not the instant), UTC arithmetic is safe.
  const anchor = new Date(`${todayStr}T00:00:00Z`);
  anchor.setUTCDate(anchor.getUTCDate() - 1);
  return anchor.toISOString().slice(0, 10);
}

function generateSummary(db: any): DailySummary {
  const tz = getTenantTimezone(db);
  // TZ6 fix: compute yesterday in tenant-local time, not UTC.
  const yesterday = getLocalYesterdayIsoDate(tz);
  // TZ3 fix: compute today in tenant-local time so overdue comparisons use a
  // tenant-local `YYYY-MM-DD` boundary instead of SQLite's UTC `DATE('now')`.
  const todayLocal = getLocalTodayIsoDate(tz);

  const ticketsCreated = (db.prepare(`
    SELECT COUNT(*) AS n FROM tickets WHERE is_deleted = 0 AND DATE(created_at) = ?
  `).get(yesterday) as any).n;

  // @audit-fixed: previously this query joined `ticket_statuses ts ON ts.name = th.new_value`,
  // which silently returned 0 when statuses were renamed (e.g. "Completed" → "Done")
  // because old history rows still carried the old name. Two issues:
  //   1. Renaming a status retroactively zeros out historical "tickets closed" counts.
  //   2. The action filter `'status_change'` is one possible action name; other code paths
  //      log status transitions with different action labels.
  // Switch to a `LIKE`-based status-name compare against ALL statuses currently flagged
  // is_closed = 1, so as long as the human-readable name in history matches a current
  // closed status (case-insensitive trim), the row is counted. Still imperfect — the
  // proper fix is to add a `new_status_id` column to ticket_history — but this query
  // no longer silently undercounts after a rename.
  const ticketsClosed = (db.prepare(`
    SELECT COUNT(*) AS n FROM ticket_history th
    JOIN tickets t ON t.id = th.ticket_id
    WHERE th.action IN ('status_change', 'status_changed', 'status')
      AND LOWER(TRIM(th.new_value)) IN (
        SELECT LOWER(TRIM(name)) FROM ticket_statuses WHERE is_closed = 1
      )
      AND t.is_deleted = 0 AND DATE(th.created_at) = ?
  `).get(yesterday) as any).n;

  // @audit-fixed: revenue query previously aggregated against the local SQLite
  // server-time `DATE(created_at)`, which is UTC. For positive-offset tenants
  // (e.g. Pacific shops on UTC-8) that means a sale entered at 4pm local on
  // April 11 lands in the April 12 UTC bucket and falls out of the April 11
  // tenant-local report. We can't use Intl here because SQLite knows nothing
  // about IANA tz, so we approximate by passing tenant-local yesterday string
  // and trusting `created_at` is recorded in tenant-local time at write time.
  // The issue is documented in TZ3/TZ6 in the file header. Defensive coalesce
  // remains so a null-only payment table doesn't NPE the property access below.
  const revenueRow = db.prepare(`
    SELECT COALESCE(SUM(amount), 0) AS v FROM payments WHERE DATE(created_at) = ?
  `).get(yesterday) as { v: number | null } | undefined;
  const revenue = revenueRow?.v ?? 0;

  const newCustomers = (db.prepare(`
    SELECT COUNT(*) AS n FROM customers WHERE is_deleted = 0 AND DATE(created_at) = ?
  `).get(yesterday) as any).n;

  const openTickets = (db.prepare(`
    SELECT COUNT(*) AS n FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
  `).get() as any).n;

  const overdueInvoices = (db.prepare(`
    SELECT COUNT(*) AS n FROM invoices
    WHERE status IN ('unpaid', 'partial') AND due_on IS NOT NULL AND due_on != '' AND DATE(due_on) < ?
  `).get(todayLocal) as any).n;

  const lowStockItems = (db.prepare(`
    SELECT COUNT(*) AS n FROM inventory_items
    WHERE item_type != 'service' AND is_active = 1 AND in_stock <= reorder_level
  `).get() as any).n;

  return {
    date: yesterday,
    tickets_created: ticketsCreated,
    tickets_closed: ticketsClosed,
    revenue,
    new_customers: newCustomers,
    open_tickets: openTickets,
    overdue_invoices: overdueInvoices,
    low_stock_items: lowStockItems,
  };
}

// SW-D16: Use store_currency from DB when available
function formatCurrency(amount: number, currency: string = 'USD'): string {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(amount);
}

function buildEmailBody(summary: DailySummary, currency: string = 'USD'): string {
  return `
<h2>Daily Summary for ${summary.date}</h2>

<table style="border-collapse:collapse; width:100%; max-width:500px;">
  <tr style="border-bottom:1px solid #eee;">
    <td style="padding:8px 12px; font-weight:bold;">Tickets Created</td>
    <td style="padding:8px 12px; text-align:right;">${summary.tickets_created}</td>
  </tr>
  <tr style="border-bottom:1px solid #eee;">
    <td style="padding:8px 12px; font-weight:bold;">Tickets Closed</td>
    <td style="padding:8px 12px; text-align:right;">${summary.tickets_closed}</td>
  </tr>
  <tr style="border-bottom:1px solid #eee;">
    <td style="padding:8px 12px; font-weight:bold;">Revenue</td>
    <td style="padding:8px 12px; text-align:right;">${formatCurrency(summary.revenue, currency)}</td>
  </tr>
  <tr style="border-bottom:1px solid #eee;">
    <td style="padding:8px 12px; font-weight:bold;">New Customers</td>
    <td style="padding:8px 12px; text-align:right;">${summary.new_customers}</td>
  </tr>
</table>

<h3 style="margin-top:20px;">Current Status</h3>
<ul>
  <li><strong>${summary.open_tickets}</strong> open tickets</li>
  ${summary.overdue_invoices > 0 ? `<li style="color:#dc2626;"><strong>${summary.overdue_invoices}</strong> overdue invoices</li>` : ''}
  ${summary.low_stock_items > 0 ? `<li style="color:#d97706;"><strong>${summary.low_stock_items}</strong> items low on stock</li>` : ''}
</ul>

<p style="color:#6b7280; font-size:12px; margin-top:20px;">
  This is an automated report from BizarreCRM.
</p>
  `.trim();
}

/**
 * Resolve the list of enabled recipient addresses for the daily report.
 *
 * SEC-M47: Migration 105 introduced `scheduled_report_recipients` so
 * operators can manage multiple addresses via the UI. This function reads
 * that table first. If the table doesn't exist yet (pre-migration tenant)
 * it falls back to the legacy `store_config.scheduled_report_email` single-
 * address string so existing deployments keep working without manual action.
 */
function isValidEmail(s: string): boolean {
  return typeof s === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s) && s.length <= 320;
}

function resolveRecipients(db: any): string[] {
  try {
    const tableExists = db
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='scheduled_report_recipients'")
      .get() as { name?: string } | undefined;
    if (tableExists?.name) {
      const rows = db
        .prepare("SELECT email FROM scheduled_report_recipients WHERE enabled = 1")
        .all() as Array<{ email: string }>;
      if (rows.length > 0) {
        const valid = rows
          .map((r) => String(r.email).trim())
          .filter(isValidEmail);
        const dropped = rows.length - valid.length;
        if (dropped > 0) {
          log.warn('resolveRecipients: dropped invalid email addresses', { dropped });
        }
        return valid;
      }
      // Table exists but no enabled recipients — fall through to legacy key
      // so an operator who cleared the table but still has the old config key
      // doesn't silently stop receiving reports.
    }
  } catch (err) {
    log.warn('Failed to read scheduled_report_recipients, falling back to legacy key', {
      error: String(err),
    });
  }

  const legacy = (db.prepare(
    "SELECT value FROM store_config WHERE key = 'scheduled_report_email'"
  ).get() as any)?.value as string | undefined;
  if (!legacy) return [];
  const trimmed = String(legacy).trim();
  if (!isValidEmail(trimmed)) {
    log.warn('resolveRecipients: legacy scheduled_report_email is invalid', { value: trimmed });
    return [];
  }
  return [trimmed];
}

export async function sendDailyReport(db: any): Promise<void> {
  const recipients = resolveRecipients(db);

  if (recipients.length === 0) {
    log.debug('Scheduled report email not configured, skipping');
    return;
  }

  // SCAN-625: use shared isEmailConfigured() instead of an inline smtp_host
  // lookup so this early-return stays in sync with all other email-send paths.
  if (!isEmailConfigured(db)) {
    log.debug('SMTP not configured, skipping scheduled report');
    return;
  }

  try {
    const summary = generateSummary(db);
    const storeName = (db.prepare(
      "SELECT value FROM store_config WHERE key = 'store_name'"
    ).get() as any)?.value || 'My Shop';

    // SW-D16: Use store_currency for report formatting
    const storeCurrency = (db.prepare(
      "SELECT value FROM store_config WHERE key = 'store_currency'"
    ).get() as any)?.value || 'USD';

    const subject = `${storeName} Daily Report - ${summary.date}`;
    const html = buildEmailBody(summary, storeCurrency);

    for (const to of recipients) {
      try {
        await sendEmail(db, { to, subject, html });
        log.info('Daily report sent', { to, date: summary.date });
      } catch (err) {
        log.error('Failed to send daily report to recipient', { to, error: String(err) });
      }
    }
  } catch (err) {
    log.error('Failed to send daily report', { error: String(err) });
  }
}
