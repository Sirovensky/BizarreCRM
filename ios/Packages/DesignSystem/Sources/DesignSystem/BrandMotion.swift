import SwiftUI

// MARK: - BrandMotion (§30.6)

/// Canonical motion tokens for BizarreCRM.
///
/// Every animation in the app pulls from this table — never an inline
/// `.animation(...)` with magic numbers. The `reduceMotion` variants
/// return `.easeInOut(duration: 0)` so views become instant snapshots
/// when the system Reduce Motion flag is set.
///
/// Usage:
/// ```swift
/// .animation(BrandMotion.sheet, value: isPresented)
/// .animation(BrandMotion.reduceMotion(for: .tab), value: selectedTab)
/// ```
public enum BrandMotion {

    // MARK: - Durations (§30.6 token names)

    /// FAB appear / disappear — 160ms spring.
    public static let fab:            Animation = .spring(response: 0.28, dampingFraction: 0.78)

    /// Sticky banner slide-in (offline, sync) — 200ms easeInOut.
    public static let banner:         Animation = .easeInOut(duration: 0.20)

    /// Sheet present / dismiss — 340ms spring.
    public static let sheet:          Animation = .spring(response: 0.45, dampingFraction: 0.88)

    /// Tab-bar selection highlight — 220ms spring.
    public static let tab:            Animation = .spring(response: 0.35, dampingFraction: 0.82)

    /// Chip toggle / pill swap — 120ms snappy.
    public static let chip:           Animation = .snappy(duration: 0.12)

    // MARK: - Additional named tokens

    /// Offline banner fade — alias of `banner`.
    public static let offlineBanner:  Animation = banner

    /// Sync pulse ring (repeat) — 600ms looping for "new" badges (scale 1.0 ↔ 1.05).
    public static let syncPulse:      Animation = .easeInOut(duration: 0.60).repeatForever(autoreverses: true)

    /// Pulse for "new" badge — scale 1.0 ↔ 1.05, 600ms repeating.
    /// NOTE: `pulse` and `sharedElement` extended tokens live in Motion/MotionCatalog.swift.

    /// List row insert — 240ms smooth.
    public static let listInsert:     Animation = .smooth(duration: 0.24)

    /// Status pill swap — bouncy, 450ms.
    public static let statusChange:   Animation = .bouncy(duration: 0.45, extraBounce: 0.15)

    /// Barcode scan success flash — 180ms snappy.
    public static let barcodeSuccess: Animation = .snappy(duration: 0.18)

    /// Small status UI elements (strength meter segments) — 180ms snappy.
    public static let snappy:         Animation = .snappy(duration: 0.18)

    // MARK: - Reduce Motion

    /// Returns the canonical token for `kind`, or `.easeInOut(duration: 0)` when
    /// the system Reduce Motion flag is active. Prefer this over raw tokens at
    /// call-sites that don't already observe `@Environment(\.accessibilityReduceMotion)`.
    ///
    /// ```swift
    /// // In a View:
    /// @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// let anim = BrandMotion.reduceMotion(for: .fab, reducedIfNeeded: reduceMotion)
    /// ```
    public static func reduceMotion(
        for kind: Kind,
        reducedIfNeeded reduceMotion: Bool
    ) -> Animation {
        reduceMotion ? .easeInOut(duration: 0) : kind.animation
    }

    // MARK: - Kind enum

    /// Enumeration of named motion tokens for type-safe `reduceMotion(for:)` use.
    public enum Kind: Sendable {
        case fab, banner, sheet, tab, chip, listInsert, statusChange, barcodeSuccess, snappy

        public var animation: Animation {
            switch self {
            case .fab:            return BrandMotion.fab
            case .banner:         return BrandMotion.banner
            case .sheet:          return BrandMotion.sheet
            case .tab:            return BrandMotion.tab
            case .chip:           return BrandMotion.chip
            case .listInsert:     return BrandMotion.listInsert
            case .statusChange:   return BrandMotion.statusChange
            case .barcodeSuccess: return BrandMotion.barcodeSuccess
            case .snappy:         return BrandMotion.snappy
            }
        }
    }
}

// MARK: - ReduceMotionAnimation view modifier

/// Applies a BrandMotion token, collapsing to instant when Reduce Motion is on.
///
/// ```swift
/// myView.brandAnimation(.fab, value: isFabVisible)
/// ```
public extension View {
    func brandAnimation<V: Equatable>(_ kind: BrandMotion.Kind, value: V) -> some View {
        modifier(BrandAnimationModifier(kind: kind, value: value))
    }
}

private struct BrandAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: BrandMotion.Kind
    let value: V

    func body(content: Content) -> some View {
        content.animation(
            BrandMotion.reduceMotion(for: kind, reducedIfNeeded: reduceMotion),
            value: value
        )
    }
}
