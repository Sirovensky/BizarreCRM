import SwiftUI
#if canImport(Core)
import Core
#endif

// §22.3 — Visible keyboard focus ring.
//
// Hardware-keyboard users on iPad / Mac need to *see* which control has focus.
// SwiftUI's default focus indicator is invisible on most custom shapes; we add
// a soft outline that animates on focus state changes.
//
// Gate: iPad-only by intent (Platform.isCompact == false). On iPhone the ring
// would never be triggered (no Tab key) but is harmless if applied.
//
// Usage:
//   Button("New ticket") { ... }
//       .brandFocusRing()
//
// Respects Reduce Motion: outline still draws, but transition is instant.

public struct FocusRingModifier: ViewModifier {
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cornerRadius: CGFloat
    private let lineWidth: CGFloat

    public init(cornerRadius: CGFloat = 8, lineWidth: CGFloat = 2) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
    }

    public func body(content: Content) -> some View {
        content
            .focusable(true)
            .focused($isFocused)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(isFocused ? 0.85 : 0),
                        lineWidth: lineWidth
                    )
                    .padding(-2)
                    .allowsHitTesting(false)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: isFocused)
            }
    }
}

public extension View {
    /// Visible keyboard-focus outline. iPad / Mac primary use; harmless on iPhone.
    ///
    /// - Parameters:
    ///   - cornerRadius: Outline corner radius (default 8 pt).
    ///   - lineWidth: Outline thickness (default 2 pt).
    func brandFocusRing(cornerRadius: CGFloat = 8, lineWidth: CGFloat = 2) -> some View {
        modifier(FocusRingModifier(cornerRadius: cornerRadius, lineWidth: lineWidth))
    }
}
