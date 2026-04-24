# POS mockup → app implementation wave

Plan for turning `ios/pos-iphone-mockups.html` + `ios/pos-ipad-mockups.html`
into shipping SwiftUI. The mockups are approved (cart-right confirmed by
14-app market survey; cream dark / deep-orange light primaries; Liquid
Glass chrome; service-bundle auto-add documented in §4.7 of
`pos-redesign-plan.md`).

Each agent below owns an exclusive new subfolder under
`ios/Packages/<Package>/Sources/<Package>/<NewSubdir>/` so parallel work
cannot conflict. Tests land in the matching `Tests/<Package>Tests/<NewSubdir>/`.

All agents must:
- Use real server routes only (read `packages/server/src/routes/*.ts` first)
- Mirror the Android implementation when the Kotlin version exists in `android/app/src/main/java/...`
- Wire end-to-end (no orphan UI) — View → @Observable VM → Repository → APIClient → server
- Hit ≥80% unit test coverage on the new subfolder
- Apply `.reduceMotion` / `.reduceTransparency` fallbacks
- Use the existing `BrandColors.swift`, `BrandFonts.swift`, `BrandSpacing.swift`, `BrandMotion.swift`
- Build green: run `bash ios/scripts/gen.sh` if project.yml changes (it shouldn't for new files)
- Commit to a new branch `agent/<name>` and stop — orchestrator merges to main

---

## Agent A — Design tokens (light / dark / cream / deep-orange primary)

Path: `ios/Packages/DesignSystem/Sources/DesignSystem/POSTheme/`

Deliverables:
- `POSThemeTokens.swift` — new `struct POSThemeTokens: Sendable` mirroring the HTML `:root`:
  `bgDeep`, `bg`, `surfaceSolid`, `surfaceElev`, `surfaceGlass`, `outline`,
  `outlineBright`, `on`, `muted`, `muted2`, `primary`, `primaryBright`,
  `primarySoft`, `onPrimary`, `success`, `warning`, `error`, `teal`.
- Two static providers: `.dark` (cream primary `#fdeed0`, on-primary `#2b1400`,
  `bg #0c0b09`, etc.) and `.light` (deep orange primary `#c2410c`, on-primary
  `#ffffff`, `bg #f5f2ed`, etc.).
- `EnvironmentKey` for `posTheme` so views read via
  `@Environment(\.posTheme) private var theme`.
- `POSThemeModifier.swift` — `.posTheme(for: colorScheme)` view modifier that
  resolves `@Environment(\.colorScheme)` to dark/light + hands the correct
  `POSThemeTokens` into the env. Gated by user preference override (System /
  Light / Dark) via `@AppStorage("pos.theme.override")`.
- `BrandColors` gets the new tokens layered on top of the existing `bizarre*`
  palette so old code keeps compiling.
- Tests: ≥8 unit tests verifying token values match the HTML hex codes,
  light/dark switch behavior, override precedence.

Constraints: Do not edit existing `BrandColors.swift` / `BrandFonts.swift`
except to add a new public factory that returns a `POSThemeTokens` for a
given color scheme. Do not regenerate the Xcode project.

---

## Agent B — Customer gate (Frame 1)

Path: `ios/Packages/Pos/Sources/Pos/Gate/`

Reference frames:
- iPhone Frame 1 in `ios/pos-iphone-mockups.html`
- iPad Frame 1 in `ios/pos-ipad-mockups.html`

Deliverables:
- `PosGateView.swift` — SwiftUI view. On iPhone: hero search pill in a
  `NavigationStack`, "Can't find them?" label, two side-by-side fallback
  buttons `[+ Create new]` `[🚶 Walk-in]`. Safe-area-inset bottom for the
  primary action if any. On iPad: a centered 680pt-wide search card in the
  items column of `NavigationSplitView(columnVisibility: .detailOnly)` plus
  the 2 buttons beneath; cart column shows "No customer" placeholder.
  Size-class adaptive via `@Environment(\.horizontalSizeClass)`.
- `PosGateViewModel.swift` — `@MainActor @Observable`. Holds `query: String`,
  `results: [CustomerSearchHit]`, `isSearching: Bool`, `errorMessage: String?`.
  `onQueryChange(_:)` with 250ms debounce + `Task` cancellation. Calls the
  existing `CustomerRepository.search(keyword:)`.
- `PosGateRoute.swift` — `enum` exposing the 3 exit destinations: `.existing(CustomerID)`,
  `.createNew`, `.walkIn`. Drives the parent `PosRouter`.
- Wire `.searchable(placement: .navigationBarDrawer(displayMode: .always))`
  on iPhone; `.searchable` (automatic = top trailing on iPad) on iPad.
- `⌘K` keyboard shortcut focuses the hero search on iPad.
- Haptic `.impact(.light)` on each fallback button tap.
- Tests: ≥10 cases — empty-query state, debounce fires once, cancellation
  on keystroke, walk-in returns the sentinel route, create-new returns
  the route, error from repo surfaces in `errorMessage`.

Server route: `GET /api/v1/customers?keyword=` (confirm in
`packages/server/src/routes/customers.routes.ts`). Reuse existing
`CustomerRepository.list(keyword:)`.

---

## Agent C — Repair flow (Frames 1b → 1e)

Path: `ios/Packages/Pos/Sources/Pos/RepairFlow/`

Reference frames:
- Frame 1b Pick device, 1c Describe issue, 1d Diagnostic + quote, 1e Deposit
  in both iPhone + iPad mockups.

Deliverables:
- `PosRepairFlowCoordinator.swift` — `@MainActor @Observable` state machine
  across the 4 steps. Exposes `currentStep: RepairStep` enum, `advance()`,
  `goBack()`, `savedDraftId: TicketDraftID?`.
- `PosRepairDevicePickerView.swift` (1b) — saved-devices list from
  `GET /customers/:id/assets`; "Add new device" row with inline `📷` scan
  button (merged, not two rows); confirm CTA "Continue → describe issue".
  iPad variant renders inside `.inspector` pane.
- `PosRepairSymptomView.swift` (1c) — symptom textarea, device-condition
  dropdown, 5 quick-pick chips (Screen cracked / Won't charge / Water
  damage / Battery / Other), internal notes field, progress bar 25% /
  50% / 75% / 100%.
- `PosRepairQuoteView.swift` (1d) — diagnostic notes field, suggested
  parts + labor checklist pre-populated by server BOM resolver (see
  Agent F), running estimate, "Save as quote" vs "Continue to deposit".
- `PosRepairDepositView.swift` (1e) — reuses the tender UI from Agent D
  with a preset amount (default 15% of total, editable), shows
  "Deposit $50 of $327" header + balance-due-at-pickup footer.
- Tests: ≥16 cases across the coordinator + the four step VMs.

Server routes (confirm before writing):
- `GET /api/v1/customers/:id/assets` — saved devices
- `POST /api/v1/tickets` — create the draft
- `POST /api/v1/tickets/:id/devices` — attach device to draft
- `PATCH /api/v1/tickets/:id` — update symptom / diagnostic fields
- `POST /api/v1/tickets/:id/convert-to-invoice` — when deposit is tendered

---

## Agent D — Tender two-step (method picker + amount entry)

Path: `ios/Packages/Pos/Sources/Pos/TenderV2/`

Reference frames:
- iPhone Frame 5a (method picker) + 5b (amount entry)
- iPad Frame 4a (method picker in side panel) + 4b (amount entry)

Deliverables:
- `PosTenderCoordinator.swift` — `@MainActor @Observable`. Tracks
  `method: TenderMethod?`, `appliedTenders: [AppliedTender]`, `remaining: Int`
  (cents), `isSplit: Bool`. Advances from method-picker → amount-entry →
  confirm; on partial payment rolls back to method picker with remaining
  balance displayed.
- `PosTenderMethodPickerView.swift` — 4 method tiles (Card / Cash / Gift
  card / Store credit). On iPhone: full-screen. On iPad: replaces items
  area while cart column stays locked on the right. Shows a split-tender
  hint row + member-benefit banner at the top (only when customer attached
  and is a member).
- `PosTenderAmountEntryView.swift` — method-specific sub-flow:
  - Cash: `PosCashNumpad` + received/change glass panel + quick-amount
    chips (Exact, +$5, +$10, +$20, custom) above the numpad. Numpad keys
    ≥56pt (iPhone) / 72pt (iPad). Barlow Condensed digits.
  - Card: "Tap to Pay" placeholder view that wraps a future
    `PosTapToPayView` stub (`ProximityReader` entitlement pending —
    leave a TODO + show a placeholder illustration).
  - Gift card: scan-or-enter flow.
  - Store credit: balance apply view.
- `PosTenderAmountBar.swift` — the bottom CTA row (Split payment + Add
  tip + Confirm). `.sensoryFeedback(.success, trigger: confirmedAt)`.
- Tests: ≥20 cases across coordinator + each method sub-flow. Cover
  partial payment loop, full payment → next stage, cancel → back to
  cart, validate cash-received ≥ due.

Server routes:
- `POST /api/v1/pos/transactions` — single tender
- `POST /api/v1/pos/transactions/:id/split` — additional tender
- `POST /api/v1/pos/transactions/:id/void` — mistake recovery

---

## Agent E — Receipt frame + cart-collapse + share sheet

Path: `ios/Packages/Pos/Sources/Pos/Receipt/`

Reference frames:
- iPhone Frame 6 Receipt
- iPad Frame 5 Receipt (cart column collapses 420 → 0 on iPad)

Deliverables:
- `PosReceiptView.swift` — confirmation hero (72pt check glyph, 54–64pt
  amount in Barlow Condensed, success-green radial glow), share tiles
  (Text / Email / Print / AirDrop) as a 4-up grid; SMS primary gets cream
  bloom on dark. Post-sale loyalty celebration row with star + tier
  progress bar.
- `PosReceiptViewModel.swift` — consumes `ReceiptPayload` from the tender
  coordinator, pre-fills default share channel (SMS if customer has a
  phone on file, else Print), exposes `share(channel:)` calls that run
  through `ShareLink` / `UIActivityViewController`.
- `PosCartCollapseModifier.swift` — iPad-only `ViewModifier` that animates
  the cart column width `420 → 0` on `.paid` state (240ms spring; falls
  through to 150ms opacity fade under `.reduceMotion`).
- `PosShareTile.swift` — reusable glass tile with icon + label.
- Tests: ≥12 cases. Receipt rendering, pre-selection logic, collapse
  animation reaches 0, Reduce Motion fallback.

Server routes:
- `POST /api/v1/receipts/send-sms { invoiceId, phone }`
- `POST /api/v1/receipts/send-email { invoiceId, email }`
- No print route — AirPrint is local. AirDrop is local share sheet.

---

## Agent F — Service-bundle auto-add (BOM resolver)

Path: `ios/Packages/Pos/Sources/Pos/Bundles/`

Spec source: `docs/pos-redesign-plan.md` §4.7.

Deliverables:
- `ServiceBundleResolver.swift` — actor. `paired(for serviceItemId: Int64,
  device: CustomerAsset?) async throws -> BundleResolution`. Returns:
  required children + optional children + any missing-BOM fallback.
- `BundleResolution.swift` — value type: `required: [InventoryItemRef]`,
  `optional: [InventoryItemRef]`, `bundleId: UUID`.
- `Cart+addBundle.swift` — extension adding
  `mutating func addBundle(serviceItemId:, device:) async throws`. Performs
  a single atomic `beginTransaction`: service line + all required
  children in one array, tagged with the same bundle id, so undo is atomic.
- `PosCatalogGrid+bundleBadge.swift` — small link-badge icon on catalog
  tiles when a service has children (preview on long-press lists the
  children).
- `BundleRemoveConfirmation.swift` — action-sheet "Remove paired parts
  too?" with default Yes.
- Tests: ≥14 cases. Device-aware resolution (iPhone 14 → iPhone 14 Pro
  Screen); walk-in triggers picker; optional siblings appear as chips;
  qty scaling; remove-cascade; out-of-stock display.

Server route: `GET /api/v1/inventory/items/:id/bundle` — returns
`{ required: [...], optional: [...] }`. If not yet present, write a
stub repo that throws `.notImplemented` so the UI degrades to a modal
part-picker; document which server route we still need.

---

## Agent G — Rail sidebar (custom 64pt iPad icon rail)

Path: `ios/Packages/Core/Sources/Core/Rail/`

Reference: iPad frame rail on every mockup frame. No native SwiftUI
support for an icon-only rail.

Deliverables:
- `RailSidebarView.swift` — `@MainActor` SwiftUI view. 64pt wide, icon-
  only, 8 items, brand mark at top (tap → expand to 200pt `doubleColumn`
  for 30 s then auto-collapse), `.hoverEffect(.highlight)` on every
  item, active tab shows cream-tinted pill (dark) / orange-tinted pill
  (light), avatar bottom.
- `RailItem.swift` — value type with icon SF Symbol + title + destination
  route; optional badge (count or dot).
- `RailCatalog.swift` — static list of the 8 primary destinations:
  Dashboard, Tickets, Customers, POS, Inventory, SMS, Reports, Settings.
- `ShellLayout.swift` — `HStack { RailSidebar; NavigationSplitView(...)
  columnVisibility: .detailOnly }` so the default sidebar column is
  suppressed and the rail owns primary nav.
- Tests: ≥8 cases. Active-pill flips on selection, brand-tap expands +
  auto-collapses, badge count binding, Reduce Motion kills the
  expand-animation.

Integration: `App/RootView.swift` adopts `ShellLayout` in a follow-up
commit by the orchestrator — Agent G stops at the component level.

---

## Agent H — Membership surfaces (checkout-only)

Path: `ios/Packages/Pos/Sources/Pos/Membership/`

Rule (from user feedback): loyalty appears ONLY at tender + receipt.
Never on cart, catalog, customer gate, or inspector.

Deliverables:
- `MembershipBenefitBanner.swift` — the cream/orange top banner on the
  tender method picker. Shows tier + pts available + "SAVED $X" chip +
  "REDEEM PTS" action.
- `MembershipTierProgress.swift` — post-sale row. Star glow + tier
  progress bar (GOLD 285 / 500 → PLATINUM). Renders in the receipt
  frame only.
- `MembershipViewModel.swift` — consumes `LoyaltyAccount` from existing
  loyalty repo (if missing, a read stub). Computes applied discount,
  pts earned, pts to next tier.
- `RedeemPointsSheet.swift` — detent sheet that lets cashier apply
  N pts worth of discount mid-tender.
- Tests: ≥10 cases. Tier math, redeem limit enforcement (≤ cart total),
  silver / gold / platinum thresholds, no-customer fallback (benefits
  hidden).

Server routes:
- `GET /api/v1/customers/:id/loyalty`
- `POST /api/v1/loyalty/redeem`

---

## Wiring-up (orchestrator, not agents)

After all 8 agents land:
1. `App/RootView.swift` — adopt `ShellLayout` from Agent G
2. `Packages/Pos/Sources/Pos/PosView.swift` — route through the new
   `PosGateView` at launch → `PosCartView` post-attach → `PosTenderCoordinator`
   at charge → `PosReceiptView` at paid, with the cart-collapse modifier.
3. Inject `POSThemeTokens` at the `WindowGroup` root.
4. Add `PosRepairRoute` to the gate exit map.
5. Apply `.posTheme(for: colorScheme)` on `RootView`.
6. Run the full test suite.
7. Build + install on iPad Pro 11" 3rd gen device for end-to-end smoke.
8. Commit to main + push.

Wiring is deliberately scoped out of the parallel wave because it
touches `App/RootView.swift` which every agent would otherwise race on.

---

## Quality gates per agent

- Swift 6 strict concurrency clean (no `@unchecked Sendable` cop-outs
  without a comment explaining why)
- No force-unwraps outside test code
- `AppLog.pos.error(...)` on every error branch
- Accessibility: every interactive element gets `.accessibilityLabel`
  and `.accessibilityHint`; rows combine children via
  `.accessibilityElement(children: .combine)`
- Dynamic Type caps at `.accessibility2` for layout-sensitive text
- Tests: XCTest or Swift Testing — pick one per subfolder, don't mix

Each agent reports: files created, test count, build status, server
routes consumed. Orchestrator audits before merging.
