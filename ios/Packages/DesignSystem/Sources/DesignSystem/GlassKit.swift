import SwiftUI
#if canImport(OSLog)
import OSLog
#endif

public enum BrandGlassVariant: Sendable {
    case regular, clear, identity

    fileprivate var fallbackMaterial: Material {
        switch self {
        case .regular:  return .ultraThinMaterial
        case .clear:    return .thinMaterial
        case .identity: return .regularMaterial
        }
    }
}

// MARK: - .brandGlass modifier

public extension View {
    /// Applies Liquid Glass on iOS 26+, falls back to `.ultraThinMaterial`
    /// on earlier. Call sites never branch on `#available` directly.
    ///
    /// Pass `tint` to tint the glass to a brand hue (primary CTAs, warnings).
    /// Pass `interactive: true` for press-reactive glass (buttons, FABs).
    func brandGlass<S: Shape>(
        _ variant: BrandGlassVariant = .regular,
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(BrandGlassModifier(variant: variant, shape: shape, tint: tint, interactive: interactive))
    }

    /// Capsule-shape convenience.
    func brandGlass(
        _ variant: BrandGlassVariant = .regular,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        brandGlass(variant, in: Capsule(), tint: tint, interactive: interactive)
    }
}

private struct BrandGlassModifier<S: Shape>: ViewModifier {
    let variant: BrandGlassVariant
    let shape: S
    let tint: Color?
    let interactive: Bool

    /// §1.4 — Reduce Transparency: read the a11y flag so we can skip glass.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        #if DEBUG
        return glassBodyDebug(content: content)
        #else
        return glassBody(content: content)
        #endif
    }

    @ViewBuilder
    private func glassBody(content: Content) -> some View {
        // §1.4 Reduce Transparency fallback: pure elevated surface fill, no blur.
        if reduceTransparency {
            applyReduceTransparencyFallback(content: content)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            applyGlass(content: content)
        } else {
            applyFallback(content: content)
        }
    }

    /// §1.4 — Solid fill used when "Reduce Transparency" is enabled in Accessibility settings.
    /// Uses `.brandSurfaceElevated` token (equivalent to Surface1 in BrandColors).
    private func applyReduceTransparencyFallback(content: Content) -> some View {
        content
            .background(Color.bizarreSurface1, in: shape)
            .overlay {
                if let tint {
                    shape.fill(tint.opacity(0.20))
                }
            }
    }

    #if DEBUG
    private static var logger: Logger {
        Logger(subsystem: "com.bizarrecrm", category: "glass-budget")
    }

    @ViewBuilder
    private func glassBodyDebug(content: Content) -> some View {
        glassBody(content: content)
            .onAppear {
                GlassBudgetMonitor.shared.register()
            }
            .onDisappear {
                GlassBudgetMonitor.shared.release()
            }
    }
    #endif

    private func applyGlass(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            return AnyView(applyGlassIOS26(content: content))
        } else {
            return AnyView(applyFallback(content: content))
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func applyGlassIOS26(content: Content) -> some View {
        var glass: Glass = {
            switch variant {
            case .regular:  return .regular
            case .clear:    return .clear
            case .identity: return .identity
            }
        }()
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return content.glassEffect(glass, in: shape)
    }

    private func applyFallback(content: Content) -> some View {
        content
            .background(variant.fallbackMaterial, in: shape)
            .overlay {
                if let tint {
                    shape.fill(tint.opacity(0.15))
                }
            }
    }
}

// MARK: - Debug glass budget monitor (§1.4 + §30)

#if DEBUG
/// Tracks visible `.brandGlass` count across the app. Debug-only.
///
/// Trips `preconditionFailure` past the 6-element ceiling so the violation
/// surfaces immediately in dev / CI snapshot tests. Production builds skip
/// all of this entirely (see `#if DEBUG` gate in `BrandGlassModifier`).
@MainActor
final class GlassBudgetMonitor {
    static let shared = GlassBudgetMonitor()
    private(set) var visible: Int = 0

    func register() {
        visible += 1
        if visible > DesignTokens.Glass.maxPerScreen {
            let msg = "Glass budget exceeded: \(visible) visible (max \(DesignTokens.Glass.maxPerScreen)). Reduce `.brandGlass` usage or wrap siblings in `BrandGlassContainer`."
            #if canImport(OSLog)
            Logger(subsystem: "com.bizarrecrm", category: "glass-budget").fault("\(msg, privacy: .public)")
            #endif
            assertionFailure(msg)
        }
    }

    func release() {
        visible = max(0, visible - 1)
    }
}
#endif

// MARK: - BrandGlassContainer — group adjacent glass surfaces

/// Wrap nearby glass surfaces so they share a sampling region. Required by
/// Apple's HIG for iOS 26 when multiple glass elements sit close together —
/// otherwise they render fighting each other.
public struct BrandGlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: () -> Content

    public init(spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

// MARK: - §19.25 GlassLayerCounter — public diagnostics hook

/// Public facade over `GlassBudgetMonitor` that exposes the active glass-layer
/// count to the diagnostics UI (Settings → Diagnostics → Danger → Glass layer counter).
///
/// In release builds the counter always returns 0 because `GlassBudgetMonitor`
/// is `#if DEBUG` only — the overlay is harmless but shows nothing.
@MainActor
public final class GlassLayerCounter: Sendable {
    public static let shared = GlassLayerCounter()
    private init() {}

    /// Number of `.brandGlass` modifier instances currently on-screen.
    public var activeCount: Int {
        #if DEBUG
        return GlassBudgetMonitor.shared.visible
        #else
        return 0
        #endif
    }
}

// MARK: - Button styles

/// Brand primary CTA — `.glassProminent` on iOS 26, `.borderedProminent` earlier.
/// Use `.tint(.bizarreOrange)` (or red for destructive) at the call site.
public struct BrandGlassProminentButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            AnyView(
                configuration.label
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .brandGlass(.regular, in: Capsule(), tint: .accentColor, interactive: true)
                    .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            )
        } else {
            AnyView(
                configuration.label
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.black)
                    .opacity(configuration.isPressed ? 0.85 : 1.0)
            )
        }
    }
}

public struct BrandGlassButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            AnyView(
                configuration.label
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .brandGlass(.regular, in: Capsule(), interactive: true)
                    .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            )
        } else {
            AnyView(
                configuration.label
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .opacity(configuration.isPressed ? 0.75 : 1.0)
            )
        }
    }
}

public extension ButtonStyle where Self == BrandGlassProminentButtonStyle {
    static var brandGlassProminent: BrandGlassProminentButtonStyle { BrandGlassProminentButtonStyle() }
}

public extension ButtonStyle where Self == BrandGlassButtonStyle {
    static var brandGlass: BrandGlassButtonStyle { BrandGlassButtonStyle() }
}

// MARK: - BrandGlassClearButtonStyle (§30 — low-prominence ghost action)

/// Ghost-clear glass button. Minimum visual footprint — use for secondary /
/// tertiary actions where `.brandGlass` would compete with the primary CTA.
/// Pre-iOS 26: `.ultraThinMaterial` at reduced opacity.
public struct BrandGlassClearButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            AnyView(
                configuration.label
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .brandGlass(.clear, in: Capsule(), interactive: true)
                    .opacity(configuration.isPressed ? 0.70 : 1.0)
                    .animation(.spring(response: 0.20, dampingFraction: 0.85), value: configuration.isPressed)
            )
        } else {
            AnyView(
                configuration.label
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
                    .opacity(configuration.isPressed ? 0.65 : 1.0)
            )
        }
    }
}

public extension ButtonStyle where Self == BrandGlassClearButtonStyle {
    static var brandGlassClear: BrandGlassClearButtonStyle { BrandGlassClearButtonStyle() }
}

// MARK: - §1.4 On-device glass verification helper

/// Reports whether the current device/OS combination renders real Liquid Glass
/// (iOS 26+ `.glassEffect` with GPU refraction) vs the `.ultraThinMaterial`
/// fallback used on older OS versions.
///
/// Call from Settings → Diagnostics or a debug overlay to confirm glass quality.
///
/// - Returns: `true` when iOS 26+ is active, meaning `.glassEffect` will engage
///   full refraction on A14+ chips. Returns `false` pre-iOS 26 (material fallback).
@MainActor
public func brandGlassIsRealRefraction() -> Bool {
    if #available(iOS 26.0, *) { return true }
    return false
}

/// A small diagnostic badge for `#if DEBUG` overlays that shows whether the
/// real Liquid Glass renderer is active on this device.
///
/// Usage (debug overlay):
/// ```swift
/// #if DEBUG
/// GlassQualityBadge().padding()
/// #endif
/// ```
#if DEBUG
public struct GlassQualityBadge: View {
    @State private var isReal: Bool = false

    public init() {}

    public var body: some View {
        Label(
            isReal ? "Liquid Glass ✓" : "Glass fallback",
            systemImage: isReal ? "sparkles" : "sparkles.slash"
        )
        .font(.caption2.bold())
        .foregroundStyle(isReal ? Color.bizarreSuccess : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .task { isReal = await MainActor.run { brandGlassIsRealRefraction() } }
    }
}
#endif

// MARK: - BrandGlassBadge — capsule badge with glass backing (§30)

/// Capsule badge backed by glass. Use for counts, labels, status chips that
/// live on the navigation chrome or over imagery.
///
/// - `variant`: `.regular` (default), `.clear`, or `.identity` (brand tint).
/// - Pre-iOS 26: coloured fill fallback via `BrandGlassVariant.fallbackMaterial`.
public struct BrandGlassBadge: View {
    private let label: String
    private let variant: BrandGlassVariant
    private let tint: Color?

    public init(
        _ label: String,
        variant: BrandGlassVariant = .regular,
        tint: Color? = nil
    ) {
        self.label = label
        self.variant = variant
        self.tint = tint
    }

    /// §30 — three-level glass intensity convenience. Maps the named intensity
    /// onto the underlying `BrandGlassVariant` so call sites can express intent
    /// (`.strong` / `.medium` / `.minimal`) without knowing the variant table.
    public init(
        _ label: String,
        intensity: BrandGlassIntensity,
        tint: Color? = nil
    ) {
        self.init(label, variant: intensity.variant, tint: tint)
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .brandGlass(variant, in: Capsule(), tint: tint)
            .accessibilityLabel(label)
    }
}

// MARK: - Glass blur ladder (§80 Tokens / §292 Glass strength levels)
//
// Seven named blur intensities that cover all sanctioned use-cases.
// Views must pick a named step rather than expressing an inline radius.
// Pre-iOS 26: the `blurRadius` is applied via `.blur(radius:)` as a
// fallback; iOS 26+ Liquid Glass controls its own internal blur so the
// named step is for documentation / pre-iOS-26 parity only.
//
// Usage:
//   myView.blur(radius: GlassBlur.card.radius)  // pre-iOS 26 fallback
//
// SwiftLint `forbid_inline_design_values` flags raw `.blur(radius: <literal>)`
// calls — use `GlassBlur.<step>.radius` instead.
public enum GlassBlur: CaseIterable, Sendable {

    /// 2pt — hairline frost. Barely-there depth cue on dense information rows.
    case hairline

    /// 6pt — subtle card backing. Standard depth for list-row glass cards.
    case subtle

    /// 12pt — card standard. Default for most floating cards and chips.
    case card

    /// 20pt — sheet standard. Modals, popovers, action sheets.
    case sheet

    /// 32pt — navigation chrome. Tab bar, navigation bar, sidebar background.
    case chrome

    /// 48pt — hero overlay. Full-bleed background blur behind modals and
    /// over imagery cards on the dashboard.
    case hero

    /// 72pt — immersive. Onboarding / celebration overlays that fill the whole
    /// screen and need the background to be nearly unrecognisable.
    case immersive

    // MARK: Radius

    /// The `blur(radius:)` value to use in pre-iOS 26 fallback paths.
    public var radius: CGFloat {
        switch self {
        case .hairline:  return 2
        case .subtle:    return 6
        case .card:      return 12
        case .sheet:     return 20
        case .chrome:    return 32
        case .hero:      return 48
        case .immersive: return 72
        }
    }

    // MARK: Reduce-Transparency fallback opacity

    /// The background surface opacity that approximates this blur level when
    /// "Reduce Transparency" is on. Higher blur → higher opacity so depth
    /// cues are still legible without frosted glass.
    public var solidOpacity: Double {
        switch self {
        case .hairline:  return 0.60
        case .subtle:    return 0.70
        case .card:      return 0.80
        case .sheet:     return 0.88
        case .chrome:    return 0.92
        case .hero:      return 0.96
        case .immersive: return 1.00
        }
    }
}

// MARK: - blurStep view modifier

public extension View {
    /// Applies a named `GlassBlur` step via `.blur(radius:)` for pre-iOS 26 paths.
    /// On iOS 26+, prefer `.glassEffect` via `.brandGlass()`; use this only in
    /// non-glass contexts that still need a depth blur (e.g. snapshot backgrounds,
    /// custom screenshot overlays).
    ///
    /// Automatically suppresses the blur when the system "Reduce Transparency"
    /// flag is active, replacing it with an opaque tint at the step's
    /// `solidOpacity`.
    func blurStep(_ step: GlassBlur) -> some View {
        modifier(BlurStepModifier(step: step))
    }
}

private struct BlurStepModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let step: GlassBlur

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color.bizarreSurface1.opacity(step.solidOpacity))
        } else {
            content
                .blur(radius: step.radius)
        }
    }
}
