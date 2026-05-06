# T16 — Voice / IVR / TwiML / Webhook Security

**Scope:** `packages/server/src/routes/voice.routes.ts`, `packages/server/src/providers/sms/twilio.ts`, `packages/server/src/providers/sms/telnyx.ts`, `packages/server/src/providers/sms/plivo.ts`, `packages/server/src/providers/sms/bandwidth.ts`, `packages/server/src/providers/sms/vonage.ts`, `packages/server/src/providers/sms/console.ts`, `packages/server/src/services/smsProvider.ts` (index), `packages/server/src/index.ts` (mounting), `packages/server/src/db/migrations/043_sms_mms_voice.sql`

> **Note:** Two findings already documented in S35 are intentionally excluded here to avoid duplication:
> - HIGH — `voiceInstructionsHandler` has no webhook signature verification (S35, line 7)
> - MEDIUM — `voiceInstructionsHandler` accepts arbitrary `?to=` phone number (S35, line 88)

---

### HIGH — IDOR: entity_type+entity_id bypass exposes all calls, recordings, and transcriptions to any authenticated user

**Where:** `packages/server/src/routes/voice.routes.ts:183–214`

**What:**
`GET /api/v1/voice/calls` applies the non-admin restriction (`cl.user_id = ? OR cl.direction = 'inbound'`) only when `entityType && entityId` are both absent. When a caller supplies any `entity_type` + `entity_id` query parameter pair, the restriction is dropped entirely — no check verifies whether the requesting user has access to that entity. Any authenticated user (technician, receptionist) can enumerate call logs, recording URLs, and transcriptions for any entity by cycling through `entity_id` values.

**Code:**
```typescript
// voice.routes.ts:183–201
const entityType = req.query.entity_type as string | undefined;
const entityId = req.query.entity_id as string | undefined;

if (convPhone) { where += ' AND cl.conv_phone = ?'; params.push(convPhone); }
if (entityType && entityId) {
  where += ' AND cl.entity_type = ? AND cl.entity_id = ?';
  params.push(entityType, parseInt(entityId, 10));
}

const isAdmin = req.user!.role === 'admin' || req.user!.role === 'manager';
if (!isAdmin && !(entityType && entityId)) {   // <— bypass: condition is FALSE when entity provided
  where += ' AND (cl.user_id = ? OR cl.direction = ?)';
  params.push(req.user!.id, 'inbound');
}
```

**Exploit:**
A technician-role user sends `GET /api/v1/voice/calls?entity_type=ticket&entity_id=1` to retrieve all call logs for ticket 1, including `from_number`, `to_number`, `recording_url`, `recording_local_path`, and `transcription` of calls made by other employees. Cycling `entity_id` from 1 upward dumps the full call history with no per-record authz check.

**Fix:**
Before removing the user-scope restriction, verify the requesting user has read access to the specified entity (e.g., confirm the ticket/customer belongs to their tenant and they have at minimum `viewer` access). Alternatively, keep the restrictive filter and add an OR clause: `AND (cl.entity_type = ? AND cl.entity_id = ? AND <entity_read_check>)`.

---

### MEDIUM — Any authenticated non-admin user can read ALL inbound call logs and recordings

**Where:** `packages/server/src/routes/voice.routes.ts:197–201` (list), `voice.routes.ts:239`, `voice.routes.ts:332`, `voice.routes.ts:364`

**What:**
Without an entity scope, the non-admin WHERE clause adds `OR cl.direction = 'inbound'`, which reveals every inbound call—regardless of which user the call is associated with—to any authenticated user. The same condition appears on single-call detail (`GET /calls/:id`), recording URL issuance (`GET /calls/:id/recording-url`), and the streaming endpoint (`GET /calls/:id/recording`). Inbound calls contain customer phone numbers, transcriptions (which may include CC numbers spoken aloud, PII, complaints), and recording audio.

**Code:**
```typescript
// voice.routes.ts:197–200
const isAdmin = req.user!.role === 'admin' || req.user!.role === 'manager';
if (!isAdmin && !(entityType && entityId)) {
  where += ' AND (cl.user_id = ? OR cl.direction = ?)';
  params.push(req.user!.id, 'inbound');  // exposes ALL inbound calls
}
// Single call detail:
if (!isAdmin && call.user_id !== req.user!.id && call.direction !== 'inbound') {
  throw new AppError('Not authorized', 403); // inbound calls always pass
}
```

**Exploit:**
A new technician with no calls of their own sends `GET /api/v1/voice/calls` and receives the entire inbound call history for the shop, including transcriptions and recording URLs for every customer call. They can then fetch any recording via `GET /calls/:id/recording-url` (which issues a signed URL without a further user-scope check for inbound calls).

**Fix:**
Inbound calls that have no `user_id` association should be viewable only by admin/manager. Non-admin users should see only inbound calls associated with their `user_id` (e.g., calls they answered or that reference an entity they can access). Replace the OR with: `AND (cl.user_id = ? OR (cl.direction = 'inbound' AND cl.user_id IS NULL))` or add a proper entity-based access check.

---

### MEDIUM — POST /call accepts any phone number — any authenticated user can initiate toll-fraud calls

**Where:** `packages/server/src/routes/voice.routes.ts:76–167`

**What:**
`POST /api/v1/voice/call` checks only that `to` is non-empty (line 83) and then passes it directly to `provider.initiateCall()`. There is no E.164 format validation, no geo-block, and no restriction on premium-rate number ranges (`+1900…`, `+44XXX…`, etc.). Because this route is protected by auth (any role) and limited to 10 calls/min per user — not per IP or globally — each of the shop's technicians can individually initiate calls to billing traps at the provider's per-minute rate, charged to the tenant's account.

**Code:**
```typescript
// voice.routes.ts:79–90
const { to, mode, entity_type, entity_id } = req.body as {
  to?: string; mode?: 'bridge' | 'push'; entity_type?: string; entity_id?: number;
};
if (!to) throw new AppError('Recipient phone number is required', 400);
// SCAN-719: rate limit — 10/min per user, not per shop or globally
if (!checkWindowRate(req.db, 'voice_call', String(userId), 10, 60_000)) {
  throw new AppError('Too many call attempts — try again later', 429);
}
recordWindowAttempt(req.db, 'voice_call', String(userId), 60_000);
// `to` passed verbatim to provider.initiateCall(to, storePhone, opts)
```

**Exploit:**
A low-privilege technician (`role=tech`) authenticates, then POSTs `{ "to": "+19001234567" }` — a US pay-per-call premium number — 10 times per minute. With 5 technicians on staff, the shop is billed for 50 premium calls/minute until the provider cuts off the account. Because `to_number` is logged in `call_logs` without PII scrubbing in the rate-limit key, different users with the same `to` number are not jointly rate-limited.

**Fix:**
Validate `to` against an E.164 regex at minimum (`/^\+[1-9]\d{7,14}$/`). Consider an admin-configurable geo-allow/block list. Add a per-shop global rate limit (not per-user) to cap total outbound call spend. Flag premium-rate prefixes (`+1900`, `+1976`, `+44909`, etc.) as blocked by default.

---

### MEDIUM — TOCTOU race in POST /call rate limiter allows burst past the 10/min cap

**Where:** `packages/server/src/routes/voice.routes.ts:87–90`

**What:**
The rate check uses the deprecated two-step pattern `checkWindowRate(…)` + `recordWindowAttempt(…)` instead of the atomic `consumeWindowRate(…)`. Both functions are separate SQLite statements and are not wrapped in a transaction. Two concurrent `POST /call` requests from the same user can both see `count = 9`, both pass `checkWindowRate`, and both record, submitting 2 provider calls instead of 1. SCAN-1065 (documented in `rateLimiter.ts` line 53) flagged this exact pattern for migration; `voice_call` was not on the priority list in S28's audit.

**Code:**
```typescript
// voice.routes.ts:87–90
if (!checkWindowRate(req.db, 'voice_call', String(userId), 10, 60_000)) {
  throw new AppError('Too many call attempts — try again later', 429);
}
recordWindowAttempt(req.db, 'voice_call', String(userId), 60_000);
// Two concurrent requests both pass checkWindowRate before either records
```

**Exploit:**
An attacker opens two browser tabs and fires `POST /call` simultaneously from both. Both see count=9, both pass, both initiate provider calls, resulting in 11+ calls in the window instead of 10. Under automation (JS `Promise.all`), a user can place significantly more than 10 calls per minute against the provider.

**Fix:**
Replace with `consumeWindowRate(req.db, 'voice_call', String(userId), 10, 60_000)` (single atomic check-and-record transaction). This matches the pattern used by `webhookRateLimit` and the global API limiter.

---

### MEDIUM — voiceStatusWebhookHandler stores unvalidated recordingUrl directly into call_logs

**Where:** `packages/server/src/routes/voice.routes.ts:476–477`

**What:**
`voiceStatusWebhookHandler` parses `event.recordingUrl` from the webhook payload and writes it to `call_logs.recording_url` without passing it through `validateRecordingUrl()`. The recording webhook handler (`voiceRecordingWebhookHandler`) correctly calls `validateRecordingUrl(downloadUrl)` before downloading, but the status webhook bypasses this check and persists the raw URL. If an attacker forges a status webhook (possible when webhook signature verification is not implemented or misconfigured), they can inject an arbitrary URL — including non-provider domains or data URIs — into the `recording_url` column. This URL is returned in `cl.*` API responses and exposed in the UI as the recording URL.

**Code:**
```typescript
// voice.routes.ts:472–480
const updates: string[] = ['status = ?', "updated_at = datetime('now')"];
const params: any[] = [event.status];

if (event.duration != null) { updates.push('duration_secs = ?'); params.push(event.duration); }
if (event.recordingUrl) { updates.push('recording_url = ?'); params.push(event.recordingUrl); }
// No validateRecordingUrl() call here — raw URL stored directly
params.push(call.id);
await adb.run(`UPDATE call_logs SET ${updates.join(', ')} WHERE id = ?`, ...params);
```

**Exploit:**
An attacker forges a Twilio status webhook (e.g., exploiting the SHA-1 HMAC weakness noted in T08, or by replaying a captured webhook, or using ConsoleProvider in a dev deployment). They include `RecordingUrl: "https://evil.com/phishing-audio.mp3"` in the payload. The URL is stored in `call_logs.recording_url` and returned in `GET /voice/calls/:id` responses. UI components that render it as a clickable link present it to shop staff as a legitimate recording. The actual redirect through `/recording/:id` is blocked by `validateRecordingUrl`, but the raw URL appearing in the API response is sufficient for phishing.

**Fix:**
Call `validateRecordingUrl(event.recordingUrl)` before adding it to the update array. Wrap in a try/catch (same as `voiceRecordingWebhookHandler`) and skip the update if validation fails, logging a warning.

---

### LOW — No length limit on transcription field stored from webhook

**Where:** `packages/server/src/routes/voice.routes.ts:678–683`, `packages/server/src/db/migrations/043_sms_mms_voice.sql:28`

**What:**
`voiceTranscriptionWebhookHandler` stores `req.body.TranscriptionText` (or equivalent) directly into `call_logs.transcription` (a TEXT column with no CHECK constraint or length limit). There is no server-side truncation or size guard. A forged webhook (feasible with ConsoleProvider, a replay attack, or an upstream provider compromise) can store megabytes of text per call, filling disk and degrading SQLite performance for all queries on `call_logs`.

**Code:**
```typescript
// voice.routes.ts:678–683
if (call && transcription) {
  await adb.run(`
    UPDATE call_logs SET transcription = ?, transcription_status = 'completed', ...
    WHERE id = ?
  `, transcription, call.id);
}
// `transcription` is req.body.TranscriptionText — unbounded length
```

**Exploit:**
An attacker targeting a ConsoleProvider-configured dev server (or exploiting Plivo's nonce-only replay protection gap noted in T11) POSTs a fabricated transcription webhook with a 50 MB `TranscriptionText` body. SQLite stores it; the next `SELECT * FROM call_logs` that scans the table transmits 50 MB per row, degrading all call log queries.

**Fix:**
Truncate `transcription` to a reasonable maximum (e.g., 64 KB) before storing: `transcription.slice(0, 65536)`. Add a similar limit check in the `voiceRecordingWebhookHandler` transcription trigger path. Consider adding a CHECK constraint on the column.

---

### LOW — Transcription callback URL uses LAN IP in production — transcriptions never delivered

**Where:** `packages/server/src/routes/voice.routes.ts:627–629`

**What:**
When `voice_auto_transcribe` is enabled and a recording is downloaded, the transcription callback URL sent to the provider is constructed using `getLanIp()` (a private network address) in all environments, not just dev. The POST `/call` endpoint correctly uses `req.get('host')` in production but the recording webhook handler does not. The result: Twilio (or other providers) cannot reach the transcription webhook URL from the internet, so `transcription_status` stays `'pending'` forever and transcriptions are silently dropped.

**Code:**
```typescript
// voice.routes.ts:627–630
const lanIp = getLanIp();
const protocol = config.nodeEnv === 'production' ? 'https' : (req.protocol || 'https');
const callbackUrl = `${protocol}://${lanIp}:${config.port}/api/v1/voice/transcription-webhook`;
await provider.requestTranscription(recordingId, callbackUrl);
// Contrast with POST /call (line 130–132):
// const callbackBaseUrl = config.nodeEnv === 'production'
//   ? `https://${req.get('host')}`       ← correct
//   : `https://${lanIp}:${config.port}`;
```

**Exploit:**
Not a security exploit, but the inconsistency can be intentionally abused: a tenant enables `voice_auto_transcribe` expecting a security audit trail (compliance requirement), which silently produces no transcriptions. The functional gap also means `transcription_status = 'pending'` rows accumulate indefinitely with no cleanup path.

**Fix:**
Use the same `callbackBaseUrl` pattern as `initiateCall`: in production use `https://${req.get('host')}`, in dev use `https://${lanIp}:${config.port}`. Pass `callbackBaseUrl` or derive it in `voiceRecordingWebhookHandler` from the incoming request the same way the POST /call handler does.

---

### INFO — Multi-tenant path-based routing missing recording and transcription webhook routes

**Where:** `packages/server/src/index.ts:1590–1591`

**What:**
In multi-tenant mode, the path-based webhook routes (`/api/v1/t/:slug/…`) include `inbound-webhook` and `status-webhook` but not `recording-webhook` or `transcription-webhook`. If a provider is configured to use path-based tenant routing (instead of subdomain-based routing), recording downloads and transcriptions will be silently dropped for those tenants.

**Code:**
```typescript
// index.ts:1590–1591 — only two of four voice webhook routes mounted for t/:slug
app.post('/api/v1/t/:slug/voice/inbound-webhook', webhookRateLimit, webhookTenantResolver, voiceInboundWebhookHandler);
app.post('/api/v1/t/:slug/voice/status-webhook', webhookRateLimit, webhookTenantResolver, voiceStatusWebhookHandler);
// Missing:
// app.post('/api/v1/t/:slug/voice/recording-webhook', ...)
// app.post('/api/v1/t/:slug/voice/transcription-webhook', ...)
```

**Exploit:**
Functional gap, not a direct security exploit. However, missing recordings means compliance/audit requirements fail silently without any error surfaced to the tenant.

**Fix:**
Add `recording-webhook` and `transcription-webhook` to the multi-tenant slug routing block, mirroring the pattern for the existing two routes.

---
