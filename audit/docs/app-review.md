# BizarreCRM iOS — App Review Checklist

**Target:** App Store submission (Phase 11 release gate)
**Bundle ID:** `com.bizarrecrm`
**Platform:** iOS 17+, iPadOS 17+, macOS via "Designed for iPad"

Run `bash ios/scripts/app-review-lint.sh` before submission. Fix all `[FAIL]` items.

---

## §1 Safety (App Store Review Guidelines §1)

| # | Item | Status | Evidence |
|---|---|---|---|
| 1.1 | No user-generated content moderation required — app is staff-only, not public UGC | - [ ] Confirmed | Staff-only: `ios/CLAUDE.md` — "BizarreCRM remains staff-only" |
| 1.2 | Child protection — N/A (no minor-facing surfaces; staff app requires employer-issued credentials) | - [ ] Confirmed | App description + review notes |
| 1.3 | No objectionable content (no adult, violent, gambling content) | - [ ] Confirmed | Content audit before submission |
| 1.4 | Demo account + server URL provided in review notes | - [ ] Pending | `ios/fastlane/metadata/review_information/` — `notes.txt` |

---

## §2 Performance (App Store Review Guidelines §2)

| # | Item | Status | Evidence |
|---|---|---|---|
| 2.1 | App launches within 10 seconds on supported hardware | - [ ] Tested | `docs/perf-baseline.json`; §29.1 cold launch < 1500ms on iPhone 13 |
| 2.2 | No crashes on supported OS versions (iOS 17, 18, 26) | - [ ] CI clean | Xcode Organizer crash rate < 1%; simulator matrix in CI |
| 2.3 | All metadata accurate — description, screenshots match current UI | - [ ] Pending | `ios/fastlane/metadata/` |
| 2.4 | No beta / placeholder UI, "Coming Soon" screens, or lorem ipsum | - [ ] Pending | UI audit before submission |
| 2.5 | No references to other platforms ("tap Back on Android…") | - [ ] Pending | Copy audit |
| 2.6 | Accurate age rating — 4+ (staff business app, no mature content) | - [ ] Pending | App Store Connect age rating section |

---

## §3 Business (App Store Review Guidelines §3)

| # | Item | Status | Evidence |
|---|---|---|---|
| 3.1 | In-App Purchase — N/A (memberships / subscriptions are server-side billing; no StoreKit purchase in app) | - [ ] Confirmed | `ios/ActionPlan.md` §38: "server-side billing avoids IAP" |
| 3.2 | Tip jar — N/A | - [ ] N/A | No tip UI |
| 3.3 | Advertising — N/A (no ad SDKs; sovereignty rule bans third-party SDKs) | - [ ] Confirmed | `ios/scripts/sdk-ban.sh` blocks ad SDK imports |
| 3.4 | Physical goods / services — payments processed server-side via BlockChyp; no in-app payment for digital goods requiring StoreKit | - [ ] Confirmed | §33 ActionPlan + §16 BlockChyp architecture |

---

## §4 Design (App Store Review Guidelines §4)

| # | Item | Status | Evidence |
|---|---|---|---|
| 4.1 | Minimum functionality — app is fully functional, not a thin web wrapper | - [ ] Confirmed | Native SwiftUI; `WKWebView` only for PDF preview + receipt |
| 4.2 | iPad support — distinct layout, not upscaled iPhone UI | - [ ] Tested | `Platform.isCompact` gates in all screens; snapshot tests cover both variants per §22 |
| 4.3 | Sign in with Apple — N/A (no third-party authentication; passkey via WebAuthn is first-party Apple API) | - [ ] Confirmed | `ios/CLAUDE.md` — passkey/WebAuthn is native Apple credential; no OAuth social login |
| 4.4 | Interface guidelines followed — uses standard iOS navigation, Dynamic Type, VoiceOver | - [ ] Pending | A11y CI audit clean (Phase 10 gate) |
| 4.5 | No spam / duplicate app submission | - [ ] Confirmed | Single binary; staging uses unlisted distribution via ABM |

---

## §5 Legal (App Store Review Guidelines §5)

| # | Item | Status | Evidence |
|---|---|---|---|
| 5.1 | Privacy Policy URL provided | - [ ] Pending | `https://bizarrecrm.com/privacy` — set in App Store Connect + `ios/ActionPlan.md` §33.7 |
| 5.2 | Terms of Service URL | - [ ] Pending | `https://bizarrecrm.com/terms` |
| 5.3 | Support URL | - [ ] Pending | `https://bizarrecrm.com/support` |
| 5.4 | Data collection accurately declared in App Privacy section | - [ ] Pending | See Privacy Manifest section below; mirrors `PrivacyInfo.xcprivacy` |
| 5.5 | Export compliance declaration — `ITSAppUsesNonExemptEncryption = false` | - [ ] Confirmed | `ios/App/Resources/Info.plist` key `ITSAppUsesNonExemptEncryption` = `false`; uses HTTPS (standard exempt) + CryptoKit for SQLCipher passphrase derivation (also exempt under US export regulations category EAR99) |
| 5.6 | CSAM reporting — N/A (no user-generated photo sharing to minors; staff-only app) | - [ ] N/A | |
| 5.7 | Location purpose string — `NSLocationWhenInUseUsageDescription` present; used only for clock-in geofence verify | - [ ] Confirmed | `ios/scripts/write-info-plist.sh` line: `NSLocationWhenInUseUsageDescription` — **NOTE: currently missing from write-info-plist.sh; must be added before submission** |
| 5.8 | All required purpose strings present (see lint script) | - [ ] Pending | Run `ios/scripts/app-review-lint.sh` |
| 5.9 | BlockChyp PCI certification reference in review notes | - [ ] Pending | `ios/fastlane/metadata/review_information/notes.txt` |
| 5.10 | No undisclosed private APIs | - [ ] Pending | Run `ios/scripts/app-review-lint.sh` private-API check |

---

## Purpose Strings Reference

All purpose strings must match the strings in `ios/scripts/write-info-plist.sh`.
Run `bash ios/scripts/app-review-lint.sh` to verify all are present.

| Key | Purpose | Current Value in write-info-plist.sh |
|---|---|---|
| `NSCameraUsageDescription` | Ticket photos, receipts, barcodes | "Scan barcodes and take photos of devices under repair." |
| `NSPhotoLibraryUsageDescription` | Attach existing photos to tickets/expenses | "Attach existing photos to repair tickets." |
| `NSPhotoLibraryAddUsageDescription` | Save receipts to photo library | "Save ticket photos to your library." |
| `NSMicrophoneUsageDescription` | Voice memos in SMS | **MISSING from write-info-plist.sh — must add** |
| `NSFaceIDUsageDescription` | Biometric authentication | "Authenticate to unlock Bizarre CRM." |
| `NSContactsUsageDescription` | Import customer contacts | "Import customer phone numbers from Contacts." |
| `NSBluetoothAlwaysUsageDescription` | Receipt printers, barcode scanners | "Connect to Bluetooth receipt printers and card readers." |
| `NSLocationWhenInUseUsageDescription` | Clock-in geofence verification | **MISSING from write-info-plist.sh — must add** |

> Add missing strings in `ios/scripts/write-info-plist.sh` then re-run `bash ios/scripts/gen.sh`.

---

## Privacy Manifest (`PrivacyInfo.xcprivacy`)

The file `ios/App/Resources/PrivacyInfo.xcprivacy` already exists and is checked into the repo. Contents are managed directly in Xcode's property list editor. Template / required structure documented below for reference.

### Required API Reason Declarations

| API Category | Reason Code | Justification |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Store non-sensitive user preferences (theme, sort order, last tab) |
| `NSPrivacyAccessedAPICategoryDiskSpace` | `E174.1` | Show "App storage" breakdown in Settings; pause cache writes when disk < 2 GB |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` | Read attachment modification time for staleness check in offline cache |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` | Compute uptime for RateLimiter token-bucket expiry; `CACurrentMediaTime()` relative clock |

All four are present in the current `PrivacyInfo.xcprivacy`. No changes needed.

### Collected Data Types

| Data Type | Linked to Identity | Tracking | Purpose |
|---|---|---|---|
| `NSPrivacyCollectedDataTypeEmailAddress` | Yes | No | Customer records (staff enters; tenant data) |
| `NSPrivacyCollectedDataTypeName` | Yes | No | Customer records |
| `NSPrivacyCollectedDataTypePhoneNumber` | Yes | No | Customer records |
| `NSPrivacyCollectedDataTypePhotosorVideos` | Yes | No | Ticket photos, receipt scans |
| `NSPrivacyCollectedDataTypeOtherUserContent` | Yes | No | Ticket notes, SMS messages (staff-to-customer) |

All five are declared in `PrivacyInfo.xcprivacy`. Tracking = `false`; tracking domains = empty.

### Third-Party SDK Manifests

Verify each SDK ships its own `PrivacyInfo.xcprivacy` bundled in its `.xcframework`:

- [ ] BlockChyp SDK — confirm privacy manifest present
- [ ] GRDB-SQLCipher — no network access; minimal API usage; manifest may be absent (acceptable if verified)
- [ ] Nuke — image loading; confirm manifest declares `NSPrivacyAccessedAPICategoryDiskSpace`
- [ ] Starscream — WebSocket only; no required-reason APIs expected

---

## Pre-Submission Checklist (final gate)

- [ ] `bash ios/scripts/app-review-lint.sh` exits 0
- [ ] All purpose strings in `write-info-plist.sh` match table above
- [ ] `ITSAppUsesNonExemptEncryption = false` in Info.plist
- [ ] App Store Connect — Privacy Policy URL, ToS URL, Support URL filled
- [ ] App Store Connect — App Privacy data types match `PrivacyInfo.xcprivacy`
- [ ] Review notes include: demo tenant URL, demo credentials, BlockChyp PCI cert reference, explanation of tenant-server architecture
- [ ] Screenshots: 6.7" iPhone, 6.5" iPhone, 13" iPad, 12.9" iPad, Mac (light + dark)
- [ ] Age rating: 4+
- [ ] Phased release: 7-day rollout enabled
- [ ] `fastlane release` lane tested end-to-end on staging binary
- [ ] `sdk-ban.sh` passes on release tag

---

*Associated lint script: `ios/scripts/app-review-lint.sh`*
*Threat model: `docs/security/threat-model.md`*
