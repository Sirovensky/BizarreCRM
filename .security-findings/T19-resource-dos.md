# T19 — Resource Exhaustion / DoS Surface

**Auditor:** T19 agent  
**Date:** 2026-05-06  
**Backend root:** `packages/server/src/`

---

### [MEDIUM] bcrypt.compareSync called without password length guard in /login, /gdpr-erase, and /settings user-edit reauth paths

**Where:**  
- `packages/server/src/routes/auth.routes.ts:746` (`/login`)  
- `packages/server/src/routes/customers.routes.ts:2024` (`/customers/:id/gdpr-erase`)  
- `packages/server/src/routes/settings.routes.ts:1122` (user update reauth)  

**What:**  
`bcrypt.compareSync` is a pure-JS, synchronous operation that runs on Node's single event loop thread. The login handler at line 746 reads `password` from `req.body` and passes it directly to `bcrypt.compareSync` without checking its length first. The global body-parser limit (`1mb`) means an attacker can submit a password string of ~700 000 characters. With bcrypt at 12 rounds, hashing a 72-byte input takes ~100–200 ms; bcryptjs (pure-JS) at that cost factor blocks the event loop entirely for the duration. The `/gdpr-erase` endpoint (line 2024) has no length guard at all on the `password` field, and the settings reauth path (line 1122) only checks that the string is non-empty.

**Code:**
```typescript
// auth.routes.ts ~line 712-746 — /login
const { username, password } = req.body;
if (!username) { … return; }
// ← NO password.length check here
const hashToCheck = user?.password_hash || DUMMY_HASH;
const bcryptResult = password ? bcrypt.compareSync(password, hashToCheck) : false;

// customers.routes.ts ~line 2013-2024 — /gdpr-erase
const { password } = req.body;
if (!password) throw new AppError('Password confirmation is required …', 400);
// ← NO length cap
const passwordValid = bcrypt.compareSync(password, adminUser.password_hash);
```

**Exploit:**  
An attacker (authenticated or not for the login endpoint) sends `POST /api/v1/auth/login` with `{"username":"x","password":"A".repeat(900000)}`. The rate limiter fires a DB check first but does not reject oversized passwords, so `bcrypt.compareSync` runs the full PBKDF-equivalent loop synchronously, stalling the event loop for several hundred ms per request. At the 300 req/min global rate limit, an attacker on multiple IPs can keep the event loop saturated continuously, causing all other requests to queue and time out — effective DoS for the entire server.

**Fix:**  
Add `if (!password || typeof password !== 'string' || password.length > 128) { reject }` before any `bcrypt.compareSync` call in all three locations, mirroring the cap already in place in `auth.routes.ts:892` (reset-password), `settings.routes.ts:951` (user creation), and `auth.routes.ts:612` (set-password). 128 chars is generous for legitimate users and bcryptjs truncates at 72 anyway.

---

### [MEDIUM] `crypto.pbkdf2Sync` (100 000 iterations) and `crypto.scryptSync` (N=32768) called on main event-loop thread during backup encryption/decryption and tenant export

**Where:**  
- `packages/server/src/services/backup.ts:297` — `pbkdf2Sync` (100k iterations, SHA-512)  
- `packages/server/src/services/tenantExport.ts:288` — `scryptSync` (N=32768, r=8, p=1)  

**What:**  
`deriveKey()` in `backup.ts` calls `crypto.pbkdf2Sync` with 100 000 iterations on the synchronous path. It is invoked from `encryptFile` and `decryptFile`, which are in turn awaited by `runBackup` and `restoreBackup`. Both are called directly from HTTP route handlers (`POST /admin/backup` at `admin.routes.ts:460` and `POST /admin/backups/:filename/restore` at `admin.routes.ts:540`). The `tenantExport.ts` version uses `scryptSync` inside `encryptBuffer`, which is called from `runExportJob`; however, `runExportJob` is deferred via `setImmediate` so it still runs on the main thread, just deferred by one tick. A large backup (the SQLite DB + uploads) will block the event loop for ~50–300 ms per call.

**Code:**
```typescript
// backup.ts:295-297
function deriveKey(salt: Buffer, version: number): Buffer {
  const passphrase = getPassphrase(version);
  return crypto.pbkdf2Sync(passphrase, salt, PBKDF2_ITERATIONS, KEY_LEN, 'sha512');
  // PBKDF2_ITERATIONS = 100_000 — blocks event loop ~50-200ms
}

// tenantExport.ts:287-292
const key = crypto.scryptSync(passphrase, salt, KEY_LEN, {
  N: SCRYPT_N,   // 32_768
  r: SCRYPT_R,   // 8
  p: SCRYPT_P,   // 1
});  // blocks event loop ~50-200ms on main thread
```

**Exploit:**  
An admin repeatedly triggers `POST /admin/backup` (no concurrency mutex on the backup route itself, only a backup-running flag inside `runBackup`). Each call blocks the event loop for ~100–300 ms during `pbkdf2Sync`. If the DB file is large enough that `fsp.readFile` also loads multi-GB into memory (line 302), the combined block + GC pause can stall normal request handling. A compromised admin account can DoS the tenant's server this way.

**Fix:**  
Replace `pbkdf2Sync` with `util.promisify(crypto.pbkdf2)(…)` and `scryptSync` with `util.promisify(crypto.scrypt)(…)` which offload to libuv's thread pool, keeping the event loop free. Alternatively, derive keys in a Piscina worker (the worker pool already exists for DB I/O). The backup restore path (`admin.routes.ts:540`) must also be made fully async by converting `decryptFile` to a streaming pipeline so multi-GB DB files are never fully read into memory.

---

### [MEDIUM] `fs.createReadStream` without `.on('error')` handler in two voice recording endpoints — file descriptor leak on stream errors

**Where:**  
- `packages/server/src/routes/voice.routes.ts:298` — `GET /voice/recording/:id` (signed-URL endpoint)  
- `packages/server/src/routes/voice.routes.ts:371` — `GET /voice/calls/:id/recording` (authed endpoint)  

**What:**  
Both endpoints call `fs.createReadStream(filePath).pipe(res)` without attaching an `'error'` event listener. If the underlying file disappears, the OS revokes read permission, or a disk I/O error occurs mid-stream, Node emits an `'error'` event on the readable stream. Without a listener, this becomes an unhandled `'error'` event and crashes the process (Node treats unhandled `'error'` events as fatal). Additionally, an unfinished pipe on an errored stream can leave the file descriptor open until GC cleans it up, slowly exhausting the fd limit. This is in contrast to `admin.routes.ts:490–496` which correctly registers `.on('error', …)`.

**Code:**
```typescript
// voice.routes.ts:295-299
if (fs.existsSync(filePath)) {
  res.setHeader('Content-Type', 'audio/mpeg');
  res.setHeader('Cache-Control', 'no-store');
  fs.createReadStream(filePath).pipe(res);   // ← no .on('error', ...)
  return;
}

// voice.routes.ts:368-372
const filePath = path.join(config.uploadsPath, …);
res.setHeader('Content-Type', 'audio/mpeg');
fs.createReadStream(filePath).pipe(res);     // ← no .on('error', ...)
```

**Exploit:**  
An attacker who can cause a race between the `fs.existsSync` check and the `createReadStream` call (e.g., by deleting the recording file via an admin API after obtaining its path) can trigger an unhandled stream error on the HTTP worker. On older Node versions (< 18.11) this crashes the process; on newer versions the async context catches it, but the fd may still leak until GC. In a heavily loaded environment with many concurrent recording requests this can exhaust file descriptors.

**Fix:**  
Attach `.on('error', (err) => { log.error(…); if (!res.headersSent) res.status(500).end(); else res.destroy(); })` on both stream instances, mirroring the pattern in `admin.routes.ts:491–497`. Consider using `pipeline(stream, res)` from `node:stream/promises` which automatically destroys both on error.

---

### [LOW] `node-cron` backup tasks (`scheduleBackup`, `scheduleMultiTenantBackups`) are never stopped during graceful shutdown

**Where:**  
- `packages/server/src/services/backup.ts:992` — `cronTask = cron.schedule(…)`  
- `packages/server/src/services/backup.ts:1032` — `multiTenantBackupCron = cron.schedule('7 3 * * *', …)`  
- `packages/server/src/index.ts:3768` — shutdown loop only clears `backgroundIntervals`  

**What:**  
Both backup cron tasks are `node-cron` `ScheduledTask` objects, not raw `NodeJS.Timeout` handles. They are NOT pushed into `backgroundIntervals` and their `.stop()` method is never called in the `shutdown()` function. If a cron tick fires during the shutdown window (after `backgroundIntervals` are cleared but before `process.exit()`), it will attempt to open/read the tenant DB after `closeAllTenantDbs()` has already closed it, producing "database is closed" errors in logs and potentially crashing the teardown path.

**Code:**
```typescript
// backup.ts:992 — module-scoped, never exported for shutdown
cronTask = cron.schedule(schedule, () => { … runBackup(getDb()) … });

// index.ts:3768 — shutdown only covers backgroundIntervals
for (const handle of backgroundIntervals) {
  try { clearInterval(handle); cleared++; } catch { /* ignore */ }
}
// ← no cronTask.stop() or multiTenantBackupCron.stop()
```

**Exploit:**  
During graceful shutdown at 3:07 AM (the scheduled backup time), `multiTenantBackupCron` fires as the server is closing, opens tenant DB handles (which may already be closed), and crashes with "database is closed" errors. This is observable as a non-zero exit code, confusing PM2's restart logic and potentially masking the real shutdown signal.

**Fix:**  
Export `stopBackupScheduler()` from `backup.ts` that calls `cronTask?.stop()` and `multiTenantBackupCron?.stop()`, and call it at the start of `shutdown()` in `index.ts` alongside `stopWebSocketHeartbeat()`. Similarly, `stopMetricsCollector()` (which already exists in `metricsCollector.ts:359`) is never called during shutdown — add it to the shutdown sequence to prevent the self-rescheduling `setTimeout` chain from firing after DB teardown.

---

### [LOW] Four external cron timers (`receiptOcrCron`, `recurringInvoicesCron`, `dataExportScheduleCron`, `slaBreachCron`) use raw `setInterval` without `.unref()`, preventing clean process exit if `backgroundIntervals` cancellation is skipped

**Where:**  
- `packages/server/src/services/receiptOcrCron.ts:184`  
- `packages/server/src/services/recurringInvoicesCron.ts:336`  
- `packages/server/src/services/dataExportScheduleCron.ts:290`  
- `packages/server/src/services/slaBreachCron.ts:284`  

**What:**  
All four service files return a `NodeJS.Timeout` from `setInterval(…)` without calling `.unref()`. They are pushed into `backgroundIntervals` in `index.ts` and cleared during normal shutdown. However, if a `process.exit` path fires before the graceful shutdown handler runs (e.g., an uncaught exception in early boot before the handlers are registered), these ref'd timers prevent the process from exiting naturally, causing PM2 or Docker's `kill_timeout` to force-kill with SIGKILL. By contrast, `trackInterval()` in `utils/trackInterval.ts:59` calls `.unref()` by default — the external cron helpers do not use `trackInterval`.

**Code:**
```typescript
// receiptOcrCron.ts:184 — no .unref()
return setInterval(() => void tick(), CRON_INTERVAL_MS);

// recurringInvoicesCron.ts:336 — no .unref()
return setInterval(tick, CRON_INTERVAL_MS);
```

**Exploit:**  
If the server hard-exits (OOM kill, uncaught exception before shutdown handlers register), these intervals keep Node's event loop alive, causing a hung process that PM2 must SIGKILL after `kill_timeout`. In a container environment this means the pod does not exit cleanly, blocking re-scheduling.

**Fix:**  
Call `.unref()` on the returned handle in each file before returning, or refactor these services to use `trackInterval()` from `utils/trackInterval.ts` which already handles `unref`, error catching, and `backgroundIntervals` registration consistently.

---

### [LOW] `/health` and `/api/v1/health` run a synchronous DB `SELECT 1` probe on every request with no rate limit

**Where:**  
- `packages/server/src/index.ts:1863–1886` — `probeMasterDb()`, `/health`, `/api/v1/health`  

**What:**  
Both `/health` and `/api/v1/health` routes call `probeMasterDb()` which executes `db.prepare('SELECT 1').get()` synchronously on every hit. These endpoints are mounted outside the `/api/v1` rate-limiter scope (the limiter is `app.use('/api/v1', …)` at line 1181 which activates only inside that prefix, and `/health` is at the root). A monitoring service, load balancer, or attacker polling at high frequency will execute a synchronous DB round-trip per request. While `SELECT 1` is extremely cheap, thousands of requests per second from a health-check flood can still add measurable synchronous pressure to the event loop.

**Code:**
```typescript
// index.ts:1863-1878 — no rate limit, no cache
function probeMasterDb(): boolean {
  try { db.prepare('SELECT 1').get(); return true; } catch { return false; }
}
app.get('/health', (_req, res) => {
  if (!probeMasterDb()) { res.status(503)…; return; }
  res.json({ success: true, data: { status: 'ok' } });
});
```

**Exploit:**  
An external client or scanner floods `/health` at 10 000 req/s. Each call executes a synchronous SQLite read. The combined synchronous pressure degrades response times for authenticated API routes sharing the same event loop.

**Fix:**  
Cache the `probeMasterDb()` result in a module-level variable with a 5-second TTL (the watchdog polls `/api/v1/health/live` at 30s so 5s staleness is safe). Alternatively, add a lightweight in-process IP rate limit (e.g., `consumeWindowRate` at 60 req/min per IP) on these two probes using the existing SQLite rate-limiter.

---

### [LOW] Backup `encryptFile`/`decryptFile` read entire DB file into memory before processing — unbounded memory spike on large databases

**Where:**  
- `packages/server/src/services/backup.ts:302` — `await fsp.readFile(inputPath)` (entire DB into Buffer)  
- `packages/server/src/services/backup.ts:336` — `await fsp.readFile(encPath)` (entire `.enc` into Buffer)  
- `packages/server/src/services/backup.ts:907` — `await fsp.readFile(opts.targetDbPath)` (for SHA-256 hash)  

**What:**  
`encryptFile` reads the entire DB file into `plaintext` with a single `fsp.readFile`, allocates another `Buffer` for the ciphertext, then concatenates them for the write — tripling peak memory for the duration. For a 500 MB SQLite database this spikes RSS by ~1.5 GB in a single backup call. `decryptFile` does the same for the encrypted file. The ecosystem config sets `max_memory_restart: '1G'` for the PM2 process; a backup on a large tenant DB will trip the restart threshold and kill the server mid-backup.

**Code:**
```typescript
// backup.ts:300-316
export async function encryptFile(inputPath: string): Promise<string> {
  const plaintext = await fsp.readFile(inputPath);      // entire DB → Buffer
  const key = deriveKey(salt, CURRENT_KEY_VERSION);
  const cipher = crypto.createCipheriv(ENCRYPTION_ALGO, key, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]); // 2× size
  await fsp.writeFile(outputPath,
    Buffer.concat([BACKUP_MAGIC, versionByte, salt, iv, authTag, encrypted])); // 3× size peak
```

**Exploit:**  
A production tenant with a 400 MB database triggers the daily backup cron. The RSS spikes by ~1.2 GB, crossing the 1 GB PM2 `max_memory_restart` threshold, which kills and restarts the server. The partially written `.enc` file is left on disk but the DB handle is closed mid-operation. Repeated oscillation causes PM2 to exhaust `max_restarts: 10` and permanently disable the app.

**Fix:**  
Implement the backup as a streaming pipeline: `fs.createReadStream(inputPath)` piped through `crypto.createCipheriv(…)` piped to `fs.createWriteStream(outputPath)`. This reduces peak memory from 3× file size to a few kilobytes of cipher block size. The SHA-256 hash post-restore (line 907) should similarly use `crypto.createHash('sha256').update(readStream)` instead of buffering the full file.

---

### [INFO] `metricsCollector` self-rescheduling `setTimeout` chain not stopped during graceful shutdown

**Where:** `packages/server/src/services/metricsCollector.ts:359` — `stopMetricsCollector()` exists but is never called from `packages/server/src/index.ts` shutdown()

**What:**  
`startMetricsCollector()` is called at boot (line 327 of `index.ts`) but `stopMetricsCollector()` is never called in the `shutdown()` function. The `sampleTimer` and `rollupTimer` are `setTimeout` handles that reschedule themselves. They call `.unref()` so they do not prevent process exit on their own, but when `collectorStopped` remains false the chain keeps rescheduling; if the 60 s sample fires after `metricsDb` is closed, a logged error occurs. The `metricsDb` handle inside `metricsCollector.ts` is also never closed during shutdown, leaving the fd open.

**Fix:**  
Call `stopMetricsCollector()` (already exported) inside `shutdown()` in `index.ts`, alongside `stopWebSocketHeartbeat()`.

---

## Summary

| Sev | Count | Title snippet |
|-----|-------|--------------|
| MEDIUM | 3 | bcrypt.compareSync without length guard; pbkdf2Sync/scryptSync on event loop; createReadStream without error handler |
| LOW | 4 | node-cron backup not stopped on shutdown; cron timers lack .unref(); /health DB probe unthrottled; backup reads full DB into RAM |
| INFO | 1 | metricsCollector not stopped on shutdown |
