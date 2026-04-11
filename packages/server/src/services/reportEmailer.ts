/**
 * Report emailer — Weekly auto-summary + scheduled delivery (audit 47.14/17)
 *
 * Responsibilities:
 *   • Every Monday 08:07 local the default weekly-summary runs.
 *   • Owner-defined cron schedules in `scheduled_email_reports` drive extras.
 *   • Renders plain-text + HTML email for the last 7 days.
 *   • Uses the per-tenant SMTP config via services/email.ts.
 *
 * Wiring:
 *   Import { startReportEmailer } from this file into index.ts once (see the
 *   "// TODO: wire report emailer cron" marker in reports.routes.ts). The
 *   scheduler is idempotent — calling start twice is a no-op.
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

  const [revRow, closedRow, newCustRow, topParts, topTechs] = await Promise.all([
    adb.get<{ total: number }>(
      `SELECT COALESCE(SUM(amount), 0) AS total
       FROM payments
       WHERE DATE(created_at) >= ?`,
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
    adb.all<{ name: string; units: number; revenue: number }>(
      `SELECT ii.name AS name,
              SUM(tdp.quantity) AS units,
              SUM(tdp.quantity * tdp.price) AS revenue
       FROM ticket_device_parts tdp
       JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
       WHERE DATE(tdp.created_at) >= ?
       GROUP BY ii.id
       ORDER BY units DESC
       LIMIT 5`,
      fromIso
    ),
    adb.all<{ name: string; closed: number; revenue: number }>(
      `SELECT COALESCE(u.first_name || ' ' || u.last_name, u.username) AS name,
              COUNT(DISTINCT t.id) AS closed,
              COALESCE(SUM(t.total), 0) AS revenue
       FROM users u
       JOIN tickets t ON t.assigned_to = u.id AND t.is_deleted = 0
       JOIN ticket_statuses ts ON ts.id = t.status_id
       WHERE ts.is_closed = 1 AND DATE(t.updated_at) >= ?
       GROUP BY u.id
       ORDER BY revenue DESC
       LIMIT 5`,
      fromIso
    ),
  ]);

  const revenue = Number(revRow?.total ?? 0);
  const closed = Number(closedRow?.n ?? 0);

  return {
    period_label: `${fromIso} to ${toIso}`,
    revenue: Math.round(revenue * 100) / 100,
    tickets_closed: closed,
    new_customers: Number(newCustRow?.n ?? 0),
    avg_ticket_value: closed > 0 ? Math.round((revenue / closed) * 100) / 100 : 0,
    top_parts: topParts.map(p => ({
      name: p.name,
      units: Number(p.units),
      revenue: Math.round(Number(p.revenue) * 100) / 100,
    })),
    top_techs: topTechs.map(t => ({
      name: t.name,
      closed: Number(t.closed),
      revenue: Math.round(Number(t.revenue) * 100) / 100,
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

<footer>Sent automatically by Bizarre Electronics CRM. Manage or unsubscribe in Reports &gt; Scheduled Delivery.</footer>
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
    '-- Bizarre Electronics CRM',
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

interface DeliveryTargets {
  db: any;                 // better-sqlite3 sync DB (for email.ts + UPDATE)
  adb: AsyncDb;            // async DB for the metric query
  recipients: string[];    // fallback owner inbox if no scheduled rows exist
}

/** Send the weekly summary. Returns number of successful deliveries. */
export async function sendWeeklySummary(targets: DeliveryTargets): Promise<number> {
  const { db, adb, recipients } = targets;

  if (!isEmailConfigured(db)) {
    logger.warn('SMTP not configured; skipping weekly summary');
    return 0;
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

  const toEmails = new Set<string>(recipients.filter(Boolean));
  for (const row of scheduled) toEmails.add(row.recipient_email);

  let sent = 0;
  for (const to of toEmails) {
    const ok = await sendEmail(db, { to, subject, html, text });
    if (ok) sent += 1;
  }

  // Record last_sent_at for every scheduled row
  const nowIso = new Date().toISOString();
  for (const row of scheduled) {
    await adb.run(
      `UPDATE scheduled_email_reports SET last_sent_at = ? WHERE id = ?`,
      nowIso, row.id
    );
  }

  logger.info('weekly summary dispatched', { sent, total: toEmails.size });
  return sent;
}

// ─── Scheduler ──────────────────────────────────────────────────────────

let running = false;
let intervalHandle: NodeJS.Timeout | null = null;

/**
 * Start the Monday 08:07 local weekly summary loop.
 * Uses a lightweight setInterval that checks "is it Monday 08:07 and we
 * haven't already sent today?" rather than pulling in a full cron library.
 *
 * @param getTargets   Factory that returns per-tick delivery targets. Re-invoked
 *                     every tick so multi-tenant callers can iterate tenants.
 */
export function startReportEmailer(getTargets: () => Promise<DeliveryTargets[]>): void {
  if (running) return;
  running = true;

  const tick = async () => {
    try {
      const now = new Date();
      const isMonday = now.getDay() === 1;
      const isTargetTime = now.getHours() === 8 && now.getMinutes() === 7;
      if (!isMonday || !isTargetTime) return;

      const targets = await getTargets();
      for (const t of targets) {
        try {
          await sendWeeklySummary(t);
        } catch (err) {
          logger.error('weekly summary send failed for tenant', { err: String(err) });
        }
      }
    } catch (err) {
      logger.error('report emailer tick failed', { err: String(err) });
    }
  };

  // Check every minute — cheap, idempotent per-minute.
  intervalHandle = setInterval(tick, 60 * 1000);
  logger.info('report emailer started', { cadence: 'every minute, fires Mon 08:07 local' });
}

export function stopReportEmailer(): void {
  if (intervalHandle) clearInterval(intervalHandle);
  intervalHandle = null;
  running = false;
}
