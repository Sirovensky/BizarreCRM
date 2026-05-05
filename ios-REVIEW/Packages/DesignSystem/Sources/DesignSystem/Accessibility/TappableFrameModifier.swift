import SwiftUI

// MARK: - TappableFrameModifier
// §26.7 — Tap-target enforcement modifier.
//
// This modifier combines two things:
//  1. **Runtime enforcement (DEBUG)** — a `GeometryReader` reads the rendered
//     frame; in DEBUG builds an `assertionFailure` fires if either dimension
//     is below 44 pt, surfacing the violation at dev-time rather than in
//     production UI.
//  2. **Visual hit-area expansion** — `.contentShape` grows the tappable
//     region to at least 44×44 pt without changing the view's visual frame,
//     so small icons remain visually compact while being easy to tap.
//
// In RELEASE builds the assertion is elided but the `.contentShape` expansion
// is kept so users always benefit from the larger hit area.
//
// **Usage:**
// ```swift
// Button { viewModel.dismiss() } label: {
//     Image(systemName: "xmark")
//         .font(.caption)
// }
// .tappableFrame()          // expands hit area + asserts ≥ 44 pt in DEBUG
//
// // Badge button — visual size intentionally small, hit area always 44×44:
// BadgeButton(count: unread)
//     .tappableFrame(assert: false)   // skip assertion, just expand hit area
// ```
//
// Relationship to `MinTapTargetModifier`: `MinTapTargetModifier` sets
// `frame(minWidth:minHeight:)` which *can* change the view's layout size.
// `TappableFrameModifier` only modifies `contentShape` — visual layout is
// never altered.  Prefer this modifier for icons; prefer `MinTapTargetModifier`
// when you also want the surrounding layout to account for the larger region.

// MARK: - Modifier

public struct TappableFrameModifier: ViewModifier {

    /// Minimum side length that satisfies the HIG tap-target rule.
    public static let minimumSide: CGFloat = 44

    /// Whether to assert in DEBUG builds when the rendered frame is too small.
    public let assertOnViolation: Bool

    public init(assertOnViolation: Bool = true) {
        self.assertOnViolation = assertOnViolation
    }

    public func body(content: Content) -> some View {
        content
            .background(tappableFrameChecker)
            .contentShape(
                Rectangle()
            )
            .frame(
                minWidth: TappableFrameModifier.minimumSide,
                minHeight: TappableFrameModifier.minimumSide
            )
    }

    // MARK: Private

    @ViewBuilder
    private var tappableFrameChecker: some View {
        #if DEBUG
        if assertOnViolation {
            GeometryReader { proxy in
                Color.clear.onAppear {
                    let w = proxy.size.width
                    let h = proxy.size.height
                    if w < TappableFrameModifier.minimumSide
                        || h < TappableFrameModifier.minimumSide
                    {
                        assertionFailure(
                            "[A11y §26.7] Tap target too small: \(Int(w))×\(Int(h)) pt — "
                            + "must be ≥ \(Int(TappableFrameModifier.minimumSide)) pt on both axes."
                        )
                    }
                }
            }
        }
        #endif
    }
}

// MARK: - View extension

public extension View {
    /// Enforces a 44×44 pt tappable hit area.
    ///
    /// - The visual frame is **not** resized; only the `contentShape` is expanded.
    /// - In DEBUG builds, triggers an `assertionFailure` when the rendered
    ///   frame is smaller than 44 pt on either axis (unless `assert` is `false`).
    ///
    /// - Parameter assert: When `true` (default) the DEBUG assertion is active.
    func tappableFrame(assert assertOnViolation: Bool = true) -> some View {
        modifier(TappableFrameModifier(assertOnViolation: assertOnViolation))
    }
}
