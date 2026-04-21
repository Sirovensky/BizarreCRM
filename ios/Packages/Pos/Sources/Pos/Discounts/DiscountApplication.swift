import Foundation

/// A single applied discount record attached to a cart line or to the whole cart.
///
/// Produced by `DiscountEngine.apply(cart:rules:)`. Stored on each `CartItem`
/// (via `CartItem.appliedDiscounts`) and on the `Cart` for whole-cart rules.
/// Used to render the discount breakdown in the cart UI and to build the
/// server-side sale payload.
public struct DiscountApplication: Codable, Sendable, Identifiable, Hashable {
    /// Stable id for diff/animation purposes.
    public let id: UUID
    /// The rule that produced this application.
    public let ruleId: String
    /// Human-readable name shown in the cart breakdown row.
    public let ruleName: String
    /// Scope of the originating rule.
    public let scope: DiscountScope
    /// Discount amount in cents.
    public let discountCents: Int
    /// Whether this application required manager approval.
    public let managerApprovalRequired: Bool

    public init(
        id: UUID = UUID(),
        ruleId: String,
        ruleName: String,
        scope: DiscountScope,
        discountCents: Int,
        managerApprovalRequired: Bool = false
    ) {
        self.id = id
        self.ruleId = ruleId
        self.ruleName = ruleName
        self.scope = scope
        self.discountCents = discountCents
        self.managerApprovalRequired = managerApprovalRequired
    }
}
