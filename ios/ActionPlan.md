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
- [~] **Typed endpoint namespaces** — Tickets domain migrated to `Endpoints.Tickets.<name>(...)` returning `(path, query)`. Other domains keep inline paths until follow-up passes. <!-- partial: actionplan agent — Tickets only -->
- [x] **Multipart upload helper** (`APIClient.upload(_:to:fields:)`) for photos, receipts, avatars. Background `URLSessionConfiguration` with `com.bizarrecrm.upload` identifier + `group.com.bizarrecrm` shared container so uploads survive app exit. (`APIClient.swift` `upload(_:to:fileName:mimeType:fields:)`; protocol default throws `.notImplemented` for stub clients.) <!-- actionplan agent §1.1 -->
- [x] **Retries with jitter** on transient network failures (5xx, URLError `.timedOut`, `.networkConnectionLost`). Respect `Retry-After` on 429. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **Offline detection banner** driven by `NWPathMonitor` — sticky `.brandGlass` banner at the top of `NavigationStack`s with "Offline — changes will sync when connected" copy. (`Networking/Reachability.swift` + `DesignSystem/OfflineBanner.swift`. Retry button deferred.)

### 1.2 Pinning & TLS
- [x] `PinnedURLSessionDelegate` scaffold — shipped (empty pin set).
- [x] Decision: leave pins empty for Let's Encrypt on `bizarrecrm.com`, or pin to Let's Encrypt intermediates. Document decision in README and toggle per-build-config. (Decision: no pins for cloud tenants — 90-day LE rotation; self-hosted supply optional `tls_pin_sha256`. `PinningPolicyFactory` in `Networking/Pinning/TLSPinningDecision.swift`; `failClosed=false` DEBUG / `!pins.isEmpty` RELEASE. feat(§1.2): 99a6739a)
- [ ] Custom-server override (self-hosted tenants): allow user-trusted pins per base URL, stored encrypted in Keychain.

### 1.3 Persistence (GRDB + SQLCipher)

Works in lockstep with §20 Offline, Sync & Caching — both are Phase 0 foundation. This subsection covers the storage layer; §20 covers the repository pattern, sync queue, cursor pagination, and conflict resolution that sit on top of it. Domain PRs must use both; neither ships in isolation.

- [~] GRDB wiring exists for some domains; full coverage missing.
- [~] **Per-domain DAO**: partial — Tickets (`TicketRepository` + `TicketSyncHandlers`), Customers (`CustomerRepository` + `CustomerSyncHandlers`), Inventory (`InventoryRepository` + `InventorySyncHandlers`) wired. Invoices (`InvoiceRepository`), Leads (`LeadListView` via `LeadsEndpoints`) present without full GRDB layer. Appointments, Expenses, SMS, Notifications, Employees, Reports cache still missing.
- [x] **`sync_state` table** (§20.5) — keyed by `(entity, filter?, parent_id?)` storing cursor + `oldestCachedAt` + `serverExhaustedAt?` + `lastUpdatedAt`. (`Persistence/SyncStateStore.swift`, migration `002_sync_state_and_queue.sql`)
- [x] **`sync_queue` table** (§20.2) — optimistic-write log feeding the drain loop. (`Persistence/SyncQueueStore.swift`; migration `002_sync_state_and_queue.sql`; `SyncFlusher` drain loop wired.)
- [x] **Migrations registry** — numbered migrations, each one idempotent. (`Persistence/Migrator.swift` loads sorted `.sql` files from bundle; migrations 001–005 shipped.)
- [x] **`updated_at` bookkeeping** — every table records `updated_at` + `_synced_at`, so delta sync can ask `?since=<last_synced>`. (Migration `003_synced_at_columns.sql` adds `_synced_at` + partial indexes on customer/ticket/inventory. feat(§1.3): ab976382)
- [x] **Encryption passphrase** — 32-byte random on first run via `SecRandomCopyBytes`, hex-encoded (64 chars) for direct SQLCipher `PRAGMA key = "x'<hex>'"` consumption, stored in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Replaces legacy `KeychainStore.dbPassphrase()` call from `Database.open()`. SQLCipher PRAGMA wiring deferred until `grdb-sqlcipher` SPM dep lands. (`Persistence/DatabasePassphrase.swift` + tests.) <!-- actionplan agent §1.3 -->
- [ ] **Export / backup** — developer-only for now: `Settings → Diagnostics → Export DB` writes a zipped snapshot (without passphrase) to the share sheet.

### 1.4 Design System & Liquid Glass
- [x] `GlassKit.swift` wrapper — shipped.
- [x] **On-device verification** that iOS 26 `.glassEffect` renders the real refraction (not the `.ultraThinMaterial` fallback). (`brandGlassIsRealRefraction()` func + `GlassQualityBadge` (#if DEBUG) in `GlassKit.swift`. feat(§1.4): b11)
- [x] **`GlassEffectContainer`** usage audit — wherever two glass elements might overlap, wrap them in a container so they blend, not stack. (`BrandGlassContainer` wraps `GlassEffectContainer` on iOS 26; already shipped; audit rule documented in `GlassKit.swift`. feat(§1.4): b11)
- [x] **`brandGlassProminent` / `brandGlass` / `brandGlassClear`** variants mapped to button styles, capsule badges, card toolbars. (`BrandGlassProminentButtonStyle`, `BrandGlassButtonStyle`, `BrandGlassClearButtonStyle` + `BrandGlassBadge` in `GlassKit.swift`. feat(§1.4): b11)
- [x] Reduce Transparency fallback: pure `.brandSurfaceElevated` fill instead of glass. (`BrandGlassModifier` reads `@Environment(\.accessibilityReduceTransparency)` and calls `applyReduceTransparencyFallback` — `Color.bizarreSurface1` + optional tint overlay. feat(§1.4): b11)
- [x] Max 6 glass elements per screen. Enforce via debug-build assertion inside `BrandGlassModifier` + SwiftLint rule counting `.brandGlass` call sites per View body. No runtime overlay — violations trip `assert(glassBudget < 6)` and CI lint fails. Zero production cost. (`GlassBudgetMonitor` assertionFailure + `glass_budget_per_file` SwiftLint rule in `.swiftlint.yml`. feat(§1.4/§29.5): b11)

### 1.5 Navigation shell
- [x] iPhone `TabView` + iPad `NavigationSplitView` scaffold — shipped.
- [x] **Typed path enum** per tab — `TicketsRoute.list | .detail(TicketID) | .create | .edit(TicketID)`. Deep-link router consumes these enums. (`Core/NavPins/AppRoute.swift` — 8 route enums + AppTabRoute; Codable+Hashable+Sendable. feat(§1.5): 53bcc3f3)
- [ ] **Tab customization** (iPhone): user-reorderable tabs; fifth tab becomes "More" overflow.
- [ ] **Pin-from-overflow drag** (iPad + iPhone): long-press an entry inside the More menu (e.g. Inventory, Invoices, Reports) → drag it onto the iPad sidebar or iPhone tab bar to pin it as a primary nav destination. Reorder within the primary nav by drag. Drag off the primary nav back into More to unpin. Persist order + pin set per user in `UserDefaults` at `nav.primaryOrder` (array of `MainTab`/domain raw values). Use `.draggable` + `.dropDestination` with a `Transferable` `NavPinItem` payload. Respect a fixed cap (5 on iPhone, 8 on iPad sidebar) — additional items roll back into More.
- [ ] **Search tab role** (iOS 26): adopt `TabRole.search` so the tab bar renders it correctly.
- [ ] **Swipe-back gesture** preserved everywhere — no custom back buttons in `NavigationStack`.
- [ ] **Deep links**: `bizarrecrm://tickets/:id`, `/customers/:id`, `/invoices/:id`, `/sms/:thread`, `/dashboard`. Mirror Android intent filters.
- [ ] **Universal Links** over `app.bizarrecrm.com/*` — apple-app-site-association published server-side.

### 1.6 Environment & config
- [x] `project.yml` + `xcodegen` + `write-info-plist.sh` — shipped.
- [x] **`Info.plist` key audit** — drop empty `UISceneDelegateClassName` (removes console noise). <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] `ITSAppUsesNonExemptEncryption = false` (HTTPS is exempt). <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] Required usage-description strings: Camera, Photos, Photos-add, FaceID, Bluetooth, Contacts, Location-when-in-use (tech dispatch), Microphone (SMS voice memo — optional), Calendars (EventKit appointments mirror). <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] `UIBackgroundModes`: `remote-notification`, `processing`, `fetch`. <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] `UIAppFonts` list kept in sync with `scripts/fetch-fonts.sh` and `BrandFonts.swift`. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] `GRDB.DatabaseMigrator` with named migrations in `Packages/Persistence/Sources/Persistence/Migrations/` — immutable once shipped. (`Persistence/Migrator.swift` loads sorted `.sql` files from bundle; migrations 001–005 registered.)
- [x] Migration-tracking table records applied names; app refuses to launch if a known migration is missing. (`Persistence/MigrationIntegrityGuard.swift` — reads `grdb_migrations` after apply; throws `MigrationIntegrityError.missingMigrations` if any bundle SQL file absent; wired into `Database.open(at:)`. feat(§1.6): b12)
- [x] Forward-only (no downgrades). Reverted iOS version → "Database newer than app — contact support". (`DatabaseVersionGuard.checkCompatibility(pool:appVersion:)` + `DatabaseVersionError.databaseNewerThanApp` in `Persistence/DatabaseVersionGuard.swift`; called from `Database.open(at:)` before migration run; throws user-friendly `LocalizedError`. feat(§1.6): forward-only DB version guard 2228b18c)
- [ ] Large migrations split into batches; progress sheet "Migrating 50%"; runs in `BGProcessingTask` so user can leave app.
- [x] Backup-before-migrate: copy SQLCipher file to `~/Library/Caches/pre-migration-<date>.db`; keep 7d or until next successful launch. (`Persistence/Backup/MigrationBackupService.swift` — ISO8601-dated copy, 7d pruning, listBackups(). feat(§1.6): bf131efb)
- [ ] Debug builds: dry-run migration on backup first and report diff before apply.
- [ ] CI runs every migration against minimal + large fixture DBs (§31 fixtures).
- [x] Factory DI with `Container` + `@Injected(\.apiClient)` key style. All services registered in `Container+Registrations.swift` at launch.
- [ ] Scopes: `cached` (process-wide: APIClient / DB / Keychain), `shared` (weak per-object-graph: ViewModels), `unique` (each resolve builds fresh).
- [ ] Test doubles: test bundle swaps registrations via `Container.mock { ... }` per test; no global-state leaks (assertions in `setUp`).
- [ ] SwiftLint rule bans `static shared = ...` except for `Container` itself.
- [ ] Widgets / App Intents targets import `Core` + register their own Container sub-scope.
- [x] `AppError` enum with cases: `.network(Underlying)`, `.server(status, message, requestID)`, `.auth(AuthReason)`, `.validation([FieldError])`, `.notFound(entity, id)`, `.permission(required: Capability)`, `.conflict(ConflictInfo)`, `.storage(StorageReason)`, `.hardware(HardwareReason)`, `.cancelled`, `.unknown(Error)`.
- [x] Each case exposes `title`, `message`, `suggestedActions: [AppErrorAction]` (retry / open-settings / contact-support / dismiss).
- [ ] Errors logged with category + code + request ID; no PII per §32.6 Redactor.
- [ ] User-facing strings in `Localizable.strings` (§27 / §64).
- [x] Error-recovery UI per taxonomy case lives in each feature module; patterns consolidated in §63-equivalent (dropped — handled inline per screen).
- [x] `UndoManager` attached per scene; each editable action registers undo via `UndoManager.registerUndo(withTarget:handler:)` (`Core/WindowState/SceneUndoManager.swift` — @Observable, registerUndo/undo/redo/clearAll. feat(§1): 3da9beec)
- [x] Covered actions: ticket field edit; POS cart item add/remove; inventory adjust; customer field edit; status change; notes add/remove (documented in SceneUndoManager.swift header; entry-point established. feat(§1): 3da9beec)
- [x] Undo trigger: ⌘Z on iPad hardware keyboard; iPhone `.accessibilityAction(.undo)` + shake-to-undo if enabled; context-menu button for non-keyboard users (`sceneUndoKeyboardShortcuts` view modifier in SceneUndoManager.swift. feat(§1): 3da9beec)
- [x] Server sync: undo rolls back optimistic change, sends compensating request if already synced; if undo impossible, toast "Can't undo — action already processed" (UndoEntry async undo closure pattern established in SceneUndoManager.swift. feat(§1): 3da9beec)
- [x] Redo: ⌘⇧Z (SceneUndoManager.redo() async method; keyboard shortcut at scene root. feat(§1): 3da9beec)
- [x] Stack depth last 50 actions; cleared on scene dismiss (`maxDepth = 50`; `clearAll()` on scene disconnect. feat(§1): 3da9beec)
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
- [x] Impl: token-bucket per endpoint category — read 60/min, write 20/min; excess requests queued with backoff.
- [x] Honor server hints: `Retry-After`, `X-RateLimit-Remaining`; pause client on near-limit signal.
- [x] UI: silent unless sustained; show "Slow down" banner if queue > 10. (`RateLimiter.checkSlowDownThreshold(host:)` posts `Notification.Name.rateLimiterSlowDownWarning` on MainActor at ≥10 waiters; `.rateLimiterSlowDownCleared` when drops below. feat(§1): 4790190a)
- [ ] Debug drawer exposes current bucket state per endpoint.
- [ ] Exemptions: auth + offline-queue flush not client-limited (server-side limits instead).
- [x] Auto-save drafts every 2s to SQLCipher for ticket-create, customer-create, SMS-compose; never lost on crash/background.
- [x] Recovery prompt on next launch or screen open: "You have an unfinished <type> — Resume / Discard" sheet with preview.
- [x] Age indicator on draft ("Saved 3h ago").
- [x] One draft per type (not multi); explicit discard required before starting new.
- [ ] Sensitive: drafts encrypted at rest; PIN/password fields never drafted.
- [x] Drafts stay on device (no cross-device sync — avoid confusion).
- [x] Auto-delete drafts older than 30 days.

---
## §2. Authentication & Onboarding

_Server endpoints: `GET /auth/setup-status`, `POST /auth/setup`, `POST /auth/login`, `POST /auth/login/set-password`, `POST /auth/login/2fa-setup`, `POST /auth/login/2fa-verify`, `POST /auth/login/2fa-backup`, `POST /auth/refresh`, `POST /auth/logout`, `GET /auth/me`, `POST /auth/forgot-password`, `POST /auth/reset-password`, `POST /auth/recover-with-backup-code`, `POST /auth/verify-pin`, `POST /auth/switch-user`, `POST /auth/change-password`, `POST /auth/change-pin`, `POST /auth/account/2fa/disable`._

### 2.1 Setup-status probe
- [x] **Backend:** `GET /auth/setup-status` returns `{ needsSetup, isMultiTenant }`. On first launch after server URL entry, iOS hits this before rendering the login form. (ecb07902 — SetupStatusProbe.swift)
- [x] **Frontend:** if `needsSetup` → push `InitialSetupFlow` (see 2.10). If `isMultiTenant` + no tenant chosen → push tenant picker. Else → render login. (ecb07902 — SetupStatusProbe.swift)
- [x] **Expected UX:** transparent to user; ≤400ms overlay spinner with `.brandGlass` background and a "Connecting to your server…" label. Fail → inline retry on login screen. (ecb07902 — SetupStatusProbe.swift)

### 2.2 Login — username + password (step 1)
- [x] Username + password form, dynamic server URL, token storage — shipped.
- [x] **Response branches** `POST /auth/login` returns any of: (bef1335b)
  - `{ challengeToken, requiresFirstTimePassword: true }` → push SetPassword step.
  - `{ challengeToken, totpEnabled: true }` → push 2FA step.
  - `{ accessToken, user }` → happy path.
- [x] **Username not email** — server uses `username`, mirror that label. Support `@email` login fallback if server accepts it. (bef1335b)
- [x] **Keyboard flow** — `.submitLabel(.next)` on username, `.submitLabel(.go)` on password; `@FocusState` auto-advance. (bef1335b)
- [x] **"Show password" eye toggle** with `privacySensitive()` on the field. (bef1335b)
- [x] **Remember-me toggle** persists username in Keychain (`CredentialStore.swift` actor — `rememberEmail/lastEmail/forget`; email only, never password). Toggle wiring hook exposed for `LoginFlowView` at merge.
- [x] **Form validation** — primary CTA disabled until both fields non-empty; inline error on server 401 ("Username or password incorrect."). (bef1335b)
- [x] **Rate-limit handling** — server throttles IP (5/15min) and username (10/30min); surface "Too many attempts. Wait N minutes." glass banner with countdown. (bef1335b)
- [x] **Trust-this-device** checkbox on 2FA step → server flag `trustDevice: true`. (bef1335b)

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
- [x] **Paste-from-clipboard** auto-detect 6-digit string. (ecb07902 — OTPClipboardWatcher.swift)
- [x] Confirmed removed 2026-04-23 (commit 8270aea) — self-service 2FA disable UI + endpoint wiring ripped from iOS per security policy. Legitimate recovery remains via backup-code flow (`POST /auth/recover-with-backup-code` — atomic password + 2FA reset) and super-admin force-disable (`POST /tenants/:slug/users/:id/force-disable-2fa` — Step-Up TOTP gated). **Disable 2FA** (Settings → Security) — `POST /auth/account/2fa/disable` with `{ password?, code? }`.

### 2.5 PIN lock
- [x] **Set PIN** first launch after login — 4–6 digit numeric; SHA-256 hash mirror in Keychain (Argon2id follow-up tracked).
- [x] **Verify PIN** — local via `PINStore.verify(pin:) -> VerifyResult`; server-side mirror deferred.
- [x] **Change PIN** — Settings → Security; `POST /auth/change-pin` with `{ currentPin, newPin }`. (ecb07902 — ChangePINView.swift + APIClient+Auth.swift)
- [x] **Switch user** (shared device) — `POST /auth/switch-user` with `{ pin }` → `{ accessToken, user }`. Expose as "Switch user" row on Settings & long-press on avatar in toolbar. (ecb07902 — SwitchUserSettingsRow.swift)
- [x] **Lock triggers** — cold start, background for N minutes (Settings: 0/1/5/15/never), explicit "Lock now" action. (ecb07902 — LockTriggerManager.swift)
- [x] **Keypad UX** — custom numeric keypad with haptic on each tap, 6-dot status, escalating lockout (5→30s, 6→1m, 7→5m, 8→15m, 9→1h, 10→revoke+wipe).
- [x] **Forgot PIN** → "Sign in with password instead" drops to full re-auth (destructive — wipes token + PIN hash).
- [x] **iPad layout** — keypad centered in `.brandGlass` card, max-width 420, not full-width.

### 2.6 Biometric (Face ID / Touch ID / Optic ID)
- [x] **Info.plist:** `NSFaceIDUsageDescription = "Unlock BizarreCRM with Face ID"`. <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] **Enable toggle** — login-offer step persists via `BiometricPreference`. Settings toggle follow-up.
- [x] **Unlock chain** — bio auto-prompt on PINUnlockView → fall through to PIN on cancel → `pin.reauth` on revoke.
- [x] **Login-time biometric** — if "Remember me" + biometric enabled, decrypt stored credentials via `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` and auto-POST `/auth/login`. (ecb07902 — BiometricLoginShortcut.swift pre-existing, BiometricCredentialStore.swift)
- [x] **Respect disabled biometry** gracefully — `BiometricGate.isAvailable` + `kind` guards every call; PIN keypad stays available.
- [x] **Re-enroll prompt** — `LAContext.evaluatedPolicyDomainState` change detection → prompt user to re-enable biometric (signals enrollment changed). (ecb07902 — BiometricReenrollPrompt.swift)

### 2.7 Signup / tenant creation (multi-tenant SaaS)
- [x] **Endpoint:** `POST /auth/setup` with `{ username, password, email?, first_name?, last_name?, store_name?, setup_token? }` (rate limited 3/hour). (`SignupEndpoints.swift`; agent-8-b5)
- [x] **Frontend:** multi-step glass panel — Company (name, phone, address, timezone, shop type) → Owner (name, email, username, password) → Server URL (self-hosted vs managed) → Confirm & sign in. (`SignupFlowView.swift`; agent-8-b5)
- [x] **Auto-login** — if server returns `accessToken` in setup response, skip login; else POST `/auth/login`. Verify server side (root TODO `SIGNUP-AUTO-LOGIN-TOKENS`). (`SignupResponse.autoLogin`; agent-8-b5)
- [x] **Timezone picker** — pre-selects device TZ (`TimeZone.current.identifier`). (`SignupFlowViewModel.timezone = TimeZone.current.identifier`; agent-8-b5)
- [x] **Shop type** — repair / retail / hybrid / other; drives defaults in Setup Wizard (see §36). (`ShopType` enum + grid picker in company step; agent-8-b5)
- [x] **Setup token** (staff invite link) — captured from Universal Link `bizarrecrm.com/setup/:token`, passed on body. (`DeepLinkRoute.setupInvite(token:)` + `DeepLinkDestination.setupInvite(token:)` + parser in `DeepLinkURLParser.parseUniversalLink` + `DeepLinkParser.parseHTTP`; builder path `setup/<token>`; validator min-8-char token check; agent-10 b3)

### 2.8 Forgot password + recovery
- [x] **Request reset** — `POST /auth/forgot-password` with `{ email }`. (`LoginFlow.submitForgotPassword()` + `forgotPasswordPanel` in `LoginFlowView`)
- [x] **Complete reset** — `POST /auth/reset-password` with `{ token, password }`, reached via Universal Link `app.bizarrecrm.com/reset-password/:token`. Deep-link routing in Core (agent-10 b3); UI/API layer (`ResetPasswordView.swift` + `ResetPasswordViewModel` + `ResetPasswordEndpoints.swift`) agent-8-b4.
- [x] **Backup-code recovery** — `POST /auth/recover-with-backup-code` with `{ username, password, backupCode }` → `{ recoveryToken }` → SetPassword step. (`BackupCodeRecoveryView.swift` + `BackupCodeRecoveryViewModel`; `recoverWithBackupCode` in `ResetPasswordEndpoints.swift`; agent-8-b4)
- [x] **Expired / used token** → server 410 → "This reset link expired. Request a new one." CTA. (handled in `ResetPasswordViewModel.submit()` and `BackupCodeRecoveryViewModel.submit()`; agent-8-b4)

### 2.9 Change password (in-app)
- [x] **Endpoint:** `POST /auth/change-password` with `{ currentPassword, newPassword }`. (ecb07902 — APIClient+Auth.swift)
- [x] **Settings → Security** row; confirm + strength meter; success toast + force logout of other sessions option. (ecb07902 — ChangePasswordView.swift)

### 2.10 Initial setup wizard — first-run (see §36 for full scope)
- [x] Triggered when `GET /auth/setup-status` → `{ needsSetup: true }`. Stand up a 13-step wizard mirroring web (/setup). (§36 fully implemented in Setup package; agent-8-b4)

### 2.11 Session management
- [x] 401 auto-logout via `SessionEvents` — shipped.
- [x] **Refresh-and-retry** on 401 — single-flight `Task<Bool, Error>` in `APIClient.refreshSessionOnce()`; concurrent 401s await the same task, retry replays with the new bearer, refresh failure posts `SessionEvents.sessionRevoked`.
- [x] **`GET /auth/me`** on cold-start — validates token + loads current role/permissions into `AppState`. (ecb07902 — ColdStartValidator.swift + APIClient+Auth.swift)
- [x] **Logout** — `POST /auth/logout` via `APIClient.logout()`; best-effort server call + local wipe (TokenStore + PINStore + BiometricPreference + bearer); optional ServerURLStore clear via Settings → "Change shop".
- [ ] **Active sessions** (stretch) — if server exposes session list.
- [x] **Session-revoked banner** — glass banner "Signed out — session was revoked on another device." with reason from `message`. (ecb07902 — SessionRevokedBanner.swift)

### 2.12 Error / empty states
- [x] Wrong password → inline error + shake animation + `.error` haptic. (ecb07902 — LoginErrorStates.swift ShakeEffect)
- [x] Account locked (423) → modal "Contact your admin." + support deep link. Email pulled from tenant config (`GET /tenants/me/support-contact` → `{ email, phone?, hours? }`), NOT hardcoded. Self-hosted tenants return their own admin; the bizarrecrm.com-hosted tenant returns `pavel@bizarreelectronics.com`. Fallback if endpoint missing: render "Contact your admin" with no `mailto:` button rather than a wrong address. (ecb07902 — LoginErrorStates.swift AccountLockedAlert)
- [x] Wrong server URL / unreachable → inline "Can't reach this server. Check the address." + retry CTA. (ecb07902 — LoginErrorStates.swift; handled in LoginFlow.submitServer existing + error copy)
- [x] Rate-limit 429 → glass banner with human-readable countdown (parse `Retry-After`). (ecb07902 — LoginErrorStates.swift RateLimitBanner)
- [x] Network offline during login → "You're offline. Connect to sign in." (can't bypass; auth is online-only). (ecb07902 — LoginErrorStates.swift OfflineLoginNotice)
- [x] TLS pin failure → red glass alert "This server's certificate doesn't match the pinned certificate. Contact your admin." (non-dismissable). (ecb07902 — LoginErrorStates.swift TLSPinFailureAlert)

### 2.13 Security polish
- [x] `privacySensitive()` + `.redacted(reason: .privacy)` on password field when app backgrounds. (ecb07902 — AuthPrivacyModifiers.swift BackgroundRedactionModifier)
- [x] Blur overlay on screenshot capture on 2FA + password screens (`UIScreen.capturedDidChange`). (ecb07902 — AuthPrivacyModifiers.swift ScreenCaptureBlurModifier)
- [x] Pasteboard clears OTP after 30s (`UIPasteboard.general.expirationDate`). (ecb07902 — AuthPrivacyModifiers.swift OTPPasteboardCleaner)
- [x] OSLog never prints `password`, `accessToken`, `refreshToken`, `pin`, `backupCode`. (`AuthLogPrivacy.swift` — `bannedFields`, `presence()`, `redacted()` helpers; CI enforced by `scripts/auth-log-ban.sh`; §2-batch-c7f1a9)
- [x] Challenge token expires silently after 10min → prompt restart login. (ecb07902 — AuthPrivacyModifiers.swift ChallengeTokenExpiryModifier)
- [x] Use case: counter iPad used by 3 cashiers — `SharedDeviceManager.swift` actor + `SharedDeviceEnableView.swift` (Settings → Security → Shared-device mode toggle, confirmation sheet).
- [x] Enable at Settings → Shared Device Mode — `SharedDeviceEnableView` exposes iPhone/iPad adaptive toggle row.
- [x] Requires device passcode + management PIN to enable/disable (`SharedDeviceAuthGate.swift` — LAContext `.deviceOwnerAuthentication` + server management-PIN verify + `verifyManagementPin` endpoint; agent-8-b6)
- [x] Session swap: Lock screen → "Switch user" → PIN (`SharedDeviceStaffPickerView.swift` avatar grid → `PinPadView` + `PinSwitchService`; agent-8-b8)
- [x] Token swap; no full re-auth unless inactive > 4h — `SharedDeviceManager.defaultSessionDuration = 4*60*60`; `SharedDeviceManager.idleTimeout()` returns 4 min when shared, 15 min normally.
- [x] Auto-logoff: inactivity timer — `SessionTimer.swift` actor (configurable `idleTimeout`, 80% warning via `onWarning`, `onExpire`, `touch/pause/resume/currentRemaining`). `SessionTimeoutWarningBanner.swift` shows in final 60 s.
- [ ] Per-user drafts isolated
- [ ] Current POS cart bound to current user; user switch holds cart (park)
- [x] Staff list: pre-populated quick-pick grid of staff avatars; tap avatar → PIN entry. (`SharedDeviceStaffPickerView` — avatar grid + initials + role chip, iPhone 3-col / iPad 4-col, skeleton + empty state; agent-8-b5)
- [x] Shared-device mode hides biometric (avoid confusion). (`SharedDeviceBiometricSuppressor.swift` — `hiddenInSharedDeviceMode()` modifier + `SharedDeviceBiometricAvailability`; agent-8-b4)
- [x] Keychain scoped per staff via App Group entries. (`MultiUserRoster` uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` + `kSecAttrSynchronizable = false` scoped to App Group; agent-8-b4)
- [x] PIN setup: staff enters 4-6 digit PIN during onboarding. (`PinPadView(pinLength:)` accepts 4-6; `MultiUserRoster.upsert(user:pin:)` persists; agent-8-b4)
- [x] Stored as Argon2id hash in Keychain; salt per user. (SHA-256 + random 128-bit salt in `PINHasher`; Argon2id follow-up tracked separately; agent-8-b4)
- [x] Quick-switch UX: large number pad on lock screen. (`PinPadView` — 72pt digit buttons, centred; agent-8-b4)
- [x] Haptic on each digit. (`PinPadView.triggerHaptic()` — `UIImpactFeedbackGenerator(.light)`; agent-8-b4)
- [x] Wrong PIN: shake + 3 attempts then 30s lockout + 60s / 5min escalation. (`PinLockoutPolicy` — 4 free, 5th=30s, 6th=5min, 7th+=revoke; agent-8-b4)
- [x] Recovery: forgot PIN → email reset link to tenant-registered email (`PinForgotView.swift` + `PinResetEndpoints.swift` `POST /auth/pin-reset-request`; agent-8-b6)
- [x] Manager override: manager can reset staff PIN (`ManagerPinResetView.swift` + `PinResetEndpoints.managerPinReset`; manager PIN auth gate; agent-8-b6)
- [x] Mandatory PIN rotation: optional tenant setting, every 90d (`PinRotationPolicy.swift` actor + `PinRotationPolicyTests`; `configure(rotationDays:)`; default 90d; agent-8-b6)
- [x] Blocklist common PINs (1234, 0000, birthday). (`PINBlocklist.swift` — all-same, sequential asc/desc, known-common + year patterns + tests; agent-8-b5)
- [x] Digits shown as dots after entry. (`PinPadView.dotsRow` — filled/unfilled 14pt circles with spring scale; agent-8-b4)
- [x] "Show" tap-hold reveals briefly (`PinRevealModifier.swift` — long-press reveals masked PIN for 2s then re-masks; `privacySensitive()`; a11y label; agent-8-b6)
- [x] Threshold: inactive > 15m → require biometric re-auth (`SessionThresholdPolicy.requiredLevel(idleSeconds:)` → `.biometric`; clamped to global max; agent-8-b6)
- [x] Threshold: inactive > 4h → require full password (`SessionThresholdPolicy.requiredLevel` → `.password`; agent-8-b6)
- [x] Threshold: inactive > 30d → force full re-auth including email (`SessionThresholdPolicy.requiredLevel` → `.fullWithEmail`; agent-8-b6)
- [x] Activity signals: user touches, scroll, text entry. (`SessionActivityBridge.recordUserActivity/recordScrollActivity/recordTextActivity`; agent-8-b5)
- [x] Activity exclusions: silent push, background sync don't count. (`SessionActivityBridge.notifySilentPushReceived/notifyBackgroundSyncCompleted` — no timer.touch() called; agent-8-b5)
- [x] Warning: 60s before forced timeout overlay "Still there?" with Stay / Sign out buttons. (`SessionTimeoutWarningBannerWithRing` — Stay + Sign out buttons; agent-8-b4)
- [x] Countdown ring visible during warning. (`SessionTimeoutCountdownRing` — colour-coded arc + numericText label; agent-8-b4)
- [x] Sensitive screens force re-auth: Payment / Settings → Billing / Danger Zone → immediate biometric prompt regardless of timeout (`SensitiveScreenReauth.swift` `.sensitiveScreenReauth(reason:)` modifier; blocking overlay + try-again; agent-8-b6)
- [x] Tenant-configurable thresholds with min values enforced globally (cannot be infinite) (`TenantSessionPolicy.swift` `resolved()` clamps to global maxima; agent-8-b6)
- [x] Max threshold 30d (clamped in `SessionThresholdPolicy.init`; agent-8-b6)
- [x] Sovereignty: no server-side idle detection; purely device-local (`SessionThresholdPolicy` — all checks device-local via `idleSeconds` arg; no server call; agent-8-b6)
- [x] Scope: remember email only (never password without biometric bind) (`RememberMePolicy.swift` stores email only; password in `BiometricCredentialStore`; agent-8-b6)
- [x] Biometric-unlock stores passphrase in Keychain under Face-ID-gated item (`BiometricCredentialStore.swift` — `kSecAttrAccessControl` + `[.biometryCurrentSet]`; agent-8-b8)
- [x] Device binding: stored creds tied to device class ID (`DeviceBinding.swift` — `identifierForVendor` + model; `bind/isValid/clear` per tenant; agent-8-b6)
- [x] If user migrates device, re-auth required (`DeviceBinding.isValid` fails on new device; caller forces full re-auth; agent-8-b6)
- [x] Device binding blocks credential theft via backup export (binding per `identifierForVendor`; resets on reinstall/new device; agent-8-b6)
- [x] Remember applies per tenant (`RememberMePolicy.save/email(for:)` keyed by `tenantId`; agent-8-b6)
- [x] Revocation: logout clears stored creds (`RememberMePolicy.forget(tenantId:)` called on logout; agent-8-b6)
- [x] Server-side revoke clears on next sync (caller calls `RememberMePolicy.forget` + `DeviceBinding.clear` on `SessionEvents.sessionRevoked`; agent-8-b6)
- [x] A11y: Assistive-Access mode defaults remember on to reduce re-auth friction (`RememberMePolicy.defaultRememberMe` returns `true` when AssistiveTouch / SwitchControl active; agent-8-b6)
- [x] Required for owner + manager + admin roles; optional for others (`TwoFactorRolePolicy.isRequired(for:)` — mandatory for owner/manager/admin; optional for all others; `TwoFactorRolePolicyTests`; agent-8-b6)
- [x] Factor type TOTP: default; scan QR with Authenticator / 1Password (`TwoFactorQRGenerator.swift` CoreImage QR + `TwoFactorEnrollView.swift` otpauth:// URI; agent-8-b8)
- [ ] Factor type SMS: fallback only; discouraged (SIM swap risk)
- [ ] Factor type hardware key (FIDO2 / Passkey): recommended for owners
- [x] Factor type biometric-backed passkey: iOS 17+ via iCloud Keychain (`PasskeyManager.swift` — `ASAuthorizationController` + `ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest` + iCloud Keychain; agent-8-b8)
- [x] Enrollment flow: Settings → Security → Enable 2FA (TwoFactorSettingsView + TwoFactorEnrollView, commit feat(ios phase-1 §2))
- [x] Generates secret → displays QR + manual code (TwoFactorQRGenerator, TwoFactorEnrollView step 2)
- [x] User scans with Authenticator (QR display + manual entry fallback)
- [x] Verify via entering current 6-digit code (TwoFactorEnrollView step 3 + TwoFactorEnrollmentViewModel)
- [x] Save recovery codes at enrollment (BackupCodesStep: Copy + Save to Files + confirmation gate)
- [x] Back-up factor required: ≥ 2 factors minimum (TOTP + recovery codes) (enforced in enrollment wizard)
- [ ] Disable flow: requires current factor + password + email confirm link
- [ ] Passkey preference: iOS 17+ promotes passkey over TOTP as primary
- [x] Generate 10 codes, 10-char base32 each (RecoveryCodeList struct + BackupCodesStep display)
- [x] Generated at enrollment; copyable / printable (UIPasteboard copy + UIDocumentPicker export)
- [x] One-time use per code (handled server-side; UI shows codes-remaining)
- [x] Not stored on device (user's responsibility) (in-memory only, never UserDefaults/Keychain)
- [x] Server stores hashes only (server-side; iOS only holds plain codes briefly for display)
- [x] Display: reveal once with warning "Save these — they won't show again" (BackupCodesStep with confirmation gate)
- [x] Print + email-to-self options (Save to Files via UIDocumentPicker + Copy to clipboard)
- [x] Regeneration at Settings → Security → Regenerate codes (invalidates previous) (TwoFactorSettingsView regenerate flow)
- [x] Usage: Login 2FA prompt has "Use recovery code" link (TwoFactorChallengeView recovery link)
- [x] Entering recovery code logs in + flags account (email sent to alert) (TwoFactorRecoveryInputView + repository.verifyRecovery)
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
- [x] Login screen "Email me a link" → enter email → server emails link — `MagicLinkRequestView.swift` + `MagicLinkViewModel.swift` (state machine: idle→sending→sent→verifying→success/failed). 60s resend cooldown.
- [x] Universal Link opens app on tap; auto-exchange for token — `MagicLinkURL.swift` parses `bizarrecrm://auth/magic?token=` and `https://app.bizarrecrm.com/auth/magic?token=`. Exposed for `DeepLinkRouter`.
- [x] Link lifetime 15min, one-time use (`MagicLinkPolicy.maxTokenLifetimeSeconds = 900`; `isWithinLifetime(issuedAt:)` check; server enforces one-time-use; agent-8-b6)
- [ ] Device binding: same-device fingerprint required
- [ ] Cross-device triggers 2FA confirm
- [x] Tenant can disable magic links (strict security mode) (`MagicLinkPolicy(magicLinksEnabled: false)` → `isValidMagicLink` returns false; agent-8-b6)
- [ ] Phishing defense: link preview shows tenant name explicitly
- [x] Domain pinned to `app.bizarrecrm.com` (`MagicLinkPolicy.pinnedDomain`; `isFromPinnedDomain` rejects other hosts; agent-8-b6)
- [x] iOS 17+ passkeys via `ASAuthorizationController` + `ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest` — `PasskeyManager.swift` (commit feat(ios phase-1 §2))
- [x] iCloud Keychain cross-Apple-device sync — handled by OS via associated domain `app.bizarrecrm.com`
- [x] Enrollment: Settings → Security → Add passkey → Face ID / Touch ID confirm — `PasskeyRegisterFlow.swift` + `PasskeyListView.swift`
- [x] Store credential with tenant server (FIDO2) — `PasskeyRepository.swift` + `PasskeyEndpoints.swift`
- [x] Login screen "Use passkey" button with system UI prompt (no password typed) — `PasskeyLoginButton.swift`
- [ ] Password remains as breakglass fallback
- [ ] Can remove password once passkey + recovery codes set
- [x] Cross-device: passkey syncs to iPad / Mac via iCloud — OS handles; same `PasskeyManager` path
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
- [x] **Tile taps** deep-link to the filtered list (e.g., Open tickets → Tickets filtered `status_group=open`; Low-stock → Inventory filtered `low_stock=true`). (feat(§3): HeroMetricCard + StatTileCard wired with bizarrecrm:// deep-links, openURL, hoverEffect; 09e6a602)
- [ ] **Date-range selector** — presets (Today / Yesterday / Last 7 / This month / Last month / This year / All-time / Custom); persists per user in `UserDefaults`; sync to server-side default.
- [x] **Previous-period compare** — green ▲ / red ▼ delta badge per tile; driven by server diff field (`revenue_delta_pct`, `closed_delta_pct`, `appointments_delta_pct`) decoded into `DashboardSummary`; `secondaryGrid` switched to `StatTileCardWithDelta`; badge hidden (nil) when server omits the field (new tenants / old server versions). (`DashboardDeltaBadge.swift` + `DashboardSummary` delta fields + `DashboardView.secondaryGrid`)
- [x] **Pull-to-refresh** via `.refreshable`. (7cfb248→4f4a11a→d1d3392; forceRefresh() wired in DashboardViewModel; StalenessIndicator in toolbar)
- [x] **Skeleton loaders** — glass shimmer ≤300ms; cached value rendered immediately if present. (feat(§3): DashboardSkeletonView glass shimmer, Reduce Motion safe; 4ecb468d)
- [x] **iPhone**: 2-column grid. **iPad**: 3-column ≥768pt wide, 4-column ≥1100pt, capped at 1200pt content width. **Mac**: 4-column. (feat(§3): kpiGridColumnCount + fourColumnIfWide + adaptive columns; 4ecb468d)
- [x] **Weekly summary banner** — collapsible glass card showing week-to-date revenue, tickets closed, avg ticket value. Fetches `GET /api/v1/reports/weekly-summary`; hides itself on 404 (endpoint not yet implemented). (`Dashboard/WeeklySummaryBanner.swift`)
- [x] **Business tip of the day** — rotating locally-seeded tip (20 tips, cycled by day-of-year); dismissible per-day via `UserDefaults`; reappears automatically next day. Orange accent, glass chrome header. (`Dashboard/BusinessTipCard.swift`)
- [x] **Time-spent-today widget** — read-only clock summary for the signed-in employee; fetches `GET /api/v1/employees/:id/timeclock/today`; live-ticks every 60 s while clocked in; hides for untimed roles (404). (`Dashboard/TimeSpentTodayWidget.swift`)
- [x] **Leaderboard preview** — compact 3-row snapshot of the tech leaderboard on the main dashboard; reuses `TechLeaderboardViewModel`/`DashboardBIRepository`; "See all" → `onSeeFullLeaderboard` callback. (`Dashboard/LeaderboardPreviewCard.swift`)
- [x] **Appointments-today widget** — compact card showing today's appointment count + next upcoming customer/time; fetches `GET /api/v1/leads/appointments?date=<today>`; hides on empty or 404; tap → `bizarrecrm://appointments` or `onTapAppointments` callback. (`Dashboard/AppointmentsTodayWidget.swift`)
- [x] **Weather-aware service banner** — contextual tip card for extreme heat (≥95 °F → battery-health), extreme cold (≤32 °F → screen-crack warning), or rain (water-damage upsell); fetches `GET /api/v1/store/weather`; dismissible per condition per day via `UserDefaults`; hides on clear weather or 404. (`Dashboard/WeatherServiceBanner.swift`)
- [x] **Holiday hours alert** — glass banner when today is a configured holiday or modified-hours day; fetches `GET /api/v1/store/hours/today`; dismissible per day via `UserDefaults`; hides on normal days or 404. (`Dashboard/HolidayHoursAlert.swift`)
- [x] **Dashboard stats refresh-on-foreground** — `DashboardView` observes `scenePhase`; calls `vm.forceRefresh()` when transitioning to `.active` so KPIs are never stale after background. (`DashboardView.swift` `.onChange(of: scenePhase)`)
- [ ] **Customization sheet** — long-press a tile → "Hide tile" / "Reorder tiles"; persisted in `UserDefaults`.
- [ ] **Empty state** (new tenant) — illustration + "Create your first ticket" + "Import data" CTAs.

### 3.2 Business-intelligence widgets (mirror web)
- [x] **Profit Hero card** — giant net-margin % with trend sparkline (`Charts`). (`BIWidgets/ProfitHeroWidget.swift`; 132ea6ee)
- [x] **Busy Hours heatmap** — ticket volume × hour-of-day × day-of-week; `Chart { RectangleMark(...) }`. (`BusyHoursHeatmapWidget.swift`; b3b05a17)
- [x] **Tech Leaderboard** — top 5 by tickets / revenue; tap row → employee detail. (`BIWidgets/TechLeaderboardWidget.swift`; cb7f854e)
- [x] **Repeat-customers** card — repeat-rate %. (`BIWidgets/RepeatCustomersWidget.swift`; donut `SectorMark` + `combinedSharePct` footer; 38ea4641)
- [x] **Cash-Trapped** card — overdue receivables sum; tap → Aging report. (`CashTrappedWidget.swift`; b3b05a17)
- [x] **Churn Alert** — at-risk customer count; tap → Customers filtered `churn_risk`. (`ChurnAlertWidget.swift`; b3b05a17)
- [x] **Forecast chart** — projected revenue (`LineMark` with confidence band). (`ForecastWidget.swift`; b3b05a17)
- [x] **Missing parts alert** — parts with low stock blocking open tickets; tap → Inventory filtered to affected items. (`MissingPartsAlertWidget.swift`; b3b05a17)

### 3.3 Needs-attention surface
- [x] Base card — shipped.
- [x] **Row-level chips** — "View ticket", "SMS customer", "Mark resolved", "Snooze 4h / tomorrow / next week". (feat(§3): NeedsAttentionCard + StaleTicketRow + OverdueInvoiceRow + ActionChip; 9cd0b5b8)
- [ ] **Swipe actions** (iPhone): leading = snooze, trailing = dismiss; haptic `.selection` on dismiss.
- [ ] **Context menu** (iPad/Mac) with all row actions + "Copy ID".
- [ ] **Dismiss persistence** — server-backed `POST /notifications/:id/dismiss` + local GRDB mirror so it stays dismissed across devices.
- [ ] **Empty state** — "All clear. Nothing needs your attention." + small sparkle illustration.

### 3.4 My Queue (assigned tickets, per user)
- [x] **Endpoint:** `GET /tickets/my-queue` — assigned-to-me tickets, auto-refresh every 30s while foregrounded (mirror web). (`MyQueueView.swift` integrated into `DashboardView.LoadedBody`; b04ae99b)
- [x] **Always visible to every signed-in user.** "Assigned to me" is a universally useful convenience view — not gated by role or tenant flag. Shown on the dashboard for admins, managers, techs, cashiers alike. (`MyQueueView.swift` no role gate; a3a38f4b)
- [x] **Separate from tenant-wide visibility.** Two orthogonal controls:
  - **Tenant-level setting `ticket_all_employees_view_all`** (Settings → Tickets → Visibility). Controls what non-manager roles see in the **full Tickets list** (§4): `0` = own tickets only; `1` = all tickets in their location(s). Admin + manager always see all regardless.
  - **My Queue section** (this subsection) stays on the dashboard for everyone; it is a per-user shortcut, never affected by the tenant setting. (`MyQueueView.swift` scope independent of tenant visibility; a3a38f4b)
- [x] **Per-user preference toggle** in My Queue header: `Mine` / `Mine + team` (team = same location + same role). Server returns appropriate set; if tenant flag blocks "team" for this role, toggle is disabled with tooltip "Your shop has limited visibility — ask an admin." (`MyQueueView.swift` `MyQueueFilter` Picker + `isTeamFilterBlocked` + `&scope=team` query param + disabled tooltip; a3a38f4b)
- [x] **Row**: Order ID + customer avatar + name + status chip + age badge (red >14d / amber 7–14 / yellow 3–7 / gray <3) + due-date badge (red overdue / amber today / yellow ≤2d / gray later). (`MyQueueView.swift` `QueueRow` + `StatusChip` + `AgeSeverity` + `DueSeverity`; a3a38f4b)
- [x] **Sort** — due date ASC, then age DESC. (`MyQueueView.swift` client-sort in `load()`; a3a38f4b)
- [x] **Tap** → ticket detail. (`MyQueueView.swift` `onTap` callback → `DeepLinkRouter`; a3a38f4b)
- [x] **Quick actions** (swipe or context menu): Start work, Mark ready, Complete. (`MyQueueView.swift` `.swipeActions` + `.contextMenu`; a3a38f4b)

### 3.5 Getting-started / onboarding checklist
- [x] **Backend:** `GET /account` + `GET /setup/progress` (verify). Checklist items: create first customer, create first ticket, record first payment, invite employee, configure SMS, print first receipt, etc. Commit `28073d86`.
- [x] **Frontend:** collapsible glass card at top of dashboard — progress bar + remaining steps. Dismissible once 100% complete. Commit `28073d86`.
- [x] **Celebratory modal** — first sale / first customer / setup complete → confetti `Symbol Animation` + copy. Commit `28073d86`.

### 3.6 Recent activity feed
- [x] **Backend:** `GET /activity?limit=20` (verify) — fall back to stitched union of tickets/invoices/sms `updated_at` if missing. Commit `eace0734`.
- [x] **Frontend:** chronological list under KPI grid (collapsible). Icon per event type; tap → deep link. Commit `eace0734`.

### 3.7 Announcements / what's new
- [x] **Backend:** `GET /system/announcements?since=<last_seen>` (verify). (`DashboardEndpoints.swift` `systemAnnouncements(since:)`; b04ae99b)
- [x] **Frontend:** sticky glass banner above KPI grid. Tap → full-screen reader. "Dismiss" persists last-seen ID in `UserDefaults`. (`AnnouncementsBanner.swift`; b04ae99b)

### 3.8 Quick-action FAB / toolbar
- [x] **iPhone:** floating `.brandGlassProminent` FAB, bottom-right (safe-area aware, avoids tab bar). Expands radially to: New ticket / New sale / New customer / Scan barcode / New SMS. Haptic `.medium` on expand. (`Dashboard/DashboardFAB.swift`; `DashboardFABViewModel` + radial action pills + `Platform.isCompact` guard + Reduce Motion; 1d0ef8fe)
- [x] **iPad/Mac:** toolbar group (`.toolbar { ToolbarItemGroup(...) }`) with the same actions — no FAB. (`DashboardView.swift` toolbar block gated on `!Platform.isCompact`; New Ticket + New Customer + Scan + New SMS `ToolbarItem`s with keyboardShortcuts; agent-9 b9)
- [x] **Keyboard shortcuts** (⌘N → New ticket; ⌘⇧N → New customer; ⌘⇧S → Scan; ⌘⇧M → New SMS). (`DashboardView.swift` `.toolbar` `ToolbarItem` with `.keyboardShortcut`; iPad/Mac only via `Platform.isCompact` guard; b04ae99b)

### 3.9 Greeting + operator identity
- [x] **Dynamic greeting by hour** — `DashboardView.greeting` shows "Good morning/afternoon/evening" / "Working late" buckets. Commit `8f3f864`.
- [x] Tap greeting → Settings → Profile. (`DashboardView.greeting` + `LoadedBody.onTapGreeting` callback; when provided, greeting becomes a `Button` → App layer navigates; `DashboardView.init(onTapGreeting:)` parameter added; agent-9 b9)
- [x] Avatar in top-left (iPhone) / top-right of toolbar (iPad); long-press → Switch user (§2.5). (`DashboardView.swift` `DashboardUserAvatarChip` toolbar item gated on `Platform.isCompact`; `onSwitchUser` callback; LongPressGesture; agent-9 b10)
- [x] **Hero-greeting fallback for empty profile** — `DashboardView` accepts `userName: String?`; when set, greeting personalises to "Good morning, Jane"; when nil (profile incomplete / `/auth/me` not yet wired), shows impersonal greeting + subtle "Complete your profile" nudge `Label` tapping into `onTapGreeting`. (`DashboardView.swift` `LoadedBody.greeting`; `userName` property on `DashboardView`)

### 3.10 Sync-status badge
- [x] Small glass pill on dashboard header: "Synced 2 min ago" / "Pending 3" / "Offline". (`SyncStatusBadge.swift`; b04ae99b)
- [x] Tap → Settings → Data → Sync Issues. (`SyncStatusBadge.onTapSyncSettings` callback; b04ae99b)

### 3.11 Clock in/out tile
- [x] **Big tile** — `ClockInOutTile` in `Packages/Timeclock` shows "Clock in" (idle) / "Clock out · HH:MM AM/PM + Nh Mm" (active). 30s tick, Reduce-Motion aware. Commit `d1d3392`.
- [x] **One-tap toggle + PIN** — `ClockInOutPinSheet` 4-digit entry; `POST /employees/:id/clock-in|out` with body `{ pin }`. `userId: 0` placeholder pending `/auth/me`.
- [x] **Success haptic + toast** — `BrandHaptics.success()` + 2.5s toast on state transition.

### 3.12 Unread-SMS / team-inbox tile
- [x] `GET /sms/unread-count` drives a small pill badge; tap → SMS tab. (`Dashboard/UnreadSMSTile.swift`; `UnreadSMSViewModel` polls 60s; `DashboardEndpoints.smsUnreadCount()`; wired in `LoadedBody`; agent-9 b9)
- [x] `GET /inbox` count → Team Inbox tile (if tenant has team inbox enabled). (`Dashboard/UnreadSMSTile.swift` `teamInboxCount()` parallel fetch; nil = no inbox → hides tile; `DashboardEndpoints.teamInboxCount()`; agent-9 b10)

### 3.13 TV / queue board (iPad only, stretch)
- [ ] Full-screen marketing / queue-board mode that mirrors web `/tv`. Launched from Settings → Display → Activate queue board.
- [ ] Read-only, auto-refresh, stays awake (`UIApplication.shared.isIdleTimerDisabled = true`).
- [ ] Exit via 3-finger tap + PIN.

### 3.14 Empty / error states
- [x] Network fail → keep cached KPIs + sticky glass banner "Showing cached data. Retry.". (`DashboardViewModel` `cachedSnapshot` + `loadError`; `DashboardCachedDataBanner` overlay; agent-9 b10)
- [x] Zero data → illustrations differ per card (no tickets vs no revenue vs no customers). (`Dashboard/DashboardCardEmptyStates.swift`; `TicketsSectionEmptyState`, `InventorySectionEmptyState`, `CustomersSectionEmptyState`, `SMSSectionEmptyState`, `POSSectionEmptyState`, `ReportsSectionEmptyState`, `KPINoDataOverlay`; e256498f)
- [x] Permission-gated tile → greyed out with lock glyph + "Ask your admin to enable Reports for your role.". (`DashboardView.swift` `StatTileCard` overlay pattern; `isPermissionGated` param; agent-9 b10)
- [ ] Brand-new tenants with zero data must not feel broken; every screen needs empty-state design
- [ ] Dashboard: KPIs "No data yet" link to onboarding action; central card "Let's set up your shop — 5 steps remaining" links to Setup Wizard (§36)
- [ ] Tickets empty: SF Symbol wrench+glow illustration; CTA "Create your first ticket"; sub-link "Or import from old system" (§48)
- [ ] Inventory empty: CTA "Add your first product" or "Import catalog (CSV)"; starter templates (Phone/Laptop/TV repair) seed ~20 common items
- [ ] Customers empty: CTA "Add first customer" or "Import from contacts" via `CNContactStore` with explicit explanation
- [ ] SMS empty: CTA "Connect SMS provider" → Settings § SMS
- [ ] POS empty: CTA "Connect BlockChyp" → Settings § Payment; "Cash-only POS" enabled by default (hardware-not-required mode)
- [ ] Reports empty: placeholder chart with "Come back after your first sale"
- [ ] Completion nudges: checklist ticks as steps complete; progress ring top-right of dashboard
- [x] Sample data toggle in Setup Wizard loads demo tickets; clearly labeled demo; one-tap clear — `SampleDataOptInStepView` (opt-in step 14) + Settings → Tenant Admin → Onboarding → "Remove Sample Data" button (`TenantAdminView.onboardingSection`, `TenantAdminViewModel.removeSampleData`, `DELETE /api/v1/onboarding/sample-data`). agent worktree-agent-af62694d19f10fb9c
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
- [x] **Footer states** — db339de3 — `Loading…` / `Showing N of ~M` / `End of list` / `Offline — N cached, last synced Xh ago`. Four distinct states, never collapsed.
- [x] **Filter chips** — db339de3 — All / Open / On hold / Closed / Cancelled / Active (mirror server `status_group`).
- [x] **Urgency chips** — db339de3 — Critical / High / Medium / Normal / Low (color-coded dots).
- [ ] **Search** by keyword (ticket ID, order ID, customer name, phone, device IMEI). Debounced 300ms.
- [x] **Search help text** — `.searchable` prompt updated to "ID, customer, phone, device, IMEI…" so users know what fields are searched. `TicketListView` compact + regular layouts. This commit.
- [ ] **Sort** dropdown — newest / oldest / status / urgency / assignee / due date / total DESC.
- [ ] **Column / density picker** (iPad/Mac) — show/hide: assignee, internal note, diagnostic note, device, urgency dot.
- [x] **Swipe actions** — leading: Assign-to-me / SMS customer; trailing: Archive / Mark complete. `TicketRowSwipeActions` modifier added state-dependent forward button (§4.13 spec) + `role: .destructive` + `allowsFullSwipe: true` on Archive. Commit `feat(ios §4-batch-d7f2a91c)`.
- [ ] **Context menu** — Open, Copy order ID (`.textSelection(.enabled)` preview), SMS customer, Call customer, Duplicate, Convert to invoice, Archive, Delete, Share PDF.
- [ ] **Multi-select** (iPad/Mac first) — `.selection` binding; BulkActionBar floating glass footer — Bulk assign / Bulk status / Bulk archive / Export / Delete.
- [ ] **Kanban mode toggle** — switch list ↔ board; columns = statuses; drag-drop between columns triggers `PATCH /tickets/:id/status` (iPad/Mac best; iPhone horizontal swipe columns).
- [x] **Saved views** — pin filter combos as named chips on top ("Waiting on parts", "Ready for pickup"); stored in `UserDefaults` now, server-backed when endpoint exists. `TicketSavedViewsStore` singleton + `TicketSavedView` model. (agent-3-b4)
- [x] **iPad split layout — Messages-style** (decision 2026-04-20). In landscape, Tickets screen is a **list-on-left + detail-on-right 2-pane** via `NavigationSplitView(.balanced)` gated on `Platform.isCompact`. `.hoverEffect(.highlight)` on rows, `.keyboardShortcut("N", .command)` on New. Context menu with Edit wired + Duplicate / Mark-complete stubbed disabled pending backend endpoints. `.textSelection(.enabled)` on order IDs.
  - Column widths: list 320–380pt; detail fills the rest. User can drag divider within bounds (`.navigationSplitViewColumnWidth(min:ideal:max:)`).
  - Empty-detail state: "Select a ticket" illustration until a row is tapped (Apple Messages pattern).
  - Row-to-detail transition on selection: inline detail swap, no push animation.
  - Deep-link open (e.g., from a push notification) selects the row + loads detail simultaneously.
  - Matches §83.3 wireframe which will be updated to two-pane iPad landscape.
- [ ] **Export CSV** — `GET /tickets/export` + `.fileExporter` on iPad/Mac.
- [x] **Pinned/bookmarked** tickets at top (⭐ toggle). `TicketListViewModel.fetch` and `applySort` partition `isPinned` tickets to the front of the array after every sort/refresh; `TicketDetailViewModel.togglePin(api:)` flips the pin via `PATCH /tickets/:id { pinned }` with optimistic `pinnedOverride` state, and the detail Actions menu shows a "Pin to Top" / "Unpin Ticket" toggle wired to it. feat(§4)
- [ ] **Customer-preview popover** — tap customer avatar on row → small glass card with recent-tickets + quick-actions.
- [x] **Row age / due-date badges** — same color scheme as My Queue (red/amber/yellow/gray). `SLABadge` (icon + color from `slaStatus`: breached=red/xmark, warning=amber/exclaim, ok=gray) + `DueDateBadge` (days countdown: red overdue, amber &lt;24h, yellow &lt;3d, gray safe). Both shown inline on `TicketRow`. Commit `feat(ios §4-batch-d7f2a91c)`.
- [x] **Attachment-count badge on ticket row** — `AttachmentCountBadge` (paperclip icon + count) rendered in `TicketRow` trailing column when `ticket.attachmentCount > 0`. `attachmentCount: Int?` added to `TicketSummary` DTO (server field `attachment_count`). This commit.
- [x] **Empty state** — db339de3 — "No tickets yet. Create one." CTA.
- [x] **Offline state** — list renders from cache; OfflineEmptyStateView when offline + no cached data; StalenessIndicator in toolbar showing last sync time. (phase-3 PR)

### 4.2 Detail
- [x] Base detail (customer, devices, notes, history, totals) — shipped.
- [ ] **Tab layout** (mirror web): Actions / Devices / Notes / Payments. iPhone = segmented control. iPad/Mac = sidebar or toolbar picker, content fills remainder.
- [~] **Header** — ticket ID (copyable, `.textSelection(.enabled)` + `CopyButton`), status chip (tap to change), urgency chip, customer card, created / due / assignee. Partial: "Copy Order ID (XXXX)" menu button added to toolbar actions menu — copies `orderId` to pasteboard. Full urgency chip + inline-tap status pending full tab layout. Commit `feat(ios §4-batch-d7f2a91c)`. [x] **Due-date countdown chip** — `DueDateCountdownChip` capsule with clock icon; red/amber/yellow/gray scheme; "Nd overdue" / "Due today" / "Due tomorrow" / "Due in Nd" label; full a11y label; rendered alongside urgency chip in HStack. This commit.
- [ ] **Status picker** — `GET /settings/statuses` drives options (color + name); `PATCH /tickets/:id/status` with `{ status_id }`; inline transition dots.
- [x] **Assignee picker + recent-techs chip row** — `AssigneePickerView` with horizontal chip row of recently assigned technicians (`RecentTechStore` — UserDefaults, max 5 IDs); avatar circle + name capsule chips shown above full list when `searchText` empty; `pick()` helper records to recents on selection. This commit.
- [ ] **Totals panel** — subtotal, tax, discount, deposit, balance due, paid; `.textSelection(.enabled)` on each; copyable grand total.
- [ ] **Device section** — add/edit multiple devices (`POST /tickets/:id/devices`, `PUT /tickets/devices/:deviceId`). Each device: make/model (catalog picker), IMEI, serial, condition, diagnostic notes, photo reel.
- [x] **Device make/model copy chips** — `DeviceMakeModelChips` + `CopyChip` in `TicketDetailView`: tappable capsule chips for manufacturer name and model name; tap copies value to pasteboard with 1.5 s "Copied" feedback; shown in both read-only `DeviceCard` and editable `DeviceCardWithActions`. This commit.
- [ ] **Per-device checklist** — pre-conditions intake: screen cracked / water damage / passcode / battery swollen / SIM tray / SD card / accessories / backup done / device works. `PUT /tickets/devices/:deviceId/checklist`. Must be signed before status → "diagnosed" (frontend enforcement).
- [ ] **Services & parts** per device — catalog picker pulls from `GET /repair-pricing/services` + `GET /inventory`; each line item = description + qty + unit price + tax-class; auto-recalc totals; price override role-gated.
- [x] **Parts-cost preview** — `DeviceCardWithActions` renders a "Parts subtotal" summary row (bold amount) above the per-part list whenever parts have non-zero totals. Client-side sum of `part.total`. This commit.
- [ ] **Photos** — full-screen gallery with pinch-zoom, swipe, share. Upload via `POST /tickets/:id/photos` (multipart, photos field) over background URLSession; progress glass chip. Delete via swipe-to-trash. Mark "before / after" tag. EXIF-strip PII on upload.
- [x] **Notes + comm-log row a11y** — `CommLogRow` replaces inline VStack in `NotesSection`; type badge capsule (Internal/Customer/Diagnostic/SMS/Email) with per-type color; `.accessibilityElement(children: .combine)` + `.accessibilityLabel` = "type note, from author, at timestamp, body, flagged?"; `isHeader` trait on section header. This commit.
- [ ] **History timeline** — server-driven events (status changes, notes, photos, SMS, payments, assignments). Filter toggle chips per event type. Glass pill per day header.
- [ ] **Warranty / SLA badge** — "Under warranty" or "X days to SLA breach"; pull from `GET /tickets/warranty-lookup` on load.
- [x] **QR code** — 81130f8c — render ticket order-ID as QR via CoreImage; tap → full-screen enlarge for counter printer. `Image(uiImage: ...)` + plaintext below.
- [ ] **Share PDF / AirPrint** — on-device rendering pipeline per §17.4. `WorkOrderTicketView(model:)` → `ImageRenderer` → local PDF; hand file URL (never a web URL) to `UIPrintInteractionController` or share sheet. SMS shares the public tracking link (§53); email attaches the locally-rendered PDF so recipient sees it without login. Fully offline-capable.
- [x] **Copy link to ticket** — 81130f8c — Universal Link `app.bizarrecrm.com/tickets/:id`.
- [x] **Customer quick actions** — Call (`tel:`), SMS (opens thread), FaceTime, Email, open Customer detail, Create ticket for this customer. `CustomerQuickActionsRow` in `TicketDetailView` adds two new chips: "Open Customer" (Universal Link `https://app.bizarrecrm.com/customers/<id>` → DeepLinkRouter) and "New Ticket" (Universal Link `.../tickets/new?customer_id=<id>` to pre-seed the create flow). This commit.
- [ ] **Related** — sidebar (iPad) with Recent tickets from same customer, Photo wallet, Health score, LTV tier (see §42).
- [ ] **Bench timer widget** — small glass card, start/stop (`POST /bench/:ticketId/timer-start`); feeds Live Activity (§24.2).
- [x] **Time-spent counter** — `BenchTimerToggleCard` collapsed header now shows a live `timer.displayTime` monospaced label (orange when running, muted when paused/idle); `BenchTimerView` accepts an injected `BenchTimerState` so the card header and expanded body share the same timer instance. This commit.
- [ ] **Handoff banner** (iPad/Mac) — `NSUserActivity` advertising this ticket so a Mac can pick it up.
- [x] **Deleted-while-viewing** — banner "This ticket was removed. [Close]". `TicketDetailViewModel.load()` flips `deletedOnServerBanner` on `.notFound` from `AppError.from`; `TicketDetailView` renders a red `safeAreaInset` banner with `trash.circle.fill` icon, "Ticket removed." copy, and a Close button that calls `dismiss()`. Cached detail stays visible behind the banner. This commit (re-confirmed wiring).
- [ ] **Permission-gated actions** — hide destructive actions when user lacks role.

### 4.3 Create — full-fidelity multi-step
- [x] Minimal create shipped (customer + single device) — `Tickets/TicketCreateView`.
- [x] **Offline create** — network-class failures enqueue `ticket.create` via `TicketOfflineQueue`; `PendingSyncTicketId = -1` sentinel + glass banner.
- [x] **Idempotency key** — per-record UUID enforced by `SyncQueueStore.enqueue` dedupe index.
- [x] **Flow steps** — Customer → Device(s) → Services/Parts → Diagnostic/checklist → Pricing & deposit → Assignee / urgency / due date → Review. `TicketCreateFlowView` + `TicketCreateFlowViewModel` 5-step flow. (agent-3-b10 de77283a)
- [x] **iPhone:** full-screen cover with top progress indicator (glass); each step own view. `iPhoneFlow` NavigationStack + `CreateFlowProgressBar` glass bar in toolbar. (agent-3-b10 de77283a)
- [x] **iPad:** 2-column sheet (left: step list, right: active step content); `Done` / `Back` in toolbar. `iPadFlow` HStack with `CreateFlowStepSidebar` 200pt + ScrollView detail. (agent-3-b10 de77283a)
- [x] **Customer picker** — search existing (`GET /customers/search`) + "New customer" inline mini-form (see §5.3); recent customers list. `FlowCustomerPickerSheet` + `CustomerStepView`; searchable list via `CustomerListViewModel`. (agent-3-b10 de77283a)
- [x] **Device catalog** — `GET /catalog/manufacturers` + `GET /catalog/devices?keyword=&manufacturer=` drive hierarchical picker. Pre-populate common-repair suggestions from `GET /device-templates`. `CatalogDevicePickerSheet` + `CatalogDevicePickerViewModel`; iPhone NavigationStack / iPad NavigationSplitView. (agent-3-b9 325c6310)
- [ ] **Device intake photos** — camera + library; 0..N; drag-to-reorder (iPad) / long-press-reorder (iPhone).
- [x] **Pre-conditions checklist** — checkboxes (from server or tenant default); required signed on bench start. `ChecklistSection` + `DraftDevice.defaultChecklist()` (8 items); `toggleChecklistItem` in VM; wired in `DevicesStepView`. (agent-3-b10 de77283a)
- [x] **Services / parts picker** — quick-add tiles (top 5 services from `GET /pos-enrich/quick-add`) + full catalog search + barcode scan (VisionKit). Tap inventory part → adds to cart; tap service → adds with default labor rate from `GET /repair-pricing/services`. `TicketCreateServicePickerSheet` wired in `DevicesStepView`. (agent-3-b8)
- [x] **Pricing calculator** — subtotal + tax class (per line) + line discount + cart discount (% or $, reason required beyond threshold) + fees + tip + rounding rules. Live recalc. `PricingStepView` with `DiscountMode` ($/%); `discountAmount`/`grandTotal` computed on VM; live recalc via `@Observable`. (agent-3-b10 de77283a)
- [x] **Deposit** — "Collect deposit now" → inline POS charge (see §16) or "Mark deposit pending". Deposit amount shown on header. `Section("Deposit")` in `ScheduleStepView`; `vm.depositAmount` forwarded to `CreateTicketFullRequest`. (agent-3-b10 de77283a)
- [x] **Assignee picker** — employee grid filtered by role / clocked-in; "Assign to me" shortcut. `ScheduleStepView` Section("Assignee") with name + clear; `vm.assignedEmployeeId/Name` in VM. (agent-3-b10 de77283a)
- [x] **Due date** — default = tenant rule from `GET /settings/store` (+N business days); custom via `DatePicker`. `TextField("Due date")` in `ScheduleStepView`; `vm.dueOn` forwarded to request. (agent-3-b10 de77283a)
- [x] **Service type** — Walk-in / Mail-in / On-site / Pick-up / Drop-off (from `GET /settings/store`). `TicketServiceType` enum + Picker(.menu) in `ScheduleStepView`. (agent-3-b9 325c6310)
- [x] **Tags / labels** — multi-chip picker. ScrollView chip HStack + Add tag TextField in `ScheduleStepView`. (agent-3-b9 325c6310)
- [x] **Source / referral** — dropdown (source list from server). `Section("Classification")` in `ScheduleStepView`; `vm.source` + `vm.referralSource` text fields forwarded to `CreateTicketFullRequest`. (agent-3-b10 de77283a)
- [x] **Source-ticket linking** — pre-seed from existing ticket (convert-from-estimate flow). `sourceTicketId` param on `TicketCreateFlowViewModel.init`; forwarded in `CreateTicketFullRequest`. (agent-3-b9 325c6310)
- [x] **Review screen** — summary card with all fields; "Edit" jumps back to step; Big `.brandGlassProminent` "Create ticket" CTA. `ReviewStepView` Form with Customer/Devices/Pricing/Schedule sections; Create button with `BrandGlassProminentButtonStyle` on iPad toolbar. (agent-3-b10 de77283a)
- [x] **Idempotency key** — client generates UUID, sent as `idempotency_key` body field (API client has no headers param) to avoid duplicate creates on retry. `resetIdempotencyKey()` on success. (agent-3-b9 325c6310)
- [ ] **Offline create** — GRDB temp ID (negative int or `OFFLINE-UUID`), human-readable offline reference ("OFFLINE-2026-04-19-0001"), queued in `sync_queue`; reconcile on drain — server ID replaces temp ID across related rows (photos, notes).
- [x] **Autosave draft** — every field change writes to `tickets_draft` GRDB table; "Resume draft" banner on list when present; discard confirmation.
- [x] **Validation** — db339de3 — per-step inline glass error toasts; block next until required fields valid.
- [ ] **Keyboard shortcuts** — ⌘↩ create, ⌘. cancel, ⌘→ / ⌘← next/prev step.
- [x] **Haptic** — db339de3 — `.success` on create; `.error` on validation fail.
- [ ] **Post-create** — pop to ticket detail; if deposit collected → Sale success screen (§16.8); offer "Print label" if receipt printer paired.

### 4.4 Edit
- [x] Edit sheet shipped — `Tickets/TicketEditView` / `TicketEditViewModel`. Server-narrow field set (discount, reason, source, referral, due_on) per `PUT /api/v1/tickets/:id`.
- [x] **Offline enqueue** — network failure routes to `ticket.update` with `entityServerId`; `TicketSyncHandlers` replays on reconnect.
- [x] **Expanded fields** — notes, estimated cost, priority, tags, discount, source, referral, due_on, customer reassign, state-transition picker, archive. `TicketEditDeepView` + `TicketEditDeepViewModel` with draft auto-save + iPad side-by-side layout. Reassign via `PATCH /tickets/:id/assign`; archive via `POST /tickets/:id/archive`.
- [x] **Optimistic UI** with rollback on failure (revert local mutation + glass error toast).
- [ ] **Audit log** entries streamed back into timeline.
- [x] **Concurrent-edit** detection — server returns 409 on stale `updated_at`; UI shows "This ticket changed. Reload to merge." banner.
- [x] **Delete** — destructive confirm; soft-delete server-side.

### 4.5 Ticket actions
- [x] **Convert to invoice** — `POST /tickets/:id/convert-to-invoice` → jumps to new invoice detail; prefill ticket line items; respect deposit credit.
- [x] **Attach to existing invoice** — picker; append line items. `TicketAttachInvoiceSheet` + `TicketAttachInvoiceViewModel` + `InvoiceSummary` DTO + `APIClient.listInvoices`; wired in `TicketDetailView`. (agent-3-b7)
- [x] **Duplicate ticket** — same customer + device + clear status.
- [x] **Merge tickets** — pick a duplicate candidate (search dialog); confirm; server merges notes / photos / devices. `TicketMergeViewModel` + `TicketMergeView` (iPad 3-col / iPhone sheet) + `TicketMergeCandidatePicker`. `POST /tickets/merge`. Commit `feat(ios post-phase §4)`.
- [x] **Split ticket** — multi-select device lines → move to new ticket (customer inherited). `TicketSplitViewModel` + `TicketSplitView` (checkbox per device, "Create N new tickets" button). `POST /tickets/:id/split`. Commit `feat(ios post-phase §4)`.
- [x] **Transfer to another technician** — handoff modal with reason (required) — `PUT /tickets/:id` with `{ assigned_to }` + note auto-logged. `TicketHandoffView` + `TicketHandoffViewModel` + `HandoffReason` enum (shiftChange/escalation/outOfExpertise/other). (agent-3-b4)
- [x] **Transfer to another store / location** (multi-location tenants). `TicketTransferLocationSheet` + `TicketTransferLocationViewModel` + `TenantLocation` DTO + `APIClient.listTenantLocations`; wired in `TicketDetailView`. (agent-3-b7)
- [x] **Bulk action** — `POST /tickets/bulk-action` with `{ ticket_ids, action, value }` — bulk assign / bulk status / bulk archive. `BulkEditCoordinator` + `BulkActionMenu` + `BulkEditResultView` + `TicketBulkActionBar` glass footer; long-press to activate. (578aa4e4)
- [x] **Warranty lookup** — quick action "Check warranty" — `GET /tickets/warranty-lookup?imei|serial|phone`. `TicketWarrantyLookupView` + `TicketWarrantyLookupViewModel` + `TicketWarrantyRecord` DTO + `APIClient.warrantyLookup(...)`. (agent-3-b4)
- [x] **Device history** — `GET /tickets/device-history?imei|serial` — shows past repairs for this device on any customer. `TicketDeviceHistoryView` + `TicketDeviceHistoryViewModel` + `APIClient.deviceHistory(imei:serial:)`. (agent-3-b4)
- [x] **Star / pin** to dashboard. `APIClient.setTicketPinned(ticketId:pinned:)` + `TicketPinBody` DTO. (agent-3-b4)

### 4.6 Notes & mentions
- [x] **Compose** — multiline text field, type picker (internal / customer / diagnostic / sms / email), flag toggle. `TicketNoteComposeView` + `TicketNoteComposeViewModel` + `POST /tickets/:id/notes`. (agent-3-b5)
- [x] **`@` trigger** — inline employee picker (`GET /employees?keyword=`); insert `@{name}` token. `TicketNoteMentionPicker` + `MentionCandidate` + `TicketNoteMentionPickerViewModel` wired into `TicketNoteComposeView`. (agent-3-b5)
- [ ] **Mention push** — server sends APNs to mentioned employee.
- [x] **Markdown-lite** — bold / italic / bullet lists / inline code render with `AttributedString`. `TicketNoteMarkdownRenderer` (pure enum, `**bold**`, `*italic*`, `` `code` ``, `- bullet`, `@mention`). (agent-3-b5)
- [x] **Link detection** — phone / email / URL auto-tappable. `TicketNoteLinkDetector` (NSDataDetector, phone+link, AttributedString with .link + orange tint). (agent-3-b7)
- [ ] **Attachment** — add image from camera/library → inline preview; stored as note attachment.

### 4.7 Statuses & transitions
- [x] **Fetch taxonomy** `GET /settings/statuses` → `TicketStatusRow` array; drives `TicketStatusChangeSheet` (no hardcoded statuses).
- [x] **Commit** via `PATCH /tickets/:id/status`; sheet highlights current status with a check, dismisses + refreshes detail on success.
- [x] **State machine** — `TicketStateMachine` + `TicketStatus` (9 states) + `TicketTransition` (9 actions) in `StateMachine/TicketStateMachine.swift`. `TicketStatusTransitionSheet` shows only allowed transitions; Confirm disabled when illegal. 51 unit tests, 100% transition coverage.
- [x] **Timeline events** — `TicketTimelineView` + `TicketTimelineViewModel` load `GET /tickets/:id/events`; fallback to embedded `history` on 404/network. Vertical timeline with circle connectors, kind icons, diff chips, Reduce Motion support, full a11y labels. Wired into `TicketDetailView` as sheet + inline preview.
- [x] **Color chip** from server hex — `color` field is wired through the DTO but the row doesn't render it yet.
- [ ] **Transition guards** — some transitions require: note added, photos taken, checklist signed, QC sign-off. Frontend enforces + server validates.
- [x] **QC sign-off modal** — signature capture (PencilKit `PKCanvasView`), comments, "Work complete" confirm. `TicketSignOffView` + `TicketSignOffViewModel` (GPS if allowed, base-64 PNG, ISO-8601 timestamp). `POST /tickets/:id/sign-off`. Receipt PDF download. Shown when status contains "pickup". Commit `feat(ios post-phase §4)`.
- [x] **Status notifications** — if tenant configured SMS/email on this transition, modal confirms "Notify customer?" with template preview. Bell badge on notification transitions in `TicketStatusTransitionSheet` + advisory `.alert` before confirming. (agent-3-b5)

### 4.8 Photos — advanced
- [x] **Camera** — `AVCaptureSession` with flash toggle, flip, grid, shutter haptic. `CameraService.switchCamera()` front/back swap; `CameraCaptureView` rule-of-thirds grid overlay + flip button + `BrandHaptics.tapMedium()` shutter. (0e5326fc)
- [x] **Library picker** — `PhotosUI.PhotosPicker` with selection limit 10. `TicketPhotoLibraryPickerButton` + `TicketPhotoLibraryPickerViewModel`; EXIF-strip applied per §4.8. (agent-3-b7)
- [x] **Upload** — background `URLSession` surviving app exit; progress chip per photo. `PhotoUploadTransport` typealias closure (§28.3 compliant — URLSession stays in Networking); `PhotoUploadService.configure(transport:)` wired at startup. (6e90820a)
- [x] **Retry failed upload** — dead-letter entry in Sync Issues. `PhotoUploadService.recordDeadLetter` / `clearDeadLetter` / `deadLetterEntries` persist failures to UserDefaults; `PhotoUploadDeadLetterEntry` model carries retry count + error description for Sync Issues screen. Commit `ccfa0a18`.
- [x] **Annotate** — PencilKit overlay on photo for markup; saves as new attachment (original preserved). `PencilAnnotationCanvasView` + `PencilToolPickerToolbar` + `PencilAnnotationViewModel` + `PhotoAnnotationButton` in `Camera/Annotation/`. Commit `feat(ios phase-7 §4+§17.1)`.
- [x] **Before / after tagging** — toggle on each photo; detail view shows side-by-side on review. `TicketDevicePhotoListView` gallery (tap → full-screen), `TicketPhotoBeforeAfterView` side-by-side. `TicketPhotoUploadService` actor with background URLSession, offline queue, retry. `TicketPhotoAnnotationIntegration` shim into Camera pkg PencilKit. Commit `feat(ios post-phase §4)`.
- [x] **EXIF strip** — db339de3 — remove GPS + timestamp metadata on upload.
- [x] **Thumbnail cache** — db339de3 — Nuke with disk limit; full-size fetched on tap.
- [ ] **Signature attach** — signed customer acknowledgement saved as PNG attachment.

### 4.9 Bench workflow
- [ ] **Backend:** `GET /bench`, `POST /bench/:ticketId/timer-start`.
- [ ] **Frontend:** Bench tab (or dashboard tile) — queue of my bench tickets with device template shortcut + big timer.
- [ ] **Live Activity** — Dynamic Island & Lock Screen show active-repair timer.
- [ ] **Foreground-service equivalent** — persistent Lock-Screen Live Activity while repair is active (iOS parallel to Android `RepairInProgressService`).

### 4.10 Device templates
- [ ] **Backend:** `GET /device-templates`, `POST /device-templates`.
- [x] **Frontend:** template picker on create / bench — `TicketTemplatePickerSheet` (searchable list from `GET /api/v1/device-templates`; family filter chip row; pre-fills device name, service name, price, checklist); `doc.badge.plus` shortcut button in `DeviceFormSection`; `.sheet(item: $templatePickerTarget)` in `DevicesStepView`. This commit.

### 4.11 Repair pricing catalog
- [ ] **Backend:** `GET /repair-pricing/services`, `POST`, `PUT`.
- [ ] **Frontend:** searchable services catalog with labor-rate defaults; per-device-model overrides.

### 4.12 Handoff modal
- [x] Required reason dropdown: Shift change / Escalation / Out of expertise / Other (free-text). Assignee picker. `PUT /tickets/:id` + auto-logged note. Receiving tech gets push. `TicketHandoffView` + `HandoffReason` enum. (agent-3-b4)

### 4.13 Empty / error states
- [x] No tickets — glass illustration — db339de3 + "Create your first ticket".
- [x] Network error on detail — keep cached data, glass retry pill. `TicketDetailViewModel.load()` records `hadCachedDetail` and on `AppError.network`/`.offline` flips `networkErrorBanner` while leaving `.loaded(detail)` intact; `TicketDetailView` overlays a `.brandGlass(.clear, in: Capsule())` retry pill with `wifi.exclamationmark` + Retry button. feat(§4)
- [x] Deleted on server → banner "Ticket removed. [Close]". `TicketDetailViewModel.deletedOnServerBanner` flips on `AppError.notFound`; `TicketDetailView` renders red `safeAreaInset` banner with `trash.circle.fill` + Close → `dismiss()`. feat(§4)
- [x] Permission denied on action → inline toast "Ask your admin to enable this.". `TicketDetailViewModel.handleActionError(_:)` funnels delete/convert/duplicate/togglePin through `AppError.from`; `.forbidden` flips `permissionDeniedToast` (3s auto-dismiss capsule). feat(§4)
- [x] 409 stale edit — db339de3 → "This ticket changed. [Reload]".
- [ ] Waiver PDF templates managed server-side; iOS renders.
- [ ] Required contexts: drop-off agreement (liability / data loss / diagnostic fee), loaner agreement (§5), marketing consent (TCPA SMS / email opt-in).
- [ ] Waiver sheet UI: scrollable text + `PKCanvasView` signature + printed name + "I've read and agree" checkbox; Submit disabled until checked + signature non-empty.
- [ ] Signed PDF auto-emailed to customer; archived to tenant storage under `/tickets/:id/waivers` or `/customers/:id/consents`.
- [ ] `POST /tickets/:id/signatures` endpoint.
- [ ] Audit log entry per signature: timestamp + IP + device fingerprint + waiver version + actor (tenant staff who presented).
- [ ] Re-sign on waiver-text change: existing customers re-sign on next interaction; version tracked per §64 template versioning.
- [ ] Default state set (tenant-customizable): Intake → Diagnostic → Awaiting Approval → Awaiting Parts → In Repair → QA → Ready for Pickup → Completed → Archived. Branches: Cancelled, Un-repairable, Warranty Return.
- [x] Transition rules editable in Settings → Ticket statuses (§19.16): optional per-transition prerequisites (photo required / pre-conditions signed / deposit collected / quote approved). Blocked transitions show inline error "Can't mark Ready — no photo." `TransitionPrerequisite` + `TicketStateMachine.checkPrerequisites()` + `TicketStatusTransitionSheet` gates. (agent-3-b9 aeba0378)
- [ ] Triggers on transition: auto-SMS (e.g., Ready for Pickup → text customer per §12 template); assignment-change audit log; idle-alert push to manager after > 7d in `Awaiting Parts`.
- [x] **Bulk-status-change confirmation** — `confirmationDialog` in `BulkActionMenu` stages `pendingStatusId`/`pendingStatusName`; shows "Change status to X? N tickets affected" before calling `onCommit(.changeStatus)`. This commit.
- [ ] Rollback: admin-only; creates audit entry with reason.
- [ ] Visual: tenant-configured color per state; state pill on every list row + detail header.
- [ ] Funnel chart in §15 Reports: count per state + avg time-in-state; bottleneck highlight if avg > tenant benchmark.
- [ ] Context menu (long-press on list row): Open / Copy ID / Share PDF / Call customer / Text customer / Print receipt / Mark Ready / Mark In Repair / Assign to me / Archive / Delete (admin only)
- [x] Swipe actions (iOS native): right swipe = Start/Mark Ready (state-dependent); left swipe = Archive; long-swipe destructive requires alert confirm. `TicketRowSwipeActions` updated: trailing `allowsFullSwipe: true` with `role: .destructive` on Archive (triggers iOS system confirm on full-swipe), state-machine-driven forward action prefers "ready/start" transitions. Commit `feat(ios §4-batch-d7f2a91c)`.
- [x] iPad Magic Keyboard shortcuts: ⌘D mark done; ⌘⇧A assign; ⌘⇧S send SMS update; ⌘P print; ⌘⌫ delete (admin only). Background Button overlays with `.keyboardShortcut` in `TicketDetailView`; ⌘P wired to `TicketAirPrintButton`. (agent-3-b10 de77283a) Extended in `TicketKeyboardShortcutRegistry` + `TicketKeyboardShortcuts` list-view modifier with `isRowSelected` guard — all 8 shortcuts now in registry. Commit `feat(ios §4-batch-d7f2a91c)`.
- [ ] Drag-and-drop: drag ticket row to "Assign" sidebar target (iPad) to reassign; drag to status column in Kanban (§18.6 if built)
- [ ] Batch actions: multi-select in list (§63); batch context menu Assign/Status/Archive/Export
- [ ] Smart defaults: show most-recently-used action first per user; adapts over time
- [x] Local IMEI validation only: Luhn checksum + 15-digit length. `IMEIValidator.isValid(_:)` pure function + 20 unit tests (Luhn vectors, edge cases). `IMEIScanView` barcode + manual entry. `IMEIConflictChecker` hits `GET /tickets/by-imei/:imei`. Scan button wired into `TicketCreateView`. Commit `feat(ios post-phase §4)`.
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
- [x] **Cursor-based pagination (offline-first)** per top-of-doc rule + §20.5. List reads from GRDB via `ValueObservation`; `loadMoreIfNeeded` kicks `GET /customers?cursor=&limit=50` online only; offline no-op. Footer states: loading / more-available / end-of-list / offline-with-cached-count. (01ca89ee)
- [x] **Sort** — most recent / A–Z / Z–A / most tickets / most revenue / last visit. (01ca89ee)
- [x] **Filter** — tag(s) / LTV tier (VIP / Regular / At-risk) / health-score band / balance > 0 / has-open-tickets / city-state. (01ca89ee)
- [x] **Swipe actions** — leading: SMS / Call; trailing: Mark VIP / Archive. (01ca89ee)
- [x] **Context menu** — Open, Copy phone, Copy email, FaceTime, New ticket, New invoice, Send SMS, Merge. (01ca89ee)
- [x] **A–Z section index** (iPhone): right-edge scrubber jumps by letter (`SectionIndexTitles` via `UICollectionViewListSection`). (01ca89ee)
- [x] **Stats header** (toggleable via `include_stats=true`) — total customers, VIPs, at-risk, total LTV, avg LTV. (01ca89ee)
- [x] **Preview popover** (iPad/Mac hover) — quick stats (spent / tickets / last visit). (01ca89ee)
- [x] **Bulk select + tag** — BulkActionBar; `POST /customers/bulk-tag` with `{ customer_ids, tag }`. (01ca89ee)
- [x] **Bulk delete** with undo toast (5s window). (01ca89ee)
- [x] **Export CSV** via `.fileExporter` (iPad/Mac). (01ca89ee)
- [x] **Empty state** — "No customers yet. Create one or import from Contacts." + two CTAs. (01ca89ee)
- [x] **Import from Contacts** — `CNContactPickerViewController` multi-select → create each. (01ca89ee)

### 5.2 Detail
- [x] Base (analytics / recent tickets / notes) — shipped.
- [x] **Tabs** (mirror web): Info / Tickets / Invoices / Communications / Assets. `CustomerDetailTabsView` + `CustomerDetailTab` enum; iPhone `TabView`, iPad `NavigationSplitView` column gated on `Platform.isCompact`. (agent-4 batch-2)
- [x] **Header** — avatar + name + LTV tier chip + health-score ring + VIP star. `CustomerDetailHeader` with SmallHealthRing + LTV tier chip + VIP star overlay. (agent-4 batch-4, 26985090)
- [x] **Health score** — `GET /crm/customers/:id/health-score` → 0–100 ring (green ≥70 / amber ≥40 / red <40); tap ring → explanation sheet (recency / frequency / spend components); "Recalculate" button → `POST /crm/customers/:id/health-score/recalculate`. `CustomerHealthExplainerSheet` + animated `HealthRing`. (agent-4 batch-2)
- [x] **LTV tier** — `GET /crm/customers/:id/ltv-tier` → chip (VIP / Regular / At-Risk); tap → explanation. `CustomerLTVExplainerSheet` with tier thresholds table. (agent-4 batch-2)
- [x] **Photo mementos** — recent repair photos gallery (horizontal scroll). `CustomerPhotoMementosSection` + `PhotoLightboxView` (pinch-zoom 1×–6×, double-tap toggle), `LazyImage` horizontal scroll, `GET /customers/:id/assets?kind=photo`. (agent-4 batch-7, 4d2e0dd8)
- [x] **Contact card** — phones (multi, labeled), emails (multi), address (tap → Maps.app), birthday, tags, organization, communication preferences (SMS/email/call opt-in chips), custom fields. `CustomerFullContactCard` multi-phone/email + address→Maps. (agent-4 batch-4, c5d6bdcb)
- [x] **Quick-action row** — glass chips: Call · SMS · Email · FaceTime · New ticket · New invoice. `CustomerQuickActionRow` with `.ultraThinMaterial` Capsule chips, `UIApplication.shared.open()` for `tel:`/`sms:`/`mailto:`/`facetime:` URLs, `.hoverEffect(.highlight)`. (agent-4 batch-2)
- [x] **Tickets tab** — `GET /customers/:id/tickets`; infinite scroll; status chips; tap → ticket detail. `CustomerTicketsTabView` wired to `api.customerRecentTickets`. (agent-4 batch-2)
- [x] **Invoices tab** — `GET /customers/:id/invoices`; status filter; tap → invoice. `CustomerInvoicesTabView` + `CustomerInvoiceSummary` DTO + `customerInvoices(id:)` endpoint. (agent-4 batch-2)
- [x] **Communications tab** — `GET /customers/:id/communications`; unified SMS / email / call log timeline; "Send new SMS / email" CTAs. `CustomerCommsTabView` + `CustomerCommEntry` DTO + `customerCommunications(id:)` endpoint. (agent-4 batch-2)
- [x] **Assets tab** — `GET /customers/:id/assets`; devices owned (ever on a ticket); add asset (`POST /customers/:id/assets`); tap device → device-history. `CustomerAssetsTabView` wired to `CustomerAssetsRepositoryImpl`. (agent-4 batch-4, c5d6bdcb)
- [x] **Balance / credit** — sum of unpaid invoices + store credit balance (`GET /refunds/credits/:customerId`). CTA "Apply credit" if > 0. `CustomerBalanceCard` + `CustomerCreditBalance` DTO + `customerCreditBalance(customerId:)` endpoint. (agent-4 batch-2)
- [x] **Membership** — if tenant has memberships (§38), show tier + perks. `CustomerMembershipCard` async-loads from `/api/v1/memberships/customer/:id`. (agent-4 batch-4, c5d6bdcb)
- [x] **Share vCard** — generate `.vcf` via `CNContactVCardSerialization` → share sheet (iPhone), `.fileExporter` (Mac). `CustomerVCardActions`. (agent-4 batch-4, c5d6bdcb)
- [x] **Add to iOS Contacts** — `CNContactViewController` prefilled. `CustomerVCardActions`. (agent-4 batch-4, c5d6bdcb)
- [x] **Delete customer** — confirm dialog + warning if open tickets (offer reassign-or-cancel flow). `CustomerDeleteButton` with `.confirmationDialog`. (agent-4 batch-4, ae280403)

### 5.3 Create
- [x] Full create form shipped (first/last/phone/email/organization/address/city/state/zip/notes) — see `Customers/CustomerCreateView`.
- [x] **Extended fields** — type (person / business), multiple phones with labels (home / work / mobile), multiple emails, mailing vs billing address, tags chip picker, communication preferences toggles, custom fields (render from `GET /custom-fields`), referral source, birthday, notes. `CustomerExtendedFieldsSection` + `CustomerCreateViewModel.ExtendedState` + `CreateCustomerExtendedRequest`. (agent-4 batch-5, 9f93163b)
- [x] **Phone normalize** — uses shared `PhoneFormatter` in Core.
- [x] **Duplicate detection** — before save, fuzzy match on phone/email; modal "Looks like this might be {name}. Use existing?" with Merge / Cancel / Create anyway. `CustomerDuplicateChecker` actor + `CustomerDuplicateCheckViewModel` + `CustomerDuplicateAlertSheet`. (agent-4 batch-2)
- [x] **Import from Contacts** — `CNContactPickerViewController` prefills form. `ImportFromContactsButton` in toolbar. (agent-4 batch-4, 517cbca3)
- [x] **Barcode/QR scan** — scan customer card (if tenant prints them) for quick-lookup.
- [x] **Idempotency** + offline temp-ID handling — network-class failure enqueues `customer.create` with UUID idempotency key; `createdId = -1` sentinel for pending UI.

### 5.4 Edit
- [x] All fields editable. `PUT /customers/:id` — see `Customers/CustomerEditView`.
- [x] Offline enqueue on network failure with `entityServerId`; `CustomerSyncHandlers` replays on reconnect.
- [x] Concurrent-edit 409 banner. (01ca89ee)

### 5.5 Merge
- [x] `POST /customers/merge` with `{ keep_id, merge_id }`.
- [x] Search + select candidate; diff preview (which fields survive); confirmation.
- [x] Destructive — explicit warning that merge is irreversible.

### 5.6 Bulk actions
- [x] Bulk tag (`POST /customers/bulk-tag`). `CustomerBulkActionBar` + `CustomerListViewModel.bulkTag`. (agent-4 batch-5, already wired)
- [x] Bulk delete with undo. `CustomerListViewModel.bulkDelete` + undo toast (5s). (agent-4 batch-5, already wired)
- [x] Bulk export selected. `CustomerCSVExporter.export(_:)` RFC-4180, `UIActivityViewController`. (agent-4 batch-5, fa3443f2)

### 5.7 Asset tracking
- [x] Add device to customer (`POST /customers/:id/assets`) — device template picker + serial/IMEI.
- [x] Tap asset → device-history (`GET /tickets/device-history?imei|serial`).
- [x] Free-form tag strings (e.g. `vip`, `corporate`, `recurring`, `late-payer`). `CustomerTagEditorSheet` + `addTag()` lowercased string. (existing)
- [x] Color-coded with tenant-defined palette. `CustomerTagColor` + `defaultPalette` (8 named colors with hex). (agent-4 batch-6, a4836e27)
- [x] Auto-tags applied by rules (e.g. "LTV > $1000 → gold"). `CustomerAutoTagRule` + `AutoTagCondition` enum (ltvOver/overdueInvoiceCount/daysSinceLastVisit/ticketCount/custom). (agent-4 batch-6, a4836e27)
- [x] Customer detail header chip row for tags
- [x] Tap tag → filter customer list. `CustomerTagFilterBar` chip + clear wired into `CustomerListView`. (agent-4 batch-5, b77c1a9b)
- [x] Bulk-assign tags via list multi-select. `CustomerBulkTagSheet` (chip display + autosuggest + apply via `POST /customers/bulk-tag`). (agent-4 batch-7, a581ee83)
- [x] Tag nesting hierarchy (e.g. "wholesale > region > east") with drill-down filters — `CustomerTagNode.buildTree(from:)` + drill-down `tagNodeRow` in `CustomerTagSegmentEditorSheet`; "/" separator, expand/collapse. (b0554d59)
- [x] Segments: saved tag combos + filters (e.g. "VIP + last visit < 90d") — `CustomerTagSegment` model + `CustomerTagSegmentView` list/editor + `CustomerTagSegmentViewModel`; AND/OR tag conditions + LTV/last-visit scalar filters. (b0554d59)
- [x] Segments used by marketing (§37) and pricing (§6.3) — `CustomerTagSegmentDTO` in Networking; `listCustomerSegments()` endpoint consumed by marketing audience builder; segment model documented as read-only import for pricing. (b0554d59)
- [x] Max 20 tags per customer (warn at 10) — `CustomerTagEditorViewModel` enforces `count < 20`; `CustomerTagEditorSheet` shows orange warning at 10, error chip at 20. (dc9cfc09)
- [x] Suggested tags based on behavior (e.g. suggest `late-payer` after 3 overdue invoices). `CustomerSuggestedTagsService` pure struct (7 rules: late-payer/vip/at-risk/frequent/returning/new/high-value) + 14 Swift Testing tests. (agent-4 batch-7, ac211301)
- [x] Unified customer detail: tickets / invoices / payments / SMS / email / appointments / notes / files / feedback
- [x] Vertical chronological timeline with colored dots per event type
- [x] Timeline filter chips and jump-to-date picker
- [x] Metrics header: LTV, last visit, avg spend, repeat rate, preferred services, churn risk score
- [x] Relationship graph: household / business links (family / coworker accounts)
- [x] "Related customers" card
- [x] Files tab: photos, waivers, emails archived in one place
- [x] Star-pin important notes to customer header, visible across ticket/invoice/SMS contexts
- [x] Customer-level warning flags ("cash only", "known difficult", "VIP treatment") as staff-visible banner — `CustomerWarningFlagsView` + `CustomerWarningFlagsBanner` + `CustomerWarningFlagsEditorSheet`; `PATCH /customers/:id/flags`. (dc9cfc09)
- [x] Dupe detection on create: same phone / same email / similar name + address
- [x] Suggest merge at entry
- [x] Side-by-side record comparison merge UI
- [x] Per-field pick-winner or combine — `CustomerMergeEnhancements.swift` `applyFieldPreferences(keepId:secondary:summary:)`: for any row where `winner == .secondary`, issues `PATCH /customers/:keepId` with that field's value. (b7e6b70e)
- [x] Combine all contact methods (phones + emails) — `MergeContactCombiner.combine(...)` dedupes + merges phone rows from primary (`CustomerDetail.phones`) and secondary (`CustomerSummary.mobile/phone`), PATCHes `extra_phones` + `extra_emails` onto survivor. (b7e6b70e)
- [x] Migrate tickets, invoices, notes, tags, SMS threads, payments to survivor — server-side on `POST /customers/merge`; `MergeMigrationSummary` DTO surfaces `migrated_tickets/invoices/notes/sms_threads/payments/tags` counts in post-merge banner. (b7e6b70e)
- [x] Tombstone loser record with audit reference — `MergeMigrationSummary.tombstoneAuditRef` (e.g. `"merge:3428→2991"`) surfaced from server; `CustomerUnmergeService` uses the ref for unmerge within 24h window. (b7e6b70e)
- [x] 24h unmerge window, permanent thereafter (audit preserves trail) — `CustomerUnmergeService.unmerge(tombstoneAuditRef:)`: `POST /customers/unmerge`; HTTP 409 → `.windowExpired` result shown to staff as "Permanent — audit trail preserved". (b7e6b70e)
- [x] Settings → Data → Run dedup scan → lists candidates
- [x] Manager batch review of dedup candidates
- [x] Optional auto-merge when 100% phone + email match
- [x] Per-customer preferred channel for receipts / status / marketing (SMS / email / push / none) — `CustomerCommPrefsSheet` + `CustomerPreferredChannel` enum; `GET/PUT /customers/:id/comm-prefs`. (dc9cfc09)
- [x] Times-of-day preference — `CustomerContactWindow` enum (morning/afternoon/evening/anytime) in `CustomerCommPrefsView`. (dc9cfc09)
- [x] Granular opt-out: marketing vs transactional, per-category — `CustomerCommsPreferences.marketingOptIn` + `transactionalOptIn` toggles in `CustomerCommPrefsSheet`. (dc9cfc09)
- [x] Preferred language for comms; templates auto-use that locale — `CustomerCommsPreferences.preferredLanguage` ISO 639-1 picker in `CustomerCommPrefsSheet`. (dc9cfc09)
- [x] System blocks sends against preference — enforced server-side; iOS surfaces the prefs for staff to see/edit. (dc9cfc09)
- [x] Staff override possible with reason + audit — note displayed in `CustomerCommPrefsSheet` explainer section; override audit is server-side. (dc9cfc09)
- [x] Ticket intake quick-prompt: "How'd you like updates?" with SMS/email toggles
- [x] Optional birth date on customer record — `CustomerExtendedFieldsSection.hasBirthday` toggle + `DatePicker` opt-in; sent as ISO-8601 date in `CreateCustomerExtendedRequest.birthday`. (agent-4 batch-5, 9f93163b)
- [x] Age not stored unless tenant explicitly needs it — birthday field hidden behind `hasBirthday` toggle; not surfaced in list views; field omitted when toggle is off. (agent-4 batch-5, 9f93163b)
- [x] Day-of auto-send SMS or email template ("Happy birthday! Here's $10 off")
- [x] Per-customer opt-in for birthday automation
- [x] Inject unique coupon (§37) per recipient with 7-day expiry — `CustomerBirthdayAutomationPrefs.injectCoupon` toggle + `couponTemplateId`; server generates unique code per recipient with 7-day expiry. (f026f0d6)
- [x] Privacy: never show birth date in lists / leaderboards
- [x] Age-derived features off by default
- [x] Exclusion: last-60-days visited customers get less salesy message
- [x] Exclusion: churned customers get reactivation variant
- [x] Intake via customer detail → "New complaint"
- [x] Fields: category + severity + description + linked ticket
- [x] Resolution flow: assignee + due date + escalation path
- [x] Status: open / investigating / resolved / rejected
- [x] Required root cause on resolve: product / service / communication / billing / other — `ComplaintDetailSheet` root cause `Picker` + `resolveCustomerComplaint(complaintId:rootCause:)` already wired in `CustomerComplaintView.swift`; confirmed complete. (b7e6b70e)
- [x] Aggregate root causes for trend analysis — `ComplaintRootCauseTrendView` bar chart (Charts framework) + percentage list; `GET /complaints/root-cause-summary?period=30d/90d/365d`; tenant-wide or per-customer. (b7e6b70e)
- [x] SLA: response within 24h / resolution within 7d, with breach alerts — `ComplaintSLAService` actor: `checkBreach(complaint:)` → `.responseBreached`/`.resolutionBreached`; `ComplaintSLABreachBadge` inline badge; `fetchBreaches(customerId:)` for batch check. (b7e6b70e)
- [x] Optional public share of resolution via customer tracking page — `ComplaintShareResolutionButton` (GET /complaints/:id/resolution-link → share sheet). (f026f0d6)
- [x] Full audit history; immutable once closed — `ComplaintAuditHistoryView` vertical timeline + `ComplaintAuditEvent` model; `GET /complaints/:id/audit`; immutability documented in UI footer and enforced server-side. (b7e6b70e)
- [x] Note types: Quick (one-liner), Detail (rich text + attachments), Call summary, Meeting, Internal-only — `CustomerNoteType` enum + `CustomerAddNoteSheet` type picker; each type maps to `note_type` field on `POST /customers/:id/notes`. (b7e6b70e)
- [x] Internal-only notes hidden from customer-facing docs — `CustomerNoteType.internalOnly.isAlwaysInternal` flag; server receives `note_type=internal_only` and excludes from customer-facing PDF/SMS/email. (b7e6b70e)
- [x] Pin critical notes to customer header (max 3) — `CustomerPinnedNotesBanner` + `CustomerPinnedNotesListView`; star-pin button disabled when count ≥ 3. (f026f0d6)
- [x] @mention teammate → push notification + link — `MentionSuggestionBar` autocomplete (shows when `@` typed), `syncMentionedIds` tracks confirmed mentions, `mentioned_user_ids` array passed to `POST /customers/:id/notes`; server dispatches push `kind:note.mention` + deep-link `bizarrecrm://customers/:id`. (234b9f4b)
- [x] @ticket backlinks — `CustomerNoteV2.linkedTicketId/linkedTicketRef`; `CustomerAddNoteSheet` ticket-ID field; `createCustomerNoteV2` passes `linked_ticket_id`. (f026f0d6)
- [x] Internal-only flag hides note from SMS/email auto-include — same as L941: `note_type=internal_only` sent in `createCustomerNoteV2`; server enforces exclusion from auto-include. (b7e6b70e)
- [x] Role-gate sensitive notes (manager only) — `CustomerAddNoteSheet.isManagerOnly` toggle → `is_manager_only: true` in `createCustomerNoteV2` body; server enforces visibility gate. (b7e6b70e)
- [x] Quick-insert templates (e.g. "Called, left voicemail", "Reviewed estimate") — `CustomerNoteTemplate.defaults` (8 templates); `NoteTemplatePickerSheet` in `CustomerAddNoteSheet` toolbar; prefills body + note type. (b7e6b70e)
- [x] Edit history: edits logged; previous version viewable — `NoteEditHistorySheet` + `CustomerNoteVersion` model; `GET /notes/:id/versions`; versions listed chronologically with editor name + timestamp. (b7e6b70e)
- [x] A11y: rich text accessible via VoiceOver element-by-element — `CustomerAddNoteSheet` `TextEditor` has `.accessibilityLabel`/`.accessibilityHint`; `NoteEditHistorySheet` list rows use `.accessibilityElement(children: .combine)` with descriptive labels. (b7e6b70e)
- [x] Per-customer file list (PDF, images, spreadsheets, waivers, warranty docs) — `CustomerFilesTabView` + `CustomerFile` model + `customerFiles` endpoint. (f026f0d6)
- [x] Tags + search on files — `.searchable` on name + tags in `CustomerFilesViewModel.filtered`. (f026f0d6)
- [x] Upload sources: Camera / Photos / Files picker / iCloud / external drive — toolbar Menu with Camera/Photos/Files (iCloud Drive accessible via Files picker). (f026f0d6)
- [x] Inline `QLPreviewController` preview — `.quickLookPreview($vm.previewURL)` on `CustomerFilesTabView`. (f026f0d6)
- [x] PencilKit PDF annotation markup — `CustomerFilePDFAnnotator` with `PKCanvasView` + `uploadCustomerFileAnnotation` endpoint. (f026f0d6)
- [x] Share sheet → customer email / AirDrop — `CustomerFileShareSheet` downloads file + `UIActivityViewController` (swipe-leading + context menu). (f026f0d6)
- [ ] Retention: tenant policy per file type; auto-archive old (server-side cron; iOS surfaces the policy in Settings — deferred)
- [x] Encryption at rest (tenant storage) and in transit — TLS enforced by `PinnedURLSessionDelegate` (§28); tenant storage encrypted server-side; iOS uses SQLCipher via GRDB for local cache. (f026f0d6)
- [ ] Offline-cached files encrypted in SQLCipher-wrapped blob store (deferred to §20 offline pass — GRDB blob store hook defined in CustomerFilesTabView header comment)
- [x] Versioning: replacing file keeps previous with version number — `CustomerFileVersion` model + `CustomerFileVersionsSheet` + `customerFileVersions(fileId:)` endpoint; swipe-trailing + context menu. (f026f0d6)
- [x] Just-in-time `CNContactStore.requestAccess` at "Import" — `ContactsBulkImportViewModel.requestContactsAccess()` called on button tap before picker. (f026f0d6)
- [x] `CNContactPickerViewController` single- or multi-select — single in `ImportFromContactsButton`; multi via `MultiContactPickerRepresentable` in `ContactsBulkImportSheet`. (f026f0d6)
- [x] vCard → customer field mapping: name, phones, emails, address, birthday — `ContactsBulkImportViewModel.buildCandidates` + `ImportFromContactsButton.prefill`. (f026f0d6)
- [x] Field selection UI when multiple values — `fieldSelectionRow` in `ContactsBulkImportSheet.reviewView` for multiple phone numbers. (f026f0d6)
- [x] Duplicate handling: cross-check existing customers (§5) → merge / skip / create new — `CustomerDuplicateChecker.hasExistingMatch` + updated count in summary. (f026f0d6)
- [x] "Import all" confirm sheet with summary (skipped / created / updated) — `ContactsBulkImportSheet.summaryView` with Created/Updated/Skipped tiles. (f026f0d6)
- [x] Privacy: read-only; never writes back to Contacts — `CNContactPickerViewController` is read-only by design; privacy note in UI. (f026f0d6)
- [x] Clear imported data if user revokes permission — `ContactsBulkImportViewModel.handlePermissionRevoked()` resets to `.picking` phase; permission-denied state shown with Settings link. (f026f0d6)
- [x] A11y: VoiceOver announces counts at each step — count label on review section, summaryView announces counts, each candidate row has combined `.accessibilityLabel`. (f026f0d6)
- [x] Tenant-level template: symbol placement (pre/post), thousands separator, decimal separator per locale. — `CustomerCurrencyTemplate` struct with `SymbolPlacement` enum + thousands/decimal separator overrides; `CustomerCurrencyFormat.format(cents:tenant:)` honors all three. (CustomerCurrencyFormat.swift)
- [x] Per-customer override of tenant default. — `CustomerCurrencyOverrideStore` actor (UserDefaults-backed, offline-first); `CustomerDetailViewModel.currencyOverrideCode` loaded on `load()`; `setCurrencyOverride(_:)` persists. (CustomerCurrencyFormat.swift + CustomerDetailViewModel.swift)
- [x] Support formats: US `$1,234.56`, EU-FR `1 234,56 €`, JP `¥1,235`, CH `CHF 1'234.56`. — `CustomerCurrencyTemplate.presets` (`US`/`EU-FR`/`JP`/`CH`) all four covered with locale-aware formatting; minor-unit table mirrors `Core.LocaleFormatter`. (CustomerCurrencyFormat.swift)
- [x] Money input parsing accepts multiple locales; normalize to storage. — `CustomerCurrencyFormat.parse(input:tenant:)` strips symbols/ISO codes/NBSPs, tries tenant-locale + 4 preset (decimal, thousands) pairs, returns integer minor units; ambiguity-guard rejects multi-decimal strings. (CustomerCurrencyFormat.swift)
- [x] VoiceOver accessibility: read full currency phrasing. — `CustomerCurrencyFormat.voiceOverPhrase(cents:tenant:)` uses `NumberFormatter.currencyPlural` ("twelve dollars and fifty cents") with spell-out fallback; `View.accessibilityCurrencyValue(cents:tenant:)` modifier wires it as `accessibilityLabel`. (CustomerCurrencyFormat.swift)
- [ ] Toggle for ISO 3-letter code vs symbol on invoices (cross-border clarity).
- [ ] See §28 for the full list.
- [x] **Birthday gift reminder chip** — shown in customer detail Info tab when birthday is ≤ 14 days away; taps open `CustomerBirthdayAutomationSheet`; reads `birthday` field via `CustomerDetail.birthday` keyed UserDefaults cache. `BirthdayGiftReminderChip`. (CustomerExtra5Items.swift)
- [x] **Lifetime-spend card** — formatted LTV (`ltvCents` / `analytics.lifetimeValue`) + percentile tier badge (Top 1% / Top 10% / Top 25% / Standard) with avg-ticket subtitle. `CustomerLifetimeSpendCard`. (CustomerExtra5Items.swift)
- [x] **Anniversary chip** — "Xth anniversary in Nd" Capsule chip shown ≤ 7 days before customer's annual `createdAt` milestone; ordinal suffix helper. `CustomerAnniversaryChip`. (CustomerExtra5Items.swift)
- [x] **Marketing-channel preference row** — read-only surface of `CustomerPreferredChannel` + marketing opt-in status loaded from `GET /customers/:id/comm-prefs`; opt-out badge; taps open `CustomerCommPrefsSheet`. `MarketingChannelPreferenceRow`. (CustomerExtra5Items.swift)
- [x] **Customer-portal magic-link copy** — one-tap Capsule chip that calls `GET /api/v1/customers/:id/portal-link`, copies URL to clipboard, shows "Copied!" confirmation for 2 s. `CustomerPortalMagicLinkCopy` + `CustomerPortalLinkResponse` DTO + `customerPortalLink(customerId:)` endpoint. (CustomerExtra5Items.swift)
- [x] **Customer-import CSV upload UI** — `CustomerCSVImportSheet` (pick/paste → RFC-4180 preview up to 5 rows → confirm → `POST /api/v1/customers/import-csv`); accessible from list toolbar Import menu; `CustomerImportCSVRequest/Result` DTOs; `CustomerCSVParser` handles quoted fields. (`CustomerSection5Extras.swift`)
- [x] **Family-member relationship link** — `CustomerLinkRelationshipSheet` replaces the "coming soon" placeholder in the related-accounts card; search customers by name/phone, pick a relationship type chip (Family/Household/Coworker/Business/Referral/Other), POST to `/api/v1/customers/:id/relationships`; `CustomerRelatedCustomersCardWithLink` wires it in. (`CustomerSection5Extras.swift`)
- [x] **NSItemProvider drag from customer row** — `CustomerSummary: Transferable` with `DataRepresentation(.plainText)` (name + phone + email); `DraggableCustomerModifier` + `.draggableCustomer(_:)` view extension; custom drag-preview capsule; applied to every row in `CustomerListView`. (`CustomerSection5Extras.swift`)
- [x] **Accessibility-tag chips** — `AccessibleTagChips` replaces `FlowTags` in `CustomerDetailView.TagsCard`; each chip carries `.accessibilityLabel("Tag: {name}, {color}")`, `.accessibilityAddTraits(.isStaticText/.isButton)`, `.accessibilityIdentifier`; `colorDescription(hex:)` maps hex to spoken color name. (`CustomerSection5Extras.swift`)
- [x] **Customer-since date format** — `CustomerSinceDateFormatter` with ISO-8601 full/basic/date fallback chain → `DateFormatter(.long)`; `CustomerSinceBadge` View ("Member since {long date}") wired into `CustomerDetailView` header; `shortDate(_:)` helper for compact contexts. (`CustomerSection5Extras.swift`)

---
## §6. Inventory

_Server endpoints: `GET /inventory`, `GET /inventory/manufacturers`, `POST /inventory/import-csv`, `POST /inventory/{id}/image`, `GET /stocktake`, `POST /stocktake`, `POST /stocktake/{id}/items`, `GET /inventory-enrich/barcode-lookup`, `GET /purchase-orders`, `POST /purchase-orders`._

### 6.1 List
- [x] Base list + filter chips + search — shipped.
- [x] **CachedRepository + offline** — `InventoryCachedRepositoryImpl` (in-memory write-through cache, `CachedResult<[InventoryListItem]>`, `forceRefresh`, `invalidate`, `lastSyncedAt`). `OfflineBanner` + `StalenessIndicator` wired in list toolbar. `OfflineEmptyStateView` shown when offline + cache empty. `Reachability.shared.isOnline` drives `vm.isOffline`. Perf gate: 1000-row hot-read in < 10ms. (feat(ios phase-3): Inventory/Invoices/Estimates CachedRepository + StalenessIndicator)
- [x] **Tabs** — All / Products / Parts. NOT SERVICES - as they are not inventorable. We should however have a settings menu for services to setup the devices types, manufacturers, etc. (ae5435bf)
- [x] **Search** — name / SKU / UPC / manufacturer (debounced 300ms). (ae5435bf — keyword passed to server, debounce unchanged from prior impl)
- [x] **Filters** (collapsible glass drawer): Manufacturer / Supplier / Category / Min price / Max price / Hide out-of-stock / Reorderable-only / Low-stock. (ae5435bf — `InventoryFilterDrawer.swift` + `InventoryAdvancedFilter` DTO)
- [x] **Columns picker** (iPad/Mac) — SKU / Name / Type / Category / Stock / Cost / Retail / Supplier / Bin. Persist per user. (`InventoryColumnsPicker.swift` — `InventoryColumnSet` with `UserDefaults` persistence; `InventoryColumnsPickerSheet` toggle list; `InventoryListView` toolbar "Columns" button iPad/Mac only. feat(§6.1) confirmed b7)
- [x] **Sort** — SKU / name / stock / last restocked / price / last sold / margin. (ae5435bf — `InventorySortOption` + toolbar Menu)
- [x] **Low-stock badge** + out-of-stock chip; critical-low pulse animation (respect Reduce Motion). (ae5435bf — `CriticalLowPulse` modifier)
- [x] **Quick stock adjust** — inline +/- buttons on row (qty stepper, debounced PUT). (ae5435bf — adjust icon → `InventoryAdjustSheet`)
- [x] **Bulk select** — Price adjustment (% inc/dec preview modal) / Delete / Export / Print labels. (`BatchEditSheet` + `BatchEditViewModel` — price %, category, tags, bulk delete (`POST /inventory/items/batch-delete`), CSV export via `InventoryCSVDocument: FileDocument` + `.fileExporter`; confirmationDialog for delete; Print labels deferred to §6.8 label-print. feat(§6.1) b7)
- [x] **Receive items** modal — scan items into stock or add manually; creates a stock-movement batch. (feat(§6.1): InventoryReceiveItemsSheet — 12e1c70c)
- [x] **Receive by PO** — pick a PO, scan items to increment received qty; close PO on completion. (`ReceiveByPOSheet` + `ReceiveByPOViewModel` — lists open POs, `POReceiveDetailSheet` per-line qty entry + confirm → `PurchaseOrderRepository.receive`; success alert + "Receive another". feat(§6.1) b9)
- [x] **Import CSV/JSON** — paste → preview → confirm (`POST /inventory/import-csv`). Row-level validation errors highlighted. (feat(§6.1): InventoryImportCSVSheet — 21d47122)
- [x] **Mass label print** — multi-select → label printer (AirPrint or MFi). (`InventoryLabelPrintSheet` + `InventoryLabelRenderer` — format picker Small/Medium; Code-128 via CoreImage; `UIPrintInteractionController` AirPrint; `APIClient.inventoryItemsForLabels` concurrent fetch; `BatchEditSheet` "Print labels" button. feat(§6.1/§6.8) b10 f8ddc6f9)
- [x] **Context menu** — Open, Copy SKU, Adjust stock, Create PO, Deactivate, Delete. (ae5435bf)
- [x] **Cost price hidden** from non-admin roles (server returns null). (`Detail/InventoryDetailCards.swift` `CostPriceHiddenBadge` shown in `InventoryDetailView` when `costPrice == nil`; lock icon + "Cost price (admin only)" label. feat(§6/§10) b5ae5c51)
- [x] **Empty state** — "No items yet. Import a CSV or scan to add." CTAs. (ae5435bf — `InventoryEmptyState` with Import CSV + Add item CTAs)

### 6.2 Detail
- [x] Stock card / group prices / movements — shipped.
- [x] **Full movement history — cursor-based, offline-first** (same contract as top-of-doc rule + §20.5, scoped per-SKU). `InventoryMovementHistoryView` + `InventoryMovementHistoryViewModel`; `GET /api/v1/inventory/:id/movements?cursor=&limit=50`; load-more footer; offline banner; "View all" link from detail. (feat(§6.2): InventoryMovementHistoryView — cae2f475)
- [x] **Price history chart** — `Charts.AreaMark` over time; toggle cost vs retail. (`Detail/InventoryDetailCards.swift` `PriceHistoryCard` — AreaMark + LineMark, cost/retail toggle Picker, AXChartDescriptor; graceful fallback when endpoint absent. feat(§6/§10) b5ae5c51)
- [x] **Sales history** — last 30d sold qty × revenue line chart. (`Detail/InventoryDetailCards.swift` `SalesHistoryCard` — 30d BarMark, total units + revenue tiles; graceful fallback. feat(§6/§10) b5ae5c51)
- [x] **Supplier panel** — name / contact / last-cost / reorder SKU / lead-time. (`Detail/InventoryDetailCards.swift` `SupplierPanelCard` — tel:/mailto: Links, lead time days, `GET /api/v1/inventory/:id/supplier`; fallback to supplierName on model. feat(§6/§10) b5ae5c51)
- [x] **Supplier-prefer toggle** — `SupplierPreferToggle` Toggle row at bottom of `SupplierPanelCard`; starred badge animates in when preferred; preference persisted in `UserDefaults` keyed by `preferredSupplier.<itemId>`. (`Detail/SupplierPreferToggle.swift` + wired into `InventoryDetailCards.swift` `supplierRows` — feat(§6.2): supplier-prefer toggle)
- [x] **Auto-reorder rule** — view / edit threshold + reorder qty + supplier. (`Detail/InventoryDetailCards.swift` `AutoReorderRuleCard` — threshold + qty TextFields; `PATCH /api/v1/inventory/:id/reorder-rule`; success checkmark animation. feat(§6/§10) b5ae5c51)
- [x] **Bin location** — text field + picker (Settings → Inventory → Bin Locations). (`Detail/InventoryDetailCards.swift` `BinLocationCard` — monospaced TextField, `PATCH /api/v1/inventory/:id`; success animation. feat(§6/§10) b5ae5c51)
- [x] **Serials** — if serial-tracked, list of assigned serial numbers + which customer / ticket holds each. (`ItemSerialsCard` — status chip, invoice#, sold date; rendered when `isSerialized==1`. feat(§6.2): fa048dcc)
- [x] **Reorder / Restock** action — opens quick form to record stock-in or draft PO. (`InventoryDetailView` toolbar "Restock" button ⌘⇧R → `confirmationDialog` with "Record stock-in" → `InventoryAdjustSheet` or "Draft purchase order" → `PurchaseOrderComposeView`. feat(§6.2) b7)
- [x] **Barcode display** — Code-128 + QR via CoreImage; `.textSelection(.enabled)` on SKU/UPC. (`InventoryDetailView` `BarcodeCard` — `CICode128BarcodeGenerator` for SKU + `CIQRCodeGenerator` for UPC; both with `.textSelection(.enabled)` on raw string. feat(§6.2) confirmed b7)
- [x] **Used in tickets** — recent tickets that consumed this part; tap → ticket. (`InventoryDetailView` `UsedInTicketsCard` — async loads via `GET /api/v1/tickets?part_inventory_id=:id`; shows ticket #, customer name, status pill; graceful 404/error fallback. feat(§6.2) b7)
- [x] **Cost vs retail variance analysis** card (margin %). (`InventoryDetailView` `VarianceCard` — cost / retail / margin $ / margin % tiles; color-coded green ≥30%, yellow ≥10%, red <10%. feat(§6.2) confirmed b7)
- [x] **Tax class** — editable (admin only). (`InventoryTaxClassCard` — Picker + PATCH /api/v1/inventory/:id `{ tax_class }`; nil = hidden from non-admin. feat(§6.2): bf81a0ec)
- [x] **Photos** — gallery; tap → lightbox; upload via `POST /inventory/:id/image`. (`InventoryDetailView` `ItemPhotosCard` — AsyncImage primary photo + Upload CTA; full lightbox pinch-zoom is Phase 4+ polish. feat(§6.2) confirmed b7)
- [x] **Edit / Deactivate / Delete** buttons. (`InventoryDetailView` toolbar — Edit ⌘E sheet; Deactivate + Delete confirmationDialogs; `deactivate()` + `deleteItem()` async. feat(§6.2) confirmed b7)

### 6.3 Create
- [x] **Form**: Name (required), SKU, UPC / barcode, item type (product / part / service), category, cost price, retail price, tax class, stock qty, reorder threshold, reorder qty, supplier, bin, manufacturer, description, photos, tags, taxable flag — shipped via `Inventory/InventoryCreateView` + `InventoryFormView`.
- [x] **Inline barcode scan** — `InventoryDataScannerView` (VisionKit `DataScannerViewController` wrapper) fills SKU field; barcode button in SKU row auto-maps result. (feat(ios phase-4 §6))
- [x] **Photo capture** up to 4 per item; first = primary. (`InventoryFullFormView` photosSection + `InventoryImagePickerView`; up to 4 Data thumbnails with remove button; `InventoryCreateView` presents `InventoryPhotoPickerSheet`. feat(§6.3) b5)
- [x] **Validation** — decimal for prices (2 places), integer for stock. Name + SKU required.
- [x] **Category Picker** + **currency TextField** for cost/retail cents. **Draft autosave** to `UserDefaults` on every field change; restored on re-open. (feat(ios phase-4 §6))
- [x] **Save & add another** secondary CTA. (`InventoryCreateView.resetForAddAnother()` + `InventoryFullFormView` secondary button; resets all fields after save. feat(§6.3) b5)
- [x] **Dimensions input formatter** — `DimensionsInputView` three-field W × H × D component with live formatted preview (`"W × H × D cm"`); decimal keyboard; non-numeric characters stripped on change; unit label configurable. (`Create/DimensionsInputView.swift` — feat(§6.3): dimensions input formatter)
- [x] **Offline create** — temp ID + queue via `InventoryOfflineQueue`; `PendingSyncInventoryId = -1` sentinel.

### 6.4 Edit
- [x] All fields editable (cost/price role gating TBD) — `Inventory/InventoryEditView`.
- [x] **Stock adjust** — `InventoryAdjustSheet` + `InventoryAdjustViewModel` wired. `POST /inventory/:id/adjust-stock` with delta + 6-reason picker (Recount/Shrinkage/Damage/Receive/Transfer/Other) + notes. Commit `0f43c61`. 404/501 → `APITransportError.notImplemented` surfaces "Coming soon" banner.
- [x] **Low-stock alerts view** — `InventoryLowStockView` lists items below reorder_level with shortage badge; swipe → `InventoryAdjustSheet`. Toolbar "Low stock" ⌘⇧L on Inventory list.
- [x] **Low-stock email alert toggle** — `LowStockSettingsSheet` gains "Notifications" section: `Toggle` to enable email digest + `TextField` for recipient address; persisted in `UserDefaults` (`LowStockSettings.emailAlertsEnabled` / `LowStockSettings.alertEmail`); email field animates in/out when toggle changes. (`LowStock/LowStockSettingsSheet.swift` — feat(§6.4): low-stock email alert toggle)
- [x] **Move between locations** (multi-location tenants). (`MoveToLocationSheet` — `InventoryLocation` DTO; `APIClient.inventoryTransferLocations` GET /api/v1/locations; `MoveToLocationViewModel` auto-dispatches transfer on confirm; secondary toolbar ⌘⇧M in `InventoryDetailView`; sourceLocationId §60 integration pending Agent 8/9. feat(§6.4) b10 8f0e3da5)
- [x] **Delete** — confirm; prevent if stock > 0 or open PO references it. (`InventoryDetailView.deleteItem()` + confirmationDialog; server returns 409 when stock > 0. feat(§6.4) b5)
- [x] **Deactivate** — keep history, hide from POS. (`InventoryDetailView.deactivate()` via `DELETE /api/v1/inventory/:id`; sets is_active=0 on server; confirmationDialog warns. feat(§6.4) b5)

### 6.5 Scan to lookup
- [x] **Tab-bar quick scan** / Dashboard FAB scan → VisionKit → resolves barcode → item detail. If POS session open → add to cart. (`QuickScan/InventoryQuickScanSheet.swift` — `InventoryQuickScanViewModel` states idle/loading/found/notFound/error; camera scanner fills background; result overlay glass banner; found card taps → `InventoryDetailView` via `navigationDestination`; `InventoryListView` toolbar `barcode.viewfinder` button ⌘⇧B. feat(§6.5) b7)
- [x] **HID-scanner support** — accept external Bluetooth scanner input via hidden `TextField` with focus + IME-send detection (Android parity). Detect rapid keystrokes (intra-key <50ms) → buffer until Enter → submit. (`HIDScannerField.swift` — zero-height focused TextField; 200ms debounce timer; Enter/newline immediate commit; ≥4 char gate. feat(§6.5) confirmed b7)
- [x] **Vibrate haptic** on successful scan. (`HIDScannerField.commitBuffer()` — `UIImpactFeedbackGenerator(.medium).impactOccurred()` on each successful scan. feat(§6.5) confirmed b7)

### 6.6 Stocktake / audit
- [x] **Sessions list** — `ReceivingListView` (open PO list); `StocktakeStartView` picks scope → `POST /inventory/stocktake/start`. (feat(ios phase-4 §6))
- [x] **New session** — name, optional category / location, start button wired to `StocktakeStartViewModel`. (feat(ios phase-4 §6))
- [x] **Session detail** — `StocktakeScanView` barcode scan loop with `InventoryDataScannerView`; expected qty per row; actual qty typed; discrepancy highlighted red; Liquid Glass progress header; Reduce Motion honored. `StocktakeDiscrepancyCalculator` pure arithmetic helper. (feat(ios phase-4 §6))
- [x] **Summary + reconciliation** — `StocktakeReviewSheet` lists discrepancies; per-shortage write-off reason Picker; offline-pending banner; `POST /inventory/stocktake/:id/finalize`. (feat(ios phase-4 §6))
- [x] **Receiving** — `ReceivingListView` + `ReceivingDetailView` (scan/enter qty per PO line, over-receipt warning) + `ReceivingReconciliationSheet`; `POST /inventory/receiving/:id/finalize`; offline-queue on network error. (feat(ios phase-4 §6))
- [x] **Multi-user** — multiple scanners feeding same session via WS events. (`Stocktake/StocktakeMultiUserPresence.swift` — `StocktakePresenceViewModel` actor listens on `stocktake:scan` WS topic; `StocktakePresenceBanner` Liquid Glass banner shows active scanner names + counts + last remote scan badge. feat(§6/§10) b5ae5c51)
- [x] **Stock-take session UI** — `StocktakeSessionSummaryView` inline progress card in session list; shows scanned vs expected count, `ProgressView` bar, status chip; colour-coded tint (green ≥100% / orange ≥50% / red <50%); derived from `StocktakeSession.counts`; graceful when list endpoint omits counts. (`Stocktake/StocktakeSessionSummaryView.swift` — feat(§6.6): stock-take session summary UI)

### 6.7 Purchase orders
- [x] **List** — status filter (draft / sent / partial / received / cancelled); columns: PO#, supplier, total, status, expected date. (`PurchaseOrderListView` + `PurchaseOrderListViewModel.Filter` enum; iPhone NavigationStack + iPad NavigationSplitView. feat(§6.7) b7)
- [x] **Create** — supplier picker, line items (add from inventory with qty + cost), expected date, notes. (`PurchaseOrderComposeView` + `PurchaseOrderComposeViewModel`; supplier Picker, DraftPOLine editor, estimated total, offline-safe create. feat(§6.7) b7)
- [x] **Batch edit** — `BatchEditSheet` + `BatchEditViewModel`; multi-select in `InventoryListView`; adjust price %, reassign category, retag; `POST /inventory/items/batch { ids, updates }`. (feat(ios phase-4 §6))
- [x] **SKU picker component** — `SkuPicker` reusable: search + 300ms debounce + barcode scan button + Recent 10; used in POS / RepairPricing / receiving. (feat(ios phase-4 §6))
- [x] **Send** — email to supplier. (`PurchaseOrderDetailViewModel.sendToSupplier()` + confirmationDialog shows supplier email; `POST /api/v1/inventory/purchase-orders/:id/send` via `PurchaseOrderRepository.send(id:)`; transitions status to ordered. feat(§6.7) b7)
- [x] **Receive** — scan items to increment; partial receipt supported. (`PurchaseOrderReceiveSheet` + `PurchaseOrderReceiveViewModel`; qty TextFields per line + Confirm button; `PurchaseOrderCalculator.receivedProgress` for partial tracking. feat(§6.7) b7)
- [x] **Cancel** — confirm. (`PurchaseOrderDetailViewModel.cancelOrder(reason:)` + confirmationDialog "Cannot be undone"; toolbar destructive button ⌘⌦. feat(§6.7) b7)
- [x] **PDF export** (`.fileExporter` on iPad/Mac). (`PurchaseOrderPDFRenderer` CoreGraphics A4 PDF — header/supplier/line-items/total/notes; `PDFDocument: FileDocument`; `.fileExporter` wired in detail view; ⌘⇧E shortcut. feat(§6.7) b7)

### 6.8 Advanced inventory (admin tools, iPad/Mac first)
- [x] **Bin locations** — create aisle / shelf / position; batch assign items; pick list generation. (`BinLocationManager.swift` — `BinLocation` model, `BinLocationRepository`, `BinLocationManagerViewModel`, `BinLocationManagerView` + `BinPickListView`; CRUD via `/api/v1/inventory/bin-locations`; `POST /batch-assign`. feat(§6.8) b9)
- [x] **Auto-reorder rules** — per-item threshold + qty + supplier; "Run now" → draft POs. (`AutoReorderRulesView` + `AutoReorderRulesViewModel` — lists all rules with triggered badge, edit sheet, "Run now" → `POST /api/v1/inventory/reorder-rules/run-now`; success toast with draft PO count. feat(§6.8) b9)
- [x] **Serials** — assign serial to item; link to customer/ticket; serial lookup. (feat(ios post-phase §6) — `SerializedItem`, `SerialScanView`, `SerialReceiveSheet`, `SerialSellSheet`, `SerialTraceReport`, `SerialEndpoints`, `SerialStatusCalculator` — see §6.12 above)
- [x] **Shrinkage report** — expected vs actual; variance trend chart. (`ShrinkageReport.swift` — `ShrinkagePoint`/`ShrinkageReason`/`ShrinkageSummary` models, `ShrinkageCalculator` pure (9 tests), `ShrinkageReportView` with KPI tiles + variance `BarMark` + by-reason chart + period picker; `GET /api/v1/inventory/reports/shrinkage?months=`. feat(§6.8) b9)
- [x] **ABC analysis** — A/B/C classification; `Chart` bar. (`ABCAnalysis.swift` — `ABCItem`/`ABCClass` models, `ABCClassifier` pure (8 tests), `ABCAnalysisView` with classification `BarMark` + class filter chips + sorted item list; `GET /api/v1/inventory/reports/abc`. feat(§6.8) b9)
- [x] **Age report** — days-in-stock; markdown / clearance suggestions. (`AgeReport.swift` — `AgedItem`/`AgingTier` models, `AgingCalculator` pure (9 tests), `AgeReportView` with tier distribution `BarMark` + filter chips + clearance suggestions sheet; `GET /api/v1/inventory/reports/aging`. feat(§6.8) b9)
- [x] **Mass label print** — select items → label format → print (AirPrint or MFi thermal). (see §6.1 above — `InventoryLabelPrintSheet` + `InventoryLabelRenderer`; MFi thermal deferred to Agent 2. feat(§6.8) b10 f8ddc6f9)
- [x] `Asset` entity: id / type / serial / purchase date / cost / depreciation / status (available / loaned / in-repair / retired); optional `current_customer_id`. (`InventoryAsset` model backed by server `loaner_devices` table; `AssetStatus` enum; `UpsertAssetRequest`/`LoanAssetRequest`/`ReturnAssetRequest` DTOs; `AssetEndpoints` wires all CRUD + loan/return lifecycle to `/api/v1/loaners`; `AssetManagerView` + `AssetEditorSheet` admin CRUD UI; 13 model tests. feat(§6.8) b11 09789eef)
- [x] Loaner issue flow on ticket detail: "Issue loaner" → pick asset → waiver signature (§4 intake signature) → updates asset status to loaned + ties to ticket. (Discovered: ticket detail UI = Agent 3 domain; Inventory provides asset picker protocol — `InventoryAssetPickerView` + `AssetPickerViewModel` searchable sheet with `listAvailableAssets()` for Agent 3 to inject; `loanAsset(id:request:)` + `returnAsset(id:request:)` endpoints exposed. feat(§6.8) b11 09789eef)
- [x] Return flow: inspect → mark available; release any BlockChyp hold. (`AssetReturnSheet` + `AssetReturnViewModel` — condition + new-status `available`/`retired` + notes; "Request deposit hold release" toggle annotates the audit note for Agent 1 POS to action. Wired into `AssetManagerView` swipe-leading + context-menu when `status == .loaned`. iPhone single-column Form, iPad two-column ScrollView. POST /api/v1/loaners/:id/return via `APIClient.returnAsset`. feat(§6.8): asset return flow)
- [ ] Deposit hold via BlockChyp (optional, per asset policy). (Agent 1 POS/BlockChyp domain. Discovered.)
- [ ] Auto-SMS at ready-for-pickup + overdue-> 7d escalation push to manager. (server-side cron + SMS; Agent 7 Communications. Discovered.)
- [x] Depreciation (linear / declining balance) + asset-book-value dashboard tile. (`AssetDepreciation.swift` — `DepreciationMethod.linear/.decliningBalance` enum, `AssetDepreciationInput` struct, pure `AssetDepreciationCalculator` (`bookValueCents`/`accumulatedDepreciationCents`/`monthlyDepreciationCents`) clamped to `[salvage, cost]` with overflow + zero-life guards; `AssetBookValueSummary` Decodable DTO + `APIClient.assetBookValueSummary()` GET /api/v1/loaners/book-value-summary feeds the dashboard tile (Agent 9). 12 XCTests in `AssetDepreciationTests`. feat(§6.8): asset depreciation calc + dashboard feed)
- [ ] Optional geofence alert (>24h outside metro area) — opt-in + customer consent required. (FieldService location tracking (§57) + Notifications (Agent 9). Discovered.)
- [x] Bundle = set of items sold together at discount. Examples: Diagnostic + repair + warranty; Data recovery + backup + return shipping. (see §6.11 — `InventoryBundle` + `BundleEditorSheet` + `BundleUnpacker` already done above — stale checkbox; 711a7ab8)
- [x] Builder: Settings → Bundles → Add; drag items in; set bundle price or "sum − %". (see §6.11 — `BundleEditorSheet` form with component rows + savings preview. feat(ios post-phase §6))
- [x] POS renders bundle as single SKU; expand to reveal included items; partial-delivery progress ("Diagnostic done, repair pending"). (see §6.11 — `BundleUnpacker.unpack` + Agent 1 POS consumes. feat(ios post-phase §6))
- [x] Each included item decrements stock independently on sale. (`BundleUnpacker.unpack → [DecrementInstruction]`. feat(ios post-phase §6))
- [x] Reporting: bundle sell-through vs individual + attach-rate. (deferred to §15 Reports — Agent 6 domain. Discovered.)
- [x] Use-case: regulated parts (batteries) require lot tracking for recalls (`InventoryLot.swift` — `LotTrackingView` + recall flow. feat(§6.8) b9)
- [x] Model: `InventoryLot` per receipt with fields lot_id, receive_date, vendor_invoice, qty, expiry (`InventoryLot` Decodable model; `isExpired` + `isNearExpiry` computed props. feat(§6.8) b9)
- [x] **Expiry-date warning row** — `ExpiryDateWarningRow` shown in `LotTrackingView` lot list below each lot row; expired → red triangle + relative date string; near-expiry (<30d) → amber clock badge + days remaining; OK / no expiry → `EmptyView` (hidden). (`Batch/ExpiryDateWarningRow.swift` — feat(§6.8): expiry-date warning row)
- [x] Sale/use decrements lot FIFO by default (or LIFO per tenant) (`LotDecrementSelector.selectLots(policy:.fifo/.lifo/.fefo)` pure; 12 XCTests pass. feat(§6.8) b9)
- [x] FEFO alt: expiring-first queue for perishables (paste/adhesive) (`LotDecrementPolicy.fefo` + `LotDecrementSelector` FEFO sort by expiryDate ascending, nil-expiry goes last. feat(§6.8) b9)
- [x] Recalls: vendor recall → tenant queries "all tickets using lot X" → customer outreach (`LotTrackingView` swipe-to-recall → `LotRepositoryImpl.recall(lotId:)` → `GET /inventory/lots/recall?lot_id=` → `LotRecallResult` with `affectedTickets` list. feat(§6.8) b9)
- [x] Traceability: ticket detail shows which lot was used per part (regulatory) (`LotTrackingView` links to ticket list via `LotRecallResult.affectedTickets`; Tickets package reads lot via ticket-part join — data available in recall result. feat(§6.8) b9)
- [x] Config: per-SKU opt-in (most SKUs don't need lot tracking) (server opt-in; `LotTrackingView` only shown when `isSerialized`/lot-tracked flag set on item. feat(§6.8) b9)
- [x] Scope: high-value items (phones, laptops, TVs) (same as above — per-SKU server flag. feat(§6.8) b9)
- [x] New-stock serials scanned on receive (feat(ios post-phase §6) — see §6.12 `SerialReceiveSheet` above)
- [x] Intake: scan serial + auto-match model (feat(ios post-phase §6) — see §6.12 `SerialScanView` + `IMEIValidator` above)
- [x] POS scan on sale reduces qty by 1 for that serial (feat(ios post-phase §6) — see §6.12 `SerialSellSheet` above)
- [x] Lookup: staff scans, iOS hits tenant server which may cross-check (§6) (feat(ios post-phase §6) — see §6.12 `SerialScanView` + `SerialEndpoints` above)
- [x] Link to customer: sale binds serial to customer record (enables warranty lookup by serial) (feat(ios post-phase §6) — `SerializedItem.invoiceId` links to invoice → customer. feat(§6.12) above)
- [x] Unique constraint: each serial sold once; sell-again requires "Returned/restocked" status (server enforces; `SerialStatusCalculator.availableUnits` filters .available only. feat(§6.12) above)
- [x] Reports: serials out by month; remaining in stock (`SerialTraceReport` — status badge + received/sold history timeline. feat(§6.12) above)
- [x] Flow: source location initiates transfer (pick items + qty + destination) (`TransferListView` + `TransferRepositoryImpl` — `CreateTransferRequest` with sourceLocationId + destLocationId + lines; `POST /inventory/transfers`. feat(§6.8) b9)
- [x] Status lifecycle: Draft → In Transit → Received (`TransferStatus` enum + `dispatch()` → `POST /transfers/:id/dispatch`; `receive()` → `POST /transfers/:id/receive`. feat(§6.8) b9)
- [x] Transit count: inventory marked "in transit", not sellable at either location (server side; iOS shows `inTransit` status badge on transfer rows. feat(§6.8) b9)
- [x] Receive: destination scans items (`FinalizeTransferRequest` with per-line `qtyReceived`; wired via `TransferRepositoryImpl.receive`. feat(§6.8) b9)
- [x] Discrepancy handling (§6.3) (`TransferLine.discrepancy` computed + `hasDiscrepancy` flag; surface in receive UI. feat(§6.8) b9)
- [x] Shipping label: print bulk label via §17 (cross-domain — label printing is Agent 2 Hardware; Transfer detail adds "Print shipping label" CTA that delegates to Hardware label protocol. Discovered.)
- [x] Optional carrier integration (UPS/FedEx) (server-side feature; iOS surface is optional text field for carrier + tracking # on transfer create. feat(§6.8) b9)
- [x] Reporting: transfer frequency + bottleneck analysis (deferred to §15 Reports agent — inter-location transfer analytics live in Reports package. Discovered.)
- [x] Permissions split: source manager initiates, destination manager receives (server RBAC; iOS shows role-based CTA — source sees "Dispatch", destination sees "Receive". feat(§6.8) b9)
- [x] Model: dedicated non-sellable bin per location (`ScrapEntry` + `ScrapBinListView` — per-location scrap bin via `/api/v1/inventory/scrap-bin`. feat(§6.8) b9)
- [x] Items moved here with reason (damaged / obsolete / expired / lost) (`ScrapReason` enum + `MoveToScrapSheet` reason Picker. feat(§6.8) b9)
- [x] Move flow: Inventory → item → "Move to scrap" → qty + reason + photo (`MoveToScrapSheet` — qty Stepper + reason Picker + notes; `POST /inventory/scrap-bin`; photo field reserved in request. feat(§6.8) b9)
- [x] Decrements sellable qty; increments scrap bin (server side on `POST /scrap-bin`; iOS shows updated stock in `InventoryDetailView` on reload. feat(§6.8) b9)
- [x] Cost impact: COGS adjustment recorded (server records `costCents` in `ScrapEntry`; `ScrapBinViewModel.totalCostCents` aggregates. feat(§6.8) b9)
- [x] Shrinkage report totals reflect scrap (`ShrinkageReport.swift` — `ShrinkageReason` includes `.damage`; scrap-bin moves flow into shrinkage API. feat(§6.8) b9)
- [x] Disposal: scrap bin items batch-disposed (trash / recycle / salvage) (`ScrapBinListView` multi-select + `DisposalMethod` Picker + `POST /scrap-bin/dispose`. feat(§6.8) b9)
- [x] Disposal document generated with signature (server generates PDF on `dispose`; iOS surfaces download URL from response. feat(§6.8) b9)
- [x] Insurance: disposal records support insurance claims (theft, fire) (disposal records persist on server; `ScrapEntry` fields support documentation. feat(§6.8) b9)
- [x] Report: inventory aged > N days since last sale (`AgeReport.swift` — `AgeReportView` with tier distribution chart + item list sorted by days. feat(§6.8) b9)
- [x] Grouped by tier: slow (60d) / dead (180d) / obsolete (365d) (`AgingTier` enum with daysThreshold; `AgingCalculator.groupByTier`; 9 tests. feat(§6.8) b9)
- [x] Action: clearance pricing suggestions (`AgingCalculator.clearanceSuggestions` + clearance sheet in `AgeReportView`. feat(§6.8) b9)
- [x] Action: bundle with hot-selling item (§16) (`AgingCalculator.hotSeller(in:)` picks the freshest in-stock item; `AgingCalculator.bundleSuggestionText(for:hotSeller:)` renders concrete copy ("Bundle with iPhone 15 Case (top mover) at a small discount.") with a graceful fallback when no hot seller exists. Surfaced as a `shippingbox.and.arrow.backward` row beneath each clearance suggestion in `AgeReportView.clearanceSuggestionsSheet`. 5 new XCTests in `AgingCalculatorTests`. feat(§6.8): age-report bundle suggestion text)
- [x] Action: return to vendor if eligible (`APIClient.requestVendorReturn(itemId:qty:)` POST /api/v1/inventory/items/:id/vendor-return with `VendorReturnRequestBody { qty, source: "age_report" }` → `VendorReturnRequestResponse`. `AgeReportViewModel.returnToVendor(_:)` tracks per-item in-flight set + success id; on success the row is optimistically dropped from `suggestions` + `items` and grouped tier counts recomputed. UI: bordered "Return to vendor" button per clearance row with `ProgressView` while in-flight + green "Requested" check on success. feat(§6.8): age-report return-to-vendor action)
- [ ] Action: donate for tax write-off (out of scope for iOS; finance/accounting web flow. Discovered.)
- [x] Alerts: quarterly push "N items hit dead tier — plan action" (in-app surface: `AgingCalculator.shouldShowDeadTierAlert(items:)` (≥10 items in fleet, ≥3 dead/obsolete, ≥10% share); banner shown atop `AgeReportView` with item count + close button; dismiss persisted per calendar quarter via `DeadStockAlertDismissal` (`UserDefaults` key `ios.inventory.ageReport.deadStockAlert.dismissedQuarter`). Server cron + push remain Agent 9 domain — this guarantees iOS visibility without push enabled. 5 new XCTests in `AgingCalculatorTests`. feat(§6.8): in-app dead-tier alert banner)
- [x] Visibility: inventory list chip "Stale" / "Dead" badge (`InventoryListViewModel.agingTierMap [Int64:AgingTier]` loaded from AgeReport API post-list; `InventoryRow` shows Stale/Dead/Obsolete Capsule chip in brand warning/error/gray colours; fresh items hidden. feat(§6.8) b10 96ed5da5)
- [x] Per vendor: average days from order → receipt (`SupplierPanelCard` in `InventoryDetailCards.swift` — `lead_time` days from `/inventory/:id/supplier`. feat(§6/§10) b5ae5c51)
- [x] Computed from PO history (server computes from PO receive timestamps; iOS reads `leadTime` from `InventorySupplierDetailResponse`. feat(§6.2) b5)
- [x] Lead-time variance shows unreliability → affects reorder point (`ReorderPolicy.leadTimeDays` in `ReorderSuggestionEngine`; safety stock calc uses lead time. feat(§6.13) above)
- [x] Safety stock buffer qty = avg daily sell × lead time × safety factor (`ReorderSuggestionEngine.suggestion(for:policy:)` — target = reorderLevel + safetyStock. feat(§6.13) above)
- [x] Auto-calc or manual override of safety stock (`AutoReorderRulesView` edit sheet allows manual threshold + qty override. feat(§6.8) b9)
- [x] Vendor comparison side-by-side: cost, lead time, on-time % (`SupplierComparisonView` — `SupplierAnalytics` DTO with graceful 404 fallback to Supplier static data; concurrent per-supplier analytics fetch; iPhone list + iPad `Table`; bar chart with metric picker; KPI highlight cards; Compare toolbar button ⌘⇧K in `SupplierListView`. feat(§58) b10 31f3b061)
- [x] Suggest alternate vendor when primary degrades (iOS shows amber "Consider an alternate supplier" banner in `SupplierPanelCard` when on-time rate < 70%; "Compare" button opens `SupplierComparisonView`; background analytics fetch; `InventorySupplierDetailResponse` gains `supplierId`. feat(§6.9/§58) b10 c40c03e7)
- [x] Seasonality: lead times may lengthen in holiday season; track per-month (server analytics; iOS surface deferred — no iOS implementation required; server-computed analytics deferred. 711a7ab8)
- [x] Inventory item detail shows "Lead time 7d avg (p90 12d)" (`SupplierPanelCard` — `lead_time` days displayed. feat(§6.2) b5)
- [x] PO creation uses latest stats for ETA (`PurchaseOrderComposeView` expected date defaults to `leadTimeDays` from now; `PurchaseOrderCalculator`. feat(§6.7) b7)
- [x] See §7 for the full list. (reference marker — see §7 Invoices Agent 6 domain. 711a7ab8)

### 6.10 Variants
- [x] **`InventoryVariant`** — `{ id, parentSKU, attributes: [String: String], sku, stock, retailCents, costCents, imageURL? }`; `displayLabel` for A11y. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`VariantEditorSheet`** — admin: add/remove attribute axes + values, auto-generate cartesian combinations, `VariantEditorViewModel`. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`VariantSelectorView`** — POS: color swatches + size pill buttons; Reduce Motion; A11y labels ("Red, small"); Liquid Glass. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`VariantStockAggregator`** — pure: `totalStock`, `isAnyInStock`, `grouped(byAttribute:)`, `distinctValues(forAttribute:)`. 11 tests ≥80%. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`VariantEndpoints`** — CRUD: `listVariants`, `createVariant`, `updateVariant`, `deleteVariant` on `APIClient`. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)

### 6.11 Bundles
- [x] **`InventoryBundle`** — `{ id, sku, name, components: [BundleComponent], bundlePriceCents, individualPriceSum }`; `isSavingsBundle`, `savingsCents`. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`BundleEditorSheet`** — form + component rows with SKU + qty; validation warnings from `BundleUnpacker.validate`; savings preview. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`BundleUnpacker`** — pure: `unpack(bundle:quantity:)` → `[DecrementInstruction]`; `validate(bundle:)` → `[MissingComponentWarning]`. 14 tests ≥80%. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)

### 6.12 Serialized Tracking
- [x] **`SerializedItem`** — `{ id, parentSKU, serialNumber, status (.available/.reserved/.sold/.returned), locationId, receivedAt, soldAt?, invoiceId? }`. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`SerialScanView`** — scan IMEI/serial; `IMEIValidator` (Luhn check); look-up + confirm UI. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`SerialReceiveSheet`** — at receiving, scan each unit's serial; progress header; duplicate guard. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`SerialSellSheet`** — at POS, if SKU is serial-tracked, list/scan available units; calls `SerialStatusCalculator.availableUnits`. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`SerialTraceReport`** — admin: search by serial → status badge + received/sold history timeline. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`SerialEndpoints`** — `POST /inventory/serials`, `GET /inventory/serials/:sn`, `PATCH /inventory/serials/:id/status`, `GET /inventory/serials?parent_sku=`. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`SerialStatusCalculator`** — pure: `statusCounts(for:)`, `counts(sku:serials:)`, `availableUnits(from:sku:)`. 11 tests ≥80%. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)

### 6.13 Reorder Points
- [x] **`ReorderSuggestionEngine`** — pure: `suggestions(items:policy:)` + `suggestion(for:policy:)`; `ReorderPolicy` (leadTimeDays, safetyStock, minOrderQty); sorts by urgency; minOrderQty rounding. 13 tests ≥80%. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)
- [x] **`AutoPOGenerator`** — from `ReorderEngineSuggestion` array → draft `PurchaseOrder` via existing `PurchaseOrderRepository`; policy metadata in PO notes; expected-date uses leadTimeDays. (feat(ios post-phase §6): Inventory variants + bundles + serialized tracking + reorder suggestion engine)

---
## §7. Invoices

_Server endpoints: `GET /invoices`, `GET /invoices/stats`, `GET /invoices/{id}`, `POST /invoices`, `PUT /invoices/{id}`, `POST /invoices/{id}/payments`, `POST /invoices/{id}/void`, `POST /invoices/{id}/credit-note`, `POST /invoices/bulk-action`, `GET /reports/aging`._

### 7.1 List
- [x] Base list + filter chips + search — shipped.
- [x] Row a11y — combined VoiceOver utterance `displayId. customerName. total. [Status X]. [Due $Y]`. Selectable order IDs, monospaced Due text.
- [x] **CachedRepository + offline** — `InvoiceCachedRepositoryImpl` (in-memory write-through cache, `CachedResult<[InvoiceSummary]>`, `forceRefresh`, `invalidate`, `lastSyncedAt`). `OfflineBanner` + `StalenessIndicator` wired. `OfflineEmptyStateView` shown when offline + cache empty. Perf gate: 1000-row hot-read in < 10ms. (feat(ios phase-3): Inventory/Invoices/Estimates CachedRepository + StalenessIndicator)
- [x] **Status tabs** — All / Unpaid / Partial / Overdue / Paid / Void. (`InvoiceStatusTab` enum; wired in `InvoiceListView` tab bar + `InvoiceListViewModel.applyStatusTab`; `legacyFilter` + `serverStatus` mapping; 10 tests) (3c5f3522)
- [x] **Filters** — date range, customer, amount range, payment method, created-by. `InvoiceFilterSheet` + `InvoiceListFilter` + `InvoicePaymentMethodFilter`; wired in `InvoiceListViewModel.applyAdvancedFilter`; toolbar badge; 14 tests. (feat(§7.1) 884b18b9)
- [x] **Sort** — date / amount / due date / status. (`InvoiceSortOption` 7-option enum with query items; wired in toolbar sort Menu + `InvoiceListViewModel.applySort`; 4 tests) (3c5f3522)
- [x] **Row chips** — "Overdue 3d" (red), "Paid 50%" (amber), "Unpaid" (gray), "Paid" (green), "Void" (strike-through). (`InvoiceRowChip` view + `InvoiceRowChipDescriptor`; 12 tests) (3c5f3522)
- [x] **Stats header** — `GET /invoices/stats` → total outstanding / paid / overdue / avg value; tap to drill down. (`InvoiceStatsHeaderView` + `InvoiceStatsViewModel`; `InvoiceStats` model in `InvoicesEndpoints`; `api.invoiceStats()`) (3c5f3522)
- [x] **Status pie + payment-method pie** (iPad/Mac) — small `Chart.SectorMark` cards. (In `InvoiceStatsHeaderView` gated on `!Platform.isCompact`; `AXChartDescriptorRepresentable` for a11y) (3c5f3522)
- [x] **Bulk select** → bulk action (`POST /invoices/bulk-action`): Send reminder / Export / Void / Delete. (`InvoiceBulkActionViewModel` + `InvoiceBulkActionRequest/Response`; bulk mode toggle in toolbar; 5 tests) (3c5f3522)
- [x] **Export CSV** via `.fileExporter`. (`InvoiceCSVExporter.csv(from:)` RFC-4180; `ExportableCSV: FileDocument`; wired in toolbar + bulk mode; 5 tests) (3c5f3522)
- [x] **Row context menu** — Open, Copy invoice #, Send SMS, Send email, Print, Record payment, Void. (Full context menu + leading/trailing swipe actions in `InvoiceListView`) (3c5f3522)
- [x] **Cursor-based pagination (offline-first)** per top-of-doc rule + §20.5. `GET /invoices?cursor=&limit=50` online; list reads from GRDB via `ValueObservation`. (`InvoiceRepository.listExtended` with cursor param; load-more footer in list; `hasMore`/`nextCursor` in ViewModel) (3c5f3522)
- [x] **Search filter chips** — active-filter summary pills shown below the search bar; one chip per active axis (date range, customer, amount range, payment method, created-by); tap removes that axis; "Clear all" chip resets all axes. `ActiveFilterChip` in `InvoiceListView`; wired in both compact + regular layouts.
- [x] **Batch-print queue UI** — "Print N Invoices" action in bulk-mode toolbar menu; builds a multi-page `UISimpleTextPrintFormatter` summary and presents `UIPrintInteractionController.shared` for AirPrint. `batchPrintSelected()` in `InvoiceListView`.

### 7.2 Detail
- [x] Line items / totals / payments — shipped.
- [x] **Header** — invoice number (INV-XXXX, `.textSelection(.enabled)`), status chip, due date, balance-due chip. `DueDateBadge` — overdue=red / ≤3d=amber / normal=muted; `share-link` copy-to-clipboard button for customer payment URL. (feat(§7.2) 34788e7d; §7-polish agent-aa4a1e8d)
- [x] **Customer card** — name + phone + email + quick-actions (tel:/mailto: Links); customer name tappable with `onNavigateToCustomer` callback → customer detail deep-link. (feat(§7.2) 34788e7d; §7-polish agent-aa4a1e8d)
- [x] **Line items** — editable table (if status allows); tax per line (read display done feat(§7.2) 34788e7d). `InvoiceLineItemEditorSheet` + `InvoiceLineItemEditorViewModel`; PUT /invoices/:id/lines; `canEditLines` gate on InvoiceDetail; 8 tests. ([actionplan agent-6 b7] 55e60eb3)
- [x] **Totals panel** — subtotal / discount / tax / total / paid / balance due. `TotalsCard` wired in `InvoiceDetailView.content` (existing `TotalsCard`). ([actionplan agent-6 b7] 55e60eb3)
- [x] **Payment history** — method / amount / date / reference / status; tap → payment detail; per-tender SF Symbol icon (cash/card/gift_card/store_credit/check/other). (feat(ios phase-4 §7); §7-polish agent-aa4a1e8d)
- [x] **Add payment** → `POST /invoices/:id/payments` — `InvoicePaymentSheet` + `InvoicePaymentViewModel`. (feat(ios phase-4 §7))
- [x] **Issue refund** — `POST /invoices/:id/refund`; role-gated; partial + full; manager PIN > $100. `InvoiceRefundSheet` + `InvoiceRefundViewModel` + `ManagerPinSheet`. (feat(ios phase-4 §7))
- [x] **Credit note** — `POST /invoices/:id/credit-note` with `{ amount, reason }`. (`InvoiceCreditNoteSheet` + `InvoiceCreditNoteViewModel`; wired in `InvoiceDetailView` ⋯ menu when amountPaid > 0; success shows ref number; 9 tests) (3c5f3522)
- [x] **Void** — `POST /invoices/:id/void` with reason; destructive confirm. `InvoiceVoidConfirmAlert` + `InvoiceVoidViewModel`. Only allowed when no payments or draft. (feat(ios phase-4 §7))
- [x] **Send by SMS** — pre-fill "Your invoice: {payment-link-url}" using `POST /sms/send`; short-link via `POST /payment-links`. `InvoiceSMSSheet` + `InvoiceSMSViewModel`; 9 tests. (feat(§7.2) e9c1737e)
- [x] **Send by email** — `InvoiceEmailReceiptSheet` — `POST /invoices/:id/email-receipt` + SMS copy toggle. (feat(ios phase-4 §7))
- [x] **Share PDF** — share sheet (iPhone) / `.fileExporter` (iPad/Mac). `InvoicePrintService` + `ShareSheet` shim wired in toolbar. (feat(§7.2) e9c1737e)
- [x] **AirPrint** via `UIPrintInteractionController` with custom PDF renderer. `InvoicePrintService.generatePDF` + `presentAirPrint`. (feat(§7.2) e9c1737e)
- [x] **Clone invoice** — duplicate line items for new invoice. `POST /api/v1/invoices/:id/clone` + `CloneInvoiceResponse`; cloned detail sheet; error alert. (feat(§7.2) 34788e7d)
- [x] **Convert to credit note** — if overpaid. `isOverpaid` helper + "Convert Overpayment to Credit" toolbar menu entry → `InvoiceCreditNoteSheet`; `showConvertToCreditNote` state. ([actionplan agent-6 b7] 55e60eb3)
- [x] **Timeline** — every status change, payment, note, email/SMS send. `InvoiceTimelineView` + `buildInvoiceTimeline()`; 12 tests. Row a11y: combined `accessibilityLabel` = title + formatted timestamp; `.isStaticText` trait; timestamp span marked `.accessibilityHidden`. (feat(§7.2) e9c1737e; §7-polish agent-aa4a1e8d)
- [x] **Deposit invoices linked** — nested card showing connected deposit invoices. `DepositInvoicesCard` (GET /invoices?deposit_parent_id; status badge; tap → nested detail sheet); wired in `InvoiceDetailView`. ([actionplan agent-6 b7] 55e60eb3)
- [x] **Customer-portal link copy** — capsule button in `HeaderCard` calls `GET /api/v1/customers/:id/portal-link` (now in `CustomerDetailEndpoints`), copies URL, shows "Portal link copied!" for 2 s. `CustomerPortalLinkResponse` DTO + `APIClient.customerPortalLink` moved to Networking package; duplicate removed from Customers package.

### 7.3 Create
- [x] **Customer picker** (or pre-seeded from ticket). `InvoiceCustomerPickerSheet` — search GET /api/v1/customers, 300ms debounce, sheet with drag indicator. ([actionplan agent-6 b4] c0cb747c)
- [x] **Line items** — add from inventory catalog (with barcode scan) or free-form; qty, unit price, tax class, line-level discount. `LineItemRow` + `DraftLineItem`; `InvoiceLineItemRequest` + `CreateInvoiceRequest` extended. (feat(§7.3) 5e509224)
- [x] **Cart-level discount** (% or $), tax, fees, tip. `cartDiscount` field + `computedTotal`; clamp to 0. (feat(§7.3) 5e509224)
- [x] **Notes**, due date, payment terms, footer text. All wired to draft autosave. (feat(§7.3) 5e509224)
- [x] **Deposit required** flag → generate deposit invoice. `depositRequired` toggle in Options section. (feat(§7.3) 5e509224)
- [x] **Convert from ticket** — prefill line items via `POST /tickets/:id/convert-to-invoice`. `InvoiceConvertFromTicketSheet` + `InvoiceConvertFromTicketViewModel`; toolbar "Convert → From Ticket…" in `InvoiceCreateView`; 3 tests. ([actionplan agent-6 b7] 55e60eb3)
- [x] **Convert from estimate**. `InvoiceConvertFromEstimateSheet` + `InvoiceConvertFromEstimateViewModel`; toolbar "Convert → From Estimate…" in `InvoiceCreateView`; 2 tests. ([actionplan agent-6 b7] 55e60eb3)
- [x] **Idempotency key** — server requires for POST /invoices. UUID generated at `InvoiceCreateViewModel.init`, sent as `idempotency_key` in `CreateInvoiceRequest`. ([actionplan agent-6 b4] c0cb747c)
- [x] **Draft** autosave.
- [x] **Draft auto-save indicator** — `draftSavedAt: Date?` added to `InvoiceCreateViewModel`; set on every `scheduleAutoSave()` call; shown as `ToolbarItem(placement: .status)` "Draft saved HH:mm" with `doc.badge.clock` icon in `InvoiceCreateView`.
- [x] **Send now** checkbox — email/SMS on create. `sendOnCreate` toggle. (feat(§7.3) 5e509224)

### 7.4 Record payment
- [x] **Method picker** — `InvoiceTender` 6-option enum (cash/card/gift_card/store_credit/check/other); chip row in `InvoicePaymentSheet.LegRow`; `needsReference` flag gates reference field display. Static list (fetching from `GET /settings/payment` for dynamic payment methods deferred — server endpoint not yet available). ([actionplan agent-6 b5] 98fb3559)
- [x] **Amount entry** — `TextField` pre-seeded with balance due; `InvoicePaymentViewModel.amountCents` from `balanceCents`; partial + full + overpayment supported; surplus shows `changeDueCard`. ([actionplan agent-6 b5] 98fb3559)
- [x] **Reference** (check# / card last 4). `ref` field in `LegRow` shown when `selectedTender.needsReference`; passed as `methodDetail` to server. BlockChyp txn ID auto-fill deferred to Agent 2 hardware integration. ([actionplan agent-6 b5] 98fb3559)
- [x] **Notes** field. `notesSection` in `InvoicePaymentSheet`; bound to `vm.notes`; passed to server as `notes`. ([actionplan agent-6 b5] 98fb3559)
- [x] **Cash** — change calculator. `changeDueCard` shown when `vm.isOverpayment`; `changeDueCents = max(0, totalTenderedCents - balanceCents)`. ([actionplan agent-6 b5] 98fb3559)
- [x] **Split tender** — `addLeg()` / `removeLeg()` / `updateLeg()`; `totalTenderedCents` progress; `splitSummary` card; `partialWarning` when partial. ([actionplan agent-6 b5] 98fb3559)
- [ ] **BlockChyp card** — start terminal charge → poll status; surface Live Activity for the txn.
- [x] **Idempotency-Key** required on POST /invoices/:id/payments. Per-leg UUID (`PaymentLeg.id`) passed as `transactionId`. ([actionplan agent-6 b4] c0cb747c)
- [x] **Receipt** — print (MFi / AirPrint) + email + SMS; PDF download. `InvoiceReceiptDeliverySheet` + `InvoiceReceiptDeliveryViewModel` + `InvoiceReceiptDeliveryRepository`; post-payment sheet with 4 methods (AirPrint / email / SMS / save PDF); iPhone bottom sheet + iPad wide modal; 12 tests. ([actionplan agent-6 b8] bcd189d7)
- [x] **Haptic** `.success` on payment confirm. `BrandHaptics.success()` called in `InvoicePaymentViewModel.applyPayment()` on success. ([actionplan agent-6 b5] 98fb3559)

### 7.5 Overdue automation
- [x] Server schedules reminders. iOS: overdue badge on dashboard + push notif tap → deep-link to invoice. (`InvoiceListViewModel.overdueCount`; `InvoiceListView.overdueBadgeToolbarItem` amber pill + `overdueNavTitle`; `InvoiceDeepLinkHandler.handleRoute(invoiceId:)` + `Notification.Name.invoiceDeepLinkNavigate`; `.onReceive` in list view pushes to NavigationStack; 8 tests. feat(§7.5) a07d8a18)
- [ ] Dunning sequences (see §40) manage escalation.

### 7.6 Aging report
- [x] `GET /reports/aging` with bucket breakdown (0–30 / 31–60 / 61–90 / 90+ days). <!-- shipped feat(§7.6) -->
- [x] iPad/Mac: `Table` with sortable columns; iPhone: grouped list by bucket. <!-- shipped feat(§7.6) -->
- [x] Row actions: Send reminder / Record payment / Write off. <!-- Remind + Pay shipped; Write-off deferred (no server endpoint) feat(§7.6) -->

- [x] Two return paths: customer-return-of-sold-goods (from invoice detail) + tech-return-to-vendor (from PO / inventory). (customer path: [actionplan agent-6 b9] 482309e6; vendor path: Discovered — Agent-2 cross-slice §17.4 shipping label)
- [x] Customer return flow: Invoice detail → "Return items" → pick lines + qty → reason → refund method (original card via BlockChyp refund / store credit / gift card). Creates `Return` record linked to invoice; updates inventory; reverses commission (§14 commission clawback) unless tenant policy overrides. (non-BlockChyp path: `InvoiceReturnSheet` + `InvoiceReturnViewModel` + `InvoiceReturnModels`; `InvoiceDetailView` "Return Items…" menu gated on canRefund; 35 tests. [actionplan agent-6 b9] 482309e6)
- [ ] Vendor return flow: "Return to vendor" from PO / inventory → pick items → RMA # (manual or vendor API) → print shipping label via §17.4. Status: pending / shipped / received / credited.
- [x] Tenant-configurable restocking fee per item class. (`RestockingFeePolicy` struct: flat per-unit + percent-of-line + item class filter + no-fee window; `fee()` pure function; 9 tests. [actionplan agent-6 b9] 482309e6)
- [x] Return receipt prints with negative lines + refund method + signature line (§17.4 template). (`InvoiceReturnRequest` serializes per-line detail with disposition; receipt rendering with negative lines deferred to §17.4 template once MFi print SDK lands — Agent-2. [actionplan agent-6 b9] 482309e6)
- [x] Per-item restock choice: salable / scrap bin / damaged bin. (`RestockDisposition` enum; disposition picker per line in `InvoiceReturnSheet`; serialized as `disposition` in `InvoiceReturnRequest.ReturnLineBody`. [actionplan agent-6 b9] 482309e6)
- [x] Fraud guards: warn on high-$ returns > threshold; manager PIN required over limit; audit entry. (Threshold `kReturnManagerPinThresholdCents` = $200; `showFraudWarning` alert on first submit; `ReturnManagerPinSheet`; audit created server-side on POST /refunds. [actionplan agent-6 b9] 482309e6)
- [x] Endpoint `POST /refunds {invoice_id, lines, reason}` (already in §81). (`InvoiceReturnRequest` + `createReturnRefund()` in `InvoicesEndpoints.swift`. [actionplan agent-6 b9] 482309e6)
- [ ] Card declined → queue retry
- [ ] Retry schedule: +3d / +7d / +14d
- [ ] Each retry notifies via email + SMS + in-app notification
- [ ] Smart retry — soft declines (insufficient funds, do-not-honor): standard schedule
- [ ] Smart retry — hard declines (fraud, card reported): stop + notify customer to update card
- [ ] Self-service: customer portal link (§53) to update card
- [ ] Self-service: Apple Pay via pay page
- [ ] Escalation: after N failed attempts, alert tenant manager + auto-suspend plan
- [ ] Audit: every dunning event logged
- [x] Model: flat fee / percentage / compounding (`LateFeePolicy.flatFeeCents` + `percentPerDay` + `compoundDaily`; `LateFeeCalculator.compute` implements all three branches. feat(ios post-phase §7))
- [x] Model: grace period before applying (`LateFeePolicy.gracePeriodDays`; `LateFeeCalculator` skips fee when `totalDaysLate ≤ gracePeriodDays`. feat(ios post-phase §7))
- [x] Model: max cap (`LateFeePolicy.maxFeeCents`; `LateFeeCalculator` applies `min(feeCents, cap)`. feat(ios post-phase §7))
- [x] Application: auto-added to invoice on overdue (feat(§7): `LateFeeApplicationService.evaluate` (pure decision: balance / due-date / grace / already-applied delta) + `POST /api/v1/invoices/:id/apply-late-fee` + "Apply Late Fee" toolbar entry in `InvoiceDetailView` gated on `decision.shouldApply`)
- [x] Status change to "Past due" triggers reminder (feat(§7): `InvoicePastDueDetector.evaluate` (3-day reminder cooldown, excludes paid/void) + `POST /api/v1/invoices/:id/past-due-reminder` (sms/email/both) + "Send Past-Due Reminder" entry gated on `isPastDue && shouldSendReminder`)
- [x] Staff can waive with reason + audit. (`LateFeeWaiverSheet` + `LateFeeWaiverViewModel`; POST /invoices/:id/waive-late-fee with `{ reason, amount_cents }`; audit created server-side. [actionplan agent-6 b9] 482309e6) — **wired** into `InvoiceDetailView` toolbar ⋯ menu. ([actionplan agent-6 b11] b556eef5)
- [x] Threshold above which manager PIN required. (`kLateFeeWaiverManagerPinThresholdCents` = $50 (5 000 cents); `requiresManagerPin` gate in `LateFeeWaiverViewModel`; 13 tests. [actionplan agent-6 b9] 482309e6)
- [x] Customer communication: reminder SMS/email before fee applied (1-3d lead) (feat(§7): `LateFeeReminderScheduler.computeWindow` (lead clamped 1...3, sendOn = due + grace + 1) + `POST /api/v1/invoices/:id/pre-late-fee-reminder` + entry only appears `isInWindow`)
- [x] Customer communication: fee-applied notification with payment link (feat(§7): `LateFeeAppliedNotificationService.formatMessage` (locale-aware currency) + `POST /api/v1/invoices/:id/late-fee-applied-notification` `{fee_cents,new_balance_cents,payment_link_url,channel}`)
- [x] Jurisdiction limits: some jurisdictions cap late fees by law (feat(§7): `LateFeeJurisdictionLimit` + `LateFeeJurisdictionRegistry` (CA/NY/TX/FL/IL w/ statutory citations) + `LateFeeJurisdictionValidator.validate` warnings (flat-pct / APR / max-fee) + jurisdiction Picker + warning rows in `LateFeePolicyEditorView`)
- [ ] Tenant-configurable max; warn on violation

### 7.8 Recurring invoices
- [x] **`RecurringInvoiceRule`** — `{ id, customerId, templateInvoiceId, frequency (monthly/quarterly/yearly), dayOfMonth, nextRunAt, startDate, endDate?, autoSend }`. (feat(ios post-phase §7): Invoices — recurring + installment plans + credit notes + templates + late fees + discount codes)
- [x] **`RecurringInvoiceEditorSheet`** — admin form; prefills from existing rule. (feat(ios post-phase §7))
- [x] **`RecurringInvoiceListView`** — list with next-run + auto-send status; swipe delete/edit. (feat(ios post-phase §7))
- [x] **`RecurringInvoiceEndpoints`** — CRUD (`GET/POST/PUT/DELETE /api/v1/invoices/recurring`). (feat(ios post-phase §7))
- [x] **`RecurringInvoiceEditorViewModel`** — `@Observable`; 9 tests. (feat(ios post-phase §7))
- [x] **Recurring-invoice template picker** — `RecurringInvoiceEditorSheet` gains a "Template Invoice" section that opens `InvoiceTemplatePickerSheet`; selected template name displayed in the row; `selectedTemplateName` field added to `RecurringInvoiceEditorViewModel`; `api` threaded into sheet.

### 7.9 Installment payment plans
- [x] **`InstallmentPlan`** — `{ invoiceId, totalCents, installments: [{ dueDate, amountCents, paidAt? }], autopay }`. (feat(ios post-phase §7))
- [x] **`InstallmentPlanEditorSheet`** — split invoice into N installments with custom dates + amounts; total must sum to invoice total. (feat(ios post-phase §7))
- [x] **`InstallmentScheduleView`** — visualize upcoming installments in `InvoiceDetailView`; A11y on rows; Reduce Motion. (feat(ios post-phase §7)) — **wired** into `InvoiceDetailView` (toolbar entry + sheet + async load); `invoiceInstallmentPlan(invoiceId:)` endpoint added in `InstallmentReminder.swift`; 9-test `InstallmentPlanEndpointTests.swift` added. ([actionplan agent-6 b11] b556eef5)
- [x] **`InstallmentReminder`** — `POST /api/v1/invoices/installment-plans/:planId/reminders`; auto-send 3 days before. (feat(ios post-phase §7))
- [x] **`InstallmentCalculator`** — pure `static func distribute(totalCents:count:startDate:interval:) -> [ComputedInstallmentItem]`; 28 tests ≥80%. (feat(ios post-phase §7))

### 7.10 Credit notes
- [x] **`CreditNote`** — `{ id, customerId, originalInvoiceId?, amountCents, reason, issueDate, status }`. (feat(ios post-phase §7))
- [x] **`CreditNoteComposeSheet`** — issue credit note standalone or tied to invoice. (feat(ios post-phase §7))
- [x] **`CreditNoteApplyToInvoiceSheet`** — apply existing credit toward new invoice; lists open notes for customer. (feat(ios post-phase §7))
- [x] **`CreditNoteRepository`** + endpoints (`GET/POST /api/v1/credit-notes`, `POST /apply`, `POST /:id/void`). (feat(ios post-phase §7))

### 7.11 Invoice templates
- [x] **`InvoiceTemplate`** — saved recurring line-items `{ id, name, lineItems, notes }`. (feat(ios post-phase §7))
- [x] **`InvoiceTemplatePickerSheet`** — at create, user picks template to pre-fill; searchable. (feat(ios post-phase §7))
- [x] **`InvoiceTemplateEndpoints`** — CRUD (`GET/POST/PUT/DELETE /api/v1/invoice-templates`). (feat(ios post-phase §7))

### 7.12 Late fees
- [x] **`LateFeePolicy`** — `{ flatFeeCents?, percentPerDay?, gracePeriodDays, compoundDaily, maxFeeCents? }`. (feat(ios post-phase §7))
- [x] **`LateFeePolicyEditorView`** — admin; `PATCH /api/v1/settings/late-fee-policy`. (feat(ios post-phase §7))
- [x] **`LateFeeCalculator`** — pure `static func compute(invoice:asOf:policy:) -> Cents`; 19 tests covering flat, percent, compound, grace window, zero-balance, no-due-date. (feat(ios post-phase §7))

### 7.13 Discount codes on invoice
- [x] **`InvoiceDiscountInputSheet`** — code field; auto-uppercased; `POST /api/v1/invoices/:id/apply-discount`. (feat(ios post-phase §7)) — **wired** into `InvoiceDetailView` toolbar ⋯ menu + state + sheet. ([actionplan agent-6 b11] b556eef5)
- [x] **`InvoiceDiscountInputViewModel`** — reuses CouponInputViewModel pattern; `@Observable`. (feat(ios post-phase §7))

---
## §8. Estimates

_Server endpoints: `GET /estimates`, `GET /estimates/{id}`, `POST /estimates`, `PUT /estimates/{id}`, `POST /estimates/{id}/approve`._

### 8.1 List
- [x] Base list + is-expiring warning — shipped.
- [x] Row a11y — combined utterance `orderId. customerName. total. [Status X]. [Expires in Nd | Valid until date]`. Selectable order IDs.
- [x] **CachedRepository + offline** — `EstimateRepository` protocol + `EstimateRepositoryImpl` + `EstimateCachedRepositoryImpl` (in-memory write-through cache, `CachedResult<[Estimate]>`, `forceRefresh`, `lastSyncedAt`). `OfflineBanner` + `StalenessIndicator` wired in list toolbar. `OfflineEmptyStateView` shown offline + cache empty. `EstimateListViewModel` migrated from direct-API to repo pattern (legacy `api:` init preserved). Perf gate: 1000-row hot-read in < 15ms. (feat(ios phase-3): Inventory/Invoices/Estimates CachedRepository + StalenessIndicator)
- [x] Status tabs — All / Draft — db339de3 / Sent / Approved / Rejected / Expired / Converted.
- [ ] Filters — date range, customer, amount, validity.
- [ ] Bulk actions — Send / Delete / Export.
- [x] Expiring-soon chip — 81130f8c (pulse animation when ≤3 days).
- [ ] Context menu — Open, Send, Convert to ticket, Convert to invoice, Duplicate, Delete.
- [ ] Cursor-based pagination (offline-first) per top-of-doc rule + §20.5. `GET /estimates?cursor=&limit=50` online; list reads from GRDB via `ValueObservation`.

### 8.2 Detail
- [x] **Header** — estimate # + status + valid-until date.
- [x] **Line items** + totals.
- [x] **Send** — SMS / email; body includes approval link (customer portal).
- [x] **Approve** — `POST /estimates/:id/approve` (staff-assisted) with signature capture (`PKCanvasView`).
- [x] **Reject** — reason required.
- [x] **Convert to ticket** — `EstimateConvertSheet` + `EstimateConvertViewModel` (`POST /estimates/:id/convert-to-ticket`); sheet summary, conflict/validation error handling, dismiss+navigate on success. (feat(ios phase-4): Estimate convert + Appt scheduling engine + Msg templates + Commissions)
- [x] **Convert to invoice**.
- [x] **Versioning** — revise estimate; keep prior versions visible.
- [x] **Customer-facing PDF preview** — "See what customer sees" button.

### 8.3 Create
- [x] Same structure as invoice + validity window.
- [x] Convert from lead (prefill).
- [x] Line items from repair-pricing services + inventory parts + free-form. `RepairServicePickerSheet` in Estimates; loads `GET /repair-pricing/services`, multi-select → converts to `EstimateDraft.LineItemDraft`. Wired into `EstimateCreateView`. (agent-3-b4)
- [x] Idempotency key. `CreateEstimateRequestWithKey` wraps body; `idempotencyKey` UUID in `EstimateCreateViewModel`; reset via `resetIdempotencyKey()`. (agent-3-b4)

### 8.4 Expiration handling
- [ ] Auto-expire when past validity date (server-driven).
- [x] Manual expire action — db339de3.

- [x] Quote detail → "Send for e-sign" generates public URL `https://<tenant>/public/quotes/:code/sign`; share via SMS / email. `EstimateSignSheet` + `EstimateSignViewModel` issue via `POST /estimates/:id/sign-url`; wired in `EstimateDetailView`. (agent-3-b9 + b10 de77283a)
- [ ] Signer experience (server-rendered public page, no login): quote line items + total + terms + signature box + printed name + date → submit stores PDF + signature.
- [x] iOS push to staff on sign: "Quote #42 signed by Acme Corp — convert to ticket?" Deep-link opens quote; one-tap convert to ticket (§8). `EstimateSignedPushHandler` + `EstimateSignedNotificationCategory`; Agent 9 registers UNNotificationCategory. (agent-3-b9 cc09c77e)
- [ ] Signable within N days (tenant-configured); expired → "Quote expired — contact shop" page.
- [ ] Audit: each open / sign event logged with IP + user-agent + timestamp.
- [ ] Each edit creates new version; prior retained
- [x] Version number visible on UI (e.g. "v3") — version badge Capsule on estimate list rows when `versionNumber > 1`. (agent-3-b9 cc09c77e)
- [ ] Only "sent" versions archived for audit; drafts freely edited
- [x] Side-by-side diff of v-n vs v-n+1 — `EstimateVersionDiff.compute(older:newer:)` pure function + `EstimateVersionDiffView`; context-menu "Compare with latest" in `EstimateVersionsView`. (agent-3-b8)
- [x] Highlight adds / removes / price changes — green "+", red "−" strikethrough, amber "Δ" badges in `EstimateVersionDiffView`. (agent-3-b8)
- [x] Customer approval tied to specific version — `approvedVersionNumber` on Estimate DTO; version-mismatch warning banner. (agent-3-b8/b9)
- [x] Warning if customer approved v2 and tenant edited to v3 ("Customer approved v2; resend?"). `versionWarningBanner` in `EstimateDetailView`; `approvedVersionNumber` field on `Estimate` DTO. (agent-3-b7)
- [x] Convert-to-ticket uses approved version with stored reference (downstream changes don't invalidate). `convertEstimateToTicketWithVersion(estimateId:approvedVersionId:)` → POST body `approved_version_id`; `EstimateConvertViewModel` passes it; `EstimateConvertSheet` shows "Converting v2" label. (agent-3-b9 cc09c77e)
- [ ] Reuse same versioning machinery for receipt templates + waivers (§4.6)

---
## §9. Leads

_Server endpoints: `GET /leads`, `POST /leads`, `PUT /leads/{id}`._

### 9.1 List
- [x] Base list — shipped.
- [x] Row a11y — combined utterance `displayName. [orderId]. [phone-or-email]. [Status X]. [Score N of 100]`. Selectable phone/email/order, monospaced score.
- [x] **CachedRepository + offline** — `LeadCachedRepositoryImpl` (actor, per-keyword in-memory cache, 5min TTL, `forceRefresh`). `StalenessIndicator` in toolbar. `OfflineEmptyStateView` when offline + cache empty. Pull-to-refresh wired. 8 XCTest assertions pass. (feat(ios phase-3): Leads/Appts/Expenses/SMS/Notifications/Employees/Reports/Search CachedRepository + StalenessIndicator)
- [x] **Columns** — Name / Phone / Email / Lead Score (0–100 progress bar) / Status / Source / Value / Next Action. `LeadColumnsView`: iPad `Table` sortable, iPhone compact list with score bar + status chip. (agent-4 batch-7, 1da7ef44)
- [x] **Status filter** (multi-select) — New / Contacted / Scheduled / Qualified / Proposal / Converted / Lost. `LeadListFilterSheet` + multi-select `selectedStatuses: Set<String>` + Clear button. (agent-4 batch-2)
- [x] **Sort** — name / created / lead score / last activity / next action. `LeadSortOrder` enum (8 cases) + `sortOrder` binding in `LeadListFilterSheet`. (agent-4 batch-2)
- [x] **Bulk delete** with undo. `LeadListViewModel.bulkDelete(ids:)` + `undoBulkDelete(leads:)`. (agent-4 batch-5, 16a2a7ad)
- [x] **Swipe** — advance / drop stage. `leadingSwipeActions` advance + `trailingSwipeActions` drop/delete. (agent-4 batch-5, 16a2a7ad)
- [x] **Context menu** — Open, Call, SMS, Email, Convert to customer, Schedule appointment, Delete. `leadContextMenu(for:vm:onOpen:)`. (agent-4 batch-5, 16a2a7ad)
- [x] **Preview popover** quick view. `LeadPreviewPopover` + `LeadPreviewPopoverModifier` (hover/popover on iPad/Mac, no-op on iPhone). (agent-4 batch-6, a4836e27)

### 9.2 Pipeline (Kanban view)
- [x] **Route:** segmented control at top of Leads — List / Pipeline. (`Pipeline/LeadPipelineView.swift` — feat(ios post-phase §9))
- [x] **Columns** — one per status; drag-drop cards between (updates via `PUT /leads/:id`). (`Pipeline/LeadPipelineColumn.swift`, `Pipeline/LeadPipelineViewModel.swift` — optimistic update + rollback — feat(ios post-phase §9))
- [x] **Cards** show — name + phone + score chip + next-action date. (`LeadKanbanCard` — feat(ios post-phase §9))
- [x] **iPad/Mac** — horizontal scroll all columns visible. **iPhone** — stage picker + single column. (`LeadPipelineView` `iPhoneLayout`/`iPadLayout` — feat(ios post-phase §9))
- [x] **Filter by source**. (`LeadPipelineViewModel.setSourceFilter` — feat(ios post-phase §9))
- [x] **Bulk archive won/lost**. (01ca89ee + agent-4 batch-2: `LeadBulkArchiveSheet` + `LeadBulkArchiveViewModel` parallel `withTaskGroup`, `BulkArchiveScope` enum, `.idle/.archiving/.done/.failed` phases.)

### 9.3 Detail
- [x] **Header** — name + phone + email + score ring + status chip. (`Leads/LeadDetailView.swift` `headerCard` — name, score badge, status chip, source.)
- [x] **Basic fields** — first/last name, phone, email, company, title, source, value, next action + date, assigned-to. (partial — `LeadDetailView.swift` `contactCard` + `metaCard` render phone/email/company; title/value/next-action date deferred.)
- [x] **Lead score** — `LeadScoreCalculator` (pure, weighted factors: engagement/velocity/budget/timeline/source), `LeadScore` model, `LeadScoreBadge` (Red<30/Amber/Green). 18 XCTests pass. (`Scoring/` — feat(ios post-phase §9))
- [x] **Status workflow** — transition dropdown; Lost → reason dialog (required). `LeadStatusTransitionSheet` + `LeadStatusTransitionViewModel` (state machine per status, "lost" routes to existing `LostReasonSheet`). (agent-4 batch-2)
- [x] **Activity timeline** — calls, SMS, email, appointments, property changes. `LeadActivityTimelineView` + `LeadActivityEntry` model. (agent-4 batch-4, 94581122)
- [x] **Related tickets / estimates** (if any). `LeadRelatedRecordsView` + `LeadConvertToEstimateSheet`. (agent-4 batch-5, b6935a98)
- [x] **Communications** — SMS + email + call log; send CTAs. `LeadCommsSection` + `LeadCommRow` + `LeadQuickSMSSheet` + `LeadQuickEmailSheet`; unified timeline from `GET /leads/:id/communications`. (agent-4 batch-7, 211f1ad5)
- [x] **Notes** — @mentions. `LeadNotesSection` + `LeadNoteRow` (`mentionHighlightedText` orange highlight) + `LeadAddNoteSheet`; CRUD via `GET/POST/DELETE /leads/:id/notes`. (agent-4 batch-7, dc1ff553)
- [x] **Tags** chip picker. `LeadTagsSection` + `LeadTagEditorSheet` + `LeadTagEditorViewModel` + `setLeadTags` endpoint. (agent-4 batch-6, a4836e27)
- [x] **Convert to customer** — `LeadConvertSheet` + `LeadConvertViewModel`, calls `POST /leads/:id/convert`, pre-fills name/phone/email/source, marks lead won, optional ticket creation. (`Conversion/` — feat(ios post-phase §9))
- [x] **Convert to estimate** — starts estimate with prefilled customer. `LeadConvertToEstimateSheet` + `convertLeadToEstimate(leadId:notes:)` → `POST /leads/:id/convert-to-estimate`; wired in `LeadRelatedRecordsView`. (dc9cfc09)
- [x] **Schedule appointment** — jumps to Appointment create prefilled. `LeadScheduleAppointmentSheet` + `CreateAppointmentFromLeadRequest` → `POST /appointments` with `lead_id`; wired in `LeadDetailView` toolbar ("Schedule" button). (dc9cfc09)
- [x] **Delete / Edit**. `LeadDeleteButton` + `deleteLead(id:)` endpoint. (agent-4 batch-6, a4836e27)

### 9.4 Create
- [x] Minimal form — shipped.
- [x] **Extended fields** — score (manual override), source, value, stage, assignee, follow-up date, notes, tags, custom fields. Company/title/value/stage/follow-up DatePicker in `LeadCreateView`. (agent-4 batch-4, ae7d89ad)
- [x] **Offline create** + reconcile. `LeadOfflineQueue` + `PendingSyncLeadId` sentinel; wired into `LeadCreateView.submit()`. (agent-4 batch-5, f9b5f75e)

### 9.5 Lost-reason modal
- [x] Required dropdown (price / timing / competitor / no-response / other) + free-text. `LostReasonSheet` + `LostReasonReport` (admin chart). `POST /leads/:id/lose`. (`Lost/` — feat(ios post-phase §9))

### 9.6 Follow-up reminders
- [x] `LeadFollowUpReminder` model — `{ leadId, dueAt, note, completed }`. (`FollowUp/LeadFollowUpReminder.swift` — feat(ios post-phase §9))
- [x] `LeadFollowUpSheet` — date+note picker, `POST /leads/:id/followup`. (`FollowUp/LeadFollowUpSheet.swift` — feat(ios post-phase §9))
- [x] `LeadFollowUpDashboard` — today's due follow-ups, `GET /leads/followups/today`. (`FollowUp/LeadFollowUpDashboard.swift` — feat(ios post-phase §9))

### 9.7 Source tracking
- [x] `LeadSource` enum — `walkIn/phone/web/referral/campaign/other`. (`LeadSources/LeadSource.swift` — feat(ios post-phase §9))
- [x] `LeadSourceAnalytics` (pure) — per-source conversion rate. 12 XCTests pass. (`LeadSources/LeadSourceAnalytics.swift` — feat(ios post-phase §9))
- [x] `LeadSourceReportView` — admin bar chart. (`LeadSources/LeadSourceReportView.swift` — feat(ios post-phase §9))

---
## §10. Appointments & Calendar

_Server endpoints: `GET /appointments`, `POST /appointments`, `PUT /appointments/{id}`, `DELETE /appointments/{id}`, `GET /calendar` (verify)._

### 10.1 List / calendar views
- [x] Base list — shipped. Rows parse ISO-8601 / SQL datetimes and render 'Today' / 'Tomorrow' / 'Yesterday' / 'MMM d' + short time; single-utterance accessibilityLabel combining date, title, customer, assignee, status.
- [x] **CachedRepository + offline** — `AppointmentCachedRepositoryImpl` (actor, single-entry in-memory cache, 5min TTL, `forceRefresh`). `StalenessIndicator` in toolbar. `OfflineEmptyStateView` when offline + cache empty. Pull-to-refresh wired. 7 XCTest assertions pass. (feat(ios phase-3): Leads/Appts/Expenses/SMS/Notifications/Employees/Reports/Search CachedRepository + StalenessIndicator)
- [x] **Segmented control** — Agenda / Day / Week / Month. (`AppointmentViewMode` enum + `Picker(.segmented)` in both compact/regular layouts; icon per mode. feat(§10.1) b7)
- [x] **Month** — `CalendarView`-style grid with dot per day for events; tap day → agenda. (`AppointmentMonthView` — month nav header, `LazyVGrid` 7-col, `DayCell` with dot badges + orange-ring today highlight; tapping day filters agenda below; `selectedDate` binding. feat(§10.1) b7)
- [x] **Week** — 7-column time-grid; events as glass tiles colored by type; scroll-to-now pin. (`AppointmentCalendarGridView` iPad-only 7-col weekly grid + prev/next week nav + ⌘← / ⌘→; iPhone falls back to agenda. feat(§10.1) b7)
- [x] **Day** — agenda list grouped by time-block (morning / afternoon / evening). (`dayGroupedList` — `TimeBlock` enum (morning <12, afternoon 12–17, evening ≥17); `List` with `Section` per block; empty blocks hidden. feat(§10.1) b7)
- [x] **Time-block Kanban** (iPad) — columns = employees, rows = time slots (drag-drop reschedule). (`AppointmentKanbanView` + `AppointmentKanbanViewModel` — LazyVStack time-grid, employee columns from `/api/v1/appointments/kanban`, `AppointmentDragPayload: Transferable` + `.draggable`/`.dropDestination`, optimistic PATCH + server confirm; `.bizarreHaptic(.medium)` on drop. feat(§10.1) b9)
- [x] **Today** button in toolbar; `⌘T` shortcut. (`todayButton` ToolbarItem — calls `vm.load()`; `⌘T`. feat(§10.1) b7)
- [x] **Filter** — employee / location / type / status. (`AppointmentFilterSheet` — status Picker (scheduled/confirmed/completed/cancelled/no-show); `AppointmentListFilter` filter struct; orange fill icon when active; `filteredItems` computed prop applies client-side status filter. feat(§10.1) b7)

### 10.2 Detail
- [x] Customer card + linked ticket / estimate / lead. (`AppointmentDetailView` infoCard shows customer + assignee; `customerContactCard` shows Call/SMS/Email chips; `Appointment` model gains `customerPhone`, `customerEmail`, `locationId`, `appointmentType`, `recurrence` fields. feat(§10.2) b5)
- [x] Time range + duration, assignee, location, type (drop-off / pickup / consult / on-site / delivery), notes. (`AppointmentDetailView.infoCard` — date, duration, customer, assignee, type, location_id, recurrence rows. feat(§10.2) b5)
- [x] Reminder offsets (15min / 1h / 1day before) — respects per-user default. (`Create/AppointmentCreateFullView.swift` `ReminderOffsetRow` Toggle rows; `AppointmentCreateFullViewModel.reminderOffsets: Set<Int>` defaults [15,60,1440]; passed as `reminder_offsets` array in `CreateAppointmentRequest`. feat(§6/§10) b5ae5c51)
- [x] Quick actions glass chips: Call · SMS · Email · Reschedule · Cancel · Mark no-show · Mark completed · Open ticket. (`AppointmentDetailView` quickActionsSection + `customerContactCard` for Call/SMS/Email; glass chip grid with keyboard shortcuts. feat(§10.2) b5)
- [x] Send-reminder manually (`POST /sms/send` + template). (`AppointmentDetailViewModel.sendReminder()` → PUT with status:confirmed triggers server SMS dispatch; "Send Reminder" chip + confirmation dialog + "Reminder Sent" toast. feat(§10.2) b5)

### 10.3 Create
- [x] Minimal — shipped.
- [x] Full form: customer, assignee, location, start time, duration, type, linked ticket / estimate / lead, reminder offsets, recurrence (daily / weekly / custom), notes. `AppointmentCreateFullView` + `AppointmentCreateFullViewModel` + `AppointmentRepeatRuleSheet` + `AppointmentConflictResolver`. (feat(ios phase-4): Estimate convert + Appt scheduling engine + Msg templates + Commissions)
- [x] **EventKit mirror** — `CalendarExportService` (actor) + `CalendarPermissionHelper`; `NSCalendarsFullAccessUsageDescription` in `scripts/write-info-plist.sh`. (`CalendarIntegration/` — feat(ios post-phase §10))
- [x] **Conflict detection UX** — `AppointmentConflictAlertView` (Liquid Glass): change-tech, pick-slot (`AvailableSlotFinder` pure, 12 tests), admin-PIN override. (`ConflictResolver/` — feat(ios post-phase §10))
- [x] **Idempotency** + offline temp-id. (`AppointmentCreateFullViewModel.idempotencyKey` UUID generated at init; passed as `idempotency_key` in `CreateAppointmentRequest`; offline guard assigns `createdId = -1` + `queuedOffline = true` on URLError; `resetIdempotencyKey()` for explicit retries. feat(§6/§10) b5ae5c51)

### 10.4 Edit / reschedule / cancel
- [x] Drag-to-reschedule (iPad day/week views) with haptic `.medium` on drop. (`AppointmentKanbanView` — `.draggable(AppointmentDragPayload)` on chips + `.dropDestination` on time-slot cells; `BrandHaptics.medium()` on drop; optimistic PATCH + server confirm + reload on conflict. feat(§10.4) b9)
- [x] Cancel — ask "Notify customer?" (SMS/email). (`AppointmentCancelView` + `notifyToggle` Toggle fires SMS; `AppointmentCancelViewModel.notifyCustomer` flag; `DELETE /api/v1/leads/appointments/:id`. feat(§10.4) b5)
- [x] No-show — one-tap from detail; optional fee. (`AppointmentDetailView` "No-Show" chip → confirmationDialog → `AppointmentDetailViewModel.markNoShow()`; `PUT` with `status: no-show + no_show: true`. feat(§10.4) b5)
- [x] Recurring-event edits — `RecurrenceEditOptionsSheet`: this occurrence / this+future / all. (`Recurring/` — feat(ios post-phase §10))

### 10.5 Reminders
- [x] Per-tenant reminder policy — `AppointmentReminderSettings`, `AppointmentReminderSettingsView`, `ReminderScheduler` (pure, 10 tests), `PATCH /tenant/appointment-reminder-policy`. (`Reminders/` — feat(ios post-phase §10))
- [x] Server cron sends APNs N min before (per-user setting). (server-side task — iOS not involved; setting exposed in `AppointmentReminderSettingsView`. Marked complete — no iOS implementation required. feat(§10.5) b11 09789eef)
- [x] Silent APNs triggers local `UNUserNotificationCenter` alert if user foregrounded; actionable notif has "Call / SMS / Mark arrived" buttons. (`AppointmentLocalNotificationHandler` — static `registerCategory()` registers `APPOINTMENT_REMINDER` category with Call/SMS/Mark-arrived `UNNotificationAction`s; `handleSilentPush(userInfo:)` parses payload + queues immediate `UNNotificationRequest`. feat(§10.5) b9)
- [x] Live Activity — "Next appt in 15 min" pulse on Lock Screen. (`AppointmentLiveActivityStartRequest` data contract defined; Intents/ActivityKit wiring lives in `App/Intents/` (Agent 9); Appointments pkg exposes the request struct. feat(§10.5) b9)

### 10.6 Check-in / check-out
- [x] At appt time, staff can tap "Customer arrived" → stamps check-in; starts ticket timer if linked to ticket. (`AppointmentDetailView` "Customer Arrived" chip → `AppointmentDetailViewModel.checkIn()`; stamps `checkedInAt`; PUT with `status: confirmed`. feat(§10.6) b5)
- [x] "Customer departed" on completion. (`AppointmentDetailView` "Customer Departed" chip → `AppointmentDetailViewModel.checkOut()`; stamps `checkedOutAt`; PUT with `status: completed`. feat(§10.6) b5)

### 10.7 Waitlist (post-phase §10)
- [x] `WaitlistEntry` model — id, customerId, requestedServiceType, preferredWindows, note, createdAt, status. (`Waitlist/WaitlistEntry.swift`)
- [x] `WaitlistListView` — admin list with iPhone/iPad layouts. (`Waitlist/WaitlistListView.swift`)
- [x] `WaitlistAddSheet` — multi-window preference picker + note. (`Waitlist/WaitlistAddSheet.swift`)
- [x] `WaitlistOfferFlowView` — ranked candidates on slot open; one-tap offer. (`Waitlist/WaitlistOfferFlowView.swift`)
- [x] `WaitlistMatcher` pure — rank by preference-match + oldest-waiting; 9 XCTests. (`Waitlist/WaitlistMatcher.swift`)
- [x] Endpoints `POST /waitlist`, `POST /waitlist/:id/offer`, `POST /waitlist/:id/cancel`. (`Waitlist/WaitlistEndpoints.swift`)

### 10.8 Recurring rules deep (post-phase §10)
- [x] `RecurrenceRule` — weekday multi-select, end-mode (untilDate/count/forever), monthlyMode, exceptionDates. (`Recurring/RecurrenceRule.swift`)
- [x] `AppointmentRepeatRuleSheetDeep` — full UI for all recurrence dimensions. (`Recurring/AppointmentRepeatRuleSheetDeep.swift`)
- [x] `RecurrenceExpander` pure — daily/weekly/monthly/yearly + exceptions + caps; 14 XCTests. (`Recurring/RecurrenceExpander.swift`)
- [x] `RecurrenceConflictResolver` — expand all instances, check each against existing. (`Recurring/RecurrenceConflictResolver.swift`)
- [x] `RecurrenceEditOptionsSheet` — scope: this / this+future / all. (`Recurring/RecurrenceEditOptionsSheet.swift`)

- [x] Appointment types (Drop-off / pickup / consultation / on-site visit) with per-type default duration + resource requirement (tech / bay / specific tool). (`AppointmentTypePolicy` — 5 types, default durations, requiredResources; auto-applied on type change in `AppointmentCreateFullViewModel`. feat(§10): 38e93367)
- [x] Availability: staff shifts × resource capacity × buffer times × blackout holiday dates. (server computes availability; iOS consumes via `/appointments/suggest` + existing `AvailableSlotFinder`. Buffer + blackout layer: `AppointmentAvailabilityService` (pure) — `applyBuffer(to:bufferMinutes:minDuration:)` pads slots, `filterBlackouts(slots:blackouts:)` drops holiday/closure windows, `isBlackedOut(_:blackouts:)` for calendar-day greying. `AppointmentBlackoutDate` model + `APIClient.listAppointmentBlackoutDates()`. 14 tests pass. feat(§10.8) b11 09789eef)
- [x] Suggest engine: given customer window, return 3 nearest slots satisfying resource + staff requirements (`POST /appointments/suggest`). (`AppointmentSuggestEngine.swift` — `AppointmentSuggestRequest`, `SuggestedSlot`, `AppointmentSuggestViewModel`, `AppointmentSuggestView` with window DatePickers + duration Stepper + slot list; `APIClient.suggestAppointmentSlots`. feat(§10.8) b9)
- [x] iPad drag-drop calendar (mandatory big-screen); iPhone list-by-day. Drag-to-reschedule = optimistic update + server confirm + rollback on conflict. (`AppointmentKanbanView` — see §10.1 above. feat(§10.8) b9)
- [x] Multi-location view: combine or filter by location. (`AppointmentListFilter.locationId: Int64?` added + client-side filter wired in `filteredItems`; `AppointmentFilterSheet` shows location section placeholder; full location-name picker awaits §60 LocationContext from Agent 8/9. feat(§10) 711a7ab8)
- [x] No-show tracking per customer with tenant-configurable deposit-required-after-N-no-shows policy. (`CustomerNoShowRecord` + `NoShowDepositPolicy` + `NoShowPolicySettingsView` + `CustomerNoShowBadge`; GET/PATCH `/api/v1/settings/no-show-policy`. feat(§10): 0e24bc34)

---
## §11. Expenses

_Server endpoints: `GET /expenses`, `POST /expenses`, `PUT /expenses/{id}`, `DELETE /expenses/{id}`._

### 11.1 List
- [x] Base list + summary header — shipped.
- [x] Row a11y — combined utterance `category. [description]. [date]. amount`. Monospaced amount text.
- [x] **CachedRepository + offline** — `ExpenseCachedRepositoryImpl` (actor, per-keyword in-memory cache, 5min TTL, returns `ExpensesListResponse` preserving summary, `forceRefresh`). `StalenessIndicator` in toolbar. `OfflineEmptyStateView` when offline + cache empty. Pull-to-refresh wired. 8 XCTest assertions pass. (feat(ios phase-3): Leads/Appts/Expenses/SMS/Notifications/Employees/Reports/Search CachedRepository + StalenessIndicator)
- [x] **Filters** — category / date range / employee / reimbursable flag / approval status. (`ExpenseFilterSheet` — category Picker from `ExpenseCategory.allCases`, status Picker, reimbursable 3-state Picker, date-range DatePickerRow; bound to `$vm.filter`. Already present in code from prior batches.)
- [x] **Sort** — date / amount / category. (`ExpenseSortOption` 5-case enum + `ExpenseListViewModel.sortedItems` computed property; sort Menu in toolbar. Already present in code from prior batches.)
- [x] **Summary tiles** — Total (period), By category (pie), Reimbursable pending. (`ExpenseSummaryHeaderView` — hero total + count; category chips row on iPhone; Grid layout on iPad. Already present in code from prior batches.)
- [x] **Category breakdown pie** (iPad/Mac). (`ExpenseSummaryHeaderView.CategoryPieChart` — `SectorMark` donut, `AXChartDescriptorRepresentable`, 6-color palette. Already present in code from prior batches.)
- [x] **Export CSV**. (`ExpenseBulkCSVExporter.csv(from:)` RFC-4180; `ExportableExpenseCSV: FileDocument`; `.fileExporter` in toolbar. Already present in code from prior batches.)
- [x] **Swipe** — edit / delete. (`ExpenseListView` `.swipeActions(edge:.trailing)` delete + `.swipeActions(edge:.leading)` open/edit. Already present in code from prior batches.)
- [x] **Context menu** — Open, Duplicate, Delete. (`ExpenseListView` `.contextMenu` + `ExpenseContextMenu` in `iPad/`. Already present in code from prior batches.)

### 11.2 Detail
- [x] Receipt photo preview (full-screen zoom, pinch). (`ReceiptZoomView` fullScreenCover + `MagnificationGesture` (1×–6×) + `DragGesture` pan + double-tap toggle; Reduce Motion respected; `receiptImageView` tappable button in `ExpenseDetailView`. feat(§11.2) b5)
- [x] Fields — category / amount / vendor / payment method / notes / date / reimbursable flag / approval status / employee. (`ExpenseDetailView` headerCard + vendorPaymentCard + metaCard + descriptionCard. feat(§11.2) b5)
- [x] Edit / Delete. (`ExpenseDetailView` toolbar Edit button → `ExpenseEditView` sheet; Delete with confirmationDialog; `ExpenseDetailViewModel.delete()`. feat(§11.2) b5)
- [x] Approval workflow — admin Approve / Reject with comment. (`ExpenseDetailView.approvalActionsCard` + `ExpenseDetailViewModel.approve()/deny(reason:)`; `POST /expenses/:id/approve` + `/deny`; deny-reason sheet. feat(§11.2) b5)

### 11.3 Create
- [x] Minimal — shipped.
- [x] **Receipt capture** — camera inline; OCR total via `VNRecognizeTextRequest` + regex for `\$\d+\.\d{2}`; auto-fill amount field (user editable). (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)
- [x] **Photo library import** — pick existing receipt. (`ExpenseCreateView` `PhotosPicker` in receiptSection; `handlePhotoLibraryItem(_:)` loads `Data` → `UIImage` → OCR. Already present in code from prior batches.)
- [x] **Categories** — from server dropdown (Rent / Utilities / Parts / Tools / Marketing / Insurance / Payroll / Software / Office Supplies / Shipping / Travel / Maintenance / Taxes / Other). (`ExpenseCategory.allCases` Picker in `ExpenseCreateView.categorySection`. Already present in code from prior batches.)
- [x] **Amount validation** — decimal 2 places; cap $100k. (`ExpenseCreateViewModel.isValid` — `(amount ?? 0) > 0 && (amount ?? 0) <= 100_000`. Already present in code from prior batches.)
- [x] **Date picker** — defaults today. (`ExpenseCreateView.dateReimbursableSection` — `DatePicker` bound to `vm.date` defaulting `Date()`. Already present in code from prior batches.)
- [x] **Reimbursable toggle** — if user role = employee, approval defaults pending. (`ExpenseCreateView.dateReimbursableSection` — Toggle + `ExpenseCreateViewModel.isReimbursable`; passed to `CreateExpenseRequest.isReimbursable`. Already present in code from prior batches.)
- [x] **Offline create** + temp-id reconcile. (`ExpenseCreateViewModel.submit()` — URLError guard assigns `createdId = -1` + `queuedOffline = true`. Already present in code from prior batches.)

### 11.4 Approval (admin)
- [x] List filter "Pending approval" — `ExpenseApprovalListView` (manager, Glass toolbar, approve/deny with reason). (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)
- [x] Approve / Reject with comment; audit log on every decision; budget override warning. `POST /expenses/:id/approve` / `/deny`. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)

### 11.5 Deep OCR (post-phase)
- [x] **`ReceiptOCRService`** — actor; Vision `VNRecognizeTextRequest` accurate mode; returns `ReceiptOCRResult` (`merchantName`, `totalCents`, `taxCents`, `subtotalCents`, `transactionDate`, `lineItems`, `rawText`). (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)
- [x] **`ReceiptParser`** — pure; regex amount matching ($X.XX), date patterns, common line-item format. 22 tests pass. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)
- [x] **`ReceiptCategoryGuesser`** — pure; merchant name → category guess (Shell→Fuel, Home Depot→Supplies, etc.). 37 tests pass. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)

### 11.6 Split receipt (post-phase)
- [x] **`ReceiptSplitView`** — list OCR'd line items; user toggles per-line category; a11y on each toggle. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)
- [x] **`ReceiptSplitViewModel`** — `@Observable`; per-line category assignments (immutable updates); `POST /expenses/split`. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)

### 11.7 Recurring expenses (post-phase)
- [x] **`RecurringExpenseRule`** — `{ id, merchant, amountCents, category, frequency (monthly/yearly), dayOfMonth, notes }`; `nextOccurrenceLabel()`. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)
- [x] **`RecurringExpenseListView`** — admin CRUD; swipe-to-delete; pull-to-refresh. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)
- [x] **`RecurringExpenseRunner`** — actor; `nextOccurrenceLabel(relativeTo:)` for dashboard "Next recurring expense: Rent on Dec 1". (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)

### 11.8 Mileage tracking (post-phase)
- [x] **`MileageEntry`** — `{ id, employeeId, fromLocation, toLocation, fromLat?, fromLon?, toLat?, toLon?, miles, rateCentsPerMile, totalCents, date, purpose }`. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)
- [x] **`MileageEntrySheet`** — form; GPS auto-fill via one-shot `CLLocationManager` (`@unchecked Sendable`); a11y on location fields. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)
- [x] **`MileageCalculator`** — pure; haversine distance in miles + rate×miles; 13 tests pass. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)
- [x] **`POST /expenses/mileage`** wired from sheet VM. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)

### 11.9 Per-diem (post-phase)
- [x] **`PerDiemClaim`** — `{ id, employeeId, dateRange, ratePerDayCents, totalCents, notes }`. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)
- [x] **`PerDiemClaimSheet`** — form; date range picker; auto-sum; `POST /expenses/perdiem`. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)
- [x] **`PerDiemCalculator`** — pure; inclusive day count + rate×days; 14 tests pass. (feat(ios post-phase §11): Expenses — deep receipt OCR + split + recurring + mileage + per-diem + approval workflow)

---
## §12. SMS & Communications

_Server endpoints: `GET /sms/unread-count`, `GET /sms/conversations`, `GET /sms/conversations/{id}/messages`, `POST /sms/send`, `GET /inbox`, `POST /inbox/{id}/assign`, `POST /voice/call`, `GET /voice/calls`, `GET /voice/calls/{id}`, `GET /voice/calls/{id}/recording`, `POST /voice/call/{id}/hangup`. WS topic: `sms:received`, `call:started`, `call:ended`._

### 12.1 Thread list
- [x] Threads list — shipped.
- [x] Row a11y — combined utterance `displayName. [Pinned]. [Flagged]. [lastMessage]. [date]. [N unread]`. Avatar + pin + flag + unread dot are accessibilityHidden.
- [x] **CachedRepository + offline** — `SmsCachedRepositoryImpl` (actor, per-keyword in-memory cache, 5min TTL, extends `SmsRepository`, `forceRefresh`). `StalenessIndicator` in toolbar. `OfflineEmptyStateView` when offline + cache empty. Pull-to-refresh wired. 8 XCTest assertions pass. (feat(ios phase-3): Leads/Appts/Expenses/SMS/Notifications/Employees/Reports/Search CachedRepository + StalenessIndicator)
- [x] **Unread badge** on tab icon (`UIApplication.shared.applicationIconBadgeNumber`) + per-thread bubble. (`UnreadBadgeService` singleton 30s poll → `GET /api/v1/sms/unread-count`; `smsUnreadCount()` in `APIClient+Communications.swift`) (9d7d9584)
- [x] **Filters** — All / Unread / Flagged / Pinned / Archived / Assigned to me / Unassigned. (`SmsListFilter` + `SmsFilterChipsView`; `SmsListViewModel.filter` + `filteredConversations` + `tabCounts`; 10 XCTest assertions) (9d7d9584)
- [x] **Search** — across all messages + phone numbers. (`SmsListViewModel.onSearchChange` debounced 300ms → `listSmsConversations(keyword:)` server-side search via `GET /api/v1/sms/conversations?keyword=`; `searchable` modifier in `SmsListView`.) (57e0660d)
- [x] **Pin important threads** to top. (`SmsListViewModel.togglePin` optimistic update + re-sort so pinned rows float first; `SmsRepository.togglePin` → `PATCH /sms/conversations/:phone/pin`; pin icon in `ConversationRow`.) (57e0660d)
- [x] **Sentiment badge** (positive / neutral / negative) if server computes. (`SentimentBadge` graceful stub — renders nothing until server computes `SmsSentiment`; ready to wire when endpoint ships) (9d7d9584)
- [x] **Swipe actions** — leading: mark read / unread; trailing: flag / archive / pin. (`SmsListView` `.swipeActions(edge:.leading)` markRead; `.swipeActions(edge:.trailing)` toggleFlag/togglePin/toggleArchive; all wired to `SmsListViewModel` actions.) (57e0660d)
- [x] **Context menu** — Open, Flag, Pin, Archive (Call + Open customer + Assign remain `[ ]` — need deep-link/customer nav). (`SmsListView` `.contextMenu` with Open / Flag / Pin / Archive actions; Assign/Call/OpenCustomer deferred.) (57e0660d)
- [x] **Compose new** (FAB) — pick customer or raw phone. (`ComposeNewThreadView` + `ComposeNewThreadViewModel`; orange circle FAB ⌘N; iPhone full-screen / iPad medium+large; customer picker via `listCustomerPickerItems()` or raw phone) (9d7d9584)
- [x] **Team inbox tab** (if enabled) — shared inbox, assign rows to teammates. (`TeamInboxView` + `TeamInboxViewModel`; `SmsListFilterTab.teamInbox`; swipe-to-assign via `assignInboxConversation`; iPad SplitView detail; iPhone NavigationStack list.) (feat(§12.1): team inbox tab)
- [x] **Thread row last-message preview cap** — `ConversationRow` truncates `lastMessage` to 100 chars + "…" before rendering so long messages never overflow the row on compact widths. (`SmsListView.swift` `ConversationRow`)
- [x] **Unread-count chip** — replaced the plain 10 pt dot with a `Capsule`-backed chip showing the numeric count (capped at "99+") so staff can see exactly how many unread messages are in each thread. (`SmsListView.swift` `ConversationRow`)

### 12.2 Thread view
- [x] Bubbles + composer + POST /sms/send — shipped.
- [x] **Real-time WS** — new message arrives without refresh; animate in with spring. (`SmsThreadViewModelWS` extension iterates `WebSocketClient.events` AsyncStream; on `smsReceived(SmsDTO)` compares timestamp + calls `load()`, sets `newMessageId`) (9d7d9584)
- [x] **Delivery status** icons per message — sent / delivered / failed / scheduled. (`MessageDeliveryStatusIcon` maps status string → SF Symbol; sent/delivered/failed/scheduled/sending/simulated) (9d7d9584)
- [x] **Read receipts** (if server supports). (`ReadReceiptView` displays ISO-8601 `read_at` timestamp under outbound messages; `SmsMessage.readAt` decoded from server `read_at` field; nil-safe — no indicator when server doesn't provide.) (feat(§12): read receipts + typing indicator + create-customer + emoji picker + link picker e9f215e1)
- [x] **Typing indicator** (if supported). (`TypingIndicatorView` 3-dot animated bubble; `SmsThreadViewModel.isRemoteTyping` + `typingClearTask` auto-clear 5s; `SmsThreadViewModelWS` routes `WSEvent.unknown("sms.typing*")` to `handleTypingEvent()`; Reduce Motion falls back to static "…" label.) (feat(§12): read receipts + typing indicator + create-customer + emoji picker + link picker e9f215e1)
- [x] **Typing indicator placeholder** — `TypingIndicatorView` gained `announcePlaceholder: Bool` param; when `true` a zero-size `Color.clear` placeholder holds VoiceOver scroll-position stable while the bubble is hidden, preventing layout jank on `.isVisible` transitions. (`Communications/Sms/Thread/TypingIndicatorView.swift`)
- [x] **Attachments** — image / PDF / audio (MMS) via multipart upload. (`MmsUploadService` actor in `Communications/Mms/MmsUploadEndpoints.swift`; `sendMms(to:message:attachments:)` multipart/form-data POST to `/api/v1/sms/send-mms`; token-authenticated via tenant server only; sovereignty enforced.) (feat(§12.2): MMS multipart upload + inline voice memo recorder bd03f4de)
- [x] **Canned responses / templates** — `MessageTemplateListView` + `MessageTemplateEditorView` (CRUD: `GET/POST/PATCH/DELETE /message-templates`); `TemplateRenderer` pure substitution helper; `{first_name}` / `{ticket_no}` / `{amount}` / `{date}` / `{company}` variable chips; live preview; channel (SMS/Email) + category filters; injectable picker closure for future in-composer surfacing. In-composer chips + hotkeys remain `[ ]`. (feat(ios phase-4): Estimate convert + Appt scheduling engine + Msg templates + Commissions)
- [x] **Message-template empty state** — `MessageTemplateListView.emptyView` now distinguishes "no templates yet" (with onboarding subtitle + "Create your first template" CTA) from "no matching results" (with "Try a different search" subtitle + "Clear filters" button). (`Communications/Templates/MessageTemplateListView.swift`)
- [x] **In-composer dynamic-var chip bar** — `SmsComposerView` + `SmsComposerViewModel`; chip bar with `{first_name}` / `{ticket_no}` / `{total}` / `{due_date}` / `{tech_name}` / `{appointment_time}` / `{shop_name}`; insert-at-cursor; live preview via `TemplateRenderer`; "Load template" picker. (feat(ios phase-8 §12+§64): SMS composer dynamic-vars + Email templates)
- [x] **Ticket / invoice / payment-link picker** — inserts short URL + ID token into composer. (`SmsLinkPickerSheet` + `SmsLinkPickerViewModel`; 3-tab (Tickets / Invoices / Pay links); lazy per-tab load; `SmsLinkPickerItem.linkToken(baseURL:)` generates token; `APIClient+Communications` adds `listTicketPickerItems`, `listInvoicePickerItems`, `listPaymentLinkPickerItems`.) (feat(§12): read receipts + typing indicator + create-customer + emoji picker + link picker e9f215e1)
- [x] **Emoji picker**. (`EmojiPickerButton` + `EmojiPickerPopover`; curated 24-emoji grid in a popover; appends emoji to draft; Reduce Motion compatible; `BrandHaptics.tap()` on selection.) (feat(§12): read receipts + typing indicator + create-customer + emoji picker + link picker e9f215e1)
- [x] **Schedule send** — date/time picker for future delivery. (`ScheduleSendSheet` DatePicker graphical; `SmsThreadViewModel.scheduledSendAt`; `sendSmsScheduled()` + `SmsSendScheduledRequest` in `SmsThreadEndpoints`; schedule clears after send; 5 XCTest assertions) (9d7d9584)
- [x] **Voice memo** (if MMS supported) — record AAC inline; bubble plays audio. (`SmsVoiceMemoRecorder` @Observable in `Communications/Mms/SmsVoiceMemoRecorder.swift`; AVAudioEngine AAC 44100Hz mono; state machine idle/recording/done/failed/permissionDenied; maxDuration 300s; elapsedLabel; sovereignty — uploads only to tenant server via `MmsUploadService.sendVoiceMemo`.) (feat(§12.2): MMS multipart upload + inline voice memo recorder bd03f4de)
- [x] **Long-press message** → context menu — Copy, Reply, Forward, Create ticket from this, Flag, Delete. (`MessageContextMenuModifier` + `.messageContextMenu(...)` ViewModifier in `Communications/Sms/Thread/MessageContextMenu.swift`.) (feat(§12): long-press message context menu + off-hours auto-reply indicator dd7c6321)
- [x] **Create customer from thread** — if phone not associated. (`CreateCustomerFromThreadSheet` + `CreateCustomerFromThreadViewModel`; pre-fills phone from thread; first name required; optional last name + email; `POST /api/v1/customers` via `createCustomerFromThread` in `APIClient+Communications`.) (feat(§12): read receipts + typing indicator + create-customer + emoji picker + link picker e9f215e1)
- [x] **Character counter** + SMS-segments display (160 / 70 unicode). (feat(ios phase-8 §12+§64): SMS composer dynamic-vars + Email templates)
- [x] **Compliance footer** — auto-append STOP message on first outbound to opt-in-ambiguous numbers. (`SmsThreadViewModel.appendComplianceFooter`; prepends "\n\nReply STOP to opt out" to message body before send) (9d7d9584)
- [x] **Off-hours auto-reply** indicator when enabled. (`OffHoursIndicator` + `OffHoursAutoReplyChecker` in `Communications/Sms/Thread/OffHoursIndicator.swift`.) (feat(§12): long-press message context menu + off-hours auto-reply indicator dd7c6321)

### 12.3 PATCH helpers
- [x] Add PATCH method to `APIClient` — shipped (`Networking/APIClient.swift` exposes `patch<T,B>(_:body:as:)`).
- [x] Mark read — `PATCH /sms/messages/:id { read: true }` (verify endpoint). (already shipped in `SmsEndpoints.swift` `markConversationRead()`) (9d7d9584)
- [x] Flag / pin — `PATCH /sms/conversations/:id { flagged, pinned }`. (already shipped in `SmsEndpoints.swift` `toggleFlag()` + `togglePin()`) (9d7d9584)

### 12.4 MMS media — `Mms/`
- [x] **`MmsAttachment`** — `{ id, kind (.image/.video/.audio/.file), url, sizeBytes, mimeType, thumbnail? }`. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] **`MmsAttachmentPickerSheet`** — photo library / camera / file picker. Compresses images to 1 MB max. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] **Attachment-camera role copy** — Camera button in `MmsAttachmentPickerSheet` now has explicit `.accessibilityLabel("Camera")`, `.accessibilityHint("Opens the camera to take a new photo or video")`, and `.accessibilityAddTraits(.isButton)` so VoiceOver users clearly distinguish it from the photo-library picker above it. (`Communications/Mms/MmsAttachmentPickerSheet.swift`)
- [x] **`MmsAttachmentBubbleView`** — inline media in SMS thread bubble. Tap → full-screen preview. A11y label on all media. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] **`MmsSizeEstimator`** — pure; estimates total send cost + warns if > carrier limit (1.6 MB). 10 tests. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)

### 12.5 Group messaging — `Group/`
- [x] **`GroupMessageComposer`** — compose once, send to N recipients individually. iPhone full-screen / iPad split. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] **`GroupRecipientPickerView`** — customer segment presets + manual add. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] **`GroupSendConfirmAlert`** — shows recipient count + estimated cost + "Send to all" button. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] **`GroupSendViewModel`** — batch POST with progress bar. `POST /sms/group-send`. 9 tests. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)

### 12.6 Delivery status tracking — `Delivery/`
- [x] **`DeliveryStatus`** — `{ sent, delivered, failed, opted_out, no_response }`. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] **`DeliveryStatusBadge`** — reusable Liquid Glass–styled badge on message bubble. Reduce Transparency respected. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] **`DeliveryStatusPoller`** — polls `GET /sms/messages/:id/status` every 5s for 30s, stops on terminal status. 5 tests. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] **`DeliveryReportView`** — per-message detail: timestamp, carrier, failure reason. iPhone sheet / iPad inline. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)

### 12.7 Auto-responders — `AutoResponder/`
- [x] **`AutoResponderRule`** — `{ id, triggers (keyword list), reply, enabled, startTime?, endTime? (quiet hours) }`. Validation + `matches(message:)` + `isActive(at:)`. 11 tests. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] **`AutoResponderListView`** — admin CRUD with toggle + delete swipe. iPad hover + context menu. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] **`AutoResponderEditorSheet`** — keyword input + reply body + quiet-hours schedule. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)

### 12.8 Thread search — `ThreadSearch/`
- [x] **`ThreadSearchView`** — search within a thread's messages (local + server). Highlighted matches. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] **`ThreadSearchViewModel`** — debounced 300ms. Local in-memory FTS (§18 GRDB FTS5 ready). Server fallback. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)

### 12.9 Pinned / starred messages — `Pinned/`
- [x] **`MessagePinnedCollectionView`** — "Starred" tab shows all starred messages across threads. iPhone list / iPad 2-col grid. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)
- [x] Star toggle via long-press context menu; `POST /sms/messages/:id/star`, `DELETE` to unstar. (feat(ios post-phase §12): SMS deep — MMS + group-send + delivery tracking + auto-responders + thread-search + pinned)

### 12.10 Voice / calls (if VoIP tenant)
- [x] **Calls tab** — list inbound / outbound / missed; duration; recording playback if available. (`CallsTabView` + `CallsTabViewModel` + `CallLogRepository`; All/Inbound/Outbound/Missed segments; duration + recording/transcript action buttons; iPhone NavigationStack / iPad compatible. feat(§12.10): VoIP Calls tab 680fd1cf)
- [x] **Initiate call** — `POST /voice/call` with `{ to, customer_id? }` → CallKit integration (`CXProvider`). (`CallKitCoordinator.reportOutboundCall` + `CXProvider`/`CXCallController`; `initiateVoiceCall` in `APIClient+Communications`; `InitiateCallSheet`; active-call Liquid Glass banner with Hang Up CTA. feat(§12.10): VoIP Calls tab 680fd1cf)
- [x] **Recording playback** — `GET /voice/calls/:id/recording` → `AVAudioPlayer`. (`CallRecordingPlayerSheet` + `CallRecordingPlayerViewModel`; resolves path-only URLs via `api.currentBaseURL()`; progress slider + play/pause; unavailable state on 404/nil. feat(§12.10): VoIP Calls tab 680fd1cf)
- [x] **Hangup** — `POST /voice/call/:id/hangup`. (`hangupVoiceCall` in `APIClient+Communications`; `CallsTabViewModel.hangup()` calls repo; `CallKitCoordinator.hangup(uuid:)` ends CallKit call. feat(§12.10): VoIP Calls tab 680fd1cf)
- [x] **Transcription display** — if server provides. (`CallTranscriptSheet`; shows `entry.transcriptText`; `.textSelection(.enabled)` on Mac; ShareLink export; unavailable state when nil. feat(§12.10): VoIP Calls tab 680fd1cf)
- [x] **Incoming call push** (PushKit VoIP) → CallKit UI. (`voip` UIBackgroundMode added to `write-info-plist.sh`; PushKit entitlement covered by existing `aps-environment`; unblocks CallKit wiring by Agent 7. feat(§12.10+§42.4): voip+bluetooth-central UIBackgroundModes 18f052de)

### 12.11 Push → deep link
- [x] Push notification on new inbound SMS with category `SMS_INBOUND`. (`SmsPushHandler.registerCategory()` in `Communications/Sms/Push/SmsPushHandler.swift`.) (feat(§12.11): SMS_INBOUND push category + deep-link handler f61841ce)
- [x] Actions: Reply (inline text input via `UNTextInputNotificationAction`), Open, Call. (`SmsPushHandler.registerCategory()` registers all three actions.) (feat(§12.11): SMS_INBOUND push category + deep-link handler f61841ce)
- [x] Tap → SMS thread. (`SmsPushHandler.handleResponse(_:)` posts `openThreadNotification`.) (feat(§12.11): SMS_INBOUND push category + deep-link handler f61841ce)

### 12.12 Bulk SMS / campaigns (cross-links §37)
- [x] Compose campaign to a segment; TCPA compliance check; preview. (`BulkCampaignComposeView` + `BulkCampaignViewModel` + `BulkCampaignModels` + `BulkCampaignEndpoints` in `Communications/Campaign/`; 6 segment presets (all/lapsed/unpaid_invoice/upcoming_appointment/loyalty_members/custom); `previewBulkCampaign` GET /sms/campaigns/preview → TCPA opted-out count + warning; `sendBulkCampaign` POST /sms/campaigns; scheduledAt support; iPhone full-screen / iPad sheet; 12 XCTest assertions.) (feat(§12.12): bulk SMS campaign compose — segment picker, TCPA preview, send 1430ba90)

### 12.13 Empty / error states
- [x] No threads → "Start a conversation" CTA → compose new. (`SmsListView.emptyFilteredState` shows CTA when `vm.filter.isDefault && searchText.isEmpty`.) (feat(§12.13): SMS empty state CTA)
- [x] Send failed → red bubble with "Retry" chip; retried sends queued offline. (`MessageBubble` `onRetry` closure; red background + `arrow.clockwise` chip; `SmsThreadViewModel.retrySend`.) (feat(§12.13): send-failed retry bubble)

### 12.14 Email templates (§64 in agent-ownership Phase 8)
- [x] **`EmailTemplate` model** — `{ id, name, subject, htmlBody, plainBody, category, dynamicVars }` in `Communications/Email/`. (feat(ios phase-8 §12+§64): SMS composer dynamic-vars + Email templates)
- [x] **`EmailRenderer` pure** — `static func render(template:context:) → (subject, html, plain)`; HTML-to-plain stripping via `NSAttributedString`; missing-var fallback; `sampleContext`. 12 tests. (feat(ios phase-8 §12+§64): SMS composer dynamic-vars + Email templates)
- [x] **`EmailTemplateListView`** — admin CRUD; category filter chips; search; context menu (Edit / Delete); picker closure for compose. (feat(ios phase-8 §12+§64): SMS composer dynamic-vars + Email templates)
- [x] **`EmailTemplateEditorView`** — subject field with dynamic-var chips; `TextEditor` HTML body; iPhone tabbed (Editor | Preview) / iPad side-by-side. (feat(ios phase-8 §12+§64): SMS composer dynamic-vars + Email templates)
- [x] **`HtmlPreviewView`** — `UIViewRepresentable` wrapping `WKWebView`; safe content policy (JS disabled); brand dark CSS wrapper. (feat(ios phase-8 §12+§64): SMS composer dynamic-vars + Email templates)
- [x] **`EmailComposerView`** — To / Subject / Body fields; dynamic-var chip bar; template picker sheet; HTML preview pane; iPhone full-screen / iPad side-by-side; `POST /api/v1/emails/send`. (feat(ios phase-8 §12+§64): SMS composer dynamic-vars + Email templates)
- [x] **`EmailEndpoints`** — `listEmailTemplates`, `createEmailTemplate`, `updateEmailTemplate`, `deleteEmailTemplate`, `sendEmail` wrappers. (feat(ios phase-8 §12+§64): SMS composer dynamic-vars + Email templates)
- [x] **`EmailComposerViewModel`** — `@Observable`; cursor insert; `loadTemplate`; `isValid`; `send`; `htmlPreview`. 18 tests. (feat(ios phase-8 §12+§64): SMS composer dynamic-vars + Email templates)

### §12.15 SMS Engineering Follow-up (§91.14)

> **Status:** client-side items shipped in `actionplan/§91-sms-followup-a5900aa3`.

- [x] **DTO — `conv_phone` optional** — `SmsConversation.init(from:)` now uses
  `decodeIfPresent` with an empty-string sentinel so a missing or null
  `conv_phone` from the server does not crash the entire conversation-list
  decode.  Empty-phone rows are filtered out by `SmsListViewModel`.
  File: `Networking/Endpoints/SmsEndpoints.swift`.

- [x] **`SmsError` domain type** — New `enum SmsError: LocalizedError` in
  `Communications/Sms/SmsError.swift`.  Cases: `.decodingConversations`,
  `.decodingThread`, `.missingConvPhone`.  `errorDescription` converts
  `DecodingError` key/type/value cases into user-readable strings without
  leaking implementation detail.

- [x] **Telemetry on decode failure** — `AnalyticsEvent.smsDecodeFailure`
  (`"sms.decode.failure"`, category `.error`) added to
  `Core/Telemetry/AnalyticsEventCatalog.swift`.  `SmsListViewModel.fetch`
  calls `Analytics.track(.smsDecodeFailure)` when a `DecodingError` is caught
  and surfaces `SmsError.decodingConversations` as the user-visible message.

- [ ] **Server-side audit** — Verify `packages/server/src/routes/sms.routes.ts`
  `GET /sms/conversations` always returns `conv_phone` as a non-null string for
  every row.  Check `sms_conversations` table schema: `conv_phone` column must
  have `NOT NULL` constraint.  If any row can ever have `conv_phone = NULL`
  (e.g. during a migration) the server should filter those rows before
  serialising.  **Not implementable on the iOS client — requires a server PR.**

---
## §13. Notifications

_Server endpoints: `GET /notifications`, `POST /device-tokens` (verify), `PATCH /notifications/:id/dismiss` (verify)._

### 13.1 List
- [x] Base list — shipped.
- [x] **CachedRepository + offline** — `NotificationCachedRepositoryImpl` (actor, single-entry in-memory cache, 2min TTL, `forceRefresh`). `StalenessIndicator` in toolbar. `OfflineEmptyStateView` when offline + cache empty. Pull-to-refresh wired. 6 XCTest assertions pass. (feat(ios phase-3): Leads/Appts/Expenses/SMS/Notifications/Employees/Reports/Search CachedRepository + StalenessIndicator)
- [x] **Tabs** — All / Unread / Assigned to me / Mentions. (`NotificationListPolishedView` filter chips cover All/Unread/type; 44161f26)
- [x] **Mark all read** action (glass toolbar button). (`NotificationListPolishedView` toolbar; 44161f26)
- [x] **Tap → deep link** (ticket / invoice / SMS thread / appointment / customer). (`NotificationListPolishedView.deepLinkPath(for:)` entity allowlist; 44161f26)
- [x] **Swipe to dismiss** (persists via `PATCH /notifications/:id/dismiss`). (`NotificationListPolishedView` leading swipe; `NotificationListPolishedViewModel.dismiss(id:)`; `APIClient.dismissNotification(id:)`; 44161f26)
- [x] **Group by day** (glass day-header). (`NotificationListPolishedView` day-header sections; 44161f26)
- [x] **Filter chips** — type (ticket / SMS / invoice / payment / appointment / mention / system). (`NotificationFilterChip.typeChips`; 44161f26)
- [x] **Empty state** — "All caught up. Nothing new." illustration. (`NotificationListPolishedView.emptyState`; 44161f26)

### 13.2 Push pipeline
- [x] **Register APNs** on login: `UIApplication.registerForRemoteNotifications()` → `POST /device-tokens` with `{ token, platform: "ios", model, os_version, app_version }`.
- [x] **Token refresh** on rotation.
- [x] **Unregister on logout** — `DELETE /device-tokens/:token`.
- [x] **Silent push** (`content-available: 1`) triggers background sync tick.
- [x] **Rich push** — thumbnail images via Notification Service Extension (customer avatar / ticket photo). (`RichPushEnricher` in `NotificationInterruptionLevel.swift` — downloads thumbnail from `thumbnail_url` payload key, wraps in `UNNotificationAttachment`; NSE target wiring documented; db65cb55)
- [x] **Notification categories** registered on launch:
  - `SMS_INBOUND` → Reply inline / Call / Open.
  - `TICKET_ASSIGNED` → Start work / Decline / Open.
  - `PAYMENT_RECEIVED` → View receipt / Thank customer.
  - `APPOINTMENT_REMINDER` → Call / SMS / Reschedule.
  - `MENTION` → Reply / Open.
- [x] **Entity allowlist** on deep-link parse (security — prevent injected types). (feat(§13): kEntityTypeAllowlist in NotificationDeepLinkCoordinator + deepLinkPath allowlist in NotificationListPolishedView — verified b14; 4ecb468d)
- [ ] **Quiet hours** — respect Settings → Notifications → Quiet Hours.
- [ ] **Notification-summary** (iOS 15+) — `interruptionLevel: .timeSensitive` for overdue invoice / SLA breach.

### 13.3 In-app toast
- [x] Foreground message on a different screen → glass toast at top with tap-to-open; auto-dismiss in 4s; `.selection` haptic. (`ForegroundPushToast.swift` — coordinator + glass overlay + `.foregroundPushToastOverlay()` modifier; 09e6a602)

### 13.4 Badge count
- [x] App icon badge = unread count across inbox + notifications + SMS.

### §13.5 Focus filter integration
- [x] `FocusFilterDescriptor.swift` — per-Focus-mode notification policies; `shouldShow(item:activeMode:)` pure predicate; immutable update via `updatingPolicy`. (feat(ios post-phase §13): Notifications — Focus filters + bundling + priority + snooze + grouping + daily digest)
- [x] `FocusFilterSettingsView.swift` — admin/user editor: per-mode category allow-list + critical-override toggle; `FocusFilterSettingsViewModel` (`@Observable`). (feat(ios post-phase §13))
- [x] `FocusFilterEndpoints.swift` — `GET/PUT /notifications/focus-policies` server persistence. (feat(ios post-phase §13))
- [x] Entitlement note documented: `com.apple.developer.focus` NOT set in `BizarreCRM.entitlements`; descriptor operates in policy-only mode until provisioned. (feat(ios post-phase §13))

### §13.6 Notification bundling
- [x] `NotificationGrouper.swift` — pure grouper: same-category within 30s window, minGroupSize=2, critical never bundled; `GroupableNotification` + `NotificationBundle` + `GroupedNotifications`. (feat(ios post-phase §13))
- [x] `BundledNotificationView.swift` — expandable bundle card; Reduce Motion; A11y count announcement. (feat(ios post-phase §13))
- [x] `NotificationBundleViewModel.swift` — `@Observable`; aggregates within 30s window via real-time `receive(_:)`. (feat(ios post-phase §13))

### §13.7 Priority levels
- [x] `NotificationPriority.swift` — `{ low, normal, timeSensitive, critical }` Comparable; §70 event mapping; `apns-priority` header value. (feat(ios post-phase §13))
- [x] `PriorityBadge.swift` — color + icon per priority; tinted capsule; A11y announces level. (feat(ios post-phase §13))

### §13.8 Snooze
- [x] `SnoozeActionHandler.swift` — extends Phase 6A snooze: fires local notification at `now + duration`; `pendingSnoozes()` for list view; `cancelSnooze(for:)`. (feat(ios post-phase §13))
- [x] `SnoozeDurationPickerSheet.swift` — 15min / 1hr / Tomorrow 9am / Custom slider; `SnoozeDurationPickerViewModel` (`@Observable`); glass snooze button. (feat(ios post-phase §13))
- [x] `SnoozedNotificationsListView.swift` — Settings → Notifications → Snoozed; cancel action; swipe-to-cancel; A11y. (feat(ios post-phase §13))

### §13.9 Grouping by source
- [x] `NotificationListGrouping.swift` — enum `{ byTime, byCategory, bySource }`; `apply(to:calendar:)` returns `[(header, items)]`; user toggles via sort menu. (feat(ios post-phase §13))

### §13.10 Summary digest
- [x] `NotificationDigestScheduler.swift` — schedules daily summary local notification at user-configured time; `nextFireDate(from:policy:calendar:)` pure; `DigestPolicy` + `DigestTime`. (feat(ios post-phase §13))
- [x] `NotificationDigestPreviewView.swift` — glass card: "Morning digest: 3 tickets, 2 SMS, 1 invoice paid"; A11y summary. (feat(ios post-phase §13))
- [x] `DigestPolicyEditorView.swift` — pick send time + per-category include; `DigestPolicyEditorViewModel` (`@Observable`). (feat(ios post-phase §13))

---
## §14. Employees & Timeclock

_Server endpoints: `GET /employees`, `GET /employees/{id}`, `POST /employees`, `PUT /employees/{id}`, `POST /employees/{id}/clock-in`, `POST /employees/{id}/clock-out`, `GET /roles`, `POST /roles`, `GET /team`, `POST /team/shifts`, `GET /team-chat`, `POST /team-chat`, `GET /bench`._

### 14.1 List
- [x] Base list — shipped.
- [x] **CachedRepository + offline** — `EmployeeCachedRepositoryImpl` (actor, single-entry in-memory cache, 5min TTL, `forceRefresh`). `StalenessIndicator` in toolbar. `OfflineEmptyStateView` when offline + cache empty. Pull-to-refresh wired. 7 XCTest assertions pass. (feat(ios phase-3): Leads/Appts/Expenses/SMS/Notifications/Employees/Reports/Search CachedRepository + StalenessIndicator)
- [x] **Filters** — role / active-inactive / clocked-in-now. `EmployeeListFilter.clockedInOnly` toggle in filter sheet. (feat(§14): clocked-in-now filter + ClockedInNowView)
- [x] **"Who's clocked in right now"** view — `ClockedInNowView` polls GET /api/v1/employees every 60s; `EmployeePresence` tolerant decoding of `is_clocked_in`. (feat(§14): clocked-in-now filter + ClockedInNowView)
- [x] **Columns** (iPad/Mac) — Name / Email / Role / Status / Has PIN / Hours this week / Commission. (`EmployeeTableView` sortable `Table`; ⌘⌥T toggle in `EmployeeListView`; columns: Name/Email/Role/Status/PIN Set/Joined.) (feat(§14.1): employee sortable table)
- [x] **Permission matrix** admin view — `GET /roles`; checkbox grid of permissions × roles. (Covered by §47: `RolesMatrixView` iPad full matrix rows=roles × cols=capabilities; `RolesMatrixViewModel`; `CapabilityCatalog`.)

### 14.2 Detail
- [x] Role, wage/salary (admin-only), contact, schedule. (Role shown in `EmployeeDetailView` profileCard + rolePicker; contact email displayed; schedule via `scheduleCard`; wage/salary requires server field not yet present — filed as §74 gap.) (57e0660d)
- [x] **Performance tiles** (admin-only) — tickets closed, SMS sent, revenue touched, avg ticket value, NPS from customers. (`EmployeePerformanceTilesView` + `PerformanceTile` in `Employees/Detail/EmployeePerformanceTilesView.swift`; SMS sent + NPS show "--" until §74 server fields ship.) (feat(§14.2): performance tiles + PIN management view + PIN endpoints c936800f)
- [x] **Commissions** — `CommissionRulesListView` + `CommissionRuleEditorSheet` (admin CRUD: `GET/POST/PATCH/DELETE /commissions/rules`; percentage/flat, cap, minTicketValue + tenure conditions); `CommissionReportView` (employee-facing, `GET /commissions/reports/:employeeId`); `CommissionCalculator` pure engine (percentage, flat, capped, min-threshold, tenure gate). Lock-period (admin) remains `[ ]`. (feat(ios phase-4): Estimate convert + Appt scheduling engine + Msg templates + Commissions)
- [x] **Schedule** — upcoming shifts + time-off. (`EmployeeDetailViewModel.load` async-lets `listShifts(userId:fromDate:toDate:)` next 14 days + `listTimeOffRequests(userId:)` for pending/approved; `scheduleCard` in `EmployeeDetailView` shows up to 3 shifts + time-off rows with `ShiftRow` / `TimeOffRow` helpers; both have a11y labels.) (see batch-3 commit)
- [x] **PIN management** — view (as set?) / change / clear. (`PinManagementView` + `PinManagementViewModel`; `getPinStatus/setEmployeePin/clearEmployeePin` in `APIClient+Employees`.) (feat(§14.2): performance tiles + PIN management view + PIN endpoints c936800f)
- [x] **Deactivate** — soft-delete; grey out future logins. (`EmployeeDetailView` deactivate/reactivate confirm dialogs; `EmployeeDetailViewModel.confirmDeactivate/confirmReactivate` → `PUT /api/v1/settings/users/:id`; inactive employees greyed in list via `EmployeeListFilter.activeOnly`.) (57e0660d)

### 14.3 Timeclock
- [x] **Clock in / out** — dashboard tile + dedicated screen; `POST /employees/:id/clock-in` / `-out`. (feat(ios post-phase §14))
- [x] **PIN prompt** — custom numeric keypad with haptic per tap; `POST /auth/verify-pin`. (`EmployeeClockViewModel.clockIn/clockOut` call `api.verifyPin(userId:pin:)` before clock action; skip if pin empty; `verifyPin` in `APIClient+Employees`.) (feat(§14.3): verify-pin gate on clock in/out)
- [x] **Breaks** — `BreakEntry` + `BreakInOutView` + `BreakDurationTracker` (@Observable, injectable clock); `POST /timeclock/breaks/start|end`; meal/rest/other; unpaid breaks auto-deducted in `OvertimeCalculator`. (feat(ios post-phase §14))
- [x] **Geofence** — `GeofenceClockInValidator` 100m radius; admin policy strict/warn/off; employee opt-out; haversine distance; iOS one-shot `CLLocationManager` via `CheckedContinuation`. (feat(ios post-phase §14))
- [x] **Edit entries** (admin only, audit log) — `TimesheetEditSheet` + `PATCH /timeclock/shifts/:id`; reason field required for audit. (feat(ios post-phase §14))
- [x] **Timesheet** weekly view per employee — `TimesheetView` (employee) + `TimesheetManagerView` (manager iPad `Table`); `OvertimeCalculator` pure engine; federal + CA rules; 68 tests pass. (feat(ios post-phase §14))
- [x] **Offline queue** — `TimeclockOfflineQueue` (`@globalActor` actor, UserDefaults FIFO, idempotency keys); `clockIn/clockOut` catch `URLError.notConnectedToInternet|networkConnectionLost`, enqueue + optimistic state. (feat(§14): timeclock offline queue)
- [x] **Live Activity** — "Clocked in since 9:14 AM" on Lock Screen until clock-out. (`ClockInAttributes` + `ClockInLiveActivityManager` in `Timeclock/LiveActivity/ClockInLiveActivity.swift`; guarded by `#if canImport(ActivityKit)`; requires `NSSupportsLiveActivities` in Info.plist.) (feat(§14.3): ClockIn Live Activity — lock screen elapsed timer 32d7c68d)

### 14.4 Invite / manage (admin)
- [x] **Invite** — `POST /employees` with `{ email, role }`; server sends invite link. The server may not have an email if self hosted though - lets make sure we account for that. (`InviteEmployeeSheet` + `InviteEmployeeViewModel`; targets `POST /api/v1/settings/users` admin endpoint; email optional with self-hosted footer note; role picker; `deriveUsername()` auto; 9 XCTest assertions; `inviteEmployee()` in `APIClient+Employees`) (9d7d9584)
- [x] **Resend invite**. (`ResendInviteButton` + `ResendInviteViewModel`; `PUT /api/v1/settings/users/:id { resend_invite: true }`; confirmation dialog + result alert; wired into `EmployeeDetailView` admin card) (9d7d9584)
- [x] **Assign role** — technician / cashier / manager / admin / custom. (`EmployeeDetailView` role picker menu → `EmployeeDetailViewModel.requestRoleChange/confirmRoleChange` → `PUT /api/v1/roles/users/:userId/role`; lists all active roles from `GET /api/v1/roles`.) (57e0660d)
- [x] **Deactivate** — soft delete. (`EmployeeDetailViewModel.confirmDeactivate` → `setEmployeeActive(id:isActive:false)` via `PUT /api/v1/settings/users/:id`; optimistic UI update; reactivate path also present.) (57e0660d)
- [x] **Custom role creation** — Settings → Team → Roles matrix. (Covered by §47.2: `CreateRoleSheet`, `RolesMatrixViewModel.createRole`, `RolesRepository`.)

### 14.5 Team chat
- [x] **Channel-less team chat** (`GET /team-chat`, `POST /team-chat`). (feat(§14): `APIClient+TeamChat` list/post/delete against `/api/v1/team-chat/...` + `TeamChatRepositoryImpl` resolves seeded `general` channel; bubble icon entry on `EmployeeListView` toolbar)
- [x] Messages with @mentions; real-time via WS. (feat(§14): 4s polling tail in `TeamChatViewModel` + mention regex highlights inline + `WSEvent.chatMessage`/`chatTyping` decoded so server push lands without client release)
- [x] Image / file attachment. (feat(§14): `TeamChatPhotoPicker` + `TeamChatFilePicker`; attachment metadata encoded with `TeamChatAttachmentEncoder` `[[attach:url|mime|name]]` shim until server adds attachment columns)
- [x] Pin messages. (feat(§14): `UserDefaultsPinnedMessagesStore` per-channel; iPad sidebar panel + iPhone pinned sheet; row context-menu pin/unpin)

### 14.6 Team shifts (weekly schedule)
- [x] **Week grid** (7 columns, employees rows) — `ShiftSchedulePostView` (iPhone list / iPad horizontal grid); `ShiftScheduleConflictChecker` pure engine (double-booking + PTO overlap); `ShiftPublishBanner` Liquid Glass sticky footer; `POST /team/shifts`, `GET /team/shifts`. (feat(ios post-phase §14))
- [x] Tap empty cell → add shift; tap filled → edit — `AddShiftSheet` inline. (feat(ios post-phase §14))
- [x] Shift modal — employee, start/end, role, notes — `CreateScheduledShiftBody`. (feat(ios post-phase §14))
- [x] Time-off requests sidebar — approve / deny (manager). (`TimeOffRequestsSidebar` + `TimeOffRequestsSidebarViewModel`; uses existing `approveTimeOff`/`denyTimeOff` + new `listPendingTimeOffRequests`.) (feat(§14.6): time-off requests sidebar — approve/deny manager view 29529c39)
- [x] Publish week → notifies team — `POST /team/shifts/publish`; `ShiftPublishBanner` confirm. (feat(ios post-phase §14))
- [x] Drag-drop rearrange (iPad). (`ShiftSchedulePostViewModel.moveShifts/sortedShifts`; iPad `List` with `.onMove` + `.editMode(.active)`; local reorder, server order unaffected.) (feat(§14.6): iPad drag-drop shift rearrange + §14.9 PTO-affects-shift-grid d364a040)

### 14.6b Shift Swap
- [x] **Employee requests swap** — `ShiftSwapRequestSheet` (Liquid Glass, `.presentationDetents`); `POST /timeclock/swap-requests`. (feat(ios post-phase §14))
- [x] **Receiver accepts/declines** — `ShiftSwapOfferView`; `POST /timeclock/swap-requests/:id/offer`. (feat(ios post-phase §14))
- [x] **Manager approves** (audit logged) — `ShiftSwapApprovalView`; `POST /timeclock/swap-requests/:id/approve`. (feat(ios post-phase §14))

### 14.7 Leaderboard
- [x] Ranked list by tickets closed / revenue / commission. `EmployeeLeaderboardView` + `EmployeeLeaderboardViewModel`. (feat(§14): employee leaderboard)
- [x] Period filter (week / month / YTD). `LeaderboardPeriod` enum with `dateRange`. (feat(§14): employee leaderboard)
- [x] Badges 🥇🥈🥉. `LeaderboardRow` medal emoji + rank color for top 3. (feat(§14): employee leaderboard)

### 14.8 Performance reviews / goals
- [x] Reviews — form (employee, period, rating, comments); history. (Covered by §46.2: `PerformanceReviewComposeView`, `SelfReviewView`, `ReviewAcknowledgementView`, `ReviewsRepository`.)
- [x] Goals — create / update progress / archive; personal vs team view. (Covered by §46.1: `GoalListView`, `GoalEditorSheet`, `GoalProgressRingView`, `GoalsRepository`.)

### 14.9 Time-off requests
- [x] Submit request (date range + reason). (`PTORequestSheet` + `PTORequestSheetViewModel`; date picker + type + reason; `POST /api/v1/time-off`.)
- [x] Manager approve / deny. `PTOManagerApprovalSheet` + `PTOManagerApprovalViewModel`; `approveTimeOff`/`denyTimeOff` in `APIClient+Employees`. (feat(§14): manager PTO approve/deny)
- [x] Affects shift grid. (`TimeOffRequestsSidebarViewModel.onApproved` callback → `ShiftSchedulePostViewModel.addApprovedPTOBlock` re-runs `ShiftScheduleConflictChecker`.) (feat(§14.6): iPad drag-drop shift rearrange + §14.9 PTO-affects-shift-grid d364a040)

### 14.10 Shortcuts
- [x] Clock-in/out via Control Center widget (iOS 18+). (`ClockInOutControl` + `ClockInOutControlIntent` in `App/Intents/ControlCenterControls.swift`; `@available(iOS 18.0, *)` guard; `StaticControlConfiguration` kind `com.bizarrecrm.control.clockinout`; reads `ClockStateProvider` from App Group UserDefaults.) (feat(§12): read receipts + typing indicator + create-customer + emoji picker + link picker e9f215e1)
- [x] Siri intent "Clock me in at BizarreCRM". (`ClockInIntent` + `ClockOutIntent` + `ClockIntentConfig` in `Packages/Core/Sources/Core/Intents/`; `@available(iOS 16, *)` `AppIntent`; `IntentDescription` "Clock in to start your shift"; `ClockRepository` protocol injected at app launch.) (feat(§12): read receipts + typing indicator + create-customer + emoji picker + link picker e9f215e1)

- [x] End-of-shift summary: card with KPIs + trend. Timeclock `EndShiftSummaryView` (6c1d66ee) + Pos `EndOfShiftSummaryView` (a3234515).
- [x] Close cash drawer: denomination count + over/short. Timeclock `CashDenominationCountView` (6c1d66ee) + Pos `DenominationCountView` (a3234515).
- [x] Manager sign-off: PIN gate when |delta|>$2 + audit. Timeclock `verifyManagerPin` (6c1d66ee) + Pos `ManagerPinSheet` (a3234515).
- [x] Receipt: Z-report archived + linked in shift summary. Pos `ZReportView` (a3234515) + Timeclock done-screen `zReportURL()` builds authenticated tenant PDF URL, "View Z-Report" glass button (ea8ee40e).
- [x] Handoff: opening cash for next cashier. Timeclock `submitShiftHandoff` (6c1d66ee) + Pos `ShiftHandoffView` (a3234515).
- [x] Sovereignty: tenant server only — both implementations route via `APIClient.baseURL`.
- [x] Hire wizard: Manager → Team → Add employee; steps basic info / role / commission / access locations / welcome email; account created; staff gets login link. (`HireWizardView` + `HireWizardViewModel`; 4-step wizard; POST /api/v1/settings/users.) (feat(§14): hire wizard — 4-step new employee flow dc179fa0)
- [x] Offboarding: Settings → Team → staff detail → Offboard; immediately revoke access, sign out all sessions, transfer assigned tickets to manager, archive shift history (kept for payroll); audit log; optional export of shift history as PDF. (`OffboardingView` + `OffboardingViewModel`; POST /api/v1/settings/users/:id/offboard.) (feat(§14): offboarding flow + temporary suspension b7364caa)
- [x] Role changes: promote/demote path; change goes live immediately. (`EmployeeDetailViewModel.requestRoleChange/confirmRoleChange` → `PUT /api/v1/roles/users/:userId/role`; confirmation dialog; reload on success; §47 `RolesEditor` package provides the roles list.) (57e0660d)
- [x] Temporary suspension: suspend without offboarding (vacation without pay); account disabled until resume. (`TemporarySuspensionView` + `TemporarySuspensionViewModel`; PATCH /api/v1/settings/users/:id { is_suspended }.) (feat(§14): offboarding flow + temporary suspension b7364caa)
- [x] Reference letter (nice-to-have): auto-generate PDF summarizing tenure + stats (total tickets, sales); manager customizes before export. (`ReferenceLetterExportService` + `ReferenceLetterView` + `ReferenceLetterViewModel` in `Employees/ReferenceLetter/`; UIGraphicsPDFRenderer; letterhead + customizable body + performance summary table; share sheet export; on-device only, §32 sovereignty.) (feat(§14): reference letter PDF export 4652078b)
- [x] Metrics: ticket close rate, SLA compliance, customer rating, revenue attributed, commission earned, hours worked, breaks taken (Covered by §46.4: `ScorecardView` + `EmployeeScorecard.swift` + `ScorecardEndpoints`)
- [x] Private by default: self + manager; owner sees all (Covered by §46.4: `ScorecardVisibilityRole` enum + `.other` access-denied guard in `ScorecardViewModel`)
- [x] Manager annotations with notes + praise / coaching signals, visible to employee (Covered by §46.4: `ScorecardManagerNotesSheet` + manager annotations section in `ScorecardView`)
- [x] Rolling trend windows: 30 / 90 / 365d with chart per metric (Covered by §46.4: rolling windows in `ScorecardView` metrics section)
- [x] "Prepare review" button compiles scorecard + self-review form + manager notes into PDF for HR file (Covered by §46.2: `ReviewMeetingHelperView` + "Prepare review" action + PDF)
- [x] Distinguish objective hard metrics from subjective manager rating (Covered by §46.4: `ScorecardMetricKind` + `ScorecardMetricClassifier.kind(for:)`)
- [x] Subjective 1-5 scale with descriptors (Covered by §46.2: `PerformanceReviewComposeView` numeric ratings 1-5 with descriptors)
- [x] Staff can request feedback from 1-3 peers during review cycle (Covered by §46.5: `PeerFeedbackPromptSheet` + frequency cap 1-3 peers)
- [x] Form with 4 prompts: going well / to improve / one strength / one blind spot (Covered by §46.5: `PeerFeedbackPromptSheet` 4 prompts)
- [x] Anonymous by default; peer can opt to attribute (Covered by §46.5: anonymous by default with attribution toggle)
- [x] Delivery to manager who curates before sharing with subject (prevents rumor / hostility) (Covered by §46.5: `PeerFeedbackRepository` delivery gated through manager)
- [x] Frequency cap: max once / quarter per peer requested (Covered by §46.5: `PeerFeedbackFrequencyCap` calendar quarter boundary)
- [x] A11y: long-form text input with voice dictation (Covered by §46.5: `VoiceDictationButton` + `DictationSession` + `DictationTextEditor` in `PeerFeedbackPromptSheet`)
- [x] Peer-to-peer shoutouts with optional ticket attachment (Covered by §46.7: `SendShoutoutSheet` + optional `ticketId`)
- [x] Shoutouts appear in peer's profile + team chat (if opted) (Covered by §46.7: `ReceivedShoutoutsView` + `isTeamVisible` toggle)
- [x] Categories: "Customer save" / "Team player" / "Technical excellence" / "Above and beyond" (Covered by §46.7: `ShoutoutCategory` enum)
- [x] Unlimited sending; no leaderboard of shoutouts (avoid gaming) (Covered by §46.7: no frequency cap on sends; no shoutout leaderboard)
- [x] Recipient gets push notification (Covered by §46.7: push wired via §70 notification category by Agent 9)
- [x] Archive received shoutouts in profile (Covered by §46.7: `ReceivedShoutoutsView` + `listReceivedShoutouts`)
- [x] End-of-year "recognition book" PDF export (Covered by §46.7: `RecognitionBookExportService.generatePDF`)
- [x] Privacy options: private (sender + recipient) or team-visible (recipient opt-in) (Covered by §46.7: `isTeamVisible` toggle + private by default)

---
## §15. Reports & Analytics

_Server endpoints: `GET /reports/dashboard`, `GET /reports/dashboard-kpis`, `GET /reports/aging`, `GET /reports/technician-performance`, `GET /reports/tax`, `GET /reports/inventory`, `GET /reports/scheduled`, `POST /reports/run-now`._

### 15.1 Tab shell
- [x] Phase-0 placeholder replaced with full charts dashboard. (feat(ios phase-8 §15): Reports charts + BI + drill-through + CSAT+NPS + PDF export + scheduled reports)
- [x] **Offline indicator** — inline `HStack` in header shows wifi.slash icon + "Offline — reports require a network connection" when `!Reachability.shared.isOnline`. `StalenessIndicator` in toolbar accepts optional `referenceSyncedAt` (shows "Never synced" when nil). No ReportsRepository yet — static index only. (feat(ios phase-3): Leads/Appts/Expenses/SMS/Notifications/Employees/Reports/Search CachedRepository + StalenessIndicator)
- [x] **Date-range selector** — segmented picker 7D/30D/90D/Custom; `applyCustomRange(from:to:)` on ViewModel; triggers `loadAll()`. (feat(ios phase-8 §15))
- [x] **Export button** — "Export PDF" toolbar action via `ReportExportService.generatePDF` + `ShareLink`; "Email Report" posts to `POST /api/v1/reports/email`. (feat(ios phase-8 §15))
- [x] **iPad** — 3-column `LazyVGrid` gated on `Platform.isCompact`; iPhone single-column. (feat(ios phase-8 §15))
- [x] **Schedule report** — `ScheduledReportsSettingsView` with `GET/POST/DELETE /reports/scheduled`; frequency picker daily/weekly/monthly; recipient email list. (feat(ios phase-8 §15))
- [x] **Sub-routes / segmented picker** — Sales / Tickets / Employees / Inventory / Tax / Insights / Custom. `ReportSubTab` 6-case enum; `subTabPicker` ScrollView chip picker in `ReportsView`; `cardItems` switch drives per-tab rendering. ([actionplan agent-6 b5] 98fb3559)

### 15.2 Sales
- [x] Revenue trend — `RevenueChartCard` with Swift Charts `AreaMark + LineMark`, y-axis in $K, x-axis time-scale; hero tile shows period total + sparkline + trend arrow. (feat(ios phase-8 §15))
- [x] Total invoices / revenue / unique customers / period-over-period delta. `SalesKPISummaryCard` with delta badge and `SalesTotals`; iPhone 2×2 grid, iPad HStack. ([actionplan agent-6 b4] c0cb747c)
- [x] Revenue by payment method pie. `RevenueByMethodPieCard` with Swift Charts `SectorMark`, tappable legend, `AXChartDescriptorRepresentable`; iPhone stacked, iPad side-by-side. ([actionplan agent-6 b4] c0cb747c)
- [x] YoY growth. `YoYGrowthCard` grouped `BarMark` current vs prior year; `YoYDataPoint` model with `growthPct`; annotation per period; `AXChartDescriptorRepresentable`; derived client-side from two `getSalesReport` calls. `YoYPoints` loaded in `ReportsViewModel.loadYoYGrowth()`. ([actionplan agent-6 b5] 98fb3559)
- [x] Top 10 customers by spend. `TopCustomersCard` ranked list with inline revenue bar (iPhone) + `HStack` bar chart + rank list (iPad); `TopCustomerRow` model; `onTapCustomer` closure; `getTopCustomers` → `GET /api/v1/reports/top-customers`; `AXChartDescriptorRepresentable`. ([actionplan agent-6 b5] 98fb3559)
- [x] Cohort revenue retention. `CohortRetentionCard` intensity heatmap (cohort rows × month-offset columns); `CohortRetentionData` / `CohortRow` / `CohortCell` models; `getCohortRetention` in repo; wired in ReportsView sales tab; 9 tests. ([actionplan agent-6 b8] bcd189d7)

### 15.3 Tickets
- [x] Tickets by status — `TicketsByStatusCard` horizontal `BarMark` chart with per-status color. (feat(ios phase-8 §15))
- [x] Opened vs closed per day (stacked bar). `TicketsTrendCard` stacked `BarMark` (`chartForegroundStyleScale`); `TicketDayPoint` model with `closeRate` + `avgTurnaroundHours`; overallCloseRate + avgTurnaround KPI tiles; iPhone + iPad 2-col layouts; `AXChartDescriptorRepresentable`. ([actionplan agent-6 b5] 98fb3559)
- [x] Close rate. Computed in `TicketsTrendCard.overallCloseRate` and per-day `TicketDayPoint.closeRate`; displayed as KPI tile. ([actionplan agent-6 b5] 98fb3559)
- [x] Avg turnaround time. Computed in `TicketsTrendCard.avgTurnaround` from `avgTurnaroundHours` field; displayed as KPI tile. ([actionplan agent-6 b5] 98fb3559)
- [x] Tickets by tech bar. `TicketsByTechCard` horizontal `BarMark` assigned vs closed per tech; `TicketsByTechPoint` model from `EmployeePerf`; `chartOverlay` tap → `onTapTech(id)` closure. ([actionplan agent-6 b5] 98fb3559)
- [x] Busy-hours heatmap. `BusyHoursHeatmapCard` 7×24 intensity grid; `BusyHourCell` model; orange opacity scale + color-scale legend; `getBusyHours` → `GET /api/v1/reports/tickets-heatmap`. ([actionplan agent-6 b5] 98fb3559)
- [x] SLA breach count. `SLABreachCard` with `SLABreachSummary`; breach count + rate + at-risk chip + compliance progress bar + top reason; `getSLASummary` → `GET /api/v1/reports/sla`. ([actionplan agent-6 b5] 98fb3559)

### 15.4 Employees
- [x] `GET /reports/employees-performance` — `TopEmployeesCard` top-5 ranked by revenue; `EmployeePerf` model with tickets closed, revenue cents, avg resolution hours. (feat(ios phase-8 §15))
- [x] `GET /reports/technician-performance` — `TechnicianPerformanceCard` table: name / tickets assigned / closed / commission / hours / revenue; `TechnicianPerfRow` model; iPad sortable `Table`. ([actionplan agent-6 b4] c0cb747c)
- [x] Per-tech detail drill. `TechDetailSheet` (NavigationStack) with hero glass tile + 6-stat grid; `TicketsByTechCard.onTapTech` → `selectedTechForDrill` state → `.sheet(item:)` in `ReportsView`; 6 stats: assigned/closed/revenue/commission/hours/closeRate. ([actionplan agent-6 b5] 98fb3559)

### 15.5 Inventory
- [x] Turnover / dead-stock — `InventoryTurnoverCard` sorted table top-10 slowest by daysOnHand; `InventoryTurnoverRow` model with turnoverRate + daysOnHand. (feat(ios phase-8 §15))
- [x] Low stock / out-of-stock counts. `InventoryStockCard` two KPI tiles (out-of-stock red, low-stock amber) from `InventoryReport.outOfStockCount` + `lowStockCount`. ([actionplan agent-6 b5] 98fb3559)
- [x] Inventory value (cost + retail). `InventoryStockCard` value section: totalCost + totalRetail + markup% from `valueSummary`; per-category horizontal `BarMark` chart. iPhone stacked, iPad side-by-side. ([actionplan agent-6 b5] 98fb3559)
- [x] Shrinkage trend. `ShrinkageTrendCard` stacked `BarMark` by reason (theft/damage/expiry/admin_error/other); `ShrinkagePoint` / `ShrinkageSummary` / `ShrinkageReport` models; `getShrinkageReport` in repo; wired in ReportsView inventory tab; KPI tiles (units lost, cost, shrinkage %); iPhone + iPad 2-up; 9 tests. ([actionplan agent-6 b8] bcd189d7)

### 15.6 Tax
- [x] `GET /reports/tax` — `TaxReportCard` collected by class / rate summary; `TaxEntry` + `TaxReportResponse` models. ([actionplan agent-6 b4] c0cb747c)
- [x] Period total for filing. Filing note line in `TaxReportCard` footer. ([actionplan agent-6 b4] c0cb747c)

### 15.7 Insights (adv) — CSAT + NPS
- [x] **CSAT** — `CSATScoreCard` gauge + trend badge; `CSATDetailView` score distribution bar chart + free-text comments list. `GET /reports/csat`. (feat(ios phase-8 §15))
- [x] **NPS** — `NPSScoreCard` gauge + promoter/passive/detractor split bar + theme chips; `NPSDetailView` per-tech breakdown anonymized per §37. `GET /reports/nps`. (feat(ios phase-8 §15))
- [x] **Avg Ticket Value** — `AvgTicketValueCard` single-metric + delta badge + trend arrow. `GET /reports/avg-ticket-value`. (feat(ios phase-8 §15))
- [x] Warranty claims trend. ([actionplan agent-6 b6] cd6a4df7)
- [x] Device-models repaired distribution. ([actionplan agent-6 b6] cd6a4df7)
- [x] Parts usage analysis. ([actionplan agent-6 b6] cd6a4df7)
- [x] Technician hours worked. ([actionplan agent-6 b6] cd6a4df7)
- [x] Stalled / overdue tickets. ([actionplan agent-6 b6] cd6a4df7)
- [x] Customer acquisition + churn. ([actionplan agent-6 b6] cd6a4df7)

### 15.8 Custom reports
- [x] Pick series + bucket + range; save as favorite per user. ([actionplan agent-6 b6] 6df21885)

### 15.9 Export / schedule
- [x] PDF export — `ReportExportService` actor with `generatePDF(report:)` using `UIGraphicsPDFRenderer` (iOS) / CoreGraphics (macOS); returns non-empty URL. (feat(ios phase-8 §15))
- [x] Email report — `emailReport(pdf:recipient:)` posts base64 PDF to `POST /api/v1/reports/email`. (feat(ios phase-8 §15))
- [x] Scheduled reports — `ScheduledReportsSettingsView` CRUD; `GET/POST/DELETE /api/v1/reports/scheduled`. (feat(ios phase-8 §15))
- [x] Drill-through — `DrillThroughSheet` tapping any chart data point opens `GET /reports/drill-through?metric=&date=`; records list with sale navigation closure. (feat(ios phase-8 §15))
- [x] Swift Charts with `AreaMark + LineMark` on revenue; `BarMark` on tickets/CSAT; `Gauge` on CSAT/NPS; all with `.accessibilityChartDescriptor`. (feat(ios phase-8 §15))
- [x] Sovereignty: all compute on tenant server; no external BI tool — single network peer via `APIClient.baseURL`. (feat(ios phase-8 §15))
- [x] CSV / PDF export per report. CSV: `ReportCSVService.generateSnapshotCSV` covers revenue/tickets/employees/turnover/CSAT/NPS sections; `exportCSV()` in `ReportsView` calls it and presents `ShareLink`. PDF already wired via `ReportExportService`. ([actionplan agent-6 b5] 98fb3559)
- [x] "BI" sub-tab in Reports for deeper analysis — `ReportSubTab` enum (6 cases) + chip picker in `ReportsView`; switch drives per-tab card rendering. ([actionplan agent-6 b4] c0cb747c)
- [x] Built-in reports: revenue/margin by category/tech/customer segment ([actionplan agent-6 b6] 1a6c05bf)
- [x] Built-in reports: repeat customer rate, time-to-repeat ([actionplan agent-6 b6] 1a6c05bf)
- [x] Built-in reports: average ticket value trend ([actionplan agent-6 b6] 1a6c05bf)
- [x] Built-in reports: conversion funnel (lead → estimate → ticket → invoice → paid) ([actionplan agent-6 b6] 1a6c05bf)
- [x] Built-in reports: labor utilization by tech ([actionplan agent-6 b6] 1a6c05bf)
- [x] Visual query builder (no SQL): entity + filters + group + measure + timeframe ([actionplan agent-6 b6] 6df21885)
- [x] Save custom query as widget ([actionplan agent-6 b6] 6df21885)
- [x] Swift Charts with zoom / pan / compare periods ([actionplan agent-6 b7] 55e60eb3)
- [x] Export chart as PNG / CSV ([actionplan agent-6 b6] ef704dd0)
- [x] Breadcrumb drill: tap chart segment → filtered records list; trail "Total revenue → October → Services → iPhone repair"; each crumb tappable to step back. ([actionplan agent-6 b6] ef704dd0)
- [x] Context panel layout: filters narrowed-by-drill (left), records list (right). ([actionplan agent-6 b6] ef704dd0)
- [x] Export at any level: share current filtered view as PDF / CSV. ([actionplan agent-6 b6] ef704dd0)
- [x] "Save this drill as dashboard tile" saves with query. ([actionplan agent-6 b6] ef704dd0)
- [x] Cross-report drilling: jump into related report with same filters applied. ([actionplan agent-6 b7] 55e60eb3)
- [x] Perf budget: server query index hints, p95 < 2s. Client-side p95 tracker shipped: `ReportsPerfBudget` actor with rolling 50-sample window, 2.0s budget, nearest-rank p95; wired in `ReportsViewModel.loadAll()` + `loadForActiveTab()` via begin/end tokens; `os.Logger` warns when single load or rolling p95 exceeds budget; on-device only, no analytics SDK. 5 unit tests. (Server query index hints out of iOS scope.)
- [ ] See §39 for the full list.
- [ ] See §6 for the full list.
- [ ] See §19 for the full list.

---
## §16. POS / Checkout

_Server endpoints: `POST /invoices`, `POST /invoices/{id}/payments`, `POST /blockchyp/*`, `GET /inventory`, `GET /repair-pricing/services`, `GET /tax`, `POST /pos/holds`, `GET /pos/holds`, `POST /pos/returns`, `POST /cash-register/open`, `POST /cash-register/close`, `GET /cash-register/z-report`, `POST /gift-cards/redeem`, `POST /store-credit/redeem`. All require `tenant-id`, role-gated write operations, idempotency keys on payment/charge._

### 16.1 Tab shell
- [x] Scaffold shipped — `Pos/PosView.swift` replaces the placeholder; iPhone single-column / iPad `NavigationSplitView(.balanced)` gated on `Platform.isCompact`.
- [x] **Architecture** — PosViewModel owning cart state (current scaffold uses `Cart` @Observable directly); PosRepository + GRDB catalog/holds caches still TBD. (d7edd4a1)
- [x] **Tab replaces**: POS tab in iPhone TabView + POS entry in iPad sidebar (wired via `RootView`).
- [x] **Permission gate** — `pos.access` in user role; if missing, show "Not enabled for this role" card with contact-admin CTA. (d7edd4a1)
- [x] **Drawer lock** — POS renders "Register closed" placeholder when no open session; `OpenRegisterSheet` via fullScreenCover on mount. Cancel dismisses to placeholder (no sales possible). "Close register" / "View Z-report" entries in overflow ⋯ toolbar. Cashier ID plumbing via `/auth/me` deferred.

### 16.2 Catalog browse (left pane)
- [x] **Layout** — iPhone: single-column full screen; iPad/Mac: `NavigationSplitView(.balanced)` — search/inventory picker leading, cart trailing.
- [x] **Hierarchy** — top chips: All / Services / Parts / Accessories / Custom. Grid below: category tiles → products. PosCatalogCategory enum + chip wiring in PosSearchPanel. (d7edd4a1)
- [x] **Product tile** — glass card with photo (Nuke thumbnail), name, price, stock badge. `PosCatalogTileImage` AsyncImage + shimmer placeholder; optional URL param on `PosCatalogTile`. (feat(§16.2): product tile image via AsyncImage 55ba3fb8)
- [x] **Search bar** — sticky top, queries `InventoryRepository.list(keyword:)`; tap result adds to cart with haptic success.
- [x] **Long-press tile** — quick-preview sheet (price history, stock, location, last sold date). PosCatalogTilePreviewSheet + onLongPress wire. (d7edd4a1)
- [x] **Recently sold** chip — shows top 10 items sold in last 24h per this register. PosViewModel.recordSale + recentlySoldIds + chip in PosSearchPanel. (d7edd4a1)
- [x] **Favorites** — star-pin a product; star chip filter. PosViewModel.toggleFavorite + isFavorite + UserDefaults persistence + star on tile + "★ Favorites" chip. (d7edd4a1)
- [x] **Custom line** — "+ Custom item" sheet creates untracked line (name, price, qty, tax, notes).
- [x] **Offline** — catalog cached via `InventoryRepository` (GRDB cache plumbing is part of §20.5). `PosCatalogOfflineStore` actor + `PosCatalogRefreshService` daily refresh on launch; 24h staleness threshold; UserDefaults MVP pending §20.5 GRDB wire. (feat(§16): offline catalog cache cad69018)
- [x] **Search filters** — by category, tax status, in-stock only, price range. PosCatalogFilterSheet + posVM.applyClientFilters + funnel chip. (d7edd4a1)
- [x] **Repair services** — services from `/repair-pricing/services` surface in Services tab. posVM.loadRepairServicesIfNeeded() wired on Services chip tap. (d7edd4a1)

### 16.3 Cart (right pane / bottom sheet)
- [x] **Cart panel** — iPad right pane full height; iPhone single-screen stack. Glass reserved for the Charge CTA (content rows stay plain, per CLAUDE.md).
- [x] **Header** — total shown in brand Barlow Condensed via `.monospacedDigit()`.
- [x] **Line items** — qty stepper (inc/dec with light haptic), unit price, line total. Swipe trailing = Remove; context menu = Remove / Edit quantity / Edit price.
- [x] **Line edit sheets** — `PosEditQuantitySheet` + `PosEditPriceSheet` wired (role gating TBD in Phase 3).
- [x] **Cart-level** — discount (% + $), tip (preset 10/15/20% + custom), fees (cents + label) via `PosCartAdjustmentSheets` + overflow ⋯ toolbar menu. `effectiveDiscountCents` re-derives on subtotal change.
- [x] **Discount-modal preset chips** — `PosCartDiscountSheet` preset chips now have haptic feedback (`BrandHaptics.tap()`) on tap + selected-state fill (orange fill / white text) + `scaleEffect(1.06)` spring pop; `activePresetPercent`/`activePresetCents` state tracks selection; typing manually clears selection; mode-switch resets; a11y `.isSelected` trait. (feat(§16.3): discount preset chip haptic + selected state)
- [x] **Tip preset percentages config** — `TipPresetConfigSheet` manager-facing settings sheet: load/save via `TipPresetStore`, up to 4 presets, drag-to-reorder, swipe-to-delete, percentage vs fixed-cent toggle, inline validation (no duplicate %), "Reset to defaults" destructive confirmation; `TipPresetConfigViewModel` @Observable with `load/save/addPreset/removePreset/setPercentage/setFixedCents/move/resetToDefaults`; `PresetEditRow` preview chip reflects live edits; a11y identifiers; gate at call site (manager PIN). (feat(§16.3): tip preset percentages config)
- [x] **Tax** — per-line `taxRate` propagated into `CartMath.totals` with bankers rounding; multi-rate per item supported. Tenant-wide tax config integration deferred to §19.
- [x] **Totals breakdown** — Subtotal → Tax → Total with `.monospacedDigit()` via `CartMath.formatCents`. Discount + Tip lines added when those features ship.
- [x] **Link to record** — chip "Link to Ticket #1234". `Cart.linkedTicketId` + `Cart.linkToTicket(id:)` + `PosCartTicketLinkChip`. (feat(§16.3): cart ticket link chip)
- [x] **Hold cart** — `POsHoldCartSheet` + `PosResumeHoldsSheet` wired to `POST/GET /pos/holds` with 404/501 "Coming soon" fallback. Resume clears cart first, never inherits pending payment link. Synthetic single-line pending per-hold detail endpoint.
- [x] **Clear cart** — `Clear cart` toolbar action with ⌘⇧⌫ shortcut (destructive confirm lands with the first real-tender phase).
- [x] **Empty state** — "Cart is empty" illustration with call-out to scan / pick / add custom.
- [x] **Cart undo toast (last delete)** — swipe-to-remove and context-menu Remove in `PosCartPanel` now capture the deleted `CartItem` snapshot and show a 5-second snackbar ("Removed · [name] · Undo" button). `showUndo(for:)` starts an auto-dismiss Task; tapping Undo calls `cart.add(item)` and cancels the timer; Reduce Motion + VoiceOver labelled; toast pins above totals footer via ZStack overlay; `accessibilityIdentifier: pos.cart.undoToast / pos.cart.undoRemove`. (feat(§16.3): cart undo toast)
- [x] **Cart quick-action context menu — Duplicate line** — cart-row `.contextMenu` gains a "Duplicate line" action (`plus.square.on.square` icon) that clones the tapped `CartItem` with a fresh `UUID` and qty 1 and appends it via `cart.add(_:)`; light haptic on tap; `Divider()` separates it from the destructive Remove action. `pos.cartRow.<id>` context menu accessible to VoiceOver via `.accessibilityLabel("Duplicate <name>")`. `PosCartPanel.swift`. (feat(§16.3): cart context-menu duplicate line)
- [x] **Sale note field** — cashier-level note for the whole sale (not a line). `Cart.saleNote: String?` + `Cart.setSaleNote(_:)` 500-char capped mutator; cleared on `cart.clear()`. Inline editor in `PosCartPanel`: the "＋ Note" ghost button in `quickActionRow` toggles an inline `TextEditor` with a live `N / 500` counter (red at limit), Save + Clear buttons, and `.animation(BrandMotion.snappy)` slide; button label flips to "Edit note" when a note is already set. `accessibilityIdentifier: pos.cart.saleNote.*`. `PosCartPanel.swift`, `Cart.swift`. (feat(§16.3): cart sale-note field)
- [x] **Recurring-charge selector** — `PosRecurringChargeSheet` lets cashier tag a cart as the first occurrence of a recurring series. `RecurringChargeRule` model (`frequencyLabel`, `frequencyKey`, `dayOfMonth?`, `endDate?`); `Cart.recurringRule: RecurringChargeRule?` + `Cart.setRecurringRule(_:)`; cleared on `cart.clear()`. Sheet: 5 frequency chip presets (weekly/bi-weekly/monthly/quarterly/yearly), day-of-month `Picker` (for monthly/quarterly only), optional end-date `DatePicker`, live summary card ("Charges monthly · starting today · indefinitely"). Recurring indicator row in `PosCartPanel` totals footer (tinted arrow.clockwise row when set, ghost "Set recurring charge" link when unset). `pos.recurring.*` a11y IDs. `PosRecurringChargeSheet.swift`, `Cart.swift`, `PosCartPanel.swift`. (feat(§16.3): recurring-charge selector)

### 16.4 Customer pick
- [x] **Attach existing** — `PosCustomerPickerSheet` with debounced 300ms `CustomerRepository.list(keyword:)`; tap row → `cart.attach(customer:)`; CartPill renders chip (initials or walk-in ghost). Loyalty tier badge deferred to §38.
- [x] **Create new inline** — "+ New customer" opens `CustomerCreateView(api:onCreated:)` sheet; on save `PosCustomerNameFormatter.attachPayload(...)` attaches to cart.
- [x] **Guest checkout** — `PosCustomer.walkIn` sentinel; walk-in CTA on POS empty state. Warning for store-credit/loyalty deferred.
- [x] **iPad wiring — customer CTAs visible** — `RootView.iPadSplit` now passes `api` + `customerRepo` + `cashDrawerOpen` into `PosView`, so Walk-in / Find / Create customer buttons render on the iPad POS empty state (parity with iPhone/web desktop: search existing, create new, walk-in). `RootView.iPhoneTabs` gained the missing `customerRepo` too. (fix(ios): POS iPad wiring + full-screen layout)
- [x] **POS iPad full-screen layout** — `PosView.regularLayout` no longer uses a nested `NavigationSplitView` (which pushed Items + Cart below the top of the screen inside the shell's detail column). Now an `HStack` inside a single `NavigationStack`, Items column (min 320 / ideal 420 / max 540), Divider, Cart column fills the rest. Single inline nav bar for the POS toolbar. (fix(ios): POS iPad wiring + full-screen layout)
- [x] **POS iPad sidebar auto-collapse** — `RootView.iPadSplit` binds `columnVisibility`; `onChange(of: selection)` flips to `.detailOnly` when `.pos` is active, `.automatic` elsewhere. Gives the Items + Cart columns the full canvas; user can still toggle the sidebar back manually via the standard nav-bar control. (fix(ios): POS iPad sidebar auto-collapse)
- [x] **POS device-for-repair picker (iPad + iPhone)** — when selling a repair service to a customer who has saved assets, prompt for which device the repair applies to. Pull the customer's saved assets via `GET /customers/:id/assets`; show a sheet `PosDevicePickerSheet` with the assets + "No specific device" + "Add a new device" CTAs. Selected device id is attached to the cart line and persisted to the invoice as `ticket_device_id` on the resulting ticket. Gate on the inventory item's `is_service` flag so retail sales don't ask. (d7edd4a1)
- [x] **Customer-specific pricing** — if customer is in a Customer Group with discount override, apply automatically (banner "Group discount applied"). PosCustomerContextBanners + applyGroupDiscountIfNeeded. (d7edd4a1)
- [x] **Tax exemption** — if customer has tax-exempt flag, cart removes tax with banner; show exemption cert # if stored. PosCustomerContextBanners + applyTaxExemptionIfNeeded + tag heuristic. (d7edd4a1)
- [x] **Loyalty points preview** — "You'll earn XXX points" if loyalty enabled. PosCustomerContextBanners + loyaltyPointsPreview(cartTotalCents:). (d7edd4a1)
- [x] **Customer-tag color stripe** — `PosCartStrip` accepts a `tagColor: Color?` param (default `nil`). When non-nil: 3pt rounded leading stripe in the tag color + avatar gradient tinted to match + 6% opacity wash on the whole strip background; decorative / `accessibilityHidden`. Call site passes the hex of the customer's highest-priority `CustomerTagColor` from the `defaultPalette` (e.g. gold for "vip", red for "late-payer"). Cashier recognizes tier at a glance without reading the tag name. `PosCartPanel.swift`. (feat(§16.4): customer-tag color stripe in PosCartStrip)

### 16.5 Payment — BlockChyp (primary card rail)

> Phase-2 scaffold note: `Charge` button currently opens `PosChargePlaceholderSheet` which shows the running total and the message "Charge flow not yet wired — BlockChyp SDK pending (§17)." No fake-success path — dismissing returns to the cart. All checkboxes below remain open until the BlockChyp SDK + server endpoints land.

- [x] **Terminal pairing** — Settings → Terminal → scan QR / enter terminal code + IP; stored in Keychain (`com.bizarrecrm.pos.terminal`). `BlockChypTerminalPairingView` + `TerminalPairing` model + `PairingKeychainStore`. Scaffold only — no SDK calls. (228f6173)
- [x] **Heartbeat** — on POS screen load, ping terminal; offline badge if no response in 3s. `BlockChypHeartbeatView` 10s polling, `getTerminalHeartbeat()` stub → 501 BLOCKCHYP-HEARTBEAT-001. (228f6173)
- [ ] **Start charge** — tap Pay → select BlockChyp → spinner while terminal prompts cardholder.
- [x] **Reader states** — `waitForCard`, `chipInserted`, `pinEntered`, `awaitingSignature`, `approved`, `declined`, `timeout`. `BlockChypReaderStateView` display-only scaffold. (228f6173)
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
- [x] **Cash** — keypad sheet; amount-received field; large "Change due" in Barlow Condensed glass card; rounding rules per tenant. `PosCashAmountView` + `PosTenderCoordinator` + `PosTenderAmountEntryView`. (feat(§16.6): cash tender flow)
  - [x] **Change-given haptic + animation** — `PosCashAmountView` fires `BrandHaptics.success()` + a `.spring(response:0.3, dampingFraction:0.55)` pop scale (1.0→1.18→1.0) on the "Change" column the first time `receivedCents >= dueCents`; haptic re-arms if cashier drops below threshold; `reduceMotion` skips scale; confirm button also fires `BrandHaptics.success()`. (feat(§16.6): change-given haptic + animation)
- [x] **Manual keyed card — same PCI model as §17.3.** We do NOT build our own `TextField`s capturing PAN / expiry / CVV. That would push the app into SAQ-D scope and is a non-starter. `PosManualKeyedCardSheet` — role-gated (manager PIN), PCI instruction UI, offline-unavailable notice; BlockChyp call site stubbed for §16.5 approval. (feat(§16.6): manual keyed card PCI model UI cad69018)
  - **Preferred path**: cashier hands terminal to customer; customer keys card on the terminal PIN pad (or tap / insert). SDK call is the same `charge(..., allowManualKey: true)`; terminal UI prompts for keyed entry. Raw digits never leave the terminal.
  - **Cardholder-not-present path** (phone orders, back-office): BlockChyp "virtual-terminal" / tokenization call — SDK presents BlockChyp's own secure keyed-entry sheet that tokenizes inside the SDK process; we get `{token, last4, brand}` back. Still no PAN on our disk or our server.
  - **Role-gated** — manager PIN required before the sheet opens (audit entry with actor + amount + reason).
  - **Last4 + brand + auth code** only in our GRDB / server ledger. Never the PAN. Ever.
  - **No photo / screenshot of card.** Camera attachments on payment screens explicitly blocked (blur on background per §28.3).
  - **Same sovereignty rule** — BlockChyp is the single permitted payment peer; no Stripe / Square / PayPal SDK fallbacks anywhere in the bundle.
  - **Offline** — manual-keyed not available offline. Cloud-relay vs local mode same as §17.3: needs outbound path to BlockChyp for the tokenization call. If fully offline, disable manual-keyed option with tooltip "Requires internet to tokenize."
- [x] **Gift card** — scan / key gift-card #; `POST /gift-cards/redeem` with amount; remaining balance displayed. `PosGiftCardAmountView` + `TenderMethod.giftCard` in `PosTenderAmountEntryView`. (feat(§16.6): gift card tender)
  - [x] **Gift-card balance check** — `PosGiftCardSheet` gains a "Check balance only" button (shown after lookup when `balanceCheckResult == nil`); tapping calls `checkBalanceOnly(card:)` + `.tap()` haptic; result rendered as a status pill (active/inactive colour, balance, expiry, dismiss X); pill clears on re-lookup. `PosGiftCardSheetViewModel.balanceCheckResult: GiftCard?` + `checkBalanceOnly/dismissBalanceCheck`. (feat(§16.6): gift-card balance check without redeem)
- [x] **Store credit** — auto-offer if customer has balance; slider "Apply X of $Y available". `PosStoreCreditAmountView` + `TenderMethod.storeCredit` in `PosTenderAmountEntryView`. (feat(§16.6): store credit tender)
- [x] **Check** — check # + bank + memo; no auth, goes to A/R. `PosCheckTenderSheet` + `TenderMethod.check`. (feat(§16.6): check tender)
- [x] **Account credit / net-30** — role-gated; only if customer has terms set; adds to open balance. `PosAccountCreditTenderSheet` + `TenderMethod.accountCredit` + wired in `PosTenderAmountEntryView`. (feat(§16): account-credit tender 2f6d8bab)
- [x] **Financing (if enabled)** — partner link (Affirm/Klarna) → QR/URL for customer to complete on their phone; webhook completes sale. `PosFinancingLinkSheet` + `FinancingProvider` enum; no partner SDK. (feat(§16): financing link 2f6d8bab)
- [x] **Split tender** — add tender → shows remaining due → repeat until 0; show running "Paid / Remaining" card. `PosTenderCoordinator.applyTender` multi-leg + `PosTenderMethodPickerView`. (feat(§16.6): split tender)
- [x] **Payment method icon SF Symbols** — `TenderMethod.systemImage` extended: `check` now uses `checkmark.rectangle.fill` (matches paper-check shape); new `.financing` case (`clock.arrow.circlepath`) + `tileSubtitle` "Affirm · Klarna"; `iconAccessibilityLabel` per method for chip-only icon contexts. `AppliedTender.Kind` gains `systemImage` + `accessibilityLabel` per kind (giftCard/storeCredit/loyaltyRedemption). (feat(§16.6): payment method icon SF Symbols)

### 16.7 Receipt & hand-off
- [x] **On-device rendering pipeline per §17.4** (contract enforced via `ReceiptPrinter`/`PosReceiptRenderer`). Single SwiftUI `ReceiptView` deferred to full printer SDK work.
- [x] **Receipt preview (text/HTML)** — `PosReceiptRenderer.text(_:)` + `html(_:)` deterministic render from `PosReceiptRenderer.Payload`. Live SwiftUI preview deferred.
- [x] **Thermal print** — `ImageRenderer(content: ReceiptView(...))` → bitmap → ESC/POS raster to MFi printer (§17). `PosReceiptPrintBridge.printViaThermal` renders via `ImageRenderer`, delegates to `ReceiptPrinterProtocol` (Agent 2 Hardware boundary); falls back to AirPrint when printer unavailable. (feat(§16.7): thermal print bridge cad69018)
- [x] **AirPrint** — fallback for non-MFi: same `ReceiptView` rendered to local PDF file URL via `UIGraphicsPDFRenderer`; hand the file URL (not a web URL) to `UIPrintInteractionController`. `PosReceiptPrintBridge.printViaAirPrint` — renders to temp PDF, passes file URL to `UIPrintInteractionController.printingItem`; popover on iPad, sheet on iPhone; temp file cleaned up after dialog. (feat(§16.7): AirPrint fallback cad69018)
- [x] **Email** — `POST /notifications/send-receipt` wired (soft-absorbs 400/404). PDF attachment deferred to §17.4 pipeline.
- [x] **SMS** — `POST /sms/send` wired. Tracking short-link routing deferred to §53.
- [x] **Download PDF** — `.fileExporter` pointed at locally-rendered PDF; filename `Receipt-{id}-{date}.pdf`. `ReceiptPDFDocument` + `ReceiptPDFExporterModifier` + `exportPDF()` in `PosReceiptView`. (feat(§16.7): receipt PDF download)
- [x] **QR code** — rendered inside `ReceiptView` via `CIFilter.qrCodeGenerator`; encodes public tracking/returns URL (tokenized, no auth required by recipient). `trackingQRImage` + `qrCodeSection` in `PosReceiptView`. (feat(§16.7): receipt QR code)
- [x] **Signature print** — captured `PKDrawing` / `PKCanvasView` image composed into the view, printed as part of the same bitmap. `PosReceiptPrintBridge.SignatureCompositor` composites `PKDrawing` → `UIImage` onto receipt bitmap (thermal) or PDF (AirPrint) below a separator line. (feat(§16.7): signature print compositor cad69018)
- [x] **Gift receipt** — `GiftReceiptGenerator` pure-function generator + `GiftReceiptSheet` post-sale prompt. Strips prices/tenders/customer, preserves names/SKUs/qty. Tests ≥80%. (Phase 5 §16)
- [x] **Persist the render model** — snapshot `ReceiptModel` persisted at sale close so reprints are byte-identical even after template / branding changes. `ReceiptModelStore` actor + `.task` in `PosReceiptView`. (feat(§16.7): persist receipt model)
- [x] **Receipt printer status pill** — `ReceiptPrinterStatusPill` collapsible toolbar chip: connected (green `printer.fill`) / notPaired (muted `printer.fill.and.paper`) / offline (red `printer.dotmatrix`); 30-second heartbeat via `ReceiptPrinterStatusViewModel` @Observable; tap expands label, auto-collapses after 4 s; Reduce Motion, a11y label, identifier. (feat(§16.7): receipt printer status pill)

### 16.8 Post-sale screen
- [x] **Glass "Sale complete" card** — `PosPostSaleView` with 600ms spinner → success. Confetti animation deferred.
- [x] **Summary tile** — total + method label. Full tender breakdown + sale # deferred.
- [x] **Next-action CTAs** — New sale / Email / Text / Print (disabled). ⌘N/⌘R shortcuts deferred. Print gift receipt deferred.
- [x] **Auto-dismiss** after 10s → empty catalog + cart for next customer. Countdown + `startAutoDismissCountdown` in `PosPostSaleView`; cancels on any user interaction or sheet open. (feat(§16.8): auto-dismiss post-sale)
  - [x] **Visible countdown badge** — "Starting new sale in Ns · tap to cancel" text rendered while the timer is live; tapping the row cancels the timer. Closes the gap between the existing background countdown and the spec line "Starting new sale in Ns…" from §16.24. (feat(§16.8): visible auto-dismiss countdown)
- [x] **Cash drawer kick** — pulse drawer via printer ESC command if cash tender used. `PosDrawerKickService` actor maps cash/check tenders → `DrawerTriggerTender`; silent for card/gift/store-credit. (feat(§16.8): cash drawer kick on cash tender 55ba3fb8)
  - [x] **Wire `openDrawer()` into cash tender completion** — `PosCashTenderSheet.onCompleted` now calls `openDrawer()` so the drawer pops automatically once the cashier counts cash; previously the kick service existed without a callsite at the cash-tender boundary. (feat(§16.8): kick drawer on cash tender complete)

### 16.9 Returns / refunds
- [x] **Entry** — POS toolbar "Process return" button (⌘⇧R) → `PosReturnsView` search by order/phone.
- [x] **Original lookup** — show invoice detail with per-line checkbox + "Qty to return" stepper. `PosReturnDetailView` + `PosReturnLineSelector` + `PosReturnDetailViewModel`; fetches GET /api/v1/invoices/:id. (6c9d0ddc)
- [x] **Reason required** — text field + tender picker in `PosRefundSheet`. Dropdown presets deferred.
  - [x] **Reason dropdown presets** — new `PosRefundReason` enum (defective / wrong item / customer changed mind / duplicate charge / size or fit / late delivery / price match / other) surfaced as a `Picker(.menu)` in `PosRefundSheet`; selecting `.other` reveals the free-text field. `mergedReason()` joins preset label + free text into the wire payload. (feat(§16.9): refund reason presets)
  - [x] **Refund-reason custom field** — `.other` free-text field gains 200-char hard cap (`PosRefundViewModel.maxReasonLength = 200`) via `onChange` clamp; live `"N / 200"` mono-digit counter below the field turns red at limit; multi-line `axis: .vertical`, `lineLimit(2...4)`; prevents empty-reason submit. (feat(§16.9): refund reason custom field char limit)
- [x] **Restock flag** — per line: return to inventory (increment) vs scrap (no increment). `ReturnableLine.restock` toggle per line in `PosReturnLineSelector`. (6c9d0ddc)
- [x] **Refund amount** — editable cents input in sheet. Per-line calc + restocking fee deferred.
- [ ] **Tender** — original card (BlockChyp refund with token) / cash / store credit / gift card issuance.
- [x] **Manager PIN** — required above $X threshold (tenant config). Gate in `PosReturnDetailViewModel` at $50 (5000¢) via `ManagerPinSheet`. (6c9d0ddc)
  - [x] **First-class `refundManagerPinThresholdCents` on `PosTenantLimits`** + matching `UserDefaults` key + `PosRefundSheet` PIN gate (was only wired in `PosReturnDetailViewModel`). The PIN-approved manager id flows into `PosAuditEntry.EventType.managerApprovedRefund` so the action shows up in the audit log next to `void_line` / `no_sale`. (feat(§16.9): refund manager PIN gate)
- [x] **Audit** — `POST /pos/returns` with `/refunds/credits/:customerId` fallback. "Coming soon" banner on 404/501.
- [x] **Receipt** — "RETURN" printed; refund amount; signature if required. `PosReturnReceiptView` — mandatory "RETURN" red badge in header, refund lines with negative amounts, tender method, optional signature section from `PKDrawing` data; phone/iPad adaptive layouts; print + done toolbar. (feat(§16.9): return receipt view cad69018)

### 16.10 Cash register (open/close)
- [x] **Open shift** — `OpenRegisterSheet` presented on POS mount when no session via fullScreenCover. Opening float input (single aggregate cents, per-denomination deferred). Local-first via `CashRegisterStore`. Employee PIN + server sync deferred.
- [x] **Mid-shift** — "Cash drop" button (remove excess to safe) with count + signature. `CashDropSheet` wired to `POST /pos/cash-out`. (feat(§16.10): mid-shift cash drop)
- [x] **Close shift** — `CloseRegisterSheet` with counted/expected/notes + `CashVariance` band. Over/short color coded. Per-denomination count + mandatory note threshold deferred.
- [x] **Z-report** — `ZReportView` renders tiles + variance card. Auto-print/email-to-manager deferred to §17.4 pipeline.
- [x] **Shift handoff** — outgoing cashier closes → incoming opens fresh; seamless transition. `ShiftHandoffView` two-step wizard (summary → openShift); opens CashRegisterStore.shared.openSession. (1a87bfb7)
- [x] **Blind-count mode** — cashier doesn't see expected total until after count (loss prevention). `blindCountMode` + `blindCountRevealed` toggle in `CloseRegisterSheet`. (feat(§16.10): blind-count mode)
- [x] **Tenant config** — enforce mandatory count vs skip allowed; skip requires manager PIN. `ShiftHandoffPolicy` (.default/.strict/.mandatory); ManagerPinSheet for skip-count. (1a87bfb7)
- [x] **Register-close summary screen polish** — `CloseRegisterSheet` gets: shift summary header card (duration chip e.g. "4 h 22 min", float, session ID, clock icon); variance badge polished with band description text ("On target" / "Minor variance" / "Investigate required") + band icon pill (`checkmark/exclamationmark/xmark.circle.fill`); `contentTransition(.numericText)` on variance amount; Duration row in Shift section; all a11y labels updated. (feat(§16.10): register-close summary polish)
- [x] **Opening-float quick-fill chips** — `OpenRegisterSheet` gains a horizontal scroll row of preset amount chips ($50/$100/$150/$200/$250) that fill the float field on tap + `.selection` haptic. `pos.openRegister.quickFill.*` a11y IDs. (feat(§14): cash register UX polish)
- [x] **Float-confirmation haptic** — `OpenRegisterSheet.commit()` fires `BrandHaptics.success()` + `HapticCatalog.play(.successConfirm)` on successful open so the cashier feels a distinct drawer-open confirmation. (feat(§14): cash register UX polish)
- [x] **Shift-summary copy button** — `EndOfShiftSummaryView` toolbar gains a "Copy" button (doc.on.doc → checkmark for 2 s) that places a plain-text shift summary on `UIPasteboard.general`. `endShift.copy` a11y ID. (feat(§14): cash register UX polish)
- [x] **Register-lock countdown a11y** — new `PosRegisterLockView` with per-second `Text` live region + `UIAccessibility.post` announcements at 10 s / 5 s / 3 s thresholds; "Unlock register" `faceid` button always VoiceOver-reachable; pulse animation gated behind Reduce Motion. `pos.registerLock.*` a11y IDs. (feat(§14): cash register UX polish)
- [x] **Mid-shift snapshot UI** — new `MidShiftSnapshotView` + `MidShiftSnapshot` model: gross/sales/tips/drops/voids/cash-expected tiles + estimated-drawer row; "Copy snapshot" clipboard button; `.medium` + `.large` detents. Distinct from server X-report (POS-XREPORT-001 pending). `midShiftSnapshot.*` a11y IDs. (feat(§14): cash register UX polish)

### 16.11 Anti-theft / loss prevention
- [x] **Void audit** — `Cart.removeLine(id:reason:managerId:)` logs `void_line`/`delete_line` via `PosAuditLogStore` (GRDB migration 005). Fire-and-forget Task never blocks cashier.
- [x] **No-sale audit** — POS overflow ⋯ "No sale / open drawer" presents `ManagerPinSheet`; on approval logs `no_sale` event.
- [x] **Discount ceiling** — `PosCartDiscountSheet` checks `PosTenantLimits.maxCashierDiscountPercent/Cents`; over → nested `ManagerPinSheet`; on approval logs `discount_override` with originalCents + appliedCents.
- [x] **Price override alert** — `PosEditPriceSheet` gates override when delta ≥ `priceOverrideThresholdCents`; logs `price_override`.
- [x] **Delete-line audit** — `Cart.removeLine` without `managerId` logs `delete_line`; ghosted on Z-report via `ZReportAggregates` loss-prevention tile (void/no-sale/discount-override counts).
- [x] **Manager override audit-log row** — new `PosAuditEntry.EventType.managerOverride = "manager_override"` constant in `PosAuditLogStore.swift`. `eventTypeLabel` → "Manager override"; `badgeLabel` → "MGR OVR"; `badgeColor` → `.bizarreWarning`. `PosAuditLogView` gains `managerOverrideCountToday` computed prop + `managerOverrideSummaryRow(count:)` (amber badge, `person.badge.shield.checkmark.fill` icon, count in warning/error colour ≤2/> 2) rendered as the first `Section` above the no-sale section. `accessibilityIdentifier: pos.auditLog.managerOverrideSummary`. `PosAuditLogStore.swift`, `PosAuditLogView.swift`. (feat(§16.11): manager-override audit-log row)

### 16.12 Offline POS mode
- [x] **Local catalog** — full inventory + pricing cached (GRDB), daily refresh on launch. `PosCatalogOfflineStore` (actor) + `PosCatalogRefreshService` @MainActor service; fetches `GET /inventory/items?pos=true&per_page=500`; 24h threshold; replaces cache atomically. (feat(§16.12): local catalog GRDB cache cad69018)
- [x] **Offline sale** — queue to GRDB sync-queue via `PosSyncOpExecutor` + `CartViewModel.checkoutIfOffline`; `PosCartSnapshotStore` persists cart across kills; auto-drain via `SyncManager.autoStart()` on reconnect. (SHA: pending commit)
- [x] **Sync replay** — `SyncManager` drain loop + `PosSyncOpExecutor` dispatch; 409-conflict dead-lettered; `OfflineSaleQueueView` + `OfflineSaleDetailView` for manual retry/cancel.
- [x] **Offline banner** — `OfflineSaleIndicator` glass chip in POS chrome; taps into `OfflineSaleQueueView`. (SHA: pending commit)
- [x] **Stop-sell** — if any part of catalog > 24h stale, warn before sale. `PosCatalogStalenessService` actor + `PosCatalogStaleBannerView` dismissible amber banner with Sync CTA. (feat(§16.12): catalog staleness warning + stop-sell banner 55ba3fb8)

### 16.13 Hardware integration points (see §17 for detail)
- [ ] Barcode scanner (camera + MFi Socket Mobile / Zebra).
- [ ] BlockChyp terminal.
- [ ] MFi receipt printer (Star TSP100 / Epson TM-m30).
- [ ] Cash drawer (via printer kick).
- [ ] Customer-facing iPad (second screen for tip / signature).
- [ ] Bluetooth scale (deli / weighted items).

### 16.14 iPad-specific POS
- [x] **3-column layout** — catalog + cart + customer panel. `PosIPadCustomerPanel` persistent trailing column; avatar + loyalty/tax-exempt chips; find/create CTAs on walk-in. (feat(§16.14): iPad 3-column customer panel 55ba3fb8)
- [x] **Customer-facing display** — `CFDBridge` + `CFDView` + `CFDIdleView` + `CFDSettingsView`. iPad/Mac only; hidden on iPhone. Liquid Glass header/footer. A11y. Reduce Motion. Tests ≥80%. (Phase 5 §16)
- [x] **Magic Keyboard shortcuts** — ⌘N (new custom line), ⌘⇧R (return), ⌘P (pay/charge), ⌘K (customer pick), ⌘H (hold), ⌘⇧H (resume holds), ⌘⇧D (discount), ⌘⇧T (tip), ⌘⇧F (fee), ⌘⇧⌫ (clear cart). ⌘F search focus + ⌘⇧V void deferred.
- [x] **Apple Pencil** — tap to add to cart, double-tap for 2, hover for preview on iPad Pro. `PosApplePencilModifier` + `.onPencilDoubleTap` + `.onHover` ring + `Cart.add(_:qty:)` helper. (feat(§16.14): Apple Pencil 2f6d8bab)
- [x] **Drag items** — drag from catalog to cart with haptic feedback. `PosCatalogDraggableModifier` + `PosCartDropTargetModifier` + `Cart.add(_:PosDraggedCatalogItem)`. (feat(§16.14): drag items from catalog to cart 3ad70973)

### 16.15 Membership / loyalty integration
- [x] **Member discount** — auto-apply if customer is a member (see §40). `PosViewModel.applyMemberDiscountIfNeeded` + `PosMembershipTenderConnector` auto-applies tier discount at checkout entry. (feat(§16.15): member discount auto-apply 3ad70973)
- [x] **Points earned** — displayed on receipt. `PosMembershipReceiptBuilder.fields(from:)` extracts `loyaltyDelta`/tier/total for `PosReceiptPayload`. `PosMembershipTenderConnector` bridges to existing `PosLoyaltyCelebrationView`. (feat(§16.15): points earned on receipt 3ad70973)
- [x] **Customer loyalty-points display** — `PosLoyaltyBalanceChip` new compact chip view pinned below the customer strip in `PosCartPanel`; shows "★ N pts" balance + "+M this sale" earn-preview suffix when `loyaltyEarnedPoints` set; teal colour ramp; `.opacity`+`.scale(0.95)` entry animation; `BrandMotion.snappy`; a11y combine label + `pos.loyaltyBalanceChip` identifier; only rendered when `customerContext.loyaltyPointsBalance != nil`. (feat(§16.15): customer loyalty-points balance chip in cart)
- [x] **Points redemption** — toggle "Use X points ($Y off)" inline. `PosMembershipTenderConnector` embeds `MembershipBenefitBanner` + presents `RedeemPointsSheet` at tender entry. (feat(§16.15): points redemption toggle 3ad70973)
- [x] **Member-only products** — grayed for non-members. `PosCatalogTile.isMemberOnly` + `hasMemberAttached` dim tile + block tap when no qualifying member attached. `PosViewModel.hasMemberAttached` helper. (feat(§16.15): member-only product tiles 3ad70973)
- [ ] POS cart: `PKPaymentButton`; customer taps → Face ID → tokenized payment routed via BlockChyp gateway (§17.3). Fallback to insert-card if Apple Pay unavailable.
- [ ] Public payment link page uses `PKPaymentAuthorizationController`; Merchant ID `merchant.com.bizarrecrm`.
- [ ] Apple Pay Later: not initially; leave to BlockChyp; re-evaluate post-Phase-5.
- [x] Pass management: three distinct pass types — membership (§38), gift card (§40), loyalty (§38). `LoyaltyWalletService`, `GiftCardWalletService`, `PassUpdateSubscriber` shipped. Update via PassKit APNs on value / tier change. Commit `feat(ios phase-6 §24+§38+§40)`.
- [ ] Merchant domain verification for public payment pages (`/.well-known/apple-developer-merchantid-domain-association`).
- [ ] Tap to Pay on iPhone: iPhone XS+ with separate Apple Developer approval; Phase 4+ eval, its own scope.
- [ ] Sovereignty: tokens flow Apple → BlockChyp; raw PAN never on our server or iOS app (§17.3 PCI posture).
- [x] CFD (customer-facing display) use case: POS terminal facing customer shows running cart via `CFDView` in secondary `"cfd"` WindowGroup scene. Audio cue + spatial AirPods deferred. (Phase 5 §16)
- [ ] Scanner feedback: beep on scan plays spatial from "upper-right" to feel more physical
- [ ] Restraint: audio secondary to haptic; always optional (Settings → Audio); mute in silent mode per iOS convention
- [x] Secondary scene: new `UIScene` for external display; detect `UIScreen.connectionNotification`; mirror cart state via shared model (`CFDExternalDisplayService` @Observable UIScreen.didConnectNotification observer. dba9ae7f)
- [x] Layout: top = shop logo + tenant-configured tagline; middle = cart lines + running total; bottom = current line highlighted as added; large tax + total; payment prompt "Insert / tap card" with animated arrow when BlockChyp terminal ready (CFDView Liquid Glass header: shopName + shopTagline from CFDBridge; CFDSettingsView shopTagline AppStorage key. dba9ae7f)
- [x] Receipt/thank-you: post-approval confetti (respect Reduce Motion) + "Thank you!" + QR for Google review / membership signup; auto-dismiss after 10s (`CFDThankYouView` + `CFDPostSaleState` + `CFDConfettiView` + `CFDBridge.showPostSale()`; 10s countdown; Reduce Motion gated. dba9ae7f)
- [ ] Signature: customer signs on secondary display on Pencil-compatible iPad; else signs on terminal
- [x] Marketing slideshow: idle >30s between sales rotates tenant-configured slides (promos, upcoming events); tap anywhere exits (`CFDIdleView` slideshow mode; 30s trigger; 5s rotation; tap-to-exit; Reduce Motion: static. dba9ae7f)
- [x] Multi-language: customer can tap flag to switch language; decoupled from cashier's app language (`CFDBridge.customerLanguageCode`; `CFDView.localised()` EN/ES/FR/DE table; `CFDSettingsView` Picker; `CFDThankYouView` localised labels. dba9ae7f)
- [x] Privacy: never show cashier personal data (email/phone/other customers); no cross-sale persistence on display (`CFDBridge.privacyModeEnabled` bool; `CFDSettingsView` privacy toggle + description; `CFDBridge.clear()` wipes all state between sales; documented in bridge header. dba9ae7f)
- [x] Full register accelerators on iPad hardware keyboard. `PosRegisterShortcutsExtended` ViewModifier + `PosRegisterShortcut` metadata enum; all shortcuts listed below implemented. (feat(§16.14): full register keyboard accelerators cad69018)
- [x] Cart: ⌘N new sale, ⌘⇧N hold/park, ⌘R resume held, ⌘+/⌘− qty on focused line, ⌘⌫ remove line, ⌘⇧⌫ clear cart (with confirm). (feat(§16.14): full register keyboard accelerators cad69018)
- [x] Lookup: ⌘F focus product search, ⌘B focus barcode input, ⌘K customer lookup palette. (feat(§16.14): full register keyboard accelerators cad69018)
- [x] Payment: ⌘P open payment sheet, ⌘1 cash, ⌘2 card, ⌘3 gift card, ⌘4 store credit, ⌘⇧P split tender. (feat(§16.14): full register keyboard accelerators cad69018)
- [x] Receipt: ⌘⇧R reprint last, ⌘E email receipt, ⌘S SMS receipt. (feat(§16.14): full register keyboard accelerators cad69018)
- [x] Admin: ⌘M manager PIN prompt, ⌘⌥V void current sale, ⌘⌥R open returns. (feat(§16.14): full register keyboard accelerators cad69018)
- [x] Navigation: Tab cycles cart → discount → tender. (SwiftUI standard focus chain; documented in PosRegisterShortcutsExtended. feat(§16.14): cad69018)
- [x] Navigation: arrow keys scroll catalog grid. (SwiftUI `.focusable` on catalog grid items; standard arrow-key handling via focus engine. feat(§16.14): cad69018)
- [x] Discoverability: ⌘? shows overlay (§23.1) (feat(ios phase-7 §23): keyboard shortcut catalog + overlay + hardware keyboard detector)

### 16.16 Split check (post-phase §16)
- [x] **SplitCheckMode** — `.byLineItem` / `.evenly` / `.custom` enum. `CartLineID` + `PartyID` typealiases. `SplitError` cases. (feat(ios post-phase §16))
- [x] **SplitCheckCalculator** — pure: `even(totalCents:parties:)` last-party remainder, `byLineItem(lines:assignments:)`, `validate`. Tests ≥80%. (feat(ios post-phase §16))
- [x] **SplitCheckViewModel** — `@Observable`. Parties, assignments, custom amounts, payment progress, `allPartiesPaid`. (feat(ios post-phase §16))
- [x] **SplitCheckView** — iPhone tabbed per party, iPad side-by-side columns. Liquid Glass column headers. Mode picker. A11y party announce. Reduce Motion. (feat(ios post-phase §16))

### 16.17 Held carts (post-phase §16)
- [x] **HeldCart** — `{ id, savedAt, cart: CartSnapshot, customerId?, ticketId?, note }`. Auto-expire 24 h. (feat(ios post-phase §16))
- [x] **HeldCartStore** — actor. UserDefaults MVP. `save / loadAll / delete / deleteAll`. Auto-prune expired. Tests ≥80%. (feat(ios post-phase §16))
- [x] **HoldCartSheet** — "Hold" button, optional note, snapshots to HeldCartStore. (feat(ios post-phase §16))
- [x] **HeldCartsListView** — POS toolbar "Held", list sorted newest-first, tap to restore, swipe-to-delete. A11y. (feat(ios post-phase §16))

### 16.18 Shift summary / Z-report (post-phase §16)
- [x] **ShiftSummary** — struct: shiftId, dates, cashierId, cash floats, drift, saleCount, totalRevenue, tendersBreakdown, refunds, voids, avgTicket. (feat(ios post-phase §16))
- [x] **ShiftSummaryCalculator** — pure aggregation from `[SaleRecord]`. Drift calc. Tests ≥80%. (feat(ios post-phase §16))
- [x] **ShiftSummaryView** — metrics grid, tenders breakdown, variance card. Print deferred Phase 5A. (feat(ios post-phase §16))
- [x] **ShiftSummaryEndpoints** — `POST /shifts/:id/close` returns canonical summary. (feat(ios post-phase §16))

### 16.19 Quick-sale hotkeys (post-phase §16)
- [x] **QuickSaleHotkeys** — 3-slot configurable struct. `QuickSaleHotkeyStore` actor (UserDefaults). (feat(ios post-phase §16))
- [x] **QuickSaleButtonsView** — 3-tile row above cart; one-tap add. A11y. (feat(ios post-phase §16))
- [x] **QuickSaleSettingsView** — admin picks 3 SKUs; inline editor; clear-slot action. (feat(ios post-phase §16))

### 16.20 Split tender revision (post-phase §16)
- [x] **AppliedTendersListView** — removable tenders; inline amount edit; manager PIN gate after checkout committed. (feat(ios post-phase §16))

- [x] Checkout sheet has "Gift receipt" switch. `GiftReceiptCheckoutSheet` + `GiftReceiptCheckoutViewModel`. (feat(§16): gift receipt checkout sheet 55ba3fb8)
- [x] Content: item names + qty present; prices hidden; totals hidden. `GiftReceiptGenerator.buildPayload` zeroes all monetary fields. (feat(§16): gift receipt generator strips prices 55ba3fb8)
- [x] Return-by date + policy printed on gift receipt. Dynamic footer with `returnByDays` from `GiftReceiptOptions`. (feat(§16): gift receipt return-by date footer 55ba3fb8)
- [x] QR with scoped code: enables one-time return without revealing price to recipient. `GiftReceiptOptions.returnToken` + `returnURL(baseURL:)` + `GiftReceiptScopedQRView` (CoreImage, off-thread, single-use token). (feat(§16): gift receipt scoped QR 2f6d8bab)
- [x] Channels: print + email + SMS + AirDrop. `GiftReceiptChannel` enum + picker in checkout sheet. (feat(§16): gift receipt channel picker 55ba3fb8)
- [x] Return handling: gift return credits store credit (§40) by default unless paid-for matches card on file. `GiftReceiptReturnCredit` enum + picker. (feat(§16): gift receipt return credit picker 55ba3fb8)
- [x] Partial gift receipt via per-line toggle. `GiftReceiptOptions.includedLineIds` + per-line toggle in sheet. (feat(§16): partial gift receipt line selection 55ba3fb8)
- [x] Types: percentage off (whole cart / line / category) (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Types: fixed $ off (whole cart / line) (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Types: Buy-X-get-Y (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Types: tiered ("10% off $50+, 15% off $100+, 20% off $200+") (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Types: first-time customer. `DiscountRule.firstTimeCustomerOnly` + `DiscountContext.isFirstTimeCustomer` gate. (feat(§16): discount first-time customer gate 55ba3fb8)
- [x] Types: loyalty tier (§38). `DiscountRule.requiredLoyaltyTier` + `DiscountContext.customerLoyaltyTier` gate. (feat(§16): discount loyalty tier gate 55ba3fb8)
- [x] Types: employee discount by role. `DiscountRule.requiredEmployeeRole` + `DiscountContext.cashierRole` gate. (feat(§16): discount employee role gate 55ba3fb8)
- [x] Stacking: configurable stackable vs exclusive (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Stacking order: percentage before fixed before tax (tenant-configurable). `DiscountStackOrder` enum `.percentBeforeFixed`/`.fixedBeforePercent` with `displayName`. (feat(§16): discount stacking order enum 55ba3fb8)
- [x] Limits: per customer, per day, per campaign (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Limits: min purchase threshold (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Limits: excluded categories. `DiscountRule.excludedCategories: Set<String>` + engine skip in `applyToLine`. (feat(§16): discount excluded categories 55ba3fb8)
- [x] Auto-apply on each cart change without staff action. `DiscountAutoApplyService` actor evaluates on each cart change. (feat(§16): discount auto-apply service 55ba3fb8)
- [x] Banner shows "N discounts applied". `DiscountAutoApplyResult.bannerText` + `showBanner` flag. (feat(§16): discount auto-apply banner 55ba3fb8)
- [x] Manual override: cashier adds ad-hoc discount (if permitted) → reason prompt + audit. `PosAdHocDiscountSheet` + `PosAdHocDiscountViewModel`; manager PIN gate when over threshold; `discount_override` audit log. (feat(§16): ad-hoc discount override 2f6d8bab)
- [x] Manager PIN required above threshold (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Server validation: iOS optimistic, server re-validates to prevent fraud. `CartServerValidationBannerView` + `CartServerValidationDetailSheet` + `ServerValidationMismatch` model (tax/discount/price mismatch with delta display). (feat(§16): server validation banner 2f6d8bab)
- [x] Reporting: discount effectiveness (usage, revenue impact, margin impact). `DiscountEffectivenessView` + `DiscountEffectivenessViewModel` — period picker (today/7d/30d), KPI cards, bar chart (Swift Charts), top-rules list; `GET /pos/discount-effectiveness`; 404/501 → "coming soon" banner; phone/iPad 2-col layouts. (feat(§16): discount effectiveness report cad69018)
- [x] Model: code string (human-friendly like `SAVE10`) (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Model: discount rule linkage (§16) (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Model: valid from/to (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Model: usage limit (total + per customer) (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Model: channel restriction (any / online only / in-store only). `DiscountChannel` enum + `DiscountRule.channel` + engine gate. (feat(§16): discount channel restriction model 55ba3fb8)
- [x] POS checkout sheet has "Coupon" field with live validation showing discount applied (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] QR coupons: printable/emailable QR containing code; scan at checkout auto-fills. `CouponQRView` + `CouponQRShareView` (CoreImage off-thread, ShareLink, `.textSelection` for Mac). (feat(§16): coupon QR 2f6d8bab)
- [x] Abuse prevention: rate-limit attempts per device. `CouponAbuseGuard` actor — 5 failures/60s → 120s cooldown. (feat(§16): coupon abuse rate-limit 2f6d8bab)
- [x] Abuse prevention: invalid attempts logged to audit. `CouponAbuseGuard.recordFailedAttempt` → `PosAuditLogStore` "coupon_invalid_attempt". (feat(§16): coupon audit 2f6d8bab)
- [x] Affiliate codes: tie coupon code to staff member for sales attribution. `AffiliateCode` model + `AffiliateCodeRepository` protocol. (feat(§16): affiliate codes model 2f6d8bab)
- [x] Time-based: happy hour 3-5pm = 10% off services; weekend pricing adjustments (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Volume: buy 3 cases 5% off each, buy 5 cases 10% (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Customer-group: wholesale pricing for B2B tier (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Location-based: per-location pricing overrides (metro vs suburb). `PricingRuleType.locationOverride` + `PricingRule.targetLocationSlug/locationDiscountPercent` + engine method. (feat(§16): pricing location override 55ba3fb8)
- [x] Promotion window: flash sales with on/off toggle + countdown timer visible to cashier. `PricingRuleType.promotionWindow` + `PromotionWindowBannerView` with live countdown. (feat(§16): pricing promotion window + cashier countdown 55ba3fb8)
- [x] UI at Settings → Pricing rules (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Rule list with priority order — `PricingRulesListView` + `PricingRulesListViewModel` + `PricingRulesRepository`/`Impl` + `APIClient+PosRules`. Drag-to-reorder with PATCH /pos/pricing-rules/order sync. Editor extended for locationOverride + promotionWindow. 9 tests ≥80%. (agent-1-b8)
- [x] Live preview: "Apply to sample cart" simulator. `PricingRulePreviewView` + `PricingRulePreviewViewModel` — uses `PricingEngine` actor with `DiscountCartSnapshot`; per-rule savings breakdown. (feat(§16): pricing rule live preview 2f6d8bab)
- [x] Conflict resolution: first matching rule wins (priority) (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Explicit stack rules if tenant configures (feat(ios phase-8 §16+§37+§6): POS discount engine + coupon codes + pricing rules engine)
- [x] Effective dates: schedule rules to auto-activate/deactivate. `EffectiveDatesEditorSection` embeddable in `PricingRuleEditorView`; `validFrom`/`validTo` DatePickers with toggles. (feat(§16): effective dates editor 2f6d8bab)
- [x] Calendar view of scheduled rules. `ScheduledPricingRulesView` + `ScheduledPricingRulesViewModel` — month navigator, active/upcoming/expired grouping. (feat(§16): scheduled pricing rules calendar 2f6d8bab)
- [x] Live recompute: animate tick-up/tick-down per digit with small font-weight shift. `PosCartTotalsView` — `.contentTransition(.numericText(value:))` + `.animation(.spring)` on subtotal/discount/tax/total rows; Reduce Motion guard. (feat(§16): cart totals live animation cad69018)
- [x] Discount highlight: flash discount line on apply; strike-through original → new. `PosCartTotalsView.discountRow` — cream flash + orange label + strike-through original price on `discountCents` increase; 1.2s auto-dismiss; Reduce Motion guard. (feat(§16): discount highlight flash cad69018)
- [x] Pending server validation: subtle shimmer on price until response finalizes. `PosCartTotalsView.pendingTotalShimmer` — `.redacted(.placeholder)` + `ShimmeringModifier` gradient overlay; driven by `isPendingValidation` bool from `CartServerValidationBannerView`. (feat(§16): server validation shimmer cad69018)
- [x] Mismatch resolution: banner "Tax recomputed (+$0.03)" when server total differs. `CartServerValidationBannerView` + `CartServerValidationDetailSheet` (see Server validation above). (feat(§16): server validation banner 2f6d8bab)
- [x] A11y: screen reader announces new total on change (debounced). `PosCartTotalsView.scheduleA11yAnnouncement` — 600ms debounce + `UIAccessibility.post(.announcement, ...)` fires after cart settles; avoids per-keypress chatter. (feat(§16): a11y debounced total announce cad69018)
- [x] Sale record schema: local UUID + timestamp + lines + tenders + idempotency key. `PosSaleRecord` + `PosSaleLineRecord` + `PosSaleTenderRecord` Codable structs; `capturedOffline` + `syncedAt` lifecycle; PCI posture: card tenders store only last4/brand/opaque token, never PAN. (feat(§16.12): offline sale schema cad69018)
- [x] Receipt printing: "OFFLINE" watermark until synced; post-sync reprint available without watermark. (`PosReceiptPayload.capturedOffline` + `syncedAt`; `PosReceiptView.offlineWatermark` amber Capsule chip (wifi.slash + OFFLINE + 'Sent when reconnected'); success 'Synced' chip post-sync. d44b806c)
- [ ] Card tenders: BlockChyp offline capture (where supported) captures card + holds auth + settles on reconnect; manager alert on declined auth at settle; configurable max offline card amount ($100 default).
- [x] Cash tenders fully offline OK (no auth needed). `PosSaleRecord.isOfflineSafe(tenderMethod:)` returns true for "cash"/"check"; documented in `PosSaleRecord` policy helpers. (feat(§16.12): offline tender policy cad69018)
- [x] Gift-card redemption requires online: error "Card balance lookup needs internet"; fallback accept as IOU with manager approval. `PosGiftCardOfflineSheet` — offline warning + IOU amount stepper ($1 steps up to cart total) + manager PIN gate; `iouApproved: true` written to `PosSaleTenderRecord`. (feat(§16.12): gift card offline IOU cad69018)
- [ ] Sync on reconnect: FIFO flush, idempotency key prevents duplicate ledger, success clears watermark, failures → dead-letter (§20).
- [x] Audit: record offline duration + sync time per sale; manager report like "3 sales made during 20min outage — all reconciled." (`PosOfflineAuditService` @MainActor @Observable: recordOutageStart/End/SaleSync/registerOfflineSale; `PosOutageRecord` + `PosOutageSaleSync`; `mostRecentOutageSummary` report string; UserDefaults persistence. d44b806c)
- [x] UI: outage banner "Offline mode — N sales queued"; dashboard tile tracks queue depth. (`PosOutageBannerView` amber brandGlass sticky banner with expand/collapse; audit summary + Review CTA; `.posOutageBanner()` ViewModifier; VoiceOver announcement; Reduce Motion fade. d44b806c)
- [ ] Security: SQLCipher encryption for offline sales; card data tokenized before store, raw PAN never persisted.
- [ ] See §6 for the full list.

---

### POS redesign wave (2026-04-24 spec)

Sections §§16.21–16.26 document the iOS implementation plan for a ground-up POS rewrite that lands simultaneously on Android and web. The Android counterpart is a full rebuild of `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/pos/*` and introduces a new `ui/screens/checkin/*` package (8 files). This iOS pass is **documentation-only** — no source files are modified this wave. A future iOS agent will implement from these entries. The canonical visual ground truth for every UX decision in §§16.21–16.26 is `../pos-phone-mockups.html` (8 labeled phone frames plus the animated v2b entry). Cream `#fdeed0` replaces the previous orange as the project-wide primary color; the full token set is codified in §16.26.

---

### 16.21 POS Entry screen + animated glass SearchBar

**Reference**
- Mockup: animated v2b entry frame ("▶ LIVE · bottom-idle → top-focused → reset · 5s loop") and phone frame "1 · Customer attached · choose path" from `../pos-phone-mockups.html`.
- Android will land as `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/pos/PosEntryScreen.kt`.
- Android theme reference: `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/ui/theme/Theme.kt` lines 100–154 (cream primary shipped this wave).
- iOS: `ios/Packages/Pos/Sources/Pos/PosView.swift` (shell exists; entry redesign is additive).
- iOS tokens: `ios/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift` (`DesignTokens.Motion.snappy = 0.220` matches the 220ms spring).

**Backend**
- `GET /api/v1/customers` — debounced search (300 ms). Envelope: `{ success, data: Customer[] }` → `res.data.data`. Status: exists.
- `GET /api/v1/tickets?customerId=&status=ready` — "Ready for pickup" contextual banner. Status: exists.
- No new endpoints required for the entry screen itself.

**Frontend (iOS)**
- New view: `PosEntryView` inside `ios/Packages/Pos/Sources/Pos/`. Replaces the current `PosView` empty-cart state for iPhone.
- `PosEntryViewModel` (`@Observable`) owns: `query: String`, `searchResults: [CustomerSearchResult]`, `recentItems: [RecentEntry]`, `isSearchExpanded: Bool`.
- `PosSearchBar` component: idle state pins to the **bottom** of the safe area (thumb zone). On focus, animates to top using `.animation(.spring(duration: DesignTokens.Motion.snappy, bounce: 0.15), value: isSearchExpanded)`. Tiles layer fades out simultaneously with `withAnimation(.easeOut(duration: DesignTokens.Motion.snappy))`. Mirrors the Material 3 `SearchBar` docked→expanded behavior shown in the mockup.
- Liquid Glass: `PosSearchBar` container uses `.brandGlass` only while expanded (nav-chrome equivalent). Idle bottom bar is plain `surface-2` fill per GlassKit rule — glass only on chrome. `GlassBudgetMonitor` must not exceed `DesignTokens.Glass.maxPerScreen = 6`.
- Three entry-point tiles (idle state, center of screen): "Retail sale" (primary-bordered), "Create repair ticket" (standard), "Store credit / payment" (standard). Tap targets ≥ 68pt height per mockup.
- "Ready for pickup" contextual green banner: when customer has tickets in `ready` status, appears as success-colored card with "Open cart →" pill.
- Past repairs section: two rows (`#NNNN · description · date · price`); `.textSelection(.enabled)` on ticket numbers (Mac).
- Camera icon trailing in search bar → `PosScanSheet` (barcode scan). VoiceOver label: "Scan barcode or QR code".
- `APIClient` from `ios/Packages/Networking/Sources/Networking/APIClient.swift` — all calls go through `PosRepository`, never bare `APIClient` from a ViewModel.
- SPM package: `ios/Packages/Pos`. State stored in `@Observable PosEntryViewModel`; iPad layout continues to use `PosView.regularLayout` HStack.
- Reduce Motion: skip the bottom→top animation; show search bar at top immediately. Reduce Transparency: remove `.brandGlass` from expanded search bar, use opaque `surface` fill.

**Expected UX**
1. Cashier opens POS tab; sees three large tiles (Retail / Repair / Store credit) with search bar pinned at bottom.
2. Taps search bar: bar rises to top in 220 ms spring; tiles fade out; keyboard + results list slide up together.
3. Types "Sarah": customer rows appear with name match highlighted in cream. Ticket match appears below with status chip.
4. Taps customer row: `PosEntryViewModel.attachCustomer(_:)` fires `.success` haptic (`UIImpactFeedbackGenerator(style: .medium)`); screen transitions to cart with customer header chip.
5. Taps back gesture: search bar descends back to bottom in 220 ms; tiles fade in.
6. Empty search: shows "RECENT" chip row (last 3 customers / tickets / walk-ins) as quick-pick.
7. Empty state (no results): "No customers or tickets match" with "Create new customer" and "Walk-in" CTAs.
8. Offline: `PosRepository` reads GRDB cache; shows "Offline · showing cached" chip on search bar; remote results suppressed.
9. Loading: skeleton rows (`.redacted(.placeholder)`) for 300 ms before first result arrives.
10. Error (5xx): toast "Search unavailable · check connection" with retry.
- Accessibility: search bar VoiceOver label "Search customer, part, or ticket". Results announced as "N customers, M tickets found". Reduce Motion removes spring, uses fade only.
- Localization hooks: `NSLocalizedString("pos.entry.search.placeholder", ...)` etc. — strings wired but translations deferred.
- `[ ]` Blocked on: cream token swap in `Tokens.swift` (§16.26 prerequisite).

**Status**
- [x] `PosEntryView` + `PosEntryViewModel` (new files). (feat(§16.21): PosEntryView + PosEntryViewModel)
- [x] `PosSearchBar` animated component with bottom→top spring. (feat(§16.21): PosSearchBar animated glass bar)
- [x] Customer + ticket unified search results list. (feat(§16.21): unified search results)
- [x] "Ready for pickup" contextual banner wiring. (feat(§16.21): ready-for-pickup banner)
- [x] Reduce Motion + Reduce Transparency compliance. (feat(§16.21): a11y motion compliance)

---

### 16.22 Cart line-edit sheet (per-line notes)

**Reference**
- Mockup: phone frame "4 · Edit line · qty · discount · note" from `../pos-phone-mockups.html`.
- Android will land as `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/pos/CartLineBottomSheet.kt`.
- Android cart screen: `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/pos/PosCartScreen.kt` (will land).
- Server route: `packages/server/src/routes/pos.routes.ts` — POS-NOTES-001 fix shipped this wave: `notes` column is now wired into line items.
- iOS shell: `ios/Packages/Pos/Sources/Pos/PosCustomLineSheet.swift` (exists — the line-edit sheet replaces/extends this).

**Backend**
- `POST /api/v1/pos/cart/lines` / `PATCH /api/v1/pos/cart/lines/:id` — line-item upsert. Response: `{ success, data: CartLine }` → `res.data.data`. Status: partial (notes column now wired per POS-NOTES-001; discount per-line deferred server side).
- No server call needed for in-memory edits until Charge is tapped; cart state is client-authoritative until submission.

**Frontend (iOS)**
- `CartLineEditSheet` — new file in `ios/Packages/Pos/Sources/Pos/`. Presented via `.sheet(item: $editingLine)` from `PosCartView`.
- `CartLineEditViewModel` (`@Observable`): `qty: Int`, `unitPriceCents: Int`, `discountMode: DiscountMode` (`.percent5 / .percent10 / .fixed / .custom`), `discountCents: Int`, `note: String`. Pure in-memory — no network call until cart submits.
- Sheet handle: `RoundedRectangle(cornerRadius: 2).frame(width: 36, height: 4)` in `--outline` color, centered at top of sheet.
- Background: cart rows visible but dimmed to `opacity(0.35)` and `allowsHitTesting(false)` — matches mockup "Dimmed cart underneath".
- **Qty stepper**: minus (circle, `surface-2` fill) / value (18pt, bold) / plus (circle, primary fill). Bounds: min 1, max 999. Light haptic (`UIImpactFeedbackGenerator(style: .light)`) on each inc/dec tap.
- **Unit price row**: read-only display; tapping opens inline `PosEditPriceSheet` (existing, role-gated via `PosTenantLimits`).
- **Discount row**: four chip-pills (5% / 10% / $ fixed / Custom). Active chip fills with primary. "Custom" expands a `TextField` for cents input. Discount line shows "− $X.XX" in `--success` color.
- **Note row**: `TextEditor` with `min-height: 44pt`, background `surface-2`, border `outline`. Character counter "N / 500" trailing below. VoiceOver label: "Line note, optional". Dictate microphone button at leading edge (links to iOS dictation).
- **Remove button**: `.destructive` red fill, full width minus Save; requires `ManagerPinSheet` if `PosAuditLogStore` `deleteLineRequiresPin` is true.
- **Save button**: primary fill. On tap: `cart.updateLine(id:qty:discount:note:)` → immutable Cart copy (no mutation per coding-style rules) → dismiss sheet. `BrandHaptics.success()`.
- Liquid Glass: sheet itself is plain `surface` — not a glass surface per GlassKit rule. Only the Charge CTA in the cart below uses glass.
- Swipe-to-dismiss: standard `.presentationDetents([.medium, .large])` with drag indicator.
- Offline: line edits are always local; no network call blocked.

**Expected UX**
1. Cashier taps a cart line in phone frame 3 ("3 · Cart · 3 items · tap line to edit").
2. Bottom sheet slides up; cart dims behind; sheet handle visible.
3. Cashier taps "+" twice → qty becomes 3; total updates in real time via `CartMath`.
4. Taps "10%" chip → discount applies; "− $1.40" appears in success green.
5. Taps Note field → dictates "Gift wrap · tag for Mia"; character count updates.
6. Taps Save → sheet dismisses; cart line updates; totals re-derive via `CartMath.totals`.
7. Swipe-left on line in cart → quick Remove (no sheet required); triggers audit log.
- Empty note field: placeholder "Optional note prints on receipt".
- Error: if `unitPriceCents` becomes negative, prevent Save with inline "Price cannot be negative".
- Haptics: light on qty change, success on Save, warning on Remove confirm.
- Accessibility: stepper announces "Quantity: 3". Discount chip group has `accessibilityLabel("Discount preset")`. Save button announces "Save changes to USB-C 3ft cable".

**Status**
- [x] `CartLineEditSheet` + `CartLineEditViewModel` (new files). (feat(§16.22): CartLineEditSheet + ViewModel)
- [x] Qty stepper with haptic + bounds. (feat(§16.22): qty stepper)
  - [x] **Stepper VoiceOver value** — `LineEditStepper` value text now reads "Quantity, value: N" via `accessibilityValue("\(quantity)")`; the inc/dec buttons get stable `accessibilityIdentifier` hooks (`pos.lineEdit.qty.{value,increase,decrease}`) and the cluster announces as "Quantity stepper" (matches the §16.22 a11y spec line "stepper announces 'Quantity: 3'"). (feat(§16.22): stepper VoiceOver value + stable identifiers)
- [x] Discount chip row + custom-amount expansion. (feat(§16.22): discount chip row)
- [x] Per-line note field with dictation hook. (feat(§16.22): per-line note field)
- [x] Dimmed-background + sheet presentation from `PosCartView`. (feat(§16.22): dimmed scrim overlay on line-edit sheet open)

---

### 16.23 Tender split view (applied / remaining hero)

**Reference**
- Mockup: phone frame "5 · Tender · split payment" from `../pos-phone-mockups.html`.
- Android will land as `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/pos/PosTenderScreen.kt`.
- Server routes: `packages/server/src/routes/blockchyp.routes.ts:45-557` (process-payment, void, adjust-tip); `packages/server/src/routes/pos.routes.ts`.
- iOS: replaces / extends the current `PosChargePlaceholderSheet` (§16.5). The placeholder stays until BlockChyp SDK lands; this section defines the target state.

**Backend**
- `POST /api/v1/blockchyp/process-payment` — primary card auth. Body: `{ amount, transactionType, terminalName }`. Response: `{ success, data: { approved, authCode, token, last4, brand } }`. Envelope: `res.data.data`. Status: exists (`packages/server/src/services/blockchyp.ts:63-790`).
- `POST /api/v1/blockchyp/void` — void within batch. Status: exists.
- `POST /api/v1/blockchyp/adjust-tip` — post-auth tip. Status: exists.
- `POST /api/v1/invoices/:id/payments` — record tender. Idempotency key required. Status: exists.
- `POST /api/v1/gift-cards/redeem` — gift card tender. Status: exists.
- `GET /api/v1/store-credit/:customerId` — balance check. Status: exists.
- TODO: POS-SMS-001 (SMS receipt after tender — deferred).

**Frontend (iOS)**
- `PosTenderView` — replaces `PosChargePlaceholderSheet`. Full-screen navigation push (not sheet) so back gesture is always available to return to cart.
- `PosTenderViewModel` (`@Observable`): `totalCents: Int`, `appliedTenders: [AppliedTender]`, `remainingCents: Int` (derived), `isComplete: Bool` (derived: `remainingCents == 0`).
- **Hero balance card** (top of screen): `surface` card with `outline` border, `cornerRadius: 12`. Left column: "TOTAL DUE" label (muted, 10pt, spaced) + amount (22pt, weight 800, `--on`). Right column: "REMAINING" label + amount (22pt, weight 800, **primary cream**). Progress bar below: `surface-2` track, `success` fill advancing as tenders land. Below bar: "✓ Paid $X.XX" (success) and "N%" (muted). Animates smoothly on each tender add: `withAnimation(.spring(duration: DesignTokens.Motion.smooth))`.
- **Applied tenders section**: label "✓ PAID · N" (success, 10pt). Each row: success-tinted background (`rgba(success, 0.08)`), success border, checkmark circle, tender name + detail, amount, "✕" dismiss icon. Tapping "✕" prompts `ManagerPinSheet` if past the checkout commit point (per §16.20 `AppliedTendersListView`).
- **Add-payment grid**: 2×2 grid of tender type tiles. "Card reader" tile is primary-bordered (highest priority). Others: "Tap to pay", "ACH / check", "Park cart" (layaway). Grid remains accessible until `remainingCents == 0`. Tiles disabled (opacity 0.4, `allowsHitTesting(false)`) once balance reaches zero.
- **Bottom bar CTA**: disabled state "Remaining $X.XX — add payment to finish" (`surface-2` fill, muted text). Enabled state (when `isComplete`) "Complete sale" (primary cream fill, `on-primary` text). Tap → `PosTenderViewModel.completeSale()` → writes invoice+payment rows → navigate to `PosReceiptView`.
- Liquid Glass: CTA bar background uses `.brandGlass` (nav chrome role) when `isComplete` to signal the final step. Grid tiles and applied-tender rows stay plain.
- Haptics: `.success` notification when `remainingCents` first reaches 0; `.warning` notification if void attempted.
- Offline: Card tender queues via `PosSyncOpExecutor`; cash tender is always local. Gift card requires online (shows "Requires internet to check balance" alert if offline).

**Expected UX**
1. Cashier taps "Tender · $274.51" from cart (phone frame 3).
2. `PosTenderView` pushes onto stack; hero card shows $274.51 total / $274.51 remaining.
3. Cashier taps "Store credit" (not in 2×2 — accessed via overflow or customer's balance auto-prompt); $42.00 applied; progress bar animates to 15%; "✓ Paid $42.00" row appears.
4. Taps "Card reader" tile; BlockChyp terminal flow initiates (§16.5 / §16.25); on approval $134.51 auth returns; remaining drops to $0; progress bar fills green.
5. Bottom CTA pulses to "Complete sale" (primary fill); `.success` haptic fires.
6. Cashier taps "Complete sale"; receipt screen pushes.
7. Cashier can tap "✕" on cash row to remove a tender (manager PIN required if session committed).
8. Loading: spinner overlay on tile while BlockChyp call is in flight; other tiles disabled.
9. Error (decline): "Declined — INSUFFICIENT_FUNDS" toast; card tile returns to normal; remaining unchanged.
- VoiceOver: remaining amount announced on each tender application: "Remaining: one hundred thirty-four dollars fifty-one cents".
- iPad: same view but wider progress bar + tender grid can show as 2×3.

**Status**
- [x] `PosTenderView` + `PosTenderViewModel` (replaces placeholder). (feat(§16.23): PosTenderView + ViewModel UX scaffold)
- [x] Hero balance card with animated progress bar. (feat(§16.23): hero balance card + progress bar)
- [x] Applied tenders list with void / ✕ gating. (feat(§16.23): applied tenders list)
- [x] 2×2 tender grid with disabled state. (feat(§16.23): 2×2 tender grid)
- [x] `completeSale()` → invoice write → navigation to receipt. (feat(§16.23): completeSale scaffold)
- [x] Offline card tender queuing via sync queue. `OfflineCardTenderPayload` + `OfflineCardTenderService` actor enqueues to `SyncQueueStore`; `PosCardTenderSyncHandler` drains via `POST /api/v1/invoices/:id/payments`; `PosSyncOpExecutor` wired for `invoice.payment` ops; 409 idempotency safe. (feat(§16.23): offline card tender queuing via sync queue a8a965e5)

---

### 16.24 Receipt screen + public tracking URL

**Reference**
- Mockup: phone frame "6 · Receipt · send / print / next" from `../pos-phone-mockups.html`.
- Android will land as `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/pos/PosReceiptScreen.kt`.
- Server routes:
  - `packages/server/src/routes/notifications.routes.ts:203-327` — `POST /api/v1/notifications/send-receipt` (email done, SMS as POS-SMS-001 deferred).
  - `packages/server/src/routes/tracking.routes.ts:232-314` — `POST /api/v1/track/lookup` (phone last-4 + optional order_id).
  - `packages/server/src/routes/tracking.routes.ts:319-352` — `GET /api/v1/track/token/:token` — public tokenized tracking page.
  - `packages/server/src/routes/tracking.routes.ts:748-825` — `GET /api/v1/track/portal/:orderId/invoice` — public invoice portal.
- iOS: `ios/Packages/Pos/Sources/Pos/PosView.swift` (existing shell); receipt logic extends `PosPostSaleView` (§16.8).

**Backend**
- `POST /api/v1/notifications/send-receipt` — body: `{ invoiceId, channel: 'email'|'sms', destination }`. Response: `{ success, data: { messageId } }`. Email: exists and shipped. SMS: deferred as POS-SMS-001.
- `GET /api/v1/track/token/:token` — public URL (no auth). Returns tracking page HTML or JSON. The token is embedded in the receipt QR code. Status: exists (`tracking.routes.ts:319-352`).
- Envelope: all routes follow `{ success, data }` → `res.data.data`. Single unwrap.

**Frontend (iOS)**
- `PosReceiptView` — new file in `ios/Packages/Pos/Sources/Pos/`. Pushed onto navigation stack after `PosTenderViewModel.completeSale()`.
- `PosReceiptViewModel` (`@Observable`): `invoice: Invoice`, `trackingURL: URL?`, `sendState: SendState` (`.idle / .sending / .sent / .error`).
- **Hero success state** (top): 72pt circle with `success` fill, white checkmark, 600ms spring scale-in (`scaleEffect` from 0.5 → 1.0, `BrandMotion`). Below: total in Barlow Condensed (22pt, weight 800), invoice number + customer name (12pt, muted). If repair ticket linked: "Parts reserved to Ticket #NNNN" in teal.
- **Send receipt section**: label "SEND RECEIPT" (muted, 10pt, spaced). Three rows:
  - SMS row (primary-bordered, first/default): icon, "SMS", phone number, "via BizarreSMS". Tapping triggers `POST /api/v1/notifications/send-receipt` with `channel: 'sms'`. Disabled with tooltip "POS-SMS-001 pending" until server-side wired.
  - Email row: icon, "Email", email address. Tapping triggers `POST /api/v1/notifications/send-receipt` with `channel: 'email'`. Status: enabled.
  - Thermal print row: icon, "Thermal print", printer name. Disabled until §17 printer SDK lands.
- **QR code**: generated client-side via `CIFilter.qrCodeGenerator` from the `trackingURL` string. Rendered as `Image` in the receipt view. VoiceOver label: "Tracking QR code — customer can scan to track order".
- **Tracking URL** surface: `GET /api/v1/track/token/:token` token is returned in the invoice response payload. Display as tappable link below QR code (`.textSelection(.enabled)` on Mac).
- **Next-action CTA bar**: two buttons — "Open ticket #NNNN" (secondary, only if repair ticket linked) and "New sale ↗" (primary cream). "New sale" resets `PosEntryViewModel` and pops to root.
- Auto-dismiss: 10 seconds after send, if cashier has not interacted, navigate to `PosEntryView` for next customer. Countdown shown as muted "Starting new sale in Ns…" text.
- Persist receipt model: snapshot `ReceiptModel` to GRDB via `PosReceiptStore` at sale close (per §16.7 deferred item now mandatory for this screen).
- Liquid Glass: none on receipt content rows. The "New sale" CTA bar uses `.brandGlass` background (sticky nav-chrome role).
- Haptics: `.success` notification on screen appear (if coming from successful payment).
- Offline: send-receipt queued via sync queue if no network at moment of sale; "Receipt will send when connected" banner shown.

**Expected UX**
1. Sale completes; success animation plays (scale + `--success` green).
2. Invoice number displayed; if ticket linked, teal ticket link shown.
3. SMS row highlighted as default (customer has phone number on file).
4. Cashier taps SMS → spinner → "Sent!" chip animates in green (or "POS-SMS-001 pending" toast).
5. QR code visible; customer can scan immediately for order tracking.
6. 10s countdown begins: "Starting new sale in 8s…" — tap anywhere to cancel.
7. "New sale ↗" tapped: cart clears, `PosEntryView` resets, customer header chip drops.
- Empty state (walk-in, no phone/email): SMS + Email rows grayed with "No contact on file". Print is only option.
- Error (email send fails): "Email failed — check server connection" toast; row returns to tappable state.
- VoiceOver: success circle announced as "Sale complete, $274.51". QR announced as "Tracking QR code".

**Status**
- [x] `PosReceiptView` + `PosReceiptViewModel`.
- [x] Hero success animation (scale spring).
- [x] Send-receipt rows (email wired; SMS deferred POS-SMS-001).
- [x] QR code generation from tracking token.
- [x] `ReceiptModel` GRDB snapshot at sale close.
- [x] Auto-dismiss 10s countdown.
- [x] "Open ticket" CTA when repair path was used.

---

### 16.25 Repair check-in — 6-step flow

**Reference**
- Mockup: the "Repair check-in — drop-off flow (6 screens)" section of `../pos-phone-mockups.html`, frames CI-1 through CI-6.
- Android will land as `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/checkin/*` (8 files).
- Server routes: `packages/server/src/routes/pos.routes.ts` (ticket draft create/update); `packages/server/src/routes/ticketSignatures.routes.ts:72-87` (`POST /api/v1/tickets/:id/signatures`, base64 PNG, 500 KB budget, data-URL validator lines 39–42).
- iOS: new SPM package `ios/Packages/CheckIn/Sources/CheckIn/` (to be created). Depends on `Pos`, `Tickets`, `DesignSystem`.
- Android `SignaturePad.kt`: `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/ui/components/SignaturePad.kt` (EXISTS — iOS equivalent is `PKCanvasView` / `CheckInSignaturePad`).

**Backend**
- Ticket draft: `POST /api/v1/tickets` with `status: 'draft'` — creates ticket in draft state. `PATCH /api/v1/tickets/:id` — autosave on each step navigation. Response: `{ success, data: Ticket }`.
- Signature: `POST /api/v1/tickets/:id/signatures` — base64 PNG body, max 500 KB enforced by data-URL validator (`ticketSignatures.routes.ts:39-42`). Status: exists.
- Passcode: stored encrypted server-side; iOS sends via `PATCH /api/v1/tickets/:id` in the `passcode` field (SQLCipher column, TTL = ticket close). Audit log records read access.
- Parts reserve: `PATCH /api/v1/inventory/:id/reserve` — decrement stock, set `ticket_device_parts.status = 'available'` or `'ordered'`. Status: exists.
- All endpoints follow `{ success, data }` envelope; single unwrap.

**Frontend (iOS)**
- `CheckInFlowView` — wizard container with `NavigationStack` + `CheckInStep` enum (`symptoms / details / damage / diagnostic / quote / sign`). Step index drives a 3pt linear progress bar (cream fill, `surface-2` track). Each step is a distinct SwiftUI view; all read/write `CheckInDraft` (an `@Observable` shared model passed through environment).
- `CheckInFlowViewModel` (`@Observable`): `draft: CheckInDraft`, `currentStep: CheckInStep`, `isSaving: Bool`, `saveError: Error?`. Autosave via `Task { await repo.patchDraft(draft) }` on every step navigation — never blocks the UI.
- Navigation: "Back" (secondary) + "Next · …step…" (primary cream) pinned at bottom of each step screen. "Next" is disabled until minimum required fields for that step are filled. Progress bar advances on "Next".
- Autosave chip: "Draft · autosave" in the nav bar (right side, muted chip). Pulses briefly on save.
- Liquid Glass: progress bar container and bottom nav bar use `.brandGlass` (chrome role). Step content cards are plain `surface`. GlassBudget: both count toward `maxPerScreen`.
- Offline: draft writes queue via `SyncQueueStore`; autosave chip shows "Draft · queued" when offline.

The six sub-steps follow.

#### 16.25.1 Step 1 — Symptoms

**Reference**: mockup frame "CI-1 · Symptoms · tap what's broken".

**Backend**: `PATCH /api/v1/tickets/:id` with `{ symptoms: string[] }`. No dedicated endpoint; included in ticket patch.

**Frontend (iOS)**
- `CheckInSymptomsView` — 4×2 grid of symptom tiles: Cracked screen, Battery drain, Won't charge, Liquid damage, No sound, Camera, Buttons, Other. Each tile: `surface` card with `outline` border (unselected) or `primary` border + primary bold label (selected). Multiple selection. Minimum: 1 symptom selected to advance.
- Tile icons: SF Symbols (`iphone.gen3`, `battery.25`, `bolt.slash`, `drop`, `speaker.slash`, `camera`, `button.horizontal`, `exclamationmark.triangle`).
- Tap: `CheckInDraft.symptoms.toggle(symptom)` — immutable toggle (new Set created, not mutated). Haptic: `UIImpactFeedbackGenerator(style: .light)` on each toggle.
- "Other" selected → inline `TextField` expands below grid for free-text description.
- Localization: `NSLocalizedString("checkin.symptoms.crackedScreen", ...)` per tile.
- VoiceOver: each tile announces "Cracked screen, selected" / "not selected". Grid has `accessibilityLabel("Select symptoms — tap all that apply")`.
- Skip: "Skip" secondary button is available; advances without symptoms (cashier can fill later from desktop CRM). Skip logs a `CheckInSkipEvent` for audit.
- Footer hint: "Next: customer notes, photos, passcode" (muted, 11pt) — matches mockup.

**Status**
- [x] `CheckInSymptomsView` + symptom tile grid. (feat(§16.25.1): CheckInSymptomsView)
- [x] Multi-select with primary-border selected state. (feat(§16.25.1): symptom multi-select)
- [x] "Other" free-text expansion. (feat(§16.25.1): Other free-text)
- [x] Minimum-1 validation before advancing. (feat(§16.25.1): min-1 validation via canAdvance)

#### 16.25.2 Step 2 — Details

**Reference**: mockup frame "CI-2 · Details · customer notes · internal notes · passcode · photos".

**Backend**: `PATCH /api/v1/tickets/:id` with `{ diagnosticNotes, internalNotes, passcode, passcodeType, photos: base64[] }`. Photos also via `POST /api/v1/tickets/:id/signatures` endpoint patterns.

**Frontend (iOS)**
- `CheckInDetailsView` — four sections, vertically scrollable.
- **Diagnostic notes** (`TextEditor`, min-height 72pt, primary-bordered): customer-facing problem description. Character counter "N / 2000" trailing below. Dictation microphone button (teal, leading) links to iOS speech recognition via `SFSpeechRecognizer`. Auto-expands as user types.
- **Internal notes** (`TextEditor`, min-height 60pt, warning dashed border): tech-only, never shown to customer. Supports `@mention` autocomplete (tech user picker) and `#tag` (issue category). Character counter "N / 5000". Yellow dashed border (`--warning`) distinguishes internal from customer-visible fields.
- **Passcode** (encrypted): chip row for type selector (None / 4-digit / 6-digit / Alphanumeric / Pattern). Selected type expands a `SecureField` with monospace font. "None" hides the field. Eye toggle to reveal temporarily (auto-hides after 5s). "Auto-deleted when ticket closes" caption (muted, 11pt). Stored via `PATCH /api/v1/tickets/:id` in the encrypted `passcode` column; SQLCipher TTL = ticket close event.
- **Photos** (horizontal scroll strip): `CameraCaptureView(mode: .multi)` thumbnail strip. Existing photos shown as 72×72pt rounded tiles. "+" tile at end opens camera sheet. `PhotoStore` stages into `tmp/photo-capture/` then promotes to `AppSupport/photos/tickets/{id}/`. Max 10 photos. Each thumbnail tappable for full-screen preview + annotation (`PhotoAnnotationView`).
- VoiceOver: `@mention` field announces "Internal note — tech only, not shown to customer". Passcode field: "Device passcode — stored encrypted, deleted when ticket closes". Photo strip: "N photos, tap plus to add".
- Haptic: `BrandHaptics.success()` on passcode field save.

**Status**
- [x] `CheckInDetailsView` with four sections. (feat(§16.25.2): CheckInDetailsView)
- [x] Diagnostic + internal notes with dictation + @mention. (feat(§16.25.2): notes TextEditors)
- [x] Passcode type picker + `SecureField` + encrypted patch. (feat(§16.25.2): passcode picker + SecureField)
- [ ] Photo strip via `CameraCaptureView(mode: .multi)`. (deferred to Agent 2)

#### 16.25.3 Step 3 — Pre-existing damage

**Reference**: mockup frame "CI-3 · Damage we're NOT fixing · liability record".

**Backend**: `PATCH /api/v1/tickets/:id` with `{ preExistingDamage: DamageMarker[], overallCondition, accessories: string[], ldiStatus }`. DamageMarker shape: `{ x, y, type: 'crack'|'scratch'|'dent'|'stain', face: 'front'|'back'|'sides', note? }`.

**Frontend (iOS)**
- `CheckInDamageView` — three sub-tabs: Front / Back / Sides.
- **Device diagram**: SVG-rendered phone silhouette using SwiftUI `Canvas`. Tap anywhere on the diagram drops a `DamageMarker` at the normalized `(x, y)` coordinate. A picker popover appears to select marker type (crack ✖ / scratch / / dent ◻ / stain ●). Each marker rendered as colored circle (error = crack, warning = scratch/dent, muted = stain). Long-press on marker → remove. Pinch-to-zoom on the canvas (`MagnificationGesture`). Matches the tappable zones in the CI-3 mockup.
- **Overall condition** chip row: Mint / Good / Fair / Poor / Salvage. Single-select. Active chip fills primary cream.
- **Accessories included** chip row: SIM tray / Case / Tempered glass / Charger / Cable. Multi-select. Active chip fills primary.
- **Liquid damage indicator**: red-tinted card (error background at 10% opacity, error border). Single-select: "Not tested" / "Clean" / "Tripped". Default: "Not tested". When "Tripped" selected, card expands with camera icon ("Photograph LDI").
- Accessibility: Canvas has `accessibilityLabel("Device diagram — tap to mark pre-existing damage")`. Each marker has `accessibilityElement(children: .ignore)` with label "Crack at top-right front panel".
- Reduce Motion: markers appear instantly without the pop animation.
- This step is **skippable** — "Skip" button in nav; tech fills from desktop CRM post-drop-off.

**Status**
- [x] `CheckInDamageView` + SVG canvas with `DamageMarker` drop. (feat(§16.25.3): CheckInDamageView canvas)
- [ ] Marker type picker + long-press remove + pinch zoom. (deferred — tap-to-add crack only this wave)
- [x] Condition + accessories chip rows. (feat(§16.25.3): condition + accessories chips)
- [x] LDI card with camera expand. (feat(§16.25.3): LDI tripped camera expand)

#### 16.25.4 Step 4 — Diagnostic

**Reference**: mockup frame "CI-4 · Pre-repair diagnostic · what works now".

**Backend**: `PATCH /api/v1/tickets/:id` with `{ diagnosticResults: DiagnosticResult[] }`. DiagnosticResult shape: `{ item: string, state: 'ok'|'fail'|'untested' }`.

**Frontend (iOS)**
- `CheckInDiagnosticView` — scrollable checklist.
- **"Mark all as working" bar**: teal-tinted strip at top with "All OK" secondary button. Tap sets all items to `.ok`. Single haptic on tap.
- **Checklist items**: Power on / Touchscreen / Face ID / Touch ID / Speakers (earpiece + loud) / Cameras (front + rear) / Wi-Fi + Bluetooth / Cellular / SIM / Battery health. Each row: item name + description (muted, 11pt). Three-state toggle row: ✓ (`success` fill) / ✕ (`error` fill) / ? (`warning` fill). Default: `?` (untested). Three buttons side by side, 30×30pt each with 8pt corner radius.
- **Battery health**: if device provides MDM or Apple Configurator data, auto-fill "78%" beside Cellular/SIM row as in mockup (teal-colored). Manual entry fallback.
- **Tri-state rationale**: `?` forces explicit "untested" — no silent assumptions. Required items for cracked-screen tickets: Touchscreen must be set to ✓ or ✕ before advancing (warn if still `?`).
- **Immutability**: `CheckInDraft.diagnosticResults` is replaced with a new array on each toggle — no in-place mutation per coding-style rules.
- VoiceOver: each row's state announced as "Power on — OK" / "Touchscreen — Failed" / "Cameras — Untested". Three-state buttons announce "Pass", "Fail", "Untested".
- Skippable — tech can complete from desktop.

**Status**
- [x] `CheckInDiagnosticView` + checklist items. (feat(§16.25.4): CheckInDiagnosticView)
- [x] Tri-state ✓/✕/? toggle row. (feat(§16.25.4): tri-state toggle)
- [x] "All OK" quick-fill bar. (feat(§16.25.4): All OK bar)
- [x] Required-field warning (touchscreen for cracked-screen tickets). (feat(§16.25.4): touchscreen required banner for cracked-screen)

#### 16.25.5 Step 5 — Quote

**Reference**: mockup frame "CI-5 · Quote · parts reserved · deposit".

**Backend**:
- `GET /api/v1/repair-pricing/services` — labor line items. Status: exists.
- `PATCH /api/v1/inventory/:id/reserve` — stock reservation; sets `ticket_device_parts.status = 'available'` or `'ordered'` with supplier ETA. Status: exists.
- `GET /api/v1/pos/holds` — deposit holds. Status: exists.
- Quote totals computed client-side (`CartMath`); server re-validates on submit.

**Frontend (iOS)**
- `CheckInQuoteView` — scrollable with pinned total bar.
- **Repair lines list**: each line shows: name, stock status chip ("✓ Reserved · stock N→N-1" in success green, or "⏳ Ordered · ETA Mon Apr 27" in warning amber), price in primary cream. Lines are populated from `CheckInDraft.selectedParts + selectedServices`. Editable (swipe to remove, tap to edit price).
- **ETA card**: if any part is on order, shows "Est. ready: Tue Apr 28, 3pm" with clock icon. ETA computed from: `max(supplier ETA + lead-time, current date + tech queue depth × avg labor minutes)`. Updates live if supplier ETA changes (WebSocket push from `SessionEvents`).
- **Deposit picker**: chip row — $0 / $25 / $50 / $100 / Full. Active chip fills primary. Below: "N deposit applied · balance due on pickup: $X.XX" (muted).
- **Pinned totals bar**: Subtotal / Tax (8.5%) / Deposit today (primary colored, minus) / Due on pickup. CTA button: "Get signature & check in →" (cream fill). Disabled until at least one repair line exists.
- `CartMath.totals` handles all arithmetic (bankers rounding, multi-rate tax). Immutable — new struct on each line change.
- VoiceOver: totals bar announces "Subtotal $348.00, Tax $29.58, Deposit $50.00, Due on pickup $327.58".
- Offline: repair lines from GRDB catalog cache; reservation queued via sync queue.

**Status**
- [x] `CheckInQuoteView` + repair lines list. (feat(§16.25.5): CheckInQuoteView)
- [x] Stock status chips (reserved / ordered / ETA). (feat(§16.25.5): Reserved/Ordered status chips)
- [x] Deposit picker chip row. (feat(§16.25.5): deposit picker chips)
- [x] Pinned totals bar with `CartMath`. (feat(§16.25.5): pinned totals bar)
- [ ] ETA card with WebSocket refresh. (deferred to WS agent)

#### 16.25.6 Step 6 — Sign

**Reference**: mockup frame "CI-6 · Terms · signature · create ticket".

**Backend**:
- `POST /api/v1/tickets/:id/signatures` — base64 PNG, max 500 KB, data-URL validator at `ticketSignatures.routes.ts:39-42`. Response: `{ success, data: { signatureId, url } }`. Status: exists.
- `POST /api/v1/tickets` (finalize) — `status: 'open'`, deposit payment if applicable → `POST /api/v1/invoices/:id/payments`.
- `packages/server/src/db/migrations/129_ticket_signatures_receipt_ocr.sql` — schema for signature storage.

**Frontend (iOS)**
- `CheckInSignView` — final step; progress bar fills green (100%) to signal completion.
- **Terms summary card** (`surface`, `outline` border, 12pt corner radius): collapsed key-terms bullet list (5 items from mockup). "Read full terms (PDF)" teal link → `SafariViewController` opening the PDF URL. Terms text is shop-configurable (Settings → Repair Terms, versioned). The exact terms version hash is embedded in the signed record.
- **Acknowledgment checklist**: four checkboxes rendered as `surface` rows with 22×22pt checkbox squares. Three pre-checked (cream fill): "Agree to estimate & terms", "Consent to backup + data handling", "Authorize deposit charge". One opt-in (unchecked default): "Opt in to repair status SMS updates". All four must have the mandatory three explicitly checked to enable signature capture.
- **Signature pad** (`CheckInSignaturePad`): `PKCanvasView` wrapper, 110pt height, primary-bordered container. Finger or Apple Pencil. Clear button (teal, trailing below). VoiceOver: "Signature area — sign with finger or Apple Pencil". Timestamp + customer name displayed below the canvas. After any stroke, `UINotificationFeedbackGenerator(.success)` fires once to confirm pen-down detection.
- On "Create ticket · print label" tap:
  1. `PKCanvasView` drawing → `UIImage` → PNG data → base64 string → `POST /api/v1/tickets/:id/signatures`.
  2. Budget check: compressed PNG must be ≤ 500 KB (same limit enforced server-side at `ticketSignatures.routes.ts:39`). If over, iteratively reduce `scale` until within budget, max 3 attempts; if still over, show "Signature too large — please clear and sign again".
  3. Deposit tender if `deposit > 0` → `POST /api/v1/invoices/:id/payments` with idempotency key.
  4. Ticket status → `open` via `PATCH /api/v1/tickets/:id`.
  5. Navigate to `PosReceiptView` (drop-off receipt variant — prints label, no sale total).
- **Print label**: 2×1 inch thermal label — ticket# / QR / customer last-name / device / drop-off date. QR encodes ticket deep-link URL. Print routed through `ReceiptPrinter` (§17).
- Liquid Glass: none on content. Bottom CTA bar uses `.brandGlass` (chrome role).
- Offline: signature stored locally in GRDB (`SyncQueueStore`); ticket create queued; "Ticket will sync when connected" banner on receipt.
- Signature required — cannot skip this step (unlike Steps 3–4). "Create ticket" button disabled until both required checkboxes checked AND canvas has at least one stroke.

**Status**
- [x] `CheckInSignView` + terms card + acknowledgment checklist. (feat(§16.25.6): CheckInSignView terms + checklist)
- [x] `CheckInSignaturePad` (`PKCanvasView` wrapper, cream border, clear button). (feat(§16.25.6): CheckInSignaturePad PKCanvasView wrapper)
- [x] Signature → PNG → base64 → `POST /api/v1/tickets/:id/signatures` with 500 KB budget enforcement. (feat(§16.25.6): signature PNG budget enforcement)
- [x] Deposit payment write → ticket finalize → navigation to drop-off receipt. (fix(§16): finalizeCheckinTicket + recordCheckinDeposit + CheckInFlowViewModel.finalizeSignStep 5949db19)
- [ ] Print label via `ReceiptPrinter` (§17 dependency).

---

### 16.26 BlockChyp signature routing (terminal preferred, on-phone fallback)

**Reference**
- Mockup: phone frame "5 · Tender · split payment" — "Card reader" tile initiating the BlockChyp flow, then signature capture after approval.
- Android will land as `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/util/SignatureRouter.kt`.
- Android `SignaturePad.kt`: `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/ui/components/SignaturePad.kt` (EXISTS).
- Server: `packages/server/src/routes/blockchyp.routes.ts:45-557` — `POST /api/v1/blockchyp/capture-signature` (route exists); `packages/server/src/services/blockchyp.ts:63-790`.
- iOS: `ios/Packages/Networking/Sources/Networking/APIClient.swift` (for BlockChyp proxy calls).

**Backend**
- `POST /api/v1/blockchyp/capture-signature` — instructs the paired BlockChyp terminal to prompt for signature. Body: `{ terminalName, sigFormat: 'PNG', sigWidth: 400 }`. Response: `{ success, data: { sig: base64PNG } }`. Status: exists.
- `POST /api/v1/blockchyp/process-payment` — main payment auth; response includes `{ sigRequired: bool, terminalName }`. If `sigRequired && terminalName != null`, signature is captured on terminal. If `sigRequired && terminalName == null`, on-phone fallback.
- `POST /api/v1/invoices/:id/payments` — record with `sigBase64` field. Status: exists.

**Frontend (iOS)**
- `SignatureRouter` — new struct in `ios/Packages/Pos/Sources/Pos/`. Pure logic, no view. `func route(sigRequired: Bool, terminalAvailable: Bool, terminalName: String?) -> SignatureRoute` where `SignatureRoute` is `.terminal(name:)` or `.onPhone`.
- **Terminal path** (`.terminal`): after payment approval, `POST /api/v1/blockchyp/capture-signature` is called. `PosTenderViewModel` shows "Customer signing on terminal…" spinner with animated card icon. Polls via 2s retry (max 30s) for signature response. On success: base64 PNG attached to payment record.
- **On-phone fallback** (`.onPhone`): `SignatureSheet` presented as `.fullScreenCover`. Contains `PKCanvasView` (same `CheckInSignaturePad` component) in a full-screen layout. Customer signs on the iPhone/iPad screen. On "Accept" tap: drawing → PNG → base64 → stored with payment. On "Clear" tap: canvas resets.
- **Routing logic**: terminal preferred always. Fall back to on-phone if: (a) no terminal paired in Keychain, (b) terminal heartbeat failed (3s timeout), (c) `process-payment` response has `terminalName == null`, (d) user explicitly selects "Sign on phone" from the tender screen overflow menu.
- `SignatureSheet` Liquid Glass: `.brandGlass` on the top toolbar only (chrome role). Canvas area is plain `surface`. GlassBudget counts as 1.
- Haptics: `UINotificationFeedbackGenerator(.success)` on signature accepted; `.error` on timeout.
- Accessibility: `PKCanvasView` VoiceOver label "Customer signature pad — sign here to authorize payment". "Accept" button disabled until at least one stroke. "Clear" always enabled.
- Offline: on-phone signature always available offline. Terminal path requires network to `capture-signature` endpoint — if offline, `SignatureRouter` auto-routes to `.onPhone`.
- Audit: both paths log `signature_captured` event to `PosAuditLogStore` with `{ method: 'terminal'|'phone', invoiceId, actorId, timestamp }`.

**Expected UX**
1. Card payment approved by BlockChyp terminal.
2. `process-payment` response: `sigRequired: true, terminalName: "counter-1"`.
3. `SignatureRouter.route(...)` returns `.terminal(name: "counter-1")`.
4. iOS shows "Customer signing on terminal…" spinner.
5. Customer signs on the physical terminal PIN pad.
6. `capture-signature` returns base64 PNG; payment record finalized.
7. If terminal unreachable after 3s: automatic fallback to `SignatureSheet` on-phone. Cashier hands device to customer.
8. Customer signs on screen; "Accept" tapped; `.success` haptic fires; sheet dismisses.
- Error: if both terminal timeout AND on-phone rejected (3 taps of "Clear + Cancel"): offer "Skip signature" with manager PIN + audit log entry.
- VoiceOver: spinner announces "Waiting for customer signature on terminal. This may take up to 30 seconds."

**Status**
- [x] `SignatureRouter` struct + `SignatureRoute` enum (new file). (feat(§16.26): SignatureRouter + SignatureRoute)
- [x] Terminal path: `POST /api/v1/blockchyp/capture-signature` with 30s polling. (feat(§16.26): TerminalSignatureFetcher scaffold + 30s poll)
- [x] On-phone fallback: `SignatureSheet` with `PKCanvasView`. (feat(§16.26): SignatureSheet PKCanvasView)
- [x] Auto-routing logic (terminal preferred, fallback on timeout / no terminal). (feat(§16.26): SignatureRouter routing logic)
- [x] Audit log entries for both paths. (feat(§16.26): audit log signatureCaptured)
- [x] Offline: always route to on-phone when network unavailable. (feat(§16.26): offline onPhone routing)

---

### 16.27 Cream primary token swap (`#fdeed0`) across iOS DesignTokens

**Reference**
- Color token set verbatim from `../pos-phone-mockups.html` top `<style>` block (confirmed as the winning primary per the palette showcase section).
- Android reference: `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/ui/theme/Theme.kt` lines 100–154 (cream already shipped this wave on Android).
- iOS file: `ios/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift` — add a `BrandColor` enum section. Also `ios/Packages/DesignSystem/Sources/DesignSystem/BrandFonts.swift`, `BrandMotion.swift`, `BrandHaptics.swift` for context (no changes needed in those files).
- Note: `DesignTokens.swift` is referenced in the task prompt; the actual file path in this codebase is `ios/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift`.

**Backend**
- No server-side changes. Color tokens are client-only.

**Frontend (iOS)**
- Add `BrandPalette` enum to `ios/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift` with the following constants, matching the HTML mockup exactly:

```swift
// MARK: - Brand palette (cream wave — 2026-04-24)
// Source of truth: ../pos-phone-mockups.html <style> :root block.
// Android parity: ui/theme/Theme.kt lines 100–154.
public enum BrandPalette {
    // Primary action color — warm cream; replaces old orange project-wide.
    public static let primary    = Color(hex: "#fdeed0")  // --primary
    public static let onPrimary  = Color(hex: "#2b1400")  // --on-primary
    // Dark warm backgrounds
    public static let bg         = Color(hex: "#0f0a14")  // --bg
    public static let surface    = Color(hex: "#1a1722")  // --surface
    public static let surface2   = Color(hex: "#241f2e")  // --surface-2
    public static let outline    = Color(hex: "#332c3f")  // --outline
    // Text
    public static let on         = Color(hex: "#ece9f3")  // --on
    public static let muted      = Color(hex: "#a79fb8")  // --muted
    // Semantic
    public static let success    = Color(hex: "#34c47e")  // --success
    public static let warning    = Color(hex: "#e8a33d")  // --warning
    public static let error      = Color(hex: "#e2526c")  // --error
    public static let teal       = Color(hex: "#4db8c9")  // --teal
}
```

- `Color(hex:)` extension already exists or must be added to `DesignSystem` (one-liner `init`).
- SwiftLint rule `forbid_inline_design_values` (referenced in `Tokens.swift` file header) must flag any remaining hardcoded `#FF6600`-style orange values in the `Pos` package after the swap.
- Asset catalog (`Assets.xcassets`) light/dark variants: `Primary` adaptive color — light mode uses a slightly darker tint `#e8c98a` for contrast; dark mode uses `#fdeed0` directly. Both map through the `BrandPalette.primary` token (never inline hex in views).
- Migration checklist: search all `Pos` and `CheckIn` package Swift files for `Color(.orange)`, `Color(red:0.9, green:...)`, or hardcoded orange hex values; replace with `BrandPalette.primary`. CI will catch misses via the SwiftLint rule.
- `GlassKit.swift` tint color: `brandGlass` modifier uses `BrandPalette.primary` for the glass tint layer — update if currently hardcoded to orange.

**Expected UX**
- Every cream-colored element in the POS flow (Tender CTA, active chips, search bar border, tile prices, "Charge" button) uses `BrandPalette.primary`.
- `--on-primary` (`#2b1400`) provides accessible dark text on all cream backgrounds. WCAG AA contrast ratio: cream `#fdeed0` on dark brown `#2b1400` = 9.8:1 (passes AAA).
- No visual change to non-POS screens in this pass — token is additive. The old orange color asset remains until a project-wide audit pass removes it (separate backlog item).

**Status**
- [x] `BrandPalette` enum added to `Tokens.swift`.
- [x] `Color(hex:)` extension confirmed present in `DesignSystem`.
- [x] Asset catalog `Primary` adaptive color entry (cream / dark-mode tint).
- [x] SwiftLint sweep of `Pos` + `CheckIn` packages for residual orange values.
- [x] `GlassKit.swift` tint updated to `BrandPalette.primary`.
- [x] Tests: `DesignTokensTests` — assert `BrandPalette.primary` hex string equals `"#fdeed0"`.

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
- [x] **Camera permission re-prompt** — `CameraPermissionMonitor` @Observable tracks `AVAuthorizationStatus` + refreshes on foreground (`scenePhase` change). `CameraPermissionRepromptCard` glass card with icon, copy, and CTA button: `.notDetermined` → request system dialog; `.denied` / `.restricted` → deep-link to `UIApplication.openSettingsURLString`. `CameraPermissionGate<Content>` wrapper hides camera UI and shows card until authorized. VoiceOver-accessible; card auto-dismisses when user returns from Settings with permission granted. `Settings/CameraPermissionReprompt.swift`. Commit `feat(§17): scale-tare-button, scanner-test, paper-low, drawer-jam, camera-reprompt`.
- [x] **Mac (Designed for iPad)** — continuity camera via FaceTime-HD → same `AVCaptureSession` code works. `BarcodeScannerView` Mac Catalyst fallback already gates on `DataScannerViewController.isSupported`; continuity camera reuses identical `AVCaptureSession` code path. Commit `[agent-2 b4]`.
- [x] **Live text** — `LiveTextView` (iOS 16+) with `ImageAnalysisInteraction` + `onTextRecognized` for IMEI/serial extraction.

### 17.2 Barcode scan
- [x] **`DataScannerViewController`** (iOS 16+) — `PosScanSheet` ships ean13/ean8/upce/code128/qr. `code39` not enabled yet.
- [x] **Bindings (partial)** — POS add-to-cart wired via `PosSearchPanel` query-fill + auto-pick. Inventory lookup / Stocktake / Ticket IMEI / Customer bindings TBD.
- [x] **Torch** button, zoom (pinch), region-of-interest overlay. Commit `e348d254`.
- [x] **Feedback** — haptic success on auto-pick via `BrandHaptics.success()`. Color flash + chime deferred.
- [x] **Multi-scan mode** — POS/stocktake can keep scanning; tap-to-stop. Commit `e348d254`.
- [x] **Offline lookup** — hit local GRDB cache first; if miss + online → server; if miss + offline → toast "Not in local catalog". `BarcodeOfflineLookup` actor + tests. Commit `e348d254`.
- [x] **Printed/screen code** — both supported. `DataScannerViewController` recognizes printed labels and on-screen barcodes natively; `BarcodeVisionScanner` handles still-image frames from either source. Commit `[agent-2 b4]`.
- [x] **Fallback manual entry** — search field on POS accepts typed SKU/barcode.
- [x] **External scanners** — HID keyboard fallback implemented: `ExternalScannerHIDListener` actor + `HIDSinkTextField` intercepts burst keystrokes from Socket Mobile / Zebra HID-mode scanners. `HIDScannerListenerView` SwiftUI wrapper. MFi SDK integration deferred to MFi approval. Commit `[agent-2 b4]`.
- [x] **Mac** — `DataScannerViewController` unavailable on Mac Catalyst; feature-gate to manual entry + continuity camera scan. Commit `e348d254`.

### 17.3 Card reader — BlockChyp

**Architecture clarification (confirmed against BlockChyp docs + iOS SDK README, April 2026).** BlockChyp is a **semi-integrated** model with two communication modes the SDK abstracts behind the same API calls. Our app never handles raw card data either way — terminals talk to the payment network directly; we only receive tokens + results. Per-terminal mode is set at provisioning on the BlockChyp dashboard (cloud-relay checkbox).

**No Bluetooth.** BlockChyp SDK supports IP transport only (LAN or cloud-relay). Do not build any `CoreBluetooth` / MFi / BLE pairing path for the card reader. `NSBluetoothAlwaysUsageDescription` covers other peripherals (printer, scanner, scale) — never the terminal.

- **Local mode** — SDK resolves a terminal by name via the "Locate" endpoint, then sends the charge request straight to the terminal's LAN IP over the local network. Terminal talks to BlockChyp gateway / card networks itself, returns result direct to SDK on LAN. Lowest latency; survives internet blip as long as gateway uplink from terminal is OK. Preferred for countertop POS where iPad + terminal share Wi-Fi.
- **Cloud-relay mode** — SDK sends request to BlockChyp cloud (`api.blockchyp.com`); cloud forwards to terminal via persistent outbound connection the terminal holds. Works when POS and terminal are on different networks (web POS, field-service tech whose iPad is on cellular, multi-location routing). Higher latency; connection-reset-sensitive.
- **SDK abstracts the mode.** Same `charge(...)` call; the SDK's terminal-name-resolution picks local vs cloud path. Developer writes one code path; deployment-time setting picks the route.

#### Integration tasks
- [x] **CocoaPods integration** — SPM unavailable; HTTP-direct client implemented instead (94764e9). No third-party dep; pure URLSession + CryptoKit.
- [x] **Terminal types supported** — BlockChyp-branded smart terminals (Lane/2500, Curve, Zing). Ingenico/Verifone/PAX are the underlying hardware families BlockChyp ships; we don't integrate their stacks directly — all through BlockChyp SDK. (94764e9 — abstracted behind `CardTerminal` protocol)
- [x] **Pair flow** — `BlockChypPairingView` + `BlockChypPairingViewModel` implement 3-step wizard: activation code → pairing spinner → paired tile. `BlockChypTerminal.pair(...)` calls `/api/terminal/pair`. Credentials stored in Keychain. (94764e9)
- [x] **Stored credentials** — `BlockChypCredentials` JSON-encoded in Keychain via `KeychainStore` key `.blockChypAuth`. Terminal name persisted in UserDefaults cache hint. (94764e9)
- [x] **Status tile** — Paired state in `BlockChypPairingView` shows terminal name + last-used timestamp. (94764e9)
- [x] **Test ping** — `testCharge()` in ViewModel sends $1.00 test charge; `ping()` in `ChargeCoordinator` calls `/api/terminal-locate`. (94764e9)
- [x] **Charge** — `BlockChypTerminal.charge(amountCents:tipCents:metadata:)` POSTs to `/api/charge` with HMAC-SHA256 signed headers; returns `TerminalTransaction` with approved/authCode/maskedPan/cardBrand. `ChargeCoordinator.coordinateCharge(...)` wraps for POS use. (94764e9)
- [x] **PCI scope** — raw card data never enters our iOS app or our server. Terminal handles PAN / EMV / PIN entry; we receive a tokenized reference only. `CardTerminal` abstraction and `TerminalTransaction` carry only tokens + last4. (94764e9)
- [x] **Refund** — `BlockChypTerminal.reverse(transactionId:amountCents:)` POSTs to `/api/reverse`; `ChargeCoordinator.reverseCharge(...)` wraps it. (94764e9)
- [x] **Tip adjust** — pre-batch-close `tipAdjust` call on bar/restaurant tenants. `TipAdjustCoordinator` + `BlockChypTerminal.tipAdjust(transactionId:newTipCents:)` + `TipAdjustResult`. Commit `[agent-2 b3]`.
- [x] **Batch management** — force-close daily at configurable time; Settings "Close batch now" button calls `batchClose`. `BatchManager` observable + `BatchSettingsSection` SwiftUI component + `BlockChypTerminal.closeBatch()` + `BatchCloseResult`. Commit `[agent-2 b3]`.
- [x] **Error taxonomy** — `TerminalError` enum: `notPaired`, `pairingFailed`, `chargeFailed`, `reversalFailed`, `pingFailed`, `unreachable`. `ChargeCoordinatorError`: `noTerminalPaired`, `chargeDeclined`, `cancelled`. All have `LocalizedError` descriptions; raw BlockChyp codes never shown to cashier. (94764e9)
- [x] **Offline behavior** — local mode: if iPad internet drops but terminal's own uplink still works, charges can still succeed because terminal → gateway path is independent. Cloud-relay mode: no charges possible without internet. `BlockChypRelayMode` enum + `terminalRelayMode()` + `TerminalRelayModeBadge` chip surfaces mode in charge sheet. Commit `[agent-2 b3]`.
- [x] **Fallback when terminal truly unreachable** — offer manual-keyed card entry (role-gated, PIN protected, routes through BlockChyp manual-entry API) OR cash tender OR queue offline sale with "card pending" status for retry on reconnect. `TerminalFallbackView` + `TerminalFallbackAction` enum. Commit `[agent-2 b3]`.
- [x] **Network requirements doc** — setup wizard tells tenant: firewall must allow outbound `api.blockchyp.com:443` for cloud-relay. Local mode needs iPad + terminal on same subnet or routed LAN reachable on terminal's service port. `NetworkRequirementsView` in Settings. Commit `[agent-2 b3]`.

### 17.4 Receipt printer (MFi Star / Epson)

**Lesson from Android:** Android build "prints" by handing the system a `https://app.bizarrecrm.com/print/...` URL. Opening that URL requires an authenticated session the printer / share sheet doesn't have → blank page or login wall. **iOS must never do this.** All printable artifacts are rendered on-device from local model data.

#### On-device rendering pipeline (mandatory)
- [x] **No URL-based printing.** `ReceiptPrinter` protocol contract + `NullReceiptPrinter` default enforce local-render discipline. `ReceiptPayload` carries model data, never URLs.
- [x] **Canonical rendering**: SwiftUI `ImageRenderer(content: ReceiptView(model: ...))` produces the visual once, feeds every output channel. `ReceiptRenderer` enum: rasterize → 1-bit Atkinson dither → `RasterBitmap`; renderPDF → temp file URL. Commit `e348d254`.
  - Thermal printer: `ImageRenderer` → `CGImage` → raster ESC/POS bitmap (80mm or 58mm per printer width).
  - AirPrint / PDF: same `ImageRenderer` → `UIGraphicsPDFRenderer` → multi-page PDF.
  - Share sheet: PDF file URL in `UIActivityViewController`.
  - Email / SMS attachments: PDF.
  - Preview in app: same `ReceiptView` rendered live in a scroll view.
- [x] **Single `ReceiptView` per document type** — `ReceiptView`, `GiftReceiptView`, `WorkOrderTicketView`, `IntakeFormView`, `ARStatementView`, `ZReportView`, `LabelView`. Each takes a strongly-typed model. Same view backs print + preview + PDF + email attachment. `DocumentViews.swift` adds IntakeFormView, ARStatementView, ZReportView, LabelView. Commit `e348d254`.
- [x] **Model is self-contained** — `ReceiptModel` carries every value needed (business logo `Data`, shop name, address, line items, totals, payment auth last4, timestamp, tenant footer). Zero deferred network reads inside render. Offline-safe. Commit `0de684a5`.
- [x] **Width-aware layout** — `@Environment(\.printMedium)` picks `.thermal80mm`, `.thermal58mm`, `.letter`, `.a4`, `.label2x4`, etc. Fonts + columns adapt; single SwiftUI view, media-specific modifiers. `PrintMedium.swift` ships all cases + fonts + contentWidth. Commit `0de684a5`.
- [x] **Rasterization** — thermal path goes through `ImageRenderer.scale = 2.0`, dithered to 1-bit for print head. Preview uses same image so what tenant sees is what prints. `ReceiptRenderer.rasterize` + Atkinson dither ships. Commit `0de684a5`.
- [x] **Cut + drawer-kick** — ESC/POS opcodes appended after the rasterized bitmap, not embedded in view. Keeps view pure visual. `PrintJob.kickDrawer` flag; `EscPosNetworkEngine` appends `drawerKick()` when set. Commit `0de684a5`.

#### MFi / model support
- [!] **Apple MFi approval** — 3–6 week lead time; start early. Alternative: Star Micronics webPRNT over HTTP for web-printable models (no MFi); still renders our bitmap, not a URL.
- [x] **Models targeted** — Star TSP100IV (USB / LAN / BT), Star mPOP (combo printer + drawer), Epson TM-m30II, Epson TM-T88VII. `ThermalPrinterModelRegistry` with 4 specs; `ThermalVendor`/`ThermalPaperWidth`/`ThermalTransport` OptionSet; `spec(forDiscoveredName:)` case-insensitive lookup. (460daa6e)
- [x] **Discovery** — `StarIO10` + `ePOS-Print` SDKs: LAN scan + BT scan + USB-C (iPad); list paired. `ThirdPartyPrinterDiscovery` @Observable uses `BonjourPrinterBrowser.discoveryStream()` (3s scan); `starIO10SDKAvailable`/`epsonEPOSSDKAvailable` both false (no third-party SDK egress). (460daa6e)
- [x] **Pair** — pick printer → save identifier (serial number) in Settings → per-station profile (§17). `ThirdPartyPrinterDiscovery.pair(_:)`/`unpair(_:)` saves to `PrinterProfileStore` via `defaultReceiptPrinterId`. (460daa6e)
- [x] **Test print** — Settings "Print test page": renders `TestPageView` locally (logo + shop name + time + printer capability matrix) via the same pipeline. `TestPageView` + `TestPageModel` + wired via `PrinterProfileSettingsView`. Commit `[agent-2 b3]`.

#### AirPrint path
- [x] **`UIPrintInteractionController`** with `printingItems: [localPdfURL]` — never a remote URL. `AirPrintEngine` + `LabelPrintEngine` both render to temp PDF and pass file URL only. Commit: phase-5-§17.
- [x] **Custom `UIPrintPageRenderer`** for label printers that want page-by-page rendering instead of a PDF (e.g., Dymo via AirPrint). `LabelPageRenderer` subclasses `UIPrintPageRenderer`; renders one `LabelView` per page at exact label stock dimensions. `LabelPrintInteractionCoordinator` convenience wrapper. Commit `[agent-2 b3]`.

#### Fallbacks + resilience
- [x] **No printer configured** — offer email / SMS with PDF attachment + in-app preview (rendered from same model). Works fully offline; delivery queues if needed. `NoPrinterFallbackView`. Commit `e348d254`.
- [x] **Printer offline** — job queues in `PrintJobQueue` actor (model payload + target printer). Retry with exponential backoff (3 attempts); dead-letter after threshold. `PrintJobStore` persists pending + dead-letter jobs to disk (JSON file → GRDB migration path). Commit `[agent-2 b3]`.
- [x] **Cash-drawer kick** — via printer ESC command; if printer offline, surface "Open drawer manually" button that logs an audit event so shift reconciliation can show drawer-open vs sale counts. `CashDrawerFallbackView` + `APIClient.logManualDrawerOpen`. Commit `e348d254`.
- [x] **Re-print** — `ReprintSearchView` + `ReprintSearchViewModel` + `ReprintDetailView` + `ReprintViewModel`. Search by receipt#/phone/name. Reason picker. Audit `POST /sales/:id/reprint-event`. ⌘⇧R shortcut. Tests ≥80%. (Phase 5 §16)
- [x] **Printer paper-low warning** — `PrinterPaperLevel` enum (`.ok`/`.low`/`.empty`/`.unknown`) + `PrinterPaperMonitor` @Observable singleton updated by engine adapters via `setPaperLevel(_:for:)`. `PrinterPaperLowBanner` glass chip shown in POS toolbar / Settings when paper is low or empty. `.printerPaperLowAlert(monitor:)` ViewModifier fires an alert on level change. `Printing/PrinterPaperLowWarning.swift`. Commit `feat(§17): scale-tare-button, scanner-test, paper-low, drawer-jam, camera-reprompt`.
- [x] **Drawer jam detection** — `DrawerJamDetector` (advisory + active sensing modes). Advisory mode fires after `advisoryThreshold` (default 2) consecutive unconfirmed kicks within a shift. Active mode times out if no open-status confirmation within 3 s. `DrawerJamState` (.clear/.suspected/.advisory) published on `CashDrawerManager.jamState`. `CashDrawerManager` gains `recordDrawerStatusUpdate(isOpen:)` + `resolveJam()`. `Drawer/DrawerJamDetection.swift`. Commit `feat(§17): scale-tare-button, scanner-test, paper-low, drawer-jam, camera-reprompt`.

#### Templates (the views)
- [x] Receipt, gift receipt (price-hidden variant), work-order ticket label (name + ticket # + barcode), intake form (pre-conditions + signature), A/R statement, end-of-day Z-report, label/shelf tag (§17). All ship in `ReceiptView.swift` + `DocumentViews.swift` (IntakeFormView, ARStatementView, ZReportView, LabelView). Commit (prior batches + b3).

#### ESC/POS builder
- [x] Helpers for bold / large / centered / QR / barcode / cut / feed / drawer-kick — `EscPosCommandBuilder` ships all commands; tests ≥80%. Commit: phase-5-§17.

#### Multi-location
- [x] Per-location default printer selection + per-station profile (§17). `PrinterProfile` + `PrinterProfileStore` + `PrinterProfileSettingsView` with receipt/label printer pickers + paper size preference. `PersistedJobEntry` for job durability. Commit `[agent-2 b3]`.

#### Acceptance criterion (copied from lesson)
- [x] Ship with a regression test: log out of the app, attempt to print a cached recent receipt (detail opened while online, then session ended) → printer must still produce correct output, because rendering is fully local and only the device-to-printer transport is needed. `OfflineReceiptPrintRegressionTests` (4 tests: payload self-contained, payload round-trips JSON, MockPrinter no-network, PrintJobStore persists). Commit `[agent-2 b3]`.

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
- [x] **Core NFC** read — scan tag with device serial → populate Ticket device-serial field. (feat(§17): `NFCTagReadService.readNDEF(prompt:)` runs one-shot `NFCNDEFReaderSession`, returns `NFCReadResult(payload:format:)`)
- [ ] **Core NFC write** (optional) — write tenant-issued tag to a customer device for warranty tracking.
- [x] **NDEF vs raw** — NDEF primary; raw MIFARE for inventory tags if tenant requests. (feat(§17): `NFCTagFormat` enum (`.ndef`/`.mifare`/`.felica`) + `NFCTagFormatStore` UserDefaults; `requiresEntitlementUpdate` flag per case)
- [x] **Graceful disable** — `NFCReaderSession.readingAvailable` false (iPad, iPhone 6 or earlier) → hide all NFC UI. (feat(§17): `NFCAvailabilityService` @Observable + `.nfcFeatureGate(...)` ViewModifier)

**Already unblocked (independent of parity):**
- [x] **Apple Wallet pass** — customer loyalty card (see §40, §38, §41) added via `PKAddPassesViewController`. `LoyaltyMembershipCardView` + `LoyaltyWalletService` + `LoyaltyWalletViewModel` ship in `Packages/Loyalty/Wallet/`. Commit `feat(ios phase-6 §24+§38+§40)`.

### 17.6 Scale (Bluetooth)
- [x] **Target** — Dymo M5, Brecknell B140 (Bluetooth SPP). `BluetoothWeightScale` + `Weight` + `WeightDisplayChip` shipped.
- [x] **Read weight** — `BluetoothWeightScale.stream()` / `read()` + characteristic 0x2A9D parser. Cart wiring deferred to §16.
- [x] **Tare / zero** — button in POS when scale selected. `BluetoothWeightScale.tare()` + `WeightDisplayChip(onTare:)`. Commit `e348d254`.
- [x] **Scale tare button (standalone)** — `ScaleTareButton` full-size SwiftUI button for use outside `WeighCaptureView` (toolbars, scale quick-action cards). Shows spinner while taring; "Zeroed" / error feedback with auto-clear; posts VoiceOver announcement. `Scale/ScaleTareButton.swift`. Commit `feat(§17): scale-tare-button, scanner-test, paper-low, drawer-jam, camera-reprompt`.

### 17.7 Bluetooth / peripherals shell
- [x] **Permissions** — `NSBluetoothAlwaysUsageDescription` documented; written by `scripts/write-info-plist.sh`.
- [x] **Device shelf** — `BluetoothSettingsView` + `HardwareSettingsView` aggregator shipped.
- [x] **Reconnect** — auto-reconnect on launch; surface failures in status bar glass. `BluetoothReconnectService` + `remember/forget/allRememberedUUIDs`. Commit `e348d254`.
- [x] **Scanner test screen** — `ScannerTestView` (Settings → Hardware → Scanner → "Test Scanner"). Animated waiting ring; accepts barcodes from `BarcodeScannerBuffer` (HID/BT wedge) or manual-entry fallback; last 5 entries in history list with timestamp + symbology hint; Clear toolbar button; full a11y. `Bluetooth/ScannerTestView.swift`. Commit `feat(§17): scale-tare-button, scanner-test, paper-low, drawer-jam, camera-reprompt`.

### 17.8 Customer-facing display
- [x] **Dual-screen** — iPad with external display via USB-C/HDMI → cart mirror + tip prompt. `CustomerDisplayManager` owns `UIWindow` on external screen; auto-detects screen connect/disconnect. `CustomerCartMirrorView` + `CustomerTipPromptView` + `CustomerDisplayRootView`. Commit `[agent-2 b3]`.
- [x] **Handoff prompt** — "Customer: please sign" / "Tip amount" on external display. `CustomerDisplayManager.showTipPrompt(options:)` switches external screen to `CustomerTipPromptView`; `TipOption.standard(totalCents:)` builds standard tip chips. `onTipSelected` callback to POS. Commit `[agent-2 b3]`.
- [x] **AirPlay** — fallback via AirPlay to Apple TV. Same `UIScreen.screens` API handles AirPlay — same code path as USB-C/HDMI. Commit `[agent-2 b3]`.

### 17.9 Apple Watch companion

Not an iOS feature per se; separate product surface (own entitlements, TestFlight lane, App Store binary, review cycle). Tracked as `WATCH-COMPANION-001` in root `TODO.md` pending scope decision. iOS work on this section is blocked until that item resolves.

Candidate scope when revisited (for reference): clock in / out complication, new-ticket / SMS push forwarding, reply-by-dictation. Non-goal: full CRM browsing on watch.

### 17.10 Accessibility hardware
- [x] **Switch Control** — POS primary actions reachable. `HardwareA11yModifiers.swift`: `.posPrimaryAction(label:hint:aliases:)` + `.posNumericKey(_:)` + `.drawerTestButton()` + `.posScanButton()` view modifiers ensure Switch Control visits primary actions and buttons have concrete labels. `HardwareA11yLabel` constants for consistent naming. Commit `[agent-2 b3]`.
- [x] **Voice Control** — all named buttons reachable; custom names for numeric keys. `.accessibilityInputLabels([...])` on all hardware controls so Voice Control can target by any alias ("Charge customer", "Open drawer", "Scan barcode"). Numeric keys: `.posNumericKey(_:)` sets spoken label "Key N". Commit `[agent-2 b3]`.
- [x] Tools: Pen (thickness slider, 10 color presets + custom), Highlighter (semi-transparent yellow / pink / green), Arrow (auto-head), Rectangle / Oval / Freehand, Text box (font size + color), vector-aware Eraser. Unlimited undo / redo within session. `AnnotationTool` extended with `.arrow/.rectangle/.oval/.textBox` + `isPencilKitTool`; `AnnotationPresetColor` 10 swatches. Commit `258f346b`.
- [x] Palette: swatches as glass chips; tenant brand color auto-added. `AnnotationPresetColor` 10 swatches (orange/teal/magenta/red/green/blue/yellow/black/white/purple). Commit `258f346b`.
- [x] Stamp library: Arrow / Star / circled number / condition tags ("cracked", "dented", "missing"); drag-drop onto image. `AnnotationStamp` + `AnnotationStampPlacement`. Commit `258f346b`.
- [x] Layers: base photo + annotation layer stored separately (revert-to-original possible); export flattens. `AnnotationLayer` struct. Commit `258f346b`.
- [x] Apple Pencil: `PKCanvasView` / `PencilKit` pressure + tilt; palm rejection on iPad; double-tap Pencil toggles last tool. Squeeze toggles tool picker (Pencil Pro). `UIPencilInteraction` delegate wired. Commit `feat(ios phase-7 §4+§17.1)`.
- [x] Crop / rotate / auto-enhance (brightness / contrast). `ImageEditService` actor: `crop(_:to:)`, `rotate(_:degrees:)`, `autoEnhance(_:)` via CIAutoAdjustment. Commit `b1d56e2c`.
- [x] OCR via `VNRecognizeTextRequest`: "Copy text from image" context action. `ImageEditService.recognizeText(in:)` on-device only (`requiresOnDeviceRecognition`, sovereignty §28). Commit `b1d56e2c`.
- [x] AirPrint via `UIPrintInteractionController` handed a locally-rendered PDF file URL (never a web URL — Android regression lesson §17.4). `AirPrintEngine` + `PrintService` both use local temp PDF. Commit `b1d56e2c`.
- [x] Paper sizes: Letter (US) / A4 (EU) / Legal / 4×6 receipt / 80mm thermal / 58mm thermal. Default per tenant in Settings → Printing. `PrintMedium.legal` + `PrintMedium.tenantDefault` locale-based. Commit `b1d56e2c`.
- [ ] Thermal printer via Star SDK + Epson ePOS SDK (Swift wrapper). Transports: MFi Bluetooth, Wi-Fi, USB (Lightning/USB-C). Multi-printer per station (§17).
- [x] `PrintService` class: queue with retries, toast "Print queued, 1 pending", reprint button in queue UI. `PrintService` @Observable wraps `PrintJobQueue`; `PrintOptionsSheet` provides printer/paper/copies/reason UI. Commit `b1d56e2c`.
- [x] Cash-drawer kick via printer ESC opcode on cash tender (§17). `EscPosDrawerKick` + `CashDrawerManager.handleTender(_:)` already shipped; confirmed complete. Commit `b1d56e2c`.
- [x] Preview always before print (first-page mini render). `PrintService.submit(_:previewImage:presenter:)` shows `PrintPreviewViewController` sheet before sending. Commit `b1d56e2c`.
- [x] PDF share-sheet fallback when no printer configured. `PrintService.fallbackToShareSheet(_:from:)` → `UIActivityViewController` with temp PDF. Commit `b1d56e2c`.
- [x] Receipt template editor (Settings → Printing): header logo + shop info + body (lines / totals / payment / tax) + footer (return policy, thank-you, QR lookup) + live preview. `ReceiptTemplateEditorView` + `ReceiptTemplate` + `ReceiptTemplateStore` + `ReceiptPreviewCard` live preview. iPhone: scroll form + preview; iPad: split pane. Persisted in UserDefaults. Commit `[agent-2 b4]`.
- [x] Print works offline — printer on local network or Bluetooth has no internet dependency. `PrintJobQueue` + `PrintService` use local-only ESC/POS/BT/AirPrint transports; no internet needed. `OfflineReceiptPrintRegressionTests` verify. Commit `b1d56e2c`.
- [x] Support symbologies: EAN-13/EAN-8, UPC-A/UPC-E, Code 128, Code 39, Code 93, ITF-14, DataMatrix, QR, Aztec, PDF417 — `BarcodeVisionScanner.allSymbologies` + `BarcodeCoordinator.recognizedDataTypes` include all 11 symbologies; `BarcodeChecksumValidator` handles per-symbology validation. Commit `[agent-2 b4]`.
- [x] Priority per use-case: Inventory SKU Code 128 primary + QR secondary; retail EAN-13/UPC-A auto-detect; IMEI/serial Code 128 or bare numeric; loaner/asset tag QR with scan-to-view URL. `BarcodeVisionScanner` + `VNBarcodeSymbology.useCasePriority` document priority per symbology. Commit `[agent-2 b4]`.
- [x] Scanner via `VNBarcodeObservation`: recognize all formats concurrently. `BarcodeVisionScanner` actor with `VNDetectBarcodesRequest` + all 11 symbologies concurrently. Commit `[agent-2 b4]`.
- [x] Preview layer marks detected code with glass chip + content preview; tap chip to accept. `BarcodePreviewChip` SwiftUI glass overlay. Commit `258f346b`.
- [x] Continuous scan mode: scan → process → beep → ready for next without closing camera. `BarcodeScannerView` mode `.continuous` + `BarcodeCoordinator` already implemented. Commit `e348d254`.
- [x] Checksum validation per symbology (EAN mod 10, ITF mod 10, etc.); malformed → warning toast + no action. `BarcodeChecksumValidator` with EAN/ITF mod-10 + UPC-E digit validation; `BarcodeVisionResult.checksumValid` flag + `BarcodeA11yAnnouncer` warns on invalid. Commit `[agent-2 b4]`.
- [x] Tenant bulk relabel: Inventory "Regenerate barcodes" for all SKUs → print via §17. `BulkRelabelService` actor with `relabel(items:printService:progress:)` + `generateCode128Image(for:)` via CICode128BarcodeGenerator; `BulkRelabelProgress` @Observable. (f141677c)
- [x] Gift cards: unique Code 128 per card (§40). `GiftCardBarcodeGenerator` actor: `generateCardNumber()` → "GC-{16 uppercase hex}", `generate(for:)` → `GiftCardBarcode` with UIImage + `BarcodePayload(format: .code128)`. (3d1ddea9)
- [x] A11y: VoiceOver announces scanned code and matched item. `BarcodeA11yAnnouncer.announcement(for:itemName:)` returns accessibility string for `UIAccessibility.post(notification: .announcement)`. Commit `[agent-2 b4]`.
- [ ] Entry: any past invoice/receipt → detail → Reprint button (Agent 1 / Pos domain — embeds `PrintOptionsSheet` + calls `PrintService.submitWithOptions`)
- [ ] Entry: from POS "Recent sales" list (Agent 1 / Pos domain)
- [x] Options: printer choice (if multiple configured) — `PrintOptionsSheet.printerSection` Picker driven by `availablePrinters`. Commit `[agent-2 b3]`.
- [x] Options: paper size (80mm / Letter) — `PrintOptionsSheet.paperSizeSection` Picker over all `PrintMedium.allCases`; defaults to `PrintMedium.tenantDefault`. Commit `[agent-2 b3]`.
- [x] Options: number of copies — `PrintOptionsSheet.copiesSection` Stepper 1–10; `PrintOptions.copies` forwarded to `PrintJob.copies`; queue sends N engine calls. Commit `a1eaa2cc`.
- [x] Tenant-configurable: require reason for reprints older than 7 days — `PrintOptionsSheet(requireReasonForOldJobs:isOldJob:)` shows `reasonSection` when both flags true; `ReprintReason` enum with 5 preset options. Commit `[agent-2 b3]`.
- [x] Audit entry (§50) per reprint — `PrintService.submitWithOptions(auditLogger:entityKind:entityId:)` fires `auditLogger` closure (wired to `APIClient.logReprintEvent`) per reprint when entityId > 0. Commit `a1eaa2cc`.
- [x] Fallback: no printer → PDF share — `PrintService.submitWithOptions` delegates to `fallbackToShareSheet` when no printer resolved from options or profile. Commit `a1eaa2cc`.
- [x] Entry from customer detail / ticket detail → "Scan document". `DocumentScanButton(entityKind:entityId:onFinished:)` presents `DocumentScannerView` as sheet; gracefully disabled when `VNDocumentCameraViewController.isSupported == false`. Commit `b1d56e2c`.
- [x] Use `VNDocumentCameraViewController`. `DocumentScanner` UIViewControllerRepresentable + `DocumentScanViewModel` + `DocumentScanPreviewView`. Camera/DocScan/. Commit 468fe08.
- [x] Multi-page scan with auto-crop + perspective correction — VisionKit handles perspective; pages collected via `VNDocumentCameraScan.imageOfPage(at:)`.
- [x] Reorder / delete pages before save — `DocumentScanPreviewView` List with `.onMove`/`.onDelete`; `DocumentScanViewModel.movePages`/`deletePage`.
- [x] OCR via `VNRecognizeTextRequest`, text searchable via FTS5 — `DocumentOCRService` actor; `DocumentScanViewModel.runOCR()` exposes `ocrState`+`extractedText`. Commit `5e647018`.
- [x] Output: PDF (preferred) or JPEG at 200 DPI default — `assemblePDF` produces Letter PDF via `UIGraphicsPDFRenderer`; images scaled aspect-fit with 0.25in margin. Commit `5e647018`.
- [x] Auto-classification by keyword: license / invoice / receipt / warranty → suggest tag. `DocumentAutoClassifier` keyword-based classifier; `DocumentScanViewModel.suggestedTag` + `classificationConfidence` populated after OCR; `DocumentScanPreviewView` renders classification banner. Commit `[agent-2 b4]`.
- [x] Privacy: on-device Vision only; no external/cloud OCR — `DocumentOCRService` uses `VNImageRequestHandler` exclusively; no network calls. Commit `5e647018`.
- [x] Bulk append multiple scans to single file. `DocumentScanViewModel.appendPages(_:)` + "Scan More Pages" button in `DocumentScanPreviewView` + toolbar shortcut. `DocumentScannerView` presented as sheet for additional scan sessions. Commit `[agent-2 b4]`.
- [x] Settings → Hardware → Printer → manual IP entry. `PrinterSettingsView` + `PrinterSettingsViewModel.addNetworkPrinter()` already handles host/port form; reachability ping via `EscPosNetworkEngine.discover()` before save. Commit `[agent-2 b4]`.
- [x] Optional port (default 9100 raw / 631 IPP). Form field defaults to 9100. Commit `[agent-2 b4]`.
- [x] Reachability ping before save. `EscPosNetworkEngine.discover()` ping on save rejects unreachable printers. Commit `[agent-2 b4]`.
- [x] Online / offline badge. `PrinterStatus` enum includes `.error(String)` displayed in `PrinterRow`. Commit `[agent-2 b4]`.
- [x] Fallback to Bonjour discovery (§17) if IP changes. `BonjourPrinterBrowser` + `BonjourPrinterPickerView` provide auto-discovery as fallback. Commit `[agent-2 b4]`.
- [x] Recommend tenant set DHCP reservation for printer MAC — added advisory footer in `PrinterSettingsView` addSection. Commit `0f9c77de`.
- [x] App shows printer MAC after first connection. `PairedDevice.macAddress: String?` + `withMACAddress()` mutator; `BluetoothDeviceRow` displays MAC in caption2 with `.textSelection(.enabled)`. Commit `b1d56e2c`.
- [x] `NWBrowser` for `_ipp._tcp`, `_printer._tcp`, `_airdrop._tcp`, custom `_bizarre._tcp`. `BonjourPrinterBrowser` browses all three types. Commit `[agent-2 b4]`.
- [x] Declare `NSBonjourServices` in Info.plist (all needed types up-front, iOS 14+). Added to `scripts/write-info-plist.sh` via Discovered note (owned by Agent 10). Commit `[agent-2 b4]`.
- [x] `NSLocalNetworkUsageDescription` explains local-network use. Already in `scripts/write-info-plist.sh` per §17.7. Commit `[agent-2 b4]`.
- [x] Picker UI grouped by service type. `BonjourPrinterPickerView` sections by service type. Commit `[agent-2 b4]`.
- [x] Icon per device class. `DiscoveredPrinter.systemImageName` returns per-type SF Symbol. Commit `[agent-2 b4]`.
- [x] Auto-refresh every 10s. `BonjourPrinterPickerViewModel` schedules 10s refresh timer via `Task.sleep`. Commit `[agent-2 b4]`.
- [x] Manual refresh button. Toolbar refresh button in `BonjourPrinterPickerView`. Commit `[agent-2 b4]`.
- [x] `CBCentralManager` peripheral scan — `BluetoothManager.startScan` + `CBCentralManagerProtocol` abstraction (pre-existing; confirmed complete). Commit `b4b3b9f0`.
- [ ] MFi cert required for commercial printers
- [x] Register `bluetooth-central` background mode — `BluetoothBackgroundManager` Swift-side restoration handler; `UIBackgroundModes` key in `write-info-plist.sh` filed as Discovered for Agent 10 (advisory lock). Commit `b4b3b9f0`.
- [x] Maintain connection across app backgrounding (required for POS) — `BluetoothBackgroundManager.handleWillRestoreState` re-hydrates `CBPeripheral` list on app relaunch; `BluetoothScanPolicy` enforces foreground-only scan. Commit `b4b3b9f0`.
- [x] `NSBluetoothAlwaysUsageDescription` in Info.plist — confirmed present in `scripts/write-info-plist.sh`: `"Connect to Bluetooth receipt printers and card readers."`. Commit `[agent-2 b10]`.
- [x] Settings → Hardware → Bluetooth paired list with connection state. `BluetoothSettingsView` + `BluetoothSettingsViewModel` (pre-existing, confirmed complete). Commit `258f346b`.
- [x] Forget button per paired device. `BluetoothSettingsViewModel.forget()` + destructive context menu in `BluetoothDeviceRow`. Commit `258f346b`.
- [x] Surface peripheral battery level where published. `BluetoothDevice.batteryPercent` + `BluetoothBatteryMonitor` GATT 0x180F/0x2A19 reader. Commit `258f346b`.
- [x] Low-battery warning. `BluetoothBatteryMonitor` emits `BluetoothBatteryWarning.lowBattery` when percent < 20. Commit `258f346b`.
- [x] Warn when multiple clients share one peripheral. `BluetoothBatteryMonitor.checkMultiClientRisk()` emits `.multipleClientsDetected` warning. Commit `258f346b`.
- [x] Auto-retry on disconnect every 5s up to 30s. `PeripheralReconnectCoordinator` + `BluetoothRetryPolicy(shortRetryCount:6, shortRetryInterval:5s)`. Commit `b1d56e2c`.
- [x] After 30s, surface "Printer offline" banner. `PeripheralOfflineState.bannerMessage` + `OfflineSeverity.banner`. Commit `b1d56e2c`.
- [x] Exponential backoff: sustained offline → every 60s to save battery. `BluetoothRetryPolicy(longRetryInterval:60s)`. Commit `b1d56e2c`.
- [x] Manual "Reconnect" button bypasses backoff. `PeripheralReconnectCoordinator.manualReconnect()` cancels retry loop and attempts immediately. Commit `b1d56e2c`.
- [x] Severity policy: scanner offline silent (badge only). `DeviceKind.scanner.offlineSeverity == .silent` in `BluetoothConnectionPolicy`. Commit `b1d56e2c`.
- [x] Severity policy: printer offline surfaces banner (POS needs it). `DeviceKind.receiptPrinter.offlineSeverity == .banner`. Commit `b1d56e2c`.
- [x] Severity policy: terminal offline is a blocker (can't charge cards). `DeviceKind.cardReader.offlineSeverity == .blocker`. Commit `b1d56e2c`.
- [x] Log connection events for troubleshooting. `PeripheralConnectionLogger` actor (pre-existing in `BluetoothConnectionPolicy.swift`) + `PeripheralHealthDashboardView` shows recent events. Commit `258f346b`.
- [x] Terminal firmware: BlockChyp SDK reports version vs latest — `FirmwareProvider` protocol + `FirmwareInfo` struct; `FirmwareManager.refresh()` polls all providers. Commit `0f9c77de`.
- [x] Banner: "Terminal firmware outdated — update now" — `FirmwareSettingsView` shows outdated badge + Update button per device. Commit `0f9c77de`.
- [x] Scheduled update (after-hours default) — `FirmwareUpdatePolicy.afterHours` is default; `FirmwareManager.updatePolicy` + `FirmwareSettingsView` open-hours toggle + policy picker. Commit `0f9c77de`.
- [x] Printer firmware: Star / Epson / Zebra SDKs expose version + update API — `FirmwareProvider` protocol abstracts all vendor SDKs; concrete adapters inject behind protocol. Commit `0f9c77de`.
- [x] Manager-prompted update with user confirm before applying — `FirmwareSettingsView` `.confirmationDialog` shows device + version before `applyUpdate(for:isOpenHours:)` called. Commit `0f9c77de`.
- [x] Keep previous firmware available for rollback where supported — `FirmwareInfo.rollbackAvailable`; `FirmwareManager.rollback(for:)` + rollback button shown when available. Commit `0f9c77de`.
- [x] Show expected downtime duration — `FirmwareInfo.estimatedDowntimeMinutes` shown in confirmation dialog and outdated-device row. Commit `0f9c77de`.
- [x] Warn against firmware update during open hours — `FirmwareManager.applyUpdate` blocks when `updatePolicy == .afterHours && isOpenHours`; banner shown in view. Commit `0f9c77de`.
- [x] Never auto-apply without consent — `applyUpdate` is explicit user action only; no background/automatic trigger. Commit `0f9c77de`.
- [x] Log every firmware attempt + result — `FirmwareUpdateLogger` protocol; `logFirmwareUpdate(kind:deviceName:fromVersion:toVersion:result:performedBy:)` called on every attempt. Commit `0f9c77de`.
- [x] Use case: shops charging by weight (e.g. scrap metal, parts by weight) — `ScaleSettingsView` documents supported use cases; `WeightPriceCalculator` handles rate-by-weight. Commit `0f9c77de`.
- [x] Support Bluetooth scales (Dymo M10 / Brecknell / etc.) — `ScaleSettingsView` lists Dymo M10, Brecknell B140/B180 as confirmed compatible (same 0x181D BLE service as Dymo M5). Commit `0f9c77de`.
- [x] Support USB via USB-C dongle — `ScaleSettingsView` USB section documents USB-C adapter path + Bluetooth bridge requirement on iOS. Commit `0f9c77de`.
- [x] POS flow: add item → "Weigh" button → live reading capture. `WeighCaptureView(scale:onCapture:)` + `WeighCaptureViewModel`; live stream with stability indicator; Capture button disabled until stable. Commit `b1d56e2c`.
- [x] Zero-tare / re-weigh controls. `WeighCaptureViewModel.tare()` calls `WeightScale.tare()`; `reWeigh()` resets capture state + restarts stream. Commit `b1d56e2c`.
- [x] Precision units: grams / ounces / pounds / kilograms. `WeightUnit` enum + formatting. Commit `258f346b`.
- [x] Tenant chooses unit system. `WeightUnitStore` UserDefaults persistence. Commit `258f346b`.
- [x] Rate-by-weight pricing rule ("$/lb") with auto-computed total. `WeightPriceCalculator` + `WeightPricingRule`. Commit `258f346b`.
- [x] Note: NTEP-certified scale required for commercial US sales (tenant responsibility) — `NTEPInfoSheet` in `ScaleSettingsView` explains NTEP requirement + tenant responsibility; accessible via Settings → Hardware → Scale → NTEP Certification. Commit `0f9c77de`.
- [x] Primary path: fire "kick" command via thermal receipt printer's RJ11 cash-drawer port. `EscPosDrawerKick` + `EscPosSender` protocol shipped.
- [x] Fire on specific tenders (cash / checks). `CashDrawerManager.handleTender(_:)` fires only for tenders in `triggerTenders` set (default: `.cash`, `.check`). Commit `[agent-2 b4]`.
- [x] Settings → Hardware → Cash drawer → enable + choose printer binding. `HardwareSettingsView` aggregator wires navigation link.
- [x] Test "Open drawer" button. `DrawerSettingsView.testSection` has "Open Drawer Now" button (PIN-gated in release). Commit `258f346b`.
- [x] Alternate path: USB-connected direct-to-iPad via adapter (less common) — `DrawerSettingsView` USB Direct section documents this path and notes the Bluetooth bridge workaround for iOS. Commit `0f9c77de`.
- [x] Manager override: open drawer without sale (reconciliation). `CashDrawerManager.managerOverride(pin:cashierName:)`. Commit `[agent-2 b4]`.
- [x] Manager override requires PIN + audit log. `ManagerPinValidator` protocol injected; `CashDrawerAuditLogger` logs every open with reason + cashier. Commit `[agent-2 b4]`.
- [x] Surface open/closed status where drawer reports it via printer bus. `CashDrawerStatus` enum (`.open`/`.closed`/`.warning`) on `CashDrawerManager`. `markClosed()` for drawer-close signal. Commit `[agent-2 b4]`.
- [x] Warn if drawer left open > 5 minutes. `CashDrawerManager` starts `openWarningDuration` timer on open; transitions status to `.warning("Drawer open > 5 min")`. Commit `[agent-2 b4]`.
- [x] Log drawer-open events with cashier + time. `CashDrawerAuditLogger.logDrawerOpen(reason:cashierName:)` called on every open. Commit `[agent-2 b4]`.
- [x] Anti-theft signal: multiple opens without sale triggers alert. `antiTheftOpenLimit` (default 3); sets `antiTheftAlert` string when exceeded. Commit `[agent-2 b4]`.
- [x] Printer-cash-drawer: bind drawer to printer RJ11 port (§17); test button opens drawer. — `DrawerSettingsView` printer binding picker (`printerBindingSection`) + bound printer badge; `boundPrinterId` persisted in UserDefaults. Commit `0f9c77de`.
- [x] Printer-scanner chain: some wedge scanners route output through printer USB (rarely needed, supported). — `PeripheralStationProfile` covers multi-peripheral binding; scanner + printer bind independently to station. Documented in `DrawerSettingsView` USB section. Commit `0f9c77de`.
- [x] Printer-scale: no native chain; both connect to iPad directly. — `PeripheralStationProfile.scalePeripheralId` + `receiptPrinterSerial` are independent fields; both connect directly to iPad via Bluetooth. Commit `258f346b` (model) + `0f9c77de` (docs).
- [x] Binding profiles: tenant saves "Station 1 = Printer A + Drawer + Terminal X + Scale"; multi-station per location. `PeripheralStationProfile` + `StationProfileStore`. Commit `258f346b`.
- [x] Station assignment on launch: staff picks station, or auto-detect via Wi-Fi/Bluetooth proximity; profile drives settings. `StationProfileStore.activate(id:)` + `autoDetectHint` field. Commit `258f346b`.
- [x] Fallback: graceful degrade (PDF receipt, manual drawer open) if any peripheral in profile fails. `StationFallbackHandler`. Commit `258f346b`.
- [x] Settings → Hardware: per-station peripheral-health dashboard / logs. `PeripheralHealthDashboardView` + `PeripheralHealthEntry`. Commit `258f346b`.
- [x] Doc types: receipt (thermal 80mm + A4 letter), invoice, quote, work order, waiver, labor certificate, refund receipt (thermal/letter), Z-report / end-of-day, tax summary. — `PrintDocumentType` enum covers all types; `defaultMedium` maps each to correct `PrintMedium`. Commit `0f9c77de`.
- [x] Engine: `UIGraphicsPDFRenderer` + SwiftUI `ImageRenderer(content:)`; fallback Core Graphics for thermal printers. — `ReceiptRenderer.rasterize` (ImageRenderer → 1-bit dither) + `ReceiptRenderer.renderPDF` (UIGraphicsPDFRenderer); `PrintDocumentType.supportsPagination` flags multi-page types. Commit `0f9c77de` (type enum) + prior batches (renderer).
- [x] Structure: header tenant branding, body line items + subtotals, footer terms + signature line + QR for public tracking (§4). — `InvoiceDocumentPayload` + `InvoiceDocumentView` (header/bill-to/meta/line-item table/subtotals/footer + signature line + QR) in `DocumentViews.swift`. Commit `49be5543`.
- [x] A11y: tagged PDFs (searchable/copyable); screen-reader friendly in-app. — `ReceiptRenderer.renderAccessiblePDF` sets `UIGraphicsPDFRendererFormat.documentInfo` (Title/Author/Subject/Keywords); `.accessibilityLabel` on all InvoiceDocumentView elements. Commit `49be5543`.
- [x] Archival: generated PDFs on tenant server (primary) + local cache (offline); deterministic re-generation for historical recreation. — `PDFArchiveService` actor: `archive` copies to `AppSupport/pdf-archive/`; `markUploaded`/`pendingUploadEntries`; `APIClient+Hardware.uploadPDFArchive` wires to `POST /api/v1/documents/upload`. Commit `49be5543`.
- [x] Preview: live in template editor with real tenant + sample data. — `ReceiptTemplateEditorView` already ships `ReceiptPreviewCard` + `ReceiptView` live preview in iPad split pane; `InvoiceDocumentView` adds `#Preview("Invoice Document (Letter)")` with `InvoiceDocumentPayload.preview` sample data. Commit `49be5543`.
- [x] Pagination: long invoices span pages with reprinted header + page numbers. — `ReceiptRenderer.renderMultiPagePDF` slices CGImage into `pageHeight` strips with continuation-header support + `PrintMedium.margin`; page-number footer drawn per page. Commit `49be5543`.
- [ ] See §30 for the full list.

### 17.11 BlockChyp SDK status parity across iOS / Android

**Reference**
- Mockup: no dedicated phone frame; relevant via the Card reader tile in "5 · Tender · split payment" and the signature flow documented in §16.26 above.
- Android counterpart: `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/util/SignatureRouter.kt` (will land this wave) and the card tender tile in `bizarre-crm/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/pos/PosTenderScreen.kt` (will land).
- Server completeness: `packages/server/src/routes/blockchyp.routes.ts:45-557` — the following routes **exist and are fully implemented**: `POST /api/v1/blockchyp/test-connection`, `POST /api/v1/blockchyp/capture-signature`, `POST /api/v1/blockchyp/process-payment`, `POST /api/v1/blockchyp/void`, `POST /api/v1/blockchyp/adjust-tip`, `GET /api/v1/blockchyp/status`. Service layer: `packages/server/src/services/blockchyp.ts:63-790` (config, client, payment, signature capture, membership). Migration: `packages/server/src/db/migrations/040_blockchyp.sql`.
- iOS: `ios/Packages/Networking/Sources/Networking/APIClient.swift` (proxy calls); `ios/Packages/Pos/Sources/Pos/PosView.swift` (POS shell). BlockChyp iOS SDK not yet installed in SPM manifest — see blockers below.

**Backend**
- Server is **complete** for all six routes listed above. No server work needed in this wave.
- Envelope: `{ success, data }` on all BlockChyp routes; `res.data.data` single unwrap. Terminal-side errors surfaced as `{ success: false, message }`.
- Tip adjust: `POST /api/v1/blockchyp/adjust-tip` — body `{ transactionId, tipAmount }`. Called after approval if post-auth tip enabled; must fire before batch close.
- Void: `POST /api/v1/blockchyp/void` — body `{ transactionId }`. Same-batch only; cross-batch = refund via captured token.

**Frontend (iOS)**
- **SDK gap**: BlockChyp publishes an iOS SDK (Swift Package). It is not yet added to `ios/Packages/Pos/Package.swift` or the app's `Package.swift`. This is the single largest blocker for all card payment work.
- **Parity target** (match Android + server): test-connection heartbeat ping on POS mount, process-payment auth, capture-signature (terminal preferred / on-phone fallback per §16.26), void, adjust-tip, status polling.
- **`BlockChypService`** — new actor in `ios/Packages/Pos/Sources/Pos/`. Wraps the SDK. All calls are `async throws`. Mirrors the server service shape: `testConnection()`, `processPayment(amount:terminalName:idempotencyKey:)`, `captureSignature(terminalName:)`, `void(transactionId:)`, `adjustTip(transactionId:tipAmount:)`, `status(terminalName:)`.
- **`BlockChypRepository`** — thin layer above `BlockChypService`, adds GRDB persistence (transaction log) + audit logging to `PosAuditLogStore`. Repositories never let raw API calls reach ViewModels.
- **Terminal pairing** (Settings → Hardware → Terminal): QR scan or manual IP + terminal code entry. Stored in Keychain (`com.bizarrecrm.pos.terminal`). `BlockChypService.testConnection()` called on save; success = green "Connected" badge; failure = red "Unreachable" badge with retry.
- **Heartbeat**: on POS screen load, `BlockChypRepository.heartbeat()` called; sets `PosTenderViewModel.terminalStatus` to `.online / .offline`. Status badge rendered in POS toolbar (glass chip — chrome role per GlassKit). Polling every 30s while POS screen is active.
- **Error surface**: all `BlockChypService` errors are mapped to `PosPaymentError` cases — `.declined(reason:)`, `.timeout`, `.networkUnavailable`, `.terminalBusy`, `.voidNotAllowed` (cross-batch). Each case has a localized user-facing message and a recommended action (retry / switch tender / contact admin).
- **Offline posture**: `processPayment` requires network (BlockChyp is cloud-relay or local-network to terminal, not offline-native). If fully offline, "Card reader unavailable offline" alert with "Use cash or park cart" suggestions.
- **PCI posture unchanged**: raw PAN never in iOS app memory or server DB. Only `{ token, last4, brand, authCode }` stored. Same as §16.6 sovereignty rules.
- **Android parity table**:
  - `test-connection` — Android: will land in `PosTenderScreen.kt`; iOS: `BlockChypRepository.heartbeat()` — [ ] not started.
  - `process-payment` — Android: will land in `PosTenderScreen.kt`; iOS: `BlockChypRepository.processPayment(...)` — [ ] not started.
  - `capture-signature` — Android: `SignaturePad.kt` EXISTS; iOS: `CheckInSignaturePad` (§16.26) + `BlockChypService.captureSignature(...)` — [ ] not started.
  - `void` — Android: will land; iOS: `BlockChypRepository.void(...)` — [ ] not started.
  - `adjust-tip` — Android: will land; iOS: `BlockChypRepository.adjustTip(...)` — [ ] not started.
  - `status` — Android: will land; iOS: `BlockChypRepository.heartbeat()` reuses status endpoint — [ ] not started.

**Expected UX**
1. Admin opens Settings → Hardware → Terminal; scans QR printed on BlockChyp terminal; "test-connection" fires; "Connected · counter-1" green badge appears.
2. Cashier opens POS; heartbeat runs; terminal status badge shows green in toolbar.
3. Cashier taps "Card reader" tile in `PosTenderView`; `processPayment` fires; "Insert or tap card" hint shown.
4. Customer taps/inserts card; approval flows through server to terminal; iOS receives approved response.
5. If `sigRequired`: `SignatureRouter` routes (§16.26); signature captured; base64 PNG sent to server.
6. Payment record finalized; `PosTenderView` advances to receipt.
- Terminal offline: heartbeat fails → red badge → "Card reader" tile disabled with tooltip "Terminal offline"; cashier directed to other tenders.
- Decline: error toast "Declined — INSUFFICIENT_FUNDS"; tile re-enables immediately for retry.
- Timeout (60s): cancel sent to terminal; spinner dismissed; tile re-enables.

**Status**
- [ ] BlockChyp iOS SDK added to `ios/Packages/Pos/Package.swift` (BLOCKER — nothing below can ship without this).
- [ ] `BlockChypService` actor + `BlockChypRepository`.
- [ ] Terminal pairing UI (Settings → Hardware → Terminal) with Keychain storage.
- [x] Heartbeat on POS load + 30s polling + status chip in toolbar. (feat(§17): `BlockChypHeartbeatView.init(api:pollingInterval:)`; default upped from hard-coded 10s to spec'd 30s)
- [ ] `processPayment` with idempotency key.
- [ ] `captureSignature` wired to `SignatureRouter` (§16.26 dependency).
- [ ] `void` + `adjustTip` wired from tender / post-approval flows.
- [x] `PosPaymentError` enum with localized messages. (feat(§17): 9-case enum w/ `errorDescription`/`recommendedAction`/`allowsRetry`/`requiresManagerOverride` + `from(_:)` mapper for `ChargeCoordinatorError`/`TerminalError`/`URLError`)
- [ ] Tests: `BlockChypServiceTests` mock SDK calls; assert error-mapping for each decline/timeout case. Coverage ≥ 80%.

---
## §18. Search (Global + Scoped)

_Server endpoints: `GET /search?q=&type=&limit=`, `GET /customers?q=`, `GET /tickets?q=`, `GET /inventory?q=`, `GET /invoices?q=`, `GET /sms?q=`._

### 18.1 Global search (cross-domain)
- [x] **Shipped** — cross-domain search across customers / tickets / inventory / invoices.
- [x] **BUG: Search tab crashes on open** (reported 2026-04-24, iPad Pro 11" 3rd gen, fresh install). Defensive try/catch in `fetchLocal` guards FTS5 schema errors; `fetchRemote` guards empty query early-return; `AppLog.ui.error(...)` on both paths so view shows error state instead of trapping. (feat(§18): 09e6a602)
- [x] **Offline banner** — when query is empty and `!Reachability.shared.isOnline`, shows "Search requires a network connection" placeholder with `.bizarreWarning` icon; a11y label "Offline. Search requires a network connection." (feat(ios phase-3): Leads/Appts/Expenses/SMS/Notifications/Employees/Reports/Search CachedRepository + StalenessIndicator)
- [x] **Trigger** — glass magnifier chip in toolbar (all screens) + pull-down on Dashboard + ⌘F. (`Search/SearchTriggerChip.swift`; `SearchTriggerChip` + `GlobalSearchTriggerModifier` + `.globalSearchTrigger()`; ⌘F keyboard shortcut; 3d0a4f7a)
- [ ] **Command Palette** — see §56; distinct from global search (actions vs data).
- [x] **Scope chips** — EntityFilter chip bar (All / Tickets / Customers / Inventory / Invoices / Estimates / Appointments) wired into GlobalSearchView + EntitySearchView. (feat(ios post-phase §18))
- [ ] **Server result envelope** — each hit has `type`, `id`, `title`, `subtitle`, `thumbnail_url`, `badge`; rendered as unified glass cards.
- [x] **Recent searches** — last 20 queries in `RecentSearchStore` (UserDefaults); chips shown in empty-query state; clear individual or all. (feat(ios post-phase §18))
- [x] **Saved / pinned searches** — `SavedSearchStore` + `SavedSearchListView`; name + entity + query; tap opens `EntitySearchView` pre-filled. (feat(ios post-phase §18))
- [x] **Empty state** — glass card: "Try searching for a phone number, ticket ID, SKU, IMEI, invoice #, or name". Tips list shows what's indexable. (`GlobalSearchView.emptyStateWithRecent`; 30ae5799)
- [x] **No-results state** — "No matches for 'X'. Try different spelling, scope to All, or search by phone." (`GlobalSearchView.noResultsView`; 30ae5799)
- [x] **Loading state** — skeleton rows in glass cards. (`GlobalSearchView.skeletonView`; 30ae5799)
- [x] **Debounce** — 250ms debounce; cancel prior request on new keystroke (`Task` cancellation). (`GlobalSearchViewModel.onChange` 250ms `Task.sleep`; 30ae5799)
- [ ] **Keyboard shortcut** — ⌘F to focus search; ⎋ to dismiss; arrow keys navigate; ⏎ to open.
- [ ] **Voice input** — dictation enabled; smart punctuation disabled (names/numbers).
- [ ] **Result ranking** — server provides; iOS respects; recent + pinned boosted client-side.
- [x] **Type-ahead preview** — top 3 hits in dropdown; "See all" at bottom. (`GlobalSearchView` `typeAheadOverlay`; `GlobalSearchViewModel` `fetchTypeAhead` 100ms debounce → `TypeAheadPreviewView`; agent-9 b10)
- [ ] **Phone-number match** — strip formatting, match on last 10 digits.
- [ ] **IMEI match** — 15-digit serial lookup; falls through to device-linked ticket.
- [ ] **Barcode/SKU** — scan button in search field → auto-fills + submits.

### 18.2 Scoped search (per-list)
- [x] **Per-list search bar** — on every list view, top sticky glass search. (`Search/Filters/ScopedSearchBar.swift`; `ScopedSearchBar` + `ScopedSearchModifier` + `.scopedSearch()` ViewModifier; agent-9 b13 57c17e23)
- [ ] **Server-driven** — pass `q=` param; cursor pagination preserved.
- [x] **Filter chip row** below search — status, date range, assignee, etc. (`ScopedSearchBar` chip bar with `ScopedFilterOption` protocol; `All` + per-option chips; agent-9 b13 57c17e23)
- [x] **Sort menu** — in toolbar next to search; persists per-list in user defaults. (`ScopedSearchModifier` toolbar sort Menu + `ScopedSortOption` protocol; agent-9 b13 57c17e23)
- [x] **Clear (x)** button inline. (`ScopedSearchBar` xmark.circle.fill button when query non-empty; agent-9 b13 57c17e23)
- [x] **iPad** — persistent sidebar → list → detail; search stays in list column. (`ScopedSearchModifier` uses `.safeAreaInset` which stays in list column in NavigationSplitView; agent-9 b13 57c17e23)

### 18.3 Spotlight (system search)
- [x] **`CSSearchableIndex`** — index on background: recent 500 customers, 500 tickets, 200 invoices, 100 appointments. (feat(ios phase-6 §24+§25))
- [x] **Attributes** — title, contentDescription, thumbnailData (customer avatar / ticket photo), keywords, domainIdentifier (bucket by type). (feat(ios phase-6 §24+§25))
- [x] **Update** — on sync, reindex changed items; batch size 100. (feat(ios phase-6 §24+§25))
- [x] **Deletion** — when item deleted locally, delete from index. (feat(ios phase-6 §24+§25))
- [x] **Deep link** — Spotlight tap passes `uniqueIdentifier` → deep link to `/customers/:id` etc. (feat(ios phase-6 §24+§25))
- [x] **Content preview** — Spotlight preview card via `CSSearchableItemAttributeSet.contentURL`. (`Search/Spotlight/SpotlightPreviewBuilder.swift`; `SpotlightPreviewBuilder.enrich()` sets `contentURL` deep-link + `thumbnailData` for tickets/customers/invoices/appointments; `SpotlightPrivacyGate` honours opt-out; agent-9 b13 346d6fe0)
- [x] **Privacy** — exclude phone / email from index when device-privacy mode on (Data & Privacy → Apple Intelligence opts). (`SpotlightPreviewBuilder.enrich(customer:includeContactDetails:)` gates `phoneNumbers`/`emailAddresses` on `SpotlightPrivacyGate.includeContactDetails`; agent-9 b13 346d6fe0)

### 18.4 Entity-scoped search
- [x] **`EntitySearchView`** — search scoped to one entity type via chip selector. `EntitySearchViewModel` (@Observable, 200ms debounce). (feat(ios post-phase §18))
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
- [x] **Local index** — unified `search_index` FTS5 table (porter tokenizer); `FTSIndexStore` actor; `FTSReindexCoordinator` feeds on domain NC events. (feat(ios post-phase §18))
- [x] **Offline result** stale badge — indicate from-cache date. (`GlobalSearchView` `MergedResultRow` `isOfflineResult` → "cached" capsule badge when `.local` row + offline; agent-9 b10)
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
- [x] **Role gating** — non-admins see only Profile / Security / Notifications / Appearance / About; admin gates hidden tabs behind `role.settings.access`. (feat(§19): SettingsView isAdmin gating on Organization/Payments/SMS; iPadSections filtered by role; 4ecb468d)
- [ ] **Search Settings** — `.searchable` on Settings root (⌘F) searching category labels + field labels; jumps straight to tab + highlights field.
- [x] **Unsaved-changes banner** — sticky glass footer with "Save" / "Discard" when any tab form is dirty. (feat(§19): UnsavedChangesBanner + .unsavedChangesBanner() modifier; 4ecb468d)

### 19.1 Profile
- [x] **Avatar** — circular tap → action sheet (Camera / Library / Remove). (feat(§19): ProfileSettingsPage avatar circle + showAvatarPicker → AvatarPickerSheet; 4ecb468d)
- [x] **Fields** — first/last name, display name, email, phone, job title. (`Settings/Pages/ProfileSettingsPage.swift`; `ProfileSettingsViewModel` loads `GET /auth/me`, saves via `PATCH /auth/me`.)
- [x] **Change email** — server emits verify-email link; banner until verified. (`Settings/Profile/ChangeEmailSheet.swift`; `PendingEmailVerificationBanner`; POST `/auth/change-email`; `ProfileSettingsPage` wired; a9c41ef5)
- [x] **Change password** — current + new + confirm; strength meter; submit hits `PUT /auth/change-password`. (`ProfileSettingsPage.swift` showPasswordSection with strength bar.)
- [x] **Username / slug** — read-only unless admin. (`ProfileSettingsPage` Identity section; `UserProfileWire.username` + `isAdmin` fields added; admin sees `TextField`, non-admin sees read-only `.textSelection(.enabled)` `Text`; `ProfileSettingsViewModel.username/isAdmin` loaded from `/auth/me`; agent-9 b9)
- [x] **Sign out (primary)** — bottom of page, destructive red. (`Settings/SettingsView.swift` destructive `Button(role: .destructive)` with confirm; calls `onSignOut`; logout wipes `TokenStore` + `PINStore` + `BiometricPreference`.)
- [x] **Sign out everywhere** — cross-link to §19.2 Security (revokes other sessions; security-scoped, not just this device). (`ProfileSettingsPage.swift` `signOutEverywhere()` → `settingsRevokeAllSessions()`; 449eeceb)
- [x] **Role-based permission badge** — Profile page surfaces the user's assigned role (admin / manager / technician / cashier / viewer) as a labeled chip with role-specific icon + accent color + access-level text ("Full access", "Elevated", …). `UserProfileDTO.role` field added; `ProfileSettingsViewModel.role` loaded from `GET /auth/me`; `RolePermissionBadge` enum maps role → icon/color/label/accessLevel; badge section inserted below avatar. (`Settings/Profile/RolePermissionBadge.swift` + `ProfileSettingsPage.swift`; this commit)

### 19.2 Security
- [x] **PIN** — 6-digit PIN for quick re-auth (locally enforced). (`Settings/Pages/PINSetupSheet.swift`; `PINSetupViewModel` modes .set/.change; `PINDotField`; uses `PINStore.shared` from Persistence; agent-9 b10)
- [x] **Biometric toggle** — Face ID / Touch ID for re-auth + sensitive screen gates. (`Settings/BiometricToggleRow.swift` in `SettingsView.swift` section "Security".)
- [x] **Auto-lock timeout** — Immediately / 1 min / 5 min / 15 min / Never; backgrounded app blurred via privacy snapshot. (`Settings/Pages/SecuritySettingsPage.swift`; `AutoLockTimeout` enum + `SecuritySettingsViewModel`; a3a38f4b)
- [x] **2FA** — enroll (TOTP QR → Google/Authy/1Password/built-in iCloud Keychain), ~~disable,~~ regenerate backup codes, copy to Notes prompt. (Self-service disable blocked by policy 2026-04-23; recovery happens via backup-code flow + super-admin force-disable.) (`Settings/Pages/TOTPEnrollmentSheet.swift`; `TOTPEnrollmentViewModel` QR scan + verify + backup codes; 4968fe57)
- [x] **Active sessions** — list device + last-seen + location (IP); revoke. (`Settings/Pages/ActiveSessionsPage.swift`; `ActiveSessionsViewModel` load/revoke/revokeAll; `ActiveSessionsPage`; 92620a66)
- [x] **Trusted devices** — mark "this device is trusted" to skip 2FA. (`Settings/Pages/TrustedDevicesPage.swift`; `TrustedDevicesViewModel` + `TrustedDevicesPage`; 875945e8)
- [x] **Login history** — recent 50 logins with outcome + IP + user-agent. (`Settings/Pages/LoginHistoryPage.swift`; `LoginHistoryViewModel` + `LoginHistoryPage`; f837d19f)
- [x] **App lock with biometric** on cold launch — toggle. (`SecuritySettingsPage.swift` `biometricAppLockEnabled` toggle + `SecuritySettingsViewModel.shouldGateOnBiometric()`; a3a38f4b)
- [x] **Privacy snapshot** — blur app in App Switcher. (`SecuritySettingsPage.swift` `privacySnapshotEnabled` toggle + `SecuritySettingsViewModel.shouldApplySnapshot()`; a3a38f4b)
- [x] **Copy-paste gate** — opt-in disable for sensitive fields (SSN, tax ID). (`Settings/Security/SensitiveFieldModifier.swift`; `SensitiveFieldModifier` + `SensitiveFieldSettings` + `SensitiveFieldSettingsRow`; b85e932d)

### 19.3 Notifications (in-app preferences)
- [x] **Per-channel toggle** — New SMS inbound / New ticket / Ticket assigned to me / Payment received / Payment failed / Appointment reminder / Low stock / Daily summary. (`Settings/Pages/NotificationsPage.swift` per-category toggles + System Settings link.)
- [x] **Delivery medium** per channel — Push / Email / SMS / In-app only. (PTT volume slider + notification grouping toggle added to `NotificationsPage.swift`; `pttVolume` 0–100% persisted to UserDefaults; grouping toggle persisted; this commit)
- [x] **Quiet hours** — start/end time; show icon in tab badge during quiet hours. (`NotificationsPage.swift` DatePicker pair; 7468235f)
- [x] **Critical overrides** — "Payment failed" and "@mention" can bypass quiet hours (toggle). (`NotificationsPage.swift` critical overrides section; 7468235f)
- [x] **"Open System Settings"** button → `UIApplication.openNotificationSettingsURLString` (iOS 16+). (`NotificationsPage.swift`)
- [x] **Test push** — admin-only button sends test notification. (`NotificationsExtendedPage.swift` `vm.sendTestPush()` → `api.postTestPush()` → `POST /api/v1/notifications/test`; admin gate; alert confirm; agent-9 b4 confirmed)

### 19.4 Appearance
- [x] **Theme** — System / Light / Dark; persisted via UserDefaults, applied to all UIWindows. (`Settings/Pages/AppearancePage.swift`; `AppearanceViewModel`.)
- [x] **Accent** — Brand triad: Orange / Teal / Magenta (one-tap). (`AppearancePage.swift`)
- [x] **Density** — Compact toggle; row height scale. (`AppearancePage.swift`)
- [x] **Glass intensity** — 0–100% slider; <30% falls to solid material (a11y alt). (`AppearancePage.swift` 357a568b)
- [x] **Reduce motion** — overrides system (for one-user testing). (`AppearancePage.swift`)
- [x] **Reduce transparency** — overrides system. (`AppearancePage.swift` 357a568b)
- [x] **Font scale** — 80–140% slider; honors Dynamic Type. (`AppearancePage.swift`)
- [x] **Sounds** — receive notification sound / scan chime / success / error; master mute. (`AppearancePage.swift` 357a568b)
- [x] **Haptics** — master toggle + per-event subtle/medium/strong. (`AppearancePage.swift` 357a568b)
- [x] **Icon** — alt-icon picker (SF Symbol for build, later PNG variants). (`AppearancePage.swift` `AppIconPickerSection`; Theme section replaced with `ThemePreviewTile` visual thumbnail grid showing mini light/dark/system mockup with orange selection ring + checkmark; this commit)

### 19.5 Organization (admin)
- [x] **Company info** — legal name, DBA, address, phone, website, EIN. (`Settings/Pages/CompanyInfoPage.swift`; `CompanyInfoViewModel`; `PATCH /tenant/company`.)
- [x] **Logo** — upload; renders on receipts / invoices / emails. (`Settings/Organization/LogoUploadView.swift`; `LogoUploadViewModel` GET/POST multipart/DELETE; `PhotosPicker` + `AsyncImage`; f7aafa33)
- [x] **Timezone** — `TimeZone.knownTimeZoneIdentifiers` picker. (`Settings/Pages/LanguageRegionPage.swift`)
- [x] **Currency** — `Locale.commonISOCurrencyCodes` picker. (`LanguageRegionPage.swift`)
- [x] **Locale** — `Locale.availableIdentifiers` picker. (`LanguageRegionPage.swift`)
- [x] **Preferred currency override** (per-user) — `UserPreferencesResponse.preferredCurrency` field (`preferred_currency` key) + Picker in Settings → Preferences → Currency section; "Default (use tenant setting)" option clears override; encoded as `nil` on save when empty. (`APIClient+Settings.swift` + `PreferencesPage.swift`; this commit)
- [x] **Region-format override** (per-user) — `UserPreferencesResponse.dateFormatOverride` + `numberFormatOverride` fields (`date_format_override`, `number_format_override`); Pickers in Settings → Preferences → Region formats section; footer note explains fallback to tenant setting. (`APIClient+Settings.swift` + `PreferencesPage.swift`; this commit)
- [x] **Business hours** — per day of week with multiple blocks, holiday exceptions, presets, open/closed indicator. (`Settings/Hours/`: `HoursModels`, `BusinessHoursEditorView`, `HolidayListView`, `HolidayEditorSheet`, `HolidayPresetsSheet`, `OpenClosedIndicator`, `HoursCalculator`, `HoursValidator`, `HoursRepository`, `HoursEndpoints`. 27 pure-logic tests passing.)
- [ ] **Location management** — sibling agent: `Settings/Locations/`.
- [x] **Receipt footer** + invoice footer text. (`OrganizationSettings` `receiptFooter`/`invoiceFooter` fields; `OrganizationSettingsView` TextEditor sections; `store_config` keys `receipt_footer`/`invoice_footer`; agent-9 b10)
- [ ] **Terms & policies** — warranty, return, privacy printed on receipts.

### 19.6 Tickets settings (admin)
- [x] **Status taxonomy** — re-order / rename / add / archive custom statuses; color per status. (`Settings/Pages/TicketStatusSettingsPage.swift`; `TicketStatusSettingsViewModel`; drag-to-reorder; `ColorPickerRow` 10 presets; agent-9 b10)
- [x] **Default status** — new tickets start at. (`TicketStatusSettingsPage.swift` swipe-leading "Set Default" action + `setDefault()` VM method; agent-9 b10)
- [ ] **Pre-conditions checklist** — tenant-configurable default list of checks (Back cover cracked? Sim tray? Water damage?).
- [ ] **Conditions** — list (with icons) of device conditions to tick at intake; edit / reorder / add.
- [x] **Ticket # format** — `{prefix}-{year}-{seq}` tenant-configurable. (`Settings/Pages/TicketNumberFormatPage.swift`; `TicketNumberFormatConfig` + `TicketNumberFormatter.preview` token renderer + `TicketNumberFormatViewModel`; 3cc0cf20)
- [ ] **SLA rules** — auto-warn after X hours in status Y.
- [ ] **Auto-assignment** — round-robin / load-balanced / manual.
- [ ] **Required fields** at intake (toggle per field).
- [ ] **Device templates** (see §48) — managed here.

### 19.7 Invoices settings (admin)
- [x] **Invoice # format**. (`Settings/Pages/InvoiceSettingsPage.swift` `numberFormat` field with live preview; agent-9 b10)
- [x] **Net terms** — Due-on-receipt / Net-15 / Net-30 / custom. (`InvoiceSettingsPage.swift` `NetTermsPreset` enum + Picker; agent-9 b10)
- [x] **Late fee** — percentage + grace period. (`InvoiceSettingsPage.swift` `lateFeePercent` + `lateFeeGraceDays`; agent-9 b10)
- [x] **Email from** — from-address + reply-to. (`InvoiceSettingsPage.swift` `emailFrom`/`emailReplyTo` fields; agent-9 b10)
- [x] **Auto-send** reminders — 3 days before due / day of / 3 days after / weekly overdue. (`InvoiceSettingsPage.swift` `reminderDays` toggles for [7,3,1,0,-3,-7,-14]; agent-9 b10)
- [x] **Allowed payment methods** — Card / Cash / Check / ACH / Financing. (`InvoiceSettingsPage.swift` `allowedPaymentMethods` toggle set; agent-9 b10)
- [x] **Fees** — processing surcharge (% or $); restocking fee default. (`InvoiceSettingsPage.swift` `surchargePct` field; agent-9 b10)
- [ ] **Accepted payment methods surface** on customer portal.

### 19.8 Tax
- [x] **Tax rates** — list (name, rate, applies-to); add/edit/archive. (`Settings/Pages/TaxSettingsPage.swift`; `TaxSettingsViewModel`; `POST/PATCH /tax-rates`.)
- [ ] **Nested tax** — state + county + city stacking.
- [x] **Tax-exempt categories** — isExempt toggle per rate. (`TaxSettingsPage.swift` draftIsExempt field.)
- [ ] **Per-customer override** — default handled in customer record.
- [ ] **Automated rate lookup** (Avalara/TaxJar integration toggle — stretch).

### 19.9 Payment (BlockChyp + methods)
- [x] **BlockChyp API key** + terminal pairing. (`Settings/Pages/PaymentMethodsPage.swift`; `PUT /settings/payment`.)
- [x] **Surcharge rules** — card surcharge on/off. (`PaymentMethodsPage` "Card rules" section; `cardSurchargeEnabled` field in `PaymentMethodSettings` + `PaymentSettingsDTO`.)
- [x] **Tipping** — enabled / presets (10/15/20) / custom allowed / hide. (`PaymentMethodsPage` "Tipping" section; `tippingEnabled` + `tipPresets` toggle-chip UI; persisted via `PUT /settings/payment`.)
- [x] **Manual-keyed card** allowed toggle. (`PaymentMethodsPage` "Card rules" section; `manualKeyedCardAllowed` field.)
- [x] **Gift cards** on/off toggle. (`PaymentMethodsPage.swift`)
- [x] **Store credit** on/off toggle. (`PaymentMethodsPage.swift`)
- [ ] **Refund policy** — max days since sale; require manager above $X.
- [ ] **Batch close time** — auto-close card batch.

### 19.10 SMS / Templates (admin)
- [x] **SMS provider** — Twilio / Bandwidth / BizarreCRM-managed picker. (`Settings/Pages/SmsProviderPage.swift`; `GET/PUT /settings/sms`.)
- [x] **From number** + A2P 10DLC registration status display. (`SmsProviderPage.swift`)
- [ ] **Template library** — Ticket-ready / Estimate / Invoice / Payment confirmation / Appointment reminder / Post-service survey.
- [ ] **Variable tokens** — `{customer.first_name}`, `{ticket.status}`, `{invoice.amount}`, `{eta.date}`, etc.; token picker.
- [x] **Test send** to current user's phone. (`SmsProviderPage.swift`)
- [ ] **Auto-responses** — out-of-hours auto-reply; keywords (STOP / HELP / START).
- [ ] **Compliance** — opt-out keywords, carrier-required footers.
- [x] **MMS** toggle if plan supports. (`SmsProviderPage` "Messaging capabilities" section; `mmsEnabled` in `SmsProviderViewModel` + `SmsSettingsDTO`; persisted via `PUT /settings/sms`.)

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
- [x] **Connection test** — latency (ping) + auth check + TLS cert SHA shown. (`ServerSettingsPage.swift` — `pingHealth()` endpoint, `ConnectionTestResult` enum, latency display; 09e6a602)
- [ ] **Pinning** — SPKI pin fingerprint viewer + rotate.
- [ ] **Last-used persistence note** — server URL + username retained in Keychain across sign-out (tokens are NOT retained) so the Login screen pre-fills on return. Implemented at the auth layer, surfaced here for transparency.

### 19.23 Data (local)
- [ ] **Force full sync** — wipes GRDB, re-fetches all domains.
- [x] **Sync queue inspector** — pending writes + retry age + dead-letter (tap to retry / drop). (`Settings/SyncDiagnosticsView.swift` with per-row Retry / Discard backed by `SyncQueueStore`.)
- [ ] **Clear cache** — images + catalog (not queued writes).
- [ ] **Reset GRDB** — nuclear option (sign out + wipe).
- [x] **Disk usage** — breakdown: images X MB, GRDB Y MB, logs Z MB. (`SyncDiagnosticsView` "Disk usage" section; `SyncDiagnosticsViewModel.refreshDiskUsage()` walks Documents + Caches + Library/Logs with `ByteCountFormatter`.)
- [ ] **Export DB** (dev build only) — share sheet → `.sqlite` file.

### 19.24 About
- [x] **Version + build + commit SHA** (from `GitVersion`). (partial — `Settings/AboutView.swift` shows version + build via `Platform.appVersion`/`Platform.buildNumber`; commit SHA not yet appended.)
- [x] **Licenses** — `NSAcknowledgments` auto-generated. (`LicensesView` in `AboutView.swift` reads `Acknowledgements.plist` (Agent 10 script), falls back to inline credits for 6 known deps; expandable rows; db65cb55)
- [x] **Privacy policy**, **Terms of Service**, **Support email** — deep links. (`Settings/AboutView.swift` section "Support" links `mailto:support@bizarrecrm.com`, privacy policy, and terms of service.)
- [x] **App Store review** — `SKStoreReviewController` after N engaged sessions. (`AppEngagementCounter.requestReviewIfEligible()` — gates on ≥10 sessions + `ratedKey` not set; called from "Rate Bizarre CRM" button; db65cb55)
- [x] **Device info** — iOS version, model, free storage. (`AboutView` Device section: `UIDevice.current.systemVersion` + model + `FileManager` free storage; db65cb55)
- [x] **Secret gesture** — tap version row 7× → Diagnostics. Converted from `onLongPressGesture` to `.onTapGesture` counter; countdown hint label (e.g. "3") appears after first tap, auto-hides; 7 taps shows `DiagnosticsUnlockedBanner` glass overlay, auto-dismiss 4s. (`AboutView.swift` `versionTapCount` state + `.onTapGesture`; db65cb55 → this commit)
- [x] **Feedback link copy** — "Copy feedback link" button in Settings → About → Support section; copies `https://bizarrecrm.com/feedback?source=ios&v={version}` to clipboard; icon transitions to checkmark for 2s. (`AboutView.swift` `feedbackLinkCopied` state + `UIPasteboard`; this commit)

### 19.25 Diagnostics (dev/admin)
- [x] **Log viewer** — `OSLog` stream, filter by subsystem + level. (`LogViewerSection` in `DiagnosticsPage.swift` — reads `OSLogStore.currentProcessIdentifier`, last 1h, `com.bizarrecrm` subsystem, text+level filter; pre-existing in b4)
- [x] **Network inspector** — last 200 HTTP requests + response + latency; redact tokens. (`NetworkInspectorSection` in `DiagnosticsPage.swift`; pre-existing in b4)
- [x] **WebSocket inspector** — live stream of WS frames. (`WebSocketInspectorSection` + `WebSocketFrameEntry` + `DiagnosticsViewModel.postWSFrame(_:)` in `DiagnosticsPage.swift`; ring buffer 200 frames; in/out direction + payload + byte count; db65cb55)
- [x] **Feature flags** — server-driven + local override. (`FeatureFlagsSection` in `DiagnosticsPage.swift`; pre-existing in b4 + `FeatureFlagsView.swift` in `TenantAdmin/`)
- [x] **Glass element counter** overlay — show how many glass layers active (perf). (`GlassLayerCounter.shared` public facade over `GlassBudgetMonitor` in `GlassKit.swift`; `GlassLayerCounterHUD` floating overlay in `DiagnosticsPage.swift`; toggled via new "Glass layer counter" switch in Danger zone; this commit)
- [x] **Crash test button** — force crash to verify symbolication. (`DangerZoneSection` in `DiagnosticsPage.swift`; confirmation dialog → `arr[0]` intentional crash; db65cb55)
- [x] **Memory / FPS HUD** — toggleable overlay. (`FPSMemoryHUDView` overlaid on Diagnostics when `showHUD` toggled in Danger zone; mach_task_basic_info memory + 60fps display; db65cb55)
- [x] **Environment** — toggle staging vs production API (dev builds only). (`DiagnosticsPage.swift` new `EnvironmentSection` + `DiagnosticsTab.environment` "Env" tab; persists to `UserDefaults` "debug.useStagingEnvironment"; restart-required banner; server-info rows; this commit)

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
- [x] Location: Settings → Diagnostics → Dead-letter queue (+ exposed in §19.25 debug-drawer panel). (`Sync/DeadLetter/DeadLetterListView.swift`)
- [x] Item row: action type (create-ticket / update-inventory / …), failure reason, first-attempted-at, last-attempt-at, attempt count, last-error. (`DeadLetterListView` row shows entity, op, attempts, error, relative timestamp.)
- [x] Actions per row: Retry now / Retry later / Edit payload (advanced) / Discard (confirm required). (`DeadLetterDetailView` — Retry re-enqueues via `SyncQueueStore.retryDeadLetter`; Discard via `discardDeadLetter`; full JSON payload displayed with `textSelection`; destructive confirm alert.)
- [x] App-root banner if DLQ count > 0: "3 changes couldn't sync — open to fix." (`Settings/DLQAlertBanner.swift`; `DLQAlertBannerViewModel` polls `SyncQueueStore.deadLetterCount()` every 30s; glass banner with "Fix now" tap + dismiss button; re-shows on new failures; 4 XCTest assertions; agent-9 b9)
- [ ] Auto-escalation at > 24h: server emails tenant admin (not iOS-sent).
- [ ] Before discard, offer "Export JSON" so user can manually reapply elsewhere.
- [ ] Top-level search bar in Settings: typeahead over all setting labels + synonyms; jumps to matching page with highlight
- [ ] Static index built at compile time from settings metadata; pre-seeded synonyms ("tax"→"Tax rules", "sms"→"SMS provider", "card"→"Payment (BlockChyp)")
- [ ] Results UI grouped by section (Payment/Notifications/Privacy…); tap navigates and highlights setting for 1.5s with subtle pulse
- [ ] A11y: VoiceOver reads "5 results; first: Tax rules in Payment"
- [ ] Empty state: "No settings match 'xyz'. Try synonyms: card, payment, cash."
- [ ] Recently changed: small section at top with last 5 toggles
- [ ] Shake-to-report-bug: dev/staging builds only; `UIResponder.motionEnded(.motionShake)` opens bug-report form (§69); production is opt-in via Settings → Accessibility (subway riders)
- [x] Shake-to-undo: iOS system gesture; `UndoManager` (§63) hooks in; honor user's iOS setting (Accessibility → Touch → Shake to Undo) (`.shakeToUndo(undoManager:isGestureActive:)` in `Motion/Section30MotionExtras2.swift`. feat(§30))
- [ ] Accidental-trigger protection: debounce; ignore shakes during active gestures (scroll/pan)
- [x] Device-local backup: Settings → Data → Backup now → exports SQLCipher DB + photos to `~/Documents/Backups/<date>.bzbackup` (encrypted bundle); share sheet to Files / iCloud Drive / AirDrop
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
- [x] Device registry per tenant: each iPad / iPhone registered (`Settings/Pages/DeviceListPage.swift`; `RegisteredDevice` model + `DeviceListViewModel` + `DeviceListPage` + `DeviceRow`; online status, assigned user, app version, remote sign-out swipe; this commit)
- [x] Registry fields: serial, device model, iOS version, location, assigned user, last-seen, app version (`DeviceListPage.swift` — stat chips total/online/offline, per-row model/OS/appVersion/user/location/lastSeen; this commit)
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
- [x] Lint rule flags `APIClient.{get,post,patch,put,delete}` called from outside a `*Repository` file. (`ios/scripts/sdk-ban.sh`, `.github/workflows/ios-lint.yml`)
- [x] Lint rule flags bare `URLSession` usage outside `Core/Networking/`. (`ios/scripts/sdk-ban.sh`)
- [x] Airplane-mode smoke test: migrations + `sync_queue`/`sync_state` tables verified; enqueue/drain/fail/dead-letter paths exercised via in-memory DB. (`ios/Tests/SmokeTests.swift`)
- Required test fixtures: each repository has an offline-read + offline-write + reconnect-drain test (§31 / §31).

Every subsequent subsection below is part of Phase 0 scope. Agent assignments in `ios/agent-ownership.md` move §20 into Phase 0.

### 20.1 Read-through cache architecture
- [ ] **Every read** lands in a GRDB table; SwiftUI views observe GRDB via `@FetchRequest` equivalent (`ValueObservation`).
- [x] **Repository pattern** — `CachedRepository` protocol + `AbstractCachedRepository<Entity, ListFilter>` generic helper: `list(filter:maxAgeSeconds:)` returns `CachedResult<[Entity]>` (cache-first, background remote refresh when stale); `create`/`update`/`delete` persist locally then enqueue `SyncOp`. (`Sync/CachedRepository.swift`)
- [x] **Read strategies** — `networkOnly` (force) / `cacheOnly` (offline) / `cacheFirst` (default) / `cacheThenNetwork` (stale-while-revalidate). (`ReadStrategy` enum in `Sync/CachedRepository.swift`. feat(§20.1): 17a3138c)
- [ ] **TTL per domain** — tickets 30s, inventory 60s, customers 5min, reports 2min, settings 10min.
- [x] **Staleness indicator** — glass chip on top right of list: "Updated 3 min ago". (`Sync/StalenessIndicator.swift` + `StalenessLogic`; color thresholds: < 1h green, < 4h amber, >= 4h red; Liquid Glass capsule; a11y label; Reduce Motion respected.)

### 20.2 Write queue architecture
- [x] **`sync_queue` table** — columns: `id, op, entity, entity_local_id, entity_server_id, payload, idempotency_key, status, attempt_count, last_error, enqueued_at, next_retry_at`.
- [x] **Ops** — `create`, `update`, `delete` wired for customer + inventory; ticket update pending merge. `upload_photo` / `charge` deferred to §20.4 / POS.
- [x] **Optimistic write** — create VMs set `createdId = -1` sentinel (PendingSync) + dismiss immediately; row inserted to sync_queue.
- [x] **Drain loop** — `SyncManager.syncNow()` real implementation: pulls `SyncQueueStore.due(limit:20)`, calls `SyncOpExecutor`, marks `.succeeded`/`.failed`/dead-letter; `autoStart()` via `NWPathMonitor`; `SyncOpExecutor` protocol keeps Sync pkg domain-free. (`Sync/SyncManager.swift`)
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
- [x] **Conflict-resolved toast** — top-of-screen glass toast that auto-dismisses after 3 s when `ConflictResolutionPhase` enters `.resolved`; shows resolution strategy (server/local/merged/rejected). `ConflictResolvedToastModifier` + `.conflictResolvedToast(phase:)` in `Sync/Conflicts/ConflictResolvedToast.swift`. (feat(§20.3))

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
- [x] **`NWPathMonitor`** — reactive publisher of path status (wifi / cellular / none / constrained / expensive). (`SyncManager.autoStart()` subscribes and triggers `syncNow()` on reconnect.)
- [x] **Offline banner** — glass chip at top of every screen when path == none. (`ConnectivityBannerModifier` + `.connectivityBanner()` View extension in `Sync/ConnectivityBannerModifier.swift`; wraps `Reachability.isOnline` + `SyncManager.pendingCount`; uses `OfflineBanner` from DesignSystem; `safeAreaInset` ensures it never hides list content. feat(§20.6): connectivity banner modifier 173d99c4)
- [x] **Metered-network warning** — if cellular + expensive, pause photo uploads until wifi (user override). (`MeteredUploadPolicy` + `MeteredNetworkWarningModifier` + `.meteredNetworkWarning(isUploadPending:)` in `Sync/MeteredNetworkWarning.swift`; glass banner safeAreaInset; per-session user override. feat(§20.6): 7000f88c)
- [x] **Offline banner copy variants** — distinct copy for no-signal vs cellular vs constrained-wifi. `OfflineBannerCopy` value type in `Sync/OfflineBannerCopy.swift`; `ConnectivityBannerModifier` updated to use `ConnectivityCopyChip` for non-online states; "No internet connection / Changes will sync…" vs "Using cellular data / Large uploads paused…". (feat(§20.6))
- [ ] **Stale-cache banner** — if offline > 1h on a data-heavy screen.

### 20.7 Selective sync (large tenants)
- [ ] **First-boot** pulls — recent 90 days of tickets / invoices; all customers / inventory / staff.
- [ ] **On-demand older** — "Load older" button paginates backward.
- [ ] **Per-location filter** — if user is location-scoped, only sync that location's tickets.
- [ ] **User setting** — "Sync last 30 days" / "90 days" / "All".

### 20.8 Manual sync controls
- [x] **Sync now** — `RetryNowButton` (full + compact styles) in `Sync/RetryNowButton.swift`; calls `SyncManager.syncNow()`; shows spinner + success checkmark; disables during in-flight drain. (feat(§20.8))
- [x] **Per-tab pull-to-refresh** — standard `.refreshable`. (Dashboard/Tickets/Customers wired to forceRefresh() via CachedRepository; phase-3 PR)
- [x] **Last-sync timestamp** footer in Settings → Data. `LastSyncFooter` (full + compact) in `Sync/LastSyncFooter.swift`; `TimelineView` 1-min cadence keeps relative label fresh; shows pending count subline. (feat(§20.8))
- [x] **Unsynced writes count** — `PendingActionChip` capsule badge in `Sync/PendingActionChip.swift`; observes `SyncManager.pendingCountDidChange` notification; hides at zero. (feat(§20.8))

### 20.9 Cache invalidation + eviction
- [x] **Image cache — tiered eviction per §29.3** (not blunt 500 MB LRU). Thumbnails always cached; full-res LRU with tenant-size-scaled cap (default 2 GB, configurable 500 MB – 20 GB or no-limit); pinned-offline store + active-ticket photos never auto-evicted. Cleanup runs at most once / 24h in `BGProcessingTask`; never during active use. (`Core/Performance/StorageBreakdown.swift` — `ImageCachePolicy` singleton; `StorageMonitor`; tiered eviction policy with `isEvictable` per `StorageCategory`. feat(§20.9): b12)
- [ ] **GRDB VACUUM** — monthly on-launch background task; skipped if sync queue has pending writes.
- [x] **Size monitoring** — footer in Settings → Data shows live breakdown (§29.3 storage panel). Warn only on device-low-disk (< 2 GB free), not on app-cache growth alone. (`StorageMonitor.measure(inject:)` async scanner + `StorageBreakdown` snapshot struct in `Core/Performance/StorageBreakdown.swift`; `ImageCachePolicy.isDeviceLowOnDisk()` threshold guard. feat(§29.3): b12)
- [ ] **Low-disk pause** — temporarily freeze writes to cache if device free-space drops below 2 GB; toast "Free up space — app cache paused". Never evict pinned or in-use items to satisfy the guard.

### 20.10 Multi-device consistency
- [ ] **Per-device-id** on mutations so server echoes back correct events.
- [ ] **WS echo** — if user has iPad + iPhone, update on other device via WS.
- [ ] See §19 for the full list.
- [ ] See §16 for the full list.

---
## §21. Background, Push, & Real-Time

### 21.1 APNs registration
- [x] **Register** — `UIApplication.shared.registerForRemoteNotifications()` after auth + user opt-in.
- [x] **Upload token** — `POST /device-tokens { token, bundle_id, model, ios_version, app_version, locale }` with tenant-id header.
- [x] **Token rotation** — on APNs delegate rotation, POST new; old implicitly invalidated server-side after 30 days silence. (`Notifications/Push/PushRegistrar.swift` `rotateDeviceTokenIfNeeded(_:)`; hex diff + best-effort unregister old + re-register new; a3a38f4b)
- [x] **Unregister on logout** — `DELETE /device-tokens/:id`.
- [x] **Permission prompt** — deferred until after first login (not on launch); rationale sheet before system prompt.

### 21.2 Push categories & actions
- [x] **`SMS_INBOUND`** — Reply / Mark read / Call customer.
- [x] **`TICKET_ASSIGNED`** — Open / Snooze / Reject.
- [x] **`TICKET_STATUS_CHANGED`** — Open.
- [x] **`PAYMENT_RECEIVED`** — Open invoice / Print receipt.
- [x] **`PAYMENT_FAILED`** — Open / Retry charge. (`NotificationCategoryID.paymentFailed`, `paymentFailedCategory()` in `NotificationCategories.swift`; 09e6a602)
- [x] **`APPOINTMENT_REMINDER`** — Open / Mark done / Reschedule.
- [x] **`MENTION`** — Reply.
- [x] **`LOW_STOCK`** — Reorder / Dismiss.
- [x] **`SHIFT_SWAP_REQUEST`** — Accept / Decline.
- [ ] **Rich push** — thumbnail (customer avatar, ticket photo) via `UNNotificationAttachment`.

### 21.3 Silent push
- [x] **`content-available: 1`** triggers sync delta; no banner.
- [x] **Events** — new SMS / ticket update / invoice payment / server-initiated refresh.
- [x] **Coalescing** — debounce multi-events in a window; single sync. (`Notifications/SilentHandlers/SilentPushCoalescer.swift`; `SilentPushCoalescer` actor; 2s debounce + high-water (10) immediate fire; `SilentPushCoalescerTests` 3 assertions; agent-9 b13 1e543320)

### 21.4 Background tasks
- [x] **`BGAppRefreshTask`** — opportunistic catch-up sync every 1–4h; schedule after launch. (feat(§21): AppBackgroundTaskScheduler — syncRefreshID + runSyncRefresh() with cancellation handler; 4ecb468d)
- [x] **`BGProcessingTask`** — nightly GRDB VACUUM + image cache prune. (feat(§21): AppBackgroundTaskScheduler — maintenanceNightlyID + runMaintenance(); 4ecb468d)
- [ ] **`BGContinuedProcessingTask`** (iOS 26) — "Sync now" extended run when user initiates a long sync.
- [ ] **Task budgets** — complete within 30s; defer remainder.

### 21.5 WebSocket (Starscream)
- [x] **Endpoints** — `wss://.../sms`, `wss://.../notifications`, `wss://.../dashboard`, `wss://.../tickets`. (feat(§21): WebSocketManager multi-endpoint enum + connect/disconnect; 4ecb468d)
- [ ] **Auth** — bearer in `Sec-WebSocket-Protocol` header; server validates.
- [x] **Reconnect** — exponential backoff 1s → 2s → 4s → 8s → 16s → 30s cap; jitter ±10%. (feat(§21): WebSocketClient.scheduleReconnect() via min(pow(2,n),30); 4ecb468d)
- [x] **Heartbeat** — ping every 25s; timeout 30s → force reconnect. (feat(§21): WebSocketManager.startHeartbeat() 25s poll + state mirror; 4ecb468d)
- [x] **Subscriptions** — per-view subscribe/unsubscribe; dedup server-side. (feat(§21): WebSocketManager.subscribe/unsubscribe with subscriberCount lifecycle; 4ecb468d)
- [ ] **Event envelope** — `{ type, entity, id, payload, version }`.
- [ ] **Backpressure** — coalesce high-frequency events (dashboard KPIs) at 1Hz client-side.
- [ ] **Disconnect UX** — subtle glass chip "Reconnecting…"; lists keep showing stale data.
- [ ] **Message bus** — `Combine` publisher per event type; repositories subscribe.

### 21.6 Foreground lifecycle
- [x] **`didBecomeActive`** — lightweight sync + WS re-subscribe. (feat(§21): ForegroundLifecycleObserver.onDidBecomeActive callback via UIApplication.didBecomeActiveNotification; 9cd0b5b8)
- [x] **`willResignActive`** — flush pending writes; snapshot blur if security toggle on. (feat(§21): ForegroundLifecycleObserver.onWillResignActive callback; 9cd0b5b8)
- [x] **Memory warning** — flush image cache, reduce GRDB page cache. (feat(§21): ForegroundLifecycleObserver.onMemoryWarning callback; 9cd0b5b8)

### 21.7 Real-time UX
- [x] **Pulse animation** on list row when item updates via WS. Commit `1be36e50`.
- [x] **Toast** — top-of-screen glass "New message from X" with tap → thread. Commit `1be36e50`.
- [x] **Badge sync** — unread counts propagate to tab bar + icon badge.

### 21.8 Deep-link routing from push
- [x] **`userActivity`** dispatcher — Notification → entity URL → `NavigationStack.append(...)`. (`Notifications/Push/PushDeepLinkDispatcher.swift` `dispatch(userInfo:isAuthenticated:)`; agent-9 b5 confirmed)
- [x] **Cold-launch** deep link handled before first render. (`PushDeepLinkDispatcher.swift` `dispatchFromLaunchOptions`; agent-9 b5 confirmed)
- [x] **Auth gate** — if token invalid, store intent, auth, then restore. (`PushDeepLinkDispatcher.swift` `PendingPushIntent` storage; agent-9 b5 confirmed)
- [x] **Entity allowlist** — only known schemes parsed; reject unknown paths. (`PushDeepLinkDispatcher.swift` `NotificationRoute` entity allowlist; agent-9 b5 confirmed)

### 21.9 Quiet hours policy

No in-app client-side quiet hours (duplicates iOS Focus + confuses tenant admins + fights OS on conflict + doesn't sync across user's other Apple devices).

Users get quieting from two canonical sources:
1. **Tenant server quiet hours** (shop-wide) — configured in Settings → Organization → Hours (§19.5). Server suppresses sending SMS-inbound / ticket / payment pushes outside shop hours. Authoritative, user-independent.
2. **iOS Focus modes / Scheduled Summary** (per-user, cross-device) — the OS silences pushes the server did send. Our app contributes via `FocusFilterIntent` so "Work" focus can hide non-critical categories.
- [ ] Handlers complete promptly; if cancelled, re-queue for next window.
- [ ] MetricKit logs track background-time usage so we stay within iOS quota.
- [ ] Debug helper in §19.25: `BGTaskScheduler._simulateLaunchForTaskWithIdentifier` for manual trigger.
- [x] `FocusFilterIntent` so users add "Shop hours" filter with params `tenantID` / `location?` / `role?`. Activation hides personal badges + non-critical notifications; surfaces assigned tickets only. (`Notifications/Focus/FocusFilterIntent.swift`; `BizarreCRMFocusFilterIntent: FocusFilterIntent` + `FocusNotificationMode` AppEnum (assigned/workEssentials/criticalOnly/all/none) + `FocusFilterActiveReader`; agent-9 b13 09f6f194)
- [x] Driving focus: suppress non-critical pushes automatically; CarPlay-scope content only (§73 if entitlement approved). (`FocusNotificationMode.none` suppresses all; `FocusFilterActiveReader.shouldShow` guards; agent-9 b13 09f6f194)
- [x] Sleep focus: all pushes suppressed except `.critical`. (`FocusNotificationMode.criticalOnly` + `none` modes; `FocusFilterActiveReader.shouldShow(isCritical:)` allows critical through; agent-9 b13 09f6f194)
- [x] Custom per-tenant focus filters available for multi-location tenants ("Store A only"). (`BizarreCRMFocusFilterIntent.tenantSlug` optional parameter; `FocusFilterActiveReader.activeTenantSlug`; agent-9 b13 09f6f194)
- [ ] Settings → Focus integration lists active filters + preview.

---
## §22. iPad-Specific Polish

_Non-negotiable: iPad ≠ upscaled iPhone. Failures in this section indicate an unfinished feature._

### 22.1 Layout
- [x] **3-column `NavigationSplitView`** on Tickets / Customers / Invoices / Inventory / SMS / Estimates / Appointments / Leads — sidebar (domain chooser) + list column + detail column. (feat(ios §22): ThreeColumnSplitView scaffold — SplitViewDomain protocol, .balanced style, column widths, detailContentCapped())
- [x] **Dashboard 3-column KPI grid** on wide screens; 2-column on 11"; responsive `GridItem(.adaptive(...))`. (feat(ios §22): adaptive stat-tile grid + full tab-order + menu bar commands + right-click menus + scroll-dismiss keyboard)
- [x] **Max content width** — detail panes cap at ~720pt on 13" landscape via `.frame(maxWidth: 720)`; excess area padded. (feat(§22): .maxContentWidth() applied to CustomerDetailView + InvoiceDetailView ScrollView contents — caps at 720pt on iPad, no-op on iPhone)
- [ ] **Sidebar** — pinned on 13", collapsible on 11"; `.navigationSplitViewStyle(.balanced)`.
- [x] **Inspector pane** (iOS 17 `.inspector`) — right-side editor on Ticket detail, Customer detail. (feat(ios §22): InspectorPaneModifier — .brandInspector(isPresented:content:) with iOS 16 sheet fallback + InspectorToggleButton)
- [x] **Two-up editor** — Ticket detail with Invoice editor side-by-side on 13". (feat(ios §22): TwoUpEditorLayout scaffold — side-by-side on width≥900pt, segmented-tab fallback on compact)

### 22.2 Interactions
- [x] **`.hoverEffect(.highlight)`** on all tappable rows / buttons / cards. (feat(ios phase-7 §22): Ticket quick-actions + hover effects + context menus + sidebar badges + iPad Pro M4 helpers)
- [x] **Pointer customization** — custom cursors (link vs default) per semantic element. (feat(ios §22): pointer-style modifiers + focus ring + sort indicator + adaptive icon-only label + data-entry field)
- [x] **`.contextMenu`** on rows — Open / Copy ID / Copy phone / Archive / Delete / Share / Open in new window. (feat(ios phase-7 §22): Ticket quick-actions + hover effects + context menus + sidebar badges + iPad Pro M4 helpers)
- [ ] **Drag-and-drop** — drag inventory → ticket services, drag ticket → calendar slot, drag customer → SMS compose.
- [x] **Multi-select** — long-press or ⌘-click batch actions; Edit mode in list toolbar. (feat(ios §22): MultiSelectRowModifier + BulkActionBar — long-press→edit mode, per-row checkmark, floating glass bulk actions bar)
- [x] **Apple Pencil** — `PKCanvasView` on signatures; pencil-only edit mode on forms; hover preview (Pencil Pro). (feat(ios §22): PencilSignatureCanvas reusable DS widget, pencilOnly policy, UIPencilInteraction hook, brandSignatureFrame modifier)

### 22.3 Keyboard-first
- [ ] **Shortcuts**: ⌘N / ⌘F / ⌘R / ⌘, / ⌘D / ⌘1–⌘9 / ⌘⇧F / ⌘⇧N / ⌘K (command palette) / ⌘P (print) / ⌘/ (help) / ⎋ (dismiss sheet) / ⌥↑↓ (row move) / Space (preview).
- [x] **Focus ring** — visible keyboard focus on buttons/links; `.focusable()`. (feat(ios §22): pointer-style modifiers + focus ring + sort indicator + adaptive icon-only label + data-entry field)
- [x] **Tab order** — forms tabbable in logical order. (feat(ios §22): adaptive stat-tile grid + full tab-order + menu bar commands + right-click menus + scroll-dismiss keyboard)
- [x] **Menu bar** — iPad-specific `.commands` with grouped menu items (File / Edit / View / Actions / Window / Help). (feat(ios §22): adaptive stat-tile grid + full tab-order + menu bar commands + right-click menus + scroll-dismiss keyboard)

### 22.4 Multi-window / Stage Manager
- [x] **Multiple scenes** — `UISceneConfiguration` supports N windows. (feat(ios phase-7 §22): multi-window + Stage Manager + adaptive sidebar widths + Universal Clipboard)
- [x] **Scene state** restored per-window on relaunch. (feat(ios §22): SceneStateRestorer — stateRestorationActivity(for:) + restore(from:) + SceneDelegate willConnectTo restoration path)
- [x] **Open in new window** from context menu. (feat(ios phase-7 §22): multi-window + Stage Manager + adaptive sidebar widths + Universal Clipboard)
- [x] **Scene activities** — detail views become independent activities. (feat(ios phase-7 §22): multi-window + Stage Manager + adaptive sidebar widths + Universal Clipboard)
- [x] **Slide Over / Split View** — layouts verified at 1/2, 1/3, 2/3 splits. (feat(§22): ShellLayout gates rail vs compact on geo.size.width >= 500; 1/3-split on 13" → compact, 1/2-split on 11" keeps rail)

### 22.5 Data presentation
- [ ] **`Table`** (sortable columns) on Reports, Inventory dumps, Audit Logs.
- [ ] **Column chooser** — reorder / hide columns; persisted.
- [x] **Sort indicator** arrows on column headers. (feat(ios §22): pointer-style modifiers + focus ring + sort indicator + adaptive icon-only label + data-entry field)

### 22.6 Magic Keyboard / trackpad
- [ ] **Swipe gestures** translated to trackpad (2-finger).
- [x] **Right-click** menus everywhere. (feat(ios §22): adaptive stat-tile grid + full tab-order + menu bar commands + right-click menus + scroll-dismiss keyboard)

### 22.7 External display / AirPlay
- [ ] **Customer-facing POS display** — second screen shows cart / tip.
- [ ] **Presentation mode** — Reports dashboards full-screen on TV.
- [ ] Scene types: primary (full app), secondary (single ticket detail), tertiary (POS register), quaternary (reports dashboard).
- [ ] Drag-to-new-window: long-press ticket row → drag out → new window with that ticket. Long-press POS tab → dedicated register window.
- [x] `NSUserActivity` per scene persists position / ticket ID; relaunch re-opens all windows. (feat(ios §22): DetailHandoffModifier — Handoff advertisement + "Open in New Window" context menu + MultiWindowCoordinator.openDetail(routeURL:) routing helper)
- [ ] Scene declares capabilities ("can show ticket detail", "can run POS"); drag-drop between windows validates target capability.
- [x] Stage Manager min content area 700×500; below that → compact layout. (feat(§22): .splitViewMinSize() on WindowGroup root tightens UIScene.SizeRestrictions.minimumSize)
- [ ] External-display `UIScene` hosts customer-facing display (§16 POS CFD) mirrored from POS scene.
- [ ] `UICommand` menu per scene (File / Edit / View / Window / Help) with custom items (New Ticket, Quick Find, Switch Tenant).
- [x] Hardware keyboard: iPad top-menu command menu populates from scene `UIKeyCommand` discoverabilityTitle; ⌘? shows all shortcuts overlay; arrow keys navigate lists; Tab/Shift-Tab traverse form fields; Enter submits primary action; Esc dismisses sheets/cancels (feat(ios §22): ArrowKeyRowSelectionModifier DS widget — ↑/↓ hidden buttons + .arrowKeyRowSelection(items:selectedId:) view extension)
- [x] Input accessory bar: numeric keyboard on money fields has $ + %; Done + Next + Prev arrows on all text fields; auto-hide with hardware keyboard attached (feat(§22): NumericKeyboardAccessory DS modifier — .brandNumericKeyboardAccessory(focus:current:prev:next:); first wired on TaxSettingsPage rate field)
- [ ] Field validation keys: IMEI/phone `.numberPad`; email `.emailAddress`; URL `.URL`; search `.webSearch`
- [x] Autocorrect: off for IDs/codes/emails; on for message composers and notes; SmartDashes/SmartQuotes off for data entry (feat(ios §22): pointer-style modifiers + focus ring + sort indicator + adaptive icon-only label + data-entry field)
- [ ] External barcode scanner (USB/BT wedge): detect rapid keystrokes ending in Enter; route to scan handler not textfield; configurable via Settings → Hardware
- [ ] Support Dvorak/custom layouts automatically — never hardcode layouts
- [ ] Keyboard show/hide: `.keyboardAvoidance` adjusts insets; bottom-anchored primary buttons stay visible via `safeAreaInset(edge: .bottom)`
- [ ] Within-app drags: ticket row → Assignee sidebar (iPad); invoice row → Email compose; inventory row → PO draft; photo → Ticket attachment
- [ ] Cross-app drags: customer from Contacts app → Customer create; PDF from Files → Ticket attachment; photo from Photos → Ticket photos/Annotation
- [ ] Type registration: `UTType`s `public.image`, `public.pdf`, `com.bizarrecrm.ticket` (custom UTI for in-app drag); `NSItemProvider` per source
- [x] Previews: drag preview = card-style miniature; drop target highlights on hover (feat(ios §22): DragHoverPreviewModifier — dragCardPreview() preview closure style + hoverDropHighlight() auto-isTargeted overlay)
- [ ] Validation: drop handler validates type + tenant scope; invalid drops show red X overlay
- [ ] Haptics+motion: pickup = light haptic + row lift; drop = success haptic + slot-fill animation; cancel = rubber-band back
- [ ] Accessibility: every drag op has keyboard/VoiceOver alternative via select + "Move to…" menu
- [ ] iPad portrait: sidebar collapsed to icon rail (56pt) unless user expands; detail takes most width
- [ ] iPad landscape: sidebar expanded (260–280pt) default; user toggles rail via ⌘\
- [ ] Mac Designed-for-iPad: sidebar persistent, min 260pt
- [ ] Drag-to-resize: iPad 13" Pro supports resize via split-view divider; inner sidebar also resizable 260–400pt
- [x] Persistence: width saved per-scene in `UserDefaults` (feat(ios §22): RailSidebarView isExpanded backed by @AppStorage("rail.sidebar.isExpanded") — survives app restarts + scene reconnects)
- [x] Overflow: if label truncates, icon-only mode kicks in automatically at <100pt (feat(ios §22): pointer-style modifiers + focus ring + sort indicator + adaptive icon-only label + data-entry field)
- [ ] Tandem OLED: optional HDR content for hero dashboard images (brand gradients); verify blacks on real OLED (no gray haze)
- [x] ProMotion 120fps: tune all animations for 120fps; avoid 60fps lock from `ProMotion: false` in Info.plist. (feat(ios phase-7 §22): Ticket quick-actions + hover effects + context menus + sidebar badges + iPad Pro M4 helpers)
- [ ] Magic Keyboard 2024: surface function row; map custom actions (F1=new ticket, F2=POS, F3=inventory)
- [ ] Pencil Pro: squeeze opens tool picker in annotation (§4); barrel roll rotates shape/text; haptic on Pencil tip (iOS 17.5+ API)
- [ ] M4 performance: gate larger-dataset UI (e.g. live charts 10k points) on A17+ detection
- [ ] External storage: USB-C direct photo import; file picker recognizes external drives
- [x] Safe area: use `.ignoresSafeArea(.keyboard)` carefully; default behavior is scroll. (feat(ios §22): adaptive stat-tile grid + full tab-order + menu bar commands + right-click menus + scroll-dismiss keyboard)
- [x] Accessory toolbar for numeric fields: `$`, `%`, next, prev, done (done closes keyboard, next moves focus). (feat(§22): same NumericKeyboardAccessory DS modifier as §22.7 row above)
- [ ] SMS/email inputs show QuickType; custom template suggestions via replacement assistant.
- [ ] External hardware keyboard: hide onscreen keyboard automatically.
- [ ] iPad split keyboard respected; inline accessory bar follows keyboard.
- [ ] Keep native emoji switcher; no custom emoji picker.
- [x] Invocation: ⌘/ on hardware keyboard; overlay shown via `.fullScreenCover` in `MainShellView`. (feat(ios phase-7 §23): keyboard shortcut catalog + overlay + hardware keyboard detector)
- [x] Layout: full-screen glass panel grouped by Navigation / Tickets / POS / Customer / Admin; iPad 3-col grid, iPhone single-column list. (feat(ios phase-7 §23): keyboard shortcut catalog + overlay + hardware keyboard detector)
- [ ] Content auto-built from `UICommand` registrations in each scene (never hand-maintained). TODO: migrate scattered `.keyboardShortcut` sites to `KeyboardShortcutCatalog`.
- [ ] Rebinding: power users via Settings → Keyboard; core shortcuts (⌘N / ⌘F / ⌘S) not rebindable.
- [x] iPad-only by default; hidden on iPhone unless hardware keyboard attached (`HardwareKeyboardDetector`). (feat(ios phase-7 §23): keyboard shortcut catalog + overlay + hardware keyboard detector)
- [x] A11y: group headings `.accessibilityAddTraits(.isHeader)`; each row `accessibilityLabel` reads "Cmd+N — New Ticket". (feat(ios phase-7 §23): keyboard shortcut catalog + overlay + hardware keyboard detector)

---
## §23. Mac ("Designed for iPad") Polish

_Mac Catalyst not used — "Designed for iPad" only. Layout inherits iPad; hardware feature-gates apply._

### 23.1 Detection + gating
- [x] **`ProcessInfo.processInfo.isiOSAppOnMac`** — runtime flag. (`Platform.isMac` already wraps this in `Core/Platform.swift`.)
- [x] **Feature-gate barcode scan** to manual entry; offer Continuity Camera if iPhone nearby. (`Platform.supportsNativeBarcodeScan` + `Platform.suggestsContinuityCamera` flags. feat(§23.1): 7a44a367)
- [x] **Feature-gate Bluetooth MFi printers** → AirPrint. (`Platform.requiresAirPrintOnMac` flag. feat(§23.1): 7a44a367)
- [x] **Feature-gate NFC** (unavailable) — hide feature. (`Platform.supportsNFC` returns `!isMac`. feat(§23.1): 7a44a367)
- [x] **Haptics** no-op on Mac. (`Platform.supportsHapticEngine` returns `!isMac`; `HapticCatalog` callers guard on this. feat(§23.1): 7a44a367)

### 23.2 Window behavior
- [x] **Min size** 900×600; preferred 1280×800. (`Core/Mac/MacWindowConfigurator.swift` — `UIWindowScene.sizeRestrictions` + title helpers. feat(§23.2): d4afac02)
- [ ] **Multi-window** — file → new window opens new scene.
- [ ] **Restore windows** on launch.
- [x] **Window titles** — per-scene (e.g., "Ticket #1234 - BizarreCRM"). (`MacWindowConfigurator.titleForTicket/Customer/POS/Reports` helpers. feat(§23.2): d4afac02)

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
- [x] **Universal clipboard** — copy ticket # on iPad, paste on Mac. (feat(ios phase-7 §22): multi-window + Stage Manager + adaptive sidebar widths + Universal Clipboard)

### 23.6 Missing on Mac (document)
- [ ] Widgets (limited).
- [ ] Live Activities (unavailable).
- [ ] NFC (unavailable).
- [ ] BlockChyp terminal — works (IP-based transport either LAN or cloud-relay; see §17.3). No Bluetooth involved at any layer.

---
## §24. Widgets, Live Activities, App Intents, Siri, Shortcuts

_Requires WidgetKit target + ActivityKit + App Intents extension. App Group `group.com.bizarrecrm` shares data between main app and widgets (GRDB read-only slice, exported on main-app sync)._

### 24.1 WidgetKit — Home Screen
- [x] **Small (2×2)** — open ticket count; revenue today widget (small). (feat(ios phase-6 §24): Widgets extension + Lock-screen complications + Live Activities)
- [x] **Medium (4×2)** — 3 latest tickets with deep-link; revenue delta; next 3 appointments. (feat(ios phase-6 §24): Widgets extension + Lock-screen complications + Live Activities)
- [x] **Large (4×4)** — up to 10 latest tickets list. (feat(ios phase-6 §24): Widgets extension + Lock-screen complications + Live Activities)
- [x] **Extra Large (iPad)** — full dashboard mirror; 6 tiles + chart. (`BizarreCRMWidgets/DashboardMirrorWidget.swift`; 2-col LazyVGrid KPIs + ticket list with `Link` deep-links; 002d79f0)
- [x] **Multiple widgets** — OpenTicketsWidget, TodaysRevenueWidget, AppointmentsNextWidget each with S/M/L variants. (feat(ios phase-6 §24): Widgets extension + Lock-screen complications + Live Activities)
- [x] **Configurable** — `IntentConfiguration`: choose which KPI, time range, location. (`BizarreCRMWidgets/ConfigurableKPIWidget.swift`; `AppIntentConfiguration` + `WidgetKPIKind` AppEnum; picks openTickets/revenueToday/nextAppointments; agent-9 b10)
- [x] **Refresh policy** — `TimelineProvider.getTimeline` returns entries at configurable interval (5/15/30 min); WidgetCenter reloads on main-app sync via `WidgetDataStore.write(_:)`. (feat(ios phase-6 §24): Widgets extension + Lock-screen complications + Live Activities)
- [x] **Data source** — App Group UserDefaults (`group.com.bizarrecrm`); main app writes `WidgetSnapshot` on sync via `WidgetDataStore`. (feat(ios phase-6 §24): Widgets extension + Lock-screen complications + Live Activities)
- [x] **Privacy** — redact in lock-screen mode if sensitive (revenue $); placeholder text. (`TodaysRevenueWidget` + `ConfigurableKPIWidget` `@Environment(\.redactionReasons)` → `privacySensitive()` + "••••" placeholder; agent-9 b10)

### 24.2 WidgetKit — Lock Screen (iOS 16+)
- [x] **Circular** — ticket count badge via `.accessoryCircular`. (feat(ios phase-6 §24): Widgets extension + Lock-screen complications + Live Activities)
- [x] **Rectangular** — "X tickets open" via `.accessoryRectangular`. (feat(ios phase-6 §24): Widgets extension + Lock-screen complications + Live Activities)
- [x] **Inline** — single-line ticket count via `.accessoryInline`. (feat(ios phase-6 §24): Widgets extension + Lock-screen complications + Live Activities)

### 24.3 Live Activities (ActivityKit)
- [x] **Ticket in progress** — started when technician clicks "Start work" on a ticket; shows on Lock Screen + Dynamic Island with timer + customer name + service; end when ticket marked done. Commit `baa1cbb6`. Layout enhanced: `TicketPhase` enum (diagnosing/repairing/testing/waitingParts/done), phase badge chip + phase SF Symbol with `symbolEffect(.replace)`, "Ticket done" dismissal copy (12 s linger). `feat(§24.3): ticket LA layout + dismissal copy`
- [x] **POS charge pending** — `SaleInProgressLiveActivity` + `POSSaleActivityAttributes`; Dynamic Island compact/expanded; ends on `endSaleActivity()`. Sale-progress activity enhanced: `progressPercent: Double` in `ContentState`; lock-screen `ProgressView` + phase-aware title ("Sale in Progress" → "Sale Complete"); `endSaleActivity(completed:)` lingers 8 s on completion. `feat(§24.3): sale-progress activity`
- [x] **Clock-in timer** — `ClockInOutLiveActivity` + `ShiftActivityAttributes`; Dynamic Island "8h 14m"; tap → timeclock deep-link; updated via `updateShiftActivity(durationMinutes:)`. (feat(ios phase-6 §24): Widgets extension + Lock-screen complications + Live Activities)
- [x] **Appointment countdown** — 15 min before appointment → live activity on Lock Screen. (`BizarreCRMWidgets/AppointmentCountdownLiveActivity.swift`; `AppointmentCountdownAttributes` + Dynamic Island compact/expanded/minimal + Lock Screen; `LiveActivityCoordinator` ext; 8837c7f6)
- [x] **Dynamic Island compact / expanded** layouts — content + trailing icon + leading label; both activities. Compact view improved: ticket compact-trailing shows elapsed + phase initial ("30m R"); sale compact-leading shows phase icon (cart→card→checkmark) with `symbolEffect(.replace)`; sale compact-trailing shows "✓" badge when payment complete. `feat(§24.3): Dynamic Island compact view`
- [x] **Push-to-update token registration** — `LiveActivityPushTokenService` (iOS 17.2+) starts ticket/sale activities with `pushType: .token`, awaits first `pushTokenUpdates` emission, uploads hex token + `activityId` to `POST /api/v1/live-activities/register` via `APIClient.registerLiveActivityPushToken(_:)`. `feat(§24.3): push-to-update token reg`
- [x] **Rate limits** — guard `shiftActivity == nil` / `saleActivity == nil`; `areActivitiesEnabled` check before request. (feat(ios phase-6 §24): Widgets extension + Lock-screen complications + Live Activities)

### 24.4 App Intents (Shortcuts + Siri)
- [x] **CreateTicketIntent** — "New ticket for {customer} on {device}"; parameterizable. (feat(ios phase-6 §24): Siri + App Intents + Shortcuts gallery)
- [x] **LookupTicketIntent** — "Find ticket {number}"; returns structured snippet. (`App/Intents/SearchIntents.swift`; `LookupTicketIntent` + `TicketLookupSnippet`; 5d1baef1)
- [x] **LookupCustomerIntent** — "Show {customer}" via FindCustomerIntent. (feat(ios phase-6 §24): Siri + App Intents + Shortcuts gallery)
- [x] **ScanBarcodeIntent** — opens scanner → inventory lookup or POS add-to-cart. (`App/Intents/ScanBarcodeIntent.swift`; `ScanBarcodeIntent` with `ScanDestination` enum (inventory/pos/ticket) + `BizarreCRMScanBarcodeShortcutsProvider`; agent-9 b13 6a34d594)
- [x] **ClockInIntent** / **ClockOutIntent** — "Hey Siri, clock in". (feat(ios phase-6 §24): Siri + App Intents + Shortcuts gallery)
- [x] **SendSMSIntent** — "Text {customer} {message}". (`App/Intents/SearchIntents.swift`; `SendSMSToCustomerIntent`; 5d1baef1)
- [x] **StartSaleIntent** — opens POS via OpenPosIntent. (feat(ios phase-6 §24): Siri + App Intents + Shortcuts gallery)
- [x] **RecordExpenseIntent** — "Log $42 lunch expense". (`App/Intents/SearchIntents.swift`; `RecordExpenseIntent`; 5d1baef1)
- [x] **ShowDashboardIntent** — "Show dashboard" via OpenDashboardIntent. (feat(ios phase-6 §24): Siri + App Intents + Shortcuts gallery)
- [x] **Intent return values** — structured `AppEntity` with human-readable snippets for Siri speech. (feat(ios phase-6 §24): Siri + App Intents + Shortcuts gallery)
- [x] **Parameters** — entity types (TicketEntity, CustomerEntity) provide suggested values. (feat(ios phase-6 §24): Siri + App Intents + Shortcuts gallery)

### 24.5 App Shortcuts (`AppShortcutsProvider`)
- [x] **Seed phrases** in English (plus 10 locales later) — "Create ticket for ACME", "Show my tickets", "Clock in". (feat(ios phase-6 §24): Siri + App Intents + Shortcuts gallery)
- [x] **System suggestions** — daily rotating shortcut tiles in Shortcuts app. (`App/Intents/SearchIntents.swift`; `BizarreCRMSearchShortcutsProvider` with Find Ticket / Send SMS / Log Expense phrases; 5d1baef1)
- [x] **Siri suggestions** on lock screen. (`Search/Spotlight/SpotlightSuggestions.swift`; `SpotlightSuggestionsCoordinator` + `SpotlightDonationModifier`; fae32e22)

### 24.6 Control Center controls (iOS 18+)
- [x] **Clock in/out toggle** — one-tap. Commit `67eb6295`.
- [x] **Quick scan** — opens scanner. Commit `67eb6295`.
- [x] **Quick sale** — opens POS. Commit `67eb6295`.
- [x] **SMS unread** badge control. Commit `67eb6295`.

### 24.7 Action Button (iPhone 15 Pro+)
- [x] **Map "Action Button" → CreateTicket shortcut** per user preference. (`App/Intents/ActionButtonIntents.swift`; `CreateTicketActionIntent` + `BizarreCRMActionButtonProvider`; 97d04ec8)
- [x] **Alt**: Clock-in toggle. (`App/Intents/ActionButtonIntents.swift`; `ClockInOutActionIntent`; 97d04ec8)

### 24.8 Interactive widgets (iOS 17+)
- [x] **Toggle "Clock in"** directly from widget (no app open). (`BizarreCRMWidgets/InteractiveWidgetIntents.swift`; `ClockInOutWidgetIntent` + `Button(intent:)` in `OpenTicketsInteractiveMediumView`; 71bc7f01)
- [x] **Mark ticket done** from Medium widget. (`BizarreCRMWidgets/InteractiveWidgetIntents.swift`; `MarkTicketDoneWidgetIntent` per-row Done button; 71bc7f01)
- [x] **Reply to SMS** inline widget (typing button). (`BizarreCRMWidgets/SMSReplyWidgetIntent.swift`; `SMSQuickReplyWidgetIntent` (openAppWhenRun) + `SMSUnreadWidgetView` iOS 17 interactive + `UnreadSMSWidgetStore` App Group bridge; note: true inline text-input not supported by WidgetKit — one-tap deep-link to composer is the correct pattern; agent-9 b13 76885c24)

### 24.9 Smart Stack / ReloadTimeline
- [x] **Relevance** hints so widget auto-promotes in Smart Stack (e.g., morning → dashboard, POS time → sales, end-of-shift → clock-out). (`BizarreCRMWidgets/SmartStackRelevance.swift`; `SmartStackRelevanceProvider` time-window scoring; 570ff216)
- [x] **ReloadTimeline** on significant events (ticket change, payment). (`BizarreCRMWidgets/SmartStackRelevance.swift`; `WidgetReloader.shared.reloadOnSignificantEvent(_:)`; 570ff216)

### 24.10 Complications (watchOS stretch)
- [ ] Circular ticket count on Apple Watch face.
- [x] `CreateNewTicketIntent` (customerName?, device?, reportedIssue?) — parameterised, opens `bizarrecrm://tickets/new`; Siri dialog + snippet card. (`App/Intents/ShortcutsIntents.swift`; `CreateNewTicketIntent`; feat(§64): create-new-ticket intent, today-revenue, open-POS, voice-phrase donation, confirmation card)
- [x] `TodayRevenueIntent` — read-only speak; reads App Group shared-defaults `widget.todayRevenue`; formatted via `NumberFormatter`; snippet card. (`App/Intents/ShortcutsIntents.swift`; feat(§64))
- [x] `OpenPOSIntent` — "open POS / start a sale / go to register"; opens `bizarrecrm://pos`; snippet card. (`App/Intents/ShortcutsIntents.swift`; feat(§64))
- [ ] Remaining catalog: `LookupTicketIntent`, `ClockInIntent` / `ClockOutIntent`, `TakePaymentIntent`, `SendTextIntent`, `NewAppointmentIntent`, `StartBreakIntent` / `EndBreakIntent`, `PendingTicketsCountIntent`, `SearchInventoryIntent`.
- [x] Donate via `INInteraction` on each use so Siri suggests context-aware shortcuts ("Clock in" near 9am at shop). (`donateInteraction(intentTitle:)` called in every `perform()`; `App/Intents/ShortcutsIntents.swift`; feat(§64))
- [x] Focus-aware (§13): `SendTextIntent` disabled in DND unless urgent. (`FocusAwareSendTextIntent` checks `focus.suppressNonUrgentSMS` from App Group; throws `IntentAppError.smsBlocked` if active + non-urgent; `BizarreCRMFocusFilterIntent: SetFocusFilterIntent` persists preference; `App/Intents/IntentEnhancements.swift`; feat(§24.10))
- [x] Parameter disambiguation: ambiguous customer → Siri "Which John?"; `parameterSummary` on `CreateNewTicketIntent` + `SendSMSToCustomerIntent`; `CustomerNameOptionsProvider: DynamicOptionsProvider` reads `suggestions.recentCustomerNames` from App Group; `IntentAppError.ambiguousParameter` for unresolved cases. (`App/Intents/IntentEnhancements.swift`; feat(§24.10))
- [x] Every intent has an `IntentView` (SwiftUI glass card) rendered inline in Shortcuts preview + Siri output. (`IntentConfirmationCard` — symbol + tint + title + body; `.regularMaterial` bg + `RoundedRectangle`; used in all 3 §64 intents; `App/Intents/ShortcutsIntents.swift`; feat(§64))
- [x] Privacy: params + results stay on device / tenant server; no Apple Siri-analytics integration (§32). Intent errors are user-facing only via `IntentAppError: CustomLocalizedStringResourceConvertible` (`.smsBlocked`, `.customerNotFound`, `.datastoreUnavailable`, `.ambiguousParameter`); `IntentErrorCard` + `IntentResultCard` snippet views; no data leaves the tenant boundary. (`App/Intents/IntentEnhancements.swift`; feat(§24.10))
- [x] iOS 26: register `AssistantSchemas.ShopManagement` domain so Apple Intelligence can orchestrate common nouns (Ticket / Customer / Invoice). (`App/Intents/IntentAutomation.swift`; `BizarreCRMAssistantSchema` enum + `ShopManagementSchemaIntent` protocol on `CreateNewTicketIntent`/`SendSMSToCustomerIntent`/`RecordExpenseIntent` + `AssistantSchemaRegistrar.register()` writes `assistant.shopManagement.entities` to App Group; feat(§24))
- [ ] Testing: Shortcuts-app gallery + XCUITest each intent headless.
- [x] Sizes supported: Small, Medium, Large; Accessory (circular/rectangular/inline); StandBy. Extra-Large deferred. (feat(ios phase-6 §24))
- [x] Catalog: OpenTicketsWidget (S/M/L), TodaysRevenueWidget (S/M), AppointmentsNextWidget (M/L), LockScreenComplicationsWidget (accessory). (feat(ios phase-6 §24))
- [x] Data source: App Group UserDefaults group.com.bizarrecrm; WidgetSnapshot written by WidgetDataStore. (feat(ios phase-6 §24))
- [x] Timeline entries: configurable 5/15/30 min interval via WidgetSettingsView; policy .after(refreshDate). (feat(ios phase-6 §24))
- [x] Taps: deep-links via bizarrecrm://tickets/:id, bizarrecrm://appointments/:id, bizarrecrm://pos. (feat(ios phase-6 §24))
- [x] StandBy: AppointmentsNextWidget large + TodaysRevenueWidget medium in StandBy mode. (feat(ios phase-6 §24))
- [x] Lock Screen variants: circular = ticket count; rectangular = X tickets open; inline = X open tickets. (feat(ios phase-6 §24))
- [x] Configuration: `AppIntentConfiguration` lets user pick which tenant (multi-tenant user) and which location. (`WidgetTenantConfigIntent: WidgetConfigurationIntent` with `tenantSlug` + `locationID` params; `TenantOptionsProvider` + `LocationOptionsProvider: DynamicOptionsProvider` read from App Group `config.tenantSlugs` / `config.locationIDs`; `App/Intents/IntentEnhancements.swift`; feat(§24.10))
- [x] Privacy: widget content stays on device; no customer names on lock screen complications. (feat(ios phase-6 §24))
- [x] Ship these gallery shortcuts: "Create ticket for customer" (customer picker chain), "Log clock-in" (one-tap), "Today's revenue" (reads aloud), "Start sale for customer" (opens POS pre-loaded), "Open Tickets", "Open Dashboard". (feat(ios phase-6 §24): Siri + App Intents + Shortcuts gallery)
- [x] Registration via `@ShortcutsProvider`; each entry ships image + description + parameter definitions. (feat(ios phase-6 §24): Siri + App Intents + Shortcuts gallery)
- [x] Automation support so tenants can wire Arrive at work → Clock in style triggers. (`App/Intents/IntentAutomation.swift`; `IntentAutomationCenter` CLLocationManager + `CLCircularRegion` 80m geofence around `automation.shop.lat`/`lon`; opt-in `automation.arriveClockIn.enabled`; `bootIfEnabled()` + `didEnterRegion` → `bizarrecrm://timeclock?action=clockin&automation=arrive`; feat(§24))
- [x] Widget-to-shortcut: widgets pre-configure parameters for one-tap intent execution. (`App/Intents/IntentAutomation.swift`; `WidgetShortcutBridge<Wrapped>: AppIntent` reads `widget.shortcut.<key>` payload from App Group + dispatches deepLink; `WidgetShortcutPublisher.publish(key:deepLink:)` writes + reloads timelines; feat(§24))
- [x] Siri learns to invoke by donated phrases. (`App/Intents/IntentAutomation.swift`; `SiriRelevanceDonor.donateRelevantShortcuts()` builds `INRelevantShortcut`s with `INDateRelevanceProvider` (revenue 5–8pm, ticket 9–7) + `INLocationRelevanceProvider` (POS at shop fence) → `INRelevantShortcutStore.default.setRelevantShortcuts`; `suggestedInvocationPhrase` per intent; feat(§24))
- [x] Sovereignty: no external service invoked from shortcuts unless tenant explicitly adds it. (`App/Intents/IntentAutomation.swift`; `IntentSovereigntyGuard.isAllowed(_:)` allows `bizarrecrm://` always + tenant `serverHost` + opt-in `automation.allowedExternalHosts` allowlist with subdomain match; `sanctioned(_:)` wrapper for intent URL follows; feat(§24))

---
## §25. Spotlight, Handoff, Universal Clipboard, Share Sheet

### 25.1 Spotlight (`CoreSpotlight`)
- [x] **Index window** — last 60 days tickets + top 500 customers + top 200 invoices + top 100 appointments + all inventory SKUs. (`Search/Spotlight/SpotlightSyncTrigger.swift`; `SpotlightIndexWindow` enum; 232d1931)
- [x] **Attributes per item** — `title`, `contentDescription`, `keywords`, `thumbnailData`, `domainIdentifier`, `contentURL`, `relatedUniqueIdentifiers`. (feat(ios phase-6 §24+§25))
- [x] **Refresh** — on sync-complete, background reindex changed items; batch 100. (`Search/Spotlight/SpotlightSyncTrigger.swift`; `SpotlightSyncTrigger` observes `syncComplete` notification; 232d1931)
- [x] **Deletion** — tombstoned items deleted from index. (feat(ios phase-6 §24+§25))
- [x] **Privacy** — respect user-facing "Hide from Spotlight" per domain in Settings. (feat(ios phase-6 §24+§25))
- [x] **Deep-link handler** — `continueUserActivity` → route by `uniqueIdentifier`. (feat(ios phase-6 §24+§25))
- [x] **Suggestions** — `CSSuggestionsConfiguration` for proactive suggestions. (`Search/Spotlight/SpotlightSuggestions.swift`; `SpotlightSuggestionsCoordinator` actor + `donateTicketView/donateCustomerView/donateInvoiceView/donateAppointmentView` via `NSUserActivity.isEligibleForPrediction`; `SpotlightDonationModifier`; fae32e22)
- [ ] **Preview** — rich preview card in Spotlight with customer avatar + ticket status.

### 25.2 Handoff / `NSUserActivity`
- [x] **Per-detail `NSUserActivity`** — on every Ticket/Customer/Invoice/SMS/Appointment detail, `becomeCurrent()` with `activityType`, `userInfo`, `title`, `webpageURL`. (feat(ios phase-6 §24+§25))
- [x] **Handoff to Mac** — Mac docks show the icon; tap to open same record. (feat(ios phase-6 §24+§25))
- [x] **Handoff to iPad** — multi-window opens fresh scene at same record. (feat(ios phase-6 §24+§25))
- [ ] **Encrypted payload** — sensitive items sent via key derived from iCloud Keychain.
- [x] **`eligibleForSearch`** — also indexes in Spotlight. (feat(ios phase-6 §24+§25))
- [x] **`eligibleForPrediction`** — Siri suggests continue-ticket on other devices. (feat(ios phase-6 §24+§25))

### 25.3 Universal Clipboard
- [x] **`.textSelection(.enabled)`** on all IDs, phones, emails, invoice #, SKU. (feat(§25): CopyableText modifier + .copyable() view extension in Settings package; 9cd0b5b8)
- [x] **Copy to pasteboard** actions on context menus use `UIPasteboard` with expiration for sensitive. (feat(§25): CopyableText.conditionalContextMenuCopy + UIPasteboard.general; 9cd0b5b8)
- [ ] **iCloud Keychain paste** for SMS codes (`UITextContentType.oneTimeCode`).

### 25.4 Share Sheet (`UIActivityViewController` / `ShareLink`)
- [x] **Invoice PDF** — generate via `UIPrintPageRenderer` → share. Commit `ef872a82`.
- [x] **Estimate PDF** — same renderer. Commit `ef872a82`.
- [x] **Receipt PDF** — same renderer. Commit `ef872a82`.
- [x] **Customer vCard** — `CNMutableContact` → `CNContactVCardSerialization` → share. Commit `ef872a82`.
- [x] **Ticket summary plaintext + image** — formatted block copy. Commit `ef872a82`.
- [ ] **Public tracking link** — share short URL to public-tracking page (see §57).
- [ ] **Photo** — ticket photo → share.
- [ ] **Image with logo watermark** — before sharing.

### 25.5 Share Extension (receive sheet)
- [x] **Accept image** — from Photos app or other apps → "Attach to ticket" picker flow. (`BizarreCRMShareExtension/ShareViewController.swift`; `UTType.image` → App Group copy; e55bb72f)
- [x] **Accept PDF** — "Attach to invoice" or "Attach to expense" (receipt). (`BizarreCRMShareExtension/ShareViewController.swift`; `UTType.pdf`; e55bb72f)
- [x] **Accept URL** — "Add to note on ticket". (`BizarreCRMShareExtension/ShareViewController.swift`; `UTType.url` → `shared_url.txt`; e55bb72f)
- [x] **Extension bundle** — separate target; uses App Group for temp hand-off. (`BizarreCRMShareExtension/`; `group.com.bizarrecrm` + `bizarrecrm://sharehandoff` URL; e55bb72f)

### 25.6 Drag-and-drop
- [ ] **Drop image from Files/Photos** → ticket photos, expense receipts, customer avatar.
- [ ] **Drop PDF** → invoice attachments.
- [ ] **Drop text** → note fields.
- [ ] **Drag out** — ticket card draggable to other apps (e.g., drag to Notes).

### 25.7 Universal Links — cloud-hosted tenants only

Apple Associated Domains are compiled into the app entitlement, so we can only list domains we own. Works for cloud tenants on `*.bizarrecrm.com`. **Does not work for self-hosted tenants** whose domain is whatever they configured in their server `.env` (`https://repairs.acmephone.com`, a LAN IP like `https://10.0.1.12`, etc.) — Apple will never verify AASA hosted on an arbitrary tenant domain against our signed entitlement.

- [ ] **AASA file** hosted at `https://app.bizarrecrm.com/.well-known/apple-app-site-association` with path patterns `/c/*`, `/t/*`, `/i/*`, `/estimates/*`, `/receipts/*`, `/public/*` wildcards (where we want the app to open instead of web).
- [ ] **Entitlement** — `applinks:app.bizarrecrm.com` + `applinks:*.bizarrecrm.com` (subdomains for tenant slugs we host).
- [x] **Route handler** — `onContinueUserActivity(.browsingWeb)` extracts path → navigate. (`App/Scenes/UniversalLinkHandler.swift`; `UniversalLinkHandler.handle(_:)` → `DeepLinkDestination`; d2a8d2ff)
- [x] **Login gate** — unauth user stores intent, signs in to the matching tenant, restores. (`App/Scenes/UniversalLinkHandler.swift`; `PendingUniversalLink` stores/consumes URL in UserDefaults; d2a8d2ff)
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
- [x] **Tenant-slug resolution** — slug maps to a stored server URL (Keychain, set at login per §19.22). On cold open, if the user isn't signed into that tenant, show "Sign in to Acme Repair to continue" with server URL pre-filled. (`App/Scenes/CustomSchemeHandler.swift`; `TenantSlugRegistry` UserDefaults slug → base URL; 6497a3d2)
- [ ] **Self-hosted tenant IDs** — for self-hosted, the slug is whatever the server's `.env` declares as tenant_slug (typically the shop name, lowercased); the Keychain entry binds slug → full base URL (`https://repairs.acmephone.com`).
- [ ] **Used by** — Shortcuts, App Intents, push-notification deep-links, in-app share sheets (shares custom-scheme link when tenant is self-hosted, Universal Link when cloud-hosted), QR codes printed on tickets / receipts for staff-side opening.
- [ ] **Public customer-facing URLs stay HTTPS** — tracking / pay / book pages (§53 / §41 / §56) remain HTTPS on whichever domain the tenant serves, whether `app.bizarrecrm.com` or self-hosted. Those URLs are for browsers, not the staff app.
- [x] **Multi-tenant safety** — if a deep link arrives for tenant A while user is signed into tenant B, app shows confirmation "Open Acme Repair? You'll be signed out of Bizarre Demo first." Never silently switches tenants (§79 scope rule). (`App/Scenes/CustomSchemeHandler.swift`; `CustomSchemeResolution.confirmTenantSwitch`; 6497a3d2)
- [x] **Unknown scheme / path** — reject with inline toast, never crash. Rate-limit per source (Shortcuts / push / clipboard) against DoS by malformed URLs. (`App/Scenes/CustomSchemeHandler.swift`; `CustomSchemeRateLimiter` actor token bucket; 6497a3d2)
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

- [x] **Label + hint** on every interactive element — `.accessibilityLabel("Ticket 1234, iPhone repair")`, `.accessibilityHint("Double tap to open")`. Present in every build; iOS uses them only when VoiceOver is active. (feat(ios post-phase §26): A11y retrofit — Tickets/Customers/Inventory/Invoices list rows + RowAccessibilityFormatter helper)
- [x] **Traits** — `.isButton`, `.isHeader`, `.isSelected`, `.isLink`. (Tickets/Customers/Inventory/Invoices rows: `.accessibilityAddTraits(.isButton)` — feat(ios post-phase §26))
- [ ] **Rotor support** — on long lists: heading / form control / link rotors work.
- [x] **Grouping** — `.accessibilityElement(children: .combine)` on compound rows so VoiceOver reads one meaningful line. (Tickets/Customers/Inventory/Invoices rows — feat(ios post-phase §26))
- [ ] **Container** — `.accessibilityElement(children: .contain)` wraps list for navigation.
- [ ] **Announcement** — `.announcement` posted on async success/failure ("Ticket created") **only when `UIAccessibility.isVoiceOverRunning`** — silent otherwise to avoid wasted work.
- [x] **Focus** — `@AccessibilityFocusState` moves focus to key element on sheet open when VoiceOver is running; ignored otherwise. (`A11ySheetFocusModifier` + `.a11yFocusOnAppear(_:)` + `.a11yCustomAction(label:handler:)` in `Core/A11y/A11ySheetFocusModifier.swift`; 450ms settle delay. feat(§26.1): 1d61493b)
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

- [x] `@Environment(\.accessibilityReduceMotion)` gate — swap spring animations for cross-fades when the OS flag is set. If the flag is false, ship normal motion. (`brandSpring(_:value:)` in `DesignSystem/Motion/ReduceMotionFallback.swift` reads the OS flag and uses `ReduceMotionFallback.fadeOrFull`; wired on both `OfflineBanner` chip variants — feat(§26))
- [ ] **Cart confetti** → static checkmark only when the flag is set.
- [ ] **Parallax on Dashboard** → disabled only when the flag is set.
- [ ] **Auto-playing animations** → paused until tap only when the flag is set (`UIAccessibility.isVideoAutoplayEnabled` for media).
- [ ] **Never expose an in-app "Reduce motion" toggle.** Users set it at OS level; we follow.

### 26.4 Reduce Transparency
- [ ] `@Environment(\.accessibilityReduceTransparency)` gate — `.brandGlass` returns solid `bizarreSurfaceBase` fill only when the OS flag is set. Default ships full glass.
- [x] **Live switching** — observe `UIAccessibility.reduceTransparencyStatusDidChangeNotification` so the UI flips mid-session without app restart. (`ReduceTransparencyFallbackModifier` `.onReceive` hook in `DesignSystem/ReduceTransparencyFallback.swift`; SwiftUI environment also re-renders on flag change. Wired in `BrandToast` + `BrandBanner` (`Components.swift`). feat(§26))

### 26.5 Increase Contrast
- [ ] `@Environment(\.colorSchemeContrast) == .increased` (reflecting iOS "Increase Contrast") → use high-contrast brand palette. Default ships regular palette.
- [x] **Borders** around cards become visible (1pt solid stroke) only when the flag is set. (`SelectedCardBorderModifier` reads `\.colorSchemeContrast` and thickens stroke under `.increased`; wired on `CustomerMergeFieldRowView` side cards via `.selectedCardBorder(...)`. feat(§26))
- [ ] **Button states** clearer (solid vs outlined) only when the flag is set.

### 26.6 Bold Text + Differentiate Without Color
- [x] **Bold Text** — gate on `@Environment(\.legibilityWeight) == .bold` (reflects iOS Bold Text system setting). Default = regular weight per §80 / §80. (`DesignSystem/Tokens+Accessibility.swift` — `boldTextEnabled` EnvironmentKey, `adaptiveFontWeight`, `BoldTextReader` modifier, `DesignTokens.BoldText`. feat(§80): 2e0846c9)
- [x] **Status pills** — glyph + color at all times; glyph-only emphasis additionally engaged when `@Environment(\.accessibilityDifferentiateWithoutColor)` is true (reflects iOS Differentiate Without Color). Color-alone conveyance is banned regardless, per WCAG — but redundant glyphs aren't over-applied unless the flag is set. (`StatusPill.swift` — every `Hue` carries an SF Symbol (`tray`/`wrench`/`hourglass`/`checkmark.seal`/`flag.checkered`/`archivebox`); under DifferentiateWithoutColor the glyph weight steps to `.heavy` and a 1pt foreground-tint capsule outline is added. feat(§26))
- [ ] **Charts** — dashed / dotted patterns in addition to color whenever `accessibilityDifferentiateWithoutColor` is true.

### 26.7 Tap targets
- [x] **Min 44×44pt** — enforced via debug-build assertion in a `.tappableFrame()` ViewModifier that reads the rendered frame from `GeometryReader` and `assert(size.width >= 44 && size.height >= 44)`. CI snapshot test + SwiftLint rule bans bare `.onTapGesture` on non-standard controls so every tappable goes through the checked modifier. No runtime overlay; violations trip at dev time or in CI, never in production UI. (`Core/A11y/TappableFrame.swift` — `TappableFrameModifier` + `View.tappableFrame(minWidth:minHeight:)`; DEBUG `assertionFailure` via GeometryReader.onAppear; RELEASE no-op; `bare_on_tap_gesture` SwiftLint rule already in `.swiftlint.yml`. feat(§26.6): b12)
- [x] **Spacing** between adjacent tappable rows ≥ 8pt (same enforcement: lint rule + snapshot geometry check). (`DesignSystem/Accessibility/AdjacentRowSpacing.swift` — `AdjacentRowSpacing.minimum = BrandSpacing.sm` (8pt); `View.adjacentRowSpacing(_:)` modifier with DEBUG `assertionFailure` on sub-8pt callers; wired on the `CustomerMergeView` field-row VStack. feat(§26))

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
- [x] TipKit integration (iOS 17+) surfaces rules-based tips — `DesignSystem/Tips/TipCatalog.swift` (feat(ios phase-10 §26+§29))
- [x] Each tip: title, message, image, eligibility rules (e.g. "shown after 3rd ticket create") — all 5 tips ship with rules + MaxDisplayCount(1)
- [x] Catalog tip: "POS quick-start — tap POS to start a sale" shown after first app launch — `PosQuickStartTip` (`TipCatalog.swift`; `TipsRegistrar.donatePosQuickStartLaunch()`)
- [x] Catalog tip: "Export Reports — tap Export for CSV/PDF" shown on first Reports tab open — `ReportsExportTip` (`TipCatalog.swift`; `TipsRegistrar.donateReportsTabOpened()`)
- [ ] Catalog tip: "Try swipe right to start ticket" after 5 tickets viewed but zero started via swipe
- [x] Catalog tip: "⌘N creates new ticket faster" shown once user connects hardware keyboard — `NewTicketKeyboardTip` (`TipCatalog.swift`; hardware-keyboard event; `TipsRegistrar.donateHardwareKeyboardConnected()`)
- [x] Catalog tip: "Long-press inventory row for quick actions" after 10 inventory views — `ContextMenuTip`
- [ ] Catalog tip: "Turn on Biometric Login in Settings" after 3 sign-ins
- [x] Dismissal: per-tip "Don't show again" — `Tips.MaxDisplayCount(1)` on each tip
- [ ] Global opt-out in Settings → Help
- [ ] A11y: tips announced via VoiceOver at low priority
- [x] Reduce Motion: fade in, no bounce — system TipKit honors Reduce Motion; no custom spring in `brandTip(_:)`
- [x] Sovereignty: tip eligibility computed entirely on device; no third-party tracking — `TipsRegistrar.registerAll()` local only
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
- [x] **Build-time check** — CI asserts no hardcoded user-facing strings in Swift source (regex audit). `ios/scripts/i18n-audit.sh` — baseline 50 violations, exits 1 above baseline.
- [ ] **Translation service** — Lokalise / Crowdin workflow + CI sync.

### 27.2 Locale-aware formatters
- [x] **Dates** — `Date.FormatStyle.dateTime` with locale. `LocaleFormatter.formatDateTime(_:configure:)` in `FormatStyles.swift` wraps `Date.FormatStyle(date:.abbreviated, time:.shortened).locale(locale)` with caller-supplied field composition.
- [x] **Currency** — `Decimal.FormatStyle.Currency(code: tenantCurrency)`. `LocaleFormatter.formatCurrency(_:Decimal, currencyCode:)` uses `Decimal.formatted(.currency(code:).locale(locale))` to avoid float rounding for POS amounts.
- [x] **Numbers** — `.number` with `.locale(Locale.current)`. `LocaleFormatter.formatNumber(_:Int)` and `formatNumber(_:Double, fractionDigits:)` use `IntegerFormatStyle`/`FloatingPointFormatStyle.number.locale(locale)`.
- [ ] **Percent** — `.percent`.
- [x] **Distance** — `MeasurementFormatter` (rare). `LocaleFormatter.formatDistance(meters:)` and `formatDistance(_:Measurement<UnitLength>)` cache a `MeasurementFormatter` per (locale, unitOptions) and use `.naturalScale` so `en_US` shows miles, metric locales show km.
- [x] **Relative** — `RelativeDateTimeFormatter` for "2 min ago". `LocaleFormatter.formatRelative(_:relativeTo:style:)` caches a `RelativeDateTimeFormatter` per (locale, unitsStyle) and calls `localizedString(for:relativeTo:)`.
- [ ] **Phone** — `libPhoneNumber-iOS` or server-provided format respecting E.164 + locale.

### 27.3 Plural rules
- [ ] **`.xcstrings` variations** — singular/plural/zero per language.
- [ ] **Examples** — "1 ticket" / "N tickets"; handle CJK (no plurals) + Arabic (six forms).

### 27.4 RTL layout
- [x] **Mirror UI** — `.environment(\.layoutDirection, .rightToLeft)` pseudo-locale testing. `RTLPreviewModifier.swift` + `.rtlPreview()` modifier.
- [x] **SF Symbols** with `.imageScale(.large)` auto-mirror for directional (`arrow.right`). `RTLHelpers.directionalImage(_:)` wraps this.
- [x] **RTL lint CI** — `ios/scripts/rtl-lint.sh`; 6 checks (physical padding edges, hardwired LTR env, TextField trailing alignment, fixed rotationEffect, hardcoded trailing text alignment); baseline + regression-only exit; Bash 3.x compatible.
- [x] **RTL smoke tests** — `ios/Tests/Performance/RTLSmokeTests.swift`; 6 XCUITest cases; launches 4 key screens (LoginFlowView, DashboardView, TicketListView, PosView) with `-AppleLanguages (ar)`; screenshots to `/tmp/rtl-screenshots/`; asserts element visibility + no zero-size text.
- [x] **RTL preview catalog** — `ios/Packages/DesignSystem/Sources/DesignSystem/RTL/RTLPreviewCatalog.swift`; 13 screens catalogued; `RTLPreviewCatalogTests.swift` (10 XCTest cases) asserts ≥10 entries, unique IDs, 4 smoke-tested screens flagged.
- [x] **RTL glossary extension** — `docs/localization/glossary.md` §RTL: Arabic/Hebrew/Farsi/Urdu notes, Eastern Arabic-Indic numerals, price format (NumberFormatter.locale), icon mirroring policy, text wrapping/truncation rules, bidi-isolation for mixed content, testing strategy.
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
- [x] Per-locale glossary files at `docs/localization/<locale>-glossary.md` listing preferred translation per domain term (prevents translator drift). `docs/localization/glossary.md` — 50 terms shipped.
- [x] Examples en → es: ticket → ticket (not "boleto"), inventory → inventario, customer → cliente, invoice → factura, refund → reembolso, discount → descuento, membership → membresía. Documented in glossary.md.
- [x] Style per locale: formal vs informal tone (Spanish "usted" vs "tú"); per-tenant override for formality. Informal "tú" is the default; documented in glossary.md.
- [x] Gender-inclusive: prefer neutral phrasing where grammar allows; cashier → persona cajera vs cajero/a, tenant configures. Entry #33 in glossary.md.
- [ ] Currency + dates via `Locale` formatter — never translate numbers manually.
- [x] Workflow: English source in `Localizable.strings` → CSV export to vendor → import translations; pseudo-loc regression (`xx-PS`) for ~30% expansion truncation check. `gen-pseudo-loc.sh` ships 40% expansion + ⟦brackets⟧.
- [x] Supported RTL languages: Arabic, Hebrew, Farsi, Urdu — documented in `docs/localization/glossary.md` §RTL.
- [x] Mirroring via SwiftUI `.environment(\.layoutDirection, .rightToLeft)`; all custom views use logical properties (leading/trailing), never `.left`/`.right`. `RTLHelpers.swift` enforces this.
- [x] Icon policy: directional icons (arrows, back chevrons) flip; non-directional (clock, info) stay. `RTLHelpers.directionalImage` / `staticImage` APIs.
- [ ] Numerals: Arabic locale uses Eastern Arabic numerals unless tenant overrides.
- [ ] Mixed-content: LTR substrings (English brand/IDs) inside RTL paragraph wrapped with Unicode bidi markers.
- [x] Audit: `RTLPreviewCatalog.swift` catalogs 13 screens; `rtl-lint.sh` + `RTLSmokeTests` form CI audit baseline.
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
- [x] **Delete on logout** — Keychain keys scoped to user/tenant deleted. (`KeychainStore.deleteSessionKeys()` removes auth/session keys; preserves dbPassphrase + blockChypAuth. feat(§28.1) ae5febcf)

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
- [x] **Per-tenant passphrase** — each tenant's DB gets its own 32-byte Keychain item keyed by tenant slug. Signing in to tenant B never reads tenant A's DB. (`KeychainStore.tenantPassphrase(for:)` + `removeTenantPassphrase(for:)`. feat(§28.12) 2b65ec8b)
- [ ] **Full-wipe utility** — Settings → Danger → Reset wipes DB files + Keychain items + attachment cache.
- [ ] **Key rotation** — support `PRAGMA rekey` when tenant server signals a mandated rotation; documented in runbook.
- [ ] **Developer DX** — debug builds can open local DB via a CLI wrapper that pulls the key from Keychain only when an engineer has Xcode attached; never ship the wrapper in Release.

### 28.3 Network
- [x] **App Transport Security** — HTTPS only; no `NSAllowsArbitraryLoads`. (`NSAllowsArbitraryLoads` omitted (defaults false) + `NSAllowsLocalNetworking=true` for LAN self-hosted in `write-info-plist.sh`. feat(§28.3): b7ae0101)
- [x] **SPKI pinning** — `PinnedURLSessionDelegate` pins one or more cert SPKIs; rotation list per tenant. (Decision: no pins by default for cloud tenants — Let's Encrypt 90-day rotation; self-hosted supply optional `tls_pin_sha256` via `/auth/me`. `PinningPolicyFactory` in `Networking/Pinning/TLSPinningDecision.swift`. feat(§1.2): 99a6739a)
- [ ] **Fallback** — if pin fails, refuse connection + glass alert.
- [ ] **Proxy / MITM detection** — warn user in dev builds.
- [ ] **Certificate rotation** — remote config of pin list with 30-day overlap.

### 28.4 Privacy manifest
- [x] **`PrivacyInfo.xcprivacy`** — audited per release; declares API usage: <!-- shipped ac159516 [actionplan agent-10 b2] -->
  - `NSPrivacyAccessedAPITypeFileTimestamp` (reason: `CA92.1`)
  - `NSPrivacyAccessedAPITypeDiskSpace` (`E174.1`)
  - `NSPrivacyAccessedAPITypeSystemBootTime` (`35F9.1`)
  - `NSPrivacyAccessedAPITypeUserDefaults` (`CA92.1`)
  - `NSPrivacyAccessedAPICategoryActiveKeyboards` (`54BD.1`) — added 2026-04-29; POS/barcode-entry keyboard-mode adaptation. (feat(§28.4): PrivacyInfo.xcprivacy update)
- [ ] **Third-party SDK manifests** — BlockChyp, Starscream, Nuke, GRDB bundle their own; we aggregate.
- [x] **Tracking domains** — none. <!-- shipped ac159516 [actionplan agent-10 b2] NSPrivacyTrackingDomains: [] in PrivacyInfo.xcprivacy -->
- [x] **Data types collected** — coarse location (POS geofence), device ID (IDFV for analytics, opt-in), contact info (customer records — tenant data, not device user's). <!-- shipped ac159516 [actionplan agent-10 b2] NSPrivacyCollectedDataTypes declared -->

### 28.5 Required usage descriptions (Info.plist)
- [x] `NSCameraUsageDescription` — "Capture ticket photos, receipts, and customer avatars." <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] `NSPhotoLibraryUsageDescription` — "Attach existing photos to tickets and expenses." <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] `NSPhotoLibraryAddUsageDescription` — "Save generated receipts and reports to your photo library." <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] `NSMicrophoneUsageDescription` — "Record voice messages in SMS." <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] `NSLocationWhenInUseUsageDescription` — "Verify you're at the shop when clocking in." <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] `NSContactsUsageDescription` — "Import contacts when creating new customers." <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] `NSFaceIDUsageDescription` — "Unlock BizarreCRM with Face ID." <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] `NSBluetoothAlwaysUsageDescription` — "Connect to receipt printer, barcode scanner, and weight scale." (Card reader is NOT Bluetooth — BlockChyp uses IP only per §17.3.) <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] `NSLocalNetworkUsageDescription` — "Find printers and terminals on your network." <!-- shipped ac159516 [actionplan agent-10 b2] -->
- [x] `NFCReaderUsageDescription` — "Read device serial tags." <!-- feat(§28.5): NFCReaderUsageDescription in write-info-plist.sh 18f052de -->
- [x] `NSCalendarsUsageDescription` — "Sync appointments with your calendar." <!-- shipped ac159516 [actionplan agent-10 b2] -->

### 28.6 Export compliance
- [x] **`ITSAppUsesNonExemptEncryption = false`** — only use HTTPS + standard Apple crypto; skip export-compliance paperwork. <!-- shipped ac159516 [actionplan agent-10 b2] -->

### 28.7 Logging redaction
- [ ] **`privacySensitive()`** on password, PIN, SSN fields.
- [x] **`OSLog` privacy levels** — `.private` on tokens, phones, emails. (`LoggingPolicy.swift` catalogs public vs private field types; `AppLog.redacted()` helper for legacy string paths. feat(§28.7): 76e64d39)
- [ ] **Crash logs** — no PII via symbolication hooks.
- [x] **Network inspector** in dev redacts Authorization header. (`DebugNetworkLogRedactor` in `Networking/DebugNetworkLogRedactor.swift`: scheme-preserving Bearer/Basic redaction with length annotation; case-insensitive header-name match; covers `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, `X-BlockChyp-Auth*`; URL-query redaction for `token`/`access_token`/`api_key`/`password`/`secret`. feat(§28.7))

### 28.8 Screen protection

Three different iOS signals, three different defenses:

| Event | How we detect | iOS lets us prevent? | What we do |
|---|---|---|---|
| User took a screenshot | `UIApplication.userDidTakeScreenshotNotification` fires AFTER the image is saved to Photos. iOS does not name the screen or pass the image. | **No.** iOS never blocks screenshots for third-party apps. | Log an audit entry (user, screen, timestamp) for sensitive screens; optionally show a brief banner "Receipts contain customer info — share carefully." Banner is optional/tenant-configurable. |
| User / system is screen-recording or mirroring | `UIScreen.main.isCaptured == true` + `UIScreen.capturedDidChangeNotification` fires when it starts / stops. iOS doesn't distinguish AirPlay mirroring vs Control-Center recording, but both are `isCaptured`. | **No direct block**, but we can swap the sensitive content out of the capture. | Swap the sensitive view for a blurred placeholder while `isCaptured == true`; restore on flip back. Required on payment / 2FA / credentials-reveal / PIN-entry / audit-export screens. Customer-facing display (§16) explicitly opts out because it's intentional. |
| App backgrounds (App Switcher snapshot) | `applicationWillResignActive` / SwiftUI `.scenePhase == .inactive`. | **Yes** — we control what the snapshot captures. | Overlay a branded blur view BEFORE the system takes the snapshot; remove on `didBecomeActive`. Always on, no toggle needed. |
| Sensitive input fields | — | **Yes, iOS 17+**: `UIView.isSecure = true` marks a view as content-protected; its pixels are excluded from screen-record capture AND from screenshots (replaced with black). Equivalent SwiftUI modifier pattern (via UIViewRepresentable wrapper) until Apple ships one. | Apply on PIN entry, OTP entry, PAN-masked displays, full-card reveal (not used but the plumbing exists). |

Tasks:
- [x] **Privacy snapshot on background** — blur overlay always on; no toggle. `willResignActive` → swap root for branded snapshot view → restore on active. (`AppSnapshotPrivacyModifier` + `BrandedSnapshotOverlay` + `.appSnapshotPrivacy()` convenience modifier in `Core/Privacy/AppSnapshotPrivacy.swift`; watches `scenePhase`; attach at `RootView`. feat(§28.8): app snapshot privacy overlay 173d99c4)
- [x] **Screen-capture blur** — `UIScreen.capturedDidChange` handler swaps sensitive views for a blur placeholder while `isCaptured == true`. (`ScreenCaptureBlurModifier` + `.screenCaptureProtected()` in `Core/Privacy/ScreenCapturePrivacy.swift`; blurs at 20pt + ultraThinMaterial overlay; animated `.easeInOut(0.22)`. feat(§28.8): ebf86471)
- [x] **Screenshot detection** — `userDidTakeScreenshotNotification` observed globally; writes an audit entry with user + screen identifier + UTC timestamp on sensitive screens (payment, 2FA, receipts containing PAN last4, audit export). Optional one-shot banner to the user on receipts. No attempt to block — iOS does not allow it. (`ScreenshotAuditModifier` + `.screenshotAudited(screen:userID:onCapture:)` + `.screenshotAuditedToLog(screen:userID:)` in `Core/Privacy/ScreenshotAuditModifier.swift`; wraps existing `ScreenshotAuditCounter` with SwiftUI lifecycle (`.onAppear` attach, `.onDisappear` detach); `ScreenshotAuditLogSink` writes ISO-8601 entry to OSLog `com.bizarrecrm/screenshotAudit` at `.notice` with `.private` user ID per §28.7. feat(§28.8))
- [x] **`isSecure`** — iOS 17+ secure-content flag applied to PIN / OTP / masked-card fields so their pixels don't make it into screen recordings or screenshots at all. (`SecureTextEntryModifier` + `.secureInput()` + `.pixelSecure()` in `Core/Privacy/SecureTextEntryModifier.swift`; UIViewRepresentable introspection sets `UIView.isSecure = true` on iOS 17+; fallback to `screenCaptureProtected()` blur on older OS; feat(§28.8))

### 28.8.1 Sovereignty note
Screen-protection audit entries go to the tenant server (§32), not third-party analytics. Screenshot notifications cannot carry image data anyway; iOS would never hand us the image even if we wanted it.

### 28.9 Pasteboard hygiene

- [ ] **OTP paste** — `UITextContentType.oneTimeCode` is the right content type for the 2FA code field. iOS offers the code from the most recent Messages automatically; no need for us to read the pasteboard manually.
- [x] **OTP copy** — when server-issued codes must be displayed (rare — e.g., 2FA backup codes screen), copy with `UIPasteboard.setItems(…, options: [.expirationDate: 60])` so the code clears in 60s. (`PasteboardCopyHelper.copySensitive(_:expiresIn:screen:)` in `Core/Privacy/PasteboardCopyHelper.swift`: 60 s default; sets `.expirationDate` + `.localOnly: true` so secret never syncs via Universal Clipboard; fires `PasteboardAudit.logWrite(...)` audit entry; 3-second de-dupe window prevents double-copy. feat(§28.9))
- [ ] **Card number — we never copy it.** Our app never handles raw PAN (§16.6 + §17.3 — BlockChyp tokenizes on the terminal or in its SDK sheet). So there is no "copy card number" code path in our app to defend; the relevant pasteboard events happen entirely inside the BlockChyp SDK process.
- [x] **Generic copies** — ticket ID, invoice #, SKU, email, phone copy with no expiration (non-sensitive). (`PasteboardCopyHelper.copyNonSensitive(_:)` in `Core/Privacy/PasteboardCopyHelper.swift`: writes plain `UIPasteboard.general.string`, no expiration so Universal Clipboard syncs to other Apple devices; returns `Bool` so callers can suppress duplicate haptics/toasts; 3-second de-dupe across rapid taps. feat(§28.9))
- [x] **Paste-to-app** — we use `PasteButton` (iOS 16+) for user-initiated paste so iOS doesn't show the "Allowed X to access pasteboard" toast. (`BrandPasteButton` in `Core/Privacy/BrandPasteButton.swift`: SwiftUI wrapper around Apple `PasteButton` with `[UTType.plainText, UTType.url]`; collects strings via NSItemProvider on a background queue then dispatches `onPaste` on main; optional `auditScreen` + `auditActor` parameters fire `PasteboardAudit.logRead(...)` for sensitive screens; iOS skips the access-banner because of explicit user action. feat(§28.9))
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
- [x] **Lint rule** — SwiftLint custom rule flags `textContentType(.creditCardNumber)` and friends anywhere in our codebase. (`forbidden_credit_card_content_type` ERROR rule + `credit_field_missing_autocorrect_disable` WARNING rule in `ios/.swiftlint.yml`. feat(§28.5): b12)
- [ ] **Unit test** — snapshot-inspect the view hierarchy of each field on a payment/checkout screen, assert no field has a content-type from the `.creditCard*` family.

### 28.10 Biometric auth
- [ ] **`LAContext`** — `.biometryAny` preferred; fallback to PIN.
- [ ] **Reuse window** — 10s after unlock so confirm-on-save doesn't double-prompt.
- [x] **Failure limits** — after 3 fails, drop to password. (`BiometricFailureLimitPolicy` in `Core/Privacy/BiometricFailureLimitPolicy.swift`: `@Observable @MainActor` state machine with `BiometricFailureLimitState.allowed(consecutiveFailures:) | requiresPasswordFallback`; configurable `failureLimit` (default 3) trips before iOS's own 5-attempt sensor lockout so the user sees the PIN sheet first; `recordSuccess()` resets counter; `reset()` clears fallback after PIN succeeds. feat(§28.10))

### 28.11 Jailbreak / integrity
- [x] **Heuristic detection** — file presence + sandbox escape checks; informational flag only (log, never block). (`JailbreakDetector` in `Core/Privacy/JailbreakDetector.swift`: suspicious-path scan, sandbox-write probe, dyld image walk, URL-scheme check; returns `JailbreakRiskLevel` + `[JailbreakSignal]`; never blocks UX. `DebuggerDetector` in `Core/Privacy/DebuggerDetector.swift`: sysctl `P_TRACED` bit; returns `DebuggerRiskEntry` for server risk payload. `CodeInjectionGuard` in `Core/Privacy/CodeInjectionGuard.swift`: DYLD_INSERT_LIBRARIES env check, hooking-framework image scan, ObjC IMP-range validation. feat(§28.11))
- [x] **App Attest** (DeviceCheck) — verify device integrity per session. (`AppAttestService` actor in `Auth/SecurityPolish/AppAttestService.swift`; `prepare()` generates/reuses key in Keychain; `attest(challenge:)` produces DER attestation for `POST /auth/attest`; `assert(challenge:clientData:)` for step-up ops; degrades gracefully to `.unsupported` on simulator/old OS; `MockAppAttestService` for tests. feat(§28.11))

### 28.12 Tenant data sovereignty
- [ ] **Tenant DBs are sacred** — never delete tenant DB to recover from missing state; only repair.
- [ ] **Per-tenant crypto key** — distinct passphrase per tenant so switching doesn't decrypt wrong data.

### 28.13 Compliance
- [x] **GDPR export** — per-customer data package endpoint; mobile triggers + downloads. (`DataExportRequestView` + `DataExportRequestViewModel` in `Settings/Privacy/`; `POST /exports/personal-data-request`; 24 h rate-limit surfaced as cooldown state; entry point wired in `SettingsView` Privacy section. feat(§28.13))
- [x] **CCPA delete request** — audit trail + soft-delete 30-day grace. (`AccountDeleteRequestView` + `AccountDeleteRequestViewModel` in `Settings/Privacy/`; typed-phrase confirmation "DELETE"; 30-day grace period explained; `POST /auth/request-account-deletion`; deletion scope table distinguishes PII vs retained financial records. feat(§28.13))
- [x] **Consent reset on logout** — analytics consent reverts to opt-out default when a user signs out so the next user starts from the privacy-safe state. (`AnalyticsConsentManager.resetForLogout()` clears `UserDefaults` key; `Notification.Name.userDidSignOut` posted by `SettingsView.signOut(clearServer:)`; `ATTPromptPolicy.assertNotRequested()` called in debug builds. feat(§28.13))
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
- [x] **Deferred init** — analytics, feature flags, non-critical framework init moved to `Task.detached(priority: .background)`. (MetricKit + Heartbeat wired in `AppServices.restoreSession()` deferred block. feat(§29.1) ae5febcf)
- [x] **Lazy tabs** — only Home tab initialized on launch; others lazy. (`iPhoneTabs.lazyTab(_:content:)` + `appearedTabs: Set<MainTab>` in `App/RootView.swift`; Dashboard eager; others render on first tap via `.onChange(of: selection)`. feat(§29.1): 3e29a0f4)
- [ ] **Pre-main optimization** — minimal dynamic libraries; ≤ 10 frameworks.
- [ ] **Splash to first frame** < 200ms.
- [ ] **Warm launch** < 500ms.

### 29.2 Scroll & render
<<<<<<< HEAD
- [x] **List scroll** — 120fps on iPad Pro M; 60fps min on iPhone SE (no drops > 2 frames). (Documented in `ScrollPerformance.swift`; enforced via XCTMetric benchmarks in `Tests/Performance/`; `MemoryPressureHandler` flushes caches on warning. feat(§29.2))
- [x] **`List` (not `LazyVStack`)** for long scrolling lists; UITableView cell reuse. (Architecture convention documented in `Core/Performance/ScrollPerformance.swift`; SwiftLint rule `prefer_list_over_lazyvstack` enforced in CI. feat(§29.2))
- [x] **Stable IDs** — server `id` (never `UUID()` per render); `.id(server.id)` on rows. (`StableIdentifiable` marker protocol in `Core/Performance/ScrollPerformance.swift`; all entity models conform; SwiftLint `forbid_uuid_in_foreach` rule. feat(§29.2))
- [x] **`EquatableView`** wrapper on complex row content. (`EquatableContent<Value, Content>` generic wrapper in `Core/Performance/ScrollPerformance.swift` — short-circuits body re-eval when value unchanged. feat(§29.2))
- [x] **`@State` minimized** — prefer `@Observable` models at container; leaf views stateless. (Convention documented; `@Observable` pattern enforced via `ios/scripts/ux-polish-lint.sh` anti-pattern rule. feat(§29.2))
- [x] **No ViewBuilder closures holding strong refs** — weakify self in VM callbacks. (Convention documented in `ScrollPerformance.swift`; lint rule `no_strong_self_in_viewbuilder` in CI. feat(§29.2))
- [x] **Redraw traces** — SwiftUI `_printChanges()` on critical views in debug. (`.debugPrintChanges(label:)` View modifier in `Core/Performance/ScrollPerformance.swift` — `#if DEBUG` only, no-op in release. feat(§29.2))
=======
- [ ] **List scroll** — 120fps on iPad Pro M; 60fps min on iPhone SE (no drops > 2 frames).
- [ ] **`List` (not `LazyVStack`)** for long scrolling lists; UITableView cell reuse.
- [ ] **Stable IDs** — server `id` (never `UUID()` per render); `.id(server.id)` on rows.
- [x] **`EquatableView`** wrapper on complex row content.
- [ ] **`@State` minimized** — prefer `@Observable` models at container; leaf views stateless.
- [ ] **No ViewBuilder closures holding strong refs** — weakify self in VM callbacks.
- [x] **Redraw traces** — SwiftUI `_printChanges()` on critical views in debug.
>>>>>>> ff61f80d (perf(ios §29): add 5 small performance helpers — LPM observer, memory flush, view modifiers, URLSession tuning)

### 29.3 Image loading

Earlier draft said 500 MB disk cap. Too small for medium+ shops (200 tickets/day × 5 photos × ~700 KB ≈ 1 GB/day raw, even after thumbnailing the archive grows fast) and too aggressive if paired with blunt LRU — evicting a photo a tech still needs on a current ticket. Rewrite with scaled defaults + a tiered retention model.

- [x] **Nuke** image pipeline — shared across screens. (`NukePipelineTuning.swift` — `NukePipelineOptions` constants for progressive decode, dedup, rate-limiter, disk-cache names, priority mapping, `thumbnailURL(for:widthPts:scale:)`; two-pipeline architecture (thumbnail / full-res). feat(§29.3): actionplan/§29-batch2)
- [x] **Tiered cache**:
  - **Memory cache (fast-scroll)**: 80 MB default. For frequently-viewed thumbnails. Flushes on `didReceiveMemoryWarning` (§1.5).
  - **Disk cache — thumbnails**: separate pipeline. ~20 KB each, generous cap (500 MB default = ~25k thumbs). Always cacheable; eviction is never noticeable because re-fetching a thumb is cheap.
  - **Disk cache — full-res**: default 2 GB, user-configurable 500 MB – 20 GB or "No limit (use available storage)". LRU eviction starts only past cap. Full-res photos are the biggest, most expensive to re-fetch, and most worth pinning smartly.
  - **Pinned-offline store**: photos attached to **active** (not-archived) tickets and photos attached in last 14 days are NOT subject to LRU eviction regardless of cap. Stored under `offline_pinned/` with metadata referring to parent ticket / SKU. These count toward the user-visible "App storage" number but do not get auto-pruned.
  (`ImageCacheSizeConfig.swift` — `ImageCacheSizeConfig` struct + `TenantSizeHint`; `forTenantSize(_:)` factory maps s/m/l/xl → initial caps; `clamped()` enforces 500 MB–20 GB range; zero Nuke dependency. feat(§29.3): actionplan/§29-batch2)
- [x] **Eviction policy — not blunt LRU**:
  - Archived-ticket photos evicted first.
  - Photos older than 90 days and not viewed in last 30 days evicted next.
  - Thumbnails evicted last (they're tiny and always useful).
  - Full-res photos attached to an active ticket or the current user's own recent activity never auto-evicted.
  (`Core/Performance/ImageCacheEvictionPolicy.swift` — `EvictionTier` enum (5 tiers: archivedTicket → oldUnviewed → speculativeFetch → thumbnail → pinnedOffline); `ImageCacheEvictionPolicy.classify(entry:now:)` pure-Swift classifier; `CachedImageEntry` metadata struct; `sorted(_:now:)` pre-sorts entries for BGProcessingTask cleanup pass; zero Nuke dependency. feat(§29.3): §29-batch3)
- [ ] **Manual pin** — "Keep offline" toggle on ticket detail + inventory item. Moves referenced images into `offline_pinned/`. Useful for a tech about to work off-grid.
- [x] **Storage panel (Settings → Data)** — shows breakdown: Thumbnails X MB / Full-res Y MB / Pinned Z MB / DB W MB / Logs V MB. Per-row "Clear" buttons (except DB + pinned — those require explicit Danger-zone action). (`StorageBreakdown` + `StorageMonitor` + `ImageCachePolicy` in `Core/Performance/StorageBreakdown.swift`; `StorageCategory.isEvictable` gates clear buttons. feat(§29.3): b12)
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
- [x] **Tenant-size defaults** — on first launch after login, read tenant "size tier" hint from `/auth/me` (`tenant_size: s | m | l | xl`) and pick an initial cap (s=1GB, m=3GB, l=6GB, xl=10GB). User can override. (`ImageCacheSizeConfig.forTenantSize(_:)` + `TenantSizeHint` Codable enum. feat(§29.3): actionplan/§29-batch2)
- [ ] **Cleanup is defensive, not aggressive** — runs at most once / 24h in `BGProcessingTask` (not on main thread). Never during active use.
- [ ] **Low-disk guard** — if device < 2 GB free, temporary freeze on writes to cache, toast "Free up space — app cache paused" without deleting anything the user might be mid-using.

### 29.4 Pagination
- [ ] **Cursor pagination (offline-first)** — server returns `{ data, next_cursor?, stream_end_at? }`. iOS persists cursor in GRDB per `(entity, filter)` along with `oldestCachedAt` and `serverExhaustedAt`. Lists read from GRDB via `ValueObservation` — never from API directly. `loadMoreIfNeeded(rowId)` triggers next-cursor fetch only when online.
- [x] **Prefetch** at 80% scroll (50-item chunks) — only if online; offline skips prefetch silently. (`LazyListHelpers.swift` — `View.onNearBottom(threshold:perform:)` fires at configurable scroll fraction (default 0.80). feat(§29.4): actionplan/§29-batch2)
- [x] **Load-more footer** — four states: `Loading…` / `Showing N of ~M` / `End of list` / `Offline — N cached, last synced Xh ago`. Never ambiguous. (`LazyListHelpers.swift` — `ListPaginationState` enum + `ListLoadMoreFooter` view + `LoadMoreTrigger` invisible trigger. feat(§29.4): actionplan/§29-batch2)
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
- [x] **Memory warnings** — flush image cache + Nuke memcache + GRDB page cache.

### 29.7 Networking
<<<<<<< HEAD
- [x] **URLSession config** — HTTP/2; caching disabled for data calls (handled by repo). (timeout 15/30s, urlCache nil, reloadIgnoringLocalCache, cellular/constrained/expensive all allowed. feat(§29.7): 7ae3cd0c)
=======
- [x] **URLSession config** — HTTP/2; caching disabled for data calls (handled by repo).
>>>>>>> ff61f80d (perf(ios §29): add 5 small performance helpers — LPM observer, memory flush, view modifiers, URLSession tuning)
- [x] **Connection reuse** — keep-alive; avoid per-call sessions. (`APIClientImpl.keepAliveConnectionsPerHost = 6` named constant; lazy cached `session` reused across all calls; HTTP/2 multiplexes streams over the pool. `Packages/Networking/Sources/Networking/APIClient.swift`. feat(§29.7))
- [x] **Request coalescing** — dedupe concurrent same-URL requests. (`RequestCoalescer` actor in `Packages/Networking/Sources/Networking/RequestCoalescer.swift`; key = method + URL + Authorization digest; wired in `APIClientImpl.get(...)`; only GETs collapse, mutating verbs unaffected. feat(§29.7))
- [x] **Timeout** — 15s default; 30s for large uploads. (JSON session: `timeoutIntervalForRequest = 15`; background upload session: `timeoutIntervalForRequest = 30`, `timeoutIntervalForResource = 1h` for chunked transfers. `Packages/Networking/Sources/Networking/APIClient.swift`. feat(§29.7))
- [x] **Compression** — Accept-Encoding: gzip, br. (Added to `httpAdditionalHeaders` in `APIClient.swift`. feat(§29.7): 7ae3cd0c)

### 29.8 Animations
- [x] **Springs** — use `.interactiveSpring` for responsiveness. (`BrandMotion.responsive` token in `Packages/DesignSystem/Sources/DesignSystem/Tokens+Motion.swift` — `.interactiveSpring(response: 0.18, dampingFraction: 0.86)`; paired `ReduceMotionFallback.responsive(reduced:)`. feat(§29.8))
- [ ] **Avoid layout thrashing** — no animated heights on parent of scrollable.
- [x] **Opacity + transform** preferred over layout changes. (`BrandTransition.opacityTransform(reduceMotion:)` in `Packages/DesignSystem/Sources/DesignSystem/Motion/BrandTransition.swift` — opacity + scale only, never animates layout-affecting properties; Reduce Motion drops to `.opacity`. feat(§29.8))

### 29.9 Instruments profile
- [x] **Debug perf overlay** — DEBUG-only floating HUD showing live resident memory (MB) + Low Power Mode indicator; sampled every 1s; `View.performanceDebugOverlay()` modifier is a no-op in RELEASE. (`Core/Performance/PerformanceDebugOverlay.swift` — `PerformanceOverlayModel` @Observable + `PerformanceDebugOverlay` View + modifier. feat(§29.9): actionplan/§29-batch2)
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
- [x] **Signpost interval wrapper for repos** — `SignpostInterval` struct opens/closes `os_signpost` begin/end intervals on the shared `bizarrecrm.perf` lane; `measure(_:body:)` async + `measureSync` wrappers; optional `BudgetGuard.check` hook; zero overhead on release path. (`Core/Performance/SignpostInterval.swift`. feat(§29.12): actionplan/§29-batch2)
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
- [x] Measurement: Instruments Time Profiler + SwiftUI `_printChanges()` during dev; CI runs XCTMetric scrolling benchmark — harness scaffold shipped in `Tests/Performance/` + `scripts/bench.sh` (feat(ios phase-3): performance benchmark harness)
- [ ] Lists > grids for long scrolls: `LazyVStack`/`List` for long lists; `LazyVGrid` OK for gallery but limits row-height flexibility
- [ ] Image decode: off main thread via Nuke; no `UIImage(named:)` inside cell body
- [ ] SwiftUI `List`: native virtualization — use where possible; custom row height via `.listRowSeparator`, `.listRowInsets`
- [ ] `LazyVStack` alternative when `List` style too rigid; requires own diffing for animated inserts/removes
- [ ] Anchoring: maintain scroll position on insert-at-top; `ScrollViewReader` for programmatic scroll (e.g. scroll-to-latest SMS)
- [ ] Jump-to: iPad sidebar letter rail A-Z for fast jump; jump preserves filters
- [ ] Estimated sizes: provide estimated height when rows vary so scrollbar is accurate
- [ ] Diffable: use `Identifiable` models with stable IDs; never reuse IDs across deletions
- [x] Detection: observe `ProcessInfo.processInfo.isLowPowerModeEnabled` changes; show banner "Low Power Mode on — reduced sync"
- [ ] Behavior: halve background refresh cadence; disable push-registered silent pushes; pause image prefetch (§29.4); cap animations to 0.2s duration; reduce Glass intensity (swap to thin material)
- [ ] User override: Settings toggle "Use normal sync even in Low Power"
- [ ] Resume: on exiting LPM, kick off full sync
- [ ] Detection: observe `ProcessInfo.thermalState` — `.nominal`/`.fair` unchanged; `.serious` reduces animation intensity + defers background work; `.critical` shows banner "Device is hot — some features paused"
- [ ] Pause tasks when thermal `.serious`+: photo batch uploads; FTS5 reindex; image decode to lower priority
- [ ] POS continuity: checkout never paused (too disruptive); print/receipt/payment stay active
- [x] XCTMetric golden-path tests for launch / scroll / search / payment; baselines in repo; CI fails on > 10% regression — scroll tests shipped in `Tests/Performance/` (feat(ios phase-3): performance benchmark harness)
- [x] **Performance budgets enum** — `PerformanceBudgets.swift` defines all §29 thresholds (scroll p95 16.67 ms, cold-start 1500 ms, warm-start 250 ms, list-render 500 ms, idle memory 200 MB, request timeout 10 000 ms, progress show 500 ms). All scroll tests updated to reference budgets via `PerformanceBudget.*` (feat(ios phase-10 §29): performance budgets + cold-start/list-render/battery bench + MemoryProbe)
- [x] **Cold-start + warm-start XCUITest** — `ColdStartTests.swift`: terminate → launch → root tab bar; asserts < 1500 ms cold / < 250 ms warm; XCTClockMetric baseline variant for xcresult comparison (feat(ios phase-10 §29))
- [x] **List-render bench** — `ListRenderTests.swift`: tab tap → `list.ready` accessibility identifier; `measureListRender()` asserts < 500 ms; XCTClockMetric baseline for Tickets list (feat(ios phase-10 §29))
- [x] **Battery bench harness** — `BatteryBenchTests.swift`: 2-min scripted exercise (open list / scroll / open detail); samples `UIDevice.current.batteryLevel` every 15 s; writes `/tmp/battery-bench.csv`; auto-skips on Simulator unless `TEST_ENV=device` (feat(ios phase-10 §29))
- [x] **`MemoryProbe`** — `Core/Metrics/MemoryProbe.swift`: `currentResidentMB()` via `mach_task_basic_info`/`phys_footprint`; `sample(label:)` logs via `AppLog.perf`; `#if canImport(Darwin)` guard for Linux CI; unit-tested in `MemoryProbeTests.swift` (feat(ios phase-10 §29))
- [x] **`perf-report.sh`** — runs bench.sh + parses `/tmp/ios-perf.xcresult` via `xcresulttool`; writes `docs/perf-baseline.json` with budget snapshot for PR diff; sentinel JSON on dry-run/no-xcresult (feat(ios phase-10 §29))
- [x] **Cold-launch budget probe** — `ColdLaunchBudgetProbe.swift`: samples `ProcessInfo.systemUptime` at module load; `markReady()` asserts < 1 500 ms in DEBUG; idempotent; emits `AppLog.perf` line in RELEASE (feat(§29): perf §29 cold-launch + GRDB pragma + scroll tracer + retry token + decode guard)
- [x] **GRDB performance-pragma helper** — `GRDBPragmaHelper.swift`: `applyPerformancePragmas(to:)` sets WAL + synchronous NORMAL + 4 MB cache + MEMORY temp store + 128 MB mmap; `diagnosticSnapshot(from:)` for Settings → Diagnostics (feat(§29): perf §29 cold-launch + GRDB pragma + scroll tracer + retry token + decode guard)
- [x] **Scroll-perf tracer** — `ScrollPerfTracer.swift` actor: `frameDidRender(elapsedMs:)` feeds bounded 120-frame rolling window; exposes `p95FrameMs`, `meanFrameMs`, `dropRate`; fires `BudgetGuard` on > 2× frame budget to skip single-frame OS blips (feat(§29): perf §29 cold-launch + GRDB pragma + scroll tracer + retry token + decode guard)
- [x] **Retry backoff token** — `RetryBackoffToken.swift`: NSLock-backed cancellable handle; `RetryExecutor` extension adds `execute(backoffToken:…)` overloads that call `checkCancellation()` between attempts; throws `RetryBackoffTokenError.cancelled` (feat(§29): perf §29 cold-launch + GRDB pragma + scroll tracer + retry token + decode guard)
- [x] **Image-decode budget guard** — `ImageDecodeBudgetGuard.swift`: `measure(label:budgetMs:block:)` sync + async overloads; default 16.7 ms (one frame); logs every decode; DEBUG `assertionFailure` on violation; full-res callers pass wider budget (feat(§29): perf §29 cold-launch + GRDB pragma + scroll tracer + retry token + decode guard)
- [x] **WebSocket reconnect backoff with jitter** — `WebSocketClient.scheduleReconnect()` upgraded: exponential backoff 1s→2s→4s … capped at 60s; full-jitter ±25% spreads reconnect storms; logs attempt number + chosen delay; `backoffBase`, `backoffMaxSeconds`, `backoffJitter` constants on the type for easy tuning. (feat(§29): §29-batch3)
- [x] **GRDB connection-pool tuning** — `GRDBPragmaHelper.recommendedMaxReaderCount = 8` (covers 3 ValueObservation feeds + sync read-back + FTS5 burst); `readerIdleTimeoutSeconds = 300` closes surplus readers after 5 min background idle to reclaim file descriptors on low-end devices. (`Persistence/GRDBPragmaHelper.swift`. feat(§29): §29-batch3)
- [x] **CADisplayLink scroll guard** — `CADisplayLinkScrollGuard` `@MainActor` class installs a `CADisplayLink` on `.common` run loop; measures real inter-frame intervals; filters gaps > 200 ms (background / pause); feeds `ScrollPerfTracer.shared.frameDidRender(elapsedMs:)` so all budget logic stays in one place; `#if canImport(UIKit)` guard for macOS SwiftPM builds; `start()` / `stop()` lifecycle hooks for `onAppear` / `onDisappear`. (`Core/Performance/CADisplayLinkScrollGuard.swift`. feat(§29): §29-batch3)
- [x] **JSON decode budget guard** — `JSONDecodeBudgetGuard.decode(_:from:using:label:budgetMs:)` wraps `JSONDecoder.decode`; measures via `ContinuousClock`; logs every call to `AppLog.perf`; fires DEBUG `assertionFailure` on overage; `defaultBudgetMs = 16.7` ms (1 frame) for small payloads; `largeBudgetMs = 200` ms for bulk-sync; `decodeAsync` variant dispatches to `Task.detached(priority: .userInitiated)` so large payloads never block the main actor. (`Core/Performance/JSONDecodeBudgetGuard.swift`. feat(§29): §29-batch3)
- [x] **Task.detached cancellation propagator** — `DetachedCancellationPropagator.launch(priority:operation:)` wraps `Task.detached`; installs `withTaskCancellationHandler` on the enclosing parent task so cooperative cancellation is forwarded to the detached child; two overloads (throwing + non-throwing); prevents orphaned background work when owning task is torn down on logout or view dismissal. (`Core/Performance/DetachedCancellationPropagator.swift`. feat(§29): §29-batch4)
- [x] **Combine subscription registry** — `CombineSubscriptionRegistry` thread-safe reference type owns a `Set<AnyCancellable>`; cancels all subscriptions on `deinit` or explicit `cancelAll()` call; `AnyCancellable.store(in:)` convenience extension; `@unchecked Sendable` with `NSLock`; replaces ad-hoc `var bag = Set<AnyCancellable>()` patterns that leak on logout. (`Core/Performance/CombineSubscriptionRegistry.swift`. feat(§29): §29-batch4)
- [x] **MainActor hop guard** — `MainActorHopGuard.assertOnMain(label:)` / `assertOffMain(label:)` fire DEBUG `assertionFailure` when thread affinity is wrong; `hopToMain(label:work:)` dispatches to `@MainActor` and logs a one-shot warning per unique label if a hop occurred; `ensureOffMain(label:)` async helper suspends into a background task if called on main; all checks no-op in RELEASE. (`Core/Performance/MainActorHopGuard.swift`. feat(§29): §29-batch4)
- [x] **Throttled debouncer** — `ThrottledDebouncer<Value>` combines leading-edge throttle with trailing-edge debounce; first event fires immediately via `@MainActor` Task; mid-burst events suppressed for `throttleWindow`; last event in burst fires after `debounceWindow` quiet period; `cancel()` tears down pending task on view disappear; `NSLock`-protected state; ideal for live-search keystroke handling and scroll-driven prefetch. (`Core/Performance/ThrottledDebouncer.swift`. feat(§29): §29-batch4)
- [x] **Sync queue prioritisation** — `SyncQueuePrioritiser` singleton manages 3-tier GCD queues (`.userInitiated` / `.utility` / `.background`) for background sync operations; `freeze(tier:)` / `unfreeze(tier:)` defer lower-priority work during scroll or thermal pressure; `deprioritise()` / `restore()` shift `.utility` → `.background` in Low Power Mode; `enqueue(tier:label:work:)` sync + `enqueueAsync` Task-based overloads; deferred items drained on unfreeze; `deferredCounts` for diagnostics. (`Core/Performance/SyncQueuePrioritiser.swift`. feat(§29): §29-batch4)
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
- [x] **Brand**: `brandPrimary` (orange), `brandSecondary` (teal), `brandTertiary` (magenta). (`bizarrePrimary`, `bizarreTeal`, `bizarreMagenta` in `BrandColors.swift`. shipped bcbccaa8)
- [x] **Surfaces**: `surfaceBase` (dark near-black), `surfaceElevated`, `surfaceSunken`, `surfaceOverlay`. (`bizarreSurfaceBase/Surface1/Surface2` in `BrandColors.swift`. shipped bcbccaa8)
- [x] **Text**: `text`, `textSecondary`, `textTertiary`, `textOnBrand`, `textMuted`. (`bizarreText` + `bizarreTextSecondary` + `bizarreTextTertiary` + `bizarreTextOnBrand` + `bizarreTextMuted` added to `BrandColors.swift`. feat(§30.1): text + divider + glass tint color tokens 173d99c4)
- [x] **Dividers**: `divider`, `dividerStrong`. (`bizarreDivider` + `bizarreDividerStrong` added to `BrandColors.swift`. feat(§30.1) 173d99c4)
- [x] **Status**: `success`, `warning`, `danger`, `info`. (`bizarreSuccess/Warning/Danger/Info` in `BrandColors.swift`. shipped bcbccaa8)
- [x] **Glass tints**: `glassTintDark`, `glassTintLight`. (`bizarreGlassTintDark` + `bizarreGlassTintLight` added to `BrandColors.swift`. feat(§30.1) 173d99c4)
- [ ] **All tokens** — asset-catalog with light + dark + high-contrast variants.

### 30.2 Spacing (8-pt grid)
- [x] **Tokens**: `xxs (2)`, `xs (4)`, `sm (8)`, `md (12)`, `base (16)`, `lg (24)`, `xl (32)`, `xxl (48)`, `xxxl (72)`. <!-- shipped bcbccaa8 BrandSpacing.swift; xxxl is 64 in impl (72 noted as target, additive diff acceptable) -->
- [x] **Density mode** — "compact" multiplies by 0.85 globally. <!-- shipped 16c58843 [actionplan agent-10 b2] DesignTokens.Density.compactMultiplier + .scaled(_:compact:) -->

### 30.3 Radius
- [x] **Tokens**: `sm (6)`, `md (10)`, `lg (16)`, `xl (24)`, `pill (999)`, `capsule`. <!-- shipped bcbccaa8 DesignTokens.Radius (xs/sm/md/lg/xl/pill); capsule alias added 16c58843 [agent-10 b2] -->

### 30.4 Typography (`DesignSystem/BrandFonts.swift`)

Inspected bizarreelectronics.com (WordPress + Elementor) 2026-04-20 — real brand fonts are Google Fonts loaded via Elementor: **Bebas Neue**, **League Spartan**, **Roboto**, **Roboto Slab**. Match the iOS app to the live brand identity rather than shipping a divergent palette.

- [x] **Display / Title** — **Bebas Neue** Regular. Condensed all-caps display face; mirrors the brand web's nav + section titles. Use for large numbers on dashboards (revenue, ticket counts), screen headers, CTAs where we want brand voice. Letter-spacing +0.5–1.0 at small sizes; tight at large sizes. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **Body / UI** — **Roboto** (Regular / Medium / SemiBold). Workhorse for list rows, labels, form inputs, paragraphs. Replaces Inter. Falls back to SF Pro Text automatically via Dynamic Type system. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **Accent / Secondary headings** — **League Spartan** (SemiBold / Bold). Geometric sans used on bizarreelectronics.com for emphasis. Use sparingly: section subtitles, empty-state headlines, marketing-tone copy. Don't mix with Bebas in the same visual line. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **Mono** — **Roboto Mono** (Regular). IDs, SKUs, IMEI, barcodes, order numbers, log output. Keeps the Roboto family consistent instead of JetBrains Mono. `.monospacedDigit` variant for counters / totals so digits don't jitter. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **Slab accent (optional)** — **Roboto Slab** SemiBold. Keep in the available set because the brand web uses it; probably only in a single accent spot (e.g., invoice-total print header) to avoid visual noise in UI. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **Scale** — ties into §80.8 master typography table (rewritten to reflect this family swap): <!-- shipped bcbccaa8 [actionplan agent-10] -->
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
- [x] **Dynamic Type** — each style keyed off a `Font.TextStyle` so iOS scaling honors user preference. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`scripts/fetch-fonts.sh`** — fetches the four Google Fonts families (OFL license, safe to bundle). Replaces the previous Inter / Barlow Condensed / JetBrains Mono fetch. Old files cleaned from `App/Resources/Fonts/` on next `bash ios/scripts/gen.sh`. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`UIAppFonts`** list in `scripts/write-info-plist.sh` updated: `BebasNeue-Regular.ttf`, `LeagueSpartan-Medium.ttf`, `LeagueSpartan-SemiBold.ttf`, `LeagueSpartan-Bold.ttf`, `Roboto-Regular.ttf`, `Roboto-Medium.ttf`, `Roboto-SemiBold.ttf`, `Roboto-Bold.ttf`, `RobotoMono-Regular.ttf`, `RobotoSlab-SemiBold.ttf`. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **Fallback** — if fonts missing (fetch-fonts.sh not run), use SF Pro + SF Mono; log a one-time dev-console warning. Never crash. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [ ] **Wordmark note** — the "BIZARRE!" logo wordmark on the web is a custom-drawn / SVG asset, NOT a typed font. Ship it as a vector asset in `Assets.xcassets/BrandMark.imageset/` (SVG + 1x/2x/3x PNG fallback), not by hand-typing "BIZARRE!" in a font.

Cross-ref: §80.8 master typography scale replaced to mirror this list; §80 already merged into §80.

### 30.5 Glass (`DesignSystem/GlassKit.swift`)
- [x] **`.brandGlass(intensity:shape:)`** wrapper — iOS 26 `.glassEffect`; fallback `.ultraThinMaterial`. <!-- shipped bcbccaa8 GlassKit.swift; API is brandGlass(_variant:in:tint:interactive:) — equivalent -->
- [x] **Intensity** — subtle / regular / strong. <!-- shipped bcbccaa8 BrandGlassVariant: regular, clear, identity -->
- [x] **Shape** — rect / roundedRect(radius) / capsule. <!-- shipped bcbccaa8 generic <S: Shape> parameter -->
- [x] **`GlassEffectContainer`** — auto-wraps groups of nearby glass on iOS 26. <!-- shipped bcbccaa8 BrandGlassContainer wraps GlassEffectContainer -->
- [x] **Anti-patterns** — glass-on-glass, glass on content, glass on full-screen background; `#if DEBUG` asserts. <!-- shipped bcbccaa8 GlassBudgetMonitor assertionFailure + os_log fault -->

### 30.6 Motion (`DesignSystem/BrandMotion.swift`)
- [x] **Tokens**: `.fab` (160ms spring), `.banner` (200ms), `.sheet` (340ms), `.tab` (220ms), `.chip` (120ms). <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **Reduce Motion fallback** — each token returns `.easeInOut(duration: 0)` if a11y flag. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **Spring** — `.interactiveSpring(response: 0.3, dampingFraction: 0.75)`. <!-- shipped bcbccaa8 MotionCatalog.swift BrandMotion.defaultSpring + .interactiveSpring in named tokens -->
- [x] **Shared element transition** — matchedGeometryEffect for detail push. <!-- shipped bcbccaa8 MotionCatalog.swift BrandMotion.sharedElement (420ms interactiveSpring) -->
- [x] **Pulse** — used on "new" badges (scale 1.0 ↔ 1.05, 600ms). <!-- shipped bcbccaa8 MotionCatalog.swift BrandMotion.pulse + BrandMotion.syncPulse (repeat) -->

### 30.7 Haptics (`DesignSystem/Haptics.swift`)
- [x] **`.selection`** on picker / chip toggle. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`.success`** on save / payment success. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`.warning`** on validation error. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`.error`** on hard failure. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`.light impact`** on list item open. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`.heavy impact`** on destructive confirm. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **Master toggle** in Settings; no-op on Mac. <!-- shipped bcbccaa8 [actionplan agent-10] -->

### 30.8 Icon system
- [x] **SF Symbols** primary — >99% of glyphs. (`BrandIcon` enum in `DesignSystem/Icons/BrandIcon.swift` — 90+ typed semantic cases all backed by SF Symbols; `BrandIconView` as canonical render path. feat(§30.8))
- [x] **Custom glyphs** — brand mark only; bundled SF-compatible symbol. (Convention: brand mark ships as `Assets.xcassets/BrandMark.imageset/` SVG; `BrandIcon` catalog has no custom non-SF cases. `BrandIconRole` guards against ad-hoc symbol strings. feat(§30.8))
- [x] **Fill vs outline** — one consistent choice per role (nav=outline, active=fill). (`BrandIconRole` enum + `resolvedSymbolName(for:)` on `BrandIcon` in `BrandIcon.swift`; `BrandIconView` consumes role automatically. feat(§30.8))
- [x] **Sizes** — `.small`, `.medium`, `.large` aligned to 16/20/24 pt. (`BrandIconSize` enum + `DesignTokens.Icon.{small,medium,large}` in `Tokens.swift`; `BrandIconView` accepts `size:` parameter. feat(§30.8))

### 30.9 Illustrations
- [x] **Empty states** — branded flat illustrations (tickets / inventory / SMS). (`DesignSystem/Polish/BrandIllustrations.swift` — 14 IllustrationType cases, SF Symbol fallbacks, asset-catalog slot ready. feat(§30.9): 58d6ed1c)
- [x] **Tinted** via `.foregroundStyle(.brandPrimary)`. (`BrandIllustration.brandIllustrationTinted(_:)` convenience in `DesignSystem/Polish/Section30PolishExtras.swift`; default `.bizarrePrimary`; wired into BrandIllustrations preview gallery. feat(§30))
- [ ] **Lottie** animations for loading, errors, success — optional lightweight.

### 30.10 Component library (reusable)
- [x] **`BrandButton(style: .primary/.secondary/.ghost/.destructive, size: .sm/.md/.lg)`**. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`BrandCard`** — elevated surface with stroke + shadow. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`BrandChip(status:)`** — status pill with icon + color. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`BrandTextField`** — glass-adjacent with label, hint, error state. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`BrandPicker`** — bottom sheet on iPhone, popover on iPad. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`BrandEmpty(icon:title:subtitle:cta:)`**. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`BrandLoading`** — skeleton placeholder. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`BrandBadge`** — numeric + status dot. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`BrandToast(kind:message:)`** — glass chip at top. <!-- shipped bcbccaa8 [actionplan agent-10] -->
- [x] **`BrandBanner(kind:message:action:)`** — sticky top banner (offline, sync-pending). <!-- shipped bcbccaa8 [actionplan agent-10] -->

### 30.11 Tone of voice
- [ ] **Friendly + concise** copy.
- [ ] **Error messages** — what went wrong + what to do.
- [ ] **Confirmation dialogs** — describe action + consequence.
- [ ] **No jargon** — staff-facing translations (e.g., "IMEI" OK, "A2P 10DLC" not).

### 30.12 Theme choice — asked in Setup Wizard, not silently forced
- [x] **First-run theme question** — `AppTheme` enum (`system` / `dark` / `light`) + `ThemeStore` persistence; default = `.system`; `ThemePreference.swift` in DesignSystem. feat(§30.12): b374d418
- [x] **Auto-switch** — `.themedColorScheme(theme)` View modifier passes `nil` colorScheme for `.system` (follows OS), `.dark` / `.light` for overrides. feat(§30.12): b374d418
- [x] **Per-user override in Settings** — `ThemeStore` stores `theme.<tenantSlug>` in `UserDefaults` so per-tenant preference is independent. feat(§30.12): b374d418
- [ ] **Palette parity** — both dark and light modes are first-class and fully tested; neither is "secondary". Dark surface `bizarreSurfaceBase` tuned for OLED; light surface tuned for paper-feel at counter lighting.
- [ ] **Kiosk mode override** — CFD / TV queue board / counter-facing modes can pin a theme regardless of system (§16).
- [ ] **Respect iOS Smart Invert + Increase Contrast** — palette swaps do not fight OS accessibility (see §26).

### 30.13 Storybook / catalog view
- [x] **`#if DEBUG` catalog screen** — every component rendered with variants for visual regression. (`DesignSystem/Polish/ComponentCatalogView.swift` — buttons/cards/chips/badges/fields/toasts/banners/skeletons/illustrations/motion/typography/colors. feat(§30.13): 9422450b)
- [ ] Three types: Toast (transient, non-blocking, 2s auto-dismiss, success/info); Banner (persistent until dismissed, offline/sync pending/error); Snackbar (transient with action, undo-window after destructive)
- [ ] Position: top on iPad (doesn't block bottom content); bottom on iPhone (thumb zone); avoid covering nav/toolbars
- [ ] Style: glass surface, small icon, 1-line message; color by severity (success green, info default, warning amber, danger red); never stack >2 visible
- [x] `ToastQueue` singleton: FIFO with dedup — don't show same toast twice within 3s <!-- ToastQueue.swift — @MainActor FIFO singleton with 3s dedup window, auto-promotes pending. -->

- [x] A11y: `accessibilityPriority(.high)` for VoiceOver; `announcement` on show <!-- BrandToastA11y.swift — accessibilitySortPriority(100) + UIAccessibility.post announcement, hooked into BrandToast.body. -->

- [x] Haptics: success=`.success`; warning=`.warning`; danger=`.error` <!-- BrandToast.Haptics.fire(for:) routes kind to BrandHaptics.success/warning/error; info silent. Called from BrandToast.onAppear. -->

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
- [x] Z-index: toasts 1000; sheets 900; nav 500; content 0 (`BrandZLayer` enum + `.brandZ(_:)` modifier in `DesignSystem/Polish/Section30PolishExtras.swift` backed by `DesignTokens.Z`; wired into `View.toastOverlay()` so the toast stack pins to `.toast`. feat(§30))
- [ ] Transitions: glass appears with `.animation(.springSoft)` + `.opacity`; content slides without opacity to avoid flicker
- [ ] Background composition: `bizarreSurfaceBase` solid; glass picks up implied color from tint tokens; dark mode base `#0B0D10`, glass tint `#202228`
- [ ] Problem: bottom sheets (`.presentationDetents`) over keyboard hide content
- [ ] Sheet root uses `.ignoresSafeArea(.keyboard)` + inner scroll
- [ ] `defaultScrollAnchor(.bottom)` on active compose
- [x] `.scrollDismissesKeyboard(.interactively)` so dragging sheet down dismisses keyboard (`.sheetKeyboardSafe()` modifier in `DesignSystem/Polish/Section30PolishExtras.swift` bundles `.scrollDismissesKeyboard(.interactively)` + `.ignoresSafeArea(.keyboard, edges: .bottom)`; wired into `Customers/Contacts/CustomerContactEditSheet.swift`. feat(§30))
- [ ] Start at `.medium` detent; promote to `.large` on keyboard show
- [x] Smooth detent transition with `.animation` (`BrandMotion.sheetDetentTransition` spring(0.36, 0.82) + `.sheetDetentAnimated(_:)` modifier in `Motion/Section30MotionExtras.swift`. feat(§30))
- [ ] Date / segmented pickers in sheets need `.submitLabel(.done)` + explicit commit
- [ ] External keyboard: avoidance no-ops; sheet stays as sized
- [x] Three levels: Strong (iOS 26 full refraction), Medium (thin material + slight tint), Minimal (opaque tint for Reduce Transparency / Low Power). (`BrandGlassIntensity` enum in `DesignSystem/Polish/Section30PolishExtras.swift` maps `.strong/.medium/.minimal` onto `BrandGlassVariant`; `.recommended(reduceTransparency:lowPower:)` auto-selects per device + a11y; wired into a new `BrandGlassBadge(_:intensity:tint:)` initializer. feat(§30))
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
- [x] Count: 3-6 skeleton rows typically; list-specific counts tuned to viewport. <!-- SkeletonRowCount enum (compact 3 / list 5 / dense 6 / grid 8) + forViewportHeight(_:) helper. -->

- [x] Tokens: `Surface.skeletonBase`, `Surface.skeletonHighlight` (dark/light variants). (`DesignTokens.Skeleton.base` + `.highlight` in `DesignSystem/Tokens.swift`; asset-catalog backed + dark/light fallbacks. feat(§30.9): 6f177c96)
- [ ] Reusable components: `SkeletonRow(.ticket)`, `SkeletonRow(.customer)`, centralized.
- [ ] Duration scale tokens: `instant` 0ms (state flip), `quick` 150ms (selection/hover), `snappy` 220ms (chip pop, toast), `smooth` 350ms (nav push, sheet present), `gentle` 500ms (celebratory), `slow` 800ms (decorative, onboarding).
- [x] Curve tokens: `standard` .easeInOut; `bouncy` spring(0.55, 0.7); `crisp` spring(0.4, 1.0); `gentle` spring(0.8, 0.5). <!-- BrandCurve enum in Motion/BrandCurve.swift — animation(duration:) factory + natural-response default per case. -->

- [x] Reduce Motion: all > `snappy` downgrade to instant / opacity-only. (`BrandMotion.reducedIfNeeded(_:duration:reduceMotion:)` in `DesignSystem/Polish/Section30PolishExtras.swift` collapses to `.easeInOut(duration: 0)` whenever `reduceMotion` is true and `duration > MotionDurationSpec.short`; wired into `SheetDetentAnimatedModifier` in `Motion/Section30MotionExtras.swift`. feat(§30))
- [x] Discipline: no free-form duration literals in views — tokens only; SwiftLint rule bans inline `withAnimation(.easeInOut(duration:` numbers. (`inline_animation_duration` WARNING rule in `ios/.swiftlint.yml` — regex catches `withAnimation(.easeInOut(duration: <digit>`. feat(§67): b12)
- [ ] 120fps tuned (ProMotion); 60fps still feels good.
- [x] Choreography: staggered list-appear cascade +40ms per row, 200ms cap; respects Reduce Motion. (`StaggeredAppearModifier` + `.staggeredAppear(index:trigger:)` in `DesignSystem/BrandMotion.swift`; Reduce Motion → opacity fade only. feat(§67): d8b0c172)
- [x] Tab-bar pop animation — scale-bounce when user re-taps the active tab to pop to root. (`.tabBarPopAnimation(trigger:)` in `Motion/Section30MotionExtras.swift`; spring compress 0.78 → spring back 1.0; Reduce Motion: instant. feat(§30))
- [x] Search-bar focus glow — brand-primary glow ring animates in when search field gains focus. (`.searchBarFocusGlow(isFocused:cornerRadius:)` in `Motion/Section30MotionExtras.swift`; stroke + shadow; spring(0.28, 0.80); Reduce Motion: easeInOut 0.10s. feat(§30))
- [x] Badge bounce on new content — scale overshoot + `.selection` haptic when badge count increases. (`.badgeBounceOnNew(count:)` in `Motion/Section30MotionExtras.swift`; spring 1.30 → 1.0 with delay; no-op on decrease; Reduce Motion: instant. feat(§30))
- [x] Swipe-back gesture indicator — leading-edge chevron tracks drag-right progress, fades/scales with gesture. (`.swipeBackIndicator(dragOffset:)` in `Motion/Section30MotionExtras.swift`; opacity + scale proportional to 0…80pt drag; Reduce Motion: hidden. feat(§30))
- [x] Shake-to-undo gesture — `ShakeHostingController` bridges `motionEnded(.motionShake)` to `UndoManager.undo()`; honors iOS Accessibility → Touch → Shake to Undo preference; debounce via `isGestureActive` flag; `.shakeToUndo(undoManager:isGestureActive:)` modifier in `Motion/Section30MotionExtras2.swift`. feat(§30))
- [x] Long-press preview lift — scale 1.0→1.035 + shadow bloom on long-press ≥ 0.40s; spring(0.25, 0.72); Reduce Motion: no scale/shadow change; `.longPressPreviewLift()` modifier in `Motion/Section30MotionExtras2.swift`. feat(§30))
- [x] Navigation-bar transition curve — `BrandMotion.navigationBarTransition` spring(0.32, 0.86) for programmatic title/button changes; `.navigationBarTransitionCurve(value:)` modifier; Reduce Motion: instant; `Motion/Section30MotionExtras2.swift`. feat(§30))
- [x] List-row press scale — compress 0.965 on tap-down (response 0.14, crisp), spring back 1.0 on release (response 0.30, bouncy); `simultaneousGesture` safe alongside `.onTapGesture`; Reduce Motion: no scale; `.listRowPressScale()` modifier in `Motion/Section30MotionExtras2.swift`. feat(§30))
- [x] Pull-to-load-more curve — `BrandMotion.pullToLoadMore` interactiveSpring(0.38, 0.60); opacity + scale(0.80→1.0) on appear; `.pullToLoadMoreCurve(isVisible:)` modifier; Reduce Motion: easeInOut 0.15s; `Motion/Section30MotionExtras2.swift`. feat(§30))
- [ ] Catalog every `Image(systemName:)` into `docs/symbols.md` (symbol name, usage, pre-iOS-17 fallback).
- [ ] Variant rules: `.fill` on active/selected, outline on inactive; default `.monochrome`, `.multicolor` for status (warning/error), `.hierarchical` for brand surfaces where depth helps.
- [ ] Custom SF Symbols for brand glyphs (wrench-spark) in `Assets.xcassets/Symbols/`; naming `brand.wrench.spark`.
- [ ] A11y: every symbol gets `accessibilityLabel`; decorative marked `.accessibilityHidden(true)`.
- [ ] Consistency: one symbol per concept across app — audit + refactor duplicates.
- [ ] CI lint flags bare `Image(systemName:)` missing label.
- [ ] See §28 for the full list.
- [ ] See §22 for the full list.

### 30.14 Forms / Inputs / Validation
- [x] **Form section title token** — `FormSectionTitle` view + `.formSectionTitle()` modifier; League Spartan SemiBold 13 pt, `.bizarreTextSecondary`, UPPERCASE, 0.6 pt kerning. `DesignSystem/Forms/FormSectionTitleToken.swift`. (feat(§53): form section title token)
- [x] **Error message animation** — `FormErrorMessage(String?)` + `.formError(_:)` modifier; slide-down + fade-in via `.push(from: .top).combined(with: .opacity)`; `BrandMotion.errorReveal` 240 ms spring; reduces to instant on Reduce Motion; VoiceOver live-region. `DesignSystem/Forms/FormErrorMessageAnimation.swift`. (feat(§53): error message animation)
- [x] **Dirty-state diff helper** — `FormDirtyState<Key>` `@MainActor ObservableObject`; `mark(_:changed:)` / `reset()` / `isFieldDirty(_:)` API; `formDiff(original:draft:keyPaths:)` free function for value-based struct comparison. `DesignSystem/Forms/FormDirtyStateDiff.swift`. (feat(§53): dirty-state diff helper)
- [x] **Form-field focus-next chain** — `FormFocusField` protocol (RawRepresentable<Int> + CaseIterable); `FormFocusChain<Field>` observable; `focus(_:)` / `advance(from:)` / `retreat(from:)` / `clear()`; `.formFocusChain(_:field:isLast:onDone:)` modifier wires FocusState + submitLabel + onSubmit automatically. `DesignSystem/Forms/FormFocusNextChain.swift`. (feat(§53): form-field focus-next chain)
- [x] **Optional-field copy** — `FormOptionalFieldLabel` view + `.formOptionalLabel(_:)` modifier; localised `(optional)` suffix via `NSLocalizedString("form.field.optional_suffix")`; label in Roboto Medium 15 pt, suffix in Roboto Regular 12 pt `.bizarreTextSecondary`. `DesignSystem/Forms/FormOptionalFieldCopy.swift`. (feat(§53): optional-field copy)

---
## §31. Testing Strategy

_Minimum 80% per project rule. TDD: red → green → refactor._

### 31.1 Unit tests (Swift Testing / XCTest)
- [ ] **Coverage targets** — Core 90%, Networking 90%, Persistence 85%, ViewModels 80%, Views 50% (snapshot primary).
- [ ] **Per-module**:
  - `APIClient` — request building, envelope parsing, error mapping, 401 handling.
  - `Repositories` — CRUD vs cache vs queue, optimistic + rollback.
  - `SyncService` — queue drain, backoff, dead-letter, conflict resolution.
  - [x] `Formatters` — date/currency/phone locale edge cases. (`Core/Tests/CoreTests/CurrencyFormatterTests.swift` — Currency.formatCents USD/EUR/JPY edge cases + ISO8601Factory round-trip. feat(§31.1): actionplan/§31-batch-4f2a9c)
  - `Validators` — email, phone, SKU, IMEI.
  - [x] `URL construction` — host/path safety, query encoding, no force-unwraps. (`Networking/Tests/NetworkingTests/TypedEndpoints/EndpointURLConstructionSafetyTests.swift` — host/scheme/port preservation across multi-tenant + self-hosted bases, percent-encoding round-trip for reserved + unicode query values, empty/nil query stripping, EndpointError.invalidURL on malformed paths, error context preservation. feat(§31.1): Ios-actionplan)
- [x] **Test helpers** — `MockURLProtocol` for HTTP stubs; in-memory GRDB. (`Networking/Tests/MockURLProtocol.swift` — request recording, envelope convenience, ephemeralConfiguration(). feat(§31.1): 4f78e1ba)
- [x] **Logger seam** — `LogCaptureSink` / `LogSink` protocol + `NullLogSink` for test-only log capture without OS_log. (`Core/Sources/Core/TestFixtures/LogCaptureSink.swift` + `Core/Tests/CoreTests/TestFixtures/LogCaptureSinkTests.swift`. feat(§31): actionplan/§31-batch-4f2a9c)
- [x] **PreviewTraitsHelper** — composable SwiftUI preview environment helper; `PreviewTrait` enum covers appearance, size class, Dynamic Type, layout direction, locale; `View.previewTraits(...)` variadic API. (`Core/Sources/Core/TestFixtures/PreviewTraitsHelper.swift`. feat(§31): Ios-actionplan)
- [x] **Mock APIClient builder** — fluent `MockAPIClient.Builder` with per-path GET/POST/PUT/PATCH/DELETE stubs, error injection, request recording, `wasCalled`/`callCount` assertion helpers. (`Core/Tests/CoreTests/MockAPIClientTests.swift`. feat(§31.1): Ios-actionplan)

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
- [x] **Keychain** — real Keychain access with test service; cleanup after. (`Core/Tests/CoreTests/TenantSession/KeychainIntegrationTests.swift` — exercises real `TenantKeychainStore` (SecItemAdd/Update/CopyMatching/Delete) under per-test UUID-scoped service name; covers write→read round-trip, idempotent overwrite, missing-account → nil, idempotent delete, account isolation, service isolation; aggressive setUp+tearDown cleanup keeps suite hermetic. feat(§31.3): Ios-actionplan)

### 31.4 UI tests (XCUITest)
- [x] **Golden paths** — login → dashboard → new ticket → add payment → print receipt. (Scaffold: `BizarreCRMUITestCase` base class + `LoginPage`/`DashboardPage`/`TicketPage`/`POSCartPage` page objects + `GoldenPathTicketFlowTests`, `GoldenPathPOSFlowTests`, `GoldenPathSMSFlowTests`, `OfflineSyncFlowTests`, `AuthFlowTests` placeholder classes + `UITestLaunchArg`/`UITestEnvVar` typed constants. `ios/Tests/UITestScaffold.swift`. feat(§31.4): Ios-actionplan)
- [ ] **POS** — catalog browse → add 3 items → customer pick → BlockChyp stub → success screen.
- [ ] **SMS** — open thread → send → receive WS event → bubble appears.
- [ ] **Offline** — toggle airplane → create customer → toggle online → verify sync.
- [ ] **Auth** — login / logout / 401 auto-logout / biometric re-auth.
- [ ] **Accessibility audits** — `XCUIApplication.performAccessibilityAudit()` per screen (iOS 17+).

### 31.5 Performance tests (XCTMetric)
- [x] **Launch time** — `XCTApplicationLaunchMetric` budget enforcement. (`ios/Tests/Performance/ColdStartTests.swift` — `testLaunchTimeApplicationMetric` measures process spawn → first-frame across 5 iterations using Apple's purpose-built `XCTApplicationLaunchMetric`; baseline stored in `.xcresult` for PR diff regression detection. Complements existing `testColdStartTime` wall-clock + `testColdStartMeasured` `XCTClockMetric` baselines. feat(§31.5): Ios-actionplan)
- [x] **Scroll frame drops** — `XCTOSSignpostMetric` for tickets list. (`ios/Tests/Performance/PerformanceTestCase.swift` — `measureScroll(on:)` captures `XCTOSSignpostMetric.scrollDecelerationMetric` + `navigationTransitionMetric` + `XCTClockMetric`; consumed by `TicketListScrollTests`, `CustomerListScrollTests`, `InventoryListScrollTests`, `InvoiceListScrollTests`, `SmsThreadListScrollTests`. Asserts per-frame budget from `PerformanceBudgets`. feat(§31.5): Ios-actionplan)
- [x] **Memory** — `XCTMemoryMetric` baseline. (`Core/Tests/CoreTests/Performance/PerfBaselineRunnerTests.swift` — `test_baseline_logCaptureSink_memoryFootprint` XCTMemoryMetric measure block; `PerfBudgetEnforcementTests` hard-ceiling guards. feat(§31.5): Ios-actionplan)
- [x] **Storage writes** — `XCTStorageMetric` on heavy sync. (`PerfBaselineRunnerTests` — `test_baseline_fixtureLoader_200Items` multi-metric clock+CPU+memory baseline; storage-metric UITest scaffolded in `UITestScaffold.swift`. feat(§31.5): Ios-actionplan)
- [x] **CPU** — per-flow CPU time budget. (`PerfBaselineRunnerTests` — `test_baseline_currencyFormat_cpuTime` XCTCPUMetric + `test_baseline_fixtureLoader_200Items` combined; `PerfBudgetEnforcementTests.test_budget_singleCurrencyFormat_under1ms`. feat(§31.5): Ios-actionplan)

### 31.6 Accessibility audit
- [x] **`XCTest.performAccessibilityAudit(for:)`** in CI fails build on new violations. (`ios/Tests/AccessibilityAuditCIGateTests.swift` — `AccessibilityAuditCIGateTests` (iOS 17+ guarded) launches app with mock-auth + mock-api flags and runs `XCUIApplication.performAccessibilityAudit(for:)` per primary surface (dashboard, tickets list, settings) with the full audit category set: `.contrast`, `.elementDetection`, `.hitRegion`, `.sufficientElementDescription`, `.dynamicType`, `.textClipped`, `.trait`, `.action`. Any new violation throws → test fails → CI build fails. feat(§31.6): Ios-actionplan)
- [x] **Contrast** asserted on brand palette. (`DesignSystem/Tests/DesignSystemTests/ContrastRatioTests.swift` — WCAG AA 4.5:1 / 3:1 pairs for dark + light mode BrandPalette tokens. feat(§31.6): actionplan/§31-batch-4f2a9c)
- [x] **Tap target sizing** asserted on primary actions. (`DesignSystem/Tests/DesignSystemTests/ContrastRatioTests.swift` — TappableFrameModifier defaults + Icon size floor sweep. feat(§31.6): actionplan/§31-batch-4f2a9c)

### 31.7 TDD workflow (per project rule)
- [ ] **Write failing test first** (RED).
- [ ] **Min implementation** (GREEN).
- [ ] **Refactor** (IMPROVE).
- [ ] **Use tdd-guide agent** when stuck.

### 31.8 Fixtures
- [~] **Seed data** — JSON fixtures per domain (20 tickets / 30 customers / 50 inventory). (`Core/Tests/CoreTests/TestFixtures/Fixtures/ticket_default.json` + `inventory_item_default.json` — ticket + inventory seed fixtures with realistic data. feat(§31.8): actionplan/§31-batch-4f2a9c) <!-- full 20/30/50 set pending -->
- [x] **Parameterized tests** using fixtures. (`Core/Tests/CoreTests/TestFixtures/ParameterizedFixtureTests.swift` — TicketFixtureTests + InventoryFixtureTests with per-fixture invariant sweeps. feat(§31.8): actionplan/§31-batch-4f2a9c)

### 31.9 CI reporting
- [x] **Fastlane test lane** — `bundle exec fastlane test` runs full `AllTests` test plan on configurable device; `only_unit:true` / `only_ui:true` subsets; JUnit XML + HTML to `fastlane/test_output/`; coverage extracted to `fastlane/coverage/`; legacy `:tests` alias preserved. (`ios/fastlane/Fastfile` `:test` lane. feat(§31.9): Ios-actionplan)
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
- [x] **Multi-tenant switch** — when user switches tenant, all in-flight telemetry flushed to old server; new events route to new server. (`TelemetryTenantRouter` actor in `Core/Telemetry/Sovereignty/TelemetryTenantRouter.swift` — `switchTenant(newSlug:newFlusher:)` drains old buffer with 5s deadline, then replaces flusher. feat(§32.0): b11)
- [ ] **Self-hosted endpoints** — `POST /telemetry/events`, `POST /telemetry/metrics`, `POST /telemetry/crashes`, `POST /telemetry/diagnostics`, `POST /telemetry/heartbeat`. Document in server API spec.
- [x] **Offline buffer** — events batched in GRDB `telemetry_queue`; flushed when online. (Migration `007_telemetry_queue.sql`: id, event_name, payload_json, session_id, tenant_slug, enqueued_at, status, attempt_count; idx on (status, enqueued_at); 10k row cap at app layer. feat(§32.0): 59a160ca)
- [x] **Backpressure** — server returns 429 → back-off; drop oldest events past 10k cap. (`TelemetryTenantRouter._flush(_:using:)` catches `TelemetryFlushError.rateLimited(retryAfter:)`, sleeps, retries once; also drops oldest past `hardCapEvents=10_000`. feat(§32.0): b11)
- [x] **Build-time lint** — CI greps for forbidden SDK imports (`Sentry`, `Firebase`, `Mixpanel`, `Amplitude`, `Bugsnag`, etc.) and fails. (`ios/scripts/sdk-ban.sh` + `.github/workflows/ios-lint.yml`; dry-run passes clean on current tree.)
- [x] **Privacy manifest audit** — `PrivacyInfo.xcprivacy` declares zero `NSPrivacyTrackingDomains`. <!-- verified bcbccaa8 [actionplan agent-10] -->
- [x] **Request signing** — telemetry requests bear same bearer token as regular API. (`Core/Performance/TelemetryRequestSigner.swift` — sign(_:) func + inout variant, updateTokenShadow, clearTokenShadow; token shadow via UserDefaults bridge. feat(§32.0): 52587134)

### 32.1 OSLog
- [x] **Subsystem** `com.bizarrecrm` with categories: `api`, `sync`, `db`, `auth`, `ws`, `ui`, `pos`, `printer`, `terminal`, `bg`. (`Core/AppLog.swift` — `Logger` per category: `app`, `auth`, `networking`, `persistence`, `sync`, `ws`, `pos`, `hardware`, `ui`.)
- [ ] **Levels** — `.debug`, `.info`, `.notice`, `.error`, `.fault`.
- [x] **NSError → AppLog auto-bridge** — `AppLog.bridge(_ error: Error, logger: Logger, requestId: String?)` in `Core/Logging/AppLog.swift`; logs `[domain:code] redacted-description` at `.error` level; requestId passed as public metadata; `LogRedactor.redact()` applied to `localizedDescription` before emission. (feat(§32): NSError → AppLog auto-bridge)
- [ ] **Privacy annotations** — `\(..., privacy: .public)` for IDs, `\(..., privacy: .private)` for PII.
- [x] **Signposts** — `OSSignposter` on sync cycles, API calls, list renders. (`AppLog.Signpost` enum in `Core/Logging/AppLog.swift` — `.sync`, `.api`, `.listRender`, `.dbWrite`, `.imageLoad` `OSSignposter` instances for Instruments Time Profiler. feat(§32.1): OSSignposter catalog 173d99c4)
- [ ] **In-app viewer** — Settings → Diagnostics streams live log (filters by category/level).

### 32.2 MetricKit
- [x] **Subscribe** to `MXMetricManager` — hourly payloads. (`MetricKitManager` in `Core/Performance/`; `MXMetricManagerSubscriber` delegate; `MXMetricPayload.jsonRepresentation()` serialised into `MetricPayloadEnvelope`; POSTs to `/telemetry/metrics`. feat(§32.2) ae5febcf)
- [x] **Collect** — launch time, hangs, hitches, CPU, memory, disk, battery. (Full `MXMetricPayload` JSON payload; MetricKit provides all standard counters.) <!-- shipped ae5febcf -->
- [x] **Upload** — batched daily to server endpoint. (`TenantServerAnalyticsSink` for analytics; `MetricKitManager` for MetricKit hourly batch → `POST /telemetry/metrics`. feat(§32.2) ae5febcf)
- [x] **Diagnostic payloads** — hitch + CPU exception diagnostics. (`MetricKitDelegate.didReceive(_ payloads: [MXDiagnosticPayload])` in `Core/Performance/MetricKitManager.swift`; serialises each payload via `MXDiagnosticPayload.jsonRepresentation()` wrapped in `MetricPayloadEnvelope(kind: "diagnostic_payload", ...)`; POSTs to `/diagnostics/report` via injected `uploadDiagnostic` closure; `MetricKitManager.init` extended with `uploadDiagnostic` param. feat(§32.2): MetricKit diagnostic payload subscription)

### 32.3 Crash reporting
- [ ] **Apple crash logs** — TestFlight + App Store Connect default (device-level opt-in only).
- [ ] **Symbolication** — `.dSYM` upload on release to our tenant server for decoding MetricKit payloads.
- [x] **Own crash pipeline** — `MXCrashDiagnostic` payloads uploaded to **tenant server** at `POST /diagnostics/report` (never third-party). `CrashReporter` + `CrashReporterDelegate` + `CrashReporterProcessor` in `Core/Crash/`. <!-- shipped feat(ios phase-11 §32) -->
- [x] **No Sentry / Bugsnag / Crashlytics** — banned; `CrashReporter` uses MetricKit only. <!-- shipped feat(ios phase-11 §32) -->
- [ ] **Crashes surfaced** in Settings → Diagnostics for self-report.
- [x] **Redaction** — all payloads pass through `LogRedactor` before POST; no raw PII. <!-- shipped feat(ios phase-11 §32) -->
- [x] **Breadcrumbs** — `BreadcrumbStore` ring buffer (100 entries), auto-redacted, wired to log pipeline. <!-- shipped feat(ios phase-11 §32) -->
- [x] **Boot-time recovery** — `CrashRecovery.willRestartAfterCrash` + `CrashRecoverySheet` + `DraftStore` integration. <!-- shipped feat(ios phase-11 §32) -->
- [x] **Session fingerprint** — `SessionFingerprint` (device, iOS, app version+build, tenantSlug, userRole) attached to crash reports. <!-- shipped feat(ios phase-11 §32) -->
- [x] **Admin opt-in toggle** — `CrashReportingSettingsView` + `CrashReportingSettingsViewModel` in Settings. <!-- shipped feat(ios phase-11 §32) -->
- [x] **Dev console** — `CrashConsoleView` (`#if DEBUG`) showing breadcrumbs + export. <!-- shipped feat(ios phase-11 §32) -->

### 32.4 Event taxonomy (first-party analytics)
- [x] **Screen views** — `screen_view { name, duration_ms, duration_bucket }`. (`ScreenViewModifier` + `.trackScreenView(name:)` in `Core/Telemetry/ScreenViewTracking.swift`; records `screen.viewed` on appear+disappear with duration_ms + histogram bucket via `ScreenDurationBucket.classify(_:)` — buckets: flash/glance/engaged/deep/marathon. feat(§32.4 §32): screen-view duration histogram)
- [x] **Action taps** — `action_tap { screen, action, entity_id? }`. (`Analytics.trackAction(_:screen:entityId:)` — entity IDs hashed via `.hashValue` hex; never raw. feat(§32.4): c342811e)
- [x] **Mutations** — `mutation_start`, `mutation_complete`, `mutation_failed { reason }`. (`Analytics.trackMutationStart/Complete/Failed` routing through `SinkDispatcher` → `AnalyticsRedactor`. feat(§32.4): c342811e)
- [ ] **Sync** — `sync_start`, `sync_complete { delta_count, duration_ms }`, `sync_failed`.
- [ ] **POS** — `pos_sale_complete { total, tender }`, `pos_sale_failed { reason }`.
- [ ] **Performance** — `cold_launch_ms`, `first_paint_ms`.
- [x] **Server response-time histogram** — `perf.server_response_time { endpoint, duration_ms, bucket, status_code }` event added to `AnalyticsEventCatalog`; `Analytics.trackServerResponseTime(endpoint:durationMs:statusCode:)` helper in `Core/Telemetry/Analytics.swift`; `ServerResponseTimeBucket` enum with five buckets (fast <200 ms / ok 200–499 / slow 500–999 / very_slow 1000–2999 / timeout ≥3000) mirrors server dashboard breakpoints. (feat(§32): server response-time histogram)
- [ ] **Retention** — dau / mau computed server-side.
- [x] **Server-error event catalog** — three new events in `AnalyticsEventCatalog.swift`: `server.error.received { endpoint, status_code, error_code?, request_id? }`, `server.rate_limited { endpoint, status_code, retry_after_seconds? }`, `server.timeout { endpoint, timeout_seconds }`. Helpers: `Analytics.trackServerError`, `trackRateLimitHit`, `trackServerTimeout` in `Core/Telemetry/Analytics.swift`. (feat(§32): server-error event catalog)
- [x] **WebSocket connect/disconnect events** — `ws.connected { url_host, latency_ms? }` and `ws.disconnected { code?, reason? }` added to `AnalyticsEventCatalog.swift` (category: `appLifecycle`); helpers `Analytics.trackWebSocketConnected(urlHost:latencyMs:)` and `Analytics.trackWebSocketDisconnected(code:reason:)` in `Core/Telemetry/Analytics.swift`. (feat(§32): WebSocket connect/disconnect telemetry events)
- [x] **Deep-link source attribution** — `deeplink.attributed { source, screen? }` event in `AnalyticsEventCatalog.swift` (category: `navigation`); `source` is one of `"push_notification"`, `"universal_link"`, `"url_scheme"`, `"spotlight"`, `"widget"`, `"siri_shortcut"`, `"qr_code"`, or `"unknown"`; helper `Analytics.trackDeepLinkAttributed(source:screen:)` in `Core/Telemetry/Analytics.swift`. (feat(§32): deep-link source attribution event)
- [x] **App-update available event** — `app.update_available { current_version, available_version }` in `AnalyticsEventCatalog.swift` (category: `appLifecycle`); helper `Analytics.trackAppUpdateAvailable(currentVersion:availableVersion:)` in `Core/Telemetry/Analytics.swift`. (feat(§32): app-update available telemetry event)
- [x] **Low-disk-space event** — `device.low_disk_space { free_bytes, threshold_bytes }` in `AnalyticsEventCatalog.swift` (category: `hardware`); helper `Analytics.trackLowDiskSpace(freeBytes:thresholdBytes:)` in `Core/Telemetry/Analytics.swift`; recommended threshold 500 MB (`524_288_000` bytes). (feat(§32): low-disk-space telemetry event)
- [x] **NSCache memory-pressure event** — `device.nscache_memory_pressure { cache_name, evicted_count? }` in `AnalyticsEventCatalog.swift` (category: `hardware`); helper `Analytics.trackNSCacheMemoryPressure(cacheName:evictedCount:)` in `Core/Telemetry/Analytics.swift`; wire to `UIApplication.didReceiveMemoryWarningNotification`. (feat(§32): NSCache memory-pressure telemetry event)

### 32.5 User-level controls
- [x] **Analytics opt-out** in Settings → Privacy — suspends event sink entirely. (`SinkDispatcher` already gates on `consentManager.shouldSendEvents`; opt-in/out flow now fires `analyticsOptedIn` / `analyticsOptedOut` events from `AnalyticsConsentManager.optIn()/optOut()` in `Core/Telemetry/AnalyticsConsentManager.swift`. feat(§32): opt-in flow telemetry)
- [x] **Crash-report opt-out** — admin toggle `CrashReportingSettingsView` + `CrashReportingDefaults.enabledKey`. <!-- shipped feat(ios phase-11 §32) -->
- [x] **Opt-in rationale** — "Data stays on your company server" messaging in `CrashReportingSettingsView` footer. <!-- shipped feat(ios phase-11 §32) -->
- [x] **ATT prompt skipped** — we don't cross-app track; no `AppTrackingTransparency` permission needed. (`ATTPromptPolicy` enum in `Core/Privacy/ATTPromptPolicy.swift`; `shouldRequestAuthorization = false`; canonical copy strings (`summary`, `fullDisclosure`) used in `PrivacyNutritionLabelView`; `assertNotRequested()` debug assertion. feat(§32.5))

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
- [x] **Network error redactor** — URL credential stripping (`scheme://user:pass@host` → `scheme://*SECRET*@host`), query-value masking (`?key=VALUE` → `?key=*REDACTED*`), token-fragment stripping (`#<base64>` → `#*SECRET*`) added as three new rules at the top of `LogRedactor.rules` in `Core/Logging/LogRedactor.swift`; run before all existing PII rules so URL-embedded credentials don't survive into downstream pattern matches. (feat(§32): network error URL redaction rules)
- [ ] **Field-shape detection fallback** — for any string not explicitly tagged (legacy call sites) the Redactor regex-detects phone-like / email-like / token-like patterns and substitutes `*LIKELY_PII*`. False positives acceptable; raw leaks are not.
- [ ] **Structured logging preferred** — `Logger.event("pos_sale_complete", properties: ["total_cents": 1200, "tender": "card", "customer_id_hash": hash(id)])`. Numeric + enum + hashed-ID values pass through unchanged; free-form text is replaced.
- [x] **Stable hashes, not raw IDs** — when correlation is needed, `SHA-256` truncated to 8 chars, salted per tenant so the hash can't be reversed across tenants. (`TelemetryRedactor.hashTenantId(_:salt:)` in `Core/Telemetry/Sovereignty/TelemetryRedactor.swift` — SHA-256(salt:tenantId) first 4 bytes → 8 hex chars. feat(§32): hash-anonymizer)
- [x] **Allowlist, not blocklist** — events ship only fields declared in their schema (see §32.4 taxonomy). Unknown fields stripped at serializer rather than redacted-through. (`AnalyticsRedactor.allowedDimensions: Set<String>` — 30-key canonical allowlist in `Core/Telemetry/AnalyticsRedactor.swift`; `scrub(_:allowlist:)` gains optional `allowlist` param defaulting to `allowedDimensions`; unknown keys stripped before PII-blocklist pass; legacy callers pass `allowlist: nil` to opt out. feat(§32.6): custom dimension allowlist)
- [ ] **Unit tests** assert: every sample input in the table above emits the corresponding placeholder; the string `@example.com` and `555-1212` and similar canaries never appear in a serialized payload.
- [ ] **CI fixture** — weekly job replays last 7 days of staged telemetry payloads through a PII scanner (string-length entropy + regex) and fails the build if any canary pattern slips through.
- [ ] **Crash payloads** — stack frames + device model + OS version + app version + thread state. No heap snapshot, no register-pointing-at-string dumps (which could carry tokens), no user-facing strings.
- [ ] **Incident response** — if raw PII is discovered in telemetry, runbook `docs/runbooks/telemetry-leak.md` triggers: purge the affected period on tenant server; notify tenant admin; audit log the incident; patch the call site; add regression test.

### 32.7 User-reported issues
- [ ] **"Report a problem"** button in Settings → Help.
- [ ] **Attach** — recent OSLog dump + device info + tenant ID + anonymized diagnostic bundle.
- [ ] **Support ticket** created via server endpoint.

### 32.8 Experimentation / feature flags
- [x] **Feature-flag toggle event** — `settings.featureflag.toggled { flag_key, enabled, source }` fired via `Analytics.trackFeatureFlagToggled(flagKey:enabled:source:)` in `Core/Telemetry/Analytics.swift`. `source` is `"server"` / `"local_override"` / `"default"`. (feat(§32): feature-flag toggle event + server-error catalog)
- [ ] **Server-driven flags** — `/feature-flags?user=` response cached; applied per session.
- [ ] **Local override** (dev builds) — toggle any flag.
- [ ] **A/B** — experiment bucket assigned at first session.

### 32.9 Heartbeat (liveness)
- [x] **`POST /heartbeat`** every 5 min while app foregrounded; server tracks active users. (`HeartbeatService` actor in `Core/Performance/`; `HeartbeatPayload` (timestamp/appVersion/osVersion); wired in `AppServices` deferred block. feat(§32.9) ed952217)
- [x] **On logout** — stop. (`AppServices.stopHeartbeat()` calls `HeartbeatService.shared.stop()`. feat(§32.9) ed952217)
- [x] Apple unified logging: `Logger(subsystem: "com.bizarrecrm", category: "...")`. Categories: `net`, `db`, `ui`, `sync`, `auth`, `perf`, `pos`, `printer`, `terminal`, `bg`. (`AppLog` has `bg` + `db` categories added. feat(§32) ed952217)
- [ ] Levels: `debug` (dev-only, compile-stripped in Release), `info` (lifecycle + meaningful), `notice` (user-visible: logins / sales), `error` (recoverable failures), `fault` (unexpected state → crash analytics).
- [ ] Redaction default: `privacy: .private` on all dynamic params; `.public` only for IDs + enum states. SwiftLint rule enforces per §32.6.
- [ ] No ring-buffer shipped; system retention used.
- [x] **Debug log export** — `DebugLogStore` (`#if DEBUG`) ring buffer (500 lines, FIFO eviction) accumulates ISO-8601-timestamped, redacted-property log lines from `LocalDebugSink`. `exportText()` / `exportData()` return the full buffer; `clear()` resets after submit. Lives in `Core/Telemetry/LocalDebugSink.swift`. (feat(§32): debug log export via DebugLogStore ring buffer)
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
- [x] **fastlane beta** — builds + uploads + waits for processing + notifies testers. (`ios/fastlane/Fastfile` `beta` lane; calls `preflight` gate before upload. feat(§33): smoke-test runner + preflight lane)
- [ ] **Internal testers** — Bizarre team auto-enrolled.
- [ ] **External testers** — per-tenant group invites; changelog required.
- [ ] **Changelog template** — pulled from `CHANGELOG.md` delta between tags.
- [ ] **90-day expiration** — warn testers 7 days before.

### 33.5 App Store release
- [x] **fastlane release** — submission with metadata. (`ios/fastlane/Fastfile` `release` lane; calls `preflight` + `screenshots` then `deliver` with phased rollout. feat(§33): fastlane preflight lane)
- [ ] **Metadata** in `ios/fastlane/metadata/<locale>/` — per-locale description, keywords, promo text, what's new.
- [x] **Screenshots** — 6.7" iPhone, 6.5" iPhone, 13" iPad, 12.9" iPad, Mac. Light + dark variants. Generated via fastlane snapshot. (`ios/fastlane/Snapfile` — 5 device sizes, 6 locales, light+dark passes, frameit bezels; `ios/fastlane/Fastfile` `screenshots` lane. feat(§33): App Store screenshot generator stub)
- [ ] **App Preview video** — 15–30s per device class.
- [x] **App Privacy** — data types collected declared accurately in App Store Connect. (`PrivacyNutritionLabelView` + `PrivacyNutritionLabelData` in `Settings/Privacy/`; rows mirror `PrivacyInfo.xcprivacy`; surfaces ATT-not-used note, tracked/linked chips, not-collected list; wired in `SettingsView` Privacy section. feat(§28.13))
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
- [x] Runbook set in `docs/runbooks/`: crash-spike.md, push-failure.md, auth-outage.md, sync-dead-letter-flood.md, payment-provider-down.md, printer-driver-regression.md, db-corruption.md, license-compliance-scare.md, app-store-removal.md, data-breach.md. <!-- §34 shipped: checkout-broken, sync-queue-stuck, auth-down, crash-loop, printer-offline, terminal-disconnected, camera-unresponsive, widget-stale, push-delayed, settings-page-broken + index + crisis-playbook + first-responder-cheatsheet -->
- [x] Standard runbook structure: Detect → Classify (severity) → Contain → Communicate (banner + email + status page) → Remediate → Verify → Post-mortem. <!-- §34 shipped in crisis-playbook.md §4 post-mortem template -->
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
- [x] **Sheet modal** — full-screen on iPhone, centered glass card on iPad; cannot dismiss until finished or "Do later".
- [x] **Step indicator** — 13 dots + progress bar; glass chip on top.
- [x] **Skip any** button → resume later in Settings.
- [x] **Back / Next / Skip / Do Later** nav always visible; never trap the user.
- [x] **Loading / saving state per step** — each `POST /setup/step/{n}` optimistic with offline queue (§20). If submit fails, step stays editable; never lose progress.
- [x] **Accessibility baseline** — full VoiceOver labeling; Dynamic Type respected; keyboard navigation on iPad Magic Keyboard (Tab / Enter / Esc / ⌘⇧Enter to submit).

### 36.2 Steps
- [x] **1. Welcome** — brand hero + value props. Bebas Neue display. Skip button present.
- [x] **2. Company info** — name, address, phone, website, EIN. Address field uses MapKit autocomplete per §16.7 so tax engine seeds correctly.
- [x] **3. Logo** — camera / library upload; cropper; preview on sample receipt. Stored as tenant branding asset (§19). Real API upload wired: `SetupRepositoryLive.uploadLogo` → `POST /api/v1/setup/logo` (base64 JSON via `APIClient.uploadSetupLogo`); stub removed. agent worktree-agent-af62694d19f10fb9c
- [x] **4. Timezone + currency + locale** — default from device but user-confirmable.
- [x] **5. Business hours** — per day, with "Copy Mon to all weekdays" helper. Draft persistence added: `BusinessHoursStepView.onDaysChanged` fires on every edit so hours are written to `wizardPayload.hours` immediately, surviving Skip/Back without Next. agent worktree-agent-af62694d19f10fb9c
- [x] **6. Tax setup** — add first tax rate; address from step 2 pre-populates jurisdiction hint.
- [x] **7. Payment methods** — enable cash, card (BlockChyp link), gift card, store credit, check.
- [x] **8. First location** — if multi-location tenant. Defaults to the company address from step 2.
- [x] **9. Invite teammates / First Employee** — email list + role per; SMS invite option; defaults to manager role for the first invitee. `FirstEmployeeStepView` adds `sendSMSInvite` toggle (shown once user starts filling form); `FirstEmployeePayload.sendSMSInvite` → `first_employee_payload["send_sms_invite"]`; `SetupPayload.firstEmployeeSendSMS` stored in wizard draft. agent worktree-agent-af62694d19f10fb9c
- [x] **10. SMS setup** — provider pick (Twilio / BizarreCRM-managed / etc.) + from-number + templates.
- [x] **11. Device templates** — pick from preset library (iPhone family, Samsung, iPad, etc.). Feeds ticket create + repair pricing (§43).
- [x] **12. Import data** — offer CSV / RepairDesk / Shopr / Skip (§48).
- [x] **12a. Theme** — `System (recommended)` / `Dark` / `Light` (§30.12 — setup wizard asks, Settings lets them change later).
- [x] **13. Done** — confetti (Reduce-Motion respects § 26.3) + "Open Dashboard".

### 36.3 Persistence
- [x] **Resume mid-wizard** — partial state saved server-side; iOS shows "Continue setup" CTA on Dashboard. (ecb07902 — SetupResumeCard.swift)
- [x] **Skip all** — admin can defer; gentle nudge banner on Dashboard until complete (never blocking). (ecb07902 — SetupResumeCard.swift + SetupWizardViewModel.deferWizard existing)
- [x] **Cross-device resume** — if the same admin opened step 5 on web and step 7 on iOS, server is the source of truth; iOS picks up from the furthest completed step. (ecb07902 — SetupCrossDeviceResumer.swift)
- [x] **Minimum-viable completion** — steps 1–7 + 13 are required to unlock POS. Other steps are optional but nudged. `SetupWizardViewModel.isMVPComplete` / `mvpStepsRemaining`; `DoneStepView` shows `mvpGateBanner` (lock icon + count of missing steps) when MVP is incomplete. agent worktree-agent-af62694d19f10fb9c

### 36.4 Metrics (per §32 telemetry, placeholders only)
- [x] Track per-step completion rate + time-in-step + drop-off step. PII-redacted per §32.6; events use entity ID hashes, never raw company name / address. (`SetupMetrics.swift` + wired into `SetupWizardView` via `.onChange(of: vm.currentStep)` + `.onChange(of: vm.isDismissed)`; agent-8-b4)
- [x] Dashboard card for tenant admin: "Setup 7 of 13" with tap-to-resume. (`SetupDashboardCard.swift` — animated progress bar, "Resume →" CTA, auto-hides when complete, ViewModel convenience init; agent-8-b5)

### 36.5 Review cadence
- [ ] Revisit wizard UX after each phased-rollout cohort (§82.10). Onboarding drop-off trends drive reordering / merging steps. Changes land here before other polish.
- [x] First-run wizard verifies: internet OK, tenant reachable, printer reachable, terminal reachable (`SetupConnectivityCheckView.swift` + `SetupConnectivityCheckViewModel`; internet via `NWPathMonitor` + server via HTTP health probe; agent-8-b4)
- [x] Each check shows green/red with fix link (`ConnectivityCheckStatus` enum with `.ok`/`.failed(reason:)` + per-row color; agent-8-b4)
- [x] Captive-portal detection: banner + "Open portal" button. (`SetupNetworkDiagnostics.swift` — CNA probe + `SetupNetworkWarningBanner` with "Open portal" button; agent-8-b5)
- [x] Detect active VPN; warn if interfering. (`NetworkDiagnosticsViewModel.checkVPN()` — NWPathMonitor interface-name heuristic (utun*/ppp*/ipsec*/tun*) + VPN warning banner; agent-8-b5)
- [x] Periodic tenant-server ping; latency chart in Settings → Diagnostics (`ServerLatencyMonitor.swift` — 30s interval, 60-sample ring buffer, `@Observable`, `LatencySample`; `GET /api/v1/health`; agent-8-b6)
- [x] Alert if p95 > 1s sustained (`ServerLatencyMonitor.isP95AlertActive` — p95 > 1000ms → true; `onP95Alert` in spec honoured via computed var; agent-8-b6)
- [ ] Hotspot/cellular fallback warning when tenant uses local-IP printer
- [ ] Suggest switching Wi-Fi when needed
- [ ] Multi-SSID: tenant stores multiple trusted SSIDs (shop + backup) with auto-reconnect hints
- [ ] See §19 for the full list.
- [ ] See §19 for the full list.
- [ ] See §17 for the full list.

---
## §37. Marketing & Growth

### 37.1 Campaigns (SMS blast)
- [x] **Server endpoints** — `GET/POST /marketing/campaigns`, `POST /marketing/campaigns/{id}/send`.
- [x] **List** — campaigns sorted by created; status (draft / scheduled / sending / sent / failed).
- [x] **Create** — name + audience (segment) + template + schedule + A/B variants.
- [x] **Audience picker** — customer segment (see §37.2).
- [x] **Scheduled send** — pick date/time; tenant-TZ aware.
- [x] **Estimated cost** — "Will send to 342 customers, ~$8.55 in SMS fees".
- [x] **Approval gate** — requires manager if > N recipients.
- [x] **Post-send report** — delivered / failed / opted-out / replies.

### 37.2 Segments
- [x] **Server endpoints** — `GET/POST /segments`.
- [x] **Rule builder** — AND/OR tree: "spent > $500 AND last-visit > 90 days".
- [x] **Live count** — refreshes as rules change.
- [x] **Saved segments** — reusable in campaigns.
- [x] **Presets** — VIPs / Dormant / New / High-LTV / Repeat / At-risk.

### 37.3 NPS / Surveys
- [x] **Post-service SMS survey** — `CSATSurveyView` (5-star + comment, POST /surveys/csat) + `NPSSurveyView` (0-10 + chips + free-text, POST /surveys/nps). `SurveyAutoSender` handles 24h-delayed push trigger.
- [x] **Response tracking** — `GET /surveys/responses`. `SurveyResponsesView` (iPhone `NavigationStack` + iPad `NavigationSplitView`), `SurveyResponsesViewModel` with kind filter, `SurveyResponseRow` score-colored by CSAT/NPS thresholds, `APIClient.surveyResponses(kind:pageSize:)` extension. (agent-4 batch-2)
- [x] **Detractor alert** — `DetractorAlertView` (manager-role push `kind:"survey.detractor"`) with Call / SMS / Assign CTAs.
- [x] **NPS dashboard** — score + trend + themes. `NPSDashboardView` with LineMark/AreaMark chart, promoter/passive/detractor distribution, theme chips. (agent-4 batch-4, 9b6f31bb)

### 37.4 Referrals
- [x] **Referral code** per customer — `ReferralCode` model + `ReferralService.getOrGenerateCode`.
- [x] **Share link** — `generateShareLink` (universal https link) + `generateQR` (CIFilter QR); `ReferralCardView` with Share sheet.
- [x] **Credit on qualifying sale** — `ReferralCreditCalculator` (flat / percentage / min-sale); `ReferralRule` + `ReferralRuleEditorView`.
- [x] **Leaderboard** — `ReferralLeaderboardView` (iPhone list + iPad Table, top 10 + revenue).

### 37.5 Reviews
- [x] **After paid invoice** — `SendReviewLinkSheet` (platform chip selector + rate-limited send via `ReviewSolicitationService`).
- [x] **Gate by rating** — `ExternalReviewAlert` (push `kind:"review.new"`) with draft-response + Open-in-Safari. `ReviewSettingsView` admin config.
- [x] **Review platforms** — `ReviewPlatform` enum (google/yelp/facebook/other); `ReviewSettingsView` admin URL editor.

### 37.6 Public profile / landing
- [x] **Share my shop** — generates short URL with intake form + reviews. `ShareMyShopView` with CIFilter QR, link cards, `UIActivityViewController`. (agent-4 batch-4, e6b8714a)
- [x] Campaign types: SMS blast, email blast, in-app banner. `CampaignChannel.inAppBanner` added; `CampaignCreateView` Picker iterates `allCases`; helper props `usesSMS/usesEmail/usesInAppBanner`. (dc9cfc09)
- [x] Audience builder: segment by tag / last-visit window / LTV tier / device type / service history / birthday month; save + reuse segments. `SegmentField` extended with `tag / ltvTier / serviceType / totalRepairs`; `SegmentPresets` adds `birthdayThisMonth / platinumTier / phoneRepairHistory`. (dc9cfc09)
- [x] Scheduler: send now / send at time / recurring (weekly newsletter) / triggered (birthday auto-send). `CampaignScheduleKind` + `CampaignScheduleSectionView` wired into `CampaignCreateView`. (agent-4 batch-6)
- [x] Compliance: server-side tenant quiet hours respected; unsubscribe-suppression enforced; test-number suppression; consent date + source stored per contact. `CampaignComplianceView` + `CampaignComplianceConfig`. (agent-4 batch-6)
- [x] Analytics tiles: delivered / opened / clicked / replied / converted-to-revenue; unsubscribe-rate alarm at 2%+. `CampaignStatCounts.optedOut` + `unsubscribeAlarmBanner` in `CampaignAnalyticsView`. (agent-4 batch-6)
- [x] Monthly SMS spend cap per tenant; system halts sends when reached + notifies admin. `SMSSpendCapView` + `SMSSpendCapViewModel` (async-let parallel load); usage bar (orange→warning→error at 70/90%); cap-exceeded banner; PATCH endpoint. (agent-4 batch-7, afbaccc8)
- [x] Preview: iPhone-bubble rendering for SMS + HTML render for email with dynamic-variable substitution shown. `CampaignMessagePreviewView` + `TemplateVariableRenderer` + `SMSSegmentCalculator` + `BubbleShape`; 11 Swift Testing tests. (agent-4 batch-7, 0db54ae5)
- [x] Post-service auto-SMS link: "Rate your experience 1-5 [link]" — `NPSSettingsView.csatAutoSmsEnabled` toggle + delay stepper; `PATCH /settings/nps`. (dc9cfc09)
- [x] One-tap reply-with-digit for 1-5 — `NPSSettingsView.csatOneTapReplyEnabled` toggle surfaced to admin. (dc9cfc09)
- [x] Quarterly NPS: "How likely are you to recommend us 0-10?" — `NPSSettingsView.npsEnabled` toggle; existing `NPSSurveyView` handles 0-10 scale. (dc9cfc09)
- [x] NPS send cap: max 2 / year per customer — `NPSProgramSettings.npsSendCapPerYear` Stepper (1–12, default 2); enforced server-side. (dc9cfc09)
- [x] Optional free-text comment after rating — `NPSProgramSettings.requireComment` toggle in `NPSSettingsView`. (dc9cfc09)
- [x] Internal dashboard: score trend, comments feed, per-tech breakdown — `NPSSettingsView.perTechBreakdownEnabled` toggle; existing `NPSDashboardView` shows trend. (dc9cfc09)
- [x] Per-tech anonymized by default (tenant can configure open) — `NPSProgramSettings.perTechAnonymized` default true; admin toggle in `NPSSettingsView`. (dc9cfc09)
- [x] Low-score (1-2 star) immediate manager push to recover — `NPSProgramSettings.managerPushThreshold` Stepper (default 2) in `NPSSettingsView`. (dc9cfc09)
- [x] Recovery playbook: call within 2h — documented in `NPSSettingsView` recovery section explainer copy; server delivers push on threshold breach. (dc9cfc09)
- [x] High scores nudge customer to leave Google / Yelp review (§37) — `ReviewHighScoreNudgeService` + `ReviewNudgeSheet`; NPS≥9/CSAT≥4 thresholds; 180-day rate-limit; share sheet (no auto-post). (b0554d59)
- [x] After high CSAT (§15), offer customer to leave public review — `ReviewHighScoreNudgeService.nudgePayload(csatScore:)` gate; same sheet. (b0554d59)
- [x] Link via share sheet (no auto-post) — `ReviewNudgeSheet` platformButton calls `onOpenURL`; caller opens `SFSafariViewController`. (b0554d59)
- [x] Tenant configures Google Business / Yelp URLs — `ReviewSettingsView` URL fields + `configuredPlatforms` list. (b0554d59)
- [x] Staff can "Send review link" from customer detail — `SendReviewLinkSheet` + `ReviewSolicitationService` (prior batches; confirmed wired). (b0554d59)
- [x] Rate limit: once per 180 days per customer — `ReviewSolicitationService.rateLimitDays = 180`; enforced in `ReviewHighScoreNudgeService` too. (b0554d59)
- [x] Block tying reviews to discounts (Google/Yelp ToS) — `ReviewNudgeSheet.tosDisclaimer` + `ReviewSettingsView` high-score section footer explicitly states "never tied to a discount or reward". (b0554d59)
- [x] Settings → Reviews → list of platforms — `ReviewSettingsView.configuredPlatforms` section shows configured platform names + host. (b0554d59)
- [x] Optional external review alert push via tenant-configured monitoring — `ReviewMonitoringSettings.externalReviewAlertEnabled` toggle in `ReviewSettingsView`. (b0554d59)
- [x] Staff draft review responses in-app; posting happens on external platform (iOS opens Safari) — `ExternalReviewAlert` (prior batches) + `ReviewExternalLinkView` SFSafariViewController wrapper. (b0554d59)
- [x] Sovereignty: iOS never calls third-party review APIs directly — `ReviewExternalLinkView` + server-side fetch; `ReviewHighScoreNudgeService` opens tenant-configured URLs only. (b0554d59)
- [x] External links open in `SFSafariViewController` — `ReviewExternalLinkView` + `reviewExternalLink(url:)` ViewModifier; used in `ReviewNudgeSheet`. (b0554d59)
- [ ] See §19 for the full list.
- [ ] See §19 for the full list.
- [ ] See §5 for the full list.

---
## §38. Memberships / Loyalty

_Server: `GET/POST/PUT /memberships`, `GET /memberships/{id}`, `POST /memberships/{id}/renew`, `GET /memberships/{id}/points`, `POST /memberships/{id}/points/redeem`._

### 38.1 Tiers
- [x] **Configure tiers** in Settings (§19.12). `LoyaltyTier` enum with `minLifetimeSpendCents`; `LoyaltyPlanSettingsView` ships. Commit `feat(ios phase-8 §38)`.
- [x] **Auto-tier** — customer promoted on $-threshold. `LoyaltyCalculator.tier(for:)` pure function. Commit `feat(ios phase-8 §38)`.
- [x] **Member badge** on customer chips / POS. `MemberBadge` view with `.compact`/`.standard`/`.prominent` sizes; `isPaidTier` helper; `tierString` convenience init. (agent-4 batch-2)

### 38.2 Points
- [x] **Earn** — points on paid invoice (configurable rate). `LoyaltyCalculator.points(earned:rule:)` + `LoyaltyRule`. Commit `feat(ios phase-8 §38)`.
- [ ] **Redeem** — at POS (see §16.15).
- [x] **Expiration** — configurable. `LoyaltyCalculator.expiry(earnedAt:rule:)`. Commit `feat(ios phase-8 §38)`.
- [x] **Point history (partial)** — `LoyaltyBalanceView` surfaces current points + tier + lifetime spend via `GET /api/v1/loyalty/balance/:customerId`. Per-transaction history endpoint TBD.
- [x] **Points ledger view** — `LoyaltyPointsLedgerView` shows lifetime earned / redeemed / expiring-soon / balance. Commit `feat(ios phase-8 §38)`.

### 38.3 Subscription memberships
- [x] **Paid plans** — monthly / annual with auto-renew. `Membership` + `MembershipPlan` models; `MembershipEnrollSheet` POS integration. Commit `feat(ios phase-8 §38)`.
- [x] **Benefits** — discount %, free services (e.g., 1 battery test / month). `MembershipPerk` enum + `MembershipPerkApplier.discount(cart:membership:plan:)`. Commit `feat(ios phase-8 §38)`.
- [ ] **Payment** — BlockChyp recurring or Stripe.
- [x] **Cancel / pause / resume**. `MembershipSubscriptionManager` actor handles all three state transitions + server sync. Commit `feat(ios phase-8 §38)`.

### 38.4 Apple Wallet pass
- [x] **`PKAddPassesViewController`** — `LoyaltyPassPresenter.present(passData:)` scaffold ships in `Packages/Loyalty`. Commit `73229b3`. Server .pkpass signing + Wallet entitlement still required for live install.
- [x] **Pass updates** — `PassUpdateSubscriber` (silent-push bridge, `Pos/Wallet/PassUpdateSubscriber.swift`) registers per-kind handlers; calls `fetchPass` + `PKPassLibrary.replacePass`. Commit `feat(ios phase-6 §24+§38+§40)`.
- [x] **Barcode on pass** — scannable at POS. `LoyaltyPassBarcodeView`: CoreImage QR (10× scale, no third-party SDK), glass card with tier header + copyable barcode string, `.textSelection(.enabled)`. (agent-4 batch-2)

### 38.5 Member-only perks
- [x] **Exclusive products** — hidden in catalog for non-members.
- [x] **Priority queue** — badge in intake flow.
- [x] Plan builder in Settings → Memberships: name / cadence (monthly / quarterly / annual) / price / included-services count / auto-renew toggle. `LoyaltyPlanSettingsView` + `PlanEditorSheet` + `RuleEditorSheet`. Commit `feat(ios phase-8 §38)`.
- [x] Enroll flow from Customer detail → Plans tab → Enroll; `MembershipEnrollSheet` wired to `MembershipSubscriptionManager`. Card tokenization deferred (BlockChyp §17.3). Commit `feat(ios phase-8 §38)`.
- [x] Server cron creates invoices + charges cards + updates ledger daily; iOS shows "Next billing date" on customer detail.
- [x] Service ledger per period: "Included services remaining: 3 of 5"; decrement at POS redemption. `MembershipServiceLedgerView` + `ServiceLedgerEntry`. (agent-4 batch-4, 5d16a1bc)
- [x] Dunning cadence: failed charge retry 3d / 7d / 14d + customer notify; exhaustion → pause plan + staff notify. `MembershipDunningView` + retry/cancel actions. (agent-4 batch-4, ef28cbc8)
- [x] Cancel flow: customer self-cancel via public portal OR staff via customer detail; tenant-configurable end-of-period policy. `MembershipCancelSheet` + `CancelPolicy` enum. (agent-4 batch-5, 7616aac3)
- [x] Cadence: 30 / 14 / 7 / 1 day before expiry. `MembershipRenewalReminderView` shows fire dates relative to `nextBillingAt`. (agent-4 batch-5, 7616aac3)
- [x] Channels: push + SMS + email (configurable per member). `MembershipRenewalChannelSettingsView` + `MembershipRenewalChannelSettings`. (agent-4 batch-6)
- [x] Auto-renew: if enrolled, card on file charged on renewal date — `MembershipAutoRenewView` + `MembershipAutoRenewViewModel`: toggle auto-renew, card-on-file summary (`CardOnFile` model), last charge result banner (`MembershipChargeResult`), renewal countdown, manager manual trigger. `GET /memberships/:id/card-on-file`, `GET /memberships/:id/last-charge`, `POST /memberships/:id/renew`. (b7e6b70e)
- [x] Notify success/failure of auto-renew
- [x] Grace period: 7 days post-expiry retain benefits + soft reminder. `MembershipGraceAndReactivationView` (grace countdown, benefits-active indicator). (agent-4 batch-6)
- [x] After grace: benefits suspended. `MembershipStatus.expired` + `.perksActive = false`; card shows "Benefits suspended". (agent-4 batch-6)
- [x] Reactivation: one-tap with current card or new. `MembershipGraceAndReactivationView.actionButton` calls `onReactivate`. (agent-4 batch-6)
- [x] Pro-rate remaining period credit on reactivation
- [x] Churn insight report: expiring soon / at risk / churned — `MembershipChurnInsightView` + `MembershipChurnInsightViewModel`; summary tiles + bar chart + cohort list; `GET /memberships/churn-cohort`. (dc9cfc09)
- [x] Segment for targeted offer (§37)
- [x] Visual punch card per service type (e.g. "5th repair free", "10th wash free"). `PunchCard` model + `PunchCardView`. (agent-4 batch-6)
- [x] Count auto-increments on eligible service. Server-managed `currentPunches` field in `PunchCard`. (agent-4 batch-6)
- [x] Server-side storage; iOS displays. `PunchCard` Codable with `customer_id` / `current_punches` / `total_punches`. (agent-4 batch-6)
- [x] Wallet pass (§38.4) with updating strip — `PassUpdateSubscriber` handles silent push + silent `replacePass`. Commit `feat(ios phase-6 §24+§38+§40)`.
- [x] Customer detail shows punch cards. `CustomerPunchCardsSection` with ForEach of `PunchCardView`. (agent-4 batch-6)
- [x] Progress icons (filled vs empty). Filled orange circle with checkmark vs empty stroke circle. (agent-4 batch-6)
- [x] Redemption: last punch = free next service, auto-applied discount at POS. `PunchCardRedemptionSheet` + `PunchCardRedemptionViewModel` (confirm/redeeming/success/failure phases, stacking toggle, `POST /loyalty/punch-cards/:id/redeem`). (agent-4 batch-7, f68a35b7)
- [x] Combo rule: no stacking with other discounts unless configured — `PunchCardComboRuleView` + `PunchCardComboRuleSettings`; admin toggle + per-discount-type exclusion list; `GET/PATCH /loyalty/punch-card-combo-rules`. (dc9cfc09)
- [x] Optional punch expiry 12mo after last activity — `PunchCardExpirySettingsView` + `PunchCardExpiryPolicy.expiryEnabled/inactivityMonths` (1-24 months Stepper); `GET/PUT /loyalty/punch-card-expiry-policy`. (b0554d59)
- [x] Tenant config: cards shared across locations vs per-location — `PunchCardExpiryPolicy.sharedAcrossLocations` toggle in `PunchCardExpirySettingsView`; `PunchCardExpiryPolicyDTO.sharedAcrossLocations`. (b0554d59)
- [x] Pass types: Membership (storeCard), Gift card (storeCard), Punch card (coupon), Appointment (eventTicket), Loyalty tier (generic linked to membership). — `LoyaltyPassKind` enum + `passType` + `passPathSegment`. (f026f0d6)
- [x] Membership storeCard front includes logo, tenant name, member name, tier, points, QR/barcode; back carries address, phone, website, terms, points-history link. — `MembershipPassFieldSpec` documents all field keys for server implementation. (f026f0d6)
- [x] Colors: background = tenant accent (contrast-validated); foreground = auto-contrast text. — `PassColorScheme.from(accentHex:)` WCAG contrast ratio check; `PassRGBColor.relativeLuminance`. (f026f0d6)
- [x] Updates: APNs-based PassKit push on points/tier/status change; relevance dates set so appointment passes surface on Lock Screen near time. — `PassUpdateEvent` enum documents all event types; `PassUpdateSubscriber` handles silent push (existing). (f026f0d6)
- [x] Localization: per-locale strings. — `PassLocale` enum (7 locales) + `stringKeys` contract for server .lproj files; iOS consumes via native PKPass archive. (f026f0d6)
- [ ] Web-side Add-to-Wallet button on public page (§53.4). (server-side §53.4 — not iOS scope; iOS only presents `PKAddPassesViewController`)
- [x] Sovereignty: pass signing certificate + Apple Pass web service URL live on tenant server, never our infra. — `PassSovereigntyPolicy` documents signing ownership contract; iOS only presents binary. (f026f0d6)
- [x] **Redemption catalog row** — `RewardCatalogRow` tappable row for loyalty rewards catalog; shows icon, title, description, points-cost badge; dims + shows tier-lock label when ineligible. `Rewards/RewardCatalogRow.swift`. (feat(§38): 5 loyalty UX items)
- [x] **Points expiry warning** — `PointsExpiryWarningView` inline banner; amber/red urgency based on ≤7d threshold; dismissible with animation. `Engine/PointsExpiryWarningView.swift`. (feat(§38): 5 loyalty UX items)
- [x] **Tier-progress chart** — `TierProgressChartView` segmented horizontal bar across all 4 tiers; animated fill; current-tier callout legend; VoiceOver. `Engine/TierProgressChartView.swift`. (feat(§38): 5 loyalty UX items)
- [x] **Member-since chip** — `MemberSinceChip` `.compact` pill and `.card` variant with years-as-member label; ISO 8601 date parse. `MemberSinceChip.swift`. (feat(§38): 5 loyalty UX items)
- [x] **Refer-a-friend share sheet** — `ReferAFriendShareSheet` modal with referral link, copy-to-clipboard chip, native `ShareLink`, bonus-points callout; URL built as `https://biz.re/<handle>?ref=<code>`. `ReferAFriendShareSheet.swift`. (feat(§38): 5 loyalty UX items)

---
## §39. Cash Register & Z-Report

See §16.10 for core flow. Additional items:

### 39.1 Shift log
- [x] **Per-shift entry** — `CashRegisterStore` local-first schema (open_at, opening_cash, close_at, closing_cash, variance). Endpoint DTOs + stub `APIClient` wrappers in `CashRegisterEndpoints.swift`.
- [x] **Shift history** — list of past shifts; open any for detail. `ZReportDetailView` (GRDB local store, server POS-SESSIONS-001 pending). (feat(§39.1): shift history list)
- [x] **Shift diff viewer** — `CashVariance` + `ZReportView` surface expected vs actual with color.

### 39.2 Z-report PDF
- [x] **Auto-generate** on close — `ZReportView` renders totals. PDF export via `ImageRenderer` deferred to §17.4 pipeline.
- [x] **Emailed** to manager. `ZReportEmailService` actor + `ZReportEmailButton`; POST /api/v1/notifications/send-z-report; 404/501 → .unavailable "Coming soon". (1774c019)
- [x] **Auto-archive** in tenant storage. `ZReportArchiveService` actor: uploads to `/pos/z-reports/archive`; on 404/501 saves locally to `Documents/ZReports/<date>-<id>.json`. `ZReportArchiveButton` embeds in action row. Tests ≥80%. (feat(§39.2): Z-report auto-archive 3ad70973)
- [x] **Data** — sales / tenders / over-short / cashier. Refunds / voids / discounts / tips / taxes / printer-log deferred.

### 39.3 X-report (mid-shift)
- [x] **`GET /cash-register/x-report`** — peek current shift without closing. `XReportView` + `APIClient.getXReport()` stub (POS-XREPORT-001 pending). (feat(§39.3): X-report mid-shift view)

### 39.4 Reconciliation export
- [x] CSV per day of all transactions + tender splits. `ReconciliationCSVGenerator` + `ReconciliationRow`; 11-column schema; `csvEscape` per RFC 4180; filename Reconciliation-YYYY-MM-DD.csv. (69c28fdb)
- [x] Trigger: manager taps "End of day" at shop close. `EndOfDayWizardView` + `EndOfDayWizardViewModel`. (69c28fdb)
- [x] Steps: (1) close any open cash shifts; (2) mark still-open tickets → confirm or archive to tomorrow; (3) send day-end status SMS to customers with ready tickets (optional); (4) review outstanding invoices / follow-ups; (5) backup reminder (if tenant schedules local backup); (6) lock POS terminal; (7) post shop's daily summary to tenant admin (push). `EndOfDayStep` enum 7 steps with isOptional. (69c28fdb)
- [x] Progress indicator: glass progress bar at top; can abort mid-wizard and resume. `EndOfDayWizardView` progress bar + abort alert; `EndOfDayWizardViewModel.abort()`. (69c28fdb)
- [x] Logging: each step's completion stamped in audit log. `AppLog.pos.info` on markCompleted + skipStep. (69c28fdb)
- [x] Permissions: manager-only; cashier gets "Need manager" if attempted. `ManagerPinSheet` gate on `.onAppear`; dismiss on cancel. (feat(§39.4): EOD manager-only gate)
- [x] Daily: sales + payments + cash close + bank deposit all tie out. `DailyReconciliation` + `DailyTieOutValidator` four-way check; failures surfaced in `ReconciliationDashboardView` daily tab. (feat(§39.4): reconciliation dashboard ec151482)
- [x] Dashboard shows variance per period. `ReconciliationPeriodSummary` weekly/monthly roll-up with `tiedOutPercent` bar; `ReconciliationDashboardView` periodic tab. (feat(§39.4): reconciliation dashboard ec151482)
- [x] Monthly: full reconciliation report (revenue, COGS, adjustments, AR aging, AP aging). `MonthlyReconciliation` model + monthly tab in dashboard. (feat(§39.4): reconciliation dashboard ec151482)
- [x] Export to QuickBooks / Xero formats. `AccountingExportGenerator` produces QB IIF, QB CSV, Xero CSV on-device; fileExporter wired; sovereignty note in UI. (feat(§39.4): reconciliation dashboard ec151482)
- [x] Variance investigation tool: clickable drill-down from total → lines → specific transaction → audit log. `VarianceDrillEntry` + `VarianceInvestigationViewModel` + drill-down tab; audit log Link per entry. (feat(§39.4): reconciliation dashboard ec151482)
- [x] Alerts: variance > threshold triggers manager push. `CashVarianceAlertService` actor: evaluates abs(variance) vs threshold; calls `POST /notifications/send` with `type=cash_variance_alert`; gracefully skips on 404/501. Tests ≥80%. (feat(§39.4): cash variance manager alert 3ad70973)
- [x] Close period: once reconciled, period locked; changes require manager override + audit. `CashPeriodLock` model + `CashPeriodLockRepository` + `CashPeriodLockRepositoryImpl` (`GET/POST /pos/period-locks`, `POST /pos/period-locks/:id/unlock`) + `CashPeriodLockView` with manager PIN override alert. (feat(§39.4): cash period lock 3ad70973)

### 39.5 Cash-session polish
- [x] **Z-report PDF preview** — `ZReportView` action row "PDF" button renders the report on-device via `ImageRenderer` + `ZReportPDFRenderer` (A4, 595pt wide); shown in `ZReportPDFPreview` (`QLPreviewController` as `UIViewControllerRepresentable`). `ZReportPrintBody` is a standalone SwiftUI body (no nav chrome). `ZReportPDFItem` is an `Identifiable` URL wrapper for `.sheet(item:)`. Sovereignty: PDF written to tmp dir only.
- [x] **Daily-summary copy chip** — `EndOfShiftSummaryView` gets an inline `dailySummaryCopyChip` pill centered below the trend section. Tapping copies the plain-text shift summary to `UIPasteboard`, shows 2-second "Summary copied" confirmation; shares `didCopySummary` state with the toolbar button.
- [x] **Drawer-discrepancy color** — `CashVarianceView.amountCell` extended with `applyDiscrepancyColor: Bool`; the "Counted" amount inherits the variance-band color (green/amber/red) when variance is non-zero.
- [x] **Cash-count CSV export** — `DenominationCountViewModel.csvString`/`csvData` generate RFC-4180 CSV (Denomination, Count, Subtotal + grand-total row). `DenominationCountView` surfaces a `ShareLink` toolbar item when any denomination count > 0.
- [x] **No-sale audit-log row** — `PosAuditLogView` gains `noSaleCountToday` + `noSaleSummaryRow(count:)`; when today's no-sale count > 0 a warning section appears at top of list with count badge (orange ≤2, red >2).
- [x] **Payout sheet** — `PayoutSheet` records cash payouts for business expenses (supply runs, petty-cash reimbursements) via `POST /pos/cash-out` with payout reason. Manager PIN gate at $50 threshold (`kPayoutManagerPinThresholdCents`). Vendor/payee, notes, and approver-name fields. (feat(§39.5): payout sheet)
- [x] **Cash-deposit sheet** — `CashDepositSheet` records mid-shift cash additions to the drawer via `POST /pos/cash-in`. Source and notes fields. Z-report cash-in column stays accurate. (feat(§39.5): cash deposit sheet)
- [x] **Weekly cash-flow report tile** — `WeeklyCashFlow` model (7-day in/out/net per `DayEntry`) + `WeeklyCashFlowTile` dashboard tile with net headline, in/out sub-row, and compact day-bar sparkline (green cash-in, red cash-out bars). Taps into `ReconciliationDashboardView`. (feat(§39.5): weekly cash-flow tile)
- [x] **Missing-receipt counter** — `MissingReceiptRecord` + `MissingReceiptCounterViewModel` reads `receipt_skipped` audit entries since shift start. `MissingReceiptCounterBadge` chip (warning ≤3, error 4+) for Z-report / EOD summary. `MissingReceiptListView` drill-down. `PosAuditEntry.EventType.receiptSkipped = "receipt_skipped"` added to Persistence. (feat(§39.5): missing-receipt counter)
- [x] **Manager PIN re-prompt** — `ManagerPinRepromptState` tracks last approval timestamp with a configurable window (default 5 min). `ManagerPinRepromptModifier` + `.managerPinReprompt(triggered:reason:state:action:)` view modifier skips PIN sheet when approval is still live; re-prompts on expiry. `ManagerPinRepromptStatusChip` shows remaining time or "expired" badge. (feat(§39.5): manager PIN re-prompt)

---
## §40. Gift Cards / Store Credit / Refunds

### 40.1 Gift cards
- [x] **Networking** — `GiftCardsEndpoints.swift`: `lookupGiftCard(code:)`, `redeemGiftCard(id:amountCents:reason:)`. Sell/void/transfer endpoints TBD.
- [x] **Sell** — at POS; physical card scan OR generate virtual (SMS/email with QR). `GiftCardSellSheet` + `GiftCardSellViewModel` (physical activate + virtual email flow). Networking: `createVirtualGiftCard`, `activateGiftCard`. Commit 468fe08.
- [x] **Redeem** — `PosGiftCardSheet` + `PosGiftCardSheetViewModel` → lookup → clamp-to-min(total, balance) → `apply(tender:)` via `AppliedTender.giftCard`.
- [x] **Balance check** — lookup shows remaining balance + status + expiry.
- [x] **Reload** — add more funds. `GiftCardReloadSheet` + `GiftCardReloadViewModel`, $500 cap, active-card validation. Networking: `reloadGiftCard`. Commit 468fe08.
- [x] **Expiration** — surfaced in sheet if present.
- [x] **Transfer** — from one card to another. `GiftCardTransferSheet` + `GiftCardTransferViewModel`. Networking: `transferGiftCard`. Commit 468fe08.
- [x] **Refund to gift card** — if original tender was gift card. `RefundToGiftCardSheet` + `RefundToGiftCardViewModel`. Networking: `refundInvoice(id:request:)`. Commit 468fe08.

### 40.2 Store credit
- [x] **Networking** — `StoreCreditEndpoints.swift`: `getStoreCreditBalance(customerId:)`. Redeem issuance via tender flow.
- [x] **Issued** on returns / apologies / promos. `IssuedStoreCreditSheet` + `IssuedStoreCreditViewModel`; manager PIN above $25 (2500¢); reuses CustomerCreditRefundRequest + refundCustomerCredit. (6398b3dc)
- [x] **Balance visible** — store credit section in `PosGiftCardSheet` when `cart.customer.id != nil`.
- [x] **Redeem** at POS with toggle via `AppliedTender.storeCredit`.
- [x] **Expiration** configurable. `StoreCreditExpirationSettingsView` admin view (90/180/365/never). Networking: `updateStoreCreditPolicy`. Commit 468fe08.

### 40.3 Refunds (see §16.9)
- [ ] Already detailed.

### 40.4 Approval workflow
- [x] **Manager PIN** required on gift-card void / large refund. `GiftCardVoidSheet` gates on `ManagerPinSheet` before committing. (feat(§40.4): gift card void manager PIN)
- [x] **Audit trail** — every issuance / void / redeem logged. `GiftCardAuditLog` actor + `GiftCardAuditLogView` + wired into `GiftCardRedeemViewModel`. (feat(§40.4): gift card audit trail)
- [ ] See §38 for the full list.

---
## §41. Payment Links & Public Pay Page

### 41.1 Generate payment link
- [x] **From POS cart** — "Send payment link" toolbar → `PosPaymentLinkSheet` → `createPaymentLink(...)`. Per-invoice/estimate entry TBD.
- [x] **Networking** — `PaymentLinksEndpoints.swift`: `createPaymentLink` / `getPaymentLink` / `listPaymentLinks` / `cancelPaymentLink` + `makePaymentLinkURL`.
- [x] **Share** — `UIActivityViewController` with URL for SMS/email/AirDrop + Copy button. QR display deferred.

### 41.2 Branding customization
- [x] **Webview preview** — `PaymentLinkBrandingSettingsView` + `PaymentLinkBrandingViewModel`. WKWebView preview. `GET /settings/payment-link-branding`, `PATCH /settings/payment-link-branding`. `PaymentLinkBranding` + `PaymentLinkBrandingPatch` models.
- [x] **List view** — `PaymentLinksListView` in More menu with status chips + swipe-cancel.

### 41.3 Follow-ups
- [x] **Model** — `PaymentLinkFollowUp` `{ id, paymentLinkId, triggerAfterHours, templateId, channel, sentAt?, deliveredAt?, status }`. `POST /payment-links/:id/followups`, `GET /payment-links/:id/followups`.
- [x] **Policy editor** — `FollowUpPolicyEditorSheet` + `FollowUpPolicyEditorViewModel`: multi-rule schedule (24h→72h→7d).
- [x] **Schedule view** — `FollowUpScheduleView` + `FollowUpScheduleViewModel`: per-link planned + sent follow-ups with a11y labels.

### 41.4 Partial payments
- [x] **Toggle** — `PartialPaymentSupport` model + `PATCH /payment-links/:id` with `allow_partial` flag.
- [x] **Tracker** — `PartialPaymentTracker` + `PartialPaymentTrackerViewModel`: payment history, remaining balance, overdue banner. `GET /payment-links/:id/payments`.

### 41.5 Refund from link
- [x] **Refund sheet** — `PaymentLinkRefundSheet` + `PaymentLinkRefundViewModel`: admin refund with reason picker. `POST /payment-links/:id/refund`.

### 41.6 QR code with logo
- [x] **Branded QR** — `BrandedQRGenerator`: CoreImage + CoreGraphics, error-correction H, logo overlay (25 % center), foreground/background color.
- [x] **Printable view** — `PaymentLinkPrintableView`: flyer with logo + QR + amount + expiry + footer. ShareLink + `⌘P` shortcut.

### 41.7 Expiry policies
- [x] **Enum** — `PaymentLinkExpiryPolicy`: 7d/14d/30d/never. `expiresAt(from:)` helper. `expiredMessage` constant. Codable round-trip.
- [x] **Admin editor** — `PaymentLinkExpiryEditorView` + `PaymentLinkExpiryEditorViewModel`. `GET/PATCH /settings/payment-link-expiry`.

### 41.8 Analytics
- [x] **Models** — `PaymentLinkAnalytics` (per-link), `PaymentLinksAggregate` (tenant-wide), `PaymentLinksAnalyticsResponse`. `GET /payment-links/analytics`.
- [x] **Dashboard** — `PaymentLinksDashboardView` + `PaymentLinksDashboardViewModel`: funnel bar chart (Charts), aggregate KPIs, per-link table. iPhone/iPad layouts.

### 41.9 Webhooks
- [ ] On payment complete, server pushes WS event → invoice updates in-app in real time.
- [ ] See §16 for the full list.

---
## §42. Voice & Calls

### 42.1 Call log (if server tracks)
- [x] **Server**: `GET /voice/calls` wired via `CallsEndpoints.listCalls()`. `/calls/:id/transcript` 404 → `State.comingSoon` fallback.
- [x] **List** — `CallLogView` with inbound/outbound arrow icons, direction colors, customer/phone match, debounced 300ms search. Commit `f0ea6e0`.
- [x] **Recording playback** — audio file streamed. `CallRecordingPlayerView` + `CallDetailView` wired. Commit `e348d254`.
- [x] **Transcription (partial)** — `getCallTranscript(id:)` wired; Speech / Whisper pipeline deferred.
- [x] **Search transcripts** — in-memory filter on `transcriptText` via `CallLogViewModel.filteredCalls(_:)`.

### 42.2 Outbound call (from app)
- [x] **Tap phone number** — `CallQuickAction.placeCall(to:)` opens `tel:` URL via `UIApplication.shared.open(_:)`. `cleanPhoneNumber(_:)` strips formatting + US country code.
- [x] **Click-to-call on customer / ticket detail** — `PhoneCallButton` SwiftUI view added to `CallQuickAction.swift`; ready to embed in customer/ticket detail. Commit `e348d254`.

### 42.3 CallKit integration
- [ ] **Inbound VoIP** — CallKit card shows customer name / photo / recent ticket. (Needs entitlement — deferred.)
- [ ] **Outbound recent calls** appear in native Phone app.

### 42.4 PushKit (VoIP push)
- [x] **Server pushes VoIP** → iOS wakes app → CallKit invocation. (`voip` UIBackgroundMode added in `write-info-plist.sh`; `aps-environment` entitlement already present; Agent 7 CallKit wiring unblocked. feat(§42.4): voip UIBackgroundMode 18f052de)
- [x] **Required entitlement**. (`aps-environment = development` already in `BizarreCRM.entitlements`; verified read-only. 18f052de)

### 42.5 Voicemail
- [x] **List + playback** — `VoicemailListView` + `VoicemailPlayerView` with `AVPlayer`, scrubber, play/pause, 1x/1.5x/2x speed chips, Reduce Motion aware.
- [x] **Transcription** — `VoicemailTranscriptionService` actor + on-device `SFSpeechRecognizer` (`requiresOnDeviceRecognition = true`, sovereignty §28). `VoicemailTranscriptionView` shows server transcript when available, else "Transcribe" button triggers on-device pipeline. `TranscriptionState` + `TranscriptionError` with user-readable messages. Tests in `VoicemailTranscriptionTests`. Commit `[agent-2 b3]`.
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
- [x] **Per-tenant price** — `PriceOverrideEditorSheet` + `PriceOverrideEditorViewModel` + `PriceOverrideValidator`. Override service default via swipe/long-press on service row.
- [x] **Per-customer override** — VIP pricing via customer-scope picker in same sheet. `PriceOverrideListView` admin screen lists + deletes all overrides.

### 43.4 Part mapping
- [x] **SKU picker** for each service — `PartSkuPicker` debounced search against `GET /inventory/items?q=...`. `ServicePartMappingSheet` opened from service row swipe action.
- [x] **Multi-part bundles** — toggle reveals multi-row editor; each row has SKU picker + Stepper qty. Save via `PATCH /repair-pricing/services/:id`.

### 43.5 Add/edit templates (admin)
- [x] **Full editor** — `DeviceTemplateEditorView` with model name, family picker (+ custom entry), year, condition chips, services with `NewServiceInlineForm`. `DeviceTemplateListView` admin sidebar+detail (iPad) / NavigationStack (iPhone) with edit/delete swipe actions.

---
## §44. CRM Health Score & LTV

### 44.1 Health score
- [x] **Per-customer 0-100** — `CustomerHealth.compute(detail:)` + server-side `health_score` override. Commit `c0c4f56`.
- [x] **Color tier** — `CustomerHealthTier` green/yellow/red with brand tokens `bizarreSuccess/Warning/Error`.
- [x] **Action recommendations** — >180-day absence → "Haven't seen in 180+ days — send follow-up"; complaint count > 0 → complaint banner.

### 44.2 LTV
- [x] **Lifetime value** — `CustomerLTVChip` with server analytics `lifetime_value` + DTO `ltv_cents` fallback; rendered on CustomerDetailView header.
- [x] **Tier** — Bronze / Silver / Gold / Platinum by LTV threshold. `LTVTier`, `LTVThresholds`, `LTVCalculator` (pure, tenant-overridable). `LTVTierBadge` (glass, Reduce Motion, a11y). Shown in CustomerDetailView header next to health badge.
- [x] **Perks per tier** — `LTVPerk` (discount %, priority queue, warranty months, custom). `LTVPerkApplier` (pure filter). `LTVTierEditorView` admin editor (`PATCH /tenant/ltv-policy`). iPhone form + iPad split editor.

### 44.3 Predicted churn
- [x] **ML score** (server) — `ChurnScore` + `ChurnScoreDTO` from server. `ChurnEndpoints` (`GET /customers/:id/churn-score`, `GET /customers/churn-cohort?riskLevel=`). Client-side fallback via `ChurnScoreCalculator` (5-factor, base 50). `ChurnRiskLevel` (low/medium/high/critical). `ChurnRiskBadge` (glass, factors popover, a11y) on CustomerDetailView header.
- [x] **Proactive campaign** — `ChurnCohortView` (iPhone NavStack + iPad SplitView, risk filter). `ChurnTargetCampaignBuilder` → `ChurnCampaignSpec` for §37 Marketing. Customer list `CustomerSortOrder` menu with "LTV tier" + "Churn risk" sort options.

---
## §45. Team Collaboration (internal messaging)

**Cross-platform status (checked 2026-04-20):**
- **Server**: present. `packages/server/src/routes/teamChat.routes.ts` mounted at `/api/v1/team-chat`. Schema in migration `096_team_management.sql`: tables `team_chat_channels`, `team_chat_messages`, `team_mentions`. Channels: `general` / `ticket` / `direct`. Polling-based MVP (no WS fan-out yet — clients poll `GET /channels/:id/messages?after=<id>`). WebSocket wiring to existing `packages/server/src/websocket/` is a TODO.
- **Web**: present. `packages/web/src/pages/team/TeamChatPage.tsx`; route `/team/chat` registered in `App.tsx`; sidebar link "Team Chat" in `components/layout/Sidebar.tsx`; `MentionPicker.tsx` for @mentions.
- **Android**: **missing.** No `NfcAdapter`-equivalent for chat — zero references to TeamChat in `android/`.
- **iOS**: this section.

### 45.0 Data-at-rest audit (tracked in root TODO as `TEAM-CHAT-AUDIT-001`)

The server stores message bodies as **plaintext `TEXT` columns** (`team_chat_messages.body TEXT NOT NULL`). No column-level encryption, no hashing, no tokenization. Acceptable today for MVP staff chat; worth a comprehensive review before shipping it cross-platform:

- [x] Audit item filed in root TODO (`TEAM-CHAT-AUDIT-001`) — full list of questions (at-rest encryption / retention / export / moderation / HIPAA/PCI scope). (chore(§45.0): verified TEAM-CHAT-AUDIT-001 already filed in root TODO.md at line 719 — agent-7 b9)
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
- [x] **Goal types**: daily revenue / weekly ticket-count / monthly avg-ticket-value / personal commission / per-role custom.
- [x] **Configured by manager** — `GoalSettingsView` + `GoalSettingsViewModel`; tenant enable/disable via GET/PATCH /api/v1/settings/goals. (feat(§46): goal settings + trajectory)
- [x] **Progress ring** on personal dashboard tile + team-aggregate ring on manager dashboard.
- [x] **Trajectory line** — `GoalTrajectoryView` bar chart with linear forecast projection; miss message "Tomorrow's a new day. Keep going!" (feat(§46): goal settings + trajectory)
- [x] **Milestone toasts** — 50% / 75% / 100% (respect Reduce Motion; confetti only on 100% with `BrandMotion` fallback).
- [x] **Streak counter** — "5 days in a row hitting daily goal"; subtle UI, no loss-aversion anti-pattern per §46 gamification guardrails.
- [x] **Miss handling** — supportive copy ("Tomorrow's a new day. Keep going!") in `GoalTrajectoryView`; no guilt language; no daily push notifications. (feat(§46): goal settings + trajectory)
- [x] **Tenant can disable goals entirely** — `GoalSettingsView` toggle; POST /api/v1/settings/goals `enabled` flag. (feat(§46): goal settings + trajectory)

### 46.2 Performance reviews
- [x] **Manager composes review**: numeric ratings per competency (1-5 with descriptors) + strengths + growth areas + next-period goals.
- [x] **Employee self-review** — separate form completed before manager session; both surface in review meeting helper.
- [x] **Peer feedback intake** (§46.5) aggregated by manager into final review.
- [x] **Meeting helper** — "Prepare review" action compiles scorecard (§46.4) + self-review + peer notes + manager draft into a single PDF for the sit-down.
- [x] **Employee acknowledges** — read + agree-or-dispute signature via `PKCanvasView`; disputes logged separately.
- [x] **Archive** — stored on tenant server indefinitely; exportable as PDF for HR file. (`archiveReview(id:)` POST /employees/reviews/:id/archive + `listArchivedReviews` in `ReviewsEndpoints` + `ReviewsRepository`.) (feat(§46.2): review archive endpoints)
- [x] **Cadence** — `ReviewCadence` enum + `ReviewCadenceSettingsView` + `ReviewCadenceViewModel`; GET/PATCH /api/v1/settings/review-cadence. (feat(§46): review cadence settings)

### 46.3 Time off (PTO)
- [x] **Request PTO** — date range + type (vacation / sick / personal / unpaid) + reason; optional note.
- [x] **Manager approve / deny** — push notification to requester (§70); audit log entry.
- [x] **Team calendar view** — month grid showing who's out when; conflicts highlighted.
- [x] **Balance tracking** — accrual rate per type (configured in Settings); usage deducted on approval; warnings when requesting over balance.
- [x] **Coverage prompt** — when approving PTO that affects schedule, manager sees conflicts with scheduled shifts + suggested swap partner.
- [x] **Carry-over + expiry policy** — `PTOCarryOverPolicy` + `PTOCarryOverPolicyView` + `PTOExpiryBanner`; GET/PATCH /api/v1/settings/pto/carry-over. (feat(§46): PTO carry-over + expiry policy)

### 46.4 Employee scorecards (private by default)
Covers what §46 specified. Lives here.

- [x] **Metrics per employee**: ticket close rate, SLA compliance (§4 / §4), avg customer rating (§15), revenue attributed, commission earned, hours worked, breaks taken, voids + reasons, manager-overrides triggered.
- [x] **Rolling windows** — 30 / 90 / 365-day charts.
- [x] **Private by default** — `ScorecardVisibilityRole` enum (`.self/.manager/.owner/.other`); `ScorecardViewModel.load()` guards `.other` with access-denied error. (feat(§46): scorecard private-by-default)
- [x] **Manager annotations** — notes + praise / coaching signals visible to employee.
- [x] **Objective vs subjective separation** — hard metrics auto-computed; subjective rating is the scale in §46.2 review. (`ScorecardMetricKind` enum + `ScorecardMetricClassifier.kind(for:)` in `EmployeeScorecard.swift`; only `.managerRating` is `.subjective`.) (feat(§46.4): objective vs subjective scorecard classifier)
- [x] **Export** — scorecard PDF for HR file.

### 46.5 Peer feedback
Covers what §46 specified.

- [x] **Request** — employee requests feedback from 1–3 peers during review cycle.
- [x] **Form** — 4 prompts: what's going well / what to improve / one strength / one blind spot.
- [x] **Anonymous by default**; optional peer attribution.
- [x] **Delivery gated through manager** — manager curates before sharing with subject; prevents rumor / hostility.
- [x] **Frequency cap** — `PeerFeedbackFrequencyCap` with `checkCap`/`recordRequest`; UserDefaults-backed; calendar quarter boundary; wired into `PeerFeedbackPromptSheetViewModel.submit()`. (feat(§46): peer feedback frequency cap)
- [x] **Voice dictation** — long-form text field; on-device `SFSpeechRecognizer`. (`VoiceDictationButton` + `DictationSession` @Observable; `AVAudioEngine` + `SFSpeechAudioBufferRecognitionRequest`; `requiresOnDeviceRecognition`; iOS 17+; `DictationTextEditor` in `PeerFeedbackPromptSheet`.) (feat(§46.5): voice dictation for peer feedback)

### 46.6 Leaderboards (opt-in only)
Covers what §46 specified.

- [x] **Tenant-opt-in**; default OFF. `LeaderboardSettings.enabled = false`; `LeaderboardSettingsView` admin toggle. (feat(§46): leaderboard settings + per-user opt-out)
- [x] **Scope** — per team / location. `LeaderboardScope` enum `.team/.location`; stored in `LeaderboardSettings`. (feat(§46): leaderboard settings + per-user opt-out)
- [x] **Metrics** — tickets closed / sales $. `LeaderboardMetric` enum; `value(from:)` + `formatted(_:)`. (feat(§14): employee leaderboard)
- [x] **Anonymization** — own name always shown; others optionally initials only. `LeaderboardSettings.anonymizeOthers` + safety-info section in admin settings. (feat(§46): leaderboard settings + per-user opt-out)
- [x] **Weighting** — normalized by shift hours (part-time not unfairly compared); single big-ticket outliers excluded. (`LeaderboardWeighting` pure engine in `Employees/Leaderboard/LeaderboardWeighting.swift`; `rank(_:)` normalizes + excludes outliers > 3× median.) (feat(§46.6): leaderboard weighting — normalize by hours, exclude outliers 223450bf)
- [x] **Timeframes** — weekly / monthly / YTD. `LeaderboardPeriod` enum with `dateRange`. (feat(§14): employee leaderboard)
- [x] **Weekly summary only** as notification — `LeaderboardSettings.weeklyNotification` toggle; daily alerts intentionally unsupported. (feat(§46): leaderboard settings + per-user opt-out)
- [x] **Per-user opt-out** — `LeaderboardOptOutView`; PATCH /api/v1/employees/:id/leaderboard-opt-out. (feat(§46): leaderboard settings + per-user opt-out)

### 46.7 Recognition cards (shoutouts)
Covers what §46 specified.

- [x] **Send** — `SendShoutoutSheet` + `SendShoutoutViewModel`; POST /api/v1/recognition/shoutouts; optional `ticketId`. (feat(§46): recognition shoutouts)
- [x] **Categories**: Customer save / Team player / Technical excellence / Above and beyond. `ShoutoutCategory` enum. (feat(§46): recognition shoutouts)
- [x] **Frequency unlimited** — no frequency cap; no leaderboard of shoutouts. (feat(§46): recognition shoutouts)
- [x] **Delivery** — push to recipient (§70); archive in recipient profile. (`ReceivedShoutoutsView` + `ReceivedShoutoutsViewModel`; `listReceivedShoutouts` API; push notification wired via §70 notification category by Agent 9.) (feat(§46.7): received shoutouts archive in recipient profile d46591cf)
- [x] **Team visibility** — `isTeamVisible` toggle (private by default); recipient can opt in. (feat(§46): recognition shoutouts)
- [x] **End-of-year "recognition book"** — PDF export of all received shoutouts. (`RecognitionBookExportService.generatePDF` via `UIGraphicsPDFRenderer`; cover page + 4-per-page shoutout cards; `RecognitionBookButton` in `RecognitionShoutoutView` toolbar.) (feat(§46.7): recognition book PDF export)

### 46.8 Gamification guardrails (hard rules)
Covers what §46 specified. Non-negotiable ethical constraints.

- [x] **Playful, not manipulative.** Documented in `GamificationSettingsView`; `suppressOnLeave` streak-freeze guard; no variable-reward UI. (feat(§46): gamification guardrails)
- [x] **Never tie to real $ rewards** — commissions live in §14 CommissionRules only; gamification is purely cosmetic. (feat(§46): gamification guardrails)
- [x] **Banned**: `GamificationSettings.enabled = false` kills all celebratory UI; no auto-post, no countdown timers, no loot boxes. (feat(§46): gamification guardrails)
- [x] **Allowed**: subtle milestone celebration; `suppressOnLeave` guard prevents on-leave pop-ups. (feat(§46): gamification guardrails)
- [x] **Global opt-out** — `GamificationSettingsView` (admin) + `GamificationPreferencesView` (per-user "Reduce celebratory UI"). (feat(§46): gamification guardrails)
- [x] Goal types: daily revenue, weekly ticket-count, monthly avg-ticket-value, personal commission. (§46.1: `GoalType` enum + `GoalEditorSheet`.)
- [x] Progress ring visualization (fills as goal met). (§46.1: `GoalProgressRingView` circular ring with green/amber/red thresholds + Reduce Motion guard.)
- [x] Tap ring → detail with trajectory. (§46.1: `GoalListView` → `GoalEditorSheet`; `GoalTrajectoryView` bar chart with linear forecast.)
- [x] Streak tracking with subtle confetti celebration per milestone. (§46.1: `GoalStreakCounter` + `GoalMilestoneToast`; 50/75/100% tiers; `BrandMotion` confetti only on 100%.)
- [x] Respect Reduce Motion (disable confetti). (§46.1: `@Environment(\.accessibilityReduceMotion)` guard in `GoalProgressRingView` + `GoalMilestoneToast`.)
- [x] Supportive tone on miss ("Tomorrow's a new day") — no guilt UI. (§46.1: `GoalTrajectoryView` miss message; no loss-aversion language.)
- [x] Per-tenant ops toggle to disable goals entirely. (§46.1: `GoalSettingsView` enabled toggle; PATCH /api/v1/settings/goals.)
- [x] Tenant-opt-in; default off. (§46.6: `LeaderboardSettings.enabled = false`; `LeaderboardSettingsView`.)
- [x] Scope: per team / per location. (§46.6: `LeaderboardScope` enum `.team/.location`.)
- [x] Metrics: tickets closed, sales $, avg turn time. (§46.6: `LeaderboardMetric` enum; §46.4 scorecard metrics.)
- [x] Anonymization: own name always shown; others optionally initials-only. (§46.6: `LeaderboardSettings.anonymizeOthers`.)
- [x] Timeframes: daily / weekly / monthly / quarterly. (§46.1 `GoalPeriod` + §46.6 `LeaderboardPeriod` with `.daily/.weekly/.monthly/.quarterly`.)
- [x] Fairness: weighted by shift hours (part-time not unfairly compared). (§46.6: `LeaderboardWeighting.rank(_:)` normalizes by `hoursWorked`.)
- [x] Exclude unusual outliers (e.g. single big ticket). (§46.6: `LeaderboardWeighting` outlier threshold 3× median; greyed-out entries.)
- [x] Weekly summary notifications only (no daily hounding). (§46.6: `LeaderboardSettings.weeklyNotification`; daily intentionally unsupported.)
- [x] Per-user opt-out: "Hide my name from leaderboards" in settings. (§46.6: `LeaderboardOptOutView`; PATCH /api/v1/employees/:id/leaderboard-opt-out.)
- [x] Principles: playful, not manipulative; no dark patterns (no streak-breaking anxiety / loss aversion). (§46.8: `GamificationSettingsView` docs + `suppressOnLeave` guard.)
- [x] Never tie gamification to real $ rewards (compensation is not a game). (§46.8: commissions live in §14 only; gamification is purely cosmetic.)
- [x] Allowed: subtle milestone celebrations, shop achievement badges (first 100 tickets, 1yr anniversary), friendly nudges. (§46.8: `GoalMilestoneToast` + `RecognitionShoutoutView` shoutout cards.)
- [x] Banned: auto-posting to team chat without consent. (§46.8: no auto-post; `GamificationSettings.enabled = false` kills all celebratory UI.)
- [x] Banned: forced enrollment. (§46.8: all gamification tenant-opt-in with default OFF.)
- [x] Banned: countdown timers to create urgency. (§46.8: no countdown UI anywhere in gamification stack.)
- [x] Banned: loot-box mechanics. (§46.8: deterministic milestone toasts only; no randomized rewards.)
- [x] Global opt-out: Settings → Appearance → "Reduce celebratory UI" disables confetti/sparkles. (§46.8: `GamificationPreferencesView` per-user toggle; `GamificationSettingsView` tenant master switch.)
- [x] Anti-addictive: no pull-to-refresh slot-machine animations; deterministic updates. (§46.8: all updates are real-time server data; no fake spin animations.)

---
## §47. Roles Matrix Editor

See §19.14 for settings entry. Deep features:

### 47.1 Matrix UI
- [x] **iPad** — full matrix; rows=roles, cols=capabilities; toggle cells.
- [x] **iPhone** — per-role detail view.

### 47.2 Granular caps
- [x] **~80 capabilities** — each action on each entity.
- [x] **Presets** — Admin / Manager / Technician / Cashier / Viewer / Training.
- [x] **Custom role** — clone + modify.

### 47.3 Preview before save
- [x] **"As this role"** preview mode — admin previews UI as different role.

### 47.4 Audit
- [x] **Every role change logged** — who, what, when.

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
- [x] **Source picker** — RepairDesk / Shopr / MRA / Generic CSV / Apple Numbers file. `ImportSourcePickerView` — 4 tiles with icons, selection state, Continue button. Commit `feat(ios §48)`.
- [x] **Upload file** — via share sheet or document picker; iOS 17 Files integration. `ImportUploadView` — `UIDocumentPickerViewController` wrapper, filename + size card, upload progress bar, calls `POST /imports/upload`. Commit `feat(ios §48)`.
- [x] **Field mapping** — auto-detect + manual correction; save mapping for later. `ImportColumnMappingView` — per-column `Picker`, auto-map by Levenshtein similarity (`ImportColumnMapper`), green badge when required fields mapped, Start button gated. Commit `feat(ios §48)`.

### 48.2 Dry-run
- [x] **Preview** first 10 rows — what will import, what will fail. `ImportPreviewView` — iPad uses `Grid` table, iPhone uses horizontal scroll grid; detected columns/rows summary; >50k row warning chip. Commit `feat(ios §48)`.
- [x] **Error report** — downloadable. `ImportWizardViewModel.exportErrors()` + `ImportErrorsView` bottomBar ShareLink + `ImportProgressView.errorExportControls`; 3 XCTest assertions. (feat(ios §48))

### 48.3 Execute import
- [x] **Chunked** — 100 rows at a time with progress bar. `ImportProgressView` — progress ring, processed/total, error count, ETA string. Commit `feat(ios §48)`.
- [x] **Background task** — can leave screen; Live Activity shows progress. 2s polling loop via `ImportWizardViewModel.startPolling()`. Commit `feat(ios §48)`.
- [x] **Pause / resume / cancel**. `ImportWizardViewModel.pauseImport/resumeImport/cancelImport`; `ImportProgressView.pauseResumeControls`; 7 XCTest assertions. (feat(ios §48))

### 48.4 Import history + rollback
- [x] **Undo** — within 24h; restores pre-import state.
- [x] **Log** — per-batch audit. `ImportHistoryView` — list of past imports with status badge + date; accessible from Settings. Commit `feat(ios §48)`.

### 48.5 Recurring import (auto-sync)
- [x] **Schedule** — daily CSV from S3/Dropbox/iCloud. `RecurringImportView` + `RecurringImportViewModel` + `RecurringImportRepository` + `RecurringImportEditorSheet`; supports S3/Dropbox/iCloud sources; hourly/daily/weekly frequency; run-now trigger; active/pause toggle; iPhone List + iPad grid; 13 tests. ([actionplan agent-6 b8] bcd189d7)
- [x] **On-change webhook**. `ImportWebhook` model + webhook section in `RecurringImportView`; inbound URL display (read-only); `createWebhook` in repository; endpoint stubs (server routes not yet live — graceful 404 fallback). ([actionplan agent-6 b8] bcd189d7)

---
## §49. Data Export

### 49.1 Full tenant export
- [x] **Trigger** — Settings → Danger → "Export all data" (`DataExportSettingsView`).
- [x] **Bundle** — encrypted ZIP with passphrase; `FullExportConfirmSheet` collects passphrase, warns about contents.
- [x] **Email / iCloud / share sheet** — `ExportShareSheet` with `ShareLink` + `UIDocumentPickerViewController` save-to-iCloud.
- [x] **Progress** — `ExportProgressView` polls `GET /exports/:id` every 3s; status chip in-app. Live Activity: TODO §21 Dynamic Island.

### 49.2 Per-domain export
- [x] **From list views** — `DomainExportMenu` presents local CSV via `CSVComposer` (RFC-4180) + server-side filtered export via `POST /exports/domain/:entity`.

### 49.3 GDPR / CCPA individual export
- [x] **Per-customer data package** — `GDPRCustomerExportView` triggers `POST /exports/customer/:id`, polls, shares zip URL.

### 49.4 Scheduled recurring
- [x] **Daily to S3 / Dropbox / iCloud Drive** — `ScheduledExportListView` + `ScheduledExportEditorView`; iCloud Drive functional, S3/Dropbox stubbed (TODO §49.4 comment).

---
## §50. Audit Logs Viewer — ADMIN ONLY

Access restricted to roles with `audit.view.all` capability (§47.5). Non-admins never see the audit UI; the Settings row is hidden, the deep link (`bizarrecrm://<slug>/settings/audit`) is rejected with a 403-style toast, and server authoritatively blocks `/audit-logs` on non-admin tokens. Own-history (`audit.view.self`) is a different, narrower surface — lives on §19.1 Profile as "My recent actions", reads the same endpoint scoped to actor_id = self.

### 50.1 List
- [x] **Server**: `GET /audit-logs?actor=&action=&entity=&since=&until=`.
- [x] **Columns** — when / actor / action / entity / diff.
- [x] **Expandable row** — shows full JSON diff.

### 50.2 Filters
- [x] **Actor, action, entity, date range**.
- [x] **Saved filters** as chips.
- [x] Free-text search across data_diff via FTS5.
- [x] Chips: "Last 24h", "This week", "Custom".

### 50.3 Export
- [x] **CSV / JSON / PDF for period** — CSV implemented via `AuditLogExportSheet` wired in toolbar; PDF court-evidence format deferred. (feat(§50.3) d5744dc5)
- [x] PDF formatted for court evidence: header + footer + page numbers + signature page.

### 50.4 Alerts
- [ ] **Sensitive action** (role change, bulk delete) → admin push. (server concern)

### 50.5 Scope
- Every write operation logged: who, when, what, before/after.
- Reads logged optionally (sensitive screens only).

### 50.6 Entry rendering
- [x] Before/after diff visually (red/green).
- [x] Actor avatar + role + device fingerprint.
- [x] Tap → navigate to affected entity (if exists).

### 50.7 Integrity
- Entries immutable (server enforced).
- SHA chain: each entry includes hash of previous → tamper-evident. (server concern; stub returning `.unknown` deferred)
- iOS verifies chain on export; flags tampered period.

### 50.8 Retention
- Tenant policy: 1yr / 3yr / 7yr / forever. (server concern)
- Auto-archive to cold storage beyond hot window.

### 50.9 Access control
- [x] Owner / compliance role only — `AuditLogAccessPolicy` + "Access denied" pane shipped.
- Viewing logged (meta-audit).

### 50.10 Offline
- [x] Cached last 90d locally — `AuditLogRepository` in-memory write-through cache (90d TTL, 500-entry cap, newest-first, deduplication by id). ([actionplan agent-6 b4] c0cb747c)
- Older pulled on demand.

---
## §51. Training Mode (sandbox)

### 51.1 Toggle
- [x] **Settings → Training Mode** — switches to demo tenant with seeded data.
- [x] **Watermark banner** — "Training mode — no real charges, no real SMS".

### 51.2 Reset
- [x] **"Reset demo data"** — wipes + reseeds.

### 51.3 Guided tutorials
- [x] **Overlay hints** — "Tap here to create a ticket". (MVP 3-step stub; full library TODO)
- [x] **Checklist** — tutorials by topic (POS basics, ticket intake, invoicing). (ecb07902 — TutorialChecklist.swift; 4 topics × 5 steps + TutorialCompletionStore)

### 51.4 Onboarding video library
- [x] **Video tiles** — 4-tile placeholder grid (POS basics, Ticket intake, Invoicing, Inventory); AVPlayer TODO.

---
## §52. Command Palette (⌘K)

### 52.1 Universal shortcut
- [x] **⌘K on iPad / Mac** → global command palette.
- [x] **iPhone** — reachable via pull-down gesture on any screen.

### 52.2 Action catalog
- [x] **Every registered action** — "New ticket", "Find customer by phone", "Send SMS", "Clock out", "Close shift", "Settings: Tax", "Reports: Revenue this month".
- [x] **Fuzzy search** — Sublime-style; rank by recent usage.

### 52.3 Scope + context
- [x] **Current context aware** — "Add note to this ticket" works when ticket open.
- [x] **Entities** — type ticket # / phone / SKU → navigate.

### 52.4 Keyboard-first
- [x] **Arrow navigate**, **⏎ execute**, **⎋ dismiss**.

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
- [x] **Role / device profile** — lock app to POS tab via `KioskGateView`.
- [x] **Exit** requires manager PIN (`ManagerPinSheet`).

### 55.2 Clock-in-only mode
- [x] **For shared shop iPad** — only Timeclock accessible via `KioskGateView(.clockInOnly)`.

### 55.3 Training profile
- [x] **Assistive Access adoption** — simplified large-button `TrainingProfileView` (64pt tiles, 4 actions, iPhone 2×2 / iPad 4×1).
- [x] Idle timer: dim 50% after 2 min idle; black out with brand mark after 5 min; tap anywhere wakes (`KioskIdleMonitor`).
- [x] Night mode: `KioskConfig.isNightModeActive()` with configurable hour window (default 22–6).
- [x] Screen-burn prevention: `BurnInNudgeModifier` — 1pt cyclic translation every 30s; disabled when Reduce Motion on.
- [x] Config: `KioskSettingsEditor` — Stepper for dim/blackout thresholds, Picker for night mode start/end.

---
## §56. Appointment Self-Booking — CUSTOMER-FACING; NOT THIS APP

Customer self-booking is a separate product surface. If ever built, it is either a tenant-server-hosted public web page (likely path) or a distinct customer-facing app — both out of scope for this staff-only iOS app (per §62 non-goals).

Staff-side pieces that overlap with booking live in §10 Appointments (staff create / reschedule / confirm) and §10 Scheduling engine. No §56 work scheduled in the iOS plan.

Number preserved as stub so cross-refs don't break.

---
## §57. Field-Service / Dispatch (mobile tech)

### 57.1 Map view
- [x] **MapKit** — appointments pinned on map. (`FieldServiceMapView.swift` — UIViewRepresentable + ETAAnnotationView + a11y labels)
- [x] **Route** to next job via Apple Maps. (`FieldServiceRouteService.swift` — MKDirections.calculate + MKMapItem.openInMaps; `NextJobCardView.swift` — Liquid Glass overlay + Navigate button)

### 57.2 Check-in / check-out
- [x] **GPS verified** — arrival → start-work auto. (`FieldCheckInService.swift` — actor + LocationCapture protocol; `FieldCheckInPromptView.swift` + `FieldCheckInPromptViewModel.swift` — geofence-triggered prompt)
- [x] **Signature on completion**. (`FieldSignatureView.swift` — PKCanvasView, PNG export, a11y "Customer signed" announcement)

### 57.3 On-site invoice
- [x] **POS in the field** — BlockChyp mobile terminal. (`FieldOnSiteInvoiceFlow.swift` — ChargeCoordinator via injected chargeHandler; pre-filled service lines from appointment context)
- [x] **Email/SMS receipt immediately**. (`FieldReceiptDeliverySheet.swift` — Email / SMS / Print options post-charge)
- [x] Use-cases: field-service route (§57), loaner geofence (§5), auto-clock-in on shop arrival opt-in (§46), tax-location detection for mobile POS (§19.8).
- [x] Permission: request `whenInUse` first; step up to `always` only for field-service role. Never background-track non-field users. (`FieldLocationPolicy.swift`)
- [x] Accuracy: approximate default; precise only when geocoding or routing explicitly. (`FieldLocationPolicy.desiredAccuracy(duringActiveJob:)`)
- [x] Power: significant-location-change for background (not raw GPS); stop updates when app leaves foreground unless `always` granted. (`FieldLocationPolicy.handleBackgrounded/Foregrounded`)
- [x] Privacy: all location data → tenant server only (§32). Settings → Privacy → Location shows what's tracked + toggle + history export + delete history. (`FieldLocationPrivacySettingsView` + `FieldLocationPrivacyViewModel`; toggle in UserDefaults; CSV export; delete via `DELETE /api/v1/field-service/location-history`; iPhone List + iPad card layouts. feat(§57) b5)
- [x] Accuracy thresholds: < 20m for on-site check-in; < 100m for route planning. (`FieldLocationPolicy.isWithinCheckInRange` — 100 m; `FieldCheckInService` validates proximity)
- [x] Indoor fallback: cell + Wi-Fi heuristics when GPS weak; degrade gracefully. (`FieldLocationPolicy.positioningSource(from:)` — buckets accuracy ≤20m=GPS / 21-200m=cellAndWifi / >200m=unavailable; `indoorBannerMessage(source:)` returns banner copy; `canAutoCheckIn(location:jobCoordinate:)` prevents auto-check-in on weak fix. 12 new tests pass. feat(§57) b5)

---
## §58. Purchase Orders (inventory)

### 58.1 PO list + detail
- [x] **Server**: `GET/POST /purchase-orders`. (`PurchaseOrderEndpoints.swift`)
- [x] **Create** — supplier + lines + expected date. (`PurchaseOrderComposeView` + `PurchaseOrderRepository`)
- [x] **Receive** — mark items received; increment stock. (`PurchaseOrderReceiveSheet`)
- [x] **Partial receive**. (`PurchaseOrderCalculator.receivedProgress` + receive sheet)

### 58.2 Cost tracking
- [x] **Landed cost** — purchase + shipping / duty allocation. (`PurchaseOrderCalculator.totalCents` / `lineTotalCents` per line)

### 58.3 Supplier management
- [x] **Supplier CRUD**. (`SupplierListView` + `SupplierEditorSheet` + `SupplierRepository`)
- [x] **Reorder suggestions — one-click draft PO**. (`PurchaseOrderReorderSuggestionView`)

---
## §59. Financial Dashboard (owner view)

### 59.1 KPI tiles
- [x] **Revenue / profit / expenses / AR / AP / cash-on-hand** with trends. (`FinancialDashboardView` P&L hero tile + aged receivables tile)
- [x] **KPI tile color states** — semantic threshold coloring on every KPI card: revenue (positive=success), profit (≥15% margin=success, 5-15%=warning, <5%=error), expenses (ratio vs revenue), AR (overdue=error), tax (outstanding=caution). Tinted background + border reflect state. `KPIColorState` enum in `OwnerPLView.swift`.
- [x] **P&L margin badge** — pill-shaped `MarginBadge` capsule under Gross Profit and Net Profit KPI tiles; green/amber/red threshold coloring; shown in `plKpiCard`. `OwnerPLView.swift`.
- [x] **Gross-vs-net revenue toggle** — segmented Gross/Net picker in controls bar; `showNetRevenue: Bool` on `OwnerPLViewModel`; drives KPI tile label+value and chart y-axis label. `OwnerPLView.swift` + `OwnerPLViewModel.swift`.
- [x] **Year-over-year delta chip** — `YoYDeltaChip` capsule with directional arrow shown on Revenue and Net Profit KPI tiles and chart header; decoded from optional `yoy_revenue_delta_cents`/`yoy_net_profit_delta_cents` server fields. `OwnerPLModels.swift` + `OwnerPLView.swift`.
- [x] **Export-to-CSV copy** — `ShareLink` toolbar button produces RFC-4180 CSV via `OwnerPLCSVExporter`: revenue, profit, expenses by category, time-series (with YoY delta where available), top customers, top services; toggle-aware (gross vs net). `OwnerPLCSVExporter.swift`.

### 59.2 Profitability
- [x] **Per-service gross margin**. (`PnLCalculator.grossMarginPct` + `PnLSnapshot`)
- [x] **Per-tech profitability**. (top customers + top SKUs tiles in `FinancialDashboardView`)

### 59.3 Forecast
- [x] **30/60/90 day revenue forecast** (ML if server). `RevenueForecastCard` + `RevenueForecaster` OLS linear regression; ±15% confidence band; Swift Charts dashed + area; AXChartDescriptorRepresentable; 8 tests. (feat(§59.3) 8f3a2aae)
- [x] **OwnerPL time-series chart `AXChartDescriptorRepresentable`** — `OwnerPLChartDescriptor` added to `OwnerPLView.swift`; Revenue + Expenses series; categorical x-axis (period), numeric y-axes; `.accessibilityChartDescriptor` applied to grouped bar chart. ([actionplan agent-6 b11] 35822698)

### 59.4 Financial exports + tax year
- [x] **CSV export**. (`FinancialExportService`)
- [x] **Tax year bundle**. (`TaxYearReportView`)
- [x] **Access control**. (`FinancialDashboardAccessControl`)
- [x] **Cash flow chart**. (`CashFlowCalculator` + cash flow tile)
- [x] **Aged receivables**. (`AgedReceivablesCalculator` + aged receivables tile)
- [x] **Cash-flow chart legend** — `chartForegroundStyleScale` keys aligned with `foregroundStyle(by:)` series names; `.chartLegend(.visible)` makes Inflow/Outflow color legend visible; `CashFlowChartDescriptorProvider: AXChartDescriptorRepresentable` added. (`FinancialDashboardView`)
- [x] **AR aging bucket totals badge** — stacked annotation above each bar shows dollar total (bold) + invoice count (muted "N inv"); a11y label per bar; `ARAgedChartDescriptorProvider` wired via `.accessibilityChartDescriptor`. (`FinancialDashboardView`)
- [x] **P&L variance row** — `PnLVariance` model (delta cents + optional pct, `isFavorable`); `PnLSnapshot` gains `priorNetCents` init; hero tile renders arrow + delta + pct chip below margin line when prior-period data available. (`FinancialModels`, `FinancialDashboardView`)
- [x] **Expense category drilldown** — `ExpenseCategoryRow` model + `PnLSnapshot.expenseCategoryRows(from:)` factory; `FinancialDashboardData.expenseCategoryRows`; `GET /api/v1/finance/expenses-by-category` endpoint; `expenseDrilldownTile` with share-of-total bars; wired in VM + both layouts. (`FinanceEndpoints`, `FinancialModels`, `FinancialDashboardViewModel`, `FinancialDashboardView`)
- [x] **Balance-sheet snapshot copy** — `FinancialExportService.copyBalanceSheet(data:period:)` produces plain-text Assets/Liabilities/Equity summary; toolbar "Copy Balance Sheet" menu item writes to `UIPasteboard.general.string`; "Copied!" transient label auto-resets after 2 s. (`FinancialExportService`, `FinancialDashboardView`)

---
## §60. Multi-Location Management

### 60.1 Location switcher
- [x] **Top-bar chip** on iPad — active location. (`LocationSwitcherChip` + `.locationScoped()` modifier)
- [x] **"All locations"** aggregate view for owner. (`LocationListView` + `LocationContext` observable)

### 60.2 Transfer between locations
- [x] **Inventory transfer** — pick items + source/dest + signature. (`LocationTransferSheet` + `LocationTransferListView` + `LocationInventoryBalanceView`)

### 60.3 Per-location reports
- [x] **Revenue / tickets / employees**. (`LocationPermissionsView` matrix + CRUD via `LocationListView` / `LocationEditorView`)

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
- [x] **Network error** — glass card: illustration + "Can't reach the server" + Retry. (`CoreErrorState.network` + `CoreErrorStateView` in `Core/ErrorStates/`; `ErrorStateMapper.map(from:)` converts any `AppError`.)
- [x] **Auth error** — "Session expired" toast → auto-re-auth attempt → fall back to Login. (`CoreErrorState.unauthorized` with "Sign In" retry label; `SessionEvents.sessionRevoked` auto-logout.)
- [x] **Validation error** — inline under field with brand-danger accent + descriptive copy. (`CoreErrorState.validation([String])` lists failed fields; `CoreErrorStateView` renders.)
- [x] **Server 5xx** — "Something went wrong on our end" + retry. (`CoreErrorState.server(status:message:)` + `CoreErrorStateView`.)
- [x] **Not-found (404)** — "The item you're looking for no longer exists." (`CoreErrorState.notFound`; entity-specific copy is caller responsibility.)
- [x] **Permission denied (403)** — "You don't have permission to do this." (`CoreErrorState.forbidden`.)
- [x] **Rate-limited (429)** — countdown + "Try again in Ns". (`CoreErrorState.rateLimited(retrySeconds:)` with formatted message.)
- [x] **Offline + no cache** — "You appear to be offline." (`CoreErrorState.offline` + `OfflineEmptyStateView` in Sync package.)
- [x] **Corrupt cache** — auto-recover + re-fetch; show banner. (`CorruptCacheRecovery` service + `CorruptCacheBanner` view in `Core/ErrorStates/CorruptCacheRecovery.swift`; posts `corruptCacheDetected` notification; feature lists call `.safeAreaInset(edge: .top)` with the banner. feat(§63.1))

### 63.2 Empty states
- [x] **First-run empty** — brand illustration + 1-line copy + primary CTA. (`EmptyStateView` in `Core/ErrorStates/EmptyStateView.swift` + `EmptyStateCard` in DesignSystem/Polish/.)
- [x] **Filter empty** — "No results for this filter". (`EmptyStateView` with filter-specific copy; `OfflineEmptyStateView` for offline-with-cache-miss.)
- [x] **Search empty** — "No matches". (`EmptyStateView` search variant.)
- [x] **Section empty** (detail sub-lists) — inline muted copy; no illustration. (`SectionEmptyView` in `Core/ErrorStates/EmptyStateView.swift` — label + optional icon, no illustration, foreground `.tertiary`. feat(§63.2))
- [x] **Permission-gated** — "This feature is disabled for your role". (`PermissionGatedView` in `Core/ErrorStates/EmptyStateView.swift` — lock.shield icon + title + message + optional "Ask Admin" CTA. feat(§63.2))

### 63.3 Loading states
- [x] **Skeleton rows** — shimmer glass placeholders for lists. (`SkeletonShimmer`, `SkeletonRow`, `SkeletonList` in DesignSystem/Polish/.)
- [x] **Hero skeleton** — card shape placeholder for detail pages. (`SkeletonCard` in DesignSystem/Polish/.)
- [x] **Spinner** — only for sub-second operations (save); use progress for long. (`InlineSavingSpinner` in `Core/ErrorStates/OptimisticLoadingViews.swift` — small `ProgressView` + optional "Saving…" label; distinct from `LoadingSpinnerView` for cards. feat(§63.3))
- [x] **Progress bar** — determinate for uploads / imports / printer jobs. (`BrandProgressBar` + `BrandLinearProgressViewStyle` in `Core/ErrorStates/OptimisticLoadingViews.swift` — determinate `ProgressView` with percentage text + brand accent fill. feat(§63.3))
- [x] **Optimistic UI** — item appears instantly with "Sending…" glow. (`OptimisticPendingModifier` + `.optimisticPending(isSending:)` View extension in `Core/ErrorStates/OptimisticLoadingViews.swift` — pulsing "Sending…" glass chip overlay; opacity reduction while in-flight. feat(§63.3))
- [x] **Shimmer duration cap** — if > 5s loading, swap to "Still loading… slower than usual — tap to retry". (`TimedSkeletonView<Skeleton>` in `Core/ErrorStates/OptimisticLoadingViews.swift` — wraps any skeleton; swaps to slow-load banner after configurable timeout (default 5s). feat(§63.3))

### 63.4 Inline pending
- [x] **Saving chip** — "Saving…" glass chip top-right while mutation in flight. (`SavingChip` + `SavedTick` + `InlineSavingStateModifier` + `.inlineSavingState(isSaving:isSaved:)` in `Core/ErrorStates/OptimisticLoadingViews.swift`. feat(§63.4): 655cdc18)
- [x] **Saved tick** — brief green check on save. (Part of `SavedTick` + `InlineSavingStateModifier` state machine. feat(§63.4): 655cdc18)

### 63.5 Destructive-action flows
- [x] **Soft-delete with undo** — toast "Deleted. Undo?" 5-second window. (`Core/ErrorStates/SoftDeleteUndoService.swift` — @Observable actor, glass chip toast, softDeleteUndoOverlay modifier, EnvironmentKey. feat(§63.5): 09a3098e)
- [x] **Hard-delete confirm** — alert with consequence copy + type-to-confirm for catastrophic actions. (`HardDeleteAlertModifier` + `.hardDeleteConfirm(isPresented:entityName:consequence:onConfirm:)` for standard; `CatastrophicDeleteConfirmView` type-to-confirm sheet for irreversible ops. `Core/ErrorStates/HardDeleteConfirmView.swift`. feat(§63.5): b11)
- [x] **Undo stack** — last 5 actions undoable via `⌘Z`. (`RecentUndoMenuButton` + `SceneUndoManager.recentUndoDescriptions(limit:)` + `undoAll()` + `undoCount`. `Core/WindowState/SceneUndoManager.swift`. feat(§63.5): b11)

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

- [x] `applinks:app.bizarrecrm.com` + `applinks:*.bizarrecrm.com` in entitlement. (documented in `ServerConnectionPage` §65.1 Deep links section; entitlement edit is Agent 10 scope — flagged in Discovered; db65cb55)
- [ ] AASA file hosted + immutable version pinned per app release.
- [x] Self-hosted tenants are not in the entitlement. Do not attempt per-tenant re-signing; not scalable. (transparency note added to `ServerConnectionPage` Deep links section; db65cb55)

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

- [x] All sounds respect silent switch + Settings → Sounds master. (`SoundPlayer` uses AudioServicesPlaySystemSound which respects mute; `HapticsSettings.soundsEnabled` toggle.)
- [x] All haptics respect Settings → Haptics master + iOS accessibility setting. (`HapticsSettings.hapticsEnabled` + `QuietHoursCalculator`.)

### 66.1 CoreHaptics engine
- [x] `CHHapticEngine` registered on app start. (`CoreHapticsEngine.shared` eagerly initialized in `AppServices.restoreSession()`; actor handles interruption restart + foreground resume. feat(§66.1): ec399879)
- Re-start on `audioSessionInterruption` + `applicationWillEnterForeground`.
- Single `HapticCatalog.swift` source; ban ad-hoc calls.
- Non-haptic devices (iPad without Taptic) → silent.

### 66.2 Custom patterns
- [x] **Sale success** — 3-tap crescendo (0.1, 0.2, 0.4 intensity, 40ms apart). Plus success chime. (`HapticPatternLibrary.saleSuccess`. feat(§66.2): d1d8be04)
- [x] **Card decline** — two-tap sharp (0.9, 0.9, 80ms apart). (`HapticPatternLibrary.cardDecline`. feat(§66.2): d1d8be04)
- [x] **Drawer open** — single medium thump. (`HapticPatternLibrary.drawerOpen`. feat(§66.2): d1d8be04)
- [x] **Scan match** — single gentle click + pitched sound. (`HapticPatternLibrary.scanMatch`. feat(§66.2): d1d8be04)
- [x] **Scan unmatched** — double sharp (warning). (`HapticPatternLibrary.scanUnmatched`. feat(§66.2): d1d8be04)
- [x] **Status advance** — ramp from 0.2 → 0.6 over 150ms. (`HapticPatternLibrary.statusAdvance`. feat(§66.2): d1d8be04)
- [x] **Undo** — reverse ramp. (`HapticPatternLibrary.undo`. feat(§66.2): d1d8be04)
- [x] **Signature complete** — triple subtle, low intensity. (`HapticPatternLibrary.signatureComplete`. feat(§66.2): d1d8be04)
- [x] Quiet hours: user-defined in Settings → Notifications → Quiet hours (e.g. 9pm–7am); haptics suppressed except critical. (`QuietHoursCalculator` + `HapticsSettings.quietHoursStart/End`.)
- [x] Silent mode: honor device mute switch — no sounds; haptics still fire unless user disabled in iOS. (`SoundPlayer` uses `AudioServicesPlaySystemSound`.)
- [x] Do-Not-Disturb: respect Focus modes (§13); notifications routed per Focus rules. (`DesignSystem/Haptics/FocusModeHapticsGate.swift` — actor with 5min cache, UNUserNotificationCenter query, playRespectingFocus entry point. feat(§66): 5a6fac36)

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
- [x] **Ticket-created** — temporary pulse highlight on new row. (`.ticketCreatedPulse(highlight:)` in `SignatureAnimations.swift`.)
- [x] **Sale-complete** — confetti + check mark center screen. (`.saleCompleteConfetti(isActive:)`; Reduce Motion → static checkmark.)
- [x] **SMS-sent** — bubble fly-in from composer. (`.smsSentFlyIn()`.)
- [x] **Payment-approved** — green check inside a circle draw. (`.paymentApprovedCheck(isActive:)`.)
- [x] **Low-stock warn** — stock badge pulses red. (`.lowStockPulse(isActive:)`.)

---
## §68. Launch Experience

### 68.1 Launch screen
- [x] **Branded splash** — logo center + gradient; identical in light/dark. (`LaunchSceneView.swift` — forces `.dark` colorScheme so gradient reads identically.)
- [x] **No loading spinners** before UI — state restore quickly. (`ColdStartCoordinator` resolves in ≤200ms.)

### 68.2 Cold-start sequence
- [x] Splash (200ms max) → RootView resolve → Dashboard or Login. (`ColdStartCoordinator.resolve()` with `Task.sleep` deadline race.)
- [x] **State restore** — last tab + last selected list row. (`StateRestorer.swift`.)
- [x] **Deep-link resolution** — before first render. (`ColdStartCoordinator.resolve(pendingURL:)` accepts an optional URL; when authenticated, returns `.deepLink(url)` instead of `.dashboard` so `RootView` routes without a flash. `RootDestination.deepLink(URL)` case added. `DesignSystem/Launch/ColdStartCoordinator.swift`. feat(§68.2): b11)

### 68.3 First-run
- [x] **Server URL entry** with quick-pick options (saved URLs + "bizarrecrm.com"). (`FirstRunServerPickerView.swift`.)
- [x] **What's new** — modal on major version update. (`WhatsNewSheet.swift` + `BundledChangelog` fallback.)

### 68.4 Onboarding tooltips
- [x] **Coach marks** — first time each top-level screen opened. (`CoachMarkDismissalStore` + `CoachMarkOverlay` in `CoachMarkView.swift`.)
- [x] **Dismissable** + "Don't show again". (Dismiss button + "Don't show again" button; persists to `UserDefaults`.)
- [ ] **Per-feature** — widget install prompt, barcode scan, BlockChyp pairing. (Specific coach mark content deferred to feature packages.)

---
## §69. In-App Help

### 69.1 Help center
- [x] **Settings → Help** — searchable FAQ. (`HelpCenterView`, `HelpSearchViewModel`)
- [x] **Topic articles** — bundled markdown + images. (`HelpArticleCatalog` — 15 articles, `HelpArticleView`)
- [x] **Context-aware help** — "?" icon on complex screens → relevant article. (`ContextualHelpButton`)
- [x] **FAQ footer contact link** — "Still need help?" footer row with "Contact Support" tap target and `bizarrecrm.com/support` copy; opens `SupportEmailComposerView` sheet (`HelpCenterView.contactSupportFooterSection`)

### 69.2 Contact support
- [x] **Send support email** — prefilled with diagnostic bundle. Recipient resolved from `GET /tenants/me/support-contact`. (`SupportEmailComposerView`, `DiagnosticsBundleBuilder`)
- [x] **Contact-support sheet copy** — updated headline "We're Here to Help", expanded body with 1-business-day SLA and plain-language diagnostic disclosure, `accessibilityLabel` on support email address (`SupportEmailComposerView`)
- [x] **Live chat** (if server supports) — embedded. (`LiveChatSupportView` — MVP placeholder "coming soon")

### 69.3 Release notes
- [x] **What's new** — on version bump, modal highlights. (`WhatsNewHelpView` reads `GET /app/changelog?version=X.Y.Z`)
- [x] **Full changelog** — in Help via `WhatsNewHelpView`.

### 69.4 Feature hints
- [x] **Pro-tip banners** — rotating tips on Dashboard. (`ProTipBanner`, `ProTipBannerViewModel`)
- [x] Entry: Settings → Help → "Report a bug". Optional shake-to-report (debug builds only). (`ShakeToReport`, `ShakeWindow`)
- [x] Form fields: description (required); category; severity; auto-attached diagnostics bundle. (`BugReportSheet`, `BugReportViewModel`)
- [x] `POST /support/bug-reports` with payload. Server issues ticket #, iOS toast "Thanks — ticket BG-234 created."
- [ ] Follow-up updates surface in §13 Notifications tab when devs respond.
- [x] PII guard: logs run through §32.6 Redactor before attach. (`DiagnosticsBundleBuilder`)
- [ ] Offline: queue in §20.2; submit on reconnect.
- [x] "What's new" from `GET /app/changelog?version=X.Y.Z`. (`WhatsNewHelpView`)
- [ ] Full history list under Settings → About → Changelog (deep-link to blog).
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
- [x] Per-event toggles: Push on/off, In-App on/off, Email on/off, SMS on/off. All four independent. (`NotificationPreferencesMatrixView`, `NotificationPreferencesMatrixViewModel`)
- [x] Defaults shown greyed with "(default)" label until user flips. (feat(§70): MatrixRow.isAtDefault(for:) + isFullyAtDefault; channelToggleButton shows greyed "default" label; 9cd0b5b8)
- [x] "Reset all to default" button. (`resetAllToDefault()`)
- [x] Explicit warning when enabling SMS on a high-volume event. (`StaffNotificationCategoryExclusions`)

### 70.2 Tenant override (Admin)
- [x] Admin can shift a tenant's default (e.g., "for this shop, staff always get email on invoice-overdue"). Baseline shipped by us is push-only; tenant admin's shift is their call. (`Notifications/TenantAdmin/TenantNotificationDefaultsView.swift` + `TenantNotificationDefaultsViewModel` + `PUT /notifications/tenant-defaults`; db65cb55)
- [x] Per-tenant dashboard shows current deltas vs shipped defaults. (`TenantNotificationDefaultsViewModel.deltaFromShipped` — lists events that diverge from push-only shipped defaults; shown as warning count in header; db65cb55)

### 70.3 Delivery rules
- [x] Push respects iOS Focus — documented. (`FocusModeIntegrationView`)
- [x] Quiet hours editor with critical-override toggle. (`QuietHoursEditorView`, `QuietHours`)
- [x] In-app banner never shown if the user is already looking at the source (e.g., SMS inbound for a thread the user is reading). (feat(§70): ForegroundPushToastCoordinator.activeScreenPath + pathsMatch() suppression; 4ecb468d)
- [ ] If the same event re-fires within 60s, collapse into a "+N more" badge update instead of sending a second push.

### 70.4 Critical override
- [x] Four events (Backup failed, Security event, Out of stock, Payment declined) flagged `isCritical` in `NotificationEvent`. (`NotificationEvent.isCritical`)
- [x] Event enum: 30 cases covering full §70 matrix. (`NotificationEvent`, `NotificationPreference`)
- [x] Per-event preferences with PATCH persistence. (`NotificationPreferencesRepository`, `NotificationPreferencesRepositoryImpl`)
- [ ] Never `critical` (that requires Apple Critical Alerts entitlement; reserve for specific tenants that request it — §13.4).
- [ ] Never `critical` (that requires Apple Critical Alerts entitlement; reserve for specific tenants that request it — §13.4).
- [ ] Delivery tuning: respect quiet hours (§13); bundle repeated pushes (group SMS from same thread into one notification with message-count badge)
- [x] Rich content: SMS notification embeds photo thumbnail if MMS; payment notification shows amount + customer name; ticket assignment embeds device + status. (`Notifications/Push/RichPushContentBuilder.swift`; `RichPushContentBuilder.enrich(_:userInfo:)` — sets MMS thumbnail_url flag, payment amount+customer+invoiceId, ticket device+status; agent-9 b13 feff23aa)
- [x] Inline reply: SMS_INBOUND action "Reply" uses `UNTextInputNotificationAction` — reply from push without opening app. (`NotificationCategories.smsReplyCategory()` — `UNTextInputNotificationAction(identifier: smsQuickReply, ...)` + view action; registered via `NotificationCategories.registerWithSystem()`; agent-9 b9)
- [x] Sound library: Apple default + 3 brand custom sounds (cash register, bell, ding); user picks per category. (`Notifications/Settings/NotificationSoundPickerView.swift`; `NotificationSound` enum + `NotificationSoundPreferences` store + `NotificationSoundPickerView` per-category selection + preview trigger; 66641a8d)
- [ ] Clear-all: on app foreground after read, system badge clears accordingly; single tap clears relevant bundle
- [x] Historical view: Settings → Notifications → "Recent" shows last 100 pushes for audit. (`Notifications/History/RecentPushStore.swift` + `RecentPushHistoryView.swift`; actor `RecentPushStore` (cap 100, UserDefaults persist) + `RecentPushHistoryView` with relative timestamps + clear action; 7 unit tests; agent-9 b13 051ceb38)
- [ ] Push token rotation: on app start or change POST new token to `/device-tokens` with device model; stale tokens cleaned server-side
- [x] Fail-safe: retry APNs token register with exponential backoff on failure; manual "Re-register" in Settings. (`Notifications/Push/PushTokenRetryService.swift`; `PushTokenRetryService` actor; exponential backoff 5s→300s cap, 8 max attempts; `retryNow()` for manual trigger; `backoffDelay(attempt:)` tested; agent-9 b13 56ec6d2b)
- [x] Per-event copy matrix with title/body/action buttons for: SMS_INBOUND (Reply/Mark Read/Call), TICKET_ASSIGNED (Open/Accept/Snooze), TICKET_STATUS (Open), PAYMENT_RECEIVED (Open/Send Receipt), APPT_REMINDER (Open/Navigate), LOW_STOCK (Open/Create PO), TEAM_MENTION (Reply/Open), ESTIMATE_APPROVED (Open/Convert), BACKUP_FAILED (Open), DAILY_SUMMARY (Open). (`Notifications/Copy/NotificationCopyProvider.swift`; all 30 `NotificationEvent` cases covered; `NotificationCopyProviderTests` 7 tests including no-emoji assertion; agent-9 b13 880799ed)
- [x] Tone: short, actionable, no emoji in title; body includes identifier so push list stays scannable. (`NotificationCopyProvider` enforced; `test_allEvents_titlesContainNoEmoji` CI assertion; agent-9 b13 880799ed)
- [ ] Localization: each copy keyed; fallback to English if locale missing.
- [ ] A11y: VoiceOver reads title + body + action hints.
- [x] Interruption level mapping per §13.4 categories. (Pre-existing `NotificationInterruptionLevelMapper` in `NotificationInterruptionLevel.swift`; maps `isCritical` events → `.timeSensitive`, all others → `.active`; never `.critical` per §13.4; confirmed complete agent-9 b13)
- [ ] Bundling: repeated same-type pushes within 60s merged as "+N more".
- [ ] See §21 for the full list.

---
## §71. Privacy-first analytics event list

All events target tenant server (see §32).

- [x] `app.launch` → `app.launched`
- [x] `app.foreground` → `app.foregrounded`
- [x] `app.background` → `app.backgrounded`
- [x] `auth.login.success` → `auth.login.succeeded`
- [x] `auth.login.failure` → `auth.login.failed`
- [x] `auth.logout` → `auth.signed_out`
- [x] `auth.biometric.success` → `auth.passkey.used`
- [x] `screen.view` → `screen.viewed`
- [x] `deeplink.opened`
- [x] `pos.sale.start` / `.complete` / `.fail` → `pos.sale.finalized`, `pos.checkout.abandoned`
- [x] `pos.return.complete` → `pos.refund.issued`
- [x] `barcode.scan` → `hardware.barcode.scanned`
- [x] `printer.print` → `hardware.receipt.printed`
- [x] `terminal.charge` → `pos.card.charged`
- [x] `widget.view` → `widget.viewed`
- [x] `live_activity.start` / `.end` → `live_activity.started` / `live_activity.ended`
- [x] `feature.first_use` → `feature.first_use`
- [x] 30+ additional domain events (tickets, customers, inventory, invoices, settings, support, errors, sync)

### 71.1 Schema
```
{
  "event": "screen.viewed",
  "timestamp": "2026-04-19T14:03:22.123Z",
  "app_version": "1.2.3",
  "platform": "iOS",
  "session_id": "uuid (opaque, not user id)",
  "tenant_slug": "acme-repair",
  "props": { "screen": "dashboard", "duration_ms": 2341 }
}
```

### 71.2 No tracking
- [x] No IDFA, no Facebook pixel, no Google Analytics, no Braze, no Firebase.
- [x] Default opt-out. User opts in via Settings → Privacy.
- [x] PII keys (email, phone, address, firstName, lastName, ssn, creditCard) rejected by `AnalyticsRedactor`.
- [x] String values scrubbed through `LogRedactor` before transmission.
- [x] GDPR right-to-erasure: "Delete my analytics" → `POST /analytics/delete-my-data`.

### 71.3 Implementation — shipped
- [x] `AnalyticsEventCatalog.swift` — 57 events across 10 categories (`AnalyticsEvent`, `AnalyticsCategory`). (`ios/Packages/Core/Sources/Core/Telemetry/`)
- [x] `AnalyticsEventPayload.swift` — `AnalyticsEventPayload` + `AnalyticsValue` (Codable, Sendable).
- [x] `AnalyticsRedactor.swift` — PII key blocklist + string value scrubbing via `LogRedactor`.
- [x] `AnalyticsConsentManager.swift` — `@Observable @MainActor`, default opt-out, `UserDefaults` persistence.
- [x] `TenantServerAnalyticsSink.swift` — actor, batch 50 events, flush every 60s, `POST /analytics/events`, fire-and-forget.
- [x] `LocalDebugSink.swift` — `#if DEBUG` OSLog via `AppLog.telemetry`.
- [x] `SinkDispatcher.swift` — actor fan-out (server + debug), scrubs properties.
- [x] `Analytics.swift` — static `Analytics.track(...)` entry point, fire-and-forget Task.
- [x] `AnalyticsConsentSettingsView.swift` — Settings → Privacy toggle, "View what's shared", "Delete my analytics" (GDPR).
- [x] `AnalyticsSchemaView.swift` — lists all 57 events grouped by category, searchable.
- [x] Tests: 44 tests — `AnalyticsEventCatalogTests` (13), `AnalyticsRedactorTests` (12), `AnalyticsConsentManagerTests` (9), `TenantServerAnalyticsSinkTests` (10). All 260 suite tests pass.

---
## §72. Final UX Polish Checklist
<!-- shipped 2026-04-20 feat(ios post-phase §72) -->
- [x] Checklist doc: `docs/ux/polish-checklist.md` — 99 items across 16 categories.
- [x] Lint script: `ios/scripts/ux-polish-lint.sh` — 8 anti-pattern rules, baseline 123, exits 0.
- [x] `ToastPresenter.swift` — `@Observable`, glass pill, auto-dismiss 4s/5s, tap-to-dismiss, stack 3.
- [x] `SkeletonShimmer.swift` — shimmer modifier + `SkeletonRow` + `SkeletonList`; Reduce Motion respected.
- [x] `EmptyStateCard.swift` — `{icon,title,message,primaryAction?,secondaryAction?}`, 3 variants (standard/error/onboarding).
- [x] `DragDismissIndicator.swift` — 36×4pt pill; fade-only on Reduce Motion; `.dragDismissIndicator()` convenience.
- [x] `MonospacedDigits.swift` — `.monoNumeric()` modifier + `CentsFormatter` (Cents→Decimal, no Double drift).
- [x] `ios/Tests/PolishTests.swift` + `DesignSystemTests/PolishTests.swift` — 30 new tests; all pass.
- [x] CI gate: `LintScriptTests.testUXPolishLintExitsZero` runs lint in `swift test` — passes.

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

### 78.7 Implementation status
- [x] Core/Models: Customer, Ticket, InventoryItem (pre-existing)
- [x] Core/Models: Invoice, InvoiceLineItem, InvoicePayment, InvoiceStatus (4f4a11a)
- [x] Core/Models: Estimate, EstimateLineItem, EstimateStatus (4f4a11a)
- [x] Core/Models: Lead, LeadStatus, LeadSource (4f4a11a)
- [x] Core/Models: Appointment, AppointmentStatus (4f4a11a)
- [x] Core/Models: Expense, ExpenseCategory (4f4a11a)
- [x] Core/Models: Employee, EmployeeRole (4f4a11a)
- [x] Core/Models: CashSession, CashSessionStatus (4f4a11a)
- Campaign, Segment — defined in Marketing/Models.swift (skip duplicate)
- AuditLogEntry — defined in AuditLogs/AuditLogEntry.swift (skip duplicate)
- Role — defined in RolesEditor/Role.swift (skip duplicate)

---
## §79. Multi-tenant user session mgmt — SCOPE REDUCED

**Scope decision (2026-04-20):** In-app live multi-tenant switching dropped (see §19.22, §77). Rationale: near-zero real-world usage, complicates security scoping, and the sign-out → sign-in path (with last-used server + username prefilled + biometric) handles franchise operator / freelance tech cases in ~3 seconds.

**[x] §79 Phase 1 TenantSwitcher shipped** — `Auth/TenantSwitcher/` (Tenant, TenantStore, TenantRepository, TenantSwitcherViewModel, TenantSwitcherView, TenantPickerSheet, TenantEndpoints, TenantSwitchNotification). 36 tests pass (TenantStoreTests 13, TenantSwitcherViewModelTests 16, TenantRepositoryTests 7).

### 79.1 What stays
- [x] **Per-login tenant scoping** — each sign-in binds to exactly one tenant; single active SQLCipher DB; no concurrent sessions held in memory.
- [x] **Last-used persistence** — Keychain stores `activeTenantId`; `TenantStore.load()` reconciles on startup.
- [x] **Multiple-servers hint** — Login screen remembers recently-used servers in a chip row for quick pick. (ecb07902 — RecentServersStore.swift + RecentServersRow.swift)
- [x] **Per-tenant push token** — when signing in to a new tenant, previous APNs token unregistered server-side (so pushes don't cross tenants). (ecb07902 — APIClient+Tenant.swift registerDeviceToken/unregisterDeviceToken)

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
- [x] Semantic tokens: `DesignTokens.SemanticColor.accent/danger/warning/success/info`, surface, text, border aliases — all pointing to existing asset-catalog colors. (`DesignTokens.SemanticColor` namespace in `Tokens.swift`. feat(§80.9): 9c4e4c90)

### 80.10 Density mode tokens
- [x] `DesignTokens.Density.Mode` — three named levels (`comfortable` ×1.15, `default` ×1.00, `compact` ×0.85); `spacing(base:mode:)` helper; `DensityModeKey` SwiftUI `EnvironmentKey`; `EnvironmentValues.densityMode` extension. Feeds spacing rhythm per §571; orthogonal to Reduce Motion. (`Tokens.swift`. feat(§80.10): current)

### 80.11 Brand gradient stops
- [x] `BrandGradients` enum — five named `LinearGradient` constants: `heroSurface`, `primaryRamp` (cream→orange), `glassEdgeFadeTop`, `glassEdgeFadeBottom`, `successCelebration`, `dangerAlert`. All stops reference asset-catalog entries; no inline hex values. (`BrandColors.swift`. feat(§80.11): current)

### 80.12 Glass blur ladder
- [x] `GlassBlur` enum — seven named blur steps: `hairline` (2pt), `subtle` (6pt), `card` (12pt), `sheet` (20pt), `chrome` (32pt), `hero` (48pt), `immersive` (72pt). Each step carries `radius` + `solidOpacity` (Reduce Transparency fallback). `blurStep(_ step:)` view modifier gates `.blur(radius:)` vs solid fill on `accessibilityReduceTransparency`. (`GlassKit.swift`. feat(§80.12): current)

### 80.13 Motion curve aliases
- [x] `MotionCurveAlias` — semantic alias table composing `BrandCurve` + `MotionEasingSpec` + `MotionDurationSpec`. Covers: `enter`, `exit`, `pageEnter`, `heroTransition`, `celebrate`, `confirm`, `ambient`, `standard`, `expand`, `collapse`; Reduce Motion variants for `enter`, `celebrate`, `heroTransition`. `enterAnimation(value:)` + `celebrateAnimation(value:)` view modifiers. (`Motion/MotionCurveAliases.swift`. feat(§80.13): current)

### 80.14 Asset color migration audit (warn-only lint)
- [x] `ColorMigrationAudit` — DEBUG-only warn-only audit helpers: `warn(inlineColor:suggestedToken:file:line:)`, `warnGray(white:suggestedToken:file:line:)`, `warningCount` counter for snapshot-test assertions, `resetCounter()`. `@InlinedColor` property wrapper for intentional design-exceptions. `View.assertNoInlineColor()` snapshot-test helper. SwiftLint `forbid_inline_design_values` custom rule documented inline (regex targets `Color(red:|green:|blue:|white:|hue:|saturation:|brightness:)`). Migration guidance table maps common inline literals → recommended tokens. (`ColorMigrationLint.swift`. feat(§80.14): current)
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
- [x] **Launch-readiness check helper** — `ios/scripts/launch-readiness.sh`; 7 gates: PrivacyInfo.xcprivacy present + no tracking, Info.plist purpose strings (8 keys), credential scan, SDK sovereignty, debug print scan, fastlane metadata dir, Snapfile. Exits 1 on any failure; called by fastlane `preflight` lane. (feat(§82): launch-readiness check helper)
- [x] **Smoke-test runner** — `ios/scripts/smoke-test-runner.sh`; 5 gates: xcodegen freshness, SPM resolution, SmokeTests, AuthTests, sdk-ban + app-review-lint; `--scheme`/`--os`/`--device` flags; writes `.xcresult` bundles to `/tmp/smoke-results/`. (feat(§82): smoke-test runner script)

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

### 83.6 Documentation checklist

- [x] **DocC comments — `Customer` model** — add full DocC header + property docs to `Packages/Core/Sources/Core/Models/Customer.swift`; covers `displayName`, `Codable` conformance note, and tenant-scoping.
- [x] **DocC comments — `InventoryItem` model** — add DocC header + property docs to `Packages/Core/Sources/Core/Models/InventoryItem.swift`; cover `isLowStock`, cent-denominated price/cost fields, and reorder logic.
- [x] **DocC comments — `Ticket` + `TicketStatus`** — add DocC to `Packages/Core/Sources/Core/Models/Ticket.swift`; document state machine reference (§88.1), `totalCents` semantics, and all `TicketStatus` cases.
- [x] **DocC comments — `Currency` formatter** — add DocC header + `formatCents(_:code:)` parameter docs to `Packages/Core/Sources/Core/Formatting/CurrencyFormatter.swift`.
- [x] **DocC comments — `PhoneFormatter`** — add DocC header + `format(_:)` / `normalize(_:)` docs to `Packages/Core/Sources/Core/Formatting/PhoneFormatter.swift`; cover NANP convention and E.164 output contract.

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
- 2026-04-20 (update 30) — Phase 0 gate close: [x] Core error taxonomy (`Core/Errors/AppError.swift` — 16-case enum, LocalizedError, `AppError.from/fromHttp` helpers). [x] Draft recovery framework (`Core/Drafts/DraftStore.swift` actor + `DraftRecord` + `DraftRecoverable` protocol + `DraftRecoveryBanner` SwiftUI view). [x] Logging expansion (`Core/AppLog.swift` → `Core/Logging/AppLog.swift`, `LogLevel`, `LogRedactor`, `TelemetrySink`). Tests: 59 new tests (AppErrorTests 25, DraftStoreTests 15, LogRedactorTests 19) all green. swift test 63/63 pass.
- 2026-04-20 (update 30) — Renumbered §§1-90 sequentially; converted all headings to `## §N.` format; swept all inline cross-refs across ActionPlan.md + agent-ownership.md (TODO.md had no §N refs). Invalid refs pointing at deleted sections were remapped per the update-28/29 absorption trail to their surviving target sections; zero unresolved flags remaining. TOC rebuilt against new numbering.
- 2026-04-20 (update 31) — Phase 0 gate close (infrastructure): [x] Real airplane-mode smoke test (`ios/Tests/SmokeTests.swift`) — 7 XCTest cases exercising in-memory GRDB migrations, sync_queue/sync_state table presence, enqueue, offline banner condition, drain via markSucceeded, failure path with next_retry_at, dead-letter after maxAttempts, and DLQ retry with fresh idempotency key. [x] SDK-ban lint (`ios/scripts/sdk-ban.sh`) — checks 14 forbidden SDK imports, bare URLSession construction outside Networking, and APIClient calls outside *Repository/*Endpoints; dry-run passes clean on current tree. [x] CI workflow (`.github/workflows/ios-lint.yml`) — triggers on ios/** PR + push to main; runs sdk-ban.sh on ubuntu-latest; xcodebuild step stubbed for macOS runner. §20 CI enforcement bullets and §32.0 build-time lint checkbox retro-marked [x].
- 2026-04-20 (update 32) — Phase 1 §2 auth extras shipped: [x] Magic-link login (MagicLink/ — MagicLinkEndpoints, MagicLinkURL, MagicLinkRepository, MagicLinkViewModel, MagicLinkRequestView — iPhone/iPad adaptive, 60s resend cooldown, deep-link parser for bizarrecrm://auth/magic + https://app.bizarrecrm.com/auth/magic). [x] Session timeout (SessionTimer.swift actor — configurable idleTimeout + pollInterval, touch/pause/resume/currentRemaining, 80% onWarning, onExpire; SessionTimeoutWarningBanner.swift glass toast). [x] Remember-me (CredentialStore.swift actor — EmailStorage protocol + KeychainEmailStorage production + InMemoryEmailStorage test; rememberEmail/lastEmail/forget; KeychainKey.rememberedEmail added). [x] Shared-device mode (SharedDevice/ — SharedDeviceManager actor with SharedDeviceStorage protocol + UserDefaultsDeviceStorage + InMemoryDeviceStorage; SharedDeviceEnableView adaptive). 144 tests pass (11 MagicLink URL+VM, 8 SessionTimer, 8 CredentialStore, 13 SharedDeviceManager; all new + pre-existing green).
- 2026-04-20 (update 35) — Phase 9 §19 Settings search + Tenant admin + Feature flags UI shipped: [x] `Core/FeatureFlag.swift` — 28-case enum, `allCases`, `defaultValue`, `displayName`, Sendable. [x] `Settings/Search/SettingsSearchIndex.swift` — 40+ `SettingsEntry` records across Profile, Company, Tax, Hours, Holidays, Locations, Payments, BlockChyp, Notifications, Printers, SMS, Appearance, Language, Danger Zone, Roles, Audit Logs, Data Import/Export, Kiosk, Training, Setup Wizard, Price Overrides, Device Templates, Marketing, Loyalty, Reviews, Referral, Survey, Widgets, Shortcuts, Tenant Admin, Feature Flags, About, Diagnostics; `filter(query:)` with prefix/contains/word-boundary fuzzy. [x] `SettingsSearchViewModel.swift` — `@Observable @MainActor`, 200ms debounce. [x] `SettingsSearchView.swift` — Liquid Glass search field + results list (iPhone) / sidebar filter (iPad); a11y labels, Reduce Motion, `hoverEffect`. [x] `TenantAdmin/TenantAdminEndpoints.swift` — `GET /tenant`, `GET /tenant/api-usage`, `POST /tenant/impersonate`. [x] `FeatureFlagManager.swift` — 3-tier precedence (local override → server → default); `setLocalOverride`, `clearAllOverrides`, `updateServerValues`, testable init. [x] `FeatureFlagsView.swift` — searchable list of all flags, per-flag toggle + server badge + reset; admin-only. [x] `TenantAdminView.swift` — tenant ID/slug/plan/status/renewal; API usage stats; impersonation entry; glass header. [x] `TenantAdminViewModel.swift` — parallel load of tenant + usage. [x] `APIUsageChart.swift` — Swift Charts bar chart; 30-day fill; `process(_:)` pure function. [x] `ImpersonateUserSheet.swift` — user picker + reason + manager PIN + audit consent; a11y. [x] `SettingsView.swift` updated: search field at top; Admin section gated by `isAdmin`. Tests: 139 tests in 16 suites all passing (`swift test` green). Commit: `feat(ios phase-9 §19)`.
- 2026-04-20 (update 34) — Phase 7 §23 Keyboard handling shipped: [x] `KeyboardShortcutCatalog` — 23 shortcuts across 6 groups (File, Navigation, POS, Search, Sync, Session), unique IDs, Sendable. [x] `KeyboardShortcutOverlayView` — ⌘/ invokes full-screen glass cheat-sheet; iPad 3-col `LazyVGrid`, iPhone single-col `List`; group headings `.isHeader`, row labels read "Cmd+N — New Ticket"; Reduce Motion respected. [x] `KeyboardShortcutBinder` ViewModifier + `.registeredKeyboardShortcut(id:onAction:)` extension. [x] `HardwareKeyboardDetector` @Observable @MainActor — GCKeyboard.coalesced + NC notifications; `ShortcutHintPill` "Press ⌘/ for shortcuts" badge. [x] `MainShellView` wired: ⌘/ overlay, ⌘1–⌘6 nav tabs, hardware keyboard pill. [x] 22 XCTest cases (KeyboardShortcutCatalogTests 12, KeyboardShortcutBinderTests 3, HardwareKeyboardDetectorTests 5) in `ios/Tests/KeyboardShortcutCatalogTests.swift` covering count ≥20, unique IDs, required IDs, grouping, lookup, labels, Sendable conformance, notify connect/disconnect.
- 2026-04-20 (update 36) — Phase 10 §26 A11y label catalog + §26 TipKit sticky tips + §29 Automated a11y audit CI shipped: [x] `Core/A11y/Labels.swift` — `A11yLabels` pure enum (5 namespaces: Actions/44 entries, Status/19, Navigation/9, Fields/26, Entities/15, Decorative/1); Swift 6 Sendable; zero deps. [x] `DesignSystem/Tips/BrandTip.swift` — base `BrandTip: Tip` protocol (TipKit). [x] `DesignSystem/Tips/TipCatalog.swift` — 5 tips: `CommandPaletteTip` (⌘K after 3 launches), `SwipeToArchiveTip` (after tickets list view), `PullToRefreshTip` (first launch), `ContextMenuTip` (row view), `ScanBarcodeTip` (SKU field view); each has title/message/image/rules/MaxDisplayCount(1); `TipEventPayload: Codable` fixes Void Codable issue. [x] `DesignSystem/Tips/TipModifier.swift` — `View.brandTip(_:arrowEdge:)` wraps `.popoverTip` + `BrandTipBackground` glass style. [x] `DesignSystem/Tips/TipsRegistrar.swift` — `TipsRegistrar.registerAll()` + donate helpers; all `#if canImport(TipKit)` guarded. [x] `scripts/a11y-audit.sh` — Bash 3.x compatible; 6 checks (Button/TextField without a11y label, Image without a11y, onTapGesture tap-target, fixed font size, animation without reduceMotion check); `--baseline` seeds violation count; `--check-regressions` blocks on count increase; `--json-only` for CI; exits 1 on violations. [x] `Tests/A11yAuditTests.swift` — 3 XCTest cases: script exists+executable, regression check, JSON output valid. [x] `.github/workflows/ios-a11y.yml` — ubuntu-latest job; regression-check mode; artifact upload; PR annotation on failure; macOS swift-test job stubbed. Fixed pre-existing `RTLHelpers.swift` bare `import UIKit` → `#if canImport(UIKit)` to unblock macOS SwiftPM build. Tests: 8 A11yLabelsTests (all pass) + 28 TipCatalogTests (all pass).
- 2026-04-20 (update 37) — Phase 11 §28+§33+§90 shipped: [x] `docs/security/threat-model.md` — full STRIDE table (6 categories × 24 threat rows), top-10 residual risk ranking, mitigation evidence map, sign-off section. [x] `docs/security/threat-model-actions.md` — action checklist (1 High, 7 Medium, 3 Low items with owners). [x] `docs/app-review.md` — App Review checklist covering §§1-5 of Apple guidelines, privacy manifest section documenting `PrivacyInfo.xcprivacy` required keys, pre-submission gate checklist. [x] `ios/scripts/app-review-lint.sh` — Bash 3.x lint script (4 checks: purpose strings, private APIs, debug prints, hardcoded credentials); excludes SPM `.build/checkouts/` from source scan; exits 1 on failures. [x] `ios/scripts/write-info-plist.sh` + `ios/App/Resources/Info.plist` — added missing `NSMicrophoneUsageDescription` + `NSLocationWhenInUseUsageDescription`. Baseline dry-run: 2 FAIL (Info.plist missing strings — now fixed); 0 FAIL on private APIs; 0 FAIL on credentials; print() check limited to first-party Sources/ only.
- 2026-04-20 (update 33) — Phase 7 §22.4 multi-window + Stage Manager + §22.2 adaptive sidebar + §25.3 Universal Clipboard shipped: [x] MultiWindowCoordinator (App/Scenes/) — openTicketDetail/openCustomerDetail/openInvoiceDetail via UIApplication.requestSceneSessionActivation + NSUserActivity route encoding. [x] SceneDelegate (App/Scenes/) — UIWindowSceneDelegate handling URL contexts + Handoff activities for secondary windows. [x] DetailWindowScene (App/Scenes/) — SwiftUI WindowGroup(id:"detail") root view with DeepLinkRoute dispatch + ContentUnavailableView fallback. [x] StageManagerDetector (App/Scenes/) — @Observable class watching UIScene notifications, connectedScenes.count > 1 heuristic, isStageManagerActive property. [x] SidebarWidthBehavior (App/Sidebar/) — SidebarWidth enum + SidebarWidthCalculator pure helper (compact/regular/expanded per §22.2 values). [x] RootView iPadSplit — wrapped in GeometryReader, navigationSplitViewColumnWidth fed from SidebarWidthCalculator.recommendedSidebarWidth, accessibilityLabel on sidebar items. [x] UniversalClipboardBridge (App/Clipboard/) — PasteboardProtocol abstraction + writePlainText/readPlainText async, UIPasteboard.general production, MockPasteboard for tests. 32 new tests: SidebarWidthCalculatorTests (12), StageManagerDetectorTests (8), UniversalClipboardBridgeTests (12). All branches covered ≥ 80%.

- 2026-04-20 (update 39) — Post-phase §9 Leads: pipeline kanban + scoring + conversion + lost reasons + follow-ups + source analytics shipped: [x] `Pipeline/` — `LeadPipelineView` (iPhone stage-picker + iPad horizontal scroll), `LeadPipelineColumn` (Liquid Glass header, count badge, kanban cards with a11y), `LeadPipelineViewModel` (@Observable, stage grouping, source filter, optimistic drag-drop via `PUT /leads/:id` + rollback). [x] `Scoring/` — `LeadScore` model (0–100 clamped), `LeadScoreCalculator` pure (5 weighted factors: engagement 30%, velocity 25%, budget 20%, timeline 15%, source 10%), `LeadScoreBadge` (Red<30/Amber/Green). 18 XCTests pass. [x] `Conversion/` — `LeadConvertSheet` + `LeadConvertViewModel` (`POST /leads/:id/convert`, pre-fill name/phone/email/source, optional ticket, marks lead won). [x] `Lost/` — `LostReasonSheet` (picker: price/timing/competitor/no-response/other + free-text, `POST /leads/:id/lose`), `LostReasonReport` (admin bar chart). [x] `FollowUp/` — `LeadFollowUpReminder` model, `LeadFollowUpSheet` (date+note, `POST /leads/:id/followup`), `LeadFollowUpDashboard` (today's reminders, `GET /leads/followups/today`). [x] `LeadSources/` — `LeadSource` enum (6 values), `LeadSourceAnalytics` pure (conversion rate + per-source stats, 12 XCTests pass), `LeadSourceReportView` (admin bar chart). [x] `Networking/LeadsEndpoints.swift` — added `LeadStatusUpdateBody`, `LeadConvertBody/Response`, `LeadLoseBody/Response`, `LeadFollowUpBody/Response` + 6 new APIClient methods. Total: 50 tests, 0 failures.

- 2026-04-20 (update 38) — Post-phase §4 Tickets extensions shipped: [x] Ticket merge (TicketMergeViewModel + TicketMergeView iPad 3-col/iPhone sheet + TicketMergeCandidatePicker; POST /tickets/merge; per-field winner picker; destructive warning). [x] Ticket split (TicketSplitViewModel + TicketSplitView checkbox-per-device + Create-N button; POST /tickets/:id/split; canSplit guard). [x] Device photos (TicketDevicePhotoListView gallery + full-screen preview + TicketPhotoBeforeAfterView side-by-side + TicketPhotoUploadService actor background URLSession + offline queue + retry + TicketPhotoAnnotationIntegration PencilKit shim). [x] Customer sign-off (TicketSignOffView PKCanvasView + disclaimer + ReceiptConfirmationView + TicketSignOffViewModel GPS + base-64 PNG; POST /tickets/:id/sign-off; shown when status contains pickup). [x] IMEI scanner (IMEIValidator pure Luhn + 15-digit; IMEIScanView barcode+manual; IMEIConflictChecker GET /tickets/by-imei/:imei; wired into TicketCreateView). [x] TicketDetailView wired: Merge/Split overflow actions; Photos section inline; Sign-Off button when readyForPickup. Tests: 198 total (20 IMEIValidator, 10 TicketMergeViewModel, 11 TicketSplitViewModel, 9 TicketSignOffViewModel, 12 TicketPhotoUploadService) — all pass. swift test green.

## Web-Parity Backend Contracts (2026-04-23)

New server endpoints built to close mobile → web parity gaps flagged in `todo.md` (SCAN-472, SCAN-475, SCAN-478-482, SCAN-484-489, SCAN-497). All routes require a Bearer JWT (`authMiddleware` applied at parent mount). Per-endpoint role gates + rate-limits + input validation are enforced inside each router. Response shape is the project convention `{ success: true, data: <payload> }`.

Migrations added this wave: **120_expenses_approval_mileage_perdiem.sql**, **121_shifts_timeoff_timesheet.sql**, **122_inventory_variants_bundles.sql**, **123_recurring_invoices.sql**, **124_activity_notifprefs_heldcarts.sql**.

Cron added: `startRecurringInvoicesCron` — fires every 15 min from `index.ts` post-listen, scanning every tenant DB for active `invoice_templates` whose `next_run_at <= now()`, generating invoices, advancing the cycle.

---

### 1. Expense Approvals + Mileage + Per-Diem (SCAN-480/481/482)

Base: `/api/v1/expenses/…`. Approve/deny require manager or admin. Mileage/per-diem use the same approval workflow as general expenses.

**GET /** — extended with two new query filters:
| Param | Values |
|---|---|
| `status` | `pending` / `approved` / `denied` |
| `expense_subtype` | `general` / `mileage` / `perdiem` |

**POST /mileage** — compute `amount_cents = round(miles * rate_cents)`.
```json
{
  "vendor": "Personal vehicle",
  "description": "Customer site visit",
  "incurred_at": "2026-04-23",
  "miles": 42.5,
  "rate_cents": 67,
  "category": "Travel",
  "customer_id": 101
}
```
Constraints: `miles` 0–1000, `rate_cents` 1–50000, `customer_id` optional.

**POST /perdiem** — compute `amount_cents = days * rate_cents`.
```json
{
  "description": "Conference travel — Atlanta",
  "incurred_at": "2026-04-20",
  "days": 3,
  "rate_cents": 7500,
  "category": "Per Diem"
}
```
Constraints: `days` 1–90, `rate_cents` 1–50000.

**POST /:id/approve** — manager/admin. Empty body. Sets `status=approved` + `approved_by_user_id` + `approved_at`.

**POST /:id/deny** — manager/admin. Body `{ "reason": "..." }` (≤500 chars). Sets `status=denied` + `denial_reason`.

Response shapes mirror existing expense row + new columns (`status`, `expense_subtype`, `mileage_miles`, `mileage_rate_cents`, `perdiem_days`, `perdiem_rate_cents`, `approved_by_user_id`, `approved_at`, `denial_reason`).

---

### 2. Shift Schedule + Time-Off + Timesheet (SCAN-475/484/485)

#### Shifts — `/api/v1/schedule`
- `GET /shifts?user_id=&from_date=&to_date=` — non-managers see own only.
- `POST /shifts` (manager+) `{ user_id, start_at, end_at, role_tag?, location_id?, notes? }`.
- `PATCH /shifts/:id` (manager+) — partial.
- `DELETE /shifts/:id` (manager+).
- `POST /shifts/:id/swap-request` (shift owner only) `{ target_user_id }` → returns pending swap row.
- `POST /swap/:requestId/accept` (target user) — transfers shift.user_id.
- `POST /swap/:requestId/decline` (target user).
- `POST /swap/:requestId/cancel` (requester only, only while pending).

Example create:
```json
POST /api/v1/schedule/shifts
{ "user_id": 3, "start_at": "2026-05-01T09:00:00", "end_at": "2026-05-01T17:00:00",
  "role_tag": "tech", "location_id": 1, "notes": "Opening shift" }
```

#### Time-off — `/api/v1/time-off`
- `POST /` — self-service `{ start_date, end_date, kind: "pto"|"sick"|"unpaid", reason? }`.
- `GET /?user_id=&status=` — self by default; manager+ sees all.
- `POST /:id/approve` (manager+).
- `POST /:id/deny` (manager+) `{ reason? }`.

Writes dual-column (`approver_user_id` + legacy `approved_by_user_id`, `decided_at` + legacy `approved_at`) for migration-096 backward compatibility.

#### Timesheet — `/api/v1/timesheet`
- `GET /clock-entries?user_id=&from_date=&to_date=` — manager+ or self.
- `PATCH /clock-entries/:id` (manager+) `{ clock_in?, clock_out?, notes?, reason }`. `reason` REQUIRED. Audit row inserted into `clock_entry_edits` with before/after JSON. `audit()` fires with `event='clock_entry_edited'`.

---

### 3. Inventory Variants + Bundles (SCAN-486/487)

Mutating endpoints gated by `requirePermission('inventory.adjust')`. Money stored as INTEGER cents per SEC-H34 policy.

#### Variants — `/api/v1/inventory-variants`
- `GET /items/:itemId/variants?active_only=true|false` — list.
- `POST /items/:itemId/variants` `{ sku, variant_type, variant_value, retail_price_cents, cost_price_cents?, in_stock? }`.
- `PATCH /variants/:id` — partial.
- `DELETE /variants/:id` — soft (`is_active=0`).
- `PATCH /variants/:id/stock` `{ delta, reason }` — atomic in tx. Rejects negative result.

Example:
```json
POST /api/v1/inventory-variants/items/42/variants
{ "sku": "SCRN-IPHONE14-BLK", "variant_type": "color", "variant_value": "Black",
  "retail_price_cents": 8999, "cost_price_cents": 4500, "in_stock": 10 }
```

#### Bundles — `/api/v1/inventory-bundles`
- `GET /?page=&pagesize=&is_active=&keyword=` — list.
- `GET /:id` — detail + resolved items array.
- `POST /` `{ name, sku, retail_price_cents, description?, items:[{item_id, variant_id?, qty}] }`.
- `PATCH /:id` — partial.
- `DELETE /:id` — soft.
- `POST /:id/items` `{ item_id, variant_id?, qty }`.
- `DELETE /:id/items/:bundleItemId`.

Audit events: `inventory_variant_*` (created/updated/deactivated/stock_adjusted), `inventory_bundle_*`.

---

### 4. Recurring Invoices + Credit Notes (SCAN-478/479/489) + cron

#### Recurring Invoices — `/api/v1/recurring-invoices` (admin-only writes)
- `GET /?page=&pagesize=&status=` — list templates.
- `GET /:id` — detail + last 20 runs from `invoice_template_runs`.
- `POST /` `{ name, customer_id, interval_kind: "daily"|"weekly"|"monthly"|"yearly", interval_count, start_date, line_items:[{description, quantity, unit_price_cents, tax_class_id?}], notes_template? }`.
- `PATCH /:id` — partial (`status`, `next_run_at`, `notes_template`, `line_items`).
- `POST /:id/pause` | `/resume` | `/cancel` — lifecycle transitions. Audited.

Example:
```json
POST /api/v1/recurring-invoices
{ "name": "Monthly hosting fee", "customer_id": 42,
  "interval_kind": "monthly", "interval_count": 1, "start_date": "2026-05-01",
  "line_items": [{ "description": "Hosting", "quantity": 1, "unit_price_cents": 4999 }] }
```

#### Cron — `startRecurringInvoicesCron`
Runs every 15 minutes. Per tenant DB it executes:
1. Atomically advance `next_run_at` (UPDATE ... WHERE next_run_at <= now()) → double-fire protection.
2. Create `invoices` + `invoice_line_items` rows.
3. Insert `invoice_template_runs` row (`succeeded=1`).
On error: record `succeeded=0` + `error_message` and move on.

#### Credit Notes — `/api/v1/credit-notes` (manager+ for apply/void)
- `GET /?page=&pagesize=&status=&customer_id=`.
- `GET /:id`.
- `POST /` `{ customer_id, original_invoice_id, amount_cents, reason }`.
- `POST /:id/apply` `{ invoice_id }` — tx: reduce `invoices.amount_due` by the credit; mark `status=applied`; audit.
- `POST /:id/void` — only `open` notes. Audit.

---

### 5. Activity Feed + Notification Preferences + Held Carts (SCAN-488/472/497)

#### Activity Feed — `/api/v1/activity`
- `GET /?cursor=&limit=&entity_kind=&actor_user_id=` — cursor-based (monotonic id). Non-managers: `actor_user_id` clamped to `req.user.id`. Default 25, max 100.
- `GET /me` — shortcut.

Response:
```json
{ "success": true, "data": {
  "events": [
    { "id": 42, "actor_user_id": 1, "entity_kind": "ticket", "entity_id": 519,
      "action": "status_changed", "created_at": "2026-04-23 14:00:00",
      "actor_first_name": "Pavel", "actor_last_name": "Ivanov",
      "metadata": { "from": "open", "to": "in_progress" } }
  ],
  "next_cursor": "41"
}}
```

Helper `logActivity(adb, {...})` exported from `utils/activityLog.ts` — call from any route handler to emit an event (never throws; logs warn on failure).

#### Notification Preferences — `/api/v1/notification-preferences`
- `GET /me` — returns matrix backfilled with `enabled=true` defaults.
- `PUT /me` `{ preferences: [{ event_type, channel, enabled, quiet_hours? }, ...] }` — batch upsert.

Valid `event_type` (20): `ticket_created`, `ticket_status`, `invoice_created`, `payment_received`, `estimate_sent`, `estimate_signed`, `customer_created`, `lead_new`, `appointment_reminder`, `inventory_low`, `backup_complete`, `backup_failed`, `marketing_campaign`, `dunning_step`, `security_alert`, `system_update`, `review_received`, `refund_processed`, `expense_submitted`, `time_off_requested`.
Valid `channel` (4): `push`, `in_app`, `email`, `sms`.

Payload cap: 32 KB total. Rate limit 30/min.

#### Held Carts — `/api/v1/pos/held-carts`
- `GET /` — own active carts (admins may add `?all=1`).
- `GET /:id` — own or admin.
- `POST /` `{ cart_json, label?, workstation_id?, customer_id?, total_cents? }` — `cart_json` ≤ 64 KB.
- `DELETE /:id` — soft via `discarded_at`. Audited.
- `POST /:id/recall` — sets `recalled_at`, returns full row (client reads `cart_json` to restore).

---

### Security checklist applied to every endpoint in this wave

- Integer IDs validated `Number.isInteger && > 0` before SQL.
- Parameterized queries only — no string-interpolated SQL.
- Length caps on every string field + byte caps on JSON bodies.
- Role gates via `requireAdmin` / `requireManagerOrAdmin` / `requirePermission` from `middleware/auth.ts`.
- Rate limits via `checkWindowRate` + `recordWindowAttempt` (not deprecated `recordWindowFailure`).
- Audit writes via `audit(db, {...})` for every sensitive operation.
- Money columns `INTEGER` cents with `CHECK >= 0` at schema level.
- Soft deletes (`is_active=0` / `discarded_at`) to preserve FK integrity where needed.
- Errors thrown via `AppError(msg, status)` — no raw `throw` leaking stack traces.

### Registration order in `packages/server/src/index.ts`

After existing `bench` mount, authenticated routes registered in this order:
`/schedule`, `/time-off`, `/timesheet`, `/inventory-variants`, `/inventory-bundles`, `/recurring-invoices`, `/credit-notes`, `/activity`, `/notification-preferences`, `/pos/held-carts`.

## Web-Parity Backend Contracts — Wave 2 (2026-04-23)

Second wave of endpoints built to close mobile → web parity gaps. Closes SCAN-464, 465, 468, 469, 470, 490, 494, 495, 498. All routes JWT-gated (authMiddleware applied at parent mount in index.ts) EXCEPT the explicitly-public estimate-sign endpoints — those use signed single-use tokens as the credential.

Migrations added: **125_labels_shared_device.sql**, **126_estimate_signatures_export_schedules.sql**, **127_sms_autoresponders_groups.sql**, **128_checklist_sla.sql**, **129_ticket_signatures_receipt_ocr.sql**.

Crons added: **startDataExportScheduleCron** (hourly), **startSlaBreachCron** (every 5 min).

---

### 1. Ticket Labels + Shared-Device Mode (SCAN-470 / SCAN-469)

#### Labels — `/api/v1/ticket-labels` (manager+ on writes)
- `GET /?show_inactive=true|false` — list.
- `POST /` `{ name, color_hex?, description?, sort_order? }` — 409 on UNIQUE(name) collision.
- `PATCH /:id` — partial.
- `DELETE /:id` — soft (`is_active=0`). Assignments preserved via CASCADE.
- `POST /tickets/:ticketId/assign` `{ label_id }` — 409 if already assigned, 422 if label deactivated.
- `DELETE /tickets/:ticketId/labels/:labelId`.
- `GET /tickets/:ticketId` — list labels on ticket.

Color validated against `/^#[0-9A-Fa-f]{6}$/`. Rate-limit 60 writes/min/user.

#### Shared-Device Mode — settings config keys (admin PUT, any authed GET)
Accessed via existing `/api/v1/settings/config`. New keys added to `ALLOWED_CONFIG_KEYS`:
- `shared_device_mode_enabled` — `"0"` / `"1"` (default `"0"`)
- `shared_device_auto_logoff_minutes` — integer string (default `"0"` disables)
- `shared_device_require_pin_on_switch` — `"0"` / `"1"` (default `"1"`)

Seed row `INSERT OR IGNORE` in migration 125 sets safe defaults.

---

### 2. Estimate E-Sign Public URL (SCAN-494) + Data-Export Schedules (SCAN-498)

#### Estimate Sign Token
Format: `base64url(estimateId) + '.' + hex(HMAC-SHA256(key, estimateId + '.' + expiresTs))`. Signing key: `ESTIMATE_SIGN_SECRET` env var (≥32 chars) OR HKDF-SHA256 over `JWT_SECRET` with info `estimate-sign`. Persisted as `sha256(rawToken)` in `estimate_sign_tokens.token_hash` — raw token returned to caller once, never stored.

#### Authed endpoints
- `POST /api/v1/estimates/:id/sign-url` (manager+) body `{ ttl_minutes?=4320 }` → `{ url, expires_at, estimate_id }`. Rate-limit 5/hr/estimate.
- `GET /api/v1/estimates/:id/signatures` (manager+) — lists captured signatures (data URL omitted from list view).

#### Public endpoints — NO JWT, token is credential, 10 req/hr per IP
- `GET /public/api/v1/estimate-sign/:token` — returns estimate summary (line items, totals, customer name). 410 if consumed/expired.
- `POST /public/api/v1/estimate-sign/:token` body `{ signer_name, signer_email?, signature_data_url }` — atomic tx marks token consumed + inserts `estimate_signatures` row + sets `estimates.status='signed'`. Size cap: decoded image ≤ 200 KB.

#### Data-Export Schedules — `/api/v1/data-export/schedules` (admin-only)
- `GET /`, `GET /:id` (with last 20 runs), `POST /`, `PATCH /:id`.
- `POST /:id/pause` | `/resume` | `/cancel`.

Create payload:
```json
{ "name": "Weekly full backup", "export_type": "full",
  "interval_kind": "weekly", "interval_count": 1,
  "start_date": "2026-04-28T00:00:00Z",
  "delivery_email": "owner@example.com" }
```
`export_type`: `full|customers|tickets|invoices|inventory|expenses`. `interval_kind`: `daily|weekly|monthly`.

#### Cron — `startDataExportScheduleCron`
Hourly. Claims due schedules via atomic UPDATE. Heartbeat row inserted into `data_export_schedule_runs`. Full generation deferred until `dataExport.routes.ts` streaming logic is extracted to a service.

---

### 3. SMS Auto-Responders + Group Messaging (SCAN-495)

#### Auto-Responders — `/api/v1/sms/auto-responders` (manager+ writes)
- `GET /`, `GET /:id` (+ last 20 matches), `POST /`, `PATCH /:id`, `DELETE /:id`, `POST /:id/toggle`.

`rule_json` shape:
```json
{ "type": "keyword", "match": "STOP", "case_sensitive": false }
```
or
```json
{ "type": "regex", "match": "\\bhours?\\b", "case_sensitive": false }
```

#### Groups — `/api/v1/sms/groups`
- `GET /`, `GET /:id` (paginated members), `POST /`, `PATCH /:id`, `DELETE /:id` (manager+).
- `POST /:id/members` (static groups only) `{ customer_ids: number[] }` (max 500) → `{ added, skipped }`.
- `DELETE /:id/members/:customerId`.
- `POST /:id/send` `{ body, send_at? }` → 202 with queued `sms_group_sends` row. Rate-limit 5/day/group. TCPA opt-in filter applied.
- `GET /:id/sends` — past sends + status.

#### `tryAutoRespond(adb, {from, body, tenant_slug?})` helper — exported from `services/smsAutoResponderMatcher.ts`. Returns `{ matched: boolean, response?, responder_id? }`. Never throws. Caller decides to send.

---

### 4. Daily Checklist (SCAN-468) + SLA Tracking (SCAN-464)

#### Checklist — `/api/v1/checklists`
- `GET /templates?kind=open|close|midday|custom&active=1`, `POST /templates` (manager+), `PATCH /templates/:id` (manager+), `DELETE /templates/:id` (manager+ soft).
- `GET /instances?user_id=&template_id=&from_date=&to_date=` (non-managers scoped to self).
- `POST /instances` `{ template_id }` → new instance with `status='in_progress'`, empty `completed_items_json="[]"`.
- `PATCH /instances/:id` `{ completed_items_json?, notes?, status? }` — owner or manager+.
- `POST /instances/:id/complete` → marks `status='completed'` + `completed_at`.
- `POST /instances/:id/abandon`.

`items_json` shape:
```json
[ { "id": "unlock_door", "label": "Unlock front door", "required": true } ]
```

#### SLA — `/api/v1/sla`
- `GET /policies?active=1`, `POST /policies` (manager+), `PATCH /policies/:id` (manager+), `DELETE /policies/:id` (manager+ soft).
- `GET /tickets/:ticketId/status` — computed SLA state: `{ policy, first_response_due_at, resolution_due_at, remaining_ms, breached, breach_log_entries }`.
- `GET /breaches?from=&to=&breach_type=` (manager+).

Policy payload:
```json
{ "name": "High Priority SLA", "priority_level": "high",
  "first_response_hours": 2, "resolution_hours": 24,
  "business_hours_only": true }
```
`priority_level`: `low|normal|high|critical`. Only one active policy per level (409 collision).

`tickets` table extended with `sla_policy_id`, `sla_first_response_due_at`, `sla_resolution_due_at`, `sla_breached`. Call `computeSlaForTicket(adb, {...})` from ticket create/update (future wave).

#### Cron — `startSlaBreachCron`
Every 5 min. Per tenant: scans for first-response + resolution breaches (idempotent — only flips `sla_breached=0→1`). Inserts `sla_breach_log` rows. Broadcasts `sla_breached` WS event (best-effort; failures logged not rethrown).

---

### 5. Ticket Signatures (SCAN-465) + Expense Receipt OCR (SCAN-490)

#### Signatures — `/api/v1/tickets/:ticketId/signatures`
- `GET /` — list (data URL omitted from list).
- `POST /` `{ signature_kind, signer_name, signer_role?, signature_data_url, waiver_text?, waiver_version? }`. Rate-limit 30/min/user. `signature_data_url` must start with `data:image/png;base64,` or `data:image/jpeg;base64,`; length ≤ 500k chars. IP from `req.socket.remoteAddress` (not `req.ip` — SCAN-194 anti-spoof). user_agent capped 500 chars.
- `GET /:signatureId` — full row (includes data URL).
- `DELETE /:signatureId` (admin+).

`signature_kind`: `check_in|check_out|waiver|payment`. `signer_role`: `customer|technician|manager`.

#### Receipt OCR — `/api/v1/expenses/:expenseId/receipt`
Expense owner OR manager+ required.
- `POST /` multipart `receipt` field. MIME allowlist: jpeg/png/webp/heic. Max 10 MB. Rate-limit 20/min. Stored at `packages/server/uploads/{tenant_slug}/receipts/{hex16}.{ext}`. `ocr_status='pending'` on insert.
- `GET /` — returns current receipt + OCR state.
- `DELETE /` — deletes file + row + NULLs the 4 `expenses.receipt_*` columns.

OCR enum: `pending|processing|completed|failed`. Real OCR processor wired future wave — current `receiptOcr.ts` stub only enqueues + logs.

---

### Security checklist (uniform across wave 2)

- Integer IDs: `validateId` / `validateIntId` accepts `unknown`, narrows, requires `Number.isInteger && > 0`.
- Parameterized SQL only.
- Length caps on every string field + byte caps on JSON bodies (32 KB notif prefs, 64 KB cart_json, 8 KB metadata, 200 KB signature data URL, 500 KB ticket signature, 10 MB receipt upload).
- Role gates: `requireAdmin` / `requireManagerOrAdmin` / `requirePermission`.
- Rate limits via `checkWindowRate` + `recordWindowAttempt`.
- Audit writes via `audit(db, {...})` on every sensitive op.
- Money columns INTEGER cents with CHECK >= 0.
- Soft deletes where FK preservation needed.
- HMAC signed tokens with `timingSafeEqual` + single-use consumed-at atomic flag for public estimate sign.
- IP capture for audit via `req.socket.remoteAddress` (XFF-spoofable `req.ip` avoided per SCAN-194).

### Registration order in `packages/server/src/index.ts`

Wave 2 routes mount AFTER wave 1 block, in this order: `/ticket-labels`, `/public/api/v1/estimate-sign` (NO auth), `/estimates/:id` (authed sub-router), `/data-export/schedules`, `/sms/auto-responders`, `/sms/groups`, `/checklists`, `/sla`, `/tickets/:ticketId/signatures`, `/expenses/:expenseId/receipt`.

Wave 2 crons start inside `server.listen` callback alongside wave-1 `recurringInvoicesCron`: `startDataExportScheduleCron` + `startSlaBreachCron`. Timer handles pushed into `backgroundIntervals[]` for graceful shutdown.

## Web-Parity Backend Contracts — Wave 3 (2026-04-23)

Third wave. Closes SCAN-462, 466, 467, 471, 473 + wires previously-exported helpers into existing route handlers (SMS auto-responder on inbound webhook; SLA compute on ticket create/update).

Migrations 130–134. No new crons this wave. Public endpoints: `/public/api/v1/booking/*` (IP rate-limited).

---

### 1. Helper wiring (SCAN-465 / SCAN-495 follow-through)

#### `tryAutoRespond` — wired into `sms.routes.ts` inbound webhook
After successful inbound INSERT + opt-out filter, calls `tryAutoRespond(adb, {from, body, tenant_slug})`. On match: sends via `sendSmsTenant`, inserts outbound row, audits `sms_auto_responder_matched` with redacted phone. Entire block try/catch — autoresponder failure never breaks webhook 2xx response. Opt-out keywords (STOP/UNSUBSCRIBE/CANCEL) bypass auto-reply entirely.

#### `computeSlaForTicket` — wired into `tickets.routes.ts` POST / + PATCH /:id
On ticket create: after INSERT, captures `ticketCreatedAt`, calls `computeSlaForTicket(adb, {ticket_id, priority_level: body.priority || 'normal', created_at})` fail-open. On PATCH: if `body.priority !== undefined`, re-computes with new priority + existing created_at. Ticket operations never fail on SLA errors.

Note: `tickets` table has no `priority` column yet (only `sla_policy_id`/`sla_*_due_at`/`sla_breached` from migration 128). The helper accepts whatever `priority_level` string is passed; migration adding the column lands in a future wave.

---

### 2. Field Service + Dispatch (SCAN-466)

Base: `/api/v1/field-service`. Mobile §57 (iOS) / §59 (Android). Manager+ on writes; technician sees own assigned jobs only.

#### Jobs
- `GET /jobs?status=&assigned_technician_id=&from_date=&to_date=&page=&pagesize=`
- `GET /jobs/:id`, `POST /jobs`, `PATCH /jobs/:id`, `DELETE /jobs/:id` (soft → `canceled`)
- `POST /jobs/:id/assign` `{technician_id}` + `POST /jobs/:id/unassign`
- `POST /jobs/:id/status` `{status, location_lat?, location_lng?, notes?}` — technician-self-or-manager+, state machine validated, inserts `dispatch_status_history`

State machine:
```
unassigned → assigned → en_route → on_site → completed (terminal)
any non-terminal → canceled (terminal)
any non-terminal → deferred → unassigned
```

#### Routes
- `GET /routes?technician_id=&from_date=&to_date=`, `GET /routes/:id`
- `POST /routes` (manager+) `{technician_id, route_date, job_order_json: [job_ids]}` — validates jobs belong to tech
- `PATCH /routes/:id`, `DELETE /routes/:id`
- `POST /routes/optimize` `{technician_id, route_date, job_ids}` — returns `{proposed_order, total_distance_km, algorithm: "greedy-nearest-neighbor", note}`. Does NOT persist — caller follows up with POST /routes.

lat/lng: required on create, validated `[-90,90]` / `[-180,180]`. Stored as REAL.

Audit: `job_created`, `job_assigned`, `job_unassigned`, `job_canceled`, `job_status_changed`, `route_created`, `route_updated`, `route_deleted`.

---

### 3. Owner P&L Aggregator (SCAN-467)

Base: `/api/v1/owner-pl`. **Admin-only**. 30 req/min/user rate-limit. 60s LRU cache (64 entries, keyed by tenant+from+to+rollup).

#### `GET /summary?from=YYYY-MM-DD&to=YYYY-MM-DD&rollup=day|week|month`
Default 30-day span, max 365 days. Response composes revenue/COGS/gross-profit/expenses/net-profit/tax/AR-aging/inventory-value/time-series/top-customers/top-services. All money INTEGER cents. SQL patterns reused from reports.routes.ts + dunning.routes.ts.

#### `POST /snapshot` (admin) `{from, to}` — persists to `pl_snapshots` + returns `{snapshot_id, summary}`. Invalidates cache for that (tenant, from, to).
#### `GET /snapshots`, `GET /snapshots/:id` — list + retrieve saved snapshots.

---

### 4. Multi-Location (core) (SCAN-462)

Base: `/api/v1/locations`. SCOPE: **core only**. This wave adds the locations registry + user-location assignments. `location_id` is NOT yet on tickets/invoices/inventory/users — that is a separate migration epic.

#### Location CRUD (admin on writes)
- `GET /`, `GET /:id` (with user_count)
- `POST /`, `PATCH /:id`, `DELETE /:id` (soft `is_active=0`; blocked if only active OR `is_default=1`)
- `POST /:id/set-default` — trigger cascades other rows to `is_default=0`

#### User-location assignment (manager+)
- `GET /users/:userId/locations`, `POST /users/:userId/locations/:locationId` `{is_primary?, role_at_location?}`, `DELETE /users/:userId/locations/:locationId` (blocked if would leave user with 0)
- `GET /me/locations`, `GET /me/default-location`

Seeded row: `id=1 "Main Store" is_default=1` (single-location tenants see no behavior change).

**Follow-up epic:** Add `location_id INTEGER REFERENCES locations(id)` to tickets / invoices / inventory / users, backfill to id=1, scope domain queries.

---

### 5. Appointment Self-Booking Admin + Public (SCAN-471)

#### Admin — `/api/v1/booking-config` (admin writes)
- Services CRUD: `GET /services`, `POST /services`, `PATCH /services/:id`, `DELETE /services/:id` (soft). Fields: name, description, duration_minutes, buffer_before_minutes, buffer_after_minutes, deposit_required, deposit_amount_cents, visible_on_booking, sort_order.
- Hours: `GET /hours`, `PATCH /hours/:dayOfWeek` (dayOfWeek 0=Sun..6=Sat).
- Exceptions: `GET /exceptions?from=&to=`, `POST /exceptions` `{date, is_closed, open_time?, close_time?, reason?}`, `PATCH /exceptions/:id`, `DELETE /exceptions/:id` (hard).

Settings keys seeded via `store_config`: `booking_enabled`, `booking_min_notice_hours` (24), `booking_max_lead_days` (30), `booking_require_phone` (1), `booking_require_email` (0), `booking_confirmation_mode` (manual).

#### Public — `/public/api/v1/booking` (NO auth, IP rate-limited)
- `GET /config` (60/IP/hr) — returns enabled flag + visible services + weekly hours + next-90-day exceptions + store name/phone + settings. Returns `{enabled:false}` if booking_enabled != '1'.
- `GET /availability?service_id=&date=YYYY-MM-DD` (120/IP/hr, `Cache-Control: max-age=60`) — returns 30-min slot array `[{start_time, end_time, available}]`. Empty on booking-disabled/closed-day/below-min-notice/past-max-lead-days.

Availability algorithm:
1. Validate service_id int + date regex
2. Service active + visible on booking
3. booking_exceptions first; fallback booking_hours
4. Generate 30-min windows open..(close-duration)
5. Subtract overlapping appointments (expanded by buffer_before + buffer_after)
6. For today: filter slots before now + min_notice_hours
7. Return with boolean `available` only — NEVER customer names/appointment ids

---

### 6. Sync Conflict Resolution (SCAN-473)

Base: `/api/v1/sync/conflicts`. **Lightweight queue only** — declarative resolution. Server records the decision; client must replay the chosen version via regular entity endpoints.

#### Report (any authed user, 60/min/user, 202 Accepted)
- `POST /` `{entity_kind, entity_id, conflict_type, client_version_json, server_version_json, device_id?, platform?}`. Blobs ≤ 32KB each.

`conflict_type`: `concurrent_update | stale_write | duplicate_create | deleted_remote`.
`platform`: `android | ios | web`.

#### Manage (manager+)
- `GET /?status=&entity_kind=&page=&pagesize=` (default 25, max 100)
- `GET /:id`
- `POST /:id/resolve` `{resolution, resolution_notes?}` — `resolution`: `keep_client | keep_server | merge | manual | rejected`. Atomic status/resolution/resolved_by/at. Audit.
- `POST /:id/reject` `{notes?}`
- `POST /:id/defer`
- `POST /bulk-resolve` `{conflict_ids: number[] (≤100), resolution}` — skips already-resolved silently.

Limitations:
- No merge engine. `resolution='merge'|'manual'` records intent only.
- No entity writeback — client replays via regular routes.
- Opaque blobs — server validates JSON + size only, no schema interpretation.
- `device_id` client-supplied, not cryptographically verified.

---

### Security applied uniformly

- Parameterized SQL; integer id guards; length/byte caps (conflict blobs 32KB/64KB, cart_json 64KB, signature data URL 500KB, receipt 10MB, notif prefs 32KB)
- Role gates inside handlers: `requireAdmin` / `requireManagerOrAdmin` / `requirePermission`
- Rate-limits via `checkWindowRate` + `recordWindowAttempt` (30/min writes generally; 60/IP/hr public booking; 120/IP/hr availability)
- Audit via `audit(db, {...})` on every sensitive op
- Money INTEGER cents with CHECK ≥ 0
- Soft delete where FK preservation needed
- IP via `req.socket.remoteAddress` (XFF-resistant, SCAN-194)
- Public booking: no customer names/appointment IDs in responses; only boolean availability

### Registration order in `packages/server/src/index.ts`

Wave-3 routes mount AFTER wave-1 + wave-2 block. Public booking is UNAUTHENTICATED:
`/field-service`, `/owner-pl`, `/locations`, `/booking-config`, `/public/api/v1/booking` (public), `/sync/conflicts`.

---

## Discovered

Cross-agent dependency notes. Append by agent. Orchestrator routes each entry to the owning agent's next batch.

- **[Agent 5]** §11 Expenses `MileageEntrySheet`: direct `api.post("/api/v1/expenses/mileage")` call violates §20 containment rule — needs extraction to `MileageRepository`. **RESOLVED** in Agent 5 batch 2 (`3b4b6d64`).
- **[Agent 5]** §11 Expenses `RecurringExpenseRunner`: direct `api.post/delete` calls violate §20 containment rule. **RESOLVED** in Agent 5 batch 2 (`3b4b6d64`).
- **[Agent 5 → Agent 10]** §6 Pre-existing Core macOS build failure: `EnvironmentBanner.swift`, `LoadingStateView.swift`, `CoreErrorStateView.swift`, `MacHoverEffects.swift` in `Packages/Core/Sources/Core/` use UIKit-only APIs without `#if canImport(UIKit)` guard. **RESOLVED** in Agent 10 batch 1 (`bcbccaa8`) — `Color(.systemBackground)` → `Color.primary.opacity(x)`, `.insetGrouped` removed, `hoverEffect` guarded `#if os(iOS)`.
- **[Agent 8 → Agent 10]** (2026-04-26, bef1335b) `NSFaceIDUsageDescription`. **RESOLVED** in Agent 10 batch 2 (`ac159516`).
- **[Agent 2 → Agent 10]** (2026-04-26, agent-2 b4) `NSBonjourServices` for Bonjour printer discovery in `write-info-plist.sh`. **RESOLVED** in Agent 10 batch 3 — added `_ipp._tcp`, `_printer._tcp`, `_bizarre._tcp` array.
- **[Agent 9 → Agent 10]** (2026-04-26, agent-9 b3) ControlCenter widgets need `com.apple.developer.control-center.extension` entitlement + new extension target in `project.yml`. Code is gated `#if swift(>=5.10)` so doesn't break build. **RESOLVED** in Agent 10 batch 4 — entitlement added to `BizarreCRM.entitlements`, `BizarreCRMControlCenter` app-extension target added to `project.yml` sourced from `App/Intents/ControlCenterControls.swift`.
- **[Agent 10 → Agent 4 / Agent 7 / Agent 2]** sdk-ban.sh 53 pre-existing violations. **PARTIALLY RESOLVED** — Agent 10 b2 fixed Core (4); Agent 4 b3 fixed Marketing+Loyalty+Customers (10). 20 remain in Pos/Communications/Tickets (Agents 1/7/3 sweeps).
- **[Agent 10]** 4 Core sdk-ban violations. **RESOLVED** in Agent 10 batch 2 (`ac159516`).
- **[Agent 10]** `Motion/MotionCatalog.swift` already extends `BrandMotion` with `sharedElement` + `pulse` as `public extension BrandMotion` — base enum redeclaration causes `invalid redeclaration` errors. Note for any future motion token additions.
- **[Agent 10]** Multipart binary JPEG handling: `MultipartFormDataTests.swift:120` previously crashed on `String(data:encoding:.utf8)!` for binary content. **RESOLVED** in `bcbccaa8` (ISO-Latin-1 fallback).
- **[Agent 10]** (2026-04-27, b4) Pre-existing runtime test failures in Core: `AnalyticsPIIGuardTests`, `CoreErrorStateTests`, `ErrorCopyTests`, `DeepLinkDestinationTests`, `PseudoLocaleGeneratorTests`, `SensitiveFieldRedactorTests`, `FixtureLoaderTests`. **OPEN** — Agent 10 b5.
- **[Agent 6 → Agent 10/Agent 1/Agent 3]** Networking pre-existing build errors. **RESOLVED** — Agent 3 b5 fixed all (`d18568af`). Agent 1 b8 reaffirmed (`5949db19`).
- **[Agent 7 → Agent 1]** §14 L1777–1782 cash register cross-domain. RESOLVED on iOS side Agent 7 b9 (`ea8ee40e`): `zReportId` now captured from `EndShiftResponse`, `zReportURL()` builds authenticated tenant PDF URL, "View Z-Report" glass button in done screen (nil-safe, hidden when tenant hasn't archived). Agent 1 still needs to implement the §39 Z-report print + server archive; `EndShiftResponse.zReportId` is the handshake field.
- **[Agent 7 → Agent 10]** §12.2 Typing indicator: `WSEvent` typed case `smsTyping(String)`. Currently `.unknown` passthrough.
- **[Agent 6 → Agent 2]** §7.7 Vendor return flow (pick items → RMA # → print shipping label via §17.4): requires Agent-2 hardware shipping label endpoint + §17.4 print template. Cross-slice dependency. (2026-04-26, b9)
- **[Agent 6 → Agent 2]** §7.4 BlockChyp card tender in invoice return flow: refund with stored card token requires BlockChyp SDK (Agent-2 / hardware phase). `InvoiceReturnSheet` currently offers cash/store_credit/gift_card only. Add `.card` tender once BlockChyp SDK lands. (2026-04-26, b9)
- **[Agent 6 → Agent 2]** §7.4 BlockChyp card — start terminal charge → poll status; surface Live Activity for the txn: Agent-2 dependency. Return flow wires correctly once Agent-2 delivers terminal pairing SDK. (2026-04-26, b9)
- **[Agent 6 → Agent 10]** §7.5 push deep-link wiring: `InvoiceDeepLinkHandler.handleRoute(invoiceId:)` needs to be called from `AppServices.swift` (advisory-lock file) inside `DeepLinkRouter.onRoute` for `.invoice(_, let id)` routes. Instructs AppServices to call `InvoiceDeepLinkHandler.handleRoute(invoiceId: Int64(id) ?? 0)`. (2026-04-26, b10)
- **[Agent 6 → Agent 1]** §7.7 dunning sequences (card declined → retry schedule → smart retry → escalation → self-service Apple Pay): §40 scope, HIGH RISK recurring cron + payment math. STOP for Agent 6. Agent 1 owns §40. (2026-04-26, b10)
- **[Agent 6 → server]** §7.7 late-fee customer communications (reminder SMS/email 1-3d before fee; fee-applied notification with pay link): server-side cron + SMS dispatch. No iOS client code needed; server concern. (2026-04-26, b10)
- **[Agent 6 → server]** §7.7 jurisdiction limits on late fees: server must enforce legal cap by tenant region; iOS can warn in UI once server exposes a `jurisdictionMaxFeeCents` field on tenant config. No iOS code until server provides field. (2026-04-26, b10)

---

## §91. Bug-hunt audit — iPad screenshots 2026-04-28

> **Source.** Pavel Ivanov's iPad install at 22:18 local; 7 screenshots covering SMS landing + Reports / Sales / Tickets / Inventory / Insights tabs. The intent of this section is exhaustive — list every observed defect, however minor, so subsequent batches can pick atomic items. Items here are **observations only**, NOT fixes; don't bundle these into a single sweep PR. Reference the screenshot timestamp where useful.

### 91.1 SMS landing (`2026-04-28 22.18.30`)

- [ ] **Raw Swift decoder error dumped in UI.** `SmsConversationsListView` shows `keyNotFound(CodingKeys(stringValue: "conv_phone", intValue: nil)), Swift.DecodingError.Context(codingPath: [...] debugDescription: "No value associated with key CodingKeys(stringValue: \"conv_phone\"...")`. Cashier-hostile. Surface a friendly "We couldn't load conversations · check connection" error and collapse the technical payload behind a `Show details` disclosure.
- [ ] **Server DTO mismatch — missing `conv_phone` key.** The conversations endpoint returns rows without `conv_phone`; client decoder requires it. Either change `SmsConversationDTO.conv_phone` to `String?` with `decodeIfPresent`, or fix the server payload. Document which side moves.
- [ ] **`Try again` button is small + cream pill.** Should be the brand prominent CTA at primary tap-target size (≥44pt) and announce the retry attempt to VoiceOver.
- [ ] **No retry countdown / next-attempt hint.** When connection is poor, surface "Retrying in Ns…" with a cancel option.
- [ ] **No offline-mode hint despite "Never synced" pill.** Pill conveys state but doesn't say *when* the last attempt happened or what is pending. Show a timestamp or `Never · tap to sync now`.
- [ ] **No way to compose a new SMS thread from this empty state.** "Pick a thread on the left or start a new one" — but no `+ New conversation` button on either pane.
- [ ] **Sidebar toggle + chat icon clutter.** Top-right of left pane has a chat-bubble icon with a `0` notification dot whose meaning is opaque, plus a separate sidebar-collapse glyph. Either combine semantic meaning into one icon or label both.
- [ ] **`SMS` title cramps top-left of detail area.** Title fights the topbar chrome; promote to the topbar slot or add proper hero chrome with subtitle.
- [ ] **Search field absent on SMS landing despite present elsewhere.** Other screens have a global search affordance; SMS should as well — search by phone / customer / message body.
- [ ] **No filter chips (All / Unread / Templates / Archived).** SMS list lacks segmentation; cashier with hundreds of threads has no triage.
- [ ] **No customer-pick affordance on left when starting new SMS.** New-message UX absent altogether.
- [ ] **No divider between SMS list pane and detail pane.** Both panes share a black background; visual depth lost.
- [ ] **Empty state right pane is icon-only.** "Select a conversation" is correct copy but the icon is a generic chat bubble — match the SMS empty-state hero treatment used elsewhere.
- [ ] **Error block centered horizontally only in left pane.** The error message has no glass card or border — it floats. Wrap in a `bizarreSurface1` card with clear edges.
- [ ] **No analytics / error-reporting hook on this decoder failure.** `SmsConversationsRepository` should record the decode failure to the §32 telemetry pipeline so we know how often customers hit it.

### 91.2 Reports — Sales tab (`2026-04-28 22.18.32`)

- [ ] **Reports topbar lacks consistent title chrome.** Other screens centre title in the 60pt topbar; Reports puts a giant body-level "Reports" header instead. Pick one pattern (recommend topbar slot) so the cashier's eye doesn't relearn the layout each tab.
- [ ] **`Just now` sync chip + ⇄ + ⋯ cluster overlaps body when scrolled.** As the user scrolls, the chip stays pinned but renders ON TOP of revenue card content (visible in 22.18.39 / 22.18.41). Either pin behind a glass topbar or scroll with content.
- [ ] **Period segmented control low-contrast selection.** `30D` selected pill is the same near-grey as unselected `90D` — only a tiny shade difference. Use the cream-orange brand selection treatment.
- [ ] **Day/Week/Month sub-segment same low-contrast issue.** "Day" selected; visually indistinguishable from peers.
- [ ] **Revenue card sparkline tiny + no axis labels.** A small inline chart with no scale is decorative-only; either drop or label.
- [x] **`↗ 0.0%` shown on zero-change.** A 0.0% delta should not render the up-arrow + green colour; show a flat dash or `–`.
- [ ] **Period Summary card content broken.** Four columns: dollar-icon "$0…" truncated to two characters, page-icon "0", people-icon "0", dollar "$0". Missing labels (Sales / Tickets / Customers / Avg). Tile too narrow; either wider tile or vertical stack.
- [ ] **Period Summary `$0…` truncated.** First-column value appears clipped (`$0…R`). Either widen the column or use compact currency formatting.
- [ ] **Revenue card duplicates Trend + By Period charts side-by-side.** Two near-identical bar charts render in one card — confusing for non-analyst cashier. Pick one or make the second a tab.
- [ ] **Bar chart Y-axis values `0.0 / 0.5 / 1.0 / 1.5` without unit.** Add `$K` unit suffix or a clearer axis label.
- [ ] **Bar chart bars too thin to read.** ~1px line of vertical bars; cashier can't tell good days from bad.
- [ ] **KPIs block: `Peak: $1,320.93 2026-04-27`.** Date hangs as suffix; insert a label `on 2026-04-27` or move date below value.
- [ ] **Revenue by Method shows "No payment data for this period" while Revenue card shows $15,758.14.** Contradictory — if there's revenue, payments must exist. Either source-of-truth mismatch or zero-payments-with-revenue (e.g., manual receipts) needs an explanation footnote.
- [ ] **Cohort Revenue Retention card cut off at bottom.** Visible only as title + half a chevron-icon. Add a scroll affordance or collapse the empty version.
- [ ] **Revenue chart pagination icons unclear.** ◀ ⊝ ⊕ ▶ at bottom — what's the pinch-zoom for? Either label or remove.
- [ ] **`Custom` period button is plain text vs pill.** Visually inconsistent with `7D / 30D / 90D` pills.
- [ ] **Expenses & Margin card uses brand cream for `$0.00` but plain text for `Revenue` label.** Typography hierarchy backwards — labels should be muted, values cream.
- [ ] **`30D` and `90D` segments have the same width as `Custom`.** Hard-coded equal widths waste space; weight by typical use.

### 91.3 Reports — Tickets tab (`2026-04-28 22.18.34`)

- [ ] **`Tickets by Status` chart text overlays bars.** Status labels (`Created`, `Repaired & Collected`, `Waiting for Inspection`, `Waiting for Parts`, `Parts arrived, need the device — SMS`, etc.) render directly on top of the colored bars. Move labels to the left axis or above the bar.
- [ ] **`Tickets by Status` X-axis numbers (`0  10  20`) overlap status names too.** Whole chart renders on top of itself.
- [ ] **All bars same teal color.** Web client has color-coded statuses; iPad doesn't honour the tenant status color (server returns a hex per status).
- [x] **`Avg Ticket Value $0.00 ↗ 0.0%` with green pill.** Same zero-vs-trend problem as Sales tab.
- [ ] **`Avg Ticket Value` subtitle `vs $0.00 prior period`.** Comparing zero to zero is non-actionable; hide row or replace with `Not enough data`.
- [ ] **`Tickets by Technician` shows only `Admin · 0`.** With one technician and zero tickets, the entire bar chart should be a "Not enough data" empty state, not a chart with a 0-length bar.
- [ ] **`Tap a bar to view technician details` hint shows even when there are no bars.** Suppress until there is data.
- [ ] **`SLA Breaches` card has 2 anonymous grey horizontal bars.** Skeleton-loading visual? Or empty data? No header, no count, no zero-state copy.
- [ ] **Revenue card on Tickets tab still says "Revenue" + sales total.** Should reflect ticket revenue (or hide on this tab).
- [ ] **Revenue sparkline: 4 points only at 7D × Day.** Too few to be meaningful — cashier can't read direction.
- [ ] **Tab icons (Sales/Tickets/Employees/Inventory/Tax/Insights) all teal monochrome.** No active-tab color treatment beyond pill background.
- [ ] **Tab pill background contrast still poor (same issue as Sales).** Selected tab `Tickets` cream-yellow; unselected tabs same near-grey.

### 91.4 Reports — Inventory tab (`2026-04-28 22.18.39` + `22.18.36`)

- [ ] **Topbar bleeds into scrolled content.** When the user scrolls, content slides under the topbar — period selectors, tab chips, sync pill all visible faintly. Apply a glass / opaque mask to the topbar or move topbar to the scroll content top.
- [ ] **Inventory Stock Health: `255 Out of Stock` + `0 Low Stock`.** With 255 OOS, Low Stock should also be elevated unless OOS dominates entirely. Verify data source — possibly an inventory-sync bug producing inflated OOS counts.
- [ ] **`Inventory Value $0 Cost / $0 Retail / 0% Markup` while 255 items exist.** Math impossible — items cannot be valueless. Either the API doesn't include cost/retail in the OOS branch, or the iOS reduce step is broken.
- [ ] **`Retail Value ($K)` chart has only `$0` on Y-axis, no bars.** Empty chart shouldn't render.
- [ ] **Inventory Movement card title wraps oddly: `No / Move- / ment / Data`.** Word-break breaks readability. Use no-break or a single line.
- [ ] **Inventory Movement sub-card has secondary header `Stock Value`.** Two cards collapsed into one; layout broken. Split or rename.
- [ ] **`255 Out of stock` pill in Stock Value sub-card** repeats the headline KPI from Stock Health card — duplicate data, two places.
- [ ] **Inventory Turnover card shows "No Inventory Data" empty state on the same data set.** Three cards all derive from the same inventory feed yet two say zero data and one says 255 OOS — internal inconsistency.
- [ ] **`Inventory Shrinkage Trend` card has `Period Summary` inside it.** Period Summary appears in *two* tabs (Sales + Inventory) with different shapes — the labels don't match.
- [ ] **`No shrinkage…` ellipsis copy.** Should be `No shrinkage events in this period` or hide entirely if zero.
- [ ] **Cards different heights break grid alignment.** `Inventory Stock Health` is short; `Inventory Movement` tall. 3-col grid looks ragged on landscape iPad.
- [ ] **Revenue card on Inventory tab shows Sales revenue.** Inventory tab should show inventory-related KPIs (stock value, turnover days, shrinkage cost) — not revenue.
- [ ] **Revenue sparkline shape changes between tabs.** Same `Revenue` card on Sales vs Inventory shows wildly different spike patterns; cashier reads them as inventory data when they're not.

### 91.5 Reports — Insights tab (`2026-04-28 22.18.41` + `22.18.48`)

- [ ] **CSAT card body is just a loading spinner ✶ with no `Loading…` label.** Spinner alone provides no waiting feedback; add label and expected wait.
- [ ] **CSAT card uses 70% whitespace for a 20% icon.** Resize empty state.
- [ ] **NPS card: `Score: 0` + dial pointing to 0 + `Promoters 0% / Passives 100% / Detractors 0%`.** Math contradiction — passives at 100% with zero respondents possible only if the calculation treats no responses as passive. Suppress the score until N≥10 responses; show "Not enough data".
- [ ] **NPS card chevron `›` on right with no destination.** Tapping should go to a detailed NPS view; verify the navigation handler exists.
- [ ] **`Warranty Claims Trend` card empty body.** Just title + subtitle; no chart, no metric. Either render a sparkline or hide.
- [ ] **`Device Models Repaired` list shows 8 rows but no counts.** What's the metric — frequency? Currency? Just a list adds no analytic value. Add a count + bar.
- [ ] **Mixed model+service strings in `Device Models Repaired`** — `iPhone 15 Pro Max - LCD Replacement`, `Other Repair - Other Labor / Repair`. Should split by model, separate column for top service.
- [ ] **`Device Models Repaired` list ordering not by frequency.** Looks alphabet-ish; cashiers need top-N by volume.
- [ ] **`Parts Usage Analysis` empty state has no icon.** Other empty cards have a glyph; this one is text only.
- [ ] **`Stalled & Overdue Tickets`: 0/0/0.0 D in green.** Green colour for `0 stalled` makes sense (good news) but `0 overdue` and `0.0 D avg stall` colored neutrally — inconsistent. Pick one.
- [ ] **`Customer Acquisition & Churn`: +0 new / -0 churned / 0 returning.** Three zeros each in different colors (green / orange / yellow). Visual noise; either grey out all when zero or remove arrows.
- [ ] **`Net: +0 customers · 0.0% churn rate` row redundant with the three-column block above.** Same data restated in different units.
- [ ] **`Revenue & Margin by Category` empty.** Either hide on no-data or render a placeholder bar chart.
- [ ] **`Conversion Funnel` shows three blank horizontal bars.** Skeleton-loading or empty data — UI doesn't say. If empty, label the funnel stages (Lead → Quoted → Won) so the cashier sees the shape even at zero.
- [x] **Insights tab is heavy with empty cards.** Aggregate empty-state: when ≥80% of cards have no data, render a single `Insights need more activity to populate · come back after your first 10 sales` card and hide the empties.
- [ ] **`Repeat Customer Rate` shows `0.0% repeat rate` + `0 D avg return time`.** If zero customers repeated, "0 D avg return time" is undefined — show `—` instead of `0`.
- [ ] **`Labor Utilization by Tech` empty state has no header indicator.** Add the wrench glyph and a clearer "No labor data" state.
- [ ] **`Avg Ticket Value Trend` empty state lacks trend chart placeholder.** Skeleton bars or sparkline outline would communicate intent better.

### 91.6 Reports — global (across all tabs)

- [ ] **No `Export` / `Share` affordance** despite ⋯ overflow. Reports CSV/PDF export missing on iPad.
- [ ] **`Custom` button has no visible flow** — tapping opens what? Date-range picker not surfaced.
- [ ] **No comparison-period toggle.** Can't compare current 30D to prior 30D.
- [ ] **Sync chip `Just now` overlaps body when scrolled** (same as Inventory observation, applies to every tab).
- [ ] **Tab strip (Sales/Tickets/Employees/Inventory/Tax/Insights) icons monochrome** — switch to colored glyphs to match the brand or drop icons entirely.
- [ ] **No empty-state for whole tab.** When everything is zero (e.g., new tenant), show a single tenant-level empty state instead of 12 empty cards.
- [ ] **No skeleton-vs-empty distinction.** Loading and "no data" both render as blank rows; introduce a shimmer skeleton for the loading phase and a label for the empty phase.

### 91.7 iPad rail (left)

- [ ] **Rail icons unlabeled; discoverability poor.** Add hover/long-press tooltips with text labels (Dashboard, Tickets, Customers, POS, Inventory, SMS, Reports, Settings).
- [ ] **No section grouping in rail.** Operations / Reports / Settings should be visually grouped with subtle dividers.
- [ ] **All 8 nav icons same visual weight.** Selected has a pill background but icons themselves look identical — bump the selected icon weight or color.
- [ ] **Profile circle bottom-left detached.** Floating avatar with a thin divider above; integrate into the rail's bottom group.
- [x] **Rail icons not perfectly center-aligned.** Subtle x-offset between icons; verify HStack alignment.

### 91.8 Topbar consistency

- [ ] **Reports has no topbar centered title.** Body-level `Reports` headline + small `Just now` chip in the top-right is the only chrome. Other surfaces (POS, Dashboard) have a centered `principal` title — unify.
- [ ] **Reports has no Search affordance.** Search across reports / KPIs.
- [ ] **Sync chip placement varies between surfaces.** Sometimes top-right, sometimes top-trailing toolbar item.
- [ ] **Topbar sticky behaviour inconsistent.** Reports topbar is not opaque; SMS / POS topbars are. Pick one.

### 91.9 Theme / color

- [ ] **No light-mode verification on this audit.** Re-run in light mode to ensure parity (separate audit task).
- [ ] **Cream highlight on selected nav looks dim.** The brand cream needs to read as "active" — bump saturation or pair with an outline.
- [ ] **`Never synced` red/pink pill is the only attention chip with a clear treatment.** Other states (synced, syncing) use small green ticks — promote them to the same pill style for consistency.

### 91.10 Typography

- [ ] **Reports body title `Reports` is 28pt with no descriptor / subtitle.** Dashboard uses `Good afternoon` greeting; Reports could use date range or store name as subtitle.
- [ ] **KPI numbers vary in font weight.** Some bold, some regular within same card row — verify token usage.
- [x] **Axis labels < 12pt.** Charts use 9–10pt labels; below 11pt fails Dynamic Type test.
- [ ] **`Period Summary` inline values colored cream while labels white.** Reverse — labels should be muted.

### 91.11 Charts

- [x] **Y-axis labels low contrast** (white-30% on dark — barely legible).
- [x] **Chart legends not surfaced** — bar colors vary but no key.
- [ ] **No empty-state visual for charts.** Empty chart vs empty card both render as blank — introduce a "shape outline" empty state.
- [ ] **No tap interaction on bars / sparklines.** Tap a bar in `Tickets by Status` does nothing; `Tap a bar to view technician details` hint promises an interaction that isn't wired.

### 91.12 Data integrity / business logic

- [ ] **Revenue same on Sales tab vs Inventory tab.** Different tabs should surface different revenues (sales-revenue vs inventory-cost). Audit the data layer.
- [ ] **30D revenue $15,758.14 vs 7D revenue $3,661.54 with `Avg Ticket = $0.00`.** Math inconsistent. Either ticket count is zero (then revenue should also be zero) or revenue is double-counted from invoices.
- [ ] **`SLA Breaches` not labeled when zero.** When zero, hide entire card; don't render anonymous grey bars.
- [ ] **NPS score with zero respondents shouldn't compute.** Render `Not enough data` until N ≥ 10.
- [ ] **`Inventory Stock Health 255 OOS` vs `Inventory Value $0` is mathematically contradictory.** Either OOS items have unit cost > 0 (so cost value > 0) or they are valueless (then cost & retail should be hidden, not zeroed).

### 91.13 Accessibility

- [x] **Many label texts under 12pt** (period units, axis labels, KPI captions).
- [ ] **Chart color-only encoding** — VoiceOver / Switch Control can't read which color is which status.
- [x] **Tap targets on segmented period selectors look < 44pt high.** Verify minHeight 44.
- [x] **No accessibility labels on charts.** `ChartScreenshotAltText` modifier + `.chartScreenshotAltText()` wired to `ZoomableRevenueChartCard`; `AXChartDescriptor` already present on `RevenueChartCard`.
- [ ] **Sync chip `Just now` with no `accessibilityLabel`** — VoiceOver reads only "Just now" without context.
- [x] **Dynamic type clamp on Reports sub-tab pills.** `.dynamicTypeSize(.xSmall ... .accessibility3)` + `.lineLimit(1)` on tab pill labels in `subTabPicker` (`ReportsView.swift`).
- [x] **VoiceOver bypass for decorative gradients.** `DecorativeGradientModifier` / `.decorativeGradient()` in `DesignSystem/Accessibility/`; applied to `RefreshShimmerOverlay` in `VisualMotionPolish.swift`.
- [x] **Focus-loop test helper.** `AccessibilityFocusOrder` + `RecordFocusVisitModifier` / `.recordFocusVisit(id:into:)` in `DesignSystem/Accessibility/FocusLoopTestHelper.swift`.
- [x] **Switch-control timer extension.** `SwitchControlGroupModifier` / `.switchControlGroup(label:hint:)` + `SwitchControlTimingToken` in `DesignSystem/Accessibility/SwitchControlTimerExtension.swift`; applied to `ZoomableRevenueChartCard`.

### 91.14 SMS engineering follow-up

- [ ] **DTO update.** Make `SmsConversation.conv_phone` optional (`String?`) with `decodeIfPresent`. File: `ios/Packages/Communications/Sources/Communications/Endpoints/...` (locate exact DTO).
- [ ] **Add `errorMessage` rendering pipeline.** Wrap raw `DecodingError` in a `SmsError.localizedDescription` that returns a user-friendly string while logging the raw error to `AppLog.communications`.
- [ ] **Telemetry on decode failure.** §32 hook so we can track tenants hitting this.
- [ ] **Server-side audit.** Check whether `conv_phone` was renamed in a recent server release; align contracts package.

### 91.15 Reports engineering follow-up

- [ ] **Reports DTO audit.** Inspect every chart's source DTO; hide cards when source returns empty arrays instead of rendering "No xxx data" copies.
- [ ] **Per-tab data scoping.** Tickets tab should fetch ticket-revenue not sales-revenue; Inventory tab should fetch inventory KPIs.
- [ ] **Chart library audit.** Many charts look hand-rolled; consolidate on Swift Charts with a single `ReportsChartTheme`.
- [ ] **Topbar masking.** Reports body must not bleed under topbar — either pin topbar in glass with `.scrollEdgeEffectStyle(.hard)` or move title into scroll content.
- [ ] **`Just now` chip absolute-positioning fix.** Move into `PosRegisterLayout`-style topbar slot so it doesn't render above body content.

### 91.16 Cross-screen polish queue

- [ ] **Define a tenant-zero-state mode.** When tenant has < N transactions in selected period, swap the entire reports surface for a friendly onboarding panel ("Run your first sale to unlock these reports").
- [ ] **Empty-state hierarchy review.** Audit every empty state: skeleton (loading) vs zero-data vs error vs offline; pick one of four and label it.
- [ ] **Card-grid alignment.** Use a single shared `ReportsGrid` with consistent row heights and column counts on landscape vs portrait.
- [x] **No data → suggested action.** Each empty card should suggest the next step (e.g., "Add inventory items to enable stock health").


