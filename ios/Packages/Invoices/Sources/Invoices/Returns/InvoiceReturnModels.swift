import Foundation

// §7.7 Invoice customer return flow — models
// Endpoint: POST /api/v1/refunds { invoice_id, lines, reason }
// Non-BlockChyp tenders only (cash / store_credit / gift_card).
// BlockChyp refund with token is Agent-2 / hardware work — deferred.

// MARK: - Restock disposition

/// Per-item disposition on return: goes back to salable stock, scrap bin, or damaged bin.
public enum RestockDisposition: String, CaseIterable, Sendable, Identifiable, Hashable {
    case salable  = "salable"
    case scrap    = "scrap"
    case damaged  = "damaged"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .salable:  return "Return to stock"
        case .scrap:    return "Scrap"
        case .damaged:  return "Damaged bin"
        }
    }

    public var systemImage: String {
        switch self {
        case .salable:  return "checkmark.circle"
        case .scrap:    return "trash"
        case .damaged:  return "exclamationmark.triangle"
        }
    }
}

// MARK: - Return line item

/// A line item on an invoice that can be selected for return from Invoice detail.
public struct InvoiceReturnLine: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let displayName: String
    public let sku: String?
    /// Original quantity on the invoice (integer for simplicity; decimals deferred).
    public let originalQty: Int
    /// Unit price in cents.
    public let unitPriceCents: Int
    /// Whether this line is selected for return.
    public var isSelected: Bool
    /// How many units to return (1…originalQty).
    public var qtyToReturn: Int
    /// Restock disposition for returned units.
    public var disposition: RestockDisposition

    public init(
        id: Int64,
        displayName: String,
        sku: String? = nil,
        originalQty: Int,
        unitPriceCents: Int,
        isSelected: Bool = false,
        qtyToReturn: Int? = nil,
        disposition: RestockDisposition = .salable
    ) {
        self.id = id
        self.displayName = displayName
        self.sku = sku
        self.originalQty = max(1, originalQty)
        self.unitPriceCents = max(0, unitPriceCents)
        self.isSelected = isSelected
        self.qtyToReturn = min(qtyToReturn ?? max(1, originalQty), max(1, originalQty))
        self.disposition = disposition
    }

    /// Refund credit for this line in cents (unit price × qty, before restocking fee).
    public var grossRefundCents: Int { unitPriceCents * qtyToReturn }
}

// MARK: - Restocking fee policy

/// Tenant-configurable restocking fee per item class.
/// Stored server-side in `settings/restocking-fee`; pulled at session startup.
/// Fee is applied to each returned line as a deduction from the gross refund.
public struct RestockingFeePolicy: Codable, Sendable, Hashable {
    /// Flat fee in cents per returned unit (applied once per line-item returned).
    public let flatFeeCentsPerUnit: Int?
    /// Percentage of line gross amount (e.g. 0.15 = 15%).
    public let percentOfLine: Double?
    /// Item classes this policy applies to (nil = applies to all).
    public let itemClasses: [String]?
    /// If true, fee is waived when the item is returned within `noFeeWindowDays` days.
    public let noFeeWindowDays: Int?

    public init(
        flatFeeCentsPerUnit: Int? = nil,
        percentOfLine: Double? = nil,
        itemClasses: [String]? = nil,
        noFeeWindowDays: Int? = nil
    ) {
        self.flatFeeCentsPerUnit = flatFeeCentsPerUnit
        self.percentOfLine = percentOfLine
        self.itemClasses = itemClasses
        self.noFeeWindowDays = noFeeWindowDays
    }

    enum CodingKeys: String, CodingKey {
        case flatFeeCentsPerUnit = "flat_fee_cents_per_unit"
        case percentOfLine       = "percent_of_line"
        case itemClasses         = "item_classes"
        case noFeeWindowDays     = "no_fee_window_days"
    }

    /// Compute restocking fee in cents for a given line.
    /// - Parameters:
    ///   - grossCents: Gross refund for the line (unitPrice × qty).
    ///   - qtyReturned: Number of units returned.
    ///   - itemClass: Item class identifier (nil = always applies if policy has no class filter).
    ///   - daysSincePurchase: Days since the original sale; used for no-fee window.
    /// - Returns: Restocking fee in cents (non-negative).
    public func fee(
        grossCents: Int,
        qtyReturned: Int,
        itemClass: String? = nil,
        daysSincePurchase: Int = 0
    ) -> Int {
        // Class filter: if policy restricts to certain classes, skip if not matching.
        if let classes = itemClasses, !classes.isEmpty {
            guard let cls = itemClass, classes.contains(cls) else { return 0 }
        }
        // No-fee window: if within window, no fee.
        if let window = noFeeWindowDays, daysSincePurchase <= window { return 0 }

        var fee = 0
        if let flatPerUnit = flatFeeCentsPerUnit {
            fee += flatPerUnit * qtyReturned
        }
        if let pct = percentOfLine {
            fee += Int((Double(grossCents) * pct).rounded())
        }
        // Fee cannot exceed the gross refund.
        return min(fee, max(0, grossCents))
    }
}

// MARK: - Return tender options (non-BlockChyp)

/// Refund method options available for invoice returns.
/// BlockChyp card refund (with token) is deferred to Agent-2 / hardware phase.
public enum ReturnTender: String, CaseIterable, Sendable, Identifiable {
    case cash        = "cash"
    case storeCredit = "store_credit"
    case giftCard    = "gift_card"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cash:        return "Cash"
        case .storeCredit: return "Store Credit"
        case .giftCard:    return "Gift Card"
        }
    }

    public var systemImage: String {
        switch self {
        case .cash:        return "banknote"
        case .storeCredit: return "creditcard.fill"
        case .giftCard:    return "gift"
        }
    }
}

// MARK: - Fraud threshold

/// Tenant-level threshold above which a manager PIN is required to process a return.
/// Defaults to $200 (20 000 cents). Configurable via `settings/return-policy`.
public let kReturnManagerPinThresholdCents: Int = 20_000
