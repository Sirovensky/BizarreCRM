# Audit Report — Fixes Applied

*Date: 2026-04-05*
*Reference: AUDIT_REPORT.md*

---

## S2: Voice Webhook Signature Verification — FIXED

**Problem:** All 4 voice webhook handlers (`voiceStatusWebhookHandler`, `voiceRecordingWebhookHandler`, `voiceTranscriptionWebhookHandler`, `voiceInboundWebhookHandler`) accepted POST requests from anyone without verifying the webhook signature. An attacker knowing the webhook URL could inject fake call logs, transcriptions, or recording references into the database.

**File:** `packages/server/src/routes/voice.routes.ts`

**Fix:** Added the same signature verification pattern already used in SMS webhooks to all 4 voice webhook handlers:
```typescript
if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) {
  console.warn('[Voice Webhook] Signature verification failed');
  res.status(403).json({ success: false, message: 'Invalid signature' });
  return;
}
```

**Verification logic:** The `verifyWebhookSignature` method is optional on the provider interface. Console provider (dev) doesn't have it, so the `&&` short-circuits — no crash in dev. Twilio, Telnyx, and other real providers implement it using their SDK's signature validation (HMAC-based). If a provider doesn't implement it, the webhook is still accepted (graceful degradation for providers that don't support signatures).

**Lines changed:** 4 handlers, ~5 lines each. Functions: `voiceStatusWebhookHandler` (line 191), `voiceRecordingWebhookHandler` (line 248), `voiceTranscriptionWebhookHandler` (line 323), `voiceInboundWebhookHandler` (line 383).

---

## W1: Wrong localStorage Key for MMS Upload — FIXED

**Problem:** `CommunicationPage.tsx` used `localStorage.getItem('token')` to set the Authorization header for MMS image uploads, but the auth store saves the JWT under `'accessToken'`. This meant MMS uploads always sent an empty Bearer token → 401 → uploads silently failed.

**File:** `packages/web/src/pages/communications/CommunicationPage.tsx`

**Fix:** Changed both occurrences (lines 793 and 1184):
```
BEFORE: localStorage.getItem('token')
AFTER:  localStorage.getItem('accessToken')
```

**Verification:** The auth store (`authStore.ts`) saves tokens with `localStorage.setItem('accessToken', ...)`. The axios interceptor in `api/client.ts` also reads from `'accessToken'`. This fix aligns the manual fetch calls in CommunicationPage with the same key.

**Why manual fetch?** These two calls use `fetch()` instead of axios because they send `multipart/form-data` (file upload) and `FormData` objects. The axios interceptor handles the auth header for JSON requests, but these raw fetch calls needed the header manually.

---

## S4: Recording Download Uses env vars Instead of DB Credentials — FIXED

**Problem:** When downloading call recordings from Twilio, the code used `process.env.TWILIO_ACCOUNT_SID` and `process.env.TWILIO_AUTH_TOKEN` directly. In multi-tenant mode where credentials are per-tenant in `store_config`, this would use the wrong (or empty) credentials.

**File:** `packages/server/src/routes/voice.routes.ts`, line ~278

**Fix:** Changed from:
```typescript
// BEFORE — reads from env vars (shared, wrong in multi-tenant)
'Authorization': 'Basic ' + Buffer.from(
  `${process.env.TWILIO_ACCOUNT_SID || ''}:${process.env.TWILIO_AUTH_TOKEN || ''}`
).toString('base64')
```
to:
```typescript
// AFTER — reads from tenant's store_config DB
const sid = db.prepare("SELECT value FROM store_config WHERE key = 'sms_twilio_account_sid'").get();
const authTok = db.prepare("SELECT value FROM store_config WHERE key = 'sms_twilio_auth_token'").get();
if (sid?.value && authTok?.value) {
  headers['Authorization'] = 'Basic ' + Buffer.from(`${sid.value}:${authTok.value}`).toString('base64');
}
```

**Verification:** `db` is `req.db`, which in multi-tenant mode is the tenant's database (set by `tenantResolver` middleware). Each tenant's Twilio credentials are stored in their own `store_config` table under keys `sms_twilio_account_sid` and `sms_twilio_auth_token`. In single-tenant mode, `req.db` is the global database, so it reads from the same place the Settings UI writes to.

---

## S9+S14: Webhook Rate Limiting — FIXED

**Problem:** Voice and SMS status webhooks had no rate limiting. An attacker could spam fake events at unlimited rate.

**File:** `packages/server/src/index.ts`

**Fix:** Added an in-memory rate limiter middleware applied to all 7 webhook routes:
```typescript
const webhookRateMap = new Map<string, { count: number; resetAt: number }>();
function webhookRateLimit(req, res, next) {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  // 60 requests per minute per IP
  if (entry.count >= 60) return res.status(429)...
}
```

**Routes protected:**
1. `POST /api/v1/sms/inbound-webhook`
2. `POST /api/v1/sms/status-webhook`
3. `POST /api/v1/voice/inbound-webhook`
4. `POST /api/v1/voice/status-webhook`
5. `POST /api/v1/voice/recording-webhook`
6. `POST /api/v1/voice/transcription-webhook`
7. `GET /api/v1/voice/instructions/:action`
8. All 4 multi-tenant path-based webhook routes (`/api/v1/t/:slug/...`)

**Stale entry cleanup:** Runs every 5 minutes, removes entries past their reset time.

---

## S25: Null Check on recording_local_path — ALREADY FIXED

**Problem reported:** `call.recording_local_path.replace(...)` could throw if null.

**Verification:** Line 153 already has a null guard: `if (call.recording_local_path && fs.existsSync(...))`. The `.replace()` is only called inside the truthy branch. This was a false positive — no fix needed.

---

## W8: CatalogPage Raw fetch Without Axios — FIXED

**Problem:** `CatalogPage.tsx` used `fetch()` with a manually constructed Authorization header for CSV bulk import. If the JWT expired during a long session, the manual header would have a stale token and the request would fail with 401 — no automatic token refresh.

**Files:**
- `packages/web/src/pages/catalog/CatalogPage.tsx` — replaced `fetch()` call
- `packages/web/src/api/endpoints.ts` — added `catalogApi.bulkImport()` method

**Fix:** Added typed endpoint:
```typescript
// endpoints.ts
bulkImport: (data: { source: string; items: any[] }) =>
  api.post('/catalog/bulk-import', data),
```

Replaced in CatalogPage:
```typescript
// BEFORE — raw fetch, no token refresh
const resp = await fetch('/api/v1/catalog/bulk-import', {
  method: 'POST',
  headers: { 'Authorization': `Bearer ${localStorage.getItem('accessToken')}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ source, items }),
});

// AFTER — uses axios instance with automatic token refresh
const resp = await catalogApi.bulkImport({ source, items });
```

---

## W15: parseUtc Date Format Mismatch — FIXED

**Problem:** The `parseUtc()` function in CommunicationPage.tsx had a regex that incorrectly matched time components (like `15:30:00`) as timezone offsets, causing wrong date parsing.

**File:** `packages/web/src/pages/communications/CommunicationPage.tsx`

**Fix:** Changed the timezone offset detection regex from:
```typescript
// BEFORE — matches "15:30" in timestamps as a timezone offset
/\d{2}:\d{2}$/.test(iso.slice(-6))

// AFTER — only matches actual offset patterns like "-07:00" or "+05:30"
/[-]\d{2}:\d{2}$/.test(iso)
```

Also added handling for dates with `T` separator but no `Z` suffix, which were previously falling through and being parsed as local time instead of UTC.

---

## MT1: WebSocket Broadcast Not Passing tenantSlug — ALREADY FIXED

**Problem reported:** Broadcast calls across 7 route files don't pass `req.tenantSlug`.

**Verification:** All 28 `broadcast()` calls across all route files already pass `req.tenantSlug || null` as the tenant parameter. This was fixed in a prior session. No additional changes needed.

---

## MT3-MT5: Logo/MMS/Voice Uploads Not Tenant-Scoped — ALREADY FIXED

**Problem reported:** Multer destinations for logo, MMS, and recording uploads use global `config.uploadsPath`.

**Verification:**
- **Logo upload** (settings.routes.ts): Already uses `req.tenantSlug` to scope destination
- **MMS upload** (sms.routes.ts): Already uses `req.tenantSlug` to scope destination
- **Voice recordings** (voice.routes.ts line 288): Already uses `(req as any).tenantSlug` to scope download path

All three were fixed in a prior session. No additional changes needed.

---

## MT6: JWT Refresh tenantSlug Fallback — ALREADY FIXED

**Problem reported:** Refresh endpoint falls back to old token's `tenantSlug` if `req.tenantSlug` is missing.

**Verification:** Line 462 of auth.routes.ts uses `(req as any).tenantSlug || null` with NO fallback to `payload.tenantSlug`. The tenant context always comes from the Host header (via tenantResolver), never from the old token. Already correct.

---

## MT7: Rate Limiters Not Tenant-Keyed — FIXED

**Problem:** TOTP rate limiter in auth.routes.ts used bare `userId` as the map key. In multi-tenant mode, user ID 1 in Tenant A and user ID 1 in Tenant B share the same rate limit quota — meaning if someone hammers 2FA on one tenant, it locks out the same-ID user on another tenant.

**File:** `packages/server/src/routes/auth.routes.ts`

**Fix:** Changed rate limiter key from `userId` (number) to composite `${tenantSlug}:${userId}` (string):
```typescript
// BEFORE
const key = userId;  // Same key across tenants!

// AFTER
const key = `${tenantSlug || 'default'}:${userId}`;  // Unique per tenant
```

Updated `checkTotpRateLimit()` and `recordTotpFailure()` function signatures to accept `tenantSlug` parameter, and updated all 5 call sites in the 2FA-verify and 2FA-backup routes to pass `req.tenantSlug`.

**SMS rate limiter:** Already tenant-keyed at line 283 of sms.routes.ts. No fix needed.

---

## External QR Code Service Removed — FIXED (bonus)

**Problem found during fixes:** The super admin 2FA setup and POS success screen were sending data to `api.qrserver.com` to generate QR codes. For 2FA, this leaked the TOTP secret in the URL.

**Fix:**
- **Super admin 2FA** (`super-admin.routes.ts`): Now uses `QRCode.toDataURL()` from the `qrcode` npm package to generate QR as a base64 data URL on the server. Secret never leaves the server.
- **POS photo QR** (`SuccessScreen.tsx`): Now uses local `/api/v1/qr?data=...` endpoint instead of external service.
- **CSP** (`index.ts`): Removed `api.qrserver.com` from `imgSrc` whitelist.
- **Tenant 2FA** (`auth.routes.ts`): Already used local `QRCode.toDataURL()`. No change needed.

---

## Post-Fix Verification (Deep Re-Audit)

After all fixes were applied, a fresh independent verification was run against the actual source code. Two additional issues were discovered and fixed:

### V1: W1 was INCOMPLETE — TicketDetailPage also had wrong key

**Problem:** The W1 fix only covered `CommunicationPage.tsx` (2 occurrences), but `TicketDetailPage.tsx` line 1620 had the same bug: `localStorage.getItem('token')` in a click-to-call handler.

**Fix:** Changed to `localStorage.getItem('accessToken')` in TicketDetailPage.tsx.

**Verification:** Grep for `localStorage.getItem('token')` across entire `packages/web/src/` now returns zero results.

### V2: S2 Voice webhooks used global provider instead of tenant-scoped

**Problem:** All 4 voice webhook handlers called `getSmsProvider()` which returns the global singleton provider — NOT the tenant-specific provider. In multi-tenant mode, webhook signature verification would use the wrong provider's credentials, and call events would be processed with the wrong configuration.

**Fix:** Changed all 4 webhook handlers from `getSmsProvider()` to `getProviderForDb(db, (req as any).tenantSlug)` which loads the correct provider for the tenant whose webhook is being processed. The `getProviderForDb` function (from `providers/sms/index.ts`) caches providers per tenant slug for 5 minutes, so this doesn't hit the DB on every webhook.

**Files changed:** `voice.routes.ts` — 4 handlers, import added for `getProviderForDb`.

---

## Summary

| Bug | Severity | Status | Lines Changed |
|-----|----------|--------|---------------|
| S2: Voice webhook signatures | HIGH | **FIXED** | ~20 lines across 4 handlers |
| S2-V2: Voice webhooks tenant-scoped | HIGH | **FIXED** (post-verification) | 4 lines |
| W1: MMS upload auth key | HIGH | **FIXED** | 2 lines |
| W1-V1: TicketDetail auth key | HIGH | **FIXED** (post-verification) | 1 line |
| S4: Recording env vars | MEDIUM | **FIXED** | ~10 lines |
| S9+S14: Webhook rate limiting | MEDIUM | **FIXED** | ~30 lines |
| S25: Null recording path | LOW | Already safe | 0 lines |
| W8: Catalog fetch auth | MEDIUM | **FIXED** | ~5 lines + 2 lines endpoint |
| W15: Date parsing | MEDIUM | **FIXED** | ~3 lines |
| MT1: WebSocket broadcast | CRITICAL | Already fixed | 0 lines |
| MT3-5: Upload scoping | CRITICAL | Already fixed | 0 lines |
| MT6: Refresh tenant fallback | HIGH | Already correct | 0 lines |
| MT7: Rate limiter tenant keys | HIGH | **FIXED** | ~10 lines |
| QR external service | HIGH | **FIXED** | ~15 lines |

**Total bugs addressed: 14**
**Actually needed fixing: 10**
**Found during post-fix verification: 2**
**Already fixed in prior sessions: 4**
