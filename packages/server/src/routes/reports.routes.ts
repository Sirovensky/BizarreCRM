import { Router } from 'express';
import db from '../db/connection.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { AppError } from '../middleware/errorHandler.js';
import { calculateAvgActiveRepairTime, getRecentClosedTicketIds, getClosedTicketIds } from '../utils/repair-time.js';

const router = Router();

// Validate date range (max 2555 days / ~7 years to prevent DoS via expensive queries)
function validateDateRange(from: string, to: string) {
  const f = new Date(from).getTime();
  const t = new Date(to).getTime();
  if (isNaN(f) || isNaN(t)) throw new AppError('Invalid date format', 400);
  if (t - f > 2556 * 86400_000) throw new AppError('Date range cannot exceed 7 years', 400);
}

// ─── Dashboard KPIs ───────────────────────────────────────────────────────────

router.get('/dashboard', asyncHandler(async (_req, res) => {
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD

  // Open tickets (not closed, not cancelled, not deleted)
  const openTickets = (db.prepare(`
    SELECT COUNT(*) AS n FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
  `).get() as any).n as number;

  // Revenue today: prefer payments; fall back to invoice amount_paid for imported data
  const paymentRevToday = (db.prepare(`
    SELECT COALESCE(SUM(p.amount), 0) AS total
    FROM payments p
    JOIN invoices i ON i.id = p.invoice_id
    WHERE i.status != 'void' AND DATE(p.created_at) = ?
  `).get(today) as any).total as number;

  const invoiceRevToday = (db.prepare(`
    SELECT COALESCE(SUM(i.amount_paid), 0) AS total
    FROM invoices i
    WHERE i.status IN ('paid', 'overpaid', 'partial') AND DATE(i.created_at) = ?
  `).get(today) as any).total as number;

  const revenueToday = paymentRevToday > 0 ? paymentRevToday : invoiceRevToday;

  // Tickets closed today
  const closedToday = (db.prepare(`
    SELECT COUNT(*) AS n FROM ticket_history th
    JOIN tickets t ON t.id = th.ticket_id
    JOIN ticket_statuses ts ON ts.name = th.new_value
    WHERE DATE(th.created_at) = ?
      AND th.action = 'status_change'
      AND ts.is_closed = 1
      AND t.is_deleted = 0
  `).get(today) as any).n as number;

  // Average ACTIVE repair time in hours (closed tickets, last 30 days)
  // Excludes time in hold/waiting statuses
  const recentClosedIds = getRecentClosedTicketIds(30);
  const avgRepair = calculateAvgActiveRepairTime(recentClosedIds);

  // Tickets created today
  const ticketsCreatedToday = (db.prepare(`
    SELECT COUNT(*) AS n FROM tickets
    WHERE is_deleted = 0 AND DATE(created_at) = ?
  `).get(today) as any).n as number;

  // Appointments today
  const appointmentsToday = (db.prepare(`
    SELECT COUNT(*) AS n FROM appointments
    WHERE DATE(start_time) = ?
  `).get(today) as any).n as number;

  // Status group counts (matching ticket list overview bar)
  const statusGroupCounts = db.prepare(`
    SELECT
      COUNT(*) AS total,
      COUNT(CASE WHEN ts.is_closed = 0 AND ts.is_cancelled = 0
                  AND LOWER(ts.name) NOT LIKE '%hold%'
                  AND LOWER(ts.name) NOT LIKE '%waiting%'
                  AND LOWER(ts.name) NOT LIKE '%pending%'
                  AND LOWER(ts.name) NOT LIKE '%transit%'
            THEN 1 END) AS open_count,
      COUNT(CASE WHEN ts.is_closed = 0 AND ts.is_cancelled = 0
                  AND (LOWER(ts.name) LIKE '%hold%'
                    OR LOWER(ts.name) LIKE '%waiting%'
                    OR LOWER(ts.name) LIKE '%pending%'
                    OR LOWER(ts.name) LIKE '%transit%')
            THEN 1 END) AS on_hold_count,
      COUNT(CASE WHEN ts.is_closed = 1 THEN 1 END) AS closed_count,
      COUNT(CASE WHEN ts.is_cancelled = 1 THEN 1 END) AS cancelled_count
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.is_deleted = 0
  `).get() as any;

  // Per-status breakdown (individual counts for each active status)
  const perStatusCounts = db.prepare(`
    SELECT ts.id, ts.name, ts.color, ts.sort_order, ts.is_closed, ts.is_cancelled,
           COUNT(t.id) AS count
    FROM ticket_statuses ts
    LEFT JOIN tickets t ON t.status_id = ts.id AND t.is_deleted = 0
    GROUP BY ts.id
    ORDER BY ts.sort_order ASC
  `).all() as any[];

  res.json({
    success: true,
    data: {
      open_tickets: openTickets,
      revenue_today: revenueToday,
      closed_today: closedToday,
      tickets_created_today: ticketsCreatedToday,
      appointments_today: appointmentsToday,
      avg_repair_hours: avgRepair ? Math.round(avgRepair * 10) / 10 : null,
      status_groups: {
        total: statusGroupCounts.total,
        open: statusGroupCounts.open_count,
        on_hold: statusGroupCounts.on_hold_count,
        closed: statusGroupCounts.closed_count,
        cancelled: statusGroupCounts.cancelled_count,
      },
      status_counts: perStatusCounts,
    },
  });
}));

// ─── Dashboard KPIs (enhanced) ────────────────────────────────────────────

router.get('/dashboard-kpis', asyncHandler(async (req, res) => {
  const from = (req.query.from_date as string) || new Date().toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);
  const employeeId = req.query.employee_id ? Number(req.query.employee_id) : null;

  const empFilter = employeeId ? ' AND t.assigned_to = ?' : '';
  const empFilterInv = employeeId ? ' AND i.created_by = ?' : '';
  const empParams = employeeId ? [employeeId] : [];

  // Total sales: CRM payments + imported invoice amount_paid (for invoices without CRM payments)
  const totalSales = (db.prepare(`
    SELECT COALESCE(SUM(revenue), 0) AS v FROM (
      -- CRM payments (from payments table)
      SELECT SUM(p.amount) AS revenue
      FROM payments p
      JOIN invoices i ON i.id = p.invoice_id
      WHERE i.status != 'void' AND DATE(p.created_at) BETWEEN ? AND ?${empFilterInv}
      UNION ALL
      -- Imported invoices (amount_paid, only for invoices with NO CRM payment records)
      SELECT SUM(i.amount_paid) AS revenue
      FROM invoices i
      WHERE i.status IN ('paid', 'overpaid', 'partial')
        AND DATE(i.created_at) BETWEEN ? AND ?${empFilterInv}
        AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.invoice_id = i.id)
    )
  `).get(from, to, ...empParams, from, to, ...empParams) as any).v as number;

  // Tax collected
  const tax = (db.prepare(`
    SELECT COALESCE(SUM(ili.tax_amount), 0) AS v
    FROM invoice_line_items ili
    JOIN invoices i ON i.id = ili.invoice_id
    WHERE i.status != 'void' AND DATE(i.created_at) BETWEEN ? AND ?${empFilterInv}
  `).get(from, to, ...empParams) as any).v as number;

  // Discounts
  const discounts = (db.prepare(`
    SELECT COALESCE(SUM(i.discount), 0) AS v
    FROM invoices i
    WHERE i.status != 'void' AND DATE(i.created_at) BETWEEN ? AND ?${empFilterInv}
  `).get(from, to, ...empParams) as any).v as number;

  // COGS (cost of parts used — prefer inventory cost_price, fallback to supplier catalog price)
  const cogs = (db.prepare(`
    SELECT COALESCE(SUM(
      COALESCE(
        NULLIF(ii.cost_price, 0),
        (SELECT MIN(sc.price) FROM supplier_catalog sc WHERE LOWER(TRIM(sc.name)) = LOWER(TRIM(ii.name)) AND sc.price > 0),
        0
      ) * tdp.quantity
    ), 0) AS v
    FROM ticket_device_parts tdp
    JOIN ticket_devices td ON td.id = tdp.ticket_device_id
    JOIN tickets t ON t.id = td.ticket_id
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?${empFilter}
  `).get(from, to, ...empParams) as any).v as number;

  const net_profit = totalSales - cogs - discounts;

  // Refunds
  const refunds = (db.prepare(`
    SELECT COALESCE(SUM(p.amount), 0) AS v
    FROM payments p
    JOIN invoices i ON i.id = p.invoice_id
    WHERE i.status = 'refunded' AND DATE(p.created_at) BETWEEN ? AND ?${empFilterInv}
  `).get(from, to, ...empParams) as any).v as number;

  // Expenses
  const expenses = (db.prepare(`
    SELECT COALESCE(SUM(amount), 0) AS v
    FROM expenses
    WHERE DATE(created_at) BETWEEN ? AND ?
  `).get(from, to) as any).v as number;

  // Account receivables
  const receivables = (db.prepare(`
    SELECT COALESCE(SUM(i.total - COALESCE(paid.total_paid, 0)), 0) AS v
    FROM invoices i
    LEFT JOIN (SELECT invoice_id, SUM(amount) as total_paid FROM payments GROUP BY invoice_id) paid ON paid.invoice_id = i.id
    WHERE i.status IN ('unpaid', 'partial') AND DATE(i.created_at) BETWEEN ? AND ?${empFilterInv}
  `).get(from, to, ...empParams) as any).v as number;

  // Sales by item type
  const repairTicketsSales = db.prepare(`
    SELECT
      COUNT(DISTINCT t.id) AS quantity,
      COALESCE(SUM(t.total), 0) AS sales,
      COALESCE(SUM(t.discount), 0) AS discounts,
      COALESCE(SUM(cogs_sub.cogs), 0) AS cogs,
      COALESCE(SUM(t.total_tax), 0) AS tax
    FROM tickets t
    LEFT JOIN (
      SELECT td.ticket_id, SUM(COALESCE(NULLIF(ii.cost_price, 0), (SELECT MIN(sc.price) FROM supplier_catalog sc WHERE LOWER(TRIM(sc.name)) = LOWER(TRIM(ii.name)) AND sc.price > 0), 0) * tdp.quantity) AS cogs
      FROM ticket_device_parts tdp
      JOIN ticket_devices td ON td.id = tdp.ticket_device_id
      LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
      GROUP BY td.ticket_id
    ) cogs_sub ON cogs_sub.ticket_id = t.id
    WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?${empFilter}
  `).get(from, to, ...empParams) as any;

  // Products: exclude invoices converted from tickets to avoid double-counting with Repair Tickets
  const productSales = db.prepare(`
    SELECT
      COALESCE(SUM(ili.quantity), 0) AS quantity,
      COALESCE(SUM(ili.total), 0) AS sales,
      COALESCE(SUM(ili.line_discount), 0) AS discounts,
      0 AS cogs,
      COALESCE(SUM(ili.tax_amount), 0) AS tax
    FROM invoice_line_items ili
    JOIN invoices i ON i.id = ili.invoice_id
    WHERE i.status != 'void' AND i.ticket_id IS NULL AND DATE(i.created_at) BETWEEN ? AND ?${empFilterInv}
  `).get(from, to, ...empParams) as any;

  const sales_by_type = [
    {
      type: 'Repair Tickets',
      quantity: repairTicketsSales?.quantity ?? 0,
      sales: repairTicketsSales?.sales ?? 0,
      discounts: repairTicketsSales?.discounts ?? 0,
      cogs: repairTicketsSales?.cogs ?? 0,
      net_profit: (repairTicketsSales?.sales ?? 0) - (repairTicketsSales?.cogs ?? 0) - (repairTicketsSales?.discounts ?? 0),
      tax: repairTicketsSales?.tax ?? 0,
    },
    {
      type: 'Products',
      quantity: productSales?.quantity ?? 0,
      sales: productSales?.sales ?? 0,
      discounts: productSales?.discounts ?? 0,
      cogs: productSales?.cogs ?? 0,
      net_profit: (productSales?.sales ?? 0) - (productSales?.cogs ?? 0) - (productSales?.discounts ?? 0),
      tax: productSales?.tax ?? 0,
    },
  ];

  // Daily sales
  const daily_sales = db.prepare(`
    SELECT
      DATE(p.created_at) AS date,
      COALESCE(SUM(p.amount), 0) AS sale,
      0 AS cogs,
      COALESCE(SUM(p.amount), 0) AS net_profit,
      100.0 AS margin,
      0 AS tax
    FROM payments p
    JOIN invoices i ON i.id = p.invoice_id
    WHERE i.status != 'void' AND DATE(p.created_at) BETWEEN ? AND ?${empFilterInv}
    GROUP BY DATE(p.created_at)
    ORDER BY date DESC
    LIMIT 30
  `).all(from, to, ...empParams) as any[];

  // Open tickets
  const open_tickets = db.prepare(`
    SELECT
      t.id, t.order_id,
      COALESCE(td.device_name, '') AS task,
      td.due_on AS due_at,
      COALESCE(u.first_name || ' ' || u.last_name, '') AS assigned_to,
      COALESCE(c.first_name || ' ' || c.last_name, '') AS customer_name,
      ts.name AS status_name,
      ts.color AS status_color
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN (
      SELECT ticket_id, MIN(id) AS first_device_id, device_name, due_on
      FROM ticket_devices
      GROUP BY ticket_id
    ) td ON td.ticket_id = t.id
    LEFT JOIN users u ON u.id = t.assigned_to
    LEFT JOIN customers c ON c.id = t.customer_id
    WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
    ORDER BY t.created_at DESC
    LIMIT 20
  `).all() as any[];

  res.json({
    success: true,
    data: {
      total_sales: totalSales,
      tax,
      discounts,
      cogs,
      net_profit,
      refunds,
      expenses,
      receivables,
      sales_by_type,
      daily_sales,
      open_tickets,
    },
  });
}));

// ─── Insights (Charts) ──────────────────────────────────────────────────────

router.get('/insights', asyncHandler(async (req, res) => {
  const from = (req.query.from_date as string) || new Date(Date.now() - 365 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);

  // Most popular models repaired (top 10)
  const popular_models = db.prepare(`
    SELECT td.device_name AS name, COUNT(*) AS count
    FROM ticket_devices td
    JOIN tickets t ON t.id = td.ticket_id
    WHERE t.is_deleted = 0 AND td.device_name IS NOT NULL AND td.device_name != ''
      AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY td.device_name
    ORDER BY count DESC
    LIMIT 10
  `).all(from, to) as any[];

  // Repairs by month
  const repairs_by_month = db.prepare(`
    SELECT STRFTIME('%Y-%m', t.created_at) AS month, COUNT(*) AS count
    FROM tickets t
    WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY month
    ORDER BY month ASC
  `).all(from, to) as any[];

  // Revenue by model (top 10)
  const revenue_by_model = db.prepare(`
    SELECT td.device_name AS name, COALESCE(SUM(td.price), 0) AS revenue
    FROM ticket_devices td
    JOIN tickets t ON t.id = td.ticket_id
    WHERE t.is_deleted = 0 AND td.device_name IS NOT NULL AND td.device_name != ''
      AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY td.device_name
    ORDER BY revenue DESC
    LIMIT 10
  `).all(from, to) as any[];

  // Most popular repair services (top 10)
  const popular_services = db.prepare(`
    SELECT td.service_name AS name, COUNT(*) AS count
    FROM ticket_devices td
    JOIN tickets t ON t.id = td.ticket_id
    WHERE t.is_deleted = 0 AND td.service_name IS NOT NULL AND td.service_name != ''
      AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY td.service_name
    ORDER BY count DESC
    LIMIT 10
  `).all(from, to) as any[];

  res.json({
    success: true,
    data: {
      popular_models,
      repairs_by_month,
      revenue_by_model,
      popular_services,
    },
  });
}));

// ─── Sales Report ─────────────────────────────────────────────────────────────

router.get('/sales', asyncHandler(async (req, res) => {
  const from = (req.query.from_date as string) || new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);
  const groupBy = (req.query.group_by as string) || 'day'; // day | week | month

  // For weeks, use the Monday date (start of ISO week) so frontend can match
  const dateFormat = groupBy === 'month' ? '%Y-%m' : '%Y-%m-%d';
  const groupExpr = groupBy === 'week'
    ? "DATE(COALESCE(p.created_at, i.created_at), 'weekday 1', '-7 days')"
    : `STRFTIME('${dateFormat}', COALESCE(p.created_at, i.created_at))`;

  // Use payments when available, fall back to invoice amount_paid for imported data
  const rows = db.prepare(`
    SELECT
      ${groupExpr} AS period,
      COUNT(DISTINCT i.id) AS invoices,
      COALESCE(SUM(p.amount), 0) AS payment_revenue,
      COALESCE(SUM(CASE WHEN p.id IS NULL THEN i.amount_paid ELSE 0 END), 0) AS imported_revenue,
      COUNT(DISTINCT i.customer_id) AS unique_customers
    FROM invoices i
    LEFT JOIN payments p ON p.invoice_id = i.id
    WHERE i.status != 'void' AND DATE(COALESCE(p.created_at, i.created_at)) BETWEEN ? AND ?
    GROUP BY period
    ORDER BY period ASC
  `).all(from, to) as any[];

  // Combine payment + imported revenue
  const combinedRows = rows.map((r: any) => ({
    period: r.period,
    invoices: r.invoices,
    revenue: r.payment_revenue + r.imported_revenue,
    unique_customers: r.unique_customers,
  }));

  const totals = db.prepare(`
    SELECT
      COUNT(DISTINCT i.id) AS total_invoices,
      COALESCE(SUM(p.amount), 0) AS payment_revenue,
      COALESCE(SUM(CASE WHEN p.id IS NULL AND i.amount_paid > 0 THEN i.amount_paid ELSE 0 END), 0) AS imported_revenue,
      COUNT(DISTINCT i.customer_id) AS unique_customers
    FROM invoices i
    LEFT JOIN payments p ON p.invoice_id = i.id
    WHERE i.status != 'void' AND DATE(COALESCE(p.created_at, i.created_at)) BETWEEN ? AND ?
  `).get(from, to) as any;

  const byMethod = db.prepare(`
    SELECT COALESCE(p.method, 'Other') AS method, SUM(p.amount) AS revenue, COUNT(*) AS count
    FROM payments p
    JOIN invoices i ON i.id = p.invoice_id
    WHERE i.status != 'void' AND DATE(p.created_at) BETWEEN ? AND ?
    GROUP BY COALESCE(p.method, 'Other')
    ORDER BY revenue DESC
  `).all(from, to) as any[];

  // Compare with previous period of same length
  const daysDiff = Math.round((new Date(to).getTime() - new Date(from).getTime()) / 86400_000);
  const prevTo = new Date(new Date(from).getTime() - 86400_000).toISOString().slice(0, 10);
  const prevFrom = new Date(new Date(prevTo).getTime() - daysDiff * 86400_000).toISOString().slice(0, 10);

  const prevTotals = db.prepare(`
    SELECT
      COALESCE(SUM(p.amount), 0) + COALESCE(SUM(CASE WHEN p.id IS NULL AND i.amount_paid > 0 THEN i.amount_paid ELSE 0 END), 0) AS total_revenue
    FROM invoices i
    LEFT JOIN payments p ON p.invoice_id = i.id
    WHERE i.status != 'void' AND DATE(COALESCE(p.created_at, i.created_at)) BETWEEN ? AND ?
  `).get(prevFrom, prevTo) as any;

  const totalRevenue = (totals.payment_revenue || 0) + (totals.imported_revenue || 0);
  const prevRevenue = prevTotals?.total_revenue || 0;
  const revenueChange = prevRevenue > 0 ? ((totalRevenue - prevRevenue) / prevRevenue) * 100 : null;

  res.json({
    success: true,
    data: {
      rows: combinedRows,
      totals: {
        total_invoices: totals.total_invoices,
        total_revenue: totalRevenue,
        unique_customers: totals.unique_customers,
        previous_revenue: prevRevenue,
        revenue_change_pct: revenueChange != null ? Math.round(revenueChange * 10) / 10 : null,
      },
      byMethod,
      from,
      to,
    },
  });
}));

// ─── Ticket Report ────────────────────────────────────────────────────────────

router.get('/tickets', asyncHandler(async (req, res) => {
  const from = (req.query.from_date as string) || new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);

  const byStatus = db.prepare(`
    SELECT ts.name AS status, ts.color, COUNT(*) AS count
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY ts.id
    ORDER BY count DESC
  `).all(from, to) as any[];

  const byDay = db.prepare(`
    SELECT DATE(created_at) AS day, COUNT(*) AS created
    FROM tickets
    WHERE is_deleted = 0 AND DATE(created_at) BETWEEN ? AND ?
    GROUP BY day ORDER BY day ASC
  `).all(from, to) as any[];

  const byTech = db.prepare(`
    SELECT u.first_name || ' ' || u.last_name AS tech_name,
      COUNT(*) AS ticket_count,
      SUM(CASE WHEN ts.is_closed = 1 THEN 1 ELSE 0 END) AS closed_count,
      COALESCE(SUM(t.total), 0) AS total_revenue
    FROM tickets t
    JOIN users u ON u.id = t.assigned_to
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY t.assigned_to
    ORDER BY ticket_count DESC
  `).all(from, to) as any[];

  // Summary totals
  const summary = db.prepare(`
    SELECT
      COUNT(*) AS total_created,
      SUM(CASE WHEN ts.is_closed = 1 THEN 1 ELSE 0 END) AS total_closed,
      COALESCE(SUM(t.total), 0) AS total_revenue,
      COALESCE(AVG(t.total), 0) AS avg_ticket_value
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?
  `).get(from, to) as any;

  // Avg ACTIVE turnaround time (hours) for closed tickets — excludes hold/waiting time
  const closedIds = getClosedTicketIds(from, to);
  const avgTurnaround = calculateAvgActiveRepairTime(closedIds);

  res.json({
    success: true,
    data: {
      byStatus,
      byDay,
      byTech,
      summary: {
        total_created: summary?.total_created || 0,
        total_closed: summary?.total_closed || 0,
        total_revenue: summary?.total_revenue || 0,
        avg_ticket_value: summary?.avg_ticket_value ? Math.round(summary.avg_ticket_value * 100) / 100 : 0,
        avg_turnaround_hours: avgTurnaround ? Math.round(avgTurnaround * 10) / 10 : null,
      },
      from,
      to,
    },
  });
}));

// ─── Employee Report ──────────────────────────────────────────────────────────

router.get('/employees', asyncHandler(async (req, res) => {
  const from = (req.query.from_date as string) || new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);

  const rows = db.prepare(`
    SELECT
      u.id, u.first_name || ' ' || u.last_name AS name, u.role,
      COALESCE(ticket_counts.cnt, 0) AS tickets_assigned,
      COALESCE(ticket_counts.closed, 0) AS tickets_closed,
      COALESCE(commission_sums.total, 0) AS commission_earned,
      COALESCE(clock_sums.hours, 0) AS hours_worked,
      COALESCE(revenue_sums.total, 0) AS revenue_generated
    FROM users u
    LEFT JOIN (
      SELECT assigned_to, COUNT(*) AS cnt,
        SUM(CASE WHEN ts.is_closed = 1 THEN 1 ELSE 0 END) AS closed
      FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?
      GROUP BY assigned_to
    ) ticket_counts ON ticket_counts.assigned_to = u.id
    LEFT JOIN (
      SELECT user_id, SUM(amount) AS total
      FROM commissions
      WHERE DATE(created_at) BETWEEN ? AND ?
      GROUP BY user_id
    ) commission_sums ON commission_sums.user_id = u.id
    LEFT JOIN (
      SELECT user_id, SUM(
        CASE WHEN clock_out IS NOT NULL
          THEN (JULIANDAY(clock_out) - JULIANDAY(clock_in)) * 24
          ELSE 0 END
      ) AS hours
      FROM clock_entries
      WHERE DATE(clock_in) BETWEEN ? AND ?
      GROUP BY user_id
    ) clock_sums ON clock_sums.user_id = u.id
    LEFT JOIN (
      SELECT i.created_by, SUM(p.amount) AS total
      FROM payments p
      JOIN invoices i ON i.id = p.invoice_id
      WHERE i.status != 'void' AND DATE(p.created_at) BETWEEN ? AND ?
      GROUP BY i.created_by
    ) revenue_sums ON revenue_sums.created_by = u.id
    WHERE u.is_active = 1
    ORDER BY tickets_assigned DESC
  `).all(from, to, from, to, from, to, from, to) as any[];

  res.json({ success: true, data: { rows, from, to } });
}));

// ─── Inventory Report ─────────────────────────────────────────────────────────

router.get('/inventory', asyncHandler(async (_req, res) => {
  const lowStock = db.prepare(`
    SELECT id, name, sku, in_stock, reorder_level, retail_price, cost_price, item_type
    FROM inventory_items
    WHERE item_type != 'service' AND is_active = 1
      AND in_stock <= reorder_level
    ORDER BY in_stock ASC
    LIMIT 50
  `).all() as any[];

  const valueSummary = db.prepare(`
    SELECT
      item_type,
      COUNT(*) AS item_count,
      SUM(in_stock) AS total_units,
      SUM(in_stock * cost_price) AS total_cost_value,
      SUM(in_stock * retail_price) AS total_retail_value
    FROM inventory_items
    WHERE is_active = 1 AND item_type != 'service'
    GROUP BY item_type
  `).all() as any[];

  // Out of stock items
  const outOfStock = (db.prepare(`
    SELECT COUNT(*) AS n FROM inventory_items
    WHERE is_active = 1 AND item_type != 'service' AND in_stock = 0
  `).get() as any).n as number;

  // Top moving items (most used in repairs in last 30 days)
  const topMoving = db.prepare(`
    SELECT ii.name, ii.sku, SUM(tdp.quantity) AS used_qty, ii.in_stock
    FROM ticket_device_parts tdp
    JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    JOIN ticket_devices td ON td.id = tdp.ticket_device_id
    JOIN tickets t ON t.id = td.ticket_id
    WHERE t.is_deleted = 0 AND DATE(t.created_at) >= DATE('now', '-30 days')
    GROUP BY ii.id
    ORDER BY used_qty DESC
    LIMIT 10
  `).all() as any[];

  res.json({ success: true, data: { lowStock, valueSummary, outOfStock, topMoving } });
}));

// ─── Tax Report ───────────────────────────────────────────────────────────────

router.get('/tax', asyncHandler(async (req, res) => {
  const from = (req.query.from_date as string) || new Date().toISOString().slice(0, 7) + '-01';
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);

  const rows = db.prepare(`
    SELECT
      tc.name AS tax_class,
      tc.rate,
      SUM(ili.tax_amount) AS tax_collected,
      SUM(ili.total) AS revenue
    FROM invoice_line_items ili
    JOIN invoices i ON i.id = ili.invoice_id
    LEFT JOIN tax_classes tc ON tc.id = ili.tax_class_id
    WHERE i.status != 'void' AND DATE(i.created_at) BETWEEN ? AND ?
    GROUP BY ili.tax_class_id
    ORDER BY tax_collected DESC
  `).all(from, to) as any[];

  res.json({ success: true, data: { rows, from, to } });
}));

// ─── Tech Workload ───────────────────────────────────────────────────────────

router.get('/tech-workload', asyncHandler(async (_req, res) => {
  const monthStart = new Date();
  monthStart.setDate(1);
  const monthStartStr = monthStart.toISOString().slice(0, 10);
  const todayStr = new Date().toISOString().slice(0, 10);

  const rows = db.prepare(`
    SELECT
      u.id,
      u.first_name || ' ' || u.last_name AS name,
      COALESCE(open_counts.open_tickets, 0) AS open_tickets,
      COALESCE(open_counts.in_progress, 0) AS in_progress,
      COALESCE(open_counts.waiting_parts, 0) AS waiting_parts,
      COALESCE(rev.revenue, 0) AS revenue_this_month
    FROM users u
    LEFT JOIN (
      SELECT
        t.assigned_to,
        COUNT(*) AS open_tickets,
        SUM(CASE WHEN ts.name = 'In Progress' THEN 1 ELSE 0 END) AS in_progress,
        SUM(CASE WHEN ts.name IN ('Waiting for Parts', 'Special Part Order (Pending Parts)') THEN 1 ELSE 0 END) AS waiting_parts
      FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
      GROUP BY t.assigned_to
    ) open_counts ON open_counts.assigned_to = u.id
    LEFT JOIN (
      SELECT
        t.assigned_to,
        COALESCE(SUM(t.total), 0) AS revenue
      FROM tickets t
      WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?
      GROUP BY t.assigned_to
    ) rev ON rev.assigned_to = u.id
    WHERE u.is_active = 1
      AND (open_counts.open_tickets > 0 OR rev.revenue > 0)
    ORDER BY open_counts.open_tickets DESC
  `).all(monthStartStr, todayStr) as any[];

  // Calculate active repair time per tech (excludes hold/waiting statuses)
  const data = rows.map((r: any) => {
    const techClosedIds = getClosedTicketIds(undefined, undefined, r.id);
    // Only use last 90 days of closed tickets
    const recentIds = techClosedIds.slice(0, 200); // cap for performance
    const avgHours = calculateAvgActiveRepairTime(recentIds);
    return {
      ...r,
      avg_repair_hours: avgHours ? Math.round(avgHours * 10) / 10 : 0,
      revenue_this_month: Math.round(r.revenue_this_month * 100) / 100,
    };
  });

  res.json({ success: true, data });
}));

// ─── Needs Attention ──────────────────────────────────────────────────────────

router.get('/needs-attention', asyncHandler(async (_req, res) => {
  const today = new Date().toISOString().slice(0, 10);

  // Stale tickets: open, not updated in 3+ days
  const stale_tickets = db.prepare(`
    SELECT t.id, t.order_id,
      COALESCE(c.first_name || ' ' || c.last_name, 'Unknown') AS customer_name,
      CAST(JULIANDAY('now') - JULIANDAY(t.updated_at) AS INTEGER) AS days_stale,
      ts.name AS status
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN customers c ON c.id = t.customer_id
    WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
      AND JULIANDAY('now') - JULIANDAY(t.updated_at) >= 3
    ORDER BY days_stale DESC
    LIMIT 20
  `).all() as any[];

  // Missing parts count (open tickets with parts that have status='missing' or in_stock < quantity)
  const missing_parts_count = (db.prepare(`
    SELECT COUNT(DISTINCT tdp.id) AS n
    FROM ticket_device_parts tdp
    JOIN ticket_devices td ON td.id = tdp.ticket_device_id
    JOIN tickets t ON t.id = td.ticket_id
    JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
      AND (tdp.status = 'missing' OR (ii.id IS NOT NULL AND ii.in_stock < tdp.quantity))
  `).get() as any).n as number;

  // Overdue invoices: unpaid/partial, past due_on
  const overdue_invoices = db.prepare(`
    SELECT i.id, i.order_id,
      COALESCE(c.first_name || ' ' || c.last_name, 'Unknown') AS customer_name,
      i.total - COALESCE(i.amount_paid, 0) AS amount_due,
      CAST(JULIANDAY('now') - JULIANDAY(i.due_on) AS INTEGER) AS days_overdue
    FROM invoices i
    LEFT JOIN customers c ON c.id = i.customer_id
    WHERE i.status IN ('unpaid', 'partial')
      AND i.due_on IS NOT NULL AND i.due_on != ''
      AND DATE(i.due_on) < ?
    ORDER BY days_overdue DESC
    LIMIT 20
  `).all(today) as any[];

  // Low stock count
  const low_stock_count = (db.prepare(`
    SELECT COUNT(*) AS n FROM inventory_items
    WHERE item_type != 'service' AND is_active = 1 AND is_reorderable = 1
      AND in_stock <= reorder_level
  `).get() as any).n as number;

  res.json({
    success: true,
    data: {
      stale_tickets,
      missing_parts_count,
      overdue_invoices,
      low_stock_count,
    },
  });
}));

export default router;
