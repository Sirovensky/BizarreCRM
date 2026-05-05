import Foundation

// MARK: - §6.12 Serial Status Calculator (pure)

/// Pure helper — no UIKit / network dependencies.
/// Aggregates status counts for a collection of serialized items per SKU.
public enum SerialStatusCalculator {

    // MARK: - Status count

    public struct StatusCount: Sendable, Equatable {
        public let sku: String
        public let available: Int
        public let reserved: Int
        public let sold: Int
        public let returned: Int
        public let total: Int

        public init(sku: String, available: Int, reserved: Int, sold: Int, returned: Int) {
            self.sku = sku
            self.available = available
            self.reserved = reserved
            self.sold = sold
            self.returned = returned
            self.total = available + reserved + sold + returned
        }
    }

    // MARK: - Aggregate per SKU

    /// Groups serials by parentSKU and returns status counts.
    public static func statusCounts(
        for items: [SerializedItem]
    ) -> [StatusCount] {
        let grouped = Dictionary(grouping: items, by: \.parentSKU)
        return grouped.map { sku, serials in
            counts(sku: sku, serials: serials)
        }.sorted(by: { $0.sku < $1.sku })
    }

    /// Returns status count for a single SKU's serials.
    public static func counts(
        sku: String,
        serials: [SerializedItem]
    ) -> StatusCount {
        var available = 0
        var reserved  = 0
        var sold      = 0
        var returned  = 0
        for item in serials {
            switch item.status {
            case .available: available += 1
            case .reserved:  reserved  += 1
            case .sold:      sold      += 1
            case .returned:  returned  += 1
            }
        }
        return StatusCount(
            sku: sku,
            available: available,
            reserved: reserved,
            sold: sold,
            returned: returned
        )
    }

    /// Filters to only available (sellable) units.
    public static func availableUnits(
        from items: [SerializedItem],
        sku: String
    ) -> [SerializedItem] {
        items.filter { $0.parentSKU == sku && $0.status == .available }
    }
}
