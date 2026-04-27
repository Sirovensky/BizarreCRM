import { Router, Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import { config } from '../config.js';
import { AppError } from '../middleware/errorHandler.js';
import { getSmsProvider, getProviderForDb, getVoiceConfig } from '../services/smsProvider.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { broadcast } from '../ws/server.js';
import { escapeXml } from '../utils/xml.js';
import { getConfigValue } from '../utils/configEncryption.js';
import { checkWindowRate, recordWindowAttempt } from '../utils/rateLimiter.js';
import { reserveStorage } from '../services/usageTracker.js';
import { getMasterDb } from '../db/master-connection.js';
import { getPlanDefinition, type TenantPlan } from '@bizarre-crm/shared';
import type { AsyncDb } from '../db/async-db.js';
import { escapeLike } from '../utils/query.js';
import { createLogger } from '../utils/logger.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';

const logger = createLogger('voice.routes');

// SEC-H93: Allowlist of hosts that may supply voice recording URLs.
// Auth headers (Twilio Basic Auth, Telnyx Bearer) are sent on these fetches —
// any non-allowlisted host would receive our provider credentials (credential exfil).
// IP-literal URLs are separately rejected. Reject-by-default.
const ALLOWED_VOICE_HOSTS = new Set([
  'api.twilio.com',          // Twilio recordings: /Accounts/.../Recordings/*.mp3
  'voice.bandwidth.com',     // Bandwidth recording media
  'api.telnyx.com',          // Telnyx recordings
  'api.plivo.com',           // Plivo recordings
  'api.nexmo.com',           // Vonage (Nexmo) recordings
]);

/**
 * SEC-H93: Validate that a recording URL is from an allowed provider host.
 * Throws with a descriptive reason on rejection.
 * Callers catch and log; the recording is skipped (no download, no credential send).
 */
function validateRecordingUrl(url: string): void {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error(`recording URL parse failed — rejecting`);
  }

  if (parsed.protocol !== 'https:') {
    throw new Error(`only https: URLs allowed for recordings, got ${parsed.protocol}`);
  }

  const { hostname } = parsed;

  // Reject IP-literal addresses — SSRF path to cloud metadata / internal hosts.
  const isIpv4 = /^\d{1,3}(\.\d{1,3}){3}$/.test(hostname);
  const isIpv6 = hostname.startsWith('[');
  if (isIpv4 || isIpv6) {
    throw new Error(`IP-literal recording URL rejected (${hostname})`);
  }

  if (!ALLOWED_VOICE_HOSTS.has(hostname)) {
    throw new Error(`recording host not in allowlist (${hostname})`);
  }
}

const router = Router();

type AnyRow = Record<string, any>;

const recordingsDir = path.join(config.uploadsPath, 'recordings');
if (!fs.existsSync(recordingsDir)) fs.mkdirSync(recordingsDir, { recursive: true });

// ---------------------------------------------------------------------------
// POST /voice/call — Initiate click-to-call (auth required)
// ---------------------------------------------------------------------------
router.post('/call', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { to, mode, entity_type, entity_id } = req.body as {
    to?: string; mode?: 'bridge' | 'push'; entity_type?: string; entity_id?: number;
  };

  if (!to) throw new AppError('Recipient phone number is required', 400);

  // SCAN-719: prevent credit-depletion + provider-DoS via bulk call triggers
  const userId = req.user!.id;
  if (!checkWindowRate(req.db, 'voice_call', String(userId), 10, 60_000)) {
    throw new AppError('Too many call attempts — try again later', 429);
  }
  recordWindowAttempt(req.db, 'voice_call', String(userId), 60_000);

  // PROD104: Emergency kill-switch. When DISABLE_OUTBOUND_VOICE=true, suppress
  // all outbound call origination immediately without a code deployment. Return
  // a synthesised success-shape with { suppressed: true, reason: 'kill-switch' }
  // so callers can distinguish a suppressed call from a provider failure.
  if (config.disableOutboundVoice) {
    logger.warn('[kill-switch] outbound voice call suppressed', { toLength: to.length, userId: req.user!.id });
    res.status(200).json({
      success: true,
      data: { suppressed: true, reason: 'kill-switch' },
    });
    return;
  }

  const provider = getSmsProvider();
  if (!provider.initiateCall) {
    throw new AppError('Voice calls not supported by current provider', 400);
  }

  const voiceCfg = getVoiceConfig(db);
  const storePhone = (await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'store_phone'"))?.value || '';
  const autoRecord = voiceCfg.voice_auto_record === '1' || voiceCfg.voice_auto_record === 'true';
  const autoTranscribe = voiceCfg.voice_auto_transcribe === '1' || voiceCfg.voice_auto_transcribe === 'true';

  // For push mode, get tech's mobile number
  let pushTo: string | undefined;
  if (mode === 'push') {
    const user = await adb.get<AnyRow>('SELECT mobile_number FROM users WHERE id = ?', req.user!.id);
    if (!user?.mobile_number) {
      throw new AppError('Your mobile number is not set. Update it in your profile to use "Send to Phone".', 400);
    }
    pushTo = user.mobile_number;
  }

  // Determine callback base URL.
  // SCAN-715: always HTTPS — call metadata (transcripts, recordings, caller IDs)
  // is PII + sensitive business data. Dev can use self-signed cert; the provider
  // must accept it. Never plaintext HTTP even in dev.
  const lanIp = getLanIp();
  const callbackBaseUrl = config.nodeEnv === 'production'
    ? `https://${req.get('host')}`
    : `https://${lanIp}:${config.port}`;

  const convPhone = to.replace(/\D/g, '').replace(/^1/, '');

  const result = await provider.initiateCall(to, storePhone, {
    mode: mode || 'bridge',
    pushTo,
    record: autoRecord,
    transcribe: autoTranscribe,
    callbackBaseUrl,
  });

  // Log to call_logs
  const logResult = await adb.run(`
    INSERT INTO call_logs (direction, from_number, to_number, conv_phone, provider, provider_call_id,
                           status, call_mode, user_id, entity_type, entity_id)
    VALUES ('outbound', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `,
    storePhone, to, convPhone,
    provider.name, result.callId || null,
    result.success ? 'initiated' : 'failed',
    mode || 'bridge',
    req.user!.id,
    entity_type || null, entity_id || null,
  );

  if (!result.success) {
    throw new AppError(result.error || 'Failed to initiate call', 500);
  }

  const callLog = await adb.get<AnyRow>('SELECT * FROM call_logs WHERE id = ?', logResult.lastInsertRowid);

  broadcast('voice:call_initiated', { call: callLog }, req.tenantSlug || null);

  res.status(201).json({ success: true, data: callLog });
}));

// ---------------------------------------------------------------------------
// GET /voice/calls — Call history (auth required)
// ---------------------------------------------------------------------------
// @audit-fixed: §37 — Previously every authenticated user (technician,
// receptionist, anyone) could list ALL call logs across the shop, including
// recordings + transcriptions. Restrict by-default to the user's own calls,
// allow admin/manager to see everything (managers need this for QA), and let
// anyone see calls scoped to a specific entity_type+entity_id (e.g. the
// ticket-detail call panel).
router.get('/calls', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const page = parsePage(req.query.page);
  const pageSize = parsePageSize(req.query.pagesize, 20);
  const convPhone = req.query.conv_phone as string | undefined;
  const entityType = req.query.entity_type as string | undefined;
  const entityId = req.query.entity_id as string | undefined;

  let where = 'WHERE 1=1';
  const params: any[] = [];

  if (convPhone) { where += ' AND cl.conv_phone = ?'; params.push(convPhone); }
  if (entityType && entityId) {
    where += ' AND cl.entity_type = ? AND cl.entity_id = ?';
    params.push(entityType, parseInt(entityId, 10));
  }

  // @audit-fixed: §37 — restrict non-admin users to their own outbound +
  // inbound calls when no entity scope is provided.
  const isAdmin = req.user!.role === 'admin' || req.user!.role === 'manager';
  if (!isAdmin && !(entityType && entityId)) {
    where += ' AND (cl.user_id = ? OR cl.direction = ?)';
    params.push(req.user!.id, 'inbound');
  }

  const total = ((await adb.get<AnyRow>(`SELECT COUNT(*) as cnt FROM call_logs cl ${where}`, ...params))!).cnt;
  const totalPages = Math.ceil(total / pageSize);
  const offset = (page - 1) * pageSize;

  const calls = await adb.all<AnyRow>(`
    SELECT cl.*, u.first_name || ' ' || u.last_name AS user_name
    FROM call_logs cl
    LEFT JOIN users u ON u.id = cl.user_id
    ${where}
    ORDER BY cl.created_at DESC
    LIMIT ? OFFSET ?
  `, ...params, pageSize, offset);

  res.json({
    success: true,
    data: { calls, pagination: { page, per_page: pageSize, total, total_pages: totalPages } },
  });
}));

// ---------------------------------------------------------------------------
// GET /voice/calls/:id — Single call detail (auth required)
// ---------------------------------------------------------------------------
// @audit-fixed: §37 — Previously any authenticated user could view any call
// detail (including transcription, recording_url, conv_phone). Limit to the
// user who placed the call OR an admin/manager.
router.get('/calls/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const call = await adb.get<AnyRow>(`
    SELECT cl.*, u.first_name || ' ' || u.last_name AS user_name
    FROM call_logs cl
    LEFT JOIN users u ON u.id = cl.user_id
    WHERE cl.id = ?
  `, req.params.id);

  if (!call) throw new AppError('Call not found', 404);
  const isAdmin = req.user!.role === 'admin' || req.user!.role === 'manager';
  if (!isAdmin && call.user_id !== req.user!.id && call.direction !== 'inbound') {
    throw new AppError('Not authorized to view this call', 403);
  }
  res.json({ success: true, data: call });
}));

// ---------------------------------------------------------------------------
// GET /voice/calls/:id/recording-token — Issue a short-lived signed token
// ---------------------------------------------------------------------------
// WEB-W3-023: The old pattern opened recordings via a raw URL in a new tab,
// which bypasses the axios auth header. The fix is a two-step pattern:
//   1. Frontend calls this endpoint (JWT-authed) to get a short-lived HMAC
//      token (30s TTL) bound to the call ID.
//   2. Frontend opens /voice/calls/:id/recording?token=<signed> — that route
//      validates the HMAC before streaming, so no cookie or Bearer header is
//      needed for the GET that the browser tab initiates.
//
// HMAC construction: HMAC-SHA256( uploadsSecret, "<call_id>|<expires_unix>" )
// Token wire format: "<expires_unix>.<hex_hmac>" (URL-safe, no padding needed)
router.post('/calls/:id/recording-token', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const callId = parseInt(String(req.params.id), 10);
  if (!callId || isNaN(callId)) throw new AppError('Invalid call id', 400);

  const call = await adb.get<AnyRow>('SELECT user_id, direction FROM call_logs WHERE id = ?', callId);
  if (!call) throw new AppError('Call not found', 404);

  const isAdmin = req.user!.role === 'admin' || req.user!.role === 'manager';
  if (!isAdmin && call.user_id !== req.user!.id && call.direction !== 'inbound') {
    throw new AppError('Not authorized to access this recording', 403);
  }

  const expires = Math.floor(Date.now() / 1000) + 30; // 30-second window
  const payload = `${callId}|${expires}`;
  const hmac = crypto.createHmac('sha256', config.uploadsSecret).update(payload).digest('hex');
  const token = `${expires}.${hmac}`;

  res.json({ success: true, data: { token } });
}));

// ---------------------------------------------------------------------------
// GET /voice/calls/:id/recording — Stream recording audio
// ---------------------------------------------------------------------------
// Accepts either:
//   - JWT auth (Bearer / cookie) — full access check (existing flow)
//   - ?token=<signed> — short-lived HMAC token issued by /recording-token
//     above; no session cookie needed (browser new-tab / <audio> src).
//
// @audit-fixed: §37 — Same authorization gap. Recordings may contain
// sensitive customer information (CC numbers spoken aloud, PII, etc.) so
// gate them by user_id or admin/manager just like the detail endpoint.
router.get('/calls/:id/recording', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const callId = parseInt(String(req.params.id), 10);
  if (!callId || isNaN(callId)) throw new AppError('Invalid call id', 400);

  // --- WEB-W3-023: token-based auth path ---
  const rawToken = req.query.token as string | undefined;
  if (rawToken) {
    const dotIdx = rawToken.indexOf('.');
    if (dotIdx === -1) throw new AppError('Invalid recording token', 403);
    const expires = parseInt(rawToken.slice(0, dotIdx), 10);
    const provided = rawToken.slice(dotIdx + 1);
    const nowSec = Math.floor(Date.now() / 1000);
    if (!expires || isNaN(expires) || expires < nowSec) {
      throw new AppError('Recording token expired', 403);
    }
    const payload = `${callId}|${expires}`;
    const expected = crypto.createHmac('sha256', config.uploadsSecret).update(payload).digest('hex');
    // Constant-time comparison to prevent timing attacks
    if (!crypto.timingSafeEqual(Buffer.from(provided, 'hex'), Buffer.from(expected, 'hex'))) {
      throw new AppError('Invalid recording token', 403);
    }
    // Token is valid — skip user-level auth; token already binds to call id.
  } else {
    // --- Traditional JWT auth path ---
    const call = await adb.get<AnyRow>('SELECT user_id, direction FROM call_logs WHERE id = ?', callId);
    if (!call) throw new AppError('Call not found', 404);
    const isAdmin = req.user!.role === 'admin' || req.user!.role === 'manager';
    if (!isAdmin && call.user_id !== req.user!.id && call.direction !== 'inbound') {
      throw new AppError('Not authorized to access this recording', 403);
    }
  }

  const call = await adb.get<AnyRow>('SELECT recording_local_path, recording_url FROM call_logs WHERE id = ?', callId);
  if (!call) throw new AppError('Call not found', 404);

  if (call.recording_local_path && fs.existsSync(path.join(config.uploadsPath, call.recording_local_path.replace(/^\/uploads\//, '')))) {
    const filePath = path.join(config.uploadsPath, call.recording_local_path.replace(/^\/uploads\//, ''));
    res.setHeader('Content-Type', 'audio/mpeg');
    // WEB-W3-023: allow range requests so the <audio> element can seek.
    res.setHeader('Accept-Ranges', 'bytes');
    fs.createReadStream(filePath).pipe(res);
    return;
  }

  if (call.recording_url) {
    // SCAN-721: revalidate URL against provider allowlist before redirecting —
    // a malicious webhook could store an attacker-controlled URL in recording_url.
    try {
      validateRecordingUrl(call.recording_url);
    } catch (err) {
      throw new AppError('Recording URL not trusted', 403);
    }
    res.redirect(call.recording_url);
    return;
  }

  throw new AppError('Recording not available', 404);
}));

// ---------------------------------------------------------------------------
// POST /voice/call/:id/hangup — Hang up an active call (auth required)
// ---------------------------------------------------------------------------
// AUDIT T1 / MW7: This endpoint was a "lying endpoint" — it updated the DB row
// to status='completed' but never actually told the telephony provider to tear
// down the call. Clients saw a 200/success and assumed the line was hung up,
// but the remote leg kept billing. Return 501 NOT_IMPLEMENTED instead so
// callers know this is not yet wired to a provider. Auth checks still run
// first so callers still get clear 401/403/404 responses when applicable.
//
// TODO(MEDIUM, §26, voice-hangup): Implement per-provider hangup by reading the provider
// type from store_config, instantiating the provider client, and calling its
// hangup/end-call API (Twilio callSid.update({status:'completed'}), Telnyx
// /calls/:id/actions/hangup, Bandwidth /calls/:id {state:'completed'}, etc.)
// with the call's external provider_call_id before touching local state. Only
// after the provider ACKs should the local status be updated to 'completed'.
router.post('/call/:id/hangup', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const call = await adb.get<AnyRow>('SELECT id, user_id, status FROM call_logs WHERE id = ?', req.params.id);
  if (!call) throw new AppError('Call not found', 404);

  // Only the user who initiated the call or an admin can hang up
  if (call.user_id !== req.user!.id && req.user!.role !== 'admin') {
    throw new AppError('Not authorized to hang up this call', 403);
  }

  if (call.status === 'completed' || call.status === 'failed') {
    throw new AppError('Call is already ended', 400);
  }

  res.status(501).json({
    success: false,
    error: 'Voice hangup not yet integrated with telephony provider',
    code: 'NOT_IMPLEMENTED',
  });
}));

export default router;

// ============================================================================
// PUBLIC WEBHOOKS (no auth) — exported for index.ts to mount separately
// ============================================================================

/** Voice call status webhook — called by provider when call status changes */
export async function voiceStatusWebhookHandler(req: Request, res: Response): Promise<void> {
  try {
    const db = req.db;
    const adb = req.asyncDb;
    const provider = getProviderForDb(db, (req as any).tenantSlug);

    // Verify webhook signature (same pattern as SMS webhooks)
    if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) {
      logger.warn('voice status webhook signature verification failed', { ip: req.ip, provider: provider.name ?? 'unknown' });
      res.status(403).json({ success: false, message: 'Invalid signature' });
      return;
    }

    if (!provider.parseCallWebhook) {
      res.status(200).json({ success: true });
      return;
    }

    const event = provider.parseCallWebhook(req);
    if (!event) {
      res.status(200).json({ success: true });
      return;
    }

    const call = await adb.get<AnyRow>('SELECT id FROM call_logs WHERE provider_call_id = ?', event.providerCallId);
    if (!call) {
      // Might be an inbound call — create new log
      if (event.direction === 'inbound') {
        const convPhone = (event.from || '').replace(/\D/g, '').replace(/^1/, '');
        await adb.run(`
          INSERT INTO call_logs (direction, from_number, to_number, conv_phone, provider, provider_call_id, status)
          VALUES ('inbound', ?, ?, ?, ?, ?, ?)
        `, event.from || '', event.to || '', convPhone, provider.name, event.providerCallId, event.status);
      }
      res.status(200).json({ success: true });
      return;
    }

    // Update existing call log
    const updates: string[] = ['status = ?', "updated_at = datetime('now')"];
    const params: any[] = [event.status];

    if (event.duration != null) { updates.push('duration_secs = ?'); params.push(event.duration); }
    if (event.recordingUrl) { updates.push('recording_url = ?'); params.push(event.recordingUrl); }

    params.push(call.id);
    await adb.run(`UPDATE call_logs SET ${updates.join(', ')} WHERE id = ?`, ...params);

    broadcast('voice:call_updated', { callId: call.id, status: event.status, duration: event.duration }, req.tenantSlug || null);

    res.status(200).json({ success: true });
  } catch (err: any) {
    logger.error('voice status webhook pipeline crashed', { error: err instanceof Error ? err.message : String(err) });
    res.status(200).json({ success: false });
  }
}

/** Recording ready webhook — download and store recording locally */
export async function voiceRecordingWebhookHandler(req: Request, res: Response): Promise<void> {
  try {
    const db = req.db;
    const adb = req.asyncDb;
    const provider = getProviderForDb(db, (req as any).tenantSlug);

    if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) {
      logger.warn('voice recording webhook signature verification failed', { ip: req.ip, provider: provider.name ?? 'unknown' });
      res.status(403).json({ success: false, message: 'Invalid signature' });
      return;
    }

    const event = provider.parseCallWebhook ? provider.parseCallWebhook(req) : null;

    const providerCallId = event?.providerCallId || req.body?.CallSid || req.body?.call_control_id || req.body?.callId;
    const recordingUrl = event?.recordingUrl || req.body?.RecordingUrl || req.body?.recording_urls?.mp3;
    const recordingId = event?.recordingId || req.body?.RecordingSid || req.body?.recording_id;

    if (!providerCallId) {
      res.status(200).json({ success: true });
      return;
    }

    const call = await adb.get<AnyRow>('SELECT id FROM call_logs WHERE provider_call_id = ?', providerCallId);
    if (!call) {
      res.status(200).json({ success: true });
      return;
    }

    // Download recording
    let localPath: string | null = null;
    const downloadUrl = recordingUrl || (recordingId && provider.getRecordingUrl ? await provider.getRecordingUrl(recordingId) : null);

    if (downloadUrl) {
      try {
        // SEC-H93: Validate recording URL against provider allowlist BEFORE building
        // auth headers. Without this check, a forged webhook (or signature miss)
        // could supply an attacker-controlled URL and receive our Twilio Basic Auth /
        // Telnyx Bearer token — a direct credential-exfiltration path.
        // Also rejects IP-literal URLs (SSRF to cloud metadata / internal hosts).
        validateRecordingUrl(downloadUrl);
        const MAX_RECORDING_SIZE = 50 * 1024 * 1024; // 50MB limit for recordings
        // Get Twilio credentials from tenant DB (auto-decrypted)
        const headers: Record<string, string> = {};
        if (provider.name === 'twilio') {
          const sid = getConfigValue(db, 'sms_twilio_account_sid');
          const authTok = getConfigValue(db, 'sms_twilio_auth_token');
          if (sid && authTok) {
            headers['Authorization'] = 'Basic ' + Buffer.from(`${sid}:${authTok}`).toString('base64');
          }
        }
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 30_000); // 30s timeout
        // SEC-H93 / SEC-H92: Never follow redirects — a 3xx from a provider host
        // pointing to an internal/attacker address would bypass the allowlist.
        const resp = await fetch(downloadUrl, { headers, signal: controller.signal, redirect: 'error' });
        clearTimeout(timeout);
        if (resp.ok) {
          const contentLength = parseInt(resp.headers.get('content-length') || '0', 10);
          if (contentLength > MAX_RECORDING_SIZE) {
            logger.warn('voice recording too large (content-length), skipping', { downloadUrl, contentLength, maxSize: MAX_RECORDING_SIZE });
          } else {
            const chunks: Buffer[] = [];
            let totalSize = 0;
            const reader = resp.body?.getReader();
            let oversize = false;
            if (reader) {
              while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                totalSize += value.byteLength;
                if (totalSize > MAX_RECORDING_SIZE) {
                  reader.cancel();
                  logger.warn('voice recording exceeded 50MB during download, skipping', { downloadUrl, totalSize, maxSize: MAX_RECORDING_SIZE });
                  oversize = true;
                  break;
                }
                chunks.push(Buffer.from(value));
              }
            }
            if (!oversize && chunks.length > 0) {
              const buffer = Buffer.concat(chunks);
              const slug = (req as any).tenantSlug;

              // Storage tier check (only relevant in multi-tenant mode).
              // The webhook doesn't have req.tenantLimits set (it bypasses tenantResolver),
              // so we need to look up the tenant's plan from the master DB ourselves.
              if (config.multiTenant && slug) {
                const masterDb = getMasterDb();
                if (masterDb) {
                  const tenantRow = masterDb.prepare(
                    'SELECT id, plan, storage_limit_mb, trial_ends_at FROM tenants WHERE slug = ?'
                  ).get(slug) as { id: number; plan: string; storage_limit_mb: number | null; trial_ends_at: string | null } | undefined;
                  if (tenantRow) {
                    const trialActive = !!tenantRow.trial_ends_at && new Date(tenantRow.trial_ends_at).getTime() > Date.now();
                    const effectivePlan: TenantPlan = trialActive ? 'pro' : (tenantRow.plan === 'pro' ? 'pro' : 'free');
                    const planDef = getPlanDefinition(effectivePlan);
                    const limitMb = effectivePlan === 'pro'
                      ? planDef.limits.storageLimitMb
                      : (tenantRow.storage_limit_mb ?? planDef.limits.storageLimitMb);
                    if (!reserveStorage(tenantRow.id, buffer.length, limitMb)) {
                      logger.warn('voice recording dropped: tenant storage limit reached', { slug, bytes: buffer.length });
                      // Don't write the file. Skip transcription. Mark recording_url so the call log isn't broken.
                      localPath = null;
                      throw new Error('storage_limit_reached');
                    }
                  }
                }
              }

              const recDir = slug ? path.join(config.uploadsPath, slug, 'recordings') : recordingsDir;
              if (!fs.existsSync(recDir)) fs.mkdirSync(recDir, { recursive: true });
              const filename = `call-${call.id}-${crypto.randomBytes(4).toString('hex')}.mp3`;
              fs.writeFileSync(path.join(recDir, filename), buffer);
              localPath = slug ? `/uploads/${slug}/recordings/${filename}` : `/uploads/recordings/${filename}`;
            }
          }
        }
      } catch (err) {
        logger.warn('voice recording download failed or rejected', {
          downloadUrl,
          reason: err instanceof Error ? err.message : String(err),
        });
      }
    }

    await adb.run(`
      UPDATE call_logs SET recording_url = ?, recording_local_path = ?, updated_at = datetime('now')
      WHERE id = ?
    `, recordingUrl || null, localPath, call.id);

    // Request transcription if enabled
    const voiceCfg = getVoiceConfig(db);
    if ((voiceCfg.voice_auto_transcribe === '1' || voiceCfg.voice_auto_transcribe === 'true') && recordingId && provider.requestTranscription) {
      await adb.run("UPDATE call_logs SET transcription_status = 'pending' WHERE id = ?", call.id);
      const lanIp = getLanIp();
      const protocol = config.nodeEnv === 'production' ? 'https' : (req.protocol || 'https');
      const callbackUrl = `${protocol}://${lanIp}:${config.port}/api/v1/voice/transcription-webhook`;
      await provider.requestTranscription(recordingId, callbackUrl);
    }

    broadcast('voice:recording_ready', { callId: call.id, localPath }, req.tenantSlug || null);
    res.status(200).json({ success: true });
  } catch (err: any) {
    logger.error('voice recording webhook pipeline crashed', { error: err instanceof Error ? err.message : String(err) });
    res.status(200).json({ success: false });
  }
}

/** Transcription webhook — store transcription text */
export async function voiceTranscriptionWebhookHandler(req: Request, res: Response): Promise<void> {
  try {
    const db = req.db;
    const adb = req.asyncDb;
    const provider = getProviderForDb(db, (req as any).tenantSlug);
    if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) {
      logger.warn('voice transcription webhook signature verification failed', { ip: req.ip, provider: provider.name ?? 'unknown' });
      res.status(403).json({ success: false, message: 'Invalid signature' });
      return;
    }
    // Twilio: TranscriptionText, TranscriptionSid, RecordingSid
    // Telnyx: data.payload.transcription_text, data.payload.call_control_id
    const transcription = req.body?.TranscriptionText || req.body?.data?.payload?.transcription_text || req.body?.transcription;
    const recordingSid = req.body?.RecordingSid || req.body?.data?.payload?.recording_id;
    const callSid = req.body?.CallSid || req.body?.data?.payload?.call_control_id;

    const providerCallId = callSid;
    if (!providerCallId && !recordingSid) {
      res.status(200).json({ success: true });
      return;
    }

    let call: AnyRow | undefined;
    if (providerCallId) {
      call = await adb.get<AnyRow>('SELECT id FROM call_logs WHERE provider_call_id = ?', providerCallId);
    }
    if (!call && recordingSid) {
      // recordingSid comes from the webhook payload (provider-controlled, but
      // still not trusted for LIKE wildcards). escapeLike() + ESCAPE '\'
      // stop the `%`/`_` characters from widening the match.
      call = await adb.get<AnyRow>(
        "SELECT id FROM call_logs WHERE recording_url LIKE ? ESCAPE '\\'",
        `%${escapeLike(String(recordingSid))}%`,
      );
    }

    if (call && transcription) {
      await adb.run(`
        UPDATE call_logs SET transcription = ?, transcription_status = 'completed', updated_at = datetime('now')
        WHERE id = ?
      `, transcription, call.id);
      broadcast('voice:transcription_ready', { callId: call.id }, req.tenantSlug || null);
    }

    res.status(200).json({ success: true });
  } catch (err: any) {
    logger.error('voice transcription webhook pipeline crashed', { error: err instanceof Error ? err.message : String(err) });
    res.status(200).json({ success: false });
  }
}

/** Call instructions endpoint — returns TwiML/TeXML/BXML/NCCO for provider */
export async function voiceInstructionsHandler(req: Request, res: Response): Promise<void> {
  const db = req.db;
  const adb = req.asyncDb;
  const action = (req.params.action as string) || 'connect';
  const to = (req.query.to as string) || '';
  const provider = getSmsProvider();
  const voiceCfg = getVoiceConfig(db);

  const storePhone = (await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'store_phone'"))?.value || '';
  const announceRecording = voiceCfg.voice_announce_recording === '1' || voiceCfg.voice_announce_recording === 'true';

  if (!provider.generateCallInstructions) {
    // Generic TwiML fallback
    res.type('text/xml').send(`<?xml version="1.0" encoding="UTF-8"?>
<Response><Dial>${escapeXml(to)}</Dial></Response>`);
    return;
  }

  const instructions = provider.generateCallInstructions(action, { to, from: storePhone, announceRecording });

  // Detect format: JSON (NCCO/Telnyx) or XML (TwiML/BXML/Plivo)
  if (instructions.startsWith('[') || instructions.startsWith('{')) {
    res.type('application/json').send(instructions);
  } else {
    res.type('text/xml').send(instructions);
  }
}

/** Inbound call webhook — forward to configured number */
export async function voiceInboundWebhookHandler(req: Request, res: Response): Promise<void> {
  const db = req.db;
  const adb = req.asyncDb;
  const provider = getProviderForDb(db, (req as any).tenantSlug);

  // Verify webhook signature
  if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) {
    logger.warn('voice inbound webhook signature verification failed', { ip: req.ip, provider: provider.name ?? 'unknown' });
    res.status(403).json({ success: false, message: 'Invalid signature' });
    return;
  }

  const voiceCfg = getVoiceConfig(db);
  const forwardNumber = voiceCfg.voice_forward_number || '';

  if (!forwardNumber) {
    // No forwarding configured — just acknowledge
    if (provider.generateCallInstructions) {
      const instructions = provider.generateCallInstructions('hangup', {});
      res.type(instructions.startsWith('[') || instructions.startsWith('{') ? 'application/json' : 'text/xml').send(instructions);
    } else {
      res.type('text/xml').send('<?xml version="1.0" encoding="UTF-8"?><Response><Say>Sorry, we are unable to take your call right now.</Say></Response>');
    }
    return;
  }

  // Log inbound call
  const event = provider.parseCallWebhook ? provider.parseCallWebhook(req) : null;
  if (event) {
    const convPhone = (event.from || '').replace(/\D/g, '').replace(/^1/, '');
    await adb.run(`
      INSERT INTO call_logs (direction, from_number, to_number, conv_phone, provider, provider_call_id, status)
      VALUES ('inbound', ?, ?, ?, ?, ?, 'ringing')
    `, event.from || '', event.to || '', convPhone, provider.name, event.providerCallId);
    broadcast('voice:inbound_call', { from: event.from, callId: event.providerCallId }, req.tenantSlug || null);
  }

  // Forward to configured number
  if (provider.generateCallInstructions) {
    const storePhone = (await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'store_phone'"))?.value || '';
    const announceRecording = voiceCfg.voice_announce_recording === '1';
    const instructions = provider.generateCallInstructions('connect', {
      to: forwardNumber,
      from: storePhone,
      announceRecording,
    });
    res.type(instructions.startsWith('[') || instructions.startsWith('{') ? 'application/json' : 'text/xml').send(instructions);
  } else {
    res.type('text/xml').send(`<?xml version="1.0" encoding="UTF-8"?><Response><Dial>${escapeXml(forwardNumber)}</Dial></Response>`);
  }
}

// --- Helper ---
function getLanIp(): string {
  const os = require('os');
  const ifaces = os.networkInterfaces();
  for (const addrs of Object.values(ifaces)) {
    for (const addr of (addrs as any[] || [])) {
      if (addr.family === 'IPv4' && !addr.internal) return addr.address;
    }
  }
  return 'localhost';
}
