import SwiftUI
import Core

/// §Agent-E — iPad-only `ViewModifier` that animates the cart column width
/// from 420 pt to 0 when `isCollapsed` is `true`.
///
/// Spring spec: `response: 0.24, dampingFraction: 0.8` — matches the POS
/// redesign motion brief. Under the system `.reduceMotion` preference the
/// animation falls through to a 150 ms opacity crossfade via
/// `ReduceMotionFallback.animation(...)`.
///
/// iPhone: modifier is a no-op (cart column is full-screen, not split).
/// iPad:   `frame(width: isCollapsed ? 0 : 420, alignment: .leading)` is
///         applied unconditionally; `clipped()` hides overflow during the
///         spring over-shoot.
///
/// Usage:
/// ```swift
/// cartColumn
///     .modifier(PosCartCollapseModifier(isCollapsed: isPaid))
/// ```
public struct PosCartCollapseModifier: ViewModifier {

    // MARK: - Layout constants (exposed for unit tests)

    /// Target width when the cart column is collapsed (animation end state).
    public static let collapsedWidth: CGFloat = 0

    /// Target width when the cart column is expanded.
    public static let expandedWidth: CGFloat = 420

    /// Spring response duration in seconds (normal motion).
    public static let springResponse: Double = 0.24

    /// Spring damping fraction (normal motion).
    public static let springDampingFraction: Double = 0.8

    /// Duration of the linear fallback animation when Reduce Motion is on.
    public static let reduceMotionDuration: Double = 0.15

    // MARK: - Instance state

    /// When `true` the cart column animates to zero width.
    public let isCollapsed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(isCollapsed: Bool) {
        self.isCollapsed = isCollapsed
    }

    public func body(content: Content) -> some View {
        if sizeClass == .regular {
            // iPad path: animate width collapse.
            content
                .frame(width: isCollapsed ? Self.collapsedWidth : Self.expandedWidth, alignment: .leading)
                .clipped()
                .opacity(isCollapsed && reduceMotion ? 0 : 1)
                .animation(effectiveAnimation, value: isCollapsed)
        } else {
            // iPhone / compact: pass through unchanged.
            content
        }
    }

    /// Spring animation for regular motion; 150ms opacity crossfade when
    /// `.reduceMotion` is active.
    private var effectiveAnimation: Animation {
        if reduceMotion {
            return .linear(duration: Self.reduceMotionDuration)
        }
        return .spring(response: Self.springResponse, dampingFraction: Self.springDampingFraction)
    }
}

// MARK: - Convenience extension

public extension View {
    /// Applies `PosCartCollapseModifier`. On iPhone (compact size class) the
    /// modifier is a structural no-op.
    func posCartCollapse(isCollapsed: Bool) -> some View {
        modifier(PosCartCollapseModifier(isCollapsed: isCollapsed))
    }
}
