/**
 * Notification Preferences
 *
 * Canonical routes:
 *   - /api/v1/notification-preferences/me
 *   - /api/v1/users/me/notification-prefs
 *
 * SCAN-472
 * Auth:  authMiddleware applied at parent mount (index.ts) — not re-added here.
 * Authz: prefs are scoped strictly to the requesting user.
 *        No cross-user reads or writes.
 * Size:  total JSON payload cap enforced at 32 KB.
 */
import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { createLogger } from '../utils/logger.js';

const router = Router();
const logger = createLogger('notificationPrefs');

// ---------------------------------------------------------------------------
// Master event-type list — the single source of truth for valid event_types.
// Add new event types here when new notification categories are introduced.
// ---------------------------------------------------------------------------
const EVENT_TYPES: readonly string[] = [
  'global',
  'ticket_created',
  'ticket_status',
  'ticket_assigned',
  'ticket_status_auto',
  'sms_inbound',
  'mention',
  'team_mention',
  'invoice_created',
  'invoice_overdue',
  'payment_received',
  'payment_declined',
  'estimate_sent',
  'estimate_signed',
  'estimate_approved',
  'customer_created',
  'lead_new',
  'appointment_reminder',
  'inventory_low',
  'low_stock',
  'sla_breach',
  'shift_starting',
  'timeoff_request',
  'daily_summary',
  'weekly_digest',
  'setup_wizard_incomplete',
  'subscription_renewal',
  'integration_disconnected',
  'backup_complete',
  'backup_failed',
  'marketing_campaign',
  'dunning_step',
  'security_alert',
  'security_event',
  'system_update',
  'review_received',
  'refund_processed',
  'expense_submitted',
  'time_off_requested',
];
const EVENT_TYPE_SET = new Set(EVENT_TYPES);

const VALID_CHANNELS: readonly string[] = ['push', 'in_app', 'email', 'sms'];
const CHANNEL_SET = new Set(VALID_CHANNELS);

// Rate limit: 30 writes per minute per user for PUT /me
const WRITE_RATE_MAX = 30;
const WRITE_RATE_WINDOW_MS = 60_000;

// Max total payload size for PUT /me body
const MAX_PAYLOAD_BYTES = 32 * 1024;

interface PrefRow {
  user_id: number;
  event_type: string;
  channel: string;
  enabled: number;
  quiet_hours_json: string | null;
}

interface PrefOut {
  event_type: string;
  channel: string;
  enabled: boolean;
  quiet_hours: unknown | null;
  stored: boolean;
}

const DEFAULT_ENABLED: Record<string, Partial<Record<string, boolean>>> = {
  global: { push: true, in_app: true, email: true, sms: true },
  sms_inbound: { push: true, in_app: true, email: false, sms: false },
  appointment_reminder: { push: true, in_app: true, email: false, sms: false },
  mention: { push: true, in_app: true, email: false, sms: false },
  team_mention: { push: true, in_app: true, email: false, sms: false },
  ticket_assigned: { push: true, in_app: true, email: false, sms: false },
  ticket_created: { push: true, in_app: true, email: false, sms: false },
  ticket_status_auto: { push: true, in_app: true, email: false, sms: false },
  estimate_approved: { push: true, in_app: true, email: false, sms: false },
  payment_received: { push: true, in_app: true, email: false, sms: false },
  payment_declined: { push: true, in_app: true, email: false, sms: false },
  invoice_overdue: { push: true, in_app: true, email: true, sms: false },
  low_stock: { push: true, in_app: true, email: true, sms: false },
  inventory_low: { push: true, in_app: true, email: true, sms: false },
  sla_breach: { push: true, in_app: true, email: true, sms: false },
  shift_starting: { push: true, in_app: true, email: false, sms: false },
  timeoff_request: { push: true, in_app: true, email: false, sms: false },
  daily_summary: { push: false, in_app: true, email: true, sms: false },
  weekly_digest: { push: false, in_app: true, email: true, sms: false },
  setup_wizard_incomplete: { push: false, in_app: true, email: false, sms: false },
  subscription_renewal: { push: false, in_app: true, email: false, sms: false },
  integration_disconnected: { push: true, in_app: true, email: false, sms: false },
  backup_failed: { push: true, in_app: true, email: false, sms: false },
  security_event: { push: true, in_app: true, email: false, sms: false },
};

function defaultEnabled(eventType: string, channel: string): boolean {
  return DEFAULT_ENABLED[eventType]?.[channel] ?? true;
}

function parseQuietHours(raw: string | null): unknown | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

/**
 * Build the full matrix from stored rows, backfilling missing combos with
 * enabled=true so the UI always receives a complete grid.
 */
function buildMatrix(rows: PrefRow[]): PrefOut[] {
  // Index stored prefs by "event_type:channel"
  const stored = new Map<string, PrefRow>();
  for (const row of rows) {
    stored.set(`${row.event_type}:${row.channel}`, row);
  }

  const result: PrefOut[] = [];
  for (const et of EVENT_TYPES) {
    for (const ch of VALID_CHANNELS) {
      const key = `${et}:${ch}`;
      const row = stored.get(key);
      result.push({
        event_type: et,
        channel: ch,
        enabled: row ? row.enabled === 1 : defaultEnabled(et, ch),
        quiet_hours: row ? parseQuietHours(row.quiet_hours_json) : null,
        stored: Boolean(row),
      });
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// GET /me — return full notification preferences matrix for current user
// ---------------------------------------------------------------------------
const getNotificationPreferences = asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;

  const rows = await adb.all<PrefRow>(
    'SELECT user_id, event_type, channel, enabled, quiet_hours_json FROM notification_preferences WHERE user_id = ?',
    userId,
  );

  res.json({
    success: true,
    data: {
      preferences: buildMatrix(rows),
      event_types: Array.from(EVENT_TYPES),
      channels: Array.from(VALID_CHANNELS),
    },
  });
});

router.get(
  '/me',
  getNotificationPreferences,
);

// ---------------------------------------------------------------------------
// PUT/PATCH /me — upsert notification preference batch for current user
// ---------------------------------------------------------------------------
const upsertNotificationPreferences = asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const user = req.user!;

  // Rate-limit writes per user
  const rl = consumeWindowRate(req.db, 'notif_prefs_write', String(user.id), WRITE_RATE_MAX, WRITE_RATE_WINDOW_MS);
  if (!rl.allowed) {
    throw new AppError(`Too many preference updates. Retry in ${rl.retryAfterSeconds}s.`, 429);
  }

  // Enforce total payload size cap
  const rawBody = JSON.stringify(req.body);
  if (Buffer.byteLength(rawBody, 'utf8') > MAX_PAYLOAD_BYTES) {
    throw new AppError('Request body exceeds 32 KB limit', 413);
  }

  const { preferences } = req.body as { preferences?: unknown };
  if (!Array.isArray(preferences)) {
    throw new AppError('preferences must be an array', 400);
  }
  if (preferences.length === 0) {
    throw new AppError('preferences array must not be empty', 400);
  }
  // Cap array length to prevent degenerate payloads.
  if (preferences.length > EVENT_TYPES.length * VALID_CHANNELS.length) {
    throw new AppError(`preferences array exceeds maximum of ${EVENT_TYPES.length * VALID_CHANNELS.length} entries`, 400);
  }

  // Validate each item before touching the DB
  const validated: Array<{ event_type: string; channel: string; enabled: number; quiet_hours_json: string | null }> = [];
  for (let i = 0; i < preferences.length; i++) {
    const item = preferences[i] as Record<string, unknown>;
    if (typeof item !== 'object' || item === null) {
      throw new AppError(`preferences[${i}] must be an object`, 400);
    }

    const { event_type, channel, enabled, quiet_hours } = item;

    if (typeof event_type !== 'string' || !EVENT_TYPE_SET.has(event_type)) {
      throw new AppError(`preferences[${i}].event_type "${event_type}" is not a valid event type`, 400);
    }
    if (typeof channel !== 'string' || !CHANNEL_SET.has(channel)) {
      throw new AppError(`preferences[${i}].channel "${channel}" must be one of: ${VALID_CHANNELS.join(', ')}`, 400);
    }
    if (enabled !== undefined && typeof enabled !== 'boolean' && enabled !== 0 && enabled !== 1) {
      throw new AppError(`preferences[${i}].enabled must be a boolean`, 400);
    }

    let quietHoursJson: string | null = null;
    if (quiet_hours !== undefined && quiet_hours !== null) {
      try {
        quietHoursJson = JSON.stringify(quiet_hours);
        // Cap quiet_hours blob size
        if (Buffer.byteLength(quietHoursJson, 'utf8') > 1024) {
          throw new AppError(`preferences[${i}].quiet_hours exceeds 1 KB`, 400);
        }
      } catch (err) {
        if (err instanceof AppError) throw err;
        throw new AppError(`preferences[${i}].quiet_hours is not serializable`, 400);
      }
    }

    const enabledInt = enabled === false || enabled === 0 ? 0 : 1;
    validated.push({ event_type, channel, enabled: enabledInt, quiet_hours_json: quietHoursJson });
  }

  // Batch upsert in a single transaction
  const queries = validated.map((v) => ({
    sql: `INSERT INTO notification_preferences (user_id, event_type, channel, enabled, quiet_hours_json, updated_at)
          VALUES (?, ?, ?, ?, ?, strftime('%Y-%m-%d %H:%M:%S', 'now'))
          ON CONFLICT(user_id, event_type, channel) DO UPDATE SET
            enabled = excluded.enabled,
            quiet_hours_json = excluded.quiet_hours_json,
            updated_at = excluded.updated_at`,
    params: [user.id, v.event_type, v.channel, v.enabled, v.quiet_hours_json],
  }));

  await adb.transaction(queries);

  logger.info('notif_prefs: batch upsert', { user_id: user.id, count: validated.length });

  // Return updated full matrix
  const rows = await adb.all<PrefRow>(
    'SELECT user_id, event_type, channel, enabled, quiet_hours_json FROM notification_preferences WHERE user_id = ?',
    user.id,
  );

  res.json({
    success: true,
    data: {
      preferences: buildMatrix(rows),
      event_types: Array.from(EVENT_TYPES),
      channels: Array.from(VALID_CHANNELS),
    },
  });
});

router.put(
  '/me',
  upsertNotificationPreferences,
);

router.patch(
  '/me',
  upsertNotificationPreferences,
);

export const userNotificationPrefsRouter = Router();
userNotificationPrefsRouter.get(
  '/',
  getNotificationPreferences,
);
userNotificationPrefsRouter.put(
  '/',
  upsertNotificationPreferences,
);
userNotificationPrefsRouter.patch(
  '/',
  upsertNotificationPreferences,
);

export default router;
