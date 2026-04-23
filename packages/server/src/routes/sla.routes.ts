/**
 * SLA routes — mount at /api/v1/sla
 *
 * authMiddleware is applied at the parent mount point in index.ts.
 * Manager/admin gates are enforced inline on write endpoints.
 *
 * SCAN-464: Ticket SLA tracking (badge, breach timer, config)
 *
 * Registration snippet (add to index.ts beside other route mounts):
 * ```ts
 * import slaRoutes from './routes/sla.routes.js';
 * app.use('/api/v1/sla', authMiddleware, slaRoutes);
 * ```
 */

import { Router, Request, Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { checkWindowRate, recordWindowAttempt } from '../utils/rateLimiter.js';
import { parsePage, parsePageSize } from '../utils/pagination.js';
import { createLogger } from '../utils/logger.js';

const router = Router();
const logger = createLogger('sla.routes');

type AnyRow = Record<string, unknown>;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const VALID_PRIORITY_LEVELS = ['low', 'normal', 'high', 'critical'] as const;
type PriorityLevel = typeof VALID_PRIORITY_LEVELS[number];

const MAX_NAME_LEN = 200;
const MAX_HOURS = 8760; // 365 days

// Rate-limit: 20 policy writes per user per minute
const SLA_POLICY_WRITE_CATEGORY = 'sla_policy_write';
const SLA_POLICY_WRITE_MAX = 20;
const SLA_POLICY_WRITE_WINDOW_MS = 60_000;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function now(): string {
  return new Date().toISOString().replace('T', ' ').slice(0, 19);
}

function requireManagerOrAdmin(req: Request): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Manager or admin role required', 403);
  }
}

function parseId(raw: unknown, label = 'ID'): number {
  const id = parseInt(String(raw), 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError(`Invalid ${label}`, 400);
  return id;
}

function validateHours(value: unknown, field: string): number {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0 || n > MAX_HOURS) {
    throw new AppError(`${field} must be a positive integer up to ${MAX_HOURS}`, 400);
  }
  return n;
}

function checkPolicyWriteRate(req: Request): void {
  const db = req.db;
  const key = String(req.user!.id);
  if (!checkWindowRate(db, SLA_POLICY_WRITE_CATEGORY, key, SLA_POLICY_WRITE_MAX, SLA_POLICY_WRITE_WINDOW_MS)) {
    throw new AppError('Too many SLA policy writes. Please slow down.', 429);
  }
  recordWindowAttempt(db, SLA_POLICY_WRITE_CATEGORY, key, SLA_POLICY_WRITE_WINDOW_MS);
}

/**
 * Compute remaining milliseconds to a due-at timestamp.
 * Returns 0 if already breached or no due-at set.
 */
function computeRemainingMs(dueAt: string | null | undefined): number {
  if (!dueAt) return 0;
  const ms = new Date(dueAt).getTime() - Date.now();
  return ms > 0 ? ms : 0;
}

// ---------------------------------------------------------------------------
// Policy routes
// ---------------------------------------------------------------------------

// GET /policies — list SLA policies
router.get('/policies', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const page = parsePage(req.query.page);
  const pageSize = parsePageSize(req.query.pagesize, 25);
  const offset = (page - 1) * pageSize;
  const activeOnly = req.query.active !== '0';

  const conditions: string[] = [];
  const params: unknown[] = [];
  if (activeOnly) { conditions.push('is_active = 1'); }
  const where = conditions.length ? 'WHERE ' + conditions.join(' AND ') : '';

  const [totalRow, policies] = await Promise.all([
    adb.get<AnyRow>(`SELECT COUNT(*) AS c FROM sla_policies ${where}`, ...params),
    adb.all<AnyRow>(
      `SELECT * FROM sla_policies ${where}
       ORDER BY CASE priority_level
         WHEN 'critical' THEN 1
         WHEN 'high'     THEN 2
         WHEN 'normal'   THEN 3
         WHEN 'low'      THEN 4
         ELSE 5
       END
       LIMIT ? OFFSET ?`,
      ...params, pageSize, offset,
    ),
  ]);

  const total = (totalRow as AnyRow).c as number;
  res.json({
    success: true,
    data: {
      policies,
      pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) },
    },
  });
}));

// POST /policies — create policy (manager+)
router.post('/policies', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  checkPolicyWriteRate(req);

  const adb = req.asyncDb;
  const db = req.db;

  const { name, priority_level, first_response_hours, resolution_hours, business_hours_only } = req.body;

  if (typeof name !== 'string' || name.trim().length === 0) {
    throw new AppError('name is required', 400);
  }
  const safeName = name.trim().slice(0, MAX_NAME_LEN);

  if (!(VALID_PRIORITY_LEVELS as readonly string[]).includes(priority_level)) {
    throw new AppError('priority_level must be one of: low, normal, high, critical', 400);
  }
  const level = priority_level as PriorityLevel;

  const frHours = validateHours(first_response_hours, 'first_response_hours');
  const resHours = validateHours(resolution_hours, 'resolution_hours');
  if (frHours >= resHours) {
    throw new AppError('resolution_hours must be greater than first_response_hours', 400);
  }
  const bizHours = business_hours_only !== undefined ? (business_hours_only ? 1 : 0) : 1;

  // Check for conflicting active policy on this level
  const conflict = await adb.get<AnyRow>(
    'SELECT id FROM sla_policies WHERE priority_level = ? AND is_active = 1',
    level,
  );
  if (conflict) {
    throw new AppError(
      `An active SLA policy for priority_level '${level}' already exists. Deactivate it first.`,
      409,
    );
  }

  const result = await adb.run(
    `INSERT INTO sla_policies
       (name, priority_level, first_response_hours, resolution_hours, business_hours_only,
        is_active, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 1, ?, ?)`,
    safeName, level, frHours, resHours, bizHours, now(), now(),
  );

  audit(db, 'sla_policy.created', req.user!.id, req.ip || 'unknown', {
    policy_id: Number(result.lastInsertRowid),
    name: safeName,
    priority_level: level,
    first_response_hours: frHours,
    resolution_hours: resHours,
  });

  const created = await adb.get<AnyRow>('SELECT * FROM sla_policies WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: created });
}));

// PATCH /policies/:id — update policy (manager+)
router.patch('/policies/:id', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  checkPolicyWriteRate(req);

  const adb = req.asyncDb;
  const db = req.db;
  const id = parseId(req.params.id, 'policy ID');

  const existing = await adb.get<AnyRow>('SELECT * FROM sla_policies WHERE id = ?', id);
  if (!existing) throw new AppError('SLA policy not found', 404);

  const {
    name, first_response_hours, resolution_hours, business_hours_only, is_active,
  } = req.body;

  const safeName = name !== undefined
    ? (typeof name === 'string' && name.trim().length > 0
        ? name.trim().slice(0, MAX_NAME_LEN)
        : (() => { throw new AppError('name must be a non-empty string', 400); })())
    : null;

  const frHours = first_response_hours !== undefined
    ? validateHours(first_response_hours, 'first_response_hours')
    : null;
  const resHours = resolution_hours !== undefined
    ? validateHours(resolution_hours, 'resolution_hours')
    : null;

  // Validate combined hours if both provided
  const effectiveFr = frHours ?? (existing.first_response_hours as number);
  const effectiveRes = resHours ?? (existing.resolution_hours as number);
  if (effectiveFr >= effectiveRes) {
    throw new AppError('resolution_hours must be greater than first_response_hours', 400);
  }

  const bizHours = business_hours_only !== undefined ? (business_hours_only ? 1 : 0) : null;
  const activeFlag = is_active !== undefined ? (is_active ? 1 : 0) : null;

  await adb.run(
    `UPDATE sla_policies
     SET name                  = COALESCE(?, name),
         first_response_hours  = COALESCE(?, first_response_hours),
         resolution_hours      = COALESCE(?, resolution_hours),
         business_hours_only   = COALESCE(?, business_hours_only),
         is_active             = COALESCE(?, is_active),
         updated_at            = ?
     WHERE id = ?`,
    safeName, frHours, resHours, bizHours, activeFlag, now(), id,
  );

  audit(db, 'sla_policy.updated', req.user!.id, req.ip || 'unknown', {
    policy_id: id,
    changes: { name: safeName, first_response_hours: frHours, resolution_hours: resHours, is_active: activeFlag },
  });

  const updated = await adb.get<AnyRow>('SELECT * FROM sla_policies WHERE id = ?', id);
  res.json({ success: true, data: updated });
}));

// DELETE /policies/:id — soft deactivate (manager+)
router.delete('/policies/:id', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);

  const adb = req.asyncDb;
  const db = req.db;
  const id = parseId(req.params.id, 'policy ID');

  const existing = await adb.get<AnyRow>('SELECT id FROM sla_policies WHERE id = ? AND is_active = 1', id);
  if (!existing) throw new AppError('Active SLA policy not found', 404);

  await adb.run('UPDATE sla_policies SET is_active = 0, updated_at = ? WHERE id = ?', now(), id);

  audit(db, 'sla_policy.deactivated', req.user!.id, req.ip || 'unknown', { policy_id: id });
  res.json({ success: true, data: { id } });
}));

// ---------------------------------------------------------------------------
// Ticket SLA status route
// ---------------------------------------------------------------------------

interface BreachLogEntry {
  id: number;
  breach_type: string;
  breached_at: string;
  acknowledged_at: string | null;
  notes: string | null;
}

interface SlaStatusResponse {
  policy: AnyRow | null;
  first_response_due_at: string | null;
  resolution_due_at: string | null;
  remaining_ms: number;
  breached: boolean;
  breach_log_entries: BreachLogEntry[];
}

// GET /tickets/:ticketId/status — compute current SLA state
router.get('/tickets/:ticketId/status', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseId(req.params.ticketId, 'ticket ID');

  const ticket = await adb.get<AnyRow>(
    `SELECT id, sla_policy_id, sla_first_response_due_at,
            sla_resolution_due_at, sla_breached
     FROM tickets WHERE id = ?`,
    ticketId,
  );
  if (!ticket) throw new AppError('Ticket not found', 404);

  const [policy, breachEntries] = await Promise.all([
    ticket.sla_policy_id
      ? adb.get<AnyRow>('SELECT * FROM sla_policies WHERE id = ?', ticket.sla_policy_id)
      : Promise.resolve(null),
    adb.all<BreachLogEntry>(
      `SELECT id, breach_type, breached_at, acknowledged_at, notes
       FROM sla_breach_log WHERE ticket_id = ? ORDER BY breached_at DESC`,
      ticketId,
    ),
  ]);

  const firstResponseDue = (ticket.sla_first_response_due_at as string | null) ?? null;
  const resolutionDue = (ticket.sla_resolution_due_at as string | null) ?? null;
  const breached = Boolean(ticket.sla_breached);

  // remaining_ms is time until resolution deadline (negative when overdue)
  const remainingMs = resolutionDue
    ? new Date(resolutionDue).getTime() - Date.now()
    : 0;

  const data: SlaStatusResponse = {
    policy: policy ?? null,
    first_response_due_at: firstResponseDue,
    resolution_due_at: resolutionDue,
    remaining_ms: remainingMs,
    breached,
    breach_log_entries: breachEntries,
  };

  res.json({ success: true, data });
}));

// ---------------------------------------------------------------------------
// Breach log route
// ---------------------------------------------------------------------------

// GET /breaches — list recent breach log (manager+)
router.get('/breaches', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);

  const adb = req.asyncDb;
  const page = parsePage(req.query.page);
  const pageSize = parsePageSize(req.query.pagesize, 50);
  const offset = (page - 1) * pageSize;

  const conditions: string[] = [];
  const params: unknown[] = [];

  if (req.query.from) {
    conditions.push('bl.breached_at >= ?');
    params.push(String(req.query.from).slice(0, 30));
  }
  if (req.query.to) {
    conditions.push('bl.breached_at <= ?');
    params.push(String(req.query.to).slice(0, 30));
  }
  if (req.query.breach_type) {
    const bt = String(req.query.breach_type);
    if (!['first_response', 'resolution'].includes(bt)) {
      throw new AppError('breach_type must be first_response or resolution', 400);
    }
    conditions.push('bl.breach_type = ?');
    params.push(bt);
  }

  const where = conditions.length ? 'WHERE ' + conditions.join(' AND ') : '';

  const [totalRow, entries] = await Promise.all([
    adb.get<AnyRow>(`SELECT COUNT(*) AS c FROM sla_breach_log bl ${where}`, ...params),
    adb.all<AnyRow>(
      `SELECT bl.*, t.order_id AS ticket_order_id, p.name AS policy_name,
              p.priority_level
       FROM sla_breach_log bl
       JOIN tickets t ON t.id = bl.ticket_id
       LEFT JOIN sla_policies p ON p.id = bl.policy_id
       ${where}
       ORDER BY bl.breached_at DESC
       LIMIT ? OFFSET ?`,
      ...params, pageSize, offset,
    ),
  ]);

  const total = (totalRow as AnyRow).c as number;
  res.json({
    success: true,
    data: {
      breach_log: entries,
      pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) },
    },
  });
}));

export default router;
