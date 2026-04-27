# agents.md — iOS ActionPlan 10-Agent Partition

> Scope: execution of `ios/ActionPlan.md` on branch `Ios-actionplan`.
> Orchestrator: Opus 4.7 (this session). Implementers: 10 parallel Sonnet sub-agents.
> Sister doc: `ios/agent-ownership.md` (phase + dependency map — read for sequencing context).

## Stats at a glance

- 2940 open tasks · 947 done · 35 blocked · 90 sections
- ~37 SwiftPM packages under `ios/Packages/`
- Partition target: ~290 open tasks per agent (variance accepted ±50%)

---

## Hard rules (apply to every agent)

1. **No cross-coding.** Touch only paths under your "Owns" list. If a task forces touching another agent's slice, stop and append it to the **Discovered** section at the bottom of `ios/ActionPlan.md` — do not edit and do not delegate.
2. **`APIClient+<Domain>.swift` files** live in `Packages/Networking/Sources/Networking/`. Each agent owns the file matching their domain(s). Never edit another domain's file. Add the file if missing.
3. **`Packages/DesignSystem/Sources/DesignSystem/Tokens.swift`** is shared additive: append new tokens at the bottom of the relevant enum. Never rename/delete/reorder existing tokens (Agent 10 only for that).
4. **Advisory-lock files** (must claim via PR comment before edit):
   - `App/BizarreCRMApp.swift`
   - `App/RootView.swift`
   - `App/AppServices.swift`
   - `App/AppState.swift`
   - `Packages/Core/Sources/Core/Container+Registrations.swift`
   - `Packages/Networking/Sources/Networking/APIClient.swift` (base)
   Default owner: Agent 10. Other agents request edits via PR comment; Agent 10 implements.
5. **`App/DeepLinkRouter.swift`** is shared additive: feature modules register routes via `DeepLinkRouter.register(path:handler:)` from their module init — never edit another module's registration block.
6. **Per-feature a11y, i18n, perf, snapshot tests** stay with the feature owner. Agent 10 owns the cross-cutting harnesses (CI workflows, lint scripts, Tokens, root Tests/ infra), not per-package retrofits.
7. **`ios/ActionPlan.md` content is read-only during execution.** Only flip `[ ]` → `[x]` (with commit SHA) on completion. New discoveries → "Discovered" section at bottom.
8. **Branch:** `Ios-actionplan` only. Push every commit to `origin` immediately. Never merge to `main`.
9. **Risky tasks** (auth flow rewrites, payment flows, data migrations, project-file rewrites, anything in `Configs/`, `fastlane/`, `scripts/write-info-plist.sh`, entitlements): pause and surface to orchestrator before dispatching.
10. **Match style and architecture** of neighbouring code. Read 2-3 sibling files before adding a new one.

---

## Agent roster

| # | Title | Sections | Open est. | Domain |
|---|---|---|---|---|
| 1 | POS & Register & Payments | §16, §39, §40, §41 | ~219 | Pos / Cash / Gift cards / Pay links |
| 2 | Hardware & Camera & Voice | §17, §42, §4 camera bits | ~170 | Printers / scanners / scale / drawer / terminals / camera / voice |
| 3 | Tickets & Estimates & Repair pricing | §4 (non-camera), §8, §43 | ~213 | Service jobs / quotes / device catalog |
| 4 | Customers & Leads & Loyalty & Marketing | §5, §9, §37, §38, §44 | ~217 | CRM / pipelines / memberships / campaigns |
| 5 | Inventory & Appointments & Expenses & Field-service | §6, §10, §11, §57, §58 | ~161 | Stock / scheduling / spend / field tech / POs |
| 6 | Invoices & Reports & Data IO & Audit & Financial | §7, §15, §48, §49, §50, §59 | ~130 | Billing / analytics / import-export / audit |
| 7 | Employees & Timeclock & Roles & Communications | §12, §14, §45, §46, §47 | ~171 | Staff / shifts / chat / SMS / role matrix |
| 8 | Auth & Setup & Kiosk & Command Palette | §2, §36, §51, §52, §55, §60, §79 | ~141 | Login / 2FA / onboarding / training / multi-tenant |
| 9 | Settings shell & Dashboard & Search & Notifications & Widgets/Intents/Spotlight | §3, §13, §18, §19, §21, §24, §25, §65, §70 | ~370 | App shell surfaces |
| 10 | Platform / Sync / Design System / Networking core / Security / Perf / Release | §1, §20, §22, §23, §26, §27, §28, §29, §30, §31, §32, §33, §61, §63, §64, §66, §67, §68, §69, §72, §74, §80–§90 | ~700 (mostly token/infra adds) | Foundations |

---

## Agent 1 — POS & Register & Payments

**Sections:** §16 POS/Checkout · §39 Cash register/Z-report · §40 Gift cards/Store credit/Refunds · §41 Payment links

**Owns (exclusive):**
- `ios/Packages/Pos/**`
- `ios/Packages/Networking/Sources/Networking/APIClient+POS.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+CashRegister.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+GiftCards.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+PaymentLinks.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+HeldCarts.swift`
- Tests under `ios/Packages/Pos/Tests/**`

**Settings sub-pages owned:** Pricing rules, Discount engine config, Coupon codes, Held carts admin (under `Packages/Pos/Settings/**`).

**Cross-package coordination:** Hardware integrations (printer, drawer, BlockChyp, scanner) — request via Agent 2 PR. Customer / inventory lookups — read-only via repository protocols from Agent 4 / Agent 5.

---

## Agent 2 — Hardware & Camera & Voice

**Sections:** §17 Hardware integrations · §42 Voice & calls · §4 camera sub-features (photo annotation, doc scanner, voice memos)

**Owns (exclusive):**
- `ios/Packages/Hardware/**` (Printing, Labels, Terminal/BlockChyp, Bluetooth, Scale, Drawer, Firmware)
- `ios/Packages/Camera/**` (Barcode, Annotation, DocScan, Voice)
- `ios/Packages/Voice/**`
- `ios/Packages/Networking/Sources/Networking/APIClient+Hardware.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Voice.swift`
- Tests under each package's `Tests/**`

**Settings sub-pages owned:** Printers, BlockChyp pairing, Bluetooth devices, Scale config (under `Packages/Hardware/Settings/**`).

**Cross-package coordination:** POS receipt rendering uses Hardware printing — Hardware exposes protocol; Pos consumes.

---

## Agent 3 — Tickets & Estimates & Repair Pricing

**Sections:** §4 Tickets (excluding camera/voice/annotation — those go to Agent 2) · §8 Estimates · §43 Device templates / repair-pricing catalog

**Owns (exclusive):**
- `ios/Packages/Tickets/**`
- `ios/Packages/Estimates/**`
- `ios/Packages/RepairPricing/**`
- `ios/Packages/Networking/Sources/Networking/APIClient+Tickets.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Estimates.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+RepairPricing.swift`
- Tests under each package's `Tests/**`

**Settings sub-pages owned:** Device templates, Repair pricing, Ticket templates/macros, Warranty config, SLA tracking, QC checklist (under `Packages/Tickets/Settings/**` or `Packages/RepairPricing/Settings/**`).

**Cross-package coordination:** Estimate→Ticket conversion stays within Agent 3 (both packages owned). Photo annotation invoked via Camera protocol from Agent 2.

---

## Agent 4 — Customers & Leads & Loyalty & Marketing

**Sections:** §5 Customers · §9 Leads · §37 Marketing & growth · §38 Memberships/Loyalty · §44 CRM health & LTV

**Owns (exclusive):**
- `ios/Packages/Customers/**` (incl. Merge, Tags, Segments, Customer 360, Notes, Files, CSAT, NPS, Reviews, Birthdays, Complaints)
- `ios/Packages/Leads/**` (incl. Pipeline, Scoring, Conversion, Lost, FollowUp, Sources)
- `ios/Packages/Loyalty/**` (incl. Engine, Memberships, PunchCard, Renewals, Dunning, LateFees, Referrals)
- `ios/Packages/Marketing/**` (Campaigns, Coupons, ReviewSolicitation, EmailTemplates)
- `ios/Packages/Networking/Sources/Networking/APIClient+Customers.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Leads.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Loyalty.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Marketing.swift`

**Settings sub-pages owned:** Marketing settings, Loyalty settings, Reviews, Referral program config, Survey, Customer tags admin.

**Cross-package coordination:** SMS templates for marketing campaigns delivered via Communications protocol from Agent 7.

---

## Agent 5 — Inventory & Appointments & Expenses & Field-Service & Purchase Orders

**Sections:** §6 Inventory · §10 Appointments & calendar · §11 Expenses · §57 Field-service/Dispatch · §58 Purchase orders

**Owns (exclusive):**
- `ios/Packages/Inventory/**` (incl. Receiving, Stocktake, Variants, Bundles, Batch/Lot, Serial, Transfers, Reconciliation, Damage, Aging, Reorder)
- `ios/Packages/Appointments/**` (incl. Scheduling engine)
- `ios/Packages/Expenses/**` (incl. Mileage, Per-diem, Approvals)
- `ios/Packages/FieldService/**`
- `ios/Packages/Networking/Sources/Networking/APIClient+Inventory.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Appointments.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Expenses.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+FieldService.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+PurchaseOrders.swift`

**Settings sub-pages owned:** Vendor management, Tax classes (inventory side), Re-order rules.

**Cross-package coordination:** Barcode scan invoked via Camera protocol from Agent 2. Inventory sale events flow to POS via repository.

---

## Agent 6 — Invoices & Reports & Data IO & Audit & Financial Dashboard

**Sections:** §7 Invoices · §15 Reports & analytics · §48 Data import · §49 Data export · §50 Audit logs · §59 Financial dashboard

**Owns (exclusive):**
- `ios/Packages/Invoices/**` (incl. Payment, Refunds, RecurringInvoices, CreditNotes)
- `ios/Packages/Reports/**` (incl. BI, DrillThrough, Charts)
- `ios/Packages/DataImport/**` (RepairDesk/Shopr/MRA/CSV)
- `ios/Packages/DataExport/**`
- `ios/Packages/AuditLogs/**`
- `ios/Packages/Networking/Sources/Networking/APIClient+Invoices.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Reports.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+RecurringInvoices.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+CreditNotes.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Audit.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+DataIO.swift`

**Settings sub-pages owned:** Audit log viewer, Data import wizard, Data export, Tax engine UI, Multi-currency settings.

---

## Agent 7 — Employees & Timeclock & Roles & Communications

**Sections:** §12 SMS & communications · §14 Employees & timeclock · §45 Team collaboration (internal chat) · §46 Goals/Performance/PTO · §47 Roles matrix editor

**Owns (exclusive):**
- `ios/Packages/Employees/**` (incl. Clock, Commissions, Scorecards, PeerFeedback, Recognition)
- `ios/Packages/Timeclock/**` (Shifts, Swap, Time-off, Timesheet edits)
- `ios/Packages/RolesEditor/**`
- `ios/Packages/Communications/**` (SMS threads + templates + TeamChat + EmailTemplates body)
- `ios/Packages/Networking/Sources/Networking/APIClient+Employees.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Schedule.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+TimeOff.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Timesheet.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Roles.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Comms.swift`

**Settings sub-pages owned:** Roles matrix, Hours & holiday calendar, Goals config, SMS settings.

**Cross-package coordination:** Marketing SMS campaigns: Agent 4 imports Comms send-protocol from Agent 7.

---

## Agent 8 — Auth & Setup & Kiosk & Command Palette & Multi-Tenant

**Sections:** §2 Authentication & onboarding · §36 Setup wizard · §51 Training mode · §52 Command palette (⌘K) · §55 Kiosk modes · §60 Multi-location · §79 Multi-tenant session mgmt

**Owns (exclusive):**
- `ios/Packages/Auth/**` (Login, 2FA, Recovery, SSO, MagicLink, Passkey, PIN, SharedDevice, SessionTimer, CredentialStore, TenantSwitcher)
- `ios/Packages/Setup/**`
- `ios/Packages/KioskMode/**`
- `ios/Packages/CommandPalette/**`
- `ios/Packages/Networking/Sources/Networking/APIClient+Auth.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Tenant.swift` (writes; reads coord with Agent 9)
- `ios/Packages/Networking/Sources/Networking/APIClient+Setup.swift`

**Settings sub-pages owned:** Profile, Danger Zone (account/sign-out paths), Training mode toggle, Multi-location switcher, Setup wizard re-entry.

**Risky:** Auth/2FA/Passkey/SSO changes — flag to orchestrator before non-trivial edits.

---

## Agent 9 — Settings shell & Dashboard & Search & Notifications & Widgets/Intents/Spotlight

**Sections:** §3 Dashboard · §13 Notifications · §18 Search (global + scoped + FTS) · §19 Settings (shell + non-domain sub-pages) · §21 Background/Push/Real-time · §24 Widgets / Live Activities / App Intents / Siri / Shortcuts · §25 Spotlight / Handoff / Universal Clipboard / Share Sheet · §65 Deep-link reference doc · §70 Notifications event matrix

**Owns (exclusive):**
- `ios/Packages/Dashboard/**`
- `ios/Packages/Search/**` (incl. FTS5 indexer, Spotlight bridge)
- `ios/Packages/Notifications/**` (Push, Categories, UX)
- `ios/Packages/Settings/**` (shell + Search index + sub-pages NOT claimed by other agents)
- `ios/App/Widgets/**` (new target)
- `ios/App/Intents/**` (new target, incl. Shortcuts gallery)
- `ios/App/Handoff/**`
- `ios/App/Clipboard/**`
- `ios/App/Sidebar/**`
- `ios/App/Scenes/**` (multi-window / Stage Manager / DetailWindowScene)
- `ios/App/Keyboard/**`
- `ios/Packages/Networking/Sources/Networking/APIClient+Dashboard.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Search.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+Notifications.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+ActivityFeed.swift`
- `ios/Packages/Networking/Sources/Networking/APIClient+NotifPrefs.swift`

**Settings sub-pages owned:** Notifications settings, Appearance, Language, Tenant Admin, Feature Flags, About, Diagnostics, Widgets settings, Shortcuts settings, Search scope.

**Sub-pages explicitly NOT owned (delegated):** Roles → Agent 7 · Audit → Agent 6 · DataImport/Export → Agent 6 · Training → Agent 8 · Multi-loc → Agent 8 · Marketing/Loyalty/Reviews/Referral/Survey → Agent 4 · Pricing/Discounts/Coupons → Agent 1 · Printers/BlockChyp/Bluetooth/Scale → Agent 2 · Vendors → Agent 5 · DeviceTemplates → Agent 3 · Tax → Agent 6 · Hours/Holidays/Goals/SMS → Agent 7 · Profile/DangerZone/SetupWizard/MultiLoc → Agent 8.

---

## Agent 10 — Platform / Foundation / Design System / Sync / Networking / Security / Perf / Release

**Sections:** §1 Platform & foundation · §20 Offline/Sync/Caching · §22 iPad shell (per-feature iPad polish stays with feature owner) · §23 Mac polish shell · §26 A11y (label catalog + audit infra; per-feature labels stay with feature) · §27 i18n infra · §28 Security & privacy · §29 Performance budgets (harness) · §30 Design System & motion · §31 Test strategy & infra · §32 Telemetry/crash/logging · §33 CI/Release/TestFlight/AppStore (deferred but owned) · §61 Release checklist · §63 Error/Empty/Loading patterns infra · §64 Copy guide · §66 Haptics catalog · §67 Motion spec · §68 Launch experience · §69 In-app help · §72 Final UX polish · §74 Server API gap audit · §80 Token table · §81 API endpoint catalog · §82 Phase DoD · §86–§90 Server map / ERD / state diagrams / arch / STRIDE

**Owns (exclusive):**
- `ios/Packages/Core/**` (Platform, Logging, Errors, Drafts, A11y/Labels, FeatureFlag, Container)
- `ios/Packages/Persistence/**` (GRDB, SQLCipher, Migrations, Backup)
- `ios/Packages/Sync/**` (sync_queue, sync_state, OfflineBanner, StalenessIndicator, DeadLetter)
- `ios/Packages/Networking/Sources/Networking/APIClient.swift` (base only)
- `ios/Packages/Networking/Sources/Networking/PinnedURLSessionDelegate.swift`
- `ios/Packages/Networking/Sources/Networking/RateLimiter.swift`
- `ios/Packages/DesignSystem/**` (Tokens.swift = additive shared, but renames/deletions are this agent only)
- `ios/App/BizarreCRMApp.swift`
- `ios/App/AppServices.swift`
- `ios/App/AppState.swift`
- `ios/App/RootView.swift`
- `ios/App/SyncOrchestrator.swift`
- `ios/App/SessionBootstrapper.swift`
- `ios/App/DeepLinkRouter.swift` (registration table; feature modules add via additive helper)
- `ios/App/Resources/**` (incl. Info.plist generator inputs, Assets, Locales)
- `ios/Tests/**` (root XCUITest + smoke + a11y audit + perf bench)
- `ios/project.yml`
- `ios/scripts/**`
- `ios/Configs/**`
- `ios/fastlane/**`
- `.github/workflows/ios-*.yml`
- `docs/security/**`
- `docs/runbooks/**`

**Risky:** project.yml, scripts/write-info-plist.sh, entitlements, fastlane lanes — flag to orchestrator before non-trivial edits.

---

## Shared additive contracts

| File / Path | Rule |
|---|---|
| `Packages/DesignSystem/Sources/DesignSystem/Tokens.swift` | Append only. Never reorder / rename / delete. Renames = Agent 10 task. |
| `Packages/Core/Sources/Core/FeatureFlag.swift` | Append cases only. Never reorder. |
| `App/DeepLinkRouter.swift` | Add routes via `DeepLinkRouter.register(...)` calls in feature module init. Don't edit existing entries. |
| `Packages/Networking/Sources/Networking/APIClient+<Domain>.swift` | One file per domain, exclusive to that domain's owner. New domain → that owner adds the file. |
| `App/Resources/Locales/<lang>.lproj/Localizable.strings` | Each feature owner appends English keys for their package; Agent 10 coordinates non-English locales. |

---

## Phase / sequencing notes

Per `ios/agent-ownership.md`, work has phase dependencies:
- Phase 0 foundations (Sync, DI, DesignSystem, Networking) must close before write flows.
- Phase 1 Auth must close before any authenticated surface.

Most foundation work is already `[x]` done. Each agent should grep for `[ ]` in their owned sections and verify upstream `[x]` before starting. If blocked on a Phase-0 foundation gap, file under "Discovered" and pause.

---

## Discovered (out-of-scope findings)

Agents append here when work uncovers issues outside their slice.

### Agent 9 — b5 discoveries

**§65.1 Universal Links entitlement — Agent 10 action needed (§28 / entitlements / project.yml)**
The `applinks:app.bizarrecrm.com` and `applinks:*.bizarrecrm.com` associated-domains entitlement must be added to `BizarreCRM.entitlements` (Agent 10 owns that file per the advisory-lock rule). The §65 deep-link section in `ServerConnectionPage.swift` documents the requirement and the public-path exclusion (`/public/*` must NOT be in AASA so customers see the web page). Agent 10 should add the `com.apple.developer.associated-domains` key to the entitlements file. The AASA JSON file itself is server-side (Agent 10 server work or ops).

**Pre-existing Networking compile errors (Agent 10 + Agent 1 fixes needed)**
Two classes of pre-existing errors found during b5 build gate:
1. `APIClient+Pos.swift` lines 259+274: nested struct inside generic function causes Swift 6 error — `PatchTicketDraftBody` and `SignatureBody` must be moved out of the generic func scope. Agent 1 owns this file.
2. `WebSocketConnection.swift` lines 40+46: `reference to property 'url' in closure requires explicit use of 'self'` — Swift 6 strict concurrency. Agent 10 owns this file.
3. `InvoiceDetailEndpoints.swift` line 186: `invalid redeclaration of 'EmptyBody'` — private struct with same name in another file. Agent 6 owns this file.
These errors prevent `swift test` from completing across the full package graph. Per-package tests on Agent 9's own packages (Notifications, Settings, Search) compile and pass cleanly.

### Agent 2 — b9 discoveries

**`UIBackgroundModes bluetooth-central` + `CBCentralManagerOptionRestoreIdentifierKey` — Agent 10 action needed (`scripts/write-info-plist.sh` + `project.yml`)**

`BluetoothBackgroundManager` (b9, `b4b3b9f0`) implements the Swift-side state-restoration delegate for CoreBluetooth background mode. For the background reconnection to work at runtime, two changes are needed in files owned by Agent 10:

1. `scripts/write-info-plist.sh` — add `bluetooth-central` to the `UIBackgroundModes` array.
2. `BluetoothManager.init` — pass `[CBCentralManagerOptionRestoreIdentifierKey: BluetoothBackgroundManager.restoreIdentifier]` as options when constructing `CBCentralManager`, and wire `centralManager(_:willRestoreState:)` delegate method to call `BluetoothBackgroundManager.shared.handleWillRestoreState(_:manager:)`.

The `BluetoothManager` init and the `CBCentralManagerDelegate` extension both live in `ios/Packages/Hardware/Sources/Hardware/Bluetooth/BluetoothManager.swift` (Agent 2 owns this file). Agent 2 will implement the delegate wiring in a follow-up batch once Agent 10 confirms the `UIBackgroundModes` key is added (ordering: plist change first so CI doesn't fail on missing entitlement).

### Agent 1 — b10 BlockChyp tasks STOPPED (HIGH RISK — orchestrator review required)

**§16.5 BlockChyp live payment flow** (8 open tasks: start-charge, signature-capture, receipt-data POST, success/partial-auth/decline/timeout/tip-adjust/void/offline) — these require live payment rail calls via `POST /api/v1/blockchyp/process-payment` and manipulation of authorization tokens, partial-auth states, and refund-by-token flows. Per hard rule "BlockChyp payment math = HIGH RISK → STOP", all §16.5 tasks are paused. Existing scaffold code lives in `ios/Packages/Pos/Sources/Pos/BlockChyp/` (`BlockChypReaderStateView`, `BlockChypHeartbeatView`, `BlockChypTerminalPairingView`, `SignatureRouter`, `SignatureSheet`). Server routes exist in `packages/server/src/services/blockchyp.ts:63-790`. Also note: pre-existing Swift 6 compile errors in `APIClient+POS.swift` lines 259+274 (nested structs in generic functions) per Agent 9 b5 Discovered — these must be fixed before §16.5 can proceed. Orchestrator should approve before any agent implements live card payment processing.

**§16.9 Return tender (BlockChyp refund with token) + return receipt** — the "Tender — original card (BlockChyp refund with token)" and "Receipt — RETURN printed; refund amount; signature if required" tasks involve BlockChyp token replay. Same HIGH RISK category. Paused alongside §16.5.

---

## Workflow per agent (reminder)

### CRITICAL FIRST STEP for batch 2 onwards

Your isolated worktree is created off `main`, NOT off `Ios-actionplan`. Before reading any files, run:
```bash
cd ios   # or repo root
git fetch origin
git reset --hard origin/Ios-actionplan
```
This pulls in all merged work from sibling agents (and your own prior batches). Skipping this step causes you to re-implement work that's already merged, producing massive merge conflicts.

### Per batch

1. Run the rebase step above.
2. Read your assigned sections in `ios/ActionPlan.md` end-to-end.
3. Read `ios/CLAUDE.md` and `ios/agent-ownership.md` for non-negotiables.
4. Read 2-3 sibling files in your owned packages before adding new code.
5. Implement task-by-task; flip `[ ]` → `[x]` with commit SHA in ActionPlan.md as you finish each.
6. **Light gate (default):** `bash ios/scripts/sdk-ban.sh` only. Skip `swift test` and `swift build` unless you specifically need to verify a non-trivial change. Spot-check single-package compile via `swift build --package-path Packages/<YourPkg>` if uncertain. Pre-existing failures across other packages are tracked in Discovered — do not chase them.
7. Commit per batch (preferred) or per task. **Do NOT push** — orchestrator merges + pushes after review.
8. Report back to orchestrator when batch done OR blocked — do not start next batch until reviewed.

### Disk hygiene

Each `.build` directory consumes 600–900 MB. Across 30+ active worktrees, this can fill the disk. If `swift test` reports disk-full, stop and report — orchestrator will purge inactive `.build` dirs.
