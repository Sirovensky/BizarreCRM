import Foundation

// MARK: - LowStockAlert

/// Immutable value type representing a single low-stock violation.
///
/// Produced by `LowStockChecker` when an inventory item's on-hand quantity
/// falls at or below its effective threshold.
public struct LowStockAlert: Sendable, Identifiable, Equatable {

    // MARK: Stored properties

    /// Stable identity matching the source `InventoryListItem.id`.
    public let itemId: Int64
    /// Human-readable item name.
    public let itemName: String
    /// Optional stock-keeping unit.
    public let sku: String?
    /// Quantity currently on hand.
    public let currentQty: Int
    /// Threshold that was breached.
    public let threshold: Int
    /// Whether the threshold came from a per-item override (`true`) or the
    /// global default (`false`).
    public let isOverrideThreshold: Bool

    // MARK: Identifiable

    public var id: Int64 { itemId }

    // MARK: Derived

    /// How many units short the item is relative to its threshold.
    /// Always >= 0.
    public var shortageBy: Int { max(0, threshold - currentQty) }

    /// Severity bucket — useful for visual triage.
    public var severity: Severity {
        switch shortageBy {
        case 0: return .atThreshold
        case 1...5: return .low
        default: return .critical
        }
    }

    // MARK: Init

    public init(
        itemId: Int64,
        itemName: String,
        sku: String?,
        currentQty: Int,
        threshold: Int,
        isOverrideThreshold: Bool
    ) {
        self.itemId = itemId
        self.itemName = itemName
        self.sku = sku
        self.currentQty = currentQty
        self.threshold = threshold
        self.isOverrideThreshold = isOverrideThreshold
    }

    // MARK: - Severity

    public enum Severity: Sendable, Equatable, CaseIterable {
        /// On hand is exactly at the threshold.
        case atThreshold
        /// Short by 1-5 units.
        case low
        /// Short by more than 5 units.
        case critical
    }
}
