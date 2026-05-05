import Foundation
import Networking

// MARK: - §6.13 Reorder Policy

/// Configuration for automated reorder calculation.
public struct ReorderPolicy: Sendable, Equatable {
    /// Days between PO submission and stock arrival.
    public let leadTimeDays: Int
    /// Extra buffer stock to hold above reorder point.
    public let safetyStock: Int
    /// Minimum order quantity per line.
    public let minOrderQty: Int

    public init(leadTimeDays: Int, safetyStock: Int, minOrderQty: Int) {
        self.leadTimeDays = leadTimeDays
        self.safetyStock = safetyStock
        self.minOrderQty = minOrderQty
    }

    public static let `default` = ReorderPolicy(leadTimeDays: 7, safetyStock: 5, minOrderQty: 1)
}

// MARK: - Reorder Suggestion (engine output)

/// One suggested reorder for a single inventory item.
public struct ReorderEngineSuggestion: Sendable, Identifiable, Equatable {
    public let id: UUID = UUID()
    public let item: InventoryListItem
    /// Suggested qty to order to bring stock to safe level.
    public let suggestedQty: Int
    /// Stock level after the order arrives (projected).
    public let projectedStock: Int

    public init(item: InventoryListItem, suggestedQty: Int, projectedStock: Int) {
        self.item = item
        self.suggestedQty = suggestedQty
        self.projectedStock = projectedStock
    }

    public static func == (lhs: ReorderEngineSuggestion, rhs: ReorderEngineSuggestion) -> Bool {
        lhs.item.id == rhs.item.id && lhs.suggestedQty == rhs.suggestedQty
    }
}

// MARK: - Reorder Suggestion Engine (pure)

/// Pure helper — no UIKit / network dependencies.
/// Given inventory items + a ReorderPolicy, computes which items need reordering and by how much.
public enum ReorderSuggestionEngine {

    /// Compute reorder suggestions for items below their reorder level.
    /// - Parameters:
    ///   - items: Current inventory list.
    ///   - policy: ReorderPolicy defining lead time, safety stock, and min order qty.
    /// - Returns: Suggestions only for items at or below their reorder level, sorted by urgency.
    public static func suggestions(
        items: [InventoryListItem],
        policy: ReorderPolicy
    ) -> [ReorderEngineSuggestion] {
        items.compactMap { item in
            suggestion(for: item, policy: policy)
        }
        .sorted { lhs, rhs in
            // Most urgent first: items furthest below reorder point
            let lhsShortage = (lhs.item.reorderLevel ?? 0) - (lhs.item.inStock ?? 0)
            let rhsShortage = (rhs.item.reorderLevel ?? 0) - (rhs.item.inStock ?? 0)
            return lhsShortage > rhsShortage
        }
    }

    /// Compute suggestion for a single item.
    /// Returns nil when stock is above reorder level.
    public static func suggestion(
        for item: InventoryListItem,
        policy: ReorderPolicy
    ) -> ReorderEngineSuggestion? {
        guard let currentStock = item.inStock,
              let reorderLevel = item.reorderLevel,
              reorderLevel > 0,
              currentStock <= reorderLevel else { return nil }

        // Target stock = reorder level + safety stock (what we want after receiving)
        let targetStock = reorderLevel + policy.safetyStock
        let rawQty = max(targetStock - currentStock, 0)
        // Round up to minOrderQty
        let suggestedQty = max(
            policy.minOrderQty,
            rawQty > 0 ? ceilToMultiple(rawQty, of: policy.minOrderQty) : policy.minOrderQty
        )
        let projectedStock = currentStock + suggestedQty

        return ReorderEngineSuggestion(
            item: item,
            suggestedQty: suggestedQty,
            projectedStock: projectedStock
        )
    }

    // MARK: Helpers

    /// Rounds `value` up to the nearest multiple of `multiple` (≥1).
    private static func ceilToMultiple(_ value: Int, of multiple: Int) -> Int {
        let m = max(1, multiple)
        return ((value + m - 1) / m) * m
    }
}
