import SwiftUI

// §30 — StaggeredAppear
// Choreography: staggered list-appear cascade +40ms per row, 200ms cap.
// Per §30 spec (line 4703): respects Reduce Motion.

// MARK: - StaggeredAppearModifier

private struct StaggeredAppearModifier: ViewModifier {
    /// Zero-based row index. Determines the delay applied to the entrance.
    let index: Int
    /// Per-item delay increment (seconds). Default is 40ms per spec.
    let step: Double
    /// Maximum total delay cap (seconds). Default is 200ms per spec.
    let cap: Double

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    let delay = min(Double(index) * step, cap)
                    withAnimation(BrandMotion.listItemAppear.delay(delay)) {
                        appeared = true
                    }
                }
            }
    }
}

// MARK: - View extension

public extension View {

    /// Staggers this view's entrance by `index × step`, capped at `cap`.
    ///
    /// Use inside a `ForEach` or `List` to produce a cascading reveal:
    /// ```swift
    /// ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
    ///     TicketRow(item: item)
    ///         .staggeredAppear(index: idx)
    /// }
    /// ```
    ///
    /// Spec §30: +40ms per row, 200ms cap, Reduce Motion collapses to instant.
    ///
    /// - Parameters:
    ///   - index: Zero-based row position within the list.
    ///   - step: Per-item delay increment. Defaults to 0.040 s (40ms).
    ///   - cap: Maximum cumulative delay. Defaults to 0.200 s (200ms).
    func staggeredAppear(
        index: Int,
        step: Double = 0.040,
        cap: Double = 0.200
    ) -> some View {
        modifier(StaggeredAppearModifier(index: index, step: step, cap: cap))
    }
}
