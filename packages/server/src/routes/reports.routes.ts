import { Router } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { AppError } from '../middleware/errorHandler.js';
import { requireFeature } from '../middleware/tierGate.js';
import { calculateAvgActiveRepairTime, getRecentClosedTicketIds, getClosedTicketIds } from '../utils/repair-time.js';
import { dashboardCache } from '../utils/cache.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

// SEC-H11: Admin or manager role required for financial report endpoints.
// Technicians should not have access to revenue, sales, KPI, or tax data.
function requireAdminOrManager(req: any): void {
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager') {
    throw new AppError('Admin or manager access required', 403);
  }
}

// Validate date range (max 2555 days / ~7 years to prevent DoS via expensive queries)
function validateDateRange(from: string, to: string) {
  const f = new Date(from).getTime();
  const t = new Date(to).getTime();
  if (isNaN(f) || isNaN(t)) throw new AppError('Invalid date format', 400);
  if (t - f > 2556 * 86400_000) throw new AppError('Date range cannot exceed 7 years', 400);
}

// ─── Dashboard KPIs ───────────────────────────────────────────────────────────

router.get('/dashboard', asyncHandler(async (req, res) => {
  // Cache key includes tenant slug (if multi-tenant) to avoid cross-tenant leaks
  const tenantSlug = (req as any).tenantSlug || 'default';
  const cacheKey = `dashboard:${tenantSlug}`;
  const cached = dashboardCache.get(cacheKey);
  if (cached) {
    res.json(cached);
    return;
  }

  const adb = req.asyncDb;
  const db = req.db; // needed for sync repair-time utils
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
  const monthStart = new Date();
  monthStart.setDate(1);
  const monthStartStr = monthStart.toISOString().slice(0, 10);

  // Parallelize all independent queries
  const [
    openTicketsRow,
    paymentRevTodayRow,
    invoiceRevTodayRow,
    closedTodayRow,
    ticketsCreatedTodayRow,
    appointmentsTodayRow,
    statusGroupCounts,
    perStatusCounts,
    revenueTrend,
    topServices,
    customerTrend,
    inventoryValueRow,
    staffLeaderboard,
  ] = await Promise.all([
    // Open tickets (not closed, not cancelled, not deleted)
    adb.get<any>(`
      SELECT COUNT(*) AS n FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
    `),
    // RPT1: Revenue today — CRM payments (from payments table) PLUS imported invoice
    // amount_paid for invoices that have NO payment rows (avoids double-counting the
    // same money when both records exist for an invoice).
    adb.get<any>(`
      SELECT COALESCE(SUM(p.amount), 0) AS total
      FROM payments p
      JOIN invoices i ON i.id = p.invoice_id
      WHERE i.status != 'void' AND DATE(p.created_at) = ?
    `, today),
    adb.get<any>(`
      SELECT COALESCE(SUM(i.amount_paid), 0) AS total
      FROM invoices i
      LEFT JOIN (SELECT DISTINCT invoice_id FROM payments) crm_pay ON crm_pay.invoice_id = i.id
      WHERE i.status IN ('paid', 'overpaid', 'partial')
        AND DATE(i.created_at) = ?
        AND crm_pay.invoice_id IS NULL
    `, today),
    // Tickets closed today
    adb.get<any>(`
      SELECT COUNT(*) AS n FROM ticket_history th
      JOIN tickets t ON t.id = th.ticket_id
      JOIN ticket_statuses ts ON ts.name = th.new_value
      WHERE DATE(th.created_at) = ?
        AND th.action = 'status_change'
        AND ts.is_closed = 1
        AND t.is_deleted = 0
    `, today),
    // Tickets created today
    adb.get<any>(`
      SELECT COUNT(*) AS n FROM tickets
      WHERE is_deleted = 0 AND DATE(created_at) = ?
    `, today),
    // Appointments today
    adb.get<any>(`
      SELECT COUNT(*) AS n FROM appointments
      WHERE DATE(start_time) = ?
    `, today),
    // Status group counts (matching ticket list overview bar)
    adb.get<any>(`
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
    `),
    // Per-status breakdown (individual counts for each active status)
    adb.all<any>(`
      SELECT ts.id, ts.name, ts.color, ts.sort_order, ts.is_closed, ts.is_cancelled,
             COUNT(t.id) AS count
      FROM ticket_statuses ts
      LEFT JOIN tickets t ON t.status_id = ts.id AND t.is_deleted = 0
      GROUP BY ts.id
      ORDER BY ts.sort_order ASC
    `),
    // ENR-D1: Revenue trend — last 12 months of revenue
    adb.all<any>(`
      SELECT
        STRFTIME('%Y-%m', COALESCE(p.created_at, i.created_at)) AS month,
        COALESCE(SUM(p.amount), 0) + COALESCE(SUM(
          CASE WHEN p.id IS NULL AND i.amount_paid > 0 THEN i.amount_paid ELSE 0 END
        ), 0) AS revenue
      FROM invoices i
      LEFT JOIN payments p ON p.invoice_id = i.id
      WHERE i.status != 'void'
        AND DATE(COALESCE(p.created_at, i.created_at)) >= DATE('now', '-12 months')
      GROUP BY month
      ORDER BY month ASC
    `),
    // RPT4: Top services by revenue — top 5 repair services, last 12 months.
    // Must match the default range used by the drill-in /insights report so
    // dashboard totals line up with the detail view.
    adb.all<any>(`
      SELECT
        td.service_name AS name,
        COUNT(*) AS count,
        COALESCE(SUM(td.price), 0) AS revenue
      FROM ticket_devices td
      JOIN tickets t ON t.id = td.ticket_id
      WHERE t.is_deleted = 0
        AND td.service_name IS NOT NULL AND td.service_name != ''
        AND DATE(t.created_at) >= DATE('now', '-12 months')
      GROUP BY td.service_name
      ORDER BY revenue DESC
      LIMIT 5
    `),
    // ENR-D3: Customer acquisition trend — new customers per month, last 6 months
    adb.all<any>(`
      SELECT
        STRFTIME('%Y-%m', created_at) AS month,
        COUNT(*) AS new_customers
      FROM customers
      WHERE is_deleted = 0
        AND DATE(created_at) >= DATE('now', '-6 months')
      GROUP BY month
      ORDER BY month ASC
    `),
    // ENR-D4: Inventory value — total cost_price * in_stock for active items
    adb.get<any>(`
      SELECT COALESCE(SUM(cost_price * in_stock), 0) AS total
      FROM inventory_items
      WHERE is_active = 1 AND item_type != 'service'
    `),
    // ENR-D5: Staff performance leaderboard — top 5 techs by tickets closed this month
    adb.all<any>(`
      SELECT
        u.first_name || ' ' || u.last_name AS name,
        COUNT(*) AS tickets_closed,
        COALESCE(SUM(t.total), 0) AS revenue
      FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      JOIN users u ON u.id = t.assigned_to
      WHERE t.is_deleted = 0 AND ts.is_closed = 1
        AND DATE(t.updated_at) BETWEEN ? AND ?
      GROUP BY t.assigned_to
      ORDER BY tickets_closed DESC
      LIMIT 5
    `, monthStartStr, today),
  ]);

  const openTickets = openTicketsRow?.n ?? 0;
  const paymentRevToday = paymentRevTodayRow?.total ?? 0;
  const invoiceRevToday = invoiceRevTodayRow?.total ?? 0;
  // RPT1: sum payments + imported-invoice-fallback because the two queries are now
  // mutually exclusive (imported invoice query excludes rows that have payments).
  const revenueToday = paymentRevToday + invoiceRevToday;
  const closedToday = closedTodayRow?.n ?? 0;
  const ticketsCreatedToday = ticketsCreatedTodayRow?.n ?? 0;
  const appointmentsToday = appointmentsTodayRow?.n ?? 0;
  const inventoryValue = inventoryValueRow?.total ?? 0;

  // Average ACTIVE repair time in hours (closed tickets, last 30 days)
  // Excludes time in hold/waiting statuses — uses sync db
  const recentClosedIds = getRecentClosedTicketIds(db, 30);
  const avgRepair = calculateAvgActiveRepairTime(db, recentClosedIds);

  const response = {
    success: true,
    data: {
      open_tickets: openTickets,
      revenue_today: revenueToday,
      closed_today: closedToday,
      tickets_created_today: ticketsCreatedToday,
      appointments_today: appointmentsToday,
      avg_repair_hours: avgRepair ? Math.round(avgRepair * 10) / 10 : null,
      status_groups: {
        total: statusGroupCounts?.total ?? 0,
        open: statusGroupCounts?.open_count ?? 0,
        on_hold: statusGroupCounts?.on_hold_count ?? 0,
        closed: statusGroupCounts?.closed_count ?? 0,
        cancelled: statusGroupCounts?.cancelled_count ?? 0,
      },
      status_counts: perStatusCounts,
      revenue_trend: revenueTrend,
      top_services: topServices,
      customer_trend: customerTrend,
      inventory_value: inventoryValue,
      staff_leaderboard: staffLeaderboard,
    },
  };

  // Cache for 60 seconds to avoid re-running expensive aggregation queries
  dashboardCache.set(cacheKey, response, 60_000);
  res.json(response);
}));

// ─── Dashboard KPIs (enhanced) ────────────────────────────────────────────

router.get('/dashboard-kpis', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date().toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);
  const employeeId = req.query.employee_id ? Number(req.query.employee_id) : null;

  const empFilter = employeeId ? ' AND t.assigned_to = ?' : '';
  const empFilterInv = employeeId ? ' AND i.created_by = ?' : '';
  const empParams = employeeId ? [employeeId] : [];

  // RPT8: Screen view uses small LIMITs (30 daily rows, 20 open tickets) to
  // keep dashboard responsive. When export_all=true is passed, raise the limit
  // to 10000 so CSV/download paths can pull the full period without the screen
  // truncating them. The 10000 cap is a hard DoS guard.
  const exportAll = req.query.export_all === 'true' || req.query.export_all === '1';
  const dailySalesLimit = exportAll ? 10000 : 30;
  const openTicketsLimit = exportAll ? 10000 : 20;

  // Parallelize all independent scalar queries
  const [
    totalSalesRow,
    taxRow,
    discountsRow,
    cogsRow,
    refundsRow,
    expensesRow,
    receivablesRow,
    repairTicketsSales,
    productSales,
    daily_sales,
    open_tickets,
  ] = await Promise.all([
    // Total sales: CRM payments + imported invoice amount_paid (for invoices without CRM payments)
    // PERF-7: Replaced NOT EXISTS with LEFT JOIN for imported invoices to avoid repeated subquery scan
    adb.get<any>(`
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
        LEFT JOIN (SELECT DISTINCT invoice_id FROM payments) crm_pay ON crm_pay.invoice_id = i.id
        WHERE i.status IN ('paid', 'overpaid', 'partial')
          AND DATE(i.created_at) BETWEEN ? AND ?${empFilterInv}
          AND crm_pay.invoice_id IS NULL
      )
    `, from, to, ...empParams, from, to, ...empParams),
    // Tax collected
    adb.get<any>(`
      SELECT COALESCE(SUM(ili.tax_amount), 0) AS v
      FROM invoice_line_items ili
      JOIN invoices i ON i.id = ili.invoice_id
      WHERE i.status != 'void' AND DATE(i.created_at) BETWEEN ? AND ?${empFilterInv}
    `, from, to, ...empParams),
    // Discounts
    adb.get<any>(`
      SELECT COALESCE(SUM(i.discount), 0) AS v
      FROM invoices i
      WHERE i.status != 'void' AND DATE(i.created_at) BETWEEN ? AND ?${empFilterInv}
    `, from, to, ...empParams),
    // COGS (cost of parts used — prefer inventory cost_price, fallback to supplier catalog min price)
    // PERF-6: Pre-aggregate supplier catalog min prices via subquery JOIN instead of
    // correlated subquery per row. Uses idx_supplier_catalog_name_price expression index.
    adb.get<any>(`
      SELECT COALESCE(SUM(
        COALESCE(NULLIF(ii.cost_price, 0), sc_min.min_price, 0) * tdp.quantity
      ), 0) AS v
      FROM ticket_device_parts tdp
      JOIN ticket_devices td ON td.id = tdp.ticket_device_id
      JOIN tickets t ON t.id = td.ticket_id
      LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
      LEFT JOIN (
        SELECT LOWER(TRIM(name)) AS norm_name, MIN(price) AS min_price
        FROM supplier_catalog WHERE price > 0
        GROUP BY LOWER(TRIM(name))
      ) sc_min ON ii.cost_price = 0 AND sc_min.norm_name = LOWER(TRIM(ii.name))
      WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?${empFilter}
    `, from, to, ...empParams),
    // Refunds
    adb.get<any>(`
      SELECT COALESCE(SUM(p.amount), 0) AS v
      FROM payments p
      JOIN invoices i ON i.id = p.invoice_id
      WHERE i.status = 'refunded' AND DATE(p.created_at) BETWEEN ? AND ?${empFilterInv}
    `, from, to, ...empParams),
    // Expenses
    adb.get<any>(`
      SELECT COALESCE(SUM(amount), 0) AS v
      FROM expenses
      WHERE DATE(created_at) BETWEEN ? AND ?
    `, from, to),
    // Account receivables
    adb.get<any>(`
      SELECT COALESCE(SUM(i.total - COALESCE(paid.total_paid, 0)), 0) AS v
      FROM invoices i
      LEFT JOIN (SELECT invoice_id, SUM(amount) as total_paid FROM payments GROUP BY invoice_id) paid ON paid.invoice_id = i.id
      WHERE i.status IN ('unpaid', 'partial') AND DATE(i.created_at) BETWEEN ? AND ?${empFilterInv}
    `, from, to, ...empParams),
    // Sales by item type — Repair Tickets
    adb.get<any>(`
      SELECT
        COUNT(DISTINCT t.id) AS quantity,
        COALESCE(SUM(t.total), 0) AS sales,
        COALESCE(SUM(t.discount), 0) AS discounts,
        COALESCE(SUM(cogs_sub.cogs), 0) AS cogs,
        COALESCE(SUM(t.total_tax), 0) AS tax
      FROM tickets t
      LEFT JOIN (
        SELECT td.ticket_id, SUM(COALESCE(NULLIF(ii.cost_price, 0), sc_min.min_price, 0) * tdp.quantity) AS cogs
        FROM ticket_device_parts tdp
        JOIN ticket_devices td ON td.id = tdp.ticket_device_id
        LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
        LEFT JOIN (
          SELECT LOWER(TRIM(name)) AS norm_name, MIN(price) AS min_price
          FROM supplier_catalog WHERE price > 0
          GROUP BY LOWER(TRIM(name))
        ) sc_min ON ii.cost_price = 0 AND sc_min.norm_name = LOWER(TRIM(ii.name))
        GROUP BY td.ticket_id
      ) cogs_sub ON cogs_sub.ticket_id = t.id
      WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?${empFilter}
    `, from, to, ...empParams),
    // RPT3: Products — real COGS from inventory_items.cost_price (LEFT JOIN so
    // line items with no matching inventory record count as unknown cost = 0).
    // Excludes invoices converted from tickets to avoid double-counting with Repair Tickets.
    adb.get<any>(`
      SELECT
        COALESCE(SUM(ili.quantity), 0) AS quantity,
        COALESCE(SUM(ili.total), 0) AS sales,
        COALESCE(SUM(ili.line_discount), 0) AS discounts,
        COALESCE(SUM(COALESCE(ii.cost_price, 0) * ili.quantity), 0) AS cogs,
        COALESCE(SUM(ili.tax_amount), 0) AS tax
      FROM invoice_line_items ili
      JOIN invoices i ON i.id = ili.invoice_id
      LEFT JOIN inventory_items ii ON ii.id = ili.inventory_item_id
      WHERE i.status != 'void' AND i.ticket_id IS NULL AND DATE(i.created_at) BETWEEN ? AND ?${empFilterInv}
    `, from, to, ...empParams),
    // RPT2: Daily sales — real COGS + tax + margin instead of hardcoded values.
    // Each day: sum of payments (revenue), joined against per-invoice COGS
    // (from product line items via inventory_items.cost_price) and per-invoice
    // tax (from invoice_line_items.tax_amount). Margin is (rev - cogs)/rev * 100
    // or NULL when revenue is 0 (avoid /0). Note: tax and COGS are keyed by
    // invoice, so splitting one invoice across multiple payment days would count
    // that invoice's cogs/tax on every payment day — acceptable since same-day
    // payments are the overwhelming norm for this report.
    adb.all<any>(`
      SELECT
        DATE(p.created_at) AS date,
        COALESCE(SUM(p.amount), 0) AS sale,
        COALESCE(SUM(inv_cogs.cogs), 0) AS cogs,
        COALESCE(SUM(p.amount), 0) - COALESCE(SUM(inv_cogs.cogs), 0) AS net_profit,
        CASE
          WHEN COALESCE(SUM(p.amount), 0) > 0
          THEN ROUND(
            (COALESCE(SUM(p.amount), 0) - COALESCE(SUM(inv_cogs.cogs), 0))
            / SUM(p.amount) * 100, 1)
          ELSE NULL
        END AS margin,
        COALESCE(SUM(inv_tax.tax), 0) AS tax
      FROM payments p
      JOIN invoices i ON i.id = p.invoice_id
      LEFT JOIN (
        SELECT ili.invoice_id,
               SUM(COALESCE(ii.cost_price, 0) * ili.quantity) AS cogs
        FROM invoice_line_items ili
        LEFT JOIN inventory_items ii ON ii.id = ili.inventory_item_id
        GROUP BY ili.invoice_id
      ) inv_cogs ON inv_cogs.invoice_id = i.id
      LEFT JOIN (
        SELECT invoice_id, SUM(tax_amount) AS tax
        FROM invoice_line_items
        GROUP BY invoice_id
      ) inv_tax ON inv_tax.invoice_id = i.id
      WHERE i.status != 'void' AND DATE(p.created_at) BETWEEN ? AND ?${empFilterInv}
      GROUP BY DATE(p.created_at)
      ORDER BY date DESC
      LIMIT ${dailySalesLimit}
    `, from, to, ...empParams),
    // Open tickets
    adb.all<any>(`
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
      LIMIT ${openTicketsLimit}
    `),
  ]);

  const totalSales = totalSalesRow?.v ?? 0;
  const tax = taxRow?.v ?? 0;
  const discounts = discountsRow?.v ?? 0;
  const cogs = cogsRow?.v ?? 0;
  const net_profit = totalSales - cogs - discounts;
  const refunds = refundsRow?.v ?? 0;
  const expenses = expensesRow?.v ?? 0;
  const receivables = receivablesRow?.v ?? 0;

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
  const adb = req.asyncDb;
  // RPT4: Default to the same ~12-month window as the dashboard top-services
  // card so the drill-in detail view matches the summary on first load.
  // Callers can still override with explicit from_date / to_date.
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  const defaultFrom = new Date();
  defaultFrom.setMonth(defaultFrom.getMonth() - 12);
  const from = (req.query.from_date as string) || defaultFrom.toISOString().slice(0, 10);
  validateDateRange(from, to);

  const [popular_models, repairs_by_month, revenue_by_model, popular_services] = await Promise.all([
    // Most popular models repaired (top 10)
    adb.all<any>(`
      SELECT td.device_name AS name, COUNT(*) AS count
      FROM ticket_devices td
      JOIN tickets t ON t.id = td.ticket_id
      WHERE t.is_deleted = 0 AND td.device_name IS NOT NULL AND td.device_name != ''
        AND DATE(t.created_at) BETWEEN ? AND ?
      GROUP BY td.device_name
      ORDER BY count DESC
      LIMIT 10
    `, from, to),
    // Repairs by month
    adb.all<any>(`
      SELECT STRFTIME('%Y-%m', t.created_at) AS month, COUNT(*) AS count
      FROM tickets t
      WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?
      GROUP BY month
      ORDER BY month ASC
    `, from, to),
    // Revenue by model (top 10)
    adb.all<any>(`
      SELECT td.device_name AS name, COALESCE(SUM(td.price), 0) AS revenue
      FROM ticket_devices td
      JOIN tickets t ON t.id = td.ticket_id
      WHERE t.is_deleted = 0 AND td.device_name IS NOT NULL AND td.device_name != ''
        AND DATE(t.created_at) BETWEEN ? AND ?
      GROUP BY td.device_name
      ORDER BY revenue DESC
      LIMIT 10
    `, from, to),
    // Most popular repair services (top 10)
    adb.all<any>(`
      SELECT td.service_name AS name, COUNT(*) AS count
      FROM ticket_devices td
      JOIN tickets t ON t.id = td.ticket_id
      WHERE t.is_deleted = 0 AND td.service_name IS NOT NULL AND td.service_name != ''
        AND DATE(t.created_at) BETWEEN ? AND ?
      GROUP BY td.service_name
      ORDER BY count DESC
      LIMIT 10
    `, from, to),
  ]);

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
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);
  const groupBy = (req.query.group_by as string) || 'day'; // day | week | month

  // For weeks, use the Monday date (start of ISO week) so frontend can match
  const dateFormat = groupBy === 'month' ? '%Y-%m' : '%Y-%m-%d';
  const groupExpr = groupBy === 'week'
    ? "DATE(COALESCE(p.created_at, i.created_at), 'weekday 1', '-7 days')"
    : `STRFTIME('${dateFormat}', COALESCE(p.created_at, i.created_at))`;

  // Compare with previous period of same length
  const daysDiff = Math.round((new Date(to).getTime() - new Date(from).getTime()) / 86400_000);
  const prevTo = new Date(new Date(from).getTime() - 86400_000).toISOString().slice(0, 10);
  const prevFrom = new Date(new Date(prevTo).getTime() - daysDiff * 86400_000).toISOString().slice(0, 10);

  const [rows, totals, byMethod, prevTotals] = await Promise.all([
    // Use payments when available, fall back to invoice amount_paid for imported data
    adb.all<any>(`
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
    `, from, to),
    adb.get<any>(`
      SELECT
        COUNT(DISTINCT i.id) AS total_invoices,
        COALESCE(SUM(p.amount), 0) AS payment_revenue,
        COALESCE(SUM(CASE WHEN p.id IS NULL AND i.amount_paid > 0 THEN i.amount_paid ELSE 0 END), 0) AS imported_revenue,
        COUNT(DISTINCT i.customer_id) AS unique_customers
      FROM invoices i
      LEFT JOIN payments p ON p.invoice_id = i.id
      WHERE i.status != 'void' AND DATE(COALESCE(p.created_at, i.created_at)) BETWEEN ? AND ?
    `, from, to),
    adb.all<any>(`
      SELECT COALESCE(p.method, 'Other') AS method, SUM(p.amount) AS revenue, COUNT(*) AS count
      FROM payments p
      JOIN invoices i ON i.id = p.invoice_id
      WHERE i.status != 'void' AND DATE(p.created_at) BETWEEN ? AND ?
      GROUP BY COALESCE(p.method, 'Other')
      ORDER BY revenue DESC
    `, from, to),
    adb.get<any>(`
      SELECT
        COALESCE(SUM(p.amount), 0) + COALESCE(SUM(CASE WHEN p.id IS NULL AND i.amount_paid > 0 THEN i.amount_paid ELSE 0 END), 0) AS total_revenue
      FROM invoices i
      LEFT JOIN payments p ON p.invoice_id = i.id
      WHERE i.status != 'void' AND DATE(COALESCE(p.created_at, i.created_at)) BETWEEN ? AND ?
    `, prevFrom, prevTo),
  ]);

  // Combine payment + imported revenue
  const combinedRows = rows.map((r: any) => ({
    period: r.period,
    invoices: r.invoices,
    revenue: r.payment_revenue + r.imported_revenue,
    unique_customers: r.unique_customers,
  }));

  const totalRevenue = (totals?.payment_revenue || 0) + (totals?.imported_revenue || 0);
  const prevRevenue = prevTotals?.total_revenue || 0;
  const revenueChange = prevRevenue > 0 ? ((totalRevenue - prevRevenue) / prevRevenue) * 100 : null;

  res.json({
    success: true,
    data: {
      rows: combinedRows,
      totals: {
        total_invoices: totals?.total_invoices ?? 0,
        total_revenue: totalRevenue,
        unique_customers: totals?.unique_customers ?? 0,
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
  const adb = req.asyncDb;
  const db = req.db; // needed for sync repair-time utils
  const from = (req.query.from_date as string) || new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);

  const [byStatus, byDay, byTech, summary] = await Promise.all([
    adb.all<any>(`
      SELECT ts.name AS status, ts.color, COUNT(*) AS count
      FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?
      GROUP BY ts.id
      ORDER BY count DESC
    `, from, to),
    adb.all<any>(`
      SELECT DATE(created_at) AS day, COUNT(*) AS created
      FROM tickets
      WHERE is_deleted = 0 AND DATE(created_at) BETWEEN ? AND ?
      GROUP BY day ORDER BY day ASC
    `, from, to),
    adb.all<any>(`
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
    `, from, to),
    // Summary totals
    adb.get<any>(`
      SELECT
        COUNT(*) AS total_created,
        SUM(CASE WHEN ts.is_closed = 1 THEN 1 ELSE 0 END) AS total_closed,
        COALESCE(SUM(t.total), 0) AS total_revenue,
        COALESCE(AVG(t.total), 0) AS avg_ticket_value
      FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?
    `, from, to),
  ]);

  // Avg ACTIVE turnaround time (hours) for closed tickets — excludes hold/waiting time
  // Uses sync db for repair-time utils
  const closedIds = getClosedTicketIds(db, from, to);
  const avgTurnaround = calculateAvgActiveRepairTime(db, closedIds);

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
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);

  const rows = await adb.all<any>(`
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
  `, from, to, from, to, from, to, from, to);

  res.json({ success: true, data: { rows, from, to } });
}));

// ─── Inventory Report ─────────────────────────────────────────────────────────

router.get('/inventory', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;

  const [lowStock, valueSummary, outOfStockRow, topMoving] = await Promise.all([
    adb.all<any>(`
      SELECT id, name, sku, in_stock, reorder_level, retail_price, cost_price, item_type
      FROM inventory_items
      WHERE item_type != 'service' AND is_active = 1
        AND in_stock <= reorder_level
      ORDER BY in_stock ASC
      LIMIT 50
    `),
    adb.all<any>(`
      SELECT
        item_type,
        COUNT(*) AS item_count,
        SUM(in_stock) AS total_units,
        SUM(in_stock * cost_price) AS total_cost_value,
        SUM(in_stock * retail_price) AS total_retail_value
      FROM inventory_items
      WHERE is_active = 1 AND item_type != 'service'
      GROUP BY item_type
    `),
    // Out of stock items
    adb.get<any>(`
      SELECT COUNT(*) AS n FROM inventory_items
      WHERE is_active = 1 AND item_type != 'service' AND in_stock = 0
    `),
    // Top moving items (most used in repairs in last 30 days)
    adb.all<any>(`
      SELECT ii.name, ii.sku, SUM(tdp.quantity) AS used_qty, ii.in_stock
      FROM ticket_device_parts tdp
      JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
      JOIN ticket_devices td ON td.id = tdp.ticket_device_id
      JOIN tickets t ON t.id = td.ticket_id
      WHERE t.is_deleted = 0 AND DATE(t.created_at) >= DATE('now', '-30 days')
      GROUP BY ii.id
      ORDER BY used_qty DESC
      LIMIT 10
    `),
  ]);

  const outOfStock = outOfStockRow?.n ?? 0;

  res.json({ success: true, data: { lowStock, valueSummary, outOfStock, topMoving } });
}));

// ─── Tax Report ───────────────────────────────────────────────────────────────

router.get('/tax', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date().toISOString().slice(0, 7) + '-01';
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);

  // Try line-item tax first; fall back to invoice-level total_tax if line items have no tax data
  const lineItemRows = await adb.all<any>(`
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
  `, from, to);

  const hasLineItemTax = lineItemRows.some((r: any) => r.tax_collected > 0);

  const rows = hasLineItemTax ? lineItemRows : await adb.all<any>(`
    SELECT
      COALESCE(tc.name, 'Tax (from invoice totals)') AS tax_class,
      tc.rate,
      SUM(i.total_tax) AS tax_collected,
      SUM(i.total - i.total_tax) AS revenue
    FROM invoices i
    LEFT JOIN tax_classes tc ON tc.id = i.tax_class_id
    WHERE i.status != 'void' AND DATE(i.created_at) BETWEEN ? AND ?
      AND i.total_tax > 0
    GROUP BY i.tax_class_id
    ORDER BY tax_collected DESC
  `, from, to);

  res.json({ success: true, data: { rows, from, to } });
}));

// ─── Tech Workload ───────────────────────────────────────────────────────────

router.get('/tech-workload', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const db = req.db; // needed for sync calculateAvgActiveRepairTime
  const monthStart = new Date();
  monthStart.setDate(1);
  const monthStartStr = monthStart.toISOString().slice(0, 10);
  const todayStr = new Date().toISOString().slice(0, 10);

  const rows = await adb.all<any>(`
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
  `, monthStartStr, todayStr);

  // Batch-fetch closed ticket IDs for ALL techs in one query (avoids N+1).
  // Each tech previously triggered a separate getClosedTicketIds() call.
  const techIds = rows.map((r: any) => r.id);
  const closedByTech = new Map<number, number[]>();
  if (techIds.length > 0) {
    const placeholders = techIds.map(() => '?').join(',');
    const closedRows = await adb.all<{ id: number; assigned_to: number }>(`
      SELECT t.id, t.assigned_to
      FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.is_deleted = 0 AND ts.is_closed = 1
        AND t.assigned_to IN (${placeholders})
      ORDER BY t.created_at DESC
    `, ...techIds);
    for (const row of closedRows) {
      const list = closedByTech.get(row.assigned_to);
      if (list) { if (list.length < 200) list.push(row.id); }
      else closedByTech.set(row.assigned_to, [row.id]);
    }
  }

  // Calculate active repair time per tech (excludes hold/waiting statuses)
  // Uses sync db for calculateAvgActiveRepairTime
  const data = rows.map((r: any) => {
    const recentIds = closedByTech.get(r.id) ?? [];
    const avgHours = calculateAvgActiveRepairTime(db, recentIds);
    return {
      ...r,
      avg_repair_hours: avgHours ? Math.round(avgHours * 10) / 10 : 0,
      revenue_this_month: Math.round(r.revenue_this_month * 100) / 100,
    };
  });

  res.json({ success: true, data });
}));

// ─── Tip Report ──────────────────────────────────────────────────────────────

router.get('/tips', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);
  const groupBy = (req.query.group_by as string) || 'day'; // day | week

  // Daily/weekly tip totals
  const dateExpr = groupBy === 'week'
    ? "DATE(pt.created_at, 'weekday 1', '-7 days')"
    : "DATE(pt.created_at)";

  const [daily, byEmployee, summary] = await Promise.all([
    adb.all<any>(`
      SELECT
        ${dateExpr} AS period,
        COALESCE(SUM(pt.tip), 0) AS tip_total,
        COUNT(CASE WHEN pt.tip > 0 THEN 1 END) AS tip_count,
        COUNT(*) AS transaction_count
      FROM pos_transactions pt
      WHERE DATE(pt.created_at) BETWEEN ? AND ?
      GROUP BY period
      ORDER BY period DESC
    `, from, to),
    // Per-employee breakdown
    adb.all<any>(`
      SELECT
        u.id AS employee_id,
        u.first_name || ' ' || u.last_name AS employee_name,
        COALESCE(SUM(pt.tip), 0) AS tip_total,
        COUNT(CASE WHEN pt.tip > 0 THEN 1 END) AS tip_count,
        COUNT(*) AS transaction_count,
        CASE WHEN COUNT(CASE WHEN pt.tip > 0 THEN 1 END) > 0
          THEN ROUND(SUM(pt.tip) / COUNT(CASE WHEN pt.tip > 0 THEN 1 END), 2)
          ELSE 0 END AS avg_tip
      FROM pos_transactions pt
      JOIN users u ON u.id = pt.user_id
      WHERE DATE(pt.created_at) BETWEEN ? AND ?
      GROUP BY pt.user_id
      ORDER BY tip_total DESC
    `, from, to),
    // Summary totals
    adb.get<any>(`
      SELECT
        COALESCE(SUM(pt.tip), 0) AS total_tips,
        COUNT(CASE WHEN pt.tip > 0 THEN 1 END) AS tipped_transactions,
        COUNT(*) AS total_transactions,
        CASE WHEN COUNT(CASE WHEN pt.tip > 0 THEN 1 END) > 0
          THEN ROUND(SUM(pt.tip) / COUNT(CASE WHEN pt.tip > 0 THEN 1 END), 2)
          ELSE 0 END AS avg_tip,
        MAX(pt.tip) AS max_tip
      FROM pos_transactions pt
      WHERE DATE(pt.created_at) BETWEEN ? AND ?
    `, from, to),
  ]);

  res.json({
    success: true,
    data: {
      daily,
      by_employee: byEmployee,
      summary: {
        total_tips: summary?.total_tips ?? 0,
        tipped_transactions: summary?.tipped_transactions ?? 0,
        total_transactions: summary?.total_transactions ?? 0,
        avg_tip: summary?.avg_tip ?? 0,
        max_tip: summary?.max_tip ?? 0,
        tip_rate_pct: (summary?.total_transactions ?? 0) > 0
          ? Math.round((summary.tipped_transactions / summary.total_transactions) * 1000) / 10
          : 0,
      },
      from,
      to,
    },
  });
}));

// ─── Needs Attention ──────────────────────────────────────────────────────────

router.get('/needs-attention', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const today = new Date().toISOString().slice(0, 10);

  const [stale_tickets, missingPartsRow, overdue_invoices, lowStockRow] = await Promise.all([
    // Stale tickets: open, not updated in 3+ days
    adb.all<any>(`
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
    `),
    // Missing parts count (open tickets with parts that have status='missing' or in_stock < quantity)
    adb.get<any>(`
      SELECT COUNT(DISTINCT tdp.id) AS n
      FROM ticket_device_parts tdp
      JOIN ticket_devices td ON td.id = tdp.ticket_device_id
      JOIN tickets t ON t.id = td.ticket_id
      JOIN ticket_statuses ts ON ts.id = t.status_id
      LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
      WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
        AND ii.id IS NOT NULL AND ii.in_stock <= ii.reorder_level
    `),
    // Overdue invoices: unpaid/partial, past due_on
    adb.all<any>(`
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
    `, today),
    // Low stock count
    adb.get<any>(`
      SELECT COUNT(*) AS n FROM inventory_items
      WHERE item_type != 'service' AND is_active = 1 AND is_reorderable = 1
        AND in_stock <= reorder_level
    `),
  ]);

  const missing_parts_count = missingPartsRow?.n ?? 0;
  const low_stock_count = lowStockRow?.n ?? 0;

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

// ─── ENR-R1: Warranty Claims Report ──────────────────────────────────────────

router.get('/warranty-claims', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 365 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);

  const rows = await adb.all<any>(`
    SELECT
      td.device_name AS model,
      COUNT(*) AS claim_count,
      COALESCE(SUM(t.total), 0) AS total_cost,
      COALESCE(AVG(t.total), 0) AS avg_repair_cost
    FROM ticket_devices td
    JOIN tickets t ON t.id = td.ticket_id
    WHERE td.warranty = 1
      AND t.is_deleted = 0
      AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY td.device_name
    ORDER BY claim_count DESC
  `, from, to);

  res.json({ success: true, data: { rows, from, to } });
}));

// ─── ENR-R2: Device Model Report ────────────────────────────────────────────

router.get('/device-models', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 365 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);

  const rows = await adb.all<any>(`
    SELECT
      td.device_name AS model,
      COUNT(*) AS repair_count,
      COALESCE(AVG(t.total), 0) AS avg_ticket_total,
      COALESCE(SUM(
        (SELECT COALESCE(SUM(
          COALESCE(NULLIF(ii.cost_price, 0), 0) * tdp.quantity
        ), 0)
        FROM ticket_device_parts tdp
        JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
        WHERE tdp.ticket_device_id = td.id)
      ), 0) AS total_parts_cost
    FROM ticket_devices td
    JOIN tickets t ON t.id = td.ticket_id
    WHERE t.is_deleted = 0
      AND td.device_name IS NOT NULL AND td.device_name != ''
      AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY td.device_name
    ORDER BY repair_count DESC
  `, from, to);

  res.json({ success: true, data: { rows, from, to } });
}));

// ─── ENR-R3: Parts Usage Report ─────────────────────────────────────────────

router.get('/parts-usage', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 365 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);

  const rows = await adb.all<any>(`
    SELECT
      ii.name AS part_name,
      ii.sku,
      COUNT(*) AS usage_count,
      SUM(tdp.quantity) AS total_qty_used,
      COALESCE(SUM(COALESCE(NULLIF(ii.cost_price, 0), 0) * tdp.quantity), 0) AS total_cost,
      COALESCE(s.name, 'Unknown') AS supplier
    FROM ticket_device_parts tdp
    JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    JOIN ticket_devices td ON td.id = tdp.ticket_device_id
    JOIN tickets t ON t.id = td.ticket_id
    LEFT JOIN suppliers s ON s.id = ii.supplier_id
    WHERE t.is_deleted = 0
      AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY ii.id
    ORDER BY usage_count DESC
    LIMIT 20
  `, from, to);

  res.json({ success: true, data: { rows, from, to } });
}));

// ─── ENR-R4: Technician Billable Hours ──────────────────────────────────────

router.get('/technician-hours', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);

  const rows = await adb.all<any>(`
    SELECT
      u.first_name || ' ' || u.last_name AS tech_name,
      COALESCE(closed_counts.tickets_closed, 0) AS tickets_closed,
      COALESCE(rev.total_revenue, 0) AS total_revenue,
      COALESCE(hrs.hours_logged, 0) AS hours_logged
    FROM users u
    LEFT JOIN (
      SELECT t.assigned_to, COUNT(*) AS tickets_closed
      FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.is_deleted = 0 AND ts.is_closed = 1
        AND DATE(t.updated_at) BETWEEN ? AND ?
      GROUP BY t.assigned_to
    ) closed_counts ON closed_counts.assigned_to = u.id
    LEFT JOIN (
      SELECT t.assigned_to, COALESCE(SUM(t.total), 0) AS total_revenue
      FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.is_deleted = 0 AND ts.is_closed = 1
        AND DATE(t.updated_at) BETWEEN ? AND ?
      GROUP BY t.assigned_to
    ) rev ON rev.assigned_to = u.id
    LEFT JOIN (
      SELECT user_id, SUM(
        CASE WHEN clock_out IS NOT NULL
          THEN (JULIANDAY(clock_out) - JULIANDAY(clock_in)) * 24
          ELSE 0 END
      ) AS hours_logged
      FROM clock_entries
      WHERE DATE(clock_in) BETWEEN ? AND ?
      GROUP BY user_id
    ) hrs ON hrs.user_id = u.id
    WHERE u.is_active = 1
      AND (closed_counts.tickets_closed > 0 OR hrs.hours_logged > 0)
    ORDER BY tickets_closed DESC
  `, from, to, from, to, from, to);

  res.json({ success: true, data: { rows, from, to } });
}));

// ─── ENR-R5: Stalled Ticket Report ──────────────────────────────────────────

router.get('/stalled-tickets', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 365 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);

  const rows = await adb.all<any>(`
    SELECT
      COALESCE(u.first_name || ' ' || u.last_name, 'Unassigned') AS tech_name,
      COUNT(*) AS stalled_count,
      GROUP_CONCAT(t.order_id, ', ') AS ticket_ids,
      MIN(t.updated_at) AS oldest_update,
      MAX(CAST(JULIANDAY('now') - JULIANDAY(t.updated_at) AS INTEGER)) AS max_days_stalled
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN users u ON u.id = t.assigned_to
    WHERE t.is_deleted = 0
      AND ts.is_closed = 0 AND ts.is_cancelled = 0
      AND t.updated_at < datetime('now', '-7 days')
      AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY t.assigned_to
    ORDER BY stalled_count DESC
  `, from, to);

  res.json({ success: true, data: { rows, from, to } });
}));

// ─── ENR-R6: Customer Acquisition Report ────────────────────────────────────

router.get('/customer-acquisition', requireFeature('advancedReports'), asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 365 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);

  const [rows, monthly_totals] = await Promise.all([
    adb.all<any>(`
      SELECT
        STRFTIME('%Y-%m', created_at) AS month,
        COUNT(*) AS new_customers,
        COALESCE(referred_by, source, 'Unknown') AS acquisition_source
      FROM customers
      WHERE is_deleted = 0
        AND DATE(created_at) BETWEEN ? AND ?
      GROUP BY month, acquisition_source
      ORDER BY month DESC, new_customers DESC
    `, from, to),
    // Also provide a monthly summary without source breakdown
    adb.all<any>(`
      SELECT
        STRFTIME('%Y-%m', created_at) AS month,
        COUNT(*) AS new_customers
      FROM customers
      WHERE is_deleted = 0
        AND DATE(created_at) BETWEEN ? AND ?
      GROUP BY month
      ORDER BY month DESC
    `, from, to),
  ]);

  res.json({ success: true, data: { rows, monthly_totals, from, to } });
}));

// ─── ENR-R8: Report Comparison Mode ─────────────────────────────────────────

router.get('/comparison', requireFeature('advancedReports'), asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;

  const from1 = req.query.from1 as string;
  const to1 = req.query.to1 as string;
  const from2 = req.query.from2 as string;
  const to2 = req.query.to2 as string;

  if (!from1 || !to1 || !from2 || !to2) {
    throw new AppError('All four date params required: from1, to1, from2, to2', 400);
  }
  validateDateRange(from1, to1);
  validateDateRange(from2, to2);

  async function getMetrics(from: string, to: string) {
    const [revenue, tickets, customers, avgTicket] = await Promise.all([
      adb.get<any>(`
        SELECT
          COALESCE(SUM(p.amount), 0) +
          COALESCE(SUM(CASE WHEN p.id IS NULL AND i.amount_paid > 0 THEN i.amount_paid ELSE 0 END), 0) AS total
        FROM invoices i
        LEFT JOIN payments p ON p.invoice_id = i.id
        WHERE i.status != 'void'
          AND DATE(COALESCE(p.created_at, i.created_at)) BETWEEN ? AND ?
      `, from, to),
      adb.get<any>(`
        SELECT COUNT(*) AS total, COUNT(CASE WHEN ts.is_closed = 1 THEN 1 END) AS closed
        FROM tickets t
        JOIN ticket_statuses ts ON ts.id = t.status_id
        WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?
      `, from, to),
      adb.get<any>(`
        SELECT COUNT(*) AS new_customers
        FROM customers
        WHERE is_deleted = 0 AND DATE(created_at) BETWEEN ? AND ?
      `, from, to),
      adb.get<any>(`
        SELECT COALESCE(AVG(i.total), 0) AS avg_total
        FROM invoices i
        WHERE i.status != 'void' AND DATE(i.created_at) BETWEEN ? AND ?
      `, from, to),
    ]);

    return {
      revenue: revenue?.total ?? 0,
      tickets_created: tickets?.total ?? 0,
      tickets_closed: tickets?.closed ?? 0,
      new_customers: customers?.new_customers ?? 0,
      avg_ticket_value: Math.round((avgTicket?.avg_total ?? 0) * 100) / 100,
    };
  }

  const [period1, period2] = await Promise.all([
    getMetrics(from1, to1),
    getMetrics(from2, to2),
  ]);

  // Compute percentage changes
  function pctChange(a: number, b: number): number | null {
    if (a === 0) return b === 0 ? 0 : null;
    return Math.round(((b - a) / a) * 1000) / 10;
  }

  const changes = {
    revenue_pct: pctChange(period1.revenue, period2.revenue),
    tickets_created_pct: pctChange(period1.tickets_created, period2.tickets_created),
    tickets_closed_pct: pctChange(period1.tickets_closed, period2.tickets_closed),
    new_customers_pct: pctChange(period1.new_customers, period2.new_customers),
    avg_ticket_value_pct: pctChange(period1.avg_ticket_value, period2.avg_ticket_value),
  };

  res.json({
    success: true,
    data: {
      period1: { from: from1, to: to1, ...period1 },
      period2: { from: from2, to: to2, ...period2 },
      changes,
    },
  });
}));

// ─── ENR-R10: Saved Report Presets CRUD ─────────────────────────────────────

router.get('/presets', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const reportType = req.query.report_type as string | undefined;

  const conditions = ['user_id = ?'];
  const params: unknown[] = [userId];

  if (reportType) {
    conditions.push('report_type = ?');
    params.push(reportType);
  }

  const presets = await adb.all<any>(
    `SELECT * FROM report_presets WHERE ${conditions.join(' AND ')} ORDER BY is_default DESC, name ASC`,
    ...params,
  );

  res.json({ success: true, data: presets });
}));

router.post('/presets', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const { name, report_type, filters, is_default } = req.body;

  if (!name || typeof name !== 'string' || name.trim().length === 0) {
    throw new AppError('Preset name is required', 400);
  }
  if (!report_type || typeof report_type !== 'string') {
    throw new AppError('report_type is required', 400);
  }

  const filtersJson = typeof filters === 'string' ? filters : JSON.stringify(filters || {});

  // If marking as default, clear other defaults for this type
  if (is_default) {
    await adb.run(
      'UPDATE report_presets SET is_default = 0 WHERE user_id = ? AND report_type = ?',
      userId, report_type,
    );
  }

  const result = await adb.run(
    `INSERT INTO report_presets (user_id, name, report_type, filters, is_default) VALUES (?, ?, ?, ?, ?)`,
    userId, name.trim(), report_type, filtersJson, is_default ? 1 : 0,
  );

  const preset = await adb.get<any>('SELECT * FROM report_presets WHERE id = ?', result.lastInsertRowid);

  res.json({ success: true, data: preset });
}));

router.put('/presets/:presetId', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const presetId = Number(req.params.presetId);
  const { name, filters, is_default } = req.body;

  const existing = await adb.get<any>(
    'SELECT * FROM report_presets WHERE id = ? AND user_id = ?',
    presetId, userId,
  );
  if (!existing) throw new AppError('Preset not found', 404);

  const updates: string[] = [];
  const params: unknown[] = [];

  if (name !== undefined) {
    if (typeof name !== 'string' || name.trim().length === 0) {
      throw new AppError('Preset name cannot be empty', 400);
    }
    updates.push('name = ?');
    params.push(name.trim());
  }
  if (filters !== undefined) {
    updates.push('filters = ?');
    params.push(typeof filters === 'string' ? filters : JSON.stringify(filters));
  }
  if (is_default !== undefined) {
    if (is_default) {
      await adb.run(
        'UPDATE report_presets SET is_default = 0 WHERE user_id = ? AND report_type = ?',
        userId, existing.report_type,
      );
    }
    updates.push('is_default = ?');
    params.push(is_default ? 1 : 0);
  }

  if (updates.length === 0) {
    throw new AppError('No fields to update', 400);
  }

  updates.push("updated_at = datetime('now')");
  params.push(presetId, userId);

  await adb.run(
    `UPDATE report_presets SET ${updates.join(', ')} WHERE id = ? AND user_id = ?`,
    ...params,
  );

  const updated = await adb.get<any>('SELECT * FROM report_presets WHERE id = ?', presetId);
  res.json({ success: true, data: updated });
}));

router.delete('/presets/:presetId', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const presetId = Number(req.params.presetId);

  const existing = await adb.get<any>(
    'SELECT * FROM report_presets WHERE id = ? AND user_id = ?',
    presetId, userId,
  );
  if (!existing) throw new AppError('Preset not found', 404);

  await adb.run('DELETE FROM report_presets WHERE id = ? AND user_id = ?', presetId, userId);
  res.json({ success: true, data: { message: 'Preset deleted' } });
}));

// ─── ENR-R11: Profit Margin Trends ─────────────────────────────────────────

router.get('/margin-trends', requireFeature('advancedReports'), asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const months = Math.min(24, Math.max(1, parseInt(req.query.months as string, 10) || 12));

  // Revenue per month from payments + invoice fallback
  // COGS per month from ticket_device_parts cost (inventory cost_price * quantity)
  const rows = await adb.all<any>(`
    SELECT
      m.month,
      COALESCE(rev.revenue, 0) AS revenue,
      COALESCE(cogs.total_cost, 0) AS cogs,
      COALESCE(rev.revenue, 0) - COALESCE(cogs.total_cost, 0) AS gross_profit,
      -- RPT5: Never clamp or floor the margin. Let negative margins surface
      -- so the user sees unprofitable months. NULL only when revenue is 0
      -- (division by zero is undefined, not "0% margin").
      CASE
        WHEN COALESCE(rev.revenue, 0) > 0
        THEN ROUND((COALESCE(rev.revenue, 0) - COALESCE(cogs.total_cost, 0)) / rev.revenue * 100, 1)
        ELSE NULL
      END AS margin_pct
    FROM (
      -- Generate month series
      WITH RECURSIVE months_cte(month) AS (
        SELECT STRFTIME('%Y-%m', 'now', '-' || ? || ' months')
        UNION ALL
        SELECT STRFTIME('%Y-%m', month || '-01', '+1 month')
        FROM months_cte
        WHERE month < STRFTIME('%Y-%m', 'now')
      )
      SELECT month FROM months_cte
    ) m
    LEFT JOIN (
      -- Revenue: payments + imported invoice fallback
      SELECT
        STRFTIME('%Y-%m', COALESCE(p.created_at, i.created_at)) AS month,
        COALESCE(SUM(p.amount), 0) +
        COALESCE(SUM(CASE WHEN p.id IS NULL AND i.amount_paid > 0 THEN i.amount_paid ELSE 0 END), 0) AS revenue
      FROM invoices i
      LEFT JOIN payments p ON p.invoice_id = i.id
      WHERE i.status != 'void'
        AND DATE(COALESCE(p.created_at, i.created_at)) >= DATE('now', '-' || ? || ' months')
      GROUP BY STRFTIME('%Y-%m', COALESCE(p.created_at, i.created_at))
    ) rev ON rev.month = m.month
    LEFT JOIN (
      -- RPT6: COGS — LEFT JOIN on inventory_items so parts whose inventory row
      -- is missing or deleted still contribute to the month count (with cost 0),
      -- instead of silently dropping the whole ticket_device_part row.
      SELECT
        STRFTIME('%Y-%m', t.created_at) AS month,
        SUM(COALESCE(ii.cost_price, 0) * tdp.quantity) AS total_cost
      FROM ticket_device_parts tdp
      JOIN ticket_devices td ON td.id = tdp.ticket_device_id
      JOIN tickets t ON t.id = td.ticket_id
      LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
      WHERE t.is_deleted = 0
        AND DATE(t.created_at) >= DATE('now', '-' || ? || ' months')
      GROUP BY STRFTIME('%Y-%m', t.created_at)
    ) cogs ON cogs.month = m.month
    ORDER BY m.month ASC
  `, months - 1, months, months);

  // Summary totals — RPT5: use NULL (not 0) when total revenue is 0 so the UI
  // can distinguish "no data" from "break even" and negative overall margins
  // are preserved honestly.
  const totalRevenue = rows.reduce((s: number, r: any) => s + (r.revenue || 0), 0);
  const totalCogs = rows.reduce((s: number, r: any) => s + (r.cogs || 0), 0);
  const totalProfit = totalRevenue - totalCogs;
  const overallMargin = totalRevenue > 0 ? Math.round((totalProfit / totalRevenue) * 1000) / 10 : null;

  res.json({
    success: true,
    data: {
      rows,
      summary: {
        total_revenue: Math.round(totalRevenue * 100) / 100,
        total_cogs: Math.round(totalCogs * 100) / 100,
        total_profit: Math.round(totalProfit * 100) / 100,
        overall_margin_pct: overallMargin,
      },
      months,
    },
  });
}));

// ─── ENR-R7: Report Export to CSV ───────────────────────────────────────────

// Helper: convert array of objects to CSV string
function toCsv(rows: Record<string, unknown>[]): string {
  if (rows.length === 0) return '';
  const headers = Object.keys(rows[0]);
  const csvLines = [headers.join(',')];
  for (const row of rows) {
    const values = headers.map(h => {
      const val = row[h];
      if (val == null) return '';
      const str = String(val);
      // Escape fields containing commas, quotes, or newlines
      if (str.includes(',') || str.includes('"') || str.includes('\n')) {
        return '"' + str.replace(/"/g, '""') + '"';
      }
      return str;
    });
    csvLines.push(values.join(','));
  }
  return csvLines.join('\n');
}

// Map of report types to their async query functions
const reportQueries: Record<string, (adb: any, from: string, to: string) => Promise<Record<string, unknown>[]>> = {
  'warranty-claims': (adb, from, to) => adb.all(`
    SELECT td.device_name AS model, COUNT(*) AS claim_count,
      COALESCE(SUM(t.total), 0) AS total_cost, COALESCE(AVG(t.total), 0) AS avg_repair_cost
    FROM ticket_devices td JOIN tickets t ON t.id = td.ticket_id
    WHERE td.warranty = 1 AND t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY td.device_name ORDER BY claim_count DESC
  `, from, to),

  'device-models': (adb, from, to) => adb.all(`
    SELECT td.device_name AS model, COUNT(*) AS repair_count,
      COALESCE(AVG(t.total), 0) AS avg_ticket_total
    FROM ticket_devices td JOIN tickets t ON t.id = td.ticket_id
    WHERE t.is_deleted = 0 AND td.device_name IS NOT NULL AND td.device_name != ''
      AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY td.device_name ORDER BY repair_count DESC
  `, from, to),

  'parts-usage': (adb, from, to) => adb.all(`
    SELECT ii.name AS part_name, ii.sku, COUNT(*) AS usage_count, SUM(tdp.quantity) AS total_qty_used,
      COALESCE(SUM(COALESCE(NULLIF(ii.cost_price, 0), 0) * tdp.quantity), 0) AS total_cost,
      COALESCE(s.name, 'Unknown') AS supplier
    FROM ticket_device_parts tdp
    JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    JOIN ticket_devices td ON td.id = tdp.ticket_device_id
    JOIN tickets t ON t.id = td.ticket_id
    LEFT JOIN suppliers s ON s.id = ii.supplier_id
    WHERE t.is_deleted = 0 AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY ii.id ORDER BY usage_count DESC LIMIT 20
  `, from, to),

  'technician-hours': (adb, from, to) => adb.all(`
    SELECT u.first_name || ' ' || u.last_name AS tech_name,
      COALESCE(cc.tickets_closed, 0) AS tickets_closed,
      COALESCE(rev.total_revenue, 0) AS total_revenue,
      COALESCE(hrs.hours_logged, 0) AS hours_logged
    FROM users u
    LEFT JOIN (SELECT assigned_to, COUNT(*) AS tickets_closed FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.is_deleted = 0 AND ts.is_closed = 1 AND DATE(t.updated_at) BETWEEN ? AND ?
      GROUP BY assigned_to) cc ON cc.assigned_to = u.id
    LEFT JOIN (SELECT assigned_to, SUM(total) AS total_revenue FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.is_deleted = 0 AND ts.is_closed = 1 AND DATE(t.updated_at) BETWEEN ? AND ?
      GROUP BY assigned_to) rev ON rev.assigned_to = u.id
    LEFT JOIN (SELECT user_id, SUM(CASE WHEN clock_out IS NOT NULL
      THEN (JULIANDAY(clock_out) - JULIANDAY(clock_in)) * 24 ELSE 0 END) AS hours_logged
      FROM clock_entries WHERE DATE(clock_in) BETWEEN ? AND ? GROUP BY user_id) hrs ON hrs.user_id = u.id
    WHERE u.is_active = 1 AND (cc.tickets_closed > 0 OR hrs.hours_logged > 0)
    ORDER BY tickets_closed DESC
  `, from, to, from, to, from, to),

  'stalled-tickets': (adb, from, to) => adb.all(`
    SELECT COALESCE(u.first_name || ' ' || u.last_name, 'Unassigned') AS tech_name,
      COUNT(*) AS stalled_count, GROUP_CONCAT(t.order_id, ', ') AS ticket_ids,
      MIN(t.updated_at) AS oldest_update,
      MAX(CAST(JULIANDAY('now') - JULIANDAY(t.updated_at) AS INTEGER)) AS max_days_stalled
    FROM tickets t JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN users u ON u.id = t.assigned_to
    WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
      AND t.updated_at < datetime('now', '-7 days') AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY t.assigned_to ORDER BY stalled_count DESC
  `, from, to),

  'customer-acquisition': (adb, from, to) => adb.all(`
    SELECT STRFTIME('%Y-%m', created_at) AS month, COUNT(*) AS new_customers,
      COALESCE(referred_by, source, 'Unknown') AS acquisition_source
    FROM customers WHERE is_deleted = 0 AND DATE(created_at) BETWEEN ? AND ?
    GROUP BY month, acquisition_source ORDER BY month DESC, new_customers DESC
  `, from, to),
};

router.get('/:type/export', requireFeature('exportReports'), asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const reportType = req.params.type as string;
  const format = (req.query.format as string) || 'csv';

  if (format !== 'csv') {
    throw new AppError('Only CSV format is supported', 400);
  }

  const queryFn = reportQueries[reportType];
  if (!queryFn) {
    throw new AppError(`Unknown report type: ${reportType}`, 400);
  }

  const from = (req.query.from_date as string) || new Date(Date.now() - 365 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateDateRange(from, to);

  const rows = await queryFn(adb, from, to);
  const csv = toCsv(rows as Record<string, unknown>[]);

  res.setHeader('Content-Type', 'text/csv');
  res.setHeader('Content-Disposition', `attachment; filename="${reportType}-${from}-to-${to}.csv"`);
  res.send(csv);
}));

// ─── Cash Flow Forecast (ENR-R12) ────────────────────────────────────────────

router.get('/cash-flow-forecast', requireFeature('advancedReports'), asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb: AsyncDb = req.asyncDb;

  // Receivables: total outstanding on unpaid/partial invoices
  const receivablesRow = await adb.get<{ total: number }>(
    `SELECT COALESCE(SUM(total - amount_paid), 0) AS total
     FROM invoices
     WHERE status IN ('unpaid', 'partial')`
  );

  // Overdue receivables: subset that are past due
  const overdueRow = await adb.get<{ total: number }>(
    `SELECT COALESCE(SUM(total - amount_paid), 0) AS total
     FROM invoices
     WHERE status IN ('unpaid', 'partial')
       AND due_on IS NOT NULL AND due_on < date('now')`
  );

  // Payables: expenses recorded in the last 30 days (proxy for upcoming costs)
  const payablesRow = await adb.get<{ total: number }>(
    `SELECT COALESCE(SUM(amount), 0) AS total
     FROM expenses
     WHERE date >= date('now', '-30 days')`
  );

  const receivables = receivablesRow?.total ?? 0;
  const overdueReceivables = overdueRow?.total ?? 0;
  const payables = payablesRow?.total ?? 0;

  res.json({
    success: true,
    data: {
      receivables,
      overdueReceivables,
      payables,
      net: receivables - payables,
    },
  });
}));

export default router;
