---
name: Future TODO items
description: Non-critical feature ideas and improvements to implement later
type: project
---

> **NOTE:** All completed tasks must be moved to [DONETODOS.md](./DONETODOS.md).
> **TODO format:** Use `- [ ] ID. **Title:** actionable summary`. Keep supporting evidence indented under the checkbox. Move completed tasks to [DONETODOS.md](./DONETODOS.md).

## NEW 2026-04-16 (from live Android verify)

- [ ] NEW-BIOMETRIC-LOGIN. **Android: biometric re-login from fully logged-out state** — reported by user 2026-04-17. After an explicit logout (or server-side 401/403 on refresh), the login screen asks for username + password even when biometric is enabled. Expectation: if biometric was previously enrolled and the last-logged-in username is remembered, offer a "Unlock with biometric" button on LoginScreen that uses the stored (AES-GCM-encrypted via Android KeyStore) password to submit `/auth/login` automatically on successful biometric. Needs: (1) at enroll time (Settings → Enable Biometric), encrypt `{username, password}` with a KeyStore-backed key requiring biometric auth, persist to EncryptedSharedPreferences; (2) on LoginScreen mount, if biometric enabled + stored creds present, show an "Unlock" button that triggers BiometricPrompt; (3) on prompt success, decrypt creds, call LoginVm.submit() with them; (4) on explicit Log Out, wipe stored creds too. Related fixes shipped same day: AuthInterceptor now preserves tokens across transient refresh failures (commit 4201aa1) + MainActivity biometric gate accepts refresh-only session (commit 05f6e45) — those cover the common "logging out after wifi blip" case. This item covers the true post-logout biometric-login flow.

## DEBUG / SECURITY BYPASSES — must harden or remove before production

## CROSS-PLATFORM

- [ ] CROSS9c-needs-api. **Customer detail addresses card (Android, DEFERRED)** — parent CROSS9 split. Investigated 2026-04-17: there is **no `GET /customers/:id/addresses` endpoint** and the server schema stores a **single** address per customer (`address1, address2, city, state, country, postcode` columns on `customers` — see `packages/server/src/routes/customers.routes.ts:861` INSERT and the `CustomerDto` single-address shape). Rendering a dedicated "Addresses" card with billing + shipping rows therefore requires a server-side schema change first: either split into a separate `customer_addresses(id, customer_id, type, street, city, state, postcode)` table with `type IN ('billing','shipping')`, or promote existing columns to a billing address and add parallel `shipping_*` columns. The CustomerDetail "Contact info" card already renders the single address via `customer.address1 / address2 / city / state / postcode` (see `CustomerDetailScreen.kt:757-779`), which covers the data we actually have today. Leaving deferred until the web app commits to one-vs-two address pattern and the server migration lands.

- [ ] CROSS9d. **Customer detail tags chips (Android)** — parent CROSS9 split. Current Tags card renders the raw comma-separated string; upgrade to proper chip layout once the web tag-chip component pattern is stable.

- [ ] CROSS31-save. **"No pricing configured" manual-price: save-as-default (DEFERRED, schema-shape mismatch with original spec):** confirmed 2026-04-16 — picking a service in the ticket wizard shows "No pricing configured. Enter price manually:" with a Price text field. Option (b) of CROSS31 (save the manual price as a default) was attempted 2026-04-17 but **deferred** because the original task assumed a `repair_services.price` column that **does not exist**. The schema (migration `010_repair_pricing.sql`) stores pricing in `repair_prices(device_model_id, repair_service_id, labor_price)` — a composite key, not a per-service default. Persisting a manual price as "default for this service" therefore requires a `repair_prices` upsert keyed on BOTH the selected device model AND the service (plus a decision on grade/part_price semantics and active flag). Server shape: `POST /api/v1/repair-pricing/prices` with `{ device_model_id, repair_service_id, labor_price }` already exists (see `packages/server/src/routes/repairPricing.routes.ts:171`). Android work needed: (1) add `RepairPricingApi.createPrice` wrapper, (2) add `saveAsDefault: Boolean = false` to wizard state, (3) add Checkbox below the manual-price field, (4) on submit when `saveAsDefault && selectedDevice.id != null && selectedService.id != null`, fire the upsert before `createTicket`. Estimated 45-60 min; out of the 30-min spike budget, so deferring. Options (a) seed baseline prices per category and (c) Settings→Pricing link remain part of first-run shop setup wizard scope.


- [ ] CROSS35-compose-bump. **Android login Cut action performs Copy instead of Cut — root cause is a Compose regression, NOT app code:** reported by user 2026-04-16. Long-press → Cut inside the Username or Password TextField on the Sign In screen copies the selection to the clipboard but does NOT remove it from the field (should do both). Diagnosed 2026-04-17 — `LoginScreen.kt` uses a vanilla `OutlinedTextField` with no custom `TextToolbar`, `LocalTextToolbar`, or `onCut` override (grep on LoginScreen.kt and the entire `app/src/main` tree confirms zero hits for `TextToolbar` / `LocalTextToolbar` / `onCut` / `ClipboardManager` / `LocalClipboardManager`). Compose BOM is already `2025.03.00` per `app/build.gradle.kts:126` — far past the 2024.06.00+ fix for the earlier reported Cut regression — so the original "upgrade BOM" remediation doesn't apply. There's nothing to patch in user code; this is a deeper framework or device-level regression. Next steps: (a) bump BOM to the latest GA when a newer release is available and re-test; (b) if it still repros post-bump, file a Compose issue with a minimal repro and add a TextToolbar wrapper that re-implements cut = copy + clearSelection as a workaround. Deferred with no code change; kept visible in TODO so a future BOM bump can close it out. (Renamed from CROSS35 → CROSS35-compose-bump to make the dependency explicit.)

- [ ] CROSS50. **Android Customer detail: redesign layout to separate viewing from acting (accident-prone Call button):** discussed with user 2026-04-16. Current layout puts a HUGE orange-filled Call button at the top plus an orange tap-to-dial phone number in Contact Info — two paths to accidentally dial the customer. On a VIEW screen the top third is wasted on ACTION buttons. Proposed redesign: **(a)** header: big avatar initial circle + name + quick-stats row (ticket count, LTV, last visit date) — informational only; **(b)** Contact Info card displays phone/email/address/org as DISPLAY ONLY, tap each row → action sheet (Call / SMS / Copy / Open Maps) — deliberate two-tap intent for destructive actions like Call; **(c)** body scrolls through ticket history, notes, invoices (CROSS9 content); **(d)** FAB bottom-right (matching CROSS42 pattern) with speed-dial: Create Ticket (primary), Call, SMS, Create Invoice. Rationale: Call has real-world consequences (phone bill, surprised customer), warrants two-tap intent. FAB puts action at thumb reach without eating prime real estate. Frees top half for customer STATE, not ACTION.


- [ ] CROSS54. **Android Notifications page naming is ambiguous — inbox vs preferences:** confirmed 2026-04-16. More → Settings → Notifications goes to a notification-inbox list screen ("No notifications / You're all caught up"), NOT to notification preferences/settings. Users expect "Notifications" under the SETTINGS section to be preferences (enable push, mute categories, etc.). Two fixes together: (a) rename this list screen to "Activity" or "Alerts" or "Inbox" so Notifications settings is free; (b) add a real Notifications Preferences page in Settings (push enable, categories, quiet hours). Alternately put the Inbox at the TOP of More (not under SETTINGS section) and reserve "Notifications" under SETTINGS for prefs.

- [ ] CROSS55. **Android Notifications list missing filter chips + search + settings gear:** confirmed 2026-04-16. Every other list screen in the app (Customers, Tickets, Inventory, Invoices, Leads, Estimates, Expenses) has a search bar and filter chips at the top. Notifications has neither — just an empty state. Add: (a) search bar ("Search notifications..."), (b) filter chips (All / Unread / Mentions / System), (c) settings-gear icon in top bar routing to notification preferences. Parity matters — users don't want to guess where notification features live.

- [ ] CROSS57. **Web-vs-Android parity audit — surface advanced web features on Android under a "Superuser" (advanced) tab:** 2026-04-16 audit comparing `packages/web/src/pages/` (≈150 files) vs `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/` (39 files). Web has many features missing entirely from Android. User directive: "if too advanced for Android, put under Superuser tab so people know it's advanced". Break into **CORE** (must ship on Android, everyday workflows) and **SUPERUSER** (advanced, acceptable in Settings → Superuser). NOT in scope: customer-facing portal (`portal/*`), landing/signup (`signup/SignupPage`, `landing/LandingPage`), tracking public page, TV display — these are non-admin surfaces that don't belong in the admin app.

  **Consolidation caveat (verified via code read 2026-04-16):** several Android screens roll multiple web pages into one scrollable detail. When auditing parity, check for consolidation before declaring a feature "missing":
  - Android `TicketDetailScreen.kt` (932 lines) has Customer card + Info row + Devices + Notes + Timeline/History + Photos sections inline. This covers web's `TicketSidebar`, `TicketDevices`, `TicketNotes`, `TicketActions` — NOT missing. Only web-exclusive here is `TicketPayments.tsx` (payments likely route through Invoice in Android).
  - Android `InvoiceDetailScreen.kt` (660 lines) has Status + customer + Line items + Totals + Payments sections inline. Covers `InvoiceDetailPage`. Payment dialog is inline.
  - Android `CustomerDetailScreen.kt` (676 lines) renders email, address, organization, tags, notes SECTIONS CONDITIONALLY — only when data is non-empty. I saw only Phone on Testy McTest because email/address/etc. were all blank. CROSS51 was WRONG: the fields DO display when filled. CROSS9 still valid because **no ticket history, no invoice history, no lifetime value** is rendered regardless of data.
  - Android `SmsThreadScreen.kt` (441 lines) is bare conversation UI — genuinely missing every communications-advanced feature (templates inline, scheduled, assign, tags, sentiment, bulk, attachments, canned responses, auto-reply).

  **A. CORE — must add to Android (everyday workflows):**
  - **Unified POS cart/checkout**: `web/unified-pos/*` (14 files). Android currently has POS landing ("Quick Sale: Coming soon" — CROSS14). Needs full cart, product picker, discount, payment, receipt.
  - **Ticket Kanban board**: `web/tickets/KanbanBoard.tsx`. Android parity = alternate view mode on Tickets list (swipe between list/kanban).
  - **Ticket Payments panel**: `web/tickets/TicketPayments.tsx`. Either add a Payments section to TicketDetailScreen or route a "Take payment" action to a new screen.
  - **Communications advanced (genuinely missing on Android)**: in SmsThreadScreen add inline template picker, scheduled-send modal, assign-to-tech, conversation tags, attachment button, canned-response hotkeys; in SmsListScreen add bulk-SMS modal, failed-send retry list, off-hours auto-reply toggle, team-inbox header, sentiment badges.
  - **Lead pipeline (Kanban)**: `leads/LeadPipelinePage.tsx`.
  - **Lead calendar view**: `leads/CalendarPage.tsx`.
  - **Customer LTV/health badges**: `customers/components/HealthScoreBadge.tsx`, `LtvTierBadge.tsx`. Attach to CustomerDetailScreen quick-stats (fits CROSS50 redesign).
  - **Customer photos wallet**: `customers/components/PhotoMementosWallet.tsx`.
  - **Customer ticket/invoice history sections on CustomerDetailScreen**: genuinely missing — add a Tickets section (recent 5 tickets) and Invoices section (recent 5) that tap through to detail screens. Code already has `onNavigateToTicket` callback wired but never renders a list.
  - **Reports tabs**: Web has CustomerAcquisition, DeviceModels, PartsUsage, StalledTickets, TechnicianHours, WarrantyClaims, PartnerReport, TaxReport. Android ReportsScreen has 3 tabs (Dashboard / Sales / Needs Attention — CROSS36). Port the 8 additional report tabs.
  - **SMS templates**: Android HAS SmsTemplatesScreen — verify parity against web `SmsVoiceSettings` (separate audit task).
  - **Photo capture wiring**: Android has `PhotoCaptureScreen` — verify it's wired into TicketDetailScreen photo-add flow and InventoryDetail barcode/photo flow.
  - **Team features**: `team/MyQueuePage` (Android shows "My Queue" card on dashboard but taps "View All" — verify where it lands), `team/ShiftSchedulePage`, `team/TeamChatPage`, `team/TeamLeaderboardPage`. MyQueue + TeamChat highest value on mobile.

  **B. SUPERUSER — put under Settings → Superuser (advanced, power-user):**
  - **Billing & aged receivables**: `billing/AgingReportPage`, `DunningPage`, `PaymentLinksPage`, `CustomerPayPage`, `DepositCollectModal`. Owner/bookkeeper concerns, not day-to-day tech.
  - **Advanced inventory ops**: `AbcAnalysisPage`, `AutoReorderPage`, `BinLocationsPage`, `InventoryAgePage`, `MassLabelPrintPage`, `PurchaseOrdersPage`, `SerialNumbersPage`, `ShrinkagePage`, `StocktakePage`. Ship under Inventory → Advanced or Superuser. Stocktake especially benefits from mobile (barcode + on-floor counting).
  - **Marketing suite**: `marketing/CampaignsPage`, `NpsTrendPage`, `ReferralsDashboard`, `SegmentsPage`. Owner-level, not tech-level.
  - **Team admin**: `team/GoalsPage`, `PerformanceReviewsPage`, `RolesMatrixPage` (permissions matrix). Manager-only.
  - **Settings — 15 tabs missing**: AuditLogsTab, AutomationsTab, BillingTab, BlockChypSettings, ConditionsTab, DeviceTemplatesPage, InvoiceSettings, MembershipSettings, NotificationTemplatesTab, PosSettings, ReceiptSettings, RepairPricingTab (**fixes CROSS31 no-pricing bug**), SmsVoiceSettings, TicketsRepairsSettings, SetupProgressTab. Android Settings is bare (CROSS38: only 3 toggles). All these tabs should be accessible on Android — at minimum RepairPricingTab, ReceiptSettings, TicketsRepairsSettings as CORE, the rest under Superuser.
  - **Catalog browser**: `catalog/CatalogPage.tsx` — supplier device catalog. Useful during ticket intake when tech needs parts price/availability.
  - **Cash register**: `pos/CashRegisterPage.tsx` — open/close shift, cash counts. Ship as CORE if tenant uses cash (most repair shops do).
  - **Setup wizard**: `setup/SetupPage.tsx` + steps. First-run only — lives on SSW1 (existing TODO). Not needed as Settings tab, but Android should respect the `setup_wizard_completed` flag and show the wizard on first login.

  **C. Recommended Android Settings information architecture:**
  ```
  Settings
    ├─ Profile (existing ProfileScreen)
    ├─ Device preferences (biometric, haptic, dark mode — existing)
    ├─ Store
    │   ├─ Store info (hours, address, phone) — maps to web StepStoreInfo
    │   ├─ Receipts — maps to ReceiptSettings
    │   ├─ Tax — maps to StepTax
    │   └─ Repair pricing — maps to RepairPricingTab (fixes CROSS31)
    ├─ Communications
    │   ├─ SMS templates (existing SmsTemplatesScreen)
    │   ├─ SMS/Voice provider — maps to SmsVoiceSettings
    │   └─ Notification templates — maps to NotificationTemplatesTab
    ├─ Tickets & Repairs — maps to TicketsRepairsSettings
    ├─ Team
    │   ├─ Employees (existing)
    │   ├─ Clock in/out (existing ClockInOutScreen)
    │   └─ Roles & permissions — maps to RolesMatrixPage (superuser)
    ├─ Integrations
    │   ├─ BlockChyp / Stripe — maps to BlockChypSettings
    │   └─ Memberships — maps to MembershipSettings (superuser)
    └─ Superuser (advanced)
        ├─ Audit logs — AuditLogsTab
        ├─ Automations — AutomationsTab
        ├─ Billing / subscription — BillingTab
        ├─ Conditions / warranty — ConditionsTab
        ├─ Device templates — DeviceTemplatesPage
        ├─ Invoice settings — InvoiceSettings
        ├─ POS settings — PosSettings
        ├─ Inventory advanced (ABC, auto-reorder, bins, aging, labels, POs, serials, shrinkage, stocktake)
        └─ Marketing (campaigns, NPS, referrals, segments)
    ├─ Data sync (existing)
    └─ Log out (NEW — fixes CROSS38)
  ```
  Superuser tab must be HIDDEN behind a tap-the-logo-5-times-style easter egg OR visible to users with role=owner only, so regular techs don't get lost in power-user surfaces. Toast on first reveal: "Superuser settings unlocked — advanced options may change app behavior."

  **D. Icons / cross-surface notes:**
  - Missing QR/barcode scanner entry from POS and Ticket Detail (intake by barcode). Android has BarcodeScanScreen — wire additional entry points.
  - Missing Z-report / end-of-day report on Android POS (web has ZReportModal).
  - Missing "Training mode" flag on Android POS (web has TrainingModeBanner).
  - Missing Cash Drawer integration on Android POS.

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










## FIRST-RUN SHOP SETUP WIZARD — 2026-04-10

Self-serve signup on 2026-04-10 with slug `dsaklkj` completed successfully and the user was able to log in, but the shop then dropped them straight into the dashboard without asking for any of the info that `store_config` needs: store name (we set it from the signup form, but only that one key), phone, address, business hours, tax settings, receipt header/footer, logo, and — critically — whether they want to import existing data from RepairDesk / RepairShopr / another system. Result: the shop boots with mostly empty defaults and the user has to hunt through Settings to fill everything in. Poor first-run UX.

- [ ] SSW1. **First-login setup wizard gate:** on first login after signup, if `store_config.setup_completed` is `'true'` but a new `setup_wizard_completed` flag is missing (or `'false'`), show a full-screen modal wizard instead of the dashboard. Wizard collects all the fields currently buried in Settings → Store, Settings → Receipts, and Settings → Tax. Dismissal is only possible via "Complete setup" (all required fields filled) or "Skip for now" (sets a `setup_wizard_skipped_at` timestamp so we can nag on subsequent logins). After completion, set `setup_wizard_completed = 'true'`.

- [ ] SSW2. **Import-from-existing-CRM step in the wizard:** the existing import code lives at `packages/server/src/services/repairDeskImport.ts` and similar. Expose it as a wizard step: "Do you have data from another CRM?" → show RepairDesk, RepairShopr, CSV options. For RepairDesk/RepairShopr, ask for their API key + base URL inline, validate it, then kick off a background import with a progress indicator. User can come back to it later if it takes a while. On skip, just move on.

- [ ] SSW3. **Comprehensive field audit:** enumerate every `store_config` key referenced by the codebase and the whole `Settings → Store` page. For each one, decide:
  - Is it REQUIRED for a functioning shop? (name, phone, email, address, business hours, tax rate, currency) → wizard must collect it
  - Is it OPTIONAL but affects visible UX from day 1? (logo, receipt header/footer, SMS provider creds) → wizard offers it with "skip" option
  - Is it ADVANCED / power-user only? (BlockChyp keys, phone, webhooks, backup config) → wizard skips entirely, user configures later in Settings
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
### Agent 3: Input Validation & Mass Assignment

### Agent 4: Frontend XSS Vulnerabilities

### Agent 5: Backend API Endpoint Abuse

### Agent 6: Component Rendering & React State

### Agent 7: Background Jobs & Crons
- [ ] SA7-1. **Blocking sleep loops:** Modules like `reimport-notes.ts`, `myRepairAppImport.ts`, and `repairDeskImport.ts` rely on recursive or loop-bound async `setTimeout` sleeps. A crash aborts the entire queue without persistent job state recovery.

### Agent 8: Desktop/Electron App Constraints
- [ ] SA8-1. **Deep link validation:** The Electron app now implements a per-user installation without UAC, but the `setup` URL handlers lack strict deep-link origin validation, allowing potential arbitrary custom protocol abuse.

### Agent 9: Android Mobile App Integrations

### Agent 10: General Code Quality & Technical Debt
- [ ] SA10-1. **Lingering Type Mismatches:** Use of `as any` casting is still present in webhook firing and invoice data wrapping hooks, diminishing Typescript's strict enforcement inside the event broadcast components.

## DEEP AUDIT ESCALATION - Advanced Security & Technical Debt (April 12, 2026)

### 1. Incomplete File Upload Constraints (Path Traversal/DoS)

### 2. File Corruptions via Non-Atomic Writes

### 3. Synchronous CPU Event-Loop Locks

### 4. Cryptographic Defaults

### 5. SQLite Parameter Array Bounds Execution Halt 

### 6. Idempotency Skips in Financial Bridging

### 7. Global Socket Scope Leakage

### 8. Hardcoded Secret Entanglements 

### 9. Cookie Parsing Signing Exclusions

### 10. Floating Promises in Database Interfacing

## DAEMON AUDIT (Pass 3) - Core Structural & RCE Escalations (April 12, 2026)

### 1. Remote Code Execution (RCE) via Backup Paths

### 2. Missing Database Concurrency Locks

### 3. Server OOM via Unbounded Image Streams

### 4. Horizontal Privilege Escalation (IDOR)

### 5. Regular Expression Denial of Service (ReDoS)

### 6. LocalStorage Key Scraping
- [ ] D3-6. **Token Exposure over Global `window`:** Web client stores primary JWT definitions and persistent configurations in `localStorage`. There are zero `httpOnly` secure proxy mitigations. If an XSS vector ever triggers, automated 3rd party scrapers dump the user's primary login token bypassing CORS origins completely. — **Partial mitigation in place:** refreshToken is already `httpOnly + secure + sameSite: 'strict'` (auth.routes.ts:269), so XSS cannot rotate a session. AccessToken is short-lived. Full migration to httpOnly access cookie + CSRF header is a larger auth refactor — tracked but deferred.

### 7. Global Socket Scopes via Offline Maps

### 8. Null-Routing on Background Schedulers

## DAEMON AUDIT (Pass 4) - UI/UX & Accessibility Heaven (April 12, 2026)

### 1. Lack of Optimistic UI Interactions
- [ ] D4-1. **Laggy State Transitions:** Across core components (`TicketNotes.tsx`, `TicketListPage.tsx`), React Query `useMutation` implementations strictly invalidate queries `onSuccess`. They entirely lack `onMutate` optimistic caching. Users endure a `~200-400ms` perceived lag upon clicking "Save" or dragging a Kanban card, frustrating power users compared to instantaneous modern apps.

### 2. Form Input Hindrances on Mobile/Touch

### 3. Flash of Skeleton Rows (Flicker)

### 4. Poor Error Boundary Granularity

### 5. Infinite Undo/Redo Voids
- [ ] D4-5. **No Recoverable Destructive Actions:** Modifying or deleting tickets/leads pops up a standard `toast.success`. There is no 5-second `Undo` queue array injected into the Toast mappings. Users who misclick a status change are forced to physically navigate backwards through UI pages to hunt down their mistake instead of clicking "Undo" natively via notification popups.

### 6. Modal Focus Traps (WCAG Violation)

### 7. WCAG "aria-label" Screen-Reader Blindness

### 8. FOUC (Flash of Unstyled Content) on Dark Mode

### 9. HCI Touch Target Ratios
- [ ] D4-9. **Fat-Finger Mobile Actions:** Numerous inline badges and interactive buttons (e.g., `px-1.5 py-0.5` inside Ticket notes and pagination) render to roughly `~16-20px` tall. This mathematically violates standard mobile HCI ratios (Minimum `44x44px`), guaranteeing extreme mis-click rates on phones deployed in the field.

### 10. Indefinite Stacking Toasts

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
- [ ] D5-5. **Offline Spam Escalation:** When a user repeatedly smashes "Complete Payment" inside `CheckoutScreen.kt` on a broken Wi-Fi map, the `SnackbarHostState` queues the network error infinitely. Jetpack sequentially loads these native Snackbars for the duration of the timeout, forcing the user to wait a literal physical minute while 15 identical "Network error" snackbars rotate off the screen individually. While here, also check if the offline error will only show up for credit card processing - we are ok to accept cash without internet, just schedule it to be posted to server later.

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

## Low Priority / Usability Findings

  - `packages/web/src/components/shared/CommandPalette.tsx` searches entities only (tickets, customers, inventory, invoices), not static app pages.

## Second Pass Additions

These items were found in a fresh second pass and are not duplicates of the findings above.

## Medium Priority Findings

## Low Priority / Usability Findings

## APRIL 14 2026 CODEBASE AUDIT ADDITIONS

Static audit scope: global deploy config, server authorization/business logic, reachable web UI, Electron management IPC, Android sync/storage/networking, and shared permission contracts. No source-code changes were made; these items capture follow-up work only.

## High Priority Findings


  Evidence:

  - `docker-compose.yml:7` maps `"443:443"` and `docker-compose.yml:16` sets `PORT=443`.
  - `packages/server/Dockerfile:84` says containerized runs should set `PORT=8443`, while `packages/server/Dockerfile:89` switches to `USER node` and `packages/server/Dockerfile:92` still exposes `443`.

  User impact:

  The default container path can fail at boot because a non-root Linux process cannot bind privileged port 443 without extra capabilities.

  Suggested fix:

  Align the container contract around an unprivileged internal port: set compose to `443:8443`, set `PORT=8443`, expose `8443`, and update any health checks or docs that still assume in-container 443.


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

- [ ] AND-20260414-M9. **Ticket detail bottom bar is likely to overflow on phone widths:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:473-582` places five labeled `TextButton`s in one `BottomAppBar` row: Status, Call, Note, SMS, and Print.
  - The row uses `Arrangement.SpaceEvenly` with fixed horizontal padding and no overflow menu, horizontal scroll, or compact icon-only mode.

  User impact:

  On narrow phones or larger accessibility font sizes, the action row can clip labels, push actions off screen, or create difficult touch targets.

  Suggested fix:

  Collapse secondary actions into an overflow menu, use icon-only actions with tooltips/content descriptions, or switch to an adaptive bottom action layout at compact width.

## Low Priority / Android Polish

## PRODUCTION READINESS PLAN — Outstanding Items (moved from ProductionPlan.md, 2026-04-16)

> Source: `ProductionPlan.md`. All `[x]` items stay there as completion record. All `[ ]` items relocated here for active tracking. IDs prefixed `PROD`.

### Phase 0 — Pre-flight inventory

- [ ] PROD1. **Confirm public repo target + license decision:** note GitHub org/user that will host, and chosen license (MIT/Apache-2.0/AGPL/proprietary). Blocks first commit.

- [x] ~~PROD3. **History depth audit (post `git init`):**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD4. **List + prune branches before publish:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD5. **List + prune tags before publish:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD6. **Drop / commit stashes:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD7. **Submodule check:**~~ — migrated to DONETODOS 2026-04-16.

### Phase 1 — Secrets sweep (post-init verification)

- [x] ~~PROD8. **Untrack any DB/WAL/SHM files:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD9. **Untrack APK/AAB:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD10. **Untrack build output:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD11. **Cross-reference env vars vs `.env.example`:**~~ — migrated to DONETODOS 2026-04-16.

### Phase 2 — JWT, sessions, auth hardening

- [x] ~~PROD13. **VERIFY refresh token deleted from `sessions` on logout:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD14. **VERIFY 2FA server-side enforcement:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD15. **VERIFY rate limiting wired on `/auth/forgot-password` + `/signup`:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD16. **VERIFY admin session revocation UI exists:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD17. **Spot-check `requireAuth` on every endpoint of 5 routes:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD18. **Grep for routes querying by `id` alone w/o tenant scope:**~~ — migrated to DONETODOS 2026-04-17.

### Phase 3 — Input validation & injection

- [x] ~~PROD19. **Hunt SQL injection via template-string interpolation:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD20. **Audit `db.exec(...)` calls for dynamic input:**~~ — migrated to DONETODOS 2026-04-17.

- [ ] PROD21. **Deep-audit dynamic-WHERE routes:** `search.routes.ts`, `import.routes.ts`, `reports.routes.ts`, `customers.routes.ts` bulk ops. These build dynamic WHERE clauses and are highest injection risk.

- [x] ~~PROD22. **Confirm validation library in use (zod/joi/express-validator):**~~ — migrated to DONETODOS 2026-04-17. **Zod installed but not yet used** — codebase currently uses custom `utils/validate.ts` helpers. Flagged as gap; schema validation work still required.

- [x] ~~PROD23. **Spot-check 3 high-risk routes for `req.body` schema validation:**~~ — migrated to DONETODOS 2026-04-17. **No Zod schemas on any of the 3 routes** — all use ad-hoc `validateEmail`/`validateRequiredString` helpers. Gap flagged.

- [x] ~~PROD24. **VERIFY multer `limits.fileSize` set in every upload route.**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD25. **VERIFY uploaded files served via controlled route (not raw filesystem path).**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD26. **Audit `dangerouslySetInnerHTML` usage in `packages/web/src`:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD27. **Email/SMS templates escape variables before substitution:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD28. **Path traversal grep:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD30. **Open-redirect guard on `redirect`/`next`/`returnUrl` params:**~~ — migrated to DONETODOS 2026-04-17.

### Phase 4 — Transport, headers, CORS

- [x] ~~PROD32. **HSTS header:** `max-age=15552000; includeSubDomains`.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD33. **Secure cookies:** `Secure`, `HttpOnly`, `SameSite=Lax|Strict`~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD34. **VERIFY CSP config in `helmet({...})` block (`index.ts`):**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD36. **`credentials: true` only paired with explicit origins.**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD37. **VERIFY unauthenticated WS upgrade rejected (401/close):**~~ — migrated to DONETODOS 2026-04-17.

### Phase 5 — Multi-tenant isolation

- [x] ~~PROD42. **Confirm per-tenant SQLite isolation:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD43. **`tenantResolver` fails closed:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD44. **Super-admin endpoints gated by separate auth check:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD45. **Tenant code cannot write to master DB:**~~ — migrated to DONETODOS 2026-04-17. Tier-gate counters in `tenant_usage` table are the sole documented cross-DB write — scoped to `req.tenantId`, safe.

### Phase 6 — Logging, monitoring, errors

- [x] ~~PROD49. **VERIFY no accidental body logging:** grep `console\.(log|info)\(.*req\.body` across route handlers.~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD50. **VERIFY `services/crashTracker.ts` does NOT snapshot request bodies on crash.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD51. **VERIFY 403 vs 404 indistinguishable for non-owned resources:** fetching another tenant's ticket → 404, not 403 (prevents enumeration).~~ — migrated to DONETODOS 2026-04-16.

### Phase 7 — Backups, data, recovery

- [ ] PROD58. **Per-tenant "download all my data" capability:** GDPR/CCPA basics.

- [ ] PROD59. **"Delete tenant" capability (admin-only, multi-step confirm):** wipes tenant DB. Per memory rule: this is the ONE allowed deletion path — explicit user-initiated termination only.

### Phase 8 — Dependencies & supply chain

- [x] ~~PROD62. **`package-lock.json` committed at every package root.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD63. **No `node_modules/` tracked.**~~ — migrated to DONETODOS 2026-04-16.

- [ ] PROD64. **Dependency typo-squat audit:** read top-level `dependencies` in each `package.json`. Flag unknown packages, look for typo-squats (`reqeust`, `loadsh`, etc.).

- [ ] PROD65. **`package.json` `repository`/`bugs`/`homepage` fields:** point to right URL or absent.

- [ ] PROD66. **Strip local absolute paths from `scripts` blocks:** no `C:\Users\...`.

- [ ] PROD67. **No sketchy `postinstall` scripts.**

### Phase 9 — Build & deploy hygiene

- [ ] PROD68. **Confirm `npm run build` in `packages/web/` produces `dist/` and `index.ts` serves it.**

- [ ] PROD69. **Source maps decision:** if shipped, intentional. Fine for OSS but document.

- [x] ~~PROD70. **`dist/` not in tree.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD71. **Single source of truth for `NODE_ENV=production` at deploy:** mention in README.~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD72. **Audit `if (process.env.NODE_ENV === 'development')` blocks:** confirm none expose debug routes / dev-only endpoints / relaxed auth in prod.~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD73. **VERIFY `repair-tenant.ts` does no DB deletion.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD74. **Migrations idempotent + auto-run on boot:** re-running a completed migration must be safe.~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD75. **No migration deletes data without a guard.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD76. **Migration order deterministic:** numbered, no naming collisions. (See Phase 99.3 — `049_*` and `050_*` prefix collisions exist; verify `migrate.ts` handles.)~~ — migrated to DONETODOS 2026-04-16.

- [ ] PROD77. **VERIFY `scripts/reset-database.sh` + `scripts/clear-imported-data.sh` have `NODE_ENV` guard if they exist.**

### Phase 10 — Repo polish for public release

- [ ] PROD78. **Update `bizarre-crm/README.md` for public audience:** tagline, architecture overview (1 paragraph), setup steps, env vars (link `.env.example`), default credentials / first-boot, license, contributing, disclaimers (alpha software, self-host at your own risk).

- [ ] PROD79. **Decide repo-root README:** mirror or simplified.

- [ ] PROD80. **Single primary `LICENSE` at repo root with chosen license.** Ask user which (MIT/Apache-2.0/AGPL/proprietary).

- [ ] PROD81. **`LICENSES.md` lists transitive third-party license obligations.**

- [ ] PROD82. **Manually read each `docs/*.md` before publish:** `product-overview.md`, `developer-guide.md`, `tech-stack-and-security.md`, `android-field-app.md`, `android-operational-features-audit.md`, `operator-guide.md`. Strip internal IPs, SSH hosts, customer data, personal email/phone, derogatory competitor mentions. Grep already clean for `pavel`/`bizarre electronics`/IPs — manual read catches informal notes.

- [x] ~~PROD83. **Verify scratch markdowns excluded:**~~ — migrated to DONETODOS 2026-04-16.

- [ ] PROD84. **Repo-root markdown decision:** `Repair_Shop_CRM_UIUX_Audit_Instructions.md`, `UsersPavel.claudeplansmighty-...md`, `antigravity.md` — default untrack.

- [ ] PROD85. **Hidden personal data sweep:** owner real name, personal email/phone, home address, store address, RepairDesk account ID. Replace with placeholders or remove.

- [ ] PROD86. **`pavel` / `bizarre` / owner-username intentionality audit:** confirm each occurrence intentional, not accidental.

- [ ] PROD87. **Internal-IP scrub:** `grep -E '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'`. Replace any ips with the .env value for domain situations or make sure localhost works for non-public self hosted>`.

- [ ] PROD89. **Strip personal-opinion comments about people/customers/competitors.**

- [ ] PROD90. **Confirm no JSON dump of real customer data in `seed.ts`/`sampleData.ts`/fixtures.**

- [ ] PROD91. **Confirm `services/sampleData.ts` generates fake data, not real exports.**

- [x] ~~PROD92. **Create `SECURITY.md` at repo root with private disclosure email.**~~ — migrated to DONETODOS 2026-04-16.

- [ ] PROD93. **Verify `.github/ISSUE_TEMPLATE/*.md` not blocked by `*.md` rule:** `git check-ignore -v .github/ISSUE_TEMPLATE/bug_report.md` before assuming included.

- [ ] PROD94. **Optional: `CODE_OF_CONDUCT.md` for community engagement.**

- [ ] PROD95. **CI workflows in `.github/workflows/`:** no inline secrets, use repo secrets.

- [ ] PROD96. **Minimal CI:** install + lint + typecheck + build. NO deploy workflows pointing to user's prod server.

### Phase 11 — Operational

- [ ] PROD97. **Read `ecosystem.config.js` (PM2) — confirm no local-only paths.**

- [ ] PROD98. **Graceful shutdown handlers in `index.ts`:** close DB, drain WS, finish in-flight requests on SIGTERM/SIGINT.

- [ ] PROD99. **Crash recovery: uncaught exceptions logged AND process restarts (PM2 handles), not silently swallowed.** Confirm `middleware/crashResiliency.ts` + `services/crashTracker.ts`.

- [ ] PROD100. **`/healthz` returns 200 quickly without DB heavy work** (LB probe-suitable).

- [ ] PROD101. **`/readyz` (if present) checks DB connectivity.**

- [ ] PROD102. **Per-tenant upload quota enforced BEFORE write (not after):** per migration `085_upload_quotas.sql`.

- [ ] PROD103. **Log rotation on `bizarre-crm/logs/`:** prevent unbounded growth.

- [ ] PROD104. **Outbound kill-switch env var (e.g. `DISABLE_OUTBOUND_EMAIL=true`) for emergencies.**

- [ ] PROD105. **SMS sender ID / from-email per-tenant config, not global.**

### Phase 12 — Final pre-publish checklist (gate before flipping public)

- [ ] PROD106. **Phase 1–6 (all PROD items above) complete and clean.**

- [ ] PROD107. **All security tests pass:** `bash security-tests.sh && bash security-tests-phase2.sh && bash security-tests-phase3.sh` (60 tests, 3 phases per CLAUDE.md).

- [ ] PROD108. **`npm run build` succeeds in `packages/web/`.**

- [ ] PROD109. **Server starts cleanly with fresh `.env`** (only `JWT_SECRET`, `JWT_REFRESH_SECRET`, `PORT`).

- [ ] PROD110. **Manual smoke: login as default admin → change password → 2FA flow.**

- [ ] PROD111. **Manual smoke: signup new tenant → tenant DB created → data isolation verified.**

- [ ] PROD112. **Backup → restore on scratch dir → data round-trips.**

- [ ] PROD113. **`git status` clean, `git log` reviewed for embarrassing commit messages.**

- [ ] PROD114. **Push to PRIVATE GitHub repo first → verify CI passes → no secret-scanning alerts → THEN flip public.**

- [ ] PROD115. **Post-publish: subscribe to GitHub secret scanning + Dependabot alerts.**

### Phase 99 — Findings (open decisions/risks from executor)

- [ ] PROD116. **Migration prefix collision risk (Phase 99.3):** three files share `049_` (`049_customer_is_active.sql`, `049_po_status_workflow.sql`, `049_sms_scheduled_and_archival.sql`) and two share `050_`. Verify `db/migrate.ts` sorts by filename + handles duplicates gracefully (no non-deterministic order, no silent skips).

- [ ] PROD117. **`scripts/full-import.ts` + `scripts/reimport-notes.ts` are shop-specific (Phase 99.4):** one-time RepairDesk import for Bizarre Electronics. Move to `scripts/archive/` or document as single-use migration tools. `ADMIN_PASSWORD` env var already added.

## Security Audit Findings (2026-04-16) — deduped against existing backlog

Findings sourced from `bughunt/findings.jsonl` (451 entries) + `bughunt/verified.jsonl` (22 verdicts) + Phase-4 live probes against local + prod sandbox. Severity reflects post-verification state. Items flagged `[uncertain — verify overlap]` may duplicate an existing PROD/AUD/TS entry — review before starting.

### CRITICAL

### HIGH — auth

### HIGH — authz

- [ ] SEC-H20-stepup. **Step-up TOTP on super-admin destructive endpoints** (delete tenant, PUT /tenants/:slug plan, force-disable-2fa, DELETE /sessions, PUT /config). Session TTL already shortened to 30m via commit b0ae99e (2026-04-17). Remainder: UI prompt + `x-super-admin-totp` header check on each destructive route handler before mutation. `super-admin.routes.ts`. (AZ-009 / AZ-023 / BH-B-016)
- [ ] SEC-H25. **Enforce `requirePermission` on every mutating tenant endpoint** (role matrix advisory today). `routes/{tickets,invoices,customers,inventory,refunds,giftCards,deposits}.routes.ts`. (AZ-027)
- [x] ~~SEC-H27. **Tracking token out of URL query** — hash at rest, move to `Authorization` header, add expiry. `tracking.routes.ts:99-141`. (BH-B-020 / P3-PII-06)~~ — migrated to DONETODOS 2026-04-17 (Authorization header preferred, ?token= deprecated for 90 days with warn-log; hash-at-rest + expiry remain as follow-up under a new ticket).
- [x] ~~SEC-H32. **Tracking `/portal/:orderId/message` require portal session** for `customer_message` writes. `tracking.routes.ts:466`. (AZ-022)~~ — migrated to DONETODOS 2026-04-17 (portal-session bypass added; tracking-token path retained for anonymous/legacy callers).
### HIGH — payment

- [ ] SEC-H34-money-refactor. **Convert money columns REAL → INTEGER (minor units)** across invoices/payments/refunds/pos_transactions/cash_register/gift_cards/deposits/commissions. (PAY-01) DEFERRED 2026-04-17 — scope is fleet-wide: schema migration across 8+ tables in every per-tenant DB, every SELECT/INSERT/UPDATE in server code that touches those columns (dozens of handlers in invoices/pos/refunds/giftCards/deposits/membership/blockchyp/stripe/reports routes + retention sweepers + analytics), web DTO + form handling (every money field in pages/invoices, pages/pos, pages/refunds, pages/giftCards, pages/deposits, pages/reports), and Android DTO + UI updates. Recipe: (1) add new `_cents` INTEGER columns alongside each existing REAL column; (2) dual-write period where both columns are kept in sync; (3) flip reads to the cents columns handler-by-handler; (4) reconcile any drift; (5) drop REAL columns. Each step must ship separately with its own verification; skipping this phasing risks silent rounding corruption on live invoices. Not safe as a single commit. Blocks SEC-H37 (currency column) — they should land as a joint cents+currency migration.
- [ ] SEC-H35. **Stripe webhook handlers for `charge.dispute.created`, `charge.refunded`, `payment_intent.payment_failed`, `customer.subscription.trial_will_end`.** Unhandled events silently record `tenant_id=NULL`. `stripe.ts:523-751`. (PAY-07)
- [ ] SEC-H38. **Store SHA-256 of gift card code, not plaintext;** mask in `audit_log.details`; bump `generateCode` to 128 bits. **Verified live — code `3B2681D6E6416C5B` in audit_logs plaintext.** `giftCards.routes.ts:33-35, 237`. (PAY-14 / BH-B-004 / CRYPTO-H02 / LIVE-04)
- [ ] SEC-H40. **Deposit DELETE must call processor refund;** link to originating `payment_id`; update invoice amount_paid/amount_due on apply. `deposits.routes.ts:218-245, 165-215`. (PAY-19, 20)
- [ ] SEC-H41-needs-sdk. **BlockChyp `/void-payment` must call `client.void()`** at processor + add BlockChyp webhook receiver. `blockchyp.routes.ts:359-397`. (trace-pos-005 / trace-webhook-002) DEFERRED 2026-04-17 — `services/blockchyp.ts` has no `void()` wrapper today. Recipe: (1) add voidCharge(transactionId) wrapping the SDK's void endpoint, (2) call it from /void-payment before signature cleanup, (3) record processor-side errors back to the payment row, (4) add /webhooks/blockchyp receiver with HMAC verify. Each step needs a smoke-test against a live terminal — not safe as a pure code-only commit.
- [ ] SEC-H45-needs-sdk. **Membership `/subscribe` verify `blockchyp_token` with processor** before activating subscription. `membership.routes.ts:140-203`. (LOGIC-024) DEFERRED 2026-04-17 — `services/blockchyp.ts` has no token-validation helper. Recipe: add `verifyCustomerToken(token)` wrapping the SDK customerLookup/tokenMetadata endpoint, call before INSERT, reject 400 if token not found processor-side, record audit. Same SDK dependency as SEC-H41-needs-sdk — batch together.
- [ ] SEC-H47. **Bulk `mark_paid` route through `POST /:id/payments`** (currently hardcodes cash, skips dedup/webhooks/commissions). `invoices.routes.ts:695-725`. (LOGIC-006)
- [ ] SEC-H50. **Estimate `/approve` disallow self-approval** (`created_by=current_user`). `estimates.routes.ts:902-935`. (LOGIC-016)
- [ ] SEC-H51. **Estimate `/:id/convert` atomic** — `UPDATE...WHERE status NOT IN ('converted','cancelled')` + check `changes=1`. `estimates.routes.ts:645-744`. (LOGIC-026)
- [ ] SEC-H52. **Hash estimate `approval_token` at rest** (currently plaintext). `estimates.routes.ts:793-808`. (LOGIC-028)

### HIGH — pii

- [ ] SEC-H53. **Extend GDPR-erase** to scrub FTS, `ticket_photos` on disk, `audit_log.details` JSON, Stripe customers, SMS suppression. `customers.routes.ts:1692-1773` + migrations. (P3-PII-03, 04, 11)
- [ ] SEC-H54. **Gate `/uploads/<slug>/*` behind auth;** signed-URL + HMAC(file_path+expires_at) for portal/MMS; separate `/admin-uploads` for licenses. `index.ts:845-865`. (P3-PII-07 / PUB-022)
- [ ] SEC-H55. **Audit `customer_viewed` on GET `/:id` + bulk list-with-stats.** `customers.routes.ts:88, 991-1019`. (P3-PII-05)
- [ ] SEC-H56. **Step-up auth + email notification on PII exports** (`/customers/:id/export`, `/settings-ext/export.json`, `/reports/*?export_all=1`). (P3-PII-12, 13, 20)
- [ ] SEC-H57. **Retention rules for sms_messages, call_logs, email_messages, ticket_notes** (default 24mo, tenant-configurable). `services/retentionSweeper.ts:54-70`. (P3-PII-08)
- [ ] SEC-H58. **Upload retention:** unlink `ticket_photos` files for closed tickets > 12mo; scrub on GDPR-erase. `tickets.routes.ts:2173-2229`. (P3-PII-15)
- [ ] SEC-H59. **Full tenant export endpoint** for data portability (zip of all tables + uploads, tenant passphrase). (P3-PII-16)
- [ ] SEC-H60. **Backup restore filename slug+tenant_id match + HMAC over metadata** to prevent tampered `.db.enc` swap. `services/backup.ts:82-139, 432-458`, `super-admin.routes.ts:1161-1183`. (P3-PII-17, 18)
- [ ] SEC-H61. **Reset-password link `Referrer-Policy: no-referrer`** + `history.replaceState` to strip token from URL. [uncertain] (P3-PII-14)

### HIGH — concurrency

- [ ] SEC-H62. **Differential atomic UPDATEs on every stock mutation path** (POS `stock_membership`, stocktake, ticket parts delete/quick-add, gift card reload). (C3-001, 003, 004, 010, 011)
- [ ] SEC-H63. **Transactional stocktake commit** with `WHERE status='open'` guard inside txn. `stocktake.routes.ts:267-325`. (BH-B-011)
- [ ] SEC-H64. **Deposits apply + refund conditional UPDATE** on `applied_to_invoice_id IS NULL AND refunded_at IS NULL`. `deposits.routes.ts:165-245`. (C3-005, 006)
- [ ] SEC-H65. **Password reset UPDATE `WHERE reset_token = ?` + single transaction** with DELETE sessions. `auth.routes.ts:1198-1231`. (trace-reset-001 / C3-014)
- [ ] SEC-H66. **pruneOldSessions + INSERT in single `adb.transaction()`** with atomic CTE-based prune. `auth.routes.ts:157-169, 247-250`. (C3-013)
- [ ] SEC-H67. **store_credits UPSERT + `UNIQUE(customer_id)` constraint.** `refunds.routes.ts:222-237`. (C3-035)
- [ ] SEC-H68. **`commissions UNIQUE(ticket_id)` partial index WHERE type != 'reversal'** + single-statement atomic status change. `tickets.routes.ts:1861-1948`. (C3-009, 049)
- [ ] SEC-H69. **Notification/SMS/email retry queues SELECT-and-claim** pattern + backoff jitter. `services/notifications.ts:220-266` + `index.ts:2138-2180`. (C3-019…022, 045)
- [ ] SEC-H70. **Stripe webhook `processPaymentFailed` differential UPDATE** + wrap full switch in `masterDb.transaction()`. `stripe.ts:418-509`. (C3-031)
- [ ] SEC-H71. **Idempotency store → tenant DB table `idempotency_keys`** with `UNIQUE(user_id, key)`. `middleware/idempotency.ts:49-100`. (C3-017)
- [ ] SEC-H72. **UNIQUE partial index on `customer_subscriptions(customer_id) WHERE status IN ('active','past_due')`.** `membership.routes.ts:164-195`. (C3-033)
- [ ] SEC-H73. **Backup code consume atomic UPDATE** (`JSON_REMOVE` + `WHERE json_extract`). `auth.routes.ts:754-762, 818-830`. (C3-016)

### HIGH — reliability

- [ ] SEC-H74. **Explicit 15s timeouts + `maxNetworkRetries`** on Stripe, BlockChyp, Nodemailer (80s / 10min defaults today). (REL-001, 002, 003)
- [ ] SEC-H75. **Promisified `execFile` in githubUpdater** (30s sync git blocks Express process hourly). `services/githubUpdater.ts:89-96, 239-247`. (REL-005)
- [ ] SEC-H76. **Wallclock ceiling (90min) on catalogScraper** + async spawn in backup disk-space check. `services/catalogScraper.ts:42-68` + `backup.ts:215-256`. (REL-006, 007)
- [ ] SEC-H77. **Circuit breakers on outbound providers** (Stripe/BlockChyp/Twilio/Telnyx/Vonage/Plivo/Bandwidth/SMTP/Cloudflare/GitHub). (REL-008)
- [ ] SEC-H78. **Single-query kanban + tv-display** (ROW_NUMBER / IN-clause vs Promise.all). `tickets.routes.ts:1130-1176, 1362-1389`. (REL-011, 012)
- [ ] SEC-H79. **dashboardCache single-flight** to prevent cache stampede. `utils/cache.ts`. (REL-013)
- [ ] SEC-H80. **Cap reports date range 90d default / 365d flag;** long range = async job. `reports.routes.ts:22-27`. (REL-016)
- [ ] SEC-H81. **Drop global `express.json` limit to 1mb** + per-route carve-outs (10mb × 300req/min = 3GB RAM DoS today). `index.ts:776-779`. (REL-019 / PUB-005)
- [ ] SEC-H82. **RepairDesk import to Piscina worker + wallclock + business-hours throttle.** `services/repairDeskImport.ts`. (REL-028)

### HIGH — public-surface

- [ ] SEC-H83. **Migrate global `/api/v1` rate limiter + `webhookRateMap` to DB-backed** (auth paths already migrated via 069). `index.ts:719-770, 906-927`. (PUB-001, 002)
- [ ] SEC-H84. **Trust proxy = explicit CF/LB IPs**, not integer 1. `index.ts:374`. [uncertain] (PUB-012)
- [ ] SEC-H85. **CAPTCHA on `/auth/login` + `/forgot-password`** after N failures. (PUB-013, 014)
- [ ] SEC-H86. **WebSocket origin allowlist fail-closed on parse/DB error;** cap per-IP + per-tenant concurrent sockets. `ws/server.ts:181-225, 242-462`. (BH-0011 / PUB-018, 019)
- [ ] SEC-H87. **Portal PIN 6 digits + per-customer_id rate limit + SMS notification on lockout.** `portal.routes.ts:478, 661-664, 706`. (P3-AUTH-13 / P3-PII-09)
- [ ] SEC-H88. **Portal quick-track per-order_id + per-phone-last4 lockout;** portal comments require portal session. `portal.routes.ts:337-415, 1057`. (AZ-010 / P3-AUTH-14 / AZ-022)
- [ ] SEC-H89. **CSRF token on `/api/v1/auth/refresh`** + tighten CSP on `/admin` + `/super-admin` panels (remove `'unsafe-inline'` script-src). `index.ts:593-622, 885-895`. (PUB-007, 008, 023)
- [ ] SEC-H90. **Host-header sanitation on HTTP→HTTPS redirect** (only redirect to approved baseDomain). `index.ts:406-411, 567-574`. (PUB-028)
- [ ] SEC-H91. **Remove legacy `master-admin.routes.ts`** (kill-switch theatre). (P3-AUTH-16 / PUB-027)
- [ ] SEC-H92. **SSRF guards on `services/webhooks.ts webhook_url`:** reject RFC1918/link-local/loopback after DNS; strict http(s); block cross-host redirect follow. `services/webhooks.ts:86`. (sinks-001)
- [ ] SEC-H93. **Allowlist provider domains for MMS/voice recording fetches** before GET with Authorization. `routes/{sms,voice}.routes.ts`. (sinks-005, 006)
- [ ] SEC-H94. **Signup fail-closed on missing `HCAPTCHA_SECRET` in prod + email-verification gate** before provisioning subdomain + CF DNS record. **Verified live — empty captcha_token provisioned tenant `probetest` id 9.** `signup.routes.ts:~274`. (LIVE-01 / BH-0001 / BH-0002)

### HIGH — electron + android

- [ ] SEC-H95. **Sig-verify auto-update (`update.bat`):** signed git tag / tarball before `git pull` + confirm dialog + EV Authenticode cert. `management/src/main/ipc/management-api.ts:336-482` + `electron-builder.yml`. (electron-002, 004)
- [ ] SEC-H96. **`@electron/fuses`:** disable RunAsNode, EnableNodeOptionsEnvironmentVariable, EnableNodeCliInspectArguments; enable OnlyLoadAppFromAsar + EnableEmbeddedAsarIntegrityValidation. (electron-005, 006)
- [ ] SEC-H97. **Zod schemas on every `ipcMain.handle` + senderFrame URL check + path normalization/UNC-reject** in admin:browse-drive / admin:create-folder. `management/src/main/ipc/management-api.ts:234-273, 612-620`. (electron-007, 008)
- [ ] SEC-H98. **Pin cert fingerprint of `packages/server/certs/server.cert`** in management api-client (port-squat impersonation risk). `management/src/main/services/api-client.ts:92-99`. [uncertain] (electron-009)
- [ ] SEC-H99. **Replace Android `PRIMARY_LEAF_PIN_REPLACE_ME`/`BACKUP_LEAF_PIN_REPLACE_ME`** with real SPKI SHA-256 pins + CI guard rejecting `REPLACE_ME` in release builds. [uncertain — may overlap AUD-20260414-H4] (BH-A001)
- [ ] SEC-H100. **Android release signing fail-closed** when `~/.android-keystores/bizarrecrm-release.properties` missing (falls back to global debug keystore today). `android/app/build.gradle.kts:65-95`. (BH-A010)
- [ ] SEC-H101. **Move `fcmToken` from plain `AppPreferences` to `EncryptedSharedPreferences`.** `android/.../AppPreferences.kt:16, 40-46`. (BH-A003)
- [ ] SEC-H102. **`AuthInterceptor.clearAuthState()` POST `/auth/logout`** before wiping local prefs. `android/.../AuthInterceptor.kt:96-177`. (BH-B-021)

### HIGH — crypto

- [ ] SEC-H103. **Split `JWT_SECRET` into dedicated env vars:** `ACCESS_JWT_SECRET`, `REFRESH_JWT_SECRET`, `CONFIG_ENCRYPTION_KEY`, `BACKUP_ENCRYPTION_KEY`, `DB_ENCRYPTION_KEY`. Require `BACKUP_ENCRYPTION_KEY` + `CONFIG_ENCRYPTION_KEY` in production (fatal, not warn). `utils/configEncryption.ts:17-19` + `backup.ts:60-75` + `config.ts`. (CRYPTO-H01 / BH-S003 / BH-S008 / BH-S009 / P3-PII-02)
- [ ] SEC-H104. **Remove inbox bulk-send HMAC fallback `|| 'bizarre-inbox-bulk'`.** `inbox.routes.ts:414, 429`. (BH-S004)
- [ ] SEC-H105. **Super-admin fallback secret `'super-admin-dev-secret'`** in single-tenant mode — require `SUPER_ADMIN_SECRET` whenever router mounts. `config.ts:188`. (BH-S007)

### HIGH — supply-chain + tests

- [ ] SEC-H106. **Resolve `bcryptjs` 2.4.3 vs ^3.0.2 drift:** `npm install` at repo root, commit `package-lock.json`.
- [ ] SEC-H107. **Minimum CI:** `npm ci && npm run build && npm audit --audit-level=high && npm ls --all` on PR.
- [ ] SEC-H108. **Pin `app-builder-bin` exact version** + move to devDependencies. `management/package.json:25`.
- [ ] SEC-H109. **Bump `dompurify` >=3.3.4** + audit every `ADD_TAGS` usage. (CVE GHSA-39q2-94rc-95cp / BH-0013)
- [ ] SEC-H110. **Bump `follow-redirects` >=1.15.12** via `npm audit fix`; set `maxRedirects:0` on BlockChyp axios. (CVE GHSA-r4q5-vmmm-2653 / BH-0014)
- [ ] SEC-H111. **`.npmrc ignore-scripts=true` in CI** + SHA256 verification of Electron/native-binary prebuilds.

### HIGH — logic

- [ ] SEC-H112. **Ticket status state machine + transition guard** on UPDATE. `tickets.routes.ts:1803-1895`. (LOGIC-001)
- [ ] SEC-H113. **Invoice + lead status enums + state-machine validation.** (LOGIC-002, 003, 027)
- [ ] SEC-H114. **Gift card expiry cron + redeem atomic** `AND (expires_at IS NULL OR expires_at > datetime('now'))`. `giftCards.routes.ts:312-351`. (LOGIC-004)
- [ ] SEC-H115. **SMS send checks `customers.sms_opt_in` (TCPA)** + admin override for transactional-exempt. `sms.routes.ts:414-590`. (BH-B-022)
- [ ] SEC-H116. **Customer merge `Number(keep_id) === Number(merge_id)`** (string-vs-number type confusion enables self-merge soft-delete). `customers.routes.ts:404-538`. (LOGIC-008)
- [ ] SEC-H117. **Cap line-item qty ≤ 10000 + invoice.total ≤ $1M** without admin override. `invoices.routes.ts:240-250`. (LOGIC-025)
- [ ] SEC-H118. **Trade-ins state machine + soft-delete** (accepted → deleted loses audit). `tradeIns.routes.ts:104-132`. (LOGIC-012, BH-B-006, 008)
- [ ] SEC-H119. **Pagination guard reject `OFFSET > 100000`** across trade-ins/loaners/gift-cards/rma/refunds/payment-links. (LOGIC-011)
- [ ] SEC-H120. **Universal `MAX_PAGE_SIZE=100` constant.** (PUB-015)
- [ ] SEC-H121. **Soft-delete + `is_deleted` filter** on trade-ins, loaners, rma, gift cards. (LOGIC-019)
- [ ] SEC-H122. **`automations.executeChangeStatus` reuse HTTP handler guards** (post-conditions, parts, diagnostic note). `services/automations.ts:270-286`. (LOGIC-023)

### HIGH — ops (additional)

- [ ] SEC-H123. **Per-tenant/per-IP WebSocket connection cap + back-pressure** (`ws.bufferedAmount` threshold). `ws/server.ts:508-545`, `index.ts:547-562`. (REL-020, 021 / PUB-019)
- [ ] SEC-H124. **Tenant-DB pool refcounting** + MAX_POOL_SIZE review. `db/tenant-pool.ts:55-78`. [uncertain — overlap AUD-M19] (REL-009)

### MEDIUM

- [x] ~~SEC-M14. **Deposits `POST /` manager/admin role gate.** `deposits.routes.ts:97-159`. (PAY-21)~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-M15. **Per-email signup rate limit** (in addition to per-IP). `signup.routes.ts:62-68`. (trace-signup-003)~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-M17. **Trade-ins accept atomic inventory + store_credit INSERT** on status→accepted. `tradeIns.routes.ts:104-132`. (BH-B-007)~~ — migrated to DONETODOS 2026-04-17.
- [x] ~~SEC-M20. **Management routes require master-auth + per-handler tenantId guard.** `management.routes.ts` + `index.ts:1094`. (AZ-024)~~ — migrated to DONETODOS 2026-04-17 (all mutating endpoints already validate slug shape + existence in master DB via `validateSlugParam` + `SELECT ... WHERE slug = ?`; invariant now codified in file header docstring).
- [ ] SEC-M21. **Portal register/send-code 24h per-phone hard cap + CAPTCHA on first new IP.** `portal.routes.ts:510`. (AZ-025)
- [x] ~~SEC-M25. **Stripe webhook: on exception DELETE idempotency claim** so retries work; or DLQ. `stripe.ts:745-753`. (trace-webhook-001)~~ — migrated to DONETODOS 2026-04-16.
- [ ] SEC-M26. **Import worker yield 100-row batches + `PRAGMA wal_checkpoint(PASSIVE)`** periodically. (C3-028, 029)
- [ ] SEC-M28-pino-add. **Rotating logger** (pino/winston file transport + max size). `utils/logger.ts`. (REL-015) DEFERRED 2026-04-17 — adding pino/winston is a dependency + build change (neither is currently in `packages/server/package.json`). Meanwhile `utils/logger.ts` already emits structured JSON on stdout/stderr with PII redaction + level gating. The canonical rotation path for production deployments is the host supervisor, NOT the app:
    - PM2: `pm2-logrotate` module handles size/time-based rotation (already documented in ecosystem.config.js).
    - systemd: `journald` with `SystemMaxUse=` + `MaxFileSec=` in `journald.conf`.
    - Docker / Kubernetes: the container log driver (`json-file max-size`, `max-file`; or a cluster aggregator like Loki/Fluent Bit).
    - Bare metal: `logrotate` + a `>>` redirect wrapper.
  App-level rotation is a secondary concern — it can duplicate work the supervisor already does and introduces a new failure mode (log disk-full handling inside the Node process). Revisit only if ops reports a scenario where host rotation is not available.
- [ ] SEC-M34. **BlockChyp terminal offline:** invalidate client cache on timeout + reconcile via terminal query before marking failed. `services/blockchyp.ts:57-104, 318-420`. (PAY-23)
- [ ] SEC-M35. **Stripe idempotency key derive from (tenant_id, price_id, epoch_day)** — latent fix pending Enterprise checkout. `stripe.ts:215-245, 323-341`. (PAY-03)
- [ ] SEC-M36. **Tenant-owned Stripe + recurring charge worker** [uncertain — overlap TS1/TS2]
- [x] ~~SEC-M42. **Janitor cron** for stuck `payment_idempotency.status='pending'` > 5min → `failed`. (PAY-04 / trace-pos-003)~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-M43. **`checkout-with-ticket` auto-store-credit on card overpayment.** `pos.routes.ts:1334-1370`. (PAY-11)~~ — migrated to DONETODOS 2026-04-17.
- [x] ~~SEC-M44. **Add `capture_state` column on payments** + gate refund on 'captured'. `refunds.routes.ts:79-158`. (PAY-12)~~ — migrated to DONETODOS 2026-04-17.
- [ ] SEC-M47. **scheduled_report_email → scheduled_report_recipients table** with status + audit. `services/scheduledReports.ts:201-242`. (LOGIC-022)
- [ ] SEC-M48. **Per-task timeout on Piscina runs + maxQueue 2000→200** with 503 Retry-After. `db/worker-pool.ts:33-39`. (REL-022)
- [x] ~~SEC-M51. **TOTP AES-256-GCM HMAC-based KDF + version AAD.** `auth.routes.ts:40, 45` + `super-admin.routes.ts:94, 103`. (CRYPTO-M01, 02)~~ — migrated to DONETODOS 2026-04-17 (auth.routes.ts scope only; super-admin.routes.ts still pending).
- [ ] SEC-M57. **Reject control/RTL codepoints** in customer names/notes/tags. `customers.routes.ts`. (LOGIC-018)
- [ ] SEC-M61. **user_permissions fine-grained capability table** (replace role='admin' grab-bag). (LOGIC-017)
### LOW

- [x] ~~SEC-L2. **Portal phone lookup full-normalized equality** instead of SQL LIKE suffix. `portal.routes.ts:443-464, 539-565`. (P3-AUTH-23)~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-L8. **Node engines tighten `>=22.11.0 <23`** + `engine-strict=true`.~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-L18. **Per-tenant failure circuit on cron handlers.** `index.ts:1524-1761`. (REL-029)~~ — migrated to DONETODOS 2026-04-17.
- [x] ~~SEC-L24. **`/api/v1/info` auth-gate in multi-tenant** (leaks LAN IP — **verified live** Tailscale 100.x). `index.ts:868-878`. (PUB-020 / LIVE-08)~~ — migrated to DONETODOS 2026-04-16.
### Uncertain overlaps — verify before starting (human review)

- AZ-019 (SMS inbound-webhook forge) — verified.jsonl rejected as CRITICAL (drivers fail-closed). Latent: `getSmsProvider` not tenant-scoped. Possibly overlap AUD-M22/23/24 in DONETODOS.md.
- PROD12 (PIN 1234) ↔ BH-S006 / SEC-H15 — same default PIN. Keep one.
- PROD15 (rate limit signup / forgot-password) ↔ SEC-H85 CAPTCHA — both needed (rate limit + captcha complementary).
- PROD29 (SSRF audit) ↔ SEC-H92 / SEC-H93 — consolidate under PROD29 or split.
- PROD32/33/34 (HSTS, cookies, CSP) ↔ SEC-H89 — review merge.
- PROD44 (super-admin auth separate check) ↔ SEC-H105 — subtask.
- TS1/TS2 (tenant-owned Stripe) ↔ SEC-C3 / SEC-M36 — adjacent, keep separate.
- AUD-M19 (LRU pool eviction refcounting) ↔ SEC-H124 — dedupe.
- AUD-L19 (super-admin TOTP replay) ↔ SEC-M3/M4 — dedupe.
- SA1-2 (localStorage token storage) ↔ SEC-H61 — consolidate.
- AUD-20260414-H4 (Android cert pins) ↔ SEC-H99 — same placeholder-pin finding; dedupe.

### Phase 4 live-probe positive controls (no action — reference only)

Verified working. Not TODOs.

- JWT `algorithms:['HS256']` + iss/aud pinned on every verify.
- Stripe webhook signature + 300s replay window + INSERT OR IGNORE idempotency (forge rejected 400).
- Helmet HSTS `max-age=63072000 includeSubDomains preload` + CSP + Referrer-Policy + Permissions-Policy.
- bcrypt cost 12 users / 14 super-admins; constant-time password compare with dummy-hash + 100ms floor.
- DB-backed rate limits (migration 069) SURVIVE server restart (login 429 persisted 3 restarts). (LIVE-06)
- POS `/transaction` single `adb.transaction()` with `expectChanges` guards.
- Gift-card redeem guarded atomic UPDATE (no double-spend).
- Store-credit decrement guarded atomic UPDATE.
- `counters.allocateCounter` transactional `UPDATE...RETURNING`.
- `stripe_webhook_events` PK + `INSERT OR IGNORE` (+ SEC-C3 transaction-wrap still needed).
- requestLogger redacts Authorization/Cookie/CSRF/API-key/password/token/pin/auth.
- `/uploads` path traversal blocked 403 (`/uploads/%2e%2e%2f%2e%2e%2f.env` → 403).
- `.env` not HTTP-reachable (all enumerated paths serve SPA fallback).
- `/super-admin/*` localhostOnly fix shipped in commit 585a06c — BH-S002 / LIVE-03 mitigated, external requests 404 (see DONETODOS.md).
