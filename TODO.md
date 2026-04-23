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


- [ ] WAVE11-ANDROID-RESUME. **Wave 11 Android work stashed mid-flight 2026-04-23 — session paused before completion.** Three parallel sub-agents + one targeted fix were killed with uncommitted files on disk; work was stashed as `stash@{0}` labeled `wave11-killed-midwork-A11-LeadsKanban-B11-DashA11y-C11-SMSTemplates-ReportsChartsVicoFix`. When resuming:
  - [ ] **A11 — Leads Kanban** (ActionPlan §9): reads `ui/screens/leads/LeadListScreen.kt` (stashed edit — adds view toggle) + `ui/screens/leads/LeadKanbanBoard.kt` (stashed new file — read-only Kanban with horizontal-scroll columns grouped by lead.stage, tap-to-detail, drag-drop deferred). Verify compile, finish, commit atomically.
  - [ ] **B11 — Dashboard a11y sweep** (ActionPlan §26): stashed edit to `ui/screens/dashboard/DashboardScreen.kt` adds contentDescription + Role.Button + mergeDescendants + heading() semantics across KPI tiles, action buttons, section headers. Verify TalkBack, commit.
  - [ ] **C11 — SMS template picker** (ActionPlan §12): stashed edits to `data/remote/api/SmsApi.kt` (add GET /sms/templates), `data/remote/dto/SmsTemplateDto.kt` (new), `ui/screens/communications/SmsThreadScreen.kt` (add template button), `ui/screens/communications/SmsTemplatePickerSheet.kt` (new), `ui/screens/settings/SmsTemplatesScreen.kt` (touched). Includes `interpolate({{customer_name}}…)` helper. Verify server endpoint shape matches `packages/server/src/routes/sms.routes.ts`.
  - [ ] **Vico API fix** (ActionPlan §15 follow-up): `ui/screens/reports/ReportsCharts.kt` has ~20 Vico 2.0.1 compile errors (committed in `10fa3325` but that compile likely benefited from KSP cache; fresh `compileDebugKotlin` fails). Fix: `rememberStartAxis()` → `VerticalAxis.rememberStart()`, `rememberBottomAxis()` → `HorizontalAxis.rememberBottom()`, `rememberLine()` → `LineCartesianLayer.rememberLine(fill = LineFill.single(...))`, `CartesianChartHost` signature, `modelProducer.runTransaction { columnSeries { series(...) } }` DSL. Fallback: replace the two Vico-rendered charts with pure-Compose Canvas like `CategoryBreakdownPieChart` already does. Must get `./gradlew compileDebugKotlin` to zero errors.
  - Recovery steps: `cd .claude/worktrees/crazy-banzai-2f7945 && git stash pop stash@{0}` → verify working tree has the 5 modified + 3 new files → split into 4 atomic commits matching the sub-agent scopes above → run `compileDebugKotlin` after each → push.

- [ ] SESSION-2026-04-23-INCOMPLETES. **Other items that did not finish in the 2026-04-23 Android orchestration session.** Beyond Wave 11 (see above):
  - [ ] `[~]` partials in `android/ActionPlan.md` (91 items) — many are "util/state ready; composable wiring pending" entries from Waves 1-10 where per-feature UI consumers still need to be wired. Examples: Undo stack wiring into ViewModels for ticket/customer/POS/inventory actions (§1 L232-L234); DraftStore 2s-debounce timer in ticket-create / customer-create / SMS-compose ViewModels (§1 L260); Validation/FormError bullets for ErrorSurface per feature; field-level retry CTAs; error-recovery UI per domain.
  - [ ] `[blocked]` items (3): (a) Disable 2FA (§2.4 L304 — Android, policy, never unblock), (b) Glance widgets (§24 L2314-L2315 — needs `androidx.glance:glance-appwidget:1.1.0` dep addition under dep-policy review), (c) — same Glance line.
  - [ ] LoginScreen long-press-on-avatar path for switch-user (§2.5 L310 secondary entry) — Settings row shipped; top-bar long-press avatar path deferred.
  - [ ] Root scaffold banner mount is live (commit a762605) but BizarreCrmApp.onCreate ON_STOP hook for `ClipboardUtil.clearSensitiveIfPresent` + draft flush + FLAG_SECURE still carry TODO markers (see commit 30d65d7).
  - [ ] `AppCompatDelegate.wrapContext()` not wired into `MainActivity.attachBaseContext` — on API 26-32 the language picker only applies after `recreate()`, not on cold starts (commit d3d546c note).
  - [ ] `testDebugUnitTest` Gradle task is broken project-wide per pre-existing KSP Windows path-length / incremental-state race. Sub-agents fell back to direct JVM runners. Needs either (a) `./gradlew --stop && rm -rf app/build/generated/ksp app/build/kspCaches && ./gradlew testDebugUnitTest` cycle on a clean machine, or (b) a Linux/macOS CI runner where KSP is stable.
  - [ ] SEC-2FA-NO-SELF-DISABLE sub-item: server endpoint deprecation (see below) still pending.

- [ ] SEC-2FA-NO-SELF-DISABLE. **Policy: no self-service 2FA disable on any client.** Directive 2026-04-23 — users cannot turn off 2FA from any UI (Android / iOS / Web). Legitimate paths that remain: (a) backup-code recovery flow (`POST /auth/recover-with-backup-code` — resets password + disables 2FA atomically; user must re-enroll on next sign-in), (b) super-admin force-disable (`POST /tenants/:slug/users/:userId/force-disable-2fa` — gated by Step-Up TOTP + full audit, used when tenant admin loses both device and backup codes). Action required:
  - [ ] **iOS — rip UI**: delete Disable 2FA button + alert in `ios/Packages/Auth/Sources/Auth/TwoFactor/TwoFactorSettingsView.swift` (lines 41, 127-129); remove `TwoFactorRepository.disable()` (line 51); remove `TwoFactorEndpoints.twoFactorDisable()` (lines 116-121); strip `showDisableAlert` state + handlers from `TwoFactorSettingsViewModel`; remove `.disable` test path in `TwoFactorEnrollmentViewModelTests.swift` (line 474). Leave enroll + regenerate-backup-codes intact. Update `ios/ActionPlan.md` line 275 after code removal (currently marked `[blocked: policy]`).
  - [ ] **Android — never add**: `android/ActionPlan.md` line 304 marked `[blocked: policy]` 2026-04-23 before any UI shipped. Do not add endpoint to `AuthApi.kt` or any Security screen row. Wave 6 "Disable 2FA" agent was killed mid-attempt and reverted (see git log around commit 98d1d2b9).
  - [ ] **Web — audit + never add**: confirmed 2026-04-23 — `packages/web/src/` has NO disable-2FA UI (grep shows only TOTP login + enroll paths). Keep it that way.
  - [ ] **Server — deprecate self-service endpoint**: `POST /auth/account/2fa/disable` (`packages/server/src/routes/auth.routes.ts:1744`) lets an authenticated user turn off their own 2FA with password + TOTP. Deprecation options: (a) return 410 Gone with message "Use backup-code recovery or contact admin to reset 2FA", (b) soft-delete: keep endpoint but require super-admin Step-Up TOTP header (effectively making it a force-disable), (c) remove entirely. SEC-H8 hardening (DONETODOS:607 — session revoke + device cookie clear on successful disable) stays relevant for legacy callers during deprecation window. Keep `POST /auth/force-disable-2fa/:userId` (admin/super-admin override) + `POST /auth/reset-password` + `POST /auth/recover-with-backup-code` (legit recovery paths) untouched.
  - Rationale: 2FA disable via password + TOTP means a shoulder-surfed or phished credential combo can turn off the auth layer that was supposed to protect against exactly that compromise. Forcing the recovery path through backup codes or admin action keeps an out-of-band factor in the loop.

- [ ] CROSS9c-needs-api. **Customer detail addresses card (Android, DEFERRED)** — parent CROSS9 split. Investigated 2026-04-17: there is **no `GET /customers/:id/addresses` endpoint** and the server schema stores a **single** address per customer (`address1, address2, city, state, country, postcode` columns on `customers` — see `packages/server/src/routes/customers.routes.ts:861` INSERT and the `CustomerDto` single-address shape). Rendering a dedicated "Addresses" card with billing + shipping rows therefore requires a server-side schema change first: either split into a separate `customer_addresses(id, customer_id, type, street, city, state, postcode)` table with `type IN ('billing','shipping')`, or promote existing columns to a billing address and add parallel `shipping_*` columns. The CustomerDetail "Contact info" card already renders the single address via `customer.address1 / address2 / city / state / postcode` (see `CustomerDetailScreen.kt:757-779`), which covers the data we actually have today. Leaving deferred until the web app commits to one-vs-two address pattern and the server migration lands.
  - [ ] BLOCKED: requires upstream product decision (one vs two customer addresses) + server schema migration BEFORE Android work. Not actionable from client-only.

- [x] ~~CROSS9d.~~ FIXED 2026-04-23 — commit 392d1d5. **Customer detail tags chips (Android)** — shipped `ui/components/TagChip.kt` (reusable Material 3 SuggestionChip / AssistChip with secondaryContainer colors + LocalOffer icon + Tag: $label contentDescription) + CustomerDetailScreen.kt tags section now parses the comma-separated string and renders a wrapping FlowRow of chips with empty-state "No tags" text. No server contract change. Tap is a no-op this wave; onClick param pre-wired for future filter-by-tag.

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

- [ ] **NFC-PARITY-001. Cross-platform NFC support — product decision + backend + parity.**
  Surfaced from `ios/ActionPlan.md §17.5`. Today no package implements NFC: `packages/server/src/` has no `nfc_tag_id` column and no `/nfc/*` routes; `packages/web/src/` no Web NFC usage; `android/` no `NfcAdapter` / `NdefRecord` usage. iOS would be a solo feature with nowhere to persist and no way for web / Android to consume. Decision needed: ship cross-platform or drop from iOS spec. If ship, scope:
  1. Server: add `nfc_tag_id` to `tickets.device` + `inventory.item` + `customer.device` tables (tenant-scoped, indexed). Routes `POST /tickets/:id/nfc-tag`, `GET /tickets/by-nfc/:tagId`, parallel for inventory and customer device. Migration.
  2. Android: `NfcAdapter` reader-mode in matching screens; same graceful-disable pattern on devices without NFC.
  3. iOS: §17.5 tasks unblocked (`CoreNFC`, reader / writer, graceful-disable on iPad < M4 and iPhone 6 or earlier).
  4. Web: no-op — no Web NFC on Safari; prompt "Use the phone app to scan".
  5. Use cases to validate first: attach tag to customer device for warranty lookup; attach tag to loaner bin for §123 asset tracking; tag inventory for cycle-count speed.
  Block iOS §17.5 implementation work until this item resolves.

- [ ] **WATCH-COMPANION-001. Apple Watch companion — product scope decision.**
  Surfaced from `ios/ActionPlan.md §17.9`. Separate product surface (not just another iOS task): own entitlements, TestFlight lane, App Store binary. Decision needed:
  - Is the watch surface worth the maintenance for expected user volume?
  - Minimum viable scope (candidate): clock in / clock out complication + push notifications forwarded + reply-by-dictation.
  - Non-goals: no full CRM browsing on watch.
  - Delivery: shares `Core` package with iOS; new `WatchCompanion` target in `ios/project.yml`; new provisioning profile; separate phased-rollout cohort; separate review cycle.
  - Gate: revisit post iOS 1.0 GA + at least 3 tenants explicitly request the feature.
  iOS `ActionPlan.md §17.9` points here instead of scheduling inside the iOS plan.

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

## AUDIT CYCLE 3 — 2026-04-23 (parallel discovery wave 1: routes security + perf, web pages, DB schema, build/infra)

### Server routes — security/authz (12 findings)
- [ ] SCAN-001. **[SEC] admin backup settings accepts raw body with no allowlist** — `packages/server/src/routes/admin.routes.ts:503` passes entire `req.body` to `updateBackupSettings`. Fix: allowlist accepted fields (backup_enabled, backup_path, backup_schedule) before write.
- [ ] SCAN-002. **[SEC] admin /drives/browse has no rate-limit — fs enumeration** — `packages/server/src/routes/admin.routes.ts:275` rapid calls walk filesystem. Fix: `checkWindowRate` IP/session keyed.
- [ ] SCAN-003. **[SEC] sms PATCH /conversations/:phone/flag|pin|archive no format/ownership check** — `packages/server/src/routes/sms.routes.ts:334` any auth user flags other tenants phones. Fix: E.164 validate + scope to tenants sms_messages.
- [ ] SCAN-004. **[SEC] sms POST /templates unbounded name/content length** — `packages/server/src/routes/sms.routes.ts:850` no cap → DB bloat. Fix: name ≤200, content ≤1600.
- [ ] SCAN-005. **[SEC] sms POST /preview-template unchecked template_id + unbounded render output** — `packages/server/src/routes/sms.routes.ts:878` large `vars` → MB response. Fix: validate template_id positive int + cap output bytes.
- [ ] SCAN-006. **billing rate limiter increments on success** — `packages/server/src/routes/billing.routes.ts:22` `recordWindowFailure` unconditional → legit users throttled after 10 requests. Fix: only increment on abuse/failure.
- [ ] SCAN-007. **[SEC] voice GET /calls/:id/recording redirects to provider URL** — `packages/server/src/routes/voice.routes.ts:257` exposes provider-signed URL via browser history/referrer. Fix: proxy download server-side + restrict inbound recordings to admin/manager.
- [ ] SCAN-008. **voice dev callback derived from `getLanIp()` at runtime** — `packages/server/src/routes/voice.routes.ts:119` unreliable behind NAT. Fix: require explicit `WEBHOOK_BASE_URL` env + `req.get(host)` dev fallback.
- [ ] SCAN-009. **[SEC] blockchyp POST /adjust-tip no role gate + unvalidated transaction_id** — `packages/server/src/routes/blockchyp.routes.ts:526` technician can adjust tips. Fix: gate to admin/manager (match process-payment) + validate transaction_id format.
- [ ] SCAN-010. **[SEC] super-admin TOTP key uses raw SHA-256 not HKDF** — `packages/server/src/routes/super-admin.routes.ts:107` inconsistent with tenant v3 HKDF pattern. Fix: migrate `deriveKey()` to `hkdfSync` with explicit salt+info.
- [ ] SCAN-011. **super-admin /security-alerts params not validated** — `packages/server/src/routes/super-admin.routes.ts:1360` `severity` no allowlist, `acknowledged=abc` silently 0. Fix: enum guard + reject non-0/1.
- [ ] SCAN-012. **auth POST /switch-user bcrypt scan over all users — O(N) + timing channel** — `packages/server/src/routes/auth.routes.ts:1344` sequential `bcrypt.compareSync` loop. Fix: require username alongside PIN, single bcrypt.compare.

### Server routes — perf / N+1 / authz (12 findings)
- [ ] SCAN-013. **N+1 inventory POST /bulk-action — 2× SELECT+UPDATE per id, no cap** — `packages/server/src/routes/inventory.routes.ts:248-276`. Fix: cap item_ids 500 + single UPDATE WHERE id IN.
- [ ] SCAN-014. **N+1 customers POST /bulk-tag — SELECT+UPDATE per id (up to 500)** — `packages/server/src/routes/customers.routes.ts:623-644`. Fix: batch WHERE id IN fetch, then `adb.transaction()` batched writes.
- [ ] SCAN-015. **N+1 customers POST /bulk-sms — SELECT+INSERT+sendSms+UPDATE sequential per row** — `packages/server/src/routes/customers.routes.ts:761-830`. Fix: pre-fetch all rows; loop only does I/O writes.
- [ ] SCAN-016. **invoices POST /bulk-action mark_paid missing transaction — split payment+invoice writes** — `packages/server/src/routes/invoices.routes.ts:831-938` crash mid-way → orphan payment row. Fix: `adb.transaction()` wrap.
- [ ] SCAN-017. **customers POST /merge runs ~14 sequential writes with no transaction** — `packages/server/src/routes/customers.routes.ts:483-574` partial state on fail. Fix: collect `TxQuery[]` + `adb.transaction()`.
- [ ] SCAN-018. **inventory GET / correlated subquery N+1 (supplier_catalog × 2 per row)** — `packages/server/src/routes/inventory.routes.ts:94-104` pagesize=250 → 500 subqueries. Fix: LEFT JOIN pre-aggregated supplier_catalog.
- [ ] SCAN-019. **tickets GET / latest-SMS subquery — no index on sms_messages(from_number|to_number)** — `packages/server/src/routes/tickets.routes.ts:711-720`. Fix: `CREATE INDEX idx_sms_messages_from_number ON sms_messages(from_number)` + same for to_number.
- [ ] SCAN-020. **reports GET /dashboard uses DATE(created_at) — defeats index** — `packages/server/src/routes/reports.routes.ts:109-121`. Fix: range `>= ? AND < ?` to permit index seek.
- [ ] SCAN-021. **[SEC] reports GET /dashboard missing `requireAdminOrManager` — any user reads KPIs/revenue** — `packages/server/src/routes/reports.routes.ts:50-65`. Fix: gate at top of handler.
- [ ] SCAN-022. **N+1 pos POST /transaction item loop — SELECT inventory+tax+kit per item (×500)** — `packages/server/src/routes/pos.routes.ts:369-461`. Fix: batch-fetch via WHERE id IN maps.
- [ ] SCAN-023. **N+1 invoices POST / line-item tax_class lookup — per-row SELECT tax_classes** — `packages/server/src/routes/invoices.routes.ts:308-322`. Fix: collect distinct ids + single WHERE IN batch.
- [ ] SCAN-024. **[SEC] reports GET /employees missing `requireAdminOrManager` — discloses hours_worked + commission_earned** — `packages/server/src/routes/reports.routes.ts:779-828`. Fix: add role gate to match /sales, /dashboard-kpis.

### Web pages — bugs / types / a11y (12 findings)
- [ ] SCAN-025. **AutoReorderPage deleteMut missing onError** — `packages/web/src/pages/inventory/AutoReorderPage.tsx:91` silent 403/500. Fix: add `onError` toast.
- [ ] SCAN-026. **BinLocationsPage deleteMut missing onError** — `packages/web/src/pages/inventory/BinLocationsPage.tsx:101`. Fix: add `onError` toast.
- [ ] SCAN-027. **SettingsPage import-cancel mutations (cancelMutRd/cancelMutRs/cancelMutMra) missing onError** — `packages/web/src/pages/settings/SettingsPage.tsx:2581`. Fix: add `onError` toasts to each.
- [ ] SCAN-028. **dead export `getIndexedTabIds`** — `packages/web/src/pages/settings/settingsSearchIndex.ts:121` not imported anywhere. Fix: remove export (or make module-private).
- [ ] SCAN-029. **InventoryDetailPage `item: any`, `movements: any[]` — shape drift risk** — `packages/web/src/pages/inventory/InventoryDetailPage.tsx:48`. Fix: define `InventoryItem` interface.
- [ ] SCAN-030. **InvoiceDetailPage payMutation `d: any`** — `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:79`. Fix: `RecordPaymentPayload` interface.
- [ ] SCAN-031. **TicketDetailPage totals use `(d: any)`/`(p: any)` inside reduce — silent NaN on field rename** — `packages/web/src/pages/tickets/TicketDetailPage.tsx:379`. Fix: type `TicketPart` cost_price+quantity.
- [ ] SCAN-032. **TicketListPage view-toggle icons (List/Kanban/Calendar) lack `aria-label` + `aria-pressed`** — `packages/web/src/pages/tickets/TicketListPage.tsx:1117`. Fix: add both.
- [ ] SCAN-033. **InventoryListPage CSV preview `key={i}` causes stale DOM reuse on reorder** — `packages/web/src/pages/inventory/InventoryListPage.tsx:847`. Fix: content-derived key.
- [ ] SCAN-034. **CustomerListPage CSV preview `key={i}` — same** — `packages/web/src/pages/customers/CustomerListPage.tsx:815`. Fix: content-derived key.
- [ ] SCAN-035. **TicketListPage calendar cells `key={i}` — wrong animated state on month nav** — `packages/web/src/pages/tickets/TicketListPage.tsx:1301`. Fix: date-ISO key.
- [ ] SCAN-036. **CustomerDetailPage comm list fallback `key={msg.id || i}` corrupts reconciliation on insert** — `packages/web/src/pages/customers/CustomerDetailPage.tsx:1654`. Fix: require stable id or composite key.

### DB / migrations / seed (11 findings)
- [ ] SCAN-037. **membership_tiers.monthly_price REAL — post SEC-H34, storing money in float** — `packages/server/src/db/migrations/068_membership_system.sql:6`. Fix: new migration renames to `monthly_price_cents INTEGER`.
- [ ] SCAN-038. **membership_tiers.slug missing UNIQUE** — `packages/server/src/db/migrations/068_membership_system.sql:5` — duplicate slugs possible via name collision. Fix: `CREATE UNIQUE INDEX idx_membership_tiers_slug ON membership_tiers(slug)`.
- [ ] SCAN-039. **subscription_payments.amount REAL (money in float)** — `packages/server/src/db/migrations/068_membership_system.sql:46`. Fix: `amount_cents INTEGER`.
- [ ] SCAN-040. **cash_drawer_shifts.opened_by_user_id/closed_by_user_id lack FK + no cleanup in 098 trigger** — `packages/server/src/db/migrations/093_pos_enrichment.sql:28`. Fix: add `REFERENCES users(id)` + add NULL-on-delete trigger path.
- [ ] SCAN-041. **installment_plans + installment_schedule declared with zero FK REFERENCES** — `packages/server/src/db/migrations/095_billing_enrichment.sql:45-72` + not covered by 097 cleanup trigger. Fix: rebuild with FKs + extend `trg_customer_del_enrichment_cleanup`/`trg_invoice_del_enrichment_cleanup`.
- [ ] SCAN-042. **store_credits missing ON DELETE CASCADE on customer_id + absent from 097 trigger** — `packages/server/src/db/migrations/026_refunds_credits.sql:18-23` — GDPR erase leaves orphan balance. Fix: add `DELETE FROM store_credits WHERE customer_id = OLD.id` to trigger.
- [ ] SCAN-043. **rma_items.inventory_item_id no ON DELETE policy + absent from 097 inventory trigger** — `packages/server/src/db/migrations/027_rma.sql:19`. Fix: add cleanup step to `trg_inventory_del_enrichment_cleanup`.
- [ ] SCAN-044. **loaner_history.loaner_device_id no ON DELETE policy + no 097/098 cascade** — `packages/server/src/db/migrations/001_initial.sql:501`. Fix: new trigger on loaner_devices hard-delete.
- [ ] SCAN-045. **customers.driving_license / id_number / id_type / license_image — orphan plaintext gov-ID PII columns, never read/written by any route** — `packages/server/src/db/migrations/001_initial.sql:97-100`. Fix: drop columns in new migration (after confirming import flows dont use them) or encrypt-at-rest.
- [ ] SCAN-046. **workstations DDL lives in `seedDatabase()` not a numbered migration — test/clone fixtures miss the table** — `packages/server/src/db/seed.ts:68-78`; `pos.routes.ts:2235` throws on missing table. Fix: move `CREATE TABLE workstations` to new `099_workstations.sql`, keep only `INSERT OR IGNORE` in seed.
- [ ] SCAN-047. **payment_links.invoice_id + customer_id declared without REFERENCES** — `packages/server/src/db/migrations/095_billing_enrichment.sql:24` — FK enforced only in app code. Fix: rebuild with explicit `REFERENCES`.

### Build / infra / middleware (11 findings)
- [ ] SCAN-048. **@types/cheerio ghost dep — cheerio ^1.2.0 ships own types** — `packages/server/package.json:46`. Fix: remove `@types/cheerio` from devDependencies.
- [ ] SCAN-049. **[SEC] CSP connect-src includes bare `ws:` and `wss:` (any host)** — `packages/server/src/index.ts:906`. Fix: restrict to tenant base domain + wildcard subdomain.
- [ ] SCAN-050. **HSTS disabled unless NODE_ENV === 'production' (bare NODE_ENV=staging silently drops HSTS)** — `packages/server/src/index.ts:874`. Fix: treat any non-dev/test env as prod, or assert NODE_ENV at startup.
- [ ] SCAN-051. **Electron management sourceMap:true ships .js.map into production bundle** — `packages/management/tsconfig.node.json:15` leaks TS paths. Fix: `sourceMap: false` for prod build (or exclude `.map` from packager glob).
- [ ] SCAN-052. **[SEC] `/api/v1/catalog/bulk-import` registers 10MB JSON parser before auth middleware — unauth caller forces 10MB alloc at parse** — `packages/server/src/index.ts:1166-1168`. Fix: `app.post('/api/v1/catalog/bulk-import', authMiddleware, express.json({limit:10mb}))`.
- [ ] SCAN-053. **[SEC] global rate-limiter skips entire `/auth/*` subtree — sub-routes without own limit unprotected** — `packages/server/src/index.ts:1125-1128`. Fix: narrow bypass to specific public endpoints (e.g. /auth/login) + audit each /auth/* for its own limit.
- [ ] SCAN-054. **[SEC] NO_ORIGIN_ALLOWED_PATHS includes `/api/v1/auth/` prefix — verify-totp + change-password accept no-origin POSTs** — `packages/server/src/index.ts:971-983`. Fix: remove the blanket `/auth/` prefix, keep only actual public endpoints.
- [ ] SCAN-055. **tsconfig.base.json missing strict flags — noUnusedLocals, noUnusedParameters, noImplicitReturns, noUncheckedIndexedAccess** — all packages inherit lax base. Fix: enable in `tsconfig.base.json` compilerOptions (expect lint fixups).
- [ ] SCAN-056. **No global SameSite/`__Host-` cookie enforcement — relies on per-handler choice + content-type CSRF guard** — `packages/server/src/index.ts:1111` cookie-parser default. Fix: enforce SameSite=Strict + Secure for session cookies, or add guard middleware.
- [ ] SCAN-057. **[STALE-DEP report-only] react-router-dom ^7.1.0 — 7.4+ includes nested-route path-traversal fix** — `packages/web/package.json:29`.
- [ ] SCAN-058. **[STALE-DEP report-only] dompurify ^3.3.4 — 3.4.0+ closes sanitizer bypass edge cases** — `packages/web/package.json:22`.

## AUDIT CYCLE 3 — 2026-04-23 (parallel discovery wave 2: leads/portal/refunds/estimates + campaigns/membership/gift/auto + web shared + server services + web remaining pages)

### Server routes — leads/portal/refunds/estimates/loaners/tradeIns/dunning (12 findings)
- [ ] SCAN-059. **[SEC] leads GET /pipeline missing tenant filter (`WHERE is_deleted=0` only)** — `packages/server/src/routes/leads.routes.ts:106`. Fix: verify per-request DB isolation covers this; add explicit `tenant_id = ?` if shared DB.
- [ ] SCAN-060. **leads GET /pipeline + GET / no rate-limit on fan-out** — `packages/server/src/routes/leads.routes.ts:106,165`. Fix: per-user/IP limit.
- [ ] SCAN-061. **tradeIns GET /:id + PATCH /:id + DELETE /:id pass raw string id to SQL** — `packages/server/src/routes/tradeIns.routes.ts:73,139,317`. Fix: `parseInt + Number.isInteger` guard at handler top.
- [ ] SCAN-062. **[SEC] loaners POST / / PUT /:id / DELETE /:id no role/permission gate — cashier can add/delete loaner hardware** — `packages/server/src/routes/loaners.routes.ts:67,80,162`. Fix: `requirePermission('inventory.adjust')`.
- [ ] SCAN-063. **loaners GET /:id missing integer validation on params.id** — `packages/server/src/routes/loaners.routes.ts:52`. Fix: parseInt + positive-int guard.
- [ ] SCAN-064. **estimates GET /:id + PUT /:id missing integer validation on id** — `packages/server/src/routes/estimates.routes.ts:481,519`. Fix: Number.isInteger + >0 guard.
- [ ] SCAN-065. **estimates POST /bulk-convert element-level integer validation missing** — `packages/server/src/routes/estimates.routes.ts:308,370`. Fix: coerce+validate each id before query.
- [ ] SCAN-066. **[SEC] dunning GET /sequences unprotected — exposes collection strategy to any auth user** — `packages/server/src/routes/dunning.routes.ts:49`. Fix: `requireAdmin`.
- [ ] SCAN-067. **[SEC] dunning GET /invoices/aging unprotected — cashier reads full AR aging** — `packages/server/src/routes/dunning.routes.ts:153`. Fix: `requirePermission('invoices.view')` or `requireAdmin`.
- [ ] SCAN-068. **[SEC] refunds GET /credits/:customerId unprotected — any user reads any customer's balance + 50-row history** — `packages/server/src/routes/refunds.routes.ts:354`. Fix: add permission guard.

### Server routes — campaigns/paymentLinks/giftCards/membership/automations/deposits/rma/snippets (12 findings)
- [ ] SCAN-069. **[SEC] snippets PUT /:id no auth check — any user overwrites any snippet** — `packages/server/src/routes/snippets.routes.ts:70`. Fix: role check + enforce `created_by === req.user.id` for non-admin.
- [ ] SCAN-070. **[SEC] snippets DELETE /:id no permission guard** — `packages/server/src/routes/snippets.routes.ts:113`. Fix: role check.
- [ ] SCAN-071. **snippets PUT /:id missing typeof string guard on shortcode/title/content — TypeError on non-string** — `packages/server/src/routes/snippets.routes.ts:81`. Fix: typeof guards matching POST handler.
- [ ] SCAN-072. **snippets PUT /:id empty-string shortcode bypasses uniqueness check** — `packages/server/src/routes/snippets.routes.ts:86`. Fix: reject empty-string shortcode with 400.
- [ ] SCAN-073. **automations POST / trigger_type/action_type unconstrained strings** — `packages/server/src/routes/automations.routes.ts:67`. Fix: enum allowlist.
- [ ] SCAN-074. **automations PUT /:id trigger_config/action_config no size cap** — `packages/server/src/routes/automations.routes.ts:112`. Fix: `validateJsonPayload(..., 16_384)` matching campaigns.
- [ ] SCAN-075. **membership PUT /tiers/:id no validation on name/monthly_price/discount_pct/sort_order/is_active** — `packages/server/src/routes/membership.routes.ts:85`. Fix: length + `validatePositiveAmount` + integer checks.
- [ ] SCAN-076. **[SEC] membership POST /subscribe records status='success' without processor confirmation** — `packages/server/src/routes/membership.routes.ts:195` zero-payment subscription possible. Fix: require valid provider token + record payment only after successful charge response.
- [ ] SCAN-077. **rma GET /:id missing integer validation on params.id** — `packages/server/src/routes/rma.routes.ts:96`. Fix: parseInt + isFinite.
- [ ] SCAN-078. **campaigns POST /:id/run-now no idempotency — double-tap double-dispatches mass SMS/email** — `packages/server/src/routes/campaigns.routes.ts:639`. Fix: `last_run_at` cooldown (60s) or idempotency key.
- [ ] SCAN-079. **[SEC] deposits GET / + GET /:id no permission guard — cashier lists all deposits + amounts** — `packages/server/src/routes/deposits.routes.ts:56`. Fix: `requirePermission('deposits.view')` or manager-or-admin.
- [ ] SCAN-080. **[SEC] giftCards GET /:id no permission guard — enumerate code + balance + tx history** — `packages/server/src/routes/giftCards.routes.ts:409`. Fix: `requirePermission('gift_cards.view')`.

### Web components / stores / hooks / utils (12 findings)
- [ ] SCAN-081. **[SEC] UpgradeModal open redirect from `res.data?.data?.url` unvalidated** — `packages/web/src/components/shared/UpgradeModal.tsx:50`. Fix: same-origin or Stripe-domain allowlist before `window.location.href`.
- [ ] SCAN-082. **UpgradeModal type-unsafe error cast hides shape** — `packages/web/src/components/shared/UpgradeModal.tsx:63`. Fix: `extractApiError(e)` from utils/apiError.ts.
- [ ] SCAN-083. **UpgradeModal missing role=dialog / aria-modal / aria-labelledby** — `packages/web/src/components/shared/UpgradeModal.tsx:62`. Fix: add dialog ARIA.
- [ ] SCAN-084. **PinModal missing role=dialog + aria-modal + aria-labelledby** — `packages/web/src/components/shared/PinModal.tsx:76`. Fix: add dialog ARIA.
- [ ] SCAN-085. **PrintPreviewModal missing role=dialog + aria-modal + focus trap** — `packages/web/src/components/shared/PrintPreviewModal.tsx:69`. Fix: dialog ARIA + ConfirmDialog focus-trap pattern.
- [ ] SCAN-086. **QuickSmsModal labels not linked to inputs (missing htmlFor/id)** — `packages/web/src/components/shared/QuickSmsModal.tsx:98`. Fix: add matching id/htmlFor.
- [ ] SCAN-087. **QuickSmsModal missing role=dialog + aria-modal + aria-labelledby** — `packages/web/src/components/shared/QuickSmsModal.tsx:76`. Fix: dialog ARIA.
- [ ] SCAN-088. **AppShell `as any` on configData** — `packages/web/src/components/layout/AppShell.tsx:52,56`. Fix: type useQuery with config response shape.
- [ ] SCAN-089. **[SEC] authStore writes JWT access token to localStorage (XSS pivot)** — `packages/web/src/stores/authStore.ts:54`. Fix: in-memory only; rely on httpOnly refresh cookie for persistence.
- [ ] SCAN-090. **InstallmentPlanWizard acceptance text input lacks id/aria-label/htmlFor** — `packages/web/src/components/billing/InstallmentPlanWizard.tsx:170`. Fix: add id + label.
- [ ] SCAN-091. **usePosKeyboardShortcuts re-adds keydown listener on every render (handlers unstable ref)** — `packages/web/src/hooks/usePosKeyboardShortcuts.ts:64`. Fix: accept individual handler props or document memo requirement.
- [ ] SCAN-092. **Duplicate formatCurrency util — portal version vs utils/format** — `packages/web/src/utils/formatCurrency.ts:12`. Fix: consolidate to one implementation.

### Server services (8 findings)
- [ ] SCAN-093. **[SEC] repairShoprImport SSRF via user-controlled `subdomain` interpolated into URL** — `packages/server/src/services/repairShoprImport.ts:102-104`. Fix: regex validate `^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$` + `assertPublicUrl`.
- [ ] SCAN-094. **myRepairApp import unbounded response body buffering on bulk endpoints** — `packages/server/src/services/myRepairAppImport.ts:164-176,183-218,225-236`. Fix: Content-Length pre-check + 50MB cap matching catalogScraper.ts:403-421.
- [ ] SCAN-095. **repairShoprImport fetchAllPages unbounded json() buffering** — `packages/server/src/services/repairShoprImport.ts:159-185`. Fix: cap + stream-read pattern.
- [ ] SCAN-096. **[SEC] myRepairApp MraApiClient accepts optional `baseUrl` override — SSRF** — `packages/server/src/services/myRepairAppImport.ts:1249-1263`. Fix: hardcode domain or `assertPublicUrl`.
- [ ] SCAN-097. **backup.ts PowerShell error log includes full resolved dir path** — `packages/server/src/services/backup.ts:505-509,525`. Fix: redact to `path.basename(dir)` in error context.
- [ ] SCAN-098. **repairShoprImport uses console.log bypassing structured logger** — `packages/server/src/services/repairShoprImport.ts:1039,1085`. Fix: `log.info()` via createLogger.
- [ ] SCAN-099. **repairDeskImport fetchAllPages unbounded json() buffering** — `packages/server/src/services/repairDeskImport.ts:388-399`. Fix: Content-Length cap + stream pattern.
- [ ] SCAN-100. **[SEC] email.ts smtp_from fallback accepted without EMAIL_FROM_RE validation — CRLF header injection possible** — `packages/server/src/services/email.ts:60-68`. Fix: apply same regex guard before using smtp_from.

### Web remaining pages — communications/marketing/billing/super-admin/dashboard/leads/portal (12 findings)
- [ ] SCAN-101. **CommunicationPage markReadMutation missing onError** — `packages/web/src/pages/communications/CommunicationPage.tsx:971`. Fix: onError toast.
- [ ] SCAN-102. **CampaignsPage updateStatus missing onError** — `packages/web/src/pages/marketing/CampaignsPage.tsx:122`. Fix: onError toast.
- [ ] SCAN-103. **DunningPage toggleMutation missing onError** — `packages/web/src/pages/billing/DunningPage.tsx:84`. Fix: onError toast.
- [ ] SCAN-104. **[SEC] super-admin TenantsListPage writes SA JWT to localStorage** — `packages/web/src/pages/super-admin/TenantsListPage.tsx:67`. Fix: in-memory or sessionStorage.
- [ ] SCAN-105. **CommunicationPage customerTickets typed any[]** — `packages/web/src/pages/communications/CommunicationPage.tsx:1006`. Fix: `TicketSummary` interface.
- [ ] SCAN-106. **DashboardPage MissingPartsCard queueSummary prop typed any** — `packages/web/src/pages/dashboard/DashboardPage.tsx:189`. Fix: `QueueSummary` interface.
- [ ] SCAN-107. **CommunicationPage outbound sms payload typed any** — `packages/web/src/pages/communications/CommunicationPage.tsx:1172`. Fix: explicit `{to,message,send_at?}` type.
- [ ] SCAN-108. **LeadListPage convertMut onError uses console.error (prod log leak)** — `packages/web/src/pages/leads/LeadListPage.tsx:291`. Fix: remove console.error, keep toast.
- [ ] SCAN-109. **StatusTimeline li key uses `${event.at}-${index}` — unstable on reorder** — `packages/web/src/pages/portal/components/StatusTimeline.tsx:78`. Fix: derive from stable id/hash.
- [ ] SCAN-110. **LeadDetailPage activity-feed key includes array idx** — `packages/web/src/pages/leads/LeadDetailPage.tsx:565`. Fix: `${item.type}-${item.id}`.
- [ ] SCAN-111. **DunningPage mutationFn parses steps JSON — unformatted error to toast** — `packages/web/src/pages/billing/DunningPage.tsx:67`. Fix: validate JSON before mutate in dedicated validator.
- [ ] SCAN-112. **CommunicationPage createMut + linkExisting missing onError** — `packages/web/src/pages/communications/CommunicationPage.tsx:682,697`. Fix: onError toasts.

## AUDIT CYCLE 3 — 2026-04-23 (parallel discovery wave 3: remaining routes + Electron management + public pages + tests)

### Server routes — crm/bench/deviceTemplates/employees/expenses/customFields (12 findings)
- [ ] SCAN-113. **[SEC] crm GET /crm/reviews no role gate — technician reads all customer reviews + PII** — `packages/server/src/routes/crm.routes.ts:826`. Fix: `requireManagerOrAdmin`.
- [ ] SCAN-114. **[SEC] crm PATCH /crm/reviews/:id no role gate — any user replies + toggles public_posted** — `packages/server/src/routes/crm.routes.ts:884`. Fix: `requireManagerOrAdmin`.
- [ ] SCAN-115. **crm refreshSegmentMembership DELETE + N INSERTs not in transaction — empty segment on crash** — `packages/server/src/routes/crm.routes.ts:784`. Fix: `adb.transaction()` wrap DELETE + INSERTs + count UPDATE.
- [ ] SCAN-116. **[SEC] bench GET /timer/by-ticket/:ticketId no tenant/ownership check — labor rates + notes leak** — `packages/server/src/routes/bench.routes.ts:534`. Fix: join tickets + enforce tenant_id or role.
- [ ] SCAN-117. **[SEC] bench GET /defects/stats + /defects/by-item/:id no role gate** — `packages/server/src/routes/bench.routes.ts:1057`. Fix: manager/admin gate.
- [ ] SCAN-118. **[SEC] deviceTemplates POST /:id/apply-to-ticket/:ticketId no role gate (peers are admin-only)** — `packages/server/src/routes/deviceTemplates.routes.ts:382`. Fix: admin check matching sibling handlers.
- [ ] SCAN-119. **N+1 enrichTemplate — adb.get per part in serial loop** — `packages/server/src/routes/deviceTemplates.routes.ts:108`. Fix: batch SELECT WHERE id IN.
- [ ] SCAN-120. **[SEC] employees GET / no role gate — any user enumerates username/email/role/permissions of all employees** — `packages/server/src/routes/employees.routes.ts:171`. Fix: manager/admin gate or minimal public shape.
- [ ] SCAN-121. **[SEC] employees GET /performance/all no role gate — revenue + repair times per employee leak** — `packages/server/src/routes/employees.routes.ts:191`. Fix: admin/manager gate.
- [ ] SCAN-122. **expenses PUT /:id no ownership/role check (DELETE has it)** — `packages/server/src/routes/expenses.routes.ts:111`. Fix: `admin OR existing.user_id === req.user.id`.
- [ ] SCAN-123. **[SEC] crm GET /customers/:id/subscriptions uses SELECT * exposing card_token** — `packages/server/src/routes/crm.routes.ts:456`. Fix: explicit column list, omit card_token.
- [ ] SCAN-124. **customFields GET /values/:entityType/:entityId missing VALID_ENTITY_TYPES whitelist on read (PUT has it)** — `packages/server/src/routes/customFields.routes.ts:120`. Fix: add allowlist guard.

### Server routes — import/inbox/inventoryEnrich/management/notifications/posEnrich (12 findings)
- [ ] SCAN-125. **[SEC] import /repairshopr SSRF via unvalidated subdomain** — `packages/server/src/routes/import.routes.ts:593`. Fix: regex `^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$` before string interp.
- [ ] SCAN-126. **import /repairdesk/nuclear role check ordered after confirm parse — leaks error sequence** — `packages/server/src/routes/import.routes.ts:473`. Fix: move role check to handler top.
- [ ] SCAN-127. **import rate-limit TOCTOU — two concurrent starts pass check simultaneously** — `packages/server/src/routes/import.routes.ts:248`. Fix: record rate-limit row inside same tx as lock claim.
- [ ] SCAN-128. **[SEC] inbox PATCH /conversation/:phone/assign no ownership/role check — any user reassigns any conversation** — `packages/server/src/routes/inbox.routes.ts:221`. Fix: admin/manager or current-assignee check.
- [ ] SCAN-129. **[SEC] inbox /retry-queue/:id/retry + /cancel no role check — cashier retries/cancels any SMS** — `packages/server/src/routes/inbox.routes.ts:647`. Fix: `requireAdmin` or manager-or-admin.
- [ ] SCAN-130. **[SEC] notifications POST /send-receipt IDOR — any auth user mails any invoice to any email** — `packages/server/src/routes/notifications.routes.ts:181`. Fix: ownership/tenant scope + email format validation.
- [ ] SCAN-131. **notifications PUT /focus-policies no JSON size cap — multi-MB blob stored** — `packages/server/src/routes/notifications.routes.ts:148`. Fix: `Buffer.byteLength(json) > 32KB` guard matching preferences.
- [ ] SCAN-132. **[SEC] inventoryEnrich POST /assign-bin/:id IDOR + no role gate** — `packages/server/src/routes/inventoryEnrich.routes.ts:305`. Fix: verify inventory_items.id exists + manager/admin role.
- [ ] SCAN-133. **inventoryEnrich PUT /serials/:serialId — no `changes` check, SELECT then res.json undefined on missing id** — `packages/server/src/routes/inventoryEnrich.routes.ts:569`. Fix: check update changes > 0 or 404; drop redundant SELECT.
- [ ] SCAN-134. **[SEC] posEnrich manager PIN verify — bcrypt.compareSync in .find() loop — timing oracle on manager count** — `packages/server/src/routes/posEnrich.routes.ts:597`. Fix: constant-time accumulation, no short-circuit.
- [ ] SCAN-135. **import GET /history in-memory JSON parse on unbounded error_log column** — `packages/server/src/routes/import.routes.ts:439`. Fix: SQL substr cap or limit error_log entries at write time.
- [ ] SCAN-136. **management POST /reenable-route accepts arbitrary-length string route** — `packages/server/src/routes/management.routes.ts:449`. Fix: max-200 + pattern `^/[a-zA-Z0-9/_:-]+$`.

### Server routes — settings/roles/team/teamChat/stocktake/tracking/tv/settingsExport (12 findings)
- [ ] SCAN-137. **[SEC] settings PUT /store writes tcx_password + smtp_pass cleartext to store_config (bypasses ENCRYPTED_CONFIG_KEYS of PUT /config)** — `packages/server/src/routes/settings.routes.ts:479`. Fix: encrypt matching keys + emit audit log for sensitive keys.
- [ ] SCAN-138. **settings PUT /statuses/:id missing integer validation on params.id** — `packages/server/src/routes/settings.routes.ts:552`. Fix: `parseId(...)` guard.
- [ ] SCAN-139. **settings DELETE /statuses/:id missing integer validation on id** — `packages/server/src/routes/settings.routes.ts:588`. Fix: same parseId guard.
- [ ] SCAN-140. **[SEC] settingsExport GET /history missing adminOnly — any user reads settings audit log** — `packages/server/src/routes/settingsExport.routes.ts:401`. Fix: add `adminOnly` middleware.
- [ ] SCAN-141. **[SEC] roles GET /:id/permissions no requireAdmin — any user reads role permission matrix** — `packages/server/src/routes/roles.routes.ts:220`. Fix: `requireAdmin(req)`.
- [ ] SCAN-142. **[SEC] roles PUT /users/:userId/role writes user_custom_roles but never syncs users.role — authMiddleware reads stale role** — `packages/server/src/routes/roles.routes.ts:282`. Fix: when custom role maps to built-in, sync `users.role`.
- [ ] SCAN-143. **[SEC] team GET /shifts accepts `user_id` filter with no ownership guard — enumerate any employees schedule** — `packages/server/src/routes/team.routes.ts:83`. Fix: non-admin/manager restricted to own user_id.
- [ ] SCAN-144. **team GET /payroll/export.csv gross wrong (no rate multiplication) + username not CSV-sanitized** — `packages/server/src/routes/team.routes.ts:808`. Fix: wrap username in sanitize(); fix gross formula or document commission-only.
- [ ] SCAN-145. **[SEC] teamChat GET + POST /channels/:id/messages no membership check — any user reads/posts private direct channels** — `packages/server/src/routes/teamChat.routes.ts:167`. Fix: membership lookup or participant-match for direct channels.
- [ ] SCAN-146. **[SEC] stocktake POST / no role gate — cashier opens session + locks expected_qty snapshot** — `packages/server/src/routes/stocktake.routes.ts:87`. Fix: `requireAdminOrManager`.
- [ ] SCAN-147. **tracking GET /:orderId `recordWindowFailure` unconditional — legit customers throttled on valid reads** — `packages/server/src/routes/tracking.routes.ts:181`. Fix: only on failed token match.
- [ ] SCAN-148. **[SEC] tv GET /board exposes customer_last_name on public TV feed + no rate-limit on unauth path** — `packages/server/src/routes/tv.routes.ts:186`. Fix: strip last_name in shapeTicket output; add per-IP rate-limit.

### Electron management package (10 findings)
- [ ] SCAN-149. **[SEC-P0] service:* IPC handlers (get-status/start/stop/restart/emergency-stop/set-auto-start/disable/kill-all) all skip assertRendererOrigin** — `packages/management/src/main/ipc/service-control.ts:596`. Fix: add `assertRendererOrigin(event)` as first line of each.
- [ ] SCAN-150. **[SEC] system:open-log-file missing assertRendererOrigin — opens shell/cmd.exe** — `packages/management/src/main/ipc/system-info.ts:237`. Fix: add guard + accept event arg.
- [ ] SCAN-151. **service:set-auto-start no runtime typeof check on boolean arg** — `packages/management/src/main/ipc/service-control.ts:697`. Fix: `typeof enabled !== 'boolean'` reject.
- [ ] SCAN-152. **[SEC] admin:list-logs returns absolute filesystem paths to renderer — install-dir leak** — `packages/management/src/main/ipc/management-api.ts:1855`. Fix: omit path or replace with `exists:boolean`.
- [ ] SCAN-153. **[SEC] super-admin:2fa-verify returns raw JWT token in IPC response — renderer exfil risk** — `packages/management/src/main/ipc/management-api.ts:944`. Fix: strip token field before return.
- [ ] SCAN-154. **management:perform-update inherits COMSPEC env in spawned cmd.exe — resolution hijack risk** — `packages/management/src/main/ipc/management-api.ts:1478`. Fix: strip COMSPEC; use explicit cmd.exe path from SystemRoot.
- [ ] SCAN-155. **[SEC] SchemaBrowseDrive accepts any 4096-char Windows-root path — enumerate System32, user dirs** — `packages/management/src/main/ipc/management-api.ts:85`. Fix: restrict to data-dir prefix + block known sensitive paths.
- [ ] SCAN-156. **tryPowershellDiskSpace uses execSync(string) — shell-interpreted; SystemRoot hijack risk** — `packages/management/src/main/ipc/system-info.ts:158`. Fix: spawnSync with `shell:false` + arg array.
- [ ] SCAN-157. **renderer main.tsx uses innerHTML for fallback error page + CSP style-src 'unsafe-inline'** — `packages/management/src/renderer/src/main.tsx:78`. Fix: DOM construction (createElement+textContent) + drop style-src unsafe-inline.
- [ ] SCAN-158. **[SEC] Electron pinned 39.8.7 — no longer in support window (Electron supports newest 3 majors)** — `packages/management/package.json:37`. Fix: bump to supported stable + re-run flip-fuses afterPack.

### Web public pages + WS + teamChat + tests (12 findings)
- [ ] SCAN-159. **LandingPage nav missing aria-label + hamburger missing aria-label/aria-expanded** — `packages/web/src/pages/landing/LandingPage.tsx:243,259`. Fix: add aria attributes.
- [ ] SCAN-160. **LandingPage no title/meta description/OG tags — crawlers see empty head** — `packages/web/src/pages/landing/LandingPage.tsx:1`. Fix: react-helmet-async in page.
- [ ] SCAN-161. **SignupPage no title/meta description** — `packages/web/src/pages/signup/SignupPage.tsx:258`. Fix: react-helmet-async.
- [ ] SCAN-162. **teamChat POST /channels/:id/messages no per-user rate-limit — message flood DoS** — `packages/server/src/routes/teamChat.routes.ts:192`. Fix: `consumeWindowRate` 60/min/user, 429 on breach.
- [ ] SCAN-163. **PrintPage diagnostic note stripped with `replace(/<[^>]*>/g,'')` — malformed `<img src=x onerror=...>` slips** — `packages/web/src/pages/print/PrintPage.tsx:620`. Fix: replace with `sanitizePrintText()` already defined line 52.
- [ ] SCAN-164. **EstimateDetailPage versions array typed any[]** — `packages/web/src/pages/estimates/EstimateDetailPage.tsx:44,377`. Fix: `VersionRow` interface.
- [ ] SCAN-165. **CatalogPage query result + job list cast to any[]** — `packages/web/src/pages/catalog/CatalogPage.tsx:75-86,383`. Fix: `CatalogItem` + `SyncJob` interfaces.
- [ ] SCAN-166. **PhotoCapturePage catch(e:any) — use unknown** — `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:75`. Fix: `catch(e:unknown)` + AxiosError narrow.
- [ ] SCAN-167. **LandingPage bare `<button>` elements missing `type="button"` — latent submit risk** — `packages/web/src/pages/landing/LandingPage.tsx:254,257,263,266,287,349,446`. Fix: add `type="button"`.
- [ ] SCAN-168. **teamChat GET /channels no tenant_id column on channels — channel scoping assumed not enforced** — `packages/server/src/routes/teamChat.routes.ts:77`. Fix: add tenant_id column + `WHERE tenant_id=?` or assert isolated-DB model.
- [ ] SCAN-169. **TeamChatPage polls `?limit=200` every 5s regardless of activity + drops history on busy channels** — `packages/web/src/pages/team/TeamChatPage.tsx:68`. Fix: use `?after=<lastId>` incremental polling.
- [ ] SCAN-170. **SubscriptionsListPage useQuery missing onError — generic "Failed to load"** — `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:98`. Fix: onError toast with message.

## AUDIT CYCLE 3 — 2026-04-23 (parallel discovery wave 4: shared utils + middleware + WebSocket + deep web pos/auth + tests/docs)

### Server utils (12 findings)
- [ ] SCAN-171. **[SEC] csrf safeEquals leaks token length — early-return on `bufA.length !== bufB.length`** — `packages/server/src/utils/csrf.ts:48-51`. Fix: pad both buffers to fixed 64 bytes before `timingSafeEqual`.
- [ ] SCAN-172. **logger PII masking gated on NODE_ENV==='production' — staging/unset env leaks** — `packages/server/src/utils/logger.ts:88-91`. Fix: default-on masking gated on `nodeEnv !== 'development'`.
- [ ] SCAN-173. **logger redactMetaValue recurses only 1 level deep — nested `{error:{details:{to:...}}}` slips** — `packages/server/src/utils/logger.ts:59-68`. Fix: recurse with max-depth cap.
- [ ] SCAN-174. **logger formatOutput JSON.stringify not wrapped — BigInt/toJSON throw/circular refs throw out of log calls** — `packages/server/src/utils/logger.ts:101-103`. Fix: try/catch with fallback serializer.
- [ ] SCAN-175. **[SEC] configEncryption derives key via HMAC-SHA256 not HKDF — weak KDF with no salt/cost** — `packages/server/src/utils/configEncryption.ts:26`. Fix: `crypto.hkdfSync` with info + salt.
- [ ] SCAN-176. **duplicate MAX_PAGE_SIZE — constants.ts=1000 vs pagination.ts=100 — routes importing wrong one bypass SEC-H120** — `packages/server/src/utils/constants.ts:8`. Fix: single source of truth.
- [ ] SCAN-177. **validateEnum does NOT lowercase trimmed value (comment claims it does) — case mismatch bugs** — `packages/server/src/utils/validate.ts:192-207`. Fix: `.toLowerCase()` before allowed.includes.
- [ ] SCAN-178. **rateLimiter check-then-act race — checkLockoutRate + recordLockoutFailure not atomic, concurrent pass both** — `packages/server/src/utils/rateLimiter.ts:88-106,122-132`. Fix: `checkAndRecordLockout` in single tx.
- [ ] SCAN-179. **masterAudit logSecurityAlert JSON.stringify(details) unguarded — console warning lost on circular/BigInt** — `packages/server/src/utils/masterAudit.ts:137`. Fix: try/catch + safe fallback.
- [ ] SCAN-180. **[SEC] signedUploads canonicalString pipe-delimits type|slug|file|exp without escaping — `|` in file forges signatures** — `packages/server/src/utils/signedUploads.ts:33-35`. Fix: percent-encode components or length-prefixed form.
- [ ] SCAN-181. **validateId parseInt truncates "42abc" → 42 silently — regex guard missing** — `packages/server/src/utils/validate.ts:326-331`. Fix: `/^-?\d+$/` guard like validateQuantity.
- [ ] SCAN-182. **N+1 in calculateActiveRepairTime — db.prepare().get() inside .reverse().find() loop** — `packages/server/src/utils/repair-time.ts:86-91`. Fix: preload ticket_statuses into Map or JOIN in initial query.

### Server middleware (12 findings)
- [ ] SCAN-183. **[SEC] auth token-type check only rejects defined-non-access — tokens missing `type` claim pass** — `packages/server/src/middleware/auth.ts:82`. Fix: require `payload.type === 'access'` explicitly.
- [ ] SCAN-184. **[SEC] auth parses permissions JSON without boolean-value validation — corrupt `permissions: {admin.full:true}` grants anything** — `packages/server/src/middleware/auth.ts:174-176,213,232`. Fix: validate value typeof boolean, discard non-boolean.
- [ ] SCAN-185. **auth `.catch()` swallows all DB errors as 401 — DB outage indistinguishable from auth fail, masks availability** — `packages/server/src/middleware/auth.ts:183`. Fix: 503 on infra errors + log.
- [ ] SCAN-186. **[SEC] errorHandler spreads AppError `extra` into top-level JSON — sensitive fields leak** — `packages/server/src/middleware/errorHandler.ts:73`. Fix: namespace under `details` key + allowlist.
- [ ] SCAN-187. **tenantResolver calls next() without req.db on master DB failure — downstream crash** — `packages/server/src/middleware/tenantResolver.ts:428-431`. Fix: 503 JSON response.
- [ ] SCAN-188. **[SEC] tenantResolver builds asyncDb path directly (joins tenantDataDir + slug+'.db') bypassing getTenantDb traversal checks** — `packages/server/src/middleware/tenantResolver.ts:488`. Fix: use validated resolver path.
- [ ] SCAN-189. **[SEC] fileUploadValidator route allowedMimes compares client-declared MIME not magic-byte-detected** — `packages/server/src/middleware/fileUploadValidator.ts:251`. Fix: compare against detected type returned by `validateFileMagicBytes`.
- [ ] SCAN-190. **fileUploadValidator counter race — readFileCounter + adjustFileCounter read-then-write not atomic; concurrent uploads under-count quota** — `packages/server/src/middleware/fileUploadValidator.ts:111-136,158`. Fix: per-tenant mutex or exclusive file lock.
- [ ] SCAN-191. **crashResiliency uses module-level `currentRequestRoute` — interleaved requests misattribute crash routes** — `packages/server/src/middleware/crashResiliency.ts:17,34`. Fix: AsyncLocalStorage or res.locals.
- [ ] SCAN-192. **requestLogger SENSITIVE_HEADER_NAMES declared + `void` suppressed — never applied to log meta** — `packages/server/src/middleware/requestLogger.ts:141-142`. Fix: apply redaction or remove dead set.
- [ ] SCAN-193. **tenantResolver dev-mode DEV_TENANT_SLUG not regex-validated before query** — `packages/server/src/middleware/tenantResolver.ts:325`. Fix: regex guard matching normal slug rules.
- [ ] SCAN-194. **[SEC] stepUpTotp audit log IP from req.ip (XFF-spoofable) — audit trails unreliable** — `packages/server/src/middleware/stepUpTotp.ts:154,289`. Fix: req.socket.remoteAddress or validate XFF against trusted proxy allowlist.

### Server WebSocket + startup (7 findings)
- [ ] SCAN-195. **[SEC] WS TOCTOU — client registered in `clients` map before async isTenantOriginAllowed() resolves** — `packages/server/src/ws/server.ts:450-465,467-473`. Fix: await origin check before send/register.
- [ ] SCAN-196. **WS heartbeat terminate path never decrements wsConnsByIp/wsConnsByTenant — counter bloat blocks reconnects** — `packages/server/src/ws/server.ts:582-607`. Fix: explicit decrement or shared close-cleanup helper.
- [ ] SCAN-197. **WS broadcast() no per-event throttle — high-frequency event saturates event loop** — `packages/server/src/ws/server.ts:634-668`. Fix: per-event-type throttle/debounce or frames-per-second cap.
- [ ] SCAN-198. **shutdown() server.close() doesn't terminate open WS — 10s forced exit(1) looks like crash** — `packages/server/src/index.ts:3429`. Fix: iterate allClients + ws.terminate() before server.close().
- [ ] SCAN-199. **[SEC] no per-IP new-connection-rate limit on WS pre-auth — rapid connect/close storm** — `packages/server/src/ws/server.ts:98-99`. Fix: 10/10s per IP.
- [ ] SCAN-200. **WS close-handler re-reads req.socket.remoteAddress — may differ from connect-time key under reuse** — `packages/server/src/ws/server.ts:272-302,545`. Fix: store ws._clientIp on socket object.
- [ ] SCAN-201. **[SEC] WS role from JWT payload not re-validated — downgraded admins continue receiving unredacted PII until token expiry** — `packages/server/src/ws/server.ts:417-418`. Fix: re-fetch role from DB at auth time OR short-lived WS auth tokens with re-auth.

### Web deep pos/auth/pos/setup/gift-cards (11 findings)
- [ ] SCAN-202. **LoginPage two concurrent setupStatus() calls on mount — overlapping race on step/autoChecking state** — `packages/web/src/pages/auth/LoginPage.tsx:92,118`. Fix: consolidate into single effect with shared cancelled flag.
- [ ] SCAN-203. **ResetPasswordPage setTimeout(navigate,3000) not cleared on unmount** — `packages/web/src/pages/auth/ResetPasswordPage.tsx:68`. Fix: store id + clearTimeout in cleanup.
- [ ] SCAN-204. **UnifiedPosPage scanFlash setTimeout(1200) inside keydown listener no cleanup on unmount** — `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:125`. Fix: ref + clear in effect cleanup.
- [ ] SCAN-205. **UnifiedPosPage usePosKeyboardShortcuts no modal-open guard — F5 during checkout re-opens modal** — `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:163`. Fix: bail when showCheckout/showSuccess true.
- [ ] SCAN-206. **[SEC/UX] RepairsTab collects device passcode in `type="text"` (unmasked) — shared-display leak** — `packages/web/src/pages/unified-pos/RepairsTab.tsx:748`. Fix: type=password + autoComplete=off + show/hide toggle.
- [ ] SCAN-207. **[SEC] setup StepEmailSmtp smtp_pass lacks autoComplete — browsers autofill saved login passwords into SMTP secret field** — `packages/web/src/pages/setup/steps/StepEmailSmtp.tsx:15`. Fix: `autoComplete="new-password"` on sensitive inputs.
- [ ] SCAN-208. **[SEC] setup StepSmsProvider all sensitive API-secret inputs lack autoComplete** — `packages/web/src/pages/setup/steps/StepSmsProvider.tsx:34`. Fix: autoComplete=off in field() helper when sensitive=true.
- [ ] SCAN-209. **CashRegisterPage history typed any[] — render branches silently wrong on shape drift** — `packages/web/src/pages/pos/CashRegisterPage.tsx:22`. Fix: `RegisterEntry` interface.
- [ ] SCAN-210. **GiftCardDetailPage show/hide code toggle button icon-only, no aria-label** — `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:210`. Fix: aria-label toggle string.
- [ ] SCAN-211. **GiftCardsListPage modal close button icon-only, no aria-label** — `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:139`. Fix: aria-label="Close".
- [ ] SCAN-212. **CustomerSelector remove-customer button uses title but no aria-label** — `packages/web/src/pages/unified-pos/CustomerSelector.tsx:171`. Fix: aria-label="Remove customer".

### Tests / docs / startup / portal i18n (12 findings)
- [ ] SCAN-213. **[SEC] full-import script hard-coded fallback password 'admin123' (env-optional)** — `packages/server/src/scripts/full-import.ts:33`. Fix: drop fallback; throw if `ADMIN_PASSWORD` unset.
- [ ] SCAN-214. **[SEC] tenant-provisioning hard-codes bcrypt('1234') PIN for every new tenant admin — startup guard only checks single-tenant** — `packages/server/src/services/tenant-provisioning.ts:336`. Fix: require PIN at provisioning or force change on first login.
- [ ] SCAN-215. **startup blocks on sync syncCostPricesFromCatalog — row-by-row fuzzy match during boot** — `packages/server/src/index.ts:539`. Fix: move post-listen async (setImmediate or after readyPromise).
- [ ] SCAN-216. **TLS cert path hard-coded relative + no hot-reload — renewal requires restart** — `packages/server/src/index.ts:557-566`. Fix: SIGHUP handler + `httpsServer.setSecureContext(freshOpts)`.
- [ ] SCAN-217. **[SEC] /api/v1/tv mounted with no auth, gated only on DB toggle — misprovisioned default exposes PII** — `packages/server/src/index.ts:1617-1622`. Fix: shared secret or IP-allowlist + add security test.
- [ ] SCAN-218. **CLAUDE.md stale: "24 migrations (001-024)" — current count ~122** — `C:/Users/Owner/Downloads/MY OWN CRM/CLAUDE.md:69`. Fix: update count to highest migration.
- [ ] SCAN-219. **[SEC] /api/v1/health/ready leaks schemaVersion to unauth caller — aids fingerprinting** — `packages/server/src/index.ts:1765-1772`. Fix: remove from unauth response or move to /health/internal.
- [ ] SCAN-220. **PortalLogin + PortalRegister inline error divs lack role="alert" / aria-live — SR misses errors** — `packages/web/src/pages/portal/PortalLogin.tsx:122` + PortalRegister:119. Fix: add role=alert.
- [ ] SCAN-221. **Portal i18n only EN/ES + hardcoded English error strings slip through (mapRegisterError + catch literals)** — `packages/web/src/pages/portal/i18n.ts:15-153`. Fix: move errors through t() with dict keys in both locales.
- [ ] SCAN-222. **management endpoints skip global rate-limiter (explicit bypass) — localhost SSRF enumerates crashes/disabled-routes unlimited** — `packages/server/src/routes/management.routes.ts:365-445` + `index.ts:1133`. Fix: lightweight rate-limit even on loopback.
- [ ] SCAN-223. **zero security-tests coverage on /api/v1/tv, /api/v1/signup, /portal/api/v2, /api/v1/public/payment-links** — all three phases. Fix: add cases (TV toggle-off empty, toggle-on no PII, signup rate-limit, portal-enrich session-required, payment link expiry/reuse).
- [ ] SCAN-224. **[SEC] scripts/clear-imported-data.sh interpolates $ENTITY into inline node -e string + `batch` IDs concatenated into `DELETE ... IN (${batch})`** — `scripts/clear-imported-data.sh:57-121`. Fix: node process.argv + prepared statements.

## AUDIT CYCLE 3 — 2026-04-23 (parallel discovery wave 5: bundle + api types + 2FA/reset + upload/restore/template + class-level + build scripts)

### Web api types / bundle / cache (12 findings)
- [ ] SCAN-225. **customerApi.list params type omits sort_by/sort_order — callers use `as any`** — `packages/web/src/api/endpoints.ts:103` + CustomerListPage.tsx:169. Fix: add both to params type.
- [ ] SCAN-226. **customerApi.list response untyped — consumers implicit any on `.data.data`** — `packages/web/src/api/endpoints.ts:104`. Fix: `api.get<{...}>` explicit generic.
- [ ] SCAN-227. **ticketApi.list response untyped — same pattern** — `packages/web/src/api/endpoints.ts:154`. Fix: typed generic.
- [ ] SCAN-228. **invoiceApi.list response untyped — same pattern** — `packages/web/src/api/endpoints.ts:242`. Fix: typed generic.
- [ ] SCAN-229. **UpdateUserInput.role typed bare string (CreateUserInput uses literal union)** — `packages/web/src/api/types.ts:240`. Fix: `'admin'|'manager'|'technician'|'cashier'`.
- [ ] SCAN-230. **CheckoutWithTicketInput product_items + misc_items typed `unknown[]`** — `packages/web/src/api/types.ts:335-336`. Fix: `PosLineItem[]`.
- [ ] SCAN-231. **RepairPricingTab useQuery casts catalogApi.searchDevices result `as any[]`** — `packages/web/src/pages/settings/RepairPricingTab.tsx:323`. Fix: type via CatalogDevice[].
- [ ] SCAN-232. **DepositCollectModal useMutation onSuccess missing invalidateQueries — invoices/ticket totals stale** — `packages/web/src/pages/billing/DepositCollectModal.tsx:42`. Fix: invalidate `['invoices']` + `['tickets', ticketId]`.
- [ ] SCAN-233. **QuickSmsModal multiple `any` types (templates/tpl/onError/grouped)** — `packages/web/src/components/shared/QuickSmsModal.tsx:29,42,59,69`. Fix: `SmsTemplate` read-model.
- [ ] SCAN-234. **CustomerListPage `as any` on customerApi.list call — cascade of SCAN-225** — `packages/web/src/pages/customers/CustomerListPage.tsx:169`. Fix: remove cast after fixing endpoints.ts:103.
- [ ] SCAN-235. **CatalogPage jobsData `as any[]`** — `packages/web/src/pages/catalog/CatalogPage.tsx:75`. Fix: type catalogApi.getJobs response.
- [ ] SCAN-236. **TicketWizard popularDevices `as any[]` via catalogApi.searchDevices** — `packages/web/src/pages/tickets/TicketWizard.tsx:327`. Fix: CatalogDevice interface propagated.

### 2FA/TOTP/password-reset (7 findings)
- [ ] SCAN-237. **[SEC] TOTP code reuse within 30s window — no `afterTimeStep` guard, same 6 digits valid twice** — `packages/server/src/routes/auth.routes.ts:922,1394,1790`. Fix: persist `totp_last_used_step` on users; pass `afterTimeStep` to `verifySync`.
- [ ] SCAN-238. **[SEC] POST /reset-password no rate-limit — token brute-force allowed** — `packages/server/src/routes/auth.routes.ts:1648`. Fix: `checkWindowRate(db, 'reset_password', ip, 5, 900_000)` + 429.
- [ ] SCAN-239. **[SEC] POST /forgot-password IP-only rate-limit — distributed attacker floods victim inbox + invalidates in-flight tokens** — `packages/server/src/routes/auth.routes.ts:1532`. Fix: per-user (per-email) limit (2/hour) after user lookup.
- [ ] SCAN-240. **[SEC] TOTP setup response returns plaintext base32 `secret` + `manualEntry` — captured by any logging proxy** — `packages/server/src/routes/auth.routes.ts:856`. Fix: strip from JSON; require client to parse secret from QR URI.
- [ ] SCAN-241. **POST /reset-password distinct error messages leak format vs DB-miss** — `packages/server/src/routes/auth.routes.ts:1650,1670`. Fix: single message regardless of failure mode.
- [ ] SCAN-242. **/account/2fa/disable audit row reveals which factor failed (`bad_password` vs `bad_totp`)** — `packages/server/src/routes/auth.routes.ts:1797`. Fix: audit 'bad_credentials'; keep factor detail only in non-tenant monitoring.
- [ ] SCAN-243. **[SEC] /login/2fa-setup enrolls new TOTP device on challenge token alone — no password re-confirmation** — `packages/server/src/routes/auth.routes.ts:833`. Fix: require password at setup endpoint OR authMiddleware + current_password.

### Photo upload / backup-restore / template injection (7 findings)
- [ ] SCAN-244. **[SEC] uploaded photos retain EXIF GPS — customer/device location leak** — `packages/server/src/routes/tickets.routes.ts:57-68`. Fix: `sharp().rotate().withMetadata(false)` or `exifr` strip before final write.
- [ ] SCAN-245. **photo-upload scoped-token concurrent batches bypass file-count quota** — `packages/server/src/routes/tickets.routes.ts:2264` + fileUploadValidator. Fix: reserve slot atomically pre-multer or per-tenant mutex.
- [ ] SCAN-246. **PhotoCapturePage soft 0/20 counter advisory only — rapid Add-more queues >20, server silently drops excess** — `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:29-52`. Fix: hard-enforce `photos.length + valid.length <= 20` + surface error.
- [ ] SCAN-247. **SMS body never length-capped after `{customer_name}` substitution — long name inflates multi-part carrier charges** — `packages/server/src/services/notifications.ts:428-433`. Fix: hard-truncate to `MAX_SMS_CHARS` (~306) after substitution.
- [ ] SCAN-248. **[SEC] email template fallback path uses SMS body as HTML — raw customer name rendered unescaped** — `packages/server/src/services/notifications.ts:506-511`. Fix: `escapeHtml(body)` before passing as `html:` when email_body absent.
- [ ] SCAN-249. **[SEC] signedUploads URL valid for full 1h TTL with no revoke-on-use — replay to re-download receipt images** — `packages/server/src/utils/signedUploads.ts:57`. Fix: nonce table marking signature consumed OR reduce TTL to ≤300s for receipt/MMS.
- [ ] SCAN-250. **[SEC] restoreBackup fires on single POST — no service-layer confirmation/time-lock — CSRF-triggered DB wipe** — `packages/server/src/services/backup.ts:803-924`. Fix: require `confirm=true` + two-step token (60s TTL) + UI countdown.

### Class-level sweeps across routes (10 findings)
- [ ] SCAN-251. **SELECT * on `marketing_campaigns` leaks internal columns** — `packages/server/src/routes/campaigns.routes.ts:354`. Fix: enumerate frontend-needed columns.
- [ ] SCAN-252. **automations params.id uses bare `Number()` — `Number('')===0` matches unintended rows** — `packages/server/src/routes/automations.routes.ts:108`. Fix: `Number.isInteger + >0` guard.
- [ ] SCAN-253. **voice list LIMIT/OFFSET without COUNT(*) total — client can't page last** — `packages/server/src/routes/voice.routes.ts:202`. Fix: parallel SELECT COUNT(*) + return total/total_pages.
- [ ] SCAN-254. **estimate_versions JSON.parse(version.data) with no try/catch — corrupt row crashes handler** — `packages/server/src/routes/estimates.routes.ts:678`. Fix: try/catch → 422.
- [ ] SCAN-255. **membership.subscription.benefits JSON.parse crashes status page on corrupt row** — `packages/server/src/routes/membership.routes.ts:133`. Fix: try/catch → `[]`.
- [ ] SCAN-256. **automations UPDATE uses `datetime('now')` (SQLite UTC) — inconsistent with JS `toISOString()` elsewhere** — `packages/server/src/routes/automations.routes.ts:117`. Fix: parameterized ISO timestamp.
- [ ] SCAN-257. **blockchyp audit() outside transaction block — split failure mode** — `packages/server/src/routes/blockchyp.routes.ts:344-393,399`. Fix: inside tx OR explicit best-effort try/catch + documented.
- [ ] SCAN-258. **deposits GET returns raw DB row (created_at/updated_at/soft-delete)** — `packages/server/src/routes/deposits.routes.ts:91`. Fix: explicit destructure of API-contract fields.
- [ ] SCAN-259. **customFields SELECT uses raw req.params.id — no integer parse/validate** — `packages/server/src/routes/customFields.routes.ts:81`. Fix: parseInt + Number.isInteger + >0.
- [ ] SCAN-260. **[SEC] automations SELECT * returns trigger_config + action_config (may contain webhook_secret / api_key)** — `packages/server/src/routes/automations.routes.ts:44`. Fix: redact secret fields in response mapping.

### Build / CI / infra / CSS (9 findings)
- [ ] SCAN-261. **[SEC] .github/workflows/ci.yml pins actions by mutable tag (@v4) not SHA — tag force-push supply-chain risk** — `.github/workflows/ci.yml:16`. Fix: pin to commit SHA per GitHub Actions hardening guide.
- [ ] SCAN-262. **[SEC] .github/workflows/ios-a11y.yml same mutable-tag pinning** — `.github/workflows/ios-a11y.yml:36,56`. Fix: SHA pin.
- [ ] SCAN-263. **[SEC] scripts/stress-test.sh uses `eval "$CURL ... $args '$url'"` — shell-meta in ENDPOINTS/PAYLOADS executes** — `scripts/stress-test.sh:98`. Fix: array-based invocation `"${curl_cmd[@]}"`.
- [ ] SCAN-264. **[SEC] CommunicationPage inline-style status_color not through `safeColor()` — CSS injection** — `packages/web/src/pages/communications/CommunicationPage.tsx:1452,1575`. Fix: wrap with safeColor() (pattern already in TicketSidebar).
- [ ] SCAN-265. **[SEC] DashboardPage status_color interpolated into style prop without safeColor** — `packages/web/src/pages/dashboard/DashboardPage.tsx:970,1994`. Fix: import + wrap safeColor.
- [ ] SCAN-266. **[SEC] ios/scripts/fetch-fonts.sh downloads `google/fonts/main` branch (unpinned) at build-time** — `ios/scripts/fetch-fonts.sh:45,66,78`. Fix: pin by commit SHA + sha256sum verify.
- [ ] SCAN-267. **[SEC] Dockerfile `npm ci` without `--ignore-scripts` — postinstall runs as root pre-`USER node`** — `packages/server/Dockerfile:15`. Fix: `--ignore-scripts` on all `npm ci` calls; run needed scripts explicitly.
- [ ] SCAN-268. **[SEC] setup.bat uses `call npm install` (mutable) — postinstall hooks from attacker-modified lockfile execute on dev machines** — `setup.bat:66`. Fix: `npm ci --ignore-scripts`.
- [ ] SCAN-269. **No `npm-shrinkwrap.json` — production Docker + setup.bat rely solely on mutable package-lock.json** — repo root. Fix: `npm shrinkwrap` for server package + commit.

## AUDIT CYCLE 3 — 2026-04-23 (parallel discovery wave 6: cache invalidation 2nd pass + regex DoS + TZ + form edges + PWA + inventory deep + CSS/SVG)

### React Query cache invalidation + error boundaries (8 findings)
- [ ] SCAN-270. **CheckoutModal posApi.checkoutWithTicket success — no invalidate for invoices/tickets/inventory** — `packages/web/src/pages/unified-pos/CheckoutModal.tsx:345`. Fix: invalidate all three in the try block after setShowSuccess.
- [ ] SCAN-271. **TicketPayments convertInvoiceMut onSuccess only invalidates ticket, not invoices list** — `packages/web/src/pages/tickets/TicketPayments.tsx:57`. Fix: `invalidateQueries({queryKey:['invoices']})` in onSuccess.
- [ ] SCAN-272. **InvoiceDetailPage payMutation onSuccess doesn't invalidate `['ticket', invoice.ticket_id]`** — `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:78`. Fix: add ticket invalidation when ticket_id present.
- [ ] SCAN-273. **EstimateDetailPage convertMut onSuccess doesn't invalidate `['tickets']` list** — `packages/web/src/pages/estimates/EstimateDetailPage.tsx:69`. Fix: add invalidation for tickets list.
- [ ] SCAN-274. **ErrorBoundary doesn't report to any service — only console.error + reload clears signal** — `packages/web/src/components/ErrorBoundary.tsx:28`. Fix: Sentry (or similar) capture in componentDidCatch with componentStack.
- [ ] SCAN-275. **No per-feature ErrorBoundary around POS checkout tree — crash during live payment hides invoice status from cashier** — `packages/web/src/App.tsx:362`. Fix: wrap CheckoutModal or UnifiedPosPage in dedicated boundary with recovery UI.
- [ ] SCAN-276. **TicketDetailPage scheduleTicketDelete optimistic setQueriesData but no previousData snapshot — undo can't restore on invalidation failure** — `packages/web/src/pages/tickets/TicketDetailPage.tsx:316`. Fix: snapshot via `getQueriesData` pre-write; restore via `setQueriesData(snapshot)` in onUndo before invalidate.
- [ ] SCAN-277. **LeadPipelinePage drag-stage updateMut no optimistic onMutate + rollback — card jitters on slow network** — `packages/web/src/pages/leads/LeadPipelinePage.tsx:200`. Fix: onMutate snapshot + optimistic move + rollback in onError.

### Regex DoS / time-zone / log spam (11 findings)
- [ ] SCAN-278. **Membership renewal cron console.log inside per-subscription loop — N lines/run/tenant** — `packages/server/src/index.ts:2041`. Fix: single post-loop `log.info` with count.
- [ ] SCAN-279. **PaymentJanitor sweep console.log inside forEachDb per-tenant callback** — `packages/server/src/index.ts:2085`. Fix: accumulate totals + single summary log.
- [ ] SCAN-280. **Hourly session-cleanup cron console.log per-tenant** — `packages/server/src/index.ts:2212`. Fix: buffer + one summary log.
- [ ] SCAN-281. **Appointment-reminder cron console.log per-appointment — burst spam when batch due** — `packages/server/src/index.ts:2592`. Fix: count + single summary.
- [ ] SCAN-282. **Scheduled-SMS cron console.log per-message dispatched** — `packages/server/src/index.ts:2664`. Fix: aggregate sent/failed counts; log once.
- [ ] SCAN-283. **Invoice-reminder cron console.log per-invoice** — `packages/server/src/index.ts:2941`. Fix: counter + single log.info.
- [ ] SCAN-284. **Membership renewal newEnd derived from `new Date()` not stored `current_period_end` — drifts seconds per renewal; inconsistent with `datetime('now')` trigger** — `packages/server/src/index.ts:2028`. Fix: anchor to `new Date(sub.current_period_end)` or use SQL `datetime('now','+1 month')`.
- [ ] SCAN-285. **EmployeeListPage getWeekRange uses `.setHours(0,0,0,0)` — DST spring-forward off by 1h** — `packages/web/src/pages/employees/EmployeeListPage.tsx:83`. Fix: `toLocaleDateString('en-CA')` or UTC-anchored.
- [ ] SCAN-286. **CalendarPage startOfWeek uses `.setHours(0,0,0,0)` — same DST issue** — `packages/web/src/pages/leads/CalendarPage.tsx:71`. Fix: UTC-anchored YYYY-MM-DD.
- [ ] SCAN-287. **metricsCollector `toISOString().replace('T',' ')` then rollup uses `SUBSTR(timestamp,1,13)` — non-UTC tz diverges** — `packages/server/src/services/metricsCollector.ts:87,118`. Fix: consistent ISO-8601 UTC + align SQL cutoff.
- [ ] SCAN-288. **catalog.routes.ts `/\s+/` split on device query param matches CR/LF/FF/VT — alters SQL LIKE chain with multi-line input** — `packages/server/src/routes/catalog.routes.ts:497`. Fix: `/[ \t]+/` + reject vertical whitespace.

### Form validation / focus mgmt / a11y (11 findings)
- [ ] SCAN-289. **SignupPage email regex too loose (`/\S+@\S+\.\S+/` accepts a@b.c)** — `packages/web/src/pages/signup/SignupPage.tsx:189`. Fix: `/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/` matching CustomerCreatePage.
- [ ] SCAN-290. **TicketCreatePage security_code input lacks autocomplete="off" — browser offers to save device PIN** — `packages/web/src/pages/tickets/TicketCreatePage.tsx:538-545`. Fix: pass autoComplete="off" through TextInput.
- [ ] SCAN-291. **TicketCreatePage repair price number input lacks min="0"** — `packages/web/src/pages/tickets/TicketCreatePage.tsx:538-545`. Fix: min="0" attribute.
- [ ] SCAN-292. **DepositCollectModal amount input lacks min="0.01" — native spinner allows negative** — `packages/web/src/pages/billing/DepositCollectModal.tsx:78-84`. Fix: min="0.01".
- [ ] SCAN-293. **PaymentLinksPage amount input lacks min — negative payment link can be submitted** — `packages/web/src/pages/billing/PaymentLinksPage.tsx:187-194`. Fix: min="0.01".
- [ ] SCAN-294. **CustomerCreatePage first_name input lacks maxLength — silent DB truncation risk** — `packages/web/src/pages/customers/CustomerCreatePage.tsx:213-221`. Fix: maxLength={100} matching DB column.
- [ ] SCAN-295. **CustomerCreatePage: focus not moved to first invalid field after validation fails** — `packages/web/src/pages/customers/CustomerCreatePage.tsx:140-154`. Fix: ref + .focus() on first error field.
- [ ] SCAN-296. **CampaignsPage create form: name input no maxLength** — `packages/web/src/pages/marketing/CampaignsPage.tsx:339-344`. Fix: maxLength={200}.
- [ ] SCAN-297. **CampaignsPage template_body textarea no maxLength — unlimited SMS body** — `packages/web/src/pages/marketing/CampaignsPage.tsx:405-411`. Fix: maxLength={1600}.
- [ ] SCAN-298. **PortalRegister PIN input paste bypasses digit-only stripping with confusing empty-field state** — `packages/web/src/pages/portal/PortalRegister.tsx:185-193`. Fix: onPaste handler that sanitises then setPin with feedback.
- [ ] SCAN-299. **InventoryCreatePage retail_price accepts 3+ decimal places via direct typing — parseFloat stores extras to DB** — `packages/web/src/pages/inventory/InventoryCreatePage.tsx:143`. Fix: `^\d+(\.\d{1,2})?$` regex in handleSubmit or step-forced input.

### PWA / manifest / shared types / robots (8 findings)
- [ ] SCAN-300. **manifest.json name/short_name/description/colors hard-coded single-tenant — every tenant gets wrong branding in PWA install** — `packages/web/public/manifest.json:2`. Fix: dynamic `/api/manifest.json` from store settings or per-tenant Vite build.
- [ ] SCAN-301. **manifest.json start_url="/" + no `scope` — installed PWA covers /super-admin routes** — `packages/web/public/manifest.json:5`. Fix: `scope:"/app/"` + `start_url:"/app/"`.
- [ ] SCAN-302. **index.html SW-cleanup script unregisters + deletes all caches, but /public/sw.js still served — perpetual install/unregister loop** — `packages/web/index.html:43`. Fix: remove sw.js + script after all clients migrated, or stop serving sw.js.
- [ ] SCAN-303. **cleanup sw.js not versioned + no `updateViaCache` — future real SW re-enablement will stale-pin** — `packages/web/public/sw.js:1`. Fix: any replacement must use `updateViaCache:'none'` + versioned cache name.
- [ ] SCAN-304. **shared Customer interface missing is_active/last_ticket_date/health_score — fields returned by server, untyped at web consumer** — `packages/shared/src/types/customer.ts:1`. Fix: add optional fields matching server response.
- [ ] SCAN-305. **LEAD_STATUSES duplicated in LeadListPage instead of import from `@bizarre-crm/shared`** — `packages/web/src/pages/leads/LeadListPage.tsx:16`. Fix: import + derive display locally.
- [ ] SCAN-306. **ESTIMATE_STATUSES duplicated in EstimateListPage — same drift risk** — `packages/web/src/pages/estimates/EstimateListPage.tsx:15`. Fix: import from shared.
- [ ] SCAN-307. **[SEC] no robots.txt — portal login + super-admin + app routes indexed by crawlers, leaks tenant slugs** — `packages/web/public/` missing file. Fix: add `robots.txt` with `User-agent: * Disallow: /`.

### Inventory serials/kits/stocktake + feature flags + SVG (11 findings)
- [ ] SCAN-308. **inventoryEnrich auto-reorder `is_enabled` defaults to 1 when field omitted — silent auto-enable** — `packages/server/src/routes/inventoryEnrich.routes.ts:418`. Fix: `req.body?.is_enabled === true ? 1 : 0` or require explicit.
- [ ] SCAN-309. **migration 091 serials UNIQUE is (inventory_item_id, serial_number) — duplicate serial across items silently accepted** — `packages/server/src/db/migrations/091_inventory_enrichment.sql:91`. Fix: add global UNIQUE(serial_number) or cross-item lookup at route.
- [ ] SCAN-310. **inventory kit item quantity silently coerces 0/negative → 1 via `Math.max(1, parseInt||1)`** — `packages/server/src/routes/inventory.routes.ts:718-719`. Fix: validateIntegerQuantity reject 0/neg.
- [ ] SCAN-311. **inventory kit deletion uses two separate adb.run() outside transaction — partial failure orphans kit row** — `packages/server/src/routes/inventory.routes.ts:786-787`. Fix: `adb.transaction([...])` wrap.
- [ ] SCAN-312. **stocktake counted_qty capped at 100k via validateIntegerQuantity — blocks legitimate large warehouse counts** — `packages/server/src/routes/stocktake.routes.ts:190`. Fix: raise/remove cap for stocktake path or document.
- [ ] SCAN-313. **supplier-returns quantity accepted beyond in_stock — drives in_stock negative on process** — `packages/server/src/routes/inventoryEnrich.routes.ts:1052-1054`. Fix: guard `in_stock >= quantity` before insert.
- [ ] SCAN-314. **GET /settings/config full table scan every request (hot path for every authed page load)** — `packages/server/src/routes/settings.routes.ts:305-320`. Fix: 5s per-tenant in-process cache invalidated on PUT.
- [ ] SCAN-315. **[SEC] GET /config returns operational integration metadata (terminal name, webhook URLs, 10dlc status) to any authed user — not admin-gated** — `packages/server/src/routes/settings.routes.ts:307`. Fix: admin gate OR non-admin allowlist.
- [ ] SCAN-316. **[SEC] CatalogPage `<img src={item.image_url}>` unsanitised — supplier catalog `javascript:` URL renders** — `packages/web/src/pages/catalog/CatalogPage.tsx:439`. Fix: `isSafeLogoUrl` guard (already exists in PrintPage).
- [ ] SCAN-317. **[SEC] PortalLogin public page `<img src={storeLogo}>` unsanitised — tenant-poisoned logo on unauth page** — `packages/web/src/pages/portal/PortalLogin.tsx:83`. Fix: `isSafeLogoUrl` check before render.
- [ ] SCAN-318. **inventoryEnrich ZPL label `^FD${sku}^FS` without escaping `^`/`~` in SKU — premature format termination** — `packages/server/src/routes/inventoryEnrich.routes.ts:1253-1259`. Fix: `.replace(/[\^~]/g,' ')` on sku (matches displayName path).

## AUDIT CYCLE 3 — 2026-04-23 (parallel discovery wave 7: webhooks + CSP/headers + streaming/backup + tx retry/session + JWT/bounce)

### Webhooks inbound + outbound (8 findings)
- [ ] SCAN-319. **[SEC] outbound webhook accepts plain `http://` scheme — signed payload + HMAC cleartext over network** — `packages/server/src/services/webhooks.ts:149`. Fix: reject http:; require https:.
- [ ] SCAN-320. **[SEC] webhook signing secret stored plaintext in store_config — INSERT OR IGNORE raw; not via setConfigValue** — `packages/server/src/services/webhooks.ts:248`. Fix: route through encryptConfigValue.
- [ ] SCAN-321. **[SEC] `webhook_secret` absent from `ENCRYPTED_CONFIG_KEYS` allowlist** — `packages/server/src/utils/configEncryption.ts:31`. Fix: add key to set.
- [ ] SCAN-322. **[SEC] outbound webhook payload `data` field has no per-event allowlist — raw row may include token/card_token** — `packages/server/src/services/webhooks.ts:462`. Fix: project through explicit safe-field list per `WebhookEvent`.
- [ ] SCAN-323. **Bandwidth inbound webhook falls through with `console.warn` when no auth header — sms.routes accepts 200** — `packages/server/src/providers/sms/bandwidth.ts:117`. Fix: enforce Basic-auth in URL at settings-save validator.
- [ ] SCAN-324. **voice webhook verifyWebhookSignature optional — provider missing method silently unauth** — `packages/server/src/routes/voice.routes.ts:309`. Fix: require method in SmsProvider interface; default-deny.
- [ ] SCAN-325. **Telnyx verify logs missing-rawBody as `console.warn` only — misconfig silently drops all traffic** — `packages/server/src/providers/sms/telnyx.ts:86`. Fix: `logger.error` + startup assertion that rawBody middleware mounted.
- [ ] SCAN-326. **Outbound webhook retry re-uses stale timestamp in signature — dead-letter loops past receiver window** — `packages/server/src/services/webhooks.ts:479,543`. Fix: regenerate timestamp + re-sign on retry; add `X-Retry-Attempt` header.

### CSP / headers / iframe / SRI (10 findings)
- [ ] SCAN-327. **[SEC] CSP `scriptSrcAttr:'self'` allows same-origin inline event handlers — should be `'none'`** — `packages/server/src/index.ts:903`. Fix: `scriptSrcAttr:["'none'"]`.
- [ ] SCAN-328. **[SEC] CSP `imgSrc` includes bare `https:` wildcard — tracking-pixel exfil** — `packages/server/src/index.ts:905`. Fix: explicit CDN allowlist.
- [ ] SCAN-329. **helmet `crossOriginEmbedderPolicy:false` — COEP header entirely omitted + COOP not set** — `packages/server/src/index.ts:914`. Fix: explicit `crossOriginOpenerPolicy:{policy:'same-origin'}` + COEP `unsafe-none` (signalled intent, not omitted).
- [ ] SCAN-330. **hCaptcha script injected dynamically without SRI integrity hash** — `packages/web/src/pages/signup/SignupPage.tsx:170`. Fix: pin SRI hash or self-host proxy.
- [ ] SCAN-331. **`js.hcaptcha.com` absent from server `script-src` allowlist — hCaptcha blocked in browsers honoring CSP** — `packages/server/src/index.ts:902`. Fix: add `https://js.hcaptcha.com`.
- [ ] SCAN-332. **public tracking-widget.html has no CSP meta + no Referrer-Policy + static served — inline `onclick=` × many** — `packages/web/public/tracking-widget.html` (whole file). Fix: CSP meta tag OR serve through Express (helmet applies); convert onclick= to addEventListener.
- [ ] SCAN-333. **tracking-widget.html multiple inline `onclick=` attributes violate `script-src-attr`** — `packages/web/public/tracking-widget.html:239`. Fix: addEventListener in existing IIFE.
- [ ] SCAN-334. **reports `/tax-report.pdf` + `/partner-report.pdf` HTML has inline `onclick="window.print()"` — blocked by admin `script-src-attr:'none'`** — `packages/server/src/routes/reports.routes.ts:2786,2881`. Fix: external handler / `<script>` with addEventListener.
- [ ] SCAN-335. **crm wallet-pass HTML fallback returns text/html with no per-response CSP override** — `packages/server/src/routes/crm.routes.ts:307`. Fix: audit `renderWalletPassHtml` inline scripts; add nonce or endpoint-specific CSP.

### Streaming / backup / export (10 findings)
- [ ] SCAN-336. **dataExport materializes entire table `SELECT *` before streaming — OOM on large tenants** — `packages/server/src/routes/dataExport.routes.ts:287`. Fix: `db.prepare().iterate()` row-by-row.
- [ ] SCAN-337. **dataExport starts writing bytes without `res.on('close')` abort listener — client-disconnect doesn't stop loop** — `packages/server/src/routes/dataExport.routes.ts:274`. Fix: abort flag + check each table iteration.
- [ ] SCAN-338. **backup download no X-Content-SHA256 integrity header** — `packages/server/src/routes/admin.routes.ts:379`. Fix: compute SHA-256 pre-stream; emit as header.
- [ ] SCAN-339. **backup download no `Accept-Ranges:none` — Range requests bypass audit byte count** — `packages/server/src/routes/admin.routes.ts:378`. Fix: set header reject Range with 416.
- [ ] SCAN-340. **backup encryptFile reads entire plaintext DB into memory — 2× peak heap** — `packages/server/src/services/backup.ts:302`. Fix: stream pipeline (createReadStream → cipher → output).
- [ ] SCAN-341. **customer GDPR export unbounded `SELECT * FROM tickets WHERE customer_id=?` + notes + devices — one allocation** — `packages/server/src/routes/customers.routes.ts:1752,1765`. Fix: hard LIMIT 10k or paginate.
- [ ] SCAN-342. **dataExport stream has no per-chunk auth re-verify — JWT expiry mid-stream keeps delivering data** — `packages/server/src/routes/dataExport.routes.ts:214`. Fix: max stream duration OR re-check token per table iteration.
- [ ] SCAN-343. **tenantExport `GET /download/:signedToken` unauth public — no rate-limit on token lookup (timing oracle)** — `packages/server/src/routes/tenantExport.routes.ts:159`. Fix: per-IP rate-limit 10 req/min.
- [ ] SCAN-344. **dataExport audit log fires after `res.end()` outside try/catch — catch branch still runs audit with under-reported rowCounts** — `packages/server/src/routes/dataExport.routes.ts:337`. Fix: move into `finally`.
- [ ] SCAN-345. **repairDeskImport no back-pressure — fetchAllPages allocates all 500k records before per-page tx commits** — `packages/server/src/services/repairDeskImport.ts:647,800,1194`. Fix: max in-flight page count + flush/GC per page.

### DB tx retry / session / step-up (8 findings)
- [ ] SCAN-346. **sync better-sqlite3 `req.db` on event-loop thread — busy_timeout 5s blocks all requests under contention** — `packages/server/src/db/connection.ts:1`. Fix: migrate rate-limiter + audit writes to asyncDb worker pool.
- [ ] SCAN-347. **sessions table has no `ip_address` column — no source-IP audit per session; anomaly detection impossible** — `packages/server/src/routes/auth.routes.ts:258,331`. Fix: migration adds ip_address TEXT + populate from req.ip in pruneAndInsertSession.
- [ ] SCAN-348. **logout deletes session row + clears cookie but refresh JWT body-path (mobile) still valid vs sessionId check — mitigation fragile if issueTokens changes** — `packages/server/src/routes/auth.routes.ts:1309,1142`. Fix: also revoke refresh token DB-side (blocklist jti) independent of sessions.
- [ ] SCAN-349. **no `/auth/logout-all` endpoint — user can't revoke all sessions after compromise (except via password change)** — `packages/server/src/routes/auth.routes.ts:1309`. Fix: add `POST /auth/logout-all` + `DELETE FROM sessions WHERE user_id=?` + admin variant.
- [ ] SCAN-350. **step-up TOTP not session-bound single-use — code replayable within same 30s window to different protected endpoint in same session** — `packages/server/src/middleware/stepUpTotp.ts:140`. Fix: record consumed code keyed `(session_id, code, totp_window_epoch)` in short-lived set.
- [ ] SCAN-351. **credential stuffing gap: per-username limit only fires when same username retried — spray across usernames each hitting <5 tries evades account lockout** — `packages/server/src/routes/auth.routes.ts:607,422`. Fix: cross-IP per-account failure counter keyed solely on tenantSlug:username.
- [ ] SCAN-352. **db-worker no exp-backoff retry on SQLITE_BUSY beyond 5s busy_timeout — 8 workers writing rate_limits stall entire pool + return 503** — `packages/server/src/db/db-worker.mjs:39`. Fix: 3-attempt exp backoff (50/100/200ms jitter) wrapping SQLITE_BUSY in worker execute().
- [ ] SCAN-353. **[SEC] sync main-thread busy_timeout 5s blocks Node.js event loop on contention (synchronous audit + rate-limiter writes)** — `packages/server/src/db/tenant-pool.ts:51`. Fix: move all sync req.db writes to asyncDb worker path.

### JWT claims / email suppression / portal auth (8 findings)
- [ ] SCAN-354. **automations `executeSendEmail` doesn't gate on `customers.email_opt_in` — unsubscribed customers still receive automation mail** — `packages/server/src/services/automations.ts:255-263`. Fix: gate on `email_opt_in !== 0`.
- [ ] SCAN-355. **notifications auto-email dispatch doesn't check `email_opt_in` (SMS path does check `sms_opt_in`)** — `packages/server/src/services/notifications.ts:488`. Fix: query + gate before sendEmail.
- [ ] SCAN-356. **dunningScheduler sends to customer.email with no email_opt_in check — unsubscribes keep receiving dunning** — `packages/server/src/services/dunningScheduler.ts:673`. Fix: `AND c.email_opt_in != 0` in customer query or route gate.
- [ ] SCAN-357. **`sendEmail` has no suppression-list lookup + no `email_suppressions` table exists — hard-bounces resent forever, IP/domain reputation risk** — `packages/server/src/services/email.ts:138`. Fix: create table (address, reason, ts); query in sendEmail; return false on match.
- [ ] SCAN-358. **no SES/SendGrid bounce/complaint webhook endpoint registered — bounces + spam complaints never received** — repo-wide. Fix: `/api/v1/email/webhook` with shared-secret/SNS-sig verify; write to email_suppressions.
- [ ] SCAN-359. **[SEC] device-trust token signed with same `audience: 'bizarre-crm-api'` as access token — type-check guard is only line of defense** — `packages/server/src/routes/auth.routes.ts:982-985`. Fix: sign with `audience:'device-trust'` + verify explicitly.
- [ ] SCAN-360. **access token payload doesn't set explicit `type:'access'` — middleware accepts any token missing `type` field** — `packages/server/src/routes/auth.routes.ts:346-349`. Fix: add `type:'access'` at sign; middleware strict-positive assert.
- [ ] SCAN-361. **[SEC] portal session token returned in JSON body only (no httpOnly cookie) — stored in JS-accessible storage, XSS-exfiltrable** — `packages/server/src/routes/portal.routes.ts:105-107,490,628`. Fix: issue as httpOnly + SameSite=Strict cookie (mirror admin refreshToken).

## AUDIT CYCLE 3 — 2026-04-23 (parallel discovery wave 8: reports CSV/PDF + admin + utils 2nd pass + a11y + dead code)

### Reports CSV/PDF / export / formula injection (7 findings)
- [ ] SCAN-362. **[SEC] toCsv formula injection — values starting with `=`/`+`/`-`/`@`/`\t`/`\r` emitted raw** — `packages/server/src/routes/reports.routes.ts:1683`. Fix: prepend `'` for formula-trigger chars before comma/quote check.
- [ ] SCAN-363. **[SEC] team payroll CSV `username` field unquoted + unsanitized — only name fields wrapped via sanitize()** — `packages/server/src/routes/team.routes.ts:885`. Fix: wrap username in sanitize() + formula-escape.
- [ ] SCAN-364. **[SEC] payroll sanitize() strips quotes/CR/LF but does NOT neutralize formula-trigger start chars** — `packages/server/src/routes/team.routes.ts:877`. Fix: after replace, if trimmed starts with `=|+|-|@|\t|\r` prepend `'`.
- [ ] SCAN-365. **CSV Content-Disposition filename uses raw `reportType` + `from`/`to` — CRLF injection if double-decode bypass** — `packages/server/src/routes/reports.routes.ts:1799`. Fix: strip `\r\n` + encodeURIComponent; RFC 5987 `filename*=UTF-8''...`.
- [ ] SCAN-366. **tax report totals (totalTax/totalRevenue) computed client-side only — MitM/extension row-mutation silently drifts tax-remittance summary** — `packages/web/src/pages/reports/ReportsPage.tsx:807`. Fix: server returns `total_tax_collected` + `total_taxable_revenue` aggregates; render those.
- [ ] SCAN-367. **CSV Content-Type missing charset — UTF-8 BOM mismatch renders garbled in proxies/mail clients** — `packages/server/src/routes/reports.routes.ts:1798`. Fix: `text/csv; charset=utf-8`.
- [ ] SCAN-368. **/tax-report.pdf + /partner-report.pdf HTML fallback no Content-Disposition + no `X-Content-Type-Options:nosniff` — phishing-shareable URL** — `packages/server/src/routes/reports.routes.ts:2789,2884`. Fix: add inline disposition + nosniff, or auth-gate.

### Admin console / impersonate / 2FA / device-trust (6 findings)
- [ ] SCAN-369. **[SEC P0] `GET /admin` backup panel served without `localhostOnly` — remote brute-force exposed** — `packages/server/src/index.ts:1637`. Fix: wrap with `localhostOnly` (pattern matches `/super-admin` at line 1413).
- [ ] SCAN-370. **[SEC P0] super-admin `POST /tenants/:slug/impersonate` missing `requireStepUpTotpSuperAdmin` — stolen 30-min JWT impersonates any tenant without 2nd factor** — `packages/server/src/routes/super-admin.routes.ts:2074`. Fix: add guard matching sibling destructive endpoints.
- [ ] SCAN-371. **ImpersonationBanner exit flow calls clearImpersonationSession + logout() — wipes wrong auth; super-admin token remains but UI lost** — `packages/web/src/components/ImpersonationBanner.tsx:63`. Fix: navigate to /super-admin without logout(); keep SA session intact.
- [ ] SCAN-372. **[SEC] impersonation audit rows attribute to victim user not operator — superAdminId in JWT but never propagated to audit()** — `packages/server/src/routes/super-admin.routes.ts:2113`. Fix: pass impersonated+superAdminId through req.user to audit utility.
- [ ] SCAN-373. **2fa-setup pending enrolment discarded on tab close — user re-enters unverified state indefinitely (no DB pending flag)** — `packages/web/src/pages/auth/LoginPage.tsx:589` + `super-admin.routes.ts:343`. Fix: server-side `pending_totp_since` column blocking login until confirmed or timeout.
- [ ] SCAN-374. **deviceTrust cookie `Secure` gated on `nodeEnv==='production'` — staging/dev-over-HTTPS issues cookie without Secure; 90-day 2FA bypass on plain HTTP if browser permits** — `packages/server/src/routes/auth.routes.ts:989`. Fix: Secure:true whenever `useHttps`, not only in production.

### Server utils 2nd pass / cross-file patterns (12 findings)
- [ ] SCAN-375. **N+1 catalog import: outer for-of up to 5k items × inner for-of compat devices — up to 50k+ sequential DB round-trips** — `packages/server/src/routes/catalog.routes.ts:316,379`. Fix: batch `WHERE source=? AND external_id IN (...)` + bulk insert in tx.
- [ ] SCAN-376. **N+1 campaigns send: for-of over recipients × INSERT campaign_sends per row (×6 variants for SMS/email)** — `packages/server/src/routes/campaigns.routes.ts:216,233,246,253,262,278,301,308,323`. Fix: accumulate + single `adb.transaction([])` bulk INSERT.
- [ ] SCAN-377. **auth JSON.parse(currentBackupCodes) no try/catch — corrupt row → unhandledRejection → process.exit(1)** — `packages/server/src/routes/auth.routes.ts:1049`. Fix: try/catch + 500 or asyncHandler wrap.
- [ ] SCAN-378. **idempotency middleware JSON.parse(existing.response_body) no try/catch — truncated body crashes pipeline** — `packages/server/src/middleware/idempotency.ts:172`. Fix: try/catch + fall back to stored status + empty body.
- [ ] SCAN-379. **invoices.routes bare setInterval not registered with shutdown/trackInterval — holds event loop open on SIGTERM (pattern spans 8 files: signup×3, import, management, super-admin, tenantTermination)** — `packages/server/src/routes/invoices.routes.ts:474`. Fix: store handle + register via trackInterval/clearInterval in shutdown hook.
- [ ] SCAN-380. **employees autoClockout setTimeout fire-and-forget — 5min callback may run post-shutdown on torn-down pool** — `packages/server/src/routes/employees.routes.ts:624`. Fix: store handle + clearTimeout in shutdown.
- [ ] SCAN-381. **settings PUT /config + PUT /store for-of with await adb.run per key — one DB write per body key serially** — `packages/server/src/routes/settings.routes.ts:424,483`. Fix: accumulate + `adb.transaction([])` batch.
- [ ] SCAN-382. **auth middleware `.catch(() => {})` swallows session last_active UPDATE failure — persistent DB error silently leaves stale timestamps** — `packages/server/src/middleware/auth.ts:154`. Fix: `.catch((e) => logger.warn('session touch failed', {error: e.message}))`.
- [ ] SCAN-383. **auth JSON.parse(user.permissions) no try/catch × 3 sites — corrupt row throws sync during login → unhandled → restart** — `packages/server/src/routes/auth.routes.ts:399,1284,1439`. Fix: try/catch + null default.
- [ ] SCAN-384. **tickets setTimeout async fire-and-forget captures db + req.tenantSlug — runs against closed DB on shutdown** — `packages/server/src/routes/tickets.routes.ts:1989`. Fix: store handle + register shutdown clear + guard callback.
- [ ] SCAN-385. **catalog `req.body.source as CatalogSource` no typeof guard — non-string body silently passes (pattern spans 7+ sites: portal/pos/tracking/voice)** — `packages/server/src/routes/catalog.routes.ts:224,580`. Fix: typeof-string guard before enum check.
- [ ] SCAN-386. **settings credentials `as Record<string,string>` — non-object body leaks branch via error message (aids provider-type enum)** — `packages/server/src/routes/settings.routes.ts:1556`. Fix: `typeof credentials === 'object' && !Array.isArray` guard + AppError 400.

### Web a11y deep sweep (11 findings)
- [ ] SCAN-387. **AppShell missing skip-link before `<main>` landmark — keyboard users tab through entire nav on every page** — `packages/web/src/components/layout/AppShell.tsx:94,149`. Fix: add `<a href="#main-content">` + `id="main-content"`.
- [ ] SCAN-388. **No `aria-live` region for react-hot-toast notifications — screen readers never announce toasts** — `packages/web/src/components/layout/AppShell.tsx:107`. Fix: aria-live polite container + Toaster config.
- [ ] SCAN-389. **Loading spinners (PageLoader/LoadingScreen/Header) lack `role="status"` + `aria-live` + `aria-label`** — `packages/web/src/components/layout/AppShell.tsx:108` + `App.tsx:110,176` + `Header.tsx:328`. Fix: add role + aria-label.
- [ ] SCAN-390. **KanbanBoard drag-and-drop no keyboard alternative (no onKeyDown/role=button/aria-grabbed)** — `packages/web/src/pages/tickets/KanbanBoard.tsx:82`. Fix: @dnd-kit/core keyboard sensors or Enter/Space column-picker.
- [ ] SCAN-391. **KanbanBoard status dot is color-only indicator — no sr-only text for colorblind users** — `packages/web/src/pages/tickets/KanbanBoard.tsx:294`. Fix: `<span className="sr-only">{status.name}</span>` or title.
- [ ] SCAN-392. **DataTable `<table>` no caption or aria-label — all tables unlabelled for AT** — `packages/web/src/components/shared/DataTable.tsx:152`. Fix: optional caption prop + sr-only caption.
- [ ] SCAN-393. **InstallmentPlanWizard schedule table no caption/aria-label** — `packages/web/src/components/billing/InstallmentPlanWizard.tsx:141`. Fix: sr-only caption.
- [ ] SCAN-394. **BusyHoursHeatmap chart no text fallback + only mouse tooltip — inaccessible without pointer** — `packages/web/src/components/reports/BusyHoursHeatmap.tsx:50`. Fix: sr-only `<table>` inside `<details><summary>`.
- [ ] SCAN-395. **KeyboardShortcutsPanel modal missing role=dialog + aria-modal + aria-labelledby** — `packages/web/src/components/shared/KeyboardShortcutsPanel.tsx:104`. Fix: dialog ARIA.
- [ ] SCAN-396. **LeadDetailPage lost-reason radio group lacks `<fieldset>` + `<legend>`** — `packages/web/src/pages/leads/LeadDetailPage.tsx:103`. Fix: wrap in fieldset with sr-only legend.
- [ ] SCAN-397. **Skeleton animate-pulse no `prefers-reduced-motion` guard + no aria-busy/role=status — vestibular-disorder users get no opt-out** — `packages/web/src/components/shared/Skeleton.tsx:9`. Fix: `motion-safe:animate-pulse` + aria-busy + role=status.

### Dead code / stale TODOs / duplicates (11 findings)
- [ ] SCAN-398. **auth.routes imports `cleanupExpiredEntries` from rateLimiter but never calls it** — `packages/server/src/routes/auth.routes.ts:13`. Fix: remove unused import; schedule cleanup in index.ts if needed.
- [ ] SCAN-399. **utils/format.ts 4 dead exports (formatDate/formatDateTime/formatCurrency/getStoreLocale); only generateOrderId imported** — `packages/server/src/utils/format.ts:17`. Fix: remove exports or delete; scheduledReports imports from here instead of duplicating.
- [ ] SCAN-400. **scheduledReports duplicates formatCurrency (missing NaN/invalid-currency guards the canonical has)** — `packages/server/src/services/scheduledReports.ts:161`. Fix: delete local copy + import from utils/format.
- [ ] SCAN-401. **utils/constants.ts entirely unused — every export redefined inline in routes or duplicated in pagination.ts** — `packages/server/src/utils/constants.ts:7`. Fix: delete or consolidate + wire route imports.
- [ ] SCAN-402. **commissions.ts `calcCommissionCents` exported but only called internally** — `packages/server/src/utils/commissions.ts:74`. Fix: remove export keyword (internal helper).
- [ ] SCAN-403. **rateLimiter.recordWindowFailure marked `@deprecated` but still called in 6 route files (auth×5, billing, invoices, giftCards, estimates, admin)** — `packages/server/src/utils/rateLimiter.ts:43`. Fix: replace with `recordWindowAttempt` (alias at line 76); drop deprecated export.
- [ ] SCAN-404. **RepairPricingTab 46-line commented-out stream-of-thought block (lines 425-470) above real impl** — `packages/web/src/pages/settings/RepairPricingTab.tsx:425`. Fix: delete comment block.
- [ ] SCAN-405. **settingsDeadToggles 4 dead exports (getAllDeadToggles/findMetadataOnlyDeadKeys/findOrphanDeadKeys/setHideDeadToggles)** — `packages/web/src/pages/settings/settingsDeadToggles.ts:132`. Fix: remove export or wire dev-tools panel.
- [ ] SCAN-406. **[SEC] fileValidation TODO ClamAV stub returns `{clean:true, scanner:'stub-clamav-pending'}` even when `CLAMAV_HOST` env set — every upload silently passes** — `packages/server/src/utils/fileValidation.ts:210-226`. Fix: implement clamscan OR fatal startup error when CLAMAV_HOST set but unimplemented.
- [ ] SCAN-407. **reports.routes TODO: startReportEmailer implemented but never called from index.ts — daily summary-email cron wired to nothing** — `packages/server/src/routes/reports.routes.ts:1850`. Fix: import + invoke in index.ts post-listen + delete TODO.
- [ ] SCAN-408. **CustomerPayPage `console.debug` guarded by `import.meta.env?.DEV` optional chain may defeat Vite tree-shake — call can ship in prod bundle** — `packages/web/src/pages/billing/CustomerPayPage.tsx:65`. Fix: use `import.meta.env.DEV` (no optional chain) so static analysis strips reliably.

## AUDIT CYCLE 3 — 2026-04-23 (parallel discovery wave 9: Docker hardening + compression leaks + socket/DB leaks + signup/WS/audit cluster + stubs/dep-confusion)

### Docker + Node pins + CDN SRI (11 findings)
- [ ] SCAN-409. **Dockerfile missing HEALTHCHECK — only compose defines it; standalone runs (k8s/ECS) have no liveness probe** — `packages/server/Dockerfile:1`. Fix: add `HEALTHCHECK --interval=30s --timeout=10s ...` before final CMD.
- [ ] SCAN-410. **Dockerfile no `tini` / `--init` — Node as PID 1 doesn't reap zombies + signal forwarding broken** — `packages/server/Dockerfile:93`. Fix: `apk add tini` + `ENTRYPOINT ["/sbin/tini","--"]`.
- [ ] SCAN-411. **[SEC] No `.dockerignore` at repo root — full context (`.env`, `.git`, certs/, node_modules) sent to daemon, risks embedding secrets in layers** — repo root. Fix: create .dockerignore with `.env*`, `.git`, node_modules, certs/*.key, data, uploads.
- [ ] SCAN-412. **[SEC] Dockerfile copies `packages/server/certs/` including `server.key` into image — private key baked into layer** — `packages/server/Dockerfile:71`. Fix: mount certs as runtime secret/volume OR .dockerignore `*.key`.
- [ ] SCAN-413. **docker-compose.yml service missing `read_only:true` + `security_opt:["no-new-privileges:true"]` + seccomp** — `docker-compose.yml:1`. Fix: add all three + tmpfs mounts for /tmp /run.
- [ ] SCAN-414. **Google Fonts stylesheet loaded without SRI integrity — CDN-compromise → CSS injection/data exfil** — `packages/web/index.html:18`. Fix: self-host fonts OR pin SRI hash + crossorigin=anonymous.
- [ ] SCAN-415. **CSP lacks `worker-src 'none'` + `child-src 'none'` — Cloudflare Insights script could register SW or spawn frames** — `packages/server/src/index.ts:904`. Fix: add both directives.
- [ ] SCAN-416. **packages/shared engines.node `>=22.0.0` no upper bound — diverges from root `<25` + allows 22.0–22.10 (unfixed CVEs)** — `packages/shared/package.json:17`. Fix: align to `">=22.11.0 <25"`.
- [ ] SCAN-417. **packages/web engines.node misalignment (22.0.0 vs 22.11.0 root)** — `packages/web/package.json:8`. Fix: `">=22.11.0 <25"`.
- [ ] SCAN-418. **packages/management engines.node misalignment** — `packages/management/package.json:10`. Fix: `">=22.11.0 <25"`.
- [ ] SCAN-419. **Dockerfile floating tag `node:22-alpine` — non-reproducible, silent patch rolls** — `packages/server/Dockerfile:46`. Fix: pin exact version or digest (e.g., `node:22.11.0-alpine3.21`).

### Compression leaks / prototype pollution / input bloat (7 findings)
- [ ] SCAN-420. **[SEC] global `compression()` middleware applies gzip to `/auth/*` responses — BREACH-class secret recovery via response-length oracle** — `packages/server/src/index.ts:852`. Fix: filter exclude `/auth/` OR `Content-Encoding: identity` + `Cache-Control: no-store` on auth responses.
- [ ] SCAN-421. **[SEC] /auth/login/2fa-setup response (secret + manualEntry + challengeToken + QR) compressed — amplifies BREACH on TOTP seed** — `packages/server/src/routes/auth.routes.ts:856`. Fix: exclude route from compression + `Cache-Control: no-store`.
- [ ] SCAN-422. **[SEC] /auth/login/2fa-verify response with backupCodes compressed — one-time codes leak via response-size oracle** — `packages/server/src/routes/auth.routes.ts:999`. Fix: `Content-Encoding: identity` before res.json.
- [ ] SCAN-423. **settings PUT /store no per-value length cap (bulk PATCH does) — admin writes multi-MB `receipt_header` blob** — `packages/server/src/routes/settings.routes.ts:483`. Fix: `if (strVal.length > 65_536) continue;` matching bulk path.
- [ ] SCAN-424. **settings PUT /store allowlist array (O(n) includes) + `tcx_password` may be stored cleartext if not in ENCRYPTED_CONFIG_KEYS** — `packages/server/src/routes/settings.routes.ts:483`. Fix: Set for allowlist + verify tcx_password in encryption set.
- [ ] SCAN-425. **inbox PATCH /config accepts `Record<string, unknown>` + `String(value)` without typeof guard — proto-pollution adjacent footgun** — `packages/server/src/routes/inbox.routes.ts:948`. Fix: guard typeof string|number|boolean only.
- [ ] SCAN-426. **[SEC] /auth/refresh response (`accessToken, user`) compressed — HTTP/2 chosen-plaintext attacker distinguishes token prefix bytes** — `packages/server/src/routes/auth.routes.ts:1293`. Fix: exclude from compression OR `Cache-Control: no-store` before res.json.

### Socket/stream cleanup + DB pool + WAL + health (12 findings)
- [ ] SCAN-427. **httpRedirectServer no keepAliveTimeout/headersTimeout/requestTimeout — slow-loris exposed** — `packages/server/src/index.ts:638`. Fix: set short values (10s/15s) since it only 301s.
- [ ] SCAN-428. **no scheduled `PRAGMA wal_checkpoint(PASSIVE|TRUNCATE)` cron — low-write tenants bloat .db-wal indefinitely** — `packages/server/src/db/db-worker.mjs:42` + `connection.ts:22`. Fix: hourly `trackInterval` across master + forEachDb tenant.
- [ ] SCAN-429. **no scheduled `PRAGMA optimize` / ANALYZE — query planner stats go stale as data grows** — `packages/server/src/db/connection.ts:22`. Fix: daily `trackInterval` + forEachDb.
- [ ] SCAN-430. **db-worker.mjs prepares statements per-task — no statement cache, repeated compile** — `packages/server/src/db/db-worker.mjs:107`. Fix: per-connection `Map<sql, Statement>` closure cache.
- [ ] SCAN-431. **tenant-pool health-check creates new `SELECT 1` prepared stmt every 30s — GC churn** — `packages/server/src/db/tenant-pool.ts:127`. Fix: prepare once per PoolEntry at open.
- [ ] SCAN-432. **voice recording `fs.createReadStream().pipe(res)` no error handler + no `req.on('close', src.destroy)` — FD leak on error/abort** — `packages/server/src/routes/voice.routes.ts:253`. Fix: stream.on('error',...) + req.on('close',...).
- [ ] SCAN-433. **tenantExport (authed) pipe `stream.pipe(res)` no req.on('close') abort guard** — `packages/server/src/routes/tenantExport.routes.ts:220`. Fix: add req.on('close',()=>stream.destroy()).
- [ ] SCAN-434. **tenantExport public download pipe no req.on('close') abort guard** — `packages/server/src/routes/tenantExport.routes.ts:333`. Fix: same.
- [ ] SCAN-435. **WS isTenantOriginAllowed calls getTenantDb but never releaseTenantDb — permanent refcount inflation prevents LRU eviction** — `packages/server/src/ws/server.ts:225`. Fix: finally release.
- [ ] SCAN-436. **db-worker 4 case branches all re-prepare — no (dbPath, sql) 2-level cache** — `packages/server/src/db/db-worker.mjs:107-116`. Fix: nested Map cache.
- [ ] SCAN-437. **tenant-pool MAX_POOL_SIZE flat cap, no idle-timeout eviction — stale entries hold WAL + 16MiB page cache per tenant** — `packages/server/src/db/tenant-pool.ts:19`. Fix: idle-evict sweep when lastUsed > 30min + refcount==0.
- [ ] SCAN-438. **admin backup download pipe has .on('error') but no req.on('close',stream.destroy) abort guard — FD leak on client cancel** — `packages/server/src/routes/admin.routes.ts:390`. Fix: add req.on('close',...).

### Signup + WS lifecycle + audit retention + cluster (11 findings)
- [ ] SCAN-439. **[SEC] signup counters (signupEmailCounters/slugCheckCounters/pendingSignups) are in-process Maps — multi-worker deploy allows N× quota bypass via worker round-robin** — `packages/server/src/routes/signup.routes.ts:38`. Fix: back all via SQLite `checkWindowRate`/`recordWindowAttempt`.
- [ ] SCAN-440. **signup route pre-flight isSlugAvailable redundant + misleading — provisionTenant already does same check; losing request of concurrent pair still consumes quota/captcha** — `packages/server/src/routes/signup.routes.ts:527`. Fix: remove route-level check + rely on UNIQUE constraint.
- [ ] SCAN-441. **WS heartbeat dead-socket branch deletes from allClients but never removes from `clients` Map + never decrements counters** — `packages/server/src/ws/server.ts:583-591`. Fix: replicate full close-handler teardown in heartbeat.
- [ ] SCAN-442. **WS wsConnsByIp/wsConnsByTenant module-level Maps — per-IP/per-tenant cap multiplies by worker count under clustering** — `packages/server/src/ws/server.ts:138-139`. Fix: DB-backed rate-limiter or document single-process requirement.
- [ ] SCAN-443. **worker pool shutdownWorkerPool calls pool.destroy() without draining — queued tasks dropped silently on SIGTERM** — `packages/server/src/db/worker-pool.ts:161` + `index.ts:3452`. Fix: await queueSize==0 with bounded wait before destroy.
- [ ] SCAN-444. **masterDb module singleton + multi-process each calls setMasterDb → concurrent writes to master DB from N processes → SQLITE_BUSY/LOCKED at load** — `packages/server/src/utils/masterAudit.ts:1`. Fix: document single-process master OR IPC-queue writes.
- [ ] SCAN-445. **audit_logs has only flat idx_audit_logs_created — range queries degrade linearly with 730-day retention** — `packages/server/src/db/migrations/022_audit_logs.sql:9-11`. Fix: composite `(created_at, event)` covering index + expression column for `strftime('%Y-%m', created_at)`.
- [ ] SCAN-446. **deleteTenant no cooldown — admin loop create→delete→re-signup exhausts slug namespace via pending_deletion accumulation** — `packages/server/src/services/tenant-provisioning.ts:470`. Fix: per-tenant 24h rate-limit + cap pending_deletion rows per admin email.
- [ ] SCAN-447. **audit_logs retention sweep keyed on per-tenant timezone hourly tick — fires at 2AM local but may miss if restart lands at 01:59→03:01** — `packages/server/src/index.ts:2250-2252`. Fix: UTC anchor + validate AUDIT_LOG_RETENTION_DAYS at startup.
- [ ] SCAN-448. **[SEC] pendingSignups stores `adminPassword` plaintext in memory up to 1h — heap dump / --inspect exposes** — `packages/server/src/routes/signup.routes.ts:582-592`. Fix: store bcrypt hash in Map; pass to provisionTenant with skip-hash flag.
- [ ] SCAN-449. **RESERVED_SLUGS static compile-time Set — operators can't add reserved words without deploy (e.g. `billing`, `dashboard` claims by attacker before new route ships)** — `packages/server/src/services/tenant-provisioning.ts:17-21`. Fix: load from platform_config table at isSlugAvailable time.

### Virus stub / TODO defaults / dep-confusion (11 findings)
- [ ] SCAN-450. **[SEC] fileValidation second stub path (CLAMAV_HOST set but integration absent) also returns `{clean:true, scanner:'stub-clamav-pending'}` — operator believes ClamAV active but default-pass** — `packages/server/src/utils/fileValidation.ts:231`. Fix: return `{clean:false}` when CLAMAV_HOST set but unwired.
- [ ] SCAN-451. **SMS setSmsProvider exported unguarded — any route/service import can swap provider to ConsoleProvider at runtime, bypassing prod telephony** — `packages/server/src/providers/sms/index.ts:311`. Fix: gate NODE_ENV !== 'production' or move to test-harness module.
- [ ] SCAN-452. **SMS getProviderForDb uses `{strict:false}` — per-tenant misconfig silently falls back to ConsoleProvider (simulated:true)** — `packages/server/src/providers/sms/index.ts:346`. Fix: propagate fail as 503 + tenant-level health flag + ERROR log.
- [ ] SCAN-453. **[SEC] voice hangup endpoint not wired — returns 501 but billing leg stays open (active billing-leak)** — `packages/server/src/routes/voice.routes.ts:275`. Fix: implement per-provider hangup OR block route entirely until wired.
- [ ] SCAN-454. **tickets notes type='email' stored + responds 200 without dispatching email — caller + customer believe comm was sent** — `packages/server/src/routes/tickets.routes.ts:2063`. Fix: wire outbound send OR respond 202 `{emailDispatched:false}`.
- [ ] SCAN-455. **tenant-provisioning archiveDueTenants never called from any cron — cancelled tenant DBs accumulate on disk indefinitely** — `packages/server/src/services/tenant-provisioning.ts:464`. Fix: register hourly trackInterval in index.ts.
- [ ] SCAN-456. **recalculateAllCustomerHealth + birthday/churn dispatch helpers never scheduled — all health-score + lifecycle triggers skipped** — `packages/server/src/index.ts:1571`. Fix: daily cron post-listen.
- [ ] SCAN-457. **[SEC] `.npmrc` has no scope→registry mapping for `@bizarre-crm` — attacker registers scope on public npm → dep-confusion on any install without workspace lockfile** — `.npmrc:1`. Fix: add `@bizarre-crm:registry=https://registry.npmjs.org` (or private registry URL).
- [ ] SCAN-458. **[SEC] tenant-provisioning TEMP-NO-EMAIL-VERIF permanently bypasses email verification + forces password_set=1 + setup_completed='true' on every new tenant — no feature flag** — `packages/server/src/services/tenant-provisioning.ts:332`. Fix: gate behind feature flag / env var.
- [ ] SCAN-459. **[SEC] scanFileForViruses default-pass with no boot warning when CLAMAV_HOST unset — prod deploy silently approves all uploads** — `packages/server/src/utils/fileValidation.ts:204-207`. Fix: boot-time warning when unset + optional REQUIRE_VIRUS_SCAN policy flag to block.
- [ ] SCAN-460. **SMS kill-switch result carries `success:true` for suppression — audit/billing callsites that check result.success increment counters for suppressed sends** — `packages/server/src/providers/sms/index.ts:375-378`. Fix: define `SmsKillSwitchResult` with success:false OR add `suppressed:true` field to type.

## PARITY AUDIT — 2026-04-23 (web feature gaps vs android/ActionPlan.md + ios/ActionPlan.md)

### Android parity gaps (17 findings — features present on Android, missing or weak on web)
- [ ] SCAN-461. **[PARITY] Stocktake endpoint wrappers missing from `packages/web/src/api/endpoints.ts`** — android §60/§6.6. `StocktakePage.tsx` exists but no `stocktakeApi`; page cannot call `GET /stocktake` / `POST /stocktake` / `POST /stocktake/:id/items` through typed client.
- [ ] SCAN-462. **[PARITY] Multi-location management page + location-switcher missing on web** — android §63 / ios §60. No `locationsApi` + no page under `packages/web/src/pages/locations/`. Multi-location shops can't switch active location or manage per-location settings.
- [ ] SCAN-463. **[PARITY] Employee Detail page missing — only `EmployeeListPage.tsx` exists** — android §14.2. `employeeApi.get(id)` wired but no `EmployeeDetailPage.tsx`. Certifications, commission rates, performance history unreachable from web.
- [ ] SCAN-464. **[PARITY] Ticket SLA tracking (badge, breach timer, config) missing from `packages/web/src/pages/tickets/`** — android §4.19/§4.22. Web technicians can't see SLA breach risk Android shows inline.
- [ ] SCAN-465. **[PARITY] Ticket signature/waiver capture missing** — android §4.14. No waiver/signature page in web tickets + no `POST /tickets/:id/signatures` wrapper in endpoints (only `blockchypApi.captureSignature` for POS). Repair authorization signatures cannot be collected from web.
- [ ] SCAN-466. **[PARITY] Field service / dispatch page missing** — android §59 / ios §57. No dispatch page under `packages/web/src/pages/field-service/`, no `dispatchApi`, no consumer for `POST /dispatch/optimize`. Job routing + technician dispatch are mobile-only.
- [ ] SCAN-467. **[PARITY] Owner P&L / financial dashboard page missing** — android §62 / ios §59. Individual report endpoints exist (profitHero, cashTrapped, inventoryTurnover, dayOfWeekProfit) but no unified owner-facing P&L + forecast + budget-vs-actual page.
- [ ] SCAN-468. **[PARITY] Open-shop / daily operational checklist page missing** — android §3.15. No checklist page + no endpoint consumer for morning/closing workflow. Staff opening from desktop has no structured checklist.
- [ ] SCAN-469. **[PARITY] Shared-Device Mode settings missing (PIN-based session swap + auto-logoff policy)** — android §2.14. No settings page in `packages/web/src/pages/settings/`. Shared web terminals can't configure employee-swap behavior.
- [ ] SCAN-470. **[PARITY] Ticket labels CRUD / management page missing** — android §4.21. Labels referenced in ticket detail but no label management in settings + no labels CRUD API in endpoints. Web users can't create/rename/delete triage labels.
- [ ] SCAN-471. **[PARITY] Appointment self-booking admin configuration page missing** — android §58.3. Public booking portal served but admin config UI for booking rules / deposit requirements / service availability absent from settings.
- [ ] SCAN-472. **[PARITY] Notification per-event matrix (per-user, per-event, per-channel toggle) missing** — android §73. `NotificationTemplatesTab.tsx` covers template content only; no matrix UI for ~20 event types × push/in-app/email/SMS.
- [ ] SCAN-473. **[PARITY] Sync conflict-resolution UI missing** — android §20.3. No page under `packages/web/src/pages/` + no consumer for `POST /sync/conflicts/resolve`. Concurrent Android+web edits with conflicts have no web resolution surface.
- [ ] SCAN-474. **[PARITY] Team Chat: `teamChatApi` absent from `packages/web/src/api/endpoints.ts`** — android §14.5 / §47. `TeamChatPage.tsx` exists but no typed client for `GET /team-chat` / `POST /team-chat/messages`; likely hand-rolls axios or non-functional.
- [ ] SCAN-475. **[PARITY] Shift schedule API methods (POST /team/shifts, time-off CRUD, shift-swap) missing from typed client** — android §14.6. `ShiftSchedulePage.tsx` exists but `employeeApi` only exposes list/get/clockIn/clockOut/hours/commissions. Schedule page can't persist shift data through typed API.
- [ ] SCAN-476. **[PARITY] Training mode on web is cosmetic banner only (`TrainingModeBanner.tsx` scoped to unified-pos) — no separate-DB / orange-accent / no-send-guards isolation** — android §53. Web doesn't provide the isolated safe environment Android does.
- [ ] SCAN-477. **[PARITY] Appointments calendar views (Agenda/Day/Week/Month) missing for main appointments domain** — android §10.1. `CalendarPage.tsx` is leads-scoped only; no calendar for `GET /appointments`.

### iOS parity gaps (21 findings — features present on iOS, missing or weak on web)
- [ ] SCAN-478. **[PARITY] Recurring invoices — no endpoints in web `invoiceApi` + no dedicated page** — ios §7.8. Expected `packages/web/src/pages/invoices/RecurringInvoicesPage.tsx`. Subscription-style billing can't be scheduled from web.
- [ ] SCAN-479. **[PARITY] Installment payment plans UI missing — no `InstallmentPlansPage.tsx`** — ios §7.9. `InstallmentPlanWizard.tsx` component exists but no list/management page. High-ticket staged payments can't be tracked.
- [ ] SCAN-480. **[PARITY] Mileage expense entry + endpoint wrapper missing** — ios §11.8. `POST /expenses/mileage` server-side; no web wrapper + no UI. Field techs can't log deductible mileage.
- [ ] SCAN-481. **[PARITY] Per-diem expense claims UI + endpoint wrapper missing** — ios §11.9. `POST /expenses/perdiem` server-side; no web wrapper.
- [ ] SCAN-482. **[PARITY] Expense approve/deny workflow missing from web `expenseApi` + `ExpensesPage.tsx`** — ios §11.4. Only CRUD wired. Managers must use iOS to approve submitted expenses.
- [ ] SCAN-483. **[PARITY] Bench workflow page missing — `benchApi` fully wired (timer/QC/sign-off/defect) but no page renders it** — ios §4 bench subsection. Expected `packages/web/src/pages/bench/BenchPage.tsx`. Bench techs at desktop have no timer/QC surface.
- [ ] SCAN-484. **[PARITY] Timesheet drill-down/edit page missing — only `EmployeeListPage.tsx`** — ios §14.3. Payroll review requires editing clock entries inaccessible on web. Expected `packages/web/src/pages/employees/TimesheetPage.tsx`.
- [ ] SCAN-485. **[PARITY] Time-off request submit/approve/deny flow missing — no endpoints + no page** — ios §14.9. Expected `packages/web/src/pages/employees/TimeOffPage.tsx`.
- [ ] SCAN-486. **[PARITY] Inventory variants (color/size multi-SKU) CRUD + UI missing from `inventoryApi`** — ios §6.10. Multi-SKU products can't be created/managed from web.
- [ ] SCAN-487. **[PARITY] Inventory bundles (kit assembly) CRUD + UI missing** — ios §6.11. `BundleEditorSheet` equivalent absent. Bundled repair kits + accessory packs can't be assembled/priced.
- [ ] SCAN-488. **[PARITY] Recent activity feed page + `activityApi` wrapper missing** — ios §3.6. Real-time shop-wide action stream from `GET /activity` absent. Managers lose visibility off-mobile.
- [ ] SCAN-489. **[PARITY] Credit notes list/detail page missing — `invoiceApi.createCreditNote` wired but no view/apply/void UI** — ios §7.10. Expected `packages/web/src/pages/invoices/CreditNotesPage.tsx`. Accountants can't audit outstanding credits.
- [ ] SCAN-490. **[PARITY] Expense receipt OCR missing — no image-upload trigger on `ExpensesPage.tsx`** — ios §11.3. Desktop users manually type every field iOS auto-extracts via `ReceiptOCRService`.
- [ ] SCAN-491. **[PARITY-WEAK] Dashboard BI widgets exist in `reportApi` (profitHero/busyHoursHeatmap/churn/demandForecast/overstaffing) but `DashboardPage.tsx` may not render them as first-class cards** — ios §3.2. Insights possibly only in /reports drill-through not primary dashboard.
- [ ] SCAN-492. **[PARITY-WEAK] Needs-attention snooze/dismiss actions missing — alert list shown but no per-item snooze/dismiss in endpoints** — ios §3.3. Web users see alerts but can't act without navigating to each record.
- [ ] SCAN-493. **[PARITY-WEAK] QC sign-off button + checklist modal missing from web ticket detail — `benchApi.qc.signOff` only on bench API path** — ios §4.7. Sign-off must be triggered from a bench page that doesn't exist on web.
- [ ] SCAN-494. **[PARITY-WEAK] Estimate e-sign public shareable URL missing — `estimatesApi` has no `signUrl` method** — ios §8. Staff can't copy + send signing link to customers from estimates page.
- [ ] SCAN-495. **[PARITY-WEAK] SMS group messaging + auto-responders missing — `smsApi` covers conversations + templates only, no `createAutoResponder` / `listAutoResponders` / group-thread endpoints** — ios §12. Bulk + auto-response workflows are mobile-only.
- [ ] SCAN-496. **[PARITY-WEAK] Scheduled reports management page missing — `reportApi.scheduledList/scheduleEmail/deleteScheduled` wired but no UI** — ios §15. Users can't manage email report schedules without iOS.
- [ ] SCAN-497. **[PARITY-WEAK] Held carts (POS park/recall) missing — `posApi` has no `holdCart`/`listHeld`/`recallCart` endpoints** — ios §16. Web POS users can't park a transaction for another customer.
- [ ] SCAN-498. **[PARITY-WEAK] Data export scheduling missing — `dataExportApi` has `status`/`downloadAll` only, no `schedule`/`listSchedules`** — ios §19.19. Web users can trigger one-time exports only, not recurring backups.

### BACKEND SHIPPED 2026-04-23 — web UI + mobile consumers still pending
**Wave 1** (commit bd7532c): SCAN-472, SCAN-475, SCAN-478, SCAN-479, SCAN-480, SCAN-481, SCAN-482, SCAN-484, SCAN-485, SCAN-486, SCAN-487, SCAN-488, SCAN-489, SCAN-497. Docs `docs/web-parity-backend-contracts-2026-04-23.md`. Migrations 120-124.
**Wave 2** (commit 407f5c9 + ad8b89b): SCAN-464, SCAN-465, SCAN-468, SCAN-469, SCAN-470, SCAN-490, SCAN-494, SCAN-495, SCAN-498. Docs `docs/web-parity-backend-contracts-wave2-2026-04-23.md`. Migrations 125-129. Crons: data-export schedules hourly + SLA breach every 5 min. Public estimate-sign at `/public/api/v1/estimate-sign/:token` (HMAC single-use).
**Wave 3** (commit 97ea94b5): SCAN-462, SCAN-466, SCAN-467, SCAN-471, SCAN-473. Docs `docs/web-parity-backend-contracts-wave3-2026-04-23.md`. Migrations 130-134. No new crons. Also wired previously-exported helpers: `tryAutoRespond` into `sms.routes.ts` inbound webhook; `computeSlaForTicket` into `tickets.routes.ts` POST/PATCH. Multi-location is CORE ONLY — `location_id` on domain tables deferred to separate epic.
**Wave 4** (commit bba762b7): Migration 135 (tickets.priority column + SLA wiring). Real dataExport generator service extracted — cron now produces actual files, not heartbeat rows. Receipt OCR processor + cron wired (graceful stub when tesseract.js absent). Scan-loop discovered 15 NEW findings in wave-1/2/3 code; 6 P0 security fixes applied in same commit (bulk-SMS role gate, credit-notes role gate, XFF spoof fix, audit metadata sanitize, SQL-interp safe pattern); 9 non-P0 logged as SCAN-499..506.
**Wave 5** (commit 428ff717): Fixed SCAN-499 (recurringInvoices asyncHandler wrap ×7), SCAN-500 (shifts swap-accept atomic tx), SCAN-501 (next_run_at Date.parse validation), SCAN-502-504 (fieldService N+1 batched ×3), SCAN-505 (smsGroups /members rate-limit 10/min/user), SCAN-506 (activity metadata PII allowlist scrub). Multi-location Phase 1: migration 136 adds `tickets.location_id` + backfill + optional filter. Scan-loop appended SCAN-507..520.
**Wave 6** (pending commit): Migration 137 adds hot-path indices (`expense_receipt_uploads(ocr_status, created_at)` + partial `tickets(sla_first_response_due_at)` WHERE NOT NULL) — SCAN-507, SCAN-511. Migration 138 adds ON DELETE SET NULL via table-rebuild for checklist_instances.template_id, field_service_jobs.customer_id, sync_conflicts.resolved_by_user_id, pl_snapshots.generated_by_user_id — SCAN-508/510/517/518. Trigger approach for tickets.sla_policy_id (no full rebuild of huge tickets table) — SCAN-509. Code fixes: receiptOcrCron stale-query parameterized (SCAN-512), dataExportGenerator `.iterate()` (SCAN-519), syncConflicts list omits 32KB blobs (SCAN-520), ownerPl AR LIMIT 10k + truncated flag (SCAN-513), bookingPublic 400 instead of 404 on unknown service (SCAN-515), smsAutoResponderMatcher LIMIT 200 (SCAN-516). Multi-location Phase 2: migration 139 `invoices.location_id` + route wiring.
Do NOT flip `[x]` — web UI consumption still needed to fully close these items.

### Scan-loop findings in wave-1/2/3 code (2026-04-23, wave-4 scan)
- [ ] SCAN-499. **recurringInvoices 7 route handlers use raw `async (req,res)` without `asyncHandler` wrap — unhandled rejections bypass global error handler** — `packages/server/src/routes/recurringInvoices.routes.ts:113`. Fix: wrap each handler with `asyncHandler(...)`.
- [ ] SCAN-500. **shifts swap-accept writes two `adb.run()` calls (UPDATE shift_schedules + UPDATE shift_swap_requests) with no transaction — concurrent accepts double-fire** — `packages/server/src/routes/shiftsSchedule.routes.ts:350`. Fix: `adb.transaction([...])` wrap.
- [ ] SCAN-501. **recurringInvoices `next_run_at` accepted with only `typeof !== 'string'` check — garbage datetime strings persist unchecked** — `packages/server/src/routes/recurringInvoices.routes.ts:311`. Fix: `Date.parse()` guard or zod datetime schema; reject invalid.
- [ ] SCAN-502. **fieldService POST /routes N+1 — `Promise.all(jobIds.map(...))` fires one SELECT per job** — `packages/server/src/routes/fieldService.routes.ts:752`. Fix: single `WHERE id IN (?)` query.
- [ ] SCAN-503. **fieldService PATCH /routes/:id same N+1 per-job SELECT inside map** — `packages/server/src/routes/fieldService.routes.ts:801`. Fix: batch WHERE id IN.
- [ ] SCAN-504. **fieldService POST /routes/optimize same N+1 per-job SELECT inside map** — `packages/server/src/routes/fieldService.routes.ts:893`. Fix: batch WHERE id IN.
- [ ] SCAN-505. **smsGroups POST /:id/members adds up to 500 members per call with no per-user rate-limit (only group-level send limit exists)** — `packages/server/src/routes/smsGroups.routes.ts:293`. Fix: 10 calls/min/user write limit via `checkWindowRate`.
- [ ] SCAN-506. **activity `metadata_json` returned raw to any manager — signer_name/signer_email/timesheet-edit-reason leak PII cross-entity** — `packages/server/src/routes/activity.routes.ts:147`. Fix: scrub PII fields from metadata before return OR scope metadata visibility to the owning-entity manager.

### Scan-loop wave-5 findings in cron/service/new-route code (2026-04-23)
- [ ] SCAN-507. **No index on `expense_receipt_uploads(ocr_status, created_at)` — cron polls every 2 min with full table scan** — `packages/server/src/db/migrations/129_ticket_signatures_receipt_ocr.sql:57`. Fix: `CREATE INDEX idx_expense_receipt_uploads_ocr_status ON expense_receipt_uploads(ocr_status, created_at)`.
- [ ] SCAN-508. **`checklist_instances.template_id` FK no ON DELETE — deleting active template blocks with RESTRICT** — `packages/server/src/db/migrations/128_checklist_sla.sql:29`. Fix: add `ON DELETE SET NULL` (+ nullable) or `CASCADE`.
- [ ] SCAN-509. **`tickets.sla_policy_id` ALTER FK no ON DELETE — policy delete RESTRICTed** — `packages/server/src/db/migrations/128_checklist_sla.sql:76`. Fix: `ON DELETE SET NULL` via table rebuild.
- [ ] SCAN-510. **`field_service_jobs.customer_id` FK no ON DELETE — customer delete silently blocked** — `packages/server/src/db/migrations/130_field_service_dispatch.sql:12`. Fix: `ON DELETE SET NULL`.
- [ ] SCAN-511. **slaBreachCron first-response scan no index on `tickets.sla_first_response_due_at` — full scan every 5 min** — `packages/server/src/services/slaBreachCron.ts:151-165` + `128_checklist_sla.sql:77`. Fix: partial index `CREATE INDEX idx_tickets_sla_first_response_due ON tickets(sla_first_response_due_at) WHERE sla_first_response_due_at IS NOT NULL`.
- [ ] SCAN-512. **receiptOcrCron stale cleanup template-literal interpolates `STALE_PENDING_HOURS` into SQL** — `packages/server/src/services/receiptOcrCron.ts:68-70`. Fix: parameterize via `datetime('now', ? || ' hours')`.
- [ ] SCAN-513. **owner-pl arQuery fetches every outstanding invoice with no LIMIT — heap bloat on large tenants** — `packages/server/src/routes/ownerPl.routes.ts:292-301`. Fix: LIMIT 10000 + `truncated:true` flag OR server-side SQL aging aggregation.
- [ ] SCAN-514. **pl_snapshots `metadata_json` stores `generated_by` user-id that is also in dedicated typed column — duplicate + leaks on export** — `packages/server/src/routes/ownerPl.routes.ts:589`. Fix: drop duplicate from metadata_json OR redact in SELECT projection.
- [ ] SCAN-515. **bookingPublic /availability 404 on unknown service_id enables service-id enumeration** — `packages/server/src/routes/bookingPublic.routes.ts:192`. Fix: return generic 400 "Invalid service" (no info leak).
- [ ] SCAN-516. **smsAutoResponderMatcher loads all active rules with no LIMIT — hundreds-of-rules tenant → heap on every inbound SMS** — `packages/server/src/services/smsAutoResponderMatcher.ts:134-138`. Fix: LIMIT 200 or configurable cap.
- [ ] SCAN-517. **`sync_conflicts.resolved_by_user_id` FK no ON DELETE — user delete RESTRICTed** — `packages/server/src/db/migrations/134_sync_conflicts.sql:53`. Fix: `ON DELETE SET NULL`.
- [ ] SCAN-518. **`pl_snapshots.generated_by_user_id` FK no ON DELETE — admin delete RESTRICTed** — `packages/server/src/db/migrations/131_owner_pl_snapshot.sql:24`. Fix: `ON DELETE SET NULL`.
- [ ] SCAN-519. **dataExportGenerator uses `.all()` not `.iterate()` — full table materialized despite claimed streaming** — `packages/server/src/services/dataExportGenerator.ts:204`. Fix: `db.prepare(...).iterate()` row-by-row.
- [ ] SCAN-520. **syncConflicts GET / list returns `sc.*` including 32KB+ `client_version_json` + `server_version_json` per row — bloated list responses** — `packages/server/src/routes/syncConflicts.routes.ts:307`. Fix: omit version blobs from list; return only in detail endpoint.
- [ ] SCAN-521. **[STALE-DEP add-required] `tesseract.js` not in packages/server/package.json — receipt OCR cron always fails with "OCR processor not installed; configure tesseract.js in package.json"** — `packages/server/package.json`. Real OCR processing blocked until dep added. Fix (needs user approval per no-dep-bump policy): `npm install --workspace=@bizarre-crm/server tesseract.js@^5`. After install, `services/receiptOcr.ts` lazy-imports it; no code change needed.

### Wave-7 scan-loop + helpers audit findings (2026-04-23)
- [x] SCAN-522. **[SEC-CRITICAL FIXED commit pending] activity_events table NEVER populated — zero INSERT sites anywhere except `logActivity` helper which was never called** — `packages/server/src/utils/activityLog.ts` + `packages/server/src/routes/activity.routes.ts`. Fix: logActivity now wired at 6 sites (ticket created/status-changed, invoice created, payment received, customer created, inventory stock-adjusted).
- [x] SCAN-523. ~~customerHealthScore 4 orphan exports~~ FIXED — removed export keyword on internal helpers.
- [x] SCAN-524. ~~recordCustomerInteraction orphan~~ FIXED — wired into invoices.routes.ts payment handler as fire-and-forget.
- [x] SCAN-525. ~~sweepClosedTicketPhotos orphan export~~ FIXED — removed export.
- [x] SCAN-526. ~~[SEC-P0] tickets GET /export authz gap~~ FIXED — allViewCfg visibility guard mirrored from list handler.
- [x] SCAN-527. ~~[SEC-P0 PII] tickets feedback SMS console.log phone~~ FIXED — logger + redactPhone.
- [x] SCAN-528. ~~[SEC-P0 PII] OTP SMS console.error phone~~ FIXED — logger + redactPhone.
- [x] SCAN-529. ~~tickets clone-warranty INSERT missing location_id~~ FIXED — inherits source.location_id ?? 1.
- [x] SCAN-530. ~~[SEC-P0 TCPA] sms auto-responder doesn't check sms_opt_in~~ FIXED — lookup added before tryAutoRespond block.
- [x] SCAN-531. ~~[SEC-P0 TCPA] sms business-hours auto-reply missing opt-in~~ FIXED — sms_opt_in guard on isOutsideHours branch.
- [x] SCAN-532. ~~[SEC] sms templates write endpoints no authz~~ FIXED — requireManagerOrAdmin on POST/PUT/DELETE /templates.
- [x] SCAN-533. ~~invoices credit-note location_id missing~~ FIXED — inherits original.location_id ?? 1.
- [x] SCAN-534. ~~invoices console.warn/error bypassing structured logger~~ FIXED — logger.warn/error at 3 sites.
- [x] SCAN-535. ~~sms preview-template tenant scope~~ CONFIRMED not an issue — per-tenant DB-file model isolates; comment added.
- [x] SCAN-536. ~~[SEC] invoices GET /stats no authz~~ FIXED — requirePermission('invoices.view').

### Wave-8 scan-loop findings (2026-04-23)
- [ ] SCAN-537. **[SEC] reports GET /dashboard no role gate — cashier/tech reads revenue totals + staff leaderboard** — `packages/server/src/routes/reports.routes.ts:51`. Fix: `requireAdminOrManager(req)` (pattern matches /dashboard-kpis:288).
- [ ] SCAN-538. **[SEC] reports GET /insights no role gate — 12-mo revenue-by-model + popular-services** — `packages/server/src/routes/reports.routes.ts:545`. Fix: role gate.
- [ ] SCAN-539. **[SEC] reports GET /employees no role gate — commission totals + hours + revenue per staff leak to cashier/tech** — `packages/server/src/routes/reports.routes.ts:779`. Fix: role gate.
- [ ] SCAN-540. **[SEC] reports GET /inventory no role gate — cost_price × in_stock value + top-moving parts w/ cost** — `packages/server/src/routes/reports.routes.ts:834`. Fix: role gate.
- [ ] SCAN-541. **[SEC] reports GET /tech-workload no role gate — per-tech open-tickets + revenue-this-month + avg repair hours (salary-correlated)** — `packages/server/src/routes/reports.routes.ts:933`. Fix: role gate.
- [ ] SCAN-542. **[SEC] reports GET /needs-attention no role gate — overdue invoices + customer PII + low-stock SKUs** — `packages/server/src/routes/reports.routes.ts:1092`. Fix: role gate.
- [ ] SCAN-543. **[SEC] reports GET /device-models no role gate — aggregated repair counts + avg ticket totals per model (competitive intel)** — `packages/server/src/routes/reports.routes.ts:1191`. Fix: role gate.
- [ ] SCAN-544. **[SEC] reports GET /parts-usage no role gate — supplier names + cost totals per part** — `packages/server/src/routes/reports.routes.ts:1224`. Fix: role gate.
- [ ] SCAN-545. **[SEC] reports GET /stalled-tickets no role gate — tech names grouped with per-tech stall counts (staff-performance PII)** — `packages/server/src/routes/reports.routes.ts:1312`. Fix: role gate.
- [ ] SCAN-546. **portal-enrich /ticket/:id/queue-position missing `guardPortalRate` — rate-limiter applied on other reads but skipped here; unbounded COUNT(*)+EXISTS scans possible** — `packages/server/src/routes/portal-enrich.routes.ts:296`. Fix: add `guardPortalRate(req, PORTAL_READ_CATEGORY, portalIdentityKey(req), PORTAL_READ_MAX, PORTAL_READ_WINDOW_MS)`.
- [ ] SCAN-547. **[SEC-P0] portal getTicketDetail returns full `imei` + `serial` per device — ticket-scoped portal session (last-4-phone auth) leaks hardware IDs enabling SIM-swap / insurance fraud** — `packages/server/src/routes/portal.routes.ts:244,374-375`. Fix: omit imei+serial from portal device map OR gate behind portalScope==='full'.
- [ ] SCAN-548. **portal getTicketDetail uses `SELECT * FROM invoices` — any new column added to invoices table auto-leaks via portal** — `packages/server/src/routes/portal.routes.ts:328`. Fix: explicit column allowlist.
- [ ] SCAN-549. **[SEC] fileUploadValidator adjustFileCounter TOCTOU race — concurrent uploads both read current=99, both write 100 — quota erodes silently** — `packages/server/src/middleware/fileUploadValidator.ts:157-178`. Fix: OS-level O_EXCL lock or move counter to SQLite with atomic UPDATE SET counter=counter+?.
- [ ] SCAN-550. **[SEC-TCPA] campaigns fetchEligibleRecipients `COALESCE(c.sms_opt_in, 1)` defaults opted-in on NULL — violates affirmative-consent, new customers get bulk SMS without consent** — `packages/server/src/routes/campaigns.routes.ts:157`. Fix: `COALESCE(..., 0)` for both sms_opt_in and email_opt_in; update count queries at lines 600-621 consistently.

### Wave-9 scan findings (2026-04-23)
- [ ] SCAN-551. **super-admin auditLog catch uses `console.error` — audit failures on highest-priv path bypass SIEM** — `packages/server/src/routes/super-admin.routes.ts:143`. Fix: `logger.error('super_admin_audit_write_failed', ...)`.
- [ ] SCAN-552. **membership GET /tiers `JSON.parse(benefits)` no try/catch — malformed cell crashes 500** — `packages/server/src/routes/membership.routes.ts:56`. Fix: safe-parse wrapper.
- [ ] SCAN-553. **membership GET /customer/:customerId same bare JSON.parse(benefits)** — `packages/server/src/routes/membership.routes.ts:133`. Fix: safe-parse.
- [ ] SCAN-554. **[SEC-H34] membership 4 money columns `REAL` (monthly_price, discount_pct, last_charge_amount, subscription_payments.amount) — floating-point drift on recurring bills** — `packages/server/src/db/migrations/068_membership_system.sql:6,7,33,48`. Fix: migrate → INTEGER cents + app cents/dollars conversion.
- [ ] SCAN-555. **[SEC] admin PUT /backup-settings passes `req.body` unvalidated to updateBackupSettings — path traversal / unbounded schedule** — `packages/server/src/routes/admin.routes.ts:501-504`. Fix: path blocked-list + schedule regex + retention int range.
- [ ] SCAN-556. **tradeIns POST / + PATCH /:id no rate-limit on financial-write mutation — DB flood via session** — `packages/server/src/routes/tradeIns.routes.ts:86-116,123`. Fix: `consumeWindowRate` keyed by user.
- [ ] SCAN-557. **[SEC] tradeIns GET / + GET /:id no `requirePermission` — any auth user enumerates imei/serial/offered_price/customer PII** — `packages/server/src/routes/tradeIns.routes.ts:46-69`. Fix: `requirePermission('trade_ins.read')` or role check.
- [ ] SCAN-558. **cloudflareDns 4 `console.log` leak tenant slugs + DNS record IDs to plaintext logs** — `packages/server/src/services/cloudflareDns.ts:178,198,216,222`. Fix: structured logger.
- [ ] SCAN-559. **[SEC] billing 3 `console.error` may dump Stripe API error with PII/card-fragments** — `packages/server/src/routes/billing.routes.ts:34,64,91`. Fix: `logger.error` pipeline.
- [ ] SCAN-560. **management PM2 restart/stop `console.error` bypass structured log** — `packages/server/src/routes/management.routes.ts:626,636`. Fix: logger.error.
- [ ] SCAN-561. **pos 3 audit-write `console.error` on hot path — PII-bearing err dumped to stdout** — `packages/server/src/routes/pos.routes.ts:1934,2164,2201`. Fix: logger.error.
- [ ] SCAN-562. **invoices 2 more `console.warn` at lines 845 + 1151 (credit-note overflow financial op — forensic loss)** — `packages/server/src/routes/invoices.routes.ts:845,1151`. Fix: logger.warn.
- [ ] SCAN-563. **[SEC] admin.routes `adminTokens` in-memory Map unbounded — 60s cleanup interval; heap exhaustion via login floods** — `packages/server/src/routes/admin.routes.ts:29`. Fix: cap size 1000 + evict-oldest OR fixed-size LRU.
- [ ] SCAN-564. **[SEC] super-admin `challenges` in-memory Map unbounded — 2FA-setup challenges accumulate; per-adminId not per-IP rate-limited** — `packages/server/src/routes/super-admin.routes.ts:154`. Fix: size cap + LRU OR one-challenge-per-IP limit.
- [ ] SCAN-565. **tickets SMS lookup `console.error` may log customer phones from error messages** — `packages/server/src/routes/tickets.routes.ts:758`. Fix: logger.error + scrub phone numbers before log.

### Wave-10 scan findings (2026-04-23)
- [ ] SCAN-566. **expenseApi.create/update missing `location_id` param — web UI silently drops field, all expenses default location 1 regardless of user intent** — `packages/web/src/api/endpoints.ts:455-463`. Fix: add `location_id?: number` to typed param shapes.
- [ ] SCAN-567. **employeeApi.clockIn/Out pass only `{pin}` — POST /clock-in INSERT omits location_id, migration-142 column always NULL** — `packages/web/src/api/endpoints.ts:735-736` + `packages/server/src/routes/employees.routes.ts:347`. Fix: thread optional location_id through both.
- [ ] SCAN-568. **leads appointments INSERTs (2 sites single + recurring) omit location_id** — `packages/server/src/routes/leads.routes.ts:516,578`. Fix: accept + validate + INSERT location_id.
- [ ] SCAN-569. **tickets POST /:id/appointment INSERT omits location_id** — `packages/server/src/routes/tickets.routes.ts:3679`. Fix: accept + validate + INSERT.
- [ ] SCAN-570. **[SEC-TCPA] campaigns marketing consent gap — uses only `sms_opt_in` (legacy global flag) ignoring `sms_consent_marketing` (migration 063 TCPA marketing-channel consent); line 740 transactional still `COALESCE(...,1)`** — `packages/server/src/routes/campaigns.routes.ts:157-164,740`. Fix: join + require `sms_consent_marketing=1` for 'sms'/'both' channel; `COALESCE(...,0)` on line 740 too.
- [ ] SCAN-571. **[SEC] super-admin impersonate no end-event + no tenant-side audit + no revocable session row — stolen JWT cannot be revoked short of rotating secret** — `packages/server/src/routes/super-admin.routes.ts:2097-2161`. Fix: write tenant sessions row + tenant-side audit() + `POST /tenants/:slug/impersonate/:jti/end` endpoint.
- [ ] SCAN-572. **index.ts `corsRejectionLog` module-level Map unbounded (no TTL/size cap) — subdomain spray grows map forever** — `packages/server/src/index.ts:1069-1074`. Fix: 5-min cleanup interval evicting entries older than throttle window OR `addWithCap`.
- [ ] SCAN-573. **web ExpensesPage createMut.mutate passes `form:any` — TypeScript can't catch missing/extra fields incl. new location_id** — `packages/web/src/pages/expenses/ExpensesPage.tsx:41,61`. Fix: typed `ExpenseFormPayload` interface.
- [ ] SCAN-574. **backup filename prefix not run through `assertSafePath` — slug edge-cases could confuse `isBackupFile` regex** — `packages/server/src/services/backup.ts:607-610`. Fix: `/^[a-z0-9-]+$/` assertion on prefix.
- [ ] SCAN-575. **adminTokens stale entries only evicted on cap-overflow — low-volume admin login accumulates forever** — `packages/server/src/routes/admin.routes.ts:29,73`. Fix: 5-min sweep `setInterval` deletes entries where expires < now.

### Wave-11 scan findings (2026-04-23)
- [ ] SCAN-576. **estimates SEC-M54 quota-refund uses `console.error` not logger** — `packages/server/src/routes/estimates.routes.ts:461`. Fix: `logger.error`.
- [ ] SCAN-577. **estimates GET /:id/versions/:versionId bare `JSON.parse(version.data)` no try/catch — corrupt snapshot crashes 500** — `packages/server/src/routes/estimates.routes.ts:678`. Fix: try/catch or `safeParseJson`.
- [ ] SCAN-578. **estimates POST /bulk-convert inline role check not via requirePermission** — `packages/server/src/routes/estimates.routes.ts:307-309`. Fix: `requirePermission('estimates.create')` (or dedicated bulk permission).
- [ ] SCAN-579. **[SEC] loaners POST/PUT/DELETE + /loan + /return no `requirePermission` — any auth user can create/modify/delete hardware assets** — `packages/server/src/routes/loaners.routes.ts:67,80,104,139,162`. Fix: `requirePermission('inventory.adjust')`.
- [ ] SCAN-580. **[SEC] stocktake POST / (open session) no role gate — technician opens session + scans variances + manager unknowingly commits** — `packages/server/src/routes/stocktake.routes.ts:87-122`. Fix: admin|manager gate at handler top.
- [ ] SCAN-581. **[SEC] stocktake POST /:id/counts (scan entry) no role gate** — `packages/server/src/routes/stocktake.routes.ts:169-247`. Fix: admin|manager|technician minimum.
- [ ] SCAN-582. **[SEC-TCPA] dunningScheduler dispatchStep sends SMS without `sms_opt_in` / `sms_consent_transactional` check** — `packages/server/src/services/dunningScheduler.ts:598-644`. Fix: load consent in `loadCustomer` + skip when opted-out + record `outcome:'skipped'`.
- [ ] SCAN-583. **dunningScheduler sendSmsTenant return typed `any`; fragile `.success === false` check passes undefined → every SMS logged dispatched even on silent fail** — `packages/server/src/services/dunningScheduler.ts:617`. Fix: assert provider-specific success field OR check `!result`.
- [ ] SCAN-584. **[SEC] automations GET / no role gate — any auth user enumerates rules incl. action_config (SMS/email templates + target user IDs)** — `packages/server/src/routes/automations.routes.ts:39-56`. Fix: `requirePermission('automations.read')` or admin gate.
- [ ] SCAN-585. **[SEC-TCPA] automations.ts executeSendSms uses global `sendSms` not `sendSmsTenant` + no opt-in check — automation-triggered SMS bypass consent** — `packages/server/src/services/automations.ts:238-247`. Fix: load consent before dispatch OR pass db + use isAutoSmsAllowed.
- [ ] SCAN-586. **rma GET /:id passes raw req.params.id — non-numeric "../admin" returns 404 silently** — `packages/server/src/routes/rma.routes.ts:99`. Fix: parseInt + finite + >0 guard.
- [ ] SCAN-587. **tenantTermination WAL/SHM rename bare `catch {}` silent swallow — incomplete archive on permission/lock error** — `packages/server/src/services/tenantTermination.ts:315`. Fix: `logger.warn` with slug+error.
- [ ] SCAN-588. **repairPricing /prices query params empty string not validated — silent zero rows instead of 400** — `packages/server/src/routes/repairPricing.routes.ts:146-177`. Fix: parseInt + isFinite before use.
- [ ] SCAN-589. **reportEmailer ticket_status JOIN uses direct `ts.name = th.new_value` — case/trim fragile; status rename zeros weekly report** — `packages/server/src/services/reportEmailer.ts:88-92`. Fix: `LOWER(TRIM(...))` pattern from scheduledReports.ts:104-112.
- [ ] SCAN-590. **estimates POST /:id/convert tier-limit block leaves estimate in 'converting' permanently (no finally block revert)** — `packages/server/src/routes/estimates.routes.ts:757`. Fix: add finally{} that reverts status when function exits before 'converted' write; OR move tier check before status lock.

### Wave-12 scan findings (2026-04-23)
- [ ] SCAN-591. **idempotency middleware `INSERT idempotency_keys` on GET/PATCH (not just POST) — phantom rows block subsequent POSTs until 24h sweep** — `packages/server/src/middleware/idempotency.ts:87`. Fix: `if (req.method !== 'POST') { next(); return; }` at top.
- [ ] SCAN-592. **crashResiliency module-level `currentRequestRoute` mutable — concurrent requests interleave, A's crash attributed to B's route** — `packages/server/src/middleware/crashResiliency.ts:34`. Fix: per-request `res.locals.currentRoute` read from uncaughtException handler.
- [ ] SCAN-593. **[SEC] stepUpTotp no replay guard — valid TOTP code usable multiple times within 30s window → 2 concurrent PII-export requests both succeed on one OTP tap** — `packages/server/src/middleware/stepUpTotp.ts:196`. Fix: `(userId, code, windowBucket)` set in memory or DB; reject reuse within bucket.
- [ ] SCAN-594. **[SEC-TCPA P0] inbox previewBulkSegment `all_customers`/`open_tickets`/`recent_purchases` segments have no `sms_opt_in`/`sms_consent_marketing` filter — bulk-send dispatches to non-consented phones** — `packages/server/src/routes/inbox.routes.ts:394`. Fix: `AND COALESCE(c.sms_opt_in,0)=1 AND COALESCE(c.sms_consent_marketing,0)=1` on all 3 segment queries.
- [ ] SCAN-595. **[SEC-DATA-LOSS] tenantTermination purgeExpiredDeletions uses archive file `mtime` not DB `deletion_scheduled_at` — touch/backup-restore causes early purge OR permanent retention** — `packages/server/src/services/tenantTermination.ts:404`. Fix: authoritative cutoff from master DB; fallback to mtime only when DB record absent.
- [ ] SCAN-596. **campaigns review-request/trigger coupled to admin JWT despite being internal-event hook — server-internal calls drop silently** — `packages/server/src/routes/campaigns.routes.ts:731`. Fix: expose as internal function OR add IP-allowlist/service-token path.
- [ ] SCAN-597. **customFields PUT /values/:entityType/:entityId no entity existence check — phantom entity_id values silently accumulate** — `packages/server/src/routes/customFields.routes.ts:133`. Fix: `SELECT id FROM <entity_table> WHERE id = ?` precheck.
- [ ] SCAN-598. **snippets PUT /:id doesn't re-validate shortcode regex (POST does) — admin can set shortcode with whitespace/shell metachars** — `packages/server/src/routes/snippets.routes.ts:81`. Fix: apply `/^[a-zA-Z0-9_\\-]+$/` guard.
- [ ] SCAN-599. **web App.tsx `/super-admin/tenants` route reachable for regular tenant admins — no SuperAdminRoute guard (page has its own login but routing is unrestricted)** — `packages/web/src/App.tsx:425`. Fix: SuperAdminRoute wrapper.
- [ ] SCAN-600. **useWebSocket `connect` in effect deps + queryClient dep in useCallback — queryClient identity change recreates connect → old onclose reconnects after new WS is live (redundant reconnect)** — `packages/web/src/hooks/useWebSocket.ts:314,362`. Fix: queryClient into useRef OR stabilize identity.
- [ ] SCAN-601. **useDraft keyRef.current read inside timeout callback — key change before timeout fire writes new key's text with old-key's last value** — `packages/web/src/hooks/useDraft.ts:33`. Fix: capture `const currentKey = keyRef.current` in effect body.
- [ ] SCAN-602. **[SEC] inbox bulk-send step-2 re-fetches segment — phones added between preview token mint + dispatch receive SMS admin never confirmed** — `packages/server/src/routes/inbox.routes.ts:527`. Fix: HMAC phone-list hash or count in confirmation token; reject on drift.
- [ ] SCAN-603. **tenantTermination master_audit_log row hardcodes `ip_address=NULL` for `tenant_self_terminated` — IP available but not threaded** — `packages/server/src/services/tenantTermination.ts:350,354`. Fix: plumb requestIp through FinalizeTerminationInput.
- [ ] SCAN-604. **idempotency DB INSERT error logs + calls next() — fail-open silently bypasses idempotency; retry dupes mutations** — `packages/server/src/middleware/idempotency.ts:122`. Fix: return 503 on unexpected DB error, OR add `X-Idempotency-Bypassed: 1` header so caller detects degraded path.

### Wave-13 scan findings (2026-04-23)
- [ ] SCAN-605. **[SEC-TCPA P0] stale-ticket auto-SMS cron (ENR-A1) no consent check — `sms_opt_in`/`sms_consent_transactional` not read; only rate-limit checked** — `packages/server/src/index.ts:2983-3002`. Fix: add consent columns to SELECT, skip if opted-out.
- [ ] SCAN-606. **[SEC-TCPA P0] overdue-invoice auto-reminder cron (ENR-A2) no consent check** — `packages/server/src/index.ts:3060-3078`. Fix: same pattern.
- [ ] SCAN-607. **[SEC-TCPA P0] estimate follow-up cron (ENR-LE8) no consent check** — `packages/server/src/index.ts:3136-3147`. Fix: same pattern.
- [ ] SCAN-608. **[SEC-TCPA] customers POST /bulk-sms only checks `sms_opt_in` — `sms_consent_marketing` ignored (migration 063 granular column)** — `packages/server/src/routes/customers.routes.ts:764`. Fix: add column to SELECT + skip condition.
- [ ] SCAN-609. **[SEC] WS tenant origin check fire-and-forget — auth success frame sent + socket added to clients map BEFORE async origin revalidation rejects** — `packages/server/src/ws/server.ts:450-465,473`. Fix: await origin check before register/send.
- [ ] SCAN-610. **[SEC] bench GET /timer/by-ticket/:ticketId returns all users' timer rows — no ownership/role check; leaks labor_rate_cents/notes/pause_log across techs** — `packages/server/src/routes/bench.routes.ts:533-566`. Fix: admin/manager see all; tech WHERE user_id=?.
- [ ] SCAN-611. **[SEC] bench GET /defects/by-item/:id returns full rows incl `photo_path` + `description` with no role gate** — `packages/server/src/routes/bench.routes.ts:1088-1104`. Fix: restrict to admin/manager OR strip photo_path for non-admins.
- [ ] SCAN-612. **[SEC] paymentLinks GET /:id returns `SELECT *` incl raw `token` + `created_by_user_id` + click counts to any auth user** — `packages/server/src/routes/paymentLinks.routes.ts:96-101`. Fix: `requireManagerOrAdmin` (matches create/cancel gate).
- [ ] SCAN-613. **[SEC] JWT type check still accepts tokens with `type === undefined` as access tokens — refresh-token reuse if crafted/legacy** — `packages/server/src/routes/auth.routes.ts:82`. Fix: strictly require `payload.type === 'access'`.
- [ ] SCAN-614. **web client.ts JWT atob decode without length cap — corrupt localStorage payload can block main thread + catch doesn't remove malformed token** — `packages/web/src/api/client.ts:87`. Fix: `localStorage.removeItem('accessToken')` in catch OR byte-length cap pre-parse.
- [ ] SCAN-615. **[SEC] deviceTemplates POST /:id/apply-to-ticket/:ticketId no role gate — tech/cashier can silently apply any template** — `packages/server/src/routes/deviceTemplates.routes.ts:382-493`. Fix: admin/manager gate (matches create/update/delete).
- [ ] SCAN-616. **[SEC] bench GET /qc/status/:ticketId returns `tech_signature_path` + `working_photo_path` to any auth user — reveals server upload dir structure** — `packages/server/src/routes/bench.routes.ts:680-722`. Fix: strip paths for non-admin/non-manager OR return only boolean signed flag.

### Wave-14 scan findings (2026-04-23)
- [ ] SCAN-617. **[SEC-TCPA P0] appointment-reminder cron no consent check — 4th cron missed previous fixes** — `packages/server/src/index.ts:2709`. Fix: add sms_opt_in + sms_consent_transactional to SELECT; skip opted-out.
- [ ] SCAN-618. **[SEC-TCPA P0] notification_queue SMS cron (ENR-A7) no opt-in check — queue fires unconditionally** — `packages/server/src/index.ts:3214`. Fix: lookup consent by recipient phone at dispatch OR opt_in_verified=1 gate at enqueue.
- [ ] SCAN-619. **reportEmailer tickets-closed query still uses single action + no ticket_history JOIN improvements from scheduledReports fix** — `packages/server/src/services/reportEmailer.ts:91`. Fix: copy multi-action IN (...) + LOWER TRIM pattern from scheduledReports.ts:104-112.
- [ ] SCAN-620. **[SEC] invoices GET / list no `requirePermission` — tech can list all invoices incl amounts + customer refs** — `packages/server/src/routes/invoices.routes.ts:110`. Fix: `requirePermission('invoices.view')` (matches /stats pattern).
- [ ] SCAN-621. **estimates POST /:id/convert vs POST /bulk-convert use DIFFERENT column names for ticket_notes — `note` vs `content` — one is wrong** — `packages/server/src/routes/estimates.routes.ts:808,418`. Fix: confirm actual column + align both.
- [ ] SCAN-622. **reportEmailer computes week window with UTC (`.toISOString().slice(0,10)`) not tenant TZ — same TZ6 bug fixed in scheduledReports** — `packages/server/src/services/reportEmailer.ts:55`. Fix: pass timezone from DeliveryTargets + use tenant-local date.
- [ ] SCAN-623. **invoices POST /bulk-action mark_paid branch skips loyalty accrual + commission vs single /:id/payments path** — `packages/server/src/routes/invoices.routes.ts:863`. Fix: replicate `accruePaymentPoints` + `writeCommission` into bulk branch.
- [ ] SCAN-624. **[PII] stale-ticket + invoice-reminder + estimate-followup cron success uses `console.log` with raw `${phone}` — SEC-M56 last-4 mask bypass** — `packages/server/src/index.ts:3007,3094,3165`. Fix: `log.info` + `redactPhone(phone)`.
- [ ] SCAN-625. **scheduledReports inline `smtp_host` check diverges from `isEmailConfigured` helper** — `packages/server/src/services/scheduledReports.ts:239,246`. Fix: replace with `isEmailConfigured(db)` for consistency.
- [ ] SCAN-626. **estimates POST /:id/send imports from `providers/sms/index.js` not `services/smsProvider.js` — bypasses tenant provider lookup** — `packages/server/src/routes/estimates.routes.ts:924-925`. Fix: use `sendSmsTenant` from `services/smsProvider.js`.
- [ ] SCAN-627. **invoices bulk mark_paid no `logActivity` + no `fireWebhook('payment_received',...)` — audit + integration gap vs single payment path** — `packages/server/src/routes/invoices.routes.ts:880,940`. Fix: replicate logActivity + fireWebhook from /:id/payments.
- [ ] SCAN-628. **reportEmailer defines module-private `escapeHtml` duplicating shared utility** — `packages/server/src/services/reportEmailer.ts:235`. Fix: import from utils/escape.js; delete local.

### Wave-15 scan findings (2026-04-23)
- [ ] SCAN-629. **refunds reverseCommission called OUTSIDE approval tx — 403 from locked-payroll-period propagates as unhandled 500 AFTER refund already committed → caller thinks failed, retries** — `packages/server/src/routes/refunds.routes.ts:287`. Fix: wrap in try/catch, 200 with `commission_reversal_skipped:true` on AppError 403.
- [ ] SCAN-630. **portal consumeRate non-atomic check+record — two concurrent /login or /register/send-code both pass → maxAttempts+1 actual** — `packages/server/src/routes/portal.routes.ts:84,87`. Fix: use `consumeWindowRate` (atomic, already used on some paths).
- [ ] SCAN-631. **portal /login success doesn't clear `portal_pin_verify` bucket — legitimate user can't log in from 2nd device within 10min window after correct PIN on attempt 4** — `packages/server/src/routes/portal.routes.ts:626-652`. Fix: `clearRateLimit(req.db, RL.PIN_VERIFY, customer.id)` on success.
- [ ] SCAN-632. **portal idle-timeout parses `last_used_at + 'Z'` — if server tz != UTC, idle window drifts ±14h** — `packages/server/src/routes/portal.routes.ts:135`. Fix: use `datetime('now', 'utc')` at store time OR parse without appending 'Z'.
- [ ] SCAN-633. **db-worker.ts dead code shadows db-worker.mjs — TS file lacks expectChanges guard; build misconfig silently drops rollback protection on refunds/stock** — `packages/server/src/db/db-worker.ts:41-73`. Fix: delete db-worker.ts OR compile-time assert only .mjs used.
- [ ] SCAN-634. **blockchyp getClient accepts `db: any` — callers may pass req.asyncDb accidentally, runtime crash on `.prepare()`** — `packages/server/src/services/blockchyp.ts:105-151`. Fix: type as `Database.Database`.
- [ ] SCAN-635. **blockchyp sweepStuckPaymentIdempotency template-literal SQL (`-${STUCK_PENDING_THRESHOLD_MINUTES} minutes`) — pattern risk for future config-driven values** — `packages/server/src/services/blockchyp.ts:820,817`. Fix: parameterize via `datetime('now', ? || ' minutes')`.
- [ ] SCAN-636. **[SEC] dunning GET /sequences no role gate — cashier reads collection cadence + contact strategy** — `packages/server/src/routes/dunning.routes.ts:49-63`. Fix: `requireAdmin(req)` (matches sibling writes).
- [ ] SCAN-637. **rma `received` transition status UPDATE + N stock increments NOT in transaction — mid-flight crash leaves RMA received but stock not restored** — `packages/server/src/routes/rma.routes.ts:255-268,230`. Fix: batch in `adb.transaction([TxQuery[]])`.
- [ ] SCAN-638. **web ReportsPage useEffect risk of loop — openUpgradeModal not in deps + isReportTabLocked not memoized + eslint-disable suppresses exhaustive-deps warning** — `packages/web/src/pages/reports/ReportsPage.tsx:1144-1153`. Fix: `useCallback` isReportTabLocked + include openUpgradeModal in deps (or ref) + drop lint-disable.
- [ ] SCAN-639. **portal embed-config uses dynamic `import('../utils/rateLimiter.js')` at request time — overhead + theoretical failure lets request pass without rate-limit** — `packages/server/src/routes/portal.routes.ts:1487`. Fix: use static top-of-file import (already exists at line 9).

### Wave-16 scan findings (2026-04-23)
- [ ] SCAN-640. **errorHandler middleware 2 console.error bypass structured logger** — `packages/server/src/middleware/errorHandler.ts:40,42`. Fix: logger.error.
- [ ] SCAN-641. **tenantResolver 2 console.error in critical auth path** — `packages/server/src/middleware/tenantResolver.ts:429,491`. Fix: log.error.
- [ ] SCAN-642. **tierGate 2 console.warn** — `packages/server/src/middleware/tierGate.ts:17,28`. Fix: createLogger + structured.
- [ ] SCAN-643. **tickets feedback SMS detached setTimeout console.error** — `packages/server/src/routes/tickets.routes.ts:2132`. Fix: logger.error.
- [ ] SCAN-644. **tickets notification import dynamic-chain console.error** — `packages/server/src/routes/tickets.routes.ts:2091`. Fix: logger.error.
- [ ] SCAN-645. **auth.routes JSON.parse(backup_codes) no try/catch — corrupt column throws in loop, unhandled 500 leak** — `packages/server/src/routes/auth.routes.ts:1051`. Fix: try/catch → valid:false.
- [ ] SCAN-646. **auth.routes JSON.parse(user.permissions) 3 bare sites (generateTokens, refresh, impersonate) — corrupt column throws during token gen** — `packages/server/src/routes/auth.routes.ts:401,1287,1443`. Fix: `safeParsePermissions(raw)` helper at all 3 sites.
- [ ] SCAN-647. **campaigns `requireAdminOrServiceToken(req: any)` — type-check disabled on auth helper** — `packages/server/src/routes/campaigns.routes.ts:750`. Fix: `Request` type + augmented req.user.
- [ ] SCAN-648. **settings req.body `Record<string,string>` cast without typeof guard — non-string values silently coerce via String()** — `packages/server/src/routes/settings.routes.ts:428,487,1830`. Fix: typeof-string guard before accept.
- [ ] SCAN-649. **10 bare `setInterval(...)` across 7+ route files not using trackInterval — leak handles on shutdown/test** — admin×2, auth, signup×3, invoices, management, super-admin, import. Fix: `trackInterval` (extract to shared util if needed).
- [ ] SCAN-650. **catalog req.body `as` cast + `q.trim()` without typeof string check — `q:42` → TypeError** — `packages/server/src/routes/catalog.routes.ts:580`. Fix: typeof guard.
- [ ] SCAN-651. **metricsCollector 2 console.log startup + rollup** — `packages/server/src/services/metricsCollector.ts:144,307`. Fix: log.info.
- [ ] SCAN-652. **tenantTermination module-scope `setInterval(...)` not via trackInterval** — `packages/server/src/services/tenantTermination.ts:76`. Fix: return handle from start() + register in index.ts.
- [ ] SCAN-653. **posEnrich `JSON.parse(cartSerialized)` no try/catch (surrounding helper has one, this doesn't)** — `packages/server/src/routes/posEnrich.routes.ts:553`. Fix: use parseTrainingTxList helper OR wrap + AppError.

### Wave-18 scan-loop findings in wave-3/4 code (2026-04-23)
- [ ] SCAN-654. **[SEC-HIGH] bookingPublic /availability IP rate-limit uses `req.ip` directly — XFF spoof bypass behind proxy** — `packages/server/src/routes/bookingPublic.routes.ts:44`. Fix: use `req.socket.remoteAddress` (SCAN-194 pattern).
- [ ] SCAN-655. **[HIGH] pos POST `/workstations/:id/set-default` missing `asyncHandler` wrap — unhandled rejection crashes server** — `packages/server/src/routes/pos.routes.ts:2294`. Fix: wrap handler.
- [ ] SCAN-656. **locations POST /:id/set-default trigger `trg_locations_single_default_update` clears others AND app also runs UPDATE — non-atomic double-clear race** — `packages/server/src/routes/locations.routes.ts:493`. Fix: rely on trigger alone OR wrap both in adb.transaction.
- [ ] SCAN-657. **ownerPl LRU cache key uses `req.tenantSlug` hint — if resolved tenant differs, cross-tenant cache collision** — `packages/server/src/routes/ownerPl.routes.ts:544-545`. Fix: include `req.tenantId` (DB-resolved) in key; not the client-supplied slug.
- [ ] SCAN-658. **fieldService PATCH /jobs/:id `validateOptionalLatLng` accepts empty string → `Number('')=0`, PATCH writes NaN/0 to DB** — `packages/server/src/routes/fieldService.routes.ts:398-400,439`. Fix: treat `''` as `undefined` (no-op) OR reject 400.
- [ ] SCAN-659. **locations PATCH /:id inconsistent COALESCE — `address_line` uses `?? null` while other fields use conditional; undefined overwrites old value on some fields only** — `packages/server/src/routes/locations.routes.ts:405-414`. Fix: uniform COALESCE pattern for all optional fields.
- [ ] SCAN-660. **[POSSIBLE] ownerPl computeSummary fires 14 parallel queries incl AR capped at 10k — memory spike unbounded on large tenants** — `packages/server/src/routes/ownerPl.routes.ts:390-405`. Fix: sequential or limit concurrency (p-limit 4) OR SQL-side aggregation.
- [ ] SCAN-661. **bookingConfig POST /exceptions allows `is_closed=true` with `open_time`/`close_time` supplied — no mutual exclusion enforcement** — `packages/server/src/routes/bookingConfig.routes.ts:434-449`. Fix: reject 400 if is_closed && (open_time || close_time).
- [ ] SCAN-662. **syncConflicts `validateVersionJson` byte-size check after `.trim()` — whitespace-padded JSON bypasses 32KB cap** — `packages/server/src/routes/syncConflicts.routes.ts:144`. Fix: size-check raw input before trim.
- [ ] SCAN-663. **bookingPublic /availability Cache-Control header set conditionally AFTER JSON build — thrown error drops cache directive** — `packages/server/src/routes/bookingPublic.routes.ts:255,273,293`. Fix: set header at top of handler.
