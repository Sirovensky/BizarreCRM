# T21 — SQLite-Specific Injection / Pragma Manipulation / Recursive CTE DoS / FTS5 Quirks

**Slot:** T21
**Date:** 2026-05-06
**Auditor:** Claude (Sonnet 4.6)
**Scope:** `packages/server/src/db/connection.ts`, `db/template.ts`, `db/migrate.ts`, `db/seed.ts`, `services/retentionSweeper.ts`, `services/backup.ts`, `routes/search.routes.ts`, `routes/customers.routes.ts`, `routes/reports.routes.ts`, `index.ts` — and exhaustive grep across all server TypeScript for PRAGMA, ATTACH, LOAD EXTENSION, WITH RECURSIVE, json_each/json_tree, db.exec, db.function, application_id, user_version.

---

## Summary

| SEV | Count |
|-----|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 1 |
| INFO | 2 |

---

### [LOW] `PRAGMA user_version` exposed to unauthenticated public health probe

**Where:** `packages/server/src/index.ts:1920-1948`

**What:**
The `/api/v1/health/ready` endpoint is public (no `authMiddleware`). It reads `PRAGMA user_version` from the master SQLite DB and returns it as `schemaVersion` in the JSON response body. `user_version` equals the count of applied migrations (158 as of this audit), which precisely fingerprints the deployed application version — including whether specific known-vulnerable migration states are present. An attacker can poll this endpoint from outside the network to determine exactly which version of BizarreCRM is running without any credentials.

**Code:**
```typescript
app.get('/api/v1/health/ready', (_req, res) => {   // no authMiddleware
  // ...
  const row = db.prepare('PRAGMA user_version').get() as { user_version?: number } | undefined;
  userVersion = row?.user_version ?? null;
  // ...
  res.json({
    success: true,
    data: {
      status: 'ready',
      degraded: readyError !== null,
      schemaVersion: userVersion,          // ← unauthenticated disclosure
    },
  });
});
```

**Exploit:**
Any unauthenticated caller `GET /api/v1/health/ready` receives `{"data":{"schemaVersion":158,...}}`. An attacker targeting a known vulnerability in a specific migration window (e.g. a bug fixed in migration 120) can confirm whether a given instance is below or above that version before investing in an exploit attempt. The `degraded` flag also leaks boot-phase state.

**Fix:**
Remove `schemaVersion` from the public readiness probe. Return only `{"status":"ready"}` (or a boolean `ok`). Move the schema-version detail to `/api/v1/health/internal` which is already gated to admin role. If orchestrators genuinely need a schema-version signal, expose it only under an API key or admin auth.

---

### [INFO] `PRAGMA table_info(${table})` without own identifier guard in `columnExists`

**Where:** `packages/server/src/services/retentionSweeper.ts:332-339`

**What:**
`columnExists()` builds `PRAGMA table_info(${table})` by string interpolation. SQLite's PRAGMA syntax cannot accept `?` placeholder bindings for pragmas that take an identifier argument (a documented limitation), so this pattern is technically the only viable approach for this pragma. However, `columnExists` itself performs no identifier validation — it relies entirely on the single call-site (`applyPiiRule`, line 476) having already executed `assertSqlIdent(rule.table, 'table')` earlier in the same function. The `PII_RULES` array is a static constant so no user-controlled input flows here at runtime. The risk is latent: a future caller of `columnExists` that passes a user-supplied table name would silently skip the guard. Note: S12 (Pass 2, I4) already documented this finding with identical analysis.

**Code:**
```typescript
function columnExists(db: Database, table: string, column: string): boolean {
  try {
    const rows = db.prepare(`PRAGMA table_info(${table})`).all()   // ← no guard
      as Array<{ name?: string }>;
    return rows.some((r) => r.name === column);
  } catch {
    return false;
  }
}
// Single call-site — applyPiiRule:476 — already called assertSqlIdent(rule.table) at line 449.
// PII_RULES is a static constant; no user input ever reaches columnExists today.
```

**Exploit:**
No current exploit path. All callers pass static string literals from `PII_RULES`. Latent risk: a future caller that passes user-supplied input could trigger PRAGMA injection that reads arbitrary table schema metadata or causes a parse error that the `catch {}` silently swallows.

**Fix:**
Add `assertSqlIdent(table, 'table')` as the first line of `columnExists`, consistent with the pattern already used by `assertSqlIdent` in `applyRule`/`applyPiiRule`. This costs one regex test and closes the latent vector permanently, independently of call-site discipline.

---

### [INFO] `@no-transaction` directive enables `PRAGMA writable_schema = 1` in migrations

**Where:** `packages/server/src/db/migrate.ts:69-80`, `packages/server/src/db/migrations/074_customer_nullable_on_child_tables.sql:27`

**What:**
`migrate.ts` supports a `-- @no-transaction` header in `.sql` files; such migrations run with `db.unsafeMode(true)` which unlocks `sqlite_master` for direct writes. Migration `074` explicitly sets `PRAGMA writable_schema = 1` to rewrite a `CREATE TABLE` statement in-place. This is a legitimate SQLite technique for schema rewriting, and migration files are server-controlled deployment artifacts — not user input. However, the combination of `unsafeMode(true)` + `writable_schema` during boot means that any compromise of the `packages/server/src/db/migrations/` directory (e.g. a supply-chain or CI/CD injection) could introduce a migration that irreversibly corrupts every tenant's SQLite schema at boot time.

**Code:**
```typescript
if (noTransaction) {
  const unsafe = typeof db.unsafeMode === 'function';
  if (unsafe) db.unsafeMode(true);      // ← sqlite_master write-unlocked
  try {
    db.exec(sql);                        // ← runs migration with writable_schema access
    db.prepare('INSERT INTO _migrations ...').run(file);
  } finally {
    if (unsafe) db.unsafeMode(false);   // ← restored deterministically
  }
}
```

**Exploit:**
Not directly exploitable from the network. Exploit requires write access to the `migrations/` directory or the ability to inject a file there (CI/CD compromise, malicious npm package in the build pipeline). A malicious `-- @no-transaction` migration file could issue `PRAGMA writable_schema = 1; UPDATE sqlite_master SET sql = 'DROP TABLE users'; PRAGMA writable_schema = 0;` on every tenant DB at the next boot.

**Fix:**
Consider computing a SHA-256 checksum manifest of all migration files at build time and verifying the manifest at runtime before executing any `@no-transaction` migration. At minimum, document the attack surface in a security runbook so that CI/CD pipeline integrity controls are understood as a dependency of database schema integrity.

---

## SCOPE CLEARED

The following T21 attack surfaces were exhaustively investigated and found to be safe:

1. **ATTACH DATABASE** — Zero occurrences of `ATTACH` in any `.ts` file under `packages/server/src/`. SQLite `ATTACH` is never called anywhere in the server. No user can trigger a cross-database read/write. Verified with: `grep -rn "ATTACH\b" packages/server/src/ --include="*.ts"` → no results.

2. **LOAD EXTENSION / loadExtension** — Zero occurrences. `better-sqlite3` disables extension loading by default (requires `new Database(path, { fileMustExist: false })` followed by `db.loadExtension(path)` to enable). The codebase never calls `loadExtension`. Verified: `grep -rn "loadExtension\|load_extension\|LOAD EXTENSION" packages/server/src/ --include="*.ts"` → no results.

3. **`db.function` / `db.aggregate` UDFs** — Zero occurrences. No user-defined functions are registered on any database handle. There is no `db.function()` or `db.aggregate()` call in any production code. Verified: `grep -rn "db\.function\|db\.aggregate\|createFunction" packages/server/src/ --include="*.ts"` → no results.

4. **`db.exec(userString)` — multi-statement execution with user input** — `db.exec()` is called in exactly three contexts: (a) `db/migrate.ts` running static `.sql` migration files from disk; (b) `repairDeskImport.ts:2459,2479` running hardcoded `CREATE TRIGGER IF NOT EXISTS` DDL to recreate FTS triggers after a nuclear wipe. None of these receive user-supplied SQL strings. Verified: all `db.exec()` call sites were enumerated.

5. **`WITH RECURSIVE` CTE DoS** — The only `WITH RECURSIVE` in the codebase is in `reports.routes.ts:1624` (`months_cte`). The bound parameter is `months - 1` where `months = Math.min(24, Math.max(1, parseInt(req.query.months, 10) || 12))`. Maximum recursion depth is 23 rows (24 months - 1 seed row). No DoS is possible. The `parseBiDays()` helper used in other report endpoints (line 1920) similarly clamps all user-supplied counts.

6. **`json_each` / `json_tree` on user JSON** — Neither function appears anywhere in the server codebase. T09 also confirmed this independently. No JSON depth-bomb surface exists via SQLite's JSON table-valued functions.

7. **`PRAGMA user_version` / `application_id` set by user** — No route or service accepts user input that flows into `db.pragma('user_version = N')` or `db.pragma('application_id = N')`. The `user_version` is only read (in `index.ts:1935`) for the health probe; `application_id` is never used in the server. Column named `application_id` in Vonage/Bandwidth SMS config is an unrelated SMS API field, not a SQLite pragma.

8. **PRAGMA `table_info` injection** — The only interpolated `PRAGMA table_info(${table})` is in `retentionSweeper.ts:334` (`columnExists`). The table name comes exclusively from the static `PII_RULES` constant array and `assertSqlIdent()` has already validated it at the call-site. The two other `PRAGMA table_info(...)` calls in the codebase (`giftCardCodeHashBackfill.ts:44`, `estimateApprovalTokenHashBackfill.ts:50`) use hardcoded literal table names. No user input ever reaches any of these.

9. **FTS5 query injection / DoS via special tokens** — T09 (I2) already exhaustively audited FTS5 MATCH usage. Both `customers.routes.ts:82` and `search.routes.ts:15` implement `ftsMatchExpr()` which: (a) slices input to 200 chars; (b) strips all chars except `[a-zA-Z0-9À-ɏ\s\-@.]` (removing `"`, `*`, `^`, `+`, `(`, `)`, `:`); (c) wraps each token in double-quotes (`"token"*`); (d) binds the result as a `?` parameter. No FTS5 operator survives the sanitizer. The `^aaaa*` DoS pattern is prevented because `^` is stripped and the `*` suffix is only added after the quoted token, not inside it.

10. **WAL / SHM files world-readable** — SQLite WAL mode is enabled (`journal_mode = WAL` in `connection.ts:14`, `tenant-pool.ts:83`). The DB files reside at `packages/server/dist/../data/bizarre-crm.db` and `packages/server/dist/../data/tenants/*.db` — neither path is inside `packages/web/dist/` (the web-served static directory) or `packages/server/dist/../uploads/` (auth-gated by `authMiddleware`). WAL/SHM sidecars are co-located with the DB files in the `data/` directory which is not mapped to any HTTP route. `template.ts:75-78` explicitly deletes `-wal` and `-shm` files when rebuilding the template DB. Backup restore in `backup.ts:900-903` also clears WAL/SHM before the file swap. No HTTP path exposes raw `.db-wal` or `.db-shm` files.

11. **VACUUM triggered by user input** — No route or API accepts input that invokes `VACUUM` or `PRAGMA incremental_vacuum(N)`. The only vacuum calls are inside the internal cron (`index.ts:2537` on a 60-minute tick) and `metricsCollector.ts:176` on a 24-hour throttle — both hardcoded, no user control over timing or scope.

12. **`OR 1=1` parameterization bypass** — All SQL values go through `db.prepare().run(?)` / `adb.all()` / `adb.get()` parameterization. No `${}` string interpolation of user values was found in WHERE clause value positions after the full audit. The `OR 1=1` pattern is only present as a safe `WHERE 1=1` seed for dynamic query builders (e.g. `expenses.routes.ts`, `voice.routes.ts`), not as a bypass.

13. **`backup_path` directory traversal / arbitrary file read** — `backup.ts:764-773` (`resolveBackupPath`) enforces: (a) `isBackupFile()` filename allowlist (must end in `.db` or `.db.enc`, must start with known prefix or pattern); (b) `..`, `/`, `\` rejection; (c) `path.resolve(full).startsWith(resolvedDir + path.sep)` containment. Download streams only allowed files. The `.meta.json` sidecar is blocked by `isBackupFile` (`!f.endsWith('.db') && !f.endsWith('.db.enc')`). `CRLF` injection via `Content-Disposition: attachment; filename="..."` is mitigated by Node.js 14+ header validation (throws `ERR_HTTP_INVALID_HEADER_VALUE` on `\r\n` in header values).

14. **`backup_schedule` cron injection** — `backup.ts:989` calls `cron.validate(schedule)` before activating any scheduled backup; invalid cron expressions cause the schedule to be skipped silently.
