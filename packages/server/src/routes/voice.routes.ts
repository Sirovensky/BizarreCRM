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
import { reserveStorage } from '../services/usageTracker.js';
import { getMasterDb } from '../db/master-connection.js';
import { getPlanDefinition, type TenantPlan } from '@bizarre-crm/shared';
import type { AsyncDb } from '../db/async-db.js';

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

  // Determine callback base URL
  const lanIp = getLanIp();
  const callbackBaseUrl = config.nodeEnv === 'production'
    ? `https://${req.get('host')}`
    : `http://${lanIp}:${config.port}`;

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
router.get('/calls', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
  const pageSize = Math.min(100, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));
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
router.get('/calls/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const call = await adb.get<AnyRow>(`
    SELECT cl.*, u.first_name || ' ' || u.last_name AS user_name
    FROM call_logs cl
    LEFT JOIN users u ON u.id = cl.user_id
    WHERE cl.id = ?
  `, req.params.id);

  if (!call) throw new AppError('Call not found', 404);
  res.json({ success: true, data: call });
}));

// ---------------------------------------------------------------------------
// GET /voice/calls/:id/recording — Stream recording audio (auth required)
// ---------------------------------------------------------------------------
router.get('/calls/:id/recording', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const call = await adb.get<AnyRow>('SELECT recording_local_path, recording_url FROM call_logs WHERE id = ?', req.params.id);
  if (!call) throw new AppError('Call not found', 404);

  if (call.recording_local_path && fs.existsSync(path.join(config.uploadsPath, call.recording_local_path.replace(/^\/uploads\//, '')))) {
    const filePath = path.join(config.uploadsPath, call.recording_local_path.replace(/^\/uploads\//, ''));
    res.setHeader('Content-Type', 'audio/mpeg');
    fs.createReadStream(filePath).pipe(res);
    return;
  }

  if (call.recording_url) {
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
// TODO(voice-hangup): Implement per-provider hangup by reading the provider
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
      console.warn('[Voice Webhook] Signature verification failed');
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
    console.error('[Voice Status Webhook] Error:', err.message);
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
      console.warn('[Voice Webhook] Recording signature verification failed');
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
        const resp = await fetch(downloadUrl, { headers, signal: controller.signal });
        clearTimeout(timeout);
        if (resp.ok) {
          const contentLength = parseInt(resp.headers.get('content-length') || '0', 10);
          if (contentLength > MAX_RECORDING_SIZE) {
            console.warn('[Voice] Recording too large (content-length), skipping:', downloadUrl, contentLength);
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
                  console.warn('[Voice] Recording exceeded 50MB during download, skipping:', downloadUrl);
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
                      console.warn(`[Voice] Tenant ${slug} storage limit reached — dropping recording (${buffer.length} bytes)`);
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
        console.warn('[Voice] Failed to download recording:', (err as Error).message);
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
    console.error('[Voice Recording Webhook] Error:', err.message);
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
      console.warn('[Voice Webhook] Transcription signature verification failed');
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
      call = await adb.get<AnyRow>("SELECT id FROM call_logs WHERE recording_url LIKE ?", `%${recordingSid}%`);
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
    console.error('[Voice Transcription Webhook] Error:', err.message);
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
    console.warn('[Voice Webhook] Inbound signature verification failed');
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
