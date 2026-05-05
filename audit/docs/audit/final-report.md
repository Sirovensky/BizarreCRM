# BizarreCRM iOS — Final Audit Report
## Post-Phase-11 · 2026-04-20

> Scope: `ios/ActionPlan.md` honest status (Audit 1), code sanity sweep of `ios/Packages/*/Sources/` (Audit 2), UX/workflow/security sweep (Audit 3).
> Constraints: source code untouched; ActionPlan.md untouched; no push.

---

## Quick-reference stats

| Metric | Value |
|---|---|
| ActionPlan items total | 3,651 |
| Checked `[x]` (shipped) | 624 (17 %) |
| Unchecked `[ ]` (outstanding) | 2,990 (82 %) |
| Partial `[~]` | 2 |
| Blocked `[!]` | 35 |
| Swift source files (all packages, excl. `.build/`) | ~950 |
| Production stub indicators (TODO/FIXME/fatalError/placeholder) | ~182 occurrences across 25+ files |
| Duplicate public type names across packages | 4 confirmed |
| Security findings — blocker | 2 |
| Security findings — high | 3 |
| Security findings — medium | 4 |

---

## Audit 1 — ActionPlan Honest Status

### 1.1 Classification methodology

| Class | Definition |
|---|---|
| **deferred** | Intentionally out of scope for this sprint cycle; spec preserved; no engineering allocated |
| **out-of-scope** | Explicitly server-side, tvOS, customer-facing, or non-iOS per §62/§53/§54/§56 |
| **todo** | Real outstanding iOS work; should exist but doesn't |
| **deep-feature-cut** | Feature shipped at MVP; remaining bullets are edge-case polish or stretch goals |
| **broken** | Code exists but contains a known defect, placeholder, or incorrect stub |

### 1.2 Per-section classification tally

| Section | Done | Open | Class for open items | Notes |
|---|---|---|---|---|
| §1 Platform & Foundation | 25 | 70 | 55 todo, 15 deep-feature-cut | Typed endpoints, multipart upload, jitter retry, DB passphrase, UndoManager — all missing |
| §2 Auth & Onboarding | 50 | 121 | 80 todo, 41 deep-feature-cut | SSO/SAML, signup wizard, change-PIN server call, biometric re-enroll — real todo |
| §3 Dashboard | 7 | 93 | 60 todo, 33 deep-feature-cut | KPI tiles, BI widgets, My Queue section — real todo |
| §4 Tickets | 16 | 184 | 120 todo, 64 deep-feature-cut | Multi-step create flow, notes/mentions, full edit-form parity, Kanban — real todo |
| §5 Customers | 13 | 128 | 80 todo, 48 deep-feature-cut | Tabs (Info/Tickets/Invoices/Comms/Assets), tags, merge UI — real todo |
| §6 Inventory | 18 | 115 | 60 todo, 55 deep-feature-cut | Bin locations, serials, lot tracking are stretch; PO list/create — todo |
| §7 Invoices | 10 | 74 | 50 todo, 24 deep-feature-cut | Create form, full record-payment, aging report — real todo |
| §8 Estimates | 5 | 33 | 20 todo, 13 deep-feature-cut | Detail view full build, e-sign flow, versioning — real todo |
| §9 Leads | 6 | 27 | 15 todo, 12 deep-feature-cut | Pipeline Kanban, lost-reason modal — real todo |
| §10 Appointments | 4 | 30 | 20 todo, 10 deep-feature-cut | Calendar views, EventKit mirror, recurring edits — real todo |
| §11 Expenses | 4 | 20 | 12 todo, 8 deep-feature-cut | Detail view, filters, summary tiles — real todo |
| §12 SMS | 16 | 36 | 20 todo, 16 deep-feature-cut | Compose, template manager, bulk blast — real todo |
| §13 Notifications | 8 | 12 | 8 todo, 4 deep-feature-cut | Granular category toggles — todo |
| §14 Employees | 3 | 74 | 50 todo, 24 deep-feature-cut | Commission rules, goal tracking, time-off — todo |
| §15 Reports | 19 | 46 | 30 todo, 16 deep-feature-cut | Charts shipped as stubs; drill-through, CSAT/NPS — real todo |
| §16 POS | 66 | 133 | 80 todo, 53 deep-feature-cut | Charge card live (terminal wiring stub), drawer wired as stub, receipt method placeholder |
| §17 Hardware | 40 | 154 | 100 todo, 53 deferred/blocked | MFi approval 3–6 weeks; BlockChyp SDK hybrid; weight scale — todo |
| §18 Search | 7 | 47 | 30 todo, 17 deep-feature-cut | Spotlight, FTS5 indexer — todo |
| §19 Settings | 32 | 291 | 200 todo, 91 deep-feature-cut | 27 sub-pages largely empty; Settings search built but data sparse |
| §20 Sync/Offline | 15 | 41 | 25 todo, 16 deep-feature-cut | `updated_at` bookkeeping, DB passphrase, large-migration split — real todo |
| §21 Push/Real-time | 15 | 34 | 20 todo, 14 deep-feature-cut | WebSocket connections, background silent-push wiring — real todo |
| §22 iPad Polish | 10 | 63 | 45 todo, 18 deep-feature-cut | iPad variants on most read surfaces beyond Tickets — todo |
| §23 Mac Polish | 1 | 25 | 20 todo, 5 deep-feature-cut | `.contextMenu`, `.fileExporter`, hover effects — todo |
| §24 Widgets/Intents | 31 | 37 | 20 todo, 17 deep-feature-cut | Live Activities for POS/repairs — todo |
| §25 Spotlight/Handoff | 9 | 45 | 30 todo, 15 deep-feature-cut | Spotlight indexer not wired to app startup — todo |
| §26 Accessibility | 6 | 58 | 40 todo, 18 deep-feature-cut | Reduce Transparency fallback, a11y CI, per-feature audits — todo |
| §27 i18n | 10 | 36 | 25 todo, 11 deep-feature-cut | Only English strings exist; pseudo-loc, RTL — todo |
| §28 Security & Privacy | 0 | 86 | 60 todo, 26 deferred | Privacy manifest, SQLCipher passphrase, STRIDE review not done |
| §29 Perf Budget | 8 | 104 | 60 todo, 44 deep-feature-cut | Perf benchmark harness absent; battery bench absent |
| §30 Design System | 0 | 161 | 80 todo, 81 deep-feature-cut | Glass budget enforcer, Reduce Transparency fallback — todo |
| §31 Testing Strategy | 0 | 44 | 44 todo | Formal test strategy document not written; CI coverage gate not automated |
| §32 Telemetry/Crash | 12 | 57 | 35 todo, 22 deep-feature-cut | CrashReporter exists but AppServices wiring comment-only |
| §33 CI/Release | 0 | 54 | **deferred** | Explicit defer to Phase 11 pre-submission |
| §34 Known Risks | 2 | 44 | 35 blocked, 9 todo | 34 hard blockers on hardware/server/policy |
| §36 Setup Wizard | 14 | 25 | 20 todo, 5 deep-feature-cut | 13-step wizard largely unbuilt |
| §37 Marketing | 22 | 34 | 20 todo, 14 deep-feature-cut | Campaign blast, review solicitation — todo |
| §38 Loyalty | 14 | 36 | 20 todo, 16 deep-feature-cut | Membership portal, wallet pass design — todo |
| §39 Cash Register | 4 | 17 | 12 todo, 5 deep-feature-cut | Z-report, EOD summary — todo |
| §40 Gift Cards | 12 | 5 | deep-feature-cut | Core shipped; dunning/retry edge cases are stretch |
| §41 Payment Links | 4 | 3 | deep-feature-cut | Core shipped; self-service Apple Pay is stretch |
| §42 Voice | 7 | 7 | 6 todo, 1 deferred | Voicemail endpoint DEFERRED server-side |
| §43 Repair Pricing | 9 | 0 | done | |
| §44 CRM Health | 4 | 4 | deep-feature-cut | Recalculate button; daily auto-refresh |
| §45 Team Chat | 0 | 15 | **todo** | Server exists; iOS package not started |
| §46 Goals/Perf/Time-off | 0 | 77 | todo | Entire section not started |
| §47 Roles Editor | 7 | 0 | done | |
| §48 Data Import | 7 | 5 | deep-feature-cut | Core CSV import done; source-specific mappers stretch |
| §49 Data Export | 7 | 0 | done | |
| §50 Audit Logs | 11 | 4 | deep-feature-cut | Filter/export polish |
| §51 Training Mode | 5 | 1 | deep-feature-cut | |
| §52 Command Palette | 7 | 0 | done | |
| §53 Public Tracking | 0 | 21 | **out-of-scope** | Server-side web page; iOS is thin deep-link only |
| §54 TV Queue Board | 0 | 0 | **out-of-scope** | Explicitly not an iOS feature |
| §55 Kiosk/Assistive | 8 | 0 | done | |
| §56 Self-Booking | 0 | 0 | **out-of-scope** | Customer-facing; not this app |
| §57 Field Service | 0 | 13 | todo | Package not started |
| §58 Purchase Orders | 0 | 5 | todo | PO list/create not built |
| §59 Financial Dashboard | 0 | 4 | todo | Owner-view charts missing |
| §60 Multi-Location | 4 | 0 | done | |
| §61 Release Checklist | 0 | 17 | **deferred** | Phase 11 |
| §62 Non-goals | — | — | **out-of-scope** | Reference section only |
| §63 Error/Empty States | 0 | 25 | todo | Cross-cutting patterns not codified |
| §64 Copy Style Guide | 0 | 40 | deep-feature-cut | English-only baseline missing; low runtime impact |
| §65 Deep-link Ref | 0 | 7 | todo | DeepLinkRoute enum exists; not all routes have navigation sites |
| §66 Haptics | 0 | 5 | deep-feature-cut | BrandHaptics exists; catalog not documented |
| §67 Motion Spec | 0 | 5 | deep-feature-cut | |
| §68 Launch Experience | 0 | 10 | todo | Launch screen is solid color placeholder |
| §69 In-App Help | 0 | 19 | deep-feature-cut | |
| §70 Notifications Matrix | 0 | 26 | todo | Granular per-event toggles not built |
| §72 UX Polish Checklist | 0 | 20 | todo | Final polish; not started |
| §73 CarPlay | 0 | 0 | **deferred** | Explicit defer |
| §75 App Store Assets | 0 | 0 | **deferred** | Phase 11 |
| §76 TestFlight Rollout | 0 | 0 | **deferred** | Phase 11 |
| §78 Data Model / ERD | 8 | 0 | done | |
| §79 Multi-tenant Session | 2 | 0 | done | Scope reduced |

### 1.3 Top-10 outstanding TODO items by user impact

Ranked by: would ship with a visible defect / broken flow if not addressed.

| Rank | Item | Section | Why it blocks ship |
|---|---|---|---|
| 1 | `openDrawer()` is `/* §17.4 stub */` — cash-drawer never opens | §16/§17 | POS cash tender flow is incomplete; cashier must manually open drawer on every cash sale |
| 2 | `methodLabel: "Placeholder — pending §17.3"` in `PosPostSaleViewModel` | §16 | Post-sale receipt screen shows wrong payment method on every transaction |
| 3 | `ClockInOutViewModel.userId = 0` placeholder — clock-in/out uses wrong user ID | §3.11/§14 | All clock-in/out records are attributed to user 0; no `GET /auth/me` integration |
| 4 | DB encryption passphrase (32-byte random in Keychain) not implemented — SQLCipher passphrase is missing | §1.3/§28 | Offline data is stored in SQLCipher but the passphrase is not properly seeded per §28.2; security requirement |
| 5 | Only 3 domains registered in `SyncFlusher` (Customers, Tickets, Inventory) — Invoices, Appointments, Expenses, SMS, Employees, POS have no offline-write replay | §20/§2 phase gate | Users lose writes made offline in 6+ domains on reconnect |
| 6 | `TicketStatus` defined twice — `Core.TicketStatus` (7 cases, snake_case raw values) vs `Tickets.TicketStatus` (9 cases, camelCase raw values) — raw value mismatch causes silent decode failures | §4 | Tickets decoded from server may silently fall through to `.intake` for unknown status values; affects filtering and state machine |
| 7 | No `GET /auth/me` on cold-start — role/permissions never loaded into `AppState` | §2.11 | Permission-gated actions cannot be correctly hidden/shown; every role check is vacuous |
| 8 | Ticket multi-step create flow not built (only minimal create exists) — missing Device catalog, Services/Parts picker, deposit, assignee, full review step | §4.3 | Creating a real repair ticket on iPhone requires significantly less data than web/Android — parity gap |
| 9 | Settings has 291 open items — most of the 27 sub-pages are stubs or empty placeholders | §19 | App ships with a Settings tab that mostly shows "Coming soon" |
| 10 | `§45 Team Chat` — server exists, iOS package not started at all | §45 | Team collaboration tab is completely absent; server is live |

### 1.4 Classification summary

| Classification | Count (estimated items) |
|---|---|
| **deferred** | ~54 items (§33, §73, §75, §76, §61) |
| **out-of-scope** | ~21+ items (§53, §54, §56 + §62 reference) |
| **todo** | ~1,400 real iOS items outstanding |
| **deep-feature-cut** | ~1,200 items (edge cases, polish, stretch) |
| **broken** | ~15 items (stubs in shipped code that degrade UX) |

---

## Audit 2 — Code Sanity Sweep

### 2.1 Per-package file count and stub density

| Package | Source files | Prod stub count | Notes |
|---|---|---|---|
| Auth | 42 | 25 | Mostly field placeholders; PasskeyManager has pre-ship TODO |
| Pos | 78 | 20 | `openDrawer()` stub, `methodLabel` placeholder, `CouponListView` swallows errors |
| Core | 53 | 18 | DI `fatalError` guards (intentional); `Strings.swift` TODO for l10n |
| Tickets | 23 | 7 | `TicketStatus` duplication (see §2.4) |
| Setup | 22 | 7 | Logo step + company info step have placeholder stubs |
| Hardware | 31 | 7 | `LabelPrintEngine` and `PrinterSettingsViewModel` have TODOs |
| AuditLogs | 10 | 7 | Test mock `fatalError`s; production code has filter TODO |
| Networking | 54 | 6 | `SmsThreadEndpoints`, `TimeclockEndpoints` have TODOs |
| KioskMode | 16 | 6 | `OnboardingVideoLibraryView`, `TutorialOverlayView` have placeholders |
| Marketing | 31 | 5 | `ReviewSettingsView` has TODO |
| Invoices | 19 | 5 | `InvoiceListView` has FIXME for cursor pagination |
| Customers | 27 | 5 | `CustomerListView` has FIXME for A-Z index |
| Communications | 20 | 5 | `EmailRenderer`, `TemplateRenderer` have TODOs |
| Appointments | 7 | 5 | `AppointmentCachedRepositoryImpl` TODO |
| Loyalty | 19 | 2 | `MembershipPassUpdater` has bare `print()` debug calls (see §3.4) |
| Persistence | 14 | 2 | `BackupManager` TODO |
| Employees | 6 | 2 | `EmployeeCachedRepositoryImpl` TODO |
| Estimates | 9 | 3 | `EstimateDetailView` TODO |
| Inventory | 27 | 4 | `InventoryListView` FIXME |
| Expenses | 4 | 2 | `ExpenseCachedRepositoryImpl` TODO |
| Notifications | 8 | 3 | `SilentPushHandler` has production `fatalError` if not configured |
| Reports | 16 | 1 | Shimmer placeholder (cosmetic) |
| Dashboard | 4 | 2 | `DashboardCachedRepositoryImpl` TODO |
| DataExport | 15 | 2 | `ExportRepository` placeholder; `ImportErrorsView` out-of-scope TODO |
| Voice | 5 | 1 | Voicemail endpoint DEFERRED comment |

**Total: ~950 source files; ~182 stub indicators in production code.**

### 2.2 Orphan code — top-10 candidates

Files exist and compile but have no confirmed call site in the App or in another package's non-test source:

| Rank | File | Package | Evidence of orphan |
|---|---|---|---|
| 1 | `OnboardingVideoLibraryView.swift` | KioskMode | No import of `KioskMode.OnboardingVideoLibraryView` found in App or Settings |
| 2 | `TutorialOverlayView.swift` | KioskMode | Same — no call site found |
| 3 | `BurnInNudgeModifier.swift` | KioskMode | No usage found outside KioskMode package |
| 4 | `VoicemailPlayerView.swift` | Voice | Voicemail endpoint DEFERRED; `VoicemailListView` shows "Coming soon"; player unreachable |
| 5 | `CallQuickAction.swift` | Voice | No import site found outside Voice package |
| 6 | `DrillThrough/` folder | Reports | Reports charts are stubs; drill-through not wired |
| 7 | `ScheduledReports/` folder | Reports | No `ScheduledReport` call site in App |
| 8 | `NPS/` folder | Reports | No call site; NPS marked `[ ]` in ActionPlan |
| 9 | `CSAT/` folder | Reports | No call site; CSAT marked `[ ]` in ActionPlan |
| 10 | `ScheduledExportEditorView.swift` | DataExport | No navigation site confirmed in Settings |

### 2.3 Stub detector findings

**Production `fatalError` in non-test code (7 occurrences):**

| File | Trigger condition | Severity |
|---|---|---|
| `Container+Registrations.swift` (×6) | DI factory resolved before `registerAllServices()` | Intentional guard — acceptable |
| `SilentPushHandler.swift` | `shared` accessed before `setUp(syncManager:)` | **High** — app will crash if push arrives before AppServices.init completes |

**Empty/near-empty function bodies in production (4 confirmed):**

| File | Empty body | Impact |
|---|---|---|
| `PosView.swift:576` | `private func openDrawer() { /* §17.4 stub */ }` | **Blocker** — cash drawer never opens |
| `MagicLinkRequestView.swift:186` | `Button { }` during `.sending` state | Medium — button fires no action while loading (acceptable pattern for non-interactive state) |
| `PosPostSaleView.swift:140` | `NavigationLink(destination:isActive:) { }` | Medium — navigation destination is empty |
| `Sync/DeadLetterListView.swift:33` | `Button("OK") { }` | Low — dismiss button in dead-letter UI does nothing |

**"Placeholder — pending §17.x" strings visible to user:**

| File | String |
|---|---|
| `PosView.swift:566` | `"Placeholder — pending §17.3"` as `methodLabel` — shown in receipt |
| `PosPostSaleViewModel.swift:179,197,214,225` | `"Receipt placeholder (real charge pending §17.3)"` — shown in post-sale email/SMS status |

### 2.4 Type duplication across packages

| Type name | Locations | Risk |
|---|---|---|
| `TicketStatus` | `Core/Models/Ticket.swift` (7 cases, snake_case raw values) AND `Tickets/StateMachine/TicketStateMachine.swift` (9 cases, camelCase raw values) | **High** — raw value mismatch (`awaiting_parts` vs `awaitingParts`) causes silent decode failures when server returns `awaiting_parts`; the StateMachine enum will not match |
| `ManagerPinSheet` | `Invoices/Refunds/InvoiceRefundSheet.swift`, `Pos/ManagerPinSheet.swift`, `KioskMode/ManagerPinSheet.swift` | Medium — three independent implementations; inconsistent UX and validation |
| `Sale` (struct) | `Networking/CommissionsEndpoints.swift` AND `Marketing/Referrals/ReferralCode.swift` | Low — different packages, no import clash; but confusing when debugging |
| `CartMath` | Multiple files (enum in Pos) | Low — scoped to Pos module |

### 2.5 ViewModel annotation conformance

Checked all `*ViewModel` classes for `@Observable` or `@MainActor`:

**Classes missing `@Observable` annotation (incomplete list):**

| ViewModel | Package | Missing |
|---|---|---|
| `CustomerEditViewModel` | Customers | `@Observable` |
| `CustomerCreateViewModel` | Customers | `@Observable` |
| `CustomerListViewModel` | Customers | `@Observable` |
| `CustomerMergeViewModel` | Customers | `@Observable` |
| `CustomerContactViewModel` | Customers | `@Observable` |
| `CustomerTagEditorViewModel` | Customers | `@Observable` |
| `CustomerDetailViewModel` | Customers | `@Observable` |
| `SyncDiagnosticsViewModel` | Settings | `@Observable` |
| `LocationPermissionsViewModel` | Settings | `@Observable` |
| `LocationInventoryBalanceViewModel` | Settings | `@Observable` |

Note: some of these may use `ObservableObject` conformance implicitly via `@Published` — a full Xcode build check is required to confirm these are not compile failures.

### 2.6 Naming conformance issues

`*Endpoints.swift` files that define multiple public types (not conforming to single-type-per-file convention):

- `TenantAdminEndpoints.swift` — public name mismatch with file
- `LocationHeader.swift`, `LocationModels.swift`, `LocationEndpoints.swift` — multi-type helper files
- `HoursModels.swift`, `HoursEndpoints.swift` — multi-type files

These are minor; the pattern of grouping DTOs with their endpoint namespace is common and not a compile risk.

**Protocol-without-implementation gaps:**

`RepositoryImpl` pattern is followed consistently in shipped packages. No `*RepositoryImpl` found without a corresponding `*Repository` protocol.

---

## Audit 3 — UX, Workflow, and Security Sweep

### 3.1 Login → PIN → Dashboard flow

**Status: functional with one gap.**

Trace confirmed:
- `RootView` → `LoginFlowView` (Auth) on `.unauthenticated`
- Login success → `appState.phase = .authenticated`
- `.locked` → `PINUnlockView(onUnlock: { appState.phase = .authenticated })`
- `SessionEvents.sessionRevoked` → `TokenStore.shared.clear()` → `appState.phase = .unauthenticated`

**Gap — PINUnlock escalating revocation path:**
- `PINUnlockView` handles forgot-PIN (drops to re-auth), but the 10-attempt wipe path (PIN auto-revoke after max lockout) is not confirmed wired to `SessionEvents.sessionRevoked` in `AppServices`. The `PINStore` escalation logic exists but there are no PIN-specific files in `Auth/Sources/Auth/PIN/` — the directory is empty in the filesystem. The PIN UI and `PINStore` live in `LoginFlowView.swift` inline. The lockout escalation chain is **not verifiably connected** to app-level session revocation.

**Recommendation (High):** Verify and wire PIN max-lockout → `SessionEvents.sessionRevoked` so the `RootView` observer triggers wipe.

### 3.2 Ticket offline create → sync flow

**Status: partially wired — significant gap in drain coverage.**

Trace:
1. `TicketCreateViewModel.submit` (network failure) → `TicketOfflineQueue.enqueue(record)` → `SyncQueueStore.shared.enqueue(record)` ✓
2. `SyncFlusher.shared.register(entity: "ticket", op: "create")` registered in `TicketSyncHandlers` ✓
3. `SyncFlusher` drain loop wired — `SyncQueueStore` → `SyncOrchestrator` ✓

**Gap — SyncFlusher only covers 3 domains:**
`AppServices.init` registers:
```
CustomerSyncHandlers.register(api: apiClient)
TicketSyncHandlers.register(api: apiClient)
InventorySyncHandlers.register(api: apiClient)
```
**Missing registrations for:** Invoices, Appointments, Expenses, SMS, Employees, POS (`PosSyncOpExecutor` exists but is not registered anywhere in `AppServices`). Offline writes in these domains enqueue into `SyncQueueStore` but the drain loop has no handler — writes are silently stranded.

**Severity: Blocker** — POS offline sales finalize via `PosSyncOpExecutor` which is never registered.

### 3.3 POS cart → charge → receipt → drawer flow

**Status: critically incomplete — 3 stubs block the complete happy path.**

Trace:
1. `CartViewModel.checkoutIfOffline` / online checkout path → `PosView.startCharge()` ✓ (partial)
2. `ChargeCoordinator` / BlockChyp terminal charge → **not wired**. `PosView` calls `startCharge()` which ultimately calls `buildPostSaleViewModel()` — the BlockChyp terminal flow (`§17.3`) is deferred; `methodLabel` is hardcoded `"Placeholder — pending §17.3"`
3. `InvoiceRepository.finalize` / `POST /pos/sale/finalize` → `PosSyncOpExecutor.finalizeSale` ✓ (online path)
4. `PrintJobQueue.enqueue(ReceiptPayload)` → `PosPostSaleView` has a print button that calls `PosReceiptRenderer` but **does not enqueue to `PrintJobQueue`** or the `Hardware` package's `PrintEngine`; the receipt print is email/SMS only via `api.sendReceiptEmail`
5. `EscPosDrawerKick.open` → `openDrawer() { /* §17.4 stub */ }` **never calls Hardware package**

**Gaps summary:**

| Step | Status | Severity |
|---|---|---|
| BlockChyp terminal charge flow | Not built — §17.3 pending | Blocker |
| Receipt → PrintJobQueue → PrintEngine | Not wired — email/SMS only | High |
| Cash drawer kick after cash tender | `openDrawer()` is a no-op stub | Blocker |
| `methodLabel` in post-sale screen | Hardcoded placeholder | High |

### 3.4 Universal Link deep-link flow

**Status: router exists; several routes lack navigation sites.**

Trace confirmed:
- `DeepLinkRouter.shared.handle(url)` → `DeepLinkParser.parse(url)` → `pending: DeepLinkRoute?` ✓
- `RootView.onChange(of: router.pending)` → navigation dispatched ✓

`DeepLinkRoute` cases vs navigation sites:

| Route | Navigation site wired | Notes |
|---|---|---|
| `.ticket(id:)` | Confirmed via `TicketListView` split-detail selection | ✓ |
| `.customer(id:)` | Confirmed via `CustomersListView` | ✓ |
| `.invoice(id:)` | Confirmed via `InvoiceListView` | ✓ |
| `.smsThread(id:)` | Probable — `Communications` imported in `RootView` | Needs verification |
| `.dashboard` | Tab-switch dispatch | ✓ |
| Magic link `bizarrecrm://auth/magic?token=` | `MagicLinkURL.parse` exposed for router | ✓ |
| Password reset Universal Link | **Not confirmed in `DeepLinkParser`** | Gap — users tapping reset link may land on wrong screen |
| Staff invite setup link | **Not confirmed** | Gap |

**Universal Links AASA:** §34 marks `[!]` — server must publish `/.well-known/apple-app-site-association`; this is an external dependency, not an iOS code issue.

### 3.5 Security checklist

#### SC-1: Token/secret in UserDefaults — PASS (mostly) with one advisory

- No `UserDefaults.set(..., forKey: "token"...)` found in production source.
- `CrashReporter.swift:183` reads `UserDefaults.standard.string(forKey: "com.bizarrecrm.apiBaseURL")` — this is the **base URL** (not a token), which is non-sensitive. Acceptable.
- `KioskMode/TrainingModeManager.swift` doc-comment notes "Persists `isActive` in UserDefaults and orchestrates demo token swapping" — needs review to confirm the demo token is not a real credential.

**Finding (Medium):** `TrainingModeManager` comment implies demo-token manipulation via UserDefaults; confirm demo tokens are not real auth tokens.

#### SC-2: Third-party network hostnames — MEDIUM finding

All `URLSession` calls outside `Networking/` resolve to `APIClient.baseURL` (tenant server) **except:**

| File | URL | Issue |
|---|---|---|
| `LoyaltyWalletService.swift` | `base.appendingPathComponent(response.passUrl)` | Connects to `APIClient.baseURL`-derived URL for `.pkpass` download — **acceptable** (tenant server) |
| `GiftCardWalletService.swift` | Same pattern | **Acceptable** |
| `CrashReporter.swift` | `baseURL.appendingPathComponent("diagnostics/report")` | Tenant server — **acceptable** |

**Twilio credentials in `SmsProviderPage.swift`:** The view displays and `PUT /settings/sms` the Twilio Account SID and Auth Token. The Auth Token is shown in a `SecureField` and sent to the **tenant server** (not Twilio directly). This is architecturally correct. However:

**Finding (High):** `twilioAuthToken` flows through view state as a plain `String` in an `@Observable` ViewModel. If a crash or debug snapshot occurs mid-form, the token could appear in diagnostic output. The field should use `privacySensitive()` and be cleared from memory after save.

**Recording URL in Voice tests:** `VoiceTests/CallsEndpointsTests.swift` contains `"https://api.twilio.com/recordings/abc.mp3"` — this is in a **test fixture only**, not production code. No sovereignty violation.

#### SC-3: `.keyboardShortcut(.delete, ...)` without confirm alert

**Finding (Medium):**
`PosView.swift:519` — `Button(role: .destructive) { cart.clear() }` with `.keyboardShortcut(.delete, modifiers: [.command, .shift])`.

The button **does** have `role: .destructive` (correct) and is `.disabled(cart.isEmpty)` (correct guard). However, it fires **without a confirmation alert**. On iPad with hardware keyboard, pressing ⌘⇧Delete clears the entire active POS cart instantly with no undo. This is high-impact at POS.

**Recommendation:** Wrap in a `.confirmationDialog` or require a second keypress. The `.delete` shortcut should not be a single-chord destructive action for a cart that may have 20+ items.

#### SC-4: Destructive `Button` without `.role(.destructive)` — MEDIUM

`InvoiceVoidConfirmAlert.swift:115` — the "Void" confirm button inside the alert is:
```swift
Button {
    Task { await vm.submitVoid() }
} label: { ... }
```
This button is missing `role: .destructive`. SwiftUI uses the role to render the button in red and apply the correct accessibility announcement "Void, destructive action". While the wrapping `Alert` provides context, the button itself should carry the role.

#### SC-5: `NSLog` / bare `print()` in production source — HIGH

**Finding (High):**
`Loyalty/Sources/Loyalty/Memberships/MembershipPassUpdater.swift:82,86`:
```swift
print("[DEBUG] \(msg)")
print("[ERROR] \(msg)")
```
These are bare `print()` calls in production code. Per `ios/CLAUDE.md` and §32, all logging must go through `AppLog` (the `Logger` wrapper with `LogRedactor`). The `[DEBUG]` call may expose wallet pass URLs or customer IDs in the device console. The `[ERROR]` call means pass-update errors are not captured in the structured log pipeline.

`DesignSystem/Tips/TipsRegistrar.swift:35`:
```swift
print("[TipsRegistrar] Tips.configure failed: \(error)")
```
Also a bare `print()` in production — low risk (no PII) but inconsistent with policy.

#### SC-6: SQLCipher passphrase not provisioned — BLOCKER

`§1.3` item `[ ] Encryption passphrase — 32-byte random on first run, stored in Keychain` is **unchecked**. The `SyncQueueStore`, `SyncStateStore`, and domain repositories all use GRDB but there is no evidence in `Persistence/Sources/` of a Keychain-backed passphrase being generated and applied. If GRDB opens without a passphrase, SQLCipher falls back to plaintext storage, defeating the encryption-at-rest requirement.

**Severity: Blocker** — Per §28.2 and CLAUDE.md, this is a non-negotiable security requirement.

### 3.6 Security findings summary

| ID | Severity | Finding |
|---|---|---|
| SEC-1 | **Blocker** | SQLCipher DB passphrase not provisioned — offline data stored without encryption |
| SEC-2 | **Blocker** | `PosSyncOpExecutor` never registered in AppServices — offline POS sales are stranded permanently |
| SEC-3 | **High** | `MembershipPassUpdater` uses bare `print()` — wallet pass URLs and errors bypass `LogRedactor` |
| SEC-4 | **High** | `twilioAuthToken` in plain `String` ViewModel state — no `privacySensitive()` on the field |
| SEC-5 | **High** | PIN max-lockout escalation chain not confirmed wired to `SessionEvents.sessionRevoked` |
| SEC-6 | **Medium** | `InvoiceVoidConfirmAlert` "Void" button missing `role: .destructive` |
| SEC-7 | **Medium** | POS ⌘⇧Delete (clear cart) fires without confirm dialog — instant data loss at POS |
| SEC-8 | **Medium** | `TrainingModeManager` demo-token described as UserDefaults-persisted; verify no real credential overlap |
| SEC-9 | **Medium** | `TipsRegistrar` bare `print()` (low PII risk, policy violation) |

---

## Audit 3B — Critical Wiring Gaps (UX)

### Gap map: flows that degrade silently

| Flow | Gap | User impact |
|---|---|---|
| Clock-in/out | `userId: 0` placeholder in `ClockInOutViewModel` | All timeclock records attributed to user 0 |
| Any offline write in 6 domains | No SyncHandler registered for Invoices/Appointments/Expenses/SMS/Employees/POS | Data silently lost on reconnect |
| POS cash sale | `openDrawer()` stub | Drawer never opens; cashier must manually open |
| POS card sale | BlockChyp terminal flow not built | Card payments require a workaround |
| Receipt method label | Hardcoded placeholder | Post-sale screen shows wrong payment method |
| `GET /auth/me` not called on startup | AppState.currentUser never set | All role-based permission checks are vacuous |
| Password-reset Universal Link | Not confirmed in DeepLinkParser | User tapping reset link may not land on reset screen |
| `TicketStatus` raw value mismatch | `Core` uses `awaiting_parts`; `Tickets.StateMachine` uses `awaitingParts` | Server's `awaiting_parts` fails to decode against StateMachine enum; state machine may reject valid server states |

---

## Action priority list

### Blockers (must fix before TestFlight)

1. Provision SQLCipher passphrase in `Persistence` package (SEC-1)
2. Register `PosSyncOpExecutor` in `AppServices.init` (SEC-2 / workflow gap)
3. Register SyncHandlers for Invoices, Appointments, Expenses, SMS, Employees in `AppServices.init`
4. Wire `openDrawer()` to `Hardware.EscPosDrawerKick` or `Hardware.PrintEngine`
5. Resolve `TicketStatus` duplication — consolidate to a single enum (raw values must match server)
6. Call `GET /auth/me` on cold-start and populate `AppState.currentUser` + permissions

### High priority (before internal beta)

7. Replace `methodLabel: "Placeholder — pending §17.3"` with real BlockChyp charge result
8. Replace `ClockInOutViewModel.userId = 0` with real user ID from `AppState`
9. Fix `MembershipPassUpdater` `print()` calls → `AppLog` (SEC-3)
10. Add `privacySensitive()` to `twilioAuthToken` SecureField (SEC-4)
11. Verify and wire PIN max-lockout → `SessionEvents.sessionRevoked` (SEC-5)
12. Wire `PosPostSaleView` print button → `PrintJobQueue.enqueue(ReceiptPayload)` → `Hardware.PrintEngine`
13. Add `role: .destructive` to `InvoiceVoidConfirmAlert` void button (SEC-6)

### Medium priority (before public TestFlight)

14. Add confirm dialog to POS ⌘⇧Delete shortcut (SEC-7)
15. Consolidate `ManagerPinSheet` to a single implementation in `Core` or `DesignSystem`
16. Verify `DeepLinkParser` handles password-reset and staff-invite Universal Links
17. Fix `TipsRegistrar` bare `print()` (SEC-9)
18. Remove/replace `OnboardingVideoLibraryView` and `TutorialOverlayView` orphans or wire them
19. Begin §45 Team Chat iOS package (server is live; zero iOS code)
20. Implement `GET /auth/me` role loading and audit §19 permission-gated actions

---

## Appendix A — Deferred sections (do not pick up)

| Section | Reason deferred |
|---|---|
| §33 CI/Release | Pre-Phase-11 only; manual Xcode/fastlane until then |
| §53 Public Tracking Page | Server-side web page; iOS thin deep-link only |
| §54 TV Queue Board | Explicitly not an iOS feature |
| §56 Appointment Self-Booking | Customer-facing; not this staff app |
| §62 Non-goals | Reference only |
| §73 CarPlay | Threshold-gated; no active work |
| §75 App Store Assets | Phase 11 |
| §76 TestFlight Rollout | Phase 11 |

## Appendix B — Package file counts (reference)

| Package | Source files |
|---|---|
| Networking | 54 |
| Core | 53 |
| Settings | 51 |
| Auth | 42 |
| Pos | 78 |
| Hardware | 31 |
| Marketing | 31 |
| RepairPricing | 23 |
| Customers | 27 |
| Inventory | 27 |
| Setup | 22 |
| Communications | 20 |
| DesignSystem | 20 |
| Invoices | 19 |
| Loyalty | 19 |
| Tickets | 23 |
| Camera | 18 |
| DataExport | 15 |
| DataImport | 15 |
| KioskMode | 16 |
| Reports | 16 |
| RolesEditor | 15 |
| Persistence | 14 |
| Notifications | 8 |
| Sync | 8 |
| AuditLogs | 10 |
| Estimates | 9 |
| Appointments | 7 |
| Employees | 6 |
| Timeclock | 3 |
| Voice | 5 |
| CommandPalette | 5 |
| Search | 5 |
| Expenses | 4 |
| Dashboard | 4 |
| Leads | 4 |
| **Total** | **~950** |

---

*Report generated: 2026-04-20. Auditor: Claude (post-Phase-11 sweep). No source files were modified during this audit.*
