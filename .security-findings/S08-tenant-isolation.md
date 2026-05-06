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
