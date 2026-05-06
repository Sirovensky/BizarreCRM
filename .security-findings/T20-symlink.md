# T20 — Symlink Attack Sweep: fs.write/unlink/rename/copyFile on User-Influenced Paths

## Scope

Sweep of every `fs.writeFile`, `fs.writeFileSync`, `fs.unlink`, `fs.unlinkSync`,
`fs.rename`, `fs.renameSync`, `fs.copyFile`, `fs.copyFileSync`, `fs.chmod`,
`fs.chmodSync`, `fs.symlink`, and `path.resolve` call across `packages/server/src/`
for symlink-following and path-containment weaknesses.

Focus files examined end-to-end:
- `services/backup.ts`
- `services/tenantTermination.ts`
- `services/tenant-provisioning.ts`
- `services/retentionSweeper.ts`
- `services/tenantExport.ts`
- `services/crashTracker.ts`
- `services/blockchyp.ts`
- `services/tenant-repair.ts`
- `routes/expenseReceipts.routes.ts`
- `routes/tickets.routes.ts`
- `routes/settings.routes.ts`
- `routes/customers.routes.ts`
- `routes/sms.routes.ts`
- `routes/voice.routes.ts`
- `routes/bench.routes.ts`
- `routes/inventory.routes.ts`
- `routes/inventoryEnrich.routes.ts`
- `middleware/fileUploadValidator.ts`
- `index.ts` (signed-URL + `/uploads` static handler)

---

### HIGH — Admin can delete arbitrary server files via store_logo path traversal

**Where:** `packages/server/src/routes/settings.routes.ts:1675–1680`
(write vector at `settings.routes.ts:570–583`)

**What:**
`PUT /api/v1/settings/store` (admin-only) accepts `store_logo` as a free-form string
with no path validation. The value is written verbatim to `store_config`.
When the admin later uploads a new logo (`POST /api/v1/settings/logo`), the handler
reads the previous `store_logo` value, strips the `/uploads/` prefix with a simple
`startsWith` guard, then calls `path.join(config.uploadsPath, relPath)` followed by
`fs.unlinkSync(prevAbs)` — without `path.resolve` + containment check.
`path.join` does not normalize `..` segments, so a stored value like
`/uploads/../../../etc/cron.d/backdoor` produces `prevAbs = /etc/cron.d/backdoor`
and `fs.unlinkSync` deletes that file.

**Code:**
```typescript
// settings.routes.ts:1675-1680
const prevRow = await adb.get<{ value: string }>(
  "SELECT value FROM store_config WHERE key = 'store_logo'"
);
if (prevRow?.value && prevRow.value.startsWith('/uploads/')) {   // ← only check
  const prevAbs = path.join(                                      // ← path.join NOT realpath
    config.uploadsPath,
    prevRow.value.replace(/^\/uploads\//, '')                     // ← traversal survives
  );
  const stat = fs.statSync(prevAbs);
  decrementStorageBytes(req.tenantId, stat.size);
  try { fs.unlinkSync(prevAbs); } catch {}                        // ← deletes arbitrary file
}
```

**Verified locally:**
```
node -e "const path=require('path');
  const uploadsPath='/app/uploads';
  const value='/uploads/../../../etc/passwd';
  console.log(path.join(uploadsPath, value.replace(/^\/uploads\//,'')));"
// → /etc/passwd
```

**Exploit:**
An authenticated tenant admin sends:
```
PUT /api/v1/settings/store
{ "store_logo": "/uploads/../../../etc/cron.d/daily-job" }
```
Then uploads a new logo via `POST /api/v1/settings/logo`.
The server deletes `/etc/cron.d/daily-job` (or any other file writable by the
Node process) without ever touching the actual uploads directory.
Impact ranges from crashing the application (delete config/DB) to privilege
escalation (delete a file whose absence is exploitable).

**Fix:**
After building `prevAbs`, call `fs.realpathSync` and verify the result starts
with `path.resolve(config.uploadsPath) + path.sep` before proceeding.
Alternatively, reject any `store_logo` value in `PUT /settings/store` that
contains `..` or does not match the expected server-generated pattern
(`/uploads/<slug>/<filename>`).

---

### MEDIUM — expenseReceipts DELETE: diskPath built with path.join, no containment check

**Where:** `packages/server/src/routes/expenseReceipts.routes.ts:336–356`

**What:**
The `DELETE /api/v1/expenses/:expenseId/receipt` handler reconstructs the
on-disk path from the stored `file_path` column using `path.join` without a
subsequent `path.resolve` + `startsWith` containment guard. In normal operation
`file_path` is server-generated (random-hex filename), so direct exploitation
requires a tampered DB row. However, if the row is ever written with a traversal
value (e.g. via a future bug or backup-restore of a crafted DB), `safeUnlink`
will delete an arbitrary file.

**Code:**
```typescript
// expenseReceipts.routes.ts:336-356
const storedPath = upload?.file_path ?? expense.receipt_image_path ?? '';
const relPath    = storedPath.replace(/^\/uploads\//, '');
const diskPath   = relPath
  ? path.join(config.uploadsPath, relPath)   // ← no containment guard
  : null;

// ... transaction ...

if (diskPath) safeUnlink(diskPath);           // ← no check before unlink
```

**Exploit:**
If `file_path` in `expense_receipt_uploads` contains `../../../etc/shadow` (e.g.
from a crafted backup restore or future SQL injection), `diskPath` resolves to
`/etc/shadow` and `safeUnlink` deletes it silently. With admin access and access
to the backup-restore flow, a tenant admin could trigger this.

**Fix:**
After computing `diskPath`, resolve and verify containment:
```typescript
const resolved = path.resolve(diskPath);
const safeBase = path.resolve(config.uploadsPath) + path.sep;
if (!resolved.startsWith(safeBase)) {
  logger.error('expenseReceipt DELETE: path escapes uploads root', { diskPath });
  // skip unlink
} else {
  safeUnlink(resolved);
}
```

---

### MEDIUM — sweepOldExports unlinks absolute DB-stored file_path with no containment check

**Where:** `packages/server/src/services/tenantExport.ts:739–754`

**What:**
`sweepOldExports()` reads `file_path` rows from `tenant_exports` and calls
`fsp.unlink(row.file_path)` directly. `file_path` is an absolute path written
at job completion (`path.join(exportsDir, filename)`) and is server-controlled
in normal operation. However, there is no re-verification that the path still
falls under `config.exportsPath` before deletion. A crafted DB row (via backup
restore of a modified export, or future SQLi) could cause the sweeper to delete
an arbitrary absolute path on the server's filesystem.

**Code:**
```typescript
// tenantExport.ts:739-754
for (const row of expired) {
  if (row.file_path) {
    try {
      await fsp.unlink(row.file_path);   // ← absolute path, no containment
    } catch (err: unknown) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code !== 'ENOENT') {
        logger.error('sweepOldExports: unlink failed', { ... });
        continue;
      }
    }
  }
  // DB row deleted
}
```

**Exploit:**
Attacker restores a crafted tenant backup where `tenant_exports.file_path` contains
`/etc/crontab` or a database file. On the next nightly retention sweep, the sweeper
deletes the targeted file without any path guard.

**Fix:**
Verify that `row.file_path` starts with `path.resolve(config.exportsPath) + path.sep`
before calling `fsp.unlink`. Log and skip (do NOT delete the DB row) if containment
fails.

---

### LOW — Logo replacement path traversal also exposes stat of arbitrary file (info leak)

**Where:** `packages/server/src/routes/settings.routes.ts:1678`

**What:**
Before the `unlinkSync` at line 1680, `fs.statSync(prevAbs)` is called on the
same unchecked `prevAbs` path. `statSync` follows symlinks, so if an attacker
places a symlink at a path inside the uploads directory pointing to a sensitive
file (e.g. `master.db`), the `stat.size` of the target is returned. While the
impact is lower than deletion, it leaks file metadata to the attacker through
`decrementStorageBytes` telemetry and, in a future logging change, potentially
through response bodies.

**Code:**
```typescript
const prevAbs = path.join(config.uploadsPath, prevRow.value.replace(/^\/uploads\//, ''));
const stat = fs.statSync(prevAbs);           // ← follows symlinks, no containment
decrementStorageBytes(req.tenantId, stat.size);
```

**Exploit:**
A tenant admin creates a symlink inside the tenant uploads directory pointing to
`/data/master.db`, stores its relative path in `store_logo`, then triggers a logo
upload. `stat.size` of `master.db` is consumed and, if ever surfaced in an API
response or log, leaks the master DB file size.

**Fix:**
Apply the same `fs.realpathSync` + containment check recommended for the HIGH
finding above. Verify the real path before both `statSync` and `unlinkSync`.

---

## SCOPE CLEARED — Areas verified safe

1. **`middleware/fileUploadValidator.ts` counter writes (lines 144–145, 228–229):**
   Uses `tmpPath = counterPath + '.tmp.' + pid + ts` (unique) then `renameSync(tmpPath, counterPath)`.
   `renameSync` replaces the directory entry atomically — if `counterPath` is a symlink it
   replaces the symlink itself, not the target. No symlink-following write occurs.

2. **`services/blockchyp.ts:deleteSignatureFile` (lines 239–243):**
   Has explicit `path.resolve` + `uploadsRoot + path.sep` containment check before any unlink.
   Verified safe.

3. **`routes/tickets.routes.ts:DELETE /photos/:photoId` (lines 2604–2618):**
   Uses `path.resolve(tenantUploadsRoot, photo.file_path)` then verifies
   `filePath.startsWith(tenantUploadsRoot + path.sep)` before unlink. `path.resolve` normalizes
   `..` segments. `fs.unlinkSync` on a symlink removes the symlink entry, not the target — safe.

4. **`routes/tickets.routes.ts:DELETE /devices/:deviceId` (lines 3128–3139):**
   Same pattern as above — resolve + startsWith guard present, and unlinks affect only the
   symlink inode. Verified safe.

5. **`services/retentionSweeper.ts:sweepClosedTicketPhotos` (lines 207–216):**
   Has explicit `resolvedBase` + `path.sep` containment check before every `fs.unlinkSync`.
   Verified safe.

6. **`routes/customers.routes.ts:GDPR erase` (lines 2065–2081):**
   Has `path.resolve(uploadsBase)` + `resolvedBase + path.sep` containment check. Verified safe.

7. **`services/tenantTermination.ts:purgeExpiredDeletions` (lines 455–493):**
   Iterates `fs.readdirSync(deletedDir)` — all filenames come from the OS, not user input.
   `fs.unlinkSync` on a symlink removes the symlink itself (POSIX unlink semantics),
   not the symlink target. Verified safe.

8. **`services/tenant-provisioning.ts` copyFileSync/renameSync (lines 295, 588–590):**
   `dbPath = path.join(config.tenantDataDir, dbFilename)` where `dbFilename = slug + '.db'`
   and slug passes `SLUG_REGEX = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/`. No traversal chars
   possible. Verified safe.

9. **`services/crashTracker.ts:cleanupStaleTmpFiles` (lines 123–129):**
   Operates only on `path.dirname(CRASH_LOG_PATH)` (static), iterates `readdirSync`,
   filters on a known prefix. No user input. Verified safe.

10. **`index.ts` signed-URL and `/uploads` static handler (lines 1341–1394):**
    Both paths use `path.resolve` + `startsWith` containment checks. Verified safe.
