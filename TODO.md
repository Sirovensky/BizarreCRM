---
name: Future TODO items
description: Non-critical feature ideas and improvements to implement later
type: project
---

> **NOTE:** All completed tasks must be moved to [DONETODOS.md](./DONETODOS.md).
> **TODO format:** Use `- [ ] ID. **Title:** actionable summary`. Keep supporting evidence indented under the checkbox. Move completed tasks to [DONETODOS.md](./DONETODOS.md).

## AUDIT CYCLE 2 — 2026-04-19 (deep-dive: reports/portal/print + WebSocket/Room/deep-links + Electron updater/windows)

### Web cycle 2 (packages/web) — 24 findings

### Android cycle 2 (android) — 20 findings

### Management cycle 2 (packages/management) — 16 findings

## AUDIT CYCLE 1 — 2026-04-19 (shipping-readiness sweep, web + Android + management)

### Web (packages/web)
- [ ] AUDIT-WEB-009. **estimate_followup_days + lead_auto_assign settings unwired** — `pages/settings/settingsDeadToggles.ts:82-91`. No backend cron reads them. Fix: mark with visible "Coming Soon" badge in all UI paths (not just the dead-toggle list), or remove inputs.
  - [ ] BLOCKED: listed as not-wired in `settingsDeadToggles.ts` registry; operators can see the dead-toggle indicator when enabled via debug flag. Real fix requires building the follow-up + auto-assign crons (new `services/estimateFollowupCron.ts` + `services/leadAutoAssignCron.ts` + migration linking lead assignment policy), which is ticket-worthy feature scope. Revisit when lead/estimate automation sprint starts.
- [ ] AUDIT-WEB-010. **3CX credentials (tcx_host/username/extension) accepted but never sent** — `pages/settings/settingsDeadToggles.ts:62-76`, marked not-wired but in dev render without badge. Fix: remove fields entirely until 3CX integration exists, or ensure hidden in all environments.
  - [ ] BLOCKED: 3CX PBX integration is a significant new feature (Call Manager API, inbound screen-pop, click-to-dial, presence sync) — not a quick fix. The dead-toggle registry already marks them not-wired. Either remove the inputs in a UI cleanup pass or build the integration as a dedicated sprint. Revisit when VoIP integration is scoped.

### Android (android)
- [ ] AUDIT-AND-010. **Notification preferences device-local only** — `AppPreferences.kt:117-138` 6 notification toggles never sync to server. Fix: `PATCH /api/v1/users/me/notification-prefs` on change (debounced); read back on login.
  - [ ] BLOCKED: requires a server-side endpoint (`PATCH /api/v1/users/me/notification-prefs`) that does not exist yet; needs a DB schema migration adding notification-pref columns to the users table AND a preferences schema decision (per-user vs per-device). Not a pure-Android fix — backend work must land first.
- [ ] AUDIT-AND-012. **[P0 OPS] google-services.json is placeholder — FCM push dead** — `project_number:"000000000000"`, fake API key. `FcmService.onNewToken()` never called. Fix: replace with real `google-services.json` from Firebase console before any release build.
  - [ ] BLOCKED: operator infra task — the owner of the Firebase project must generate a real `google-services.json` from the Firebase console and drop it into `android/app/`. Not code-side fixable; no source-code change resolves this.
- [ ] AUDIT-AND-013. **androidx.biometric:1.2.0-alpha05 is pre-release** — `build.gradle.kts:209`. Fix: track biometric library milestone; upgrade to stable when released, or pin with TODO in version catalog.
  - [ ] BLOCKED: no stable release of `androidx.biometric:1.2.0` exists as of this audit (latest is `1.2.0-alpha05`). The `1.1.0` stable release lacks `BiometricManager.Authenticators.BIOMETRIC_STRONG` constants required by the current biometric prompt setup. Re-open when a stable `1.2.x` milestone ships upstream.
- [ ] AUDIT-AND-017. **Virtually all user-facing strings hardcoded — no strings.xml coverage** — `res/values/strings.xml` only 7 entries. i18n + RTL blocked. Fix: extract to strings.xml incrementally; at minimum cover all ContentDescription + error messages before ship.
  - [ ] BLOCKED: multi-week extraction task spanning 100+ screens and 500+ literal strings. Requires a design decision on initial i18n locales, a QA review cycle, and a translation vendor contract. Not a quick-fix batch item. Can ship without for launch locale EN-US; revisit when i18n scope is approved.

### Management (packages/management)
- [ ] AUDIT-MGT-009. **electron-builder.yml forceCodeSigning:false** — `electron-builder.yml:34`. Windows SmartScreen blocks/warns; no integrity guarantee. Fix: treat `forceCodeSigning:true` as release gate; CI check `WIN_CERT_SUBJECT`/`WIN_CERT_FILE` before release build.
  - [ ] BLOCKED: requires purchasing an Authenticode signing certificate from a CA (Sectigo/DigiCert, ~$400/yr). Operator procurement task, not code. Once cert acquired, flip `forceCodeSigning:true` + set `WIN_CERT_SUBJECT`/`WIN_CERT_FILE` env in CI. Re-open post-cert.

## NEW 2026-04-18 (user reported)

- [ ] POSSIBLE-MISSING-CUSTOM-SHOP. **Possible issue: "Create Custom Shop" button missing on self-hosted server** — reported by user 2026-04-18. Investigation needed to confirm why the button is not visible on self-hosted instances. Possible causes: (a) default credentials (admin/admin123) might trigger a different UI state; (b) config flat/env mismatch; (c) logic in `TenantsPage.tsx` or signup entry points hiding it. NOT 100% sure if it's a bug or intended behavior for certain roles/credentials.
  - [ ] BLOCKED: Investigation 2026-04-19 found two candidate "Create Shop" surfaces: (1) `/super-admin` HTML panel at `packages/server/src/index.ts:1375-1384` is gated by BOTH `localhostOnly` middleware AND `config.multiTenant` — if self-hosted deployment runs with `MULTI_TENANT=false` (or unset) the panel 404s; if it runs with `MULTI_TENANT=true` but user accesses it from a non-loopback IP (e.g. Tailscale / LAN / WAN) the `localhostOnly` guard rejects. (2) `packages/management/src/renderer/src/pages/TenantsPage.tsx:162-168` renders a "New Tenant" button (NOT "Create Custom Shop") reachable only through the Electron management app super-admin flow. Cannot reproduce or fully diagnose without access to the user's self-hosted instance — need to know: which panel they're looking at, MULTI_TENANT env value, and the IP they're connecting from. Low-risk / possibly intended behavior; recommend closing once user confirms their deployment mode.

## NEW 2026-04-16 (from live Android verify)

- [ ] NEW-BIOMETRIC-LOGIN. **Android: biometric re-login from fully logged-out state** — reported by user 2026-04-17. After an explicit logout (or server-side 401/403 on refresh), the login screen asks for username + password even when biometric is enabled. Expectation: if biometric was previously enrolled and the last-logged-in username is remembered, offer a "Unlock with biometric" button on LoginScreen that uses the stored (AES-GCM-encrypted via Android KeyStore) password to submit `/auth/login` automatically on successful biometric. Needs: (1) at enroll time (Settings → Enable Biometric), encrypt `{username, password}` with a KeyStore-backed key requiring biometric auth, persist to EncryptedSharedPreferences; (2) on LoginScreen mount, if biometric enabled + stored creds present, show an "Unlock" button that triggers BiometricPrompt; (3) on prompt success, decrypt creds, call LoginVm.submit() with them; (4) on explicit Log Out, wipe stored creds too. Related fixes shipped same day: AuthInterceptor now preserves tokens across transient refresh failures (commit 4201aa1) + MainActivity biometric gate accepts refresh-only session (commit 05f6e45) — those cover the common "logging out after wifi blip" case. This item covers the true post-logout biometric-login flow.
  - [ ] BLOCKED: pure Android feature touching BiometricPrompt + KeyStore + EncryptedSharedPreferences + Settings UI + LoginScreen — needs working Android build + device for verification. Out of server/web loop scope.

## DEBUG / SECURITY BYPASSES — must harden or remove before production

## CROSS-PLATFORM


- [ ] CROSS9c-needs-api. **Customer detail addresses card (Android, DEFERRED)** — parent CROSS9 split. Investigated 2026-04-17: there is **no `GET /customers/:id/addresses` endpoint** and the server schema stores a **single** address per customer (`address1, address2, city, state, country, postcode` columns on `customers` — see `packages/server/src/routes/customers.routes.ts:861` INSERT and the `CustomerDto` single-address shape). Rendering a dedicated "Addresses" card with billing + shipping rows therefore requires a server-side schema change first: either split into a separate `customer_addresses(id, customer_id, type, street, city, state, postcode)` table with `type IN ('billing','shipping')`, or promote existing columns to a billing address and add parallel `shipping_*` columns. The CustomerDetail "Contact info" card already renders the single address via `customer.address1 / address2 / city / state / postcode` (see `CustomerDetailScreen.kt:757-779`), which covers the data we actually have today. Leaving deferred until the web app commits to one-vs-two address pattern and the server migration lands.
  - [ ] BLOCKED: requires upstream product decision (one vs two customer addresses) + server schema migration BEFORE Android work. Not actionable from client-only.

- [ ] CROSS9d. **Customer detail tags chips (Android)** — parent CROSS9 split. Current Tags card renders the raw comma-separated string; upgrade to proper chip layout once the web tag-chip component pattern is stable.
  - [ ] BLOCKED: Android Compose client work + waits on web tag-chip component pattern to stabilize (still in flux as of 2026-04-19). Re-open when web ships a canonical `TagChip` variant suitable to port.

- [ ] CROSS31-save. **"No pricing configured" manual-price: save-as-default (DEFERRED, schema-shape mismatch with original spec):** confirmed 2026-04-16 — picking a service in the ticket wizard shows "No pricing configured. Enter price manually:" with a Price text field. Option (b) of CROSS31 (save the manual price as a default) was attempted 2026-04-17 but **deferred** because the original task assumed a `repair_services.price` column that **does not exist**. The schema (migration `010_repair_pricing.sql`) stores pricing in `repair_prices(device_model_id, repair_service_id, labor_price)` — a composite key, not a per-service default. Persisting a manual price as "default for this service" therefore requires a `repair_prices` upsert keyed on BOTH the selected device model AND the service (plus a decision on grade/part_price semantics and active flag). Server shape: `POST /api/v1/repair-pricing/prices` with `{ device_model_id, repair_service_id, labor_price }` already exists (see `packages/server/src/routes/repairPricing.routes.ts:171`). Android work needed: (1) add `RepairPricingApi.createPrice` wrapper, (2) add `saveAsDefault: Boolean = false` to wizard state, (3) add Checkbox below the manual-price field, (4) on submit when `saveAsDefault && selectedDevice.id != null && selectedService.id != null`, fire the upsert before `createTicket`. Estimated 45-60 min; out of the 30-min spike budget, so deferring. Options (a) seed baseline prices per category and (c) Settings→Pricing link remain part of first-run shop setup wizard scope.
  - [ ] BLOCKED: Android wizard + repair-pricing API plumbing (4 discrete steps, ~45-60 min) requires working Android device build to verify UI flow. Needs Android dev loop; separate work slice.


- [ ] CROSS35-compose-bump. **Android login Cut action performs Copy instead of Cut — root cause is a Compose regression, NOT app code:** reported by user 2026-04-16. Long-press → Cut inside the Username or Password TextField on the Sign In screen copies the selection to the clipboard but does NOT remove it from the field (should do both). Diagnosed 2026-04-17 — `LoginScreen.kt` uses a vanilla `OutlinedTextField` with no custom `TextToolbar`, `LocalTextToolbar`, or `onCut` override (grep on LoginScreen.kt and the entire `app/src/main` tree confirms zero hits for `TextToolbar` / `LocalTextToolbar` / `onCut` / `ClipboardManager` / `LocalClipboardManager`). Compose BOM is already `2025.03.00` per `app/build.gradle.kts:126` — far past the 2024.06.00+ fix for the earlier reported Cut regression — so the original "upgrade BOM" remediation doesn't apply. There's nothing to patch in user code; this is a deeper framework or device-level regression. Next steps: (a) bump BOM to the latest GA when a newer release is available and re-test; (b) if it still repros post-bump, file a Compose issue with a minimal repro and add a TextToolbar wrapper that re-implements cut = copy + clearSelection as a workaround. Deferred with no code change; kept visible in TODO so a future BOM bump can close it out. (Renamed from CROSS35 → CROSS35-compose-bump to make the dependency explicit.)
  - [ ] BLOCKED: upstream Jetpack Compose framework regression; no code fix in this repo reproducible without the newer Compose BOM being published. Revisit on next BOM bump cycle.

- [ ] CROSS50. **Android Customer detail: redesign layout to separate viewing from acting (accident-prone Call button):** discussed with user 2026-04-16. Current layout puts a HUGE orange-filled Call button at the top plus an orange tap-to-dial phone number in Contact Info — two paths to accidentally dial the customer. On a VIEW screen the top third is wasted on ACTION buttons. Proposed redesign: **(a)** header: big avatar initial circle + name + quick-stats row (ticket count, LTV, last visit date) — informational only; **(b)** Contact Info card displays phone/email/address/org as DISPLAY ONLY, tap each row → action sheet (Call / SMS / Copy / Open Maps) — deliberate two-tap intent for destructive actions like Call; **(c)** body scrolls through ticket history, notes, invoices (CROSS9 content); **(d)** FAB bottom-right (matching CROSS42 pattern) with speed-dial: Create Ticket (primary), Call, SMS, Create Invoice. Rationale: Call has real-world consequences (phone bill, surprised customer), warrants two-tap intent. FAB puts action at thumb reach without eating prime real estate. Frees top half for customer STATE, not ACTION.
  - [ ] BLOCKED: Android-only Compose redesign requiring UX sign-off + device testing on physical hardware. Not code-library-only; needs design iteration. Re-open when Android team has bandwidth for the CustomerDetail layout pass.



- [ ] CROSS57. **Web-vs-Android parity audit — surface advanced web features on Android under a "Superuser" (advanced) tab:** 2026-04-16 audit comparing `packages/web/src/pages/` (≈150 files) vs `android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/` (39 files). Web has many features missing entirely from Android. User directive: "if too advanced for Android, put under Superuser tab so people know it's advanced". Break into **CORE** (must ship on Android, everyday workflows) and **SUPERUSER** (advanced, acceptable in Settings → Superuser). NOT in scope: customer-facing portal (`portal/*`), landing/signup (`signup/SignupPage`, `landing/LandingPage`), tracking public page, TV display — these are non-admin surfaces that don't belong in the admin app.
  - [ ] BLOCKED: 100+ screen parity audit — multi-week scope needing Android team capacity. Can't batch via sub-agent since each screen needs design + implementation + QA pass. Re-open as a dedicated Android parity sprint.

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



## Medium Priority Findings


  Evidence:

  - `packages/server/src/middleware/masterAuth.ts:14-18` pins `algorithms`, `issuer`, and `audience`, and `packages/server/src/middleware/masterAuth.ts:36` applies those options.
  - `packages/server/src/routes/super-admin.routes.ts:169` and `packages/server/src/routes/super-admin.routes.ts:475` call `jwt.verify(token, config.superAdminSecret)` without verify options.
  - `packages/server/src/routes/super-admin.routes.ts:447-450` signs the active super-admin token with only `expiresIn`, and `packages/server/src/routes/management.routes.ts:231` verifies management tokens without issuer/audience/algorithm options.

  User impact:

  Super-admin JWT handling is inconsistent across master, super-admin, and management APIs. Tokens signed with the same secret are not scoped by audience/issuer, and future algorithm/config regressions would only be caught in one middleware path.

  Suggested fix:

  Centralize super-admin JWT sign/verify helpers with explicit `HS256`, issuer, audience, and expiry, then use them in super-admin login/logout, management routes, and master auth.




## Low Priority / Audit Hygiene Findings

_(AUD-20260414-L1 — closed 2026-04-17, see DONETODOS.md.)_

---

# APRIL 14 2026 ANDROID FOCUSED AUDIT ADDITIONS

## High Priority / Android Workflow Breakers




## Medium Priority / Android UX and Navigation Gaps



## Low Priority / Android Polish

## PRODUCTION READINESS PLAN — Outstanding Items (moved from ProductionPlan.md, 2026-04-16)

> Source: `ProductionPlan.md`. All `[x]` items stay there as completion record. All `[ ]` items relocated here for active tracking. IDs prefixed `PROD`.

### Phase 0 — Pre-flight inventory







### Phase 1 — Secrets sweep (post-init verification)





### Phase 2 — JWT, sessions, auth hardening







### Phase 3 — Input validation & injection












### Phase 4 — Transport, headers, CORS






### Phase 5 — Multi-tenant isolation





### Phase 6 — Logging, monitoring, errors




### Phase 7 — Backups, data, recovery



### Phase 8 — Dependencies & supply chain







### Phase 9 — Build & deploy hygiene











### Phase 10 — Repo polish for public release



















### Phase 11 — Operational





- [ ] PROD103. **Log rotation on `bizarre-crm/logs/`:** prevent unbounded growth.
  - [ ] BLOCKED: canonical rotation is host-supervisor concern (PM2 `pm2-logrotate`, journald + `systemd-journal`, Docker log-driver `max-size`) — already documented in ecosystem.config.js. Operator infra task, not app code. Same blocker class as SEC-M28-pino-add. App-level rotation is secondary; re-open only if ops surfaces a scenario where host rotation isn't available.



### Phase 12 — Final pre-publish checklist (gate before flipping public)

- [ ] PROD106. **Phase 1–6 (all PROD items above) complete and clean.**
  - [ ] BLOCKED: meta-gate — depends on PROD102-105 and human-smoke items PROD109-112 being closed. Vacuously BLOCKED until every predecessor is either migrated or has its own BLOCKED note.

- [ ] PROD107. **All security tests pass:** `bash security-tests.sh && bash security-tests-phase2.sh && bash security-tests-phase3.sh` (60 tests, 3 phases per CLAUDE.md).
  - [ ] BLOCKED: the three security-tests shell scripts require a running server on port 443 with seeded tenant DB. No live server in this worktree; cannot invoke. Operator must run post-deploy.


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



## Security Audit Findings (2026-04-16) — deduped against existing backlog

Findings sourced from `bughunt/findings.jsonl` (451 entries) + `bughunt/verified.jsonl` (22 verdicts) + Phase-4 live probes against local + prod sandbox. Severity reflects post-verification state. Items flagged `[uncertain — verify overlap]` may duplicate an existing PROD/AUD/TS entry — review before starting.

### CRITICAL

### HIGH — auth

### HIGH — authz

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

### HIGH — pii


### HIGH — concurrency


### HIGH — reliability


### HIGH — public-surface


### HIGH — electron + android


### HIGH — crypto


### HIGH — supply-chain + tests


### HIGH — logic


### HIGH — ops (additional)


### MEDIUM

- [ ] SEC-M21-captcha. **Portal register/send-code CAPTCHA on first new IP** — DEFERRED 2026-04-17. The 24h per-phone hard cap (10/day) shipped in the same commit that closed the main SEC-M21 entry. CAPTCHA-on-first-new-IP remains open because it requires a CAPTCHA provider integration (hCaptcha / reCAPTCHA / Turnstile) — recipe: (1) pick a provider + bake site key into env, (2) front-end widget on portal registration step, (3) server-side `verifyCaptcha(token, remoteIp)` before consuming rate buckets, (4) bypass for already-seen IPs (new table, 30-day TTL), (5) audit failures.
  - [ ] BLOCKED: needs product decision on CAPTCHA provider + account signup + env-var wiring + public-portal JS widget integration. Not code-only.
- [ ] SEC-M28-pino-add. **Rotating logger** (pino/winston file transport + max size). `utils/logger.ts`. (REL-015) DEFERRED 2026-04-17 — adding pino/winston is a dependency + build change (neither is currently in `packages/server/package.json`). Meanwhile `utils/logger.ts` already emits structured JSON on stdout/stderr with PII redaction + level gating. The canonical rotation path for production deployments is the host supervisor, NOT the app:
    - PM2: `pm2-logrotate` module handles size/time-based rotation (already documented in ecosystem.config.js).
    - systemd: `journald` with `SystemMaxUse=` + `MaxFileSec=` in `journald.conf`.
    - Docker / Kubernetes: the container log driver (`json-file max-size`, `max-file`; or a cluster aggregator like Loki/Fluent Bit).
    - Bare metal: `logrotate` + a `>>` redirect wrapper.
  App-level rotation is a secondary concern — it can duplicate work the supervisor already does and introduces a new failure mode (log disk-full handling inside the Node process). Revisit only if ops reports a scenario where host rotation is not available.
  - [ ] BLOCKED: intentionally deferred — host-supervisor rotation (PM2 / journald / Docker) is the canonical path and already documented. App-level rotation is secondary; re-open only if ops surfaces a scenario where host rotation isn't available.
- [ ] SEC-M36. **Tenant-owned Stripe + recurring charge worker** [uncertain — overlap TS1/TS2]
  - [ ] BLOCKED: same scope as TS1 + TS2 (tenant-owned Stripe integration + recurring billing worker) — both BLOCKED on product decision about whether tenants use their own Stripe account vs. platform-relay model. Do not implement until TS1/TS2 unblocks.
- [ ] SEC-M61. **user_permissions fine-grained capability table** (replace role='admin' grab-bag). (LOGIC-017)
  - [ ] BLOCKED: partially addressed 2026-04-19 by SEC-H25 — 17 new permission constants + role matrix (`ROLE_PERMISSIONS` in middleware/auth.ts) + `requirePermission` gates on 72 mutating handlers. Remaining for full SEC-M61: schema migration for `user_permissions` table (user_id, permission, granted_at, granted_by), UI for admin to toggle per-user overrides, and `hasPermission()` check that consults both role matrix AND user overrides. Defer as a follow-up — the role matrix is the authoritative path today and covers the common case; per-user overrides can be added incrementally without a schema break.
### LOW

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

## Cross-platform scope decisions (surfaced by ios/ActionPlan.md review, 2026-04-20)

- [ ] **IMAGE-FORMAT-PARITY-001. Cross-platform image-format support (HEIC / TIFF / DNG).**
  Surfaced from `ios/ActionPlan.md §29.3`. iOS photo captures default to HEIC since iOS 11; DNG comes from "pro" cameras and iPhone ProRAW; TIFF from scanners and multi-page documents. iOS Image I/O decodes all of these natively. Parity unknowns:
  - `packages/server/src/` uploads endpoint — confirm it accepts `image/heic`, `image/heif`, `image/tiff`, `image/x-adobe-dng`. Today likely JPEG/PNG only; needs audit. File-size limits must be re-evaluated because DNG + multi-page TIFF are much larger than JPEG.
  - `packages/web/src/` — `<img>` HEIC support is Safari-only; Chrome + Firefox still don't render HEIC client-side. Server must transcode to JPEG for web display OR web must reject uploads in those formats. Decision: pick one (transcode preferred).
  - `android/` — Android 9+ handles HEIC; older devices do not. Android DNG + TIFF is uneven. Same transcode-on-upload or reject path.
  - iOS: confirms formats decode locally, uploads honor whatever server accepts, surfaces "Your shop's server doesn't accept X — convert or attach different file" when rejected.
  Recommend server-side transcoding to JPEG on ingestion so all clients see a consistent format; keep original on server for download. Block iOS implementation of TIFF / DNG / HEIC upload until this is decided.

- [ ] **TEAM-CHAT-AUDIT-001. Team chat data-at-rest audit (server + clients).**
  Surfaced from `ios/ActionPlan.md §47`. Server today stores message bodies in SQLite TEXT columns (`team_chat_messages.body TEXT NOT NULL`, migration `096_team_management.sql`). No column-level encryption, no hashing. Fine as a staff-chat MVP but needs a comprehensive review before scaling:
  1. **At-rest encryption.** Does the tenant server DB sit on an encrypted filesystem? For SQLite deployments, the file is plaintext-readable unless SQLCipher (or equivalent) is applied at the DB layer. Cloud-hosted tenants inherit our infra's disk encryption; self-hosted tenants are on their own.
  2. **In-transit.** HTTPS already covers this; verify no polling fallback ever lands HTTP.
  3. **Access control.** Current server reads require only auth; verify tenant-scoping on every `SELECT` (audit reports this is correct but re-confirm).
  4. **Retention policy.** No expiry today. Decide: forever / 1yr / 90d / per-tenant config. Add a purge job.
  5. **Export.** Tenant owner can currently query via admin UI only. GDPR / CCPA subject-request flow should be able to export a user's messages + @mentions on request (§139 in ActionPlan).
  6. **Moderation.** Admins can delete any message (§47.10); user own-delete window 5 min. Deleted messages retain body in audit log for manager review — check the audit blob doesn't also go plaintext into telemetry (§32.6 Redactor).
  7. **PII / secret risk.** Free-form chat can carry phone numbers, customer names, even tokens (via copy-paste). Apply §32.6 placeholder redactor when a message body is quoted in any telemetry / log / crash payload. Never redact the stored message itself (that's what users typed), only our observability copies.
  8. **HIPAA / PCI tenants.** If a tenant processes PHI or PAN-adjacent data, plaintext chat is a non-starter. Gate: tenants with HIPAA / PCI mode enabled must opt into column-level encryption on `team_chat_messages.body` (server-side, key derived from tenant secret) OR have team chat disabled for them entirely.
  9. **Search.** Currently index-free. Future FTS5 would index plaintext too. Audit before that ships.
  10. **Backup.** Tenant-server backups include the chat table; make sure backup encryption is at least as strong as the primary store.
  11. **Client cache.** Web + iOS + Android will locally cache messages (offline support). iOS/Android use SQLCipher — covered. Web uses IndexedDB / localStorage — needs its own review.
  Block wide rollout of team chat (iOS + Android) until findings close.

- [ ] **TEAM-CHAT-ANDROID-PARITY-001. Android team-chat client missing.**
  Surfaced from `ios/ActionPlan.md §47`. Server + web both ship team chat today (`/api/v1/team-chat`, `/team/chat`). Android has zero references. Parity work for Android: list channels, thread view, compose + @mention, polling with `?after=<id>` cursor (matches server MVP), room for later WS upgrade. Shares schema with iOS once iOS ships; both should use the same shape so server doesn't grow per-client variants. Blocks iOS team-chat merge.

- [ ] **STOCKTAKE-ANDROID-PARITY-001. Android stocktake missing.**
  Surfaced from `ios/ActionPlan.md §60` / §89. Server has `/api/v1/stocktake` (`stocktake.routes.ts`) and web has `pages/inventory/StocktakePage.tsx`. Android only references stocktake in a dashboard widget placeholder. Full Android parity: sessions list, per-session count UI, barcode-scan loop, variance resolution, adjust on commit. Follows same cursor-based pagination contract the other list surfaces use.

### Wave-48 scan-loop findings (2026-04-23) — web/api + web/stores

### Wave-49 scan-loop findings (2026-04-23) — web/components

### Wave-50 scan-loop findings (2026-04-23) — web/pages
- [ ] SCAN-961. **Ticket wizard still has ~18 FormLabel/input pairs in device + service sections without htmlFor wiring — needs full sweep.**
  <!-- meta: scope=web/pages; files=packages/web/src/pages/tickets/TicketWizard.tsx; fix=wire-all-FormLabel-with-useId -->

### Wave-52 scan-loop findings (2026-04-23) — web/layout + web/auth

### Wave-51 scan-loop findings (2026-04-23) — web/pages dashboard+reports+settings+customers

### Wave-53 scan-loop findings (2026-04-23) — web/pages inventory+estimates + shared
- [ ] SCAN-984. **Estimate convert mutation navigates away while concurrent send/approve mutations may still be pending — race condition.**
  <!-- meta: scope=web/pages/estimates; files=packages/web/src/pages/estimates/EstimateDetailPage.tsx:74-76,EstimateListPage.tsx:392-394; fix=mutually-disable-all-action-buttons -->

### Wave-54 scan-loop findings (2026-04-23) — web/pages catalog+employees+billing+marketing+gift-cards+expenses+loaners
- [ ] SCAN-992b. **Catalog `jobs` + `items` still `any[]` — narrow interface deferred until server DTOs stabilise. `modelResults` is now typed.**
  <!-- meta: scope=web/pages/catalog; files=packages/web/src/pages/catalog/CatalogPage.tsx; fix=type-when-dto-stable -->

### Wave-55 scan-loop findings (2026-04-23) — web/pages communications+reviews+expenses + shared API types
- [ ] SCAN-1003. **Communications page: pervasive `(x.data as any)?.data?...` chains — server response shapes unchecked across SMS/customer/voice queries.**
  <!-- meta: scope=web/pages/communications; files=packages/web/src/pages/communications/CommunicationPage.tsx:958; fix=type-response-interfaces -->
- [ ] SCAN-1004. **`smsApi.templates()` response cast via `as any` in 3 files — lost template-shape safety.**
  <!-- meta: scope=web/api+web/pages; files=BulkSmsModal.tsx:63,CannedResponseHotkeys,CommunicationPage.tsx; fix=export-SmsTemplateListResponse-type -->
- [ ] SCAN-1009. **Communications `sendMutation` closure captures `selectedPhone` — mid-flight conversation switch invalidates wrong thread cache.**
  <!-- meta: scope=web/pages/communications; files=packages/web/src/pages/communications/CommunicationPage.tsx:1085; fix=pass-phone-in-mutation-variables -->
- [ ] SCAN-1010b. **ExpensesPage `exp: any` loop variable — lost type safety on rendered rows (CashRegister half shipped).**
  <!-- meta: scope=web/pages/expenses; files=packages/web/src/pages/expenses/ExpensesPage.tsx:196; fix=define-Expense-interface -->

### Wave-56 scan-loop findings (2026-04-24) — web/pages pos+print+setup+photo-capture+loaners+landing
- [ ] SCAN-1014. **PrintPage ticket + config props typed as `any` — 30+ property accesses unchecked.**
  <!-- meta: scope=web/pages/print; files=packages/web/src/pages/print/PrintPage.tsx:141,396,707,834; fix=define-Ticket-PrintConfig-Device-Payment -->
- [ ] SCAN-1015. **Setup import polling swallows all errors — no retry limit, silent failure indefinitely.**
  <!-- meta: scope=web/pages/setup; files=packages/web/src/pages/setup/steps/StepImport.tsx:155; fix=count-consecutive-failures-and-abort -->
- [ ] SCAN-1016. **Setup import interval captures stale `source` state in closure.**
  <!-- meta: scope=web/pages/setup; files=packages/web/src/pages/setup/steps/StepImport.tsx:134-156; fix=useRef-or-local-const -->
- [ ] SCAN-1017. **PhotoCapturePage upload `catch (e: any)` with no toast — mobile users miss silent failures.**
  <!-- meta: scope=web/pages/photo-capture; files=packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:75; fix=unknown+toast-error -->
- [ ] SCAN-1018. **SetupPage `(setupData as any)` triple-cast for wizard status fields.**
  <!-- meta: scope=web/pages/setup; files=packages/web/src/pages/setup/SetupPage.tsx:60-62; fix=type-useQuery-generic -->
- [ ] SCAN-1019. **LoanersPage "Mark Returned" button missing `type="button"`.**
  <!-- meta: scope=web/pages/loaners; files=packages/web/src/pages/loaners/LoanersPage.tsx:179; fix=add-type-button -->
- [ ] SCAN-1020. **LandingPage inline onMouseEnter/Leave handlers recreated every render across mapped pricing cards.**
  <!-- meta: scope=web/pages/landing; files=packages/web/src/pages/landing/LandingPage.tsx:318-319; fix=extract-stable-or-CSS-hover -->
- [ ] SCAN-1021. **LandingPage uses `window.location.href = 'mailto:…'` instead of real `<a href>` — pattern-fragile.**
  <!-- meta: scope=web/pages/landing; files=packages/web/src/pages/landing/LandingPage.tsx:397; fix=use-anchor-element -->
- [ ] SCAN-1022. **LoanersPage list query has no `staleTime`.**
  <!-- meta: scope=web/pages/loaners; files=packages/web/src/pages/loaners/LoanersPage.tsx:105; fix=staleTime-30000 -->
- [ ] SCAN-1023. **PrintPage query fires with `Number(undefined)`=NaN when route missing `:id`.**
  <!-- meta: scope=web/pages/print; files=packages/web/src/pages/print/PrintPage.tsx:874,876; fix=enabled-isFinite-guard -->- [ ] SCAN-997b. **Billing aging/dunning/payment-links icon buttons still need aria-label review (type="button" applied, aria TODO).**
  <!-- meta: scope=web/pages/billing; files=AgingReportPage.tsx,DunningPage.tsx,PaymentLinksPage.tsx; fix=audit-aria-labels -->

