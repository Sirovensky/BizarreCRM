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
