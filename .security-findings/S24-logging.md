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
