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

    func body(content: Content) -> some View {
        #if DEBUG
        return glassBodyDebug(content: content)
        #else
        return glassBody(content: content)
        #endif
    }

    @ViewBuilder
    private func glassBody(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            applyGlass(content: content)
        } else {
            applyFallback(content: content)
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
