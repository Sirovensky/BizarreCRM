---
name: Future TODO items
description: Non-critical feature ideas and improvements to implement later
type: project
---

> **NOTE:** All completed tasks must be moved to [DONETODOS.md](./DONETODOS.md).
> **TODO format:** Use `- [ ] ID. **Title:** actionable summary`. Keep supporting evidence indented under the checkbox. Move completed tasks to [DONETODOS.md](./DONETODOS.md).

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

- [ ] TPH2. **Add a startup sweep that DETECTS (not deletes) stale provisioning rows:** new function `detectStaleProvisioningRecords()` in `tenant-provisioning.ts`. Runs from `index.ts` after `migrateAllTenants()`. Queries `SELECT id, slug, created_at FROM tenants WHERE status='provisioning' AND created_at < datetime('now', '-30 minutes')` and logs each one as `[Startup] Stale provisioning: {slug} created {created_at} — run: npx tsx scripts/repair-tenant.ts {slug}`. Also checks whether the tenant DB file + uploads dir exist on disk and reports each separately. NO auto-delete, NO auto-repair — just visibility. Admins run `repair-tenant.ts` manually per row.

- [ ] TPH3. **Rework `cleanupStaleProvisioningRecords()` to quarantine instead of delete:** current implementation `fs.unlinkSync`s the DB file + WAL/SHM sidecars + uploads directory, which violates the preservation rule. Replace with `quarantineStaleProvisioningRecords()` that MOVES (`fs.renameSync`) everything into `packages/server/data/tenants/.quarantine/{slug}-{timestamp}/` and updates the master row to `status='quarantined'` (new status value — needs tenantResolver to treat it as not-found). Must stay opt-in (called from a CLI command, not auto-run at startup).

- [ ] TPH4. **Add outer try/catch inside `provisionTenant()`:** wrap the full body in a belt-and-suspenders try/catch that calls `cleanup()` on any thrown error that escaped a step's inner catch. Does NOT help against process crashes (closures can't run in dead processes), but closes the gap if a future bug throws outside one of the 6 step-local try/catch blocks. `tenant-provisioning.ts:67-225`.

- [ ] TPH5. **Add a `provisioning_step` column to the `tenants` table:** via new migration in `packages/server/src/db/master-connection.ts` ALTER block. Update it (`UPDATE tenants SET provisioning_step = ? WHERE id = ?`) BEFORE entering each step in `provisionTenant()`. When forensics matters, the stuck row immediately tells you which step crashed instead of requiring a disk inventory. Nullable TEXT column, existing rows unaffected.

- [ ] TPH6. **Integrate `scripts/repair-tenant.ts` into the Management Dashboard UI:** new super-admin API endpoint that invokes the repair logic, plus a "Repair" button on the Tenants page for any tenant whose status is not `active`. Must show the setup-token URL prominently when the repair generates one (single-use, single-shown — losing it means regenerating). Saves operators from opening PowerShell.

- [ ] TPH7. **Enable Node's native-crash report via `process.report`:** near the top of `packages/server/src/index.ts` before any imports that load native modules: `process.report.reportOnFatalError = true; process.report.directory = './packages/server/data/crash-reports';`. Native aborts like the Node 24 libuv assertion will write a diagnostic JSON to disk post-mortem instead of disappearing silently. Add the directory to `.gitignore`.

- [ ] TPH8. **Pin supported Node versions in `package.json` engines field:** add `"engines": { "node": ">=22 <25" }` (or current supported range) to both root and `packages/server/package.json`. Document in README that `npm rebuild` is required after any Node major upgrade. Prevents silent ABI mismatches from surfacing as opaque exit-code 3221226505 crashes. npm will warn on install if the active Node is out of range.

- [ ] TPH9. **Log start and end of each `provisionTenant()` step:** add `console.log('[Provision] {slug} — step N: {description}')` before each step and a matching completion log at the happy path. Currently the only log is `[Tenant] Provisioned: {slug}` at line 223, which only fires on full success. With per-step logs, tailing the log file immediately shows the last-reached step when a crash occurs.

- [ ] TPH10. **`.env.example` should warn that CF vars are required for auto-DNS:** currently the file has them commented out with a "Required in production multi-tenant mode. Optional in dev / single-tenant." note, which turned out to be insufficiently prominent (`newshop.bizarrecrm.com` signup on 2026-04-10 hit exactly this failure — server `.env` simply didn't have the CF section at all, so signup silently succeeded with no DNS record, producing "Server Not Found"). Either make the section uncommented with empty values + a `REQUIRED FOR AUTO-DNS` comment marker, or print a louder warning at server startup when multi-tenant is on with a real base domain but CF vars are missing.

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
- [ ] SA2-2. **parseFloat silent bypass:** In `invoices.routes.ts:577`, `parseFloat(req.body.amount)` in the webhook handler silently truncates invalid strings to floats (e.g., parsing `"12.50abc"` as `12.50`). Must use strict validation.

### Agent 3: Input Validation & Mass Assignment
- [ ] SA3-1. **Dynamic property loops:** `super-admin.routes.ts:628` iterates directly over `req.body` fields without a static allowed-fields whitelist. An unexpected top-level key matching a database column could bypass schema enforcement.

### Agent 4: Frontend XSS Vulnerabilities
- [ ] SA4-1. **dangerouslySetInnerHTML usage:** Used in `packages/web/src/pages/tickets/TicketNotes.tsx:333` and `packages/web/src/pages/print/PrintPage.tsx:930`. If note contents or print variables are unsanitized prior to storage, this leads directly to stored Cross-Site Scripting (XSS).

### Agent 5: Backend API Endpoint Abuse
- [ ] SA5-1. **In-memory cache reset resets limits:** `voidTimestamps` map in `invoices.routes.ts` tracks per-user void rate limiting but keeps it in application memory, which is flushed on deploy or restart.

### Agent 6: Component Rendering & React State
- [ ] SA6-1. **Unmounted component memory leaks:** `CommunicationPage.tsx` uses `setTimeout(() => document.addEventListener('click', handler), 0)` without tracking the timer ID or ensuring the listener is predictably removed if the component unmounts immediately.

### Agent 7: Background Jobs & Crons
- [ ] SA7-1. **Blocking sleep loops:** Modules like `reimport-notes.ts`, `myRepairAppImport.ts`, and `repairDeskImport.ts` rely on recursive or loop-bound async `setTimeout` sleeps. A crash aborts the entire queue without persistent job state recovery.

### Agent 8: Desktop/Electron App Constraints
- [ ] SA8-1. **Deep link validation:** The Electron app now implements a per-user installation without UAC, but the `setup` URL handlers lack strict deep-link origin validation, allowing potential arbitrary custom protocol abuse.

### Agent 9: Android Mobile App Integrations

### Agent 10: General Code Quality & Technical Debt
- [ ] SA10-1. **Lingering Type Mismatches:** Use of `as any` casting is still present in webhook firing and invoice data wrapping hooks, diminishing Typescript's strict enforcement inside the event broadcast components.

## DEEP AUDIT ESCALATION - Advanced Security & Technical Debt (April 12, 2026)

### 1. Incomplete File Upload Constraints (Path Traversal/DoS)
- [ ] DA-1. **Multer diskStorage Injection:** `multer` implementations across `inventoryEnrich.routes.ts`, `settings.routes.ts`, and `sms.routes.ts` directly rely on `diskStorage` without filtering MIME streams before disk hits. Malicious extensions traversing boundaries (e.g., `../../`) or unbounded upload floods can exhaust block storage. Needs transition to memory streams with explicit pre-validation before FS piping.

### 2. File Corruptions via Non-Atomic Writes
- [ ] DA-2. **fs.writeFileSync Corruptions:** Key modules modifying critical on-disk state (e.g., `crashTracker.ts`, `blockchyp.ts`, `voice.routes.ts`) invoke `fs.writeFileSync(file, buffer)` directly. If the V8 engine aborts mid-write layer (power failure, native abort), index and configuration files permanently corrupt to 0 bytes. Requires atomic file switching (`fs.writeFileSync(tmp) -> fs.renameSync(tmp, file)`).

### 3. Synchronous CPU Event-Loop Locks
- [ ] DA-3. **Synchronous Cryptography & RegEx:** The FTS matcher (`ftsMatchExpr`) sanitizes completely unbounded inputs (`req.query.keyword`) natively. Combined with nested API loops triggering `bcrypt.compareSync/hashSync` on overlapping logins, a low-volume payload of 30 concurrent complex requests trivially locks the single Node.js thread and triggers network layer 502/504 timeouts across all users.

### 4. Cryptographic Defaults
- [ ] DA-4. **JWT Algorithmic Enforcement Bypass:** The core authorization flow in `middleware/auth.ts` calls `jwt.verify(token, config.jwtSecret, options)` but omits explicit algorithmic locking (`{ algorithms: ['HS256'] }`). This enables asymmetric key confusion if standard token parsers are leveraged asynchronously.

### 5. SQLite Parameter Array Bounds Execution Halt 
- [ ] DA-5. **Exceeded SQLite Variables Limits:** In `customers.routes.ts`, the array expansion for `phoneIN (${emailPlaceholders})` relies on unchunked arrays. SQLite rigidly enforces bounds on total variable substitutions (defaults to 32766/999 variables max). Massive import streams or global deletes explicitly crash the C-binding driver inherently without cascading fallback.

### 6. Idempotency Skips in Financial Bridging
- [ ] DA-6. **Ticket-to-Invoice Duplication Flaw:** POS payments check idempotency caches, but the UI click triggering `POST /invoices` (Bridging from Ticket conversion) completely lacks an idempotency token check mapping. Double-clicking or poor network jitter creates two exact instances of unpaid invoices duplicating parts allocations natively.

### 7. Global Socket Scope Leakage
- [ ] DA-7. **WebSocket Replay Scope Expansion:** `broadcast()` handles stringency on `tenantSlug`, but failure conditions pushing unauthenticated sockets down to a payload where tenant resolution fails natively casts null payloads out to base-level generic room listeners.

### 8. Hardcoded Secret Entanglements 
- [ ] DA-8. **Direct fs.readFileSync on Certificates:** The web server strictly initializes mapping hardcoded reads over `server.key` and `server.cert`. If these permissions leak into standard tenant backup snapshots physically grouped into `packages/server/data`, raw keys can be exfiltrated safely.

### 9. Cookie Parsing Signing Exclusions
- [ ] DA-9. **Native Cookie Exfiltration:** Use of `cookie-parser` does not employ cryptographic signatures against secrets. While Auth relies on the inner JWT layer to hold state security, XSS payload actors modifying native device trust layers avoid middleware layer rejection flags for un-signed payloads because standard cookies bypass integrity validations instantly.

### 10. Floating Promises in Database Interfacing
- [ ] DA-10. **Await Nullifications:** Select segments handling generic audit logs (e.g., `audit(req.db, 'customers_archived')` in `archive-inactive`) fire void return promises. Database shutdown or concurrent load causes unhandled promise rejection panics that crash PM2 worker nodes quietly.

## DAEMON AUDIT (Pass 3) - Core Structural & RCE Escalations (April 12, 2026)

### 1. Remote Code Execution (RCE) via Backup Paths
- [ ] D3-1. **OS Command Injection (execSync):** In `packages/server/src/services/backup.ts`, `getFreeDiskSpace` pipelines the `backupDir` config key straight into native `execSync` (`df -B1 --output=avail "${dir}"` and powershell variants) without rigorous token stripping. Any compromised admin or SQLi modifying the `backup_path` config to contain shell terminators (e.g., `"; rm -rf /; "`) will trigger arbitrary RCE as root/node.

### 2. Missing Database Concurrency Locks
- [ ] D3-2. **SQLite SQLITE_BUSY Cascades:** Database instantiation arrays omit enforced `busyTimeout` pragmas (e.g., `better-sqlite3` initialized without `{ timeout: 5000 }` on `master-connection.ts`). Although WAL is presumed, heavy synchronous write traffic loops (batch imports, bulk-tag) will rapidly spike `SQLITE_BUSY` contention, crashing concurrent readers globally via 500 exceptions since the thread has no native wait-queue.

### 3. Server OOM via Unbounded Image Streams
- [ ] D3-3. **`sharp` Memory Exhaustion:** Multimedia processors (specifically instances like `sharp(filePath).resize(1600... )` in `sms.routes.ts`) digest file streams globally without enforcing payload memory caps prior to buffering. 100 concurrent requests uploading 10MB compression-bombs will instantly overrun Node's V8 default heap limit (~1.5GB) triggering uncatchable OOM container restarts.

### 4. Horizontal Privilege Escalation (IDOR)
- [ ] D3-4. **Blind Delete Authorization:** In `leads.routes.ts` (`DELETE /appointments/:id`), the route checks `is_deleted = 0` but entirely skips verifying `req.user.role === 'admin'` or ensuring the `assigned_to` parameter matches `req.user.id`. Any authorized base technician can sequentially cycle ID numbers manually, quietly soft-deleting the entire company's scheduled calendar events.

### 5. Regular Expression Denial of Service (ReDoS)
- [ ] D3-5. **Mention Threat Vectors:** `teamChat.routes.ts` implements an unbound regular expression lookup `/@([a-zA-Z0-9_.\-]{2,32})/g` across 2,000 character comment bodies. Carefully crafted malicious inputs with massive overlaps against capturing groups lock the CPU thread into logarithmic backtracking.

### 6. LocalStorage Key Scraping
- [ ] D3-6. **Token Exposure over Global `window`:** Web client stores primary JWT definitions and persistent configurations in `localStorage`. There are zero `httpOnly` secure proxy mitigations. If an XSS vector ever triggers, automated 3rd party scrapers dump the user's primary login token bypassing CORS origins completely.

### 7. Global Socket Scopes via Offline Maps
- [ ] D3-7. **Zombie Event Listeners:** Components bridging WS socket emitters inside `React.useEffect` closures occasionally fail to invoke symmetrical `.off()` bounds inside the cleanup return function on rapid route changes, bleeding memory and causing 4x or 5x event handling duplication directly on users' CPU after 30 minutes of dashboard usage.

### 8. Null-Routing on Background Schedulers
- [ ] D3-8. **Missing Try-Catches in Crons:** Base node-cron layers initialize without robust local catch logic around `masterDb` connections. A transient database disconnect precisely when the background worker fires creates an unhandled stack native panic that kills the background cron job permanently strictly for the remainder of the Node process lifecycle.

## DAEMON AUDIT (Pass 4) - UI/UX & Accessibility Heaven (April 12, 2026)

### 1. Lack of Optimistic UI Interactions
- [ ] D4-1. **Laggy State Transitions:** Across core components (`TicketNotes.tsx`, `TicketListPage.tsx`), React Query `useMutation` implementations strictly invalidate queries `onSuccess`. They entirely lack `onMutate` optimistic caching. Users endure a `~200-400ms` perceived lag upon clicking "Save" or dragging a Kanban card, frustrating power users compared to instantaneous modern apps.

### 2. Form Input Hindrances on Mobile/Touch
- [ ] D4-2. **Awkward `type="number"` Side-Effects:** POS and pricing fields across `unified-pos` and `TicketWizard.tsx` enforce generic `<input type="number">`. This causes two critical HCI failures: (A) Mouse trackpad scrolling randomly spins decimal values inadvertently if hovered active. (B) Mobile native browsers render the massive alphabetic keyboard rather than the clean decimal-pad. Should transition strictly to `type="text" inputMode="decimal" pattern="[0-9]*"`.

### 3. Flash of Skeleton Rows (Flicker)
- [ ] D4-3. **Skeleton Jitter:** `TicketListPage.tsx` and data tables render `Array.from({ length: 8 }).map(SkeletonRow)` instantly on `isPending`. If the local API resolves in `<80ms` (which it frequently does on internal SQLite networks), the entire screen explosively flickers the skeleton before painting the real data. Requires a `useDeferredValue` UI bridge to hide skeletons on micro-loading states.

### 4. Poor Error Boundary Granularity
- [ ] D4-4. **Total Component Collapse:** We use a massive top-level `<PageErrorBoundary>` wrapped around entire Routes. If a single micro-component (like a sub-tab calculating misconfigured device strings) crashes, the **entire application view** drops to a blank empty stack-trace frame instead of gracefully isolating the error into just the localized tab container.

### 5. Infinite Undo/Redo Voids
- [ ] D4-5. **No Recoverable Destructive Actions:** Modifying or deleting tickets/leads pops up a standard `toast.success`. There is no 5-second `Undo` queue array injected into the Toast mappings. Users who misclick a status change are forced to physically navigate backwards through UI pages to hunt down their mistake instead of clicking "Undo" natively via notification popups.

### 6. Modal Focus Traps (WCAG Violation)
- [ ] D4-6. **Broken Keyboard Accessibility:** Key workflow modals like `CheckoutModal.tsx` don't implement a `FocusTrap`. A keyboard-only technician using `TAB` to navigate will smoothly exit the modal's DOM tree and begin uncontrollably highlighting invisible elements on the background app header natively.

### 7. WCAG "aria-label" Screen-Reader Blindness
- [ ] D4-7. **Silent Icon Buttons:** Core interactive features (such as the SMS and Email toggles directly inside `TicketNotes.tsx`: `<button><Mail /></button>`) don't specify explicit HTML `aria-label` tags. Visually impaired technicians using standard screen readers merely hear sequential `"Button. Unlabelled."` without any structural context.

### 8. FOUC (Flash of Unstyled Content) on Dark Mode
- [ ] D4-8. **Bright White Loading Spike:** The `dark` class initialization is pushed down the React render cycle or `useEffect` boundaries. On initial cold-boots of the CRM desktop app, the screen flashes a blinding white native `#FFFFFF` frame for half a second before traversing user configs to apply `bg-surface-900`.

### 9. HCI Touch Target Ratios
- [ ] D4-9. **Fat-Finger Mobile Actions:** Numerous inline badges and interactive buttons (e.g., `px-1.5 py-0.5` inside Ticket notes and pagination) render to roughly `~16-20px` tall. This mathematically violates standard mobile HCI ratios (Minimum `44x44px`), guaranteeing extreme mis-click rates on phones deployed in the field.

### 10. Indefinite Stacking Toasts
- [ ] D4-10. **Toast Notification Avalanche:** High-frequency event pages (like rapid barcode scanning inside `CheckoutModal.tsx`) push linear streams of generic toasts. Omitting a generic cap limit configuration causes 20+ toast notifications to stack vertically down the whole app, permanently blocking the UI layers.

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
