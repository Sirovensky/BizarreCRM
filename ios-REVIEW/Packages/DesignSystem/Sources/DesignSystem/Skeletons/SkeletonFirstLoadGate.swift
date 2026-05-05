import SwiftUI

// §29.4 Pagination — "Skeleton rows during first load only."
//
// Most lists make the same mistake: they show skeleton rows on every refresh,
// including pull-to-refresh on a populated list. That flashes the user's data
// off-screen and replaces it with grey bars — visual noise. The right rule is
// "skeleton on the very first paint when we have nothing yet; subsequent
// refreshes use a top progress indicator and keep stale rows in place."
//
// This modifier centralises that rule so callers don't each re-implement
// "isLoading && rowCount == 0".

/// Decision helper for §29.4 — whether a list should currently render
/// skeleton rows or its real content.
public enum SkeletonFirstLoadGate {

    /// `true` only when the list is loading AND has zero rows already on
    /// screen. Returns `false` for pull-to-refresh, background refresh, or
    /// any subsequent fetch where stale rows are visible.
    public static func shouldShowSkeleton(isLoading: Bool, rowCount: Int) -> Bool {
        isLoading && rowCount == 0
    }
}

public extension View {
    /// Apply skeleton overlay only on first load. Pull-to-refresh / background
    /// refresh leave the existing rows in place and surface progress via the
    /// caller's own top indicator (per §29.4).
    ///
    /// Usage:
    /// ```swift
    /// List(rows) { row in RowView(row) }
    ///     .skeletonOnFirstLoad(isLoading: vm.isLoading, rowCount: rows.count) {
    ///         SkeletonListRow().repeated(times: 6)
    ///     }
    /// ```
    @ViewBuilder
    func skeletonOnFirstLoad<Skeleton: View>(
        isLoading: Bool,
        rowCount: Int,
        @ViewBuilder skeleton: () -> Skeleton
    ) -> some View {
        if SkeletonFirstLoadGate.shouldShowSkeleton(isLoading: isLoading, rowCount: rowCount) {
            skeleton()
        } else {
            self
        }
    }
}
