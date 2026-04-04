/**
 * Scheduled report email service.
 * Generates a daily summary and emails it to configured recipients.
 * Only runs if SMTP is configured and scheduled_report_email setting is set.
 */

import db from '../db/connection.js';
import { sendEmail } from './email.js';
import { createLogger } from '../utils/logger.js';

const log = createLogger('scheduled-reports');

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

function generateSummary(): DailySummary {
  const yesterday = new Date(Date.now() - 86400_000).toISOString().slice(0, 10);

  const ticketsCreated = (db.prepare(`
    SELECT COUNT(*) AS n FROM tickets WHERE is_deleted = 0 AND DATE(created_at) = ?
  `).get(yesterday) as any).n;

  const ticketsClosed = (db.prepare(`
    SELECT COUNT(*) AS n FROM ticket_history th
    JOIN tickets t ON t.id = th.ticket_id
    JOIN ticket_statuses ts ON ts.name = th.new_value
    WHERE th.action = 'status_change' AND ts.is_closed = 1
      AND t.is_deleted = 0 AND DATE(th.created_at) = ?
  `).get(yesterday) as any).n;

  const revenue = (db.prepare(`
    SELECT COALESCE(SUM(amount), 0) AS v FROM payments WHERE DATE(created_at) = ?
  `).get(yesterday) as any).v;

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
    WHERE status IN ('unpaid', 'partial') AND due_on IS NOT NULL AND due_on != '' AND DATE(due_on) < DATE('now')
  `).get() as any).n;

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

function formatCurrency(amount: number): string {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount);
}

function buildEmailBody(summary: DailySummary): string {
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
    <td style="padding:8px 12px; text-align:right;">${formatCurrency(summary.revenue)}</td>
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
  This is an automated report from Bizarre Electronics CRM.
</p>
  `.trim();
}

export async function sendDailyReport(): Promise<void> {
  // Check if scheduled reports are configured
  const emailSetting = (db.prepare(
    "SELECT value FROM store_config WHERE key = 'scheduled_report_email'"
  ).get() as any)?.value;

  if (!emailSetting) {
    log.debug('Scheduled report email not configured, skipping');
    return;
  }

  const smtpHost = (db.prepare(
    "SELECT value FROM store_config WHERE key = 'smtp_host'"
  ).get() as any)?.value;

  if (!smtpHost) {
    log.debug('SMTP not configured, skipping scheduled report');
    return;
  }

  try {
    const summary = generateSummary();
    const storeName = (db.prepare(
      "SELECT value FROM store_config WHERE key = 'store_name'"
    ).get() as any)?.value || 'Bizarre Electronics';

    await sendEmail({
      to: emailSetting,
      subject: `${storeName} Daily Report - ${summary.date}`,
      html: buildEmailBody(summary),
    });

    log.info('Daily report sent', { to: emailSetting, date: summary.date });
  } catch (err) {
    log.error('Failed to send daily report', { error: String(err) });
  }
}
