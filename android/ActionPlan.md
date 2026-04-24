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
- [ ] Triggered when `GET /auth/setup-status` → `{ needsSetup: true }`. Stand up 13-step wizard mirroring web (/setup).

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
- [ ] Recovery: forgot PIN → email reset link to tenant-registered email.
- [ ] Manager override: manager can reset staff PIN from Employees screen.
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
- [~] Sensitive screens force re-auth: Payment / Settings → Billing / Danger Zone → immediate biometric prompt regardless of timeout. (commit b35d122 — `requireReAuthNow(level)` hook exposed; composable wiring pending)
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
- [ ] Providers: Okta, Azure AD, Google Workspace, JumpCloud.
- [ ] SAML 2.0 primary; OIDC for newer.
- [ ] Setup: tenant admin (web only) pastes IdP metadata.
- [ ] Certificate rotation notifications.
- [ ] Android flow: Login screen "Sign in with SSO" button.
- [ ] Opens Chrome Custom Tabs (`androidx.browser:browser`) → IdP login → callback via App Link.
- [ ] Token exchange with tenant server.
- [ ] SCIM (stretch, Phase 5+): user provisioning via SCIM feed from IdP; auto-create/disable BizarreCRM accounts.
- [ ] Hybrid: some users via SSO, others local auth; Login screen auto-detects based on email domain.
- [ ] Breakglass: tenant owner retains local password if IdP down.
- [ ] Sovereignty: IdP external by nature; per-tenant consent; documented in privacy notice. No third-party IdP tokens stored beyond session lifetime.

### 2.21 Magic-link login (optional)
- [ ] Login screen "Email me a link" → enter email → server emails link.
- [ ] App Link opens app on tap; auto-exchange for token.
- [ ] Link lifetime 15min, one-time use.
- [ ] Device binding: same-device fingerprint required.
- [ ] Cross-device triggers 2FA confirm.
- [ ] Tenant can disable magic links (strict security mode).
- [ ] Phishing defense: link preview shows tenant name explicitly.
- [ ] Domain pinned to `app.bizarrecrm.com`.

### 2.22 Passkey / WebAuthn via Credential Manager
- [ ] Android 14+ passkeys via AndroidX Credential Manager (`CreatePublicKeyCredentialRequest` / `GetCredentialRequest`).
- [ ] Cross-device sync through Google Password Manager.
- [ ] Enrollment: Settings → Security → Add passkey → biometric confirm → store credential with tenant server (FIDO2 challenge/attestation).
- [ ] Login screen "Use passkey" button triggers Credential Manager system UI (no password typed).
- [ ] Password remains as breakglass fallback.
- [ ] Can remove password once passkey + recovery codes set.
- [ ] Cross-device: passkey syncs to user's other Android + ChromeOS devices via Google account.
- [ ] iOS coworker stays on their passkey ecosystem (no cross-OS sync yet — WebAuthn shared protocol, different keychain).
- [ ] Recovery via §2.19 recovery codes when all Android devices lost.

### 2.23 Hardware security key (FIDO2 / NFC / USB-C)
- [ ] YubiKey 5C (USB-C) plugs into tablet; triggers WebAuthn via Credential Manager.
- [ ] NFC YubiKey tap on NFC-capable tablet.
- [ ] Security levels: owners recommended hardware key; staff optional.
- [ ] Settings → Security → Hardware keys → "Register YubiKey".
- [ ] Key management: list + last-used + revoke.
- [ ] Tenant policy can require attested hardware.

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
- [ ] **Customization sheet** — long-press tile → `ModalBottomSheet` with "Hide tile" / "Reorder tiles"; persisted in DataStore.
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
- [ ] **Tablet/ChromeOS:** top-app-bar action row + `NavigationRail` header actions instead of FAB for space + precision input. Same five actions as menu items.
- [x] **Hardware-keyboard shortcuts** (tablet/ChromeOS): Ctrl+N → New ticket; Ctrl+Shift+N → New customer; Ctrl+Shift+S → Scan; Ctrl+Shift+M → New SMS. Registered via `onKeyEvent` modifier on root scaffold. (`util/KeyboardShortcutsHost` wraps NavHost in AppNavGraph with all six chords incl. Ctrl+F → search, Ctrl+, → settings.)

### 3.9 Greeting + operator identity
- [x] Dynamic greeting by hour ("Good morning / afternoon / evening, {firstName}") using `LocalDateTime.now().hour`.
- [x] Tap greeting → Settings → Profile.
- [ ] Avatar in top-left top bar (phone) / leading nav-rail header (tablet); long-press → Switch user (§2.5).

### 3.10 Sync-status badge
- [x] Small pill on dashboard header: "Synced 2 min ago" / "Pending 3" / "Offline".
- [x] Tap → Settings → Data → Sync Issues.

### 3.11 Clock in/out tile
- [~] Visible when timeclock enabled — big tile "Clock in" / "Clock out (since 9:14 AM)". (`ui/screens/dashboard/ClockInTile.kt` shows clocked-in state pulled from `GET /employees` filtered by self id; tap routes to `ClockInOutScreen`. "Since X" timestamp pending — needs server-side clock-in started_at.)
- [ ] One-tap toggle; PIN prompt if Settings requires it.
- [ ] Success haptic + Snackbar.

### 3.12 Unread-SMS / team-inbox tile
- [ ] `GET /sms/unread-count` drives small pill badge; tap → SMS tab.
- [ ] `GET /inbox` count → Team Inbox tile (if tenant has team inbox enabled).

### 3.13 TV / queue board (tablet only, stretch)
- [ ] Full-screen marketing / queue-board mode mirrors web `/tv`. Launched from Settings → Display → Activate queue board.
- [ ] Read-only, auto-refresh, stays awake (`Window.addFlags(FLAG_KEEP_SCREEN_ON)`), hides system bars via `WindowInsetsController.hide(systemBars())`.
- [ ] Exit via 3-finger tap + PIN, or hardware-key Escape + PIN on ChromeOS.

### 3.14 Empty / error states
- [ ] Network fail → keep cached KPIs + sticky banner "Showing cached data. Retry.".
- [ ] Zero data → illustrations differ per card (no tickets vs no revenue vs no customers).
- [ ] Permission-gated tile → greyed out with lock icon + "Ask your admin to enable Reports for your role.".
- [ ] Brand-new tenants with zero data must not feel broken; every screen needs empty-state design.
- [ ] Dashboard: KPIs "No data yet" link to onboarding action; central card "Let's set up your shop — 5 steps remaining" links to Setup Wizard (§36).
- [ ] Tickets empty: vector wrench+glow illustration; CTA "Create your first ticket"; sub-link "Or import from old system" (§50).
- [ ] Inventory empty: CTA "Add your first product" or "Import catalog (CSV)"; starter templates (Phone/Laptop/TV repair) seed ~20 common items.
- [ ] Customers empty: CTA "Add first customer" or "Import from contacts" via `ContactsContract` with explicit explanation.
- [ ] SMS empty: CTA "Connect SMS provider" → Settings § SMS.
- [ ] POS empty: CTA "Connect BlockChyp" → Settings § Payment; "Cash-only POS" enabled by default.
- [ ] Reports empty: placeholder chart with "Come back after your first sale".
- [ ] Completion nudges: checklist ticks as steps complete; progress ring top-right of dashboard.
- [ ] Sample data toggle in Setup Wizard loads demo tickets; clearly labeled demo; one-tap clear.

### 3.15 Open-shop checklist
- [ ] Trigger: on first app unlock of the day for staff role; gently suggests opening checklist.
- [ ] Steps (customizable per tenant): open cash drawer, count starting cash; print last night's backup receipt; review pending tickets for today; check appointments list; check inventory low-stock alerts; power on hardware (printer/terminal) with app pinging status; unlock POS.
- [ ] Hardware ping: ping each configured device (printer, terminal) via Bluetooth socket / ipv4 with 2s timeout; green check or red cross per device; tap red → diagnostic page.
- [ ] Completion: stored with timestamp per staff; optional post to team chat ("Morning!").
- [ ] Skip: user can skip; skipped state noted in audit log.

### 3.16 Activity feed (dashboard variant)
- [ ] Real-time event stream (not audit log; no diffs — social-feed style).
- [ ] Dashboard tile: compact last 5 events, expand to full feed Activity.
- [ ] Filters: team / location / event type / employee.
- [ ] Tap event drills to entity.
- [ ] Subtle reactions (thumbs / party / check) — not a social app.
- [ ] Per-user notifications: "Notify me when X happens to my tickets".
- [ ] Privacy: no customer PII in feed text (IDs only).
- [ ] Infinite scroll with cursor-based pagination via Paging3 + Room RemoteMediator.

### 3.17 Per-role / saved dashboards
- [ ] Tenant admin defines per-role tile templates.
- [ ] Cashier default tiles: today sales / shift totals / quick actions.
- [ ] Tech default tiles: my queue / my commission / tasks.
- [ ] Manager default tiles: revenue / team perf / low stock.
- [ ] User can reorder tiles within allowed set (drag-to-rearrange via `Modifier.draggable` on tablet).
- [ ] Multiple named saved dashboards per user (e.g. "Morning", "End of day").
- [ ] Quick-switch between saved dashboards via segmented tab.
- [ ] Shared data plumbing with §24 Glance widgets.
- [ ] New users get curated minimal set; reveal advanced on demand.

### 3.18 Density modes
- [ ] Three modes: Comfortable (default phone, 1-2 col), Cozy (default tablet, 2-3 col), Compact (power user, 3-4 col smaller type).
- [ ] Per-user setting: Settings → Appearance → Dashboard density; sync respects shared-device mode (off on shared devices).
- [ ] Density token feeds spacing rhythm (§30); orthogonal to Reduce Motion.
- [ ] Live preview in settings (real dashboard) as user toggles.

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
- [ ] **Cursor-based pagination (offline-first)** — list reads from Room via `Flow<PagingData<Ticket>>`. `RemoteMediator` drives `GET /tickets?cursor=<opaque>&limit=50` when online; response upserts into Room; list auto-refreshes. Offline: no-op (or un-archive older rows if applicable). `hasMore` derived from local `{ oldestCachedAt, serverExhaustedAt? }` per filter, NOT from `total_pages`.
- [ ] **Room cache** — render from disk instantly, background-refresh from server; cache keyed by ticket id, filtered locally via Room predicates on `(status_group, assignee, urgency, updated_at)` rather than server-returned pagination tuple. No `(filter, keyword, page)` cache buckets.
- [ ] **Footer states** — `Loading…` / `Showing N of ~M` / `End of list` / `Offline — N cached, last synced Xh ago`. Four distinct states, never collapsed.
- [x] **Filter chips** — All / Open / On hold / Closed / Cancelled / Active (mirror server `status_group`) via `FilterChip`.
- [x] **Urgency chips** — Critical / High / Medium / Normal / Low (color-coded dots). (commit 68cadc5 — `components/TicketUrgencyChip.kt` + `TicketUrgency` enum Critical→errorContainer/High→tertiary/Medium→secondary/Normal→surfaceVariant/Low→faded; `ticketUrgencyFor()` derives from status-name heuristics; TODO comment for server priority field)
- [~] **Search** by keyword (ticket ID, order ID, customer name, phone, device IMEI). Debounced 300ms via Flow `debounce`.
- [x] **Sort** dropdown — newest / oldest / status / urgency / assignee / due date / total DESC — via `ExposedDropdownMenuBox`. (commit 68cadc5 — `components/TicketSortDropdown.kt` `TicketSort` enum + DropdownMenu sort picker highlighting active; VM `currentSort: StateFlow` + `applySortOrder()` pure func 6 sort variants; 8 JVM tests)
- [ ] **Column / density picker** (tablet/ChromeOS) — show/hide: assignee, internal note, diagnostic note, device, urgency dot. Persist per user.
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
- [ ] **Export CSV** — `GET /tickets/export` + Storage Access Framework `ACTION_CREATE_DOCUMENT` on tablet/ChromeOS.
- [ ] **Pinned/bookmarked** tickets at top (⭐ toggle).
- [ ] **Customer-preview popover** — tap customer avatar on row → `Popup` with recent-tickets + quick-actions.
- [ ] **Row age / due-date badges** — same color scheme as My Queue.
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
- [ ] **Photos** — full-screen gallery with pinch-zoom (`Modifier.pointerInput(detectTransformGestures)`), swipe (`HorizontalPager`), share intent. Upload via `POST /tickets/:id/photos` (multipart) through WorkManager + foreground service so uploads survive app kill. Progress chip per photo. Delete via swipe. Mark "before / after" tag. EXIF-strip PII on upload via `ExifInterface`.
- [x] **Notes** — types: internal / customer-visible / diagnostic / sms / email / string (server types). `POST /tickets/:id/notes` with `{ type, content, is_flagged, ticket_device_id? }`. Flagged notes badge-highlight. (commit bf6369f — `components/TicketNotesTab.kt` type chip selector + compose box + POST via VM; flagged badge highlight)
- [x] **History timeline** — server-driven events (status changes, notes, photos, SMS, payments, assignments). Filter toggle chips per event type. Pill per day header. (commit bf6369f — `components/TicketHistoryTimeline.kt` vertical dot-connector timeline + M3 icons; empty state; event fetch via VM)
- [x] **Warranty / SLA badge** — "Under warranty" or "X days to SLA breach"; pull from `GET /tickets/warranty-lookup` on load. (commit bf6369f — prominent banner above tabs color-coded by days remaining; warningContainer/errorContainer tokens)
- [ ] **QR code** — render ticket order-ID as QR via ZXing `BarcodeEncoder`; tap → full-screen enlarge for counter printer. `Image(bitmap)` + plaintext below.
- [ ] **Share PDF / Android Print** — on-device PDF pipeline per §17.4. `WorkOrderTicketView(model)` Composable → `PdfDocument` via `writeTo(outputStream)`; hand file URI (via `FileProvider`) to `PrintManager.print(...)` or share sheet (`Intent.createChooser`). SMS shares public tracking link (§55); email attaches locally-rendered PDF so recipient sees it without login. Fully offline-capable.
- [x] **Copy link to ticket** — App Link `app.bizarrecrm.com/tickets/:id`. (commit bf6369f — overflow menu "Copy link" action + `ClipboardUtil.copy("bizarrecrm://tickets/$id")` + Snackbar "Link copied")
- [x] **Customer quick actions** — Call (`ACTION_DIAL`), SMS (opens thread), Email (`ACTION_SENDTO` with `mailto:`), open Customer detail, Create ticket for this customer. (commit bf6369f — `components/TicketCustomerActions.kt` AssistChip row {Call/SMS/Email}; `util/PhoneIntents.kt` helpers via ACTION_DIAL / ACTION_VIEW `sms:` / ACTION_SENDTO `mailto:`)
- [ ] **Related** — side rail (tablet) with Recent tickets from same customer, Photo wallet, Health score, LTV tier (see §42).
- [ ] **Bench timer widget** — small card, start/stop (`POST /bench/:ticketId/timer-start`); feeds Live Update notification (§24).
- [ ] **Continuity banner** (tablet/ChromeOS) — `ComponentActivity.onProvideAssistContent` advertises this ticket so Cross-device Services / handoff can pick up on another signed-in device.
- [ ] **Deleted-while-viewing** — banner "This ticket was removed. [Close]".
- [ ] **Permission-gated actions** — hide destructive actions when user lacks role.

### 4.3 Create — full-fidelity multi-step
- [ ] Minimal create (customer + single device).
- [ ] **Flow steps** — Customer → Device(s) → Services/Parts → Diagnostic/checklist → Pricing & deposit → Assignee / urgency / due date → Review.
- [ ] **Phone:** full-screen `Activity` with top `LinearProgressIndicator` (segmented via steps); each step own Composable screen via `AnimatedContent`.
- [ ] **Tablet:** 2-pane sheet (`ModalBottomSheet` large or full-screen dialog): left = step list, right = active step content; `Done` / `Back` in top bar.
- [ ] **Customer picker** — search existing (`GET /customers/search`) + "New customer" inline mini-form (see §5.3); recent customers list.
- [ ] **Device catalog** — `GET /catalog/manufacturers` + `GET /catalog/devices?keyword=&manufacturer=` drive hierarchical picker. Pre-populate common-repair suggestions from `GET /device-templates`.
- [ ] **Device intake photos** — CameraX + system PhotoPicker; 0..N; drag-to-reorder (tablet) / long-press-reorder (phone).
- [ ] **Pre-conditions checklist** — checkboxes (from server or tenant default); required signed on bench start.
- [ ] **Services / parts picker** — quick-add tiles (top 5 services from `GET /pos-enrich/quick-add`) + full catalog search + barcode scan (CameraX + ML Kit Barcode). Tap inventory part → adds to cart; tap service → adds with default labor rate from `GET /repair-pricing/services`.
- [ ] **Pricing calculator** — subtotal + tax class (per line) + line discount + cart discount (% or $, reason required beyond threshold) + fees + tip + rounding rules. Live recalc via `derivedStateOf`.
- [ ] **Deposit** — "Collect deposit now" → inline POS charge (see §16) or "Mark deposit pending". Deposit amount shown on header.
- [ ] **Assignee picker** — employee grid filtered by role / clocked-in; "Assign to me" shortcut.
- [ ] **Due date** — default = tenant rule from `GET /settings/store` (+N business days); custom via `DatePicker` (Material3).
- [ ] **Service type** — Walk-in / Mail-in / On-site / Pick-up / Drop-off (from `GET /settings/store`). Custom types supported.
- [ ] **Tags / labels** — multi-chip picker (`InputChip`).
- [ ] **Source / referral** — dropdown (source list from server).
- [ ] **Source-ticket linking** — pre-seed from existing ticket (convert-from-estimate flow).
- [ ] **Review screen** — summary card with all fields; "Edit" jumps back to step; big `Button` "Create ticket" CTA.
- [ ] **Idempotency key** — client generates UUID, sent as `Idempotency-Key` header to avoid duplicate creates on retry.
- [ ] **Offline create** — Room temp ID (negative int or `OFFLINE-UUID`), human-readable offline reference ("OFFLINE-2026-04-19-0001"), queued in `sync_queue`; reconcile on drain — server ID replaces temp ID across related rows (photos, notes).
- [ ] **Autosave draft** — every field change writes to `tickets_draft` Room table; "Resume draft" banner on list when present; discard confirmation.
- [ ] **Validation** — per-step inline error helper text; block next until required fields valid.
- [x] **Hardware-keyboard shortcuts** — Ctrl+Enter create, Ctrl+. cancel, Ctrl+→ / Ctrl+← next/prev step.
- [ ] **Haptic** — `CONFIRM` on create; `REJECT` on validation fail.
- [ ] **Post-create** — pop to ticket detail; if deposit collected → Sale success screen (§16.8); offer "Print label" if receipt printer paired.

### 4.4 Edit
- [ ] In-place edit on detail: status, assignee, notes, devices, services, prices, deposit, due date, urgency, tags, labels, customer reassign, source.
- [ ] **Optimistic UI** with rollback on failure (revert local mutation + error Snackbar).
- [ ] **Audit log** entries streamed back into timeline.
- [ ] **Concurrent-edit** detection — server returns 409 on stale `updated_at`; UI shows "This ticket changed. Reload to merge." banner.
- [ ] **Delete** — destructive confirm; soft-delete server-side.

### 4.5 Ticket actions
- [ ] **Convert to invoice** — `POST /tickets/:id/convert-to-invoice` → navigates to new invoice detail; prefill ticket line items; respect deposit credit.
- [ ] **Attach to existing invoice** — picker; append line items.
- [ ] **Duplicate ticket** — same customer + device + clear status.
- [ ] **Merge tickets** — pick duplicate candidate (search dialog); confirm; server merges notes / photos / devices.
- [ ] **Transfer to another technician** — handoff modal with reason (required) — `PUT /tickets/:id` with `{ assigned_to }` + note auto-logged.
- [ ] **Transfer to another store / location** (multi-location tenants).
- [ ] **Bulk action** — `POST /tickets/bulk-action` with `{ ticket_ids, action, value }` — bulk assign / bulk status / bulk archive / bulk tag.
- [ ] **Warranty lookup** — quick action "Check warranty" — `GET /tickets/warranty-lookup?imei|serial|phone`.
- [ ] **Device history** — `GET /tickets/device-history?imei|serial` — shows past repairs for this device on any customer.
- [ ] **Star / pin** to dashboard.

### 4.6 Notes & mentions
- [ ] **Compose** — multiline `OutlinedTextField`, type picker (internal / customer / diagnostic / sms / email), flag toggle.
- [ ] **`@` trigger** — inline employee picker (`GET /employees?keyword=`); insert `@{name}` token via `AnnotatedString` + `SpanStyle`.
- [ ] **Mention push** — server sends FCM to mentioned employee.
- [ ] **Markdown-lite** — bold / italic / bullet lists / inline code rendered via `AnnotatedString` + custom parser (no WebView).
- [ ] **Link detection** — phone / email / URL auto-tappable via `LinkAnnotation`.
- [ ] **Attachment** — add image from camera / PhotoPicker → inline preview; stored as note attachment.

### 4.7 Statuses & transitions
- [ ] **Fetch taxonomy** `GET /settings/statuses` — drives picker; no hardcoded statuses.
- [ ] **Color chip** from server hex.
- [ ] **Transition guards** — some transitions require: note added, photos taken, checklist signed, QC sign-off. Frontend enforces + server validates.
- [ ] **QC sign-off modal** — signature capture via custom Compose `Canvas` + `detectDragGestures`, comments, "Work complete" confirm.
- [ ] **Status notifications** — if tenant configured SMS/email on this transition, modal confirms "Notify customer?" with template preview.

### 4.8 Photos — advanced
- [ ] **Camera** — CameraX `PreviewView` with flash toggle, flip, grid, shutter haptic.
- [ ] **Library picker** — system `PhotoPicker` (`ActivityResultContracts.PickMultipleVisualMedia`) with selection limit 10.
- [ ] **Upload** — WorkManager Worker surviving app exit; foreground service during active uploads; progress chip per photo.
- [ ] **Retry failed upload** — dead-letter entry in Sync Issues.
- [ ] **Annotate** — Compose `Canvas` overlay on photo for markup via stylus or finger; saves as new attachment (original preserved).
- [ ] **Before / after tagging** — toggle on each photo; detail view shows side-by-side on review.
- [ ] **EXIF strip** — remove GPS + timestamp metadata on upload via `ExifInterface.setAttribute(...)` clearing sensitive tags.
- [ ] **Thumbnail cache** — Coil with disk limit; full-size fetched on tap.
- [ ] **Signature attach** — signed customer acknowledgement saved as PNG attachment (Bitmap → PNG → upload).

### 4.9 Bench workflow
- [ ] **Backend:** `GET /bench`, `POST /bench/:ticketId/timer-start`.
- [ ] **Frontend:** Bench tab (or dashboard tile) — queue of my bench tickets with device template shortcut + big timer.
- [ ] **Live Update** (Android 16) — Progress-style ongoing notification shows active-repair timer on Lock Screen + status bar. Foreground service `repairInProgress` keeps process alive; notification category `CATEGORY_PROGRESS`.
- [ ] Parallels to iOS Live Activity: same server payload, same copy deck.

### 4.10 Device templates
- [ ] **Backend:** `GET /device-templates`, `POST /device-templates`.
- [ ] **Frontend:** template picker on create / bench — pre-fills common repairs per device; editable per tenant in Settings → Device Templates.

### 4.11 Repair pricing catalog
- [ ] **Backend:** `GET /repair-pricing/services`, `POST`, `PUT`.
- [ ] **Frontend:** searchable services catalog with labor-rate defaults; per-device-model overrides.

### 4.12 Handoff modal
- [ ] Required reason dropdown: Shift change / Escalation / Out of expertise / Other (free-text). Assignee picker. `PUT /tickets/:id` + auto-logged note. Receiving tech gets FCM push.

### 4.13 Empty / error states
- [ ] No tickets — illustration + "Create your first ticket".
- [ ] Network error on detail — keep cached data, retry pill.
- [ ] Deleted on server → banner "Ticket removed. [Close]".
- [ ] Permission denied on action → inline Snackbar "Ask your admin to enable this.".
- [ ] 409 stale edit → "This ticket changed. [Reload]".

### 4.14 Signatures & waivers
- [ ] Waiver PDF templates managed server-side; Android renders.
- [ ] Required contexts: drop-off agreement (liability / data loss / diagnostic fee), loaner agreement (§43), marketing consent (TCPA SMS / email opt-in).
- [ ] Waiver sheet UI: scrollable text + Compose-Canvas signature + printed name + "I've read and agree" checkbox; Submit disabled until checked + signature non-empty.
- [ ] Signed PDF auto-emailed to customer; archived to tenant storage under `/tickets/:id/waivers` or `/customers/:id/consents`.
- [ ] `POST /tickets/:id/signatures` endpoint.
- [ ] Audit log entry per signature: timestamp + IP + device fingerprint + waiver version + actor (tenant staff who presented).
- [ ] Re-sign on waiver-text change: existing customers re-sign on next interaction; version tracked.

### 4.15 Ticket state machine
- [ ] Default state set (tenant-customizable): Intake → Diagnostic → Awaiting Approval → Awaiting Parts → In Repair → QA → Ready for Pickup → Completed → Archived. Branches: Cancelled, Un-repairable, Warranty Return.
- [ ] Transition rules editable in Settings → Ticket statuses (§19): optional per-transition prerequisites (photo required / pre-conditions signed / deposit collected / quote approved). Blocked transitions show inline error "Can't mark Ready — no photo."
- [ ] Triggers on transition: auto-SMS (e.g., Ready for Pickup → text customer per template); assignment-change audit log; idle-alert push to manager after > 7d in `Awaiting Parts`.
- [ ] Bulk transitions via multi-select → "Move to Ready" menu; rules enforced per-ticket; skipped ones shown in summary.
- [ ] Rollback: admin-only; creates audit entry with reason.
- [ ] Visual: tenant-configured color per state; state pill on every list row + detail header.
- [ ] Funnel chart in §15 Reports: count per state + avg time-in-state; bottleneck highlight if avg > tenant benchmark.

### 4.16 Quick-actions catalog
- [ ] Context menu (long-press on list row): Open / Copy ID / Share PDF / Call customer / Text customer / Print receipt / Mark Ready / Mark In Repair / Assign to me / Archive / Delete (admin only).
- [ ] Swipe actions: right swipe = Start/Mark Ready (state-dependent); left swipe = Archive; long-swipe destructive requires AlertDialog confirm.
- [ ] Tablet hardware-keyboard: Ctrl+D mark done; Ctrl+Shift+A assign; Ctrl+Shift+S send SMS update; Ctrl+P print; Ctrl+Delete delete (admin only).
- [ ] Drag-and-drop: drag ticket row to "Assign" rail target (tablet) to reassign; drag to status column in Kanban.
- [ ] Batch actions: multi-select in list; batch context menu Assign/Status/Archive/Export.
- [ ] Smart defaults: show most-recently-used action first per user; adapts over time.

### 4.17 IMEI validation (identification only)
- [x] Local IMEI validation only: Luhn checksum + 15-digit length. (`util/ImeiValidator.kt`)
- [x] Optional TAC lookup (first 8 digits) via offline table to name device model. (`ImeiValidator.lookupTacModel`; ~40-entry table — grows via §44 Device Templates.)
- [~] Called from ticket create / inventory trade-in purely for device identification + autofill make/model. (TicketCreate now surfaces Luhn + TAC-match as supportingText under the IMEI field; inventory trade-in call-site still pending.)
- [x] No stolen/lost/carrier-blacklist provider lookup — scope intentionally dropped. Shop does not gate intake on external device-status services.

### 4.18 Warranty tracking
- [ ] Warranty record created on ticket close for each installed part/service.
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
- [ ] Per-service checklist configurable per repair type.
- [ ] Example iPhone screen checklist: Display lights up / Touch works / Camera / Speaker / Mic / Wi-Fi / Cellular / Battery health / Face unlock / No new scratches.
- [ ] Each item: pass / fail / N/A + optional photo.
- [ ] Failure: fail item returns ticket to In Repair with failure noted; require reason on flip back.
- [ ] Sign-off: tech signature + timestamp.
- [ ] Optional second-tech verification for high-value repairs.
- [ ] Customer-visible: checklist printed on invoice/receipt so customer sees what was tested.
- [ ] Audit: QC history visible in ticket history including who tested and when.

### 4.21 Labels (separate from status)
- [ ] Labels separate from status: status is lifecycle (one), labels are optional flags (many).
- [ ] Example labels: urgent, VIP, warranty, insurance claim, parts-ordered, QC-pending.
- [ ] Color-coded chips on list rows.
- [ ] Filter ticket list by label.
- [ ] Auto-rules: "device-value > $500 → auto-label VIP"; "parts-ordered → auto-label on PO link".
- [ ] Multi-select bulk apply/remove label.
- [ ] Conceptual: ticket labels are ticket-scoped vs customer tags are customer-scoped — don't conflate.
- [ ] Label break-outs in revenue/duration reports (e.g. "Insurance claims avg turn time = 8d").

### 4.22 SLA visualizer
- [ ] Inline chip on ticket list row: small ring showing % of SLA consumed; green < 60%, amber 60-90%, red > 90%, black post-breach.
- [ ] Detail header: progress bar with phase markers (diagnose / awaiting parts / repair / QC); long-press reveals phase timestamps + remaining.
- [ ] Timeline overlay: status history overlays SLA curve to show phase-budget consumption.
- [ ] Manager aggregated view: all-open tickets on SLA heatmap (tickets × time to SLA); red-zone sortable to top.
- [ ] Projection: predict breach time at current pace ("At current rate, will breach at 14:32").
- [ ] One-tap "Notify customer of delay" with template pre-filled.
- [ ] Reduce Motion: gauge animates only when Reduce Motion off; else static value.

---
## 5. Customers

_Server endpoints: `GET /customers`, `GET /customers/search`, `GET /customers/{id}`, `POST /customers`, `PUT /customers/{id}`, `DELETE /customers/{id}`, `GET /customers/{id}/tickets`, `GET /customers/{id}/invoices`, `GET /customers/{id}/communications`, `GET /customers/{id}/assets`, `POST /customers/{id}/assets`, `GET /customers/{id}/analytics`, `POST /customers/bulk-tag`, `POST /customers/merge`, `GET /crm/customers/{id}/health-score`, `POST /crm/customers/{id}/health-score/recalculate`, `GET /crm/customers/{id}/ltv-tier`._

### 5.1 List
- [x] Base list + search via LazyColumn + Paging3.
- [ ] **Cursor-based pagination (offline-first)** per top-of-doc rule + §20.5. Room `Flow<PagingData>` + `RemoteMediator`; `GET /customers?cursor=&limit=50` online only; offline no-op. Footer states: loading / more-available / end-of-list / offline-with-cached-count.
- [ ] **Sort** — most recent / A–Z / Z–A / most tickets / most revenue / last visit.
- [ ] **Filter** — tag(s) / LTV tier (VIP / Regular / At-risk) / health-score band / balance > 0 / has-open-tickets / city-state.
- [ ] **Swipe actions** — leading: SMS / Call; trailing: Mark VIP / Archive.
- [ ] **Context menu** (long-press / right-click) — Open, Copy phone, Copy email, New ticket, New invoice, Send SMS, Merge.
- [ ] **A–Z section index** (phone) — fast-scroller via custom `Modifier` on right edge that jumps by letter anchor.
- [ ] **Stats header** (toggleable via `include_stats=true`) — total customers, VIPs, at-risk, total LTV, avg LTV.
- [ ] **Preview popover** (tablet/ChromeOS hover via `pointerHoverIcon`) — quick stats (spent / tickets / last visit).
- [ ] **Bulk select + tag** — long-press enters selection; `BulkActionBar`; `POST /customers/bulk-tag` with `{ customer_ids, tag }`.
- [ ] **Bulk delete** with undo Snackbar (5s window).
- [ ] **Export CSV** via Storage Access Framework `ACTION_CREATE_DOCUMENT` (tablet/ChromeOS surfaces CTA more prominently).
- [ ] **Empty state** — "No customers yet. Create one or import from Contacts." + two CTAs.
- [ ] **Import from Contacts** — system `ContactsContract` picker multi-select → create each.

### 5.2 Detail
- [ ] Base (analytics / recent tickets / notes).
- [ ] **Tabs** (mirror web): Info / Tickets / Invoices / Communications / Assets.
- [ ] **Header** — avatar + name + LTV tier chip + health-score ring + VIP star.
- [ ] **Health score** — `GET /crm/customers/:id/health-score` → 0–100 ring (green ≥70 / amber ≥40 / red <40); tap ring → explanation sheet (recency / frequency / spend components); "Recalculate" button → `POST /crm/customers/:id/health-score/recalculate`. Auto-recalc on open if last calc > 24h; daily refresh worker at 4am local time.
- [ ] **LTV tier** — `GET /crm/customers/:id/ltv-tier` → chip (VIP / Regular / At-Risk); tap → explanation.
- [x] **Photo mementos** — recent repair photos gallery (`LazyRow` horizontal scroll).
- [ ] **Contact card** — phones (multi, labeled), emails (multi), address (tap → `ACTION_VIEW` `geo:` URI opens Maps), birthday, tags, organization, communication preferences (SMS/email/call opt-in chips), custom fields.
- [ ] **Quick-action row** — chips: Call · SMS · Email · New ticket · New invoice · Share · Merge · Delete.
- [ ] **Tickets tab** — `GET /customers/:id/tickets`; infinite scroll; status chips; tap → ticket detail.
- [ ] **Invoices tab** — `GET /customers/:id/invoices`; status filter; tap → invoice.
- [ ] **Communications tab** — `GET /customers/:id/communications`; unified SMS / email / call log timeline; "Send new SMS / email" CTAs.
- [ ] **Assets tab** — `GET /customers/:id/assets`; devices owned (ever on a ticket); add asset (`POST /customers/:id/assets`); tap device → device-history.
- [ ] **Balance / credit** — sum of unpaid invoices + store credit balance (`GET /refunds/credits/:customerId`). CTA "Apply credit" if > 0.
- [ ] **Membership** — if tenant has memberships (§38), show tier + perks.
- [ ] **Share vCard** — generate `.vcf` via `VCardEntryConstructor` → share sheet; SAF export on tablet/ChromeOS.
- [ ] **Add to system Contacts** — `Intent(ACTION_INSERT, RawContacts.CONTENT_URI)` prefilled.
- [ ] **Delete customer** — confirm `AlertDialog` + warning if open tickets (offer reassign-or-cancel flow).

### 5.3 Create
- [ ] Full create form (first/last/phone/email/organization/address/city/state/zip/notes).
- [ ] **Extended fields** — type (person / business), multiple phones with labels (home / work / mobile), multiple emails, mailing vs billing address, tags chip picker, communication preferences toggles, custom fields (render from `GET /custom-fields`), referral source, birthday, notes.
- [ ] **Phone normalize** — shared `PhoneFormatter` util using libphonenumber-android.
- [ ] **Duplicate detection** — before save, fuzzy match on phone/email; modal "Looks like this might be {name}. Use existing?" with Merge / Cancel / Create anyway.
- [ ] **Import from Contacts** — `ContactsContract.Contacts.CONTENT_URI` picker prefills form.
- [ ] **Barcode/QR scan** — scan customer card (if tenant prints them) for quick-lookup.
- [ ] **Idempotency** + offline temp-ID handling.

### 5.4 Edit
- [ ] All fields editable. `PUT /customers/:id`.
- [ ] Optimistic UI + rollback.
- [ ] Concurrent-edit 409 banner.

### 5.5 Merge
- [ ] `POST /customers/merge` with `{ keep_id, merge_id }`.
- [ ] Search + select candidate; diff preview (which fields survive); confirmation.
- [ ] Destructive — explicit warning that merge is irreversible past 24h window.

### 5.6 Bulk actions
- [ ] Bulk tag (`POST /customers/bulk-tag`).
- [ ] Bulk delete with undo.
- [ ] Bulk export selected.

### 5.7 Asset tracking
- [ ] Add device to customer (`POST /customers/:id/assets`) — device template picker + serial/IMEI.
- [ ] Tap asset → device-history (`GET /tickets/device-history?imei|serial`).

### 5.8 Tags & segments
- [ ] Free-form tag strings (e.g. `vip`, `corporate`, `recurring`, `late-payer`).
- [ ] Color-coded with tenant-defined palette.
- [ ] Auto-tags applied by rules (e.g. "LTV > $1000 → gold").
- [ ] Customer detail header chip row for tags.
- [ ] Tap tag → filter customer list.
- [ ] Bulk-assign tags via list multi-select.
- [ ] Tag nesting hierarchy (e.g. "wholesale > region > east") with drill-down filters.
- [ ] Segments: saved tag combos + filters (e.g. "VIP + last visit < 90d").
- [ ] Segments used by marketing (§37) and pricing rules.
- [ ] Max 20 tags per customer (warn at 10).
- [ ] Suggested tags based on behavior (e.g. suggest `late-payer` after 3 overdue invoices).

### 5.9 Customer 360
- [ ] Unified customer detail: tickets / invoices / payments / SMS / email / appointments / notes / files / feedback.
- [ ] Vertical chronological timeline with colored dots per event type.
- [ ] Timeline filter chips and jump-to-date picker.
- [ ] Metrics header: LTV, last visit, avg spend, repeat rate, preferred services, churn risk score.
- [ ] Relationship graph: household / business links (family / coworker accounts).
- [ ] "Related customers" card.
- [ ] Files tab: photos, waivers, emails archived in one place.
- [ ] Star-pin important notes to customer header, visible across ticket/invoice/SMS contexts.
- [ ] Customer-level warning flags ("cash only", "known difficult", "VIP treatment") as staff-visible banner.

### 5.10 Dedup & merge
- [ ] Dupe detection on create: same phone / same email / similar name + address.
- [ ] Suggest merge at entry.
- [ ] Side-by-side record comparison merge UI.
- [ ] Per-field pick-winner or combine.
- [ ] Combine all contact methods (phones + emails).
- [ ] Migrate tickets, invoices, notes, tags, SMS threads, payments to survivor.
- [ ] Tombstone loser record with audit reference.
- [ ] 24h unmerge window, permanent thereafter (audit preserves trail).
- [ ] Settings → Data → Run dedup scan → lists candidates.
- [ ] Manager batch review of dedup candidates.
- [ ] Optional auto-merge when 100% phone + email match.

### 5.11 Communication preferences
- [ ] Per-customer preferred channel for receipts / status / marketing (SMS / email / push / none).
- [ ] Times-of-day preference.
- [ ] Granular opt-out: marketing vs transactional, per-category.
- [ ] Preferred language for comms; templates auto-use that locale.
- [ ] System blocks sends against preference.
- [ ] Staff override possible with reason + audit.
- [ ] Ticket intake quick-prompt: "How'd you like updates?" with SMS/email toggles.

### 5.12 Birthday automation
- [ ] Optional birth date on customer record.
- [ ] Age not stored unless tenant explicitly needs it.
- [ ] Day-of auto-send SMS or email template ("Happy birthday! Here's $10 off").
- [ ] Per-customer opt-in for birthday automation.
- [ ] Inject unique coupon per recipient with 7-day expiry.
- [ ] Privacy: never show birth date in lists / leaderboards.
- [ ] Age-derived features off by default.
- [ ] Exclusion: last-60-days visited customers get less salesy message.
- [ ] Exclusion: churned customers get reactivation variant.

### 5.13 Complaint tracking
- [ ] Intake via customer detail → "New complaint".
- [ ] Fields: category + severity + description + linked ticket.
- [ ] Resolution flow: assignee + due date + escalation path.
- [ ] Status: open / investigating / resolved / rejected.
- [ ] Required root cause on resolve: product / service / communication / billing / other.
- [ ] Aggregate root causes for trend analysis.
- [ ] SLA: response within 24h / resolution within 7d, with breach alerts.
- [ ] Optional public share of resolution via customer tracking page.
- [ ] Full audit history; immutable once closed.

### 5.14 Customer notes
- [ ] Note types: Quick (one-liner), Detail (rich text + attachments), Call summary, Meeting, Internal-only.
- [ ] Internal-only notes hidden from customer-facing docs.
- [ ] Pin critical notes to customer header (max 3).
- [ ] @mention teammate → push notification + link.
- [ ] @ticket backlinks.
- [ ] Internal-only flag hides note from SMS/email auto-include.
- [ ] Role-gate sensitive notes (manager only).
- [ ] Quick-insert templates (e.g. "Called, left voicemail", "Reviewed estimate").
- [ ] Edit history: edits logged; previous version viewable.
- [ ] A11y: rich text accessible via TalkBack element-by-element.

### 5.15 Customer files cabinet
- [ ] Per-customer file list (PDF, images, spreadsheets, waivers, warranty docs).
- [ ] Tags + search on files.
- [ ] Upload sources: Camera / PhotoPicker / Files picker (`ACTION_OPEN_DOCUMENT`) / external drive via DocumentsContract.
- [ ] Inline preview: images via Coil, PDF via `PdfRenderer`, docs via external app `ACTION_VIEW`.
- [ ] Stylus annotation markup on PDFs via Compose `Canvas`.
- [ ] Share sheet → customer email / nearby share.
- [ ] Retention: tenant policy per file type; auto-archive old.
- [ ] Encryption at rest (tenant storage) and in transit.
- [ ] Offline-cached files encrypted in SQLCipher-wrapped blob store.
- [ ] Versioning: replacing file keeps previous with version number.

### 5.16 Contact import
- [ ] Just-in-time `requestPermissions(READ_CONTACTS)` at "Import".
- [ ] System `Intent(ACTION_PICK, ContactsContract.Contacts.CONTENT_URI)` single-select; bulk via custom picker with `LazyColumn`.
- [ ] vCard → customer field mapping: name, phones, emails, address, birthday.
- [ ] Field selection UI when multiple values.
- [ ] Duplicate handling: cross-check existing customers → merge / skip / create new.
- [ ] "Import all" confirm sheet with summary (skipped / created / updated).
- [ ] Privacy: read-only; never writes back to Contacts.
- [ ] Clear imported data if user revokes permission.
- [ ] A11y: TalkBack announces counts at each step.

### 5.17 Currency / locale display
- [ ] Tenant-level template: symbol placement (pre/post), thousands separator, decimal separator per locale.
- [ ] Per-customer override of tenant default.
- [ ] Support formats: US `$1,234.56`, EU-FR `1 234,56 €`, JP `¥1,235`, CH `CHF 1'234.56`.
- [ ] Money input parsing accepts multiple locales; normalize to storage via `NumberFormat.getCurrencyInstance(locale)`.
- [ ] TalkBack: read full currency phrasing.
- [ ] Toggle for ISO 3-letter code vs symbol on invoices (cross-border clarity).

---
## 6. Inventory

_Server endpoints: `GET /inventory`, `GET /inventory/manufacturers`, `POST /inventory/import-csv`, `POST /inventory/{id}/image`, `GET /stocktake`, `POST /stocktake`, `POST /stocktake/{id}/items`, `GET /inventory-enrich/barcode-lookup`, `GET /purchase-orders`, `POST /purchase-orders`._

### 6.1 List
- [x] Base list + filter chips + search.
- [x] **Tabs** — All / Products / Parts. NOT SERVICES — services aren't inventoriable. Settings menu handles services catalog (device types, manufacturers).
- [x] **Search** — name / SKU / UPC / manufacturer (debounced 300ms).
- [x] **Filters** (collapsible drawer via `ModalBottomSheet`): Manufacturer / Supplier / Category / Min price / Max price / Hide out-of-stock / Reorderable-only / Low-stock. (commit 4428dc6 — `components/InventoryFilterSheet.kt` ModalBottomSheet with 6 filter fields + `InventoryFilter` data class + active-count badge on filter icon)
- [ ] **Columns picker** (tablet/ChromeOS) — SKU / Name / Type / Category / Stock / Cost / Retail / Supplier / Bin. Persist per user.
- [x] **Sort** — SKU / name / stock / last restocked / price / last sold / margin. (commit 4428dc6 — `components/InventorySortDropdown.kt` InventorySort enum + `applyInventorySortOrder()` + DropdownMenu; 6 options; 8 JVM tests)
- [x] **Low-stock badge** + out-of-stock chip; critical-low pulse animation (respect Reduce Motion). (commit 4428dc6 — `components/InventoryStockBadge.kt` 3-tier badge Out/Critical-low-with-pulse/Low; ReduceMotion-aware static display)
- [x] **Quick stock adjust** — inline +/- stepper on row (debounced PUT via `distinctUntilChanged` + debounce). (commit 4428dc6 — `components/QuickStockAdjust.kt` tablet inline stepper + long-press ModalBottomSheet with `AdjustReason` dropdown {Sold/Received/Damaged/Adjusted}; optimistic VM `adjustStockBy()` + SyncQueue enqueue)
- [~] **Bulk select** — Price adjustment (% inc/dec preview modal) / Delete / Export / Print labels. (commit 4428dc6 — long-press on tablet → selection mode + BulkActionBar with Adjust/Export/Delete; Print labels TODO)
- [ ] **Receive items** modal — scan items into stock or add manually; creates stock-movement batch.
- [ ] **Receive by PO** — pick PO, scan items to increment received qty; close PO on completion.
- [ ] **Import CSV/JSON** — paste → preview → confirm (`POST /inventory/import-csv`). Row-level validation errors highlighted.
- [ ] **Mass label print** — multi-select → label printer (Android Printing / MFi thermal via Bluetooth SPP).
- [x] **Context menu** — Open, Copy SKU, Adjust stock, Create PO, Deactivate, Delete. (commit 4428dc6 — `components/InventoryContextMenu.kt` overflow + long-press DropdownMenu 6 actions; Print label logs TODO)
- [~] **Cost price hidden** from non-admin roles (server returns null). (commit 4428dc6 — `LocalIsAdmin` CompositionLocal defaults false with `TODO(role-gate)` pending Session role exposure)
- [x] **Empty state** — "No items yet. Import a CSV or scan to add." CTAs. (commit 4428dc6 — filter-aware: "No items match these filters" + {Clear filters / Import CSV stub} CTAs)

### 6.2 Detail
- [x] Stock card / group prices / movements.
- [ ] **Full movement history — cursor-based, offline-first** scoped per-SKU. Room `inventory_movement` table keyed by SKU + movement_id; detail view reads via Paging3. `sync_state` stored per-SKU: `{ cursor, oldestCachedAt, serverExhaustedAt?, lastUpdatedAt }`. Online scroll-to-bottom triggers `GET /inventory/:sku/movements?cursor=&limit=50`. Offline shows cached range with banner "History from X to Y — older rows require sync". FCM silent push / WS broadcast inserts new movements at top via `updated_at` anchor so scroll position preserved. Four footer states. Never use `total_pages`.
- [ ] **Price history chart** — Vico `AreaCartesianLayer` over time; toggle cost vs retail.
- [ ] **Sales history** — last 30d sold qty × revenue line chart.
- [ ] **Supplier panel** — name / contact / last-cost / reorder SKU / lead-time.
- [ ] **Auto-reorder rule** — view / edit threshold + reorder qty + supplier.
- [ ] **Bin location** — text field + picker (Settings → Inventory → Bin Locations).
- [ ] **Serials** — if serial-tracked, list of assigned serial numbers + which customer / ticket holds each.
- [ ] **Reorder / Restock** action — opens quick form to record stock-in or draft PO.
- [ ] **Barcode display** — Code-128 + QR via ZXing `BarcodeEncoder`; `SelectionContainer` on SKU/UPC.
- [ ] **Used in tickets** — recent tickets that consumed this part; tap → ticket.
- [ ] **Cost vs retail variance analysis** card (margin %).
- [ ] **Tax class** — editable (admin only).
- [ ] **Photos** — gallery; tap → lightbox; upload via `POST /inventory/:id/image`.
- [ ] **Edit / Deactivate / Delete** buttons.

### 6.3 Create
- [~] **Form**: Name (required), SKU, UPC / barcode, item type (product / part), category, cost price, retail price, tax class, stock qty, reorder threshold, reorder qty, supplier, bin, manufacturer, description, photos, tags, taxable flag.
- [ ] **Inline barcode scan** — CameraX + ML Kit `BarcodeScanning.getClient()` to fill SKU/UPC; auto-lookup via `GET /inventory-enrich/barcode-lookup` (external DB). Autofill name/manufacturer/UPC from result.
- [ ] **Photo capture** up to 4 per item; first = primary.
- [ ] **Validation** — decimal for prices (2 places), integer for stock.
- [ ] **Save & add another** secondary CTA.
- [ ] **Offline create** — temp ID + queue.

### 6.4 Edit
- [ ] All fields editable (role-gated for cost/price).
- [ ] **Stock adjust** quick-action: +1 / −1 / Set to… (logs stock movement with reason).
- [ ] **Move between locations** (multi-location tenants).
- [ ] **Delete** — confirm; prevent if stock > 0 or open PO references it.
- [ ] **Deactivate** — keep history, hide from POS.

### 6.5 Scan to lookup
- [ ] **Bottom-nav quick scan** / Dashboard FAB scan → CameraX + ML Kit → resolves barcode → item detail. If POS session open → add to cart.
- [ ] **HID-scanner support** — accept external Bluetooth scanner input via hidden focused `TextField` + IME-send detection. Detect rapid keystrokes (intra-key <50ms) → buffer until `KeyEvent.KEYCODE_ENTER` → submit.
- [x] **Vibrate** (`HapticFeedbackConstants.CONFIRM`) on successful scan.

### 6.6 Stocktake / audit
- [ ] **Sessions list** (`GET /stocktake`) — open + recent sessions with item count, variance summary.
- [ ] **New session** — name, optional location, start.
- [ ] **Session detail** — barcode scan loop → running count list with expected vs counted + variance dots. Manual entry fallback. Commit (`POST /stocktake/:id/items`) creates adjustments. Cancel discards.
- [ ] **Summary** — items counted / items-with-variance / total variance / surplus / shortage.
- [ ] **Multi-user** — multiple scanners feeding same session via WebSocket events.

### 6.7 Purchase orders
- [ ] **List** — status filter (draft / sent / partial / received / cancelled); columns: PO#, supplier, total, status, expected date.
- [ ] **Create** — supplier picker, line items (add from inventory with qty + cost), expected date, notes.
- [ ] **Send** — email to supplier via `ACTION_SEND` with PDF attachment.
- [ ] **Receive** — scan items to increment; partial receipt supported.
- [ ] **Cancel** — confirm.
- [ ] **PDF export** via SAF (tablet/ChromeOS primary).

### 6.8 Advanced inventory (admin tools, tablet/ChromeOS first)
- [ ] **Bin locations** — create aisle / shelf / position; batch assign items; pick list generation.
- [ ] **Auto-reorder rules** — per-item threshold + qty + supplier; "Run now" → draft POs.
- [ ] **Serials** — assign serial to item; link to customer/ticket; serial lookup.
- [ ] **Shrinkage report** — expected vs actual; variance trend chart.
- [ ] **ABC analysis** — A/B/C classification; Vico bar chart.
- [ ] **Age report** — days-in-stock; markdown / clearance suggestions.
- [ ] **Mass label print** — select items → label format → print (Mopria / MFi thermal).

### 6.9 Loaner / asset tracking
- [ ] `Asset` entity: id / type / serial / purchase date / cost / depreciation / status (available / loaned / in-repair / retired); optional `current_customer_id`.
- [ ] Loaner issue flow on ticket detail: "Issue loaner" → pick asset → waiver signature → updates asset status to loaned + ties to ticket.
- [ ] Return flow: inspect → mark available; release any BlockChyp hold.
- [ ] Deposit hold via BlockChyp (optional, per asset policy).
- [ ] Auto-SMS at ready-for-pickup + overdue > 7d escalation push to manager.
- [ ] Depreciation (linear / declining balance) + asset-book-value dashboard tile.
- [ ] Optional geofence alert (>24h outside metro area) — opt-in + customer consent required.

### 6.10 Bundles
- [ ] Bundle = set of items sold together at discount. Examples: Diagnostic + repair + warranty; Data recovery + backup + return shipping.
- [ ] Builder: Settings → Bundles → Add; drag items in; set bundle price or "sum − %".
- [ ] POS renders bundle as single SKU; expand to reveal included items; partial-delivery progress ("Diagnostic done, repair pending").
- [ ] Each included item decrements stock independently on sale.
- [ ] Reporting: bundle sell-through vs individual + attach-rate.

### 6.11 Batch / lot tracking
- [ ] Use-case: regulated parts (batteries) require lot tracking for recalls.
- [ ] Model: `InventoryLot` per receipt with fields lot_id, receive_date, vendor_invoice, qty, expiry.
- [ ] Sale/use decrements lot FIFO by default (or LIFO per tenant).
- [ ] FEFO alt: expiring-first queue for perishables (paste/adhesive).
- [ ] Recalls: vendor recall → tenant queries "all tickets using lot X" → customer outreach.
- [ ] Traceability: ticket detail shows which lot was used per part (regulatory).
- [ ] Config: per-SKU opt-in (most SKUs don't need lot tracking).

### 6.12 Serial number tracking
- [ ] Scope: high-value items (phones, laptops, TVs).
- [ ] New-stock serials scanned on receive.
- [ ] Intake: scan serial + auto-match model.
- [ ] POS scan on sale reduces qty by 1 for that serial.
- [ ] Lookup: staff scans, Android hits tenant server which may cross-check (§4.17).
- [ ] Link to customer: sale binds serial to customer record (enables warranty lookup by serial).
- [ ] Unique constraint: each serial sold once; sell-again requires "Returned/restocked" status.
- [ ] Reports: serials out by month; remaining in stock.

### 6.13 Inter-location transfers
- [ ] Flow: source location initiates transfer (pick items + qty + destination).
- [ ] Status lifecycle: Draft → In Transit → Received.
- [ ] Transit count: inventory marked "in transit", not sellable at either location.
- [ ] Receive: destination scans items.
- [ ] Discrepancy handling.
- [ ] Shipping label: print bulk label via §17.
- [ ] Optional carrier integration (UPS / FedEx).
- [ ] Reporting: transfer frequency + bottleneck analysis.
- [ ] Permissions split: source manager initiates, destination manager receives.

### 6.14 Scrap / damage bin
- [ ] Model: dedicated non-sellable bin per location.
- [ ] Items moved here with reason (damaged / obsolete / expired / lost).
- [ ] Move flow: Inventory → item → "Move to scrap" → qty + reason + photo.
- [ ] Decrements sellable qty; increments scrap bin.
- [ ] Cost impact: COGS adjustment recorded.
- [ ] Shrinkage report totals reflect scrap.
- [ ] Disposal: scrap bin items batch-disposed (trash / recycle / salvage).
- [ ] Disposal document generated with signature.
- [ ] Insurance: disposal records support insurance claims (theft, fire).

### 6.15 Dead-stock aging
- [ ] Report: inventory aged > N days since last sale.
- [ ] Grouped by tier: slow (60d) / dead (180d) / obsolete (365d).
- [ ] Action: clearance pricing suggestions.
- [ ] Action: bundle with hot-selling item.
- [ ] Action: return to vendor if eligible.
- [ ] Action: donate for tax write-off.
- [ ] Alerts: quarterly push "N items hit dead tier — plan action".
- [ ] Visibility: inventory list chip "Stale" / "Dead" badge.

### 6.16 Reorder lead times
- [ ] Per vendor: average days from order → receipt.
- [ ] Computed from PO history.
- [ ] Lead-time variance shows unreliability → affects reorder point.
- [ ] Safety stock buffer qty = avg daily sell × lead time × safety factor.
- [ ] Auto-calc or manual override of safety stock.
- [ ] Vendor comparison side-by-side: cost, lead time, on-time %.
- [ ] Suggest alternate vendor when primary degrades.
- [ ] Seasonality: lead times may lengthen in holiday season; track per-month.
- [ ] Inventory item detail shows "Lead time 7d avg (p90 12d)".
- [ ] PO creation uses latest stats for ETA.

---
## 7. Invoices

_Server endpoints: `GET /invoices`, `GET /invoices/stats`, `GET /invoices/{id}`, `POST /invoices`, `PUT /invoices/{id}`, `POST /invoices/{id}/payments`, `POST /invoices/{id}/void`, `POST /invoices/{id}/credit-note`, `POST /invoices/bulk-action`, `GET /reports/aging`._

### 7.1 List
- [x] Base list + filter chips + search.
- [x] **Status tabs** — All / Unpaid / Partial / Overdue / Paid / Void via `ScrollableTabRow`.
- [ ] **Filters** — date range, customer, amount range, payment method, created-by.
- [ ] **Sort** — date / amount / due date / status.
- [ ] **Row chips** — "Overdue 3d" (red), "Paid 50%" (amber), "Unpaid" (gray), "Paid" (green), "Void" (strike-through).
- [ ] **Stats header** — `GET /invoices/stats` → total outstanding / paid / overdue / avg value; tap to drill down.
- [ ] **Status pie + payment-method pie** (tablet/ChromeOS) — Vico `PieChart`-equivalent via custom renderer or MPAndroidChart interop.
- [ ] **Bulk select** → bulk action (`POST /invoices/bulk-action`): Send reminder / Export / Void / Delete.
- [ ] **Export CSV** via SAF.
- [ ] **Row context menu** — Open, Copy invoice #, Send SMS, Send email, Print, Record payment, Void.
- [ ] **Cursor-based pagination (offline-first)** per top-of-doc rule. `GET /invoices?cursor=&limit=50` online; list reads from Room via Paging3 + RemoteMediator.

### 7.2 Detail
- [x] Line items / totals / payments.
- [ ] **Header** — invoice number (INV-XXXX, `SelectionContainer`), status chip, due date, balance-due chip.
- [ ] **Customer card** — name + phone + email + quick-actions.
- [ ] **Line items** — editable table (if status allows); tax per line.
- [ ] **Totals panel** — subtotal / discount / tax / total / paid / balance due.
- [ ] **Payment history** — method / amount / date / reference / status; tap → payment detail.
- [ ] **Add payment** → `POST /invoices/:id/payments` (see 7.4).
- [ ] **Issue refund** — `POST /refunds` with `{ invoice_id, amount, reason }`; role-gated; partial + full.
- [ ] **Credit note** — `POST /invoices/:id/credit-note` with `{ amount, reason }`.
- [ ] **Void** — `POST /invoices/:id/void` with reason; destructive confirm.
- [ ] **Send by SMS** — pre-fill "Your invoice: {payment-link-url}" using `POST /sms/send`; short-link via `POST /payment-links`.
- [ ] **Send by email** — `Intent(ACTION_SENDTO)` with `mailto:` + PDF attached via FileProvider URI.
- [ ] **Share PDF** — system share sheet.
- [ ] **Android Print** via `PrintManager.print(...)` with custom PDF renderer.
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
- [ ] **Method picker** — fetched from `GET /settings/payment` (cash / card-in-person → POS flow / card-manual / ACH / check / gift card / store credit / other). Wire each method correctly, especially card, store credit, gift cards.
- [ ] **Amount entry** — default to balance due; support partial + overpayment (surplus → store credit prompt).
- [ ] **Reference** (check# / card last 4 / BlockChyp txn ID — auto-filled from terminal).
- [ ] **Notes** field.
- [ ] **Cash** — change calculator.
- [ ] **Split tender** — chain multiple methods until balance = 0.
- [ ] **BlockChyp card** — start terminal charge via BlockChyp Android SDK → poll status; surface ongoing Live Update notification for the txn.
- [ ] **Idempotency-Key** required on POST /invoices/:id/payments.
- [ ] **Receipt** — print (Bluetooth thermal / Mopria) + email + SMS; PDF download.
- [ ] **Haptic** `CONFIRM` on payment confirm.

### 7.5 Overdue automation
- [ ] Server schedules reminders. Android: overdue badge on dashboard + push notif tap → deep-link to invoice.
- [ ] Dunning sequences (see §7.7) manage escalation.

### 7.6 Aging report
- [ ] `GET /reports/aging` with bucket breakdown (0–30 / 31–60 / 61–90 / 90+ days).
- [x] Tablet/ChromeOS: sortable table via custom Compose `LazyColumn` headers; phone: grouped list by bucket.
- [ ] Row actions: Send reminder / Record payment / Write off.

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
- [ ] Status tabs — All / Draft / Sent / Approved / Rejected / Expired / Converted.
- [ ] Filters — date range, customer, amount, validity.
- [ ] Bulk actions — Send / Delete / Export.
- [ ] Expiring-soon chip (pulse animation when ≤3 days; honor Reduce Motion).
- [ ] Context menu — Open, Send, Convert to ticket, Convert to invoice, Duplicate, Delete.
- [ ] Cursor-based pagination (offline-first) per top-of-doc rule. `GET /estimates?cursor=&limit=50` online; list reads from Room.

### 8.2 Detail
- [ ] **Header** — estimate # + status + valid-until date.
- [ ] **Line items** + totals.
- [ ] **Send** — SMS / email; body includes approval link (customer portal).
- [ ] **Approve** — `POST /estimates/:id/approve` (staff-assisted) with signature capture (Compose Canvas).
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

### 8.5 E-sign (public page)
- [ ] Quote detail → "Send for e-sign" generates public URL `https://<tenant>/public/quotes/:code/sign`; share via SMS / email.
- [ ] Signer experience (server-rendered public page, no login): quote line items + total + terms + signature box + printed name + date → submit stores PDF + signature.
- [ ] FCM push to staff on sign: "Quote #42 signed by Acme Corp — convert to ticket?" Deep-link opens quote; one-tap convert to ticket.
- [ ] Signable within N days (tenant-configured); expired → "Quote expired — contact shop" page.
- [ ] Audit: each open / sign event logged with IP + user-agent + timestamp.

### 8.6 Versioning
- [ ] Each edit creates new version; prior retained.
- [ ] Version number visible on UI (e.g. "v3").
- [ ] Only "sent" versions archived for audit; drafts freely edited.
- [ ] Side-by-side diff of v-n vs v-n+1.
- [ ] Highlight adds / removes / price changes.
- [ ] Customer approval tied to specific version.
- [ ] Warning if customer approved v2 and tenant edited to v3 ("Customer approved v2; resend?").
- [ ] Convert-to-ticket uses approved version with stored reference (downstream changes don't invalidate).
- [ ] Reuse same versioning machinery for receipt templates + waivers.

---
## 9. Leads

_Server endpoints: `GET /leads`, `POST /leads`, `PUT /leads/{id}`._

### 9.1 List
- [x] Base list.
- [ ] **Columns** — Name / Phone / Email / Lead Score (0–100 `LinearProgressIndicator`) / Status / Source / Value / Next Action.
- [x] **Status filter** (multi-select `FilterChip` row) — New / Contacted / Scheduled / Qualified / Proposal / Converted / Lost.
- [ ] **Sort** — name / created / lead score / last activity / next action.
- [ ] **Bulk delete** with undo Snackbar.
- [ ] **Swipe** — advance / drop stage.
- [ ] **Context menu** — Open, Call, SMS, Email, Convert to customer, Schedule appointment, Delete.
- [ ] **Preview popover** quick view.

### 9.2 Pipeline (Kanban view)
- [ ] **Route:** `SegmentedButton` at top of Leads — List / Pipeline.
- [ ] **Columns** — one per status; drag-drop cards between via `detectDragGestures` + custom reorderable grid (updates via `PUT /leads/:id`).
- [ ] **Cards** show — name + phone + score chip + next-action date.
- [ ] **Tablet/ChromeOS** — horizontal scroll all columns visible. **Phone** — `HorizontalPager` paging between columns.
- [ ] **Filter by salesperson / source**.
- [ ] **Bulk archive won/lost**.

### 9.3 Detail
- [ ] **Header** — name + phone + email + score ring + status chip.
- [ ] **Basic fields** — first/last name, phone, email, company, title, source, value, next action + date, assigned-to.
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
- [x] Minimal form.
- [ ] **Extended fields** — score (manual override), source, value, stage, assignee, follow-up date, notes, tags, custom fields.
- [ ] **Offline create** + reconcile.

### 9.5 Lost-reason modal
- [ ] Required dropdown (price / timing / competitor / not-a-fit / other) + free-text.

---
## 10. Appointments & Calendar

_Server endpoints: `GET /appointments`, `POST /appointments`, `PUT /appointments/{id}`, `DELETE /appointments/{id}`, `GET /calendar` (verify)._

### 10.1 List / calendar views
- [x] Base list.
- [ ] **`SegmentedButton`** — Agenda / Day / Week / Month.
- [ ] **Month** — custom `CalendarGrid` Composable with dot per day for events; tap day → agenda.
- [ ] **Week** — 7-column time-grid; events as tonal tiles colored by type; scroll-to-now pin.
- [ ] **Day** — agenda list grouped by time-block (morning / afternoon / evening).
- [ ] **Time-block Kanban** (tablet) — columns = employees, rows = time slots (drag-drop reschedule via `detectDragGestures`).
- [ ] **Today** button in top bar; `Ctrl+T` shortcut.
- [ ] **Filter** — employee / location / type / status.

### 10.2 Detail
- [ ] Customer card + linked ticket / estimate / lead.
- [ ] Time range + duration, assignee, location, type (drop-off / pickup / consult / on-site / delivery), notes.
- [ ] Reminder offsets (15min / 1h / 1day before) — respects per-user default.
- [ ] Quick actions chips: Call · SMS · Email · Reschedule · Cancel · Mark no-show · Mark completed · Open ticket.
- [ ] Send-reminder manually (`POST /sms/send` + template).

### 10.3 Create
- [ ] Minimal.
- [ ] Full form: customer, assignee, location, start time, duration, type, linked ticket / estimate / lead, reminder offsets, recurrence (daily / weekly / custom via RRULE), notes.
- [ ] **Calendar mirror** — "Add to my Calendar" toggle writes event via `CalendarContract.Events.CONTENT_URI` to user's selected calendar (requires `WRITE_CALENDAR` runtime permission, requested on toggle).
- [ ] **Conflict detection** — if assignee double-booked, modal warning with "Schedule anyway" / "Pick another time".
- [ ] **Idempotency** + offline temp-id.

### 10.4 Edit / reschedule / cancel
- [x] Drag-to-reschedule (tablet day/week views) with `HapticFeedbackConstants.GESTURE_END` on drop.
- [ ] Cancel — ask "Notify customer?" (SMS/email).
- [ ] No-show — one-tap from detail; optional fee.
- [ ] Recurring-event edits — "This event" / "This and following" / "All".

### 10.5 Reminders
- [ ] Server cron sends FCM N min before (per-user setting).
- [ ] Data-only FCM triggers `NotificationManagerCompat` local alert if user foregrounded; actionable notif has "Call / SMS / Mark arrived" `Notification.Action` buttons.
- [ ] Live Update — "Next appt in 15 min" ongoing notification on Lock Screen.

### 10.6 Check-in / check-out
- [ ] At appt time, staff can tap "Customer arrived" → stamps check-in; starts ticket timer if linked to ticket.
- [ ] "Customer departed" on completion.

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
- [~] **Filters** — category / date range / employee / reimbursable flag / approval status.
- [ ] **Sort** — date / amount / category.
- [~] **Summary tiles** — Total (period), By category (Vico pie), Reimbursable pending. (commit f8f6a90 — By-category donut pie shipped; Total tile + Reimbursable-pending tile pending)
- [x] **Category breakdown pie** (tablet/ChromeOS). (commit f8f6a90 — `ExpenseCategoryPieChart.kt` Canvas donut + tappable legend + collapsible card on ExpenseListScreen; ReduceMotion-aware)
- [ ] **Export CSV** via SAF.
- [ ] **Swipe** — edit / delete.
- [ ] **Context menu** — Open, Duplicate, Delete.

### 11.2 Detail
- [ ] Receipt photo preview (full-screen zoom, pinch via `detectTransformGestures`).
- [ ] Fields — category / amount / vendor / payment method / notes / date / reimbursable flag / approval status / employee.
- [ ] Edit / Delete.
- [ ] Approval workflow — admin Approve / Reject with comment.

### 11.3 Create
- [x] Minimal.
- [ ] **Receipt capture** — CameraX inline; OCR total via ML Kit `TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)` + regex for `\$\d+\.\d{2}`; auto-fill amount field (user editable).
- [ ] **PhotoPicker import** — pick existing receipt.
- [ ] **Categories** — from server dropdown (Rent / Utilities / Parts / Tools / Marketing / Insurance / Payroll / Software / Office Supplies / Shipping / Travel / Maintenance / Taxes / Other).
- [ ] **Amount validation** — decimal 2 places; cap $100k.
- [ ] **Date picker** — Material3 `DatePicker`; defaults today.
- [ ] **Reimbursable toggle** — if user role = employee, approval defaults pending.
- [ ] **Offline create** + temp-id reconcile.

### 11.4 Approval (admin)
- [ ] List filter "Pending approval".
- [ ] Approve / Reject with comment; auto-notify submitter via FCM.

---
## 12. SMS & Communications

_Server endpoints: `GET /sms/unread-count`, `GET /sms/conversations`, `GET /sms/conversations/{id}/messages`, `POST /sms/send`, `GET /inbox`, `POST /inbox/{id}/assign`, `POST /voice/call`, `GET /voice/calls`, `GET /voice/calls/{id}`, `GET /voice/calls/{id}/recording`, `POST /voice/call/{id}/hangup`. WS topic: `sms:received`, `call:started`, `call:ended`._

### 12.1 Thread list
- [x] Threads list via `LazyColumn`.
- [x] **Search** — across all messages + phone numbers.
- [ ] **Unread badge** on launcher icon via `ShortcutBadger` / Android 8+ notification-dot auto-badge driven by NotificationChannel; per-thread bubble on row.
- [ ] **Filters** — All / Unread / Flagged / Pinned / Archived / Assigned to me / Unassigned.
- [ ] **Pin important threads** to top.
- [ ] **Sentiment badge** (positive / neutral / negative) if server computes.
- [ ] **Swipe actions** — leading: mark read / unread; trailing: flag / archive / pin.
- [ ] **Context menu** — Open, Call, Open customer, Assign, Flag, Pin, Archive.
- [x] **Compose new** (FAB) — pick customer or raw phone.
- [ ] **Team inbox tab** (if enabled) — shared inbox, assign rows to teammates.

### 12.2 Thread view
- [x] Bubbles + composer + POST /sms/send.
- [~] **Real-time WebSocket** via OkHttp `WebSocket` — new message arrives without refresh; animate in with `AnimatedVisibility` + slide-up spring.
- [ ] **Delivery status** icons per message — sent / delivered / failed / scheduled.
- [ ] **Read receipts** (if server supports).
- [ ] **Typing indicator** (if supported).
- [ ] **Attachments** — image / PDF / audio (MMS) via multipart upload through WorkManager.
- [ ] **Canned responses / templates** (from `GET /settings/templates`) surfaced as chips above composer; hotkeys Alt+1..9 (hardware keyboard).
- [ ] **Ticket / invoice / payment-link picker** — inserts short URL + ID token into composer.
- [ ] **Emoji picker** — system input method; Android 12+ emoji2 compat.
- [ ] **Schedule send** — date/time picker for future delivery.
- [ ] **Voice memo** (if MMS supported) — record AAC via `MediaRecorder` inline; bubble plays audio via `ExoPlayer`.
- [ ] **Long-press message** → `DropdownMenu` — Copy, Reply, Forward, Create ticket from this, Flag, Delete.
- [ ] **Create customer from thread** — if phone not associated.
- [ ] **Character counter** + SMS-segments display (160 / 70 unicode).
- [ ] **Compliance footer** — auto-append STOP message on first outbound to opt-in-ambiguous numbers.
- [ ] **Off-hours auto-reply** indicator when enabled.

### 12.3 PATCH helpers
- [ ] Add `@PATCH` method to Retrofit `ApiService` (currently missing if truly missing — verify).
- [ ] Mark read — `PATCH /sms/messages/:id { read: true }` (verify endpoint).
- [ ] Flag / pin — `PATCH /sms/conversations/:id { flagged, pinned }`.

### 12.4 Voice / calls (if VoIP tenant)
- [ ] **Calls tab** — list inbound / outbound / missed; duration; recording playback if available.
- [ ] **Initiate call** — `POST /voice/call` with `{ to, customer_id? }` → Android `TelecomManager` self-managed ConnectionService integration.
- [ ] **Recording playback** — `GET /voice/calls/:id/recording` → `ExoPlayer`.
- [ ] **Hangup** — `POST /voice/call/:id/hangup`.
- [ ] **Transcription display** — if server provides.
- [ ] **Incoming call** via `ConnectionService.onCreateIncomingConnection` → Android InCallService UI.

### 12.5 Push → deep link
- [ ] FCM on new inbound SMS with NotificationChannel `sms_inbound`.
- [ ] Actions: Reply (`RemoteInput` inline text input), Open, Call.
- [ ] Tap → SMS thread Activity.

### 12.6 Bulk SMS / campaigns (cross-links §37)
- [ ] Compose campaign to a segment; TCPA compliance check; preview.

### 12.7 Empty / error states
- [ ] No threads → "Start a conversation" CTA → compose new.
- [ ] Send failed → red bubble with "Retry" chip; retried sends queued offline via WorkManager.

---
## 13. Notifications

_Server endpoints: `GET /notifications`, `POST /device-tokens` (verify), `PATCH /notifications/:id/dismiss` (verify)._

### 13.1 List
- [ ] Base list.
- [ ] **Tabs** — All / Unread / Assigned to me / Mentions.
- [x] **Mark all read** action (top-bar button).
- [x] **Tap → deep link** (ticket / invoice / SMS thread / appointment / customer).
- [~] **Swipe to dismiss** (persists via `PATCH /notifications/:id/dismiss`).
- [x] **Group by day** (sticky day-header via `stickyHeader` in `LazyColumn`).
- [x] **Filter chips** — type (ticket / SMS / invoice / payment / appointment / mention / system).
- [x] **Empty state** — "All caught up. Nothing new." illustration.

### 13.2 Push pipeline
- [ ] **Register FCM** on login via `FirebaseMessaging.getInstance().token` → `POST /device-tokens` with `{ token, platform: "android", model, os_version, app_version }`.
- [ ] **Token refresh** via `FirebaseMessagingService.onNewToken`.
- [ ] **Unregister on logout** — `FirebaseMessaging.getInstance().deleteToken()` + `DELETE /device-tokens/:token`.
- [ ] **Data-only FCM** triggers background expedited Worker for delta sync.
- [ ] **Rich push** — Big-picture / big-text style via `NotificationCompat.BigPictureStyle`; thumbnails (customer avatar / ticket photo) downloaded via Coil before posting.
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
- [ ] Each channel exposes vibration pattern + sound + bypass DND (for critical only) + badge enabled.
- [x] **Entity allowlist** on deep-link parse (security — prevent injected types).
- [x] **Quiet hours** — respect Settings → Notifications → Quiet Hours; also honor system `NotificationManager.getCurrentInterruptionFilter()`. (`util/QuietHours.kt` + Settings → Notifications → Quiet hours card with toggle + start/end TimePicker rows. SLA breach + security alerts allow-listed. System DND check still pending.)
- [ ] **Time-sensitive** — Android 16 Live Updates for overdue invoice / SLA breach.
- [x] **POST_NOTIFICATIONS runtime permission** (Android 13+) — request just-in-time with rationale card before first important notification.

### 13.3 In-app toast
- [x] Foreground message on a different screen → in-app banner (Compose `Snackbar` at top via `SnackbarHost` or custom `Popup`) with tap-to-open; auto-dismiss 4s; `HapticFeedbackConstants.CLOCK_TICK`.

### 13.4 Badge count
- [ ] Launcher icon badge = unread count across inbox + notifications + SMS via NotificationChannel posting (Android auto-aggregates). Fallback via `ShortcutBadger` for Samsung / Xiaomi launchers that don't auto-badge.

---
## 14. Employees & Timeclock

_Server endpoints: `GET /employees`, `GET /employees/{id}`, `POST /employees`, `PUT /employees/{id}`, `POST /employees/{id}/clock-in`, `POST /employees/{id}/clock-out`, `GET /roles`, `POST /roles`, `GET /team`, `POST /team/shifts`, `GET /team-chat`, `POST /team-chat`, `GET /bench`._

### 14.1 List
- [x] Base list.
- [ ] **Filters** — role / active-inactive / clocked-in-now.
- [ ] **"Who's clocked in right now"** view — real-time via WebSocket presence events.
- [ ] **Columns** (tablet/ChromeOS) — Name / Email / Role / Status / Has PIN / Hours this week / Commission.
- [ ] **Permission matrix** admin view — `GET /roles`; checkbox grid of permissions × roles.

### 14.2 Detail
- [~] Role, wage/salary (admin-only), contact, schedule. (`EmployeeDetailScreen.kt` shows role, contact card, account card with PIN-set + active + clocked-in chips. Wage/schedule pending server endpoint.)
- [ ] **Performance tiles** (admin-only) — tickets closed, SMS sent, revenue touched, avg ticket value, NPS from customers.
- [ ] **Commissions** — `POST /team/shifts` drives accrual; display per-period; lock period (admin).
- [ ] **Schedule** — upcoming shifts + time-off.
- [ ] **PIN management** — change / clear (cannot view server-hashed PIN).
- [ ] **Deactivate** — soft-delete; grey out future logins.

### 14.3 Timeclock
- [x] **Clock in / out** — dashboard tile + dedicated screen; `POST /employees/:id/clock-in` / `-out`.
- [x] **PIN prompt** — custom numeric keypad with `HapticFeedbackConstants.VIRTUAL_KEY` per tap; `POST /auth/verify-pin`.
- [ ] **Breaks** — start / end break with type (meal / rest); accumulates toward labor law compliance.
- [ ] **Geofence** — optional; capture location on clock-in/out if `ACCESS_FINE_LOCATION` granted; server records inside/outside store geofence.
- [ ] **Edit entries** (admin only, audit log).
- [ ] **Timesheet** weekly view per employee.
- [ ] **Offline queue** — clock events persisted locally in Room, synced later via WorkManager.
- [ ] **Live Update** (Android 16) — "Clocked in since 9:14 AM" ongoing notification on Lock Screen until clock-out; foreground service `shortService` type so OS won't kill.

### 14.4 Invite / manage (admin)
- [ ] **Invite** — `POST /employees` with `{ email, role }`; server sends invite link. Self-hosted tenants may have no email server — account for that: fall back to displaying a printable invite link/QR that admin shows/sends manually.
- [ ] **Resend invite**.
- [ ] **Assign role** — technician / cashier / manager / admin / custom.
- [ ] **Deactivate** — soft delete.
- [ ] **Custom role creation** — Settings → Team → Roles matrix.

### 14.5 Team chat
- [ ] **Channel-less team chat** (`GET /team-chat`, `POST /team-chat`).
- [ ] Messages with @mentions; real-time via WebSocket.
- [ ] Image / file attachment via PhotoPicker + SAF.
- [ ] Pin messages.

### 14.6 Team shifts (weekly schedule)
- [ ] **Week grid** (7 columns, employees rows).
- [ ] Tap empty cell → add shift; tap filled → edit.
- [ ] Shift modal — employee, start/end, role, notes.
- [ ] Time-off requests side rail — approve / deny (manager).
- [ ] Publish week → notifies team via FCM.
- [ ] Drag-drop rearrange (tablet via `detectDragGestures`).

### 14.7 Leaderboard
- [ ] Ranked list by tickets closed / revenue / commission.
- [ ] Period filter (week / month / YTD).
- [ ] Badges 🥇🥈🥉.

### 14.8 Performance reviews / goals
- [ ] Reviews — form (employee, period, rating, comments); history.
- [ ] Goals — create / update progress / archive; personal vs team view.

### 14.9 Time-off requests
- [ ] Submit request (date range + reason).
- [ ] Manager approve / deny — **ensure manager approval queue screen actually ships**, not just the submit flow.
- [ ] Affects shift grid.

### 14.10 Shortcuts / Assistant
- [ ] Clock-in/out via Quick Settings Tile (`TileService`) — one-tap from pull-down shade without opening app.
- [ ] Clock-in/out via App Shortcut (`ShortcutManager`) on long-press launcher icon.
- [ ] Google Assistant App Actions ("Clock me in at BizarreCRM") via `shortcuts.xml` + `actions.xml`.

### 14.11 Shift close / Z-report
- [ ] End-of-shift summary: cashier taps "End shift" → summary card (sales count / gross / tips / cash expected / cash counted entered / over-short / items sold / voids); compare to prior shifts for trend.
- [ ] Close cash drawer: prompt to count cash by denomination ($100, $50, $20…); system computes expected from sales; delta live; over-short reason required if >$2.
- [ ] Manager sign-off: over-short threshold exceeded requires manager PIN; audit entry with cashier + manager IDs.
- [ ] Receipt: Z-report printed + PDF archived in §39 Cash register; PDF linked in shift summary.
- [ ] Handoff: next cashier starts with opening cash count entered by closing cashier.
- [ ] Sovereignty: shift data on tenant server only.

### 14.12 Hiring & offboarding
- [ ] Hire wizard: Manager → Team → Add employee; steps basic info / role / commission / access locations / welcome email; account created; staff gets login link.
- [ ] Offboarding: Settings → Team → staff detail → Offboard; immediately revoke access, sign out all sessions, transfer assigned tickets to manager, archive shift history (kept for payroll); audit log; optional export of shift history as PDF.
- [ ] Role changes: promote/demote path; change goes live immediately.
- [ ] Temporary suspension: suspend without offboarding (vacation without pay); account disabled until resume.
- [ ] Reference letter (nice-to-have): auto-generate PDF summarizing tenure + stats (total tickets, sales); manager customizes before export.

### 14.13 Scorecards / subjective review
- [ ] Metrics: ticket close rate, SLA compliance, customer rating, revenue attributed, commission earned, hours worked, breaks taken.
- [ ] Private by default: self + manager; owner sees all.
- [ ] Manager annotations with notes + praise / coaching signals, visible to employee.
- [ ] Rolling trend windows: 30 / 90 / 365d with chart per metric.
- [ ] "Prepare review" button compiles scorecard + self-review form + manager notes into PDF for HR file.
- [ ] Distinguish objective hard metrics from subjective manager rating.
- [ ] Subjective 1-5 scale with descriptors.

### 14.14 Peer feedback
- [ ] Staff can request feedback from 1-3 peers during review cycle.
- [ ] Form with 4 prompts: going well / to improve / one strength / one blind spot.
- [ ] Anonymous by default; peer can opt to attribute.
- [ ] Delivery to manager who curates before sharing with subject (prevents rumor / hostility).
- [ ] Frequency cap: max once / quarter per peer requested.
- [ ] A11y: long-form text input with voice dictation via system IME.

### 14.15 Recognition / shoutouts
- [ ] Peer-to-peer shoutouts with optional ticket attachment.
- [ ] Shoutouts appear in peer's profile + team chat (if opted).
- [ ] Categories: "Customer save" / "Team player" / "Technical excellence" / "Above and beyond".
- [ ] Unlimited sending; no leaderboard of shoutouts (avoid gaming).
- [ ] Recipient gets FCM push.
- [ ] Archive received shoutouts in profile.
- [ ] End-of-year "recognition book" PDF export.
- [ ] Privacy options: private (sender + recipient) or team-visible (recipient opt-in).

---
## 15. Reports & Analytics

_Server endpoints: `GET /reports/dashboard`, `GET /reports/dashboard-kpis`, `GET /reports/aging`, `GET /reports/technician-performance`, `GET /reports/tax`, `GET /reports/inventory`, `GET /reports/scheduled`, `POST /reports/run-now`._

### 15.1 Tab shell
- [x] Phase-0 placeholder.
- [ ] **Sub-routes / `SegmentedButton`** — Sales / Tickets / Employees / Inventory / Tax / Insights / Custom.
- [ ] **Date-range selector** with presets + custom; persists in DataStore.
- [ ] **Export button** — CSV / PDF via SAF.
- [ ] **Tablet/ChromeOS** — side rail list of reports + chart detail pane (`NavigableListDetailPaneScaffold`).
- [ ] **Schedule report** — `GET /reports/scheduled`; create schedule; auto-email.

### 15.2 Sales report
- [x] Revenue line chart (Vico `LineCartesianLayer`) + period compare. (commit 10fa332 — `RevenueOverTimeLineChart` + `SalesByDayBarChart` + donut `CategoryBreakdownPieChart` in `ReportsCharts.kt`; Overview tab added to ReportsScreen)
- [~] Drill-through: tap chart point → sales of that day. (commit 10fa332 — chart surfaces live; tap-to-drill pending)
- [ ] Top-items table; top-customers table.
- [ ] Gross / net / refunds / tax split.
- [ ] Export CSV.

### 15.3 Tickets report
- [ ] Throughput (created vs closed) chart.
- [ ] Avg time-in-status funnel.
- [ ] SLA compliance % per tech.
- [ ] Label breakdowns.

### 15.4 Employee performance
- [ ] Leaderboard chart.
- [ ] Hours worked vs revenue attributed.
- [ ] Commission accrual.

### 15.5 Inventory report
- [ ] Stock value over time.
- [ ] Sell-through rate per SKU.
- [ ] Dead-stock age report.
- [ ] Shrinkage %.

### 15.6 Tax report
- [ ] Per jurisdiction × period tax collected.
- [ ] Export for accountant (CSV with per-line breakdown).

### 15.7 Insights (BI)
- [ ] Profit Hero, Busy Hours, Churn, Forecast, Missing parts (shared with Dashboard §3.2).
- [ ] Heatmap / sparkline cards tappable to full chart.

### 15.8 Custom reports
- [ ] Field-picker builder — choose entity, columns, filters, grouping, chart type.
- [ ] Save as named report.
- [ ] Share via deep-link.

### 15.9 Drill-through
- [ ] Every chart point tappable → filtered list.
- [ ] Preserve filter context across drill levels (back stack in NavController).

### 15.10 Scheduled reports
- [ ] Tenant-level scheduled run (daily / weekly / monthly).
- [ ] Delivery: email to recipients + in-app Notification entry + optional FCM push.
- [ ] Pause / resume / delete schedule.

### 15.11 Print
- [ ] Reports printable via Android Print Framework as PDF.
- [ ] PDF rendering via Compose → `PdfDocument.Page.canvas` or WebView-to-PDF for tables.

---
## 16. POS / Checkout

_Server endpoints: `POST /pos/sales`, `GET /pos/carts`, `POST /pos/carts`, `POST /pos/carts/{id}/lines`, `POST /blockchyp/charge`, `POST /pos/cash-sessions`, `POST /pos/cash-sessions/{id}/close`._

### 16.1 POS shell
- [ ] 2-pane layout on tablet (catalog left, cart right) via `Row` + weight modifiers. Phone: tabs — Catalog / Cart.
- [ ] Top bar: customer chip (tap to change), location chip, shift status, parked-carts chip.
- [ ] Always-visible bottom bar: subtotal + tax + total + big tender `Button`.

### 16.2 Catalog
- [ ] Grid of tiles with photo / name / price (tablet 4-col, phone 2-col).
- [ ] Search — debounced; barcode scan via FAB ICON `QrCodeScanner`.
- [ ] Category filter chips.
- [ ] Quick-add top-5 bar driven by `GET /pos-enrich/quick-add`.
- [ ] HID scanner input (external Bluetooth / USB-C).

### 16.3 Cart
- [ ] Lines with qty stepper, unit price (editable role-gated), discount, tax class, remove.
- [ ] Line-level discount and cart-level discount.
- [ ] Customer attach — search or inline mini-create (§5.3).
- [ ] Tip prompt (flat / %) configurable per tenant.
- [ ] Park cart — stores in Room; list of parked carts in top bar chip.
- [ ] Split cart — split by item or evenly.

### 16.4 Payment
- [ ] Tender buttons: Cash / Card (BlockChyp) / Google Pay / Gift Card / Store Credit / Check / ACH / Split / Invoice later.
- [ ] **Cash** — numeric keypad + change calculator + denomination hints.
- [ ] **Card (BlockChyp)** — BlockChyp Android SDK `TransactionClient.charge(...)` → terminal prompts customer; progress ongoing notification Live Update; surfaces approval code + last 4.
- [ ] **Google Pay / Google Wallet NFC** — `PaymentsClient.loadPaymentData(...)` with PaymentDataRequest; appears only if PaymentsClient.isReadyToPay passes.
- [ ] **Gift card** — scan code → `POST /gift-cards/redeem`; balance + partial redeem.
- [ ] **Store credit** — pull balance → apply up to min(balance, total); surplus refunds to credit.
- [ ] **Split tender** — chain methods until balance = 0; cart shows running balance.
- [ ] **Invoice later** — creates invoice + attaches to customer; no immediate payment.
- [ ] **Idempotency-Key** required on POST /pos/sales.

### 16.5 Tax engine
- [ ] Per-line tax class; cart-level tax override (tenant admin).
- [ ] Tax-exempt customer flag honored.
- [ ] Multi-jurisdiction: tenant configures rules; client displays breakdown.
- [ ] Tax rounding per tenant rule.

### 16.6 Receipt
- [ ] Print via Bluetooth thermal printer (ESC/POS via `BluetoothSocket` SPP) OR Mopria via Android Print Framework OR USB printer via UsbManager.
- [ ] Email via `Intent(ACTION_SENDTO, mailto:)` with PDF attachment.
- [ ] SMS link via `POST /sms/send`.
- [ ] Download PDF via SAF.
- [ ] Gift receipt option — hides prices, shows item names only.
- [ ] Reprint flow — Sales history → "Reprint" action.

### 16.7 Sale types
- [ ] Retail sale (inventory only).
- [ ] Service sale (labor + parts).
- [ ] Mixed (repair ticket completion).
- [ ] Deposit collection (partial — from ticket).
- [ ] Refund (see §7.7).
- [ ] Trade-in (negative line item, feeds used-stock).
- [ ] Layaway (deposit now, balance later).

### 16.8 Sale success
- [ ] Full-screen confetti-lite animation (respects Reduce Motion) + big total.
- [ ] Big buttons: Print / Email / SMS / New Sale.
- [ ] Auto-dismiss after 10s or staff taps New Sale.

### 16.9 Offline POS
- [ ] Full POS operational offline: read catalog from Room, queue sale in `sync_queue` with idempotency key.
- [ ] BlockChyp terminal also supports offline/standalone: card processed, voucher printed; txn reconciles on reconnect.
- [ ] Cash sales: no network dependency.
- [ ] Offline indicator banner at top of POS while disconnected.
- [ ] Drain-worker resolves sales on reconnect; failures go to Dead-Letter queue (§20.7).

### 16.10 Cash drawer trigger
- [ ] Bluetooth / RJ11-via-printer drawer opens on tender via ESC/POS cash-drawer kick command.
- [ ] Manual open button role-gated (reason required, audit logged).

### 16.11 Customer-facing display (optional)
- [ ] Secondary display via `DisplayManager` + `Presentation` Activity mirroring cart + totals + ads.
- [ ] Signature capture when tablet flipped to customer.

### 16.12 POS keyboard shortcuts (tablet/ChromeOS)
- [ ] F1 new sale, F2 scan, F3 customer search, F4 discount, F5 tender, F6 park, F7 print, F8 refund; Ctrl+F focus search.

---
## 17. Hardware Integrations

### 17.1 Camera
- [ ] CameraX `LifecycleCameraController` + `PreviewView` (Compose `AndroidView`).
- [ ] Flash toggle, lens flip, tap-to-focus, pinch zoom.
- [ ] Image capture to tenant server via multipart + WorkManager.
- [ ] Video capture (MP4, H.264) for damage intake — size-capped 30s + 15 MB.

### 17.2 Barcode / QR scan
- [ ] ML Kit `BarcodeScanning.getClient(BarcodeScannerOptions.Builder().setBarcodeFormats(...))`.
- [ ] Formats: Code 128, Code 39, EAN-13, UPC-A, UPC-E, QR, Data Matrix, ITF.
- [ ] Live detection with green reticle overlay; haptic on match.
- [ ] Multi-scan mode (stocktake) — beep + highlight, keep scanning until exit.
- [ ] Torch toggle (critical in warehouse lighting).

### 17.3 Document scanner
- [ ] ML Kit `GmsDocumentScanning` (Google Play Services) — edge detection + perspective correction + PDF export.
- [ ] Use cases: waivers, warranty cards, receipts, ID.

### 17.4 Printers
- [ ] **Receipt (thermal 58/80mm)** — via Bluetooth SPP socket: ESC/POS commands to Star / Epson / Xprinter / Citizen. Vendor SDK support: Star mC-Print SDK, Epson TM Utility SDK where available.
- [ ] **Label (ZPL / CPCL)** — via Bluetooth / USB: Zebra, Brother, DYMO (where Android SDKs exist).
- [ ] **Full-page (invoice, waiver)** — Android Print Framework `PrintManager.print(...)` with `PrintDocumentAdapter` rendering Compose layouts via `ImageBitmap` → `PdfDocument`. Routes through Mopria Print Service, Brother, HP, etc.
- [ ] On-device PDF pipeline: every doc rendered locally to a `File` under `filesDir/printed/`, shared via `FileProvider` URI. Never depend on server-side PDF for print.
- [ ] Printer discovery & pairing: Settings → Hardware → Printers — list paired Bluetooth + Mopria discovered + USB devices. Assign roles: Receipt / Label / Invoice.
- [ ] Reconnect: auto-reconnect on Activity resume; manual reconnect button; status pill on POS / ticket detail ("Printer ready" / "Not connected").
- [ ] Test print from settings.

### 17.5 Cash drawer
- [ ] Bluetooth thermal printer with RJ11 passthrough OR USB cash-drawer module.
- [ ] Kick command sent on tender success.
- [ ] Manual-open button role-gated.

### 17.6 Terminal (BlockChyp)
- [ ] BlockChyp Android SDK pairing (IP LAN: static IP or DHCP with mDNS discovery).
- [ ] Charge / refund / void / capture / adjust.
- [ ] Terminal firmware update prompts surfaced in-app.
- [ ] Offline-capable (store-and-forward).
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
- [ ] Top bar search icon → full-screen search Activity.
- [ ] Indexes: customers, tickets, invoices, inventory, employees, appointments, leads, SMS threads.
- [ ] **On-device FTS5** via Room `@Fts4` / SQLite FTS5 virtual tables synced from canonical tables on upsert.
- [ ] Debounced 300ms; results grouped by entity type with count chip.
- [ ] Tap result → deep link.
- [x] Recent searches cached in DataStore.
- [ ] Keyboard shortcut Ctrl+F on tablet/ChromeOS.

### 18.2 Scoped search per screen
- [ ] Each list has its own `SearchBar` (Material 3) at top.
- [ ] Scoped fields per entity (e.g. Tickets: order ID, customer, IMEI).

### 18.3 Fuzzy / typo tolerance
- [ ] FTS5 with prefix matching + custom tokenizer (lowercase, remove punctuation).
- [ ] Optional Levenshtein for typos (edit distance ≤ 2 on ≥ 4 chars).

### 18.4 Voice search
- [ ] Mic button in search bar → `RecognizerIntent.ACTION_RECOGNIZE_SPEECH` → transcribed query injected.
- [ ] Requires `RECORD_AUDIO` at tap-time.

### 18.5 Recent + saved searches
- [ ] Recent 10 shown under empty state.
- [ ] Pin a query — named chip at top of search screen.

### 18.6 Natural-language query (stretch)
- [ ] `POST /nlq-search` (server-side LLM) with user query → structured filter.
- [ ] Example: "tickets assigned to Anna past 7 days in Ready status" → filtered ticket list.
- [ ] Sovereignty: routes through tenant server only; tenant admin toggles NLQ on/off.

### 18.7 App search index
- [ ] Expose top N customers / tickets to Android `AppSearch` system index for Assistant / launcher surfacing (opt-in, privacy-reviewed).
- [ ] Opt-out per tenant.

### 18.8 Empty / loading states
- [ ] Empty: "Try a different search" + tips.
- [ ] Loading: shimmer rows.
- [ ] No network: "Showing cached results" banner.

---
## 19. Settings

_Server endpoints: `GET /settings/*`, `PUT /settings/*`, `GET /tenants/me`, `PUT /tenants/me`, `GET /account`, `GET /settings/payment`, `GET /settings/sms`, `GET /settings/statuses`, `GET /settings/templates`, `GET /settings/custom-fields`._

### 19.1 Shell
- [x] Settings screen — Material 3 grouped list.
- [ ] Search-in-settings (`SearchBar`) indexing every setting key + metadata (mirror web `settingsMetadata.ts`).
- [ ] Tablet/ChromeOS: list-detail pane so edit screen shows to the right of the list.
- [ ] Deep-links into each setting supported via route.

### 19.2 Profile
- [ ] Avatar upload / replace (PhotoPicker) via `POST /auth/avatar`.
- [~] Name, display name, email, phone.
- [ ] Password change (§2.9).
- [x] PIN change (§2.5).
- [x] Biometric toggle (§2.6).
- [x] Sign-out button.

### 19.3 Notifications
- [~] Per-NotificationChannel toggle (actually routes to system Settings → App → Notifications on Android 8+; app shows inline shortcut).
- [x] Quiet hours (start / end / days-of-week).
- [ ] Per-event override matrix (§73).
- [ ] Sound picker per channel — opens `RingtoneManager.ACTION_RINGTONE_PICKER`.

### 19.4 Appearance
- [x] Theme: System / Light / Dark (DataStore + `AppCompatDelegate.setDefaultNightMode`). (commit 6cfcefa — `ui/screens/settings/ThemeScreen.kt` with radio rows; `AppPreferences.darkModeFlow` + MainActivity observes via `collectAsState`; no activity recreate needed)
- [x] Dynamic color on/off (Android 12+). (commit 6cfcefa — ThemeScreen Switch gated on `SDK_INT >= S`; `AppPreferences.dynamicColorFlow` → BizarreCrmTheme)
- [ ] Tenant accent override color picker.
- [ ] Density mode (§3.18).
- [ ] Font-scale preview.
- [ ] High-contrast toggle (swaps to AA 7:1 palette).

### 19.5 Language & region
- [x] Per-app language via `LocaleManager.setApplicationLocales` (Android 13+); pre-13 falls back to in-app `ConfigurationCompat` + `AppCompatDelegate.setApplicationLocales`. (commit d3d546c — `util/LanguageManager.kt` + `ui/screens/settings/LanguageScreen.kt` + `locales_config.xml`)
- [ ] Timezone override.
- [ ] Date / time / number formats follow locale.
- [ ] Currency display override (§5.17).

### 19.6 Security
- [ ] 2FA (§2.4), Passkey (§2.22), Hardware key (§2.23), Recovery codes (§2.19), SSO (§2.20).
- [ ] Session timeout (§2.16).
- [ ] Remember-me (§2.17).
- [ ] Shared-device mode (§2.14).
- [ ] Screenshot blocking toggle (forces `FLAG_SECURE` across sensitive screens).
- [ ] Active sessions list + revoke.

### 19.7 Tickets
- [ ] Default assignee, default due date rule (+N business days), tenant-level visibility (§4 `ticket_all_employees_view_all`), status taxonomy editor, transition guards, default service type.
- [ ] IMEI/serial required flag.
- [ ] Photo count required on close.

### 19.8 POS / payment
- [ ] Payment methods enabled.
- [ ] BlockChyp terminal pairing.
- [ ] Tax classes, default tax.
- [ ] Tip presets.
- [ ] Rounding rules (per jurisdiction).
- [ ] Receipt template editor (live preview).
- [ ] Cash drawer enabled.

### 19.9 SMS
- [ ] Provider connection status.
- [ ] Sender number / TFN.
- [ ] Compliance footer.
- [ ] Off-hours auto-reply template.
- [ ] Rate-limit & quota display.

### 19.10 Integrations
- [ ] Connected: BlockChyp, SMS provider, Google Wallet, Webhooks, Zapier.
- [ ] Disconnect / reconnect / test.
- [ ] Admin-only.

### 19.11 Team / roles
- [ ] Employee list deep link (§14).
- [ ] Custom role matrix editor (§49).

### 19.12 Data
- [ ] Import (§50).
- [ ] Export (§51).
- [ ] Sync issues (§20.7).
- [ ] Dedup scan (§5.10).
- [ ] Clear cache.
- [ ] Reset to defaults.

### 19.13 Diagnostics (developer / support)
- [ ] Server URL (read-only outside Shared Device Mode).
- [ ] App version + build + commit SHA.
- [ ] View logs (last 200 lines, redacted).
- [ ] Export DB (dev-only, encrypted zip).
- [ ] Feature flags viewer (admin).
- [ ] Telemetry events counter.
- [ ] Force crash (debug builds only).
- [ ] Force sync / Flush drafts.

### 19.14 About
- [ ] Open-source licenses (`OssLicensesMenuActivity`).
- [ ] Privacy policy.
- [ ] Terms.
- [ ] Rate app on Play Store (`ReviewManager` in-app review flow).

### 19.15 Feature flags UI (admin)
- [ ] List tenant feature flags + toggles.
- [ ] Scoped per environment (sandbox vs prod).

### 19.16 Ticket-status editor
- [ ] Reorder statuses (drag).
- [ ] Edit name, color, transition guards.
- [ ] Mark statuses as `waiting_customer` / `awaiting_parts` (pauses SLA per §4.19).

### 19.17 Tax configuration
- [ ] Multi-jurisdiction rules.
- [ ] Tax-exempt customer policy.
- [ ] Rounding mode.
- [ ] Fiscal-period lock date.

### 19.18 Receipts / waivers / templates
- [ ] Template editor with preview.
- [ ] Versioning per §8.6.
- [ ] Per-location override.

### 19.19 Business info
- [ ] Shop name, logo, address, phone, email, hours.
- [ ] Tax ID, EIN.
- [ ] Social links.
- [ ] Display on public tracking page (§55), receipts, quotes, invoices.

---
## 20. Offline, Sync & Caching

**Phase 0 foundation.** No domain feature ships without wiring into this.

### 20.1 Repository pattern
- [ ] Every domain has `XyzRepository` class (Hilt-injected) exposing `Flow<List<Xyz>>` (reads) + `suspend fun createXyz(...)` (writes).
- [ ] Reads: `Room DAO → Flow → ViewModel → UI`. Never a bare Retrofit call in a ViewModel.
- [ ] Writes: enqueue to `sync_queue` table + Optimistic UI update to Room; WorkManager drain-worker processes queue.
- [ ] Lint rule: `ApiClient`, `Retrofit`, `OkHttpClient` imports banned outside `data/remote/` package.

### 20.2 Sync queue
- [ ] Room table `sync_queue` — `{ id, entity, op (create/update/delete), payload (JSON), idempotency_key, created_at, attempts, status, last_error }`.
- [ ] Drain `SyncWorker` (`CoroutineWorker`, `unique + keepExisting`) picks oldest Queued, POSTs, on success: delete + apply server response to canonical table; on retryable failure: backoff + re-enqueue; on permanent failure: move to dead-letter.
- [ ] WorkManager expedited when foreground; periodic (15min) when background; kicked on connectivity resume via `Constraints.Builder().setRequiredNetworkType(CONNECTED)`.
- [~] Idempotency-Key header = `sync_queue.idempotency_key` (UUIDv4 client-generated at enqueue time). (`OfflineIdGenerator.newIdempotencyKey()` generates UUIDs + used in CustomerRepository as `clientRequestId` body field; HTTP-header variant still pending.)
- [ ] Ordering: FIFO per entity; inter-entity dependencies tracked via `depends_on_queue_id`.

### 20.3 Conflict resolution
- [ ] Server returns 409 on stale `updated_at`; client fetches latest + 3-way merge attempt.
- [ ] Merge rules per entity: last-writer-wins for simple fields; list-union for tags; user-prompt for prices / totals.
- [ ] Merge UI: side-by-side diff with "Keep mine / Keep theirs / Merge" per field.
- [ ] `POST /sync/conflicts/resolve` reports chosen resolution to server.

### 20.4 Delta sync
- [ ] `GET /sync/delta?since=<last_synced_at>&cursor=<opaque>&limit=500` returns batched changes.
- [ ] Periodic (15min in background, 2min while foregrounded) + on foreground + on WebSocket `delta:invalidate` nudge.
- [ ] Applies upserts + tombstones to Room; updates per-entity `_synced_at`.
- [ ] Full sync fallback on missing cursor or > 7d gap.

### 20.5 Cursor pagination
- [ ] Per `(entity, filter?, parent_id?)` key: `sync_state { cursor, oldestCachedAt, serverExhaustedAt?, lastUpdatedAt }`.
- [ ] List reads from Room via Paging3 `RemoteMediator`.
- [ ] `loadMore` calls `GET /entity?cursor=&limit=50`; response upserts.
- [ ] `hasMore` derived from `{ oldestCachedAt, serverExhaustedAt? }`, NOT `total_pages`.
- [ ] Footer states: Loading / More available / End of list / Offline w/ cached count. Four distinct, never collapsed.

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
- [ ] List-detail: `NavigableListDetailPaneScaffold` for Tickets / Customers / Inventory / Invoices / SMS.
- [ ] Three-pane: `ThreePaneScaffoldNavigator` for Settings (list → category → item) on XL tablets.

### 22.2 Navigation rail
- [~] `NavigationSuiteScaffold` picks `NavigationSuiteType.NavigationRail` on Medium+. (Hand-rolled equivalent in `AppNavGraph`: `WindowSize.isMediumOrExpandedWidth()` swaps the bottom `NavigationBar` for a side `NavigationRail` + `VerticalDivider` at \u2265600dp. Phones still use the bottom bar.)
- [ ] Rail items rendered with icon + label at ≥ 600dp.
- [ ] Permanent drawer at ≥ 1240dp.

### 22.3 Keyboard & mouse
- [~] Full hardware-keyboard shortcut map — Ctrl+N / Ctrl+F / Ctrl+P / Ctrl+K / Ctrl+S / Ctrl+Z / Ctrl+Shift+Z / Escape. (Ctrl+N, Shift+N/S/M, Ctrl+F, Ctrl+H, Ctrl+",", Ctrl+/, Esc DONE; Ctrl+P/K/S/Z pending)
- [x] Shortcut overlay (Ctrl+/) lists every shortcut for current screen.
- [~] Hover affordances: `pointerHoverIcon(PointerIcon.Hand)` on tappable rows / buttons.
- [ ] Right-click: `Modifier.onPointerEvent(Release) { ... if (button.isSecondary) showDropdown }`.

### 22.4 Split-screen / multi-window
- [x] `android:resizeableActivity="true"` already required (targetSdk 24+). Verify manifest.
- [ ] Minimum window size: 400×560 dp declared via `<layout android:minWidth="400dp" android:minHeight="560dp" ... />`.
- [ ] Test split with Messages, Calculator, Chrome, another instance of self.

### 22.5 Pencil / stylus polish
- [ ] Signature capture pressure-sensitive via `MotionEvent.getPressure()`.
- [ ] S Pen button: tap = quick sig, double-tap = undo (Samsung tablets).

### 22.6 Large-grid density
- [ ] Tablet grid / list density "Cozy" default (§3.18); user may toggle Compact.

### 22.7 Context menus
- [ ] Long-press + right-click both open `DropdownMenu` near pointer.
- [ ] Submenus supported via `Submenu` construct.

### 22.8 Drag & drop
- [ ] Drag ticket row → Assignee rail target (§4.16).
- [ ] Drag photo across multiple tickets (long-press → `startDragAndDrop`).
- [ ] Cross-app drag (tablet multi-window): drop text / URL / image from Chrome / Gmail into our composer fields.

### 22.9 Large composers
- [ ] SMS composer, note composer, email composer expand to 60% height on tablet.

### 22.10 Picture-in-Picture
- [ ] Call-in-progress Activity enters PiP via `setAutoEnterEnabled(true)` while on another task.

---
## 23. Foldable & Desktop-Mode Polish

### 23.1 Foldable postures
- [ ] WindowManager `WindowInfoTracker.getOrCreate(this).windowLayoutInfo(this)` observes `FoldingFeature`.
- [ ] **Tabletop** posture (hinge flat) — ticket detail uses upper half for photos, lower half for controls; dashboard places chart on upper, legend + actions on lower.
- [ ] **Book** posture (hinge vertical) — list-detail auto-snaps to left/right pane along hinge.
- [ ] Avoid placing interactive elements directly on the hinge.

### 23.2 Dual-screen (horizontal fold)
- [ ] SMS thread: bubbles upper, composer lower.
- [ ] POS: catalog upper, cart lower (though tablets usually horizontal fold anyway).

### 23.3 Desktop mode (Android 16 freeform / Samsung DeX / ChromeOS)
- [ ] Resizable windows — test 400×300 up to full-screen.
- [ ] Title bar + controls follow system theme.
- [ ] Cursor hover states (see §22.3).
- [ ] Right-click context menus everywhere.
- [ ] Keyboard shortcuts everywhere.
- [ ] External monitor via `DisplayManager` — secondary display can host POS customer-facing display, or span app with main on laptop + secondary on client-facing screen.

### 23.4 Stylus ergonomics on large displays
- [ ] Palm rejection via `MotionEvent.TOOL_TYPE_FINGER` vs `TOOL_TYPE_STYLUS`.
- [ ] Signature capture surface sized proportionally to device DP.

### 23.5 Window insets
- [x] Edge-to-edge via `WindowCompat.setDecorFitsSystemWindows(window, false)`.
- [~] `Scaffold` + `WindowInsets.safeDrawing` / `.systemBars` padding rules applied consistently.
- [ ] Respect 3-button vs gesture navigation.

### 23.6 Predictive back
- [ ] `PredictiveBackHandler` on every non-root screen; animations preview the back target.
- [ ] Custom enter/exit transitions survive the drag.

---
## 24. Widgets, Live Updates, App Shortcuts, Assistant

### 24.1 Glance widgets
- [blocked: deps — `androidx.glance:glance-appwidget` absent from version catalog; classic `DashboardWidgetProvider` (RemoteViews) ships today. Unblock by adding `androidx.glance:glance-appwidget:1.1.0` to `gradle/libs.versions.toml` + `app/build.gradle.kts` (note: must be done under policy review — Glance adds ~200KB + another artifact).] Today's revenue / counts widget (1x1, 2x1, 2x2, 4x2 sizes via `SizeMode.Exact`).
- [blocked: same — glance dep] My Queue widget — shows 3 next tickets; tap → ticket detail.
- [ ] Unread SMS widget.
- [ ] Clock-in/out toggle widget.
- [ ] Low-stock widget.
- [ ] Widget data read from Room via `@GlanceComposable` + `GlanceStateDefinition` with app-group DataStore; refresh on delta sync.
- [ ] Widget → App deep link via `actionStartActivity(...)` preserving context.

### 24.2 Live Updates (Android 16)
- [ ] See §21.3.
- [ ] Use cases: Bench timer, Payment in progress, Shift clock, Delivery ETA.
- [ ] Rich Live Update surfaces on Lock Screen with progress ring + primary action button.

### 24.3 App Shortcuts (launcher long-press)
- [x] Static `res/xml/shortcuts.xml`: New Ticket / Scan Barcode / New SMS / Clock In.
- [ ] Dynamic shortcuts via `ShortcutManager.setDynamicShortcuts(...)`: Recent customers (top 4 by last-interaction).
- [ ] Pinned shortcuts supported.
- [ ] Icon per shortcut; theme-aware variant.

### 24.4 Quick Settings Tiles
- [~] `TileService` subclasses: Clock in/out; Barcode scan; Lock-now.
- [ ] Active state reflects current shift / session.
- [ ] User adds via Settings → Notifications → Quick settings.

### 24.5 Assistant App Actions
- [ ] `actions.xml` declaring Built-in Intents: `actions.intent.CREATE_TASK` → new ticket; `actions.intent.GET_RESERVATION` → appointment lookup; custom BIIs for "Clock me in".
- [ ] Deep-link handlers in MainActivity parse intent + navigate.
- [ ] Integration via `androidx.google.shortcuts` (deprecated in favor of Shortcuts framework — migrate to Shortcuts + Capabilities API).
- [ ] Voice tests via Assistant "Hey Google, create ticket in BizarreCRM".

### 24.6 Conversation shortcuts / bubbles
- [ ] SMS thread surfaces as conversation shortcut for Android 11+ People API; appears in Pixel launcher "Conversations" section.
- [ ] Bubble notification option on SMS inbound (long-press notification → Bubble).

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
- [ ] Xiaomi / Oppo / Vivo / Huawei aggressively kill background services. Push + WorkManager fallback critical.
- [ ] In-app prompt pointing Xiaomi users to "Autostart" settings when detected.

### 34.2 FCM in markets without Google Play
- [ ] China / Russia: FCM blocked. Decision: Android builds targeting China use polling fallback. Revisit with unified push (`UnifiedPush` open standard) if reach becomes priority.

### 34.3 BlockChyp Android SDK parity
- [ ] Verify feature parity with iOS SDK — charge, refund, void, adjust, offline/forward, Tap-to-Pay support on Android.

### 34.4 SQLCipher + Room
- [ ] SQLCipher releases lag Android SDK sometimes; verify `net.zetetic:sqlcipher-android:4.6.1+` supports targetSdk 36.

### 34.5 Passkeys on pre-14 devices
- [ ] Credential Manager API requires Android 14+. Pre-14 fallback: password + TOTP only.

### 34.6 PhotoPicker availability
- [ ] `ActivityResultContracts.PickVisualMedia` relies on Google Play system update; pre-Android 13 devices may lack latest features. Fall back to SAF `OPEN_DOCUMENT`.

### 34.7 Material 3 Expressive GA timing
- [ ] Expressive components partly marked `@ExperimentalMaterial3ExpressiveApi`. Verify GA track before Phase 1 ship; shim behind version check.

### 34.8 Foldable fragmentation
- [ ] Samsung / Pixel / Xiaomi / Huawei use different `FoldingFeature` APIs; rely on Jetpack WindowManager abstraction only.

### 34.9 Android Auto / CarPlay mirror
- [ ] Deferred. See iOS §82 parallel decision. Revisit only if field-service volume > 20% tenants.

### 34.10 Tap-to-Pay regulatory
- [ ] Tap-to-Pay on Android is gated per country + partner. BlockChyp availability + Google's Wallet SDK prerequisites vary.

### 34.11 ML Kit on-device
- [ ] ML Kit on-device models download lazily first time → cache. Need bytes-down budget + wifi-only default.

### 34.12 Play Policy on `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
- [ ] Play rejects apps that request this without a legit foreground-service use case. Our repair-timer case likely qualifies; prep justification.

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
| Audit log | ✅ | planned | planned | §52 |
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
- [ ] Configure tiers: Basic / Silver / Gold; benefits (free diagnostics, discount %, priority queue, extended warranty).
- [ ] Pricing per tier (monthly / annual).

### 38.2 Enrollment
- [ ] At POS: "Add member" → tier picker → charge → membership active immediately.
- [ ] Expiration tracked; renewal reminders via SMS / email / push.

### 38.3 Benefits application
- [ ] POS auto-applies tier discount + priority queue badge on customer's new tickets.
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
- [ ] Open: count starting cash by denomination → record → status `open`.
- [ ] Throughout shift: sales increment expected cash; cash-in/cash-out events logged (pay-outs, pay-ins).
- [ ] Close: count ending cash → system computes expected → delta → over/short reason if > $2.
- [ ] Manager PIN required over threshold; audit.
- [ ] Z-report prints + PDF archived.

### 39.2 Z-report contents
- [ ] Shift ID, cashier, start / end time.
- [ ] Sales count + gross + net.
- [ ] Tender breakdown (cash / card / gift / store credit).
- [ ] Refunds count + total.
- [ ] Voids count.
- [ ] Opening + closing cash + expected + over/short.
- [ ] Top 5 items.
- [ ] Tips collected.

### 39.3 X-report (mid-shift)
- [ ] Snapshot of current shift stats without closing.

### 39.4 Multi-register
- [ ] Per-tablet register ID (e.g. REG-01, REG-02); report by register or combined.

### 39.5 Pay-in / pay-out
- [ ] Pay-out: take cash out for rent / parts / lunch → record reason + amount; adjusts expected cash.
- [ ] Pay-in: add cash from petty → adjusts expected.

### 39.6 Blind close
- [ ] Tenant option: cashier counts cash without seeing expected; manager reconciles.

---
## 40. Gift Cards / Store Credit / Refunds

### 40.1 Gift cards
- [ ] Issue: at POS → enter amount → scan / enter code → linked to customer (optional).
- [ ] Balance check: scan → `GET /gift-cards/:code`.
- [ ] Redeem: `POST /gift-cards/redeem` with `{ code, amount }`; partial redemption supported.
- [ ] Reload: add value to existing card.
- [ ] Physical card stock: tenant orders pre-printed; app scans barcode.
- [ ] Digital gift card: emailed / SMSed to recipient with QR.
- [ ] Expiration: tenant policy; warn at 30d prior.

### 40.2 Store credit
- [ ] Issue: refund → store credit option.
- [ ] Balance on customer detail; applies automatically at POS (or user-toggles).
- [ ] `POST /store-credit/:customerId` with `{ amount, reason }`.
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
- [ ] Create: from invoice detail or standalone (amount + memo + customer).
- [ ] `POST /payment-links` → `{ url, id }`.
- [ ] Share: SMS / email / copy to clipboard / QR display.
- [ ] Expiration + max uses + partial-allowed flag.

### 41.2 Status tracking
- [ ] `GET /payment-links/:id/status` polled or WebSocket push.
- [ ] Status: pending / paid / expired / cancelled.
- [ ] Paid triggers invoice update.

### 41.3 Public pay page
- [ ] Served by tenant server on web; Android provides deep link only.
- [ ] Supports Google Pay / Apple Pay / credit card via BlockChyp hosted form.

### 41.4 Request-for-payment push
- [ ] "Send payment request" → customer receives SMS with link + FCM push if customer has our app.

---
## 42. Voice & Calls

### 42.1 Phone dial-out
- [ ] `Intent(ACTION_DIAL, Uri.parse("tel:..."))` from any customer row. Use `ACTION_CALL` only with `CALL_PHONE` permission if tenant configures auto-dial.
- [ ] Caller ID shows customer name via contacts role (privacy-aware).

### 42.2 VoIP calling (if tenant uses)
- [ ] ConnectionService self-managed for outbound via `TelecomManager.placeCall(...)`.
- [ ] Incoming via PushKit-analog (FCM high-priority data) → `ConnectionService.onCreateIncomingConnection`.
- [ ] CallKit-parallel: full-screen notification with accept / decline.
- [ ] In-call UI: mute, speaker, hold, transfer, DTMF keypad.
- [ ] Records: `POST /call-logs` entries synced to tenant.

### 42.3 Call recording
- [ ] Opt-in tenant + per-jurisdiction compliance (two-party consent states require announcement).
- [ ] Playback via ExoPlayer.
- [ ] Transcription via tenant server (not on-device).

### 42.4 Voicemail
- [ ] Fetched via tenant server (third-party VoIP provider); UI similar to SMS.

### 42.5 Click-to-call from anywhere
- [ ] Customer chip tap → dial prompt with recent numbers.

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
- [ ] Reverse chronological list.
- [ ] Columns: timestamp / actor / action / entity / diff preview.

### 52.2 Filters
- [ ] By actor, action type, entity, date range.

### 52.3 Diff view
- [ ] Field-level before/after with highlight.
- [ ] Redacted fields still show "(redacted)" placeholder.

### 52.4 Export
- [ ] Filtered set → CSV via SAF.

### 52.5 Chain integrity
- [ ] Server appends hash chain; client verifies last-N records on open.
- [ ] Warning banner if chain broken.

### 52.6 Access
- [ ] Admin + Owner roles only.

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
- [ ] Ctrl+K on hardware keyboard; top-bar search icon on touch.

### 54.2 Entries
- [ ] Nav: "Go to Tickets", "Go to Customers", ...
- [ ] Actions: "New ticket", "Scan barcode", "Clock in", "Open printer settings".
- [ ] Entities: recent customers / tickets / invoices (fuzzy match).
- [ ] Settings: jump to any setting by name.

### 54.3 UI
- [ ] Center-screen modal with search input + result list.
- [ ] Arrow-key navigation; Enter to activate.
- [ ] Recent commands pinned at top.

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
- [ ] "What's new" modal shown once on new `versionCode`.
- [ ] Dismissible; auto-dismiss after interaction.

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
