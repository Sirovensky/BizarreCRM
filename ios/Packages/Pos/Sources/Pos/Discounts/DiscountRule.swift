import Foundation

// MARK: - DiscountScope

/// Defines which cart elements a `DiscountRule` targets.
public enum DiscountScope: String, Codable, Sendable, Hashable, CaseIterable {
    /// Applied once to the entire cart subtotal.
    case whole
    /// Applied per matching cart line item.
    case lineItem
    /// Applied to every line whose item category matches `matcher`.
    case category
    /// Applied to every line whose SKU matches the `matcher` regex.
    case sku
}

// MARK: - DiscountRule

/// A persistent, server-synced discount rule.
///
/// All money values use **cents** (Int) to avoid floating-point drift.
/// Percentages use `Double` 0.0–1.0 (e.g. 0.10 = 10 %).
///
/// Rules can restrict applicability via:
/// - `validFrom` / `validTo` date window
/// - `minQuantity` on a line
/// - `minCartTotalCents` cart threshold
/// - `maxUsesPerCustomer` per-customer cap (enforced server-side; iOS is optimistic)
///
/// `stackable = false` means this rule participates in the
/// "take best for customer" conflict resolution pass (see `DiscountEngine`).
/// `stackable = true` means it piles on top of every other stackable discount.
///
/// `managerApprovalRequired` blocks checkout until a `ManagerPinSheet` is
/// presented and approved.
public struct DiscountRule: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var scope: DiscountScope
    /// Interpretation depends on `scope`:
    /// - `.whole` — ignored
    /// - `.lineItem` — ignored (applies to every line)
    /// - `.category` — exact category name match
    /// - `.sku` — regular-expression matched against `CartItem.sku`
    public var matcher: String
    /// Percentage discount 0.0–1.0.  Mutually exclusive with `discountFlatCents`.
    public var discountPercent: Double?
    /// Fixed discount in cents.  Mutually exclusive with `discountPercent`.
    /// Prefer `discountPercent` for percentage rules; use this for "$5 off" rules.
    public var discountFlatCents: Int?
    /// Minimum line quantity required for the rule to apply (`.lineItem` / `.sku`).
    public var minQuantity: Int?
    /// Minimum cart subtotal (cents) required for the rule to apply.
    public var minCartTotalCents: Int?
    /// Wall-clock window — rule is inert outside this window.
    public var validFrom: Date?
    public var validTo: Date?
    /// Server-enforced per-customer usage cap.  iOS shows a warning when
    /// the limit is reached (from the server error) but does NOT enforce locally.
    public var maxUsesPerCustomer: Int?
    /// When `false`, conflicts with other non-stackable rules are resolved by
    /// choosing the best discount for the customer.  When `true`, this rule
    /// stacks with any other stackable rules.
    public var stackable: Bool
    /// When `true`, cart checkout is blocked until a manager approves via
    /// `ManagerPinSheet`.
    public var managerApprovalRequired: Bool

    public init(
        id: String,
        name: String,
        scope: DiscountScope,
        matcher: String = "",
        discountPercent: Double? = nil,
        discountFlatCents: Int? = nil,
        minQuantity: Int? = nil,
        minCartTotalCents: Int? = nil,
        validFrom: Date? = nil,
        validTo: Date? = nil,
        maxUsesPerCustomer: Int? = nil,
        stackable: Bool = true,
        managerApprovalRequired: Bool = false
    ) {
        self.id = id
        self.name = name
        self.scope = scope
        self.matcher = matcher
        self.discountPercent = discountPercent
        self.discountFlatCents = discountFlatCents
        self.minQuantity = minQuantity
        self.minCartTotalCents = minCartTotalCents
        self.validFrom = validFrom
        self.validTo = validTo
        self.maxUsesPerCustomer = maxUsesPerCustomer
        self.stackable = stackable
        self.managerApprovalRequired = managerApprovalRequired
    }

    // MARK: - Validity helpers

    /// Returns `true` when the rule is currently within its date window.
    public func isValid(at date: Date = .now) -> Bool {
        if let from = validFrom, date < from { return false }
        if let to = validTo, date > to { return false }
        return true
    }

    /// Computes the discount in cents to apply to a single `basis` amount.
    /// Returns 0 when neither `discountPercent` nor `discountFlatCents` is set.
    public func discountCents(forBasis basisCents: Int) -> Int {
        if let pct = discountPercent {
            return Int((Double(basisCents) * pct).rounded())
        }
        if let flat = discountFlatCents {
            return min(flat, basisCents) // never discount below 0
        }
        return 0
    }
}
