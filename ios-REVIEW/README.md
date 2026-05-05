# BizarreCRM iOS

Native SwiftUI port of the Android Bizarre CRM. Targets iPhone, iPad, and Apple Silicon Macs via "Designed for iPad" (see `docs/howtoIOS.md` §25).

## Targets

- **Deployment target**: iOS 17.0 (iPad 17.0, macOS 14 Sonoma via iPad-on-Mac)
- **Design target**: iOS 26 (Liquid Glass), `.ultraThinMaterial` fallback on 17–25
- **Swift**: 6.0 with approachable concurrency
- **Xcode**: 26

## Layout

```
ios/
  App/                   UIApplication bootstrap, Info.plist, PrivacyInfo, Assets
  Packages/              Local Swift packages (one per feature + infra)
    Core/                Models, logging, platform helpers
    DesignSystem/        Colors, type, spacing, GlassKit wrapper, WaveDivider
    Networking/          APIClient, APIResponse envelope, SPKI pinning
    Persistence/         GRDB + SQLCipher, migrations, Keychain
    Auth/                Login → 2FA → PIN → biometric flow
    Sync/                SyncManager, WebSocket client, SyncQueue
    Hardware/            Printer + card reader adapters
    Dashboard/ Tickets/ Customers/ Inventory/ Invoices/ Estimates/
    Leads/ Appointments/ Expenses/ Pos/ Communications/ Reports/
    Settings/ Notifications/ Employees/ Camera/ Search/
  Widgets/               WidgetKit extension
  LiveActivities/        ActivityKit extension
  Intents/               App Intents extension
  Tests/                 App-level XCUITests
  fastlane/              Match + gym + pilot
  .github/workflows/     CI (macos-14, Xcode 26)
  project.yml            XcodeGen project spec
```

## Getting started (once Xcode 26 is installed)

```bash
# one-time
brew install xcodegen fastlane
bash ios/scripts/fetch-fonts.sh     # downloads Inter/Barlow/JetBrains Mono (OFL)
bash ios/scripts/gen.sh             # writes Info.plist + regenerates BizarreCRM.xcodeproj

# daily
open ios/BizarreCRM.xcodeproj

# whenever project.yml or Info.plist content needs to change
bash ios/scripts/gen.sh             # always via the script — never bare `xcodegen generate`
```

The brand fonts are OFL-licensed and fetched by `scripts/fetch-fonts.sh` so the binaries stay out of git. Re-run the script when a font version bumps.

Swift packages in `Packages/` resolve automatically via SPM. No CocoaPods at the project level; BlockChyp (Obj-C) is the only Podfile-scoped dep and lives under `Packages/Hardware`.

## Phase 0 exit criteria (§26)

- [ ] Blank app builds + launches in Simulator
- [ ] `/api/v1/health` call succeeds with pinned TLS
- [ ] CI uploads a signed build to TestFlight from `main`

See `docs/howtoIOS.md` + `docs/howtoIOS-quickref.md` for the full plan.
