# ios/TODO.md — iOS follow-ups

Living checklist. Done items kept for reference with commit SHAs.

## Shipped this session (for context)

All committed to main between d6ab6dd and e809239.

Reads (list + detail where applicable):
- [x] Dashboard — `/reports/dashboard` + `/reports/needs-attention` KPI grid + attention card.
- [x] Tickets list with filter chips + search, detail with customer / devices / notes / history / totals.
- [x] Customers list with search, detail with parallel analytics / recent tickets / notes.
- [x] Inventory list with filter chips + search, detail with stock card / group prices / movements.
- [x] Invoices list with filter chips + search, detail with line items / totals / payments.
- [x] SMS threads list, thread view with bubbles + send composer (POST /sms/send).
- [x] Notifications list.
- [x] Appointments list.
- [x] Leads list.
- [x] Estimates list with is-expiring warning.
- [x] Expenses list with summary header.
- [x] Employees list.
- [x] Global Search across customers / tickets / inventory / invoices.

Creates:
- [x] Customer create (CustomerCreateView).
- [x] Expense create.
- [x] Appointment create.
- [x] Lead create.
- [x] Ticket create (minimal — single device, customer picker).

Platform:
- [x] Sign-out flow (Settings screen, clears Keychain + tokens).
- [x] 401 auto-logout — SessionEvents broadcasts revocation, RootView returns to Login.
- [x] iPad split-view balanced style + pinned sidebar width.
- [x] xcodegen + write-info-plist.sh so Info.plist is a build artifact.
- [x] URL construction hardening (no force-unwraps on user-influenced strings).
- [x] Self-hosted server URL accepts bare host, rejects non-http(s) schemes.

## Remaining write flows (parity gaps)

- [ ] **Ticket create — full feature parity**. Shipped a minimal version; still missing: pricing calculator, multiple devices, service/part lookup, pre-conditions checklist, status picker, photo attach, assignee picker.
- [ ] **Ticket edit** — status change, notes add, assignee change. All PATCH /tickets/:id or nested routes.
- [ ] **Invoice payment** — `POST /invoices/:id/payments` to record a payment.
- [ ] **Inventory create** — `POST /inventory` form.
- [x] **Estimate create** + **convert-to-ticket** — `POST /estimates/:id/convert`. (feat(§8): dcc7e2a)
- [ ] **Customer edit** — `PUT /customers/:id`.
- [ ] **Lead edit / convert-to-customer**.
- [ ] **Employee clock in/out**.
- [ ] **SMS: mark read / flag / pin** — need a PATCH helper on APIClient.

## POS / Hardware

- [ ] **POS checkout flow** (Pos/PosView is still Phase 0 placeholder). Cart model, catalog browse, BlockChyp SDK integration (CocoaPods — requires adding a Podfile), receipt printer abstraction.
- [ ] **Barcode scan** via `VisionKit.DataScannerViewController` — bind to Inventory create / lookup.
- [ ] **Photo capture** via `AVCaptureSession` — bind to Ticket photos.

## Reports / Notifications / System

- [ ] **Reports charts** — Swift Charts backing `/reports/revenue`, `/reports/expenses`, `/reports/inventory`. Currently the tab is a Phase 0 placeholder.
- [ ] **APNs registration** — register device token + POST `/api/v1/device-tokens`.
- [ ] **Notification tap → deep link** — open the relevant detail when the user taps a push.
- [ ] **Live Activities** — "Ticket in progress" on Lock Screen / Dynamic Island.
- [ ] **Widgets** — home-screen ticket count / revenue.
- [ ] **App Intents** — Create Ticket / Scan Barcode / Lookup Ticket for Shortcuts + Siri.

## Pagination + cache

All lists fetch first page (50 items) then stop. Users with more data don't see the rest.

- [ ] Add `loadMoreIfNeeded(rowId)` on every list — `.onAppear` on last row + `hasMore` from server `pagination.total_pages`.
- [ ] GRDB cache layer per repository so lists render instantly from disk + background-refresh from server.
- [ ] Stock movements + customer notes currently cap at a client-side slice — move to server-driven cursor.

## Auth refinements

- [ ] Token refresh on 401 with retry-of-original-request. Current behavior after session revocation is drop-back-to-login via SessionEvents — works but interrupts flow. Refresh-and-retry would keep users in-context through silent rotation.
- [ ] Persist last-logged-in username so re-auth is frictionless.
- [ ] Biometric re-login shortcut on the Login screen (LAContext + decrypt stored password).

## Console warnings to clean up (harmless but noisy)

- [ ] **Remove empty `UISceneDelegateClassName`** — `scripts/write-info-plist.sh` sets the key to `""`; Xcode logs "could not load class with name \"\"" twice at launch. For SwiftUI `@main` apps the key should be omitted.
- [ ] **`BrandMark` imageset is empty** — `RootView.LaunchView` references `Image("BrandMark")` but there's no PNG. Bundle a brand mark or swap to an SF Symbol.

## iPad layouts — polish

Current iPad shell is a 2-column NavigationSplitView (sidebar → detail pane hosting a whole NavigationStack). Lists push detail on top instead of using the right pane.

- [ ] Refactor Tickets / Customers / Invoices / Inventory / SMS into 3-column `NavigationSplitView` on iPad (sidebar + list column + detail column).
- [ ] Dashboard: 3-column KPI grid on wide screens.
- [ ] Detail views: cap content to ~720pt on iPad so nothing stretches across a 13" landscape.
- [ ] `.hoverEffect(.highlight)` on list rows.
- [ ] `.keyboardShortcut(_:)` for ⌘N / ⌘F / ⌘R.
- [ ] `.contextMenu` on list rows (Open, Copy ID, Archive, Delete).

## Visual polish

- [ ] **Liquid Glass aesthetic** — `.brandGlass` wrapper hits the `#available(iOS 26, *)` branch but needs on-device verification that the real refraction renders.
- [ ] **Dark-mode surface palette** tune-up — Login background orbs flat; re-tune blur + color for iOS 26 sampling.
- [ ] **Brand fonts** — `scripts/fetch-fonts.sh` downloads Inter / Barlow Condensed / JetBrains Mono; verify on device after running.
- [ ] **AppIcon** — ship a real 1024×1024 PNG.
- [ ] **Launch screen** — solid `SurfaceBase` color today; design a branded splash.
- [ ] **Accessibility** — VoiceOver labels, Dynamic Type audit, Reduce Transparency.
- [ ] **Motion spec** — apply `BrandMotion.*` uniformly with Reduce Motion fallback.

## See also

- `docs/howtoIOS.md` — full plan, risks, Liquid Glass rules.
- `TODO.md` (repo root) — cross-platform items including server changes like `SIGNUP-AUTO-LOGIN-TOKENS`.
