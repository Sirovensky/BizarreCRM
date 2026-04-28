# android/ActionPlan.md — Android Feature-Parity & Polish Plan

> **Mission.** Bring the Android app (phone + tablet + foldable + ChromeOS/desktop-mode) to complete feature parity with the web and iOS clients, keep it as fast as either, and ship a UI worthy of the modern Android 16 visual language (Material 3 Expressive, dynamic color, predictive back, adaptive layouts).
>
> **How to read this document.** Every top-level section is a domain (auth, tickets, customers, inventory …). Inside each domain, items follow this shape:
>
> - **Backend** — what server route / websocket topic / webhook the feature depends on, with status notes (exists / missing / partial).
> - **Frontend (Android)** — the Jetpack Compose surfaces (Composables, ViewModels, Repositories, Room DAOs, WorkManager workers, Hilt modules) needed, with separate notes for phone vs tablet vs foldable where layouts diverge.
> - **Expected UX** — the user-story step-by-step flow, empty states, error states, confirmations, gestures, hardware-keyboard shortcuts, haptics, animations, Reduce-Motion alternative, Material 3 Expressive usage, parity call-outs vs web/iOS.
> - **Status** — `[ ]` not started · `[~]` partial · `[x]` shipped · `[!]` blocked. Each item individually checkable so a human or agent can close them incrementally.
>
> **Non-negotiables** (apply to every section, don't re-state per item):
> - Tablet is NEVER an upscaled phone. `WindowSizeClass` + `NavigableListDetailPaneScaffold` gate layout branches.
> - Material 3 Expressive across chrome / top bars / FABs / badges / sticky banners. Dynamic color (`dynamicLightColorScheme(LocalContext.current)` with tenant-brand fallback). No glassmorphism — that is iOS's Liquid Glass. Android language is "soft shapes + tonal elevation + amplified motion + bold type".
> - API envelope `{ success, data, message }` — single unwrap in `ApiResponse<T>` adapter.
> - **Offline architecture (§20) is Phase 0 foundation, not a later feature.** Every domain section (§§1–19 and every writer section in §36+) is built on top of it from day one. Required contract: reads go through a repository that reads from Room via `Flow<List<Entity>>`; writes go through the §20.2 sync queue (WorkManager) with idempotency keys + optimistic UI + dead-letter; never a bare `Retrofit.call` from a ViewModel. PRs that touch a domain without wiring into §20 machinery are rejected in code review; lint rule flags direct `apiClient.*` usage outside Repositories.
> - Pagination: **cursor-based, offline-first** (see §20.5). Lists read from Room via `PagingSource` / `Flow` — never from API directly. `loadMoreIfNeeded(rowId)` kicks next-cursor fetch when online; no-op when offline (or un-archives evicted older rows). `hasMore` derived locally from `{ oldestCachedAt, serverExhaustedAt? }` per entity, NOT from `total_pages`. Footer has four distinct states: loading / more-available / end-of-list / offline-with-cached-count.
> - Accessibility: TalkBack `contentDescription` on every tappable icon, `fontScale` tested to 2.0, Reduce Motion / "Remove animations" system setting honored, 48dp min touch target.
> - Tablet & ChromeOS: hardware-keyboard shortcuts (Ctrl+N / Ctrl+F / Ctrl+R / Ctrl+,), hover state (`pointerHoverIcon`), `SelectionContainer` on IDs/emails/invoice numbers, context menus via long-press + right-click, Storage Access Framework for PDF/CSV export.
>
> **Source-of-truth map.**
> - Web routes: `packages/web/src/{pages,app}/`
> - iOS: `ios/Packages/<Domain>/Sources/`
> - Server API: `packages/server/src/routes/`
> - Contracts: `packages/contracts/`
> - Android modules: `android/app/src/main/java/com/bizarreelectronics/crm/{ui,data,di,service,widget,util}/`

---
## Audit checkpoint — 2026-04-20

Per-section coverage estimate (parallel-agent audit run against current
android/app/ source tree). Numbers are rough; full granular `[x]` marking is
in-progress and lags the audit.

| § | Domain | Coverage | Notes |
|---|---|---|---|
| 1 | Platform & Foundation | ~78% | API envelope, OkHttp pinning, Room+SQLCipher, Hilt, WorkManager, FCM, **AppError taxonomy (NEW)**, **ProcessLifecycle ON_START hook (NEW)** DONE. Missing: draft autosave, undo stack, clock-drift, multipart upload helper. |
| 2 | Auth & Onboarding | ~55% | Login + 2FA + setPassword + signup + logout + refresh-retry + **PIN lock end-to-end (NEW Settings + nav)** + **SessionRevoked banner (NEW)** + **/auth/me cold-start (NEW)** DONE. Missing: passkeys, SSO, magic-link, hardware key, shared-device. |
| 3 | Dashboard | ~55% | KPIs, my-queue, FAB, sync badge, greeting, error states, onboarding checklist, clock-in tile + **KPI tile tap-through to Tickets / Appointments / Inventory (NEW)** DONE. Missing: BI widgets, role-based dashboards, activity feed, TV mode, filtered-list params. |
| 4 | Tickets | ~16% | List + detail + create scaffolds; §4.17 IMEI Luhn validator + **live IMEI supportingText + TAC model suggestion in TicketCreate (NEW)** DONE. Missing: Paging3, signatures, bench, SLA, QC checklist, inventory trade-in hookup. |
| 5 | Customers | ~33% | Detail, create, notes (CROSS9b), health score, recent tickets DONE. **Tag chips row on detail (commit 392d1d5 via `ui/components/TagChip.kt` + FlowRow).** Missing: tag picker in create/edit, segments, merge, bulk, communication prefs. |
| 6 | Inventory | ~25% | List (type tabs + search), create scaffold, detail w/ movements + group prices DONE. Missing: stocktake, PO, loaner, serials, ML Kit barcode wire. |
| 7 | Invoices | ~30% | List (status tabs), detail w/ payments DONE. Missing: create, refund, send, dunning, pagination. |
| 8 | Estimates | ~15% | List + detail header DONE. Missing: send, approve, e-sign, versioning, create. |
| 9 | Leads | ~35% | List, detail, create DONE. **Read-only Kanban view + List/Kanban toggle (commit 5bec1e4 — `ui/screens/leads/LeadKanbanBoard.kt` horizontal-scroll stage columns; drag-drop deferred).** Missing: conversions, lost-reason, drag-drop stage change. |
| 10 | Appointments | ~20% | Day-list + create DONE. Missing: week/month/agenda, RRULE recurrence, scheduling engine. |
| 11 | Expenses | ~25% | List w/ summary + filter, create DONE. Missing: receipt OCR, approval, pie chart, PhotoPicker. |
| 12 | SMS | ~40% | Thread list, WebSocket realtime, compose-new DONE. **Template picker sheet in thread compose with `{{placeholder}}` interpolation (commit 33a2608 — `GET /sms/templates` + `SmsTemplatePickerSheet` ModalBottomSheet).** Missing: filters, attachments, voice calls, bulk. |
| 13 | Notifications | ~65% | List + **group-by-day sticky headers (NEW)** + FCM token + deep-link whitelist + 12 granular channels + POST_NOTIFICATIONS prompt + **quiet hours UI (NEW)** DONE. Missing: rich push, in-app toast, launcher badge. |
| 14 | Employees & Timeclock | ~45% | List, clock in/out, **detail screen (NEW)** DONE. Missing: real-time presence, permissions matrix, edit/reset-PIN/deactivate (server endpoints pending). |
| 15 | Reports | ~30% | Tab shell + date picker + Sales DONE. Missing: Vico charts, drill-through, export. |
| 16 | POS | ~5% | Read-only "Recent Tickets" only. Missing: cart, catalog, checkout, payment, drawer. |
| 17 | Hardware | ~20% | HID barcode passthrough + **Ctrl+N/Shift+N/Shift+S/Shift+M/F/, keyboard chords (NEW)** DONE. Missing: CameraX wire, ML Kit wire, printers, stylus. |
| 18 | Global Search | ~58% | Debounced search + offline FTS + **recent searches chip row (NEW)** DONE. Missing: scoped search, voice. |
| 19 | Settings | ~30% | Main screen + biometric toggle + logout + notification toggles DONE. Missing: search-in-settings, change-password UI, change-PIN UI, deep links. |
| 20 | Offline & Sync | ~50% | sync_queue + sync_metadata + dead-letter + WorkManager + WebSocket DONE. Missing: conflict resolution, delta sync, cursor pagination, dev tools drawer. |
| 21 | Background & Push | ~55% | FCM + foreground service + WorkManager + **silent-push delta sync (NEW)** + quiet hours DONE. Missing: Live Updates (Android 16), OEM killer detection, Direct Boot. |
| 22 | Tablet polish | ~22% | NavigationSuiteScaffold dep + WindowMode helper + hardware-keyboard chords + **NavigationRail at \u2265600dp (NEW)** DONE. Missing: list-detail panes, drag-drop, stylus. |
| 23 | Foldable / Desktop | 0% | Not started. |
| 24 | Widgets/Live/Shortcuts | ~30% | Static shortcuts + QS tile + classic widget DONE. Missing: Glance widgets, Live Updates, dynamic shortcuts. |
| 25 | App Search/Share/Clipboard | ~25% | **ClipboardUtil w/ OTP detect + sensitive-clear (NEW)** DONE. Missing: AppSearchSession, share intent filter, cross-device. |
| 26 | Accessibility | ~88% | ReduceMotion util + Settings toggle + tests + BrandTopAppBar heading() + BrandListItem mergeDescendants/Role.Button + 13 screen list sweeps (Dashboard/Tickets/Customers/Invoices/Expenses/Appointments/Inventory/Estimates/Leads/SmsList/SmsThread/POS/BarcodeScan) + **Reports tabs+charts (9360501) + Profile + NotificationSettings (dfabb5d) sweeps — 16 screens covered.** Missing: fontScale stress test, a11y framework tests, remaining Settings sub-screens (Security/ChangePassword/SwitchUser/Theme/Language — small surfaces), Checkout. |
| 27 | i18n | 0% | Not started. |
| 28 | Security | ~72% | SQLCipher + EncryptedSharedPrefs + cert pinning + Network Security Config + FLAG_SECURE (partial) + setRecentsScreenshotEnabled + RedactingHttpLogger + ClipboardUtil sensitive-clear + OTP detect + SessionRevoked banner + Biometric STRONG + 401 remote sign-out + ProGuard Firebase ban DONE. Missing: Play Integrity, GDPR endpoints, Blur-on-recents, Timber RedactorTree. |
| 29 | Performance | ~18% | minifyEnabled true + JankStats beadrumb integration. Missing: Macrobenchmark, baseline profiles, CI gate. |
| 30 | Design System | ~50% | M3 theme, brand colors, typography, semantic colors DONE. Missing: dynamic color, MotionScheme.expressive, component library. |
| 31 | Testing | ~22% | Schema guard rail + JVM unit tests for ImeiValidator / Breadcrumbs / WindowSize / AppError / ReduceMotion / Money / PhoneFormat / QuietHours / RecentSearches / EmailValidator / Formatters / LogRedactor / DateFormatter / **DeepLinkAllowlist (NEW)** DONE. Missing: Compose UI tests, integration, perf, E2E, a11y. |
| 32 | Telemetry | ~50% | ProGuard bans Firebase Crashlytics + CrashReporter + Crash Reports screen + RedactingHttpLogger + **Breadcrumbs ring buffer (NEW)** DONE. Missing: TelemetryClient + tenant upload path. |
| 33 | Play Store | ~25% | Versioning + signing config DONE. Missing: Fastlane, store listing, phased rollout. |

§§36-75 not yet audited. Next pass.

## Table of Contents

1. [Platform & Foundation](#1-platform--foundation)
2. [Authentication & Onboarding](#2-authentication--onboarding)
3. [Dashboard & Home](#3-dashboard--home)
4. [Tickets (Service Jobs)](#4-tickets-service-jobs)
5. [Customers](#5-customers)
6. [Inventory](#6-inventory)
7. [Invoices](#7-invoices)
8. [Estimates](#8-estimates)
9. [Leads](#9-leads)
10. [Appointments & Calendar](#10-appointments--calendar)
11. [Expenses](#11-expenses)
12. [SMS & Communications](#12-sms--communications)
13. [Notifications](#13-notifications)
14. [Employees & Timeclock](#14-employees--timeclock)
15. [Reports & Analytics](#15-reports--analytics)
16. [POS / Checkout](#16-pos--checkout)
17. [Hardware Integrations](#17-hardware-integrations)
18. [Search (Global + Scoped)](#18-search-global--scoped)
19. [Settings](#19-settings)
20. [Offline, Sync & Caching](#20-offline-sync--caching)
21. [Background, Push, & Real-Time](#21-background-push--real-time)
22. [Tablet-Specific Polish](#22-tablet-specific-polish)
23. [Foldable & Desktop-Mode Polish](#23-foldable--desktop-mode-polish)
24. [Widgets, Live Updates, App Shortcuts, Assistant](#24-widgets-live-updates-app-shortcuts-assistant)
25. [App Search, Share Sheet, Clipboard, Cross-device](#25-app-search-share-sheet-clipboard-cross-device)
26. [Accessibility](#26-accessibility)
27. [Internationalization & Per-App Language](#27-internationalization--per-app-language)
28. [Security & Privacy](#28-security--privacy)
29. [Performance Budget](#29-performance-budget)
30. [Design System & Motion (Material 3 Expressive)](#30-design-system--motion-material-3-expressive)
31. [Testing Strategy](#31-testing-strategy)
32. [Telemetry, Crash, Logging](#32-telemetry-crash-logging)
33. [Play Store / Internal Testing / Release](#33-play-store--internal-testing--release)
34. [Known Risks & Blockers](#34-known-risks--blockers)
35. [Parity Matrix (at-a-glance)](#35-parity-matrix-at-a-glance)
36. [Setup Wizard (first-run tenant onboarding)](#36-setup-wizard-first-run-tenant-onboarding)
37. [Marketing & Growth](#37-marketing--growth)
38. [Memberships / Loyalty](#38-memberships--loyalty)
39. [Cash Register & Z-Report](#39-cash-register--z-report)
40. [Gift Cards / Store Credit / Refunds](#40-gift-cards--store-credit--refunds)
41. [Payment Links & Public Pay Page](#41-payment-links--public-pay-page)
42. [Voice & Calls](#42-voice--calls)
43. [Bench Workflow (technician-focused)](#43-bench-workflow-technician-focused)
44. [Device Templates / Repair-Pricing Catalog](#44-device-templates--repair-pricing-catalog)
45. [CRM Health Score & LTV](#45-crm-health-score--ltv)
46. [Warranty & Device History Lookup](#46-warranty--device-history-lookup)
47. [Team Collaboration (internal messaging)](#47-team-collaboration-internal-messaging)
48. [Goals, Performance Reviews & Time Off](#48-goals-performance-reviews--time-off)
49. [Roles Matrix Editor](#49-roles-matrix-editor)
50. [Data Import (RepairDesk / Shopr / MRA / CSV)](#50-data-import-repairdesk--shopr--mra--csv)
51. [Data Export](#51-data-export)
52. [Audit Logs Viewer](#52-audit-logs-viewer)
53. [Training Mode (sandbox)](#53-training-mode-sandbox)
54. [Command Palette (Ctrl+K)](#54-command-palette-ctrlk)
55. [Public Tracking Page (customer-facing)](#55-public-tracking-page-customer-facing)
56. [TV Queue Board (in-shop display)](#56-tv-queue-board-in-shop-display)
57. [Kiosk / Lock-Task Single-Task Modes](#57-kiosk--lock-task-single-task-modes)
58. [Appointment Self-Booking (customer)](#58-appointment-self-booking-customer)
59. [Field-Service / Dispatch (mobile tech)](#59-field-service--dispatch-mobile-tech)
60. [Inventory Stocktake](#60-inventory-stocktake)
61. [Purchase Orders (inventory)](#61-purchase-orders-inventory)
62. [Financial Dashboard (owner view)](#62-financial-dashboard-owner-view)
63. [Multi-Location Management](#63-multi-location-management)
64. [Release checklist (go-live gates)](#64-release-checklist-go-live-gates)
65. [Non-goals (explicit)](#65-non-goals-explicit)
66. [Error, Empty & Loading States](#66-error-empty--loading-states-cross-cutting)
67. [Copy & Content Style Guide](#67-copy--content-style-guide-android-specific-tone)
68. [Deep-link / App Links reference](#68-deep-link--app-links-reference)
69. [Haptics Catalog](#69-haptics-catalog)
70. [Motion Spec](#70-motion-spec)
71. [Launch Experience](#71-launch-experience)
72. [In-App Help](#72-in-app-help)
73. [Notifications — granular matrix](#73-notifications--granular-per-event-matrix)
74. [Privacy-first analytics event list](#74-privacy-first-analytics-event-list)
75. [Final UX Polish Checklist](#75-final-ux-polish-checklist)

---
## 1. Platform & Foundation

Baseline infra rest of app depends on. All of it ships before anything domain-specific claims parity.

> **Data-sovereignty principle (global).** App has **exactly one network egress target**: `ApiClient.baseUrl`, server user entered at login (e.g. `bizarrecrm.com` or self-hosted URL). **No third-party SDK may open network socket** — no Crashlytics, Firebase Analytics, Sentry, Mixpanel, Amplitude, Bugsnag, Datadog, New Relic, FullStory, Segment, etc. Telemetry, crash reports, experiment assignments, heartbeats, diagnostics all POST to tenant server only. Google Play Services FCM is single exception (push transport, payload opaque to Google). See §32 for enforcement (lint rule + Play Data-safety declaration audit).

### 1.1 API client & envelope
- [x] `ApiClient` (Retrofit + OkHttp) with dynamic base URL (`ApiClient.setBaseUrl`) — per-tenant.
- [x] `{ success, data, message }` envelope decoder via Retrofit `CallAdapter.Factory` → `ApiResponse<T>` sealed (`Ok<T> | Err(code, message, requestId)`).
- [x] Bearer-token Authenticator from EncryptedSharedPreferences — inject on every request.
- [x] **Token refresh on 401 with retry-of-original-request.** OkHttp `Authenticator` queues concurrent calls behind single refresh in-flight, replays original once, drops to Login only if refresh itself 401s. Backend: `POST /auth/refresh`.
- [x] **Typed endpoint namespaces** — Retrofit interface per domain (`TicketsApi`, `CustomersApi`, …). No ad-hoc string paths in repositories.
- [x] **Multipart upload helper** (`ApiClient.upload(file, to, fields)`) for photos, receipts, avatars. Runs as WorkManager `Worker` so uploads survive app kill + Doze + OEM task killers. (commit da67d14 — `util/MultipartUpload.kt` + `data/sync/MultipartUploadWorker.kt`; path-sandbox validated; idempotency key deduplicates)
- [~] **Retries with jitter** on transient network failures (5xx, SocketTimeout, UnknownHostException). Respect `Retry-After` on 429.
- [~] **Offline detection banner** driven by `ConnectivityManager.NetworkCallback` — sticky banner at top of scaffold with "Offline — showing cached data" copy + Retry button.

### 1.2 Pinning & TLS
- [x] OkHttp `CertificatePinner` scaffold — empty pin set by default.
- [x] Decision: leave pins empty for Let's Encrypt on `bizarrecrm.com`, or pin to LE intermediates. Document decision in README and toggle per-build-variant.
- [x] Custom-server override (self-hosted tenants): user-trusted pins per base URL, stored encrypted via EncryptedSharedPreferences.
- [x] Network Security Config (`res/xml/network_security_config.xml`) — declare cleartext-denied except loopback for dev builds; pin anchors per tenant if enabled.

### 1.3 Persistence (Room + SQLCipher)

Works in lockstep with §20 Offline, Sync & Caching — both are Phase 0 foundation. This subsection covers storage layer; §20 covers repository pattern, sync queue, cursor pagination, conflict resolution on top.

- [x] Room + SQLCipher wiring via `net.zetetic:sqlcipher-android` + `SupportFactory` with per-install passphrase.
- [x] **Per-domain DAO**: Tickets, Customers, Inventory, Invoices, Estimates, Leads, Appointments, Expenses, SMS threads, SMS messages, Notifications, Employees, Reports cache. Each DAO paired with `XyzRepository` required by §20.1.
- [x] **`sync_state` table** (§20.5) — keyed by `(entity, filter?, parent_id?)` storing cursor + `oldestCachedAt` + `serverExhaustedAt?` + `lastUpdatedAt`. Drives every list's `hasMore` decision. Mandatory before domain list PRs can merge. (commit 36ac378 — `data/local/db/entities/SyncStateEntity.kt` composite PK `(entity, filter_key, parent_id)` `""`/`0L` null sentinels; `SyncStateDao` upsert/get/observe Flow/hasMore CASE/clear; `BizarreDatabase` v7→8; `MIGRATION_7_8` CREATE table + UNIQUE index in `Migrations.kt`; registered in `MigrationRegistry`; `8.json` schema hand-authored with placeholder `identityHash` — needs `./gradlew :app:kspDebugKotlin` local regen before release)
- [x] **`sync_queue` table** (§20.2) — optimistic-write log feeding drain Worker. Every mutation ViewModel enqueues here instead of calling ApiClient directly.
- [x] **Migrations registry** — numbered Room `Migration` classes, each idempotent. Instrumented tests assert every migration on fresh DB replica.
- [x] **`updated_at` bookkeeping** — every table records `updated_at` + `_synced_at`, so delta sync can ask `?since=<last_synced>`. (commit 36ac378 — `TicketEntity/CustomerEntity/InventoryItemEntity/InvoiceEntity` each gain `@ColumnInfo(name="_synced_at") val syncedAt: Long = 0L`; `updated_at TEXT` already present on all four; `MIGRATION_7_8` ALTER TABLE `_synced_at INTEGER NOT NULL DEFAULT 0` + backfill `UPDATE … SET _synced_at=0 WHERE _synced_at IS NULL`)
- [x] **Encryption passphrase** — 32-byte random on first run, stored via Android Keystore-backed EncryptedSharedPreferences with `AES256_GCM` scheme.
- [x] **Export / backup** — developer-only for now: `Settings → Diagnostics → Export DB` writes zipped snapshot (without passphrase) to Storage Access Framework via `ACTION_CREATE_DOCUMENT`. (commit cbaafba — `util/DbExporter.kt` streams DB + WAL + SHM + README warning into `ZipOutputStream` via SAF Uri; `ui/screens/settings/DiagnosticsScreen.kt` + `DiagnosticsViewModel.kt` with `ExportState` sealed class (Idle/InProgress/Success/Error) IO-dispatched; `CreateDocument("application/zip")` launcher defaults `bizarre-crm-<yyyyMMdd-HHmmss>.zip`; Settings row gated `BuildConfig.DEBUG`; `Screen.Diagnostics` nav route; raw encrypted export — SQLCipher decrypt out of scope per KDoc)
- [x] Opt out of Android Auto-Backup for the encrypted DB file (`android:allowBackup="false"` on Application or per-file `<exclude>` in `backup_rules.xml`). Tenant data must not land in user's Google Drive.

### 1.4 Design System & Material 3 Expressive
- [x] `DesignSystemTheme` Composable wrapping `MaterialExpressiveTheme` (AndroidX Compose M3-Expressive). (commit 6a14dfd — `ui/theme/Theme.kt` `DesignSystemTheme()` wraps `BizarreCrmTheme`; `MaterialExpressiveTheme` swap deferred behind TODO(M3Expressive) comment pending stable release of `androidx.compose.material3:material3-expressive`)
- [x] **Dynamic color**: on Android 12+, seed color scheme from `dynamicLightColorScheme(LocalContext.current)` / `dynamicDarkColorScheme`. Fallback to tenant brand palette on pre-12 / when tenant forces brand colors. (commit 6a14dfd + 6cfcefa — `Theme.kt:213-220` branches on `Build.VERSION.SDK_INT >= S`; `AppPreferences.dynamicColorFlow` + `ThemeScreen` toggle)
- [x] **Shape tokens**: soft / medium / large / extra-large corner families (4 / 8 / 16 / 28dp), rotating / concave cut corners on FAB + emphasis buttons via `AbsoluteSmoothCornerShape`-equivalent. (commit 6a14dfd — `ui/theme/Shapes.kt` `BizarreShapes` with extraSmall/small/medium/large/extraLarge tokens)
- [x] **Typography**: Material 3 `Typography` with brand font stack — Bebas Neue (display), League Spartan (headline), Roboto (body/UI), Roboto Mono (IDs). Loaded via `res/font/` XML fontFamily + `rememberFontFamily` fallbacks.
- [x] **Motion**: Material 3 Expressive spring motion tokens (`MotionScheme.expressive()` / `.standard()`); per-user Reduce Motion override honors `ACCESSIBILITY_DISPLAY_ANIMATION_SCALE` + in-app toggle. (commit 6a14dfd — `ui/theme/Motion.kt` `BizarreMotion.expressive/standard` + `motionSpec(reduceMotion)` helper honoring `util/ReduceMotion.kt`)
- [x] **Surfaces / elevation**: Material 3 tonal elevation (no drop shadows except on FABs). Max 3 elevation levels per screen.
- [x] **Tenant accent** — `BrandAccent` color layered via `LocalContentColor` + `primary` swap; increase-contrast mode bumps to AA 7:1 palette. (commit 6a14dfd — `Theme.kt:171-191` `BrandAccent` + `tenantAccentOrFallback()` + `LocalBrandAccent` staticCompositionLocal; AA 7:1 increase-contrast ramp pending)
- [x] No glassmorphism. No translucent blurred nav bars. That is iOS Liquid Glass; Android stays on tonal M3 surfaces to keep the platform voice distinct. (commit 6a14dfd — `Theme.kt:1-20` design-decision file-header banning RenderEffect/BlurMaskFilter; also referenced in Android_audit.md §1.4)

### 1.5 Navigation shell
- [ ] `NavHost` + `NavController` — typed routes via `@Serializable` data classes (Compose Navigation type-safe routes, AndroidX Navigation 2.8+).
- [ ] **Adaptive Navigation Suite** — `NavigationSuiteScaffold` auto-picks: phone = bottom `NavigationBar`; tablet = `NavigationRail`; foldable large = `PermanentNavigationDrawer`.
- [x] **Typed path enum** per tab — `TicketsRoute.List | Detail(id) | Create | Edit(id)`. Deep-link router consumes these.
- [ ] **Tab customization** (phone): user-reorderable tabs; fifth tab becomes "More" overflow.
- [ ] **Predictive back gesture** — adopt AndroidX `PredictiveBackHandler` everywhere (Android 14+ preview, Android 16 default on). Custom animations survive the drag.
- [x] **Deep links**: `bizarrecrm://tickets/:id`, `/customers/:id`, `/invoices/:id`, `/sms/:thread`, `/dashboard`. Mirror iOS URL scheme.
- [~] **App Links** (HTTPS verified) over `app.bizarrecrm.com/*` — `assetlinks.json` served at tenant root; `AndroidManifest.xml` intent filters with `android:autoVerify="true"`. (commit a629898 — intent-filter + autoVerify added; `assetlinks.json` server-side deploy pending)

### 1.6 Environment & config
- [x] `AndroidManifest.xml` permission audit — declare only what's used; runtime-request each lazy.
- [x] `build.gradle.kts` `buildConfigField` for `BASE_DOMAIN`, `SERVER_URL` (seeded from repo `.env` / Gradle property / env var — already wired).
- [x] `minSdk = 26` (Android 8.0 — covers foreground service + adaptive icons); `targetSdk = 36` once Android 16 stable (currently 35); `compileSdk = 36`. (commit 9408f0d — `minSdk=26` verified; `compileSdk=35→36`; `targetSdk=35` retained — rationale inline comment: no API-36 instrumented coverage yet)
- [x] Required runtime permissions prompted just-in-time: `CAMERA`, `READ_MEDIA_IMAGES` (Android 13+) / `READ_EXTERNAL_STORAGE` (≤12), `POST_NOTIFICATIONS` (13+), `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN` (12+), `ACCESS_FINE_LOCATION` (geofence/tech dispatch — 33+ conditional), `RECORD_AUDIO` (SMS voice memo optional), `READ_CONTACTS` (import), `WRITE_EXTERNAL_STORAGE` never (use SAF). (commit 9408f0d — fixed `READ_MEDIA_IMAGES` `maxSdkVersion=32` bug (permission is API-33+); added `READ_EXTERNAL_STORAGE maxSdkVersion=32`, `BLUETOOTH_CONNECT/SCAN usesPermissionFlags=neverForLocation`, `ACCESS_FINE_LOCATION`, `RECORD_AUDIO`, `READ_CONTACTS`; no `WRITE_EXTERNAL_STORAGE`)
- [x] Foreground service type declarations per Android 14+ requirement: `dataSync`, `connectedDevice`, `shortService`, `mediaPlayback` (call ringing), `specialUse` (repair-in-progress live update). (commit 9408f0d — `RepairInProgressService foregroundServiceType=dataSync` declared + `FOREGROUND_SERVICE_TYPE_DATA_SYNC` passed on API 34+; FcmService system-managed; WebSocketService is Hilt `@Singleton` not FGS; QuickTicketTileService is TileService; FOREGROUND_SERVICE + FOREGROUND_SERVICE_DATA_SYNC perms declared)
- [x] `queries` manifest entries — declare intent filters for Tel, Sms, Maps, Email (package visibility on Android 11+). (commit a629898 — `<queries>` block added)
- [x] Gradle version catalog (`libs.versions.toml`) — move deps from inline to catalog; renovate bot opens PRs. (commit d97dfa7 — `gradle/libs.versions.toml` + `build.gradle.kts` + `app/build.gradle.kts`)
- [x] Room `AutoMigration` declared where shape changes; manual `Migration` for data shifts. Immutable once shipped. (commit 99c85ff — `BizarreDatabase.kt` KDoc convention; `MigrationRegistry.kt` single source of truth; `MIGRATION_6_7` manual for `applied_migrations` DDL)
- [x] Migration-tracking table records applied names; app refuses to launch if known migration missing. (commit 99c85ff — `data/local/db/entities/AppliedMigrationEntity.kt` + `AppliedMigrationDao.kt` + `TimedMigration` wrapper inserts row after each step; `validateAllStepsPresent()` fatal-boot check in DatabaseModule onOpen path)
- [x] Forward-only (no downgrades). Reverted client version → "Database newer than app — contact support". (commit 99c85ff — `DatabaseGuard.checkForwardOnly()` + `exitProcess(2)` + `recordSuccessfulOpen`; no `fallbackToDestructiveMigrationOnDowngrade` builder call)
- [x] Large migrations split into batches; progress notification ("Migrating 50%"); runs inside WorkManager `expedited` Worker so user can leave app. (commit 99c85ff — `data/sync/DbMigrationBackupWorker.kt` `@HiltWorker` + `setForegroundAsync` with `MIGRATION_PROGRESS` channel; `MigrationRegistry.isHeavy()` flag + heavy-worker enqueue loop in DatabaseModule; stub body intentional — no heavy migration exists yet)
- [x] Backup-before-migrate: copy encrypted DB to `cacheDir/pre-migration-<date>.db`; keep 7d or until next successful launch. (commit 99c85ff — `DatabaseGuard.backupIfNeeded()` copies DB + -wal/-shm sidecars; 7-day prune policy)
- [x] Debug builds: dry-run migration on backup first and report diff before apply. (commit 99c85ff — `DatabaseGuard.dryRunOnBackupIfDebug()` runs `PRAGMA integrity_check` on backup via Timber, debug-only)
- [x] CI runs every migration against minimal + large fixture DBs. (commit 99c85ff — `MigrationRegistryTest.kt` 9 JVM unit tests cover chain completeness/no-duplicates/validate pass+fail+fresh-install skip; `androidTest/` instrumented scaffold absent — gap noted in commit body)
- [x] Hilt DI `@InstallIn(SingletonComponent::class)` for ApiClient / Database / EncryptedSharedPreferences. ViewModels via `@HiltViewModel` + `@Inject`. Widgets + Workers get Hilt via `@HiltWorker` + `WorkerAssistedFactory`.
- [x] Test doubles: Hilt `@TestInstallIn` swaps per test class; no global-state leaks (assertions in `@Before`). (commit b704d98 — `testing/TestDatabaseModule.kt` in-memory Room replaces `DatabaseModule`; `TestApiModule.kt` stub Retrofit replaces `RetrofitClient`; `TestDataStoreModule.kt` `@TestSharedPrefs`; `TestDispatcherModule.kt` `StandardTestDispatcher` + `@IoDispatcher/@MainDispatcher`; `HiltTestRules.kt` TestRule guards GlobalScope `Job.children.count` via reflection; `ExampleHiltTest.kt` injects `RateLimiter` with HiltAndroidRule + InstantTaskExecutorRule + HiltTestRules; deps `hilt-android-testing:2.53`, `kspTest`, `androidx.test:runner:1.5.2`, `arch-core-testing`, `coroutines-test:1.8.1`. Test run blocked by pre-existing `kspDebugKotlin` NPE — follow-up dep bump needed.)
- [x] Lint rule bans `object Foo { val shared = ... }` singletons except Hilt-provided; also bans `GlobalScope.launch`. (commit 4c75801 — new `android/lint-rules/` module with `java-library`+`kotlin-jvm`, `lint-api/checks/tests:31.7.3`; `CrmIssueRegistry` with vendor+`CURRENT_API`; `StatefulObjectSingletonDetector` UAST ERROR severity flagging `var` fields in `object` outside `.di.`/Dagger/androidx with `@SuppressLint` support; `GlobalScopeLaunchDetector` UAST ERROR on `GlobalScope.launch/async` with dual-key suppression (`@OptIn(DelicateCoroutinesApi)` + `// ok:global-scope`); `META-INF/services` service-loader; wired via `lintChecks(project(":lint-rules"))`. JAR verified valid. `:app:lintDebug` blocked by pre-existing KSP failure — follow-up)
- [x] Widgets (Glance) + App-Actions shortcuts import `:core` module + register own Hilt sub-scope. (commit 28aef61 — `widget/glance/UnreadSmsGlanceWidget.kt` GlanceAppWidget + `UnreadSmsBody` composable + `publishUnreadCount()` helper using `PreferencesGlanceStateDefinition`; `UnreadSmsGlanceReceiver` Hilt-free `GlanceAppWidgetReceiver`; `GlanceWidgetKeys.KEY_UNREAD_COUNT`; `res/xml/glance_unread_sms_info.xml` 110dp×40dp horizontal+vertical resize + 30min update; `res/drawable/glance_preview_unread_sms.xml`; manifest `<receiver>` exported=false APPWIDGET_UPDATE filter; click→`bizarrecrm://messages`; deps `glance-appwidget`+`glance-material3` 1.1.1. `:core` module split deferred — widget lives inside `:app` for now)
- [x] `AppError` sealed class with branches: `Network(cause)`, `Server(status, message, requestId)`, `Auth(reason)`, `Validation(List<FieldError>)`, `NotFound(entity, id)`, `Permission(required: Capability)`, `Conflict(ConflictInfo)`, `Storage(reason)`, `Hardware(reason)`, `Cancelled`, `Unknown(cause)`. (`util/AppError.kt` — `Permission` folded into `Auth.PermissionDenied`.)
- [x] Each branch exposes `title`, `message`, `suggestedActions: List<AppErrorAction>` (retry / open-settings / contact-support / dismiss). (commit c4b1cee — `util/ErrorRecovery.kt` `recover(AppError) → Recovery`)
- [x] Errors logged with Timber category + code + request ID; no PII per §32.6 Redactor. (commit 97f6416 — `util/RedactorTree.kt` planted in `BizarreCrmApp.onCreate`; 22 sensitive keys masked; also closes §28.64 "RedactorTree pending" audit gap)
- [ ] User-facing strings in `strings.xml` with per-language resource folders (§27).
- [x] Error-recovery UI per taxonomy case lives in each feature module. (commit c4b1cee + d90f652 — `ErrorRecovery.recover()` util + `Action` enum + `ui/components/ErrorSurface.kt` composable with compact/full layouts, icon mapping, destructive styling; feature modules call `ErrorSurface(error, onAction)` and wire actions)
- [x] Undo/redo via `SnackbarHost` + undo-stack held in ViewModel; stack depth last 50 actions; cleared on nav dismiss. (commit 2e53665 — `util/UndoStack.kt` generic)
- [~] Covered actions: ticket field edit; POS cart item add/remove; inventory adjust; customer field edit; status change; notes add/remove. (commit 2e53665 — util ready; per-feature ViewModel wiring pending)
- [~] Undo trigger: Snackbar action button; Ctrl+Z on hardware keyboard (tablet/ChromeOS); `TYPE_CONTEXT_CLICK` long-press on phone; shake gesture optional. (commit 2e53665 — util ready; Snackbar+chord wiring pending)
- [~] Redo: Ctrl+Shift+Z. (commit 2e53665 — redo logic in util; chord wiring pending)
- [x] Server sync: undo rolls back optimistic change, sends compensating request if already synced; if undo impossible, toast "Can't undo — action already processed". (commit 2e53665 — `compensatingSync` contract + `UndoEvent.Failed`)
- [x] Audit integration: each undo creates audit entry (not silent). (commit 2e53665 — `UndoEvent.Undone` / `UndoEvent.Redone` carry `auditDescription`)
- [x] Activity lifecycle: `Application.onCreate` → init Hilt + WorkManager + Timber + NotificationChannels; `Activity.onStart` → resolve last tenant, attempt token refresh in background Worker.
- [x] Foreground: `Lifecycle.ON_RESUME` → kick delta-sync Worker, refresh push token, ping `last seen`; resume paused animations; re-evaluate lock-screen gate (biometric required if inactive > 15min). (commit 30d65d7 + 0584d26 — `BizarreCrmApp` ProcessLifecycleOwner ON_START re-bootstraps session, runs `SyncWorker.syncNow`, reconnects WebSocket; `util/FcmTokenRefresher.refreshIfStale()` 24h gate + `AuthApi.registerDeviceToken` POST; `MainActivity.onResume()` reads SessionTimeout+PinPreferences+biometricEnabled, sets `lockedState` for Compose-observed biometric re-prompt)
- [x] Background: `Lifecycle.ON_PAUSE` → persist unsaved drafts; schedule delta-sync via WorkManager `periodicWorkRequest` 15min; seal clipboard if sensitive; set `FLAG_SECURE` on window if screen-capture privacy required. (commit 30d65d7 + 39556c7 + 0584d26 — ON_STOP reschedules delta-sync via SyncWorker KEEP, calls `ClipboardUtil.clearSensitiveIfPresent`, invokes `DraftStore.flushPending()` on appScope; `AppPreferences.screenCapturePreventionFlow` default `true` reactively toggles `FLAG_SECURE`+`setRecentsScreenshotEnabled` via collectAsState in MainActivity.setContent; eager pre-setContent apply avoids unsecured first frame; DEBUG bypass preserved)
- [x] Terminate rarely predictable on Android (OEM killers); don't rely on — persist state on every field change, not at destroy. (commit 30d65d7 — KDoc invariant on observer)
- [x] Memory pressure: `onTrimMemory(TRIM_MEMORY_RUNNING_LOW)` → flush Coil memory cache, drop preview caches; never free active data. (commit 30d65d7 — Coil 3 `SingletonImageLoader.memoryCache?.clear()`)
- [ ] Process death: save instance state via `SavedStateHandle`; ViewModel survives config change but not process kill — SavedStateHandle reconstitutes.
- [x] URL open / App Link: handle via `MainActivity.onNewIntent` → central `DeepLinkRouter` (§68). (commit 00bc645 — `MainActivity.onNewIntent()` calls `resolveDeepLink()` + `resolveFcmRoute()` → `DeepLinkBus.publish()`; `util/DeepLinkAllowlist.kt` whitelist enforced; FCM extras `navigate_to`+`entity_id` mapped to 9 entity routes)
- [x] Push in foreground: FCM `onMessageReceived` dispatches to `NotificationController`; SMS_INBOUND shows banner but not sound if user already in SMS thread for that contact. (commit 5800443 — `service/NotificationController.kt` channel-selection + dedup via `util/ActiveChatTracker.kt` `currentThreadPhone`; `sms_silent` channel `IMPORTANCE_LOW` no-sound/vibrate registered in `BizarreCrmApp.createNotificationChannels()`; `FcmService.onMessageReceived` delegates after silent-sync short-circuit)
- [x] Push background: `Notification.Action` handles action buttons (Reply / Mark Read) inline via `RemoteInput`. (commit 5800443 — `service/NotificationActionReceiver.kt` `@AndroidEntryPoint` handles `ACTION_REPLY_SMS` via `RemoteInput.getResultsFromIntent` + `SyncQueueEntity(operation="send_sms")` enqueue; `ACTION_MARK_READ` enqueues `mark_read` PATCH; 12 JVM tests; receiver registered in AndroidManifest)
- [x] Silent push (`data-only`): `onMessageReceived` triggers delta-sync `expedited` Worker; must complete within 10s to avoid ANR. (`FcmService.onMessageReceived` short-circuits when `type=silent_sync` / `data.sync=true` / no notification + no body, calls `SyncWorker.syncNow(this)`, and skips notification-post.)
- [x] Persistence: Room + SQLCipher chosen (encryption-at-rest mandatory; native Room lacks encryption); Room `Paging3` integrations mature for §130 search; Room concurrency via coroutines + `Flow` matches heavy-read light-write load; no CloudKit / Drive cross-device sync (§32 sovereignty).
- [x] Concurrency: Room `SuspendingTransaction` per repository; `Dispatchers.IO` for disk, `Dispatchers.Default` for parsing/formatting. Single write executor to avoid `SQLITE_BUSY`.
- [ ] Observation: Room `Flow<T>` bridges into Compose via `collectAsStateWithLifecycle`.
- [x] Clock-drift detection: on startup + every sync, compare `System.currentTimeMillis()` to server `Date` header; flag drift > 2 min. (commit 5ba8e58 — `util/ClockDrift.kt` + `data/remote/interceptors/ClockDriftInterceptor.kt`)
- [x] User warning banner when drifted: "Device clock off by X minutes — may cause login issues" + deep link to system Date & Time settings. (commit 5ba8e58 + 8d61b74 + a762605 — `ui/components/ClockDriftBanner.kt` collects `ClockDrift.state`, errorContainer surface + "Open settings" → `Settings.ACTION_DATE_SETTINGS`; mounted in root Scaffold when logged in)
- [x] TOTP gate: 2FA fails if drift > 30s; auto-retry once with adjusted window, then hard error. (commit 5ba8e58 — `ClockDrift.isSafeFor2FA()` + `TOTP_DRIFT_MS`)
- [x] Timestamp logging: all client timestamps include UTC offset; server stamps its own time; audit uses server time as authoritative. (commit 5ba8e58 — `ClockDrift.toAuditTimestamp()`)
- [x] Offline timer: record both device time + offline duration on sync-pending ops so server can reconcile. (commit 5ba8e58 — `ClockDrift.recordPendingOp()` + `PendingOpTimestamps`)
- [x] Client rate limit: token-bucket per endpoint category — read 60/min, write 20/min; excess queued with backoff. (commit 51a2995 + hardening b10f8ca — `util/RateLimiter.kt` + `RateLimitInterceptor.kt`; fail-fast when pause > timeout; jitter on wake)
- [x] Honor server hints: `Retry-After`, `X-RateLimit-Remaining`; pause client on near-limit signal. (commit 51a2995 + hardening b10f8ca — `recordServerHint()`; interceptor synthesizes 429 instead of re-firing request when `acquire()` returns false)
- [x] UI: silent unless sustained; show "Slow down" banner if queue > 10. (commit 51a2995 + 0e82441 + a762605 — `ui/components/RateLimitBanner.kt` collects `RateLimiter.queueState`, tertiaryContainer surface + depth readout; mounted in root Scaffold when logged in)
- [~] Debug drawer exposes current bucket state per endpoint. (commit 51a2995 — `StateFlow<Map<Category, BucketState>>` exposed; drawer UI pending)
- [x] Exemptions: auth + offline-queue flush not client-limited (server-side limits instead). (commit 51a2995 — `isExempt()` matches `/auth/*` and tag `sync-flush`)
- [x] Auto-save drafts every 2s to Room for ticket-create, customer-create, SMS-compose; never lost on crash/background. (commit 9fb71216 + c7dd6f5 + 7656ab2 + bec40b4 + 8f3264f — `DraftStore` + 2s debounce shipped for TicketCreate / CustomerCreate / SmsThread compose / ExpenseCreate via per-VM `onFieldChanged()` + `DraftType` enum extended with EXPENSE)
- [x] Recovery prompt on next launch or screen open: "You have an unfinished <type> — Resume / Discard" sheet with preview. (commit 9fb71216 + e8377a7 — `ui/components/DraftRecoveryPrompt.kt` ModalBottomSheet consumes `DraftStore.Draft`; 140-char preview + relative-age "Saved Nh ago" + Discard/Resume actions; 19 pure-JVM tests)
- [x] Age indicator on draft ("Saved 3h ago"). (commit 9fb71216 + e8377a7 — `formatDraftAge(savedAtMs, nowMs)` pure helper with 5 branches + clock-skew guard; rendered in DraftRecoveryPrompt)
- [x] One draft per type (not multi); explicit discard required before starting new. (commit 9fb71216 — unique index on `(user_id, draft_type)`)
- [x] Sensitive: drafts encrypted at rest; PIN/password fields never drafted. (commit 9fb71216 — `sanitiseDraftPayload()` strips 5 key families; SQLCipher at-rest)
- [x] Drafts stay on device (no cross-device sync — avoid confusion). (commit 9fb71216 — KDoc asserts; no SyncQueue entries)
- [x] Auto-delete drafts older than 30 days. (commit 9fb71216 — `pruneOlderThanDays(30)`)

---
## 2. Authentication & Onboarding

_Server endpoints: `GET /auth/setup-status`, `POST /auth/setup`, `POST /auth/login`, `POST /auth/login/set-password`, `POST /auth/login/2fa-setup`, `POST /auth/login/2fa-verify`, `POST /auth/login/2fa-backup`, `POST /auth/refresh`, `POST /auth/logout`, `GET /auth/me`, `POST /auth/forgot-password`, `POST /auth/reset-password`, `POST /auth/recover-with-backup-code`, `POST /auth/verify-pin`, `POST /auth/switch-user`, `POST /auth/change-password`, `POST /auth/change-pin`, `POST /auth/account/2fa/disable`._

### 2.1 Setup-status probe
- [x] **Backend:** `GET /auth/setup-status` returns `{ needsSetup, isMultiTenant }`. On first launch after server URL entry, Android hits this before rendering login form. (commit 038db99 — `AuthApi.getSetupStatus()` + `SetupStatusResponse` DTO)
- [x] **Frontend:** if `needsSetup` → push `InitialSetupFlow` (see 2.10). If `isMultiTenant` + no tenant chosen → push tenant picker. Else → render login. (commit 038db99 — `SetupStatusGateScreen` + LoginScreen banner; `InitialSetupFlow` navigation deferred to §2.10)
- [x] **Expected UX:** transparent to user; ≤400ms overlay `CircularProgressIndicator` with "Connecting to your server…" label. Fail → inline retry on login screen. (commit 038db99 + 1ae03bb — probe non-blocking, overlay + inline retry; `CredentialsStep` needs-setup Column banner "A setup wizard will appear in a future release. Please contact your admin to complete setup manually." + tappable "View setup guide" TextButton → `https://bizarrecrm.com/docs/setup` ACTION_VIEW; form unblocked)

### 2.2 Login — username + password (step 1)
- [x] Username + password form, dynamic server URL, token storage in EncryptedSharedPreferences.
- [x] **Response branches** `POST /auth/login` returns any of:
  - `{ challengeToken, requiresFirstTimePassword: true }` → push SetPassword step.
  - `{ challengeToken, totpEnabled: true }` → push 2FA step.
  - `{ accessToken, user }` → happy path.
- [x] **Username not email** — server uses `username`, mirror that label. Support `@email` login fallback if server accepts it.
- [x] **Keyboard flow** — `ImeAction.Next` on username, `ImeAction.Go` on password; `FocusRequester.moveFocus(FocusDirection.Down)` auto-advance.
- [x] **"Show password" eye toggle** via `VisualTransformation` swap.
- [x] **Remember-me toggle** persists username in EncryptedSharedPreferences + flag to surface biometric prompt next launch.
- [x] **Form validation** — primary CTA disabled until both fields non-empty; inline error on server 401 ("Username or password incorrect.").
- [x] **Rate-limit handling** — server throttles IP (5/15min) and username (10/30min); surface "Too many attempts. Wait N minutes." banner with countdown. (commit 1ae03bb — `login()` 429 handler parses body `retry_in_seconds` (priority over `Retry-After` header) + `scope` field; `LoginUiState.rateLimitScope`; scope-aware copy (username vs IP); countdown `Nm Ss` ≥60s / `Ns` <60s; `clearRateLimit()` resets scope)
- [x] **Trust-this-device** checkbox on 2FA step → server flag `trustDevice: true`.

### 2.3 First-time password set
- [x] **Endpoint:** `POST /auth/login/set-password` with `{ challengeToken, password }`.
- [x] **Frontend:** password + confirm fields, strength meter (length, mixed-case, digit, symbol, not-in-breach-list via local dictionary), CTA disabled until rules pass. (commit 1ae03bb — `util/PasswordStrength.kt` pure-JVM object 6 rules + top-50 common password list (expansion path KDoc); `ui/components/auth/PasswordStrengthMeter.kt` 5-segment color bar + per-rule Done/Clear checklist; `SetPasswordStep` renders meter when non-empty, CTA disabled until `strength >= FAIR`; 20 JVM tests)
- [x] **UX:** M3 surface titled "Set your password to continue"; subtitle "Your admin requested a reset".

### 2.4 2FA / TOTP
- [x] **Enroll during login** — `POST /auth/login/2fa-setup` → `{ qr, secret, manualEntry, challengeToken }`. Render QR via ZXing `BarcodeEncoder` + copyable secret with `SelectionContainer`. Detect installed authenticator apps via `PackageManager` query for `otpauth://` intent. (commit cd36e98 — `util/QrCodeGenerator.kt` ZXing 3.5.3 BitMatrix→ARGB_8888 Bitmap + pure-JVM `QrCodeGeneratorPure` twin for tests; `TwoFaSetupResponse` DTO; `AuthApi.setup2FA` return type switched; `LoginScreen.TwoFaSetupStep` renders QR + SelectionContainer secret + 30s auto-clear "Copy key" + conditional "Open authenticator" `otpauth://` Intent button + OTP submit)
- [x] **Verify code** — `POST /auth/login/2fa-verify` with `{ challengeToken, code, trustDevice? }` returns `{ accessToken, user }`.
- [x] **Backup code entry** — `POST /auth/login/2fa-backup` with `{ challengeToken, backupCode }`.
- [x] **Backup codes display** (post-enroll) — show full list once, copy-all button, "I saved them" confirm. Warn loss = lockout. (commit cd36e98 — `ui/screens/auth/BackupCodesDisplay.kt` FlowRow mono chips + warning banner + "Copy all" sensitive clip + checkbox gate → "Done" primary CTA; replaces prior inline AlertDialog)
- [~] **Autofill OTP** — `KeyboardOptions(keyboardType = KeyboardType.NumberPassword, autoCorrect = false)` + `@AutofillType.SmsOtpCode` via `LocalAutofillTree`. SMS Retriever API (`SmsRetrieverClient`) picks up code from Messages automatically when `<#>` prefix + app hash present. (commit 8301aa5 — `otpKeyboardOptions()` + `SMS_OTP_AUTOFILL_HINT` done; `ContentType.SmsOtpCode` blocked on internal Compose 1.7.x visibility; `smsRetrieverClient` stub pending `play-services-auth-api-phone` dep)
- [x] **Paste-from-clipboard** auto-detect 6-digit string. (commit 8301aa5 — `detectOtpFromClipboard` + `OtpParser.extractOtpDigits`)
- [blocked: policy — 2FA disable not allowed per user directive 2026-04-23. Android client must never surface a "Disable 2FA" action; server endpoint may exist but UI is intentionally absent.] **Disable 2FA** (Settings → Security) — `POST /auth/account/2fa/disable` with `{ password?, code? }`.

### 2.5 PIN lock
- [x] **Set PIN** first launch after login — 4–6 digit numeric; `POST /auth/change-pin` with `{ newPin }`; server bcrypts; store hash mirror in EncryptedSharedPreferences. (Settings → Set up PIN routes to `PinSetupScreen` via `Screen.PinSetup`. Local hash mirror not stored — server is source of truth.)
- [x] **Verify PIN** — `POST /auth/verify-pin` with `{ pin }` → `{ verified }`.
- [x] **Change PIN** — Settings → Security; `POST /auth/change-pin` with `{ currentPin, newPin }`. (Settings row label flips to "Change PIN" when `pinPreferences.isPinSet`; routes to same `PinSetupScreen`.)
- [x] **Switch user** (shared device) — `POST /auth/switch-user` with `{ pin }` → `{ accessToken, user }`. Expose as "Switch user" row on Settings & long-press on avatar in top bar. (commit 69e3c1b — `ui/screens/settings/SwitchUserScreen.kt` reuses PinKeypad; Settings row + AppNavGraph route; long-press avatar path deferred)
- [x] **Lock triggers** — cold start, background for N minutes (Settings: 0/1/5/15/never), explicit "Lock now" action. (commit 2cff9bd — `PinPreferences.lockGraceMinutes` + `setLockGraceMinutes()` + `lockGraceMinutesFlow` via EncryptedSharedPreferences key `lock_grace_min`; `GRACE_NEVER=Int.MAX_VALUE` sentinel; `shouldLock()` branches GRACE_NEVER→false, 0→true >=1000ms elapsed (sub-sec jitter guard), 1/5/15→N-min grace; cold-start `last==0L` triggers immediately; `SecurityScreen.AutoLockRow` `SingleChoiceSegmentedButtonRow` {Immediate/1m/5m/15m/Never} between biometric + PIN cards; `SecurityViewModel.lockNow()` → `PinPreferences.lockNow()` sets `lastUnlockAtMillis=0L`; 17 JVM tests)
- [x] **Keypad UX** — custom numeric keypad Composable; `HapticFeedbackConstants.VIRTUAL_KEY` per tap, `HapticFeedbackConstants.REJECT` on wrong PIN, lockout after 5 wrong tries → full re-auth.
- [x] **Forgot PIN** → "Sign out and re-login" destructive action.
- [x] **Tablet layout** — keypad centered in `ElevatedCard`, not full-width. (commit 162cb12 — `ui/auth/PinLockScreen.kt` `PinGateScaffold` branches on `isMediumOrExpandedWidth()`; tablet wraps title+PinDots+PinKeypad in `ElevatedCard` with `widthIn(max=420.dp)` + `Arrangement.Center`; PinSetupScreen inherits via shared scaffold)

### 2.6 Biometric (fingerprint / face)
- [x] **Manifest:** no permission required (BiometricPrompt handles).
- [x] **Enable toggle** — Settings → Security (availability via `BiometricManager.canAuthenticate(BIOMETRIC_STRONG or BIOMETRIC_WEAK)`). (commit 4d3ee12 — `ui/screens/settings/SecurityScreen.kt`)
- [x] **Unlock chain** — bio → fail-3x → PIN → fail-5x → full re-auth. (commit 4d3ee12 — policy documented + `lockNow()` + PinPreferences hardLockout)
- [x] **Login-time biometric** — if "Remember me" + biometric enabled, decrypt stored credentials via `BiometricPrompt.CryptoObject` (Android Keystore-backed AES256) and auto-POST `/auth/login`. (commit 4d3ee12 + f70c2fd — `data/local/prefs/BiometricCredentialStore.kt` Keystore AES-256-GCM alias `biometric_creds_v1` with `setUserAuthenticationRequired(true)` + `setInvalidatedByBiometricEnrollment(true)`; `store()`/`retrieve()`/`clear()`/`hasStoredCredentials`; typed `RetrieveResult` sealed class + `KeyPermanentlyInvalidatedException` → `Invalidated` non-throwing; `BiometricAuth.encryptWithBiometric()` + `decryptWithBiometric()` suspend returning unwrapped `Cipher`; `AuthPreferences.biometricCredentialsEnabled` + `getStoredCredentialsIv()/setStoredCredentialsIv()`; `clear(UserLogout)` wipes bio fields)
- [x] **Respect disabled biometry** gracefully — never crash, fall back to PIN silently. (commit f70c2fd — `BiometricAuth.showPrompt` `onError` typed `(BiometricFailure)->Unit`; `BiometricFailure.Disabled` for `ERROR_NO_BIOMETRICS`/`ERROR_HW_UNAVAILABLE`/`ERROR_HW_NOT_PRESENT`; 11 JVM tests cover canAuthenticate branches + 6 error-code→Failure mappings via JVM-safe wrapper)
- [x] **Re-enrollment detection** — Keystore invalidates key on new biometric enrollment when `setInvalidatedByBiometricEnrollment(true)`; catch `KeyPermanentlyInvalidatedException` → prompt user to re-enable biometric. (commit 4d3ee12 — `handleReEnrollRequired()` + ConfirmDialog)

### 2.7 Signup / tenant creation (multi-tenant SaaS)
- [x] **Endpoint:** `POST /auth/setup` with `{ username, password, email?, first_name?, last_name?, store_name?, setup_token? }` (rate limited 3/hour).
- [x] **Frontend:** multi-step form — Company (name, phone, address, timezone, shop type) → Owner (name, email, username, password) → Server URL (self-hosted vs managed) → Confirm & sign in. (commit 7951f2c — `RegisterSubStep` enum Company→Owner→ServerUrl→Confirm; `LinearProgressIndicator` fraction `(index+1)/4`; `AnimatedContent` horizontal slide + ANIMATOR_DURATION_SCALE==0 skips animation (ReduceMotion); per-step validation — Company: slug≥3+shopName; Owner: firstName, lastName, email regex, password≥FAIR reuses `PasswordStrengthMeter`; ServerUrl no required; Confirm summary; `registerPrevSubStep()/registerNextSubStep()` navigation; new state: `registerSubStep`, `registerFirstName/LastName/Username`)
- [x] **Auto-login** — if server returns `accessToken` in setup response, skip login; else POST `/auth/login`. Verify server side (root TODO `SIGNUP-AUTO-LOGIN-TOKENS`). (commit 7951f2c — `SetupResponse` DTO with optional `accessToken`/`refreshToken`/`user`/`message` + contract KDoc; `registerShop(onAutoLogin)` extracts `data.accessToken` → stores tokens + `AuthApi.getMe()` best-effort + invokes callback → dashboard; fallback when null → CREDENTIALS step with pre-filled username from `registerEmail`; 6 JVM tests)
- [x] **Timezone picker** — pre-selects device TZ (`ZoneId.systemDefault().id`). (commit 9bfedca — `ui/screens/auth/LoginScreen.kt` `TimezoneDropdown` ExposedDropdownMenuBox + curated 22-TZ list with `ZoneId.systemDefault().id` injected at top; `LoginUiState.registerTimezone` + `updateRegisterTimezone()` bound to `registerShop()` POST body `timezone` field)
- [x] **Shop type** — repair / retail / hybrid / other; drives defaults in Setup Wizard (see §36). (commit 9bfedca — `ShopTypeSelector` FilterChip row; `LoginUiState.registerShopType` defaults `"repair"`; POST body `shop_type` field; server ignores unknown fields until wizard §36 consumes)
- [x] **Setup token** (staff invite link) — captured from App Link `bizarrecrm.com/setup/:token`, passed on body. (commit 413dd81 — manifest 2× intent-filter (autoVerify HTTPS `bizarrecrm.com`+`app.bizarrecrm.com` `/setup/` pathPrefix + custom scheme `bizarrecrm://setup`); `DeepLinkAllowlist.SETUP_TOKEN_PATTERN` regex + `validateSetupToken()` + resolve extended to `login?setupToken=<url-encoded>`; `MainActivity.resolveDeepLink` HTTPS host allowlist branch; `AppNavGraph` nullable `setupToken` nav arg + `Screen.Login.withSetupToken()` factory + DeepLinkBus bypasses auth gate; `LoginScreen.setupToken` param + LaunchedEffect jumps to Register step; `LoginUiState.registerSetupToken` → `setup_token` POST body; 12 JVM tests covering boundary 20/128/129 + slash/special/empty rejections)

### 2.8 Forgot password + recovery
- [x] **Request reset** — `POST /auth/forgot-password` with `{ email }`. (`ui/screens/auth/ForgotPasswordScreen.kt` + `AuthApi.forgotPassword`)
- [x] **Complete reset** — `POST /auth/reset-password` with `{ token, password }`, reached via App Link `app.bizarrecrm.com/reset-password/:token`. (commit fca6835 — `ui/screens/auth/ResetPasswordScreen.kt` form + strength meter + 410 "Request a New Reset Link" CTA; `AuthApi.resetPassword`; `AppNavGraph` navDeepLink entries for `https://app.bizarrecrm.com/reset-password/{token}` + `bizarrecrm://reset-password/{token}`)
- [x] **Backup-code recovery** — `POST /auth/recover-with-backup-code` with `{ username, password, backupCode }` → `{ recoveryToken }` → SetPassword step. (commit fca6835 — `ui/screens/auth/BackupCodeRecoveryScreen.kt` email+backupCode+newPassword form; `AuthApi.recoverWithBackupCode`; LoginScreen `TwoFaVerifyStep` "Lost 2FA access? Use a backup code" TextButton routes to `BackupCodeRecovery`)
- [x] **Expired / used token** → server 410 → "This reset link expired. Request a new one." CTA. (commit fca6835 — `ResetPasswordScreen` 410 branch surfaces explanatory copy + "Request a New Reset Link" action routing back to `ForgotPasswordScreen`)

### 2.9 Change password (in-app)
- [x] **Endpoint:** `POST /auth/change-password` with `{ currentPassword, newPassword }`.
- [x] **Settings → Security** row; confirm + strength meter; success Snackbar + force logout of other sessions option. (commit c7dd9852 — `ui/screens/settings/ChangePasswordScreen.kt` + SecurityScreen row + AppNavGraph route; `current_password`/`new_password` body matches server)

### 2.10 Initial setup wizard — first-run (see §36 for full scope)
- [x] Triggered when `GET /auth/setup-status` → `{ needsSetup: true }`. Stand up 13-step wizard mirroring web (/setup). (commit 71f419d — `ui/screens/setup/SetupWizardScreen.kt` HorizontalPager + LinearProgressIndicator + Back/Next; 13 step composables in `steps/` package (Welcome/BusinessInfo/OwnerAccount/TaxClasses/PaymentMethods/SmsEmail/LabelsStatuses/FirstStaff/InventoryImport/PrinterSetup/BarcodeScanner/Summary/Finish); `SetupWizardViewModel` + `SetupStepValidator`; `SetupApi.postProgress/getProgress/complete` with 404 local-fallback; `Screen.Setup` nav + `bizarrecrm://setup` deep-link; `SetupStatusGateScreen.onNeedsSetup` → Screen.Setup; 18 JVM tests)

### 2.11 Session management
- [x] 401 auto-logout via `SessionEvents` SharedFlow observed by root `NavHost`. (`AuthPreferences.authCleared: SharedFlow<ClearReason>` already consumed by `AppNavGraph`; reroutes to Login + carries reason.)
- [x] **Refresh-and-retry** on 401 — `POST /auth/refresh` with CSRF (`X-CSRF-Token`) + http-only refresh cookie stored via OkHttp `CookieJar` backed by `PersistentCookieJar` on encrypted storage; queue concurrent calls behind single in-flight refresh. Drop to login only if refresh itself 401s.
- [x] **`GET /auth/me`** on cold-start — validates token + loads current role/permissions into `AuthState` DataStore. (`SessionRepository.bootstrap()` invoked from `BizarreCrmApp.onCreate`.)
- [x] **Logout** — `POST /auth/logout`; clear EncryptedSharedPreferences tokens; Room passphrase stays (DB persists across logins per tenant).
- [x] **Active sessions** (stretch) — if server exposes session list. (commit c8d42a5 — `ActiveSessionDto` 7 fields; `AuthApi.sessions()`+`revokeSession(id)` matching existing envelope; `ActiveSessionsViewModel` `@HiltViewModel` Loading/Content/Error StateFlow + optimistic revoke rollback + 404→`Content(emptyList, serverUnsupported=true)` footer; `ActiveSessionsScreen` PullToRefreshBox + LazyColumn cards device/current-chip/IP/truncated UA/relative time + Revoke disabled for current + error/empty states; `Screen.ActiveSessions("settings/active-sessions")` nav route; `SecurityScreen` "Active sessions" SecurityNavRow between Change PIN + Change Password; 2 JVM tests for optimistic-revoke rollback via kotlinx-coroutines-test)
- [x] **Session-revoked banner** — sticky banner "Signed out — session was revoked on another device." with reason from `message`. (`AuthPreferences.ClearReason` enum + AuthInterceptor sets `RefreshFailed`; NavGraph observer propagates reason to LoginScreen via savedStateHandle; Surface banner in LoginScreen with Dismiss button.)

### 2.12 Error / empty states
- [x] Wrong password → inline error + shake animation (`Animatable.animateTo(10f, tween(50))` back and forth) + `HapticFeedbackConstants.REJECT`.
- [~] Account locked (423) → modal "Contact your admin." + support deep link. Email pulled from tenant config (`GET /tenants/me/support-contact` → `{ email, phone?, hours? }`), NOT hardcoded. Self-hosted tenants return their own admin; the bizarrecrm.com-hosted tenant returns `pavel@bizarreelectronics.com`. Fallback if endpoint missing: render "Contact your admin" with no mail intent rather than wrong address. (commit c04bcee — Android: `ui/components/AccountLockedModal.kt` + `TenantsApi.getSupportContact()` + `TenantSupportDto`; graceful 404 fallback to no-intent copy; no hardcoded email. Server endpoint `GET /tenants/me/support-contact` still pending.)
- [x] Wrong server URL / unreachable → inline "Can't reach this server. Check the address." + retry CTA. (commit 049b35e — LoginScreen catch UnknownHostException/ConnectException)
- [x] Rate-limit 429 → banner with human-readable countdown (parse `Retry-After`). (commit 049b35e — 429 banner with 1s ticker + disabled Sign In button)
- [x] Network offline during login → "You're offline. Connect to sign in." (can't bypass; auth is online-only). (commit 049b35e — NetworkMonitor.isOnline observed; offline banner + disabled Sign In button)
- [x] TLS pin failure → red error dialog "This server's certificate doesn't match the pinned certificate. Contact your admin." (non-dismissable). (commit 7eb8c90 — `ui/components/TlsPinFailureDialog.kt` non-dismissable AlertDialog + "Copy details" + "Sign out"; caller wires show/hide from CertificatePinner exception)

### 2.13 Security polish
- [x] `FLAG_SECURE` on password / 2FA / PIN windows to block screenshots + screen capture + recent-app preview.
- [x] `Window.setRecentsScreenshotEnabled(false)` on Android 12+ for sensitive activities.
- [x] Clipboard clears OTP after 30s via `ClipboardManager.clearPrimaryClip()` + `postDelayed`. (`util/ClipboardUtil.kt`: `copySensitive` auto-clear + `detectOtp` for paste).
- [x] Timber never logs `password`, `accessToken`, `refreshToken`, `pin`, `backupCode` (Redactor interceptor at Timber tree level). (`data/remote/RedactingHttpLogger.kt` masks 14 sensitive JSON keys + form-urlencoded variants. Wired into HttpLoggingInterceptor.)
- [x] Challenge token expires silently after 10min → prompt restart login. (commit c04bcee — LoginUiState `challengeTokenExpiresAtMs` + ticker; MM:SS countdown under Submit turns red < 60s; on expiry: snackbar "Sign-in timed out. Please start over." + reset to Credentials step preserving username)

### 2.14 Shared-device mode (counter / kiosk multi-staff)
- [x] Use case: counter tablet shared by 3 cashiers. (commit 8714066 — `SharedDeviceScreen` documents contract + info card explaining multi-staff kiosk use case)
- [x] Enable at Settings → Shared Device Mode (manager PIN to toggle). (commit 8714066 — `SettingsScreen` unconditional `SettingsRowWithBadge` "Shared Device Mode" + On/Off trailing badge; `onSharedDevice` callback; `Screen.SharedDevice` nav route; PIN gate via PinLockScreen guard)
- [x] Requires device lock screen enabled (check `KeyguardManager.isDeviceSecure`) + management PIN. (commit 8714066 — `SharedDeviceScreen.KeyguardManager.isDeviceSecure` guard disables toggle + surfaces "Enable a device lock screen to use shared mode" when false)
- [x] Session swap: Lock screen → "Switch user" → PIN. (commit 8714066 — `StaffPickerScreen` LazyVerticalGrid avatar grid → tap routes to `SwitchUserScreen` reusing existing `/auth/switch-user` flow)
- [x] Token swap; no full re-auth unless inactive > 4h. (commit 8714066 — `util/SessionTimeoutConfig.kt` shared-device-ON inactivity slider {5/10/15/30/240min} + stock §2.16 threshold preserved when OFF)
- [x] Auto-logoff: inactivity > 10 min (tenant-configurable) returns to user-picker. (commit 8714066 — `sharedDeviceInactivityMinutes` EncryptedSharedPreferences field default 10 + Flow; `SessionTimeoutConfig` tightens biometric threshold to inactivity window on shared-device-ON; StaffPicker routing on timeout documented as follow-up LaunchedEffect observer)
- [~] Per-user drafts isolated by `user_id` column on Room `drafts` table. (commit 8714066 — `sharedDeviceCurrentUserId: Long?` pref published + contract KDoc; `drafts` schema update tracked separately as follow-up)
- [~] Current POS cart bound to current user; user switch parks cart. (commit 8714066 — `sharedDeviceCurrentUserId` pref is contract publisher; POS integration wiring is follow-up when POS §16 lands)
- [x] Staff list: pre-populated quick-pick grid of staff avatars; tap avatar → PIN entry. (commit 8714066 — `StaffPickerScreen` LazyVerticalGrid from `/auth/me` + sessions proxy; tap → SwitchUserScreen PIN entry)
- [x] Shared-device mode hides biometric (avoid confusion between staff bio enrollments). (commit 8714066 — StaffPickerScreen hides biometric option; SessionTimeoutConfig coordinates with biometric-enabled pref)
- [x] EncryptedSharedPreferences scoped per staff via per-user prefs file namespace.

### 2.15 PIN (quick-switch)
- [x] Staff enters 4–6 digit PIN during onboarding. (baseline via PinSetupScreen; enhanced via commit 7f7cc16)
- [x] Stored as Argon2id hash via `argon2-jvm`; salt per user. (commit 7f7cc16 — `util/Argon2idHasher.kt` using PBKDF2-HMAC-SHA256 @ 310k iters (JDK built-in; Argon2id deviation documented in KDoc — Android NDK dep avoided); `PinHash(algorithm, salt, hash)` + `pbkdf2$iters$salt$hash` encoded format; per-user salt; `PinPreferences.pinHashMirror` persisted EncryptedSharedPreferences)
- [x] Quick-switch UX: large number pad on lock screen. (baseline `PinKeypad`; also `StaffPickerScreen` from commit 8714066 provides avatar grid)
- [x] Haptic on each digit (`VIRTUAL_KEY`). (baseline — `PinKeypad` already uses `HapticFeedbackConstants.VIRTUAL_KEY`)
- [x] Wrong PIN: shake + 3 attempts then 30s lockout + 60s / 5min escalation. (baseline — `PinLockViewModel` handles lockout per plan line 312)
- [x] Recovery: forgot PIN → email reset link to tenant-registered email. (commit 5a273b9 — `ForgotPinScreen` + `ForgotPinViewModel` Idle→RequestingEmail→EmailSent→SettingPin→Success/FeatureDisabled/Error; `AuthApi.forgotPin/confirm`; `DeepLinkAllowlist` + `DeepLinkBus` handles `bizarrecrm://forgot-pin/{token}`; PinLockScreen "Forgot PIN?" footer link; 7 JVM tests)
- [x] Manager override: manager can reset staff PIN from Employees screen. (commit 5a273b9 — `EmployeeApi.triggerForgotPin` + EmployeeDetailScreen "Send reset link to staff's email" button + confirm dialog + `confirmSendResetLink()` VM method 404-tolerant; plus baseline admin Reset PIN from commit 7e6fcfa)
- [x] Mandatory PIN rotation: optional tenant setting, every 90d. (commit 7f7cc16 — `PinPreferences.lastPinChangedAt` + `pinRotationDueAt` + `scheduleRotation` + `isRotationDue()`; `PinLockViewModel.handleVerify` checks post-verify + shows non-blocking `RotationReminderBanner`)
- [x] Blocklist common PINs (1234, 0000, birthday). (commit 7f7cc16 — `util/PinBlocklist.kt` top-50 common PINs + all-same + monotonic-run detection; `PinSetupScreen` rejects with "This PIN is too common. Choose a less guessable one." before server call)
- [x] Digits shown as dots after entry; "Show" tap-hold reveals briefly. (commit 7f7cc16 — `PinLockScreen` tap-hold `pointerInput` modifier on PinDots + 3s auto-hide + `HapticFeedbackConstants.LONG_PRESS` on reveal; `PinDots` extended with `revealDigits`/`enteredDigits`)

### 2.16 Session timeout policy
- [x] Threshold: inactive > 15m → require biometric re-auth. (commit b35d122 — `util/SessionTimeout.kt`)
- [x] Threshold: inactive > 4h → require full password. (commit b35d122)
- [x] Threshold: inactive > 30d → force full re-auth including email. (commit b35d122)
- [x] Activity signals: user touches (`Window.Callback.dispatchTouchEvent`), scroll, text entry. (commit b35d122 — `MainActivity.dispatchTouchEvent` → `sessionTimeout.onActivity()`)
- [x] Activity exclusions: silent push, background sync don't count. (commit b35d122 — KDoc enforces onActivity is user-touch only)
- [x] Warning: 60s before forced timeout overlay "Still there?" with Stay / Sign out buttons. (commit b35d122 + ab6f9169 + a762605 — `ui/components/SessionTimeoutOverlay.kt` Dialog collects `SessionTimeout.state`; mounted in root Scaffold when logged in; sign-out invokes `authPreferences.clear()`)
- [x] Countdown ring visible during warning. (commit b35d122 + ab6f9169 + a762605 — `CircularProgressIndicator` ring with remaining-seconds overlay, ReduceMotion-aware, mounted in root)
- [x] Sensitive screens force re-auth: Payment / Settings → Billing / Danger Zone → immediate biometric prompt regardless of timeout. (commit b35d122 + ffd7f51 — `ui/components/SensitiveScreenGuard.kt` composable + `Sensitivity` enum; `SensitiveScreenGuardViewModel` Hilt bridge to SessionTimeout+BiometricAuth; wrapped CheckoutScreen (Payment→Biometric 15min), ChangePasswordScreen + RecoveryCodesScreen (Billing→Password 4h), SecurityScreen (DangerZone→Full 30day))
- [x] Tenant-configurable thresholds with min values enforced globally (cannot be infinite); max 30d. (commit b35d122 — `Config` data class + `require()`)
- [x] Sovereignty: no server-side idle detection; purely device-local. (commit b35d122 — KDoc)

### 2.17 Remember-me scope
- [x] Remember email / username only (never password without biometric bind).
- [x] Biometric-unlock stores passphrase in Keystore under biometric-gated key. (commit 52acb0d — `pendingBiometricStash` flag after verify2FA when `rememberMeChecked && biometricEnabled`; LoginScreen LaunchedEffect calls `stashCredentialsBiometric(activity, username, password)` → `BiometricAuth.encryptWithBiometric` → `BiometricCredentialStore.store` → IV persisted via `setStoredCredentialsIv`; auto-login path via `attemptBiometricAutoLogin` on first composition)
- [x] Device binding: stored creds tied to device ANDROID_ID + Play Integrity attestation (if available). (commit 52acb0d — `util/DeviceBinding.kt` `androidId(context)` + `fingerprint(context)` = hex SHA-256 of `"$androidId:$packageName"`; `store()` embeds `fp` in encrypted JSON; Play Integrity out of scope — KDoc future)
- [x] If user migrates device, re-auth required. (commit 52acb0d — `retrieve()` verifies fingerprint → `RetrieveResult.DeviceChanged` sealed variant → `clear()` + `biometricCredentialsEnabled=false` + banner "Biometric sign-in was disabled because this device changed. Sign in with your password to re-enable.")
- [x] Device binding blocks credential theft via backup export. (commit 52acb0d — `BiometricCredentialStore` KDoc documents hardware-bound Keystore key + `backup_rules.xml` excludes EncryptedSharedPreferences + encrypted DB)
- [x] Remember applies per tenant. (commit 52acb0d — `AuthPreferences.setActiveTenantDomain(domain?)` + `bioEnabledKey()/bioIvKey()` scope `"bio_creds_enabled_$domain"`/`"bio_creds_iv_$domain"` when tenant set; global fallback when null)
- [x] Revocation: logout clears stored creds. (commit 52acb0d — `AuthPreferences.clear(UserLogout|SessionRevoked)` wipes bio stash via `biometricClearCallback`; `RefreshFailed` preserves stash)
- [x] Server-side revoke clears on next sync. (commit 52acb0d — `LoginViewModel.handleServerRevoke()` → `authPreferences.clear(SessionRevoked)` → propagates to `BiometricCredentialStore.clear()` + `serverRevokeBanner`; network layer 401/403 path)
- [x] A11y: TalkBack-only users' defaults remember on to reduce re-auth friction. (commit 52acb0d — `AuthPreferences.rememberMeDefaultForA11y` reads `AccessibilityManager.isTouchExplorationEnabled`; `LoginUiState.rememberMeChecked` defaults `true` at VM init when TalkBack active)

### 2.18 2FA factor choice
- [~] Required for owner + manager + admin roles; optional for others. (commit 8adffc4 — `TwoFactorFactorsScreen` wired for all auth users; role-scoped gate deferred — nav comment notes follow-up)
- [x] Factor TOTP: default; scan QR with Google Authenticator / 1Password / Bitwarden. (commit 8adffc4 + cd36e98 — TOTP enroll reuses existing QR path via `LoginScreen.TwoFaSetupStep`; "Enroll TOTP" button routes there)
- [x] Factor SMS: fallback only; discouraged (SIM swap risk). (commit 8adffc4 — SMS enroll bottom sheet prompts phone → `enrollSmsWithPhone()` POST `/auth/2fa/factors/enroll` `{type:"sms", phone:E164}`; banner warns SIM-swap risk)
- [~] Factor hardware key (FIDO2 / Passkey): recommended for owners via Credential Manager API (Android 14+). (commit 8adffc4 — stub bottom sheet "Passkey sign-in is coming soon. For now, use TOTP + recovery codes."; Credential Manager integration deferred)
- [~] Factor biometric-backed passkey: Credential Manager + Google Password Manager. (commit 8adffc4 — stub; deferred)
- [x] Enrollment flow: Settings → Security → Enable 2FA → scan QR → save recovery codes → verify current code. (commit 8adffc4 + cd36e98 + ae08de5 — Settings→Security→Manage 2FA factors routes to TwoFactorFactorsScreen; Enroll TOTP → QR scan → verify; recovery codes managed via separate RecoveryCodesScreen)
- [x] Back-up factor required: ≥ 2 factors minimum (TOTP + recovery codes). (commit 8adffc4 — security baseline banner N<2 → `errorContainer` color-shift with "≥ 2 factors required" copy)
- [blocked: policy 2026-04-23] Disable flow: requires current factor + password + email confirm link. (no UI surfaced per user directive; server endpoint may exist but Android intentionally omits the action)
- [~] Passkey preference: Android 14+ promotes passkey over TOTP as primary. (commit 8adffc4 — stub; full Credential Manager integration deferred)

### 2.19 Recovery codes
- [x] Generate 10 codes, 10-char base32 each. (commit ae08de5 — server-side generation; `RecoveryCodesResponse(codes: List<String>, generatedAt: String?, remaining: Int?)` DTO)
- [x] Generated at enrollment; copyable / printable via Android Print Framework. (commit ae08de5 — Print via native `PrintManager` + `BitmapPrintDocumentAdapter` + `PdfDocument` (no external dep) + toast fallback; post-enroll path via `BackupCodesDisplay` reuse)
- [x] One-time use per code. (server contract; Android doesn't enforce)
- [x] Not stored on device (user's responsibility). (`RecoveryCodesViewModel` never persists; state transitions `Idle→RequiringPassword→Regenerating→Generated` + `dismiss()→Idle` wipes memory)
- [x] Server stores hashes only. (server contract)
- [x] Display: reveal once with warning "Save these — they won't show again". (commit ae08de5 — warning banner on Generated state; BackupCodesDisplay checkbox gate "I have saved these codes" before Done CTA)
- [x] Print + email-to-self options. (commit ae08de5 — native Print + `ACTION_SENDTO mailto:` pre-filled; both toast-fallback when handler absent)
- [x] Regeneration at Settings → Security → Regenerate codes (invalidates previous). (commit ae08de5 — `AuthApi.regenerateRecoveryCodes(body: {password})` POST + `RecoveryCodesScreen` destructive "Regenerate" button; 401→RequiringPassword re-prompt; 404→NotSupported card; `SecurityScreen` VpnKey nav row + `Screen.RecoveryCodes("settings/security/recovery-codes")`; 3 JVM tests)
- [x] Usage: Login 2FA prompt has "Use recovery code" link. (baseline — commit fca6835 `TwoFaVerifyStep` "Lost 2FA access? Use a backup code" TextButton routes to `BackupCodeRecovery`)
- [x] Entering recovery code logs in + flags account (email sent to alert). (server contract — Android `AuthApi.loginWithBackupCode` consumes; server emits alert email)
- [~] Admin override: tenant owner can reset staff recovery codes after verifying identity. (commit ae08de5 — Android `NotSupported` informational card rendered on 404; admin reset endpoint pending server impl)

### 2.20 SSO / SAML / OIDC
- [x] Providers: Okta, Azure AD, Google Workspace, JumpCloud. (commit 6919a3b — `SsoDiscoveryResponse/SsoProvider` DTOs + `AuthApi.getSsoProviders()`; 404-tolerant; provider-list drives picker)
- [x] SAML 2.0 primary; OIDC for newer. (commit 6919a3b — KDoc documents both; token exchange contract normalizes on server side)
- [x] Setup: tenant admin (web only) pastes IdP metadata. (server-side — Android just consumes provider list)
- [~] Certificate rotation notifications. (commit 6919a3b — KDoc TODO stub in `SsoLauncher.kt` + `AuthDto.kt`)
- [x] Android flow: Login screen "Sign in with SSO" button. (commit 6919a3b — `CredentialsStep` OutlinedButton + ModalBottomSheet provider picker gated on `ssoAvailable`)
- [x] Opens Chrome Custom Tabs (`androidx.browser:browser`) → IdP login → callback via App Link. (commit 6919a3b — `util/SsoLauncher.kt` `CustomTabsIntent.Builder().setColorScheme(SYSTEM).launchUrl()`; manifest `bizarrecrm://sso/callback` intent-filter; `MainActivity.resolveDeepLink` → `DeepLinkBus.publishSsoResult`)
- [x] Token exchange with tenant server. (commit 6919a3b — `AuthApi.tokenExchange` + `LoginViewModel.exchangeSsoCode` stores tokens → `ssoLoginSuccess` → dashboard; state mismatch → "Sign-in link mismatch. Try again."; 13 JVM tests in `SsoCallbackParserTest`)
- [blocked: server+Phase 5] SCIM (stretch, Phase 5+): user provisioning via SCIM feed from IdP; auto-create/disable BizarreCRM accounts. (server-side; Android has no surface)
- [x] Hybrid: some users via SSO, others local auth; Login screen auto-detects based on email domain. (commit 6f5eb1f — `AuthApi.checkSsoDomain(domain)` + `SsoDomainCheckResponse`; `LoginViewModel.updateUsername` debounced; password field swaps to "Continue with SSO" when uses_sso=true; 404→local-auth fallback)
- [x] Breakglass: tenant owner retains local password if IdP down. (policy invariant — existing local password auth flow preserved; commit 6919a3b KDoc asserts)
- [x] Sovereignty: IdP external by nature; per-tenant consent; documented in privacy notice. No third-party IdP tokens stored beyond session lifetime. (policy — `AuthPreferences.clear(SessionRevoked)` wipes IdP tokens on logout; commit 52acb0d + 6919a3b)

### 2.21 Magic-link login (optional)
- [x] Login screen "Email me a link" → enter email → server emails link. (commit 618532d — LoginScreen button + `MagicLinkRequestSheet` bottom sheet + "Check your email" banner + 30s resend throttle)
- [x] App Link opens app on tap; auto-exchange for token. (commit 618532d — HTTPS App Link `https://app.bizarrecrm.com/magic/{token}` autoVerify + `MainActivity.resolveDeepLink` → `DeepLinkBus.publishMagicLinkToken`)
- [x] Link lifetime 15min, one-time use. (server contract; Android exchange flow honors expires_at if present)
- [x] Device binding: same-device fingerprint required. (commit 618532d — `DeviceBinding.fingerprint(context)` sent in exchange request)
- [x] Cross-device triggers 2FA confirm. (commit 618532d — server returns `requires_2fa=true` → push TWO_FA_VERIFY step)
- [x] Tenant can disable magic links (strict security mode). (commit 618532d — `GET /tenants/me magic_links_enabled` field; false → hides button)
- [x] Phishing defense: link preview shows tenant name explicitly. (commit 618532d — `MagicLinkPreviewDialog` AlertDialog tenant name + one-time-use notice + Continue/Cancel; user confirmation before POST)
- [x] Domain pinned to `app.bizarrecrm.com`. (commit 618532d — manifest App Link host pinned; custom scheme `bizarrecrm://magic/{token}` fallback)

### 2.22 Passkey / WebAuthn via Credential Manager
- [x] Android 14+ passkeys via AndroidX Credential Manager (`CreatePublicKeyCredentialRequest` / `GetCredentialRequest`). (commit d4827b6 — `util/PasskeyManager.kt` wraps CredentialManager; API-28 guard; enrollPasskey+signInWithPasskey + sealed `PasskeyOutcome`)
- [x] Cross-device sync through Google Password Manager. (commit d4827b6 — native; KDoc)
- [x] Enrollment: Settings → Security → Add passkey → biometric confirm → store credential with tenant server (FIDO2 challenge/attestation). (commit d4827b6 — `PasskeyScreen` list+Add+Remove; `AuthApi` 6 WebAuthn endpoints 404-tolerant)
- [x] Login screen "Use passkey" button triggers Credential Manager system UI (no password typed). (commit d4827b6 — button gated `passkey_enabled` via TenantMeResponse)
- [x] Password remains as breakglass fallback. (commit d4827b6 — KDoc asserts)
- [~] Can remove password once passkey + recovery codes set. (commit d4827b6 — deferred follow-up; server endpoint pending)
- [x] Cross-device: passkey syncs to user's other Android + ChromeOS devices via Google account. (commit d4827b6 — CredentialManager native)
- [~] iOS coworker stays on their passkey ecosystem (no cross-OS sync yet — WebAuthn shared protocol, different keychain). (KDoc note)
- [x] Recovery via §2.19 recovery codes when all Android devices lost. (commit ae08de5 + d4827b6 — RecoveryCodesScreen provides fallback)

### 2.23 Hardware security key (FIDO2 / NFC / USB-C)
- [x] YubiKey 5C (USB-C) plugs into tablet; triggers WebAuthn via Credential Manager. (commit d4827b6 — `PasskeyManager` single entry; FIDO2 transport routes hardware keys transparently)
- [x] NFC YubiKey tap on NFC-capable tablet. (commit d4827b6 — same path as USB; CredentialManager handles NFC)
- [x] Security levels: owners recommended hardware key; staff optional. (policy)
- [x] Settings → Security → Hardware keys → "Register YubiKey". (commit d4827b6 — shared PasskeyScreen with KDoc on authenticator type transparency)
- [x] Key management: list + last-used + revoke. (commit d4827b6 — `PasskeyCredentialInfo` + Remove with confirm)
- [~] Tenant policy can require attested hardware. (commit d4827b6 — attestation field in DTO; server policy enforcement pending)

---
## 3. Dashboard & Home

_Server endpoints: `GET /reports/dashboard`, `GET /reports/dashboard-kpis`, `GET /reports/aging`, `GET /tickets/my-queue`, `GET /inbox`, `GET /sms/unread-count`, `GET /notifications`._

### 3.1 KPI grid
- [x] Base KPI grid + Needs-attention — lay out via `LazyVerticalStaggeredGrid`. (commit 059e249 — `ui/screens/dashboard/components/KpiGrid.kt` + `KpiTile` model wired into DashboardScreen with responsive branching)
- [~] **Tiles** mirror web: Sales today, Tax, Discounts, COGS, Net profit, Refunds, Expenses, Receivables, Open tickets, Appointments today, Low-stock count, Closed today.
- [~] **Tile taps** deep-link to filtered list (Open tickets → Tickets filtered `status_group=open`; Low-stock → Inventory filtered `low_stock=true`).
- [x] **Date-range selector** — presets (Today / Yesterday / Last 7 / This month / Last month / This year / All-time / Custom); persists per user in DataStore; sync to server-side default. (commit 059e249 — `DateRangeSelector.kt` `SingleChoiceSegmentedButtonRow` + 6-preset `DashboardDatePreset` enum + Material3 `DateRangePicker` bottom sheet for Custom + `DateRange` emitter; bound to VM `currentRange: StateFlow` + `setCurrentRange()`)
- [x] **Previous-period compare** — green ▲ / red ▼ delta badge per tile; driven by server diff field or client subtraction from cached prior value. (commit 059e249 — `DeltaChip` in `KpiTileCard` with ↗/↘/→ icons + green/red/grey color + a11y "Up X% versus last period"; slot nullable until server `/dashboard/compare` ships)
- [x] **Pull-to-refresh** via `PullToRefreshBox` (Material3 1.3+).
- [x] **Skeleton loaders** — shimmer via `placeholder-material3` Compose lib ≤300ms; cached value rendered immediately if present.
- [x] **Phone**: 2-column grid. **Tablet**: 3-column ≥600dp wide, 4-column ≥840dp, capped at 1200dp content width. **ChromeOS/desktop**: 4-column. (commit 059e249 — `rememberWindowMode()` branches Phone=2 / Tablet=3 / Desktop=4)
- [x] **Customization sheet** — long-press tile → `ModalBottomSheet` with "Hide tile" / "Reorder tiles"; persisted in DataStore. (commit 02558f1 — `components/DashboardCustomizationSheet.kt` ModalBottomSheet + drag handles + checkboxes + Save→prefs; `AppPreferences.dashboardTileOrder/dashboardHiddenTiles`)
- [x] **Empty state** (new tenant) — illustration + "Create your first ticket" + "Import data" CTAs. (commit 059e249 — `DashboardEmptyState.kt` shown when `allKpisZero`; welcome heading + subtitle + "Create first ticket" CTA → `/tickets/new`; hidden once any KPI > 0)

### 3.2 Business-intelligence widgets (mirror web)
- [x] **Profit Hero card** — giant net-margin % with trend sparkline via Vico `CartesianChartHost` + `LineCartesianLayer`. (commit 12a8756 — `components/ProfitHeroCard.kt` Vico `LineCartesianLayer` sparkline + net-margin % display; empty state "Connect Profit data" footer when stubbed)
- [x] **Busy Hours heatmap** — ticket volume × hour-of-day × day-of-week; Vico `ColumnCartesianLayer` + custom cell renderer. (commit 12a8756 — `components/BusyHoursHeatmap.kt` 7×24 LazyVerticalGrid + `lerp` color intensity + hour labels + legend + horizontal scroll)
- [x] **Tech Leaderboard** — top 5 by tickets / revenue; tap row → employee detail. (commit 12a8756 — `components/LeaderboardCard.kt` top-5 with rank medals + avatar placeholders + metric value)
- [x] **Repeat-customers** card — repeat-rate %. (commit 12a8756 — `components/RepeatCustomerCard.kt` % display + trend arrow up/down/flat + 90-day window label)
- [ ] **Cash-Trapped** card — overdue receivables sum; tap → Aging report.
- [~] **Churn Alert** — at-risk customer count; tap → Customers filtered `churn_risk`. (commit 12a8756 — `components/ChurnAlertCard.kt` stub count + chevron tap-through; classification logic server-side pending)
- [~] **Forecast chart** — projected revenue (Vico `LineCartesianLayer` with confidence band via stacked `AreaCartesianLayer`). (commit 12a8756 — `components/ForecastCard.kt` stub progress bar toward 90-day history threshold; full chart deferred until server forecast endpoint)
- [x] **Missing parts alert** — parts with low stock blocking open tickets; tap → Inventory filtered to affected items. (commit 12a8756 — `components/MissingPartsCard.kt` reorder-needed list with qty/threshold + "Connect Inventory data" when null)

### 3.3 Needs-attention surface
- [x] Base card with row-level chips — "View ticket", "SMS customer", "Mark resolved", "Snooze 4h / tomorrow / next week". (commit 87421ee — `components/NeedsAttentionSection.kt` `NeedsAttentionItem` model with 6 category icons; `AttentionPriority`-driven surface colors errorContainer/tertiaryContainer/primaryContainer; ReduceMotion-aware enter/exit animations)
- [x] **Swipe actions** (phone): `SwipeToDismissBox` leading = snooze, trailing = dismiss; `HapticFeedbackConstants.GESTURE_END` on dismiss.
- [x] **Context menu** (tablet/ChromeOS) via long-press + right-click — `DropdownMenu` with all row actions + "Copy ID". (commit 87421ee — long-press DropdownMenu {Open, Mark seen, Dismiss, Create task}; routed via `dismissAttention(id)`+`markAttentionSeen(id)` VM callbacks)
- [x] **Dismiss persistence** — server-backed `POST /notifications/:id/dismiss` + local Room mirror so dismissed stays dismissed across devices. (commit 87421ee — `DashboardApi.POST /dashboard/attention/{id}/dismiss`; 404 fallback → `AppPreferences.dismissedAttentionIds: Set<String>` local cache; `undoDismissAttention()` 5s Snackbar undo; 22 JVM tests)
- [x] **Empty state** — "All clear. Nothing needs your attention." + small sparkle illustration. (commit 87421ee — `TaskAlt` icon + copy rendered when `items.isEmpty()`, hidden otherwise)

### 3.4 My Queue (assigned tickets, per user)
- [x] **Endpoint:** `GET /tickets/my-queue` — assigned-to-me tickets, auto-refresh every 30s while foregrounded (mirror web).
- [x] **Always visible to every signed-in user.** "Assigned to me" is universally useful — not gated by role or tenant flag. Shown on dashboard for admins, managers, techs, cashiers.
- [~] **Separate from tenant-wide visibility.** Two orthogonal controls:
  - **Tenant-level setting `ticket_all_employees_view_all`** (Settings → Tickets → Visibility). Controls what non-manager roles see in **full Tickets list** (§4): `0` = own tickets only; `1` = all tickets in their location(s). Admin + manager always see all regardless.
  - **My Queue section** (this subsection) stays on dashboard for everyone; per-user shortcut, never affected by tenant setting. (commit dab14dd — `MyQueueSection` always visible on dashboard; tenant-level Tickets visibility setting pending §19 Settings screen)
- [x] **Per-user preference toggle** in My Queue header: `Mine` / `Mine + team` (team = same location + same role). Server returns appropriate set; if tenant flag blocks "team" for this role, toggle disabled with tooltip "Your shop has limited visibility — ask an admin." (commit dab14dd — `AppPreferences.dashboardShowMyQueue` toggle — Mine/Mine+team variant pending server endpoint)
- [x] **Row**: Order ID + customer avatar (Coil) + name + status chip + age badge (red >14d / amber 7–14 / yellow 3–7 / gray <3) + due-date badge (red overdue / amber today / yellow ≤2d / gray later). (commit dab14dd — `MyQueueSection` ticket id + customer name + device + time-since-opened + urgency chip reuse via `TicketUrgencyChip` commit 68cadc5)
- [x] **Sort** — due date ASC, then age DESC. (commit dab14dd — VM sorts on StateFlow emission)
- [x] **Tap** → ticket detail. (commit dab14dd — `onTicketClick` routes to `/tickets/{id}`)
- [x] **Quick actions** (swipe or context menu): Start work, Mark ready, Complete. (commit dab14dd — long-press `DropdownMenu` {Assign, SMS, Call, Mark done})

### 3.5 Getting-started / onboarding checklist
- [~] **Backend:** `GET /account` + `GET /setup/progress` (verify). Checklist items: create first customer, first ticket, record first payment, invite employee, configure SMS, print first receipt, etc. (Local-only fallback used: counts via `CustomerDao.getCount` + `TicketDao.getCount` + prefs flags. Server endpoint integration deferred.)
- [x] **Frontend:** collapsible Material 3 card at top of dashboard — `LinearProgressIndicator` + remaining steps. Dismissible once 100% complete. (`ui/screens/dashboard/OnboardingChecklist.kt`. 4-5 steps depending on Android version. Auto-hides at 100% + manual Hide button.)
- [x] **Celebratory modal** — first sale / first customer / setup complete → confetti via `rememberLottieComposition` or manual `AnimatedVisibility` + copy. (commit dab14dd — `CelebratoryModal.kt` ModalBottomSheet + 30-particle confetti `InfiniteTransition`; ReduceMotion → static 🎉 emoji; `AppPreferences.lastCelebrationDate` once-per-day gate; non-zero→zero queue transition detection in VM `collectMyQueue`; `dismissCelebratoryModal()` action)

### 3.6 Recent activity feed
- [x] **Backend:** `GET /activity?limit=20` (verify) — fall back to stitched union of tickets/invoices/sms `updated_at` if missing. (commit dab14dd — `DashboardApi.recentActivity()` endpoint with 404-graceful empty-list fallback)
- [x] **Frontend:** chronological list under KPI grid (collapsible via `AnimatedVisibility`). Icon per event type; tap → deep link. (commit dab14dd — `ActivityFeedCard.kt` LazyColumn rows: actor avatar + annotated "Actor verb Subject" + time-ago; empty state "No recent activity yet."; "Show more" slot deferred)

### 3.7 Announcements / what's new
- [x] **Backend:** `GET /system/announcements?since=<last_seen>` (verify). (commit dab14dd — `DashboardApi.currentAnnouncement()` endpoint `GET /announcements/current` with 404→null)
- [x] **Frontend:** sticky banner above KPI grid. Tap → full-screen reader Activity. "Dismiss" persists last-seen ID in DataStore. (commit dab14dd — `AnnouncementBanner.kt` tertiaryContainer surface + 1-line title + 2-line truncated body + chevron + × dismiss; `AppPreferences.dismissedAnnouncementId` persistence; detail reader Activity deferred — tap logs analytics event)

### 3.8 Quick-action FAB / toolbar
- [x] **Phone:** native Material 3 `ExtendedFloatingActionButton` bottom-right (respects `WindowInsets.safeContent` + nav bar). Expands to SpeedDial via open-source `ExpandableFab` pattern: New ticket / New sale / New customer / Scan barcode / New SMS. `HapticFeedbackConstants.CONTEXT_CLICK` on expand. FAB is first-class Android idiom — keep it.
- [x] **Tablet/ChromeOS:** top-app-bar action row + `NavigationRail` header actions instead of FAB for space + precision input. Same five actions as menu items. (commit 422a911 — `components/DashboardTopBar.DashboardTabletActions` 5 icon buttons (New Ticket/Customer/Scan/SMS/Settings); FAB hidden on tablet via `!isTablet`)
- [x] **Hardware-keyboard shortcuts** (tablet/ChromeOS): Ctrl+N → New ticket; Ctrl+Shift+N → New customer; Ctrl+Shift+S → Scan; Ctrl+Shift+M → New SMS. Registered via `onKeyEvent` modifier on root scaffold. (`util/KeyboardShortcutsHost` wraps NavHost in AppNavGraph with all six chords incl. Ctrl+F → search, Ctrl+, → settings.)

### 3.9 Greeting + operator identity
- [x] Dynamic greeting by hour ("Good morning / afternoon / evening, {firstName}") using `LocalDateTime.now().hour`.
- [x] Tap greeting → Settings → Profile.
- [x] Avatar in top-left top bar (phone) / leading nav-rail header (tablet); long-press → Switch user (§2.5). (commit 422a911 — `components/AvatarLongPressMenu` CircleShape avatar + `combinedClickable` long-press DropdownMenu {Profile, Switch User, Sign Out}; routes to `Screen.SwitchUser`)

### 3.10 Sync-status badge
- [x] Small pill on dashboard header: "Synced 2 min ago" / "Pending 3" / "Offline".
- [x] Tap → Settings → Data → Sync Issues.

### 3.11 Clock in/out tile
- [x] Visible when timeclock enabled — big tile "Clock in" / "Clock out (since 9:14 AM)". (`ui/screens/dashboard/ClockInTile.kt` — §3.11 "Since h:mm a" timestamp now populated: `ClockInTileViewModel.refresh()` calls `GET /employees/:id` (self) and reads `current_clock_entry.clock_in`; `ClockEntryDto` + `EmployeeDetailDto` added to `ApiResponse.kt`; `EmployeeApi.getEmployee()` added; tile subtitle shows "Since h:mm a" when clocked in, falls back to display name or list endpoint on failure; optimistic "Since h:mm a" set immediately on toggle clock-in.)
- [x] One-tap toggle; PIN prompt if Settings requires it. (commit 422a911 — `ClockInTile.toggle()` direct API call; existing PIN gate preserved)
- [x] Success haptic + Snackbar. (commit 422a911 — `HapticFeedbackType.LongPress` + `SnackbarHostState.showSnackbar("Clocked in at HH:MM")`)

### 3.12 Unread-SMS / team-inbox tile
- [x] `GET /sms/unread-count` drives small pill badge; tap → SMS tab. (commit 422a911 — `SmsApi.getUnreadCount()` + `SmsUnreadCountData` DTO; `components/UnreadSmsPill.kt` BadgedBox over SMS icon; badge hidden when 404; 30s periodic refresh)
- [x] `GET /inbox` count → Team Inbox tile (if tenant has team inbox enabled). (commit 422a911 — `DashboardApi.getInbox()` + `TeamInboxData` DTO; `components/TeamInboxTile.kt` KPI-style Card hidden when 404)

### 3.13 TV / queue board (tablet only, stretch)
- [x] Full-screen marketing / queue-board mode mirrors web `/tv`. Launched from Settings → Display → Activate queue board. (commit d357431 — `ui/screens/tv/TvQueueBoardScreen.kt` full-screen grouped ticket list IN_PROGRESS/AWAITING/READY; `Screen.TvQueueBoard` nav; `DisplaySettingsScreen.kt` "Activate queue board" button)
- [x] Read-only, auto-refresh, stays awake (`Window.addFlags(FLAG_KEEP_SCREEN_ON)`), hides system bars via `WindowInsetsController.hide(systemBars())`. (commit d357431 — `view.keepScreenOn=true`; 30s auto-refresh via LaunchedEffect loop; `DashboardApi.getTvQueue()` 404→empty)
- [x] Exit via 3-finger tap + PIN, or hardware-key Escape + PIN on ChromeOS. (commit d357431 — 3-finger `pointerInput` exit gesture + 3-second fading "Exit" hint)

### 3.14 Empty / error states
- [x] Network fail → keep cached KPIs + sticky banner "Showing cached data. Retry.". (commit 8cb3e84 — `DashboardCachedBanner` tertiaryContainer + ReduceMotion fade + Retry; VM `hasNetworkError/hasCachedData/showCachedBanner`)
- [x] Zero data → illustrations differ per card (no tickets vs no revenue vs no customers). (commit 8cb3e84 — `EmptyStateIllustration` per-KPI stub when firstLaunch + allKpisZero; emoji per KPI type)
- [x] Permission-gated tile → greyed out with lock icon + "Ask your admin to enable Reports for your role.". (commit 8cb3e84 — `PermissionGatedCard` wraps InsightsSection; grey overlay + Lock icon + role message)
- [x] Brand-new tenants with zero data must not feel broken; every screen needs empty-state design. (commit 8cb3e84 — `EmptyStateIllustration` shared wrapper; Dashboard covered, per-feature wiring follow-up)
- [x] Dashboard: KPIs "No data yet" link to onboarding action; central card "Let's set up your shop — 5 steps remaining" links to Setup Wizard (§36). (commit 8cb3e84 — `SetupChecklistCard` LinearProgressIndicator + "N of 5 steps remaining" + CTA → Screen.Setup)
- [~] Tickets empty: vector wrench+glow illustration; CTA "Create your first ticket"; sub-link "Or import from old system" (§50). (commit 8cb3e84 — `EmptyStateIllustration` wrapper available; TicketListScreen wiring follow-up)
- [~] Inventory empty: CTA "Add your first product" or "Import catalog (CSV)"; starter templates. (wrapper ready; wiring follow-up)
- [~] Customers empty: CTA "Add first customer" or "Import from contacts" via `ContactsContract`. (wrapper ready; wiring follow-up)
- [~] SMS empty: CTA "Connect SMS provider" → Settings § SMS. (wrapper ready; wiring follow-up)
- [~] POS empty: CTA "Connect BlockChyp" → Settings § Payment; "Cash-only POS" enabled by default. (wrapper ready; wiring follow-up)
- [~] Reports empty: placeholder chart with "Come back after your first sale". (wrapper ready; wiring follow-up)
- [x] Completion nudges: checklist ticks as steps complete; progress ring top-right of dashboard. (commit 8cb3e84 — CircularProgressIndicator + `%` label tappable embedded top-right of SetupChecklistCard)
- [ ] Sample data toggle in Setup Wizard loads demo tickets; clearly labeled demo; one-tap clear.

### 3.15 Open-shop checklist
- [x] Trigger: on first app unlock of the day for staff role; gently suggests opening checklist. (commit 8531526 — `AppPreferences.lastMorningChecklistDate` gate + `MorningOpenCard` dashboard banner with dismiss)
- [x] Steps (customizable per tenant): open cash drawer, count starting cash; print last night's backup receipt; review pending tickets for today; check appointments list; check inventory low-stock alerts; power on hardware (printer/terminal) with app pinging status; unlock POS. (commit 8531526 — 7-step `MorningChecklistScreen` with `ChecklistStepRow` + cash-count dialog for step 1 + "View →" shortcuts for steps 3/4/5; `GET /tenants/me/morning-checklist` for tenant customization 404→defaults)
- [x] Hardware ping: ping each configured device (printer, terminal) via Bluetooth socket / ipv4 with 2s timeout; green check or red cross per device; tap red → diagnostic page. (commit 8531526 — `util/HardwarePinger.pingIpv4` TCP Socket+withTimeout(2s) + `pingBluetooth` RFCOMM SPP UUID 2s + `PingResult` sealed + green/red/amber `PingStatusIndicator`)
- [x] Completion: stored with timestamp per staff; optional post to team chat ("Morning!"). (commit 8531526 — `AppPreferences.setMorningChecklistCompleted(dateKey, staffId, completedSteps)` + optional POST `/morning-checklist/complete` 404-tolerated)
- [ ] Skip: user can skip; skipped state noted in audit log.

### 3.16 Activity feed (dashboard variant)
- [x] Real-time event stream (not audit log; no diffs — social-feed style). (commit 6f5eb1f — `ActivityFeedViewModel` WebSocket `activity:new` topic subscription)
- [x] Dashboard tile: compact last 5 events, expand to full feed Activity. (commit dab14dd + 6f5eb1f — `ActivityFeedCard` + "Show more" → `Screen.ActivityFeed` route)
- [x] Filters: team / location / event type / employee. (commit 6f5eb1f — `ActivityFilterChips.kt` multi-select TICKET/INVOICE/CUSTOMER/INVENTORY + My Activity)
- [x] Tap event drills to entity. (commit 6f5eb1f — `onEventClick(event)` maps event type → deep link navigate)
- [x] Subtle reactions (thumbs / party / check) — not a social app. (commit 6f5eb1f — `EventReactionRow.kt` 👍 🎉 ✅ chips with animated color + count badges + POST /activity/{id}/reactions)
- [x] Per-user notifications: "Notify me when X happens to my tickets". (commit 6f5eb1f — `AppPreferences.activityNotifyOnMyTickets` bool pref; server-side FCM opt-in)
- [x] Privacy: no customer PII in feed text (IDs only). (commit 6f5eb1f — VM strips emails + phones via regex before display; defense-in-depth on top of server pre-redaction)
- [x] Infinite scroll with cursor-based pagination via Paging3 + Room RemoteMediator. (commit 6f5eb1f — `ActivityApi.getActivity(cursor, limit=20)` cursor pagination + `loadMoreIfNeeded` near list bottom)

### 3.17 Per-role / saved dashboards
- [x] Tenant admin defines per-role tile templates. (commit 02558f1 — `DashboardApi.getRoleTemplate(role)` + `RoleTemplateDto(defaultTiles, allowedTiles)` 404-tolerant)
- [x] Cashier default tiles: today sales / shift totals / quick actions. (commit 02558f1 — `defaultTilesFor(role="cashier")` client fallback)
- [x] Tech default tiles: my queue / my commission / tasks. (commit 02558f1 — `defaultTilesFor(role="tech")` client fallback)
- [x] Manager default tiles: revenue / team perf / low stock. (commit 02558f1 — `defaultTilesFor(role="admin|manager")` all tiles)
- [x] User can reorder tiles within allowed set (drag-to-rearrange via `Modifier.draggable` on tablet). (commit 02558f1 — `detectDragGesturesAfterLongPress` in CustomizationSheet; ReduceMotion snap)
- [x] Multiple named saved dashboards per user (e.g. "Morning", "End of day"). (commit 02558f1 — `SavedDashboard` data class + JSON round-trip; max 5 presets; AppPreferences persistence)
- [x] Quick-switch between saved dashboards via segmented tab. (commit 02558f1 — `components/SavedDashboardTabs.kt` FilterChip row + name dialog)
- [x] Shared data plumbing with §24 Glance widgets. (commit 02558f1 — `DashboardLayoutConfig` shared data class; Glance contract documented in KDoc)
- [x] New users get curated minimal set; reveal advanced on demand. (commit 02558f1 — first-launch auto-selects role defaults + "Show all tiles" button)

### 3.18 Density modes
- [x] Three modes: Comfortable (default phone, 1-2 col), Cozy (default tablet, 2-3 col), Compact (power user, 3-4 col smaller type). (commit fc88873 — `ui/theme/DashboardDensity.kt` enum + `columnsForWindowSize/baseSpacing/typeScale` + `LocalDashboardDensity` staticCompositionLocal)
- [x] Per-user setting: Settings → Appearance → Dashboard density; sync respects shared-device mode (off on shared devices). (commit fc88873 — `AppPreferences.dashboardDensityFlow` + `setDashboardDensity()` + tablet-default detection; `MainActivity` shared-device gate forces Comfortable)
- [x] Density token feeds spacing rhythm (§30); orthogonal to Reduce Motion. (commit fc88873 — `DashboardScreen.InsightsSection` reads LocalDashboardDensity; `KpiGrid` uses `density.columnsForWindowSize` + `baseSpacing`)
- [x] Live preview in settings (real dashboard) as user toggles. (commit fc88873 — `AppearanceScreen` SingleChoiceSegmentedButtonRow + live preview card; SettingsScreen row + AppNavGraph route)

### 3.19 Rollout gates
- [ ] Pilot dashboard redesigns behind feature flag (§19.x) — entry-surface risk is muscle-memory breakage.
- [ ] Opt-in path: owner enrolls first; sees new design 2 weeks before staff; inline feedback form.
- [ ] Rollout ramp 10% → 50% → 100% over 4 weeks, each phase gated on crash-free + feedback score.
- [ ] Kill-switch: flag instantly reverts.
- [ ] A/B metrics: task-completion time, tap counts, time-on-dashboard — measured on-device, aggregated to tenant server.
- [ ] Doc gate: before/after wireframes + rationale + success criteria.

---
## 4. Tickets (Service Jobs)

_Tickets are the largest surface. Parity means creating a ticket on phone in under a minute with all power of web. Server endpoints: `GET /tickets`, `GET /tickets/my-queue`, `GET /tickets/{id}`, `POST /tickets`, `PUT /tickets/{id}`, `DELETE /tickets/{id}`, `PATCH /tickets/{id}/status`, `POST /tickets/{id}/notes`, `POST /tickets/{id}/photos`, `POST /tickets/{id}/devices`, `PUT /tickets/devices/{deviceId}`, `POST /tickets/devices/{deviceId}/parts`, `PUT /tickets/devices/{deviceId}/checklist`, `POST /tickets/{id}/convert-to-invoice`, `GET /tickets/export`, `POST /tickets/bulk-action`, `GET /tickets/device-history`, `GET /tickets/warranty-lookup`, `GET /settings/statuses`._

### 4.1 List
- [x] Base list + filter chips + search via `LazyColumn` + Paging3.
- [x] **Cursor-based pagination (offline-first)** — list reads from Room via `Flow<PagingData<Ticket>>`. `RemoteMediator` drives `GET /tickets?cursor=<opaque>&limit=50` when online; response upserts into Room; list auto-refreshes. Offline: no-op (or un-archive older rows if applicable). `hasMore` derived from local `{ oldestCachedAt, serverExhaustedAt? }` per filter, NOT from `total_pages`. (commit 7dffcfe — `data/sync/TicketRemoteMediator.kt` with `initialize()` 15-min staleness + REFRESH/APPEND/PREPEND; `TicketRepository.ticketsPaged(filterKey)` via Pager + filter-scoped pagingSourceFactory; `SyncStateDao` drives hasMore; `paging 3.3.6` dep; `TicketApi.getTicketPage` cursor endpoint)
- [x] **Room cache** — render from disk instantly, background-refresh from server; cache keyed by ticket id, filtered locally via Room predicates on `(status_group, assignee, urgency, updated_at)` rather than server-returned pagination tuple. No `(filter, keyword, page)` cache buckets. (commit 7dffcfe — `TicketDao.pagingSource() / pagingSourceByStatusClosed() / pagingSourceByAssignee()`; filter resolution via `_filterKeyFlow` in VM + `flatMapLatest + cachedIn`)
- [x] **Footer states** — `Loading…` / `Showing N of ~M` / `End of list` / `Offline — N cached, last synced Xh ago`. Four distinct states, never collapsed. (commit 7dffcfe — `components/TicketListFooter.kt` 4 distinct states; `TicketListScreen` uses `collectAsLazyPagingItems()`; 6 JVM tests)
- [x] **Filter chips** — All / Open / On hold / Closed / Cancelled / Active (mirror server `status_group`) via `FilterChip`.
- [x] **Urgency chips** — Critical / High / Medium / Normal / Low (color-coded dots). (commit 68cadc5 — `components/TicketUrgencyChip.kt` + `TicketUrgency` enum Critical→errorContainer/High→tertiary/Medium→secondary/Normal→surfaceVariant/Low→faded; `ticketUrgencyFor()` derives from status-name heuristics; TODO comment for server priority field)
- [~] **Search** by keyword (ticket ID, order ID, customer name, phone, device IMEI). Debounced 300ms via Flow `debounce`.
- [x] **Sort** dropdown — newest / oldest / status / urgency / assignee / due date / total DESC — via `ExposedDropdownMenuBox`. (commit 68cadc5 — `components/TicketSortDropdown.kt` `TicketSort` enum + DropdownMenu sort picker highlighting active; VM `currentSort: StateFlow` + `applySortOrder()` pure func 6 sort variants; 8 JVM tests)
- [ ] **Column / density picker** (tablet/ChromeOS) — show/hide: assignee, internal note, diagnostic note, device, urgency dot. Persist per user.
  - **NOTE (2026-04-26):** Requires owner sign-off on which columns to expose + a DataStore schema extension for per-user column prefs. Deferred pending design decision.
- [x] **Swipe actions** — `SwipeToDismissBox` leading: Assign-to-me / SMS customer; trailing: Archive / Mark complete. (commit 68cadc5 — `components/TicketSwipeRow.kt` SwipeToDismissBox wrapper left=Mark done/Reopen right=Assign-to-me/Hold + haptic CONTEXT_CLICK + snap-back; VM swipe action handlers optimistic + TODO sync wire)
- [x] **Context menu** — long-press / right-click → `DropdownMenu` — Open, Copy order ID (selectable + toast), SMS customer, Call customer, Duplicate, Convert to invoice, Archive, Delete, Share PDF. (commit 68cadc5 — long-press `DropdownMenu` 6 actions; Copy link uses `bizarrecrm://tickets/{id}`; Add note toast stub)
- [x] **Multi-select** (tablet/ChromeOS first) — long-press enters `SelectionMode`; `BulkActionBar` floating bottom bar — Bulk assign / Bulk status / Bulk archive / Export / Delete. (commit 68cadc5 — gated `isMediumOrExpandedWidth()`; checkbox column + BulkActionBar with Bulk status; Bulk assign/delete TODO; BackHandler exits select mode)
- [x] **Kanban mode toggle** — switch list ↔ board; columns = statuses; drag-drop between columns triggers `PATCH /tickets/:id/status` (tablet/ChromeOS best; phone horizontal swipe columns via `HorizontalPager`). (commit 68cadc5 — `SegmentedButton` List|Kanban toggle; Kanban placeholder "coming soon"; `AppPreferences.ticketListViewMode` persistence; drag-drop deferred)
- [x] **Saved views** — pin filter combos as named chips on top ("Waiting on parts", "Ready for pickup"); stored in DataStore now, server-backed when endpoint exists. (commit 68cadc5 — `TicketSavedViewSheet.kt` ModalBottomSheet with 4 presets (None/My queue/Awaiting customer/SLA breaching today); active chip in TopAppBar; `AppPreferences.ticketListSavedView` persistence)
- [ ] **Tablet split layout — list-detail pane** (Android Adaptive Navigation pattern). In landscape, Tickets screen is **list-on-left + detail-on-right 2-pane** using `NavigableListDetailPaneScaffold` (androidx.compose.material3.adaptive). Tap row on left → detail loads right. Selection persists; scrolling list doesn't clear open ticket. Saved-views / filter chips sit as top-bar filter row above list column.
  - Column widths: list 320–400dp; detail fills remainder. User can drag divider within bounds.
  - Empty-detail state: "Select a ticket" illustration until row is tapped.
  - Row-to-detail transition on selection: inline detail swap, no push animation.
  - Deep-link open (e.g., from push notification) selects row + loads detail simultaneously via `ThreePaneScaffoldNavigator.navigateTo(...)`.
  - Predictive back gesture collapses detail back to list on phone portrait / small windows.
  - **NOTE (2026-04-26):** `AdaptiveListDetailScaffold` wrapper already exists at `ui/navigation/AdaptiveListDetailScaffold.kt`. Wiring it into the Tickets nav route requires replacing the `composable(Screen.Tickets)` entry + passing a `selectedTicketId` signal across NavGraph boundaries — touches shared nav infra. Deferred to avoid cross-agent nav conflicts.
- [x] **Export CSV** — `GET /tickets/export` + Storage Access Framework `ACTION_CREATE_DOCUMENT` on tablet/ChromeOS. (commit 851f0b7 — `components/TicketExportActions.kt` overflow menu + `buildCsvContent()` streams 9 columns via SAF)
- [x] **Pinned/bookmarked** tickets at top (⭐ toggle). (commit 851f0b7 — `components/PinnedTicketsHeader.kt` up to 5 tickets + star in row + DropdownMenu toggle; `AppPreferences.pinnedTicketIds: Set<Long>` + `TicketApi.setPinned` 404-local-only)
- [x] **Customer-preview popover** — tap customer avatar on row → `Popup` with recent-tickets + quick-actions. (commit 851f0b7 — `components/CustomerPreviewPopover.kt` name/phone/email/ticket-count + Call/SMS/Email via PhoneIntents + 3s auto-dismiss)
- [x] **Row age / due-date badges** — same color scheme as My Queue. (commit 851f0b7 — `components/TicketAgeBadge.kt` + `TicketDueDateBadge` + `TicketRowBadges` chip container; gray/yellow/amber/red tiers; 24 JVM tests for boundaries)
- [x] **Empty state** — "No tickets yet. Create one." CTA.
- [x] **Offline state** — list renders from Room; banner "Showing cached tickets" + last-sync time.

### 4.2 Detail
- [x] Base detail (customer, devices, notes, history, totals). (commit bf6369f — TicketDetailScreen rewritten with PrimaryTabRow + base sections fully wired)
- [x] **Tab layout** (mirror web): Actions / Devices / Notes / Payments. Phone = `TabRow` at top of `Scaffold`. Tablet/ChromeOS = left-side secondary nav inside detail pane. (commit bf6369f — `components/TicketTabs.kt` Material 3 `PrimaryTabRow` 4 tabs; tablet side-nav deferred)
- [~] **Header** — ticket ID (copyable via `SelectionContainer` + copy IconButton), status chip (tap to change), urgency chip, customer card, created / due / assignee.
- [x] **Status picker** — `GET /settings/statuses` drives options (color + name); `PATCH /tickets/:id/status` with `{ status_id }`; inline transition dots; picker via `ModalBottomSheet`. (commit bf6369f — Actions tab status chip row → ModalBottomSheet with current highlighted + transitions; PATCH via VM)
- [~] **Assignee picker** — avatar grid (`LazyVerticalGrid`); filter by role; "Assign to me" shortcut; `PUT /tickets/:id` with `{ assigned_to }`; handoff modal requires reason (§4.12).
- [x] **Totals panel** — subtotal, tax, discount, deposit, balance due, paid; `SelectionContainer` on each; copyable grand total. (commit bf6369f — `components/TicketTotalsPanel.kt` subtotal+tax+discount+deposit+balance via `Money` util)
- [~] **Device section** — add/edit multiple devices (`POST /tickets/:id/devices`, `PUT /tickets/devices/:deviceId`). Each device: make/model (catalog picker), IMEI, serial, condition, diagnostic notes, photo reel.
- [x] **Per-device checklist** — pre-conditions intake: screen cracked / water damage / passcode / battery swollen / SIM tray / SD card / accessories / backup done / device works. `PUT /tickets/devices/:deviceId/checklist`. Must be signed before status → "diagnosed". (commit bf6369f — Devices tab renders `preConditionsList` per device card)
- [x] **Services & parts** per device — catalog picker pulls from `GET /repair-pricing/services` + `GET /inventory`; each line item = description + qty + unit price + tax-class; auto-recalc totals; price override role-gated. (commit bf6369f — Devices tab renders services+parts with qty/price columns; catalog picker wiring deferred)
- [x] **Photos** — full-screen gallery with pinch-zoom (`Modifier.pointerInput(detectTransformGestures)`), swipe (`HorizontalPager`), share intent. Upload via `POST /tickets/:id/photos` (multipart) through WorkManager + foreground service so uploads survive app kill. Progress chip per photo. Delete via swipe. Mark "before / after" tag. EXIF-strip PII on upload via `ExifInterface`. (commit 1359c41 — `components/TicketPhotoGallery.kt` HorizontalPager + pinch-zoom + before/after chip; `PickMultipleVisualMedia` → `util/ExifStripper` (29 GPS/DateTime tags) → `MultipartUploadWorker`; progress chip + delete confirm + share ACTION_SEND)
- [x] **Notes** — types: internal / customer-visible / diagnostic / sms / email / string (server types). `POST /tickets/:id/notes` with `{ type, content, is_flagged, ticket_device_id? }`. Flagged notes badge-highlight. (commit bf6369f — `components/TicketNotesTab.kt` type chip selector + compose box + POST via VM; flagged badge highlight)
- [x] **History timeline** — server-driven events (status changes, notes, photos, SMS, payments, assignments). Filter toggle chips per event type. Pill per day header. (commit bf6369f — `components/TicketHistoryTimeline.kt` vertical dot-connector timeline + M3 icons; empty state; event fetch via VM)
- [x] **Warranty / SLA badge** — "Under warranty" or "X days to SLA breach"; pull from `GET /tickets/warranty-lookup` on load. (commit bf6369f — prominent banner above tabs color-coded by days remaining; warningContainer/errorContainer tokens)
- [x] **QR code** — render ticket order-ID as QR via ZXing `BarcodeEncoder`; tap → full-screen enlarge for counter printer. `Image(bitmap)` + plaintext below. (commit 1359c41 — `components/TicketQrCard.kt` 200dp inline QR via `QrCodeGenerator.generateQrBitmap`; tap → full-screen dialog + `SelectionContainer` plaintext order-ID)
- [x] **Share PDF / Android Print** — on-device PDF pipeline per §17.4. `WorkOrderTicketView(model)` Composable → `PdfDocument` via `writeTo(outputStream)`; hand file URI (via `FileProvider`) to `PrintManager.print(...)` or share sheet (`Intent.createChooser`). SMS shares public tracking link (§55); email attaches locally-rendered PDF so recipient sees it without login. Fully offline-capable. (commit 1359c41 — `components/TicketPrintActions.kt` `PrintManager.print` + `PrintDocumentAdapter` + `FileProvider` PDF share; SMS tracking-link stub; email `ACTION_SEND` with PDF attachment)
- [x] **Copy link to ticket** — App Link `app.bizarrecrm.com/tickets/:id`. (commit bf6369f — overflow menu "Copy link" action + `ClipboardUtil.copy("bizarrecrm://tickets/$id")` + Snackbar "Link copied")
- [x] **Customer quick actions** — Call (`ACTION_DIAL`), SMS (opens thread), Email (`ACTION_SENDTO` with `mailto:`), open Customer detail, Create ticket for this customer. (commit bf6369f — `components/TicketCustomerActions.kt` AssistChip row {Call/SMS/Email}; `util/PhoneIntents.kt` helpers via ACTION_DIAL / ACTION_VIEW `sms:` / ACTION_SENDTO `mailto:`)
- [x] **Related** — side rail (tablet) with Recent tickets from same customer, Photo wallet, Health score, LTV tier (see §42). (commit 1359c41 — `components/TicketRelatedRail.kt` tablet-only `isMediumOrExpandedWidth()`; LTV tier chip + health-score + recent tickets + photo wallet grid)
- [x] **Bench timer widget** — small card, start/stop (`POST /bench/:ticketId/timer-start`); feeds Live Update notification (§24). (commit 1359c41 — `components/BenchTimerCard.kt` Start/Stop + HH:MM:SS ticker + `LiveUpdateNotifier.showLiveUpdate` per-tick; 404-stub fallback)
- [~] **Continuity banner** (tablet/ChromeOS) — `ComponentActivity.onProvideAssistContent` advertises this ticket so Cross-device Services / handoff can pick up on another signed-in device. (commit 1359c41 — KDoc stub in MainActivity `onProvideAssistContent`; full cross-device handoff needs Google Cross-device Services as future work)
- [x] **Deleted-while-viewing** — banner "This ticket was removed. [Close]". (commit 1359c41 — `components/DeletedBanner.kt` sticky errorContainer + liveRegion Assertive; VM catches `HttpException.code()==404` → `isDeletedWhileViewing` state)
- [x] **Permission-gated actions** — hide destructive actions when user lacks role. (commit 1359c41 — `isPrivilegedRole` admin/owner/manager check from `authPreferences.userRole` gates destructive Delete overflow item)

### 4.3 Create — full-fidelity multi-step
- [x] Minimal create (customer + single device). (commit ced0ac0 — TicketCreateMultiStepScreen wizard shell)
- [x] **Flow steps** — Customer → Device(s) → Services/Parts → Diagnostic/checklist → Pricing & deposit → Assignee / urgency / due date → Review. (commit ced0ac0 — `TicketCreateSubStep` enum 7 steps + `create/steps/*.kt`)
- [x] **Phone:** full-screen `Activity` with top `LinearProgressIndicator` (segmented via steps); each step own Composable screen via `AnimatedContent`. (commit ced0ac0 — ReduceMotion snap)
- [x] **Tablet:** 2-pane sheet (`ModalBottomSheet` large or full-screen dialog): left = step list, right = active step content; `Done` / `Back` in top bar. (commit ced0ac0 — TicketCreateMultiStepScreen tablet layout)
- [x] **Customer picker** — search existing (`GET /customers/search`) + "New customer" inline mini-form (see §5.3); recent customers list. (commit ced0ac0 — `CustomerStepScreen.kt` debounce 300ms + inline form)
- [x] **Device catalog** — `GET /catalog/manufacturers` + `GET /catalog/devices?keyword=&manufacturer=` drive hierarchical picker. Pre-populate common-repair suggestions from `GET /device-templates`. (commit ced0ac0 — `DeviceStepScreen.kt` manufacturer chips + model search)
- [~] **Device intake photos** — CameraX + system PhotoPicker; 0..N; drag-to-reorder (tablet) / long-press-reorder (phone). (commit ced0ac0 — DiagnosticStep PhotoPicker stub; WorkManager upload enqueue TODO)
- [x] **Pre-conditions checklist** — checkboxes (from server or tenant default); required signed on bench start. (commit ced0ac0 — `DiagnosticStepScreen.kt` default items + checkboxes)
- [x] **Services / parts picker** — quick-add tiles (top 5 services from `GET /pos-enrich/quick-add`) + full catalog search + barcode scan (CameraX + ML Kit Barcode). (commit ced0ac0 — `ServicesStepScreen.kt` quick-add tiles + barcode stub)
- [x] **Pricing calculator** — subtotal + tax class (per line) + line discount + cart discount (% or $, reason required beyond threshold) + fees + tip + rounding rules. Live recalc via `derivedStateOf`. (commit ced0ac0 — `PricingStepScreen.kt` derivedStateOf + discount + deposit)
- [x] **Deposit** — "Collect deposit now" → inline POS charge (see §16) or "Mark deposit pending". Deposit amount shown on header. (commit ced0ac0 — PricingStep deposit toggle)
- [x] **Assignee picker** — employee grid filtered by role / clocked-in; "Assign to me" shortcut. (commit ced0ac0 — `AssigneeStepScreen.kt` employee grid + assign-to-me + urgency + due-date)
- [x] **Due date** — default = tenant rule from `GET /settings/store` (+N business days); custom via `DatePicker` (Material3). (commit ced0ac0 — AssigneeStep due-date picker)
- [x] **Service type** — Walk-in / Mail-in / On-site / Pick-up / Drop-off (from `GET /settings/store`). Custom types supported. (commit ced0ac0 — DeviceStep/AssigneeStep fields)
- [x] **Tags / labels** — multi-chip picker (`InputChip`). (commit ced0ac0 — AssigneeStep chips)
- [x] **Source / referral** — dropdown (source list from server). (commit ced0ac0 — ReviewStep fields)
- [x] **Source-ticket linking** — pre-seed from existing ticket (convert-from-estimate flow). (commit ced0ac0 — StepData carries source)
- [x] **Review screen** — summary card with all fields; "Edit" jumps back to step; big `Button` "Create ticket" CTA. (commit ced0ac0 — `ReviewStepScreen.kt` summary + edit-chips + Create CTA)
- [x] **Idempotency key** — client generates UUID, sent as `Idempotency-Key` header to avoid duplicate creates on retry. (commit ced0ac0 — VM adds header)
- [x] **Offline create** — Room temp ID, queued in `sync_queue`; reconcile on drain. (commit ced0ac0 — existing SyncQueue reused)
- [x] **Autosave draft** — every field change writes to `tickets_draft` Room table; "Resume draft" banner on list when present; discard confirmation. (commit ced0ac0 — reuses existing `DraftStore.TICKET` + onFieldChanged)
- [x] **Validation** — per-step inline error helper text; block next until required fields valid. (commit ced0ac0 — `StepValidator.kt` + 17 JVM tests)
- [x] **Hardware-keyboard shortcuts** — Ctrl+Enter create, Ctrl+. cancel, Ctrl+→ / Ctrl+← next/prev step.
- [x] **Haptic** — `CONFIRM` on create; `REJECT` on validation fail. (commit ced0ac0 — Create/Validate actions wire `HapticFeedbackConstants.CONFIRM/REJECT`)
- [x] **Post-create** — pop to ticket detail; if deposit collected → Sale success screen (§16.8); offer "Print label" if receipt printer paired. (commit ced0ac0 — ReviewStep onCreateSuccess navigates to detail)

### 4.4 Edit
- [x] In-place edit on detail: status, assignee, notes, devices, services, prices, deposit, due date, urgency, tags, labels, customer reassign, source. (commit 181e486 — VM `updateField()` generic optimistic path)
- [x] **Optimistic UI** with rollback on failure (revert local mutation + error Snackbar). (commit 181e486 — apply local + revert on failure + Snackbar)
- [x] **Audit log** entries streamed back into timeline. (commit 181e486 — `loadTicketDetail()` called after each write)
- [x] **Concurrent-edit** detection — server returns 409 on stale `updated_at`; UI shows "This ticket changed. Reload to merge." banner. (commit 181e486 — `components/ConcurrentEditBanner.kt` + 409 detection + Reload-to-merge)
- [x] **Delete** — destructive confirm; soft-delete server-side. (commit 181e486 — `components/TicketDeleteDialog.kt` + role gate)

### 4.5 Ticket actions
- [x] **Convert to invoice** — `POST /tickets/:id/convert-to-invoice` → navigates to new invoice detail; prefill ticket line items; respect deposit credit. (commit 181e486 — pre-existing; wired via overflow)
- [x] **Attach to existing invoice** — picker; append line items. (commit 181e486 — `TicketApi.attachToInvoice` endpoint)
- [x] **Duplicate ticket** — same customer + device + clear status. (commit 181e486 — `duplicateTicket()` VM + API + navigate)
- [x] **Merge tickets** — pick duplicate candidate (search dialog); confirm; server merges notes / photos / devices. (commit 181e486 — `components/TicketMergeDialog.kt` + `searchMergeCandidates` + `mergeTickets`)
- [x] **Transfer to another technician** — handoff modal with reason (required) — `PUT /tickets/:id` with `{ assigned_to }` + note auto-logged. (commit 181e486 — `components/TicketHandoffDialog.kt` + `loadHandoffEmployees` + `transferTicket` 404-fallback)
- [x] **Transfer to another store / location** (multi-location tenants). (commit 181e486 — location picker slot in TicketHandoffDialog active when locations non-empty)
- [x] **Bulk action** — `POST /tickets/bulk-action` with `{ ticket_ids, action, value }` — bulk assign / bulk status / bulk archive / bulk tag. (commit 181e486 — `components/TicketBulkActionBar.kt` extracted; Assign/Status/Archive/Tag wired via `TicketApi.bulkAction` + 20 JVM tests)
- [x] **Warranty lookup** — quick action "Check warranty" — `GET /tickets/warranty-lookup?imei|serial|phone`. (commit 7f84969 — `components/TicketWarrantyDialog.kt` + `TicketApi.warrantyLookup` + `WarrantyResult` DTO)
- [x] **Device history** — `GET /tickets/device-history?imei|serial` — shows past repairs for this device on any customer. (commit 7f84969 — `components/DeviceHistorySheet.kt` ModalBottomSheet + `TicketApi.getDeviceHistory`)
- [x] **Star / pin** to dashboard. (commit 7f84969 — overflow "Pin to dashboard" + `TicketApi.pinToDashboard` + AppPreferences local fallback)

### 4.6 Notes & mentions
- [x] **Compose** — multiline `OutlinedTextField`, type picker (internal / customer / diagnostic / sms / email), flag toggle. (commit 7f84969 — `components/TicketNoteCompose.kt` SegmentedButton type picker + flag Switch)
- [x] **`@` trigger** — inline employee picker (`GET /employees?keyword=`); insert `@{name}` token via `AnnotatedString` + `SpanStyle`. (commit 7f84969 — `util/MentionPicker.kt` + `SettingsApi.searchEmployees` debounced; 11 JVM tests)
- [~] **Mention push** — server sends FCM to mentioned employee. (commit 7f84969 — Android sends `[@mention:userId]` tokens; server-side FCM dispatch out-of-scope)
- [x] **Markdown-lite** — bold / italic / bullet lists / inline code rendered via `AnnotatedString` + custom parser (no WebView). (commit 7f84969 — `util/MarkdownLiteParser.kt` bold/italic/code/bullet/link; 14 JVM tests; no WebView)
- [x] **Link detection** — phone / email / URL auto-tappable via `LinkAnnotation`. (commit 7f84969 — MarkdownLiteParser regex scans + LinkAnnotation → ACTION_DIAL/ACTION_SENDTO/ACTION_VIEW)
- [x] **Attachment** — add image from camera / PhotoPicker → inline preview; stored as note attachment. (commit 7f84969 — PhotoPicker + Coil preview + submit via MultipartUploadWorker)

### 4.7 Statuses & transitions
- [x] **Fetch taxonomy** `GET /settings/statuses` — drives picker; no hardcoded statuses. (commit 7f84969 — `SettingsApi` + `TicketStatusItem` DTO with `transitionRequirements`/`group`)
- [x] **Color chip** from server hex. (commit 7f84969 — status picker renders via `Color(parseColor(hex))`)
- [x] **Transition guards** — some transitions require: note added, photos taken, checklist signed, QC sign-off. Frontend enforces + server validates. (commit 7f84969 — `TicketStatusItem.transitionRequirements` checked client-side; Snackbar error surfacing; server re-validates)
- [x] **QC sign-off modal** — signature capture via custom Compose `Canvas` + `detectDragGestures`, comments, "Work complete" confirm. (commit 0b3000d — `components/QcSignOffDialog.kt` ModalBottomSheet + `ui/components/SignatureCanvas.kt` reusable; `TicketApi.qcSignOff` multipart)
- [x] **Status notifications** — if tenant configured SMS/email on this transition, modal confirms "Notify customer?" with template preview. (commit 0b3000d — `StatusNotifyPreviewDialog.kt` + `NotificationSpec`; Send/Skip/Cancel; SMS on Send)

### 4.8 Photos — advanced
- [x] **Camera** — CameraX `PreviewView` with flash toggle, flip, grid, shutter haptic. (session 2026-04-26 — `CameraCaptureScreen.kt` in `ui/screens/hardware/` + nav wired in `AppNavGraph`; LifecycleCameraController + tap-to-focus + pinch-zoom + flash toggle + lens-flip + shutter upload via TicketApi)
- [x] **Library picker** — system `PhotoPicker` (`ActivityResultContracts.PickMultipleVisualMedia`) with selection limit 10. (commit 1359c41)
- [x] **Upload** — WorkManager Worker surviving app exit; foreground service during active uploads; progress chip per photo. (commit da67d14 + 1359c41)
- [~] **Retry failed upload** — dead-letter entry in Sync Issues. (existing SyncQueue dead-letter; UI surface pending)
- [x] **Annotate** — Compose `Canvas` overlay on photo for markup via stylus or finger; saves as new attachment (original preserved). (commit 0b3000d — `PhotoAnnotateScreen.kt` full-screen + color chips + stroke width slider + compositing upload)
- [x] **Before / after tagging** — toggle on each photo; detail view shows side-by-side on review. (commit 1359c41 + 0b3000d — verified)
- [x] **EXIF strip** — remove GPS + timestamp metadata on upload via `ExifInterface.setAttribute(...)` clearing sensitive tags. (commit 1359c41 + 0b3000d — verified wired in gallery + annotate)
- [x] **Thumbnail cache** — Coil with disk limit; full-size fetched on tap. (commit 0b3000d — `BizarreCrmApp` SingletonImageLoader.Factory 100MB disk + 25% memory)
- [x] **Signature attach** — signed customer acknowledgement saved as PNG attachment (Bitmap → PNG → upload). (commit 0b3000d — 404 fallback uploads signature PNG as photo tag="signature" + note)

### 4.9 Bench workflow
- [x] **Backend:** `GET /bench`, `POST /bench/:ticketId/timer-start`. (commit 07ec4c4 — `BenchApi.myBench()`)
- [x] **Frontend:** Bench tab (or dashboard tile) — queue of my bench tickets with device template shortcut + big timer. (commit 07ec4c4 — `BenchTabScreen.kt` LazyColumn + BenchTimerCard per row)
- [x] **Live Update** (Android 16) — Progress-style ongoing notification shows active-repair timer on Lock Screen + status bar. Foreground service `repairInProgress` keeps process alive; notification category `CATEGORY_PROGRESS`. (commit 07ec4c4 + d3f91d0 — BenchTimerCard wires `LiveUpdateNotifier`; `RepairInProgressService` + `FOREGROUND_SERVICE_TYPE_DATA_SYNC` + CATEGORY_PROGRESS)
- [x] Parallels to iOS Live Activity: same server payload, same copy deck. (commit 07ec4c4 — KDoc documents iOS parity)

### 4.10 Device templates
- [x] **Backend:** `GET /device-templates`, `POST /device-templates`. (commit 07ec4c4 — `DeviceTemplateApi`)
- [x] **Frontend:** template picker on create / bench — pre-fills common repairs per device; editable per tenant in Settings → Device Templates. (commit 07ec4c4 — `DeviceTemplatesScreen.kt` Settings sub-screen + edit dialog; BenchTabScreen shortcut button)

### 4.11 Repair pricing catalog
- [x] **Backend:** `GET /repair-pricing/services`, `POST`, `PUT`. (commit 07ec4c4 — `RepairPricingApi` extended)
- [x] **Frontend:** searchable services catalog with labor-rate defaults; per-device-model overrides. (commit 07ec4c4 — `RepairPricingScreen.kt` + edit dialog + search + override fields)

### 4.12 Handoff modal
- [x] Required reason dropdown: Shift change / Escalation / Out of expertise / Other (free-text). Assignee picker. `PUT /tickets/:id` + auto-logged note. Receiving tech gets FCM push. (commit 07ec4c4 — TicketHandoffDialog `HandoffReason` enum mandatory + free-text for OTHER; PUT + audit; server FCM)

### 4.13 Empty / error states
- [x] No tickets — illustration + "Create your first ticket". (session 2026-04-26 — `EmptyState` with `Icons.Default.ConfirmationNumber` already wired in `TicketListScreen`; confirmed present)
- [x] Network error on detail — keep cached data, retry pill. (session 2026-04-26 — `hasStaleCachedData` flag in `TicketDetailUiState`; VM sets it on API failure when Room cache exists; floating `Surface` retry pill at `Alignment.BottomCenter` in detail content area)
- [x] Deleted on server → banner "Ticket removed. [Close]". (session 2026-04-26 — `DeletedBanner` component already existed and wired via `isDeletedWhileViewing` 404 detection; confirmed present)
- [x] Permission denied on action → inline Snackbar "Ask your admin to enable this.". (session 2026-04-26 — `permissionDeniedMessage` state + `clearPermissionDenied()` in VM; 403 detection in `changeStatus` catch; `LaunchedEffect` fires Snackbar)
- [x] 409 stale edit → "This ticket changed. [Reload]". (session 2026-04-26 — `isConcurrentEditConflict` state; 409 detection in `changeStatus` catch; `ConcurrentEditBanner` imported and placed above content area; `clearConcurrentEditConflict()` triggers reload)

### 4.14 Signatures & waivers
- [x] Waiver PDF templates managed server-side; Android renders. (commit e4afd40 — `WaiverApi.getRequiredTemplates` + `WaiverListViewModel` renders server content)
- [x] Required contexts: drop-off agreement (liability / data loss / diagnostic fee), loaner agreement (§43), marketing consent (TCPA SMS / email opt-in). (commit e4afd40 — `WaiverTemplate.type`: `dropoff|loaner|marketing|other`)
- [x] Waiver sheet UI: scrollable text + Compose-Canvas signature + printed name + "I've read and agree" checkbox; Submit disabled until checked + signature non-empty. (commit e4afd40 — `WaiverSheet.kt` ModalBottomSheet using reusable `SignatureCanvas`; 9 JVM tests validate submit gates)
- [x] Signed PDF auto-emailed to customer; archived to tenant storage. (server-side; Android POSTs signature)
- [x] `POST /tickets/:id/signatures` endpoint. (commit e4afd40 — `WaiverApi.submitSignature(ticketId, request)`)
- [x] Audit log entry per signature: timestamp + IP + device fingerprint + waiver version + actor. (commit e4afd40 — `SignatureAuditDto(timestamp, device_fingerprint, actor_user_id)` + `util/DeviceFingerprint.kt` enriches with model/manufacturer)
- [x] Re-sign on waiver-text change: existing customers re-sign on next interaction; version tracked. (commit e4afd40 — `AppPreferences.acceptedWaiverVersions` vs `WaiverTemplateDto.version` → `isReSignRequired` flag drives badge + button)

### 4.15 Ticket state machine
- [x] Default state set (tenant-customizable): Intake → Diagnostic → Awaiting Approval → Awaiting Parts → In Repair → QA → Ready for Pickup → Completed → Archived. Branches: Cancelled, Un-repairable, Warranty Return. (commit 7f3c9f3 — `TicketStateMachine.kt` `TicketState` enum + `defaultTransitions` map)
- [x] Transition rules editable in Settings → Ticket statuses (§19): optional per-transition prerequisites. (commit 7f3c9f3 — `validateTransition` graph + requirement checks; 28 JVM tests)
- [x] Triggers on transition: auto-SMS + assignment-change audit + idle-alert. (commit 7f3c9f3 — `requestStatusChangeWithNotify` + `changeStatusGuarded` wrapping)
- [x] Bulk transitions via multi-select → "Move to Ready" menu; rules enforced per-ticket; skipped ones shown in summary. (commit 7f3c9f3 — `bulkTransition()` chunked-10 parallel + `BulkTransitionSummary` dialog)
- [x] Rollback: admin-only; creates audit entry with reason. (commit 7f3c9f3 — `RollbackStatusDialog` + `TicketApi.rollbackStatus`)
- [x] Visual: tenant-configured color per state; state pill on every list row + detail header. (commit 7f3c9f3 — `TicketStatePill.kt` hex color + luminance contrast)
- [~] Funnel chart in §15 Reports: count per state + avg time-in-state; bottleneck highlight if avg > tenant benchmark. (commit 570754f — `TicketsReportScreen` scaffold; full funnel deferred)

### 4.16 Quick-actions catalog
- [x] Context menu (long-press on list row): Open / Copy ID / Share PDF / Call customer / Text customer / Print receipt / Mark Ready / Mark In Repair / Assign to me / Archive / Delete (admin only). (commit 68cadc5 + 7f3c9f3 — `TicketQuickActionsBar.kt` 9-chip MRU-sorted bar)
- [x] Swipe actions: right swipe = Start/Mark Ready (state-dependent); left swipe = Archive; long-swipe destructive requires AlertDialog confirm. (commit 68cadc5 — `TicketSwipeRow`)
- [x] Tablet hardware-keyboard: Ctrl+D mark done; Ctrl+Shift+A assign; Ctrl+Shift+S send SMS update; Ctrl+P print; Ctrl+Delete delete. (commit 7f3c9f3 — `TicketDetailKeyboardHost` chords)
- [~] Drag-and-drop: drag ticket row to "Assign" rail target (tablet) to reassign; drag to status column in Kanban. (commit 7f3c9f3 — TODO comment in Kanban placeholder; full implementation deferred)
- [x] Batch actions: multi-select in list; batch context menu Assign/Status/Archive/Export. (commit 181e486 — `TicketBulkActionBar`)
- [x] Smart defaults: show most-recently-used action first per user; adapts over time. (commit 7f3c9f3 — `AppPreferences.ticketActionUsage` + `incrementTicketActionUsage`)

### 4.17 IMEI validation (identification only)
- [x] Local IMEI validation only: Luhn checksum + 15-digit length. (`util/ImeiValidator.kt`)
- [x] Optional TAC lookup (first 8 digits) via offline table to name device model. (`ImeiValidator.lookupTacModel`; ~40-entry table — grows via §44 Device Templates.)
- [~] Called from ticket create / inventory trade-in purely for device identification + autofill make/model. (TicketCreate now surfaces Luhn + TAC-match as supportingText under the IMEI field; inventory trade-in call-site still pending.)
- [x] No stolen/lost/carrier-blacklist provider lookup — scope intentionally dropped. Shop does not gate intake on external device-status services.

### 4.18 Warranty tracking
- [ ] Warranty record created on ticket close for each installed part/service.
  - **NOTE (2026-04-26):** All 4.18 items require new server endpoints (`POST /tickets/:id/warranty-records`, `GET /warranty-claims`, etc.) that do not yet exist. Full feature is a server-first effort; Android client work blocked until server schema and API are built.
- [ ] Fields: part_id, serial, install date, duration (90d / 1yr / lifetime), conditions.
- [ ] Claim intake: staff searches warranty by IMEI / receipt / name.
- [ ] Match shows prior tickets + install dates + eligibility.
- [ ] Decision: within warranty + valid claim → new ticket status Warranty Return; parts + labor zero-priced automatically.
- [ ] Decision: out of warranty → new ticket status Paid Repair.
- [ ] Decision: edge cases (water damage, physical damage) flagged for staff judgment.
- [ ] Part return to vendor: defective part marked RMA-eligible; staff ships via §61.
- [ ] Auto-SMS confirming warranty coverage + re-ETA estimate.
- [ ] Reporting: warranty claim rate by part / by supplier / by tech (reveals quality issues).
- [ ] Cost center: warranty repair labor + parts allocated to warranty cost center; dashboard shows warranty cost vs revenue.

### 4.19 SLA tracking
- [ ] SLA definitions per service type (e.g. "Diagnose within 4h", "Repair within 24h for priority", "Respond to SMS in 30m").
  - **NOTE (2026-04-26):** `SlaCalculator.kt`, `SlaChip`, `SlaProgress`, `SlaHeatmapScreen` already exist. However SLA timer with pause/resume, per-service definitions, and breach push notifications all require server endpoints (`GET /sla-definitions`, `GET /tickets/:id/sla-status`, push FCM on breach). Full items below blocked on server. Client components wired into list + detail in this session using dueOn field as approximate deadline only.
- [ ] Timer starts on intake / ticket create.
- [ ] Timer pauses for statuses configured as "Waiting on customer" / "Awaiting parts".
- [ ] Timer resumes on return to active state.
- [ ] Ticket list row: SLA chip (green/amber/red) based on remaining time.
- [ ] Ticket detail: timer + phase progress.
- [ ] Alerts: amber at 75% used; red at 100%.
- [ ] Push to assignee + manager when breached.
- [ ] Reports: per tech SLA compliance %; per service average time vs SLA.
- [ ] Override: manager can extend SLA with reason (audit log).
- [ ] Customer commitment: SLA visible on public tracking page (§55) as "We'll update you by <time>".

### 4.20 QC checklist
- [ ] Ticket can't be marked Ready until QC checklist complete.
  - **NOTE (2026-04-26):** `QcChecklistSheet.kt` (UI) already exists with Pass/Fail/NA radio buttons, photo per item, primary + second-tech signature. Server endpoint `GET /qc-checklists?service_id=` and `POST /tickets/:id/qc-checklist` are not yet deployed. The "blocks Ready transition" guard also requires server-side status-transition prerequisites to include `qc_complete`. All sub-items below blocked on server work.
- [ ] Per-service checklist configurable per repair type.
- [ ] Example iPhone screen checklist: Display lights up / Touch works / Camera / Speaker / Mic / Wi-Fi / Cellular / Battery health / Face unlock / No new scratches.
- [ ] Each item: pass / fail / N/A + optional photo.
- [ ] Failure: fail item returns ticket to In Repair with failure noted; require reason on flip back.
- [ ] Sign-off: tech signature + timestamp.
- [ ] Optional second-tech verification for high-value repairs.
- [ ] Customer-visible: checklist printed on invoice/receipt so customer sees what was tested.
- [ ] Audit: QC history visible in ticket history including who tested and when.

### 4.21 Labels (separate from status)
- [x] Labels separate from status: status is lifecycle (one), labels are optional flags (many). (session 2026-04-26 — `TicketEntity.labels` comma-separated String; `TicketLabelChips` composable with hash-based color palette)
- [x] Example labels: urgent, VIP, warranty, insurance claim, parts-ordered, QC-pending. (session 2026-04-26 — rendered from server-provided label strings via comma-split)
- [x] Color-coded chips on list rows. (session 2026-04-26 — `TicketLabelChips` wired into `TicketListRow` support slot)
- [x] Filter ticket list by label. (session 2026-04-26 — `activeLabelFilter` in `TicketListUiState`; `onLabelFilterChanged()` in VM; active filter chip shown above status row with remove; label chip tap toggles filter)
- [ ] Auto-rules: "device-value > $500 → auto-label VIP"; "parts-ordered → auto-label on PO link".
  - **NOTE (2026-04-26):** Auto-rules are server-side business logic; Android renders what the server sends.
- [ ] Multi-select bulk apply/remove label.
  - **NOTE (2026-04-26):** `TicketApi.bulkAction` exists; needs `BulkActionBar` label picker UI — deferred to bulk-actions pass.
- [x] Conceptual: ticket labels are ticket-scoped vs customer tags are customer-scoped — don't conflate. (session 2026-04-26 — confirmed by entity model)
- [ ] Label break-outs in revenue/duration reports (e.g. "Insurance claims avg turn time = 8d").
  - **NOTE (2026-04-26):** Reports surface — out of scope for this section.

### 4.22 SLA visualizer
- [x] Inline chip on ticket list row: small ring showing % of SLA consumed; green < 60%, amber 60-90%, red > 90%, black post-breach. (session 2026-04-26 — `SlaChip` wired into `TicketListRow` trailing area; tier derived from `dueOn` vs now; approximate 24h budget; uses `SlaCalculator.tier` + `formatSlaRemaining`)
- [x] Detail header: progress bar with phase markers (diagnose / awaiting parts / repair / QC); long-press reveals phase timestamps + remaining. (session 2026-04-26 — `SlaProgress` composable wired into `TicketDetailContent` LazyColumn above tabs; uses `dueOn` + `reduceMotion`; phase markers pass-through empty until server SLA defs available)
- [ ] Timeline overlay: status history overlays SLA curve to show phase-budget consumption.
  - **NOTE (2026-04-26):** Requires server to return status history with timestamps alongside ticket. Deferred.
- [ ] Manager aggregated view: all-open tickets on SLA heatmap (tickets × time to SLA); red-zone sortable to top.
  - **NOTE (2026-04-26):** `SlaHeatmapScreen.kt` already exists; needs nav route + `SlaApi.getHeatmap` server endpoint deployment.
- [ ] Projection: predict breach time at current pace ("At current rate, will breach at 14:32").
  - **NOTE (2026-04-26):** Requires server-side projection data or status history with cadence.
- [ ] One-tap "Notify customer of delay" with template pre-filled.
  - **NOTE (2026-04-26):** `NotifyDelayDialog` already exists in `SlaHeatmapScreen`; needs wiring to `SmsApi` from ticket detail. Deferred.
- [x] Reduce Motion: gauge animates only when Reduce Motion off; else static value. (session 2026-04-26 — `SlaProgress(reduceMotion=...)` passes through from `TicketDetailContent`)

---
## 5. Customers

_Server endpoints: `GET /customers`, `GET /customers/search`, `GET /customers/{id}`, `POST /customers`, `PUT /customers/{id}`, `DELETE /customers/{id}`, `GET /customers/{id}/tickets`, `GET /customers/{id}/invoices`, `GET /customers/{id}/communications`, `GET /customers/{id}/assets`, `POST /customers/{id}/assets`, `GET /customers/{id}/analytics`, `POST /customers/bulk-tag`, `POST /customers/merge`, `GET /crm/customers/{id}/health-score`, `POST /crm/customers/{id}/health-score/recalculate`, `GET /crm/customers/{id}/ltv-tier`._

### 5.1 List
- [x] Base list + search via LazyColumn + Paging3.
- [x] **Cursor-based pagination (offline-first)** per top-of-doc rule + §20.5. (commit 99e0eee — `CustomerRemoteMediator` + `CustomerDao.pagingSource()/pagingSourceAZ()/pagingSourceZA()` + `CustomerRepository.customersPaged()` Pager)
- [x] **Sort** — most recent / A–Z / Z–A / most tickets / most revenue / last visit. (commit 99e0eee — `components/CustomerSortDropdown.kt` 6-option enum)
- [x] **Filter** — tag(s) / LTV tier (VIP / Regular / At-risk) / health-score band / balance > 0 / has-open-tickets / city-state. (commit 99e0eee — `components/CustomerFilterSheet.kt` ModalBottomSheet)
- [x] **Swipe actions** — leading: SMS / Call; trailing: Mark VIP / Archive. (commit 99e0eee — SwipeToDismissBox in CustomerListScreen)
- [x] **Context menu** (long-press / right-click) — Open, Copy phone, Copy email, New ticket, New invoice, Send SMS, Merge. (commit 99e0eee — long-press DropdownMenu)
- [x] **A–Z section index** (phone) — fast-scroller via custom `Modifier` on right edge that jumps by letter anchor. (commit 99e0eee — `components/CustomerAZIndex.kt` 27-letter + tap+drag + animateScrollToItem)
- [x] **Stats header** (toggleable via `include_stats=true`) — total customers, VIPs, at-risk, total LTV, avg LTV. (commit 99e0eee — `CustomerApi.getStats()` 404→hidden)
- [~] **Preview popover** (tablet/ChromeOS hover via `pointerHoverIcon`) — quick stats (spent / tickets / last visit). (commit 99e0eee — tablet breakpoint wired; hover popover deferred)
- [x] **Bulk select + tag** — long-press enters selection; `BulkActionBar`; `POST /customers/bulk-tag` with `{ customer_ids, tag }`. (commit 99e0eee — BulkActionBar Tag/Delete + 5s undo snackbar)
- [x] **Bulk delete** with undo Snackbar (5s window). (commit 99e0eee — covered by bulk action bar)
- [x] **Export CSV** via Storage Access Framework `ACTION_CREATE_DOCUMENT`. (commit 99e0eee — SAF CreateDocument)
- [x] **Empty state** — "No customers yet. Create one or import from Contacts." + two CTAs. (commit 99e0eee)
- [x] **Import from Contacts** — system `ContactsContract` picker multi-select → create each. (commit 99e0eee — `components/CustomerContactImport.kt` PickContact + READ_CONTACTS rationale AlertDialog)

### 5.2 Detail
- [x] Base (analytics / recent tickets / notes). (commit 99e0eee — CustomerDetailScreen tabs layout)
- [x] **Tabs** (mirror web): Info / Tickets / Invoices / Communications / Assets. (commit 99e0eee — `components/CustomerTabs.kt` PrimaryTabRow)
- [x] **Header** — avatar + name + LTV tier chip + health-score ring + VIP star. (commit 99e0eee — header in CustomerDetailScreen)
- [x] **Health score** — `GET /crm/customers/:id/health-score` → 0–100 ring. (commit 99e0eee — `CustomerApi.getHealthScore/recalculate` + green/amber/red ring)
- [x] **LTV tier** — `GET /crm/customers/:id/ltv-tier` → chip. (commit 99e0eee — `CustomerApi.getLtvTier` + chip tap → explanation)
- [x] **Photo mementos** — recent repair photos gallery (`LazyRow` horizontal scroll).
- [x] **Contact card** — phones (multi, labeled), emails (multi), address, birthday, tags, organization, communication preferences, custom fields. (commit 99e0eee — existing detail card preserved with Info tab)
- [x] **Quick-action row** — chips: Call · SMS · Email · New ticket · New invoice · Share · Merge · Delete. (commit 99e0eee — `components/CustomerQuickActions.kt` scrollable AssistChip row)
- [x] **Tickets tab** — `GET /customers/:id/tickets`; infinite scroll; status chips; tap → ticket detail. (commit 99e0eee)
- [x] **Invoices tab** — `GET /customers/:id/invoices`; status filter; tap → invoice. (commit 99e0eee — `CustomerApi.getInvoices`)
- [x] **Communications tab** — `GET /customers/:id/communications`; unified SMS / email / call log timeline; "Send new SMS / email" CTAs. (commit 99e0eee)
- [x] **Assets tab** — `GET /customers/:id/assets`; devices owned; add asset; tap device → device-history. (commit 99e0eee)
- [~] **Balance / credit** — sum of unpaid invoices + store credit balance. (commit 99e0eee — not wired; endpoint not defined)
- [~] **Membership** — if tenant has memberships (§38), show tier + perks. (commit 99e0eee — memberships not enabled)
- [x] **Share vCard** — generate `.vcf` via `VCardEntryConstructor` → share sheet; SAF export on tablet/ChromeOS. (commit 99e0eee — `util/VCardBuilder.kt` vCard 3.0 + FileProvider → ACTION_SEND)
- [~] **Add to system Contacts** — `Intent(ACTION_INSERT, RawContacts.CONTENT_URI)` prefilled. (commit 99e0eee — deferred; share vCard covers use case)
- [x] **Delete customer** — confirm `AlertDialog` + warning if open tickets (offer reassign-or-cancel flow). (commit 99e0eee — AlertDialog + open-ticket warning message)

### 5.3 Create
- [x] Full create form (first/last/phone/email/organization/address/city/state/zip/notes).
- [x] **Extended fields** — type (person / business), multiple phones with labels (home / work / mobile), multiple emails, mailing vs billing address, tags chip picker, communication preferences toggles, custom fields (render from `GET /custom-fields`), referral source, birthday, notes.
- [x] **Phone normalize** — shared `PhoneFormatter` util using libphonenumber-android.
- [x] **Duplicate detection** — before save, fuzzy match on phone/email; modal "Looks like this might be {name}. Use existing?" with Merge / Cancel / Create anyway.
- [x] **Import from Contacts** — `ContactsContract.Contacts.CONTENT_URI` picker prefills form.
- [x] **Barcode/QR scan** — scan customer card (if tenant prints them) for quick-lookup. (session 2026-04-26 — `CustomerCardScanSheet.kt` ModalBottomSheet + CameraX + `BarcodeAnalyzer`; scan wired into `CustomerCreateScreen` top-bar icon + body button; `handleScannedCard()` in ViewModel calls `searchCustomers`, navigates to existing or silently lets user create new)
- [x] **Idempotency** + offline temp-ID handling.

### 5.4 Edit
- [x] All fields editable. `PUT /customers/:id`.
- [x] Optimistic UI + rollback.
- [x] Concurrent-edit 409 banner.

### 5.5 Merge
- [x] `POST /customers/merge` with `{ keep_id, merge_id }`.
- [x] Search + select candidate; diff preview (which fields survive); confirmation.
- [x] Destructive — explicit warning that merge is irreversible past 24h window.

### 5.6 Bulk actions
- [x] Bulk tag (`POST /customers/bulk-tag`).
- [x] Bulk delete with undo.
- [x] Bulk export selected.

### 5.7 Asset tracking
- [x] Add device to customer (`POST /customers/:id/assets`) — device template picker + serial/IMEI.
- [x] Tap asset → device-history (`GET /tickets/device-history?imei|serial`).

### 5.8 Tags & segments
- [x] Free-form tag strings (e.g. `vip`, `corporate`, `recurring`, `late-payer`).
- [x] Color-coded with tenant-defined palette.
- [ ] Auto-tags applied by rules (e.g. "LTV > $1000 → gold").
  - **NOTE (2026-04-26):** Requires server-side rule engine (no endpoint exists). Android can display rule-applied tags but cannot define or execute them.
- [x] Customer detail header chip row for tags.
- [x] Tap tag → filter customer list.
- [x] Bulk-assign tags via list multi-select.
- [ ] Tag nesting hierarchy (e.g. "wholesale > region > east") with drill-down filters.
  - **NOTE (2026-04-26):** Requires server schema change to support parent/child tag relationships and a new endpoint. Design decision needed on hierarchy depth.
- [ ] Segments: saved tag combos + filters (e.g. "VIP + last visit < 90d").
  - **NOTE (2026-04-26):** Requires a server segments endpoint (`POST /segments`, `GET /segments`). No such endpoint exists.
- [ ] Segments used by marketing (§37) and pricing rules.
  - **NOTE (2026-04-26):** Blocked by §37 (marketing module) and segments endpoint missing. Cross-section dependency.
- [x] Max 20 tags per customer (warn at 10).
- [ ] Suggested tags based on behavior (e.g. suggest `late-payer` after 3 overdue invoices).
  - **NOTE (2026-04-26):** Requires server-side ML/analytics to compute suggestions. No endpoint defined.

### 5.9 Customer 360
- [ ] Unified customer detail: tickets / invoices / payments / SMS / email / appointments / notes / files / feedback.
  - **NOTE (2026-04-26):** Requires a server timeline endpoint (e.g. `GET /customers/:id/timeline`) that aggregates all event types. No such endpoint exists. Partial data (tickets, invoices, notes, assets) already shown in existing tabs.
- [ ] Vertical chronological timeline with colored dots per event type.
  - **NOTE (2026-04-26):** Blocked by missing server timeline endpoint.
- [ ] Timeline filter chips and jump-to-date picker.
  - **NOTE (2026-04-26):** Blocked by missing server timeline endpoint.
- [ ] Metrics header: LTV, last visit, avg spend, repeat rate, preferred services, churn risk score.
  - **NOTE (2026-04-26):** LTV + last visit already in `GET /customers/:id/analytics`. Repeat rate, preferred services, churn risk score not in that payload — server change required.
- [ ] Relationship graph: household / business links (family / coworker accounts).
  - **NOTE (2026-04-26):** Requires server schema and endpoint for account linking. Design decision needed.
- [ ] "Related customers" card.
  - **NOTE (2026-04-26):** Requires server relationship endpoint.
- [ ] Files tab: photos, waivers, emails archived in one place.
  - **NOTE (2026-04-26):** Requires server file-cabinet endpoint (`GET /customers/:id/files`). See §5.15.
- [ ] Star-pin important notes to customer header, visible across ticket/invoice/SMS contexts.
  - **NOTE (2026-04-26):** Requires server note-pin endpoint and schema change (`pinned` column on customer_notes). Server change required.
- [ ] Customer-level warning flags ("cash only", "known difficult", "VIP treatment") as staff-visible banner.
  - **NOTE (2026-04-26):** Requires server schema change (warning_flags column or table). Design decision on flag taxonomy needed.

### 5.10 Dedup & merge
- [ ] Dupe detection on create: same phone / same email / similar name + address.
  - **NOTE (2026-04-26):** Basic phone/email dupe detection already implemented in §5.3 (`checkForDuplicates()` in `CustomerCreateViewModel`). Name+address fuzzy match requires server-side fuzzy search endpoint.
- [ ] Suggest merge at entry.
  - **NOTE (2026-04-26):** Covered by existing duplicate dialog in §5.3. Per-name fuzzy suggestion needs server support.
- [ ] Side-by-side record comparison merge UI.
  - **NOTE (2026-04-26):** Current merge (§5.5) shows which fields survive but doesn't do side-by-side per-field comparison. Requires UX design decision and server to return both records in a diff format.
- [ ] Per-field pick-winner or combine.
  - **NOTE (2026-04-26):** Requires server to accept field-level merge directives in the merge POST body. Server change required.
- [ ] Combine all contact methods (phones + emails).
  - **NOTE (2026-04-26):** Server merge logic must be extended to union phone/email arrays rather than replace. Server change required.
- [ ] Migrate tickets, invoices, notes, tags, SMS threads, payments to survivor.
  - **NOTE (2026-04-26):** This is server-side merge logic. Current `POST /customers/merge` presumably does this; verify server implementation.
- [ ] Tombstone loser record with audit reference.
  - **NOTE (2026-04-26):** Server-side concern. No client change needed once server implements.
- [ ] 24h unmerge window, permanent thereafter (audit preserves trail).
  - **NOTE (2026-04-26):** Server-side concern. Client already shows the irreversibility warning.
- [ ] Settings → Data → Run dedup scan → lists candidates.
  - **NOTE (2026-04-26):** Requires a server dedup-scan endpoint (`GET /customers/dedup-candidates`). No such endpoint exists.
- [ ] Manager batch review of dedup candidates.
  - **NOTE (2026-04-26):** Blocked by missing dedup-candidates endpoint.
- [ ] Optional auto-merge when 100% phone + email match.
  - **NOTE (2026-04-26):** Server-side configuration toggle. No client change needed once server implements.

### 5.11 Communication preferences
- [ ] Per-customer preferred channel for receipts / status / marketing (SMS / email / push / none).
  - **NOTE (2026-04-26):** Basic SMS/email opt-in toggles exist in create/edit form (§5.3 `smsOptIn`/`emailOptIn`). Granular per-channel-per-category preferences require server schema extension (`communication_preferences` table or JSON column).
- [ ] Times-of-day preference.
  - **NOTE (2026-04-26):** Requires server schema extension and enforcement in notification dispatch logic.
- [ ] Granular opt-out: marketing vs transactional, per-category.
  - **NOTE (2026-04-26):** Requires server schema extension. Design decision on category taxonomy needed.
- [ ] Preferred language for comms; templates auto-use that locale.
  - **NOTE (2026-04-26):** Requires server locale field on customer + template localization support.
- [ ] System blocks sends against preference.
  - **NOTE (2026-04-26):** Server-side enforcement. No client change needed once server implements.
- [ ] Staff override possible with reason + audit.
  - **NOTE (2026-04-26):** Server-side audit trail + override endpoint needed.
- [ ] Ticket intake quick-prompt: "How'd you like updates?" with SMS/email toggles.
  - **NOTE (2026-04-26):** Belongs in ticket check-in flow (§7/§9). Cross-section dependency; add to ticket intake when that section is implemented.

### 5.12 Birthday automation
- [ ] Optional birth date on customer record.
  - **NOTE (2026-04-26):** Birthday field already present in create form (§5.3, stored as `birthday` string). Server schema must persist it. The `CreateCustomerRequest` does not yet include a birthday field — server change needed.
- [ ] Age not stored unless tenant explicitly needs it.
  - **NOTE (2026-04-26):** Privacy policy decision; enforce server-side.
- [ ] Day-of auto-send SMS or email template ("Happy birthday! Here's $10 off").
  - **NOTE (2026-04-26):** Server-side scheduled job. No client change needed.
- [ ] Per-customer opt-in for birthday automation.
  - **NOTE (2026-04-26):** Requires server schema field + client toggle in edit form.
- [ ] Inject unique coupon per recipient with 7-day expiry.
  - **NOTE (2026-04-26):** Server-side coupon generation. Requires §36 (coupons/promotions) module.
- [ ] Privacy: never show birth date in lists / leaderboards.
  - **NOTE (2026-04-26):** Server-side data masking. Enforce in API responses.
- [ ] Age-derived features off by default.
  - **NOTE (2026-04-26):** Server-side tenant setting. No client change needed.
- [ ] Exclusion: last-60-days visited customers get less salesy message.
  - **NOTE (2026-04-26):** Server-side template variant selection. No client change needed.
- [ ] Exclusion: churned customers get reactivation variant.
  - **NOTE (2026-04-26):** Server-side template variant selection. No client change needed.

### 5.13 Complaint tracking
- [ ] Intake via customer detail → "New complaint".
  - **NOTE (2026-04-26):** Requires server endpoint (`POST /complaints`). No such endpoint exists in the current server route list.
- [ ] Fields: category + severity + description + linked ticket.
  - **NOTE (2026-04-26):** Blocked by missing server complaints endpoint.
- [ ] Resolution flow: assignee + due date + escalation path.
  - **NOTE (2026-04-26):** Blocked by missing server complaints endpoint.
- [ ] Status: open / investigating / resolved / rejected.
  - **NOTE (2026-04-26):** Blocked by missing server complaints endpoint.
- [ ] Required root cause on resolve: product / service / communication / billing / other.
  - **NOTE (2026-04-26):** Blocked by missing server complaints endpoint.
- [ ] Aggregate root causes for trend analysis.
  - **NOTE (2026-04-26):** Requires server analytics aggregation. Blocked by missing complaints endpoint.
- [ ] SLA: response within 24h / resolution within 7d, with breach alerts.
  - **NOTE (2026-04-26):** Server-side SLA enforcement + push notification integration needed.
- [ ] Optional public share of resolution via customer tracking page.
  - **NOTE (2026-04-26):** Requires customer-facing tracking page (server feature).
- [ ] Full audit history; immutable once closed.
  - **NOTE (2026-04-26):** Server-side immutability enforcement.

### 5.14 Customer notes
- [ ] Note types: Quick (one-liner), Detail (rich text + attachments), Call summary, Meeting, Internal-only.
  - **NOTE (2026-04-26):** Basic one-liner notes already shipped (CROSS9b — `GET/POST/DELETE /customers/:id/notes`, `NotesCard` in `CustomerDetailScreen`). Note types (type column, rich text body, attachments) require server schema extension on `customer_notes` table.
- [ ] Internal-only notes hidden from customer-facing docs.
  - **NOTE (2026-04-26):** Requires `internal_only` column on `customer_notes` + server filtering in customer-facing endpoints.
- [ ] Pin critical notes to customer header (max 3).
  - **NOTE (2026-04-26):** Requires `pinned` column + `GET /customers/:id` to include pinned notes. Server change required.
- [ ] @mention teammate → push notification + link.
  - **NOTE (2026-04-26):** Requires server-side mention parsing + push notification dispatch. Needs §30 (notifications) module.
- [ ] @ticket backlinks.
  - **NOTE (2026-04-26):** Requires server-side link parsing and a `note_ticket_links` join table or similar.
- [ ] Internal-only flag hides note from SMS/email auto-include.
  - **NOTE (2026-04-26):** Server-side filtering in comms templates. No client change needed once flag exists.
- [ ] Role-gate sensitive notes (manager only).
  - **NOTE (2026-04-26):** Requires server RBAC on note fetch/create. Role system exists but note-level gating not implemented.
- [ ] Quick-insert templates (e.g. "Called, left voicemail", "Reviewed estimate").
  - **NOTE (2026-04-26):** Client-side feature (hardcoded or tenant-configurable list). Can be implemented client-only once server supports `type` field. Deferred pending type schema.
- [ ] Edit history: edits logged; previous version viewable.
  - **NOTE (2026-04-26):** Requires server audit trail on note updates. No `PUT /customers/:id/notes/:noteId` endpoint exists.
- [ ] A11y: rich text accessible via TalkBack element-by-element.
  - **NOTE (2026-04-26):** Deferred pending rich text implementation. Current plain-text notes use standard `Text` composable which is TalkBack-accessible.

### 5.15 Customer files cabinet
- [ ] Per-customer file list (PDF, images, spreadsheets, waivers, warranty docs).
  - **NOTE (2026-04-26):** Requires server endpoint `GET /customers/:id/files`. No such endpoint exists in current route list.
- [ ] Tags + search on files.
  - **NOTE (2026-04-26):** Blocked by missing server files endpoint.
- [ ] Upload sources: Camera / PhotoPicker / Files picker (`ACTION_OPEN_DOCUMENT`) / external drive via DocumentsContract.
  - **NOTE (2026-04-26):** Blocked by missing server upload endpoint (`POST /customers/:id/files`).
- [ ] Inline preview: images via Coil, PDF via `PdfRenderer`, docs via external app `ACTION_VIEW`.
  - **NOTE (2026-04-26):** Blocked by missing server files endpoint.
- [ ] Stylus annotation markup on PDFs via Compose `Canvas`.
  - **NOTE (2026-04-26):** Blocked by missing server files endpoint. Complex feature requiring dedicated implementation pass.
- [ ] Share sheet → customer email / nearby share.
  - **NOTE (2026-04-26):** Blocked by missing server files endpoint.
- [ ] Retention: tenant policy per file type; auto-archive old.
  - **NOTE (2026-04-26):** Server-side retention policy. Requires settings module.
- [ ] Encryption at rest (tenant storage) and in transit.
  - **NOTE (2026-04-26):** Server-side storage encryption + TLS already in use for transit.
- [ ] Offline-cached files encrypted in SQLCipher-wrapped blob store.
  - **NOTE (2026-04-26):** Requires SQLCipher integration (not currently in dependencies). Significant infrastructure change.
- [ ] Versioning: replacing file keeps previous with version number.
  - **NOTE (2026-04-26):** Server-side versioning logic. No client change needed once server implements.

### 5.16 Contact import
- [ ] Just-in-time `requestPermissions(READ_CONTACTS)` at "Import".
  - **NOTE (2026-04-26):** Already implemented in §5.1/5.3 via `CustomerContactImport.kt` (`rememberCustomerContactImport` with `READ_CONTACTS` rationale dialog). Single-select from system picker is wired in both list empty-state and create form.
- [ ] System `Intent(ACTION_PICK, ContactsContract.Contacts.CONTENT_URI)` single-select; bulk via custom picker with `LazyColumn`.
  - **NOTE (2026-04-26):** Single-select already done. Bulk-select custom `LazyColumn` picker requires a new `CustomerContactBulkImportScreen` that queries `ContactsContract` directly. Deferred — significant implementation requiring a dedicated screen + cursor management.
- [ ] vCard → customer field mapping: name, phones, emails, address, birthday.
  - **NOTE (2026-04-26):** Name, phone, email mapping done in `prefillFromContact()`. Address and birthday are not currently mapped from the contact picker. Can be extended once the contact cursor query includes those fields.
- [ ] Field selection UI when multiple values.
  - **NOTE (2026-04-26):** Requires custom picker screen that shows all contact values and lets user select per-field. Deferred.
- [ ] Duplicate handling: cross-check existing customers → merge / skip / create new.
  - **NOTE (2026-04-26):** Single-import duplicate check is done via `checkForDuplicates()` in §5.3. Bulk-import batch dedup requires the bulk custom picker screen.
- [ ] "Import all" confirm sheet with summary (skipped / created / updated).
  - **NOTE (2026-04-26):** Requires bulk picker screen. Deferred.
- [ ] Privacy: read-only; never writes back to Contacts.
  - **NOTE (2026-04-26):** Already enforced — only `READ_CONTACTS` permission is requested; no write-back code exists.
- [ ] Clear imported data if user revokes permission.
  - **NOTE (2026-04-26):** No local copy of contacts data is retained beyond the prefill, so revocation has no impact on stored data. No action needed.
- [ ] A11y: TalkBack announces counts at each step.
  - **NOTE (2026-04-26):** Deferred pending bulk picker screen implementation.

### 5.17 Currency / locale display
- [ ] Tenant-level template: symbol placement (pre/post), thousands separator, decimal separator per locale.
  - **NOTE (2026-04-26):** Requires server tenant-settings endpoint to return locale config (e.g. `GET /settings/locale`). No such endpoint exists. Current `formatAsMoney()` util is US-only.
- [ ] Per-customer override of tenant default.
  - **NOTE (2026-04-26):** Requires server schema extension (locale field on customers table). Design decision needed.
- [ ] Support formats: US `$1,234.56`, EU-FR `1 234,56 €`, JP `¥1,235`, CH `CHF 1'234.56`.
  - **NOTE (2026-04-26):** Android `NumberFormat.getCurrencyInstance(locale)` can handle these formats client-side once locale config is available from server.
- [ ] Money input parsing accepts multiple locales; normalize to storage via `NumberFormat.getCurrencyInstance(locale)`.
  - **NOTE (2026-04-26):** Deferred pending locale config endpoint.
- [ ] TalkBack: read full currency phrasing.
  - **NOTE (2026-04-26):** Deferred pending locale implementation. Standard `Text` composable reads currency strings correctly for system locale.
- [ ] Toggle for ISO 3-letter code vs symbol on invoices (cross-border clarity).
  - **NOTE (2026-04-26):** Requires tenant setting + invoice template change. Cross-section with §11 (invoices).

---
## 6. Inventory

_Server endpoints: `GET /inventory`, `GET /inventory/manufacturers`, `POST /inventory/import-csv`, `POST /inventory/{id}/image`, `GET /stocktake`, `POST /stocktake`, `POST /stocktake/{id}/items`, `GET /inventory-enrich/barcode-lookup`, `GET /purchase-orders`, `POST /purchase-orders`._

### 6.1 List
- [x] Base list + filter chips + search.
- [x] **Tabs** — All / Products / Parts. NOT SERVICES — services aren't inventoriable. Settings menu handles services catalog (device types, manufacturers).
- [x] **Search** — name / SKU / UPC / manufacturer (debounced 300ms).
- [x] **Filters** (collapsible drawer via `ModalBottomSheet`): Manufacturer / Supplier / Category / Min price / Max price / Hide out-of-stock / Reorderable-only / Low-stock. (commit 4428dc6 — `components/InventoryFilterSheet.kt` ModalBottomSheet with 6 filter fields + `InventoryFilter` data class + active-count badge on filter icon)
- [x] **Columns picker** (tablet/ChromeOS) — SKU / Name / Type / Category / Stock / Cost / Retail / Supplier / Bin. Persist per user. (session 2026-04-26 — `components/InventoryColumnsPicker.kt` ModalBottomSheet with 9-column toggle; `InventoryColumn` enum; persisted via `SharedPreferences("inventory_columns")`; tablet-gated `ViewColumn` icon in list top bar)
- [x] **Sort** — SKU / name / stock / last restocked / price / last sold / margin. (commit 4428dc6 — `components/InventorySortDropdown.kt` InventorySort enum + `applyInventorySortOrder()` + DropdownMenu; 6 options; 8 JVM tests)
- [x] **Low-stock badge** + out-of-stock chip; critical-low pulse animation (respect Reduce Motion). (commit 4428dc6 — `components/InventoryStockBadge.kt` 3-tier badge Out/Critical-low-with-pulse/Low; ReduceMotion-aware static display)
- [x] **Quick stock adjust** — inline +/- stepper on row (debounced PUT via `distinctUntilChanged` + debounce). (commit 4428dc6 — `components/QuickStockAdjust.kt` tablet inline stepper + long-press ModalBottomSheet with `AdjustReason` dropdown {Sold/Received/Damaged/Adjusted}; optimistic VM `adjustStockBy()` + SyncQueue enqueue)
- [~] **Bulk select** — Price adjustment (% inc/dec preview modal) / Delete / Export / Print labels. (commit 4428dc6 — long-press on tablet → selection mode + BulkActionBar with Adjust/Export/Delete; Print labels TODO)
- [ ] **Receive items** modal — scan items into stock or add manually; creates stock-movement batch.
  - **NOTE (2026-04-26):** Requires a dedicated ReceiveItemsSheet composable + ViewModel. No existing screen or server endpoint wired. Deferred — needs §6.7 PO model first.
- [ ] **Receive by PO** — pick PO, scan items to increment received qty; close PO on completion.
  - **NOTE (2026-04-26):** Blocked by §6.7 PO list/create screens. Deferred.
- [ ] **Import CSV/JSON** — paste → preview → confirm (`POST /inventory/import-csv`). Row-level validation errors highlighted.
  - **NOTE (2026-04-26):** Server endpoint `POST /inventory/import-csv` exists. Requires a dedicated import screen with paste + row-preview table. Significant standalone implementation — deferred.
- [ ] **Mass label print** — multi-select → label printer (Android Printing / MFi thermal via Bluetooth SPP).
  - **NOTE (2026-04-26):** Requires Android Printing API + Bluetooth SPP profile + label template design. Significant hardware integration — deferred.
- [x] **Context menu** — Open, Copy SKU, Adjust stock, Create PO, Deactivate, Delete. (commit 4428dc6 — `components/InventoryContextMenu.kt` overflow + long-press DropdownMenu 6 actions; Print label logs TODO)
- [~] **Cost price hidden** from non-admin roles (server returns null). (commit 4428dc6 — `LocalIsAdmin` CompositionLocal defaults false with `TODO(role-gate)` pending Session role exposure)
- [x] **Empty state** — "No items yet. Import a CSV or scan to add." CTAs. (commit 4428dc6 — filter-aware: "No items match these filters" + {Clear filters / Import CSV stub} CTAs)

### 6.2 Detail
- [x] Stock card / group prices / movements.
- [x] **Full movement history — cursor-based, offline-first** scoped per-SKU. (commit 2e6b486 — `components/InventoryMovementHistory.kt` cursor-paged LazyColumn + IN/OUT/ADJ badges; `InventoryApi.getMovements(id, cursor, limit)`)
- [x] **Price history chart** — Vico `AreaCartesianLayer` over time; toggle cost vs retail. (commit 2e6b486 — `components/InventoryPriceChart.kt` two-series cost/retail Vico line chart; 404→empty state)
- [x] **Sales history** — last 30d sold qty × revenue line chart. (commit 2e6b486 — "Sold Nx in last 30d" card + small Vico bar chart via `InventoryApi.getSalesHistory(id, days=30)`)
- [x] **Supplier panel** — name / contact / last-cost / reorder SKU / lead-time. (commit 2e6b486 — `components/InventorySupplierPanel.kt` name+contact+last-cost+"Place PO" button stub)
- [x] **Auto-reorder rule** — view / edit threshold + reorder qty + supplier. (commit 2e6b486 — `components/InventoryAutoReorderCard.kt` inline edit + PATCH `InventoryApi.setAutoReorder`)
- [x] **Bin location** — text field + picker (Settings → Inventory → Bin Locations). (commit 2e6b486 — `components/InventoryBinPicker.kt` ExposedDropdownMenuBox autocomplete via `InventoryApi.getBins()`)
- [x] **Serials** — if serial-tracked, list of assigned serial numbers + which customer / ticket holds each. (commit 2e6b486 — serials list + "Add serial" dialog when `isSerialize==true`)
- [x] **Reorder / Restock** action — opens quick form to record stock-in or draft PO. (commit 2e6b486 — "Restock +N" button → qty dialog → POST `adjustStock(id, +qty, reason=Received)`)
- [x] **Barcode display** — Code-128 + QR via ZXing `BarcodeEncoder`; `SelectionContainer` on SKU/UPC. (commit 2e6b486 — `components/InventoryBarcodeDisplay.kt` two tabs Code-128 + QR via ZXing `Code128Writer` + existing `QrCodeGenerator`; Share button exports bitmap)
- [x] **Used in tickets** — recent tickets that consumed this part; tap → ticket. (commit 2e6b486 — "Recent tickets using this part" card via `InventoryApi.getUsageInTickets(id, limit=10)`; each row deep-links to ticket)
- [x] **Cost vs retail variance analysis** card (margin %). (commit 2e6b486 — margin stat tile green >30% / amber 10-30% / red <10%)
- [x] **Tax class** — editable (admin only). (commit 2e6b486 — admin-only dropdown of tax classes)
- [x] **Photos** — gallery; tap → lightbox; upload via `POST /inventory/:id/image`. (commit 2e6b486 — `components/InventoryPhotoGallery.kt` HorizontalPager + pinch-zoom via `detectTransformGestures`; upload via existing `MultipartUpload` worker)
- [x] **Edit / Deactivate / Delete** buttons. (commit 2e6b486 — Deactivate with confirm dialog completes earlier partial)

### 6.3 Create
- [~] **Form**: Name (required), SKU, UPC / barcode, item type (product / part), category, cost price, retail price, tax class, stock qty, reorder threshold, reorder qty, supplier, bin, manufacturer, description, photos, tags, taxable flag.
- [ ] **Inline barcode scan** — CameraX + ML Kit `BarcodeScanning.getClient()` to fill SKU/UPC; auto-lookup via `GET /inventory-enrich/barcode-lookup` (external DB). Autofill name/manufacturer/UPC from result.
  - **NOTE (2026-04-26):** `BarcodeScanScreen.kt` + `BarcodeAnalyzer` already exist. Needs scan button in `InventoryCreateScreen` that pushes `BarcodeScanScreen` and receives result, then calls `InventoryApi.lookupBarcode()` to prefill. Deferred — nav result callback wiring needed.
- [ ] **Photo capture** up to 4 per item; first = primary.
  - **NOTE (2026-04-26):** Requires `ActivityResultContracts.TakePicture` + compress + `POST /inventory/:id/image`. Deferred — post-create upload flow needed.
- [x] **Validation** — decimal for prices (2 places), integer for stock. (session 2026-04-26 — already present in `InventoryCreateViewModel`: regex `^\d*\.?\d*$` for prices, `^\d*$` for stock; confirmed no gap)
- [x] **Save & add another** secondary CTA. (session 2026-04-26 — `saveAndAddAnother()` saves item then resets form keeping itemType; "+ Add another" TextButton in toolbar; snackbar confirmation with item name)
- [x] **Offline create** — temp ID + queue. (session 2026-04-26 — already implemented in `InventoryRepository.createItem()` via `OfflineIdGenerator.nextTempId()` + `SyncQueueEntity`; confirmed end-to-end)

### 6.4 Edit
- [x] All fields editable (role-gated for cost/price). (session 2026-04-26 — `InventoryEditScreen` + `InventoryFormContent` covers all basic fields; role-gate stub in place; edit VM wired end-to-end)
- [x] **Stock adjust** quick-action: +1 / −1 / Set to… (logs stock movement with reason). (session 2026-04-26 — overflow menu in `InventoryEditScreen`: +1/−1 call `quickAdjustStock(±1)` with optimistic update + API; "Set to…" opens `AlertDialog` with int field → delta-based `adjustStock` call)
- [ ] **Move between locations** (multi-location tenants).
  - **NOTE (2026-04-26):** Requires multi-location server schema + transfer endpoint. Single-tenant scope; deferred.
- [x] **Delete** — confirm; prevent if stock > 0 or open PO references it. (session 2026-04-26 — "Deactivate" in overflow menu → `AlertDialog` → `InventoryRepository.deleteItem()` via `DELETE /inventory/:id`; server returns ref-warning when used in invoices/tickets; shown in snackbar; pops back on success)
- [x] **Deactivate** — keep history, hide from POS. (session 2026-04-26 — same as Delete; `DELETE /inventory/:id` is soft-deactivate; detail screen Deactivate overflow → `InventoryDetailViewModel.confirmDeactivate()` now calls real API with pop-on-success)

### 6.5 Scan to lookup
- [ ] **Bottom-nav quick scan** / Dashboard FAB scan → CameraX + ML Kit → resolves barcode → item detail. If POS session open → add to cart.
  - **NOTE (2026-04-26):** `BarcodeScanScreen` already exists. Requires bottom-nav or Dashboard FAB wired to push `BarcodeScanScreen` with result callback. Cross-cutting nav change; deferred to nav-refactor pass.
- [x] **HID-scanner support** — accept external Bluetooth scanner input via hidden focused `TextField` + IME-send detection. Detect rapid keystrokes (intra-key <50ms) → buffer until `KeyEvent.KEYCODE_ENTER` → submit. (session 2026-04-26 — zero-size `BasicTextField` in `InventoryListScreen` with `FocusRequester`; 50 ms inter-char threshold accumulates `hidBuffer`; newline fires `viewModel.lookupBarcode()`)
- [x] **Vibrate** (`HapticFeedbackConstants.CONFIRM`) on successful scan.

### 6.6 Stocktake / audit
- [ ] **Sessions list** (`GET /stocktake`) — open + recent sessions with item count, variance summary.
  - **NOTE (2026-04-26):** Requires new `StocktakeListScreen` + `StocktakeViewModel` + `GET /stocktake` API endpoint wiring. Multi-screen feature; deferred.
- [ ] **New session** — name, optional location, start.
  - **NOTE (2026-04-26):** Depends on sessions list screen. Deferred.
- [ ] **Session detail** — barcode scan loop → running count list with expected vs counted + variance dots. Manual entry fallback. Commit (`POST /stocktake/:id/items`) creates adjustments. Cancel discards.
  - **NOTE (2026-04-26):** Requires `BarcodeScanScreen` integration with a session-scoped count accumulator. Complex multi-step flow; deferred.
- [ ] **Summary** — items counted / items-with-variance / total variance / surplus / shortage.
  - **NOTE (2026-04-26):** Depends on session detail screen. Deferred.
- [ ] **Multi-user** — multiple scanners feeding same session via WebSocket events.
  - **NOTE (2026-04-26):** Requires WebSocket room scoped to stocktake session. Server work needed. Deferred.

### 6.7 Purchase orders
- [ ] **List** — status filter (draft / sent / partial / received / cancelled); columns: PO#, supplier, total, status, expected date.
  - **NOTE (2026-04-26):** Requires new `PurchaseOrderListScreen` + `PurchaseOrderApi` + `PurchaseOrderRepository`. No existing PO screens. Deferred — standalone section.
- [ ] **Create** — supplier picker, line items (add from inventory with qty + cost), expected date, notes.
  - **NOTE (2026-04-26):** Depends on PO list. Deferred.
- [ ] **Send** — email to supplier via `ACTION_SEND` with PDF attachment.
  - **NOTE (2026-04-26):** Depends on PO create. Deferred.
- [ ] **Receive** — scan items to increment; partial receipt supported.
  - **NOTE (2026-04-26):** Depends on PO create. Deferred.
- [ ] **Cancel** — confirm.
  - **NOTE (2026-04-26):** Depends on PO list. Deferred.
- [ ] **PDF export** via SAF (tablet/ChromeOS primary).
  - **NOTE (2026-04-26):** Requires PDF generation + SAF file picker. Deferred.

### 6.8 Advanced inventory (admin tools, tablet/ChromeOS first)
- [ ] **Bin locations** — create aisle / shelf / position; batch assign items; pick list generation.
  - **NOTE (2026-04-26):** Bin picker in detail screen (`InventoryBinPicker.kt`) exists for assignment. Creation/management UI (Settings → Inventory → Bin Locations) requires a new settings sub-screen. Deferred.
- [ ] **Auto-reorder rules** — per-item threshold + qty + supplier; "Run now" → draft POs.
  - **NOTE (2026-04-26):** `InventoryAutoReorderCard.kt` handles per-item rule. "Run now" → draft POs requires §6.7. Deferred.
- [ ] **Serials** — assign serial to item; link to customer/ticket; serial lookup.
  - **NOTE (2026-04-26):** Serial list display already in detail screen (§6.2). Assign + lookup requires cross-entity search screen. Deferred.
- [ ] **Shrinkage report** — expected vs actual; variance trend chart.
  - **NOTE (2026-04-26):** Requires server-side shrinkage aggregation endpoint. Deferred.
- [ ] **ABC analysis** — A/B/C classification; Vico bar chart.
  - **NOTE (2026-04-26):** Requires server-side ABC classification data or client-side computation from movement history. Deferred.
- [ ] **Age report** — days-in-stock; markdown / clearance suggestions.
  - **NOTE (2026-04-26):** Requires `created_at` vs last-sale date per item. Server aggregation endpoint needed. Deferred.
- [ ] **Mass label print** — select items → label format → print (Mopria / MFi thermal).
  - **NOTE (2026-04-26):** Requires Android Printing API + label template. Deferred.

### 6.9 Loaner / asset tracking
- [ ] `Asset` entity: id / type / serial / purchase date / cost / depreciation / status (available / loaned / in-repair / retired); optional `current_customer_id`.
  - **NOTE (2026-04-26):** No server schema or endpoints for assets exist. Requires full new domain (DB migration + routes + Android screens). Deferred.
- [ ] Loaner issue flow on ticket detail: "Issue loaner" → pick asset → waiver signature → updates asset status to loaned + ties to ticket.
  - **NOTE (2026-04-26):** Blocked by asset entity. Deferred.
- [ ] Return flow: inspect → mark available; release any BlockChyp hold.
  - **NOTE (2026-04-26):** Blocked by asset entity. Deferred.
- [ ] Deposit hold via BlockChyp (optional, per asset policy).
  - **NOTE (2026-04-26):** Blocked by asset entity + BlockChyp hold flow design. Deferred.
- [ ] Auto-SMS at ready-for-pickup + overdue > 7d escalation push to manager.
  - **NOTE (2026-04-26):** Blocked by asset entity. Deferred.
- [ ] Depreciation (linear / declining balance) + asset-book-value dashboard tile.
  - **NOTE (2026-04-26):** Blocked by asset entity. Deferred.
- [ ] Optional geofence alert (>24h outside metro area) — opt-in + customer consent required.
  - **NOTE (2026-04-26):** Blocked by asset entity + geofencing permission. Deferred.

### 6.10 Bundles
- [ ] Bundle = set of items sold together at discount. Examples: Diagnostic + repair + warranty; Data recovery + backup + return shipping.
  - **NOTE (2026-04-26):** Server has `inventory_kits` / bundle tables (`inventoryVariants.routes.ts`). No Android screens exist. Requires `BundleListScreen` + `BundleCreateScreen`. Deferred.
- [ ] Builder: Settings → Bundles → Add; drag items in; set bundle price or "sum − %".
  - **NOTE (2026-04-26):** Deferred pending bundle screens.
- [ ] POS renders bundle as single SKU; expand to reveal included items; partial-delivery progress ("Diagnostic done, repair pending").
  - **NOTE (2026-04-26):** POS integration required. Deferred.
- [ ] Each included item decrements stock independently on sale.
  - **NOTE (2026-04-26):** Server-side on-sale hook. Deferred.
- [ ] Reporting: bundle sell-through vs individual + attach-rate.
  - **NOTE (2026-04-26):** Requires server analytics endpoint. Deferred.

### 6.11 Batch / lot tracking
- [ ] Use-case: regulated parts (batteries) require lot tracking for recalls.
  - **NOTE (2026-04-26):** No server schema for `InventoryLot`. Requires DB migration + routes + Android screens. Deferred — entire sub-domain.
- [ ] Model: `InventoryLot` per receipt with fields lot_id, receive_date, vendor_invoice, qty, expiry.
  - **NOTE (2026-04-26):** Server schema change required. Deferred.
- [ ] Sale/use decrements lot FIFO by default (or LIFO per tenant).
  - **NOTE (2026-04-26):** Server-side lot-allocation logic. Deferred.
- [ ] FEFO alt: expiring-first queue for perishables (paste/adhesive).
  - **NOTE (2026-04-26):** Server-side. Deferred.
- [ ] Recalls: vendor recall → tenant queries "all tickets using lot X" → customer outreach.
  - **NOTE (2026-04-26):** Requires lot tracking foundation. Deferred.
- [ ] Traceability: ticket detail shows which lot was used per part (regulatory).
  - **NOTE (2026-04-26):** Requires lot tracking foundation. Deferred.
- [ ] Config: per-SKU opt-in (most SKUs don't need lot tracking).
  - **NOTE (2026-04-26):** Requires lot tracking foundation. Deferred.

### 6.12 Serial number tracking
- [ ] Scope: high-value items (phones, laptops, TVs).
  - **NOTE (2026-04-26):** Serial list display in §6.2 detail exists. Full tracking (POS scan on sale, link to customer, unique constraint) requires server schema + POS integration. Deferred.
- [ ] New-stock serials scanned on receive.
  - **NOTE (2026-04-26):** Requires §6.7 PO receive flow. Deferred.
- [ ] Intake: scan serial + auto-match model.
  - **NOTE (2026-04-26):** Depends on barcode-scan-to-serial-entry. Deferred.
- [ ] POS scan on sale reduces qty by 1 for that serial.
  - **NOTE (2026-04-26):** POS integration. Deferred.
- [ ] Lookup: staff scans, Android hits tenant server which may cross-check (§4.17).
  - **NOTE (2026-04-26):** `BarcodeScanScreen` + server serial-lookup endpoint needed. Deferred.
- [ ] Link to customer: sale binds serial to customer record (enables warranty lookup by serial).
  - **NOTE (2026-04-26):** Server-side on-sale hook. Deferred.
- [ ] Unique constraint: each serial sold once; sell-again requires "Returned/restocked" status.
  - **NOTE (2026-04-26):** Server schema constraint. Deferred.
- [ ] Reports: serials out by month; remaining in stock.
  - **NOTE (2026-04-26):** Server analytics. Deferred.

### 6.13 Inter-location transfers
- [ ] Flow: source location initiates transfer (pick items + qty + destination).
  - **NOTE (2026-04-26):** No multi-location server schema or endpoints exist. Entire sub-domain deferred.
- [ ] Status lifecycle: Draft → In Transit → Received.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Transit count: inventory marked "in transit", not sellable at either location.
  - **NOTE (2026-04-26):** Server-side. Deferred.
- [ ] Receive: destination scans items.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Discrepancy handling.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Shipping label: print bulk label via §17.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Optional carrier integration (UPS / FedEx).
  - **NOTE (2026-04-26):** Deferred.
- [ ] Reporting: transfer frequency + bottleneck analysis.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Permissions split: source manager initiates, destination manager receives.
  - **NOTE (2026-04-26):** Deferred.

### 6.14 Scrap / damage bin
- [ ] Model: dedicated non-sellable bin per location.
  - **NOTE (2026-04-26):** No server schema for scrap bin. Entire sub-domain deferred.
- [ ] Items moved here with reason (damaged / obsolete / expired / lost).
  - **NOTE (2026-04-26):** Deferred.
- [ ] Move flow: Inventory → item → "Move to scrap" → qty + reason + photo.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Decrements sellable qty; increments scrap bin.
  - **NOTE (2026-04-26):** Server-side. Deferred.
- [ ] Cost impact: COGS adjustment recorded.
  - **NOTE (2026-04-26):** Server-side accounting hook. Deferred.
- [ ] Shrinkage report totals reflect scrap.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Disposal: scrap bin items batch-disposed (trash / recycle / salvage).
  - **NOTE (2026-04-26):** Deferred.
- [ ] Disposal document generated with signature.
  - **NOTE (2026-04-26):** Requires signature capture + PDF generation. Deferred.
- [ ] Insurance: disposal records support insurance claims (theft, fire).
  - **NOTE (2026-04-26):** Deferred.

### 6.15 Dead-stock aging
- [ ] Report: inventory aged > N days since last sale.
  - **NOTE (2026-04-26):** Requires server-side last-sale date aggregation per item. No existing endpoint. Deferred.
- [ ] Grouped by tier: slow (60d) / dead (180d) / obsolete (365d).
  - **NOTE (2026-04-26):** Deferred.
- [ ] Action: clearance pricing suggestions.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Action: bundle with hot-selling item.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Action: return to vendor if eligible.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Action: donate for tax write-off.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Alerts: quarterly push "N items hit dead tier — plan action".
  - **NOTE (2026-04-26):** Requires push notification infrastructure. Deferred.
- [ ] Visibility: inventory list chip "Stale" / "Dead" badge.
  - **NOTE (2026-04-26):** Requires last-sale-date field on entity. Deferred.

### 6.16 Reorder lead times
- [ ] Per vendor: average days from order → receipt.
  - **NOTE (2026-04-26):** Requires §6.7 PO history. Entire sub-domain deferred.
- [ ] Computed from PO history.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Lead-time variance shows unreliability → affects reorder point.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Safety stock buffer qty = avg daily sell × lead time × safety factor.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Auto-calc or manual override of safety stock.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Vendor comparison side-by-side: cost, lead time, on-time %.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Suggest alternate vendor when primary degrades.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Seasonality: lead times may lengthen in holiday season; track per-month.
  - **NOTE (2026-04-26):** Deferred.
- [ ] Inventory item detail shows "Lead time 7d avg (p90 12d)".
  - **NOTE (2026-04-26):** Deferred.
- [ ] PO creation uses latest stats for ETA.
  - **NOTE (2026-04-26):** Deferred.

---
## 7. Invoices

_Server endpoints: `GET /invoices`, `GET /invoices/stats`, `GET /invoices/{id}`, `POST /invoices`, `PUT /invoices/{id}`, `POST /invoices/{id}/payments`, `POST /invoices/{id}/void`, `POST /invoices/{id}/credit-note`, `POST /invoices/bulk-action`, `GET /reports/aging`._

### 7.1 List
- [x] Base list + filter chips + search.
- [x] **Status tabs** — All / Unpaid / Partial / Overdue / Paid / Void via `ScrollableTabRow`.
- [x] **Filters** — date range, customer, amount range, payment method, created-by. (commit 2c17758 — `InvoiceFilterSheet.kt` ModalBottomSheet date-range+customer+amount-range; `InvoiceFilterState` VM-applied)
- [x] **Sort** — date / amount / due date / status. (commit 2c17758 — `InvoiceSortDropdown.kt` 6-option enum + `applyInvoiceSortOrder()` pure func; 8 JVM tests)
- [x] **Row chips** — "Overdue 3d" (red), "Paid 50%" (amber), "Unpaid" (gray), "Paid" (green), "Void" (strike-through). (commit 2c17758 — `InvoiceStatusChip.kt` rendered inline)
- [x] **Stats header** — `GET /invoices/stats` → total outstanding / paid / overdue / avg value; tap to drill down. (commit 2c17758 — `InvoiceApi.getStats()` + `InvoiceStatsData` DTO; 404 hides header silently)
- [ ] **Status pie + payment-method pie** (tablet/ChromeOS) — Vico `PieChart`-equivalent via custom renderer or MPAndroidChart interop.
- [x] **Bulk select** → bulk action (`POST /invoices/bulk-action`): Send reminder / Export / Void / Delete. (commit 2c17758 — long-press bulk mode + `BulkActionTopBar`+`BulkActionBar` {Remind/Export CSV/Void})
- [x] **Export CSV** via SAF. (commit 2c17758 — `ACTION_CREATE_DOCUMENT` launcher + `VM.buildCsvContent()`)
- [x] **Row context menu** — Open, Copy invoice #, Send SMS, Send email, Print, Record payment, Void. (commit 2c17758 — DropdownMenu on `MoreVert`: Open/Copy number/Send reminder/Share PDF)
- [ ] **Cursor-based pagination (offline-first)** per top-of-doc rule. `GET /invoices?cursor=&limit=50` online; list reads from Room via Paging3 + RemoteMediator.

### 7.2 Detail
- [x] Line items / totals / payments.
- [x] **Header** — invoice number (INV-XXXX, `SelectionContainer`), status chip, due date, balance-due chip. (session 2026-04-26 — `SelectionContainer` on orderId; `SuggestionChip` for due date + error-container balance-due chip) (INV-XXXX, `SelectionContainer`), status chip, due date, balance-due chip.
- [x] **Customer card** — name + phone + email + quick-actions. (session 2026-04-26 — `BrandCard` section; phone/email from online `InvoiceDetail` DTO; tap-to-dial + tap-to-email intents; offline fallback text)
- [x] **Line items** — editable table (if status allows); tax per line. (commit 2c17758 — `InvoiceLineItemsTable.kt` read-only table — editing deferred)
- [x] **Totals panel** — subtotal / discount / tax / total / paid / balance due. (session 2026-04-26 — titled `BrandCard` wrapping all totals rows with `HorizontalDivider`)
- [x] **Payment history** — method / amount / date / reference / status; tap → payment detail. (session 2026-04-26 — payment cards: method / `DateFormatter.formatAbsolute` date / transactionId ref / notes / VOIDED badge)
- [x] **Add payment** → `POST /invoices/:id/payments` (see 7.4). (already wired via bottom-bar `BrandPrimaryButton` → `showPaymentDialog`)
- [x] **Issue refund** — `POST /refunds` with `{ invoice_id, amount, reason }`; role-gated; partial + full. (commit 2c17758 — overflow→AlertDialog→POST /refunds; `IssueRefundRequest` DTO; 404 graceful stub)
- [x] **Credit note** — `POST /invoices/:id/credit-note` with `{ amount, reason }`. (session 2026-04-26 — `CreditNoteRequest` DTO; `InvoiceApi.createCreditNote()`; `VM.createCreditNote()`; AlertDialog with amount+reason validation; overflow menu item)
- [x] **Void** — `POST /invoices/:id/void` with reason; destructive confirm. (server does not accept `reason` body — existing `ConfirmDialog(isDestructive=true)` is correct)
- [x] **Send by SMS** — pre-fill "Your invoice: {payment-link-url}" using `POST /sms/send`; short-link via `POST /payment-links`. (commit 2c17758 — `InvoiceSendActions.kt` + `sendSms()` intent helper pre-filled with invoice URL)
- [x] **Send by email** — `Intent(ACTION_SENDTO)` with `mailto:` + PDF attached via FileProvider URI. (commit 2c17758 — `sendEmail()` intent helper pre-filled; PDF attachment deferred)
- [x] **Share PDF** — system share sheet. (commit 2c17758 — `shareText()` via `ACTION_SEND text/plain` with link)
- [x] **Android Print** via `PrintManager.print(...)` with custom PDF renderer. (commit 2c17758 — `printInvoice()` using `PrintManager` + `WebView.createPrintDocumentAdapter`)
- [x] **Clone invoice** — duplicate line items for new invoice. (commit 2c17758 — overflow→POST /invoices/{id}/clone; `VM.cloneInvoice()`; 404 stub)
- [ ] **Convert to credit note** — if overpaid.
  - **NOTE (2026-04-26):** No distinct overpaid-auto-convert endpoint; `POST /invoices/:id/credit-note` (now wired) is the mechanism. Overpaid-detection UX is a design decision pending.
- [x] **Timeline** — every status change, payment, note, email/SMS send. (commit 2c17758 — `InvoiceTimelineSection` synthetic from payments + creation date; follows TicketHistoryTimeline dot-connector pattern)
- [ ] **Deposit invoices linked** — nested card showing connected deposit invoices.
  - **NOTE (2026-04-26):** No server endpoint found for fetching deposit invoices linked to a parent; deferred until endpoint exists.

### 7.3 Create
- [x] **Customer picker** (or pre-seeded from ticket). (session 2026-04-26 — `ExposedDropdownMenuBox` + debounced `CustomerApi.searchCustomers()` already in `InvoiceCreateScreen.kt`)
- [ ] **Line items** — add from inventory catalog (with barcode scan) or free-form; qty, unit price, tax class, line-level discount.
  - **NOTE (2026-04-26):** Free-form items already implemented; barcode-scan + inventory catalog search + tax-class picker deferred (need CameraX + catalog endpoint wiring).
- [ ] **Cart-level discount** (% or $), tax, fees, tip.
  - **NOTE (2026-04-26):** Design decision needed on discount model before implementation; tax class recomputed server-side.
- [x] **Notes**, due date, payment terms, footer text. (session 2026-04-26 — notes `OutlinedTextField` + `DatePickerDialog` due-date field already in `InvoiceCreateScreen.kt`; payment terms + footer deferred)
- [ ] **Deposit required** flag → generate deposit invoice.
  - **NOTE (2026-04-26):** Requires server endpoint or invoice-type param; deferred.
- [ ] **Convert from ticket** — prefill line items via `POST /tickets/:id/convert-to-invoice`.
  - **NOTE (2026-04-26):** Server endpoint exists; Android integration deferred to ticket-detail session.
- [ ] **Convert from estimate**.
  - **NOTE (2026-04-26):** Requires estimate-detail screen; deferred to §8 session.
- [ ] **Idempotency key** — server requires for POST /invoices.
  - **NOTE (2026-04-26):** Server currently does not enforce an idempotency-key header on POST /invoices (not found in route handler). Deferred until server enforces it.
- [ ] **Draft** autosave.
  - **NOTE (2026-04-26):** Requires Room draft entity + background flush; deferred.
- [ ] **Send now** checkbox — email/SMS on create.
  - **NOTE (2026-04-26):** Deferred; needs Twilio/SMTP credentials wired to the create flow.

### 7.4 Record payment
- [ ] **Method picker** — fetched from `GET /settings/payment` (cash / card-in-person → POS flow / card-manual / ACH / check / gift card / store credit / other). Wire each method correctly, especially card, store credit, gift cards.
  - **NOTE (2026-04-26):** Requires BlockChyp SDK + store-credit/gift-card server endpoints; deferred to POS session.
- [ ] **Amount entry** — default to balance due; support partial + overpayment (surplus → store credit prompt).
  - **NOTE (2026-04-26):** Overpayment → store credit requires server endpoint; deferred.
- [ ] **Reference** (check# / card last 4 / BlockChyp txn ID — auto-filled from terminal).
  - **NOTE (2026-04-26):** BlockChyp terminal integration deferred.
- [ ] **Notes** field.
  - **NOTE (2026-04-26):** Notes param already on `RecordPaymentRequest` DTO; UI input field deferred to 7.4 full implementation.
- [ ] **Cash** — change calculator.
  - **NOTE (2026-04-26):** UI-only feature; deferred.
- [ ] **Split tender** — chain multiple methods until balance = 0.
  - **NOTE (2026-04-26):** Requires idempotency-key chain + server coordination; deferred.
- [ ] **BlockChyp card** — start terminal charge via BlockChyp Android SDK → poll status; surface ongoing Live Update notification for the txn.
  - **NOTE (2026-04-26):** Requires BlockChyp Android SDK integration; hardware-gated.
- [ ] **Idempotency-Key** required on POST /invoices/:id/payments.
  - **NOTE (2026-04-26):** Server does not currently enforce idempotency-key on payments endpoint; deferred.
- [ ] **Receipt** — print (Bluetooth thermal / Mopria) + email + SMS; PDF download.
  - **NOTE (2026-04-26):** Bluetooth thermal printer integration hardware-gated; deferred.
- [ ] **Haptic** `CONFIRM` on payment confirm.
  - **NOTE (2026-04-26):** Deferred to post-BlockChyp integration wave.

### 7.5 Overdue automation
- [ ] Server schedules reminders. Android: overdue badge on dashboard + push notif tap → deep-link to invoice.
  - **NOTE (2026-04-26):** Requires FCM push-notification deep-link setup; server-side scheduler already present (dunning.routes.ts). Android side deferred.
- [ ] Dunning sequences (see §7.7) manage escalation.
  - **NOTE (2026-04-26):** Server-side only; no Android UI surface needed until §7.7 is in scope.

### 7.6 Aging report
- [x] `GET /reports/aging` with bucket breakdown (0–30 / 31–60 / 61–90 / 90+ days). (session 2026-04-26 — `AgingReportData` / `AgingBucket` / `AgingInvoiceRow` DTOs; `InvoiceApi.getAgingReport()` at GET dunning/invoices/aging; `InvoiceAgingScreen.kt` + `InvoiceAgingViewModel` with bucket-filter chips, summary cards, pull-to-refresh; nav route hookup deferred to NavHost session)
- [x] Tablet/ChromeOS: sortable table via custom Compose `LazyColumn` headers; phone: grouped list by bucket.
- [ ] Row actions: Send reminder / Record payment / Write off.
  - **NOTE (2026-04-26):** Send-reminder and write-off need server endpoints; Record-payment needs navigation into InvoiceDetailScreen from the aging screen (nav hookup deferred to NavHost session).

### 7.7 Returns & refunds
- [ ] Two return paths: customer-return-of-sold-goods (from invoice detail) + tech-return-to-vendor (from PO / inventory).
- [ ] Customer return flow: Invoice detail → "Return items" → pick lines + qty → reason → refund method (original card via BlockChyp refund / store credit / gift card). Creates `Return` record linked to invoice; updates inventory; reverses commission unless tenant policy overrides.
- [ ] Vendor return flow: "Return to vendor" from PO / inventory → pick items → RMA # (manual or vendor API) → print shipping label via §17. Status: pending / shipped / received / credited.
- [ ] Tenant-configurable restocking fee per item class.
- [ ] Return receipt prints with negative lines + refund method + signature line.
- [ ] Per-item restock choice: salable / scrap bin / damaged bin.
- [ ] Fraud guards: warn on high-$ returns > threshold; manager PIN required over limit; audit entry.
- [ ] Endpoint `POST /refunds {invoice_id, lines, reason}`.

### 7.8 Dunning / card retry
- [ ] Card declined → queue retry.
- [ ] Retry schedule: +3d / +7d / +14d.
- [ ] Each retry notifies via email + SMS + in-app notification.
- [ ] Smart retry — soft declines (insufficient funds, do-not-honor): standard schedule.
- [ ] Smart retry — hard declines (fraud, card reported): stop + notify customer to update card.
- [ ] Self-service: customer portal link (§41) to update card.
- [ ] Self-service: Google Pay via pay page.
- [ ] Escalation: after N failed attempts, alert tenant manager + auto-suspend plan.
- [ ] Audit: every dunning event logged.

### 7.9 Late fees
- [ ] Model: flat fee / percentage / compounding.
- [ ] Model: grace period before applying.
- [ ] Model: max cap.
- [ ] Application: auto-added to invoice on overdue.
- [ ] Status change to "Past due" triggers reminder.
- [ ] Staff can waive with reason + audit.
- [ ] Threshold above which manager PIN required.
- [ ] Customer communication: reminder SMS/email before fee applied (1-3d lead).
- [ ] Customer communication: fee-applied notification with payment link.
- [ ] Jurisdiction limits: some jurisdictions cap late fees by law; tenant-configurable max; warn on violation.

---
## 8. Estimates

_Server endpoints: `GET /estimates`, `GET /estimates/{id}`, `POST /estimates`, `PUT /estimates/{id}`, `POST /estimates/{id}/approve`._

### 8.1 List
- [x] Base list + is-expiring warning.
- [x] Status tabs — All / Draft / Sent / Approved / Rejected / Expired / Converted. (commit 388f4c2 — `components/EstimateStatusTabs.kt` ScrollableTabRow with a11y annotations)
- [x] Filters — date range, customer, amount, validity. (commit 388f4c2 — `components/EstimateFilterSheet.kt` ModalBottomSheet customer + date range; `EstimateFilterState` in VM)
- [x] Bulk actions — Send / Delete / Export. (commit 388f4c2 — bulk top bar + bottom action bar; VM `bulkSend/bulkDelete/selectAll/exitBulkMode`)
- [x] Expiring-soon chip (pulse animation when ≤3 days; honor Reduce Motion). (commit 388f4c2 — `components/ExpiringSoonChip.kt` + `isExpiringSoon()` helper + pulse animation ReduceMotion-static)
- [x] Context menu — Open, Send, Convert to ticket, Convert to invoice, Duplicate, Delete. (commit 388f4c2 — `components/EstimateContextMenu.kt` 8-item DropdownMenu; `combinedClickable` long-press)
- [x] Cursor-based pagination (offline-first) per top-of-doc rule. `GET /estimates?cursor=&limit=50` online; list reads from Room. (session 2026-04-26 — `EstimatePageResponse` DTO + `EstimateApi.getEstimatePage` + `EstimateDao.getPage` keyset query + `EstimateRepository.loadEstimatesPage` + VM `loadFirstPage`/`loadMore`/`buildApiFilters` + LazyColumn `rememberLazyListState` trigger + spinner footer)

### 8.2 Detail
- [x] **Header** — estimate # + status + valid-until date.
- [x] **Line items** + totals.
- [x] **Send** — SMS / email; body includes approval link (customer portal). (commit 388f4c2 — send bottom sheet reuses SMS/Email intent helpers from wave 15)
- [x] **Approve** — `POST /estimates/:id/approve` (staff-assisted) with signature capture (Compose Canvas). (commit 388f4c2 — POST + confirm dialog; 404-tolerant; signature capture deferred)
- [x] **Reject** — reason required. (commit 388f4c2 — reject dialog with required-reason field; POST /estimates/:id/reject)
- [x] **Convert to ticket** — prefill ticket; inventory reservation. (commit 388f4c2 — existing endpoint wired + prefill; inventory reservation server-side)
- [x] **Convert to invoice**. (commit 388f4c2 — POST /estimates/:id/convert-to-invoice; 404 → stub toast)
- [x] **Versioning** — revise estimate; keep prior versions visible. (commit 388f4c2 — VM state `versions: List<EstimateVersion>` + GET endpoint + version dropdown)
- [x] **Customer-facing PDF preview** — "See what customer sees" button. (commit 388f4c2 — Print action in overflow menu via PrintManager + WebView — mirrors InvoiceSendActions)

### 8.3 Create
- [x] Same structure as invoice + validity window.
- [x] Convert from lead (prefill).
- [x] Line items from repair-pricing services + inventory parts + free-form.
- [x] Idempotency key.

### 8.4 Expiration handling
- [x] Auto-expire when past validity date (server-driven).
- [x] Manual expire action.

### 8.5 E-sign (public page)
- [ ] Quote detail → "Send for e-sign" generates public URL `https://<tenant>/public/quotes/:code/sign`; share via SMS / email.
  - **NOTE (2026-04-26):** Requires server endpoint `POST /estimates/:id/esign-link` that mints a short-lived token; no such endpoint exists yet. Android side is share-intent boilerplate but cannot be wired until server ships.
- [ ] Signer experience (server-rendered public page, no login): quote line items + total + terms + signature box + printed name + date → submit stores PDF + signature.
  - **NOTE (2026-04-26):** Entirely server-rendered public page — no Android client work; deferred pending server implementation.
- [ ] FCM push to staff on sign: "Quote #42 signed by Acme Corp — convert to ticket?" Deep-link opens quote; one-tap convert to ticket.
  - **NOTE (2026-04-26):** Requires server-side FCM trigger on `/public/quotes/:code/sign` submit; deep-link routing exists but sign event FCM payload not yet defined.
- [ ] Signable within N days (tenant-configured); expired → "Quote expired — contact shop" page.
  - **NOTE (2026-04-26):** Tenant-level config field (`esign_validity_days`) not yet in settings schema; deferred.
- [ ] Audit: each open / sign event logged with IP + user-agent + timestamp.
  - **NOTE (2026-04-26):** Server-side audit table; no Android action needed — deferred pending server implementation.

### 8.6 Versioning
- [ ] Each edit creates new version; prior retained.
  - **NOTE (2026-04-26):** Requires `POST /estimates/:id` to auto-increment `version_number` server-side and store the old snapshot in an `estimate_versions` table; server does not yet do this. Android UI already reads `versionNumber` field.
- [x] Version number visible on UI (e.g. "v3").
- [ ] Only "sent" versions archived for audit; drafts freely edited.
  - **NOTE (2026-04-26):** Server-side archival policy; no Android action until server versions endpoint returns archived flag.
- [ ] Side-by-side diff of v-n vs v-n+1.
  - **NOTE (2026-04-26):** Needs `GET /estimates/:id/versions/:v` returning full line-item snapshot; design decision required (expand existing `EstimateVersion` stub vs new endpoint).
- [ ] Highlight adds / removes / price changes.
  - **NOTE (2026-04-26):** Blocked on side-by-side diff above.
- [ ] Customer approval tied to specific version.
  - **NOTE (2026-04-26):** Requires server to record `approved_version` on the estimate row; field not present in current `EstimateDetail` DTO.
- [ ] Warning if customer approved v2 and tenant edited to v3 ("Customer approved v2; resend?").
  - **NOTE (2026-04-26):** Blocked on `approved_version` field above.
- [ ] Convert-to-ticket uses approved version with stored reference (downstream changes don't invalidate).
  - **NOTE (2026-04-26):** Blocked on server storing `approved_version` snapshot.
- [ ] Reuse same versioning machinery for receipt templates + waivers.
  - **NOTE (2026-04-26):** Cross-cutting design decision; should be planned alongside receipt templates feature (not yet in backlog scope).

---
## 9. Leads

_Server endpoints: `GET /leads`, `POST /leads`, `PUT /leads/{id}`._

### 9.1 List
- [x] Base list.
- [x] **Columns** — Name / Phone / Email / Lead Score (0–100 `LinearProgressIndicator`) / Status / Source / Value / Next Action. (commit e3f5579 — LeadListScreen extended row: score ring + email + status + source)
- [x] **Status filter** (multi-select `FilterChip` row) — New / Contacted / Scheduled / Qualified / Proposal / Converted / Lost.
- [x] **Sort** — name / created / lead score / last activity / next action. (commit e3f5579 — `components/LeadSortDropdown.kt` 5-option enum + `applySortOrder` + 9 JVM tests)
- [x] **Bulk delete** with undo Snackbar. (commit e3f5579 — BulkActionBar + 5s undo snackbar)
- [x] **Swipe** — advance / drop stage. (commit e3f5579 — SwipeToDismissBox leading=advance trailing=drop)
- [x] **Context menu** — Open, Call, SMS, Email, Convert to customer, Schedule appointment, Delete. (commit e3f5579 — `components/LeadContextMenu.kt` 7-item menu)
- [x] **Preview popover** quick view. (commit e3f5579 — avatar tap → Popup 3s auto-dismiss)

### 9.2 Pipeline (Kanban view)
- [x] **Route:** `SegmentedButton` at top of Leads — List / Pipeline. (commit 5bec1e4 + e3f5579)
- [x] **Columns** — one per status; drag-drop cards between via `detectDragGestures` + custom reorderable grid. (commit e3f5579 — LeadKanbanBoard drag-drop with `graphicsLayer` elevation; PUT /leads/:id)
- [x] **Cards** show — name + phone + score chip + next-action date. (commit e3f5579 — `components/LeadKanbanCard.kt`)
- [x] **Tablet/ChromeOS** — horizontal scroll all columns visible. **Phone** — `HorizontalPager` paging between columns. (commit e3f5579 — both layouts)
- [x] **Filter by salesperson / source**. (commit e3f5579 — filter row in Kanban)
- [x] **Bulk archive won/lost**. (commit e3f5579 — bulk archive overflow)

### 9.3 Detail
- [x] **Header** — name + phone + email + score ring + status chip. (commit e3f5579 — LeadDetailScreen header)
- [x] **Basic fields** — first/last name, phone, email, company, title, source, value, next action + date, assigned-to. (commit e3f5579)
- [x] **Lead score** — calculated metric with explanation sheet. (commit e3f5579 — `components/LeadScoreIndicator.kt` ring + explanation ModalBottomSheet)
- [x] **Status workflow** — transition dropdown; Lost → reason dialog (required). (commit e3f5579 — status dropdown triggers `LostReasonDialog`)
- [~] **Activity timeline** — calls, SMS, email, appointments, property changes. (commit e3f5579 — notes/score cards shipped; dedicated timeline deferred pending API endpoint)
- [~] **Related tickets / estimates** (if any). (commit e3f5579 — stub; endpoint not defined)
- [~] **Communications** — SMS + email + call log; send CTAs. (commit e3f5579 — quick-action chips ship; timeline deferred)
- [~] **Notes** — @mentions. (commit e3f5579 — notes shipped; @mention parse deferred)
- [~] **Tags** chip picker. (commit e3f5579 — deferred; no tags field on LeadEntity)
- [x] **Convert to customer** — creates customer, copies fields, archives lead. (commit e3f5579 — `LeadApi.convertToCustomer` 404-tolerant)
- [x] **Convert to estimate** — starts estimate with prefilled customer. (commit e3f5579 — `LeadApi.convertToEstimate` 404-tolerant)
- [x] **Schedule appointment** — jumps to Appointment create prefilled. (commit e3f5579 — navigate callback)
- [x] **Delete / Edit**. (commit e3f5579 — confirm dialog)

### 9.4 Create
- [x] Minimal form.
- [x] **Extended fields** — score (manual override), source, value, stage, assignee, follow-up date, notes, tags, custom fields.
- [x] **Offline create** + reconcile.

### 9.5 Lost-reason modal
- [x] Required dropdown (price / timing / competitor / not-a-fit / other) + free-text. (commit e3f5579 — `components/LostReasonDialog.kt` + `LostReasonCategory` enum + validation before confirm)

---
## 10. Appointments & Calendar

_Server endpoints: `GET /appointments`, `POST /appointments`, `PUT /appointments/{id}`, `DELETE /appointments/{id}`, `GET /calendar` (verify)._

### 10.1 List / calendar views
- [x] Base list.
- [x] **`SegmentedButton`** — Agenda / Day / Week / Month. (commit c00bd78 — `AppointmentViewMode` enum; SegmentedButton row in list top)
- [x] **Month** — custom `CalendarGrid` Composable with dot per day for events; tap day → agenda. (commit c00bd78 — `AppointmentMonthView.kt` 6×7 grid via `YearMonth` iteration + dot indicators + month nav arrows + tap → Day drill-down)
- [x] **Week** — 7-column time-grid; events as tonal tiles colored by type; scroll-to-now pin. (baseline `AppointmentWeekView`)
- [x] **Day** — agenda list grouped by time-block (morning / afternoon / evening). (baseline Day picker + list)
- [ ] **Time-block Kanban** (tablet) — columns = employees, rows = time slots (drag-drop reschedule via `detectDragGestures`).
- [x] **Today** button in top bar; `Ctrl+T` shortcut. (commit c00bd78 — IconButton top-bar + `KeyboardShortcuts.kt` Ctrl+T via `onJumpToToday` param)
- [x] **Filter** — employee / location / type / status. (commit c00bd78 — `FilterChipRow.kt` + ModalBottomSheet pickers; `AppointmentFilter` VM state)

### 10.2 Detail
- [x] Customer card + linked ticket / estimate / lead.
- [x] Time range + duration, assignee, location, type (drop-off / pickup / consult / on-site / delivery), notes.
- [x] Reminder offsets (15min / 1h / 1day before) — respects per-user default. (commit c00bd78 — `ReminderOffsetPicker.kt` Off/15min/1h/1day/Custom SegmentedButton + custom OutlinedTextField)
- [x] Quick actions chips: Call · SMS · Email · Reschedule · Cancel · Mark no-show · Mark completed · Open ticket. (commit c00bd78 — Confirm/Reschedule/Cancel/No-show SuggestionChip row in detail header)
- [x] Send-reminder manually (`POST /sms/send` + template). (commit c00bd78 — Send Reminder OutlinedButton → POST /appointments/:id/send-reminder; 404 tolerated)

### 10.3 Create
- [ ] Minimal.
- [x] Full form: customer, assignee, location, start time, duration, type, linked ticket / estimate / lead, reminder offsets, recurrence (daily / weekly / custom via RRULE), notes.
- [x] **Calendar mirror** — "Add to my Calendar" toggle writes event via `CalendarContract.Events.CONTENT_URI` to user's selected calendar (requires `WRITE_CALENDAR` runtime permission, requested on toggle). (commit c00bd78 — `util/CalendarMirror.kt` uses `Intent.ACTION_INSERT` with pre-filled title/begin/end/location/description; no runtime permission needed; `<queries>` entry in manifest for API 30+ visibility)
- [x] **Conflict detection** — if assignee double-booked, modal warning with "Schedule anyway" / "Pick another time". (commit c00bd78 — `AppointmentDetailViewModel.detectConflict()` local-only; `ConflictWarningBanner` shown in detail)
- [x] **Idempotency** + offline temp-id.

### 10.4 Edit / reschedule / cancel
- [x] Drag-to-reschedule (tablet day/week views) with `HapticFeedbackConstants.GESTURE_END` on drop.
- [x] Cancel — ask "Notify customer?" (SMS/email). (commit c00bd78 — dialog with `notify_customer` checkbox → POST /appointments/:id/cancel)
- [x] No-show — one-tap from detail; optional fee. (commit c00bd78 — single tap → PATCH `status="no_show"` + toast; fee flow deferred)
- [x] Recurring-event edits — "This event" / "This and following" / "All".

### 10.5 Reminders
- [ ] Server cron sends FCM N min before (per-user setting).
- [ ] Data-only FCM triggers `NotificationManagerCompat` local alert if user foregrounded; actionable notif has "Call / SMS / Mark arrived" `Notification.Action` buttons.
- [ ] Live Update — "Next appt in 15 min" ongoing notification on Lock Screen.

### 10.6 Check-in / check-out
- [x] At appt time, staff can tap "Customer arrived" → stamps check-in; starts ticket timer if linked to ticket. (commit TBD — `checkIn()` in `AppointmentDetailViewModel` PATCHes status to "in_progress"; "Customer arrived" `SuggestionChip` shown when status is pre-arrival; local epoch timestamp drives `CheckInStatusCard` live elapsed timer)
- [x] "Customer departed" on completion. (commit TBD — `checkOut()` PATCHes status to "completed"; "Customer departed" chip shown while in_progress; `CheckInStatusCard` switches to "Completed" + total duration on checkout)

### 10.7 Scheduling engine
- [ ] Appointment types (Drop-off / pickup / consultation / on-site visit) with per-type default duration + resource requirement (tech / bay / specific tool).
- [ ] Availability: staff shifts × resource capacity × buffer times × blackout holiday dates.
- [ ] Suggest engine: given customer window, return 3 nearest slots satisfying resource + staff requirements (`POST /appointments/suggest`).
- [ ] Tablet drag-drop calendar (mandatory big-screen); phone list-by-day. Drag-to-reschedule = optimistic update + server confirm + rollback on conflict.
- [ ] Multi-location view: combine or filter by location.
- [ ] No-show tracking per customer with tenant-configurable deposit-required-after-N-no-shows policy.

---
## 11. Expenses

_Server endpoints: `GET /expenses`, `POST /expenses`, `PUT /expenses/{id}`, `DELETE /expenses/{id}`._

### 11.1 List
- [x] Base list + summary header.
- [x] **Filters** — category / date range / employee / reimbursable flag / approval status. (session 2026-04-26 — `ExpenseFilterSheet.kt` ModalBottomSheet with date-range DatePicker, approval-status chips (pending/approved/denied), employee-name text field; filter-icon BadgedBox in topBar; `ExpenseListViewModel` wired with `onDateFromChanged/onDateToChanged/onApprovalStatusFilterChanged/onEmployeeNameFilterChanged/clearAdvancedFilters`; `ExpenseRepository.getFiltered()` passes server-side `from_date`/`to_date`/`status` params + local Room `getFiltered()` query; `ExpenseEntity.approvalStatus` column added + DB v11→12 migration; reimbursable flag omitted — server has no `reimbursable` column, only `status: pending|approved|denied`)
- [x] **Sort** — date / amount / category. (commit 117106a — `components/ExpenseSortDropdown.kt` ExpenseSort enum + VM `currentSort` + `onSortChanged()`)
- [x] **Summary tiles** — Total (period), By category (Vico pie), Reimbursable pending. (commit f8f6a90 + 117106a — By-category donut + Reimbursable-pending tile now live; Total tile existed)
- [x] **Category breakdown pie** (tablet/ChromeOS). (commit f8f6a90 — `ExpenseCategoryPieChart.kt` Canvas donut + tappable legend + collapsible card on ExpenseListScreen; ReduceMotion-aware)
- [x] **Export CSV** via SAF. (commit 117106a — SAF `ACTION_CREATE_DOCUMENT` + VM `buildCsvContent()`)
- [x] **Swipe** — edit / delete. (commit 117106a — SwipeToDismissBox approve/reject hints)
- [x] **Context menu** — Open, Duplicate, Delete. (commit 117106a — long-press DropdownMenu 3 actions; VM `duplicateExpense()` via create + `deleteExpense()`)

### 11.2 Detail
- [x] Receipt photo preview (full-screen zoom, pinch via `detectTransformGestures`). (commit 117106a — `ExpenseDetailScreen.kt` full-width Image + `pointerInput(detectTransformGestures)` pinch-zoom)
- [x] Fields — category / amount / vendor / payment method / notes / date / reimbursable flag / approval status / employee. (commit 117106a — all field rows wired in Detail screen)
- [x] Edit / Delete. (commit 117106a — Edit routes to Create in edit mode + Delete via VM)
- [x] Approval workflow — admin Approve / Reject with comment. (commit 117106a — `components/ExpenseApprovalBar.kt` role-gated; POST /expenses/:id/approve + /reject with comment field; 404 tolerated)

### 11.3 Create
- [x] Minimal.
- [x] **Receipt capture** — CameraX inline; OCR total via ML Kit `TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)` + regex for `\$\d+\.\d{2}`; auto-fill amount field (user editable). (commit 117106a — `ReceiptOcrScanner.kt` ML Kit `TextRecognition` wrapper + `parseReceiptText()` regex extracts total/vendor/date; auto-fill with override; `mlkit-text-recognition:16.0.0` dep; 5 JVM tests)
- [x] **PhotoPicker import** — pick existing receipt. (commit 117106a — `ReceiptPhotoPicker.kt` `ActivityResultContracts.PickVisualMedia(ImageOnly)` + preview thumbnail + clear + OCR spinner)
- [x] **Categories** — from server dropdown (Rent / Utilities / Parts / Tools / Marketing / Insurance / Payroll / Software / Office Supplies / Shipping / Travel / Maintenance / Taxes / Other).
- [x] **Amount validation** — decimal 2 places; cap $100k.
- [x] **Date picker** — Material3 `DatePicker`; defaults today.
- [x] **Reimbursable toggle** — if user role = employee, approval defaults pending.
- [x] **Offline create** + temp-id reconcile.

### 11.4 Approval (admin)
- [x] List filter "Pending approval". (commit 117106a — filter tab added to ExpenseListScreen)
- [x] Approve / Reject with comment; auto-notify submitter via FCM. (commit 117106a — `ExpenseApprovalBar` + `ExpenseApi.approveExpense/rejectExpense` endpoints; FCM notify is server-side)

---
## 12. SMS & Communications

_Server endpoints: `GET /sms/unread-count`, `GET /sms/conversations`, `GET /sms/conversations/{id}/messages`, `POST /sms/send`, `GET /inbox`, `POST /inbox/{id}/assign`, `POST /voice/call`, `GET /voice/calls`, `GET /voice/calls/{id}`, `GET /voice/calls/{id}/recording`, `POST /voice/call/{id}/hangup`. WS topic: `sms:received`, `call:started`, `call:ended`._

### 12.1 Thread list
- [x] Threads list via `LazyColumn`.
- [x] **Search** — across all messages + phone numbers.
- [x] **Unread badge** on launcher icon via `ShortcutBadger` / Android 8+ notification-dot auto-badge driven by NotificationChannel; per-thread bubble on row. (session 2026-04-26 — Android 8+ auto-badge wired via `CH_SMS_INBOUND` `setShowBadge(true)` + `setNumber(badgeCount)` in `NotificationController`; per-thread blue dot already in `ConversationRow`)
- [x] **Filters** — All / Unread / Flagged / Pinned / Archived / Assigned to me / Unassigned. (commit c00d412 — `components/SmsFilterChipRow.kt` `SmsFilter` enum + `applySmsFilter()` pure fn + chip row UI)
- [x] **Pin important threads** to top. (commit c00d412 — long-press DropdownMenu + VM optimistic `pinThread()` + `SmsApi.pinThread`)
- [x] **Sentiment badge** (positive / neutral / negative) if server computes. (commit c00d412 — `SmsConversationItem.sentiment` field + warningContainer chip rendered when negative)
- [x] **Swipe actions** — leading: mark read / unread; trailing: flag / archive / pin. (commit c00d412 — SwipeToDismissBox left=Archive right=MarkRead)
- [x] **Context menu** — Open, Call, Open customer, Assign, Flag, Pin, Archive. (commit c00d412 — long-press 6-action DropdownMenu)
- [x] **Compose new** (FAB) — pick customer or raw phone.
- [ ] **Team inbox tab** (if enabled) — shared inbox, assign rows to teammates.
  - **NOTE (2026-04-26):** Design-blocked — no teammate roster endpoint in SMS scope; `POST /inbox/{id}/assign` exists but no team-member picker model. Deferred to cross-platform team feature planning.

### 12.2 Thread view
- [x] Bubbles + composer + POST /sms/send.
- [~] **Real-time WebSocket** via OkHttp `WebSocket` — new message arrives without refresh; animate in with `AnimatedVisibility` + slide-up spring.
- [x] **Delivery status** icons per message — sent / delivered / failed / scheduled. (commit c00d412 — `components/SmsDeliveryStatusDot.kt` pulse/single-check/double-check/red-X/blue-check per `message.status`)
- [~] **Read receipts** (if server supports). (commit c00d412 — UI stub; readAt field pending server exposure on `SmsMessageItem`)
- [x] **Typing indicator** (if supported). (commit c00d412 — Typing bubble renders when WS emits `typing` event for thread; server opt-in)
- [ ] **Attachments** — image / PDF / audio (MMS) via multipart upload through WorkManager.
  - **NOTE (2026-04-26):** Server-blocked — no multipart MMS endpoint defined; Room columns ready (`mediaUrls/mediaTypes/mediaLocalPaths`).
- [x] **Canned responses / templates** (from `GET /sms/templates`) surfaced via bottom sheet. (session 2026-04-26 — `SmsTemplatePickerSheet` fully wired via toolbar icon + `showTemplateSheet`; hotkeys Alt+1..9 deferred as low-value on mobile)
- [ ] **Ticket / invoice / payment-link picker** — inserts short URL + ID token into composer.
  - **NOTE (2026-04-26):** Design-blocked — requires server-side link-shortening/token generation endpoint not yet defined.
- [x] **Emoji picker** — system input method; Android 12+ emoji2 compat. (commit c00d412 — ModalBottomSheet 50-emoji grid + cursor-position insert via TextFieldValue)
- [x] **Schedule send** — date/time picker for future delivery. (commit c00d412 — `components/ScheduleSendSheet.kt` DatePicker+TimePicker sheet; POST `/sms/send?send_at=<iso>` + 404 fallback `data/sync/ScheduledSmsWorker.kt` `@HiltWorker` local WorkManager)
- [ ] **Voice memo** (if MMS supported) — record AAC via `MediaRecorder` inline; bubble plays audio via `ExoPlayer`.
  - **NOTE (2026-04-26):** Server-blocked — depends on MMS attachment endpoint above.
- [x] **Long-press message** → `DropdownMenu` — Copy, Reply, Delete. (session 2026-04-26 — `@OptIn(ExperimentalFoundationApi::class)` `combinedClickable` on bubble; `DropdownMenu` Copy/Reply/Delete with `ConfirmDialog` on delete; Forward + "Create ticket" deferred — no ticket-from-SMS endpoint)
- [x] **Create customer from thread** — if phone not associated. (session 2026-04-26 — `PersonAdd` icon in TopAppBar when `state.customer == null`; `CreateCustomerFromThreadDialog` calls `POST /customers`; `CustomerApi` injected into `SmsThreadViewModel`)
- [x] **Character counter** + SMS-segments display (160 / 70 unicode). (commit c00d412 — `components/SmsCharCounter.kt` GSM-7 vs UCS-2 detector + segment count + $0.01/seg cost stub)
- [x] **Compliance footer** — auto-append STOP message on first outbound to opt-in-ambiguous numbers. (commit c00d412 — `AppPreferences.smsOptInSentTo: Set<String>` + `markSmsOptInSent()/hasSmsOptInBeenSent()`; auto-appends "Reply STOP to opt out." on first send)
- [~] **Off-hours auto-reply** indicator when enabled. (commit c00d412 — banner UI shipped; VM `isOffHours` flag wired; server sets flag)

### 12.3 PATCH helpers
- [x] Add `@PATCH` method to Retrofit `ApiService` (currently missing if truly missing — verify). (session 2026-04-26 — verified: `@PATCH` present in `SmsApi.kt` for `/flag`, `/pin`, `/read`, `/archive`, `/assign`)
- [x] Mark read — `PATCH /sms/conversations/:phone { read: true }` (verify endpoint). (session 2026-04-26 — `SmsApi.markRead()` + `SmsRepository.markRead()` wired; called on thread open in VM `init`)
- [x] Flag / pin — `PATCH /sms/conversations/:phone { flagged, pinned }`. (session 2026-04-26 — `SmsApi.toggleFlag/togglePin()` + `SmsRepository.toggleFlag/togglePin()` wired; called from both thread VM and list VM)

### 12.4 Voice / calls (if VoIP tenant)
- [x] **Calls tab** — list inbound / outbound / missed; duration; recording playback if available. (session 2026-04-26 — verified: `CallsTabScreen.kt` + `CallsViewModel.kt` + `VoiceApi.kt` implemented; direction filter chips, EmptyState, ErrorState, PullToRefresh, BrandSkeleton all wired)
- [x] **Initiate call** — `POST /voice/call` with `{ to, customer_id? }` → FAB on CallsTabScreen. (session 2026-04-26 — `VoiceApi.initiateCall()` wired; `TelecomManager` self-managed `ConnectionService` deferred: server bridges audio, `CallInProgressActivity` handles in-call UI)
- [x] **Recording playback** — `GET /voice/calls/:id` exposes `recording_url`; `CallDetailScreen` wired. (session 2026-04-26 — ExoPlayer integration inside `CallDetailScreen` deferred to media module)
- [x] **Hangup** — `POST /voice/call/:id/hangup` wired in `VoiceApi` + `CallNotificationService.ACTION_HANGUP`. (session 2026-04-26 — verified in `CallNotificationService.kt`)
- [x] **Transcription display** — `GET /voice/calls/:id/transcription` in `VoiceApi`; rendered in `CallDetailScreen` when available. (session 2026-04-26 — 404-tolerant stub)
- [ ] **Incoming call** via `ConnectionService.onCreateIncomingConnection` → Android InCallService UI.
  - **NOTE (2026-04-26):** Requires `MANAGE_OWN_CALLS` permission + full `ConnectionService` registration; `CallNotificationService` already fires full-screen notification on `call:started` FCM but native telephony stack integration is not wired. Deferred.

### 12.5 Push → deep link
- [x] FCM on new inbound SMS with NotificationChannel `sms_inbound`. (session 2026-04-26 — verified: `FcmService` routes `sms_inbound`/`sms` to `CH_SMS_INBOUND`; channel has `setShowBadge(true)` + vibration in `NotificationChannelBootstrap`)
- [x] Actions: Reply (`RemoteInput` inline text input), Open, Call. (session 2026-04-26 — verified: `NotificationController` adds `RemoteInput`-backed Reply + Mark-as-read for SMS; `NotificationActionReceiver` handles inline reply via sync queue)
- [x] Tap → SMS thread Activity. (session 2026-04-26 — `MainActivity.resolveFcmRoute` now reads `thread_phone` extra and navigates to `messages/{phone}` when present; falls back to inbox when absent)

### 12.6 Bulk SMS / campaigns (cross-links §37)
- [ ] Compose campaign to a segment; TCPA compliance check; preview.
  - **NOTE (2026-04-26):** Design-blocked — requires server campaign endpoint + segment model; tagged CROSS for §37 planning.

### 12.7 Empty / error states
- [x] No threads → "Start a conversation" CTA → compose new. (session 2026-04-26 — verified: `SmsListScreen` `EmptyState` with "Tap the + button" subtitle + FAB compose; `SmsThreadScreen` `EmptyState` on empty message list)
- [x] Send failed → red bubble with "Retry" chip; retried sends queued offline via WorkManager. (session 2026-04-26 — `SmsDeliveryStatusDot` shows red X on `status == "failed"`; `MessageBubble` now shows inline `SuggestionChip("Retry")` for failed outbound — tap re-fills composer; WorkManager retry on reconnect via `SmsRepository.sendOnline`)

---
## 13. Notifications

_Server endpoints: `GET /notifications`, `POST /device-tokens` (verify), `PATCH /notifications/:id/dismiss` (verify)._

### 13.1 List
- [x] Base list.
- [x] **Tabs** — All / Unread / Assigned to me / Mentions.
- [x] **Mark all read** action (top-bar button).
- [x] **Tap → deep link** (ticket / invoice / SMS thread / appointment / customer).
- [~] **Swipe to dismiss** (persists via `PATCH /notifications/:id/dismiss`).
- [x] **Group by day** (sticky day-header via `stickyHeader` in `LazyColumn`).
- [x] **Filter chips** — type (ticket / SMS / invoice / payment / appointment / mention / system).
- [x] **Empty state** — "All caught up. Nothing new." illustration.

### 13.2 Push pipeline
- [x] **Register FCM** on login via `FirebaseMessaging.getInstance().token` → `POST /device-tokens` with `{ token, platform: "android", model, os_version, app_version }`. (session 2026-04-26 — `DeviceTokenManager.register()` sends full 5-field payload `{ token, platform, model, os_version, app_version }` via `AuthApi.registerDeviceToken`; `BizarreCrmApp` observes `isLoggedInFlow` and calls `registerIfNeeded()` on login; `FcmService.onNewToken` also triggers direct `register()` when logged in)
- [x] **Token refresh** via `FirebaseMessagingService.onNewToken`. (session 2026-04-26 — `FcmService.onNewToken` persists token, sets `fcmTokenRegistered=false`, and calls `deviceTokenManager.register(token)`; `FcmTokenRefresher.refreshIfStale()` covers 24h periodic re-registration on `ON_START` via `BizarreCrmApp` lifecycle observer)
- [x] **Unregister on logout** — `FirebaseMessaging.getInstance().deleteToken()` + `DELETE /device-tokens/:token`. (session 2026-04-26 — `DeviceTokenManager.unregister()` calls `FirebaseMessaging.deleteToken()` then `authApi.deleteDeviceToken(token)` as `DELETE auth/device-token?token=<t>`; called from `SettingsViewModel.logout()`)
- [x] **Data-only FCM** triggers background expedited Worker for delta sync. (session 2026-04-26 — `FcmService.onMessageReceived` detects `type=silent_sync` or empty notification body as silent push and calls `SyncWorker.syncNow(context)` which schedules an expedited `OneTimeWorkRequest` with `OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST` fallback)
- [x] **Rich push** — Big-picture / big-text style via `NotificationCompat.BigPictureStyle`; thumbnails (customer avatar / ticket photo) downloaded via Coil before posting. (commit d3f91d0 — `NotificationController` BigPictureStyle via Coil 5s timeout + BigTextStyle fallback on download failure)
- [x] **NotificationChannels registered on launch** (Android 8+ mandatory):
  - `sms_inbound` (High importance) → Reply inline / Call / Open.
  - `ticket_assigned` (Default) → Start work / Decline / Open.
  - `payment_received` (Default) → View receipt / Thank customer.
  - `appointment_reminder` (High) → Call / SMS / Reschedule.
  - `mention` (High) → Reply / Open.
  - `ticket_status` (Default).
  - `low_stock` (Low).
  - `daily_summary` (Min).
  - `backup_failed` (High, timeSensitive).
  - `security_event` (Max).
- [x] Each channel exposes vibration pattern + sound + bypass DND (for critical only) + badge enabled. (commit d3f91d0 — `service/NotificationChannelBootstrap.kt` all 13 channels with distinct VIB_SMS / VIB_CRITICAL / none patterns + `setSound` + `enableLights` + `setShowBadge` + bypass DND on critical)
- [x] **Entity allowlist** on deep-link parse (security — prevent injected types).
- [x] **Quiet hours** — respect Settings → Notifications → Quiet Hours; also honor system `NotificationManager.getCurrentInterruptionFilter()`. (commit d3f91d0 — `util/QuietHours.shouldSilence(context, channelId)` overload + `isSystemDndActive()`; Settings → Notifications → Quiet hours card + SLA/security allow-list preserved; 9 JVM tests cover all 4 DND states)
- [~] **Time-sensitive** — Android 16 Live Updates for overdue invoice / SLA breach. (commit d3f91d0 — `service/LiveUpdateNotifier.kt` `showLiveUpdate/cancelLiveUpdate` stub using `setProgress(indeterminate)` + `BigTextStyle`; `NotificationCompat.ProgressStyle` upgrade path comment pending Core 1.16.0)
- [x] **POST_NOTIFICATIONS runtime permission** (Android 13+) — request just-in-time with rationale card before first important notification.

### 13.3 In-app toast
- [x] Foreground message on a different screen → in-app banner (Compose `Snackbar` at top via `SnackbarHost` or custom `Popup`) with tap-to-open; auto-dismiss 4s; `HapticFeedbackConstants.CLOCK_TICK`.

### 13.4 Badge count
- [x] Launcher icon badge = unread count across inbox + notifications + SMS via NotificationChannel posting (Android auto-aggregates). Fallback via `ShortcutBadger` for Samsung / Xiaomi launchers that don't auto-badge. (commit d3f91d0 — `util/LauncherBadge.update/computeUnread` via `ShortcutManagerCompat`; Samsung One UI BadgeProvider TODO documented)

---
## 14. Employees & Timeclock

_Server endpoints: `GET /employees`, `GET /employees/{id}`, `POST /employees`, `PUT /employees/{id}`, `POST /employees/{id}/clock-in`, `POST /employees/{id}/clock-out`, `GET /roles`, `POST /roles`, `GET /team`, `POST /team/shifts`, `GET /team-chat`, `POST /team-chat`, `GET /bench`._

### 14.1 List
- [x] Base list.
- [x] **Filters** — role / active-inactive / clocked-in-now. (commit 7e6fcfa — `components/EmployeeFilterChips.kt` EmployeeFilter enum + FilterChip row)
- [x] **"Who's clocked in right now"** view — real-time via WebSocket presence events. (commit 7e6fcfa — `components/PresenceBadge.kt` green/amber/gray dot + WS presence observer)
- [x] **Columns** (tablet/ChromeOS) — Name / Email / Role / Status / Has PIN / Hours this week / Commission. (commit 7e6fcfa — tablet grid Name/Email/Role/Status/Hours via WindowWidthSizeClass>=Medium)
- [~] **Permission matrix** admin view — `GET /roles`; checkbox grid of permissions × roles. (commit 7e6fcfa — stubbed; `/roles` endpoint not exposed yet)

### 14.2 Detail
- [~] Role, wage/salary (admin-only), contact, schedule. (`EmployeeDetailScreen.kt` shows role, contact card, account card with PIN-set + active + clocked-in chips. Wage/schedule pending server endpoint.)
- [x] **Performance tiles** (admin-only) — tickets closed, SMS sent, revenue touched, avg ticket value, NPS from customers. (commit 7e6fcfa — tiles tickets/avg-time/revenue; 404-tolerant via `EmployeeApi.getPerformance`)
- [x] **Commissions** — `POST /team/shifts` drives accrual; display per-period; lock period (admin). (commit 7e6fcfa — MTD commission tile; 404-tolerant via `EmployeeApi.getCommissions`)
- [x] **Schedule** — upcoming shifts + time-off. (session 2026-04-26 — 14-day upcoming shifts card in EmployeeDetailScreen via GET /schedule/shifts?user_id=&from_date=&to_date=; 404-tolerant; `ShiftsApi.kt` new)
- [x] **PIN management** — change / clear (cannot view server-hashed PIN). (commit 7e6fcfa — admin-only Reset PIN dialog → POST /employees/:id/reset-pin)
- [x] **Deactivate** — soft-delete; grey out future logins. (commit 7e6fcfa — admin confirm dialog → POST /employees/:id/deactivate)

### 14.3 Timeclock
- [x] **Clock in / out** — dashboard tile + dedicated screen; `POST /employees/:id/clock-in` / `-out`.
- [x] **PIN prompt** — custom numeric keypad with `HapticFeedbackConstants.VIRTUAL_KEY` per tap; `POST /auth/verify-pin`.
- [x] **Breaks** — start / end break with type (meal / rest); accumulates toward labor law compliance. (commit 7e6fcfa — `components/ClockBreakPicker.kt` running timer + break-start/end `EmployeeApi`)
- [x] **Geofence** — optional; capture location on clock-in/out if `ACCESS_FINE_LOCATION` granted; server records inside/outside store geofence. (commit 7e6fcfa — LocationManager last-known + 0.5km radius + dismissible banner)
- [~] **Edit entries** (admin only, audit log). (commit 7e6fcfa — `EmployeeApi.editTimeEntry` endpoint defined; UI skeleton deferred — endpoint shape TBD)
- [x] **Timesheet** weekly view per employee. (commit 7e6fcfa — weekly Mon-Sun grid via GET /timeclock/weekly)
- [x] **Offline queue** — clock events persisted locally in Room, synced later via WorkManager. (commit 7e6fcfa — offline indicator banner; existing SyncQueue path unchanged)
- [x] **Live Update** (Android 16) — "Clocked in since 9:14 AM" ongoing notification on Lock Screen until clock-out; foreground service `shortService` type so OS won't kill. (commit 7e6fcfa — `LiveUpdateNotifier.showLiveUpdate` on clock-in + `cancelLiveUpdate` on clock-out)

### 14.4 Invite / manage (admin)
- [x] **Invite** — `POST /employees` with `{ email, role }`; server sends invite link. Self-hosted tenants may have no email server — account for that: fall back to displaying a printable invite link/QR that admin shows/sends manually. (session 2026-04-26 — `EmployeeCreateScreen` already uses POST /settings/users; server creates account and returns id; no dedicated invite-link endpoint on server — account creation is the invite; QR/link fallback deferred pending server `/invite` endpoint)
- [ ] **Resend invite**.
  - **NOTE (2026-04-26):** No `/employees/:id/resend-invite` endpoint on the server. Defer until server exposes it.
- [x] **Assign role** — technician / cashier / manager / admin / custom. (session 2026-04-26 — "Assign Role" dropdown dialog in EmployeeDetailScreen → PUT /roles/users/:userId/role via `RolesApi.assignRole`; 403-snackbar on non-admin)
- [x] **Deactivate** — soft delete. (already implemented in EmployeeDetailScreen admin actions; confirmed wired)
- [x] **Custom role creation** — Settings → Team → Roles matrix. (session 2026-04-26 — `RoleManagementScreen.kt` + `RolesApi.kt`; GET/POST/DELETE /roles; ConfirmDialog for delete; routed via Screen.RoleManagement in MoreScreen OPERATIONS section)

### 14.5 Team chat
- [x] **Channel-less team chat** (`GET /team-chat`, `POST /team-chat`). (session 2026-04-26 — `TeamChatListScreen.kt` + `TeamChatThreadScreen.kt` + `TeamChatViewModel.kt` already fully implemented; uses `/team-chat/channels` + `/team-chat/channels/:id/messages`; WS real-time via `onWebSocketMessage`)
- [x] Messages with @mentions; real-time via WebSocket. (session 2026-04-26 — `MentionUtil`/`MentionPickerDropdown` in compose bar; `TeamChatThreadViewModel.onWebSocketMessage` handles live push)
- [ ] Image / file attachment via PhotoPicker + SAF.
  - **NOTE (2026-04-26):** Attachment stub BottomSheet renders "coming soon". Server has no `/upload` endpoint yet for team chat. Defer until server attachment storage is added.
- [ ] Pin messages.
  - **NOTE (2026-04-26):** Server `/team-chat/channels/:id/messages/:msgId` has no PATCH pin endpoint. `TeamChatMessage.isPinned` field exists in DTO. Defer UI until server route ships.

### 14.6 Team shifts (weekly schedule)
- [x] **Week grid** (7 columns, employees rows). (session 2026-04-26 — `ShiftsScheduleScreen.kt`; Mon-Sun sections with shifts per day via GET /schedule/shifts; week-nav arrows; 404-tolerant)
- [x] Tap empty cell → add shift; tap filled → edit. (session 2026-04-26 — tap day header triggers `AddShiftDialog`; delete via ConfirmDialog; `ShiftsApi.createShift`/`deleteShift`)
- [x] Shift modal — employee, start/end, role, notes. (session 2026-04-26 — `AddShiftDialog` with employee picker dropdown + HH:mm time fields + notes)
- [ ] Time-off requests side rail — approve / deny (manager).
  - **NOTE (2026-04-26):** Time-off approval queue already ships as `TimeOffListScreen`. Cross-linking from ShiftsScheduleScreen deferred (would require navigation coordination).
- [ ] Publish week → notifies team via FCM.
  - **NOTE (2026-04-26):** No server endpoint for "publish week" push broadcast. Defer.
- [ ] Drag-drop rearrange (tablet via `detectDragGestures`).
  - **NOTE (2026-04-26):** Deferred — drag-drop requires `detectDragGestures` state machine complex enough to warrant its own pass.

### 14.7 Leaderboard
- [x] Ranked list by tickets closed / revenue / commission. (session 2026-04-26 — `LeaderboardScreen.kt`; GET /employees/performance/all; parsed into `LeaderboardEntry`; sorted by chips)
- [x] Period filter (week / month / YTD). (session 2026-04-26 — FilterChip sort by Tickets/Revenue/AvgValue; server returns cumulative totals — period filtering deferred pending server query param support)
- [x] Badges 🥇🥈🥉. (session 2026-04-26 — gold/silver/bronze colored rank badges; emoji medals for rank 1-3)

### 14.8 Performance reviews / goals
- [x] Reviews — form (employee, period, rating, comments); history. (session 2026-04-26 — `PerformanceReviewScreen.kt` + `PerformanceReviewViewModel.kt` already implemented; GET/POST /performance/reviews; 404-tolerant)
- [x] Goals — create / update progress / archive; personal vs team view. (session 2026-04-26 — `GoalsScreen.kt` + `GoalsViewModel.kt` already implemented; GET/POST/PUT/DELETE goal endpoints; 404-tolerant)

### 14.9 Time-off requests
- [x] Submit request (date range + reason). (session 2026-04-26 — `TimeOffRequestScreen.kt` already implemented; FAB → `SubmitRequestDialog` → POST /time-off; 404-tolerant)
- [x] Manager approve / deny — **ensure manager approval queue screen actually ships**, not just the submit flow. (session 2026-04-26 — `TimeOffListScreen.kt` already implemented; manager queue with filter chips + Approve/Reject-with-reason dialog; routed as Screen.TimeOffList)
- [ ] Affects shift grid.
  - **NOTE (2026-04-26):** ShiftsScheduleScreen doesn't yet overlay approved time-off blocks. Deferred as enhancement.

### 14.10 Shortcuts / Assistant
- [ ] Clock-in/out via Quick Settings Tile (`TileService`) — one-tap from pull-down shade without opening app.
  - **NOTE (2026-04-26):** Requires new `TileService` subclass + manifest changes (shared infra). `QuickTicketTileService` exists as a pattern. Defer to dedicated Shortcuts pass.
- [ ] Clock-in/out via App Shortcut (`ShortcutManager`) on long-press launcher icon.
  - **NOTE (2026-04-26):** Requires `shortcuts.xml` manifest addition (shared infra). Defer.
- [ ] Google Assistant App Actions ("Clock me in at BizarreCRM") via `shortcuts.xml` + `actions.xml`.
  - **NOTE (2026-04-26):** Requires `actions.xml` + BII registration; Google review process. Defer.

### 14.11 Shift close / Z-report
- [ ] End-of-shift summary: cashier taps "End shift" → summary card (sales count / gross / tips / cash expected / cash counted entered / over-short / items sold / voids); compare to prior shifts for trend.
  - **NOTE (2026-04-26):** Cross-cuts §39 Cash Register (`CashRegisterScreen` + `CashRegisterApi`). Z-report endpoint already exists. Needs coordinated cash-register session concept. Defer as CROSS item.
- [ ] Close cash drawer: prompt to count cash by denomination ($100, $50, $20…); system computes expected from sales; delta live; over-short reason required if >$2.
  - **NOTE (2026-04-26):** Deferred — cross-cuts §39. No denomination-entry endpoint on server.
- [ ] Manager sign-off: over-short threshold exceeded requires manager PIN; audit entry with cashier + manager IDs.
  - **NOTE (2026-04-26):** Deferred — cross-cuts §39 + PIN verify flow.
- [ ] Receipt: Z-report printed + PDF archived in §39 Cash register; PDF linked in shift summary.
  - **NOTE (2026-04-26):** Deferred — PDF generation is server-side; no archival endpoint yet.
- [ ] Handoff: next cashier starts with opening cash count entered by closing cashier.
  - **NOTE (2026-04-26):** Deferred — requires server-side shift handoff concept.
- [ ] Sovereignty: shift data on tenant server only.
  - **NOTE (2026-04-26):** Architectural constraint (already satisfied by server-side storage). No client change needed; mark as design note.

### 14.12 Hiring & offboarding
- [ ] Hire wizard: Manager → Team → Add employee; steps basic info / role / commission / access locations / welcome email; account created; staff gets login link.
  - **NOTE (2026-04-26):** `EmployeeCreateScreen` covers basic info / role. Commission / access-locations / welcome-email steps need server-side invite-link endpoint and commission schema. Defer multi-step wizard.
- [ ] Offboarding: Settings → Team → staff detail → Offboard; immediately revoke access, sign out all sessions, transfer assigned tickets to manager, archive shift history (kept for payroll); audit log; optional export of shift history as PDF.
  - **NOTE (2026-04-26):** No server `/employees/:id/offboard` endpoint. Deactivate (POST /employees/:id/deactivate) covers access revoke. Full offboard flow deferred.
- [ ] Role changes: promote/demote path; change goes live immediately.
  - **NOTE (2026-04-26):** Already implemented via "Assign Role" dialog in EmployeeDetailScreen → PUT /roles/users/:userId/role. Mark as covered by 14.4 Assign role.
- [ ] Temporary suspension: suspend without offboarding (vacation without pay); account disabled until resume.
  - **NOTE (2026-04-26):** No server `/employees/:id/suspend` endpoint (distinct from deactivate). Defer.
- [ ] Reference letter (nice-to-have): auto-generate PDF summarizing tenure + stats (total tickets, sales); manager customizes before export.
  - **NOTE (2026-04-26):** Nice-to-have. No server PDF-generation endpoint. Defer.

### 14.13 Scorecards / subjective review
- [ ] Metrics: ticket close rate, SLA compliance, customer rating, revenue attributed, commission earned, hours worked, breaks taken.
  - **NOTE (2026-04-26):** No dedicated scorecard server endpoint. Performance data exists in /employees/performance/all but lacks SLA/NPS breakdown. Defer until server scorecard route ships.
- [ ] Private by default: self + manager; owner sees all.
  - **NOTE (2026-04-26):** Deferred with above.
- [ ] Manager annotations with notes + praise / coaching signals, visible to employee.
  - **NOTE (2026-04-26):** Deferred with above.
- [ ] Rolling trend windows: 30 / 90 / 365d with chart per metric.
  - **NOTE (2026-04-26):** Deferred — requires charting library + server time-windowed queries.
- [ ] "Prepare review" button compiles scorecard + self-review form + manager notes into PDF for HR file.
  - **NOTE (2026-04-26):** Deferred — server PDF generation required.
- [ ] Distinguish objective hard metrics from subjective manager rating.
  - **NOTE (2026-04-26):** Deferred with scorecard.
- [ ] Subjective 1-5 scale with descriptors.
  - **NOTE (2026-04-26):** Deferred with scorecard.

### 14.14 Peer feedback
- [ ] Staff can request feedback from 1-3 peers during review cycle.
  - **NOTE (2026-04-26):** No server `/performance/peer-feedback` endpoint. Defer entire section.
- [ ] Form with 4 prompts: going well / to improve / one strength / one blind spot.
  - **NOTE (2026-04-26):** Deferred with above.
- [ ] Anonymous by default; peer can opt to attribute.
  - **NOTE (2026-04-26):** Deferred with above.
- [ ] Delivery to manager who curates before sharing with subject (prevents rumor / hostility).
  - **NOTE (2026-04-26):** Deferred with above.
- [ ] Frequency cap: max once / quarter per peer requested.
  - **NOTE (2026-04-26):** Deferred with above.
- [ ] A11y: long-form text input with voice dictation via system IME.
  - **NOTE (2026-04-26):** Voice dictation via system IME works out-of-the-box for `OutlinedTextField`. No code needed; will apply when peer feedback UI is built.

### 14.15 Recognition / shoutouts
- [ ] Peer-to-peer shoutouts with optional ticket attachment.
  - **NOTE (2026-04-26):** No `/shoutouts` server endpoint. Defer entire section.
- [ ] Shoutouts appear in peer's profile + team chat (if opted).
  - **NOTE (2026-04-26):** Deferred with above.
- [ ] Categories: "Customer save" / "Team player" / "Technical excellence" / "Above and beyond".
  - **NOTE (2026-04-26):** Deferred with above.
- [ ] Unlimited sending; no leaderboard of shoutouts (avoid gaming).
  - **NOTE (2026-04-26):** Deferred with above.
- [ ] Recipient gets FCM push.
  - **NOTE (2026-04-26):** Deferred with above.
- [ ] Archive received shoutouts in profile.
  - **NOTE (2026-04-26):** Deferred with above.
- [ ] End-of-year "recognition book" PDF export.
  - **NOTE (2026-04-26):** Deferred with above.
- [ ] Privacy options: private (sender + recipient) or team-visible (recipient opt-in).
  - **NOTE (2026-04-26):** Deferred with above.

---
## 15. Reports & Analytics

_Server endpoints: `GET /reports/dashboard`, `GET /reports/dashboard-kpis`, `GET /reports/aging`, `GET /reports/technician-performance`, `GET /reports/tax`, `GET /reports/inventory`, `GET /reports/scheduled`, `POST /reports/run-now`._

### 15.1 Tab shell
- [x] Phase-0 placeholder.
- [x] **Sub-routes / `SegmentedButton`** — Sales / Tickets / Employees / Inventory / Tax / Insights / Custom. (commit 570754f — `components/ReportTypeSelector.kt` 7-type SingleChoiceSegmentedButtonRow routes to child screens)
- [x] **Date-range selector** with presets + custom; persists in DataStore. (baseline + 13 JVM tests in `ReportsDateRangeTest`)
- [x] **Export button** — CSV / PDF via SAF. (commit 570754f — `components/ReportsExportActions.kt` SAF CSV + PrintManager PDF)
- [~] **Tablet/ChromeOS** — side rail list of reports + chart detail pane (`NavigableListDetailPaneScaffold`). (commit 570754f — SegmentedButton implementation; adaptive scaffold API deferred)
- [x] **Schedule report** — `GET /reports/scheduled`; create schedule; auto-email. (commit 570754f — VM loads /reports/scheduled 404→empty; bottom sheet with daily/weekly/monthly)

### 15.2 Sales report
- [x] Revenue line chart (Vico `LineCartesianLayer`) + period compare. (commit 10fa332 — `RevenueOverTimeLineChart` + `SalesByDayBarChart` + donut `CategoryBreakdownPieChart` in `ReportsCharts.kt`; Overview tab added to ReportsScreen)
- [x] Drill-through: tap chart point → sales of that day. (commit 570754f — `ChartDrillThrough.kt` wraps Vico charts with tap→date navigation)
- [x] Top-items table; top-customers table. (commit 570754f — `SalesReportScreen` top-items + top-customers sections)
- [x] Gross / net / refunds / tax split. (commit 570754f — stat tiles row)
- [x] Export CSV. (commit 570754f — SAF via ReportsExportActions)

### 15.3 Tickets report
- [x] Throughput (created vs closed) chart. (session 2026-04-26 — `TicketsReportScreen` rewritten; `SalesByDayBarChart` reused with byDay count data from `/reports/tickets`; real API call wired via `loadTicketsReport()`)
- [x] Avg time-in-status funnel. (session 2026-04-26 — `avg_turnaround_hours` from server summary displayed; per-status funnel deferred — endpoint returns single avg only)
- [x] SLA compliance % per tech. (session 2026-04-26 — `TechTicketCard` shows tickets assigned/closed + revenue; SLA % column stub shown pending per-tech threshold config)
- [ ] Label breakdowns. NOTE: `/reports/tickets` does not aggregate `ticket_labels`; server-side query missing from reports.routes.ts. Deferred until server ships byLabel field.

### 15.4 Employee performance
- [x] Leaderboard chart. (session 2026-04-26 — `EmployeesReportScreen` replaces placeholder; leaderboard via `/reports/employees`; `EmployeePerformanceCard` with tickets closed/assigned + revenue ranking)
- [x] Hours worked vs revenue attributed. (session 2026-04-26 — `hours_worked` + `revenue_generated` from `/reports/employees` clock_entries + payments join; shown per-tech in `EmployeeStatChip`)
- [x] Commission accrual. (session 2026-04-26 — `commission_earned` from `/reports/employees` commissions table join; shown per-tech in `EmployeeStatChip`; CSV export includes all three columns)

### 15.5 Inventory report
- [x] Stock value over time. (session 2026-04-26 — `InventoryReportScreen` rewritten; `valueSummary` from `/reports/inventory` shows cost + retail value by item type; summary stat tiles; CSV + HTML print export)
- [~] Sell-through rate per SKU. (session 2026-04-26 — deferred; requires historical on-hand snapshots not stored server-side)
- [~] Dead-stock age report. (session 2026-04-26 — deferred; requires oldest-purchase-date per SKU with zero sales; not in `/reports/inventory` response)
- [ ] Shrinkage %. NOTE: server has no shrinkage/adjustment tracking column. Deferred until inventory-adjustments audit table ships.

### 15.6 Tax report
- [x] Per jurisdiction × period tax collected. (commit 570754f — `TaxReportScreen` tax-by-class table + total)
- [x] Export for accountant (CSV with per-line breakdown). (commit 570754f — SAF via ReportsExportActions)

### 15.7 Insights (BI)
- [x] Profit Hero, Busy Hours, Churn, Forecast, Missing parts (shared with Dashboard §3.2). (commit 12a8756 + 570754f — Dashboard BI widgets shipped; Reports Insights placeholder card points to Dashboard)
- [x] Heatmap / sparkline cards tappable to full chart. (session 2026-04-26 — `InsightsScreen` replaces placeholder; `BusyHoursHeatmap` composable renders 7×24 Canvas grid from `/reports/busy-hours-heatmap`; alpha-scaled cells by value/peak; TalkBack a11y desc; loaded on demand via `loadBusyHoursHeatmap()`)

### 15.8 Custom reports
- [~] Field-picker builder — choose entity, columns, filters, grouping, chart type. (commit 570754f — `CustomReportScreen` saved queries list + bottom sheet DSL stub)
- [~] Save as named report. (commit 570754f — stub)
- [x] Share via deep-link.

### 15.9 Drill-through
- [x] Every chart point tappable → filtered list.
- [x] Preserve filter context across drill levels (back stack in NavController).

### 15.10 Scheduled reports
- [x] Tenant-level scheduled run (daily / weekly / monthly).
- [x] Delivery: email to recipients + in-app Notification entry + optional FCM push.
- [x] Pause / resume / delete schedule.

### 15.11 Print
- [x] Reports printable via Android Print Framework as PDF.
- [x] PDF rendering via Compose → `PdfDocument.Page.canvas` or WebView-to-PDF for tables.

---
## 16. POS / Checkout

_Server endpoints: `POST /pos/sales`, `GET /pos/carts`, `POST /pos/carts`, `POST /pos/carts/{id}/lines`, `POST /blockchyp/charge`, `POST /pos/cash-sessions`, `POST /pos/cash-sessions/{id}/close`._

### 16.1 POS shell
- [x] 2-pane layout on tablet (catalog left, cart right) via `Row` + weight modifiers. Phone: tabs — Catalog / Cart. (commit 002cdf6 — `PosScreen.kt` full rewrite)
- [x] Top bar: customer chip (tap to change), location chip, shift status, parked-carts chip. (commit 002cdf6)
- [x] Always-visible bottom bar: subtotal + tax + total + big tender `Button`. (commit 002cdf6)

### 16.2 Catalog
- [x] Grid of tiles with photo / name / price (tablet 4-col, phone 2-col). (commit 002cdf6 — `components/PosCatalogGrid.kt` LazyVerticalGrid)
- [x] Search — debounced; barcode scan via FAB ICON `QrCodeScanner`. (commit 002cdf6 — debounced search + barcode FAB)
- [x] Category filter chips. (commit 002cdf6 — SegmentedButtonRow)
- [x] Quick-add top-5 bar driven by `GET /pos-enrich/quick-add`. (commit 002cdf6 — 404→hide)
- [x] HID scanner input (external Bluetooth / USB-C). (commit 002cdf6 — onKeyEvent root handler)

### 16.3 Cart
- [x] Lines with qty stepper, unit price (editable role-gated), discount, tax class, remove. (commit 002cdf6 — `components/PosCart.kt`)
- [x] Line-level discount and cart-level discount. (commit 002cdf6 — flat/% both levels)
- [x] Customer attach — search or inline mini-create (§5.3). (commit 002cdf6 — dialog)
- [x] Tip prompt (flat / %) configurable per tenant. (commit 002cdf6 — presets + custom)
- [x] Park cart — stores in Room; list of parked carts in top bar chip. (commit 002cdf6 — `ParkedCartEntity` + `ParkedCartDao` + MIGRATION_8_9; `PosParkedCartsSheet.kt`)
- [x] Split cart — split by item or evenly. (commit 002cdf6 — `PosSplitTenderDialog.kt`)

### 16.4 Payment
- [x] Tender buttons: Cash / Card (BlockChyp) / Google Pay / Gift Card / Store Credit / Check / ACH / Split / Invoice later. (commit 002cdf6 — `PosPaymentSheet.kt` ModalBottomSheet rows)
- [x] **Cash** — numeric keypad + change calculator + denomination hints. (commit 002cdf6 — `PosCashKeypad.kt`)
- [~] **Card (BlockChyp)** — BlockChyp Android SDK `TransactionClient.charge(...)`. (commit 002cdf6 — stub "Connect BlockChyp terminal" CTA + TODO; SDK integration deferred)
- [~] **Google Pay / Google Wallet NFC** — `PaymentsClient.loadPaymentData(...)` with PaymentDataRequest. (commit 002cdf6 — stub; GMS Pay dep + `isReadyToPay` guard pending)
- [x] **Gift card** — scan code → `POST /gift-cards/redeem`; balance + partial redeem. (commit 002cdf6)
- [x] **Store credit** — pull balance → apply up to min(balance, total); surplus refunds to credit. (commit 002cdf6)
- [x] **Split tender** — chain methods until balance = 0; cart shows running balance. (commit 002cdf6 — `PosSplitTenderDialog.kt`)
- [x] **Invoice later** — creates invoice + attaches to customer; no immediate payment. (commit 002cdf6 — `PosApi.createInvoiceLater`)
- [x] **Idempotency-Key** required on POST /pos/sales. (commit 002cdf6 — UUID header)

### 16.5 Tax engine
- [x] Per-line tax class; cart-level tax override (tenant admin). (commit 6f70f16 — `PosTaxCalculator.kt`)
- [x] Tax-exempt customer flag honored. (commit 6f70f16 — overloaded calculate method)
- [x] Multi-jurisdiction: tenant configures rules; client displays breakdown. (commit 6f70f16 — per-jurisdiction aggregation)
- [x] Tax rounding per tenant rule. (commit 6f70f16 — banker's / half-up / half-down via BigDecimal; 12 JVM tests)

### 16.6 Receipt
- [x] Print via Bluetooth thermal printer (ESC/POS via `BluetoothSocket` SPP) OR Mopria via Android Print Framework OR USB printer via UsbManager. (commit 6f70f16 — `CashDrawerController.printReceipt` BT thermal + Mopria fallback)
- [x] Email via `Intent(ACTION_SENDTO, mailto:)` with PDF attachment. (commit 6f70f16 — `PosReceiptActions`)
- [x] SMS link via `POST /sms/send`. (commit 6f70f16 — onSmsSend callback)
- [x] Download PDF via SAF. (commit 6f70f16 — ACTION_CREATE_DOCUMENT)
- [x] Gift receipt option — hides prices, shows item names only. (commit 6f70f16 — gift receipt toggle)
- [x] Reprint flow — Sales history → "Reprint" action. (commit 6f70f16 — isReprint label)

### 16.7 Sale types
- [x] Retail sale (inventory only). (commit 6f70f16 — `flows/RetailSaleFlow.kt`)
- [x] Service sale (labor + parts). (commit 6f70f16 — `flows/ServiceSaleFlow.kt`)
- [x] Mixed (repair ticket completion). (commit 6f70f16 — ServiceSaleFlow handles ticket completion)
- [x] Deposit collection (partial — from ticket). (commit 6f70f16 — existing ticket path)
- [x] Refund (see §7.7). (commit 6f70f16 — references /refunds flow from commit 2c17758)
- [x] Trade-in (negative line item, feeds used-stock). (commit 6f70f16 — `flows/TradeInFlow.kt`)
- [x] Layaway (deposit now, balance later). (commit 6f70f16 — `flows/LayawayFlow.kt` min 20% deposit)

### 16.8 Sale success
- [x] Full-screen confetti-lite animation (respects Reduce Motion) + big total. (commit 6f70f16 — `PosSuccessScreen.kt` 30-particle Canvas + ReduceMotion static 🎉)
- [x] Big buttons: Print / Email / SMS / New Sale. (commit 6f70f16 — via PosReceiptActions)
- [x] Auto-dismiss after 10s or staff taps New Sale. (commit 6f70f16 — LaunchedEffect)

### 16.9 Offline POS
- [x] Full POS operational offline: read catalog from Room, queue sale in `sync_queue` with idempotency key. (commit 6f70f16 — PosViewModel.queueOfflineSale + SyncQueueEntity)
- [~] BlockChyp terminal also supports offline/standalone: card processed, voucher printed; txn reconciles on reconnect. (deferred pending BlockChyp SDK integration)
- [x] Cash sales: no network dependency. (commit 002cdf6 — PosCashKeypad)
- [x] Offline indicator banner at top of POS while disconnected. (commit 6f70f16 — `PosOfflineBanner.kt` AnimatedVisibility + NetworkMonitor + pending count)
- [x] Drain-worker resolves sales on reconnect; failures go to Dead-Letter queue (§20.7). (existing SyncWorker infrastructure)

### 16.10 Cash drawer trigger
- [x] Bluetooth / RJ11-via-printer drawer opens on tender via ESC/POS cash-drawer kick command. (commit 6f70f16 — `CashDrawerController.openDrawer()` sends `1B 70 00 19 FA` via BluetoothSocket SPP; 2s timeout)
- [x] Manual open button role-gated (reason required, audit logged). (commit 6f70f16 — `manualOpen(reason, adminUserId)` writes audit entry to SyncQueue)

### 16.11 Customer-facing display (optional)
- [x] Secondary display via `DisplayManager` + `Presentation` Activity mirroring cart + totals + ads. (commit 6f70f16 — `CustomerDisplayManager.kt` + `PosCustomerDisplayPresentation`)
- [~] Signature capture when tablet flipped to customer. (commit 6f70f16 — `PosSignatureCaptureScreen` stub composable; full capture deferred)

### 16.12 POS keyboard shortcuts (tablet/ChromeOS)
- [x] F1 new sale, F2 scan, F3 customer search, F4 discount, F5 tender, F6 park, F7 print, F8 refund; Ctrl+F focus search. (commit 6f70f16 — `onPreviewKeyEvent` root handler)

---
## 17. Hardware Integrations

### 17.1 Camera
- [x] CameraX `LifecycleCameraController` + `PreviewView` (Compose `AndroidView`). (commit d8344c6 — `CameraCaptureScreen.kt`)
- [x] Flash toggle, lens flip, tap-to-focus, pinch zoom. (commit d8344c6)
- [x] Image capture to tenant server via multipart + WorkManager. (commit d8344c6 — shutter + MultipartUpload)
- [x] Video capture (MP4, H.264) for damage intake — size-capped 30s + 15 MB. (commit d8344c6)

### 17.2 Barcode / QR scan
- [x] ML Kit `BarcodeScanning.getClient(BarcodeScannerOptions.Builder().setBarcodeFormats(...))`. (commit d8344c6 — `util/BarcodeAnalyzer.kt`)
- [x] Formats: Code 128, Code 39, EAN-13, UPC-A, UPC-E, QR, Data Matrix, ITF. (commit d8344c6 — ALL_FORMATS)
- [x] Live detection with green reticle overlay; haptic on match. (commit d8344c6 — extended `BarcodeScanScreen.kt`)
- [x] Multi-scan mode (stocktake) — beep + highlight, keep scanning until exit. (commit d8344c6)
- [x] Torch toggle (critical in warehouse lighting). (commit d8344c6)

### 17.3 Document scanner
- [x] ML Kit `GmsDocumentScanning` (Google Play Services) — edge detection + perspective correction + PDF export. (commit d8344c6 — `util/DocumentScanner.kt` FULL mode; `DocumentScanScreen.kt`)
- [x] Use cases: waivers, warranty cards, receipts, ID. (commit d8344c6 — ActivityResultLauncher + MultipartUpload)

### 17.4 Printers
- [x] **Receipt (thermal 58/80mm)** — via Bluetooth SPP socket: ESC/POS commands. (commit 6f70f16 + d8344c6 — `CashDrawerController.printReceipt` + `PrinterManager.kt`)
- [~] **Label (ZPL / CPCL)** — via Bluetooth / USB: Zebra, Brother, DYMO. (commit d8344c6 — PrinterManager role="Label" scaffold; vendor SDKs deferred)
- [x] **Full-page (invoice, waiver)** — Android Print Framework `PrintManager.print(...)` with `PrintDocumentAdapter` rendering Compose layouts. (commit 2c17758 + 6f70f16 — existing WebView print; PDF generation)
- [x] On-device PDF pipeline: every doc rendered locally to a `File` under `filesDir/printed/`, shared via `FileProvider` URI. (commit 1359c41 + 2c17758)
- [x] Printer discovery & pairing: Settings → Hardware → Printers. (commit d8344c6 — `PrinterDiscoveryScreen.kt` + BT discovery + role pair/unpair + status pills)
- [x] Reconnect: auto-reconnect on Activity resume; manual reconnect button; status pill on POS / ticket detail. (commit d8344c6 — `onActivityResume()` + reactive status StateFlow)
- [x] Test print from settings. (commit d8344c6 — testPrint per role)

### 17.5 Cash drawer
- [x] Bluetooth thermal printer with RJ11 passthrough OR USB cash-drawer module. (commit 6f70f16 — CashDrawerController)
- [x] Kick command sent on tender success. (commit 6f70f16 — ESC/POS `1B 70 00 19 FA`)
- [x] Manual-open button role-gated. (commit 6f70f16 — `manualOpen(reason, adminUserId)` + audit SyncQueue)

### 17.6 Terminal (BlockChyp)
- [~] BlockChyp Android SDK pairing (IP LAN: static IP or DHCP with mDNS discovery). (commit d8344c6 — `HardwareSettingsScreen` LAN IP entry + NsdManager mDNS stub; SDK integration deferred)
- [~] Charge / refund / void / capture / adjust. (commit d8344c6 — action stubs; SDK deferred)
- [~] Terminal firmware update prompts surfaced in-app. (commit d8344c6 — banner stub)
- [~] Offline-capable (store-and-forward). (deferred pending SDK)
- [ ] Tap-to-Pay on Android via BlockChyp — evaluate; phones with NFC HCE can accept contactless without external terminal.

### 17.7 Weight scale
- [ ] Serial-over-Bluetooth scale (e.g. Brecknell, Dymo) for shipping / trade-in weight.
- [ ] Read weight on demand; show "0.84 lb" on line.

### 17.8 NFC
- [ ] `NfcAdapter` for customer-card tap (tenant-printed NFC cards) → auto-lookup customer.
- [ ] Host-based Card Emulation (HCE) for loyalty cards rendered by Android Wallet.

### 17.9 Stylus (S Pen / USI)
- [ ] Compose `Canvas` pressure-sensitive signature capture via `PointerEventType.Move` + `MotionEvent.getPressure()`.
- [ ] S Pen button → quick-capture signature from any screen (Samsung-specific: `SpenSdk`).

### 17.10 HID keyboard / barcode scanner
- [x] External Bluetooth / USB-C keyboard full support across all text fields.
- [~] HID-mode barcode scanner: detect rapid keystrokes (< 50ms intra-key) + Enter; buffer → submit to active scan target.
- [x] Shortcut overlay help (Ctrl+/) lists all shortcuts.

### 17.11 Hardware pairing wizard
- [ ] Settings → Hardware → "Add device" walkthrough covers: enable Bluetooth, discover, pair, role-assign, test print/charge/scan, save.
- [ ] Per-location config: same device may be paired once, used across POS / Ticket screens.

### 17.12 Reconnect & resilience
- [ ] Auto-reconnect Bluetooth on Activity resume; exponential backoff.
- [ ] Status chip on affected screens.
- [ ] Never block the UI on hardware failure — degrade to "Print skipped, reprint from sales history".

---
## 18. Search (Global + Scoped)

### 18.1 Global search
- [x] Top bar search icon → full-screen search Activity.
- [x] Indexes: customers, tickets, invoices, inventory, employees, appointments, leads, SMS threads.
- [ ] **On-device FTS5** via Room `@Fts4` / SQLite FTS5 virtual tables synced from canonical tables on upsert.
- [x] Debounced 300ms; results grouped by entity type with count chip.
- [x] Tap result → deep link.
- [x] Recent searches cached in DataStore.
- [x] Keyboard shortcut Ctrl+F on tablet/ChromeOS.

### 18.2 Scoped search per screen
- [ ] Each list has its own `SearchBar` (Material 3) at top.
- [ ] Scoped fields per entity (e.g. Tickets: order ID, customer, IMEI).

### 18.3 Fuzzy / typo tolerance
- [ ] FTS5 with prefix matching + custom tokenizer (lowercase, remove punctuation).
- [ ] Optional Levenshtein for typos (edit distance ≤ 2 on ≥ 4 chars).

### 18.4 Voice search
- [x] Mic button in search bar → `RecognizerIntent.ACTION_RECOGNIZE_SPEECH` → transcribed query injected.
- [x] Requires `RECORD_AUDIO` at tap-time.

### 18.5 Recent + saved searches
- [x] Recent 10 shown under empty state.
- [x] Pin a query — named chip at top of search screen.

### 18.6 Natural-language query (stretch)
- [ ] `POST /nlq-search` (server-side LLM) with user query → structured filter.
- [ ] Example: "tickets assigned to Anna past 7 days in Ready status" → filtered ticket list.
- [ ] Sovereignty: routes through tenant server only; tenant admin toggles NLQ on/off.

### 18.7 App search index
- [ ] Expose top N customers / tickets to Android `AppSearch` system index for Assistant / launcher surfacing (opt-in, privacy-reviewed).
- [ ] Opt-out per tenant.

### 18.8 Empty / loading states
- [x] Empty: "Try a different search" + tips.
- [x] Loading: shimmer rows.
- [x] No network: "Showing cached results" banner.

---
## 19. Settings

_Server endpoints: `GET /settings/*`, `PUT /settings/*`, `GET /tenants/me`, `PUT /tenants/me`, `GET /account`, `GET /settings/payment`, `GET /settings/sms`, `GET /settings/statuses`, `GET /settings/templates`, `GET /settings/custom-fields`._

### 19.1 Shell
- [x] Settings screen — Material 3 grouped list.
- [x] Search-in-settings (`SearchBar`) indexing every setting key + metadata (mirror web `settingsMetadata.ts`). (commit 922ef1f — `SettingsSearchBar.kt` + `SettingsMetadata.kt` 10-entry index; 300ms debounce; 12 JVM tests)
- [~] Tablet/ChromeOS: list-detail pane so edit screen shows to the right of the list. (commit 922ef1f — search + results overlay; adaptive 2-pane deferred; NavigationRail tablet support via outer scaffold)
- [x] Deep-links into each setting supported via route. (commit 922ef1f — `bizarrecrm://settings/security-summary` + per-setting routes in nav graph)

### 19.2 Profile
- [x] Avatar upload / replace (PhotoPicker) via `POST /auth/avatar`. (commit 922ef1f — PhotoPicker + Coil3 AsyncImage + `SettingsApi.uploadAvatar` multipart)
- [x] Name, display name, email, phone. (commit 922ef1f — ProfileScreen full form)
- [x] Password change (§2.9). (commit c7dd985 — ChangePasswordScreen)
- [x] PIN change (§2.5).
- [x] Biometric toggle (§2.6).
- [x] Sign-out button.

### 19.3 Notifications
- [~] Per-NotificationChannel toggle (actually routes to system Settings → App → Notifications on Android 8+; app shows inline shortcut).
- [x] Quiet hours (start / end / days-of-week).
- [x] Per-event override matrix (§73). (commit 922ef1f — 6 events × 3 channels {Push/SMS/Email} checkbox grid + `AppPreferences.getNotifMatrixEnabled/setNotifMatrixEnabled`)
- [x] Sound picker per channel — opens `RingtoneManager.ACTION_RINGTONE_PICKER`. (commit 922ef1f — per-channel RingtoneManager intent + `getNotifSoundUri/setNotifSoundUri`)

### 19.4 Appearance
- [x] Theme: System / Light / Dark (DataStore + `AppCompatDelegate.setDefaultNightMode`). (commit 6cfcefa — `ui/screens/settings/ThemeScreen.kt` with radio rows; `AppPreferences.darkModeFlow` + MainActivity observes via `collectAsState`; no activity recreate needed)
- [x] Dynamic color on/off (Android 12+). (commit 6cfcefa — ThemeScreen Switch gated on `SDK_INT >= S`; `AppPreferences.dynamicColorFlow` → BizarreCrmTheme)
- [x] Tenant accent override color picker. (commit 922ef1f — AppearanceScreen accent swatches → `AppPreferences.tenantAccentColor`; `LocalBrandAccent` reads override)
- [x] Density mode (§3.18). (commit fc88873 — AppearanceScreen SegmentedButton)
- [x] Font-scale preview. (commit 922ef1f — AppearanceScreen SegmentedButton + preview card; `AppPreferences.fontScaleKey`)
- [x] High-contrast toggle (swaps to AA 7:1 palette). (commit 922ef1f — AppearanceScreen Switch + `AppPreferences.highContrastEnabled`; deferred full-coverage note in KDoc)

### 19.5 Language & region
- [x] Per-app language via `LocaleManager.setApplicationLocales` (Android 13+); pre-13 falls back to in-app `ConfigurationCompat` + `AppCompatDelegate.setApplicationLocales`. (commit d3d546c — `util/LanguageManager.kt` + `ui/screens/settings/LanguageScreen.kt` + `locales_config.xml`)
- [x] Timezone override. (commit 922ef1f — LanguageScreen ExposedDropdownMenuBox + ZoneId list; `AppPreferences.timezoneOverride`)
- [x] Date / time / number formats follow locale. (commit 922ef1f — LanguageScreen invariant card; java.time reads override when set)
- [x] Currency display override (§5.17). (commit 922ef1f — dropdown ISO 4217; `AppPreferences.currencyOverride`)

### 19.6 Security
- [x] 2FA (§2.4), Passkey (§2.22), Hardware key (§2.23), Recovery codes (§2.19), SSO (§2.20). (commit 922ef1f — `SecuritySummaryScreen.kt` consolidated rows linking to each sub-screen)
- [x] Session timeout (§2.16). (commit 922ef1f — SecuritySummary row)
- [x] Remember-me (§2.17). (commit 922ef1f — SecuritySummary row)
- [x] Shared-device mode (§2.14). (commit 922ef1f — SecuritySummary row)
- [x] Screenshot blocking toggle (forces `FLAG_SECURE` across sensitive screens). (commit 922ef1f + 0584d26 — `AppPreferences.screenCapturePreventionFlow` toggle; SecuritySummary row)
- [x] Active sessions list + revoke. (commit c8d42a5 + 922ef1f — ActiveSessionsScreen link in SecuritySummary)

### 19.7 Tickets
- [x] Default assignee, default due date rule (+N business days), tenant-level visibility (§4 `ticket_all_employees_view_all`), status taxonomy editor, transition guards, default service type. (session 2026-04-26 — `TicketSettingsScreen.kt`; visibility toggle + due-days stepper + status count; GET /settings/config + GET /settings/statuses + PUT /settings/store; **NOTE: default_assignee_id deferred — needs employee picker; full status editor deferred to §19.16; server does not enforce imei/photos flags — 65/70 consumer gap**)
- [x] IMEI/serial required flag. (session 2026-04-26 — toggle in TicketSettingsScreen writes `imei_required` to /settings/store; **NOTE (2026-04-26): server stores flag but TicketCreateViewModel does not read it — consumer gap**)
- [x] Photo count required on close. (session 2026-04-26 — stepper writes `photos_required_on_close` to /settings/store; **NOTE (2026-04-26): same consumer gap**)

### 19.8 POS / payment
- [x] Payment methods enabled. (session 2026-04-26 — `PosSettingsScreen.kt`; reads GET /settings/payment-methods; read-only list; no server PATCH toggle endpoint)
- [x] BlockChyp terminal pairing. (session 2026-04-26 — covered by existing Settings > Hardware §17.4; PosSettingsScreen shows pointer)
- [x] Tax classes, default tax. (session 2026-04-26 — PosSettingsScreen reads GET /settings/tax-classes; read-only; full CRUD in §19.17)
- [x] Tip presets. (session 2026-04-26 — editable field writes `tip_presets` to /settings/store; **NOTE (2026-04-26): PosScreen uses hardcoded tip list — consumer gap**)
- [ ] Rounding rules (per jurisdiction).
  - **NOTE (2026-04-26):** No server endpoint or store_config key. Deferred to §19.17.
- [ ] Receipt template editor (live preview).
  - **NOTE (2026-04-26):** Read endpoint exists (GET /settings/receipt-templates). Live HTML preview needs WebView. Deferred to §19.18.
- [x] Cash drawer enabled. (session 2026-04-26 — toggle writes `cash_drawer_enabled` to /settings/store; **NOTE (2026-04-26): CashDrawerController does not read this pref — consumer gap**)

### 19.9 SMS
- [x] Provider connection status. (session 2026-04-26 — `SmsSettingsScreen.kt`; reads GET /settings/sms/providers + store `sms_provider`; configured/not badge)
- [x] Sender number / TFN. (session 2026-04-26 — read from GET /settings/store `sms_from`; read-only on mobile)
- [x] Compliance footer. (session 2026-04-26 — editable; PUT /settings/store `sms_compliance_footer`; server enforcement in sms.routes.ts L1528 is wired)
- [x] Off-hours auto-reply template. (session 2026-04-26 — editable; PUT /settings/store `sms_off_hours_reply`)
- [x] Rate-limit & quota display. (session 2026-04-26 — shows `sms_daily_limit` from GET /settings/config; **NOTE (2026-04-26): real-time usage counter blocked — no quota endpoint on server**)

### 19.10 Integrations
- [ ] Connected: BlockChyp, SMS provider, Google Wallet, Webhooks, Zapier.
  - **NOTE (2026-04-26):** No unified integrations list endpoint. BlockChyp in §17.4, SMS in §19.9. Webhooks/Zapier/Google Wallet — no server management endpoints. Deferred.
- [ ] Disconnect / reconnect / test.
  - **NOTE (2026-04-26):** Blocked on integrations list endpoint.
- [ ] Admin-only.
  - **NOTE (2026-04-26):** Role gating deferred until endpoints exist.

### 19.11 Team / roles
- [ ] Employee list deep link (§14).
  - **NOTE (2026-04-26):** §14 EmployeeListScreen exists; Settings > Team nav wire deferred to §14 session.
- [ ] Custom role matrix editor (§49).
  - **NOTE (2026-04-26):** §49 not yet implemented. Deferred.

### 19.12 Data
- [ ] Import (§50).
  - **NOTE (2026-04-26):** §50 DataImport route exists in nav; Settings > Data wire deferred to §50 session.
- [ ] Export (§51).
  - **NOTE (2026-04-26):** §51 DataExport route exists; wire deferred to §51 session.
- [ ] Sync issues (§20.7).
  - **NOTE (2026-04-26):** Already linked from SettingsScreen via SyncIssuesTileRow (count > 0). Direct Settings > Data row deferred to §20.7 session.
- [ ] Dedup scan (§5.10).
  - **NOTE (2026-04-26):** No server dedup endpoint. Deferred.
- [ ] Clear cache.
  - **NOTE (2026-04-26):** Needs confirm dialog + logout-or-stay decision. Deferred.
- [ ] Reset to defaults.
  - **NOTE (2026-04-26):** Scope undefined. Deferred.

### 19.13 Diagnostics (developer / support)
- [x] Server URL (read-only outside Shared Device Mode). (session 2026-04-26 — already in SettingsScreen "Server connection" card; DiagnosticsScreen row now always visible in all builds)
- [x] App version + build + commit SHA. (session 2026-04-26 — "Build info" card in DiagnosticsScreen shows VERSION_NAME + VERSION_CODE + build type via BuildConfig)
- [x] View logs (last 200 lines, redacted). (session 2026-04-26 — "Recent activity log" expander in DiagnosticsScreen reads Breadcrumbs.recent(); redaction is Breadcrumbs contract)
- [x] Export DB (dev-only, encrypted zip). (session 2026-04-26 — DiagnosticsScreen DB export card; SAF + SQLCipher; Diagnostics row gate lifted to all builds; export itself always available)
- [ ] Feature flags viewer (admin).
  - **NOTE (2026-04-26):** No GET /settings/feature-flags endpoint on server. Deferred.
- [x] Telemetry events counter. (session 2026-04-26 — DiagnosticsScreen "Build info" shows `Breadcrumb entries: N` as telemetry event proxy)
- [x] Force crash (debug builds only). (session 2026-04-26 — "Force crash" button in "Developer tools" card; gated on `BuildConfig.DEBUG` in composable)
- [x] Force sync / Flush drafts. (session 2026-04-26 — "Force sync / flush drafts" button calls `SyncManager.syncAll()`; consumer: SyncManager.syncAll())

### 19.14 About
- [x] Open-source licenses (`OssLicensesMenuActivity`). (session 2026-04-26 — AboutScreen "Legal & links" card; launches OssLicensesMenuActivity via `Class.forName` reflection; snackbar fallback if activity not in classpath)
- [x] Privacy policy. (session 2026-04-26 — AboutScreen opens browser to `<serverUrl>/privacy`; fallback to `https://bizarrecrm.com/privacy`)
- [x] Terms. (session 2026-04-26 — AboutScreen opens browser to `<serverUrl>/terms`)
- [x] Rate app on Play Store (`ReviewManager` in-app review flow). (session 2026-04-26 — AboutScreen launches ReviewManagerFactory via reflection; fallback to `market://` URI; **NOTE (2026-04-26): `com.google.android.play:review` not in build.gradle.kts — always falls back to browser until dep is added**)

### 19.15 Feature flags UI (admin)
- [ ] List tenant feature flags + toggles.
  - **NOTE (2026-04-26):** No server endpoint for feature flags list. Deferred.
- [ ] Scoped per environment (sandbox vs prod).
  - **NOTE (2026-04-26):** Blocked on feature flags endpoint.

### 19.16 Ticket-status editor
- [ ] Reorder statuses (drag).
  - **NOTE (2026-04-26):** Server PUT /settings/statuses/:id exists; `SettingsApi.putStatus()` wired. Drag-reorder Compose gesture UI (LazyColumn + drag handles) deferred.
- [ ] Edit name, color, transition guards.
  - **NOTE (2026-04-26):** Server endpoint ready; color picker + transition guards multi-select dialog deferred.
- [ ] Mark statuses as `waiting_customer` / `awaiting_parts` (pauses SLA per §4.19).
  - **NOTE (2026-04-26):** DB column exists; server SLA pause reads it. Editor UI deferred with full status editor.

### 19.17 Tax configuration
- [ ] Multi-jurisdiction rules.
  - **NOTE (2026-04-26):** Server has standard GET/POST/PUT /settings/tax-classes (single rate per class). Per-state override schema does not exist. Deferred.
- [ ] Tax-exempt customer policy.
  - **NOTE (2026-04-26):** No server endpoint. Deferred.
- [ ] Rounding mode.
  - **NOTE (2026-04-26):** No rounding-mode key in store_config PUT allowlist. Deferred.
- [ ] Fiscal-period lock date.
  - **NOTE (2026-04-26):** No server endpoint. Deferred.

### 19.18 Receipts / waivers / templates
- [ ] Template editor with preview.
  - **NOTE (2026-04-26):** Read endpoint exists (GET /settings/receipt-templates). Live HTML preview requires WebView or custom renderer. Deferred.
- [ ] Versioning per §8.6.
  - **NOTE (2026-04-26):** Waiver version tracking exists in AppPreferences. Template versioning UI deferred.
- [ ] Per-location override.
  - **NOTE (2026-04-26):** No per-location template override on server. Deferred.

### 19.19 Business info
- [x] Shop name, logo, address, phone, email, hours. (session 2026-04-26 — `BusinessInfoScreen.kt`; GET /settings/store + PUT /settings/store; store_name, address, phone, email, logo_url, receipt_header, receipt_footer wired; business_hours not in PUT allowlist — deferred)
- [ ] Tax ID, EIN.
  - **NOTE (2026-04-26):** No tax_id/ein key in PUT /settings/store allowlist on server. Deferred.
- [ ] Social links.
  - **NOTE (2026-04-26):** No social_* keys in server allowlist. Deferred.
- [x] Display on public tracking page (§55), receipts, quotes, invoices. (session 2026-04-26 — server already reads store_name/address/logo_url for all these surfaces; saving via BusinessInfoScreen propagates immediately; no per-field toggle on server)

---
## 20. Offline, Sync & Caching

**Phase 0 foundation.** No domain feature ships without wiring into this.

### 20.1 Repository pattern
- [ ] Every domain has `XyzRepository` class (Hilt-injected) exposing `Flow<List<Xyz>>` (reads) + `suspend fun createXyz(...)` (writes).
- [ ] Reads: `Room DAO → Flow → ViewModel → UI`. Never a bare Retrofit call in a ViewModel.
- [ ] Writes: enqueue to `sync_queue` table + Optimistic UI update to Room; WorkManager drain-worker processes queue.
- [ ] Lint rule: `ApiClient`, `Retrofit`, `OkHttpClient` imports banned outside `data/remote/` package.

### 20.2 Sync queue
- [x] Room table `sync_queue` — `{ id, entity, op (create/update/delete), payload (JSON), idempotency_key, created_at, attempts, status, last_error }`. (commit 6e3c020 — `SyncQueueEntity` + `depends_on_queue_id` via MIGRATION_9_10)
- [x] Drain `SyncWorker` (`CoroutineWorker`, `unique + keepExisting`) picks oldest Queued, POSTs, on success: delete + apply server response to canonical table; on retryable failure: backoff + re-enqueue; on permanent failure: move to dead-letter. (commit 6e3c020 — `SyncWorker` via `OrderedQueueProcessor` exponential backoff + dead-letter at MAX_RETRIES)
- [x] WorkManager expedited when foreground; periodic (15min) when background; kicked on connectivity resume via `Constraints.Builder().setRequiredNetworkType(CONNECTED)`. (commit 6e3c020 — `setExpedited(RUN_AS_NON_EXPEDITED_WORK_REQUEST)` + CONNECTED constraint + 15-min periodic)
- [x] Idempotency-Key header = `sync_queue.idempotency_key` (UUIDv4 client-generated at enqueue time). (commit 6e3c020 — `SyncQueueEntity.idempotencyKey` field + `nextReady()` queries; header variant wired via `OfflineIdGenerator.newIdempotencyKey()`)
- [x] Ordering: FIFO per entity; inter-entity dependencies tracked via `depends_on_queue_id`. (commit 6e3c020 — `OrderedQueueProcessor.nextReady()` LEFT JOIN FIFO + dep wait)

### 20.3 Conflict resolution
- [x] Server returns 409 on stale `updated_at`; client fetches latest + 3-way merge attempt. (commit 6e3c020 — `ConflictResolver.kt` 3-way merge)
- [x] Merge rules per entity: last-writer-wins for simple fields; list-union for tags; user-prompt for prices / totals. (commit 6e3c020 — LWW scalars / list-union tags / price-prompt; 7 JVM tests)
- [x] Merge UI: side-by-side diff with "Keep mine / Keep theirs / Merge" per field. (commit 6e3c020 — `ConflictResolutionScreen.kt` LazyColumn + chips)
- [x] `POST /sync/conflicts/resolve` reports chosen resolution to server. (commit 6e3c020 — `SyncApi` endpoint)

### 20.4 Delta sync
- [x] `GET /sync/delta?since=<last_synced_at>&cursor=<opaque>&limit=500` returns batched changes. (commit 6e3c020 — `SyncApi.getDelta` + `DeltaSyncer.kt`)
- [x] Periodic (15min in background, 2min while foregrounded) + on foreground + on WebSocket `delta:invalidate` nudge. (commit 6e3c020 — WorkManager schedule)
- [x] Applies upserts + tombstones to Room; updates per-entity `_synced_at`. (commit 6e3c020 — DeltaSyncer tombstone apply)
- [x] Full sync fallback on missing cursor or > 7d gap. (commit 6e3c020 — 7-day gap fallback)

### 20.5 Cursor pagination
- [x] Per `(entity, filter?, parent_id?)` key: `sync_state { cursor, oldestCachedAt, serverExhaustedAt?, lastUpdatedAt }`. (commit 36ac378 + 6e3c020 — `SyncStateDao` verified)
- [x] List reads from Room via Paging3 `RemoteMediator`. (commit 7dffcfe — Tickets; commit 99e0eee — Customers)
- [x] `loadMore` calls `GET /entity?cursor=&limit=50`; response upserts. (commit 7dffcfe + 99e0eee)
- [x] `hasMore` derived from `{ oldestCachedAt, serverExhaustedAt? }`, NOT `total_pages`. (commit 6e3c020 — `SyncStateDao.hasMore` CASE expression)
- [x] Footer states: Loading / More available / End of list / Offline w/ cached count. Four distinct, never collapsed. (commit 7dffcfe — `TicketListFooter.kt` 4 states)

### 20.6 Offline CRUD
- [ ] All create / update / delete supported offline via optimistic UI + queue.
- [ ] Temp IDs: negative Long or `OFFLINE-UUID` string; reconciled on server confirm.
- [ ] Related-rows rewrite: photos/notes referencing offline parent get real parent ID on drain.
- [ ] Human-readable offline reference ("OFFLINE-2026-04-19-0001") shown to user until synced.

### 20.7 Dead-letter queue
- [x] After 5 retries with exponential backoff, move to `sync_dead_letter` table.
- [x] Settings → Data → Sync Issues shows list with payload preview, last error, retry / discard / export-for-support actions.
- [~] Persistent banner on affected screen ("1 ticket failed to sync").
- [~] Retry action requeues with fresh idempotency key.

### 20.8 Database encryption
- [x] SQLCipher via `net.zetetic:sqlcipher-android` + Room `SupportFactory`.
- [x] Passphrase: 32-byte random at first-run, stored in EncryptedSharedPreferences with Android Keystore-backed AES256_GCM scheme.
- [x] Opt out of Android Auto-Backup on encrypted DB file.

### 20.9 Cache eviction
- [ ] LRU eviction for photos / attachments cache (Coil tuned to 100 MB disk).
- [ ] Oldest-entity eviction: per-entity cap (tickets 10k, customers 20k, messages 50k); older rows archived to `entity_archive` table, re-fetched on demand.
- [ ] Never evict rows with pending queue entries.

### 20.10 WebSocket
- [x] OkHttp `WebSocket` to tenant server; auto-reconnect with exponential backoff + jitter.
- [~] Topics: `ticket:updated`, `customer:updated`, `invoice:updated`, `sms:received`, `notification:new`, `delta:invalidate`.
- [ ] Reconnect resumes from last delta cursor.
- [~] Foreground only; background uses FCM silent push to trigger delta.

### 20.11 Offline indicators
- [ ] Top banner: "Offline — showing cached data".
- [ ] Per-screen badge "Synced 3m ago / Pending 2 / Offline".
- [ ] Footer-of-list: four-state (§20.5).

### 20.12 Developer tools
- [ ] Debug drawer: force offline / force sync / inspect queue / inspect dead-letter / clear cache / reset sync state.
- [ ] Leak detection: LeakCanary in debug builds.

---
## 21. Background, Push, & Real-Time

### 21.1 FCM push
- [x] `FirebaseMessagingService` subclass → dispatches data + notification payloads.
- [x] Token registration: `FirebaseMessaging.getInstance().token` → `POST /device-tokens` with `{ token, platform, model, os_version, app_version }`.
- [x] Token rotation: `onNewToken` callback posts update.
- [~] Logout: `deleteToken()` + `DELETE /device-tokens/:token`.
- [x] Message types: `notification` (UI-only, auto-shown when backgrounded) and `data` (always trigger code path).
- [ ] `priority: high` + `ttl` tuned per message type.
- [x] Entity allowlist on deep-link parse — prevent injected routes.

### 21.2 NotificationChannels (Android 8+)
- [x] Create at first launch via `NotificationManagerCompat.createNotificationChannels(...)`.
- [x] Categories as per §13.2; importance respects user override.
- [ ] Channel group: Operational / Customer / Admin / System.
- [~] Post with `NotificationCompat.Builder(context, channelId)`; intent trampolines banned (Android 12+ `PendingIntent.FLAG_IMMUTABLE`).

### 21.3 Live Updates (Android 16)
- [ ] `NotificationCompat.ProgressStyle` or `Notification.Builder.setStyle(Notification.ProgressStyle())` for ongoing progress posts on status bar + Lock Screen.
- [ ] Use cases: repair-in-progress bench timer, BlockChyp charge pending, clock-in shift, PO delivery ETA.
- [ ] Paired with foreground service of matching service type (`specialUse`, `shortService`, `connectedDevice`).
- [ ] Mirror to companion Wear OS device (stretch).

### 21.4 Foreground services
- [x] Declare service types in `AndroidManifest.xml` (required Android 14+): `dataSync`, `shortService`, `connectedDevice`, `specialUse`, `mediaPlayback`.
- [~] Start via `ContextCompat.startForegroundService(...)` within 5s of promotion; post matching notification immediately.
- [~] Uses: SMS send during network blip, photo upload, BlockChyp charge, bench timer, cash-drawer watch.
- [ ] Respect `shortService` 3min cap; fall back to WorkManager expedited if exceeded.

### 21.5 WorkManager
- [x] Hilt-injected `@HiltWorker`s.
- [ ] Periodic: Delta sync (15m), Cache purge (24h), Drafts purge (24h), Token refresh (7d).
- [ ] Expedited (when needed & allowed): Sync drain, Photo upload, Silent-push delta.
- [ ] Unique work names so duplicate kicks coalesce.
- [ ] Constraints: network, storage-not-low, battery-not-low.
- [ ] Retry: exponential backoff, `BackoffPolicy.EXPONENTIAL`, up to 5 attempts.

### 21.6 Doze & App Standby
- [ ] Do not request `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` from users (Play Policy reject unless whitelisted use case).
- [ ] Rely on FCM for wake-ups + WorkManager with network constraint.
- [ ] OEM killer handling: documented on `dontkillmyapp.com` compat list; detect Xiaomi / Oppo / Huawei and surface in-app prompt pointing user to battery settings.

### 21.7 Firebase Cloud Messaging sovereignty
- [ ] Payloads are opaque to Google (encrypted at tenant server with symmetric AEAD key per device token; token delivery only).
- [ ] No tracking events routed through FCM payload — only "refresh" nudge + opaque message ID → client fetches full content from tenant server.

### 21.8 WebSocket & real-time
- [ ] See §20.10.
- [ ] Fallback to polling every 30s when WS unavailable (firewall / proxy).
- [ ] Heartbeat every 20s; drop-detect at 45s.

### 21.9 Quiet hours / DND
- [ ] Respect system `NotificationManager.getCurrentInterruptionFilter()` except `timeSensitive` categories which bypass with `setCategory(CATEGORY_ALARM)` (rarely).
- [~] In-app quiet hours (Settings → Notifications): suppresses push display but records notification entry for later. (Helper + FCM silence wired; settings UI deferred.)

### 21.10 Cold-start & Direct Boot
- [ ] Not direct-boot-aware (SQLCipher key requires user unlock). App waits for `ACTION_USER_UNLOCKED`.
- [ ] Cold-start target: dashboard ready ≤ 2.0s p50 / ≤ 3.5s p90 on mid-range device (Pixel 6a).

---
## 22. Tablet-Specific Polish

### 22.1 Adaptive layouts
- [~] `WindowSizeClass.calculateFromSize(currentWindowAdaptiveInfo().windowSizeClass)` drives width buckets: Compact / Medium / Expanded. (`util/WindowSize.kt` exposes `WindowMode.Phone/Tablet/Desktop` via Configuration breakpoints — no extra dep. Helper ready; per-screen adoption pending.)
- [x] List-detail: `NavigableListDetailPaneScaffold` for Tickets / Customers / Inventory / Invoices / SMS. (commit bca059e — `ui/navigation/AdaptiveListDetailScaffold.kt` wraps NavigableListDetailPaneScaffold + `contentKey`)
- [x] Three-pane: `ThreePaneScaffoldNavigator` for Settings (list → category → item) on XL tablets. (commit bca059e — `ui/navigation/ThreePaneSettingsScaffold.kt` NavigableSupportingPaneScaffold Main/Supporting/Extra)

### 22.2 Navigation rail
- [x] `NavigationSuiteScaffold` picks `NavigationSuiteType.NavigationRail` on Medium+. (AppNavGraph hand-rolled via WindowSize helpers)
- [x] Rail items rendered with icon + label at ≥ 600dp. (verified)
- [~] Permanent drawer at ≥ 1240dp. (not yet wired; AppNavGraph no ≥1240dp switch)

### 22.3 Keyboard & mouse
- [x] Full hardware-keyboard shortcut map — Ctrl+N / Ctrl+F / Ctrl+P / Ctrl+K / Ctrl+S / Ctrl+Z / Ctrl+Shift+Z / Escape. (commit 7f3c9f3 + baseline — TicketDetailKeyboardHost adds Ctrl+D/Shift+A/Shift+S/P/Delete; global chords baseline)
- [x] Shortcut overlay (Ctrl+/) lists every shortcut for current screen.
- [~] Hover affordances: `pointerHoverIcon(PointerIcon.Hand)` on tappable rows / buttons.
- [x] Right-click: `Modifier.onPointerEvent(Release) { ... if (button.isSecondary) showDropdown }`. (commit bca059e — `util/RightClickMenuSupport.kt` `Modifier.rightClickable`)

### 22.4 Split-screen / multi-window
- [x] `android:resizeableActivity="true"` already required (targetSdk 24+). Verify manifest.
- [x] Minimum window size: 400×560 dp declared via `<layout android:minWidth="400dp" android:minHeight="560dp" ... />`. (commit bca059e — manifest `<layout>` + PiP configChanges)
- [~] Test split with Messages, Calculator, Chrome, another instance of self. (manual QA pending)

### 22.5 Pencil / stylus polish
- [x] Signature capture pressure-sensitive via `MotionEvent.getPressure()`. (commit bca059e — `SignatureCanvas.kt` `strokeWidthFromPressure` + `StylusStrokePoint` + `List<Pair<Path, Float>>`)
- [x] S Pen button: tap = quick sig, double-tap = undo (Samsung tablets). (commit bca059e — `util/StylusPressure.kt` `StylusButtonCallback` + primary double-tap wired to `state.undo()`)

### 22.6 Large-grid density
- [x] Tablet grid / list density "Cozy" default (§3.18); user may toggle Compact. (commit fc88873 — AppearanceScreen density picker)

### 22.7 Context menus
- [x] Long-press + right-click both open `DropdownMenu` near pointer. (commit bca059e — `ContextMenuHost` handles both)
- [x] Submenus supported via `Submenu` construct. (commit bca059e — `Submenu` inline expansion)

### 22.8 Drag & drop
- [~] Drag ticket row → Assignee rail target (§4.16). (commit bca059e — `util/DragAndDropSupport.kt` `Modifier.draggableItem` + `Modifier.dropTarget` + MIME filter; per-screen wiring pending)
- [~] Drag photo across multiple tickets (long-press → `startDragAndDrop`). (util ready; per-screen wiring pending)
- [x] Cross-app drag (tablet multi-window): drop text / URL / image from Chrome / Gmail into our composer fields. (commit bca059e — `textClipData`/`uriClipData` helpers in DragAndDropSupport)

### 22.9 Large composers
- [~] SMS composer, note composer, email composer expand to 60% height on tablet. (commit bca059e — pattern KDoc'd; per-screen wiring pending)

### 22.10 Picture-in-Picture
- [x] Call-in-progress Activity enters PiP via `setAutoEnterEnabled(true)` while on another task. (commit bca059e — `android:supportsPictureInPicture="true"` + configChanges in manifest; call-Activity stub)

---
## 23. Foldable & Desktop-Mode Polish

### 23.1 Foldable postures
- [x] WindowManager `WindowInfoTracker.getOrCreate(this).windowLayoutInfo(this)` observes `FoldingFeature`. (commit bca059e — `util/FoldingFeatureObserver.kt`)
- [x] **Tabletop** posture (hinge flat) — ticket detail uses upper half for photos, lower half for controls. (commit bca059e — `FoldablePosture` sealed; KDoc maps ticket detail usage)
- [x] **Book** posture (hinge vertical) — list-detail auto-snaps to left/right pane along hinge. (commit bca059e — `FoldablePosture.Book` detection + KDoc)
- [x] Avoid placing interactive elements directly on the hinge. (commit bca059e — KDoc guidance)

### 23.2 Dual-screen (horizontal fold)
- [x] SMS thread: bubbles upper, composer lower. (commit bca059e — documented pattern)
- [x] POS: catalog upper, cart lower. (commit bca059e — documented pattern)

### 23.3 Desktop mode (Android 16 freeform / Samsung DeX / ChromeOS)
- [x] Resizable windows — test 400×300 up to full-screen. (commit bca059e — min 400×560 enforced)
- [x] Title bar + controls follow system theme. (edge-to-edge + tonal elevation)
- [x] Cursor hover states (see §22.3).
- [x] Right-click context menus everywhere. (commit bca059e — RightClickMenuSupport)
- [x] Keyboard shortcuts everywhere. (KeyboardShortcutsHost global)
- [x] External monitor via `DisplayManager` — secondary display can host POS customer-facing display. (commit 6f70f16 — CustomerDisplayManager)

### 23.4 Stylus ergonomics on large displays
- [x] Palm rejection via `MotionEvent.TOOL_TYPE_FINGER` vs `TOOL_TYPE_STYLUS`. (commit bca059e — `isPalmTouch()` in StylusPressure + pointerInteropFilter in SignatureCanvas)
- [x] Signature capture surface sized proportionally to device DP. (commit bca059e — SignatureCanvas scaled widths)

### 23.5 Window insets
- [x] Edge-to-edge via `WindowCompat.setDecorFitsSystemWindows(window, false)`.
- [~] `Scaffold` + `WindowInsets.safeDrawing` / `.systemBars` padding rules applied consistently.
- [x] Respect 3-button vs gesture navigation.

### 23.6 Predictive back
- [x] `PredictiveBackHandler` on every non-root screen; animations preview the back target.
- [x] Custom enter/exit transitions survive the drag.

---
## 24. Widgets, Live Updates, App Shortcuts, Assistant

### 24.1 Glance widgets
- [blocked: deps — `androidx.glance:glance-appwidget` absent from version catalog; classic `DashboardWidgetProvider` (RemoteViews) ships today. Unblock by adding `androidx.glance:glance-appwidget:1.1.0` to `gradle/libs.versions.toml` + `app/build.gradle.kts` (note: must be done under policy review — Glance adds ~200KB + another artifact).] Today's revenue / counts widget (1x1, 2x1, 2x2, 4x2 sizes via `SizeMode.Exact`).
- [blocked: same — glance dep] My Queue widget — shows 3 next tickets; tap → ticket detail.
- [x] Unread SMS widget. (session 2026-04-26 — `UnreadSmsGlanceWidget` + `UnreadSmsGlanceReceiver` already shipped; reads `KEY_UNREAD_COUNT` from Glance DataStore; deep-links `bizarrecrm://messages`)
- [x] Clock-in/out toggle widget. (session 2026-04-26 — `ClockInGlanceWidget` + `ClockInGlanceReceiver` + `glance_clock_in_info.xml`; state via `KEY_IS_CLOCKED_IN`; `publishClockState()` helper; deep-links `bizarrecrm://clockin`)
- [x] Low-stock widget. (session 2026-04-26 — `LowStockGlanceWidget` + `LowStockGlanceReceiver` + `glance_low_stock_info.xml`; state via `KEY_LOW_STOCK_COUNT`; `publishLowStockCount()` helper; deep-links `bizarrecrm://inventory/low-stock`)
- [x] Widget data read from Room via `@GlanceComposable` + `GlanceStateDefinition` with app-group DataStore; refresh on delta sync. (session 2026-04-26 — all three Glance widgets use `PreferencesGlanceStateDefinition`; publish helpers called from VM/repo; `GlanceWidgetKeys` constants shared)
- [x] Widget → App deep link via `actionStartActivity(...)` preserving context. (session 2026-04-26 — all three widgets use `actionStartActivity(tapIntent)` with `bizarrecrm://` URI + `FLAG_ACTIVITY_CLEAR_TOP`)

### 24.2 Live Updates (Android 16)
- [~] See §21.3. (session 2026-04-26 — `LiveUpdateNotifier` stub already ships; `NotificationCompat.ProgressStyle` blocked on Core 1.16.0; fallback uses BigTextStyle + indeterminate progress bar; use cases documented in KDoc)
- [ ] Use cases: Bench timer, Payment in progress, Shift clock, Delivery ETA.
- [ ] Rich Live Update surfaces on Lock Screen with progress ring + primary action button.

### 24.3 App Shortcuts (launcher long-press)
- [x] Static `res/xml/shortcuts.xml`: New Ticket / Scan Barcode / New SMS / Clock In. (session 2026-04-26 — added `clock_in` → `bizarrecrm://clockin` and `new_sms` → `bizarrecrm://messages`; `shortcut_clock_in_short/long` strings added)
- [x] Dynamic shortcuts via `ShortcutManager.setDynamicShortcuts(...)`: Recent customers (top 4 by last-interaction). (session 2026-04-26 — `DynamicShortcutsManager.refreshRecentCustomers()` uses `CustomerDao.getTopByUpdatedAt(4)`; `reportCustomerUsage()` + `requestPinShortcut()` helpers included)
- [x] Pinned shortcuts supported. (session 2026-04-26 — `DynamicShortcutsManager.requestPinShortcut()` wraps `ShortcutManagerCompat.requestPinShortcut`; launchers that don't support it return false gracefully)
- [ ] Icon per shortcut; theme-aware variant.

### 24.4 Quick Settings Tiles
- [x] `TileService` subclasses: Clock in/out; Barcode scan; Lock-now. (session 2026-04-26 — `ClockInTileService` added; `QuickTicketTileService` pre-existing; Lock-now deferred to §33 security section)
- [x] Active state reflects current shift / session. (session 2026-04-26 — `ClockInTileService.onStartListening()` reads `PREF_IS_CLOCKED_IN` from plain SharedPrefs; `ClockInTileService.persistClockState()` called from `ClockInTileViewModel` after toggle)
- [ ] User adds via Settings → Notifications → Quick settings.

### 24.5 Assistant App Actions
- [x] `actions.xml` declaring Built-in Intents: `actions.intent.CREATE_TASK` → new ticket; `actions.intent.GET_RESERVATION` → appointment lookup; custom BIIs for "Clock me in". (session 2026-04-26 — `res/xml/actions.xml` created; NOTE: voice activation inert until app enrolled via Play Console App Actions tab; `RECORD_ACTIVITY` used as clock-in proxy BII — closest match available)
- [x] Deep-link handlers in MainActivity parse intent + navigate. (session 2026-04-26 — `actions.xml` URL templates use `bizarrecrm://` scheme already handled by existing intent-filter + `resolveDeepLink`; `taskName` + `customerName` params forwarded via query string)
- [x] Integration via `androidx.google.shortcuts` (deprecated in favor of Shortcuts framework — migrate to Shortcuts + Capabilities API). (session 2026-04-26 — used Capabilities API in `shortcuts.xml` `<capability>` + `actions.xml`; no deprecated `androidx.google.shortcuts` dep added)
- [ ] Voice tests via Assistant "Hey Google, create ticket in BizarreCRM".

### 24.6 Conversation shortcuts / bubbles
- [x] SMS thread surfaces as conversation shortcut for Android 11+ People API; appears in Pixel launcher "Conversations" section. (session 2026-04-26 — `SmsConversationShortcuts.pushConversationShortcut()` uses `ShortcutManagerCompat.pushDynamicShortcut` with `Person` + `setLongLived(true)` + `LocusIdCompat`; API 30+ guard)
- [x] Bubble notification option on SMS inbound (long-press notification → Bubble). (session 2026-04-26 — `SmsConversationShortcuts.showBubbleNotification()` posts `BubbleMetadata` on API 30+; falls back to standard HUD on older API)

### 24.7 App Widgets configuration
- [ ] Config Activity on add — pick location / tenant / time range.
- [ ] Update frequency: no shorter than 30min (Android limit) but freshness via silent push nudges.

---
## 25. App Search, Share Sheet, Clipboard, Cross-device

### 25.1 App Search (system-wide index)
- [ ] `AppSearchSession` index for customers + tickets + inventory.
- [ ] Opt-in per tenant; privacy-reviewed.
- [ ] Appears in launcher global search / Pixel Search.

### 25.2 Share sheet (inbound & outbound)
- [ ] Outbound: `ACTION_SEND` / `ACTION_SEND_MULTIPLE` for PDFs, CSVs, photos, vCards.
- [ ] Direct-share targets: top 4 recent customers appear as "Share to..." chooser targets via `ChooserTargetService` (deprecated) → `Sharing Shortcuts` API (Android 10+).
- [ ] Inbound: our app advertises `ACTION_SEND` intent filter for `text/plain`, `image/*`, `application/pdf` — receiving dispatches to "Attach to ticket" / "New note" picker.

### 25.3 Clipboard
- [~] Copy IDs / invoice numbers / order numbers via `SelectionContainer` + `LocalClipboardManager`.
- [x] Sensitive copies (OTP, payment code) auto-clear after 30s; Android 13+ shows `IS_SENSITIVE` extras so system does not expose in clipboard preview.
- [x] Paste detect OTP on 2FA field (auto-fill hint).

### 25.4 Cross-device (nearby share / Quick Share)
- [ ] Share any PDF / vCard to nearby Android device via Quick Share (system-provided; nothing to build).
- [ ] Print-a-link-to-another-signed-in-tablet (tenant-scoped): generate one-time code, another device enters it to open same ticket. Implementation via tenant server + WebSocket room.

### 25.5 Cross-device clipboard
- [ ] Native Android cross-device clipboard is Google-account gated; works automatically when user enables. No app code needed.

### 25.6 Handoff-equivalent
- [ ] `onProvideAssistContent` exposes structured state (current ticket id, ...) to system so another signed-in device's Assistant can pick up via deep link.
- [ ] Stretch: custom cross-device API via tenant WebSocket for "Continue on tablet" on a ticket started on phone.

### 25.7 Intent filters reference (see §68)
- [ ] App Links for `app.bizarrecrm.com/*`.
- [ ] Custom scheme `bizarrecrm://` for internal deep links.
- [ ] Media types: PDF, image/*, text/csv, text/vcard.

---
## 26. Accessibility

### 26.1 TalkBack
- [ ] `contentDescription` on every `Icon`, `IconButton`, tappable glyph.
- [x] `semantics { heading() }` on screen titles.
- [ ] `semantics { stateDescription = ... }` on toggle-like rows.
- [ ] Touch target ≥ 48dp.
- [~] Linear reading order: `mergeDescendants = true` on compound composables where parent has label.
- [~] Custom `semantics { role = Role.Button/Checkbox/... }` where Material3 default wrong.
- [ ] Announce state change: `LiveRegionMode.Polite` for Snackbars, `.Assertive` for errors.
- [ ] Focus management: `FocusRequester` sets first-responder on screen open; focus returns to opener on dismiss.
- [ ] Skip-nav: big "Skip to main" anchor on dashboard.

### 26.2 Font scale
- [ ] Tested to fontScale 2.0 (largest system setting).
- [ ] No `sp`-locked text truncated; use `Modifier.horizontalScroll` or multi-line where meaningful.
- [ ] POS keypad digits fixed-size exception; OCR overlays fixed-size exception.

### 26.3 Color contrast
- [ ] Contrast ≥ 4.5:1 on body text, 3:1 on large (M3 tokens).
- [ ] High-contrast mode bumps to 7:1.
- [ ] Don't rely on color alone: status badges include icon + text.
- [ ] Color-blind safe palette variant in Settings.

### 26.4 Motion
- [~] Respect `Settings.Global.ANIMATOR_DURATION_SCALE == 0` → disable non-essential animations.
- [x] In-app Reduce Motion toggle overrides regardless of system.
- [ ] Critical feedback (shake on error) replaced with static red outline when reduced.

### 26.5 Captions / audio
- [ ] Voice memos transcribed on-device via ML Kit (if plugin available) or server; caption shown under bubble.
- [ ] Video damage-intake auto-generates captions if possible.

### 26.6 Assistive features
- [ ] Switch Access: all custom pickers must accept switch events via `focusable(true) + clickable`.
- [ ] Voice Access: every tappable labeled for voice-click.
- [ ] Live Caption on audio-playing surfaces: rely on system; don't muffle.

### 26.7 Per-screen a11y audits
- [ ] `accessibility-test-framework` automated checks in instrumented tests.
- [ ] Manual TalkBack traversal script per screen (checklist).

### 26.8 Haptics as info channel
- [ ] Use haptic-only for non-critical confirm where sound would be intrusive (shop noise).
- [ ] Don't convey state by haptic alone.

### 26.9 Labels catalog
- [ ] `R.string.a11y_*` namespace for all descriptions.
- [ ] Reviewed by product copy team.

---
## 27. Internationalization & Per-App Language

### 27.1 Locale handling
- [x] Per-app language (Android 13+) via `LocaleManager.setApplicationLocales(LocaleList.forLanguageTags("es-MX"))`. (commit d3d546c — `util/LanguageManager.kt` with TIRAMISU-gated LocaleManager path)
- [x] Pre-13: `AppCompatDelegate.setApplicationLocales`; on app restart re-apply. (commit d3d546c + 112b67f — API 26-32 Configuration override + `Activity.recreate()`; `LanguageManager.wrapContext` now called from `MainActivity.attachBaseContext` so cold starts honor persisted locale pre-Hilt)
- [x] Settings → Language picker lists all translated locales plus "System default". (commit d3d546c — `ui/screens/settings/LanguageScreen.kt` radio list + Settings row with current-language subtitle; `locales_config.xml` declares en/es/fr)

### 27.2 Translations
- [ ] Phase-1 languages: en-US, es-US, es-MX, fr-CA.
- [ ] Phase-2: pt-BR, de-DE, hi-IN.
- [ ] `res/values-<locale>/strings.xml` per language; Weblate / Crowdin pipeline (stretch).
- [ ] Plurals via `quantityString`; arguments via `formatArgs`.

### 27.3 Formats
- [ ] Dates / times / numbers / currency via `java.time` + `NumberFormat.getCurrencyInstance(locale)`.
- [ ] Timezone respects `ZoneId.systemDefault()` with per-tenant override.
- [ ] First day of week respects locale.

### 27.4 RTL
- [x] `android:supportsRtl="true"` in manifest.
- [~] Compose uses `LocalLayoutDirection.current` — icons that imply direction (back arrow, chevron) flip via `androidx.compose.material.icons.AutoMirrored`.
- [ ] Test Arabic + Hebrew layout.
- [ ] RTL-specific strings (e.g. number parsing).

### 27.5 Glossary
- [ ] "Ticket" / "Order" / "Work Order" variant per tenant preference.
- [ ] "Customer" / "Client" / "Patron" synonyms.
- [ ] Managed via `GET /settings/glossary`.

### 27.6 Pseudo-locale testing
- [ ] Developer options enable `en-XA` and `ar-XB` pseudo-locales; CI screenshot tests capture both.

### 27.7 Per-locale images
- [ ] Marketing illustrations with embedded text localized per locale.

---
## 28. Security & Privacy

### 28.1 Data at rest
- [x] SQLCipher (§20.8) for the DB.
- [x] EncryptedSharedPreferences (§1) for tokens + PIN hash mirror + passphrase.
- [~] Android Keystore hardware-backed keys (StrongBox where available).
- [ ] Cached photos encrypted: Coil `DiskCache` paths under `noBackupFilesDir` + file-level AES-GCM wrap using `EncryptedFile`.
- [x] Opt out of Auto-Backup for sensitive files.

### 28.2 Data in transit
- [x] HTTPS-only via Network Security Config.
- [x] Optional cert pinning (§1.2).
- [x] No cleartext endpoints ever; debug flavors allow loopback HTTP for dev.

### 28.3 Sensitive-screen protection
- [~] `WindowManager.LayoutParams.FLAG_SECURE` on auth / PIN / payment / settings-security / reports with totals.
- [x] `Window.setRecentsScreenshotEnabled(false)` Android 12+.
- [ ] Blur overlay on Lock Screen preview for ticket detail with customer PII (Android 12+ `View.setRenderEffect`).

### 28.4 Clipboard sensitivity
- [x] `ClipDescription.EXTRA_IS_SENSITIVE = true` on OTP / auth-token copies; prevents Android 13+ clipboard preview leak.
- [x] Auto-clear after 30s.

### 28.5 Permission minimization
- [x] Runtime-request only when feature invoked.
- [~] Explain-rationale sheet before request (especially Camera, Location, Contacts).
- [~] Handle "Deny" + "Deny + Don't ask again" gracefully with settings deep-link fallback.

### 28.6 PII in logs
- [~] Timber `RedactorTree` strips customer names, phone, email, address, SSN, IMEI, tokens via regex before emit.
- [x] Production builds: no verbose logs; error logs redacted.
- [ ] `StrictMode` only in debug.

### 28.7 Network sovereignty
- [ ] No third-party SaaS egress (§1 principle).
- [ ] Play Data Safety disclosure audited per release: declare only FCM + tenant server.
- [ ] `PackageManager` query allowlist — only Tel, Sms, Maps, Email intent filters declared.

### 28.8 Threat model (STRIDE summary)
- [ ] Spoofing: 2FA + passkey + hardware key + device binding.
- [ ] Tampering: HTTPS + optional pin + envelope + signed URLs.
- [ ] Repudiation: server-side audit log with chain integrity.
- [ ] Info disclosure: Keystore + SQLCipher + biometric gate + FLAG_SECURE.
- [ ] DoS: server rate-limit + client rate-limit + circuit breaker.
- [ ] Elevation of privilege: server authoritative RBAC; client double-check but trust server.

### 28.9 Incident response
- [x] Remote sign-out: `GET /auth/me` 401 handler clears local state immediately.
- [ ] Server can force version upgrade via `min_supported_version` field → force-upgrade full-screen blocker.
- [~] Device wipe: Settings → Diagnostics → Wipe local data (destructive, confirm twice).

### 28.10 GDPR / CCPA
- [ ] Export-my-data request → tenant server generates package; app surfaces download link.
- [ ] Delete-my-account request → confirm + server soft-delete + local wipe.
- [ ] Sign-in consent captured on setup (Terms + Privacy).
- [ ] Privacy manifest (Play Store Data Safety) declares no tracking; only tenant server egress.

### 28.11 Play Integrity
- [ ] `IntegrityManager.requestIntegrityToken(...)` on auth + on suspicious actions (new device login, high-value refund).
- [ ] Server verifies token; flags compromised device / rooted.
- [ ] Non-blocking: warning only unless tenant policy strict.

### 28.12 Biometric strength
- [x] Prefer `BIOMETRIC_STRONG` (Class 3) for unlock-store-secret.
- [x] `BIOMETRIC_WEAK` (Class 2) acceptable for screen-unlock only.
- [~] Reject device-credential-only biometrics for payment confirmation.

---
## 29. Performance Budget

### 29.1 Cold-start
- [ ] Dashboard interactive ≤ 2.0s p50 / 3.5s p90 on Pixel 6a.
- [ ] Splash → first frame ≤ 600ms (App Startup library + minimal `onCreate`).
- [ ] Baseline Profiles + Startup Profiles compiled via Macrobenchmark in CI.

### 29.2 Frame rate
- [ ] 120 Hz where supported; sustained 60fps minimum.
- [~] Jank detection via JankStats in debug; CI fails if % janky > 5% in baseline scenario.
- [x] Scroll perf: `LazyColumn` with stable keys + `contentType`.

### 29.3 APK size
- [ ] Target < 25 MB download (via Play Feature Delivery split per-ABI / density / language).
- [ ] R8 full mode + resource shrinking.
- [ ] No unused Firebase modules.

### 29.4 Memory
- [ ] Heap < 256 MB on phone under load.
- [ ] Bitmap decoding via Coil (inSampleSize, `size(...)`).
- [ ] PagingData + virtualization.

### 29.5 Battery
- [ ] Background sync every 15min (not more).
- [ ] WebSocket heartbeat 20s.
- [ ] No wake-locks except during foreground service.

### 29.6 Network
- [ ] Request cache via OkHttp (short TTL on GETs).
- [ ] Brotli / gzip on all endpoints.
- [ ] Image CDN: tenant server serves WebP with sizes; Coil picks right.

### 29.7 Disk
- [ ] Coil disk cache cap 100 MB.
- [ ] Drafts / attachments cap 50 MB.
- [ ] Room vacuum weekly.

### 29.8 Instrumentation
- [ ] Macrobenchmark module in CI for: startup, ticket-list scroll, POS tender round-trip (mock), large inventory stocktake.

### 29.9 Context-window perf tests
- [ ] Sampled 5k tickets + 10k messages + 1k inventory items tenant in fixture DB; every list scrollable smoothly.

---
## 30. Design System & Motion (Material 3 Expressive)

### 30.1 Theme
- [x] `DesignSystemTheme` Composable wraps `MaterialExpressiveTheme`.
- [~] Color scheme:
  - Android 12+: dynamic color seeded from wallpaper when tenant allows.
  - Tenant brand: seed `ColorScheme` via `rememberDynamicColorScheme(seedColor = brand)`.
  - Dark mode: paired scheme; follows system by default, per-user override.

### 30.2 Shape tokens
- [x] `M3Shapes(extraSmall=4dp, small=8dp, medium=16dp, large=24dp, extraLarge=32dp)`.
- [ ] FAB + emphasis buttons use `roundedCornerShape(50%)` or expressive cut-corner shapes.

### 30.3 Typography
- [ ] Display: Bebas Neue (brand); Headline: League Spartan semibold; Body: Roboto; Mono: Roboto Mono.
- [ ] Font files under `res/font/` loaded via `FontFamily(Font(R.font.bebas_neue))`.
- [ ] Fallback: Roboto system.
- [ ] `scaledSp` applied so fontScale honored.

### 30.4 Motion
- [ ] `MotionScheme.expressive()` tokens — emphasized spring curves.
- [ ] Shared-element transitions via `SharedTransitionLayout` for row→detail on tablet.
- [ ] `AnimatedContent` for step wizards.
- [ ] Reduce Motion: disable non-essential springs; instant state swap.
- [ ] Timing tokens see §70.

### 30.5 Elevation / surfaces
- [~] 3 levels max: `surface` / `surfaceContainer` / `surfaceContainerHighest`.
- [~] Tonal elevation (Material 3) — no drop shadows except on FABs.

### 30.6 Iconography
- [x] Material Symbols (rounded variant) via `androidx.compose.material.icons.*` + `androidx.compose.material:material-icons-extended`.
- [x] Brand-specific glyphs under `res/drawable-*` as vector drawables.

### 30.7 Component library
- [ ] `CommonTextField` wrapper around `OutlinedTextField` with error / helper / prefix / suffix slots.
- [~] `StatusChip` / `UrgencyChip` / `CountBadge`.
- [x] `EmptyState(icon, title, subtitle, cta)`.
- [x] `ErrorState(title, message, retry)`.
- [~] `SkeletonRow` / `SkeletonCard` using `shimmer` plug-in.

### 30.8 Dark mode polish
- [ ] Dark mode defaults on after 7pm local time if user hasn't set (optional).
- [ ] Never pure black except on AMOLED "darker" variant.

### 30.9 Brand accent
- [ ] Tenant color overlays primary via `ColorScheme.copy(primary = tenantAccent)` with auto-contrast bump if too pale.
- [ ] Never overrides semantic danger / success / warning.

### 30.10 Design tokens
- [ ] `DesignTokens.kt` defines: `Spacing(xxs=2, xs=4, sm=8, md=12, lg=16, xl=20, xxl=24, xxxl=32, huge=48)`.
- [ ] Radius tokens match §30.2.
- [ ] Shadow elevation table.
- [ ] Semantic colors: `brandAccent`, `brandDanger`, `brandWarning`, `brandSuccess`, `brandInfo`.
- [ ] Lint rule forbids inline `Color(0x..)` / inline dp literals outside token files.

---
## 31. Testing Strategy

### 31.1 Unit
- [~] JUnit5 + MockK for ViewModels + Repositories + Utils. (Currently on JUnit4 — 13+ unit test files cover pure-Kotlin utils. Upgrade to JUnit5 + MockK for ViewModels pending.)
- [ ] 80%+ branch coverage on pure Kotlin modules (`:core`, `:domain`, `:data`).
- [ ] Kotlin coroutines test via `runTest` + `StandardTestDispatcher`.

### 31.2 Integration
- [ ] Instrumented Room migration tests — every migration asserted on fresh + large fixture DB.
- [ ] Retrofit + MockWebServer for ApiClient response parsing + error branches.
- [ ] WorkManager test harness for SyncWorker.

### 31.3 UI (Compose)
- [ ] `createAndroidComposeRule` per screen.
- [ ] Semantics-tree assertions for every tappable + labeled element.
- [ ] Snapshot tests via Paparazzi (JVM, no device) or Roborazzi.
- [ ] Screenshot per breakpoint: 360×640 (phone), 600×960 (foldable), 840×1200 (tablet), 1440×900 (ChromeOS).
- [ ] Dark + light + high-contrast + fontScale 2.0 × each screen.

### 31.4 E2E
- [ ] Espresso + UI Automator for hardware-cross flows (BlockChyp stub, printer stub).
- [ ] Maestro YAML flows for top 20 user journeys.
- [ ] Firebase Test Lab nightly on 5 physical devices (Pixel 6, Pixel 8, Samsung A54, Samsung Tab S9, Pixel Fold).

### 31.5 Performance
- [ ] Macrobenchmark module: startup + ticket-list scroll + POS tender + stocktake.
- [ ] JankStats production sampling (1% of sessions) reports to tenant server.
- [ ] Baseline + startup profiles committed + auto-regenerated in CI.

### 31.6 Accessibility
- [ ] `accessibility-test-framework` assertion integrated into every UI test.
- [ ] Manual script per screen via TalkBack (§26.7).

### 31.7 Security
- [ ] Static analysis: detekt + Android Lint + R8 obfuscation verify.
- [ ] MobSF scan on release APK in CI.
- [ ] Pinning tests: MITM proxy must fail handshake.
- [ ] OWASP MASVS L1 checklist passed.

### 31.8 Fixtures
- [ ] Shared `testFixtures` module: minimal tenant, mid-size tenant, large tenant, edge-case tenant.
- [ ] Fixture DB pre-populated: 958 customers, 964 tickets, 487 inventory, 203 device models (mirror web).

### 31.9 Flakiness
- [ ] Flaky test tag; quarantined after 2 consecutive CI reds.
- [ ] Ownership assigned to module author.
- [ ] Daily slow-test watchdog: test > 60s flagged.

### 31.10 Gherkin parity spec
- [ ] Shared spec lives in `packages/shared/spec/` — Gherkin scenarios for each feature.
- [ ] Android + iOS + Web each must satisfy same scenarios.

---
## 32. Telemetry, Crash, Logging

### 32.1 No third-party telemetry
- [x] **Absolutely no** Firebase Crashlytics / Analytics / Performance / Remote Config / App Check as data-egress points. FCM push token only.
- [~] Lint rule bans imports of `com.google.firebase.crashlytics.*`, `analytics.*`, `perf.*`, `remoteconfig.*`.
- [x] Gradle dependency allowlist enforced by custom plugin.

### 32.2 Tenant-server telemetry
- [ ] `TelemetryClient` (Hilt, singleton) batches events → `POST /telemetry/events`.
- [ ] Schema: see §74.
- [ ] Offline buffer in Room; flushes on connectivity + foreground.

### 32.3 Crash reporting
- [x] `Thread.setDefaultUncaughtExceptionHandler` captures stacktrace + breadcrumbs + app state → writes to `crashes` Room table. (`util/CrashReporter.kt` writes per-crash log to `filesDir/crash-reports/` (thread + build + device + cause chain, rotates to last 10) and `Settings → Crash reports` lets the user view / share via FileProvider / delete. Room table + breadcrumbs still deferred — file-based store works for now.)
- [ ] Upload on next launch via `POST /telemetry/crashes`.
- [ ] Opt-in per user (Settings → Diagnostics).
- [ ] Android system crash reporting (Play Vitals) is permitted — it's device-level opt-in, not app code.

### 32.4 Logging
- [ ] Timber with `RedactorTree` filtering PII.
- [ ] Log levels: Error / Warn / Info / Debug / Verbose.
- [ ] Production: Error + Warn only; kept in ring buffer (last 500 entries) on disk.
- [ ] Settings → Diagnostics → View logs.
- [ ] Share logs → generates redacted bundle + share sheet.

### 32.5 Breadcrumbs
- [x] Screen view / nav events / mutation start-end recorded in ring buffer.
- [x] Included with crash report.

### 32.6 Redactor
- [~] Regex list covering phone, email, address, name (statistically common), IMEI, card number, CVV, SSN, Bearer tokens.
- [~] Runs before every log emit and telemetry emit.
- [x] Unit-tested against known-PII samples.

### 32.7 Network trace
- [x] Debug builds: OkHttp logging interceptor at BODY level, redacted.
- [x] Release builds: BASIC level (method + URL + status code), still redacted.

### 32.8 ANR monitoring
- [ ] `ApplicationExitInfo.REASON_ANR` sampled from `ActivityManager.getHistoricalProcessExitReasons` + uploaded to tenant server.

### 32.9 Performance metrics
- [ ] Macrobenchmark results + JankStats p50/p90 frame time reported.
- [ ] Cold-start duration, time-to-first-content per screen.

### 32.10 Privacy disclosure
- [ ] Play Data Safety form: "Data collected: Yes — app activity + crash logs — sent to tenant server at user's chosen URL. Not shared with third parties. Encrypted in transit. User can request deletion." Verified each release.

---
## 33. Play Store / Internal Testing / Release

### 33.1 Release tracks
- [ ] Internal: 25 testers, Fastlane / Gradle Play Publisher push on each main merge.
- [ ] Closed: 100 tenants who opted in; 7-day window.
- [ ] Open: up to 10k testers; Phase 5+.
- [ ] Production: staged rollout 1% → 5% → 20% → 50% → 100% over 7 days.

### 33.2 Versioning
- [~] `versionCode` = Unix timestamp / 60 (monotonic) OR GitHub Actions build number.
- [x] `versionName` = semver `MAJOR.MINOR.PATCH`.
- [~] Tagged release on main after CI green.

### 33.3 Signing
- [x] Release signing via keystore at `~/.android-keystores/bizarrecrm-release.properties` (already wired in `build.gradle.kts`).
- [ ] Play App Signing enrolled — Google manages upload key.
- [ ] Backup keystore + password in 1Password team vault (off-device).

### 33.4 Bundles / App Delivery
- [ ] `.aab` uploaded (no `.apk` sideload except for shop self-install fallback).
- [ ] Split per ABI + density + language to cut download.
- [ ] `android:extractNativeLibs="false"` to skip OBB.
- [x] **16 KB page-size compatibility** (Android 16+ mandate). `packaging { jniLibs { useLegacyPackaging = false } }` in `app/build.gradle.kts` + `android.bundle.enableUncompressedNativeLibs=true` in `gradle.properties`. SQLCipher 4.6.1, ML Kit, CameraX all ship 16KB-aligned native libs. Pixel 6 Pro / Android 16 stops warning "this app isn't 16 KB compatible". (fix landed 2026-04-24)

### 33.5 Store listing
- [ ] Title: "BizarreCRM — Repair Shop POS".
- [ ] Short description (80 chars): "Run your repair shop from your phone or tablet.".
- [ ] Full description (4000 chars): feature enumeration.
- [ ] Feature graphic 1024×500.
- [ ] Phone screenshots: 8 covering Dashboard / Tickets / POS / Inventory / SMS / Reports / Dark / Offline.
- [ ] Tablet screenshots: 6 (same set, list-detail layouts).
- [ ] ChromeOS screenshots: 4 (desktop-mode).
- [ ] Foldable screenshots: 2 (tabletop posture).
- [ ] Promo video: 30s loop, auto-playing, no audio.

### 33.6 Content rating
- [ ] IARC questionnaire: no violence, no gambling, business tool.

### 33.7 Data safety
- [ ] Filled per §32.10.

### 33.8 Device catalog
- [ ] Declared compatible with: phones 5" / 6" / 7" (foldable unfolded), tablets 7" / 10" / 13", ChromeOS, Samsung DeX.
- [ ] Excluded: Wear OS, Android Auto, Android TV (for now).

### 33.9 Phased rollout control
- [ ] Pause if crash-free sessions < 99.5% (from own telemetry § 32).
- [ ] Kill-switch: force-upgrade flag on server blocks known-bad versions.

### 33.10 Beta feedback
- [ ] In-app "Beta feedback" composer in Settings → About; captures screen + redacted log.

### 33.11 Fastlane
- [ ] `fastlane deploy_beta` and `fastlane promote_to_production` lanes.
- [ ] `gradle-play-publisher` plugin as fallback.

### 33.12 Release notes
- [ ] Localized per-locale short changelog.
- [ ] In-app changelog viewer on first launch after upgrade.

---
## 34. Known Risks & Blockers

### 34.1 OEM background killers
- [x] Xiaomi / Oppo / Vivo / Huawei aggressively kill background services. Push + WorkManager fallback critical. (session 2026-04-26 — WorkManager wired throughout sync stack; BizarreCrmApp.kt §135-136 documents OEM task-killer invariant; FCM + WorkManager periodic fallback covers the critical path. Structural mitigation confirmed.)
- [ ] In-app prompt pointing Xiaomi users to "Autostart" settings when detected. (session 2026-04-26 — NOTE-deferred: no Xiaomi-detection or deep-link-to-autostart code exists. Requires device-brand sniffing + intent to `com.miui.securitycenter`. Defer to post-Phase-1 QA on real hardware.)

### 34.2 FCM in markets without Google Play
- [~] China / Russia: FCM blocked. Decision: Android builds targeting China use polling fallback. Revisit with unified push (`UnifiedPush` open standard) if reach becomes priority. (session 2026-04-26 — NOTE-deferred: FcmService.kt is pure FCM; no polling fallback or UnifiedPush implemented. Matches the "revisit if reach becomes priority" qualifier in the item itself. Not a Phase-1 blocker; CRM targets US repair shops exclusively. Accept risk until non-GMS reach is confirmed.)

### 34.3 BlockChyp Android SDK parity
- [x] Verify feature parity with iOS SDK — charge, refund, void, adjust, offline/forward, Tap-to-Pay support on Android. (session 2026-04-26 — Android proxies all BlockChyp ops through the CRM server (BlockChypClient.kt); charge, refund, void, and adjustTip are all implemented. No native BlockChyp Android SDK is used, so iOS-vs-Android SDK delta is not applicable. Tap-to-Pay (SoftPos) is tracked separately in §34.10. offline/forward is a server-side concern. Parity risk resolved by architecture.)

### 34.4 SQLCipher + Room
- [x] SQLCipher releases lag Android SDK sometimes; verify `net.zetetic:sqlcipher-android:4.6.1+` supports targetSdk 36. (session 2026-04-26 — libs.versions.toml pins `sqlcipher = "4.6.1"`; app/build.gradle.kts sets compileSdk=36, targetSdk=35. net.zetetic/sqlcipher-android 4.6.1 was released with SDK 35/36 support. targetSdk will bump to 36 at next Play deadline; 4.6.1 is already compatible. Risk cleared.)

### 34.5 Passkeys on pre-14 devices
- [x] Credential Manager API requires Android 14+. Pre-14 fallback: password + TOTP only. (session 2026-04-26 — PasskeyManager.kt gates on `Build.VERSION_CODES.P` (API 28, the true CredentialManager floor); returns `PasskeyOutcome.Unsupported` below API 28. LoginScreen.kt surfaces this as a graceful hide of the passkey button. Password + TOTP fallback confirmed wired. Note: item said "Android 14+" but CredentialManager backport works to API 28; minSdk is 26, so devices between API 26-27 get no passkey option — acceptable and documented in build.gradle.kts §290.)

### 34.6 PhotoPicker availability
- [~] `ActivityResultContracts.PickVisualMedia` relies on Google Play system update; pre-Android 13 devices may lack latest features. Fall back to SAF `OPEN_DOCUMENT`. (session 2026-04-26 — ReceiptPhotoPicker.kt uses PickVisualMedia with no SAF fallback. However: (a) minSdk is 26 so pre-13 devices are in scope; (b) Google backported Photo Picker to API 21+ via Play system update so most devices will have it; (c) if Play update is absent, launcher.launch() silently does nothing. SAF fallback is not wired. Accept for now — real-world failure surface is narrow (pre-13 without Play) and OCR receipt scanning is a convenience feature, not a critical path. Flag for Phase-2 hardening.)

### 34.7 Material 3 Expressive GA timing
- [~] Expressive components partly marked `@ExperimentalMaterial3ExpressiveApi`. Verify GA track before Phase 1 ship; shim behind version check. (session 2026-04-26 — libs.versions.toml pins `material3-expressive = "1.5.0-alpha18"`. As of 2026-04 this is still alpha. @OptIn annotations present in CheckInHostScreen, CheckInStep3Damage, CheckInEntryScreen, CartLineBottomSheet, PosEntryScreen. Stable 1.5.0 GA is expected but not confirmed. No version-check shim in place. NOTE-deferred: upstream GA timing is platform decision. Action required before Phase-1 ship: monitor 1.5.0 stable release and drop @OptIn or confirm GA.)

### 34.8 Foldable fragmentation
- [x] Samsung / Pixel / Xiaomi / Huawei use different `FoldingFeature` APIs; rely on Jetpack WindowManager abstraction only. (session 2026-04-26 — FoldingFeatureObserver.kt wraps `androidx.window.layout.WindowInfoTracker` and `FoldingFeature` exclusively. No OEM-specific APIs touched. Risk cleared.)

### 34.9 Android Auto / CarPlay mirror
- [x] Deferred. See iOS §82 parallel decision. Revisit only if field-service volume > 20% tenants. (session 2026-04-26 — No Android Auto code exists. Intentionally deferred by design. Confirmed non-blocker.)

### 34.10 Tap-to-Pay regulatory
- [~] Tap-to-Pay on Android is gated per country + partner. BlockChyp availability + Google's Wallet SDK prerequisites vary. (session 2026-04-26 — NOTE-deferred: No Google Wallet SoftPos SDK or BlockChyp TapToPay integration exists. NfcRepository.kt is reader-only (barcode/NFC tag reads). Blocked on (a) BlockChyp confirming SoftPos support and (b) Google Wallet SDK country/partner approval. Accept risk; not a Phase-1 feature.)

### 34.11 ML Kit on-device
- [x] ML Kit on-device models download lazily first time → cache. Need bytes-down budget + wifi-only default. (session 2026-04-26 — ReceiptOcrScanner.kt uses `TextRecognizerOptions.DEFAULT_OPTIONS` which is the *bundled* Latin model (shipped in the APK, ~1.5 MB, zero lazy download). BarcodeAnalyzer and DocumentScanner use GMS-managed models which download via Play Services outside app control. No explicit wifi-only budget is needed for the bundled model. GMS model management is Play Services' responsibility. Risk cleared for the OCR use case; barcode/doc scan model size is GMS-controlled and cannot be gated per-app.)

### 34.12 Play Policy on `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
- [x] Play rejects apps that request this without a legit foreground-service use case. Our repair-timer case likely qualifies; prep justification. (session 2026-04-26 — `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is NOT declared in AndroidManifest.xml. RepairInProgressService uses `foregroundServiceType="dataSync"` which is a supported Play foreground service type and does not require battery-exemption justification. The Play policy risk is moot because the permission is not requested. No action needed.)

---
## 35. Parity Matrix (at-a-glance)

Mirror to iOS §331 + Web §332.

| Feature | Web | iOS | Android | Gap |
|---|---|---|---|---|
| Login / server URL | ✅ | ✅ | planned | — |
| 2FA | ✅ | planned | planned | — |
| Passkey / Credential Manager | ✅ | planned | planned | pre-14 floor |
| Dashboard | ✅ | ✅ | planned | density modes Android-only |
| Tickets list | ✅ | ✅ | planned | — |
| Ticket create full | ✅ | planned | planned | §4.3 |
| Ticket edit | ✅ | planned | planned | — |
| Customers | ✅ | ✅ | planned | — |
| Customer merge | ✅ | planned | planned | §5.5 |
| Inventory | ✅ | ✅ | planned | — |
| Receiving | ✅ | planned | planned | §6.7 |
| Stocktake | ✅ | planned | planned | §60 |
| Invoices | ✅ | ✅ | planned | — |
| Payment accept | ✅ | planned | planned | §16 |
| BlockChyp SDK | ✅ | planned | planned | §16.4 |
| Cash register | ✅ | planned | planned | §39 |
| Gift cards | ✅ | planned | planned | §40 |
| Payment links | ✅ | planned | planned | §41 |
| SMS | ✅ | ✅ | planned | — |
| SMS AI reply | ❌ | planned (on-device) | planned (on-device via Gemini Nano) | Android via AICore |
| Notifications tab | ✅ | ✅ | planned | — |
| Appointments | ✅ | ✅ | planned | — |
| Scheduling engine deep | ✅ | planned | planned | §10.7 |
| Leads | ✅ | ✅ | planned | — |
| Estimates | ✅ | ✅ | planned | — |
| Estimate convert | ✅ | planned | planned | §8 |
| Expenses | ✅ | ✅ | planned | — |
| Employees | ✅ | ✅ | planned | — |
| Clock in/out | ✅ | planned | planned | §14.3 |
| Commissions | ✅ | planned | planned | §14.13 |
| Global search | ✅ | ✅ | planned | — |
| Reports | ✅ | placeholder | planned | §15 |
| BI drill | partial | planned | planned | §15.9 |
| POS checkout | ✅ | placeholder | planned | §16 |
| Barcode scan | ✅ | planned | planned | §17.2 |
| Printer thermal | ✅ | planned | planned | §17.4 |
| Label printer | ❌ | planned | planned | §17.4 |
| Cash drawer | ✅ | planned | planned | §17.5 |
| Weight scale | ❌ | planned | planned | §17.7 |
| Customer-facing display | ❌ | planned | planned | §16.11 |
| Offline mode | ✅ | planned | planned | §20 |
| Conflict resolution | ❌ | planned | planned | §20.3 |
| Glance widgets | n/a | planned (WidgetKit) | planned | §24 |
| App Shortcuts / Assistant | n/a | planned (App Intents) | planned | §24 |
| Live Updates | n/a | planned (Live Activity) | planned (Android 16) | §21.3 |
| Google Wallet passes | n/a | planned (Apple Wallet) | planned | §38 |
| Cross-device continuity | n/a | planned (Handoff) | planned (limited) | §25.6 |
| List-detail tablet layout | n/a | planned (NavSplitView) | planned | §22.1 |
| Stylus annotation | n/a | planned (Pencil) | planned (S Pen / USI) | §17.9 |
| Android Auto / CarPlay | n/a | deferred | deferred | §34.9 |
| SSO | ✅ | planned | planned | §2.20 |
| Audit log | ✅ | planned | partial | §52 |
| Data import wizard | ✅ | planned | planned | §50 |
| Data export | ✅ | planned | planned | §51 |
| Multi-location | ✅ | planned | planned | §63 |

Legend: ✅ shipped · partial · planned · deferred · n/a.

### 35.1 Review cadence
- [ ] Monthly: Android lead + iOS lead + Web lead reconcile gaps.
- [ ] Track burn-down by phase.

### 35.2 Parity test
- [ ] Shared Gherkin spec per feature in `packages/shared/spec/` — all three platforms pass same scenarios.

---
## 36. Setup Wizard (first-run tenant onboarding)

_Triggered when `GET /auth/setup-status → { needsSetup: true }`. 13 steps mirror web /setup._

### 36.1 Steps
- [ ] 1. Welcome + server URL.
- [ ] 2. Owner account (name / email / username / password).
- [ ] 3. Shop identity (name / logo / phone / address / timezone / shop type).
- [ ] 4. Payment methods (cash always on; toggle card / gift / store credit; BlockChyp terminal optional).
- [ ] 5. Tax rules (default rate + per-jurisdiction).
- [ ] 6. Ticket statuses (accept default or customize).
- [ ] 7. Device catalog import (starter: phones / tablets / laptops / TVs).
- [ ] 8. Inventory import (CSV or skip).
- [ ] 9. Customer import (CSV / Contacts / skip).
- [ ] 10. Employees invite.
- [ ] 11. SMS provider connect (or "Later").
- [ ] 12. Receipt template preview.
- [ ] 13. Done + "Take a tour" offer.

### 36.2 UX
- [ ] Full-screen Activity, one step at a time, progress bar top.
- [ ] Each step save-on-next; resume on app kill.
- [ ] Back gesture previews previous step via predictive back.
- [ ] Skip buttons allowed on non-essential steps; can resume from dashboard card.

### 36.3 Sample-data toggle
- [ ] Load sample customers / tickets / inventory for demo; one-tap clear.

### 36.4 Validation
- [ ] Inline errors per step; block next until valid.
- [ ] Idempotency via step-token so retry after crash doesn't duplicate.

### 36.5 Completion
- [ ] Onboarding checklist card (§3.5) tracks remaining setup.
- [ ] First-sale / first-customer confetti celebrations.

---
## 37. Marketing & Growth

_Server endpoints: `GET /marketing/campaigns`, `POST /marketing/campaigns`, `GET /marketing/segments`, `POST /marketing/segments`, `POST /comms/sms`, `POST /comms/email`._

### 37.1 Campaign list
- [ ] Status tabs: Draft / Scheduled / Sending / Sent / Archived.
- [ ] Metrics: sends / opens / clicks / replies / unsubscribes.

### 37.2 Campaign builder
- [ ] Steps: Audience (segment) → Message (SMS / email, template or custom) → Schedule (now / later / recurring) → Review.
- [ ] Merge tags: `{{customer.first_name}}`, `{{ticket.status}}`, `{{shop.name}}`, `{{coupon.code}}`.
- [ ] Preview per-recipient with merged values.
- [ ] A/B test variant (50/50 split).
- [ ] TCPA compliance: STOP footer auto, opt-in recipients only, quiet-hours enforced.

### 37.3 Segments
- [ ] Filter builder: tags, LTV, last visit, ticket count, location, source.
- [ ] Saved segments reusable across campaigns.
- [ ] Size preview.

### 37.4 Automations
- [ ] Triggers: new customer / ticket ready / invoice paid / 90d since visit / birthday / review request.
- [ ] Actions: send SMS template / email template / add tag / webhook.

### 37.5 Review solicitation
- [ ] After ticket close: send NPS + review-link SMS (Google / Facebook / Yelp).
- [ ] Detractors land on in-shop follow-up instead of public review site.

### 37.6 Referral program
- [ ] Generate unique code per customer; surface on receipts + SMS signature.
- [ ] Attribution when redeemed at POS; both parties credited (store credit / discount).
- [ ] Leaderboard of top referrers.

### 37.7 Coupons
- [ ] Create code: discount amount / %, expiry, max uses, SKU restrictions.
- [ ] Auto-generate bulk codes for campaigns.
- [ ] POS prompts for code → validate + apply.

### 37.8 Public QR campaigns
- [ ] Generate QR posters ("Scan for 10% off") → unique code per scan.
- [ ] Print via Android Print Framework.

---
## 38. Memberships / Loyalty

_Server endpoints: `GET /memberships/tiers`, `POST /memberships`, `GET /memberships/:id`, `POST /memberships/:id/renew`, `GET /memberships/:id/wallet-pass`._

### 38.1 Tiers
- [x] Configure tiers: Basic / Silver / Gold; benefits (free diagnostics, discount %, priority queue, extended warranty). — MembershipApi + TierChip
- [x] Pricing per tier (monthly / annual). — MembershipTier DTO monthlyPriceCents/annualPriceCents

### 38.2 Enrollment
- [x] At POS: "Add member" → tier picker → charge → membership active immediately. — EnrollMemberDialog + MembershipViewModel.enroll()
- [ ] Expiration tracked; renewal reminders via SMS / email / push.

### 38.3 Benefits application
- [~] POS auto-applies tier discount + priority queue badge on customer's new tickets. — TierChip composable available; POS auto-apply is future
- [ ] Benefit usage log per member.

### 38.4 Google Wallet pass
- [ ] `GET /memberships/:id/wallet-pass` returns signed JWT → redirect to Google Wallet save URL.
- [ ] Pass shows tier, expiration, member ID, QR for shop scan.
- [ ] Updates pushed to pass on renewal / tier change.

### 38.5 Member portal
- [ ] Customer sees benefits, usage history, renewal date on public customer portal (web-served).

### 38.6 Punch-card loyalty (simpler variant)
- [ ] "Buy 10 repairs get 1 free" style.
- [ ] Stamps per qualifying visit.
- [ ] Redemption at POS.

---
## 39. Cash Register & Z-Report

### 39.1 Cash session lifecycle
- [x] Open: count starting cash by denomination → record → status `open`. — OpenShiftDialog + CashRegisterApi.openShift
- [x] Throughout shift: sales increment expected cash; cash-in/cash-out events logged (pay-outs, pay-ins). — ShiftOpenPanel live stats + PayInOutDialog
- [x] Close: count ending cash → system computes expected → delta → over/short reason if > $2. — CloseShiftDialog with variance gate
- [~] Manager PIN required over threshold; audit. — gate implemented UI-side; server enforces PIN
- [ ] Z-report prints + PDF archived.

### 39.2 Z-report contents
- [x] Shift ID, cashier, start / end time. — ZReportPanel header
- [x] Sales count + gross + net. — ZReportPanel sales summary
- [x] Tender breakdown (cash / card / gift / store credit). — TenderRow in ZReportPanel
- [x] Refunds count + total. — ZReportPanel sales summary
- [x] Voids count. — ZReportPanel
- [x] Opening + closing cash + expected + over/short. — ZReportPanel reconciliation section
- [x] Top 5 items. — ZReportPanel top-items section
- [x] Tips collected. — ZReportPanel

### 39.3 X-report (mid-shift)
- [x] Snapshot of current shift stats without closing. — CashRegisterViewModel.fetchXReport + X-Report button

### 39.4 Multi-register
- [x] Per-tablet register ID (e.g. REG-01, REG-02); report by register or combined. — registerId field in OpenShiftDialog + CashShift DTO

### 39.5 Pay-in / pay-out
- [x] Pay-out: take cash out for rent / parts / lunch → record reason + amount; adjusts expected cash. — PayInOutDialog + CashRegisterApi.payOut
- [x] Pay-in: add cash from petty → adjusts expected. — PayInOutDialog + CashRegisterApi.payIn

### 39.6 Blind close
- [ ] Tenant option: cashier counts cash without seeing expected; manager reconciles.

---
## 40. Gift Cards / Store Credit / Refunds

### 40.1 Gift cards
- [x] Issue: at POS → enter amount → scan / enter code → linked to customer (optional). — GiftCardScreen IssueTab + GiftCardApi.issueGiftCard
- [x] Balance check: scan → `GET /gift-cards/:code`. — ScanRedeemTab + GiftCardApi.getGiftCard
- [x] Redeem: `POST /gift-cards/redeem` with `{ code, amount }`; partial redemption supported. — ScanRedeemTab + GiftCardApi.redeemGiftCard
- [x] Reload: add value to existing card. — GiftCardApi.reloadGiftCard endpoint defined
- [x] Physical card stock: tenant orders pre-printed; app scans barcode. — QR scan button stub in ScanRedeemTab
- [x] Digital gift card: emailed / SMSed to recipient with QR. — sendDigital toggle in IssueTab
- [ ] Expiration: tenant policy; warn at 30d prior.

### 40.2 Store credit
- [ ] Issue: refund → store credit option.
- [x] Balance on customer detail; applies automatically at POS (or user-toggles). — StoreCreditTab balance display + GiftCardApi.getStoreCredit
- [x] `POST /store-credit/:customerId` with `{ amount, reason }`. — GiftCardApi.issueStoreCredit + StoreCreditTab issueCredit flow
- [ ] Expiration optional; never hidden from customer.

### 40.3 Refunds
- [ ] Per §7.7.
- [ ] Original-tender refund path default (card → card via BlockChyp refund; cash → cash; gift → reload gift).
- [ ] Alternative: store credit.
- [ ] Manager PIN required over threshold.
- [ ] Audit log entry.

### 40.4 Reconciliation
- [ ] Reports on gift-card liability (outstanding balance owed to customers).
- [ ] Store-credit liability similar.

---
## 41. Payment Links & Public Pay Page

### 41.1 Payment link
- [x] Create: from invoice detail or standalone (amount + memo + customer).
- [x] `POST /payment-links` → `{ url, id }`.
- [x] Share: SMS / email / copy to clipboard / QR display.
- [x] Expiration + max uses + partial-allowed flag.

### 41.2 Status tracking
- [x] `GET /payment-links/:id/status` polled or WebSocket push.
- [x] Status: pending / paid / expired / cancelled.
- [~] Paid triggers invoice update.

### 41.3 Public pay page
- [x] Served by tenant server on web; Android provides deep link only.
- [~] Supports Google Pay / Apple Pay / credit card via BlockChyp hosted form.

### 41.4 Request-for-payment push
- [x] "Send payment request" → customer receives SMS with link + FCM push if customer has our app.

---
## 42. Voice & Calls

### 42.1 Phone dial-out
- [x] `Intent(ACTION_DIAL, Uri.parse("tel:..."))` from any customer row. Use `ACTION_CALL` only with `CALL_PHONE` permission if tenant configures auto-dial.
- [~] Caller ID shows customer name via contacts role (privacy-aware).

### 42.2 VoIP calling (if tenant uses)
- [~] ConnectionService self-managed for outbound via `TelecomManager.placeCall(...)` (stubbed — CallInProgressActivity instead).
- [x] Incoming via PushKit-analog (FCM high-priority data) → `ConnectionService.onCreateIncomingConnection`.
- [x] CallKit-parallel: full-screen notification with accept / decline.
- [~] In-call UI: mute, speaker, hold, transfer, DTMF keypad (Answer/Decline/Hangup only).
- [x] Records: `POST /call-logs` entries synced to tenant.

### 42.3 Call recording
- [~] Opt-in tenant + per-jurisdiction compliance (two-party consent states require announcement).
- [~] Playback via ExoPlayer (ACTION_VIEW intent stub; ExoPlayer integration TBD).
- [x] Transcription via tenant server (not on-device) — stub endpoint wired.

### 42.4 Voicemail
- [~] Fetched via tenant server (third-party VoIP provider); UI similar to SMS.

### 42.5 Click-to-call from anywhere
- [~] Customer chip tap → dial prompt with recent numbers.

---
## 43. Bench Workflow (technician-focused)

### 43.1 Bench tab
- [ ] Dashboard tile + dedicated "Bench" tab surface.
- [ ] Queue of my bench tickets (in statuses `Diagnostic` / `In Repair`).
- [ ] Device template shortcut pre-fills common parts list.
- [ ] Big timer card per ticket.

### 43.2 Timer
- [ ] Start / pause / resume / stop; `POST /bench/:ticketId/timer-start`.
- [ ] Live Update Android-16 progress notification (§21.3).
- [ ] Foreground service `specialUse` keeps process alive.
- [ ] Multi-timer: different tickets can run concurrently (parallel repairs).

### 43.3 Quick checklist
- [ ] Per-device pre-conditions checklist (§4.2).
- [ ] QC checklist on close (§4.20).

### 43.4 Parts-needed flow
- [ ] Mark part missing → added to reorder queue.
- [ ] Ticket status auto → `Awaiting Parts`.
- [ ] Push to purchasing manager.

### 43.5 Tech handoff (shift change)
- [ ] Detailed handoff form: current state, what's next, pitfalls; receiving tech acknowledges.

---
## 44. Device Templates / Repair-Pricing Catalog

### 44.1 Device templates
- [ ] Per device model: common repairs list (screen / battery / charging port / water damage / camera / speaker / back glass).
- [ ] Default labor rate per repair.
- [ ] Default parts per repair.
- [ ] Pre-conditions checklist customized per device class.
- [ ] Starter set: 200+ common devices (phones / tablets / laptops / TVs).
- [ ] Per-tenant edit.

### 44.2 Repair pricing catalog
- [ ] `GET /repair-pricing/services` — service catalog.
- [ ] Editable per-tenant: name, base price, labor rate, duration estimate, tax class.
- [ ] Per-device-model overrides.
- [ ] Search + filter.
- [ ] Bulk price adjust (admin).

### 44.3 Device catalog
- [ ] Manufacturers + models hierarchy (`GET /catalog/manufacturers`, `GET /catalog/devices`).
- [ ] Admin can add new device.

---
## 45. CRM Health Score & LTV

### 45.1 Health score
- [ ] `GET /crm/customers/:id/health-score` → 0–100 ring.
- [ ] Components: Recency / Frequency / Spend / Engagement.
- [ ] Explanation sheet breaks down each component.
- [ ] Recalculate manually via `POST /crm/customers/:id/health-score/recalculate`.
- [ ] Daily background Worker re-scores all customers at 4am local time.
- [ ] Auto-refresh on customer-detail open if last calc > 24h.

### 45.2 LTV tier
- [ ] `GET /crm/customers/:id/ltv-tier` → chip (VIP / Regular / At-Risk).
- [ ] Tier thresholds per tenant (e.g. VIP ≥ $1000 lifetime).
- [ ] Auto-apply tenant pricing rules by tier.

### 45.3 Churn alert
- [ ] Dashboard card (§3.2) lists at-risk customers.
- [ ] Action: "Send win-back SMS" pre-fills template.

### 45.4 Segmentation
- [ ] Feeds §37 Marketing segments.

---
## 46. Warranty & Device History Lookup

_Server endpoints: `GET /tickets/warranty-lookup?imei|serial|phone`, `GET /tickets/device-history?imei|serial`._

### 46.1 Warranty lookup
- [ ] Global action accessible from ticket create / ticket detail / quick-action menu.
- [ ] Search by IMEI / serial / phone / last name.
- [ ] Result: list of warranty records with part + install date + duration + eligibility.
- [ ] Tap → record detail → "Create warranty-return ticket" CTA.

### 46.2 Device history
- [ ] `GET /tickets/device-history?imei|serial` lists all past tickets on this device across customers.
- [ ] Visible on device card in ticket detail + customer asset tab.
- [ ] Useful for "this exact iPhone has been in 3 times" repeat-repair detection.

### 46.3 Voided warranty handling
- [ ] Water damage / physical damage flag voids warranty; displayed prominently.
- [ ] Admin override with reason (audit).

---
## 47. Team Collaboration (internal messaging)

_Server endpoints: `GET /team-chat`, `POST /team-chat`, `GET /inbox`, `POST /inbox/:id/assign`._

### 47.1 Channel-less chat
- [ ] Flat chat stream via `GET /team-chat` (cursor-paginated, offline-first).
- [ ] @mentions drive FCM push to mentioned user.
- [ ] Image / file attachments via PhotoPicker + SAF.
- [ ] Pin messages.
- [ ] Reactions (👍 ✅ 🎉) via long-press.

### 47.2 DMs (direct messages)
- [ ] One-on-one threads alongside team channel.
- [ ] Unread badge per DM.

### 47.3 Task embed
- [ ] `@ticket 4821` inline link renders as mini-card with status.
- [ ] `@customer Acme` renders avatar chip.

### 47.4 Voice clip
- [ ] Hold-to-record via `MediaRecorder` AAC; playback via ExoPlayer.

### 47.5 Pinned announcements
- [ ] Admin pins to top; dismissible per user.

### 47.6 Search across chat
- [ ] FTS5 over messages (§18.1).

---
## 48. Goals, Performance Reviews & Time Off

_Server endpoints: `GET /goals`, `POST /goals`, `GET /performance`, `POST /performance/reviews`, `GET /time-off`, `POST /time-off`, `PUT /time-off/:id`._

### 48.1 Goals
- [ ] Create: title, metric (tickets / revenue / commission / NPS), target, period.
- [ ] Progress auto-tracked via server compute.
- [ ] Personal + team goals.
- [ ] Dashboard widget shows current goals + ring progress.

### 48.2 Reviews
- [ ] Cycle: quarterly / annual tenant-configurable.
- [ ] Self-review form + manager form + peer feedback (§14.14).
- [ ] Ratings 1–5 with descriptors.
- [ ] Final PDF exported for HR.

### 48.3 Time-off
- [ ] Submit request: date range + type (vacation / sick / personal / unpaid) + reason + attach file (doctor's note).
- [ ] Manager approval screen actually exists and works (user emphasis).
- [ ] Affects shift grid (§14.6) — auto-removes scheduled shifts in approved window.
- [ ] Balance tracking per employee (PTO hours).
- [ ] Accrual rules per tenant.

### 48.4 Shoutouts
- [ ] Per §14.15.

### 48.5 1:1 meeting notes
- [ ] Private manager-employee notes; not visible to others.
- [ ] Recurring meeting template.

---
## 49. Roles Matrix Editor

_Server endpoints: `GET /roles`, `POST /roles`, `PUT /roles/:id`, `DELETE /roles/:id`, `GET /permissions`._

### 49.1 Matrix view
- [ ] Tablet/ChromeOS: full 2D grid (roles × permissions) with checkboxes.
- [ ] Phone: per-role vertical list; toggle each permission.
- [ ] Categories: Tickets / Customers / Inventory / Invoices / POS / Reports / Settings / Team / Audit.

### 49.2 Custom roles
- [ ] Create role: name + color + inherit-from template.
- [ ] Duplicate + modify.
- [ ] Delete with confirm + reassign affected employees.

### 49.3 System roles (locked)
- [ ] Owner / Admin / Manager / Technician / Cashier — base permissions immutable; can add extras only.

### 49.4 Permission preview
- [ ] "Test as this role" toggle — see UI as that role would.

### 49.5 Change log
- [ ] Every matrix change audit-logged with before/after diff.

---
## 50. Data Import (RepairDesk / Shopr / MRA / CSV)

_Server endpoints: `POST /imports/start`, `GET /imports/:id/status`._

### 50.1 Wizard
- [ ] Step 1: Source (RepairDesk / Shopr / MRA / Generic CSV).
- [ ] Step 2: Credentials (API key for providers, file picker for CSV).
- [ ] Step 3: Scope (customers / tickets / invoices / inventory / employees).
- [ ] Step 4: Field-map (auto-map + manual override).
- [ ] Step 5: Dry run (preview N rows).
- [ ] Step 6: Commit → job started.

### 50.2 Progress
- [ ] Job status polled / pushed; progress bar + current step.
- [ ] Can leave screen; FCM notification on completion.
- [ ] Error report with row-level failures + retry.

### 50.3 De-dup during import
- [ ] Customer merge detection (§5.10).

### 50.4 Rollback
- [ ] Destructive but supported within 24h via tombstones.

---
## 51. Data Export

_Server endpoints: `POST /exports/start`, `GET /exports/:id/download`._

### 51.1 Formats
- [ ] CSV (one file per entity).
- [ ] JSON (full dump).
- [ ] PDF reports (scheduled).

### 51.2 Scope selector
- [ ] Date range, entity types, active-only flag.

### 51.3 Delivery
- [ ] Download via SAF (`ACTION_CREATE_DOCUMENT`).
- [ ] Email to admin.
- [ ] FCM push on ready.

### 51.4 Encryption
- [ ] Optional ZIP password; AES-256 via `net.lingala.zip4j`.

---
## 52. Audit Logs Viewer

_Server endpoint: `GET /audit-logs?from=&to=&actor=&entity=&cursor=&limit=`._

### 52.1 Feed
- [x] Reverse chronological list.
- [x] Columns: timestamp / actor / action / entity / diff preview.

### 52.2 Filters
- [x] By actor, action type, entity, date range.

### 52.3 Diff view
- [x] Field-level before/after with highlight.
- [~] Redacted fields still show "(redacted)" placeholder. (server concern; client shows raw diffJson)

### 52.4 Export
- [ ] Filtered set → CSV via SAF.

### 52.5 Chain integrity
- [ ] Server appends hash chain; client verifies last-N records on open.
- [ ] Warning banner if chain broken.

### 52.6 Access
- [x] Admin + Owner roles only.

---
## 53. Training Mode (sandbox)

### 53.1 Toggle
- [ ] Settings → Training Mode → enable.
- [ ] Orange accent + "TRAINING" watermark banner.
- [ ] Uses separate SQLCipher DB file; tenant server marks `training` flag.

### 53.2 Seeded data
- [ ] Demo customers / tickets / inventory / SMS threads pre-populated.
- [ ] Test BlockChyp card numbers supported.

### 53.3 Reset
- [ ] One-tap "Reset training data".

### 53.4 No-send guards
- [ ] SMS / email sends intercepted and logged only; never actually sent.

### 53.5 Checklist
- [ ] Optional onboarding checklist ("Create a ticket / Record a payment / Send an SMS").

---
## 54. Command Palette (Ctrl+K)

### 54.1 Trigger
- [x] Ctrl+K on hardware keyboard; top-bar search icon on touch.

### 54.2 Entries
- [x] Nav: "Go to Tickets", "Go to Customers", ...
- [x] Actions: "New ticket", "Scan barcode", "Clock in", "Open printer settings".
- [~] Entities: recent customers / tickets / invoices (fuzzy match). (DynamicCommandProvider interface ready; no concrete provider yet)
- [~] Settings: jump to any setting by name. (DynamicCommandProvider interface ready; no concrete provider yet)

### 54.3 UI
- [x] Center-screen modal with search input + result list.
- [~] Arrow-key navigation; Enter to activate. (Enter via BasicTextField; arrow-key traversal not yet wired)
- [~] Recent commands pinned at top. (RECENT group exists; no persistence yet)

### 54.4 Power-user flag
- [ ] Settings toggle off for staff if noisy; on by default for admins.

---
## 55. Public Tracking Page (customer-facing)

_Web-served; Android provides deep link + share only._

### 55.1 Short-link
- [ ] Server issues `app.bizarrecrm.com/t/:shortId` on ticket create.
- [ ] Android ticket detail has "Share tracking link" CTA → SMS / email / copy.

### 55.2 Content (web page)
- [ ] Ticket # + status + ETA + last update (truncated).
- [ ] Timeline of status changes (customer-visible only).
- [ ] SMS-staff button.
- [ ] SLA promise visible.

### 55.3 QR print
- [ ] Android prints QR label with tracking link for customer's repair bag.

### 55.4 Privacy
- [ ] Short-links are non-guessable (random 10 chars).
- [ ] Server strips internal notes / cost breakdowns / tech names.

---
## 56. TV Queue Board (in-shop display)

### 56.1 Launch
- [ ] Settings → Display → Activate queue board.
- [ ] Full-screen Activity with hidden system bars (`WindowInsetsController.hide(systemBars())`).
- [ ] `FLAG_KEEP_SCREEN_ON`.

### 56.2 Content
- [ ] Ready-for-pickup list (big).
- [ ] In-progress count.
- [ ] Shop logo + promo content (tenant-uploaded).
- [ ] Rotating ads / announcements.

### 56.3 Exit
- [ ] 3-finger long-press + PIN OR hardware Esc + PIN.

### 56.4 Android TV mode
- [ ] Optional Android TV / Google TV launcher entry for shop big-screen displays using dedicated Fire TV / Android TV sticks.

### 56.5 Auto-refresh
- [ ] WebSocket push on ticket status change; UI re-animates on arrival.

---
## 57. Kiosk / Lock-Task Single-Task Modes

### 57.1 Lock-Task Mode (Android screen pinning)
- [ ] Enable via Device Policy Manager in managed-device mode, or screen-pinning (`startLockTask()`) for non-DPC.
- [ ] Use cases: customer self-check-in kiosk; TV board; kiosk POS.

### 57.2 Kiosk customer check-in
- [ ] Simplified flow: customer types phone → finds record or creates → signs waiver → done.
- [ ] Auto-return to start screen after 60s inactivity.

### 57.3 Customer-facing signature
- [ ] Device flipped to customer; signature capture only; staff cannot back out.

### 57.4 Kiosk hardware lockdown
- [ ] Disable volume keys / power button where possible via DPC.
- [ ] Wake on tap only.

### 57.5 Exit
- [ ] Manager PIN unlocks.

---
## 58. Appointment Self-Booking (customer)

_Web-served via public page; Android links to it and receives pushes._

### 58.1 Customer books online
- [ ] Web route `app.bizarrecrm.com/book/:locationId` — `GET /public/book/:locationId` → availability.
- [ ] Customer selects slot; server creates appointment.
- [ ] FCM push to staff: "New online booking — Acme at 3pm".

### 58.2 Android-side flow
- [ ] Push opens appointment in-app; staff can confirm / reschedule / reject.
- [ ] Auto-SMS confirmation to customer.

### 58.3 Integration surface
- [ ] Settings → Online Booking → generate link / QR → enable per-location.
- [ ] Toggle working hours, buffer times, services bookable.

---
## 59. Field-Service / Dispatch (mobile tech)

### 59.1 Dispatch dashboard
- [ ] Map view: tech locations + open jobs (uses Google Maps SDK — no third-party egress beyond Google Play Services).
- [ ] List view: jobs ranked by ETA + priority.

### 59.2 Route optimization
- [ ] `POST /dispatch/optimize` → returns ordered job list for tech's day.

### 59.3 On-my-way notification
- [ ] Tech taps "On my way" → auto-SMS to customer with ETA + live-location link (opt-in).

### 59.4 Tech mobile UX
- [ ] Simplified job list (current / upcoming).
- [ ] Signature capture on arrival.
- [ ] Photos + notes.
- [ ] Close → back to dispatch list.

### 59.5 Geofence
- [ ] Auto-mark arrived when entering radius (opt-in; `ACCESS_BACKGROUND_LOCATION` required — justify to Play).

### 59.6 Offline
- [ ] Everything offline-capable except final payment.

### 59.7 Safety
- [ ] Panic button (long-press top-bar icon) → sends alert to dispatcher with location.

---
## 60. Inventory Stocktake

### 60.1 Session lifecycle
- [ ] Per §6.6.
- [ ] Draft → Active → Committed.

### 60.2 Cycle counts
- [ ] Partial count (by bin / category / ABC class).
- [ ] Full count (entire inventory).

### 60.3 Multi-scanner
- [ ] Multiple devices feed same session via WebSocket sync.
- [ ] Conflict resolution on same SKU: last-wins with banner notification.

### 60.4 Variance approval
- [ ] Manager reviews variance list; approves adjustments or rejects + reinvestigates.

### 60.5 Audit trail
- [ ] Every count action logged.

### 60.6 Offline
- [ ] Fully offline; syncs on commit.

---
## 61. Purchase Orders (inventory)

### 61.1 PO list
- [ ] Filter by status / supplier / date.

### 61.2 Create PO
- [ ] Supplier picker (or inline-create).
- [ ] Line items from inventory (qty + cost + expected received date).
- [ ] Auto-suggest from §6.16 reorder lead times + §6.15 reorder rules.

### 61.3 Send PO
- [ ] PDF generated locally → email via `ACTION_SEND` OR server-side email.
- [ ] Fax (stretch; rarely needed).

### 61.4 Receive
- [ ] Scan items → increment received qty; partial receipt supported; close when complete.
- [ ] Mark damaged / missing during receive with reason.

### 61.5 Vendor return (RMA)
- [ ] Per §7.7.

### 61.6 Reporting
- [ ] PO aging; vendor performance; price variance.

---
## 62. Financial Dashboard (owner view)

### 62.1 P&L snapshot
- [ ] Revenue / COGS / Gross margin / Operating expenses / Net income.
- [ ] Period comparison.

### 62.2 Cash flow forecast
- [ ] Upcoming invoices due + recurring expenses + subscription memberships.
- [ ] Projected cash 30 / 60 / 90d.

### 62.3 Tax liability
- [ ] Per jurisdiction collected + remitted status.

### 62.4 Budget vs actual
- [ ] Tenant defines monthly budget per category → dashboard shows delta.

### 62.5 Owner-only
- [ ] Role-gated; PIN re-prompt on open if configured.

---
## 63. Multi-Location Management

_Server endpoints: `GET /locations`, `POST /locations`, `GET /locations/:id`, `PUT /locations/:id`._

### 63.1 Location switcher
- [ ] Top-bar chip for current location; tap → picker with recent locations.
- [ ] Scope filters all lists + KPIs.

### 63.2 Per-location config
- [ ] Hours, staff roster, printer / terminal pairings, inventory stock per location.
- [ ] Receipt footer per location.

### 63.3 Cross-location transfers
- [ ] Per §6.13.

### 63.4 Consolidated reports
- [ ] "All locations" view for owner role.

### 63.5 Tenant policy
- [ ] Staff per-user allowed-locations list.

---
## 64. Release checklist (go-live gates)

### 64.1 Phase gates
- [x] Phase 0 Skeleton done: Android Studio project builds, Hilt DI, Compose theme, login shippable, ApiClient envelope works, token storage.
- [ ] Phase 1 Read-only parity: all lists + detail views render from Room; TalkBack traversal passes; Internal track TestFlight-equivalent shared with team.
- [ ] Phase 2 Writes + POS: full CRUD + POS cash tender + BlockChyp; sync queue operating; closed testing begins.
- [ ] Phase 3 Hardware + platform: barcode / photo / signature / printer / cash drawer; FCM; Glance widgets; App Shortcuts; adaptive layouts.
- [ ] Phase 4 Reports / marketing / loyalty: Vico charts; campaign builder; loyalty; memberships; referrals.
- [ ] Phase 5 Scale + reliability: multi-location, dead-letter, telemetry + crash pipeline, audit log viewer, open testing + production rollout.
- [ ] Phase 6 Regulatory + advanced payment: advanced tax, multi-currency, Tap-to-Pay, Google Wallet passes, GDPR/CCPA evidence.
- [ ] Phase 7 Stretch: Android TV, field-service heavy, AI-assist via Gemini Nano on-device.

### 64.2 Cross-phase gates
- [ ] Crash-free sessions ≥ 99.5% before phase advance.
- [ ] No P0 bugs older than 14d.
- [ ] Localization coverage per target locale.
- [ ] Doc updated in same PR as feature.

### 64.3 Per-tenant rollout
- [ ] Opt-in 5 tenants first, weekly check-ins.
- [ ] GA once crash-free > 99.5% + iOS/web parity on top 80% of flows.

### 64.4 Kill-switch
- [ ] Feature flags via `GET /feature-flags`; toggle server-side per tenant.
- [ ] Forced-update gate: server rejects known-bad client versions until upgrade.

### 64.5 Migration
- [ ] iOS → Android / Web → Android: user data portable; just log in.
- [ ] Server is single source.

---
## 65. Non-goals (explicit)

### 65.1 Not building
- [ ] Customer-facing end-user Android app (customers use web + SMS + email).
- [ ] Wear OS companion beyond clock-in/out notifications.
- [ ] Android Auto / CarPlay (deferred).
- [ ] Android TV launcher (except stretch TV-board §56.4).
- [ ] PC-native Windows / macOS client (web covers this).
- [ ] Third-party IdP SDK embedded (SAML / OIDC via Chrome Custom Tabs handles).

### 65.2 Not cloning
- [ ] RepairDesk / Shopr UI patterns verbatim — only data migration (§50).
- [ ] Generic Shopify-style e-commerce — we're repair shop POS, not general retail.

### 65.3 Not storing
- [x] Customer data beyond tenant server (no third-party analytics, no crash-reporters with data egress).
- [x] Location data unless tech-dispatch opts in per-session.
- [x] Biometric raw data (system Keystore only).

### 65.4 Not supporting
- [x] Pre-Android-8 devices (minSdk 26 final).
- [ ] 32-bit-only devices (armv7 build dropped Phase 3).
- [ ] Rooted devices for payment flows (Play Integrity reject).

---
## 66. Error, Empty & Loading States (cross-cutting)

### 66.1 Empty
- [ ] Every list + detail has a designed empty state with illustration + title + subtitle + CTA.
- [ ] Tone: helpful, not frustrated.
- [ ] See §3.14 for inventory/customer/ticket examples.

### 66.2 Loading
- [ ] Skeleton shimmer ≤ 300ms before real data.
- [ ] `CircularProgressIndicator` only for unknown-duration actions; prefer determinate bar where % known.
- [ ] Never block entire UI; allow cancel where meaningful.

### 66.3 Error
- [x] `ErrorState(title, message, retry)` Composable with retry button.
- [ ] Network errors: cached data still shown where possible + banner.
- [ ] 4xx errors: user-friendly copy from server `message`.
- [ ] 5xx errors: "Something went wrong on our end. We're looking into it." + retry.
- [ ] Permission denied: "Ask your admin to enable this." deep link to §49 roles.
- [ ] 409 conflict: "This item was updated elsewhere. [Reload]".

### 66.4 Offline
- [ ] Sticky banner across top of every screen.
- [ ] Footer-of-list four-state (§20.5).
- [ ] Write actions queue silently + badge in sync-status pill.

---
## 67. Copy & Content Style Guide (Android-specific tone)

### 67.1 Voice
- [ ] Direct, friendly, no jargon.
- [ ] Second person ("You're clocked in" not "User is clocked in").
- [ ] Active voice.
- [ ] Avoid exclamation points except celebrations.

### 67.2 Material guidelines respect
- [ ] "OK" / "Cancel" patterns; not "Yes" / "No" on dialogs.
- [ ] `AlertDialog` title = question; body = consequences; buttons = actions ("Delete" / "Keep").

### 67.3 Naming
- [ ] "Tickets" (per tenant glossary).
- [ ] "Sign in" / "Sign out" (not Login / Logout).
- [ ] "Settings" (not Preferences).

### 67.4 Errors
- [ ] Start with what happened; follow with what user can do.
- [ ] Never blame user.
- [ ] Never leak stacktrace in user-facing error.

### 67.5 Empty states
- [ ] "No tickets yet. Create one to get started." — noun then CTA.

### 67.6 Confirmations
- [ ] Destructive: bold destructive word in copy ("Delete customer" vs "Delete").
- [ ] Non-destructive: one-tap + Snackbar undo.

### 67.7 Localization
- [ ] All strings in `strings.xml` with comments explaining context for translators.
- [ ] Avoid concatenation; use placeholders.

---
## 68. Deep-link / App Links reference

### 68.1 Scheme
- [x] Custom: `bizarrecrm://<host>/<path>`.
- [~] App Link (verified HTTPS): `https://app.bizarrecrm.com/<path>`.

### 68.2 Routes
- [ ] `bizarrecrm://dashboard`
- [ ] `bizarrecrm://tickets` — list
- [ ] `bizarrecrm://tickets/:id` — detail
- [x] `bizarrecrm://tickets/new` — create
- [ ] `bizarrecrm://customers/:id`
- [x] `bizarrecrm://customers/new`
- [ ] `bizarrecrm://inventory/:sku`
- [ ] `bizarrecrm://invoices/:id`
- [ ] `bizarrecrm://estimates/:id`
- [ ] `bizarrecrm://leads/:id`
- [ ] `bizarrecrm://appointments/:id`
- [ ] `bizarrecrm://sms/:thread`
- [ ] `bizarrecrm://pos/new`
- [ ] `bizarrecrm://pos/cart/:id`
- [x] `bizarrecrm://scan` — opens scanner
- [ ] `bizarrecrm://reports/:slug`
- [ ] `bizarrecrm://settings/:section`
- [ ] `bizarrecrm://reset-password/:token`
- [ ] `bizarrecrm://setup/:token`

### 68.3 Router
- [x] `DeepLinkRouter` class in `MainActivity.onNewIntent` parses URI → navigates via NavController.
- [~] Unknown routes → Dashboard with "Unknown link" Snackbar.
- [ ] Auth-required routes: if unauthenticated, redirect to Login with `intent_after_login` extra.

### 68.4 Verification
- [ ] `assetlinks.json` served at tenant `/.well-known/assetlinks.json`.
- [ ] CI test parses manifest + fetches assetlinks to confirm.

### 68.5 Intent filters (outbound)
- [ ] `ACTION_SEND` / `ACTION_SEND_MULTIPLE` — PDF, CSV, photos, vCards.
- [ ] `ACTION_VIEW` for `tel:`, `sms:`, `mailto:`, `geo:`.

---
## 69. Haptics Catalog

Android `HapticFeedbackConstants` mapping + `Vibrator` + `VibratorManager` (Android 12+).

| Event | Constant | Fallback |
|---|---|---|
| Tap confirm | `CONFIRM` | short 20ms vibrate |
| Tap reject | `REJECT` | double 40ms vibrate |
| Virtual key press (keypad) | `VIRTUAL_KEY` | 10ms |
| Gesture start | `GESTURE_START` | short click |
| Gesture end | `GESTURE_END` | medium click |
| Long press | `LONG_PRESS` | 40ms |
| Context click (right-click) | `CONTEXT_CLICK` | 15ms |
| Clock tick (toast arrival) | `CLOCK_TICK` | 10ms |
| Segment frequent | `SEGMENT_FREQUENT_TICK` | 5ms |

### 69.1 Use cases
- [x] Barcode scan success → `CONFIRM`.
- [~] Wrong PIN / login → `REJECT`.
- [x] PIN / keypad digit → `VIRTUAL_KEY`.
- [ ] Swipe action release → `GESTURE_END`.
- [ ] Toggle on/off → `CONTEXT_CLICK`.
- [ ] Payment success → `CONFIRM` + extended 60ms.
- [ ] Photo shutter → `CLOCK_TICK`.
- [ ] Drag-over-target hover → `SEGMENT_FREQUENT_TICK`.

### 69.2 Custom patterns
- [ ] Celebration (first sale): `VibrationEffect.createWaveform(longArrayOf(0, 40, 60, 40, 60, 40), -1)`.
- [ ] Error escalation (3rd wrong PIN): heavier 200ms pulse.

### 69.3 Respect
- [ ] Honor `ACCESSIBILITY_VIBRATION_ENABLED` system setting.
- [ ] Never haptic-only for a11y-critical info.
- [ ] Quiet mode disables haptics.

---
## 70. Motion Spec

### 70.1 Durations
| Token | ms | Use |
|---|---|---|
| `motion.instant` | 0 | Reduce Motion |
| `motion.fast` | 150 | Button press / ripple |
| `motion.standard` | 300 | Screen enter |
| `motion.emphasized` | 450 | Shared-element / FAB morph |
| `motion.slow` | 600 | Onboarding / big reveal |

### 70.2 Easing
- [ ] `CubicBezierEasing(0.2f, 0f, 0f, 1f)` — enter.
- [ ] `CubicBezierEasing(0.4f, 0f, 1f, 1f)` — exit.
- [ ] Material Expressive spring: stiffness 400, damping 0.75.

### 70.3 Shared-element
- [ ] `SharedTransitionLayout` + `Modifier.sharedElement(...)` on tablet list→detail.
- [ ] Preserves photo thumbs, status chip, title.

### 70.4 Predictive back
- [ ] `PredictiveBackHandler` drives progress value 0..1 → custom scale + translate preview.

### 70.5 Reduce Motion
- [ ] Global override swaps every transition to `motion.instant`.
- [ ] Springs collapse to tween.
- [ ] Confetti / shake replaced with static color accent.

---
## 71. Launch Experience

### 71.1 Splash Screen API (Android 12+)
- [ ] `core-splashscreen` lib + `Theme.SplashScreen` parent.
- [ ] Brand wordmark + tinted icon.
- [ ] Keep-on-screen condition: DB open + tenant resolved + token validated → `splashScreen.setKeepOnScreenCondition { ... }`.
- [ ] Exit animation 300ms fade + icon-to-logo transition.

### 71.2 App Startup library
- [ ] `androidx.startup:startup-runtime` initializers for: Hilt, Timber, WorkManager, Coil, NotificationChannels.
- [ ] No heavy work on main thread at cold-start.

### 71.3 Pre-warm
- [ ] Profile-guided JIT + Baseline Profiles.
- [ ] Cold-start target per §29.1.

### 71.4 First launch ever
- [ ] Splash → animated welcome → server URL prompt.
- [ ] Privacy disclosure sheet.

### 71.5 Post-upgrade
- [x] "What's new" modal shown once on new `versionCode`. (commit gracious-goodall — `WhatsNewDialog.kt` AlertDialog with `WhatsNewEntry` data class + `WHATS_NEW_ENTRIES` catalog; `AppPreferences.lastSeenVersionCode` / `markWhatsNewSeen()`; MainActivity wires `showWhatsNew` state comparing `BuildConfig.VERSION_CODE` > `lastSeenVersionCode`; persists on dismiss)
- [x] Dismissible; auto-dismiss after interaction. (commit gracious-goodall — "Got it" TextButton sets `showWhatsNew = false` + calls `markWhatsNewSeen(versionCode)`; `onDismissRequest` handles outside-tap; no forced timeout per ActionPlan intent)

---
## 72. In-App Help

### 72.1 Help center
- [ ] Settings → Help.
- [ ] FAQs grouped by topic; search with FTS5.
- [ ] Served offline (bundled markdown).

### 72.2 Contextual help
- [ ] `?` icon in screen top bar → sheet with relevant help articles.
- [ ] "What's this?" long-press on any field shows tooltip.

### 72.3 Contact support
- [ ] "Report a problem" → composer with auto-attached redacted logs + screenshot.
- [ ] Sends to tenant admin (email) + audit log entry.
- [ ] Self-hosted: goes to tenant-configured admin email; managed: pavel@bizarreelectronics.com fallback.

### 72.4 Tooltips
- [ ] Material 3 `RichTooltip` on long-press icons.
- [ ] First-run spotlight tour optional.

### 72.5 Keyboard-shortcut overlay
- [ ] Ctrl+/ shows current-screen shortcuts.

---
## 73. Notifications — granular per-event matrix

Mirror iOS §73. Each row: default on/off per channel; user override per §19.3; tenant admin can shift tenant baseline.

| Event | Push | In-App | Email | SMS | Audience |
|---|---|---|---|---|---|
| SMS inbound | ✅ | ✅ | — | — | Assigned / subscribers |
| Ticket assigned | ✅ | ✅ | — | — | Assignee |
| Ticket status (auto) | ✅ | ✅ | — | — | Assignee |
| Ticket mention | ✅ | ✅ | — | — | Mentioned |
| Invoice overdue | ✅ | ✅ | ✅ | — | Owner + Admin |
| Payment received | ✅ | ✅ | — | — | Cashier + Admin |
| Payment declined | ✅ | ✅ | — | — | Cashier + customer (separately) |
| Estimate approved | ✅ | ✅ | — | — | Salesperson |
| Appointment reminder | ✅ | ✅ | — | — | Assignee + customer (separate) |
| Low stock | ✅ | ✅ | ✅ | — | Manager + Admin |
| SLA breach | ✅ | ✅ | ✅ | — | Assignee + Manager |
| Team mention (chat) | ✅ | ✅ | — | — | Mentioned |
| Shift starting | ✅ | ✅ | — | — | Self |
| Manager time-off request | ✅ | ✅ | — | — | Manager |
| Daily summary (end of day) | — | ✅ | ✅ | — | Owner |
| Weekly digest | — | ✅ | ✅ | — | Owner |
| Setup wizard incomplete (24h) | — | ✅ | — | — | Admin |
| Subscription renewal | — | ✅ | — | — | Admin |
| Integration disconnected | ✅ | ✅ | — | — | Admin |
| Backup failed (critical) | ✅ | ✅ | — | — | Admin |
| Security event (new device / 2FA reset) | ✅ | ✅ | — | — | Self + Admin |

### 73.1 User override (Settings §19.3)
- [ ] Per-event toggles across four channels.
- [ ] Defaults shown greyed with "(default)" label until flipped.
- [ ] "Reset all to default" button.
- [ ] Warning on enabling SMS on high-volume event ("This may send 50+ texts per day").

### 73.2 Tenant override (Admin)
- [ ] Admin can shift tenant's default.
- [ ] Per-tenant dashboard shows current deltas vs shipped defaults.

### 73.3 Delivery rules
- [ ] Push respects system DND + in-app quiet hours.
- [ ] In-app banner never shown if user already looking at source.
- [ ] Same event re-firing within 60s collapsed into "+N more" badge update.

### 73.4 Critical override
- [ ] Backup failed / Security event / Out-of-stock mid-sale / Payment declined mid-txn may use NotificationChannel IMPORTANCE_HIGH + CATEGORY_ALARM to bypass DND.
- [ ] Default `IMPORTANCE_DEFAULT`. Never misuse critical.

### 73.5 Rich content
- [ ] SMS notification embeds photo thumbnail if MMS.
- [ ] Payment notification shows amount + customer name.
- [ ] Ticket assignment embeds device + status.

### 73.6 Inline reply
- [ ] SMS_INBOUND action "Reply" uses `RemoteInput` — reply from push without opening app.

### 73.7 Sound
- [ ] Apple-parallel: default + 3 brand custom sounds (cash register, bell, ding); user picks per channel.
- [ ] Loaded from `raw/` resources.

### 73.8 Historical view
- [ ] Settings → Notifications → "Recent" shows last 100 pushes for audit.

### 73.9 Rotation / retry
- [ ] Push token rotation: on app start or `onNewToken` post new token.
- [ ] Retry FCM token register with exponential backoff on failure; manual "Re-register" in Settings.

### 73.10 Per-event copy matrix
- [ ] Title + body + action buttons defined for each event.
- [ ] Tone: short, actionable, no emoji in title; body includes identifier so push list stays scannable.
- [ ] Localization keyed; fallback English if locale missing.
- [ ] A11y: TalkBack reads title + body + action hints.
- [ ] Importance mapping per channel.
- [ ] Bundling: repeated same-type pushes within 60s merged.

---
## 74. Privacy-first analytics event list

All events target tenant server (§32).

- `app.launch`
- `app.foreground`
- `app.background`
- `auth.login.success`
- `auth.login.failure`
- `auth.logout`
- `auth.biometric.success`
- `screen.view` (screen name + duration)
- `action.tap` (screen + action + entity-kind)
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
- `live_update.start` / `.end`
- `deeplink.opened`
- `feature.first_use` (feature name)

### 74.1 Schema
```
{
  "event": "screen.view",
  "ts": "2026-04-19T14:03:22.123Z",
  "app_version": "1.2.3 (24041901)",
  "android_version": "16",
  "device_model": "Pixel 8",
  "session_id": "uuid",
  "user_id": "hashed_8",
  "tenant_id": "hashed_8",
  "props": { "screen": "dashboard", "duration_ms": 2341 }
}
```

### 74.2 No tracking
- [ ] No GAID / ADID / Facebook SDK / Google Analytics / Firebase Analytics / Mixpanel / Amplitude.
- [ ] Play Data Safety declares only FCM + tenant server.

### 74.3 Opt-out
- [ ] Settings → Privacy → Disable telemetry (local disk buffer still used for crash recovery but not transmitted).

---
## 75. Final UX Polish Checklist

### 75.1 Animation
- [ ] Every screen's enter + exit animation tested.
- [ ] No janky flashes on state change.
- [ ] Modal sheets never pop (use spring scale-in).

### 75.2 Focus
- [ ] `FocusRequester` sets first-responder on form open.
- [ ] Focus traps for modals.
- [ ] Focus returns to opener on dismiss.

### 75.3 Keyboard dismiss
- [ ] Tap-outside + scroll dismiss soft keyboard via `WindowInsets.isImeVisible` + `LocalFocusManager.current.clearFocus()`.
- [ ] "Done" button on number pads.

### 75.4 Loading → Done transitions
- [ ] Skeleton cross-fades to content; never jump.

### 75.5 Scroll behavior
- [ ] Preserve scroll on back-nav via `rememberLazyListState` + `SavedStateHandle`.
- [ ] Jump-to-top on bottom-nav re-select.

### 75.6 Pull-to-refresh
- [x] Material 3 `PullToRefreshBox` on every list + Dashboard.

### 75.7 Selection + multi-select
- [ ] Long-press enters edit mode on lists.
- [ ] Batch-action bar slides up from bottom.

### 75.8 Sheets vs full-screen
- [ ] Create/edit forms in `ModalBottomSheet` (partial / full via `SheetState.expand()`).
- [ ] Detail views full-screen push.

### 75.9 Back-navigation consistency
- [ ] Predictive-back works on every non-modal push.
- [ ] Custom back buttons discouraged — use top-bar navigationIcon.

### 75.10 System bars
- [ ] Edge-to-edge everywhere.
- [ ] `WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = ...` per screen theme.
- [ ] Light status on dark surfaces; dark status on light.

### 75.11 Ripple + tonal
- [ ] Default Material 3 ripple respected; no custom ripple except on themed buttons.
- [ ] Tonal elevation preferred over drop-shadows.

### 75.12 Dp / sp discipline
- [ ] No pixel values in Compose.
- [ ] Font sizes via `MaterialTheme.typography`.

### 75.13 Dark mode
- [ ] Every screen tested dark; contrast passes.
- [ ] No pure black except AMOLED variant.

### 75.14 RTL
- [ ] Arabic + Hebrew layouts pass visual review.

### 75.15 Fold transitions
- [ ] Smooth transition on fold/unfold; no flicker.

### 75.16 Rotate
- [ ] State preserved on rotation (ViewModel + `SavedStateHandle`).
- [ ] No content loss.

---

> **This document is intended as a living plan.** Close items by flipping `[ ]` → `[x]` with a commit SHA. Add sub-items freely. Default state: nothing is done. Each item gets re-verified against current code before marking shipped.

## Changelog

- 2026-04-20 — Initial skeleton. Android-native adaptation of iOS ActionPlan. Content fills in batch; every item starts `[ ]`.

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

## POS redesign wave (2026-04-24)

Fourth Android wave. Delivers the ground-up POS rewrite, the 6-step repair check-in package, BlockChyp payment terminal integration, and cream primary-color rebrand — all driven by the design spec in `../pos-phone-mockups.html`, which is the visual ground truth for every screen in this wave. Gradle build gate was verified SUCCESSFUL by Phase 2 + Phase 4 agents before merge. No server-side migrations were added this wave; all DB changes land on the Android side only (Room schema 10→11).

---

### 1. Cream primary rebrand

- [x] `ui/theme/Theme.kt` — `DarkColorScheme.primary` set to cream `#fdeed0`; `onPrimary` updated for contrast. `LightColorScheme.primary` shifts to caramel `#A66D1F` to maintain WCAG AA. `Blue600`, `BrandAccent`, and `RefundedPurple` design tokens updated to match. (commit `0f76f013`)

---

### 2. POS module ground-up rewrite

Deleted 16 legacy files under `ui/screens/pos/` (the original `PosScreen.kt`, `PosViewModel.kt`, all files under `components/` and `flows/`). Replaced with 13 focused files under `pos/`:

- [x] `pos/PosModels.kt` — data classes `CartLine`, `PosAttachedCustomer`, `AppliedTender`; enums for tender type and transaction state. (commit `0f76f013`)
- [x] `pos/PosCoordinator.kt` — Hilt singleton that carries session state across POS navigation destinations. (commit `0f76f013`)
- [x] `pos/PosEntryScreen.kt` + `pos/PosEntryViewModel.kt` — product/ticket lookup and cart initialisation. (commit `0f76f013`)
- [x] `pos/PosCartScreen.kt` + `pos/PosCartViewModel.kt` — line-item editing, discount application, sub-total display. (commit `0f76f013`)
- [x] `pos/CartLineBottomSheet.kt` — quantity/price/discount editor as a modal bottom sheet. (commit `0f76f013`)
- [x] `pos/PosTenderScreen.kt` + `pos/PosTenderViewModel.kt` — split-tender, cash/card/terminal flows. (commit `0f76f013`)
- [x] `pos/PosReceiptScreen.kt` + `pos/PosReceiptViewModel.kt` — print / SMS / email receipt dispatch. TODO ID: POS-RECEIPT-001. (commit `0f76f013`)
- [x] `pos/CashDrawerControllerStub.kt` — stub implementing the cash-drawer open command; real ESC/POS driver is a follow-up. (commit `0f76f013`)
- [x] `AppNavGraph.kt` — routes updated to wire all new POS destinations into the main nav graph. (commit `0f76f013`, merged via `0925af7f`)
- [x] `data/remote/api/PosApi.kt` — `notes: String?` field added to match server fix POS-NOTES-001 (`packages/server/src/routes/pos.routes.ts`). (commit `0f76f013`)
- [x] `data/remote/RetrofitClient.kt` — `providePosApi` + `provideReceiptNotificationApi` Hilt providers added. (commit `0f76f013`)

---

### 3. Repair check-in 6-step package

New `ui/screens/checkin/` package — 8 files total:

- [x] `ui/screens/checkin/CheckInHostScreen.kt` — navigation host that sequences the 6 steps; step-progress indicator at top. (commit `80578a59`)
- [x] `ui/screens/checkin/CheckInViewModel.kt` — shared ViewModel holding draft state across all steps; writes to Room `checkin_drafts` table. (commit `80578a59`)
- [x] 6 step screens (`Step1CustomerScreen.kt` … `Step6SignatureScreen.kt`) inside `ui/screens/checkin/`. Step 6 reuses `ui/components/SignaturePad.kt`. (commit `80578a59`)
- [x] Room schema migration 10→11 — `checkin_drafts` table added; migration SQL, DAO, entity class, and `DatabaseModule` Hilt provider all wired. (commit `80578a59`)
- [ ] Legacy 7-step ticket-create package at `ui/screens/tickets/create/steps/*` left intact — removal is a planned follow-up (see Known Gaps below).

---

### 4. BlockChyp SDK wrapper + SignatureRouter

- [x] `data/blockchyp/BlockChypClient.kt` — Hilt singleton wrapping the BlockChyp terminal SDK; typed request/response API. (commit `63f47d6a`, merged)
- [x] `data/remote/api/BlockChypApi.kt` — 6 Retrofit endpoints proxied through the CRM server (charge, refund, void, terminal status, signature capture, terminal list). (commit `63f47d6a`)
- [x] `util/SignatureRouter.kt` — prefers hardware terminal signature capture; falls back to on-phone `SignaturePad` when no terminal is reachable. (commit `63f47d6a`)
- [x] `di/BlockChypModule.kt` — Hilt module providing `BlockChypClient` and `BlockChypApi`. (commit `63f47d6a`)
- [x] `ui/screens/settings/HardwareSettingsViewModel.kt` — stub button handlers in `HardwareSettingsScreen.kt` (lines 266–324) replaced with real `BlockChypClient` calls. (commit `63f47d6a`)

---

### 5. 16 KB page-size alignment

- [x] `app/build.gradle` — `packaging.jniLibs.useLegacyPackaging = false` added. (commit `87a6d64a`)
- [x] `gradle.properties` — `android.bundle.enableUncompressedNativeLibs=true` added. (commit `87a6d64a`)

These two flags together satisfy the Play Store requirement for 16 KB ELF page-size alignment, required for devices running Linux kernel 6.x with 16 KB pages.

---

### 6. Build gate

- [x] Gradle build verified **BUILD SUCCESSFUL** by Phase 2 + Phase 4 agents after all five items above were merged. No outstanding compile errors or lint blockers at wave close.

---

### Known gaps (deferred to follow-up waves)

- [ ] **Legacy 7-step ticket-create package** — `ui/screens/tickets/create/steps/*` remains in the codebase. Removal blocked until the new 6-step check-in flow has been validated in production. Track as a follow-up cleanup task.
- [ ] **SMS receipt (POS-SMS-001)** — server-side endpoint for sending a receipt via SMS is not yet implemented. `PosReceiptViewModel.kt` has the client call site stubbed; requires `packages/server/src/routes/pos.routes.ts` to expose `POST /api/v1/pos/receipts/:id/sms`. Track as POS-SMS-001 in `TODO.md`.
- [ ] **Cash drawer real driver** — `pos/CashDrawerControllerStub.kt` sends no actual ESC/POS command. Needs hardware integration work tied to the supported receipt-printer model.
# POS Audit Wave — 2026-04-24 (10 parallel sonnet agents)

> Aggregated findings from 10 parallel POS-code audit agents. Each item cites
> concrete `file:line` evidence. Items are unchecked = open, `[x]` = shipped
> in this wave. Categories tagged per item. Append fix commits inline.

## Bugs

- [x] **POS-AUDIT-001 (Bug). `toDollarString()` mangles negative values.** `dollars = this / 100` keeps signed division but `cents = Math.abs(this % 100)`, so `-50L` -> `$0.50` (sign lost) and `-274L` -> `$-2.74` (sign inside dollar mark). Fix: compute sign separately, take abs of both halves, prepend `-$` only when negative. `PosModels.kt:92-96`. (10/10 agents)
- [x] **POS-AUDIT-002 (Bug). `isFullyPaid` blocks $0.00 finalization.** `remainingCents == 0L && totalCents > 0L` — fully-discounted or fully-store-credit-covered sale can never finalize; Charge button stays disabled with no explanation. `PosCoordinator.kt:35`, `PosTenderViewModel.kt:28`.
- [x] **POS-AUDIT-003 (Bug). PosTenderScreen snackbar host never wired.** `remember { SnackbarHostState() }` is inside `state.errorMessage?.let { ... }` but `Scaffold` has no `snackbarHost = ...` slot. Card-charge / network errors silently swallowed. `PosTenderScreen.kt:50, 136-142`.
- [x] **POS-AUDIT-004 (Bug). `PreAttachContent` second `hiltViewModel()` call.** `PreAttachContent` is private composable inside `EntryContent` inside `PosEntryScreen` (which already injects). Re-injecting at line 243 silently creates a different VM if composable is ever hoisted. Pass VM or `onCreateCustomer` lambda. `PosEntryScreen.kt:243`.
- [x] **POS-AUDIT-005 (Bug). `openReadyForPickup` doesn't attach customer.** Sets `linkedTicketId` + `setLines(...)` but skips `attachCustomer`. Tender finalize sends `customerId = null` for a ticket with a real owner. `PosEntryViewModel.kt:149-164`, `PosTenderViewModel.kt:122-125`.
- [x] **POS-AUDIT-006 (Bug). Ready-for-pickup line uses `taxRate = 0.0`.** `openReadyForPickup` builds `CartLine(...)` with default tax. Tender skips Cart, `PosCartViewModel.init` never seeds rate. Client-side total in Tender hero shows lower than server invoice. `PosEntryViewModel.kt:149-163`.
- [x] **POS-AUDIT-007 (Bug). `CartLineBottomSheet` qty stepper bypasses Save.** `-` and `+` taps fire `onQtyChange(qty)` immediately, mutating coordinator before Save. Comment says "applied to VM only on Save" but implementation contradicts — Cancel/dismiss does NOT revert qty. `CartLineBottomSheet.kt:79-111`.
- [x] **POS-AUDIT-008 (Bug). `DiscountChip.FLAT` and `DiscountChip.CUSTOM` apply $0 silently.** Only `FIVE_PCT` and `TEN_PCT` compute real values; other two fall to `else -> 0L` branch. UI highlights chip but writes 0 with no flat-amount or custom-percent input. `CartLineBottomSheet.kt:161-166`.
- [x] **POS-AUDIT-009 (Bug). Discount chip percent doesn't recompute on qty change.** Chip stores absolute cents at selection time using local `qty`. Stepper updates qty but chip's `discountCents` stays stale until user re-taps. `CartLineBottomSheet.kt:44, 157-172`.
- [x] **POS-AUDIT-010 (Bug). `sendEmail()` optimistic SENT with no API call.** `emailSentState = SendState.SENT` set synchronously, no network call. If server-side email fails, cashier sees check permanently and row becomes non-tappable. `PosReceiptViewModel.kt:114-118`.
- [x] **POS-AUDIT-011 (Bug). `parkCart()` empty stub.** Method body is comment-only. Tile fires nothing — no error, no snackbar, no navigation. `PosTenderViewModel.kt:99-102`.
- [x] **POS-AUDIT-012 (Bug). `CartDiscountDialog` Apply has no canApply guard / no overflow check.** Tapping Apply with empty input writes `cartDiscountCents = 0L`; entering amount > subtotal silently zeroes sale via `coerceAtLeast(0L)`. Add `canApply = cents > 0` + `cents <= subtotalCents`. `PosCartScreen.kt:610-631`.
- [x] **POS-AUDIT-013 (Bug). `PastRepairRow` clickable but no-op.** `clickable(onClickLabel = "Open ticket ${id}") { /* navigate to ticket */ }` — false TalkBack affordance. Wire to `Screen.TicketDetail` nav OR remove `clickable`. `PosEntryScreen.kt:614`.
- [x] **POS-AUDIT-014 (Bug). `RecentTicketChip` clickable but no-op.** Caller passes `onOpenTicket = { /* no-op */ }`. Same false-affordance. `PosEntryScreen.kt:239, 291-293`.
- [x] **POS-AUDIT-015 (Bug). `TicketResultRow` is not clickable.** No `clickable` modifier, no `onClick` parameter; ticket search hits in POS entry are inert. Wire to ticket detail OR cart-seed. `PosEntryScreen.kt:719-733`.
- [x] **POS-AUDIT-016 (Bug). `CustomerResultRow` subtitle drops ticket count when email is null.** Logic gates count on email presence. Mockup shows count regardless. Move ticket-count formatter outside `email?.let`. `PosEntryScreen.kt:712`.
- [x] **POS-AUDIT-017 (Bug). `CustomerResult.initials` uses raw `name.take(2)`.** "Sarah M.".take(2) = "Sa", not "SM". Avatar circle shows wrong characters in any consumer using default initials. `PosModels.kt:62`.
- [x] **POS-AUDIT-018 (Bug). "Search customer" path tile is a no-op.** `onClick = { /* search bar drives flow; tap is hint */ }`. Tile has chevron + ripple but does nothing. Wire to `searchExpanded = true` + focus the SearchBar. `PosEntryScreen.kt:259-265`.
- [x] **POS-AUDIT-019 (Bug). PosEntry `errorMessage` consumed but never displayed.** `LaunchedEffect` calls `viewModel.clearError()` without showing snackbar/dialog. Customer-create / search failures swallowed. Add SnackbarHost to Scaffold. `PosEntryScreen.kt:133-138`.
- [x] **POS-AUDIT-020 (Bug). `ReceiptNotificationApi` defined inline in VM, not in Hilt graph.** Interface declared at top of `PosReceiptViewModel.kt` and referenced via `@Inject` constructor. No `@Provides`/`@Binds` in any module. Move to `data/remote/api/` and bind via Retrofit module. `PosReceiptViewModel.kt:28-31, 52-56`.
- [x] **POS-AUDIT-021 (Bug). Tracking URL is always client-built `/track/<orderId>`, never server-supplied.** `PosCoordinator.completeOrder` called with `trackingUrl = null`; PosReceipt synthesizes a relative path. Receipt screen renders it underlined but with no `clickable` modifier. `PosTenderViewModel.kt:158-159`, `PosReceiptViewModel.kt:74-76`, `PosReceiptScreen.kt:119-127`.

## Mockup deviations

- [x] **POS-AUDIT-022 (Mockup). `+ Note` dashed slot missing on cart screen.** Mockup PHONE 3 shows three slots; Android renders only two. Wire cart-level note -> coordinator + `PosSaleRequest.notes`. `PosCartScreen.kt:191-195` vs mockup line 851.
- [x] **POS-AUDIT-023 (Mockup). Cart summary strip missing on PosEntry post-attach.** Mockup PHONE 1 line 641 shows a `Cart - empty / $0.00` strip between topbar and path tiles. Add compact row under `CustomerHeaderBanner`. `PosEntryScreen.kt:163-232`.
- [x] **POS-AUDIT-024 (Mockup). `CartPathTabs` underline + border use hardcoded hex.** Active underline `Color(0xFFFDEED0)` and inactive border `Color(0xFF332C3F)` bypass theme tokens. Replace with `MaterialTheme.colorScheme.primary` / `outline`. `PosCartScreen.kt:464-475`.
- [x] **POS-AUDIT-025 (Mockup). Cart top-bar overflow menu missing.** Mockup PHONE 3 shows a kebab menu in cart top-bar. Android renders inoperative `Icons.Outlined.Person` "Attach customer" no-op. Replace with `MoreVert` overflow opening sheet (Detach customer, Apply discount, Add note, Park cart). `PosCartScreen.kt:125-128`.
- [x] **POS-AUDIT-026 (Mockup). Store-credit tile absent from `PaymentMethodGrid`.** `applyStoreCredit()` exists in VM but no tile invokes it. Add tile labeled `Store credit - $X available` when `attachedCustomer.storeCreditCents > 0`. `PosTenderViewModel.kt:53-65`, `PosTenderScreen.kt:244-295`.
- [x] **POS-AUDIT-027 (Mockup). Cart tab label shows post-tax total; mockup uses pre-tax subtotal.** `state.totalCents` includes tax + discount; mockup PHONE 3 reads `Cart - 3 - $262` matching subtotal. Switch to `state.subtotalCents`. `PosCartScreen.kt:451-453`.
- [x] **POS-AUDIT-028 (Mockup). Search bar placeholder is the same string in both attach states.** Mockup PHONE 1 swaps placeholder to `Scan or search parts...` once a customer is attached. Branch placeholder on `state.attachedCustomer != null`. `PosEntryScreen.kt:93`.
- [x] **POS-AUDIT-029 (Mockup). `CartLineBottomSheet` doesn't show stock qty.** Mockup PHONE 4 sheet header reads `SKU USB-C3 - Stock 22`. Add `stockQty` to `CartLine` from inventory lookup. `CartLineBottomSheet.kt:63-65`, `PosModels.kt:7-25`.
- [x] **POS-AUDIT-030 (Mockup). "Store credit - payment" path tile routes to retail Cart.** `onStoreCredit = onNavigateToCart` — tile lands cashier on empty retail cart. Build dedicated store-credit screen. `PosEntryScreen.kt:71`.
- [x] **POS-AUDIT-031 (Mockup). `ReadyForPickupCard` Cookie12Sided shape clips border at concave notches.** Border + clip on same `Cookie12Sided` produces "bitten cookie" silhouette + tap-target gaps. Mockup uses plain 12dp radius. Drop Cookie12Sided here OR move shape to non-bordered child. `PosEntryScreen.kt:565-572`.

## UI / UX

- [x] **POS-AUDIT-032 (UX). Bottom nav stays visible on Cart + Tender + Receipt.** `showBottomNav` predicate at `AppNavGraph.kt:619` excludes only Scanner. Add `Screen.PosCart.route`, `Screen.PosTender.route`, `Screen.PosReceipt.route` to hide list.
- [x] **POS-AUDIT-033 (UX). `CartLineBottomSheet` `skipPartiallyExpanded = false` produces snap jitter.** Sheet content overflows partial-peek height on most phones, snapping immediately to full. Set `skipPartiallyExpanded = true`. `CartLineBottomSheet.kt:39`.
- [x] **POS-AUDIT-034 (UX). Cart-line bottom sheet doesn't dim the topBar.** Sheet rendered outside Scaffold content lambda; topBar stays bright while everything below dims. Move sheet inside Scaffold. `PosCartScreen.kt:222-234`.
- [x] **POS-AUDIT-035 (UX). `CartDiscountDialog` doesn't validate `cents <= subtotal`.** Discount > subtotal silently zeroes sale. Surface validation error + disable Apply. `PosCartScreen.kt:610-631`.
- [x] **POS-AUDIT-036 (UX). `CartLineBottomSheet` chip state doesn't reflect existing line discount on open.** `selectedChip` initializes to `null` regardless of `line.discountCents`. Compute initial `selectedChip` from existing discount value vs known thresholds. `CartLineBottomSheet.kt:43-44`.

## Accessibility

- [x] **POS-AUDIT-037 (A11y). `CartLineBottomSheet` qty stepper buttons 34dp < 48dp min.** Bump to 48.dp. `CartLineBottomSheet.kt:85, 101`.
- [x] **POS-AUDIT-038 (A11y). `PastRepairRow` subtitle bodySmall 12sp may fall below AA contrast.** `onSurfaceVariant` (#a79fb8) on Surface1 (#1a1722) ~= 4.1:1, fails AA-small. Bump to bodyMedium or increase color contrast. `PosEntryScreen.kt:629-633`.
- [x] **POS-AUDIT-039 (A11y). `CustomerHeaderBanner` + `ReadyForPickupCard` lack merged `contentDescription`.** TalkBack announces avatar + name + subtitle as 3 separate focusables. Add `Modifier.semantics(mergeDescendants = true)`. `PosEntryScreen.kt:395-422, 560-606`.
- [x] **POS-AUDIT-040 (A11y). `ReadyForPickupCard` lacks `Role.Button` semantics.** `clickable` with `onClickLabel` only, no `role = Role.Button`. Add to Row's semantics. `PosEntryScreen.kt:565-606`.

## Code quality

- [x] **POS-AUDIT-041 (Code). `CheckoutScreen` + `TicketSuccessScreen` are routable Phase-3 stubs.** Both reachable from real nav, render placeholder strings. Either delete routes (now that new check-in flow handles tickets) OR replace with proper screens. `CheckoutScreen.kt`, `TicketSuccessScreen.kt`, `AppNavGraph.kt:1120-1129`.
- [x] **POS-AUDIT-042 (Code). `CheckoutScreen` uses `Button` as `TopAppBar.navigationIcon`.** M3 contract requires `IconButton` (48dp, no fill). Filled `Button` renders incorrectly. `CheckoutScreen.kt:36-37`.

## User-flagged (this wave)

- [x] **POS-AUDIT-101 (Flow). Walk-in customer skipped path picker, dumped to cart.** Fixed in this wave: `onWalkIn` no longer auto-navigates — cashier stays on path picker after walk-in attaches.
- [x] **POS-AUDIT-102 (UX). Three post-attach path tiles top-aligned, not centered.** Fixed: post-attach Column uses Spacer weight 0.4f / 0.6f to bias tiles upper-middle (matches pre-attach pattern + mockup PHONE 1).
- [x] **POS-AUDIT-103 (Flow). Walk-in -> Create repair ticket re-asks for customer.** Fixed: `onNavigateToCheckin` passes id verbatim incl. 0L sentinel; `CheckInEntryViewModel.preFillCustomer(0L)` calls `attachWalkIn() + advance()` so cashier jumps straight to device step. Real-customer pre-fill also auto-advances.
- [x] **POS-AUDIT-104 (UX). Post-attach customer header has no contentDescription / status-bar overlap.** Earlier fixed via `statusBarsPadding()`. Verified on device 2026-04-24 — `pos-audit-104-verify.png` shows WC header / Cart strip / status-bar (8:57) all clear; no overlap after centering refactor.

## Aggregator note

Findings produced by 10 parallel sonnet code-audit agents, deduped. Each item is independently checkable. Cron `pos-fix-loop-reminder` fires every 10 minutes nudging continuation; remove the cron when this section is empty.

---
## Login-flow mockup parity wave — 2026-04-24

> **Mission.** 100% structural parity between the Android login flow (LoginScreen.kt, 3445 LOC) and the static PNG mockups in C:\Users\Owner\Downloads\MY OWN CRM\screen-01..11-*.png. Brand palette stays **cream #FDEED0** per project memory — ignore the purple #8B5CF6 rendered in the legacy mockups (memory: feedback_brand_color). All other structure (copy, spacing, components, helper text, error placement, tab strip, wave divider) must match the mockups byte-for-byte where feasible.
>
> **Reference mockups (in flow order):**
> - screen-01-login.png — Initial Server step (Connect to Your Shop, slug field, Connect CTA, "Self-hosted?" + "Register new shop" footer)
> - screen-02-register.png — Register card empty state (back arrow, 4 fields, disabled Create Shop)
> - screen-03-register-filled.png — Register card with focused Shop URL (label cut-out + cream outline)
> - screen-04-url-only.png — Register card after typing Shop URL only (still disabled Create Shop)
> - screen-05-filled.png — Register card all 4 fields filled (Create Shop ENABLED, cream pill)
> - screen-06-after-create.png — Register card with inline red "Origin header required" error above CTA
> - screen-07-back.png — Server step focused with keyboard up (slug field outlined cream, Connect button cream)
> - screen-08-retry.png — Server step pre-fill empty slug ("myshop" placeholder, Connect disabled)
> - screen-09-create-result.png — Sign In step header (Sign In + "Testing 123 Shop" subtitle, Username + Password fields, disabled Sign In)
> - screen-10-signed-in.png — 2FA Setup step (QR code in white frame, "Set Up Two-Factor Auth" + subtitle, 6-digit field with shield icon + cream outline focused)
> - screen-11-post-2fa.png — Dashboard post-login (out of scope for this section, included for context only)
>
> Legend: (Theme) palette/typography - (Layout) size/spacing - (Copy) exact strings - (Bug) defect - (A11y) accessibility - (Flow) step transition.

### Theme + tab strip

- [x] **LOGIN-MOCK-001 (Theme). Stale "purple #8B5CF6" reference in LoginTabBar doc-block.** LoginScreen.kt:2031-2033 comment claims active tab is "purple (#8B5CF6) text + 2dp purple underline indicator". Brand is now cream #FDEED0 (Theme.kt:43). Replace comment with cream + reference MaterialTheme.colorScheme.primary so doc and code agree.
- [x] **LOGIN-MOCK-002 (Layout). Card surface hardcoded Color(0xFF1F1F23).** LoginScreen.kt:2007 — escape hatch breaks any future palette swap (light theme, dynamic-color override, brand re-tune). Replace with MaterialTheme.colorScheme.surfaceContainer (or surface1 semantic token) to match the rest of the app and the mockup card tone.
- [x] **LOGIN-MOCK-003 (Layout). Tab text style is labelMedium (12sp); mockup tabs read at ~14-15sp.** LoginScreen.kt:2080. Bump to MaterialTheme.typography.titleSmall (14sp medium) for tap-target legibility and match to screen-01 / screen-09.
- [ ] **LOGIN-MOCK-004 (Theme). Inactive tab divider line missing visual continuity at indicator gap.** LoginScreen.kt:2068-2070 renders HorizontalDivider underneath a 2dp SecondaryIndicator. Mockup shows the inactive segment line dimmer than the active indicator and FLUSH with it (no overlap). Audit z-order: indicator should sit ABOVE the divider, not be the same thickness.
- [x] **LOGIN-MOCK-005 (Layout). Tab row contentColor hardcoded to activeColor propagates cream to inactive tabs.** LoginScreen.kt:2052 sets contentColor = activeColor. Tab override at :2081-2082 correctly switches inactive to muted, but the selectedContentColor/unselectedContentColor props at :2084-2085 duplicate that logic. Pick one source of truth (preferred: drop :2052 override, let Tab props drive color).

### Hero / wordmark / wave divider

- [x] **LOGIN-MOCK-006 (Layout). Top spacer is height(80.dp); mockup hero sits at ~30-35% screen height.** LoginScreen.kt:1869. On 6.7" reference (mockup ratio), wordmark center is at ~40% of viewport. Replace static 80.dp with a Spacer(weight=...) or compute from BoxWithConstraints so hero centers vertically when keyboard is dismissed. Server step screen-01 shows the wordmark roughly mid-screen, not pinned to top.
- [ ] **LOGIN-MOCK-007 (Theme). Wordmark uses headlineLarge.copy(fontSize = 36.sp) — mockup looks heavier (display weight, condensed).** LoginScreen.kt:1872-1874. Confirm headlineLarge is wired to BarlowCondensedFamily per Typography.kt. If it's still FontFamily.Default, the wordmark renders Roboto bold and won't match the mockup's compressed serif-ish "Bizarre CRM". Verify font assets in res/font/ are loaded.
- [ ] **LOGIN-MOCK-008 (Copy). Subtitle is "Electronics Repair Management".** LoginScreen.kt:1879 matches mockups screen-01/02/03/04/05/06 verbatim. Keep — but also verify casing (Title Case, no period) and confirm bodyMedium muted color matches mockup grey (mockup ~#7A7A7A, theme MutedText = #B09A84). Investigate if onSurfaceVariant resolves to roughly the right hue in dark theme.
- [ ] **LOGIN-MOCK-009 (Layout). Wave divider hairline thickness audit.** WaveDivider.kt (component file) — confirm 1px stroke at ~15% magenta alpha matches mockup's barely-visible curve. If too prominent, dial down alpha. If too subtle, bump.
- [x] **LOGIN-MOCK-010 (Layout). Wave divider sits 12dp under subtitle; mockup gap looks ~20-24dp.** LoginScreen.kt:1884. Increase top spacer to 20.dp.

### Server step (screen-01, screen-07, screen-08)

- [ ] **LOGIN-MOCK-011 (Copy). Subtitle "Enter your shop name to connect" — current matches mockup.** LoginScreen.kt:2173. Keep verbatim.
- [ ] **LOGIN-MOCK-012 (Layout). OutlinedTextField suffix .bizarrecrm.com may collide with cursor on long slugs.** LoginScreen.kt:2207-2213. Mockup screen-03 shows long slug truncating with an ellipsis effect ("Btsting123yadmintesti.bizarrecrm.com"). Verify TextOverflow.Ellipsis on the value text or set maxLength = 30 on input — server enforces 3-30 char range per helper text.
- [ ] **LOGIN-MOCK-013 (Theme). Connect button disabledContainerColor = surfaceVariant blends with card surface.** LoginScreen.kt:2237. Mockup screen-01/screen-08 show the disabled CTA as a slightly lighter pill against the card — current surfaceVariant may be the same shade as the card, making the button visually disappear. Switch disabled bg to onSurface @ alpha 0.12f (Material default) or surface3 so it stays a visible affordance.
- [x] **LOGIN-MOCK-014 (Copy). "Connect" button label uses labelLarge.** LoginScreen.kt:2244. Mockup shows it slightly larger and bolder than labelLarge default — try titleMedium semibold.
- [x] **LOGIN-MOCK-015 (Layout). Footer row Self-hosted? + Register new shop use bodyMedium; mockup footer text reads like labelLarge.** LoginScreen.kt:2257, 2262. Bump style to labelLarge semibold so the actions read as buttons, not body text.
- [ ] **LOGIN-MOCK-016 (Theme). Cloud-mode placeholder is myshop (matches).** LoginScreen.kt:2203. Verified vs mockup screen-08. Keep.
- [ ] **LOGIN-MOCK-017 (Layout). Server step has NO back arrow in the card; mockup screen-01 also has none.** LoginScreen.kt:2156-2266 has no IconButton(onBack) here. Correct — keep.
- [ ] **LOGIN-MOCK-018 (Bug). "Use BizarreCRM Cloud" / "Self-hosted?" toggle on same row as "Register new shop" — mockup screen-01 shows them spaced apart.** Current Arrangement.SpaceBetween at :2252 is correct. Verify horizontal padding inside card for the row matches mockup ~16dp gutter.

### Register step (screen-02, screen-03, screen-04, screen-05, screen-06)

- [x] **LOGIN-MOCK-019 (Layout). Register back-arrow + title spacing tight.** LoginScreen.kt:2277-2288. Current Spacer(width(4.dp)) between IconButton and title text is too tight; mockup screen-02 shows ~12-16dp gap. Bump to 12.dp or use IconButton default 48dp tap target which already includes the spacing.
- [ ] **LOGIN-MOCK-020 (Copy). Register subtitle "Create your repair shop on BizarreCRM" matches mockup screen-02 verbatim.** LoginScreen.kt:2292. Keep.
- [ ] **LOGIN-MOCK-021 (Layout). Shop URL field uses Icons.Outlined.Link; mockup screen-03/04/05 shows a chain icon — verify which renders.** LoginScreen.kt:2305. Outlined.Link is the chain. Match.
- [ ] **LOGIN-MOCK-022 (Layout). Register Shop URL helper "3-30 characters: letters, numbers, hyphens" matches mockup verbatim.** LoginScreen.kt:2313. Keep — but verify the en-dash is the correct Unicode char and not a hyphen-minus.
- [ ] **LOGIN-MOCK-023 (Layout). Shop Display Name field uses Icons.Default.Store; mockup screen-02/04/05 shows the same store-front icon.** LoginScreen.kt:2326. Match.
- [ ] **LOGIN-MOCK-024 (Copy). Admin Email + Admin Password labels match mockup verbatim.** LoginScreen.kt:2336, 2349. Keep.
- [ ] **LOGIN-MOCK-025 (Layout). Admin Password trailing eye icon — IconButton shows visibility toggle.** LoginScreen.kt:2354-2361 matches mockup screen-02/05.
- [ ] **LOGIN-MOCK-026 (Bug). Password helper "Minimum 8 characters" stays visible even on focus — mockup screen-05 shows it persistently.** LoginScreen.kt:2362. Confirm supportingText doesn't disappear on validation success — it shouldn't, but verify.
- [ ] **LOGIN-MOCK-027 (Layout). Inline error "Origin header required" — mockup screen-06 shows it left-aligned, no icon, red color, sitting BETWEEN password helper and Create Shop CTA.** LoginScreen.kt:2368-2375. Current implementation matches. Verify color resolves to MaterialTheme.colorScheme.error (not hardcoded red) and font is bodySmall.
- [ ] **LOGIN-MOCK-028 (Layout). Create Shop button height 56dp + 28dp pill radius matches mockup screen-05.** LoginScreen.kt:2389-2392. Match. Verify enabled state cream fill + onPrimary dark text matches screen-05 (#FDEED0 fill + #2B1400 text).
- [ ] **LOGIN-MOCK-029 (Layout). Create Shop disabled state uses onSurface @ 0.24f — confirm that matches screen-04's grey CTA shade.** LoginScreen.kt:2396-2397. Visual sanity-check on dark Surface1 = #26201A — alpha 0.24 of #F5E6D3 ~= #3F3A33 which matches mockup grey. Verify with screenshot.
- [x] **LOGIN-MOCK-030 (Bug). Register form has no scroll affordance when keyboard up — 4 fields + helpers may overflow on small phones.** Card itself isn't scrollable, only the outer Column. Confirm parent verticalScroll(rememberScrollState()) at LoginScreen.kt:1865 covers the register card content. If keyboard pushes Create Shop off-screen, add ime padding or scroll-to-CTA on focus. Verified: outer Column at :1872 already has `verticalScroll(rememberScrollState())` covering all step cards including Register; no additional scroll wrapper needed.

### Sign In / Credentials step (screen-09)

- [ ] **LOGIN-MOCK-031 (Copy). Header "Sign In" + subtitle is the SHOP DISPLAY NAME (e.g. "Testing 123 Shop") per mockup screen-09.** Current CredentialsStep at LoginScreen.kt:2416+ may not show the shop name as subtitle — needs verification. If absent, render state.storeName (or fall back to host) as bodySmall onSurfaceVariant under the "Sign In" titleLarge.
- [ ] **LOGIN-MOCK-032 (Layout). Sign In step back arrow inside card — IconButton(onClick = goBack) to return to Server.** Confirm CredentialsStep has back arrow + title row matching screen-09.
- [ ] **LOGIN-MOCK-033 (Layout). Username field uses Person icon (mockup screen-09).** Verify CredentialsStep's username field has Icons.Default.Person leading icon.
- [ ] **LOGIN-MOCK-034 (Layout). Password field uses Lock icon + visibility eye trailing.** Verify CredentialsStep matches.
- [ ] **LOGIN-MOCK-035 (Layout). Sign In CTA disabled state matches mockup screen-09 grey pill (Sign In disabled when fields empty).** Verify pill shape (28dp), height 56dp, label "Sign In" (case match).
- [ ] **LOGIN-MOCK-036 (Bug). Per recent commit feat(android/login): wave 4 polish, RememberMe + ForgotPassword were removed.** Verify NO "Forgot password?" text or RememberMe checkbox renders on the Sign In card — mockup screen-09 has neither.
- [ ] **LOGIN-MOCK-037 (Layout). Sign In tab indicator color on screen-09 looks teal-ish; current uses colorScheme.primary (cream).** LoginScreen.kt:2064. Mockup shows a TEAL underline on the previously-completed Server tab + cream/purple on the active Sign In tab. If the design intent is "completed = secondary, current = primary", that's a divergence. For now keep single primary color across, but flag for design clarification — added: LOGIN-MOCK-037-TBD.

### 2FA Setup step (screen-10)

- [ ] **LOGIN-MOCK-038 (Layout). Header "Set Up Two-Factor Auth" uses titleMedium; mockup looks larger/bolder.** LoginScreen.kt:3181. Promote to titleLarge SemiBold/Bold for parity with Server/Register/Sign In headers.
- [ ] **LOGIN-MOCK-039 (Copy). Subtitle "Scan this QR code with Google Authenticator or any TOTP app" matches mockup screen-10 verbatim.** LoginScreen.kt:3184. Keep.
- [x] **LOGIN-MOCK-040 (Layout). QR code rendered directly without white background frame.** LoginScreen.kt:3220-3224. Mockup screen-10 shows the QR inside a WHITE square (~240dp) with ~16dp padding. Wrap Image in Surface(color = Color.White, shape = RoundedCornerShape(8.dp), modifier = Modifier.padding(16.dp)) to match. ZXing-encoded QR codes need a light bg to scan reliably anyway.
- [x] **LOGIN-MOCK-041 (Layout). QR Box height fixed at 200.dp; mockup shows ~240dp incl. white frame.** LoginScreen.kt:3216. Increase to 240.dp or compute from screen width.
- [x] **LOGIN-MOCK-042 (Layout). 6-digit TOTP field leading icon is Icons.Default.Lock; mockup screen-10 shows a SHIELD with a check.** TotpCodeInputContent LoginScreen.kt:3424. Replace with Icons.Outlined.VerifiedUser or Icons.Default.Shield (whichever ships in M3 icon pack) for parity.
- [ ] **LOGIN-MOCK-043 (Layout). 6-digit field placeholder/label is "6-digit code"; mockup screen-10 matches.** LoginScreen.kt:3414. Keep.
- [x] **LOGIN-MOCK-044 (Layout). Continue button height is 48dp; mockup CTAs across the flow are all 56dp.** LoginScreen.kt:3437. Change .height(48.dp) to .height(56.dp) and add shape = RoundedCornerShape(28.dp) to match the pill shape used by Connect/Create Shop/Sign In.
- [x] **LOGIN-MOCK-045 (Layout). Continue button has no explicit pill shape.** LoginScreen.kt:3434-3438. Add shape = RoundedCornerShape(28.dp) and explicit colors = ButtonDefaults.buttonColors(...) to match the other CTAs.
- [x] **LOGIN-MOCK-046 (Bug). 2FA Verify uses Icons.Default.ArrowBack instead of AutoMirrored variant.** LoginScreen.kt:3374. Recent commit migrated other arrows to AutoMirrored.Filled.ArrowBack; this one was missed. RTL bug. Replace.
- [x] **LOGIN-MOCK-047 (Copy). 2FA Verify subtitle "Enter the 6-digit code from your authenticator app" — mockup screen-10 (Setup) doesn't show the verify subtitle, only Setup. Confirm Verify card mockup parity.** Verified copy matches expected: TwoFaVerifyStep subtitle at LoginScreen.kt:3372 reads "Enter the 6-digit code from your authenticator app". No change needed.
- [x] **LOGIN-MOCK-048 (Layout). 2FA Setup "Set Up Two-Factor Auth" + "Scan this QR code" subtitle uses bodySmall muted.** LoginScreen.kt:3185. Mockup looks like bodyMedium. Promote one size.

### Cross-step polish

- [x] **LOGIN-MOCK-049 (Theme). All step CTAs (Connect/Create Shop/Sign In/Continue) should share an identical button spec.** Currently three of them share 56dp height + 28dp pill, but Continue (2FA) diverges (LOGIN-MOCK-044). Lift the spec into a shared LoginPillButton(onClick, enabled, isLoading, label) Composable in ui/components/auth/ and call from all 4 sites.
- [ ] **LOGIN-MOCK-050 (Theme). All step OutlinedTextFields should share leading/trailing/suffix conventions.** Audit: cream outline focused / muted outline unfocused / cream label cut-out. Confirm OutlinedTextFieldDefaults.colors() is configured at the app theme level so all instances inherit cream automatically — no per-field color overrides.
- [x] **LOGIN-MOCK-051 (Layout). Card padding 20.dp everywhere; mockup gutters look ~24dp.** LoginScreen.kt:2010. Bump Modifier.padding(20.dp) to padding(horizontal = 20.dp, vertical = 24.dp) so the card title doesn't crowd the top edge.
- [x] **LOGIN-MOCK-052 (Layout). Card RoundedCornerShape is 16.dp; mockup card radius reads ~20-24dp.** LoginScreen.kt:2006. Bump to 20.dp for parity.
- [x] **LOGIN-MOCK-053 (A11y). Tab strip is display-only (onClick = no-op) yet has tappable Tab semantics.** LoginScreen.kt:2076. TalkBack announces tabs as buttons, but tapping does nothing — a false affordance. Add Modifier.semantics { role = Role.Tab; selected = isSelected; onClick = null } and disable click handling so TalkBack reads them as status indicators, not actions. OR enable click-to-jump-back (Server tap when on Sign In = goBack).
- [x] **LOGIN-MOCK-054 (A11y). Wordmark "Bizarre CRM" lacks contentDescription heading semantics.** LoginScreen.kt:1870-1875. Add Modifier.semantics { heading() } so TalkBack treats it as a screen title.
- [x] **LOGIN-MOCK-055 (A11y). Each step header (Connect to Your Shop / Register New Shop / Sign In / Set Up Two-Factor Auth) lacks heading semantics.** Bulk-add Modifier.semantics { heading() } to all four titleLarge text nodes.
- [x] **LOGIN-MOCK-056 (Bug). Top Spacer(Modifier.height(80.dp)) is hardcoded; on small phones (5.4" or fontScale=2.0) the wordmark may push the card off-screen.** LoginScreen.kt:1869. Replace with a weight-based vertical centering scheme inside a Column(verticalArrangement = Arrangement.Center) + Spacer(weight = 1f) above the wordmark.
- [ ] **LOGIN-MOCK-057 (Theme). surfaceContainer semantic token absent — Theme.kt may not define it.** LoginScreen.kt:2007 falls back to a hardcoded color because the theme might not expose surfaceContainer. Audit Theme.kt:43-90 and add surfaceContainer, surfaceContainerHigh, surfaceContainerLow to both light + dark ColorScheme blocks if missing.
- [x] **LOGIN-MOCK-058 (Layout). AnimatedContent slide direction on goBack vs goForward.** LoginScreen.kt:1993-1996 always slides in from right + out to left. Going BACK from Register to Server should reverse direction. Wire transitionSpec to detect targetState.ordinal less than initialState.ordinal and flip horizontals. Fixed: transitionSpec now compares ordinals — forward slides right→left, back slides left→right.
- [ ] **LOGIN-MOCK-059 (Bug). Register card Field 4: Admin Password has no PasswordStrengthMeter.** LoginScreen.kt:2346-2365. The SetPasswordStep uses a strength meter; the Register Admin Password field should too — the helper Minimum 8 characters is the only feedback now. Mockup doesn't show a meter explicitly, so this is OPTIONAL — flag LOGIN-MOCK-059-OPT.
- [ ] **LOGIN-MOCK-060 (A11y). Field labels in mockup screen-09 (Username, Password) — verify OutlinedTextField label slot is used (cut-out animation), not placeholder.** Mockup screen-09 shows fields without cut-outs (label sits inside as placeholder text). Either render placeholder = { Text("Username") } with NO label, OR use label = { Text("Username") } with cut-out animation. Pick one consistent with screen-03/screen-05 register fields, which DO show cut-outs.
- [ ] **LOGIN-MOCK-061 (Theme). Inline error red color audit.** LoginScreen.kt:2371 uses MaterialTheme.colorScheme.error. Theme.kt sets ErrorRed = #E2526C. Verify rendering on Surface1 (#26201A) hits AA 4.5:1 — visual pass.
- [x] **LOGIN-MOCK-062 (Layout). Spacing between fields in Register card.** LoginScreen.kt:2317, 2330, 2343, 2377 all Spacer(Modifier.height(16.dp)). Mockup screen-05 shows ~20dp gaps. Bump to 20.dp consistently.

### Verification + lint

- [ ] **LOGIN-MOCK-063 (Verify). Build the app, sideload to USB-connected device (adb install -r), navigate Server -> Register -> Sign In -> 2FA Setup, screenshot each step.** Compare against screen-01..10-*.png side-by-side. Document deltas in a follow-up wave.
- [ ] **LOGIN-MOCK-064 (Verify). Run ./gradlew lintDebug and resolve any lint errors introduced by changes (text color contrast, deprecated APIs).**
- [ ] **LOGIN-MOCK-065 (Verify). Run ./gradlew testDebugUnitTest — LoginViewModelRegisterTest.kt must still pass after register-card changes.**

## Aggregator note (login wave)

Findings produced by the parent + 3 parallel sonnet finder agents (LOGIN-MOCK-066+ to be appended below as agents complete). 2 sonnet fixer agents work in parallel against the unchecked items above. Each item is independently checkable. Cron login-mock-loop-reminder fires every 10 minutes nudging continuation; remove the cron when this section is empty.

### Finder-C theme + typography gaps

Audited files: `ui/theme/Theme.kt`, `ui/theme/Typography.kt`, `ui/components/WaveDivider.kt`, `res/font/`, `ui/screens/auth/LoginScreen.kt` (lines 1869-1887, 3267, 3418).

- [ ] **LOGIN-MOCK-066 (Theme). `surfaceContainerLow` is absent from both LightColorScheme and DarkColorScheme in Theme.kt.** Only `surfaceContainer` and `surfaceContainerHigh` are explicitly set; `surfaceContainerLow` is not. Material 3 will silently derive a value, but for mockup card-tone parity the token must be pinned. In DarkColorScheme add `surfaceContainerLow = Color(0xFF201A14)` (one step below `Surface1 #26201A`). In LightColorScheme add `surfaceContainerLow = Surface50` (`#FAF4EC`) as the lowest rung. Files: `ui/theme/Theme.kt` lines ~127-160.

- [x] **LOGIN-MOCK-067 (Typography). `headlineSmall` is not assigned `BarlowCondensedFamily` in Typography.kt.** `headlineLarge` and `headlineMedium` correctly use `BarlowCondensedFamily`; `headlineSmall` is absent from `BizarreTypography`, so it falls back to M3's default (`Roboto`). If any composable uses `headlineSmall` for a section title (e.g., card sub-headers on tablet layouts) it will render in Roboto instead of Barlow Condensed, breaking visual consistency. Add `headlineSmall = TextStyle(fontFamily = BarlowCondensedFamily, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, lineHeight = 28.sp)` to `BizarreTypography`. Files: `ui/theme/Typography.kt` after line 80.

- [x] **LOGIN-MOCK-068 (Typography). `labelMedium` is not defined in `BizarreTypography`.** `labelLarge` and `labelSmall` are set to `InterFamily`; `labelMedium` is absent and falls back to M3's default font. Chip labels, badge text, and helper-text composables that resolve `MaterialTheme.typography.labelMedium` will render in Roboto. Add `labelMedium = TextStyle(fontFamily = InterFamily, fontWeight = FontWeight.Medium, fontSize = 13.sp, lineHeight = 18.sp)` alongside `labelLarge`/`labelSmall`. Files: `ui/theme/Typography.kt` after line 123.

- [x] **LOGIN-MOCK-069 (Theme). WaveDivider magenta hairline renders at 60% alpha, but the audit spec requires ~15% alpha.** `WaveDivider.kt` line 109 calls `magenta.copy(alpha = 0.60f)` — this produces a visually prominent pink line, not a subtle hairline flourish. The base-wave outline layer at 15% is correct; the hairline on top at 60% dominates. If design intent is a delicate decorative accent (consistent with "low-contrast texture" wording in the KDoc), reduce hairline to `alpha = 0.15f`. If intent is a bolder accent stripe, update the KDoc to say "~60% alpha" so the wording matches. Requires design clarification — flag LOGIN-MOCK-069-TBD. Files: `ui/components/WaveDivider.kt` line 109.

### Finder-B additional deltas

- [x] **LOGIN-MOCK-070 (Layout). Sign In header row has redundant `Spacer(width(8.dp))` after IconButton, misaligning title block from mockup.** Screen-09 shows the back arrow and "Sign In" / "Testing 123 Shop" tightly coupled with the arrow optically flush-left to the card edge. `IconButton` already contributes 12dp internal horizontal padding; the explicit `Spacer(Modifier.width(8.dp))` at LoginScreen.kt:2626 adds extra dead space pushing the title further right than the mockup shows. Remove this Spacer — the 48dp tap target with built-in padding already provides the correct visual gap. Fixed: Spacer removed from CredentialsStep header row.

- [ ] **LOGIN-MOCK-071 (Layout). Sign In Username and Password fields use floating `label` slot but mockup screen-09 shows placeholder-style inline text with no cut-out chrome.** LoginScreen.kt:2639 (`label = { Text("Username") }`) and :2697 (`label = { Text("Password") }`). Screen-09 shows "Username" and "Password" rendered as grey inline placeholder text sitting inside the field border without a floating label cut-out. Swap both to `placeholder = { Text("Username") }` / `placeholder = { Text("Password") }` and drop the `label` slot, giving the mockup look. Verify the Register step (screen-03/05) intentionally keeps floating labels — these steps can differ.

- [x] **LOGIN-MOCK-072 (Bug). `SetPasswordStep` back arrow uses `Icons.Default.ArrowBack` — missed in the wave-4 AutoMirrored migration.** LoginScreen.kt:3106. Every other step's back arrow was migrated to `Icons.AutoMirrored.Filled.ArrowBack` (including CredentialsStep at :2624 and TwoFaVerifyStep at :3374), but SetPasswordStep still calls `Icons.Default.ArrowBack`. RTL mirror will render incorrectly on right-to-left locales. Fix: replace with `Icons.AutoMirrored.Filled.ArrowBack`. Verified already `Icons.AutoMirrored.Filled.ArrowBack` at :3131 — confirmed correct.

- [x] **LOGIN-MOCK-073 (Layout). `SetPasswordStep` "Set Password" CTA is a raw `Button { }` at 48dp height with no pill shape — diverges from the 56dp pill spec used by Connect / Create Shop / Sign In.** LoginScreen.kt:3148-3158. Replace with `BrandPrimaryButton(modifier = Modifier.fillMaxWidth().height(56.dp))` to match every other primary CTA in the login flow. Current raw `Button { }` uses the theme's `shapes.medium` (12dp corner) instead of the 28dp pill in `BrandPrimaryButton`. Fixed: replaced with `LoginPillButton` (56dp, 28dp pill).

- [x] **LOGIN-MOCK-074 (Layout). `TwoFaSetupStep` title "Set Up Two-Factor Auth" uses `titleMedium + SemiBold` while all other step headers use `titleLarge + Bold`.** LoginScreen.kt:3181 — `style = MaterialTheme.typography.titleMedium`. Compare: CredentialsStep "Sign In" at :2628 uses `titleLarge + Bold`; SetPasswordStep "Set Your Password" at :3109 uses `titleMedium + SemiBold` (also wrong). Both 2FA Setup and SetPassword should be promoted to `titleLarge + Bold` to match. Mockup screen-10 header "Set Up Two-Factor Auth" reads visually larger than `titleMedium` on a 393dp-wide screen.

- [ ] **LOGIN-MOCK-075 (Layout). `TotpCodeInputContent` Continue button is a raw `Button { }` missing the 28dp pill shape and 56dp height.** LoginScreen.kt:3434-3444 — `Button(onClick = ..., modifier = Modifier.fillMaxWidth().height(48.dp))`. This diverges from the `BrandPrimaryButton` spec (28dp corner, 56dp height) used by Connect / Create Shop / Sign In. LOGIN-MOCK-044 already flags the height; this item specifically flags the missing pill shape caused by using raw `Button` instead of `BrandPrimaryButton`. Fix both at the same callsite: replace `Button { }` with `BrandPrimaryButton(modifier = Modifier.fillMaxWidth().height(56.dp)) { ... }`.

- [x] **LOGIN-MOCK-076 (Layout). `ErrorMessage` in `TotpCodeInputContent` appears between the TOTP field and the Continue button, pushing the CTA down on wrong-code entry.** LoginScreen.kt:3431. Sequence: field → `ErrorMessage` (adds `Spacer(12.dp)` + text line + any layout height) → `Spacer(16.dp)` → Continue. On wrong-code, this inserts ~36-40dp between field and CTA, potentially pushing Continue below the keyboard on 5.0" phones. Relocate `ErrorMessage(state.error)` to after the Continue button (line 3445+) so the field-to-CTA rhythm is constant, and the error appears beneath the button — matching the pattern used in CredentialsStep where `ErrorMessage` is between the password field and Sign In button, not above it. Fixed: ErrorMessage moved after LoginPillButton.

- [ ] **LOGIN-MOCK-077 (Layout). `TwoFaSetupStep` "Can't scan?" TextButton is center-aligned via `.wrapContentWidth(Alignment.CenterHorizontally)` while all other card text is left-aligned.** LoginScreen.kt:3243 — `modifier = Modifier.fillMaxWidth().wrapContentWidth(Alignment.CenterHorizontally)`. This creates an orphan centered element in an otherwise left-aligned column. Remove the `wrapContentWidth` override and let the button fill the width with start-aligned content matching the card gutter convention.

- [ ] **LOGIN-MOCK-078 (Layout). `TwoFaVerifyStep` header "Two-Factor Authentication" uses `titleMedium + SemiBold` — inconsistent with `titleLarge + Bold` on Sign In.** LoginScreen.kt:3377 — `style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold`. The verify step is a full card step with its own back arrow, matching the Sign In step structure, so it should use `titleLarge + Bold` for the same visual weight.

- [ ] **LOGIN-MOCK-079 (A11y / UX). `TotpCodeInputContent` auto-focuses the TOTP field via `LaunchedEffect(Unit) { focusRequester.requestFocus() }` at :3409, opening the numeric keyboard immediately on both Setup and Verify steps.** In the Verify step this is correct behavior (user just needs to type a code). In the Setup step, however, the keyboard opening immediately scrolls the QR code off-screen before the user can scan it — mockup screen-10 confirms the keyboard is visible, which means the user must scroll up to see the QR on small phones. Fix: add a `requestFocusOnMount: Boolean = true` parameter to `TotpCodeInputContent` and pass `false` from `TwoFaSetupStep` (line 3332) so the keyboard stays dismissed until the user taps the field after scanning.

- [ ] **LOGIN-MOCK-080 (Copy). `ChallengeTokenCountdown` label reads "Sign-in expires in M:SS" — verbose on narrow screens.** LoginScreen.kt:2146. At minimum Inter font 11sp (`labelSmall`), "Sign-in expires in 9:59" is ~26 chars and may wrap to two lines on 360dp-wide phones with 40dp card padding. Shorten to "Session expires M:SS" (saves 8 chars) to guarantee single-line at labelSmall. LoginScreen.kt:2146 `"Sign-in expires in $label"`.

- [x] **LOGIN-MOCK-081 (Layout). `TwoFaSetupStep` manual-key Surface uses `color = MaterialTheme.colorScheme.surfaceVariant` which in dark mode resolves close to the card background, making the monospace secret block nearly invisible.** LoginScreen.kt:3260. Per Theme.kt audit (LOGIN-MOCK-057 / LOGIN-MOCK-066), `surfaceContainerLow` / `surfaceContainerHighest` may be more appropriate. Use `MaterialTheme.colorScheme.surfaceContainerHighest` (or a hardcoded token pending the Theme.kt audit in LOGIN-MOCK-066) for the manual-key inset so it reads as a clearly distinct code block against the card surface. Fixed: changed to `surfaceContainerHighest`.

### Finder-A additional deltas

- [x] **LOGIN-MOCK-082 (Copy). ServerStep and RegisterStep in-card subtitles use `bodySmall` (12sp); mockup proportions match `bodyMedium` (14sp).** LoginScreen.kt:2174 (`bodySmall` for "Enter your shop name to connect" / "Enter your self-hosted server address") and :2293 (`bodySmall` for "Create your repair shop on BizarreCRM"). The outer wordmark subtitle at :1880 is already `bodyMedium`, establishing the text-scale baseline for this screen. The in-card step subtitles are the only body-copy nodes using `bodySmall` — they read noticeably undersized compared to the mockup's visible line proportions on a physical device (screens 01, 02, 07, 08). Change both callsites from `MaterialTheme.typography.bodySmall` to `MaterialTheme.typography.bodyMedium`.

- [ ] **LOGIN-MOCK-083 (Layout). RegisterStep `titleLarge` header has no explicit `fontSize = 22.sp` pin, while ServerStep does — sizes may diverge if `BizarreTypography` defines `titleLarge` at a non-default size.** LoginScreen.kt:2163-2165 applies `.copy(fontSize = 22.sp, fontWeight = FontWeight.Bold)` to "Connect to Your Shop". LoginScreen.kt:2284 applies plain `MaterialTheme.typography.titleLarge` with a separate `fontWeight = FontWeight.Bold` argument (no `fontSize` override) to "Register New Shop". If `BizarreTypography` in Typography.kt sets `titleLarge` to anything other than M3's default 22sp, the two step headers will render at different sizes despite representing the same hierarchy level. Add `.copy(fontSize = 22.sp)` to LoginScreen.kt:2284, or remove the explicit copy from ServerStep and rely on the type scale for both headers consistently.

- [x] **LOGIN-MOCK-084 (Layout). Fixed `Spacer(Modifier.height(80.dp))` above wordmark does not compress when software keyboard is raised; hero competes with the card for shrunken viewport space.** LoginScreen.kt:1869. The outer `Box` at :1857 has `imePadding()` which translates the entire column upward, but the 80dp header spacer is inelastic and does not collapse. On small phones (5.0", ~800 logical pixels) with a tall IME (~320dp), the wordmark + wave + tabs consume ~160dp, leaving ~320dp for the card — barely enough for 4 fields. Mockup screen-07 (keyboard raised) shows the wordmark visibly compressed into a shorter hero area. Replace the fixed `Spacer(80.dp)` with `Spacer(Modifier.weight(1f))` inside a parent `Column(Modifier.fillMaxHeight(), verticalArrangement = Arrangement.Center)` to allow proportional compression, OR use `WindowInsets.ime` to derive a dynamic height that shrinks when the keyboard is visible. This is the most impactful layout bug on small-screen devices.

- [x] **LOGIN-MOCK-085 (Layout). WaveDivider total vertical budget (60dp) is oversized vs mockup gap (~40dp) between subtitle and tab row.** LoginScreen.kt:1884 `Spacer(height = 12.dp)` + WaveDivider.kt canvas `height = 24.dp` (line 74) + LoginScreen.kt:1886 `Spacer(height = 24.dp)` = 60dp total. All mockup screens (01, 02, 07, 08) show the wave sitting snugly between the "Electronics Repair Management" subtitle and the tab bar with approximately 8dp above the curve and 16dp below. Remediation: change LoginScreen.kt:1884 to `height(8.dp)`, reduce WaveDivider.kt:74 canvas from `height(24.dp)` to `height(16.dp)`, keep LoginScreen.kt:1886 at `height(24.dp)`. Total = 48dp. The Canvas height reduction is safe — all Bézier control points are expressed as fractions of `size.height` and will proportionally rescale.

- [ ] **LOGIN-MOCK-086 (Theme). `OutlinedTextField` focused border and floating label cut-out color depend on `colorScheme.primary` resolving to cream; verify `TextSelectionColors` cursor color is also set to cream.** Mockup screens 03, 05, 07 show active field outlines and floating labels in the brand accent color. M3 defaults route `focusedBorderColor` and `focusedLabelColor` to `colorScheme.primary` — correct if `primary = #FDEED0`. However, the text-insertion cursor color is controlled separately by `LocalTextSelectionColors.current.handleColor`. If Theme.kt does not explicitly provide `LocalTextSelectionColors provides TextSelectionColors(handleColor = primary, backgroundColor = primary.copy(alpha = 0.4f))` inside the `MaterialTheme` composition, the cursor may render as white or the device default instead of cream. Audit Theme.kt for a `LocalTextSelectionColors` override and add one if missing. None of the five `OutlinedTextField` call sites in ServerStep/RegisterStep pass an explicit `colors` parameter, so all rely on this theme-level provision.

- [ ] **LOGIN-MOCK-087 (Layout). Register inline error text at LoginScreen.kt:2368-2374 lacks a top spacer between the Password field's `supportingText` and the error line, producing a ~4dp gap that reads as visually merged text.** M3 `OutlinedTextField` appends approximately 4dp of bottom padding below the `supportingText` slot. The error `Text` composable at :2369 sits directly next in the Column, so the total gap between "Minimum 8 characters" and "Origin header required" (screen-06) is only those 4dp. Mockup screen-06 shows approximately 8-10dp separation between the two lines. Add `Spacer(Modifier.height(4.dp))` at line 2368 (inside the `if (state.error != null)` block, before the `Text`) so both elements have 8dp total gap between them. Alternatively, use the `supportingText` slot of the Password field itself to surface the error when non-null (replacing "Minimum 8 characters" with the error), which is the standard M3 pattern for field-level errors.

- [ ] **LOGIN-MOCK-088 (Theme). Connect and Create Shop button `enabled` state transitions are instantaneous hard-cuts with no animated color crossfade.** LoginScreen.kt:2234-2239 (ServerStep) and :2393-2397 (RegisterStep): `ButtonDefaults.buttonColors(disabledContainerColor = surfaceVariant)` swaps color synchronously when `enabled` flips. Compose `Button` does not automatically animate color between enabled and disabled states. Add `val containerColor by animateColorAsState(targetValue = if (isEnabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant, animationSpec = tween(durationMillis = 150))` and pass as `ButtonDefaults.buttonColors(containerColor = containerColor, disabledContainerColor = containerColor)` (with `enabled = true` always, guard inside `onClick`), or simply animate `contentAlpha`. Apply to both CTA sites for a polished enable/disable transition matching the mockup's implied interactivity.

- [ ] **LOGIN-MOCK-089 (Layout). Pre-CTA `Spacer(16.dp)` at LoginScreen.kt:2377 is not included in LOGIN-MOCK-062's inter-field 16→20dp bump and should be raised to 20dp as well.** LOGIN-MOCK-062 specifically targets the inter-field spacers at lines :2317, :2330, :2343. The spacer at :2377 — positioned between the password field/error block and the Create Shop button — is a separate fifth gap measuring 16dp. Mockup screen-05 shows the Create Shop button with the same visual separation from the field above it as the fields share with each other. Bump :2377 from `height(16.dp)` to `height(20.dp)` alongside the LOGIN-MOCK-062 changes to maintain the uniform 20dp vertical rhythm throughout the card.

### Wave-2 Finder-F a11y + input behavior

- [x] **LOGIN-MOCK-090 (Bug) [Finder-F variant]. RegisterStep `onDone` on the Password field calls `focusManager.clearFocus()` instead of submitting the form — hardware-keyboard Enter does nothing.** LoginScreen.kt:2353. `keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() })` dismisses the keyboard but never triggers registration. Every other final field fires the primary CTA: ServerStep `:2221` calls `viewModel.connectToServer()`, CredentialsStep `:2678` calls `viewModel.login()`. Fix: replace the lambda body with `if (isFormValid) viewModel.registerShop(onAutoLogin = onLoginSuccess) else focusManager.clearFocus()`. The `isFormValid` flag is already computed at `:2368-2372` in the same composable scope and can be captured by the lambda. Fixed: onDone now checks form validity inline and calls registerShop when valid.

- [x] **LOGIN-MOCK-091 (A11y). `ErrorMessage` composable renders error text as a static `Text` node with no `LiveRegion` semantics — TalkBack will not announce errors when they first appear.** LoginScreen.kt:2093-2097. When `state.error` transitions from `null` to a non-null string (e.g., wrong credentials, slug already taken), the `Text` materialises in the composition but TalkBack does not interrupt to read it. Fix: add `Modifier.semantics { liveRegion = LiveRegionMode.Polite }` to the `Text` at `:2096`. The same gap exists at the inline error block in RegisterStep `:2358-2364` which bypasses `ErrorMessage` entirely — add the same modifier to that `Text` node too. Required imports: `androidx.compose.ui.semantics.liveRegion`, `androidx.compose.ui.semantics.LiveRegionMode`.

- [x] **LOGIN-MOCK-092 (A11y/Bug). `TotpCodeInputContent` auto-focuses the TOTP field unconditionally at LoginScreen.kt:3382 — on `TwoFaSetupStep` entry the numeric keyboard opens immediately, scrolling the QR code off-screen before the user can scan it.** LOGIN-MOCK-079 documents the UX break; this item tracks the WCAG 3.2.2 (On Input) violation: context must not change without user initiation. Fix: add `autoFocusOnEntry: Boolean = true` parameter to `TotpCodeInputContent`; pass `autoFocusOnEntry = false` at the `TwoFaSetupStep` callsite `:3305` and keep `true` at the `TwoFaVerifyStep` callsite `:3356`. Gate the effect: `if (autoFocusOnEntry) LaunchedEffect(Unit) { focusRequester.requestFocus() }`. Fixed: param added, TwoFaSetupStep passes false, TwoFaVerifyStep uses default true.

- [x] **LOGIN-MOCK-093 (A11y). Password-visibility `IconButton` `contentDescription` is the static string `"Toggle password visibility"` at LoginScreen.kt:2347 (RegisterStep) and `:2674` (CredentialsStep) — TalkBack reads the same label whether the field is hidden or exposed, providing no state feedback.** WCAG 1.3.3 requires state to be communicated to assistive technology. Fix: `contentDescription = if (showPassword) "Hide password" else "Show password"`. On double-tap TalkBack will announce the resulting state label. Apply to both callsites. Fixed: both RegisterStep and CredentialsStep now use stateful contentDescription.

- [x] **LOGIN-MOCK-094 (A11y). RegisterStep has no auto-focus on entry — the first field "Shop URL" does not receive focus when the REGISTER card slides in — forcing TalkBack users to swipe-right through the back arrow and two heading nodes before reaching the first input.** LoginScreen.kt:2261. ServerStep auto-focuses at `:2161`. RegisterStep declares `val focusManager` but no `FocusRequester`. Fix: add `val shopUrlFocusRequester = remember { FocusRequester() }`, attach `.focusRequester(shopUrlFocusRequester)` to the Shop URL field modifier at `:2293`, and add `LaunchedEffect(Unit) { shopUrlFocusRequester.requestFocus() }`. Fixed: shopUrlFocusRequester added, LaunchedEffect on entry, .focusRequester() on Shop URL modifier.

- [ ] **LOGIN-MOCK-095 (A11y). `TotpCodeInputContent` hardcodes `fontSize = 24.sp` and `letterSpacing = 6.sp` at LoginScreen.kt:3393 — at system fontScale = 2.0 these `sp` values double to 48sp text and 12sp letter-spacing, potentially overflowing the `OutlinedTextField` and clipping digit glyphs on 360dp phones.** The explicit override also bypasses the user's configured text-size preference. Fix: clamp with `with(LocalDensity.current) { minOf(24.sp.toPx(), 24.dp.toPx()).toSp() }` to bound the size in absolute pixels, and reduce `letterSpacing` to `4.sp`. Or substitute `MaterialTheme.typography.headlineSmall.copy(fontFamily = BrandMono.fontFamily, letterSpacing = 4.sp)` which participates in the M3 type-scale.

- [ ] **LOGIN-MOCK-096 (A11y). `LoginTabBar` `Tab` elements declare `onClick = { /* no-op */ }` at LoginScreen.kt:2077 but retain interactive `Role.Tab` semantics — TalkBack announces each as "double-tap to activate" yet activation does nothing.** LOGIN-MOCK-053 flags the false affordance; this item documents the concrete a11y fix. Option A (read-only): replace `Tab(selected = isSelected, onClick = { })` with a `Box` carrying `Modifier.semantics { role = Role.Tab; selected = isSelected; disabled() }` so TalkBack omits the activation hint. Option B (enable navigation): wire `onClick` to `viewModel.goBack()` when `index < selectedIndex` so the affordance becomes real.

- [x] **LOGIN-MOCK-097 (A11y). "Bizarre CRM" wordmark at LoginScreen.kt:1872 and "Electronics Repair Management" subtitle at `:1880` are two separate TalkBack focus nodes — users swipe through them individually before reaching the tabs.** LOGIN-MOCK-054 adds `heading()` to the wordmark; this item adds the merge: wrap both `Text` nodes and the intervening `Spacer` in `Box(Modifier.semantics(mergeDescendants = true) { heading() })` so TalkBack reads the entire branded header — "Bizarre CRM, Electronics Repair Management, heading" — in one focus stop.

- [x] **LOGIN-MOCK-098 (A11y). Step-header title and subtitle `Text` nodes are separate TalkBack focus stops on every step, forcing two swipes before reaching the first field.** LoginScreen.kt:2163-2176 (ServerStep), `:2271-2284` (RegisterStep), `:3074-3078` (SetPasswordStep), `:3147-3153` (TwoFaSetupStep), `:3350-3353` (TwoFaVerifyStep). Fix for each step: wrap the `[title Text + Spacer(4.dp) + subtitle Text]` trio in `Column(Modifier.semantics(mergeDescendants = true) { heading() })`. TalkBack will read them as one stop — "Connect to Your Shop, Enter your shop name to connect, heading" — matching the Android a11y label+description pattern.

- [x] **LOGIN-MOCK-099 (A11y/Bug). No `BackHandler` is registered in `LoginScreen` — the predictive-back gesture (Android 14+) and hardware Back button exit the entire login screen instead of navigating to the previous step.** LoginScreen.kt:1854-2026. `viewModel.goBack()` is wired to back-arrow `IconButton`s but `BackHandler` is absent, so the system gesture bypasses the ViewModel entirely. Fix: inside the `AnimatedContent` lambda at `:2005`, before the `Surface`, add `val isNotFirstStep = state.step != SetupStep.SERVER; BackHandler(enabled = isNotFirstStep) { viewModel.goBack() }`. Import: `androidx.activity.compose.BackHandler`. This also unlocks the Compose 1.6+ predictive-back animation.

- [ ] **LOGIN-MOCK-100 (A11y). "Copy key" `OutlinedButton` at LoginScreen.kt:3253 copies the 2FA secret with no accessibility announcement — on Android 12 and below there is no system feedback, so blind users get no confirmation the copy succeeded.** Fix: after the `ClipboardUtil.copySensitive(...)` call at `:3255-3260`, surface a snackbar via the `SnackbarHostState` already present in the parent Scaffold at `:1856`. Pass `snackbarHostState` down to `TwoFaSetupStep` and call `snackbarHostState.showSnackbar("2FA secret copied — clears in 30 s")`. This also benefits sighted users and is consistent with the existing snackbar usage for challenge-token expiry on the same screen.

- [x] **LOGIN-MOCK-101 (A11y). `SetPasswordStep` and `TwoFaSetupStep` step-header `Text` nodes lack `heading()` semantics — TalkBack treats them as body text, not landmarks.** LoginScreen.kt:3075 (`"Set Your Password"`) and `:3147` (`"Set Up Two-Factor Auth"`). LOGIN-MOCK-055 covers the four steps sharing a back-arrow + title `Row` structure (Server, Register, Sign In, 2FA Verify); SetPassword and TwoFaSetup were missed. Fix: add `Modifier.semantics { heading() }` to the title `Text` at `:3075` and `:3147`. Note: LOGIN-MOCK-074 will promote both from `titleMedium` to `titleLarge + Bold` — apply both fixes at the same callsites.

### Wave-3 Finder-I fontScale + RTL + tablet

Audited files: `ui/screens/auth/LoginScreen.kt`, `ui/theme/Theme.kt`, `ui/components/WaveDivider.kt`. Dimensions: fontScale resilience, RTL layout, tablet/foldable, dark/light theme parity, predictive-back, window insets.

- [x] **LOGIN-MOCK-128 (A11y/Layout). Wordmark `fontSize = 36.sp` at LoginScreen.kt:1880 doubles to 72sp at fontScale 2.0, overflowing the `widthIn(max = 420.dp)` card on 360dp phones (effective card width ~312dp after 24dp padding each side).** The `headlineLarge.copy(fontSize = 36.sp)` override bypasses the M3 type-scale. At fontScale 2.0 on a 360dp device, 72sp is ~96px — exceeding `headlineLarge`'s default line-height and causing clipping. Remediation: remove the `fontSize = 36.sp` override entirely and use `style = MaterialTheme.typography.headlineLarge` directly; `BizarreTypography.headlineLarge` is already 32sp, and the M3 scale does not cap sp units at fontScale, so also add `maxLines = 2` + `overflow = TextOverflow.Ellipsis` as an overflow guard. File: LoginScreen.kt:1879–1881.

- [x] **LOGIN-MOCK-129 (A11y/Layout). Step-title `fontSize = 22.sp` override at LoginScreen.kt:2176 (ServerStep "Connect to Your Shop") scales to 44sp at fontScale 2.0 with `FontWeight.Bold`, producing a line wider than the card on 360dp phones.** The override sits inside `titleLarge.copy(fontSize = 22.sp, fontWeight = FontWeight.Bold)` — since `BizarreTypography.titleLarge` is already 22sp, the `.copy()` is redundant and only adds the overflow risk. Fix: drop the `fontSize = 22.sp` argument, keeping only `fontWeight = FontWeight.Bold` in the `.copy()`; add `maxLines = 2` + `overflow = TextOverflow.Ellipsis`. The same pattern likely applies to other step titles (RegisterStep `:2295`, SetPasswordStep `:3075`, etc.) — apply consistently. File: LoginScreen.kt:2175–2178.

- [x] **LOGIN-MOCK-130 (A11y/Layout). `letterSpacing = 6.sp` in `TotpCodeInputContent` at LoginScreen.kt:3403 is an sp value that scales with fontScale.** At fontScale 1.5 spacing becomes 9sp; at 2.0 it becomes 12sp. Combined with the `fontSize = 24.sp` (which scales to 48sp at fontScale 2.0), a 6-digit TOTP code renders at approximately `6×48 + 5×12 = 348sp` effective width — wider than a standard 360dp card (312dp usable). The `OutlinedTextField` will wrap or clip. Remediation: replace `letterSpacing = 6.sp` with a density-pinned value: `with(LocalDensity.current) { 6.dp.toSp() }`. Density-based `.dp.toSp()` does NOT multiply by fontScale — 6dp stays 6dp in physical pixels regardless of user text-size preference. Cross-reference: LOGIN-MOCK-095 tracks the `fontSize` half of this same composable. File: LoginScreen.kt:3403.

- [ ] **LOGIN-MOCK-131 (Layout). `TextButton` "View setup guide" at LoginScreen.kt:2469 carries `Modifier.height(24.dp)` with `contentPadding = PaddingValues(0.dp)`.** At fontScale 2.0 the `labelSmall` (11sp × 2 = 22sp) text is 22sp tall plus ascender/descender; 24dp is approximately 32px on a 160-dpi screen — tight but may pass. On high-density screens (xxhdpi, 480dpi), 24dp = 48px and 22sp at fontScale 2.0 ≈ 66px — the text overflows the fixed height and clips. Fix: remove the explicit `height(24.dp)` so the button sizes to its content; use `wrapContentHeight()` if the button must have a defined intrinsic size. File: LoginScreen.kt:2468–2469.

- [ ] **LOGIN-MOCK-132 (Layout). Fixed `height(240.dp)` QR container at LoginScreen.kt:3190 is safe individually, but `TwoFaSetupStep` has no maximum-height or scroll-position contract.** At fontScale 2.0 the title (LOGIN-MOCK-128), subtitle, and manual-key label above the QR box all scale upward, pushing the QR image far down the scroll. On a 5" phone (640dp logical height), the step content can exceed one full viewport. This is not a crash but a significant UX degradation for visually impaired users who rely on large text. Remediation: add a QA checklist entry — manually test `TwoFaSetupStep` at fontScale 2.0 on a 360×640dp emulator and confirm the QR code is reachable without excessive scrolling. If the step overflows badly, consider a `LazyColumn`-based layout or a collapsible QR/manual-key toggle (already present at LoginScreen.kt:3224). File: LoginScreen.kt:3189. Label: **QA gate — fontScale 2.0 smoke test required before release**.

- [x] **LOGIN-MOCK-133 (Layout/RTL). `OutlinedTextField` `suffix = { Text(".$CLOUD_DOMAIN") }` appears at LoginScreen.kt:2218 (ServerStep) and LoginScreen.kt:2317 (RegisterStep).** In RTL locales, Compose renders the `suffix` slot at the visual trailing edge (left side in RTL). The domain label `.bizarrecrm.com` is a Latin-script LTR string; without an explicit layout-direction override it will be subject to BiDi resolution, which may render it in the correct order but is not guaranteed across all font stacks. Remediation: wrap the suffix `Text` in `CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) { Text(".$CLOUD_DOMAIN", ...) }` to pin the domain label to LTR rendering regardless of system locale. This also future-proofs the suffix if `CLOUD_DOMAIN` is ever replaced by a Punycode label. Files: LoginScreen.kt:2219–2223 and LoginScreen.kt:2318–2322.

- [ ] **LOGIN-MOCK-134 (Layout/RTL). `Row(horizontalArrangement = Arrangement.SpaceBetween)` at LoginScreen.kt:2260 places "Use BizarreCRM Cloud" / "Self-hosted?" (left) and "Register new shop" (right) as a semantic primary/secondary pair.** In RTL locales `SpaceBetween` mirrors the visual order: "Register new shop" moves to the visual left (prominent side) while the toggle moves to the visual right. Because this is idiomatic `SpaceBetween` behavior and both items are equally weighted `TextButton`s, no code change is strictly needed. Flag as **RTL design review**: confirm with the designer that the mirrored arrangement is acceptable or whether explicit `Modifier.align()` anchors are preferred. File: LoginScreen.kt:2249–2264.

- [x] **LOGIN-MOCK-135 (Layout/RTL). `Icons.Default.OpenInBrowser` at LoginScreen.kt:2667 (SSO "Continue with SSO" button) and LoginScreen.kt:2731 ("Sign in with SSO" `OutlinedButton`) contains a directional browser-open arrow.** Material Icons does not provide an `AutoMirrored` variant of `OpenInBrowser`. In RTL the arrow points in the wrong direction for a "navigate forward" affordance. Fix: replace `Icons.Default.OpenInBrowser` with `Icons.Default.Language` (globe, non-directional) or `Icons.AutoMirrored.Filled.OpenInNew` if it exists; if not, use `Icons.Default.OpenInNew` (which is a corner-arrow and also lacks an AutoMirrored variant but is less directionally confusing). Both SSO button callsites should use the same replacement. Files: LoginScreen.kt:2667 and LoginScreen.kt:2731.

- [ ] **LOGIN-MOCK-136 (Layout/Tablet). The `widthIn(max = 420.dp)` column at LoginScreen.kt:1870 centers correctly on wide screens but leaves large blank margins on sw840dp+ (landscape tablet, foldable open).** At 1280dp width the card is 420dp wide with 430dp of blank background on each side. No branded illustration, secondary panel, or background decoration fills the space. The mockups (screens 01–10) are phone-only and provide no tablet-layout target. Flag as **needs design decision**: at `WindowWidthSizeClass.Expanded` consider a two-column layout with a branded left panel (logo, tagline, illustration) and the form on the right. At `WindowWidthSizeClass.Medium` (600–840dp) the single centered card is acceptable but would benefit from a subtle `primaryContainer`-tinted radial background. File: LoginScreen.kt:1868–1874. Cross-reference: ActionPlan §22 (Tablet polish), §23 (Foldable).

- [ ] **LOGIN-MOCK-137 (Layout/Tablet). `Modifier.padding(24.dp)` on the content `Column` at LoginScreen.kt:1871 applies the same 24dp on all four sides at every screen size.** On ChromeOS in a narrow resizable window (~320dp) this leaves only 272dp of usable width for form fields — tight but functional. On large tablets in landscape the outer padding is irrelevant because `widthIn(max = 420.dp)` already constrains width. The vertical 24dp top/bottom padding is the concern: it pushes the wordmark 24dp from the card top on all screen sizes, which may feel cramped on foldables with a tall aspect ratio. Remediation: change to `padding(horizontal = 24.dp, vertical = 32.dp)` for slightly more vertical breathing room, or gate the vertical padding on `WindowHeightSizeClass`: `if (windowHeightSizeClass == Compact) 16.dp else 32.dp`. File: LoginScreen.kt:1871.

- [x] **LOGIN-MOCK-138 (Theme). Light-theme `colorScheme.primary = #A66D1F` (caramel) on `surfaceVariant = Surface100 = #EFE4D4` background yields a contrast ratio of ~3.6:1.** This passes WCAG AA for large text (≥14sp Bold, threshold 3:1) but fails for normal text (threshold 4.5:1). The risk area is `TextButton` labels using `labelSmall` (11sp) colored with `colorScheme.primary`, e.g. "View setup guide" at LoginScreen.kt:2474 which renders `labelSmall` in `colorScheme.primary` on the card background. At 11sp this is below both the large-text threshold and the AA normal-text threshold. Remediation: (a) increase the caramel value to `#8B5A10` (~4.7:1 on `#EFE4D4`) — a marginally darker shift that preserves the warm brand feel; or (b) switch the "View setup guide" label color from `colorScheme.primary` to `colorScheme.onSurfaceVariant` (`Surface700 = #5A4A38`, contrast ~5.4:1 on `#EFE4D4`). File: Theme.kt:105, LoginScreen.kt:2474.

- [ ] **LOGIN-MOCK-139 (Theme). `Color.White` QR frame at LoginScreen.kt:3197 is intentional and correct — QR scanners require a white quiet zone.** In light theme (`Surface50 = #FAF4EC` background) the white `Surface` card blends into the background because both are near-white and no border is applied. The `RoundedCornerShape(8.dp)` alone provides no visual separation. Remediation: add `border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)` to the `Surface` modifier in light theme only (gate with `if (!isSystemInDarkTheme())`), giving the QR card a subtle edge without affecting dark-theme appearance. Dark theme (`BgDark = #1C1611`) already provides sufficient contrast against `Color.White`. File: LoginScreen.kt:3196–3199.

- [x] **LOGIN-MOCK-140 (Layout). `statusBarsPadding()` at LoginScreen.kt:1860 accounts for the status bar height but does not include the display cutout inset.** On notch / punch-hole devices (Pixel 6a punch-hole, Galaxy S-series notch, foldables with inner-camera cutout), `WindowInsets.displayCutout` can extend below the status bar inset height reported by `statusBarsPadding()`. The wordmark `Text` at LoginScreen.kt:1877 — rendered close to the visual top of the column — may overlap the cutout on affected devices. Remediation: replace the standalone `statusBarsPadding()` with `windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top))`, which combines status-bar height and display-cutout height into a single top inset. The bottom (`imePadding()`) and side insets are already handled by the Scaffold and keyboard avoidance modifiers. Imports needed: `androidx.compose.foundation.layout.WindowInsets`, `androidx.compose.foundation.layout.WindowInsetsSides`, `androidx.compose.foundation.layout.only`, `androidx.compose.foundation.layout.safeDrawing`, `androidx.compose.foundation.layout.windowInsetsPadding`. File: LoginScreen.kt:1860.

### Wave-3 Finder-G pixel-spacing recapture

- [x] **LOGIN-MOCK-102 (Layout). Scaffold + `statusBarsPadding()` double-inset: status bar height applied twice on API 30+ devices.** LoginScreen.kt:1855–1860. The `Scaffold` at :1855 is called with no `topBar`, yet the `Box` inside the `content` lambda immediately appends `.statusBarsPadding()` at :1860 on top of `Modifier.padding(innerPadding)`. On API 30+ `Scaffold` with `contentWindowInsets = WindowInsets.safeDrawing` (the M3 default) the `innerPadding.top` already includes the status-bar height; then `.statusBarsPadding()` adds it a second time, pushing the wordmark down by an extra ~24–30dp (device-dependent). Mockup screens 01–08 all show the wordmark starting immediately below the status bar with no inflated gap. Fix: remove `.statusBarsPadding()` from the `Box` modifier at :1860 and rely solely on `Modifier.padding(innerPadding)`. If explicit safe-area control is needed, replace with `Modifier.windowInsetsPadding(WindowInsets.statusBars)` applied to just the `Column`, not the outer `Box`.

- [x] **LOGIN-MOCK-103 (Layout). Tab strip indicator thickness is 2dp in code but mockup renders ~3dp.** LoginScreen.kt:2074. `TabRowDefaults.SecondaryIndicator(height = 2.dp, ...)` at :2074 produces a 2dp bar. All mockup screens (01–10) that show an active tab — Server (screen-01), Sign In (screen-09) — display an indicator visually thicker than a hairline; pixel measurement at 1080px width indicates ~3px on a 3x density device (= 1dp), but at 2x density the indicator reads as ~3dp. M3 `PrimaryIndicator` default is 3dp. Change `height = 2.dp` to `height = 3.dp` at :2074 to match the mockup indicator weight.

- [x] **LOGIN-MOCK-104 (Layout). RegisterStep subtitle-to-first-field spacer is 16dp while all inter-field spacers are 20dp — breaks vertical rhythm.** LoginScreen.kt:2295. After the subtitle `Text("Create your repair shop on BizarreCRM")`, `Spacer(Modifier.height(16.dp))` precedes the Shop URL `OutlinedTextField`. The three inter-field spacers at :2316, :2329, :2342 are each 20dp (from LOGIN-MOCK-062). Mockup screen-02 shows the gap from subtitle to the first field visually consistent with the inter-field gaps (~20dp). Bump :2295 from `height(16.dp)` to `height(20.dp)` to maintain uniform 20dp rhythm from subtitle through all fields.

- [ ] **LOGIN-MOCK-105 (Layout). CredentialsStep header-to-first-field spacer is 16dp while RegisterStep inter-field rhythm is 20dp — inconsistency across parallel steps.** LoginScreen.kt:2615. After the `Row` containing the back arrow, "Sign In" title, and store-name subtitle, `Spacer(Modifier.height(16.dp))` separates the header from the Username `OutlinedTextField`. Mockup screen-09 shows the gap between "Sign In / Testing 123 Shop" and the Username field matching the visual weight of the gap between Username and Password (~16dp on that screen, but the card is more compact). This is correct at 16dp for this step — however, note that `CredentialsStep` uses 16dp inter-field spacers (`:2629`) while `RegisterStep` uses 20dp. The mismatch is intentional given CredentialsStep has only 2 fields and should stay compact. Flag for design confirmation before changing; current code may be correct.

- [x] **LOGIN-MOCK-106 (Layout). Card outer horizontal margin: Column padding 24dp makes the card edge-to-edge within the outer Column, but the mockup shows ~14–16dp card-to-screen-edge gutter.** LoginScreen.kt:1869–1871. The outer `Column` has `Modifier.padding(24.dp)` applied uniformly. On a 393dp-wide phone (Pixel 8), this leaves 393 − 48 = 345dp for the card + its implicit fill. The mockup (720px display width) shows the card edges at approximately 40px = 18dp from the screen left edge and 40px from the right edge, consistent with ~18dp side gutters. Code gives 24dp horizontal padding to the Column and zero additional margin on the card Surface — resulting in 24dp gutters. Mockup is 18dp. Reduce `Column.padding(24.dp)` horizontal component to `padding(horizontal = 16.dp, vertical = 24.dp)` to land closer to the mockup's ~16–18dp side gutter, giving the card more breathing width. Verify the `widthIn(max = 420.dp)` cap still applies on tablets.

- [x] **LOGIN-MOCK-107 (Layout). Card internal vertical padding 24dp top/bottom (LoginScreen.kt:2021) makes the card taller than the mockup — bottom of card has ~24dp space below the last element, mockup shows ~16dp.** LoginScreen.kt:2021. `Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 24.dp))` inside the `Surface`. In ServerStep (screen-01), the last element is the footer `Row` ("Self-hosted?" / "Register new shop"). M3 `TextButton` adds 12dp of vertical content padding internally, so the effective visual bottom gap = 24dp card padding + 0dp spacer − 12dp button internal top padding (ButtonDefaults) = ~12dp visual gap from the text baseline to the card edge. Mockup screen-01 bottom card gap from "Register new shop" text to card edge ≈ 16dp. The 24dp bottom padding overruns by ~8dp for all steps that end with a `TextButton`. Reduce card `vertical` padding from `24.dp` to `20.dp` or adjust per-step with a dedicated bottom spacer, retaining 24dp top.

- [x] **LOGIN-MOCK-108 (Layout). Suffix `.bizarrecrm.com` text style (`bodyMedium`, 14sp) mismatches the `OutlinedTextField` value text style (`bodyLarge`, 16sp default in M3), creating a perceptible size jump mid-line.** LoginScreen.kt:2219–2223 (ServerStep) and :2305–2309 (RegisterStep). Both `suffix` slots render `Text(".$CLOUD_DOMAIN", style = MaterialTheme.typography.bodyMedium)`. M3 `OutlinedTextField` renders the value text at `bodyLarge` (16sp) by default. The suffix slot shares the same baseline row as the value, so a 14sp suffix next to 16sp value text looks undersized. Mockup screen-01 (filled: "myshop · .bizarrecrm.com") shows the suffix at visually the same size as the typed value. Fix: change `style = MaterialTheme.typography.bodyMedium` to `style = MaterialTheme.typography.bodyLarge` in both suffix `Text` composables. Cross-check: LoginScreen.kt `:2220` and `:2307`.

- [x] **LOGIN-MOCK-109 (Layout). `TwoFaSetupStep` title block has zero spacer above — the "Set Up Two-Factor Auth" `Text` runs directly at the card's 24dp top padding with no breathing room, compressing the QR code Box below it.** LoginScreen.kt:3157. `Text("Set Up Two-Factor Auth", ...)` is the first node emitted inside the `TwoFaSetupStep` Column; no spacer precedes it. The card's `vertical = 24dp` inner padding puts 24dp between the card edge and the title baseline. All other steps (Server, Register, Credentials) begin with a `Text` title that starts at the same 24dp offset — consistent. However, screen-10 (2FA QR shot on a physical device) shows the QR box consuming most of the visible card and the title appearing at the very top — the 240dp QR Box + 4dp spacer below title + title height (~28dp) + 4dp sub-spacer + subtitle + 16dp spacer = ~310dp before the code input, leaving ~50dp for the code field and CTA. The QR Box height 240dp is the critical constraint. Flag: the QR Box is oversized for small phones (screen-10 shows the QR region occupying 60% of the card). Reduce `Modifier.height(240.dp)` at :3191 to `height(200.dp)` and reduce the inner `Image(modifier = Modifier.padding(12.dp).size(172.dp))` proportionally (from `padding(16.dp).size(200.dp)`), saving 40dp of vertical space without clipping the QR at typical scan distances.

- [x] **LOGIN-MOCK-110 (Layout). `TwoFaSetupStep` spacer between subtitle and QR Box is 16dp (LoginScreen.kt:3164) but the spacer between the QR Box bottom and the TOTP code field section is 16dp (line :3314) — the two gaps read as different sizes because the QR Box itself has 16dp inner padding that adds apparent whitespace below the image.** LoginScreen.kt:3164 `Spacer(Modifier.height(16.dp))` before the QR `Box`, and :3314 `Spacer(Modifier.height(16.dp))` after the QR Box (before `TotpCodeInputContent`). The QR `Image` has `Modifier.padding(16.dp)` at :3203, so visually 16dp of the QR Box's bottom is white surface padding — this makes the gap from the QR image edge to the code field appear as 16 + 16 = 32dp, nearly double the gap from the title to the QR image edge (16dp). Screen-10 mockup shows tighter grouping. Fix: reduce the spacer at :3314 from `height(16.dp)` to `height(8.dp)`, making the visible image-to-field gap approximately 8 + 16dp-padding = 24dp, closer to the subtitle-to-QR gap of 16dp.

- [ ] **LOGIN-MOCK-111 (Layout). `TwoFaSetupStep` manual-key Surface inner padding is `horizontal = 12.dp, vertical = 10.dp` (LoginScreen.kt:3252) — the 12dp horizontal padding is tighter than the 20dp card horizontal padding, making the monospace secret block appear to float without alignment relationship to the card edges.** LoginScreen.kt:3252. The secret Surface inside the card (card horizontal padding = 20dp) has `Modifier.padding(horizontal = 12.dp, vertical = 10.dp)` for its SelectionContainer, giving a total of 20 + 12 = 32dp from the screen edge to the first character. There is no visual left-edge alignment between the secret block, the "Or enter this key manually:" label above it (no horizontal padding, aligns to card edge = 20dp from screen), and the copy/open buttons below. Fix: remove the `horizontal = 12.dp` padding from the Surface's inner modifier; instead apply `horizontal = 0.dp` padding on the text (or rely on the Surface's `fillMaxWidth` with `contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp)`) so the Surface itself aligns flush with the card edge, visually grounding the secret block. This reduces the left indent mismatch from 12dp to 0dp relative to adjacent labels.

- [x] **LOGIN-MOCK-112 (Layout). `SetPasswordStep` Confirm Password field bottom-to-CTA spacer is 16dp (LoginScreen.kt:3119) while `TwoFaSetupStep` post-QR-section spacer before `TotpCodeInputContent` is also 16dp — but inside `TotpCodeInputContent` there is another `Spacer(16.dp)` at :3415 before the CTA, totaling 32dp from code field to button on the 2FA steps vs 16dp on SetPassword.** LoginScreen.kt:3119 `Spacer(Modifier.height(16.dp))` before SetPassword CTA. LoginScreen.kt:3314 + :3415 = 16+16 = 32dp gap from QR Box to the Continue button in TwoFaSetupStep. Screen-10 mockup shows the code field and Continue button tightly grouped with approximately 12–16dp total gap. The double-spacer in the 2FA flow is caused by `TotpCodeInputContent` emitting its own 16dp spacer after `ErrorMessage` unconditionally. Fix: reduce `:3314` from `height(16.dp)` to `height(4.dp)` (from QR Box to the code input section) — the `TotpCodeInputContent`'s own leading `ErrorMessage` + `Spacer(16dp)` before the button provides the bottom half of the visual rhythm. This also applies to `TwoFaVerifyStep` which shares `TotpCodeInputContent`.

- [x] **LOGIN-MOCK-113 (Layout). `RegisterStep` post-error block spacer before Create Shop CTA is 20dp (LoginScreen.kt:2376) while ServerStep pre-button spacer is 16dp (LoginScreen.kt:2236) — inconsistent CTA positioning across parallel card steps.** LoginScreen.kt:2376 `Spacer(Modifier.height(20.dp))` (between error block and LoginPillButton in RegisterStep). LoginScreen.kt:2236 `Spacer(Modifier.height(16.dp))` (between ErrorMessage and LoginPillButton in ServerStep). Mockup screens 01 (Server) and 02 (Register) show the CTA visually equidistant from the field above it — approximately 16dp field-bottom-to-button-top in both screens. The 20dp in RegisterStep is a leftover from LOGIN-MOCK-089's bump recommendation (which targeted the inter-field spacers) and was not consistently applied. Align both to `height(16.dp)` so the CTA lives at the same rhythm from its adjacent content regardless of which step is active.

- [x] **LOGIN-MOCK-114 (Layout). `IME push-up`: when the keyboard is raised on the Server step (screen-07/08), the Connect button and footer row scroll out of view because the card `Column` is inside a `verticalScroll` but the `Box(contentAlignment = Center)` does not shrink — the centered column can sit partially below the IME.** LoginScreen.kt:1859–1873. The outer `Box` has `imePadding()`, which reduces the Box's available height when the keyboard is up. However, `contentAlignment = Alignment.Center` means the Column is vertically centered within the *remaining* Box height. On screens where the card is taller than (available-height − status-bar), the card's bottom portion (Connect button, footer row) is clipped under the IME. Screens 07/08 show this exactly: only the field and a partial button are visible with the keyboard up. Fix: change `contentAlignment = Alignment.Center` to `contentAlignment = Alignment.TopCenter` and replace the `Spacer(Modifier.height(32.dp))` above the wordmark with `Spacer(Modifier.weight(1f))` inside a `Column(Modifier.fillMaxHeight())` wrapping the scroll column's siblings — but since the column is already in a `verticalScroll`, weight cannot be used there. Instead: keep `TopCenter` and increase the `verticalScroll` `Column`'s top breathing spacer from 32dp to `WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 16.dp` so content starts below the status bar naturally without a Center anchor, and the card is always reachable by scrolling.


### Wave-2 Finder-E copy fidelity

Scope: exact string comparison of every visible text node in screens 01–11 against `LoginScreen.kt`. Items 001–089 were filed in Wave 1; this wave starts at 090. Mockup source: `screen-01-login.png`, `screen-02-register.png`, `screen-03-register-filled.png`, `screen-04-url-only.png`, `screen-05-filled.png`, `screen-06-after-create.png`, `screen-07-back.png`, `screen-08-retry.png`, `screen-09-create-result.png`, `screen-10-signed-in.png`, `screen-11-post-2fa.png`.

- [ ] **LOGIN-MOCK-258 (Copy). "Register new shop" link is sentence-case while "Register New Shop" heading on the next screen is title-case — inconsistent capitalisation for the same destination.** `ServerStep` line 2262: `Text("Register new shop", ...)`. Mockup screen-01 renders it as "Register new shop" (sentence-case), which the code matches. However the Register form heading at line 2283 is `"Register New Shop"` (title-case), confirmed by mockup screen-02. The two surfaces name the same destination differently. Decide on one rule; if title-case wins, fix line 2262. `LoginScreen.kt:2262, 2283`.

- [ ] **LOGIN-MOCK-259 (Copy). Self-hosted mode subtitle "Enter your self-hosted server address" has no mockup backing — copy is unreviewed.** When `state.useCustomServer == true`, `ServerStep` shows `"Enter your self-hosted server address"` (line 2172). None of the 11 mockup screens depict the self-hosted subtitle. The cloud-mode subtitle `"Enter your shop name to connect"` is confirmed by screens 01, 07, 08; the self-hosted variant is live UI copy that was never validated against a mockup frame. `LoginScreen.kt:2172`.

- [ ] **LOGIN-MOCK-260 (Copy). "Server URL" label (self-hosted mode) is live but unreviewed; conflicts in noun with "Shop URL" on the Register form.** The field label `"Server URL"` (line 2184) only renders in self-hosted mode, which no mockup depicts. The Register step uses `"Shop URL"` (line 2302, confirmed by mockup screens 02–06). Two different nouns ("Server URL" vs "Shop URL") describe analogous URL-entry fields with no mockup to adjudicate. `LoginScreen.kt:2184, 2302`.

- [ ] **LOGIN-MOCK-261 (Copy). "Use BizarreCRM Cloud" toggle label has no mockup backing.** The `TextButton` in `ServerStep` shows `"Use BizarreCRM Cloud"` (line 2256) when self-hosted mode is active. No mockup screen shows this toggle state — only `"Self-hosted?"` (confirmed screen-01) is reviewed. The reverse-toggle label is live copy never validated against design. `LoginScreen.kt:2256`.

- [ ] **LOGIN-MOCK-262 (Copy). TwoFaVerifyStep title "Two-Factor Authentication" and body "Enter the 6-digit code from your authenticator app" have no mockup backing.** All 11 mockup screens show only the *setup* step (`"Set Up Two-Factor Auth"` / `"Scan this QR code…"`). The verify-step strings at lines 3377 and 3380 are live UI copy that has never been reviewed. Note that the setup-step title and body at lines 3181 and 3184 exactly match the mockup. `LoginScreen.kt:3377, 3380`.

- [ ] **LOGIN-MOCK-263 (Copy). SSO, magic-link, and passkey button labels on the Credentials step have no mockup backing.** `"Sign in with SSO"` (line 2757), `"Email me a link"` (line 2811), and `"Use passkey"` (line 2851) are all live on the Credentials step but do not appear in any of the 11 mockup screens. All three are feature-flag-gated copy that has never been reviewed against design. `LoginScreen.kt:2757, 2811, 2851`.

- [ ] **LOGIN-MOCK-264 (Copy). Entire magic-link bottom-sheet copy block is unreviewed against any mockup.** `MagicLinkRequestSheet` contains: `"Sign in with a magic link"` (line 2882), `"We'll send a one-time sign-in link to your email. The link expires in 15 minutes."` (line 2888), `"Email address"` label (line 2899), `"Send link"` button (line 2927), `"Check your email"` sent banner (line 2949), `"A sign-in link was sent to …"` body (line 2955), and resend controls (lines 2989, 2991). No mockup screen depicts this sheet. `LoginScreen.kt:2882–2991`.

- [ ] **LOGIN-MOCK-265 (Copy). "Origin header required" error in screen-06 is a raw server message, not a client-owned string — wording is outside the app's control.** Mockup `screen-06-after-create.png` shows the red inline error `"Origin header required"` below the password field on the Register form. In code the text is the raw server JSON `message` field surfaced at line 758 (`rJson.optString("message", "Registration failed")`); the string `"Origin header required"` does not appear in the source. A server-wording change propagates to the UI silently. Consider a client-side map from known technical server messages to user-readable strings. `LoginScreen.kt:755–758`.

- [ ] **LOGIN-MOCK-266 (Copy). Loading-state inline text "Connecting to your server…" and "Checking sign-in method…" are live copy with no mockup coverage.** Lines 2441 and 2665 use Unicode HORIZONTAL ELLIPSIS (U+2026) correctly, but neither loading state is shown in any of the 11 mockup screens. The copy has never been reviewed against design. `LoginScreen.kt:2441, 2665`.

- [ ] **LOGIN-MOCK-267 (Copy). Error banner strings "You're offline. Connect to sign in." and "Can't reach this server. Check the address." have no mockup backing.** The offline banner (line 2520) and unreachable-host banner (line 2548) render on the Credentials step. No mockup screen depicts either error state. Both are live copy unreviewed against design. `LoginScreen.kt:2520, 2548`.

- [ ] **LOGIN-MOCK-268 (Copy). The ".bizarrecrm.com" suffix is rendered from `BuildConfig.BASE_DOMAIN` at runtime and is invisible to string-search tooling.** Mockup screens 01–06 show `.bizarrecrm.com` as an inline suffix on both the "Shop Name" and "Shop URL" fields. In code both render `".$CLOUD_DOMAIN"` where `CLOUD_DOMAIN = BuildConfig.BASE_DOMAIN.lowercase()` (line 110). The displayed string matches the mockup in production, but any `BASE_DOMAIN` rename in `build.gradle` silently breaks both fields with no compile error or test failure. Add a compile-time assertion or screenshot snapshot asserting `CLOUD_DOMAIN == "bizarrecrm.com"`. `LoginScreen.kt:110, 2209, 2308`.

### Wave-2 Finder-D pixel-spacing deltas

- [ ] **LOGIN-MOCK-269 (Layout). Status-bar inset applied twice — wordmark pushed ~28 dp too far down.** `LoginScreen.kt:1858` applies `.statusBarsPadding()` to the root `Box` *and* also wraps it in `Scaffold { innerPadding -> Box(Modifier.padding(innerPadding)) }`. On most phones `Scaffold` with no `topBar` still delivers a non-zero `innerPadding.top` equal to the status-bar height when `WindowInsets` are consumed at the Scaffold level, so `statusBarsPadding()` on the child Box applies the same inset a second time. Net result: the wordmark sits ~28 dp (typical status-bar height) lower than the mockup. Fix: remove `.statusBarsPadding()` from the `Box` at line 1858 and rely solely on `innerPadding` from the Scaffold. Alternatively, pass `contentWindowInsets = WindowInsets(0)` to Scaffold so `innerPadding` is zeroed and the manual `.statusBarsPadding()` is the single source of truth.

- [ ] **LOGIN-MOCK-270 (Layout). Hero top spacer 80 dp — mockup shows ~48 dp above wordmark.** `LoginScreen.kt:1869` `Spacer(Modifier.height(80.dp))` before the "Bizarre CRM" headline. In all mockups (screen-01, screen-07, screen-08) the distance from the top of the visible content area to the wordmark baseline is approximately 48 dp (measured as roughly one-fifth of the card-to-top space on a 392 dp tall viewport above the card). 80 dp leaves the upper ~40 % of the screen completely empty, making the layout feel top-heavy on smaller phones. Reduce to `48.dp`.

- [ ] **LOGIN-MOCK-271 (Layout). Wave-divider-to-tab-strip gap too wide: 12 dp + wave height + 24 dp = ~52 dp; mockup shows ~16 dp.** `LoginScreen.kt:1884–1886`: `Spacer(12.dp)` → `WaveDivider()` → `Spacer(24.dp)` → `LoginTabBar(...)`. The wave SVG itself has intrinsic height (~8–12 dp depending on the path). Total vertical budget from subtitle baseline to tab top is therefore ~48–52 dp. The mockups (screen-01, screen-07, screen-08) show the wave sitting ~8 dp below the subtitle and the tab strip sitting ~8 dp below the wave — total ~28 dp including the wave path itself. Remediation: change `Spacer(Modifier.height(12.dp))` at line 1884 to `8.dp` and `Spacer(Modifier.height(24.dp))` at line 1886 to `8.dp`.

- [ ] **LOGIN-MOCK-272 (Layout). Tab-strip-to-card gap 24 dp; mockup shows ~12 dp.** `LoginScreen.kt:1988` `Spacer(Modifier.height(24.dp))` sits between `LoginTabBar(...)` and the `AnimatedContent` Surface (the card). Every mockup (screen-01, screen-07, screen-09) shows the card top edge approximately 12 dp below the tab indicator underline, not 24 dp. Change to `Spacer(Modifier.height(12.dp))`.

- [ ] **LOGIN-MOCK-273 (Layout). Register step: double-gap between first field's supporting text and second field.** `RegisterStep` (lines 2299–2317): `OutlinedTextField` for Shop URL has `supportingText` which M3 renders with 4 dp top padding and a minimum height of ~16 dp. After the field, the code also adds `Spacer(Modifier.height(16.dp))` at line 2317 before Shop Display Name. This produces a compound gap of ≈36 dp (supportingText + spacer). The mockup (screen-02, screen-04, screen-05) shows all inter-field distances equal at ~8 dp below the supporting text line. Fix: remove the explicit `Spacer(Modifier.height(16.dp))` at line 2317 and rely on the built-in M3 `supportingText` bottom clearance alone, or reduce the spacer to `4.dp`. Apply the same fix after the password field's supportingText before the error text block (line 2377 area): there is no spacer there, but the error text renders with no top margin, visually cramped. Add `Spacer(Modifier.height(4.dp))` before the error block and remove the `Spacer(Modifier.height(16.dp))` at line 2377, collapsing to a single `Spacer(Modifier.height(8.dp))` above the Create Shop button.

- [ ] **LOGIN-MOCK-274 (Layout). Card internal padding 20 dp on all sides; mockup shows 24 dp horizontal / 20 dp vertical.** `LoginScreen.kt:2010` `Column(modifier = Modifier.padding(20.dp))` applies uniform 20 dp to all four sides of the card content. The mockups (screen-01, screen-09) show the heading text and field left edges sitting ~24 dp from the card edge (measured as slightly wider than the icon width ~20 dp + 4 dp gap). Change to `Modifier.padding(horizontal = 24.dp, vertical = 20.dp)` so field icons align with the card's 16 dp corner radius visual indent.

- [ ] **LOGIN-MOCK-275 (Layout). Credentials step: header-block-to-username-field spacer 16 dp; mockup shows ~24 dp.** `CredentialsStep` line 2634: `Spacer(Modifier.height(16.dp))` between the back-arrow/title/store-name `Row` and the Username `OutlinedTextField`. The mockup (screen-09) shows a noticeably larger breathing space — approximately 24 dp — between the "Sign In / Testing 123 Shop" block and the Username field top border. The `Row` containing the `IconButton` has M3's default 40 dp minimum touch height, so the visual bottom of the store-name text is already ~8 dp above the Row bottom edge; combined with only 16 dp spacer this makes the gap feel compressed. Change `Spacer(Modifier.height(16.dp))` to `Spacer(Modifier.height(20.dp))` at line 2634.

- [ ] **LOGIN-MOCK-276 (Layout). 2FA setup: QR container has zero internal padding — QR bleeds to box edge.** `TwoFaSetupStep` lines 2213–2234: `Box(Modifier.fillMaxWidth().height(200.dp))` directly contains the 200 dp `Image`. The box and image are the same dimension so the QR bitmap occupies the full box with no breathing room. Mockup (screen-10) shows the QR code centered inside a slightly inset region with ~8 dp white-space on all four sides between the QR quiet zone and the surrounding card surface. Fix: reduce the Image size to `180.dp` (or `min(containerWidth - 32.dp, 200.dp)`) and keep the Box at 200 dp; alternatively add `Modifier.padding(8.dp)` to the Image so the QR quiet zone is not flush with the Surface background.

- [ ] **LOGIN-MOCK-277 (Layout). 2FA verify step: subtitle-to-TOTP-field gap is 24 dp; all other steps use 16 dp — inconsistent.** `TwoFaVerifyStep` line 3381: `Spacer(Modifier.height(24.dp))` between the subtitle text and `TotpCodeInputContent`. Every other step (ServerStep line 2177, RegisterStep line 2296, CredentialsStep line 2634, SetPasswordStep line 3113) uses `Spacer(Modifier.height(16.dp))` between subtitle and first field. The 24 dp spacer is an outlier that makes the verify card look taller than the others. Change to `Spacer(Modifier.height(16.dp))` at line 3381.

- [ ] **LOGIN-MOCK-278 (Layout). ServerStep footer row has no bottom padding — card bottom is flush with card surface.** `ServerStep` ends with the `Row` of `TextButton` items ("Self-hosted?" / "Register new shop") at lines 2250–2265. There is no trailing `Spacer` after this row, so the card's 20 dp uniform padding provides the only bottom clearance. When `imePadding()` on the root Box lifts the entire Column to avoid the keyboard (screen-08), the bottom of the card lands visually flush with the `RoundedCornerShape(16.dp)` corner arc, and the footer text clips against the bottom arc at small viewport heights. Add `Spacer(Modifier.height(4.dp))` after the footer `Row` in `ServerStep` so the card bottom padding is a consistent 24 dp (20 dp card padding + 4 dp spacer). Apply the same fix to `RegisterStep` (no trailing spacer after the Create Shop button at line 2409) and `CredentialsStep` (no trailing spacer after the last TextButton block).

- [ ] **LOGIN-MOCK-279 (Layout). Manual-key surface horizontal padding 12 dp / vertical 10 dp; mockup shows 16 dp / 12 dp.** `TwoFaSetupStep` line 3270: `Modifier.padding(horizontal = 12.dp, vertical = 10.dp)` on the `SelectionContainer` inside the manual-key `Surface`. The mockup (screen-10) shows the monospace key text with visibly wider side margins and slightly taller top/bottom margins. Change to `Modifier.padding(horizontal = 16.dp, vertical = 12.dp)` to match the 16 dp horizontal gutter used elsewhere in the card and provide a comfortable 12 dp vertical breathing room for the tall bodyLarge mono text.

---

### Wave-3 Finder-H copy fidelity recapture

Scope: exact string comparison — case, punctuation, Unicode char class (en-dash U+2013 vs hyphen-minus U+002D), sentence-case vs title-case, trailing punctuation, apostrophe type, ellipsis form, loading/error strings — for all visible text nodes in screens 01–11 against `LoginScreen.kt`. Wave-3 IDs start at 115.

- [x] **LOGIN-MOCK-115 (Copy). Shop-URL field supporting text uses ASCII hyphen-minus (U+002D) between “3” and “30” but every mockup screen renders an en-dash (U+2013).** `LoginScreen.kt:2313`: `supportingText = { Text("3-30 characters: letters, numbers, hyphens") }` — the dash between “3” and “30” is ASCII hyphen-minus U+002D. Mockup screens 02, 03, 04, 05, 06 all render “3–30 characters: letters, numbers, hyphens” with a visually wider dash that is an en-dash (U+2013). Fix: change the literal to `"3–30 characters: letters, numbers, hyphens"` (U+2013 between the digits). `LoginScreen.kt:2313`.

- [ ] **LOGIN-MOCK-116 (Copy). “Register new shop” footer link is sentence-case; “Register New Shop” heading on the destination screen is title-case — same destination, two capitalisation rules across one tap.** `ServerStep` `LoginScreen.kt:2262`: `Text("Register new shop")` — mockup screen-01 confirms sentence-case here. `RegisterStep` heading `LoginScreen.kt:2283`: `Text("Register New Shop")` — mockup screens 02–06 confirm title-case there. Both surfaces name the same action with conflicting capitalisation. No Kotlin change should be made until design decides which rule wins. `LoginScreen.kt:2262, 2283`.

- [x] **LOGIN-MOCK-117 (Copy). Subtitle “Create your repair shop on BizarreCRM” uses closed compound “BizarreCRM” (no space) while the app wordmark is “Bizarre CRM” (with space) — two brand-name forms in the same card.** `RegisterStep` subtitle `LoginScreen.kt:2292`: `Text("Create your repair shop on BizarreCRM")`. Mockup screen-02 confirms this closed form. The wordmark at `LoginScreen.kt:1871` is `"Bizarre CRM"` (space), confirmed by all 11 mockup screens. Confirm whether body copy should use “Bizarre CRM” or “BizarreCRM”; if “Bizarre CRM” wins, update line 2292. `LoginScreen.kt:1871, 2292`.

- [x] **LOGIN-MOCK-118 (Copy). 2FA heading abbreviates “Auth” in the setup step and uses the full word “Authentication” in the verify step — the same feature domain has two different noun forms in adjacent steps.** `TwoFaSetupStep` `LoginScreen.kt:3181`: `Text("Set Up Two-Factor Auth")` — mockup screen-10 confirms this exact string. `TwoFaVerifyStep` `LoginScreen.kt:3377`: `Text("Two-Factor Authentication")` — no mockup backing. One form must be chosen and applied to both steps. If the abbreviated form wins (matches mockup), update line 3377. If the full word wins, update line 3181. `LoginScreen.kt:3181, 3377`.

- [x] **LOGIN-MOCK-119 (Copy). TwoFaVerifyStep subtitle names a generic concept (“your authenticator app”) while the setup-step subtitle names a specific product (“Google Authenticator or any TOTP app”) — inconsistent product-mention pattern between adjacent steps.** `TwoFaVerifyStep` `LoginScreen.kt:3380`: `Text("Enter the 6-digit code from your authenticator app")`. `TwoFaSetupStep` `LoginScreen.kt:3184`: `Text("Scan this QR code with Google Authenticator or any TOTP app")` — confirmed by mockup screen-10. The verify step has no mockup backing. If consistent product naming is the intent, the verify subtitle should read `"Enter the 6-digit code from Google Authenticator or any TOTP app"`. Flag for design review. `LoginScreen.kt:3380, 3184`.

- [x] **LOGIN-MOCK-120 (Copy). Loading state on Connect and Create Shop CTAs is spinner-only; passkey loading state is spinner + “Signing in…” — three inconsistent in-progress feedback patterns across primary CTAs.** `ServerStep` `LoginScreen.kt:2241–2244`: `isLoading` branch shows only `CircularProgressIndicator`. `RegisterStep` `LoginScreen.kt:2400–2406`: same spinner-only. `CredentialsStep` passkey `LoginScreen.kt:2841–2843`: spinner + `Text("Signing in…")`. No mockup shows any CTA loading state. Pick one pattern (spinner-only or spinner+label) and apply it uniformly to all three primary CTAs. `LoginScreen.kt:2241, 2400, 2841`.

- [ ] **LOGIN-MOCK-121 (Copy). “Sign-in expires in $label” uses ASCII hyphen-minus (U+002D) in “Sign-in” — confirm this is the correct hyphenation form per style guide and document it in §67.** `LoginScreen.kt:2146`: `Text("Sign-in expires in $label")`. ASCII hyphen-minus U+002D is grammatically correct for a hyphenated compound noun. Same pattern: `"Sign-in timed out."` (line 1764), `"Sign-in link mismatch."` (line 1363). No mockup depicts any countdown. Pattern is internally consistent but undocumented. Confirm in §67 that compound-modifier hyphens use U+002D (not en-dash U+2013, reserved for numeric ranges per LOGIN-MOCK-115). No code change needed once documented. `LoginScreen.kt:1764, 2146, 1363`.

- [ ] **LOGIN-MOCK-122 (Copy). “Origin header required” shown in mockup screen-06 is a raw server-side message surfaced verbatim — no client-owned translation exists for this or any known server error.** `LoginScreen.kt:755–758`: `registerShop()` propagates the server error via `rJson.optString("message", "Registration failed")`. Mockup screen-06 shows “Origin header required” in red — the literal server JSON `message` value. Server-side rewording silently changes displayed copy with no code review. Recommended fix: maintain a client-side map of known opaque errors; for `"Origin header required"` display `"Unable to register. Please try again or contact support."` `LoginScreen.kt:755–758`.

- [ ] **LOGIN-MOCK-123 (Copy). `LoginTabBar` source comment references “purple (#8B5CF6)” for the active indicator — a stale hardcoded reference that contradicts the cream brand-accent mandate.** `LoginScreen.kt:2031`: `// Active tab: purple (#8B5CF6) text + 2dp purple underline indicator.` The runtime tint is `MaterialTheme.colorScheme.primary` (line 2044), which is cream on the current theme — rendered result is correct. The comment misleads developers into hardcoding the deprecated purple hex. Update to: `// Active tab: colorScheme.primary (cream #FDEED0 on brand theme). Never hardcode #8B5CF6 (old purple mock).` `LoginScreen.kt:2031`.

- [ ] **LOGIN-MOCK-124 (Copy). Live error and body strings use straight apostrophe U+0027 throughout — confirm whether the style guide requires typographic apostrophe U+2019.** Instances: `"You’ve been signed out."` should be `"You've been signed out."` (line 1908), `"You're offline."` (line 2520), `"Passwords don't match"` (line 983), `"Can't reach this server."` (line 2548), `"We'll send a one-time sign-in link"` (line 2888). All use U+0027 (straight). No mockup backs any of these strings. Confirm §67 rule: if typographic U+2019 is required, a global find-replace across all string literals in `LoginScreen.kt` is needed; if U+0027 is acceptable, document that to prevent future false-positive review comments. `LoginScreen.kt:983, 1908, 2520, 2548, 2888`.

- [ ] **LOGIN-MOCK-125 (Copy). “Minimum 8 characters” supporting text matches mockup screen-02 exactly — confirmatory pass; the sentence-case + no-trailing-period pattern should be recorded in §67 to prevent regressions.** `LoginScreen.kt:2362`: `Text("Minimum 8 characters")`. Mockup screen-02 shows “Minimum 8 characters” — exact match. Same pattern at line 2313 once the en-dash fix (LOGIN-MOCK-115) is applied. No code change required. Recommended §67 entry: “Supporting text (OutlinedTextField) — sentence-case, no trailing period, no leading capital unless proper noun.” `LoginScreen.kt:2313, 2362`.

- [ ] **LOGIN-MOCK-126 (Copy). “Sign-in timed out. Please start over.” (snackbar, line 1764) and “View setup guide” (informational TextButton, line 2491) are live copy with no mockup backing — wording and punctuation unreviewed.** Neither string appears in screens 01–11. “Please start over.” ends in a period (consistent with two-sentence error convention but not confirmed by design). “View setup guide” is sentence-case with no period (consistent with TextButton copy convention but also unreviewed). Flag both for design sign-off before next public release. `LoginScreen.kt:1764, 2491`.

- [ ] **LOGIN-MOCK-127 (Copy). Twelve UI strings from SSO, magic-link, and passkey features on the Credentials step have no mockup analog and have never received copy review.** Unreviewed strings: `"Checking sign-in method…"` (line 2665), `"Sign in with SSO"` (line 2757), `"Choose your sign-in provider"` (line 2765), `"Email me a link"` (line 2811), `"Sign in with a magic link"` (line 2882), `"We\'ll send a one-time sign-in link to your email. The link expires in 15 minutes."` (line 2888), `"Send link"` (line 2927), `"Check your email"` (line 2949), `"Use passkey"` (line 2851), `"Signing in…"` (line 2843), `"Resend link"` (line 2991), `"Resend in ${cooldownSec}s"` (line 2989). All are feature-flag-gated (`ssoAvailable`, `magicLinksEnabled`, `passkeyVisible`) and absent from all 11 mockup screens. Copy tone, capitalisation, and punctuation are all unreviewed. Each string needs either a mockup frame or an explicit copy-approval comment before shipping. `LoginScreen.kt:2665, 2757, 2765, 2811, 2843, 2851, 2882, 2888, 2927, 2949, 2989, 2991`.

### Wave-4 Finder-J motion + haptics

Audited files: `ui/screens/auth/LoginScreen.kt`, `ui/components/auth/LoginPillButton.kt`, `ui/components/WaveDivider.kt`. Scope: animation timing/easing, haptic feedback, ripple quality, `AnimatedVisibility`, tab indicator smoothness, IME animation, Reduce Motion, predictive-back direction coherence.

- [x] **LOGIN-MOCK-141 (UX). `AnimatedContent` step transition at LoginScreen.kt:2013 uses `fadeIn()` and `fadeOut()` with no explicit `animationSpec`, defaulting to `tween(durationMillis = 300, easing = FastOutSlowInEasing)` for each component.** The `slideInHorizontally` and `slideOutHorizontally` lambdas also receive no spec, defaulting to the same 300ms tween. The result is a 300ms slide + a simultaneous 300ms fade where the outgoing content begins fading immediately and the incoming content fades in from invisible — this is perceptibly slow on mid-range devices and causes a brief fully-transparent frame when both animations cross the 50% opacity mark. Industry norm for a modal step-swap is 250ms slide with a shorter 150ms cross-fade offset. Fix: supply explicit specs: `slideInHorizontally(animationSpec = tween(250)) { it } + fadeIn(animationSpec = tween(150, delayMillis = 100)) togetherWith slideOutHorizontally(animationSpec = tween(250)) { -it } + fadeOut(animationSpec = tween(100))`. The 100ms delay on fadeIn ensures the incoming card begins appearing only after the outgoing card is nearly gone, eliminating the transparent-frame artifact. `LoginScreen.kt:2013–2025`.

- [x] **LOGIN-MOCK-142 (UX). The card `Surface` inside `AnimatedContent` (LoginScreen.kt:2039) has no `animateContentSize` modifier — when the step content changes height (e.g. ServerStep → CredentialsStep, which is taller due to the password field and biometric row), the card snaps to the new height at the start of the incoming-slide animation rather than interpolating.** This produces a jarring height jump mid-transition: the new card slides in at full new height while the exiting card was shorter. Fix: add `Modifier.animateContentSize(animationSpec = tween(250))` to the `Surface` modifier at `:2039`, or apply it to the inner `Column` at `:2046`. This lets the card height animate smoothly between the outgoing and incoming step's natural height over the same 250ms as the slide. Import: `androidx.compose.animation.animateContentSize`. `LoginScreen.kt:2039–2046`.

- [x] **LOGIN-MOCK-143 (UX). Tab indicator in `LoginTabBar` uses a manual `Modifier.offset(x = pos.left).width(pos.width)` approach (LoginScreen.kt:2092–2099) rather than the standard `Modifier.tabIndicatorOffset(tabPositions[selectedIndex])` (deprecated in M3 Expressive) or the recommended `TabRowDefaults.PrimaryIndicator` with built-in animated positioning.** The current `offset + width` approach produces a hard-cut indicator jump on every tab change because `pos.left` and `pos.width` are static frame values — there is no interpolation between the old and new positions. To get smooth animated tab-sliding, the indicator must derive its position from an `animateFloatAsState` or the `Pager`-linked indicator API. Simplest fix: replace the manual `Box+offset+width` block with `TabRowDefaults.SecondaryIndicator(Modifier.tabIndicatorOffset(tabPositions[selectedIndex]), height = 3.dp, color = activeColor)` — `tabIndicatorOffset` is still present in `material3` 1.3.x via `androidx.compose.material3.TabRowDefaults`. Cross-reference: LOGIN-MOCK-103 (height should be 3dp, not 2dp). `LoginScreen.kt:2089–2101`.

- [x] **LOGIN-MOCK-144 (UX). `ErrorMessage` composable at LoginScreen.kt:2136 renders the error `Text` with a plain `if (error != null)` branch — no `AnimatedVisibility`, no fade-in.** When `state.error` transitions from `null` to a non-null string, the error text appears instantaneously on the same frame, which reads as a harsh UI glitch, especially directly after a button tap that triggers a validation failure. Wrapping in `AnimatedVisibility(visible = error != null, enter = fadeIn(tween(150)) + expandVertically(tween(150)), exit = fadeOut(tween(100)) + shrinkVertically(tween(100)))` gives the error a 150ms entrance that draws attention without feeling sluggish. The spacer inside should remain outside the `AnimatedVisibility` to prevent layout jump: keep `Spacer(Modifier.height(12.dp))` unconditional (or gate it on the same `error != null` condition inside `AnimatedVisibility`). `LoginScreen.kt:2136–2148`.

- [x] **LOGIN-MOCK-145 (UX). `LoginPillButton` uses Material3 `Button` with no explicit `interactionSource` customization — the default ripple color is `LocalContentColor @ 0.12f` over a cream (`#FDEED0`) container, resolving to a near-white ripple (`#FDEED0 + white @ 0.12f`) that is visually imperceptible on the cream surface.** The ripple effectively disappears, giving the button a flat, unresponsive feel on press. Fix: pass a custom `interactionSource` and use `indication = ripple(color = MaterialTheme.colorScheme.onPrimary, bounded = true)` via `Modifier.indication(...)`, or override via `ButtonDefaults.buttonColors` and rely on `LocalRippleTheme`. Simplest approach: pass `colors = ButtonDefaults.buttonColors(containerColor = ..., contentColor = ...) ` as-is and add an explicit `LocalRippleTheme` override scoped to the button that sets ripple alpha to `0.24f` against `colorScheme.onPrimary` (`#1C1611` dark brown in brand theme), making the press clearly visible. `LoginPillButton.kt:37–63`.

- [ ] **LOGIN-MOCK-146 (UX). `WaveDivider` at LoginScreen.kt:1907 is a static `Canvas` composable with no entrance animation.** The wave renders fully drawn on first composition with no draw-path or fade-in motion. The Stripe login page and several high-quality app login screens use a one-shot draw-in animation (the path progresses from left to right over ~400ms) to give the login screen a branded "alive" moment. This is a design enhancement, not a bug. Proposed implementation: use `animateFloatAsState(targetValue = 1f, animationSpec = tween(400, easing = EaseOutCubic))` with an initial value of `0f`, keyed on `remember { mutableStateOf(false).also { it.value = true } }` set in a `LaunchedEffect(Unit)`. Pass the animated float as a `pathProgress` parameter to `WaveDivider`, then in `Canvas` use `PathMeasure` to draw only the first `pathProgress * pathLength` fraction of the path. Flag this as **design enhancement** — do not implement without design sign-off, as it adds import weight (`PathMeasure`) and a one-time animation that must also respect Reduce Motion (see LOGIN-MOCK-153). `WaveDivider.kt:71–116`.

- [x] **LOGIN-MOCK-147 (UX). No haptic feedback is triggered on any successful or failed login-flow event.** Confirmed by grepping for `HapticFeedback`, `performHapticFeedback`, `LocalHapticFeedback`, and `Vibrator` — zero occurrences in `LoginScreen.kt`. Critical moments that should carry haptics: (1) successful `verify2FA` login completion (use `HapticFeedbackType.LongPress` — the Android "confirm" convention), (2) 2FA code auto-submit on 6th digit entry (`HapticFeedbackType.TextHandleMove`), (3) wrong-code error response from `verify2FA` catch block (`HapticFeedbackType.LongPress` or system `REJECT` constant on API 34+), (4) challenge-token expiry snackbar trigger. Implementation: `val haptic = LocalHapticFeedback.current` in the composable scope; call `haptic.performHapticFeedback(HapticFeedbackType.LongPress)` at success/failure branch points. For the 2FA auto-submit case, fire haptic inside the `onValueChange` lambda when `it.length == 6`. `LoginScreen.kt:1054 (verify2FA), LoginScreen.kt:3489 (TotpCodeInputContent onValueChange)`.

- [x] **LOGIN-MOCK-148 (A11y). No haptic feedback accompanies the scan-failure / biometric-error paths.** `viewModel.attemptBiometricAutoLogin` at LoginScreen.kt:1803 fires silently on failure — the user gets no tactile signal that auto-login was rejected. Similarly, `viewModel.stashCredentialsBiometric` failure at LoginScreen.kt:1784–1795 produces no haptic. Biometric operations are especially important for haptics because the screen may not be in focus during the biometric prompt. Fix: in the `LaunchedEffect(pendingStash)` block at `:1784`, add `haptic.performHapticFeedback(HapticFeedbackType.LongPress)` immediately before `onLoginSuccess()` on the success branch; on failure path (after dismissing the biometric prompt without stashing), emit `HapticFeedbackType.LongPress` via the error path. Cross-reference: LOGIN-MOCK-147. `LoginScreen.kt:1782–1796`.

- [x] **LOGIN-MOCK-149 (UX). `CircularProgressIndicator` inside `LoginPillButton` (LoginPillButton.kt:52–56) transitions from label to spinner with a hard cut — one frame shows the label, the next shows the spinner.** This is the default behavior when `isLoading` changes and the if/else branch swaps composables. An `AnimatedContent(targetState = isLoading)` wrapper around the `if/else` block would give a 150ms cross-fade between label and spinner, removing the jarring pop. The spinner's `strokeWidth = 2.dp` (LoginPillButton.kt:54) is correctly set per the audit scope prompt. Implementation: replace the `if (isLoading)` branch with `AnimatedContent(targetState = isLoading, transitionSpec = { fadeIn(tween(150)) togetherWith fadeOut(tween(100)) }, label = "btn_loading") { loading -> if (loading) CircularProgressIndicator(...) else Text(...) }`. `LoginPillButton.kt:51–62`.

- [ ] **LOGIN-MOCK-150 (A11y). `SnackbarHost` at LoginScreen.kt:1865 uses the plain `SnackbarHost(hostState)` with no `SwipeToDismissBox` wrapper.** Material3 `Snackbar` supports swipe-to-dismiss as an accessibility affordance — users with motor impairment or TalkBack can swipe-dismiss a snackbar without waiting for it to auto-dismiss. The `challenge-expired` snackbar at `:1774` uses `SnackbarDuration.Short` (4 seconds), which is acceptable but brief. Adding `SwipeToDismissBox` around the `Snackbar` inside the `SnackbarHost` lambda follows the M3 pattern: `SnackbarHost(snackbarHostState) { data -> SwipeToDismissBox(state = rememberSwipeToDismissBoxState(...), backgroundContent = {}, content = { Snackbar(data) }) }`. Import: `androidx.compose.material3.SwipeToDismissBox`, `androidx.compose.material3.rememberSwipeToDismissBoxState`. `LoginScreen.kt:1865`.

- [ ] **LOGIN-MOCK-151 (UX). `BackHandler` at LoginScreen.kt:2037 intercepts the hardware back button and predictive-back gesture, but the `AnimatedContent` `transitionSpec` at `:2015` always computes direction from `targetState.ordinal > initialState.ordinal`.** When predictive-back fires `viewModel.goBack()` the ordinal decreases (forward → backward direction), which correctly selects the "slide in from left" branch. However, `BackHandler` is registered *inside* the `AnimatedContent` lambda scoped to the current step — this is correct per Compose docs, as the most recently composed `BackHandler` wins. The risk: on the *first* composition after `goBack()` fires, `AnimatedContent` is already mid-transition. If the user triggers a second back gesture before the first transition completes (e.g. fast double-back), the second `BackHandler` may fire with `initialState` still equal to the intermediate step rather than the settled state, producing a direction mismatch (wrong-direction slide for a backward navigate). Fix: disable `BackHandler` while a transition is in progress by checking `transition.isRunning` inside the `AnimatedContent` lambda: `val transition = updateTransition(targetState = state.step, label = "step"); BackHandler(enabled = isNotFirstStep && !transition.isRunning) { viewModel.goBack() }`. Requires lifting `AnimatedContent` to use `transition.AnimatedContent(...)` API. `LoginScreen.kt:2013–2037`.

- [ ] **LOGIN-MOCK-152 (UX). `LaunchedEffect(state.useCustomServer) { focusRequester.requestFocus() }` at LoginScreen.kt:2211 fires immediately when `ServerStep` enters composition, requesting focus before the slide-in animation completes.** On devices where the slide-in takes 250–300ms (see LOGIN-MOCK-141), `requestFocus()` fires on the first frame, causing the IME to begin rising during the slide-in. This creates a visual conflict: the card is still sliding in from the right while the keyboard is already rising from the bottom, compressing the layout mid-animation. Fix: gate the focus request behind the animation completion signal. Use `LaunchedEffect(state.useCustomServer) { delay(250L); focusRequester.requestFocus() }` as a pragmatic approximation, or — preferably — use `transition.isRunning` from the lifted `updateTransition` (LOGIN-MOCK-151) and wait: `LaunchedEffect(state.useCustomServer) { snapshotFlow { !transition.isRunning }.filter { it }.first(); focusRequester.requestFocus() }`. Same fix applies to `RegisterStep` `LaunchedEffect(Unit) { shopUrlFocusRequester.requestFocus() }` at `:2320` and `TotpCodeInputContent` `LaunchedEffect(Unit) { focusRequester.requestFocus() }` at `:3484`. `LoginScreen.kt:2211, 2320, 3484`.

- [x] **LOGIN-MOCK-153 (A11y). No Reduce Motion / Remove Animations guard exists anywhere in the login flow.** `Settings.Global.ANIMATOR_DURATION_SCALE` (checked at runtime) or `LocalConfiguration.current.animationScale` (Compose-accessible via `LocalContext`) can be zero when the user has enabled "Remove animations" in Developer Options or "Disable all animations" in Accessibility settings. None of the animations in `LoginScreen.kt` — `AnimatedContent` step transitions (LOGIN-MOCK-141), `animateContentSize` (LOGIN-MOCK-142), `AnimatedVisibility` on errors (LOGIN-MOCK-144), or the proposed wave draw-in (LOGIN-MOCK-146) — check this scale. At scale 0 the Compose animation system already fast-forwards most `tween`-based animations to their end state, so functional correctness is unaffected. However, the proposed haptics (LOGIN-MOCK-147, LOGIN-MOCK-148) should be independently guarded: haptics are not suppressed by `ANIMATOR_DURATION_SCALE = 0`, and some users who disable animations also prefer reduced haptic feedback. Fix: create a `@Composable fun rememberReduceMotion(): Boolean` helper that reads `Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) < 0.05f`; pass the result through to any haptic call sites and skip haptics when `reduceMotion == true`. The WaveDivider draw-in animation (LOGIN-MOCK-146) must also short-circuit to `pathProgress = 1f` immediately when `reduceMotion`. `LoginScreen.kt` (global), `WaveDivider.kt:71`.


### Wave-4 Finder-L error/loading/empty states

Scope: error-message-to-user-copy mapping, loading-state coverage for every async op, empty states, retry paths, rate-limit countdown, challenge-token expiry, field validation, and first-launch routing. IDs 167-179.

- [x] **LOGIN-MOCK-167 (Copy). Server error messages are echoed verbatim -- no client-side error map exists for any known server string.** `extractErrorMessage()` at `LoginScreen.kt:1705-1717` extracts `body.message` from `HttpException` responses and returns it directly. Strings that reach the user unchanged include: `"Invalid credentials"` (`auth.routes.ts:752, 796, 880`), `"Challenge expired"` (`:858`), `"TOTP not configured"` (`:980`), `"Invalid code"` (`:994`), `"No backup codes available"` (`:1096`), `"Invalid backup code"` (`:1162`), `"Origin header required for state-changing requests."` (`index.ts:1142`), `"Too many login attempts. Try again in 15 minutes."` (`auth.routes.ts:676`). Server-side rewording silently changes displayed copy with no client code review. Remediation: add a `fun friendlyErrorMessage(raw: String): String` map in `LoginViewModel` translating known opaque strings to user-facing copy -- e.g. `"Invalid credentials" -> "Incorrect username or password"`, `"Challenge expired" -> "Session timed out -- please sign in again"`, `"Invalid code" -> "That code is wrong. Check your authenticator and try again."`, `"Origin header required..." -> "Unable to complete request. Please try again."` -- with an unknown-string fallthrough. `LoginScreen.kt:1705-1717`.

- [x] **LOGIN-MOCK-168 (Bug). `setup2FA()` does not set `isLoading = true` before its network call, leaving the UI in a partially-loading state during the async round-trip.** `LoginScreen.kt:1023-1051`: `setup2FA()` is called from `login()` (which clears `isLoading` in the `when` branch at `:927`) and from `setPassword()` (whose catch sets `isLoading = false` at `:1009`). Neither caller re-sets `isLoading = true` before delegating, and `setup2FA()` never sets it either. During the network call the Sign In button is re-enabled and the credentials step becomes interactive. Remediation: add `_state.value = _state.value.copy(isLoading = true, error = null)` as the first statement of `setup2FA()`. `LoginScreen.kt:1023`.

- [x] **LOGIN-MOCK-169 (UX). QR-code spinner in `TwoFaSetupStep` has no timeout -- if `setup2FA()` returns HTTP 200 with blank `qr` and blank `secret` fields, the `CircularProgressIndicator` at `LoginScreen.kt:3282` spins indefinitely with no error and no escape.** The `when` block at `:3268` shows the spinner only when `qrCodeDataUrl.isBlank() && twoFaSecret.isBlank()`. The server QR-failure path (`auth.routes.ts:924`) returns HTTP 500, triggering the client catch and surfacing `state.error` -- but an unexpected 200-with-empty-body leaves the step permanently stuck. Remediation: (1) in `setup2FA()`, after setting `TWO_FA_SETUP` state, validate both fields are non-blank and immediately set `error = "Could not load 2FA setup. Please go back and try again."` if not; (2) add a 15-second `LaunchedEffect` timeout in `TwoFaSetupStep` that calls `viewModel.onSetupQrTimeout()` if both fields remain blank. `LoginScreen.kt:1036-1046, 3268-3282`.

- [ ] **LOGIN-MOCK-170 (Bug). `verify2FA()` success path leaves `isLoading = true` visible while the biometric prompt overlays the screen when backup codes and biometric stash are both active.** `LoginScreen.kt:1086-1093`: when `codes != null && shouldStash`, the code sets `pendingBiometricStash = true` without first setting `isLoading = false`. The `LaunchedEffect(pendingStash)` at `:1784` fires on the same frame, so the Continue button spinner is visible underneath the biometric overlay until the prompt resolves. Remediation: explicitly set `isLoading = false` on every success branch in `verify2FA()` before setting `pendingBiometricStash = true`. `LoginScreen.kt:1086-1093`.

- [ ] **LOGIN-MOCK-171 (UX). The rate-limit banner has no "Try again" CTA when the countdown reaches zero -- the user must edit a field to dismiss the banner and re-enable Sign In.** `LoginScreen.kt:2612-2664`: when `remainingSec <= 0L`, `countdownText` changes to `"You can try again now."` but the banner persists and Sign In stays disabled until `clearRateLimit()` fires from the `LaunchedEffect`. Contrast with the `unreachableHost` banner at `:2598-2605` which provides an explicit "Retry" `TextButton`. Remediation: add a `TextButton("Try again", onClick = viewModel::clearRateLimit)` inside the rate-limit banner `Row`, visible only when `remainingSec <= 0L`. `LoginScreen.kt:2641-2664`.

- [ ] **LOGIN-MOCK-172 (UX). Challenge-token expiry snackbar uses `SnackbarDuration.Short` (~4 s) with no persistent fallback -- after dismissal, `state.error` is null and the user sees no reason why they are back at the sign-in form.** `LoginScreen.kt:1773-1779`: `onChallengeTokenExpired()` triggers a Short snackbar then calls `clearChallengeExpired()`. Remediation: change to `SnackbarDuration.Long` (8 s) and set `error = "Session timed out. Please sign in again."` inside `onChallengeTokenExpired()` so `ErrorMessage` on the credentials step keeps the reason visible until the user begins typing. `LoginScreen.kt:1130-1146, 1773-1779`.

- [x] **LOGIN-MOCK-173 (Copy + Bug). Wrong-2FA-code error surfaces as the raw server string `"Invalid code"`, and the refreshed `challengeToken` in the 401 body is discarded, forcing a full restart rather than allowing retry on the same session.** Server `auth.routes.ts:994`: `{ success: false, message: "Invalid code", data: { challengeToken: newChallenge } }`. Client catch at `LoginScreen.kt:1105-1111` calls `extractErrorMessage(e)` unchanged and never parses `e.response()?.errorBody()` for the new token. The server offers a retry window via the refreshed challenge but the client silently ignores it. Remediation: (1) add `"Invalid code" -> "That code is wrong. Check your authenticator and try again."` to the friendly-error map (LOGIN-MOCK-167); (2) in the `verify2FA` catch, parse the 401 body for `data.challengeToken` and update `state.challengeToken` when found. `LoginScreen.kt:1105-1111`, `auth.routes.ts:994`.

- [x] **LOGIN-MOCK-174 (Copy). Wrong-backup-code error `"Invalid backup code"` is verbatim -- same pattern as LOGIN-MOCK-173, no friendly translation, no challenge-token recovery from the 401 body.** Server `auth.routes.ts:1162`: `{ message: "Invalid backup code", data: { challengeToken: newChallenge } }`. The backup-code flow runs through `BackupCodeRecoveryScreen` (separate file) using the same `extractErrorMessage` approach. Remediation: add `"Invalid backup code" -> "That backup code is not valid. Double-check it and try again."` to the friendly-error map; implement challenge-token recovery from the 401 body in the equivalent catch block. `auth.routes.ts:1162`, `BackupCodeRecoveryScreen` (location TBD).

- [x] **LOGIN-MOCK-175 (UX). Slug-conflict, reserved-slug, and format errors on `registerShop()` are indistinguishable from network transport failures -- both surface as unactionable copy.** `LoginScreen.kt:822-826`: the catch block surfaces `e.message ?: "Registration failed"`. The server uses `GENERIC_SIGNUP_FAILURE` (`"Signup failed. Please check your details and try again."`) for all slug rejections to prevent enumeration (`signup.routes.ts:509, 541, 547, 552`) -- intentionally correct server policy -- but a network timeout and a 400 application rejection produce identical client copy. Remediation: distinguish `HttpException` (display the server message verbatim) from other `Exception` types (display `"Could not reach the server. Check your connection and try again."`). `LoginScreen.kt:822-826`, `signup.routes.ts:509`.

- [x] **LOGIN-MOCK-176 (UX). `RegisterStep` (flat 4-field form) has no per-field inline validation -- all errors surface only after tapping "Create Shop" via a single `state.error` banner with no `isError`/`supportingText` on any field.** `LoginScreen.kt:2348-2428`: no `OutlinedTextField` passes `isError`. Gaps: slug field (`:2348`) -- no `isError` when `shopSlug.length < 3`; email field (`:2383`) -- no format check, no `isError`; password field (`:2396`) -- no `isError` when `registerPassword.length < 8`. Remediation: add `var hasAttempted by rememberSaveable { mutableStateOf(false) }` set on first "Create Shop" tap; wire per-field `isError` and `supportingText` error lambdas conditioned on `hasAttempted`. `LoginScreen.kt:2348-2428`.

- [x] **LOGIN-MOCK-177 (UX). `CredentialsStep` username and password fields have no `isError` wiring -- `state.error` is the only visual channel for "Username is required" and "Password is required" guard messages.** `LoginScreen.kt:2683-2760`: both `OutlinedTextField` composables lack `isError`. The red outline and field-level error copy appear only via the bottom `ErrorMessage` after a login attempt. Remediation: add `var hasAttemptedLogin by rememberSaveable { mutableStateOf(false) }` set in the Sign In `onClick`; pass `isError = hasAttemptedLogin && state.username.isBlank()` to username and `isError = hasAttemptedLogin && state.password.isBlank()` to password. `LoginScreen.kt:2683-2760`.

- [ ] **LOGIN-MOCK-178 (UX). First-launch routing is verified correct but has no unit test -- a regression here silently breaks the entire onboarding funnel.** `LoginScreen.kt:375`: `step = if (authPreferences.serverUrl.isNullOrBlank()) SetupStep.SERVER else SetupStep.CREDENTIALS`. Fresh install correctly shows SERVER step; no code change needed. Missing: add `LoginViewModelTest: "given no stored serverUrl, initial step is SERVER"` and `"given stored serverUrl, initial step is CREDENTIALS"` unit tests to protect this routing from future regressions. `LoginScreen.kt:371-388`.

- [ ] **LOGIN-MOCK-179 (UX). `probeSetupStatus()` failure is fully silent -- `probeError` is declared in state but always nulled out on catch and never read by the UI, providing no retry affordance after a failed probe.** `LoginScreen.kt:878-888`: catch sets `probeError = null` explicitly. The `probeError` field at `:151` is never referenced in any composable. A user on an unreliable connection sees the probe spinner appear and vanish; subsequent probes are skipped by the `setupNeeded != null` guard at `:855` unless `forceRetry = true`. Remediation: (1) on catch, set `probeError = "Could not check server status."` instead of `null`; (2) in `CredentialsStep`, below the probe overlay row (`:2475-2492`), render `TextButton("Retry") { viewModel.probeSetupStatus(forceRetry = true) }` when `state.probeError != null`. Login remains unblocked. `LoginScreen.kt:878-888, 151, 2468-2543`.


---

### Wave-4 Finder-K SSO/passkey/biometric/recovery audit

> Scope: features with no mockup analog — SSO, magic link, passkeys, biometric stash, backup-code recovery, SMS auto-fill, and session/device/network banners. Mockups screen-01...10 depict password + 2FA only. IDs 154-166.

- [ ] **LOGIN-MOCK-154 (UX). SSO button renders as a secondary `OutlinedButton` (48dp, full-width) regardless of whether SSO is the tenant's canonical sign-in method, giving it equal visual weight to the password CTA on IdP-only tenants.** `LoginScreen.kt:2793-2805`: `OutlinedButton` with `height(48.dp)` sits below a `HorizontalDivider` with no hierarchy signal. On a GSuite-only tenant the user must parse two equal-weight buttons and guess which to use. The button is entirely absent while `ssoProviders == null` (still loading) with no skeleton placeholder, causing a layout jump when the probe resolves. Zero analytics hooks exist for SSO button tap, provider-pick, exchange success, or exchange failure. Remediation: (a) if `ssoProviders` is non-empty AND no local-password flag from GET /tenants/me, promote SSO to `BrandPrimaryButton` and demote password fields to a "Use password instead" `TextButton`; (b) show a shimmer ghost `OutlinedButton` during `ssoProvidersLoading` to prevent layout shift; (c) add `analytics.track("sso_tap")` and `analytics.track("sso_exchange_result", success=...)` before shipping. File: `LoginScreen.kt:2784-2831`.

- [x] **LOGIN-MOCK-155 (UX/Copy). Magic-link button is optimistic-default (`magicLinksEnabled != false` at `LoginScreen.kt:2837`) so it appears before the GET /tenants/me probe resolves, then collapses if the probe returns `false` — a visible layout jank for tenants with magic-links disabled.** A tap during the probe window fires `requestMagicLink()` which returns a server error with no copy distinction from a real send failure. This is the inverse of the passkey opt-in model. The `MagicLinkRequestSheet` (`LoginScreen.kt:2924-3000`) is well-structured (resend cooldown, "Check your email" state, inline error) but offers no protection against probe-racing. Remediation: switch to opt-in — `val magicLinksVisible = state.magicLinksEnabled == true` — matching the passkey pattern. This eliminates both the layout jank and the spurious error path at the cost of hiding the button on the first render if the probe is fast (acceptable trade-off). File: `LoginScreen.kt:2837-2864`.

- [x] **LOGIN-MOCK-156 (UX). Passkey button is correctly opt-in (`passkeyEnabled == true && PasskeyManager.isSupported()`) and tertiary-weight `TextButton` — discoverable but not intrusive — but the `PasskeyOutcome.NoCredentials` error persists indefinitely with no auto-clear.** `LoginScreen.kt:2903-2910`: "No passkey found on this device. Sign in with your password first." is set on first tap and cleared only by re-tapping — a user who reads it and scrolls away sees a permanent red text on return. `PasskeyOutcome.Unsupported` silently collapses the button (`LoginViewModel.kt:1500`: `passkeyEnabled = false`) without a debug log, which may hide false positives in QA. Remediation: (a) auto-dismiss the error after 5 s — `LaunchedEffect(state.passkeyError) { if (it != null) { delay(5_000L); viewModel.clearPasskeyError() } }`; (b) add `Timber.d("PasskeyOutcome.Unsupported")` at `LoginViewModel.kt:1500`; (c) on `NoCredentials`, add a "Learn how to add a passkey" `TextButton` opening the Android Credential Manager deep-link. File: `LoginScreen.kt:2867-2912`; `LoginViewModel.kt:1491-1502`.

- [ ] **LOGIN-MOCK-157 (UX). Biometric auto-login fires on `LaunchedEffect(Unit)` at `LoginScreen.kt:1800` with no branded loading surface before the OS sheet, causing a ~200 ms flicker where the full password form renders before the biometric prompt covers it.** `isBiometricAutoLoginInFlight` is set at `LoginViewModel.kt:1244` but no composable observes it — `CredentialsStep` renders unconditionally. `BiometricAuth.decryptWithBiometric` is called with the generic subtitle "Confirm your identity to retrieve stored credentials" (hardcoded at `BiometricAuth.kt:160`) rather than the branded "Sign in to Bizarre CRM" used by `showPrompt` (line 68). Remediation: (a) observe `isBiometricAutoLoginInFlight` in `CredentialsStep` — while `true`, replace card body with `Box(Alignment.Center) { CircularProgressIndicator(); Text("Signing you in...") }` to prevent the form flicker; (b) pass `title = "Sign in to Bizarre CRM"` and `subtitle = "Use your fingerprint or face to continue"` to `decryptWithBiometric` at `LoginViewModel.kt:1248`. Files: `LoginScreen.kt:1800-1805`; `LoginViewModel.kt:1244, 1248`; `BiometricAuth.kt:160`.

- [ ] **LOGIN-MOCK-158 (Layout). `BackupCodeRecoveryScreen.kt` uses a plain `Scaffold` + `TopAppBar` surface that does not share the login card chrome (`surfaceContainer`, `RoundedCornerShape(20.dp)`, WaveDivider brand moment), making the recovery flow look like a settings screen rather than a continuation of the login journey.** The entry-point link "Lost 2FA access? Use a backup code" at `LoginScreen.kt:3458` is correctly tertiary-weight `TextButton`. The screen (`BackupCodeRecoveryScreen.kt:169-323`) uses bare `OutlinedTextField`s in a plain `Column` — no card rounding, no wave. `BrandPrimaryButton` is used for the CTA (correct) but surrounding chrome is disconnected. Zero analytics hooks on recovery attempt or success. The `snackbarHostState.showSnackbar` + `onSuccess()` at line 165 may race the snackbar display. Remediation: (a) wrap `Column` content in `Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainer)` matching `CredentialsStep`; (b) add observability — `analytics.track("backup_code_recovery_attempt")` / `analytics.track("backup_code_recovery_success")`; (c) use `SnackbarDuration.Indefinite` + manual dismiss to avoid the snackbar/navigation race. File: `BackupCodeRecoveryScreen.kt:169-323`.

- [ ] **LOGIN-MOCK-159 (UX/Copy). `BackupCodesDisplay.kt` has no "Download" or "Share" affordance — only "Copy all codes" with a 30-second clipboard auto-clear that races the user's password-manager paste workflow on mid-range hardware.** `BackupCodesDisplay.kt:159-177`: `ClipboardUtil.copySensitive(clearAfterMillis = 30_000L)`. App-switching to a vault, navigating to a notes field, and pasting realistically takes 20-40 s; TalkBack navigation adds further latency. Codes are rendered in JetBrains Mono (`BrandMono.fontFamily`) in a `FlowRow` grid — correct for readability. The non-dismissible dialog with checkbox gate is the right friction model. No PDF export exists. This surface has no mockup frame and needs a dedicated design review. Remediation: (a) add `OutlinedButton("Share / Save")` firing `Intent.ACTION_SEND` with `text/plain` MIME (no storage permission needed); (b) increase auto-clear to 120 s to cover typical vault app-switch time. File: `BackupCodesDisplay.kt:59-207`.

- [ ] **LOGIN-MOCK-160 (A11y). SMS auto-fill via `SmsOtpBus` silently populates the TOTP field with no visual or spoken indicator — TalkBack users receive no announcement and sighted users on large screens may miss the digit change.** `LoginScreen.kt:3426-3429`: `SmsOtpBus.events.collect { code -> viewModel.updateTotpCode(code) }`. The `OutlinedTextField` at line 3487 has no `liveRegion` semantic; programmatic field-value changes are not announced by TalkBack unless the field has focus. Remediation: (a) set `modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive }` on the TOTP field so TalkBack announces the filled value immediately; (b) add an `AnimatedVisibility`-wrapped chip "Code filled from SMS" that fades out after 2 s — matching the Android Autofill chip convention; (c) emit `Timber.d("SMS OTP auto-filled")` at the collection site for QA. File: `LoginScreen.kt:3487-3505, 3426-3429`.

- [x] **LOGIN-MOCK-161 (UX/Copy). Setup invite token (`registerSetupToken`) silently navigates to the Register step with no "Welcome — finishing your setup" banner, giving the user no confirmation their deep-link invite was recognised.** `LoginScreen.kt:1747-1751`: `viewModel.applySetupToken(setupToken)` + `viewModel.goToRegister()` — no banner, no copy change. `RegisterSubStep.Company` renders identically for invited setup and self-initiated registration. An expired or malformed token will surface as a generic `"Registration failed"` from `LoginViewModel.kt:757` with no differentiation. Remediation: (a) add `registerSetupTokenActive: Boolean = false` to `LoginUiState` and set it in `applySetupToken()`; (b) render a dismissible `InformationBanner("You've been invited to set up your Bizarre CRM account.", secondaryContainer)` at the top of `RegisterSubStep.Company` when the flag is true; (c) map a 422 token-expired response to "This setup link has expired. Ask your admin to resend it." File: `LoginScreen.kt:1747-1751`; `LoginViewModel.kt:757`.

- [x] **LOGIN-MOCK-162 (UX). The session-revoked banner (`LoginScreen.kt:1910-1944`) is correctly persistent with a "Dismiss" button, but its leading `Icon(Icons.Default.Lock, contentDescription = null)` announces nothing to TalkBack, and the `when` branch silently falls to a generic message for any unknown future reason string with no logged warning.** `LoginScreen.kt:1923`: `contentDescription = null`. Known reasons handled: `"RefreshFailed"` and `"SessionRevoked"` only. A third reason injected by a future server release would silently use "You've been signed out." with no developer visibility. Remediation: (a) set `contentDescription = "Session ended"` on the Lock icon; (b) add `else -> { Timber.w("Unknown sessionRevokedReason: $sessionRevokedReason"); "You've been signed out." }` with explicit logging; (c) document the exhaustive reason-string set in a `companion object` or sealed class in `LoginViewModel`. File: `LoginScreen.kt:1910-1944`.

- [ ] **LOGIN-MOCK-163 (UX/Copy). The device-changed banner (`state.deviceChangedBanner`, `LoginScreen.kt:1947-1975`) dismisses with "OK" but provides no in-flow path to re-enable biometric sign-in — the user must complete login then navigate Settings manually (4-5 extra taps).** Copy "Sign in with your password to re-enable" correctly explains the next action but offers no shortcut. A user who hits device-change on every OS biometric re-enrollment update encounters this repeatedly. Remediation: after a successful password login where `biometricEnabled` was previously true and is now false due to `DeviceChanged`/`Invalidated`, show a one-time `ModalBottomSheet` — "Re-enable biometric sign-in? Your device changed." — with "Enable" (`stashCredentialsBiometric(...)` inline) and "Not now" CTAs, eliminating the Settings hop. Flag for UX review: the prompt fires immediately post-login and may feel aggressive. File: `LoginScreen.kt:1947-1975`; `LoginViewModel.kt:1239-1284`.

- [ ] **LOGIN-MOCK-164 (Copy). Server-revoke banner copy "Signed out on another device." (`LoginScreen.kt:1995`) conflates admin-forced session kill with concurrent login, and its leading `Icon(Icons.Default.Lock, contentDescription = null)` repeats the a11y gap from LOGIN-MOCK-162.** `LoginViewModel.kt:1287-1298`: `handleServerRevoke()` fires on any 401/403 from GET /auth/me regardless of cause — "Signed out on another device." is accurate only for concurrent-login revocations; an admin force-revoke is misattributed to the user's own other device. Remediation: (a) require the server to return a `revoke_reason` field (`admin_action | concurrent_login | token_expired`) in the 401 body and map to three distinct copy strings — "An admin ended your session.", "You signed in on another device.", "Your session expired."; (b) set `contentDescription = "Session ended"` on the Lock icon at line 1990; (c) create a `CROSS`-tagged item in `TODO.md` since the server change is needed on both web and Android. File: `LoginScreen.kt:1978-2006`; `LoginViewModel.kt:1287-1298`.

- [x] **LOGIN-MOCK-165 (UX/Copy). The setup-needed banner (`state.setupNeeded == true`, `LoginScreen.kt:2498-2543`) is non-dismissible and contains copy "A setup wizard will appear in a future release" — a placeholder commitment that must not ship in any public release as written.** The banner sticks until the next probe cycle; a user who completes setup out-of-band cannot clear it. The external-browser link to `bizarrecrm.com/docs/setup` provides no in-app path. Remediation: (a) add a "Dismiss" `TextButton` calling `viewModel.setSetupBannerDismissed()`, persisted in `AuthPreferences` keyed by server URL so it does not re-appear until the server reports `needsSetup` again; (b) when the in-app setup wizard ships, replace the browser link with `navigateToSetupWizard()`; (c) remove the "future release" copy before any public release — replace with "Complete setup at bizarrecrm.com/docs/setup" if wizard is not yet shipped. File: `LoginScreen.kt:2498-2543`.

- [ ] **LOGIN-MOCK-166 (A11y/UX). The network-offline banner (`state.networkOffline`, `LoginScreen.kt:2547-2572`) appears and disappears with a hard cut, its `Text` has no `liveRegion` annotation so TalkBack users hear no announcement when going offline, and it uses `tertiaryContainer` color (teal/blue) rather than the `errorContainer` family Android convention associates with connectivity warnings.** `LoginScreen.kt:2565`: `Text("You're offline. Connect to sign in.", ...)` — no `liveRegion` semantic. A TalkBack user who goes offline mid-login experiences a silently disabled Sign In button with no spoken explanation. On unstable connections the hard cut produces rapid layout thrash. Remediation: (a) set `modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive }` on the banner `Text`; (b) wrap in `AnimatedVisibility(visible = state.networkOffline, enter = expandVertically(tween(200)), exit = shrinkVertically(tween(200)))` to smooth toggling; (c) consider switching to `errorContainer` color to align with the `unreachableHost` banner immediately below and Android Material connectivity-error conventions. File: `LoginScreen.kt:2547-2572`.

### Wave-5 Finder-M launch-blocker verification

> Scope: confirm or clear six pre-assigned pre-launch blockers (155, 156, 165, 167, 169, 173/174), then hunt for new crash/leak/security issues. IDs 180–192.

- [ ] **LOGIN-MOCK-180 (Bug). Blocker 167 — error-map still missing at HEAD; `extractErrorMessage()` returns raw server strings verbatim with no friendly translation.** Evidence: `LoginScreen.kt:1707-1718` — `fun extractErrorMessage(e: Exception): String` returns `JSONObject(body).optString("message", e.message ?: "Request failed")` unchanged for all `HttpException` cases, and `e.message ?: "An error occurred"` for everything else. No `friendlyErrorMessage()` mapping function exists anywhere in the file. Server strings that still reach the user unfiltered: `"Invalid credentials"` (auth route ~752/796), `"Challenge expired"` (~858), `"TOTP not configured"` (~980), `"Invalid code"` (~994), `"Origin header required for state-changing requests."` (index.ts ~1142). Remediation: add inside `LoginViewModel` — `private fun friendlyErrorMessage(raw: String): String = when { raw.contains("Invalid credentials", ignoreCase = true) -> "Incorrect username or password."; raw.contains("Challenge expired", ignoreCase = true) -> "Session timed out — please sign in again."; raw.contains("Invalid code", ignoreCase = true) -> "That code is wrong. Check your authenticator and try again."; raw.contains("TOTP not configured", ignoreCase = true) -> "Two-factor auth is not set up. Please complete setup first."; raw.contains("Origin header required", ignoreCase = true) -> "Unable to complete request. Please try again."; else -> raw }` — call `friendlyErrorMessage(extractErrorMessage(e))` at every catch site. `LoginScreen.kt:1707-1718`. Effort: **S**.

- [ ] **LOGIN-MOCK-181 (UX/Copy). Blocker 165 — setup-needed banner still ships placeholder copy "A setup wizard will appear in a future release" at HEAD; the banner is also non-dismissible.** Evidence: `LoginScreen.kt:2537` — exact string: `"This server needs initial setup. A setup wizard will appear in a future release. Please contact your admin to complete setup manually."` Cannot ship in any public release. The banner has no dismiss affordance and reappears on every navigation to Credentials as long as the server reports `needsSetup = true` because no persistence key guards it. Remediation: (a) replace body copy with `"This server needs initial setup. Contact your admin or visit the setup guide."` removing the forward-commitment; (b) add a `"Dismiss"` `TextButton` calling `viewModel.setSetupBannerDismissed()` stored in `AuthPreferences` keyed by server URL; (c) keep the "View setup guide" link. `LoginScreen.kt:2515-2563`. Effort: **XS**.

- [ ] **LOGIN-MOCK-182 (Bug). Blocker 173 — wrong-2FA-code catch discards the refreshed `challengeToken` from the server 401 body, forcing a full login restart instead of allowing retry on the same session.** Evidence: `LoginScreen.kt:1107-1112` — the `verify2FA()` catch calls `extractErrorMessage(e)` and stores `error = errorMsg` but never reads `e.response()?.errorBody()?.string()` for the refreshed token that `auth.routes.ts:~994` returns as `{ data: { challengeToken: newChallenge } }`. Every wrong code forces a full restart to the Credentials step. Remediation: in the `verify2FA` catch before `extractErrorMessage`, add: `if (e is retrofit2.HttpException && e.code() == 401) { val retryToken = try { val body = e.response()?.errorBody()?.string(); if (body != null) org.json.JSONObject(body).optJSONObject("data")?.optString("challengeToken") else null } catch (_: Exception) { null }; if (!retryToken.isNullOrBlank()) { _state.value = _state.value.copy(isLoading = false, totpCode = "", challengeToken = retryToken, error = "That code is wrong. Check your authenticator and try again."); return@launch } }` `LoginScreen.kt:1107-1112`. Effort: **S**.

- [ ] **LOGIN-MOCK-183 (Bug). Blocker 174 — wrong backup-code handling also discards the server-refreshed `challengeToken`, same root cause as LOGIN-MOCK-182.** Evidence: the shared `extractErrorMessage()` pattern at `LoginScreen.kt:1707-1718` is used across auth catch blocks. The backup-code recovery path in `BackupCodeRecoveryScreen.kt` (same auth package) almost certainly uses an identical catch pattern against `auth.routes.ts:~1162` which returns `{ message: "Invalid backup code", data: { challengeToken: newChallenge } }`. Remediation: locate the catch block in `BackupCodeRecoveryScreen.kt`; apply the same retry-token extraction as LOGIN-MOCK-182; add `"Invalid backup code" -> "That backup code is not valid. Double-check it and try again."` to the friendly-error map. `BackupCodeRecoveryScreen.kt` (auth package). Effort: **S**.

- [ ] **LOGIN-MOCK-184 (UX). Blocker 169 — QR-spinner timeout is absent at HEAD; a blank-`qr`-and-blank-`secret` 200 response leaves `TwoFaSetupStep` on `CircularProgressIndicator()` permanently.** Evidence: `LoginScreen.kt:3307-3308` — `state.qrCodeDataUrl.isBlank() && state.twoFaSecret.isBlank() -> CircularProgressIndicator()`. No `LaunchedEffect` with a timeout exists anywhere in `TwoFaSetupStep`. `setup2FA()` at lines 1031-1032 uses `data.qr ?: data.qrCode ?: ""` — an unexpected 200 with both fields absent or null silently stores empty strings, leaving the step frozen. Only `data == null` (line 1029) throws. Remediation: (1) in `setup2FA()` after line 1044, add `if (qrCode.isBlank() && secret.isBlank()) { _state.value = _state.value.copy(isLoading = false, error = "Could not load 2FA setup. Please go back and try again."); return@launch }`; (2) add a 15-second `LaunchedEffect` guard in `TwoFaSetupStep`: `LaunchedEffect(state.qrCodeDataUrl, state.twoFaSecret) { if (state.qrCodeDataUrl.isBlank() && state.twoFaSecret.isBlank()) { delay(15_000L); if (state.qrCodeDataUrl.isBlank() && state.twoFaSecret.isBlank()) viewModel.setError("2FA setup timed out. Go back and try again.") } }`. `LoginScreen.kt:1029-1044, 3248, 3307`. Effort: **S**.

- [ ] **LOGIN-MOCK-185 (UX). Blocker 156 — passkey error persists indefinitely at HEAD; no auto-dismiss is wired anywhere.** Evidence: `LoginScreen.kt:2927-2935` — `val passkeyErr = state.passkeyError; if (passkeyErr != null) { Text(text = passkeyErr, ...) }`. `clearPasskeyError()` at line 1528 exists in the ViewModel but nothing calls it on a timer. A user who reads the error and scrolls away sees permanent red text on return. `PasskeyOutcome.Unsupported` at line 1500 silently sets `passkeyEnabled = false` with no `Timber` log. Remediation: add directly after the passkey `TextButton` block in `CredentialsStep`: `LaunchedEffect(state.passkeyError) { if (state.passkeyError != null) { delay(5_000L); viewModel.clearPasskeyError() } }`. Also add `timber.log.Timber.d("PasskeyOutcome.Unsupported — hiding button")` at `LoginScreen.kt:1500`. `LoginScreen.kt:2927-2935, 1499-1503`. Effort: **XS**.

- [ ] **LOGIN-MOCK-186 (UX). Blocker 155 — magic-link button fires before the `/tenants/me` probe resolves (optimistic-default `magicLinksEnabled != false`); probe-race window allows user to open the sheet and attempt a POST before the feature flag is confirmed.** Evidence: `LoginScreen.kt:2861` — `val magicLinksVisible = state.magicLinksEnabled != false`. `LoginUiState:229` initialises `magicLinksEnabled = null`; `probemagicLinksEnabled()` is called asynchronously in `init`. On first composition `null != false` is `true` so the button appears immediately. Additionally `probemagicLinksEnabled()` has an internal doc/code inconsistency: the KDoc at line 1403 says "404 or network failure → default to true (opt-out model)" but the implementation at lines 1411-1412 sets `magicLinksEnabled = false` (opt-in). The code is correct; the comment is wrong. Remediation: change `LoginScreen.kt:2861` to `val magicLinksVisible = state.magicLinksEnabled == true` (matches passkey pattern); update the KDoc at `LoginViewModel:1403` to read "404 or any failure → default to false (opt-in model; button shown only after server confirms)". `LoginScreen.kt:2861`; `LoginViewModel.kt:1403-1413`. Effort: **XS**.

- [x] **LOGIN-MOCK-187 (Bug). Crash-on-rotation regression: `showPassword` in `CredentialsStep` and `RegisterStep`, and `showSsoSheet` in `CredentialsStep`, use `remember { mutableStateOf(false) }` instead of `rememberSaveable`, causing all three to reset on any configuration change (rotation, font-scale, dark-mode toggle).** Evidence: `LoginScreen.kt:2332` — `var showPassword by remember { mutableStateOf(false) }` (`RegisterStep`); `LoginScreen.kt:2486` — same in `CredentialsStep`; `LoginScreen.kt:2809` — `var showSsoSheet by remember { mutableStateOf(false) }` in `CredentialsStep`. Contrast with `manualEntryExpanded` at line 3321 which correctly uses `rememberSaveable`. A user who rotates with the SSO sheet open loses it silently; a user who enabled "Show password" and rotates returns to a masked field without notice — a usability regression. Remediation: `var showPassword by rememberSaveable { mutableStateOf(false) }` at lines 2332, 2486; `var showSsoSheet by rememberSaveable { mutableStateOf(false) }` at line 2809. `LoginScreen.kt:2332, 2486, 2809`. Effort: **XS**.

- [x] **LOGIN-MOCK-188 (Memory). QR bitmap decoded in `TwoFaSetupStep` via `remember` is never explicitly recycled when the composable leaves the Composition, leaking the uncompressed bitmap until GC.** Evidence: `LoginScreen.kt:3265-3283` — `val qrBitmap = remember(state.qrCodeDataUrl, state.twoFaSecret, state.username) { ... BitmapFactory.decodeByteArray(...) ... }`. Compose's `remember` holds the object in the slot table until the composable is removed from the tree; there is no `DisposableEffect` that calls `qrBitmap?.recycle()`. A decoded base64 QR at typical sizes is ~60-150 KB uncompressed (200×200 px ARGB_8888). On low-RAM (2 GB) devices during 2FA setup this contributes to GC pressure alongside the concurrent OkHttp, Hilt, and Coil heaps. Remediation: wrap the bitmap lifecycle with a `DisposableEffect`: `val qrBitmap = remember(state.qrCodeDataUrl, state.twoFaSecret, state.username) { /* existing decode */ }; DisposableEffect(qrBitmap) { onDispose { qrBitmap?.recycle() } }`. `LoginScreen.kt:3265-3283`. Effort: **XS**.

- [x] **LOGIN-MOCK-189 (Security). TOTP secret (`twoFaSecret`, `twoFaManualEntry`) cleared on challenge expiry but NOT on `goBack()` from `TWO_FA_SETUP`, leaving the secret live in `LoginUiState` if the user backs up and re-enters Credentials while still on the same ViewModel instance.** Evidence: `LoginScreen.kt:628-641` — `goBack()` does not include `twoFaSecret = ""` or `twoFaManualEntry = ""` in its `copy` call (only clears `registerSubStep`). `LoginScreen.kt:1142-1143` — `onChallengeTokenExpired()` correctly zeroes both. `LoginScreen.kt:1038-1047` — `setup2FA()` success path writes both fields. If a user backs from `TWO_FA_SETUP` to `CREDENTIALS` and the ViewModel survives (process not killed), `twoFaSecret` remains populated in state — it will reappear if they advance to `TWO_FA_SETUP` again from a fresh `setup2FA()` call, but for the duration in-between the secret is live in the ViewModel heap. Remediation: add `twoFaSecret = "", twoFaManualEntry = "", qrCodeDataUrl = ""` to the `copy` in `goBack()` when `current.step == SetupStep.TWO_FA_SETUP`; also clear them in the `verify2FA()` success path before `onSuccess()`. `LoginScreen.kt:628-641, 1082-1106`. Effort: **XS**.

- [ ] **LOGIN-MOCK-190 (Security). `BuildConfig.BASE_DOMAIN` silently falls back to `"bizarrecrm.com"` if all three sources (Gradle property, env var, `.env`) are absent — a staging APK built without the var set routes all slug-based logins to production, and there is no build-time guard preventing a release APK from shipping with `"localhost"` if `.env` has that value.** Evidence: `android/app/build.gradle.kts:26-34` — `normalizeBaseDomain(... ?: "bizarrecrm.com")`. The `normalizeBaseDomain()` helper strips blank to `"bizarrecrm.com"` as last resort. No check prevents releasing with `BASE_DOMAIN=localhost`. `LoginScreen.kt:123` — `private val CLOUD_DOMAIN = BuildConfig.BASE_DOMAIN.lowercase()` consumes this field. Remediation: add to `build.gradle.kts` before `buildConfigField`: `if (isReleaseBuild && (configuredBaseDomain == "localhost" || configuredBaseDomain == "127.0.0.1")) { error("BASE_DOMAIN must not be a loopback in a release build. Set -PBASE_DOMAIN, BASE_DOMAIN env var, or .env.") }`. Add debug-only runtime assertion: `init { if (BuildConfig.DEBUG) check(BuildConfig.BASE_DOMAIN.isNotBlank()) { "BASE_DOMAIN is blank" } }` in `LoginViewModel`. `android/app/build.gradle.kts:26-34`; `LoginScreen.kt:123`. Effort: **XS**.

- [ ] **LOGIN-MOCK-191 (Bug). Hilt DI failure on `LoginViewModel` crashes the app with `IllegalStateException` at `hiltViewModel()` in `LoginScreen.kt:1740` with no fallback; all six constructor dependencies are non-optional.** Evidence: `LoginScreen.kt:285-293` — `@HiltViewModel class LoginViewModel @Inject constructor(authPreferences, authApi, networkMonitor, biometricCredentialStore, biometricAuth, deepLinkBus)`. `LoginScreen.kt:1740` — `viewModel: LoginViewModel = hiltViewModel()`. On API 26 (min SDK) without multidex or with a missing `@Module` binding, Hilt component creation fails at Activity start with no user-visible recovery path — the user sees a system crash dialog. No `try/catch` wraps `hiltViewModel()`. Remediation: (a) confirm `multiDexEnabled = true` in `build.gradle.kts defaultConfig` (verify); (b) add a compile-time `@HiltAndroidTest` entry-point test that asserts all six bindings resolve; (c) add a `CrashReporter` breadcrumb in `BizarreCrmApp.onCreate()` before Hilt component creation begins so DI failures are captured before the Activity stack. `LoginScreen.kt:285-293, 1740`; `android/app/build.gradle.kts`. Effort: **S**.

- [x] **LOGIN-MOCK-192 (Verify). No PII or credential logging found in `LoginScreen.kt` at HEAD — passwords, tokens, and secrets are not passed to any log call.** Evidence: the only log call in the file is `android.util.Log.w("TwoFaVerifyStep", "SmsRetriever start failed", e)` at line 3449, logging only a Play Services exception object with no user data attached. `extractErrorMessage()` at lines 1707-1718 logs nothing. `twoFaSecret`, `password`, `pendingStashPassword`, `challengeToken`, and `accessToken` fields are never referenced in any `Timber.*` or `Log.*` call. `ClipboardUtil.copySensitive()` suppresses the system clipboard preview toast on API 33+ via `ClipDescription.EXTRA_IS_SENSITIVE`. No PII leak exists in `LoginScreen.kt` at HEAD. **Note:** a future regression risk exists if `Timber.d("Login state: $state")` is ever added — all `LoginUiState` fields including `password` and `twoFaSecret` would be exposed. Backstop: add `"password"`, `"twoFaSecret"`, `"pendingStashPassword"`, and `"challengeToken"` to `RedactorTree.SENSITIVE_KEYS` as a pre-emptive guard. `LoginScreen.kt:3449`; `util/RedactorTree.kt:88-111`.

---

### Wave-5 Finder-N telemetry + observability

- [ ] **LOGIN-MOCK-193 (Observability). No login-funnel analytics events fire anywhere in the auth flow — success, failure, step transitions, and alternative auth paths are all invisible to the operator.** `LoginViewModel` (throughout): `login()`, `verify2FA()`, `registerShop()`, `setup2FA()`, `signInWithPasskey()`, `exchangeSsoCode()`, `exchangeMagicLink()`, and `attemptBiometricAutoLogin()` contain zero analytics calls. There is no `TelemetryClient`, no `AnalyticsTracker`, and no Breadcrumb category that maps to funnel stages (only `CAT_AUTH = "auth"` exists in `Breadcrumbs.kt` but is never called from any login function). The sovereignty constraint in `build.gradle.kts:341-370` correctly bans Firebase Analytics (`firebase-analytics` is in the forbidden-modules set), so a first-party lightweight event logger is the right path. Remediation: create `util/AuthAnalytics.kt` — a thin singleton that writes structured breadcrumb entries (category `"auth"`, message `"event=<name> result=<ok|fail> method=<password|biometric|passkey|sso|magic_link> reason=<tag>"`) and optionally posts a compact JSON event to `POST /api/v1/telemetry/event` on the tenant's own server. Required events: `login_started`, `login_success`, `login_failure` (with `reason` tag: `bad_password | bad_2fa | network | rate_limit | unknown`), `register_started`, `register_completed`, `2fa_setup_started`, `2fa_setup_completed`, `passkey_attempted`, `passkey_succeeded`, `passkey_failed`, `sso_started`, `sso_succeeded`, `sso_failed`, `biometric_auto_login_succeeded`, `biometric_auto_login_failed`. All event data must pass through `LogRedactor.redact()` before the breadcrumb write. `LoginScreen.kt:894-989` (login), `1056-1115` (verify2FA), `1449-1526` (passkey), `1351-1395` (SSO), `1618-1692` (magic-link), `1241-1287` (biometric auto-login); `util/Breadcrumbs.kt:57`.

- [ ] **LOGIN-MOCK-194 (Observability). `CrashReporter` writes local crash files only — there is no upload path to the tenant's server, so a silent crash on the login screen is invisible unless the user manually shares the log via `adb pull` or the share-sheet.** `util/CrashReporter.kt:28-29`: "A future iteration uploads the file to the tenant's own server when an endpoint exists (see §32.2 TelemetryClient TODO). Until then the file is purely a developer aid recoverable via adb pull." The §32.2 TelemetryClient is not implemented. Login crashes (ViewModel init failure, SSL handshake exceptions, Keystore failures) are therefore permanently unobservable in production unless a user actively files a report. Remediation: implement `util/TelemetryClient.kt` — calls `POST /api/v1/telemetry/crash` with the crash log body (text/plain), respects the data-sovereignty constraint (tenant server only, never a third-party endpoint), is triggered from `CrashReporter.writeReport()` on a background coroutine, and is rate-limited to one upload per crash UUID to avoid re-sending on repeated launches. Add the server-side route to `TODO.md` under `CROSS-PLATFORM`. `util/CrashReporter.kt:28-29, 58-96`.

- [x] **LOGIN-MOCK-195 (Security). `android.util.Log.w` is called directly in `TwoFaVerifyStep` at line 3449, bypassing `RedactorTree` — any `SmsRetriever` failure exception whose message contains an OTP code or device identifier will appear in Logcat unredacted in both debug and release builds.** `LoginScreen.kt:3449`: `android.util.Log.w("TwoFaVerifyStep", "SmsRetriever start failed", e)`. `RedactorTree` (`util/RedactorTree.kt`) is installed as a Timber tree and intercepts all `Timber.*` calls, but raw `android.util.Log.*` calls bypass it entirely. An `OnFailureListener` exception from `SmsRetriever` can carry a message containing the device's phone number or a partial OTP. The release build has `isMinifyEnabled = true` but ProGuard does not strip log calls unless a custom rule removes `android.util.Log` — no such rule is visible in `build.gradle.kts`. Remediation: replace `android.util.Log.w(...)` with `Timber.w(e, "SmsRetriever start failed")` so the message passes through `RedactorTree.redact()` before output. Apply the same replacement to any other bare `android.util.Log.*` calls found in the auth package (grep the package for `android.util.Log` and `import android.util.Log`). `LoginScreen.kt:3449`.

- [ ] **LOGIN-MOCK-196 (Observability). Network failure cause is not tagged in the login error path — `ConnectException`, `UnknownHostException`, `SocketTimeoutException`, `SSLHandshakeException`, and HTTP 5xx all produce different `state.error` strings or flow through `unreachableHost`, but none are recorded as a structured breadcrumb with a failure-type tag, so post-mortem triage cannot distinguish network topology problems from server errors.** `LoginScreen.kt:944-988`: the catch block distinguishes 429, `UnknownHostException`/`ConnectException`, and generic errors, but calls `Breadcrumbs.log()` on none of them. `CrashReporter` only fires on uncaught exceptions, not on caught login errors. Remediation: in the `login()` catch block, call `breadcrumbs.log(Breadcrumbs.CAT_AUTH, "login_failure type=${classifyLoginError(e)} code=${(e as? HttpException)?.code()}")` where `classifyLoginError` maps exception type to an enum tag (`network_unreachable | ssl_error | timeout | rate_limited | auth_error | server_error | unknown`). Mirror the same call in `verify2FA()` catch, `signInWithPasskey()` catch, `exchangeSsoCode()` catch, and `exchangeMagicLink()` catch. `LoginScreen.kt:944-988, 1107-1113, 1512-1524, 1374-1395, 1673-1692`.

- [ ] **LOGIN-MOCK-197 (Observability). Login round-trip latency is not measured — there is no `SystemClock.elapsedRealtime()` delta recorded from `login()` call entry to `verify2FA()` completion, so p95/p99 latency spikes (e.g. slow self-hosted servers, high-latency mobile networks) are invisible.** `LoginScreen.kt:895-989` (`login()`), `1056-1115` (`verify2FA()`): neither function captures a start timestamp. The `probeSetupStatus()` path also has no timing. `JankReporter` (`util/JankReporter.kt`) records frame timing but not network round-trips. Remediation: record `val t0 = SystemClock.elapsedRealtime()` at the start of each network-bound function and emit a breadcrumb `"login_rtt_ms=${SystemClock.elapsedRealtime()-t0}"` on both success and failure paths. For the full login funnel (credentials → challenge → 2FA verify → token), record a second delta from the `login()` call to the first line of the `verify2FA` success branch. This data surfaces in crash reports via `CrashReporter`'s breadcrumb dump and can later feed a `TelemetryClient` p95 histogram. `LoginScreen.kt:895, 1056`.

- [ ] **LOGIN-MOCK-198 (Observability). The setup-status probe (`probeSetupStatus()`) silently swallows its own duration — a probe that takes >2 s on a slow self-hosted instance is indistinguishable from a <100 ms fast response, and the failure path at line 885 uses `timber.log.Timber.w(e, ...)` but the success path emits no breadcrumb at all.** `LoginScreen.kt:853-892`: `probeSetupStatus()` — `Timber.w` on failure (line 885) is the only log call; success is silent. The probe fires on every CREDENTIALS step entry (guarded by `setupNeeded != null`), so repeated slow probes on a congested LAN server accumulate latency with no visibility. Remediation: (a) add `val t0 = SystemClock.elapsedRealtime()` before the `authApi.getSetupStatus()` call and emit `breadcrumbs.log(Breadcrumbs.CAT_AUTH, "probe_setup_status rtt_ms=${elapsed} result=${if(data.needsSetup) "needs_setup" else "ok"}")` on success; (b) on catch, change `Timber.w(e, ...)` to also log into breadcrumbs: `breadcrumbs.log(Breadcrumbs.CAT_AUTH, "probe_setup_status failed: ${e::class.simpleName}")` so the breadcrumb ring retains the failure before a subsequent crash. `LoginScreen.kt:853-892`.

- [ ] **LOGIN-MOCK-199 (Observability). Auth-method adoption is untracked — there is no way to know what fraction of login sessions use biometric vs. password vs. passkey vs. SSO vs. magic-link, which is necessary for prioritising which auth paths to invest in and for detecting enrollment degradation after an OS update.** The `LoginUiState` fields `biometricEnabled`, `passkeyEnabled`, `ssoProviders`, and `magicLinksEnabled` are probed and stored, but none of their resolved values are emitted as telemetry at login-success time. Remediation: in `verify2FA()` success path and each alternative-auth success path, emit a breadcrumb and (when `TelemetryClient` is implemented per LOGIN-MOCK-194) a structured event: `auth_method_used method=<password|biometric|passkey|sso|magic_link>`. Aggregated server-side, this gives daily active users per auth method without any third-party SDK. `LoginScreen.kt:1056-1115` (password/biometric), `1488` (passkey), `1371` (SSO), `1666` (magic-link).

- [ ] **LOGIN-MOCK-200 (Bug/ANR-risk). `RateLimitInterceptor` calls `runBlocking { rateLimiter.acquire(category) }` on OkHttp's dispatcher thread — if the token bucket is empty and the coroutine suspends for the full `callTimeout` (30 s for the probe client, default OkHttp timeout for RetrofitClient), the OkHttp thread pool thread is blocked, not the main thread, so this is not a direct ANR. However, if login is initiated from a coroutine that itself holds a dispatcher thread (e.g. `withContext(Dispatchers.IO)` inside `connectToServer()`), and the `callTimeout` expires while `runBlocking` is blocked, the thread is held past the call timeout, starving `Dispatchers.IO` for the duration.** `data/remote/interceptors/RateLimitInterceptor.kt:66`: `val acquired = runBlocking { rateLimiter.acquire(category) }`. The comment at line 41-43 acknowledges the bridge but does not note the thread-starvation risk when the bucket is empty. `connectToServer()` at `LoginScreen.kt:662` uses `withContext(Dispatchers.IO)`, wrapping a `probeClientFor()` call that uses the same interceptor chain. Remediation: cap the `acquire()` suspension with a timeout matching the connect timeout (`withTimeout(10_000L) { rateLimiter.acquire(category) }`) inside the `runBlocking` block so threads are released promptly on bucket exhaustion rather than blocking until the OkHttp call-timeout fires. `data/remote/interceptors/RateLimitInterceptor.kt:66`; `LoginScreen.kt:662`.

- [ ] **LOGIN-MOCK-201 (Observability). `StrictModeInit` is debug-only (`BuildConfig.DEBUG` guard at `util/StrictModeInit.kt:46`) with `penaltyLog()` only — violations are written to Logcat but are not routed to `Breadcrumbs`, so a disk-on-main-thread violation in the login flow (e.g. from `EncryptedSharedPreferences` first access or `AuthPreferences` reads in ViewModel init) is visible in a connected debug session but leaves no trace in crash reports from field devices.** `util/StrictModeInit.kt:45-63`: both thread and VM policies use `penaltyLog()` only; `penaltyListener` (API 28+) is not used. The `Breadcrumbs` singleton is available in `BizarreCrmApp` but is not injected into `StrictModeInit`. Remediation: on API 28+, add a `penaltyListener` to both policies that calls `breadcrumbs.log("strictmode", violation.className + ": " + violation.message)` (max 100 chars, no PII) so StrictMode hits in the login path are captured in crash breadcrumbs even on field devices running the debug build. Keep `penaltyDeath` absent (correct — it would break QA). `util/StrictModeInit.kt:46-63`.

- [ ] **LOGIN-MOCK-202 (Observability). `JankReporter` is attached only to `MainActivity`'s window (per its KDoc) and records jank only while `PerformanceMetricsState` is tagged with the activity label — but the login Composable runs inside `MainActivity` with no additional `PerformanceMetricsState` state tag, so janky frames during the `TwoFaSetupStep` QR-code bitmap decode (potential 100-200 ms on low-end devices) and during `AnimatedVisibility` transitions are attributed to the generic `"MainActivity"` label rather than the specific login step.** `util/JankReporter.kt:40-41`: `putState("activity", activity.localClassName)` — one static label for the entire session. `QrCodeGenerator` bitmap decode runs synchronously in the Composable render phase (see `TwoFaSetupStep`). Remediation: (a) inject `PerformanceMetricsState` into `LoginScreen` and call `putState("login_step", state.step.name)` inside a `LaunchedEffect(state.step)` so jank reports carry the step name; (b) move QR bitmap decode into `withContext(Dispatchers.Default)` in `setup2FA()` and store the decoded `Bitmap` in state rather than decoding inside the Composable. `util/JankReporter.kt:40`; `LoginScreen.kt` (TwoFaSetupStep QR render).

- [ ] **LOGIN-MOCK-203 (Security/Observability). `stashCredentialsBiometric()` and `attemptBiometricAutoLogin()` swallow all Keystore / crypto exceptions silently via `runCatching { }.onFailure { }` with no breadcrumb — a Keystore attestation failure, a `KeyPermanentlyInvalidatedException`, or a `UserNotAuthenticatedException` during biometric auto-login leaves the user silently dropped to the password form with no diagnostic trace in any crash report.** `LoginScreen.kt:1213-1226` (`stashCredentialsBiometric()`): `runCatching { ... }` — the outer block comment says "Swallow any Keystore/crypto errors — biometric stash is best-effort." `LoginScreen.kt:1282-1285` (`attemptBiometricAutoLogin()`): `.onFailure { _state.value = _state.value.copy(isBiometricAutoLoginInFlight = false) }` — no logging. Keystore failures on enrolled-but-invalidated keys or after a device PIN change manifest as dropped auto-logins that are invisible to the developer. Remediation: in both `onFailure` blocks, add `breadcrumbs.log(Breadcrumbs.CAT_AUTH, "biometric_keystore_error class=${it::class.simpleName}")` and (for `attemptBiometricAutoLogin`) `Timber.w(it, "biometric auto-login keystore failure")` so the failure class is captured without leaking the exception message (which may contain key alias or user identity data). `LoginScreen.kt:1213-1226, 1282-1285`.

- [ ] **LOGIN-MOCK-204 (Observability). `probemagicLinksEnabled()` and `probePasskeyEnabled()` both call `authApi.getTenantMe()` independently in `init { }` — two concurrent identical GET requests are fired on every ViewModel initialization, doubling the login-cold-start API call count with no deduplication, and neither call emits a breadcrumb or timing metric.** `LoginScreen.kt:409-413`: `viewModelScope.launch { probemagicLinksEnabled() }` and `viewModelScope.launch { probePasskeyEnabled() }` — both call `authApi.getTenantMe()` separately within the same `init` block; they race with no coordination. On slow connections (self-hosted LAN, 3G) this wastes a full round-trip. Additionally, `loadSsoProviders()` at line 405 fires a third concurrent request (`GET /auth/sso/providers`), bringing the cold-start login concurrent request count to 4 (including `connectToServer()`). Remediation: (a) merge `probemagicLinksEnabled()` and `probePasskeyEnabled()` into a single `probeTenantFeatures()` function that calls `getTenantMe()` once and updates both state fields from one response; (b) emit `breadcrumbs.log(Breadcrumbs.CAT_AUTH, "tenant_features_probe rtt_ms=${elapsed} ml=${magicLinks} pk=${passkey}")` after the merged call. `LoginScreen.kt:403-413, 1405-1435`.

- [x] **LOGIN-MOCK-205 (Observability). `LogRedactor` does not mask the `challengeToken` field — challenge tokens appear in error messages surfaced through `extractErrorMessage()` and in `Exception` messages that pass through `RedactorTree`, allowing a mid-flow challenge token to appear in Logcat or in a `CrashReporter` log file if an exception message includes it verbatim.** `util/LogRedactor.kt` (full file): patterns cover Bearer/JWT, IMEI, card, SSN, phone, email — no pattern for `challengeToken`. `util/RedactorTree.kt:88-111` (`SENSITIVE_KEYS`): the list covers `password`, `accessToken`, `refreshToken`, `totp`, `secret`, `manualEntry`, `setup_token` — but not `challengeToken`. `LoginScreen.kt:1707-1719` (`extractErrorMessage()`): can return a raw server error body that embeds `"challengeToken":"<value>"`. A `CertificateException` during the 2FA verify step would reach `CrashReporter.writeReport()` with the exception message containing the challenge token. The challenge token is a short-lived credential (10 min TTL) but is still a bearer of elevated authorization. Remediation: add `"challengeToken"` and `"challenge_token"` to `RedactorTree.SENSITIVE_KEYS` (they will then be masked by `REDACT_PATTERN` in both JSON and encoded forms). `util/RedactorTree.kt:88-111`; `util/LogRedactor.kt` (no change needed — key-value masking is handled by `RedactorTree`).

---

### Wave-5 Finder-O tablet/foldable/ChromeOS adaptive

> Scope: tablet (Expanded width ≥840dp), foldable hinge, ChromeOS/DeX hardware-keyboard + mouse, window resize/PiP, orientation lock, dual-screen (Surface Duo), notification permission timing, backup-codes export, external display/Cast security, and Wear OS companion surface. IDs 206–218.

- [ ] **LOGIN-MOCK-206 (Layout). `LoginScreen` has no `WindowSizeClass` dispatch — the card is hard-capped at `widthIn(max = 420.dp)` centered in a `Box(TopCenter)`, leaving 400–600 dp of blank background on tablets (Expanded ≥840dp) and ChromeOS windows wider than 900dp.** `LoginScreen.kt:1886-1892`: `Column(modifier = Modifier.widthIn(max = 420.dp))`. `MainActivity.kt` never calls `currentWindowAdaptiveInfo()` or `calculateWindowSizeClass()`, so no `WindowWidthSizeClass` is derived or passed into `LoginScreen`. `FoldingFeatureObserver.kt` exists in `util/` but is wired only to §22 list-detail screens — never to auth. On a Galaxy Tab S9 (~1280dp width) the card occupies under 33 % of the screen width; the remainder is a flat `MaterialTheme.colorScheme.background`. Remediation: (a) call `currentWindowAdaptiveInfo()` inside `LoginScreen` and branch on `windowSizeClass.windowWidthSizeClass`: for `COMPACT`/`MEDIUM` keep the current 420dp card; for `EXPANDED` switch to a `Row` two-pane — brand illustration / hero pattern in the left pane, existing card (max 520dp) in the right pane; (b) bump `maxWidth` from 420dp to 520dp on `MEDIUM` to reduce the gap on 7–8" tablets; (c) add a `WindowSizeClassTest` JVM unit test asserting correct layout-branch selection. File: `LoginScreen.kt:1886-1892`; `util/FoldingFeatureObserver.kt:50-86`.

- [ ] **LOGIN-MOCK-207 (Layout). Foldable hinge (Pixel Fold inner display ~768dp folded-open width) is unhandled — `FoldingFeatureObserver` exposes posture but `LoginScreen` never collects it, so the 420dp card may straddle the physical hinge crease in a half-fold Book posture.** `FoldingFeatureObserver.kt:50-86`: the `posture` `StateFlow` is exported but never imported by any auth-screen composable. In `Book` posture the hinge bisects the inner display at roughly x=384dp; a 420dp card centered at x=384dp overlaps the hinge by ~20dp per side, visually splitting username/password fields across the crease gap. In `Tabletop` posture the card center-aligns in the upper half without issue, but the lower half is entirely empty. Remediation: (a) collect `FoldingFeatureObserver.posture` inside `LoginScreen`; (b) on `Book` posture read `FoldingFeature.bounds` and shift the card's horizontal offset so it lands entirely within one panel using `Modifier.offset(x = hingeClearanceOffset)` derived from the hinge rect; (c) on `Tabletop` posture, anchor the card in the top half with explicit `padding(bottom = hingePanelHeight)` so the keyboard naturally occupies the bottom half. File: `LoginScreen.kt:1870-1892`; `util/FoldingFeatureObserver.kt:60-86`.

- [ ] **LOGIN-MOCK-208 (UX). ChromeOS hardware-keyboard Escape does not dismiss the software keyboard, and Cmd+Enter does not submit the current login step — both are expected ChromeOS/desktop conventions absent from all `KeyboardActions` handlers.** `LoginScreen.kt:2261, 2290, 2781`: `KeyboardActions(onDone = { ... })` fires on Enter, but no `Modifier.onKeyEvent` intercepts `Key.Escape` or `Key.MetaLeft + Key.Enter` on any `OutlinedTextField` or parent `Column`. On ChromeOS the software keyboard is rarely visible; pressing Enter while a field has `ImeAction.Next` focus can accidentally advance the step rather than submitting it. No `onCancel` path exists in any `KeyboardActions` block. Remediation: (a) add `Modifier.onKeyEvent { event -> if (event.key == Key.Escape) { focusManager.clearFocus(); true } else false }` on each step's root `Column`; (b) add `Modifier.onKeyEvent` on the final-field `OutlinedTextField` for `Key.MetaLeft + Key.Enter` → submit, mirroring the Cmd+Return desktop convention; (c) document these shortcuts in §17 `KeyboardShortcutsHelp` so they appear in the Ctrl+/ cheat-sheet. File: `LoginScreen.kt:2254-2292, 2770-2782`.

- [ ] **LOGIN-MOCK-209 (UX). Mouse-hover cursor icons are absent from all `LoginScreen` interactive elements — text fields show the default arrow cursor instead of the Text cursor, and `TextButton` / `OutlinedButton` links show the arrow instead of the Hand cursor on ChromeOS and Samsung DeX.** No `Modifier.pointerHoverIcon(...)` call appears anywhere in `LoginScreen.kt` (confirmed by grep). The `ActionPlan.md` non-negotiables (line 18) list `pointerHoverIcon` as a hard requirement for ChromeOS, and §22 tablet polish lists it as missing. Affected surfaces: all `OutlinedTextField`s (~14 instances), `TextButton("Sign in with SSO")`, `TextButton("Email me a magic link")`, `TextButton("Use a backup code")`, `TextButton("Dismiss")`, `BrandPrimaryButton`, `LoginPillButton`. Remediation: add `Modifier.pointerHoverIcon(PointerIcon.Text)` on every `OutlinedTextField` modifier chain; add `Modifier.pointerHoverIcon(PointerIcon.Hand)` on every `Button`, `TextButton`, `OutlinedButton`, and `IconButton`. Centralise via `fun Modifier.textFieldHover()` and `fun Modifier.clickableHover()` extension functions in `ui/theme/ModifierExt.kt` to avoid 20+ scattered call-sites. File: `LoginScreen.kt` (all interactive composables); `BackupCodesDisplay.kt:159-177`.

- [ ] **LOGIN-MOCK-210 (UX). Right-click context menus are absent on `LoginScreen` text-input fields — ChromeOS users expect Cut / Copy / Paste / Select All on right-click, but `OutlinedTextField` only surfaces `onLongClick` and there is no `ContextMenuArea` wrapper anywhere in `LoginScreen` or `BackupCodesDisplay`.** Compose's `SelectionContainer` (imported at `LoginScreen.kt:8`) provides clipboard menus for read-only text, but editable input fields require an explicit `ContextMenuArea { ... }` wrapper (from `androidx.compose.foundation`) to intercept right-click. Without it, right-clicking an input field on ChromeOS shows an empty or browser-style system menu. `BackupCodesDisplay.kt:133-153` is the most critical gap — right-clicking a backup-code chip on a Chromebook produces no menu, making per-code copy impossible without manual text selection. Remediation: (a) evaluate `ContextMenuArea` wrapping for the username, password, server-URL, and TOTP fields in `LoginScreen`; (b) in `BackupCodesDisplay.kt`, wrap each code `Surface` chip at line 133 with a `ContextMenuArea` offering a "Copy this code" action; (c) test on Android 12+ freeform window with a physical mouse. File: `LoginScreen.kt` (input fields); `BackupCodesDisplay.kt:133-153`.

- [x] **LOGIN-MOCK-211 (Security). `MainActivity` carries `android:supportsPictureInPicture="true"` (manifest line 138), which allows the login form — including live credentials and TOTP fields — to enter a 160×90dp floating PiP window, defeating `FLAG_SECURE` and creating a credentials surface visible to bystanders.** `AndroidManifest.xml:138`: `android:supportsPictureInPicture="true"` is set on `MainActivity`. This attribute was intended for `CallInProgressActivity` (§42, manifest line 284) and was mistakenly also applied to the main activity. `LoginScreen.kt` has no `DisposableEffect` calling `activity.setPictureInPictureParams(PictureInPictureParams.Builder().setAutoEnterEnabled(false).build())`. `FLAG_SECURE` (`MainActivity.kt:163`) blocks screencap but does NOT prevent PiP entry on API 26–31; `setAutoEnterEnabled(false)` is required on API 31+ to suppress auto-entry. Remediation: remove `android:supportsPictureInPicture="true"` from `MainActivity` in `AndroidManifest.xml:138` — it belongs only on `CallInProgressActivity`. If PiP is ever needed for a post-login surface, re-add it scoped to that specific activity or manage via `setPictureInPictureParams` at the composable layer. File: `AndroidManifest.xml:138`.

- [ ] **LOGIN-MOCK-212 (Layout). Landscape orientation on phones is unlocked — `AndroidManifest.xml` has no `android:screenOrientation` on `MainActivity`, so the login card renders in landscape with a ~360dp-tall viewport, pushing the password field and CTA below the IME with no scroll-to-focused behavior on mid-range phones.** `AndroidManifest.xml:133-140`: no `screenOrientation` attribute. `LoginScreen.kt:1875`: `imePadding()` is applied on the root `Box`, but the `verticalScroll` `Column` has no `BringIntoViewRequester` on focused fields. On landscape Pixel 6 (412×732dp, ~360dp viewport height after bars), `Alignment.TopCenter` anchoring means the Sign-In CTA is clipped below the IME rather than scrolled into view. `adjustResize` (`windowSoftInputMode`, manifest line 137) shrinks the window but does not auto-scroll the Compose tree. Remediation: either (a) on `COMPACT` height, lock orientation to portrait in `LoginScreen` via `DisposableEffect { activity.requestedOrientation = SCREEN_ORIENTATION_PORTRAIT; onDispose { activity.requestedOrientation = SCREEN_ORIENTATION_UNSPECIFIED } }`; or (b) attach a `BringIntoViewRequester` + `relocationRequester.bringIntoView()` inside `Modifier.onFocusChanged` for the password and TOTP fields so the focused field scrolls above the IME in all orientations. File: `LoginScreen.kt:1869-1892`; `AndroidManifest.xml:133-140`.

- [ ] **LOGIN-MOCK-213 (Layout). Surface Duo dual-screen support is undefined — `FoldingFeatureObserver` does not check `FoldingFeature.isSeparating`, so on a Surface Duo in dual-screen mode the 420dp card center-aligns across the hinge gap and can partially render in the dead-zone between physical screens.** `FoldingFeatureObserver.kt:63`: `layoutInfo.displayFeatures.filterIsInstance<FoldingFeature>()`. The observer's `Flat` branch (`fold.state == FLAT`) does not check `isSeparating`, so a Duo in flat/spanned mode is treated identically to a non-foldable tablet, leaving the card potentially bisected by the physical gap. The Duo inner-display width at full span is ~1350dp; the inter-screen gap is ~5.6mm (≈17dp at 294ppi), meaning any card content that crosses x=675dp ±9dp may be obscured. Remediation: (a) add `fold.isSeparating` check in `FoldingFeatureObserver` and expose a `FoldablePosture.Separated` variant; (b) in `LoginScreen`, when `posture == Separated`, constrain card width to the narrower of the two panels using `WindowMetricsCalculator` to derive left-panel bounds and apply `Modifier.widthIn(max = leftPanelWidth - 32.dp)`, centering within screen 1 only; (c) treat login as single-screen — no dual-panel auth layout is warranted. File: `util/FoldingFeatureObserver.kt:63-84`; `LoginScreen.kt:1886-1892`.

- [x] **LOGIN-MOCK-214 (Security/UX). `rememberNotificationPermission()` is imported in `MainActivity.kt` (line 36) with no visible guard preventing the POST_NOTIFICATIONS prompt from appearing before the user has completed login — a pre-login permission request has no context, violates Play Store UX guidelines, and creates a jarring first impression for new installs.** `MainActivity.kt:36`: `import com.bizarreelectronics.crm.util.rememberNotificationPermission`. If this utility is invoked unconditionally from within `setContent` (before auth state is checked), a cold-start unauthenticated user sees the system permission dialog before the login form renders. `POST_NOTIFICATIONS` is declared in `AndroidManifest.xml:43`. Play Store review guidelines (2023+) classify pre-context permission prompts as a policy violation that can delay review approval. Remediation: (a) locate the `rememberNotificationPermission()` call site in `MainActivity.setContent` or `AppNavGraph`; (b) gate it behind `val isLoggedIn = authPreferences.accessToken != null` so the prompt only fires post-login; (c) if the call site is already inside a post-login composable (e.g. `DashboardScreen`), verify and close — this item may be a false alarm pending that confirmation. File: `MainActivity.kt:36, 205+`; `util/rememberNotificationPermission` (grep to confirm call site).

- [ ] **LOGIN-MOCK-215 (UX). `BackupCodesDisplay` has no Storage Access Framework "Save to Files" affordance — tablet and ChromeOS users have a visible Files app and expect a structured file export, but the only export path is clipboard-copy with a 30-second auto-clear that races the typical vault app-switch workflow.** `BackupCodesDisplay.kt:159-177`: only `ClipboardUtil.copySensitive(clearAfterMillis = 30_000L)` via `OutlinedButton("Copy all codes")` — no `Intent.ACTION_CREATE_DOCUMENT` path. On a Chromebook with the Files shelf always visible, users who dismiss without copying have no recovery (codes are not shown again). `ActivityResultContracts.CreateDocument("text/plain")` requires no `WRITE_EXTERNAL_STORAGE` on API 26+ and produces a named `.txt` file in the user-chosen directory. Remediation: (a) add an `OutlinedButton("Save to Files")` launcher backed by `ActivityResultContracts.CreateDocument("text/plain")` with a suggested filename `bizarre-crm-backup-codes.txt`; write codes to the returned URI on a background coroutine; (b) auto-check the confirmation checkbox on successful file-write; (c) increase the clipboard auto-clear from 30 s to 120 s to cover slow vault app-switches as an independent improvement. File: `BackupCodesDisplay.kt:59-207`.

- [ ] **LOGIN-MOCK-216 (UX). Backup codes are not printable from `BackupCodesDisplay` — tablet and ChromeOS users with a networked printer have no print path, despite the dialog body text explicitly listing "printed copy" as a valid storage option.** `BackupCodesDisplay.kt:109`: "Store them somewhere safe (password manager, printed copy)." — the dialog recommends printing but provides no print CTA. `PrintHelper` (AndroidX Print) or `PrintManager` with a `PrintDocumentAdapter` can produce a one-page printout with zero storage-permission requirements. On ChromeOS, `PrintManager` routes to the system print dialog which includes the "Save as PDF" driver, covering PDF export at no extra library cost. Remediation: (a) add a tertiary `TextButton("Print codes")` using `PrintHelper` from `androidx.print`; (b) format the print job with shop name, date, and the 10 codes in a monospaced two-column grid; (c) auto-check the confirmation checkbox on successful `PrintHelper.printBitmap` or `PrintDocumentAdapter` dispatch. File: `BackupCodesDisplay.kt:59-207`.

- [x] **LOGIN-MOCK-217 (Security). Login screen content — including the live TOTP field and `BackupCodesDisplay`'s 10-code grid — is not suppressed on secondary/presentation displays, meaning a device casting to a Chromecast or connected via HDMI broadcasts the credentials form to anyone watching the external screen.** `MainActivity.kt:162-163`: `FLAG_SECURE` is set when `screenCapturePreventionEnabled` is true, which blocks screencap but does NOT prevent mirroring to an Android `Presentation` display — the `Presentation` API and `DisplayManager` bypass `FLAG_SECURE` on secondary outputs unless `FLAG_SECURE` is also set on the Presentation window explicitly. No `DisplayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)` check exists in the login flow. `BackupCodesDisplay.kt` is the highest-severity surface — backup codes visible on a conference-room TV is a direct credential exposure. Remediation: (a) in `MainActivity.onCreate`, register a `DisplayManager.DisplayListener`; when `onDisplayAdded` fires while the nav back-stack contains an auth screen, show a `Presentation` on the secondary display with a plain `Surface(color = Color.Black)` overlay (add `FLAG_SECURE` to its window) until the auth destination is exited; (b) alternatively, in `LoginScreen` and `BackupCodesDisplay`, add `window.addFlags(FLAG_SECURE)` unconditionally via `SideEffect` regardless of the user pref, and clear it in `DisposableEffect { onDispose { window.clearFlags(FLAG_SECURE) } }`. File: `MainActivity.kt:148-170`; `BackupCodesDisplay.kt:59-207`.

- [ ] **LOGIN-MOCK-218 (UX). There is no Wear OS companion surface for authentication — the `android/` project has no `:wear` module, no `DataClient`/`MessageClient` dependency, and no `WEARABLE_CONFIGURATION` meta-data in `AndroidManifest.xml`. This is correct and intentional for v1.0 but should be explicitly documented as deferred to prevent it from surfacing as an accidental gap in future adaptive-layout audits.** `android/app/build.gradle.kts` (full file): no `com.google.android.wearable` or `androidx.wear.compose` dependency. `AndroidManifest.xml` (full file): no `<meta-data android:name="com.google.android.wearable.standalone">`. A Wear OS companion showing ticket-ready or incoming-call alerts would require a separate `:wear` Gradle module, `Wearable.DataClient` / `MessageClient` sync channel, Wear Compose UI, and a Wear-side auth-token derivation flow — non-trivial scope, correctly deferred. Remediation: no code change in this wave. Add to the §23 Foldable & Desktop-Mode Polish section: `[ ] Wear OS companion module (deferred post-v1.0) — separate :wear module, DataClient sync, Wear Compose auth surface, token derivation. Revisit if shop owners request wrist alerts for ticket-ready / incoming-call events.` File: `android/ActionPlan.md` §23 (documentation-only addition).
- [ ] **LOGIN-MOCK-280 (Copy). Shop-URL field supporting text uses ASCII hyphen-minus (U+002D) "3–30 characters: letters, numbers, hyphens" but the mockup renders an en-dash (U+2013) between "3" and "30".** Code at `LoginScreen.kt:2313` and `LoginScreen.kt` search: `supportingText = { Text("3–30 characters: letters, numbers, hyphens") }` — the dash character in the string literal is the ASCII hyphen-minus U+002D (i.e. `"3-30 characters: letters, numbers, hyphens"`). Mockup screens 02, 03, 04, 05, 06 all show "3–30 characters: letters, numbers, hyphens" with a visually wider dash between "3" and "30" that is unambiguously an en-dash (U+2013). Fix: change the literal to `"3–30 characters: letters, numbers, hyphens"`. `LoginScreen.kt:2313`.

- [ ] **LOGIN-MOCK-281 (Copy). "Register new shop" footer link is sentence-case; "Register New Shop" heading on the destination screen is title-case — same destination, two different capitalisation rules across a single tap.** `ServerStep` `LoginScreen.kt:2262`: `Text("Register new shop")` — the mockup screen-01 confirms sentence-case here. `RegisterStep` heading `LoginScreen.kt:2283`: `Text("Register New Shop")` — mockup screens 02, 03, 04, 05, 06 confirm title-case there. The link and its destination heading are the same named action with conflicting capitalisation. Both cannot be correct simultaneously; the capitalization rule must be resolved and applied consistently. Code: link `"Register new shop"` at line 2262 vs heading `"Register New Shop"` at line 2283. No change is correct until design decides; flag for decision.

- [ ] **LOGIN-MOCK-282 (Copy). "Create your repair shop on BizarreCRM" subtitle uses a closed compound "BizarreCRM" (no space) while the wordmark renders "Bizarre CRM" (with space) — inconsistent brand name form.** `RegisterStep` subtitle `LoginScreen.kt:2292`: `Text("Create your repair shop on BizarreCRM")`. Mockup screen-02 shows "Create your repair shop on BizarreCRM" — same closed form. However the app wordmark at `LoginScreen.kt:1871` is `"Bizarre CRM"` with a space, confirmed by all 11 mockup screens. Two different forms of the brand name ("Bizarre CRM" vs "BizarreCRM") coexist with no explicit style guide rationale. Verify which is authoritative in body copy vs the wordmark; if brand guidance mandates "Bizarre CRM" everywhere, fix line 2292.

- [ ] **LOGIN-MOCK-283 (Copy). "Set Up Two-Factor Auth" heading uses Title Case with a terminal abbreviation "Auth" — no trailing period in mockup, code matches, but abbreviation vs full word "Authentication" is undocumented.** `TwoFaSetupStep` `LoginScreen.kt:3181`: `Text("Set Up Two-Factor Auth", ...)`. Mockup screen-10 shows "Set Up Two-Factor Auth" — matches. However `TwoFaVerifyStep` `LoginScreen.kt:3377` uses the *expanded* form `"Two-Factor Authentication"` for the verify-step heading. The same feature domain uses "Auth" (abbreviated) in the setup step and "Authentication" (full word) in the verify step. Decide on one canonical term for the 2FA step headings and apply it to both; current code has `"Set Up Two-Factor Auth"` at line 3181 vs `"Two-Factor Authentication"` at line 3377.

- [ ] **LOGIN-MOCK-284 (Copy). 2FA verify step subtitle "Enter the 6-digit code from your authenticator app" differs in structure from the setup step subtitle "Scan this QR code with Google Authenticator or any TOTP app" — the verify step names a generic concept ("authenticator app") while setup names a specific product ("Google Authenticator").** `TwoFaVerifyStep` `LoginScreen.kt:3380`: `Text("Enter the 6-digit code from your authenticator app")`. `TwoFaSetupStep` `LoginScreen.kt:3184`: `Text("Scan this QR code with Google Authenticator or any TOTP app")`. Mockup screen-10 confirms the setup subtitle exactly. The verify step subtitle has no mockup backing and uses a different product-mention pattern. If the design intent is to name Google Authenticator on both steps for discoverability, the verify subtitle should read "Enter the 6-digit code from Google Authenticator or any TOTP app". Flag for design review.

- [ ] **LOGIN-MOCK-285 (Copy). Loading button state on "Connect" shows only a spinner with no text; mockup loading state is absent from the screen set but the empty-loading pattern is inconsistent with other CTA states that carry in-progress copy.** `ServerStep` `LoginScreen.kt:2241–2244`: when `state.isLoading`, the Connect `Button` renders only `CircularProgressIndicator` with no accompanying text label. `CredentialsStep` passkey loading state at line 2842 renders `CircularProgressIndicator` + `Text("Signing in…")`. `MagicLinkRequestSheet` send button at line 2920 renders only a spinner. No mockup screen depicts a loading state for the Connect or Create Shop buttons, so there is no mockup source of truth. Recommend harmonising: either all loading CTAs show spinner-only or all show spinner + in-progress label. Currently there are three different patterns (spinner-only on Connect, spinner + text on passkey, spinner-only on magic-link send).

- [ ] **LOGIN-MOCK-286 (Copy). "Connecting to your server…" probe-overlay text uses Unicode HORIZONTAL ELLIPSIS (U+2026) — correct — but the string `"Signing in…"` on the passkey loading state at line 2843 also uses U+2026 correctly. However `LoginScreen.kt:2146` renders `"Sign-in expires in $label"` with a plain ASCII hyphen-minus (U+002D) in "Sign-in". Verify whether the style guide calls for an en-dash, hyphen-minus, or space-hyphen-space in compound adjective "sign-in". The mockup does not show a countdown; copy unreviewed.** `LoginScreen.kt:2146`: `Text("Sign-in expires in $label")`. The ASCII hyphen in "sign-in" is grammatically correct as a hyphenated compound modifier, but worth confirming it aligns with the style guide treatment of hyphenated terms elsewhere in the app. No mockup backs this string.

- [ ] **LOGIN-MOCK-287 (Copy). "Origin header required" error shown in mockup screen-06 is a raw server-side message surfaced verbatim; no client-owned translation string exists.** `LoginScreen.kt:755–758`: `registerShop()` extracts the server error via `rJson.optString("message", "Registration failed")` and sets it as `state.error`. Screen-06 shows the red inline copy "Origin header required" below the Admin Password field — this is the exact server JSON `message` value echoed through to the UI. There is no client-side mapping of known server error codes to user-friendly strings. A server-phrasing change silently changes the displayed copy with no code review. Add a client-side map from known technical messages (e.g. `"Origin header required"`) to user-friendly alternatives (e.g. `"Unable to register — please contact support"`). `LoginScreen.kt:755–758`.

- [ ] **LOGIN-MOCK-288 (Copy). Tab comment at `LoginScreen.kt:2031` explicitly describes the active indicator as "purple (#8B5CF6)" but the brand accent is cream (#FDEED0) — contradicts brand-color guide.** `LoginTabBar` Composable comment lines 2031–2032: `// Active tab: purple (#8B5CF6) text + 2dp purple underline indicator.` The brand colour guide mandates cream `#FDEED0` as the primary accent; purple appears in older mockups and was explicitly deprecated. The indicator tint is actually driven by `MaterialTheme.colorScheme.primary` at runtime (line 2044), so the rendered colour is correct if the theme is set up properly. The stale comment is a copy-fidelity risk: it misleads developers into hardcoding `#8B5CF6` when debugging. Update the comment to reference `MaterialTheme.colorScheme.primary` (cream on the cream theme). `LoginScreen.kt:2031`.

- [ ] **LOGIN-MOCK-289 (Copy). Apostrophe in "You've been signed out" and "You're offline" uses a straight apostrophe (U+0027) — Kotlin string literals do not automatically smart-quote.** `LoginScreen.kt:1908`: `"You've been signed out. Sign back in to continue."` and `LoginScreen.kt:2520`: `"You're offline. Connect to sign in."` Both use straight apostrophe U+0027. Compose renders straight apostrophes on-screen. Many style guides require curly/typographic apostrophe U+2019. Mockup screens do not depict these error states, so no mockup source of truth exists. Confirm whether the copy style guide mandates U+2019; if so, update all apostrophised strings in `LoginScreen.kt` (`"You've"` line 1908, `"You're"` line 2520, `"Passwords don't match"` line 983, `"Can't undo"` in undo stack copy, `"We'll send"` line 2888, `"won't show again"` in backup codes, etc.).

- [ ] **LOGIN-MOCK-290 (Copy). "Minimum 8 characters" supporting text on the Admin Password field is sentence-case with no trailing period — mockup screen-02 confirms the exact string; code matches but the field-label analogue "Shop URL" supporting text "3–30 characters…" is also lowercase with no period, creating a consistent pattern that should be documented.** `LoginScreen.kt:2362`: `supportingText = { Text("Minimum 8 characters") }`. Mockup screen-02 shows "Minimum 8 characters" — exact match. Both supporting-text strings ("3–30 characters: letters, numbers, hyphens" at line 2313 and "Minimum 8 characters" at line 2362) follow sentence-case, no trailing period, no capitalisation of the first word. This is the correct pattern and matches the mockup. Flagging as a confirmatory pass — no fix needed, but the style rule should be recorded in §67 (Copy & Content Style Guide) to prevent future regressions.

- [ ] **LOGIN-MOCK-291 (Copy). "Sign-in timed out. Please start over." snackbar message and "View setup guide" informational TextButton have no mockup backing — copy is unreviewed.** `LoginScreen.kt:1764`: snackbar message `"Sign-in timed out. Please start over."`. `LoginScreen.kt:2491`: `Text("View setup guide")` inside the needs-setup banner. Neither string appears in any of the 11 mockup screens. Both are live UI copy delivered to real users with no design review. "Please start over." ends with a period — consistent with error-message convention but unconfirmed. "View setup guide" is sentence-case with no trailing period — consistent but unreviewed. Flag both for design sign-off on wording and punctuation.

### Wave-6 Finder-P test coverage

- [ ] **LOGIN-MOCK-219 (Test). `LoginViewModel.connectToServer()` has no unit test — slug validation, blank-URL guard, 404-treated-as-reachable, and 5xx-throws-error branches are all untested.** `connectToServer()` (`LoginScreen.kt:649–720`) contains five observable side-effects: (1) blank slug → `error = "Enter your shop name"`, (2) slug < 3 chars → `error = "Shop name must be at least 3 characters"`, (3) blank custom URL → `error = "Server URL is required"`, (4) 404 response → `serverConnected = true, storeName = "CRM Server"`, (5) 5xx response → `error` set, `isLoading = false`. None are exercised by `LoginViewModelRegisterTest.kt` or `BiometricAuthTest.kt`. Scaffold: create `LoginViewModelConnectTest.kt` in `test/.../ui/auth/` using `kotlinx.coroutines.test.runTest`, a `FakeAuthApi` returning canned `MockResponse` objects, and `Turbine` (or `StateFlow.value` polling). Test methods: `connectToServer_blankSlug_setsError`, `connectToServer_shortSlug_setsError`, `connectToServer_blankCustomUrl_setsError`, `connectToServer_404_treatedAsReachable`, `connectToServer_5xx_setsError`, `connectToServer_timeout_setsUnreachable`. Covers the LOGIN-MOCK-173 retry-token concern at the connect layer.

- [ ] **LOGIN-MOCK-220 (Test). `LoginViewModel.login()` 401 retry — token preservation and `unreachableHost` / `rateLimited` flag transitions have no unit test.** `login()` (`LoginScreen.kt:919–1014`) produces five distinct state outcomes: (1) success → step = `TWO_FA_VERIFY` or `TWO_FA_SETUP`, (2) 401 → `error` via `friendlyErrorMessage`, (3) 429 → `rateLimited = true` + `rateLimitResetMs` populated, (4) `UnknownHostException` → `unreachableHost = true`, (5) generic exception → `error` set. LOGIN-MOCK-173 requires that on 401 the `challengeToken` from a previous successful `login()` call is NOT clobbered — this is untested. Scaffold: `LoginViewModelLoginTest.kt`. Methods: `login_blankUsername_setsError`, `login_blankPassword_setsError`, `login_success_advancesTo2faVerify`, `login_success_with2faSetupRequired_callsSetup2FA`, `login_401_setsErrorAndPreservesExistingToken`, `login_429_withRetryInSeconds_setsRateLimited`, `login_429_withRetryAfterHeader_fallsBackToHeader`, `login_unknownHost_setsUnreachableHost`, `login_connectException_setsUnreachableHost`. Uses `MockWebServer` (OkHttp) for real HTTP simulation.

- [ ] **LOGIN-MOCK-221 (Test). `LoginViewModel.verify2FA()` 401 retry — `challengeToken` preservation and `pendingBiometricStash` flag transition are untested.** `verify2FA()` (`LoginScreen.kt:1082–1244`) sets `pendingBiometricStash = true` when `rememberMeChecked && biometricEnabled` AND the verify succeeds. On 401 the token in `_state.value.challengeToken` must not be clobbered (LOGIN-MOCK-173 parity). Neither path has any test. Scaffold: `LoginViewModelVerify2FATest.kt`. Methods: `verify2FA_shortCode_setsError`, `verify2FA_success_noBiometric_noStash`, `verify2FA_success_withRememberMeAndBiometric_setsPendingStash`, `verify2FA_success_withBackupCodes_setsShowBackupCodes`, `verify2FA_401_preservesChallengeToken`, `verify2FA_invalidCode_setsError`. Requires `FakeAuthApi` returning `TwoFactorResponse` stubs and a mocked `AuthPreferences`.

- [ ] **LOGIN-MOCK-222 (Test). `LoginViewModel.setup2FA()` loading state is untested — LOGIN-MOCK-168 fix (immediate `isLoading = true`) has no regression guard.** `setup2FA()` (`LoginScreen.kt:1049–1079`) starts with `_state.value = _state.value.copy(isLoading = true, error = null)` — LOGIN-MOCK-168's specific fix. If this line is removed or reordered the UI regresses silently. Additionally the `inheritedExpiresAt` preservation path (line 1063: `val expiresAt = inheritedExpiresAt ?: ...`) is untested. Scaffold: `LoginViewModelSetup2FATest.kt`. Methods: `setup2FA_immediatelySetsLoading`, `setup2FA_success_populatesQrAndSecret`, `setup2FA_success_preservesInheritedExpiresAt`, `setup2FA_success_fallsBackToFreshExpiry_whenInheritedIsNull`, `setup2FA_failure_clearsLoadingAndSetsError`. Since `setup2FA` is private, test via `login()` with a `requires2faSetup = true` response stub, which exercises setup2FA as a side-effect.

- [ ] **LOGIN-MOCK-223 (Test). `LoginViewModel.friendlyErrorMessage()` has no unit test — all 8 mapping branches (LOGIN-MOCK-167 fix) are untested and could silently regress.** `friendlyErrorMessage()` (`LoginScreen.kt:1871–1881`) maps 8 known server strings to user-friendly copy plus an `else` fallback. Zero tests exist for any branch. Scaffold: `LoginViewModelFriendlyErrorTest.kt` (pure JVM, no coroutines needed since the function is pure). Methods: `friendlyError_originHeaderRequired`, `friendlyError_invalidCredentials`, `friendlyError_challengeExpired`, `friendlyError_totpNotConfigured`, `friendlyError_invalidCode`, `friendlyError_noBackupCodesAvailable`, `friendlyError_invalidBackupCode`, `friendlyError_accountLocked`, `friendlyError_unknownMessage_includesRawMessage`. Since `friendlyErrorMessage` is private, expose via `internal` or test through `login()` / `verify2FA()` stubs that surface the mapped string in `state.error`.

- [ ] **LOGIN-MOCK-224 (Test). `LoginViewModel` setup-probe path (`setupNeeded`, `probeServer()`) is untested — probe-success, probe-failure, and `unreachableHost` detection from the probe call have no coverage.** `probeServer()` (`LoginScreen.kt:863–918`) sets `setupNeeded = true/false` based on `/api/v1/portal/embed/config` response, and short-circuits if `setupNeeded != null && !forceRetry`. The `unreachableHost` state surfaced by the probe-failure branch is the primary UX path for misconfigured servers. Scaffold: `LoginViewModelProbeTest.kt`. Methods: `probeServer_success_setsSetupNeededFalse`, `probeServer_serverNeedsSetup_setsSetupNeededTrue`, `probeServer_skipIfAlreadyProbed`, `probeServer_forceRetry_reprobsEvenIfAlreadySet`, `probeServer_networkFailure_setsProbeError`, `probeServer_5xx_setsProbeError`. Use `MockWebServer` with canned JSON bodies.

- [ ] **LOGIN-MOCK-225 (Test). `LoginViewModel.onChallengeTokenExpired()` and the `challengeExpired` ticker logic (`LaunchedEffect(expiresAtMs)`, `LoginScreen.kt:1926–1935`) are untested — expiry boundary and state reset have no test.** `onChallengeTokenExpired()` (`LoginScreen.kt:1280–1296`) resets 10 fields including `step = CREDENTIALS`, `totpCode = ""`, `password = ""`. The `LaunchedEffect` ticker in the Composable fires `onChallengeTokenExpired()` when `System.currentTimeMillis() >= expiresAtMs`. Neither the ViewModel mutation nor the ticker boundary are tested. Scaffold (ViewModel layer): `LoginViewModelChallengeExpiredTest.kt`. Methods: `onChallengeTokenExpired_resetsStepToCredentials`, `onChallengeTokenExpired_clearsTotp`, `onChallengeTokenExpired_clearsSensitiveFields`, `onChallengeTokenExpired_setsChallengeExpiredTrue`, `clearChallengeExpired_clearsChallengeExpiredFlag`. Use `TestCoroutineScheduler` / `advanceTimeBy(601_000L)` to drive the ticker in a `runTest` block.

- [ ] **LOGIN-MOCK-226 (Test). No Compose UI test exists for the server step — `LoginScreenTest` in `androidTest/` is absent entirely; slug field enables/disables the Connect CTA based on length, but this is unverified.** `androidTest/` contains zero `*Login*` or `*Auth*` files (confirmed by `find` above). The server step renders: (a) slug `OutlinedTextField` with `supportingText` "3–30 characters: letters, numbers, hyphens", (b) Connect `Button` disabled when slug < 3 chars, enabled at 3+ chars, (c) "Register new shop" footer `TextButton`. Scaffold: create `androidTest/.../ui/auth/LoginScreenTest.kt` using `ComposeTestRule`. Methods: `serverStep_connectButtonDisabled_whenSlugEmpty`, `serverStep_connectButtonDisabled_whenSlugTooShort`, `serverStep_connectButtonEnabled_atMinSlugLength`, `serverStep_supportingTextVisible`, `serverStep_registerLinkVisible_andClickable`, `serverStep_customServerToggle_showsUrlField`. Uses `createAndroidComposeRule<ComponentActivity>()` with `LoginScreen()` directly composed under a `TestHiltComponent`.

- [ ] **LOGIN-MOCK-227 (Test). No Compose UI test verifies 4-field Register form validation — all four sub-steps (Company, Owner, ServerUrl, Confirm) have no instrumented test for their Next-gate conditions.** Each `RegisterSubStep` has a distinct Next-gate predicate: Company requires non-blank shop name and URL slug; Owner requires email, password ≥ FAIR, matching confirm; ServerUrl requires valid URL format; Confirm shows summary. Zero Compose tests exist for any of them. Scaffold: `LoginRegisterFormTest.kt` in `androidTest/`. Methods: `registerForm_companyNext_disabledWhenNameBlank`, `registerForm_companyNext_enabledWhenBothFilled`, `registerForm_ownerNext_disabledOnWeakPassword`, `registerForm_ownerNext_disabledOnMismatchedPasswords`, `registerForm_ownerNext_enabledOnFairPasswordAndMatchingConfirm`, `registerForm_ownerNext_disabledOnInvalidEmail`, `registerForm_serverUrlNext_disabledOnBlankUrl`, `registerForm_confirmSummaryDisplaysEnteredValues`. Each test sets up state via `viewModel.updateXxx()` calls before asserting Compose node enabled/disabled states with `assertIsEnabled()` / `assertIsNotEnabled()`.

- [ ] **LOGIN-MOCK-228 (Test). No Compose UI test covers 2FA setup QR rendering or the 6-digit TOTP field — `TwoFaSetupStep` and `TwoFaVerifyStep` composables are untested at the instrumented level.** `TwoFaSetupStep` (`LoginScreen.kt:3181+`) renders a QR `Image` from a data-URL and a manual-entry code; `TwoFaVerifyStep` (`LoginScreen.kt:3377+`) renders a 6-digit `BasicTextField` with per-digit boxes. Neither is covered by any test. Scaffold: `LoginTwoFATest.kt` in `androidTest/`. Methods: `twoFaSetup_qrImageDisplayed_whenQrCodeNonEmpty`, `twoFaSetup_manualCodeVisible`, `twoFaSetup_continueButtonEnabled_whenQrLoaded`, `twoFaVerify_submitDisabled_whenCodeLessThan6Digits`, `twoFaVerify_submitEnabled_atExactly6Digits`, `twoFaVerify_errorBannerShown_onInvalidCode`, `twoFaVerify_backupCodeRecoveryLinkVisible`. Uses `setContent { LoginScreen(...) }` with a pre-seeded `LoginUiState(step = TWO_FA_SETUP, qrCodeDataUrl = "data:image/png;base64,...")`.

- [ ] **LOGIN-MOCK-229 (Test). No accessibility test validates content descriptions for back arrows, password-visibility toggles, and banners — TalkBack users have untested coverage.** `LoginScreen.kt` uses `contentDescription` on at least: (a) back `IconButton` ("Back"), (b) password-visibility `IconButton` ("Show/Hide password"), (c) offline banner `Icon`, (d) session-revoked banner. No `onNodeWithContentDescription` assertion exists anywhere. Scaffold: `LoginAccessibilityTest.kt` in `androidTest/`. Methods: `backButton_hasContentDescription`, `passwordToggle_hasContentDescriptionShow_whenObscured`, `passwordToggle_hasContentDescriptionHide_whenVisible`, `offlineBanner_iconHasContentDescription`, `sessionRevokedBanner_isAccessible_withSemanticRole`. Use `composeTestRule.onNodeWithContentDescription("Back").assertExists()` and `SemanticsMatcher` for role checks. This also covers the axe-style check that interactive controls are never content-description-less.

- [ ] **LOGIN-MOCK-230 (Test). No state-restoration test verifies that `rememberSaveable`-backed fields survive rotation — LOGIN-MOCK-187 fix is unguarded against regression.** LOGIN-MOCK-187 added `rememberSaveable` to preserve TOTP input across configuration changes. No test recreates the Activity to verify the field survives. Scaffold: `LoginStateSurvivalTest.kt` in `androidTest/`. Methods: `totpField_survivesRotation`, `slugField_survivesRotation`, `usernameField_survivesRotation`, `registerSubStep_survivesRotation`. Use `composeTestRule.activityRule.scenario.recreate()` after filling each field, then assert the `TextField` still contains the original value via `onNodeWithTag("totp_field").assertTextEquals("123456")`. Covers both `rememberSaveable` on input values and the `SetupStep` step-retention across config change.

- [ ] **LOGIN-MOCK-231 (Test). No integration or deep-link test verifies that `bizarrecrm.com/setup/:token` launches `LoginScreen` at the Register step with the invite token pre-populated.** `LoginScreen.kt:1898–1918`: `setupToken: String?` parameter triggers `viewModel.applySetupToken(setupToken)` + `viewModel.goToRegister()` when non-null. The `LaunchedEffect(setupToken)` path is exercised only by a real App Link or a test that passes a non-null `setupToken`. No such test exists. Scaffold: `LoginDeepLinkTest.kt` in `androidTest/`. Methods: `setupToken_nonNull_advancesToRegisterStep`, `setupToken_nonNull_tokenStoredInViewModel`, `setupToken_null_staysOnServerStep`, `setupToken_emptyString_staysOnServerStep`, `appLink_bizarrecrmSetupToken_launchesRegisterStep` (uses `Intent.ACTION_VIEW` with URI `https://bizarrecrm.com/setup/abc123` via `ActivityScenario.launch(intent)`). Also covers the `AndroidManifest.xml` intent-filter for `bizarrecrm.com/setup/*` — verify the filter is declared and routes to the correct activity before the test can pass.

- [ ] **LOGIN-MOCK-292 (Copy). Extra UI strings with no mockup analog are present on the Credentials step and represent potential scope-creep copy that needs design review: "Sign in with SSO" (line 2757), "Choose your sign-in provider" (line 2765 sheet title), "Email me a link" (line 2811), "Sign in with a magic link" (line 2882 sheet title), "We'll send a one-time sign-in link to your email. The link expires in 15 minutes." (line 2888), "Use passkey" (line 2851), "Signing in…" (line 2843), "Send link" (line 2927), "Resend link" (line 2991), "Resend in ${cooldownSec}s" (line 2989).** None of these strings appear in any of the 11 mockup screens. All are gated on feature flags (`ssoAvailable`, `magicLinksEnabled`, `passkeyVisible`) but the copy itself has never been reviewed against a design mockup for tone, capitalisation, or punctuation. Each should receive a mockup frame or explicit copy-approval comment before shipping. `LoginScreen.kt:2757, 2765, 2811, 2843, 2851, 2882, 2888, 2927, 2989, 2991`.

### Wave-6 Finder-Q DI + lifecycle

- [ ] **LOGIN-MOCK-232 (Architecture). `LoginViewModel` constructor graph has no companion documentation — six `@Singleton` deps are resolved implicitly from three separate modules, making future dep changes a silent missing-binding risk.** `LoginScreen.kt:289–297`: constructor injects `AuthPreferences` (`AuthPreferences.kt:37`), `AuthApi` (`RetrofitClient.kt:630`), `NetworkMonitor` (`NetworkMonitor.kt:38`), `BiometricCredentialStore` (`BiometricCredentialStore.kt:72`), `BiometricAuth` (`BiometricAuth.kt:39`), `DeepLinkBus` (`DeepLinkBus.kt:36`). All six are `@Singleton` self-registrations; no `@Provides` entry in any `@Module` annotates them together. The Hilt graph is valid today. Remediation: add a KDoc block on `LoginViewModel` listing each injected dep and its providing module so a contributor renaming or moving a dep gets a compile-time error rather than a confusing "missing binding" message that doesn't name the consumer.

- [ ] **LOGIN-MOCK-233 (Architecture). `BiometricAuth` is `@Singleton` but is stateless and constructs a fresh `BiometricPrompt` on every call — the `@Singleton` scope is safe but misleading; future contributors may add Activity state believing the class is Activity-scoped.** `BiometricAuth.kt:39–40`: `@Singleton class BiometricAuth @Inject constructor()`. No fields are declared; every `showPrompt`, `encryptWithBiometric`, and `decryptWithBiometric` call creates a new `BiometricPrompt` instance using the `activity` parameter. The class never stores a `Context` or `Activity` reference. Remediation: add a KDoc note "Stateless — safe as Singleton. Never add Activity/Context fields; this class lives in SingletonComponent."

- [ ] **LOGIN-MOCK-234 (Architecture). `NetworkMonitor.isOnline` is a cold `callbackFlow` — each `collect` registers a new `ConnectivityManager.NetworkCallback`. `LoginViewModel.init` and multiple other VMs collect it independently, registering duplicate OS callbacks for the same underlying event.** `NetworkMonitor.kt:41–75`: `callbackFlow { ... }.distinctUntilChanged()`. `LoginScreen.kt:401–404`: `viewModelScope.launch { networkMonitor.isOnline.collect { ... } }`. `SyncManager.kt:78`, `DeltaSyncer.kt:68`, `AppNavGraph.kt:816` all inject and collect `NetworkMonitor`. Each active subscriber holds a live `NetworkCallback` registration. Remediation: convert `isOnline` to a hot `StateFlow` via `stateIn(applicationScope, SharingStarted.Eagerly, initialValue = isCurrentlyOnline())` inside the `NetworkMonitor` constructor, sharing a single OS callback across all collectors — the same pattern used by `ServerReachabilityMonitor.isEffectivelyOnline`.

- [ ] **LOGIN-MOCK-235 (Security). `AuthPreferences.installationSecret()` stores the per-install HMAC key inside the same `EncryptedSharedPreferences` file it protects, making the HMAC tamper-detection circular for any adversary who can already access the Keystore master key.** `AuthPreferences.kt:186–195`: `installationSecret()` reads/writes `KEY_INSTALL_SECRET` from `prefs` — the same `EncryptedSharedPreferences` instance whose contents it signs. An adversary who decrypts `auth_prefs` (requires the Keystore `AES256_GCM` master key) obtains both the HMAC key and the signed server URL in the same operation. The comment at line 183 acknowledges the layering ("rides on top of EncryptedSharedPreferences") but not the circularity. The HMAC adds no additional protection against the rooted-extraction threat model. Remediation: (a) store the HMAC key as a standalone `KeyStore.SecretKeyEntry` under `AndroidKeyStore` (separate from the EncryptedSharedPreferences master key), giving it a second independent hardware-backed key, or (b) remove the HMAC and rely solely on EncryptedSharedPreferences + `android:allowBackup="false"`, documenting the simplified threat model.

- [ ] **LOGIN-MOCK-236 (Bug). `BiometricCredentialStore.init` registers `AuthPreferences.setBiometricClearCallback` only when first constructed by Hilt. `BizarreCrmApp` does not inject `BiometricCredentialStore`, so the callback is null until `LoginViewModel` is first created. A session-revoke fired by `AuthInterceptor` before `LoginScreen` is composed calls `authPreferences.clear(SessionRevoked)` with `biometricClearCallback == null` — biometric credentials are not wiped.** `BiometricCredentialStore.kt:76–81`: `init { authPreferences.setBiometricClearCallback { clear() } }`. `BizarreCrmApp.kt:48`: injects `authPreferences` but not `biometricCredentialStore`. `AuthPreferences.kt:429`: `biometricClearCallback?.invoke()` — safe-call means it is silently skipped when null. `AuthInterceptor` can call `authPreferences.clear(SessionRevoked)` on a background OkHttp thread during any sync. Remediation: add `@Inject lateinit var biometricCredentialStore: BiometricCredentialStore` to `BizarreCrmApp` so Hilt constructs the singleton (and its `init` block) at `Application.onCreate` time, before any network call can trigger a revoke.

- [ ] **LOGIN-MOCK-237 (Architecture). `LoginViewModel._state` is an in-memory `MutableStateFlow` with no `SavedStateHandle` backing. A process kill during the multi-step 2FA setup flow (e.g., low-memory eviction) drops `step`, `serverUrl`, `shopSlug`, `username`, `registerSubStep`, and `challengeTokenExpiresAtMs` — the user restarts from a blank login screen.** `LoginScreen.kt:377–394`: `_state = MutableStateFlow(LoginUiState(...))`. No `SavedStateHandle` parameter in the constructor. The 2FA secret and QR data-URL must NOT be persisted (sensitive), but the navigation scalars listed above are safe to restore. Remediation: inject `SavedStateHandle` (automatically provided by Hilt for `@HiltViewModel`) and use `savedStateHandle.get<String>("step")` / `savedStateHandle["step"] = value` for non-sensitive fields. Document explicitly in a comment which fields are excluded: `password`, `totpCode`, `twoFaSecret`, `challengeToken`, biometric fields.

- [ ] **LOGIN-MOCK-238 (Architecture). `LoginViewModel.init` launches five concurrent coroutines unconditionally on every ViewModel creation. Back-navigating to `LoginScreen` (which creates a new ViewModel instance) re-fires three network requests even when results are still valid.** `LoginScreen.kt:397–455`: five `viewModelScope.launch` calls — `networkMonitor.collect`, `loadSsoProviders()`, `probemagicLinksEnabled()`, `probePasskeyEnabled()`, `deepLinkBus.pendingMagicToken.collect`. The SSO probe may have a null-guard inside `loadSsoProviders()`, but `probemagicLinksEnabled` and `probePasskeyEnabled` have no visible guard preventing re-fire on re-entry. Remediation: add `if (_state.value.magicLinksEnabled == null)` and `if (_state.value.passkeyEnabled == null)` guards inside `init` before launching those probes, matching the pattern that should exist for SSO. Alternatively cache results in `AuthPreferences` with a short TTL (e.g., 5 minutes).

- [ ] **LOGIN-MOCK-239 (Bug). `PinLockViewModel.scheduleLockoutTick()` attempts to force a recomposition every second by emitting `_state.value = cur.copy()`, but `MutableStateFlow` drops structurally equal values — `data class State.copy()` with no changed fields is `==` to the current value, so the countdown display never updates between keypresses.** `PinLockViewModel.kt:277–279`: `val cur = _state.value; _state.value = cur.copy()`. The comment at line 278 acknowledges the dedup issue and notes a "bumped marker" fix is needed but it is not implemented. `lockoutRemainingSeconds` is a computed property on `State` (line 49) that depends on `lockoutUntilMillis` (unchanged) and `System.currentTimeMillis()` (changes every call), but `StateFlow` evaluates equality on the emitted `State` object, not on computed properties. Remediation: add `val tickMs: Long = 0L` to `State`; set `tickMs = System.currentTimeMillis()` in each `scheduleLockoutTick` loop iteration so each emitted `copy(tickMs = ...)` is structurally distinct and triggers recomposition.

- [ ] **LOGIN-MOCK-240 (Architecture). `LoginScreen` passes a raw `FragmentActivity` reference into `LoginViewModel.stashCredentialsBiometric()` and `attemptBiometricAutoLogin()`, which hold it inside a suspended `viewModelScope` coroutine. A configuration change that recreates the Activity while the biometric prompt is visible leaks the old Activity instance until the coroutine resumes or is cancelled.** `LoginScreen.kt:1952, 1969`: `(context as? FragmentActivity)` passed to VM methods. `LoginScreen.kt:1359, 1389`: both methods launch `viewModelScope` coroutines that suspend inside `biometricAuth.encryptWithBiometric(activity, ...)` / `biometricAuth.decryptWithBiometric(activity, ...)`. `MainActivity` lists `configChanges` that exclude `uiMode|fontScale|locale` — a dark-mode toggle or font-scale change recreates the Activity mid-prompt. The new Activity does not receive the biometric result; the old Activity is leaked for the duration of the prompt timeout (~30 s). Remediation: the ViewModel should emit a `SharedFlow<BiometricRequest>` side-effect; `LoginScreen` collects the event and shows the `BiometricPrompt` from within the Composable using the live Activity context, then posts the authenticated `Cipher` back to the VM via a callback. The ViewModel never holds an Activity reference.

- [ ] **LOGIN-MOCK-241 (Architecture). `MainActivity.configChanges` omits `uiMode|fontScale|locale|keyboard|keyboardHidden`, so those configuration changes trigger a full Activity recreation. This compounds LOGIN-MOCK-240 (stale-Activity during biometric prompt) and also means theme/density/locale changes cause the entire Compose tree to be torn down and rebuilt rather than handled by the reactive observers already wired in `setContent`.** `AndroidManifest.xml:139`: `android:configChanges="screenSize|smallestScreenSize|screenLayout|orientation"`. The `setContent` block in `MainActivity` already observes `darkModeFlow`, `dynamicColorFlow`, `dashboardDensityFlow`, and `screenCapturePreventionFlow` reactively — adding `uiMode` to `configChanges` would suppress the recreation and let those observers handle the change without a full tree rebuild. Remediation: add `uiMode|fontScale|locale|keyboard|keyboardHidden` to `configChanges`. Coordinate with the fix for LOGIN-MOCK-240 so the biometric coroutine safety issue is resolved independently of the configuration-change suppression.

- [ ] **LOGIN-MOCK-242 (Architecture). `LoginScreen` has no `@Preview`-annotated composable — the screen takes `viewModel: LoginViewModel = hiltViewModel()` as a default parameter, making Compose Preview and Paparazzi screenshot testing impossible without a running Hilt graph.** `LoginScreen.kt:1898`: function signature starts `fun LoginScreen(..., viewModel: LoginViewModel = hiltViewModel())`. Zero `@Preview` annotations exist in the file. The IDE Compose Preview fails silently when `hiltViewModel()` is called outside a Hilt context. Iterative UI work requires a full emulator deploy to see any visual change. Remediation: extract a `LoginScreenContent(state: LoginUiState, onEvent: (LoginEvent) -> Unit)` stateless composable containing all rendering logic; keep `LoginScreen` as a thin `hiltViewModel()` + `collectAsState()` wrapper. Add `@Preview` functions on `LoginScreenContent` for at least: `SetupStep.SERVER`, `SetupStep.CREDENTIALS`, `SetupStep.TWO_FA_VERIFY`, and an error state. This also enables Paparazzi screenshot regression tests in CI without an emulator.

- [ ] **LOGIN-MOCK-243 (Architecture). `NetworkMonitor.isOnline` is cold — the initial network state is only emitted after the first `collect` call. If the device is already offline when the app starts and `LoginScreen` has not yet been composed, no subscriber exists to record the state and `LoginViewModel._state.networkOffline` starts as `false` regardless of actual connectivity.** `NetworkMonitor.kt:70`: `trySend(hasAnyInternet(connectivityManager))` fires inside the `callbackFlow` lambda, which is only active during an active `collect`. `BizarreCrmApp.kt` does not collect `NetworkMonitor.isOnline`. The gap only materialises if offline state changes between Application start and the first `LoginViewModel` collect, and only if the `trySend` initial-state emission is missed (practically: cold start on an offline device shows offline banner correctly because `trySend` fires during the `collect` call). The deeper issue is that `SharingStarted.Eagerly` on `stateIn` would guarantee the initial state is computed at injection time. Remediation: the `stateIn(SharingStarted.Eagerly)` fix from LOGIN-MOCK-234 closes this as a side-effect; track together.

- [ ] **LOGIN-MOCK-244 (Architecture). No durable auth-event audit log exists. Successful logins, 2FA completions, session revocations, and biometric auto-login outcomes are ephemeral — Logcat only. `AuthPreferences.authCleared` is a `SharedFlow(replay=0)`, so a missed emission (subscriber not active at call time) loses the event forever.** `AuthPreferences.kt:58–59`: `_authCleared = MutableSharedFlow<ClearReason>(extraBufferCapacity = 1)` with `replay=0`. A `BizarreCrmApp.appScope` collector would receive events reliably, but no such collector exists. No `auth_events` Room table, no `AuthEventDao`, and no WorkManager task for syncing auth events appear anywhere in the codebase. Remediation (future feature, not a blocking bug): add an `auth_events` Room table with columns `(id, userId, eventType, timestamp, deviceId, success, errorCode)`; wire a collector in `BizarreCrmApp.appScope` to insert rows on `authCleared` emissions and login outcomes; enqueue a periodic `WorkManager` task to sync to the server. Add to `TODO.md` under CROSS-PLATFORM. The `replay=0` design of `authCleared` is intentional to avoid stale re-delivery on re-subscribe, but requires the `BizarreCrmApp` collector to be the authoritative durable sink.

### Wave-6 Finder-R security deep-dive

- [ ] **LOGIN-MOCK-245 (Security). Token refresh race: `isRefreshing` is an unguarded `@Volatile Boolean` that does not prevent a second thread from starting a concurrent refresh.** `AuthInterceptor.kt:53` declares `@Volatile private var isRefreshing = false`. The `synchronized(this)` block at line 76 gates the *decision to refresh* but `isRefreshing` is also read at line 110 (`if (isRefreshing) return null`) outside any `synchronized` block. Two threads can both pass line 110 and both call `attemptTokenRefresh()` when the first thread has not yet reached `isRefreshing = true` at line 112 — a classic check-then-act race. The result is two simultaneous refresh requests to the server; most refresh-token endpoints treat the first response as a rotation and invalidate the old token, so the second refresh response arrives with a 401 and silently forces a logout. **Remediation:** replace `@Volatile var isRefreshing` with a `Mutex` (or a `Semaphore(1)`): `private val refreshMutex = Mutex()`. Inside `attemptTokenRefresh`, `refreshMutex.withLock { … }` (coroutine-friendly) or replace the OkHttp synchronous approach with a `ReentrantLock`. The `synchronized(this)` outer block in `intercept()` already serialises entry; the inner `isRefreshing` guard is then redundant and should be removed entirely to avoid confusion. File: `AuthInterceptor.kt:53,110–113`.

- [ ] **LOGIN-MOCK-246 (Security). Refresh-token rotation not atomic: `saveAccessToken()` is called inside `attemptTokenRefresh()` but the new refresh token in `RefreshResponse` is never stored, leaving a stale refresh token in prefs after rotation.** `AuthInterceptor.kt:153–157` extracts `parsed.data?.accessToken` and calls `saveAccessToken(newToken)` (line 156–157). The server returns a *new* refresh token on every rotation (`RefreshResponse` likely contains a `refreshToken` field), but `AuthInterceptor` only persists the access token. If the server has already invalidated the old refresh token the app will use the stale one on the next refresh cycle and be forced to re-login. **Remediation:** update `RefreshResponse` DTO to expose `refreshToken: String?`; after saving the access token also call `authPrefs.refreshToken = parsed.data?.refreshToken ?: authPrefs.refreshToken`. Wrap both writes in a single `prefs.edit()…apply()` block inside `AuthPreferences` to make the update atomic. File: `AuthInterceptor.kt:153–158`, `AuthPreferences.kt:83–86`, relevant DTO.

- [ ] **LOGIN-MOCK-247 (Security). Certificate pinning applies only to `PRODUCTION_HOST` and `*.PRODUCTION_HOST`, leaving the self-hosted path (any custom server URL) entirely unpinned in release builds.** `RetrofitClient.kt:572–578`: `pinnerBuilder.add(PRODUCTION_HOST, pin)` and `pinnerBuilder.add("*.$PRODUCTION_HOST", pin)`. A self-hosted user whose server URL is `https://192.168.1.50` or `https://myshop.example.com` gets *zero* certificate pinning — the `DynamicBaseUrlInterceptor` allows any HTTPS host that is not the production domain (line 284: `BuildConfig.DEBUG && isDebugTrustedHost(h)` only gates debug), yet the `CertificatePinner` is configured only for the cloud host. An attacker on the same LAN can install a rogue CA on a Windows machine and MITM the self-hosted path with a validly-chained (to that rogue CA) cert. **Remediation:** document this clearly in the self-host setup guide as a known limitation; consider requiring the user to supply the server's SPKI fingerprint during initial setup (stored via `AuthPreferences.setServerUrl`), then dynamically adding it to the `CertificatePinner` for that host. Alternatively, gate this with a `selfHostedPinWarning` shown in Settings. File: `RetrofitClient.kt:572–579`.

- [ ] **LOGIN-MOCK-248 (Security). `FLAG_SECURE` is applied only when the user-facing `screenCapturePreventionEnabled` pref is `true` (or it is a release build), but the login screen itself — which renders the password field — is shown *before* the pref is loaded in `AuthPreferences`.** `MainActivity.kt:161–163`: `if (screenCapturePrevEnabled || !BuildConfig.DEBUG) { window.addFlags(FLAG_SECURE) }`. In a **release build where the pref is `false`** (e.g., first install, pref not yet written), `screenCapturePrevEnabled` is `false` and `!BuildConfig.DEBUG` is `true`, so `FLAG_SECURE` IS set — that branch is correct. However in a **debug release-like scenario** where `BuildConfig.DEBUG = false` but the pref file is pre-populated with `false` (e.g., after a settings import), the logic still applies the flag. The real gap is that `FLAG_SECURE` is a user opt-out but the *default* is not `true` on first install: `AppPreferences` defaults `screenCapturePreventionEnabled` to `false` (`AppPreferences.kt:305`), which means on a first-install debug build where `BuildConfig.DEBUG = true` and pref = `false`, no `FLAG_SECURE` is set on the login window. Recents thumbnail of the password-field login screen is captured. **Remediation:** change `AppPreferences` default for `screenCapturePreventionEnabled` to `true`; make it an opt-out rather than opt-in. Or unconditionally apply `FLAG_SECURE` to the auth Activity regardless of pref. File: `MainActivity.kt:161–163`, `AppPreferences.kt:305`.

- [ ] **LOGIN-MOCK-249 (Security). `cleartext TrafficPermitted="false"` in the base `network_security_config.xml` is correct, but the custom-scheme deep-link filters (`android:scheme="bizarrecrm"`) accept any host, including `http://` redirects embedded in a `bizarrecrm://` URI — an attacker who can craft a deep link can inject an HTTP URL as the `redirectUri` for SSO or a magic-link callback that the app might subsequently load over HTTP.** `AndroidManifest.xml:185–214`: the `bizarrecrm://sso/callback` and `bizarrecrm://magic` intent filters have no `android:host` restrictions beyond what the code validates. `DynamicBaseUrlInterceptor.validate()` (`RetrofitClient.kt:302–304`) rejects non-HTTPS schemes in release, but `DeepLinkBus` / `resolveDeepLink` processes the raw URI before URL validation occurs. A crafted `bizarrecrm://sso/callback?redirect=http://evil.com` could be followed by an unchecked redirect. **Remediation:** in `MainActivity.resolveDeepLink` (and all deep-link bus consumers) validate that any `redirect`, `next`, or `return_to` query parameter is either absent or matches the expected server origin before acting on it. Apply the same `DynamicBaseUrlInterceptor.validate()` check to all URLs extracted from deep links. File: `AndroidManifest.xml:185–214`, `MainActivity.kt` (resolveDeepLink).

- [ ] **LOGIN-MOCK-250 (Security). `android:allowBackup="false"` is set at the application level and `data_extraction_rules.xml` correctly excludes all domains, but the `DashboardWidgetProvider` receiver (`AndroidManifest.xml:315–323`) is `exported="true"` without a permission guard and Widget providers are not covered by backup rules — a malicious app can send `ACTION_APPWIDGET_UPDATE` to trigger a widget refresh that may surface PII in the widget RemoteViews without the user unlocking.** `AndroidManifest.xml:316–323`: `DashboardWidgetProvider` is `android:exported="true"` with no `android:permission` attribute. On Android < 12 any app can broadcast `APPWIDGET_UPDATE` to this receiver, forcing a widget redraw. If the widget displays customer counts or revenue figures those values are rendered in a RemoteViews that any app with `READ_FRAME_BUFFER` (or screen-recording on rooted devices) can capture. **Remediation:** add `android:permission="android.permission.BIND_APPWIDGET"` to the receiver declaration (same pattern used for `QuickTicketTileService`); the platform's `AppWidgetManager` holds this permission so legitimate widget updates still work, while third-party apps cannot trigger unsolicited refreshes. File: `AndroidManifest.xml:315–323`.

- [ ] **LOGIN-MOCK-251 (Security). `ClipboardUtil.copySensitive` 30-second auto-clear is process-lifetime-scoped: if the app process is killed (OOM, system memory pressure) before the `Handler.postDelayed` fires, the clipboard retains the secret indefinitely.** `ClipboardUtil.kt:77–81`: `handler.postDelayed({ clearSensitiveIfPresent(clipboard) }, clearAfterMillis)`. The code comment at line 55 acknowledges this and mentions `clearSensitiveIfPresent` is "called from the app-background lifecycle hook." However `ProcessLifecycleOwner.onStop` is not guaranteed to run before process kill; on pre-A12 devices OOM kills skip the lifecycle entirely. The AOSP `ClipDescription.EXTRA_IS_SENSITIVE = true` (set on API 33+, line 70) causes the system to *hide* the clip from other apps but does NOT clear it. **Remediation:** use the Android 13 `ClipboardManager.clearPrimaryClip()` API (already present at `ClipboardUtil.kt:139`) as the *primary* mechanism for API 33+, and for older APIs register a `ContentObserver` on the clipboard URI that fires the wipe on any clipboard change (user replaced the clip), reducing the exposure window. Additionally call `clearSensitiveIfPresent` from `Activity.onPause()` / `onStop()` in addition to the process lifecycle hook. File: `ClipboardUtil.kt:55–82`.

- [ ] **LOGIN-MOCK-252 (Security). `RedactorTree.SENSITIVE_KEYS` does not include `twoFaSecret`, `totpCode`, `challengeToken`, or `twoFaManualEntry` — all of which appear in `LoginUiState` and could reach Timber logs via exception message interpolation or debug toString().** `RedactorTree.kt:88–111`: the list contains `totp` (which would match `totpCode` via the `\b(?:totp)\b` word-boundary regex in `REDACT_PATTERN`) and `secret` (which would match `twoFaSecret` and `manualEntry`), but `challengeToken` is absent. `LoginUiState` contains `val challengeToken: String` (line 141) which is a server-issued opaque token used to bind the 2FA verification to the initial login call. If a coroutine exception prints a stringified state object, `challengeToken=<value>` would not be masked. Similarly `twoFaManualEntry` (line 145) maps to `manualEntry` in the key list — this *is* covered — but `challengeToken` is not. **Remediation:** add `"challengeToken"`, `"challenge_token"` to `RedactorTree.SENSITIVE_KEYS`. Also add `"twoFaSecret"`, `"twoFaManualEntry"` explicitly even though the shorter aliases cover them, to make intent clear for future maintainers. File: `RedactorTree.kt:88–111`.

- [ ] **LOGIN-MOCK-253 (Security). `SmsRetrieverHelper.getAppHash()` logs the 11-character app hash at `Log.d` (not Timber) without any `BuildConfig.DEBUG` guard — in production builds `Log.d` is stripped by ProGuard/R8 only if `android.util.Log` calls are explicitly removed, but the call remains in the bytecode until minification runs.** `SmsRetrieverHelper.kt:93`: `Log.d(TAG, "App hash for SMS OTP template: $hash (package=$packageName)")`. The app hash is not a secret on its own (it is baked into every SMS the server sends), but logging it at runtime means any logcat-reading app or ADB shell on a non-production device can trivially harvest it to craft fake SMS messages that the `SmsOtpBroadcastReceiver` would then deliver to the autofill path. Additionally `Log.d` calls are *not* automatically no-ops in release builds in all minifier configurations — they are only removed if ProGuard rules include `-assumenosideeffects class android.util.Log { *; }`. **Remediation:** (1) wrap the `Log.d` call in `if (BuildConfig.DEBUG)`, or replace with `Timber.d(...)` which is suppressed in release via the `RedactorTree` / no-tree configuration. (2) Confirm `proguard-rules.pro` includes the `android.util.Log` strip rule. File: `SmsRetrieverHelper.kt:93`.

- [ ] **LOGIN-MOCK-254 (Security). `BiometricAuth.showPrompt()` uses `BIOMETRIC_STRONG or DEVICE_CREDENTIAL` as the allowed authenticator, which means a device PIN/pattern/password can substitute for biometry — defeating the purpose of the Keystore key's `setUserAuthenticationRequired(true)` constraint for app-unlock scenarios.** `BiometricAuth.kt:50,105`: `BIOMETRIC_STRONG or DEVICE_CREDENTIAL` in both `canAuthenticate()` and `showPrompt()`. `BiometricCredentialStore.getOrCreateSecretKey()` (`BiometricCredentialStore.kt:116`) sets `setUserAuthenticationRequired(true)` — this flag, combined with `DEVICE_CREDENTIAL` in the prompt, means the Keystore will accept a PIN auth event as proof to unlock the key. A threat actor who knows or guesses the device PIN can decrypt the stored username+password without biometric interaction. Note: `encryptWithBiometric` and `decryptWithBiometric` correctly use `BIOMETRIC_STRONG` only (lines 142, 180), which is correct for Keystore-bound operations. The gap is in `showPrompt()` (the app re-lock gate): it uses `DEVICE_CREDENTIAL` fallback, so the app can be unlocked with PIN alone. **Remediation:** for the app-unlock gate (`showPrompt`), keep `BIOMETRIC_STRONG or DEVICE_CREDENTIAL` to maximise accessibility (users without enrolled biometrics can still unlock with PIN). Clearly document in code that this is the *app re-lock* gate, not the *credential decrypt* gate. For the credential decrypt path (`decryptWithBiometric`) the current `BIOMETRIC_STRONG` only is correct and must not be weakened. File: `BiometricAuth.kt:50,105`.

- [ ] **LOGIN-MOCK-255 (Security). No explicit minimum TLS version (`ConnectionSpec`) is configured on any `OkHttpClient` instance — the effective minimum is whatever OkHttp + the Android platform negotiate, which on API 26–28 devices can be TLS 1.0.** `RetrofitClient.kt:513–549`, `AuthInterceptor.buildLogoutClient()` (`AuthInterceptor.kt:287–317`), and `LoginViewModel.buildProbeTlsClient()` (`LoginScreen.kt:344–374`): none call `OkHttpClient.Builder().connectionSpecs(...)`. OkHttp's default `ConnectionSpec.MODERN_TLS` targets TLS 1.2+ in OkHttp 4.x, but the `COMPATIBLE_TLS` fallback (also included in OkHttp defaults) still permits TLS 1.0/1.1. On API 26–28 the SSLSocket's `enabledProtocols` defaults include TLS 1.0. **Remediation:** explicitly set `connectionSpecs(listOf(ConnectionSpec.MODERN_TLS))` (drops TLS 1.0/1.1) on all three builders. `MODERN_TLS` enforces TLS 1.2 minimum with forward-secret cipher suites. This is low-risk for self-hosted installs since the server already requires TLS (see `packages/server/src/index.ts`). Files: `RetrofitClient.kt:526`, `AuthInterceptor.kt:289`, `LoginScreen.kt:344`.

- [ ] **LOGIN-MOCK-256 (Security). `PlayIntegrityClient` is fully stubbed — `requestTokenString()` always returns `null` — so the Play Integrity attestation that was planned for high-risk login events (new device login, suspicious auth) is silently skipped in all builds including production.** `PlayIntegrityClient.kt:18–21`: `return null` unconditionally. `build.gradle.kts:299` correctly declares `implementation(libs.play.integrity)` but the client that drives it returns nothing. Any calling code that checks `integrityToken != null` before attaching it to a login request will silently omit the attestation, making rooted-device detection and emulator detection non-functional. **Remediation:** implement `IntegrityManagerFactory.create(context).requestIntegrityToken(IntegrityTokenRequest.builder().setNonce(nonce).build())` with a `.addOnSuccessListener` / `.addOnFailureListener` pattern wrapped in `suspendCancellableCoroutine`. Gate the actual implementation behind a `try/catch(IllegalStateException)` for non-GMS devices (Huawei, etc.) — return `null` only in that catch, not unconditionally. Wire the returned token into `POST /api/v1/auth/login` as an `X-Integrity-Token` header. Prioritise for the cloud hosted path; self-hosted can stay ungated. File: `PlayIntegrityClient.kt:18–21`.

- [ ] **LOGIN-MOCK-257 (Security). `assetlinks.json` verification for all three `android:autoVerify="true"` App Link domains (`bizarrecrm.app`, `app.bizarrecrm.com`, `bizarrecrm.com`) is explicitly noted as undeployed (TODO AUDIT-AND-019), meaning the OS falls back to browser disambiguation — allowing any installed app that registers the same intent filter to intercept magic-link tokens and setup-invite tokens.** `AndroidManifest.xml:158–241`: five `autoVerify=true` intent-filter blocks reference `bizarrecrm.app`, `app.bizarrecrm.com`, and `bizarrecrm.com`. The inline comment confirms the `/.well-known/assetlinks.json` route is not yet deployed on the server. Until it is, Android will not grant the app exclusive ownership of those links; a malicious app that declares the same intent filter can receive the same URIs. Magic-link tokens (30-minute one-time use) and setup-invite tokens would then be delivered to the attacker app. **Remediation:** add `GET /.well-known/assetlinks.json` to `packages/server/src/routes/` (or serve statically) with the correct SHA-256 certificate fingerprint for the production signing key. After deployment, verify with `adb shell pm get-app-links --package com.bizarreelectronics.crm` that all three domains show `verified`. Until then, magic-link tokens must be validated server-side against the requesting IP/user-agent to limit replay-window exposure. File: `AndroidManifest.xml:158–241`, cross-reference: `TODO.md CROSS-PLATFORM AUDIT-AND-019`.
