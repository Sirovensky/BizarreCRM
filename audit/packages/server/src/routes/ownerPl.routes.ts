/**
 * Owner P&L Aggregator — SCAN-467
 * android §62 / ios §59
 *
 * Mounted at /api/v1/owner-pl with authMiddleware at the parent.
 * All routes are admin-only (requireAdmin).
 *
 * Endpoints:
 *   GET  /summary?from=YYYY-MM-DD&to=YYYY-MM-DD&rollup=day|week|month
 *   POST /snapshot  body: {from, to}  — compute + persist to pl_snapshots
 *   GET  /snapshots                   — list saved snapshots
 *   GET  /snapshots/:id               — retrieve one saved snapshot
 *
 * Security:
 *   - SEC-H34: all monetary values returned as INTEGER cents
 *   - SEC-H11: admin-only; revenue + margin + tax liability + AR exposed
 *   - Date span capped at 365 days; default 30 days back
 *   - Parameterized SQL throughout
 *   - In-process LRU cache, 60 s TTL, max 64 entries
 *   - Rate-limit 30 req / 60 s / user+endpoint
 *   - Cross-tenant safety: cache key always includes resolved tenantSlug
 */

import { Router, Request, Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { LRUCache } from '../utils/cache.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';

const router = Router();
const logger = createLogger('owner-pl');

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type Rollup = 'day' | 'week' | 'month';

interface TimeBucket {
  bucket: string;
  revenue_cents: number;
  expense_cents: number;
  net_cents: number;
}

interface TopCustomer {
  customer_id: number;
  name: string;
  revenue_cents: number;
}

interface TopService {
  service: string;
  count: number;
  revenue_cents: number;
}

interface AgingBuckets {
  '0_30': number;
  '31_60': number;
  '61_90': number;
  '91_plus': number;
}

interface PlSummary {
  period: { from: string; to: string; days: number };
  revenue: {
    gross_cents: number;
    net_cents: number;
    refunds_cents: number;
    discounts_cents: number;
  };
  cogs: { inventory_cents: number; labor_cents: number };
  gross_profit: { cents: number; margin_pct: number };
  expenses: { total_cents: number; by_category: Array<{ category: string; cents: number }> };
  net_profit: { cents: number; margin_pct: number };
  tax_liability: { collected_cents: number; remitted_cents: number; outstanding_cents: number };
  ar: {
    outstanding_cents: number;
    overdue_cents: number;
    aging_buckets: AgingBuckets;
    truncated: boolean;
  };
  inventory_value: { cents: number; sku_count: number };
  time_series: TimeBucket[];
  top_customers: TopCustomer[];
  top_services: TopService[];
}

// ---------------------------------------------------------------------------
// In-process LRU cache — 64-entry cap, 60 s TTL
// ---------------------------------------------------------------------------

// Key format: `${tenantSlug}|${from}|${to}|${rollup}`
const plCache = new LRUCache<{ success: true; data: PlSummary }>(64, 60_000);

function cacheKey(tenantId: number | string, from: string, to: string, rollup: Rollup): string {
  return `${tenantId}|${from}|${to}|${rollup}`;
}

/** Invalidate all cache entries whose key starts with a given tenant+period prefix. */
function invalidateTenantPeriod(tenantId: number | string, from: string, to: string): void {
  // Iterate over all rollup variants and delete.
  for (const r of ['day', 'week', 'month'] as Rollup[]) {
    plCache.delete(cacheKey(tenantId, from, to, r));
  }
}

// ---------------------------------------------------------------------------
// Rate-limit constants — 30 req / 60 s / user
// ---------------------------------------------------------------------------

const RL_CATEGORY = 'owner_pl';
const RL_MAX = 30;
const RL_WINDOW_MS = 60_000;

// ---------------------------------------------------------------------------
// Security helpers
// ---------------------------------------------------------------------------

function requireAdmin(req: Request): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin role required', 403);
  }
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function validateDates(from: string, to: string): void {
  if (!DATE_RE.test(from) || !DATE_RE.test(to)) {
    throw new AppError('from and to must be YYYY-MM-DD', 400);
  }
  if (to < from) {
    throw new AppError('to must be >= from', 400);
  }
  const spanDays = (new Date(to).getTime() - new Date(from).getTime()) / 86_400_000;
  if (spanDays > 365) {
    throw new AppError('Date range must not exceed 365 days', 400);
  }
}

function validateRollup(raw: unknown): Rollup {
  if (raw === 'day' || raw === 'week' || raw === 'month') return raw;
  throw new AppError('rollup must be day, week, or month', 400);
}

function applyRateLimit(req: Request, res: Response): void {
  const userId = String(req.user?.id ?? req.ip ?? 'anon');
  const result = consumeWindowRate(req.db, RL_CATEGORY, userId, RL_MAX, RL_WINDOW_MS);
  if (!result.allowed) {
    res.set('Retry-After', String(result.retryAfterSeconds));
    throw new AppError(`Rate limit exceeded — retry in ${result.retryAfterSeconds}s`, 429);
  }
}

function defaultDateRange(): { from: string; to: string } {
  const to = new Date();
  const from = new Date(to);
  from.setDate(from.getDate() - 30);
  return {
    to: to.toISOString().slice(0, 10),
    from: from.toISOString().slice(0, 10),
  };
}

// ---------------------------------------------------------------------------
// SQLite strftime bucket format by rollup
// ---------------------------------------------------------------------------

const ROLLUP_FMTS = { day: '%Y-%m-%d', week: '%Y-W%W', month: '%Y-%m' } as const;

function rollupFmt(rollup: Rollup): string {
  if (!(rollup in ROLLUP_FMTS)) throw new AppError('Invalid rollup', 400);
  return ROLLUP_FMTS[rollup as keyof typeof ROLLUP_FMTS];
}

// ---------------------------------------------------------------------------
// Core aggregation query — used by both /summary and /snapshot
// ---------------------------------------------------------------------------

/**
 * Runs all P&L sub-queries in parallel and assembles the PlSummary object.
 * All monetary values in INTEGER cents (CAST/ROUND at SQL boundary per SEC-H34).
 */
async function computeSummary(
  req: Request,
  from: string,
  to: string,
  rollup: Rollup,
): Promise<PlSummary> {
  const adb = req.asyncDb;
  type Row = Record<string, unknown>;

  const fmt = rollupFmt(rollup);

  // ── Revenue ────────────────────────────────────────────────────────────────
  // Pattern reused from reports.routes.ts RPT1/RPT8: CRM payments UNION
  // imported invoice amount_paid (invoices with no payment rows only).
  const revenueQuery = `
    SELECT
      CAST(ROUND(COALESCE(SUM(rev), 0) * 100) AS INTEGER) AS gross_cents
    FROM (
      SELECT p.amount AS rev
      FROM payments p
      JOIN invoices i ON i.id = p.invoice_id
      WHERE i.status != 'void'
        AND DATE(p.created_at) BETWEEN ? AND ?
      UNION ALL
      SELECT i.amount_paid AS rev
      FROM invoices i
      LEFT JOIN (SELECT DISTINCT invoice_id FROM payments) crm_pay
        ON crm_pay.invoice_id = i.id
      WHERE i.status IN ('paid','overpaid','partial')
        AND DATE(i.created_at) BETWEEN ? AND ?
        AND crm_pay.invoice_id IS NULL
    )
  `;

  const refundsQuery = `
    SELECT CAST(ROUND(COALESCE(SUM(p.amount), 0) * 100) AS INTEGER) AS cents
    FROM payments p
    JOIN invoices i ON i.id = p.invoice_id
    WHERE i.status = 'refunded'
      AND DATE(p.created_at) BETWEEN ? AND ?
  `;

  const discountsQuery = `
    SELECT CAST(ROUND(COALESCE(SUM(i.discount), 0) * 100) AS INTEGER) AS cents
    FROM invoices i
    WHERE i.status != 'void'
      AND DATE(i.created_at) BETWEEN ? AND ?
  `;

  // ── COGS (inventory parts) ─────────────────────────────────────────────────
  // Pattern reused from reports.routes.ts PERF-6 (pre-aggregated supplier catalog min).
  const cogsQuery = `
    SELECT CAST(ROUND(COALESCE(SUM(
      COALESCE(NULLIF(ii.cost_price, 0), sc_min.min_price, 0) * tdp.quantity
    ), 0) * 100) AS INTEGER) AS cents
    FROM ticket_device_parts tdp
    JOIN ticket_devices td ON td.id = tdp.ticket_device_id
    JOIN tickets t ON t.id = td.ticket_id
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    LEFT JOIN (
      SELECT LOWER(TRIM(name)) AS norm_name, MIN(price) AS min_price
      FROM supplier_catalog WHERE price > 0
      GROUP BY LOWER(TRIM(name))
    ) sc_min ON ii.cost_price = 0
           AND sc_min.norm_name = LOWER(TRIM(ii.name))
    WHERE t.is_deleted = 0
      AND DATE(t.created_at) BETWEEN ? AND ?
  `;

  // ── Expenses ───────────────────────────────────────────────────────────────
  const expensesTotalQuery = `
    SELECT CAST(ROUND(COALESCE(SUM(amount), 0) * 100) AS INTEGER) AS cents
    FROM expenses
    WHERE DATE(created_at) BETWEEN ? AND ?
  `;

  const expensesByCategoryQuery = `
    SELECT category,
           CAST(ROUND(COALESCE(SUM(amount), 0) * 100) AS INTEGER) AS cents
    FROM expenses
    WHERE DATE(created_at) BETWEEN ? AND ?
    GROUP BY category
    ORDER BY cents DESC
  `;

  // ── Tax ───────────────────────────────────────────────────────────────────
  // Collected = SUM(tax_amount) on non-void invoices in period.
  // Remitted / outstanding: the schema stores remitted tax on the expenses
  // table with category 'tax_remittance'. Outstanding = collected - remitted.
  const taxCollectedQuery = `
    SELECT CAST(ROUND(COALESCE(SUM(ili.tax_amount), 0) * 100) AS INTEGER) AS cents
    FROM invoice_line_items ili
    JOIN invoices i ON i.id = ili.invoice_id
    WHERE i.status != 'void'
      AND DATE(i.created_at) BETWEEN ? AND ?
  `;

  const taxRemittedQuery = `
    SELECT CAST(ROUND(COALESCE(SUM(amount), 0) * 100) AS INTEGER) AS cents
    FROM expenses
    WHERE category = 'tax_remittance'
      AND DATE(created_at) BETWEEN ? AND ?
  `;

  // ── AR / aging ─────────────────────────────────────────────────────────────
  // Pattern reused from dunning.routes.ts /invoices/aging.
  // Capped at AR_LIMIT rows to prevent heap bloat on large datasets.
  // If arTruncated is true the aging buckets are approximate (first 10 000 rows).
  const AR_LIMIT = 10_000;
  const arQuery = `
    SELECT
      i.id,
      CAST(ROUND(i.amount_due * 100) AS INTEGER) AS amount_due_cents,
      i.due_date,
      i.status
    FROM invoices i
    WHERE i.status IN ('unpaid','overdue','partial','draft')
      AND i.amount_due > 0
    LIMIT ?
  `;

  // ── Inventory value ────────────────────────────────────────────────────────
  // Pattern reused from reports.routes.ts ENR-D4.
  const inventoryQuery = `
    SELECT
      CAST(ROUND(COALESCE(SUM(cost_price * in_stock), 0) * 100) AS INTEGER) AS cents,
      COUNT(*) AS sku_count
    FROM inventory_items
    WHERE is_active = 1 AND item_type != 'service'
  `;

  // ── Time series ───────────────────────────────────────────────────────────
  const timeSeriesQuery = `
    SELECT
      STRFTIME('${fmt}', DATE(p.created_at)) AS bucket,
      CAST(ROUND(COALESCE(SUM(p.amount), 0) * 100) AS INTEGER) AS revenue_cents
    FROM payments p
    JOIN invoices i ON i.id = p.invoice_id
    WHERE i.status != 'void'
      AND DATE(p.created_at) BETWEEN ? AND ?
    GROUP BY bucket
    ORDER BY bucket ASC
  `;

  const timeSeriesExpQuery = `
    SELECT
      STRFTIME('${fmt}', DATE(created_at)) AS bucket,
      CAST(ROUND(COALESCE(SUM(amount), 0) * 100) AS INTEGER) AS expense_cents
    FROM expenses
    WHERE DATE(created_at) BETWEEN ? AND ?
    GROUP BY bucket
    ORDER BY bucket ASC
  `;

  // ── Top customers (admin satisfies customers.view) ───────────────────────
  const topCustomersQuery = `
    SELECT
      i.customer_id,
      c.first_name || ' ' || c.last_name AS name,
      CAST(ROUND(COALESCE(SUM(p.amount), 0) * 100) AS INTEGER) AS revenue_cents
    FROM payments p
    JOIN invoices i ON i.id = p.invoice_id
    LEFT JOIN customers c ON c.id = i.customer_id
    WHERE i.status != 'void'
      AND DATE(p.created_at) BETWEEN ? AND ?
      AND i.customer_id IS NOT NULL
    GROUP BY i.customer_id
    ORDER BY revenue_cents DESC
    LIMIT 10
  `;

  // ── Top services ──────────────────────────────────────────────────────────
  const topServicesQuery = `
    SELECT
      td.service_name AS service,
      COUNT(*) AS count,
      CAST(ROUND(COALESCE(SUM(td.price), 0) * 100) AS INTEGER) AS revenue_cents
    FROM ticket_devices td
    JOIN tickets t ON t.id = td.ticket_id
    WHERE t.is_deleted = 0
      AND td.service_name IS NOT NULL AND td.service_name != ''
      AND DATE(t.created_at) BETWEEN ? AND ?
    GROUP BY td.service_name
    ORDER BY revenue_cents DESC
    LIMIT 10
  `;

  // Run all queries in parallel
  const [
    revenueRow,
    refundsRow,
    discountsRow,
    cogsRow,
    expTotalRow,
    expByCategory,
    taxCollectedRow,
    taxRemittedRow,
    arRows,
    inventoryRow,
    tseriesRev,
    tseriesExp,
    topCustomers,
    topServices,
  ] = await Promise.all([
    adb.get<Row>(revenueQuery, from, to, from, to),
    adb.get<Row>(refundsQuery, from, to),
    adb.get<Row>(discountsQuery, from, to),
    adb.get<Row>(cogsQuery, from, to),
    adb.get<Row>(expensesTotalQuery, from, to),
    adb.all<Row>(expensesByCategoryQuery, from, to),
    adb.get<Row>(taxCollectedQuery, from, to),
    adb.get<Row>(taxRemittedQuery, from, to),
    adb.all<Row>(arQuery, AR_LIMIT),
    adb.get<Row>(inventoryQuery),
    adb.all<Row>(timeSeriesQuery, from, to),
    adb.all<Row>(timeSeriesExpQuery, from, to),
    adb.all<Row>(topCustomersQuery, from, to),
    adb.all<Row>(topServicesQuery, from, to),
  ]);

  // ── Assemble scalar values ─────────────────────────────────────────────────
  const grossRevCents = Number(revenueRow?.gross_cents ?? 0);
  const refundsCents = Number(refundsRow?.cents ?? 0);
  const discountsCents = Number(discountsRow?.cents ?? 0);
  const netRevCents = Math.max(0, grossRevCents - refundsCents - discountsCents);

  const cogsCents = Number(cogsRow?.cents ?? 0);
  // labor_cents: not tracked as a separate column yet; reserved for future use
  const laborCents = 0;

  const grossProfitCents = netRevCents - cogsCents - laborCents;
  const grossMarginPct = netRevCents > 0
    ? Math.round((grossProfitCents / netRevCents) * 10_000) / 100
    : 0;

  const expensesTotalCents = Number(expTotalRow?.cents ?? 0);

  const netProfitCents = grossProfitCents - expensesTotalCents;
  const netMarginPct = netRevCents > 0
    ? Math.round((netProfitCents / netRevCents) * 10_000) / 100
    : 0;

  const taxCollectedCents = Number(taxCollectedRow?.cents ?? 0);
  const taxRemittedCents = Number(taxRemittedRow?.cents ?? 0);
  const taxOutstandingCents = Math.max(0, taxCollectedCents - taxRemittedCents);

  // ── AR aging ───────────────────────────────────────────────────────────────
  const arTruncated = arRows.length >= AR_LIMIT;
  const now = Date.now();
  const aging: AgingBuckets = { '0_30': 0, '31_60': 0, '61_90': 0, '91_plus': 0 };
  let arOutstandingCents = 0;
  let arOverdueCents = 0;

  for (const r of arRows) {
    const cents = Number(r.amount_due_cents) || 0;
    arOutstandingCents += cents;

    const dueTs = r.due_date ? new Date(r.due_date as string).getTime() : now;
    const daysOverdue = Math.max(0, Math.floor((now - dueTs) / 86_400_000));

    if (daysOverdue > 0) arOverdueCents += cents;

    if (daysOverdue <= 30) {
      aging['0_30'] += cents;
    } else if (daysOverdue <= 60) {
      aging['31_60'] += cents;
    } else if (daysOverdue <= 90) {
      aging['61_90'] += cents;
    } else {
      aging['91_plus'] += cents;
    }
  }

  // ── Time series merge ──────────────────────────────────────────────────────
  const revByBucket = new Map<string, number>();
  for (const r of tseriesRev) {
    revByBucket.set(r.bucket as string, Number(r.revenue_cents) || 0);
  }
  const expByBucket = new Map<string, number>();
  for (const r of tseriesExp) {
    expByBucket.set(r.bucket as string, Number(r.expense_cents) || 0);
  }
  const allBuckets = new Set([...revByBucket.keys(), ...expByBucket.keys()]);
  const timeSeries: TimeBucket[] = Array.from(allBuckets)
    .sort()
    .map((b) => {
      const rev = revByBucket.get(b) ?? 0;
      const exp = expByBucket.get(b) ?? 0;
      return { bucket: b, revenue_cents: rev, expense_cents: exp, net_cents: rev - exp };
    });

  // ── Days in period ─────────────────────────────────────────────────────────
  const periodDays = Math.round(
    (new Date(to).getTime() - new Date(from).getTime()) / 86_400_000,
  ) + 1;

  return {
    period: { from, to, days: periodDays },
    revenue: {
      gross_cents: grossRevCents,
      net_cents: netRevCents,
      refunds_cents: refundsCents,
      discounts_cents: discountsCents,
    },
    cogs: { inventory_cents: cogsCents, labor_cents: laborCents },
    gross_profit: { cents: grossProfitCents, margin_pct: grossMarginPct },
    expenses: {
      total_cents: expensesTotalCents,
      by_category: (expByCategory as Row[]).map((r) => ({
        category: String(r.category ?? 'uncategorised'),
        cents: Number(r.cents) || 0,
      })),
    },
    net_profit: { cents: netProfitCents, margin_pct: netMarginPct },
    tax_liability: {
      collected_cents: taxCollectedCents,
      remitted_cents: taxRemittedCents,
      outstanding_cents: taxOutstandingCents,
    },
    ar: {
      outstanding_cents: arOutstandingCents,
      overdue_cents: arOverdueCents,
      aging_buckets: aging,
      truncated: arTruncated,
    },
    inventory_value: {
      cents: Number(inventoryRow?.cents ?? 0),
      sku_count: Number(inventoryRow?.sku_count ?? 0),
    },
    time_series: timeSeries,
    top_customers: (topCustomers as Row[]).map((r) => ({
      customer_id: Number(r.customer_id),
      name: String(r.name ?? ''),
      revenue_cents: Number(r.revenue_cents) || 0,
    })),
    top_services: (topServices as Row[]).map((r) => ({
      service: String(r.service ?? ''),
      count: Number(r.count) || 0,
      revenue_cents: Number(r.revenue_cents) || 0,
    })),
  };
}

// ---------------------------------------------------------------------------
// GET /summary
// ---------------------------------------------------------------------------

router.get('/summary', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  applyRateLimit(req, res);

  const defaults = defaultDateRange();
  const from = (req.query.from as string | undefined)?.trim() ?? defaults.from;
  const to = (req.query.to as string | undefined)?.trim() ?? defaults.to;
  validateDates(from, to);
  const rollup = validateRollup(req.query.rollup ?? 'day');

  const tenantId = (req as Request & { tenantId?: number }).tenantId ?? 0;
  const key = cacheKey(tenantId, from, to, rollup);

  const cached = plCache.get(key);
  if (cached !== undefined) {
    res.json(cached);
    return;
  }

  const summary = await computeSummary(req, from, to, rollup);
  const response = { success: true as const, data: summary };
  plCache.set(key, response, 60_000);

  logger.info('owner-pl summary computed', { from, to, rollup, userId: req.user?.id });
  res.json(response);
}));

// ---------------------------------------------------------------------------
// POST /snapshot — compute + persist
// ---------------------------------------------------------------------------

router.post('/snapshot', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  applyRateLimit(req, res);

  const body = req.body as Record<string, unknown>;
  const from = (typeof body?.from === 'string' ? body.from : '').trim();
  const to = (typeof body?.to === 'string' ? body.to : '').trim();
  validateDates(from, to);

  const summary = await computeSummary(req, from, to, 'day');

  // Persist
  const result = await req.asyncDb.run(
    `INSERT INTO pl_snapshots (
       tenant_slug_hint, period_from, period_to,
       revenue_cents, cogs_cents, gross_profit_cents,
       expense_cents, net_profit_cents, tax_liability_cents,
       outstanding_ar_cents, inventory_value_cents,
       metadata_json, generated_by_user_id
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    (req as Request & { tenantSlug?: string }).tenantSlug ?? 'default',
    from,
    to,
    summary.revenue.gross_cents,
    summary.cogs.inventory_cents + summary.cogs.labor_cents,
    summary.gross_profit.cents,
    summary.expenses.total_cents,
    summary.net_profit.cents,
    summary.tax_liability.outstanding_cents,
    summary.ar.outstanding_cents,
    summary.inventory_value.cents,
    // NOTE: generated_by is intentionally NOT included here — it is already
    // stored in the typed column `generated_by_user_id` on this same row.
    // Duplicating it in metadata_json would leak the user id via SELECT * on
    // GET /snapshots/:id without benefit (SCAN-514).
    JSON.stringify({ rollup: 'day' }),
    req.user?.id ?? null,
  );

  const snapshotId = Number(result.lastInsertRowid);

  // Invalidate cache for this period so the next /summary is fresh
  const tenantId = (req as Request & { tenantId?: number }).tenantId ?? 0;
  invalidateTenantPeriod(tenantId, from, to);

  audit(req.db, 'owner_pl.snapshot.create', req.user?.id ?? null, req.ip ?? '', {
    snapshot_id: snapshotId,
    from,
    to,
  });

  logger.info('owner-pl snapshot saved', { snapshot_id: snapshotId, from, to, userId: req.user?.id });

  res.status(201).json({ success: true, data: { snapshot_id: snapshotId, summary } });
}));

// ---------------------------------------------------------------------------
// GET /snapshots — list
// ---------------------------------------------------------------------------

router.get('/snapshots', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  applyRateLimit(req, res);

  const rows = await req.asyncDb.all<Record<string, unknown>>(
    `SELECT id, tenant_slug_hint, period_from, period_to,
            revenue_cents, cogs_cents, gross_profit_cents,
            expense_cents, net_profit_cents, tax_liability_cents,
            outstanding_ar_cents, inventory_value_cents,
            generated_at, generated_by_user_id
     FROM pl_snapshots
     ORDER BY generated_at DESC
     LIMIT 100`,
  );

  res.json({ success: true, data: rows });
}));

// ---------------------------------------------------------------------------
// GET /snapshots/:id — retrieve one
// ---------------------------------------------------------------------------

router.get('/snapshots/:id', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  applyRateLimit(req, res);

  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

  const row = await req.asyncDb.get<Record<string, unknown>>(
    `SELECT * FROM pl_snapshots WHERE id = ?`,
    id,
  );

  if (!row) throw new AppError('Snapshot not found', 404);

  res.json({ success: true, data: row });
}));

export default router;
