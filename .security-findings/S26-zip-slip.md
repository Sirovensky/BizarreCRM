# S26 — Zip-slip / Tar-slip / CSV formula injection in archive + import flows

## Scope investigated

- `packages/server/src/services/myRepairAppImport.ts` (read fully)
- `packages/server/src/services/repairDeskImport.ts` (read fully)
- `packages/server/src/services/repairShoprImport.ts` (read fully)
- `packages/server/src/services/receiptOcr.ts` (read fully)
- `packages/server/src/scripts/full-import.ts` (read fully)
- `packages/server/src/services/dataExportGenerator.ts` (read fully)
- `packages/server/src/services/backup.ts` (read fully)
- `packages/server/src/services/tenantExport.ts` (read fully)
- `packages/server/src/services/tenantTermination.ts` (read fully)
- `packages/server/src/routes/tickets.routes.ts` (CSV export section)
- `packages/server/src/routes/inventory.routes.ts` (CSV import + export section)
- `packages/server/src/routes/customers.routes.ts` (CSV import section)
- `packages/server/src/routes/reports.routes.ts` (CSV export section)
- `packages/server/src/routes/team.routes.ts` (payroll CSV export section)
- Grep for: `unzipper`, `adm-zip`, `yauzl`, `tar.x`, `csv-parse`, `papaparse`, `extractAllTo`, `isSymbolicLink`, ZIP-related patterns

---

### [MEDIUM] `full-import.ts` script falls back to hardcoded credentials `admin`/`admin123`

**Where:** `packages/server/src/scripts/full-import.ts:33`

**What:**
The operator-run bulk-import script calls `login()` and falls back to the literal default credentials `admin`/`admin123` when the environment variables `ADMIN_USERNAME` and `ADMIN_PASSWORD` are not set. Because the script must be run with a running server, this means running it without setting those env vars will silently authenticate as `admin`:`admin123` — the same default password that `index.ts` explicitly warns is dangerous. If an operator follows copy-paste docs and the server is still running with the default password, the script succeeds and the credentials appear in shell history.

**Code:**
```typescript
// packages/server/src/scripts/full-import.ts:29-36
async function login(): Promise<string> {
  const resp = await fetch(`${SERVER_URL}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      username: process.env.ADMIN_USERNAME || 'admin',
      password: process.env.ADMIN_PASSWORD || 'admin123',  // ← hardcoded fallback
    }),
  });
```

**Exploit:**
An operator running `npx tsx src/scripts/full-import.ts` without setting `ADMIN_PASSWORD` (e.g., on a dev box that still uses the default password) will silently authenticate with the insecure default. The plaintext default password also appears in `ps aux` output on Linux since Node passes `argv` values. This is a low-bar entry point if the server is accidentally exposed.

**Fix:**
Remove both fallbacks. If either env var is missing, print an error and `process.exit(1)`. Add a `/* required */` comment: `const username = process.env.ADMIN_USERNAME; if (!username) { console.error('ADMIN_USERNAME required'); process.exit(1); }`.

---

### [MEDIUM] `tenantExport.collectUploads` does not filter symlinks — symlink targets outside uploads root are silently included

**Where:** `packages/server/src/services/tenantExport.ts:576-615`

**What:**
`collectUploads` iterates the uploads directory with `withFileTypes: true` and branches on `entry.isDirectory()` / `entry.isFile()`. These two predicates are based on `lstat`, so a symlink to a file returns `isFile() = false` and `isDirectory() = false`, meaning it is silently skipped — this is actually safe for the ZIP contents. **However**, on the branch at line 600–601, the function recursively calls `collectUploads(absPath, resolvedBase, ...)` for any entry where `isDirectory()` is true. On Linux, a symlink to a directory passes `isDirectory()` as `false` (lstat-based), but `path.resolve(dir, entry.name)` still resolves to the symlink path. When the recursive call does `fsp.readdir(absPath, { withFileTypes: true })` on a directory symlink, `readdir` follows the symlink and returns the target's contents — those entries' resolved absolute paths may be outside `resolvedBase`, but the ZIP-slip guard checks against the parent `resolvedBase` using `absPath.startsWith(resolvedBase + path.sep)`. If the symlink target directory itself contains files, their `absPath = path.resolve(absPath_of_symlink, entry.name)` may not start with `resolvedBase + sep`, so those are correctly rejected. **The actual risk is:** `entry.isDirectory()` for a symlink-to-directory returns `false` under `withFileTypes` (uses `lstat`), so the recursive branch is never taken for directory symlinks. The `isFile()` branch at line 603 returns `false` for a symlink-to-file, so those are skipped too. In practice no symlink content reaches the ZIP. However, this relies on undocumented/implicit behavior. The code contains no explicit `entry.isSymbolicLink()` guard, no comment, and no test — a future Node.js behavioral change or a platform where `withFileTypes` returns stat-based results (e.g., Windows junction handling) could silently break the assumption.

**Code:**
```typescript
// tenantExport.ts:588-614
for (const entry of entries) {
  const absPath = path.resolve(dir, entry.name);
  // ZIP-slip guard
  if (!absPath.startsWith(resolvedBase + path.sep) && absPath !== resolvedBase) {
    // ... rejected
  }
  if (entry.isDirectory()) {                    // ← lstat-based; symlink-to-dir → false
    await collectUploads(absPath, resolvedBase, zipFiles); // ← recursive
  } else if (entry.isFile()) {                  // ← lstat-based; symlink-to-file → false
    data = await fsp.readFile(absPath);         // ← follows symlink if isFile() were true
    zipFiles.push({ name: `uploads/${rel}`, rawData: data });
  }
  // symlinks: silently skipped — but no explicit guard or comment
}
```

**Exploit:**
Under current Node.js behavior (lstat semantics for `withFileTypes`) symlinks are skipped and no data leaks. The risk is latent: a future change to `withFileTypes` semantics, or an operator adding `{ followSymlinks: true }` to the readdir call, would silently allow a symlink placed inside the uploads directory (by a malicious file upload or a misconfigured storage mount) to exfiltrate `/etc/shadow` or any file readable by the server process into the tenant's encrypted export ZIP.

**Fix:**
Add an explicit `entry.isSymbolicLink()` check and `continue` (or log-and-skip) before the `isDirectory` / `isFile` branches. Document the assumption: `// Symlinks are explicitly rejected — never follow outside the uploads root.` Mirrors the pattern already used in `management.routes.ts:317`.

---

### [LOW] `backup.ts` `fsp.cp` follows symlinks into backup destination if Node.js behavior changes

**Where:** `packages/server/src/services/backup.ts:630-632`

**What:**
The backup routine copies the entire uploads directory with `fsp.cp(config.uploadsPath, uploadsDest, { recursive: true })`. Node.js `fsp.cp` defaults to `dereference: false`, which preserves symlinks as symlinks (does not follow them) — the backup copy is a symlink pointing to the original target, not a copy of its contents. This is currently safe. However, the call has no explicit `dereference: false` option, so the behavior is implicit. If Node.js ever changes the default, or if a developer adds `{ dereference: true }` thinking it "ensures all files are copied", symlinks in the uploads directory would be followed and arbitrary files readable by the server process could land in the backup archive.

**Code:**
```typescript
// backup.ts:630-632
if (fs.existsSync(config.uploadsPath)) {
  await fsp.cp(config.uploadsPath, uploadsDest, { recursive: true });
  // No explicit dereference: false — relies on Node.js default
}
```

**Exploit:**
Requires a symlink already present inside the uploads directory (from a malicious upload or storage misconfiguration). Under current Node defaults the symlink is copied as-is; if `dereference` were true, sensitive system files pointed to by the symlink would be embedded in the backup and potentially exposed to whoever downloads it.

**Fix:**
Pass `{ recursive: true, dereference: false }` explicitly and add a comment: `// dereference: false — do not follow symlinks in uploads (prevents /etc/shadow leakage)`.

---

### [INFO] No archive extraction libraries present — zip-slip via entry filename is not applicable

**Where:** `packages/server/package.json`

**What:**
The server has no dependencies on `unzipper`, `adm-zip`, `yauzl`, `archiver`, `tar`, or any other archive extraction library. All ZIP handling is done by the custom pure-Node `buildZip()` writer in `tenantExport.ts` (write-only, no extraction path), `backup.ts` (SQLite `.backup()` API — no tar/zip), and `receiptOcr.ts` (reads files already on disk, no archive extraction). There is no code path where a user-supplied archive is extracted to disk, so there is no classic zip-slip / tar-slip / symlink-extraction attack surface via entry filename containing `../`.

**Fix:**
No action required. If an extraction flow is added in future, validate every entry name against the target directory using `path.resolve` + `startsWith(targetDir + path.sep)` before writing.

---

### [INFO] CSV formula injection is guarded in all export endpoints — confirmed

**Where:**
- `packages/server/src/routes/reports.routes.ts:1701-1703` — `CSV_FORMULA_TRIGGERS` + `sanitizeCsvCell`
- `packages/server/src/routes/tickets.routes.ts:1787-1791` — `CSV_FORMULA_TRIGGERS` + `escapeCsv` (SCAN-1161)
- `packages/server/src/routes/inventory.routes.ts:1892-1899` — inline `escCsv` with `/^[=+\-@\t\r]/` (SCAN-1161)
- `packages/server/src/routes/team.routes.ts:977-979` — `sanitize()` with `/^[=+\-@\t\r]/` (SCAN-1161)

**What:**
Every CSV export endpoint prefixes cells starting with `=`, `+`, `-`, `@`, TAB, or CR with a single quote before quoting, following the OWASP CSV injection defense. The pattern is consistently applied and code-commented with SCAN-1130/SCAN-1161 references. The `customers /import-csv` and `inventory /import-csv` endpoints accept JSON bodies (not raw CSV files), so there is no parse-time formula injection attack surface on the import side. No `papaparse` or `csv-parse` library is used.

**Fix:**
No action required. Consider extracting the three inline implementations into a shared `sanitizeCsvCell` utility to eliminate drift risk.

---

## SCOPE CLEARED — checklist of what was verified safe

- **Zip-slip via entry filename**: No archive extraction library in `package.json`; the only ZIP code is the pure-Node writer in `tenantExport.ts` which is write-only.
- **Symlink extraction in tenantExport ZIP builder**: `collectUploads` uses `lstat`-based `withFileTypes` — `isFile()` and `isDirectory()` both return `false` for symlinks, so no symlink content reaches the ZIP. Flagged as INFO for explicit guard recommendation.
- **Symlink in backup fsp.cp**: `dereference` defaults to `false`; symlinks are preserved, not followed. Flagged as LOW for explicit option.
- **Zip-bomb / entry count / size**: No extraction path exists, so unbounded entry count/size in a user-supplied archive is not applicable.
- **Tar pax extended headers**: No tar library, no tar extraction.
- **CSV formula injection (export)**: All four CSV export endpoints apply the single-quote prefix guard. Confirmed line citations above.
- **CSV formula injection (import)**: Both `/import-csv` endpoints (`customers`, `inventory`) receive pre-parsed JSON arrays from the client — the CSV file is parsed client-side and the rows POSTed as JSON. No server-side CSV parser processes raw formula cells.
- **receiptOcr path traversal**: `isPathUnder()` in `receiptOcr.ts:49-55` validates `file_path` from DB is under `uploadsPath` using `path.resolve` + `startsWith(base + path.sep)` before any read.
- **RepairDesk/RepairShopr/MyRepairApp import**: All three import services consume external API JSON, not user-supplied archive files. No archive extraction. All DB writes use parameterized SQLite prepared statements. No CSV formula injection path (data stays in DB, not streamed to CSV in these services).
- **dataExportGenerator**: Write-only JSON export. Table names come from `sqlite_master` and are validated with `/^[a-zA-Z_][a-zA-Z0-9_]*$/` before interpolation. No user-controlled strings in filenames.
- **backup.ts restore path**: `resolveBackupPath` checks `filename.includes('..')`, `filename.includes('/')`, `filename.includes('\\')`, and verifies the resolved path stays inside `backupDir`. The HMAC sidecar prevents cross-tenant restore. Integrity check via `PRAGMA integrity_check` runs before the DB file is swapped.
- **tenantTermination**: Operates on DB file rename/move within configured directories; no archive extraction, no CSV, no user-controlled filenames written to disk.
- **Unicode/RTLO in filenames**: No filenames from user input are written to disk in any archive extraction flow (there is no extraction flow). Upload filenames are validated by `fileUploadValidator.ts` before storage.
