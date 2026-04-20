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
> - GRDB + SQLCipher offline cache per repository. Optimistic UI + sync queue for mutations.
> - Pagination: **cursor-based, offline-first** (see §20.5). Lists read from SQLCipher via `ValueObservation` — never from API directly. `loadMoreIfNeeded(rowId)` kicks next-cursor fetch when online; no-op when offline (or un-archives evicted older rows). `hasMore` derived locally from `{ oldestCachedAt, serverExhaustedAt? }` per entity, NOT from `total_pages`. Footer has four distinct states: loading / more-available / end-of-list / offline-with-cached-count.
> - Accessibility: VoiceOver label on every tappable glyph, Dynamic Type tested to XXXL, Reduce Motion + Reduce Transparency honored, 44pt min tap target.
> - Mac: keyboard shortcuts (⌘N / ⌘F / ⌘R / ⌘,), `.hoverEffect(.highlight)`, `.textSelection(.enabled)` on IDs/emails/invoice numbers, `.contextMenu` on rows, `.fileExporter` for PDF/CSV.
>
> **Source-of-truth map.**
> - Web routes: `packages/web/src/{pages,app}/`
> - Android: `packages/android/app/src/main/java/.../ui/screens/`
> - Server API: `packages/server/src/routes/`
> - Contracts: `packages/contracts/`
> - iOS modules: `ios/Packages/<Domain>/Sources/`

---

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
22. [iPad-Specific Polish](#22-ipad-specific-polish)
23. [Mac ("Designed for iPad") Polish](#23-mac-designed-for-ipad-polish)
24. [Widgets, Live Activities, App Intents, Siri, Shortcuts](#24-widgets-live-activities-app-intents-siri-shortcuts)
25. [Spotlight, Handoff, Universal Clipboard, Share Sheet](#25-spotlight-handoff-universal-clipboard-share-sheet)
26. [Accessibility](#26-accessibility)
27. [Internationalization & Localization](#27-internationalization--localization)
28. [Security & Privacy](#28-security--privacy)
29. [Performance Budget](#29-performance-budget)
30. [Design System & Motion](#30-design-system--motion)
31. [Testing Strategy](#31-testing-strategy)
32. [Telemetry, Crash, Logging](#32-telemetry-crash-logging)
33. [CI / Release / TestFlight / App Store](#33-ci--release--testflight--app-store)
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
54. [Command Palette (⌘K)](#54-command-palette-k)
55. [Public Tracking Page (customer-facing)](#55-public-tracking-page-customer-facing)
56. [TV Queue Board (in-shop display)](#56-tv-queue-board-in-shop-display)
57. [Assistive / Kiosk Single-Task Modes](#57-assistive--kiosk-single-task-modes)
58. [Appointment Self-Booking (customer)](#58-appointment-self-booking-customer)
59. [Field-Service / Dispatch (mobile tech)](#59-field-service--dispatch-mobile-tech)
60. [Inventory Stocktake](#60-inventory-stocktake)
61. [Purchase Orders (inventory)](#61-purchase-orders-inventory)
62. [Financial Dashboard (owner view)](#62-financial-dashboard-owner-view)
63. [Multi-Location Management](#63-multi-location-management)
64. [Release checklist (go-live gates)](#64-release-checklist-go-live-gates)
65. [Non-goals (explicit)](#65-non-goals-explicit)
66. [Error, Empty & Loading States](#66-error-empty--loading-states-cross-cutting)
67. [Copy & Content Style Guide](#67-copy--content-style-guide-ios-specific-tone)
68. [Deep-link / URL scheme reference](#68-deep-link--url-scheme-reference)
69. [Haptics Catalog](#69-haptics-catalog-iphone-specific)
70. [Motion Spec](#70-motion-spec)
71. [Launch Experience](#71-launch-experience)
72. [In-App Help](#72-in-app-help)
73. [Notifications — granular matrix](#73-notifications--granular-per-event-matrix)
74. [Privacy-first analytics event list](#74-privacy-first-analytics-event-list)
75. [Final UX Polish Checklist](#75-final-ux-polish-checklist)

---

## 1. Platform & Foundation

Baseline infra the rest of the app depends on. All of it ships before anything domain-specific claims parity.

> **Data-sovereignty principle (global).** The app has **exactly one network egress target**: `APIClient.baseURL`, the server the user entered at login (e.g. `bizarrecrm.com` or a self-hosted URL). **No third-party SDK may open a network socket** — no Sentry, Firebase, Mixpanel, Amplitude, Bugsnag, Crashlytics, Datadog, New Relic, FullStory, Segment, etc. Telemetry, crash reports, experiment assignments, heartbeats, and diagnostics all POST to the tenant server only. Apple's device-level crash reporting (opt-in per device) is the single exception. See §32 for enforcement (CI linter + privacy manifest audit).

### 1.1 API client & envelope
- [x] `APIClient` with dynamic base URL (`APIClient.setBaseURL`) — shipped.
- [x] `{ success, data, message }` envelope decoder — shipped.
- [x] Bearer-token injection from Keychain — shipped.
- [ ] **Token refresh on 401 with retry-of-original-request.** Current behavior: 401 → drop to Login. Target: refresh silently, replay original request once, fall back to drop-to-login only if refresh fails. Backend: `POST /auth/refresh` (verify exists). Frontend: request-middleware that queues concurrent calls behind a single refresh in-flight. UX: user never sees a re-login unless the refresh token is expired/revoked.
- [ ] **Typed endpoint namespaces** — migrate each repository to an `Endpoint` enum (`Endpoints.Tickets.list(page:filter:)`) so path strings are not scattered across files.
- [ ] **Multipart upload helper** (`APIClient.upload(_:to:fields:)`) for photos, receipts, avatars. Must use a background `URLSession` configuration so uploads survive app exit.
- [ ] **Retries with jitter** on transient network failures (5xx, URLError `.timedOut`, `.networkConnectionLost`). Respect `Retry-After` on 429.
- [ ] **Offline detection banner** driven by `NWPathMonitor` — sticky `.brandGlass` banner at the top of `NavigationStack`s with "Offline — showing cached data" copy and a Retry button.

### 1.2 Pinning & TLS
- [x] `PinnedURLSessionDelegate` scaffold — shipped (empty pin set).
- [ ] Decision: leave pins empty for Let's Encrypt on `bizarrecrm.com`, or pin to Let's Encrypt intermediates. Document decision in README and toggle per-build-config.
- [ ] Custom-server override (self-hosted tenants): allow user-trusted pins per base URL, stored encrypted in Keychain.

### 1.3 Persistence (GRDB + SQLCipher)
- [~] GRDB wiring exists for some domains; full coverage missing.
- [ ] **Per-domain DAO**: Tickets, Customers, Inventory, Invoices, Estimates, Leads, Appointments, Expenses, SMS threads, SMS messages, Notifications, Employees, Reports cache.
- [ ] **Migrations registry** — numbered migrations, each one idempotent. Tests assert every migration on a fresh DB replica.
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

---

## 2. Authentication & Onboarding

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
- [ ] **Endpoint:** `POST /auth/login/set-password` with `{ challengeToken, password }`.
- [ ] **Frontend:** password + confirm fields, strength meter (length, mixed-case, digit, symbol, not-in-breach-list via local dictionary), CTA disabled until rules pass.
- [ ] **UX:** glass panel titled "Set your password to continue"; subtitle "Your admin requested a reset".

### 2.4 2FA / TOTP
- [ ] **Enroll during login** — `POST /auth/login/2fa-setup` → `{ qr, secret, manualEntry, challengeToken }`. Render QR (CoreImage `CIFilter.qrCodeGenerator`) + copyable secret with `.textSelection(.enabled)`. Detect installed authenticator apps via `otpauth://` URL scheme.
- [ ] **Verify code** — `POST /auth/login/2fa-verify` with `{ challengeToken, code, trustDevice? }` returns `{ accessToken, user }`.
- [ ] **Backup code entry** — `POST /auth/login/2fa-backup` with `{ challengeToken, backupCode }`.
- [ ] **Backup codes display** (post-enroll) — show full list once, copy-all button, "I saved them" confirm. Warn loss = lockout.
- [ ] **Autofill OTP** — `.textContentType(.oneTimeCode)` on the 6-digit field picks up SMS codes from Messages.
- [ ] **Paste-from-clipboard** auto-detect 6-digit string.
- [ ] **Disable 2FA** (Settings → Security) — `POST /auth/account/2fa/disable` with `{ password?, code? }`.

### 2.5 PIN lock
- [ ] **Set PIN** first launch after login — 4–6 digit numeric; `POST /auth/change-pin` with `{ newPin }`; server bcrypts; store hash mirror in Keychain.
- [ ] **Verify PIN** — `POST /auth/verify-pin` with `{ pin }` → `{ verified }`.
- [ ] **Change PIN** — Settings → Security; `POST /auth/change-pin` with `{ currentPin, newPin }`.
- [ ] **Switch user** (shared device) — `POST /auth/switch-user` with `{ pin }` → `{ accessToken, user }`. Expose as "Switch user" row on Settings & long-press on avatar in toolbar.
- [ ] **Lock triggers** — cold start, background for N minutes (Settings: 0/1/5/15/never), explicit "Lock now" action.
- [ ] **Keypad UX** — custom numeric keypad with haptic on each tap, shake + `.error` haptic on wrong PIN, lockout after 5 wrong tries → full re-auth.
- [ ] **Forgot PIN** → "Sign out and re-login" destructive action.
- [ ] **iPad layout** — keypad centered in `.brandGlass` card, not full-width.

### 2.6 Biometric (Face ID / Touch ID / Optic ID)
- [ ] **Info.plist:** `NSFaceIDUsageDescription = "Unlock BizarreCRM with Face ID"`.
- [ ] **Enable toggle** — Settings → Security (availability via `LAContext.canEvaluatePolicy`).
- [ ] **Unlock chain** — bio → fail-3x → PIN → fail-5x → full re-auth.
- [ ] **Login-time biometric** — if "Remember me" + biometric enabled, decrypt stored credentials via `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` and auto-POST `/auth/login`.
- [ ] **Respect disabled biometry** gracefully — never crash, fall back to PIN silently.
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
- [ ] **Refresh-and-retry** on 401 — `POST /auth/refresh` with CSRF (`X-CSRF-Token`) + http-only refresh cookie stored via `HTTPCookieStorage`; queue concurrent calls behind a single in-flight refresh. Only drop to login if refresh itself 401s.
- [ ] **`GET /auth/me`** on cold-start — validates token + loads current role/permissions into `AppState`.
- [ ] **Logout** — `POST /auth/logout`; clear Keychain, GRDB passphrase stays (DB persists across logins).
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

---

## 3. Dashboard & Home

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
- [ ] Dynamic greeting by hour ("Good morning / afternoon / evening, {firstName}").
- [ ] Tap greeting → Settings → Profile.
- [ ] Avatar in top-left (iPhone) / top-right of toolbar (iPad); long-press → Switch user (§2.5).

### 3.10 Sync-status badge
- [ ] Small glass pill on dashboard header: "Synced 2 min ago" / "Pending 3" / "Offline".
- [ ] Tap → Settings → Data → Sync Issues.

### 3.11 Clock in/out tile
- [ ] Visible when timeclock enabled — big tile "Clock in" / "Clock out (since 9:14 AM)".
- [ ] One-tap toggle; PIN prompt if Settings requires it.
- [ ] Success haptic + toast.

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

---

## 4. Tickets (Service Jobs)

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
- [ ] **iPad 3-column split** — sidebar (saved views) + list + detail.
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
- [ ] **Share PDF / AirPrint** — on-device rendering pipeline per §17.4. `WorkOrderTicketView(model:)` → `ImageRenderer` → local PDF; hand file URL (never a web URL) to `UIPrintInteractionController` or share sheet. SMS shares the public tracking link (§55); email attaches the locally-rendered PDF so recipient sees it without login. Fully offline-capable.
- [ ] **Copy link to ticket** — Universal Link `app.bizarrecrm.com/tickets/:id`.
- [ ] **Customer quick actions** — Call (`tel:`), SMS (opens thread), FaceTime, Email, open Customer detail, Create ticket for this customer.
- [ ] **Related** — sidebar (iPad) with Recent tickets from same customer, Photo wallet, Health score, LTV tier (see §42).
- [ ] **Bench timer widget** — small glass card, start/stop (`POST /bench/:ticketId/timer-start`); feeds Live Activity (§24.2).
- [ ] **Handoff banner** (iPad/Mac) — `NSUserActivity` advertising this ticket so a Mac can pick it up.
- [ ] **Deleted-while-viewing** — banner "This ticket was removed. [Close]".
- [ ] **Permission-gated actions** — hide destructive actions when user lacks role.

### 4.3 Create — full-fidelity multi-step
- [~] Minimal create shipped (customer + single device).
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
- [ ] In-place edit on detail: status, assignee, notes, devices, services, prices, deposit, due date, urgency, tags, labels, customer reassign, source.
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
- [ ] **Fetch taxonomy** `GET /settings/statuses` — drives picker; no hardcoded statuses.
- [ ] **Color chip** from server hex.
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

---

## 5. Customers

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
- [ ] **Phone normalize** — use shared `PhoneFormatter` (Core) — mirrors web user-memory rule.
- [ ] **Duplicate detection** — before save, fuzzy match on phone/email; modal "Looks like this might be {name}. Use existing?" with Merge / Cancel / Create anyway.
- [ ] **Import from Contacts** — `CNContactPickerViewController` prefills form.
- [ ] **Barcode/QR scan** — scan customer card (if tenant prints them) for quick-lookup.
- [ ] **Idempotency** + offline temp-ID handling.

### 5.4 Edit
- [ ] All fields editable. `PUT /customers/:id`.
- [ ] Optimistic UI + rollback.
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

---

## 6. Inventory

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
- [ ] **Form**: Name (required), SKU, UPC / barcode, item type (product / part / service), category, cost price, retail price, tax class, stock qty, reorder threshold, reorder qty, supplier, bin, manufacturer, description, photos, tags, taxable flag.
- [ ] **Inline barcode scan** — `DataScannerViewController` to fill SKU/UPC; auto-lookup via `GET /inventory-enrich/barcode-lookup` (external DB). Autofill name/manufacturer/UPC from result.
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

---

## 7. Invoices

_Server endpoints: `GET /invoices`, `GET /invoices/stats`, `GET /invoices/{id}`, `POST /invoices`, `PUT /invoices/{id}`, `POST /invoices/{id}/payments`, `POST /invoices/{id}/void`, `POST /invoices/{id}/credit-note`, `POST /invoices/bulk-action`, `GET /reports/aging`._

### 7.1 List
- [x] Base list + filter chips + search — shipped.
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

## 8. Estimates

_Server endpoints: `GET /estimates`, `GET /estimates/{id}`, `POST /estimates`, `PUT /estimates/{id}`, `POST /estimates/{id}/approve`._

### 8.1 List
- [x] Base list + is-expiring warning — shipped.
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

## 9. Leads

_Server endpoints: `GET /leads`, `POST /leads`, `PUT /leads/{id}`._

### 9.1 List
- [x] Base list — shipped.
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
- [x] Minimal form — shipped.
- [ ] **Extended fields** — score (manual override), source, value, stage, assignee, follow-up date, notes, tags, custom fields.
- [ ] **Offline create** + reconcile.

### 9.5 Lost-reason modal
- [ ] Required dropdown (price / timing / competitor / not-a-fit / other) + free-text.

---

## 10. Appointments & Calendar

_Server endpoints: `GET /appointments`, `POST /appointments`, `PUT /appointments/{id}`, `DELETE /appointments/{id}`, `GET /calendar` (verify)._

### 10.1 List / calendar views
- [x] Base list — shipped.
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

## 11. Expenses

_Server endpoints: `GET /expenses`, `POST /expenses`, `PUT /expenses/{id}`, `DELETE /expenses/{id}`._

### 11.1 List
- [x] Base list + summary header — shipped.
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

## 12. SMS & Communications

_Server endpoints: `GET /sms/unread-count`, `GET /sms/conversations`, `GET /sms/conversations/{id}/messages`, `POST /sms/send`, `GET /inbox`, `POST /inbox/{id}/assign`, `POST /voice/call`, `GET /voice/calls`, `GET /voice/calls/{id}`, `GET /voice/calls/{id}/recording`, `POST /voice/call/{id}/hangup`. WS topic: `sms:received`, `call:started`, `call:ended`._

### 12.1 Thread list
- [x] Threads list — shipped.
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
- [ ] Add PATCH method to `APIClient` (currently missing).
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

## 13. Notifications

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

## 14. Employees & Timeclock

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

## 15. Reports & Analytics

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

---

## 16. POS / Checkout

_Server endpoints: `POST /invoices`, `POST /invoices/{id}/payments`, `POST /blockchyp/*`, `GET /inventory`, `GET /repair-pricing/services`, `GET /tax`, `POST /pos/holds`, `GET /pos/holds`, `POST /pos/returns`, `POST /cash-register/open`, `POST /cash-register/close`, `GET /cash-register/z-report`, `POST /gift-cards/redeem`, `POST /store-credit/redeem`. All require `tenant-id`, role-gated write operations, idempotency keys on payment/charge._

### 16.1 Tab shell
- [!] Currently Phase-0 placeholder — `Pos/PosView.swift` stub. Build first full feature since current version only shows an empty screen with "Coming soon".
- [ ] **Architecture** — PosView → PosViewModel (`@Observable`) → PosRepository → APIClient + GRDB (holds cache + catalog cache).
- [ ] **Tab replaces**: POS tab in iPhone TabView + POS entry in iPad sidebar.
- [ ] **Permission gate** — `pos.access` in user role; if missing, show "Not enabled for this role" card with contact-admin CTA.
- [ ] **Drawer lock** — if cash register not opened for this shift, show blocking sheet "Open register to start selling" with starting balance input (see §16.11).

### 16.2 Catalog browse (left pane)
- [ ] **Layout** — iPhone: full screen with `Back to cart` button; iPad/Mac: left 40% of split view, cart right 60%.
- [ ] **Hierarchy** — top chips: All / Services / Parts / Accessories / Custom. Grid below: category tiles → products.
- [ ] **Product tile** — glass card with photo (Nuke thumbnail), name, price, stock badge (green ≥5, yellow 1–4, red 0). Tap → add qty 1 to cart with haptic success.
- [ ] **Search bar** — sticky top with scan button (`VisionKit.DataScannerViewController`); scan → SKU/UPC match → add to cart → tile pulses.
- [ ] **Long-press tile** — quick-preview sheet (price history, stock, location, last sold date); buttons "Add 1" / "Add qty…".
- [ ] **Recently sold** chip — shows top 10 items sold in last 24h per this register.
- [ ] **Favorites** — star-pin a product; star chip filter.
- [ ] **Custom line** — "+ Custom item" button creates untracked line (name, price, taxable, category) — role-gated.
- [ ] **Offline** — catalog available from GRDB cache; stock count last-synced marker shown on tile corner.
- [ ] **Search filters** — by category, tax status, in-stock only, price range (popover on iPad).
- [ ] **Repair services** — services from `/repair-pricing/services` surface in Services tab; device-type lookup narrows list.

### 16.3 Cart (right pane / bottom sheet)
- [ ] **Glass cart panel** — sticky; iPhone: bottom sheet with `.presentationDetents([.medium, .large])`, iPad: right pane full height.
- [ ] **Header** — sale # (temp until charged), customer chip (tap to change), total in large Barlow Condensed.
- [ ] **Line items** — name, qty stepper, unit price, line total. Swipe-left: delete; swipe-right: edit.
- [ ] **Line edit sheet** — qty, price override (role-gated with PIN challenge), line discount (% or $), note (printed on receipt), tax-exempt toggle.
- [ ] **Cart-level** — discount (% or $), tip (if enabled, preset chips 10/15/20% + custom), fees (delivery, restocking, etc.).
- [ ] **Tax** — auto-calc per tenant tax config (§19 Settings.Tax); multi-rate support (state + county + city).
- [ ] **Totals breakdown** — Subtotal → Discount → Tax → Tip → Grand Total; expandable.
- [ ] **Link to record** — chip "Link to Ticket #1234" opens picker; linked ticket's parts/services auto-import.
- [ ] **Hold cart** — `POST /pos/holds` saves cart for resume later; named hold ("Repair Job #12", "Mrs. Smith #4"); list of holds accessible from toolbar.
- [ ] **Resume hold** — pick from hold list → restores cart state.
- [ ] **Clear cart** — destructive confirm dialog ("Discard X items?").
- [ ] **Empty state** — glass illustration + "Scan a barcode or tap a product".

### 16.4 Customer pick
- [ ] **Attach existing** — search bar with debounced `/customers/search`; tap result to attach; chip shows name + loyalty tier badge.
- [ ] **Create new inline** — "+ New customer" opens sheet with first/last/phone/email; on save returns to cart.
- [ ] **Guest checkout** — no customer; warning if store-credit / loyalty / financing needed.
- [ ] **Customer-specific pricing** — if customer is in a Customer Group with discount override, apply automatically (banner "Group discount applied").
- [ ] **Tax exemption** — if customer has tax-exempt flag, cart removes tax with banner; show exemption cert # if stored.
- [ ] **Loyalty points preview** — "You'll earn XXX points" if loyalty enabled.

### 16.5 Payment — BlockChyp (primary card rail)
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
  - **No photo / screenshot of card.** Camera attachments on payment screens explicitly blocked (blur on background per §158.3).
  - **Same sovereignty rule** — BlockChyp is the single permitted payment peer; no Stripe / Square / PayPal SDK fallbacks anywhere in the bundle.
  - **Offline** — manual-keyed not available offline. Cloud-relay vs local mode same as §17.3: needs outbound path to BlockChyp for the tokenization call. If fully offline, disable manual-keyed option with tooltip "Requires internet to tokenize."
- [ ] **Gift card** — scan / key gift-card #; `POST /gift-cards/redeem` with amount; remaining balance displayed.
- [ ] **Store credit** — auto-offer if customer has balance; slider "Apply X of $Y available".
- [ ] **Check** — check # + bank + memo; no auth, goes to A/R.
- [ ] **Account credit / net-30** — role-gated; only if customer has terms set; adds to open balance.
- [ ] **Financing (if enabled)** — partner link (Affirm/Klarna) → QR/URL for customer to complete on their phone; webhook completes sale.
- [ ] **Split tender** — add tender → shows remaining due → repeat until 0; show running "Paid / Remaining" card.

### 16.7 Receipt & hand-off
- [ ] **On-device rendering pipeline per §17.4.** Same `ReceiptView(model:)` drives preview / thermal / AirPrint / PDF export / email attachment / share sheet. Never hand the printer or share sheet a `https://…/print/…` URL (Android regression — auth wall).
- [ ] **Receipt preview** — same SwiftUI `ReceiptView` rendered live inside a glass card. What you see is what prints.
- [ ] **Thermal print** — `ImageRenderer(content: ReceiptView(...))` → bitmap → ESC/POS raster to MFi printer (§17).
- [ ] **AirPrint** — fallback for non-MFi: same `ReceiptView` rendered to local PDF file URL via `UIGraphicsPDFRenderer`; hand the file URL (not a web URL) to `UIPrintInteractionController`.
- [ ] **Email** — server sends templated email BUT attach the locally-rendered PDF so recipient sees the same artifact regardless of their auth state; plus inline HTML fallback.
- [ ] **SMS** — sends the tracking-page short link for self-service lookups (public, tokenized — not the private print URL). Auth-free page by design (§55).
- [ ] **Download PDF** — `.fileExporter` pointed at locally-rendered PDF; filename `Receipt-{id}-{date}.pdf`.
- [ ] **QR code** — rendered inside `ReceiptView` via `CIFilter.qrCodeGenerator`; encodes public tracking/returns URL (tokenized, no auth required by recipient).
- [ ] **Signature print** — captured `PKDrawing` / `PKCanvasView` image composed into the view, printed as part of the same bitmap.
- [ ] **Gift receipt** — `GiftReceiptView` (price-hidden variant) uses same model.
- [ ] **Persist the render model** — snapshot `ReceiptModel` persisted at sale close so reprints are byte-identical even after template / branding changes.

### 16.8 Post-sale screen
- [ ] **Confetti animation** (short, Reduce-Motion aware) + glass "Sale complete" card.
- [ ] **Summary tile** — sale #, total, tender breakdown, customer name.
- [ ] **Next-action CTAs** — New sale (⌘N) / Return (⌘R) / Print gift receipt / View invoice.
- [ ] **Auto-dismiss** after 10s → empty catalog + cart for next customer.
- [ ] **Cash drawer kick** — pulse drawer via printer ESC command if cash tender used.

### 16.9 Returns / refunds
- [ ] **Entry** — POS toolbar "Return" button → search original sale by # / customer / phone.
- [ ] **Original lookup** — show invoice detail with per-line checkbox + "Qty to return" stepper.
- [ ] **Reason required** — dropdown (defective / wrong item / customer changed mind / warranty / other) + note.
- [ ] **Restock flag** — per line: return to inventory (increment) vs scrap (no increment).
- [ ] **Refund amount** — calc from selected lines - restocking fee (role-gated to waive); editable.
- [ ] **Tender** — original card (BlockChyp refund with token) / cash / store credit / gift card issuance.
- [ ] **Manager PIN** — required above $X threshold (tenant config).
- [ ] **Audit** — `POST /pos/returns` with all fields; audit log entry; notifies original cashier.
- [ ] **Receipt** — "RETURN" printed; refund amount; signature if required.

### 16.10 Cash register (open/close)
- [ ] **Open shift** — starting balance input per denomination (1, 5, 10, 20, 50, 100, coins); total auto-calc; employee PIN; `POST /cash-register/open`.
- [ ] **Mid-shift** — "Cash drop" button (remove excess to safe) with count + signature.
- [ ] **Close shift** — count by denomination → server computes expected from sales + starting - drops; shows over/short with color; require comment if off by > $X.
- [ ] **Z-report** — `GET /cash-register/z-report` → PDF with sales by tender, taxes, tips, refunds, voids, discounts; auto-printed; emailed to manager.
- [ ] **Shift handoff** — outgoing cashier closes → incoming opens fresh; seamless transition.
- [ ] **Blind-count mode** — cashier doesn't see expected total until after count (loss prevention).
- [ ] **Tenant config** — enforce mandatory count vs skip allowed; skip requires manager PIN.

### 16.11 Anti-theft / loss prevention
- [ ] **Void audit** — every voided line logged with cashier + manager-approval name.
- [ ] **No-sale audit** — opening drawer without sale requires reason + manager PIN; event logged.
- [ ] **Discount ceiling** — cashier limit $X / %X; above → manager PIN.
- [ ] **Price override alert** — log every override ≥ threshold.
- [ ] **Delete-line audit** — deleted lines ghosted on Z-report.

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
- [ ] **Magic Keyboard shortcuts** — ⌘F (search), ⌘N (new sale), ⌘R (return), ⌘P (pay), ⌘K (customer pick), ⌘H (hold), ⌘⇧V (void).
- [ ] **Apple Pencil** — tap to add to cart, double-tap for 2, hover for preview on iPad Pro.
- [ ] **Drag items** — drag from catalog to cart with haptic feedback.

### 16.15 Membership / loyalty integration
- [ ] **Member discount** — auto-apply if customer is a member (see §40).
- [ ] **Points earned** — displayed on receipt.
- [ ] **Points redemption** — toggle "Use X points ($Y off)" inline.
- [ ] **Member-only products** — grayed for non-members.

---

## 17. Hardware Integrations

_Requires Info.plist keys (written by `scripts/write-info-plist.sh`): `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, `NSMicrophoneUsageDescription`, `NFCReaderUsageDescription`. MFi accessories need `UISupportedExternalAccessoryProtocols` array._

### 17.1 Camera (photo capture)
- [ ] **Wrapper** — `CameraService` wraps `AVCaptureSession` with torch toggle, pinch-zoom, HEIC/JPEG choice per settings.
- [ ] **Ticket photos** — 0..N per device; multi-shot mode (continue-shooting without dismissing); EXIF strip before upload; auto-orient.
- [ ] **Customer avatar** — single shot with circular crop preview.
- [ ] **Expense receipts** — auto-detect receipt edges (Vision `VNDetectRectanglesRequest`); perspective correct; OCR total via `VNRecognizeTextRequest` pre-fill.
- [ ] **Storage** — temp files in `tmp/photo-capture/`; upload → move to `AppSupport/photos/{entity}/{id}/` on success; delete on failure retry.
- [ ] **Compression** — target ≤ 1.5 MB per photo (HEIC 0.6 / JPEG 0.7); full-res option in settings.
- [ ] **Annotations** — PencilKit overlay (arrows, circles) on ticket photos.
- [ ] **Photos library** — `PhotosPicker` alt path; limited-library mode supported.
- [ ] **Permissions UX** — if denied, glass banner "Enable camera in Settings" deep-links to `UIApplication.openSettingsURLString`.
- [ ] **Mac (Designed for iPad)** — continuity camera via FaceTime-HD → same `AVCaptureSession` code works.
- [ ] **Live text** — press-and-hold on any photo → Live Text (IMEI / serial extraction) → copy/paste into form.

### 17.2 Barcode scan
- [ ] **`DataScannerViewController`** (iOS 16+) with symbologies: `.ean13`, `.ean8`, `.upce`, `.code128`, `.code39`, `.qr`.
- [ ] **Bindings** — Inventory lookup, POS add-to-cart, Stocktake (continuous mode), Ticket device IMEI, Customer (if card has QR).
- [ ] **Torch** button, zoom (pinch), region-of-interest overlay.
- [ ] **Feedback** — haptic success + color flash + chime (muteable per setting).
- [ ] **Multi-scan mode** — POS/stocktake can keep scanning; tap-to-stop.
- [ ] **Offline lookup** — hit local GRDB cache first; if miss + online → server; if miss + offline → toast "Not in local catalog".
- [ ] **Printed/screen code** — both supported.
- [ ] **Fallback manual entry** — keyboard icon to type SKU.
- [ ] **External scanners** — MFi Socket Mobile / Zebra SDK integration; scanner types as HID keyboard fallback.
- [ ] **Mac** — `DataScannerViewController` unavailable on Mac Catalyst; feature-gate to manual entry + continuity camera scan.

### 17.3 Card reader — BlockChyp

**Architecture clarification (confirmed against BlockChyp docs + iOS SDK README, April 2026).** BlockChyp is a **semi-integrated** model with two communication modes the SDK abstracts behind the same API calls. Our app never handles raw card data either way — terminals talk to the payment network directly; we only receive tokens + results. Per-terminal mode is set at provisioning on the BlockChyp dashboard (cloud-relay checkbox).

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
- [ ] **No URL-based printing.** Ban any code path that hands a `print://` / `https://…/print/…` intent to the system. Lint rule: forbid `UIPrintInteractionController.printingItem = URL(...)` unless URL is a file URL of a locally-rendered PDF.
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
- [ ] **Pair** — pick printer → save identifier (serial number) in Settings → per-station profile (§309).
- [ ] **Test print** — Settings "Print test page": renders `TestPageView` locally (logo + shop name + time + printer capability matrix) via the same pipeline.

#### AirPrint path
- [ ] **`UIPrintInteractionController`** with `printingItems: [localPdfURL]` — never a remote URL.
- [ ] **Custom `UIPrintPageRenderer`** for label printers that want page-by-page rendering instead of a PDF (e.g., Dymo via AirPrint).

#### Fallbacks + resilience
- [ ] **No printer configured** — offer email / SMS with PDF attachment + in-app preview (rendered from same model). Works fully offline; delivery queues if needed.
- [ ] **Printer offline** — job queues in `print_queue` GRDB table (model payload + target printer). Retry on reconnect; alert on repeated failure.
- [ ] **Cash-drawer kick** — via printer ESC command; if printer offline, surface "Open drawer manually" button that logs an audit event so shift reconciliation can show drawer-open vs sale counts.
- [ ] **Re-print** — past receipts re-render from stored `ReceiptModel` snapshot (persisted at the time of sale). Guarantees byte-identical reprint even after tenant branding / template changes.

#### Templates (the views)
- [ ] Receipt, gift receipt (price-hidden variant), work-order ticket label (name + ticket # + barcode), intake form (pre-conditions + signature), A/R statement, end-of-day Z-report, label/shelf tag (§114).

#### ESC/POS builder
- [ ] Helpers for bold / large / centered / QR / barcode / cut / feed / drawer-kick — used only for command sequences around the rasterized bitmap, never to draw text piecewise (text comes from SwiftUI render).

#### Multi-location
- [ ] Per-location default printer selection + per-station profile (§309).

#### Acceptance criterion (copied from lesson)
- [ ] Ship with a regression test: log out of the app, attempt to print a cached recent receipt (detail opened while online, then session ended) → printer must still produce correct output, because rendering is fully local and only the device-to-printer transport is needed.

### 17.5 NFC

**Parity check (2026-04-20).** Server (`packages/server/src/`), web (`packages/web/src/`) and Android (`packages/android/`) have **zero** NFC implementation today. No `nfc_tag_id` column, no `/nfc/*` routes, no Android `NfcAdapter` usage. Building it in iOS first would create a feature that only works when an iPhone reads it, with nowhere on the server to store it and no way for web / Android to consume it. **Do not implement until cross-platform parity lands.** Cross-platform item tracked in root `TODO.md` as `NFC-PARITY-001`.

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
- [ ] **Apple Wallet pass** — customer loyalty card (see §40, §117, §321) added via `PKAddPassesViewController`. This is `PassKit`, not `CoreNFC`. Works today.

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

### 17.9 Apple Watch companion — MOVED TO ROOT TODO

Not an iOS feature per se; separate product surface (own entitlements, TestFlight lane, App Store binary, review cycle). Tracked as `WATCH-COMPANION-001` in root `TODO.md` pending scope decision. iOS work on this section is blocked until that item resolves.

Candidate scope when revisited (for reference): clock in / out complication, new-ticket / SMS push forwarding, reply-by-dictation. Non-goal: full CRM browsing on watch. See also §154 / §297 (merged).

### 17.10 Accessibility hardware
- [ ] **Switch Control** — POS primary actions reachable.
- [ ] **Voice Control** — all named buttons reachable; custom names for numeric keys.

---

## 18. Search (Global + Scoped)

_Server endpoints: `GET /search?q=&type=&limit=`, `GET /customers?q=`, `GET /tickets?q=`, `GET /inventory?q=`, `GET /invoices?q=`, `GET /sms?q=`._

### 18.1 Global search (cross-domain)
- [x] **Shipped** — cross-domain search across customers / tickets / inventory / invoices.
- [ ] **Trigger** — glass magnifier chip in toolbar (all screens) + pull-down on Dashboard + ⌘F.
- [ ] **Command Palette** — see §58; distinct from global search (actions vs data).
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

---

## 19. Settings

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
- [ ] **Sign-out-everywhere** — in Security, but cross-linked here.
- [ ] **Username / slug** — read-only unless admin.

### 19.2 Security
- [ ] **PIN** — 6-digit PIN for quick re-auth (locally enforced).
- [ ] **Biometric toggle** — Face ID / Touch ID for re-auth + sensitive screen gates.
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
- [ ] **Device templates** (see §50) — managed here.

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
- [x] **Dynamic base URL** — shipped.
- [ ] **Switch tenant** — multi-tenant users choose active tenant; token re-issued per tenant.
- [ ] **Connection test** — latency (ping) + auth check + TLS cert SHA shown.
- [ ] **Pinning** — SPKI pin fingerprint viewer + rotate.

### 19.23 Data (local)
- [ ] **Force full sync** — wipes GRDB, re-fetches all domains.
- [ ] **Sync queue inspector** — pending writes + retry age + dead-letter (tap to retry / drop).
- [ ] **Clear cache** — images + catalog (not queued writes).
- [ ] **Reset GRDB** — nuclear option (sign out + wipe).
- [ ] **Disk usage** — breakdown: images X MB, GRDB Y MB, logs Z MB.
- [ ] **Export DB** (dev build only) — share sheet → `.sqlite` file.

### 19.24 About
- [ ] **Version + build + commit SHA** (from `GitVersion`).
- [ ] **Licenses** — `NSAcknowledgments` auto-generated.
- [ ] **Privacy policy**, **Terms of Service**, **Support email** — deep links.
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
- [ ] **Toggle** — "Training mode" → read-only sandbox against demo data; watermark banner; no SMS/card charges fire.

---

## 20. Offline, Sync & Caching

### 20.1 Read-through cache architecture
- [ ] **Every read** lands in a GRDB table; SwiftUI views observe GRDB via `@FetchRequest` equivalent (`ValueObservation`).
- [ ] **Repository pattern** — `TicketRepository.observeList(filters:)` emits from GRDB; `sync()` refreshes from server.
- [ ] **Read strategies** — `networkOnly` (force) / `cacheOnly` (offline) / `cacheFirst` (default) / `cacheThenNetwork` (stale-while-revalidate).
- [ ] **TTL per domain** — tickets 30s, inventory 60s, customers 5min, reports 2min, settings 10min.
- [ ] **Staleness indicator** — glass chip on top right of list: "Updated 3 min ago".

### 20.2 Write queue architecture
- [ ] **`sync_queue` table** — columns: `id, op, entity, entity_id_local, entity_id_server, payload_json, idempotency_key, status, retry_count, last_error, created_at, next_retry_at`.
- [ ] **Ops** — `create`, `update`, `patch`, `delete`, `upload_photo`, `charge`.
- [ ] **Optimistic write** — insert into local table with temp UUID + `pending=true`; view shows immediately.
- [ ] **Drain loop** — Combine-based `SyncService.drainLoop()` triggered on: connectivity restored, app foreground, 30s idle tick, manual sync.
- [ ] **Idempotency keys** — UUID per mutation; server dedupes same key.
- [ ] **Per-entity ordering** — sequential drain per entity to maintain invariants; parallel across entities.
- [ ] **Exponential backoff** — 1s → 2s → 4s → 8s → 16s → 32s → 60s cap; jitter ±10%.
- [ ] **Dead-letter** — after 10 failures, move to dead-letter table; surface in Settings → Diagnostics as "Failed syncs".
- [ ] **Manual retry** — user taps failed item → retry or discard.

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
- [ ] **Per-parent sub-lists use the same contract.** Ticket history timeline (§85.6), ticket notes + photos, customer notes (§261), customer timeline, SMS thread messages (§6 / §12), inventory movement history (§6.2), audit log (§52), activity feed (§242), team-chat messages (§47) — all follow the cursor / `sync_state` pattern, scoped per-parent. Each gets its own `<entity>_sync_state` row keyed by `(parent_type, parent_id, filter?)`. Never client-side slices, never `total_pages`.

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
- [ ] **LRU images** — Nuke's disk cache with size cap 500 MB; auto-evict least-recent.
- [ ] **GRDB VACUUM** — monthly on-launch background task.
- [ ] **Size monitoring** — warn user when cache > 2 GB.

### 20.10 Multi-device consistency
- [ ] **Per-device-id** on mutations so server echoes back correct events.
- [ ] **WS echo** — if user has iPad + iPhone, update on other device via WS.

---

## 21. Background, Push, & Real-Time

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

### 21.9 Quiet hours
- [ ] **Client-side quiet hours** — suppress notifications in user-set window (local only, server still sends).
- [ ] **Critical overrides** — allowlist bypass (payment failed / @mention).

---

## 22. iPad-Specific Polish

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

---

## 23. Mac ("Designed for iPad") Polish

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
- [ ] BlockChyp terminal — LAN-paired works; BT-paired may not.

---

## 24. Widgets, Live Activities, App Intents, Siri, Shortcuts

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

---

## 25. Spotlight, Handoff, Universal Clipboard, Share Sheet

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
- [ ] **Public tracking link** — share short URL to public-tracking page (see §59).
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

### 25.7 Universal Links (`app.bizarrecrm.com`)
- [ ] **AASA file** hosted on server with path patterns `/c/*`, `/t/*`, `/i/*`, `/estimates/*`, `/receipts/*`.
- [ ] **Applinks** entitlement + associated-domains.
- [ ] **Route handler** — `onContinueUserActivity(.browsingWeb)` extracts path → navigate.
- [ ] **Login gate** — unauth user stores intent, signs in, restores.
- [ ] **Fallback** — Universal Link that fails to open app shows web page instead.

### 25.8 Custom URL scheme (`bizarrecrm://`)
- [ ] **Registered** in Info.plist.
- [ ] **Routes** — `bizarrecrm://tickets/123`, `bizarrecrm://pos`, `bizarrecrm://sms/456`.
- [ ] **Used by** — Shortcuts, App Intents, push-notification deep-links.

---

## 26. Accessibility

_Baseline: `Accessibility Inspector` Audit passes on every screen. Run before PR merge._

### 26.1 VoiceOver
- [ ] **Label + hint** on every interactive element — `.accessibilityLabel("Ticket 1234, iPhone repair")`, `.accessibilityHint("Double tap to open")`.
- [ ] **Traits** — `.isButton`, `.isHeader`, `.isSelected`, `.isLink`.
- [ ] **Rotor support** — on long lists: heading / form control / link rotors work.
- [ ] **Grouping** — `.accessibilityElement(children: .combine)` on compound rows so VoiceOver reads one meaningful line.
- [ ] **Container** — `.accessibilityElement(children: .contain)` wraps list for navigation.
- [ ] **Announcement** — `.announcement` posted on async success/failure ("Ticket created").
- [ ] **Focus** — `@AccessibilityFocusState` moves focus to key element on sheet open.
- [ ] **Custom actions** — swipe actions exposed as accessibility custom actions.
- [ ] **Image descriptions** — customer avatars use initials; ticket photos labeled "Photo N of M on ticket X".

### 26.2 Dynamic Type
- [ ] **Support up through XXXL** (AX5 extra-large); test with `environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)`.
- [ ] **No truncation** on any primary heading — use `.lineLimit(nil)` + ScrollView fallback.
- [ ] **Tabular layouts** switch to vertical stacks at large sizes (`ViewThatFits`).
- [ ] **Icons scale** via `.imageScale(.medium)` and SF Symbols.

### 26.3 Reduce Motion
- [ ] `.accessibilityReduceMotion` gate — swap spring animations for cross-fades.
- [ ] **Cart confetti** → static checkmark.
- [ ] **Parallax on Dashboard** → disable.
- [ ] **Auto-playing animations** → paused until tap.

### 26.4 Reduce Transparency
- [ ] `.accessibilityReduceTransparency` gate — `.brandGlass` returns solid `bizarreSurfaceBase` with 0.98 opacity.
- [ ] **Dark mode solid** — a11y color replaces translucent.

### 26.5 Increase Contrast
- [ ] `.colorSchemeContrast` → `.increased` uses high-contrast brand palette.
- [ ] **Borders** around cards become visible (1pt solid stroke).
- [ ] **Button states** clearer (solid vs outlined).

### 26.6 Bold Text + Differentiate Without Color
- [ ] **Bold Text** — SF-family renders bold; test every screen.
- [ ] **Status pills** — glyph + color (🔴 Overdue / 🟢 Paid / etc.); never color-only.
- [ ] **Charts** — dashed / dotted patterns in addition to color.

### 26.7 Tap targets
- [ ] **Min 44×44pt** — enforced via debug-build assertion in a `.tappableFrame()` ViewModifier that reads the rendered frame from `GeometryReader` and `assert(size.width >= 44 && size.height >= 44)`. CI snapshot test + SwiftLint rule bans bare `.onTapGesture` on non-standard controls so every tappable goes through the checked modifier. No runtime overlay; violations trip at dev time or in CI, never in production UI.
- [ ] **Spacing** between adjacent tappable rows ≥ 8pt (same enforcement: lint rule + snapshot geometry check).

### 26.8 Voice Control
- [ ] **`.accessibilityInputLabels([])`** — alt names for each action ("new" for "Create ticket").
- [ ] **Show numbers overlay** mode — every tappable has a number label.
- [ ] **Custom command phrases** documented in Help.

### 26.9 Switch Control
- [ ] **Nav order** — every screen tested with external switch.
- [ ] **Point mode** works at all scales.

### 26.10 Captions / transcripts
- [ ] **In-app video tutorials** (future) — captions + transcripts bundled.
- [ ] **Voice messages** (SMS) — autogenerated transcript via `Speech` framework.

### 26.11 Guided Access / Assistive Access
- [ ] **Compatible** — no absolute fullscreen-only prompts.
- [ ] **Apple Intelligence Assistive Access** profile — simplified single-task mode (POS-only / Timeclock-only mode).

### 26.12 Accessibility audit
- [ ] **Xcode Accessibility Inspector** audit per screen.
- [ ] **Automated UI tests** assert labels on primary actions.

---

## 27. Internationalization & Localization

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

---

## 28. Security & Privacy

### 28.1 Secrets storage
- [ ] **Keychain** — access tokens, refresh tokens, PIN hash, DB passphrase, BlockChyp API key, 2FA backup codes, printer/terminal identifiers. Class `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- [ ] **Service naming** — `com.bizarrecrm.<purpose>` pattern; access group shared with widget extension where needed.
- [ ] **UserDefaults** — non-secret prefs only (theme, sort order, last-used tab).
- [ ] **App Group UserDefaults** — shared prefs between app + widgets (no secrets).
- [ ] **Delete on logout** — Keychain keys scoped to user/tenant deleted.

### 28.2 Database encryption
- [ ] **SQLCipher** — full DB encrypted at rest; passphrase derived from Keychain-stored random 32-byte key.
- [ ] **Encrypted attachments** — photos stored in AppSupport encrypted via `Data Protection` class B (accessible after first unlock).
- [ ] **Full-wipe utility** — Settings → Danger → Reset wipes DB + Keychain + photos.

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
- [ ] `NSBluetoothAlwaysUsageDescription` — "Connect to receipt printer, card reader, barcode scanner."
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
- [ ] **Privacy snapshot** — blur view placed on `willResignActive` if Security toggle on.
- [ ] **Screen-capture blur** — `UIScreen.capturedDidChange` notification on 2FA/card-entry screens → full-screen blur overlay.
- [ ] **Screenshot detection** — warn user on receipt screens (optional).
- [ ] **Screen record prevention** — `UIWindow.isSecure` on sensitive forms (iOS 17+).

### 28.9 Pasteboard hygiene
- [ ] **OTP paste** — `UITextContentType.oneTimeCode` for seamless auto-fill.
- [ ] **Sensitive copies** — card #, OTP copied with `UIPasteboard.setItems(…, options: [.expirationDate: 60])`.
- [ ] **Generic copies** — no expiration on ticket IDs etc.

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

---

## 29. Performance Budget

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
- [ ] **Nuke** image pipeline — shared across screens.
- [ ] **Memory cache** 50 MB; **disk cache** 500 MB (configurable cap 100–2000 MB).
- [ ] **Prefetch** next 10 rows on scroll.
- [ ] **Thumbnail vs full** — rows use thumb; detail uses full.
- [ ] **Progressive JPEG** decode.
- [ ] **Placeholder** — SF Symbol + brand tint on load.
- [ ] **Failure** — branded SF Symbol + retry tap.

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

---

## 30. Design System & Motion

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
- [ ] **Display** — Barlow Condensed SemiBold (headings, big numbers).
- [ ] **Body** — Inter (regular + medium + semibold).
- [ ] **Mono** — JetBrains Mono (IDs, SKUs, codes, diagnostics).
- [ ] **Scale** — xs / sm / body / lg / xl / 2xl / 3xl / 4xl / display.
- [ ] **Dynamic Type** — each scale keyed off a `Font.TextStyle` so system scaling honors.
- [ ] **Fallback** — if fonts missing (fetch-fonts.sh not run), use SF Pro + log warning.

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

### 30.12 Dark mode first
- [ ] **Dark as default** — `bizarreSurfaceBase` dark.
- [ ] **Light mode** fully supported + tested.
- [ ] **Auto-switch** follows system; manual override in Settings.

### 30.13 Storybook / catalog view
- [ ] **`#if DEBUG` catalog screen** — every component rendered with variants for visual regression.

---

## 31. Testing Strategy

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

---

## 32. Telemetry, Crash, Logging

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
- [ ] **Subsystem** `com.bizarrecrm` with categories: `api`, `sync`, `db`, `auth`, `ws`, `ui`, `pos`, `printer`, `terminal`, `bg`.
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

### 32.6 PII redaction
- [ ] **Never log** phone / email / token / card / IMEI verbatim.
- [ ] **Hash for correlation** — SHA-256 truncated to 8 chars.
- [ ] **Allowlist** — only known-safe fields in events.

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

---

## 33. CI / Release / TestFlight / App Store

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

---

## 34. Known Risks & Blockers

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

---

## 35. Parity Matrix (at-a-glance)

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

## 36. Setup Wizard (first-run tenant onboarding)

_When an admin creates a tenant (or logs in to an empty tenant), run a 13-step wizard. Mirrors web wizard. Server endpoints: `GET /setup/status`, `POST /setup/step/{n}`, `POST /setup/complete`._

### 36.1 Shell
- [ ] **Sheet modal** — full-screen on iPhone, centered glass card on iPad; cannot dismiss until finished or "Do later".
- [ ] **Step indicator** — 13 dots + progress bar; glass chip on top.
- [ ] **Skip any** button → resume later in Settings.

### 36.2 Steps
- [ ] **1. Welcome** — brand hero + value props.
- [ ] **2. Company info** — name, address, phone, website, EIN.
- [ ] **3. Logo** — camera/library upload.
- [ ] **4. Timezone + currency + locale**.
- [ ] **5. Business hours** — per day.
- [ ] **6. Tax setup** — add first tax rate.
- [ ] **7. Payment methods** — enable cash, card (BlockChyp link), etc.
- [ ] **8. First location** — if multi-location tenant.
- [ ] **9. Invite teammates** — email list + role per.
- [ ] **10. SMS setup** — provider pick + from-number + templates.
- [ ] **11. Device templates** — pick from preset library (iPhone family, Samsung, iPad, etc.).
- [ ] **12. Import data** — offer CSV / RepairDesk / Shopr / Skip.
- [ ] **13. Done** — confetti + "Open Dashboard".

### 36.3 Persistence
- [ ] **Resume mid-wizard** — partial state saved server-side; iOS shows "Continue setup" CTA on Dashboard.
- [ ] **Skip all** — admin can defer; gentle nudge banner on Dashboard until complete.

---

## 37. Marketing & Growth

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

---

## 38. Memberships / Loyalty

_Server: `GET/POST/PUT /memberships`, `GET /memberships/{id}`, `POST /memberships/{id}/renew`, `GET /memberships/{id}/points`, `POST /memberships/{id}/points/redeem`._

### 38.1 Tiers
- [ ] **Configure tiers** in Settings (§19.12).
- [ ] **Auto-tier** — customer promoted on $-threshold.
- [ ] **Member badge** on customer chips / POS.

### 38.2 Points
- [ ] **Earn** — points on paid invoice (configurable rate).
- [ ] **Redeem** — at POS (see §16.15).
- [ ] **Expiration** — configurable.
- [ ] **Point history** — per customer.

### 38.3 Subscription memberships
- [ ] **Paid plans** — monthly / annual with auto-renew.
- [ ] **Benefits** — discount %, free services (e.g., 1 battery test / month).
- [ ] **Payment** — BlockChyp recurring or Stripe.
- [ ] **Cancel / pause / resume**.

### 38.4 Apple Wallet pass
- [ ] **`PKAddPassesViewController`** — issue member card as Apple Wallet pass.
- [ ] **Pass updates** — push via pass server (tenant server).
- [ ] **Barcode on pass** — scannable at POS.

### 38.5 Member-only perks
- [ ] **Exclusive products** — hidden in catalog for non-members.
- [ ] **Priority queue** — badge in intake flow.

---

## 39. Cash Register & Z-Report

See §16.10 for core flow. Additional items:

### 39.1 Shift log
- [ ] **Per-shift entry** — cashier, start time, start cash, sales, drops, end cash, over/short.
- [ ] **Shift history** — list of past shifts; open any for detail.
- [ ] **Shift diff viewer** — visualize expected vs actual.

### 39.2 Z-report PDF
- [ ] **Auto-generate** on close; downloadable.
- [ ] **Emailed** to manager.
- [ ] **Auto-archive** in tenant storage.
- [ ] **Data** — sales / tenders / refunds / voids / discounts / tips / taxes / over-short / cashier / printer-log.

### 39.3 X-report (mid-shift)
- [ ] **`GET /cash-register/x-report`** — peek current shift without closing.

### 39.4 Reconciliation export
- [ ] CSV per day of all transactions + tender splits.

---

## 40. Gift Cards / Store Credit / Refunds

### 40.1 Gift cards
- [ ] **Server**: `GET/POST /gift-cards`, `POST /gift-cards/{id}/sell`, `POST /gift-cards/{id}/redeem`, `POST /gift-cards/{id}/void`.
- [ ] **Sell** — at POS; physical card scan OR generate virtual (SMS/email with QR).
- [ ] **Redeem** — scan / key code at POS.
- [ ] **Balance check** — scan → show remaining.
- [ ] **Reload** — add more funds.
- [ ] **Expiration** per tenant policy.
- [ ] **Transfer** — from one card to another.
- [ ] **Refund to gift card** — if original tender was gift card.

### 40.2 Store credit
- [ ] **Server**: `GET/POST /store-credit`, `POST /store-credit/redeem`.
- [ ] **Issued** on returns / apologies / promos.
- [ ] **Balance visible** on customer detail.
- [ ] **Redeem** at POS with toggle.
- [ ] **Expiration** configurable.

### 40.3 Refunds (see §16.9)
- [ ] Already detailed.

### 40.4 Approval workflow
- [ ] **Manager PIN** required on gift-card void / large refund.
- [ ] **Audit trail** — every issuance / void / redeem logged.

---

## 41. Payment Links & Public Pay Page

### 41.1 Generate payment link
- [ ] **From invoice / estimate** — "Send Pay Link" → SMS / email.
- [ ] **Server**: `POST /payment-links` → `{ url: https://app.../pay/abc }`.
- [ ] **QR** — show QR for in-person scan.

### 41.2 Public pay page (tracked by iOS)
- [ ] **Webview preview** — admin can see what customer sees.
- [ ] **Open external** — `SFSafariViewController` with receipt-after-payment hook.

### 41.3 Webhooks
- [ ] On payment complete, server pushes WS event → invoice updates in-app in real time.

---

## 42. Voice & Calls

### 42.1 Call log (if server tracks)
- [ ] **Server**: `GET /calls`, `POST /calls/:id/transcript`.
- [ ] **List** — inbound/outbound calls with customer match.
- [ ] **Recording playback** — audio file streamed.
- [ ] **Transcription** — `Speech` framework locally OR server Whisper.
- [ ] **Search transcripts**.

### 42.2 Outbound call (from app)
- [ ] **Tap phone number** — system call placed; log recorded.
- [ ] **Click-to-call on customer / ticket detail**.

### 42.3 CallKit integration
- [ ] **Inbound VoIP** — CallKit card shows customer name / photo / recent ticket.
- [ ] **Outbound recent calls** appear in native Phone app.

### 42.4 PushKit (VoIP push)
- [ ] **Server pushes VoIP** → iOS wakes app → CallKit invocation.
- [ ] **Required entitlement**.

### 42.5 Voicemail
- [ ] **List + playback** — `AVPlayer`.
- [ ] **Transcription**.
- [ ] **Mark heard / delete / forward**.

---

## 43. Bench Workflow (technician-focused)

_Technician-focused view that collapses cross-cutting actions into one screen._

### 43.1 Bench board
- [ ] **Kanban** — tickets by status (Intake / Diagnosing / Waiting Part / Fixing / Ready / Picked-up).
- [ ] **Drag between columns** — updates status + notifies customer.
- [ ] **Color coding** by urgency / SLA.

### 43.2 Tech-only view
- [ ] **My tickets today** — assigned to me, sort by due.
- [ ] **Timer per ticket** — start/stop time-on-ticket (billable).
- [ ] **Notes** — voice-to-text quick add.

### 43.3 Parts reservation
- [ ] **Reserve parts** — decrement stock on "start work".
- [ ] **Release** on cancel.

### 43.4 Intake flow shortcut
- [ ] **Fast-intake mode** — phone number → new ticket with device-template wizard.
- [ ] **Customer signature** on intake form (PKCanvasView).

### 43.5 Completion checklist
- [ ] Device tested? Charging port? Photos? Customer called?
- [ ] Lock status to Ready until all checked.

### 43.6 Tech metrics
- [ ] **Daily summary** — tickets done, avg time, idle time.

---

## 44. Device Templates / Repair-Pricing Catalog

_Server: `GET /device-templates`, `POST /device-templates`, `GET /repair-pricing/services`._

### 44.1 Catalog browser
- [ ] **Device family** — Apple / Samsung / Google / etc.
- [ ] **Model list** per family with thumbnail.
- [ ] **Service list** per model with default price + part SKU.

### 44.2 Template selection at intake
- [ ] **Device picker** → fills IMEI pattern / conditions list / service presets.

### 44.3 Price overrides
- [ ] **Per-tenant price** — override service default.
- [ ] **Per-customer override** — VIP pricing.

### 44.4 Part mapping
- [ ] **SKU picker** for each service.
- [ ] **Multi-part bundles** — e.g., screen + battery + adhesive.

### 44.5 Add/edit templates (admin)
- [ ] **Full editor** — model, year, conditions, services, default prices.

---

## 45. CRM Health Score & LTV

### 45.1 Health score
- [ ] **Per-customer** 0–100 based on: last visit, total spend, NPS, open issues, complaint count.
- [ ] **Color tier** — Green / Yellow / Red.
- [ ] **Action recommendations** — "Haven't seen in 180 days — send follow-up".

### 45.2 LTV
- [ ] **Lifetime value** computed server-side; displayed on customer chip.
- [ ] **Tier** — Bronze / Silver / Gold / Platinum by LTV threshold.
- [ ] **Perks per tier** — auto discounts, priority queue.

### 45.3 Predicted churn
- [ ] **ML score** (server) — probability of not returning.
- [ ] **Proactive campaign** — auto-target red-health customers.

---

## 46. Warranty & Device History Lookup

### 46.1 Warranty lookup
- [ ] **Scan IMEI / serial / phone** → returns device history + warranty status.
- [ ] **Server**: `GET /devices/lookup?serial=` or `?imei=`.
- [ ] **Visual timeline** — all past tickets on that device.
- [ ] **Warranty ticker** — "Warranty expires in 17 days".

### 46.2 Under-warranty ticket creation
- [ ] **Auto-flag ticket** as warranty-claim → zero-cost service; tracked separately.
- [ ] **Claim submission** — if tenant has partner warranty portal, generate claim.

### 46.3 Device profile page
- [ ] **Per-device** — model, IMEI, purchase date, current owner, past issues, warranty.
- [ ] **Transfer ownership** between customers.

---

## 47. Team Collaboration (internal messaging)

### 47.1 Internal chat
- [ ] **Per-tenant team chat** — `/team-chat/threads`, `/team-chat/{id}/messages` via WS.
- [ ] **Channels** — General / Parts / Techs / Managers.
- [ ] **DMs** — between employees.
- [ ] **@mention** anyone; push notification.
- [ ] **File upload** — images / PDFs.
- [ ] **Pin message**.

### 47.2 Staff shout-outs
- [ ] **"Shout out @Alex for closing tough ticket"** → visible on Dashboard feed.
- [ ] **Like / reply**.

### 47.3 Shift swaps
- [ ] **Request swap** — post to channel + auto-matches by role.
- [ ] **Approval**.

### 47.4 Tasks
- [ ] **Assign task to teammate** with due date, link to ticket/customer.
- [ ] **Task list** per user; badge on tab.
- [ ] **Recurring tasks** (daily opening checklist, weekly deep-clean).

### 47.5 Rooms (from §205)
- `#general` per location.
- `#managers` (admins only).
- `#tech` (technicians).
- `#announcements` (broadcast-only by managers).
- DMs between any two users.

### 47.6 Message types (from §205)
- Text + emoji reactions.
- Photo (camera / library).
- Voice memo (§112).
- File attachments (PDF, CSV) up to 25MB.
- Shared ticket / customer / invoice cards (rich preview).

### 47.7 @mentions (from §205)
- Triggers push (`.timeSensitive` interruption if user online).
- Mentions grouped in dedicated notification category.

### 47.8 Threading & search (from §205)
- Reply threading (nested under parent).
- FTS over messages + attachments filenames.
- Read receipts optional per user; default on.
- Pin important announcements at top of room.

### 47.9 Presence (from §205)
- Online / idle / offline inferred from app state; optional "Busy with customer" status.

### 47.10 Moderation (from §205)
- Admins can delete any message; user can delete / edit own within 5min.
- Edit shows "edited" tag.
- Delete creates audit entry with original content (manager-viewable).

### 47.11 E2E vs tenant-server (from §205)
- Server-side encrypted at rest; not E2E (tenant owner must be able to export history for legal).
- Sovereignty: tenant server only.

### 47.12 Layouts (from §205)
- iPad: 3-column (rooms / thread list / message pane).
- iPhone: tabbed (rooms tab / thread view).

### 47.13 Keyboard shortcuts (from §205)
- ⌘/ jump to room, ⌘K quick switcher, ⌘↑ / ↓ navigate rooms.

---

## 48. Goals, Performance Reviews & Time Off

### 48.1 Goals
- [ ] **Sales goals** — monthly revenue target per employee / location.
- [ ] **Visual progress** — ring on dashboard.
- [ ] **Achievement toast** on hit.

### 48.2 Performance reviews
- [ ] **Manager writes review** — rating + comments + goals.
- [ ] **Employee acknowledges** — signature.
- [ ] **Archive**.

### 48.3 Time off
- [ ] **Request PTO** — date range + reason.
- [ ] **Manager approve/deny** — notifies.
- [ ] **Calendar view** of team PTO.
- [ ] **Balance** — vacation / sick accrual.

---

## 49. Roles Matrix Editor

See §19.14 for settings entry. Deep features:

### 49.1 Matrix UI
- [ ] **iPad** — full matrix; rows=roles, cols=capabilities; toggle cells.
- [ ] **iPhone** — per-role detail view.

### 49.2 Granular caps
- [ ] **~80 capabilities** — each action on each entity.
- [ ] **Presets** — Admin / Manager / Technician / Cashier / Viewer / Training.
- [ ] **Custom role** — clone + modify.

### 49.3 Preview before save
- [ ] **"As this role"** preview mode — admin previews UI as different role.

### 49.4 Audit
- [ ] **Every role change logged** — who, what, when.

### 49.5 Capabilities (fine-grained, from §206)
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

### 49.6 Preset roles (from §206)
- **Owner** — all.
- **Manager** — all except tenant.delete / billing / data.wipe.
- **Shift supervisor** — daily ops, no settings.
- **Technician** — tickets (own + any assigned), inventory adjust (parts only), SMS read + send to own tickets.
- **Cashier** — POS + customers, SMS read-only, tickets view.
- **Receptionist** — appointments + customers + SMS + tickets create.
- **Accountant** — reports + invoices + exports; no POS.

### 49.7 Enforcement (from §206)
- Server authoritative.
- Client hides disallowed UI + disables actions (double defense).

### 49.8 Elevation (from §206)
- Temporary elevation via manager PIN grants next-action scope.
- Example: cashier can refund only with manager PIN pop-over.

### 49.9 Revocation (from §206)
- Immediate.
- Server pushes silent notification to active sessions to refresh capabilities.

---

## 50. Data Import (RepairDesk / Shopr / MRA / CSV)

### 50.1 Import wizard
- [ ] **Source picker** — RepairDesk / Shopr / MRA / Generic CSV / Apple Numbers file.
- [ ] **Upload file** — via share sheet or document picker; iOS 17 Files integration.
- [ ] **Field mapping** — auto-detect + manual correction; save mapping for later.

### 50.2 Dry-run
- [ ] **Preview** first 10 rows — what will import, what will fail.
- [ ] **Error report** — downloadable.

### 50.3 Execute import
- [ ] **Chunked** — 100 rows at a time with progress bar.
- [ ] **Background task** — can leave screen; Live Activity shows progress.
- [ ] **Pause / resume / cancel**.

### 50.4 Import history + rollback
- [ ] **Undo** — within 24h; restores pre-import state.
- [ ] **Log** — per-batch audit.

### 50.5 Recurring import (auto-sync)
- [ ] **Schedule** — daily CSV from S3/Dropbox/iCloud.
- [ ] **On-change webhook**.

---

## 51. Data Export

### 51.1 Full tenant export
- [ ] **Trigger** — Settings → Danger → "Export all data".
- [ ] **Bundle** — JSON + CSV + photos zip; encrypted with tenant passphrase.
- [ ] **Email / iCloud / share sheet** — delivery options.
- [ ] **Progress** — Live Activity.

### 51.2 Per-domain export
- [ ] **From list views** — export filtered results as CSV.

### 51.3 GDPR / CCPA individual export
- [ ] **Per-customer data package** — download all linked records.

### 51.4 Scheduled recurring
- [ ] **Daily to S3 / Dropbox / iCloud Drive** — tenant-configured.

---

## 52. Audit Logs Viewer

### 52.1 List
- [ ] **Server**: `GET /audit-logs?actor=&action=&entity=&since=&until=`.
- [ ] **Columns** — when / actor / action / entity / diff.
- [ ] **Expandable row** — shows full JSON diff.

### 52.2 Filters
- [ ] **Actor, action, entity, date range**.
- [ ] **Saved filters** as chips.
- [ ] Free-text search across data_diff via FTS5.
- [ ] Chips: "Last 24h", "This week", "Custom".

### 52.3 Export
- [ ] **CSV / JSON / PDF for period**.
- [ ] PDF formatted for court evidence: header + footer + page numbers + signature page.

### 52.4 Alerts
- [ ] **Sensitive action** (role change, bulk delete) → admin push.

### 52.5 Scope (from §241)
- Every write operation logged: who, when, what, before/after.
- Reads logged optionally (sensitive screens only).

### 52.6 Entry rendering (from §241)
- Before/after diff visually (red/green).
- Actor avatar + role + device fingerprint.
- Tap → navigate to affected entity (if exists).

### 52.7 Integrity (from §241)
- Entries immutable (server enforced).
- SHA chain: each entry includes hash of previous → tamper-evident.
- iOS verifies chain on export; flags tampered period.

### 52.8 Retention (from §241)
- Tenant policy: 1yr / 3yr / 7yr / forever.
- Auto-archive to cold storage beyond hot window.

### 52.9 Access control (from §241)
- Owner / compliance role only.
- Viewing logged (meta-audit).

### 52.10 Offline (from §241)
- Cached last 90d locally.
- Older pulled on demand.

---

## 53. Training Mode (sandbox)

### 53.1 Toggle
- [ ] **Settings → Training Mode** — switches to demo tenant with seeded data.
- [ ] **Watermark banner** — "Training mode — no real charges, no real SMS".

### 53.2 Reset
- [ ] **"Reset demo data"** — wipes + reseeds.

### 53.3 Guided tutorials
- [ ] **Overlay hints** — "Tap here to create a ticket".
- [ ] **Checklist** — tutorials by topic (POS basics, ticket intake, invoicing).

### 53.4 Onboarding video library
- [ ] **Video tiles** embedded; captions; transcripts.

---

## 54. Command Palette (⌘K)

### 54.1 Universal shortcut
- [ ] **⌘K on iPad / Mac** → global command palette.
- [ ] **iPhone** — reachable via pull-down gesture on any screen.

### 54.2 Action catalog
- [ ] **Every registered action** — "New ticket", "Find customer by phone", "Send SMS", "Clock out", "Close shift", "Settings: Tax", "Reports: Revenue this month".
- [ ] **Fuzzy search** — Sublime-style; rank by recent usage.

### 54.3 Scope + context
- [ ] **Current context aware** — "Add note to this ticket" works when ticket open.
- [ ] **Entities** — type ticket # / phone / SKU → navigate.

### 54.4 Keyboard-first
- [ ] **Arrow navigate**, **⏎ execute**, **⎋ dismiss**.

---

## 55. Public Tracking Page (customer-facing)

### 55.1 Share link
- [ ] **Per-ticket** — generates `https://app.bizarrecrm.com/track/<token>`.
- [ ] **QR + SMS + email** send options.

### 55.2 What customer sees (validate)
- [ ] **Status timeline** — auto-updating.
- [ ] **Tech photos** (redacted for privacy).
- [ ] **ETA**.
- [ ] **Pay balance** CTA (links to §41 public pay).

### 55.3 iOS admin preview
- [ ] **"Preview as customer"** button opens `SFSafariViewController`.

---

## 56. TV Queue Board (in-shop display)

### 56.1 TV mode
- [ ] **Landscape full-screen** iPad → mounted on wall.
- [ ] **Auto-rotating tiles** — Now-serving / Ready-for-pickup / Est-wait-times.

### 56.2 Customer-facing info only
- [ ] **No PII** — first-name + last-initial only.
- [ ] **Status color-coded**.

### 56.3 Manager controls
- [ ] **Swipe up** — hidden admin panel to advance queue / pause.

### 56.4 Screen-saver vs always-on
- [ ] **Guided Access** recommended to lock into TV mode.

---

## 57. Assistive / Kiosk Single-Task Modes

### 57.1 POS-only mode
- [ ] **Role / device profile** — lock app to POS tab.
- [ ] **Exit** requires manager PIN.

### 57.2 Clock-in-only mode
- [ ] **For shared shop iPad** — only Timeclock accessible.

### 57.3 Training profile
- [ ] **Assistive Access adoption** — simplified icons, large buttons.

---

## 58. Appointment Self-Booking (customer)

### 58.1 Public booking page
- [ ] **Customer-facing URL** — picks service + time slot.

### 58.2 iOS admin side
- [ ] **Staff sees real-time bookings**.
- [ ] **Confirm / reschedule / decline** — all SMS-notified.

### 58.3 Availability rules
- [ ] **Per-technician capacity** — max N per slot.
- [ ] **Buffer time** between appts.
- [ ] **Blackout days**.

---

## 59. Field-Service / Dispatch (mobile tech)

### 59.1 Map view
- [ ] **MapKit** — appointments pinned on map.
- [ ] **Route** to next job via Apple Maps.

### 59.2 Check-in / check-out
- [ ] **GPS verified** — arrival → start-work auto.
- [ ] **Signature on completion**.

### 59.3 On-site invoice
- [ ] **POS in the field** — BlockChyp mobile terminal.
- [ ] **Email/SMS receipt immediately**.

---

## 60. Inventory Stocktake

### 60.1 Cycle count mode
- [ ] **Scan every SKU** in location → server compares expected.
- [ ] **Variance report** — overs / shorts.
- [ ] **Adjustment** — accept + audit.

### 60.2 Bin locations
- [ ] **Multi-bin per SKU**.
- [ ] **Guided path** — tell tech which bin next.

### 60.3 Reorder automation
- [ ] **Reorder points** — auto-PO when < threshold.
- [ ] **Supplier management** — address + lead time.

---

## 61. Purchase Orders (inventory)

### 61.1 PO list + detail
- [ ] **Server**: `GET/POST /purchase-orders`.
- [ ] **Create** — supplier + lines + expected date.
- [ ] **Receive** — mark items received; increment stock.
- [ ] **Partial receive**.

### 61.2 Cost tracking
- [ ] **Landed cost** — purchase + shipping / duty allocation.

---

## 62. Financial Dashboard (owner view)

### 62.1 KPI tiles
- [ ] **Revenue / profit / expenses / AR / AP / cash-on-hand** with trends.

### 62.2 Profitability
- [ ] **Per-service gross margin**.
- [ ] **Per-tech profitability**.

### 62.3 Forecast
- [ ] **30/60/90 day revenue forecast** (ML if server).

---

## 63. Multi-Location Management

### 63.1 Location switcher
- [ ] **Top-bar chip** on iPad — active location.
- [ ] **"All locations"** aggregate view for owner.

### 63.2 Transfer between locations
- [ ] **Inventory transfer** — pick items + source/dest + signature.

### 63.3 Per-location reports
- [ ] **Revenue / tickets / employees**.

---

## 64. Release checklist (go-live gates)

### 64.1 Before TestFlight
- [ ] Auth + Dashboard + Tickets + Customers + Inventory + Invoices + SMS fully functional.
- [ ] Offline queue operational.
- [ ] Push notifications working.
- [ ] Settings has Profile + Security + Appearance + Server + About.
- [ ] Crash-free > 99.5% in internal test.

### 64.2 Before App Store public
- [ ] Parity with Android on all domains above.
- [ ] POS + barcode + BlockChyp terminal + printer.
- [ ] Widgets + Live Activities + App Intents.
- [ ] iPad 3-column polish.
- [ ] Accessibility audit passes.
- [ ] Privacy policy + Terms live.
- [ ] Screenshots + App Preview.

### 64.3 Before marketing push
- [ ] Marketing campaigns + NPS + reviews.
- [ ] Memberships.
- [ ] Public pay + public tracking.
- [ ] TV board.
- [ ] Field service / dispatch (if applicable).

---

## 65. Non-goals (explicit)

- **Management / admin tools** — handled by separate Electron app; out of iOS scope.
- **Server administration** — no server-config UI in iOS.
- **Accounting-system parity** (QuickBooks replacement) — stay focused on repair-shop workflow; export to QB via server.
- **Email marketing** — SMS-first; deprioritize email marketing tools unless tenant explicitly requests.
- **Third-party marketplaces** (Shopify, Square as payment) — BlockChyp only.
- **Employee scheduling software parity** (When I Work, Deputy) — light scheduling only.
- **Customer-facing companion app** — this app is staff-only. Customers use web + Apple Wallet passes + SMS + email. No `com.bizarrecrm.myrepair` target. (See §91.)

---

## 66. Error, Empty & Loading States (cross-cutting)

### 66.1 Error states
- [ ] **Network error** — glass card: illustration + "Can't reach the server" + Retry. Show cached data below in grayscale if available.
- [ ] **Auth error** — "Session expired" toast → auto-re-auth attempt → fall back to Login.
- [ ] **Validation error** — inline under field with brand-danger accent + descriptive copy.
- [ ] **Server 5xx** — "Something went wrong on our end" + retry + "Report a problem".
- [ ] **Not-found (404)** — specific per entity ("Ticket #1234 not found" + Search button).
- [ ] **Permission denied (403)** — "Your role doesn't allow this — ask an admin".
- [ ] **Rate-limited (429)** — countdown + "Try again in Ns".
- [ ] **Offline + no cache** — "Go online to load this screen for the first time".
- [ ] **Corrupt cache** — auto-recover + re-fetch; show banner.

### 66.2 Empty states
- [ ] **First-run empty**  — brand illustration + 1-line copy + primary CTA ("Add your first customer").
- [ ] **Filter empty** — "No results for this filter — clear filter / change dates".
- [ ] **Search empty** — "No matches — try different spelling".
- [ ] **Section empty** (detail sub-lists) — inline muted copy; no illustration.
- [ ] **Permission-gated** — "This feature is disabled for your role".

### 66.3 Loading states
- [ ] **Skeleton rows** — shimmer glass placeholders for lists.
- [ ] **Hero skeleton** — card shape placeholder for detail pages.
- [ ] **Spinner** — only for sub-second operations (save); use progress for long.
- [ ] **Progress bar** — determinate for uploads / imports / printer jobs.
- [ ] **Optimistic UI** — item appears instantly with "Sending…" glow.
- [ ] **Shimmer duration cap** — if > 5s loading, swap to "Still loading… slower than usual — tap to retry".

### 66.4 Inline pending
- [ ] **Saving chip** — "Saving…" glass chip top-right while mutation in flight.
- [ ] **Saved tick** — brief green check on save.

### 66.5 Destructive-action flows
- [ ] **Soft-delete with undo** — toast "Deleted. Undo?" 5-second window.
- [ ] **Hard-delete confirm** — alert with consequence copy + type-to-confirm for catastrophic actions.
- [ ] **Undo stack** — last 5 actions undoable via `⌘Z`.

---

## 67. Copy & Content Style Guide (iOS-specific tone)

### 67.1 Voice
- [ ] **Direct, friendly, short** — ≤ 12 words per sentence.
- [ ] **Sentence case** — not Title Case. "Create ticket" not "Create Ticket".
- [ ] **Active voice**.
- [ ] **No jargon** to end-users (staff-facing).

### 67.2 Button verbs (consistent)
- [ ] "Save" never "OK" on forms.
- [ ] "Delete" never "Remove" for hard delete.
- [ ] "Cancel" always on dismiss.
- [ ] "Done" on completion dismiss.

### 67.3 Error copy rules
- [ ] **What** happened.
- [ ] **Why** (if known).
- [ ] **What to do**.
- [ ] Don't blame the user.

### 67.4 Placeholders
- [ ] **Input hints** show format: "555-123-4567" for phone.
- [ ] **No assistive text saying obvious** ("Enter your name").

### 67.5 Timestamps
- [ ] **Relative for recent** — "3 min ago", "Yesterday at 2:30 PM".
- [ ] **Absolute for older** — "Apr 3, 2026".
- [ ] **Tooltip on hover (iPad/Mac)** — always shows absolute.

### 67.6 Numbers
- [ ] **Currency** — always with symbol + decimals respecting locale.
- [ ] **Large numbers** — 1,234 (comma-separated), or `1.2k` / `1.2M` only on dense chips.
- [ ] **Zero state** — "—" not "0" when value is N/A.

### 67.7 Names + IDs
- [ ] **Ticket IDs** — `#1234` prefix.
- [ ] **Customer** — "John S." on space-constrained, full name in detail.
- [ ] **Phone** — formatted per locale.

---

## 68. Deep-link / URL scheme reference

| Path | Screen |
|---|---|
| `bizarrecrm://dashboard` | Home |
| `bizarrecrm://tickets/:id` | Ticket detail |
| `bizarrecrm://tickets/new` | New ticket |
| `bizarrecrm://customers/:id` | Customer detail |
| `bizarrecrm://customers/new` | New customer |
| `bizarrecrm://inventory/:sku` | Inventory detail |
| `bizarrecrm://inventory/scan` | Barcode scan |
| `bizarrecrm://invoices/:id` | Invoice detail |
| `bizarrecrm://invoices/:id/pay` | Invoice pay |
| `bizarrecrm://estimates/:id` | Estimate detail |
| `bizarrecrm://leads/:id` | Lead detail |
| `bizarrecrm://appointments/:id` | Appointment detail |
| `bizarrecrm://sms/:threadId` | SMS thread |
| `bizarrecrm://sms/new?phone=…` | New SMS compose |
| `bizarrecrm://pos` | POS |
| `bizarrecrm://pos/sale/new` | New sale |
| `bizarrecrm://pos/return` | Returns |
| `bizarrecrm://settings` | Settings root |
| `bizarrecrm://settings/:tab` | Specific tab |
| `bizarrecrm://timeclock` | Timeclock |
| `bizarrecrm://search?q=…` | Search |
| `bizarrecrm://notifications` | Notifications |
| `bizarrecrm://reports/:name` | Report detail |

### 68.1 Universal Links (web-first)
- [ ] `app.bizarrecrm.com/track/:token` → iOS public-tracking page (same UI as public web).
- [ ] `app.bizarrecrm.com/pay/:token` → iOS payment page.
- [ ] `app.bizarrecrm.com/review/:token` → SMS review flow.

### 68.2 Associated-domains entitlement
- [ ] `applinks:app.bizarrecrm.com` — main.
- [ ] `applinks:*.bizarrecrm.com` — future subdomains.
- [ ] Self-hosted tenants: add their domain to entitlement via build config (fastlane per-tenant bundle).

---

## 69. Haptics Catalog (iPhone-specific)

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

### 69.1 CoreHaptics engine (from §157)
- `CHHapticEngine` registered on app start.
- Re-start on `audioSessionInterruption` + `applicationWillEnterForeground`.
- Single `HapticCatalog.swift` source; ban ad-hoc calls.
- Non-haptic devices (iPad without Taptic) → silent.

### 69.2 Custom patterns (from §157)
- **Sale success** — 3-tap crescendo (0.1, 0.2, 0.4 intensity, 40ms apart). Plus success chime.
- **Card decline** — two-tap sharp (0.9, 0.9, 80ms apart).
- **Drawer open** — single medium thump.
- **Scan match** — single gentle click + pitched sound.
- **Scan unmatched** — double sharp (warning).
- **Status advance** — ramp from 0.2 → 0.6 over 150ms.
- **Undo** — reverse ramp.
- **Signature complete** — triple subtle, low intensity.

---

## 70. Motion Spec

### 70.1 Durations
- 120ms — chip toggle
- 160ms — FAB appear
- 200ms — banner slide
- 220ms — tab switch
- 280ms — push navigation
- 340ms — modal sheet
- 420ms — shared element transition
- 600ms — pulse / confetti

### 70.2 Curves
- `.interactiveSpring(0.3, 0.75)` default.
- `.easeInOut` for bidirectional toggles.
- `.easeOut` for appearance.
- `.easeIn` for dismissal.

### 70.3 Reduce Motion paths
- Springs → fades.
- Parallax → static.
- Pulse → single-frame.
- Shared element → cross-fade.

### 70.4 Signature animations
- [ ] **Ticket-created** — temporary pulse highlight on new row.
- [ ] **Sale-complete** — confetti + check mark center screen.
- [ ] **SMS-sent** — bubble fly-in from composer.
- [ ] **Payment-approved** — green check inside a circle draw.
- [ ] **Low-stock warn** — stock badge pulses red.

---

## 71. Launch Experience

### 71.1 Launch screen
- [ ] **Branded splash** — logo center + gradient; identical in light/dark.
- [ ] **No loading spinners** before UI — state restore quickly.

### 71.2 Cold-start sequence
- [ ] Splash (200ms max) → RootView resolve → Dashboard or Login.
- [ ] **State restore** — last tab + last selected list row.
- [ ] **Deep-link resolution** — before first render.

### 71.3 First-run
- [ ] **Server URL entry** with quick-pick options (saved URLs + "bizarrecrm.com").
- [ ] **What's new** — modal on major version update.

### 71.4 Onboarding tooltips
- [ ] **Coach marks** — first time each top-level screen opened.
- [ ] **Dismissable** + "Don't show again".
- [ ] **Per-feature** — widget install prompt, barcode scan, BlockChyp pairing.

---

## 72. In-App Help

### 72.1 Help center
- [ ] **Settings → Help** — searchable FAQ.
- [ ] **Topic articles** — bundled markdown + images.
- [ ] **Context-aware help** — "? " icon on complex screens → relevant article.

### 72.2 Contact support
- [ ] **Send support email** — prefilled with diagnostic bundle. Recipient resolved from `GET /tenants/me/support-contact` (same source as §2.12 account-locked modal). Never hardcoded. Self-hosted tenants → their own admin. bizarrecrm.com-hosted → `pavel@bizarreelectronics.com`.
- [ ] **Live chat** (if server supports) — embedded.

### 72.3 Release notes
- [ ] **What's new** — on version bump, modal highlights.
- [ ] **Full changelog** — in Help.

### 72.4 Feature hints
- [ ] **Pro-tip banners** — rotating tips on Dashboard.

---

## 73. Notifications — granular per-event matrix

_Every backend-emitted event maps to a configurable notification._

| Event | Default Push | Default Email | Default In-App | Role-gated |
|---|---|---|---|---|
| Ticket assigned to me | ✅ | — | ✅ | Yes |
| Ticket status change (mine) | ✅ | — | ✅ | — |
| Ticket status change (anyone) | — | — | ✅ | Admin |
| New SMS inbound | ✅ | — | ✅ | — |
| SMS delivery failed | ✅ | — | ✅ | Sender |
| New customer created | — | — | ✅ | Admin |
| Invoice overdue | ✅ | ✅ | ✅ | Admin / AR |
| Invoice paid | ✅ | — | ✅ | Creator |
| Estimate approved | ✅ | — | ✅ | Creator |
| Estimate declined | ✅ | — | ✅ | Creator |
| Appointment reminder 24h | — | ✅ | ✅ | Assignee |
| Appointment reminder 1h | ✅ | — | ✅ | Assignee |
| Appointment canceled | ✅ | — | ✅ | Assignee |
| @mention in note / chat | ✅ | — | ✅ | — |
| Low stock | — | — | ✅ | Admin / Mgr |
| Out of stock | ✅ | — | ✅ | Admin / Mgr |
| Payment declined | ✅ | — | ✅ | Cashier |
| Refund processed | — | — | ✅ | Originator |
| Cash register short | ✅ | ✅ | ✅ | Admin |
| Shift started / ended | — | — | ✅ | Self |
| Goal achieved | ✅ | — | ✅ | Self + Mgr |
| PTO approved / denied | ✅ | — | ✅ | Requester |
| Campaign sent | — | ✅ | ✅ | Sender |
| NPS detractor | ✅ | — | ✅ | Mgr |
| Setup wizard incomplete (24h) | — | ✅ | ✅ | Admin |
| Subscription renewal | — | ✅ | ✅ | Admin |
| Integration disconnected | ✅ | ✅ | ✅ | Admin |

### 73.1 Matrix editable
- [ ] Per-user override of defaults (in Settings § 19.3).
- [ ] Per-tenant default override (Admin).
- [ ] Quiet-hours respect.
- [ ] Critical-override override (opt-in).

---

## 74. Privacy-first analytics event list

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

### 74.1 Schema
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

### 74.2 No tracking
- No IDFA, no Facebook pixel, no Google Analytics, no Braze.

---

## 75. Final UX Polish Checklist

### 75.1 Animation
- [ ] Every screen's entry + exit animation tested.
- [ ] No janky flashes on state change.
- [ ] Modals never pop.

### 75.2 Focus
- [ ] Keyboard first-responder set deliberately on form open.
- [ ] Focus traps for modals.
- [ ] Focus returns to opener on dismiss.

### 75.3 Keyboard dismiss
- [ ] Tap-outside + scroll dismisses.
- [ ] Done button on number pads.

### 75.4 Loading → Done transitions
- [ ] Skeleton never jumps to content without cross-fade.

### 75.5 Scroll behavior
- [ ] Preserve scroll on back-nav.
- [ ] Jump-to-top on tab re-select.

### 75.6 Pull-to-refresh
- [ ] Available on every list + Dashboard.

### 75.7 Selection + multi-select
- [ ] Long-press enters edit mode on lists.
- [ ] Batch-action bar slides up from bottom (glass).

### 75.8 Sheets vs full-screen
- [ ] Create/edit forms in sheets (medium/large detents).
- [ ] Detail views full-screen push.

### 75.9 Back-navigation consistency
- [ ] Swipe-back works on every non-modal push.
- [ ] Custom back buttons discouraged.

### 75.10 Status bar
- [ ] Honors `.preferredStatusBarStyle` per screen.
- [ ] Light on dark surfaces; dark on light.

---

## 76. Apple Intelligence & On-Device ML (iOS 18.1+)

_Respect data-sovereignty: any cloud-AI egress is banned. On-device Apple Intelligence + Private Cloud Compute (Apple-hosted, no third-party) only._

### 76.1 Writing Tools
- [ ] **Compose + Rewrite** — on SMS composer, ticket notes, campaign templates; system sheet offers tone changes (friendly / professional / concise).
- [ ] **Proofread** — red-underline grammar on notes.
- [ ] **Summarize** — thread summary at top of long SMS threads.
- [ ] **Staff-readable tone toggle** — technician notes can be auto-rewritten for customer-facing delivery.
- [ ] **Opt-out** — Settings toggle per tenant.

### 76.2 Genmoji / Image Playground
- [ ] **Custom emoji** in SMS composer.
- [ ] **Staff avatars** — optional Genmoji-generated avatar.
- [ ] **Receipt stamps** — light brand stamp on printed receipts (opt-in).

### 76.3 Smart replies / prompts
- [ ] **SMS quick-reply suggestions** — bubble chips above composer with 3 AI suggestions based on context; user taps or edits.
- [ ] **Ticket next-step** — "Suggest next action" button → AI proposes status change + SMS draft.
- [ ] **Expense category auto-tag** — OCR receipt → Category prediction.

### 76.4 Vision / image tasks
- [ ] **OCR pre-fill** — `VNRecognizeTextRequest` extracts totals / SKUs / IMEIs.
- [ ] **Receipt edge detect** — `VNDetectRectanglesRequest` auto-crops.
- [ ] **Remove background** — `VNGenerateForegroundInstanceMaskRequest` on product photos.
- [ ] **Subject lift** — iOS 16 lift API used to create hero photo from damage photo.
- [ ] **Image description** — generate alt-text for accessibility.

### 76.5 Voice
- [ ] **Whisper-local dictation** on ticket notes (`SFSpeechRecognizer` on-device).
- [ ] **Voice notes → text** on SMS inbound voicemails.

### 76.6 Predictions
- [ ] **Repair time prediction** — CreateML model trained on tenant history: "Est: 45 min" on intake.
- [ ] **Price suggestion** — based on past similar services.
- [ ] **Customer churn** — local scoring (see §45).

### 76.7 Private Cloud Compute
- [ ] **Fallback for long-context** — summarize 100+ SMS thread → PCC.
- [ ] **Tenant opt-in required** — default off, per-tenant toggle.
- [ ] **Audit** — show "Sent to Private Cloud Compute" badge on any AI-generated content.

### 76.8 No third-party AI
- [ ] **Banned SDKs** — OpenAI, Anthropic API, Gemini, Hugging Face, Replicate, Cohere.
- [ ] **Own server may provide AI** — if tenant server offers `POST /ai/*`, iOS can use it. No direct SaaS.

---

## 77. Android → iOS Parity Checklist (per-feature deep dive)

_For every Android feature, list iOS equivalent + status._

### 77.1 Navigation
- Android bottom nav → iOS TabView (iPhone) / NavigationSplitView (iPad).
- Android Drawer (if any) → iOS sidebar (iPad) or More tab (iPhone).

### 77.2 Forms
- Android Jetpack Compose forms → SwiftUI Forms + BrandTextField.
- Android Picker → SwiftUI Picker / BrandPicker.
- Android DatePicker → SwiftUI DatePicker.

### 77.3 Offline
- Android Room → GRDB + SQLCipher.
- Android WorkManager → BGTaskScheduler + URLSession background.
- Android EncryptedSharedPreferences → Keychain.

### 77.4 Push
- Android FCM → APNs.
- Android notification channels → UNNotificationCategory.
- Action buttons map 1:1.

### 77.5 Biometric
- Android BiometricPrompt → LAContext.
- Fallback: PIN (same).

### 77.6 Camera
- Android CameraX → AVCaptureSession.
- Android ML Kit barcode → VisionKit DataScanner.

### 77.7 WebSocket
- Android OkHttp WS → Starscream.
- Protocol + envelope identical.

### 77.8 Per-domain-screen parity table (to fill)
- Tickets List: Android ✅, iOS ✅
- Tickets Detail: Android ✅, iOS ✅
- Tickets Create full: Android ✅, iOS 🟡 (add pricing calculator, multi-device, service picker, etc.)
- POS: Android ✅, iOS ⬜
- Barcode: Android ✅ (CameraX + ML Kit), iOS ⬜ (DataScanner)
- Printer: Android ✅ (ESC/POS over BT), iOS ⬜ (MFi required)
- (Fill remainder from android repo inventory.)

### 77.9 Testing sync
- Sync bug fixed on Android must have iOS regression test.
- Shared API fixtures reused where possible.

---

## 78. Developer Onboarding (for new contributors)

_iOS/ folder is owned by distinct engineering stream; new joiners must self-serve._

### 78.1 First-time setup
- [ ] Clone repo + `cd ios/`.
- [ ] `bash scripts/fetch-fonts.sh` (required or SF Pro fallback).
- [ ] `bash scripts/gen.sh` (generates Info.plist + xcodegen project).
- [ ] Open `BizarreCRM.xcworkspace` in Xcode 26.
- [ ] Set `DEVELOPMENT_TEAM` in Signing per-user.
- [ ] `⌘R` — should launch to Login.
- [ ] Enter dev server URL + login.
- [ ] Run tests: `⌘U`.

### 78.2 Repository tour
- [ ] `ios/App/` — AppDelegate, SceneDelegate, RootView, Platform, entitlements.
- [ ] `ios/Packages/<Domain>/` — SPM packages per domain.
- [ ] `ios/DesignSystem/` — tokens, fonts, glass, motion, haptics.
- [ ] `ios/Core/` — APIClient, Persistence, Keychain, SyncService.
- [ ] `ios/scripts/` — gen.sh, write-info-plist.sh, fetch-fonts.sh.
- [ ] `ios/fastlane/` — lanes + match config.

### 78.3 Coding conventions
- [ ] SwiftLint + SwiftFormat — pre-commit hook.
- [ ] Naming: `ViewName`, `ViewNameViewModel`, `EntityRepository`, `EntityDao`.
- [ ] File size ≤ 400 lines; split when larger (per project style rule).
- [ ] Immutability preferred.
- [ ] `@Observable` over `@ObservableObject`.

### 78.4 Contribution workflow
- [ ] Branch from `main`; PR to `main`.
- [ ] TDD: test first, code second.
- [ ] Code reviewer approval required.
- [ ] Build + tests green before merge.

### 78.5 Debugging
- [ ] Settings → Diagnostics → Log viewer (filter).
- [ ] Network inspector.
- [ ] `LLDB` tips doc.

### 78.6 Common pitfalls
- [ ] Never hand-edit `.xcodeproj`.
- [ ] Never skip `gen.sh`; `Info.plist` is a build artifact.
- [ ] Never bypass envelope parsing.
- [ ] Never introduce third-party analytics / crash SDK.

### 78.7 Glossary
- [ ] **Tenant** — a customer organization.
- [ ] **Envelope** — `{success, data, message}`.
- [ ] **Sync queue** — optimistic-mutation FIFO.
- [ ] **Liquid Glass** — iOS 26 refraction material; `.brandGlass` wrapper.
- [ ] **Platform.isCompact** — iPhone gate.

---

## 79. Rollout Strategy — MERGED INTO §313

Content moved to §313 (Phase Definition of Done). §313.10-§313.12 carry per-tenant rollout, kill-switch, and migration path. Number preserved.

---

## 80. Glossary of non-negotiables

### iPad ≠ upscaled iPhone
Any screen without a distinct iPad layout using `Platform.isCompact` gate is unfinished.

### Liquid Glass is mandatory
`.brandGlass` on nav / toolbars / chips / FABs. Never on content. Never stacked. ≤ 6 visible concurrently.

### Envelope is sacred
`{ success, data, message }` — single unwrap. No branching envelope shapes.

### Data sovereignty
Single egress: `APIClient.baseURL`. No Sentry / Firebase / Mixpanel / anything off-tenant.

### No orphan UI
Every element wired end-to-end before commit.

### TDD
Test first. 80% coverage floor.

### Tenant DBs are sacred
Never wipe tenant DB to recover; repair.

### Keychain for secrets
Tokens / passphrases / PIN hashes / API keys. Never UserDefaults.

### Immutability preferred
Swift value types; let over var.

### File size discipline
≤ 400 lines per file typical; 800 max.

### iOS floor = 17
iOS 26 design target, iOS 17 minimum.

### Xcodegen-driven
Project regenerated via `bash ios/scripts/gen.sh`. Never hand-edit `.xcodeproj`.

### Info.plist is a build artifact
Generated by `scripts/write-info-plist.sh`. `.gitignore`d.

### Brand fonts fetched
`scripts/fetch-fonts.sh` first. Inter / Barlow Condensed / JetBrains Mono.

---

## 81. Open questions / TBD

- [ ] **Server capabilities** confirm: `/sync/delta`, `/telemetry/*`, `/call-logs`, `/gift-cards`, `/store-credit`, `/payment-links`, `/public-tracking`, `/nlq-search` endpoints exist or need to be added.
- [ ] **BlockChyp iOS SDK** test coverage + SwiftUI compat — evaluate vs REST bridge.
- [ ] **MFi printer vendor** — Star vs Epson primary? Both?
- [ ] **Subscription billing** — in-app (StoreKit) vs Stripe-only?
- [ ] **Multi-tenant user handling** — single user with many tenants: UX pattern for switch?
- [ ] **Self-hosted tenants without HTTPS** — lab/dev mode allowance?
- [ ] **Customer portal parity** — do customers log into the iOS app too or only view web?
- [ ] **Shared credentials** — one device shared among cashiers: switch-user flow + trust level.
- [ ] **Data-export format** for tenant migration off BizarreCRM.
- [ ] **Apple Watch** — is the 1% user volume worth the maintenance? Decide post-Phase 5.
- [ ] **CarPlay** — if field-service is meaningful, possibly worthwhile.
- [ ] **visionOS** — stretch; likely not Phase 1–7.

---

## 82. CarPlay

Evaluate only if field-service volume crosses threshold (>20% tenants use Field Service lane). Otherwise defer.

### 82.1 Use-cases
- **Today's route** — CarPlay list of on-site appointments in optimized order.
- **Tap customer → dial** — CallKit hand-off from CarPlay.
- **Navigate to address** — Apple Maps handoff.
- **Arrive / Start / Complete** — three big buttons, spoken confirmation.
- **Status note voice-dictation** — Siri "Add note to ticket 4821".
- **No pricing, no POS, no inventory** — too risky while driving.

### 82.2 Template choice
- `CPListTemplate` for appointments (driver-safe, tall rows, icons).
- `CPPointOfInterestTemplate` for customer locations.
- `CPNowPlayingTemplate` not used — not a media app.
- `CPInformationTemplate` for ticket short-detail (one line, max 3 fields).
- Never use free-form entry; everything is pick-list or Siri.

### 82.3 Entitlements
- Request CarPlay entitlement (`com.apple.developer.carplay-fleet` or `com.apple.developer.carplay-messaging`) — likely `fleet` for field techs. Apple approval process ≈ 2–4 weeks.
- If not approved, fall back to standard in-car Siri integration via App Intents (works without entitlement).

### 82.4 Sovereignty
- CarPlay location and audio stays on device. No routing through third-party nav providers — use Apple Maps only.
- Voice dictation uses on-device Siri where supported (iOS 17+).

### 82.5 Testing
- CarPlay simulator target in Xcode.
- Physical head-unit test before shipping (Apple requirement for fleet entitlement).

---

## 83. visionOS lane (stretch, post-Phase 7)

Not committed. Noted so the architecture doesn't preclude it.

### 83.1 What makes sense in visionOS
- **Dashboard glass wall** — KPI tiles floating, big. Liquid Glass was designed for this.
- **Ticket queue window** — secondary window pinned to workbench wall.
- **SMS thread window** — another window.
- **POS terminal mode** — counter-top anchored; customer-facing price on wall.

### 83.2 Port cost
- Most SwiftUI code ports free. Need to add `.glassBackgroundEffect(in:)`, ornaments, window groups, spatial navigation.
- Camera stack (`AVCaptureSession`) doesn't exist on visionOS → barcode / photo flows disabled or handoff-to-iPhone.
- BlockChyp terminal won't tether to Vision Pro directly; customer-facing display via Vision Pro instead.

### 83.3 Decision gate
- Revisit when Vision Pro US install base > 500k and ≥ 3 tenants request it. Until then, Phase ∞.

---

## 84. Server API gap analysis

Endpoints iOS expects that may not yet exist. Verify before shipping each feature.

### 84.1 Likely missing (verify with `packages/server/src/routes/`)
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
| `GET  /public/tracking/:shortId` | §55 | Likely needs public-side route |
| `POST /nlq-search` | §18.6 | Likely missing |
| `POST /pos/cash-sessions` | §39 | Verify |
| `POST /pos/cash-sessions/:id/close` | §39 | Verify |
| `GET  /audit-logs` | §52 | Verify |
| `POST /imports/start` | §50 | Verify |
| `GET  /imports/:id/status` | §50 | Verify |
| `POST /exports/start` | §51 | Verify |
| `GET  /exports/:id/download` | §51 | Verify |
| `POST /tickets/:id/signatures` | §85.5 | Verify |
| `POST /tickets/:id/pre-conditions` | §85.3 | Verify |
| `GET  /device-templates` | §44 | Verify |
| `POST /locations` | §63 | Verify |
| `GET  /memberships/:id/wallet-pass` | §38 | Likely missing (need PassKit server) |

### 84.2 Action
- Before each feature ships, an iOS engineer files a server ticket if endpoint missing.
- iOS writes request/response TypeScript DTO in `packages/shared/` so web and Android can reuse.

### 84.3 Local shim
- APIClient returns 501 hand-crafted `APIError.notImplemented` for missing endpoints. UI shows "Coming soon — feature not yet enabled on your server" rather than crash.

---

## 85. Tickets — deep drill-down (supersedes §4 partial details)

### 85.1 Pricing calculator
- **Inputs**: service lookups, parts lookups, labor minutes, tax, discount code, customer group markup.
- **Live compute**: `TicketPricing.computeTotal(lines, taxRule, discount)` pure function. Zero round-trip for each keystroke.
- **Line editor**:
  - Swipe-to-delete on rows.
  - Drag-to-reorder on iPad.
  - Inline qty stepper, unit-price editable.
  - Parts rows show stock-level chip (`In stock 4` / `Low 1` / `Out`).
  - Services rows show default labor minutes with override.
- **Discount**: percentage or fixed, stacks before tax. Admin-only can zero out tax (permission-gated).
- **Tax preview**: separate line, computed from location-aware rule; shows "Tax rule: CA 7.25%" tap → drawer with breakdown.
- **Deposit**: optional field; if set, invoice-on-create gets payment line for deposit.
- **Assumptions**: totals stored in cents; display locale-aware.
- **iPad split**: left column = parts / services catalog with search; right column = running cart.
- **Keyboard shortcut**: ⌘P → add part via picker, ⌘S → add service, ⌘T → apply tax override, ⌘+Enter → save ticket.

### 85.2 Multiple devices
- Ticket → array of `DeviceEntry { make, model, serial, imei, passcode, password, color, condition }`.
- UI: vertical list of device cards; "+ Add device" FAB; swipe-to-remove.
- Passcode field masked by default, 👁 reveal tap (1s window), clipboard copy haptic-warned "sensitive".
- IMEI validator client-side (Luhn + length).
- Auto-fill via barcode scan (§17.2) — scan IMEI → populate.
- Auto-fill from device template (§44) — pick "iPhone 15 Pro" → pre-fill make / model / typical conditions.

### 85.3 Pre-conditions checklist
- Template list per device type (cracked screen / dents / water damage / battery health / missing buttons / etc.).
- UI: grid of chips, multi-select; custom "+" adds free-text.
- "Note" field per condition for specifics.
- Photo attach per condition optional — "Photo of crack" shortcut.
- Saved to `/tickets/:id/pre-conditions` on ticket save.
- Rendered on printed / PDF / emailed ticket as a bullet list so customer can't later dispute.

### 85.4 Photo attach + annotation
- `PhotosPicker` + `AVCaptureSession` dual entry.
- After pick / capture, goes to annotation view: `PKCanvasView` overlay, draw tools (pen, highlight, text box, arrow).
- Presets: "Where cracked", "Where dent", "Water indicator".
- Save → compressed JPEG (0.7 quality, max 2048 side), upload via `URLSession` background task.
- Metadata: GPS stripped by default (privacy); tenant can opt-in.
- Photos tab shows grid with `Image`+`.scaleEffect` open-to-lightbox on tap.
- Caption field; caption searchable in FTS5.

### 85.5 Customer signature at drop-off
- `PKCanvasView` full-width, one-tap clear.
- "I agree to diagnostic fee and repair terms" checkbox above; required to enable Submit.
- Stored as PNG + embedded in PDF of work order.
- POST `/tickets/:id/signatures` with base64 + signer name + timestamp + IP + device fingerprint.

### 85.6 Status history timeline
- Vertical timeline (left line, dots, right cards).
- Entries: status change / assignment / note / price change / photo added / signature captured / SMS sent / payment received.
- Each entry shows actor avatar, timestamp, relative time, device fingerprint.
- Tap entry expand to full detail.
- Filter chips: all / status / comms / money / photos.

### 85.7 Assignee picker
- Search + avatar row of active techs.
- Workload indicator chip per tech (`3 active`, `7 active`); color-coded.
- Tap → assign + POST `/tickets/:id/assignee`.
- Reassignment creates history entry with prev / new.

### 85.8 Status picker
- Bottom sheet with all tenant-configured statuses (from §19.16).
- Each status shows color, icon, est. duration, next-status hints.
- On change, prompt "Notify customer via SMS?" with pre-filled template.
- Statuses that require photo / signature / payment gate the transition until satisfied.

### 85.9 Service request text + customer reported issue
- Two fields: "Customer reported" (printed on work order) and "Internal notes" (staff-only).
- Voice dictation via Siri (§17) one-tap mic button.
- AI-suggest rewrite via WritingTools (§76) → button "Polish with Apple Intelligence" → rewrites grammatically.

### 85.10 Follow-ups & reminders
- "Remind me in X" set a follow-up → `UNCalendarNotificationTrigger`.
- Reminders show in Notifications tab with deep-link.
- Bulk-reminder via tenant rule ("any ticket status=waiting-for-parts > 7d → escalate").

### 85.11 Attachments (non-photo)
- PDF receipts, emails, warranty docs attach via `UIDocumentPickerViewController`.
- Storage: tenant server. Downloaded to `~/Documents/tickets/<id>/...` for offline access.

### 85.12 Ticket print / share / export
- **Print**: AirPrint via `UIPrintInteractionController`.
- **PDF**: `UIGraphicsPDFRenderer` → share sheet.
- **Email**: pre-fills to customer email with PDF attached.
- **SMS**: sends short status line + public-tracking link.
- **AirDrop**: shares the PDF.

---

## 86. Per-screen wireframe outlines (iPhone / iPad variants)

This section records the intended hierarchy for each major screen — no Figma, just structured prose so wireframes can be mocked 1:1.

### 86.1 Dashboard
- **iPhone**: vertical scroll; KPI grid 2×N; Needs-Attention card; Today's Activity timeline; quick-actions row (Create Ticket / Take Payment / Scan).
- **iPad**: 3 columns: left = KPI grid 3×N, middle = Needs-Attention + Today, right = Quick actions + Recent Activity.

### 86.2 Tickets list
- **iPhone**: top glass search + filter chips; List rows: customer + device + status pill + price + updated-ago; pull-to-refresh; FAB glass "New ticket".
- **iPad**: 3-column split; sidebar = filters (status / assignee / saved views); middle = list; right = detail pane that updates on selection.

### 86.3 Ticket detail
- **iPhone**: scroll stack of cards: Header (customer + status) / Devices / Pre-conditions / Photos / Parts+Services+Totals / History / Payments / Footer actions.
- **iPad**: 2-pane inside detail: left 60% = same card stack; right 40% = inline Comms panel (SMS thread + photos + history) — no paging.

### 86.4 Customers list
- **iPhone**: search + list; avatar + name + phone + LTV chip + last-visit ago.
- **iPad**: 3-column (sidebar filters, list, detail).

### 86.5 Customer detail
- **iPhone**: tabs: Info / Tickets / Invoices / SMS / Notes.
- **iPad**: side tabs (vertical) + right content; parallel loading.

### 86.6 POS
- **iPhone**: top glass nav, cart bottom-sheet `.presentationDetents: [.medium, .large]`, catalog grid above; checkout slides up.
- **iPad**: 3-column: catalog (left 60%), cart (right 40%), top glass bar with customer + discount; checkout = full-width modal sheet.

### 86.7 Inventory list
- **iPhone**: filter chips + list; rows show thumbnail + name + SKU + qty + price.
- **iPad**: 3-column; right pane = stock history chart + movements.

### 86.8 SMS threads
- **iPhone**: list of conversations; tap opens thread; thread uses bubbles + composer + glass nav.
- **iPad**: 3-column chat-style (accounts / threads / messages).

### 86.9 Reports
- **iPhone**: tab bar of report types; each is scroll of Charts.
- **iPad**: 3-column: chart picker sidebar, date-range + filters middle, chart + breakdown right.

### 86.10 Settings
- **iPhone**: grouped List, tap → push next level.
- **iPad**: 2-column Settings-style master-detail, always visible.

---

## 87. Test fixtures catalog

Shared test data for UI tests, unit tests, snapshot tests. One source so every test sees identical data.

### 87.1 Location
`ios/Tests/Fixtures/` — JSON files mirroring server responses verbatim.

### 87.2 Catalog
- `customer_basic.json` — 1 customer, no tickets.
- `customer_full.json` — 1 customer, 12 tickets, 30 invoices, 200 SMS messages.
- `tickets_list_50.json` — page 1 of 50 tickets.
- `tickets_list_paginated_3pages.json` — for pagination tests.
- `ticket_with_all_fields.json` — every optional field set.
- `inventory_100.json` — 100 items mixed stock levels.
- `invoices_with_payments.json` — paid / partial / unpaid mix.
- `sms_thread_200msgs.json` — for scroll perf.
- `dashboard_kpis.json`, `reports_revenue_30d.json`, `reports_expenses_30d.json`.
- `auth_login_success.json`, `auth_login_2fa_required.json`, `auth_login_invalid.json`, `auth_refresh_success.json`, `auth_refresh_revoked.json`.
- `error_envelope_401.json`, `error_envelope_500.json`, `error_envelope_network_timeout.json`.

### 87.3 Fixture API
```swift
enum Fixture {
  static func load<T: Decodable>(_ name: String, as type: T.Type) -> T { ... }
}
```
Used by `MockAPIClient` to replay canned responses.

### 87.4 Snapshot tests
- Run against each fixture × (iPhone Compact / iPhone Regular / iPad Portrait / iPad Landscape) × (Light / Dark) × (Dynamic Type default / xxxLarge).
- Diff images committed to `ios/Tests/Snapshots/`.

---

## 88. SMS AI-assist (on-device only)

§6 SMS Composer gets WritingTools integration — entirely Apple Intelligence, no external LLM.

### 88.1 Reply suggestions
- After incoming SMS, one-tap "Suggest reply" button in composer.
- Calls `WritingToolsCoordinator.suggestReplies(context: threadTail(10), tone: .friendly)`.
- Returns 3 candidates; user taps to insert.
- On devices without Apple Intelligence (pre-A17 / pre-M1), button hidden.

### 88.2 Tone rewriter
- "Polish" menu on composer: Friendly / Professional / Apologetic / Firm.
- `WritingTools.rewrite(text, tone:)`.

### 88.3 Grammar fix
- Red-underline spellcheck native; "Fix all" action via WritingTools.

### 88.4 Summarize thread
- On a long thread, header chip "Summarize" → collapsed TL;DR banner.

### 88.5 Privacy
- All runs on Neural Engine. No text leaves device. Confirmed via Privacy Manifest + MetricKit egress audit.

### 88.6 Telemetry
- `sms.ai_suggest_used` event (no text content) → tenant server.

---

## 89. Inventory cycle-count deep UX

§60 Stocktake expanded.

### 89.1 Flows
- **Full count** — schedule, assign, execute; blocks POS writes for scope items during count.
- **Cycle count** — subset by ABC class or tag; non-blocking.
- **Blind count** — on-hand hidden from counter; recount on mismatch.
- **Spot count** — one-item quick count.

### 89.2 Counter view
- Big number tiles: Item / Expected (hidden if blind) / Counted.
- Tap number → keypad sheet; + / − steppers for small deltas.
- Barcode scan binds to item and increments.
- Voice: "nine" → counted 9.
- Wedge mode: external scanner gun keystrokes captured.

### 89.3 Discrepancy resolution
- After submit, list of mismatches with delta, unit cost, total value impact, reason dropdown (shrink / miscount / transfer / damage / found).
- Require reason on > X% shrink. Bulk reason apply.
- Creates adjustment movements once approved.

### 89.4 Permissions
- Counter role can count; supervisor role approves; admin role can override blind.

### 89.5 Reporting
- Shrink % by period / by tag / by location.
- Accuracy % by counter.

### 89.6 Offline
- Count works fully offline; dump to queue; uploads on reconnect with idempotency key `<location>:<count-session-id>`.

---

## 90. Control Center + Dynamic Island stages

### 90.1 Control Center widgets
- **Clock In/Out** toggle — reuses §48 App Intent. Long-press reveals current shift duration.
- **Create Ticket** — launch ticket create directly.
- **POS — Quick Sale** — opens POS empty cart.
- All widgets glass-style, adopt user's Control Center tint.

### 90.2 Lock Screen widgets
- **Ticket counter** circular widget (active tickets today).
- **Revenue today** rectangular widget.
- **Next appointment** rectangular widget (customer + time + address).

### 90.3 Dynamic Island stages for Live Activities
Ticket-in-progress Live Activity has four stages:

| Stage | Compact leading | Compact trailing | Minimal | Expanded |
|---|---|---|---|---|
| Check-in | icon wrench | customer initials | wrench | full row: customer + device + ETA |
| Diagnostic | icon magnify | timer countdown | clock | progress bar + "Awaiting parts" |
| Repair | icon gear | timer | gear | progress bar + tech name |
| Done | icon check | "Ready" | check | "Ready for pickup — tap to notify" |

### 90.4 POS Live Activity
- Shown during a sale in progress (customer at counter).
- Expanded: cart total, item count, payment state (waiting / approved / declined).
- On approval: haptic + auto-end.

### 90.5 Field-service Live Activity
- During drive-to: ETA + next-customer name + distance.
- During on-site: elapsed + current task.

### 90.6 Action Button (iPhone 15 Pro+)
- Tenant-configurable default: Clock in/out / Create ticket / POS quick sale / Scan barcode.
- Settings § under §19.4 Appearance.

---

## 91. ~~Customer-facing app variant~~ — OUT OF SCOPE

**Removed 2026-04-19.** Explicit direction: BizarreCRM is a staff-only app. No customer-facing companion app is planned. Customers interact with the shop via:

- Public tracking page (§55) — browser, no install.
- Payment link (§41) — browser + Apple Pay.
- SMS thread with shop (§6).
- Email receipts / notifications.
- Apple Wallet pass for membership / gift card (§38, §40, §117) — PassKit only, no companion app.
- Self-booking link (§58) — web.

Do not build `com.bizarrecrm.myrepair`. Do not build a white-label customer app. If customer-side functionality is needed, extend the public web surface of the tenant server, not iOS.

---

## 92. Staff training walkthrough (in-app)

§53 Training Mode + onboarding overlay specifics.

### 92.1 First-run coach marks
- After login, TipKit-style coach marks on first open of each major screen:
  - Dashboard: "Tap any KPI to drill down."
  - Tickets: "Swipe right to start, left to archive. Hold for context menu."
  - POS: "Scan barcode with Action Button. Cash drawer opens on cash tender."
  - Inventory: "Tap stock number to adjust with reason."
- Skip All + Never Show Again (persistent across sessions).

### 92.2 Interactive tutorials
- Sandbox ticket created automatically for new users — named "Training ticket — delete when done".
- Guided tour: "Add a device" → "Add pre-conditions" → "Take photo" → "Add service" → "Take payment" → "Close ticket".
- Each step validated; advance button disabled until done.

### 92.3 Role-based training
- Cashier role: POS tour, no settings tour.
- Technician role: Tickets + Bench tour.
- Manager role: Reports + Settings tour.

### 92.4 Reset
- Settings → Help → Replay tutorials.

### 92.5 Checklists / achievements
- Optional: "Onboarding checklist" in dashboard showing 10 steps.
- Per step, a lightweight achievement animation (haptic success + confetti) — subtle, not cringe.

---

## 93. Error recovery patterns

Every error must have a clear escape hatch. No dead ends.

### 93.1 Network error
- Banner: "No internet — showing offline data."
- Inline on forms: "Couldn't save — retry / keep offline."
- Retry button always offered; exponential backoff countdown visible.

### 93.2 Server 500
- "Something went wrong on our end."
- Show request ID (from `X-Request-ID` header) with "Copy" button.
- Link to "Contact support" — opens SMS or email to tenant admin with request ID pre-filled.

### 93.3 Validation 400
- Field-level error highlighting (red border + icon + message beneath).
- Focus jumps to first invalid field.
- Submit button stays enabled but gentle haptic on tap until fixed.

### 93.4 Permission denied 403
- "You don't have permission to do this."
- Suggest: "Ask [admin name]" — pulled from tenant.
- No raw JSON shown.

### 93.5 Not found 404
- "This [ticket / customer / …] no longer exists."
- "Back to list" button.

### 93.6 Conflict 409 (sync)
- Inline conflict panel: "This was changed by [user] at [time]. Yours / theirs / merge."
- See §20.6.

### 93.7 Payment decline
- "Card declined — try another payment method."
- Last-4 + reason code from BlockChyp.
- Don't show full PAN ever (PCI rule).

### 93.8 Printer failure
- "Printer not found. Reconnect or print to PDF."
- PDF fallback always available.

### 93.9 Camera denied
- "Enable camera access in Settings to scan."
- Deep-link to `UIApplication.openSettingsURLString`.

### 93.10 Storage full
- "Device storage low — sync paused. Free up space to resume."
- Tap banner → opens device Settings > General > iPhone Storage.

### 93.11 Database corruption
- `DBCorruption` alert: "Database couldn't open. Export data and reinstall — your tenant server still has everything."
- One-tap "Export local changes to file" to preserve un-synced work before wipe.

---

## 94. Network engine internals (APIClient)

Reference implementation notes so the whole team reads the same playbook.

### 94.1 Layers
```
Feature ViewModel
      ↓
Repository (domain logic, cache, retry)
      ↓
APIClient (URL + auth + serialization)
      ↓
URLSession (+ PinnedURLSessionDelegate)
```

### 94.2 APIClient surface
```swift
public protocol APIClient {
  func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T
  func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T
  func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T
  func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T
  func delete<T: Decodable>(_ path: String) async throws -> T
  func upload(_ path: String, file: URL, progress: (Double) -> Void) async throws -> URL
  var baseURL: URL { get }
  func setBaseURL(_ url: URL) throws
}
```

### 94.3 Envelope
Single unwrap:
```swift
struct Envelope<T: Decodable>: Decodable {
  let success: Bool
  let data: T?
  let message: String?
}
```
Non-success throws `APIError.server(message)`. Never branches on `error` key.

### 94.4 Retry policy
- Read GETs: 3 retries, 200ms / 500ms / 1200ms, idempotent.
- Write POSTs / PATCHes: single attempt unless `idempotency-key` header sent; with key, retry up to 3.
- 401 → attempt refresh; on refresh fail → sign-out broadcast.
- 503 / 429 → honor `Retry-After` header.
- Network unreachable → fail immediately, caller decides queue / cache.

### 94.5 Instrumentation
- Every request logs: path, status, duration, size. Logged to MetricKit-like local ring buffer, not console.
- Errors also dispatched to `/telemetry/errors` batched.

### 94.6 Auth header
- Bearer token attached on every request.
- Token rotation: on each response, check `X-Token-Rotated` header; if present, update Keychain.

### 94.7 Base URL enforcement
- `setBaseURL` validates scheme ∈ {http, https}, host non-empty, no path after /api/v1.
- Persisted to Keychain, not UserDefaults.
- Changing base URL requires re-login (avoid mixing tenants).

### 94.8 Cancellation
- `Task.cancel()` propagates to URLSession via custom operation map.
- Views use `.task { ... }` (auto-cancel on disappear).

---

## 95. Crash recovery

### 95.1 Crash detection
- MetricKit `MXMetricManager` delivers crash diagnostics on next launch.
- Our `CrashObserver` reads, serializes to JSON, POSTs to `/telemetry/crashes` on tenant server.
- Symbolication done server-side using uploaded dSYM (CI uploads dSYM to tenant artifact store).

### 95.2 Auto-safe-mode
- If app crashed twice in last 60s: next launch opens in Safe Mode (no widgets, no background sync, minimal UI).
- Safe Mode banner: "Safe Mode — tap to report the issue."
- Exiting Safe Mode requires manual action by user (taps "I'm OK now").

### 95.3 Watchdog detection
- `CADisplayLink` on main thread pings a secondary thread every second.
- If main hangs > 5s, secondary logs a `MainThreadHang` event (non-crashing).

### 95.4 No Sentry / Bugsnag
- Reiterates §32 — crashes flow to tenant's own endpoint only.

### 95.5 Local crash log
- Settings → Diagnostics → Recent crashes: list from MetricKit with timestamps and symbolication status.

---

## 96. App Store / TestFlight assets

### 96.1 Screenshots
- 6.9" iPhone (iPhone 16 Pro Max): 10 screenshots covering Dashboard / Tickets / POS / Inventory / SMS / Reports / Dark mode / Glass nav / Offline / Settings.
- 6.3" iPhone: same set.
- 5.5" iPhone: legacy — 5 screenshots.
- 13" iPad (iPad Pro M4): 10 screenshots of 3-column splits.
- 12.9" iPad legacy: same.
- Mac "Designed for iPad": 5 screenshots.

### 96.2 App preview videos
- 30s loop per device family.
- Music: none (keeps focus).
- Narrated captions (localized per market).

### 96.3 Description
- 300 chars promo — "Run your repair shop from anywhere."
- 4000 chars long — features enumerated.
- Keywords — repair, crm, pos, tickets, sms, inventory, invoice, shop, field, service (avoid competitor names).

### 96.4 Privacy
- Data Collection: none off-device (per §32).
- Privacy manifest (`PrivacyInfo.xcprivacy`) declares no tracking domains.

### 96.5 Review notes
- Demo account: `demo@bizarrecrm.com / ReviewTeam2026!` → pre-seeded tenant.
- Server URL field: `https://demo.bizarrecrm.com`.
- BlockChyp: POS available with test card sim (no real charges).

### 96.6 What's New
- Short changelog per release. Don't dump diff.

---

## 97. TestFlight rollout plan

### 97.1 Internal (team)
- 25 internal testers. Fastlane lane `beta_internal` uploads on each main-branch merge.
- Smoke tests: launch, login, view ticket, POS dry-run.

### 97.2 External — closed cohort
- 100 external testers = existing customers who opted in.
- Invite via email; 7-day test window per build.
- Feedback form in-app: Settings → "Beta feedback" → composer.
- Don't ship to cohort if internal smoke failed.

### 97.3 External — public
- Up to 10,000 testers; public link.
- Opens Phase 5+.

### 97.4 Phased release on App Store
- 1% → 2% → 5% → 10% → 20% → 50% → 100% over 7 days.
- Pause if crash-free sessions < 99.5% (measured via own MetricKit telemetry).

### 97.5 Rollback
- On crash-free < 99.0% rollback to previous binary via Phased Release pause + new build.
- Never remove from sale unless security-critical.

---

## 98. Accessibility QA scripts

Manual test scripts run before every major release. 15 min each.

### 98.1 VoiceOver script
1. Launch app.
2. Swipe right through Dashboard — every KPI announced with label + value.
3. Open Tickets list — each row announces "Customer X, device Y, status Z, $amount".
4. Open a ticket — headers announce role=heading.
5. Create a ticket — every field has label; required fields announce "required".
6. POS — add item, announce running total on change.
7. SMS compose — dictation and send accessible.

### 98.2 Dynamic Type script
- Set Dynamic Type to xxxLarge in Settings → Accessibility.
- Walk every screen. No truncation, no overlap, no horizontal scroll on supposed-vertical layouts.

### 98.3 Reduce Motion script
- Enable. Launch app. No parallax, no spring bounces, transitions ≤ 150ms crossfade.

### 98.4 Reduce Transparency script
- Enable. Glass becomes opaque tint. Legibility maintained.

### 98.5 Increase Contrast script
- Enable. All text / icons ≥ 7:1 contrast (AAA).

### 98.6 Voice Control script
- Enable. Say "Tap Tickets". Check all interactive elements have names.

### 98.7 Switch Control script
- Enable virtual switch. Walk Dashboard → Ticket detail → Save. All reachable.

### 98.8 One-handed mode
- Enable Reachability. Primary actions stay in thumb zone (bottom 1/3).

---

## 99. Performance budgets — detailed

### 99.1 Cold launch
- **p50** ≤ 900ms on iPhone 13 mini.
- **p95** ≤ 1500ms.
- Enforced via XCTMetric on CI; PR blocked if regresses > 10%.

### 99.2 Warm launch
- ≤ 400ms.

### 99.3 First meaningful paint (Dashboard)
- ≤ 1200ms from launch.
- Renders cached data first, then refresh.

### 99.4 Scroll fps
- 120fps on ProMotion iPad; 60fps minimum on iPhone SE 3.
- Instruments Time Profiler run per release on the three largest lists (Tickets, Inventory, SMS thread).

### 99.5 Memory
- Resident ≤ 200 MB typical.
- Ticket create with 10 photos ≤ 400 MB peak.
- Nuke image cache capped 500 MB disk / 50 MB memory.

### 99.6 Disk
- App binary ≤ 60 MB (after App Thinning).
- User data typical ≤ 100 MB; large tenant ≤ 1 GB.
- SQLCipher DB grows predictably; vacuum every 30 days idle.

### 99.7 Battery
- Background sync should not exceed 1% / hour device battery on active day.
- Location collection (Field Service) opt-in only; background location disabled by default.

### 99.8 Network
- < 10 MB / day typical.
- < 100 MB / day heavy user.
- Image cache hit rate > 85%.

### 99.9 Starts-per-crash
- ≥ 10,000.

### 99.10 Hang rate
- < 0.1% sessions with hang > 2s.

---

## 100. Final micro-interactions polish

The difference between "works" and "feels Apple-native" is 1000 tiny details. Catalog:

### 100.1 Haptics on everything tactile (see §69)
- Button press: `.selection`.
- Save success: `.success`.
- Delete confirm: `.warning`.
- Payment approved: `.success` + brief success sound.

### 100.2 Spring animations
- `BrandMotion.springSoft` for layout shifts (bouncy, 0.35s).
- `BrandMotion.springSnap` for selection (crisp, 0.22s).
- All gated by Reduce Motion.

### 100.3 Focus rings
- `.focusEffect` on Mac / iPad Magic Keyboard — blue ring on focused row / field.

### 100.4 Keyboard avoidance
- Forms use `.scrollDismissesKeyboard(.interactively)` + `.defaultScrollAnchor(.bottom)` during compose.

### 100.5 Pull-to-refresh
- `.refreshable { ... }` on every list.
- Haptic on release.

### 100.6 Swipe gestures
- Swipe right on ticket row: "Start".
- Swipe left: "Archive" (destructive tint).
- Long-swipe triggers without lift (standard Apple).

### 100.7 Empty states
- Each list empty state has an illustration (SF Symbol or brand) + one-sentence explanation + CTA button.
- No "No data" dead text.

### 100.8 Skeleton loading
- Shimmer skeletons for lists (3 rows) while first page loads.
- Matches row height / layout of real rows (prevents jump).

### 100.9 Scroll position memory
- Lists remember position when returning from detail (`@Environment(\.scenePhase)` + NavigationStack path).

### 100.10 Inline validation
- Email / phone / IMEI validate as user types with green check / red x.
- Never show error until first blur or submit.

### 100.11 Sheet detents
- `.presentationDetents: [.medium, .large]` on composer sheets.
- Grab handle visible.
- Dismiss on swipe-down.

### 100.12 Context menus everywhere tappable
- Ticket row: Open / Copy ID / Share PDF / Archive / Delete.
- Customer row: Open / Call / Text / New Ticket / New Appointment.
- Invoice row: Open / Print / Share PDF / Mark Paid / Refund / Delete.

### 100.13 Copy actions
- Tap-and-hold IDs / emails / phone numbers → copy.
- Confirmation haptic + floating toast "Copied" (1.5s auto-dismiss).

### 100.14 Date pickers
- Inline wheel on iPhone compact; compact popover on iPad.
- Relative defaults: "Today", "Tomorrow", "Next week" chips above picker.

### 100.15 Search field affordances
- Clear button (x) on non-empty.
- Scope buttons underneath (Tickets / Customers / Inventory / Invoices) when Global Search active.
- Recent searches in empty state.

### 100.16 Loading buttons
- Submit buttons show spinner + disabled state during request.
- Never block full-screen; button-scoped only.

### 100.17 Success confirmations
- After save / payment / SMS send: toast at top with check icon, 2s auto-dismiss.
- On iPad, toast appears in top-right so it doesn't cover primary content.

### 100.18 Navigation titles
- Large-title on iPhone for top-level; inline for detail.
- iPad uses inline always (big-title wastes vertical).

### 100.19 Tint color
- `.tint(.bizarreAccent)` respected everywhere.
- Tenant theme overrides at app root.

### 100.20 Spacing rhythm
- 8 / 12 / 16 / 20 / 24 scale (tokens in §30).
- Never hand-rolled paddings.

---

## 101. Feature-flag system

Gate risky features per tenant / per user without shipping new builds.

### 101.1 Source of truth
- Tenant server endpoint `GET /feature-flags` returns `{ flag_name: bool | enum }` at login and on silent-push trigger `flags_updated`.
- Cached in Keychain (so offline launches still know feature state).

### 101.2 Rollout strategies
- **Per tenant** — `pos_blockchyp` enabled for tenants with BlockChyp creds configured.
- **Per role** — `team_chat` enabled for non-cashier roles.
- **Per user** — beta-tester cohort for early features.
- **Percentage** — 10% of users see new Dashboard; bucket via stable hash of user ID.

### 101.3 Local override
- Debug drawer (§103) lets devs flip flags at runtime without server roundtrip.
- Override persists until session end.

### 101.4 Code surface
```swift
if FeatureFlag.isOn(.posBlockchyp) { ... }
```
- Unknown flag defaults to `false` (fail-closed for risky features) or `true` (for polish features). Attribute per flag.

### 101.5 Cleanup
- Flags live in a central `FeatureFlag.swift` enum with `isTransient: Bool`. Transient flags have a removal deadline; CI warns if past deadline.

### 101.6 Forbidden
- No feature flag for security-critical code paths (auth, token storage, PCI). Always on.

---

## 102. Tenant onboarding email templates (server-side, but iOS-driven)

When a shop owner signs up through iOS (§2.2), server sends a transactional sequence. iOS triggers via `POST /onboarding/kickoff` after sign-up succeeds.

### 102.1 Day 0 — Welcome
- Subject: "Welcome to BizarreCRM 👋"
- Body: login link + server URL + "Print the login for the cashier" button.

### 102.2 Day 1 — Import data
- Subject: "Move your old shop data over in 10 minutes."
- Body: deep-link to §50 Import wizard.

### 102.3 Day 3 — First ticket coached
- Subject: "Create your first repair ticket."
- Body: deep-link to `bizarrecrm://tickets/new`.

### 102.4 Day 7 — POS setup
- Subject: "Take your first payment this week."
- Body: links to BlockChyp order form + POS §16 tour.

### 102.5 Day 14 — Invite team
- Subject: "Add your team to BizarreCRM."
- Body: deep-link to §48 / §49 invites.

### 102.6 Day 30 — Feedback request
- Subject: "How's it going?"
- Body: in-app feedback form link + Apple Store review link if > 30d retention.

### 102.7 iOS responsibility
- Only trigger; server composes and sends.
- iOS renders a "Next steps" checklist mirroring the emails so in-app users see the same progression.

---

## 103. Debug drawer

Dev-only UI for inspecting app state. Enabled via 5-tap on version label in Settings § About (iOS tradition).

### 103.1 Sections
- **User** — id, email, role, tenant, last login.
- **Server** — base URL, version, health check response, pinned cert hash.
- **Flags** — all feature flags + toggles.
- **Database** — SQLCipher file size, table row counts, last vacuum.
- **Cache** — Nuke memory + disk usage, clear button.
- **Network log** — last 100 requests, tap to see full body.
- **Push** — device token, test-send button.
- **Sync queue** — pending writes, manual retry, clear queue (with confirm).
- **Crash log** — recent MetricKit crash diagnostics.
- **Clipboard** — show contents (dev-only sanity).
- **Environment** — build config, bundle ID, app version, OS version, device model.

### 103.2 Safety
- Hidden behind debug build + 5-tap gesture.
- If opened on App-Store build (tester cohort), banner: "DEBUG DRAWER — do not show customers."
- Does not bypass any permissions.

### 103.3 Exports
- Every panel has "Export" button → JSON share sheet. Useful for bug reports.

---

## 104. Offline-first data viewer

Even when offline, users should browse what they've seen before. §20 Offline/Sync defined storage; this defines UX.

### 104.1 Cached data lifetime
- Lists: 14 days TTL rolling.
- Detail: 30 days TTL.
- User can long-press refresh button → "Download for offline" — pins the record forever.

### 104.2 Offline banner
- Glass pill at top: "Offline — showing data from 2h ago." Tap → connectivity detail.
- When reconnects, pill fades out with check animation.

### 104.3 Stale indicator per record
- Rows show dot color: green (< 1h), yellow (< 24h), red (> 24h). Tap → "Last synced 3h ago."

### 104.4 Search works offline
- FTS5 index covers cached rows.
- "Search on server" row suggested at bottom when online.

### 104.5 Creates while offline
- Ticket create / expense create / customer create / SMS send all queue.
- Record shows "Pending upload" chip.
- On sync, chip flips to checkmark.

### 104.6 Conflicts on reconnect
- See §20.6 — conflict panel.

---

## 105. Notification channel management per iOS

iOS doesn't have Android-style channels, but we can approximate with multiple notification categories + in-app toggles.

### 105.1 Categories (registered at launch)
- `SMS_INBOUND` — incoming customer SMS.
- `TICKET_ASSIGNED` — new ticket on my queue.
- `TICKET_STATUS` — status changed on my tickets.
- `PAYMENT_RECEIVED` — invoice paid.
- `APPT_REMINDER` — upcoming appointment.
- `LOW_STOCK` — inventory threshold hit.
- `TEAM_MENTION` — mentioned in team chat.
- `ESTIMATE_APPROVED` — quote signed.
- `BACKUP_FAILED` — nightly backup error.
- `DAILY_SUMMARY` — end-of-day summary push.

### 105.2 Actions per category
- SMS_INBOUND: Reply / Mark Read / Call Customer.
- TICKET_ASSIGNED: Accept / Open / Snooze.
- PAYMENT_RECEIVED: Open Invoice / Send Receipt.
- TEAM_MENTION: Reply / Open.

### 105.3 User control
- Settings § Notifications → per-category toggle + per-category quiet hours.
- Overrides `UIApplication.registerForRemoteNotifications()` registration (we always register, but gate categories).

### 105.4 Interruption levels
- SMS_INBOUND = `.active` (default).
- TICKET_ASSIGNED = `.timeSensitive` (optional per user).
- BACKUP_FAILED = `.critical` (requires entitlement — request from Apple for ops-critical alerts).
- Default = `.passive` for summary pushes.

### 105.5 Sound / haptic
- SMS_INBOUND = custom brand SMS sound (short, polite).
- PAYMENT_RECEIVED = cash register ching.
- Others = default.
- Haptics follow §69 catalog.

### 105.6 Badge counts
- Combined count on app icon = unread SMS + assigned tickets + mentions.
- Tab-bar badges per tab.

---

## 106. Deep-link handoff web ↔ Android ↔ iOS

Same URL across platforms — each opens natively.

### 106.1 Universal Links
- `https://app.bizarrecrm.com/tickets/:id` → web on desktop, iOS on iPhone, Android on Android.
- `apple-app-site-association` file served at `/.well-known/apple-app-site-association`.
- `assetlinks.json` served for Android.

### 106.2 Custom scheme fallback
- `bizarrecrm://tickets/:id` when already inside iOS app and Universal Link fails.

### 106.3 URL table
See §68 — keep in sync. Key routes:
- `/tickets` — list.
- `/tickets/:id` — detail.
- `/tickets/new` — create sheet.
- `/customers/:id` — detail.
- `/pos` — POS.
- `/pos/sale/:id` — in-flight sale (shared to customer-facing display).
- `/reports/revenue`, `/reports/inventory`, …
- `/settings/:section`.
- `/public/tracking/:shortId` — unauthenticated tracking page.

### 106.4 Handoff `NSUserActivity`
- Viewing a ticket on iPhone → Mac nearby picks up same ticket view in web (if logged into browser at same tenant).
- `NSUserActivity.webpageURL` set to matching `https://app.bizarrecrm.com/...` URL.

### 106.5 AppClip
- Consider App Clip for public-tracking page (§55). Customer taps link, App Clip opens tracking without full install. Deferred past Phase 5.

---

## 107. Analytics event naming conventions

Per §32 all events flow to tenant server only.

### 107.1 Format
- `<domain>.<noun>.<verb>` lowercase snake.
- `tickets.ticket.created`, `pos.sale.completed`, `sms.message.sent`, `auth.login.success`, `sync.conflict.resolved`.

### 107.2 Payload
- `event_name: string`
- `timestamp: ISO-8601`
- `user_id: uuid` (hashed on server if needed)
- `tenant_id: uuid`
- `session_id: uuid` (per app launch)
- `device_model: string` (e.g. iPhone16,2)
- `os_version: string`
- `app_version: string`
- `properties: { ... }` — no PII; bounded vocabulary.

### 107.3 PII ban
- Never: customer names, phone, email, address, message content, photo URLs.
- OK: counts, durations, enum states, feature flags.

### 107.4 Session boundaries
- `session_id` created on `applicationWillEnterForeground` if no session or > 15min gap.
- Ends on `willResignActive` — buffer flushed.

### 107.5 Batching
- Client buffers events in SQLCipher.
- Flushed every 30s or 50 events, whichever first.
- Also flushed on background task grant.

### 107.6 Sampling
- Verbose events (scroll, tap) sampled at 10%.
- Lifecycle events (open, close, crash) 100%.

### 107.7 Bandwidth cap
- ≤ 10 KB / hour active use typical.
- Abort telemetry if device on cellular and user has "Low Data Mode" enabled (honor `NWPathMonitor.isExpensive + isConstrained`).

---

## 108. Sandbox vs prod tenant switching

Tenant admins often have both a prod shop and a sandbox (e.g. for training, testing).

### 108.1 Account menu
- User avatar dropdown in top bar → "Switch tenant" → list of tenants user belongs to.
- Each tenant shows badge: Production / Sandbox / Staging.
- Sandbox tenants render with orange top-bar accent so users can't confuse.

### 108.2 Data isolation
- Each tenant = separate SQLCipher DB.
- Switching closes current DB, opens new.
- No cross-tenant data ever in memory simultaneously (security).

### 108.3 Quick switcher
- ⌘⇧T on iPad keyboard.
- Sheet with recent tenants.

### 108.4 Remember last-used
- Relaunch opens last-used tenant. "Switch" always available.

### 108.5 Logout scope
- "Log out of current tenant" vs "Log out of all tenants" — distinct.

---

## 109. Local dev mock server

For offline development without real server.

### 109.1 Tech
- Swift package `MockAPI` — in-process server using SwiftNIO or `URLProtocol` subclass.
- Loads fixtures from §87 at launch.

### 109.2 Activation
- Debug build + env var `BIZARRE_MOCK=1` or Scheme toggle.
- Base URL auto-set to `https://mock.local`; PinnedURLSessionDelegate disabled.

### 109.3 Features
- Replays canned responses.
- Simulates latency via configurable delay.
- Simulates errors: set `BIZARRE_MOCK_ERRORS=401,500` to randomly inject.
- Simulates offline: `BIZARRE_MOCK_OFFLINE=1`.

### 109.4 Preview support
- Xcode SwiftUI Previews use MockAPI so every preview works without network.
- Each View has a `#Preview` with mock data.

### 109.5 Forbidden
- Never ships in Release configs (compile-time guard with `#if DEBUG`).

---

## 110. Accessibility labels catalog

A central file ensures consistency across screens.

### 110.1 Naming convention
`A11y.Tickets.createButton` — enum namespace per domain.

### 110.2 Label shape
- Button: imperative verb + what. "Create new ticket."
- Row: summary sentence. "Ticket 4821 for Acme Corp, iPhone 15, status Waiting, $250."
- Chart: trend summary. "Revenue last 30 days: trending up 12%, peak on April 12."
- Progress: percent + what. "Sync progress 60%."

### 110.3 Hints (`.accessibilityHint`)
- For gesture-heavy elements. "Swipe right to start ticket, left to archive."

### 110.4 Traits
- Headers: `.isHeader`.
- Primary actions: default (button).
- Decorative icons: `.accessibilityHidden(true)`.
- Interactive groups: `.accessibilityElement(children: .combine)` + custom label.

### 110.5 Localized
- Every label lives in `Localizable.strings` — never hand-strung.
- Pseudo-localization test (`xx-PS`) runs in CI to catch truncation.

### 110.6 Dynamic content
- Labels read from model, e.g. `a11yLabelForTicket(t)` — single source.
- Currency spoken as "two hundred fifty dollars" not "$250" (VoiceOver auto-handles `.currency` format).

### 110.7 Testing
- XCUITest's `accessibilityIdentifier` ≠ `accessibilityLabel`.
- Use `identifier` for automation, `label` for VoiceOver.

---

## 111. Camera stack details

### 111.1 Capture session architecture
- `AVCaptureSession` with `.photo` preset for still; `.hd1920x1080` for video.
- Device discovery: prefer `.builtInDualWideCamera` then `.builtInWideAngleCamera`.
- Zoom: pinch + tap-to-zoom. Cap at 2x on wide, 3x on tele, to avoid digital degradation.

### 111.2 Live preview
- `AVCaptureVideoPreviewLayer` in `UIViewRepresentable`.
- Glass-framed capture controls overlay (top: toggle flash + switch camera + close; bottom: shutter + thumbnail last photo + library).

### 111.3 Focus & exposure
- Tap-to-focus reticle animation (shrink from 100pt to 60pt with haptic).
- Long-press locks exposure + focus (AE/AF lock badge).

### 111.4 Photo output
- 2048px longest side JPEG quality 0.7.
- EXIF GPS stripped (privacy) unless tenant opts in.
- Orientation normalized.

### 111.5 Video output
- H.264 for compat; max 60s per clip.
- Audio opt-in checkbox per clip.

### 111.6 Low-light mode
- `preferredVideoStabilizationMode = .auto`.
- Night mode (iOS 26 API) auto-engages when scene darker than threshold.

### 111.7 Privacy
- Camera access requested just-in-time with clear rationale.
- Shortcut to iOS Settings if denied.

### 111.8 Integrations
- Feeds into §17.2 Barcode scan, §85.4 Photo attach, §17.6 Document scanner.

---

## 112. Voice memos attached to tickets

Technicians often want to dictate a diagnosis while hands are on the device.

### 112.1 Record
- Big mic button in ticket detail → hold-to-record (WhatsApp style).
- Swipe up to lock, continue hands-free.
- Real-time waveform rendering.

### 112.2 Transcript
- On release, on-device transcription via `SFSpeechRecognizer` (English first, expand locales per §27).
- Shows transcript draft under audio bubble.
- Tap transcript → edit.

### 112.3 Storage
- AAC 64kbps mono. Typical 60s = ~480KB.
- Upload to tenant server `/tickets/:id/voice-memos` with audio + transcript.

### 112.4 Playback
- In-app waveform scrubber.
- Speed: 1x / 1.5x / 2x.
- Skip silence toggle.

### 112.5 Privacy
- Transcript runs on device. Audio never leaves tenant boundary.
- Recording indicator (orange pill at top) per iOS rules.

### 112.6 Accessibility
- VoiceOver reads transcript.
- Subtitles surfaced for Reduce-Motion / deaf users.

---

## 113. Inventory receiving workflow

Receive shipments: verify PO, barcode-scan each unit, adjust stock.

### 113.1 Entry points
- From PO detail "Receive" button.
- From inventory top-level "Quick receive" for ad-hoc.

### 113.2 Scan & count
- Camera opens barcode scanner.
- Each scan: item matched → counter increments → row turns green.
- Unmatched item: prompt to assign SKU or add new.

### 113.3 Discrepancy handling
- Expected 10, received 9: prompt "Short by 1 — why?" (damaged / missing / backorder / mismatch).
- Expected 10, received 11: prompt "Extra 1 — why?" (bonus / mis-shipped / count error).

### 113.4 Price updates
- If cost changed on receipt, prompt to update average cost.
- Retail price auto-recompute via tenant markup rules.

### 113.5 Bin assignment
- After receiving, optional "Put away" step: scan bin barcode to record location.

### 113.6 Label printing
- Each new SKU or price change: print shelf tags via §114.

### 113.7 Completion
- Mark PO status = received (partial / full).
- Movements recorded with audit trail.

---

## 114. Label & shelf-tag printing

Beyond receipts (§39.4), users want product / shelf labels.

### 114.1 Label formats
- 1" × 2" dymo-style: SKU + barcode + name.
- 2" × 4": same + price.
- Shelf strip: price only, large.

### 114.2 Printer support
- Dymo LabelWriter wireless — USB-C / Wi-Fi.
- Zebra ZD421 — Bluetooth.
- Brother QL-820NWB — Wi-Fi.
- Fallback: print to PDF → AirPrint on label-capable printers.

### 114.3 Template editor
- Settings → Printing → Label templates.
- Drag-drop elements (SKU, barcode, name, price, date, custom text, logo).
- Preview at actual size.
- Save as named template.

### 114.4 Batch print
- From inventory list, multi-select → "Print labels" → choose template + copies per item.

### 114.5 Barcode rendering
- `CIFilter.code128BarcodeGenerator` / `CIFilter.qrCodeGenerator`.
- EAN-13 for retail; UPC-A for legacy; QR for inventory app deep-link.

### 114.6 Paper / ribbon detection
- If printer reports low paper, banner in app.

---

## 115. Re-order suggestion engine

Inventory decays; humans forget. App nudges.

### 115.1 Signals
- Stock level vs reorder point.
- Rolling 30-day sell-through rate.
- Seasonality (if enough history).
- Upcoming appointments that need specific parts.

### 115.2 UI
- Dashboard card "Re-order recommendations (8 items)".
- List sorted by urgency: items below reorder point first.
- Each row: current qty + recommended qty + supplier + cost estimate.
- Batch-select → "Create PO" opens filled draft.

### 115.3 Tuning
- Manager can override recommended qty per item.
- "Snooze" suggestion 7d/30d.
- Exclude item from suggestions (seasonal / discontinued).

### 115.4 Server math
- Heavy compute on server; iOS just renders.
- Endpoint `GET /inventory/reorder-suggestions`.

### 115.5 Notifications
- Weekly summary push: "3 critical items below reorder. Open list?"

---

## 116. Tax engine (deep-dive)

Accuracy here makes or breaks a POS.

### 116.1 Rule model
- Location → tax jurisdictions (state, county, city, district).
- Jurisdiction → rate + effective dates.
- Item → tax class (tangible / service / food / exempt).
- Customer → optional exempt certificate (non-profit, resale).

### 116.2 Compute
- Server authoritative: `POST /tax/compute { lines, location_id, customer_id }` → per-line tax + totals.
- iOS mirrors the logic for instant UX; server revalidates on save.
- Discrepancy > 1¢ triggers warning banner "Tax mismatch — server recalculated."

### 116.3 Rounding
- Per-line rounding vs aggregate — configurable in Settings § Tax.
- Default: aggregate, banker's rounding.

### 116.4 Compound taxes
- Canada GST/PST support.
- EU VAT — inclusive vs exclusive pricing toggle per tenant.

### 116.5 Returns
- Refund inherits original tax; system never re-computes for returns to avoid rate-change bugs.

### 116.6 Reports
- Tax liability by jurisdiction, by period — Reports tab (§14).
- Export for accountant (CSV, Xero, QuickBooks).

### 116.7 Address autocomplete
- Apple MapKit for address validation.
- Ensures city/state/zip match jurisdiction lookup.

### 116.8 Origin vs destination
- Tenant chooses sourcing rule per state (origin / destination / mixed).
- Stored in tenant settings.

### 116.9 International
- Dynamic currency conversion for tourist-friendly tenants (displays both currencies, charges local).
- Conversion rates fetched daily from tenant server (not third-party directly).

---

## 117. Loyalty engine (deep-dive)

§38 Memberships / §36 Marketing intersect here.

### 117.1 Point accrual
- Rule: X points per $1 spent, tunable per SKU / category.
- Bonus events: birthday (2x), membership tier (1.5x), promo codes.

### 117.2 Redemption
- Y points = $1 discount.
- Minimum redemption threshold.
- POS flow: at checkout, tap "Redeem points" → slider up to max.

### 117.3 Tiers
- Bronze / Silver / Gold auto-computed on trailing 12 months spend.
- Tier change triggers push + wallet pass update.

### 117.4 Wallet pass sync
- `/memberships/:id/wallet-pass` → `.pkpass` file with dynamic fields (points, tier).
- Push updates via PassKit `APNs` when points / tier change.

### 117.5 Expiry
- Points expire N months after earn. User sees "Expiring this month" banner.

### 117.6 History
- Customer detail → Loyalty tab: earn / redeem / expire rows.

### 117.7 Staff view
- Ticket / POS customer header shows tier + points with one-tap redeem.

---

## 118. Referral program

### 118.1 Referrer flow
- Customer detail → "Refer a friend" button.
- Generates unique link `https://app.bizarrecrm.com/r/:code`.
- Share sheet: SMS / Email / QR / Social.

### 118.2 Referee flow
- Tap link → web landing → enter info → first visit tagged with referral code.
- On first paid invoice, rewards trigger.

### 118.3 Rewards
- Configurable per tenant: fixed $ credit / % off / loyalty points / free service.
- Both referrer and referee can be rewarded; symmetric or asymmetric.

### 118.4 Fraud prevention
- Block self-referral (same device / email / phone).
- Require first invoice > $X threshold.
- Rate-limit per referrer (e.g., 5 rewards / month).

### 118.5 Tracking
- Referral dashboard: top referrers, conversion rate, revenue attributed.

### 118.6 Attribution models (from §259)
- First-touch (first visit wins).
- Last-touch (last referrer wins).
- Multi-touch (split credit).

### 118.7 Source breakdown (from §259)
- Google / Yelp / Facebook / Instagram / TikTok / walk-in / referral code.
- Customer can self-report source at intake.

### 118.8 Fraud (extended from §259)
- IP block / device-ID match on top of §118.4 rules.
- Same customer self-referring → blocked.

### 118.9 Payout (from §259)
- Staff manual trigger or automatic on referee's first paid invoice.
- Refund reversal revokes credit (ties to §132.2).

### 118.10 Dashboard (from §259)
- Top referrers leaderboard.
- Revenue attributable to referrals.
- Funnel: referrals sent → clicked → converted.

---

## 119. Commissions

For shops that pay techs / cashiers commission.

### 119.1 Rule config (Settings § Commissions)
- By role: cashier / tech / sales.
- Rate: flat % or tiered brackets (first $X @ 5%, next $Y @ 7%…).
- Base: gross revenue / net margin / labor hours.
- Per category override (higher commission on high-margin items).

### 119.2 Attribution
- Ticket assigned = commission split to assignee.
- POS sale = commission to cashier.
- Multi-party ticket splittable (40/60, etc.) via "Split commission" sheet.

### 119.3 Payout cycle
- Daily / weekly / biweekly / monthly.
- Auto-close period; report shows per-employee totals.

### 119.4 Employee view
- "My earnings" tile on their dashboard.
- Pay stubs list with PDF export.

### 119.5 Clawback
- Refund reverses commission on the original transaction.
- Store credit keeps commission (tenant-configurable).

### 119.6 Permissions
- Only admin sees others' commissions.
- Employees see only own unless elevated.

---

## 120. Cash-flow forecasting

### 120.1 Inputs
- Historical revenue + expenses.
- Scheduled AR (invoices due).
- Scheduled AP (PO payment terms).
- Recurring expenses.
- Upcoming appointments expected revenue.

### 120.2 Output
- 30 / 60 / 90 day projection chart.
- Low-cash alerts: "Projected balance drops below $X on <date>."

### 120.3 Scenarios
- "What if" sliders: delay PO, increase bookings, pause marketing.
- Compare baseline vs scenarios.

### 120.4 Compute
- Server side; iOS renders.
- Endpoint `GET /finance/forecast?horizon=90`.

### 120.5 Accuracy indicator
- Based on last N forecasts' accuracy vs actual. "Forecast confidence: 82%."

### 120.6 Export
- Share PDF to accountant / bank.

### 120.7 Privacy
- Never leaves tenant boundary. Forecast math is local-to-tenant-server.

---

## 121. Ticket templates & macros

### 121.1 Templates
- Pre-built ticket skeletons for common repairs: "iPhone screen", "Laptop keyboard", "TV board", etc.
- Template stores: device template ref, default services, default parts (with qty), est. labor minutes, default pre-conditions, default status.
- Picker in ticket create: "Start from template" button above blank form.

### 121.2 Macros
- Keyboard / action shortcuts to bulk-apply changes: "Mark all parts ordered", "Assign to bench lead + set status Awaiting", "Email customer + set status Ready".
- Managed in Settings → Macros.
- Triggered via ticket context menu or ⌘⇧M palette.

### 121.3 Tenant-wide vs personal
- Manager publishes templates; technicians save personal macros for their own workflows.

### 121.4 Share
- Export template as JSON; import on another tenant.

### 121.5 Version history
- Each template has a changelog; changes by manager notify assigned users.

---

## 122. Vendor management

### 122.1 Vendor record
- Name / contact / terms / payment method / default shipping / internal notes.
- Linked POs, bill history, on-time rate, avg lead time.

### 122.2 Preferred vendor per item
- Inventory item → default vendor. PO creation auto-selects.
- Alternate vendors ranked; manual override on PO.

### 122.3 Vendor performance
- Dashboard tile: "Vendors by on-time %".
- Alerts when vendor on-time drops below threshold.

### 122.4 Contact
- One-tap call / email / SMS.
- Thread preserved like customer threads.

### 122.5 1099 prep
- Tag vendors requiring 1099; year-end export aggregates payments.

---

## 123. Asset tracking — loaners, demo units, rentals

### 123.1 Asset record
- Asset ID, type, serial, purchase date, cost, depreciation, current status (available / loaned / in-repair / retired).
- Linked to customer if on loan.

### 123.2 Loaner flow
- Customer drops off device → staff taps "Issue loaner" → select asset → sign agreement (§124).
- Loaner returned → inspect → mark available.

### 123.3 Deposit handling
- Optional hold on card via BlockChyp; released on return.

### 123.4 Reminders
- Auto SMS to customer: "Your repair is ready; please return the loaner within 7 days."
- Escalation: manager alert if loaner overdue > 7d.

### 123.5 Depreciation
- Linear / declining balance.
- Dashboard shows asset book value.

### 123.6 Geofence (optional)
- Tenant can enable: alert if loaner GPS leaves metro area for > 24h. Opt-in + customer-consent required (privacy).

---

## 124. Scheduling engine

### 124.1 Appointment types
- Drop-off / pickup / consultation / on-site visit.
- Duration default per type.
- Resource requirement (tech, bay, specific tool).

### 124.2 Availability
- Staff shifts × resource capacity.
- Buffer times between appointments.
- Blackout dates (holidays).

### 124.3 Suggest engine
- Customer requests window → engine offers nearest 3 slots that satisfy resource + staff requirements.

### 124.4 Drag & drop calendar
- iPad mandatory (big screen). iPhone uses list-by-day.
- Drag appointment to reschedule → optimistic update + server confirm; rollback on conflict.

### 124.5 Multi-location
- View combines or filters locations (§63).

### 124.6 No-show tracking
- Stat per customer; tenant-configurable policy (deposit required after N no-shows).

---

## 125. Message templates (SMS + email)

### 125.1 Storage
- Templates stored on server; cached locally.
- Variables: `{{customer.first_name}}`, `{{ticket.id}}`, `{{ticket.status}}`, `{{link.public_tracking}}`, etc.
- Pre-view renders actual values for current context.

### 125.2 Categories
- Status updates, reminders, marketing, receipts, quotes, follow-ups.

### 125.3 Picker
- In SMS composer, "Templates" button opens bottom sheet grouped by category.
- Tap to insert; variables auto-fill; edit before send.

### 125.4 AI-assist
- §76 Apple Intelligence Writing Tools offers tone rewrites.

### 125.5 A/B testing
- Manager can define two variants; system splits sends 50/50 and tracks open / reply / revenue attribution.

### 125.6 Compliance
- Templates used for marketing must have unsubscribe link for SMS / email (TCPA / CAN-SPAM).
- System injects unsubscribe automatically.

---

## 126. Digital consents & waivers

### 126.1 Waiver documents
- Tenant uploads PDF waiver templates via web. iOS renders + allows signature.

### 126.2 Required contexts
- Drop-off agreement (liability, data loss, diagnostic fee).
- Loaner agreement (deposit, return date, fees).
- Marketing consent (SMS / email opt-in per TCPA).

### 126.3 UX
- Waiver sheet: scrollable text + `PKCanvasView` signature box + print name.
- Checkbox "I've read and agree" required before submit.
- Signed PDF emailed to customer automatically.

### 126.4 Storage
- PDF archived to tenant storage.
- Ticket detail shows "Signed waivers" card with tap-to-view.

### 126.5 Audit
- Audit log entry with timestamp + IP + device fingerprint + waiver version.

### 126.6 Re-sign on change
- If waiver text changes, existing customers re-sign on next drop-off.

---

## 127. Marketing campaigns (deep)

### 127.1 Campaign types
- SMS blast, email blast, push notification to app users, postcard (via integration), in-app banner.

### 127.2 Audience builder
- Segment by tag / last-visit window / LTV tier / device type / specific service history / birthday month.
- Save segments; reuse.

### 127.3 Scheduler
- Send now, send at time, recurring (weekly newsletter), triggered (birthday auto-send).

### 127.4 Compliance
- Quiet hours honored per locale.
- Unsubscribe suppression.
- Suppress test numbers.
- Consent date + source stored per contact.

### 127.5 Analytics
- Delivered / opened / clicked / replied / converted-to-revenue.
- Unsubscribe rate alarm at 2%+.

### 127.6 Budget cap
- Tenant sets monthly SMS spend cap; system halts sends when reached.

### 127.7 Preview
- Preview on iPhone skin (bubble) + email (HTML render).
- Dynamic variable substitution shown.

---

## 128. Recurring services & subscriptions

### 128.1 Use-cases
- Monthly maintenance plan, data-backup plan, service-contract plan.

### 128.2 Plan builder
- Name, cadence (monthly / quarterly / annual), price, included services count, auto-renew.

### 128.3 Enrollment
- Customer detail → Plans tab → Enroll. Collect card on file.
- Apple Pay / card tokenized via BlockChyp vault.

### 128.4 Billing engine
- Tenant server runs daily cron; creates invoices; charges cards; updates ledger.
- iOS shows "Next billing date" on customer detail.

### 128.5 Service ledger
- "Included services remaining this period: 3 of 5."
- When customer redeems service at POS, counter decrements.

### 128.6 Dunning
- Failed charge → retry 3 days / 7 days / 14 days + notify customer.
- After exhaustion: pause plan, notify staff.

### 128.7 Cancel flow
- Customer can self-cancel via public portal; staff can cancel via customer detail.
- End-of-period policy.

---

## 129. Service bundles & packages

### 129.1 Bundle = set of items sold together at discount
- Diagnostic + repair + warranty = bundle price.
- Data recovery + backup + return shipping = bundle.

### 129.2 Builder
- Settings → Bundles → Add. Drag items in, set bundle price (or "sum − %").

### 129.3 POS
- Bundles appear as single SKU; expanding shows included items.
- Partial-delivery support: "Diagnostic done, repair pending" tracks progress.

### 129.4 Inventory impact
- Each included item decrements separately on sale.

### 129.5 Reporting
- Bundle sell-through vs individual.
- Attach-rate reports.

---

## 130. On-device search indexer

§18 Global Search backed by FTS5; this is the indexer.

### 130.1 Pipeline
- On each GRDB insert/update of indexed models (tickets, customers, inventory, invoices, SMS messages), trigger updates matching FTS5 virtual table.
- Stop-word list per locale.
- Stem via Snowball (English) or language-specific.

### 130.2 Tables
- `ticket_fts`, `customer_fts`, `inventory_fts`, `invoice_fts`, `sms_fts`.
- Each mirrors searchable columns + `rowid` for join.

### 130.3 Rank
- BM25 (native FTS5).
- Boost recent records via timestamp factor.
- Exact-match IMEI / phone / email bumps top.

### 130.4 Synonyms
- Tenant-defined: "iphone" → "iPhone"; "lcd" → "screen"; "batt" → "battery".

### 130.5 Performance
- Cap index size per entity; rebuild on schema migration.
- Background incremental reindex in `BGAppRefreshTask`.

### 130.6 Privacy
- Full-text index lives inside SQLCipher; encrypted at rest.

### 130.7 Fuzzy
- Levenshtein edit distance up to 2 for short queries; fallback to substring.

---

## 131. Ticket state machine

### 131.1 States (tenant-customizable starting set)
`Intake → Diagnostic → Awaiting Approval → Awaiting Parts → In Repair → QA → Ready for Pickup → Completed → Archived`.
Branch: `Cancelled`, `Un-repairable`, `Warranty Return`.

### 131.2 Transition rules
- Each transition has optional pre-requisites: photo required, pre-conditions signed, deposit collected, quote approved.
- Transition blocked until satisfied. Inline error: "Can't mark Ready — no photo."
- Rules editable per tenant in Settings → Ticket statuses (§19.16).

### 131.3 Triggers
- Auto-SMS on specific transitions (Ready for Pickup → text customer).
- Assignment change auto-log.
- Idle-alert: in `Awaiting Parts` > 7d → reminder push to manager.

### 131.4 Bulk transitions
- Multi-select tickets → "Move to Ready" menu action.
- Rules enforced per ticket; skips blocked with summary.

### 131.5 Rollback
- Admin role only. Rollback transitions create audit entry with reason.

### 131.6 Visual
- Color per state (tenant-configured).
- State pill on every list row + detail header.

### 131.7 Charts
- Funnel chart in Reports: count per state + avg time-in-state.
- Bottlenecks highlighted if avg > tenant benchmark.

---

## 132. Returns & RMAs

### 132.1 Return types
- Customer returns goods sold.
- Technician returns defective parts to vendor.

### 132.2 Return flow (customer)
- From invoice detail: "Return items" → pick lines + quantities → reason → refund method (original / store credit / gift card).
- Creates Return record linked to invoice.
- Updates inventory.
- Reverses commission (§119.5 unless policy).

### 132.3 Return flow (vendor)
- From PO / inventory: "Return to vendor" → pick items → RMA # (manual or vendor API) → print shipping label.
- Status tracks: pending / shipped / received / credited.

### 132.4 Restocking fee
- Tenant policy per item class; applied optionally.

### 132.5 Receipts
- Return receipt prints with negative lines + refund method + signature line.

### 132.6 Restock choice
- Option per item: return to salable / scrap / damaged bin.

### 132.7 Fraud guards
- Warn on high-dollar returns > threshold.
- Require manager PIN override.

---

## 133. Quote e-sign

### 133.1 Quote detail → "Send for e-sign"
- Generates public URL `/public/quotes/:code/sign`.
- SMS / email with URL.

### 133.2 Signer experience (public page)
- Web view; doesn't require login.
- Reads quote line items, total, terms.
- Signature box + print name + date.
- Submit → stores PDF + signature.

### 133.3 iOS notification
- On sign, push to staff: "Quote #42 signed by Acme Corp — convert to ticket?"
- Deep-link opens quote in app; one-tap convert (§9.1).

### 133.4 Expiry
- Signable within N days (tenant-configured); after expiry, page shows "Quote expired — contact shop."

### 133.5 Audit
- Each open / sign event logged with IP + user-agent.

---

## 134. Image annotation detail (supersedes §85.4)

### 134.1 Tools
- Pen: thickness slider, color swatch (10 presets + custom).
- Highlighter: semi-transparent yellow / pink / green.
- Arrow: straight, auto-head.
- Rectangle / oval / freehand shape.
- Text box with font size + color.
- Eraser (vector-aware).
- Undo / redo unlimited within session.

### 134.2 Palette
- Swatches styled as glass chips.
- Tenant brand color auto-added.

### 134.3 Stamp library
- Arrow / star / circled number / condition tags ("cracked", "dented", "missing").
- Drag-drop anywhere.

### 134.4 Layers
- Base photo + annotation layer stored separately (can remove annotations, revert to original).
- Export flattens.

### 134.5 Apple Pencil
- Pressure + tilt supported on `PKCanvasView` / `PencilKit`.
- Palm rejection on iPad.
- Double-tap Pencil to toggle last tool.

### 134.6 Crop / rotate / enhance
- Standard `UIImagePickerController`-style crop UI.
- Auto-enhance one-tap (brightness / contrast).

### 134.7 OCR
- `VNRecognizeTextRequest` captures visible text.
- "Copy text from image" context action.

---

## 135. Dead-letter queue viewer

§20 sync + retry defined behavior; this defines the UI when retries exhaust.

### 135.1 Location
- Settings → Diagnostics → Dead-letter queue (or Debug Drawer §103).

### 135.2 Item row
- Action type (create-ticket / update-inventory / …), failure reason, first-attempted-at, last-attempt-at, attempt count, last-error.

### 135.3 Actions
- Retry now.
- Retry later.
- Edit payload (advanced — power users only).
- Discard (confirmation required).

### 135.4 Visibility
- Banner in app root if dead-letter count > 0: "3 changes couldn't sync — open to fix."

### 135.5 Auto-escalation
- Dead-letter > 24h old → notify tenant admin via email through server (not iOS).

### 135.6 Data preservation
- Before discard, offer "Export JSON" so user can manually reapply elsewhere.

---

## 136. DB schema migration strategy

### 136.1 Versioned migrations (GRDB.DatabaseMigrator)
- Each schema change = named migration in `Core/DB/Migrations/` — immutable once shipped.
- Migration table records applied names; app refuses to launch if a known migration is missing.

### 136.2 Forward-only
- No downgrades. If user reverts iOS app via TestFlight, they get "Database newer than app — contact support".

### 136.3 Large tenants
- Long migrations split into batches; progress sheet shown: "Migrating 50% — please wait."
- Backgrounded via `BGProcessingTask` so user can leave app.

### 136.4 Backup before migration
- SQLCipher file copied to `~/Library/Caches/pre-migration-<date>.db` before applying.
- Kept 7 days or until next successful launch.

### 136.5 Dry run
- Debug builds run migrations on backup first; report diff before real apply.

### 136.6 Test data
- CI runs each migration against minimal + large fixture DBs.

---

## 137. In-app bug report form

### 137.1 Entry
- Settings → Help → "Report a bug".
- Debug-drawer shake-to-report (iOS 17 `UIDevice.deviceShakeGesture` deprecated — use `UIResponder.motionEnded` on hidden view).

### 137.2 Fields
- Description (freeform, required).
- Category (crash / UI bug / data issue / perf / feature request).
- Severity.
- Optional: attach screenshot (captured automatically + annotatable), attach recent logs, attach last crash report.

### 137.3 Submission
- POST `/support/bug-reports` with payload + attachments.
- Server issues ticket number; iOS shows "Thanks — ticket BG-234 created."

### 137.4 Follow-up
- Status updates via Notification center when devs respond.

### 137.5 PII guard
- Logs scrubbed for tokens / PII via redaction rules before attach.

### 137.6 Offline
- Queue; submit on reconnect.

---

## 138. In-app changelog viewer

### 138.1 What's new sheet
- On first launch of a new version, modal sheet: "What's new in X.Y.Z".
- Text fetched from `/app/changelog?version=X.Y.Z` — controlled per locale.

### 138.2 Full history
- Settings → About → Changelog → scrollable list.
- Each entry: version + date + highlights + "Read more" deep link to blog.

### 138.3 Opt-out
- "Don't show on launch" checkbox.

### 138.4 Server-driven
- Allows post-launch content updates without app re-release.

### 138.5 Offline
- Changelog cached last-N-versions.

---

## 139. Privacy-data-subject requests (GDPR / CCPA)

### 139.1 Customer self-service
- Public portal `/public/privacy` — enter email / phone → OTP verify → options:
  - Export my data (ZIP: tickets, invoices, SMS history, photos, invoices).
  - Delete my data.
  - Opt out of marketing.

### 139.2 Staff-side
- Customer detail → Privacy actions menu.
- Export: builds ZIP; delivered via tenant email to customer.
- Delete: tombstones PII but preserves financial records (legal retention); replaces name with "Deleted Customer" + anonymizes; receipts / invoices keep aggregated numbers.

### 139.3 Audit
- Every request logged (who asked, when, outcome).

### 139.4 Sovereignty
- All processing on tenant server. No third-party data processors.

### 139.5 Opt-out flags
- Respect `do_not_call` / `do_not_sms` / `do_not_email` on customer record.
- System blocks sends if flag set; warning in composer.

---

## 140. Apple Pay wallet integration details

### 140.1 POS checkout
- Apple Pay button on cart (PKPaymentButton).
- Customer taps → Face ID → tokenized payment → BlockChyp gateway (§16.2).
- Fallback: tap-to-insert card if Apple Pay unavailable.

### 140.2 In-app charges
- Public payment links (§41) support Apple Pay via `PKPaymentAuthorizationController`.
- Merchant ID: `merchant.com.bizarrecrm`.

### 140.3 Apple Pay Later
- Not initially — leave to BlockChyp integration; re-evaluate post Phase 5.

### 140.4 Pass management
- Membership pass (§38 / §117.4) + gift card (§40) + loyalty = three distinct pass types.
- Update via APNs for PassKit.

### 140.5 ApplePay Merchant verification
- Domain verification for public payment pages (upload file to /.well-known/).

### 140.6 Tap to Pay on iPhone
- iPhone XS+ with entitlement → contactless cards accepted without dongle.
- Requires Apple Developer approval (separate from BlockChyp).
- Phase 4+ — large integration with its own evaluation.

### 140.7 Sovereignty
- Tokens handled by Apple + BlockChyp. No raw PAN ever on our server or iOS app.

---

## 141. Location manager & geofencing

### 141.1 Uses
- Field-service route (§59).
- Stolen-device recovery (loaner geofence §123.6).
- Auto-clock-in on arrival to store (opt-in, §48).
- Tax location detection for mobile POS (§116).

### 141.2 Permission
- Request `whenInUse` first; step up to `always` only for field-service techs.
- Never background-track non-field users.
- Precise vs approximate: approximate default; precise only when geocoding or routing.

### 141.3 Power
- Significant-location-change for background; no raw GPS.
- Stop updates when leaving app unless `always` granted.

### 141.4 Privacy
- All location data flows to tenant server only (§32 rule).
- Settings → Privacy → Location → show what's tracked + toggles + history export + delete history.

### 141.5 Accuracy thresholds
- < 20m for on-site check-in.
- < 100m acceptable for route planning.

### 141.6 Indoor fallback
- If GPS weak (basement / metal), use cell+wifi heuristics; degrade gracefully.

---

## 142. Background tasks catalog

All `BGTaskScheduler` registrations in one place.

| Identifier | Type | Purpose | Cadence |
|---|---|---|---|
| `com.bizarrecrm.sync.delta` | `BGAppRefreshTask` | Delta-sync cached lists | ~15min when backgrounded |
| `com.bizarrecrm.queue.flush` | `BGProcessingTask` | Retry pending writes | nightly + reconnect |
| `com.bizarrecrm.index.rebuild` | `BGProcessingTask` | FTS5 reindex | weekly |
| `com.bizarrecrm.vacuum` | `BGProcessingTask` | SQLCipher vacuum | 30 days idle |
| `com.bizarrecrm.photos.upload` | `URLSession` bg upload | Ship queued photos | on reconnect |
| `com.bizarrecrm.telemetry.flush` | `BGAppRefreshTask` | Send buffered events | ~30min |
| `com.bizarrecrm.backups.export` | `BGContinuedProcessingTask` (iOS 26) | Long-running export | on-demand |

### 142.1 Registration
- In `App.init()` before any `.task`.
- Each handler completes promptly; if cancelled, re-queue for next window.

### 142.2 Quota
- iOS grants finite background time. Track usage via MetricKit to ensure we stay friendly.

### 142.3 Testing
- `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"..."]` in debugger.

---

## 143. WKWebView policy

### 143.1 Primary rule
- iOS is native-first. `WKWebView` only for embedded PDF viewers, receipts, and the help center.
- Never load third-party sites.

### 143.2 Config
- JavaScript enabled only when strictly needed.
- Cookies isolated in per-WebView `WKWebsiteDataStore.nonPersistent()`.
- User-agent suffix identifies the app for telemetry.

### 143.3 Links out
- External links open in `SFSafariViewController` — never inline.

### 143.4 Tenant server only
- `WKNavigationDelegate` rejects any URL not on `APIClient.baseURL.host` allowlist for in-app webviews.

### 143.5 Content security
- CSP headers set on server for in-webview pages; verified on launch.

---

## 144. Image caching & CDN

### 144.1 Nuke pipeline
- `ImagePipeline.Configuration` — disk cache 500MB, memory 50MB.
- Prefetch on list scroll.
- Progressive JPEG where supported.

### 144.2 Cache key
- `url.absoluteString`. No query-string churn; include content hash where we control URLs.

### 144.3 Invalidation
- On photo edit / replace, server returns new `updated_at` → new URL segment `?v=<hash>`.

### 144.4 CDN
- Tenant server is origin.
- Optional: tenant-managed CDN in front (Cloudflare). If present, iOS fetches from CDN; telemetry still reports to tenant server (not CDN).

### 144.5 Offline
- Nuke disk cache = offline image store.
- Tenant-configured TTL.

### 144.6 Low-data mode
- Honor `NWPathMonitor.isConstrained` — fetch thumbnails only; full-res on tap.

---

## 145. Automated accessibility audits

### 145.1 CI step
- Xcode 26 `XCUIAccessibilityAudit` runs on every PR.
- Fails on issues of category: missing label, poor contrast, element too small, inaccessible text.

### 145.2 Scope
- All golden-path XCUITests opt in with `try app.performAccessibilityAudit()`.

### 145.3 Exceptions
- Decorative imagery marked `.accessibilityHidden(true)` by design — audit skips.
- Documented exceptions in `Tests/Accessibility/Exceptions.swift`.

### 145.4 Manual cadence
- §98 manual QA scripts every release.

### 145.5 Reporting
- Audit results attached to CI run; trend tracked over time.

---

## 146. Dependency injection architecture

### 146.1 Factory DI
- `Container` exposes `@Injected(\.apiClient)` style keys.
- All services registered in `Container+Registrations.swift` at launch.

### 146.2 Scopes
- `cached` — process-wide (APIClient, DB, Keychain).
- `shared` — weak shared per object graph (ViewModels).
- `unique` — each resolve builds fresh.

### 146.3 Test doubles
- Test bundle swaps registrations via `Container.mock { ... }` per test.
- No global state leaks between tests (assertions in `setUp`).

### 146.4 No singletons outside Container
- Ban `static shared = ...` except for Container itself.

### 146.5 Cross-target sharing
- Widgets / Intents targets import `Core` module; register their own Container sub-scope.

---

## 147. Error taxonomy

### 147.1 Top-level enum
```swift
enum AppError: Error {
  case network(Underlying)
  case server(status: Int, message: String, requestID: String?)
  case auth(AuthReason)
  case validation([FieldError])
  case notFound(entity: String, id: String)
  case permission(required: Capability)
  case conflict(ConflictInfo)
  case storage(StorageReason)
  case hardware(HardwareReason)
  case cancelled
  case unknown(Error)
}
```

### 147.2 User-presentable
- Each case has `title`, `message`, `suggestedActions: [AppErrorAction]`.
- Actions include retry, open-settings, contact-support, dismiss.

### 147.3 Logging
- Errors logged with category + code + request ID (no PII).

### 147.4 Localization
- All user-facing strings via `Localizable.strings`.

### 147.5 Reporting
- §93 maps taxonomy to recovery UI.

---

## 148. Logging strategy

### 148.1 Framework
- Apple unified logging (`Logger(subsystem: "com.bizarrecrm", category: "...")`).
- Categories: `net`, `db`, `ui`, `sync`, `auth`, `perf`.

### 148.2 Levels
- `debug` — dev only; compile-stripped in Release.
- `info` — lifecycle + meaningful events.
- `notice` — user-visible events (logins, sales).
- `error` — recoverable failures.
- `fault` — state we never expect (triggers crash analytics).

### 148.3 Redaction
- Default `privacy: .private` on all dynamic params; explicit `.public` only for IDs + enum states.

### 148.4 Retention
- System handles retention. We don't ship our own ring buffer (duplicative).

### 148.5 Exfil
- Bug reports (§137) ship `sysdiagnose`-style redacted bundle when user opts in.
- Never auto-upload logs.

### 148.6 Sovereignty
- Logs stay on device unless user explicitly sends in bug report, which goes to tenant server.

---

## 149. Build flavors / configs

### 149.1 Schemes
- **Debug-Dev** — local mock server (§109), verbose logging, debug drawer, feature flags override.
- **Debug-Staging** — staging.bizarrecrm.com, real API, relaxed TLS.
- **Release-Staging** — TestFlight staging.
- **Release-Prod** — App Store.

### 149.2 xcconfig
- `Config/Debug-Dev.xcconfig` etc.
- Shared base `Config/Base.xcconfig` for constants.

### 149.3 Feature gating
- Compile flags: `DEBUG`, `STAGING`, `RELEASE`.
- No flag-specific code paths in release (compile-time guard).

### 149.4 App icon variant
- Dev icon = brand + "D" badge.
- Staging icon = brand + "S" badge.
- Prod = clean.
- Avoids user confusion switching between TestFlight + App Store.

### 149.5 Bundle IDs
- Dev: `com.bizarrecrm.dev`
- Staging: `com.bizarrecrm.staging`
- Prod: `com.bizarrecrm`
- Separate App Store Connect entries; separate provisioning.

---

## 150. Certificates & provisioning

### 150.1 Fastlane match
- Centralized Git-encrypted cert/profile store.
- Lanes: `match development`, `match appstore` — zero manual Xcode signing.

### 150.2 Dev team
- `DEVELOPMENT_TEAM` kept out of `project.yml` (per CLAUDE.md).
- Developers set once via Xcode UI after clone.
- CI reads from secret env.

### 150.3 Push entitlement
- Production APNs cert rotated annually.
- Fastlane action handles regeneration + upload to tenant server (for server-side APNs auth).

### 150.4 Associated-domains
- `applinks:app.bizarrecrm.com` in entitlements.
- Verified via Apple's CDN; recheck during release.

### 150.5 Capabilities
- Keychain sharing (`group.com.bizarrecrm`), App Groups, Sign in with Apple (future), CarPlay (pending approval §82), CriticalAlerts (pending approval §105.4), HealthKit (no — unrelated).

### 150.6 2FA on developer account
- Required. Shared dev account uses YubiKey + documented recovery process in internal wiki.

---

## 151. Siri & App Intents (deep)

### 151.1 Intents catalog
- `CreateTicketIntent` — params: `customerName?`, `deviceTemplate?`, `reportedIssue?`. Opens draft or directly creates if all params present.
- `LookupTicketIntent` — param: `ticketID | customerName`. Returns status + ETA.
- `ClockInIntent` / `ClockOutIntent` — no params.
- `StartSaleIntent` — POS empty cart.
- `ScanBarcodeIntent` — opens scanner.
- `TakePaymentIntent` — param: `invoiceID`.
- `SendTextIntent` — params: `customerPhone`, `body`.
- `NewAppointmentIntent` — params: `customer?`, `date?`, `duration?`.
- `StartBreakIntent` / `EndBreakIntent`.
- `TodayRevenueIntent` — read-only, returns number for Siri to speak.
- `PendingTicketsCountIntent` — read-only, speaks count.
- `SearchInventoryIntent` — param: `query`.

### 151.2 Donation
- Donate each intent on use via `INInteraction` so Siri suggests context-aware shortcuts ("Clock in" near 9am near shop location).

### 151.3 Focus-aware
- Intents respect Focus mode (§152); "Send Text" disabled in DND unless urgent.

### 151.4 Parameter resolution
- Ambiguous customer → Siri disambiguates: "Which John do you mean?"
- Fuzzy match via §130 FTS5.

### 151.5 Output UI
- Every intent has `IntentView` (SwiftUI) rendered inline in Shortcuts preview + Siri output.
- Glass-styled card matching app aesthetic.

### 151.6 Privacy
- Intent params + results stay on device / tenant server. No Apple Siri-analytics integration.

### 151.7 iOS 26 App Intents
- `AssistantSchemas.ShopManagement` (hypothetical iOS 26 domain) registered; exposes common nouns (Ticket, Customer, Invoice) to system.
- Apple Intelligence can orchestrate ("Remind me when ticket 4821 is ready") without us writing reminder logic.

### 151.8 Testing
- Shortcuts app gallery + XCUITest to verify each intent runs headless.

---

## 152. Focus Modes integration

### 152.1 Work focus filter
- App exposes `FocusFilterIntent` so tenant users can add a "Shop hours" filter.
- Params: `tenantID`, `location?`, `role?`.
- Activation hides personal-feeling badges / non-critical notifications; surfaces only assigned tickets.

### 152.2 Driving focus
- Suppress non-critical pushes automatically.
- Show CarPlay (§82) only content if CarPlay entitlement approved.

### 152.3 Sleep focus
- All pushes suppressed except `.critical` (backup failure).

### 152.4 Custom per-tenant focus
- Tenants with multi-location can have per-location focus filters ("Store A only").

### 152.5 User UI
- Settings → Focus integration → list of active filters + preview.

---

## 153. Multi-window / Stage Manager (iPad)

### 153.1 Scene types
- Primary scene — full app (sidebar + list + detail).
- Secondary scene — single ticket detail.
- Tertiary scene — POS register.
- Quaternary scene — reports / charts dashboard.

### 153.2 Drag-to-new-window
- Long-press ticket row → drag out → iPad opens new window with that ticket.
- Long-press POS tab → new window dedicated to register.

### 153.3 State restoration
- `NSUserActivity` per scene persists position / ticket ID.
- Relaunch re-opens all windows.

### 153.4 Window-class adapters
- Each scene declares capabilities: "can show ticket detail", "can run POS".
- Drag-drop between windows validates target capability.

### 153.5 Stage Manager sizing
- Minimum 700×500 content area.
- Below min, compact layout kicks in.

### 153.6 External display
- `UIScene` for external display hosts customer-facing display (§16.15) mirrored from POS scene.

### 153.7 Menu bar
- `UICommand`s per scene (File / Edit / View / Window / Help) with standard + custom actions (New Ticket, Quick Find, Switch Tenant).

---

## 154. watchOS companion — re-scope

Deferred. Keep as stretch.

### 154.1 Candidate scope
- Glance: pending tickets count, today revenue.
- Quick clock in/out complication.
- Incoming SMS notification forward.
- No data entry — read-only plus two actions (clock + accept ticket).

### 154.2 Architecture
- WatchConnectivity keeps session with iPhone.
- Data fetched from phone (which holds session); watch never talks directly to server.
- Fallback: direct tenant-server request when iPhone unreachable — uses shared Keychain token.

### 154.3 Complications
- Circular: ticket count.
- Rectangular: today revenue.
- Corner: clock status.

### 154.4 Gate
- Skip Phase 1–5. Evaluate post 1.0.

### 154.5 Sovereignty
- All data tenant-scoped; no Apple HealthKit or third-party integration.

### 154.6 If revived (from §297)
- Smart Stack widgets first; watchOS app later.
- Complication tint follows user's watch face tint.
- StandBy overlap: similar data surfaced; keep tokens consistent.

---

## 155. iPhone Mirroring & Continuity Camera

### 155.1 iPhone Mirroring (macOS 15+)
- App supports keyboard + mouse when mirrored; already inherits from iPad handling.
- No special code needed; test on Mac to confirm glass + blur render OK.

### 155.2 Continuity Camera
- Use iPhone rear camera from Mac running app via Continuity Camera for higher-res photos of devices.
- SwiftUI `ImagePicker` auto-offers Continuity when Mac + nearby iPhone.

### 155.3 Handoff
- Start composing SMS on iPhone → continue on Mac (NSUserActivity hands off thread).

### 155.4 Universal Clipboard
- Copy on iPhone, paste on Mac (and vice versa) within app.

### 155.5 AirDrop
- Send PDF / receipt / ticket to nearby device.

### 155.6 Sidecar (iPad as Mac display)
- Detect Sidecar → prefer detail-heavy layout on iPad side.

---

## 156. Print engine (deep)

### 156.1 AirPrint path
- `UIPrintInteractionController` for documents (receipts / tickets / invoices).
- Page renderer uses `UIPrintPageRenderer` subclass for header/footer per template.

### 156.2 Paper sizes
- Letter (US), A4 (EU), Legal, 4x6 (receipt), 80mm thermal (receipt).
- User picks default in Settings → Printing.

### 156.3 Thermal printer (non-AirPrint)
- Star SDK / Epson ePOS SDK via Swift wrapper.
- Connection types: Bluetooth MFi / Wi-Fi / USB (via Lightning/USB-C).
- Each tenant configures printer(s); multi-printer per station.

### 156.4 Print queue
- `PrintService` class with queue; retries on failure; shows toast "Print queued, 1 pending".
- Reprint button in queue UI.

### 156.5 Cash drawer
- Star/Epson thermal printers fire drawer kick on cash tender (§39).

### 156.6 Preview
- Always preview before print; mini render of first page.

### 156.7 PDF fallback
- If no printer available, PDF share-sheet automatically offered.

### 156.8 Receipt templates (Settings → Printing)
- Header logo, shop info, tagline.
- Body layout: lines, totals, payment, tax.
- Footer: return policy, thank-you, barcode for lookup.
- Live preview.

### 156.9 Offline print
- Print works offline — printer on local network or Bluetooth doesn't need internet.

---

## 157. Haptic custom patterns — MERGED INTO §69

Content moved to §69.1 + §69.2. Number preserved.

---

## 158. Screen capture / screenshot consent

### 158.1 Screen protection
- `UIScreen.capturedDidChangeNotification` → banner: "Screen is being recorded."
- On sensitive screens (payment, PIN entry), blur content while recording.

### 158.2 Screenshot detection
- `UIApplication.userDidTakeScreenshotNotification` → audit log entry (user + screen + timestamp).
- No block (user has right to screenshot); log only for sensitive screens.

### 158.3 Sensitive screens
- Payment sheet, credentials reveal, audit log export, bug report.
- Blur during background (`willResignActive` → swap root to blurred snapshot).

### 158.4 AirPlay
- `UIScreen.main.mirroredScreen` not nil → behave like screen recording.
- Customer-facing display (§16.15) explicit mode bypasses blur since intended.

### 158.5 Privacy indicator
- Orange dot (mic) / green (camera) — iOS system; app respects accordingly.

---

## 159. Color token system — MERGED INTO §311

Content moved to §311.9. Number preserved.

---

## 160. Typography scale — MERGED INTO §311

Content moved to §311.8. Number preserved.

---

## 161. Micro-copy style guide (deep)

### 161.1 Voice
- Confident, direct, friendly. No "Oops!" / "Uh-oh!" / emoji-in-error-text.
- Active voice: "We couldn't save" > "Save failed".
- Shops are small businesses — avoid corporate tone.

### 161.2 Labels
- Buttons = verb first: "Save ticket", "Print receipt", "Refund payment".
- Nav titles = noun: "Tickets", "Inventory".
- Empty states = sentence + CTA: "No tickets yet. Create your first." [Create Ticket].

### 161.3 Numbers
- Money: locale currency format, always. "$1,234.00" not "1234".
- Percentages: "12%" not "12.0 percent".
- Distance: locale unit.

### 161.4 Dates
- Relative for < 7 days ("2h ago", "yesterday").
- Absolute for > 7 days ("Apr 12").
- Full date + time only in detail / tooltips.

### 161.5 Error language
- Tell user what happened, why, what to do.
- "Couldn't reach server — check your connection and try again." not "Network error 0x4.".

### 161.6 Permission prompts
- System-prompt wrapper text: explain why we need it.
- Camera: "We use the camera to scan barcodes and take photos of devices."
- Location: "For field-service routing."
- Push: "To notify you about new tickets, payments, and messages."

### 161.7 No jargon
- "Sync" → "Update".
- "Endpoint" → "URL".
- "Idempotency key" → invisible to user.

### 161.8 Abbreviations banned unless common
- OK, not "Okay".
- "appointment" not "appt".
- SMS / PIN / OTP / PDF acceptable.

### 161.9 Sentence case, not title case
- Except product / feature names.

### 161.10 i18n discipline
- Every string keyed in `Localizable.strings`.
- No concatenation — use format placeholders.

---

## 162. First-empty-tenant UX

Brand-new tenants have zero data. App must not feel broken.

### 162.1 Dashboard
- KPIs say "No data yet". Each tile links to relevant onboarding action.
- Central card: "Let's set up your shop — 5 steps remaining." Links to Setup Wizard (§36).

### 162.2 Tickets
- Empty state illustration (SF Symbol wrench + glow).
- CTA "Create your first ticket" — opens create sheet.
- Sub-link: "Or import from old system" → §50.

### 162.3 Inventory
- CTA: "Add your first product" or "Import catalog (CSV)".
- Starter templates: "Phone repair" / "Laptop repair" / "TV repair" → seeds ~20 common items.

### 162.4 Customers
- CTA: "Add first customer" or "Import from contacts".
- Import-from-contacts uses `CNContactStore` with explicit explanation.

### 162.5 SMS
- CTA: "Connect SMS provider" → Settings § SMS.

### 162.6 POS
- CTA: "Connect BlockChyp" → Settings § Payment.
- Hardware-not-required mode: "Cash-only POS" enabled by default.

### 162.7 Reports
- Placeholder chart with "Come back after your first sale".

### 162.8 Completion nudges
- As user completes each onboarding step, checklist ticks. Progress ring in top-right of dashboard.

### 162.9 Sample data (optional)
- "Show sample data" toggle in Setup Wizard loads demo tickets so new owner can explore. Clearly labeled demo; one-tap clear.

---

## 163. Ticket quick-actions

### 163.1 Context menu (long-press on list row)
- Open
- Copy ID
- Share PDF
- Call customer
- Text customer
- Print receipt
- Mark Ready
- Mark In Repair
- Assign to me
- Archive
- Delete (admin only)

### 163.2 Swipe actions (iOS native)
- Right swipe: Start / Mark Ready (depending on current state).
- Left swipe: Archive.
- Long-swipe destructive: confirm via alert.

### 163.3 Keyboard shortcut (iPad Magic Keyboard)
- ⌘D → mark done.
- ⌘⇧A → assign.
- ⌘⇧S → send SMS update.
- ⌘P → print.
- ⌘⌫ → delete (admin only).

### 163.4 Drag-and-drop
- Drag ticket to "Assign" sidebar target (iPad) to reassign.
- Drag to status column in Kanban (§18.6 if ever built).

### 163.5 Batch actions
- Multi-select in list (§169).
- Batch context menu: Assign / Status / Archive / Export.

### 163.6 Smart defaults
- First action shown first: most-recently-used per user.
- Adapts.

---

## 164. Keyboard handling (deep)

### 164.1 Hardware keyboard
- Command menu in top menu bar (iPad) populates from scene `UIKeyCommand` discoverabilityTitle.
- ⌘? shows all shortcuts overlay.
- Arrow keys navigate lists.
- Tab / Shift-Tab traverse form fields.
- Enter submits primary action per view.
- Esc dismisses sheets / cancels.

### 164.2 Input accessory bar
- Numeric keyboard on money fields has $ + %.
- Done + Next + Prev arrows on all text fields.
- On hardware keyboard, bar auto-hides.

### 164.3 Field validation keys
- IMEI / phone: `.numberPad`.
- Email: `.emailAddress`.
- URL: `.URL`.
- Search: `.webSearch`.

### 164.4 Autocorrect
- Off for IDs / codes / emails.
- On for message composers, notes.
- SmartDashes / SmartQuotes off for data entry.

### 164.5 External barcode scanner (USB/BT wedge)
- Detects rapid keystrokes ending in Enter; captured and routed to scan handler rather than textfield.
- Configurable via Settings → Hardware.

### 164.6 Dvorak / custom layouts
- Supported automatically — never hardcode layouts.

### 164.7 Keyboard showing / hiding
- `.keyboardAvoidance` adjusts insets.
- Bottom-anchored primary buttons stay visible via `safeAreaInset(edge: .bottom)`.

---

## 165. Toast / banner system

### 165.1 Types
- **Toast** — transient, non-blocking, 2s auto-dismiss. For success / info.
- **Banner** — persistent until dismissed. For offline / sync pending / error.
- **Snackbar** — transient with action. For undo-window after destructive.

### 165.2 Position
- Top on iPad (doesn't block bottom content).
- Bottom on iPhone (thumb zone).
- Avoid covering nav/toolbars.

### 165.3 Style
- Glass surface, small icon, 1-line message.
- Color by severity: success (green accent), info (default), warning (amber), danger (red).
- Never stack > 2 visible.

### 165.4 Queue
- `ToastQueue` singleton; FIFO with dedup (don't show same toast twice within 3s).

### 165.5 A11y
- `accessibilityPriority(.high)` so VoiceOver reads.
- `announcement` for VoiceOver on show.

### 165.6 Haptics
- Success toast = `.success`.
- Warning = `.warning`.
- Danger = `.error`.

### 165.7 Dismissal
- Swipe up (top) or down (bottom) to dismiss early.
- Tap on action area triggers callback.

### 165.8 Persistence across screens
- Toast outlives push-navigation; dismissed only on user action or timeout.

---

## 166. Confirm-sheet patterns

### 166.1 When required
- Destructive (delete, refund, cancel subscription).
- Irreversible (void invoice, reset PIN).
- High-value (> threshold discount, large refund).
- Role-privileged (admin override).

### 166.2 UI
- Bottom sheet (iPhone) / centered modal (iPad).
- Title: what happens. Body: consequences. Primary button: destructive tint + action name ("Delete ticket"). Secondary: "Cancel".

### 166.3 Anti-misclick
- Primary button visually dominant BUT placed right (opposite of cancel) to match Apple convention.
- For critical ops, require hold-to-confirm (3s progress ring fills).

### 166.4 Typed confirmation (extreme)
- Wipe tenant data / cancel subscription — user types tenant name to confirm.

### 166.5 Manager override
- Some ops require manager PIN even from an admin session (e.g. big refund). PIN entry inline; can't bypass.

### 166.6 Undo window
- Soft-delete → 10s snackbar with Undo.
- Hard-delete only after snackbar expires.

---

## 167. Destructive gesture ergonomics

### 167.1 No rage-taps triggering deletion
- Swipe-to-delete: require full swipe OR separate confirm after light swipe.
- Double-tap to delete: not used (ambiguous with double-tap-to-zoom).

### 167.2 Delete confirmation defaults
- Primary button = Cancel (safe). Destructive button on left, red.

### 167.3 Visual feedback
- Row redshift on destructive gesture ramp-up.
- Haptic warning at commit point.

### 167.4 Recovery
- Deleted tickets / invoices go to Trash (30 days) before hard delete.
- Manager can restore from Settings → Trash.

### 167.5 No swipe-to-delete on financial records
- Invoices / payments / receipts — never swipe-delete. Only via explicit Void action with reason.

### 167.6 Protect from force-delete edges
- Edge-swipe gesture conflicts (iOS back-gesture vs row swipe) — use `.swipeActions` not custom pan gestures.

---

## 168. Undo/redo framework

### 168.1 Undo manager per scene
- `UndoManager` attached to scene.
- Each editable action registers undo via `UndoManager.registerUndo(withTarget:handler:)`.

### 168.2 Covered actions
- Ticket field edit.
- Cart item add/remove in POS.
- Inventory adjust.
- Customer field edit.
- Status change.
- Notes add/remove.

### 168.3 Undo trigger
- ⌘Z on iPad hardware keyboard.
- iPhone: `.accessibilityAction(.undo)` + shake-to-undo if user enabled.
- Button in context menu for non-keyboard users.

### 168.4 Server sync
- Undo rolls back optimistic change, sends compensating request if already synced.
- If undo impossible (server side already completed), show toast "Can't undo — action already processed."

### 168.5 Redo
- ⌘⇧Z.

### 168.6 Stack depth
- Last 50 actions.
- Cleared on scene dismiss.

### 168.7 Audit integration
- Each undo creates audit entry (not silent).

---

## 169. Multi-select UX

### 169.1 Entry
- Long-press on list row → select mode.
- Toolbar swaps to selection mode (Select All / Deselect / Actions).
- iPad: `EditButton()` in nav also enters mode.

### 169.2 Selection affordance
- Checkmark circle on left, chevron hidden.
- Row tint shift.
- Count badge in nav: "3 selected".

### 169.3 Bulk actions
- Context-sensitive toolbar: Assign / Archive / Status / Export / Delete.
- Irreversible actions require confirm (§166).

### 169.4 Select-all scope
- "Select all on screen" (quick).
- "Select all matching filter" (applies to all pages after confirm).

### 169.5 Cross-page selection
- Selection persists while scrolling through pages.
- Nav badge shows "47 selected across 3 pages".

### 169.6 Exit mode
- Cancel button, Esc, or tap outside list.

### 169.7 Drag-to-select (iPad Magic Trackpad / Pencil)
- Drag rectangle across rows to add to selection.

---

## 170. Drag & drop

### 170.1 Within app
- Ticket row → Assignee sidebar (iPad).
- Invoice row → Email compose.
- Inventory row → PO draft.
- Photo → Ticket attachment.

### 170.2 Cross-app
- Drag customer from Contacts app → our Customer create.
- Drag PDF from Files → Ticket attachment.
- Drag photo from Photos → Ticket photos / Annotation.

### 170.3 Type registration
- `UTType`s: `public.image`, `public.pdf`, `com.bizarrecrm.ticket` (custom UTI for in-app drag).
- `NSItemProvider` per source.

### 170.4 Previews
- Drag preview = card-style miniature.
- Drop target highlights on hover.

### 170.5 Validation
- Drop handler validates type + tenant scope.
- Invalid drops show red X overlay.

### 170.6 Haptics + motion
- Pickup: light haptic + row lift.
- Drop: success haptic + slot-fill animation.
- Cancel: rubber-band back.

### 170.7 Accessibility
- Every drag op has keyboard / VoiceOver alternative: select + "Move to…" menu.

---

## 171. Clipboard patterns

### 171.1 Copy triggers
- Long-press on IDs / emails / phones / SKUs → "Copy" menu.
- Ticket detail: header chip `#4821` tap → copy with haptic confirm.
- Invoice: invoice number + total same way.

### 171.2 Feedback
- Haptic `.success` + toast "Copied" (2s).
- Avoid toast spam: dedup identical copies within 3s.

### 171.3 Paste
- Form fields auto-detect tenant-URL paste → auto-populate host field.
- Phone field parses pasted numbers (removes formatting).

### 171.4 Pasteboard hygiene
- `UIPasteboard.string` access wrapped in audit log (sensitive screens only).
- iOS 17+ `pasteButton` preferred for user-initiated paste to avoid access warnings.

### 171.5 Auto-clear
- After paste of sensitive content (credentials), offer to clear pasteboard.

### 171.6 Universal Clipboard
- Works across Apple devices seamlessly (iCloud Handoff).
- No special code.

---

## 172. Inline editing

### 172.1 Where
- Customer detail fields (name / phone / email / tags).
- Ticket fields (status / notes / priority).
- Inventory price / qty.

### 172.2 Affordance
- Pencil icon on hover (iPad) or long-press (iPhone).
- Tap → field becomes editable with inline save.

### 172.3 Save behavior
- Blur triggers save (optimistic).
- ⌘S shortcut on iPad.
- Escape reverts.

### 172.4 Conflict
- If server updated underneath, show conflict inline (§20.6).

### 172.5 Validation
- Per-field, live.
- Invalid state: red underline + inline message.

### 172.6 Batch inline
- Keyboard Tab moves to next editable.

### 172.7 Permission
- Fields read-only if user lacks edit permission; pencil icon hidden.

---

## 173. Inline validation (deep)

### 173.1 Timing
- Show errors on first blur / submit — never on first keystroke.
- Clear errors as user types valid input.

### 173.2 Rules per field
- Email: RFC 5322 light + typo suggest ("did you mean gmail.com?").
- Phone: libphonenumber-swift; E.164 normalized.
- IMEI: Luhn + 15 digits.
- Password: strength meter (4 levels); minimum length gate (not complexity theater).
- Money: locale decimal separator.
- Date: reasonable range (not 1900, not 3000).

### 173.3 Server-side re-validate
- Client validation never authoritative. Server validates on save.
- Server errors mapped to form fields via `field_errors: { ... }` in envelope.

### 173.4 Accessibility
- `.accessibilityElement` wraps field + error so VoiceOver reads both.
- Error announced with `accessibilityNotification(.announcement)`.

### 173.5 Tooltips
- iPad hover shows format hint.
- iPhone: field placeholder + helper text under field.

---

## 174. Responsive grid system

### 174.1 Breakpoints
- `.compact` (iPhone portrait, split iPad) — 1 column.
- `.regular` (iPhone landscape / small iPad) — 2 columns.
- `.wide` (iPad full / external monitor) — 3–4 columns.
- `.huge` (Studio Display) — 5+ columns.

### 174.2 Token
```swift
@Environment(\.breakpoint) var bp
Grid(cols: bp.cols(ticket: 1, 2, 3, 4)) { ... }
```

### 174.3 Layout components
- `ResponsiveGrid` — auto-columns.
- `ResponsiveForm` — 1 column compact / 2 column wide.
- `ResponsiveSplit` — master-detail or stacked.

### 174.4 Rules
- Never assume iPhone. Always read breakpoint.
- Content max width 720pt inside cards so nothing stretches crazy on 13" iPad.

### 174.5 Testing
- Snapshot at each breakpoint in CI (§87.4).

---

## 175. Lazy image loading

### 175.1 List thumbnails
- `LazyVStack` + Nuke `FetchImage` → only loads when in viewport.
- Prefetch 5 ahead / behind.

### 175.2 Placeholders
- Blurhash on first paint (if server provides hash).
- SF Symbol fallback on error.

### 175.3 Priority
- Higher for visible rows; lower for prefetch.
- Cancel on scroll past.

### 175.4 Progressive
- If server sends progressive JPEG, Nuke renders while downloading.

### 175.5 Thumbnail sizing
- Request server-resized thumbnails (e.g. `?w=120`) to save bandwidth.
- Never load full-res for list rows.

### 175.6 Retina support
- Request 2x / 3x variants based on `UIScreen.main.scale`.

---

## 176. Scroll performance

### 176.1 Budget
- Never drop below 60fps on iPhone SE 3; 120fps on ProMotion iPad.

### 176.2 Cell prep
- Row subviews lightweight; no heavy work in `onAppear`.
- Expensive calcs moved to `.task` or cached in ViewModel.

### 176.3 Materials
- Glass materials are expensive — `GlassEffectContainer` groups them.
- Limit to ≤ 6 visible glass elements per screen.

### 176.4 Measurement
- Instruments Time Profiler + SwiftUI `_printChanges()` during dev.
- CI runs XCTMetric on scrolling benchmark.

### 176.5 Lists > Grids for scroll
- `LazyVStack` or `List` for long lists.
- `LazyVGrid` fine for gallery but limits row height flexibility.

### 176.6 Image decode
- Off main thread via Nuke.
- No `UIImage(named:)` inside cell body.

---

## 177. List virtualization

### 177.1 SwiftUI `List`
- Native virtualization; use where possible.
- Custom row height via `.listRowSeparator`, `.listRowInsets`.

### 177.2 `LazyVStack` alternative
- Needed when `List` style not flexible enough.
- Requires our own diffing for animated inserts/removes.

### 177.3 Anchoring
- Maintain scroll position on insert at top.
- `ScrollViewReader` for programmatic scroll (e.g. scroll-to-latest SMS).

### 177.4 Jump-to
- iPad sidebar shows letter rail (A-Z) for fast jump.
- Jump preserves filters.

### 177.5 Estimated sizes
- If row heights vary, provide estimated height so scroll bar is accurate.

### 177.6 Diffable
- Use `Identifiable` models with stable IDs.
- Never reuse IDs across deletions.

---

## 178. Glass elevation layers

### 178.1 Hierarchy
1. **Surface** — app background (`bizarreSurfaceBase`).
2. **Content** — cards, list rows.
3. **Glass** — nav, toolbars, sheets.
4. **Overlay** — alerts, toasts.

### 178.2 Rules
- Glass never on Content layer.
- Overlay may sit atop glass with additional shadow.
- Shadow on Content to separate from Surface; no shadow on Glass (its blur is the separator).

### 178.3 Z-index
- Toasts: 1000.
- Sheets: 900.
- Nav: 500.
- Content: 0.

### 178.4 Transitions
- Glass appears with `.animation(.springSoft)` + `.opacity`.
- Content slides without opacity to avoid flicker.

### 178.5 Background composition
- `bizarreSurfaceBase` is solid; glass picks up implied color from tint tokens.
- Dark mode bases around `#0B0D10`; glass picks up `#202228` tint.

---

## 179. Sidebar adaptive widths

### 179.1 iPad portrait
- Sidebar collapsed to icon rail (56pt) unless user expands.
- Detail takes most width.

### 179.2 iPad landscape
- Sidebar expanded (260–280pt) default.
- User can toggle to rail via keyboard shortcut (⌘\).

### 179.3 Mac Designed-for-iPad
- Sidebar persistent; min 260pt.

### 179.4 Drag to resize
- iPad 13" Pro supports resize via split-view divider; our inner sidebar also resizable (260–400pt).

### 179.5 Persistence
- Width saved per-scene in `UserDefaults`.

### 179.6 Overflow
- If label truncates, icon-only mode kicks in automatically at < 100pt.

---

## 180. Settings search

### 180.1 Top-level search bar in Settings
- Typeahead over all setting labels + synonyms.
- Jump directly to matching page with highlight.

### 180.2 Index
- Static index built at compile time from settings metadata.
- Pre-seeded synonyms ("tax" → "Tax rules", "sms" → "SMS provider", "card" → "Payment (BlockChyp)").

### 180.3 Results UI
- Grouped by section (Payment / Notifications / Privacy…).
- Tap navigates + highlights setting for 1.5s with subtle pulse.

### 180.4 A11y
- VoiceOver reads "5 results; first: Tax rules in Payment."

### 180.5 Empty state
- "No settings match 'xyz'. Try synonyms: card, payment, cash."

### 180.6 Recently changed
- Small section at top: recent toggles (last 5).

---

## 181. Shake gestures

### 181.1 Shake-to-report bug
- Dev / staging builds only.
- `UIResponder.motionEnded(.motionShake)` → opens bug-report form (§137).
- Production: opt-in in Settings → Accessibility (some users ride subways).

### 181.2 Shake-to-undo
- iOS system gesture; our `UndoManager` (§168) hooks into it.
- Honor user's iOS setting (Accessibility → Touch → Shake to Undo).

### 181.3 Accidental triggers
- Debounce; ignore shakes during active gestures (scroll / pan).

---

## 182. Spatial audio

### 182.1 Customer-facing display
- When POS terminal sits on counter facing customer, CFD displays running cart.
- Audio cue on add-item: positional sound toward customer (AirPods Pro spatial).

### 182.2 Scanner feedback
- Beep on scan plays spatial from "upper-right" to feel more physical.

### 182.3 Restraint
- Audio secondary to haptic; always optional (Settings → Audio).
- Mute in silent mode per iOS convention.

---

## 183. Kiosk dimming

### 183.1 Idle timer
- In kiosk mode (§57) after 2 min idle, dim display 50%.
- After 5 min, black out with brand mark.
- Tap anywhere wakes.

### 183.2 Night mode
- Between quiet-hour window (e.g., 10pm–6am), auto-switch to darker palette even in kiosk.
- Prevents burn-in on OLED iPad Pro.

### 183.3 Screen-burn prevention
- Subtle 1px shift every 30s on static elements.

### 183.4 Config
- Tenant Settings → Kiosk → dim thresholds + schedule.

---

## 184. Battery-saver mode

### 184.1 Detection
- `ProcessInfo.processInfo.isLowPowerModeEnabled` → observe changes.
- Banner: "Low Power Mode on — reduced sync."

### 184.2 Behavior
- Halve background refresh cadence.
- Disable push-registered silent pushes.
- Pause image prefetch (§175.4).
- Cap animations to duration 0.2s (less perf cost).
- Reduce Glass intensity (swap to thin material).

### 184.3 User override
- Settings → "Use normal sync even in Low Power" toggle.

### 184.4 Resume
- On exiting LPM, full sync kicked off.

---

## 185. Thermal throttling

### 185.1 Detection
- `ProcessInfo.thermalState` observe.
- `.nominal` → normal.
- `.fair` → unchanged.
- `.serious` → reduce animation intensity + defer background work.
- `.critical` → banner to user "Device is hot — some features paused."

### 185.2 Pause tasks
- Photo batch uploads paused.
- FTS5 reindex paused.
- Image decode switches to lower priority.

### 185.3 POS continuity
- Checkout never paused (too disruptive). Print / receipt / payment all stay active.

---

## 186. Quiet-mode haptics

### 186.1 Quiet hours
- User defines in Settings → Notifications → Quiet hours (e.g., 9pm–7am).
- During quiet hours: haptics reduced to minimum intensity; sounds muted.
- Except critical (backup failure / security alert).

### 186.2 Silent mode
- Honor device mute switch — no sounds, haptics still fire unless user disabled in iOS.

### 186.3 Do-Not-Disturb
- Focus modes (§152) respected; notifications routed per Focus rules.

---

## 187. Customer-facing display layouts (§16.15 deep)

### 187.1 Secondary scene
- New `UIScene` for external display.
- Detects `UIScreen.connectionNotification`; mirrors cart state via shared model.

### 187.2 Layout
- Top: shop logo + tagline (tenant-configured).
- Middle: cart lines running total.
- Bottom: current line highlighted with animation as added.
- Large totals: tax + total.
- Payment prompt: "Insert / tap card" with animated arrow when BlockChyp terminal ready.

### 187.3 Receipt / thank-you
- After approval: confetti animation (respects Reduce Motion), "Thank you!" + QR for Google review / membership signup.
- Auto-dismiss after 10s.

### 187.4 Signature
- Customer signs on secondary display when supporting Apple Pencil-compatible iPad; else on terminal.

### 187.5 Marketing slideshow
- When idle > 30s between sales, rotate tenant-configured slides (promos, upcoming events).
- Tap anywhere exits slideshow.

### 187.6 Multi-language
- Customer can tap flag to switch language.
- Display language decouples from cashier's app language.

### 187.7 Privacy
- Never shows cashier's personal data (email / phone / other customers).
- No cross-sale persistence on display.

---

## 188. Shift reports UI

### 188.1 End-of-shift summary
- Cashier taps "End shift" → summary card: sales count / gross / tips / cash expected / cash counted (entered) / over-short / items sold / voids.
- Compare to prior shifts for trend.

### 188.2 Close cash drawer
- Prompt to count cash by denomination ($100, $50, $20…).
- System computes expected from sales; delta computed live.
- Over-short reason required if > $2.

### 188.3 Manager sign-off
- If over-short threshold exceeded, require manager PIN.
- Audit entry created with cashier + manager IDs.

### 188.4 Receipt
- Z-report printed + PDF archived in §39 Cash register.
- PDF linked in shift summary.

### 188.5 Handoff
- Next cashier starts their shift with opening cash count entered by closing cashier.

### 188.6 Sovereignty
- Shift data tenant server only.

---

## 189. End-of-day wizard

### 189.1 Triggers
- Manager taps "End of day" at shop close.

### 189.2 Steps
1. Close any open cash shifts.
2. Mark tickets still open → confirm or archive to tomorrow.
3. Send day-end status SMS to customers with ready tickets (optional).
4. Review outstanding invoices / follow-ups.
5. Backup reminder (if tenant schedules local backup).
6. Lock POS terminal.
7. Post shop's daily summary to tenant admin (push).

### 189.3 Progress indicator
- Glass progress bar at top.
- Can abort mid-wizard and resume.

### 189.4 Logging
- Each step's completion stamped in audit log.

### 189.5 Permissions
- Manager-only; cashier gets "Need manager" if attempted.

---

## 190. Open-shop checklist

### 190.1 Triggers
- On first app unlock of the day for staff role.
- Gently suggests opening checklist.

### 190.2 Steps (customizable per tenant)
- Open cash drawer; count starting cash.
- Print last night's backup receipt.
- Review pending tickets for today.
- Check appointments list.
- Check inventory low-stock alerts.
- Power on hardware (printer / terminal) — app pings and reports status.
- Unlock POS.

### 190.3 Hardware ping
- Ping each configured device (printer, terminal) with 2s timeout.
- Green check or red cross per device.
- Tap red → diagnostic page.

### 190.4 Completion
- Stored with timestamp per staff.
- Optional: post to team chat ("Morning!").

### 190.5 Skip
- User can skip; skipped state noted in audit log.

---

## 191. App lifecycle events deep

### 191.1 Launch
- `applicationDidFinishLaunching` → register Factory Container, read feature flags from Keychain cache.
- `scene(_:willConnectTo:)` → resolve last-tenant, attempt token refresh in background.

### 191.2 Foreground
- `willEnterForeground` → kick delta-sync, refresh push token, update "last seen" ping.
- Resume paused animations, restart `CHHapticEngine`.
- Lock-screen gate re-evaluated (biometric required if inactive > 15min).

### 191.3 Background
- `didEnterBackground` → persist unsaved drafts, schedule BG tasks, seal pasteboard if sensitive, blur root for screen capture privacy.

### 191.4 Terminate
- Rarely invoked; don't rely on. Persist state on every change, not at terminate.

### 191.5 Memory warning
- `didReceiveMemoryWarning` → flush Nuke memory cache, drop preview caches.
- Never free active data; user shouldn't notice.

### 191.6 Scene disconnect
- Save scene state to disk via `NSUserActivity`.

### 191.7 URL open / universal link
- Handle in `scene(_:openURLContexts:)` / `scene(_:continue:)`.
- Route through central DeepLinkRouter (§68).

### 191.8 Push delivery in foreground
- `UNUserNotificationCenterDelegate.willPresent` → decide banner/sound/badge.
- SMS_INBOUND shows banner but NOT sound if user is already in SMS thread for that contact.

### 191.9 Push background
- `didReceive` → handle action buttons (Reply / Mark Read) inline.

### 191.10 Silent push
- `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` → trigger delta-sync, call handler within 30s.

---

## 192. Data model / ERD

### 192.1 Entities (local + server)
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

### 192.2 Relationships
- Customer 1:N Ticket 1:N Invoice.
- Ticket M:N Part (via `ticket_part`), M:N Service.
- Employee 1:N Shift.
- Every entity belongs-to Tenant (row-level tenant_id enforced server + client).

### 192.3 Normalization
- Customer contacts denormalized (phones / emails arrays) for simple queries.
- Tags normalized via `tag` + `entity_tag` join.
- Photos store URL + metadata; binary not in DB.

### 192.4 IDs
- UUIDv4 server-generated.
- Client-generated for offline creates (namespace v5 with tenant seed to avoid collision).

### 192.5 Deletion
- Soft delete (tombstone) for most entities; hard delete only after retention window.

### 192.6 Versioning
- `updated_at` per entity used for sync delta.
- `version_hash` optional for conflict detection.

---

## 193. SwiftData vs GRDB (decision)

### 193.1 Choice: GRDB + SQLCipher
- Encryption-at-rest mandatory → SwiftData doesn't support encryption natively.
- GRDB has mature FTS5 bindings for §130 search.
- GRDB concurrency model (DatabasePool) matches our heavy-read-light-write load.
- CloudKit not desired (§32 sovereignty).

### 193.2 SwiftData considered
- Pro: SwiftUI bindings, less ceremony.
- Con: No encryption, iOS 17+ tightens iOS floor if we need latest features.
- Decision: GRDB for now, revisit when SwiftData adds SQLCipher integration.

### 193.3 Migration
- If ever switch, would export GRDB → SwiftData via CSV/JSON intermediary.
- Not planned.

### 193.4 Concurrency
- GRDB actors per repository.
- Read pool size 10; write queue serialized.

### 193.5 Observation
- GRDB `ValueObservation` → bridges into `AsyncSequence` for SwiftUI.

---

## 194. Backup & restore

### 194.1 Device-local backup
- Settings → Data → Backup now → exports SQLCipher DB + photos to `~/Documents/Backups/<date>.bzbackup` (encrypted bundle).
- Share sheet to send to Files / iCloud Drive / AirDrop.

### 194.2 Automatic
- Schedule: daily / weekly / off.
- Ran in `BGProcessingTask`; skipped if low battery.

### 194.3 Restore
- Settings → Data → Restore from backup.
- Picker from Files.
- Decrypts via passphrase prompt (user-supplied).
- Replaces local DB after user confirms.
- Does NOT change server; only restores local cache.

### 194.4 Server-side backup
- Orthogonal; tenant server does own cloud backups (per tenant).
- iOS backup is for "if device lost, restore your offline data on a new phone quickly".

### 194.5 Encryption
- AES-256-GCM with PBKDF2-derived key from passphrase.
- No cloud passphrase escrow (user's responsibility).

### 194.6 Cross-tenant
- Backup bundle tagged with tenant_id; refuses restore into wrong tenant.

---

## 195. Tenant ownership handoff

### 195.1 Use case
- Shop owner sells shop; transfers ownership.
- App supports reassigning primary admin.

### 195.2 Flow
- Current owner → Settings → Org → Transfer ownership.
- Enter new owner email; server sends verification link.
- New owner clicks link → becomes owner; previous downgraded to admin.

### 195.3 Safety
- 72-hour delay before effective (cancelable).
- Email notifications both parties.
- Audit entry.

### 195.4 Data ownership
- Data stays with tenant server; no export required.
- Previous owner can still access if they remain a user (unless revoked).

### 195.5 Payment billing change
- Separate flow — update billing card / account after handoff.

---

## 196. Staff hiring & offboarding

### 196.1 Hire wizard
- Manager → Team → Add employee.
- Steps: basic info / role / commission / access locations / welcome email.
- Account created; staff gets login link.

### 196.2 Offboarding
- Settings → Team → staff detail → Offboard.
- Immediately: revoke access, sign out all sessions, transfer assigned tickets to manager, archive shift history (kept for payroll).
- Audit log.
- Optional: export their shift history as PDF for records.

### 196.3 Role changes
- Promote / demote path; change goes live immediately.

### 196.4 Temporary suspension
- Suspend without offboarding (vacation without pay).
- Account disabled until resume.

### 196.5 Reference letter (nice to have)
- Auto-generate PDF summarizing tenure + stats (total tickets, sales).
- Manager customizes before export.

---

## 197. Job posting integration

### 197.1 Indeed / Craigslist API
- Tenant can post job from in-app form.
- Server handles integration; iOS is UI only.

### 197.2 Applicant tracking
- List of applicants per posting.
- Tap → resume viewer + notes + schedule interview (§124).

### 197.3 Privacy
- Applicant data is PII; encrypted at rest; limited role access.

### 197.4 Defer
- Phase 5+. Many tenants won't need.

---

## 198. iPad Pro M4-specific features

### 198.1 Tandem OLED
- HDR content optional: hero images on dashboard (brand gradients) use HDR range.
- Verify blacks on real OLED (no gray haze).

### 198.2 Promotion 120fps
- All animations tuned for 120fps.
- Avoid 60fps lock from `ProMotion: false` in Info.plist.

### 198.3 Magic Keyboard 2024
- Function row surfaced; map custom actions (F1 = new ticket, F2 = POS, F3 = inventory).

### 198.4 Pencil Pro
- Squeeze: opens tool picker in annotation (§134).
- Barrel roll: rotates shape/text.
- Haptic on Pencil tip (iOS 17.5+ API).

### 198.5 Performance
- M4 can handle larger datasets; unlock UI elements gated on A17+ e.g., live charts with 10k data points.

### 198.6 External storage
- USB-C supports direct photo import; file picker recognizes external drives.

---

## 199. Widgets (deep, expanding §24)

### 199.1 Sizes supported
- Small, Medium, Large, Extra-Large (iPad only), Accessory (Lock Screen: circular / rectangular / inline), StandBy.

### 199.2 Widgets catalog
- **Tickets today** — counts + progress bar.
- **Revenue today** — $ + trend.
- **Next appointment** — customer + time + address.
- **Pending SMS** — unread count.
- **Quick actions** — 4 buttons: New ticket / Scan / POS / Clock in.
- **Employee snapshot** — my assigned count / my sales today.
- **Inventory alert** — critical low-stock item with name.

### 199.3 Data source
- App Group SQLCipher DB (read-only in widget).
- Refreshed via app writing on every sync.

### 199.4 Timeline entries
- `IntervalTimelineProvider` every 15 min.
- Triggered refresh on background sync completion.

### 199.5 Taps
- Each widget deep-links; iOS opens app at the right screen.

### 199.6 StandBy
- Large time-of-day widget shows today revenue and next appointment in glance mode.

### 199.7 Lock Screen
- Circular: ticket count.
- Rectangular: revenue + Δ vs yesterday.
- Inline: "3 tickets ready".

### 199.8 Configuration
- `AppIntentConfiguration` lets user pick which tenant (multi-tenant user), which location.

### 199.9 Privacy
- Widget content stays on device. No sensitive data revealed on Lock Screen (no customer names; counts only).

---

## 200. Notifications UX polish

### 200.1 Delivery tuning
- Respect quiet hours (§186).
- Bundle repeated pushes (group SMS from same thread into one notification with message-count badge).

### 200.2 Rich content
- SMS notification embeds photo thumbnail if MMS.
- Payment notification shows amount + customer name.
- Ticket assignment embeds device + status.

### 200.3 Reply inline
- SMS_INBOUND action "Reply" uses `UNTextInputNotificationAction` — user replies from push without opening app.

### 200.4 Sound library
- Chat-like sounds from Apple default + 3 brand custom (cash register, bell, ding).
- User picks per category.

### 200.5 Clear all
- On app foreground after read, system badge clears accordingly.
- Single tap clears relevant bundle.

### 200.6 Historical view
- Settings → Notifications → "Recent" — list of last 100 pushes for audit purposes.

### 200.7 Push token rotation
- On app start or change, POST new token to `/device-tokens` with device model.
- Stale tokens cleaned server-side.

### 200.8 Fail-safe
- If APNs token register fails, retry with exponential backoff.
- Manual "Re-register" in Settings.

---

## 201. Barcode formats catalog

### 201.1 Supported symbologies
- **EAN-13 / EAN-8** — retail.
- **UPC-A / UPC-E** — US retail.
- **Code 128** — internal SKU, shipping.
- **Code 39** — legacy industrial.
- **Code 93** — alt industrial.
- **ITF-14** — cartons.
- **DataMatrix** — small parts, electronics.
- **QR** — tracking links, URLs.
- **Aztec** — tickets, boarding-style.
- **PDF417** — ID cards, driver licenses.

### 201.2 Priority per use-case
- Inventory SKU: Code 128 primary, QR secondary.
- Retail products: EAN-13 / UPC-A auto-detect.
- IMEI / serial from device: Code 128 or bare numeric.
- Internal loaner / asset tag: QR (also contains a URL for scan-to-view).

### 201.3 Scanner config (`VNBarcodeObservation`)
- Recognize all formats concurrently.
- Preview layer marks detected code with glass chip + content preview.
- Tap chip to accept.
- Continuous scan mode: scan → process → beep → ready for next without closing camera.

### 201.4 Validation
- Checksum verify per symbology (EAN mod 10, ITF mod 10, etc.).
- Malformed → warning toast + no action.

### 201.5 Tenant bulk relabel
- Inventory tool: "Regenerate barcodes" for all SKUs → print via §114.

### 201.6 Gift cards
- Unique Code 128 per card (§40).

### 201.7 A11y
- VoiceOver announces scanned code and matched item.

---

## 202. IMEI check / carrier blacklist

### 202.1 Local validation
- Luhn checksum + 15-digit length.
- TAC lookup (first 8 digits) via offline table to name device (optional).

### 202.2 Blacklist lookup
- Tenant-configurable provider: CheckMEND / IMEI24 / Swappa API.
- Called from ticket create / inventory trade-in.
- Server proxies request to keep third-party tokens out of iOS bundle.

### 202.3 Results UI
- Green: "Clean."
- Amber: "Previously reported lost — verify with customer."
- Red: "Reported stolen — do not accept."

### 202.4 Policy
- Red → block ticket creation; require manager override with reason.
- Amber → require photo of ID + signed affidavit.

### 202.5 Sovereignty
- Raw IMEI never logged off tenant server. Third-party response cached with TTL.

---

## 203. QR tracking labels

### 203.1 Content
- URL `https://app.bizarrecrm.com/public/tracking/<shortId>`.
- Short ID generated server-side; 8-char base32.

### 203.2 Use
- Printed on intake receipt + stuck on device bag.
- Customer scans to see status from their own phone (no install).

### 203.3 Staff scan
- Same QR, different handler in app: opens internal ticket detail.

### 203.4 Life cycle
- Active until ticket archived + 30 days.
- Permanently invalidated on tenant data delete.

### 203.5 Privacy
- Landing page shows only device + status + ETA. No PII.

### 203.6 Reprint
- Ticket detail → "Reprint tag" any time.

---

## 204. Open-hours & holiday calendar

### 204.1 Data model
- Per location: weekly schedule (Mon-Sun, open/close time), exceptions (holidays, half-days).
- Per service: allowed booking window within open hours.

### 204.2 Editor
- Settings → Org → Location → Hours.
- Copy from another location.
- Import US / CA / EU federal holiday list; tenant unchecks as needed.

### 204.3 Use
- Appointment self-booking (§58) respects hours.
- Outside hours, "Closed" badge on dashboard.
- Auto-reply on SMS outside hours (if opted in) with next-open time.

### 204.4 Timezone
- Each location has its own timezone.
- Multi-location view normalizes display to user's device timezone with "Store time: X" chip.

### 204.5 Daylight-saving
- Auto-shift via `TimeZone.current` / `Calendar` APIs.

### 204.6 Closures
- "Unexpected closure" button posts in-app banner + auto-SMS to customers with appointments.

---

## 205. Staff chat — MERGED INTO §47

Content moved to §47.5-§47.13. Number preserved.

---

## 206. Role matrix — MERGED INTO §49

Content moved to §49.5-§49.9. Number preserved.

---

## 207. Sticky accessibility tips

### 207.1 TipKit integration
- iOS 17+ TipKit surfaces rules-based tips.
- Each tip: title, message, image, eligibility rules (e.g. "shown after 3rd ticket create").

### 207.2 Catalog
- "Try swipe right to start ticket" after 5 tickets viewed but zero started via swipe.
- "⌘N creates new ticket faster" shown once user connects hardware keyboard.
- "Long-press inventory row for quick actions" after 10 inventory views.
- "Turn on Biometric Login in Settings" after 3 sign-ins.

### 207.3 Dismissal
- Per-tip "Don't show again".
- Global opt-out in Settings → Help.

### 207.4 A11y
- Tips announced via VoiceOver at low priority.
- Reduce Motion: fade in, no bounce.

### 207.5 Sovereignty
- Tip eligibility computed entirely on device; no tracking served from third-party.

---

## 208. Customer portal link surface (not an app)

Per §91 ruling, no customer app. Customer-side web is enhanced through linkable URLs only.

### 208.1 Public tracking page (§55 recap)
- `https://app.bizarrecrm.com/public/tracking/:shortId`
- Branded per tenant (logo + theme).
- Mobile-responsive, light + dark.
- Shows status, device, ETA, contact shop button.

### 208.2 Public pay page (§41)
- `https://app.bizarrecrm.com/public/pay/:linkId`
- Apple Pay + card; branded.

### 208.3 Public quote sign page (§133)
- `https://app.bizarrecrm.com/public/quotes/:code/sign`

### 208.4 Apple Wallet pass add page
- `https://app.bizarrecrm.com/public/memberships/:id/wallet`
- Detects iOS → serves `.pkpass`.
- Detects Android → serves Google Wallet pass.
- Detects desktop → QR to scan on phone.

### 208.5 Self-booking (§58)
- `https://app.bizarrecrm.com/public/book/:locationId`

### 208.6 These links open in browser
- iOS app doesn't swallow these Universal Links even if installed — staff installs own app, customers stay on web.
- `apple-app-site-association` excludes `/public/*` patterns.

### 208.7 SEO
- Tenant `robots.txt` allows `/public/book/:locationId` (for discoverability).
- Disallow `/public/tracking/*` (URL-scoped privacy).

---

## 209. Email templates deep

### 209.1 Transactional
- Welcome / verify email.
- Ticket status updates (configurable per status).
- Invoice sent.
- Payment receipt.
- Quote sent / approved / declined.
- Appointment confirm / reminder / reschedule / cancel.
- Membership renewal.
- Password reset.

### 209.2 Marketing
- Monthly newsletter.
- Birthday promo.
- Seasonal sale.
- Abandoned cart (online store, if any).

### 209.3 Engine
- Server-side via tenant's email gateway (Postmark / Amazon SES / SendGrid — tenant choice).
- iOS triggers via POST /comms/email; never sends directly.
- Credentials stay server-side.

### 209.4 Template editor
- iPad: visual WYSIWYG (drag blocks).
- iPhone: simple text + preview.
- Web: full editor (managers likely prefer).

### 209.5 Variables
- Same vocab as SMS templates (§125.1).
- Auto-injected footer: address, unsubscribe, privacy.

### 209.6 Testing
- Send test to self button.
- Preview on device (render).

### 209.7 Compliance
- CAN-SPAM footer + unsubscribe mandatory.
- Tenant controls; iOS renders.

---

## 210. Webhooks & integrations

### 210.1 Principle
- Tenants integrate BizarreCRM with other systems (QuickBooks, Zapier, Make).
- All webhook config on server; iOS surfaces read + small edits.

### 210.2 iOS surface
- Settings → Integrations → list of active integrations.
- Enable / disable toggle.
- View last N events sent.
- Retry failed.

### 210.3 Inbound webhooks
- Tenant may receive webhook from external (e.g. Shopify order → create BizarreCRM ticket).
- iOS doesn't process inbound; server does. iOS just shows audit trail.

### 210.4 Zapier-like connector
- BizarreCRM as Zap source (trigger): ticket.created / invoice.paid / customer.created.
- BizarreCRM as Zap destination (action): create ticket / send SMS / update customer.
- Tenant subscribes on Zapier; OAuth via tenant server.

### 210.5 API tokens
- Per-integration token with scoped capabilities (like roles §206).
- iOS → Integrations → Tokens → Create.

### 210.6 Rate limits
- Per-token; visible to tenant.
- Alerts when approaching.

### 210.7 Logs
- Last 1000 events per integration.
- Replay button for troubleshooting.

### 210.8 Sovereignty
- Outbound webhooks go only to tenant-configured URLs. No Zapier shortcut via our infra.
- iOS never calls third-party integration APIs directly.

---

## 211. POS keyboard shortcuts

Full register accelerators on iPad hardware keyboard.

### 211.1 Cart ops
- ⌘N — new sale.
- ⌘⇧N — hold current sale (park).
- ⌘R — resume held sale picker.
- ⌘+ / ⌘− — qty on focused line.
- ⌘⌫ — remove focused line.
- ⌘⇧⌫ — clear cart (confirm).

### 211.2 Lookup
- ⌘F — focus product search.
- ⌘B — focus barcode input.
- ⌘K — customer lookup palette.

### 211.3 Payment
- ⌘P — pay (opens payment sheet).
- ⌘1 — cash tender.
- ⌘2 — card tender.
- ⌘3 — gift card tender.
- ⌘4 — store credit tender.
- ⌘⇧P — split tender.

### 211.4 Receipt
- ⌘⇧R — reprint last.
- ⌘E — email receipt.
- ⌘S — SMS receipt.

### 211.5 Admin
- ⌘M — manager PIN prompt.
- ⌘⌥V — void current sale.
- ⌘⌥R — open returns.

### 211.6 Navigation
- Tab cycles: cart → discount → tender.
- Arrow keys scroll catalog grid.

### 211.7 Discoverability
- ⌘? shows overlay (§164.1).

---

## 212. Gift receipt

### 212.1 Toggle
- Checkout sheet has "Gift receipt" switch.

### 212.2 Content difference
- Item names + qty present.
- Prices hidden.
- Totals hidden.
- Return-by date + policy printed.
- QR with scoped code (one-time return without revealing price to recipient).

### 212.3 Channels
- Print + email + SMS + AirDrop.

### 212.4 Return handling
- Gift return credits store credit (§40) by default unless paid-for matches card on file.

### 212.5 Edge cases
- Partial gift receipt: per-line toggle.

---

## 213. Reprint flow

### 213.1 Entry
- Any past invoice / receipt → detail → Reprint button.
- From POS "Recent sales" list.

### 213.2 Options
- Printer choice (if multiple configured).
- Paper size (80mm / Letter).
- Number of copies.

### 213.3 Reason (optional)
- Tenant-configurable: require reason for reprints > 7 days old.
- "Customer lost it" / "Accountant request" / etc.

### 213.4 Log
- Audit entry (§52) per reprint.

### 213.5 Fallback
- No printer → PDF share.

---

## 214. Discount engine

### 214.1 Types
- Percentage off (whole cart / specific line / category).
- Fixed $ off (whole cart / specific line).
- Buy-X-get-Y.
- Tiered ("10% off $50+, 15% off $100+, 20% off $200+").
- First-time customer.
- Loyalty tier (§117).
- Employee discount (by role).

### 214.2 Stacking
- Configurable: stackable vs exclusive.
- Order: percentage before fixed before tax (tenant-configurable).

### 214.3 Limits
- Per customer / per day / per campaign.
- Min purchase threshold.
- Excluded categories.

### 214.4 Auto-apply
- Engine runs each cart change; applies eligible without staff action.
- Banner shows "2 discounts applied".

### 214.5 Manual override
- Cashier can add ad-hoc discount (if permitted); triggers reason prompt + audit.
- Manager PIN if over threshold.

### 214.6 Server validation
- iOS computes optimistic; server re-validates to prevent fraud.

### 214.7 Reporting
- Discount effectiveness report: usage, revenue impact, margin impact.

---

## 215. Coupon codes

### 215.1 Model
- Code string (human-friendly like `SAVE10`).
- Discount rule linkage (§214).
- Valid from/to.
- Usage limit (total + per customer).
- Channel (any / online only / in-store only).

### 215.2 Entry
- POS checkout sheet has "Coupon" field.
- Validates live; shows discount applied.

### 215.3 QR coupons
- Printable / emailable QR containing code.
- Scan at checkout auto-fills.

### 215.4 Abuse prevention
- Rate-limit attempts per device.
- Invalid attempt logged (audit).

### 215.5 Affiliate codes
- Tie coupon code to staff member → tracks sales attribution.

---

## 216. Pricing rules engine

### 216.1 Time-based
- Happy hour 3-5pm = 10% off services.
- Weekend pricing adjustments.

### 216.2 Volume
- Buy 3 cases, 5% off each; buy 5 cases, 10%.

### 216.3 Customer-group
- Wholesale pricing for B2B tier.

### 216.4 Location-based
- Per-location pricing overrides (expensive metro vs suburb).

### 216.5 Promotion window
- Flash sales: on/off toggle with countdown timer visible to cashier.

### 216.6 UI
- Settings → Pricing rules.
- Rule list with priority order.
- Live preview: "Apply to sample cart" simulator.

### 216.7 Conflict resolution
- First matching rule wins (priority).
- Explicit stack rules if tenant configures.

### 216.8 Effective dates
- Schedule rules to auto-activate / deactivate.
- Calendar view.

---

## 217. Membership renewal reminders

### 217.1 Cadence
- 30 / 14 / 7 / 1 day before expiry.
- Channels: push + SMS + email (configurable per member).

### 217.2 Auto-renew
- If enrolled, card on file charged on renewal date.
- Notify success/failure.

### 217.3 Grace period
- 7 days post-expiry retain benefits; soft reminder.
- After grace: benefits suspended.

### 217.4 Reactivation
- One-tap reactivate with current card or new.
- Pro-rate remaining period credit.

### 217.5 Churn insight
- Report: expiring soon + at risk + churned.
- Segment for targeted offer (§127).

---

## 218. Dunning

### 218.1 Failed payment handling
- Card declined → queue retry.
- Retry schedule: +3d / +7d / +14d.
- Each retry: email + SMS + in-app notification.

### 218.2 Smart retry
- Soft declines (insufficient funds, do-not-honor): standard schedule.
- Hard declines (fraud, card reported): stop + notify customer to update card.

### 218.3 Self-service
- Customer portal link (§208) to update card.
- Apple Pay via pay page.

### 218.4 Escalation
- After N failed attempts: alert tenant manager; auto-suspend plan.

### 218.5 Audit
- Every dunning event logged.

---

## 219. Late fees

### 219.1 Model
- Flat fee / percentage / compounding.
- Grace period before applying.
- Max cap.

### 219.2 Application
- Auto-added to invoice on overdue.
- Status change to "Past due" triggers reminder.

### 219.3 Waive
- Staff can waive with reason + audit.
- Threshold above which manager PIN required.

### 219.4 Customer communication
- Reminder SMS / email before fee applied (1-3d).
- Fee-applied notification with payment link.

### 219.5 Jurisdiction limits
- Some jurisdictions cap late fees by law.
- Tenant-configurable max; warn on violation.

---

## 220. Buy-now-pay-later (evaluation)

### 220.1 Providers
- Affirm, Afterpay, Klarna, PayPal Pay-Later.
- BlockChyp may offer bridge; evaluate.

### 220.2 Decision
- Deferred past Phase 5.
- Non-trivial compliance (state usury laws, Reg Z).
- Revisit if tenant demand > 10%.

### 220.3 If enabled
- Tender type alongside card / cash.
- Flow: customer scans QR → approval on phone → terminal notified.
- Server-mediated; no direct BNPL SDK in iOS bundle.

### 220.4 Sovereignty
- BNPL provider is third-party — by definition a data egress.
- Tenant must explicitly opt in per tenant; privacy disclosure shown.

### 220.5 Refunds
- Split: BNPL provider refunds customer on provider's cycle; shop just marks invoice refunded.

---

## 221. Warranty claim flow

### 221.1 Warranty record
- Created on ticket close for each installed part / service.
- Fields: part_id, serial, install date, duration (90d / 1yr / lifetime), conditions.

### 221.2 Claim intake
- Customer returns with complaint → staff searches warranty by IMEI / receipt / name.
- Match shows prior tickets + install dates + eligibility.

### 221.3 Decision tree
- Within warranty + valid claim: new ticket status = Warranty Return; parts + labor zero-priced automatically.
- Out of warranty: new ticket status = Paid Repair.
- Edge cases (water damage, physical damage) flagged for staff judgment.

### 221.4 Part return to vendor
- Defective part marked RMA-eligible; staff ships via §132.3.

### 221.5 Customer notification
- Auto-SMS confirming warranty coverage; re-ETA estimate.

### 221.6 Reporting
- Warranty claim rate by part / by supplier / by tech — reveals quality issues.

### 221.7 Cost center
- Warranty repair costs labor + parts allocated to warranty cost center.
- Dashboard shows warranty cost vs revenue.

---

## 222. SLA tracking

### 222.1 SLA definitions
- Per service type: "Diagnose within 4h" / "Repair within 24h for priority" / "Respond to SMS in 30m".

### 222.2 Timer logic
- Start on intake / ticket create.
- Pause for statuses configured as "Waiting on customer" / "Awaiting parts".
- Resume on return to active state.

### 222.3 Visualization
- Ticket list row: SLA chip (green / amber / red) based on remaining time.
- Ticket detail: timer + phase progress.

### 222.4 Alerts
- Amber at 75% used; red at 100%.
- Push to assignee + manager when breached.

### 222.5 Reports
- Per tech: SLA compliance %.
- Per service: average time vs SLA.

### 222.6 Override
- Manager can extend SLA with reason (audit log).

### 222.7 Customer commitment
- SLA visible on public tracking page (§55) as "We'll update you by <time>".

---

## 223. QC checklist

### 223.1 Pre-close quality check
- Ticket can't be marked Ready until QC checklist complete.

### 223.2 Per-service checklist
- Configurable per repair type.
- Example iPhone screen: Display lights up / Touch works / Camera works / Speaker / Mic / Wi-Fi / Cellular / Battery health / Face ID / No new scratches.
- Each item: pass / fail / N/A + optional photo.

### 223.3 Failure handling
- Fail item: ticket returns to In Repair with failure noted.
- Require reason on flip back.

### 223.4 Sign-off
- Tech signature + timestamp.
- Optionally second-tech verification for high-value repairs.

### 223.5 Customer-visible
- Checklist printed on invoice (or receipt) so customer sees what was tested.
- Builds trust.

### 223.6 Audit
- QC history visible in ticket history; includes who tested, when.

---

## 224. Batch & lot tracking

### 224.1 Use-cases
- Regulated parts (batteries) require lot tracking for recalls.

### 224.2 Model
- `InventoryLot` per receipt: lot_id, receive_date, vendor_invoice, qty, expiry.
- Sale / use decrements lot FIFO by default (or LIFO per tenant).

### 224.3 FEFO alt
- Expiring-first queue for perishables (paste / adhesive).

### 224.4 Recalls
- Vendor recall → tenant queries "all tickets using lot X" → customer outreach.

### 224.5 Traceability
- Ticket detail can show which lot was used per part (for regulatory).

### 224.6 Config
- Per SKU opt-in (most SKUs don't need lot tracking).

---

## 225. Serial number tracking

### 225.1 Scope
- High-value items (phones, laptops, TVs).
- New-stock serials scanned on receive.

### 225.2 Intake
- Scan serial + auto-match model.
- POS scan on sale reduces qty by 1 for that serial.

### 225.3 Lookup
- Customer asks "is this serial stolen?" → staff scans → iOS hits tenant server which may optionally cross-check (§202).

### 225.4 Link to customer
- Sale binds serial to customer record (enables warranty lookup by serial).

### 225.5 Unique constraint
- Each serial sold once; sell-again requires "Returned / restocked" status.

### 225.6 Reports
- Serials out by month; remaining in stock.

---

## 226. Inter-location transfers

### 226.1 Flow
- Source location initiates transfer: pick items + qty + destination.
- Status: Draft → In Transit → Received.

### 226.2 Transit count
- Inventory marked "in transit" — not sellable at either location.

### 226.3 Receive
- Destination scans items.
- Discrepancy handling (§113.3).

### 226.4 Shipping label
- Print bulk label via §114.
- Optional carrier integration (UPS/FedEx).

### 226.5 Reporting
- Transfer frequency; bottleneck analysis.

### 226.6 Permissions
- Initiate + receive split; source manager initiates, destination manager receives.

---

## 227. Reconciliation

### 227.1 Daily
- Sales + payments + cash close + bank deposit all tie out.
- Dashboard shows variance per period.

### 227.2 Monthly
- Full reconciliation report (revenue, COGS, adjustments, AR aging, AP aging).
- Export to QuickBooks / Xero formats.

### 227.3 Variance investigation tool
- Clickable drill-down from total → lines → specific transaction → audit log.

### 227.4 Alerts
- Variance > threshold triggers manager push.

### 227.5 Close period
- Once reconciled, period locked; changes require manager override + audit.

---

## 228. Damage / scrap bin

### 228.1 Model
- Dedicated non-sellable bin per location.
- Items moved here with reason (damaged / obsolete / expired / lost).

### 228.2 Move flow
- Inventory → item → "Move to scrap" → qty + reason + photo.
- Decrements sellable qty; increments scrap bin.

### 228.3 Cost impact
- COGS adjustment recorded.
- Shrinkage report totals.

### 228.4 Disposal
- Scrap bin items batch-disposed (trash / recycle / salvage).
- Disposal document generated with signature.

### 228.5 Insurance
- Disposal records support insurance claims (theft, fire).

---

## 229. Dead-stock aging

### 229.1 Report
- Inventory aged > N days since last sale.
- Grouped by tier: slow (60d) / dead (180d) / obsolete (365d).

### 229.2 Actions
- Clearance pricing suggestions.
- Bundle with hot-selling item (§129).
- Return to vendor if eligible.
- Donate for tax write-off.

### 229.3 Alerts
- Quarterly push: "5 items hit dead tier — plan action."

### 229.4 Visibility
- Inventory list chip: "Stale" / "Dead" badge.

---

## 230. Reorder lead times

### 230.1 Per vendor
- Average days from order → receipt.
- Computed from PO history.

### 230.2 Lead-time variance
- Shows unreliability → affects reorder point.

### 230.3 Safety stock
- Buffer qty = avg daily sell × lead time × safety factor.
- Auto-calc or manual override.

### 230.4 Vendor comparison
- Side-by-side: cost, lead time, on-time %.
- Suggest alternate vendor when primary degrades.

### 230.5 Seasonality
- Lead times may lengthen in holiday season; track per-month.

### 230.6 Surface
- Inventory item detail shows "Lead time 7d avg (p90 12d)".
- PO creation uses latest stats for ETA.

---

## 231. Tenant admin tools (within iOS)

### 231.1 Scope limit
- Per §65 most management stays in Electron desktop app.
- iOS exposes essentials: team invites, roles, business hours, printers, basic settings.

### 231.2 Guard rails
- Destructive settings (data wipe, billing cancel) require web/desktop — iOS shows link.
- Reason: avoid accidental destructive taps on phone.

### 231.3 Admin view
- Settings → Organization.
- Tabs: Team / Locations / Hours / Billing / Branding / API Tokens.
- Each tab read/write where safe, read-only where not.

### 231.4 Sensitive ops
- Password change, 2FA setup: in iOS.
- Tenant delete, data export: web only with email confirm.

### 231.5 Audit
- Every admin op tagged in §52 audit log.

---

## 232. Per-tenant feature flags UI

§101 defines engine; this is UX.

### 232.1 Settings → Features
- List of enabled flags + default states.
- Each row: name, description, scope (tenant / role / user), current value.

### 232.2 Explanations
- Tap row → drawer with "What this does" + "Who can change" + recent changes.

### 232.3 Preview toggles
- Some flags have "Preview" mode: staged rollout to specific users.

### 232.4 Safety
- Destructive flags (e.g., "Disable PCI mode") require extra confirm + manager PIN.

### 232.5 Inheritance
- Tenant default → role override → user override.
- UI shows inheritance chain visually.

### 232.6 Reset to default
- Per flag + bulk reset.

---

## 233. Multi-tenant user session mgmt

### 233.1 Use cases
- Franchise operator: multiple tenant stores.
- Freelance tech: visits multiple tenants.

### 233.2 Per-tenant session
- Each tenant has own session (auth token, DB).
- Switching doesn't logout others.

### 233.3 Switch UI
- Top-right avatar chip shows current tenant.
- Tap → sheet with tenant list + quick-switch.

### 233.4 Data isolation
- Each tenant's local DB is separate SQLCipher file with unique passphrase.
- Memory-scrubbed on switch (no cross-leak).

### 233.5 Notifications
- Pushes tagged with tenant_id.
- Badge counts combined per-tenant; tapping opens correct tenant.

### 233.6 Login batch
- "Login all" convenience: enter each tenant URL once, app remembers; biometric re-auth unlocks each.

### 233.7 Limit
- Max 5 concurrent tenant sessions (prevent abuse).

---

## 234. Shared-device mode

### 234.1 Use case
- Counter iPad used by 3 cashiers.

### 234.2 Enable
- Settings → Shared Device Mode.
- Requires device passcode + management PIN to enable/disable.

### 234.3 Session swap
- User switch via Lock screen → tap "Switch user" → PIN.
- Token swap; no full re-auth unless inactive > 4h.

### 234.4 Auto-logoff
- Inactivity > 10 min (tenant-configurable) → returns to user-picker.

### 234.5 Separation
- Per-user drafts isolated.
- Current cart in POS bound to current user; user switch holds cart (park).

### 234.6 Staff list
- Pre-populated quick-pick grid of staff avatars.
- Tap avatar → PIN entry.

### 234.7 Restrictions
- Shared-device mode hides biometric (avoid confusion).
- Keychain scoped per staff via App Group entries.

---

## 235. PIN quick-switch

### 235.1 PIN setup
- Staff enters 4-6 digit PIN during onboarding.
- Stored as Argon2id hash in Keychain; salt per user.

### 235.2 Quick-switch UX
- Large number pad on lock screen.
- Haptic on each digit.
- Wrong PIN: shake + 3 attempts then 30s lockout + 60s / 5min escalation.

### 235.3 Recovery
- Forgot PIN → email reset link to tenant-registered email.
- Manager override: manager can reset staff PIN.

### 235.4 Mandatory PIN rotation
- Optional tenant setting: every 90d.
- Blocklist common PINs (1234, 0000, birthday).

### 235.5 Masking
- Digits shown as dots after entry.
- "Show" tap holds reveals briefly.

---

## 236. Session timeout

### 236.1 Thresholds
- Inactive > 15m → require biometric re-auth.
- Inactive > 4h → require full password.
- Inactive > 30d → force full re-auth including email.

### 236.2 Activity signals
- User touches, scroll, text entry.
- Not: silent push, background sync.

### 236.3 Warning
- 60s before forced timeout: overlay "Still there?" with Stay / Sign out buttons.
- Countdown ring visible.

### 236.4 Sensitive screens force re-auth
- Opening Payment / Settings § Billing / Danger Zone → immediate biometric prompt regardless of timeout.

### 236.5 Tenant-configurable
- Min values enforced globally (cannot be infinite).
- Max 30d.

### 236.6 Sovereignty
- No server-side idle detection; purely device-local.

---

## 237. Remember-me

### 237.1 Scope
- Remember email only (never password without biometric bind).
- Biometric-unlock stores passphrase in Keychain under Face-ID-gated item.

### 237.2 Device binding
- Stored creds tied to device class ID; if user migrates device, re-auth required.
- Blocks credential theft via backup export.

### 237.3 Per tenant
- Remember applies per tenant.

### 237.4 Revocation
- Logout clears stored creds.
- Server-side revoke clears on next sync.

### 237.5 A11y
- Assistive-Access mode defaults remember on to reduce re-auth friction.

---

## 238. 2FA enrollment

### 238.1 Required for roles
- Owner + manager + admin: mandatory.
- Others: optional.

### 238.2 Factor types
- **TOTP** — default; scan QR with Authenticator / 1Password.
- **SMS** — fallback only; discouraged (SIM swap risk).
- **Hardware key (FIDO2 / Passkey)** — recommended for owners.
- **Biometric-backed passkey** — iOS 17+ passkey via iCloud Keychain.

### 238.3 Enrollment flow
- Settings → Security → Enable 2FA.
- Generates secret → displays QR + manual code.
- User scans with Authenticator.
- Verify via entering current 6-digit code.
- Save recovery codes.

### 238.4 Back-up factor
- Require ≥ 2 factors: TOTP + recovery codes minimum.

### 238.5 Disable flow
- Requires current factor + password + email confirm link.

### 238.6 Passkey preference
- iOS 17+ promotes passkey over TOTP as primary.

---

## 239. 2FA recovery codes

### 239.1 Generation
- 10 codes, 10-char base32 each.
- Generated at enrollment; copyable / printable.
- One-time use.

### 239.2 Storage
- Not stored on device (user's responsibility).
- Server stores hashes only.

### 239.3 Display
- Reveal once with warning "Save these — they won't show again."
- Print + email to self options.

### 239.4 Regeneration
- Settings → Security → Regenerate codes (invalidates previous).

### 239.5 Usage
- Login 2FA prompt has "Use recovery code" link.
- Entering recovery code logs in + flags account: email sent to alert.

### 239.6 Admin override
- Tenant owner can reset staff recovery codes after verifying identity.

---

## 240. SSO / SAML

### 240.1 Providers
- Okta, Azure AD, Google Workspace, JumpCloud.
- SAML 2.0 primary; OIDC for newer.

### 240.2 Setup
- Tenant admin (web only) pastes IdP metadata.
- Certificate rotation notifications.

### 240.3 iOS flow
- Login screen "Sign in with SSO" button.
- Opens `ASWebAuthenticationSession` → IdP login → callback.
- Token exchange with tenant server.

### 240.4 SCIM (stretch)
- User provisioning via SCIM feed from IdP; auto-create / disable BizarreCRM accounts.
- Phase 5+.

### 240.5 Hybrid
- Some users via SSO, others local auth.
- Login screen auto-detects based on email domain.

### 240.6 Breakglass
- Tenant owner retains local password as breakglass if IdP down.

### 240.7 Sovereignty
- IdP is external by nature; per tenant consent; documented in privacy notice.
- No third-party IdP tokens stored beyond session lifetime.

---

## 241. Audit log viewer — MERGED INTO §52

Content moved to §52.5-§52.10. Number preserved.

---

## 242. Activity feed

### 242.1 Purpose
- Real-time stream: "Jane paid $120 invoice", "Mark completed ticket 4821".
- Not an audit log (no diffs); more like social feed.

### 242.2 Dashboard tile
- Compact: last 5 events.
- Expand → full feed.

### 242.3 Filters
- By team / location / event type / employee.

### 242.4 Interactivity
- Tap event → drill to entity.
- React with 👍 / 🎉 / ✅ (subtle, not a social app).

### 242.5 Notifications
- Per user: "Notify me when X happens to my tickets".

### 242.6 Privacy
- No customer PII in feed text (only IDs).

### 242.7 Pagination
- Infinite scroll; cursor-based.

---

## 243. Tenant business intelligence

### 243.1 Dashboard BI tab
- Reports tab gets a "BI" sub-tab for deeper analysis.

### 243.2 Built-in reports
- Revenue / margin by category / by tech / by customer segment.
- Repeat customer rate, time-to-repeat.
- Average ticket value trend.
- Conversion funnel: lead → estimate → ticket → invoice → paid.
- Labor utilization by tech.

### 243.3 Custom queries
- Visual query builder (no SQL): pick entity + filters + group + measure + timeframe.
- Save as widget.

### 243.4 Charts
- Swift Charts with zoom / pan / compare periods.
- Export PNG / CSV.

### 243.5 Drill-down
- Tap chart segment → underlying records list.

### 243.6 Scheduled delivery
- Tenant can schedule PDF snapshot emails.

### 243.7 Sovereignty
- All compute on tenant server.
- No external BI tool.

---

## 244. Custom dashboards per role

### 244.1 Tenant admin defines
- Template per role: which tiles visible.
- Cashier sees: today sales / shift totals / quick actions.
- Tech sees: my queue / my commission / tasks.
- Manager sees: revenue / team perf / low stock.

### 244.2 User customization
- Users can reorder tiles within allowed set.
- Drag-to-rearrange on iPad.

### 244.3 Saved views
- Multiple named dashboards per user ("Morning", "End of day").
- Quick-switch via tab.

### 244.4 Widgets
- Shared with §199 widgets; same data plumbing.

### 244.5 Compact default
- New users get curated minimal set.
- Reveal advanced on demand (avoid overwhelm).

---

## 245. Goals & targets widget

### 245.1 Goal types
- Daily revenue goal.
- Weekly ticket-count goal.
- Monthly avg-ticket-value goal.
- Personal: my commission goal.

### 245.2 Visualization
- Progress ring (fills as goal met).
- Tappable → detail with trajectory.

### 245.3 Streaks
- "5 days in a row hitting daily goal" — subtle celebration (confetti once per streak milestone).
- Respects Reduce Motion (no confetti).

### 245.4 Miss handling
- Supportive tone: "Tomorrow's a new day."
- No guilt UI (non-judgmental).

### 245.5 Per-tenant ops toggle
- Tenant can disable goals entirely (some shops don't do sales culture).

---

## 246. Leaderboards

### 246.1 Optional
- Tenant-opt-in; default off.

### 246.2 Scope
- Per team / location.
- Metrics: tickets closed, sales $, avg turn time.

### 246.3 Anonymization
- Own name always shown; others optionally initials only.
- Prevents public shaming culture.

### 246.4 Timeframes
- Daily / weekly / monthly / quarterly.

### 246.5 Fairness
- Weighted by shift hours; part-time not unfairly compared.
- Excludes unusual outliers (single big ticket).

### 246.6 Notifications
- Weekly summary only; no daily hounding.

### 246.7 Opt-out per user
- "Hide my name from leaderboards" in settings.

---

## 247. Gamification guardrails

### 247.1 Principles
- Playful, not manipulative.
- No dark patterns (streak-breaking anxiety, loss aversion).
- Never tie gamification to real $ rewards (that's compensation, not a game).

### 247.2 Allowed
- Subtle celebration on milestones.
- Badges for shop achievements (first 100 tickets, 1 year anniversary).
- Friendly nudges (not pushy).

### 247.3 Banned
- Auto-posting to team chat without consent.
- Forced enrollment.
- Countdown timers to create urgency.
- Loot-box mechanics.

### 247.4 Opt-out global
- Settings → Appearance → "Reduce celebratory UI" → off confetti, sparkles, etc.

### 247.5 Anti-addictive
- No pull-to-refresh slot-machine animations.
- Deterministic updates.

---

## 248. Employee scorecards

### 248.1 Metrics
- Ticket close rate, SLA compliance, customer rating, revenue attributed, commission earned, hours worked, breaks taken.

### 248.2 Private by default
- Only self + manager sees.
- Owner sees all.

### 248.3 Feedback
- Manager can annotate scorecard with notes + praise / coaching signals.
- Visible to employee.

### 248.4 Trend
- Rolling 30/90/365d.
- Chart per metric.

### 248.5 Review meeting helper
- "Prepare review" button compiles scorecard + self-review form + manager notes into PDF for HR file.

### 248.6 Objective vs subjective
- Distinguish hard metrics from manager subjective rating.
- Scale for subjective (1-5 with descriptors).

---

## 249. Peer feedback

### 249.1 Request
- Staff can request feedback from 1-3 peers during review cycle.

### 249.2 Form
- 4 prompts: what's going well / what to improve / one strength / one blind spot.
- Anonymous by default; peer can attribute optionally.

### 249.3 Delivery
- Submitted to manager who curates before sharing with subject.
- Prevents rumor / hostility.

### 249.4 Frequency cap
- Max once / quarter per peer requested; prevents feedback fatigue.

### 249.5 A11y
- Long-form text input; voice dictation.

---

## 250. Recognition cards

### 250.1 Shoutouts
- Staff sends a short "Nice job on that fix" to peer — attached to optional ticket.
- Appears in peer's profile + team chat (if opted).

### 250.2 Categories
- "Customer save" / "Team player" / "Technical excellence" / "Above and beyond".

### 250.3 Frequency
- Unlimited sending; no leaderboard of shoutouts (avoid gaming).

### 250.4 Receipt
- Recipient gets push notification.
- Archive in profile.

### 250.5 Export
- End of year: print "recognition book" PDF.

### 250.6 Privacy
- Private (just recipient + sender) or team-visible (recipient opt-in).

---

## 251. Customer tags & segments

### 251.1 Tag system
- Free-form strings (`vip`, `corporate`, `recurring`, `late-payer`).
- Color-coded; tenant-defined palette.
- Auto-tags applied by rules ("LTV > $1000 → gold").

### 251.2 UI
- Customer detail header chip row.
- Tap tag → filter customer list.
- Bulk assign from list multi-select.

### 251.3 Hierarchy
- Tags can nest ("wholesale > region > east").
- Drill-down filters.

### 251.4 Segments
- Saved tag combos + filters ("VIP + last visit < 90d").
- Used for marketing (§127), pricing (§216.3).

### 251.5 Tag limits
- Max 20 tags per customer to prevent mess.
- Warn at 10.

### 251.6 Discovery
- "Suggested tags" based on customer behavior (e.g., system suggests `late-payer` if 3 overdue invoices).

---

## 252. Customer 360

### 252.1 Single pane
- Customer detail unifies: tickets / invoices / payments / SMS / email / appointments / notes / files / feedback.

### 252.2 Timeline
- Vertical chrono with colored dots per event type.
- Filter chips to narrow.
- Jump-to-date picker.

### 252.3 LTV + metrics header
- LTV, last visit, avg spend, repeat rate, preferred services, churn risk score.

### 252.4 Relationship graph
- Household / business relationships: link family / coworker accounts.
- "Related customers" card.

### 252.5 Files
- Photos, waivers, emails archived in one tab.

### 252.6 Notes pin
- Star important notes to pin at top.
- Visible across ticket/invoice/SMS contexts.

### 252.7 Warnings
- Customer-level flags ("cash only", "known difficult", "VIP treatment") — staff-visible banner.

---

## 253. Merge & dedup

### 253.1 Detection
- System flags potential duplicates on create: same phone / same email / similar name + address.
- Suggests merge at entry.

### 253.2 Merge UI
- Side-by-side record comparison.
- Per-field pick winner or combine.
- Contact methods combined (all phones + all emails).

### 253.3 Data migration
- Tickets, invoices, notes, tags, SMS threads, payments all migrated to survivor.
- Loser record tombstoned with audit reference.

### 253.4 Undo window
- 24h to unmerge; after that permanent (audit preserves trail).

### 253.5 Periodic dedup
- Settings → Data → Run dedup scan → lists candidates.
- Manager reviews batch.

### 253.6 Automerge safe-cases
- Optional: auto-merge when 100% phone + email match.

---

## 254. Preferred comms channel

### 254.1 Per customer
- Customer record: preferred channel for receipts / status / marketing (SMS / email / push / none).
- Times-of-day preference.

### 254.2 Opt-out granularity
- Opt out of marketing but keep transactional.
- Per-category.

### 254.3 Language
- Preferred language for comms.
- Templates auto-use that locale.

### 254.4 Respect
- System blocks sends against preference.
- Staff override possible with reason + audit.

### 254.5 Setup
- At ticket intake, quick "How'd you like updates?" prompt with SMS/email toggles.

---

## 255. Birthday automation

### 255.1 Data
- Optional birth date on customer record.
- Age not stored unless tenant explicitly needs it.

### 255.2 Automation
- Day-of: auto-send SMS or email template ("Happy birthday! Here's $10 off.")
- Opt-in per customer.

### 255.3 Coupon injection
- Unique coupon (§215) per recipient; 7-day expiry.

### 255.4 Privacy
- Birth date never shown in lists / leaderboards.
- Age-derived features off by default.

### 255.5 Exclusions
- Last-60-days visited customers get a less salesy message.
- Churned customers get reactivation variant.

---

## 256. CSAT + NPS

### 256.1 Post-service survey
- After ticket close, auto-SMS link: "Rate your experience 1-5 [link]".
- One-tap reply-with-digit for 1-5.

### 256.2 NPS
- Quarterly: "How likely are you to recommend us 0-10?"
- Don't over-send — max 2 / year.

### 256.3 Free-text follow
- After rating, optional comment.

### 256.4 Internal dashboard
- Score trend, comments feed, per-tech breakdown.
- Anonymized per-tech unless tenant configures open.

### 256.5 Low score alert
- 1-2 star → immediate manager push to recover.
- Recovery playbook: call within 2h.

### 256.6 Public reviews
- High scores nudge customer to leave Google / Yelp review (§260).

---

## 257. Complaint tracking

### 257.1 Intake
- Staff logs complaint via customer detail → "New complaint".
- Category + severity + description + linked ticket.

### 257.2 Resolution flow
- Assignee + due date + escalation path.
- Status: open / investigating / resolved / rejected.

### 257.3 Root cause
- Required on resolve: product / service / communication / billing / other.
- Aggregated for trend analysis.

### 257.4 SLA
- Response within 24h / resolution within 7d.
- Breach alerts.

### 257.5 Customer visibility
- Optional: share resolution publicly with customer via tracking page.

### 257.6 Audit
- Full history; immutable once closed.

---

## 258. Punch-card loyalty

### 258.1 Model
- Visual punch card per service type ("5th repair free", "10th wash free").
- Count auto-increments on eligible service.

### 258.2 Storage
- Server-side; iOS displays.
- Wallet pass (§117.4) with updating strip.

### 258.3 UI
- Customer detail shows punch cards.
- Progress icons (filled vs empty).

### 258.4 Redemption
- Last punch = free next service; discount auto-applied at POS.

### 258.5 Combo rule
- Can't stack with other discounts unless configured.

### 258.6 Expiry
- Optional: punches expire 12mo after last activity.

### 258.7 Multi-location
- Tenant config: cards shared across locations vs per-location.

---

## 259. Referral tracking — MERGED INTO §118

Content moved to §118. Number preserved.

---

## 260. Review solicitation

### 260.1 Google / Yelp integration
- After high CSAT (§256), offer customer to leave public review.
- Link via share sheet (no auto-post).

### 260.2 Review link shortcut
- Tenant configures Google Business / Yelp URLs.
- Staff can tap "Send review link" from customer detail.

### 260.3 Limit
- Once per 180 days per customer.

### 260.4 Incentive compliance
- Per Google / Yelp terms, no cash/points for reviews.
- System blocks tying reviews to discounts.

### 260.5 Monitoring
- Settings → Reviews → list of platforms.
- External review alert push (via tenant-configured monitoring, optional).

### 260.6 Response templates
- Staff can draft responses in-app but posts on external platforms (iOS opens Safari).

### 260.7 Sovereignty
- iOS never calls third-party review APIs directly.
- All external links open in `SFSafariViewController`.

---

## 261. Customer notes deep

### 261.1 Note types
- Quick (one-liner).
- Detail (rich text, attachments).
- Call summary.
- Meeting.
- Internal-only (not visible on customer-facing docs).

### 261.2 Pinning
- Pin critical notes to customer header.
- Max 3 pinned (keeps header tidy).

### 261.3 Mentions
- @mention teammate → push + link.
- @ticket → backlinks.

### 261.4 Access control
- "Internal-only" flag hides note from SMS/email auto-include.
- Role-gate sensitive notes (manager only).

### 261.5 Templates
- Quick insert: "Called, left voicemail", "Reviewed estimate", etc.

### 261.6 Edit history
- Edits logged; previous version viewable.

### 261.7 A11y
- Rich text accessible via VoiceOver element-by-element.

---

## 262. Files cabinet

### 262.1 Per-customer file list
- PDF, images, spreadsheets, waivers, warranty docs.
- Tags + search.

### 262.2 Upload
- Camera / Photos / Files picker / iCloud / external drive.

### 262.3 Preview
- `QLPreviewController` inline.
- Mark up with PencilKit (PDF annotation).

### 262.4 Sharing
- Share sheet → customer email / AirDrop.

### 262.5 Retention
- Tenant policy per file type.
- Auto-archive old.

### 262.6 Encryption
- Files encrypted at rest (tenant storage) and at transit.
- Offline-cached files encrypted in SQLCipher-wrapped blob store.

### 262.7 Versioning
- Replace file → previous kept with version number.

---

## 263. Document scanner deep

### 263.1 Entry
- Customer detail / ticket detail → "Scan document".
- Uses `VNDocumentCameraViewController`.

### 263.2 Multi-page
- Scan N pages; auto-crop + perspective correct.
- Reorder / delete before save.

### 263.3 OCR
- `VNRecognizeTextRequest` — text extracted searchable via FTS5.

### 263.4 Output
- PDF (preferred) or JPEG.
- 200 DPI default.

### 263.5 Auto-classification
- Detects license / invoice / receipt / warranty by keyword.
- Suggests tag.

### 263.6 Privacy
- No external OCR (on-device Vision).
- No upload to cloud OCR service.

### 263.7 Bulk
- Multiple scans appended to single file.

---

## 264. Contacts import

### 264.1 Permission
- `CNContactStore.requestAccess` — just-in-time at "Import".

### 264.2 Picker
- `CNContactPickerViewController` single or multi-select.

### 264.3 Field mapping
- vCard → customer: name, phones, emails, address, birthday.
- Field selection if multiple.

### 264.4 Duplicate handling
- Cross-check existing customers (§253).
- Merge / skip / create new.

### 264.5 Bulk
- "Import all" opens confirm sheet with summary (skipped / created / updated).

### 264.6 Privacy
- Read-only; never writes back to Contacts.
- Clear data if user revokes permission.

### 264.7 A11y
- VoiceOver announces counts at each step.

---

## 265. Magic-link login

### 265.1 Flow
- Login screen "Email me a link" → enter email → server emails link.
- Tap link on device → Universal Link opens app → auto-exchange for token.

### 265.2 Link lifetime
- 15min.
- One-time use.

### 265.3 Device binding
- Link valid on same device as request (fingerprint match).
- Cross-device requires 2FA confirm.

### 265.4 Tenant gate
- Tenant can disable magic links (strict security mode).

### 265.5 Phishing defense
- Link preview shows tenant name explicitly.
- Domain pinned to `app.bizarrecrm.com`.

---

## 266. Passkey login

### 266.1 iOS 17+ passkeys
- `ASAuthorizationController` with `ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest`.
- iCloud Keychain syncs across Apple devices.

### 266.2 Enrollment
- Settings → Security → Add passkey → Face ID / Touch ID confirm.
- Stored with tenant server (FIDO2 credential).

### 266.3 Login
- Login screen "Use passkey" button.
- System UI prompts; no password typed.

### 266.4 Fallback
- Password remains on account as breakglass.
- Can remove password if passkey + recovery codes set.

### 266.5 Cross-device
- Passkey syncs via iCloud to iPad / Mac.
- Android coworker uses password still; no cross-OS passkey sync yet.

### 266.6 Recovery
- Lose all Apple devices → recovery codes (§239).

---

## 267. WebAuthn on iPad

### 267.1 Hardware key
- YubiKey 5C (USB-C) plugs into iPad; triggers passkey flow.
- Useful for shared iPad where individual iCloud not set.

### 267.2 NFC key
- Tap Yubikey to iPad back for NFC auth (iPad Pro 13" 2024 with NFC).

### 267.3 Security levels
- Owners: hardware key recommended.
- Staff: optional.

### 267.4 UI
- Settings → Security → Hardware keys → "Register YubiKey".
- Management: list keys + last-used + revoke.

### 267.5 Attestation
- Tenant policy can require attested hardware.

---

## 268. Sheet keyboard avoidance

### 268.1 Problem
- Bottom sheets (`.presentationDetents`) over keyboard hide content.

### 268.2 Pattern
- Sheet root uses `.ignoresSafeArea(.keyboard)` + inner scroll.
- `defaultScrollAnchor(.bottom)` on active compose.
- `.scrollDismissesKeyboard(.interactively)` — drag sheet down also dismisses keyboard.

### 268.3 Detent switching
- Start at `.medium`, promote to `.large` on keyboard show.
- Smooth with `.animation`.

### 268.4 Picker conflicts
- Date pickers / segmented pickers inside sheets need `.submitLabel(.done)` + explicit commit.

### 268.5 External keyboard
- Keyboard avoidance no-ops; sheet stays as sized.

---

## 269. Diagnostic exporter

### 269.1 Entry
- Settings → Diagnostics → "Export diagnostic bundle".

### 269.2 Contents
- App version, OS version, device model.
- Feature flags snapshot.
- Last 100 log entries (auto-redacted).
- Last crash diagnostic.
- Sync queue status.
- Network connectivity summary.

### 269.3 Format
- ZIP of JSON files + README.
- Size capped 10MB (truncate logs if over).

### 269.4 PII redaction
- Token / password / phone / email scrubbed before pack.
- Confirmation sheet shows what's included before export.

### 269.5 Delivery
- Share sheet: save to Files / email tenant admin / AirDrop.
- Never auto-upload.

### 269.6 Use in bug report
- §137 form embeds diagnostic bundle optionally.

---

## 270. On-device ML perf notes

### 270.1 Capabilities by chip
- A17+ / M-series: Apple Intelligence full.
- A15 / A16: partial (on-device Writing Tools slower).
- A14 and earlier: disabled, fall back to server WritingTools if tenant has one.

### 270.2 Neural Engine budget
- Each inference 50-300ms typical; batch where possible.
- Avoid on cold start (user waiting).

### 270.3 Background inference
- Run during `BGProcessingTask` when device charging.
- Pre-compute suggestion candidates for SMS thread.

### 270.4 Memory
- Models loaded lazily; unload on memory warning.

### 270.5 Model caching
- Apple-provided models cached by OS.
- Our domain-specific models (if any) ship as bundle resources; lazy-load.

### 270.6 Fallback chain
- Apple Intelligence → tenant-server ML (if available) → disabled (no third-party).

### 270.7 Sovereignty
- No Hugging Face / OpenAI / Anthropic / Gemini calls.
- Content stays on device or goes to tenant server per §32.

---

## 271. Hardware inventory (per tenant)

### 271.1 Device registry
- Each iPad / iPhone used in shop registered to tenant.
- Fields: serial, device model, iOS version, location, assigned user, last-seen, app version.

### 271.2 MDM hints
- Encourage tenant to enroll in Apple Business Manager + MDM (Jamf / Kandji) for fleet management.
- App reads MDM-managed-configuration keys (server URL, kiosk-mode flag).

### 271.3 Lost device
- Owner can remote-sign-out device from web portal.
- Next launch shows "Signed out by admin".

### 271.4 Health pings
- Each device posts daily heartbeat (tenant-server only).
- Dashboard tile: "3 devices / 2 online".

### 271.5 Bulk config
- Managed app config pushes tenant URL, flags at install.
- No user interaction required in MDM scenarios.

### 271.6 App version floor
- Server rejects tokens from app versions below policy floor; prompts update.

---

## 272. Terminal pairing UX (BlockChyp)

### 272.1 Discovery
- Tap "Pair terminal" → Bluetooth scan + Wi-Fi Bonjour scan.
- Shows nearby devices; filter by vendor.

### 272.2 Handshake
- Tap device → generate pairing code on terminal → enter in app.
- Exchange certificates.

### 272.3 Tenant bind
- Terminal tied to tenant server; config synced.

### 272.4 Test transaction
- "Run $0.01 test" → verifies round-trip.
- Auto-void the test amount.

### 272.5 Multi-terminal
- Per location supports multiple terminals.
- UI labels each ("Front counter", "Back bench").

### 272.6 Troubleshoot
- Diagnostics: connection status, firmware version, last transaction time.
- Log export tied to tenant ticket.

### 272.7 Re-pair
- Factory reset terminal → re-pair via same flow.
- Old pairing revoked.

---

## 273. Network config wizard

### 273.1 First-run
- After login, verifies: internet OK, tenant reachable, printer reachable, terminal reachable.
- Each check shows green/red with fix link.

### 273.2 Captive-portal detection
- If on Wi-Fi with captive portal, banner + "Open portal" button.

### 273.3 VPN handling
- Detects VPN active; warns if interfering.

### 273.4 Tenant URL health
- Pings tenant server periodically; latency chart in Settings → Diagnostics.
- Alert if p95 > 1s sustained.

### 273.5 Hotspot fallback
- If on cellular + tenant uses local IP printer, app surfaces warning.
- Suggests switching Wi-Fi.

### 273.6 Multi-SSID
- Tenant can store multiple trusted SSIDs (shop + backup).
- Auto-reconnect hints.

---

## 274. Static-IP printers

### 274.1 Config
- Settings → Hardware → Printer → manual IP entry.
- Port optional (default 9100 raw / 631 IPP).

### 274.2 Reachability
- Ping before save.
- Badge: online / offline.

### 274.3 Fallback
- Bonjour discovery (§275) if IP changes.

### 274.4 DHCP reservation
- Recommend tenant set DHCP reservation for printer MAC.
- App shows MAC after first connection.

---

## 275. Bonjour discovery

### 275.1 Protocol
- `NWBrowser` for `_ipp._tcp`, `_printer._tcp`, `_airdrop._tcp`, custom `_bizarre._tcp`.

### 275.2 Permission
- iOS 14+ requires `NSBonjourServices` in Info.plist.
- Add all needed types up-front.

### 275.3 Local-network
- `NSLocalNetworkUsageDescription` explains why.

### 275.4 Picker UI
- Grouped by type.
- Icon per device class.

### 275.5 Ticker
- Auto-refresh every 10s.
- Manual refresh button.

---

## 276. Bluetooth device management

### 276.1 CoreBluetooth
- `CBCentralManager` scan for peripherals.
- MFi cert required for commercial printers.

### 276.2 Background
- `bluetooth-central` background mode registered.
- Maintain connection across app backgrounding (required for POS).

### 276.3 Permission
- `NSBluetoothAlwaysUsageDescription`.

### 276.4 Paired list
- Settings → Hardware → Bluetooth → list paired + connection state.
- Forget button per entry.

### 276.5 Battery
- Peripheral battery level surfaced where published.
- Low-battery warning.

### 276.6 Interference
- Multiple clients same peripheral: warn.

---

## 277. Peripheral reconnect

### 277.1 Auto
- On disconnect, retry every 5s up to 30s.
- After 30s, surface banner "Printer offline".

### 277.2 Exponential backoff
- If sustained offline, back off to every 60s to save battery.

### 277.3 User action
- Manual "Reconnect" button bypasses backoff.

### 277.4 Silent for non-critical
- Scanner offline = silent (user sees badge).
- Printer offline = banner (POS needs it).
- Terminal offline = blocker (can't charge cards).

### 277.5 Event log
- Connection events logged (helps troubleshooting).

---

## 278. Firmware update prompts

### 278.1 Terminal firmware
- BlockChyp SDK reports version; comparison to latest.
- Banner: "Terminal firmware outdated — update now".
- Scheduled update (after hours default).

### 278.2 Printer firmware
- Star / Epson / Zebra SDKs expose version + update API.
- Prompt manager; user confirms before applying.

### 278.3 Rollback
- Keep previous firmware available if supported.

### 278.4 Downtime
- Shows expected duration; warns against during open hours.

### 278.5 Safety
- Never auto-apply without consent.
- Log every attempt + result.

---

## 279. Weight scale integration

### 279.1 Use cases
- Repair shops charging by weight (rare but happens — e.g., scrap metal, parts by weight).

### 279.2 Hardware
- Bluetooth scale (Dymo M10 / Brecknell / etc.).
- USB via USB-C dongle.

### 279.3 Flow
- POS: add item → "Weigh" button → reading captures live.
- Zero-tare / re-weigh controls.

### 279.4 Precision
- Grams / ounces / pounds / kilograms.
- Tenant chooses unit system.

### 279.5 Rate-by-weight
- Item price rule "$/lb".
- Total auto-computes.

### 279.6 Trade regulation
- NTEP-certified scale required for commercial US sales.
- Tenant responsibility; app just integrates.

---

## 280. Cash drawer trigger

### 280.1 Connected via printer
- Most thermal receipt printers have RJ11 cash-drawer port.
- Fire "kick" command on specific tenders (cash / checks).

### 280.2 Config
- Settings → Hardware → Cash drawer → enable + choose printer binding.
- Test "Open drawer" button.

### 280.3 Alternate
- USB-connected direct-to-iPad via adapter (less common).

### 280.4 Permission override
- Manager can open drawer without sale (reconciliation).
- Requires manager PIN; audit.

### 280.5 Sensors
- Some drawers report open/closed status via printer bus.
- Warning if left open > 5 minutes.

### 280.6 Security
- Drawer-open events in audit log with cashier + time.
- Anti-theft signal (multiple opens without sale → alert).

---

## 281. Ticket labels

### 281.1 Separate from status
- Status = lifecycle state (one at a time).
- Label = optional flag (many).
- Examples: urgent, VIP, warranty, insurance claim, parts-ordered, QC-pending.

### 281.2 Visual
- Color-coded chips on list rows.
- Filter by label.

### 281.3 Automation
- Rules: "All tickets with device-value > $500 auto-label VIP".
- "All parts-ordered auto-label on PO link".

### 281.4 Bulk
- Multi-select → apply/remove label.

### 281.5 Labels vs tags
- Ticket labels — ticket-scoped.
- Customer tags — customer-scoped.
- Don't conflate.

### 281.6 Report
- Labels break out in revenue/duration reports ("Insurance claims avg turn time = 8d").

---

## 282. Estimate versioning

### 282.1 Revision tracking
- Each edit creates new version; prior retained.
- Version number visible: "v3".

### 282.2 Customer-sent versions
- Only "sent" versions archived for audit.
- Drafts freely edited.

### 282.3 Diff
- Side-by-side v-n vs v-n+1.
- Highlight adds / removes / price changes.

### 282.4 Customer approval tied to version
- If customer approved v2 but tenant edited to v3, warning "Customer approved v2; resend?".

### 282.5 Convert-to-ticket
- Uses approved version; stores reference so downstream changes don't invalidate.

### 282.6 Template diff
- Same machinery for receipt templates, waivers (§126.6).

---

## 283. ID / numbering formats

### 283.1 Tenant-configurable
- Settings → Numbering.
- Separate formats for: tickets / invoices / estimates / POs / receipts.
- Placeholder vocabulary: `{YYYY}`, `{YY}`, `{MM}`, `{DD}`, `{LOC}`, `{SEQ:6}` (6-digit zero-padded), `{INIT}` (creator initials).

### 283.2 Examples
- Ticket: `T-{YYYY}{MM}-{SEQ:5}` → `T-202604-00123`.
- Invoice: `INV-{YY}-{SEQ:6}` → `INV-26-000456`.

### 283.3 Reset cadence
- SEQ resets never / yearly / monthly / daily.

### 283.4 Uniqueness
- Server enforces; collision → retry.

### 283.5 Migration
- Tenant switches format → existing IDs unchanged; new IDs follow new pattern.

### 283.6 Lookup
- Global search accepts format-agnostic input (typing `123` or `T-202604-00123` both work).

---

## 284. Fiscal periods

### 284.1 Fiscal year
- Tenant sets start month (Jan default; some retailers use Feb / Jul).

### 284.2 Periods
- Daily / weekly / monthly / quarterly / annual reports align.

### 284.3 Period close
- Month-end close locks transactions; after close, edits require reopen (manager).

### 284.4 Reporting
- P&L / balance-sheet by fiscal period.
- Export to accountant.

### 284.5 Multi-fiscal support
- Tenant can keep calendar-year for internal + fiscal-year for external reporting (optional).

---

## 285. Multi-currency

### 285.1 Tenant base currency
- Set at setup (§36); cannot change lightly.

### 285.2 Foreign customers
- Customer record supports preferred currency.
- Invoice / receipt may display both.

### 285.3 Rates
- Daily rate fetched from tenant server (not third-party).
- Tenant can override manually.

### 285.4 Rate at transaction time
- Stored with invoice (freezes); report uses historical.

### 285.5 Payment
- Charge in base currency unless BlockChyp supports multi-currency (check per tenant).

### 285.6 Display
- User preference: always base / always customer / side-by-side.

### 285.7 Rounding
- Per currency precision (JPY 0 decimals; USD 2; TND 3; etc.).

---

## 286. Rounding rules

### 286.1 Methods
- Banker's (round-half-even) — default.
- Half-up — retail traditional.
- Half-down — rare.

### 286.2 Scope
- Per-line vs aggregate — tenant setting.

### 286.3 Cash rounding
- Countries without small coinage (Canada — no penny; Sweden — no öre).
- Tenant enables "Cash round to nearest 5¢".
- Only affects cash tender; card charges exact.

### 286.4 Tax rounding
- §116.3 reiterates.

### 286.5 Display
- Receipt line: sub-total, rounding adjustment, total.

### 286.6 Audit
- Rounding settings changes logged.

---

## 287. Currency display per customer

### 287.1 Templates
- Tenant chooses symbol placement (pre/post), thousands separator, decimal separator per locale.
- Overridable per customer.

### 287.2 Examples
- US: `$1,234.56`.
- EU (FR): `1 234,56 €`.
- JP: `¥1,235`.
- CH: `CHF 1'234.56`.

### 287.3 Input parsing
- Accept both locales as input in money fields; normalize to storage.

### 287.4 Accessibility
- VoiceOver reads "one thousand two hundred thirty-four dollars fifty-six cents".

### 287.5 ISO code vs symbol
- Default symbol; option for 3-letter code on invoices (reduces ambiguity cross-border).

---

## 288. Template versioning

### 288.1 Everything versioned
- Receipt, invoice, quote, waiver, email, SMS templates all versioned.

### 288.2 Default vs active
- Latest is active.
- "Draft" version editable; publish → new active.

### 288.3 Archive
- Old versions retained; used for reprint of historical documents (preserve intent).

### 288.4 Rollback
- Manager can roll back to prior version.
- Audit.

### 288.5 Lock
- Compliance template (waivers) locked once legal approves; edit = new version + re-sign required.

---

## 289. Dynamic price displays (CFD / ticket detail)

### 289.1 Live recompute
- Price changes animate with tick-up / tick-down per digit.
- Small font-weight shift on change for quick visual recognition.

### 289.2 Discount highlight
- Discount line flashes briefly on apply.
- Strike-through original → new.

### 289.3 Pending recompute
- If server validation in-flight, price shown with subtle shimmer; finalizes on response.

### 289.4 Mismatch resolution
- If server returns different total, UI shows "Tax recomputed (+$0.03)" banner.

### 289.5 A11y
- Screen reader announces new total on change (debounced).

---

## 290. Clock-drift guard

### 290.1 Detection
- On startup + every sync, compare device clock to server time.
- If drift > 2 min, flag.

### 290.2 User warning
- Banner: "Device clock off by X minutes — may cause login issues."
- Suggest auto-time on.

### 290.3 TOTP gate
- 2FA TOTP fails if drift > 30s.
- Auto-retry with adjusted window once; then hard error.

### 290.4 Timestamp logging
- All client timestamps include UTC offset; server stamps its own time.
- Audit uses server time as authoritative.

### 290.5 Offline timer
- For sync-pending ops, record both device time + offline duration so server can reconcile.

---

## 291. Dashboard density modes

### 291.1 Modes
- Comfortable (default iPhone) — larger spacing, 1-2 columns.
- Cozy (default iPad) — medium spacing, 2-3 columns.
- Compact (power user) — dense grid, 3-4 columns, smaller type.

### 291.2 Per-user
- Settings → Appearance → Dashboard density.
- Persists across devices via iCloud Keychain sync (optional; off for shared devices).

### 291.3 Tokens
- Density token feeds spacing rhythm (§100.20).
- Reduce Motion unaffected; density orthogonal.

### 291.4 Preview
- Live preview in settings (shows real dashboard) as user toggles.

---

## 292. Glass strength levels

### 292.1 Levels
- Strong — iOS 26 refraction full.
- Medium — thin material + slight tint.
- Minimal — opaque tint (for Reduce Transparency / Low Power).

### 292.2 Auto-selection
- iOS 26 + A17+ → Strong.
- iOS 26 + A14-A16 → Medium.
- Pre-iOS 26 → Medium.
- Low Power / Reduce Transparency → Minimal.

### 292.3 Manual override
- Settings → Appearance → Glass intensity (slider or 3 buttons).
- Doesn't disable glass entirely (brand continuity).

### 292.4 Perf impact
- Strong: ~2% extra GPU on scroll; acceptable on ProMotion.
- Minimal: effectively free.

### 292.5 Contrast
- Regardless of level, text-on-glass remains ≥ 4.5:1.

---

## 293. Sound design catalog

### 293.1 Sound list
- Sale success — coin drop (brand) 350ms.
- Card tap — light click 80ms.
- Scan match — pitched confirm 120ms.
- Drawer open — thud 250ms.
- Error — subtle buzz 200ms.
- Incoming SMS — soft bell.
- Payment approved — cash register ching.
- Backup complete — ascending triad.

### 293.2 Authoring
- All ≤ 2s, 44.1kHz mono AAC.
- Mastered to −14 LUFS so sounds blend rather than startle.

### 293.3 Tenant choice
- Each category has default + 2 alternates.
- Tenant admin picks in Settings → Appearance → Sounds.

### 293.4 Respect
- Silent switch honored.
- Focus modes honored.
- User per-category toggle in Settings.

### 293.5 Accessibility
- Sound paired with haptic when possible so deaf users still perceive.

### 293.6 Licensing
- All sounds created in-house or royalty-free; no third-party ASCAP/BMI risk.

---

## 294. Brand mark usage

### 294.1 Primary mark
- Wordmark "Bizarre" in Barlow Condensed.
- Icon glyph: stylized repair wrench intersecting spark.

### 294.2 Where used
- Launch screen.
- Login splash.
- About screen.
- Printed receipts (header).
- Empty-state illustrations.

### 294.3 Don't-use
- Don't recolor outside brand palette.
- Don't distort.
- Don't stack on glass without glass-container wrapping.

### 294.4 Tenant co-branding
- Tenant logo takes top billing on printed docs.
- "Powered by Bizarre" small foot.

### 294.5 Sizing
- Min 44pt tap target on tappable marks.
- Min 120pt width on receipt header.

### 294.6 Assets
- `BrandMark.imageset` vector PDF + 1x/2x/3x PNG fallback.
- SF Symbols customization for brand glyph where it fits.

---

## 295. Onscreen keyboard autolayout

### 295.1 Safe area
- `.ignoresSafeArea(.keyboard)` carefully; default scrolls.

### 295.2 Accessory toolbar
- Numeric fields: `$`, `%`, next, prev, done.
- Done closes keyboard; next moves focus.

### 295.3 Inputs with suggestions
- SMS / email show QuickType; custom suggestions (templates) inserted via replacement assistant.

### 295.4 External keyboard preference
- When hardware keyboard present, onscreen keyboard hidden automatically.

### 295.5 Split keyboard
- iPad split keyboard respected; our inline accessory bar follows keyboard.

### 295.6 Emoji
- Keyboard switcher stays native.
- No custom emoji picker.

---

## 296. iPadOS Magnifier gesture

### 296.1 Three-finger tap-to-zoom
- iOS system feature; our views respect so text zooms cleanly.
- No overlap with our own 3-finger gestures (none defined).

### 296.2 Zoom window
- Non-pixelated since we use vector assets + Dynamic Type.

### 296.3 Settings surface
- Point users to iOS Settings → Accessibility → Zoom.

---

## 297. Apple Watch complications — MERGED INTO §154

Content moved to §154 (watchOS companion). Number preserved so downstream references stay valid.

---

## 298. App Review checklist

### 298.1 Apple Guidelines
- 4.0 — Design: use native patterns, no web-wrapper feel.
- 5.1 — Data: privacy manifest accurate.
- 3.1.1 — IAP: subscription (if any) via StoreKit.
- 5.6.1 — Login: offer alternative to account; if app requires account, justify in review notes.
- 2.1 — Complete testability: provide demo login (§96.5).

### 298.2 Our special items
- BlockChyp SDK usage disclosed; PCI certification referenced.
- Biometric usage rationalized.
- Camera + local network + Bluetooth + NFC reasons in Info.plist.

### 298.3 Rejection likelihood
- Medium: tenant server concept may confuse reviewer — clearly document in review notes.
- Provide test tenant credentials.

### 298.4 Expedited review
- Don't abuse; save for genuine launch-date commitments.

---

## 299. Crisis playbook

### 299.1 Data breach
- Step 1: disable compromised tokens + rotate secrets.
- Step 2: notify tenants via email + in-app banner.
- Step 3: regulatory notifications (GDPR 72h / state breach laws).
- Step 4: post-mortem + remediation rollout.

### 299.2 App Store removal
- Apple pulls app: immediate banner to users "We're working on it".
- Self-hosted tenants unaffected (they keep web).

### 299.3 Widespread crash
- Phased release pause (§97.4).
- Hotfix via expedited review.
- Revert via server-side feature flag first.

### 299.4 Server outage
- App enters offline-first mode (§104).
- Banner explains.
- Retry with exponential backoff.

### 299.5 Payment provider outage (BlockChyp down)
- Fall back to "Manual card entry" mode (stored cards only).
- Banner to cashier + manager.

### 299.6 Incident comms
- Server-pushed banner system for critical messages.
- Tenant admin can override with own message.

### 299.7 Post-incident
- User-facing status page: `https://status.bizarrecrm.com`.
- Deep link from error banners.

---

## 300. Docs & developer handbook

### 300.1 In-repo docs
- `docs/howtoIOS.md` — full plan.
- `docs/howtoIOS-quickref.md` — cheat sheet.
- `ios/ActionPlan.md` — this file.
- `ios/TODO.md` — short-term follow-ups.
- `ios/CLAUDE.md` — session memory.
- `ios/README.md` — getting started (needs creation).

### 300.2 Code docs
- Every public type DocC comment.
- Xcode DocC generator part of CI.

### 300.3 Onboarding script
- `ios/scripts/onboard.sh` — checks Xcode, brew, xcodegen, fastlane, clones match, fetches fonts, generates project, opens.

### 300.4 Architecture decision records
- `docs/adr/` — markdown ADRs for major choices (GRDB vs SwiftData, BlockChyp, Liquid Glass).

### 300.5 Style guide
- `docs/style-guide.md` — SwiftLint rules + naming conventions.

### 300.6 Runbooks
- `docs/runbooks/` — ops incident playbooks (crash spike, push fail, auth fail).

### 300.7 Contribution guide
- `CONTRIBUTING.md` — branch strategy, PR template, review SLAs.

### 300.8 Living spec
- This document updated incrementally — any architectural change lands with doc update in same PR.

### 300.9 Handbook rotation
- Quarterly review: prune dead sections, update status checkboxes, refresh examples.

### 300.10 External developer enablement
- Non-applicable — closed internal codebase. Tenant-facing API docs separate.

---

## 301. Ticket SLA visualizer

### 301.1 Inline chip
- Ticket list row: small ring showing % of SLA consumed.
- Colors: green < 60%, amber 60-90%, red > 90%, black post-breach.

### 301.2 Detail header
- Large progress bar with marker for each phase (diagnose / awaiting parts / repair / QC).
- Hover / long-press reveals phase timestamps + remaining.

### 301.3 Timeline overlay
- Status history (§85.6) overlays SLA curve — shows where phases consumed budget.

### 301.4 Manager view
- Aggregated: all-open tickets on single SLA heatmap (tickets × time to SLA).
- Red-zone tickets sortable to top.

### 301.5 Projection
- Based on current pace: predicts breach time.
- "At current rate, will breach at 14:32."

### 301.6 Action
- One-tap "Notify customer of delay" template (§125) pre-filled.
- Prevents silent breach.

### 301.7 Reduce Motion
- Gauge animates only if Reduce Motion off.
- Else static value.

---

## 302. Drill-through reports

### 302.1 Breadcrumb
- Tap chart segment → filtered records list.
- Breadcrumb trail: Total revenue → October → Services → iPhone repair.
- Each crumb tappable to step back.

### 302.2 Context panel
- Left: filters narrowed by drill.
- Right: records list.

### 302.3 Export at any level
- Share current filtered view as PDF / CSV.

### 302.4 Save as widget
- "Save this drill as dashboard tile" — saved with query.

### 302.5 Cross-report
- From one report drill jumps into related report with same filters applied.

### 302.6 Performance
- Server query adapted with index hints; p95 < 2s.

---

## 303. Dashboard redesign gates

### 303.1 Tenant pick
- Dashboard is entry surface — any redesign risk breaks muscle memory.
- Pilot new design behind feature flag (§101).

### 303.2 Opt-in
- Owner opts in first; sees new design 2 weeks before staff.
- Feedback form surfaces inline.

### 303.3 Rollout
- 10% → 50% → 100% over 4 weeks.
- Each phase gated on crash-free + feedback score.

### 303.4 Rollback lever
- Flag kill-switch instantly reverts.

### 303.5 A/B metrics
- Task-completion time, tap counts, time-on-dashboard.
- Measured on-device, reported to tenant server aggregated.

### 303.6 Documentation
- Before/after wireframes, rationale, success criteria.

---

## 304. Theme gallery

### 304.1 Built-in themes
- **Midnight** (default dark).
- **Daylight** (default light).
- **Ink** (high-contrast dark).
- **Paper** (high-contrast light).
- **Noir** (OLED pure black).
- **Studio** (neutral gray, color-balanced for print work).

### 304.2 Tenant custom
- Tenant accent + logo + neutral palette auto-generate custom theme.
- No free-form color picking (avoid unreadable combos).

### 304.3 Per-user override
- Each user picks tenant theme or personal preference.
- Settings → Appearance → Theme.

### 304.4 Auto-switch
- System follow (default).
- Time-based (day theme / night theme schedule).
- Location-based (shop hours).

### 304.5 Preview
- Live full-app preview while selecting.
- Revert gesture (shake) within 10s.

### 304.6 Glass interplay
- Glass absorbs theme accent subtly; keeps material readable.

---

## 305. Tenant branding upload

### 305.1 Assets
- Logo: SVG preferred, PNG fallback, 1024×1024 min.
- Accent color (hex).
- Brand font (optional, otherwise defaults).
- Shop address, phone, email, tagline.

### 305.2 Upload UI
- Settings → Organization → Branding.
- Drag-drop on iPad.
- Crop tool for logo.

### 305.3 Validation
- Image: min dims, PNG/JPG/SVG.
- Color: must meet contrast against dark + light surfaces.
- If fails, show suggested alternate.

### 305.4 Preview
- Receipt / invoice / email / login screen mockups update live.

### 305.5 Distribution
- Assets cached per tenant; refreshed on branding change via silent push.

### 305.6 Sovereignty
- Assets stored on tenant server.
- Never uploaded to third-party CDN unless tenant owns the CDN.

### 305.7 White-label constraints
- Cannot remove "Powered by Bizarre" (Terms of Service).
- Cannot replace main app icon (Apple constraint for single-binary app).

---

## 306. Loading skeletons (deep)

### 306.1 Shape-matching
- Skeletons mirror actual cell layout: avatar circle + two text bars + chip row.
- Heights match final content to avoid jump.

### 306.2 Shimmer
- Diagonal gradient sweep L→R every 1.5s.
- Reduce Motion: static gray (no sweep).

### 306.3 When shown
- First load only.
- Background refresh uses existing cached content + subtle indicator on top.

### 306.4 Error transition
- Skeleton → error state with same layout footprint.

### 306.5 Count
- Show 3-6 skeleton rows typically.
- List-specific counts tuned to viewport.

### 306.6 Tokens
- `Surface.skeletonBase`, `Surface.skeletonHighlight`.
- Dark / light variants.

### 306.7 Reusable component
- `SkeletonRow(.ticket)`, `SkeletonRow(.customer)` etc. — centralized.

---

## 307. Animation timing scale

### 307.1 Scale
- `instant` 0ms — state flip, no animation.
- `quick` 150ms — selection, hover.
- `snappy` 220ms — chip pop, toast show.
- `smooth` 350ms — navigation push, sheet present.
- `gentle` 500ms — celebratory success.
- `slow` 800ms — decorative, onboarding reveal.

### 307.2 Curves
- `standard` — `.easeInOut`.
- `bouncy` — spring(0.55, 0.7).
- `crisp` — spring(0.4, 1.0).
- `gentle` — spring(0.8, 0.5).

### 307.3 Reduce Motion
- All > `snappy` downgrade to instant / opacity-only.

### 307.4 Discipline
- No free-form duration literals in views; use tokens.
- SwiftLint rule bans `withAnimation(.easeInOut(duration:` inline numbers.

### 307.5 120fps
- Tuned for ProMotion; 60fps still feels good.

### 307.6 Choreography
- Staggered cascade on list appear: each row +40ms delay up to 200ms cap.
- Respects Reduce Motion.

---

## 308. Keyboard-only operation test

### 308.1 Test matrix
- Every screen reachable without touch.
- Every interactive element reachable via Tab / arrow keys.
- Every primary action triggerable by Enter / ⌘+key.

### 308.2 Automation
- XCUITest pilot with only keyboard events.
- Fails if any critical flow requires touch.

### 308.3 Flows covered
- Login → dashboard → create ticket → add customer → add device → save.
- POS: open register → add item → discount → payment → receipt.
- SMS: reply via keyboard only.

### 308.4 Focus ring
- Visible focus indicator on whatever's focused (§100.3).
- Never lost; never invisible.

### 308.5 Switch Control parity
- Same machinery used by Switch Control users; ensure both test paths green.

### 308.6 Drop-outs
- Document any gap that can't be keyboard-driven (e.g., signature canvas requires touch/pencil — acceptable, document).

---

## 309. Pairing printers with peripherals

### 309.1 Printer-cash-drawer
- Bind drawer to printer's RJ11 port (§280).
- Test button opens drawer.

### 309.2 Printer-scanner chain
- Some wedge scanners route output through printer USB.
- Rarely needed but supported.

### 309.3 Printer-scale
- No native chain; both connect to iPad directly.

### 309.4 Binding profiles
- Tenant saves "Station 1": Printer A + Drawer + Terminal X + Scale.
- Multi-station support per location.

### 309.5 Station assignment
- On app launch, staff picks station (or auto-detect via Wi-Fi/Bluetooth proximity).
- Settings determined by station profile.

### 309.6 Fallback
- If a peripheral in profile fails, app degrades gracefully (PDF receipt, manual drawer open).

### 309.7 Logs
- Peripheral health per station dashboard in Settings → Hardware.

---

## 310. POS offline queue with idempotency

### 310.1 Sale record
- Each offline sale = local UUID + timestamp + lines + tenders + idempotency key.

### 310.2 Receipt
- Print with "OFFLINE" watermark until synced.
- Once synced, reprint available without watermark.

### 310.3 Card tenders
- BlockChyp offline capture (where supported): captures card, holds auth, settles on reconnect.
- Risk of declined auth at settle → manager alert.
- Limit: configurable max offline card amount ($100 default).

### 310.4 Cash tenders
- Fully offline OK; no auth needed.

### 310.5 Gift-card redemption
- Requires online; show error "Card balance lookup needs internet".
- Fallback: accept as IOU with manager approval.

### 310.6 Sync
- On reconnect, queue flushes FIFO.
- Idempotency key prevents duplicate ledger entries.
- Successful sync clears watermark; failed items to dead-letter (§135).

### 310.7 Audit
- Offline duration + sync time recorded per sale.
- Manager report: "3 sales made during 20min outage — all reconciled."

### 310.8 UI
- Banner during outage: "Offline mode — N sales queued".
- Dashboard tile tracks queue depth.

### 310.9 Security
- Offline sales fully encrypted at rest in SQLCipher.
- Card data tokenized before store; raw PAN never persisted.

---

## 311. Master design-token table

One source for every hex / size / radius / shadow. Replace scattered numbers. All tokens live in `DesignSystem/Tokens.swift`.

### 311.1 Spacing (pt)
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

### 311.2 Radius (pt)
| Token | Value | Usage |
|---|---|---|
| `radius.xs` | 4 | Small chip |
| `radius.sm` | 8 | Button |
| `radius.md` | 12 | Input field |
| `radius.lg` | 16 | Card |
| `radius.xl` | 24 | Sheet |
| `radius.pill` | 999 | Pill |

### 311.3 Shadow
| Token | y | blur | opacity (dark / light) |
|---|---|---|---|
| `shadow.none` | 0 | 0 | 0 / 0 |
| `shadow.xs` | 1 | 2 | 0.25 / 0.04 |
| `shadow.sm` | 2 | 4 | 0.35 / 0.06 |
| `shadow.md` | 4 | 12 | 0.45 / 0.10 |
| `shadow.lg` | 8 | 24 | 0.55 / 0.14 |

### 311.4 Color (dark theme)
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

### 311.5 Color (light theme)
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

### 311.6 Motion
See §307 for timing tokens.

### 311.7 Enforcement
- SwiftLint custom rule bans inline `Color(red:)` / inline CGFloat literals for spacing.
- Exceptions annotated with `// design-exception: ...`.

### 311.8 Typography scale (from §160)
Fonts: Inter (body/UI), Barlow Condensed (dashboard numbers), JetBrains Mono (IDs/codes/barcodes).

| Style | Size | Font | Weight |
|---|---|---|---|
| largeTitle | 34 | Barlow | semibold |
| title1 | 28 | Inter | semibold |
| title2 | 22 | Inter | semibold |
| title3 | 20 | Inter | medium |
| headline | 17 | Inter | semibold |
| body | 17 | Inter | regular |
| callout | 16 | Inter | regular |
| subheadline | 15 | Inter | regular |
| footnote | 13 | Inter | regular |
| caption1 | 12 | Inter | regular |
| caption2 | 11 | Inter | regular |
| mono | 14 | JetBrains Mono | regular |

- Dynamic Type: all scale. Fixed-size exceptions: POS keypad digits, OCR overlays.
- Tracking: condensed titles −0.5; line-height body 1.4×, caption 1.3×.
- `.monospacedDigit` on counters / totals.
- Weights limited to regular / medium / semibold / bold (bundle size).
- Fallback: missing weight → SF Pro matching size; CI fails release on missing `UIAppFonts` entry.

### 311.9 Semantic colors (from §159)
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

## 312. API endpoint catalog (abridged, full lives in `docs/api.md`)

| Method | Path | Request | Response | Used by § |
|---|---|---|---|---|
| POST | `/auth/login` | `{email, password}` | `{token, user, tenant}` | §2 |
| POST | `/auth/refresh` | `{refresh_token}` | `{token}` | §76.4 |
| POST | `/auth/logout` | `—` | `204` | §2.6 |
| POST | `/auth/2fa/verify` | `{code}` | `{token}` | §238 |
| GET | `/reports/dashboard` | `—` | `{kpis: [...]}` | §3 |
| GET | `/reports/needs-attention` | `—` | `{items: [...]}` | §3 |
| GET | `/tickets` | `?status,assignee,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §4 |
| GET | `/tickets/:id` | `—` | `Ticket` | §4 |
| POST | `/tickets` | `Ticket` | `Ticket` | §4 |
| PATCH | `/tickets/:id` | `Partial<Ticket>` | `Ticket` | §4 |
| POST | `/tickets/:id/signatures` | `{base64, name}` | `Signature` | §85.5 |
| POST | `/tickets/:id/pre-conditions` | `{...}` | `Ticket` | §85.3 |
| GET | `/customers` | `?query,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §5 |
| POST | `/customers` | `Customer` | `Customer` | §5 |
| POST | `/customers/merge` | `{keep,merge}` | `Customer` | §253 |
| GET | `/inventory` | `?filter,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §6 |
| POST | `/inventory` | `Item` | `Item` | §6 |
| POST | `/inventory/adjust` | `{sku,delta,reason}` | `Movement` | §6 |
| POST | `/inventory/receive` | `{po_id, lines}` | `Receipt` | §113 |
| POST | `/inventory/reconcile` | `{counts}` | `Report` | §89, §227 |
| GET | `/invoices` | `?status,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §7 |
| POST | `/invoices/:id/payments` | `{method, amount}` | `Payment` | §7 |
| POST | `/refunds` | `{invoice_id, lines, reason}` | `Refund` | §132 |
| GET | `/sms/threads` | `?cursor,limit` | `{threads, next_cursor?, stream_end_at?}` | §12 |
| POST | `/sms/send` | `{to, body}` | `Message` | §12 |
| GET | `/appointments` | `?from,to,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §10 |
| POST | `/appointments` | `Appointment` | `Appointment` | §124 |
| GET | `/estimates` | `?cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §8 |
| POST | `/estimates` | `Estimate` | `Estimate` | §8 |
| POST | `/estimates/:id/convert` | `—` | `Ticket` | §8 |
| GET | `/expenses` | `?from,to,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §11 |
| POST | `/expenses` | `Expense` | `Expense` | §11 |
| GET | `/employees` | `?cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §14 |
| POST | `/employees/:id/clock-in` | `{location?}` | `Shift` | §48 |
| POST | `/employees/:id/clock-out` | `—` | `Shift` | §48 |
| GET | `/reports/revenue` | `?from,to,group` | `Chart` | §15 |
| GET | `/reports/inventory` | `?from,to` | `Chart` | §15 |
| GET | `/reports/tax-liability` | `?from,to` | `Report` | §116.6 |
| POST | `/pos/sales` | `Sale` | `Sale` | §16 |
| POST | `/pos/cash-sessions` | `{open_amount}` | `Session` | §39 |
| POST | `/pos/cash-sessions/:id/close` | `{close_amount, notes}` | `Session` | §39 |
| POST | `/payment-links` | `{amount, customer, memo}` | `Link` | §41 |
| GET | `/gift-cards/:code` | `—` | `Card` | §40 |
| POST | `/gift-cards/redeem` | `{code, amount}` | `Card` | §40 |
| POST | `/store-credit/:customerId` | `{amount, reason}` | `Credit` | §40 |
| POST | `/device-tokens` | `{apns_token, model}` | `204` | §21 |
| POST | `/telemetry/events` | `{events[]}` | `204` | §32 |
| POST | `/telemetry/crashes` | `Crash` | `204` | §95 |
| GET | `/sync/delta` | `?since=<updated_at>&cursor=<opaque>&limit` | `{changes[], next_cursor?, stream_end_at?}` | §20.5 |
| POST | `/sync/conflicts/resolve` | `{...}` | `Resolved` | §20.3 |
| GET | `/audit-logs` | `?from,to,actor,cursor,limit` | `{data, next_cursor?, stream_end_at?}` | §52 |
| GET | `/feature-flags` | `—` | `{flags}` | §101 |
| POST | `/imports/start` | `{provider, file}` | `Job` | §50 |
| GET | `/imports/:id/status` | `—` | `Job` | §50 |
| POST | `/exports/start` | `{scope}` | `Job` | §51 |
| GET | `/exports/:id/download` | `—` | `File` | §51 |
| GET | `/locations` | `—` | `{data}` | §63 |
| POST | `/locations` | `Location` | `Location` | §63 |
| GET | `/memberships/:id/wallet-pass` | `—` | `.pkpass` | §38 |
| GET | `/public/tracking/:shortId` | `—` | `Tracking` | §55 |
| GET | `/public/book/:locationId` | `—` | `Availability` | §58 |
| POST | `/public/pay/:linkId` | `{token}` | `Payment` | §41 |
| POST | `/comms/email` | `{to, template, vars}` | `Send` | §209 |
| POST | `/comms/sms` | `{to, template, vars}` | `Send` | §125 |

All endpoints return envelope `{ success, data, message }`. All 4xx map to `AppError.server` with `message`.

---

## 313. Phase Definition of Done (sharper, supersedes §79)

### 313.1 Phase 0 — Skeleton
DoD:
- xcodegen generates clean project.
- `write-info-plist.sh` + `fetch-fonts.sh` produce Info.plist + fonts.
- App launches on iPhone + iPad + Mac (Designed for iPad).
- Login screen shippable (server URL + email + password + 2FA prompt).
- API envelope unwrapping + base URL swap works.
- Token storage in Keychain.
- Session revocation broadcasts to RootView.

### 313.2 Phase 1 — Read-only parity
DoD:
- All lists (§3-§15) implemented with pagination §68.
- Detail views read-complete.
- Global search (§18).
- Offline cache GRDB read-through.
- Snapshot tests pass.
- VoiceOver traversal smoke passes.
- Phase-1 TestFlight open to internal team.

### 313.3 Phase 2 — Writes + POS first pass
DoD:
- Create / edit / archive flows for tickets / customers / inventory / invoices.
- POS cash tender + BlockChyp card tender.
- Sync queue for offline writes.
- Bug-report form.
- External beta cohort opened.

### 313.4 Phase 3 — Hardware + platform polish
DoD:
- Barcode scan, photo attach, signature capture, thermal printer, cash drawer.
- APNs register, push categories, tap-to-open deep links.
- Widgets + App Intents + Shortcuts.
- Stage Manager + Pencil Pro + Magic Keyboard shortcuts.

### 313.5 Phase 4 — Reports, marketing, loyalty
DoD:
- Charts (§14) with drill-through (§302).
- Marketing campaigns (§127).
- Loyalty engine (§117).
- Memberships (§38).
- Referrals (§118).
- Full accessibility audit clean.

### 313.6 Phase 5 — Scale & reliability
DoD:
- Multi-location, multi-tenant switching.
- SLA visualizer, dead-letter queue, telemetry + crash pipeline (tenant-bound).
- Audit log viewer + chain integrity.
- Public-release App Store submission.

### 313.7 Phase 6 — Regulatory + advanced payment
DoD:
- Tax engine advanced, multi-currency, fiscal periods, rounding rules.
- Tap-to-Pay on iPhone evaluation (decision to ship or defer).
- Apple Wallet passes for memberships + gift cards.
- GDPR / CCPA / PCI evidence package.

### 313.8 Phase 7 — Optional stretch
DoD:
- CarPlay (fleet entitlement approved).
- Watch complications (re-eval gate passed).
- visionOS port (evaluation only).
- AI-assist via on-device WritingTools / GenModel per §76.

### 313.9 Cross-phase gates
- Crash-free sessions ≥ 99.5% before advancing.
- No P0 bugs older than 14d.
- Localization coverage per target locale.
- Documentation updated in same PR as feature.

### 313.10 Per-tenant rollout (from §79)
- Opt-in beta: 5 tenants first, weekly check-ins.
- General availability once crash-free > 99.5% + Android parity on top 80% of flows.

### 313.11 Kill-switch (from §79)
- Feature flags ship every feature; toggle server-side per tenant.
- Forced-update gate: server rejects client versions with known data-loss bugs until upgrade.

### 313.12 Migration path (from §79)
- Android → iOS: user data portable; just log in.
- Web-only → iOS: full sync on first login.
- No data migration needed — server is single source.

---

## 314. Wireframe ASCII sketches per screen

Compact text wireframes — informs Figma without being Figma.

### 314.1 Login (iPhone)
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

### 314.2 Dashboard (iPad landscape)
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

### 314.3 Ticket detail (iPhone)
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

### 314.4 POS (iPad landscape)
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

### 314.5 SMS thread (iPhone)
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

## 315. Copy deck

Central strings table — one source per language.

### 315.1 Format
- `.strings` files per locale under `App/Resources/Locales/<lang>.lproj/`.
- `docs/copy-deck.md` mirrors keys + English source for non-engineers.

### 315.2 Key naming
- `ticket.list.empty.title` / `.body` / `.cta`.
- Namespaces: `app.`, `nav.`, `ticket.`, `customer.`, `pos.`, `sms.`, `settings.`, `error.`, `a11y.`.

### 315.3 Variables
- `tickets.list.count` → "%d tickets" with `%#@tickets@`/plural entries.
- Phone / money / date formatted via `Locale`, not string literal.

### 315.4 Categories
- **Labels** — button / nav / chip.
- **Descriptions** — help text, placeholders.
- **Errors** — match §147 taxonomy.
- **A11y** — VoiceOver labels, hints.
- **Legal** — waivers, TOS, privacy.

### 315.5 Review
- Legal strings reviewed by counsel; immutable post-publish (re-sign required if changed).

### 315.6 Glossary
- Preferred terms: "customer" not "client", "ticket" not "job", "employee" not "staff".
- Published in `docs/glossary.md`.

### 315.7 Export / import
- CSV import from / export to translation vendor tools (Crowdin / Lokalise).
- Never call vendor APIs from iOS; all translation goes through tenant server.

---

## 316. SF Symbol audit

### 316.1 Used symbols catalog
- Every `Image(systemName:)` logged into `docs/symbols.md`.
- Fields: symbol name, where used, alternative for pre-iOS 17 devices.

### 316.2 Variants
- Prefer `.fill` on active / selected states.
- Prefer outline on inactive.
- Use `.monochrome` default; `.multicolor` for status indicators (warning / error).
- `.hierarchical` for brand surfaces where depth helps.

### 316.3 Custom symbols
- Custom SF Symbols for brand glyphs (wrench-spark) stored in `Assets.xcassets/Symbols/`.
- Naming: `brand.wrench.spark`.

### 316.4 Accessibility
- Each symbol needs `accessibilityLabel`.
- Decorative → `.accessibilityHidden(true)`.

### 316.5 Consistency
- One symbol per concept across app.
- Swap gesture: if a concept uses two symbols, pick one in audit + refactor.

### 316.6 CI check
- Lint: flag bare `Image(systemName:)` missing label.

---

## 317. A/B test harness

### 317.1 Purpose
- Measure dashboard redesign (§303), onboarding flows, campaign templates.

### 317.2 Assignment
- Deterministic bucket by user ID hash.
- Tenant-level, user-level, or device-level per experiment.
- Stored in feature-flag system (§101).

### 317.3 Exposure logging
- Event: `experiment.exposure { id, variant }`.
- Sent once per session per experiment to tenant server.

### 317.4 Analysis
- Per-tenant analysis on server; no cross-tenant pooling.
- Metrics per variant: task completion, time, error rate.

### 317.5 Auto-stop
- Tenant admin can stop experiment if one variant clearly wins or causes issues.

### 317.6 Ethics
- Never experiment on safety / pricing / billing.
- Payment flows never A/B tested.
- Destructive actions same across variants.

### 317.7 Sovereignty
- Assignments + results tenant-local.
- No external Optimizely / LaunchDarkly — all in-house.

---

## 318. Client rate-limiter

### 318.1 Purpose
- Protect server from accidental client storm (e.g., scroll triggering too many fetches).
- Improve user experience on flaky networks.

### 318.2 Impl
- Token-bucket per endpoint category: read vs write.
- Read: 60 tokens/min; write: 20 tokens/min.
- Exceed → queue request with backoff.

### 318.3 Server hint respect
- Honor `Retry-After` and `X-RateLimit-Remaining` headers.
- Pause client if server indicates near limit.

### 318.4 UI surface
- Silent unless sustained; show "Slow down" banner if queue > 10.

### 318.5 Debug
- Debug drawer shows current bucket state per endpoint.

### 318.6 Exempt
- Auth + offline-queue flush exempt from client limit (handled server-side).

---

## 319. Draft recovery UI

### 319.1 Auto-save drafts
- Ticket create, customer create, SMS compose — autosave every 2s to SQLCipher.
- Never lost on crash / backgrounded.

### 319.2 Recovery prompt
- On next launch or screen open: "You have an unfinished <type> — Resume / Discard".
- Sheet with preview of content.

### 319.3 Age indicator
- "Saved 3h ago" timestamp.

### 319.4 Multi-draft
- Per-type single draft (not multi).
- Discard explicit before new.

### 319.5 Sensitive
- Drafts encrypted at rest.
- PIN / password fields never drafted.

### 319.6 Cross-device
- Drafts stay on device (avoid cross-device confusion).

### 319.7 Cleanup
- Auto-delete drafts > 30 days old.

---

## 320. Keyboard shortcut overlay

### 320.1 Invocation
- ⌘? on hardware keyboard (iOS 17+ `UIKeyCommand.wantsPriorityOverSystemBehavior`).
- Menu item: Help → Keyboard Shortcuts.

### 320.2 Layout
- Full-screen glass panel.
- Grouped: Navigation / Tickets / POS / Customer / Admin.
- Searchable.

### 320.3 Content source
- Auto-built from `UICommand` registrations in each scene.
- Never hand-maintained.

### 320.4 Customization
- Power users can rebind some shortcuts via Settings → Keyboard.
- Core shortcuts (⌘N / ⌘F / ⌘S) not rebindable.

### 320.5 iPad-only
- Hidden on iPhone unless hardware keyboard attached.

### 320.6 Accessibility
- Navigable via arrows.
- VoiceOver reads each binding.

---

## 321. Apple Wallet pass designs

### 321.1 Pass types
- **Membership** — storeCard style.
- **Gift card** — storeCard style.
- **Punch card** — coupon style.
- **Appointment** — eventTicket style.
- **Loyalty tier** — generic style linked to membership.

### 321.2 Layout per type
Membership storeCard front:
```
┌──────────────────────────┐
│ [logo]  Acme Repair       │
│                           │
│ Jane Doe                  │
│ Gold tier                 │
│                           │
│ 1,240 points              │
│                           │
│ [QR / barcode]            │
└──────────────────────────┘
```
Back: tenant address, phone, website, terms, points history link.

### 321.3 Colors
- Background = tenant accent (validated contrast).
- Foreground = auto-contrast text.

### 321.4 Updates
- APNs-based PassKit push on change (points / tier / status).
- Relevance dates: appointment passes show on Lock Screen near time.

### 321.5 Localization
- Strings per locale.

### 321.6 Web-side add
- Add-to-Wallet button on public page (§208.4).

### 321.7 Sovereignty
- Pass signing certificate stored on tenant server.
- Apple Pass web service URL points to tenant server (never our infra).

---

## 322. PDF templates

### 322.1 Per document
- Receipt (thermal 80mm, A4 letter).
- Invoice (letter).
- Quote (letter).
- Work order (letter).
- Waiver (letter).
- Labor certificate (letter).
- Refund receipt (thermal / letter).
- Z-report / end-of-day (letter).
- Tax summary (letter).

### 322.2 Engine
- `UIGraphicsPDFRenderer` with SwiftUI `ImageRenderer(content:)` for modern iOS.
- Fallback Core Graphics draw for thermal printers.

### 322.3 Structure
- Header: tenant branding block.
- Body: line items, subtotals.
- Footer: terms, signature line, QR for public tracking (§203).

### 322.4 Accessibility
- Tagged PDF (text searchable / copyable).
- Screen-reader friendly when viewed in app.

### 322.5 Archival
- Generated PDFs stored on tenant server (primary) + local cache (offline).
- Re-generation deterministic so old PDFs can be recreated.

### 322.6 Preview
- Live preview in template editor.
- Real tenant + sample data renders.

### 322.7 Pagination
- Long invoices span pages; page numbers, header reprint each page.

---

## 323. Push copy deck

### 323.1 Per event
| Event | Title | Body | Action buttons |
|---|---|---|---|
| SMS_INBOUND | `{customer}` | Message body (truncated 120 chars) | Reply, Mark Read, Call |
| TICKET_ASSIGNED | Assigned: `#{id}` | `{device}` — `{issue}` | Open, Accept, Snooze |
| TICKET_STATUS | `#{id}` now `{status}` | `{customer}` — `{device}` | Open |
| PAYMENT_RECEIVED | `{amount}` received | from `{customer}` for `#{invoice}` | Open, Send Receipt |
| APPT_REMINDER | Upcoming: `{customer}` | `{time}` at `{location}` | Open, Navigate |
| LOW_STOCK | Low stock: `{sku}` | `{qty}` remaining | Open, Create PO |
| TEAM_MENTION | `{actor}` mentioned you | `{snippet}` | Reply, Open |
| ESTIMATE_APPROVED | Approved: `{estimate}` | by `{customer}` | Open, Convert |
| BACKUP_FAILED | Backup failed | Check diagnostics | Open |
| DAILY_SUMMARY | Today: `{revenue}` | `{count}` sales | Open |

### 323.2 Tone
- Short, actionable, no emoji in title.
- Body includes identifier so push list stays scannable.

### 323.3 Localization
- Each copy keyed; fallback to English if locale missing.

### 323.4 Accessibility
- VoiceOver reads title + body + action hints.

### 323.5 Interruption
- Per §105.4 categories mapped to interruption levels.

### 323.6 Bundling
- Repeated same-type pushes within 60s merged with "+N more".

---

## 324. Shortcuts app gallery entries

### 324.1 Pre-built shortcuts visible in Shortcuts Gallery
- "Create ticket for customer" — App Intent chain with customer picker.
- "Log clock-in" — one-tap.
- "Today's revenue" — reads aloud.
- "Start sale for customer" — opens POS with customer pre-loaded.
- "Scan barcode to inventory" — opens scanner directly.
- "Send payment link" — prompts amount, copies link.
- "Look up ticket by IMEI" — prompts IMEI, opens matching ticket.

### 324.2 App Intents contribute to gallery
- `@ShortcutsProvider` registers gallery entries.
- Each entry has image + description + parameter definitions.

### 324.3 Automation
- Tenants can wire automations (e.g., Arrive at work → Clock in).

### 324.4 Widget-to-shortcut
- Widgets pre-configure parameters for one-tap intent execution.

### 324.5 Voice
- Siri learns to invoke by donated phrases.

### 324.6 Sovereignty
- No external service invoked from shortcuts unless tenant adds it.

---

## 325. Spotlight indexing scope

### 325.1 Indexed items
- Tickets (id, customer, device, status).
- Customers (name, phones, emails).
- Invoices (id, total, status).
- Inventory (SKU, name).
- Notes (body).

### 325.2 Indexing layer
- `CSSearchableIndex` fed from SQLCipher read-through.
- Refresh on insert / update.

### 325.3 Privacy
- Per-user: Spotlight items scoped to tenant + user's role access.
- Settings → Privacy → "Disable Spotlight" for users who don't want cross-app discoverability.

### 325.4 Deep link
- Each item's `contentURL` routes to our URL scheme handler (§68).

### 325.5 Public indexing
- None. We don't publish to web Spotlight.

### 325.6 Size
- Capped 1000 items per entity type to avoid index bloat.
- Recent-first.

### 325.7 Refresh
- Full rebuild on schema migration (§136).
- Incremental via GRDB hooks.

---

## 326. URL-scheme handler

### 326.1 Schemes
- Universal Links: `https://app.bizarrecrm.com/<path>` (primary).
- Custom scheme: `bizarrecrm://<path>` (fallback / in-app).

### 326.2 Route map
- `/login?server=...&email=...` — auto-fill login.
- `/tickets/new?customer=...` — create ticket draft.
- `/tickets/:id` — open detail.
- `/customers/:id` — open customer.
- `/pos` — open POS.
- `/pos/sale/:id` — resume held sale.
- `/settings/:section` — open settings section.
- `/scan` — open scanner.
- `/search?q=...` — open global search.

### 326.3 Validation
- Reject unknown paths; show error toast.
- Reject params with excessive length (DoS).
- Reject if user not logged into matching tenant.

### 326.4 State preservation
- Deep links restore scene state; don't wipe current work-in-progress.
- If active draft, ask "Open in new window or replace?" on iPad.

### 326.5 Universal link verification
- Apple validates via `apple-app-site-association`.
- File hosted on tenant server domain + `app.bizarrecrm.com`.

### 326.6 Sovereignty
- Links only ever point to `app.bizarrecrm.com` or tenant-specific self-hosted host.
- Never third-party `link.*` wrappers (Bitly etc.).

---

## 327. Localization glossary

### 327.1 Per locale
- `docs/localization/<locale>-glossary.md`.
- Preferred translation for each domain term.
- Prevents translator drift.

### 327.2 Examples (en → es)
- ticket → ticket (vs. "boleto").
- inventory → inventario.
- customer → cliente.
- invoice → factura.
- refund → reembolso.
- discount → descuento.
- membership → membresía.

### 327.3 Style per locale
- Formal vs informal tone (e.g., Spanish "usted" vs "tú").
- Per-tenant override: each tenant can choose formality.

### 327.4 Gender-inclusive
- Prefer gender-neutral phrasing where grammar allows.
- Cashier → persona cajera vs cajero/a; tenant configures.

### 327.5 Currency + date
- Use `Locale` formatter; never translate numbers manually.

### 327.6 Translation workflow
- English source in `Localizable.strings`.
- Export CSV → vendor → import translations.
- Regression: pseudo-loc (`xx-PS`) ensures strings not truncated (~30% expansion).

---

## 328. RTL layout rules

### 328.1 Languages
- Arabic, Hebrew, Farsi, Urdu.

### 328.2 Mirroring
- SwiftUI native `.environment(\.layoutDirection, .rightToLeft)`.
- All custom views use logical properties (leading / trailing) — never `.left` / `.right`.

### 328.3 Icons
- Directional icons (arrows, back chevrons) flip.
- Non-directional (clock, info) don't.

### 328.4 Numerals
- Arabic locale uses Eastern Arabic numerals unless tenant preference overrides.

### 328.5 Mixed content
- LTR substrings (English brand, English IDs) inside RTL paragraph handled via Unicode bidi markers.

### 328.6 Audit
- Pseudo-loc RTL run: every screen snapshot tested.

### 328.7 POS / receipts
- Receipts in RTL locales print mirrored correctly on thermal printers.

---

## 329. Our uptime SLA (promise to tenants)

### 329.1 SLA target
- 99.9% monthly uptime for `app.bizarrecrm.com` hosted service.
- Self-hosted tenants run their own SLA.

### 329.2 Excluded
- Third-party outages (Apple push, BlockChyp) noted on status page but not counted against us.

### 329.3 Credits
- Credit tenants 10% / 25% / 50% of monthly fee at 99.5 / 99.0 / 95.0% breach.

### 329.4 Monitoring
- Synthetic canaries every minute from 3 regions.
- Real-user RUM via tenant-bound telemetry (§32).

### 329.5 Status page
- Public `status.bizarrecrm.com`.
- Incident history + maintenance windows.

### 329.6 Maintenance windows
- Announced 72h in advance.
- Sunday 02:00-04:00 local preferred.

### 329.7 iOS surface
- In-app banner on incidents.
- Link to status page.

---

## 330. Incident runbook index

### 330.1 Runbooks stored
- `docs/runbooks/crash-spike.md`
- `docs/runbooks/push-failure.md`
- `docs/runbooks/auth-outage.md`
- `docs/runbooks/sync-dead-letter-flood.md`
- `docs/runbooks/payment-provider-down.md`
- `docs/runbooks/printer-driver-regression.md`
- `docs/runbooks/db-corruption.md`
- `docs/runbooks/license-compliance-scare.md`
- `docs/runbooks/app-store-removal.md`
- `docs/runbooks/data-breach.md`

### 330.2 Structure per runbook
- Detect (how we know).
- Classify (severity).
- Contain (stop bleed).
- Communicate (banner + email + status page).
- Remediate (fix steps).
- Verify.
- Post-mortem.

### 330.3 On-call rotation
- Weekly rotation; primary + secondary.
- Pager via tenant-owned PagerDuty or similar.

### 330.4 Practice
- Quarterly game-day — simulate one runbook.
- Results feed back into doc.

### 330.5 Sovereignty in incident tooling
- Logs aggregated to tenant-controlled stack; no Datadog / Splunk for multi-tenant shared.
- Our cloud tenants use our own aggregator; self-hosted tenants keep theirs.

---

## 331. Android ↔ iOS parity table

| Feature | Android | iOS | Gap |
|---|---|---|---|
| Login / server URL | ✅ | ✅ | — |
| 2FA | ✅ | planned | §238 |
| Passkey / WebAuthn | partial | planned | §266 |
| Dashboard | ✅ | ✅ | density modes iOS-only |
| Tickets list | ✅ | ✅ | — |
| Ticket create full | ✅ | partial | §85 |
| Ticket edit | ✅ | planned | — |
| Customers | ✅ | ✅ | — |
| Customer merge | ✅ | planned | §253 |
| Inventory | ✅ | ✅ | — |
| Receiving | ✅ | planned | §113 |
| Stocktake | ✅ | planned | §89 |
| Invoices | ✅ | ✅ | — |
| Payment accept | ✅ | partial | §16 |
| BlockChyp SDK | ✅ | planned | §16.2 |
| Cash register | ✅ | planned | §39 |
| Gift cards | ✅ | planned | §40 |
| Payment links | ✅ | planned | §41 |
| SMS | ✅ | ✅ | — |
| SMS AI reply | ❌ | planned (on-device) | §88 iOS leads |
| Notifications tab | ✅ | ✅ | — |
| Appointments | ✅ | ✅ | — |
| Scheduling engine deep | ✅ | planned | §124 |
| Leads | ✅ | ✅ | — |
| Estimates | ✅ | ✅ | — |
| Estimate convert | ✅ | planned | §9 |
| Expenses | ✅ | ✅ | — |
| Employees | ✅ | ✅ | — |
| Clock in/out | ✅ | planned | §48 |
| Commissions | ✅ | planned | §119 |
| Global search | ✅ | ✅ | — |
| Reports | ✅ | placeholder | §14 |
| BI drill | partial | planned | §243 |
| POS checkout | ✅ | placeholder | §16 |
| Barcode scan | ✅ | planned | §17.2 |
| Printer thermal | ✅ | planned | §156 |
| Label printer | ❌ | planned | §114 |
| Cash drawer | ✅ | planned | §280 |
| Weight scale | ❌ | planned | §279 |
| Customer-facing display | ❌ | planned | §187 |
| Offline mode | ✅ | planned | §20 |
| Conflict resolution | ❌ | planned | §20.6 |
| Widgets | ❌ | planned | §199 |
| App Intents / Shortcuts | ❌ | planned | §151 |
| Live Activities | n/a | planned | §24 |
| Apple Wallet passes | n/a | planned | §321 |
| Handoff / Continuity | n/a | planned | §155 |
| Stage Manager 3-col | n/a | planned | §153 |
| Pencil annotation | n/a | planned | §134 |
| CarPlay | n/a | deferred | §82 |
| SSO | ✅ | planned | §240 |
| Audit log | ✅ | planned | §241 |
| Data import wizard | ✅ | planned | §50 |
| Data export | ✅ | planned | §51 |
| Multi-location | ✅ | planned | §63 |

Legend: ✅ shipped · partial · planned · deferred · n/a.

### 331.1 Review cadence
- Monthly: Android lead + iOS lead reconcile gaps.
- Track burn-down.

### 331.2 Parity test
- Shared behavior spec per feature (Gherkin scenarios) — both platforms must pass.
- Lives in `packages/shared/spec/`.

---

## 332. Web ↔ iOS parity table

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
| Marketing campaign builder | ✅ | planned | §127 |
| Reports builder | ✅ | planned | §243 |
| Settings comprehensive | ✅ | subset | §231.2 |
| Tenant admin destructive ops | ✅ | by-design web-only | §231.4 |
| Waivers PDF | ✅ | planned | §126 |
| Quote e-sign | ✅ | planned | §133 |
| Public tracking page | ✅ | n/a (web-served) | §55 |
| Public pay link | ✅ | n/a (web-served) | §41 |
| Self-booking | ✅ | n/a (web-served) | §58 |
| Audit log | ✅ | planned | §241 |
| Data import | ✅ | planned | §50 |
| Data export | ✅ | planned | §51 |
| Integrations config | ✅ | view-only | §210.2 |
| Receipt template editor | ✅ | planned | §288 |

### 332.1 iOS's unique edges
- Apple Wallet passes.
- Apple Pay / Tap-to-Pay.
- Camera-native barcode / document scan.
- BlockChyp mobile terminal tethering.
- Dynamic Island / Live Activities.
- Siri / App Intents / Shortcuts.
- Widgets / Lock Screen.
- Handoff / Universal Clipboard.
- Pencil annotation.

### 332.2 Web's edges
- Keyboard-heavy admin workflows (though iPad with Magic Keyboard narrows gap).
- Complex report builder (iOS can match but low ROI).
- Tenant superadmin tools.

### 332.3 Decision
- iOS targets daily operational tasks + point-of-sale.
- Web keeps admin / marketing / complex reporting.
- Sync guaranteed both directions.

---

## 333. Server capability map

### 333.1 Categories
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

### 333.2 Per capability
- Endpoint(s) in §312.
- Required for iOS feature X.
- Status (ready / in progress / not yet).

### 333.3 Gap tracker
- Live spreadsheet in `docs/server-gaps.csv`.
- Each iOS feature PR checks capability status before merge.

### 333.4 Coordination
- iOS lead weekly sync with server lead.
- Shared Linear / Jira project.

---

## 334. DB schema ERD (text)

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

### 334.1 Row-level security
- Every row has `tenant_id` column.
- Server policy: queries always filtered by tenant_id from auth token.

### 334.2 Indexes
- Customer: (tenant_id, phone), (tenant_id, email), (tenant_id, name).
- Ticket: (tenant_id, status), (tenant_id, assignee), (tenant_id, updated_at desc).
- Invoice: (tenant_id, status), (tenant_id, customer_id).
- Movement: (tenant_id, sku, created_at).

### 334.3 Soft delete
- `deleted_at` nullable on most entities.
- Queries default to WHERE deleted_at IS NULL.

### 334.4 Versioning
- `version_hash` for optimistic concurrency on Ticket / Invoice / Customer.

### 334.5 Foreign keys
- Strict FK constraints server-side.
- iOS relies on server to enforce; client validates optimistically.

---

## 335. State diagrams per entity

### 335.1 Ticket
```
Intake → Diagnostic → Awaiting Approval → Awaiting Parts → In Repair → QC → Ready → Completed → Archived
  │           │              │                 │              │         │       │
  │           ▼              ▼                 ▼              ▼         ▼       ▼
  └──► Cancelled                                                        └──► Warranty Return
                                                                              (loops back to In Repair)
```
Rules from §131.

### 335.2 Invoice
```
Draft → Sent → Partial Paid → Paid → Closed
  │       │         │           │
  ▼       ▼         ▼           ▼
Void    Overdue  Overdue     Refunded
```

### 335.3 POS Sale
```
Empty cart → Building → Ready to tender → Charging → Approved → Receipt → Closed
                                              │
                                              ▼
                                           Declined → back to Ready
```

### 335.4 Employee shift
```
Off → Clocked in → On break → Clocked in → Clocked out
                     │
                     └── (loop)
```

### 335.5 Appointment
```
Booked → Confirmed → Checked in → In service → Completed
            │           │            │
            ▼           ▼            ▼
        Cancelled   No-show      Cancelled
```

### 335.6 Sync queue item
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

## 336. Architecture flowchart

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

### 336.1 Supporting modules
- Widgets target → read-only App Group DB.
- App Intents target → read + limited write.
- Extensions (share / push-action) → thin wrappers around Core.

### 336.2 Data flow
- User action → ViewModel intent → Repository → (cache read + network call) → state update → view redraw.
- Writes: optimistic UI → Repository → APIClient → on success confirm + audit log → on failure enqueue + revert UI if needed.

### 336.3 Concurrency
- Swift structured concurrency everywhere.
- Actors per Repository.
- No GCD raw calls outside low-level delegates.

---

## 337. STRIDE threat model (summary)

| Threat | Example | Mitigation |
|---|---|---|
| **S**poofing | Attacker logs in as staff | Strong auth + 2FA + passkey; device binding |
| **T**ampering | Altered API response | HTTPS + optional SPKI pin; envelope checksum |
| **R**epudiation | Staff denies action | Audit log with chain integrity §241.5 |
| **I**nformation disclosure | Token leaked | Keychain + biometric gate; never in logs |
| **D**enial of service | Flood endpoints | Server rate-limit; client limit §318 |
| **E**levation of privilege | Cashier becomes admin | Server authoritative RBAC; client double-check |

### 337.1 Specific risks
- **Stolen device** — Keychain wipes on passcode-disable; remote sign-out §271.3.
- **Shoulder surf** — PIN mask + blur on background.
- **Malicious coworker** — audit trail + role scoping + duress codes (future).
- **Server compromise** — SPKI pin optional; tenant-side IR (§299).
- **Push phishing** — Apple APNs trust chain; no deep links from external pushes.
- **MITM on hotel Wi-Fi** — ATS + optional pin; VPN recommended.
- **SIM swap** — 2FA TOTP / passkey preferred over SMS.
- **Pasteboard sniff** — Pasteboard access audit + clear on sensitive ops.
- **Screenshot leak** — blur sensitive screens + audit log §158.

### 337.2 Review cadence
- Quarterly sec-review with security-reviewer agent + human.
- Post-incident: update threat model.

---

## 338. Perf benchmark harness

### 338.1 XCTMetric
- Golden-path tests measure launch, scroll, search, payment.
- Baselines stored in repo; CI fails on > 10% regression.

### 338.2 Tools
- Instruments automation via CLI for Time Profiler / Allocations / Animation Hitches.
- Reports archived per build.

### 338.3 Benchmarks catalog
- Cold launch.
- Warm launch.
- Dashboard first paint.
- Tickets list 1000 rows scroll.
- Inventory search 500 items.
- SMS thread 500 messages scroll.
- POS add 20 items + checkout.
- Photo attach 5 photos.
- Sync 100 changes.

### 338.4 Devices
- iPhone SE 3 (floor).
- iPhone 16 Pro.
- iPad 10 (low-end).
- iPad Pro 13" M4.
- Mac Mini M4 (Designed for iPad).

### 338.5 Reporting
- Dashboard in CI showing trends.
- Slack-free (sovereignty) — summary emailed to team.

---

## 339. Synthetic demo data

### 339.1 Purpose
- App Store review (§96.5).
- Demo tenants for sales.
- Local dev sandbox.

### 339.2 Data set
- 50 customers with varying LTV.
- 500 tickets across statuses.
- 1000 inventory items.
- 200 invoices paid / partial / overdue.
- 3000 SMS messages.
- 12 appointments this week.
- 5 employees with shifts + commissions.

### 339.3 Generator
- Server CLI: `bizarre seed-demo --tenant=demo --seed=42`.
- Deterministic via seed.
- Creates believable real-world distributions.

### 339.4 Refresh
- Weekly re-seed of demo tenant.
- Reset button in demo tenant settings.

### 339.5 Privacy
- Demo data is synthetic; never derived from real customers.
- Names from Faker locale list; phones / emails from reserved testing ranges.

---

## 340. Battery benchmark per screen

### 340.1 Methodology
- MetricKit `MXSignpostMetric` plus manual runs with device power meter.
- 30-min fixed activity per screen; measure mAh draw.

### 340.2 Budgets
- Dashboard static: ~50mAh/hr.
- Tickets list scroll: ~150mAh/hr.
- POS active: ~200mAh/hr (scanner on).
- SMS compose: ~100mAh/hr.
- Camera active: ~400mAh/hr (brief use).
- Reports chart: ~80mAh/hr.

### 340.3 Anti-patterns
- Polling replaced with silent push.
- Idle animations paused after 30s inactive.
- Location only when needed (§141).

### 340.4 Regressions
- PR template includes battery impact self-check.
- CI sample on instrumented device post-merge.

### 340.5 User surface
- Settings → Diagnostics → Battery impact — shows "last 24h" breakdown by tab.

### 340.6 Sovereignty
- All battery telemetry local + tenant-server only.

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
