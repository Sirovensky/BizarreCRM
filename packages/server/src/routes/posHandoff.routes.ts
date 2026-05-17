/**
 * POS phone-tap handoff — POS-PHONE-TAP-1.
 *
 * Two surfaces:
 *
 *   1. Device pairing (long-lived). The paired mobile app exchanges a one-time
 *      pairing code generated on the desktop session for a device_token that it
 *      then includes in subsequent /poll requests. We do NOT use shared
 *      cookies — the mobile app may not have access to the same auth domain.
 *
 *   2. Handoff queue (short-lived). When the desktop user taps a phone number
 *      anywhere (POS gate, ticket list, SMS app), the UI calls POST /pos/handoff
 *      with `action ∈ {call, sms_draft}` and a phone. We enqueue against
 *      every paired device for that user; the mobile app drains via GET
 *      /pos/handoff/poll within `expires_at` (default 90 s) and reports
 *      delivery back via POST /pos/handoff/:id/delivered. Pending rows past
 *      `expires_at` are swept to status='expired' on each poll.
 *
 * Web Push registration columns are present on `user_paired_devices` so a
 * future migration to real WebPush fan-out is a per-row update rather than
 * a new schema. For now we run pure-poll — it works on every phone with a
 * browser even without service-worker permissions.
 */
import { Router, Request, Response } from 'express';
import crypto from 'crypto';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { authMiddleware } from '../middleware/auth.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import { normalizePhone } from '../utils/phone.js';

const router = Router();
const logger = createLogger('posHandoff');

type AnyRow = Record<string, unknown>;

const PAIRING_CODE_TTL_MS = 10 * 60 * 1000; // 10 minutes
const HANDOFF_DEFAULT_TTL_S = 90; // poll within 90s or expire
// In-memory pairing-code store. Codes are single-use, expire after 10 min;
// they live in process memory only so a leaked DB row never lets an
// attacker take over a desktop session.
const pairingCodes = new Map<string, { userId: number; createdAt: number }>();

function makePairingCode(): string {
  // 8 hex chars (~32 bits) — adequate when paired with the 10-min TTL.
  return crypto.randomBytes(4).toString('hex').toUpperCase();
}

function makeDeviceToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

function reapExpiredHandoffs(asyncDb: Request['asyncDb']): Promise<unknown> {
  return asyncDb.run(
    `UPDATE pos_handoff_queue SET status = 'expired'
       WHERE status = 'pending' AND expires_at < datetime('now')`,
  );
}

// ── Pairing ─────────────────────────────────────────────────────────

router.post('/pair/start', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  // Sweep any past codes for this user — only one outstanding pairing flow
  // at a time per user keeps the in-memory map bounded.
  for (const [code, entry] of pairingCodes.entries()) {
    if (entry.userId === req.user!.id || Date.now() - entry.createdAt > PAIRING_CODE_TTL_MS) {
      pairingCodes.delete(code);
    }
  }
  const code = makePairingCode();
  pairingCodes.set(code, { userId: req.user!.id, createdAt: Date.now() });
  res.json({
    success: true,
    data: { code, expires_in_seconds: PAIRING_CODE_TTL_MS / 1000 },
  });
}));

router.post('/pair/complete', asyncHandler(async (req: Request, res: Response) => {
  // No authMiddleware — the mobile app exchanges a code for a device_token
  // without being logged in. Authentication identity comes from the code
  // owner; we issue a token scoped to that user.
  const code = String(req.body?.code ?? '').trim().toUpperCase();
  const label = typeof req.body?.label === 'string' ? req.body.label.slice(0, 64) : null;
  const platform = typeof req.body?.platform === 'string' ? req.body.platform.slice(0, 32) : null;
  if (!code) {
    res.status(400).json({ success: false, message: 'Pairing code is required.' });
    return;
  }
  const entry = pairingCodes.get(code);
  if (!entry || Date.now() - entry.createdAt > PAIRING_CODE_TTL_MS) {
    pairingCodes.delete(code);
    res.status(400).json({ success: false, code: 'ERR_PAIRING_CODE_EXPIRED', message: 'Pairing code is invalid or expired.' });
    return;
  }
  pairingCodes.delete(code); // single-use
  const adb = req.asyncDb;
  const deviceToken = makeDeviceToken();
  await adb.run(
    `INSERT INTO user_paired_devices (user_id, device_token, device_label, platform, last_seen_at)
       VALUES (?, ?, ?, ?, datetime('now'))`,
    entry.userId, deviceToken, label, platform,
  );
  audit(req.db, 'pos_handoff_device_paired', entry.userId, req.ip || 'unknown', { label, platform });
  res.json({ success: true, data: { device_token: deviceToken } });
}));

router.get('/devices', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const rows = await adb.all<AnyRow>(
    `SELECT id, device_label, platform, last_seen_at, created_at
       FROM user_paired_devices
      WHERE user_id = ?
      ORDER BY last_seen_at DESC NULLS LAST, created_at DESC`,
    req.user!.id,
  );
  res.json({ success: true, data: rows });
}));

router.delete('/devices/:id', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const deviceId = Number(req.params.id);
  if (!Number.isInteger(deviceId) || deviceId <= 0) {
    res.status(400).json({ success: false, message: 'Invalid device id.' });
    return;
  }
  const result = await adb.run(
    'DELETE FROM user_paired_devices WHERE id = ? AND user_id = ?',
    deviceId, req.user!.id,
  );
  if (result.changes === 0) {
    res.status(404).json({ success: false, message: 'Device not found.' });
    return;
  }
  audit(req.db, 'pos_handoff_device_removed', req.user!.id, req.ip || 'unknown', { device_id: deviceId });
  res.json({ success: true });
}));

// ── Handoff (enqueue → poll) ───────────────────────────────────────

router.post('/handoff', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const action = String(req.body?.action ?? '').toLowerCase();
  if (action !== 'call' && action !== 'sms_draft') {
    res.status(400).json({ success: false, message: 'action must be "call" or "sms_draft".' });
    return;
  }
  const phone = normalizePhone(String(req.body?.phone ?? ''));
  if (!phone) {
    res.status(400).json({ success: false, message: 'Valid phone is required.' });
    return;
  }
  const payload = req.body?.payload ?? null;
  const payloadJson = payload ? JSON.stringify(payload).slice(0, 2048) : null;
  const ttlSeconds = Number.isFinite(Number(req.body?.ttl_seconds))
    ? Math.min(600, Math.max(15, Number(req.body.ttl_seconds)))
    : HANDOFF_DEFAULT_TTL_S;

  // Only enqueue if the user has at least one paired device that has called
  // /poll within the last 5 minutes — otherwise the action would expire silently
  // and the desktop user would think the handoff worked.
  const devices = await adb.all<AnyRow>(
    `SELECT id FROM user_paired_devices
      WHERE user_id = ? AND last_seen_at >= datetime('now','-5 minutes')`,
    userId,
  );
  if (devices.length === 0) {
    res.status(409).json({
      success: false,
      code: 'ERR_NO_ACTIVE_PAIRED_DEVICE',
      message: 'No paired mobile device has checked in recently. Pair a device under Settings → Account.',
    });
    return;
  }

  const inserts: number[] = [];
  for (const dev of devices) {
    const result = await adb.run(
      `INSERT INTO pos_handoff_queue
         (target_user_id, target_device_id, action, phone, payload_json, created_by, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, datetime('now', '+' || ? || ' seconds'))`,
      userId, dev.id as number, action, phone, payloadJson, userId, ttlSeconds,
    );
    inserts.push(Number(result.lastInsertRowid));
  }
  audit(req.db, 'pos_handoff_enqueued', userId, req.ip || 'unknown', {
    action, phone, queue_ids: inserts, device_count: devices.length,
  });
  res.json({ success: true, data: { handoff_ids: inserts, device_count: devices.length, expires_in_seconds: ttlSeconds } });
}));

router.get('/handoff/poll', asyncHandler(async (req: Request, res: Response) => {
  // Polled by the paired mobile app — Authorization: Bearer <device_token>.
  const authHeader = req.headers.authorization || '';
  const deviceToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
  if (!deviceToken || deviceToken.length < 32) {
    res.status(401).json({ success: false, message: 'Device token required.' });
    return;
  }
  const adb = req.asyncDb;
  const device = await adb.get<{ id: number; user_id: number }>(
    'SELECT id, user_id FROM user_paired_devices WHERE device_token = ?',
    deviceToken,
  );
  if (!device) {
    res.status(401).json({ success: false, message: 'Unknown device token.' });
    return;
  }
  // Refresh last_seen_at so the desktop knows this device is alive.
  await adb.run(
    "UPDATE user_paired_devices SET last_seen_at = datetime('now') WHERE id = ?",
    device.id,
  );
  await reapExpiredHandoffs(adb);

  const pending = await adb.all<AnyRow>(
    `SELECT id, action, phone, payload_json, created_at, expires_at
       FROM pos_handoff_queue
      WHERE target_device_id = ? AND status = 'pending'
        AND expires_at >= datetime('now')
      ORDER BY created_at ASC
      LIMIT 25`,
    device.id,
  );
  // Mark each row delivered immediately so the same handoff is not handed to
  // multiple poll calls. The mobile app is expected to honor what it just
  // received; if it crashes mid-action, the user re-taps and a fresh row
  // gets enqueued.
  // BUGHUNT-2026-05-17: per-row guarded claim. Previously the bulk UPDATE
  // had no `AND status = 'pending'` guard and the SELECT didn't lock the
  // rows, so two parallel polls from the same device (e.g. a retried
  // request, or two browser tabs) would both SELECT the same row, both
  // flip it to 'delivered', and both return it to their respective
  // callers — the mobile app then placed two calls / sent two SMS
  // drafts for one handoff. Per-row guarded UPDATE means only one poller
  // wins each row; the loser's returned list drops that row.
  const claimedIds = new Set<number>();
  for (const p of pending) {
    const result = await adb.run(
      `UPDATE pos_handoff_queue SET status = 'delivered', delivered_at = datetime('now')
         WHERE id = ? AND status = 'pending'`,
      p.id,
    );
    if (result.changes > 0) {
      claimedIds.add(p.id as number);
    }
  }
  const delivered = pending.filter((p) => claimedIds.has(p.id as number));
  res.json({ success: true, data: delivered });
}));

router.post('/handoff/:id/cancel', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    res.status(400).json({ success: false, message: 'Invalid handoff id.' });
    return;
  }
  const result = await adb.run(
    `UPDATE pos_handoff_queue SET status = 'cancelled'
       WHERE id = ? AND target_user_id = ? AND status = 'pending'`,
    id, req.user!.id,
  );
  res.json({ success: true, data: { cancelled: result.changes > 0 } });
}));

logger.info('pos handoff routes mounted');
export default router;
