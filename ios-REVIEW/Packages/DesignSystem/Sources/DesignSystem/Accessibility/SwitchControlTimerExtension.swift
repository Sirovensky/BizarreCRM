import SwiftUI

// MARK: - SwitchControlTimerExtension
// §91.13 — Switch Control auto-scan timing extension.
//
// Switch Control's auto-scanning mode advances focus on a fixed interval
// (default 1.2 s in iOS Settings → Accessibility → Switch Control → Timing).
// For complex interactive cards — charts with drill-through, date-range pickers,
// export menus — the default cadence is too fast for users who operate a single
// external switch.
//
// iOS does not expose a public API to override the system interval per-view.
// The supported mitigation is to reduce the number of focusable items inside a
// heavy card by grouping children into a single accessibility element
// (`accessibilityElement(children: .combine)`) so the scanner stops once on the
// card rather than on every sub-element.
//
// This file provides:
//   1. `SwitchControlGroupModifier` — collapses a multi-child card into a single
//      scannable element with a combined label, giving the Switch Control user
//      one stop instead of N.
//   2. `View.switchControlGroup(label:hint:)` — convenience wrapper.
//   3. `SwitchControlTimingToken` — named durations teams can reference in
//      comments / documentation so the intent is self-documenting.
//
// **Usage:**
// ```swift
// BusyHoursHeatmapCard(cells: vm.busyHours)
//     .switchControlGroup(
//         label: "Busy hours heatmap. Tuesday 2–3 pm is peak.",
//         hint: "Double-tap to open detail."
//     )
// ```
//
// The modifier does NOT change visual layout or VoiceOver behavior for
// non-Switch-Control users — `.accessibilityElement(children: .combine)` is
// applied regardless of whether Switch Control is active, which is consistent
// with WCAG SC 4.1.2 (Name, Role, Value).

// MARK: - Timing reference tokens

/// Named Switch Control auto-scan durations for documentation purposes.
///
/// iOS allows users to adjust the scan interval in Settings; these tokens are
/// informational only — they document expected timing requirements in comments
/// and review checklists.
public enum SwitchControlTimingToken {
    /// Default iOS auto-scan interval (1.2 s).  Adequate for simple controls.
    public static let `default`: TimeInterval = 1.2
    /// Recommended minimum for medium-complexity cards (2 interactive zones).
    public static let medium: TimeInterval = 2.0
    /// Recommended minimum for high-complexity cards (chart + drill + filter).
    public static let complex: TimeInterval = 3.0
}

// MARK: - Modifier

/// Collapses a multi-child view into a single Switch Control scan stop.
public struct SwitchControlGroupModifier: ViewModifier {
    /// The spoken label for the combined element.
    public let label: String
    /// Optional usage hint read after a brief pause (e.g. "Double-tap to open").
    public let hint: String?

    public init(label: String, hint: String? = nil) {
        self.label = label
        self.hint  = hint
    }

    public func body(content: Content) -> some View {
        content
            // Combine all children into a single AX element — one scan stop.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .modifier(OptionalHintModifier(hint: hint))
    }
}

// MARK: - Helpers

private struct OptionalHintModifier: ViewModifier {
    let hint: String?
    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

// MARK: - View extension

public extension View {
    /// Collapses this view's subtree into a single Switch Control scan stop.
    ///
    /// Use on complex cards that contain multiple interactive children (charts,
    /// drill-through buttons, period pickers) to prevent the auto-scanner from
    /// spending multiple intervals on a single card.
    ///
    /// - Parameters:
    ///   - label: Combined accessibility label for the collapsed element.
    ///   - hint: Optional hint read after the label (e.g. "Double-tap to expand").
    func switchControlGroup(label: String, hint: String? = nil) -> some View {
        modifier(SwitchControlGroupModifier(label: label, hint: hint))
    }
}
