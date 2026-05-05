import Foundation
import Networking

// MARK: - LowStockChecker

/// Pure, stateless helper that evaluates an inventory list against a threshold
/// configuration and returns low-stock alerts.
///
/// No network or UIKit dependencies — safe to call on any actor.
public enum LowStockChecker {

    // MARK: Primary API

    /// Evaluates every item in `items` against `threshold` and returns alerts
    /// for all items whose on-hand quantity is at or below their effective threshold.
    ///
    /// - Parameters:
    ///   - items: Full inventory list to evaluate.
    ///   - threshold: Threshold configuration (global default + per-item overrides).
    /// - Returns: Alerts sorted by severity (critical first), then by shortage descending,
    ///   then by item name ascending. Items with `reorderLevel == 0` or `nil` AND no
    ///   per-item override are excluded — a zero global default still triggers alerts
    ///   when an override exists for the item.
    public static func alerts(
        for items: [InventoryListItem],
        threshold: LowStockThreshold
    ) -> [LowStockAlert] {
        items
            .compactMap { item in alert(for: item, threshold: threshold) }
            .sorted(by: sortOrder)
    }

    /// Evaluates a single item. Returns `nil` when the item is not low-stock.
    public static func alert(
        for item: InventoryListItem,
        threshold: LowStockThreshold
    ) -> LowStockAlert? {
        let hasOverride = threshold.overrides[item.id] != nil
        let effectiveThreshold: Int

        if hasOverride {
            effectiveThreshold = threshold.threshold(forItemId: item.id)
        } else {
            // Skip items with no override when the item's own reorderLevel is 0/nil
            // AND the global default is also 0 — nothing useful to alert on.
            let reorder = item.reorderLevel ?? 0
            let global = threshold.globalDefault
            // Use the higher of the item's own reorder level and the global default,
            // so the global default only tightens — it never silently ignores items
            // that already have a positive reorder level.
            effectiveThreshold = max(reorder, global)
            guard effectiveThreshold > 0 else { return nil }
        }

        let currentQty = item.inStock ?? 0
        guard currentQty <= effectiveThreshold else { return nil }

        return LowStockAlert(
            itemId: item.id,
            itemName: item.displayName,
            sku: item.sku,
            currentQty: currentQty,
            threshold: effectiveThreshold,
            isOverrideThreshold: hasOverride
        )
    }

    // MARK: Private helpers

    private static func sortOrder(_ lhs: LowStockAlert, _ rhs: LowStockAlert) -> Bool {
        let lSev = severityRank(lhs.severity)
        let rSev = severityRank(rhs.severity)
        if lSev != rSev { return lSev > rSev }
        if lhs.shortageBy != rhs.shortageBy { return lhs.shortageBy > rhs.shortageBy }
        return lhs.itemName.localizedCompare(rhs.itemName) == .orderedAscending
    }

    private static func severityRank(_ severity: LowStockAlert.Severity) -> Int {
        switch severity {
        case .critical: return 2
        case .low: return 1
        case .atThreshold: return 0
        }
    }
}
