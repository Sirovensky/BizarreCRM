import SwiftUI
import DesignSystem

/// §14 Phase 4 — "Currently clocked in" status badge.
///
/// Renders a compact Liquid Glass pill with a pulsing dot when active.
/// Intended for list rows, toolbar items, and the employee detail card.
///
/// Usage:
/// ```swift
/// ClockedInBadge(isClockedIn: true, elapsed: "2h 15m")
/// ```
public struct ClockedInBadge: View {

    let isClockedIn: Bool
    /// Optional pre-formatted elapsed string (e.g. "2h 15m"). Pass `nil` to
    /// show "Clocked in" without a duration.
    let elapsed: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isClockedIn: Bool, elapsed: String? = nil) {
        self.isClockedIn = isClockedIn
        self.elapsed = elapsed
    }

    public var body: some View {
        if isClockedIn {
            activeBadge
        }
    }

    private var activeBadge: some View {
        HStack(spacing: BrandSpacing.xs) {
            PulsingDot()
                .accessibilityHidden(true)
            Text(elapsed.map { "Clocked in · \($0)" } ?? "Clocked in")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .brandGlass(.regular, in: Capsule())
        .accessibilityLabel(elapsed.map { "Currently clocked in, \($0) elapsed" } ?? "Currently clocked in")
    }
}

// MARK: - PulsingDot

/// A small circle that pulses on `.active` shifts via `@keyframe` if
/// `reduceMotion` is off, otherwise renders as a static dot.
private struct PulsingDot: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.bizarreSuccess)
            .frame(width: 7, height: 7)
            .scaleEffect(pulsing && !reduceMotion ? 1.3 : 1.0)
            .opacity(pulsing && !reduceMotion ? 0.8 : 1.0)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}
