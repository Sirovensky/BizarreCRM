# CLAUDE.md — iOS session memory

Persistent notes for any Claude session working in `ios/`. Read before writing code.

## iPhone vs iPad MUST look different

Non-negotiable. iPad takes advantage of the larger screen — don't ship an up-scaled iPhone layout.

- **iPhone**: `TabView` at root, vertical flows, bottom sheets (`.presentationDetents`), full-screen navigation, compact forms, `List` rows.
- **iPad**: `NavigationSplitView` sidebar + detail, multi-column `Grid`s, side-by-side editors, `Table` with sortable columns on data views, `.hoverEffect(.highlight)` on tappable rows, `.keyboardShortcut(...)` on primary actions, `.contextMenu` on list rows, `.textSelection(.enabled)` on IDs/emails.
- Gate on `Platform.isCompact` (defined in `Core/Platform.swift`). If a screen only has an iPhone layout, it's unfinished.
- Mac via "Designed for iPad" inherits the iPad layout — that's why iPad layouts must be first-class.

## Bundle + domain

- Bundle ID: `com.bizarrecrm`
- Domain: `bizarrecrm.com` (live, owned)
- App Group: `group.com.bizarrecrm`
- Associated domain: `app.bizarrecrm.com`

## API contract — match the server

- Envelope: **`{ success: Bool, data: T?, message: String? }`**. Not `{ error: {...} }`.
- Base URL is **dynamic per install**. User enters server URL at login → `APIClient.setBaseURL(...)`. Don't hardcode in xcconfig.
- Auth prefix: `/auth/...`, data prefix: `/<resource>`. The server already serves under `/api/v1/` — we append our paths to a base URL that already includes that. Confirm by reading the endpoint in `packages/server/src/routes/` before adding a new call.
- TLS: SPKI pinning supported via `PinnedURLSessionDelegate`, but with Let's Encrypt on `bizarrecrm.com` it's optional — leave empty pin set by default, pin only when we explicitly decide to.

## Wiring rule — no orphan UI

Every view, button, form field lands wired end-to-end before the next UI element is added. If a View doesn't call a ViewModel method that calls a real API/GRDB query, don't commit it. "Phase 0 placeholder" stubs are banned.

When adding a feature, mirror the Android structure in `packages/android/`:
- Screen → ViewModel → Repository → API/DAO
- Read the Kotlin first (`packages/android/app/src/main/java/.../ui/screens/...`) before writing Swift.

## Tech stack (locked)

- Swift 6.0 tools, Xcode 26, iOS 17 floor, iOS 26 design target
- SwiftUI + `@Observable`, Factory DI, GRDB + SQLCipher (passphrase in Keychain), Nuke for images, Starscream for WS
- Liquid Glass: use the `.brandGlass(...)` wrapper from `DesignSystem/GlassKit.swift`. Falls back to `.ultraThinMaterial` pre-26.

## Project generation

- Xcode project is generated from `project.yml` via `xcodegen generate`. **Never hand-edit `.xcodeproj`.**
- `DEVELOPMENT_TEAM` is deliberately NOT in `project.yml` — set it in Xcode UI per-user. CI uses `fastlane match`.
- When changing bundle ID / entitlements / Info.plist: edit the template files under `ios/App/Resources/` + `project.yml`, not the Xcode UI.

## When in doubt, read

- `docs/howtoIOS.md` — the full plan (rationale, risks, phases).
- `docs/howtoIOS-quickref.md` — cheat sheet.
- `packages/android/` — wiring reference.
- `packages/server/src/routes/` — ground truth for API shape.
