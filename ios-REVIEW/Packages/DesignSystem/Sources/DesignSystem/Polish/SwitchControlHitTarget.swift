import SwiftUI

// §26.9 — SwitchControlHitTarget
// Switch Control users navigate by scanning items one at a time; small or
// tightly-packed targets are especially frustrating because a mis-tap wastes a
// full scan cycle. When `UIAccessibility.isSwitchControlRunning` is true we
// inflate the hit-testing region to a larger minimum (60×60 pt) so every item
// is comfortably large for single-switch or two-switch scanning.
//
// Visual frame is unchanged — only the `contentShape` (hit area) grows.
// The flag is observed live via `onReceive` so the modifier reacts immediately
// if Switch Control is toggled mid-session without an app restart.

// MARK: - SwitchControlHitTargetModifier

/// Enlarges the hit-testing region for Switch Control users.
///
/// The visual frame of the content is unchanged; only the tappable area grows.
///
/// - Standard minimum (HIG): 44×44 pt
/// - Switch Control minimum: 60×60 pt
///
/// **Usage:**
/// ```swift
/// Button { dismiss() } label: {
///     Image(systemName: "xmark")
/// }
/// .switchControlHitTarget()
/// ```
public struct SwitchControlHitTargetModifier: ViewModifier {

    /// Minimum side for standard (non-Switch-Control) mode.
    public static let standardMinimum: CGFloat = 44
    /// Minimum side when Switch Control is running.
    public static let switchControlMinimum: CGFloat = 60

    @State private var isSwitchControlRunning: Bool =
        UIAccessibility.isSwitchControlRunning

    public func body(content: Content) -> some View {
        let side = isSwitchControlRunning
            ? SwitchControlHitTargetModifier.switchControlMinimum
            : SwitchControlHitTargetModifier.standardMinimum

        content
            .contentShape(Rectangle())
            .frame(minWidth: side, minHeight: side)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIAccessibility.switchControlStatusDidChangeNotification
                )
            ) { _ in
                isSwitchControlRunning = UIAccessibility.isSwitchControlRunning
            }
    }
}

// MARK: - View extension

public extension View {

    /// Applies an enlarged hit-testing region when Switch Control is active,
    /// degrading gracefully to the standard 44-pt minimum otherwise.
    ///
    /// Visual layout is not affected; only the `contentShape` changes.
    func switchControlHitTarget() -> some View {
        modifier(SwitchControlHitTargetModifier())
    }
}
