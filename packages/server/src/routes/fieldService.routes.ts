/**
 * Field Service + Dispatch routes — SCAN-466
 * Mount: app.use('/api/v1/field-service', authMiddleware, fieldServiceRoutes);
 *
 * Security: authMiddleware applied at parent mount — NOT re-added here.
 * Role gates:
 *   - Manager/Admin: all write paths + route management
 *   - Technician+: read own jobs, update own job status, self-accept
 *
 * All writes are rate-limited; assignment + status changes are audited.
 * Geo data validated: -90 <= lat <= 90, -180 <= lng <= 180.
 */

import { Router, type Request, type Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { parsePage, parsePageSize } from '../utils/pagination.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';

const router = Router();

type AnyRow = Record<string, unknown>;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_ADDRESS_LEN = 500;
const MAX_NOTES_LEN = 2000;
const MAX_TECH_NOTES_LEN = 2000;

const JOB_WRITE_CATEGORY = 'fs_job_write';
const JOB_WRITE_MAX = 30;
const JOB_WRITE_WINDOW_MS = 60_000;

const OPTIMIZE_CATEGORY = 'fs_route_optimize';
const OPTIMIZE_MAX = 10;
const OPTIMIZE_WINDOW_MS = 60_000;

const VALID_PRIORITIES = ['low', 'normal', 'high', 'emergency'] as const;
const VALID_JOB_STATUSES = ['unassigned', 'assigned', 'en_route', 'on_site', 'completed', 'canceled', 'deferred'] as const;
const VALID_ROUTE_STATUSES = ['draft', 'active', 'completed'] as const;

type JobStatus = typeof VALID_JOB_STATUSES[number];

// ---------------------------------------------------------------------------
// Helper: current timestamp in SQLite format
// ---------------------------------------------------------------------------

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// ---------------------------------------------------------------------------
// Role guard
// ---------------------------------------------------------------------------

function requireManagerOrAdmin(req: Request): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Manager or admin role required', 403);
  }
}

function requireTechnicianOrAbove(req: Request): void {
  const role = req.user?.role;
  const allowed = ['technician', 'manager', 'admin'];
  if (!role || !allowed.includes(role)) {
    throw new AppError('Technician role or above required', 403);
  }
}

// ---------------------------------------------------------------------------
// validateLatLng — throws AppError 400 on invalid coords
// ---------------------------------------------------------------------------

function validateLatLng(lat: unknown, lng: unknown): void {
  const latNum = Number(lat);
  const lngNum = Number(lng);
  if (!Number.isFinite(latNum) || latNum < -90 || latNum > 90) {
    throw new AppError('lat must be a finite number between -90 and 90', 400);
  }
  if (!Number.isFinite(lngNum) || lngNum < -180 || lngNum > 180) {
    throw new AppError('lng must be a finite number between -180 and 180', 400);
  }
}

// ---------------------------------------------------------------------------
// validateOptionalLatLng — validates a single lat or lng field.
// Returns null when the value is absent (undefined/null/empty string).
// Returns the parsed finite number when present, or throws AppError.
// ---------------------------------------------------------------------------

function validateOptionalLatLng(raw: unknown, field: 'lat' | 'lng'): number | null {
  if (raw === undefined || raw === null || raw === '') return null;
  const n = Number(raw);
  if (!Number.isFinite(n)) throw new AppError(`${field} must be a finite number`, 400);
  if (field === 'lat' && (n < -90 || n > 90)) throw new AppError('lat out of range (-90 to 90)', 400);
  if (field === 'lng' && (n < -180 || n > 180)) throw new AppError('lng out of range (-180 to 180)', 400);
  return n;
}

// ---------------------------------------------------------------------------
// validateJobStatusTransition — state machine guard
//
// Allowed transitions:
//   unassigned  → assigned | canceled | deferred
//   assigned    → en_route | unassigned | canceled | deferred
//   en_route    → on_site  | assigned   | canceled | deferred
//   on_site     → completed| en_route   | canceled | deferred
//   completed   → (terminal — no further transitions)
//   canceled    → (terminal)
//   deferred    → unassigned | canceled
// ---------------------------------------------------------------------------

const STATUS_TRANSITIONS: Record<JobStatus, JobStatus[]> = {
  unassigned:  ['assigned', 'canceled', 'deferred'],
  assigned:    ['en_route', 'unassigned', 'canceled', 'deferred'],
  en_route:    ['on_site', 'assigned', 'canceled', 'deferred'],
  on_site:     ['completed', 'en_route', 'canceled', 'deferred'],
  completed:   [],
  canceled:    [],
  deferred:    ['unassigned', 'canceled'],
};

function validateJobStatusTransition(from: string, to: string): void {
  const allowed = STATUS_TRANSITIONS[from as JobStatus];
  if (!allowed) {
    throw new AppError(`Unknown current status: ${from}`, 400);
  }
  if (!allowed.includes(to as JobStatus)) {
    throw new AppError(
      `Cannot transition job status from '${from}' to '${to}'. Allowed: ${allowed.join(', ') || 'none (terminal state)'}`,
      400,
    );
  }
}

// ---------------------------------------------------------------------------
// haversineKm — great-circle distance in km
// Greedy nearest-neighbor optimization uses this to estimate route distances.
// NOT a TSP-optimal solver.
// ---------------------------------------------------------------------------

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371; // Earth radius in km
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ---------------------------------------------------------------------------
// validateIntId — integer id guard used on URL params
// ---------------------------------------------------------------------------

function validateIntId(raw: unknown, label = 'ID'): number {
  const s = Array.isArray(raw) ? String(raw[0] ?? '') : typeof raw === 'string' ? raw : String(raw ?? '');
  const n = parseInt(s, 10);
  if (!Number.isInteger(n) || n <= 0) throw new AppError(`Invalid ${label}`, 400);
  return n;
}

// ---------------------------------------------------------------------------
// validateOptionalString — length-capped trimmer
// ---------------------------------------------------------------------------

function validateOptionalString(value: unknown, field: string, maxLen: number): string | null {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string') throw new AppError(`${field} must be a string`, 400);
  const trimmed = value.trim();
  if (trimmed.length > maxLen) {
    throw new AppError(`${field} must be ${maxLen} characters or fewer`, 400);
  }
  return trimmed || null;
}

// ============================================================================
// JOBS
// ============================================================================

// GET /jobs
router.get('/jobs', asyncHandler(async (req: Request, res: Response) => {
  requireTechnicianOrAbove(req);
  const adb = req.asyncDb;
  const page = parsePage(req.query.page);
  const pageSize = parsePageSize(req.query.pagesize, 25);
  const offset = (page - 1) * pageSize;

  const conditions: string[] = [];
  const params: unknown[] = [];

  // Role scoping: technicians only see their own assigned jobs
  const isManager = req.user!.role === 'admin' || req.user!.role === 'manager';
  if (!isManager) {
    conditions.push('j.assigned_technician_id = ?');
    params.push(req.user!.id);
  } else {
    // Manager filters
    const techId = req.query.assigned_technician_id as string | undefined;
    if (techId) {
      const tid = parseInt(techId, 10);
      if (!Number.isInteger(tid) || tid <= 0) throw new AppError('Invalid assigned_technician_id', 400);
      conditions.push('j.assigned_technician_id = ?');
      params.push(tid);
    }
  }

  const statusFilter = (req.query.status as string || '').trim();
  if (statusFilter) {
    if (!VALID_JOB_STATUSES.includes(statusFilter as JobStatus)) {
      throw new AppError(`status must be one of: ${VALID_JOB_STATUSES.join(', ')}`, 400);
    }
    conditions.push('j.status = ?');
    params.push(statusFilter);
  }

  const fromDate = (req.query.from_date as string || '').trim();
  const toDate = (req.query.to_date as string || '').trim();
  if (fromDate) { conditions.push('j.scheduled_window_start >= ?'); params.push(fromDate); }
  if (toDate)   { conditions.push('j.scheduled_window_start <= ?'); params.push(toDate); }

  const whereClause = conditions.length ? 'WHERE ' + conditions.join(' AND ') : '';

  const [totalRow, jobs] = await Promise.all([
    adb.get<AnyRow>(
      `SELECT COUNT(*) AS c FROM field_service_jobs j ${whereClause}`,
      ...params,
    ),
    adb.all<AnyRow>(`
      SELECT j.*,
             c.first_name AS customer_first_name, c.last_name AS customer_last_name,
             u.first_name AS tech_first_name, u.last_name AS tech_last_name
      FROM field_service_jobs j
      LEFT JOIN customers c ON c.id = j.customer_id
      LEFT JOIN users u ON u.id = j.assigned_technician_id
      ${whereClause}
      ORDER BY j.scheduled_window_start ASC, j.id ASC
      LIMIT ? OFFSET ?
    `, ...params, pageSize, offset),
  ]);

  const total = (totalRow as AnyRow).c as number;
  res.json({
    success: true,
    data: {
      jobs,
      pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) },
    },
  });
}));

// GET /jobs/:id
router.get('/jobs/:id', asyncHandler(async (req: Request, res: Response) => {
  requireTechnicianOrAbove(req);
  const adb = req.asyncDb;
  const id = validateIntId(req.params.id, 'job ID');

  const job = await adb.get<AnyRow>(`
    SELECT j.*,
           c.first_name AS customer_first_name, c.last_name AS customer_last_name,
           u.first_name AS tech_first_name, u.last_name AS tech_last_name,
           cb.first_name AS created_by_first_name, cb.last_name AS created_by_last_name
    FROM field_service_jobs j
    LEFT JOIN customers c ON c.id = j.customer_id
    LEFT JOIN users u ON u.id = j.assigned_technician_id
    LEFT JOIN users cb ON cb.id = j.created_by_user_id
    WHERE j.id = ?
  `, id);

  if (!job) throw new AppError('Job not found', 404);

  // Technicians can only view their own assigned jobs
  const isManager = req.user!.role === 'admin' || req.user!.role === 'manager';
  if (!isManager && job.assigned_technician_id !== req.user!.id) {
    throw new AppError('Not authorized to view this job', 403);
  }

  res.json({ success: true, data: job });
}));

// POST /jobs
router.post('/jobs', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;

  const { allowed, retryAfterSeconds } = consumeWindowRate(
    db, JOB_WRITE_CATEGORY, String(req.user!.id), JOB_WRITE_MAX, JOB_WRITE_WINDOW_MS,
  );
  if (!allowed) {
    throw new AppError(`Too many job writes. Retry after ${retryAfterSeconds}s.`, 429);
  }

  const {
    ticket_id, customer_id,
    lat, lng,
    scheduled_window_start, scheduled_window_end,
    priority, estimated_duration_minutes, notes,
  } = req.body;

  // Required fields
  const address_line = validateOptionalString(req.body.address_line, 'address_line', MAX_ADDRESS_LEN);
  if (!address_line) throw new AppError('address_line is required', 400);

  // Geo validation — lat/lng are required on create
  if (lat === undefined || lat === null || lat === '') throw new AppError('lat is required', 400);
  if (lng === undefined || lng === null || lng === '') throw new AppError('lng is required', 400);
  validateLatLng(lat, lng);

  const city     = validateOptionalString(req.body.city, 'city', 100);
  const state    = validateOptionalString(req.body.state, 'state', 100);
  const postcode = validateOptionalString(req.body.postcode, 'postcode', 20);
  const notesVal = validateOptionalString(notes, 'notes', MAX_NOTES_LEN);

  if (priority && !VALID_PRIORITIES.includes(priority)) {
    throw new AppError(`priority must be one of: ${VALID_PRIORITIES.join(', ')}`, 400);
  }

  const ticketId = ticket_id != null ? (() => {
    const n = parseInt(String(ticket_id), 10);
    if (!Number.isInteger(n) || n <= 0) throw new AppError('Invalid ticket_id', 400);
    return n;
  })() : null;

  const customerId = customer_id != null ? (() => {
    const n = parseInt(String(customer_id), 10);
    if (!Number.isInteger(n) || n <= 0) throw new AppError('Invalid customer_id', 400);
    return n;
  })() : null;

  const estDur = estimated_duration_minutes != null ? (() => {
    const n = parseInt(String(estimated_duration_minutes), 10);
    if (!Number.isInteger(n) || n <= 0) throw new AppError('Invalid estimated_duration_minutes', 400);
    return n;
  })() : null;

  const ts = now();
  const result = await adb.run(`
    INSERT INTO field_service_jobs
      (ticket_id, customer_id, address_line, city, state, postcode,
       lat, lng, scheduled_window_start, scheduled_window_end,
       priority, status, estimated_duration_minutes, notes,
       created_by_user_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'unassigned', ?, ?, ?, ?, ?)
  `,
    ticketId, customerId, address_line, city, state, postcode,
    Number(lat), Number(lng),
    scheduled_window_start || null, scheduled_window_end || null,
    priority || 'normal', estDur, notesVal,
    req.user!.id, ts, ts,
  );

  const jobId = result.lastInsertRowid;
  audit(db, 'field_service.job_created', req.user!.id, req.ip || 'unknown', {
    job_id: jobId, address_line, lat: Number(lat), lng: Number(lng),
  });

  res.status(201).json({ success: true, data: { id: jobId } });
}));

// PATCH /jobs/:id
router.patch('/jobs/:id', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;

  const { allowed, retryAfterSeconds } = consumeWindowRate(
    db, JOB_WRITE_CATEGORY, String(req.user!.id), JOB_WRITE_MAX, JOB_WRITE_WINDOW_MS,
  );
  if (!allowed) {
    throw new AppError(`Too many job writes. Retry after ${retryAfterSeconds}s.`, 429);
  }

  const id = validateIntId(req.params.id, 'job ID');
  const existing = await adb.get<AnyRow>('SELECT id FROM field_service_jobs WHERE id = ?', id);
  if (!existing) throw new AppError('Job not found', 404);

  const {
    address_line, city, state, postcode, lat, lng,
    scheduled_window_start, scheduled_window_end,
    priority, estimated_duration_minutes, actual_duration_minutes,
    technician_notes, notes,
  } = req.body;

  // Validate optional address
  const addrVal = address_line !== undefined
    ? validateOptionalString(address_line, 'address_line', MAX_ADDRESS_LEN)
    : undefined;

  // Validate optional geo — returns null (skip) or finite number
  const latVal = validateOptionalLatLng(lat, 'lat');
  const lngVal = validateOptionalLatLng(lng, 'lng');
  if ((latVal === null) !== (lngVal === null)) {
    throw new AppError('lat and lng must both be provided together', 400);
  }

  if (priority !== undefined && !VALID_PRIORITIES.includes(priority)) {
    throw new AppError(`priority must be one of: ${VALID_PRIORITIES.join(', ')}`, 400);
  }

  const notesVal = notes !== undefined
    ? validateOptionalString(notes, 'notes', MAX_NOTES_LEN)
    : undefined;
  const techNotesVal = technician_notes !== undefined
    ? validateOptionalString(technician_notes, 'technician_notes', MAX_TECH_NOTES_LEN)
    : undefined;

  const cityVal     = city !== undefined     ? validateOptionalString(city, 'city', 100)         : undefined;
  const stateVal    = state !== undefined    ? validateOptionalString(state, 'state', 100)        : undefined;
  const postcodeVal = postcode !== undefined ? validateOptionalString(postcode, 'postcode', 20)   : undefined;

  await adb.run(`
    UPDATE field_service_jobs SET
      address_line             = COALESCE(?, address_line),
      city                     = COALESCE(?, city),
      state                    = COALESCE(?, state),
      postcode                 = COALESCE(?, postcode),
      lat                      = COALESCE(?, lat),
      lng                      = COALESCE(?, lng),
      scheduled_window_start   = COALESCE(?, scheduled_window_start),
      scheduled_window_end     = COALESCE(?, scheduled_window_end),
      priority                 = COALESCE(?, priority),
      estimated_duration_minutes = COALESCE(?, estimated_duration_minutes),
      actual_duration_minutes  = COALESCE(?, actual_duration_minutes),
      technician_notes         = COALESCE(?, technician_notes),
      notes                    = COALESCE(?, notes),
      updated_at               = ?
    WHERE id = ?
  `,
    addrVal ?? null,
    cityVal ?? null,
    stateVal ?? null,
    postcodeVal ?? null,
    latVal,
    lngVal,
    scheduled_window_start ?? null,
    scheduled_window_end ?? null,
    priority ?? null,
    estimated_duration_minutes ?? null,
    actual_duration_minutes ?? null,
    techNotesVal ?? null,
    notesVal ?? null,
    now(), id,
  );

  res.json({ success: true, data: { id } });
}));

// DELETE /jobs/:id  (soft cancel)
router.delete('/jobs/:id', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;

  const id = validateIntId(req.params.id, 'job ID');
  const existing = await adb.get<AnyRow>('SELECT id, status FROM field_service_jobs WHERE id = ?', id);
  if (!existing) throw new AppError('Job not found', 404);
  if (existing.status === 'canceled') throw new AppError('Job is already canceled', 409);

  const ts = now();
  await adb.run(
    "UPDATE field_service_jobs SET status = 'canceled', updated_at = ? WHERE id = ?",
    ts, id,
  );

  // Record in history
  await adb.run(`
    INSERT INTO dispatch_status_history (job_id, status, actor_user_id, notes, created_at)
    VALUES (?, 'canceled', ?, 'Soft-deleted via DELETE endpoint', ?)
  `, id, req.user!.id, ts);

  audit(db, 'field_service.job_canceled', req.user!.id, req.ip || 'unknown', { job_id: id });
  res.json({ success: true, data: { id, status: 'canceled' } });
}));

// POST /jobs/:id/assign
router.post('/jobs/:id/assign', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;

  const { allowed, retryAfterSeconds } = consumeWindowRate(
    db, JOB_WRITE_CATEGORY, String(req.user!.id), JOB_WRITE_MAX, JOB_WRITE_WINDOW_MS,
  );
  if (!allowed) {
    throw new AppError(`Too many job writes. Retry after ${retryAfterSeconds}s.`, 429);
  }

  const id = validateIntId(req.params.id, 'job ID');
  const techId = parseInt(String(req.body.technician_id), 10);
  if (!Number.isInteger(techId) || techId <= 0) {
    throw new AppError('technician_id is required and must be a positive integer', 400);
  }

  const [job, tech] = await Promise.all([
    adb.get<AnyRow>('SELECT id, status FROM field_service_jobs WHERE id = ?', id),
    adb.get<AnyRow>("SELECT id, role FROM users WHERE id = ? AND is_active = 1", techId),
  ]);

  if (!job) throw new AppError('Job not found', 404);
  if (!tech) throw new AppError('Technician user not found or inactive', 404);
  if (job.status === 'completed' || job.status === 'canceled') {
    throw new AppError(`Cannot assign a job with status '${job.status}'`, 400);
  }

  const ts = now();
  await adb.run(`
    UPDATE field_service_jobs
    SET assigned_technician_id = ?, status = 'assigned', updated_at = ?
    WHERE id = ?
  `, techId, ts, id);

  await adb.run(`
    INSERT INTO dispatch_status_history (job_id, status, actor_user_id, notes, created_at)
    VALUES (?, 'assigned', ?, ?, ?)
  `, id, req.user!.id, `Assigned to technician ${techId}`, ts);

  audit(db, 'field_service.job_assigned', req.user!.id, req.ip || 'unknown', {
    job_id: id, technician_id: techId, previous_status: job.status,
  });

  res.json({ success: true, data: { id, assigned_technician_id: techId, status: 'assigned' } });
}));

// POST /jobs/:id/unassign
router.post('/jobs/:id/unassign', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;

  const { allowed, retryAfterSeconds } = consumeWindowRate(
    db, JOB_WRITE_CATEGORY, String(req.user!.id), JOB_WRITE_MAX, JOB_WRITE_WINDOW_MS,
  );
  if (!allowed) {
    throw new AppError(`Too many job writes. Retry after ${retryAfterSeconds}s.`, 429);
  }

  const id = validateIntId(req.params.id, 'job ID');
  const job = await adb.get<AnyRow>('SELECT id, status, assigned_technician_id FROM field_service_jobs WHERE id = ?', id);
  if (!job) throw new AppError('Job not found', 404);
  if (job.status === 'completed' || job.status === 'canceled') {
    throw new AppError(`Cannot unassign a job with status '${job.status}'`, 400);
  }

  const ts = now();
  await adb.run(`
    UPDATE field_service_jobs
    SET assigned_technician_id = NULL, status = 'unassigned', updated_at = ?
    WHERE id = ?
  `, ts, id);

  await adb.run(`
    INSERT INTO dispatch_status_history (job_id, status, actor_user_id, notes, created_at)
    VALUES (?, 'unassigned', ?, 'Unassigned by manager', ?)
  `, id, req.user!.id, ts);

  audit(db, 'field_service.job_unassigned', req.user!.id, req.ip || 'unknown', {
    job_id: id, previous_technician_id: job.assigned_technician_id,
  });

  res.json({ success: true, data: { id, assigned_technician_id: null, status: 'unassigned' } });
}));

// POST /jobs/:id/status
router.post('/jobs/:id/status', asyncHandler(async (req: Request, res: Response) => {
  requireTechnicianOrAbove(req);
  const adb = req.asyncDb;
  const db = req.db;

  const { allowed, retryAfterSeconds } = consumeWindowRate(
    db, JOB_WRITE_CATEGORY, String(req.user!.id), JOB_WRITE_MAX, JOB_WRITE_WINDOW_MS,
  );
  if (!allowed) {
    throw new AppError(`Too many job writes. Retry after ${retryAfterSeconds}s.`, 429);
  }

  const id = validateIntId(req.params.id, 'job ID');
  const job = await adb.get<AnyRow>(
    'SELECT id, status, assigned_technician_id FROM field_service_jobs WHERE id = ?', id,
  );
  if (!job) throw new AppError('Job not found', 404);

  // Role: technicians can only update their own assigned jobs
  const isManager = req.user!.role === 'admin' || req.user!.role === 'manager';
  if (!isManager) {
    if (job.assigned_technician_id !== req.user!.id) {
      throw new AppError('You can only update status on your own assigned jobs', 403);
    }
  }

  const { status: newStatus, notes } = req.body;
  const location_lat = req.body.location_lat;
  const location_lng = req.body.location_lng;

  if (!newStatus || !VALID_JOB_STATUSES.includes(newStatus as JobStatus)) {
    throw new AppError(`status must be one of: ${VALID_JOB_STATUSES.join(', ')}`, 400);
  }

  validateJobStatusTransition(job.status as string, newStatus);

  // Validate optional location — returns null (skip) or finite number
  const locLatVal = validateOptionalLatLng(location_lat, 'lat');
  const locLngVal = validateOptionalLatLng(location_lng, 'lng');
  if ((locLatVal === null) !== (locLngVal === null)) {
    throw new AppError('location_lat and location_lng must both be provided together', 400);
  }

  const notesVal = validateOptionalString(notes, 'notes', MAX_NOTES_LEN);
  const ts = now();

  await adb.run(
    'UPDATE field_service_jobs SET status = ?, updated_at = ? WHERE id = ?',
    newStatus, ts, id,
  );

  await adb.run(`
    INSERT INTO dispatch_status_history
      (job_id, status, actor_user_id, location_lat, location_lng, notes, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `,
    id, newStatus, req.user!.id,
    locLatVal, locLngVal,
    notesVal, ts,
  );

  audit(db, 'field_service.job_status_changed', req.user!.id, req.ip || 'unknown', {
    job_id: id, from: job.status, to: newStatus,
  });

  res.json({ success: true, data: { id, status: newStatus } });
}));

// ============================================================================
// ROUTES
// ============================================================================

// GET /routes
router.get('/routes', asyncHandler(async (req: Request, res: Response) => {
  requireTechnicianOrAbove(req);
  const adb = req.asyncDb;
  const page = parsePage(req.query.page);
  const pageSize = parsePageSize(req.query.pagesize, 25);
  const offset = (page - 1) * pageSize;

  const conditions: string[] = [];
  const params: unknown[] = [];

  const isManager = req.user!.role === 'admin' || req.user!.role === 'manager';
  if (!isManager) {
    conditions.push('r.technician_id = ?');
    params.push(req.user!.id);
  } else {
    const techId = req.query.technician_id as string | undefined;
    if (techId) {
      const tid = parseInt(techId, 10);
      if (!Number.isInteger(tid) || tid <= 0) throw new AppError('Invalid technician_id', 400);
      conditions.push('r.technician_id = ?');
      params.push(tid);
    }
  }

  const fromDate = (req.query.from_date as string || '').trim();
  const toDate   = (req.query.to_date   as string || '').trim();
  if (fromDate) { conditions.push('r.route_date >= ?'); params.push(fromDate); }
  if (toDate)   { conditions.push('r.route_date <= ?'); params.push(toDate); }

  const whereClause = conditions.length ? 'WHERE ' + conditions.join(' AND ') : '';

  const [totalRow, routes] = await Promise.all([
    adb.get<AnyRow>(`SELECT COUNT(*) AS c FROM dispatch_routes r ${whereClause}`, ...params),
    adb.all<AnyRow>(`
      SELECT r.*, u.first_name AS tech_first_name, u.last_name AS tech_last_name
      FROM dispatch_routes r
      LEFT JOIN users u ON u.id = r.technician_id
      ${whereClause}
      ORDER BY r.route_date DESC, r.id DESC
      LIMIT ? OFFSET ?
    `, ...params, pageSize, offset),
  ]);

  const total = (totalRow as AnyRow).c as number;
  res.json({
    success: true,
    data: {
      routes,
      pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) },
    },
  });
}));

// GET /routes/:id
router.get('/routes/:id', asyncHandler(async (req: Request, res: Response) => {
  requireTechnicianOrAbove(req);
  const adb = req.asyncDb;
  const id = validateIntId(req.params.id, 'route ID');

  const route = await adb.get<AnyRow>(`
    SELECT r.*, u.first_name AS tech_first_name, u.last_name AS tech_last_name
    FROM dispatch_routes r
    LEFT JOIN users u ON u.id = r.technician_id
    WHERE r.id = ?
  `, id);

  if (!route) throw new AppError('Route not found', 404);

  const isManager = req.user!.role === 'admin' || req.user!.role === 'manager';
  if (!isManager && route.technician_id !== req.user!.id) {
    throw new AppError('Not authorized to view this route', 403);
  }

  res.json({ success: true, data: route });
}));

// POST /routes
router.post('/routes', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;

  const { allowed, retryAfterSeconds } = consumeWindowRate(
    db, JOB_WRITE_CATEGORY, String(req.user!.id), JOB_WRITE_MAX, JOB_WRITE_WINDOW_MS,
  );
  if (!allowed) {
    throw new AppError(`Too many route writes. Retry after ${retryAfterSeconds}s.`, 429);
  }

  const { technician_id, route_date, job_order_json } = req.body;

  const techId = parseInt(String(technician_id), 10);
  if (!Number.isInteger(techId) || techId <= 0) {
    throw new AppError('technician_id is required and must be a positive integer', 400);
  }

  if (!route_date || typeof route_date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(route_date.trim())) {
    throw new AppError('route_date is required and must be in YYYY-MM-DD format', 400);
  }

  if (!Array.isArray(job_order_json) || job_order_json.length === 0) {
    throw new AppError('job_order_json must be a non-empty array of job IDs', 400);
  }

  const jobIds: number[] = job_order_json.map((raw: unknown, i: number) => {
    const n = parseInt(String(raw), 10);
    if (!Number.isInteger(n) || n <= 0) {
      throw new AppError(`job_order_json[${i}] must be a positive integer job ID`, 400);
    }
    return n;
  });

  // Verify all jobs exist and are assigned to this technician (single query)
  {
    const placeholders = jobIds.map(() => '?').join(',');
    const rows = await adb.all<{ id: number; assigned_technician_id: number | null }>(
      `SELECT id, assigned_technician_id FROM field_service_jobs WHERE id IN (${placeholders})`,
      ...jobIds,
    );
    if (rows.length !== jobIds.length) {
      throw new AppError('One or more jobs not found', 404);
    }
    for (const row of rows) {
      if (row.assigned_technician_id !== techId) {
        throw new AppError('Job not assigned to this technician', 400);
      }
    }
  }

  const ts = now();
  const result = await adb.run(`
    INSERT INTO dispatch_routes
      (technician_id, route_date, job_order_json, status, created_at, updated_at)
    VALUES (?, ?, ?, 'draft', ?, ?)
  `, techId, route_date.trim(), JSON.stringify(jobIds), ts, ts);

  audit(db, 'field_service.route_created', req.user!.id, req.ip || 'unknown', {
    route_id: result.lastInsertRowid, technician_id: techId, route_date: route_date.trim(),
  });

  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

// PATCH /routes/:id
router.patch('/routes/:id', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;

  const id = validateIntId(req.params.id, 'route ID');
  const existing = await adb.get<AnyRow>('SELECT id, technician_id FROM dispatch_routes WHERE id = ?', id);
  if (!existing) throw new AppError('Route not found', 404);

  const { job_order_json, status, total_distance_km, total_duration_minutes } = req.body;

  let jobOrderStr: string | null = null;
  if (job_order_json !== undefined) {
    if (!Array.isArray(job_order_json) || job_order_json.length === 0) {
      throw new AppError('job_order_json must be a non-empty array of job IDs', 400);
    }
    const jobIds: number[] = job_order_json.map((raw: unknown, i: number) => {
      const n = parseInt(String(raw), 10);
      if (!Number.isInteger(n) || n <= 0) {
        throw new AppError(`job_order_json[${i}] must be a positive integer job ID`, 400);
      }
      return n;
    });
    // Verify jobs exist and belong to this route's technician (single query)
    {
      const placeholders = jobIds.map(() => '?').join(',');
      const rows = await adb.all<{ id: number; assigned_technician_id: number | null }>(
        `SELECT id, assigned_technician_id FROM field_service_jobs WHERE id IN (${placeholders})`,
        ...jobIds,
      );
      if (rows.length !== jobIds.length) {
        throw new AppError('One or more jobs not found', 404);
      }
      for (const row of rows) {
        if (row.assigned_technician_id !== existing.technician_id) {
          throw new AppError('Job not assigned to this technician', 400);
        }
      }
    }
    jobOrderStr = JSON.stringify(jobIds);
  }

  if (status !== undefined && !VALID_ROUTE_STATUSES.includes(status)) {
    throw new AppError(`status must be one of: ${VALID_ROUTE_STATUSES.join(', ')}`, 400);
  }

  await adb.run(`
    UPDATE dispatch_routes SET
      job_order_json       = COALESCE(?, job_order_json),
      status               = COALESCE(?, status),
      total_distance_km    = COALESCE(?, total_distance_km),
      total_duration_minutes = COALESCE(?, total_duration_minutes),
      updated_at           = ?
    WHERE id = ?
  `,
    jobOrderStr, status ?? null,
    total_distance_km ?? null, total_duration_minutes ?? null,
    now(), id,
  );

  audit(db, 'field_service.route_updated', req.user!.id, req.ip || 'unknown', { route_id: id });
  res.json({ success: true, data: { id } });
}));

// DELETE /routes/:id
router.delete('/routes/:id', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;

  const id = validateIntId(req.params.id, 'route ID');
  const existing = await adb.get<AnyRow>('SELECT id FROM dispatch_routes WHERE id = ?', id);
  if (!existing) throw new AppError('Route not found', 404);

  await adb.run('DELETE FROM dispatch_routes WHERE id = ?', id);
  audit(db, 'field_service.route_deleted', req.user!.id, req.ip || 'unknown', { route_id: id });
  res.json({ success: true, data: { id } });
}));

// POST /routes/optimize
//
// Greedy nearest-neighbor route ordering heuristic.
// NOT a TSP-optimal solver — see algorithm note in docs.
// Does NOT persist — client must call POST /routes with the returned order.
//
// Rate limit: 10 requests per minute per user.
router.post('/routes/optimize', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;

  const { allowed, retryAfterSeconds } = consumeWindowRate(
    db, OPTIMIZE_CATEGORY, String(req.user!.id), OPTIMIZE_MAX, OPTIMIZE_WINDOW_MS,
  );
  if (!allowed) {
    throw new AppError(`Too many optimize requests. Retry after ${retryAfterSeconds}s.`, 429);
  }

  const { technician_id, route_date, job_ids } = req.body;

  const techId = parseInt(String(technician_id), 10);
  if (!Number.isInteger(techId) || techId <= 0) {
    throw new AppError('technician_id is required and must be a positive integer', 400);
  }

  if (!route_date || typeof route_date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(route_date.trim())) {
    throw new AppError('route_date is required and must be in YYYY-MM-DD format', 400);
  }

  if (!Array.isArray(job_ids) || job_ids.length === 0) {
    throw new AppError('job_ids must be a non-empty array of job IDs', 400);
  }

  const jobIds: number[] = job_ids.map((raw: unknown, i: number) => {
    const n = parseInt(String(raw), 10);
    if (!Number.isInteger(n) || n <= 0) {
      throw new AppError(`job_ids[${i}] must be a positive integer job ID`, 400);
    }
    return n;
  });

  // Load jobs (must all be assigned to this technician) — single query
  const placeholders = jobIds.map(() => '?').join(',');
  const jobRows = await adb.all<AnyRow>(
    `SELECT id, lat, lng, assigned_technician_id FROM field_service_jobs WHERE id IN (${placeholders})`,
    ...jobIds,
  );
  if (jobRows.length !== jobIds.length) {
    throw new AppError('One or more jobs not found', 404);
  }
  for (const row of jobRows) {
    if ((row.assigned_technician_id as number | null) !== techId) {
      throw new AppError(`Job ${row.id as number} is not assigned to technician ${techId}`, 400);
    }
  }
  const jobMap = new Map<number, AnyRow>(jobRows.map((j) => [j.id as number, j]));
  // Preserve the requested order for the greedy algorithm input
  const jobs = jobIds.map((jid) => jobMap.get(jid)!);

  // Determine start location: use technician's home_lat/home_lng if present,
  // otherwise seed from the first job.
  const tech = await adb.get<AnyRow>(
    'SELECT id, home_lat, home_lng FROM users WHERE id = ?', techId,
  );

  let currentLat: number;
  let currentLng: number;

  const hasHomeCoords =
    tech &&
    tech.home_lat != null && tech.home_lng != null &&
    Number.isFinite(Number(tech.home_lat)) && Number.isFinite(Number(tech.home_lng));

  if (hasHomeCoords) {
    currentLat = Number((tech as AnyRow).home_lat);
    currentLng = Number((tech as AnyRow).home_lng);
  } else {
    currentLat = Number(jobs[0].lat);
    currentLng = Number(jobs[0].lng);
  }

  // Greedy nearest-neighbor: repeatedly pick the closest unvisited job.
  // O(n²) — acceptable for typical field service route sizes (<50 jobs/day).
  const remaining = [...jobs];
  const orderedJobs: AnyRow[] = [];
  let totalDistanceKm = 0;

  while (remaining.length > 0) {
    let nearest = remaining[0];
    let nearestIdx = 0;
    let nearestDist = haversineKm(currentLat, currentLng, Number(nearest.lat), Number(nearest.lng));

    for (let i = 1; i < remaining.length; i++) {
      const dist = haversineKm(currentLat, currentLng, Number(remaining[i].lat), Number(remaining[i].lng));
      if (dist < nearestDist) {
        nearest = remaining[i];
        nearestIdx = i;
        nearestDist = dist;
      }
    }

    totalDistanceKm += nearestDist;
    orderedJobs.push(nearest);
    remaining.splice(nearestIdx, 1);
    currentLat = Number(nearest.lat);
    currentLng = Number(nearest.lng);
  }

  const proposedOrder = orderedJobs.map((j) => j.id as number);

  res.json({
    success: true,
    data: {
      proposed_order: proposedOrder,
      total_distance_km: Math.round(totalDistanceKm * 100) / 100,
      algorithm: 'greedy-nearest-neighbor',
      note: 'This is a greedy nearest-neighbor heuristic, not TSP-optimal. Call POST /routes with proposed_order to persist.',
      start_from_home: hasHomeCoords,
    },
  });
}));

export default router;
