/**
 * Public Booking Routes — no auth required (SCAN-471, android §58.3)
 *
 * Mounted at /public/api/v1/booking — NO authMiddleware here.
 *
 * Endpoints:
 *   GET /config            — visible services + hours + next-90-day exceptions + tenant info
 *   GET /availability      — available 30-min slots for a given service + date
 *
 * Security:
 *   - GET /config:        60 requests / IP / hr
 *   - GET /availability: 120 requests / IP / hr (more lenient — multi-date browsing)
 *   - Strict input validation (date regex, service_id integer guard)
 *   - No customer names or internal appointment details in responses
 *   - Cache-Control: public, max-age=60 on availability
 */

import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { createLogger } from '../utils/logger.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';

const router = Router();
const log = createLogger('bookingPublic');

// ---------------------------------------------------------------------------
// Rate limit categories
// ---------------------------------------------------------------------------
const RL = {
  CONFIG: 'pub_booking_config',         // IP → 60 / hr
  AVAILABILITY: 'pub_booking_avail',    // IP → 120 / hr
} as const;

const ONE_HOUR_MS = 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const DATE_RE = /^\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])$/;

function ipRateLimit(req: any, category: string, max: number): void {
  // SCAN-1105: previously keyed on raw `req.socket.remoteAddress` which
  // ignored Express `trust proxy`. Behind Cloudflare / any reverse proxy
  // every public-booking client arrived from the same proxy IP, so the
  // per-IP limit collapsed to one shared global bucket — useless against
  // distributed `/availability` enumeration. `req.ip` respects the app-
  // level trust-proxy config and falls back to the socket IP on direct
  // LAN access.
  const ip = (req.ip || req.socket?.remoteAddress || 'unknown').slice(0, 64);
  const result = consumeWindowRate(req.db, category, ip, max, ONE_HOUR_MS);
  if (!result.allowed) {
    throw new AppError(`Rate limit exceeded. Retry in ${result.retryAfterSeconds}s`, 429);
  }
}

function timeToMinutes(t: string): number {
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
}

// Parse "YYYY-MM-DD HH:MM" or ISO datetime to date string "YYYY-MM-DD"
function extractDate(dt: string): string {
  return dt.slice(0, 10);
}

// Parse "YYYY-MM-DD HH:MM" or ISO datetime to minutes-since-midnight
function extractMinutes(dt: string): number {
  // dt may be "2026-04-23 09:30:00" or "2026-04-23T09:30:00"
  const timePart = dt.slice(11, 16); // "HH:MM"
  if (!timePart || timePart.length < 5) return 0;
  return timeToMinutes(timePart);
}

interface SlotWindow {
  start_time: string;
  end_time: string;
}

/**
 * Generate candidate 30-min slots between open and close times.
 * Returns strings like "09:00", "09:30", …
 */
function generate30MinSlots(
  openMinutes: number,
  closeMinutes: number,
  durationMinutes: number,
): SlotWindow[] {
  const slots: SlotWindow[] = [];
  const slotSize = 30;
  let cursor = openMinutes;
  while (cursor + durationMinutes <= closeMinutes) {
    const startH = Math.floor(cursor / 60);
    const startM = cursor % 60;
    const endMin = cursor + durationMinutes;
    const endH = Math.floor(endMin / 60);
    const endMM = endMin % 60;
    slots.push({
      start_time: `${String(startH).padStart(2, '0')}:${String(startM).padStart(2, '0')}`,
      end_time:   `${String(endH).padStart(2, '0')}:${String(endMM).padStart(2, '0')}`,
    });
    cursor += slotSize;
  }
  return slots;
}

// ---------------------------------------------------------------------------
// GET /config
// ---------------------------------------------------------------------------

router.get('/config', asyncHandler(async (req, res) => {
  ipRateLimit(req, RL.CONFIG, 60);

  const adb = req.asyncDb;

  // Check booking is enabled
  const enabledRow = await adb.get<{ value: string }>(
    "SELECT value FROM store_config WHERE key = 'booking_enabled'",
  );
  if (!enabledRow || enabledRow.value !== '1') {
    res.json({ success: true, data: { enabled: false } });
    return;
  }

  // Visible + active services
  const services = await adb.all(
    `SELECT id, name, description, duration_minutes,
            buffer_before_minutes, buffer_after_minutes,
            deposit_required, deposit_amount_cents, sort_order
     FROM booking_services
     WHERE is_active = 1 AND visible_on_booking = 1
     ORDER BY sort_order, name`,
  );

  // All 7 booking_hours rows
  const hours = await adb.all(
    'SELECT day_of_week, open_time, close_time, is_active FROM booking_hours ORDER BY day_of_week',
  );

  // Exceptions in the next 90 days
  const exceptions = await adb.all(
    `SELECT date, is_closed, open_time, close_time, reason
     FROM booking_exceptions
     WHERE date >= date('now') AND date <= date('now', '+90 days')
     ORDER BY date`,
  );

  // Tenant display info (name + phone only — no internal data)
  const nameRow = await adb.get<{ value: string }>(
    "SELECT value FROM store_config WHERE key = 'store_name'",
  );
  const phoneRow = await adb.get<{ value: string }>(
    "SELECT value FROM store_config WHERE key = 'store_phone'",
  );

  // Booking settings
  const settingKeys = [
    'booking_min_notice_hours',
    'booking_max_lead_days',
    'booking_require_phone',
    'booking_require_email',
    'booking_confirmation_mode',
  ];
  const settingRows = await adb.all<{ key: string; value: string }>(
    `SELECT key, value FROM store_config WHERE key IN (${settingKeys.map(() => '?').join(',')})`,
    ...settingKeys,
  );
  const settings: Record<string, string> = {};
  for (const row of settingRows) {
    settings[row.key] = row.value;
  }

  res.json({
    success: true,
    data: {
      enabled: true,
      store_name: nameRow?.value ?? null,
      store_phone: phoneRow?.value ?? null,
      services,
      hours,
      exceptions,
      settings: {
        min_notice_hours:     parseInt(settings['booking_min_notice_hours'] ?? '24', 10),
        max_lead_days:        parseInt(settings['booking_max_lead_days'] ?? '30', 10),
        require_phone:        settings['booking_require_phone'] === '1',
        require_email:        settings['booking_require_email'] === '1',
        confirmation_mode:    settings['booking_confirmation_mode'] ?? 'manual',
      },
    },
  });
}));

// ---------------------------------------------------------------------------
// GET /availability?service_id=&date=YYYY-MM-DD
// ---------------------------------------------------------------------------

router.get('/availability', asyncHandler(async (req, res) => {
  ipRateLimit(req, RL.AVAILABILITY, 120);

  // --- Input validation ---
  const rawServiceId = req.query['service_id'];
  const rawDate = req.query['date'];

  if (!rawServiceId || typeof rawServiceId !== 'string') {
    throw new AppError('service_id is required', 400);
  }
  const serviceId = parseInt(rawServiceId, 10);
  if (!Number.isInteger(serviceId) || serviceId <= 0 || String(serviceId) !== rawServiceId.trim()) {
    throw new AppError('service_id must be a positive integer', 400);
  }

  if (!rawDate || typeof rawDate !== 'string' || !DATE_RE.test(rawDate)) {
    throw new AppError('date must be YYYY-MM-DD', 400);
  }
  const dateStr = rawDate;

  // Set Cache-Control after successful validation but before any DB query that could throw
  res.set('Cache-Control', 'public, max-age=60');

  const adb = req.asyncDb;

  // --- Booking enabled check ---
  const enabledRow = await adb.get<{ value: string }>(
    "SELECT value FROM store_config WHERE key = 'booking_enabled'",
  );
  if (!enabledRow || enabledRow.value !== '1') {
    res.json({ success: true, data: [] });
    return;
  }

  // --- Service lookup ---
  const service = await adb.get<{
    id: number;
    duration_minutes: number;
    buffer_before_minutes: number;
    buffer_after_minutes: number;
  }>(
    `SELECT id, duration_minutes, buffer_before_minutes, buffer_after_minutes
     FROM booking_services
     WHERE id = ? AND is_active = 1 AND visible_on_booking = 1`,
    serviceId,
  );
  if (!service) {
    throw new AppError('Invalid service', 400);
  }

  // --- Determine open/close for the requested date ---
  // Check exceptions first; fall back to weekly booking_hours.
  const exception = await adb.get<{
    is_closed: number;
    open_time: string | null;
    close_time: string | null;
  }>(
    'SELECT is_closed, open_time, close_time FROM booking_exceptions WHERE date = ?',
    dateStr,
  );

  let openMinutes: number;
  let closeMinutes: number;

  if (exception) {
    if (exception.is_closed || !exception.open_time || !exception.close_time) {
      // Day is closed or has no valid special hours
      res.json({ success: true, data: [] });
      return;
    }
    openMinutes  = timeToMinutes(exception.open_time);
    closeMinutes = timeToMinutes(exception.close_time);
  } else {
    // day_of_week: JS Date.getDay() — 0=Sun, 1=Mon, …, 6=Sat
    const dow = new Date(dateStr + 'T12:00:00Z').getUTCDay();
    const hoursRow = await adb.get<{
      is_active: number;
      open_time: string;
      close_time: string;
    }>(
      'SELECT is_active, open_time, close_time FROM booking_hours WHERE day_of_week = ?',
      dow,
    );
    if (!hoursRow || !hoursRow.is_active) {
      res.json({ success: true, data: [] });
      return;
    }
    openMinutes  = timeToMinutes(hoursRow.open_time);
    closeMinutes = timeToMinutes(hoursRow.close_time);
  }

  // --- min_notice_hours: reject dates too soon ---
  const minNoticeRow = await adb.get<{ value: string }>(
    "SELECT value FROM store_config WHERE key = 'booking_min_notice_hours'",
  );
  const minNoticeHours = parseInt(minNoticeRow?.value ?? '24', 10);
  const nowMs = Date.now();
  // Earliest bookable moment (in ms)
  const earliestBookableMs = nowMs + minNoticeHours * 60 * 60 * 1000;
  // End of the requested date (midnight next day UTC)
  const requestedDateEndMs = new Date(dateStr + 'T00:00:00Z').getTime() + 24 * 60 * 60 * 1000;
  if (requestedDateEndMs <= earliestBookableMs) {
    // Entire day is within the no-notice window
    res.json({ success: true, data: [] });
    return;
  }

  // --- max_lead_days: reject dates too far out ---
  const maxLeadRow = await adb.get<{ value: string }>(
    "SELECT value FROM store_config WHERE key = 'booking_max_lead_days'",
  );
  const maxLeadDays = parseInt(maxLeadRow?.value ?? '30', 10);
  const maxDateMs = nowMs + maxLeadDays * 24 * 60 * 60 * 1000;
  const requestedDateStartMs = new Date(dateStr + 'T00:00:00Z').getTime();
  if (requestedDateStartMs > maxDateMs) {
    res.json({ success: true, data: [] });
    return;
  }

  // --- Generate candidate slots ---
  const candidates = generate30MinSlots(openMinutes, closeMinutes, service.duration_minutes);
  if (candidates.length === 0) {
    res.json({ success: true, data: [] });
    return;
  }

  // --- Fetch existing appointments for the day ---
  // Only fetch start_time and end_time — no customer data returned to caller.
  const existingAppointments = await adb.all<{
    start_time: string;
    end_time: string | null;
  }>(
    `SELECT start_time, end_time
     FROM appointments
     WHERE date(start_time) = ?
       AND status NOT IN ('canceled', 'deleted')`,
    dateStr,
  );

  // Convert existing appointments to minute ranges (with service buffers applied)
  const bufBefore = service.buffer_before_minutes;
  const bufAfter  = service.buffer_after_minutes;

  const bookedRanges = existingAppointments.map((appt) => {
    const startMin = extractMinutes(appt.start_time);
    const endMin   = appt.end_time ? extractMinutes(appt.end_time) : startMin + 30;
    return {
      // Expand by caller's service buffers so we don't schedule too close
      start: startMin - bufBefore,
      end:   endMin + bufAfter,
    };
  });

  // --- min_notice_hours: also filter out today's slots that are too soon ---
  // SCAN-1119: previously compared slot open/close hours (which are LOCAL
  // to the tenant) against `new Date().getUTCHours()*60` (UTC minutes). On
  // a shop in America/Denver the "is today" check + min-notice comparison
  // crossed the midnight boundary incorrectly and either let same-day
  // slots through that violated notice, or blocked the next day's early
  // slots. Pull the tenant's `store_timezone` and compute both `nowMinutes`
  // and `isToday` in that zone using Intl.DateTimeFormat.
  const tzRow = (() => {
    try {
      return req.db
        .prepare("SELECT value FROM store_config WHERE key = 'store_timezone'")
        .get() as { value?: string } | undefined;
    } catch {
      return undefined;
    }
  })();
  const tenantTimeZone = (tzRow?.value && typeof tzRow.value === 'string' && tzRow.value.trim())
    || 'America/Denver';
  const localParts = new Intl.DateTimeFormat('en-CA', {
    timeZone: tenantTimeZone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hour12: false,
  }).formatToParts(new Date());
  const partMap = Object.fromEntries(localParts.map((p) => [p.type, p.value]));
  const localDateStr = `${partMap.year}-${partMap.month}-${partMap.day}`;
  // Intl hour='2-digit' hour12=false returns '00'..'24'; clamp 24 → 0.
  const localHours = Number(partMap.hour) === 24 ? 0 : Number(partMap.hour);
  const localMinutes = Number(partMap.minute);
  const nowMinutes = localHours * 60 + localMinutes;
  const isToday = dateStr === localDateStr;
  const minBookableMinutes = isToday ? nowMinutes + minNoticeHours * 60 : -1;

  // --- Filter slots ---
  const result = candidates.map((slot) => {
    const slotStart = timeToMinutes(slot.start_time);
    const slotEnd   = timeToMinutes(slot.end_time);

    // Violates min_notice?
    if (minBookableMinutes > 0 && slotStart < minBookableMinutes) {
      return { ...slot, available: false };
    }

    // Overlaps a booked range?
    const overlaps = bookedRanges.some(
      (r) => slotStart < r.end && slotEnd > r.start,
    );

    return { ...slot, available: !overlaps };
  });

  res.json({ success: true, data: result });

  log.info('availability computed', {
    serviceId,
    date: dateStr,
    total: candidates.length,
    available: result.filter((s) => s.available).length,
  });
}));

export default router;
