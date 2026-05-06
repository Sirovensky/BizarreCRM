# S06 — JWT Secret Management, Signing & Verification

**Scope:** `packages/server/src/utils/jwtSecrets.ts`, `config.ts`, all `jwt.sign` / `jwt.verify` / `jwt.decode` call sites.

**Auditor:** Claude (read-only)  
**Date:** 2026-05-05

---

## Findings

### F-S06-01 — MEDIUM — Weak fallback dev-secret in .env.example is an active value (not commented)

**File:** `/Users/serega/BizarreCRM/.env.example` line 22  
**Code:**
```
JWT_SECRET=change-me-to-a-random-string
```
`.env.example` is committed to git (`git ls-files` confirms). The `JWT_SECRET` entry is a live `KEY=VALUE` assignment, not commented out. Any developer who `cp .env.example .env` and starts the server immediately runs with `JWT_SECRET=change-me-to-a-random-string`. The production guard in `config.ts` blocks this in `NODE_ENV=production`, but the dev fallback still produces HKDF-derived secrets whose root material is fully public. A team-wide "dev" deployment (e.g. staging with `NODE_ENV=development`) would have no protection.

**All other env secrets in `.env.example` (`SUPER_ADMIN_SECRET`, `ACCESS_JWT_SECRET`, `REFRESH_JWT_SECRET`) are correctly commented out — only `JWT_SECRET` is left active.**

**Recommendation:** Comment out `JWT_SECRET` in `.env.example` (e.g. `# JWT_SECRET=<generate: openssl rand -hex 64>`). Provide a generation command so first-time operators know what to do.

---

### F-S06-02 — MEDIUM — `/admin-uploads` handler verifies JWT but skips session revocation check

**File:** `/Users/serega/BizarreCRM/packages/server/src/index.ts` lines ~1403–1430  
**Description:**  
The inline super-admin JWT check on `app.use('/admin-uploads', localhostOnly, ...)` verifies the token signature, algorithm, issuer, and audience, and checks `payload.role === 'super_admin'` — but **does not verify that the session still exists in `super_admin_sessions`**.

All three other super-admin gatekeepers do perform the session check:
- `super-admin.routes.ts` `superAdminAuth()` — queries `super_admin_sessions` and `super_admins`.
- `management.routes.ts` `managementAuth()` — same session + admin-active check.
- `admin.routes.ts` `adminAuth()` — same (conditional on `masterDb` availability — see F-S06-03).

A super-admin token that has been revoked (logout, account disabled) can still access `/admin-uploads` within the 30-minute token TTL (configured in `SUPER_ADMIN_JWT_SIGN_OPTIONS`). The route is behind `localhostOnly` (TCP-layer), which limits exposure to localhost attackers (e.g. compromised local process, developer machine), not remote attackers.

**Severity rationale:** Mitigated by `localhostOnly` and the 30-minute token TTL. Not a remote exploit, but inconsistent with the revocation model applied everywhere else for this privilege tier.

**Recommendation:** Add the same `super_admin_sessions` + `super_admins.is_active` check to the `/admin-uploads` handler, or extract a shared `superAdminAuthInline(token)` helper and reuse it.

---

### F-S06-03 — LOW — `admin.routes.ts` session check is conditional on `masterDb != null`; null DB silently skips revocation

**File:** `/Users/serega/BizarreCRM/packages/server/src/routes/admin.routes.ts` lines 151–170  
**Code:**
```ts
const masterDb = getMasterDb();
if (masterDb && payload.sessionId) {      // skipped if masterDb is null
  // session expiry check
}
if (masterDb && payload.superAdminId) {   // skipped if masterDb is null
  // is_active check
}
return next();                            // always reached if role === 'super_admin'
```
If `getMasterDb()` returns `null` (e.g. during a DB initialisation race at startup, or after a deliberate DB connection failure), both the session-expiry and account-active checks are skipped entirely, and the request is allowed through with only a valid JWT signature.

**Severity rationale:** `getMasterDb()` returning null should be extremely rare in practice. However, the code silently proceeds rather than failing closed. In the worst case a forcibly-null master DB state allows access with any valid (even revoked) super-admin JWT.

**Recommendation:** Fail closed: if `masterDb` is unavailable, return 503 / 401 rather than granting access.
```ts
const masterDb = getMasterDb();
if (!masterDb) {
  return res.status(503).json({ success: false, message: 'Master DB unavailable' });
}
```

---

### F-S06-04 — LOW — TOTP legacy v0 key is `sha256(jwtSecret)` — collocated with JWT signing key material

**File:** `/Users/serega/BizarreCRM/packages/server/src/routes/auth.routes.ts` lines 144–148  
**Code:**
```ts
const key = crypto.createHash('sha256').update(config.jwtSecret).digest();
```
The v0 TOTP decryption path (no version prefix in ciphertext) re-derives the AES-256-GCM key as a raw SHA-256 of `config.jwtSecret`. This means:
1. A JWT secret leak also leaks the TOTP AES key for any user whose `totp_secret` was encrypted with the v0 scheme.
2. The derivation uses no salt, info, or HKDF expand — just `SHA-256(secret)` — which is weak key derivation for a symmetric encryption key.

v0 is legacy-read-only path (all new encryptions use v3 / HKDF). Risk is confined to accounts that haven't re-authenticated since before v1 was introduced. The v3 path (HKDF with salt and info) correctly addresses this.

**Recommendation:** Add a migration: on next TOTP verify success, re-encrypt any v0 ciphertext with v3. Once no v0 rows remain in DB, remove the v0 branch.

---

### F-S06-05 — INFO — All tenant tokens share a single `accessJwtSecret` / `refreshJwtSecret` — cross-tenant replay mitigated by claim assertion, not key isolation

**Files:** `config.ts`, `auth.routes.ts`, `middleware/auth.ts`  
**Description:**  
In multi-tenant mode, all tenants use the same `accessJwtSecret` and `refreshJwtSecret`. A refresh token for `tenant-a` is cryptographically valid on `tenant-b`'s endpoint. The code mitigates this correctly:
- Access tokens embed `tenantSlug` and the middleware asserts `payload.tenantSlug === req.tenantSlug`.
- Refresh tokens assert `payload.tenantSlug` via `crypto.timingSafeEqual` before issuing a new token.

This is a known architectural trade-off (per-tenant keys would require key-per-row in DB or per-tenant key derivation). The existing claim-level enforcement is adequate as long as those checks are always reached. No bypass was found.

**Recommendation:** Document in `jwtSecrets.ts` or the operator guide that cross-tenant isolation relies on claim assertion, not cryptographic key isolation, so future developers don't remove those checks assuming the key provides the isolation.

---

## NOT FOUND (explicitly checked, clean)

| Check | Result |
|---|---|
| `jwt.decode` used without `verify` | Not present anywhere in `packages/server/src/` |
| `alg:none` or algorithm not pinned | All `jwt.verify` calls pass explicit `algorithms: ['HS256']` |
| Issuer / audience not asserted | All tenant + super-admin verify calls assert `issuer` and `audience`. Vonage webhook intentionally omits iss/aud (Vonage's JWT format uses `payload_hash` binding instead) |
| Weak/placeholder secret reaching production | `config.ts` calls `process.exit(1)` in `NODE_ENV=production` if secret is absent or in `INSECURE_SECRETS` list |
| Secret printed in logs | No `console.log(secret/token)` patterns found |
| Secret committed to repo | No `.env` files (non-example) tracked in git; `.env` in `.gitignore` |
| Tenant tokens signed with same key as master/super-admin tokens | `superAdminSecret` is always a distinct env var or SHA-256-derived fallback; separate audience enforces separation |
| Role claim trusted from JWT payload for authorization | `auth.ts` middleware re-reads `role` from the `users` DB table; `payload.role` in the access token is embedded for informational use only. Super-admin verify explicitly re-checks `payload.role === 'super_admin'` after verify as a guard |
| Secret length < 32 bytes in production | Both `jwtSecret` and `superAdminSecret` enforce `length >= 32` or `exit(1)` in production |
| Key rotation strategy missing | `verifyJwtWithRotation()` + `JWT_SECRET_PREVIOUS` / `JWT_REFRESH_SECRET_PREVIOUS` + operator guide procedure present |
| HS256 with kid rotation absent | No asymmetric key / JWKS endpoint expected; HS256 with secret rotation is documented and mitigated |

---

## Summary

| ID | SEV | Title |
|---|---|---|
| F-S06-01 | MEDIUM | `JWT_SECRET` in `.env.example` is an active (uncommented) weak placeholder |
| F-S06-02 | MEDIUM | `/admin-uploads` JWT handler skips session revocation check |
| F-S06-03 | LOW | `admin.routes.ts` `adminAuth` silently skips revocation checks when `masterDb` is null |
| F-S06-04 | LOW | Legacy v0 TOTP key is `sha256(jwtSecret)` — no migration to retire it |
| F-S06-05 | INFO | Cross-tenant isolation is claim-based, not key-based (documented trade-off) |

---

## PASS 2 — DEEP DIVE

### MEDIUM — Photo-upload scoped token cross-tenant replay in multi-tenant mode

**Where:** `packages/server/src/routes/tickets.routes.ts:2440` (sign), `packages/server/src/routes/tickets.routes.ts:2479` (verify)

**What:**
The photo-upload scoped JWT (minted by `POST /:id/devices/:deviceId/photo-upload-token`) embeds `ticket_id` and `ticket_device_id` but **no `tenantSlug` claim**. All tenants share the same `config.accessJwtSecret`, so the token is cryptographically valid on every tenant's subdomain. At photo-upload time (`POST /:id/photos`), the scoped-token path bypasses `authMiddleware` entirely — the only checks are `scoped.ticket_id !== ticketId` and `scoped.ticket_device_id !== bodyDeviceId`, which compare against the **target tenant's DB**. Since every tenant DB uses auto-increment integer IDs starting from 1, ticket IDs and device IDs collide across tenants.

**Code:**
```typescript
// Sign (tickets.routes.ts:2440-2451) — no tenantSlug embedded
const token = jwt.sign(
  { sub: 'photo-upload', ticket_id: ticketId, ticket_device_id: deviceId },
  config.accessJwtSecret,
  { ...JWT_SIGN_OPTIONS, audience: 'photo-upload', expiresIn: '30m' },
);

// Verify (tickets.routes.ts:2479-2483) — no tenantSlug claim checked
scopedPayload = jwt.verify(raw, config.accessJwtSecret, {
  algorithms: ['HS256'],
  issuer: JWT_SIGN_OPTIONS.issuer,
  audience: 'photo-upload',
}) as { sub?: string; ticket_id?: number; ticket_device_id?: number };
```

**Exploit:**
A user at `tenant-a.crm.example.com` with `tickets.edit` permission mints a photo-upload token for ticket 5, device 3 (their tenant). They POST that token to `tenant-b.crm.example.com/api/v1/tickets/5/photos` with `ticket_device_id=3`. If tenant-b has a ticket 5 and device 3 (nearly certain for active tenants with many tickets), the checks pass and arbitrary files are uploaded to tenant-b's ticket — a cross-tenant write via a signed token with no tenant binding.

**Fix:**
Embed `tenantSlug` in the photo-upload token payload at sign time and assert it equals `(req as any).tenantSlug` in the scoped-token branch of the photo-upload middleware, mirroring the check already done for regular access tokens in `authMiddleware`.

---

### LOW — `management.routes.ts` `managementAuth` also silently skips revocation when `masterDb` is null

**Where:** `packages/server/src/routes/management.routes.ts:269–291`

**What:**
`managementAuth()` wraps its session-expiry and account-active checks inside `if (masterDb) { ... }`. If `getMasterDb()` returns `null`, both checks are skipped and any valid (even revoked) super-admin JWT is accepted. This is the same pattern as the already-filed F-S06-03 for `admin.routes.ts`, but Pass 1 did not cite `management.routes.ts`. The route is additionally guarded by `managementApiGuard` (which itself aborts on `!masterDb`), so in practice a null master DB would be caught one layer earlier — but that guard is before `router.use(managementAuth)`, not inside it, so if `masterDb` becomes null after the guard fires, the revocation gap is reachable.

**Code:**
```typescript
const masterDb = getMasterDb();
if (masterDb) {                          // skipped if masterDb is null
  if (payload.sessionId) { /* session expiry check */ }
  if (payload.superAdminId) { /* is_active check */ }
}
next();                                  // always reached if role === 'super_admin'
```

**Exploit:**
Same as F-S06-03: if the master DB connection is transiently null (startup race, connection failure), a super-admin with a revoked JWT (logged out, account disabled) can access `GET /api/v1/management/*` endpoints.

**Fix:**
Fail closed: if `masterDb` is null, return 503 immediately before the JWT verify, the same way `managementApiGuard` does (line 113–116).

---

### LOW — Session ownership not cross-checked in `management.routes.ts` and `admin.routes.ts`

**Where:** `packages/server/src/routes/management.routes.ts:273–275`, `packages/server/src/routes/admin.routes.ts:152–154`

**What:**
Both `managementAuth` (management.routes.ts) and `adminAuth` (admin.routes.ts) verify that a session row with `payload.sessionId` exists but do **not** assert `super_admin_id = payload.superAdminId`. By contrast, `superAdminAuth` in `super-admin.routes.ts:256` correctly includes `AND super_admin_id = ?`. If an attacker held a validly-signed JWT with admin-A's `superAdminId` but another admin's `sessionId`, the session check would pass in these two middlewares even though the session does not belong to admin-A.

**Code:**
```typescript
// management.routes.ts:273 — missing super_admin_id bind
const session = masterDb.prepare(
  "SELECT id FROM super_admin_sessions WHERE id = ? AND expires_at > datetime('now')"
).get(payload.sessionId);  // no AND super_admin_id = payload.superAdminId

// super-admin.routes.ts:255 — correct
"SELECT id FROM super_admin_sessions WHERE id = ? AND super_admin_id = ? AND expires_at > datetime('now')"
```

**Exploit:**
Requires an attacker to already hold a validly-signed (with `superAdminSecret`) JWT whose `sessionId` belongs to a different admin's session — only achievable with the server's secret or a server-side bug. Real-world blast radius is negligible without that precondition, but the session check provides no defence against a token that inadvertently carries a mismatched `sessionId`.

**Fix:**
Add `AND super_admin_id = ?` with `payload.superAdminId` as the second bind parameter to the session query in both `managementAuth` and `adminAuth`, matching the pattern already used in `superAdminAuth`.

---

### INFO — `masterAuth.ts` exports unused middleware with unreachable audience

**Where:** `packages/server/src/middleware/masterAuth.ts`

**What:**
`masterAuthMiddleware` is exported but never imported anywhere in the codebase. Its `MASTER_JWT_VERIFY_OPTIONS` pins `audience: 'bizarre-crm-master'`, yet no `jwt.sign` call in the codebase ever produces a token with that audience. The file is dead code. It does not create a security hole (the middleware can't be reached), but it suggests an incomplete refactor — if it were ever wired up without a matching sign path it would reject every token with an audience mismatch.

**Code:**
```typescript
// masterAuth.ts — exported, zero import sites across entire packages/server/src/
export function masterAuthMiddleware(req, res, next): void { ... }
// audience: 'bizarre-crm-master' — no jwt.sign ever produces this audience
```

**Exploit:**
No direct exploit. If a future developer wires up the middleware without adding a sign path, all requests to those routes will 401 unconditionally.

**Fix:**
Either delete `masterAuth.ts` (if the master-panel route concept is superseded by the super-admin JWT flow) or document its intended use and add a matching `jwt.sign` call.

---

### INFO — SEC-H103 transition fallback permanently accepts `JWT_SECRET` as verify key even after full migration

**Where:** `packages/server/src/utils/jwtSecrets.ts:88–106`

**What:**
`verifyJwtWithRotation` computes `transitionSecret = rawJwtSecret !== current ? rawJwtSecret : undefined`. When `ACCESS_JWT_SECRET` is set to a dedicated value, `current = ACCESS_JWT_SECRET` and `rawJwtSecret = JWT_SECRET` — the two differ, so `transitionSecret = JWT_SECRET` is **always active** as a third fallback verify key. The boot warning (`warnIfPreviousSecretsSet`) only fires when `ACCESS_JWT_SECRET` is **absent**, so after a complete SEC-H103 migration (all dedicated secrets set), the warning stops but the `JWT_SECRET` fallback silently remains. An operator who rotates `ACCESS_JWT_SECRET` after a suspected leak but does not also rotate `JWT_SECRET` (and does not manually remove the fallback code) has not fully closed the token-forgery window.

**Code:**
```typescript
// jwtSecrets.ts:88-91
const rawJwtSecret = purpose === 'access' ? config.jwtSecret : config.jwtRefreshSecret;
const transitionSecret = rawJwtSecret !== current ? rawJwtSecret : undefined;
// transitionSecret = JWT_SECRET whenever ACCESS_JWT_SECRET is set (always differs)
// Boot warning does NOT fire when ACCESS_JWT_SECRET is set — fallback is silent.
```

**Exploit:**
If `JWT_SECRET` is leaked but `ACCESS_JWT_SECRET` is not, an attacker can forge access tokens verifiable against the `JWT_SECRET` fallback path even if the operator believes `ACCESS_JWT_SECRET` is the only active signing key.

**Fix:**
Add a date/version gate so the transition fallback path auto-disables after the maximum refresh-token lifetime (90 days) from the deployment that introduced `ACCESS_JWT_SECRET`, or add an explicit env var `JWT_SECRET_TRANSITION_DISABLED=true` that operators can set once the migration window closes, and emit a production warning until it is set.

---

### INFO — `DEVICE_TRUST_SECRET` not documented in `.env.example` and not production-fatal

**Where:** `packages/server/src/routes/auth.routes.ts:59–63`

**What:**
`DEVICE_TRUST_SECRET` is read directly from `process.env` inside `auth.routes.ts` (not wired through `config.ts`) with a fallback to `config.jwtSecret`. It is not listed in `.env.example`, so operators have no guidance to set it. Without it, device-trust cookies are keyed from `JWT_SECRET` (via HMAC), tying the 90-day device-trust cookie key material to the JWT signing root — the same cross-purpose coupling that prompted the SEC-H103 multi-key split. A `JWT_SECRET` rotation also silently invalidates all device-trust cookies without warning.

**Code:**
```typescript
// auth.routes.ts:59-63
const _deviceTrustBase = process.env.DEVICE_TRUST_SECRET || config.jwtSecret;
if (!process.env.DEVICE_TRUST_SECRET) {
  logger.warn('DEVICE_TRUST_SECRET not set; device-trust cookies share key material with JWT ...');
}
const deviceTrustKey = crypto.createHmac('sha256', _deviceTrustBase).update('device-trust-v1').digest('hex');
```

**Exploit:**
No standalone exploit path. If `JWT_SECRET` is leaked, an attacker who can observe a device-trust cookie (XSS, MITM) can correlate or forge it — though the forged cookie also requires passing `payload.type === 'device_trust'` and a fingerprint check.

**Fix:**
Add `DEVICE_TRUST_SECRET` to `.env.example` (commented, with generation command) and to `config.ts` with the same production-fatal or at minimum production-warn guard used for `ACCESS_JWT_SECRET`.

---

## Pass 2 Summary

| ID | SEV | Title |
|---|---|---|
| F-S06-06 | MEDIUM | Photo-upload scoped token has no tenant binding — cross-tenant replay in multi-tenant mode |
| F-S06-07 | LOW | `management.routes.ts` `managementAuth` silently skips revocation when `masterDb` is null |
| F-S06-08 | LOW | Session ownership not cross-checked (no `super_admin_id` bind) in `managementAuth` and `adminAuth` |
| F-S06-09 | INFO | `masterAuth.ts` exports unused middleware with unreachable `bizarre-crm-master` audience |
| F-S06-10 | INFO | SEC-H103 transition fallback (`JWT_SECRET`) silently permanent after full migration |
| F-S06-11 | INFO | `DEVICE_TRUST_SECRET` undocumented in `.env.example`; falls back to `JWT_SECRET` without prod enforcement |
