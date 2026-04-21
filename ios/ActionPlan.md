# ios/ActionPlan.md — iOS Feature-Parity & Polish Plan

> **Mission.** Bring the iOS app (iPhone + iPad, plus Mac via "Designed for iPad") to complete feature parity with both the web and Android clients, keep it as convenient as either — and ship a UI worthy of the Liquid Glass visual language.
>
> **How to read this document.** Every top-level section is a domain (auth, tickets, customers, inventory …). Inside each domain, items follow this shape:
>
> - **Backend** — what server route / websocket topic / webhook the feature depends on, with status notes (exists / missing / partial).
> - **Frontend (iOS)** — the SwiftUI surfaces (Views, ViewModels, repository, persistence, extensions) needed, with separate notes for iPhone vs iPad vs Mac where layouts diverge.
> - **Expected UX** — the user-story step-by-step flow, empty states, error states, confirmations, gestures, shortcuts, haptics, animations, motion-reduce alternative, glass usage, and parity call-outs vs web/Android.
> - **Status** — `[ ]` not started · `[~]` partial · `[x]` shipped · `[!]` blocked. Each item is individually checkable so a human or an agent can close them incrementally.
>
> **Non-negotiables** (apply to every section, don't re-state per item):
> - iPad is NEVER an upscaled iPhone. `Platform.isCompact` gates layout branches.
> - Liquid Glass (`.brandGlass`) on nav chrome / toolbars / FABs / badges / sticky banners. Never on content rows, cards, SMS bubbles.
> - API envelope `{ success, data, message }` — single unwrap.
> - **Offline architecture (§20) is Phase 0 foundation, not a later feature.** Every domain section (§§1–19 and every writer section in §36+) is built on top of it from day one. Required contract: reads go through a repository that reads from GRDB via `ValueObservation`; writes go through the §20.2 sync queue with idempotency keys + optimistic UI + dead-letter; never a bare `URLSession` call from a ViewModel. PRs that touch a domain without wiring into §20 machinery are rejected in code review; lint rule flags raw `APIClient.get/post` usage outside repositories. GRDB + SQLCipher cache per repository.
> - Pagination: **cursor-based, offline-first** (see §20.5). Lists read from SQLCipher via `ValueObservation` — never from API directly. `loadMoreIfNeeded(rowId)` kicks next-cursor fetch when online; no-op when offline (or un-archives evicted older rows). `hasMore` derived locally from `{ oldestCachedAt, serverExhaustedAt? }` per entity, NOT from `total_pages`. Footer has four distinct states: loading / more-available / end-of-list / offline-with-cached-count.
> - Accessibility: VoiceOver label on every tappable glyph, Dynamic Type tested to XXXL, Reduce Motion + Reduce Transparency honored, 44pt min tap target.
> - Mac: keyboard shortcuts (⌘N / ⌘F / ⌘R / ⌘,), `.hoverEffect(.highlight)`, `.textSelection(.enabled)` on IDs/emails/invoice numbers, `.contextMenu` on rows, `.fileExporter` for PDF/CSV.
>
> **Source-of-truth map.**
> - Web routes: `packages/web/src/{pages,app}/`
> - Android: `android/app/src/main/java/.../ui/screens/`
> - Server API: `packages/server/src/routes/`
> - Contracts: `packages/contracts/`
> - iOS modules: `ios/Packages/<Domain>/Sources/`

---
## Table of Contents

1. [Platform & Foundation](#1-platform-foundation)
2. [Authentication & Onboarding](#2-authentication-onboarding)
3. [Dashboard & Home](#3-dashboard-home)
4. [Tickets (Service Jobs)](#4-tickets-service-jobs)
5. [Customers](#5-customers)
6. [Inventory](#6-inventory)
7. [Invoices](#7-invoices)
8. [Estimates](#8-estimates)
9. [Leads](#9-leads)
10. [Appointments & Calendar](#10-appointments-calendar)
11. [Expenses](#11-expenses)
12. [SMS & Communications](#12-sms-communications)
13. [Notifications](#13-notifications)
14. [Employees & Timeclock](#14-employees-timeclock)
15. [Reports & Analytics](#15-reports-analytics)
16. [POS / Checkout](#16-pos-checkout)
17. [Hardware Integrations](#17-hardware-integrations)
18. [Search (Global + Scoped)](#18-search-global-scoped)
19. [Settings](#19-settings)
20. [Offline, Sync & Caching — PHASE 0 FOUNDATION (read before §§1–19)](#20-offline-sync-caching)
21. [Background, Push, & Real-Time](#21-background-push-real-time)
22. [iPad-Specific Polish](#22-ipad-specific-polish)
23. [Mac ("Designed for iPad") Polish](#23-mac-designed-for-ipad-polish)
24. [Widgets, Live Activities, App Intents, Siri, Shortcuts](#24-widgets-live-activities-app-intents-siri-shortcuts)
25. [Spotlight, Handoff, Universal Clipboard, Share Sheet](#25-spotlight-handoff-universal-clipboard-share-sheet)
26. [Accessibility](#26-accessibility)
27. [Internationalization & Localization](#27-internationalization-localization)
28. [Security & Privacy](#28-security-privacy)
29. [Performance Budget](#29-performance-budget)
30. [Design System & Motion](#30-design-system-motion)
31. [Testing Strategy](#31-testing-strategy)
32. [Telemetry, Crash, Logging](#32-telemetry-crash-logging)
33. [CI / Release / TestFlight / App Store — DEFERRED (revisit pre-Phase 11)](#33-ci-release-testflight-app-store)
34. [Known Risks & Blockers](#34-known-risks-blockers)
35. [Parity Matrix (at-a-glance)](#35-parity-matrix-at-a-glance)
36. [Setup Wizard (first-run tenant onboarding) — HIGH PRIORITY](#36-setup-wizard-first-run-tenant-onboarding)
37. [Marketing & Growth](#37-marketing-growth)
38. [Memberships / Loyalty](#38-memberships-loyalty)
39. [Cash Register & Z-Report](#39-cash-register-z-report)
40. [Gift Cards / Store Credit / Refunds](#40-gift-cards-store-credit-refunds)
41. [Payment Links & Public Pay Page](#41-payment-links-public-pay-page)
42. [Voice & Calls](#42-voice-calls)
43. [Device Templates / Repair-Pricing Catalog](#43-device-templates-repair-pricing-catalog)
44. [CRM Health Score & LTV](#44-crm-health-score-ltv)
45. [Team Collaboration (internal messaging)](#45-team-collaboration-internal-messaging)
46. [Goals, Performance Reviews & Time Off](#46-goals-performance-reviews-time-off)
47. [Roles Matrix Editor](#47-roles-matrix-editor)
48. [Data Import (RepairDesk / Shopr / MRA / CSV)](#48-data-import-repairdesk-shopr-mra-csv)
49. [Data Export](#49-data-export)
50. [Audit Logs Viewer — ADMIN ONLY](#50-audit-logs-viewer)
51. [Training Mode (sandbox)](#51-training-mode-sandbox)
52. [Command Palette (⌘K)](#52-command-palette-k)
53. [Public Tracking Page — SERVER-SIDE SURFACE (iOS is thin)](#53-public-tracking-page)
54. [TV Queue Board — NOT AN iOS FEATURE](#54-tv-queue-board)
55. [Assistive / Kiosk Single-Task Modes](#55-assistive-kiosk-single-task-modes)
56. [Appointment Self-Booking — CUSTOMER-FACING; NOT THIS APP](#56-appointment-self-booking)
57. [Field-Service / Dispatch (mobile tech)](#57-field-service-dispatch-mobile-tech)
58. [Purchase Orders (inventory)](#58-purchase-orders-inventory)
59. [Financial Dashboard (owner view)](#59-financial-dashboard-owner-view)
60. [Multi-Location Management](#60-multi-location-management)
61. [Release checklist (go-live gates)](#61-release-checklist-go-live-gates)
62. [Non-goals (explicit)](#62-non-goals-explicit)
63. [Error, Empty & Loading States (cross-cutting)](#63-error-empty-loading-states-cross-cutting)
64. [Copy & Content Style Guide (iOS-specific tone)](#64-copy-content-style-guide-ios-specific-tone)
65. [Deep-link / URL scheme reference](#65-deep-link-url-scheme-reference)
66. [Haptics Catalog (iPhone-specific)](#66-haptics-catalog-iphone-specific)
67. [Motion Spec](#67-motion-spec)
68. [Launch Experience](#68-launch-experience)
69. [In-App Help](#69-in-app-help)
70. [Notifications — granular per-event matrix](#70-notifications)
71. [Privacy-first analytics event list](#71-privacy-first-analytics-event-list)
72. [Final UX Polish Checklist](#72-final-ux-polish-checklist)
73. [CarPlay — DEFERRED (contents preserved, not active work)](#73-carplay)
74. [Server API gap analysis — PRE-PHASE-0 GATE](#74-server-api-gap-analysis)
75. [App Store / TestFlight assets — DEFERRED (pre-Phase-11 only)](#75-app-store-testflight-assets)
76. [TestFlight rollout plan — DEFERRED (pre-Phase-11 only)](#76-testflight-rollout-plan)
77. [Sandbox vs prod — SCOPE REDUCED](#77-sandbox-vs-prod)
78. [Data model / ERD](#78-data-model-erd)
79. [Multi-tenant user session mgmt — SCOPE REDUCED](#79-multi-tenant-user-session-mgmt)
80. [Master design-token table](#80-master-design-token-table)
81. [API endpoint catalog (abridged, full lives in `docs/api.md`)](#81-api-endpoint-catalog-abridged-full-lives-in-docsapimd)
82. [Phase Definition of Done (sharper, supersedes legacy §79 Phase DoD skeleton)](#82-phase-definition-of-done-sharper-supersedes-legacy-79-phase-dod-skeleton)
83. [Wireframe ASCII sketches per screen](#83-wireframe-ascii-sketches-per-screen)
84. [Android ↔ iOS parity table](#84-android-ios-parity-table)
85. [Web ↔ iOS parity table](#85-web-ios-parity-table)
86. [Server capability map](#86-server-capability-map)
87. [DB schema ERD (text)](#87-db-schema-erd-text)
88. [State diagrams per entity](#88-state-diagrams-per-entity)
89. [Architecture flowchart](#89-architecture-flowchart)
90. [STRIDE threat model (summary)](#90-stride-threat-model-summary)

---
## §1. Platform & Foundation

Baseline infra the rest of the app depends on. All of it ships before anything domain-specific claims parity.

> **Data-sovereignty principle (global).** The app has **exactly one network egress target**: `APIClient.baseURL`, the server the user entered at login (e.g. `bizarrecrm.com` or a self-hosted URL). **No third-party SDK may open a network socket** — no Sentry, Firebase, Mixpanel, Amplitude, Bugsnag, Crashlytics, Datadog, New Relic, FullStory, Segment, etc. Telemetry, crash reports, experiment assignments, heartbeats, and diagnostics all POST to the tenant server only. Apple's device-level crash reporting (opt-in per device) is the single exception. See §32 for enforcement (CI linter + privacy manifest audit).

### 1.1 API client & envelope
- [x] `APIClient` with dynamic base URL (`APIClient.setBaseURL`) — shipped.
- [x] `{ success, data, message }` envelope decoder — shipped.
- [x] Bearer-token injection from Keychain — shipped.
- [x] **Token refresh on 401 with retry-of-original-request.** (`Networking/APIClient.swift` `performOnce` + `refreshSessionOnce()` single-flight `Task<Bool,Error>`; concurrent 401s queue behind same task; `AuthSessionRefresher` protocol wired via `AuthRefresher.swift`; failure posts `SessionEvents.sessionRevoked`.)
- [ ] **Typed endpoint namespaces** — migrate each repository to an `Endpoint` enum (`Endpoints.Tickets.list(page:filter:)`) so path strings are not scattered across files.
- [ ] **Multipart upload helper** (`APIClient.upload(_:to:fields:)`) for photos, receipts, avatars. Must use a background `URLSession` configuration so uploads survive app exit.
- [ ] **Retries with jitter** on transient network failures (5xx, URLError `.timedOut`, `.networkConnectionLost`). Respect `Retry-After` on 429.
- [x] **Offline detection banner** driven by `NWPathMonitor` — sticky `.brandGlass` banner at the top of `NavigationStack`s with "Offline — changes will sync when connected" copy. (`Networking/Reachability.swift` + `DesignSystem/OfflineBanner.swift`. Retry button deferred.)

### 1.2 Pinning & TLS
- [x] `PinnedURLSessionDelegate` scaffold — shipped (empty pin set).
- [ ] Decision: leave pins empty for Let's Encrypt on `bizarrecrm.com`, or pin to Let's Encrypt intermediates. Document decision in README and toggle per-build-config.
- [ ] Custom-server override (self-hosted tenants): allow user-trusted pins per base URL, stored encrypted in Keychain.

### 1.3 Persistence (GRDB + SQLCipher)

Works in lockstep with §20 Offline, Sync & Caching — both are Phase 0 foundation. This subsection covers the storage layer; §20 covers the repository pattern, sync queue, cursor pagination, and conflict resolution that sit on top of it. Domain PRs must use both; neither ships in isolation.

- [~] GRDB wiring exists for some domains; full coverage missing.
- [~] **Per-domain DAO**: partial — Tickets (`TicketRepository` + `TicketSyncHandlers`), Customers (`CustomerRepository` + `CustomerSyncHandlers`), Inventory (`InventoryRepository` + `InventorySyncHandlers`) wired. Invoices (`InvoiceRepository`), Leads (`LeadListView` via `LeadsEndpoints`) present without full GRDB layer. Appointments, Expenses, SMS, Notifications, Employees, Reports cache still missing.
- [x] **`sync_state` table** (§20.5) — keyed by `(entity, filter?, parent_id?)` storing cursor + `oldestCachedAt` + `serverExhaustedAt?` + `lastUpdatedAt`. (`Persistence/SyncStateStore.swift`, migration `002_sync_state_and_queue.sql`)
- [x] **`sync_queue` table** (§20.2) — optimistic-write log feeding the drain loop. (`Persistence/SyncQueueStore.swift`; migration `002_sync_state_and_queue.sql`; `SyncFlusher` drain loop wired.)
- [x] **Migrations registry** — numbered migrations, each one idempotent. (`Persistence/Migrator.swift` loads sorted `.sql` files from bundle; migrations 001–005 shipped.)
- [ ] **`updated_at` bookkeeping** — every table records `updated_at` + `_synced_at`, so delta sync can ask `?since=<last_synced>`.
- [ ] **Encryption passphrase** — 32-byte random on first run, stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- [ ] **Export / backup** — developer-only for now: `Settings → Diagnostics → Export DB` writes a zipped snapshot (without passphrase) to the share sheet.

### 1.4 Design System & Liquid Glass
- [x] `GlassKit.swift` wrapper — shipped.
- [ ] **On-device verification** that iOS 26 `.glassEffect` renders the real refraction (not the `.ultraThinMaterial` fallback).
- [ ] **`GlassEffectContainer`** usage audit — wherever two glass elements might overlap, wrap them in a container so they blend, not stack.
- [ ] **`brandGlassProminent` / `brandGlass` / `brandGlassClear`** variants mapped to button styles, capsule badges, card toolbars.
- [ ] Reduce Transparency fallback: pure `.brandSurfaceElevated` fill instead of glass.
- [ ] Max 6 glass elements per screen. Enforce via debug-build assertion inside `BrandGlassModifier` + SwiftLint rule counting `.brandGlass` call sites per View body. No runtime overlay — violations trip `assert(glassBudget < 6)` and CI lint fails. Zero production cost.

### 1.5 Navigation shell
- [x] iPhone `TabView` + iPad `NavigationSplitView` scaffold — shipped.
- [ ] **Typed path enum** per tab — `TicketsRoute.list | .detail(TicketID) | .create | .edit(TicketID)`. Deep-link router consumes these enums.
- [ ] **Tab customization** (iPhone): user-reorderable tabs; fifth tab becomes "More" overflow.
- [ ] **Search tab role** (iOS 26): adopt `TabRole.search` so the tab bar renders it correctly.
- [ ] **Swipe-back gesture** preserved everywhere — no custom back buttons in `NavigationStack`.
- [ ] **Deep links**: `bizarrecrm://tickets/:id`, `/customers/:id`, `/invoices/:id`, `/sms/:thread`, `/dashboard`. Mirror Android intent filters.
- [ ] **Universal Links** over `app.bizarrecrm.com/*` — apple-app-site-association published server-side.

### 1.6 Environment & config
- [x] `project.yml` + `xcodegen` + `write-info-plist.sh` — shipped.
- [ ] **`Info.plist` key audit** — drop empty `UISceneDelegateClassName` (removes console noise).
- [ ] `ITSAppUsesNonExemptEncryption = false` (HTTPS is exempt).
- [ ] Required usage-description strings: Camera, Photos, Photos-add, FaceID, Bluetooth, Contacts, Location-when-in-use (tech dispatch), Microphone (SMS voice memo — optional), Calendars (EventKit appointments mirror).
- [ ] `UIBackgroundModes`: `remote-notification`, `processing`, `fetch`.
- [ ] `UIAppFonts` list kept in sync with `scripts/fetch-fonts.sh` and `BrandFonts.swift`.
- [x] `GRDB.DatabaseMigrator` with named migrations in `Packages/Persistence/Sources/Persistence/Migrations/` — immutable once shipped. (`Persistence/Migrator.swift` loads sorted `.sql` files from bundle; migrations 001–005 registered.)
- [ ] Migration-tracking table records applied names; app refuses to launch if a known migration is missing.
- [ ] Forward-only (no downgrades). Reverted iOS version → "Database newer than app — contact support".
- [ ] Large migrations split into batches; progress sheet "Migrating 50%"; runs in `BGProcessingTask` so user can leave app.
- [ ] Backup-before-migrate: copy SQLCipher file to `~/Library/Caches/pre-migration-<date>.db`; keep 7d or until next successful launch.
- [ ] Debug builds: dry-run migration on backup first and report diff before apply.
- [ ] CI runs every migration against minimal + large fixture DBs (§31 fixtures).
- [ ] Factory DI with `Container` + `@Injected(\.apiClient)` key style. All services registered in `Container+Registrations.swift` at launch.
- [ ] Scopes: `cached` (process-wide: APIClient / DB / Keychain), `shared` (weak per-object-graph: ViewModels), `unique` (each resolve builds fresh).
- [ ] Test doubles: test bundle swaps registrations via `Container.mock { ... }` per test; no global-state leaks (assertions in `setUp`).
- [ ] SwiftLint rule bans `static shared = ...` except for `Container` itself.
- [ ] Widgets / App Intents targets import `Core` + register their own Container sub-scope.
- [ ] `AppError` enum with cases: `.network(Underlying)`, `.server(status, message, requestID)`, `.auth(AuthReason)`, `.validation([FieldError])`, `.notFound(entity, id)`, `.permission(required: Capability)`, `.conflict(ConflictInfo)`, `.storage(StorageReason)`, `.hardware(HardwareReason)`, `.cancelled`, `.unknown(Error)`.
- [ ] Each case exposes `title`, `message`, `suggestedActions: [AppErrorAction]` (retry / open-settings / contact-support / dismiss).
- [ ] Errors logged with category + code + request ID; no PII per §32.6 Redactor.
- [ ] User-facing strings in `Localizable.strings` (§27 / §64).
- [ ] Error-recovery UI per taxonomy case lives in each feature module; patterns consolidated in §63-equivalent (dropped — handled inline per screen).
- [ ] `UndoManager` attached per scene; each editable action registers undo via `UndoManager.registerUndo(withTarget:handler:)`
- [ ] Covered actions: ticket field edit; POS cart item add/remove; inventory adjust; customer field edit; status change; notes add/remove
- [ ] Undo trigger: ⌘Z on iPad hardware keyboard; iPhone `.accessibilityAction(.undo)` + shake-to-undo if enabled; context-menu button for non-keyboard users
- [ ] Server sync: undo rolls back optimistic change, sends compensating request if already synced; if undo impossible, toast "Can't undo — action already processed"
- [ ] Redo: ⌘⇧Z
- [ ] Stack depth last 50 actions; cleared on scene dismiss
- [ ] Audit integration: each undo creates an audit entry (not silent)
- [ ] Launch: `applicationDidFinishLaunching` → register Factory Container, read feature flags from Keychain cache; `scene(_:willConnectTo:)` → resolve last-tenant, attempt token refresh in background
- [ ] Foreground: `willEnterForeground` → kick delta-sync, refresh push token, update "last seen" ping; resume paused animations; restart `CHHapticEngine`; re-evaluate lock-screen gate (biometric required if inactive >15min)
- [ ] Background: `didEnterBackground` → persist unsaved drafts; schedule BG tasks; seal pasteboard if sensitive; blur root for screen-capture privacy
- [ ] Terminate rarely invoked; don't rely on — persist state on every change, not at terminate
- [ ] Memory warning: `didReceiveMemoryWarning` → flush Nuke memory cache, drop preview caches; never free active data
- [ ] Scene disconnect: save scene state to disk via `NSUserActivity`
- [ ] URL open / universal link: handle in `scene(_:openURLContexts:)` / `scene(_:continue:)`; route through central DeepLinkRouter (§65)
- [ ] Push delivery in foreground: `UNUserNotificationCenterDelegate.willPresent` decides banner/sound/badge; SMS_INBOUND shows banner but not sound if user already in SMS thread for that contact
- [ ] Push background: `didReceive` handles action buttons (Reply / Mark Read) inline
- [ ] Silent push: `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` triggers delta-sync; call handler within 30s
- [ ] Choice: GRDB + SQLCipher (encryption-at-rest mandatory; SwiftData lacks native encryption); GRDB has mature FTS5 bindings for §18 search; GRDB concurrency (DatabasePool) matches heavy-read-light-write load; CloudKit not desired (§32 sovereignty)
- [ ] SwiftData tradeoffs captured: pro = SwiftUI bindings, less ceremony; con = no encryption, iOS 17+ floor; decision = GRDB for now, revisit when SwiftData adds SQLCipher
- [ ] Migration (if ever switch): export GRDB → SwiftData via CSV/JSON intermediary; not planned
- [ ] Concurrency: GRDB actors per repository; read pool size 10; write queue serialized
- [ ] Observation: GRDB `ValueObservation` bridges into `AsyncSequence` for SwiftUI
- [ ] Detection: on startup + every sync, compare device clock to server time; flag drift > 2 min.
- [ ] User warning banner when drifted: "Device clock off by X minutes — may cause login issues" + suggest auto-time on.
- [ ] TOTP gate: 2FA fails if drift > 30s; auto-retry once with adjusted window, then hard error.
- [ ] Timestamp logging: all client timestamps include UTC offset; server stamps its own time; audit uses server time as authoritative.
- [ ] Offline timer: record both device time + offline duration on sync-pending ops so server can reconcile.
- [ ] Purpose: protect server from accidental client storm (over-scroll fetch); improve UX on flaky networks.
- [ ] Impl: token-bucket per endpoint category — read 60/min, write 20/min; excess requests queued with backoff.
- [ ] Honor server hints: `Retry-After`, `X-RateLimit-Remaining`; pause client on near-limit signal.
- [ ] UI: silent unless sustained; show "Slow down" banner if queue > 10.
- [ ] Debug drawer exposes current bucket state per endpoint.
- [ ] Exemptions: auth + offline-queue flush not client-limited (server-side limits instead).
- [ ] Auto-save drafts every 2s to SQLCipher for ticket-create, customer-create, SMS-compose; never lost on crash/background.
- [ ] Recovery prompt on next launch or screen open: "You have an unfinished <type> — Resume / Discard" sheet with preview.
- [ ] Age indicator on draft ("Saved 3h ago").
- [ ] One draft per type (not multi); explicit discard required before starting new.
- [ ] Sensitive: drafts encrypted at rest; PIN/password fields never drafted.
- [ ] Drafts stay on device (no cross-device sync — avoid confusion).
- [ ] Auto-delete drafts older than 30 days.

---
## §2. Authentication & Onboarding

_Server endpoints: `GET /auth/setup-status`, `POST /auth/setup`, `POST /auth/login`, `POST /auth/login/set-password`, `POST /auth/login/2fa-setup`, `POST /auth/login/2fa-verify`, `POST /auth/login/2fa-backup`, `POST /auth/refresh`, `POST /auth/logout`, `GET /auth/me`, `POST /auth/forgot-password`, `POST /auth/reset-password`, `POST /auth/recover-with-backup-code`, `POST /auth/verify-pin`, `POST /auth/switch-user`, `POST /auth/change-password`, `POST /auth/change-pin`, `POST /auth/account/2fa/disable`._

### 2.1 Setup-status probe
- [ ] **Backend:** `GET /auth/setup-status` returns `{ needsSetup, isMultiTenant }`. On first launch after server URL entry, iOS hits this before rendering the login form.
- [ ] **Frontend:** if `needsSetup` → push `InitialSetupFlow` (see 2.10). If `isMultiTenant` + no tenant chosen → push tenant picker. Else → render login.
- [ ] **Expected UX:** transparent to user; ≤400ms overlay spinner with `.brandGlass` background and a "Connecting to your server…" label. Fail → inline retry on login screen.

### 2.2 Login — username + password (step 1)
- [x] Username + password form, dynamic server URL, token storage — shipped.
- [ ] **Response branches** `POST /auth/login` returns any of:
  - `{ challengeToken, requiresFirstTimePassword: true }` → push SetPassword step.
  - `{ challengeToken, totpEnabled: true }` → push 2FA step.
  - `{ accessToken, user }` → happy path.
- [ ] **Username not email** — server uses `username`, mirror that label. Support `@email` login fallback if server accepts it.
- [ ] **Keyboard flow** — `.submitLabel(.next)` on username, `.submitLabel(.go)` on password; `@FocusState` auto-advance.
- [ ] **"Show password" eye toggle** with `privacySensitive()` on the field.
- [ ] **Remember-me toggle** persists username in `UserDefaults` (see user memory: phone format) + flag to surface biometric prompt next launch.
- [ ] **Form validation** — primary CTA disabled until both fields non-empty; inline error on server 401 ("Username or password incorrect.").
- [ ] **Rate-limit handling** — server throttles IP (5/15min) and username (10/30min); surface "Too many attempts. Wait N minutes." glass banner with countdown.
- [ ] **Trust-this-device** checkbox on 2FA step → server flag `trustDevice: true`.

### 2.3 First-time password set
- [x] **Endpoint:** `POST /auth/login/set-password` with `{ challengeToken, password }`.
- [x] **Frontend:** password + confirm fields, strength meter (length, mixed-case, digit, symbol, not-in-breach-list via local dictionary), CTA disabled until rules pass.
- [x] **UX:** glass panel titled "Set your password to continue"; subtitle "Your admin requested a reset".

### 2.4 2FA / TOTP
- [x] **Enroll during login** — `POST /auth/login/2fa-setup` → `{ qr, secret, manualEntry, challengeToken }`. Render QR (CoreImage `CIFilter.qrCodeGenerator`) + copyable secret with `.textSelection(.enabled)`. Detect installed authenticator apps via `otpauth://` URL scheme.
- [x] **Verify code** — `POST /auth/login/2fa-verify` with `{ challengeToken, code, trustDevice? }` returns `{ accessToken, user }`.
- [x] **Backup code entry** — `POST /auth/login/2fa-backup` with `{ challengeToken, backupCode }`.
- [x] **Backup codes display** (post-enroll) — show full list once, copy-all button, "I saved them" confirm. Warn loss = lockout.
- [x] **Autofill OTP** — `.textContentType(.oneTimeCode)` on the 6-digit field picks up SMS codes from Messages.
- [ ] **Paste-from-clipboard** auto-detect 6-digit string.
- [ ] **Disable 2FA** (Settings → Security) — `POST /auth/account/2fa/disable` with `{ password?, code? }`.

### 2.5 PIN lock
- [x] **Set PIN** first launch after login — 4–6 digit numeric; SHA-256 hash mirror in Keychain (Argon2id follow-up tracked).
- [x] **Verify PIN** — local via `PINStore.verify(pin:) -> VerifyResult`; server-side mirror deferred.
- [ ] **Change PIN** — Settings → Security; `POST /auth/change-pin` with `{ currentPin, newPin }`.
- [ ] **Switch user** (shared device) — `POST /auth/switch-user` with `{ pin }` → `{ accessToken, user }`. Expose as "Switch user" row on Settings & long-press on avatar in toolbar.
- [ ] **Lock triggers** — cold start, background for N minutes (Settings: 0/1/5/15/never), explicit "Lock now" action.
- [x] **Keypad UX** — custom numeric keypad with haptic on each tap, 6-dot status, escalating lockout (5→30s, 6→1m, 7→5m, 8→15m, 9→1h, 10→revoke+wipe).
- [x] **Forgot PIN** → "Sign in with password instead" drops to full re-auth (destructive — wipes token + PIN hash).
- [x] **iPad layout** — keypad centered in `.brandGlass` card, max-width 420, not full-width.

### 2.6 Biometric (Face ID / Touch ID / Optic ID)
- [ ] **Info.plist:** `NSFaceIDUsageDescription = "Unlock BizarreCRM with Face ID"`.
- [x] **Enable toggle** — login-offer step persists via `BiometricPreference`. Settings toggle follow-up.
- [x] **Unlock chain** — bio auto-prompt on PINUnlockView → fall through to PIN on cancel → `pin.reauth` on revoke.
- [ ] **Login-time biometric** — if "Remember me" + biometric enabled, decrypt stored credentials via `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` and auto-POST `/auth/login`.
- [x] **Respect disabled biometry** gracefully — `BiometricGate.isAvailable` + `kind` guards every call; PIN keypad stays available.
- [ ] **Re-enroll prompt** — `LAContext.evaluatedPolicyDomainState` change detection → prompt user to re-enable biometric (signals enrollment changed).

### 2.7 Signup / tenant creation (multi-tenant SaaS)
- [ ] **Endpoint:** `POST /auth/setup` with `{ username, password, email?, first_name?, last_name?, store_name?, setup_token? }` (rate limited 3/hour).
- [ ] **Frontend:** multi-step glass panel — Company (name, phone, address, timezone, shop type) → Owner (name, email, username, password) → Server URL (self-hosted vs managed) → Confirm & sign in.
- [ ] **Auto-login** — if server returns `accessToken` in setup response, skip login; else POST `/auth/login`. Verify server side (root TODO `SIGNUP-AUTO-LOGIN-TOKENS`).
- [ ] **Timezone picker** — pre-selects device TZ (`TimeZone.current.identifier`).
- [ ] **Shop type** — repair / retail / hybrid / other; drives defaults in Setup Wizard (see §36).
- [ ] **Setup token** (staff invite link) — captured from Universal Link `bizarrecrm.com/setup/:token`, passed on body.

### 2.8 Forgot password + recovery
- [ ] **Request reset** — `POST /auth/forgot-password` with `{ email }`.
- [ ] **Complete reset** — `POST /auth/reset-password` with `{ token, password }`, reached via Universal Link `app.bizarrecrm.com/reset-password/:token`.
- [ ] **Backup-code recovery** — `POST /auth/recover-with-backup-code` with `{ username, password, backupCode }` → `{ recoveryToken }` → SetPassword step.
- [ ] **Expired / used token** → server 410 → "This reset link expired. Request a new one." CTA.

### 2.9 Change password (in-app)
- [ ] **Endpoint:** `POST /auth/change-password` with `{ currentPassword, newPassword }`.
- [ ] **Settings → Security** row; confirm + strength meter; success toast + force logout of other sessions option.

### 2.10 Initial setup wizard — first-run (see §36 for full scope)
- [ ] Triggered when `GET /auth/setup-status` → `{ needsSetup: true }`. Stand up a 13-step wizard mirroring web (/setup).

### 2.11 Session management
- [x] 401 auto-logout via `SessionEvents` — shipped.
- [x] **Refresh-and-retry** on 401 — single-flight `Task<Bool, Error>` in `APIClient.refreshSessionOnce()`; concurrent 401s await the same task, retry replays with the new bearer, refresh failure posts `SessionEvents.sessionRevoked`.
- [ ] **`GET /auth/me`** on cold-start — validates token + loads current role/permissions into `AppState`.
- [x] **Logout** — `POST /auth/logout` via `APIClient.logout()`; best-effort server call + local wipe (TokenStore + PINStore + BiometricPreference + bearer); optional ServerURLStore clear via Settings → "Change shop".
- [ ] **Active sessions** (stretch) — if server exposes session list.
- [ ] **Session-revoked banner** — glass banner "Signed out — session was revoked on another device." with reason from `message`.

### 2.12 Error / empty states
- [ ] Wrong password → inline error + shake animation + `.error` haptic.
- [ ] Account locked (423) → modal "Contact your admin." + support deep link. Email pulled from tenant config (`GET /tenants/me/support-contact` → `{ email, phone?, hours? }`), NOT hardcoded. Self-hosted tenants return their own admin; the bizarrecrm.com-hosted tenant returns `pavel@bizarreelectronics.com`. Fallback if endpoint missing: render "Contact your admin" with no `mailto:` button rather than a wrong address.
- [ ] Wrong server URL / unreachable → inline "Can't reach this server. Check the address." + retry CTA.
- [ ] Rate-limit 429 → glass banner with human-readable countdown (parse `Retry-After`).
- [ ] Network offline during login → "You're offline. Connect to sign in." (can't bypass; auth is online-only).
- [ ] TLS pin failure → red glass alert "This server's certificate doesn't match the pinned certificate. Contact your admin." (non-dismissable).

### 2.13 Security polish
- [ ] `privacySensitive()` + `.redacted(reason: .privacy)` on password field when app backgrounds.
- [ ] Blur overlay on screenshot capture on 2FA + password screens (`UIScreen.capturedDidChange`).
- [ ] Pasteboard clears OTP after 30s (`UIPasteboard.general.expirationDate`).
- [ ] OSLog never prints `password`, `accessToken`, `refreshToken`, `pin`, `backupCode`.
- [ ] Challenge token expires silently after 10min → prompt restart login.
- [ ] Use case: counter iPad used by 3 cashiers
- [ ] Enable at Settings → Shared Device Mode
- [ ] Requires device passcode + management PIN to enable/disable
- [ ] Session swap: Lock screen → "Switch user" → PIN
- [ ] Token swap; no full re-auth unless inactive > 4h
- [ ] Auto-logoff: inactivity > 10 min (tenant-configurable) returns to user-picker
- [ ] Per-user drafts isolated
- [ ] Current POS cart bound to current user; user switch holds cart (park)
- [ ] Staff list: pre-populated quick-pick grid of staff avatars; tap avatar → PIN entry
- [ ] Shared-device mode hides biometric (avoid confusion)
- [ ] Keychain scoped per staff via App Group entries
- [ ] PIN setup: staff enters 4-6 digit PIN during onboarding
- [ ] Stored as Argon2id hash in Keychain; salt per user
- [ ] Quick-switch UX: large number pad on lock screen
- [ ] Haptic on each digit
- [ ] Wrong PIN: shake + 3 attempts then 30s lockout + 60s / 5min escalation
- [ ] Recovery: forgot PIN → email reset link to tenant-registered email
- [ ] Manager override: manager can reset staff PIN
- [ ] Mandatory PIN rotation: optional tenant setting, every 90d
- [ ] Blocklist common PINs (1234, 0000, birthday)
- [ ] Digits shown as dots after entry
- [ ] "Show" tap-hold reveals briefly
- [ ] Threshold: inactive > 15m → require biometric re-auth
- [ ] Threshold: inactive > 4h → require full password
- [ ] Threshold: inactive > 30d → force full re-auth including email
- [ ] Activity signals: user touches, scroll, text entry
- [ ] Activity exclusions: silent push, background sync don't count
- [ ] Warning: 60s before forced timeout overlay "Still there?" with Stay / Sign out buttons
- [ ] Countdown ring visible during warning
- [ ] Sensitive screens force re-auth: Payment / Settings → Billing / Danger Zone → immediate biometric prompt regardless of timeout
- [ ] Tenant-configurable thresholds with min values enforced globally (cannot be infinite)
- [ ] Max threshold 30d
- [ ] Sovereignty: no server-side idle detection; purely device-local
- [ ] Scope: remember email only (never password without biometric bind)
- [ ] Biometric-unlock stores passphrase in Keychain under Face-ID-gated item
- [ ] Device binding: stored creds tied to device class ID
- [ ] If user migrates device, re-auth required
- [ ] Device binding blocks credential theft via backup export
- [ ] Remember applies per tenant
- [ ] Revocation: logout clears stored creds
- [ ] Server-side revoke clears on next sync
- [ ] A11y: Assistive-Access mode defaults remember on to reduce re-auth friction
- [ ] Required for owner + manager + admin roles; optional for others
- [ ] Factor type TOTP: default; scan QR with Authenticator / 1Password
- [ ] Factor type SMS: fallback only; discouraged (SIM swap risk)
- [ ] Factor type hardware key (FIDO2 / Passkey): recommended for owners
- [ ] Factor type biometric-backed passkey: iOS 17+ via iCloud Keychain
- [ ] Enrollment flow: Settings → Security → Enable 2FA
- [ ] Generates secret → displays QR + manual code
- [ ] User scans with Authenticator
- [ ] Verify via entering current 6-digit code
- [ ] Save recovery codes at enrollment
- [ ] Back-up factor required: ≥ 2 factors minimum (TOTP + recovery codes)
- [ ] Disable flow: requires current factor + password + email confirm link
- [ ] Passkey preference: iOS 17+ promotes passkey over TOTP as primary
- [ ] Generate 10 codes, 10-char base32 each
- [ ] Generated at enrollment; copyable / printable
- [ ] One-time use per code
- [ ] Not stored on device (user's responsibility)
- [ ] Server stores hashes only
- [ ] Display: reveal once with warning "Save these — they won't show again"
- [ ] Print + email-to-self options
- [ ] Regeneration at Settings → Security → Regenerate codes (invalidates previous)
- [ ] Usage: Login 2FA prompt has "Use recovery code" link
- [ ] Entering recovery code logs in + flags account (email sent to alert)
- [ ] Admin override: tenant owner can reset staff recovery codes after verifying identity
- [ ] Providers: Okta, Azure AD, Google Workspace, JumpCloud
- [ ] SAML 2.0 primary; OIDC for newer
- [ ] Setup: tenant admin (web only) pastes IdP metadata
- [ ] Certificate rotation notifications
- [ ] iOS flow: Login screen "Sign in with SSO" button
- [ ] Opens `ASWebAuthenticationSession` → IdP login → callback
- [ ] Token exchange with tenant server
- [ ] SCIM (stretch, Phase 5+): user provisioning via SCIM feed from IdP; auto-create/disable BizarreCRM accounts
- [ ] Hybrid: some users via SSO, others local auth
- [ ] Login screen auto-detects based on email domain
- [ ] Breakglass: tenant owner retains local password if IdP down
- [ ] Sovereignty: IdP external by nature; per-tenant consent; documented in privacy notice
- [ ] No third-party IdP tokens stored beyond session lifetime
- [ ] Login screen "Email me a link" → enter email → server emails link
- [ ] Universal Link opens app on tap; auto-exchange for token
- [ ] Link lifetime 15min, one-time use
- [ ] Device binding: same-device fingerprint required
- [ ] Cross-device triggers 2FA confirm
- [ ] Tenant can disable magic links (strict security mode)
- [ ] Phishing defense: link preview shows tenant name explicitly
- [ ] Domain pinned to `app.bizarrecrm.com`
- [ ] iOS 17+ passkeys via `ASAuthorizationController` + `ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest`
- [ ] iCloud Keychain cross-Apple-device sync
- [ ] Enrollment: Settings → Security → Add passkey → Face ID / Touch ID confirm
- [ ] Store credential with tenant server (FIDO2)
- [ ] Login screen "Use passkey" button with system UI prompt (no password typed)
- [ ] Password remains as breakglass fallback
- [ ] Can remove password once passkey + recovery codes set
- [ ] Cross-device: passkey syncs to iPad / Mac via iCloud
- [ ] Android coworker stays on password (no cross-OS passkey sync yet)
- [ ] Recovery via §2 recovery codes when all Apple devices lost
- [ ] YubiKey 5C (USB-C) plugs into iPad; triggers passkey flow
- [ ] Targeted at shared iPad without individual iCloud
- [ ] NFC YubiKey tap on iPad Pro 13" 2024 (NFC) for NFC auth
- [ ] Security levels: owners recommended hardware key; staff optional
- [ ] Settings → Security → Hardware keys → "Register YubiKey"
- [ ] Key management: list + last-used + revoke
- [ ] Tenant policy can require attested hardware
- [ ] See §1 for the full list.

---
## §3. Dashboard & Home

_Server endpoints: `GET /reports/dashboard`, `GET /reports/dashboard-kpis`, `GET /reports/aging`, `GET /tickets/my-queue`, `GET /inbox`, `GET /sms/unread-count`, `GET /notifications`._

### 3.1 KPI grid
- [x] Base KPI grid + Needs-attention — shipped.
- [ ] **Tiles** mirror web: Sales today, Tax, Discounts, COGS, Net profit, Refunds, Expenses, Receivables, Open tickets, Appointments today, Low-stock count, Closed today.
- [ ] **Tile taps** deep-link to the filtered list (e.g., Open tickets → Tickets filtered `status_group=open`; Low-stock → Inventory filtered `low_stock=true`).
- [ ] **Date-range selector** — presets (Today / Yesterday / Last 7 / This month / Last month / This year / All-time / Custom); persists per user in `UserDefaults`; sync to server-side default.
- [ ] **Previous-period compare** — green ▲ / red ▼ delta badge per tile; driven by server diff field or client subtraction from cached prior value.
- [ ] **Pull-to-refresh** via `.refreshable`.
- [ ] **Skeleton loaders** — glass shimmer ≤300ms; cached value rendered immediately if present.
- [ ] **iPhone**: 2-column grid. **iPad**: 3-column ≥768pt wide, 4-column ≥1100pt, capped at 1200pt content width. **Mac**: 4-column.
- [ ] **Customization sheet** — long-press a tile → "Hide tile" / "Reorder tiles"; persisted in `UserDefaults`.
- [ ] **Empty state** (new tenant) — illustration + "Create your first ticket" + "Import data" CTAs.

### 3.2 Business-intelligence widgets (mirror web)
- [ ] **Profit Hero card** — giant net-margin % with trend sparkline (`Charts`).
- [ ] **Busy Hours heatmap** — ticket volume × hour-of-day × day-of-week; `Chart { RectangleMark(...) }`.
- [ ] **Tech Leaderboard** — top 5 by tickets / revenue; tap row → employee detail.
- [ ] **Repeat-customers** card — repeat-rate %.
- [ ] **Cash-Trapped** card — overdue receivables sum; tap → Aging report.
- [ ] **Churn Alert** — at-risk customer count; tap → Customers filtered `churn_risk`.
- [ ] **Forecast chart** — projected revenue (`LineMark` with confidence band).
- [ ] **Missing parts alert** — parts with low stock blocking open tickets; tap → Inventory filtered to affected items.

### 3.3 Needs-attention surface
- [x] Base card — shipped.
- [ ] **Row-level chips** — "View ticket", "SMS customer", "Mark resolved", "Snooze 4h / tomorrow / next week".
- [ ] **Swipe actions** (iPhone): leading = snooze, trailing = dismiss; haptic `.selection` on dismiss.
- [ ] **Context menu** (iPad/Mac) with all row actions + "Copy ID".
- [ ] **Dismiss persistence** — server-backed `POST /notifications/:id/dismiss` + local GRDB mirror so it stays dismissed across devices.
- [ ] **Empty state** — "All clear. Nothing needs your attention." + small sparkle illustration.

### 3.4 My Queue (assigned tickets, per user)
- [ ] **Endpoint:** `GET /tickets/my-queue` — assigned-to-me tickets, auto-refresh every 30s while foregrounded (mirror web).
- [ ] **Always visible to every signed-in user.** "Assigned to me" is a universally useful convenience view — not gated by role or tenant flag. Shown on the dashboard for admins, managers, techs, cashiers alike.
- [ ] **Separate from tenant-wide visibility.** Two orthogonal controls:
  - **Tenant-level setting `ticket_all_employees_view_all`** (Settings → Tickets → Visibility). Controls what non-manager roles see in the **full Tickets list** (§4): `0` = own tickets only; `1` = all tickets in their location(s). Admin + manager always see all regardless.
  - **My Queue section** (this subsection) stays on the dashboard for everyone; it is a per-user shortcut, never affected by the tenant setting.
- [ ] **Per-user preference toggle** in My Queue header: `Mine` / `Mine + team` (team = same location + same role). Server returns appropriate set; if tenant flag blocks "team" for this role, toggle is disabled with tooltip "Your shop has limited visibility — ask an admin."
- [ ] **Row**: Order ID + customer avatar + name + status chip + age badge (red >14d / amber 7–14 / yellow 3–7 / gray <3) + due-date badge (red overdue / amber today / yellow ≤2d / gray later).
- [ ] **Sort** — due date ASC, then age DESC.
- [ ] **Tap** → ticket detail.
- [ ] **Quick actions** (swipe or context menu): Start work, Mark ready, Complete.

### 3.5 Getting-started / onboarding checklist
- [ ] **Backend:** `GET /account` + `GET /setup/progress` (verify). Checklist items: create first customer, create first ticket, record first payment, invite employee, configure SMS, print first receipt, etc.
- [ ] **Frontend:** collapsible glass card at top of dashboard — progress bar + remaining steps. Dismissible once 100% complete.
- [ ] **Celebratory modal** — first sale / first customer / setup complete → confetti `Symbol Animation` + copy.

### 3.6 Recent activity feed
- [ ] **Backend:** `GET /activity?limit=20` (verify) — fall back to stitched union of tickets/invoices/sms `updated_at` if missing.
- [ ] **Frontend:** chronological list under KPI grid (collapsible). Icon per event type; tap → deep link.

### 3.7 Announcements / what's new
- [ ] **Backend:** `GET /system/announcements?since=<last_seen>` (verify).
- [ ] **Frontend:** sticky glass banner above KPI grid. Tap → full-screen reader. "Dismiss" persists last-seen ID in `UserDefaults`.

### 3.8 Quick-action FAB / toolbar
- [ ] **iPhone:** floating `.brandGlassProminent` FAB, bottom-right (safe-area aware, avoids tab bar). Expands radially to: New ticket / New sale / New customer / Scan barcode / New SMS. Haptic `.medium` on expand. We want to be aware about liquid glass design standards here - android like FAB may not be the way to go, but need to research.
- [ ] **iPad/Mac:** toolbar group (`.toolbar { ToolbarItemGroup(...) }`) with the same actions — no FAB.
- [ ] **Keyboard shortcuts** (⌘N → New ticket; ⌘⇧N → New customer; ⌘⇧S → Scan; ⌘⇧M → New SMS).

### 3.9 Greeting + operator identity
- [x] **Dynamic greeting by hour** — `DashboardView.greeting` shows "Good morning/afternoon/evening" / "Working late" buckets. Commit `8f3f864`.
- [ ] Tap greeting → Settings → Profile. (Needs `/auth/me` for firstName; deferred.)
- [ ] Avatar in top-left (iPhone) / top-right of toolbar (iPad); long-press → Switch user (§2.5).

### 3.10 Sync-status badge
- [ ] Small glass pill on dashboard header: "Synced 2 min ago" / "Pending 3" / "Offline".
- [ ] Tap → Settings → Data → Sync Issues.

### 3.11 Clock in/out tile
- [x] **Big tile** — `ClockInOutTile` in `Packages/Timeclock` shows "Clock in" (idle) / "Clock out · HH:MM AM/PM + Nh Mm" (active). 30s tick, Reduce-Motion aware. Commit `d1d3392`.
- [x] **One-tap toggle + PIN** — `ClockInOutPinSheet` 4-digit entry; `POST /employees/:id/clock-in|out` with body `{ pin }`. `userId: 0` placeholder pending `/auth/me`.
- [x] **Success haptic + toast** — `BrandHaptics.success()` + 2.5s toast on state transition.

### 3.12 Unread-SMS / team-inbox tile
- [ ] `GET /sms/unread-count` drives a small pill badge; tap → SMS tab.
- [ ] `GET /inbox` count → Team Inbox tile (if tenant has team inbox enabled).

### 3.13 TV / queue board (iPad only, stretch)
- [ ] Full-screen marketing / queue-board mode that mirrors web `/tv`. Launched from Settings → Display → Activate queue board.
- [ ] Read-only, auto-refresh, stays awake (`UIApplication.shared.isIdleTimerDisabled = true`).
- [ ] Exit via 3-finger tap + PIN.

### 3.14 Empty / error states
- [ ] Network fail → keep cached KPIs + sticky glass banner "Showing cached data. Retry.".
- [ ] Zero data → illustrations differ per card (no tickets vs no revenue vs no customers).
- [ ] Permission-gated tile → greyed out with lock glyph + "Ask your admin to enable Reports for your role.".
- [ ] Brand-new tenants with zero data must not feel broken; every screen needs empty-state design
- [ ] Dashboard: KPIs "No data yet" link to onboarding action; central card "Let's set up your shop — 5 steps remaining" links to Setup Wizard (§36)
- [ ] Tickets empty: SF Symbol wrench+glow illustration; CTA "Create your first ticket"; sub-link "Or import from old system" (§48)
- [ ] Inventory empty: CTA "Add your first product" or "Import catalog (CSV)"; starter templates (Phone/Laptop/TV repair) seed ~20 common items
- [ ] Customers empty: CTA "Add first customer" or "Import from contacts" via `CNContactStore` with explicit explanation
- [ ] SMS empty: CTA "Connect SMS provider" → Settings § SMS
- [ ] POS empty: CTA "Connect BlockChyp" → Settings § Payment; "Cash-only POS" enabled by default (hardware-not-required mode)
- [ ] Reports empty: placeholder chart with "Come back after your first sale"
- [ ] Completion nudges: checklist ticks as steps complete; progress ring top-right of dashboard
- [ ] Sample data toggle in Setup Wizard loads demo tickets; clearly labeled demo; one-tap clear
- [ ] Trigger: on first app unlock of the day for staff role; gently suggests opening checklist
- [ ] Steps (customizable per tenant): open cash drawer, count starting cash; print last night's backup receipt; review pending tickets for today; check appointments list; check inventory low-stock alerts; power on hardware (printer/terminal) with app pinging status; unlock POS
- [ ] Hardware ping: ping each configured device (printer, terminal) with 2s timeout; green check or red cross per device; tap red → diagnostic page
- [ ] Completion: stored with timestamp per staff; optional post to team chat ("Morning!")
- [ ] Skip: user can skip; skipped state noted in audit log
- [ ] Real-time event stream (not an audit log; no diffs — social-feed style)
- [ ] Dashboard tile: compact last 5 events, expand to full feed
- [ ] Filters: team / location / event type / employee
- [ ] Tap event drills to entity
- [ ] Subtle reactions (thumbs / party / check) — not a social app
- [ ] Per-user notifications: "Notify me when X happens to my tickets"
- [ ] Privacy: no customer PII in feed text (IDs only)
- [ ] Infinite scroll with cursor-based pagination
- [ ] Tenant admin defines per-role tile templates
- [ ] Cashier default tiles: today sales / shift totals / quick actions
- [ ] Tech default tiles: my queue / my commission / tasks
- [ ] Manager default tiles: revenue / team perf / low stock
- [ ] User can reorder tiles within allowed set (drag-to-rearrange on iPad)
- [ ] Multiple named saved dashboards per user (e.g. "Morning", "End of day")
- [ ] Quick-switch between saved dashboards via tab
- [ ] Shared data plumbing with §24 widgets
- [ ] New users get curated minimal set; reveal advanced on demand
- [ ] Three modes: Comfortable (default iPhone, 1-2 col), Cozy (default iPad, 2-3 col), Compact (power user, 3-4 col smaller type).
- [ ] Per-user setting: Settings → Appearance → Dashboard density; optional iCloud Keychain sync (off on shared devices).
- [ ] Density token feeds spacing rhythm (ref §72.20); orthogonal to Reduce Motion.
- [ ] Live preview in settings (real dashboard) as user toggles.
- [ ] Pilot dashboard redesigns behind feature flag (§19) — entry surface risk is muscle-memory breakage.
- [ ] Opt-in path: owner enrolls first; sees new design 2 weeks before staff; inline feedback form.
- [ ] Rollout ramp 10% → 50% → 100% over 4 weeks, each phase gated on crash-free + feedback score.
- [ ] Kill-switch: flag instantly reverts.
- [ ] A/B metrics: task-completion time, tap counts, time-on-dashboard — measured on-device, aggregated to tenant server.
- [ ] Doc gate: before/after wireframes + rationale + success criteria.

---
## §4. Tickets (Service Jobs)

_Tickets are the largest surface — Android create screen is ~2109 LOC. Parity means creating a ticket on iPhone in under a minute with all the power of web. Server endpoints: `GET /tickets`, `GET /tickets/my-queue`, `GET /tickets/{id}`, `POST /tickets`, `PUT /tickets/{id}`, `DELETE /tickets/{id}`, `PATCH /tickets/{id}/status`, `POST /tickets/{id}/notes`, `POST /tickets/{id}/photos`, `POST /tickets/{id}/devices`, `PUT /tickets/devices/{deviceId}`, `POST /tickets/devices/{deviceId}/parts`, `PUT /tickets/devices/{deviceId}/checklist`, `POST /tickets/{id}/convert-to-invoice`, `GET /tickets/export`, `POST /tickets/bulk-action`, `GET /tickets/device-history`, `GET /tickets/warranty-lookup`, `GET /settings/statuses`._

### 4.1 List
- [x] Base list + filter chips + search — shipped.
- [ ] **Cursor-based pagination (offline-first)** — list reads from GRDB via `ValueObservation`. `loadMoreIfNeeded(rowId)` on last `.onAppear` kicks `GET /tickets?cursor=<opaque>&limit=50` when online; response upserts into GRDB; list auto-refreshes. Offline: no-op (or un-archive locally evicted older rows if applicable). `hasMore` derived from local `{ oldestCachedAt, serverExhaustedAt? }` per filter, NOT from a `total_pages` field.
- [ ] **GRDB cache** — render from disk instantly, background-refresh from server; cache keyed by ticket id, filtered locally via GRDB predicates on `(status_group, assignee, urgency, updated_at)` rather than by server-returned pagination tuple. No `(filter, keyword, page)` cache buckets.
- [ ] **Footer states** — `Loading…` / `Showing N of ~M` / `End of list` / `Offline — N cached, last synced Xh ago`. Four distinct states, never collapsed.
- [ ] **Filter chips** — All / Open / On hold / Closed / Cancelled / Active (mirror server `status_group`).
- [ ] **Urgency chips** — Critical / High / Medium / Normal / Low (color-coded dots).
- [ ] **Search** by keyword (ticket ID, order ID, customer name, phone, device IMEI). Debounced 300ms.
- [ ] **Sort** dropdown — newest / oldest / status / urgency / assignee / due date / total DESC.
- [ ] **Column / density picker** (iPad/Mac) — show/hide: assignee, internal note, diagnostic note, device, urgency dot.
- [ ] **Swipe actions** — leading: Assign-to-me / SMS customer; trailing: Archive / Mark complete.
- [ ] **Context menu** — Open, Copy order ID (`.textSelection(.enabled)` preview), SMS customer, Call customer, Duplicate, Convert to invoice, Archive, Delete, Share PDF.
- [ ] **Multi-select** (iPad/Mac first) — `.selection` binding; BulkActionBar floating glass footer — Bulk assign / Bulk status / Bulk archive / Export / Delete.
- [ ] **Kanban mode toggle** — switch list ↔ board; columns = statuses; drag-drop between columns triggers `PATCH /tickets/:id/status` (iPad/Mac best; iPhone horizontal swipe columns).
- [ ] **Saved views** — pin filter combos as named chips on top ("Waiting on parts", "Ready for pickup"); stored in `UserDefaults` now, server-backed when endpoint exists.
- [x] **iPad split layout — Messages-style** (decision 2026-04-20). In landscape, Tickets screen is a **list-on-left + detail-on-right 2-pane** via `NavigationSplitView(.balanced)` gated on `Platform.isCompact`. `.hoverEffect(.highlight)` on rows, `.keyboardShortcut("N", .command)` on New. Context menu with Edit wired + Duplicate / Mark-complete stubbed disabled pending backend endpoints. `.textSelection(.enabled)` on order IDs.
  - Column widths: list 320–380pt; detail fills the rest. User can drag divider within bounds (`.navigationSplitViewColumnWidth(min:ideal:max:)`).
  - Empty-detail state: "Select a ticket" illustration until a row is tapped (Apple Messages pattern).
  - Row-to-detail transition on selection: inline detail swap, no push animation.
  - Deep-link open (e.g., from a push notification) selects the row + loads detail simultaneously.
  - Matches §83.3 wireframe which will be updated to two-pane iPad landscape.
- [ ] **Export CSV** — `GET /tickets/export` + `.fileExporter` on iPad/Mac.
- [ ] **Pinned/bookmarked** tickets at top (⭐ toggle).
- [ ] **Customer-preview popover** — tap customer avatar on row → small glass card with recent-tickets + quick-actions.
- [ ] **Row age / due-date badges** — same color scheme as My Queue (red/amber/yellow/gray).
- [ ] **Empty state** — "No tickets yet. Create one." CTA.
- [ ] **Offline state** — list renders from GRDB; banner "Showing cached tickets" + last-sync time.

### 4.2 Detail
- [x] Base detail (customer, devices, notes, history, totals) — shipped.
- [ ] **Tab layout** (mirror web): Actions / Devices / Notes / Payments. iPhone = segmented control. iPad/Mac = sidebar or toolbar picker, content fills remainder.
- [ ] **Header** — ticket ID (copyable, `.textSelection(.enabled)` + `CopyButton`), status chip (tap to change), urgency chip, customer card, created / due / assignee.
- [ ] **Status picker** — `GET /settings/statuses` drives options (color + name); `PATCH /tickets/:id/status` with `{ status_id }`; inline transition dots.
- [ ] **Assignee picker** — avatar grid; filter by role; "Assign to me" shortcut; `PUT /tickets/:id` with `{ assigned_to }`; handoff modal requires reason (§4.12).
- [ ] **Totals panel** — subtotal, tax, discount, deposit, balance due, paid; `.textSelection(.enabled)` on each; copyable grand total.
- [ ] **Device section** — add/edit multiple devices (`POST /tickets/:id/devices`, `PUT /tickets/devices/:deviceId`). Each device: make/model (catalog picker), IMEI, serial, condition, diagnostic notes, photo reel.
- [ ] **Per-device checklist** — pre-conditions intake: screen cracked / water damage / passcode / battery swollen / SIM tray / SD card / accessories / backup done / device works. `PUT /tickets/devices/:deviceId/checklist`. Must be signed before status → "diagnosed" (frontend enforcement).
- [ ] **Services & parts** per device — catalog picker pulls from `GET /repair-pricing/services` + `GET /inventory`; each line item = description + qty + unit price + tax-class; auto-recalc totals; price override role-gated.
- [ ] **Photos** — full-screen gallery with pinch-zoom, swipe, share. Upload via `POST /tickets/:id/photos` (multipart, photos field) over background URLSession; progress glass chip. Delete via swipe-to-trash. Mark "before / after" tag. EXIF-strip PII on upload.
- [ ] **Notes** — types: internal / customer-visible / diagnostic / SMS / email / string (server types). `POST /tickets/:id/notes` with `{ type, content, is_flagged, ticket_device_id? }`. Flagged notes badge-highlight.
- [ ] **History timeline** — server-driven events (status changes, notes, photos, SMS, payments, assignments). Filter toggle chips per event type. Glass pill per day header.
- [ ] **Warranty / SLA badge** — "Under warranty" or "X days to SLA breach"; pull from `GET /tickets/warranty-lookup` on load.
- [ ] **QR code** — render ticket order-ID as QR via CoreImage; tap → full-screen enlarge for counter printer. `Image(uiImage: ...)` + plaintext below.
- [ ] **Share PDF / AirPrint** — on-device rendering pipeline per §17.4. `WorkOrderTicketView(model:)` → `ImageRenderer` → local PDF; hand file URL (never a web URL) to `UIPrintInteractionController` or share sheet. SMS shares the public tracking link (§53); email attaches the locally-rendered PDF so recipient sees it without login. Fully offline-capable.
- [ ] **Copy link to ticket** — Universal Link `app.bizarrecrm.com/tickets/:id`.
- [ ] **Customer quick actions** — Call (`tel:`), SMS (opens thread), FaceTime, Email, open Customer detail, Create ticket for this customer.
- [ ] **Related** — sidebar (iPad) with Recent tickets from same customer, Photo wallet, Health score, LTV tier (see §42).
- [ ] **Bench timer widget** — small glass card, start/stop (`POST /bench/:ticketId/timer-start`); feeds Live Activity (§24.2).
- [ ] **Handoff banner** (iPad/Mac) — `NSUserActivity` advertising this ticket so a Mac can pick it up.
- [ ] **Deleted-while-viewing** — banner "This ticket was removed. [Close]".
- [ ] **Permission-gated actions** — hide destructive actions when user lacks role.

### 4.3 Create — full-fidelity multi-step
- [x] Minimal create shipped (customer + single device) — `Tickets/TicketCreateView`.
- [x] **Offline create** — network-class failures enqueue `ticket.create` via `TicketOfflineQueue`; `PendingSyncTicketId = -1` sentinel + glass banner.
- [x] **Idempotency key** — per-record UUID enforced by `SyncQueueStore.enqueue` dedupe index.
- [ ] **Flow steps** — Customer → Device(s) → Services/Parts → Diagnostic/checklist → Pricing & deposit → Assignee / urgency / due date → Review.
- [ ] **iPhone:** full-screen cover with top progress indicator (glass); each step own view.
- [ ] **iPad:** 2-column sheet (left: step list, right: active step content); `Done` / `Back` in toolbar.
- [ ] **Customer picker** — search existing (`GET /customers/search`) + "New customer" inline mini-form (see §5.3); recent customers list.
- [ ] **Device catalog** — `GET /catalog/manufacturers` + `GET /catalog/devices?keyword=&manufacturer=` drive hierarchical picker. Pre-populate common-repair suggestions from `GET /device-templates`.
- [ ] **Device intake photos** — camera + library; 0..N; drag-to-reorder (iPad) / long-press-reorder (iPhone).
- [ ] **Pre-conditions checklist** — checkboxes (from server or tenant default); required signed on bench start.
- [ ] **Services / parts picker** — quick-add tiles (top 5 services from `GET /pos-enrich/quick-add`) + full catalog search + barcode scan (VisionKit). Tap inventory part → adds to cart; tap service → adds with default labor rate from `GET /repair-pricing/services`.
- [ ] **Pricing calculator** — subtotal + tax class (per line) + line discount + cart discount (% or $, reason required beyond threshold) + fees + tip + rounding rules. Live recalc.
- [ ] **Deposit** — "Collect deposit now" → inline POS charge (see §16) or "Mark deposit pending". Deposit amount shown on header.
- [ ] **Assignee picker** — employee grid filtered by role / clocked-in; "Assign to me" shortcut.
- [ ] **Due date** — default = tenant rule from `GET /settings/store` (+N business days); custom via `DatePicker`.
- [ ] **Service type** — Walk-in / Mail-in / On-site / Pick-up / Drop-off (from `GET /settings/store`). - we should rethink the types completely though, and maybe have custom types availabel
- [ ] **Tags / labels** — multi-chip picker.
- [ ] **Source / referral** — dropdown (source list from server).
- [ ] **Source-ticket linking** — pre-seed from existing ticket (convert-from-estimate flow).
- [ ] **Review screen** — summary card with all fields; "Edit" jumps back to step; Big `.brandGlassProminent` "Create ticket" CTA.
- [ ] **Idempotency key** — client generates UUID, sent as `Idempotency-Key` header to avoid duplicate creates on retry.
- [ ] **Offline create** — GRDB temp ID (negative int or `OFFLINE-UUID`), human-readable offline reference ("OFFLINE-2026-04-19-0001"), queued in `sync_queue`; reconcile on drain — server ID replaces temp ID across related rows (photos, notes).
- [ ] **Autosave draft** — every field change writes to `tickets_draft` GRDB table; "Resume draft" banner on list when present; discard confirmation.
- [ ] **Validation** — per-step inline glass error toasts; block next until required fields valid.
- [ ] **Keyboard shortcuts** — ⌘↩ create, ⌘. cancel, ⌘→ / ⌘← next/prev step.
- [ ] **Haptic** — `.success` on create; `.error` on validation fail.
- [ ] **Post-create** — pop to ticket detail; if deposit collected → Sale success screen (§16.8); offer "Print label" if receipt printer paired.

### 4.4 Edit
- [x] Edit sheet shipped — `Tickets/TicketEditView` / `TicketEditViewModel`. Server-narrow field set (discount, reason, source, referral, due_on) per `PUT /api/v1/tickets/:id`.
- [x] **Offline enqueue** — network failure routes to `ticket.update` with `entityServerId`; `TicketSyncHandlers` replays on reconnect.
- [ ] **Expanded fields** — status, assignee, notes, devices, services, prices, deposit, urgency, tags, labels, customer reassign (pending device-level `PUT /tickets/devices/:deviceId` endpoint).
- [ ] **Optimistic UI** with rollback on failure (revert local mutation + glass error toast).
- [ ] **Audit log** entries streamed back into timeline.
- [ ] **Concurrent-edit** detection — server returns 409 on stale `updated_at`; UI shows "This ticket changed. Reload to merge." banner.
- [ ] **Delete** — destructive confirm; soft-delete server-side.

### 4.5 Ticket actions
- [ ] **Convert to invoice** — `POST /tickets/:id/convert-to-invoice` → jumps to new invoice detail; prefill ticket line items; respect deposit credit.
- [ ] **Attach to existing invoice** — picker; append line items.
- [ ] **Duplicate ticket** — same customer + device + clear status.
- [ ] **Merge tickets** — pick a duplicate candidate (search dialog); confirm; server merges notes / photos / devices.
- [ ] **Transfer to another technician** — handoff modal with reason (required) — `PUT /tickets/:id` with `{ assigned_to }` + note auto-logged.
- [ ] **Transfer to another store / location** (multi-location tenants).
- [ ] **Bulk action** — `POST /tickets/bulk-action` with `{ ticket_ids, action, value }` — bulk assign / bulk status / bulk archive / bulk tag.
- [ ] **Warranty lookup** — quick action "Check warranty" — `GET /tickets/warranty-lookup?imei|serial|phone`.
- [ ] **Device history** — `GET /tickets/device-history?imei|serial` — shows past repairs for this device on any customer.
- [ ] **Star / pin** to dashboard.

### 4.6 Notes & mentions
- [ ] **Compose** — multiline text field, type picker (internal / customer / diagnostic / sms / email), flag toggle.
- [ ] **`@` trigger** — inline employee picker (`GET /employees?keyword=`); insert `@{name}` token.
- [ ] **Mention push** — server sends APNs to mentioned employee.
- [ ] **Markdown-lite** — bold / italic / bullet lists / inline code render with `AttributedString`.
- [ ] **Link detection** — phone / email / URL auto-tappable.
- [ ] **Attachment** — add image from camera/library → inline preview; stored as note attachment.

### 4.7 Statuses & transitions
- [x] **Fetch taxonomy** `GET /settings/statuses` → `TicketStatusRow` array; drives `TicketStatusChangeSheet` (no hardcoded statuses).
- [x] **Commit** via `PATCH /tickets/:id/status`; sheet highlights current status with a check, dismisses + refreshes detail on success.
- [ ] **Color chip** from server hex — `color` field is wired through the DTO but the row doesn't render it yet.
- [ ] **Transition guards** — some transitions require: note added, photos taken, checklist signed, QC sign-off. Frontend enforces + server validates.
- [ ] **QC sign-off modal** — signature capture (PencilKit `PKCanvasView`), comments, "Work complete" confirm.
- [ ] **Status notifications** — if tenant configured SMS/email on this transition, modal confirms "Notify customer?" with template preview.

### 4.8 Photos — advanced
- [ ] **Camera** — `AVCaptureSession` with flash toggle, flip, grid, shutter haptic.
- [ ] **Library picker** — `PhotosUI.PhotosPicker` with selection limit 10.
- [ ] **Upload** — background `URLSession` surviving app exit; progress chip per photo.
- [ ] **Retry failed upload** — dead-letter entry in Sync Issues.
- [ ] **Annotate** — PencilKit overlay on photo for markup; saves as new attachment (original preserved).
- [ ] **Before / after tagging** — toggle on each photo; detail view shows side-by-side on review.
- [ ] **EXIF strip** — remove GPS + timestamp metadata on upload.
- [ ] **Thumbnail cache** — Nuke with disk limit; full-size fetched on tap.
- [ ] **Signature attach** — signed customer acknowledgement saved as PNG attachment.

### 4.9 Bench workflow
- [ ] **Backend:** `GET /bench`, `POST /bench/:ticketId/timer-start`.
- [ ] **Frontend:** Bench tab (or dashboard tile) — queue of my bench tickets with device template shortcut + big timer.
- [ ] **Live Activity** — Dynamic Island & Lock Screen show active-repair timer.
- [ ] **Foreground-service equivalent** — persistent Lock-Screen Live Activity while repair is active (iOS parallel to Android `RepairInProgressService`).

### 4.10 Device templates
- [ ] **Backend:** `GET /device-templates`, `POST /device-templates`.
- [ ] **Frontend:** template picker on create / bench — pre-fills common repairs per device; editable per tenant in Settings → Device Templates.

### 4.11 Repair pricing catalog
- [ ] **Backend:** `GET /repair-pricing/services`, `POST`, `PUT`.
- [ ] **Frontend:** searchable services catalog with labor-rate defaults; per-device-model overrides.

### 4.12 Handoff modal
- [ ] Required reason dropdown: Shift change / Escalation / Out of expertise / Other (free-text). Assignee picker. `PUT /tickets/:id` + auto-logged note. Receiving tech gets push.

### 4.13 Empty / error states
- [ ] No tickets — glass illustration + "Create your first ticket".
- [ ] Network error on detail — keep cached data, glass retry pill.
- [ ] Deleted on server → banner "Ticket removed. [Close]".
- [ ] Permission denied on action → inline toast "Ask your admin to enable this.".
- [ ] 409 stale edit → "This ticket changed. [Reload]".
- [ ] Waiver PDF templates managed server-side; iOS renders.
- [ ] Required contexts: drop-off agreement (liability / data loss / diagnostic fee), loaner agreement (§5), marketing consent (TCPA SMS / email opt-in).
- [ ] Waiver sheet UI: scrollable text + `PKCanvasView` signature + printed name + "I've read and agree" checkbox; Submit disabled until checked + signature non-empty.
- [ ] Signed PDF auto-emailed to customer; archived to tenant storage under `/tickets/:id/waivers` or `/customers/:id/consents`.
- [ ] `POST /tickets/:id/signatures` endpoint.
- [ ] Audit log entry per signature: timestamp + IP + device fingerprint + waiver version + actor (tenant staff who presented).
- [ ] Re-sign on waiver-text change: existing customers re-sign on next interaction; version tracked per §64 template versioning.
- [ ] Default state set (tenant-customizable): Intake → Diagnostic → Awaiting Approval → Awaiting Parts → In Repair → QA → Ready for Pickup → Completed → Archived. Branches: Cancelled, Un-repairable, Warranty Return.
- [ ] Transition rules editable in Settings → Ticket statuses (§19.16): optional per-transition prerequisites (photo required / pre-conditions signed / deposit collected / quote approved). Blocked transitions show inline error "Can't mark Ready — no photo."
- [ ] Triggers on transition: auto-SMS (e.g., Ready for Pickup → text customer per §12 template); assignment-change audit log; idle-alert push to manager after > 7d in `Awaiting Parts`.
- [ ] Bulk transitions via multi-select → "Move to Ready" menu; rules enforced per-ticket; skipped ones shown in summary.
- [ ] Rollback: admin-only; creates audit entry with reason.
- [ ] Visual: tenant-configured color per state; state pill on every list row + detail header.
- [ ] Funnel chart in §15 Reports: count per state + avg time-in-state; bottleneck highlight if avg > tenant benchmark.
- [ ] Context menu (long-press on list row): Open / Copy ID / Share PDF / Call customer / Text customer / Print receipt / Mark Ready / Mark In Repair / Assign to me / Archive / Delete (admin only)
- [ ] Swipe actions (iOS native): right swipe = Start/Mark Ready (state-dependent); left swipe = Archive; long-swipe destructive requires alert confirm
- [ ] iPad Magic Keyboard shortcuts: ⌘D mark done; ⌘⇧A assign; ⌘⇧S send SMS update; ⌘P print; ⌘⌫ delete (admin only)
- [ ] Drag-and-drop: drag ticket row to "Assign" sidebar target (iPad) to reassign; drag to status column in Kanban (§18.6 if built)
- [ ] Batch actions: multi-select in list (§63); batch context menu Assign/Status/Archive/Export
- [ ] Smart defaults: show most-recently-used action first per user; adapts over time
- [ ] Local IMEI validation only: Luhn checksum + 15-digit length.
- [ ] Optional TAC lookup (first 8 digits) via offline table to name device model.
- [ ] Called from ticket create / inventory trade-in purely for device identification + autofill make/model.
- [ ] No stolen/lost/carrier-blacklist provider lookup — scope intentionally dropped. Shop does not gate intake on external device-status services.
- [ ] Warranty record created on ticket close for each installed part/service
- [ ] Warranty record fields: part_id, serial, install date, duration (90d/1yr/lifetime), conditions
- [ ] Claim intake: staff searches warranty by IMEI/receipt/name
- [ ] Match shows prior tickets + install dates + eligibility
- [ ] Decision: within warranty + valid claim → new ticket status Warranty Return; parts + labor zero-priced automatically
- [ ] Decision: out of warranty → new ticket status Paid Repair
- [ ] Decision: edge cases (water damage, physical damage) flagged for staff judgment
- [ ] Part return to vendor: defective part marked RMA-eligible; staff ships via §4.3
- [ ] Auto-SMS confirming warranty coverage + re-ETA estimate
- [ ] Reporting: warranty claim rate by part / by supplier / by tech (reveals quality issues)
- [ ] Cost center: warranty repair labor + parts allocated to warranty cost center
- [ ] Dashboard shows warranty cost vs revenue
- [ ] SLA definitions per service type (e.g. "Diagnose within 4h", "Repair within 24h for priority", "Respond to SMS in 30m")
- [ ] Timer starts on intake/ticket create
- [ ] Timer pauses for statuses configured as "Waiting on customer" / "Awaiting parts"
- [ ] Timer resumes on return to active state
- [ ] Ticket list row: SLA chip (green/amber/red) based on remaining time
- [ ] Ticket detail: timer + phase progress
- [ ] Alerts: amber at 75% used; red at 100%
- [ ] Push to assignee + manager when breached
- [ ] Reports: per tech SLA compliance %
- [ ] Reports: per service average time vs SLA
- [ ] Override: manager can extend SLA with reason (audit log)
- [ ] Customer commitment: SLA visible on public tracking page (§53) as "We'll update you by <time>"
- [ ] Ticket can't be marked Ready until QC checklist complete
- [ ] Per-service checklist configurable per repair type
- [ ] Example iPhone screen checklist: Display lights up / Touch works / Camera / Speaker / Mic / Wi-Fi / Cellular / Battery health / Face ID / No new scratches
- [ ] Each item: pass / fail / N/A + optional photo
- [ ] Failure: fail item returns ticket to In Repair with failure noted
- [ ] Require reason on flip back to In Repair
- [ ] Sign-off: tech signature + timestamp
- [ ] Optional second-tech verification for high-value repairs
- [ ] Customer-visible: checklist printed on invoice/receipt so customer sees what was tested
- [ ] Audit: QC history visible in ticket history including who tested and when
- [ ] Labels separate from status: status is lifecycle (one), labels are optional flags (many)
- [ ] Example labels: urgent, VIP, warranty, insurance claim, parts-ordered, QC-pending
- [ ] Color-coded chips on list rows
- [ ] Filter ticket list by label
- [ ] Auto-rules: "device-value > $500 → auto-label VIP"
- [ ] Auto-rules: "parts-ordered → auto-label on PO link"
- [ ] Multi-select bulk apply/remove label
- [ ] Conceptual: ticket labels are ticket-scoped vs customer tags are customer-scoped — don't conflate
- [ ] Label break-outs in revenue/duration reports (e.g. "Insurance claims avg turn time = 8d")
- [ ] Inline chip on ticket list row: small ring showing % of SLA consumed; green < 60%, amber 60-90%, red > 90%, black post-breach.
- [ ] Detail header: progress bar with phase markers (diagnose / awaiting parts / repair / QC); long-press reveals phase timestamps + remaining.
- [ ] Timeline overlay: status history (§4.6) overlays SLA curve to show phase-budget consumption.
- [ ] Manager aggregated view: all-open tickets on SLA heatmap (tickets × time to SLA); red-zone sortable to top.
- [ ] Projection: predict breach time at current pace ("At current rate, will breach at 14:32").
- [ ] One-tap "Notify customer of delay" with template (§12) pre-filled.
- [ ] Reduce Motion: gauge animates only when Reduce Motion off; else static value.
- [ ] See §6 for the full list.
- [ ] See §17 for the full list.

---
## §5. Customers

_Server endpoints: `GET /customers`, `GET /customers/search`, `GET /customers/{id}`, `POST /customers`, `PUT /customers/{id}`, `DELETE /customers/{id}`, `GET /customers/{id}/tickets`, `GET /customers/{id}/invoices`, `GET /customers/{id}/communications`, `GET /customers/{id}/assets`, `POST /customers/{id}/assets`, `GET /customers/{id}/analytics`, `POST /customers/bulk-tag`, `POST /customers/merge`, `GET /crm/customers/{id}/health-score`, `POST /crm/customers/{id}/health-score/recalculate`, `GET /crm/customers/{id}/ltv-tier`._

### 5.1 List
- [x] Base list + search — shipped.
- [ ] **Cursor-based pagination (offline-first)** per top-of-doc rule + §20.5. List reads from GRDB via `ValueObservation`; `loadMoreIfNeeded` kicks `GET /customers?cursor=&limit=50` online only; offline no-op. Footer states: loading / more-available / end-of-list / offline-with-cached-count.
- [ ] **Sort** — most recent / A–Z / Z–A / most tickets / most revenue / last visit.
- [ ] **Filter** — tag(s) / LTV tier (VIP / Regular / At-risk) / health-score band / balance > 0 / has-open-tickets / city-state.
- [ ] **Swipe actions** — leading: SMS / Call; trailing: Mark VIP / Archive.
- [ ] **Context menu** — Open, Copy phone, Copy email, FaceTime, New ticket, New invoice, Send SMS, Merge.
- [ ] **A–Z section index** (iPhone): right-edge scrubber jumps by letter (`SectionIndexTitles` via `UICollectionViewListSection`).
- [ ] **Stats header** (toggleable via `include_stats=true`) — total customers, VIPs, at-risk, total LTV, avg LTV.
- [ ] **Preview popover** (iPad/Mac hover) — quick stats (spent / tickets / last visit).
- [ ] **Bulk select + tag** — BulkActionBar; `POST /customers/bulk-tag` with `{ customer_ids, tag }`.
- [ ] **Bulk delete** with undo toast (5s window).
- [ ] **Export CSV** via `.fileExporter` (iPad/Mac).
- [ ] **Empty state** — "No customers yet. Create one or import from Contacts." + two CTAs.
- [ ] **Import from Contacts** — `CNContactPickerViewController` multi-select → create each.

### 5.2 Detail
- [x] Base (analytics / recent tickets / notes) — shipped.
- [ ] **Tabs** (mirror web): Info / Tickets / Invoices / Communications / Assets.
- [ ] **Header** — avatar + name + LTV tier chip + health-score ring + VIP star.
- [ ] **Health score** — `GET /crm/customers/:id/health-score` → 0–100 ring (green ≥70 / amber ≥40 / red <40); tap ring → explanation sheet (recency / frequency / spend components); "Recalculate" button → `POST /crm/customers/:id/health-score/recalculate`. Maybe we want to have it auto calculate whenever the customer is opened? Its not really important to have this up to date 100%, so we may offer daily refreshes? 
- [ ] **LTV tier** — `GET /crm/customers/:id/ltv-tier` → chip (VIP / Regular / At-Risk); tap → explanation.
- [ ] **Photo mementos** — recent repair photos gallery (horizontal scroll).
- [ ] **Contact card** — phones (multi, labeled), emails (multi), address (tap → Maps.app), birthday, tags, organization, communication preferences (SMS/email/call opt-in chips), custom fields.
- [ ] **Quick-action row** — glass chips: Call · SMS · Email · FaceTime · New ticket · New invoice · Share · Merge · Delete.
- [ ] **Tickets tab** — `GET /customers/:id/tickets`; infinite scroll; status chips; tap → ticket detail.
- [ ] **Invoices tab** — `GET /customers/:id/invoices`; status filter; tap → invoice.
- [ ] **Communications tab** — `GET /customers/:id/communications`; unified SMS / email / call log timeline; "Send new SMS / email" CTAs.
- [ ] **Assets tab** — `GET /customers/:id/assets`; devices owned (ever on a ticket); add asset (`POST /customers/:id/assets`); tap device → device-history.
- [ ] **Balance / credit** — sum of unpaid invoices + store credit balance (`GET /refunds/credits/:customerId`). CTA "Apply credit" if > 0.
- [ ] **Membership** — if tenant has memberships (§38), show tier + perks.
- [ ] **Share vCard** — generate `.vcf` via `CNContactVCardSerialization` → share sheet (iPhone), `.fileExporter` (Mac).
- [ ] **Add to iOS Contacts** — `CNContactViewController` prefilled.
- [ ] **Delete customer** — confirm dialog + warning if open tickets (offer reassign-or-cancel flow).

### 5.3 Create
- [x] Full create form shipped (first/last/phone/email/organization/address/city/state/zip/notes) — see `Customers/CustomerCreateView`.
- [ ] **Extended fields** — type (person / business), multiple phones with labels (home / work / mobile), multiple emails, mailing vs billing address, tags chip picker, communication preferences toggles, custom fields (render from `GET /custom-fields`), referral source, birthday, notes.
- [x] **Phone normalize** — uses shared `PhoneFormatter` in Core.
- [ ] **Duplicate detection** — before save, fuzzy match on phone/email; modal "Looks like this might be {name}. Use existing?" with Merge / Cancel / Create anyway.
- [ ] **Import from Contacts** — `CNContactPickerViewController` prefills form.
- [ ] **Barcode/QR scan** — scan customer card (if tenant prints them) for quick-lookup.
- [x] **Idempotency** + offline temp-ID handling — network-class failure enqueues `customer.create` with UUID idempotency key; `createdId = -1` sentinel for pending UI.

### 5.4 Edit
- [x] All fields editable. `PUT /customers/:id` — see `Customers/CustomerEditView`.
- [x] Offline enqueue on network failure with `entityServerId`; `CustomerSyncHandlers` replays on reconnect.
- [ ] Concurrent-edit 409 banner.

### 5.5 Merge
- [ ] `POST /customers/merge` with `{ keep_id, merge_id }`.
- [ ] Search + select candidate; diff preview (which fields survive); confirmation.
- [ ] Destructive — explicit warning that merge is irreversible.

### 5.6 Bulk actions
- [ ] Bulk tag (`POST /customers/bulk-tag`).
- [ ] Bulk delete with undo.
- [ ] Bulk export selected.

### 5.7 Asset tracking
- [ ] Add device to customer (`POST /customers/:id/assets`) — device template picker + serial/IMEI.
- [ ] Tap asset → device-history (`GET /tickets/device-history?imei|serial`).
- [ ] Free-form tag strings (e.g. `vip`, `corporate`, `recurring`, `late-payer`)
- [ ] Color-coded with tenant-defined palette
- [ ] Auto-tags applied by rules (e.g. "LTV > $1000 → gold")
- [ ] Customer detail header chip row for tags
- [ ] Tap tag → filter customer list
- [ ] Bulk-assign tags via list multi-select
- [ ] Tag nesting hierarchy (e.g. "wholesale > region > east") with drill-down filters
- [ ] Segments: saved tag combos + filters (e.g. "VIP + last visit < 90d")
- [ ] Segments used by marketing (§37) and pricing (§6.3)
- [ ] Max 20 tags per customer (warn at 10)
- [ ] Suggested tags based on behavior (e.g. suggest `late-payer` after 3 overdue invoices)
- [ ] Unified customer detail: tickets / invoices / payments / SMS / email / appointments / notes / files / feedback
- [ ] Vertical chronological timeline with colored dots per event type
- [ ] Timeline filter chips and jump-to-date picker
- [ ] Metrics header: LTV, last visit, avg spend, repeat rate, preferred services, churn risk score
- [ ] Relationship graph: household / business links (family / coworker accounts)
- [ ] "Related customers" card
- [ ] Files tab: photos, waivers, emails archived in one place
- [ ] Star-pin important notes to customer header, visible across ticket/invoice/SMS contexts
- [ ] Customer-level warning flags ("cash only", "known difficult", "VIP treatment") as staff-visible banner
- [ ] Dupe detection on create: same phone / same email / similar name + address
- [ ] Suggest merge at entry
- [ ] Side-by-side record comparison merge UI
- [ ] Per-field pick-winner or combine
- [ ] Combine all contact methods (phones + emails)
- [ ] Migrate tickets, invoices, notes, tags, SMS threads, payments to survivor
- [ ] Tombstone loser record with audit reference
- [ ] 24h unmerge window, permanent thereafter (audit preserves trail)
- [ ] Settings → Data → Run dedup scan → lists candidates
- [ ] Manager batch review of dedup candidates
- [ ] Optional auto-merge when 100% phone + email match
- [ ] Per-customer preferred channel for receipts / status / marketing (SMS / email / push / none)
- [ ] Times-of-day preference
- [ ] Granular opt-out: marketing vs transactional, per-category
- [ ] Preferred language for comms; templates auto-use that locale
- [ ] System blocks sends against preference
- [ ] Staff override possible with reason + audit
- [ ] Ticket intake quick-prompt: "How'd you like updates?" with SMS/email toggles
- [ ] Optional birth date on customer record
- [ ] Age not stored unless tenant explicitly needs it
- [ ] Day-of auto-send SMS or email template ("Happy birthday! Here's $10 off")
- [ ] Per-customer opt-in for birthday automation
- [ ] Inject unique coupon (§37) per recipient with 7-day expiry
- [ ] Privacy: never show birth date in lists / leaderboards
- [ ] Age-derived features off by default
- [ ] Exclusion: last-60-days visited customers get less salesy message
- [ ] Exclusion: churned customers get reactivation variant
- [ ] Intake via customer detail → "New complaint"
- [ ] Fields: category + severity + description + linked ticket
- [ ] Resolution flow: assignee + due date + escalation path
- [ ] Status: open / investigating / resolved / rejected
- [ ] Required root cause on resolve: product / service / communication / billing / other
- [ ] Aggregate root causes for trend analysis
- [ ] SLA: response within 24h / resolution within 7d, with breach alerts
- [ ] Optional public share of resolution via customer tracking page
- [ ] Full audit history; immutable once closed
- [ ] Note types: Quick (one-liner), Detail (rich text + attachments), Call summary, Meeting, Internal-only
- [ ] Internal-only notes hidden from customer-facing docs
- [ ] Pin critical notes to customer header (max 3)
- [ ] @mention teammate → push notification + link
- [ ] @ticket backlinks
- [ ] Internal-only flag hides note from SMS/email auto-include
- [ ] Role-gate sensitive notes (manager only)
- [ ] Quick-insert templates (e.g. "Called, left voicemail", "Reviewed estimate")
- [ ] Edit history: edits logged; previous version viewable
- [ ] A11y: rich text accessible via VoiceOver element-by-element
- [ ] Per-customer file list (PDF, images, spreadsheets, waivers, warranty docs)
- [ ] Tags + search on files
- [ ] Upload sources: Camera / Photos / Files picker / iCloud / external drive
- [ ] Inline `QLPreviewController` preview
- [ ] PencilKit PDF annotation markup
- [ ] Share sheet → customer email / AirDrop
- [ ] Retention: tenant policy per file type; auto-archive old
- [ ] Encryption at rest (tenant storage) and in transit
- [ ] Offline-cached files encrypted in SQLCipher-wrapped blob store
- [ ] Versioning: replacing file keeps previous with version number
- [ ] Just-in-time `CNContactStore.requestAccess` at "Import"
- [ ] `CNContactPickerViewController` single- or multi-select
- [ ] vCard → customer field mapping: name, phones, emails, address, birthday
- [ ] Field selection UI when multiple values
- [ ] Duplicate handling: cross-check existing customers (§5) → merge / skip / create new
- [ ] "Import all" confirm sheet with summary (skipped / created / updated)
- [ ] Privacy: read-only; never writes back to Contacts
- [ ] Clear imported data if user revokes permission
- [ ] A11y: VoiceOver announces counts at each step
- [ ] Tenant-level template: symbol placement (pre/post), thousands separator, decimal separator per locale.
- [ ] Per-customer override of tenant default.
- [ ] Support formats: US `$1,234.56`, EU-FR `1 234,56 €`, JP `¥1,235`, CH `CHF 1'234.56`.
- [ ] Money input parsing accepts multiple locales; normalize to storage.
- [ ] VoiceOver accessibility: read full currency phrasing.
- [ ] Toggle for ISO 3-letter code vs symbol on invoices (cross-border clarity).
- [ ] See §28 for the full list.

---
## §6. Inventory

_Server endpoints: `GET /inventory`, `GET /inventory/manufacturers`, `POST /inventory/import-csv`, `POST /inventory/{id}/image`, `GET /stocktake`, `POST /stocktake`, `POST /stocktake/{id}/items`, `GET /inventory-enrich/barcode-lookup`, `GET /purchase-orders`, `POST /purchase-orders`._

### 6.1 List
- [x] Base list + filter chips + search — shipped.
- [ ] **Tabs** — All / Products / Parts. NOT SERVICES - as they are not inventorable. We should however have a settings menu for services to setup the devices types, manufacturers, etc. 
- [ ] **Search** — name / SKU / UPC / manufacturer (debounced 300ms).
- [ ] **Filters** (collapsible glass drawer): Manufacturer / Supplier / Category / Min price / Max price / Hide out-of-stock / Reorderable-only / Low-stock.
- [ ] **Columns picker** (iPad/Mac) — SKU / Name / Type / Category / Stock / Cost / Retail / Supplier / Bin. Persist per user.
- [ ] **Sort** — SKU / name / stock / last restocked / price / last sold / margin.
- [ ] **Low-stock badge** + out-of-stock chip; critical-low pulse animation (respect Reduce Motion).
- [ ] **Quick stock adjust** — inline +/- buttons on row (qty stepper, debounced PUT).
- [ ] **Bulk select** — Price adjustment (% inc/dec preview modal) / Delete / Export / Print labels.
- [ ] **Receive items** modal — scan items into stock or add manually; creates a stock-movement batch.
- [ ] **Receive by PO** — pick a PO, scan items to increment received qty; close PO on completion.
- [ ] **Import CSV/JSON** — paste → preview → confirm (`POST /inventory/import-csv`). Row-level validation errors highlighted.
- [ ] **Mass label print** — multi-select → label printer (AirPrint or MFi).
- [ ] **Context menu** — Open, Copy SKU, Adjust stock, Create PO, Deactivate, Delete.
- [ ] **Cost price hidden** from non-admin roles (server returns null).
- [ ] **Empty state** — "No items yet. Import a CSV or scan to add." CTAs.

### 6.2 Detail
- [x] Stock card / group prices / movements — shipped.
- [ ] **Full movement history — cursor-based, offline-first** (same contract as top-of-doc rule + §20.5, scoped per-SKU). GRDB `inventory_movement` table keyed by SKU + movement_id; detail view reads via `ValueObservation`. `sync_state` stored per-SKU: `{ cursor, oldestCachedAt, serverExhaustedAt?, lastUpdatedAt }`. Online scroll-to-bottom triggers `GET /inventory/:sku/movements?cursor=&limit=50`. Offline shows cached range with banner "History from X to Y — older rows require sync". Silent-push or WS broadcast inserts new movements at top via `updated_at` anchor so current scroll position preserved. Same four footer states as entity lists. Never use `total_pages`.
- [ ] **Price history chart** — `Charts.AreaMark` over time; toggle cost vs retail.
- [ ] **Sales history** — last 30d sold qty × revenue line chart.
- [ ] **Supplier panel** — name / contact / last-cost / reorder SKU / lead-time.
- [ ] **Auto-reorder rule** — view / edit threshold + reorder qty + supplier.
- [ ] **Bin location** — text field + picker (Settings → Inventory → Bin Locations).
- [ ] **Serials** — if serial-tracked, list of assigned serial numbers + which customer / ticket holds each.
- [ ] **Reorder / Restock** action — opens quick form to record stock-in or draft PO.
- [ ] **Barcode display** — Code-128 + QR via CoreImage; `.textSelection(.enabled)` on SKU/UPC.
- [ ] **Used in tickets** — recent tickets that consumed this part; tap → ticket.
- [ ] **Cost vs retail variance analysis** card (margin %).
- [ ] **Tax class** — editable (admin only).
- [ ] **Photos** — gallery; tap → lightbox; upload via `POST /inventory/:id/image`.
- [ ] **Edit / Deactivate / Delete** buttons.

### 6.3 Create
- [x] **Form**: Name (required), SKU, UPC / barcode, item type (product / part / service), category, cost price, retail price, tax class, stock qty, reorder threshold, reorder qty, supplier, bin, manufacturer, description, photos, tags, taxable flag — shipped via `Inventory/InventoryCreateView` + `InventoryFormView`.
- [ ] **Inline barcode scan** — `DataScannerViewController` to fill SKU/UPC; auto-lookup via `GET /inventory-enrich/barcode-lookup` (external DB). Autofill name/manufacturer/UPC from result.
- [ ] **Photo capture** up to 4 per item; first = primary.
- [x] **Validation** — decimal for prices (2 places), integer for stock. Name + SKU required.
- [ ] **Save & add another** secondary CTA.
- [x] **Offline create** — temp ID + queue via `InventoryOfflineQueue`; `PendingSyncInventoryId = -1` sentinel.

### 6.4 Edit
- [x] All fields editable (cost/price role gating TBD) — `Inventory/InventoryEditView`.
- [x] **Stock adjust** — `InventoryAdjustSheet` + `InventoryAdjustViewModel` wired. `POST /inventory/:id/adjust-stock` with delta + 6-reason picker (Recount/Shrinkage/Damage/Receive/Transfer/Other) + notes. Commit `0f43c61`. 404/501 → `APITransportError.notImplemented` surfaces "Coming soon" banner.
- [x] **Low-stock alerts view** — `InventoryLowStockView` lists items below reorder_level with shortage badge; swipe → `InventoryAdjustSheet`. Toolbar "Low stock" ⌘⇧L on Inventory list.
- [ ] **Move between locations** (multi-location tenants).
- [ ] **Delete** — confirm; prevent if stock > 0 or open PO references it.
- [ ] **Deactivate** — keep history, hide from POS.

### 6.5 Scan to lookup
- [ ] **Tab-bar quick scan** / Dashboard FAB scan → VisionKit → resolves barcode → item detail. If POS session open → add to cart.
- [ ] **HID-scanner support** — accept external Bluetooth scanner input via hidden `TextField` with focus + IME-send detection (Android parity). Detect rapid keystrokes (intra-key <50ms) → buffer until Enter → submit.
- [ ] **Vibrate haptic** on successful scan.

### 6.6 Stocktake / audit
- [ ] **Sessions list** (`GET /stocktake`) — open + recent sessions with item count, variance summary.
- [ ] **New session** — name, optional location, start.
- [ ] **Session detail** — barcode scan loop → running count list with expected vs counted + variance dots. Manual entry fallback. Commit (`POST /stocktake/:id/items`) creates adjustments. Cancel discards.
- [ ] **Summary** — items counted / items-with-variance / total variance / surplus / shortage.
- [ ] **Multi-user** — multiple scanners feeding same session via WS events.

### 6.7 Purchase orders
- [ ] **List** — status filter (draft / sent / partial / received / cancelled); columns: PO#, supplier, total, status, expected date.
- [ ] **Create** — supplier picker, line items (add from inventory with qty + cost), expected date, notes.
- [ ] **Send** — email to supplier.
- [ ] **Receive** — scan items to increment; partial receipt supported.
- [ ] **Cancel** — confirm.
- [ ] **PDF export** (`.fileExporter` on iPad/Mac).

### 6.8 Advanced inventory (admin tools, iPad/Mac first)
- [ ] **Bin locations** — create aisle / shelf / position; batch assign items; pick list generation.
- [ ] **Auto-reorder rules** — per-item threshold + qty + supplier; "Run now" → draft POs.
- [ ] **Serials** — assign serial to item; link to customer/ticket; serial lookup.
- [ ] **Shrinkage report** — expected vs actual; variance trend chart.
- [ ] **ABC analysis** — A/B/C classification; `Chart` bar.
- [ ] **Age report** — days-in-stock; markdown / clearance suggestions.
- [ ] **Mass label print** — select items → label format → print (AirPrint or MFi thermal).
- [ ] `Asset` entity: id / type / serial / purchase date / cost / depreciation / status (available / loaned / in-repair / retired); optional `current_customer_id`.
- [ ] Loaner issue flow on ticket detail: "Issue loaner" → pick asset → waiver signature (§4 intake signature) → updates asset status to loaned + ties to ticket.
- [ ] Return flow: inspect → mark available; release any BlockChyp hold.
- [ ] Deposit hold via BlockChyp (optional, per asset policy).
- [ ] Auto-SMS at ready-for-pickup + overdue-> 7d escalation push to manager.
- [ ] Depreciation (linear / declining balance) + asset-book-value dashboard tile.
- [ ] Optional geofence alert (>24h outside metro area) — opt-in + customer consent required.
- [ ] Bundle = set of items sold together at discount. Examples: Diagnostic + repair + warranty; Data recovery + backup + return shipping.
- [ ] Builder: Settings → Bundles → Add; drag items in; set bundle price or "sum − %".
- [ ] POS renders bundle as single SKU; expand to reveal included items; partial-delivery progress ("Diagnostic done, repair pending").
- [ ] Each included item decrements stock independently on sale.
- [ ] Reporting: bundle sell-through vs individual + attach-rate.
- [ ] Use-case: regulated parts (batteries) require lot tracking for recalls
- [ ] Model: `InventoryLot` per receipt with fields lot_id, receive_date, vendor_invoice, qty, expiry
- [ ] Sale/use decrements lot FIFO by default (or LIFO per tenant)
- [ ] FEFO alt: expiring-first queue for perishables (paste/adhesive)
- [ ] Recalls: vendor recall → tenant queries "all tickets using lot X" → customer outreach
- [ ] Traceability: ticket detail shows which lot was used per part (regulatory)
- [ ] Config: per-SKU opt-in (most SKUs don't need lot tracking)
- [ ] Scope: high-value items (phones, laptops, TVs)
- [ ] New-stock serials scanned on receive
- [ ] Intake: scan serial + auto-match model
- [ ] POS scan on sale reduces qty by 1 for that serial
- [ ] Lookup: staff scans, iOS hits tenant server which may cross-check (§6)
- [ ] Link to customer: sale binds serial to customer record (enables warranty lookup by serial)
- [ ] Unique constraint: each serial sold once; sell-again requires "Returned/restocked" status
- [ ] Reports: serials out by month; remaining in stock
- [ ] Flow: source location initiates transfer (pick items + qty + destination)
- [ ] Status lifecycle: Draft → In Transit → Received
- [ ] Transit count: inventory marked "in transit", not sellable at either location
- [ ] Receive: destination scans items
- [ ] Discrepancy handling (§6.3)
- [ ] Shipping label: print bulk label via §17
- [ ] Optional carrier integration (UPS/FedEx)
- [ ] Reporting: transfer frequency + bottleneck analysis
- [ ] Permissions split: source manager initiates, destination manager receives
- [ ] Model: dedicated non-sellable bin per location
- [ ] Items moved here with reason (damaged / obsolete / expired / lost)
- [ ] Move flow: Inventory → item → "Move to scrap" → qty + reason + photo
- [ ] Decrements sellable qty; increments scrap bin
- [ ] Cost impact: COGS adjustment recorded
- [ ] Shrinkage report totals reflect scrap
- [ ] Disposal: scrap bin items batch-disposed (trash / recycle / salvage)
- [ ] Disposal document generated with signature
- [ ] Insurance: disposal records support insurance claims (theft, fire)
- [ ] Report: inventory aged > N days since last sale
- [ ] Grouped by tier: slow (60d) / dead (180d) / obsolete (365d)
- [ ] Action: clearance pricing suggestions
- [ ] Action: bundle with hot-selling item (§16)
- [ ] Action: return to vendor if eligible
- [ ] Action: donate for tax write-off
- [ ] Alerts: quarterly push "N items hit dead tier — plan action"
- [ ] Visibility: inventory list chip "Stale" / "Dead" badge
- [ ] Per vendor: average days from order → receipt
- [ ] Computed from PO history
- [ ] Lead-time variance shows unreliability → affects reorder point
- [ ] Safety stock buffer qty = avg daily sell × lead time × safety factor
- [ ] Auto-calc or manual override of safety stock
- [ ] Vendor comparison side-by-side: cost, lead time, on-time %
- [ ] Suggest alternate vendor when primary degrades
- [ ] Seasonality: lead times may lengthen in holiday season; track per-month
- [ ] Inventory item detail shows "Lead time 7d avg (p90 12d)"
- [ ] PO creation uses latest stats for ETA
- [ ] See §7 for the full list.

---
## §7. Invoices

_Server endpoints: `GET /invoices`, `GET /invoices/stats`, `GET /invoices/{id}`, `POST /invoices`, `PUT /invoices/{id}`, `POST /invoices/{id}/payments`, `POST /invoices/{id}/void`, `POST /invoices/{id}/credit-note`, `POST /invoices/bulk-action`, `GET /reports/aging`._

### 7.1 List
- [x] Base list + filter chips + search — shipped.
- [x] Row a11y — combined VoiceOver utterance `displayId. customerName. total. [Status X]. [Due $Y]`. Selectable order IDs, monospaced Due text.
- [ ] **Status tabs** — All / Unpaid / Partial / Overdue / Paid / Void.
- [ ] **Filters** — date range, customer, amount range, payment method, created-by.
- [ ] **Sort** — date / amount / due date / status.
- [ ] **Row chips** — "Overdue 3d" (red), "Paid 50%" (amber), "Unpaid" (gray), "Paid" (green), "Void" (strike-through).
- [ ] **Stats header** — `GET /invoices/stats` → total outstanding / paid / overdue / avg value; tap to drill down.
- [ ] **Status pie + payment-method pie** (iPad/Mac) — small `Chart.SectorMark` cards.
- [ ] **Bulk select** → bulk action (`POST /invoices/bulk-action`): Send reminder / Export / Void / Delete.
- [ ] **Export CSV** via `.fileExporter`.
- [ ] **Row context menu** — Open, Copy invoice #, Send SMS, Send email, Print, Record payment, Void.
- [ ] **Cursor-based pagination (offline-first)** per top-of-doc rule + §20.5. `GET /invoices?cursor=&limit=50` online; list reads from GRDB via `ValueObservation`.

### 7.2 Detail
- [x] Line items / totals / payments — shipped.
- [ ] **Header** — invoice number (INV-XXXX, `.textSelection(.enabled)`), status chip, due date, balance-due chip.
- [ ] **Customer card** — name + phone + email + quick-actions.
- [ ] **Line items** — editable table (if status allows); tax per line.
- [ ] **Totals panel** — subtotal / discount / tax / total / paid / balance due.
- [ ] **Payment history** — method / amount / date / reference / status; tap → payment detail.
- [ ] **Add payment** → `POST /invoices/:id/payments` (see 7.4).
- [ ] **Issue refund** — `POST /refunds` with `{ invoice_id, amount, reason }`; role-gated; partial + full.
- [ ] **Credit note** — `POST /invoices/:id/credit-note` with `{ amount, reason }`.
- [ ] **Void** — `POST /invoices/:id/void` with reason; destructive confirm.
- [ ] **Send by SMS** — pre-fill "Your invoice: {payment-link-url}" using `POST /sms/send`; short-link via `POST /payment-links`.
- [ ] **Send by email** — `MFMailComposeViewController` with PDF attached.
- [ ] **Share PDF** — share sheet (iPhone) / `.fileExporter` (iPad/Mac).
- [ ] **AirPrint** via `UIPrintInteractionController` with custom PDF renderer.
- [ ] **Clone invoice** — duplicate line items for new invoice.
- [ ] **Convert to credit note** — if overpaid.
- [ ] **Timeline** — every status change, payment, note, email/SMS send.
- [ ] **Deposit invoices linked** — nested card showing connected deposit invoices.

### 7.3 Create
- [ ] **Customer picker** (or pre-seeded from ticket).
- [ ] **Line items** — add from inventory catalog (with barcode scan) or free-form; qty, unit price, tax class, line-level discount.
- [ ] **Cart-level discount** (% or $), tax, fees, tip.
- [ ] **Notes**, due date, payment terms, footer text.
- [ ] **Deposit required** flag → generate deposit invoice.
- [ ] **Convert from ticket** — prefill line items via `POST /tickets/:id/convert-to-invoice`.
- [ ] **Convert from estimate**.
- [ ] **Idempotency key** — server requires for POST /invoices.
- [ ] **Draft** autosave.
- [ ] **Send now** checkbox — email/SMS on create.

### 7.4 Record payment
- [ ] **Method picker** — fetched from `GET /settings/payment` (cash / card-in-person → POS flow / card-manual / ACH / check / gift card / store credit / other). Want to make sure to wire this correctly, especially for card, store credit and gift cards.
- [ ] **Amount entry** — default to balance due; support partial + overpayment (surplus → store credit prompt).
- [ ] **Reference** (check# / card last 4 / BlockChyp txn ID — auto-filled from terminal).
- [ ] **Notes** field.
- [ ] **Cash** — change calculator.
- [ ] **Split tender** — chain multiple methods until balance = 0.
- [ ] **BlockChyp card** — start terminal charge → poll status; surface Live Activity for the txn.
- [ ] **Idempotency-Key** required on POST /invoices/:id/payments.
- [ ] **Receipt** — print (MFi / AirPrint) + email + SMS; PDF download.
- [ ] **Haptic** `.success` on payment confirm.

### 7.5 Overdue automation
- [ ] Server schedules reminders. iOS: overdue badge on dashboard + push notif tap → deep-link to invoice.
- [ ] Dunning sequences (see §40) manage escalation.

### 7.6 Aging report
- [ ] `GET /reports/aging` with bucket breakdown (0–30 / 31–60 / 61–90 / 90+ days).
- [ ] iPad/Mac: `Table` with sortable columns; iPhone: grouped list by bucket.
- [ ] Row actions: Send reminder / Record payment / Write off.

- [ ] Two return paths: customer-return-of-sold-goods (from invoice detail) + tech-return-to-vendor (from PO / inventory).
- [ ] Customer return flow: Invoice detail → "Return items" → pick lines + qty → reason → refund method (original card via BlockChyp refund / store credit / gift card). Creates `Return` record linked to invoice; updates inventory; reverses commission (§14 commission clawback) unless tenant policy overrides.
- [ ] Vendor return flow: "Return to vendor" from PO / inventory → pick items → RMA # (manual or vendor API) → print shipping label via §17.4. Status: pending / shipped / received / credited.
- [ ] Tenant-configurable restocking fee per item class.
- [ ] Return receipt prints with negative lines + refund method + signature line (§17.4 template).
- [ ] Per-item restock choice: salable / scrap bin / damaged bin.
- [ ] Fraud guards: warn on high-$ returns > threshold; manager PIN required over limit; audit entry.
- [ ] Endpoint `POST /refunds {invoice_id, lines, reason}` (already in §81).
- [ ] Card declined → queue retry
- [ ] Retry schedule: +3d / +7d / +14d
- [ ] Each retry notifies via email + SMS + in-app notification
- [ ] Smart retry — soft declines (insufficient funds, do-not-honor): standard schedule
- [ ] Smart retry — hard declines (fraud, card reported): stop + notify customer to update card
- [ ] Self-service: customer portal link (§53) to update card
- [ ] Self-service: Apple Pay via pay page
- [ ] Escalation: after N failed attempts, alert tenant manager + auto-suspend plan
- [ ] Audit: every dunning event logged
- [ ] Model: flat fee / percentage / compounding
- [ ] Model: grace period before applying
- [ ] Model: max cap
- [ ] Application: auto-added to invoice on overdue
- [ ] Status change to "Past due" triggers reminder
- [ ] Staff can waive with reason + audit
- [ ] Threshold above which manager PIN required
- [ ] Customer communication: reminder SMS/email before fee applied (1-3d lead)
- [ ] Customer communication: fee-applied notification with payment link
- [ ] Jurisdiction limits: some jurisdictions cap late fees by law
- [ ] Tenant-configurable max; warn on violation

---
## §8. Estimates

_Server endpoints: `GET /estimates`, `GET /estimates/{id}`, `POST /estimates`, `PUT /estimates/{id}`, `POST /estimates/{id}/approve`._

### 8.1 List
- [x] Base list + is-expiring warning — shipped.
- [x] Row a11y — combined utterance `orderId. customerName. total. [Status X]. [Expires in Nd | Valid until date]`. Selectable order IDs.
- [ ] Status tabs — All / Draft / Sent / Approved / Rejected / Expired / Converted.
- [ ] Filters — date range, customer, amount, validity.
- [ ] Bulk actions — Send / Delete / Export.
- [ ] Expiring-soon chip (pulse animation when ≤3 days).
- [ ] Context menu — Open, Send, Convert to ticket, Convert to invoice, Duplicate, Delete.
- [ ] Cursor-based pagination (offline-first) per top-of-doc rule + §20.5. `GET /estimates?cursor=&limit=50` online; list reads from GRDB via `ValueObservation`.

### 8.2 Detail
- [ ] **Header** — estimate # + status + valid-until date.
- [ ] **Line items** + totals.
- [ ] **Send** — SMS / email; body includes approval link (customer portal).
- [ ] **Approve** — `POST /estimates/:id/approve` (staff-assisted) with signature capture (`PKCanvasView`).
- [ ] **Reject** — reason required.
- [ ] **Convert to ticket** — prefill ticket; inventory reservation.
- [ ] **Convert to invoice**.
- [ ] **Versioning** — revise estimate; keep prior versions visible.
- [ ] **Customer-facing PDF preview** — "See what customer sees" button.

### 8.3 Create
- [ ] Same structure as invoice + validity window.
- [ ] Convert from lead (prefill).
- [ ] Line items from repair-pricing services + inventory parts + free-form.
- [ ] Idempotency key.

### 8.4 Expiration handling
- [ ] Auto-expire when past validity date (server-driven).
- [ ] Manual expire action.

- [ ] Quote detail → "Send for e-sign" generates public URL `https://<tenant>/public/quotes/:code/sign`; share via SMS / email.
- [ ] Signer experience (server-rendered public page, no login): quote line items + total + terms + signature box + printed name + date → submit stores PDF + signature.
- [ ] iOS push to staff on sign: "Quote #42 signed by Acme Corp — convert to ticket?" Deep-link opens quote; one-tap convert to ticket (§8).
- [ ] Signable within N days (tenant-configured); expired → "Quote expired — contact shop" page.
- [ ] Audit: each open / sign event logged with IP + user-agent + timestamp.
- [ ] Each edit creates new version; prior retained
- [ ] Version number visible on UI (e.g. "v3")
- [ ] Only "sent" versions archived for audit; drafts freely edited
- [ ] Side-by-side diff of v-n vs v-n+1
- [ ] Highlight adds / removes / price changes
- [ ] Customer approval tied to specific version
- [ ] Warning if customer approved v2 and tenant edited to v3 ("Customer approved v2; resend?")
- [ ] Convert-to-ticket uses approved version with stored reference (downstream changes don't invalidate)
- [ ] Reuse same versioning machinery for receipt templates + waivers (§4.6)

---
## §9. Leads

_Server endpoints: `GET /leads`, `POST /leads`, `PUT /leads/{id}`._

### 9.1 List
- [x] Base list — shipped.
- [x] Row a11y — combined utterance `displayName. [orderId]. [phone-or-email]. [Status X]. [Score N of 100]`. Selectable phone/email/order, monospaced score.
- [ ] **Columns** — Name / Phone / Email / Lead Score (0–100 progress bar) / Status / Source / Value / Next Action.
- [ ] **Status filter** (multi-select) — New / Contacted / Scheduled / Qualified / Proposal / Converted / Lost.
- [ ] **Sort** — name / created / lead score / last activity / next action.
- [ ] **Bulk delete** with undo.
- [ ] **Swipe** — advance / drop stage.
- [ ] **Context menu** — Open, Call, SMS, Email, Convert to customer, Schedule appointment, Delete.
- [ ] **Preview popover** quick view.

### 9.2 Pipeline (Kanban view)
- [ ] **Route:** segmented control at top of Leads — List / Pipeline.
- [ ] **Columns** — one per status; drag-drop cards between (updates via `PUT /leads/:id`).
- [ ] **Cards** show — name + phone + score chip + next-action date.
- [ ] **iPad/Mac** — horizontal scroll all columns visible. **iPhone** — horizontal paging between columns.
- [ ] **Filter by salesperson / source**.
- [ ] **Bulk archive won/lost**.

### 9.3 Detail
- [x] **Header** — name + phone + email + score ring + status chip. (`Leads/LeadDetailView.swift` `headerCard` — name, score badge, status chip, source.)
- [x] **Basic fields** — first/last name, phone, email, company, title, source, value, next action + date, assigned-to. (partial — `LeadDetailView.swift` `contactCard` + `metaCard` render phone/email/company; title/value/next-action date deferred.)
- [ ] **Lead score** — calculated metric with explanation sheet.
- [ ] **Status workflow** — transition dropdown; Lost → reason dialog (required).
- [ ] **Activity timeline** — calls, SMS, email, appointments, property changes.
- [ ] **Related tickets / estimates** (if any).
- [ ] **Communications** — SMS + email + call log; send CTAs.
- [ ] **Notes** — @mentions.
- [ ] **Tags** chip picker.
- [ ] **Convert to customer** — creates customer, copies fields, archives lead.
- [ ] **Convert to estimate** — starts estimate with prefilled customer.
- [ ] **Schedule appointment** — jumps to Appointment create prefilled.
- [ ] **Delete / Edit**.

### 9.4 Create
- [x] Minimal form — shipped.
- [ ] **Extended fields** — score (manual override), source, value, stage, assignee, follow-up date, notes, tags, custom fields.
- [ ] **Offline create** + reconcile.

### 9.5 Lost-reason modal
- [ ] Required dropdown (price / timing / competitor / not-a-fit / other) + free-text.

---
## §10. Appointments & Calendar

_Server endpoints: `GET /appointments`, `POST /appointments`, `PUT /appointments/{id}`, `DELETE /appointments/{id}`, `GET /calendar` (verify)._

### 10.1 List / calendar views
- [x] Base list — shipped. Rows parse ISO-8601 / SQL datetimes and render 'Today' / 'Tomorrow' / 'Yesterday' / 'MMM d' + short time; single-utterance accessibilityLabel combining date, title, customer, assignee, status.
- [ ] **Segmented control** — Agenda / Day / Week / Month.
- [ ] **Month** — `CalendarView`-style grid with dot per day for events; tap day → agenda.
- [ ] **Week** — 7-column time-grid; events as glass tiles colored by type; scroll-to-now pin.
- [ ] **Day** — agenda list grouped by time-block (morning / afternoon / evening).
- [ ] **Time-block Kanban** (iPad) — columns = employees, rows = time slots (drag-drop reschedule).
- [ ] **Today** button in toolbar; `⌘T` shortcut.
- [ ] **Filter** — employee / location / type / status.

### 10.2 Detail
- [ ] Customer card + linked ticket / estimate / lead.
- [ ] Time range + duration, assignee, location, type (drop-off / pickup / consult / on-site / delivery), notes.
- [ ] Reminder offsets (15min / 1h / 1day before) — respects per-user default.
- [ ] Quick actions glass chips: Call · SMS · Email · Reschedule · Cancel · Mark no-show · Mark completed · Open ticket.
- [ ] Send-reminder manually (`POST /sms/send` + template).

### 10.3 Create
- [x] Minimal — shipped.
- [ ] Full form: customer, assignee, location, start time, duration, type, linked ticket / estimate / lead, reminder offsets, recurrence (daily / weekly / custom), notes.
- [ ] **EventKit mirror** — "Add to my Calendar" toggle writes `EKEvent` to user's default calendar (requires `NSCalendarsUsageDescription`).
- [ ] **Conflict detection** — if assignee double-booked, modal warning with "Schedule anyway" / "Pick another time".
- [ ] **Idempotency** + offline temp-id.

### 10.4 Edit / reschedule / cancel
- [ ] Drag-to-reschedule (iPad day/week views) with haptic `.medium` on drop.
- [ ] Cancel — ask "Notify customer?" (SMS/email).
- [ ] No-show — one-tap from detail; optional fee.
- [ ] Recurring-event edits — "This event" / "This and following" / "All".

### 10.5 Reminders
- [ ] Server cron sends APNs N min before (per-user setting).
- [ ] Silent APNs triggers local `UNUserNotificationCenter` alert if user foregrounded; actionable notif has "Call / SMS / Mark arrived" buttons.
- [ ] Live Activity — "Next appt in 15 min" pulse on Lock Screen.

### 10.6 Check-in / check-out
- [ ] At appt time, staff can tap "Customer arrived" → stamps check-in; starts ticket timer if linked to ticket.
- [ ] "Customer departed" on completion.

- [ ] Appointment types (Drop-off / pickup / consultation / on-site visit) with per-type default duration + resource requirement (tech / bay / specific tool).
- [ ] Availability: staff shifts × resource capacity × buffer times × blackout holiday dates.
- [ ] Suggest engine: given customer window, return 3 nearest slots satisfying resource + staff requirements (`POST /appointments/suggest`).
- [ ] iPad drag-drop calendar (mandatory big-screen); iPhone list-by-day. Drag-to-reschedule = optimistic update + server confirm + rollback on conflict.
- [ ] Multi-location view: combine or filter by location.
- [ ] No-show tracking per customer with tenant-configurable deposit-required-after-N-no-shows policy.

---
## §11. Expenses

_Server endpoints: `GET /expenses`, `POST /expenses`, `PUT /expenses/{id}`, `DELETE /expenses/{id}`._

### 11.1 List
- [x] Base list + summary header — shipped.
- [x] Row a11y — combined utterance `category. [description]. [date]. amount`. Monospaced amount text.
- [ ] **Filters** — category / date range / employee / reimbursable flag / approval status.
- [ ] **Sort** — date / amount / category.
- [ ] **Summary tiles** — Total (period), By category (pie), Reimbursable pending.
- [ ] **Category breakdown pie** (iPad/Mac).
- [ ] **Export CSV**.
- [ ] **Swipe** — edit / delete.
- [ ] **Context menu** — Open, Duplicate, Delete.

### 11.2 Detail
- [ ] Receipt photo preview (full-screen zoom, pinch).
- [ ] Fields — category / amount / vendor / payment method / notes / date / reimbursable flag / approval status / employee.
- [ ] Edit / Delete.
- [ ] Approval workflow — admin Approve / Reject with comment.

### 11.3 Create
- [x] Minimal — shipped.
- [ ] **Receipt capture** — camera inline; OCR total via `VNRecognizeTextRequest` + regex for `\$\d+\.\d{2}`; auto-fill amount field (user editable).
- [ ] **Photo library import** — pick existing receipt.
- [ ] **Categories** — from server dropdown (Rent / Utilities / Parts / Tools / Marketing / Insurance / Payroll / Software / Office Supplies / Shipping / Travel / Maintenance / Taxes / Other).
- [ ] **Amount validation** — decimal 2 places; cap $100k.
- [ ] **Date picker** — defaults today.
- [ ] **Reimbursable toggle** — if user role = employee, approval defaults pending.
- [ ] **Offline create** + temp-id reconcile.

### 11.4 Approval (admin)
- [ ] List filter "Pending approval".
- [ ] Approve / Reject with comment; auto-notify submitter.

---
## §12. SMS & Communications

_Server endpoints: `GET /sms/unread-count`, `GET /sms/conversations`, `GET /sms/conversations/{id}/messages`, `POST /sms/send`, `GET /inbox`, `POST /inbox/{id}/assign`, `POST /voice/call`, `GET /voice/calls`, `GET /voice/calls/{id}`, `GET /voice/calls/{id}/recording`, `POST /voice/call/{id}/hangup`. WS topic: `sms:received`, `call:started`, `call:ended`._

### 12.1 Thread list
- [x] Threads list — shipped.
- [x] Row a11y — combined utterance `displayName. [Pinned]. [Flagged]. [lastMessage]. [date]. [N unread]`. Avatar + pin + flag + unread dot are accessibilityHidden.
- [ ] **Unread badge** on tab icon (`UIApplication.shared.applicationIconBadgeNumber`) + per-thread bubble.
- [ ] **Filters** — All / Unread / Flagged / Pinned / Archived / Assigned to me / Unassigned.
- [ ] **Search** — across all messages + phone numbers.
- [ ] **Pin important threads** to top.
- [ ] **Sentiment badge** (positive / neutral / negative) if server computes.
- [ ] **Swipe actions** — leading: mark read / unread; trailing: flag / archive / pin.
- [ ] **Context menu** — Open, Call, Open customer, Assign, Flag, Pin, Archive.
- [ ] **Compose new** (FAB) — pick customer or raw phone.
- [ ] **Team inbox tab** (if enabled) — shared inbox, assign rows to teammates.

### 12.2 Thread view
- [x] Bubbles + composer + POST /sms/send — shipped.
- [ ] **Real-time WS** — new message arrives without refresh; animate in with spring.
- [ ] **Delivery status** icons per message — sent / delivered / failed / scheduled.
- [ ] **Read receipts** (if server supports).
- [ ] **Typing indicator** (if supported).
- [ ] **Attachments** — image / PDF / audio (MMS) via multipart upload.
- [ ] **Canned responses / templates** (from `GET /settings/templates`) surfaced as chips above composer; hotkeys Alt+1..9 (Mac/iPad keyboard).
- [ ] **Ticket / invoice / payment-link picker** — inserts short URL + ID token into composer.
- [ ] **Emoji picker**.
- [ ] **Schedule send** — date/time picker for future delivery.
- [ ] **Voice memo** (if MMS supported) — record AAC inline; bubble plays audio.
- [ ] **Long-press message** → context menu — Copy, Reply, Forward, Create ticket from this, Flag, Delete.
- [ ] **Create customer from thread** — if phone not associated.
- [ ] **Character counter** + SMS-segments display (160 / 70 unicode).
- [ ] **Compliance footer** — auto-append STOP message on first outbound to opt-in-ambiguous numbers.
- [ ] **Off-hours auto-reply** indicator when enabled.

### 12.3 PATCH helpers
- [x] Add PATCH method to `APIClient` — shipped (`Networking/APIClient.swift` exposes `patch<T,B>(_:body:as:)`).
- [ ] Mark read — `PATCH /sms/messages/:id { read: true }` (verify endpoint).
- [ ] Flag / pin — `PATCH /sms/conversations/:id { flagged, pinned }`.

### 12.4 Voice / calls (if VoIP tenant)
- [ ] **Calls tab** — list inbound / outbound / missed; duration; recording playback if available.
- [ ] **Initiate call** — `POST /voice/call` with `{ to, customer_id? }` → CallKit integration (`CXProvider`).
- [ ] **Recording playback** — `GET /voice/calls/:id/recording` → `AVAudioPlayer`.
- [ ] **Hangup** — `POST /voice/call/:id/hangup`.
- [ ] **Transcription display** — if server provides.
- [ ] **Incoming call push** (PushKit VoIP) → CallKit UI.

### 12.5 Push → deep link
- [ ] Push notification on new inbound SMS with category `SMS_INBOUND`.
- [ ] Actions: Reply (inline text input via `UNTextInputNotificationAction`), Open, Call.
- [ ] Tap → SMS thread.

### 12.6 Bulk SMS / campaigns (cross-links §37)
- [ ] Compose campaign to a segment; TCPA compliance check; preview.

### 12.7 Empty / error states
- [ ] No threads → "Start a conversation" CTA → compose new.
- [ ] Send failed → red bubble with "Retry" chip; retried sends queued offline.

---
## §13. Notifications

_Server endpoints: `GET /notifications`, `POST /device-tokens` (verify), `PATCH /notifications/:id/dismiss` (verify)._

### 13.1 List
- [x] Base list — shipped.
- [ ] **Tabs** — All / Unread / Assigned to me / Mentions.
- [ ] **Mark all read** action (glass toolbar button).
- [ ] **Tap → deep link** (ticket / invoice / SMS thread / appointment / customer).
- [ ] **Swipe to dismiss** (persists via `PATCH /notifications/:id/dismiss`).
- [ ] **Group by day** (glass day-header).
- [ ] **Filter chips** — type (ticket / SMS / invoice / payment / appointment / mention / system).
- [ ] **Empty state** — "All caught up. Nothing new." illustration.

### 13.2 Push pipeline
- [ ] **Register APNs** on login: `UIApplication.registerForRemoteNotifications()` → `POST /device-tokens` with `{ token, platform: "ios", model, os_version, app_version }`.
- [ ] **Token refresh** on rotation.
- [ ] **Unregister on logout** — `DELETE /device-tokens/:token`.
- [ ] **Silent push** (`content-available: 1`) triggers background sync tick.
- [ ] **Rich push** — thumbnail images via Notification Service Extension (customer avatar / ticket photo).
- [ ] **Notification categories** registered on launch:
  - `SMS_INBOUND` → Reply inline / Call / Open.
  - `TICKET_ASSIGNED` → Start work / Decline / Open.
  - `PAYMENT_RECEIVED` → View receipt / Thank customer.
  - `APPOINTMENT_REMINDER` → Call / SMS / Reschedule.
  - `MENTION` → Reply / Open.
- [ ] **Entity allowlist** on deep-link parse (security — prevent injected types).
- [ ] **Quiet hours** — respect Settings → Notifications → Quiet Hours.
- [ ] **Notification-summary** (iOS 15+) — `interruptionLevel: .timeSensitive` for overdue invoice / SLA breach.

### 13.3 In-app toast
- [ ] Foreground message on a different screen → glass toast at top with tap-to-open; auto-dismiss in 4s; `.selection` haptic.

### 13.4 Badge count
- [ ] App icon badge = unread count across inbox + notifications + SMS.

---
## §14. Employees & Timeclock

_Server endpoints: `GET /employees`, `GET /employees/{id}`, `POST /employees`, `PUT /employees/{id}`, `POST /employees/{id}/clock-in`, `POST /employees/{id}/clock-out`, `GET /roles`, `POST /roles`, `GET /team`, `POST /team/shifts`, `GET /team-chat`, `POST /team-chat`, `GET /bench`._

### 14.1 List
- [x] Base list — shipped.
- [ ] **Filters** — role / active-inactive / clocked-in-now.
- [ ] **"Who's clocked in right now"** view — real-time via WS presence events.
- [ ] **Columns** (iPad/Mac) — Name / Email / Role / Status / Has PIN / Hours this week / Commission.
- [ ] **Permission matrix** admin view — `GET /roles`; checkbox grid of permissions × roles.

### 14.2 Detail
- [ ] Role, wage/salary (admin-only), contact, schedule.
- [ ] **Performance tiles** (admin-only) — tickets closed, SMS sent, revenue touched, avg ticket value, NPS from customers.
- [ ] **Commissions** — `POST /team/shifts` drives accrual; display per-period; lock period (admin).
- [ ] **Schedule** — upcoming shifts + time-off.
- [ ] **PIN management** — view (as set?) / change / clear.
- [ ] **Deactivate** — soft-delete; grey out future logins.

### 14.3 Timeclock
- [ ] **Clock in / out** — dashboard tile + dedicated screen; `POST /employees/:id/clock-in` / `-out`.
- [ ] **PIN prompt** — custom numeric keypad with haptic per tap; `POST /auth/verify-pin`.
- [ ] **Breaks** — start / end break with type (meal / rest); accumulates toward labor law compliance.
- [ ] **Geofence** — optional; capture location on clock-in/out if permission granted; server records inside/outside store geofence.
- [ ] **Edit entries** (admin only, audit log).
- [ ] **Timesheet** weekly view per employee.
- [ ] **Offline queue** — clock events persisted locally, synced later.
- [ ] **Live Activity** — "Clocked in since 9:14 AM" on Lock Screen until clock-out.

### 14.4 Invite / manage (admin)
- [ ] **Invite** — `POST /employees` with `{ email, role }`; server sends invite link. The server may not have an email if self hosted though - lets make sure we account for that. 
- [ ] **Resend invite**.
- [ ] **Assign role** — technician / cashier / manager / admin / custom.
- [ ] **Deactivate** — soft delete.
- [ ] **Custom role creation** — Settings → Team → Roles matrix.

### 14.5 Team chat
- [ ] **Channel-less team chat** (`GET /team-chat`, `POST /team-chat`).
- [ ] Messages with @mentions; real-time via WS.
- [ ] Image / file attachment.
- [ ] Pin messages.

### 14.6 Team shifts (weekly schedule)
- [ ] **Week grid** (7 columns, employees rows).
- [ ] Tap empty cell → add shift; tap filled → edit.
- [ ] Shift modal — employee, start/end, role, notes.
- [ ] Time-off requests sidebar — approve / deny (manager).
- [ ] Publish week → notifies team.
- [ ] Drag-drop rearrange (iPad).

### 14.7 Leaderboard
- [ ] Ranked list by tickets closed / revenue / commission.
- [ ] Period filter (week / month / YTD).
- [ ] Badges 🥇🥈🥉.

### 14.8 Performance reviews / goals
- [ ] Reviews — form (employee, period, rating, comments); history.
- [ ] Goals — create / update progress / archive; personal vs team view.

### 14.9 Time-off requests
- [ ] Submit request (date range + reason).
- [ ] Manager approve / deny.dont forget to ACTUALLY implement the manager's access point. 
- [ ] Affects shift grid.

### 14.10 Shortcuts
- [ ] Clock-in/out via Control Center widget (iOS 18+).
- [ ] Siri intent "Clock me in at BizarreCRM".

- [ ] End-of-shift summary: cashier taps "End shift" → summary card (sales count / gross / tips / cash expected / cash counted entered / over-short / items sold / voids); compare to prior shifts for trend
- [ ] Close cash drawer: prompt to count cash by denomination ($100, $50, $20…); system computes expected from sales; delta live; over-short reason required if >$2
- [ ] Manager sign-off: over-short threshold exceeded requires manager PIN; audit entry with cashier + manager IDs
- [ ] Receipt: Z-report printed + PDF archived in §39 Cash register; PDF linked in shift summary
- [ ] Handoff: next cashier starts with opening cash count entered by closing cashier
- [ ] Sovereignty: shift data on tenant server only
- [ ] Hire wizard: Manager → Team → Add employee; steps basic info / role / commission / access locations / welcome email; account created; staff gets login link
- [ ] Offboarding: Settings → Team → staff detail → Offboard; immediately revoke access, sign out all sessions, transfer assigned tickets to manager, archive shift history (kept for payroll); audit log; optional export of shift history as PDF
- [ ] Role changes: promote/demote path; change goes live immediately
- [ ] Temporary suspension: suspend without offboarding (vacation without pay); account disabled until resume
- [ ] Reference letter (nice-to-have): auto-generate PDF summarizing tenure + stats (total tickets, sales); manager customizes before export
- [ ] Metrics: ticket close rate, SLA compliance, customer rating, revenue attributed, commission earned, hours worked, breaks taken
- [ ] Private by default: self + manager; owner sees all
- [ ] Manager annotations with notes + praise / coaching signals, visible to employee
- [ ] Rolling trend windows: 30 / 90 / 365d with chart per metric
- [ ] "Prepare review" button compiles scorecard + self-review form + manager notes into PDF for HR file
- [ ] Distinguish objective hard metrics from subjective manager rating
- [ ] Subjective 1-5 scale with descriptors
- [ ] Staff can request feedback from 1-3 peers during review cycle
- [ ] Form with 4 prompts: going well / to improve / one strength / one blind spot
- [ ] Anonymous by default; peer can opt to attribute
- [ ] Delivery to manager who curates before sharing with subject (prevents rumor / hostility)
- [ ] Frequency cap: max once / quarter per peer requested
- [ ] A11y: long-form text input with voice dictation
- [ ] Peer-to-peer shoutouts with optional ticket attachment
- [ ] Shoutouts appear in peer's profile + team chat (if opted)
- [ ] Categories: "Customer save" / "Team player" / "Technical excellence" / "Above and beyond"
- [ ] Unlimited sending; no leaderboard of shoutouts (avoid gaming)
- [ ] Recipient gets push notification
- [ ] Archive received shoutouts in profile
- [ ] End-of-year "recognition book" PDF export
- [ ] Privacy options: private (sender + recipient) or team-visible (recipient opt-in)

---
## §15. Reports & Analytics

_Server endpoints: `GET /reports/dashboard`, `GET /reports/dashboard-kpis`, `GET /reports/aging`, `GET /reports/technician-performance`, `GET /reports/tax`, `GET /reports/inventory`, `GET /reports/scheduled`, `POST /reports/run-now`._

### 15.1 Tab shell
- [~] Phase-0 placeholder.
- [ ] **Sub-routes / segmented picker** — Sales / Tickets / Employees / Inventory / Tax / Insights / Custom.
- [ ] **Date-range selector** with presets + custom; persists.
- [ ] **Export button** — CSV / PDF via `.fileExporter`.
- [ ] **iPad** — sidebar list of reports + chart detail pane.
- [ ] **Schedule report** — `GET /reports/scheduled`; create schedule; auto-email.

### 15.2 Sales
- [ ] Total invoices / revenue / unique customers / period-over-period delta.
- [ ] Revenue trend (`Charts.LineMark`) daily/weekly toggle.
- [ ] Revenue by payment method pie.
- [ ] YoY growth.
- [ ] Top 10 customers by spend.
- [ ] Cohort revenue retention.

### 15.3 Tickets
- [ ] Opened vs closed per day (stacked bar).
- [ ] Close rate.
- [ ] Avg turnaround time.
- [ ] Tickets by status pie.
- [ ] Tickets by tech bar.
- [ ] Busy-hours heatmap.
- [ ] SLA breach count.

### 15.4 Employees
- [ ] `GET /reports/technician-performance` — table: name / tickets assigned / closed / commission / hours / revenue.
- [ ] Per-tech detail drill.

### 15.5 Inventory
- [ ] Low stock / out-of-stock counts.
- [ ] Inventory value (cost + retail).
- [ ] Turnover / dead-stock / top-moving.
- [ ] Shrinkage trend.

### 15.6 Tax
- [ ] `GET /reports/tax` — collected by class / rate summary.
- [ ] Period total for filing.

### 15.7 Insights (adv)
- [ ] Warranty claims trend.
- [ ] Device-models repaired distribution.
- [ ] Parts usage analysis.
- [ ] Technician hours worked.
- [ ] Stalled / overdue tickets.
- [ ] Customer acquisition + churn.

### 15.8 Custom reports
- [ ] Pick series + bucket + range; save as favorite per user.

### 15.9 Export / schedule
- [ ] CSV / PDF export per report.
- [ ] Schedule recurring email of report (server-side).
- [ ] "BI" sub-tab in Reports for deeper analysis
- [ ] Built-in reports: revenue/margin by category/tech/customer segment
- [ ] Built-in reports: repeat customer rate, time-to-repeat
- [ ] Built-in reports: average ticket value trend
- [ ] Built-in reports: conversion funnel (lead → estimate → ticket → invoice → paid)
- [ ] Built-in reports: labor utilization by tech
- [ ] Visual query builder (no SQL): entity + filters + group + measure + timeframe
- [ ] Save custom query as widget
- [ ] Swift Charts with zoom / pan / compare periods
- [ ] Export chart as PNG / CSV
- [ ] Drill-down: tap chart segment → underlying records list
- [ ] Scheduled PDF snapshot email delivery
- [ ] Sovereignty: all compute on tenant server; no external BI tool
- [ ] Breadcrumb drill: tap chart segment → filtered records list; trail "Total revenue → October → Services → iPhone repair"; each crumb tappable to step back.
- [ ] Context panel layout: filters narrowed-by-drill (left), records list (right).
- [ ] Export at any level: share current filtered view as PDF / CSV.
- [ ] "Save this drill as dashboard tile" saves with query.
- [ ] Cross-report drilling: jump into related report with same filters applied.
- [ ] Perf budget: server query index hints, p95 < 2s.
- [ ] See §39 for the full list.
- [ ] See §6 for the full list.
- [ ] See §19 for the full list.

---
## §16. POS / Checkout

_Server endpoints: `POST /invoices`, `POST /invoices/{id}/payments`, `POST /blockchyp/*`, `GET /inventory`, `GET /repair-pricing/services`, `GET /tax`, `POST /pos/holds`, `GET /pos/holds`, `POST /pos/returns`, `POST /cash-register/open`, `POST /cash-register/close`, `GET /cash-register/z-report`, `POST /gift-cards/redeem`, `POST /store-credit/redeem`. All require `tenant-id`, role-gated write operations, idempotency keys on payment/charge._

### 16.1 Tab shell
- [x] Scaffold shipped — `Pos/PosView.swift` replaces the placeholder; iPhone single-column / iPad `NavigationSplitView(.balanced)` gated on `Platform.isCompact`.
- [ ] **Architecture** — PosViewModel owning cart state (current scaffold uses `Cart` @Observable directly); PosRepository + GRDB catalog/holds caches still TBD.
- [x] **Tab replaces**: POS tab in iPhone TabView + POS entry in iPad sidebar (wired via `RootView`).
- [ ] **Permission gate** — `pos.access` in user role; if missing, show "Not enabled for this role" card with contact-admin CTA.
- [x] **Drawer lock** — POS renders "Register closed" placeholder when no open session; `OpenRegisterSheet` via fullScreenCover on mount. Cancel dismisses to placeholder (no sales possible). "Close register" / "View Z-report" entries in overflow ⋯ toolbar. Cashier ID plumbing via `/auth/me` deferred.

### 16.2 Catalog browse (left pane)
- [x] **Layout** — iPhone: single-column full screen; iPad/Mac: `NavigationSplitView(.balanced)` — search/inventory picker leading, cart trailing.
- [ ] **Hierarchy** — top chips: All / Services / Parts / Accessories / Custom. Grid below: category tiles → products.
- [ ] **Product tile** — glass card with photo (Nuke thumbnail), name, price, stock badge.
- [x] **Search bar** — sticky top, queries `InventoryRepository.list(keyword:)`; tap result adds to cart with haptic success.
- [ ] **Long-press tile** — quick-preview sheet (price history, stock, location, last sold date).
- [ ] **Recently sold** chip — shows top 10 items sold in last 24h per this register.
- [ ] **Favorites** — star-pin a product; star chip filter.
- [x] **Custom line** — "+ Custom item" sheet creates untracked line (name, price, qty, tax, notes).
- [ ] **Offline** — catalog cached via `InventoryRepository` (GRDB cache plumbing is part of §20.5).
- [ ] **Search filters** — by category, tax status, in-stock only, price range.
- [ ] **Repair services** — services from `/repair-pricing/services` surface in Services tab.

### 16.3 Cart (right pane / bottom sheet)
- [x] **Cart panel** — iPad right pane full height; iPhone single-screen stack. Glass reserved for the Charge CTA (content rows stay plain, per CLAUDE.md).
- [x] **Header** — total shown in brand Barlow Condensed via `.monospacedDigit()`.
- [x] **Line items** — qty stepper (inc/dec with light haptic), unit price, line total. Swipe trailing = Remove; context menu = Remove / Edit quantity / Edit price.
- [x] **Line edit sheets** — `PosEditQuantitySheet` + `PosEditPriceSheet` wired (role gating TBD in Phase 3).
- [x] **Cart-level** — discount (% + $), tip (preset 10/15/20% + custom), fees (cents + label) via `PosCartAdjustmentSheets` + overflow ⋯ toolbar menu. `effectiveDiscountCents` re-derives on subtotal change.
- [x] **Tax** — per-line `taxRate` propagated into `CartMath.totals` with bankers rounding; multi-rate per item supported. Tenant-wide tax config integration deferred to §19.
- [x] **Totals breakdown** — Subtotal → Tax → Total with `.monospacedDigit()` via `CartMath.formatCents`. Discount + Tip lines added when those features ship.
- [ ] **Link to record** — chip "Link to Ticket #1234".
- [x] **Hold cart** — `POsHoldCartSheet` + `PosResumeHoldsSheet` wired to `POST/GET /pos/holds` with 404/501 "Coming soon" fallback. Resume clears cart first, never inherits pending payment link. Synthetic single-line pending per-hold detail endpoint.
- [x] **Clear cart** — `Clear cart` toolbar action with ⌘⇧⌫ shortcut (destructive confirm lands with the first real-tender phase).
- [x] **Empty state** — "Cart is empty" illustration with call-out to scan / pick / add custom.

### 16.4 Customer pick
- [x] **Attach existing** — `PosCustomerPickerSheet` with debounced 300ms `CustomerRepository.list(keyword:)`; tap row → `cart.attach(customer:)`; CartPill renders chip (initials or walk-in ghost). Loyalty tier badge deferred to §38.
- [x] **Create new inline** — "+ New customer" opens `CustomerCreateView(api:onCreated:)` sheet; on save `PosCustomerNameFormatter.attachPayload(...)` attaches to cart.
- [x] **Guest checkout** — `PosCustomer.walkIn` sentinel; walk-in CTA on POS empty state. Warning for store-credit/loyalty deferred.
- [ ] **Customer-specific pricing** — if customer is in a Customer Group with discount override, apply automatically (banner "Group discount applied").
- [ ] **Tax exemption** — if customer has tax-exempt flag, cart removes tax with banner; show exemption cert # if stored.
- [ ] **Loyalty points preview** — "You'll earn XXX points" if loyalty enabled.

### 16.5 Payment — BlockChyp (primary card rail)

> Phase-2 scaffold note: `Charge` button currently opens `PosChargePlaceholderSheet` which shows the running total and the message "Charge flow not yet wired — BlockChyp SDK pending (§17)." No fake-success path — dismissing returns to the cart. All checkboxes below remain open until the BlockChyp SDK + server endpoints land.

- [ ] **Terminal pairing** — Settings → Terminal → scan QR / enter terminal code + IP; stored in Keychain (`com.bizarrecrm.pos.terminal`).
- [ ] **Heartbeat** — on POS screen load, ping terminal; offline badge if no response in 3s.
- [ ] **Start charge** — tap Pay → select BlockChyp → spinner while terminal prompts cardholder.
- [ ] **Reader states** — `waitForCard`, `chipInserted`, `pinEntered`, `awaitingSignature`, `approved`, `declined`, `timeout`.
- [ ] **Signature capture** — if required, customer signs on terminal OR on iPad (`PKCanvasView`); stored with payment.
- [ ] **Receipt data** — token, auth code, last4, EMV tags, cardholder name → `POST /invoices/{id}/payments` with idempotency key.
- [ ] **Success** — invoice+payment rows written; auto-advance to receipt screen.
- [ ] **Partial auth** — if amount partially approved, prompt for remainder via another tender.
- [ ] **Decline** — show decline reason card; retry / switch tender / void cart.
- [ ] **Timeout** — 60s without card → cancel prompt on terminal; clear spinner.
- [ ] **Tip adjust** — if post-auth tip enabled (bar/restaurant mode), tip input after approval; send `POST /blockchyp/tip-adjust` before batch close.
- [ ] **Void / refund** via BlockChyp — within same batch: void; cross-batch: refund using captured token.
- [ ] **Offline** — queue sale locally (GRDB); replay when connection + terminal restored; show offline-sale badge on receipt ("Authorized offline").

### 16.6 Payment — other tenders
- [ ] **Cash** — keypad sheet; amount-received field; large "Change due" in Barlow Condensed glass card; rounding rules per tenant.
- [ ] **Manual keyed card — same PCI model as §17.3.** We do NOT build our own `TextField`s capturing PAN / expiry / CVV. That would push the app into SAQ-D scope and is a non-starter.
  - **Preferred path**: cashier hands terminal to customer; customer keys card on the terminal PIN pad (or tap / insert). SDK call is the same `charge(..., allowManualKey: true)`; terminal UI prompts for keyed entry. Raw digits never leave the terminal.
  - **Cardholder-not-present path** (phone orders, back-office): BlockChyp "virtual-terminal" / tokenization call — SDK presents BlockChyp's own secure keyed-entry sheet that tokenizes inside the SDK process; we get `{token, last4, brand}` back. Still no PAN on our disk or our server.
  - **Role-gated** — manager PIN required before the sheet opens (audit entry with actor + amount + reason).
  - **Last4 + brand + auth code** only in our GRDB / server ledger. Never the PAN. Ever.
  - **No photo / screenshot of card.** Camera attachments on payment screens explicitly blocked (blur on background per §28.3).
  - **Same sovereignty rule** — BlockChyp is the single permitted payment peer; no Stripe / Square / PayPal SDK fallbacks anywhere in the bundle.
  - **Offline** — manual-keyed not available offline. Cloud-relay vs local mode same as §17.3: needs outbound path to BlockChyp for the tokenization call. If fully offline, disable manual-keyed option with tooltip "Requires internet to tokenize."
- [ ] **Gift card** — scan / key gift-card #; `POST /gift-cards/redeem` with amount; remaining balance displayed.
- [ ] **Store credit** — auto-offer if customer has balance; slider "Apply X of $Y available".
- [ ] **Check** — check # + bank + memo; no auth, goes to A/R.
- [ ] **Account credit / net-30** — role-gated; only if customer has terms set; adds to open balance.
- [ ] **Financing (if enabled)** — partner link (Affirm/Klarna) → QR/URL for customer to complete on their phone; webhook completes sale.
- [ ] **Split tender** — add tender → shows remaining due → repeat until 0; show running "Paid / Remaining" card.

### 16.7 Receipt & hand-off
- [x] **On-device rendering pipeline per §17.4** (contract enforced via `ReceiptPrinter`/`PosReceiptRenderer`). Single SwiftUI `ReceiptView` deferred to full printer SDK work.
- [x] **Receipt preview (text/HTML)** — `PosReceiptRenderer.text(_:)` + `html(_:)` deterministic render from `PosReceiptRenderer.Payload`. Live SwiftUI preview deferred.
- [ ] **Thermal print** — `ImageRenderer(content: ReceiptView(...))` → bitmap → ESC/POS raster to MFi printer (§17).
- [ ] **AirPrint** — fallback for non-MFi: same `ReceiptView` rendered to local PDF file URL via `UIGraphicsPDFRenderer`; hand the file URL (not a web URL) to `UIPrintInteractionController`.
- [x] **Email** — `POST /notifications/send-receipt` wired (soft-absorbs 400/404). PDF attachment deferred to §17.4 pipeline.
- [x] **SMS** — `POST /sms/send` wired. Tracking short-link routing deferred to §53.
- [ ] **Download PDF** — `.fileExporter` pointed at locally-rendered PDF; filename `Receipt-{id}-{date}.pdf`.
- [ ] **QR code** — rendered inside `ReceiptView` via `CIFilter.qrCodeGenerator`; encodes public tracking/returns URL (tokenized, no auth required by recipient).
- [ ] **Signature print** — captured `PKDrawing` / `PKCanvasView` image composed into the view, printed as part of the same bitmap.
- [ ] **Gift receipt** — `GiftReceiptView` (price-hidden variant) uses same model.
- [ ] **Persist the render model** — snapshot `ReceiptModel` persisted at sale close so reprints are byte-identical even after template / branding changes.

### 16.8 Post-sale screen
- [x] **Glass "Sale complete" card** — `PosPostSaleView` with 600ms spinner → success. Confetti animation deferred.
- [x] **Summary tile** — total + method label. Full tender breakdown + sale # deferred.
- [x] **Next-action CTAs** — New sale / Email / Text / Print (disabled). ⌘N/⌘R shortcuts deferred. Print gift receipt deferred.
- [ ] **Auto-dismiss** after 10s → empty catalog + cart for next customer.
- [ ] **Cash drawer kick** — pulse drawer via printer ESC command if cash tender used.

### 16.9 Returns / refunds
- [x] **Entry** — POS toolbar "Process return" button (⌘⇧R) → `PosReturnsView` search by order/phone.
- [ ] **Original lookup** — show invoice detail with per-line checkbox + "Qty to return" stepper.
- [x] **Reason required** — text field + tender picker in `PosRefundSheet`. Dropdown presets deferred.
- [ ] **Restock flag** — per line: return to inventory (increment) vs scrap (no increment).
- [x] **Refund amount** — editable cents input in sheet. Per-line calc + restocking fee deferred.
- [ ] **Tender** — original card (BlockChyp refund with token) / cash / store credit / gift card issuance.
- [ ] **Manager PIN** — required above $X threshold (tenant config).
- [x] **Audit** — `POST /pos/returns` with `/refunds/credits/:customerId` fallback. "Coming soon" banner on 404/501.
- [ ] **Receipt** — "RETURN" printed; refund amount; signature if required.

### 16.10 Cash register (open/close)
- [x] **Open shift** — `OpenRegisterSheet` presented on POS mount when no session via fullScreenCover. Opening float input (single aggregate cents, per-denomination deferred). Local-first via `CashRegisterStore`. Employee PIN + server sync deferred.
- [ ] **Mid-shift** — "Cash drop" button (remove excess to safe) with count + signature.
- [x] **Close shift** — `CloseRegisterSheet` with counted/expected/notes + `CashVariance` band. Over/short color coded. Per-denomination count + mandatory note threshold deferred.
- [x] **Z-report** — `ZReportView` renders tiles + variance card. Auto-print/email-to-manager deferred to §17.4 pipeline.
- [ ] **Shift handoff** — outgoing cashier closes → incoming opens fresh; seamless transition.
- [ ] **Blind-count mode** — cashier doesn't see expected total until after count (loss prevention).
- [ ] **Tenant config** — enforce mandatory count vs skip allowed; skip requires manager PIN.

### 16.11 Anti-theft / loss prevention
- [x] **Void audit** — `Cart.removeLine(id:reason:managerId:)` logs `void_line`/`delete_line` via `PosAuditLogStore` (GRDB migration 005). Fire-and-forget Task never blocks cashier.
- [x] **No-sale audit** — POS overflow ⋯ "No sale / open drawer" presents `ManagerPinSheet`; on approval logs `no_sale` event.
- [x] **Discount ceiling** — `PosCartDiscountSheet` checks `PosTenantLimits.maxCashierDiscountPercent/Cents`; over → nested `ManagerPinSheet`; on approval logs `discount_override` with originalCents + appliedCents.
- [x] **Price override alert** — `PosEditPriceSheet` gates override when delta ≥ `priceOverrideThresholdCents`; logs `price_override`.
- [x] **Delete-line audit** — `Cart.removeLine` without `managerId` logs `delete_line`; ghosted on Z-report via `ZReportAggregates` loss-prevention tile (void/no-sale/discount-override counts).

### 16.12 Offline POS mode
- [ ] **Local catalog** — full inventory + pricing cached (GRDB), daily refresh on launch.
- [ ] **Offline sale** — queue to GRDB sync-queue; temp IDs; BlockChyp offline-auth or skip card (cash only).
- [ ] **Sync replay** — when online, push sales in order; handle server rejection (price changed, item OOS) with staff dialog.
- [ ] **Offline banner** — persistent glass chip "Offline — sales will sync" at top of POS.
- [ ] **Stop-sell** — if any part of catalog > 24h stale, warn before sale.

### 16.13 Hardware integration points (see §17 for detail)
- [ ] Barcode scanner (camera + MFi Socket Mobile / Zebra).
- [ ] BlockChyp terminal.
- [ ] MFi receipt printer (Star TSP100 / Epson TM-m30).
- [ ] Cash drawer (via printer kick).
- [ ] Customer-facing iPad (second screen for tip / signature).
- [ ] Bluetooth scale (deli / weighted items).

### 16.14 iPad-specific POS
- [ ] **3-column layout** — catalog + cart + customer panel.
- [ ] **Customer-facing display** — secondary iPad via AirPlay mirroring or external display shows cart + tip prompts.
- [x] **Magic Keyboard shortcuts** — ⌘N (new custom line), ⌘⇧R (return), ⌘P (pay/charge), ⌘K (customer pick), ⌘H (hold), ⌘⇧H (resume holds), ⌘⇧D (discount), ⌘⇧T (tip), ⌘⇧F (fee), ⌘⇧⌫ (clear cart). ⌘F search focus + ⌘⇧V void deferred.
- [ ] **Apple Pencil** — tap to add to cart, double-tap for 2, hover for preview on iPad Pro.
- [ ] **Drag items** — drag from catalog to cart with haptic feedback.

### 16.15 Membership / loyalty integration
- [ ] **Member discount** — auto-apply if customer is a member (see §40).
- [ ] **Points earned** — displayed on receipt.
- [ ] **Points redemption** — toggle "Use X points ($Y off)" inline.
- [ ] **Member-only products** — grayed for non-members.
- [ ] POS cart: `PKPaymentButton`; customer taps → Face ID → tokenized payment routed via BlockChyp gateway (§17.3). Fallback to insert-card if Apple Pay unavailable.
- [ ] Public payment link page uses `PKPaymentAuthorizationController`; Merchant ID `merchant.com.bizarrecrm`.
- [ ] Apple Pay Later: not initially; leave to BlockChyp; re-evaluate post-Phase-5.
- [ ] Pass management: three distinct pass types — membership (§38), gift card (§40), loyalty (§38). Update via PassKit APNs on value / tier change.
- [ ] Merchant domain verification for public payment pages (`/.well-known/apple-developer-merchantid-domain-association`).
- [ ] Tap to Pay on iPhone: iPhone XS+ with separate Apple Developer approval; Phase 4+ eval, its own scope.
- [ ] Sovereignty: tokens flow Apple → BlockChyp; raw PAN never on our server or iOS app (§17.3 PCI posture).
- [ ] CFD (customer-facing display) use case: POS terminal facing customer shows running cart; audio cue on add-item plays positional sound toward customer (AirPods Pro spatial)
- [ ] Scanner feedback: beep on scan plays spatial from "upper-right" to feel more physical
- [ ] Restraint: audio secondary to haptic; always optional (Settings → Audio); mute in silent mode per iOS convention
- [ ] Secondary scene: new `UIScene` for external display; detect `UIScreen.connectionNotification`; mirror cart state via shared model
- [ ] Layout: top = shop logo + tenant-configured tagline; middle = cart lines + running total; bottom = current line highlighted as added; large tax + total; payment prompt "Insert / tap card" with animated arrow when BlockChyp terminal ready
- [ ] Receipt/thank-you: post-approval confetti (respect Reduce Motion) + "Thank you!" + QR for Google review / membership signup; auto-dismiss after 10s
- [ ] Signature: customer signs on secondary display on Pencil-compatible iPad; else signs on terminal
- [ ] Marketing slideshow: idle >30s between sales rotates tenant-configured slides (promos, upcoming events); tap anywhere exits
- [ ] Multi-language: customer can tap flag to switch language; decoupled from cashier's app language
- [ ] Privacy: never show cashier personal data (email/phone/other customers); no cross-sale persistence on display
- [ ] Full register accelerators on iPad hardware keyboard
- [ ] Cart: ⌘N new sale, ⌘⇧N hold/park, ⌘R resume held, ⌘+/⌘− qty on focused line, ⌘⌫ remove line, ⌘⇧⌫ clear cart (with confirm)
- [ ] Lookup: ⌘F focus product search, ⌘B focus barcode input, ⌘K customer lookup palette
- [ ] Payment: ⌘P open payment sheet, ⌘1 cash, ⌘2 card, ⌘3 gift card, ⌘4 store credit, ⌘⇧P split tender
- [ ] Receipt: ⌘⇧R reprint last, ⌘E email receipt, ⌘S SMS receipt
- [ ] Admin: ⌘M manager PIN prompt, ⌘⌥V void current sale, ⌘⌥R open returns
- [ ] Navigation: Tab cycles cart → discount → tender
- [ ] Navigation: arrow keys scroll catalog grid
- [ ] Discoverability: ⌘? shows overlay (§23.1)
- [ ] Checkout sheet has "Gift receipt" switch
- [ ] Content: item names + qty present; prices hidden; totals hidden
- [ ] Return-by date + policy printed on gift receipt
- [ ] QR with scoped code: enables one-time return without revealing price to recipient
- [ ] Channels: print + email + SMS + AirDrop
- [ ] Return handling: gift return credits store credit (§40) by default unless paid-for matches card on file
- [ ] Partial gift receipt via per-line toggle
- [ ] Types: percentage off (whole cart / line / category)
- [ ] Types: fixed $ off (whole cart / line)
- [ ] Types: Buy-X-get-Y
- [ ] Types: tiered ("10% off $50+, 15% off $100+, 20% off $200+")
- [ ] Types: first-time customer
- [ ] Types: loyalty tier (§38)
- [ ] Types: employee discount by role
- [ ] Stacking: configurable stackable vs exclusive
- [ ] Stacking order: percentage before fixed before tax (tenant-configurable)
- [ ] Limits: per customer, per day, per campaign
- [ ] Limits: min purchase threshold
- [ ] Limits: excluded categories
- [ ] Auto-apply on each cart change without staff action
- [ ] Banner shows "N discounts applied"
- [ ] Manual override: cashier adds ad-hoc discount (if permitted) → reason prompt + audit
- [ ] Manager PIN required above threshold
- [ ] Server validation: iOS optimistic, server re-validates to prevent fraud
- [ ] Reporting: discount effectiveness (usage, revenue impact, margin impact)
- [ ] Model: code string (human-friendly like `SAVE10`)
- [ ] Model: discount rule linkage (§16)
- [ ] Model: valid from/to
- [ ] Model: usage limit (total + per customer)
- [ ] Model: channel restriction (any / online only / in-store only)
- [ ] POS checkout sheet has "Coupon" field with live validation showing discount applied
- [ ] QR coupons: printable/emailable QR containing code; scan at checkout auto-fills
- [ ] Abuse prevention: rate-limit attempts per device
- [ ] Abuse prevention: invalid attempts logged to audit
- [ ] Affiliate codes: tie coupon code to staff member for sales attribution
- [ ] Time-based: happy hour 3-5pm = 10% off services; weekend pricing adjustments
- [ ] Volume: buy 3 cases 5% off each, buy 5 cases 10%
- [ ] Customer-group: wholesale pricing for B2B tier
- [ ] Location-based: per-location pricing overrides (metro vs suburb)
- [ ] Promotion window: flash sales with on/off toggle + countdown timer visible to cashier
- [ ] UI at Settings → Pricing rules
- [ ] Rule list with priority order
- [ ] Live preview: "Apply to sample cart" simulator
- [ ] Conflict resolution: first matching rule wins (priority)
- [ ] Explicit stack rules if tenant configures
- [ ] Effective dates: schedule rules to auto-activate/deactivate
- [ ] Calendar view of scheduled rules
- [ ] Live recompute: animate tick-up/tick-down per digit with small font-weight shift.
- [ ] Discount highlight: flash discount line on apply; strike-through original → new.
- [ ] Pending server validation: subtle shimmer on price until response finalizes.
- [ ] Mismatch resolution: banner "Tax recomputed (+$0.03)" when server total differs.
- [ ] A11y: screen reader announces new total on change (debounced).
- [ ] Sale record schema: local UUID + timestamp + lines + tenders + idempotency key.
- [ ] Receipt printing: "OFFLINE" watermark until synced; post-sync reprint available without watermark.
- [ ] Card tenders: BlockChyp offline capture (where supported) captures card + holds auth + settles on reconnect; manager alert on declined auth at settle; configurable max offline card amount ($100 default).
- [ ] Cash tenders fully offline OK (no auth needed).
- [ ] Gift-card redemption requires online: error "Card balance lookup needs internet"; fallback accept as IOU with manager approval.
- [ ] Sync on reconnect: FIFO flush, idempotency key prevents duplicate ledger, success clears watermark, failures → dead-letter (§20).
- [ ] Audit: record offline duration + sync time per sale; manager report like "3 sales made during 20min outage — all reconciled."
- [ ] UI: outage banner "Offline mode — N sales queued"; dashboard tile tracks queue depth.
- [ ] Security: SQLCipher encryption for offline sales; card data tokenized before store, raw PAN never persisted.
- [ ] See §6 for the full list.

---
## §17. Hardware Integrations

_Requires Info.plist keys (written by `scripts/write-info-plist.sh`): `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, `NSMicrophoneUsageDescription`, `NFCReaderUsageDescription`. MFi accessories need `UISupportedExternalAccessoryProtocols` array._

### 17.1 Camera (photo capture)
- [x] **Wrapper** — `CameraService` actor in `Packages/Camera` wraps `AVCaptureSession` with `setTorch`/`setZoom`/`capturePhoto(format:quality:)`. Commit `e9aa17b`.
- [x] **Ticket photos** — `CameraCaptureView(mode: .multi)` with count pill. EXIF strip via `CIImage` orientation filter.
- [x] **Customer avatar (partial)** — `CameraCaptureView(mode: .single)` ships; circular crop preview deferred.
- [x] **Expense receipts** — `ReceiptEdgeDetector.detectQuadrilateral(_:)` via `VNDetectRectanglesRequest` + `ocrTotal(_:)` via `VNRecognizeTextRequest` bottom-up currency regex.
- [x] **Storage** — `PhotoStore` actor: `stage → tmp/photo-capture/`, `promote → AppSupport/photos/{entity}/{id}/`, `discard`, `listForEntity`.
- [x] **Compression** — iterative retry to ≤ 1.5 MB per photo in `CameraService.capturePhoto`.
- [x] **Annotations** — `PhotoAnnotationView` with `PKCanvasView` + `PKToolPicker`; `captureAnnotated()` flattens base + ink.
- [x] **Photos library** — `PhotoCaptureView` wraps `PhotosPicker` with `selectionLimit: 10`, inline 3-col grid + tap-to-remove. Limited-library UX deferred.
- [x] **Permissions UX** — `CameraCaptureView` + `PosScanSheet` glass permission-denied card with `UIApplication.openSettingsURLString` CTA.
- [ ] **Mac (Designed for iPad)** — continuity camera via FaceTime-HD → same `AVCaptureSession` code works.
- [x] **Live text** — `LiveTextView` (iOS 16+) with `ImageAnalysisInteraction` + `onTextRecognized` for IMEI/serial extraction.

### 17.2 Barcode scan
- [x] **`DataScannerViewController`** (iOS 16+) — `PosScanSheet` ships ean13/ean8/upce/code128/qr. `code39` not enabled yet.
- [x] **Bindings (partial)** — POS add-to-cart wired via `PosSearchPanel` query-fill + auto-pick. Inventory lookup / Stocktake / Ticket IMEI / Customer bindings TBD.
- [ ] **Torch** button, zoom (pinch), region-of-interest overlay.
- [x] **Feedback** — haptic success on auto-pick via `BrandHaptics.success()`. Color flash + chime deferred.
- [ ] **Multi-scan mode** — POS/stocktake can keep scanning; tap-to-stop.
- [ ] **Offline lookup** — hit local GRDB cache first; if miss + online → server; if miss + offline → toast "Not in local catalog".
- [ ] **Printed/screen code** — both supported.
- [x] **Fallback manual entry** — search field on POS accepts typed SKU/barcode.
- [ ] **External scanners** — MFi Socket Mobile / Zebra SDK integration; scanner types as HID keyboard fallback.
- [ ] **Mac** — `DataScannerViewController` unavailable on Mac Catalyst; feature-gate to manual entry + continuity camera scan.

### 17.3 Card reader — BlockChyp

**Architecture clarification (confirmed against BlockChyp docs + iOS SDK README, April 2026).** BlockChyp is a **semi-integrated** model with two communication modes the SDK abstracts behind the same API calls. Our app never handles raw card data either way — terminals talk to the payment network directly; we only receive tokens + results. Per-terminal mode is set at provisioning on the BlockChyp dashboard (cloud-relay checkbox).

**No Bluetooth.** BlockChyp SDK supports IP transport only (LAN or cloud-relay). Do not build any `CoreBluetooth` / MFi / BLE pairing path for the card reader. `NSBluetoothAlwaysUsageDescription` covers other peripherals (printer, scanner, scale) — never the terminal.

- **Local mode** — SDK resolves a terminal by name via the "Locate" endpoint, then sends the charge request straight to the terminal's LAN IP over the local network. Terminal talks to BlockChyp gateway / card networks itself, returns result direct to SDK on LAN. Lowest latency; survives internet blip as long as gateway uplink from terminal is OK. Preferred for countertop POS where iPad + terminal share Wi-Fi.
- **Cloud-relay mode** — SDK sends request to BlockChyp cloud (`api.blockchyp.com`); cloud forwards to terminal via persistent outbound connection the terminal holds. Works when POS and terminal are on different networks (web POS, field-service tech whose iPad is on cellular, multi-location routing). Higher latency; connection-reset-sensitive.
- **SDK abstracts the mode.** Same `charge(...)` call; the SDK's terminal-name-resolution picks local vs cloud path. Developer writes one code path; deployment-time setting picks the route.

#### Integration tasks
- [!] **CocoaPods integration** — add `Podfile`, add `BlockChyp` pod (`pod 'BlockChyp'` from `cocoapods.org/pods/BlockChyp`), update `project.yml` build phase + CI pod-install step.
- [ ] **Terminal types supported** — BlockChyp-branded smart terminals (Lane/2500, Curve, Zing). Ingenico/Verifone/PAX are the underlying hardware families BlockChyp ships; we don't integrate their stacks directly — all through BlockChyp SDK.
- [ ] **Pair flow** — Settings → POS → Terminal → "Pair new" → scan pairing QR shown on terminal screen or enter terminal name. App calls `terminalLocate(name:)` which returns routing info + local IP if in local mode, or cloud-relay flag if cloud.
- [ ] **Stored credentials** — API key + bearer token in Keychain (`com.bizarrecrm.blockchyp.apikey`, `.bearerToken`). These authenticate to BlockChyp (local or cloud); terminal IP is persisted as a cache hint but re-resolved each session.
- [ ] **Status tile** — Settings shows: terminal name, resolved mode (local / cloud-relay), local IP if applicable, heartbeat status, firmware version (from `terminalStatus`), last test transaction date.
- [ ] **Test ping** — Settings button "Test connection" → `ping` SDK call; green/red.
- [ ] **Charge** — `charge(amount, idempotencyKey)` → SDK picks local or cloud path based on terminal config → terminal prompts cardholder → SDK returns `{approved, authCode, maskedPan, last4, cardBrand, transactionId, token}` → we POST to `/invoices/{id}/payments` with the token + SDK metadata.
- [ ] **PCI scope** — raw card data never enters our iOS app or our server. Terminal handles PAN / EMV / PIN entry; we receive a tokenized reference only. Document this in the PCI evidence pack (§28.x).
- [ ] **Refund** — same-batch void vs cross-batch refund using captured token; same SDK API.
- [ ] **Tip adjust** — pre-batch-close `tipAdjust` call on bar/restaurant tenants.
- [ ] **Batch management** — force-close daily at configurable time; Settings "Close batch now" button calls `batchClose`.
- [ ] **Error taxonomy** — `TerminalUnreachable`, `ConnectionTimeout`, `UserCancelled`, `NetworkDown` (cloud-relay only), `InsufficientFunds`, `Declined`, `PartialAuth`, `ChipReadFailure`, `PINEntryTimeout`. Each maps to human-readable UX copy; don't leak raw BlockChyp codes to cashier.
- [ ] **Offline behavior** — local mode: if iPad internet drops but terminal's own uplink still works, charges can still succeed because terminal → gateway path is independent. Cloud-relay mode: no charges possible without internet. UI must surface which mode is active so cashier knows what offline means.
- [ ] **Fallback when terminal truly unreachable** — offer manual-keyed card entry (role-gated, PIN protected, routes through BlockChyp manual-entry API) OR cash tender OR queue offline sale with "card pending" status for retry on reconnect.
- [ ] **Network requirements doc** — setup wizard tells tenant: firewall must allow outbound `api.blockchyp.com:443` for cloud-relay. Local mode needs iPad + terminal on same subnet or routed LAN reachable on terminal's service port.

### 17.4 Receipt printer (MFi Star / Epson)

**Lesson from Android:** Android build "prints" by handing the system a `https://app.bizarrecrm.com/print/...` URL. Opening that URL requires an authenticated session the printer / share sheet doesn't have → blank page or login wall. **iOS must never do this.** All printable artifacts are rendered on-device from local model data.

#### On-device rendering pipeline (mandatory)
- [x] **No URL-based printing.** `ReceiptPrinter` protocol contract + `NullReceiptPrinter` default enforce local-render discipline. `ReceiptPayload` carries model data, never URLs.
- [ ] **Canonical rendering**: SwiftUI `ImageRenderer(content: ReceiptView(model: ...))` produces the visual once, feeds every output channel.
  - Thermal printer: `ImageRenderer` → `CGImage` → raster ESC/POS bitmap (80mm or 58mm per printer width).
  - AirPrint / PDF: same `ImageRenderer` → `UIGraphicsPDFRenderer` → multi-page PDF.
  - Share sheet: PDF file URL in `UIActivityViewController`.
  - Email / SMS attachments: PDF.
  - Preview in app: same `ReceiptView` rendered live in a scroll view.
- [ ] **Single `ReceiptView` per document type** — `ReceiptView`, `GiftReceiptView`, `WorkOrderTicketView`, `IntakeFormView`, `ARStatementView`, `ZReportView`, `LabelView`. Each takes a strongly-typed model. Same view backs print + preview + PDF + email attachment.
- [ ] **Model is self-contained** — `ReceiptModel` carries every value needed (business logo `Data`, shop name, address, line items, totals, payment auth last4, timestamp, tenant footer). Zero deferred network reads inside render. Offline-safe.
- [ ] **Width-aware layout** — `@Environment(\.printMedium)` picks `.thermal80mm`, `.thermal58mm`, `.letter`, `.a4`, `.label2x4`, etc. Fonts + columns adapt; single SwiftUI view, media-specific modifiers.
- [ ] **Rasterization** — thermal path goes through `ImageRenderer.scale = 2.0`, dithered to 1-bit for print head. Preview uses same image so what tenant sees is what prints.
- [ ] **Cut + drawer-kick** — ESC/POS opcodes appended after the rasterized bitmap, not embedded in view. Keeps view pure visual.

#### MFi / model support
- [!] **Apple MFi approval** — 3–6 week lead time; start early. Alternative: Star Micronics webPRNT over HTTP for web-printable models (no MFi); still renders our bitmap, not a URL.
- [ ] **Models targeted** — Star TSP100IV (USB / LAN / BT), Star mPOP (combo printer + drawer), Epson TM-m30II, Epson TM-T88VII.
- [ ] **Discovery** — `StarIO10` + `ePOS-Print` SDKs: LAN scan + BT scan + USB-C (iPad); list paired.
- [ ] **Pair** — pick printer → save identifier (serial number) in Settings → per-station profile (§17).
- [ ] **Test print** — Settings "Print test page": renders `TestPageView` locally (logo + shop name + time + printer capability matrix) via the same pipeline.

#### AirPrint path
- [ ] **`UIPrintInteractionController`** with `printingItems: [localPdfURL]` — never a remote URL.
- [ ] **Custom `UIPrintPageRenderer`** for label printers that want page-by-page rendering instead of a PDF (e.g., Dymo via AirPrint).

#### Fallbacks + resilience
- [ ] **No printer configured** — offer email / SMS with PDF attachment + in-app preview (rendered from same model). Works fully offline; delivery queues if needed.
- [ ] **Printer offline** — job queues in `print_queue` GRDB table (model payload + target printer). Retry on reconnect; alert on repeated failure.
- [ ] **Cash-drawer kick** — via printer ESC command; if printer offline, surface "Open drawer manually" button that logs an audit event so shift reconciliation can show drawer-open vs sale counts. _(Phase-2 scaffold: disabled button with "Pair a receipt printer first" hint is live under the POS totals footer; no ESC opcode wired yet.)_
- [ ] **Re-print** — past receipts re-render from stored `ReceiptModel` snapshot (persisted at the time of sale). Guarantees byte-identical reprint even after tenant branding / template changes.

#### Templates (the views)
- [ ] Receipt, gift receipt (price-hidden variant), work-order ticket label (name + ticket # + barcode), intake form (pre-conditions + signature), A/R statement, end-of-day Z-report, label/shelf tag (§17).

#### ESC/POS builder
- [ ] Helpers for bold / large / centered / QR / barcode / cut / feed / drawer-kick — used only for command sequences around the rasterized bitmap, never to draw text piecewise (text comes from SwiftUI render).

#### Multi-location
- [ ] Per-location default printer selection + per-station profile (§17).

#### Acceptance criterion (copied from lesson)
- [ ] Ship with a regression test: log out of the app, attempt to print a cached recent receipt (detail opened while online, then session ended) → printer must still produce correct output, because rendering is fully local and only the device-to-printer transport is needed.

### 17.5 NFC

**Parity check (2026-04-20).** Server (`packages/server/src/`), web (`packages/web/src/`) and Android (`android/`) have **zero** NFC implementation today. No `nfc_tag_id` column, no `/nfc/*` routes, no Android `NfcAdapter` usage. Building it in iOS first would create a feature that only works when an iPhone reads it, with nowhere on the server to store it and no way for web / Android to consume it. **Do not implement until cross-platform parity lands.** Cross-platform item tracked in root `TODO.md` as `NFC-PARITY-001`.

**How iOS would read / write, for when parity is funded:**
- **Reader is the iPhone itself** — `CoreNFC` framework. No external USB / BT reader needed.
  - Hardware floor: iPhone 7+ can read NDEF; iPhone XS+ supports background tag reading ("Automatic"); `NFCTagReaderSession` (foreground) works on all iPhone 7+.
  - iPad: only iPad Pro M4+ has an NFC antenna. Older iPads: feature gracefully disabled; button hidden.
- **Entitlement** — `com.apple.developer.nfc.readersession.formats` with `TAG` (ISO7816 / MIFARE / FeliCa) or `NDEF`.
- **Info.plist** — `NFCReaderUsageDescription` ("Scan your device tag to attach to a repair ticket.") + `com.apple.developer.nfc.readersession.iso7816.select-identifiers` for any ISO-7816 AIDs.
- **Session types**: `NFCNDEFReaderSession` for NDEF-formatted tags (simple, preferred); `NFCTagReaderSession` for raw MIFARE / NTAG / FeliCa when NDEF insufficient.
- **Write path** — `NFCNDEFReaderSession` with `connect(to:)` + `writeNDEF(_:)`. Tag must be writable (not locked).
- **Not supported on iOS**: Host Card Emulation (receiving NFC from other phones), which rules out "tap customer's phone to our iPhone" flows. If we ever want that, Android is the required platform.

**Tasks (blocked until parity):**
- [ ] NFC-PARITY-001 (root TODO) resolved — server schema + web UX + Android implementation done first.
- [ ] **Core NFC** read — scan tag with device serial → populate Ticket device-serial field.
- [ ] **Core NFC write** (optional) — write tenant-issued tag to a customer device for warranty tracking.
- [ ] **NDEF vs raw** — NDEF primary; raw MIFARE for inventory tags if tenant requests.
- [ ] **Graceful disable** — `NFCReaderSession.readingAvailable` false (iPad, iPhone 6 or earlier) → hide all NFC UI.

**Already unblocked (independent of parity):**
- [ ] **Apple Wallet pass** — customer loyalty card (see §40, §38, §41) added via `PKAddPassesViewController`. This is `PassKit`, not `CoreNFC`. Works today.

### 17.6 Scale (Bluetooth)
- [ ] **Target** — Dymo M5, Brecknell B140 (Bluetooth SPP); low priority unless tenant requests.
- [ ] **Read weight** — stream via CoreBluetooth → cart line "Weighted item" accepts reading.
- [ ] **Tare / zero** — button in POS when scale selected.

### 17.7 Bluetooth / peripherals shell
- [ ] **Permissions** — Bluetooth request with rationale copy.
- [ ] **Device shelf** — Settings → Devices shows all paired (scanner, printer, terminal, scale, customer display) with status dots.
- [ ] **Reconnect** — auto-reconnect on launch; surface failures in status bar glass.

### 17.8 Customer-facing display
- [ ] **Dual-screen** — iPad with external display via USB-C/HDMI → cart mirror + tip prompt.
- [ ] **Handoff prompt** — "Customer: please sign" / "Tip amount" on external display.
- [ ] **AirPlay** — fallback via AirPlay to Apple TV.

### 17.9 Apple Watch companion

Not an iOS feature per se; separate product surface (own entitlements, TestFlight lane, App Store binary, review cycle). Tracked as `WATCH-COMPANION-001` in root `TODO.md` pending scope decision. iOS work on this section is blocked until that item resolves.

Candidate scope when revisited (for reference): clock in / out complication, new-ticket / SMS push forwarding, reply-by-dictation. Non-goal: full CRM browsing on watch.

### 17.10 Accessibility hardware
- [ ] **Switch Control** — POS primary actions reachable.
- [ ] **Voice Control** — all named buttons reachable; custom names for numeric keys.
- [ ] Tools: Pen (thickness slider, 10 color presets + custom), Highlighter (semi-transparent yellow / pink / green), Arrow (auto-head), Rectangle / Oval / Freehand, Text box (font size + color), vector-aware Eraser. Unlimited undo / redo within session.
- [ ] Palette: swatches as glass chips; tenant brand color auto-added.
- [ ] Stamp library: Arrow / Star / circled number / condition tags ("cracked", "dented", "missing"); drag-drop onto image.
- [ ] Layers: base photo + annotation layer stored separately (revert-to-original possible); export flattens.
- [ ] Apple Pencil: `PKCanvasView` / `PencilKit` pressure + tilt; palm rejection on iPad; double-tap Pencil toggles last tool.
- [ ] Crop / rotate / auto-enhance (brightness / contrast).
- [ ] OCR via `VNRecognizeTextRequest`: "Copy text from image" context action.
- [ ] AirPrint via `UIPrintInteractionController` handed a locally-rendered PDF file URL (never a web URL — Android regression lesson §17.4).
- [ ] Paper sizes: Letter (US) / A4 (EU) / Legal / 4×6 receipt / 80mm thermal / 58mm thermal. Default per tenant in Settings → Printing.
- [ ] Thermal printer via Star SDK + Epson ePOS SDK (Swift wrapper). Transports: MFi Bluetooth, Wi-Fi, USB (Lightning/USB-C). Multi-printer per station (§17).
- [ ] `PrintService` class: queue with retries, toast "Print queued, 1 pending", reprint button in queue UI.
- [ ] Cash-drawer kick via printer ESC opcode on cash tender (§17).
- [ ] Preview always before print (first-page mini render).
- [ ] PDF share-sheet fallback when no printer configured.
- [ ] Receipt template editor (Settings → Printing): header logo + shop info + body (lines / totals / payment / tax) + footer (return policy, thank-you, QR lookup) + live preview.
- [ ] Print works offline — printer on local network or Bluetooth has no internet dependency.
- [ ] Support symbologies: EAN-13/EAN-8, UPC-A/UPC-E, Code 128, Code 39, Code 93, ITF-14, DataMatrix, QR, Aztec, PDF417
- [ ] Priority per use-case: Inventory SKU Code 128 primary + QR secondary; retail EAN-13/UPC-A auto-detect; IMEI/serial Code 128 or bare numeric; loaner/asset tag QR with scan-to-view URL
- [ ] Scanner via `VNBarcodeObservation`: recognize all formats concurrently
- [ ] Preview layer marks detected code with glass chip + content preview; tap chip to accept
- [ ] Continuous scan mode: scan → process → beep → ready for next without closing camera
- [ ] Checksum validation per symbology (EAN mod 10, ITF mod 10, etc.); malformed → warning toast + no action
- [ ] Tenant bulk relabel: Inventory "Regenerate barcodes" for all SKUs → print via §17
- [ ] Gift cards: unique Code 128 per card (§40)
- [ ] A11y: VoiceOver announces scanned code and matched item
- [ ] Entry: any past invoice/receipt → detail → Reprint button
- [ ] Entry: from POS "Recent sales" list
- [ ] Options: printer choice (if multiple configured)
- [ ] Options: paper size (80mm / Letter)
- [ ] Options: number of copies
- [ ] Tenant-configurable: require reason for reprints older than 7 days (e.g. "Customer lost it", "Accountant request")
- [ ] Audit entry (§50) per reprint
- [ ] Fallback: no printer → PDF share
- [ ] Entry from customer detail / ticket detail → "Scan document"
- [ ] Use `VNDocumentCameraViewController`
- [ ] Multi-page scan with auto-crop + perspective correction
- [ ] Reorder / delete pages before save
- [ ] OCR via `VNRecognizeTextRequest`, text searchable via FTS5
- [ ] Output: PDF (preferred) or JPEG at 200 DPI default
- [ ] Auto-classification by keyword: license / invoice / receipt / warranty → suggest tag
- [ ] Privacy: on-device Vision only; no external/cloud OCR
- [ ] Bulk append multiple scans to single file
- [ ] Settings → Hardware → Printer → manual IP entry
- [ ] Optional port (default 9100 raw / 631 IPP)
- [ ] Reachability ping before save
- [ ] Online / offline badge
- [ ] Fallback to Bonjour discovery (§17) if IP changes
- [ ] Recommend tenant set DHCP reservation for printer MAC
- [ ] App shows printer MAC after first connection
- [ ] `NWBrowser` for `_ipp._tcp`, `_printer._tcp`, `_airdrop._tcp`, custom `_bizarre._tcp`
- [ ] Declare `NSBonjourServices` in Info.plist (all needed types up-front, iOS 14+)
- [ ] `NSLocalNetworkUsageDescription` explains local-network use
- [ ] Picker UI grouped by service type
- [ ] Icon per device class
- [ ] Auto-refresh every 10s
- [ ] Manual refresh button
- [ ] `CBCentralManager` peripheral scan
- [ ] MFi cert required for commercial printers
- [ ] Register `bluetooth-central` background mode
- [ ] Maintain connection across app backgrounding (required for POS)
- [ ] `NSBluetoothAlwaysUsageDescription` in Info.plist
- [ ] Settings → Hardware → Bluetooth paired list with connection state
- [ ] Forget button per paired device
- [ ] Surface peripheral battery level where published
- [ ] Low-battery warning
- [ ] Warn when multiple clients share one peripheral
- [ ] Auto-retry on disconnect every 5s up to 30s
- [ ] After 30s, surface "Printer offline" banner
- [ ] Exponential backoff: sustained offline → every 60s to save battery
- [ ] Manual "Reconnect" button bypasses backoff
- [ ] Severity policy: scanner offline silent (badge only)
- [ ] Severity policy: printer offline surfaces banner (POS needs it)
- [ ] Severity policy: terminal offline is a blocker (can't charge cards)
- [ ] Log connection events for troubleshooting
- [ ] Terminal firmware: BlockChyp SDK reports version vs latest
- [ ] Banner: "Terminal firmware outdated — update now"
- [ ] Scheduled update (after-hours default)
- [ ] Printer firmware: Star / Epson / Zebra SDKs expose version + update API
- [ ] Manager-prompted update with user confirm before applying
- [ ] Keep previous firmware available for rollback where supported
- [ ] Show expected downtime duration
- [ ] Warn against firmware update during open hours
- [ ] Never auto-apply without consent
- [ ] Log every firmware attempt + result
- [ ] Use case: shops charging by weight (e.g. scrap metal, parts by weight)
- [ ] Support Bluetooth scales (Dymo M10 / Brecknell / etc.)
- [ ] Support USB via USB-C dongle
- [ ] POS flow: add item → "Weigh" button → live reading capture
- [ ] Zero-tare / re-weigh controls
- [ ] Precision units: grams / ounces / pounds / kilograms
- [ ] Tenant chooses unit system
- [ ] Rate-by-weight pricing rule ("$/lb") with auto-computed total
- [ ] Note: NTEP-certified scale required for commercial US sales (tenant responsibility)
- [ ] Primary path: fire "kick" command via thermal receipt printer's RJ11 cash-drawer port
- [ ] Fire on specific tenders (cash / checks)
- [ ] Settings → Hardware → Cash drawer → enable + choose printer binding
- [ ] Test "Open drawer" button
- [ ] Alternate path: USB-connected direct-to-iPad via adapter (less common)
- [ ] Manager override: open drawer without sale (reconciliation)
- [ ] Manager override requires PIN + audit log
- [ ] Surface open/closed status where drawer reports it via printer bus
- [ ] Warn if drawer left open > 5 minutes
- [ ] Log drawer-open events with cashier + time
- [ ] Anti-theft signal: multiple opens without sale triggers alert
- [ ] Printer-cash-drawer: bind drawer to printer RJ11 port (§17); test button opens drawer.
- [ ] Printer-scanner chain: some wedge scanners route output through printer USB (rarely needed, supported).
- [ ] Printer-scale: no native chain; both connect to iPad directly.
- [ ] Binding profiles: tenant saves "Station 1 = Printer A + Drawer + Terminal X + Scale"; multi-station per location.
- [ ] Station assignment on launch: staff picks station, or auto-detect via Wi-Fi/Bluetooth proximity; profile drives settings.
- [ ] Fallback: graceful degrade (PDF receipt, manual drawer open) if any peripheral in profile fails.
- [ ] Settings → Hardware: per-station peripheral-health dashboard / logs.
- [ ] Doc types: receipt (thermal 80mm + A4 letter), invoice, quote, work order, waiver, labor certificate, refund receipt (thermal/letter), Z-report / end-of-day, tax summary.
- [ ] Engine: `UIGraphicsPDFRenderer` + SwiftUI `ImageRenderer(content:)`; fallback Core Graphics for thermal printers.
- [ ] Structure: header tenant branding, body line items + subtotals, footer terms + signature line + QR for public tracking (§4).
- [ ] A11y: tagged PDFs (searchable/copyable); screen-reader friendly in-app.
- [ ] Archival: generated PDFs on tenant server (primary) + local cache (offline); deterministic re-generation for historical recreation.
- [ ] Preview: live in template editor with real tenant + sample data.
- [ ] Pagination: long invoices span pages with reprinted header + page numbers.
- [ ] See §30 for the full list.

---
## §18. Search (Global + Scoped)

_Server endpoints: `GET /search?q=&type=&limit=`, `GET /customers?q=`, `GET /tickets?q=`, `GET /inventory?q=`, `GET /invoices?q=`, `GET /sms?q=`._

### 18.1 Global search (cross-domain)
- [x] **Shipped** — cross-domain search across customers / tickets / inventory / invoices.
- [ ] **Trigger** — glass magnifier chip in toolbar (all screens) + pull-down on Dashboard + ⌘F.
- [ ] **Command Palette** — see §56; distinct from global search (actions vs data).
- [ ] **Scope chips** — All / Customers / Tickets / Inventory / Invoices / Estimates / Leads / Appointments / SMS / Employees / Expenses / Notes.
- [ ] **Server result envelope** — each hit has `type`, `id`, `title`, `subtitle`, `thumbnail_url`, `badge`; rendered as unified glass cards.
- [ ] **Recent searches** — persisted per user in GRDB; cleared from settings.
- [ ] **Saved / pinned searches** — name a search + save query JSON; surfaces as chip in empty state.
- [ ] **Empty state** — glass card: "Try searching for a phone number, ticket ID, SKU, IMEI, invoice #, or name". Tips list shows what's indexable.
- [ ] **No-results state** — "No matches for 'X'. Try different spelling, scope to All, or search by phone."
- [ ] **Loading state** — skeleton rows in glass cards.
- [ ] **Debounce** — 250ms debounce; cancel prior request on new keystroke (`Task` cancellation).
- [ ] **Keyboard shortcut** — ⌘F to focus search; ⎋ to dismiss; arrow keys navigate; ⏎ to open.
- [ ] **Voice input** — dictation enabled; smart punctuation disabled (names/numbers).
- [ ] **Result ranking** — server provides; iOS respects; recent + pinned boosted client-side.
- [ ] **Type-ahead preview** — top 3 hits in dropdown; "See all" at bottom.
- [ ] **Phone-number match** — strip formatting, match on last 10 digits.
- [ ] **IMEI match** — 15-digit serial lookup; falls through to device-linked ticket.
- [ ] **Barcode/SKU** — scan button in search field → auto-fills + submits.

### 18.2 Scoped search (per-list)
- [ ] **Per-list search bar** — on every list view, top sticky glass search.
- [ ] **Server-driven** — pass `q=` param; cursor pagination preserved.
- [ ] **Filter chip row** below search — status, date range, assignee, etc.
- [ ] **Sort menu** — in toolbar next to search; persists per-list in user defaults.
- [ ] **Clear (x)** button inline.
- [ ] **iPad** — persistent sidebar → list → detail; search stays in list column.

### 18.3 Spotlight (system search)
- [ ] **`CSSearchableIndex`** — index on background: recent 500 customers, 500 tickets, 200 invoices, 100 appointments.
- [ ] **Attributes** — title, contentDescription, thumbnailData (customer avatar / ticket photo), keywords, domainIdentifier (bucket by type).
- [ ] **Update** — on sync, reindex changed items; batch size 100.
- [ ] **Deletion** — when item deleted locally, delete from index.
- [ ] **Deep link** — Spotlight tap passes `uniqueIdentifier` → deep link to `/customers/:id` etc.
- [ ] **Content preview** — Spotlight preview card via `CSSearchableItemAttributeSet.contentURL`.
- [ ] **Privacy** — exclude phone / email from index when device-privacy mode on (Data & Privacy → Apple Intelligence opts).

### 18.4 Saved searches / smart lists
- [ ] **Create smart list** — from any filter state, "Save as smart list" → name + color.
- [ ] **Smart list chip row** — above main list, pinned smart lists as chips.
- [ ] **Auto-count** — smart list shows live count badge (updated on sync).
- [ ] **Share smart list** — share JSON filter to another staff member via deep link.

### 18.5 Voice search / Siri
- [ ] **App Intent** — "Find ticket 1234", "Show customer John Smith", "Search SMS for refund" (see §24).
- [ ] **Dictation** inline in search field.

### 18.6 Natural-language search (stretch)
- [ ] **Backend NLQ** — if server adds `/search/nlq`, route "Tickets waiting > 3 days" → structured query.
- [ ] **Fallback** to keyword search if NLQ unavailable.

### 18.7 Offline search
- [ ] **Local index** — GRDB FTS5 virtual tables for customers, tickets, inventory.
- [ ] **Offline result** stale badge — indicate from-cache date.
- [ ] **Merge** — online + offline results deduplicated by id.

### 18.8 Privacy gates
- [ ] **SSN / tax-ID** — never searchable; hashed server-side.
- [ ] **Sensitive notes** — only searchable by authors/admins (server enforces).
- [ ] FTS5 pipeline: on each GRDB insert/update of indexed models (tickets / customers / inventory / invoices / sms messages), triggers update the matching FTS5 virtual table.
- [ ] Stop-word list per locale; stemming via Snowball (English) or language-specific.
- [ ] Tables: `ticket_fts`, `customer_fts`, `inventory_fts`, `invoice_fts`, `sms_fts` — each mirrors searchable columns + `rowid` for join.
- [ ] Rank: BM25 native; timestamp boost for recency; exact-match IMEI / phone / email bumps to top.
- [ ] Synonyms (tenant-defined): "iphone" → "iPhone"; "lcd" → "screen"; "batt" → "battery".
- [ ] Cap index size per entity; rebuild on schema migration; background incremental reindex in `BGAppRefreshTask` (§21).
- [ ] Privacy: full-text index lives inside SQLCipher; encrypted at rest (§28.2).
- [ ] Fuzzy: Levenshtein edit distance up to 2 for short queries; fallback to substring.
- [ ] See §25 for the full list.

---
## §19. Settings

_Parity with web Settings tabs. Server endpoints: `GET/PUT /settings/profile`, `GET/PUT /settings/security`, `GET/PUT /settings/notifications`, `GET/PUT /settings/organization`, `GET /settings/integrations`, `GET/PUT /settings/tickets`, `GET/PUT /settings/invoices`, `GET/PUT /settings/tax`, `GET/PUT /settings/payment`, `GET/PUT /settings/sms`, `GET/PUT /settings/automations`, `GET/PUT /settings/membership`, `GET/PUT /settings/customer-groups`, `GET/PUT /settings/roles`, `GET/PUT /settings/statuses`, `GET/PUT /settings/conditions`, `GET/PUT /settings/device-templates`, `GET/PUT /settings/repair-pricing`, `GET /audit-logs`, `GET /billing`._

### 19.0 Shell
- [ ] **iPad/Mac** — `NavigationSplitView`: left sidebar is setting categories (list), detail pane hosts each tab's form; deep-linkable per tab (`bizarrecrm://settings/tax`).
- [ ] **iPhone** — `List` of categories → push to individual tab views.
- [ ] **Role gating** — non-admins see only Profile / Security / Notifications / Appearance / About; admin gates hidden tabs behind `role.settings.access`.
- [ ] **Search Settings** — `.searchable` on Settings root (⌘F) searching category labels + field labels; jumps straight to tab + highlights field.
- [ ] **Unsaved-changes banner** — sticky glass footer with "Save" / "Discard" when any tab form is dirty.

### 19.1 Profile
- [ ] **Avatar** — circular tap → action sheet (Camera / Library / Remove).
- [ ] **Fields** — first/last name, display name, email, phone, job title, bio.
- [ ] **Change email** — server emits verify-email link; banner until verified.
- [ ] **Change password** — current + new + confirm; strength meter; submit hits `PUT /auth/change-password`.
- [ ] **Username / slug** — read-only unless admin.
- [x] **Sign out (primary)** — bottom of page, destructive red. (`Settings/SettingsView.swift` destructive `Button(role: .destructive)` with confirm; calls `onSignOut`; logout wipes `TokenStore` + `PINStore` + `BiometricPreference`.)
- [ ] **Sign out everywhere** — cross-link to §19.2 Security (revokes other sessions; security-scoped, not just this device).

### 19.2 Security
- [ ] **PIN** — 6-digit PIN for quick re-auth (locally enforced).
- [x] **Biometric toggle** — Face ID / Touch ID for re-auth + sensitive screen gates. (`Settings/BiometricToggleRow.swift` in `SettingsView.swift` section "Security".)
- [ ] **Auto-lock timeout** — Immediately / 1 min / 5 min / 15 min / Never; backgrounded app blurred via privacy snapshot.
- [ ] **2FA** — enroll (TOTP QR → Google/Authy/1Password/built-in iCloud Keychain), disable, regenerate backup codes, copy to Notes prompt.
- [ ] **Active sessions** — list device + last-seen + location (IP); revoke.
- [ ] **Trusted devices** — mark "this device is trusted" to skip 2FA.
- [ ] **Login history** — recent 50 logins with outcome + IP + user-agent.
- [ ] **App lock with biometric** on cold launch — toggle.
- [ ] **Privacy snapshot** — blur app in App Switcher.
- [ ] **Copy-paste gate** — opt-in disable for sensitive fields (SSN, tax ID).

### 19.3 Notifications (in-app preferences)
- [ ] **Per-channel toggle** — New SMS inbound / New ticket / Ticket assigned to me / Ticket status change / Payment received / Payment failed / Appointment reminder / Appointment confirmed / Invoice overdue / Estimate sent / Estimate approved / @mention / Low stock / Cash drop alert / Daily summary.
- [ ] **Delivery medium** per channel — Push / Email / SMS / In-app only.
- [ ] **Quiet hours** — start/end time; show icon in tab badge during quiet hours.
- [ ] **Critical overrides** — "Payment failed" and "@mention" can bypass quiet hours (toggle).
- [ ] **"Open System Settings"** button → `UIApplication.openNotificationSettingsURLString` (iOS 16+).
- [ ] **Test push** — admin-only button sends test notification.

### 19.4 Appearance
- [ ] **Theme** — System / Light / Dark; live preview tile.
- [ ] **Accent** — Brand triad: Orange / Teal / Magenta (one-tap); advanced color picker.
- [ ] **Density** — Compact / Comfortable; row height + padding scale.
- [ ] **Glass intensity** — 0–100% slider; <30% falls to solid material (a11y alt).
- [ ] **Reduce motion** — overrides system (for one-user testing).
- [ ] **Reduce transparency** — overrides system.
- [ ] **Font scale** — honors Dynamic Type; extra bump for XL screens.
- [ ] **Sounds** — receive notification sound / scan chime / success / error; master mute.
- [ ] **Haptics** — master toggle + per-event subtle/medium/strong.
- [ ] **Icon** — alt-icon picker (SF Symbol for build, later PNG variants).

### 19.5 Organization (admin)
- [ ] **Company info** — legal name, DBA, address, phone, website, EIN.
- [ ] **Logo** — upload; renders on receipts / invoices / emails.
- [ ] **Timezone** — auto-detect + override.
- [ ] **Currency** — default + allowed.
- [ ] **Locale** — default language.
- [ ] **Business hours** — per day of week with multiple blocks.
- [ ] **Location management** — multi-location tenants: list locations, add/edit/archive; default location per user.
- [ ] **Receipt footer** + invoice footer text.
- [ ] **Terms & policies** — warranty, return, privacy printed on receipts.

### 19.6 Tickets settings (admin)
- [ ] **Status taxonomy** — re-order / rename / add / archive custom statuses; color per status.
- [ ] **Default status** — new tickets start at.
- [ ] **Pre-conditions checklist** — tenant-configurable default list of checks (Back cover cracked? Sim tray? Water damage?).
- [ ] **Conditions** — list (with icons) of device conditions to tick at intake; edit / reorder / add.
- [ ] **Ticket # format** — `{prefix}-{year}-{seq}` tenant-configurable.
- [ ] **SLA rules** — auto-warn after X hours in status Y.
- [ ] **Auto-assignment** — round-robin / load-balanced / manual.
- [ ] **Required fields** at intake (toggle per field).
- [ ] **Device templates** (see §48) — managed here.

### 19.7 Invoices settings (admin)
- [ ] **Invoice # format**.
- [ ] **Net terms** — Due-on-receipt / Net-15 / Net-30 / custom.
- [ ] **Late fee** — percentage + grace period.
- [ ] **Email from** — from-address + reply-to.
- [ ] **Auto-send** reminders — 3 days before due / day of / 3 days after / weekly overdue.
- [ ] **Allowed payment methods** — Card / Cash / Check / ACH / Financing.
- [ ] **Fees** — processing surcharge (% or $); restocking fee default.
- [ ] **Accepted payment methods surface** on customer portal.

### 19.8 Tax
- [ ] **Tax rates** — list (name, rate, applies-to); add/edit/archive.
- [ ] **Nested tax** — state + county + city stacking.
- [ ] **Tax-exempt categories** — services-only vs parts-only.
- [ ] **Per-customer override** — default handled in customer record.
- [ ] **Automated rate lookup** (Avalara/TaxJar integration toggle — stretch).

### 19.9 Payment (BlockChyp + methods)
- [ ] **BlockChyp API key** + terminal pairing (see §17.3).
- [ ] **Surcharge rules** — card surcharge on/off.
- [ ] **Tipping** — enabled / presets (10/15/20) / custom allowed / hide.
- [ ] **Manual-keyed card** allowed toggle. Tenant-level setting that enables §16.6 manual-keyed path. When off, POS hides the option entirely. When on, enforces role gate + manager PIN per §16.6. Even when on, we still don't build native card-entry fields — always BlockChyp SDK's tokenizing sheet or terminal PIN pad.
- [ ] **Gift cards** on/off + format.
- [ ] **Store credit** on/off + expiration.
- [ ] **Refund policy** — max days since sale; require manager above $X.
- [ ] **Batch close time** — auto-close card batch.

### 19.10 SMS / Templates (admin)
- [ ] **SMS provider** status — Twilio / Bandwidth / server-configured.
- [ ] **From number** + optional A2P 10DLC registration status.
- [ ] **Template library** — Ticket-ready / Estimate / Invoice / Payment confirmation / Appointment reminder / Post-service survey.
- [ ] **Variable tokens** — `{customer.first_name}`, `{ticket.status}`, `{invoice.amount}`, `{eta.date}`, etc.; token picker.
- [ ] **Test send** to current user's phone.
- [ ] **Auto-responses** — out-of-hours auto-reply; keywords (STOP / HELP / START).
- [ ] **Compliance** — opt-out keywords, carrier-required footers.
- [ ] **MMS** toggle if plan supports.

### 19.11 Automations
- [ ] **Rule builder** — When [event] Then [action]; events: ticket-created, status-changed, payment-received, etc.; actions: send SMS, send email, assign, add note, create task.
- [ ] **Rule list** + toggle per rule.
- [ ] **Dry-run** — preview recent fires.
- [ ] **Webhooks** — add/edit/remove endpoint URLs + secret; per-event filter.

### 19.12 Membership / loyalty (admin — see §40)
- [ ] **Tiers** — name, threshold, discount %, perks.
- [ ] **Points earn rate** — $ per point.
- [ ] **Points redeem rate** — points per $.
- [ ] **Referral bonus** — sender/receiver credits.
- [ ] **Member-only categories**.

### 19.13 Customer Groups (admin)
- [ ] **List** — group name + member count + discount % + tax exempt.
- [ ] **Members** — search + add / remove.
- [ ] **Pricing overrides** — per-category discount.
- [ ] **Default group** on new customer (rarely).

### 19.14 Roles & Permissions (admin)
- [ ] **Role matrix** — rows (roles) × columns (capabilities); toggles.
- [ ] **Default roles** — Admin / Manager / Technician / Cashier / Viewer.
- [ ] **Custom role** — name + clone from existing.
- [ ] **User → role** assignment in Employees.
- [ ] **Granular caps** — e.g. invoice-void requires manager; price-override requires manager + PIN.

### 19.15 Statuses (generic taxonomy)
- [ ] Shared with Tickets settings; also applies to Estimates / Leads / Appointments — each has its own status taxonomy.

### 19.16 Conditions (device conditions at intake)
- [ ] Icon + name + order; reusable across tenants.

### 19.17 Device Templates / Repair Pricing Catalog (admin — see §50)
- [ ] **Device families** — iPhone / Samsung / iPad / etc.
- [ ] **Models within family** — with service catalog per model.
- [ ] **Service default prices** — screen replace, battery, water damage, back glass, etc.
- [ ] **Parts mapping** — link device-model + service → SKU.

### 19.18 Data Import (admin — see §54)
- [ ] **From RepairDesk / Shopr / MRA / CSV** — wizard.
- [ ] **Dry-run preview** + confirm.
- [ ] **Import history** + rollback.

### 19.19 Data Export
- [ ] **Tenant-wide export** — CSV + JSON + encrypted ZIP via `.fileExporter`.
- [ ] **Per-domain export** — customers.csv / tickets.csv / invoices.csv + line items.
- [ ] **Schedule recurring export** — S3 / Dropbox / iCloud Drive.
- [ ] **Compliance export** — per-customer GDPR/CCPA data package.

### 19.20 Audit Logs (admin — see §55)
- [ ] **Log viewer** — who / what / when; filter by actor / action / entity.
- [ ] **Search + date range**.
- [ ] **Export**.

### 19.21 Billing (tenant billing)
- [ ] **Current plan** — Starter / Pro / Enterprise; usage bars (SMS left, storage, seats).
- [ ] **Change plan** — upgrade/downgrade flow (links to Stripe portal OR in-app StoreKit if chosen).
- [ ] **Invoices for tenant** — own Stripe invoice history.
- [ ] **Payment method** — update card.
- [ ] **Usage metering** — SMS sent, storage, seats added.

### 19.22 Server (connection)
Page purpose: inspect + test the tenant server connection. No tenant-switch button and no sign-out button (sign-out lives in §19.1 Profile — there is a single canonical location). Changing tenant = sign out (§19.1) + sign back in with different creds.
- [x] **Dynamic base URL** — shipped.
- [ ] **Connection test** — latency (ping) + auth check + TLS cert SHA shown.
- [ ] **Pinning** — SPKI pin fingerprint viewer + rotate.
- [ ] **Last-used persistence note** — server URL + username retained in Keychain across sign-out (tokens are NOT retained) so the Login screen pre-fills on return. Implemented at the auth layer, surfaced here for transparency.

### 19.23 Data (local)
- [ ] **Force full sync** — wipes GRDB, re-fetches all domains.
- [x] **Sync queue inspector** — pending writes + retry age + dead-letter (tap to retry / drop). (`Settings/SyncDiagnosticsView.swift` with per-row Retry / Discard backed by `SyncQueueStore`.)
- [ ] **Clear cache** — images + catalog (not queued writes).
- [ ] **Reset GRDB** — nuclear option (sign out + wipe).
- [ ] **Disk usage** — breakdown: images X MB, GRDB Y MB, logs Z MB.
- [ ] **Export DB** (dev build only) — share sheet → `.sqlite` file.

### 19.24 About
- [x] **Version + build + commit SHA** (from `GitVersion`). (partial — `Settings/AboutView.swift` shows version + build via `Platform.appVersion`/`Platform.buildNumber`; commit SHA not yet appended.)
- [ ] **Licenses** — `NSAcknowledgments` auto-generated.
- [x] **Privacy policy**, **Terms of Service**, **Support email** — deep links. (`Settings/AboutView.swift` section "Support" links `mailto:support@bizarrecrm.com`, privacy policy, and terms of service.)
- [ ] **App Store review** — `SKStoreReviewController` after N engaged sessions.
- [ ] **Device info** — iOS version, model, free storage.
- [ ] **Secret gesture** — long-press version 7x → Diagnostics.

### 19.25 Diagnostics (dev/admin)
- [ ] **Log viewer** — `OSLog` stream, filter by subsystem + level.
- [ ] **Network inspector** — last 200 HTTP requests + response + latency; redact tokens.
- [ ] **WebSocket inspector** — live stream of WS frames.
- [ ] **Feature flags** — server-driven + local override.
- [ ] **Glass element counter** overlay — show how many glass layers active (perf).
- [ ] **Crash test button** — force crash to verify symbolication.
- [ ] **Memory / FPS HUD** — toggleable overlay.
- [ ] **Environment** — toggle staging vs production API (dev builds only).

### 19.26 Danger Zone (admin)
- [ ] **Reset tenant data** — destructive; requires typing tenant name.
- [ ] **Rotate encryption key** — re-wrap SQLCipher passphrase.
- [ ] **Close account** — 7-day grace; export triggered.
- [ ] **Transfer ownership**.

### 19.27 Training mode (see §57)
- [ ] **Toggle** — "Training mode" → read-only sandbox against demo data; watermark banner; no SMS/card charges fire. big edit - dont be lazy implementing everythin
- [ ] Server-hosted templates, iOS-cached. Variables: `{{customer.first_name}}`, `{{ticket.id}}`, `{{ticket.status}}`, `{{link.public_tracking}}`, etc. Live preview renders actual values for current context.
- [ ] Categories: status updates / reminders / marketing / receipts / quotes / follow-ups.
- [ ] Composer (§12) "Templates" button → grouped bottom sheet → tap inserts w/ variables auto-filled; editable before send.
- [ ] Tone rewrite via Writing Tools on eligible devices (§12).
- [ ] A/B variants: 50/50 split with open / reply / revenue-attribution tracking.
- [ ] TCPA / CAN-SPAM: marketing templates inject unsubscribe link automatically; server blocks send if absent.
- [ ] Location: Settings → Diagnostics → Dead-letter queue (+ exposed in §19.25 debug-drawer panel).
- [ ] Item row: action type (create-ticket / update-inventory / …), failure reason, first-attempted-at, last-attempt-at, attempt count, last-error.
- [ ] Actions per row: Retry now / Retry later / Edit payload (advanced) / Discard (confirm required).
- [ ] App-root banner if DLQ count > 0: "3 changes couldn't sync — open to fix."
- [ ] Auto-escalation at > 24h: server emails tenant admin (not iOS-sent).
- [ ] Before discard, offer "Export JSON" so user can manually reapply elsewhere.
- [ ] Top-level search bar in Settings: typeahead over all setting labels + synonyms; jumps to matching page with highlight
- [ ] Static index built at compile time from settings metadata; pre-seeded synonyms ("tax"→"Tax rules", "sms"→"SMS provider", "card"→"Payment (BlockChyp)")
- [ ] Results UI grouped by section (Payment/Notifications/Privacy…); tap navigates and highlights setting for 1.5s with subtle pulse
- [ ] A11y: VoiceOver reads "5 results; first: Tax rules in Payment"
- [ ] Empty state: "No settings match 'xyz'. Try synonyms: card, payment, cash."
- [ ] Recently changed: small section at top with last 5 toggles
- [ ] Shake-to-report-bug: dev/staging builds only; `UIResponder.motionEnded(.motionShake)` opens bug-report form (§69); production is opt-in via Settings → Accessibility (subway riders)
- [ ] Shake-to-undo: iOS system gesture; `UndoManager` (§63) hooks in; honor user's iOS setting (Accessibility → Touch → Shake to Undo)
- [ ] Accidental-trigger protection: debounce; ignore shakes during active gestures (scroll/pan)
- [ ] Device-local backup: Settings → Data → Backup now → exports SQLCipher DB + photos to `~/Documents/Backups/<date>.bzbackup` (encrypted bundle); share sheet to Files / iCloud Drive / AirDrop
- [ ] Automatic schedule daily/weekly/off; runs in `BGProcessingTask`; skipped if low battery
- [ ] Restore: Settings → Data → Restore from backup; picker from Files; decrypts via user-supplied passphrase prompt; replaces local DB after confirm; does NOT change server, only local cache
- [ ] Server-side backup orthogonal: tenant server does own cloud backups per tenant; iOS backup is for device-lost recovery onto new phone
- [ ] Encryption: AES-256-GCM with PBKDF2-derived key from passphrase; no cloud passphrase escrow (user's responsibility)
- [ ] Cross-tenant: backup bundle tagged with tenant_id; refuses restore into wrong tenant
- [ ] Use case: shop owner sells shop; app supports reassigning primary admin
- [ ] Flow: current owner → Settings → Org → Transfer ownership; enter new owner email; server sends verification link; new owner clicks link → becomes owner; previous downgraded to admin
- [ ] Safety: 72-hour delay before effective (cancelable); email notifications both parties; audit entry
- [ ] Data ownership: data stays with tenant server; no export required; previous owner still accesses if they remain a user (unless revoked)
- [ ] Payment billing change: separate flow — update billing card / account after handoff
- [ ] Data model per location: weekly schedule (Mon-Sun, open/close), exceptions (holidays, half-days)
- [ ] Per service: allowed booking window within open hours
- [ ] Editor at Settings → Org → Location → Hours
- [ ] Editor supports copy from another location
- [ ] Import US/CA/EU federal holiday lists; tenant unchecks as needed
- [ ] Appointment self-booking (§56) respects hours
- [ ] Outside hours: "Closed" badge on dashboard
- [ ] Outside hours auto-reply on SMS (if opted in) with next-open time
- [ ] Each location carries its own timezone
- [ ] Multi-location view normalizes display to user device timezone with "Store time: X" chip
- [ ] Daylight-saving auto-shift via `TimeZone.current` / `Calendar` APIs
- [ ] "Unexpected closure" button posts in-app banner + auto-SMS to customers with appointments
- [ ] Transactional templates: welcome/verify, ticket status updates (per status), invoice sent, payment receipt, quote sent/approved/declined, appointment confirm/reminder/reschedule/cancel, membership renewal, password reset
- [ ] Marketing templates: monthly newsletter, birthday promo, seasonal sale, abandoned cart (if online store)
- [ ] Engine: server-side via tenant's email gateway (Postmark/SES/SendGrid, tenant choice)
- [ ] iOS triggers via POST /comms/email; never sends directly
- [ ] Credentials stay server-side
- [ ] Template editor on iPad: visual WYSIWYG (drag blocks)
- [ ] Template editor on iPhone: simple text + preview
- [ ] Full editor on web (managers likely prefer)
- [ ] Variables reuse SMS template vocab (§12.1)
- [ ] Auto-injected footer: address, unsubscribe, privacy
- [ ] Send-test-to-self button
- [ ] Preview on device (render)
- [ ] Compliance: CAN-SPAM footer + unsubscribe mandatory; tenant controls, iOS renders
- [ ] Tenants integrate BizarreCRM with QuickBooks/Zapier/Make etc.; all webhook config server-side; iOS surfaces read + small edits
- [ ] iOS surface: Settings → Integrations → list of active integrations
- [ ] Enable/disable toggle per integration
- [ ] View last N events sent per integration
- [ ] Retry failed events
- [ ] Inbound webhooks processed by server only (e.g. Shopify order → create BizarreCRM ticket); iOS shows audit trail only
- [ ] Zapier-like connector — BizarreCRM as Zap source (triggers: ticket.created, invoice.paid, customer.created)
- [ ] Zapier-like connector — BizarreCRM as Zap destination (actions: create ticket, send SMS, update customer)
- [ ] Tenant subscribes on Zapier; OAuth via tenant server
- [ ] API tokens: per-integration, scoped capabilities (like roles §47)
- [ ] Token creation at iOS → Integrations → Tokens → Create
- [ ] Per-token rate limits visible to tenant; alerts when approaching
- [ ] Logs: last 1000 events per integration with replay button for troubleshooting
- [ ] Sovereignty: outbound webhooks go only to tenant-configured URLs; no Zapier shortcut via our infra
- [ ] iOS never calls third-party integration APIs directly
- [ ] Scope limit: per §62 most management stays in Electron desktop app
- [ ] iOS exposes essentials: team invites, roles, business hours, printers, basic settings
- [ ] Guard rails: destructive settings (data wipe, billing cancel) require web/desktop — iOS shows link
- [ ] Rationale: avoid accidental destructive taps on phone
- [ ] Admin view at Settings → Organization
- [ ] Tabs: Team / Locations / Hours / Billing / Branding / API Tokens
- [ ] Each tab read/write where safe, read-only where not
- [ ] Sensitive ops in iOS: password change, 2FA setup
- [ ] Web-only sensitive ops: tenant delete, data export (with email confirm)
- [ ] Audit: every admin op tagged in §50 audit log
- [ ] §19 defines engine; this is the UX surface
- [ ] Settings → Features: list of enabled flags + default states
- [ ] Each row: name, description, scope (tenant / role / user), current value
- [ ] Tap row → drawer with "What this does" + "Who can change" + recent changes
- [ ] Preview toggles: some flags have "Preview" mode for staged rollout to specific users
- [ ] Safety: destructive flags (e.g. "Disable PCI mode") require extra confirm + manager PIN
- [ ] Inheritance chain: tenant default → role override → user override
- [ ] UI shows inheritance chain visually
- [ ] Reset to default: per flag + bulk reset
- [ ] Entry: Settings → Diagnostics → "Export diagnostic bundle"
- [ ] Contents: app version, OS version, device model
- [ ] Contents: feature flags snapshot
- [ ] Contents: last 100 log entries (auto-redacted)
- [ ] Contents: last crash diagnostic
- [ ] Contents: sync queue status
- [ ] Contents: network connectivity summary
- [ ] Format: ZIP of JSON files + README
- [ ] Size capped at 10MB (truncate logs if over)
- [ ] PII redaction: scrub token / password / phone / email before pack
- [ ] Confirmation sheet shows what's included before export
- [ ] Delivery via share sheet: Files / email tenant admin / AirDrop
- [ ] Never auto-upload
- [ ] §69 bug report form can embed diagnostic bundle
- [ ] Device registry per tenant: each iPad / iPhone registered
- [ ] Registry fields: serial, device model, iOS version, location, assigned user, last-seen, app version
- [ ] Encourage Apple Business Manager + MDM (Jamf / Kandji) enrollment for fleet management
- [ ] App reads MDM-managed-configuration keys (server URL, kiosk-mode flag)
- [ ] Owner remote-sign-out from web portal
- [ ] Next launch after remote sign-out shows "Signed out by admin"
- [ ] Daily device heartbeat (tenant-server only)
- [ ] Dashboard tile: "N devices / M online"
- [ ] Bulk MDM-managed app config: tenant URL + flags at install (no user interaction)
- [ ] Server rejects tokens from app versions below policy floor; prompts update
- [ ] Tenant-configurable via Settings → Numbering
- [ ] Separate formats per entity: tickets / invoices / estimates / POs / receipts
- [ ] Placeholder vocabulary: `{YYYY}`, `{YY}`, `{MM}`, `{DD}`, `{LOC}`, `{SEQ:N}` (N-digit zero-padded), `{INIT}` (creator initials)
- [ ] Example: `T-{YYYY}{MM}-{SEQ:5}` → `T-202604-00123`
- [ ] Example: `INV-{YY}-{SEQ:6}` → `INV-26-000456`
- [ ] SEQ reset cadence: never / yearly / monthly / daily
- [ ] Server-enforced uniqueness; collision → retry
- [ ] Migration: switching format leaves existing IDs unchanged; new IDs follow new pattern
- [ ] Global search accepts format-agnostic input (typing `123` or `T-202604-00123` both match)
- [ ] Tenant sets fiscal year start month (Jan default; some retailers use Feb / Jul)
- [ ] Period alignment: daily / weekly / monthly / quarterly / annual reports
- [ ] Month-end close locks transactions
- [ ] Edits post-close require manager reopen
- [ ] P&L / balance-sheet reporting by fiscal period
- [ ] Export reports to accountant
- [ ] Optional multi-fiscal: calendar-year for internal + fiscal-year for external
- [ ] Tenant base currency set at setup (§36); not lightly changeable
- [ ] Customer record supports preferred currency
- [ ] Invoice / receipt may display both base and customer currency
- [ ] Daily FX rates from tenant server (not third-party)
- [ ] Tenant manual rate override
- [ ] Freeze rate at transaction time; store with invoice
- [ ] Reports use historical stored rate
- [ ] Payment: charge in base currency unless BlockChyp supports multi-currency (check per tenant)
- [ ] Display preference: always base / always customer / side-by-side
- [ ] Per-currency rounding precision (JPY 0 decimals; USD 2; TND 3; etc.)
- [ ] Rounding methods: banker's (half-even, default), half-up (retail), half-down (rare).
- [ ] Scope toggle: per-line vs aggregate — tenant setting.
- [ ] Cash rounding: support countries without small coinage (Canada no penny, Sweden no öre); tenant toggles "round cash to nearest 5¢"; affects cash tender only, card charges exact.
- [ ] Tax rounding cross-ref §16.3.
- [ ] Receipt display: sub-total, rounding adjustment line, total.
- [ ] Audit log all rounding-settings changes.
- [ ] Version all templates: receipt, invoice, quote, waiver, email, SMS.
- [ ] Latest version is active; draft editable then publish → new active.
- [ ] Archive old versions; used to reprint historical docs (preserve intent).
- [ ] Manager rollback to prior version with audit entry.
- [ ] Compliance templates (waivers) locked post legal approval — edit creates new version + re-sign required.
- [ ] Built-in themes: Midnight (default dark), Daylight (default light), Ink (hi-contrast dark), Paper (hi-contrast light), Noir (OLED pure black), Studio (neutral gray, print-balanced).
- [ ] Tenant custom: auto-generate theme from accent + logo + neutral palette; no free-form color picker (unreadable-combo risk).
- [ ] Per-user override in Settings → Appearance → Theme.
- [ ] Auto-switch modes: system follow (default), time-based day/night schedule, location-based shop hours.
- [ ] Preview: live full-app preview while selecting; shake-to-revert within 10s.
- [ ] Glass interplay: glass absorbs theme accent subtly while keeping material readable.
- [ ] Assets accepted: logo (SVG preferred, PNG fallback, 1024×1024 min), accent color (hex), optional brand font, shop address/phone/email/tagline.
- [ ] Upload UI at Settings → Organization → Branding; iPad drag-drop; built-in crop tool for logo.
- [ ] Validation: image min-dims + format (PNG/JPG/SVG); accent color must pass contrast vs dark + light surfaces; suggest alternate on fail.
- [ ] Live preview: receipt / invoice / email / login screen mockups update as user changes.
- [ ] Distribution: per-tenant asset cache refreshed via silent push on branding change.
- [ ] Sovereignty: assets stored on tenant server; never third-party CDN unless tenant owns it.
- [ ] White-label constraints: cannot remove "Powered by Bizarre" (ToS); cannot replace main app icon (single-binary Apple constraint).
- [ ] See §4 for the full list.
- [ ] See §4 for the full list.
- [ ] See §69 for the full list.
- [ ] See §16 for the full list.
- [ ] See §3 for the full list.

---
## §20. Offline, Sync & Caching — PHASE 0 FOUNDATION (read before §§1–19)

**Status: architectural foundation, not a feature.** Sections 1–19 assume the machinery below exists. Numbering stays `§20` for linkability, but scheduling-wise this ships first alongside §1. No domain PR merges without:

- a `XyzRepository` reading from GRDB through `ValueObservation` and refreshing via `sync()`;
- every write routed through the `sync_queue` (§20.2) with idempotency key + optimistic UI + dead-letter fallback;
- cursor-based list pagination per the top-of-doc rule + §20.5;
- the `PagedToCursorAdapter` fronting any server endpoint still returning page-based shapes so iOS never sees `total_pages`;
- offline banner + staleness indicator wired into the screen;
- background upload via `URLSession.background` for any binary (§20.4).

CI enforcement:
- Lint rule flags `APIClient.{get,post,patch,put,delete}` called from outside a `*Repository` file.
- Lint rule flags bare `URLSession` usage outside `Core/Networking/`.
- Required test fixtures: each repository has an offline-read + offline-write + reconnect-drain test (§31 / §31).

Every subsequent subsection below is part of Phase 0 scope. Agent assignments in `ios/agent-ownership.md` move §20 into Phase 0.

### 20.1 Read-through cache architecture
- [ ] **Every read** lands in a GRDB table; SwiftUI views observe GRDB via `@FetchRequest` equivalent (`ValueObservation`).
- [ ] **Repository pattern** — `TicketRepository.observeList(filters:)` emits from GRDB; `sync()` refreshes from server.
- [ ] **Read strategies** — `networkOnly` (force) / `cacheOnly` (offline) / `cacheFirst` (default) / `cacheThenNetwork` (stale-while-revalidate).
- [ ] **TTL per domain** — tickets 30s, inventory 60s, customers 5min, reports 2min, settings 10min.
- [ ] **Staleness indicator** — glass chip on top right of list: "Updated 3 min ago".

### 20.2 Write queue architecture
- [x] **`sync_queue` table** — columns: `id, op, entity, entity_local_id, entity_server_id, payload, idempotency_key, status, attempt_count, last_error, enqueued_at, next_retry_at`.
- [x] **Ops** — `create`, `update`, `delete` wired for customer + inventory; ticket update pending merge. `upload_photo` / `charge` deferred to §20.4 / POS.
- [x] **Optimistic write** — create VMs set `createdId = -1` sentinel (PendingSync) + dismiss immediately; row inserted to sync_queue.
- [x] **Drain loop** — `SyncFlusher.flush()` triggered by `SyncOrchestrator` on connectivity restored, app foreground, 60s periodic tick when pendingCount > 0.
- [x] **Idempotency keys** — UUID per mutation; INSERT OR IGNORE on idempotency_key silently dedupes UI retries.
- [ ] **Per-entity ordering** — current drain is serial across all entities; revisit when queue size grows beyond tens of rows.
- [x] **Exponential backoff** — 1s → 2s → 4s → 8s → 16s → 32s → 60s cap; jitter ±10%. SyncQueueStoreTests locks the formula.
- [x] **Dead-letter** — after 10 failures, row moves to `sync_dead_letter` table; Settings → Sync diagnostics surfaces rows with per-row Retry / Discard.
- [x] **Manual retry** — Settings → Sync diagnostics: tap Retry on a dead-letter row to re-queue with a fresh idempotency key; Discard removes permanently.

### 20.3 Conflict resolution
- [ ] **Strategy** — Last-Write-Wins by server `updated_at` default.
- [ ] **Field-level merge** for notes (append), tags (union), statuses (server wins).
- [ ] **Conflict pane** — when server rejects with `409 CONFLICT + server_version`, show diff UI: Your change vs Server change; keep one.
- [ ] **Delete vs edit** conflict — server tombstone wins; local edit discarded with banner.

### 20.4 Photo / binary uploads
- [ ] **Background `URLSession`** — configuration `background(withIdentifier:)`; survives app exit.
- [ ] **Resumable uploads** — chunked multipart with resume-token if supported.
- [ ] **Progress per asset** — per-ticket progress ring on photo tile.
- [ ] **Retry on failure** with backoff; DL after 10 tries.
- [ ] **Receipt photo** uploads tied to expense row; row shows "Uploading… 43%".

### 20.5 Delta sync + list pagination (cursor-based, offline-first)
- [ ] **Envelope** — every list endpoint returns `{ data, next_cursor?, stream_end_at? }` alongside the standard `{ success, data, message }` wrapper. `next_cursor` is opaque; `stream_end_at` set iff server has no more rows beyond cursor.
- [ ] **Per-`(entity, filter)` state** stored in GRDB `sync_state` table:
  - `cursor` — last opaque cursor received.
  - `oldestCachedAt` — server `created_at` of oldest row held locally.
  - `serverExhaustedAt` — timestamp when server returned `stream_end_at`; null = more exist server-side.
  - `since_updated_at` — latest `updated_at` across cached rows; used for delta refresh of changed-since.
- [ ] **Two orthogonal fetches**: (a) **forward delta** pulls rows changed since `since_updated_at` (refresh); (b) **backward cursor** pulls older rows when user scrolls (paginate).
- [ ] **`hasMore` computation is local**: `serverExhaustedAt == nil || localOldestRow.created_at > serverOldestCreated_at`. Never read `total_pages`.
- [ ] **`loadMoreIfNeeded(rowId)`** behavior:
  - Online → `GET /<entity>?cursor=<stored>&limit=50`; upsert response into GRDB; update `sync_state`; list re-renders via `ValueObservation`.
  - Offline → no network call. If locally evicted older rows exist (§20.9), un-archive from cold store. Otherwise show "Offline — can't load more right now" inline.
- [ ] **Tombstone support** — deleted items propagated as `deleted_at != null` to drop from cache.
- [ ] **Full-resync trigger** — schema bump, user-initiated, corruption detected. Clears `sync_state` + re-pulls from server cursor=null.
- [ ] **Silent-push row insert** — fresh rows delivered via WS / silent push upserted at correct chronological rank; scroll position anchored on existing rowId so user doesn't lose place.
- [ ] **Client adapter for legacy page-based endpoints** — any server endpoint still returning `{ page, per_page, total_pages }` wrapped by `PagedToCursorAdapter` that synthesizes cursors. iOS code never sees `page=N`.
- [ ] **Per-parent sub-lists use the same contract.** Ticket history timeline (§4.6), ticket notes + photos, customer notes (§5), customer timeline, SMS thread messages (§6 / §12), inventory movement history (§6.2), audit log (§50), activity feed (§50), team-chat messages (§45) — all follow the cursor / `sync_state` pattern, scoped per-parent. Each gets its own `<entity>_sync_state` row keyed by `(parent_type, parent_id, filter?)`. Never client-side slices, never `total_pages`.

### 20.6 Connectivity detection
- [ ] **`NWPathMonitor`** — reactive publisher of path status (wifi / cellular / none / constrained / expensive).
- [ ] **Offline banner** — glass chip at top of every screen when path == none.
- [ ] **Metered-network warning** — if cellular + expensive, pause photo uploads until wifi (user override).
- [ ] **Stale-cache banner** — if offline > 1h on a data-heavy screen.

### 20.7 Selective sync (large tenants)
- [ ] **First-boot** pulls — recent 90 days of tickets / invoices; all customers / inventory / staff.
- [ ] **On-demand older** — "Load older" button paginates backward.
- [ ] **Per-location filter** — if user is location-scoped, only sync that location's tickets.
- [ ] **User setting** — "Sync last 30 days" / "90 days" / "All".

### 20.8 Manual sync controls
- [ ] **Sync now** — Settings → Data + pull-down on Dashboard.
- [ ] **Per-tab pull-to-refresh** — standard `.refreshable`.
- [ ] **Last-sync timestamp** footer in Settings → Data.
- [ ] **Unsynced writes count** — tab badge red dot.

### 20.9 Cache invalidation + eviction
- [ ] **Image cache — tiered eviction per §29.3** (not blunt 500 MB LRU). Thumbnails always cached; full-res LRU with tenant-size-scaled cap (default 2 GB, configurable 500 MB – 20 GB or no-limit); pinned-offline store + active-ticket photos never auto-evicted. Cleanup runs at most once / 24h in `BGProcessingTask`; never during active use.
- [ ] **GRDB VACUUM** — monthly on-launch background task; skipped if sync queue has pending writes.
- [ ] **Size monitoring** — footer in Settings → Data shows live breakdown (§29.3 storage panel). Warn only on device-low-disk (< 2 GB free), not on app-cache growth alone.
- [ ] **Low-disk pause** — temporarily freeze writes to cache if device free-space drops below 2 GB; toast "Free up space — app cache paused". Never evict pinned or in-use items to satisfy the guard.

### 20.10 Multi-device consistency
- [ ] **Per-device-id** on mutations so server echoes back correct events.
- [ ] **WS echo** — if user has iPad + iPhone, update on other device via WS.
- [ ] See §19 for the full list.
- [ ] See §16 for the full list.

---
## §21. Background, Push, & Real-Time

### 21.1 APNs registration
- [ ] **Register** — `UIApplication.shared.registerForRemoteNotifications()` after auth + user opt-in.
- [ ] **Upload token** — `POST /device-tokens { token, bundle_id, model, ios_version, app_version, locale }` with tenant-id header.
- [ ] **Token rotation** — on APNs delegate rotation, POST new; old implicitly invalidated server-side after 30 days silence.
- [ ] **Unregister on logout** — `DELETE /device-tokens/:id`.
- [ ] **Permission prompt** — deferred until after first login (not on launch); rationale sheet before system prompt.

### 21.2 Push categories & actions
- [ ] **`SMS_INBOUND`** — Reply / Mark read / Call customer.
- [ ] **`TICKET_ASSIGNED`** — Open / Snooze / Reject.
- [ ] **`TICKET_STATUS_CHANGED`** — Open.
- [ ] **`PAYMENT_RECEIVED`** — Open invoice / Print receipt.
- [ ] **`PAYMENT_FAILED`** — Open / Retry charge.
- [ ] **`APPOINTMENT_REMINDER`** — Open / Mark done / Reschedule.
- [ ] **`MENTION`** — Reply.
- [ ] **`LOW_STOCK`** — Reorder / Dismiss.
- [ ] **`SHIFT_SWAP_REQUEST`** — Accept / Decline.
- [ ] **Rich push** — thumbnail (customer avatar, ticket photo) via `UNNotificationAttachment`.

### 21.3 Silent push
- [ ] **`content-available: 1`** triggers sync delta; no banner.
- [ ] **Events** — new SMS / ticket update / invoice payment / server-initiated refresh.
- [ ] **Coalescing** — debounce multi-events in a window; single sync.

### 21.4 Background tasks
- [ ] **`BGAppRefreshTask`** — opportunistic catch-up sync every 1–4h; schedule after launch.
- [ ] **`BGProcessingTask`** — nightly GRDB VACUUM + image cache prune.
- [ ] **`BGContinuedProcessingTask`** (iOS 26) — "Sync now" extended run when user initiates a long sync.
- [ ] **Task budgets** — complete within 30s; defer remainder.

### 21.5 WebSocket (Starscream)
- [ ] **Endpoints** — `wss://.../sms`, `wss://.../notifications`, `wss://.../dashboard`, `wss://.../tickets`.
- [ ] **Auth** — bearer in `Sec-WebSocket-Protocol` header; server validates.
- [ ] **Reconnect** — exponential backoff 1s → 2s → 4s → 8s → 16s → 30s cap; jitter ±10%.
- [ ] **Heartbeat** — ping every 25s; timeout 30s → force reconnect.
- [ ] **Subscriptions** — per-view subscribe/unsubscribe; dedup server-side.
- [ ] **Event envelope** — `{ type, entity, id, payload, version }`.
- [ ] **Backpressure** — coalesce high-frequency events (dashboard KPIs) at 1Hz client-side.
- [ ] **Disconnect UX** — subtle glass chip "Reconnecting…"; lists keep showing stale data.
- [ ] **Message bus** — `Combine` publisher per event type; repositories subscribe.

### 21.6 Foreground lifecycle
- [ ] **`didBecomeActive`** — lightweight sync + WS re-subscribe.
- [ ] **`willResignActive`** — flush pending writes; snapshot blur if security toggle on.
- [ ] **Memory warning** — flush image cache, reduce GRDB page cache.

### 21.7 Real-time UX
- [ ] **Pulse animation** on list row when item updates via WS.
- [ ] **Toast** — top-of-screen glass "New message from X" with tap → thread.
- [ ] **Badge sync** — unread counts propagate to tab bar + icon badge.

### 21.8 Deep-link routing from push
- [ ] **`userActivity`** dispatcher — Notification → entity URL → `NavigationStack.append(...)`.
- [ ] **Cold-launch** deep link handled before first render.
- [ ] **Auth gate** — if token invalid, store intent, auth, then restore.
- [ ] **Entity allowlist** — only known schemes parsed; reject unknown paths.

### 21.9 Quiet hours policy

No in-app client-side quiet hours (duplicates iOS Focus + confuses tenant admins + fights OS on conflict + doesn't sync across user's other Apple devices).

Users get quieting from two canonical sources:
1. **Tenant server quiet hours** (shop-wide) — configured in Settings → Organization → Hours (§19.5). Server suppresses sending SMS-inbound / ticket / payment pushes outside shop hours. Authoritative, user-independent.
2. **iOS Focus modes / Scheduled Summary** (per-user, cross-device) — the OS silences pushes the server did send. Our app contributes via `FocusFilterIntent` so "Work" focus can hide non-critical categories.
- [ ] Handlers complete promptly; if cancelled, re-queue for next window.
- [ ] MetricKit logs track background-time usage so we stay within iOS quota.
- [ ] Debug helper in §19.25: `BGTaskScheduler._simulateLaunchForTaskWithIdentifier` for manual trigger.
- [ ] `FocusFilterIntent` so users add "Shop hours" filter with params `tenantID` / `location?` / `role?`. Activation hides personal badges + non-critical notifications; surfaces assigned tickets only.
- [ ] Driving focus: suppress non-critical pushes automatically; CarPlay-scope content only (§73 if entitlement approved).
- [ ] Sleep focus: all pushes suppressed except `.critical`.
- [ ] Custom per-tenant focus filters available for multi-location tenants ("Store A only").
- [ ] Settings → Focus integration lists active filters + preview.

---
## §22. iPad-Specific Polish

_Non-negotiable: iPad ≠ upscaled iPhone. Failures in this section indicate an unfinished feature._

### 22.1 Layout
- [ ] **3-column `NavigationSplitView`** on Tickets / Customers / Invoices / Inventory / SMS / Estimates / Appointments / Leads — sidebar (domain chooser) + list column + detail column.
- [ ] **Dashboard 3-column KPI grid** on wide screens; 2-column on 11"; responsive `GridItem(.adaptive(...))`.
- [ ] **Max content width** — detail panes cap at ~720pt on 13" landscape via `.frame(maxWidth: 720)`; excess area padded.
- [ ] **Sidebar** — pinned on 13", collapsible on 11"; `.navigationSplitViewStyle(.balanced)`.
- [ ] **Inspector pane** (iOS 17 `.inspector`) — right-side editor on Ticket detail, Customer detail.
- [ ] **Two-up editor** — Ticket detail with Invoice editor side-by-side on 13".

### 22.2 Interactions
- [ ] **`.hoverEffect(.highlight)`** on all tappable rows / buttons / cards.
- [ ] **Pointer customization** — custom cursors (link vs default) per semantic element.
- [ ] **`.contextMenu`** on rows — Open / Copy ID / Copy phone / Archive / Delete / Share / Open in new window.
- [ ] **Drag-and-drop** — drag inventory → ticket services, drag ticket → calendar slot, drag customer → SMS compose.
- [ ] **Multi-select** — long-press or ⌘-click batch actions; Edit mode in list toolbar.
- [ ] **Apple Pencil** — `PKCanvasView` on signatures; pencil-only edit mode on forms; hover preview (Pencil Pro).

### 22.3 Keyboard-first
- [ ] **Shortcuts**: ⌘N / ⌘F / ⌘R / ⌘, / ⌘D / ⌘1–⌘9 / ⌘⇧F / ⌘⇧N / ⌘K (command palette) / ⌘P (print) / ⌘/ (help) / ⎋ (dismiss sheet) / ⌥↑↓ (row move) / Space (preview).
- [ ] **Focus ring** — visible keyboard focus on buttons/links; `.focusable()`.
- [ ] **Tab order** — forms tabbable in logical order.
- [ ] **Menu bar** — iPad-specific `.commands` with grouped menu items (File / Edit / View / Actions / Window / Help).

### 22.4 Multi-window / Stage Manager
- [ ] **Multiple scenes** — `UISceneConfiguration` supports N windows.
- [ ] **Scene state** restored per-window on relaunch.
- [ ] **Open in new window** from context menu.
- [ ] **Scene activities** — detail views become independent activities.
- [ ] **Slide Over / Split View** — layouts verified at 1/2, 1/3, 2/3 splits.

### 22.5 Data presentation
- [ ] **`Table`** (sortable columns) on Reports, Inventory dumps, Audit Logs.
- [ ] **Column chooser** — reorder / hide columns; persisted.
- [ ] **Sort indicator** arrows on column headers.

### 22.6 Magic Keyboard / trackpad
- [ ] **Swipe gestures** translated to trackpad (2-finger).
- [ ] **Right-click** menus everywhere.

### 22.7 External display / AirPlay
- [ ] **Customer-facing POS display** — second screen shows cart / tip.
- [ ] **Presentation mode** — Reports dashboards full-screen on TV.
- [ ] Scene types: primary (full app), secondary (single ticket detail), tertiary (POS register), quaternary (reports dashboard).
- [ ] Drag-to-new-window: long-press ticket row → drag out → new window with that ticket. Long-press POS tab → dedicated register window.
- [ ] `NSUserActivity` per scene persists position / ticket ID; relaunch re-opens all windows.
- [ ] Scene declares capabilities ("can show ticket detail", "can run POS"); drag-drop between windows validates target capability.
- [ ] Stage Manager min content area 700×500; below that → compact layout.
- [ ] External-display `UIScene` hosts customer-facing display (§16 POS CFD) mirrored from POS scene.
- [ ] `UICommand` menu per scene (File / Edit / View / Window / Help) with custom items (New Ticket, Quick Find, Switch Tenant).
- [ ] Hardware keyboard: iPad top-menu command menu populates from scene `UIKeyCommand` discoverabilityTitle; ⌘? shows all shortcuts overlay; arrow keys navigate lists; Tab/Shift-Tab traverse form fields; Enter submits primary action; Esc dismisses sheets/cancels
- [ ] Input accessory bar: numeric keyboard on money fields has $ + %; Done + Next + Prev arrows on all text fields; auto-hide with hardware keyboard attached
- [ ] Field validation keys: IMEI/phone `.numberPad`; email `.emailAddress`; URL `.URL`; search `.webSearch`
- [ ] Autocorrect: off for IDs/codes/emails; on for message composers and notes; SmartDashes/SmartQuotes off for data entry
- [ ] External barcode scanner (USB/BT wedge): detect rapid keystrokes ending in Enter; route to scan handler not textfield; configurable via Settings → Hardware
- [ ] Support Dvorak/custom layouts automatically — never hardcode layouts
- [ ] Keyboard show/hide: `.keyboardAvoidance` adjusts insets; bottom-anchored primary buttons stay visible via `safeAreaInset(edge: .bottom)`
- [ ] Within-app drags: ticket row → Assignee sidebar (iPad); invoice row → Email compose; inventory row → PO draft; photo → Ticket attachment
- [ ] Cross-app drags: customer from Contacts app → Customer create; PDF from Files → Ticket attachment; photo from Photos → Ticket photos/Annotation
- [ ] Type registration: `UTType`s `public.image`, `public.pdf`, `com.bizarrecrm.ticket` (custom UTI for in-app drag); `NSItemProvider` per source
- [ ] Previews: drag preview = card-style miniature; drop target highlights on hover
- [ ] Validation: drop handler validates type + tenant scope; invalid drops show red X overlay
- [ ] Haptics+motion: pickup = light haptic + row lift; drop = success haptic + slot-fill animation; cancel = rubber-band back
- [ ] Accessibility: every drag op has keyboard/VoiceOver alternative via select + "Move to…" menu
- [ ] iPad portrait: sidebar collapsed to icon rail (56pt) unless user expands; detail takes most width
- [ ] iPad landscape: sidebar expanded (260–280pt) default; user toggles rail via ⌘\
- [ ] Mac Designed-for-iPad: sidebar persistent, min 260pt
- [ ] Drag-to-resize: iPad 13" Pro supports resize via split-view divider; inner sidebar also resizable 260–400pt
- [ ] Persistence: width saved per-scene in `UserDefaults`
- [ ] Overflow: if label truncates, icon-only mode kicks in automatically at <100pt
- [ ] Tandem OLED: optional HDR content for hero dashboard images (brand gradients); verify blacks on real OLED (no gray haze)
- [ ] ProMotion 120fps: tune all animations for 120fps; avoid 60fps lock from `ProMotion: false` in Info.plist
- [ ] Magic Keyboard 2024: surface function row; map custom actions (F1=new ticket, F2=POS, F3=inventory)
- [ ] Pencil Pro: squeeze opens tool picker in annotation (§4); barrel roll rotates shape/text; haptic on Pencil tip (iOS 17.5+ API)
- [ ] M4 performance: gate larger-dataset UI (e.g. live charts 10k points) on A17+ detection
- [ ] External storage: USB-C direct photo import; file picker recognizes external drives
- [ ] Safe area: use `.ignoresSafeArea(.keyboard)` carefully; default behavior is scroll.
- [ ] Accessory toolbar for numeric fields: `$`, `%`, next, prev, done (done closes keyboard, next moves focus).
- [ ] SMS/email inputs show QuickType; custom template suggestions via replacement assistant.
- [ ] External hardware keyboard: hide onscreen keyboard automatically.
- [ ] iPad split keyboard respected; inline accessory bar follows keyboard.
- [ ] Keep native emoji switcher; no custom emoji picker.
- [ ] Invocation: ⌘? on hardware keyboard via iOS 17+ `UIKeyCommand.wantsPriorityOverSystemBehavior`; also Help → Keyboard Shortcuts menu item.
- [ ] Layout: full-screen glass panel grouped by Navigation / Tickets / POS / Customer / Admin; searchable.
- [ ] Content auto-built from `UICommand` registrations in each scene (never hand-maintained).
- [ ] Rebinding: power users via Settings → Keyboard; core shortcuts (⌘N / ⌘F / ⌘S) not rebindable.
- [ ] iPad-only by default; hidden on iPhone unless hardware keyboard attached.
- [ ] A11y: arrow navigable, VoiceOver reads each binding.

---
## §23. Mac ("Designed for iPad") Polish

_Mac Catalyst not used — "Designed for iPad" only. Layout inherits iPad; hardware feature-gates apply._

### 23.1 Detection + gating
- [ ] **`ProcessInfo.processInfo.isiOSAppOnMac`** — runtime flag.
- [ ] **Feature-gate barcode scan** to manual entry; offer Continuity Camera if iPhone nearby.
- [ ] **Feature-gate Bluetooth MFi printers** → AirPrint.
- [ ] **Feature-gate NFC** (unavailable) — hide feature.
- [ ] **Haptics** no-op on Mac.

### 23.2 Window behavior
- [ ] **Min size** 900×600; preferred 1280×800.
- [ ] **Multi-window** — file → new window opens new scene.
- [ ] **Restore windows** on launch.
- [ ] **Window titles** — per-scene (e.g., "Ticket #1234 - BizarreCRM").

### 23.3 Mac-native UX conventions
- [ ] **`.textSelection(.enabled)`** on every ID, phone, email, invoice number, tag.
- [ ] **`.fileExporter`** for PDF/CSV save dialogs (not share sheet).
- [ ] **Right-click context menus** on every tappable element.
- [ ] **Drag-and-drop** from Finder → attachment fields (drop a receipt PDF onto an expense).
- [ ] **Copy formatted** — ⌘C on a table row copies TSV for Excel paste.
- [ ] **Find in page** — ⌘F in long scrolling views.
- [ ] **Keyboard arrows** nav through lists (↑↓) with ↵ to open.

### 23.4 Menu bar
- [ ] **`.commands`** — full menu hierarchy (File / Edit / View / Tickets / Customers / Inventory / POS / Window / Help).
- [ ] **Accept that "Designed for iPad" limits** — no custom app icon in menu bar; no AppKit-only windows.

### 23.5 macOS integrations (limited)
- [ ] **Continuity Camera** — scan barcode via iPhone as Mac camera; photo capture.
- [ ] **Handoff** — start on Mac, continue on iPad.
- [ ] **iCloud Drive** — photo / PDF attachments can live there.
- [ ] **Universal clipboard** — copy ticket # on iPad, paste on Mac.

### 23.6 Missing on Mac (document)
- [ ] Widgets (limited).
- [ ] Live Activities (unavailable).
- [ ] NFC (unavailable).
- [ ] BlockChyp terminal — works (IP-based transport either LAN or cloud-relay; see §17.3). No Bluetooth involved at any layer.

---
## §24. Widgets, Live Activities, App Intents, Siri, Shortcuts

_Requires WidgetKit target + ActivityKit + App Intents extension. App Group `group.com.bizarrecrm` shares data between main app and widgets (GRDB read-only slice, exported on main-app sync)._

### 24.1 WidgetKit — Home Screen
- [ ] **Small (2×2)** — today's ticket count with delta ("↑5 from yesterday"); revenue today; glass gradient.
- [ ] **Medium (4×2)** — top 3 "Needs attention" tickets; deep-link tap → ticket detail; timestamp.
- [ ] **Large (4×4)** — revenue sparkline (Swift Charts) last 7 days + KPI grid (4 tiles: tickets open, invoices overdue, SMS unread, appointments today).
- [ ] **Extra Large (iPad)** — full dashboard mirror; 6 tiles + chart.
- [ ] **Multiple widgets** — "Revenue", "Tickets", "SMS", "Appointments" each with S/M/L variants.
- [ ] **Configurable** — `IntentConfiguration`: choose which KPI, time range, location.
- [ ] **Refresh policy** — `TimelineProvider.getTimeline` returns 4-hour entries; WidgetCenter refresh on significant events.
- [ ] **Data source** — App Group shared GRDB read-only; main app writes summary on sync.
- [ ] **Privacy** — redact in lock-screen mode if sensitive (revenue $); placeholder text.

### 24.2 WidgetKit — Lock Screen (iOS 16+)
- [ ] **Circular** — ticket count badge.
- [ ] **Rectangular** — "Next appt: 2:30 PM" or "5 tickets waiting".
- [ ] **Inline** — single-line revenue today.

### 24.3 Live Activities (ActivityKit)
- [ ] **Ticket in progress** — started when technician clicks "Start work" on a ticket; shows on Lock Screen + Dynamic Island with timer + customer name + service; end when ticket marked done.
- [ ] **POS charge pending** — starts when user hits Pay → terminal; Dynamic Island live spinner; expires on success/failure.
- [ ] **Clock-in timer** — full-day live activity of time on shift; Dynamic Island minimal display "8h 14m"; tap to view timesheet.
- [ ] **Appointment countdown** — 15 min before appointment → live activity on Lock Screen.
- [ ] **Dynamic Island compact / expanded** layouts — content + trailing icon + leading avatar.
- [ ] **Push-to-start** — server triggers Live Activity via push token (iOS 17.2+).
- [ ] **Rate limits** — respect 1 active Live Activity per subject; dismiss automatically.

### 24.4 App Intents (Shortcuts + Siri)
- [ ] **CreateTicketIntent** — "New ticket for {customer} on {device}"; parameterizable.
- [ ] **LookupTicketIntent** — "Find ticket {number}"; returns structured snippet.
- [ ] **LookupCustomerIntent** — "Show {customer}".
- [ ] **ScanBarcodeIntent** — opens scanner → inventory lookup or POS add-to-cart.
- [ ] **ClockInIntent** / **ClockOutIntent** — "Hey Siri, clock in".
- [ ] **SendSMSIntent** — "Text {customer} {message}".
- [ ] **StartSaleIntent** — opens POS.
- [ ] **RecordExpenseIntent** — "Log $42 lunch expense".
- [ ] **ShowDashboardIntent** — "Show dashboard".
- [ ] **Intent return values** — structured `AppEntity` with human-readable snippets for Siri speech.
- [ ] **Parameters** — entity types (TicketEntity, CustomerEntity) provide suggested values.

### 24.5 App Shortcuts (`AppShortcutsProvider`)
- [ ] **Seed phrases** in English (plus 10 locales later) — "Create ticket for ACME", "Show my tickets", "Clock in".
- [ ] **System suggestions** — daily rotating shortcut tiles in Shortcuts app.
- [ ] **Siri suggestions** on lock screen.

### 24.6 Control Center controls (iOS 18+)
- [ ] **Clock in/out toggle** — one-tap.
- [ ] **Quick scan** — opens scanner.
- [ ] **Quick sale** — opens POS.
- [ ] **SMS unread** badge control.

### 24.7 Action Button (iPhone 15 Pro+)
- [ ] **Map "Action Button" → CreateTicket shortcut** per user preference.
- [ ] **Alt**: Clock-in toggle.

### 24.8 Interactive widgets (iOS 17+)
- [ ] **Toggle "Clock in"** directly from widget (no app open).
- [ ] **Mark ticket done** from Medium widget.
- [ ] **Reply to SMS** inline widget (typing button).

### 24.9 Smart Stack / ReloadTimeline
- [ ] **Relevance** hints so widget auto-promotes in Smart Stack (e.g., morning → dashboard, POS time → sales, end-of-shift → clock-out).
- [ ] **ReloadTimeline** on significant events (ticket change, payment).

### 24.10 Complications (watchOS stretch)
- [ ] Circular ticket count on Apple Watch face.
- [ ] Intents catalog: `CreateTicketIntent` (customerName?, deviceTemplate?, reportedIssue?), `LookupTicketIntent`, `ClockInIntent` / `ClockOutIntent`, `StartSaleIntent`, `ScanBarcodeIntent`, `TakePaymentIntent`, `SendTextIntent`, `NewAppointmentIntent`, `StartBreakIntent` / `EndBreakIntent`, `TodayRevenueIntent` (read-only speak), `PendingTicketsCountIntent` (read-only speak), `SearchInventoryIntent`.
- [ ] Donate via `INInteraction` on each use so Siri suggests context-aware shortcuts ("Clock in" near 9am at shop).
- [ ] Focus-aware (§13): `SendTextIntent` disabled in DND unless urgent.
- [ ] Parameter disambiguation: ambiguous customer → Siri "Which John?"; fuzzy match via §18 FTS5.
- [ ] Every intent has an `IntentView` (SwiftUI glass card) rendered inline in Shortcuts preview + Siri output.
- [ ] Privacy: params + results stay on device / tenant server; no Apple Siri-analytics integration (§32).
- [ ] iOS 26: register `AssistantSchemas.ShopManagement` domain so Apple Intelligence can orchestrate common nouns (Ticket / Customer / Invoice).
- [ ] Testing: Shortcuts-app gallery + XCUITest each intent headless.
- [ ] Sizes supported: Small, Medium, Large, Extra-Large (iPad only), Accessory (Lock Screen: circular/rectangular/inline), StandBy
- [ ] Catalog: Tickets today (counts + progress bar); Revenue today ($ + trend); Next appointment (customer + time + address); Pending SMS (unread count); Quick actions (4 buttons: New ticket / Scan / POS / Clock in); Employee snapshot (my assigned count / my sales today); Inventory alert (critical low-stock item with name)
- [ ] Data source: App Group SQLCipher DB read-only in widget; refreshed via app writing on every sync
- [ ] Timeline entries: `IntervalTimelineProvider` every 15 min; triggered refresh on background sync completion
- [ ] Taps: each widget deep-links; iOS opens app at the right screen
- [ ] StandBy: large time-of-day widget shows today revenue + next appointment in glance mode
- [ ] Lock Screen variants: circular = ticket count; rectangular = revenue + Δ vs yesterday; inline = "3 tickets ready"
- [ ] Configuration: `AppIntentConfiguration` lets user pick which tenant (multi-tenant user) and which location
- [ ] Privacy: widget content stays on device; no sensitive data on Lock Screen (no customer names; counts only)
- [ ] Ship these gallery shortcuts: "Create ticket for customer" (customer picker chain), "Log clock-in" (one-tap), "Today's revenue" (reads aloud), "Start sale for customer" (opens POS pre-loaded), "Scan barcode to inventory" (opens scanner), "Send payment link" (prompts amount, copies link), "Look up ticket by IMEI" (prompts IMEI, opens ticket).
- [ ] Registration via `@ShortcutsProvider`; each entry ships image + description + parameter definitions.
- [ ] Automation support so tenants can wire Arrive at work → Clock in style triggers.
- [ ] Widget-to-shortcut: widgets pre-configure parameters for one-tap intent execution.
- [ ] Siri learns to invoke by donated phrases.
- [ ] Sovereignty: no external service invoked from shortcuts unless tenant explicitly adds it.

---
## §25. Spotlight, Handoff, Universal Clipboard, Share Sheet

### 25.1 Spotlight (`CoreSpotlight`)
- [ ] **Index window** — last 60 days tickets + top 500 customers + top 200 invoices + top 100 appointments + all inventory SKUs.
- [ ] **Attributes per item** — `title`, `contentDescription`, `keywords`, `thumbnailData`, `domainIdentifier`, `contentURL`, `relatedUniqueIdentifiers`.
- [ ] **Refresh** — on sync-complete, background reindex changed items; batch 100.
- [ ] **Deletion** — tombstoned items deleted from index.
- [ ] **Privacy** — respect user-facing "Hide from Spotlight" per domain in Settings.
- [ ] **Deep-link handler** — `continueUserActivity` → route by `uniqueIdentifier`.
- [ ] **Suggestions** — `CSSuggestionsConfiguration` for proactive suggestions.
- [ ] **Preview** — rich preview card in Spotlight with customer avatar + ticket status.

### 25.2 Handoff / `NSUserActivity`
- [ ] **Per-detail `NSUserActivity`** — on every Ticket/Customer/Invoice/SMS/Appointment detail, `becomeCurrent()` with `activityType`, `userInfo`, `title`, `webpageURL`.
- [ ] **Handoff to Mac** — Mac docks show the icon; tap to open same record.
- [ ] **Handoff to iPad** — multi-window opens fresh scene at same record.
- [ ] **Encrypted payload** — sensitive items sent via key derived from iCloud Keychain.
- [ ] **`eligibleForSearch`** — also indexes in Spotlight.
- [ ] **`eligibleForPrediction`** — Siri suggests continue-ticket on other devices.

### 25.3 Universal Clipboard
- [ ] **`.textSelection(.enabled)`** on all IDs, phones, emails, invoice #, SKU.
- [ ] **Copy to pasteboard** actions on context menus use `UIPasteboard` with expiration for sensitive.
- [ ] **iCloud Keychain paste** for SMS codes (`UITextContentType.oneTimeCode`).

### 25.4 Share Sheet (`UIActivityViewController` / `ShareLink`)
- [ ] **Invoice PDF** — generate via `UIPrintPageRenderer` → share.
- [ ] **Estimate PDF** — same renderer.
- [ ] **Receipt PDF** — same renderer.
- [ ] **Customer vCard** — `CNMutableContact` → `CNContactVCardSerialization` → share.
- [ ] **Ticket summary plaintext + image** — formatted block copy.
- [ ] **Public tracking link** — share short URL to public-tracking page (see §57).
- [ ] **Photo** — ticket photo → share.
- [ ] **Image with logo watermark** — before sharing.

### 25.5 Share Extension (receive sheet)
- [ ] **Accept image** — from Photos app or other apps → "Attach to ticket" picker flow.
- [ ] **Accept PDF** — "Attach to invoice" or "Attach to expense" (receipt).
- [ ] **Accept URL** — "Add to note on ticket".
- [ ] **Extension bundle** — separate target; uses App Group for temp hand-off.

### 25.6 Drag-and-drop
- [ ] **Drop image from Files/Photos** → ticket photos, expense receipts, customer avatar.
- [ ] **Drop PDF** → invoice attachments.
- [ ] **Drop text** → note fields.
- [ ] **Drag out** — ticket card draggable to other apps (e.g., drag to Notes).

### 25.7 Universal Links — cloud-hosted tenants only

Apple Associated Domains are compiled into the app entitlement, so we can only list domains we own. Works for cloud tenants on `*.bizarrecrm.com`. **Does not work for self-hosted tenants** whose domain is whatever they configured in their server `.env` (`https://repairs.acmephone.com`, a LAN IP like `https://10.0.1.12`, etc.) — Apple will never verify AASA hosted on an arbitrary tenant domain against our signed entitlement.

- [ ] **AASA file** hosted at `https://app.bizarrecrm.com/.well-known/apple-app-site-association` with path patterns `/c/*`, `/t/*`, `/i/*`, `/estimates/*`, `/receipts/*`, `/public/*` wildcards (where we want the app to open instead of web).
- [ ] **Entitlement** — `applinks:app.bizarrecrm.com` + `applinks:*.bizarrecrm.com` (subdomains for tenant slugs we host).
- [ ] **Route handler** — `onContinueUserActivity(.browsingWeb)` extracts path → navigate.
- [ ] **Login gate** — unauth user stores intent, signs in to the matching tenant, restores.
- [ ] **Fallback** — Universal Link that fails to open app shows public web page instead.
- [ ] **Self-hosted tenants get custom scheme (§25.8), not Universal Links.** Document this in the self-hosted admin docs.

### 25.8 Custom URL scheme (`bizarrecrm://`) — works for all tenants, incl. self-hosted

The custom scheme is the portable deep-link path; it doesn't care about tenant domain. Every route carries the tenant identifier in the URL so the app routes the request to the right server (the one the user is signed into; if not signed in, we prompt to sign in to that tenant first).

- [ ] **Registered** in Info.plist (`CFBundleURLSchemes: ["bizarrecrm"]`).
- [ ] **Route shape** — tenant-aware: `bizarrecrm://<tenant-slug>/<path>`. Examples:
  - `bizarrecrm://acme-repair/tickets/123`
  - `bizarrecrm://acme-repair/pos`
  - `bizarrecrm://acme-repair/sms/456`
  - `bizarrecrm://demo/dashboard`
- [ ] **Tenant-slug resolution** — slug maps to a stored server URL (Keychain, set at login per §19.22). On cold open, if the user isn't signed into that tenant, show "Sign in to Acme Repair to continue" with server URL pre-filled.
- [ ] **Self-hosted tenant IDs** — for self-hosted, the slug is whatever the server's `.env` declares as tenant_slug (typically the shop name, lowercased); the Keychain entry binds slug → full base URL (`https://repairs.acmephone.com`).
- [ ] **Used by** — Shortcuts, App Intents, push-notification deep-links, in-app share sheets (shares custom-scheme link when tenant is self-hosted, Universal Link when cloud-hosted), QR codes printed on tickets / receipts for staff-side opening.
- [ ] **Public customer-facing URLs stay HTTPS** — tracking / pay / book pages (§53 / §41 / §56) remain HTTPS on whichever domain the tenant serves, whether `app.bizarrecrm.com` or self-hosted. Those URLs are for browsers, not the staff app.
- [ ] **Multi-tenant safety** — if a deep link arrives for tenant A while user is signed into tenant B, app shows confirmation "Open Acme Repair? You'll be signed out of Bizarre Demo first." Never silently switches tenants (§79 scope rule).
- [ ] **Unknown scheme / path** — reject with inline toast, never crash. Rate-limit per source (Shortcuts / push / clipboard) against DoS by malformed URLs.
- [ ] Indexed entity set: tickets (id/customer/device/status), customers (name/phones/emails), invoices (id/total/status), inventory (SKU/name), notes (body).
- [ ] Layer: `CSSearchableIndex` fed from SQLCipher read-through; refresh on insert/update.
- [ ] Privacy: Spotlight items scoped per-user to tenant + role access; Settings → Privacy → "Disable Spotlight" opt-out.
- [ ] Deep link: each item's `contentURL` routes via URL scheme handler (§65).
- [ ] No public indexing (no web Spotlight publish).
- [ ] Size cap: 1000 items per entity type, recent-first.
- [ ] Refresh: full rebuild on schema migration (§1); incremental via GRDB hooks.

---
## §26. Accessibility

**Core rule: respect OS, never force.** Every adaptive behavior in this section is **gated on the matching iOS system setting**. Default is the regular (non-accessibility) experience. We read `UIAccessibility.*` flags + SwiftUI `@Environment(\.accessibilityXyz)` values and adapt only when the user has opted in at the OS level. We do not ship our own app-level toggle that forces any of these on; doing so duplicates iOS, confuses users whose system settings are the source of truth, and causes drift across their other Apple devices.

Exceptions (user-adjustable within our app):
- **Per-category notification categories** (§13) — app-level because tenant notification taxonomy doesn't exist at OS level.
- **Kiosk / Assistive Access modes** (§55, §26.11) — distinct product mode, user-chosen, not an accessibility override.

Everything else listed below is passive — we honor the OS flag, we don't override it, and we never expose "Force Reduce Motion" / "Force Reduce Transparency" toggles.

### Detection reference
```swift
// SwiftUI (preferred)
@Environment(\.accessibilityReduceMotion) var reduceMotion
@Environment(\.accessibilityReduceTransparency) var reduceTransparency
@Environment(\.accessibilityDifferentiateWithoutColor) var diffWithoutColor
@Environment(\.accessibilityShowButtonShapes) var showButtonShapes
@Environment(\.colorSchemeContrast) var contrast        // .increased when Increase Contrast is on
@Environment(\.legibilityWeight) var legibility         // .bold when Bold Text is on
@Environment(\.dynamicTypeSize) var dynamicTypeSize     // scales with user's text-size pref

// UIKit / observable
UIAccessibility.isVoiceOverRunning
UIAccessibility.isSwitchControlRunning
UIAccessibility.isAssistiveTouchRunning
UIAccessibility.isReduceMotionEnabled
UIAccessibility.isReduceTransparencyEnabled
UIAccessibility.isBoldTextEnabled
UIAccessibility.isDarkerSystemColorsEnabled            // Increase Contrast
UIAccessibility.isGrayscaleEnabled
UIAccessibility.isInvertColorsEnabled
UIAccessibility.isVideoAutoplayEnabled
UIAccessibility.buttonShapesEnabled
UIAccessibility.shouldDifferentiateWithoutColor
```

Observe changes via `NotificationCenter` on `UIAccessibility.reduceMotionStatusDidChangeNotification`, etc., so behavior flips live if the user changes settings mid-session.

_Baseline: `Accessibility Inspector` Audit passes on every screen. Run before PR merge._

### 26.1 VoiceOver
Always-on data (labels, hints, traits) — these cost nothing and only matter when VoiceOver is running, which iOS controls. We emit the metadata unconditionally; iOS decides when to speak it.

- [ ] **Label + hint** on every interactive element — `.accessibilityLabel("Ticket 1234, iPhone repair")`, `.accessibilityHint("Double tap to open")`. Present in every build; iOS uses them only when VoiceOver is active.
- [ ] **Traits** — `.isButton`, `.isHeader`, `.isSelected`, `.isLink`.
- [ ] **Rotor support** — on long lists: heading / form control / link rotors work.
- [ ] **Grouping** — `.accessibilityElement(children: .combine)` on compound rows so VoiceOver reads one meaningful line.
- [ ] **Container** — `.accessibilityElement(children: .contain)` wraps list for navigation.
- [ ] **Announcement** — `.announcement` posted on async success/failure ("Ticket created") **only when `UIAccessibility.isVoiceOverRunning`** — silent otherwise to avoid wasted work.
- [ ] **Focus** — `@AccessibilityFocusState` moves focus to key element on sheet open when VoiceOver is running; ignored otherwise.
- [ ] **Custom actions** — swipe actions exposed as accessibility custom actions.
- [ ] **Image descriptions** — customer avatars use initials; ticket photos labeled "Photo N of M on ticket X".

### 26.2 Dynamic Type
iOS broadcasts the user's text-size preference via `\.dynamicTypeSize`. Layout adapts automatically; nothing is "forced large" until the user drags the OS slider.

- [ ] **Support up through XXXL** (AX5 extra-large); test with `environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)` in previews.
- [ ] **No truncation** on any primary heading when the OS-reported size is accessibility-large — use `.lineLimit(nil)` + ScrollView fallback, triggered when `dynamicTypeSize.isAccessibilitySize == true`.
- [ ] **Tabular layouts** switch to vertical stacks at large sizes via `ViewThatFits` — automatic response to OS size, no app-level override.
- [ ] **Icons scale** via `.imageScale(.medium)` and SF Symbols; this respects both size and iOS Bold-Text.

### 26.3 Reduce Motion
Gate every spring / parallax / auto-play on the OS flag. Default = full motion.

- [ ] `@Environment(\.accessibilityReduceMotion)` gate — swap spring animations for cross-fades when the OS flag is set. If the flag is false, ship normal motion.
- [ ] **Cart confetti** → static checkmark only when the flag is set.
- [ ] **Parallax on Dashboard** → disabled only when the flag is set.
- [ ] **Auto-playing animations** → paused until tap only when the flag is set (`UIAccessibility.isVideoAutoplayEnabled` for media).
- [ ] **Never expose an in-app "Reduce motion" toggle.** Users set it at OS level; we follow.

### 26.4 Reduce Transparency
- [ ] `@Environment(\.accessibilityReduceTransparency)` gate — `.brandGlass` returns solid `bizarreSurfaceBase` fill only when the OS flag is set. Default ships full glass.
- [ ] **Live switching** — observe `UIAccessibility.reduceTransparencyStatusDidChangeNotification` so the UI flips mid-session without app restart.

### 26.5 Increase Contrast
- [ ] `@Environment(\.colorSchemeContrast) == .increased` (reflecting iOS "Increase Contrast") → use high-contrast brand palette. Default ships regular palette.
- [ ] **Borders** around cards become visible (1pt solid stroke) only when the flag is set.
- [ ] **Button states** clearer (solid vs outlined) only when the flag is set.

### 26.6 Bold Text + Differentiate Without Color
- [ ] **Bold Text** — gate on `@Environment(\.legibilityWeight) == .bold` (reflects iOS Bold Text system setting). Default = regular weight per §80 / §80.
- [ ] **Status pills** — glyph + color at all times; glyph-only emphasis additionally engaged when `@Environment(\.accessibilityDifferentiateWithoutColor)` is true (reflects iOS Differentiate Without Color). Color-alone conveyance is banned regardless, per WCAG — but redundant glyphs aren't over-applied unless the flag is set.
- [ ] **Charts** — dashed / dotted patterns in addition to color whenever `accessibilityDifferentiateWithoutColor` is true.

### 26.7 Tap targets
- [ ] **Min 44×44pt** — enforced via debug-build assertion in a `.tappableFrame()` ViewModifier that reads the rendered frame from `GeometryReader` and `assert(size.width >= 44 && size.height >= 44)`. CI snapshot test + SwiftLint rule bans bare `.onTapGesture` on non-standard controls so every tappable goes through the checked modifier. No runtime overlay; violations trip at dev time or in CI, never in production UI.
- [ ] **Spacing** between adjacent tappable rows ≥ 8pt (same enforcement: lint rule + snapshot geometry check).

### 26.8 Voice Control
Metadata emitted always; surfaced only when iOS Voice Control is active.

- [ ] **`.accessibilityInputLabels([])`** — alt names for each action ("new" for "Create ticket"). Unconditional.
- [ ] **Show numbers overlay** mode (iOS renders) — every tappable has a number label; works automatically when the user turns on Voice Control.
- [ ] **Custom command phrases** documented in Help.

### 26.9 Switch Control
Layout + focus order unconditional; iOS lights up Switch traversal only when `UIAccessibility.isSwitchControlRunning`.

- [ ] **Nav order** — every screen tested with external switch.
- [ ] **Point mode** works at all scales.

### 26.10 Captions / transcripts
- [ ] **In-app video tutorials** (future) — captions + transcripts bundled; caption track displayed when iOS Media Captions + SDH setting is on.
- [ ] **Voice messages** (SMS) — autogenerated transcript via `Speech` framework; transcript shown to every user (always useful), not gated.

### 26.11 Guided Access / Assistive Access
Product-mode opt-in, not an OS flag — but our app must be compatible so users running those OS modes don't get blocked.

- [ ] **Compatible** — no absolute fullscreen-only prompts that fight Guided Access.
- [ ] **Apple Intelligence Assistive Access** profile — simplified single-task mode (POS-only / Timeclock-only); user enters via iOS setting, app responds with minimal chrome.

### 26.12 Accessibility audit
- [ ] **Xcode Accessibility Inspector** audit per screen.
- [ ] **Automated UI tests** assert labels on primary actions + that adaptive behaviors only trigger when the simulated OS flag is set (e.g., snapshot with `environment(\.accessibilityReduceMotion, true)` vs default false).
- [ ] CI step: `XCUIAccessibilityAudit` (Xcode 26) runs on every PR; fails on missing label / poor contrast / element-too-small / inaccessible text.
- [ ] Every golden-path XCUITest calls `try app.performAccessibilityAudit()`.
- [ ] Exceptions documented in `Tests/Accessibility/Exceptions.swift` (decorative imagery pre-marked `.accessibilityHidden(true)`).
- [ ] Audit results attached to CI run; trend tracked over time.
- [ ] Manual QA scripts (§26) remain per release — automation is not full replacement.
- [ ] TipKit integration (iOS 17+) surfaces rules-based tips
- [ ] Each tip: title, message, image, eligibility rules (e.g. "shown after 3rd ticket create")
- [ ] Catalog tip: "Try swipe right to start ticket" after 5 tickets viewed but zero started via swipe
- [ ] Catalog tip: "⌘N creates new ticket faster" shown once user connects hardware keyboard
- [ ] Catalog tip: "Long-press inventory row for quick actions" after 10 inventory views
- [ ] Catalog tip: "Turn on Biometric Login in Settings" after 3 sign-ins
- [ ] Dismissal: per-tip "Don't show again"
- [ ] Global opt-out in Settings → Help
- [ ] A11y: tips announced via VoiceOver at low priority
- [ ] Reduce Motion: fade in, no bounce
- [ ] Sovereignty: tip eligibility computed entirely on device; no third-party tracking
- [ ] Three-finger tap-to-zoom is system-provided; views must respect so text zooms cleanly; reserve zero app 3-finger gestures.
- [ ] Zoom window non-pixelated via vector assets + Dynamic Type.
- [ ] Help surface: deep-link to iOS Settings → Accessibility → Zoom.
- [ ] Test matrix: every screen reachable without touch; every interactive element Tab/arrow-reachable; every primary action triggerable via Enter / ⌘+key.
- [ ] XCUITest automation driven only by keyboard events; fail if any critical flow needs touch.
- [ ] Flows covered: Login → dashboard → create ticket → add customer → add device → save; POS open register → add item → discount → payment → receipt; SMS reply keyboard-only.
- [ ] Focus ring: visible indicator always (§72.3), never lost/invisible.
- [ ] Switch Control parity: same machinery as keyboard — both test paths must be green.
- [ ] Drop-outs: document any gap that can't be keyboard-driven (e.g., signature canvas needs touch/pencil — acceptable but documented).

---
## §27. Internationalization & Localization

### 27.1 Foundation
- [ ] **String catalog** (`Localizable.xcstrings`) — all UI copy externalized; Xcode 15+ catalog format with plural rules + variations.
- [ ] **No string concatenation** — use `String(format:)` or `String(localized:)` placeholders.
- [ ] **Build-time check** — CI asserts no hardcoded user-facing strings in Swift source (regex audit).
- [ ] **Translation service** — Lokalise / Crowdin workflow + CI sync.

### 27.2 Locale-aware formatters
- [ ] **Dates** — `Date.FormatStyle.dateTime` with locale.
- [ ] **Currency** — `Decimal.FormatStyle.Currency(code: tenantCurrency)`.
- [ ] **Numbers** — `.number` with `.locale(Locale.current)`.
- [ ] **Percent** — `.percent`.
- [ ] **Distance** — `MeasurementFormatter` (rare).
- [ ] **Relative** — `RelativeDateTimeFormatter` for "2 min ago".
- [ ] **Phone** — `libPhoneNumber-iOS` or server-provided format respecting E.164 + locale.

### 27.3 Plural rules
- [ ] **`.xcstrings` variations** — singular/plural/zero per language.
- [ ] **Examples** — "1 ticket" / "N tickets"; handle CJK (no plurals) + Arabic (six forms).

### 27.4 RTL layout
- [ ] **Mirror UI** — `.environment(\.layoutDirection, .rightToLeft)` pseudo-locale testing.
- [ ] **SF Symbols** with `.imageScale(.large)` auto-mirror for directional (`arrow.right`).
- [ ] **Charts** tested in RTL.
- [ ] **Pickers + chips** respect RTL flow.

### 27.5 Target locales (roadmap)
- [ ] **Phase 1 launch** — en-US.
- [ ] **Phase 2** — es-MX, es-US, es-ES (biggest repair-shop demographic overlap).
- [ ] **Phase 3** — fr-FR, fr-CA, pt-BR, de-DE.
- [ ] **Phase 4** — zh-Hans, ja-JP, ko-KR, vi-VN, ar-SA, tr-TR.

### 27.6 Server-side strings
- [ ] **Category names / status labels** — server sends translated per `Accept-Language`.
- [ ] **Receipt/invoice PDF** — server-rendered in tenant locale.

### 27.7 Multi-language tenants
- [ ] **Customer preferred language** field → SMS templates picked by customer locale.
- [ ] **Staff-facing UI** follows device locale; customer-facing follows customer pref.

### 27.8 Font coverage
- [ ] **SF fallback** for all CJK + Arabic glyphs (Inter / Barlow lack full coverage).
- [ ] **System font substitution** automatic via `Font.system(.body, design: .default)`.

### 27.9 Date/time edge cases
- [ ] **Time zone** — tenant TZ + user TZ; conflicts shown explicitly.
- [ ] **Timezone picker** — IANA list searchable.
- [ ] **DST transitions** — appointment logic respects overrides.
- [ ] **24h vs 12h** — device locale.

### 27.10 Currency edge cases
- [ ] **Multi-currency tenants** — rare but possible; tenant-configured base currency.
- [ ] **Rounding** per currency conventions.
- [ ] Per-locale glossary files at `docs/localization/<locale>-glossary.md` listing preferred translation per domain term (prevents translator drift).
- [ ] Examples en → es: ticket → ticket (not "boleto"), inventory → inventario, customer → cliente, invoice → factura, refund → reembolso, discount → descuento, membership → membresía.
- [ ] Style per locale: formal vs informal tone (Spanish "usted" vs "tú"); per-tenant override for formality.
- [ ] Gender-inclusive: prefer neutral phrasing where grammar allows; cashier → persona cajera vs cajero/a, tenant configures.
- [ ] Currency + dates via `Locale` formatter — never translate numbers manually.
- [ ] Workflow: English source in `Localizable.strings` → CSV export to vendor → import translations; pseudo-loc regression (`xx-PS`) for ~30% expansion truncation check.
- [ ] Supported RTL languages: Arabic, Hebrew, Farsi, Urdu.
- [ ] Mirroring via SwiftUI `.environment(\.layoutDirection, .rightToLeft)`; all custom views use logical properties (leading/trailing), never `.left`/`.right`.
- [ ] Icon policy: directional icons (arrows, back chevrons) flip; non-directional (clock, info) stay.
- [ ] Numerals: Arabic locale uses Eastern Arabic numerals unless tenant overrides.
- [ ] Mixed-content: LTR substrings (English brand/IDs) inside RTL paragraph wrapped with Unicode bidi markers.
- [ ] Audit: pseudo-loc RTL snapshot run on every screen.
- [ ] POS / receipts: ensure thermal receipts in RTL locales print mirrored correctly.

---
## §28. Security & Privacy

**Placement: partly Phase 0 foundation, partly per-feature enforcement, partly Phase 11 release gate.** Not a "ship then audit" afterthought; not a single-sprint deliverable either.

- **Phase 0 foundation** (built with the networking / persistence / DI layers; enforced by infra so domains can't skip):
  - §28.1 Keychain wrapper (the only API for secrets; lint bans direct `SecItem*`).
  - §28.2 SQLCipher wired into GRDB at project-init (rationale below — this is not redundant with iOS sandboxing).
  - §28.3 Network baseline (ATS on; `PinnedURLSessionDelegate` infrastructure; `URLSession` banned outside `Core/Networking/`).
  - §28.4 Privacy manifest skeleton.
  - §28.5 Usage-description strings in `scripts/write-info-plist.sh`.
  - §28.6 Export-compliance flag.
  - §28.7 Logging redaction contracts (lint: `.private` required on dynamic params in `os_log`).
  - §28.12 Tenant data sovereignty (single egress to `APIClient.baseURL`; SDK-ban lint per §32).

- **Per-feature enforcement** (every domain PR does these; no standalone agent):
  - §28.8 Screen protection on sensitive screens.
  - §28.9 Pasteboard hygiene when copying sensitive values.
  - §28.10 Biometric gate before destructive / high-value actions.
  - §28.13 Compliance hooks (GDPR export link, PHI opt-out respected, PCI scope narrow via BlockChyp tokenization).
  - §28.14 Session / token handling + force-re-auth thresholds per feature.

- **Phase 11 release gate** (pre-submission):
  - §28.11 Jailbreak / integrity re-evaluated per release.
  - §90 STRIDE review via `security-reviewer` agent.
  - Dependency CVE scan + secret scan on main before tag.
  - Privacy-manifest diff vs prior release documented.
  - External penetration test once per major release.

**Per-PR security checklist (added to PR template):**
- New secrets → only via `KeychainStore` API.
- New network call → only through `APIClient` → only to tenant base URL; lint flags bare `URLSession`.
- New sensitive screen (tokens, PIN, PAN, waiver, audit, payment) → `privacySensitive()` + `.screenProtected()` modifier + pasteboard hygiene.
- New log line → `os_log` with `.private` on every dynamic param.
- New third-party dep → read its privacy manifest, aggregate into ours, `security-reviewer` sign-off if it adds a network peer.

### 28.1 Secrets storage
- [ ] **Keychain** — access tokens, refresh tokens, PIN hash, DB passphrase, BlockChyp API key, 2FA backup codes, printer/terminal identifiers. Class `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- [ ] **Service naming** — `com.bizarrecrm.<purpose>` pattern; access group shared with widget extension where needed.
- [ ] **UserDefaults** — non-secret prefs only (theme, sort order, last-used tab).
- [ ] **App Group UserDefaults** — shared prefs between app + widgets (no secrets).
- [ ] **Delete on logout** — Keychain keys scoped to user/tenant deleted.

### 28.2 Database encryption

**Why SQLCipher when iOS already sandboxes the app container?** Good question worth answering explicitly so we don't skip this later under the impression it's redundant.

iOS sandbox alone does **not** cover these realistic threats:

1. **Device backups (Finder / iTunes / iMazing / forensic tools).** Every file in the app container goes into the backup unless the user sets a backup password. Backups are routinely read by third-party tools — including ones in the wrong hands. SQLCipher keeps a backup-extracted DB unreadable without the Keychain-held key (which is not in the backup).
2. **iCloud Backup.** Apple holds the encryption keys for iCloud Backup by default (not E2E unless Advanced Data Protection is on). Compelled access or breach = tenant's customer records readable. SQLCipher keeps the DB opaque at that layer too.
3. **Lost / stolen device + forensic extraction.** Files protected below `.complete` are exposed at rest. Law-enforcement and nation-state tooling has demonstrated extraction of `.completeUnlessOpen` and `.afterFirstUnlock` files. Adding SQLCipher is a second lock.
4. **Jailbroken devices.** Sandbox defeated. Any app can read any other app's `Documents/`. SQLCipher still requires the key held in Keychain (which is further defended).
5. **Shared desktop / corporate IT.** Someone else with physical access to a desktop that once made a backup of the device can read unencrypted app data.
6. **Regulatory compliance.** PCI-DSS, HIPAA, GDPR "appropriate technical measures" all expect encryption at rest. Documentation + audit evidence is vastly easier with SQLCipher than arguing "iOS sandbox is enough."

What SQLCipher does **not** defend against (be honest):

- **After-First-Unlock (AFU) state on a live device.** The Keychain-held key uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; once the user unlocks the device after boot, the key is accessible to our process. An attacker with a live, unlocked, running device can read the DB via our process just like iOS data-protection could. SQLCipher isn't a silver bullet for live-device compromise — that's what PIN-gated re-auth (§19.2) and sensitive-screen biometric prompts (§28.10) are for.
- **Memory inspection via debugger on a jailbroken device.** Attach a debugger to a running process → game over.

Trade-offs accepted:
- ~5–10% write / 1–5% read perf cost. Acceptable.
- Can't open DB in stock `sqlite3` CLI without the key — debugging uses an authenticated `sqlcipher` wrapper in dev builds only.
- Dep: GRDB-SQLCipher variant or the separate `sqlcipher` pod.

Tasks:
- [ ] **SQLCipher** — full DB encrypted at rest; passphrase derived from Keychain-stored random 32-byte key. Default build config — not optional.
- [ ] **Encrypted attachments** — photos / PDFs stored in AppSupport encrypted at the iOS-data-protection layer (class `.completeUntilFirstUserAuthentication` = `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). SQLCipher-opaque metadata rows reference them by ID.
- [ ] **Per-tenant passphrase** — each tenant's DB gets its own 32-byte Keychain item keyed by tenant slug. Signing in to tenant B never reads tenant A's DB.
- [ ] **Full-wipe utility** — Settings → Danger → Reset wipes DB files + Keychain items + attachment cache.
- [ ] **Key rotation** — support `PRAGMA rekey` when tenant server signals a mandated rotation; documented in runbook.
- [ ] **Developer DX** — debug builds can open local DB via a CLI wrapper that pulls the key from Keychain only when an engineer has Xcode attached; never ship the wrapper in Release.

### 28.3 Network
- [ ] **App Transport Security** — HTTPS only; no `NSAllowsArbitraryLoads`.
- [ ] **SPKI pinning** — `PinnedURLSessionDelegate` pins one or more cert SPKIs; rotation list per tenant.
- [ ] **Fallback** — if pin fails, refuse connection + glass alert.
- [ ] **Proxy / MITM detection** — warn user in dev builds.
- [ ] **Certificate rotation** — remote config of pin list with 30-day overlap.

### 28.4 Privacy manifest
- [ ] **`PrivacyInfo.xcprivacy`** — audited per release; declares API usage:
  - `NSPrivacyAccessedAPITypeFileTimestamp` (reason: `CA92.1`)
  - `NSPrivacyAccessedAPITypeDiskSpace` (`E174.1`)
  - `NSPrivacyAccessedAPITypeSystemBootTime` (`35F9.1`)
  - `NSPrivacyAccessedAPITypeUserDefaults` (`CA92.1`)
- [ ] **Third-party SDK manifests** — BlockChyp, Starscream, Nuke, GRDB bundle their own; we aggregate.
- [ ] **Tracking domains** — none.
- [ ] **Data types collected** — coarse location (POS geofence), device ID (IDFV for analytics, opt-in), contact info (customer records — tenant data, not device user's).

### 28.5 Required usage descriptions (Info.plist)
- [ ] `NSCameraUsageDescription` — "Capture ticket photos, receipts, and customer avatars."
- [ ] `NSPhotoLibraryUsageDescription` — "Attach existing photos to tickets and expenses."
- [ ] `NSPhotoLibraryAddUsageDescription` — "Save generated receipts and reports to your photo library."
- [ ] `NSMicrophoneUsageDescription` — "Record voice messages in SMS."
- [ ] `NSLocationWhenInUseUsageDescription` — "Verify you're at the shop when clocking in."
- [ ] `NSContactsUsageDescription` — "Import contacts when creating new customers."
- [ ] `NSFaceIDUsageDescription` — "Sign you in quickly with Face ID."
- [ ] `NSBluetoothAlwaysUsageDescription` — "Connect to receipt printer, barcode scanner, and weight scale." (Card reader is NOT Bluetooth — BlockChyp uses IP only per §17.3.)
- [ ] `NSLocalNetworkUsageDescription` — "Find printers and terminals on your network."
- [ ] `NFCReaderUsageDescription` — "Read device serial tags."
- [ ] `NSCalendarsUsageDescription` — "Sync appointments with your calendar."

### 28.6 Export compliance
- [ ] **`ITSAppUsesNonExemptEncryption = false`** — only use HTTPS + standard Apple crypto; skip export-compliance paperwork.

### 28.7 Logging redaction
- [ ] **`privacySensitive()`** on password, PIN, SSN fields.
- [ ] **`OSLog` privacy levels** — `.private` on tokens, phones, emails.
- [ ] **Crash logs** — no PII via symbolication hooks.
- [ ] **Network inspector** in dev redacts Authorization header.

### 28.8 Screen protection

Three different iOS signals, three different defenses:

| Event | How we detect | iOS lets us prevent? | What we do |
|---|---|---|---|
| User took a screenshot | `UIApplication.userDidTakeScreenshotNotification` fires AFTER the image is saved to Photos. iOS does not name the screen or pass the image. | **No.** iOS never blocks screenshots for third-party apps. | Log an audit entry (user, screen, timestamp) for sensitive screens; optionally show a brief banner "Receipts contain customer info — share carefully." Banner is optional/tenant-configurable. |
| User / system is screen-recording or mirroring | `UIScreen.main.isCaptured == true` + `UIScreen.capturedDidChangeNotification` fires when it starts / stops. iOS doesn't distinguish AirPlay mirroring vs Control-Center recording, but both are `isCaptured`. | **No direct block**, but we can swap the sensitive content out of the capture. | Swap the sensitive view for a blurred placeholder while `isCaptured == true`; restore on flip back. Required on payment / 2FA / credentials-reveal / PIN-entry / audit-export screens. Customer-facing display (§16) explicitly opts out because it's intentional. |
| App backgrounds (App Switcher snapshot) | `applicationWillResignActive` / SwiftUI `.scenePhase == .inactive`. | **Yes** — we control what the snapshot captures. | Overlay a branded blur view BEFORE the system takes the snapshot; remove on `didBecomeActive`. Always on, no toggle needed. |
| Sensitive input fields | — | **Yes, iOS 17+**: `UIView.isSecure = true` marks a view as content-protected; its pixels are excluded from screen-record capture AND from screenshots (replaced with black). Equivalent SwiftUI modifier pattern (via UIViewRepresentable wrapper) until Apple ships one. | Apply on PIN entry, OTP entry, PAN-masked displays, full-card reveal (not used but the plumbing exists). |

Tasks:
- [ ] **Privacy snapshot on background** — blur overlay always on; no toggle. `willResignActive` → swap root for branded snapshot view → restore on active.
- [ ] **Screen-capture blur** — `UIScreen.capturedDidChange` handler swaps sensitive views for a blur placeholder while `isCaptured == true`.
- [ ] **Screenshot detection** — `userDidTakeScreenshotNotification` observed globally; writes an audit entry with user + screen identifier + UTC timestamp on sensitive screens (payment, 2FA, receipts containing PAN last4, audit export). Optional one-shot banner to the user on receipts. No attempt to block — iOS does not allow it.
- [ ] **`isSecure`** — iOS 17+ secure-content flag applied to PIN / OTP / masked-card fields so their pixels don't make it into screen recordings or screenshots at all.

### 28.8.1 Sovereignty note
Screen-protection audit entries go to the tenant server (§32), not third-party analytics. Screenshot notifications cannot carry image data anyway; iOS would never hand us the image even if we wanted it.

### 28.9 Pasteboard hygiene

- [ ] **OTP paste** — `UITextContentType.oneTimeCode` is the right content type for the 2FA code field. iOS offers the code from the most recent Messages automatically; no need for us to read the pasteboard manually.
- [ ] **OTP copy** — when server-issued codes must be displayed (rare — e.g., 2FA backup codes screen), copy with `UIPasteboard.setItems(…, options: [.expirationDate: 60])` so the code clears in 60s.
- [ ] **Card number — we never copy it.** Our app never handles raw PAN (§16.6 + §17.3 — BlockChyp tokenizes on the terminal or in its SDK sheet). So there is no "copy card number" code path in our app to defend; the relevant pasteboard events happen entirely inside the BlockChyp SDK process.
- [ ] **Generic copies** — ticket ID, invoice #, SKU, email, phone copy with no expiration (non-sensitive).
- [ ] **Paste-to-app** — we use `PasteButton` (iOS 16+) for user-initiated paste so iOS doesn't show the "Allowed X to access pasteboard" toast.
- [ ] **No pasteboard reads without user action** — SwiftLint rule forbids `UIPasteboard.general.string` in view code.

### 28.9.1 Manual card entry — disable Apple AutoFill & keyboard predictions

Even though we don't build native `TextField`s for PAN/expiry/CVV ourselves, we still have to actively **not** invite Apple to try to autofill / suggest card data in any of our surfaces. This matters in two places:

1. **Address / billing-info fields that sit next to card entry** (for example if we collect ZIP for AVS on a cardholder-not-present flow, even when BlockChyp's tokenization sheet does the rest).
2. **Any other numeric or short field a user might mistake for a card field** (customer phone, IMEI, coupon code).

Rules:
- [ ] **Never use `UITextContentType.creditCardNumber`** (or `creditCardExpiration*`, `creditCardSecurityCode`, `newPassword`, etc.) on any of our fields. That content type is what triggers iOS Keychain-stored cards to surface in QuickType and in the "Scan Card" camera prompt above the keyboard. We want none of that.
- [ ] **`.autocorrectionDisabled(true)` + `.textInputAutocapitalization(.never)`** on any field that might accidentally attract card-shaped suggestions (coupon code, IMEI, order number).
- [ ] **`.keyboardType(.numberPad)`** on numeric fields with **no** content-type set — pure numeric keyboard, no QuickType bar card-chip, no Scan Card prompt.
- [ ] **`textContentType(.oneTimeCode)`** is the ONE exception — only on the OTP field, where iOS's autofill is desired (Messages-sourced code).
- [ ] **Name / address fields** near payment flows use `.name`, `.postalCode`, etc. explicitly (so iOS offers contact info, not cards). Never leave `textContentType` blank on those — blank is the riskiest because iOS guesses.
- [ ] **BlockChyp SDK tokenization sheet (§16.6 cardholder-not-present path)** — the PAN-entry view lives inside the BlockChyp SDK's process; Apple AutoFill behavior there is BlockChyp's concern. We confirm via the SDK readme + a manual test each release that no iOS card-autofill surfaces inside their sheet on the devices we support; file an issue with BlockChyp if it does.
- [ ] **Lint rule** — SwiftLint custom rule flags `textContentType(.creditCardNumber)` and friends anywhere in our codebase.
- [ ] **Unit test** — snapshot-inspect the view hierarchy of each field on a payment/checkout screen, assert no field has a content-type from the `.creditCard*` family.

### 28.10 Biometric auth
- [ ] **`LAContext`** — `.biometryAny` preferred; fallback to PIN.
- [ ] **Reuse window** — 10s after unlock so confirm-on-save doesn't double-prompt.
- [ ] **Failure limits** — after 3 fails, drop to password.

### 28.11 Jailbreak / integrity
- [ ] **Heuristic detection** — file presence + sandbox escape checks; informational flag only (log, never block).
- [ ] **App Attest** (DeviceCheck) — verify device integrity per session.

### 28.12 Tenant data sovereignty
- [ ] **Tenant DBs are sacred** — never delete tenant DB to recover from missing state; only repair.
- [ ] **Per-tenant crypto key** — distinct passphrase per tenant so switching doesn't decrypt wrong data.

### 28.13 Compliance
- [ ] **GDPR export** — per-customer data package endpoint; mobile triggers + downloads.
- [ ] **CCPA delete request** — audit trail + soft-delete 30-day grace.
- [ ] **PCI-DSS scope** — BlockChyp handles card data; app never touches PAN.
- [ ] **HIPAA** — tenant-level toggle to avoid storing PHI (applies to some vet clinics / medical-device repair).

### 28.14 Session & token
- [ ] **Access token** 1h; refresh token 30d rotating.
- [ ] **Force re-auth** — on sensitive actions (void > $X, delete customer).
- [ ] **Token revocation** — server-sent 401 triggers global logout (already shipped).
- [ ] **Device trust** — "Remember this device" reduces 2FA prompts; 90-day expiration.
- [ ] Customer self-service portal (server-hosted at `/public/privacy`): email/phone → OTP verify → Export my data (ZIP: tickets, invoices, SMS history, photos) / Delete my data / Opt out of marketing.
- [ ] Staff-side: Customer detail → Privacy actions menu. Export builds ZIP + emails customer via tenant. Delete tombstones PII (name → "Deleted Customer") but preserves financial records (legal retention); receipts / invoices keep aggregated numbers.
- [ ] Audit: every privacy request logged (actor / customer / action / outcome / timestamp).
- [ ] Processing stays on tenant server — no third-party data processor (§32 sovereignty).
- [ ] Opt-out flags on customer record: `do_not_call` / `do_not_sms` / `do_not_email`. System blocks sends if set; composer warning (§12).
- [ ] Primary rule: native-first. `WKWebView` used only for embedded PDF viewer, receipt preview (when no printer), and in-app help content. Never third-party sites.
- [ ] Config: JavaScript enabled only when strictly needed; cookies isolated in per-WebView `WKWebsiteDataStore.nonPersistent()`; User-Agent suffix identifies our app.
- [ ] External links open in `SFSafariViewController` inline never.
- [ ] `WKNavigationDelegate` rejects any URL not on `APIClient.baseURL.host` allowlist.
- [ ] CSP headers set by tenant server on in-webview pages; verified on page load.
- [ ] Copy triggers: long-press on IDs/emails/phones/SKUs → "Copy" menu; ticket detail header chip `#4821` tap → copy with haptic; invoice number+total same way
- [ ] Feedback: haptic `.success` + toast "Copied" (2s); dedup identical copies within 3s to avoid toast spam
- [ ] Paste: form fields auto-detect tenant-URL paste → auto-populate host; phone field parses pasted numbers (removes formatting)
- [ ] Pasteboard hygiene: `UIPasteboard.string` access wrapped in audit log on sensitive screens; prefer iOS 17+ `pasteButton` for user-initiated paste to avoid access warnings
- [ ] Auto-clear: after paste of sensitive content (credentials), offer to clear pasteboard
- [ ] Universal Clipboard works across Apple devices seamlessly via iCloud Handoff; no special code needed
- [ ] See §57 for the full list.

---
## §29. Performance Budget

### 29.1 Launch time
- [ ] **Cold launch** < 1500ms on iPhone 13; < 1000ms on iPhone 15 Pro; < 2500ms on iPhone SE (2022).
- [ ] **Deferred init** — analytics, feature flags, non-critical framework init moved to `Task.detached(priority: .background)`.
- [ ] **Lazy tabs** — only Home tab initialized on launch; others lazy.
- [ ] **Pre-main optimization** — minimal dynamic libraries; ≤ 10 frameworks.
- [ ] **Splash to first frame** < 200ms.
- [ ] **Warm launch** < 500ms.

### 29.2 Scroll & render
- [ ] **List scroll** — 120fps on iPad Pro M; 60fps min on iPhone SE (no drops > 2 frames).
- [ ] **`List` (not `LazyVStack`)** for long scrolling lists; UITableView cell reuse.
- [ ] **Stable IDs** — server `id` (never `UUID()` per render); `.id(server.id)` on rows.
- [ ] **`EquatableView`** wrapper on complex row content.
- [ ] **`@State` minimized** — prefer `@Observable` models at container; leaf views stateless.
- [ ] **No ViewBuilder closures holding strong refs** — weakify self in VM callbacks.
- [ ] **Redraw traces** — SwiftUI `_printChanges()` on critical views in debug.

### 29.3 Image loading

Earlier draft said 500 MB disk cap. Too small for medium+ shops (200 tickets/day × 5 photos × ~700 KB ≈ 1 GB/day raw, even after thumbnailing the archive grows fast) and too aggressive if paired with blunt LRU — evicting a photo a tech still needs on a current ticket. Rewrite with scaled defaults + a tiered retention model.

- [ ] **Nuke** image pipeline — shared across screens.
- [ ] **Tiered cache**:
  - **Memory cache (fast-scroll)**: 80 MB default. For frequently-viewed thumbnails. Flushes on `didReceiveMemoryWarning` (§1.5).
  - **Disk cache — thumbnails**: separate pipeline. ~20 KB each, generous cap (500 MB default = ~25k thumbs). Always cacheable; eviction is never noticeable because re-fetching a thumb is cheap.
  - **Disk cache — full-res**: default 2 GB, user-configurable 500 MB – 20 GB or "No limit (use available storage)". LRU eviction starts only past cap. Full-res photos are the biggest, most expensive to re-fetch, and most worth pinning smartly.
  - **Pinned-offline store**: photos attached to **active** (not-archived) tickets and photos attached in last 14 days are NOT subject to LRU eviction regardless of cap. Stored under `offline_pinned/` with metadata referring to parent ticket / SKU. These count toward the user-visible "App storage" number but do not get auto-pruned.
- [ ] **Eviction policy — not blunt LRU**:
  - Archived-ticket photos evicted first.
  - Photos older than 90 days and not viewed in last 30 days evicted next.
  - Thumbnails evicted last (they're tiny and always useful).
  - Full-res photos attached to an active ticket or the current user's own recent activity never auto-evicted.
- [ ] **Manual pin** — "Keep offline" toggle on ticket detail + inventory item. Moves referenced images into `offline_pinned/`. Useful for a tech about to work off-grid.
- [ ] **Storage panel (Settings → Data)** — shows breakdown: Thumbnails X MB / Full-res Y MB / Pinned Z MB / DB W MB / Logs V MB. Per-row "Clear" buttons (except DB + pinned — those require explicit Danger-zone action).
- [ ] **Re-fetch on tap** — if a requested full-res was evicted and we're online, refetch transparently with a faint "Downloading…" label. If offline, show thumbnail + "Available when online" chip; never blank.
- [ ] **Prefetch** next 10 rows on scroll (online only; skips on cellular + Low Data Mode or `NWPathMonitor.isConstrained`).
- [ ] **Thumbnail vs full** — rows always use thumb; detail uses full; gallery uses progressive to show thumb then upgrade.
- [ ] **Progressive JPEG** decode.
- [ ] **Formats accepted on decode (iOS side)**: JPEG, PNG, **HEIC** (iOS default since iOS 11), **HEIF**, **TIFF** (multi-page supported; show first page as thumbnail, page-picker on detail), **DNG** (raw — use embedded JPEG preview for thumb, full decode on detail). Nuke relies on iOS Image I/O which handles all of the above; no custom decoder code needed for iOS.
- [ ] **Gracefully reject unknown formats** (BMP / WebP-without-iOS-support / SVG as raster) with "Can't preview — download to view" + download-to-Files action.
- [ ] **Orientation / ICC profile** preserved through thumbnail resize; wide-gamut P3 images stay P3 on P3-capable displays.
- [ ] **Upload encoding** — whatever the user picked stays as-is if the tenant server accepts it. Otherwise transcode to JPEG quality 0.8 before upload, keep original locally for this device (user expectation: "the photo I took is safe").
- [ ] **Server + Android parity** for TIFF / DNG / HEIC end-to-end is tracked as `IMAGE-FORMAT-PARITY-001` in root TODO. If server or Android doesn't handle a format, iOS refuses to upload that format to that tenant and surfaces "Your shop's server doesn't accept X — please convert or attach a different file."
- [ ] **Placeholder** — SF Symbol + brand tint on load.
- [ ] **Failure** — branded SF Symbol + retry tap.
- [ ] **Tenant-size defaults** — on first launch after login, read tenant "size tier" hint from `/auth/me` (`tenant_size: s | m | l | xl`) and pick an initial cap (s=1GB, m=3GB, l=6GB, xl=10GB). User can override.
- [ ] **Cleanup is defensive, not aggressive** — runs at most once / 24h in `BGProcessingTask` (not on main thread). Never during active use.
- [ ] **Low-disk guard** — if device < 2 GB free, temporary freeze on writes to cache, toast "Free up space — app cache paused" without deleting anything the user might be mid-using.

### 29.4 Pagination
- [ ] **Cursor pagination (offline-first)** — server returns `{ data, next_cursor?, stream_end_at? }`. iOS persists cursor in GRDB per `(entity, filter)` along with `oldestCachedAt` and `serverExhaustedAt`. Lists read from GRDB via `ValueObservation` — never from API directly. `loadMoreIfNeeded(rowId)` triggers next-cursor fetch only when online.
- [ ] **Prefetch** at 80% scroll (50-item chunks) — only if online; offline skips prefetch silently.
- [ ] **Load-more footer** — four states: `Loading…` / `Showing N of ~M` / `End of list` / `Offline — N cached, last synced Xh ago`. Never ambiguous.
- [ ] **Skeleton rows** during first load only (cached refresh uses existing rows + subtle top indicator).
- [ ] **No `page=N` / `total_pages` references in iOS code.** Any server endpoint still returning page-based shape wrapped by a client adapter that derives a synthetic cursor.

### 29.5 Glass budget
- [ ] **≤ 6 active glass elements** visible simultaneously (iOS 26 GPU cost).
- [ ] **`GlassEffectContainer`** wraps nearby glass elements on iOS 26.
- [ ] **Fallback** — pre-iOS 26 uses `.ultraThinMaterial`.
- [ ] **Enforcement** — debug-build `assert(glassBudget < 6)` inside `BrandGlassModifier` (reads `\.glassBudget` env value, increments on apply) + SwiftLint rule counting `.brandGlass` call sites per View body. No runtime overlay.

### 29.6 Memory
- [ ] **Steady state** < 120 MB on iPhone SE for baseline (Dashboard + 1 list loaded).
- [ ] **Heavy list** (1000+ rows) < 220 MB.
- [ ] **POS with catalog** < 300 MB.
- [ ] **Memory warnings** — flush image cache + Nuke memcache + GRDB page cache.

### 29.7 Networking
- [ ] **URLSession config** — HTTP/2; caching disabled for data calls (handled by repo).
- [ ] **Connection reuse** — keep-alive; avoid per-call sessions.
- [ ] **Request coalescing** — dedupe concurrent same-URL requests.
- [ ] **Timeout** — 15s default; 30s for large uploads.
- [ ] **Compression** — Accept-Encoding: gzip, br.

### 29.8 Animations
- [ ] **Springs** — use `.interactiveSpring` for responsiveness.
- [ ] **Avoid layout thrashing** — no animated heights on parent of scrollable.
- [ ] **Opacity + transform** preferred over layout changes.

### 29.9 Instruments profile
- [ ] **Time Profiler** — no single function > 5% main-thread time on a list scroll.
- [ ] **Allocations** — no unbounded growth over 5 min session.
- [ ] **Metal Frame Capture** — check overdraw on glass stacks.
- [ ] **SwiftUI Profiler** — no view body > 16ms.
- [ ] **Network** — audit request waterfall on first-launch.

### 29.10 App size
- [ ] **App Store download** < 60 MB (goal); < 100 MB cap.
- [ ] **On-device install** < 200 MB.
- [ ] **On-demand resources** for large assets (illustrations / video tutorials).
- [ ] **Asset catalogs** use .xcassets for proper slicing.
- [ ] **App thinning** enabled.

### 29.11 Battery
- [ ] **Background tasks** respect budget (30s).
- [ ] **Location** — `whenInUse` only; no always-on GPS.
- [ ] **WS ping** 25s interval (not 5s).
- [ ] **Network batching** on cellular.

### 29.12 Telemetry perf
- [ ] **First-paint metric** uploaded per launch.
- [ ] **Hitch rate** measured (`MetricKit`).
- [ ] **Alerting** — `MXHitchDiagnostic` triggered events pipelined.
- [ ] List thumbnails: `LazyVStack` + Nuke `FetchImage` → only loads in viewport; prefetch 5 ahead/behind
- [ ] Placeholders: blurhash on first paint if server provides hash; SF Symbol fallback on error
- [ ] Priority: higher for visible rows, lower for prefetch; cancel on scroll-past
- [ ] Progressive: render progressive JPEGs via Nuke while downloading
- [ ] Thumbnail sizing: request server-resized thumbnails (e.g. `?w=120`); never load full-res for list rows
- [ ] Retina: request 2x/3x variants based on `UIScreen.main.scale`
- [ ] Budget: never drop below 60fps on iPhone SE 3; 120fps on ProMotion iPad
- [ ] Cell prep: row subviews lightweight; no heavy work in `onAppear`; expensive calcs in `.task` or ViewModel cache
- [ ] Materials: glass materials expensive — group via `GlassEffectContainer`; limit ≤6 visible glass elements per screen
- [ ] Measurement: Instruments Time Profiler + SwiftUI `_printChanges()` during dev; CI runs XCTMetric scrolling benchmark
- [ ] Lists > grids for long scrolls: `LazyVStack`/`List` for long lists; `LazyVGrid` OK for gallery but limits row-height flexibility
- [ ] Image decode: off main thread via Nuke; no `UIImage(named:)` inside cell body
- [ ] SwiftUI `List`: native virtualization — use where possible; custom row height via `.listRowSeparator`, `.listRowInsets`
- [ ] `LazyVStack` alternative when `List` style too rigid; requires own diffing for animated inserts/removes
- [ ] Anchoring: maintain scroll position on insert-at-top; `ScrollViewReader` for programmatic scroll (e.g. scroll-to-latest SMS)
- [ ] Jump-to: iPad sidebar letter rail A-Z for fast jump; jump preserves filters
- [ ] Estimated sizes: provide estimated height when rows vary so scrollbar is accurate
- [ ] Diffable: use `Identifiable` models with stable IDs; never reuse IDs across deletions
- [ ] Detection: observe `ProcessInfo.processInfo.isLowPowerModeEnabled` changes; show banner "Low Power Mode on — reduced sync"
- [ ] Behavior: halve background refresh cadence; disable push-registered silent pushes; pause image prefetch (§29.4); cap animations to 0.2s duration; reduce Glass intensity (swap to thin material)
- [ ] User override: Settings toggle "Use normal sync even in Low Power"
- [ ] Resume: on exiting LPM, kick off full sync
- [ ] Detection: observe `ProcessInfo.thermalState` — `.nominal`/`.fair` unchanged; `.serious` reduces animation intensity + defers background work; `.critical` shows banner "Device is hot — some features paused"
- [ ] Pause tasks when thermal `.serious`+: photo batch uploads; FTS5 reindex; image decode to lower priority
- [ ] POS continuity: checkout never paused (too disruptive); print/receipt/payment stay active
- [ ] XCTMetric golden-path tests for launch / scroll / search / payment; baselines in repo; CI fails on > 10% regression.
- [ ] Instruments CLI automation: Time Profiler, Allocations, Animation Hitches; archive reports per build.
- [ ] Benchmarks catalog: cold launch, warm launch, dashboard first paint, tickets list 1000-row scroll, inventory search 500 items, SMS thread 500-message scroll, POS add 20 items + checkout, photo attach 5 photos, sync 100 changes.
- [ ] Device matrix: iPhone SE 3 (floor), iPhone 16 Pro, iPad 10 (low-end), iPad Pro 13" M4, Mac Mini M4 (Designed for iPad).
- [ ] Reporting: CI trends dashboard + email summary to team (sovereignty → no Slack).
- [ ] Methodology: MetricKit `MXSignpostMetric` + manual device-power-meter runs; 30-min fixed activity per screen measuring mAh draw.
- [ ] Budgets: dashboard static ~50mAh/hr; tickets list scroll ~150mAh/hr; POS active ~200mAh/hr (scanner on); SMS compose ~100mAh/hr; camera active ~400mAh/hr (brief use); reports chart ~80mAh/hr.
- [ ] Anti-patterns: replace polling with silent push; pause idle animations after 30s inactive; location only when needed (§21).
- [ ] Regressions: PR template battery-impact self-check; post-merge CI sample on instrumented device.
- [ ] User surface: Settings → Diagnostics → Battery impact with last-24h tab breakdown.
- [ ] Sovereignty: all battery telemetry local + tenant-server only.

---
## §30. Design System & Motion

### 30.1 Color tokens (`DesignSystem/Colors.swift`)
- [ ] **Brand**: `brandPrimary` (orange), `brandSecondary` (teal), `brandTertiary` (magenta).
- [ ] **Surfaces**: `surfaceBase` (dark near-black), `surfaceElevated`, `surfaceSunken`, `surfaceOverlay`.
- [ ] **Text**: `text`, `textSecondary`, `textTertiary`, `textOnBrand`, `textMuted`.
- [ ] **Dividers**: `divider`, `dividerStrong`.
- [ ] **Status**: `success`, `warning`, `danger`, `info`.
- [ ] **Glass tints**: `glassTintDark`, `glassTintLight`.
- [ ] **All tokens** — asset-catalog with light + dark + high-contrast variants.

### 30.2 Spacing (8-pt grid)
- [ ] **Tokens**: `xxs (2)`, `xs (4)`, `sm (8)`, `md (12)`, `base (16)`, `lg (24)`, `xl (32)`, `xxl (48)`, `xxxl (72)`.
- [ ] **Density mode** — "compact" multiplies by 0.85 globally.

### 30.3 Radius
- [ ] **Tokens**: `sm (6)`, `md (10)`, `lg (16)`, `xl (24)`, `pill (999)`, `capsule`.

### 30.4 Typography (`DesignSystem/BrandFonts.swift`)

Inspected bizarreelectronics.com (WordPress + Elementor) 2026-04-20 — real brand fonts are Google Fonts loaded via Elementor: **Bebas Neue**, **League Spartan**, **Roboto**, **Roboto Slab**. Match the iOS app to the live brand identity rather than shipping a divergent palette.

- [ ] **Display / Title** — **Bebas Neue** Regular. Condensed all-caps display face; mirrors the brand web's nav + section titles. Use for large numbers on dashboards (revenue, ticket counts), screen headers, CTAs where we want brand voice. Letter-spacing +0.5–1.0 at small sizes; tight at large sizes.
- [ ] **Body / UI** — **Roboto** (Regular / Medium / SemiBold). Workhorse for list rows, labels, form inputs, paragraphs. Replaces Inter. Falls back to SF Pro Text automatically via Dynamic Type system.
- [ ] **Accent / Secondary headings** — **League Spartan** (SemiBold / Bold). Geometric sans used on bizarreelectronics.com for emphasis. Use sparingly: section subtitles, empty-state headlines, marketing-tone copy. Don't mix with Bebas in the same visual line.
- [ ] **Mono** — **Roboto Mono** (Regular). IDs, SKUs, IMEI, barcodes, order numbers, log output. Keeps the Roboto family consistent instead of JetBrains Mono. `.monospacedDigit` variant for counters / totals so digits don't jitter.
- [ ] **Slab accent (optional)** — **Roboto Slab** SemiBold. Keep in the available set because the brand web uses it; probably only in a single accent spot (e.g., invoice-total print header) to avoid visual noise in UI.
- [ ] **Scale** — ties into §80.8 master typography table (rewritten to reflect this family swap):
  - `largeTitle` 34 Bebas Neue Regular
  - `title1` 28 Bebas Neue Regular
  - `title2` 22 League Spartan SemiBold
  - `title3` 20 League Spartan Medium
  - `headline` 17 Roboto SemiBold
  - `body` 17 Roboto Regular
  - `callout` 16 Roboto Regular
  - `subheadline` 15 Roboto Regular
  - `footnote` 13 Roboto Regular
  - `caption1` 12 Roboto Regular
  - `caption2` 11 Roboto Regular
  - `mono` 14 Roboto Mono
- [ ] **Dynamic Type** — each style keyed off a `Font.TextStyle` so iOS scaling honors user preference.
- [ ] **`scripts/fetch-fonts.sh`** — fetches the four Google Fonts families (OFL license, safe to bundle). Replaces the previous Inter / Barlow Condensed / JetBrains Mono fetch. Old files cleaned from `App/Resources/Fonts/` on next `bash ios/scripts/gen.sh`.
- [ ] **`UIAppFonts`** list in `scripts/write-info-plist.sh` updated: `BebasNeue-Regular.ttf`, `LeagueSpartan-Medium.ttf`, `LeagueSpartan-SemiBold.ttf`, `LeagueSpartan-Bold.ttf`, `Roboto-Regular.ttf`, `Roboto-Medium.ttf`, `Roboto-SemiBold.ttf`, `Roboto-Bold.ttf`, `RobotoMono-Regular.ttf`, `RobotoSlab-SemiBold.ttf`.
- [ ] **Fallback** — if fonts missing (fetch-fonts.sh not run), use SF Pro + SF Mono; log a one-time dev-console warning. Never crash.
- [ ] **Wordmark note** — the "BIZARRE!" logo wordmark on the web is a custom-drawn / SVG asset, NOT a typed font. Ship it as a vector asset in `Assets.xcassets/BrandMark.imageset/` (SVG + 1x/2x/3x PNG fallback), not by hand-typing "BIZARRE!" in a font.

Cross-ref: §80.8 master typography scale replaced to mirror this list; §80 already merged into §80.

### 30.5 Glass (`DesignSystem/GlassKit.swift`)
- [ ] **`.brandGlass(intensity:shape:)`** wrapper — iOS 26 `.glassEffect`; fallback `.ultraThinMaterial`.
- [ ] **Intensity** — subtle / regular / strong.
- [ ] **Shape** — rect / roundedRect(radius) / capsule.
- [ ] **`GlassEffectContainer`** — auto-wraps groups of nearby glass on iOS 26.
- [ ] **Anti-patterns** — glass-on-glass, glass on content, glass on full-screen background; `#if DEBUG` asserts.

### 30.6 Motion (`DesignSystem/BrandMotion.swift`)
- [ ] **Tokens**: `.fab` (160ms spring), `.banner` (200ms), `.sheet` (340ms), `.tab` (220ms), `.chip` (120ms).
- [ ] **Reduce Motion fallback** — each token returns `.easeInOut(duration: 0)` if a11y flag.
- [ ] **Spring** — `.interactiveSpring(response: 0.3, dampingFraction: 0.75)`.
- [ ] **Shared element transition** — matchedGeometryEffect for detail push.
- [ ] **Pulse** — used on "new" badges (scale 1.0 ↔ 1.05, 600ms).

### 30.7 Haptics (`DesignSystem/Haptics.swift`)
- [ ] **`.selection`** on picker / chip toggle.
- [ ] **`.success`** on save / payment success.
- [ ] **`.warning`** on validation error.
- [ ] **`.error`** on hard failure.
- [ ] **`.light impact`** on list item open.
- [ ] **`.heavy impact`** on destructive confirm.
- [ ] **Master toggle** in Settings; no-op on Mac.

### 30.8 Icon system
- [ ] **SF Symbols** primary — >99% of glyphs.
- [ ] **Custom glyphs** — brand mark only; bundled SF-compatible symbol.
- [ ] **Fill vs outline** — one consistent choice per role (nav=outline, active=fill).
- [ ] **Sizes** — `.small`, `.medium`, `.large` aligned to 16/20/24 pt.

### 30.9 Illustrations
- [ ] **Empty states** — branded flat illustrations (tickets / inventory / SMS).
- [ ] **Tinted** via `.foregroundStyle(.brandPrimary)`.
- [ ] **Lottie** animations for loading, errors, success — optional lightweight.

### 30.10 Component library (reusable)
- [ ] **`BrandButton(style: .primary/.secondary/.ghost/.destructive, size: .sm/.md/.lg)`**.
- [ ] **`BrandCard`** — elevated surface with stroke + shadow.
- [ ] **`BrandChip(status:)`** — status pill with icon + color.
- [ ] **`BrandTextField`** — glass-adjacent with label, hint, error state.
- [ ] **`BrandPicker`** — bottom sheet on iPhone, popover on iPad.
- [ ] **`BrandEmpty(icon:title:subtitle:cta:)`**.
- [ ] **`BrandLoading`** — skeleton placeholder.
- [ ] **`BrandBadge`** — numeric + status dot.
- [ ] **`BrandToast(kind:message:)`** — glass chip at top.
- [ ] **`BrandBanner(kind:message:action:)`** — sticky top banner (offline, sync-pending).

### 30.11 Tone of voice
- [ ] **Friendly + concise** copy.
- [ ] **Error messages** — what went wrong + what to do.
- [ ] **Confirmation dialogs** — describe action + consequence.
- [ ] **No jargon** — staff-facing translations (e.g., "IMEI" OK, "A2P 10DLC" not).

### 30.12 Theme choice — asked in Setup Wizard, not silently forced
- [ ] **First-run theme question** — §36 Setup Wizard dedicates one step to: `System (recommended)` / `Dark` / `Light`. Default selection = `System`. User can skip; skipping stores `System`.
- [ ] **Palette parity** — both dark and light modes are first-class and fully tested; neither is "secondary". Dark surface `bizarreSurfaceBase` tuned for OLED; light surface tuned for paper-feel at counter lighting.
- [ ] **Auto-switch** — when `System` selected, `@Environment(\.colorScheme)` drives surface swap; live-updating on iOS setting change.
- [ ] **Per-user override in Settings** — §19.4 Appearance → Theme (System / Dark / Light). Remembered per tenant (so sandbox vs prod can differ if user wants).
- [ ] **Kiosk mode override** — CFD / TV queue board / counter-facing modes can pin a theme regardless of system (§16).
- [ ] **Respect iOS Smart Invert + Increase Contrast** — palette swaps do not fight OS accessibility (see §26).

### 30.13 Storybook / catalog view
- [ ] **`#if DEBUG` catalog screen** — every component rendered with variants for visual regression.
- [ ] Three types: Toast (transient, non-blocking, 2s auto-dismiss, success/info); Banner (persistent until dismissed, offline/sync pending/error); Snackbar (transient with action, undo-window after destructive)
- [ ] Position: top on iPad (doesn't block bottom content); bottom on iPhone (thumb zone); avoid covering nav/toolbars
- [ ] Style: glass surface, small icon, 1-line message; color by severity (success green, info default, warning amber, danger red); never stack >2 visible
- [ ] `ToastQueue` singleton: FIFO with dedup — don't show same toast twice within 3s
- [ ] A11y: `accessibilityPriority(.high)` for VoiceOver; `announcement` on show
- [ ] Haptics: success=`.success`; warning=`.warning`; danger=`.error`
- [ ] Dismissal: swipe up (top) or down (bottom) to dismiss early; tap action area triggers callback
- [ ] Persistence: toast outlives push-navigation; dismissed only on user action or timeout
- [ ] Required when: destructive (delete/refund/cancel subscription); irreversible (void invoice/reset PIN); high-value (>threshold discount, large refund); role-privileged (admin override)
- [ ] UI: bottom sheet (iPhone) / centered modal (iPad); title = what happens; body = consequences; primary = destructive tint + action name ("Delete ticket"); secondary = "Cancel"
- [ ] Anti-misclick: primary visually dominant but placed right (opposite cancel) per Apple convention; critical ops require hold-to-confirm (3s progress ring)
- [ ] Typed confirmation for extreme ops (wipe tenant data / cancel subscription): user types tenant name to confirm
- [ ] Manager override: some ops need manager PIN even in admin session (e.g. big refund); PIN entry inline; can't bypass
- [ ] Undo window: soft-delete shows 10s snackbar with Undo; hard-delete only after snackbar expires
- [ ] Prevent rage-tap deletion: swipe-to-delete requires full swipe OR separate confirm after light swipe; never use double-tap-to-delete (ambiguous with double-tap-to-zoom)
- [ ] Delete confirmation defaults: primary button = Cancel (safe); destructive button on left, red
- [ ] Visual feedback: row redshift on destructive gesture ramp-up; haptic warning at commit point
- [ ] Recovery: deleted tickets/invoices go to Trash (30 days) before hard delete; manager can restore from Settings → Trash
- [ ] No swipe-to-delete on financial records (invoices/payments/receipts) — only via explicit Void action with reason
- [ ] Protect from force-delete edges: use `.swipeActions` not custom pan gestures to avoid iOS back-gesture vs row-swipe conflicts
- [ ] Entry: long-press on list row → select mode; toolbar swaps to selection mode (Select All / Deselect / Actions); iPad `EditButton()` in nav also enters
- [ ] Selection affordance: checkmark circle on left, chevron hidden; row tint shift; count badge in nav ("3 selected")
- [ ] Bulk actions: context-sensitive toolbar Assign/Archive/Status/Export/Delete; irreversible actions require confirm (§63)
- [ ] Select-all scope: "Select all on screen" (quick); "Select all matching filter" applies to all pages after confirm
- [ ] Cross-page selection persists while scrolling; nav badge "47 selected across 3 pages"
- [ ] Exit mode: Cancel button / Esc / tap outside list
- [ ] Drag-to-select (iPad Magic Trackpad / Pencil): drag rectangle across rows to add to selection
- [ ] Where: customer detail fields (name/phone/email/tags); ticket fields (status/notes/priority); inventory price/qty
- [ ] Affordance: pencil icon on hover (iPad) or long-press (iPhone); tap → field becomes editable with inline save
- [ ] Save behavior: blur triggers save (optimistic); ⌘S shortcut on iPad; Escape reverts
- [ ] Conflict: if server updated underneath, show conflict inline (§20.6)
- [ ] Validation: per-field, live; invalid state shows red underline + inline message
- [ ] Batch inline: keyboard Tab moves to next editable field
- [ ] Permission: fields read-only if user lacks edit permission; pencil icon hidden
- [ ] Timing: show errors on first blur/submit — never on first keystroke; clear errors as user types valid input
- [ ] Rules per field: email RFC 5322 light + typo suggest ("did you mean gmail.com?"); phone via libphonenumber-swift E.164 normalized; IMEI Luhn + 15 digits; password strength meter (4 levels) + min-length gate (no complexity theater); money locale decimal separator; date reasonable range (not 1900, not 3000)
- [ ] Server-side re-validate: client validation never authoritative; server validates on save; errors mapped via `field_errors: { ... }` envelope
- [ ] Accessibility: `.accessibilityElement` wraps field+error so VoiceOver reads both; error announced via `accessibilityNotification(.announcement)`
- [ ] Tooltips: iPad hover shows format hint; iPhone uses field placeholder + helper text under field
- [ ] Breakpoints: `.compact` (iPhone portrait, split iPad) = 1 col; `.regular` (iPhone landscape / small iPad) = 2 cols; `.wide` (iPad full / external monitor) = 3–4 cols; `.huge` (Studio Display) = 5+ cols
- [ ] `@Environment(\.breakpoint)` token, e.g. `Grid(cols: bp.cols(ticket: 1, 2, 3, 4)) { ... }`
- [ ] Layout components: `ResponsiveGrid` (auto-columns); `ResponsiveForm` (1 col compact / 2 col wide); `ResponsiveSplit` (master-detail or stacked)
- [ ] Rules: never assume iPhone — always read breakpoint; content max width 720pt inside cards so nothing stretches on 13" iPad
- [ ] Testing: snapshot at each breakpoint in CI (§31.4)
- [ ] Hierarchy: (1) Surface (`bizarreSurfaceBase` app background); (2) Content (cards, list rows); (3) Glass (nav, toolbars, sheets); (4) Overlay (alerts, toasts)
- [ ] Rules: glass never on Content layer; Overlay may sit atop glass with additional shadow; shadow on Content to separate from Surface; no shadow on Glass (blur is the separator)
- [ ] Z-index: toasts 1000; sheets 900; nav 500; content 0
- [ ] Transitions: glass appears with `.animation(.springSoft)` + `.opacity`; content slides without opacity to avoid flicker
- [ ] Background composition: `bizarreSurfaceBase` solid; glass picks up implied color from tint tokens; dark mode base `#0B0D10`, glass tint `#202228`
- [ ] Problem: bottom sheets (`.presentationDetents`) over keyboard hide content
- [ ] Sheet root uses `.ignoresSafeArea(.keyboard)` + inner scroll
- [ ] `defaultScrollAnchor(.bottom)` on active compose
- [ ] `.scrollDismissesKeyboard(.interactively)` so dragging sheet down dismisses keyboard
- [ ] Start at `.medium` detent; promote to `.large` on keyboard show
- [ ] Smooth detent transition with `.animation`
- [ ] Date / segmented pickers in sheets need `.submitLabel(.done)` + explicit commit
- [ ] External keyboard: avoidance no-ops; sheet stays as sized
- [ ] Three levels: Strong (iOS 26 full refraction), Medium (thin material + slight tint), Minimal (opaque tint for Reduce Transparency / Low Power).
- [ ] Auto-select: iOS 26 + A17+ → Strong; iOS 26 + A14-A16 → Medium; pre-iOS 26 → Medium; Low Power / Reduce Transparency → Minimal.
- [ ] Manual override in Settings → Appearance → Glass intensity (slider or 3 buttons); never fully disables glass.
- [ ] Perf budget: Strong ~2% extra GPU on scroll (fine on ProMotion); Minimal effectively free.
- [ ] Contrast invariant: text-on-glass ≥ 4.5:1 regardless of level.
- [ ] Sound list: sale success (coin drop 350ms), card tap (click 80ms), scan match (pitched confirm 120ms), drawer open (thud 250ms), error (buzz 200ms), SMS in (soft bell), payment approved (cash register ching), backup complete (ascending triad).
- [ ] Authoring spec: all ≤ 2s, 44.1kHz mono AAC, mastered to −14 LUFS.
- [ ] Tenant choice: each category ships with default + 2 alternates; Settings → Appearance → Sounds.
- [ ] Respect: silent switch + Focus modes + per-category user toggle.
- [ ] A11y: pair sound with haptic so deaf users still perceive.
- [ ] Licensing: all sounds in-house or royalty-free (no ASCAP/BMI risk).
- [ ] Primary mark: "Bizarre" wordmark in Barlow Condensed + icon glyph (wrench intersecting spark).
- [ ] Placement: launch screen, login splash, about screen, printed receipts header, empty-state illustrations.
- [ ] Don'ts: no recolor outside brand palette, no distortion, no glass-stacking without glass-container wrapping.
- [ ] Tenant co-branding: tenant logo top-billed on printed docs; "Powered by Bizarre" small foot.
- [ ] Sizing: 44pt min tap target on tappable marks; 120pt min width on receipt header.
- [ ] Assets: `BrandMark.imageset` vector PDF + 1x/2x/3x PNG fallback; custom SF Symbol for brand glyph where it fits.
- [ ] Shape-match skeletons to actual cell layout (avatar circle + two text bars + chip row); heights match final content to avoid jump.
- [ ] Shimmer: diagonal gradient sweep L→R every 1.5s; Reduce Motion → static gray (no sweep).
- [ ] Shown on first load only; background refresh keeps cached content + subtle top indicator.
- [ ] Error transition: skeleton → error state with same layout footprint.
- [ ] Count: 3-6 skeleton rows typically; list-specific counts tuned to viewport.
- [ ] Tokens: `Surface.skeletonBase`, `Surface.skeletonHighlight` (dark/light variants).
- [ ] Reusable components: `SkeletonRow(.ticket)`, `SkeletonRow(.customer)`, centralized.
- [ ] Duration scale tokens: `instant` 0ms (state flip), `quick` 150ms (selection/hover), `snappy` 220ms (chip pop, toast), `smooth` 350ms (nav push, sheet present), `gentle` 500ms (celebratory), `slow` 800ms (decorative, onboarding).
- [ ] Curve tokens: `standard` .easeInOut; `bouncy` spring(0.55, 0.7); `crisp` spring(0.4, 1.0); `gentle` spring(0.8, 0.5).
- [ ] Reduce Motion: all > `snappy` downgrade to instant / opacity-only.
- [ ] Discipline: no free-form duration literals in views — tokens only; SwiftLint rule bans inline `withAnimation(.easeInOut(duration:` numbers.
- [ ] 120fps tuned (ProMotion); 60fps still feels good.
- [ ] Choreography: staggered list-appear cascade +40ms per row, 200ms cap; respects Reduce Motion.
- [ ] Catalog every `Image(systemName:)` into `docs/symbols.md` (symbol name, usage, pre-iOS-17 fallback).
- [ ] Variant rules: `.fill` on active/selected, outline on inactive; default `.monochrome`, `.multicolor` for status (warning/error), `.hierarchical` for brand surfaces where depth helps.
- [ ] Custom SF Symbols for brand glyphs (wrench-spark) in `Assets.xcassets/Symbols/`; naming `brand.wrench.spark`.
- [ ] A11y: every symbol gets `accessibilityLabel`; decorative marked `.accessibilityHidden(true)`.
- [ ] Consistency: one symbol per concept across app — audit + refactor duplicates.
- [ ] CI lint flags bare `Image(systemName:)` missing label.
- [ ] See §28 for the full list.
- [ ] See §22 for the full list.

---
## §31. Testing Strategy

_Minimum 80% per project rule. TDD: red → green → refactor._

### 31.1 Unit tests (Swift Testing / XCTest)
- [ ] **Coverage targets** — Core 90%, Networking 90%, Persistence 85%, ViewModels 80%, Views 50% (snapshot primary).
- [ ] **Per-module**:
  - `APIClient` — request building, envelope parsing, error mapping, 401 handling.
  - `Repositories` — CRUD vs cache vs queue, optimistic + rollback.
  - `SyncService` — queue drain, backoff, dead-letter, conflict resolution.
  - `Formatters` — date/currency/phone locale edge cases.
  - `Validators` — email, phone, SKU, IMEI.
  - `URL construction` — host/path safety, query encoding, no force-unwraps.
- [ ] **Test helpers** — `MockURLProtocol` for HTTP stubs; in-memory GRDB.

### 31.2 Snapshot tests (swift-snapshot-testing)
- [ ] **Per-component** — every reusable brand component (BrandButton, BrandCard, BrandChip, BrandTextField, BrandBanner, BrandToast) rendered in:
  - Light / dark.
  - Compact / regular width.
  - Dynamic Type small / XL / XXXL.
  - LTR / RTL.
- [ ] **Screen snapshots** — Dashboard, Tickets list, Ticket detail, POS cart, Settings in their golden states.

### 31.3 Integration tests
- [ ] **GRDB migrations** — run against real encrypted DB (no mocks, per CLAUDE memory rule).
- [ ] **End-to-end API** — start local server (Docker Compose) against real endpoints; assert envelopes.
- [ ] **Sync queue** — simulate offline → make N mutations → come online → assert order + idempotency.
- [ ] **WebSocket** — mock server with Starscream client; assert reconnect + event handling.
- [ ] **Keychain** — real Keychain access with test service; cleanup after.

### 31.4 UI tests (XCUITest)
- [ ] **Golden paths** — login → dashboard → new ticket → add payment → print receipt.
- [ ] **POS** — catalog browse → add 3 items → customer pick → BlockChyp stub → success screen.
- [ ] **SMS** — open thread → send → receive WS event → bubble appears.
- [ ] **Offline** — toggle airplane → create customer → toggle online → verify sync.
- [ ] **Auth** — login / logout / 401 auto-logout / biometric re-auth.
- [ ] **Accessibility audits** — `XCUIApplication.performAccessibilityAudit()` per screen (iOS 17+).

### 31.5 Performance tests (XCTMetric)
- [ ] **Launch time** — `XCTApplicationLaunchMetric` budget enforcement.
- [ ] **Scroll frame drops** — `XCTOSSignpostMetric` for tickets list.
- [ ] **Memory** — `XCTMemoryMetric` baseline.
- [ ] **Storage writes** — `XCTStorageMetric` on heavy sync.
- [ ] **CPU** — per-flow CPU time budget.

### 31.6 Accessibility audit
- [ ] **`XCTest.performAccessibilityAudit(for:)`** in CI fails build on new violations.
- [ ] **Contrast** asserted on brand palette.
- [ ] **Tap target sizing** asserted on primary actions.

### 31.7 TDD workflow (per project rule)
- [ ] **Write failing test first** (RED).
- [ ] **Min implementation** (GREEN).
- [ ] **Refactor** (IMPROVE).
- [ ] **Use tdd-guide agent** when stuck.

### 31.8 Fixtures
- [ ] **Seed data** — JSON fixtures per domain (20 tickets / 30 customers / 50 inventory).
- [ ] **Parameterized tests** using fixtures.

### 31.9 CI reporting
- [ ] **Coverage HTML** posted to PR.
- [ ] **Snapshot diffs** visible in PR.
- [ ] **Flake detection** — retry failing tests once; flag chronic flakes.

### 31.10 Device matrix
- [ ] iPhone SE (2022), iPhone 13, iPhone 15 Pro, iPad mini, iPad Air, iPad Pro 13".
- [ ] Mac Mini M-series ("Designed for iPad").
- [ ] iOS 17, iOS 18, iOS 26.
- [ ] Purposes: App Store review (§75.5), sales demo tenants, local dev sandbox.
- [ ] Dataset targets: 50 customers (varying LTV), 500 tickets across statuses, 1000 inventory items, 200 invoices (paid/partial/overdue), 3000 SMS, 12 appointments this week, 5 employees with shifts + commissions.
- [ ] Generator: server CLI `bizarre seed-demo --tenant=demo --seed=42`; deterministic via seed; believable real-world distributions.
- [ ] Refresh: weekly re-seed of demo tenant + reset button in demo tenant settings.
- [ ] Privacy: synthetic only, never derived from real customers; names from Faker locale list, phones/emails from reserved testing ranges.
- [ ] See §26 for the full list.
- [ ] See §26 for the full list.
- [ ] See §29 for the full list.

---
## §32. Telemetry, Crash, Logging

> **Data-sovereignty rule (MANDATORY).** All telemetry, metrics, crash reports, logs, events, heartbeats, experiment assignments, and support bundles report **only to the server the user set at login** — be it `bizarrecrm.com` or a self-hosted URL. **No third-party analytics, crash SaaS, or SDK sink** may exfiltrate data off-tenant. Sentry / Firebase / Mixpanel / Amplitude / New Relic / Datadog SDKs are banned. Apple crash logs via App Store Connect are the only exception (already user-opt-in at device level). `APIClient.baseURL` is the single egress.

### 32.0 Egress allowlist
- [ ] **Single sink** — telemetry collector reads `APIClient.baseURL` at send-time. No hardcoded URLs.
- [ ] **Multi-tenant switch** — when user switches tenant, all in-flight telemetry flushed to old server; new events route to new server.
- [ ] **Self-hosted endpoints** — `POST /telemetry/events`, `POST /telemetry/metrics`, `POST /telemetry/crashes`, `POST /telemetry/diagnostics`, `POST /telemetry/heartbeat`. Document in server API spec.
- [ ] **Offline buffer** — events batched in GRDB `telemetry_queue`; flushed when online.
- [ ] **Backpressure** — server returns 429 → back-off; drop oldest events past 10k cap.
- [ ] **Build-time lint** — CI greps for forbidden SDK imports (`Sentry`, `Firebase`, `Mixpanel`, `Amplitude`, `Bugsnag`, etc.) and fails.
- [ ] **Privacy manifest audit** — `PrivacyInfo.xcprivacy` declares zero `NSPrivacyTrackingDomains`.
- [ ] **Request signing** — telemetry requests bear same bearer token as regular API.

### 32.1 OSLog
- [x] **Subsystem** `com.bizarrecrm` with categories: `api`, `sync`, `db`, `auth`, `ws`, `ui`, `pos`, `printer`, `terminal`, `bg`. (`Core/AppLog.swift` — `Logger` per category: `app`, `auth`, `networking`, `persistence`, `sync`, `ws`, `pos`, `hardware`, `ui`.)
- [ ] **Levels** — `.debug`, `.info`, `.notice`, `.error`, `.fault`.
- [ ] **Privacy annotations** — `\(..., privacy: .public)` for IDs, `\(..., privacy: .private)` for PII.
- [ ] **Signposts** — `OSSignposter` on sync cycles, API calls, list renders.
- [ ] **In-app viewer** — Settings → Diagnostics streams live log (filters by category/level).

### 32.2 MetricKit
- [ ] **Subscribe** to `MXMetricManager` — hourly payloads.
- [ ] **Collect** — launch time, hangs, hitches, CPU, memory, disk, battery.
- [ ] **Upload** — batched daily to server endpoint.
- [ ] **Diagnostic payloads** — hitch + CPU exception diagnostics.

### 32.3 Crash reporting
- [ ] **Apple crash logs** — TestFlight + App Store Connect default (device-level opt-in only).
- [ ] **Symbolication** — `.dSYM` upload on release to our tenant server for decoding MetricKit payloads.
- [ ] **Own crash pipeline** — `MXCrashDiagnostic` payloads uploaded to **tenant server** at `POST /telemetry/crashes` (never third-party).
- [ ] **No Sentry / Bugsnag / Crashlytics** — banned (see §32 sovereignty rule).
- [ ] **Crashes surfaced** in Settings → Diagnostics for self-report.
- [ ] **Redaction** — stack frames only; no heap / string PII.

### 32.4 Event taxonomy (first-party analytics)
- [ ] **Screen views** — `screen_view { name, duration_ms }`.
- [ ] **Action taps** — `action_tap { screen, action, entity_id? }`.
- [ ] **Mutations** — `mutation_start`, `mutation_complete`, `mutation_failed { reason }`.
- [ ] **Sync** — `sync_start`, `sync_complete { delta_count, duration_ms }`, `sync_failed`.
- [ ] **POS** — `pos_sale_complete { total, tender }`, `pos_sale_failed { reason }`.
- [ ] **Performance** — `cold_launch_ms`, `first_paint_ms`.
- [ ] **Retention** — dau / mau computed server-side.

### 32.5 User-level controls
- [ ] **Analytics opt-out** in Settings → Privacy — suspends event sink entirely.
- [ ] **Crash-report opt-out**.
- [ ] **Opt-in rationale** — "Data stays on your company server" messaging reinforced.
- [ ] **ATT prompt skipped** — we don't cross-app track; no `AppTrackingTransparency` permission needed.

### 32.6 PII / secrets redaction — placeholders, not raw values

**Hard rule: no raw customer data or secrets ever leave the device boundary in any telemetry payload.** Even our own tenant server is not a reason to ship raw data through log / metric / event / crash / diagnostic pipelines; those pipelines are for behavior + faults, not for records. Records go through the normal domain API endpoints, where the tenant already has them.

Before any event / log line / diagnostic bundle is serialized, it passes through a `Redactor` layer that substitutes known field types with stable placeholder tokens:

| Input type | Placeholder emitted | Example |
|---|---|---|
| Customer name | `*CUSTOMER_NAME*` | `"Hello *CUSTOMER_NAME*"` |
| Customer first name | `*CUSTOMER_FIRST_NAME*` | `"Hi *CUSTOMER_FIRST_NAME*,"` |
| Customer last name | `*CUSTOMER_LAST_NAME*` | |
| Customer phone | `*CUSTOMER_PHONE*` | `"called *CUSTOMER_PHONE*"` |
| Customer email | `*CUSTOMER_EMAIL*` | |
| Customer address | `*CUSTOMER_ADDRESS*` | |
| Customer birthday | `*CUSTOMER_BIRTHDAY*` | |
| Device IMEI | `*IMEI*` | |
| Device serial | `*DEVICE_SERIAL*` | |
| Passcode / unlock code | `*DEVICE_PASSCODE*` | |
| Card PAN / last4 | `*PAN*` / `*CARD_LAST4*` | last4 removed even though it's already-limited data — not needed in telemetry |
| Auth code / OTP | `*AUTH_CODE*` | |
| Access / refresh / API tokens | `*SECRET*` | |
| Session IDs, tenant-secret keys | `*SECRET*` | |
| Apple push token | `*PUSH_TOKEN*` | |
| Printer / terminal pairing code | `*PAIRING_CODE*` | |
| SMS message body (inbound / outbound text) | `*SMS_BODY*` | content stays on device; telemetry reports counts + lengths only |
| Email body | `*EMAIL_BODY*` | |
| Ticket note text, customer-facing memo | `*NOTE_BODY*` | |
| File / photo filenames that could carry PII | `*FILENAME*` | |
| Signed waiver text post-input | `*WAIVER_TEXT*` | |
| Free-form search queries | `*QUERY*` | |
| Free-form address fields | `*ADDRESS*` | |
| Free-form comments, complaints, reviews | `*FREEFORM*` | |
| User-typed password / PIN | `*SECRET*` | |
| Biometric-derived tokens | `*SECRET*` | |

- [ ] **Redactor is the ONLY serializer path.** All `os_log`, `MetricKit`, event queue, crash payload, diagnostic bundle serializers go through it. Direct string interpolation bypassing it is a SwiftLint violation.
- [ ] **Field-shape detection fallback** — for any string not explicitly tagged (legacy call sites) the Redactor regex-detects phone-like / email-like / token-like patterns and substitutes `*LIKELY_PII*`. False positives acceptable; raw leaks are not.
- [ ] **Structured logging preferred** — `Logger.event("pos_sale_complete", properties: ["total_cents": 1200, "tender": "card", "customer_id_hash": hash(id)])`. Numeric + enum + hashed-ID values pass through unchanged; free-form text is replaced.
- [ ] **Stable hashes, not raw IDs** — when correlation is needed, `SHA-256` truncated to 8 chars, salted per tenant so the hash can't be reversed across tenants.
- [ ] **Allowlist, not blocklist** — events ship only fields declared in their schema (see §32.4 taxonomy). Unknown fields stripped at serializer rather than redacted-through.
- [ ] **Unit tests** assert: every sample input in the table above emits the corresponding placeholder; the string `@example.com` and `555-1212` and similar canaries never appear in a serialized payload.
- [ ] **CI fixture** — weekly job replays last 7 days of staged telemetry payloads through a PII scanner (string-length entropy + regex) and fails the build if any canary pattern slips through.
- [ ] **Crash payloads** — stack frames + device model + OS version + app version + thread state. No heap snapshot, no register-pointing-at-string dumps (which could carry tokens), no user-facing strings.
- [ ] **Incident response** — if raw PII is discovered in telemetry, runbook `docs/runbooks/telemetry-leak.md` triggers: purge the affected period on tenant server; notify tenant admin; audit log the incident; patch the call site; add regression test.

### 32.7 User-reported issues
- [ ] **"Report a problem"** button in Settings → Help.
- [ ] **Attach** — recent OSLog dump + device info + tenant ID + anonymized diagnostic bundle.
- [ ] **Support ticket** created via server endpoint.

### 32.8 Experimentation / feature flags
- [ ] **Server-driven flags** — `/feature-flags?user=` response cached; applied per session.
- [ ] **Local override** (dev builds) — toggle any flag.
- [ ] **A/B** — experiment bucket assigned at first session.

### 32.9 Heartbeat (liveness)
- [ ] **`POST /heartbeat`** every 5 min while app foregrounded; server tracks active users.
- [ ] **On logout** — stop.
- [ ] Apple unified logging: `Logger(subsystem: "com.bizarrecrm", category: "...")`. Categories: `net`, `db`, `ui`, `sync`, `auth`, `perf`, `pos`, `printer`, `terminal`, `bg`.
- [ ] Levels: `debug` (dev-only, compile-stripped in Release), `info` (lifecycle + meaningful), `notice` (user-visible: logins / sales), `error` (recoverable failures), `fault` (unexpected state → crash analytics).
- [ ] Redaction default: `privacy: .private` on all dynamic params; `.public` only for IDs + enum states. SwiftLint rule enforces per §32.6.
- [ ] No ring-buffer shipped; system retention used.
- [ ] Bug-report flow (§69) optionally bundles a redacted `sysdiagnose`-style export; never auto-upload.
- [ ] Logs stay on device unless user opts in via bug report → tenant server only (§32 sovereignty).
- [ ] Purpose targets: dashboard redesign (§3), onboarding flows, campaign templates.
- [ ] Assignment: deterministic bucket by user-ID hash; scope tenant-level / user-level / device-level per experiment; stored in feature-flag system (§19).
- [ ] Exposure logging: `experiment.exposure { id, variant }` once per session per experiment to tenant server.
- [ ] Analysis per-tenant only (no cross-tenant pooling); metrics per variant: task completion, time, error rate.
- [ ] Tenant admin auto-stop control when one variant clearly wins or causes issues.
- [ ] Ethics: never experiment on safety / pricing / billing; payment flows never A/B tested; destructive actions consistent across variants.
- [ ] Sovereignty: all assignments + results tenant-local; no Optimizely / LaunchDarkly external services.

---
## §33. CI / Release / TestFlight / App Store — DEFERRED (revisit pre-Phase 11)

**Status:** not needed for current work. Revisit when approaching App Store submission (Phase 11, per `ios/agent-ownership.md`). Content preserved below as a spec for the release agent; no engineering time allocated to it yet. Local dev + TestFlight uploads happen manually via Xcode until this phase is active.

Dependencies that must be done first before picking this up: §33 certs/provisioning (Phase 0) already established; all Phase 3–9 feature work merged; a11y + perf + i18n (Phase 10) green. Then the bullets below are the build-out.

### 33.1 CI pipeline (GitHub Actions)
- [ ] **PR workflow** — on pull_request: fetch fonts → `xcodegen` → build → unit tests → UI tests on simulator → SwiftLint → SwiftFormat check → coverage upload → artifact IPA.
- [ ] **Main workflow** — on push-to-main: PR workflow + fastlane beta + symbol upload.
- [ ] **Matrix** — Xcode 26 latest stable; iOS 17, 18, 26 simulators.
- [ ] **Caching** — DerivedData + SPM + Homebrew caches.
- [ ] **Runner** — macOS-14 (self-hosted preferred for Xcode speed).
- [ ] **Sovereignty lint** — grep for banned SDK imports; fail build.
- [ ] **Concurrency** — cancel previous in-progress runs on PR updates.

### 33.2 Code signing
- [ ] **fastlane match** — git-encrypted certs/profiles; shared between local + CI.
- [ ] **Provisioning** — explicit `adhoc` / `appstore` / `development` per lane.
- [ ] **`DEVELOPMENT_TEAM`** set only in per-user Xcode config (CLAUDE rule) + CI env var.
- [ ] **Key rotation** — annual renewal documented.

### 33.3 Build number & versioning
- [ ] **Marketing version** — `X.Y.Z` hand-managed in `project.yml`.
- [ ] **Build number** — `Y{year-last-2}M{month}D{day}.{commit-short}` so every build is unique + trackable.
- [ ] **Git tag per release** — `v1.2.3`.

### 33.4 TestFlight (beta)
- [ ] **fastlane beta** — builds + uploads + waits for processing + notifies testers.
- [ ] **Internal testers** — Bizarre team auto-enrolled.
- [ ] **External testers** — per-tenant group invites; changelog required.
- [ ] **Changelog template** — pulled from `CHANGELOG.md` delta between tags.
- [ ] **90-day expiration** — warn testers 7 days before.

### 33.5 App Store release
- [ ] **fastlane release** — submission with metadata.
- [ ] **Metadata** in `ios/fastlane/metadata/<locale>/` — per-locale description, keywords, promo text, what's new.
- [ ] **Screenshots** — 6.7" iPhone, 6.5" iPhone, 13" iPad, 12.9" iPad, Mac. Light + dark variants. Generated via fastlane snapshot.
- [ ] **App Preview video** — 15–30s per device class.
- [ ] **App Privacy** — data types collected declared accurately in App Store Connect.
- [ ] **Review notes** — demo account + server URL + steps.
- [ ] **Phased release** — 7-day auto-rollout on by default.

### 33.6 Unlisted distribution
- [ ] **Apple Business Manager** — unlisted app for early private tenants.
- [ ] **Redeem code** distribution option.

### 33.7 Legal assets
- [ ] **Privacy policy URL** — `https://bizarrecrm.com/privacy`.
- [ ] **Terms of Service URL** — `https://bizarrecrm.com/terms`.
- [ ] **Support URL** — `https://bizarrecrm.com/support`.
- [ ] **EULA** — standard Apple + addendum if needed.

### 33.8 Rollback plan
- [ ] **Expedited review** path documented.
- [ ] **Server-side kill switch** — feature flag + forced-update banner to block broken client versions.
- [ ] **Min-supported-version** — server rejects older clients with upgrade prompt.

### 33.9 Release cadence
- [ ] **Weekly TestFlight** — Friday cut; testers have weekend.
- [ ] **Bi-weekly App Store** — Monday submit → midweek release.
- [ ] **Hotfix** — any P0 ships within 24h.
- [ ] Schemes: Debug-Dev (MockAPI §31), Debug-Staging (staging.bizarrecrm.com), Release-Staging (TestFlight staging), Release-Prod (App Store).
- [ ] `Config/Debug-Dev.xcconfig`, `Debug-Staging.xcconfig`, `Release-Staging.xcconfig`, `Release-Prod.xcconfig` + shared `Base.xcconfig`.
- [ ] Compile flags `DEBUG` / `STAGING` / `RELEASE`; release builds must not contain STAGING code paths (compile-time guard).
- [ ] App icon variants: Dev = brand + "D" badge; Staging = brand + "S"; Prod = clean.
- [ ] Bundle IDs: Dev `com.bizarrecrm.dev` / Staging `com.bizarrecrm.staging` / Prod `com.bizarrecrm`. Separate App Store Connect entries + provisioning.
- [ ] Fastlane match: git-encrypted cert/profile store. Lanes: `match development`, `match appstore` — zero manual Xcode signing.
- [ ] `DEVELOPMENT_TEAM` kept out of `project.yml`; devs set via Xcode UI per clone; CI reads from secret env.
- [ ] APNs cert rotated annually via Fastlane action (also uploads to tenant server for APNs auth).
- [ ] Associated-Domains entitlement `applinks:app.bizarrecrm.com` + `applinks:*.bizarrecrm.com` (§65 cloud-only).
- [ ] Capabilities: Keychain sharing (`group.com.bizarrecrm`), App Groups, CarPlay (§73 deferred), CriticalAlerts (§70 `.timeSensitive` only for now). No HealthKit.
- [ ] Developer-account 2FA mandatory; shared account uses YubiKey + documented recovery runbook.
- [ ] Apple Guidelines map: 4.0 native design, 5.1 privacy manifest accurate, 3.1.1 IAP via StoreKit if any subscription, 5.6.1 login alternative or justification, 2.1 demo login per §75.5.
- [ ] Disclose BlockChyp SDK + PCI certification reference.
- [ ] Rationalize biometric usage; Info.plist reasons for camera, local network, Bluetooth, NFC.
- [ ] Rejection-risk mitigation: tenant-server concept documented in review notes with test tenant credentials.
- [ ] Expedited review: save for genuine launch-date commitments only, never overused.

---
## §34. Known Risks & Blockers

### 34.1 Hardware / SDK
- [!] **MFi Bluetooth printer approval** — 3–6 weeks of Apple process. Start paperwork before code. Alt path: webPRNT (HTTP-over-LAN) on Star TSP100IV-LAN sidesteps MFi.
- [!] **BlockChyp SDK** — ships as CocoaPods only; adds Podfile to SPM-only project. Decision tree: (a) accept Podfile hybrid, (b) wrap BlockChyp in thin Obj-C bridge + vendored xcframework, (c) use HTTP REST to a local proxy. Recommend (a) — fewest moving parts.
- [!] **BlockChyp iOS SDK maturity** — evaluate test coverage; potential Obj-C code that needs Swift wrappers.
- [!] **Barcode scanner MFi approval** — Socket Mobile, Zebra; same 3–6 week lead.

### 34.2 Apple platform
- [!] **iOS 26 Liquid Glass** — on-device verification requires iOS 26 hardware. Public release timing vs our ship date must align.
- [!] **iOS 26 API changes** — `.glassEffect` signature may shift in Xcode betas; pin to stable.
- [!] **WidgetKit perf** — App Group GRDB read may be slow on cold widget render; precompute summaries into plist.
- [!] **Live Activities rate limits** — Apple caps frequency; POS + Clock-in + Appointment competing.
- [!] **Background tasks unreliable** — iOS throttles; can't rely on `BGAppRefreshTask` for timely sync.
- [!] **BGContinuedProcessingTask** iOS 26 — API unstable; beta-test required.

### 34.3 Server coordination
- [!] **Signup auto-login** depends on `POST /auth/signup` returning tokens — see root TODO `SIGNUP-AUTO-LOGIN-TOKENS`.
- [!] **WebSocket endpoints** not all shipped on server — confirm `/sms`, `/tickets`, `/dashboard` exist.
- [!] **`/sync/delta` endpoint** — may not exist; may need server team to build.
- [!] **Idempotency key support** — confirm every write endpoint honors `Idempotency-Key` header.
- [!] **Telemetry ingest endpoints** — server team must add `/telemetry/*` routes.
- [!] **Universal Links AASA** — server must publish `/.well-known/apple-app-site-association`.

### 34.4 UI/UX debt
- [!] **Custom `UISceneDelegateClassName=""`** — harmless console warning; drop from write-info-plist.sh.
- [!] **Empty `BrandMark` imageset** — bundle real 1024px PNG or swap to SF Symbol.
- [!] **AppIcon placeholder** — ship real 1024×1024 + all sizes.
- [!] **Launch screen** — solid color today; design branded splash.
- [!] **Font fallback** — if `fetch-fonts.sh` not run, identity disappears silently.

### 34.5 Integration risks
- [!] **A2P 10DLC registration** — SMS carriers require; outside iOS scope but affects SMS flow.
- [!] **Tax calculation accuracy** — multi-rate stacking has edge cases; rely on server.
- [!] **BlockChyp offline auth rules** — varies by card brand; not all tenders supported offline.
- [!] **Gift card / store credit** — if server model not finalized, iOS ships without.

### 34.6 Scale / data
- [!] **Large tenants (>100k tickets)** — full GRDB sync impractical; selective sync essential.
- [!] **Image storage** — receipts + ticket photos can exceed 10 GB per tenant; device cache eviction strategy.
- [!] **Clock skew** — device vs server time; sync-critical for Clock-in / audit logs.

### 34.7 Distribution
- [!] **App Store review** of POS apps — expect scrutiny of card-acceptance flow; submit with detailed review notes.
- [!] **Unlisted vs public** — early private tenants via ABM; public launch timing depends on parity.

### 34.8 Compliance
- [!] **PCI-DSS scope** — clarify BlockChyp attestation; confirm iOS never sees PAN.
- [!] **HIPAA** — if any tenant in medical repair (rare), need BAA with Apple storage.
- [!] **COPPA** — N/A (no under-13 users expected).
- [!] **Export controls** — encryption used is exempt per `ITSAppUsesNonExemptEncryption = false`.
- [ ] Data breach: disable compromised tokens + rotate secrets → notify tenants (email + in-app banner) → regulatory notifications (GDPR 72h + state breach laws) → post-mortem + remediation rollout.
- [ ] App Store removal: immediate banner "We're working on it"; self-hosted tenants unaffected (web stays up).
- [ ] Widespread crash: pause phased release (§76.4), revert via server-side feature flag first, then expedited-review hotfix.
- [ ] Server outage: enter offline-first mode (§20), banner, retry with exponential backoff.
- [ ] BlockChyp / payment provider outage: fall back to manual card entry (stored cards only) + banner to cashier and manager.
- [ ] Incident comms: server-pushed banner system for critical messages; tenant admin may override with own message.
- [ ] Public status page `https://status.bizarrecrm.com`; deep-link from error banners.
- [ ] Runbook set in `docs/runbooks/`: crash-spike.md, push-failure.md, auth-outage.md, sync-dead-letter-flood.md, payment-provider-down.md, printer-driver-regression.md, db-corruption.md, license-compliance-scare.md, app-store-removal.md, data-breach.md.
- [ ] Standard runbook structure: Detect → Classify (severity) → Contain → Communicate (banner + email + status page) → Remediate → Verify → Post-mortem.
- [ ] On-call rotation: weekly primary + secondary; pager via tenant-owned PagerDuty or similar.
- [ ] Quarterly game-day: simulate one runbook, feed results back into doc.
- [ ] Sovereignty: logs aggregated to tenant-controlled stack; no Datadog / Splunk multi-tenant shared.

---
## §35. Parity Matrix (at-a-glance)

Legend: ✅ shipped · 🟡 partial · ⬜ missing · 🚫 out-of-scope.

| Domain | Web | Android | iOS |
|---|---|---|---|
| Login + password | ✅ | ✅ | ✅ |
| 2FA / TOTP | ✅ | ✅ | ⬜ |
| Biometric unlock | 🚫 | ✅ | ⬜ |
| PIN lock | 🚫 | ✅ | ⬜ |
| Signup / tenant create | ✅ | ✅ | ⬜ |
| Dashboard KPIs | ✅ | ✅ | 🟡 |
| Needs-attention | ✅ | ✅ | ✅ |
| Tickets list | ✅ | ✅ | ✅ |
| Tickets detail | ✅ | ✅ | ✅ |
| Tickets create (full) | ✅ | ✅ | 🟡 |
| Tickets edit | ✅ | ✅ | ⬜ |
| Tickets photos | ✅ | ✅ | ⬜ |
| Customers CRUD | ✅ | ✅ | 🟡 |
| Inventory CRUD | ✅ | ✅ | 🟡 |
| Invoices CRUD | ✅ | ✅ | 🟡 |
| Invoice payment | ✅ | ✅ | ⬜ |
| Estimates CRUD + convert | ✅ | ✅ | 🟡 |
| Leads pipeline | ✅ | ✅ | 🟡 |
| Appointments calendar | ✅ | ✅ | 🟡 |
| Expenses + receipt OCR | ✅ | ✅ | 🟡 |
| SMS realtime | ✅ | ✅ | 🟡 |
| Notifications center | ✅ | ✅ | 🟡 |
| Push registration | 🚫 | ✅ | ⬜ |
| Employees timeclock | ✅ | ✅ | ⬜ |
| Reports charts | ✅ | ✅ | ⬜ |
| POS checkout | ✅ | ✅ | ⬜ |
| Barcode scan | 🚫 | ✅ | ⬜ |
| Card reader (BlockChyp) | 🚫 | ✅ | ⬜ |
| Receipt printer | 🚫 | ✅ | ⬜ |
| Global search | ✅ | ✅ | ✅ |
| Settings | ✅ | ✅ | 🟡 |
| Offline + sync queue | 🟡 | ✅ | ⬜ |
| Widgets | 🚫 | ✅ | ⬜ |
| App Intents / Siri | 🚫 | ✅ (Shortcuts) | ⬜ |
| Live Activities | 🚫 | 🟡 (ongoing notif) | ⬜ |
| Spotlight | 🚫 | 🚫 | ⬜ |
| iPad 3-column | n/a | n/a | ⬜ |
| Mac (Designed for iPad) | n/a | n/a | ⬜ |

_Matrix will be refined as domain inventories land._

---
## §36. Setup Wizard (first-run tenant onboarding) — HIGH PRIORITY

**Status: critical path, not optional.** This is the first impression a new tenant admin gets of the app, the step that turns a freshly-provisioned tenant into one that can actually take a repair. Getting it wrong = high early-drop-off rate. Keep this section's bullets green in every release branch; no feature that blocks the wizard ships.

Why it matters:
- **Onboarding conversion.** An admin who bails mid-wizard rarely comes back. Every step is a potential exit; friction matters more than polish.
- **Tenant baseline.** The wizard's outputs (hours, tax, payment method, locations, SMS provider, device templates) are prerequisites for POS, appointments, marketing, and tickets. Half-setup tenants are the #1 support cost.
- **Parity anchor.** Same flow on iOS, Android, web — users who signed up on one surface finish on another. iOS must resume mid-wizard from server state.
- **First real brand exposure.** Logo + Bebas Neue headers + Liquid Glass on the step shell are what makes the app feel like Bizarre's. Rough drafts here damage trust.
- **Tied to many downstream gates.** Theme choice (§30.12), tax (§16), hours (§19), SMS (§19.10), BlockChyp pairing (§17.3 / §17), locations (§60), device templates (§43), data import (§48), teammate invites (§14) all originate here.

_When an admin creates a tenant (or logs in to an empty tenant), run a 13-step wizard. Mirrors web wizard. Server endpoints: `GET /setup/status`, `POST /setup/step/{n}`, `POST /setup/complete`._

### 36.1 Shell
- [ ] **Sheet modal** — full-screen on iPhone, centered glass card on iPad; cannot dismiss until finished or "Do later".
- [ ] **Step indicator** — 13 dots + progress bar; glass chip on top.
- [ ] **Skip any** button → resume later in Settings.
- [ ] **Back / Next / Skip / Do Later** nav always visible; never trap the user.
- [ ] **Loading / saving state per step** — each `POST /setup/step/{n}` optimistic with offline queue (§20). If submit fails, step stays editable; never lose progress.
- [ ] **Accessibility baseline** — full VoiceOver labeling; Dynamic Type respected; keyboard navigation on iPad Magic Keyboard (Tab / Enter / Esc / ⌘⇧Enter to submit).

### 36.2 Steps
- [ ] **1. Welcome** — brand hero + value props. Bebas Neue display. Skip button present.
- [ ] **2. Company info** — name, address, phone, website, EIN. Address field uses MapKit autocomplete per §16.7 so tax engine seeds correctly.
- [ ] **3. Logo** — camera / library upload; cropper; preview on sample receipt. Stored as tenant branding asset (§19).
- [ ] **4. Timezone + currency + locale** — default from device but user-confirmable.
- [ ] **5. Business hours** — per day, with "Copy Mon to all weekdays" helper.
- [ ] **6. Tax setup** — add first tax rate; address from step 2 pre-populates jurisdiction hint.
- [ ] **7. Payment methods** — enable cash, card (BlockChyp link), gift card, store credit, check.
- [ ] **8. First location** — if multi-location tenant. Defaults to the company address from step 2.
- [ ] **9. Invite teammates** — email list + role per; SMS invite option; defaults to manager role for the first invitee.
- [ ] **10. SMS setup** — provider pick (Twilio / BizarreCRM-managed / etc.) + from-number + templates.
- [ ] **11. Device templates** — pick from preset library (iPhone family, Samsung, iPad, etc.). Feeds ticket create + repair pricing (§43).
- [ ] **12. Import data** — offer CSV / RepairDesk / Shopr / Skip (§48).
- [ ] **12a. Theme** — `System (recommended)` / `Dark` / `Light` (§30.12 — setup wizard asks, Settings lets them change later).
- [ ] **13. Done** — confetti (Reduce-Motion respects § 26.3) + "Open Dashboard".

### 36.3 Persistence
- [ ] **Resume mid-wizard** — partial state saved server-side; iOS shows "Continue setup" CTA on Dashboard.
- [ ] **Skip all** — admin can defer; gentle nudge banner on Dashboard until complete (never blocking).
- [ ] **Cross-device resume** — if the same admin opened step 5 on web and step 7 on iOS, server is the source of truth; iOS picks up from the furthest completed step.
- [ ] **Minimum-viable completion** — steps 1–7 + 13 are required to unlock POS. Other steps are optional but nudged.

### 36.4 Metrics (per §32 telemetry, placeholders only)
- [ ] Track per-step completion rate + time-in-step + drop-off step. PII-redacted per §32.6; events use entity ID hashes, never raw company name / address.
- [ ] Dashboard card for tenant admin: "Setup 7 of 13" with tap-to-resume.

### 36.5 Review cadence
- [ ] Revisit wizard UX after each phased-rollout cohort (§82.10). Onboarding drop-off trends drive reordering / merging steps. Changes land here before other polish.
- [ ] First-run wizard verifies: internet OK, tenant reachable, printer reachable, terminal reachable
- [ ] Each check shows green/red with fix link
- [ ] Captive-portal detection: banner + "Open portal" button
- [ ] Detect active VPN; warn if interfering
- [ ] Periodic tenant-server ping; latency chart in Settings → Diagnostics
- [ ] Alert if p95 > 1s sustained
- [ ] Hotspot/cellular fallback warning when tenant uses local-IP printer
- [ ] Suggest switching Wi-Fi when needed
- [ ] Multi-SSID: tenant stores multiple trusted SSIDs (shop + backup) with auto-reconnect hints
- [ ] See §19 for the full list.
- [ ] See §19 for the full list.
- [ ] See §17 for the full list.

---
## §37. Marketing & Growth

### 37.1 Campaigns (SMS blast)
- [ ] **Server endpoints** — `GET/POST /marketing/campaigns`, `POST /marketing/campaigns/{id}/send`.
- [ ] **List** — campaigns sorted by created; status (draft / scheduled / sending / sent / failed).
- [ ] **Create** — name + audience (segment) + template + schedule + A/B variants.
- [ ] **Audience picker** — customer segment (see §37.2).
- [ ] **Scheduled send** — pick date/time; tenant-TZ aware.
- [ ] **Estimated cost** — "Will send to 342 customers, ~$8.55 in SMS fees".
- [ ] **Approval gate** — requires manager if > N recipients.
- [ ] **Post-send report** — delivered / failed / opted-out / replies.

### 37.2 Segments
- [ ] **Server endpoints** — `GET/POST /segments`.
- [ ] **Rule builder** — AND/OR tree: "spent > $500 AND last-visit > 90 days".
- [ ] **Live count** — refreshes as rules change.
- [ ] **Saved segments** — reusable in campaigns.
- [ ] **Presets** — VIPs / Dormant / New / High-LTV / Repeat / At-risk.

### 37.3 NPS / Surveys
- [ ] **Post-service SMS survey** — "Rate us 1–10".
- [ ] **Response tracking** — `GET /surveys/responses`.
- [ ] **Detractor alert** — score ≤ 6 pings manager.
- [ ] **NPS dashboard** — score + trend + themes.

### 37.4 Referrals
- [ ] **Referral code** per customer.
- [ ] **Share link** — deep link + QR to public signup.
- [ ] **Credit on qualifying sale** — sender + receiver.
- [ ] **Leaderboard**.

### 37.5 Reviews
- [ ] **After paid invoice** — prompt for Google/Yelp review.
- [ ] **Gate by rating** — if user says 5★, deep-link to Google; else in-app feedback form.

### 37.6 Public profile / landing
- [ ] **Share my shop** — generates short URL with intake form + reviews.
- [ ] Campaign types: SMS blast, email blast, in-app banner. (Postcard integration is stretch; push-to-app-users handled via §70.)
- [ ] Audience builder: segment by tag / last-visit window / LTV tier / device type / service history / birthday month; save + reuse segments.
- [ ] Scheduler: send now / send at time / recurring (weekly newsletter) / triggered (birthday auto-send).
- [ ] Compliance: server-side tenant quiet hours respected; unsubscribe-suppression enforced; test-number suppression; consent date + source stored per contact.
- [ ] Analytics tiles: delivered / opened / clicked / replied / converted-to-revenue; unsubscribe-rate alarm at 2%+.
- [ ] Monthly SMS spend cap per tenant; system halts sends when reached + notifies admin.
- [ ] Preview: iPhone-bubble rendering for SMS + HTML render for email with dynamic-variable substitution shown.
- [ ] Post-service auto-SMS link: "Rate your experience 1-5 [link]"
- [ ] One-tap reply-with-digit for 1-5
- [ ] Quarterly NPS: "How likely are you to recommend us 0-10?"
- [ ] NPS send cap: max 2 / year per customer
- [ ] Optional free-text comment after rating
- [ ] Internal dashboard: score trend, comments feed, per-tech breakdown
- [ ] Per-tech anonymized by default (tenant can configure open)
- [ ] Low-score (1-2 star) immediate manager push to recover
- [ ] Recovery playbook: call within 2h
- [ ] High scores nudge customer to leave Google / Yelp review (§37)
- [ ] After high CSAT (§15), offer customer to leave public review
- [ ] Link via share sheet (no auto-post)
- [ ] Tenant configures Google Business / Yelp URLs
- [ ] Staff can "Send review link" from customer detail
- [ ] Rate limit: once per 180 days per customer
- [ ] Block tying reviews to discounts (Google/Yelp ToS)
- [ ] Settings → Reviews → list of platforms
- [ ] Optional external review alert push via tenant-configured monitoring
- [ ] Staff draft review responses in-app; posting happens on external platform (iOS opens Safari)
- [ ] Sovereignty: iOS never calls third-party review APIs directly
- [ ] External links open in `SFSafariViewController`
- [ ] See §19 for the full list.
- [ ] See §19 for the full list.
- [ ] See §5 for the full list.

---
## §38. Memberships / Loyalty

_Server: `GET/POST/PUT /memberships`, `GET /memberships/{id}`, `POST /memberships/{id}/renew`, `GET /memberships/{id}/points`, `POST /memberships/{id}/points/redeem`._

### 38.1 Tiers
- [ ] **Configure tiers** in Settings (§19.12).
- [ ] **Auto-tier** — customer promoted on $-threshold.
- [ ] **Member badge** on customer chips / POS.

### 38.2 Points
- [ ] **Earn** — points on paid invoice (configurable rate).
- [ ] **Redeem** — at POS (see §16.15).
- [ ] **Expiration** — configurable.
- [x] **Point history (partial)** — `LoyaltyBalanceView` surfaces current points + tier + lifetime spend via `GET /api/v1/loyalty/balance/:customerId`. Per-transaction history endpoint TBD.

### 38.3 Subscription memberships
- [ ] **Paid plans** — monthly / annual with auto-renew.
- [ ] **Benefits** — discount %, free services (e.g., 1 battery test / month).
- [ ] **Payment** — BlockChyp recurring or Stripe.
- [ ] **Cancel / pause / resume**.

### 38.4 Apple Wallet pass
- [x] **`PKAddPassesViewController`** — `LoyaltyPassPresenter.present(passData:)` scaffold ships in `Packages/Loyalty`. Commit `73229b3`. Server .pkpass signing + Wallet entitlement still required for live install.
- [ ] **Pass updates** — push via pass server (tenant server).
- [ ] **Barcode on pass** — scannable at POS.

### 38.5 Member-only perks
- [ ] **Exclusive products** — hidden in catalog for non-members.
- [ ] **Priority queue** — badge in intake flow.
- [ ] Plan builder in Settings → Memberships: name / cadence (monthly / quarterly / annual) / price / included-services count / auto-renew toggle.
- [ ] Enroll flow from Customer detail → Plans tab → Enroll; card tokenized via BlockChyp vault (§17.3 token-only; no PAN).
- [ ] Server cron creates invoices + charges cards + updates ledger daily; iOS shows "Next billing date" on customer detail.
- [ ] Service ledger per period: "Included services remaining: 3 of 5"; decrement at POS redemption.
- [ ] Dunning cadence: failed charge retry 3d / 7d / 14d + customer notify; exhaustion → pause plan + staff notify.
- [ ] Cancel flow: customer self-cancel via public portal OR staff via customer detail; tenant-configurable end-of-period policy.
- [ ] Cadence: 30 / 14 / 7 / 1 day before expiry
- [ ] Channels: push + SMS + email (configurable per member)
- [ ] Auto-renew: if enrolled, card on file charged on renewal date
- [ ] Notify success/failure of auto-renew
- [ ] Grace period: 7 days post-expiry retain benefits + soft reminder
- [ ] After grace: benefits suspended
- [ ] Reactivation: one-tap with current card or new
- [ ] Pro-rate remaining period credit on reactivation
- [ ] Churn insight report: expiring soon / at risk / churned
- [ ] Segment for targeted offer (§37)
- [ ] Visual punch card per service type (e.g. "5th repair free", "10th wash free")
- [ ] Count auto-increments on eligible service
- [ ] Server-side storage; iOS displays
- [ ] Wallet pass (§38.4) with updating strip
- [ ] Customer detail shows punch cards
- [ ] Progress icons (filled vs empty)
- [ ] Redemption: last punch = free next service, auto-applied discount at POS
- [ ] Combo rule: no stacking with other discounts unless configured
- [ ] Optional punch expiry 12mo after last activity
- [ ] Tenant config: cards shared across locations vs per-location
- [ ] Pass types: Membership (storeCard), Gift card (storeCard), Punch card (coupon), Appointment (eventTicket), Loyalty tier (generic linked to membership).
- [ ] Membership storeCard front includes logo, tenant name, member name, tier, points, QR/barcode; back carries address, phone, website, terms, points-history link.
- [ ] Colors: background = tenant accent (contrast-validated); foreground = auto-contrast text.
- [ ] Updates: APNs-based PassKit push on points/tier/status change; relevance dates set so appointment passes surface on Lock Screen near time.
- [ ] Localization: per-locale strings.
- [ ] Web-side Add-to-Wallet button on public page (§53.4).
- [ ] Sovereignty: pass signing certificate + Apple Pass web service URL live on tenant server, never our infra.

---
## §39. Cash Register & Z-Report

See §16.10 for core flow. Additional items:

### 39.1 Shift log
- [x] **Per-shift entry** — `CashRegisterStore` local-first schema (open_at, opening_cash, close_at, closing_cash, variance). Endpoint DTOs + stub `APIClient` wrappers in `CashRegisterEndpoints.swift`.
- [ ] **Shift history** — list of past shifts; open any for detail.
- [x] **Shift diff viewer** — `CashVariance` + `ZReportView` surface expected vs actual with color.

### 39.2 Z-report PDF
- [x] **Auto-generate** on close — `ZReportView` renders totals. PDF export via `ImageRenderer` deferred to §17.4 pipeline.
- [ ] **Emailed** to manager.
- [ ] **Auto-archive** in tenant storage.
- [x] **Data** — sales / tenders / over-short / cashier. Refunds / voids / discounts / tips / taxes / printer-log deferred.

### 39.3 X-report (mid-shift)
- [ ] **`GET /cash-register/x-report`** — peek current shift without closing.

### 39.4 Reconciliation export
- [ ] CSV per day of all transactions + tender splits.
- [ ] Trigger: manager taps "End of day" at shop close
- [ ] Steps: (1) close any open cash shifts; (2) mark still-open tickets → confirm or archive to tomorrow; (3) send day-end status SMS to customers with ready tickets (optional); (4) review outstanding invoices / follow-ups; (5) backup reminder (if tenant schedules local backup); (6) lock POS terminal; (7) post shop's daily summary to tenant admin (push)
- [ ] Progress indicator: glass progress bar at top; can abort mid-wizard and resume
- [ ] Logging: each step's completion stamped in audit log
- [ ] Permissions: manager-only; cashier gets "Need manager" if attempted
- [ ] Daily: sales + payments + cash close + bank deposit all tie out
- [ ] Dashboard shows variance per period
- [ ] Monthly: full reconciliation report (revenue, COGS, adjustments, AR aging, AP aging)
- [ ] Export to QuickBooks / Xero formats
- [ ] Variance investigation tool: clickable drill-down from total → lines → specific transaction → audit log
- [ ] Alerts: variance > threshold triggers manager push
- [ ] Close period: once reconciled, period locked; changes require manager override + audit

---
## §40. Gift Cards / Store Credit / Refunds

### 40.1 Gift cards
- [x] **Networking** — `GiftCardsEndpoints.swift`: `lookupGiftCard(code:)`, `redeemGiftCard(id:amountCents:reason:)`. Sell/void/transfer endpoints TBD.
- [ ] **Sell** — at POS; physical card scan OR generate virtual (SMS/email with QR).
- [x] **Redeem** — `PosGiftCardSheet` + `PosGiftCardSheetViewModel` → lookup → clamp-to-min(total, balance) → `apply(tender:)` via `AppliedTender.giftCard`.
- [x] **Balance check** — lookup shows remaining balance + status + expiry.
- [ ] **Reload** — add more funds.
- [x] **Expiration** — surfaced in sheet if present.
- [ ] **Transfer** — from one card to another.
- [ ] **Refund to gift card** — if original tender was gift card.

### 40.2 Store credit
- [x] **Networking** — `StoreCreditEndpoints.swift`: `getStoreCreditBalance(customerId:)`. Redeem issuance via tender flow.
- [ ] **Issued** on returns / apologies / promos.
- [x] **Balance visible** — store credit section in `PosGiftCardSheet` when `cart.customer.id != nil`.
- [x] **Redeem** at POS with toggle via `AppliedTender.storeCredit`.
- [ ] **Expiration** configurable.

### 40.3 Refunds (see §16.9)
- [ ] Already detailed.

### 40.4 Approval workflow
- [ ] **Manager PIN** required on gift-card void / large refund.
- [ ] **Audit trail** — every issuance / void / redeem logged.
- [ ] See §38 for the full list.

---
## §41. Payment Links & Public Pay Page

### 41.1 Generate payment link
- [x] **From POS cart** — "Send payment link" toolbar → `PosPaymentLinkSheet` → `createPaymentLink(...)`. Per-invoice/estimate entry TBD.
- [x] **Networking** — `PaymentLinksEndpoints.swift`: `createPaymentLink` / `getPaymentLink` / `listPaymentLinks` / `cancelPaymentLink` + `makePaymentLinkURL`.
- [x] **Share** — `UIActivityViewController` with URL for SMS/email/AirDrop + Copy button. QR display deferred.

### 41.2 Public pay page (tracked by iOS)
- [ ] **Webview preview** — admin can see what customer sees.
- [x] **List view** — `PaymentLinksListView` in More menu with status chips + swipe-cancel. `SFSafariViewController` open-external + webhook hook deferred.

### 41.3 Webhooks
- [ ] On payment complete, server pushes WS event → invoice updates in-app in real time.
- [ ] See §16 for the full list.

---
## §42. Voice & Calls

### 42.1 Call log (if server tracks)
- [x] **Server**: `GET /voice/calls` wired via `CallsEndpoints.listCalls()`. `/calls/:id/transcript` 404 → `State.comingSoon` fallback.
- [x] **List** — `CallLogView` with inbound/outbound arrow icons, direction colors, customer/phone match, debounced 300ms search. Commit `f0ea6e0`.
- [ ] **Recording playback** — audio file streamed.
- [x] **Transcription (partial)** — `getCallTranscript(id:)` wired; Speech / Whisper pipeline deferred.
- [x] **Search transcripts** — in-memory filter on `transcriptText` via `CallLogViewModel.filteredCalls(_:)`.

### 42.2 Outbound call (from app)
- [x] **Tap phone number** — `CallQuickAction.placeCall(to:)` opens `tel:` URL via `UIApplication.shared.open(_:)`. `cleanPhoneNumber(_:)` strips formatting + US country code.
- [ ] **Click-to-call on customer / ticket detail** — helper shipped, callsite wiring deferred.

### 42.3 CallKit integration
- [ ] **Inbound VoIP** — CallKit card shows customer name / photo / recent ticket. (Needs entitlement — deferred.)
- [ ] **Outbound recent calls** appear in native Phone app.

### 42.4 PushKit (VoIP push)
- [ ] **Server pushes VoIP** → iOS wakes app → CallKit invocation. (Needs entitlement — deferred.)
- [ ] **Required entitlement**.

### 42.5 Voicemail
- [x] **List + playback** — `VoicemailListView` + `VoicemailPlayerView` with `AVPlayer`, scrubber, play/pause, 1x/1.5x/2x speed chips, Reduce Motion aware.
- [ ] **Transcription** — placeholder field shown if server returns it; on-device Speech pipeline deferred.
- [x] **Mark heard** — swipe action calls `PATCH /api/v1/voicemails/:id/heard`. Delete / forward deferred.

---
## §43. Device Templates / Repair-Pricing Catalog

_Server: `GET /device-templates`, `POST /device-templates`, `GET /repair-pricing/services`._

### 43.1 Catalog browser
- [x] **Device family** — `RepairPricingCatalogView` family chips row derived from `DeviceTemplate.family` dedup. Commit `df61f91`.
- [x] **Model list** — `LazyVGrid(.adaptive(minimum: 140))` with `AsyncImage` thumbnails + SF Symbol fallback.
- [x] **Service list** — `RepairPricingDeviceDetailView` lists services with default price via `CartMath` formatting + part SKU.

### 43.2 Template selection at intake
- [x] **Device picker (standalone)** — `RepairPricingServicePicker` multi-select sheet ready for §16.2 POS wiring. IMEI pattern + conditions list display in detail view.

### 43.3 Price overrides
- [ ] **Per-tenant price** — override service default.
- [ ] **Per-customer override** — VIP pricing.

### 43.4 Part mapping
- [ ] **SKU picker** for each service.
- [ ] **Multi-part bundles** — e.g., screen + battery + adhesive.

### 43.5 Add/edit templates (admin)
- [ ] **Full editor** — model, year, conditions, services, default prices.

---
## §44. CRM Health Score & LTV

### 44.1 Health score
- [x] **Per-customer 0-100** — `CustomerHealth.compute(detail:)` + server-side `health_score` override. Commit `c0c4f56`.
- [x] **Color tier** — `CustomerHealthTier` green/yellow/red with brand tokens `bizarreSuccess/Warning/Error`.
- [x] **Action recommendations** — >180-day absence → "Haven't seen in 180+ days — send follow-up"; complaint count > 0 → complaint banner.

### 44.2 LTV
- [x] **Lifetime value** — `CustomerLTVChip` with server analytics `lifetime_value` + DTO `ltv_cents` fallback; rendered on CustomerDetailView header.
- [ ] **Tier** — Bronze / Silver / Gold / Platinum by LTV threshold.
- [ ] **Perks per tier** — auto discounts, priority queue.

### 44.3 Predicted churn
- [ ] **ML score** (server) — probability of not returning.
- [ ] **Proactive campaign** — auto-target red-health customers.

---
## §45. Team Collaboration (internal messaging)

**Cross-platform status (checked 2026-04-20):**
- **Server**: present. `packages/server/src/routes/teamChat.routes.ts` mounted at `/api/v1/team-chat`. Schema in migration `096_team_management.sql`: tables `team_chat_channels`, `team_chat_messages`, `team_mentions`. Channels: `general` / `ticket` / `direct`. Polling-based MVP (no WS fan-out yet — clients poll `GET /channels/:id/messages?after=<id>`). WebSocket wiring to existing `packages/server/src/websocket/` is a TODO.
- **Web**: present. `packages/web/src/pages/team/TeamChatPage.tsx`; route `/team/chat` registered in `App.tsx`; sidebar link "Team Chat" in `components/layout/Sidebar.tsx`; `MentionPicker.tsx` for @mentions.
- **Android**: **missing.** No `NfcAdapter`-equivalent for chat — zero references to TeamChat in `android/`.
- **iOS**: this section.

### 45.0 Data-at-rest audit (tracked in root TODO as `TEAM-CHAT-AUDIT-001`)

The server stores message bodies as **plaintext `TEXT` columns** (`team_chat_messages.body TEXT NOT NULL`). No column-level encryption, no hashing, no tokenization. Acceptable today for MVP staff chat; worth a comprehensive review before shipping it cross-platform:

- [ ] Audit item filed in root TODO (`TEAM-CHAT-AUDIT-001`) — full list of questions (at-rest encryption / retention / export / moderation / HIPAA/PCI scope).
- iOS side obeys the outcome. If server adds column-level encryption, iOS just passes through.

Iterate iOS work on this section only after Android parity + audit close in root TODO.

Content below kept as the iOS implementation spec for when those gates open.

### 45.1 Internal chat
- [ ] **Per-tenant team chat** — `/team-chat/threads`, `/team-chat/{id}/messages` via WS.
- [ ] **Channels** — General / Parts / Techs / Managers.
- [ ] **DMs** — between employees.
- [ ] **@mention** anyone; push notification.
- [ ] **File upload** — images / PDFs.
- [ ] **Pin message**.

### 45.2 Staff shout-outs
- [ ] **"Shout out @Alex for closing tough ticket"** → visible on Dashboard feed.
- [ ] **Like / reply**.

### 45.3 Shift swaps
- [ ] **Request swap** — post to channel + auto-matches by role.
- [ ] **Approval**.

### 45.4 Tasks
- [ ] **Assign task to teammate** with due date, link to ticket/customer.
- [ ] **Task list** per user; badge on tab.
- [ ] **Recurring tasks** (daily opening checklist, weekly deep-clean).

### 45.5 Rooms
- `#general` per location.
- `#managers` (admins only).
- `#tech` (technicians).
- `#announcements` (broadcast-only by managers).
- DMs between any two users.

### 45.6 Message types
- Text + emoji reactions.
- Photo (camera / library).
- Voice memo (§42).
- File attachments (PDF, CSV) up to 25MB.
- Shared ticket / customer / invoice cards (rich preview).

### 45.7 @mentions
- Triggers push (`.timeSensitive` interruption if user online).
- Mentions grouped in dedicated notification category.

### 45.8 Threading & search
- Reply threading (nested under parent).
- FTS over messages + attachments filenames.
- Read receipts optional per user; default on.
- Pin important announcements at top of room.

### 45.9 Presence
- Online / idle / offline inferred from app state; optional "Busy with customer" status.

### 45.10 Moderation
- Admins can delete any message; user can delete / edit own within 5min.
- Edit shows "edited" tag.
- Delete creates audit entry with original content (manager-viewable).

### 45.11 E2E vs tenant-server
- Server-side encrypted at rest; not E2E (tenant owner must be able to export history for legal).
- Sovereignty: tenant server only.

### 45.12 Layouts
- iPad: 3-column (rooms / thread list / message pane).
- iPhone: tabbed (rooms tab / thread view).

### 45.13 Keyboard shortcuts
- ⌘/ jump to room, ⌘K quick switcher, ⌘↑ / ↓ navigate rooms.
- [ ] See §14 for the full list.

---
## §46. Goals, Performance Reviews & Time Off

### 46.1 Goals (per-user + per-team)
- [ ] **Goal types**: daily revenue / weekly ticket-count / monthly avg-ticket-value / personal commission / per-role custom.
- [ ] **Configured by manager** — Settings → Team → Goals → set target per employee or shared team goal.
- [ ] **Progress ring** on personal dashboard tile + team-aggregate ring on manager dashboard.
- [ ] **Trajectory line** — historical vs target vs forecast curve.
- [ ] **Milestone toasts** — 50% / 75% / 100% (respect Reduce Motion; confetti only on 100% with `BrandMotion` fallback).
- [ ] **Streak counter** — "5 days in a row hitting daily goal"; subtle UI, no loss-aversion anti-pattern per §46 gamification guardrails.
- [ ] **Miss handling** — supportive copy ("Tomorrow's a new day"); no guilt language; no daily push notifications about missed goals.
- [ ] **Tenant can disable goals entirely** (some shops don't run sales culture).

### 46.2 Performance reviews
- [ ] **Manager composes review**: numeric ratings per competency (1-5 with descriptors) + strengths + growth areas + next-period goals.
- [ ] **Employee self-review** — separate form completed before manager session; both surface in review meeting helper.
- [ ] **Peer feedback intake** (§46.5) aggregated by manager into final review.
- [ ] **Meeting helper** — "Prepare review" action compiles scorecard (§46.4) + self-review + peer notes + manager draft into a single PDF for the sit-down.
- [ ] **Employee acknowledges** — read + agree-or-dispute signature via `PKCanvasView`; disputes logged separately.
- [ ] **Archive** — stored on tenant server indefinitely; exportable as PDF for HR file.
- [ ] **Cadence** — quarterly / semi-annual / annual tenant-configurable.

### 46.3 Time off (PTO)
- [ ] **Request PTO** — date range + type (vacation / sick / personal / unpaid) + reason; optional note.
- [ ] **Manager approve / deny** — push notification to requester (§70); audit log entry.
- [ ] **Team calendar view** — month grid showing who's out when; conflicts highlighted.
- [ ] **Balance tracking** — accrual rate per type (configured in Settings); usage deducted on approval; warnings when requesting over balance.
- [ ] **Coverage prompt** — when approving PTO that affects schedule, manager sees conflicts with scheduled shifts + suggested swap partner.
- [ ] **Carry-over + expiry policy** — tenant-configured; "X days expire Dec 31" banner.

### 46.4 Employee scorecards (private by default)
Covers what §46 specified. Lives here.

- [ ] **Metrics per employee**: ticket close rate, SLA compliance (§4 / §4), avg customer rating (§15), revenue attributed, commission earned, hours worked, breaks taken, voids + reasons, manager-overrides triggered.
- [ ] **Rolling windows** — 30 / 90 / 365-day charts.
- [ ] **Private by default** — only self + direct manager see; owner sees all.
- [ ] **Manager annotations** — notes + praise / coaching signals visible to employee.
- [ ] **Objective vs subjective separation** — hard metrics auto-computed; subjective rating is the scale in §46.2 review.
- [ ] **Export** — scorecard PDF for HR file.

### 46.5 Peer feedback
Covers what §46 specified.

- [ ] **Request** — employee requests feedback from 1–3 peers during review cycle.
- [ ] **Form** — 4 prompts: what's going well / what to improve / one strength / one blind spot.
- [ ] **Anonymous by default**; optional peer attribution.
- [ ] **Delivery gated through manager** — manager curates before sharing with subject; prevents rumor / hostility.
- [ ] **Frequency cap** — max 1 request per peer per quarter; prevents feedback fatigue.
- [ ] **Voice dictation** — long-form text field; on-device `SFSpeechRecognizer`.

### 46.6 Leaderboards (opt-in only)
Covers what §46 specified.

- [ ] **Tenant-opt-in**; default OFF. Some shops don't want internal competition.
- [ ] **Scope** — per team / location.
- [ ] **Metrics** — tickets closed / sales $ / avg turn time (pick per leaderboard).
- [ ] **Anonymization** — own name always shown; others optionally initials only (prevents shaming).
- [ ] **Weighting** — normalized by shift hours (part-time not unfairly compared); single big-ticket outliers excluded.
- [ ] **Timeframes** — daily / weekly / monthly / quarterly.
- [ ] **Weekly summary only** as notification — no daily hounding.
- [ ] **Per-user opt-out** — "Hide my name from leaderboards" in Settings → Profile.

### 46.7 Recognition cards (shoutouts)
Covers what §46 specified.

- [ ] **Send** — any staff sends short "Nice job on [X]" to peer; optional link to ticket / customer record.
- [ ] **Categories**: Customer save / Team player / Technical excellence / Above and beyond.
- [ ] **Frequency unlimited** — no leaderboard of shoutouts (prevents gaming per §46).
- [ ] **Delivery** — push to recipient (§70); archive in recipient profile.
- [ ] **Team visibility** — private (recipient + sender only) by default; recipient can opt in to team-visible (posts to §45 team chat).
- [ ] **End-of-year "recognition book"** — PDF export of all received shoutouts.

### 46.8 Gamification guardrails (hard rules)
Covers what §46 specified. Non-negotiable ethical constraints.

- [ ] **Playful, not manipulative.** No dark patterns (streak-break anxiety, loss aversion, variable-ratio reinforcement).
- [ ] **Never tie to real $ rewards** — that's compensation, goes through §46 commissions, not here.
- [ ] **Banned**: auto-posting to team chat without consent, forced enrollment, countdown timers creating urgency, loot-box mechanics, pull-to-refresh slot-machine animations, variable-reward schedules.
- [ ] **Allowed**: subtle milestone celebration, anniversary badges (first 100 tickets / 1yr), friendly nudges (not pushy).
- [ ] **Global opt-out** — Settings → Appearance → "Reduce celebratory UI" disables confetti / sparkles / achievement animations entirely.
- [ ] Goal types: daily revenue, weekly ticket-count, monthly avg-ticket-value, personal commission
- [ ] Progress ring visualization (fills as goal met)
- [ ] Tap ring → detail with trajectory
- [ ] Streak tracking with subtle confetti celebration per milestone
- [ ] Respect Reduce Motion (disable confetti)
- [ ] Supportive tone on miss ("Tomorrow's a new day") — no guilt UI
- [ ] Per-tenant ops toggle to disable goals entirely
- [ ] Tenant-opt-in; default off
- [ ] Scope: per team / per location
- [ ] Metrics: tickets closed, sales $, avg turn time
- [ ] Anonymization: own name always shown; others optionally initials-only
- [ ] Timeframes: daily / weekly / monthly / quarterly
- [ ] Fairness: weighted by shift hours (part-time not unfairly compared)
- [ ] Exclude unusual outliers (e.g. single big ticket)
- [ ] Weekly summary notifications only (no daily hounding)
- [ ] Per-user opt-out: "Hide my name from leaderboards" in settings
- [ ] Principles: playful, not manipulative; no dark patterns (no streak-breaking anxiety / loss aversion)
- [ ] Never tie gamification to real $ rewards (compensation is not a game)
- [ ] Allowed: subtle milestone celebrations, shop achievement badges (first 100 tickets, 1yr anniversary), friendly nudges
- [ ] Banned: auto-posting to team chat without consent
- [ ] Banned: forced enrollment
- [ ] Banned: countdown timers to create urgency
- [ ] Banned: loot-box mechanics
- [ ] Global opt-out: Settings → Appearance → "Reduce celebratory UI" disables confetti/sparkles
- [ ] Anti-addictive: no pull-to-refresh slot-machine animations; deterministic updates

---
## §47. Roles Matrix Editor

See §19.14 for settings entry. Deep features:

### 47.1 Matrix UI
- [ ] **iPad** — full matrix; rows=roles, cols=capabilities; toggle cells.
- [ ] **iPhone** — per-role detail view.

### 47.2 Granular caps
- [ ] **~80 capabilities** — each action on each entity.
- [ ] **Presets** — Admin / Manager / Technician / Cashier / Viewer / Training.
- [ ] **Custom role** — clone + modify.

### 47.3 Preview before save
- [ ] **"As this role"** preview mode — admin previews UI as different role.

### 47.4 Audit
- [ ] **Every role change logged** — who, what, when.

### 47.5 Capabilities (fine-grained, from §47)
- **Tickets**: view.any / view.own / create / edit / delete / reassign / archive / price.override.
- **Customers**: view / create / edit / delete / export.
- **Inventory**: view / create / edit / adjust / delete / import / export / reorder.
- **Invoices**: view / create / edit / void / refund / payment.accept / payment.refund.
- **SMS**: read / send / delete / broadcast.
- **Reports**: view.daily / view.historical / export.
- **Settings**: view / edit.org / edit.payment / edit.tax / edit.sms / edit.roles / edit.templates / billing.
- **Hardware**: printer.config / terminal.config / scanner.config.
- **Audit**: view.self / view.all.
- **Data**: import / export / backup / restore / wipe.
- **Team**: invite / suspend / change.role / view.payroll.
- **Marketing**: campaign.create / campaign.send / segment.edit.
- **Danger**: feature.flag.override / data.wipe / tenant.delete.

### 47.6 Preset roles
- **Owner** — all.
- **Manager** — all except tenant.delete / billing / data.wipe.
- **Shift supervisor** — daily ops, no settings.
- **Technician** — tickets (own + any assigned), inventory adjust (parts only), SMS read + send to own tickets.
- **Cashier** — POS + customers, SMS read-only, tickets view.
- **Receptionist** — appointments + customers + SMS + tickets create.
- **Accountant** — reports + invoices + exports; no POS.

### 47.7 Enforcement
- Server authoritative.
- Client hides disallowed UI + disables actions (double defense).

### 47.8 Elevation
- Temporary elevation via manager PIN grants next-action scope.
- Example: cashier can refund only with manager PIN pop-over.

### 47.9 Revocation
- Immediate.
- Server pushes silent notification to active sessions to refresh capabilities.

---
## §48. Data Import (RepairDesk / Shopr / MRA / CSV)

### 48.1 Import wizard
- [ ] **Source picker** — RepairDesk / Shopr / MRA / Generic CSV / Apple Numbers file.
- [ ] **Upload file** — via share sheet or document picker; iOS 17 Files integration.
- [ ] **Field mapping** — auto-detect + manual correction; save mapping for later.

### 48.2 Dry-run
- [ ] **Preview** first 10 rows — what will import, what will fail.
- [ ] **Error report** — downloadable.

### 48.3 Execute import
- [ ] **Chunked** — 100 rows at a time with progress bar.
- [ ] **Background task** — can leave screen; Live Activity shows progress.
- [ ] **Pause / resume / cancel**.

### 48.4 Import history + rollback
- [ ] **Undo** — within 24h; restores pre-import state.
- [ ] **Log** — per-batch audit.

### 48.5 Recurring import (auto-sync)
- [ ] **Schedule** — daily CSV from S3/Dropbox/iCloud.
- [ ] **On-change webhook**.

---
## §49. Data Export

### 49.1 Full tenant export
- [ ] **Trigger** — Settings → Danger → "Export all data".
- [ ] **Bundle** — JSON + CSV + photos zip; encrypted with tenant passphrase.
- [ ] **Email / iCloud / share sheet** — delivery options.
- [ ] **Progress** — Live Activity.

### 49.2 Per-domain export
- [ ] **From list views** — export filtered results as CSV.

### 49.3 GDPR / CCPA individual export
- [ ] **Per-customer data package** — download all linked records.

### 49.4 Scheduled recurring
- [ ] **Daily to S3 / Dropbox / iCloud Drive** — tenant-configured.

---
## §50. Audit Logs Viewer — ADMIN ONLY

Access restricted to roles with `audit.view.all` capability (§47.5). Non-admins never see the audit UI; the Settings row is hidden, the deep link (`bizarrecrm://<slug>/settings/audit`) is rejected with a 403-style toast, and server authoritatively blocks `/audit-logs` on non-admin tokens. Own-history (`audit.view.self`) is a different, narrower surface — lives on §19.1 Profile as "My recent actions", reads the same endpoint scoped to actor_id = self.

### 50.1 List
- [ ] **Server**: `GET /audit-logs?actor=&action=&entity=&since=&until=`.
- [ ] **Columns** — when / actor / action / entity / diff.
- [ ] **Expandable row** — shows full JSON diff.

### 50.2 Filters
- [ ] **Actor, action, entity, date range**.
- [ ] **Saved filters** as chips.
- [ ] Free-text search across data_diff via FTS5.
- [ ] Chips: "Last 24h", "This week", "Custom".

### 50.3 Export
- [ ] **CSV / JSON / PDF for period**.
- [ ] PDF formatted for court evidence: header + footer + page numbers + signature page.

### 50.4 Alerts
- [ ] **Sensitive action** (role change, bulk delete) → admin push.

### 50.5 Scope
- Every write operation logged: who, when, what, before/after.
- Reads logged optionally (sensitive screens only).

### 50.6 Entry rendering
- Before/after diff visually (red/green).
- Actor avatar + role + device fingerprint.
- Tap → navigate to affected entity (if exists).

### 50.7 Integrity
- Entries immutable (server enforced).
- SHA chain: each entry includes hash of previous → tamper-evident.
- iOS verifies chain on export; flags tampered period.

### 50.8 Retention
- Tenant policy: 1yr / 3yr / 7yr / forever.
- Auto-archive to cold storage beyond hot window.

### 50.9 Access control
- Owner / compliance role only.
- Viewing logged (meta-audit).

### 50.10 Offline
- Cached last 90d locally.
- Older pulled on demand.

---
## §51. Training Mode (sandbox)

### 51.1 Toggle
- [ ] **Settings → Training Mode** — switches to demo tenant with seeded data.
- [ ] **Watermark banner** — "Training mode — no real charges, no real SMS".

### 51.2 Reset
- [ ] **"Reset demo data"** — wipes + reseeds.

### 51.3 Guided tutorials
- [ ] **Overlay hints** — "Tap here to create a ticket".
- [ ] **Checklist** — tutorials by topic (POS basics, ticket intake, invoicing).

### 51.4 Onboarding video library
- [ ] **Video tiles** embedded; captions; transcripts.

---
## §52. Command Palette (⌘K)

### 52.1 Universal shortcut
- [ ] **⌘K on iPad / Mac** → global command palette.
- [ ] **iPhone** — reachable via pull-down gesture on any screen.

### 52.2 Action catalog
- [ ] **Every registered action** — "New ticket", "Find customer by phone", "Send SMS", "Clock out", "Close shift", "Settings: Tax", "Reports: Revenue this month".
- [ ] **Fuzzy search** — Sublime-style; rank by recent usage.

### 52.3 Scope + context
- [ ] **Current context aware** — "Add note to this ticket" works when ticket open.
- [ ] **Entities** — type ticket # / phone / SKU → navigate.

### 52.4 Keyboard-first
- [ ] **Arrow navigate**, **⏎ execute**, **⎋ dismiss**.

---
## §53. Public Tracking Page — SERVER-SIDE SURFACE (iOS is thin)

This is a customer-facing web page served by the tenant server, not an iOS screen. The page lives at `https://<tenant-host>/track/<token>` and is read by browsers — customers never install our iOS app to see tracking. iOS's involvement is limited to:

- [ ] **Generate + share the link** from ticket detail (§4.3). The token comes from server (`POST /tickets/:id/tracking-token`); iOS only wraps it in share sheet / QR / SMS.
- [ ] **"Preview as customer"** button opens `SFSafariViewController` pointed at the public URL.

Everything else (what the page renders, status timeline, photo redaction, ETA math, pay-balance CTA) is server + web scope. Track server work in root TODO if the page needs changes. iOS has no rendering of this page to spec.
- [ ] QR content: URL `https://app.bizarrecrm.com/public/tracking/<shortId>`
- [ ] Short ID generated server-side; 8-char base32
- [ ] Printed on intake receipt + stuck on device bag
- [ ] Customer scans to see status from own phone (no install needed)
- [ ] Staff scan: same QR, different handler — opens internal ticket detail in app
- [ ] Lifecycle: active until ticket archived + 30 days
- [ ] Permanently invalidated on tenant data delete
- [ ] Privacy: landing page shows only device + status + ETA; no PII
- [ ] Reprint: ticket detail → "Reprint tag" available any time
- [ ] Principle: no customer app (per §62 ruling); customer-side web enhanced through linkable URLs only
- [ ] Public tracking page `https://app.bizarrecrm.com/public/tracking/:shortId` — branded per tenant (logo + theme), mobile-responsive light+dark, shows status/device/ETA + contact shop button
- [ ] Public pay page `https://app.bizarrecrm.com/public/pay/:linkId` — Apple Pay + card; branded
- [ ] Public quote sign page `https://app.bizarrecrm.com/public/quotes/:code/sign`
- [ ] Apple Wallet pass add page `https://app.bizarrecrm.com/public/memberships/:id/wallet` — iOS serves `.pkpass`, Android serves Google Wallet pass, desktop serves QR to scan on phone
- [ ] Self-booking page `https://app.bizarrecrm.com/public/book/:locationId`
- [ ] iOS app does NOT swallow these Universal Links; customers stay on web
- [ ] `apple-app-site-association` excludes `/public/*` patterns
- [ ] SEO: tenant `robots.txt` allows `/public/book/:locationId`
- [ ] SEO: disallow `/public/tracking/*` (URL-scoped privacy)

---
## §54. TV Queue Board — NOT AN iOS FEATURE

An in-shop wall display is either:
- A web page served by the tenant server (open on any browser / smart TV / Apple TV via AirPlay) — correct home for this feature, tracked server + web side.
- OR an Apple TV target with tvOS, which is a separate product surface and out of this plan.

iOS staff app does not host a "TV board" mode. If a tenant wants to pin an iPad to a wall and show queue status, they open the web URL in Safari + Guided Access — no iOS-app work required.

Number preserved as stub. If ever resurrected as an iOS target, reopen.

---
## §55. Assistive / Kiosk Single-Task Modes

### 55.1 POS-only mode
- [ ] **Role / device profile** — lock app to POS tab.
- [ ] **Exit** requires manager PIN.

### 55.2 Clock-in-only mode
- [ ] **For shared shop iPad** — only Timeclock accessible.

### 55.3 Training profile
- [ ] **Assistive Access adoption** — simplified icons, large buttons.
- [ ] Idle timer: in kiosk mode (§55) dim display 50% after 2 min idle; black out with brand mark after 5 min; tap anywhere wakes
- [ ] Night mode: between quiet-hour window (e.g. 10pm–6am) auto-switch to darker palette even in kiosk; prevents OLED iPad Pro burn-in
- [ ] Screen-burn prevention: subtle 1px shift every 30s on static elements
- [ ] Config: Tenant Settings → Kiosk → dim thresholds + schedule

---
## §56. Appointment Self-Booking — CUSTOMER-FACING; NOT THIS APP

Customer self-booking is a separate product surface. If ever built, it is either a tenant-server-hosted public web page (likely path) or a distinct customer-facing app — both out of scope for this staff-only iOS app (per §62 non-goals).

Staff-side pieces that overlap with booking live in §10 Appointments (staff create / reschedule / confirm) and §10 Scheduling engine. No §56 work scheduled in the iOS plan.

Number preserved as stub so cross-refs don't break.

---
## §57. Field-Service / Dispatch (mobile tech)

### 57.1 Map view
- [ ] **MapKit** — appointments pinned on map.
- [ ] **Route** to next job via Apple Maps.

### 57.2 Check-in / check-out
- [ ] **GPS verified** — arrival → start-work auto.
- [ ] **Signature on completion**.

### 57.3 On-site invoice
- [ ] **POS in the field** — BlockChyp mobile terminal.
- [ ] **Email/SMS receipt immediately**.
- [ ] Use-cases: field-service route (§57), loaner geofence (§5), auto-clock-in on shop arrival opt-in (§46), tax-location detection for mobile POS (§19.8).
- [ ] Permission: request `whenInUse` first; step up to `always` only for field-service role. Never background-track non-field users.
- [ ] Accuracy: approximate default; precise only when geocoding or routing explicitly.
- [ ] Power: significant-location-change for background (not raw GPS); stop updates when app leaves foreground unless `always` granted.
- [ ] Privacy: all location data → tenant server only (§32). Settings → Privacy → Location shows what's tracked + toggle + history export + delete history.
- [ ] Accuracy thresholds: < 20m for on-site check-in; < 100m for route planning.
- [ ] Indoor fallback: cell + Wi-Fi heuristics when GPS weak; degrade gracefully.

---
## §58. Purchase Orders (inventory)

### 58.1 PO list + detail
- [ ] **Server**: `GET/POST /purchase-orders`.
- [ ] **Create** — supplier + lines + expected date.
- [ ] **Receive** — mark items received; increment stock.
- [ ] **Partial receive**.

### 58.2 Cost tracking
- [ ] **Landed cost** — purchase + shipping / duty allocation.

---
## §59. Financial Dashboard (owner view)

### 59.1 KPI tiles
- [ ] **Revenue / profit / expenses / AR / AP / cash-on-hand** with trends.

### 59.2 Profitability
- [ ] **Per-service gross margin**.
- [ ] **Per-tech profitability**.

### 59.3 Forecast
- [ ] **30/60/90 day revenue forecast** (ML if server).

---
## §60. Multi-Location Management

### 60.1 Location switcher
- [ ] **Top-bar chip** on iPad — active location.
- [ ] **"All locations"** aggregate view for owner.

### 60.2 Transfer between locations
- [ ] **Inventory transfer** — pick items + source/dest + signature.

### 60.3 Per-location reports
- [ ] **Revenue / tickets / employees**.

---
## §61. Release checklist (go-live gates)

### 61.1 Before TestFlight
- [ ] Auth + Dashboard + Tickets + Customers + Inventory + Invoices + SMS fully functional.
- [ ] Offline queue operational.
- [ ] Push notifications working.
- [ ] Settings has Profile + Security + Appearance + Server + About.
- [ ] Crash-free > 99.5% in internal test.

### 61.2 Before App Store public
- [ ] Parity with Android on all domains above.
- [ ] POS + barcode + BlockChyp terminal + printer.
- [ ] Widgets + Live Activities + App Intents.
- [ ] iPad 3-column polish.
- [ ] Accessibility audit passes.
- [ ] Privacy policy + Terms live.
- [ ] Screenshots + App Preview.

### 61.3 Before marketing push
- [ ] Marketing campaigns + NPS + reviews.
- [ ] Memberships.
- [ ] Public pay + public tracking.
- [ ] TV board.
- [ ] Field service / dispatch (if applicable).

---
## §62. Non-goals (explicit)

- **Management / admin tools** — handled by separate Electron app; out of iOS scope.
- **Server administration** — no server-config UI in iOS.
- **Accounting-system parity** (QuickBooks replacement) — stay focused on repair-shop workflow; export to QB via server.
- **Email marketing** — SMS-first; deprioritize email marketing tools unless tenant explicitly requests.
- **Third-party marketplaces** (Shopify, Square as payment) — BlockChyp only.
- **Employee scheduling software parity** (When I Work, Deputy) — light scheduling only.
- **Customer-facing companion app** — this app is staff-only. Customers use web + Apple Wallet passes + SMS + email. No `com.bizarrecrm.myrepair` target. (See §62.)

---
## §63. Error, Empty & Loading States (cross-cutting)

### 63.1 Error states
- [ ] **Network error** — glass card: illustration + "Can't reach the server" + Retry. Show cached data below in grayscale if available.
- [ ] **Auth error** — "Session expired" toast → auto-re-auth attempt → fall back to Login.
- [ ] **Validation error** — inline under field with brand-danger accent + descriptive copy.
- [ ] **Server 5xx** — "Something went wrong on our end" + retry + "Report a problem".
- [ ] **Not-found (404)** — specific per entity ("Ticket #1234 not found" + Search button).
- [ ] **Permission denied (403)** — "Your role doesn't allow this — ask an admin".
- [ ] **Rate-limited (429)** — countdown + "Try again in Ns".
- [ ] **Offline + no cache** — "Go online to load this screen for the first time".
- [ ] **Corrupt cache** — auto-recover + re-fetch; show banner.

### 63.2 Empty states
- [ ] **First-run empty**  — brand illustration + 1-line copy + primary CTA ("Add your first customer").
- [ ] **Filter empty** — "No results for this filter — clear filter / change dates".
- [ ] **Search empty** — "No matches — try different spelling".
- [ ] **Section empty** (detail sub-lists) — inline muted copy; no illustration.
- [ ] **Permission-gated** — "This feature is disabled for your role".

### 63.3 Loading states
- [ ] **Skeleton rows** — shimmer glass placeholders for lists.
- [ ] **Hero skeleton** — card shape placeholder for detail pages.
- [ ] **Spinner** — only for sub-second operations (save); use progress for long.
- [ ] **Progress bar** — determinate for uploads / imports / printer jobs.
- [ ] **Optimistic UI** — item appears instantly with "Sending…" glow.
- [ ] **Shimmer duration cap** — if > 5s loading, swap to "Still loading… slower than usual — tap to retry".

### 63.4 Inline pending
- [ ] **Saving chip** — "Saving…" glass chip top-right while mutation in flight.
- [ ] **Saved tick** — brief green check on save.

### 63.5 Destructive-action flows
- [ ] **Soft-delete with undo** — toast "Deleted. Undo?" 5-second window.
- [ ] **Hard-delete confirm** — alert with consequence copy + type-to-confirm for catastrophic actions.
- [ ] **Undo stack** — last 5 actions undoable via `⌘Z`.

---
## §64. Copy & Content Style Guide (iOS-specific tone)

### 64.1 Voice
- [ ] **Direct, friendly, short** — ≤ 12 words per sentence.
- [ ] **Sentence case** — not Title Case. "Create ticket" not "Create Ticket".
- [ ] **Active voice**.
- [ ] **No jargon** to end-users (staff-facing).

### 64.2 Button verbs (consistent)
- [ ] "Save" never "OK" on forms.
- [ ] "Delete" never "Remove" for hard delete.
- [ ] "Cancel" always on dismiss.
- [ ] "Done" on completion dismiss.

### 64.3 Error copy rules
- [ ] **What** happened.
- [ ] **Why** (if known).
- [ ] **What to do**.
- [ ] Don't blame the user.

### 64.4 Placeholders
- [ ] **Input hints** show format: "555-123-4567" for phone.
- [ ] **No assistive text saying obvious** ("Enter your name").

### 64.5 Timestamps
- [ ] **Relative for recent** — "3 min ago", "Yesterday at 2:30 PM".
- [ ] **Absolute for older** — "Apr 3, 2026".
- [ ] **Tooltip on hover (iPad/Mac)** — always shows absolute.

### 64.6 Numbers
- [ ] **Currency** — always with symbol + decimals respecting locale.
- [ ] **Large numbers** — 1,234 (comma-separated), or `1.2k` / `1.2M` only on dense chips.
- [ ] **Zero state** — "—" not "0" when value is N/A.

### 64.7 Names + IDs
- [ ] **Ticket IDs** — `#1234` prefix.
- [ ] **Customer** — "John S." on space-constrained, full name in detail.
- [ ] **Phone** — formatted per locale.
- [ ] Voice: confident/direct/friendly; no "Oops!"/"Uh-oh!"/emoji-in-error-text; active voice ("We couldn't save" > "Save failed"); avoid corporate tone
- [ ] Labels: buttons verb-first ("Save ticket", "Print receipt", "Refund payment"); nav titles noun ("Tickets", "Inventory"); empty-state sentence+CTA ("No tickets yet. Create your first." [Create Ticket])
- [ ] Numbers: locale currency ("$1,234.00"); percentages "12%" not "12.0 percent"; locale distance units
- [ ] Dates: relative <7 days ("2h ago", "yesterday"); absolute >7 days ("Apr 12"); full date+time only in detail/tooltips
- [ ] Error language: what happened, why, what to do ("Couldn't reach server — check your connection and try again." not "Network error 0x4")
- [ ] Permission prompts explain why: Camera ("scan barcodes and take photos"), Location ("field-service routing"), Push ("notify you about new tickets, payments, and messages")
- [ ] No jargon: "Sync"→"Update", "Endpoint"→"URL", idempotency keys invisible to user
- [ ] Abbreviations: "OK" not "Okay"; "appointment" not "appt"; SMS/PIN/OTP/PDF acceptable
- [ ] Sentence case, not title case, except product/feature names
- [ ] i18n discipline: every string keyed in `Localizable.strings`; no concatenation, use format placeholders
- [ ] Format: `.strings` files per locale in `App/Resources/Locales/<lang>.lproj/`; `docs/copy-deck.md` mirrors keys + English source for non-engineers.
- [ ] Key naming convention: `ticket.list.empty.title/.body/.cta`; namespaces `app.` `nav.` `ticket.` `customer.` `pos.` `sms.` `settings.` `error.` `a11y.`.
- [ ] Variables: plural support via `%#@tickets@`; phone/money/date formatted through `Locale`, never string literal.
- [ ] Categories: Labels (button/nav/chip), Descriptions (help/placeholders), Errors (§63 taxonomy), A11y (VO labels/hints), Legal (waivers/TOS/privacy).
- [ ] Legal-string review by counsel; immutable post-publish (re-sign required on change).
- [ ] Glossary enforced: "customer" not "client", "ticket" not "job", "employee" not "staff"; published in `docs/glossary.md`.
- [ ] Export/import via CSV with Crowdin/Lokalise; never call vendor APIs from iOS, everything via tenant server.

---
## §65. Deep-link / URL scheme reference

### 65.0 Three URL concepts — don't confuse

Easy to blur three different URL kinds. This section is explicit so the rest of the plan stays unambiguous.

| Concept | Example | Who uses it | Network? |
|---|---|---|---|
| **A. Tenant API base URL** | `https://app.bizarrecrm.com`, `https://repairs.acmephone.com`, `https://192.168.1.12` | iOS `APIClient` talking to the tenant server. Set at login from server URL field. Whatever value the customer typed (cloud-hosted or self-hosted — their server's `.env` dictates). | Yes — HTTPS network calls |
| **B. Universal Link (tap-to-open-app via HTTPS)** | `https://app.bizarrecrm.com/tickets/123` | Apple system: user taps a `https://` link in Mail / Messages / Safari; iOS checks the domain's `apple-app-site-association`; if match, opens our app directly instead of the web page. | Yes — the URL is a real website path; Apple validates AASA once |
| **C. Custom scheme (tap-to-open-app via URI)** | `bizarrecrm://<slug>/tickets/123` | iOS local app routing. Registered in our Info.plist. The `bizarrecrm://` URI is **not a network address** — no DNS, no HTTPS, no server round-trip. iOS sees the scheme, launches our app, hands the URI to our app, our app parses the path and navigates. | No — purely a local iOS routing token |

**Important distinctions:**
- **A is completely independent of B and C.** The tenant's API server domain has nothing to do with the deep-link mechanism. A self-hosted tenant on `https://repairs.acmephone.com` still uses the `bizarrecrm://` scheme for deep links; the scheme doesn't care about their domain because it's not a web URL.
- **B requires Apple entitlement, which is compiled in.** We can only include domains we own (`app.bizarrecrm.com`, `*.bizarrecrm.com`). We CANNOT include `repairs.acmephone.com` without re-signing the app; Apple rejects AASA verification for domains not in the entitlement. That's why self-hosted tenants don't get Universal Links.
- **C works everywhere, but the path must carry tenant identity.** The custom scheme's first path segment is a tenant slug so the app knows which tenant the link is about (the app might be signed into one tenant now, and the link might be for another one, or for a tenant this device hasn't seen yet). Slug maps to the API base URL (concept A) via Keychain at login time.

### 65.1 Universal Links (concept B) — cloud-hosted tenants only

Paths opened from a `https://` URL on an Apple device. iOS validates `app.bizarrecrm.com/.well-known/apple-app-site-association` once per device; if the entitlement matches, tapping the link opens our app instead of Safari.

| URL | Opens |
|---|---|
| `https://app.bizarrecrm.com/c/:shortCode` | Open tenant-scoped path derived from short code |
| `https://app.bizarrecrm.com/track/:token` | Public tracking page (customer-facing, opens without login) |
| `https://app.bizarrecrm.com/pay/:token` | Public pay page (customer-facing) |
| `https://app.bizarrecrm.com/review/:token` | Public review flow (customer-facing) |
| `https://<tenant-slug>.bizarrecrm.com/<path>` | Cloud-subdomain shortcut; maps to same internal route table as the custom scheme |

- [ ] `applinks:app.bizarrecrm.com` + `applinks:*.bizarrecrm.com` in entitlement.
- [ ] AASA file hosted + immutable version pinned per app release.
- [ ] Self-hosted tenants are not in the entitlement. Do not attempt per-tenant re-signing; not scalable.

### 65.2 Custom scheme (concept C) — every tenant, incl. self-hosted

Not a network URL. Local iOS routing token. Registered in Info.plist (`CFBundleURLSchemes: ["bizarrecrm"]`). Shape:

```
bizarrecrm://<tenant-slug>/<path>
```

`<tenant-slug>` is a stable identifier the tenant server declares on login (e.g., `acme-repair`, `bizarre-demo`, or whatever `server.env` sets). iOS Keychain maps `slug → API base URL (concept A)` at login time, so when a `bizarrecrm://` link arrives the app knows which server to talk to.

| Path | Screen |
|---|---|
| `bizarrecrm://<slug>/dashboard` | Home |
| `bizarrecrm://<slug>/tickets/:id` | Ticket detail |
| `bizarrecrm://<slug>/tickets/new` | New ticket |
| `bizarrecrm://<slug>/customers/:id` | Customer detail |
| `bizarrecrm://<slug>/customers/new` | New customer |
| `bizarrecrm://<slug>/inventory/:sku` | Inventory detail |
| `bizarrecrm://<slug>/inventory/scan` | Barcode scan |
| `bizarrecrm://<slug>/invoices/:id` | Invoice detail |
| `bizarrecrm://<slug>/invoices/:id/pay` | Invoice pay |
| `bizarrecrm://<slug>/estimates/:id` | Estimate detail |
| `bizarrecrm://<slug>/leads/:id` | Lead detail |
| `bizarrecrm://<slug>/appointments/:id` | Appointment detail |
| `bizarrecrm://<slug>/sms/:threadId` | SMS thread |
| `bizarrecrm://<slug>/sms/new?phone=…` | New SMS compose |
| `bizarrecrm://<slug>/pos` | POS |
| `bizarrecrm://<slug>/pos/sale/new` | New sale |
| `bizarrecrm://<slug>/pos/return` | Returns |
| `bizarrecrm://<slug>/settings` | Settings root |
| `bizarrecrm://<slug>/settings/:tab` | Specific tab |
| `bizarrecrm://<slug>/timeclock` | Timeclock |
| `bizarrecrm://<slug>/search?q=…` | Search |
| `bizarrecrm://<slug>/notifications` | Notifications |
| `bizarrecrm://<slug>/reports/:name` | Report detail |

Slug resolution rules:
- Slug comes from the server on login (`/auth/me` response) and is cached in Keychain against that tenant's API base URL (concept A).
- If the app receives a link with an unknown slug, show the Login screen pre-filled with last-used server URL + a note "Sign in to `<slug>` to continue."
- If the slug matches a known cached tenant the user is signed into, route immediately.
- If the slug matches a known cached tenant the user is NOT currently active in, show confirmation "Open <Tenant Name>? You'll be signed out of <Current Tenant> first." (§25.8 multi-tenant safety rule.)

### 65.3 Associated-domains entitlement (what Apple compiles in)
- [ ] `applinks:app.bizarrecrm.com` — main.
- [ ] `applinks:*.bizarrecrm.com` — cloud-hosted tenant subdomains we provision.
- [ ] **Not** per-tenant self-hosted domains. They use the custom scheme (§65.2).
- [ ] See §65 for the canonical URL-scheme handler spec (schemes, route map, validation, state preservation, Universal Link verification, sovereignty). No duplicate tracking here.

---
## §66. Haptics Catalog (iPhone-specific)

| Event | Haptic | Sound |
|---|---|---|
| Sale complete | `.success` | chime |
| Add to cart | `.impact(.light)` | — |
| Scan barcode success | `.impact(.medium)` | beep |
| Scan barcode fail | `.notificationOccurred(.warning)` | — |
| Save form | `.success` | — |
| Validation error | `.notificationOccurred(.error)` | — |
| Destructive confirm | `.impact(.heavy)` | — |
| Pull-to-refresh commit | `.selection` | — |
| Long-press menu | `.impact(.medium)` | — |
| Toggle | `.selection` | — |
| Tab switch | `.selection` | — |
| Ticket status change | `.selection` | — |
| Card declined | `.notificationOccurred(.error)` | — |
| Drawer kick | `.impact(.heavy)` | kick clack (printer) |
| Clock in | `.success` | — |
| Clock out | `.success` | — |
| Signature committed | `.selection` | — |

- [ ] All sounds respect silent switch + Settings → Sounds master.
- [ ] All haptics respect Settings → Haptics master + iOS accessibility setting.

### 66.1 CoreHaptics engine
- `CHHapticEngine` registered on app start.
- Re-start on `audioSessionInterruption` + `applicationWillEnterForeground`.
- Single `HapticCatalog.swift` source; ban ad-hoc calls.
- Non-haptic devices (iPad without Taptic) → silent.

### 66.2 Custom patterns
- **Sale success** — 3-tap crescendo (0.1, 0.2, 0.4 intensity, 40ms apart). Plus success chime.
- **Card decline** — two-tap sharp (0.9, 0.9, 80ms apart).
- **Drawer open** — single medium thump.
- **Scan match** — single gentle click + pitched sound.
- **Scan unmatched** — double sharp (warning).
- **Status advance** — ramp from 0.2 → 0.6 over 150ms.
- **Undo** — reverse ramp.
- **Signature complete** — triple subtle, low intensity.
- [ ] Quiet hours: user-defined in Settings → Notifications → Quiet hours (e.g. 9pm–7am); haptics drop to minimum intensity, sounds muted; except critical (backup failure / security alert)
- [ ] Silent mode: honor device mute switch — no sounds; haptics still fire unless user disabled in iOS
- [ ] Do-Not-Disturb: respect Focus modes (§13); notifications routed per Focus rules

---
## §67. Motion Spec

### 67.1 Durations
- 120ms — chip toggle
- 160ms — FAB appear
- 200ms — banner slide
- 220ms — tab switch
- 280ms — push navigation
- 340ms — modal sheet
- 420ms — shared element transition
- 600ms — pulse / confetti

### 67.2 Curves
- `.interactiveSpring(0.3, 0.75)` default.
- `.easeInOut` for bidirectional toggles.
- `.easeOut` for appearance.
- `.easeIn` for dismissal.

### 67.3 Reduce Motion paths
- Springs → fades.
- Parallax → static.
- Pulse → single-frame.
- Shared element → cross-fade.

### 67.4 Signature animations
- [ ] **Ticket-created** — temporary pulse highlight on new row.
- [ ] **Sale-complete** — confetti + check mark center screen.
- [ ] **SMS-sent** — bubble fly-in from composer.
- [ ] **Payment-approved** — green check inside a circle draw.
- [ ] **Low-stock warn** — stock badge pulses red.

---
## §68. Launch Experience

### 68.1 Launch screen
- [ ] **Branded splash** — logo center + gradient; identical in light/dark.
- [ ] **No loading spinners** before UI — state restore quickly.

### 68.2 Cold-start sequence
- [ ] Splash (200ms max) → RootView resolve → Dashboard or Login.
- [ ] **State restore** — last tab + last selected list row.
- [ ] **Deep-link resolution** — before first render.

### 68.3 First-run
- [ ] **Server URL entry** with quick-pick options (saved URLs + "bizarrecrm.com").
- [ ] **What's new** — modal on major version update.

### 68.4 Onboarding tooltips
- [ ] **Coach marks** — first time each top-level screen opened.
- [ ] **Dismissable** + "Don't show again".
- [ ] **Per-feature** — widget install prompt, barcode scan, BlockChyp pairing.

---
## §69. In-App Help

### 69.1 Help center
- [ ] **Settings → Help** — searchable FAQ.
- [ ] **Topic articles** — bundled markdown + images.
- [ ] **Context-aware help** — "? " icon on complex screens → relevant article.

### 69.2 Contact support
- [ ] **Send support email** — prefilled with diagnostic bundle. Recipient resolved from `GET /tenants/me/support-contact` (same source as §2.12 account-locked modal). Never hardcoded. Self-hosted tenants → their own admin. bizarrecrm.com-hosted → `pavel@bizarreelectronics.com`.
- [ ] **Live chat** (if server supports) — embedded.

### 69.3 Release notes
- [ ] **What's new** — on version bump, modal highlights.
- [ ] **Full changelog** — in Help.

### 69.4 Feature hints
- [ ] **Pro-tip banners** — rotating tips on Dashboard.
- [ ] Entry: Settings → Help → "Report a bug". Optional shake-to-report (debug builds only) via `UIResponder.motionEnded`.
- [ ] Form fields: description (freeform, required); category (crash / UI bug / data issue / perf / feature request); severity; optional attachments (auto-captured annotatable screenshot, recent logs, last crash report).
- [ ] `POST /support/bug-reports` with payload + attachments. Server issues ticket #, iOS toast "Thanks — ticket BG-234 created."
- [ ] Follow-up updates surface in §13 Notifications tab when devs respond.
- [ ] PII guard: logs run through §32.6 Redactor before attach.
- [ ] Offline: queue in §20.2; submit on reconnect.
- [ ] "What's new" modal on first launch of new version; text from `GET /app/changelog?version=X.Y.Z` (server-driven, locale-scoped, allows post-release content updates without re-ship).
- [ ] Full history list under Settings → About → Changelog: version + date + highlights + "Read more" deep-link to blog.
- [ ] Per-user "Don't show on launch" opt-out.
- [ ] Offline: cache last N versions.
- [ ] See §19 for the full list.

---
## §70. Notifications — granular per-event matrix

**Default rule: app-push only.** Every staff-facing event delivers via APNs push + in-app banner and nothing else out of the box. SMS and email to the staff member's own phone / inbox are **off by default** for every event type — they're opt-in per user in Settings § 19.3. Rationale: spamming a cashier's personal SMS inbox with every "ticket assigned" burns goodwill, doubles notification clutter, and confuses users who don't realize the app already pushed the event. Server also saves money on outbound SMS / email for internal staff comms.

**Customer-facing notifications** (reminders sent to the customer's phone / email — e.g. appointment confirmations, ready-for-pickup texts, invoice reminders) are a different flow and live in §12 Message templates + §37 Campaigns. Those do default-on and run on tenant policy, not this matrix.

| Event | Default Push | Default In-App | Default Email (to staff) | Default SMS (to staff) | Role-gated |
|---|---|---|---|---|---|
| Ticket assigned to me | ✅ | ✅ | — | — | Assignee |
| Ticket status change (mine) | ✅ | ✅ | — | — | — |
| Ticket status change (anyone) | — | ✅ | — | — | Admin |
| New SMS inbound (from customer) | ✅ | ✅ | — | — | — |
| SMS delivery failed | ✅ | ✅ | — | — | Sender |
| New customer created | — | ✅ | — | — | Admin |
| Invoice overdue | ✅ | ✅ | — | — | Admin / AR |
| Invoice paid | ✅ | ✅ | — | — | Creator |
| Estimate approved | ✅ | ✅ | — | — | Creator |
| Estimate declined | ✅ | ✅ | — | — | Creator |
| Appointment reminder 24h (staff-side) | — | ✅ | — | — | Assignee |
| Appointment reminder 1h (staff-side) | ✅ | ✅ | — | — | Assignee |
| Appointment canceled | ✅ | ✅ | — | — | Assignee |
| @mention in note / chat | ✅ | ✅ | — | — | — |
| Low stock | — | ✅ | — | — | Admin / Mgr |
| Out of stock | ✅ | ✅ | — | — | Admin / Mgr |
| Payment declined | ✅ | ✅ | — | — | Cashier |
| Refund processed | — | ✅ | — | — | Originator |
| Cash register short | ✅ | ✅ | — | — | Admin |
| Shift started / ended | — | ✅ | — | — | Self |
| Goal achieved | ✅ | ✅ | — | — | Self + Mgr |
| PTO approved / denied | ✅ | ✅ | — | — | Requester |
| Campaign sent | — | ✅ | — | — | Sender |
| NPS detractor | ✅ | ✅ | — | — | Mgr |
| Setup wizard incomplete (24h) | — | ✅ | — | — | Admin |
| Subscription renewal | — | ✅ | — | — | Admin |
| Integration disconnected | ✅ | ✅ | — | — | Admin |
| Backup failed (critical) | ✅ | ✅ | — | — | Admin |
| Security event (new device / 2FA reset) | ✅ | ✅ | — | — | Self + Admin |

Legend: Push = APNs push delivered to device. In-App = banner inside the app when foregrounded + list entry on §13 Notifications tab. Email / SMS = outbound to staff member's own personal contact (not to the customer).

### 70.1 User override (Settings § 19.3)
- [ ] Per-event toggles: Push on/off, In-App on/off, Email on/off, SMS on/off. All four independent.
- [ ] Defaults shown greyed with "(default)" label until user flips.
- [ ] "Reset all to default" button.
- [ ] Explicit warning when enabling SMS on a high-volume event ("This may send 50+ texts per day").

### 70.2 Tenant override (Admin)
- [ ] Admin can shift a tenant's default (e.g., "for this shop, staff always get email on invoice-overdue"). Baseline shipped by us is push-only; tenant admin's shift is their call.
- [ ] Per-tenant dashboard shows current deltas vs shipped defaults.

### 70.3 Delivery rules
- [ ] Push respects iOS Focus + tenant server quiet hours (§21.9 dropped — rule stands).
- [ ] In-app banner never shown if the user is already looking at the source (e.g., SMS inbound for a thread the user is reading).
- [ ] If the same event re-fires within 60s, collapse into a "+N more" badge update instead of sending a second push.

### 70.4 Critical override
- [ ] Four events (Backup failed, Security event, Out of stock of a blocking part during a sale, Payment declined mid-transaction) may mark `interruption-level: timeSensitive` so iOS Focus does not suppress them. Otherwise default `active`.
- [ ] Never `critical` (that requires Apple Critical Alerts entitlement; reserve for specific tenants that request it — §13.4).
- [ ] Delivery tuning: respect quiet hours (§13); bundle repeated pushes (group SMS from same thread into one notification with message-count badge)
- [ ] Rich content: SMS notification embeds photo thumbnail if MMS; payment notification shows amount + customer name; ticket assignment embeds device + status
- [ ] Inline reply: SMS_INBOUND action "Reply" uses `UNTextInputNotificationAction` — reply from push without opening app
- [ ] Sound library: Apple default + 3 brand custom sounds (cash register, bell, ding); user picks per category
- [ ] Clear-all: on app foreground after read, system badge clears accordingly; single tap clears relevant bundle
- [ ] Historical view: Settings → Notifications → "Recent" shows last 100 pushes for audit
- [ ] Push token rotation: on app start or change POST new token to `/device-tokens` with device model; stale tokens cleaned server-side
- [ ] Fail-safe: retry APNs token register with exponential backoff on failure; manual "Re-register" in Settings
- [ ] Per-event copy matrix with title/body/action buttons for: SMS_INBOUND (Reply/Mark Read/Call), TICKET_ASSIGNED (Open/Accept/Snooze), TICKET_STATUS (Open), PAYMENT_RECEIVED (Open/Send Receipt), APPT_REMINDER (Open/Navigate), LOW_STOCK (Open/Create PO), TEAM_MENTION (Reply/Open), ESTIMATE_APPROVED (Open/Convert), BACKUP_FAILED (Open), DAILY_SUMMARY (Open).
- [ ] Tone: short, actionable, no emoji in title; body includes identifier so push list stays scannable.
- [ ] Localization: each copy keyed; fallback to English if locale missing.
- [ ] A11y: VoiceOver reads title + body + action hints.
- [ ] Interruption level mapping per §13.4 categories.
- [ ] Bundling: repeated same-type pushes within 60s merged as "+N more".
- [ ] See §21 for the full list.

---
## §71. Privacy-first analytics event list

All events target tenant server (see §32).

- `app.launch`
- `app.foreground`
- `app.background`
- `auth.login.success`
- `auth.login.failure`
- `auth.logout`
- `auth.biometric.success`
- `screen.view` (with screen name + duration)
- `action.tap` (with screen + action + entity-kind)
- `mutation.start` / `.success` / `.fail`
- `sync.cycle.start` / `.complete`
- `sync.failure`
- `pos.sale.start` / `.complete` / `.fail`
- `pos.return.complete`
- `pos.shift.open` / `.close`
- `barcode.scan` (success/fail)
- `printer.print` (success/fail)
- `terminal.charge` (success/fail)
- `sms.send`
- `push.received`
- `push.tapped`
- `widget.view`
- `live_activity.start` / `.end`
- `deeplink.opened`
- `feature.first_use` (feature name)

### 71.1 Schema
```
{
  "event": "screen.view",
  "ts": "2026-04-19T14:03:22.123Z",
  "app_version": "1.2.3 (24041901)",
  "ios_version": "26.0",
  "device_model": "iPhone15,3",
  "session_id": "uuid",
  "user_id": "hashed_8",
  "tenant_id": "hashed_8",
  "props": { "screen": "dashboard", "duration_ms": 2341 }
}
```

### 71.2 No tracking
- No IDFA, no Facebook pixel, no Google Analytics, no Braze.

---
## §72. Final UX Polish Checklist

### 72.1 Animation
- [ ] Every screen's entry + exit animation tested.
- [ ] No janky flashes on state change.
- [ ] Modals never pop.

### 72.2 Focus
- [ ] Keyboard first-responder set deliberately on form open.
- [ ] Focus traps for modals.
- [ ] Focus returns to opener on dismiss.

### 72.3 Keyboard dismiss
- [ ] Tap-outside + scroll dismisses.
- [ ] Done button on number pads.

### 72.4 Loading → Done transitions
- [ ] Skeleton never jumps to content without cross-fade.

### 72.5 Scroll behavior
- [ ] Preserve scroll on back-nav.
- [ ] Jump-to-top on tab re-select.

### 72.6 Pull-to-refresh
- [ ] Available on every list + Dashboard.

### 72.7 Selection + multi-select
- [ ] Long-press enters edit mode on lists.
- [ ] Batch-action bar slides up from bottom (glass).

### 72.8 Sheets vs full-screen
- [ ] Create/edit forms in sheets (medium/large detents).
- [ ] Detail views full-screen push.

### 72.9 Back-navigation consistency
- [ ] Swipe-back works on every non-modal push.
- [ ] Custom back buttons discouraged.

### 72.10 Status bar
- [ ] Honors `.preferredStatusBarStyle` per screen.
- [ ] Light on dark surfaces; dark on light.

---
## §73. CarPlay — DEFERRED (contents preserved, not active work)

**Status:** not needed now. No engineering time allocated. Revisit only if field-service volume crosses threshold (> 20% tenants use Field Service lane) or a specific tenant contract requires it. CarPlay entitlement (`com.apple.developer.carplay-fleet`) adds 2–4 weeks of Apple approval on top of implementation, so this is a "decide well ahead of need" item.

Spec preserved below as reference for when it reopens; not active.

<!-- BEGIN DEFERRED — CarPlay

Evaluate only if field-service volume crosses threshold (>20% tenants use Field Service lane). Otherwise defer.

### 73.1 Use-cases
- Today's route — CarPlay list of on-site appointments in optimized order.
- Tap customer → dial — CallKit hand-off from CarPlay.
- Navigate to address — Apple Maps handoff.
- Arrive / Start / Complete — three big buttons, spoken confirmation.
- Status note voice-dictation — Siri "Add note to ticket 4821".
- No pricing, no POS, no inventory — too risky while driving.

### 73.2 Template choice
- CPListTemplate for appointments (driver-safe, tall rows, icons).
- CPPointOfInterestTemplate for customer locations.
- CPNowPlayingTemplate not used — not a media app.
- CPInformationTemplate for ticket short-detail (one line, max 3 fields).
- Never use free-form entry; everything is pick-list or Siri.

### 73.3 Entitlements
- Request CarPlay entitlement (com.apple.developer.carplay-fleet or com.apple.developer.carplay-messaging) — likely fleet for field techs. Apple approval ≈ 2–4 weeks.
- If not approved, fall back to standard in-car Siri integration via App Intents (works without entitlement).

### 73.4 Sovereignty
- CarPlay location and audio stays on device. No routing through third-party nav providers — use Apple Maps only.
- Voice dictation uses on-device Siri where supported (iOS 17+).

### 73.5 Testing
- CarPlay simulator target in Xcode.
- Physical head-unit test before shipping (Apple requirement for fleet entitlement).

END DEFERRED — CarPlay -->

---
## §74. Server API gap analysis — PRE-PHASE-0 GATE

**Runs before Phase 0 Foundation begins.** Everything in Phase 0 presumes the server endpoints below exist or are explicitly replaced by a stub — otherwise Phase 0 work stalls as soon as it tries to talk to the server. Treat this like a tech-debt audit done up-front rather than discovered mid-build.

**Status 2026-04-20:** first pass complete → `docs/ios-api-gap-audit.md`. 10 missing + 5 URL-shape mismatches. Quarterly re-audit due 2026-07-20.

Procedure:
1. **One-pass audit** against `packages/server/src/routes/`. For every endpoint below, mark: `exists` / `partial` / `missing`. Dump the result into a GitHub issue titled `iOS Phase 0 — server endpoint gap audit`.
2. **For each `missing` / `partial`** — file a matching server ticket in root `TODO.md` (same pattern as `TEAM-CHAT-AUDIT-001` / `IMAGE-FORMAT-PARITY-001`). Block the iOS feature that depends on it until the server ticket closes.
3. **Local shim (§74.3)** returns `APIError.notImplemented` for any endpoint still marked `missing`; iOS shows "Coming soon — feature not yet enabled on your server" rather than crashing. This makes Phase 3+ surfaces merge even while a handful of their endpoints are still server-pending.
4. **Re-audit** quarterly. `agent-ownership.md` Phase 0 gate mentions this audit; gate passes only once the matrix is documented (not necessarily all-green — partial is acceptable as long as shims are explicit).

Endpoints iOS expects that may not yet exist. Verify before shipping each feature. If not created, add to main `TODO.md` and skip the dependent item until the ticket closes.

### 74.1 Likely missing (verify with `packages/server/src/routes/`)
| Endpoint | Used by § | Status |
|---|---|---|
| `POST /telemetry/events` | §32 | Verify |
| `POST /telemetry/crashes` | §32.3 | Verify |
| `GET  /sync/delta?since=<cursor>` | §20.4 | Verify |
| `POST /sync/conflicts/resolve` | §20.6 | Verify |
| `POST /device-tokens` | §21.1 | Likely exists |
| `POST /call-logs` | §42 | Likely missing |
| `GET  /gift-cards/:code` | §40 | Verify |
| `POST /gift-cards/redeem` | §40 | Verify |
| `POST /store-credit/:customerId` | §40 | Verify |
| `POST /payment-links` | §41 | Verify |
| `GET  /payment-links/:id/status` | §41 | Verify |
| `GET  /public/tracking/:shortId` | §53 | Likely needs public-side route |
| `POST /nlq-search` | §18.6 | Likely missing |
| `POST /pos/cash-sessions` | §39 | Verify |
| `POST /pos/cash-sessions/:id/close` | §39 | Verify |
| `GET  /audit-logs` | §50 | Verify |
| `POST /imports/start` | §48 | Verify |
| `GET  /imports/:id/status` | §48 | Verify |
| `POST /exports/start` | §49 | Verify |
| `GET  /exports/:id/download` | §49 | Verify |
| `POST /tickets/:id/signatures` | §4.5 | Verify |
| `POST /tickets/:id/pre-conditions` | §4.3 | Verify |
| `GET  /device-templates` | §43 | Verify |
| `POST /locations` | §60 | Verify |
| `GET  /memberships/:id/wallet-pass` | §38 | Likely missing (need PassKit server) |

### 74.2 Action
- Before each feature ships, an iOS engineer files a server ticket if endpoint missing.
- iOS writes request/response TypeScript DTO in `packages/shared/` so web and Android can reuse.

### 74.3 Local shim
- APIClient returns 501 hand-crafted `APIError.notImplemented` for missing endpoints. UI shows "Coming soon — feature not yet enabled on your server" rather than crash.

---
## §75. App Store / TestFlight assets — DEFERRED (pre-Phase-11 only)

Not needed now. Content preserved as the release-agent spec; revisit pre-Phase 11 submission. Same posture as §33 + §76. Screenshots, app previews, descriptions, privacy disclosures, review notes all live in the marketing/release lane, not feature engineering.

<!-- BEGIN DEFERRED — App Store / TestFlight assets

### 75.1 Screenshots
- 6.9" iPhone (iPhone 16 Pro Max): 10 screenshots covering Dashboard / Tickets / POS / Inventory / SMS / Reports / Dark mode / Glass nav / Offline / Settings.
- 6.3" iPhone: same set.
- 5.5" iPhone: legacy — 5 screenshots.
- 13" iPad (iPad Pro M4): 10 screenshots of 3-column splits.
- 12.9" iPad legacy: same.
- Mac "Designed for iPad": 5 screenshots.

### 75.2 App preview videos
- 30s loop per device family.
- Music: none (keeps focus).
- Narrated captions (localized per market).

### 75.3 Description
- 300 chars promo — "Run your repair shop from anywhere."
- 4000 chars long — features enumerated.
- Keywords — repair, crm, pos, tickets, sms, inventory, invoice, shop, field, service (avoid competitor names).

### 75.4 Privacy
- Data Collection: none off-device (per §32).
- Privacy manifest (`PrivacyInfo.xcprivacy`) declares no tracking domains.

### 75.5 Review notes
- Demo account: `demo@bizarrecrm.com / ReviewTeam2026!` → pre-seeded tenant.
- Server URL field: `https://demo.bizarrecrm.com`.
- BlockChyp: POS available with test card sim (no real charges).

### 75.6 What's New
- Short changelog per release. Don't dump diff.

END DEFERRED — App Store / TestFlight assets -->

---
## §76. TestFlight rollout plan — DEFERRED (pre-Phase-11 only)

Same posture as §33 + §75. Content kept as the release-agent spec.

<!-- BEGIN DEFERRED — TestFlight rollout plan

### 76.1 Internal (team)
- 25 internal testers. Fastlane lane `beta_internal` uploads on each main-branch merge.
- Smoke tests: launch, login, view ticket, POS dry-run.

### 76.2 External — closed cohort
- 100 external testers = existing customers who opted in.
- Invite via email; 7-day test window per build.
- Feedback form in-app: Settings → "Beta feedback" → composer.
- Don't ship to cohort if internal smoke failed.

### 76.3 External — public
- Up to 10,000 testers; public link.
- Opens Phase 5+.

### 76.4 Phased release on App Store
- 1% → 2% → 5% → 10% → 20% → 50% → 100% over 7 days.
- Pause if crash-free sessions < 99.5% (measured via own MetricKit telemetry).

### 76.5 Rollback
- On crash-free < 99.0% rollback to previous binary via Phased Release pause + new build.
- Never remove from sale unless security-critical.

END DEFERRED — TestFlight rollout plan -->

---
## §77. Sandbox vs prod — SCOPE REDUCED

No in-app live switcher. Sign out + sign in handles tenant change. Keychain caches server URL + username (never tokens). Sandbox tenants render with orange top-bar accent (server flag `tenant_mode`). Per-tenant SQLCipher DB; signing out closes current, signing into another opens theirs; no concurrent tenants in memory. Login screen shows "Recent servers" chip row if user has signed in to multiple.

---
## §78. Data model / ERD

### 78.1 Entities (local + server)
- `Tenant` — id, name, server URL, branding.
- `User` — id, email, role, tenant_id.
- `Customer` — id, name, phones[], emails[], tags[], LTV, last_visit, tenant_id.
- `Ticket` — id, customer_id, status_id, assignee_id, created_at, updated_at, devices[], pre_conditions[], services[], parts[], notes[], photos[], signatures[], payments[].
- `Device` — embedded in ticket; make, model, serial, imei.
- `InventoryItem` — id, sku, name, cost, price, qty, location, vendor_id.
- `Invoice` — id, ticket_id?, customer_id, lines[], totals, payments[], status.
- `Payment` — id, invoice_id, amount, method, blockchyp_ref.
- `SMSThread` — id, customer_id, messages[].
- `SMSMessage` — id, thread_id, body, direction, timestamp.
- `Appointment` — id, customer_id, start, duration, type.
- `Employee` — id, user_id, role, commission_rule_id, shifts[].
- `Shift` — id, employee_id, start, end, cash_open, cash_close.
- `AuditLog` — id, actor_id, action, entity, entity_id, data_diff, timestamp.
- `FeatureFlag` — key, scope, value.
- `Notification` — local + server records.

### 78.2 Relationships
- Customer 1:N Ticket 1:N Invoice.
- Ticket M:N Part (via `ticket_part`), M:N Service.
- Employee 1:N Shift.
- Every entity belongs-to Tenant (row-level tenant_id enforced server + client).

### 78.3 Normalization
- Customer contacts denormalized (phones / emails arrays) for simple queries.
- Tags normalized via `tag` + `entity_tag` join.
- Photos store URL + metadata; binary not in DB.

### 78.4 IDs
- UUIDv4 server-generated.
- Client-generated for offline creates (namespace v5 with tenant seed to avoid collision).

### 78.5 Deletion
- Soft delete (tombstone) for most entities; hard delete only after retention window.

### 78.6 Versioning
- `updated_at` per entity used for sync delta.
- `version_hash` optional for conflict detection.

---
## §79. Multi-tenant user session mgmt — SCOPE REDUCED

**Scope decision (2026-04-20):** In-app live multi-tenant switching dropped (see §19.22, §77). Rationale: near-zero real-world usage, complicates security scoping, and the sign-out → sign-in path (with last-used server + username prefilled + biometric) handles franchise operator / freelance tech cases in ~3 seconds.

### 79.1 What stays
- **Per-login tenant scoping** — each sign-in binds to exactly one tenant; single active SQLCipher DB; no concurrent sessions held in memory.
- **Last-used persistence** — Keychain stores last server URL + username (never tokens) so re-login is one tap + biometric.
- **Multiple-servers hint** — Login screen remembers recently-used servers in a chip row for quick pick.
- **Per-tenant push token** — when signing in to a new tenant, previous APNs token unregistered server-side (so pushes don't cross tenants).

### 79.2 What is dropped
- Concurrent per-tenant sessions.
- Top-bar switcher UI.
- "Login all" biometric fan-out.
- Max-5-tenants limit logic.

Sandbox / prod distinction is visual (orange accent) not a switcher (§77.1).

---
## §80. Master design-token table

One source for every hex / size / radius / shadow. Replace scattered numbers. All tokens live in `DesignSystem/Tokens.swift`.

### 80.1 Spacing (pt)
| Token | Value |
|---|---|
| `space.xxs` | 2 |
| `space.xs` | 4 |
| `space.sm` | 8 |
| `space.md` | 12 |
| `space.lg` | 16 |
| `space.xl` | 20 |
| `space.xxl` | 24 |
| `space.xxxl` | 32 |
| `space.huge` | 48 |

### 80.2 Radius (pt)
| Token | Value | Usage |
|---|---|---|
| `radius.xs` | 4 | Small chip |
| `radius.sm` | 8 | Button |
| `radius.md` | 12 | Input field |
| `radius.lg` | 16 | Card |
| `radius.xl` | 24 | Sheet |
| `radius.pill` | 999 | Pill |

### 80.3 Shadow
| Token | y | blur | opacity (dark / light) |
|---|---|---|---|
| `shadow.none` | 0 | 0 | 0 / 0 |
| `shadow.xs` | 1 | 2 | 0.25 / 0.04 |
| `shadow.sm` | 2 | 4 | 0.35 / 0.06 |
| `shadow.md` | 4 | 12 | 0.45 / 0.10 |
| `shadow.lg` | 8 | 24 | 0.55 / 0.14 |

### 80.4 Color (dark theme)
| Token | Hex |
|---|---|
| `surface.base` | `#0B0D10` |
| `surface.raised` | `#15181D` |
| `surface.inset` | `#1C2027` |
| `surface.glass` | `#202228` @ 0.55 alpha |
| `text.primary` | `#F5F7FA` |
| `text.secondary` | `#A8B0BA` |
| `text.muted` | `#6B7380` |
| `text.inverse` | `#0B0D10` |
| `border.subtle` | `#2A2F38` |
| `border.strong` | `#3A4050` |
| `accent.primary` | `#6CA8FF` |
| `accent.success` | `#4FE0A0` |
| `accent.warning` | `#FFCB6C` |
| `accent.danger` | `#FF6C7A` |
| `accent.info` | `#6CD2FF` |

### 80.5 Color (light theme)
| Token | Hex |
|---|---|
| `surface.base` | `#F7F8FA` |
| `surface.raised` | `#FFFFFF` |
| `surface.inset` | `#EEF1F5` |
| `surface.glass` | `#FFFFFF` @ 0.70 alpha |
| `text.primary` | `#0B0D10` |
| `text.secondary` | `#44525F` |
| `text.muted` | `#7A8590` |
| `accent.primary` | `#2E6FF2` |
| `accent.success` | `#108C5A` |
| `accent.warning` | `#B37B10` |
| `accent.danger` | `#C8384B` |

Contrast tested ≥ 4.5:1 on each surface.

### 80.6 Motion
See §67 for timing tokens.

### 80.7 Enforcement
- SwiftLint custom rule bans inline `Color(red:)` / inline CGFloat literals for spacing.
- Exceptions annotated with `// design-exception: ...`.

### 80.8 Typography scale — matches bizarreelectronics.com brand fonts

Revised 2026-04-20 after inspecting the brand website's Google Fonts (Elementor): **Bebas Neue** (condensed display), **League Spartan** (geometric sans accent), **Roboto** (body / UI), **Roboto Mono** (IDs / codes). **Roboto Slab** held in reserve for one-off print / invoice accents. See §30.4 for rationale.

| Style | Size | Font | Weight |
|---|---|---|---|
| largeTitle | 34 | Bebas Neue | regular |
| title1 | 28 | Bebas Neue | regular |
| title2 | 22 | League Spartan | semibold |
| title3 | 20 | League Spartan | medium |
| headline | 17 | Roboto | semibold |
| body | 17 | Roboto | regular |
| callout | 16 | Roboto | regular |
| subheadline | 15 | Roboto | regular |
| footnote | 13 | Roboto | regular |
| caption1 | 12 | Roboto | regular |
| caption2 | 11 | Roboto | regular |
| mono | 14 | Roboto Mono | regular |
| print-accent | — | Roboto Slab | semibold (invoice/receipt headers only) |

- Dynamic Type: all scale. Fixed-size exceptions: POS keypad digits, OCR overlays.
- Tracking: Bebas Neue +0.5–1.0 at ≤20pt, tight at ≥28pt; body line-height 1.4×, caption 1.3×.
- `.monospacedDigit` on counters / totals.
- Weights limited to regular / medium / semibold / bold per face (bundle size).
- `scripts/fetch-fonts.sh` pulls these from Google Fonts (OFL). `UIAppFonts` in `scripts/write-info-plist.sh` lists all TTFs explicitly.
- Wordmark "BIZARRE!" is a vector asset (SVG) in `Assets.xcassets/BrandMark.imageset/`, NOT typed in a font — see §30.4.
- Fallback: missing weight → SF Pro matching size; CI fails release on missing `UIAppFonts` entry.

### 80.9 Semantic colors
- Semantic tokens: `Color.brandAccent`, `.brandDanger`, `.brandWarning`, `.brandSuccess`, `.brandInfo`.
- Surface: `.surfaceBase`, `.surfaceRaised`, `.surfaceInset`, `.surfaceGlass`.
- Text: `.textPrimary`, `.textSecondary`, `.textMuted`, `.textInverse`.
- Border: `.borderSubtle`, `.borderStrong`, `.borderAccent`.
- Asset catalog: `Assets.xcassets/Colors/` holds light + dark variants.
- Tenant accent overlaid via `.tint(tenantAccent)`.
- Increase-contrast mode swaps to 7:1 palette.
- Tenant brand color never overrides semantic danger/success.
- Auto-contrast: pale tenant tint bumps to readable contrast.

---
## §81. API endpoint catalog (abridged, full lives in `docs/api.md`)

| Method | Path | Request | Response | Used by § |
|---|---|---|---|---|
| POST | `/auth/login` | `{email, password}` | `{token, user, tenant}` | §2 |
| POST | `/auth/refresh` | `{refresh_token}` | `{token}` | §2.4 |
| POST | `/auth/logout` | `—` | `204` | §2.6 |
| POST | `/auth/2fa/verify` | `{code}` | `{token}` | §2 |
| GET | `/reports/dashboard` | `—` | `{kpis: [...]}` | §3 |
| GET | `/reports/needs-attention` | `—` | `{items: [...]}` | §3 |
| GET | `/tickets` | `?status,assignee,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §4 |
| GET | `/tickets/:id` | `—` | `Ticket` | §4 |
| POST | `/tickets` | `Ticket` | `Ticket` | §4 |
| PATCH | `/tickets/:id` | `Partial<Ticket>` | `Ticket` | §4 |
| POST | `/tickets/:id/signatures` | `{base64, name}` | `Signature` | §4.5 |
| POST | `/tickets/:id/pre-conditions` | `{...}` | `Ticket` | §4.3 |
| GET | `/customers` | `?query,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §5 |
| POST | `/customers` | `Customer` | `Customer` | §5 |
| POST | `/customers/merge` | `{keep,merge}` | `Customer` | §5 |
| GET | `/inventory` | `?filter,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §6 |
| POST | `/inventory` | `Item` | `Item` | §6 |
| POST | `/inventory/adjust` | `{sku,delta,reason}` | `Movement` | §6 |
| POST | `/inventory/receive` | `{po_id, lines}` | `Receipt` | §6 |
| POST | `/inventory/reconcile` | `{counts}` | `Report` | §6, §39 |
| GET | `/invoices` | `?status,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §7 |
| POST | `/invoices/:id/payments` | `{method, amount}` | `Payment` | §7 |
| POST | `/refunds` | `{invoice_id, lines, reason}` | `Refund` | §4 |
| GET | `/sms/threads` | `?cursor,limit` | `{threads, next_cursor?, stream_end_at?}` | §12 |
| POST | `/sms/send` | `{to, body}` | `Message` | §12 |
| GET | `/appointments` | `?from,to,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §10 |
| POST | `/appointments` | `Appointment` | `Appointment` | §10 |
| GET | `/estimates` | `?cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §8 |
| POST | `/estimates` | `Estimate` | `Estimate` | §8 |
| POST | `/estimates/:id/convert` | `—` | `Ticket` | §8 |
| GET | `/expenses` | `?from,to,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §11 |
| POST | `/expenses` | `Expense` | `Expense` | §11 |
| GET | `/employees` | `?cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §14 |
| POST | `/employees/:id/clock-in` | `{location?}` | `Shift` | §46 |
| POST | `/employees/:id/clock-out` | `—` | `Shift` | §46 |
| GET | `/reports/revenue` | `?from,to,group` | `Chart` | §15 |
| GET | `/reports/inventory` | `?from,to` | `Chart` | §15 |
| GET | `/reports/tax-liability` | `?from,to` | `Report` | §16.6 |
| POST | `/pos/sales` | `Sale` | `Sale` | §16 |
| POST | `/pos/cash-sessions` | `{open_amount}` | `Session` | §39 |
| POST | `/pos/cash-sessions/:id/close` | `{close_amount, notes}` | `Session` | §39 |
| POST | `/payment-links` | `{amount, customer, memo}` | `Link` | §41 |
| GET | `/gift-cards/:code` | `—` | `Card` | §40 |
| POST | `/gift-cards/redeem` | `{code, amount}` | `Card` | §40 |
| POST | `/store-credit/:customerId` | `{amount, reason}` | `Credit` | §40 |
| POST | `/device-tokens` | `{apns_token, model}` | `204` | §21 |
| POST | `/telemetry/events` | `{events[]}` | `204` | §32 |
| POST | `/telemetry/crashes` | `Crash` | `204` | §32 |
| GET | `/sync/delta` | `?since=<updated_at>&cursor=<opaque>&limit` | `{changes[], next_cursor?, stream_end_at?}` | §20.5 |
| POST | `/sync/conflicts/resolve` | `{...}` | `Resolved` | §20.3 |
| GET | `/audit-logs` | `?from,to,actor,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §50 |
| GET | `/feature-flags` | `—` | `{flags}` | §19 |
| POST | `/imports/start` | `{provider, file}` | `Job` | §48 |
| GET | `/imports/:id/status` | `—` | `Job` | §48 |
| POST | `/exports/start` | `{scope}` | `Job` | §49 |
| GET | `/exports/:id/download` | `—` | `File` | §49 |
| GET | `/locations` | `—` | `{data}` | §60 |
| POST | `/locations` | `Location` | `Location` | §60 |
| GET | `/memberships/:id/wallet-pass` | `—` | `.pkpass` | §38 |
| GET | `/public/tracking/:shortId` | `—` | `Tracking` | §53 |
| GET | `/public/book/:locationId` | `—` | `Availability` | §56 |
| POST | `/public/pay/:linkId` | `{token}` | `Payment` | §41 |
| POST | `/comms/email` | `{to, template, vars}` | `Send` | §64 |
| POST | `/comms/sms` | `{to, template, vars}` | `Send` | §12 |

All endpoints return envelope `{ success, data, message }`. All 4xx map to `AppError.server` with `message`.

---
## §82. Phase Definition of Done (sharper, supersedes legacy §79 Phase DoD skeleton)

### 82.1 Phase 0 — Skeleton
DoD:
- xcodegen generates clean project.
- `write-info-plist.sh` + `fetch-fonts.sh` produce Info.plist + fonts.
- App launches on iPhone + iPad + Mac (Designed for iPad).
- Login screen shippable (server URL + email + password + 2FA prompt).
- API envelope unwrapping + base URL swap works.
- Token storage in Keychain.
- Session revocation broadcasts to RootView.

### 82.2 Phase 1 — Read-only parity
DoD:
- All lists (§3-§15) implemented with pagination §65.
- Detail views read-complete.
- Global search (§18).
- Offline cache GRDB read-through.
- Snapshot tests pass.
- VoiceOver traversal smoke passes.
- Phase-1 TestFlight open to internal team.

### 82.3 Phase 2 — Writes + POS first pass
DoD:
- Create / edit / archive flows for tickets / customers / inventory / invoices.
- POS cash tender + BlockChyp card tender.
- Sync queue for offline writes.
- Bug-report form.
- External beta cohort opened.

### 82.4 Phase 3 — Hardware + platform polish
DoD:
- Barcode scan, photo attach, signature capture, thermal printer, cash drawer.
- APNs register, push categories, tap-to-open deep links.
- Widgets + App Intents + Shortcuts.
- Stage Manager + Pencil Pro + Magic Keyboard shortcuts.

### 82.5 Phase 4 — Reports, marketing, loyalty
DoD:
- Charts (§14) with drill-through (§15).
- Marketing campaigns (§37).
- Loyalty engine (§38).
- Memberships (§38).
- Referrals (§37).
- Full accessibility audit clean.

### 82.6 Phase 5 — Scale & reliability
DoD:
- Multi-location, multi-tenant switching.
- SLA visualizer, dead-letter queue, telemetry + crash pipeline (tenant-bound).
- Audit log viewer + chain integrity.
- Public-release App Store submission.

### 82.7 Phase 6 — Regulatory + advanced payment
DoD:
- Tax engine advanced, multi-currency, fiscal periods, rounding rules.
- Tap-to-Pay on iPhone evaluation (decision to ship or defer).
- Apple Wallet passes for memberships + gift cards.
- GDPR / CCPA / PCI evidence package.

### 82.8 Phase 7 — Optional stretch
DoD:
- CarPlay (fleet entitlement approved).
- Watch complications (re-eval gate passed).
- visionOS port (evaluation only).
- AI-assist via on-device WritingTools / GenModel per §2.

### 82.9 Cross-phase gates
- Crash-free sessions ≥ 99.5% before advancing.
- No P0 bugs older than 14d.
- Localization coverage per target locale.
- Documentation updated in same PR as feature.

### 82.10 Per-tenant rollout
- Opt-in beta: 5 tenants first, weekly check-ins.
- General availability once crash-free > 99.5% + Android parity on top 80% of flows.

### 82.11 Kill-switch
- Feature flags ship every feature; toggle server-side per tenant.
- Forced-update gate: server rejects client versions with known data-loss bugs until upgrade.

### 82.12 Migration path
- Android → iOS: user data portable; just log in.
- Web-only → iOS: full sync on first login.
- No data migration needed — server is single source.

---
## §83. Wireframe ASCII sketches per screen

Compact text wireframes — informs Figma without being Figma.

### 83.1 Login (iPhone)
```
┌────────────────────────────┐
│       [brand orbs]         │
│                            │
│       BizarreCRM           │
│                            │
│   ┌──────────────────┐     │
│   │ Server URL       │     │
│   └──────────────────┘     │
│                            │
│   ┌──────────────────┐     │
│   │ Email            │     │
│   └──────────────────┘     │
│                            │
│   ┌──────────────────┐     │
│   │ Password       👁│     │
│   └──────────────────┘     │
│                            │
│   [ Sign in  →] [glass]    │
│                            │
│   Use passkey • Email link │
└────────────────────────────┘
```

### 83.2 Dashboard (iPad landscape)
```
┌─ Sidebar ─────┬─ KPIs ─────────────┬─ Attention ─┐
│ ● Dashboard   │ ┌───┬───┬───┬───┐  │ Low stock   │
│   Tickets     │ │$$ │# │⏱ │★ │  │ ⚠ 3 items  │
│   Customers   │ └───┴───┴───┴───┘  │             │
│   Inventory   │ ┌───┬───┬───┬───┐  │ Past due    │
│   Invoices    │ │   │   │   │   │  │ 💰 2 inv   │
│   SMS         │ └───┴───┴───┴───┘  │             │
│   Reports     │ Today's activity   │ Next appt   │
│   Settings    │ • 14:02 sale $210  │ 15:30 Acme  │
│               │ • 13:48 ticket 488 │             │
└───────────────┴────────────────────┴─────────────┘
```

### 83.3 Ticket detail (iPhone)
```
┌────────────────────────────┐
│ ← Ticket #4821       ⋯     │  ← glass nav
├────────────────────────────┤
│ Acme Corp                  │
│ iPhone 15 Pro · S/N: ...   │
│ [ In Repair ] status pill  │
├────────────────────────────┤
│ Devices                 +  │
│ ▸ iPhone 15 Pro            │
│   IMEI 35...  passcode ●●  │
├────────────────────────────┤
│ Pre-conditions             │
│ ◉ Cracked screen           │
│ ◉ Back dent                │
├────────────────────────────┤
│ Photos                  +  │
│ [📷][📷][📷]               │
├────────────────────────────┤
│ Parts & services           │
│ • Display repair  $180     │
│ • Labor 30m       $50      │
│ • Tax             $18.40   │
│ ────────────────────────   │
│ Total            $248.40   │
├────────────────────────────┤
│ History                    │
│ • 13:42 status → Diagnose  │
├────────────────────────────┤
│ [ Mark Ready ] [ SMS  ]    │
└────────────────────────────┘
```

### 83.4 POS (iPad landscape)
```
┌─ Catalog ──────────────────┬─ Cart ────────────┐
│ Search ___________ [scan]  │ iPhone screen $180│
│ ┌───┬───┬───┬───┐          │ Labor 30m     $50 │
│ │📱 │🔋 │🖥 │📟│          │ ──────────────    │
│ └───┴───┴───┴───┘          │ Sub      $230     │
│ ┌───┬───┬───┬───┐          │ Tax      $18.40   │
│ │   │   │   │   │          │ Total   $248.40   │
│ └───┴───┴───┴───┘          │                   │
│                            │ Customer: Acme ▾  │
│                            │                   │
│                            │ [ Cash ] [ Card ] │
│                            │ [ Apple Pay     ] │
└────────────────────────────┴───────────────────┘
```

### 83.5 SMS thread (iPhone)
```
┌────────────────────────────┐
│ ← Acme Corp          📞 ⋯  │
├────────────────────────────┤
│                            │
│ 💬 Your repair is ready.   │
│                      2:14p │
│                            │
│      Thanks! Picking up    │
│      tomorrow.        2:16p│
│                            │
├────────────────────────────┤
│ ┌──────────────────┐ [✨]  │  ← glass accessory
│ │ Type message...  │ [ ➤ ] │
│ └──────────────────┘       │
└────────────────────────────┘
```

Pattern: every screen gets one ASCII wireframe in `docs/wireframes/`. Keeps a shared picture without a Figma license.

---
## §84. Android ↔ iOS parity table

| Feature | Android | iOS | Gap |
|---|---|---|---|
| Login / server URL | ✅ | ✅ | — |
| 2FA | ✅ | planned | §2 |
| Passkey / WebAuthn | partial | planned | §2 |
| Dashboard | ✅ | ✅ | density modes iOS-only |
| Tickets list | ✅ | ✅ | — |
| Ticket create full | ✅ | partial | §4 |
| Ticket edit | ✅ | planned | — |
| Customers | ✅ | ✅ | — |
| Customer merge | ✅ | planned | §5 |
| Inventory | ✅ | ✅ | — |
| Receiving | ✅ | planned | §6 |
| Stocktake | ✅ | planned | §6 |
| Invoices | ✅ | ✅ | — |
| Payment accept | ✅ | partial | §16 |
| BlockChyp SDK | ✅ | planned | §16.2 |
| Cash register | ✅ | planned | §39 |
| Gift cards | ✅ | planned | §40 |
| Payment links | ✅ | planned | §41 |
| SMS | ✅ | ✅ | — |
| SMS AI reply | ❌ | planned (on-device) | §12 iOS leads |
| Notifications tab | ✅ | ✅ | — |
| Appointments | ✅ | ✅ | — |
| Scheduling engine deep | ✅ | planned | §10 |
| Leads | ✅ | ✅ | — |
| Estimates | ✅ | ✅ | — |
| Estimate convert | ✅ | planned | §9 |
| Expenses | ✅ | ✅ | — |
| Employees | ✅ | ✅ | — |
| Clock in/out | ✅ | planned | §46 |
| Commissions | ✅ | planned | §46 |
| Global search | ✅ | ✅ | — |
| Reports | ✅ | placeholder | §14 |
| BI drill | partial | planned | §15 |
| POS checkout | ✅ | placeholder | §16 |
| Barcode scan | ✅ | planned | §17.2 |
| Printer thermal | ✅ | planned | §17 |
| Label printer | ❌ | planned | §17 |
| Cash drawer | ✅ | planned | §17 |
| Weight scale | ❌ | planned | §17 |
| Customer-facing display | ❌ | planned | §16 |
| Offline mode | ✅ | planned | §20 |
| Conflict resolution | ❌ | planned | §20.6 |
| Widgets | ❌ | planned | §24 |
| App Intents / Shortcuts | ❌ | planned | §24 |
| Live Activities | n/a | planned | §24 |
| Apple Wallet passes | n/a | planned | §41 |
| Handoff / Continuity | n/a | planned | §25 |
| Stage Manager 3-col | n/a | planned | §22 |
| Pencil annotation | n/a | planned | §4 |
| CarPlay | n/a | deferred | §73 |
| SSO | ✅ | planned | §2 |
| Audit log | ✅ | planned | §50 |
| Data import wizard | ✅ | planned | §48 |
| Data export | ✅ | planned | §49 |
| Multi-location | ✅ | planned | §60 |

Legend: ✅ shipped · partial · planned · deferred · n/a.

### 84.1 Review cadence
- Monthly: Android lead + iOS lead reconcile gaps.
- Track burn-down.

### 84.2 Parity test
- Shared behavior spec per feature (Gherkin scenarios) — both platforms must pass.
- Lives in `packages/shared/spec/`.

---
## §85. Web ↔ iOS parity table

| Feature | Web | iOS | Gap |
|---|---|---|---|
| Login | ✅ | ✅ | — |
| Dashboard | ✅ | ✅ | charts richer on web currently |
| Tickets CRUD | ✅ | partial | iOS needs ticket edit |
| Customers CRUD | ✅ | partial | iOS needs customer edit |
| Inventory CRUD | ✅ | partial | iOS needs create |
| Invoices CRUD + pay | ✅ | partial | iOS needs invoice payment |
| POS | partial | planned | web runs POS lightly; iOS targets full |
| SMS | ✅ | ✅ | — |
| Marketing campaign builder | ✅ | planned | §37 |
| Reports builder | ✅ | planned | §15 |
| Settings comprehensive | ✅ | subset | §19.2 |
| Tenant admin destructive ops | ✅ | by-design web-only | §19.4 |
| Waivers PDF | ✅ | planned | §4 |
| Quote e-sign | ✅ | planned | §8 |
| Public tracking page | ✅ | n/a (web-served) | §53 |
| Public pay link | ✅ | n/a (web-served) | §41 |
| Self-booking | ✅ | n/a (web-served) | §56 |
| Audit log | ✅ | planned | §50 |
| Data import | ✅ | planned | §48 |
| Data export | ✅ | planned | §49 |
| Integrations config | ✅ | view-only | §19.2 |
| Receipt template editor | ✅ | planned | §64 |

### 85.1 iOS's unique edges
- Apple Wallet passes.
- Apple Pay / Tap-to-Pay.
- Camera-native barcode / document scan.
- BlockChyp mobile terminal tethering.
- Dynamic Island / Live Activities.
- Siri / App Intents / Shortcuts.
- Widgets / Lock Screen.
- Handoff / Universal Clipboard.
- Pencil annotation.

### 85.2 Web's edges
- Keyboard-heavy admin workflows (though iPad with Magic Keyboard narrows gap).
- Complex report builder (iOS can match but low ROI).
- Tenant superadmin tools.

### 85.3 Decision
- iOS targets daily operational tasks + point-of-sale.
- Web keeps admin / marketing / complex reporting.
- Sync guaranteed both directions.

---
## §86. Server capability map

### 86.1 Categories
- Auth — login / 2FA / passkey / sessions / refresh.
- Data — CRUD on all entities.
- Sync — delta, conflicts, idempotency.
- Files — upload, download, metadata.
- Payment — BlockChyp bridge, gift card, store credit, links.
- Comms — SMS, email, push.
- Reports — aggregated queries.
- Marketing — campaigns, segments, sends.
- Billing — tenant subscription, usage.
- Admin — users, roles, locations, tenant settings.
- Public — tracking, booking, pay pages.
- Integrations — webhooks, Zapier, SSO.
- Telemetry — events, crashes, metrics.
- Audit — immutable log.
- Files / PDFs — generated.

### 86.2 Per capability
- Endpoint(s) in §81.
- Required for iOS feature X.
- Status (ready / in progress / not yet).

### 86.3 Gap tracker
- Live spreadsheet in `docs/server-gaps.csv`.
- Each iOS feature PR checks capability status before merge.

### 86.4 Coordination
- iOS lead weekly sync with server lead.
- Shared Linear / Jira project.

---
## §87. DB schema ERD (text)

```
┌──────────┐  1   ┌──────────┐  1   ┌──────────┐
│ Tenant   │──────│ User     │──────│ Shift    │
└──────────┘    N └──────────┘    N └──────────┘
     │1
     │N
┌──────────┐  N   ┌──────────┐  N   ┌──────────┐
│ Customer │──────│ Ticket   │──────│ Device   │
└──────────┘    N └──────────┘    N └──────────┘
     │1           │1         │1
     │N           │N         │N
┌──────────┐  ┌─────────┐ ┌─────────────┐
│ Invoice  │  │ Photo   │ │ Signature   │
└──────────┘  └─────────┘ └─────────────┘
     │1
     │N
┌──────────┐
│ Payment  │
└──────────┘

┌──────────┐  N   ┌─────────────┐
│ InvItem  │──────│ Movement    │
└──────────┘      └─────────────┘
     │N               │N
     │                │
┌──────────┐      ┌─────────┐
│ Vendor   │      │ POLine  │
└──────────┘      └─────────┘

┌──────────┐  1   ┌──────────┐
│Appointment│─────│ Customer │
└──────────┘      └──────────┘

┌──────────┐  N   ┌──────────┐
│ SMSThread│──────│ Customer │
└──────────┘      └──────────┘
     │1
     │N
┌──────────┐
│SMSMessage│
└──────────┘
```

### 87.1 Row-level security
- Every row has `tenant_id` column.
- Server policy: queries always filtered by tenant_id from auth token.

### 87.2 Indexes
- Customer: (tenant_id, phone), (tenant_id, email), (tenant_id, name).
- Ticket: (tenant_id, status), (tenant_id, assignee), (tenant_id, updated_at desc).
- Invoice: (tenant_id, status), (tenant_id, customer_id).
- Movement: (tenant_id, sku, created_at).

### 87.3 Soft delete
- `deleted_at` nullable on most entities.
- Queries default to WHERE deleted_at IS NULL.

### 87.4 Versioning
- `version_hash` for optimistic concurrency on Ticket / Invoice / Customer.

### 87.5 Foreign keys
- Strict FK constraints server-side.
- iOS relies on server to enforce; client validates optimistically.

---
## §88. State diagrams per entity

### 88.1 Ticket
```
Intake → Diagnostic → Awaiting Approval → Awaiting Parts → In Repair → QC → Ready → Completed → Archived
  │           │              │                 │              │         │       │
  │           ▼              ▼                 ▼              ▼         ▼       ▼
  └──► Cancelled                                                        └──► Warranty Return
                                                                              (loops back to In Repair)
```
Rules from §4.

### 88.2 Invoice
```
Draft → Sent → Partial Paid → Paid → Closed
  │       │         │           │
  ▼       ▼         ▼           ▼
Void    Overdue  Overdue     Refunded
```

### 88.3 POS Sale
```
Empty cart → Building → Ready to tender → Charging → Approved → Receipt → Closed
                                              │
                                              ▼
                                           Declined → back to Ready
```

### 88.4 Employee shift
```
Off → Clocked in → On break → Clocked in → Clocked out
                     │
                     └── (loop)
```

### 88.5 Appointment
```
Booked → Confirmed → Checked in → In service → Completed
            │           │            │
            ▼           ▼            ▼
        Cancelled   No-show      Cancelled
```

### 88.6 Sync queue item
```
Queued → Sending → Sent → Acknowledged
  │         │        │
  │         ▼        ▼
  │      Retrying  Conflict → Resolved
  │         │
  └─────► Dead-letter
```

Format: render `docs/state-diagrams/` with mermaid for web doc; ASCII kept here for terminal accessibility.

---
## §89. Architecture flowchart

```
┌─────────────┐                    ┌────────────────────┐
│  UI Layer   │  SwiftUI Views     │   Scene / Window   │
│  (@Observable│───────────────────│  (NavigationSplit)│
│   ViewModel) │                    └────────────────────┘
└─────────────┘
     │
     ▼
┌─────────────┐      ┌──────────────┐      ┌───────────┐
│ Repository  │◄────►│  GRDB cache  │      │  Factory   │
│ (domain)    │      │  (SQLCipher) │      │    DI      │
└─────────────┘      └──────────────┘      └───────────┘
     │
     ▼
┌─────────────┐      ┌──────────────┐
│  APIClient  │◄────►│  PinnedURL   │
│  (envelope) │      │  Session     │
└─────────────┘      └──────────────┘
     │
     ▼
┌────────────────────────────┐
│  Tenant Server             │
│  - app.bizarrecrm.com      │
│  - or self-hosted tenant    │
└────────────────────────────┘
     ▲
     │ (telemetry / crashes / webhooks — all here)
     │
┌────────────────────────────┐
│  iOS client is the only    │
│  network peer. No third-    │
│  party SaaS egress.        │
└────────────────────────────┘
```

### 89.1 Supporting modules
- Widgets target → read-only App Group DB.
- App Intents target → read + limited write.
- Extensions (share / push-action) → thin wrappers around Core.

### 89.2 Data flow
- User action → ViewModel intent → Repository → (cache read + network call) → state update → view redraw.
- Writes: optimistic UI → Repository → APIClient → on success confirm + audit log → on failure enqueue + revert UI if needed.

### 89.3 Concurrency
- Swift structured concurrency everywhere.
- Actors per Repository.
- No GCD raw calls outside low-level delegates.

---
## §90. STRIDE threat model (summary)

| Threat | Example | Mitigation |
|---|---|---|
| **S**poofing | Attacker logs in as staff | Strong auth + 2FA + passkey; device binding |
| **T**ampering | Altered API response | HTTPS + optional SPKI pin; envelope checksum |
| **R**epudiation | Staff denies action | Audit log with chain integrity §50.5 |
| **I**nformation disclosure | Token leaked | Keychain + biometric gate; never in logs |
| **D**enial of service | Flood endpoints | Server rate-limit; client limit §1 |
| **E**levation of privilege | Cashier becomes admin | Server authoritative RBAC; client double-check |

### 90.1 Specific risks
- **Stolen device** — Keychain wipes on passcode-disable; remote sign-out §17.3.
- **Shoulder surf** — PIN mask + blur on background.
- **Malicious coworker** — audit trail + role scoping + duress codes (future).
- **Server compromise** — SPKI pin optional; tenant-side IR (§34).
- **Push phishing** — Apple APNs trust chain; no deep links from external pushes.
- **MITM on hotel Wi-Fi** — ATS + optional pin; VPN recommended.
- **SIM swap** — 2FA TOTP / passkey preferred over SMS.
- **Pasteboard sniff** — Pasteboard access audit + clear on sensitive ops.
- **Screenshot leak** — blur sensitive screens + audit log §28.

### 90.2 Review cadence
- Quarterly sec-review with security-reviewer agent + human.
- Post-incident: update threat model.

---

---

> **This document is intended as a living plan.** Close items by flipping `[ ]` → `[x]` with a commit SHA. Add sub-items freely. Keep the "What changed" section at the bottom for posterity.

## Changelog

- 2026-04-19 — Initial skeleton by iOS-parity audit. Waiting on inventory reports from web / Android / server / current-iOS / management sub-agents to refine each section.
- 2026-04-19 (update) — Expanded all 35 existing sections with full fidelity (backend endpoints, frontend surfaces, expected UX per item). Added §1 data-sovereignty principle + §32 egress allowlist. Appended sections §36–§65 covering Setup Wizard, Marketing, Memberships, Cash Register detail, Gift Cards, Payment Links, Voice/CallKit, Bench Workflow, Device Templates, CRM Health, Warranty, Team Chat, Goals/Reviews/PTO, Role Matrix, Data Import/Export, Audit Logs, Training Mode, Command Palette, Public Tracking, TV Board, Kiosk Modes, Self-Booking, Field Service, Stocktake, POs, Financial Dashboard, Multi-Location, Release checklist, Non-goals.
- 2026-04-19 (update 2) — Appended §82–§90 covering CarPlay, visionOS stretch, Server API gap analysis, Tickets deep-drill (pricing calc, photo annotation, pre-conditions UX, signature, status history), Per-screen wireframe outlines, Test fixtures catalog, SMS AI-assist via on-device WritingTools, Inventory cycle-count deep UX, Control Center / Dynamic Island stages.
- 2026-04-19 (update 3) — Appended §91–§100: ~~Customer-facing app variant~~ (removed), Staff training walkthrough, Error recovery patterns, Network engine internals, Crash recovery, App Store assets, TestFlight rollout plan, Accessibility QA scripts, Performance budgets detailed, Final micro-interactions polish.
- 2026-04-19 (post-update 3) — Removed §91 Customer-facing app variant per direction. BizarreCRM remains staff-only; customers interact via web + Apple Wallet + SMS + email only. Section number preserved as deprecation marker so downstream references stay stable.
- 2026-04-19 (update 4) — Appended §101–§110: Feature-flag system, Tenant onboarding email templates, Debug drawer, Offline-first data viewer, Notification channel management per iOS, Deep-link handoff between web+android+iOS, Analytics event naming conventions, Sandbox vs prod tenant switching, Local dev mock server, Accessibility labels catalog.
- 2026-04-19 (update 5) — Appended §111–§120: Camera stack details, Voice memos attach, Inventory receiving workflow, Label / shelf-tag printing, Re-order suggestion engine, Tax engine deep-dive, Loyalty engine deep-dive, Referral program, Commissions, Cash-flow forecasting.
- 2026-04-19 (update 6) — Appended §121–§130: Ticket templates & macros, Vendor management, Asset / loaner tracking, Scheduling engine, Message templates, Digital consents & waivers, Marketing campaigns, Recurring services & subscriptions, Service bundles & packages, On-device search indexer.
- 2026-04-19 (update 7) — Appended §131–§140: Ticket state machine, Returns & RMAs, Quote e-sign, Image annotation detail, Dead-letter queue viewer, DB schema migration strategy, In-app bug-report form, In-app changelog viewer, Privacy-data-subject requests, Apple Pay wallet integration details.
- 2026-04-19 (update 8) — Appended §141–§150: Location manager & geofencing, Background tasks catalog, WKWebView policy, Image caching & CDN, Automated a11y audits, DI architecture, Error taxonomy, Logging strategy, Build flavors / configs, Certificates & provisioning.
- 2026-04-19 (update 9) — Appended §151–§160: Siri & App Intents deep, Focus Modes integration, Multi-window / Stage Manager deep, watchOS companion re-scope, iPhone Mirroring & Continuity Camera, Print engine deep, Haptic custom patterns, Screen capture / screenshot consent, Color token system, Typography scale.
- 2026-04-19 (update 10) — Appended §161–§170: Micro-copy style guide, First-empty-tenant UX, Ticket quick-actions, Keyboard handling, Toast / banner system, Confirm-sheet patterns, Destructive gesture ergonomics, Undo/redo framework, Multi-select UX, Drag & drop within + across apps.
- 2026-04-19 (update 11) — Appended §171–§180: Clipboard patterns, Inline editing, Inline validation deep, Responsive grid, Lazy image loading, Scroll perf, List virtualization, Glass elevation layers, Sidebar widths, Settings search.
- 2026-04-19 (update 12) — Appended §181–§190: Shake gestures, Spatial audio, Kiosk dimming, Battery-saver mode, Thermal throttling, Quiet-mode haptics, Customer-facing display layouts, Shift reports UI, End-of-day wizard, Open-shop checklist.
- 2026-04-19 (update 13) — Appended §191–§200: App lifecycle deep, Data model / ERD, SwiftData-vs-GRDB decision, Backup & restore, Tenant ownership handoff, Staff hiring & offboarding, Job-posting integration, iPad Pro M4-specific features, Widgets deep, Notifications UX polish.
- 2026-04-19 (update 14) — Appended §201–§210: Barcode formats catalog, IMEI check / blacklist, QR tracking labels, Open-hours & holiday calendar, Staff chat deep, Role matrix deep, Sticky a11y tips, Customer portal link surface, Email templates deep, Webhooks & integrations.
- 2026-04-19 (update 15) — Appended §211–§220: POS keyboard shortcuts, Gift receipt, Reprint flow, Discount engine, Coupon codes, Pricing rules engine, Membership renewal reminders, Dunning, Late fees, BNPL evaluation.
- 2026-04-19 (update 16) — Appended §221–§230: Warranty claim flow, SLA tracking, QC checklist, Batch & lot tracking, Serial number tracking, Inter-location transfers, Reconciliation, Damage / scrap bin, Dead-stock aging, Reorder lead times.
- 2026-04-19 (update 17) — Appended §231–§240: Tenant admin tools, Per-tenant feature flags UI, Multi-tenant user session mgmt, Shared-device mode, PIN quick-switch, Session timeout, Remember-me, 2FA enrollment, 2FA recovery codes, SSO / SAML.
- 2026-04-19 (update 18) — Appended §241–§250: Audit log viewer deep, Activity feed, Tenant BI, Custom dashboards per role, Goals widget, Leaderboards, Gamification guardrails, Employee scorecards, Peer feedback, Recognition cards.
- 2026-04-19 (update 19) — Appended §251–§260: Customer tags & segments, Customer 360, Merge & dedup, Preferred comms channel, Birthday automation, CSAT + NPS, Complaint tracking, Punch-card loyalty, Referral tracking deep, Review solicitation.
- 2026-04-19 (update 20) — Appended §261–§270: Customer notes deep, Files cabinet, Document scanner deep, Contacts import, Magic-link login, Passkey login, WebAuthn, Sheet keyboard avoidance, Diagnostic exporter, On-device ML perf notes.
- 2026-04-19 (update 21) — Appended §271–§280: Hardware key inventory, Terminal pairing UX, Network config wizard, Static-IP printers, Bonjour discovery, Bluetooth device mgmt, Peripheral reconnect, Firmware update prompts, Weight scale, Cash drawer trigger.
- 2026-04-19 (update 22) — Appended §281–§290: Ticket labels, Estimate versioning, ID / numbering formats, Fiscal periods, Multi-currency, Rounding rules, Currency display per-customer, Template versioning, Dynamic price displays, Clock-drift guard.
- 2026-04-19 (update 23) — Appended §291–§300: Dashboard density modes, Glass strength levels, Sound design catalog, Brand mark usage, Onscreen keyboard autolayout, iPadOS Magnifier gesture support, Apple Watch complications re-eval, App Review checklist, Crisis playbook, Docs + developer handbook.
- 2026-04-19 (update 24) — Appended §301–§310: Ticket SLA visualizer, Drill-through reports, Dashboard redesign gates, Theme gallery, Tenant branding upload, Loading skeletons deep, Animation timing scale, Keyboard-only operation test, Pairing printers with peripherals, POS offline queue with idempotency.
- 2026-04-19 (update 25) — Appended §311–§320: Master token table, API endpoint catalog, Phase DoD sharper, Wireframe ASCII sketches, Copy deck, SF Symbol audit, A/B test harness, Client rate-limiter, Draft recovery UI, Keyboard shortcut overlay.
- 2026-04-19 (update 26) — Appended §321–§330: Apple Wallet pass designs, PDF templates, Push copy deck, Shortcuts gallery, Spotlight scope, URL-scheme handler, Localization glossary, RTL rules, Our uptime SLA, Incident runbook index.
- 2026-04-19 (update 27) — Appended §331–§340: Android↔iOS parity table, Web↔iOS parity table, Server capability map, DB schema ERD, State diagrams, Architecture flowchart, STRIDE threat model, Perf bench harness, Synthetic demo data, Battery bench per screen.
- 2026-04-19 (update 28) — Merged duplicates. §79→§313, §157→§69, §159+§160→§311, §205→§47, §206→§49, §241→§52, §259→§118, §297→§154. Deprecated numbers kept as pointer stubs so link integrity holds. See `ios/agent-ownership.md` for the canonical list.
- 2026-04-20 (update 29) — Consolidated §§100+ stubs into target §§1-75; deleted 218 stub bodies. Absorbed cross-referenced actionable bullets into their primary target sections without attribution tags. §§77-340 non-whitelist sections removed. File shrunk from 9151 to ~6700 lines; 90 H2 headings remain (75 core + 15 appendix/reference).
- 2026-04-20 (update 30) — Renumbered §§1-90 sequentially; converted all headings to `## §N.` format; swept all inline cross-refs across ActionPlan.md + agent-ownership.md (TODO.md had no §N refs). Invalid refs pointing at deleted sections were remapped per the update-28/29 absorption trail to their surviving target sections; zero unresolved flags remaining. TOC rebuilt against new numbering.
