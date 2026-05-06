# S03 — Two-Factor Auth (TOTP), Step-Up Auth, Recovery Codes

## Findings

---

### [HIGH] In-tenant `/force-disable-2fa` missing re-auth / step-up

- File: `packages/server/src/routes/auth.routes.ts:1995`
- Description: `POST /force-disable-2fa/:userId` requires only `role === 'admin'` — no password confirmation, no TOTP step-up. Any hijacked admin session token (stolen cookie, XSS, network intercept within the 30-min access-token TTL) can silently strip 2FA from any user in the tenant, allowing subsequent account takeover with just the victim's password.
- Exploit: Attacker with stolen admin JWT sends `POST /force-disable-2fa/42` → victim's TOTP cleared → attacker logs in with victim's password alone.
- Compare: The _self-service_ `/account/2fa/disable` requires both `currentPassword` + current TOTP code (line 1908–1959). The _super-admin_ variant (`/tenants/:slug/users/:userId/force-disable-2fa`) is correctly gated with `requireStepUpTotpSuperAdmin` (super-admin.routes.ts:1207). Only the in-tenant admin path is unprotected.
- Fix: Add `admin_confirm_password` + `admin_totp_code` re-auth (same pattern used at settings.routes.ts:1672–1723), or apply `requireStepUpTotp` as middleware on this route.

---

### [MEDIUM] Challenge tokens not validated against tenant — cross-tenant auth confusion

- File: `packages/server/src/routes/auth.routes.ts:190–213`
- Description: `validateChallenge` / `consumeChallenge` return only `userId` and never check `entry.tenantSlug` against the current request's `req.tenantSlug`. In a multi-tenant deployment each tenant has its own SQLite DB; integer user IDs are per-tenant-sequential (user 5 in tenant A is a different person than user 5 in tenant B). A challenge token created on tenant A's `/login` endpoint (for tenant-A user 5) can be submitted to tenant B's `/login/2fa-verify` endpoint. The server looks up user 5 in tenant B's DB; if found, that person is authenticated without entering a password.
- Exploit: Attacker creates an account in tenant A, triggers a login challenge for user ID 5 (or any ID they want to target), then submits that challenge token to tenant B's 2FA-verify endpoint from a browser session pointed at tenant B.
- Note: The comment at line 170 says "Challenge tokens include tenantSlug to prevent cross-tenant 2FA reuse" — the slug is stored in the Map entry but `validateChallenge` never reads it.
- Fix: In `validateChallenge` (and `consumeChallenge`), accept and compare the caller's `tenantSlug`; reject tokens whose stored `tenantSlug` does not match.

---

### [MEDIUM] Password reset does not clear device-trust cookies

- File: `packages/server/src/routes/auth.routes.ts:1784–1892`
- Description: `POST /reset-password` revokes all sessions (`DELETE FROM sessions WHERE user_id = ?`) but does not clear the `deviceTrust` cookie. A trusted-device cookie is a 90-day JWT that bypasses the TOTP challenge on login (line 851–858). If an attacker compromised a device and the user later resets their password expecting full re-lockdown, the existing `deviceTrust` cookie on the attacker's browser remains valid and continues to skip 2FA for the remainder of its 90-day lifetime.
- The self-service 2FA disable (line 1979) and explicit logout (line 1429) both clear `deviceTrust`. Password reset is the odd-one-out.
- Exploit: Attacker captures `deviceTrust` cookie from victim's laptop. Victim notices intrusion, resets password. Attacker still authenticates without 2FA for up to 90 days.
- Mitigation present: Device-trust cookie is fingerprinted to `SHA-256(UA + IP)` (line 846–850), so the attacker must use an identical User-Agent and source IP. On different hardware or network this is not reliably reproducible, lowering practical risk.
- Fix: Add `res.clearCookie('deviceTrust', { path: '/' })` inside the `POST /reset-password` success branch (after line 1888). Because this is an HTTP-only cookie the server can only set Max-Age=0 — but that covers the case where the victim and attacker share the same browser session. For stolen cookies the correct defense is rotating `DEVICE_TRUST_SECRET` (which invalidates all outstanding tokens) upon a coordinated incident.

---

### [LOW] `verifySync` window comment misleading — actual window is current-step-only

- File: `packages/server/src/middleware/stepUpTotp.ts:79–84`
- Description: The comment at line 79 states "verifySync accepts codes from the previous, current, AND next 30-second windows (±1 step skew)." This is incorrect for the version of otplib in use. The functional `verifySync` is called without `epochTolerance`, which defaults to `0`. With `epochTolerance: 0`, `normalizeEpochTolerance` returns `[0, 0]`, giving `minCounter === maxCounter === currentCounter` — only the exact current window is accepted.
- Impact: None on security (stricter is better). However the three-bucket replay-cache logic was implemented to handle a tolerance that does not actually exist in the library call, adding unnecessary complexity. The code is correct but the justification is wrong — if a future developer adjusts the `verifySync` call to add tolerance (e.g., to handle clock-skew complaints), the three-bucket cache correctly handles it; but the current deployed state doesn't need it.
- Fix: Update the comment to accurately reflect `epochTolerance: 0` behavior, or explicitly pass `epochTolerance: 30` (one-step tolerance) to align implementation with the comment's intent and improve usability for users with slightly drifted authenticator clocks.

---

### [LOW] TOTP replay cache is process-local — unsafe in multi-process deployments

- File: `packages/server/src/middleware/stepUpTotp.ts:58`
- Description: `consumedCodes` is an in-process `Map`. If the server is ever run with multiple Node.js workers (e.g., PM2 cluster mode, Kubernetes with horizontal scaling), each process maintains an independent replay map. A TOTP code consumed by worker 1 is unknown to worker 2; the same code can be replayed to any other worker within the 30-second window.
- Current state: No `cluster`/`worker_threads` usage was found in `packages/server/src/index.ts`, so this is not an active vulnerability today.
- Fix: If horizontal scaling is adopted, move the replay store to a shared backend (e.g., a SQLite `totp_consumed_codes` table with a TTL sweep, consistent with the existing SQLite-backed rate limiter pattern in `utils/rateLimiter.ts`).

---

### [INFO] TOTP encryption key derived from `jwtSecret` concatenation (v1/v2 legacy)

- File: `packages/server/src/routes/auth.routes.ts:90–97`
- Description: Legacy v1 and v2 encryption keys are derived via raw `SHA-256` over string concatenations of `jwtSecret` and `superAdminSecret`. These are decryption-only paths (new secrets encrypt with v3 HKDF). The comment at line 70–89 accurately documents the limitation. No new writes use these keys.
- Status: Residual risk only while v1/v2 ciphertexts remain in the database. A migration to re-encrypt all rows to v3 would eliminate the legacy paths entirely.

---

### [INFO] Recovery-code entropy: 80 bits (Crockford base32, 8 codes, bcrypt-hashed)

- File: `packages/server/src/routes/auth.routes.ts:1042–1056`
- Description: Each recovery code is 16 Crockford-base32 characters (5 bits each = 80 bits entropy), generated from `crypto.randomBytes(16)` with no modulo bias (256 % 32 = 0). Eight codes are issued. Codes are bcrypt-hashed (cost 12) at rest. Consumption is atomic (conditional `JSON_REMOVE` UPDATE). No issues found.

---

### [INFO] Step-up middleware coverage — admin actions, billing, secret reads

- Description: `requireStepUpTotp` covers PII exports (customers, reports, settings export, tenant export). `requireStepUpTotpSuperAdmin` covers all destructive super-admin operations (tenant delete/suspend/activate/update, JWT rotation, session kick, config write, backup run/restore/delete, DNS backfill, rate-limit reset, webhook retry). Billing (`/api/v1/billing/checkout`, `/billing/portal`) is not step-up gated; these mutate Stripe-side state and redirect to hosted Stripe pages, so omission is a conscious design choice (low blast radius). The one gap is the in-tenant `/force-disable-2fa` described above under HIGH.

---

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH     | 1 |
| MEDIUM   | 2 |
| LOW      | 2 |
| INFO     | 3 |

---

## PASS 2 — DEEP DIVE

### [MEDIUM] TOTP replay not prevented in login, switch-user, and 2FA-disable flows

**Where:** `packages/server/src/routes/auth.routes.ts:1017` (login/2fa-verify), `auth.routes.ts:1509` (switch-user), `auth.routes.ts:1947` (2fa-disable), `auth.routes.ts:1138` (settings reauth)

**What:**
`claimCode()` replay prevention (SCAN-593) is only applied in the step-up middleware (`middleware/stepUpTotp.ts`). Every other TOTP verification call — `/login/2fa-verify`, `/switch-user`, `/account/2fa/disable`, and the admin password/role re-auth in `settings.routes.ts` — uses raw `verifySync` with no code-consumption tracking. A single valid TOTP code observed during one flow can be presented again to any of these endpoints within the same 30-second window.

**Code:**
```typescript
// auth.routes.ts:1017 — login/2fa-verify (no claimCode)
const isValid = verifySync({ token: code, secret });

// auth.routes.ts:1509 — switch-user TOTP (no claimCode)
isValid = Boolean(verifySync({ token: totpCode, secret }));

// auth.routes.ts:1947 — 2fa-disable TOTP (no claimCode)
totpValid = Boolean(verifySync({ token: totpCode, secret }));

// Contrast: middleware/stepUpTotp.ts:272 — step-up DOES claim the code
if (!claimCode(user.id, totpCode)) { return 403; }
```

**Exploit:**
An attacker who observes a user's TOTP code at login (e.g. shoulder-surfing the authenticator app) can — within the same 30-second window — call `POST /account/2fa/disable` with the same code and the user's password (already known, since the attacker just watched them log in), silently stripping 2FA. The account is then accessible with only the password for all future logins.

**Fix:**
Extract `claimCode` into a shared module (e.g. `utils/totpReplay.ts`) and call it in every TOTP verification path: `/login/2fa-verify`, `/login/2fa-backup`, `/switch-user`, `/account/2fa/disable`, and the settings reauth block. A user's code should be claimable only once per 90-second window regardless of which endpoint consumes it.

---

### [MEDIUM] Step-up TOTP middleware has no per-user brute-force lockout

**Where:** `packages/server/src/middleware/stepUpTotp.ts:201–286` (requireStepUpTotp), `stepUpTotp.ts:337–476` (requireStepUpTotpSuperAdmin)

**What:**
`requireStepUpTotp` and `requireStepUpTotpSuperAdmin` validate the `X-TOTP-Code` header but import no rate-limiting functions (no `checkLockoutRate`, no `checkWindowRate`). On failure they write an audit log entry and return 401, but apply no per-user lockout. The only defense is the global `/api/v1` rate limit of 300 req/min per IP (index.ts:1179), which is bypassed by rotating source IPs. An attacker holding a stolen access JWT can spray all 10^6 possible 6-digit codes across the 30-second TOTP window from a botnet.

**Code:**
```typescript
// stepUpTotp.ts — imports — no rate limiter imported
import crypto from 'crypto';
import { verifySync } from 'otplib';
import { audit } from '../utils/audit.js';
// ... no checkLockoutRate / checkWindowRate import

if (!valid) {
  audit(db, 'pii_export_totp_failed', user.id, ip, { endpoint: endpointLabel });
  res.status(401).json(errorBody(ERROR_CODES.ERR_INPUT_INVALID, 'Invalid TOTP', rid));
  return; // ← no lockout recorded
}
```

**Exploit:**
Attacker steals a tenant admin's access token (e.g. from browser local-storage XSS). The token grants a 1-hour window. Attacker rotates across N IPs and sends up to N × 300 TOTP guesses per minute against `GET /customers/:id/export`. TOTP windows are 30 seconds so each window allows N × 150 guesses; with N ≥ 7 IPs, an attacker exceeds 10^6/30s and can exhaustively cover one TOTP window.

**Fix:**
Add `checkLockoutRate(db, 'totp_stepup', `${userId}`, 5)` before the decrypt/verify step and call `recordLockoutFailure` on failure (same pattern as `checkTotpRateLimit` in `auth.routes.ts:230-236`). Five failed step-up attempts should trigger a 15-minute lockout keyed on the user ID, independent of IP.

---

### [MEDIUM] Super-admin TOTP verify has no per-account lockout on 2FA failures

**Where:** `packages/server/src/routes/super-admin.routes.ts:456–501`

**What:**
The super-admin `/login/2fa-verify` endpoint consumes the challenge token (single-use) but does not increment `failed_login_count` or set `locked_until` on TOTP failure. The `failed_login_count` column is only incremented on password failure (line 338) and only reset to 0 on complete 2FA success (line 519). An attacker who knows the super-admin password can replay the full password-then-TOTP flow — each time receiving a new challenge token — limited only by the IP-keyed challenge-creation cap of 10 per 15 minutes (line 356). With 10 IPs, that is 100 TOTP guesses per 15 minutes against the super-admin TOTP with no account lockout triggered.

**Code:**
```typescript
// super-admin.routes.ts:498-501 — TOTP failure: only audit, no lockout
if (!verified) {
  const ip = req.ip || 'unknown';
  auditLog('super_admin_2fa_failed', admin.id, ip);
  return res.status(401).json({ success: false, message: 'Invalid code. Try again.' });
  // ← no failed_login_count increment, no locked_until update
}
```

**Exploit:**
Attacker phishes or leaks a super-admin password. Uses that password to obtain challenge tokens from N IPs (N × 10 challenges per 15 min). For each challenge, submits one TOTP guess. After 10 attempts per IP-window across enough IPs, an attacker can systematically enumerate the 10^6 TOTP space with no account-level lockout. At N=7 IPs: 4,666 guesses per hour with no account lockout.

**Fix:**
On TOTP verification failure in `/login/2fa-verify`, apply the same `failed_login_count` increment + `locked_until` update that password failure applies (lines 336–344). A super-admin should lock out after N combined password-or-TOTP failures, not password-only failures.

---

### [INFO] Super-admin `epochTolerance: 30` widens TOTP replay surface to 3 windows

**Where:** `packages/server/src/routes/super-admin.routes.ts:493`

**What:**
The super-admin login `/login/2fa-verify` passes `epochTolerance: 30` to `verifySync`, accepting codes from the previous, current, and next 30-second step — a 90-second acceptance window. The tenant-user login path uses the default tolerance of 0 (single window only). Because the super-admin login consumes the challenge token before the TOTP check but does not claim the code, an intercepted code is usable for up to 90 seconds after it first appears in any 30-second step.

**Code:**
```typescript
// super-admin.routes.ts:493 — 3-window acceptance
verified = Boolean(verifySync({ token: code, secret: totpSecret, epochTolerance: 30 }));

// auth.routes.ts:1017 — single-window acceptance (default tolerance: 0)
const isValid = verifySync({ token: code, secret });
```

**Exploit:**
An adversary who intercepts a super-admin TOTP code (e.g. via a compromised authenticator backup) has up to 90 seconds to use it for login, vs. 30 seconds for tenant logins. The wider window is already partially mitigated because the challenge token is single-use, but it increases the effective lifetime of a stolen code.

**Fix:**
Either match the tenant path (remove `epochTolerance: 30`, accept clock skew via NTP and warn users) or add `claimCode` to the super-admin login 2FA-verify path so a code consumed during login is poisoned for the full 90 seconds. The more useful fix is per-account TOTP lockout (see finding above), which limits enumeration more broadly.

---

### [INFO] deviceTrust cookie not bound to tenantSlug — cross-tenant reuse possible in path-based routing

**Where:** `packages/server/src/routes/auth.routes.ts:1076–1090`

**What:**
The deviceTrust JWT payload is `{ userId, type: 'device_trust', fp: fingerprint }` with no `tenantSlug` field. In subdomain-based multi-tenant routing (the default) this is not exploitable because cookies are host-scoped. However, if a deployment uses path-based routing (e.g. `example.com/tenant-a/` and `example.com/tenant-b/`), a deviceTrust cookie issued by tenant A's login flow would be accepted by tenant B's login handler if tenant B also has a user with the same integer user ID, the same UA+IP fingerprint, and the same `deviceTrustKey` (both tenants share the process-level key derived from `DEVICE_TRUST_SECRET`).

**Code:**
```typescript
const deviceToken = jwt.sign(
  { userId: user.id, type: 'device_trust', fp: fingerprint },
  // ← no tenantSlug in payload
  deviceTrustKey,
  { ...JWT_SIGN_OPTIONS, expiresIn: '90d' }
);
```

**Exploit:**
Only exploitable in path-prefix multi-tenant deployments. Not exploitable in default subdomain mode. If path routing is ever adopted, an attacker with a valid deviceTrust cookie for user 5 on tenant A can skip 2FA for user 5 on tenant B during the same 90-day window.

**Fix:**
Add `tenantSlug: req.tenantSlug || null` to the deviceTrust JWT payload and verify it at login (line 851) alongside `payload.userId`.

---

### [INFO] Login response discloses 2FA enrollment status before factor verification

**Where:** `packages/server/src/routes/auth.routes.ts:876–881`

**What:**
After a correct password, the `/login` endpoint responds with `{ totpEnabled: !!user.totp_enabled, requires2faSetup: !user.totp_enabled }`. This tells an attacker, per-account, whether the target has enrolled 2FA — before any second factor is checked. While the information is not directly exploitable on its own, it gives attackers a signal to prioritize accounts without 2FA enrollment for follow-on credential-stuffing attacks and know which accounts can be taken over with only a password.

**Code:**
```typescript
res.json({
  success: true,
  data: {
    challengeToken,
    totpEnabled: !!user.totp_enabled,        // ← reveals 2FA status
    requires2faSetup: !user.totp_enabled,    // ← reveals 2FA status
    requiresPasswordSetup: false,
  },
});
```

**Exploit:**
Attacker runs a list of usernames through `/login` with a guessed/leaked password and collects the `totpEnabled` field to identify accounts that have no 2FA, then targets only those accounts for full account takeover.

**Fix:**
Always return `totpEnabled: true` from the response regardless of actual enrollment status, or omit the field entirely and redirect unenrolled users via a different mechanism (e.g. redirect to setup after issue of the access token). The client-side 2FA-setup flow can instead be driven by a flag embedded in the access token claims.

---

## Summary — Pass 2 additions

| Severity | New in Pass 2 | Pass 1 total | Combined |
|----------|--------------|-------------|---------|
| CRITICAL | 0 | 0 | 0 |
| HIGH     | 0 | 1 | 1 |
| MEDIUM   | 3 | 2 | 5 |
| LOW      | 0 | 2 | 2 |
| INFO     | 3 | 3 | 6 |
