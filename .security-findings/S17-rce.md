# S17 — RCE via dynamic exec / eval / child_process / vm / template injection

## Scope

Exhaustive search across `packages/server/src/` for:
- `eval()`, `new Function()`, `Function()`
- `child_process` (`exec`, `execSync`, `spawn`, `spawnSync`, `execFile`, `fork`)
- `vm.Script`, `vm.run`, `vm.compile`
- Dynamic `import()` with non-static arguments
- Dynamic `require()` with non-static arguments
- `setTimeout`/`setInterval` with string arguments
- Template engines: ejs, pug, handlebars, nunjucks, mustache, lodash.template
- `mathjs.evaluate`, `mathjs.compile`
- Shell injection from user input into exec/spawn
- User-controlled cron expressions reaching `cron.schedule()`
- Path injection via user-controlled args to OS binaries

---

### [MEDIUM] `Function()` constructor used as `eval` workaround for dynamic import

**Where:** `packages/server/src/services/receiptOcr.ts:215`

**What:**
`receiptOcr.ts` uses `Function('m', 'return import(m)')` to create a function dynamically — identical in power to `eval()` — to bypass TypeScript's static ESM analysis for a lazy import. While the argument passed today is the hardcoded literal `'tesseract.js'`, the pattern establishes a footgun: the `Function()` constructor can execute arbitrary JavaScript. If a future change makes the module specifier configurable (e.g., read from `store_config` to support "any OCR provider"), the argument becomes attacker-controlled and achieves server-side RCE.

**Code:**
```typescript
// packages/server/src/services/receiptOcr.ts:213-215
let tesseractModule: unknown = null;
try {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  tesseractModule = await (Function('m', 'return import(m)') as (m: string) => Promise<unknown>)('tesseract.js');
```

**Exploit:**
Today there is no direct exploit because the argument is a hardcoded string literal. However, the pattern is semantically equivalent to `eval()` and would become immediately exploitable if the specifier were ever derived from user-controlled or DB-sourced input — any admin could escalate to OS code execution by storing a path to a malicious module. Additionally, this pattern is blocked by strict Content Security Policies and Node.js hardened contexts (`--disallow-code-generation-from-strings`).

**Fix:**
Replace `Function('m', 'return import(m)')` with a standard ESM dynamic import and use `// @ts-ignore` or a conditional shim if the TypeScript ESM type issue is the concern. In ESM builds the idiomatic form is simply `await import('tesseract.js')` — TypeScript tolerates this when the module is declared `declare module 'tesseract.js'` or the import is typed `as any`. The `Function()` wrapper adds zero value once the import target is a literal.

---

### [INFO] `execSync` with hardcoded string at module-load time

**Where:** `packages/server/src/routes/management.routes.ts:347`

**What:**
`execSync('git rev-parse --short=12 HEAD', { ... })` is called once during module initialization (IIFE wrapped in the `GIT_SHA` constant) to obtain the running commit hash. The command is a fully hardcoded string — no user input reaches it — and the output is validated against `/^[a-f0-9]{7,40}$/i` before use.

**Code:**
```typescript
// management.routes.ts:342-355
const GIT_SHA: string = (() => {
  const envSha = process.env.GIT_SHA;
  if (envSha && /^[a-f0-9]{7,40}$/i.test(envSha)) return envSha.slice(0, 12);
  try {
    const cwd = path.resolve(__dirname, '..', '..', '..', '..');
    const out = execSync('git rev-parse --short=12 HEAD', { cwd, stdio: ['ignore', 'pipe', 'ignore'], timeout: 2000, windowsHide: true })
      .toString()
      .trim();
    if (/^[a-f0-9]{7,40}$/i.test(out)) return out;
  } catch { /* git not available or not a git checkout */ }
  return 'unknown';
})();
```

**Exploit:**
No user-controlled input reaches this call. The only theoretical concern is PATH manipulation by a low-privilege system user running the process, which could cause a rogue `git` binary to be found. This is a general process-hardening concern, not a CRM-specific attack surface.

**Fix:**
Prefer the `GIT_SHA` env var path (already implemented as the first check), and inject it at build time via CI so the `execSync` fallback is never needed in production. Alternatively, replace the fallback with `execFile('git', ['rev-parse', '--short=12', 'HEAD'], ...)` (no shell) to eliminate the marginal PATH-injection risk.

---

## SCOPE CLEARED

After 60+ tool calls covering every focus file and all `child_process` / eval-class call sites, the following were verified safe:

- **`child_process` in `backup.ts`**: `execFile('df', ['-B1', '--output=avail', dir], ...)` (Linux) and `execFile('powershell', [..., driveLetter], ...)` (Windows) — both use the array-argv form (no shell). `dir` is validated by `assertSafePath()` which rejects shell metacharacters (`;&|'$\n\r\t\x00<>*?"`). The Windows drive letter is separately validated as `/^[A-Za-z]$/`. `spawnSync('df', ...)` fallback also uses `shell: false`. No injection surface. (`backup.ts:492–530`, `backup.ts:934–953`)

- **`child_process` in `management.routes.ts`**: `execFile('pm2', ['restart', 'bizarre-crm'], ...)` and `execFile('pm2', ['stop', 'bizarre-crm'], ...)` use static argv arrays. `execFile('wmic', ['logicaldisk', 'get', ...], ...)` also uses static args. No user input reaches any argument. (`management.routes.ts:617, 627, 641`)

- **`child_process` in `githubUpdater.ts`**: All `git` calls use `execFile` with an explicit string array argument (`args: string[]`). The `ref` argument used in `git verify-commit` and `git tag --contains` is validated by `isValidSha()` which requires `/^[0-9a-f]{7,40}$/`. Remote URL is compared against a whitelist of three exact strings. No user input reaches any shell expansion. (`githubUpdater.ts:102–115, 159–172, 178–187`)

- **`eval()` / `new Function()`**: Only one use found — the `Function()` constructor in `receiptOcr.ts:215` (documented above). No `eval()` calls exist anywhere in `packages/server/src/`. No `vm.Script`, `vm.runInContext`, `vm.runInNewContext`, or `vm.compile` imports found.

- **`require()` with non-static argument**: None found. All `require()` calls (mainly in test files and one `bcryptjs` dynamic import in `management.routes.ts:177`) use hardcoded string literals.

- **`setTimeout`/`setInterval` with string argument**: Only one hit — `index.ts:240` — which uses `setTimeout(() => resolve('timeout'), ms)` (a callback function, not a string). No string-form timer calls exist.

- **Template engines (ejs, pug, handlebars, nunjucks, mustache, lodash.template, mathjs)**: None imported or used anywhere in `packages/server/src/`. Template interpolation in `automations.ts` and `notifications.ts` uses a custom `interpolate()` function that replaces `{keyword}` placeholders via `.replace(/\{(\w+)\}/g, ...)` with `escapeHtml` or `stripSmsControlChars` depending on output mode — no code is ever evaluated, only string substitution. (`automations.ts:93–106`)

- **Automation rule engine**: Automation actions (`send_sms`, `send_email`, `change_status`, `assign_to`, `add_note`, `create_notification`) are all dispatched by `action_type` string switch. No user-supplied code is compiled or evaluated. Action config is parsed as JSON and values are accessed by key. No expression evaluation engine is involved.

- **SMS auto-responder regex**: User-authored regexes from `rule_json` in `sms_auto_responders` are compiled with `new RegExp(rule.match, flags)` in `smsAutoResponderMatcher.ts:104`. A ReDoS guard at line 97 rejects nested-quantifier patterns (`(…+)+`, `(…*)+`). The matching is done on a body capped at 1600 chars. This is a low-severity ReDoS surface, not RCE.

- **Backup cron schedule**: `admin.routes.ts` validates `schedule` as a string ≤100 chars before saving to `store_config`. `scheduleBackup()` then calls `cron.validate(schedule)` before passing to `cron.schedule()`. Node-cron's `cron.schedule()` is a timer registration function — it cannot execute arbitrary shell code regardless of the expression content. No injection surface.

- **Backup path → `df`**: The admin sets `backup_path` via `PUT /admin/backup-settings`, which rejects values containing `..` or over 500 chars. `runBackup()` reads this path and passes it to `getFreeDiskSpace(dir)`, which calls `assertSafePath(dir)` (rejects shell metacharacters), then passes `dir` as a positional argv element to `execFile('df', ...)`. The path never touches a shell. No injection.

- **Plugin loader**: No plugin loader, dynamic module loader, or `require(variable)` pattern exists in the codebase. All module loading is static or uses hardcoded import specifiers.

- **Import wipe / selectiveWipe table names**: `repairDeskImport.ts` builds `DELETE FROM ${table}` SQL by interpolating table names, but every name is first checked against `ALLOWED_WIPE_TABLES` (a `ReadonlySet<string>`) via `assertValidTableName()`. Any name not in the explicit whitelist throws. No user input reaches the table name argument. (`repairDeskImport.ts:83–87, 2034–2042`)

- **Migration runner**: `migrate.ts` reads `.sql` files from the `db/migrations/` directory (a path resolved at startup relative to `__dirname`). Files are read from disk and passed to `db.exec(sql)`. No user input controls which files are read or their content.

- **`receiptOcr.ts` OCR file path**: The `file_path` read from `expense_receipt_uploads` is validated by `isPathUnder(filePath, uploadsPath)` before any read. No external binary is invoked with this path — only `fs.accessSync()` and the tesseract.js Node library.
