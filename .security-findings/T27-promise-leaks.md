# T27 — Promise Leaks, Unhandled Rejections, Event-Loop Hazards

Audited: 2026-05-06
Scope: long-running tasks, promise leaks, unhandled rejections, event-loop hazards
Focus files: `packages/server/src/utils/longTaskRegistry.ts`, `trackInterval.ts`, `index.ts`, `ws/server.ts`, `services/webhooks.ts`, `services/automations.ts`, `services/metricsCollector.ts`, `routes/super-admin.routes.ts`, `routes/tickets.routes.ts`, `routes/employees.routes.ts`, `routes/management.routes.ts`, `routes/billing.routes.ts`

---

### [HIGH] ~25 bare async route handlers in super-admin.routes.ts crash server on rejection

**Where:** `packages/server/src/routes/super-admin.routes.ts:697` (and lines 283, 382, 407, 752, 774, 1128, 1173, 1207, 1402, 1626, 2074, 2148, 2256, 2366, 2582, 2720+)
Also: `packages/server/src/index.ts:3918`

**What:**
`super-admin.routes.ts` contains ~25 route handlers declared as `async (req, res) =>` with no `asyncHandler` wrapper and no try/catch around await calls. In Express 4, an uncaught rejection inside an async handler does NOT propagate to `next(err)` — it becomes an `unhandledRejection`. `index.ts` line 3918 registers `process.on('unhandledRejection', …)` which calls `handleFatal()` → graceful shutdown with `process.exit(1)`. A single DB error or network failure in any of these handlers crashes the entire server. Line 697 is the highest-risk example: `await provisionTenant({…})` runs tenant provisioning (DB creation, migration runs, directory creation) with zero error containment.

**Code:**
```typescript
// super-admin.routes.ts:697 — no asyncHandler, no try/catch
router.post('/tenants', requireSuperAdmin, async (req, res) => {
  const { slug, name, plan, ownerEmail, ownerName } = req.body;
  const newTenant = await provisionTenant({        // ← rejection escapes to unhandledRejection
    masterDb, slug, name, plan, ownerEmail, ownerName,
  });
  res.status(201).json({ success: true, tenant: newTenant });
});

// index.ts:3918 — unhandledRejection → crash
process.on('unhandledRejection', (error) => {
  handleFatal('unhandledRejection', error);        // ← exits process
});
```

**Exploit:**
An authenticated super-admin hits `POST /api/v1/super-admin/tenants` with a slug that already exists (or any DB constraint violation). `provisionTenant` rejects, the rejection escapes Express 4's sync try/catch model, triggers `unhandledRejection`, and the server process exits. This is an availability attack requiring only super-admin credentials — or triggered accidentally by any provisioning conflict.

**Fix:**
Add `import { asyncHandler } from '../middleware/asyncHandler.js'` and wrap every `async (req, res) =>` handler: `router.post('/tenants', requireSuperAdmin, asyncHandler(async (req, res) => { … }))`. Alternatively upgrade to Express 5 which propagates async rejections automatically. A short-term stop-gap is adding try/catch to the highest-risk handlers (lines 697, 752, 1128, 1626).

---

### [HIGH] Untracked 24-hour setTimeout in tickets.routes.ts holds event loop and fires after DB shutdown

**Where:** `packages/server/src/routes/tickets.routes.ts:2234` (approximate — feedback SMS delay block)

**What:**
After a ticket closes with a feedback phone number, a raw `setTimeout(async () => { … }, delayMs)` fires up to 24 hours later. This timer is (a) not `.unref()`'d — it prevents the Node.js process from exiting naturally, (b) not registered in `backgroundIntervals` — graceful shutdown does not clear it, and (c) captures `db` and `adb` (the tenant DB handle and archive DB handle) by closure — both handles will be closed by the time the timer fires after a restart-free long-running session or after server shutdown starts. When the timer fires post-shutdown it attempts `await adb.run('INSERT INTO customer_feedback …')` on a closed SQLite handle, causing an unhandled rejection in a context that has no catch path.

**Code:**
```typescript
// tickets.routes.ts ~2234
setTimeout(async () => {
  try {
    const { sendSmsTenant } = await import('../services/smsProvider.js');
    await sendSmsTenant(db, tenantSlug, feedbackPhone, smsBody);
    await adb.run(`INSERT INTO customer_feedback ...`);
    await adb.run(`INSERT INTO sms_messages ...`);
  } catch (err) {
    logger.error('Feedback SMS delayed send failed', { err });
  }
}, delayMs);   // delayMs = delayHours * 3_600_000, default 24h
// ← not unref'd, not in backgroundIntervals, db/adb closure capture
```

**Exploit:**
Server restarts (deploy, crash, watchdog) reset the timer — feedback SMS is silently dropped. For availability: during server shutdown the 24h timer continues holding the event loop (no `.unref()`) which may delay or prevent clean shutdown on platforms that wait for the event loop to drain. On a long-lived server with high ticket volume, thousands of pending timers accumulate in process memory.

**Fix:**
Replace the raw `setTimeout` with a persisted deferred-job approach (store `(phone, body, sendAt)` in a DB table, process via the existing `trackInterval` sweep). If the in-process timer must stay, call `.unref()` on the handle, add it to `backgroundIntervals`, and at timer fire-time re-acquire the DB via `getTenantDb(slug)` rather than relying on the closed closure reference.

---

### [MEDIUM] Promise.race orphan in membership cron — BlockChyp charges continue after timeout

**Where:** `packages/server/src/index.ts:2224` (membership cron inner per-tenant block)

**What:**
The membership cron wraps each tenant's work in `Promise.race([membershipTenantWork(slug, tenantDb), timeout])`. When the `MEMBERSHIP_PER_TENANT_TIMEOUT_MS` timeout wins, the race resolves/rejects, but `membershipTenantWork` continues executing in the background with no way to cancel it. A comment in the code acknowledges this ("we can't abort it without AbortSignal plumbing that doesn't exist yet"). `membershipTenantWork` may include BlockChyp charge attempts — a timed-out tenant's billing logic can still complete (or partially complete) while the scheduler has already moved on, potentially resulting in double charges if the next cron tick starts a new race before the orphan finishes.

**Code:**
```typescript
// index.ts ~2224
const timeout = new Promise<void>((_, reject) => {
  timer = setTimeout(() => reject(new Error(`Membership cron timeout...`)), MEMBERSHIP_PER_TENANT_TIMEOUT_MS);
});
try {
  await Promise.race([membershipTenantWork(slug, tenantDb), timeout]);
} catch (err) {
  logger.error('Membership tenant work timed out or errored', { slug });
} finally {
  if (timer) clearTimeout(timer);
  // ← membershipTenantWork() is still running here if timeout won
}
```

**Exploit:**
Under slow DB or network conditions for a specific tenant, the cron timeout fires. The next cron tick (next scheduled interval) starts a second `membershipTenantWork` for the same tenant while the first is still in-flight. Both reach the BlockChyp charge call for the same member's renewal — double charge. Impact: financial harm to members, chargeback risk.

**Fix:**
Pass an `AbortSignal` from `AbortController` into `membershipTenantWork` and check it at each await boundary (before each charge). Alternatively add a per-tenant in-flight flag in a `Map<string, boolean>` that prevents a new run while the previous is active (even if orphaned).

---

### [MEDIUM] Nested dynamic import().then() missing inner .catch() for multi-tenant backup scheduler

**Where:** `packages/server/src/index.ts:2106`

**What:**
The multi-tenant backup setup uses nested dynamic imports. The outer `.then()` has a `.catch()`, but the inner `import('./db/tenant-pool.js').then(…)` has no `.catch()`. If `tenant-pool.js` fails to import (module resolution error, syntax error in the module), or if `getTenantDb`/`releaseTenantDb` exports are missing, the inner promise rejects silently — no error is logged, no fallback, and `scheduleMultiTenantBackups` is never called. Backups silently stop without any operator alert.

**Code:**
```typescript
// index.ts:2106
import('./services/backup.js').then(({ scheduleMultiTenantBackups }) => {
  import('./db/tenant-pool.js').then(({ getTenantDb: getTenantDbFn, releaseTenantDb: releaseTenantDbFn }) => {
    scheduleMultiTenantBackups(getMasterDb, getTenantDbFn, releaseTenantDbFn);
  });                             // ← no .catch() here — silent failure
}).catch((err) => {
  console.error('[Backup] Failed to load backup service', err);
});
```

**Exploit:**
A bad deploy that breaks `tenant-pool.js` exports causes multi-tenant backup to silently stop. Data loss risk: if tenant databases are damaged between the broken deploy and the next deploy that fixes the issue, no backups exist. No monitoring alert fires because the error is swallowed.

**Fix:**
Chain `.catch()` on the inner import: `import('./db/tenant-pool.js').then(…).catch(err => console.error('[Backup] tenant-pool import failed', err))`. Or flatten to `Promise.all([import('./services/backup.js'), import('./db/tenant-pool.js')]).then(…).catch(…)`.

---

### [MEDIUM] requestCounter dynamic import().then() missing .catch() — metrics interval silently skipped

**Where:** `packages/server/src/index.ts:2377`

**What:**
The request-counter metrics interval is set up via `import('./utils/requestCounter.js').then(({ getRequestsPerSecond, getRequestsPerMinute }) => { trackInterval(…) })` with no `.catch()`. If the dynamic import fails, `trackInterval` is never called, the metrics collection for req/s and req/min never starts, and no error is surfaced. Under normal operation this is low-risk but a module error (e.g., TypeScript compilation failure, missing dependency) silently degrades observability.

**Code:**
```typescript
// index.ts:2377
import('./utils/requestCounter.js').then(({ getRequestsPerSecond, getRequestsPerMinute }) => {
  trackInterval(() => {
    const rps = getRequestsPerSecond();
    const rpm = getRequestsPerMinute();
    // ... log metrics
  }, 5000);
});  // ← no .catch()
```

**Exploit:**
Not a direct security exploit, but silent metric loss hampers detection of brute-force attacks (which would spike req/s metrics) and DDoS. An attacker who can trigger a module load failure (e.g., via a crafted file that shadows the module in a development environment) removes rate-anomaly visibility.

**Fix:**
Add `.catch(err => logger.error('[Metrics] requestCounter import failed', err))`. Optionally make this a hard startup failure with `throw` inside `.catch` if metrics are considered critical.

---

### [MEDIUM] fireWebhook IIFE has no shutdown coordination — dead-letter INSERT after DB close

**Where:** `packages/server/src/services/webhooks.ts` (fireWebhook function, IIFE body)

**What:**
`fireWebhook()` returns `void` and internally launches `(async () => { … })()` without capturing the promise. The IIFE performs up to 3 delivery attempts with exponential backoff (total ~10 seconds). During graceful shutdown, `shutdown()` in `index.ts` closes the tenant DB handles and then the master DB. Any in-flight `fireWebhook` IIFE that is between retry delays will resume after the DB is closed and attempt to execute `db.run('INSERT INTO webhook_delivery_log …')` or similar dead-letter writes on a closed handle. The resulting exception is caught by the IIFE's try/catch and logged, but the delivery record is lost.

**Code:**
```typescript
// webhooks.ts — simplified
export function fireWebhook(db: TenantDb, event: string, data: unknown): void {
  (async () => {
    try {
      await deliverWithRetry(db, event, data);  // up to ~10s: 0s / 2s / 8s backoff
    } catch (err) {
      logger.error('Webhook pipeline crashed before delivery', { err });
      // ← dead-letter INSERT would go here — db already closed on shutdown
    }
  })();
  // ← Promise not captured, no shutdown coordination
}
```

**Exploit:**
During a rolling deploy or crash-triggered restart, webhooks fired within 10 seconds of shutdown are silently dropped — no dead-letter record, no retry on next start. For payment confirmation or ticket-closed webhooks this means downstream integrations (Zapier, partner systems) miss critical events with no indication of failure.

**Fix:**
Track in-flight IIFE promises in a module-level `Set<Promise<void>>`. Export a `drainWebhooks(timeoutMs)` function that `await Promise.race([Promise.allSettled([...inFlight]), sleep(timeoutMs)])`. Call this from `shutdown()` before closing DB handles. Additionally pass an `AbortSignal` to `deliverWithRetry` so in-flight retries can be cancelled on shutdown.

---

### [LOW] Initial setTimeout in employees.routes.ts auto-clockout sweep not tracked or unref'd

**Where:** `packages/server/src/routes/employees.routes.ts:727` (startAutoClockoutSweep function)

**What:**
`startAutoClockoutSweep()` uses a raw `setTimeout(() => { autoClockoutSweepTimer = trackInterval(…); }, firstTickDelay)` to delay the first sweep tick by ~5 minutes (jitter-based). This initial `setTimeout` handle is not stored, not `.unref()`'d, and not in `backgroundIntervals`. If shutdown occurs within the 5-minute window: (1) the timer is not cleared, (2) when it fires post-shutdown it calls `trackInterval(…)` which pushes a new handle into `backgroundIntervals` after the array has already been swept — the new interval will never be cleared.

**Code:**
```typescript
// employees.routes.ts:727
setTimeout(() => {
  autoClockoutSweepTimer = trackInterval(async () => {
    // ... auto-clockout logic
  }, AUTO_CLOCKOUT_SWEEP_INTERVAL_MS);
}, firstTickDelay);   // ← not stored, not unref'd, not in backgroundIntervals
```

**Exploit:**
Low direct security impact. On a server that starts and shuts down within 5 minutes (common in rolling deploy pipelines), the orphaned timeout fires during or after shutdown, attempts to run auto-clockout DB queries against closed handles, and logs errors. In high-frequency deploy environments this creates persistent log noise that can obscure real errors.

**Fix:**
Store the handle: `const initTimer = setTimeout(…); if (initTimer.unref) initTimer.unref(); backgroundIntervals.push(initTimer)`.

---

### [LOW] metricsCollector stop function never called in shutdown — metricsDb handle leaked

**Where:** `packages/server/src/services/metricsCollector.ts` (stopMetricsCollector function)
Also: `packages/server/src/index.ts` (shutdown function, lines 3758–3822)

**What:**
`metricsCollector.ts` exports `stopMetricsCollector()` which cancels the self-rescheduling sample and rollup setTimeout chains and (presumably) closes `metricsDb`. The `shutdown()` function in `index.ts` clears `backgroundIntervals`, closes the WS heartbeat, HTTP server, tenant pool, master DB, and primary DB — but never calls `stopMetricsCollector()`. The metrics SQLite handle remains open at process exit. On Linux/macOS this is cleaned up by OS, but on Windows this can prevent the DB file from being replaced during an update and may produce "database is closed" errors if the GC finalizes the handle after the event loop has partially torn down.

**Code:**
```typescript
// index.ts shutdown() — stopMetricsCollector() is absent
backgroundIntervals.length = 0;
stopWebSocketHeartbeat();
await httpServerClose();
await tenantPool.close();
masterDb.close();
primaryDb.close();
// ← stopMetricsCollector() never called
```

**Exploit:**
No direct exploit. On Windows deployments with auto-update, the locked `metrics.db` file prevents the updater from replacing it, causing the update to fail or skip the metrics DB replacement. Operator must manually kill the process or unlock the file.

**Fix:**
Add `stopMetricsCollector()` to the shutdown sequence before `masterDb.close()`. Import it at the top of `index.ts` or import dynamically in the shutdown path if metricsCollector is loaded lazily.

---

### [INFO] runAutomations fire-and-forget IIFE risks inconsistent state on tenant pool eviction

**Where:** `packages/server/src/services/automations.ts` (runAutomations function)

**What:**
`runAutomations()` is explicitly designed as fire-and-forget: it launches `(async () => { … })()` and returns `void`. The IIFE may execute `executeSendSms`, `executeSendEmail`, `executeChangeStatus` which write to the tenant DB passed as a closure parameter. If the tenant pool evicts that DB handle between when `runAutomations` is called and when the async work completes (possible under memory pressure with many active tenants), the writes will fail. The error is caught and logged but the automation state is left inconsistent — a status change might be half-applied (email sent but DB row not updated).

**Code:**
```typescript
// automations.ts
export function runAutomations(db, trigger, context, execContext?): void {
  (async () => {
    try {
      // ... loop over rules, call executeSendSms/Email/ChangeStatus(db, ...)
    } catch (err) {
      logger.error('Automation pipeline error', { trigger, err });
    }
  })();
}
```

**Exploit:**
Under high load with a large tenant pool, a tenant's DB may be evicted mid-automation. A ticket-close trigger fires `runAutomations`; the eviction happens; `executeChangeStatus` fails silently; the ticket remains in wrong status, automation rule marked as triggered but effect not applied. Not directly exploitable but causes audit log / state divergence.

**Fix:**
For correctness, `runAutomations` should either (a) re-acquire the DB via `getTenantDb(slug)` at the start of the IIFE rather than using the closure reference, or (b) be converted to a proper queued job. At minimum, document the eviction risk and consider adding the in-flight promise to a tracking set per tenant.

---
