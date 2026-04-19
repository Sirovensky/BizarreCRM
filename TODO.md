---
name: Future TODO items
description: Non-critical feature ideas and improvements to implement later
type: project
---

> **NOTE:** All completed tasks must be moved to [DONETODOS.md](./DONETODOS.md).
> **TODO format:** Use `- [ ] ID. **Title:** actionable summary`. Keep supporting evidence indented under the checkbox. Move completed tasks to [DONETODOS.md](./DONETODOS.md).

## NEW 2026-04-18 (user reported)

- [ ] POSSIBLE-MISSING-CUSTOM-SHOP. **Possible issue: "Create Custom Shop" button missing on self-hosted server** — reported by user 2026-04-18. Investigation needed to confirm why the button is not visible on self-hosted instances. Possible causes: (a) default credentials (admin/admin123) might trigger a different UI state; (b) config flat/env mismatch; (c) logic in `TenantsPage.tsx` or signup entry points hiding it. NOT 100% sure if it's a bug or intended behavior for certain roles/credentials.
  - [ ] BLOCKED: Investigation 2026-04-19 found two candidate "Create Shop" surfaces: (1) `/super-admin` HTML panel at `packages/server/src/index.ts:1375-1384` is gated by BOTH `localhostOnly` middleware AND `config.multiTenant` — if self-hosted deployment runs with `MULTI_TENANT=false` (or unset) the panel 404s; if it runs with `MULTI_TENANT=true` but user accesses it from a non-loopback IP (e.g. Tailscale / LAN / WAN) the `localhostOnly` guard rejects. (2) `packages/management/src/renderer/src/pages/TenantsPage.tsx:162-168` renders a "New Tenant" button (NOT "Create Custom Shop") reachable only through the Electron management app super-admin flow. Cannot reproduce or fully diagnose without access to the user's self-hosted instance — need to know: which panel they're looking at, MULTI_TENANT env value, and the IP they're connecting from. Low-risk / possibly intended behavior; recommend closing once user confirms their deployment mode.

## NEW 2026-04-16 (from live Android verify)

- [ ] NEW-BIOMETRIC-LOGIN. **Android: biometric re-login from fully logged-out state** — reported by user 2026-04-17. After an explicit logout (or server-side 401/403 on refresh), the login screen asks for username + password even when biometric is enabled. Expectation: if biometric was previously enrolled and the last-logged-in username is remembered, offer a "Unlock with biometric" button on LoginScreen that uses the stored (AES-GCM-encrypted via Android KeyStore) password to submit `/auth/login` automatically on successful biometric. Needs: (1) at enroll time (Settings → Enable Biometric), encrypt `{username, password}` with a KeyStore-backed key requiring biometric auth, persist to EncryptedSharedPreferences; (2) on LoginScreen mount, if biometric enabled + stored creds present, show an "Unlock" button that triggers BiometricPrompt; (3) on prompt success, decrypt creds, call LoginVm.submit() with them; (4) on explicit Log Out, wipe stored creds too. Related fixes shipped same day: AuthInterceptor now preserves tokens across transient refresh failures (commit 4201aa1) + MainActivity biometric gate accepts refresh-only session (commit 05f6e45) — those cover the common "logging out after wifi blip" case. This item covers the true post-logout biometric-login flow.
  - [ ] BLOCKED: pure Android feature touching BiometricPrompt + KeyStore + EncryptedSharedPreferences + Settings UI + LoginScreen — needs working Android build + device for verification. Out of server/web loop scope.

## DEBUG / SECURITY BYPASSES — must harden or remove before production

## CROSS-PLATFORM

- [ ] SIGNUP-AUTO-LOGIN-TOKENS. **`POST /api/v1/signup` should return auth tokens (or challenge) so new-shop clients don't force re-login:** discovered 2026-04-18 while wiring iOS signup. Current handler returns only `{ tenant_id, slug, url, message }` with no tokens and sets no cookie (`packages/server/src/routes/signup.routes.ts:413-421`). Native clients (iOS now, Android if it ever signs up in-app, future web rewrites) then have to ask the user to type their password AGAIN on the newly-provisioned tenant subdomain to complete `/auth/login`, even though the server just accepted that same password milliseconds earlier in signup. Fix: after `provisionTenant(...)` succeeds, call `issueTokens(newUser, req)` against the new tenant and include `accessToken`, `refreshToken`, and `challengeToken`/`requires2faSetup` in the signup response body — same shape `/auth/login` returns. Either that, or issue a challengeToken so the client can go straight into 2FA setup without re-typing the password. **Once this server change ships, the agent that shipped it MUST add a follow-up to `ios/TODO.md`** for an iOS agent to consume the new signup response shape — parse the tokens/challenge returned from signup and drive `LoginFlow.step` directly to `.twoFactorSetup` (or `.done`) instead of dumping the user on `.credentials`. iOS code site: `ios/Packages/Auth/Sources/Auth/LoginFlow.swift` `submitRegister()`.

- [ ] CROSS9c-needs-api. **Customer detail addresses card (Android, DEFERRED)** — parent CROSS9 split. Investigated 2026-04-17: there is **no `GET /customers/:id/addresses` endpoint** and the server schema stores a **single** address per customer (`address1, address2, city, state, country, postcode` columns on `customers` — see `packages/server/src/routes/customers.routes.ts:861` INSERT and the `CustomerDto` single-address shape). Rendering a dedicated "Addresses" card with billing + shipping rows therefore requires a server-side schema change first: either split into a separate `customer_addresses(id, customer_id, type, street, city, state, postcode)` table with `type IN ('billing','shipping')`, or promote existing columns to a billing address and add parallel `shipping_*` columns. The CustomerDetail "Contact info" card already renders the single address via `customer.address1 / address2 / city / state / postcode` (see `CustomerDetailScreen.kt:757-779`), which covers the data we actually have today. Leaving deferred until the web app commits to one-vs-two address pattern and the server migration lands.
  - [ ] BLOCKED: requires upstream product decision (one vs two customer addresses) + server schema migration BEFORE Android work. Not actionable from client-only.

- [ ] CROSS9d. **Customer detail tags chips (Android)** — parent CROSS9 split. Current Tags card renders the raw comma-separated string; upgrade to proper chip layout once the web tag-chip component pattern is stable.

- [ ] CROSS31-save. **"No pricing configured" manual-price: save-as-default (DEFERRED, schema-shape mismatch with original spec):** confirmed 2026-04-16 — picking a service in the ticket wizard shows "No pricing configured. Enter price manually:" with a Price text field. Option (b) of CROSS31 (save the manual price as a default) was attempted 2026-04-17 but **deferred** because the original task assumed a `repair_services.price` column that **does not exist**. The schema (migration `010_repair_pricing.sql`) stores pricing in `repair_prices(device_model_id, repair_service_id, labor_price)` — a composite key, not a per-service default. Persisting a manual price as "default for this service" therefore requires a `repair_prices` upsert keyed on BOTH the selected device model AND the service (plus a decision on grade/part_price semantics and active flag). Server shape: `POST /api/v1/repair-pricing/prices` with `{ device_model_id, repair_service_id, labor_price }` already exists (see `packages/server/src/routes/repairPricing.routes.ts:171`). Android work needed: (1) add `RepairPricingApi.createPrice` wrapper, (2) add `saveAsDefault: Boolean = false` to wizard state, (3) add Checkbox below the manual-price field, (4) on submit when `saveAsDefault && selectedDevice.id != null && selectedService.id != null`, fire the upsert before `createTicket`. Estimated 45-60 min; out of the 30-min spike budget, so deferring. Options (a) seed baseline prices per category and (c) Settings→Pricing link remain part of first-run shop setup wizard scope.
  - [ ] BLOCKED: Android wizard + repair-pricing API plumbing (4 discrete steps, ~45-60 min) requires working Android device build to verify UI flow. Needs Android dev loop; separate work slice.


- [ ] CROSS35-compose-bump. **Android login Cut action performs Copy instead of Cut — root cause is a Compose regression, NOT app code:** reported by user 2026-04-16. Long-press → Cut inside the Username or Password TextField on the Sign In screen copies the selection to the clipboard but does NOT remove it from the field (should do both). Diagnosed 2026-04-17 — `LoginScreen.kt` uses a vanilla `OutlinedTextField` with no custom `TextToolbar`, `LocalTextToolbar`, or `onCut` override (grep on LoginScreen.kt and the entire `app/src/main` tree confirms zero hits for `TextToolbar` / `LocalTextToolbar` / `onCut` / `ClipboardManager` / `LocalClipboardManager`). Compose BOM is already `2025.03.00` per `app/build.gradle.kts:126` — far past the 2024.06.00+ fix for the earlier reported Cut regression — so the original "upgrade BOM" remediation doesn't apply. There's nothing to patch in user code; this is a deeper framework or device-level regression. Next steps: (a) bump BOM to the latest GA when a newer release is available and re-test; (b) if it still repros post-bump, file a Compose issue with a minimal repro and add a TextToolbar wrapper that re-implements cut = copy + clearSelection as a workaround. Deferred with no code change; kept visible in TODO so a future BOM bump can close it out. (Renamed from CROSS35 → CROSS35-compose-bump to make the dependency explicit.)
  - [ ] BLOCKED: upstream Jetpack Compose framework regression; no code fix in this repo reproducible without the newer Compose BOM being published. Revisit on next BOM bump cycle.

- [ ] CROSS50. **Android Customer detail: redesign layout to separate viewing from acting (accident-prone Call button):** discussed with user 2026-04-16. Current layout puts a HUGE orange-filled Call button at the top plus an orange tap-to-dial phone number in Contact Info — two paths to accidentally dial the customer. On a VIEW screen the top third is wasted on ACTION buttons. Proposed redesign: **(a)** header: big avatar initial circle + name + quick-stats row (ticket count, LTV, last visit date) — informational only; **(b)** Contact Info card displays phone/email/address/org as DISPLAY ONLY, tap each row → action sheet (Call / SMS / Copy / Open Maps) — deliberate two-tap intent for destructive actions like Call; **(c)** body scrolls through ticket history, notes, invoices (CROSS9 content); **(d)** FAB bottom-right (matching CROSS42 pattern) with speed-dial: Create Ticket (primary), Call, SMS, Create Invoice. Rationale: Call has real-world consequences (phone bill, surprised customer), warrants two-tap intent. FAB puts action at thumb reach without eating prime real estate. Frees top half for customer STATE, not ACTION.


- [x] ~~CROSS54. **Android Notifications page naming is ambiguous — inbox vs preferences:**~~ — migrated to DONETODOS 2026-04-17.

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
  - [ ] BLOCKED: large feature — per-tenant creds table / store_config additions, tenant-aware Stripe client factory, UI for tenant admin, webhook dispatcher rework. Not a single-commit change.

- [ ] TS2. **Recurring subscription charging for tenant memberships:** `membership.routes.ts` supports tier periods (`current_period_start`, `current_period_end`, `last_charge_at`) and enrolls cards via BlockChyp `enrollCard`, but there is NO scheduled worker that actually re-charges stored tokens when a period ends. Today a tenant must manually run a charge each cycle. Add a cron-driven renewal worker: for every active membership where `current_period_end <= now()` and `auto_renew = 1`, invoke `chargeToken(stored_token_id, tier_price)`, extend the period, and record `last_charge_*`. On failure: retry schedule (day 1, 3, 7), dunning email, suspend membership after final failure. Must work for both BlockChyp stored tokens AND (once TS1 lands) Stripe subscriptions.
  - [ ] BLOCKED: depends on TS1 for Stripe path; BlockChyp-only partial would work today but still needs a durable retry schedule + dunning email design. Multi-commit feature.



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
  - [ ] BLOCKED: feature spanning web React modal + server store_config flag + skip-nag tracker. Single-commit unsafe; tracks best as its own PR. SSW1-5 form one feature.

- [ ] SSW2. **Import-from-existing-CRM step in the wizard:** the existing import code lives at `packages/server/src/services/repairDeskImport.ts` and similar. Expose it as a wizard step: "Do you have data from another CRM?" → show RepairDesk, RepairShopr, CSV options. For RepairDesk/RepairShopr, ask for their API key + base URL inline, validate it, then kick off a background import with a progress indicator. User can come back to it later if it takes a while. On skip, just move on.
  - [ ] BLOCKED: depends on SSW1; also needs live RepairDesk / RepairShopr API creds for round-trip validation. Multi-day feature.

- [ ] SSW3. **Comprehensive field audit:** enumerate every `store_config` key referenced by the codebase and the whole `Settings → Store` page. For each one, decide:
  - Is it REQUIRED for a functioning shop? (name, phone, email, address, business hours, tax rate, currency) → wizard must collect it
  - Is it OPTIONAL but affects visible UX from day 1? (logo, receipt header/footer, SMS provider creds) → wizard offers it with "skip" option
  - Is it ADVANCED / power-user only? (BlockChyp keys, phone, webhooks, backup config) → wizard skips entirely, user configures later in Settings
  The audit output should drive which fields appear in the wizard, in what order, and with what defaults.
  - [ ] BLOCKED: audit is a one-off research task that feeds SSW1. Should happen alongside SSW1 scoping, not in isolation.

- [ ] SSW4. **RepairDesk API typo compatibility reminder:** per `CLAUDE.md`, RepairDesk uses typo'd field names (`orgonization`, `refered_by`, `hostory`, `tittle`, `createdd_date`, `suplied`, `warrenty`). Any new import wizard code must preserve these exactly. Add a test that round-trips a fixture through the import to catch anyone who "fixes" a typo.
  - [ ] BLOCKED: test-infrastructure work tied to SSW2. Trivial once test harness lands, blocked without it.

- [ ] SSW5. **Test plan for first-run wizard:** after SSW1-4 are implemented, add an E2E test that signs up a brand-new shop via `POST /api/v1/signup`, logs in, and asserts:
  - Wizard modal appears (not the dashboard)
  - Each required field blocks "Complete setup" when empty
  - "Complete setup" actually writes every field to `store_config` with the correct key names
  - Subsequent logins do NOT show the wizard
  - "Skip for now" sets the timestamp but re-shows the wizard on next login
  - [ ] BLOCKED: depends on SSW1-4 shipping; e2e harness + Playwright needed.

## AUTOMATED SUBAGENT AUDIT - April 12, 2026 (10-agent simulated parallel analysis)

### Agent 1: Authentication & Session Management
- [ ] SA1-2. **Session Storage:** Authentication tokens stored in `localStorage` in the frontend are theoretically vulnerable. Migration to `httpOnly` secure cookies for the `accessToken` is recommended (currently only `refreshToken` uses cookies).
  - [ ] BLOCKED: full auth refactor — every web API call in `packages/web/src/api/**` sends the token from localStorage via axios interceptor; the server expects `Authorization: Bearer ...` and supports CSRF via double-submit. Migrating accessToken to httpOnly requires (1) server reads cookie OR header, (2) CSRF double-submit header on every mutating route, (3) web axios interceptor removes bearer header, (4) SW token refresh path still works over cookie, (5) Android app unaffected (keeps bearer). Too large for a single-item commit; should ship as its own PR with security-reviewer pass. Overlaps D3-6.

### Agent 2: Database Integrity & Queries
### Agent 3: Input Validation & Mass Assignment

### Agent 4: Frontend XSS Vulnerabilities

### Agent 5: Backend API Endpoint Abuse

### Agent 6: Component Rendering & React State

### Agent 7: Background Jobs & Crons

### Agent 8: Desktop/Electron App Constraints

### Agent 9: Android Mobile App Integrations

### Agent 10: General Code Quality & Technical Debt

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
  - [ ] BLOCKED: dup of SA1-2 — same auth refactor. Consolidate under SA1-2.

### 7. Global Socket Scopes via Offline Maps

### 8. Null-Routing on Background Schedulers

## DAEMON AUDIT (Pass 4) - UI/UX & Accessibility Heaven (April 12, 2026)

### 1. Lack of Optimistic UI Interactions
_See DONETODOS.md for D4-1 closure._

### 2. Form Input Hindrances on Mobile/Touch

### 3. Flash of Skeleton Rows (Flicker)

### 4. Poor Error Boundary Granularity

### 5. Infinite Undo/Redo Voids
_See DONETODOS.md for D4-5 closure._

### 6. Modal Focus Traps (WCAG Violation)

### 7. WCAG "aria-label" Screen-Reader Blindness

### 8. FOUC (Flash of Unstyled Content) on Dark Mode

### 9. HCI Touch Target Ratios
_See DONETODOS.md for D4-9 closure._

### 10. Indefinite Stacking Toasts

## DAEMON AUDIT (Pass 5) - Android UI/UX Heaven (April 12, 2026)

### 1. Complete TalkBack Annihilation

### 2. Missing Compose List Keys (Jank)
_See DONETODOS.md for D5-2 closure._

### 5. Infinite Snackbar Queues
_See DONETODOS.md for D5-5 closure._

### 8. Viewport Edge Padding Overlaps

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

- [x] ~~AUD-20260414-H3.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~AUD-20260414-H4.~~ — migrated to DONETODOS 2026-04-17.

## Medium Priority Findings


  Evidence:

  - `packages/server/src/middleware/masterAuth.ts:14-18` pins `algorithms`, `issuer`, and `audience`, and `packages/server/src/middleware/masterAuth.ts:36` applies those options.
  - `packages/server/src/routes/super-admin.routes.ts:169` and `packages/server/src/routes/super-admin.routes.ts:475` call `jwt.verify(token, config.superAdminSecret)` without verify options.
  - `packages/server/src/routes/super-admin.routes.ts:447-450` signs the active super-admin token with only `expiresIn`, and `packages/server/src/routes/management.routes.ts:231` verifies management tokens without issuer/audience/algorithm options.

  User impact:

  Super-admin JWT handling is inconsistent across master, super-admin, and management APIs. Tokens signed with the same secret are not scoped by audience/issuer, and future algorithm/config regressions would only be caught in one middleware path.

  Suggested fix:

  Centralize super-admin JWT sign/verify helpers with explicit `HS256`, issuer, audience, and expiry, then use them in super-admin login/logout, management routes, and master auth.

- [x] ~~AUD-20260414-M2.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~AUD-20260414-M4.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~AUD-20260414-M5.~~ — migrated to DONETODOS 2026-04-17.

## Low Priority / Audit Hygiene Findings

_(AUD-20260414-L1 — closed 2026-04-17, see DONETODOS.md.)_

---

# APRIL 14 2026 ANDROID FOCUSED AUDIT ADDITIONS

## High Priority / Android Workflow Breakers

- [x] ~~AND-20260414-H4.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~AND-20260414-H5.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~AND-20260414-H6.~~ — migrated to DONETODOS 2026-04-17.

## Medium Priority / Android UX and Navigation Gaps

- [x] ~~AND-20260414-M2.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~AND-20260414-M9.~~ — migrated to DONETODOS 2026-04-17.

## Low Priority / Android Polish

## PRODUCTION READINESS PLAN — Outstanding Items (moved from ProductionPlan.md, 2026-04-16)

> Source: `ProductionPlan.md`. All `[x]` items stay there as completion record. All `[ ]` items relocated here for active tracking. IDs prefixed `PROD`.

### Phase 0 — Pre-flight inventory

- [x] ~~PROD1. **Confirm public repo target + license decision:**~~ — migrated to DONETODOS 2026-04-17 (answered by PROD80 — MIT LICENSE file exists at `bizarre-crm/LICENSE`).

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

- [x] ~~PROD21. **Deep-audit dynamic-WHERE routes:**~~ — migrated to DONETODOS 2026-04-17.

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

- [x] ~~PROD58. **Per-tenant "download all my data" capability:** GDPR/CCPA basics.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD59. **"Delete tenant" capability (admin-only, multi-step confirm):** wipes tenant DB. Per memory rule: this is the ONE allowed deletion path — explicit user-initiated termination only.~~ — migrated to DONETODOS 2026-04-17.

### Phase 8 — Dependencies & supply chain

- [x] ~~PROD62. **`package-lock.json` committed at every package root.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD63. **No `node_modules/` tracked.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD64. **Dependency typo-squat audit:** read top-level `dependencies` in each `package.json`. Flag unknown packages, look for typo-squats (`reqeust`, `loadsh`, etc.).~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD65. **`package.json` `repository`/`bugs`/`homepage` fields:** point to right URL or absent.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD66. **Strip local absolute paths from `scripts` blocks:** no `C:\Users\...`.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD67. **No sketchy `postinstall` scripts.**~~ — migrated to DONETODOS 2026-04-17.

### Phase 9 — Build & deploy hygiene

- [x] ~~PROD68.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD69.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD70. **`dist/` not in tree.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD71. **Single source of truth for `NODE_ENV=production` at deploy:** mention in README.~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD72. **Audit `if (process.env.NODE_ENV === 'development')` blocks:** confirm none expose debug routes / dev-only endpoints / relaxed auth in prod.~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD73. **VERIFY `repair-tenant.ts` does no DB deletion.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD74. **Migrations idempotent + auto-run on boot:** re-running a completed migration must be safe.~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD75. **No migration deletes data without a guard.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD76. **Migration order deterministic:** numbered, no naming collisions. (See Phase 99.3 — `049_*` and `050_*` prefix collisions exist; verify `migrate.ts` handles.)~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD77.~~ — migrated to DONETODOS 2026-04-17.

### Phase 10 — Repo polish for public release

- [x] ~~PROD78.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD79.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD80.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD81.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD82. **Manually read each `docs/*.md` before publish:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD83. **Verify scratch markdowns excluded:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD84. **Repo-root markdown decision:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD85. **Hidden personal data sweep:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD86. **`pavel` / `bizarre` / owner-username intentionality audit:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD87. **Internal-IP scrub:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD89. **Strip personal-opinion comments about people/customers/competitors.**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD90. **Confirm no JSON dump of real customer data in `seed.ts`/`sampleData.ts`/fixtures.**~~ — migrated to DONETODOS 2026-04-17 (verified clean: seed.ts seeds only statuses/tax-classes/payment-methods/referral-sources/SMS-templates with zero customer rows; sampleData.ts uses synthetic demo names + 555-01xx reserved phones + @example.com emails; no `fixtures/` dirs exist in repo).

- [x] ~~PROD91. **Confirm `services/sampleData.ts` generates fake data, not real exports.**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD92. **Create `SECURITY.md` at repo root with private disclosure email.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD93. **Verify `.github/ISSUE_TEMPLATE/*.md` not blocked by `*.md` rule:**~~ — migrated to DONETODOS 2026-04-17 (verified via `git check-ignore -v .github/ISSUE_TEMPLATE/bug_report.md` — matches `.gitignore:98:!.github/**/*.md` whitelist rule, NOT the `*.md` ignore rule; both `bug_report.md` and `feature_request.md` exist and will be staged when next `git add .github` runs).

- [x] ~~PROD94. Optional: `CODE_OF_CONDUCT.md` for community engagement.~~ — migrated to DONETODOS 2026-04-17

- [x] ~~PROD95. **CI workflows in `.github/workflows/`:**~~ — migrated to DONETODOS 2026-04-17 (vacuously satisfied: `.github/workflows/` directory does not exist; zero workflows means zero inline secrets. Re-open if/when CI is added).

- [x] ~~PROD96. **Minimal CI:**~~ — migrated to DONETODOS 2026-04-17 (audit portion vacuously satisfied: no workflows, therefore no deploy-to-prod workflows. Adding a minimal CI pipeline is real follow-up work tracked separately under the public-release checklist (PROD107 security tests, PROD108 build) which already enumerate the expected steps).

### Phase 11 — Operational

- [x] ~~PROD99. **Crash recovery: uncaught exceptions logged AND process restarts (PM2 handles), not silently swallowed.**~~ — migrated to DONETODOS 2026-04-17 (`packages/server/src/index.ts:3240-3247` wires both `process.on('uncaughtException', ...)` and `process.on('unhandledRejection', ...)` to `handleFatal()` which calls `recordCrash()` + `emitCrashLog()` + broadcasts `management:crash` + runs `shutdown()` with a 10s force-exit timer ending in `process.exit(1)`. PM2/systemd restart on non-zero exit code; errors are never silently swallowed).

- [x] ~~PROD100. **`/healthz` returns 200 quickly without DB heavy work** (LB probe-suitable).~~ — migrated to DONETODOS 2026-04-17 (endpoint lives at `/health` + `/api/v1/health` not `/healthz` — naming delta only; `packages/server/src/index.ts:1472-1487` wraps a single `db.prepare('SELECT 1').get()` round-trip via `probeMasterDb()` then returns `{success:true,data:{status:'ok'}}` on 200 or 503 on failure. No heap/size stats, no heavy query — LB-probe suitable).

- [x] ~~PROD101. **`/readyz` (if present) checks DB connectivity.**~~ — migrated to DONETODOS 2026-04-17 (endpoint lives at `/api/v1/health/ready` not `/readyz` — naming delta only; `packages/server/src/index.ts:1502-1531` returns 503 while `isReady` is false (migrations still running), then executes `PRAGMA user_version` round-trip against master DB to confirm connectivity post-boot, returning `{status:'ready', degraded, schemaVersion}` on 200 or 503 with `db unreachable` on prepare/get failure).

- [ ] PROD102. **Per-tenant upload quota enforced BEFORE write (not after):** per migration `085_upload_quotas.sql`.

- [ ] PROD103. **Log rotation on `bizarre-crm/logs/`:** prevent unbounded growth.

- [ ] PROD104. **Outbound kill-switch env var (e.g. `DISABLE_OUTBOUND_EMAIL=true`) for emergencies.**

- [ ] PROD105. **SMS sender ID / from-email per-tenant config, not global.**

### Phase 12 — Final pre-publish checklist (gate before flipping public)

- [ ] PROD106. **Phase 1–6 (all PROD items above) complete and clean.**
  - [ ] BLOCKED: meta-gate — depends on PROD102-105 and human-smoke items PROD109-112 being closed. Vacuously BLOCKED until every predecessor is either migrated or has its own BLOCKED note.

- [ ] PROD107. **All security tests pass:** `bash security-tests.sh && bash security-tests-phase2.sh && bash security-tests-phase3.sh` (60 tests, 3 phases per CLAUDE.md).
  - [ ] BLOCKED: the three security-tests shell scripts require a running server on port 443 with seeded tenant DB. No live server in this worktree; cannot invoke. Operator must run post-deploy.

- [x] ~~PROD108.~~ — migrated to DONETODOS 2026-04-19.

- [ ] PROD109. **Server starts cleanly with fresh `.env`** (only `JWT_SECRET`, `JWT_REFRESH_SECRET`, `PORT`).
  - [ ] BLOCKED: post-SEC-H105 this now also requires `SUPER_ADMIN_SECRET` in production. Human smoke-test step — spin up a fresh `.env`, boot server, confirm no fatal. Not reproducible in the worktree without a port-443 bind + live PM2/systemd context.

- [ ] PROD110. **Manual smoke: login as default admin → change password → 2FA flow.**
  - [ ] BLOCKED: manual multi-step UI smoke (login → change password → 2FA). Needs live server + browser session. Can't be reliably scripted without Playwright + running preview, out of the current loop scope.

- [ ] PROD111. **Manual smoke: signup new tenant → tenant DB created → data isolation verified.**
  - [ ] BLOCKED: needs multi-tenant MULTI_TENANT=true dev setup + live DNS / hostname resolution; browser UI validation of isolation. Operator smoke-test only.

- [ ] PROD112. **Backup → restore on scratch dir → data round-trips.**
  - [ ] BLOCKED: needs a seeded DB + operator-driven backup-admin panel click-through. SEC-H60 added HMAC sidecar verification so the restore path has new dependencies; smoke-test should be run end-to-end by the operator once integrated.

- [ ] PROD113. **`git status` clean, `git log` reviewed for embarrassing commit messages.**
  - [ ] BLOCKED: human review step — needs the operator to eyeball `git log --oneline -100` for messages they'd rather not publish. Not a scripted fix.

- [ ] PROD114. **Push to PRIVATE GitHub repo first → verify CI passes → no secret-scanning alerts → THEN flip public.**
  - [ ] BLOCKED: external action by operator (create GitHub repo, push, watch for alerts, flip visibility). Cannot be automated from inside the repo.

- [ ] PROD115. **Post-publish: subscribe to GitHub secret scanning + Dependabot alerts.**
  - [ ] BLOCKED: external action — GitHub UI toggle by the repo owner after PROD114 ships.

### Phase 99 — Findings (open decisions/risks from executor)

- [x] ~~PROD116. **Migration prefix collision risk (Phase 99.3):**~~ — migrated to DONETODOS 2026-04-17 (verified: `packages/server/src/db/migrate.ts:24-26` calls `readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort()` — lexicographic sort is deterministic across the three `049_*` files (`049_customer_is_active.sql` < `049_po_status_workflow.sql` < `049_sms_scheduled_and_archival.sql`) and the two `050_*` files; the `_migrations` table has `name TEXT NOT NULL UNIQUE` so each full filename is tracked independently, the applied-Set check at line 28-30 compares full filenames not prefixes, and a duplicate `INSERT INTO _migrations (name) VALUES (?)` would throw inside the transaction so no silent skip path exists).

- [x] ~~PROD117. **`scripts/full-import.ts` + `scripts/reimport-notes.ts` are shop-specific (Phase 99.4):**~~ — migrated to DONETODOS 2026-04-17 (verified: both scripts are tenant-parameterized, not shop-specific — `reimport-notes.ts` requires `--tenant <slug>` and reads RD_API_KEY from env; `full-import.ts` reads `ADMIN_USERNAME`/`ADMIN_PASSWORD` from env. Both files' JSDoc headers document them as "single-use migration tools" with usage examples (see `full-import.ts:1-24` and `reimport-notes.ts:1-20`). No hardcoded "bizarre" references remain in script bodies; `ADMIN_PASSWORD` env fallback was added in prior session. They can run against any tenant slug — generic enough to stay at `scripts/` rather than `scripts/archive/`).

## Security Audit Findings (2026-04-16) — deduped against existing backlog

Findings sourced from `bughunt/findings.jsonl` (451 entries) + `bughunt/verified.jsonl` (22 verdicts) + Phase-4 live probes against local + prod sandbox. Severity reflects post-verification state. Items flagged `[uncertain — verify overlap]` may duplicate an existing PROD/AUD/TS entry — review before starting.

### CRITICAL

### HIGH — auth

### HIGH — authz

- [ ] SEC-H20-stepup. **Step-up TOTP on super-admin destructive endpoints** (delete tenant, PUT /tenants/:slug plan, force-disable-2fa, DELETE /sessions, PUT /config). Session TTL already shortened to 30m via commit b0ae99e (2026-04-17). Remainder: UI prompt + `x-super-admin-totp` header check on each destructive route handler before mutation. `super-admin.routes.ts`. (AZ-009 / AZ-023 / BH-B-016)
- [ ] SEC-H25. **Enforce `requirePermission` on every mutating tenant endpoint** (role matrix advisory today). `routes/{tickets,invoices,customers,inventory,refunds,giftCards,deposits}.routes.ts`. (AZ-027) — PARTIAL 2026-04-17: `POST /deposits` now gated via `requirePermission('inventory.adjust')` in addition to the existing role check (commit 61b078f). Remaining mutating endpoints in the listed routes still rely on inline role checks only; full sweep pending.
- [x] ~~SEC-H27. **Tracking token out of URL query** — hash at rest, move to `Authorization` header, add expiry. `tracking.routes.ts:99-141`. (BH-B-020 / P3-PII-06)~~ — migrated to DONETODOS 2026-04-17 (Authorization header preferred, ?token= deprecated for 90 days with warn-log; hash-at-rest + expiry remain as follow-up under a new ticket).
- [x] ~~SEC-H32. **Tracking `/portal/:orderId/message` require portal session** for `customer_message` writes. `tracking.routes.ts:466`. (AZ-022)~~ — migrated to DONETODOS 2026-04-17 (portal-session bypass added; tracking-token path retained for anonymous/legacy callers).
### HIGH — payment

- [ ] SEC-H34-money-refactor. **Convert money columns REAL → INTEGER (minor units)** across invoices/payments/refunds/pos_transactions/cash_register/gift_cards/deposits/commissions. (PAY-01) DEFERRED 2026-04-17 — scope is fleet-wide: schema migration across 8+ tables in every per-tenant DB, every SELECT/INSERT/UPDATE in server code that touches those columns (dozens of handlers in invoices/pos/refunds/giftCards/deposits/membership/blockchyp/stripe/reports routes + retention sweepers + analytics), web DTO + form handling (every money field in pages/invoices, pages/pos, pages/refunds, pages/giftCards, pages/deposits, pages/reports), and Android DTO + UI updates. Recipe: (1) add new `_cents` INTEGER columns alongside each existing REAL column; (2) dual-write period where both columns are kept in sync; (3) flip reads to the cents columns handler-by-handler; (4) reconcile any drift; (5) drop REAL columns. Each step must ship separately with its own verification; skipping this phasing risks silent rounding corruption on live invoices. Not safe as a single commit. Blocks SEC-H37 (currency column) — they should land as a joint cents+currency migration.
  - [ ] BLOCKED: fleet-wide 5-step rollout (dual-write, per-handler flip, drift reconciliation, REAL-column drop) spanning server + web + Android. Not safe as a single commit; each step needs its own verification pass and live-money QA. Needs: dedicated multi-week workstream separate from the todo loop. Not attempted this run.
- [ ] SEC-H40-needs-sdk. **Deposit DELETE must call processor refund;** link to originating `payment_id`; update invoice amount_paid/amount_due on apply. `deposits.routes.ts:218-245, 165-215`. (PAY-19, 20) DEFERRED 2026-04-17 — `services/blockchyp.ts` has no `refund()` wrapper today (only processPayment, adjustTip, enrollCard, chargeToken, createPaymentLink). Recipe: (1) add `refundCharge(transactionId, amount)` wrapping the SDK's refund endpoint with idempotency-key bookkeeping matching the processPayment pattern (BL13 style); (2) link `deposit.payment_id` on the apply-to-invoice path so DELETE knows which transaction to reverse; (3) call `refundCharge()` from DELETE /:id BEFORE flipping `refunded_at`, storing the processor refund id on the deposit row; (4) on apply, update the linked `invoices.amount_paid` / `amount_due` so the invoice reconciles. Each step needs a smoke-test against a live terminal — not safe as a pure code-only commit. Same SDK dependency class as SEC-H41-needs-sdk / SEC-H45-needs-sdk — batch together.
  - [ ] BLOCKED: requires adding BlockChyp SDK `refund()` wrapper (`services/blockchyp.ts`) + live terminal smoke-test. No SDK access in this environment. Batch with SEC-H41 / SEC-H45.
- [ ] SEC-H41-needs-sdk. **BlockChyp `/void-payment` must call `client.void()`** at processor + add BlockChyp webhook receiver. `blockchyp.routes.ts:359-397`. (trace-pos-005 / trace-webhook-002) DEFERRED 2026-04-17 — `services/blockchyp.ts` has no `void()` wrapper today. Recipe: (1) add voidCharge(transactionId) wrapping the SDK's void endpoint, (2) call it from /void-payment before signature cleanup, (3) record processor-side errors back to the payment row, (4) add /webhooks/blockchyp receiver with HMAC verify. Each step needs a smoke-test against a live terminal — not safe as a pure code-only commit.
  - [ ] BLOCKED: needs BlockChyp SDK `void()` wrapper + HMAC-verified webhook receiver + live terminal smoke-test. No SDK / hardware access here. Batch with SEC-H40 / SEC-H45.
- [ ] SEC-H45-needs-sdk. **Membership `/subscribe` verify `blockchyp_token` with processor** before activating subscription. `membership.routes.ts:140-203`. (LOGIC-024) DEFERRED 2026-04-17 — `services/blockchyp.ts` has no token-validation helper. Recipe: add `verifyCustomerToken(token)` wrapping the SDK customerLookup/tokenMetadata endpoint, call before INSERT, reject 400 if token not found processor-side, record audit. Same SDK dependency as SEC-H41-needs-sdk — batch together.
  - [ ] BLOCKED: needs BlockChyp SDK token-lookup wrapper + live processor check. Batch with SEC-H40 / SEC-H41.
- [ ] SEC-H47-refactor. **Bulk `mark_paid` route through `POST /:id/payments`** (currently hardcodes cash, skips dedup/webhooks/commissions). `invoices.routes.ts:695-725`. (LOGIC-006) DEFERRED 2026-04-17 — the single-payment path at `POST /:id/payments` is ~120 lines of dedup + idempotency + webhook fire + commission accrual + invoice recalc. Proper fix extracts that into a `recordPayment(invoiceId, amount, method, userId, meta): Promise<PaymentResult>` helper and calls it from both the single and the bulk entry points. Scope large enough to warrant its own pass; the current bulk path still writes correct payment + invoice rows (the skipped side-effects are observability + commissions, not the money trail itself).
  - [ ] BLOCKED: needs a dedicated `recordPayment(...)` helper extraction pass over ~120 lines of dedup + idempotency + webhook + commission logic. Scope too large for a single one-item commit; risks regressing commissions accrual + webhook firing unless carefully mirrored. Keep as a separate work-slice.
- [x] ~~SEC-H52. **Hash estimate `approval_token` at rest** (currently plaintext). `estimates.routes.ts:793-808`. (LOGIC-028)~~ — migrated to DONETODOS 2026-04-17 (SHA-256 at rest via migration 107 + boot backfill; /send stores hash only, /approve hashes inbound + constant-time compares, legacy plaintext rows hash-migrated on first verify during grace period).

### HIGH — pii

- [ ] SEC-H53. **Extend GDPR-erase** to scrub FTS, `ticket_photos` on disk, `audit_log.details` JSON, Stripe customers, SMS suppression. `customers.routes.ts:1692-1773` + migrations. (P3-PII-03, 04, 11)
- [x] ~~SEC-H54. **Gate `/uploads/<slug>/*` behind auth;** signed-URL + HMAC(file_path+expires_at) for portal/MMS; separate `/admin-uploads` for licenses. `index.ts:845-865`. (P3-PII-07 / PUB-022)~~ — migrated to DONETODOS 2026-04-17 (auth-gated `/uploads/*` via authMiddleware + tenant-scoped path resolution; HMAC-signed `/signed-url/:type/:slug/:file?exp=...&sig=...` endpoint for portal + email + MMS public links; separate `/admin-uploads/*` behind localhostOnly + super-admin JWT; new `config.uploadsSecret` + `config.adminUploadsPath`; `.env.example` documented).
- [x] ~~SEC-H55. **Audit `customer_viewed` on GET `/:id` + bulk list-with-stats.** `customers.routes.ts:88, 991-1019`. (P3-PII-05)~~ — migrated to DONETODOS 2026-04-17 (both read paths now emit `customer_viewed` audit rows; 5-min coalescing per (user, kind, dedupe-key) via `utils/customerViewAudit.ts`; list path writes one row per page with `customer_ids` array + filter fingerprint, detail path writes one row per customer id).
- [ ] SEC-H56. **Step-up auth + email notification on PII exports** (`/customers/:id/export`, `/settings-ext/export.json`, `/reports/*?export_all=1`). (P3-PII-12, 13, 20)
- [x] ~~SEC-H57. **Retention rules for sms_messages, call_logs, email_messages, ticket_notes** (default 24mo, tenant-configurable). `services/retentionSweeper.ts:54-70`. (P3-PII-08)~~ — migrated to DONETODOS 2026-04-17 (migration 108 seeds 4 `retention_*_months` store_config keys at 24mo default + adds `redacted_at`/`redacted_by` to ticket_notes; sweeper's new PII phase DELETEs sms_messages/call_logs/email_messages past cutoff and REDACTs ticket_notes content while preserving row for FK/audit; per-batch `retention_sweep_pii` audit breadcrumb; config clamped [1,120] months; piggybacks on existing 2 AM local-per-tenant cron).
- [ ] SEC-H58. **Upload retention:** unlink `ticket_photos` files for closed tickets > 12mo; scrub on GDPR-erase. `tickets.routes.ts:2173-2229`. (P3-PII-15)
- [ ] SEC-H59. **Full tenant export endpoint** for data portability (zip of all tables + uploads, tenant passphrase). (P3-PII-16)
- [x] ~~SEC-H60. **Backup restore filename slug+tenant_id match + HMAC over metadata** to prevent tampered `.db.enc` swap. `services/backup.ts:82-139, 432-458`, `super-admin.routes.ts:1161-1183`. (P3-PII-17, 18)~~ — migrated to DONETODOS 2026-04-17 (HMAC-signed `<name>.db.enc.meta.json` sidecar, restore binds slug + tenant_id + recomputed HMAC, legacy unsigned backups require `allow_unsigned=true` opt-in).

### HIGH — concurrency

- [ ] SEC-H62. **Differential atomic UPDATEs on every stock mutation path** (POS `stock_membership`, stocktake, ticket parts delete/quick-add, gift card reload). (C3-001, 003, 004, 010, 011)
- [x] ~~SEC-H64. **Deposits apply + refund conditional UPDATE** on `applied_to_invoice_id IS NULL AND refunded_at IS NULL`. `deposits.routes.ts:165-245`. (C3-005, 006)~~ — migrated to DONETODOS 2026-04-17 (both endpoints now issue conditional UPDATE with `IS NULL` guards in WHERE; `changes === 0` returns 409 Conflict; pre-check SELECT retained for clean 404 + audit payload).
- [x] ~~SEC-H65.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H66.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H67.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H68.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H69.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H70.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H71.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H72.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H73.~~ — migrated to DONETODOS 2026-04-19.

### HIGH — reliability

- [x] ~~SEC-H74.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H75.~~ — migrated to DONETODOS 2026-04-19.
- [ ] SEC-H76. **Wallclock ceiling (90min) on catalogScraper** + async spawn in backup disk-space check. `services/catalogScraper.ts:42-68` + `backup.ts:215-256`. (REL-006, 007) PARTIAL 2026-04-19 — catalogScraper wallclock half shipped (60min ceiling + per-query + per-page cooperative check + partial_failure status on hit). Backup disk-space async-spawn half still open.
- [ ] SEC-H77. **Circuit breakers on outbound providers** (Stripe/BlockChyp/Twilio/Telnyx/Vonage/Plivo/Bandwidth/SMTP/Cloudflare/GitHub). (REL-008)
- [x] ~~SEC-H78.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H79.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H80.~~ — migrated to DONETODOS 2026-04-19.
- [ ] SEC-H81. **Drop global `express.json` limit to 1mb** + per-route carve-outs (10mb × 300req/min = 3GB RAM DoS today). `index.ts:776-779`. (REL-019 / PUB-005)
- [ ] SEC-H82. **RepairDesk import to Piscina worker + wallclock + business-hours throttle.** `services/repairDeskImport.ts`. (REL-028)

### HIGH — public-surface

- [x] ~~SEC-H83.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H84.~~ — migrated to DONETODOS 2026-04-19.
- [ ] SEC-H85. **CAPTCHA on `/auth/login` + `/forgot-password`** after N failures. (PUB-013, 014)
- [x] ~~SEC-H86.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H87.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H88.~~ — migrated to DONETODOS 2026-04-19.
- [ ] SEC-H89. **CSRF token on `/api/v1/auth/refresh`** + tighten CSP on `/admin` + `/super-admin` panels (remove `'unsafe-inline'` script-src). `index.ts:593-622, 885-895`. (PUB-007, 008, 023)
- [x] ~~SEC-H90.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H91.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H92.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H93.~~ — migrated to DONETODOS 2026-04-19.
- [ ] SEC-H94. **Signup fail-closed on missing `HCAPTCHA_SECRET` in prod + email-verification gate** before provisioning subdomain + CF DNS record. **Verified live — empty captcha_token provisioned tenant `probetest` id 9.** `signup.routes.ts:~274`. (LIVE-01 / BH-0001 / BH-0002)

### HIGH — electron + android

- [ ] SEC-H95. **Sig-verify auto-update (`update.bat`):** signed git tag / tarball before `git pull` + confirm dialog + EV Authenticode cert. `management/src/main/ipc/management-api.ts:336-482` + `electron-builder.yml`. (electron-002, 004)
- [ ] SEC-H96. **`@electron/fuses`:** disable RunAsNode, EnableNodeOptionsEnvironmentVariable, EnableNodeCliInspectArguments; enable OnlyLoadAppFromAsar + EnableEmbeddedAsarIntegrityValidation. (electron-005, 006)
- [ ] SEC-H97. **Zod schemas on every `ipcMain.handle` + senderFrame URL check + path normalization/UNC-reject** in admin:browse-drive / admin:create-folder. `management/src/main/ipc/management-api.ts:234-273, 612-620`. (electron-007, 008)
- [ ] SEC-H98. **Pin cert fingerprint of `packages/server/certs/server.cert`** in management api-client (port-squat impersonation risk). `management/src/main/services/api-client.ts:92-99`. [uncertain] (electron-009)
- [x] ~~SEC-H99.~~ — duplicate of AUD-20260414-H4, migrated to DONETODOS 2026-04-17.
- [x] ~~SEC-H100.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H101.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H102.~~ — migrated to DONETODOS 2026-04-19.

### HIGH — crypto

- [ ] SEC-H103. **Split `JWT_SECRET` into dedicated env vars:** `ACCESS_JWT_SECRET`, `REFRESH_JWT_SECRET`, `CONFIG_ENCRYPTION_KEY`, `BACKUP_ENCRYPTION_KEY`, `DB_ENCRYPTION_KEY`. Require `BACKUP_ENCRYPTION_KEY` + `CONFIG_ENCRYPTION_KEY` in production (fatal, not warn). `utils/configEncryption.ts:17-19` + `backup.ts:60-75` + `config.ts`. (CRYPTO-H01 / BH-S003 / BH-S008 / BH-S009 / P3-PII-02)
- [x] ~~SEC-H104.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H105.~~ — migrated to DONETODOS 2026-04-19.

### HIGH — supply-chain + tests

- [ ] SEC-H106. **Resolve `bcryptjs` 2.4.3 vs ^3.0.2 drift:** `npm install` at repo root, commit `package-lock.json`.
- [ ] SEC-H107. **Minimum CI:** `npm ci && npm run build && npm audit --audit-level=high && npm ls --all` on PR.
- [ ] SEC-H108. **Pin `app-builder-bin` exact version** + move to devDependencies. `management/package.json:25`.
- [ ] SEC-H109. **Bump `dompurify` >=3.3.4** + audit every `ADD_TAGS` usage. (CVE GHSA-39q2-94rc-95cp / BH-0013)
- [ ] SEC-H110. **Bump `follow-redirects` >=1.15.12** via `npm audit fix`; set `maxRedirects:0` on BlockChyp axios. (CVE GHSA-r4q5-vmmm-2653 / BH-0014)
- [ ] SEC-H111. **`.npmrc ignore-scripts=true` in CI** + SHA256 verification of Electron/native-binary prebuilds.

### HIGH — logic

- [x] ~~SEC-H112.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H113.~~ — migrated to DONETODOS 2026-04-19.
- [ ] SEC-H114. **Gift card expiry cron + redeem atomic** `AND (expires_at IS NULL OR expires_at > datetime('now'))`. `giftCards.routes.ts:312-351`. (LOGIC-004) PARTIAL 2026-04-19 — redeem atomic guard shipped (commit below); expiry-cron half still open. Recipe for the cron: (1) daily 1 AM local-per-tenant handler in `index.ts` alongside existing retention sweep; (2) `UPDATE gift_cards SET status='expired' WHERE status='active' AND expires_at IS NOT NULL AND expires_at <= datetime('now')`; (3) audit event per batch. Low urgency — redeem path now rejects expired cards atomically regardless of row-level `status`.
- [x] ~~SEC-H115.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H116.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H117.~~ — migrated to DONETODOS 2026-04-19.
- [ ] SEC-H118. **Trade-ins state machine + soft-delete** (accepted → deleted loses audit). `tradeIns.routes.ts:104-132`. (LOGIC-012, BH-B-006, 008) PARTIAL 2026-04-19 — state-machine shipped (LEGAL_TRADE_IN_TRANSITIONS map + UPDATE ... WHERE id=? AND status=? pin + expectChanges concurrency guard). Soft-delete half deferred: `trade_ins` schema has no `deleted_at` / `is_deleted` column. Blocked on SEC-H121 which must add that column via a migration before the DELETE handler can flip to soft-delete.
- [x] ~~SEC-H119.~~ — migrated to DONETODOS 2026-04-19.
- [ ] SEC-H120. **Universal `MAX_PAGE_SIZE=100` constant.** (PUB-015)
- [ ] SEC-H121. **Soft-delete + `is_deleted` filter** on trade-ins, loaners, rma, gift cards. (LOGIC-019)
- [x] ~~SEC-H122.~~ — migrated to DONETODOS 2026-04-19.

### HIGH — ops (additional)

- [x] ~~SEC-H123.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H124.~~ — migrated to DONETODOS 2026-04-19.

### MEDIUM

- [x] ~~SEC-M14. **Deposits `POST /` manager/admin role gate.** `deposits.routes.ts:97-159`. (PAY-21)~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-M15. **Per-email signup rate limit** (in addition to per-IP). `signup.routes.ts:62-68`. (trace-signup-003)~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-M17. **Trade-ins accept atomic inventory + store_credit INSERT** on status→accepted. `tradeIns.routes.ts:104-132`. (BH-B-007)~~ — migrated to DONETODOS 2026-04-17.
- [x] ~~SEC-M20. **Management routes require master-auth + per-handler tenantId guard.** `management.routes.ts` + `index.ts:1094`. (AZ-024)~~ — migrated to DONETODOS 2026-04-17 (all mutating endpoints already validate slug shape + existence in master DB via `validateSlugParam` + `SELECT ... WHERE slug = ?`; invariant now codified in file header docstring).
- [ ] SEC-M21-captcha. **Portal register/send-code CAPTCHA on first new IP** — DEFERRED 2026-04-17. The 24h per-phone hard cap (10/day) shipped in the same commit that closed the main SEC-M21 entry. CAPTCHA-on-first-new-IP remains open because it requires a CAPTCHA provider integration (hCaptcha / reCAPTCHA / Turnstile) — recipe: (1) pick a provider + bake site key into env, (2) front-end widget on portal registration step, (3) server-side `verifyCaptcha(token, remoteIp)` before consuming rate buckets, (4) bypass for already-seen IPs (new table, 30-day TTL), (5) audit failures.
  - [ ] BLOCKED: needs product decision on CAPTCHA provider + account signup + env-var wiring + public-portal JS widget integration. Not code-only.
- [x] ~~SEC-M25. **Stripe webhook: on exception DELETE idempotency claim** so retries work; or DLQ. `stripe.ts:745-753`. (trace-webhook-001)~~ — migrated to DONETODOS 2026-04-16.
- [ ] SEC-M26. **Import worker yield 100-row batches + `PRAGMA wal_checkpoint(PASSIVE)`** periodically. (C3-028, 029)
- [ ] SEC-M28-pino-add. **Rotating logger** (pino/winston file transport + max size). `utils/logger.ts`. (REL-015) DEFERRED 2026-04-17 — adding pino/winston is a dependency + build change (neither is currently in `packages/server/package.json`). Meanwhile `utils/logger.ts` already emits structured JSON on stdout/stderr with PII redaction + level gating. The canonical rotation path for production deployments is the host supervisor, NOT the app:
    - PM2: `pm2-logrotate` module handles size/time-based rotation (already documented in ecosystem.config.js).
    - systemd: `journald` with `SystemMaxUse=` + `MaxFileSec=` in `journald.conf`.
    - Docker / Kubernetes: the container log driver (`json-file max-size`, `max-file`; or a cluster aggregator like Loki/Fluent Bit).
    - Bare metal: `logrotate` + a `>>` redirect wrapper.
  App-level rotation is a secondary concern — it can duplicate work the supervisor already does and introduces a new failure mode (log disk-full handling inside the Node process). Revisit only if ops reports a scenario where host rotation is not available.
  - [ ] BLOCKED: intentionally deferred — host-supervisor rotation (PM2 / journald / Docker) is the canonical path and already documented. App-level rotation is secondary; re-open only if ops surfaces a scenario where host rotation isn't available.
- [ ] SEC-M34. **BlockChyp terminal offline:** invalidate client cache on timeout + reconcile via terminal query before marking failed. `services/blockchyp.ts:57-104, 318-420`. (PAY-23)
- [ ] SEC-M35. **Stripe idempotency key derive from (tenant_id, price_id, epoch_day)** — latent fix pending Enterprise checkout. `stripe.ts:215-245, 323-341`. (PAY-03)
- [ ] SEC-M36. **Tenant-owned Stripe + recurring charge worker** [uncertain — overlap TS1/TS2]
- [x] ~~SEC-M42. **Janitor cron** for stuck `payment_idempotency.status='pending'` > 5min → `failed`. (PAY-04 / trace-pos-003)~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-M43. **`checkout-with-ticket` auto-store-credit on card overpayment.** `pos.routes.ts:1334-1370`. (PAY-11)~~ — migrated to DONETODOS 2026-04-17.
- [x] ~~SEC-M44. **Add `capture_state` column on payments** + gate refund on 'captured'. `refunds.routes.ts:79-158`. (PAY-12)~~ — migrated to DONETODOS 2026-04-17.
- [ ] SEC-M48. **Per-task timeout on Piscina runs + maxQueue 2000→200** with 503 Retry-After. `db/worker-pool.ts:33-39`. (REL-022)
- [x] ~~SEC-M51. **TOTP AES-256-GCM HMAC-based KDF + version AAD.** `auth.routes.ts:40, 45` + `super-admin.routes.ts:94, 103`. (CRYPTO-M01, 02)~~ — migrated to DONETODOS 2026-04-17 (auth.routes.ts scope only; super-admin.routes.ts still pending).
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
