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
