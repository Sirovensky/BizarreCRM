/**
 * Report emailer — Weekly auto-summary + scheduled delivery (audit 47.14/17)
 *
 * Responsibilities:
 *   • Every Monday 08:07 local-to-tenant the default weekly-summary runs.
 *   • Owner-defined cron schedules in `scheduled_email_reports` drive extras.
 *   • Renders plain-text + HTML email for the last 7 days.
 *   • Uses the per-tenant SMTP config via services/email.ts.
 *
 * Wiring:
 *   Import { runReportEmailerTick } from this file into index.ts once, and
 *   call it via trackInterval() so shutdown() can cancel the in-flight tick.
 *   runReportEmailerTick() is idempotent per tenant per week — a `last_sent_at`
 *   guard in sendWeeklySummary() prevents duplicate sends inside the window.
 *
 *   Historical note: this file previously owned its own `setInterval` via
 *   `startReportEmailer()`, which lived OUTSIDE the index.ts interval
 *   registry and therefore leaked through shutdown. The self-managed timer
 *   has been removed — the scheduler now lives in index.ts where every
 *   other cron is tracked.
 */

import { sendEmail, isEmailConfigured } from './email.js';
import { createLogger } from '../utils/logger.js';
import type { AsyncDb } from '../db/async-db.js';

const logger = createLogger('reportEmailer');

// ─── Types ────────────────────────────────────────────────────────────────

interface WeeklyMetrics {
  period_label: string;
  revenue: number;
  tickets_closed: number;
  new_customers: number;
  avg_ticket_value: number;
  top_parts: Array<{ name: string; units: number; revenue: number }>;
  top_techs: Array<{ name: string; closed: number; revenue: number }>;
}

interface ScheduledReportRow {
  id: number;
  name: string;
  recipient_email: string;
  report_type: string;
  cron_schedule: string;
  last_sent_at: string | null;
  is_active: number;
  config_json: string | null;
}

// ─── Metric collection ───────────────────────────────────────────────────

/** Pull the last-7-day metrics snapshot. Read-only — safe to invoke at any time. */
export async function collectWeeklyMetrics(adb: AsyncDb): Promise<WeeklyMetrics> {
  const now = new Date();
  const sevenAgo = new Date(now.getTime() - 7 * 86400_000);
  const fromIso = sevenAgo.toISOString().slice(0, 10);
  const toIso = now.toISOString().slice(0, 10);

  // NOTE: payments.amount, ticket_device_parts.price, and tickets.total are
  // all REAL columns (see criticalaudit.md §M7 "money in floats"). We can't
  // rewrite those migrations from this service, but we CAN round at the
  // boundary so the email never reads "$10.0000000003". Every SUM below
  // rounds to integer cents in SQL, then we divide by 100 on render.
  const [revRow, closedRow, newCustRow, topParts, topTechs] = await Promise.all([
    // RPT-EMAIL1: Weekly revenue must SUM CRM payments + imported invoice
    // amount_paid fallback (for invoices with NO CRM payment row). Matches
    // the dashboard /sales, /profit-hero, and /margin-trends formulas so
    // the weekly email and the dashboard agree. Without this, a shop that
    // imported historical invoices would receive a weekly email claiming
    // revenue=$0 even though the dashboard shows thousands.
    adb.get<{ total_cents: number }>(
      `SELECT COALESCE(
         CAST(ROUND(
           (COALESCE(SUM(p.amount), 0) +
            COALESCE(SUM(CASE WHEN p.id IS NULL AND i.amount_paid > 0 THEN i.amount_paid ELSE 0 END), 0)
           ) * 100
         ) AS INTEGER),
         0) AS total_cents
       FROM invoices i
       LEFT JOIN payments p ON p.invoice_id = i.id
       WHERE i.status != 'void'
         AND DATE(COALESCE(p.created_at, i.created_at)) >= ?`,
      fromIso
    ),
    adb.get<{ n: number }>(
      `SELECT COUNT(*) AS n
       FROM ticket_history th
       JOIN tickets t ON t.id = th.ticket_id
       JOIN ticket_statuses ts ON ts.name = th.new_value
       WHERE DATE(th.created_at) >= ?
         AND th.action = 'status_change'
         AND ts.is_closed = 1
         AND t.is_deleted = 0`,
      fromIso
    ),
    adb.get<{ n: number }>(
      `SELECT COUNT(*) AS n FROM customers WHERE DATE(created_at) >= ?`,
      fromIso
    ),
    adb.all<{ name: string; units: number; revenue_cents: number }>(
      `SELECT ii.name AS name,
              SUM(tdp.quantity) AS units,
              COALESCE(CAST(ROUND(SUM(tdp.quantity * tdp.price) * 100) AS INTEGER), 0) AS revenue_cents
       FROM ticket_device_parts tdp
       JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
       WHERE DATE(tdp.created_at) >= ?
       GROUP BY ii.id
       ORDER BY units DESC
       LIMIT 5`,
      fromIso
    ),
    adb.all<{ name: string; closed: number; revenue_cents: number }>(
      `SELECT COALESCE(u.first_name || ' ' || u.last_name, u.username) AS name,
              COUNT(DISTINCT t.id) AS closed,
              COALESCE(CAST(ROUND(SUM(t.total) * 100) AS INTEGER), 0) AS revenue_cents
       FROM users u
       JOIN tickets t ON t.assigned_to = u.id AND t.is_deleted = 0
       JOIN ticket_statuses ts ON ts.id = t.status_id
       WHERE ts.is_closed = 1 AND DATE(t.updated_at) >= ?
       GROUP BY u.id
       ORDER BY revenue_cents DESC
       LIMIT 5`,
      fromIso
    ),
  ]);

  const revenueCents = Number(revRow?.total_cents ?? 0);
  const closed = Number(closedRow?.n ?? 0);
  // Average computed from integer cents so a $100.00 / 3 split reads as
  // $33.33 instead of leaking 0.00000003 drift into the template.
  const avgTicketCents = closed > 0 ? Math.round(revenueCents / closed) : 0;

  return {
    period_label: `${fromIso} to ${toIso}`,
    revenue: revenueCents / 100,
    tickets_closed: closed,
    new_customers: Number(newCustRow?.n ?? 0),
    avg_ticket_value: avgTicketCents / 100,
    top_parts: topParts.map(p => ({
      name: p.name,
      units: Number(p.units),
      revenue: (Number(p.revenue_cents) || 0) / 100,
    })),
    top_techs: topTechs.map(t => ({
      name: t.name,
      closed: Number(t.closed),
      revenue: (Number(t.revenue_cents) || 0) / 100,
    })),
  };
}

// ─── Rendering ───────────────────────────────────────────────────────────

function fmtUsd(n: number): string {
  return `$${n.toFixed(2)}`;
}

function renderHtml(m: WeeklyMetrics): string {
  const partsRows = m.top_parts.length === 0
    ? '<tr><td colspan="3" style="color:#888;">No parts sold</td></tr>'
    : m.top_parts.map(p =>
        `<tr><td>${escapeHtml(p.name)}</td><td class="num">${p.units}</td><td class="num">${fmtUsd(p.revenue)}</td></tr>`
      ).join('');
  const techRows = m.top_techs.length === 0
    ? '<tr><td colspan="3" style="color:#888;">No closed tickets</td></tr>'
    : m.top_techs.map(t =>
        `<tr><td>${escapeHtml(t.name)}</td><td class="num">${t.closed}</td><td class="num">${fmtUsd(t.revenue)}</td></tr>`
      ).join('');

  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"/><title>Weekly Summary</title>
<style>
  body { font-family: system-ui, sans-serif; color: #111; max-width: 680px; margin: 24px auto; }
  h1 { border-bottom: 2px solid #111; padding-bottom: 8px; }
  .kpi { display: inline-block; width: 48%; padding: 12px; border: 1px solid #ddd; border-radius: 8px; margin: 4px 0; box-sizing: border-box; }
  .kpi .label { font-size: 11px; text-transform: uppercase; color: #666; }
  .kpi .val { font-size: 20px; font-weight: bold; }
  h2 { margin-top: 32px; font-size: 16px; }
  table { width: 100%; border-collapse: collapse; }
  th, td { border: 1px solid #ddd; padding: 6px 10px; text-align: left; }
  th { background: #f5f5f5; font-size: 12px; text-transform: uppercase; }
  .num { text-align: right; font-variant-numeric: tabular-nums; }
  footer { margin-top: 32px; color: #888; font-size: 11px; }
</style></head>
<body>
<h1>Weekly Shop Summary</h1>
<p>${escapeHtml(m.period_label)}</p>

<div>
  <div class="kpi"><div class="label">Revenue</div><div class="val">${fmtUsd(m.revenue)}</div></div>
  <div class="kpi"><div class="label">Tickets Closed</div><div class="val">${m.tickets_closed}</div></div>
  <div class="kpi"><div class="label">New Customers</div><div class="val">${m.new_customers}</div></div>
  <div class="kpi"><div class="label">Avg Ticket</div><div class="val">${fmtUsd(m.avg_ticket_value)}</div></div>
</div>

<h2>Top Parts</h2>
<table>
  <thead><tr><th>Part</th><th class="num">Units</th><th class="num">Revenue</th></tr></thead>
  <tbody>${partsRows}</tbody>
</table>

<h2>Top Technicians</h2>
<table>
  <thead><tr><th>Technician</th><th class="num">Closed</th><th class="num">Revenue</th></tr></thead>
  <tbody>${techRows}</tbody>
</table>

<footer>Sent automatically by BizarreCRM. Manage or unsubscribe in Reports &gt; Scheduled Delivery.</footer>
</body></html>`;
}

function renderText(m: WeeklyMetrics): string {
  const lines = [
    'WEEKLY SHOP SUMMARY',
    m.period_label,
    '',
    `Revenue:        ${fmtUsd(m.revenue)}`,
    `Tickets closed: ${m.tickets_closed}`,
    `New customers:  ${m.new_customers}`,
    `Avg ticket:     ${fmtUsd(m.avg_ticket_value)}`,
    '',
    'TOP PARTS',
    ...(m.top_parts.length === 0 ? ['(none)'] : m.top_parts.map(p => `  ${p.name} — ${p.units}u — ${fmtUsd(p.revenue)}`)),
    '',
    'TOP TECHNICIANS',
    ...(m.top_techs.length === 0 ? ['(none)'] : m.top_techs.map(t => `  ${t.name} — ${t.closed} closed — ${fmtUsd(t.revenue)}`)),
    '',
    '-- BizarreCRM',
  ];
  return lines.join('\n');
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ─── Sending ─────────────────────────────────────────────────────────────

export interface DeliveryTargets {
  db: any;                 // better-sqlite3 sync DB (for email.ts + UPDATE)
  adb: AsyncDb;            // async DB for the metric query
  recipients: string[];    // fallback owner inbox if no scheduled rows exist
  /** Tenant store_config.timezone — controls "is it Mon 08:07?" decisions. */
  timezone?: string;
  /** Tenant slug (or null for single-tenant). Used only for logging. */
  tenantSlug?: string | null;
}

export interface WeeklySummaryOutcome {
  /** Was the SMTP transporter configured at all? False = nothing happened. */
  readonly smtpConfigured: boolean;
  /** Total number of distinct recipients we attempted. */
  readonly attempted: number;
  /** Number of successful sendMail() calls. */
  readonly sent: number;
  /** Number of failed sendMail() calls (transport error, refused, etc.). */
  readonly failed: number;
}

/**
 * How long we wait between successful weekly-summary sends for a given tenant.
 * 6 days is deliberately shorter than the nominal 7-day cadence so operators
 * can recover from a one-off clock skew without waiting a whole extra week,
 * but long enough that a sluggish tick (two fires inside the same Monday
 * 08:07) is blocked from double-sending. This is the primary defense against
 * duplicate emails — the minute-window check is defense-in-depth only.
 */
const WEEKLY_SUMMARY_MIN_GAP_MS = 6 * 24 * 60 * 60 * 1000;

function nowMs(): number {
  return Date.now();
}

/**
 * Check the store_config sentinel row that says "the weekly summary already
 * fired recently". Returns true if we're still inside the minimum gap.
 */
function weeklySummaryRecentlySent(db: any): boolean {
  try {
    const row = db
      .prepare("SELECT value FROM store_config WHERE key = 'weekly_summary_last_sent_at'")
      .get() as { value?: string } | undefined;
    if (!row?.value) return false;
    const prev = Number.parseInt(row.value, 10);
    if (!Number.isFinite(prev)) return false;
    return nowMs() - prev < WEEKLY_SUMMARY_MIN_GAP_MS;
  } catch {
    // If store_config is missing (e.g. fresh tenant mid-migration), treat
    // as "never sent" rather than crashing the cron tick.
    return false;
  }
}

function stampWeeklySummarySent(db: any): void {
  try {
    db.prepare(
      `INSERT INTO store_config (key, value)
       VALUES ('weekly_summary_last_sent_at', ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
    ).run(String(nowMs()));
  } catch (err) {
    logger.warn('could not stamp weekly_summary_last_sent_at', {
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * Send the weekly summary.
 *
 * Previously this updated `last_sent_at` on every scheduled row even if a
 * particular recipient's sendEmail() returned false — so operators could
 * never tell which scheduled row actually delivered. Now we only tick
 * last_sent_at when that specific row's send succeeded, and we return a
 * structured outcome so the caller can decide what to do next.
 *
 * Idempotency: a tenant-scoped `weekly_summary_last_sent_at` sentinel in
 * store_config is checked BEFORE any SMTP work happens. If the sentinel
 * is within the 6-day minimum gap, the call is a no-op. This prevents a
 * clock-jitter double-fire from duplicating every recipient's inbox.
 */
export async function sendWeeklySummary(targets: DeliveryTargets): Promise<WeeklySummaryOutcome> {
  const { db, adb, recipients } = targets;

  if (!isEmailConfigured(db)) {
    logger.warn('SMTP not configured; skipping weekly summary', {
      tenantSlug: targets.tenantSlug ?? null,
    });
    return { smtpConfigured: false, attempted: 0, sent: 0, failed: 0 };
  }

  // Idempotency guard: if we already fired inside the minimum gap, bail.
  if (weeklySummaryRecentlySent(db)) {
    logger.info('weekly summary suppressed (idempotency guard)', {
      tenantSlug: targets.tenantSlug ?? null,
    });
    return { smtpConfigured: true, attempted: 0, sent: 0, failed: 0 };
  }

  const metrics = await collectWeeklyMetrics(adb);
  const html = renderHtml(metrics);
  const text = renderText(metrics);
  const subject = `Weekly summary — ${metrics.period_label}`;

  // Look up all active scheduled weekly_summary rows + ad-hoc recipients
  const scheduled = await adb.all<ScheduledReportRow>(
    `SELECT * FROM scheduled_email_reports
     WHERE is_active = 1 AND report_type = 'weekly_summary'`
  );

  // Track outcome per recipient so we only mark scheduled rows as "sent" when
  // the specific email delivery actually succeeded. Ad-hoc recipients don't
  // have a row to tick, so we just count them toward the aggregate.
  const resultsByEmail = new Map<string, boolean>();
  const adhoc = recipients.filter(Boolean);
  const allEmails = new Set<string>(adhoc);
  for (const row of scheduled) allEmails.add(row.recipient_email);

  let sent = 0;
  let failed = 0;
  for (const to of allEmails) {
    try {
      const ok = await sendEmail(db, { to, subject, html, text });
      resultsByEmail.set(to, ok);
      if (ok) sent += 1;
      else failed += 1;
    } catch (err) {
      resultsByEmail.set(to, false);
      failed += 1;
      logger.error('weekly summary sendEmail threw', {
        to,
        err: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // Only update last_sent_at for rows whose recipient actually received.
  const nowIso = new Date().toISOString();
  for (const row of scheduled) {
    if (resultsByEmail.get(row.recipient_email) === true) {
      await adb.run(
        `UPDATE scheduled_email_reports SET last_sent_at = ? WHERE id = ?`,
        nowIso, row.id
      );
    }
  }

  // Stamp the idempotency sentinel ONLY when we actually shipped at least
  // one message successfully — a run that fails 100% should be retried
  // on the next Monday tick, not silenced for 6 days.
  if (sent > 0) {
    stampWeeklySummarySent(db);
  }

  logger.info('weekly summary dispatched', {
    tenantSlug: targets.tenantSlug ?? null,
    attempted: allEmails.size,
    sent,
    failed,
  });
  return { smtpConfigured: true, attempted: allEmails.size, sent, failed };
}

// ─── Scheduler ──────────────────────────────────────────────────────────

/**
 * Return `{ weekday, hour, minute }` in the given IANA timezone. Uses
 * `Intl.DateTimeFormat` with `en-US` because that locale is guaranteed to
 * return the English weekday name we parse below — changing locale would
 * silently break the `day === 'Mon'` comparison.
 *
 * Weekday is a short English name: 'Sun' | 'Mon' | 'Tue' | 'Wed' | 'Thu' |
 * 'Fri' | 'Sat'. Hour is 0-23. Minute is 0-59.
 */
export function localTimeParts(
  now: Date,
  timeZone: string,
): { weekday: string; hour: number; minute: number } {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone,
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
  const parts = fmt.formatToParts(now);
  const weekday = parts.find((p) => p.type === 'weekday')?.value ?? '';
  const hour = Number.parseInt(parts.find((p) => p.type === 'hour')?.value ?? '0', 10);
  const minute = Number.parseInt(parts.find((p) => p.type === 'minute')?.value ?? '0', 10);
  return { weekday, hour, minute: Number.isFinite(minute) ? minute : 0 };
}

/**
 * Is `now` within the Monday-morning fire window for the given timezone?
 * The window is Monday 08:00-08:14 local — 15 minutes wide so a tick that
 * drifts a few minutes still catches it. Combined with the DB-backed
 * idempotency guard in sendWeeklySummary(), a tenant can receive AT MOST
 * one email per 6-day window even if this function returns true multiple
 * times in a row.
 */
export function isWeeklySummaryFireWindow(now: Date, timeZone: string): boolean {
  const { weekday, hour, minute } = localTimeParts(now, timeZone);
  if (weekday !== 'Mon') return false;
  if (hour !== 8) return false;
  return minute >= 0 && minute < 15;
}

/**
 * Single-tick entry point for the weekly summary. Intended to be called by
 * `trackInterval()` in index.ts at a 5-minute cadence. Per tenant, this:
 *   1. Checks the local Mon 08:00-08:14 window in the tenant's own timezone.
 *   2. Skips if outside the window.
 *   3. Calls sendWeeklySummary(), which double-guards with a DB sentinel.
 *
 * Per-tenant failures are caught + logged so one bad tenant cannot kill the
 * whole fleet's weekly summary run.
 */
export async function runReportEmailerTick(
  getTargets: () => Promise<DeliveryTargets[]>,
): Promise<void> {
  let targets: DeliveryTargets[];
  try {
    targets = await getTargets();
  } catch (err) {
    logger.error('report emailer: getTargets failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    return;
  }

  const now = new Date();
  for (const t of targets) {
    const tz = t.timezone || 'UTC';
    try {
      if (!isWeeklySummaryFireWindow(now, tz)) continue;

      const outcome = await sendWeeklySummary(t);
      if (!outcome.smtpConfigured) {
        logger.error('weekly summary: SMTP not configured for tenant', {
          tenantSlug: t.tenantSlug ?? null,
          timezone: tz,
          attempted: outcome.attempted,
          sent: outcome.sent,
          failed: outcome.failed,
        });
      } else if (outcome.failed > 0 && outcome.sent === 0) {
        logger.error('weekly summary: all recipients failed for tenant', {
          tenantSlug: t.tenantSlug ?? null,
          timezone: tz,
          attempted: outcome.attempted,
          failed: outcome.failed,
        });
      } else if (outcome.sent > 0) {
        logger.info('weekly summary: tenant run succeeded', {
          tenantSlug: t.tenantSlug ?? null,
          timezone: tz,
          sent: outcome.sent,
          failed: outcome.failed,
        });
      }
    } catch (err) {
      // SEC-BG: one bad tenant MUST NOT kill the loop. Log and continue.
      logger.error('weekly summary: per-tenant tick failed', {
        tenantSlug: t.tenantSlug ?? null,
        timezone: tz,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
}
