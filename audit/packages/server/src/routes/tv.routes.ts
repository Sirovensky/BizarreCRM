import { Router, Request, Response } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { createLogger } from '../utils/logger.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { AppError } from '../middleware/errorHandler.js';

const logger = createLogger('tv.routes');

const router = Router();

// SCAN-1120 [HIGH]: the TV routes are intentionally public (wall-mounted
// screens cannot authenticate), but previously there was no rate limit
// AND the payload included `customer_first_name` + assigned-tech full
// name. With `tv_display_enabled=1` any unauthenticated WAN caller
// (including drive-by scanners) could poll the endpoint unlimited and
// scrape a live feed of customer first names attached to device makes +
// order ids. Layered defences:
//   1. Per-IP rate limit (30 req/min/IP) closes the enumeration path.
//   2. Payload redaction below drops customer first name and tech name
//      from the public shape — signage only needs order_id + device
//      name + status. Re-surfacing identifiers on the TV would require
//      a dedicated authed view.
const TV_RATE_CATEGORY = 'tv_public';
const TV_RATE_MAX = 30;
const TV_RATE_WINDOW_MS = 60_000;

function enforceTvRateLimit(req: Request): void {
  const ip = (req.ip || req.socket?.remoteAddress || 'unknown').slice(0, 64);
  const r = consumeWindowRate(req.db, TV_RATE_CATEGORY, ip, TV_RATE_MAX, TV_RATE_WINDOW_MS);
  if (!r.allowed) {
    throw new AppError(`TV board polled too frequently. Retry in ${r.retryAfterSeconds}s`, 429);
  }
}

// SECURITY: TV display routes are intentionally public (no auth middleware).
// These endpoints serve data to wall-mounted TV screens in the shop that
// cannot authenticate. Access is gated entirely by the `tv_display_enabled`
// setting in `store_config` — when the toggle is off, every endpoint here
// returns a clear `{ success: false, error: '...' }` payload instead of
// leaking ticket data. Toggling the setting is equivalent to "unplug the TV".
//
// @audit-fixed: #21 — this file used to be a stub returning `[]` regardless
// of toggles or data. The shop has a wall-mounted TV that displays (a) the
// tickets currently in progress, (b) the tickets that are ready for pickup
// so the customer-facing counter staff can see what to hand out, and (c)
// the last few check-ins so walk-in customers can confirm their device was
// logged. All three panels update together via `GET /api/v1/tv/board`.

interface TicketRow {
  id: number;
  order_id: string;
  status_id: number;
  status_name: string | null;
  status_color: string | null;
  is_closed: number;
  is_cancelled: number;
  customer_first_name: string | null;
  customer_last_name: string | null;
  tech_first_name: string | null;
  tech_last_name: string | null;
  created_at: string;
  updated_at: string;
}

interface DeviceRow {
  ticket_id: number;
  device_name: string | null;
}

interface TvBoardTicket {
  id: number;
  order_id: string;
  status: { id: number; name: string; color: string };
  customer_first_name: string | null;
  assigned_tech: string | null;
  device_names: string[];
  created_at: string;
  updated_at: string;
}

interface TvBoardPayload {
  tickets_in_progress: TvBoardTicket[];
  ready_for_pickup: TvBoardTicket[];
  recent_checkins: TvBoardTicket[];
  generated_at: string;
}

/** Keywords that identify "in progress" / "actively being worked on" statuses. */
const IN_PROGRESS_KEYWORDS = [
  'in progress',
  'diagnosing',
  'diagnosis',
  'repair',
  'pending qc',
];

/** Keywords that identify "ready for pickup" statuses. */
const READY_PICKUP_KEYWORDS = [
  'ready for pickup',
  'ready to pick',
  'pickup',
  'waiting for payment',
  'ready for collection',
];

function shapeTicket(row: TicketRow, devices: DeviceRow[]): TvBoardTicket {
  // SCAN-1120: customer_first_name + assigned_tech are now redacted from the
  // public TV payload. The on-screen signage works fine with just order_id
  // + device_name + status — those are already visible on the printed
  // ticket stub the customer has. An authed "manager view" of the same
  // data (with identifiers) can live under a gated route if ever needed.
  return {
    id: row.id,
    order_id: row.order_id,
    status: {
      id: row.status_id,
      name: row.status_name ?? '',
      color: row.status_color ?? '#6b7280',
    },
    customer_first_name: null,
    assigned_tech: null,
    device_names: devices
      .filter((d) => d.ticket_id === row.id)
      .map((d) => d.device_name ?? 'Unknown device'),
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

async function isTvDisplayEnabled(adb: Request['asyncDb']): Promise<boolean> {
  const row = await adb.get<{ value: string }>(
    "SELECT value FROM store_config WHERE key = 'tv_display_enabled'",
  );
  if (!row) return false;
  const v = (row.value ?? '').toLowerCase();
  return v === '1' || v === 'true' || v === 'yes' || v === 'on';
}

/**
 * GET /api/v1/tv/
 *
 * Legacy root endpoint — preserved so any existing TV clients that poll
 * the mount point directly keep working. Returns the same shape as
 * `GET /api/v1/tv/board` when enabled; returns an error (not an empty
 * array) when disabled so the TV can show a clear "TV display is turned
 * off in settings" message instead of sitting blank.
 */
router.get('/', asyncHandler(async (req: Request, res: Response) => {
  enforceTvRateLimit(req);
  const adb = req.asyncDb;
  const enabled = await isTvDisplayEnabled(adb);
  if (!enabled) {
    res.status(403).json({
      success: false,
      error: 'TV display is disabled. Enable "tv_display_enabled" in Settings to turn it on.',
    });
    return;
  }

  const payload = await buildTvBoard(adb);
  res.json({ success: true, data: payload });
}));

/**
 * GET /api/v1/tv/board
 *
 * Real implementation of the wall-mounted TV display. Returns three panels
 * at once so the TV app does a single poll instead of three:
 *   - `tickets_in_progress`: open tickets whose status name matches an
 *     "in progress" / "diagnosing" / "repair" keyword.
 *   - `ready_for_pickup`: open tickets whose status name matches a
 *     "ready for pickup" / "waiting for payment" keyword.
 *   - `recent_checkins`: the last 10 tickets created in the last 2 hours
 *     (so walk-ins can confirm their device was logged).
 *
 * All three lists respect `is_deleted = 0` and exclude closed/cancelled
 * statuses from the in-progress panel. Gated on `tv_display_enabled`.
 */
router.get('/board', asyncHandler(async (req: Request, res: Response) => {
  enforceTvRateLimit(req);
  const adb = req.asyncDb;
  const enabled = await isTvDisplayEnabled(adb);
  if (!enabled) {
    res.status(403).json({
      success: false,
      error: 'TV display is disabled. Enable "tv_display_enabled" in Settings to turn it on.',
    });
    return;
  }

  try {
    const payload = await buildTvBoard(adb);
    res.json({ success: true, data: payload });
  } catch (err) {
    logger.error('Failed to build TV board', { err: (err as Error).message });
    throw err;
  }
}));

/**
 * Build the full TV board payload. Separated so both `/` and `/board`
 * can share the same query logic.
 */
async function buildTvBoard(adb: Request['asyncDb']): Promise<TvBoardPayload> {
  // Build the LIKE conditions once. We match against the lower-cased status
  // name so the scheme survives custom tenant statuses like "Diagnosis — in
  // progress" or "Ready for pickup (front counter)".
  const inProgressLike = IN_PROGRESS_KEYWORDS.map(() => "LOWER(ts.name) LIKE ?").join(' OR ');
  const readyPickupLike = READY_PICKUP_KEYWORDS.map(() => "LOWER(ts.name) LIKE ?").join(' OR ');

  const inProgressParams = IN_PROGRESS_KEYWORDS.map((k) => `%${k}%`);
  const readyPickupParams = READY_PICKUP_KEYWORDS.map((k) => `%${k}%`);

  const baseSelect = `
    SELECT t.id, t.order_id, t.status_id, t.created_at, t.updated_at,
           ts.name AS status_name, ts.color AS status_color,
           ts.is_closed, ts.is_cancelled,
           c.first_name AS customer_first_name, c.last_name AS customer_last_name,
           u.first_name AS tech_first_name, u.last_name AS tech_last_name
    FROM tickets t
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN users u ON u.id = t.assigned_to
  `;

  const [inProgressRows, readyRows, recentRows] = await Promise.all([
    adb.all<TicketRow>(
      `${baseSelect}
       WHERE t.is_deleted = 0
         AND COALESCE(ts.is_closed, 0) = 0
         AND COALESCE(ts.is_cancelled, 0) = 0
         AND (${inProgressLike})
       ORDER BY t.updated_at DESC
       LIMIT 50`,
      ...inProgressParams,
    ),
    adb.all<TicketRow>(
      `${baseSelect}
       WHERE t.is_deleted = 0
         AND (${readyPickupLike})
       ORDER BY t.updated_at DESC
       LIMIT 50`,
      ...readyPickupParams,
    ),
    adb.all<TicketRow>(
      `${baseSelect}
       WHERE t.is_deleted = 0
         AND t.created_at >= datetime('now', '-2 hours')
       ORDER BY t.created_at DESC
       LIMIT 10`,
    ),
  ]);

  // Collect ticket ids across all three panels so we fetch device names
  // in one round trip instead of N per ticket. Use Set to dedupe the
  // recent-checkins that may also appear in in-progress.
  const allTicketIds = Array.from(
    new Set<number>([
      ...inProgressRows.map((r) => r.id),
      ...readyRows.map((r) => r.id),
      ...recentRows.map((r) => r.id),
    ]),
  );

  const devices: DeviceRow[] = allTicketIds.length
    ? await adb.all<DeviceRow>(
        // SCAN-1126: DISTINCT + ORDER BY so duplicate device-name rows
        // (accumulated via edit history) don't double-render on the TV
        // and poll-to-poll ordering is deterministic.
        `SELECT DISTINCT ticket_id, device_name FROM ticket_devices
         WHERE ticket_id IN (${allTicketIds.map(() => '?').join(',')})
         ORDER BY ticket_id, device_name`,
        ...allTicketIds,
      )
    : [];

  return {
    tickets_in_progress: inProgressRows.map((r) => shapeTicket(r, devices)),
    ready_for_pickup: readyRows.map((r) => shapeTicket(r, devices)),
    recent_checkins: recentRows.map((r) => shapeTicket(r, devices)),
    generated_at: new Date().toISOString(),
  };
}

export default router;
