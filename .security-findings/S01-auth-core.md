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
