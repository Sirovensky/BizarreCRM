import CoreGraphics

// §30 — Skeleton row counts
// Implements "Count: 3-6 skeleton rows typically; list-specific counts tuned
// to viewport" from ActionPlan §30 line 4695.
//
// Centralises the per-context row counts so list screens don't sprinkle
// magic numbers (e.g. `ForEach(0..<5)`) into their loading states. Counts are
// tuned to common viewport heights:
//
// - `.compact`  — small lists / sheets (3 rows)
// - `.list`     — full-screen list scrolls (5 rows)
// - `.dense`    — settings + dense data tables (6 rows)
// - `.grid`     — grid placeholders (8 cells; 2-col × 4 rows or 4-col × 2 rows)
//
// APPEND-ONLY — do not rename or remove existing cases.

// MARK: - SkeletonRowCount

/// Recommended skeleton-row counts per layout context.
public enum SkeletonRowCount: Int, Sendable, CaseIterable {
    /// 3 — short embedded lists (sheets, popovers, dashboard cards).
    case compact = 3
    /// 5 — standard full-screen list scroll viewport.
    case list = 5
    /// 6 — dense data layouts (settings, inventory, reports).
    case dense = 6
    /// 8 — grid placeholders. Treat as cell count rather than row count.
    case grid = 8

    /// Integer count suitable for `ForEach(0..<count)`.
    public var count: Int { rawValue }
}

public extension SkeletonRowCount {
    /// Returns the recommended count for a given content area height in
    /// points. Falls back to `.list` when no break is matched.
    static func forViewportHeight(_ height: CGFloat) -> SkeletonRowCount {
        switch height {
        case ..<240:    return .compact
        case 240..<560: return .list
        default:        return .dense
        }
    }
}
