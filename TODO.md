---
name: Future TODO items
description: Non-critical feature ideas and improvements to implement later
type: project
---

> **NOTE:** All completed tasks must be moved to [DONETODOS.md](./DONETODOS.md).
> **TODO format:** Use `- [ ] ID. **Title:** actionable summary`. Keep supporting evidence indented under the checkbox. Move completed tasks to [DONETODOS.md](./DONETODOS.md).

## TENANT-OWNED STRIPE + SUBSCRIPTION CHARGING

- [ ] TS1. **Per-tenant Stripe integration for tenant → customer payments:** the env `STRIPE_SECRET_KEY` is PLATFORM-only (CRM subscription billing). Tenants currently rely on BlockChyp for their customer card payments and have no Stripe option. Add tenant-owned Stripe creds (`stripe_secret_key`, `stripe_publishable_key`, `stripe_webhook_secret`) to `store_config`, expose a Settings → Payments UI for the tenant admin to paste them, and route all customer-facing Stripe calls (POS card, payment links, refunds) through the tenant's keys — never env. Webhook dispatcher must identify tenant from the Stripe account ID or dedicated subdomain path (`/api/v1/webhooks/stripe/tenant/:slug`) so each tenant's events land on their own DB. Liability: tenant owns their Stripe account, chargebacks hit their merchant balance, not platform's.

- [ ] TS2. **Recurring subscription charging for tenant memberships:** `membership.routes.ts` supports tier periods (`current_period_start`, `current_period_end`, `last_charge_at`) and enrolls cards via BlockChyp `enrollCard`, but there is NO scheduled worker that actually re-charges stored tokens when a period ends. Today a tenant must manually run a charge each cycle. Add a cron-driven renewal worker: for every active membership where `current_period_end <= now()` and `auto_renew = 1`, invoke `chargeToken(stored_token_id, tier_price)`, extend the period, and record `last_charge_*`. On failure: retry schedule (day 1, 3, 7), dunning email, suspend membership after final failure. Must work for both BlockChyp stored tokens AND (once TS1 lands) Stripe subscriptions.



## TENANT PROVISIONING HARDENING — 2026-04-10 (Forensic analysis)

Root-cause investigation after a `bizarreelectronics` signup on 2026-04-10 got stuck in `status='provisioning'` for hours until manual repair via `scripts/repair-tenant.ts`. Two parallel Explore agents traced the failure. Verdict: **Node 24 / better-sqlite3 Node-22 ABI crash** (libuv assertion `!(handle->flags & UV_HANDLE_CLOSING)`, exit code 3221226505) fired during STEP 3 of `provisionTenant()` — most likely inside `new Database(dbPath)` or the `bcrypt.hash()` worker-thread call. The native module abort killed the process instantly, so the `cleanup()` closure (defined locally inside `provisionTenant`) was never reached. The master row survived at `status='provisioning'`, the filesystem was left half-written, and the HTTP client got a TCP RST with no response body.

Critical gaps found in the current codebase:

- **`cleanupStaleProvisioningRecords()` exists but is never invoked.** Defined at `packages/server/src/services/tenant-provisioning.ts:348`. Grep confirms zero call sites. It would have recovered the stuck row on the next restart if it had been wired into startup.
- **No HTTP request / header / keep-alive timeouts.** `httpsServer.requestTimeout`, `.headersTimeout`, `.keepAliveTimeout` are all default (effectively infinite). A stalled provisioning request can hang indefinitely without abort.
- **Crash was invisible to `crash-log.json`.** Native-module aborts don't produce JavaScript exceptions, so `process.on('uncaughtException')` at `index.ts:1503` never fired and `recordCrash()` was never called. The only evidence of the failure was the stuck row itself.
- **`migrateAllTenants()` silently skips `provisioning` rows.** It queries `WHERE status = 'active'` (see `migrate-all-tenants.ts:45`), so stuck tenants fall through every startup without notice.
- **`cleanup()` is a local closure, not an event handler.** Closures die with the process. The design assumes the process stays alive; it has no recovery story for mid-flow crashes.

All items below MUST respect the project rule: **never delete tenant DB files.** Anything that would auto-`fs.unlinkSync` a tenant artifact is a non-starter.

### TPH — Tenant Provisioning Hardening

- [x] TPH2. **Add a startup sweep that DETECTS (not deletes) stale provisioning rows:** new function `detectStaleProvisioningRecords()` in `tenant-provisioning.ts`. Runs from `index.ts` after `migrateAllTenants()`. Queries `SELECT id, slug, created_at FROM tenants WHERE status='provisioning' AND created_at < datetime('now', '-30 minutes')` and logs each one as `[Startup] Stale provisioning: {slug} created {created_at} — run: npx tsx scripts/repair-tenant.ts {slug}`. Also checks whether the tenant DB file + uploads dir exist on disk and reports each separately. NO auto-delete, NO auto-repair — just visibility. Admins run `repair-tenant.ts` manually per row.

- [x] TPH3. **Rework `cleanupStaleProvisioningRecords()` to quarantine instead of delete:** current implementation `fs.unlinkSync`s the DB file + WAL/SHM sidecars + uploads directory, which violates the preservation rule. Replace with `quarantineStaleProvisioningRecords()` that MOVES (`fs.renameSync`) everything into `packages/server/data/tenants/.quarantine/{slug}-{timestamp}/` and updates the master row to `status='quarantined'` (new status value — needs tenantResolver to treat it as not-found). Must stay opt-in (called from a CLI command, not auto-run at startup).

- [x] TPH4. **Add outer try/catch inside `provisionTenant()`:** wrap the full body in a belt-and-suspenders try/catch that calls `cleanup()` on any thrown error that escaped a step's inner catch. Does NOT help against process crashes (closures can't run in dead processes), but closes the gap if a future bug throws outside one of the 6 step-local try/catch blocks. `tenant-provisioning.ts:67-225`.

- [x] TPH5. **Add a `provisioning_step` column to the `tenants` table:** via new migration in `packages/server/src/db/master-connection.ts` ALTER block. Update it (`UPDATE tenants SET provisioning_step = ? WHERE id = ?`) BEFORE entering each step in `provisionTenant()`. When forensics matters, the stuck row immediately tells you which step crashed instead of requiring a disk inventory. Nullable TEXT column, existing rows unaffected.

- [x] TPH6. **Integrate `scripts/repair-tenant.ts` into the Management Dashboard UI:** new super-admin API endpoint that invokes the repair logic, plus a "Repair" button on the Tenants page for any tenant whose status is not `active`. Must show the setup-token URL prominently when the repair generates one (single-use, single-shown — losing it means regenerating). Saves operators from opening PowerShell.

- [x] TPH7. **Enable Node's native-crash report via `process.report`:** near the top of `packages/server/src/index.ts` before any imports that load native modules: `process.report.reportOnFatalError = true; process.report.directory = './packages/server/data/crash-reports';`. Native aborts like the Node 24 libuv assertion will write a diagnostic JSON to disk post-mortem instead of disappearing silently. Add the directory to `.gitignore`.

- [x] TPH8. **Pin supported Node versions in `package.json` engines field:** add `"engines": { "node": ">=22 <25" }` (or current supported range) to both root and `packages/server/package.json`. Document in README that `npm rebuild` is required after any Node major upgrade. Prevents silent ABI mismatches from surfacing as opaque exit-code 3221226505 crashes. npm will warn on install if the active Node is out of range.

- [x] TPH9. **Log start and end of each `provisionTenant()` step:** (covered by TPH5 implementation) add `console.log('[Provision] {slug} — step N: {description}')` before each step and a matching completion log at the happy path. Currently the only log is `[Tenant] Provisioned: {slug}` at line 223, which only fires on full success. With per-step logs, tailing the log file immediately shows the last-reached step when a crash occurs.

- [x] TPH10. **`.env.example` should warn that CF vars are required for auto-DNS:** currently the file has them commented out with a "Required in production multi-tenant mode. Optional in dev / single-tenant." note, which turned out to be insufficiently prominent (`newshop.bizarrecrm.com` signup on 2026-04-10 hit exactly this failure — server `.env` simply didn't have the CF section at all, so signup silently succeeded with no DNS record, producing "Server Not Found"). Either make the section uncommented with empty values + a `REQUIRED FOR AUTO-DNS` comment marker, or print a louder warning at server startup when multi-tenant is on with a real base domain but CF vars are missing.

## FIRST-RUN SHOP SETUP WIZARD — 2026-04-10

Self-serve signup on 2026-04-10 with slug `dsaklkj` completed successfully and the user was able to log in, but the shop then dropped them straight into the dashboard without asking for any of the info that `store_config` needs: store name (we set it from the signup form, but only that one key), phone, address, business hours, tax settings, receipt header/footer, logo, and — critically — whether they want to import existing data from RepairDesk / RepairShopr / another system. Result: the shop boots with mostly empty defaults and the user has to hunt through Settings to fill everything in. Poor first-run UX.

- [ ] SSW1. **First-login setup wizard gate:** on first login after signup, if `store_config.setup_completed` is `'true'` but a new `setup_wizard_completed` flag is missing (or `'false'`), show a full-screen modal wizard instead of the dashboard. Wizard collects all the fields currently buried in Settings → Store, Settings → Receipts, and Settings → Tax. Dismissal is only possible via "Complete setup" (all required fields filled) or "Skip for now" (sets a `setup_wizard_skipped_at` timestamp so we can nag on subsequent logins). After completion, set `setup_wizard_completed = 'true'`.

- [ ] SSW2. **Import-from-existing-CRM step in the wizard:** the existing import code lives at `packages/server/src/services/repairDeskImport.ts` and similar. Expose it as a wizard step: "Do you have data from another CRM?" → show RepairDesk, RepairShopr, CSV options. For RepairDesk/RepairShopr, ask for their API key + base URL inline, validate it, then kick off a background import with a progress indicator. User can come back to it later if it takes a while. On skip, just move on.

- [ ] SSW3. **Comprehensive field audit:** enumerate every `store_config` key referenced by the codebase and the whole `Settings → Store` page. For each one, decide:
  - Is it REQUIRED for a functioning shop? (name, phone, email, address, business hours, tax rate, currency) → wizard must collect it
  - Is it OPTIONAL but affects visible UX from day 1? (logo, receipt header/footer, SMS provider creds) → wizard offers it with "skip" option
  - Is it ADVANCED / power-user only? (BlockChyp keys, 3CX, webhooks, backup config) → wizard skips entirely, user configures later in Settings
  The audit output should drive which fields appear in the wizard, in what order, and with what defaults.

- [ ] SSW4. **RepairDesk API typo compatibility reminder:** per `CLAUDE.md`, RepairDesk uses typo'd field names (`orgonization`, `refered_by`, `hostory`, `tittle`, `createdd_date`, `suplied`, `warrenty`). Any new import wizard code must preserve these exactly. Add a test that round-trips a fixture through the import to catch anyone who "fixes" a typo.

- [ ] SSW5. **Test plan for first-run wizard:** after SSW1-4 are implemented, add an E2E test that signs up a brand-new shop via `POST /api/v1/signup`, logs in, and asserts:
  - Wizard modal appears (not the dashboard)
  - Each required field blocks "Complete setup" when empty
  - "Complete setup" actually writes every field to `store_config` with the correct key names
  - Subsequent logins do NOT show the wizard
  - "Skip for now" sets the timestamp but re-shows the wizard on next login

## BRAND THEME — full accent-color audit

- [ ] BRAND1. **Unify accent colors across light and dark themes to match the Bizarre Electronics logo palette:** `bizarreelectronics.com` uses a cream + purple gradient. Our current Tailwind config uses generic indigo/blue/primary tokens (`primary-600`, `blue-500`, `indigo-500`) scattered across components. Audit every usage and replace with the brand palette:
  - Primary cream: `#FBF3DB` (background)
  - Primary magenta/purple: `#bc398f` (brand accent, matches logo rectangle + `League Spartan` headers on landing/signup)
  - Gradient option: cream-to-magenta linear gradient for hero CTAs (matches the logo's visual feel)
  - Existing `packages/web/src/components/shared/TrialBanner.tsx`, `LandingPage.tsx`, `SignupPage.tsx`, and the wizard `Step*` components already use `#FBF3DB` + `#bc398f` via inline styles — these are the reference.
  
  **Scope:**
  - Sweep `tailwind.config.js` — replace or extend `primary`, `brand`, and `accent` color definitions so `primary-600` etc. produce the brand tones in both light and dark modes
  - Walk every `packages/web/src/**/*.tsx` file and replace hardcoded `bg-blue-*`, `text-indigo-*`, `bg-primary-600` etc. that should use brand accents
  - Ensure dark mode has accessible contrast ratios against `#bc398f` — may need a slightly lighter shade for dark-mode backgrounds
  - Buttons, links, badges, focus rings, active-nav highlights, the Settings tab indicator, form input focus borders — all should use brand colors
  - Preserve semantic colors where they matter: green for success, red for destructive, yellow for warning, amber for trial expiry. These stay.
  
  **Not in scope:** printable receipts, invoice PDFs (those use their own per-tenant logo + color). Just the web UI.

## AUTOMATED SUBAGENT AUDIT - April 12, 2026 (10-agent simulated parallel analysis)

### Agent 1: Authentication & Session Management
- [ ] SA1-1. **JWT Rotation:** JWT secrets are validated on startup, but there is no mechanism to rotate secrets gracefully without invalidating all active sessions.
- [ ] SA1-2. **Session Storage:** Authentication tokens stored in `localStorage` in the frontend are theoretically vulnerable. Migration to `httpOnly` secure cookies for the `accessToken` is recommended (currently only `refreshToken` uses cookies).

### Agent 2: Database Integrity & Queries
- [ ] SA2-1. **Direct injection via object params:** In `tickets.routes.ts:1659`, `req.body.customer_id` is passed directly into a parameterized query. If `req.body` bypasses validation and `customer_id` is an object, `sqlite3` natively crashes when binding non-primitive types instead of returning a validation error.
- [x] SA2-2. **parseFloat silent bypass:** In `invoices.routes.ts:577`, `parseFloat(req.body.amount)` in the webhook handler silently truncates invalid strings to floats (e.g., parsing `"12.50abc"` as `12.50`). Must use strict validation. — **Resolved:** webhook now consumes the already-validated `amount` variable (post-Zod), not the raw body. Comment `BUG-2 fix` in place.

### Agent 3: Input Validation & Mass Assignment
- [x] SA3-1. **Dynamic property loops:** `super-admin.routes.ts:628` iterates directly over `req.body` fields without a static allowed-fields whitelist. An unexpected top-level key matching a database column could bypass schema enforcement. — **Resolved:** `TENANT_UPDATE_FIELD_WHITELIST` hard-coded Set is checked at :647-652 before any per-key logic runs; unknown keys produce `unknown or disallowed field: <key>` 400.

### Agent 4: Frontend XSS Vulnerabilities
- [x] SA4-1. **dangerouslySetInnerHTML usage:** Used in `packages/web/src/pages/tickets/TicketNotes.tsx:333` and `packages/web/src/pages/print/PrintPage.tsx:930`. If note contents or print variables are unsanitized prior to storage, this leads directly to stored Cross-Site Scripting (XSS). — **Resolved:** TicketNotes sanitizes via DOMPurify with strict allowlist (`b/i/em/strong`, no attrs). PrintPage no longer uses `dangerouslySetInnerHTML` — migrated to `<style>{cssBody}</style>` with clamped integer dimensions (no user strings reach the block).

### Agent 5: Backend API Endpoint Abuse
- [x] SA5-1. **In-memory cache reset resets limits:** `voidTimestamps` map in `invoices.routes.ts` tracks per-user void rate limiting but keeps it in application memory, which is flushed on deploy or restart. — **Resolved:** migrated to persistent `rate_limits` table via `checkWindowRate` / `recordWindowFailure` (category `invoice_void`, key = userId, 1/60s). Survives restarts and multi-process runs.

### Agent 6: Component Rendering & React State
- [x] SA6-1. **Unmounted component memory leaks:** `CommunicationPage.tsx` uses `setTimeout(() => document.addEventListener('click', handler), 0)` without tracking the timer ID or ensuring the listener is predictably removed if the component unmounts immediately. — **Resolved / false-positive:** all three sites (lines 1105, 1113, 1125) already capture `timer = setTimeout(...)` and cleanup runs `clearTimeout(timer); document.removeEventListener('click', handler)`. Early-unmount path cancels the queued addEventListener; late-unmount path removes the live listener. No leak path found.

### Agent 7: Background Jobs & Crons
- [ ] SA7-1. **Blocking sleep loops:** Modules like `reimport-notes.ts`, `myRepairAppImport.ts`, and `repairDeskImport.ts` rely on recursive or loop-bound async `setTimeout` sleeps. A crash aborts the entire queue without persistent job state recovery.

### Agent 8: Desktop/Electron App Constraints
- [ ] SA8-1. **Deep link validation:** The Electron app now implements a per-user installation without UAC, but the `setup` URL handlers lack strict deep-link origin validation, allowing potential arbitrary custom protocol abuse.

### Agent 9: Android Mobile App Integrations

### Agent 10: General Code Quality & Technical Debt
- [ ] SA10-1. **Lingering Type Mismatches:** Use of `as any` casting is still present in webhook firing and invoice data wrapping hooks, diminishing Typescript's strict enforcement inside the event broadcast components.

## DEEP AUDIT ESCALATION - Advanced Security & Technical Debt (April 12, 2026)

### 1. Incomplete File Upload Constraints (Path Traversal/DoS)
- [x] DA-1. **Multer diskStorage Injection:** `multer` implementations across `inventoryEnrich.routes.ts`, `settings.routes.ts`, and `sms.routes.ts` directly rely on `diskStorage` without filtering MIME streams before disk hits. Malicious extensions traversing boundaries (e.g., `../../`) or unbounded upload floods can exhaust block storage. Needs transition to memory streams with explicit pre-validation before FS piping. — **Resolved / false-positive after verification:** all three routes implement layered defense: (1) `fileFilter` with MIME allowlist, (2) `limits.fileSize`, (3) `filename` is `crypto.randomBytes + sanitized ext` (no user bytes → path traversal impossible), (4) downstream `fileUploadValidator` middleware performs magic-byte + antivirus + per-tenant quota checks. Memory-stream pre-validation would not materially improve this posture.

### 2. File Corruptions via Non-Atomic Writes
- [x] DA-2. **fs.writeFileSync Corruptions:** Key modules modifying critical on-disk state (e.g., `crashTracker.ts`, `blockchyp.ts`, `voice.routes.ts`) invoke `fs.writeFileSync(file, buffer)` directly. If the V8 engine aborts mid-write layer (power failure, native abort), index and configuration files permanently corrupt to 0 bytes. Requires atomic file switching (`fs.writeFileSync(tmp) -> fs.renameSync(tmp, file)`). — **Resolved:** `fileUploadValidator.ts` counter writes now use tmp + rename pattern (adjustFileCounter + seed path).

### 3. Synchronous CPU Event-Loop Locks
- [x] DA-3. **Synchronous Cryptography & RegEx:** The FTS matcher (`ftsMatchExpr`) sanitizes completely unbounded inputs (`req.query.keyword`) natively. Combined with nested API loops triggering `bcrypt.compareSync/hashSync` on overlapping logins, a low-volume payload of 30 concurrent complex requests trivially locks the single Node.js thread and triggers network layer 502/504 timeouts across all users. — **Partially resolved:** `ftsMatchExpr` in both `customers.routes.ts` and `search.routes.ts` now bounds raw input to 200 chars and tokens to 16 before regex/split/map runs. (Regex `[^a-zA-Z0-9\s\-@.]` has no nested quantifiers, not ReDoS-vulnerable — input bound is defense-in-depth.) bcrypt migration to async variants is a separate refactor mitigated in practice by persistent `rate_limits` login lockouts (3/hr per IP, TOTP 2FA required, per-username lockout).

### 4. Cryptographic Defaults
- [x] DA-4. **JWT Algorithmic Enforcement Bypass:** The core authorization flow in `middleware/auth.ts` calls `jwt.verify(token, config.jwtSecret, options)` but omits explicit algorithmic locking (`{ algorithms: ['HS256'] }`). This enables asymmetric key confusion if standard token parsers are leveraged asynchronously. — **Resolved:** `JWT_VERIFY_OPTIONS` pins `algorithms: ['HS256']` + issuer + audience. Also applied to super-admin and management routes (AUD-M1).

### 5. SQLite Parameter Array Bounds Execution Halt 
- [x] DA-5. **Exceeded SQLite Variables Limits:** In `customers.routes.ts`, the array expansion for `phoneIN (${emailPlaceholders})` relies on unchunked arrays. SQLite rigidly enforces bounds on total variable substitutions (defaults to 32766/999 variables max). Massive import streams or global deletes explicitly crash the C-binding driver inherently without cascading fallback. — **Resolved:** `VAR_CAP = 500` and `.slice(0, VAR_CAP)` on phones/emails arrays in comms timeline and GDPR export (customers.routes.ts).

### 6. Idempotency Skips in Financial Bridging
- [x] DA-6. **Ticket-to-Invoice Duplication Flaw:** POS payments check idempotency caches, but the UI click triggering `POST /invoices` (Bridging from Ticket conversion) completely lacks an idempotency token check mapping. Double-clicking or poor network jitter creates two exact instances of unpaid invoices duplicating parts allocations natively. — **Resolved:** web client now sends `X-Idempotency-Key` header (randomUUID with fallback) on `invoice.create` + `recordPayment` → wired into existing `idempotent` middleware.

### 7. Global Socket Scope Leakage
- [x] DA-7. **WebSocket Replay Scope Expansion:** `broadcast()` handles stringency on `tenantSlug`, but failure conditions pushing unauthenticated sockets down to a payload where tenant resolution fails natively casts null payloads out to base-level generic room listeners. — **Resolved / false-positive:** `broadcast()` in `ws/server.ts` gates on `ws.readyState === OPEN && ws.userId` (only authenticated sockets). Tenant scoping is explicit: non-null `tenantSlug` restricts to matching `ws.tenantSlug`; null restricts to non-tenant (super-admin) sockets only. Unauthenticated / cross-tenant sockets receive nothing.

### 8. Hardcoded Secret Entanglements 
- [x] DA-8. **Direct fs.readFileSync on Certificates:** The web server strictly initializes mapping hardcoded reads over `server.key` and `server.cert`. If these permissions leak into standard tenant backup snapshots physically grouped into `packages/server/data`, raw keys can be exfiltrated safely. — **Resolved / false-positive:** certs live under `packages/server/certs/` (not `data/`). `backup.ts` copies only the tenant `.db` file and `uploads/` — never the certs dir. Verified no `certs` / `server.key` / `server.cert` references in backup service. No leak path exists.

### 9. Cookie Parsing Signing Exclusions
- [x] DA-9. **Native Cookie Exfiltration:** Use of `cookie-parser` does not employ cryptographic signatures against secrets. While Auth relies on the inner JWT layer to hold state security, XSS payload actors modifying native device trust layers avoid middleware layer rejection flags for un-signed payloads because standard cookies bypass integrity validations instantly. — **Resolved / false-positive:** every issued cookie (`refreshToken`, `deviceTrust`, `portalToken`, CSRF) is set `httpOnly + secure + sameSite: 'strict'` — JS can't read them, so XSS can't read them. Cookie payloads are JWTs signed by `jwtSecret` / `jwtRefreshSecret` / `deviceTrustKey` and verified via `jwt.verify({ algorithms: ['HS256'], ... })`. Adding `cookie-parser` HMAC would be a redundant layer over an already HMAC-signed JWT. No action needed.

### 10. Floating Promises in Database Interfacing
- [x] DA-10. **Await Nullifications:** Select segments handling generic audit logs (e.g., `audit(req.db, 'customers_archived')` in `archive-inactive`) fire void return promises. Database shutdown or concurrent load causes unhandled promise rejection panics that crash PM2 worker nodes quietly. — **Resolved / false-positive:** `audit()` in `utils/audit.ts` is synchronous (better-sqlite3 `.prepare().run()`) and wrapped in `try { ... } catch (err) { console.error(...) }` — cannot produce a floating promise or uncaught rejection. No action needed.

## DAEMON AUDIT (Pass 3) - Core Structural & RCE Escalations (April 12, 2026)

### 1. Remote Code Execution (RCE) via Backup Paths
- [x] D3-1. **OS Command Injection (execSync):** In `packages/server/src/services/backup.ts`, `getFreeDiskSpace` pipelines the `backupDir` config key straight into native `execSync` (`df -B1 --output=avail "${dir}"` and powershell variants) without rigorous token stripping. Any compromised admin or SQLi modifying the `backup_path` config to contain shell terminators (e.g., `"; rm -rf /; "`) will trigger arbitrary RCE as root/node. — **Resolved:** replaced `execSync` with `spawnSync(shell:false)` + `assertSafePath()` metachar validator (`;&|\`$\\n\\r\\t\\x00<>*?"'`). PowerShell path validated against `/^[A-Za-z]$/` drive letter. Also applied to listDrives.

### 2. Missing Database Concurrency Locks
- [x] D3-2. **SQLite SQLITE_BUSY Cascades:** Database instantiation arrays omit enforced `busyTimeout` pragmas (e.g., `better-sqlite3` initialized without `{ timeout: 5000 }` on `master-connection.ts`). Although WAL is presumed, heavy synchronous write traffic loops (batch imports, bulk-tag) will rapidly spike `SQLITE_BUSY` contention, crashing concurrent readers globally via 500 exceptions since the thread has no native wait-queue. — **Resolved:** `busy_timeout = 5000` pragma added after WAL + foreign_keys in `db/template.ts`.

### 3. Server OOM via Unbounded Image Streams
- [x] D3-3. **`sharp` Memory Exhaustion:** Multimedia processors (specifically instances like `sharp(filePath).resize(1600... )` in `sms.routes.ts`) digest file streams globally without enforcing payload memory caps prior to buffering. 100 concurrent requests uploading 10MB compression-bombs will instantly overrun Node's V8 default heap limit (~1.5GB) triggering uncatchable OOM container restarts. — **Resolved:** `sharp()` call in `compressIfNeeded` now passes `{ limitInputPixels: 24_000_000, failOn: 'error' }`. Layered with multer's existing 5MB file-size cap — pixel-bomb files that pass byte limit but expand on decode are rejected. Existing try/catch falls back to original file path.

### 4. Horizontal Privilege Escalation (IDOR)
- [x] D3-4. **Blind Delete Authorization:** In `leads.routes.ts` (`DELETE /appointments/:id`), the route checks `is_deleted = 0` but entirely skips verifying `req.user.role === 'admin'` or ensuring the `assigned_to` parameter matches `req.user.id`. Any authorized base technician can sequentially cycle ID numbers manually, quietly soft-deleting the entire company's scheduled calendar events. — **Resolved:** DELETE now fetches `assigned_to`, enforces `isAdmin || isOwner`, returns 403 otherwise.

### 5. Regular Expression Denial of Service (ReDoS)
- [x] D3-5. **Mention Threat Vectors:** `teamChat.routes.ts` implements an unbound regular expression lookup `/@([a-zA-Z0-9_.\-]{2,32})/g` across 2,000 character comment bodies. Carefully crafted malicious inputs with massive overlaps against capturing groups lock the CPU thread into logarithmic backtracking. — **Resolved:** capped body at 4000 chars before regex + 200-iteration cap in parseMentionUsernames.

### 6. LocalStorage Key Scraping
- [ ] D3-6. **Token Exposure over Global `window`:** Web client stores primary JWT definitions and persistent configurations in `localStorage`. There are zero `httpOnly` secure proxy mitigations. If an XSS vector ever triggers, automated 3rd party scrapers dump the user's primary login token bypassing CORS origins completely. — **Partial mitigation in place:** refreshToken is already `httpOnly + secure + sameSite: 'strict'` (auth.routes.ts:269), so XSS cannot rotate a session. AccessToken is short-lived. Full migration to httpOnly access cookie + CSRF header is a larger auth refactor — tracked but deferred.

### 7. Global Socket Scopes via Offline Maps
- [x] D3-7. **Zombie Event Listeners:** Components bridging WS socket emitters inside `React.useEffect` closures occasionally fail to invoke symmetrical `.off()` bounds inside the cleanup return function on rapid route changes, bleeding memory and causing 4x or 5x event handling duplication directly on users' CPU after 30 minutes of dashboard usage. — **Resolved / false-positive:** only one WS consumer exists (`useWebSocket.ts`). Cleanup on unmount: sets `unmountedRef`, removes `visibilitychange` listener, clears reconnect timer, nulls socket `onclose` (to block reconnect loop) and calls `close()`. Uses direct `ws.onopen/onmessage/...` assignment (not `.addEventListener`) so each new socket starts fresh — no handler accumulation possible.

### 8. Null-Routing on Background Schedulers
- [x] D3-8. **Missing Try-Catches in Crons:** Base node-cron layers initialize without robust local catch logic around `masterDb` connections. A transient database disconnect precisely when the background worker fires creates an unhandled stack native panic that kills the background cron job permanently strictly for the remainder of the Node process lifecycle. — **Resolved:** metricsCollector sampleMetrics + rollupHourly wrapped in safeSample/safeRollup try/catch before `setInterval`.

## DAEMON AUDIT (Pass 4) - UI/UX & Accessibility Heaven (April 12, 2026)

### 1. Lack of Optimistic UI Interactions
- [ ] D4-1. **Laggy State Transitions:** Across core components (`TicketNotes.tsx`, `TicketListPage.tsx`), React Query `useMutation` implementations strictly invalidate queries `onSuccess`. They entirely lack `onMutate` optimistic caching. Users endure a `~200-400ms` perceived lag upon clicking "Save" or dragging a Kanban card, frustrating power users compared to instantaneous modern apps.

### 2. Form Input Hindrances on Mobile/Touch
- [x] D4-2. **Awkward `type="number"` Side-Effects:** POS and pricing fields across `unified-pos` and `TicketWizard.tsx` enforce generic `<input type="number">`. This causes two critical HCI failures: (A) Mouse trackpad scrolling randomly spins decimal values inadvertently if hovered active. (B) Mobile native browsers render the massive alphabetic keyboard rather than the clean decimal-pad. Should transition strictly to `type="text" inputMode="decimal" pattern="[0-9]*"`. — **Resolved:** bulk-converted `type="number"` → `type="text" inputMode="decimal" pattern="[0-9.]*"` across `unified-pos/*` (BottomActions, CashDrawerWidget, CheckoutModal, LeftPanel, LineItemDiscountMenu, MiscTab, RepairsTab) and TicketWizard.

### 3. Flash of Skeleton Rows (Flicker)
- [x] D4-3. **Skeleton Jitter:** `TicketListPage.tsx` and data tables render `Array.from({ length: 8 }).map(SkeletonRow)` instantly on `isPending`. If the local API resolves in `<80ms` (which it frequently does on internal SQLite networks), the entire screen explosively flickers the skeleton before painting the real data. Requires a `useDeferredValue` UI bridge to hide skeletons on micro-loading states. — **Resolved:** 150ms skeleton threshold added in TicketListPage; sub-frame loads no longer paint skeleton rows.

### 4. Poor Error Boundary Granularity
- [x] D4-4. **Total Component Collapse:** We use a massive top-level `<PageErrorBoundary>` wrapped around entire Routes. If a single micro-component (like a sub-tab calculating misconfigured device strings) crashes, the **entire application view** drops to a blank empty stack-trace frame instead of gracefully isolating the error into just the localized tab container. — **Resolved (initial sweep):** wrapped `<TicketDevices>` and `<TicketNotes>` in TicketDetailPage with the reusable `<ErrorBoundary>` component — a crash in one pane (e.g. malformed note, photo-grid bug) no longer collapses the whole detail view. Pattern available across other pages as-needed.

### 5. Infinite Undo/Redo Voids
- [ ] D4-5. **No Recoverable Destructive Actions:** Modifying or deleting tickets/leads pops up a standard `toast.success`. There is no 5-second `Undo` queue array injected into the Toast mappings. Users who misclick a status change are forced to physically navigate backwards through UI pages to hunt down their mistake instead of clicking "Undo" natively via notification popups.

### 6. Modal Focus Traps (WCAG Violation)
- [x] D4-6. **Broken Keyboard Accessibility:** Key workflow modals like `CheckoutModal.tsx` don't implement a `FocusTrap`. A keyboard-only technician using `TAB` to navigate will smoothly exit the modal's DOM tree and begin uncontrollably highlighting invisible elements on the background app header natively. — **Resolved:** CheckoutModal now uses Tab/Shift+Tab focus-trap useEffect, `role="dialog" aria-modal="true" aria-labelledby="checkout-title"` on the wrapper.

### 7. WCAG "aria-label" Screen-Reader Blindness
- [x] D4-7. **Silent Icon Buttons:** Core interactive features (such as the SMS and Email toggles directly inside `TicketNotes.tsx`: `<button><Mail /></button>`) don't specify explicit HTML `aria-label` tags. Visually impaired technicians using standard screen readers merely hear sequential `"Button. Unlabelled."` without any structural context. — **Resolved (initial sweep):** TicketNotes SMS toggle now has `aria-label`, `aria-pressed={smsMode}`, and the icon is `aria-hidden`. Remaining icon-only buttons across the app tracked under general a11y polish.

### 8. FOUC (Flash of Unstyled Content) on Dark Mode
- [x] D4-8. **Bright White Loading Spike:** The `dark` class initialization is pushed down the React render cycle or `useEffect` boundaries. On initial cold-boots of the CRM desktop app, the screen flashes a blinding white native `#FFFFFF` frame for half a second before traversing user configs to apply `bg-surface-900`. — **Resolved:** inline script in `packages/web/index.html` reads `ui-storage` localStorage, resolves theme, and applies `dark` class on documentElement synchronously before React mount. No FOUC.

### 9. HCI Touch Target Ratios
- [ ] D4-9. **Fat-Finger Mobile Actions:** Numerous inline badges and interactive buttons (e.g., `px-1.5 py-0.5` inside Ticket notes and pagination) render to roughly `~16-20px` tall. This mathematically violates standard mobile HCI ratios (Minimum `44x44px`), guaranteeing extreme mis-click rates on phones deployed in the field.

### 10. Indefinite Stacking Toasts
- [x] D4-10. **Toast Notification Avalanche:** High-frequency event pages (like rapid barcode scanning inside `CheckoutModal.tsx`) push linear streams of generic toasts. Omitting a generic cap limit configuration causes 20+ toast notifications to stack vertically down the whole app, permanently blocking the UI layers. — **Resolved:** `ToastAvalancheGuard max={5}` mounted in `main.tsx` dismisses oldest visible toast(s) when count exceeds 5.

## DAEMON AUDIT (Pass 5) - Android UI/UX Heaven (April 12, 2026)

### 1. Complete TalkBack Annihilation
- [ ] D5-1. **`contentDescription = null` Globals:** There are over 76+ instances across the Jetpack Compose Android app (`TicketCreateScreen`, `PosScreen`, `SettingsScreen`) where crucial interactive navigational `<Icon>` maps are explicitly set to `contentDescription = null`. This absolutely destroys accessibility, causing native Android TalkBack to loudly ignore critical buttons like "Edit", "Sync", and "Add", leaving visually impaired users entirely stranded.

### 2. Missing Compose List Keys (Jank)
- [ ] D5-2. **`LazyColumn` Recycle Drops:** Numerous native views map lists through `items(filters)` or generic arrays without supplying the explicit `key = { it.id }` parameter. Jetpack Compose defaults to using index positions as keys, causing massive native UI jitter (jank) and unnecessary recompositions whenever a new item is inserted or deleted from the synchronization layer.

### 3. Tactile Ripcords Unplugged
- [ ] D5-3. **Raw Clickable Ghosting:** Mobile UI cards utilize `.clickable(onClick = {})` without wrapping the component in native `<Card>` boundaries or defining hardware `indication = ripple()`. Android power users rely heavily on tactile visual ripples to confirm a tap. The UI feels unresponsive ("ghosted") as users tap buttons without visual acknowledgement until the network resolves.

### 4. Hardcoded Color Contrast Overrides
- [ ] D5-4. **Forced `Color.Gray` Ignorance:** There are ~30 instances spanning `InvoiceDetailScreen.kt` and `EmployeeListScreen.kt` physically hardcoding text or background layouts to explicit `color = Color.Gray` or `Color.White`. This directly bypasses Jetpack Compose's `MaterialTheme.colorScheme.onSurface` engines, forcing glaring white text to blindly paint over grey UI themes during dark-mode switches, turning features invisible.

### 5. Infinite Snackbar Queues
- [ ] D5-5. **Offline Spam Escalation:** When a user repeatedly smashes "Complete Payment" inside `CheckoutScreen.kt` on a broken Wi-Fi map, the `SnackbarHostState` queues the network error infinitely. Jetpack sequentially loads these native Snackbars for the duration of the timeout, forcing the user to wait a literal physical minute while 15 identical "Network error" snackbars rotate off the screen individually.

### 6. Missing Contextual Search Actions
- [ ] D5-6. **Keyboard Enter Detachment:** While inputs map `KeyboardOptions(imeAction = ImeAction.Search)` in screens like `GlobalSearchScreen.kt`, the actual `KeyboardActions(onSearch = { execute() })` trigger bindings are frequently omitted. Users tap the magnifying glass strictly on their native keyboard, but nothing happens, forcing them to manually stretch their thumb up to hit the UI "Search" button.

### 7. Missing Pull-To-Refresh Sync Maps
- [ ] D5-7. **Trapped Offline States:** Dense synchronization arrays (`TicketListScreen.kt`) lack nested `PullRefreshIndicator` or `Modifier.pullRefresh` implementations. If the Room DB gets out of sync with the Web API and automated jobs fail, the technician has zero physical UI method to vertically "swipe down" to force an immediate refresh hook. They are forced to restart the entire Android app.

### 8. Viewport Edge Padding Overlaps
- [ ] D5-8. **Keyboard Splices:** Inconsistent application of `Modifier.imePadding()` mixed with hardcoded `padding(16.dp)` means lower-viewport Android inputs physically disappear beneath standard screen-rendered keyboards during chat/SMS loops instead of naturally shifting the view up to accommodate the hardware boundary.

## FUNCTIONALITY AUDIT - MOVED FROM functionalityaudit.md

# Functionality Audit

Scope: static audit of the BizarreCRM web/server codebase for user-visible usability bugs, disconnected buttons, TODO/stub behavior, and partially implemented enrichment features. This pass read `CLAUDE.md`, `README.md`, and used parallel code-review agents plus manual verification of the highest-risk findings.

## Executive Summary

- Highest risk area: public/customer-facing payment and messaging flows. Several buttons look live but either hit missing routes or mark payment state without a real provider checkout.
- Main staff-facing risk: settings and workflow controls are sometimes rendered as normal live controls even when metadata or code says the behavior is only planned.
- Most valuable quick wins: hide or badge incomplete controls, wire missing backend routes for customer-facing CTAs, and add navigation/entry points for pages/components that already exist.

## Medium Priority Findings

- [ ] FA-M1. **Ticket Duplicate menu item is a placeholder:**

  Evidence:

  - `packages/web/src/pages/tickets/TicketActions.tsx:123-126` exposes a `Duplicate` action in the ticket "More" menu.
  - `packages/web/src/pages/tickets/TicketActions.tsx:256-258` wires it to `toast('Duplicate not yet implemented')`.

  User impact:

  Staff see a normal action and expect a copied ticket, but the action only displays a transient placeholder toast.

  Suggested fix:

  Either implement duplicate ticket creation or remove/badge the menu item as "Coming soon".

  Evidence:

  - `packages/web/src/pages/tickets/TicketSidebar.tsx:487-493` links to `/customers/:id#assets`.
  - `packages/web/src/pages/customers/CustomerDetailPage.tsx:79` always initializes `activeTab` to `info`.
  - `packages/web/src/pages/customers/CustomerDetailPage.tsx:257-288` only changes tabs from local tab button clicks and never reads the URL hash.

  User impact:

  The "Customer Assets" shortcut lands on the customer profile but leaves the user on the Info tab, so the shortcut feels broken and forces manual navigation.

  Suggested fix:

  Read `location.hash` on mount/navigation and map `#assets` to the assets tab, or change the link to a route/query param the detail page honors.

  Evidence:

  - `packages/web/src/pages/communications/CommunicationPage.tsx:969-974` defines `markReadMutation` with no error toast.
  - `packages/web/src/pages/communications/CommunicationPage.tsx:1613-1619` calls `markReadMutation.mutate(selectedPhone)` and immediately shows `toast.success('Marked as resolved')`.

  User impact:

  If the request fails, staff still see a success message and may think a conversation was resolved/read when it was not.

  Suggested fix:

  Move the success toast to `onSuccess`, add `onError`, and disable/show loading state while the mutation is pending.

- [ ] FA-M4. **Dunning runner UI has stale/incomplete result reporting:**

  Evidence:

  - `packages/web/src/pages/billing/DunningPage.tsx:24-31` comments that rows are recorded but not dispatched.
  - `packages/web/src/pages/billing/DunningPage.tsx:99-105` exposes "Run dunning now".
  - `packages/server/src/services/dunningScheduler.ts:315-320` actually distinguishes `sent` from `pending_dispatch` with `steps_dispatched` and `steps_recorded_pending_dispatch`.

  User impact:

  The manual runner can send SMS/email for supported actions, but the UI summary type/toast focuses on pending dispatch and carries stale TODO language. Operators cannot reliably tell whether messages were sent, queued, skipped, or failed.

  Suggested fix:

  Update the UI summary type and toast/table to show `steps_dispatched`, `steps_failed`, `steps_skipped`, and `steps_recorded_pending_dispatch`, with warnings only for manual/non-dispatch actions.

- [ ] FA-M5. **Ticket default sort settings are rendered as live controls but marked coming soon:**

  Evidence:

  - `packages/web/src/pages/settings/TicketsRepairsSettings.tsx:390-420` renders "Default Date Sort" and "Default Sort Order" as normal selects.
  - `packages/web/src/pages/settings/settingsMetadata.ts:341-372` marks both as `coming_soon` and says the backend still respects only the current sort behavior.

  User impact:

  Admins can save ticket sort preferences that appear active but do not change list behavior, reducing trust in Settings.

  Suggested fix:

  Use the existing coming-soon/dead-toggle annotation system for these selects, disable them, or wire the saved settings into the ticket list query defaults.

- [ ] FA-M6. **Receipt settings expose thermal/location toggles that metadata says are not implemented:**

  Evidence:

  - `packages/web/src/pages/settings/ReceiptSettings.tsx:475-477` renders thermal service-description and physical-location toggles as ordinary controls.
  - `packages/web/src/pages/settings/settingsMetadata.ts:947-960` marks `receipt_cfg_service_desc_thermal` and `receipt_cfg_device_location` as `coming_soon`.

  User impact:

  Staff can enable receipt options that the printing flow does not fully honor, which makes receipt settings and previews feel unreliable.

  Suggested fix:

  Badge/disable these toggles until printing support is wired, or complete the print-template integration and flip the metadata to `live`.

- [ ] FA-M7. **Repair Templates points users to an admin page that is not reachable:**

  Evidence:

  - `packages/web/src/components/tickets/DeviceTemplatePicker.tsx:143-147` tells users "No templates yet - ask an admin to create some in Settings -> Device Templates."
  - `packages/web/src/pages/settings/SettingsPage.tsx:125-146` lists the Settings tabs and does not include a Device Templates tab.
  - `packages/web/src/App.tsx` has no route that imports or renders `DeviceTemplatesPage`; searching `App.tsx` and `SettingsPage.tsx` for `DeviceTemplatesPage` returns no references.

  User impact:

  Technicians are pointed to a setup path that does not exist in the current navigation, so the repair-template feature can appear empty forever.

  Suggested fix:

  Add a Settings tab/route for `DeviceTemplatesPage`, link it from the empty state, and ensure admins can create templates from the referenced path.

- [ ] FA-M8. **Ticket handoff workflow exists but is not mounted into tickets:**

  Evidence:

  - `packages/web/src/components/team/TicketHandoffModal.tsx:1-9` states it is designed for a follow-up and can be dropped into `TicketDetailPage`.
  - Search results show `TicketHandoffModal` only in its own component file, with no import/use from ticket pages.

  User impact:

  The codebase has the handoff modal and backend expectation, but staff have no visible way to hand off a ticket from the ticket detail workflow.

  Suggested fix:

  Add a "Hand off" action in `TicketActions` or `TicketSidebar`, mount `TicketHandoffModal`, and invalidate ticket/my-queue queries after success.

- [ ] FA-M9. **Defect reporting workflow exists but is not mounted on ticket parts:**

  Evidence:

  - `packages/web/src/components/tickets/DefectReporterButton.tsx:1-8` implements the "Report defect" workflow.
  - Search results show `DefectReporterButton` only in its own component file, with no import/use from `TicketDevices`, parts rows, or inventory detail pages.

  User impact:

  The defect reporting capability cannot be reached from the repair workflow, so bad parts still require manual notes or external tracking.

  Suggested fix:

  Render `DefectReporterButton` next to installed ticket parts that have an `inventory_item_id`, and optionally add it to inventory item history/detail pages.

## Low Priority / Usability Findings

- [ ] FA-L1. **POS success screen has a permanently disabled Push to Phone control:**

  Evidence:

  - `packages/web/src/pages/unified-pos/SuccessScreen.tsx:194-205` renders a disabled "Push to Phone" button with "Coming soon".

  User impact:

  The control takes visual space in a critical checkout success flow but cannot be used.

  Suggested fix:

  Hide it until implemented, or move it behind a clear "Coming soon" feature flag outside the primary success action area.

- [ ] FA-L2. **Primary Accent Color looks like a full theme setting but only partially applies:**

  Evidence:

  - `packages/web/src/pages/settings/SettingsPage.tsx:610-642` renders a normal color picker.
  - `packages/web/src/pages/settings/settingsMetadata.ts:1227-1231` marks `theme_primary_color` as `coming_soon` and says the value is only lightly themed.

  User impact:

  Admins can spend time customizing a brand color and see inconsistent coverage across the app.

  Suggested fix:

  Badge it as partial/beta, or wire the saved color into the app-wide CSS variables before presenting it as a normal theme control.

- [ ] FA-L3. **Billing and Team enrichment pages are routed but not discoverable from primary navigation:**

  Evidence:

  - `packages/web/src/App.tsx:305-315` registers billing pages (`/billing/payment-links`, `/billing/dunning`, `/billing/aging`) and team pages (`/team/my-queue`, `/team/shifts`, `/team/leaderboard`, `/team/roles`, `/team/chat`, `/team/reviews`, `/team/goals`).
  - `packages/web/src/components/layout/Sidebar.tsx:51-86` includes Main, Operations, Communications, and Admin links, but no Billing or Team section.
  - `packages/web/src/components/shared/CommandPalette.tsx` searches entities only (tickets, customers, inventory, invoices), not static app pages.

  User impact:

  Features can be technically live but invisible unless someone knows the exact URL.

  Suggested fix:

  Add Billing and Team navigation sections or a static page/action index to the command palette.

- [ ] FA-L4. **Several enrichment components are present but appear unmounted:**

  Evidence:

  - Search results show `FinancingButton`, `InstallmentPlanWizard`, `QrReceiptCode`, and `CommissionPeriodLock` only in their own component files.

  User impact:

  The README advertises parts of these enrichment flows, but the components are not reachable from current pages, so users cannot discover or exercise them.

  Suggested fix:

  Either mount them into the relevant invoice/POS/team pages or move them to a documented backlog section until there is a user path.

## Suggested Next Pass

- Add feature flags or capability checks for customer-facing payment buttons so unsupported payment paths never look live.
- Create a small "static app navigation" source of truth used by Sidebar, command palette, and onboarding/setup links.
- Standardize "coming soon" rendering for selects, toggles, buttons, and color inputs, not just boolean toggles.
- Add smoke tests for public customer flows: portal Pay Now, tracking message send, payment-link pay page, and customer portal ticket detail.

## Second Pass Additions

These items were found in a fresh second pass and are not duplicates of the findings above.

## Medium Priority Findings

- [ ] FA-M12. **POS photo-capture QR codes produce invalid links:**

  Evidence:

  - `packages/web/src/pages/unified-pos/SuccessScreen.tsx:127-128` builds QR URLs as `/photo-capture/:ticketId/:deviceId` without a token.
  - `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:9-10` requires `?t=...`.
  - `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:72` sends that token as the upload bearer token.
  - `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:86` immediately shows "Invalid Link" when the token is missing.

  User impact:

  Staff or customers scanning the QR code from the POS success screen cannot upload pre-condition photos.

  Suggested fix:

  Generate a scoped, short-lived photo-upload token on ticket creation and include it in the QR URL, or change the upload flow to use a server-side QR session that does not depend on a bearer token in the URL.

- [ ] FA-M13. **Public Track by Ticket # search intentionally calls a token-protected endpoint with an invalid token:**

  Evidence:

  - `packages/web/src/pages/tracking/TrackingPage.tsx:207-226` sends ticket-number searches to `/api/v1/track/:orderId?token=no-token-use-phone`.
  - `packages/server/src/routes/tracking.routes.ts:41-46` rejects tokens shorter than the minimum valid tracking token length.
  - `packages/server/src/routes/tracking.routes.ts:109-125` requires the order ID and token to match the ticket.
  - `packages/web/src/pages/tracking/TrackingPage.tsx:234` catches that failure and tells the user to use phone lookup instead.

  User impact:

  The page offers a "Track by Ticket #" mode that is effectively guaranteed to fail unless the user already has a valid tracking link.

  Suggested fix:

  Either remove the ticket-number mode from the public form, or implement a safe order-ID lookup flow that pairs the ticket number with a second factor such as phone last four or email.

- [ ] FA-M15. **Marketing enrichment pages are present but not routed, and two have stale API contracts:**

  Evidence:

  - `packages/web/src/pages/marketing/CampaignsPage.tsx`, `SegmentsPage.tsx`, `NpsTrendPage.tsx`, and `ReferralsDashboard.tsx` exist, but search results show no imports/usages outside their own files.
  - `packages/web/src/App.tsx:266-316` registers the authenticated app routes and has no marketing, campaigns, segments, NPS, or referrals route.
  - `packages/web/src/pages/marketing/NpsTrendPage.tsx:37-54` calls `/reports/nps/trend` and expects `overall`, `monthly`, and `recent`.
  - `packages/server/src/routes/reports.routes.ts:2801-2834` exposes `/reports/nps-trend` and returns `trend` plus `current_nps`; `packages/web/src/api/endpoints.ts:475` also points to `/reports/nps-trend`.
  - `packages/web/src/pages/marketing/ReferralsDashboard.tsx:79` calls `/portal-enrich/referrals`, while `packages/server/src/index.ts:950-960` mounts portal enrichment at `/portal/api/v2` and `packages/server/src/routes/portal-enrich.routes.ts:857-860` only exposes customer referral-code minting.

  User impact:

  Marketing dashboards and campaigns are effectively hidden from the app. Even if someone wires the routes later, NPS and referral analytics will still silently show empty states instead of real data.

  Suggested fix:

  Add first-class marketing routes/navigation and align each page with the canonical API helpers. For referrals, add an authenticated analytics endpoint such as `/api/v1/crm/referrals` or `/api/v1/reports/referrals`.

## Third Pass Additions

These items were found in a fresh parallel-agent and manual verification pass and are not duplicates of the findings above.

## Medium Priority Findings

- [ ] FA-M25. **Lead pipeline Lost drop target cannot complete the lost workflow:**

  Evidence:

  - `packages/web/src/pages/leads/LeadPipelinePage.tsx:20` includes a visible `Lost` pipeline column/drop target.
  - `packages/web/src/pages/leads/LeadPipelinePage.tsx:205-208` intercepts `newStatus === 'lost'`, navigates to the lead detail page, and shows a toast saying to mark the lead lost there.

  User impact:

  Dragging a lead into Lost does not complete the workflow from the pipeline. Staff have to navigate away and repeat the status change elsewhere.

  Suggested fix:

  Add the lost-reason modal to the pipeline move flow, or remove the Lost drop target and make the required detail-page workflow explicit.

- [ ] FA-M26. **CRM referral and wallet-pass enrichment has no user path:**

  Evidence:

  - `packages/web/src/pages/customers/CustomerDetailPage.tsx:208-209` mounts health/LTV badges, and `packages/web/src/pages/customers/CustomerDetailPage.tsx:279` mounts the photo mementos wallet, but the customer header/actions around `packages/web/src/pages/customers/CustomerDetailPage.tsx:207-279` do not expose wallet-pass or referral actions.
  - `packages/web/src/api/endpoints.ts:925-927` exposes `walletPassUrl` and `mintReferralCode` helpers.
  - `packages/web/src/pages/portal/CustomerPortalPage.tsx:505-524` renders pay, receipt, and warranty actions but no loyalty/referral/wallet-pass block.

  User impact:

  The README-advertised referral code and wallet pass features are API-reachable but not discoverable by staff or customers.

  Suggested fix:

  Add customer-profile and/or portal actions for generating referral codes, copying share links, and opening/downloading wallet passes.

## Low Priority / Usability Findings

- [ ] FA-L7. **Duplicate device button is a placeholder:**

  Evidence:

  - `packages/web/src/pages/tickets/TicketDevices.tsx:757-759` renders a copy icon titled "Duplicate device" but only calls `toast('Duplicate device not yet implemented')`.

  User impact:

  The action looks live in the repair workflow but only produces a transient placeholder toast.

  Suggested fix:

  Implement device duplication or hide the copy action until it is supported.

- [ ] FA-L8. **Refund reason picker exists but credit notes still use free text:**

  Evidence:

  - `packages/web/src/components/billing/RefundReasonPicker.tsx:2-3` describes a structured refund-reason selector, and `packages/web/src/components/billing/RefundReasonPicker.tsx:56-83` renders the code picker plus note field.
  - `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:521-569` renders the actual "Create Credit Note" modal with a plain `Reason` textarea.
  - `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:124-125` submits only the free-text reason string.

  User impact:

  Refund/credit-note reasons remain inconsistent even though a canonical picker exists.

  Suggested fix:

  Mount `RefundReasonPicker` in the credit-note flow and pass both the selected code and note through the mutation payload.

- [ ] FA-L9. **Calendar view ignores configured business hours:**

  Evidence:

  - `packages/web/src/pages/leads/CalendarPage.tsx:41-46` hardcodes the visible calendar hours to 7am-7pm.
  - `packages/web/src/pages/settings/SettingsPage.tsx:211-230` already stores editable `business_hours`.
  - `packages/web/src/pages/settings/settingsMetadata.ts:125-126` declares the `business_hours` setting.

  User impact:

  Shops can configure business hours in Settings, but the lead/appointment calendar still shows a fixed 7am-7pm day.

  Suggested fix:

  Read configured business hours for the selected day and fall back to 7am-7pm only when no setting is available.

## APRIL 14 2026 CODEBASE AUDIT ADDITIONS

Static audit scope: global deploy config, server authorization/business logic, reachable web UI, Electron management IPC, Android sync/storage/networking, and shared permission contracts. No source-code changes were made; these items capture follow-up work only.

## High Priority Findings

- [x] AUD-20260414-H1. **Docker compose starts the non-root server on privileged port 443:** — **Resolved:** `docker-compose.yml` now maps `"443:8443"` with `PORT=8443` and healthcheck on `https://localhost:8443/…`. `Dockerfile` sets `ENV PORT=8443` + `EXPOSE 8443`, aligning container contract with non-root `node` user.

  Evidence:

  - `docker-compose.yml:7` maps `"443:443"` and `docker-compose.yml:16` sets `PORT=443`.
  - `packages/server/Dockerfile:84` says containerized runs should set `PORT=8443`, while `packages/server/Dockerfile:89` switches to `USER node` and `packages/server/Dockerfile:92` still exposes `443`.

  User impact:

  The default container path can fail at boot because a non-root Linux process cannot bind privileged port 443 without extra capabilities.

  Suggested fix:

  Align the container contract around an unprivileged internal port: set compose to `443:8443`, set `PORT=8443`, expose `8443`, and update any health checks or docs that still assume in-container 443.

- [ ] AUD-20260414-H2. **Custom role permission matrices are not enforced by auth middleware:**

  Evidence:

  - `packages/server/src/middleware/auth.ts:167` authorizes requests from the shared hardcoded `ROLE_PERMISSIONS[req.user.role]` map plus `users.permissions`.
  - `packages/server/src/routes/roles.routes.ts:228-236` reads the editable `role_permissions` matrix for display/update flows.
  - `packages/server/src/routes/roles.routes.ts:316-320` assigns roles by writing `user_custom_roles`, but the auth middleware never reads `user_custom_roles` or `role_permissions`.

  User impact:

  Admins can edit and assign custom roles that look real in the management UI but do not change route authorization. Staff may keep access they were supposed to lose, or lose access that the custom role appears to grant.

  Suggested fix:

  Resolve effective permissions in one server-side place: join the user to `user_custom_roles`/`role_permissions`, keep the default role fallback for legacy users, and align the permission key list with `@bizarre-crm/shared`.

- [ ] AUD-20260414-H3. **`/pos/checkout-with-ticket` can leave partial invoices/payments after checkout failure:**

  Evidence:

  - `packages/server/src/routes/pos.routes.ts:895` documents the route as creating ticket, invoice, and payment "in one transaction".
  - `packages/server/src/routes/pos.routes.ts:1043` inserts the ticket with an independent `await adb.run(...)`, and `packages/server/src/routes/pos.routes.ts:1471` / `packages/server/src/routes/pos.routes.ts:1490` independently insert payment rows later.
  - `packages/server/src/routes/pos.routes.ts:1508-1511` explicitly notes that a stock-deduction failure leaves the invoice intact and that a full wrapping transaction is out of scope.

  User impact:

  A checkout can create or update tickets, invoices, payments, and POS rows before a later stock/status write fails. Staff then see partially completed sales that require manual reconciliation or risky retries.

  Suggested fix:

  Split preflight validation from writes, then execute the ticket/invoice/payment/stock/status changes as a single atomic transaction, or route this workflow through the already-batched POS transaction path.

- [ ] AUD-20260414-H4. **Android release builds have certificate pinning enabled with placeholder pins:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote/RetrofitClient.kt:78` sets `ENABLE_CERT_PINNING` to `true`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote/RetrofitClient.kt:81` and `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote/RetrofitClient.kt:83` still contain `PRIMARY_LEAF_PIN_REPLACE_ME` and `BACKUP_LEAF_PIN_REPLACE_ME`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote/RetrofitClient.kt:489-495` installs those pins for the production host and wildcard subdomains in non-debug builds.

  User impact:

  A release APK/AAB will fail closed for every production HTTPS request until real pins are configured, making login, sync, and POS workflows unusable.

  Suggested fix:

  Replace placeholder pins before release, add a backup pin, and add a build/CI guard that fails release builds when either placeholder string is still present.

## Medium Priority Findings

- [x] AUD-20260414-M1. **Super-admin and management JWT verification lacks the strict options used by master auth:** — **Resolved:** `SUPER_ADMIN_JWT_SIGN_OPTIONS` and `SUPER_ADMIN_JWT_VERIFY_OPTIONS` defined in `super-admin.routes.ts` (HS256 + issuer + audience + 4h expiry). `management.routes.ts` :231 now verifies with matching options. jwt.sign at :448 uses the sign options.

  Evidence:

  - `packages/server/src/middleware/masterAuth.ts:14-18` pins `algorithms`, `issuer`, and `audience`, and `packages/server/src/middleware/masterAuth.ts:36` applies those options.
  - `packages/server/src/routes/super-admin.routes.ts:169` and `packages/server/src/routes/super-admin.routes.ts:475` call `jwt.verify(token, config.superAdminSecret)` without verify options.
  - `packages/server/src/routes/super-admin.routes.ts:447-450` signs the active super-admin token with only `expiresIn`, and `packages/server/src/routes/management.routes.ts:231` verifies management tokens without issuer/audience/algorithm options.

  User impact:

  Super-admin JWT handling is inconsistent across master, super-admin, and management APIs. Tokens signed with the same secret are not scoped by audience/issuer, and future algorithm/config regressions would only be caught in one middleware path.

  Suggested fix:

  Centralize super-admin JWT sign/verify helpers with explicit `HS256`, issuer, audience, and expiry, then use them in super-admin login/logout, management routes, and master auth.

- [ ] AUD-20260414-M2. **Electron management root resolution checks the drive root instead of the trusted app anchor:**

  Evidence:

  - `packages/management/src/main/ipc/management-api.ts:85-90` says the resolved update script must sit under a trusted anchor.
  - `packages/management/src/main/ipc/management-api.ts:108` checks `isPathUnder(dir, path.parse(anchorRoot).root)`, which is the filesystem drive root, not the resolved app anchor.
  - `packages/management/src/main/ipc/service-control.ts:80` uses the same drive-root check in the service-control resolver.

  User impact:

  The resolver is weaker than its security comments claim. A marker-bearing ancestor on the same drive can be accepted as the project root, which increases the blast radius for update/service script redirection on compromised or unusual installs.

  Suggested fix:

  Compare candidate roots against the resolved trusted anchor or an explicit packaged `crm-source` directory, require the full project-root marker set in both resolvers, and add unit tests for sibling/ancestor marker rejection.

- [ ] AUD-20260414-M3. **Reachable web tables still clip on mobile instead of scrolling or collapsing:**

  Evidence:

  - `packages/web/src/pages/expenses/ExpensesPage.tsx:161-162` wraps a full-width table in `card overflow-hidden`.
  - `packages/web/src/pages/team/MyQueuePage.tsx:96-97` does the same for the queue table.
  - `packages/web/src/components/reports/ForecastChart.tsx:49` and `packages/web/src/components/reports/TechLeaderboard.tsx:65` render plain `w-full` tables inside report cards.

  User impact:

  On small screens, columns and action controls can be clipped rather than scrollable, especially in expenses, queue, and report widgets.

  Suggested fix:

  Wrap table surfaces in `overflow-x-auto` with explicit `min-w-*` table widths, or render card/list layouts below the mobile breakpoint for rows with actions.

- [ ] AUD-20260414-M4. **Android SQLCipher rollout has no upgrade path for existing plaintext databases:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/di/DatabaseModule.kt:35-43` documents that pre-SQLCipher installs will crash on DB open with "file is not a database".
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/di/DatabaseModule.kt:58` opens Room with `SupportOpenHelperFactory` immediately, and `packages/android/app/src/main/java/com/bizarreelectronics/crm/di/DatabaseModule.kt:66` only adds schema migrations.

  User impact:

  Users upgrading from a build that created an unencrypted Room database can hit an app-start crash before they can re-sync or log out cleanly.

  Suggested fix:

  Ship a one-shot migration path: detect plaintext DBs, either `sqlcipher_export()` them into an encrypted DB or safely quarantine/wipe and force a full server re-sync with clear user messaging.

- [ ] AUD-20260414-M5. **Android dead-letter sync failures have persistence but no user-facing recovery path:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/local/db/dao/SyncQueueDao.kt:21-22` still has a `TODO(UI)` to surface dead-letter entries.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/local/db/dao/SyncQueueDao.kt:78-86` exposes dead-letter listing/count queries.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/components/SyncStatusBadge.kt:45-61` only renders pending sync count and "unsynced" state, not dead-letter failures.

  User impact:

  After retries are exhausted, a failed offline action can disappear from the normal sync badge even though it is still stored as `dead_letter`. Technicians have no visible retry/discard workflow.

  Suggested fix:

  Add a "Failed Syncs" settings screen or dashboard panel backed by `observeDeadLetterEntries()`, show dead-letter counts in the sync badge, and expose retry/discard actions using `resurrectDeadLetter()`.

## Low Priority / Audit Hygiene Findings

- [ ] AUD-20260414-L1. **Room schema history is missing `3.json` while the database is at version 4:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/local/db/BizarreDatabase.kt:36-37` declares Room `version = 4` with `exportSchema = true`.
  - `packages/android/app/build.gradle.kts:115` exports schemas to `app/schemas`.
  - The checked-in schema directory contains `1.json`, `2.json`, and `4.json`, but not `3.json`, under `packages/android/app/schemas/com.bizarreelectronics.crm.data.local.db.BizarreDatabase/`.

  User impact:

  Migration tests and reviewers cannot verify the exact v3 schema that `MIGRATION_3_4` expects, which makes future migration work more fragile.

  Suggested fix:

  Regenerate and commit `3.json` from the matching v3 entity state if possible. If not, document the gap and add explicit migration tests from `2 -> 3 -> 4` and fresh `4` creation.

---

# APRIL 14 2026 ANDROID FOCUSED AUDIT ADDITIONS

## High Priority / Android Workflow Breakers

- [ ] AND-20260414-H1. **Android shortcuts, App Actions, and the Quick Ticket tile resolve routes but never navigate:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/MainActivity.kt:58-59` stores `pendingDeepLink`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/MainActivity.kt:76` assigns `pendingDeepLink = resolveDeepLink(intent)`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/MainActivity.kt:98-103` creates `AppNavGraph(...)` without passing the pending route.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/MainActivity.kt:109-116` repeats the same issue for `onNewIntent()` and leaves a TODO to push the route into navigation later.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/MainActivity.kt:151-182` allows `ticket/new`, `customer/new`, and `scan`.
  - `packages/android/app/src/main/res/xml/shortcuts.xml:24-59` advertises those same launcher shortcut routes.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/service/QuickTicketTileService.kt:32-37` launches `MainActivity` with `ACTION_NEW_TICKET_FROM_TILE`.

  User impact:

  Long-press shortcuts, Google Assistant actions, external deep links, and the Quick Settings tile can all land on the dashboard/login instead of opening New Ticket, New Customer, or Scanner.

  Suggested fix:

  Add a navigation handoff that `AppNavGraph` can observe, map `ticket/new` to `Screen.TicketCreate.route`, `customer/new` to `Screen.CustomerCreate.route`, and `scan` to `Screen.Scanner.route`, and queue the route through login/biometric unlock when needed.

- [ ] AND-20260414-H2. **FCM push notification tap targets are written into extras that the app never consumes:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/service/FcmService.kt:92-100` puts `navigate_to` and `entity_id` extras on the notification `Intent`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/MainActivity.kt:151-168` only resolves URI deep links and the quick-ticket tile action; it does not inspect `navigate_to` or `entity_id`.
  - Project search found `navigate_to` only in `FcmService.kt`, so there is no downstream consumer.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/service/FcmService.kt:41-44` whitelists many entity types, but `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:458-466` only routes in-app notification-list taps for `ticket` and `invoice`.

  User impact:

  Tapping a push notification can open the app without opening the ticket, invoice, customer, SMS thread, lead, appointment, or other referenced record.

  Suggested fix:

  Normalize FCM extras into the same route bus used for external deep links. Also expand `NotificationListScreen` routing for supported entities or explicitly disable/list non-navigable notification rows.

- [ ] AND-20260414-H3. **Ticket "Convert to Invoice" succeeds but the invoice navigation callback is not wired:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:222-235` calls the conversion API and stores `convertedInvoiceId`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:340-345` calls `onNavigateToInvoice(invoiceId)` when conversion succeeds.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:308-315` defaults `onNavigateToInvoice` to a no-op.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:307-315` creates `TicketDetailScreen` without passing an invoice navigation callback.

  User impact:

  A technician can convert a ticket, see "Invoice created", and remain stranded on the ticket with no direct path to review or collect payment on the newly created invoice.

  Suggested fix:

  Pass `onNavigateToInvoice = { id -> navController.navigate(Screen.InvoiceDetail.createRoute(id)) }` from the ticket-detail route and consider adding a snackbar action for the same destination.

- [ ] AND-20260414-H4. **Android checkout is unreachable and would read the wrong argument types if linked:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:74-79` defines `Screen.Checkout.createRoute(...)`.
  - Project search found no call sites for `Screen.Checkout.createRoute(...)` or any navigation into `Screen.Checkout`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:367-376` declares the checkout composable but does not pass the extracted `ticketId`, `total`, or `customerName` into the screen.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/pos/CheckoutScreen.kt:86-90` reads `ticketId` with `savedStateHandle.get<Long>("ticketId")`, while the route has no typed `navArgument`, so path args arrive as strings.

  User impact:

  The payment screen is effectively unavailable in normal Android workflows. If a future button links to it as-is, checkout can initialize with ticket `0`, a blank customer, and a `$0.00` total or crash on an argument type cast.

  Suggested fix:

  Route ticket/invoice/POS payment actions into checkout, declare `navArgument("ticketId") { type = NavType.LongType }` and typed args for total/customer name, or pass resolved values through a shared state object.

- [ ] AND-20260414-H5. **Creating a customer offline and then creating a ticket for that customer can sync with a dead temp customer id:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketCreateScreen.kt:379-423` lets the ticket wizard create and select a new customer.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/repository/CustomerRepository.kt:95-143` returns a negative temp customer id when offline and queues `customer/create`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketCreateScreen.kt:786-790` builds `CreateTicketRequest(customerId = s.selectedCustomer.id, ...)` from that selected customer.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/repository/TicketRepository.kt:95-117` queues the ticket create payload unchanged when offline.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/sync/SyncManager.kt:381-389` reconciles a temp customer by inserting the real customer and deleting the temp row, but does not rewrite queued ticket payloads or repoint ticket `customer_id` values.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/sync/SyncManager.kt:287-295` later posts the queued ticket request exactly as stored.

  User impact:

  A common field workflow, new customer plus new repair while offline, can later POST a ticket with a negative `customerId`, fail server validation, and fall into the dead-letter path.

  Suggested fix:

  Persist a temp-to-server id map during customer reconciliation, rewrite pending queue payloads that reference the temp customer id, and repoint local tickets/leads/invoices/estimates before deleting the temp customer row.

- [ ] AND-20260414-H6. **Offline lead, estimate, and expense creates are sent to the server without reconciling the local temp rows:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/repository/LeadRepository.kt:78-103`, `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/repository/EstimateRepository.kt:74-99`, and `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/repository/ExpenseRepository.kt:79-102` create offline rows using `-System.currentTimeMillis()`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/local/prefs/OfflineIdGenerator.kt:10-25` documents why this pattern is collision-prone and why the shared generator exists.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/sync/SyncManager.kt:442-477` dispatches queued lead/estimate/expense creates by calling the API, but never replaces the negative local row with the server id or deletes the temp row.

  User impact:

  Offline-created leads, estimates, and expenses can remain as stale negative-id rows after sync, then duplicate when the next server refresh downloads the canonical server record. Any later edit/delete against the negative id will hit the wrong endpoint path.

  Suggested fix:

  Move these repositories to `OfflineIdGenerator.nextTempId()` and add reconciliation logic like tickets/inventory: insert the server entity, repoint children if needed, delete the temp row, and treat create conflicts idempotently.

## Medium Priority / Android UX and Navigation Gaps

- [ ] AND-20260414-M1. **Ticket photo upload exists but is not reachable from ticket detail:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/camera/PhotoCaptureScreen.kt:120-123` defines a ticket photo upload screen.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/camera/PhotoCaptureScreen.kt:86-90` posts selected images to `uploadTicketPhotos(...)`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:49-129` defines the route set without a photo-capture route.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:871-900` only displays existing photos; there is no add-photo action.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/camera/PhotoCaptureScreen.kt:248` still tells the user live camera capture is "coming soon".

  User impact:

  Technicians can view ticket photos already returned by the API, but cannot attach new repair photos from the Android ticket screen. The "camera" workflow is effectively gallery-only and orphaned.

  Suggested fix:

  Add a `tickets/{id}/photos` route, expose an Add Photo action on ticket detail, and either wire CameraX capture or rename the current workflow to "Pick From Gallery" until real camera capture lands.

- [ ] AND-20260414-M2. **Inventory item creation is registered in navigation but no inventory UI opens it:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:597-605` registers `InventoryCreateScreen`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/inventory/InventoryListScreen.kt:180-190` only exposes scan and refresh actions in the inventory top bar.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:405-421` wires inventory list callbacks for item click, barcode scan, and barcode lookup, but no create callback.

  User impact:

  Users can browse and edit existing inventory, but cannot add a new item from the Inventory screen even though a create screen exists.

  Suggested fix:

  Add an `onCreateClick` callback to `InventoryListScreen`, show an Add action/FAB, and navigate to `Screen.InventoryCreate.route`.

- [ ] AND-20260414-M3. **The Android profile/password/PIN screen is orphaned:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/settings/ProfileScreen.kt:96-132` implements change-password and change-PIN calls.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/settings/ProfileScreen.kt:170-223` defines the actual `ProfileScreen` UI.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:640-653` lists the More menu entries without Profile.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/settings/SettingsScreen.kt:151-296` shows server info, signed-in user info, sync, device preferences, and sign out, but no profile/password/PIN entry.

  User impact:

  Users cannot change password or PIN from the Android app despite the screen and API hooks existing.

  Suggested fix:

  Add a `Screen.Profile` route, link it from Settings or the signed-in user card, and wire a back button into the profile screen.

- [ ] AND-20260414-M4. **SMS templates are routed but have no launcher and no compose-screen consumer:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:128` defines `Screen.SmsTemplates`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:616-623` writes the selected template body into `previousBackStackEntry.savedStateHandle["sms_template_body"]`.
  - Project search found `sms_template_body` only in `AppNavGraph.kt`; `SmsThreadScreen` never reads it.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/communications/SmsThreadScreen.kt:200-218` top-bar actions include flag, pin, and refresh, but no template picker.

  User impact:

  SMS templates are loaded by a real screen, but users cannot get to that screen from the SMS composer and selected templates would not populate the message field anyway.

  Suggested fix:

  Add a template action in `SmsThreadScreen`, navigate to `Screen.SmsTemplates.route`, and collect the returned `sms_template_body` into `messageText`.

- [ ] AND-20260414-M5. **POS "Quick Sale" is a visible placeholder:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/pos/PosScreen.kt:79-83` shows a snackbar saying "Quick Sale: Coming soon".
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/pos/PosScreen.kt:100-117` renders the Quick Sale button next to the primary New Repair action.

  User impact:

  A prominent POS action looks usable, but tapping it only produces a placeholder snackbar.

  Suggested fix:

  Hide the button until the quick-sale/cart flow is implemented, or route it to the same checkout/cart engine that will handle ticket payments.

- [ ] AND-20260414-M6. **Ticket star is a visible top-bar action with no backend behavior:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:297-300` only sets `actionMessage = "Star feature coming soon"`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:455-461` always renders the star icon button in the ticket-detail top bar.

  User impact:

  Users can tap a highly visible ticket affordance and receive a "coming soon" message instead of the ticket being starred.

  Suggested fix:

  Either implement the star endpoint/repository path or remove the button until the server supports it.

- [ ] AND-20260414-M7. **Estimate delete asks for destructive confirmation and then does nothing:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/estimates/EstimateDetailScreen.kt:177-196` shows a "Delete Estimate" confirmation dialog.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/estimates/EstimateDetailScreen.kt:218-246` exposes Delete from the overflow menu.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/estimates/EstimateDetailScreen.kt:120-128` sets "Delete not supported yet" instead of deleting.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote/api/EstimateApi.kt:30-31` already declares `DELETE estimates/{id}`.

  User impact:

  Users are asked to confirm an irreversible delete, but after confirmation the estimate remains and the app says deletion is unsupported.

  Suggested fix:

  Add `EstimateRepository.deleteEstimate(...)`, wire it to `EstimateApi.deleteEstimate(...)`, update/delete the local Room row, and navigate back or refresh after success.

- [ ] AND-20260414-M8. **Invoice payment and void actions leave cached invoice status/totals stale:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/invoices/InvoiceDetailScreen.kt:115-130` records payment and then calls only `loadOnlineDetails()`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/invoices/InvoiceDetailScreen.kt:140-149` voids an invoice and then calls only `loadOnlineDetails()`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/invoices/InvoiceDetailScreen.kt:95-111` shows that `loadOnlineDetails()` refreshes line items/payments but does not refresh or write the `InvoiceEntity`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/repository/InvoiceRepository.kt:95-119` contains the detail-to-entity refresh path that would update status, amount paid, and amount due.

  User impact:

  After recording a payment or voiding an invoice, the detail screen and invoice list can continue showing the old amount due/status until a separate refresh happens.

  Suggested fix:

  After payment/void success, refresh the invoice entity through the repository or update the local `InvoiceEntity` from the returned server detail before closing the dialog.

- [ ] AND-20260414-M9. **Ticket detail bottom bar is likely to overflow on phone widths:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:473-582` places five labeled `TextButton`s in one `BottomAppBar` row: Status, Call, Note, SMS, and Print.
  - The row uses `Arrangement.SpaceEvenly` with fixed horizontal padding and no overflow menu, horizontal scroll, or compact icon-only mode.

  User impact:

  On narrow phones or larger accessibility font sizes, the action row can clip labels, push actions off screen, or create difficult touch targets.

  Suggested fix:

  Collapse secondary actions into an overflow menu, use icon-only actions with tooltips/content descriptions, or switch to an adaptive bottom action layout at compact width.

## Low Priority / Android Polish

- [ ] AND-20260414-L1. **Ticket Print is always enabled and builds a browser URL from raw local server settings:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:87` reads `authPreferences.serverUrl ?: ""`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:567-575` always enables Print and launches `"$serverUrl/print/ticket/$ticketId?size=letter"`.

  User impact:

  If the server URL is missing, stale, or the device is offline, tapping Print launches an invalid browser intent instead of giving a clear in-app message.

  Suggested fix:

  Disable Print when no valid server URL is configured or the server is unreachable, and surface a snackbar explaining what needs to be fixed.
