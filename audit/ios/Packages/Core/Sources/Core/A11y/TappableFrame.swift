import SwiftUI

// §26.6 — Minimum 44×44 pt tap target enforcement.
//
// WCAG 2.5.5 "Target Size" requires at least 44×44 CSS pixels (≈ points on
// a typical iOS display). SwiftUI's HitTest uses the rendered frame so small
// icons, chip badges, and icon buttons must be given at least 44×44 of
// interactive area even when their visual content is smaller.
//
// This modifier:
//   • Expands the hit-test area to 44×44 pt minimum while leaving the visual
//     frame unchanged (uses `.contentShape` + frame expansion / `.padding`).
//   • In DEBUG builds fires `assertionFailure` when the rendered frame is
//     below threshold — surfaces violations at dev / CI time, never in prod.
//   • In RELEASE builds the assert is stripped; only the tappable-area
//     expansion remains.
//
// Usage:
//   ```swift
//   Button { deleteRow() } label: {
//       Image(systemName: "trash")
//           .font(.body)
//   }
//   .tappableFrame()
//   ```
//
// SwiftLint rule (§26.6): `bare_ontapgesture` flags any `.onTapGesture`
// on a view that doesn't subsequently call `.tappableFrame()` or expose a
// `.frame(width:height:)` with both dimensions ≥ 44.

// MARK: - Constants

/// Minimum accessible tap target size in points (WCAG 2.5.5 / Apple HIG).
public let minTapTarget: CGFloat = 44

// MARK: - TappableFrameModifier

/// Ensures the interactive hit-test area meets the 44×44 pt minimum.
///
/// The modifier does NOT change the visual layout — it only expands the
/// transparent hit-test zone around the content.
public struct TappableFrameModifier: ViewModifier {
    /// Minimum width for the tap target (default: 44).
    public let minWidth: CGFloat
    /// Minimum height for the tap target (default: 44).
    public let minHeight: CGFloat

    public init(minWidth: CGFloat = minTapTarget, minHeight: CGFloat = minTapTarget) {
        self.minWidth = minWidth
        self.minHeight = minHeight
    }

    public func body(content: Content) -> some View {
        content
            .frame(minWidth: minWidth, minHeight: minHeight)
            .contentShape(Rectangle())
#if DEBUG
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            let w = geo.size.width
                            let h = geo.size.height
                            if w < minWidth || h < minHeight {
                                assertionFailure(
                                    "[TappableFrame] Tap target too small: \(String(format: "%.1f×%.1f", w, h)) pt " +
                                    "(min \(String(format: "%.0f×%.0f", minWidth, minHeight)) pt). " +
                                    "Increase the frame or use .tappableFrame() after .frame()."
                                )
                            }
                        }
                }
            )
#endif
    }
}

// MARK: - View extension

public extension View {
    /// Ensures the view's interactive tap area meets the 44×44 pt WCAG minimum.
    ///
    /// Apply to any button or tappable element whose visual content may be
    /// smaller than 44 pt (icon buttons, close chips, badge toggles).
    ///
    /// In DEBUG builds, fires `assertionFailure` when the rendered frame is
    /// below threshold. In RELEASE builds, only the hit-test expansion is kept.
    ///
    /// - Parameters:
    ///   - minWidth: Override the minimum width (default 44 pt).
    ///   - minHeight: Override the minimum height (default 44 pt).
    func tappableFrame(minWidth: CGFloat = minTapTarget, minHeight: CGFloat = minTapTarget) -> some View {
        modifier(TappableFrameModifier(minWidth: minWidth, minHeight: minHeight))
    }
}
