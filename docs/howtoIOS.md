# howtoIOS.md — Bizarre Electronics CRM iOS Port Plan

> **Status**: Planning doc. Nothing built yet. Goal: port the existing Kotlin + Jetpack Compose Android app to iOS with native, 2025–2026-current design (Liquid Glass), while keeping the existing Node/Express/SQLite server unchanged.
>
> **Target audience**: engineer picking up the iOS build in a future sprint; reviewer evaluating whether to greenlight the scope; designer aligning on visual language.
>
> **Not in scope for this doc**: server changes, Android changes, business strategy. If an item requires both platforms (e.g. status-color palette migration) it is flagged `CROSS`.
>
> Last revised: 2026-04-16.

---

## Table of contents

1. [Executive summary & recommendation](#1-executive-summary--recommendation)
2. [Framework decision (why native SwiftUI)](#2-framework-decision-why-native-swiftui)
3. [Target OS, Swift, Xcode versions](#3-target-os-swift-xcode-versions)
4. [High-level architecture](#4-high-level-architecture)
5. [Liquid Glass design language primer](#5-liquid-glass-design-language-primer)
6. [Bizarre brand × Liquid Glass fusion](#6-bizarre-brand--liquid-glass-fusion)
7. [Typography, color, spacing, elevation, motion specs](#7-typography-color-spacing-elevation-motion-specs)
8. [Navigation model](#8-navigation-model)
9. [Screen-by-screen port matrix (48 screens)](#9-screen-by-screen-port-matrix-48-screens)
10. [Platform API mapping (Android → iOS)](#10-platform-api-mapping-android--ios)
11. [Self-signed HTTPS cert — the #1 porting risk](#11-self-signed-https-cert--the-1-porting-risk)
12. [Offline sync redesign (WorkManager has no iOS twin)](#12-offline-sync-redesign-workmanager-has-no-ios-twin)
13. [WebSocket strategy](#13-websocket-strategy)
14. [Auth: biometric + 2FA + PIN hybrid](#14-auth-biometric--2fa--pin-hybrid)
15. [Camera, photos, barcode/QR](#15-camera-photos-barcodeqr)
16. [POS flow + BlockChyp + Bluetooth printers](#16-pos-flow--blockchyp--bluetooth-printers)
17. [Notifications: APNs, Live Activities, widgets, Siri, App Intents](#17-notifications-apns-live-activities-widgets-siri-app-intents)
18. [Reports & charts](#18-reports--charts)
19. [Local database (GRDB vs SwiftData)](#19-local-database-grdb-vs-swiftdata)
20. [Accessibility (non-negotiable with Liquid Glass)](#20-accessibility-non-negotiable-with-liquid-glass)
21. [Performance budget & tactics](#21-performance-budget--tactics)
22. [Privacy manifest & App Store submission](#22-privacy-manifest--app-store-submission)
23. [Dev environment & CI on a Windows workstation](#23-dev-environment--ci-on-a-windows-workstation)
24. [Xcode project layout](#24-xcode-project-layout)
25. [Mac (Apple Silicon) support — "Designed for iPad"](#25-mac-apple-silicon-support--designed-for-ipad)
26. [Phased rollout plan](#26-phased-rollout-plan)
27. [Risks register](#27-risks-register)
28. [Testing strategy](#28-testing-strategy)
29. [Cross-platform parity items](#29-cross-platform-parity-items)
30. [Open questions](#30-open-questions)
31. [Reference library](#31-reference-library)

---

## 1. Executive summary & recommendation

**What we are doing.** Rewriting the Android Bizarre CRM in native SwiftUI (Swift 6, Xcode 26, iOS 26 target with iOS 17 floor), targeting iPhone, iPad, **and Apple Silicon Macs** (via "Designed for iPad" / "Mac (Apple Silicon)" — the iPad binary runs natively as an ARM64 app on any M-series Mac with zero extra code). Distributed via App Store (Unlisted App Distribution) and TestFlight. No shared-UI framework. The existing Node/Express server stays unchanged — we port a client only.

**Why native over cross-platform.** Liquid Glass is Apple's first full-system visual refresh since iOS 7 and it is the single best signal a user has that an app "feels native" in 2026. It requires real Metal shader sampling, not CSS `backdrop-filter`. Every cross-platform path (React Native, Flutter, Compose Multiplatform, Capacitor) either can't render real Liquid Glass or approximates it. Since the CRM is the store's daily driver on the counter and in the hand, the fidelity cost outweighs any code-share benefit — especially since the Android code is already Kotlin+Compose which does not share trivially with anything except Compose Multiplatform.

**What Liquid Glass is.** A meta-material that refracts and specular-highlights the content behind it in real time, using a Metal shader pipeline Apple exposes through SwiftUI's `.glassEffect()`, `GlassEffectContainer`, `.buttonStyle(.glass)` / `.glassProminent`. Unlike iOS 7–18 translucent materials, it is not a static blur — it lenses. It respects Reduce Transparency / Increase Contrast / Reduce Motion automatically.

**Biggest porting risk.** Self-signed HTTPS cert. ATS will block the first request. We solve with SPKI (public-key) pinning in a `URLSessionDelegate` OR we migrate the server to Let's Encrypt before shipping. Migrating to a real CA is strongly preferred. See §11.

**Second-biggest risk.** Background sync. iOS has no WorkManager equivalent. We replace periodic background sync with: APNs silent push + foreground sync on app launch + user-initiated "Sync now" + `BGAppRefreshTask` opportunistically. See §12.

**Estimated scope.** 48 screens, 15 API services, 13 local tables, WebSocket + offline queue, biometric+PIN hybrid, POS + card reader + Bluetooth printer, barcode scanner, photo capture, deep linking, widgets, Live Activities. Realistic greenfield estimate for a single senior iOS engineer: **10–14 weeks for v1 parity**, another 4–6 weeks for Liquid Glass polish, widgets, Live Activities, App Intents. Total ~4–5 months solo, or ~2–3 months with one senior + one designer.

**Deliverables for v1.** App Store-submittable build, TestFlight beta distribution, Unlisted listing for shop-by-shop onboarding, shared API contract with Android, phone + iPad + Apple Silicon Mac layouts (Mac runs the iPad build natively; see §25).

---

## 2. Framework decision (why native SwiftUI)

### 2.1 Paths evaluated

| Path | Dev cost | iOS 26 fidelity | Perf | Maintenance | App Store risk | Verdict |
|---|---|---|---|---|---|---|
| **Native Swift/SwiftUI** | Highest | Best — system chrome gets Liquid Glass on recompile | Best | Two codebases | Lowest | ✅ **Chosen** |
| KMP + SwiftUI for UI | High | Best (UI is SwiftUI) | Native | Shared business/network, UI split | Low | Considered, rejected — Android is already Kotlin/Compose; sharing ViewModels would require refactoring Android first. Worth revisiting in v2. |
| KMP + Compose Multiplatform | Mid | Uncanny-valley — no Liquid Glass, iOS polish lagging | Good (~9 MB weight) | Single UI codebase | Mid — reviewer won't reject but users notice | ❌ — defeats the "feels native" goal |
| React Native (New Arch) | Mid | Decent with `@callstack/liquid-glass` + Expo UI; not pixel-perfect | Decent | Ecosystem churn | Low | ❌ — web-skill leverage isn't worth the trade here |
| Flutter | Mid | Cupertino polished but Flutter renders its own pixels — cannot tap real Liquid Glass shaders | Impeller stable | Single codebase, big engine | Low-mid | ❌ — will read as "Flutter app," drifts further from native each iOS release |
| Capacitor wrap | Lowest | Worst — CSS `backdrop-filter` isn't the same material | Web-perf | Shared with web CRM | Higher — review can flag "just a website" | ❌ — rejected on fidelity grounds |

### 2.2 What we lose by going native

- **Duplicated business logic** — ticket mutation, validation, price math, sync queue semantics must be mirrored in Swift from the Kotlin sources of truth. Mitigation: since the server is authoritative for everything important, we write Swift logic that calls the same REST endpoints and mirrors the same models; there is very little "business logic" that lives on-device beyond caching, offline queueing, and form validation.
- **Duplicated designer effort** — every screen gets a SwiftUI implementation even if the Compose version exists. Mitigation: the brand system is portable (palette, type scale, motion spec), screens are relatively thin views over the same REST payloads.

### 2.3 What we gain

- Day-one Liquid Glass on every nav bar / tab bar / toolbar / sheet / popover / alert with zero custom code (recompile under Xcode 26).
- First-class Live Activities for ticket status ("Awaiting parts", "Ready for pickup") — huge UX win for a repair shop.
- SwiftUI `@Observable` + `NavigationStack` / `NavigationSplitView` + GRDB + async/await is the cleanest modern stack; less ceremony than the Android Hilt + Retrofit + Room + Compose setup.
- App Intents → Shortcuts + Siri + Spotlight + Action Button integration for "Create Ticket", "Scan Barcode", "Check Ticket #123" — trivial on iOS, painful cross-platform.
- iPad split view for free: ticket list on the left, ticket detail on the right. Counter-tablet UX without extra code.

---

## 3. Target OS, Swift, Xcode versions

| Thing | Version | Rationale |
|---|---|---|
| **Deployment target** | iOS 17.0 | Gives us `@Observable`, `.scrollTransition`, `.sensoryFeedback`, symbol effects, `ContentUnavailableView`. Anything older means we carry ObservableObject and spinner-based loading states. |
| **Primary design target** | iOS 26 | Liquid Glass, adaptive tab bars, toolbar morphing, `.glassEffect()` API. iOS 17–25 gets `.ultraThinMaterial` fallback. |
| **Xcode** | 26 (required for iOS 26 SDK) | Older Xcode won't link against Liquid Glass APIs. |
| **Swift** | 6.0 with strict concurrency enabled | `@MainActor`, Sendable, approachable-concurrency mode (6.2) for leaner migration. |
| **Minimum device** | iPhone XS / iPad (7th gen) — the A12 floor Apple set for iOS 17 | Older devices stay on Android. |
| **iPadOS** | Same iOS 17 floor, iPadOS 26 design target | `NavigationSplitView` first-class. |
| **macOS (Apple Silicon)** | macOS 14 Sonoma floor via "Designed for iPad" | The iPad binary runs natively as ARM64 on any M1/M2/M3/M4 Mac — zero extra code, zero extra target. Not Intel. See §25. |
| **Mac Catalyst** | Deferred to v2 | Recompiles iOS as AppKit-flavored; requires per-screen tuning. Skip for v1 — "Designed for iPad" gets us 90% of the value free. |
| **watchOS / visionOS** | Out of scope. |

**Why iOS 17 floor and not iOS 18 or 26:**
- iOS 17 covers ~95% of active iPhones in April 2026.
- Losing iOS 16 loses some pre-XS devices but we gain Observation, `.scrollTransition`, container-relative sizing, Phase/Keyframe animators, symbol effects — every one of which shows up on our screens. Not worth backporting.
- iOS 26 lock-in would exclude iPhone 11/12/13 owners still on 17/18. Those are common for shop customers.

**iOS version conditionals we will use:**
```swift
if #available(iOS 26.0, *) {
    view.glassEffect(.regular, in: .capsule)
} else {
    view.background(.ultraThinMaterial, in: .capsule)
}
```

---

## 4. High-level architecture

### 4.1 Layered stack

```
┌─────────────────────────────────────────────────────────────┐
│  SwiftUI Views (48 screens)                                 │
│  NavigationStack / NavigationSplitView / TabView            │
├─────────────────────────────────────────────────────────────┤
│  @Observable ViewModels (per feature)                       │
│  @MainActor, plain properties, Sendable models              │
├─────────────────────────────────────────────────────────────┤
│  Feature Services (Auth, Tickets, POS, Sync, WS, Printer…)  │
│  Stateless where possible, actor-isolated where not         │
├─────────────────────────────────────────────────────────────┤
│  Repository layer                                           │
│  Source of truth: server (REST + WebSocket). Cache: GRDB.   │
├─────────────────────────────────────────────────────────────┤
│  Infrastructure                                             │
│  APIClient (URLSession + async/await + pinning)             │
│  WebSocketClient (Starscream)                               │
│  Database (GRDB + SQLCipher)                                │
│  Keychain (tokens, PIN hash, DB passphrase)                 │
│  UserDefaults (prefs)                                       │
│  BGTaskScheduler (opportunistic refresh)                    │
│  APNs (UNUserNotificationCenter)                            │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Architectural pattern

**Vanilla MVVM with `@Observable`.** No TCA. Rationale:
- TCA's value shines with huge cross-screen state and exotic side-effect coordination. Our app is a fairly linear CRM: most screens are list → detail → edit flows against REST. `@Observable` + small service singletons covers 95% of what we need.
- TCA adds boilerplate; a solo engineer picking this up later should be able to ship a new screen in an hour, not a day.
- We revisit TCA if the POS tender flow or offline sync grows hair.

### 4.3 Dependency injection

**Factory** (by Michael Long) — lightweight, fast, Swift-native, no macros needed. Swinject is heavier and reflective; swift-dependencies is excellent but pairs best with TCA. Factory is closest in spirit to Hilt.

```swift
// App-level Container
extension Container {
    var apiClient: Factory<APIClient> { self { APIClientImpl() }.singleton }
    var ticketRepo: Factory<TicketRepository> { self { TicketRepositoryImpl() }.singleton }
    // …
}

// ViewModel consumes
@Observable final class TicketListViewModel {
    @ObservationIgnored @Injected(\.ticketRepo) private var repo
    var tickets: [Ticket] = []
    // …
}
```

### 4.4 Project structure (Swift packages)

Monorepo, one Xcode project with multiple local Swift packages to force module boundaries:

```
ios/
  BizarreCRM.xcodeproj
  App/                              # UIApplication bootstrap, app-delegate stuff
  Packages/
    Core/                           # Models, utilities, logging, date helpers
    DesignSystem/                   # Colors, type, components, GlassKit wrappers
    Networking/                     # APIClient, interceptors, endpoints
    Persistence/                    # GRDB setup, migrations, DAOs
    Auth/                           # Login, 2FA, PIN, biometric
    Tickets/                        # TicketsListView, TicketDetailView, …
    Customers/
    Inventory/
    Invoices/
    Estimates/
    Leads/
    Appointments/
    Expenses/
    Pos/
    Communications/                 # SMS list + thread
    Reports/
    Settings/
    Notifications/
    Dashboard/
    Sync/                           # SyncQueue, WebSocketClient, SyncManager
    Hardware/                       # Bluetooth printer, card reader adapters
  Widgets/                          # Widget extension target
  LiveActivities/                   # ActivityKit target
  Intents/                          # App Intents extension
  Tests/
```

This isolates build times (change one screen, don't rebuild the world) and keeps feature teams honest about imports.

---

## 5. Liquid Glass design language primer

### 5.1 What it is (technically)

Liquid Glass is Apple's system-wide material introduced in iOS 26 (WWDC 2025). Not a blur — a simulated optical glass with:
- **Real-time lensing / refraction** — bends light from the content behind it, like a lens.
- **Specular highlights** — shine reacts to device motion (accelerometer/gyro) and pointer location on iPad.
- **Adaptive tint** — samples surrounding content and tints accordingly.
- **Adaptive shadows** — contextual to placement.

It is implemented in Apple's Metal pipeline and exposed through SwiftUI's new API surface. It *is not* available as a shader you can replicate faithfully on other platforms; the best third-party approximations (Compose Multiplatform's KMPLiquidGlass, CSS glassmorphism) miss the lensing.

### 5.2 SwiftUI API surface (verified)

```swift
// Base modifier
view.glassEffect()                         // default .regular, capsule shape
view.glassEffect(.regular, in: .capsule)   // explicit form
view.glassEffect(.clear, in: .rect(cornerRadius: 16))

// Variants
Glass.regular                              // default; safe almost everywhere
Glass.clear                                // for media-rich backgrounds (photo/video)
Glass.identity                             // conditional disable without layout recalc

// Tint (sparingly — only CTAs)
view.glassEffect(.regular.tint(.orange))

// Interactive (scales, bounces, shimmers on press)
view.glassEffect(.regular.interactive())

// Shared sampling region (required when glass elements are near each other)
GlassEffectContainer(spacing: 40) {
    HStack {
        Image(systemName: "magnifyingglass").glassEffect()
        Image(systemName: "plus").glassEffect()
    }
}

// Morphing between glass elements
@Namespace var ns
view.glassEffectID("search", in: ns)
view.glassEffectUnion(id: "toolbar", namespace: ns)
view.glassEffectTransition(.matchedGeometry)

// Button styles
Button("Create") { }.buttonStyle(.glassProminent)  // primary action
Button("Cancel") { }.buttonStyle(.glass)           // secondary
```

### 5.3 Apple's three HIG principles for Liquid Glass

1. **Hierarchy** — glass belongs on the *navigation* layer (toolbars, tab bars, sheets, floating controls), not the content layer. Content rows/cards remain opaque.
2. **Harmony** — glass should feel like part of the system, not a decorative overlay. Prefer system controls; style sparingly.
3. **Consistency** — same material, same behavior, across the whole app.

### 5.4 Where to use it in our CRM

**USE** on:
- Main `TabView` bar (automatic on recompile under Xcode 26).
- Toolbars on every `NavigationStack` (automatic).
- Floating action buttons (e.g., Dashboard FAB for "Create Ticket / Quick Sale") — `.glassProminent`.
- Sheets (ticket create form, photo capture, inventory edit) — automatic.
- Search field (iOS 26 search tab) — automatic.
- Status badges on the POS cart (tint per payment state).
- Sticky "Offline" banner (glass container so ticket list behind is subtly visible).
- Dashboard KPI cards? **No.** Those are content — opaque.

**DON'T USE** on:
- Ticket list rows, customer rows, invoice line items, SMS bubbles — content, not navigation.
- Full-screen backgrounds (violates contrast).
- Dashboard charts or data tables.
- Stacked glass (one glass panel on top of another — Apple says "glass cannot sample glass"; renders weirdly).

### 5.5 Gotchas & bugs (as of iOS 26.0 / 26.1)

- Shape mismatch bug with `.interactive()` + non-default shapes — works around by wrapping in a container.
- `Menu` inside `GlassEffectContainer` breaks morphing animation.
- Performance regressions on iPhone 11–13 — community benchmarks show ~13% higher battery drain vs iOS 18 on iPhone 16 Pro Max in glass-heavy views. Rule: keep ~6 glass elements max on screen.
- `.glassEffect()` requires iOS 26.0+. Always gate.

### 5.6 Fallback strategy (iOS 17–25)

Build a thin wrapper so view code doesn't branch on every invocation:

```swift
// Packages/DesignSystem/GlassKit.swift
extension View {
    func brandGlass(_ variant: BrandGlass = .regular,
                    in shape: some Shape = Capsule()) -> some View {
        modifier(BrandGlassModifier(variant: variant, shape: shape))
    }
}

private struct BrandGlassModifier<S: Shape>: ViewModifier {
    let variant: BrandGlass
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(variant.systemGlass, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}
```

Now every screen says `.brandGlass()` and we centralize the #available.

---

## 6. Bizarre brand × Liquid Glass fusion

The Android app's brand wave (see `androidUITODO.md`) gives us:
- **Primary**: orange `#F28C42` (logo gradient top)
- **Secondary**: teal `#4DB8C9`
- **Tertiary**: magenta `#D94F9B`
- **Warm dark ramp**: `#121017 → #1A1722 → #241F2E → #332C3F`

### 6.1 How the brand meets Liquid Glass

Glass on iOS **tints from context**, so our orange primary doesn't disappear — it shines *through* glass panels. We expose brand color via `.tint(.bizarreOrange)` on the accent color and let SwiftUI cascade.

**Rule set:**
- `tintColor` (app-wide): `BizarreOrange`. This is what `.glassProminent` buttons will pick up.
- Primary CTA ("Create Ticket", "Save Invoice", "Charge Card"): `.buttonStyle(.glassProminent).tint(.bizarreOrange)`.
- Secondary actions ("Cancel", "Discard", "Filters"): `.buttonStyle(.glass)`.
- Destructive: `.buttonStyle(.glassProminent).tint(.red)` — red is a system semantic for destructive; do not override.
- Status pills (ticket status, lead status): solid filled pills, not glass. Glass on content reads wrong.
- Dashboard KPI cards: solid surfaces with the warm-dark ramp, brand orange accent bar on hover/press.

### 6.2 Dark mode first

The Android app's warm-dark ramp is the identity. iOS supports dark mode natively via `@Environment(\.colorScheme)`. We define both ramps but dark is canonical; light mode is a disciplined inversion, not an afterthought.

```swift
extension Color {
    static let bizarreSurfaceBase = Color("SurfaceBase")   // #121017 dark / #F6F4F1 light
    static let bizarreSurface1    = Color("Surface1")
    static let bizarreSurface2    = Color("Surface2")
    static let bizarreOutline     = Color("Outline")
    static let bizarreOrange      = Color("BrandOrange")
    static let bizarreTeal        = Color("BrandTeal")
    static let bizarreMagenta     = Color("BrandMagenta")
}
```

Asset catalog supplies per-appearance values.

### 6.3 Wave divider motif

The Android app has a sanctioned `WaveDivider` (low-contrast cubic curve under Login wordmark, above Dashboard greeting, above TicketSuccess checkmark). iOS version:

```swift
struct WaveDivider: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addCurve(
                to: CGPoint(x: size.width, y: size.height / 2),
                control1: CGPoint(x: size.width * 0.33, y: 0),
                control2: CGPoint(x: size.width * 0.66, y: size.height)
            )
            ctx.stroke(path, with: .linearGradient(
                .init(colors: [.bizarreOrange.opacity(0.6), .bizarreMagenta.opacity(0.3)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)
            ), lineWidth: 1.5)
        }
        .frame(height: 24)
    }
}
```

Only in the three sanctioned placements — anywhere else is brand abuse.

---

## 7. Typography, color, spacing, elevation, motion specs

### 7.1 Typography

iOS ships SF Pro (UI text) and SF Pro Rounded as system fonts. The Android stack uses Inter + Barlow Condensed + JetBrains Mono. **Decision**: we keep Inter/Barlow/JetBrainsMono for brand continuity across platforms (shop customers see identical tone in SMS receipts and app). Licenses: Inter and JetBrains Mono are OFL, Barlow is OFL — all redistributable, no App Store friction.

**Bundling fonts in iOS**:
1. Add `.ttf` files to target.
2. Declare `UIAppFonts` in Info.plist.
3. Load via `Font.custom("Inter-Regular", size: 17, relativeTo: .body)` — the `relativeTo:` lets Dynamic Type still scale it.

**Type scale (matches Android):**
| Role | Font | Size (pt) | Weight | Dynamic Type |
|---|---|---|---|---|
| displayLarge | Barlow Condensed | 57 | SemiBold | relativeTo: .largeTitle |
| displayMedium | Barlow Condensed | 45 | SemiBold | relativeTo: .largeTitle |
| headlineLarge | Barlow Condensed | 32 | SemiBold | relativeTo: .title |
| headlineMedium | Barlow Condensed | 28 | SemiBold | relativeTo: .title2 |
| titleLarge | Inter | 22 | SemiBold | relativeTo: .title3 |
| titleMedium | Inter | 16 | SemiBold | relativeTo: .headline |
| titleSmall | Inter | 14 | SemiBold | relativeTo: .subheadline |
| bodyLarge | Inter | 16 | Regular | relativeTo: .body |
| bodyMedium | Inter | 14 | Regular | relativeTo: .callout |
| labelLarge | Inter | 14 | Medium | relativeTo: .footnote |
| labelSmall | Inter | 12 | Medium | relativeTo: .caption |
| mono | JetBrainsMono | 14 | Regular | relativeTo: .body |

`BrandMono` (JetBrainsMono) reserved for: ticket IDs, SKUs, TOTP codes, backup codes, invoice numbers.

### 7.2 Color tokens

| Token | Dark | Light |
|---|---|---|
| SurfaceBase | #121017 | #F6F4F1 |
| Surface1 | #1A1722 | #EFEBE4 |
| Surface2 | #241F2E | #E3DDD2 |
| Outline | #332C3F | #CFC7B8 |
| OnSurface | #EFEAF5 | #1A1722 |
| OnSurfaceMuted | #9E95AB | #55505D |
| BrandOrange | #F28C42 | #F28C42 |
| BrandOrangeContainer | #3A2210 | #FFE3CC |
| OnBrandOrange | #2A1608 | #2A1608 |
| BrandTeal | #4DB8C9 | #2A7F8A |
| BrandMagenta | #D94F9B | #B32F76 |
| SuccessGreen | #34C47E | #1F7A4B |
| WarningAmber | #E8A33D | #B4761F |
| ErrorRose | #E2526C | #B8324B |
| GlassTintOnDark | rgba(255,255,255,0.08) | — |
| GlassTintOnLight | rgba(0,0,0,0.05) | — |

### 7.3 Spacing (8-pt grid)

`.xxs=2 .xs=4 .sm=8 .md=12 .base=16 .lg=24 .xl=32 .xxl=48 .xxxl=64`

Never inline magic numbers; only use tokens from `BrandSpacing`.

### 7.4 Corner radii

- `rect(cornerRadius: 12)` — cards, list rows, text fields.
- `rect(cornerRadius: 16)` — sheets, bottom-sheet headers.
- `rect(cornerRadius: 24)` — hero panels (login card, dashboard KPIs).
- `.capsule` — buttons, pills, badges.
- `.circle` — FAB, avatars.

Liquid Glass looks best on capsule and large-radius rounded rects. Sharp corners fight the material.

### 7.5 Elevation

Shadow spec (dark mode):
- `level0`: none.
- `level1`: `shadow(color: .black.opacity(0.4), radius: 4, y: 2)` — list cards.
- `level2`: `shadow(color: .black.opacity(0.5), radius: 8, y: 4)` — floating FAB, modals.
- `level3`: `shadow(color: .black.opacity(0.6), radius: 16, y: 8)` — alert center.

Glass surfaces get **subtler** shadows; the material already implies depth.

### 7.6 Motion spec

| Element | Duration | Curve |
|---|---|---|
| FAB expand/collapse | 160 ms | spring(response: 0.35, dampingFraction: 0.78) |
| OfflineBanner fade | 200 ms | easeInOut |
| SyncStatusBadge pulse | 600 ms | autoreverse, easeInOut |
| Sheet present | 340 ms | spring (system default) |
| List row insertion | 240 ms | `.smooth` |
| Ticket status change (matched geometry) | 450 ms | `.bouncy(duration: 0.45, extraBounce: 0.15)` |
| Barcode scan success (haptic + scale) | 180 ms | `.snappy(duration: 0.18)` |

Respect `@Environment(\.accessibilityReduceMotion)` — fall back to instant transitions.

---

## 8. Navigation model

### 8.1 Top-level

iPhone: `TabView` with 5 tabs + iOS 26 search tab (role `.search`):
1. Dashboard — `house`
2. Tickets — `wrench.and.screwdriver`
3. Customers — `person.2`
4. POS — `cart`
5. More — `square.grid.2x2`
6. Search — role: `.search` (iOS 26+) or 6th tab with glass floating search on older OS.

iPad: `NavigationSplitView` with sidebar listing the same destinations plus the "More" items inline (Inventory, Invoices, Leads, Appointments, Estimates, Expenses, Reports, Employees, Notifications, Settings).

### 8.2 NavigationStack strategy

One `NavigationStack` per tab, path bound to typed enum:

```swift
enum TicketRoute: Hashable {
    case detail(ticketId: Int64)
    case create
    case deviceEdit(ticketId: Int64, deviceId: Int64)
}

@Observable final class TicketNavigation {
    var path: [TicketRoute] = []
}

struct TicketsTab: View {
    @State private var nav = TicketNavigation()

    var body: some View {
        NavigationStack(path: $nav.path) {
            TicketListView()
                .navigationDestination(for: TicketRoute.self) { route in
                    switch route {
                    case .detail(let id):       TicketDetailView(id: id)
                    case .create:               TicketCreateView()
                    case .deviceEdit(let t, let d): TicketDeviceEditView(ticketId: t, deviceId: d)
                    }
                }
        }
    }
}
```

Deep link from a notification or widget → push onto the right tab's path.

### 8.3 Deep link scheme

- Custom scheme `bizarrecrm://` (matches Android).
- Universal Link over HTTPS later (requires `.well-known/apple-app-site-association` on the server; trivial for us).
- Routes:
  - `bizarrecrm://ticket/42`
  - `bizarrecrm://customer/117`
  - `bizarrecrm://sms/+15551234567`
  - `bizarrecrm://pos/new-repair`
  - `bizarrecrm://pos/quick-sale`

### 8.4 Modal strategy

- Create / edit forms → sheets with `.presentationDetents([.large])` and `.interactiveDismissDisabled(formIsDirty)`.
- Confirm delete / destructive → `.alert`.
- Bottom-sheet filters / sorts → sheets with `.presentationDetents([.medium, .large])` and `.presentationDragIndicator(.visible)`.
- Photo capture → `.fullScreenCover`.

### 8.5 Tab bar rules (avoiding the iOS 26 search-tab trap)

Apple's iOS 26 search tab pattern reads as an action button to many users. Our primary actions (Create Ticket, Quick Sale) **must not** hijack the search tab. Pattern:
- Search tab = global search only (matches the search icon's implied semantic).
- Primary actions live in a **floating glass FAB** anchored bottom-right, using `.buttonStyle(.glassProminent)` and a `GlassEffectContainer` wrapping the FAB + any expanded menu (Dashboard FAB pattern from Android).

### 8.6 Visibility: when to hide tab bar

Android uses an 18-clause `!startsWith(...)` chain (flagged as brittle in `androidUITODO.md`). iOS does it declaratively via `.toolbar(.hidden, for: .tabBar)` on child views, or via a `.tabBarHidden` trait we define. Rule: hide on Create/Edit sheets, photo capture, barcode scanner, auth. Show everywhere else.

---

## 9. Screen-by-screen port matrix (48 screens)

Each row: Android source → iOS SwiftUI file → notes on what changes.

### 9.1 Authentication

| Android | iOS file | Notes |
|---|---|---|
| LoginScreen.kt (1037 lines) | `Auth/LoginFlowView.swift` | Port the step machine (email/password → 2FA → PIN setup/verify) as an `@Observable LoginFlow` state machine. `AnimatedContent` → `.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))` between steps. TOTP input field = 6-digit SecureField with `.kerning(6)` in JetBrainsMono. Backup codes dialog = `.sheet` with `GlassEffectContainer`. |

### 9.2 Dashboard

| Android | iOS file | Notes |
|---|---|---|
| DashboardScreen.kt (470) | `Dashboard/DashboardView.swift` | KPI cards as plain `Grid`. Greeting uses `BrandDisplay` font. Expandable FAB uses matchedGeometry + `GlassEffectContainer`. Sync status badge sits top-right with `.symbolEffect(.variableColor.iterative.reversing, isActive: isSyncing)`. WaveDivider above greeting. |

### 9.3 Tickets (4 screens)

| Android | iOS file | Notes |
|---|---|---|
| TicketListScreen.kt (298) | `Tickets/TicketListView.swift` | `List` with `.swipeActions` (trailing-edge: Archive; leading-edge: Mark ready). Filter chips in a horizontal `ScrollView` with `.scrollTargetBehavior(.viewAligned)`. Status pill colors from the 5-hue discipline — not rainbow. |
| TicketDetailScreen.kt (949) | `Tickets/TicketDetailView.swift` | `ScrollView` with `LazyVStack`. Sections: customer card, device matrix (nested), notes, photos, activity log. Photos row as horizontal `ScrollView` with `.matchedGeometryEffect` so tapping a thumbnail zooms to full-screen via `NavigationTransition.zoom(sourceID:in:)`. |
| TicketCreateScreen.kt (2109) | `Tickets/TicketCreateView.swift` | Biggest file. Split into sub-views: `CustomerPickerSection`, `DeviceMatrixSection`, `DiagnosisSection`, `PricingSection`, `NotesSection`. Form uses `.focused($focus, equals: .customerName)` with explicit keyboard navigation via `.submitLabel(.next)`. |
| TicketDeviceEditScreen.kt (936) | `Tickets/TicketDeviceEditView.swift` | Per-device condition/parts/labor form. Parts list uses segmented picker for status (available/missing/ordered/received). |

### 9.4 Customers (3 screens)

| Android | iOS file | Notes |
|---|---|---|
| CustomerListScreen.kt (274) | `Customers/CustomerListView.swift` | `List` with contact-compatible row layout. `.swipeActions`: call (trailing), message (trailing), favorite (leading). |
| CustomerDetailScreen.kt (617) | `Customers/CustomerDetailView.swift` | Tabbed (`Picker(.segmented)`): Info / Tickets / Invoices / SMS. Phone field tappable → `URL("tel:…")`. |
| CustomerCreateScreen.kt (306) | `Customers/CustomerCreateView.swift` | Phone field auto-formats to `+1 (XXX)-XXX-XXXX` — memory item. Use `TextField` + formatter extension. |

### 9.5 Inventory (5 screens)

| Android | iOS file | Notes |
|---|---|---|
| InventoryListScreen.kt (359) | `Inventory/InventoryListView.swift` | `List` with low-stock warning badge (amber pill, rule: `stock_qty <= reorder_level`). |
| InventoryDetailScreen.kt (635) | `Inventory/InventoryDetailView.swift` | Price + cost shown as cents → rendered via `NumberFormatter.currency`. |
| InventoryCreateScreen.kt (387) | `Inventory/InventoryCreateView.swift` | Scan UPC → navigate to scanner → return barcode → lookup via catalog API → prefill. |
| InventoryEditScreen.kt (298) | `Inventory/InventoryEditView.swift` | — |
| BarcodeScanScreen.kt (118) | `Inventory/BarcodeScanView.swift` | `DataScannerViewController` via `UIViewControllerRepresentable`. Continuous recognition, haptic on first unique hit. See §15. |

### 9.6 Invoices (2)

| Android | iOS file | Notes |
|---|---|---|
| InvoiceListScreen.kt (310) | `Invoices/InvoiceListView.swift` | — |
| InvoiceDetailScreen.kt (630) | `Invoices/InvoiceDetailView.swift` | Line items as `Table` (iPad) or `List` (iPhone). Print → Bluetooth printer service (§16). Email → `MFMailComposeViewController`. |

### 9.7 Estimates (2)

| Android | iOS file | Notes |
|---|---|---|
| EstimateListScreen.kt | `Estimates/EstimateListView.swift` | — |
| EstimateDetailScreen.kt | `Estimates/EstimateDetailView.swift` | Convert-to-ticket = primary CTA `.glassProminent`. Animated transition from Estimate sheet → TicketDetail push. |

### 9.8 Leads & Appointments (5)

| Android | iOS file | Notes |
|---|---|---|
| LeadListScreen.kt (359) | `Leads/LeadListView.swift` | Flagged rainbow palette on Android — migrate to 5-hue (CROSS). |
| LeadDetailScreen.kt (575) | `Leads/LeadDetailView.swift` | — |
| LeadCreateScreen.kt (319) | `Leads/LeadCreateView.swift` | — |
| AppointmentListScreen.kt (480) | `Appointments/AppointmentListView.swift` | Date pills as `HStack` of capsules; today highlighted with brand orange. Optionally wire to Calendar.app via EventKit (v2). |
| AppointmentCreateScreen.kt (542) | `Appointments/AppointmentCreateView.swift` | `DatePicker(.graphical)` for date, `.wheel` or `.compact` for time. |

### 9.9 POS (3)

| Android | iOS file | Notes |
|---|---|---|
| PosScreen.kt (261) | `Pos/PosView.swift` | Per memory: 40/60 cart-to-content split, NOT 30/70 with auto-collapse. iPad uses `NavigationSplitView.columnVisibility` with `.prominentDetail` on the cart. iPhone uses a pinned bottom sheet at `.presentationDetents([.fraction(0.4), .large])`. |
| CheckoutScreen.kt (517) | `Pos/CheckoutView.swift` | Payment methods as segmented picker. BlockChyp integration (§16). |
| TicketSuccessScreen.kt (114) | `Pos/TicketSuccessView.swift` | Hero checkmark with `.symbolEffect(.bounce)`, WaveDivider above, ticket ID in JetBrainsMono. |

### 9.10 Communications (2)

| Android | iOS file | Notes |
|---|---|---|
| SmsListScreen.kt (349) | `Communications/SmsListView.swift` | Unread badge = `.badge(count)`. |
| SmsThreadScreen.kt (390) | `Communications/SmsThreadView.swift` | Message bubbles: inbound left-aligned `.bizarreSurface2`, outbound right-aligned `.bizarreOrangeContainer`. Composer uses `.keyboardType(.default)` with `.submitLabel(.send)`. Real-time via WebSocket subscription (§13). Character counter in JetBrainsMono. |

### 9.11 Reports (1)

| Android | iOS file | Notes |
|---|---|---|
| ReportsScreen.kt (888) | `Reports/ReportsView.swift` | Tabbed via `Picker(.segmented)`: Revenue, Expenses, Inventory, Customer. Charts via **Swift Charts** (Apple native, iOS 16+). Color-code with brand palette, not tailwind hex (CROSS issue resolved here). |

### 9.12 Settings (3)

| Android | iOS file | Notes |
|---|---|---|
| SettingsScreen.kt (317) | `Settings/SettingsView.swift` | Grouped `List` (`listStyle(.insetGrouped)`). Sections: Server, User, Sync, Preferences, About. Biometric toggle (`Toggle(isOn:)`). Sign-out as destructive row. |
| ProfileScreen.kt (558) | `Settings/ProfileView.swift` | Avatar hero with `.onTapGesture` → photo picker via `PhotosPicker`. Edit name/email/phone. Change password + PIN flows. |
| SmsTemplatesScreen.kt (246) | `Settings/SmsTemplatesView.swift` | `List` with add/edit/delete swipe actions. |

### 9.13 Employees (3)

| Android | iOS file | Notes |
|---|---|---|
| EmployeeListScreen.kt (262) | `Employees/EmployeeListView.swift` | — |
| EmployeeCreateScreen.kt | `Employees/EmployeeCreateView.swift` | — |
| ClockInOutScreen.kt (291) | `Employees/ClockInOutView.swift` | PIN pad = `LazyVGrid` of 3×4 buttons with haptic on each tap. Hero clock icon with `.symbolEffect(.pulse)`. |

### 9.14 Expenses (2)

| Android | iOS file | Notes |
|---|---|---|
| ExpenseListScreen.kt (369) | `Expenses/ExpenseListView.swift` | — |
| ExpenseCreateScreen.kt (237) | `Expenses/ExpenseCreateView.swift` | — |

### 9.15 Search (1)

| Android | iOS file | Notes |
|---|---|---|
| GlobalSearchScreen.kt (386) | `Search/GlobalSearchView.swift` | On iOS 26 this is the search tab (role: `.search`) — morphs tab into search field. On older OS, `.searchable` on root ScrollView. Results grouped by section (Tickets / Customers / Inventory / Invoices). Use Core Spotlight to also surface in system search (v2). |

### 9.16 Camera (1)

| Android | iOS file | Notes |
|---|---|---|
| PhotoCaptureScreen.kt (298) | `Camera/PhotoCaptureView.swift` | `UIImagePickerController` (simple) or `AVCaptureSession` (custom UI). Pre/post filter chips as segmented picker. Gallery fallback via `PhotosPicker`. |

### 9.17 Notifications (1)

| Android | iOS file | Notes |
|---|---|---|
| NotificationListScreen.kt (244) | `Notifications/NotificationListView.swift` | Unread badges, tap routes via deep link. |

**Total: 48 screens** in 17 feature groups.

---

## 10. Platform API mapping (Android → iOS)

### 10.1 Networking

| Android | iOS |
|---|---|
| Retrofit interface + OkHttp + AuthInterceptor | Custom `APIClient` protocol, `URLSession` with async/await, token attached by a request builder |
| Gson | `Codable` with `JSONDecoder` (configure `.keyDecodingStrategy = .convertFromSnakeCase`, `.dateDecodingStrategy = .iso8601`) |
| OkHttp interceptors | `URLSessionDelegate` for auth challenges; request builder closure for headers |
| ApiResponse<T> wrapper | Swift mirror: `struct APIResponse<T: Decodable>: Decodable { let success: Bool; let data: T; let error: APIError? }` |
| ReachabilityReportingInterceptor | `NWPathMonitor` + custom `ReachabilityService` (see §12) |

Example endpoint:

```swift
actor APIClient {
    private let session: URLSession
    private let baseURL: URL
    private var authToken: String?

    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("ios", forHTTPHeaderField: "X-Origin")
        let (data, resp) = try await session.data(for: req)
        try validate(resp)
        let envelope = try decoder.decode(APIResponse<T>.self, from: data)
        guard envelope.success, let payload = envelope.data else {
            throw envelope.error ?? APIError.unknown
        }
        return payload
    }
}
```

**Critical**: remember the `{ success, data }` envelope — same trap as web (see CLAUDE.md §1). Write `APIResponse<T>` generic once, never unwrap manually at call sites.

### 10.2 Local storage

| Android | iOS |
|---|---|
| Room 2.7.0 + SQLCipher 4.6.1 | **GRDB 6+ with SQLCipher** — same database engine, same mental model, same SQL migrations. |
| DataStore Preferences | `UserDefaults` for non-sensitive; `Keychain` (`SecItemAdd/Copy/Update/Delete`) for tokens/PIN hash/DB passphrase. |

Migration files — port them 1:1. See §19.

### 10.3 DI

| Android | iOS |
|---|---|
| Hilt @Singleton / @Module / @Inject | Factory `@Injected(\.service)` |
| @HiltAndroidApp | `ContainerBootstrap.register()` called from `App.init` |

### 10.4 Image loading

| Android | iOS |
|---|---|
| Coil 3.1.0 | **Nuke 12** — best-in-class disk+memory cache, prefetching, priority system. `AsyncImage` only for incidental images. |

### 10.5 Background work

| Android | iOS |
|---|---|
| WorkManager periodic 15 min | `BGAppRefreshTask` (opportunistic; system decides) + silent APNs push + foreground sync. No guaranteed 15-min cadence on iOS — design around push + pull. |
| Foreground service (RepairInProgressService) | **Live Activity** via ActivityKit — the correct iOS idiom. Ticket-in-progress shows on Lock Screen and Dynamic Island. |

### 10.6 Biometric

| Android | iOS |
|---|---|
| androidx.biometric | `LocalAuthentication` / `LAContext` |
| `BiometricPrompt` | `context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` |
| BIOMETRIC_STRONG OR DEVICE_CREDENTIAL fallback | Same pattern via `.deviceOwnerAuthentication` (falls back to passcode) |

Info.plist: `NSFaceIDUsageDescription` — "Authenticate to unlock Bizarre CRM quickly."

### 10.7 Barcode/QR

| Android | iOS |
|---|---|
| ML Kit 17.3.0 | `VisionKit.DataScannerViewController` (iOS 16+) — simpler, faster, natively continuous, system-blessed. Also supports QR + text recognition out of the box. |

### 10.8 Camera

| Android | iOS |
|---|---|
| CameraX 1.4.1 | `AVFoundation` (custom) or `UIImagePickerController` (standard). For our pre/post filter chips, custom `AVCaptureSession` wrapped in `UIViewControllerRepresentable`. |

### 10.9 WebSocket

| Android | iOS |
|---|---|
| OkHttp WebSocket (raw) | **Starscream 4.x** — battle-tested, handles TLS pinning, reconnection, ping/pong cleanly. `URLSessionWebSocketTask` has a long bug tail (dropped messages on app backgrounding, crashes with certain self-signed certs). |

### 10.10 Push

| Android | iOS |
|---|---|
| FCM 33.8.0 | **APNs** directly (preferred) or FCM-on-APNs. APNs tokens are registered via `UNUserNotificationCenter` + `UIApplication.registerForRemoteNotifications`. Server needs APNs p8 key + team ID + key ID in env. |

### 10.11 Shared preferences / secrets

| Android | iOS |
|---|---|
| EncryptedSharedPreferences | `Keychain` (via `KeychainAccess` library or raw `SecItem…` API) |
| SharedPreferences | `UserDefaults` |

### 10.12 Deep linking

| Android | iOS |
|---|---|
| Intent filters in manifest | Info.plist `CFBundleURLSchemes = ["bizarrecrm"]`. iOS 14+ also supports universal links via `.well-known/apple-app-site-association`. |

### 10.13 Sharing / printing

| Android | iOS |
|---|---|
| `Intent.ACTION_SEND` | `ShareLink` (SwiftUI) / `UIActivityViewController` |
| Print via vendor SDK | Vendor SDK (Star / Epson) — see §16 |

### 10.14 Quick settings tile / widget

| Android | iOS |
|---|---|
| QuickTicketTileService (Android 7+ tile) | iOS 18+ **Control widgets** (Control Center extensions) — a new quick-action surface. Expose "Create Ticket", "Scan Barcode", "New Customer". |
| Home-screen widget | WidgetKit — ticket count, sync status, today's appointments. iOS 18 interactive widgets. |

---

## 11. Self-signed HTTPS cert — the #1 porting risk

### 11.1 The problem

Your `packages/server/certs/server.cert` is a self-signed 10-year cert. iOS App Transport Security (ATS) rejects self-signed certs at the URLLoading layer — your `URLSession.data(for:)` call fails with `NSURLErrorServerCertificateUntrusted` before any code of yours runs.

### 11.2 Two solutions (pick one)

**Option A — move to Let's Encrypt (preferred, do this first).**
- Let's Encrypt issues free DV certs via ACME; automated renewal every 90 days via `certbot` or `acme.sh`.
- The shop's server is reachable on the public internet — this is table stakes for the Android app's WAN access too.
- iOS trusts Let's Encrypt's root out of the box. No code changes, no ATS exceptions, no pinning maintenance.
- **Downside**: must have a DNS-resolvable domain (you already do, since Android connects remotely).
- **Blocker**: per-tenant provisioning (memory: tenant DBs sacred). Each shop's subdomain needs a cert. `acme.sh` + wildcard DNS-01 challenge solves this with one cert across all `*.bizarreelectronics.com` tenants.

**Option B — SPKI (public-key) pinning in the app.**
- Keep self-signed cert; bundle its SPKI hash inside the app.
- Implement `URLSessionDelegate.urlSession(_:didReceive:completionHandler:)`:
  ```swift
  func urlSession(_ session: URLSession,
                  didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
      guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust,
            SecTrustEvaluateWithError(trust, nil),
            let cert = SecTrustCopyCertificateChain(trust).flatMap({ ($0 as NSArray).firstObject as! SecCertificate? }),
            let key = SecCertificateCopyKey(cert),
            let data = SecKeyCopyExternalRepresentation(key, nil) as Data?,
            pinnedSPKIHashes.contains(sha256(data))
      else {
          completionHandler(.cancelAuthenticationChallenge, nil)
          return
      }
      completionHandler(.useCredential, URLCredential(trust: trust))
  }
  ```
- **Pin the public key, not the cert** — you can re-issue the cert with the same key and not need to ship a new app build.
- **Maintenance cost**: document the key-rotation procedure. If the key is ever rotated, every existing install must update before the server key changes, or clients are bricked. Plan for a two-phase rotation: (1) ship an app update that accepts two SPKIs (old + new), (2) swap server cert, (3) ship next app update that drops old SPKI.
- **Info.plist**: also set `NSAppTransportSecurity.NSExceptionDomains.<your-host>.NSExceptionRequiresForwardSecrecy = false` if your Node TLS config doesn't support PFS (check your cipher list). Prefer: enable PFS on the server so you don't need this exception.

### 11.3 Recommendation

**Do both**: migrate to Let's Encrypt (reliable day-to-day), *and* implement SPKI pinning (defense-in-depth against MITM). The code is the same either way — pinning stays useful even on CA-signed certs.

### 11.4 App Store review note

A self-signed cert with an `NSExceptionDomains` entry will draw a reviewer question ("Why are you bypassing ATS?"). Be ready to answer: "We pin the public key of our private server." This is acceptable; arbitrary loads would not be.

---

## 12. Offline sync redesign (WorkManager has no iOS twin)

Android's `SyncWorker` with a 15-minute periodic cadence simply does not exist on iOS. The whole sync design must change.

### 12.1 iOS background-work primitives

| Primitive | Trigger | Time budget | Use for |
|---|---|---|---|
| `BGAppRefreshTask` | System decides (opportunistic; often once per 24h for rarely-used apps) | 30 s | Best-effort periodic refresh |
| `BGProcessingTask` | System decides, requires device idle/charging | A few minutes | Large batch work (image uploads) |
| `BGContinuedProcessingTask` (iOS 26) | User-initiated long task with system progress UI | Minutes | "Sync now" button that survives app backgrounding |
| Background `URLSession` | App upload/download continues after app exit | Per-request, can be hours | File uploads of ticket photos |
| Silent APNs push (`content-available: 1`) | Server triggers | ~30 s | Near-real-time delta: server nudges device when data changed |

### 12.2 Sync architecture

```
┌─────────────────────────────────────────────────────────────┐
│  SyncManager                                                │
│  - Observes NWPathMonitor (network up/down)                 │
│  - Observes UIApplication.didBecomeActive                   │
│  - Observes silent APNs pushes                              │
│  - Observes user-triggered "Sync now"                       │
│  - Drains SyncQueue (GRDB table) on each trigger            │
│  - Applies WebSocket deltas as they arrive                  │
└─────────────────────────────────────────────────────────────┘
```

**Server contribution (CROSS, small):**
- Add a silent APNs push whenever a ticket/invoice/SMS changes; payload = `{ "type": "ticket.updated", "id": 42, "aps": { "content-available": 1 } }`.
- Add a `/api/v1/sync/since?ts=<last-seen>` endpoint that returns all changed rows since timestamp. Not strictly new — the Android sync already pulls deltas — but formalize the contract.

**Client behavior:**
1. **Cold start / foreground** → `SyncManager.pullSince(lastSeen)` + drain `SyncQueue`.
2. **Silent push received** → `SyncManager.pullSpecific(kind, id)`.
3. **User taps "Sync now"** → `SyncManager.fullPull()` wrapped in `BGContinuedProcessingTask` so it survives backgrounding.
4. **Offline mutation** → append to `SyncQueue`, show in UI immediately (optimistic), retry when back online.
5. **WebSocket connected** → receive live deltas, apply to GRDB, trigger `@Observable` updates.
6. **Opportunistic refresh (`BGAppRefreshTask`)** → only if WebSocket not connected in last hour; catches up stragglers.

**Conflict resolution:** last-writer-wins by server timestamp (same as Android). Client never overrides `updated_at` from server.

**Offline UX:** `OfflineBanner` appears when `NWPathMonitor.currentPath.status != .satisfied` for ≥2s. Sync badge shows pending-queue size; tap opens a debug sheet listing pending ops.

### 12.3 Photo uploads specifically

Ticket photos are often 3–5 MB. Do **not** send them in a foreground request inside the ticket-create POST. Instead:
1. Create the ticket → get `ticket_id`.
2. For each photo: queue a background `URLSession` upload task (`URLSessionConfiguration.background(withIdentifier:)`) pointing at `/api/v1/tickets/:id/photos`.
3. Show upload progress in the ticket detail photo row.
4. On success, server emits WebSocket `ticket.photo.added` → UI refreshes.

Background URLSession survives app termination, is battery-aware, and Apple encourages it.

---

## 13. WebSocket strategy

### 13.1 Library choice: Starscream

`URLSessionWebSocketTask` is tempting (zero dependencies) but has a long bug tail: dropped messages when the app backgrounds, crashes under some self-signed-cert TLS handshakes, no built-in reconnection, no built-in ping/pong.

Starscream 4.x:
- Reliable in production (used widely).
- Supports TLS pinning (we can reuse §11's pinned SPKI).
- Handles ping/pong heartbeats.
- Backgrounding: we suspend WS on app background, resume on foreground — iOS kills long-lived sockets in background anyway.

### 13.2 Event model

```swift
enum WSEvent: Decodable {
    case ticketCreated(TicketDTO)
    case ticketUpdated(TicketDTO)
    case smsReceived(SmsDTO)
    case invoicePaid(InvoiceDTO)
    case notification(NotificationDTO)
    case unknown
}

@Observable final class WebSocketClient {
    private(set) var connectionState: ConnectionState = .disconnected
    private let socket: WebSocket
    let eventStream: AsyncStream<WSEvent>
    // Starscream delegate → AsyncStream continuation
}
```

### 13.3 Reconnection

Exponential backoff: 1s, 2s, 4s, 8s, 16s, cap at 30s. Reset on successful handshake. Same semantics as Android.

### 13.4 Integration with repositories

Each repository subscribes to the relevant `WSEvent` kinds:

```swift
final class TicketRepository {
    init(ws: WebSocketClient) {
        Task {
            for await event in ws.eventStream {
                switch event {
                case .ticketCreated(let dto): try await cache(dto)
                case .ticketUpdated(let dto): try await cache(dto)
                default: break
                }
            }
        }
    }
}
```

Writes to GRDB are observed by `@Observable` view models via GRDB's `ValueObservation`.

---

## 14. Auth: biometric + 2FA + PIN hybrid

### 14.1 Flow

First login:
1. Email + password → server returns `requires_2fa: true` + challenge.
2. User enters 6-digit TOTP → server returns JWT pair (access + refresh).
3. App asks user to set a 4-6 digit PIN (on-device unlock).
4. App asks user to enable biometric unlock (optional).

Returning user:
- Cold start → biometric prompt (if enabled) → decrypt tokens → proceed.
- Biometric fail / cancel → PIN prompt.
- PIN fail → re-auth with password + 2FA.
- Token refresh on 401 → refresh with refresh token → retry.
- Refresh expired → back to full re-auth.

### 14.2 Storage

| Secret | Where |
|---|---|
| Access token (JWT) | Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| Refresh token | Keychain, same accessibility |
| PIN hash (bcrypt or Argon2id, ≥10 rounds) | Keychain |
| DB passphrase (for GRDB+SQLCipher) | Keychain |
| 2FA backup codes | Keychain (encrypted string array) |

### 14.3 Biometric gate

```swift
func tryBiometricUnlock() async throws -> Bool {
    let ctx = LAContext()
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
        return false // no biometric enrolled / hardware
    }
    return try await ctx.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: "Unlock Bizarre CRM"
    )
}
```

Info.plist: `NSFaceIDUsageDescription` — required, or the app crashes on Face ID devices.

### 14.4 PIN pad UI

`LazyVGrid` 3 columns × 4 rows. Each button `.buttonStyle(.glass)` wrapped in `GlassEffectContainer` so they share sampling. Haptic `.sensoryFeedback(.selection, trigger: digitCount)` on each tap. Error shake via `.offset(x: shakeX).animation(.default, value: shakeX)`.

### 14.5 TOTP input

6-character field, JetBrainsMono, `.kerning(8)`, accepts only digits, auto-advances focus. On paste, accept 6 digits and auto-submit. `.submitLabel(.done)` on the keyboard.

Backup codes dialog: one-time display, forces user to acknowledge "I saved these". Codes stored in Keychain; each code is struck through after use.

---

## 15. Camera, photos, barcode/QR

### 15.1 Photo capture

`PhotoCaptureView` supports:
1. Live camera capture (pre/post repair photos).
2. Gallery picker (existing photo).
3. File import (from Files.app via `UIDocumentPickerViewController`).

**Live capture** via `AVCaptureSession` wrapped in `UIViewControllerRepresentable`:
- Preview layer.
- Shutter button at bottom with `.symbolEffect(.bounce, value: captureCount)`.
- Flip-camera button top-right.
- Filter chips (Before / After / Device / Serial) at top — each chip applies a persisted tag, not an image filter.

**Gallery** via `PhotosPicker` (iOS 16+) — simpler and respects limited-access permission.

**Info.plist strings:**
- `NSCameraUsageDescription` = "Take photos of devices under repair for ticket records."
- `NSPhotoLibraryUsageDescription` = "Attach existing photos to ticket records."
- `NSPhotoLibraryAddUsageDescription` = "Save ticket photos back to your library."

### 15.2 Barcode / QR

**Use `DataScannerViewController`** (VisionKit, iOS 16+). Substantially cleaner than rolling AVFoundation + Vision.

```swift
import VisionKit

struct BarcodeScanView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .upce, .qr, .code128, .code39])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    // delegate: on tap or recognition → write to scannedCode, haptic .success
}
```

Supports continuous scanning for inventory stock-counts in v2.

### 15.3 Photo QR for LAN pairing

CLAUDE.md §4: photo QR codes must use LAN IP (not localhost). Client fetches `/api/v1/info` → `{ lan_ip, port, server_url }` and generates a QR to pair Android/iOS with the on-prem server on first launch. Port this logic 1:1 — iOS can decode the QR same way.

---

## 16. POS flow + BlockChyp + Bluetooth printers

### 16.1 Cart layout (per memory)

40/60 cart-to-content split. **Not** 30/70 with auto-collapse (explicit user preference — see memory item).

- iPhone: cart pinned to bottom sheet at `.presentationDetents([.fraction(0.4), .large])`, never auto-collapses.
- iPad: `NavigationSplitView(sidebar: CartView, detail: CatalogView)` with `.navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 500)` on the cart (40%).

### 16.2 BlockChyp integration

BlockChyp ships an official iOS SDK (Objective-C, Swift bridge via CocoaPods):
- `pod 'BlockChyp'` in Podfile.
- All calls async with completion; wrap in a Swift `async` extension.
- Test mode uses `BlockChyp Test Suite` with developer PIN keys.
- Operations needed for v1: `charge`, `preauth`, `capture`, `void`, `refund`, `terminalStatus`, `ping`.

**Certification**: BlockChyp requires a developer-kit certification pass before production PIN keys are issued. Plan ~2 weeks for certification round-trips.

**Terminal pairing**: store paired terminal name + IP in `UserDefaults` (it's not a secret).

### 16.3 Bluetooth printers

Two primary vendors for shop thermal receipt printers:

**Star Micronics**:
- StarPRNT SDK for iOS (Swift wrapper, SPM support).
- Privacy manifest included since v2.11.1.
- **Requires Apple MFi approval** for App Store listing — Star provides a letter of support you attach to your App Store submission.
- Paired printers listed via `starIOExtManager.getPortInfos`.

**Epson**:
- ePOS SDK 2.33.1+ (Swift).
- **Requires MFi approval** — separate process, file with Epson AND Apple.
- Contact Epson MFi support before submission.

**Generic ESC/POS** over Bluetooth LE Classic:
- Works without MFi for **BLE** printers.
- Thermal printers still use Bluetooth Classic (MFi required).
- If the shop only uses BLE printers, we can skip MFi.

**Reality**: the existing shops almost certainly use Star/Epson Bluetooth Classic. Budget a **3–6 week** MFi process lag into the submission plan.

### 16.4 Print pipeline

Abstract behind a protocol so we can swap vendors:

```swift
protocol ReceiptPrinter {
    var isConnected: Bool { get }
    func connect() async throws
    func print(_ receipt: Receipt) async throws
    func disconnect()
}

// Implementations: StarPrinter, EpsonPrinter, MockPrinter
```

### 16.5 PCI scope

POS that takes cards = PCI. Our scope stays **PCI-SAQ-A-EP**-ish because BlockChyp terminals encrypt at swipe/tap; card data never touches our app. Keep it that way: never read PAN, never log card data, never store cardholder data in GRDB. BlockChyp's SDK enforces this; don't fight it.

---

## 17. Notifications: APNs, Live Activities, widgets, Siri, App Intents

### 17.1 APNs

- Server needs an APNs auth key (p8) + team ID + key ID. Env:
  ```
  APNS_TEAM_ID=...
  APNS_KEY_ID=...
  APNS_P8=...
  APNS_BUNDLE_ID=com.bizarreelectronics.crm
  APNS_ENV=production|sandbox
  ```
- Client registers: `UIApplication.shared.registerForRemoteNotifications()` → APNs token in `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` → POST to `/api/v1/device-tokens`.
- Notification categories: `sms`, `tickets`, `appointments`, `sync`. Each with its own actions (e.g. sms category has "Reply" + "Mark Read").

### 17.2 Foreground vs background

- **Alerts** (user-visible): `{ "alert": { "title": "...", "body": "..." }, "sound": "default" }`.
- **Silent pushes** (sync triggers, see §12): `{ "aps": { "content-available": 1 }, "data": { "kind": "ticket.updated", "id": 42 } }` — delivered to `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`.

### 17.3 Notification actions

```swift
let replyAction = UNTextInputNotificationAction(
    identifier: "SMS_REPLY",
    title: "Reply",
    options: [],
    textInputButtonTitle: "Send",
    textInputPlaceholder: "Reply to customer"
)
let category = UNNotificationCategory(identifier: "sms", actions: [replyAction], intentIdentifiers: [])
UNUserNotificationCenter.current().setNotificationCategories([category])
```

### 17.4 Live Activities (ActivityKit)

**The killer feature for a repair shop.** Show "Ticket #472 — Awaiting parts" on Lock Screen / Dynamic Island, updating live as the ticket's status changes.

```swift
struct RepairInProgressAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: TicketStatus
        var eta: Date?
        var noteLine: String?
    }
    var ticketId: Int64
    var ticketDisplayId: String  // "T-472"
    var customerName: String
}
```

Widget extension renders both the full Lock Screen presentation and the compact/expanded Dynamic Island presentations. Update via `Activity.update(using:)` from the main app OR push-updated from the server (iOS 17.2+) so the server pushes status changes directly without the app being open.

**iOS 26** adds iPad Live Activities + CarPlay Live Activities. Both free if we build the stack right.

### 17.5 Widgets

Home-screen + Lock Screen widgets (WidgetKit):
- **Dashboard widget** (2×2 / 2×4): today's ticket count, revenue, pending parts.
- **Appointments widget** (2×4): next 3 appointments.
- **Sync status widget** (2×2): last sync time, pending-queue count, server reachable y/n.

All interactive (iOS 17+) — buttons tied to App Intents.

### 17.6 App Intents

Expose the app's actions to Shortcuts / Siri / Spotlight / Action Button / Control Center:

```swift
struct CreateTicketIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Ticket"
    static var openAppWhenRun: Bool = true
    @Parameter(title: "Customer") var customerName: String
    @Parameter(title: "Device") var deviceName: String?

    func perform() async throws -> some IntentResult {
        let draft = TicketDraft(customerName: customerName, deviceName: deviceName)
        await DeepLinkRouter.shared.open(.createTicket(draft))
        return .result()
    }
}
```

First-class intents to ship in v1:
- `CreateTicketIntent`
- `LookupTicketIntent(ticketId:)`
- `ScanBarcodeIntent`
- `AddCustomerIntent`
- `CheckInventoryIntent(sku:)`
- `ClockInIntent / ClockOutIntent`

Each becomes a Shortcuts action, a Siri command ("Hey Siri, create a ticket for Sarah"), a Spotlight result, and a Home Screen widget button.

### 17.7 Control Center (iOS 18+)

Expose "New Ticket" as a Control widget. One tap from Control Center, opens create flow. Replaces the Android Quick Settings tile with something even faster.

---

## 18. Reports & charts

### 18.1 Chart library: Swift Charts

Apple's native `Charts` (iOS 16+) — tight SwiftUI integration, high quality, free. No reason to reach for Charts.js / PPPieChart / ShinyCharts.

```swift
import Charts

Chart(revenueByDay) { point in
    BarMark(
        x: .value("Day", point.date, unit: .day),
        y: .value("Revenue", point.amount)
    )
    .foregroundStyle(.bizarreOrange.gradient)
}
.chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) }
.chartYAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
```

### 18.2 Palette discipline

Android reports screen was flagged for tailwind hex literals (`#D1FAE5`, `#FEE2E2`) that don't match brand. iOS port uses brand tokens from day one:
- Revenue: `.bizarreOrange`
- Expenses: `.errorRose`
- Inventory: `.bizarreTeal`
- Customers: `.bizarreMagenta`

### 18.3 Tabs

`Picker(selection:) { ... }.pickerStyle(.segmented)` at top for Revenue / Expenses / Inventory / Customer. No tab state persists across sessions — same as Android.

---

## 19. Local database (GRDB vs SwiftData)

### 19.1 Recommendation: GRDB

Reasons:
1. **Mental model parity** — your server is SQLite via `better-sqlite3`, Android uses Room (SQL-based). GRDB is raw SQL with a Swift API. You can port migrations 1:1 as `.sql` files. SwiftData's macro-driven schema diverges from SQL and forces you to rethink.
2. **Encryption** — GRDB supports SQLCipher out of the box (`GRDB/SQLCipher` subspec). Matches Android's Room+SQLCipher setup with per-install Keychain-backed passphrase.
3. **Performance** — GRDB benchmarks faster than SwiftData for read-heavy workloads. Your CRM is read-heavy (ticket list, customer list, inventory scroll).
4. **SwiftData maturity** — as of iOS 26, SwiftData still has edge-case bugs in migrations and silent-save ordering. Not worth for a production-critical app.
5. **Reactive queries** — GRDB's `ValueObservation` pipes directly into `@Observable` view models. No ceremony.

### 19.2 Schema parity

13 local tables from Android; port each migration file:

```
Packages/Persistence/Migrations/
  001_initial.sql
  002_add_ticket_device_parts.sql
  003_add_sms_threads.sql
  ...
  024_reorganize_inventory_indices.sql
```

One migration file per server migration — keeps the mental map easy. Note: iOS client does not need every server table — for example, tenancy/billing tables live only on server. Port only: `ticket`, `ticket_device`, `ticket_device_part`, `ticket_note`, `customer`, `inventory`, `invoice`, `invoice_line`, `sms_thread`, `sms_message`, `lead`, `estimate`, `expense`, `notification`, `sync_queue`, `sync_metadata`.

### 19.3 Passphrase generation

```swift
// first run
let passphrase = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.base64EncodedString()
Keychain.save(passphrase, key: "db_passphrase")

// every launch
let passphrase = Keychain.load("db_passphrase")
let config = Configuration.default
config.prepareDatabase { db in try db.usePassphrase(passphrase) }
let dbPool = try DatabasePool(path: ..., configuration: config)
```

### 19.4 Observation

```swift
struct TicketListQuery: FetchRequest {
    func fetch(_ db: Database) throws -> [Ticket] {
        try Ticket.order(Column("created_at").desc).fetchAll(db)
    }
}

@Observable final class TicketListViewModel {
    private(set) var tickets: [Ticket] = []
    private var cancellable: AnyDatabaseCancellable?

    init(dbPool: DatabasePool) {
        self.cancellable = ValueObservation.tracking { db in
            try TicketListQuery().fetch(db)
        }.start(in: dbPool) { [weak self] _ in
            self?.tickets = []
        } onChange: { [weak self] tickets in
            self?.tickets = tickets
        }
    }
}
```

---

## 20. Accessibility (non-negotiable with Liquid Glass)

### 20.1 System-handled (free)

When we use system controls and `.glassEffect()`, iOS handles:
- **Reduce Transparency** — glass becomes frosted/opaque.
- **Increase Contrast** — glass gains borders, controls become high-contrast.
- **Reduce Motion** — elastic glass animations disabled.
- **Bold Text** — system font weights scale up.

### 20.2 What we still have to do

| Requirement | How |
|---|---|
| **Dynamic Type** | Always use `.font(.body)` / `.font(.custom("Inter-Regular", size: 17, relativeTo: .body))`. Test at `.accessibilityExtraExtraExtraLarge`. |
| **VoiceOver labels** | Every button/image needs `.accessibilityLabel` + `.accessibilityHint`. POS tender flow especially: "Charge $85.00 to card" not just "Charge". |
| **Accessibility elements** | Grouped rows: `.accessibilityElement(children: .combine)` so VoiceOver reads "Ticket T-472, Sarah J, Awaiting parts" as one utterance. |
| **Color contrast** | WCAG AA (4.5:1 for body, 3:1 for large). The warm-dark palette passes; audit light mode especially. |
| **Tap targets** | 44×44 pt minimum. POS PIN pad buttons should be ≥60 pt. |
| **Reduced motion fallback** | Wrap `.matchedGeometryEffect` and `.bouncy` springs in `@Environment(\.accessibilityReduceMotion)` checks. |
| **Focus order** | Login → email → password → 2FA → submit. Test with keyboard on iPad. |

### 20.3 Accessibility Nutrition Labels (new in App Store Connect)

Declare: VoiceOver ✓, Voice Control ✓, Large Text ✓, High Contrast ✓, Reduced Motion ✓, Captions (N/A). Test each claim.

### 20.4 Test routine

Per feature:
1. Turn on VoiceOver. Complete the flow with eyes closed. Fix gaps.
2. Set Dynamic Type to `.accessibilityExtraExtraExtraLarge`. Check for clipped text / broken layout.
3. Toggle Reduce Transparency + Increase Contrast. Screenshot. Fix any unreadable glass.
4. Toggle Reduce Motion. Verify animations disable.

---

## 21. Performance budget & tactics

### 21.1 Budget

| Metric | Target |
|---|---|
| Cold start | < 1.5 s to first interactive UI |
| Tab switch | < 100 ms |
| List scroll | 120 fps on iPhone 15 Pro (ProMotion), ≥ 60 fps on iPhone 12 |
| Memory (steady state) | < 200 MB |
| Battery (1h active use) | < 5% (glass-heavy budget) |

### 21.2 Tactics

1. **`List`, not `LazyVStack`** for long tables (tickets, customers). `List` recycles via UITableView; `LazyVStack` keeps old views in memory on scrollback.
2. **Stable `Identifiable` IDs**. Never use `UUID()` in an item; use the server ID.
3. **`@Observable` granularity** — split view models so unrelated state doesn't force re-render. A `TicketListVM` shouldn't hold `SmsUnreadCount`.
4. **Nuke for images** — prefetch on-screen + 3 rows ahead, thumbnail decode off main thread. `AsyncImage` re-fetches on scrollback; only OK for small/static images.
5. **Glass budget** — max ~6 glass elements on screen at once. Use `GlassEffectContainer` so multiple glass views share sampling.
6. **Metal shader cost** — any custom shader (splash animation, wave divider if Canvas becomes too expensive) runs at full device refresh rate; skip on Low Power Mode via `ProcessInfo.processInfo.isLowPowerModeEnabled`.
7. **`Instruments 26`** — run the SwiftUI template + Hangs + Hitches on every major build. Budget 1 day/month for profiling.
8. **Avoid onChange storms** — `.onChange(of:)` with multiple observers in a single view causes cascade reloads. Debounce via `Task.sleep` inside the handler where needed.
9. **Keep `body` cheap** — extract subviews; avoid `Array.filter` / `Array.sorted` inside body.
10. **UIKit escape hatches** — for the POS tender screen (most-used, highest churn), consider `UIViewControllerRepresentable` wrapping a UIKit VC. SwiftUI's rendering has narrowed the gap but UIKit still wins on raw hitches in iOS 26.

---

## 22. Privacy manifest & App Store submission

### 22.1 PrivacyInfo.xcprivacy

Mandatory since May 2024. Every new app and every update that adds a "commonly used" SDK must ship it. File lives in app target + every third-party SDK we depend on.

Template:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeEmailAddress</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
        <!-- repeat for: name, phone, photos, other user content -->
    </array>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array><string>CA92.1</string></array>
        </dict>
        <!-- repeat for: system boot time (CA92.1? check the list), disk space -->
    </array>
</dict>
</plist>
```

Third-party SDK audit — check each bundles its own manifest:
- Starscream — check latest; add if missing via PR.
- GRDB — yes.
- Nuke — yes.
- Factory — yes.
- KeychainAccess — yes.
- BlockChyp — verify current.
- StarPRNT — yes (since 2.11.1).
- Epson ePOS — verify current.

### 22.2 Info.plist essentials

```xml
<key>NSCameraUsageDescription</key>
<string>Scan barcodes and take photos of devices under repair.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Attach existing photos to repair tickets.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save ticket photos to your library.</string>
<key>NSFaceIDUsageDescription</key>
<string>Authenticate to unlock Bizarre CRM.</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Connect to Bluetooth receipt printers and card readers.</string>
<key>NSContactsUsageDescription</key>
<string>Import customer phone numbers from Contacts.</string>
<key>NSUserActivityTypes</key>
<array>
    <string>com.bizarreelectronics.crm.ticket.view</string>
    <string>com.bizarreelectronics.crm.ticket.create</string>
</array>
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
    <string>processing</string>
    <string>fetch</string>
</array>
<key>UIApplicationSceneManifest</key>
<dict>...</dict>
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key><string>com.bizarreelectronics.crm</string>
        <key>CFBundleURLSchemes</key><array><string>bizarrecrm</string></array>
    </dict>
</array>
```

### 22.3 Export compliance

`ITSAppUsesNonExemptEncryption = false` → standard HTTPS / URLSession only, which is exempt. If we later add custom end-to-end encryption for SMS threads or similar, revisit.

### 22.4 Distribution choice

**Unlisted App Distribution** via Apple Business Manager is the best fit:
- App is on the App Store (reviewed, signed) but not discoverable in search.
- Link distributed per-shop for onboarding.
- Each shop can sign in with their tenant URL.
- No separate enterprise program — Apple has discouraged that for new orgs.
- TestFlight for pre-release builds to the shop's beta testers.

### 22.5 Review risk items

| Item | Risk | Mitigation |
|---|---|---|
| Self-signed TLS | Medium | SPKI pinning + document the why in review notes; preferably migrate to LE. |
| Bluetooth printer MFi | High (separate 3–6 week process) | Start MFi process **before** App Store submission, in parallel with development. |
| Camera usage string | Low | Specific, single-purpose strings — never "access to your device". |
| Background modes | Medium | Declare all three (`remote-notification`, `processing`, `fetch`) and justify in review notes. |
| Card-reader in-app | Medium | BlockChyp's review-safe wrapper; document in review notes that payment is card-present, not IAP. |
| Tracking / analytics | None | We ship with zero trackers. No ATT prompt. |

### 22.6 TestFlight timing

- Internal builds: available within ~15–30 min of upload.
- External builds: first build to a group requires App Review (typically 24–48 h, sometimes longer during backlogs).
- Subsequent external builds in same group usually skip full review.

Plan for 2 days of TestFlight latency before any critical test build.

---

## 23. Dev environment & CI on a Windows workstation

### 23.1 The Mac requirement

Xcode is macOS-only. Options:

1. **Mac Mini M4 (~$599)** — cheapest long-term, lives on your desk, 24GB unified memory handles big Xcode sims fine. **Recommended.**
2. **MacStadium / Scaleway M1** — rented, ~$120+/month.
3. **GitHub Actions macOS runners** — 10× cost multiplier vs Linux; OK for CI, not for interactive development.
4. **Xcode Cloud** — integrated with App Store Connect; works OK for CI.
5. **Codemagic** — pay-as-you-go, M2 build minutes, annual plans.
6. **Bitrise** — ~$280/app/month.

**Plan**: buy Mac Mini for daily dev. Use GitHub Actions macOS runners for CI (build + test + TestFlight upload on push to main).

### 23.2 CI pipeline

```yaml
# .github/workflows/ios.yml (sketch)
name: iOS
on:
  push: { branches: [main] }
  pull_request:
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with: { xcode-version: '26.0' }
      - name: Build
        run: xcodebuild -scheme BizarreCRM -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.0' build
      - name: Test
        run: xcodebuild -scheme BizarreCRM test
      - name: Archive & Upload
        if: github.ref == 'refs/heads/main'
        run: bundle exec fastlane beta
```

### 23.3 Fastlane

`match` for certs/profiles (private git repo, stored encrypted):
```
fastlane match appstore
fastlane match development
```

`gym` + `pilot` for build + TestFlight upload:
```ruby
lane :beta do
  match(type: "appstore", readonly: true)
  build_app(scheme: "BizarreCRM")
  upload_to_testflight(skip_waiting_for_build_processing: true)
end
```

### 23.4 Signing

- Two App IDs: `com.bizarreelectronics.crm` (main), `com.bizarreelectronics.crm.widgets`, `com.bizarreelectronics.crm.liveactivities`, `com.bizarreelectronics.crm.intents` (extensions).
- One App Group: `group.com.bizarreelectronics.crm` for main app + extensions to share GRDB + Keychain.
- Distribution cert valid 1 yr; renewed via `match`. Add calendar reminder.
- APNs p8 key: created once in Apple Developer, reused across environments.

### 23.5 Simulators + devices

- Simulator: iPhone 16 Pro (iOS 26) for primary dev; iPhone 11 (iOS 17) for low-end check; iPad Pro 13" (iPadOS 26) for split-view dev.
- Real devices: at minimum one modern iPhone (iOS 26, Liquid Glass) + one older (iPhone 12, iOS 18) for regression.

---

## 24. Xcode project layout

### 24.1 Targets

| Target | Kind | Purpose |
|---|---|---|
| BizarreCRM | iOS App | Main app |
| BizarreCRMWidgets | Widget Extension | Home Screen + Lock Screen widgets |
| BizarreCRMLiveActivities | Widget Extension (ActivityKit) | Ticket-in-progress Live Activity |
| BizarreCRMIntents | App Intents Extension | Shortcuts / Siri / Spotlight |
| BizarreCRMTests | Unit Test Bundle | XCTest unit tests |
| BizarreCRMUITests | UI Test Bundle | XCUITest flows (login, ticket create, POS) |

### 24.2 Swift Packages (local, in `Packages/`)

Each feature package has `Package.swift`, exposes one public module, depends on `Core` + `DesignSystem` + relevant infra (`Networking`, `Persistence`).

### 24.3 Build configurations

| Config | Bundle ID | API base | TLS mode |
|---|---|---|---|
| Debug | `com.bizarreelectronics.crm.dev` | `https://dev.bizarreelectronics.com` | Pin dev key |
| TestFlight | `com.bizarreelectronics.crm` | `https://<shop>.bizarreelectronics.com` | Pin prod key |
| Release | `com.bizarreelectronics.crm` | `https://<shop>.bizarreelectronics.com` | Pin prod key |

Per-config Info.plist `API_BASE_URL` read at launch.

### 24.4 Tenant switching

Login screen accepts a `server URL` (just like Android). Store in UserDefaults per-session; use for subsequent API calls. Pinning matches SPKI — works across tenants because they share a wildcard cert or we bundle per-tenant SPKIs via a remote config fetched once over a trusted endpoint.

---

## 25. Mac (Apple Silicon) support — "Designed for iPad"

### 25.1 The three macOS distribution paths (and why we pick one)

Any iOS app targeting Apple Silicon Mac has three mutually exclusive paths. Pick one per release — they don't co-exist in a single binary cleanly.

| Path | What it is | Dev cost | Mac-native feel | Intel Mac? | Verdict |
|---|---|---|---|---|---|
| **Designed for iPad** | Same iPad `.ipa` runs as ARM64 process on Apple Silicon Mac. macOS wraps it in a resizable window with a synthetic menu bar. Apple calls it "iPad app on Mac." | **Zero** extra code. One checkbox in App Store Connect. | ~80% — feels like an iPad app running in a window, not a Mac app. No AppKit menus, no `NSToolbar`, pointer is a touch-surrogate. | No — M1/M2/M3/M4 only. | ✅ **Chosen for v1** |
| **Mac Catalyst** | Recompile iOS source with `.catalyst` destination. SwiftUI maps to AppKit primitives; iOS controls render as Mac controls. Separate product record or shared with iOS. | ~2 days/screen to tune (toolbars, menus, window sizing, keyboard shortcuts). | ~95% — looks like real Mac app. Still SwiftUI under the hood. | No — Apple Silicon + Intel x86_64 (Catalyst supports Intel). | Deferred v2+ |
| **Native macOS SwiftUI target** | Separate scheme + target in the same Xcode project; shares Swift packages. | Weeks — platform-specific view code, NSToolbar, menu bar, preferences window. | 100% — indistinguishable from Mac-first apps. | Yes, if Intel deployment target set. | Out of scope v1 |

**Why "Designed for iPad" for v1:**
- **Zero engineering cost.** Literally toggling `supports-mac = true` on the iPad target.
- **Distribution is unified.** One App Store Connect record. One TestFlight. One review.
- **Signing is shared.** Same provisioning profiles.
- **All the logic already works** — URLSession, GRDB, Keychain, WebSocket, APNs, App Intents, Live Activities (iOS 26.1+ on Mac via virtualized ActivityKit).
- **Shops probably already run Apple Silicon.** If they bought a Mac in the last 4 years, it's M-series.

**What we lose vs Catalyst:**
- No AppKit menu bar. Synthetic menu shows basic items (File > Close, Edit > Undo, Window, Help) but we can't add custom menus (e.g. "Tickets > New" as a menu command).
- No `NSToolbar`. Our SwiftUI toolbar renders as an iOS toolbar inside the window, not the macOS-native titlebar toolbar.
- No right-click context menus on window chrome.
- Pointer gestures map to touch events (no true hover cursor for non-SwiftUI-`.hoverEffect` elements).
- Window resizing is limited by the iPad size classes we support (if we pin to `Compact`, the window won't grow past ~1024pt).
- Not available on Intel Macs.

For a shop CRM, **none of these are dealbreakers**. Intel Macs are the only real concern, and they're aging out of org purchases anyway.

### 25.2 How to enable (5 minutes)

1. In Xcode, select the iOS app target.
2. General tab → Supported Destinations → click **+** → **Mac (Designed for iPad)**.
3. Build for "My Mac (Designed for iPad)" destination; launch. App runs as a resizable window.
4. In App Store Connect, when submitting, check **Mac** under Availability → Platforms.
5. Done. The same `.ipa` now lists on the Mac App Store.

No `.macos()` availability blocks, no separate build. Just works.

### 25.3 What actually changes in the binary

At runtime on Mac (`ProcessInfo.processInfo.isiOSAppOnMac == true`):
- UI renders in a resizable NSWindow.
- System keyboard shortcuts (⌘C, ⌘V, ⌘Q, ⌘W, ⌘R) auto-bind where iOS has equivalents.
- `SwiftUI.Table` with multiple columns gets Mac-style selection + column resize.
- `.hoverEffect` works with real mouse pointer.
- `.contextMenu` triggers on right-click + two-finger tap.
- `.keyboardShortcut(_:)` modifiers are respected.
- `.onDrag` / `.onDrop` work with Finder.
- Window state (size, position) persists between launches automatically.
- Trackpad gestures (pinch-to-zoom, two-finger scroll) pass through.

### 25.4 What breaks on Mac and how to handle it

| API | Mac behavior | Action |
|---|---|---|
| `AVCaptureSession` (photo capture) | Uses built-in webcam or FaceTime HD. Works. | Test on Mac; webcam framing is weirder than iPhone rear cam. |
| `DataScannerViewController` (barcode) | **Not available on Mac (iPad on Mac).** Apple Vision APIs don't bridge. | Feature-gate: show "barcode scan only on iPhone/iPad" message on Mac, or use Vision framework directly with the webcam as fallback. |
| `LAContext` (Face ID / Touch ID) | Uses Touch ID on MacBook Air/Pro, Magic Keyboard with Touch ID on desktop Macs, Apple Watch unlock. Works. | No change. |
| `UNUserNotificationCenter` (APNs) | Works. Notifications appear in Notification Center. | No change. |
| Bluetooth printer (Star/Epson MFi) | **MFi Bluetooth Classic does not work on Mac "Designed for iPad" mode.** | Feature-gate: on Mac, show AirPrint fallback or "print from iPhone/iPad". Catalyst would fix this, revisit in v2. |
| BlockChyp terminal | Works — terminal comms over IP, not USB/Bluetooth. | No change. |
| `ActivityKit` Live Activities | Works on Mac running macOS 14.6+ with iOS 26 Live Activities bridge. Shows in Notification Center instead of Dynamic Island. | No change. |
| Widgets | Mac renders home-screen widgets in the Notification Center sidebar. Works. | No change. |
| App Intents / Shortcuts | Works — Mac Shortcuts.app picks up intents automatically. | No change. |
| `UIDevice.current.orientation` | Always `.portrait` on Mac; window can still be any aspect. | Don't branch UI on orientation; use size classes. |
| `isiPad` / device-class checks | `UIDevice.current.userInterfaceIdiom == .pad` returns `.pad` on Mac. | Use `ProcessInfo.processInfo.isiOSAppOnMac` to distinguish when needed. |
| Haptics (`.sensoryFeedback`) | No-op on Mac (no Taptic Engine in standalone Macs; works on MacBook trackpad for some events). | No change — graceful degradation. |
| `FileManager` paths | Sandboxed to app container, same as iOS. | No change. |

### 25.5 UX adjustments for Mac window mode

Most of our design works on Mac unchanged. Specifics:

- **Primary layout: iPad split view.** Our `NavigationSplitView` sidebar+detail layout is the canonical Mac experience. On iPhone it collapses to a stack; on iPad and Mac it shows both columns. **Default to iPad layout on Mac** — the user gets the sidebar-with-content view they expect from a Mac app.
- **Window minimum size**: declare a sensible minimum. In the scene configuration for Mac, enforce `defaultSize(width: 1024, height: 720)` and `minimumSize(width: 800, height: 600)`. Below that, our forms wrap awkwardly.
- **Keyboard shortcuts** — add `.keyboardShortcut(_:)` to primary actions. On Mac users will expect them; on iPad with Magic Keyboard same.
  - ⌘N — New Ticket
  - ⌘F — Search
  - ⌘, — Settings (standard Mac)
  - ⌘R — Sync now
  - ⌘W — Close sheet/window
  - ⌘/ — Toggle sidebar (where applicable)
- **Trackpad hover** — `.hoverEffect(.highlight)` on tappable rows so Mac pointer gives real feedback. Already a good iPad-with-pointer idiom.
- **Right-click context menus** — already set via `.contextMenu` on list rows; just verify they trigger. Add common items (Open, Copy ID, Archive, Delete).
- **Liquid Glass on Mac** — macOS Tahoe 26 has Liquid Glass in its chrome; our `.glassEffect()` renders correctly on Mac running macOS 26+. On macOS 14/15 the `.ultraThinMaterial` fallback kicks in. No special handling.
- **Dark mode** — Mac users toggle dark mode globally. Our `@Environment(\.colorScheme)` handling works identically.
- **Text selection** — `SwiftUI.Text` allows selection with `.textSelection(.enabled)`. Enable this on ticket IDs, invoice numbers, customer emails — Mac users will expect to copy.
- **File exports** — replace "share sheet" flows with `.fileExporter(...)` for invoice PDFs / reports CSV. The iPad share sheet on Mac shows iOS-style options; `fileExporter` opens a real Finder save dialog.
- **Printing** — `UIPrintInteractionController` on Mac shows a real Mac print dialog. Keep our print flows — they just work better.
- **Menu bar commands** — **cannot add** in "Designed for iPad" mode. The system gives us File/Edit/View/Window/Help stubs. Document this as a known limitation; users launch actions from the UI.

### 25.6 Code that needs `isiOSAppOnMac` branching

Minimize this — the whole point is zero-branch. But some specific spots:

```swift
let isMac = ProcessInfo.processInfo.isiOSAppOnMac

// Barcode scanner unavailable → swap to manual entry + hide "scan" button on Mac
if isMac {
    ManualBarcodeEntryView(onCode: onCode)
} else {
    DataScannerView(onCode: onCode)
}

// Bluetooth printer unavailable → AirPrint-only on Mac
if isMac {
    PrintButton(style: .airPrintOnly)
} else {
    PrintButton(style: .bluetoothOrAirPrint)
}

// Haptic no-op on Mac — just skip
if !isMac {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}
```

Isolate these in a `Platform` module helper:

```swift
enum Platform {
    static var isMac: Bool { ProcessInfo.processInfo.isiOSAppOnMac }
    static var supportsNativeBarcodeScan: Bool { !isMac }
    static var supportsBluetoothPrinter: Bool { !isMac }
    static var supportsHaptics: Bool { !isMac }
}
```

### 25.7 Window + scene configuration

In `BizarreCRMApp.swift`:

```swift
@main
struct BizarreCRMApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .defaultSize(width: 1200, height: 800)   // initial Mac window size
        .windowResizability(.contentMinSize)     // can shrink to content min
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Ticket") { DeepLinkRouter.shared.open(.createTicket(nil)) }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Tickets") {
                // limited — only shows in Catalyst, not Designed-for-iPad
                // but harmless: iOS ignores, Catalyst picks up later
            }
        }
    }
}
```

`.commands` partially works — on "Designed for iPad" Mac, `CommandGroup(replacing:)` for system commands is respected (⌘N triggers the intent), but custom `CommandMenu` additions are ignored. Same code path works for Catalyst v2.

### 25.8 Testing on Mac

Minimum Mac test matrix for v1:

| Mac | macOS | Use case |
|---|---|---|
| MacBook Air M1 (8GB) | macOS 14 Sonoma | Low-end, older OS, `.ultraThinMaterial` fallback |
| MacBook Pro M3/M4 (16GB) | macOS 26 Tahoe | Primary dev Mac, Liquid Glass native |
| Mac Mini M4 (CI + daily) | macOS 26 Tahoe | Per §23, this is the dev machine |

Test checklist on Mac:
- [ ] Login → 2FA → PIN → Dashboard loads.
- [ ] Sidebar-detail split view renders, resize window → split stays balanced.
- [ ] `⌘N` opens new ticket.
- [ ] `⌘F` focuses search.
- [ ] Right-click ticket row → context menu appears.
- [ ] Hover ticket row → `.hoverEffect` highlight shows.
- [ ] Barcode button on Mac shows "unavailable — use iPhone" (or manual entry).
- [ ] Webcam photo capture works in ticket form.
- [ ] Touch ID unlock (on Touch ID Macs).
- [ ] APNs notification arrives in Notification Center.
- [ ] Live Activity for in-progress ticket shows in Notification Center.
- [ ] Print invoice → real macOS print dialog opens.
- [ ] Export report → real Finder save dialog.
- [ ] Dark mode follows system.
- [ ] Liquid Glass renders on macOS 26; frosted fallback on 14/15.
- [ ] Quit (⌘Q) → relaunch → window restores size/position.

### 25.9 App Store Connect setup

Availability:
- **iPhone** ✓
- **iPad** ✓
- **Mac (Designed for iPad)** ✓ ← new, check this for v1
- **Mac (Catalyst)** ✗ ← v2
- **Apple Vision Pro** ✗

Mac screenshots: 1280×800, 1440×900, 2560×1600, 2880×1800 supported. Submit 3–5 screenshots of the iPad layout running on Mac. Apple auto-generates some but curated ones convert better.

Metadata: the iPad app name/description is reused. No separate Mac copy needed.

### 25.10 When to graduate to Mac Catalyst (v2 trigger)

Graduate to Catalyst if any of:
- Shop demands Intel Mac support (unlikely in 2026+).
- Need real menu-bar commands for power users (e.g. "Tickets → Mark All Ready").
- Bluetooth printer support on Mac becomes critical (Catalyst supports MFi differently; verify before committing).
- macOS-native window chrome (NSToolbar, tabs) is needed for brand reasons.
- Selling the app to Mac-centric orgs where "iPad on Mac" smell is a dealbreaker.

Until one of those hits, stay on "Designed for iPad." Catalyst is a ~3-week engineering investment per screen audit — not free.

### 25.11 Risk additions for Mac support

Add to §27 risks register:
- **Webcam framing on Mac** — built-in cam is fixed-position, user has to hold device to it; photo capture flow needs UX tweak for Mac.
- **"Designed for iPad" removed from App Store Connect** — Apple could theoretically push devs toward Catalyst. No signal of this, but watch WWDC 2026 announcements.
- **ActivityKit on Mac** — Live Activities are newer on Mac; may have parity gaps with iOS 26 that we don't catch in testing.

---

## 26. Phased rollout plan

### Phase 0 — Foundations (Week 1–2)
- Xcode project + Swift Packages scaffold.
- `APIClient` with SPKI pinning.
- `GRDB` setup + first 5 migrations.
- `Keychain` + token store.
- `Factory` DI container.
- Brand design tokens (colors, type, spacing, glass wrapper).
- CI pipeline (GitHub Actions macOS runner + Fastlane match).
- **Exit criteria**: can call `/api/v1/health` from a blank app, see pinned TLS succeed, and TestFlight upload triggers from `main`.

### Phase 1 — Auth (Week 3)
- Login → 2FA → PIN setup → biometric gate → main shell.
- Keychain-backed tokens, auto-refresh on 401.
- Privacy manifest + Info.plist usage strings.
- **Exit criteria**: real user logs into a real shop, lands on empty Dashboard.

### Phase 2 — Read-only shell (Week 4–5)
- TabView / NavigationStack skeleton.
- Ticket list (read-only from server), customer list, inventory list, invoice list.
- WebSocket connect + event log (no handling yet).
- Offline banner.
- **Exit criteria**: shop staff can browse data on iPhone.

### Phase 3 — Core CRUD (Week 6–8)
- Ticket create / edit / detail (full form, photos).
- Customer create / edit.
- Inventory create / edit / barcode scan.
- Invoice detail (view + email + print-stub).
- SMS list + thread with live updates.
- Offline sync queue.
- **Exit criteria**: can run an end-to-end ticket + invoice + SMS workflow without touching the web app.

### Phase 4 — POS (Week 9–10)
- Cart + checkout flow (40/60 layout).
- BlockChyp integration (test mode).
- Bluetooth printer abstraction + Star integration.
- **Exit criteria**: test terminal can charge $0.01 and print receipt from the app.

### Phase 5 — Polish (Week 11–12)
- Liquid Glass pass on every screen (Xcode 26 recompile + audit).
- Motion spec applied everywhere.
- Dashboard widget, Lock Screen widget, Live Activity for in-progress tickets.
- App Intents (Create Ticket, Lookup Ticket, Scan Barcode, …).
- Accessibility audit (VoiceOver, Dynamic Type, Reduce Transparency).
- Performance pass (Instruments).
- **Exit criteria**: designer sign-off.

### Phase 6 — App Store prep (Week 13–14)
- Privacy manifest audit.
- App Store Connect listing (screenshots, description, promo text, nutrition labels).
- Unlisted distribution request via Apple Business Manager.
- MFi printer approval letters filed (Star + Epson).
- **Enable "Designed for iPad" on Mac** (§25): toggle Mac destination in Xcode target, tick Mac availability in App Store Connect, run Mac test checklist (§25.8).
- First TestFlight external build (iPhone + iPad + Mac).
- **Exit criteria**: app submitted for App Review on all three platforms.

### Phase 7 — Live Activities, iPad polish, v2 stretch (Week 15–18)
- iPad NavigationSplitView tune-up.
- Live Activity push updates (server-side APNs push to ActivityKit).
- EventKit sync for appointments.
- Core Spotlight indexing.
- Control Center control widgets (iOS 18+).
- Apple Watch companion (v2, out of scope for v1).

---

## 27. Risks register

| # | Risk | Prob. | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Self-signed cert + ATS blocks first request | High | High | SPKI pinning (§11) + migrate to Let's Encrypt. |
| R2 | MFi approval delay blocks printer | Med | High | Start MFi process in parallel with Phase 0; ship v1 without print if needed. |
| R3 | BlockChyp certification delay | Med | Med | Start cert track in Phase 4 week 1; have mock-mode path. |
| R4 | SwiftData/GRDB conflict with server schema evolution | Low | Med | Strict migration file parity with server; integration test against a fresh server DB. |
| R5 | Liquid Glass perf on iPhone 12–13 | Med | Low | Glass budget (§5) + profile on iPhone 12 real device. |
| R6 | APNs silent-push latency worse than WorkManager cadence | High | Low | Acceptable trade; WebSocket fills the real-time gap when app open. |
| R7 | Swift 6 strict concurrency friction | Med | Med | Start with approachable concurrency (Swift 6.2); migrate one module at a time. |
| R8 | GRDB passphrase Keychain race on upgrade | Low | High | Write single-writer lock on DB open; test cold-restart paths. |
| R9 | iPad split-view POS layout regression | Med | Med | Design spec before build; test both orientations + multitasking. |
| R10 | App Review delay on first submission | Med | Med | Submit Phase 6 build at week 13 end; buffer 2 weeks for re-submits. |
| R11 | Font licensing (Inter/Barlow/JetBrainsMono) in iOS bundle | Low | Low | All OFL — allowed. |
| R12 | App Transport Security exception rejected | Low | High | Redundant with R1; SPKI pinning is Apple-endorsed. |
| R13 | Background modes triggering more review scrutiny | Med | Low | Document each mode in review notes; justify `processing` specifically. |
| R14 | Privacy manifest mismatch on a 3rd-party SDK update | Med | Med | Lock SDK versions via SPM; audit on every bump. |
| R15 | Windows dev finds `match` cert renewal painful | High | Low | Calendar reminder 30 days before cert expiry; keep Mac Mini accessible. |

---

## 28. Testing strategy

### 27.1 Unit tests (XCTest)

- All view models (inputs → state transitions).
- API envelope parsing (`APIResponse<T>` for every endpoint).
- Sync queue logic (enqueue, drain, retry, conflict).
- Form validation (phone formatting, email, pricing math).
- Keychain wrapper (mock `SecItemAdd/Copy`).

### 27.2 Integration tests

- Spin up a local Node server with test data; run against it from simulator.
- Round-trip: create ticket offline → go online → verify server + local consistent.
- WebSocket reconnection on simulated network flap.

### 27.3 UI tests (XCUITest)

- Login → 2FA → PIN setup → Dashboard.
- Ticket create (full form) → save → verify detail.
- POS: add item → charge → print.
- Barcode scan (mock via `DataScannerViewController` stub).
- Dark mode + light mode snapshot tests.

### 27.4 Snapshot tests

Use `swift-snapshot-testing` (pointfree) on key views at:
- iPhone 16 Pro / iPhone SE.
- iPad Pro 13" / iPad Mini.
- Dynamic Type `.xSmall` / `.body` / `.accessibilityExtraExtraExtraLarge`.
- Light / Dark.
- Reduce Transparency on/off.

10 screens × 4 devices × 3 type sizes × 2 colors × 2 transparency = 480 snapshots. That's fine; golden library lives in tests.

### 27.5 Manual smoke

Per build:
- Login, logout, relogin.
- Offline → online transition with 3 queued mutations.
- Scan barcode, prefill inventory.
- Take photo, attach to ticket.
- Send SMS, receive reply.
- POS charge on test terminal.
- Print receipt.
- Receive APNs → tap → deep link to ticket.
- Lock screen → see Live Activity → tap → open ticket.
- Siri "Create Ticket" → fill customer → complete.

### 27.6 Accessibility smoke

- VoiceOver walk-through of each critical flow.
- Dynamic Type max.
- Reduce Transparency + Increase Contrast.
- Reduce Motion.

---

## 29. Cross-platform parity items

These affect **both** Android and iOS; put in `bizarre-crm/TODO.md` CROSS section per CLAUDE.md.

| CROSS item | Status | Notes |
|---|---|---|
| Status color palette migration (server seed) | Pending | Server returns status colors as random Material hex; migrate to Bizarre 5-hue discipline. Affects both apps. |
| `/api/v1/sync/since?ts=` endpoint | Pending | Formalize delta sync endpoint so both platforms share semantics. |
| APNs + FCM push parity | Pending | Server must fan out to both APNs (iOS) and FCM (Android) on the same event. |
| 2FA / TOTP + backup codes | Done on Android, pending on iOS | Same server endpoints. |
| Phone auto-formatting `+1 (XXX)-XXX-XXXX` | Done on Android, pending on iOS | Memory item. |
| WebSocket event model | Done on Android | Same JSON schema reused on iOS. |
| Offline queue semantics | Done on Android | Same queue table structure mirrored. |
| Tenant-aware base URL + SPKI pinning | Android uses per-install URL | Same pattern on iOS. |
| Unlisted App Distribution + Play private track | Android on internal testing | Submit unlisted on iOS. |
| Live Activity server push | N/A on Android | iOS-only; needs server to push `ActivityKit` auth tokens to APNs topic `com.bizarreelectronics.crm.push-type.liveactivity`. |

---

## 30. Open questions

1. **Who owns the Apple Developer account?** Organizational (D-U-N-S required) or individual? Unlisted distribution requires Apple Business Manager, which requires organizational.
2. **What's the canonical server hostname(s)?** Per-tenant subdomain (`shop123.bizarreelectronics.com`) or single host with tenant header? Affects TLS pinning strategy and app-onboarding UX.
3. **Do we want Mac Catalyst / visionOS targets in v2?** "Designed for iPad" (see §25) covers Apple Silicon Mac in v1 for free — the iPad binary runs native ARM64 on M-series. Mac Catalyst is a separate, heavier path (~2 days extra work per screen to tune for AppKit idioms); visionOS is a redesign. Revisit Catalyst only if shops want Intel-Mac support or macOS-native window chrome.
4. **Apple Watch companion?** Useful for "ticket ready" glance + quick clock-in. Out of scope for v1; revisit after POS launches.
5. **EventKit sync for appointments?** Write-through to user's Calendar? Powerful but opens a privacy scope; decide in Phase 2.
6. **Core Spotlight indexing?** Lets users search tickets/customers from iOS Spotlight. ~2 days; decide in Phase 5.
7. **iPad-specific layouts for which screens?** TicketCreate and POS benefit most from iPad split; other screens can share iPhone layout. Designer decision.
8. **Dark mode default vs follow system?** Android defaults to warm dark. iOS users overwhelmingly use Auto; recommend Auto with dark as forced for Login/PIN screens where brand is strongest.
9. **Designed-for-iPad on Mac — do we enable on day one, or wait for iPad polish?** Enabling the checkbox in App Store Connect takes ~5 minutes; the plan assumes day-one enablement. Flip only if a specific control (e.g. AVCaptureSession on Mac webcam) breaks and needs a feature gate. See §25.
10. **MDM / supervised deployment?** Shop iPads might be managed. MDM changes entitlements and distribution. Clarify.

---

## 31. Reference library

### Apple docs
- [Apple Newsroom — Liquid Glass announcement (June 2025)](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
- [Apple Developer — Liquid Glass technology overview](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [Apple Liquid Glass Design Gallery (2026)](https://developer.apple.com/design/new-design-gallery-2026/)
- [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [GlassButtonStyle](https://developer.apple.com/documentation/swiftui/glassbuttonstyle)
- [Migrating from ObservableObject to @Observable](https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [NavigationSplitView TN3154](https://developer.apple.com/documentation/technotes/tn3154-adopting-swiftui-navigation-split-view)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Encryption export compliance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
- [VisionKit DataScannerViewController](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller)
- [App Intents](https://developer.apple.com/documentation/appintents)
- [Widget interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Choosing background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)
- [ShaderLibrary](https://developer.apple.com/documentation/swiftui/shaderlibrary)
- [PhaseAnimator](https://developer.apple.com/documentation/swiftui/phaseanimator)
- [Core Haptics](https://developer.apple.com/documentation/corehaptics)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

### WWDC sessions
- [WWDC25 275 — Design app intents for system experiences](https://developer.apple.com/videos/play/wwdc2025/275/)
- [WWDC25 278 — What's new in widgets](https://developer.apple.com/videos/play/wwdc2025/278/)
- [WWDC25 306 — Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/)
- [WWDC24 10151 — Create custom visual effects with SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10151/)
- [WWDC24 10176 — Design app intents for system experiences](https://developer.apple.com/videos/play/wwdc2024/10176/)
- [WWDC23 10157 — Wind your way through advanced animations](https://developer.apple.com/videos/play/wwdc2023/10157/)

### Third-party Liquid Glass deep dives
- [Donny Wals — Designing custom UI with Liquid Glass on iOS 26](https://www.donnywals.com/designing-custom-ui-with-liquid-glass-on-ios-26/)
- [Donny Wals — Exploring tab bars on iOS 26 with Liquid Glass](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/)
- [atelier-socle — SwiftUI Liquid Glass guide](https://www.atelier-socle.com/en/articles/swiftui-liquid-glass-guide)
- [LiquidGlassReference (community)](https://github.com/conorluddy/LiquidGlassReference)
- [createwithswift — Liquid Glass hierarchy/harmony/consistency](https://www.createwithswift.com/liquid-glass-redefining-design-through-hierarchy-harmony-and-consistency/)
- [createwithswift — Adapting search to Liquid Glass](https://www.createwithswift.com/adapting-search-to-the-liquid-glass-design-system/)
- [dev.to — Liquid Glass best practices](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)
- [Ryan Ashcraft — Beef with iOS 26 tab bar](https://ryanashcraft.com/ios-26-tab-bar-beef/)
- [MacRumors — Reduce Transparency on Liquid Glass](https://www.macrumors.com/how-to/ios-reduce-transparency-liquid-glass-effect/)

### SwiftUI state of the art
- [avanderlee — Observable macro performance](https://www.avanderlee.com/swiftui/observable-macro-performance-increase-observableobject/)
- [Jesse Squires — @Observable is not a drop-in replacement](https://www.jessesquires.com/blog/2024/09/09/swift-observable-macro/)
- [Peter Steinberger — Automatic observation tracking UIKit/AppKit](https://steipete.me/posts/2025/automatic-observation-tracking-uikit-appkit)
- [Hacking with Swift — Swift 6 concurrency](https://www.hackingwithswift.com/swift/6.0/concurrency)
- [avanderlee — Approachable concurrency in 6.2](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/)

### Architecture
- [Medium — Modern MVVM in SwiftUI 2025](https://medium.com/@minalkewat/modern-mvvm-in-swiftui-2025-the-clean-architecture-youve-been-waiting-for-72a7d576648e)
- [Alexey Naumov — Clean Architecture for SwiftUI](https://nalexn.github.io/clean-architecture-swiftui/)
- [Factory (DI) on GitHub](https://github.com/hmlongco/Factory)
- [swift-dependencies](https://github.com/pointfreeco/swift-dependencies)
- [Bugfender — TCA guide](https://bugfender.com/blog/swift-composable-architecture/)

### Persistence
- [GRDB.swift](https://github.com/groue/GRDB.swift)
- [sharing-grdb](https://swiftpackageindex.com/pointfreeco/sharing-grdb/0.1.0/documentation/sharinggrdb/comparisonwithswiftdata)
- [fatbobman — Key considerations before using SwiftData](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/)
- [fatbobman — Why I'm still thinking about Core Data in 2026](https://fatbobman.com/en/posts/why-i-am-still-thinking-about-core-data-in-2026/)
- [distantjob — Core Data vs SwiftData 2025](https://distantjob.com/blog/core-data-vs-swiftdata/)

### Networking & security
- [avanderlee — URLSession async/await](https://www.avanderlee.com/concurrency/urlsession-async-await-network-requests-in-swift/)
- [avanderlee — Alamofire vs URLSession](https://www.avanderlee.com/swift/alamofire-vs-urlsession/)
- [serverless.lk — Certificate pinning, the right way](https://serverless.lk/certificate-pinning-in-ios-the-right-way/)
- [NowSecure — ATS guide](https://www.nowsecure.com/blog/2017/08/31/security-analysts-guide-nsapptransportsecurity-nsallowsarbitraryloads-app-transport-security-ats-exceptions/)
- [Apple dev forums — Self-signed cert + ATS](https://developer.apple.com/forums/thread/65361)
- [Starscream (WebSocket)](https://github.com/daltoniam/Starscream)
- [State of Swift WebSockets (Dept Agency)](https://engineering.deptagency.com/state-of-swift-websockets)

### Hardware SDKs
- [StarPRNT SDK for iOS (Swift)](https://github.com/star-micronics/StarPRNT-SDK-iOS-Swift)
- [Epson MFi approval process](https://epson.com/Support/wa00791)
- [BlockChyp iOS SDK](https://github.com/blockchyp/blockchyp-ios)

### UX & a11y
- [Frank Rausch — Modern iOS Navigation Patterns](https://frankrausch.com/ios-navigation/)
- [Sarunw — SwiftUI bottom sheets with presentationDetents](https://sarunw.com/posts/swiftui-bottom-sheet/)
- [Swift Crafted — SwiftUI accessibility complete guide](https://swiftcrafted.dev/article/swiftui-accessibility-complete-guide-voiceover-dynamic-type-inclusive-design)

### App Store & distribution
- [Runway — Unlisted App Distribution](https://www.runway.team/blog/unlisted-app-distribution-on-the-app-store)
- [Runway — Live App Store & TestFlight review times](https://www.runway.team/appreviewtimes)
- [Foresight — iOS App Distribution Guide 2026](https://foresightmobile.com/blog/ios-app-distribution-guide-2026)
- [Daydreamsoft — iOS submission 2025 guide](https://www.daydreamsoft.com/blog/ios-app-submission-process-a-2025-guide-for-developers)
- [Singular — iOS SDK privacy manifest FAQ](https://support.singular.net/hc/en-us/articles/24045392537243-iOS-SDK-Privacy-manifest-FAQ)
- [Bitrise — Privacy manifest enforcement](https://bitrise.io/blog/post/enforcement-of-apple-privacy-manifest-starting-from-may-1-2024)

### Cross-platform reality check (why we didn't pick them)
- [KMP Bits — iOS 26 Liquid Glass is a game-changer for KMP](https://www.kmpbits.com/posts/ios26-liquid-glass)
- [JetBrains — Compose Multiplatform 1.8.0 GA](https://blog.jetbrains.com/kotlin/2025/05/compose-multiplatform-1-8-0-released-compose-multiplatform-for-ios-is-stable-and-production-ready/)
- [Callstack — Liquid Glass in React Native](https://www.callstack.com/blog/how-to-use-liquid-glass-in-react-native)
- [Expo — Liquid Glass with Expo UI and SwiftUI](https://expo.dev/blog/liquid-glass-app-with-expo-ui-and-swiftui)
- [vagary.tech — Apple Liquid Glass across Flutter/RN/Compose MP](https://vagary.tech/blog/apple-liquid-glass-flutter-react-native-compose-mp)
- [foresightmobile — Cross-platform Liquid Glass support](https://foresightmobile.com/blog/liquid-glass-ui-overvew-cross-platform-support)
- [Volpis — Is Kotlin Multiplatform production-ready in 2026](https://volpis.com/blog/is-kotlin-multiplatform-production-ready/)

### Performance
- [fatbobman — List or LazyVStack](https://fatbobman.com/en/posts/list-or-lazyvstack/)
- [SharpSkill — SwiftUI performance with complex lists](https://sharpskill.dev/en/blog/ios/swiftui-performance-lazyvstack-complex-lists)
- [Jacob's Tech Tavern — Is SwiftUI as fast as UIKit in iOS 26](https://blog.jacobstechtavern.com/p/swiftui-vs-uikit)

### Fonts & typography
- [Inter (OFL)](https://rsms.me/inter/)
- [Barlow (OFL)](https://github.com/jpt/barlow)
- [JetBrains Mono (OFL)](https://www.jetbrains.com/lp/mono/)

### Inspiration — apps nailing Liquid Glass
- [Flighty](https://apps.apple.com/app/id1358823008)
- [Overcast](https://overcast.fm)
- [Things](https://culturedcode.com/things/)
- [Fantastical](https://flexibits.com/fantastical)
- [9to5Mac — 30+ apps with Liquid Glass](https://9to5mac.com/2025/09/26/these-30-apps-feature-a-new-liquid-glass-design-for-ios-26/)

---

## Appendix A — Copy-paste starter snippets

### A1. `GlassEffect` fallback wrapper

```swift
import SwiftUI

public enum BrandGlass {
    case regular, clear

    @available(iOS 26.0, *)
    fileprivate var systemGlass: Glass {
        switch self {
        case .regular: return .regular
        case .clear:   return .clear
        }
    }

    fileprivate var fallbackMaterial: Material {
        switch self {
        case .regular: return .ultraThinMaterial
        case .clear:   return .thinMaterial
        }
    }
}

public extension View {
    func brandGlass<S: Shape>(_ variant: BrandGlass = .regular,
                              in shape: S = Capsule() as! S,
                              tint: Color? = nil) -> some View {
        modifier(BrandGlassModifier(variant: variant, shape: shape, tint: tint))
    }
}

private struct BrandGlassModifier<S: Shape>: ViewModifier {
    let variant: BrandGlass
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            var glass = variant.systemGlass
            if let tint { glass = glass.tint(tint) }
            return AnyView(content.glassEffect(glass, in: shape))
        } else {
            return AnyView(
                content
                    .background(variant.fallbackMaterial, in: shape)
                    .overlay(tint.map { shape.fill($0.opacity(0.15)) })
            )
        }
    }
}
```

### A2. Pinned URLSession

```swift
import Foundation
import CryptoKit

final class PinnedURLSessionDelegate: NSObject, URLSessionDelegate {
    private let pinnedSPKIBase64: Set<String>

    init(pinnedSPKIBase64: Set<String>) {
        self.pinnedSPKIBase64 = pinnedSPKIBase64
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let publicKey = SecCertificateCopyKey(leaf),
              let pubData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let hash = SHA256.hash(data: pubData)
        let b64 = Data(hash).base64EncodedString()
        if pinnedSPKIBase64.contains(b64) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
```

### A3. API envelope

```swift
struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: APIError?
}

struct APIError: Decodable, Error {
    let code: String
    let message: String
}
```

### A4. Observable view model template

```swift
@MainActor
@Observable
final class TicketListViewModel {
    private(set) var tickets: [Ticket] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let repo: TicketRepository

    init(repo: TicketRepository) { self.repo = repo }

    func load() async {
        isLoading = true; defer { isLoading = false }
        do { tickets = try await repo.list() }
        catch { errorMessage = error.localizedDescription }
    }
}
```

### A5. Privacy manifest skeleton

See §22.1. Place at `App/PrivacyInfo.xcprivacy`.

---

## Appendix B — Glossary

| Term | Meaning |
|---|---|
| **ATS** | App Transport Security — iOS's TLS-enforcement layer. |
| **APNs** | Apple Push Notification service. |
| **ActivityKit** | Framework for Live Activities (Lock Screen + Dynamic Island). |
| **BGTaskScheduler** | iOS's background-task registrar (replacement-ish for WorkManager, but opportunistic). |
| **GRDB** | Swift SQLite wrapper library. |
| **Liquid Glass** | Apple's iOS 26 system material (refractive, lensing, specular-highlighted). |
| **MFi** | "Made for iPhone/iPad" — Apple's accessory approval program for Bluetooth Classic peripherals. |
| **SPKI** | Subject Public Key Info — the hashable part of a cert used for public-key pinning. |
| **@Observable** | Swift 5.9 macro replacing `ObservableObject`; triggers fine-grained SwiftUI re-renders. |
| **Unlisted App Distribution** | App Store listing that's reviewed + signed but hidden from search; accessed via direct link. |

---

**End of plan.** Open questions from §30 need answers before Phase 0 starts. When ready, file CROSS items into `bizarre-crm/TODO.md` per CLAUDE.md's cross-platform rule.
