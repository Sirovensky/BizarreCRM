import Foundation

// MARK: - §6.10 Variant Stock Aggregator (pure)

/// Pure helper — no UIKit / network dependencies.
/// Aggregates stock figures across all variants of a parent item.
public enum VariantStockAggregator {

    /// Total units in stock across all provided variants.
    public static func totalStock(variants: [InventoryVariant]) -> Int {
        variants.reduce(0) { $0 + $1.stock }
    }

    /// True when at least one variant has stock > 0.
    public static func isAnyInStock(variants: [InventoryVariant]) -> Bool {
        variants.contains { $0.stock > 0 }
    }

    /// Returns variants grouped by a named attribute key, e.g. "color".
    public static func grouped(
        variants: [InventoryVariant],
        byAttribute key: String
    ) -> [String: [InventoryVariant]] {
        Dictionary(grouping: variants) { variant in
            variant.attributes[key] ?? "Unknown"
        }
    }

    /// Distinct values for a given attribute key, sorted alphabetically.
    public static func distinctValues(
        variants: [InventoryVariant],
        forAttribute key: String
    ) -> [String] {
        let values = Set(variants.compactMap { $0.attributes[key] })
        return values.sorted()
    }
}
