# S14 — Path Traversal: Uploads, Imports, Backups, File Ops

---

### MEDIUM Missing containment check on receipt deletion via DB-stored URL path

**Where:** `packages/server/src/routes/expenseReceipts.routes.ts:336-338` (DELETE handler)

**What:**
The DELETE `/expenses/:id/receipt` route reads `file_path` from the `expense_receipt_uploads` table — stored in URL format (e.g. `/uploads/tenant/receipts/abc.jpg`) — strips the leading `/uploads/` prefix, and then calls `path.join(config.uploadsPath, relPath)` with no subsequent `path.resolve` + `startsWith` containment check. Comparable code in `tickets.routes.ts:2606-2611` and `retentionSweeper.ts:211-216` performs the correct resolve-then-contains guard; this handler does not.

**Code:**
```typescript
// expenseReceipts.routes.ts:336-338
const storedPath = upload?.file_path ?? expense.receipt_image_path ?? '';
const relPath = storedPath.replace(/^\/uploads\//, '');
const diskPath = relPath ? path.join(config.uploadsPath, relPath) : null;
// No path.resolve + startsWith guard here — unlike tickets.routes.ts:2606-2611
if (diskPath) safeUnlink(diskPath);
```

**Exploit:**
If an attacker can corrupt `file_path` in the DB (e.g., via a SQL injection elsewhere or a compromised admin account) to `/uploads/../../../etc/passwd`, then `relPath` becomes `../../../etc/passwd`, `diskPath` resolves to `/etc/passwd`, and `safeUnlink` deletes that file. The impact is arbitrary file deletion on the server's filesystem.

**Fix:**
After building `diskPath`, add: `const resolvedDisk = path.resolve(diskPath); if (!resolvedDisk.startsWith(path.resolve(config.uploadsPath) + path.sep)) throw new AppError('invalid file path', 400);` — matching the pattern already used in `tickets.routes.ts:2605-2611`.

---

### MEDIUM OCR path security check is broken: URL-format `file_path` compared against disk-format `uploadsPath` — always fails, bypass of containment validation

**Where:** `packages/server/src/services/receiptOcr.ts:49-55` (isPathUnder) and `packages/server/src/routes/expenseReceipts.routes.ts:202-205` (file_path storage)

**What:**
`processReceiptOcr` calls `isPathUnder(filePath, uploadsPath)` to validate that the receipt file lives under the uploads root. However `filePath` is the URL-format string stored at upload time — e.g. `/uploads/tenant/receipts/abc.jpg` — while `uploadsPath` is the absolute disk path resolved by config, e.g. `/app/packages/server/uploads`. `path.resolve('/uploads/…')` returns `/uploads/…`, which never starts with `/app/packages/server/uploads`. The check **always returns false** and marks every OCR job as failed with "File path failed security check", making the containment guard a dead code path that never runs on valid data and never catches anything anomalous.

**Code:**
```typescript
// receiptOcr.ts:49-55
function isPathUnder(filePath: string, baseDir: string): boolean {
  const resolved = path.resolve(filePath);
  const base = path.resolve(baseDir);
  return resolved === base || resolved.startsWith(base + path.sep);
}
// filePath = '/uploads/tenant/receipts/abc.jpg' (URL path, not disk path)
// baseDir  = '/app/packages/server/uploads'     (disk path)
// Result: always false → marks upload 'failed'
```

**Exploit:**
The containment guard never validates any real file path; OCR is completely non-functional on all deployments where `config.uploadsPath` is not literally `/uploads`. An operator reading the code believes the security check prevents out-of-root file reads, but it is inoperative. If `tesseract.js` were installed, the `fs.accessSync(filePath, R_OK)` on line 195 would immediately fail with ENOENT (URL path not a real file), causing a controlled failure — but the intended security check provides no protection.

**Fix:**
Store `file_path` as the absolute disk path (e.g. the value of `photoFile.path` from multer, which is already an absolute disk path) instead of the URL-format path. The URL path for HTTP responses can be derived separately. Alternatively, in `processReceiptOcr` reconstruct the absolute disk path from `file_path` the same way the DELETE handler does: strip `/uploads/` prefix and `path.join(config.uploadsPath, relPath)`, then apply the `isPathUnder` check.

---

### LOW Backup destination path not restricted to a safe subdirectory — admin can write DB files anywhere on the filesystem

**Where:** `packages/server/src/routes/admin.routes.ts:613-617` (PUT /admin/backup-settings), `packages/server/src/services/backup.ts:558-614` (runBackup)

**What:**
`PUT /admin/backup-settings` accepts a `path` field and only validates `!path.includes('..')` and `path.length <= 500`. It does not require the path to be within any configured root. `runBackup` then calls `fs.mkdirSync(backupDir, { recursive: true })` on that unconstrained path and writes the SQLite backup directly there. An admin can set `backup_path` to `/`, `/etc`, or any other directory and the server will create directories and write `.db` and `.db.enc` files there. The same key in `ALLOWED_CONFIG_KEYS` (settings.routes.ts:157) is blocked in multi-tenant mode (line 489) but has no specific path validation in `validateConfigValue`.

**Code:**
```typescript
// admin.routes.ts:613-617
if (path !== undefined) {
  if (typeof path !== 'string' || path.includes('..') || path.length > 500) {
    res.status(400).json({ ... message: 'Invalid path' });
    return;
  }
}
// No check that path is within a safe base directory (e.g., config.backupsPath)
```

**Exploit:**
An authenticated admin (single-tenant only; multi-tenant blocks the route at line 333) sends `PUT /admin/backup-settings { "path": "/" }`. On the next backup run, `fs.mkdirSync('/', { recursive: true })` succeeds silently and the DB is written to `/bizarre-crm-<ts>-<rand>.db` at filesystem root, potentially exposing the database on a world-readable mount or conflicting with OS files.

**Fix:**
Validate that the resolved backup path starts with a configured allowed base directory (e.g. `config.dataDir` or a dedicated `config.backupsRootPath`). Add to the `PUT /admin/backup-settings` handler: `const resolved = path.resolve(path); if (!resolved.startsWith(path.resolve(config.dataDir))) { return 400; }`.

---

### INFO HEIC MIME type accepted in `fileFilter` but always rejected by magic-byte validator — functional dead code

**Where:** `packages/server/src/routes/expenseReceipts.routes.ts:48-55` (`ALLOWED_RECEIPT_MIMES`, `ALLOWED_RECEIPT_EXTENSIONS`), `packages/server/src/utils/fileValidation.ts:56-88` (`SIGNATURES`)

**What:**
`ALLOWED_RECEIPT_MIMES` includes `'image/heic'` and multer's `fileFilter` passes files with that MIME type. However `fileValidation.ts`'s `SIGNATURES` array only covers JPEG, PNG, GIF, WebP, and PDF — it has no entry for HEIC (ISO BMFF magic: `00 00 00 XX 66 74 79 70`). Any HEIC file therefore reaches `validateFileMagicBytes` with `declaredMime = 'image/heic'`, matches no signature, and returns `{ valid: false, error: 'Unrecognized file signature (declared image/heic)' }`. The upload is then deleted and a 400 is returned. HEIC files are never accepted regardless of the whitelist.

**Code:**
```typescript
// expenseReceipts.routes.ts:48-55
const ALLOWED_RECEIPT_MIMES = [
  'image/jpeg', 'image/png', 'image/webp',
  'image/heic', // accepted by fileFilter — but always rejected by magic-byte check
] as const;
// fileValidation.ts:56-88 — SIGNATURES has no HEIC entry
```

**Exploit:**
No security exploit: the result is that legitimate HEIC uploads (common from iOS cameras) silently fail with 400 despite appearing to be supported. Users with HEIC screenshots of receipts cannot upload them.

**Fix:**
Either add a HEIC signature to `SIGNATURES` in `fileValidation.ts` (HEIC magic: bytes 4–7 = `0x66 0x74 0x79 0x70` with wildcard bytes 0–3; see ISO 14496-12) and add `'image/heic'` to `allowedMimes`, or remove `'image/heic'` from both `ALLOWED_RECEIPT_MIMES` and `ALLOWED_RECEIPT_EXTENSIONS` to make the whitelist consistent with what the validator actually accepts.

---
