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
