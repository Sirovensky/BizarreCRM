# howtoIOS-quickref.md — AI Agent Quick Reference

Condensed pointer index to [howtoIOS.md](howtoIOS.md). Read the full doc for rationale; use this file to refresh fast while coding.

---

## Core decisions (memorize these)

| Thing | Answer | Full §  |
|---|---|---|
| Framework | **Native SwiftUI**. Not RN/Flutter/CMP/Catalyst-first/Capacitor | §2 |
| Min iOS | **iOS 17.0** | §3 |
| Design target | **iOS 26 (Liquid Glass)** with `.ultraThinMaterial` fallback on 17–25 | §3, §5 |
| Xcode / Swift | Xcode 26 / Swift 6 (approachable concurrency) | §3 |
| Architecture | **MVVM + `@Observable`**. Not TCA | §4.2 |
| DI | **Factory** | §4.3 |
| Networking | `URLSession` + async/await. **SPKI pinning required** | §10.1, §11 |
| WebSocket | **Starscream 4.x** (not URLSessionWebSocketTask) | §13 |
| Local DB | **GRDB + SQLCipher**. Not SwiftData | §19 |
| Images | **Nuke**. `AsyncImage` only for incidental | §10.4 |
| Charts | **Swift Charts** (Apple native) | §18 |
| Background | APNs silent push + foreground sync + `BGAppRefreshTask`. **No WorkManager equivalent** | §12 |
| Push | **APNs direct** | §17.1 |
| Auth | Biometric (`LAContext`) + PIN + 2FA TOTP | §14 |
| Barcode | **`VisionKit.DataScannerViewController`** (iOS 16+) | §15.2 |
| Printer | Star/Epson MFi SDKs. **Requires Apple MFi approval (3–6 week lag)** | §16.3 |
| Card reader | **BlockChyp iOS SDK** via CocoaPods | §16.2 |
| Distribution | **Unlisted App Distribution** via Apple Business Manager | §22.4 |
| Mac support | **"Designed for iPad"** on Apple Silicon. Not Catalyst (v2) | §25 |
| Deploy target includes Mac | macOS 14 Sonoma floor, M-series only, no Intel | §25.1 |

---

## API response envelope (read first)

Every endpoint returns `{ success, data, error }`. One unwrap.

```swift
struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: APIError?
}
```

Same trap as web codebase — payload lives directly in `.data`, no extra nesting. See `CLAUDE.md §1`.

---

## Critical gotchas (will bite you)

1. **Self-signed cert + ATS** — first TLS request fails silently. Pin SPKI in `URLSessionDelegate` (§11 + Appendix A2). Prefer migrating server to Let's Encrypt.
2. **Background sync ≠ WorkManager** — no 15-min cadence. Redesign around silent push + foreground + user-triggered. §12.
3. **`@Observable` is NOT drop-in for ObservableObject** — subtly different lifecycle. Don't mix. §4.2.
4. **Face ID crashes without `NSFaceIDUsageDescription`** in Info.plist. §14.3.
5. **Swipe-back gesture is a user contract** — never kill it with custom nav. §7.
6. **`List` not `LazyVStack`** for long tables — recycles cells. §21.2.
7. **Glass cannot sample glass** — wrap nearby glass elements in `GlassEffectContainer`. §5.5.
8. **Privacy manifest mandatory** — every 3rd-party SDK needs own `PrivacyInfo.xcprivacy`. §22.1.
9. **MFi Bluetooth printer approval ≠ App Review** — separate 3–6 week Apple process. Start early. §16.3.
10. **Tenant DBs are sacred** (CLAUDE memory) — never delete on iOS either; repair missing state.

---

## Liquid Glass rules

**USE** on: tab bars, toolbars, sheets, popovers, FABs, search field, badges over content.
**DON'T USE** on: list rows, cards, tables, content backgrounds, stacked glass.

Fallback wrapper (use this, not raw API):
```swift
view.brandGlass(.regular, in: .capsule)   // see Appendix A1
```

Variants: `.regular` (default), `.clear` (over media), `.identity` (conditional disable).
Buttons: `.buttonStyle(.glassProminent)` (primary) / `.buttonStyle(.glass)` (secondary).
Max ~6 glass elements on screen before GPU cost bites.

---

## Android → iOS API cheatsheet

| Android | iOS |
|---|---|
| Retrofit + OkHttp | `URLSession` + async/await |
| Gson | `Codable` (snake_case → camelCase, iso8601 dates) |
| Room + SQLCipher | GRDB + SQLCipher (SQL migrations 1:1) |
| DataStore | `UserDefaults` (prefs), Keychain (secrets) |
| Hilt / Koin | Factory |
| Coil / Glide | Nuke |
| WorkManager | `BGAppRefreshTask` + APNs silent push + foreground sync |
| Foreground service | **ActivityKit Live Activity** |
| androidx.biometric | `LAContext` / `LocalAuthentication` |
| ML Kit barcode | `VisionKit.DataScannerViewController` |
| CameraX | `AVCaptureSession` or `UIImagePickerController` |
| OkHttp WebSocket | Starscream |
| FCM | APNs + `UNUserNotificationCenter` |
| Intent filters | Info.plist `CFBundleURLSchemes` + Universal Links |
| `ACTION_SEND` | `ShareLink` / `UIActivityViewController` |
| QuickSettings tile | Control Center widget (iOS 18+) |
| Home-screen widget | WidgetKit |
| Material You | Semantic SwiftUI colors + Liquid Glass — do NOT port Material styling |

---

## Brand tokens

**Primary**: `#F28C42` orange. **Secondary**: `#4DB8C9` teal. **Tertiary**: `#D94F9B` magenta.
**Dark ramp**: `#121017 → #1A1722 → #241F2E → #332C3F`.
**Fonts**: Inter (body), Barlow Condensed (display/headline), JetBrains Mono (IDs/codes). All OFL.
**Spacing**: 8-pt grid. Tokens `xxs 2 / xs 4 / sm 8 / md 12 / base 16 / lg 24 / xl 32 / xxl 48`.
**Motion**: FAB 160ms, banner 200ms, sheet 340ms. Respect `accessibilityReduceMotion`.

---

## Nav model

- iPhone: `TabView` with 5 tabs (Dashboard, Tickets, Customers, POS, More) + search tab (iOS 26 role `.search`).
- iPad/Mac: `NavigationSplitView` sidebar + detail.
- Each tab = own `NavigationStack` with typed path enum.
- Deep link scheme: `bizarrecrm://` (matches Android).
- **Never** hijack iOS 26 search tab for a primary action — use floating glass FAB bottom-right instead.

---

## Screen port matrix (summary)

48 screens across 17 feature groups. Full mapping in §9. Key files:

- Auth (1): LoginFlowView
- Dashboard (1): DashboardView
- Tickets (4): List, Detail, Create (biggest: 2109 lines Android), DeviceEdit
- Customers (3), Inventory (5 incl. BarcodeScan), Invoices (2), Estimates (2)
- Leads & Appointments (5), POS (3: Pos, Checkout, TicketSuccess)
- Communications (2: SMS list + thread), Reports (1), Settings (3), Employees (3)
- Expenses (2), Search (1), Camera (1), Notifications (1)

---

## Auth flow

1. Email + password → `/api/v1/auth/login` → `requires_2fa` or tokens.
2. If 2FA → 6-digit TOTP → tokens.
3. First run → set 4–6 digit PIN (bcrypt, stored in Keychain).
4. Offer biometric enable.
5. Cold start → biometric prompt → fail → PIN → fail → full re-auth.
6. 401 on any call → refresh with refresh token → retry. Expired refresh → full re-auth.

Storage:
- Tokens: Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- PIN hash: Keychain
- DB passphrase: Keychain (32-byte random, generated on first run)

---

## Sync architecture

```
SyncManager observes:
  - NWPathMonitor (network up/down)
  - UIApplication.didBecomeActive
  - Silent APNs push { "aps": { "content-available": 1 }, data: {...} }
  - User "Sync now" button (wrap in BGContinuedProcessingTask on iOS 26)
  - WebSocket events (apply deltas to GRDB)
  - BGAppRefreshTask (opportunistic catch-up)
```

Offline mutations → append to `sync_queue` table → show optimistic UI → drain when back online.

Photo uploads → **background `URLSession`** (survives app exit).

Conflict resolution: server timestamp wins. Client never overrides `updated_at`.

---

## Keychain / UserDefaults split

**Keychain**: access token, refresh token, PIN hash, DB passphrase, 2FA backup codes, BlockChyp terminal auth.
**UserDefaults**: server URL, tenant ID, UI prefs, last-sync timestamp, selected payment method, paired printer name.

---

## Privacy manifest + Info.plist essentials

Required `NSUsageDescription` strings (crash without):
- `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription` + `NSPhotoLibraryAddUsageDescription`
- `NSFaceIDUsageDescription`
- `NSBluetoothAlwaysUsageDescription`
- `NSContactsUsageDescription`

Set `ITSAppUsesNonExemptEncryption = false` (HTTPS is exempt).

Required `UIBackgroundModes`: `remote-notification`, `processing`, `fetch`.

`PrivacyInfo.xcprivacy` — audit every SDK on bump (Starscream, GRDB, Nuke, Factory, KeychainAccess, BlockChyp, StarPRNT, Epson ePOS).

---

## Mac ("Designed for iPad") quick rules

Enable: Xcode target → Supported Destinations → **+ Mac (Designed for iPad)**. App Store Connect → availability → check Mac.

Runtime check: `ProcessInfo.processInfo.isiOSAppOnMac`.

**Breaks on Mac:**
- `DataScannerViewController` — barcode not supported. Feature-gate to manual entry.
- Bluetooth printer MFi — not supported. Gate to AirPrint.
- Haptics — no-op (gracefully degrades).

**Works on Mac:**
- Webcam via `AVCaptureSession`.
- Touch ID via `LAContext`.
- APNs, Live Activities, widgets, App Intents.
- BlockChyp (IP-based, not USB).

**UX:**
- Default layout = iPad split view (sidebar + detail).
- Add `.keyboardShortcut()`: ⌘N new ticket, ⌘F search, ⌘R sync, ⌘, settings.
- `.textSelection(.enabled)` on ticket IDs / invoice numbers / emails.
- `.hoverEffect(.highlight)` on tappable rows.
- `.fileExporter` instead of share sheet for invoice PDFs / CSVs.
- Window min size 800×600, default 1200×800.

**Cannot do on Designed-for-iPad:** add real menu-bar `CommandMenu` entries (system menu is stubs only). Revisit with Catalyst v2 if needed.

---

## Project layout

```
ios/
  BizarreCRM.xcodeproj
  App/                    # UIApplication bootstrap
  Packages/
    Core/                 # Models, utils, logging
    DesignSystem/         # Colors, type, GlassKit wrappers
    Networking/           # APIClient, pinning, endpoints
    Persistence/          # GRDB, migrations, DAOs
    Auth/ Tickets/ Customers/ Inventory/ Invoices/ …
    Sync/                 # Queue, WS client, manager
    Hardware/             # Printer, card reader adapters
  Widgets/                # Widget extension
  LiveActivities/         # ActivityKit extension
  Intents/                # App Intents extension
  Tests/
```

App Group: `group.com.bizarreelectronics.crm` for main app + extensions to share GRDB + Keychain.

---

## Critical code snippets (copy-paste ready)

**Glass wrapper** — see §Appendix A1 in full doc.
**Pinned URLSession delegate** — see §Appendix A2.
**API envelope** — see §Appendix A3.
**Observable VM template** — see §Appendix A4.

---

## Phase plan (tight)

| Phase | Weeks | Exit |
|---|---|---|
| 0. Foundations | 1–2 | Blank app calls `/health` over pinned TLS; CI uploads to TestFlight |
| 1. Auth | 3 | Real user logs in, lands on empty Dashboard |
| 2. Read-only shell | 4–5 | Staff browse data |
| 3. Core CRUD | 6–8 | End-to-end ticket+invoice+SMS without web app |
| 4. POS | 9–10 | Test terminal charges + receipt prints |
| 5. Polish | 11–12 | Designer sign-off; widgets, Live Activities, App Intents live |
| 6. App Store prep | 13–14 | Submitted on iPhone + iPad + Mac (Designed for iPad) |
| 7. v2 stretch | 15–18 | Live Activity push, EventKit, Spotlight, Control widgets |

Solo senior: 14–18 weeks total. With designer: 10–14 weeks.

---

## When in doubt, check...

- CLAUDE.md — repo-wide conventions (especially `{ success, data }` envelope).
- `bizarre-crm/TODO.md` — CROSS-PLATFORM section for items affecting both apps.
- `androidUITODO.md` — brand system source of truth.
- `memory/MEMORY.md` — persistent user preferences (phone format, POS layout, tier pricing, preserve tenant DBs).
- [howtoIOS.md](howtoIOS.md) full doc — for rationale and inline references.

---

## Anti-patterns (never do these)

- ❌ Rebuild an Android-looking UI with Material 3 shadows and raised buttons.
- ❌ Mock `ObservableObject` + `@Published` pattern in new code — use `@Observable`.
- ❌ `UUID()` as list row ID — use server ID (breaks `List` recycling).
- ❌ Custom top-left back arrow in `NavigationStack` — kills edge-swipe.
- ❌ `LazyVStack` for 900+ row lists — memory blows up on scrollback.
- ❌ Glass on content rows — violates HIG hierarchy rule.
- ❌ Tinting every glass button — collapses hierarchy.
- ❌ Inline TLS bypass (`NSAllowsArbitraryLoads`) — pin SPKI instead.
- ❌ Mock database in integration tests (CLAUDE memory: burned last quarter).
- ❌ Delete tenant DB to recover from missing state (CLAUDE memory: sacred).
- ❌ Commit `dist/` or packaged EXE/IPA (CLAUDE memory: build on deploy).

---

**End of quickref.** ~250 lines. If you need rationale, read the corresponding § in [howtoIOS.md](howtoIOS.md).
