import Foundation

/// A single product or service line in the tenant's inventory catalog.
///
/// `InventoryItem` is the read model for `GET /inventory` and
/// `GET /inventory/:sku`.  It is used across Inventory, POS, and Tickets
/// features whenever a product must be displayed, searched, or added to a cart.
///
/// ## Monetary values
/// `priceCents` and `costCents` are stored as **integer US cents** (e.g. `$12.50
/// → 1250`).  Always format for display with ``Currency/formatCents(_:code:)``
/// rather than dividing manually, to ensure locale-correct currency symbols and
/// rounding.
///
/// ## Low-stock logic
/// ``isLowStock`` is a derived property comparing ``stockQty`` to
/// ``reorderLevel``.  The reorder level is set per-item by staff in Settings →
/// Inventory.  A value of `0` disables low-stock warnings for that item.
///
/// ## SKU format
/// SKUs must satisfy ``SKUValidator`` constraints (`[A-Z0-9-]{2,40}`).
/// The server normalises to uppercase on write; the client should display as-is.
///
/// ## See Also
/// - ``SKUValidator`` for validating SKU strings before submission.
/// - ``Currency/formatCents(_:code:)`` for monetary display.
public struct InventoryItem: Identifiable, Hashable, Codable, Sendable {
    /// Server-assigned primary key.
    public let id: Int64
    /// Stock-keeping unit — unique within the tenant's catalog.
    public let sku: String
    /// Human-readable product or service name shown in lists and receipts.
    public let name: String
    /// EAN-13, UPC-A, QR, or other scannable code.  `nil` when not assigned.
    public let barcode: String?
    /// Current on-hand quantity.  May be negative if overselling is allowed.
    public let stockQty: Int
    /// Quantity at or below which the item is considered low stock.
    /// `0` disables the low-stock indicator for this item.
    public let reorderLevel: Int
    /// Retail selling price in US cents (e.g. `1250` → $12.50).
    public let priceCents: Int
    /// Landed cost in US cents.  Used for margin calculations; never shown to
    /// customers.
    public let costCents: Int
    /// Last server-side modification timestamp (UTC).
    public let updatedAt: Date

    public init(
        id: Int64,
        sku: String,
        name: String,
        barcode: String? = nil,
        stockQty: Int = 0,
        reorderLevel: Int = 0,
        priceCents: Int = 0,
        costCents: Int = 0,
        updatedAt: Date
    ) {
        self.id = id
        self.sku = sku
        self.name = name
        self.barcode = barcode
        self.stockQty = stockQty
        self.reorderLevel = reorderLevel
        self.priceCents = priceCents
        self.costCents = costCents
        self.updatedAt = updatedAt
    }

    /// `true` when ``stockQty`` is at or below ``reorderLevel``.
    ///
    /// Returns `false` when `reorderLevel == 0`, treating zero as "no threshold
    /// configured" — use `reorderLevel > 0 && isLowStock` if you need to
    /// distinguish "explicitly below threshold" from "threshold not set".
    public var isLowStock: Bool { stockQty <= reorderLevel }
}
