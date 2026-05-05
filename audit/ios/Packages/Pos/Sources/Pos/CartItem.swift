import Foundation

/// A line item inside the POS cart. `inventoryItemId == nil` marks a
/// free-form custom line (e.g. a loose service, a miscellaneous charge) —
/// everything else points back to the inventory row the line was added
/// from.
///
/// Money is stored as `Decimal` so the totals math doesn't drift when we
/// multiply a 1.99 price by a quantity of 3. Never introduce `Double` into
/// the currency pipeline — that turns 5.97 into 5.9699999… which the cashier
/// has to round away by hand.
public struct CartItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let inventoryItemId: Int64?
    public let name: String
    public let sku: String?
    public let quantity: Int
    public let unitPrice: Decimal
    /// Nil means "inherit the tenant/inventory default tax". Concrete POS
    /// phases will eventually read that default from settings — for
    /// scaffolding we treat `nil` as untaxed so the math is deterministic.
    public let taxRate: Decimal?
    public let discountCents: Int
    public let notes: String?

    public init(
        id: UUID = UUID(),
        inventoryItemId: Int64? = nil,
        name: String,
        sku: String? = nil,
        quantity: Int = 1,
        unitPrice: Decimal,
        taxRate: Decimal? = nil,
        discountCents: Int = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.inventoryItemId = inventoryItemId
        self.name = name
        self.sku = sku
        self.quantity = max(1, quantity)
        self.unitPrice = unitPrice
        self.taxRate = taxRate
        self.discountCents = max(0, discountCents)
        self.notes = notes
    }

    /// Convenience "copy with changes" helper. We never mutate an existing
    /// `CartItem` — the cart replaces rows wholesale. Matches the
    /// immutability rule in `.claude/rules/common-coding-style.md`.
    public func with(
        quantity: Int? = nil,
        unitPrice: Decimal? = nil,
        taxRate: Decimal? = nil,
        discountCents: Int? = nil,
        notes: String? = nil
    ) -> CartItem {
        CartItem(
            id: id,
            inventoryItemId: inventoryItemId,
            name: name,
            sku: sku,
            quantity: quantity ?? self.quantity,
            unitPrice: unitPrice ?? self.unitPrice,
            taxRate: taxRate ?? self.taxRate,
            discountCents: discountCents ?? self.discountCents,
            notes: notes ?? self.notes
        )
    }
}

public extension CartItem {

    /// `quantity × unitPrice − discount`, banker-rounded to cents. This is
    /// the canonical line total used by every downstream display — don't
    /// recompute it elsewhere.
    var lineSubtotalCents: Int {
        let discount = Decimal(discountCents) / 100
        let gross = unitPrice * Decimal(quantity)
        let net = gross - discount
        return CartMath.toCents(net)
    }

    /// `lineSubtotal × taxRate`, rounded to cents. `nil` tax rate → 0.
    var lineTaxCents: Int {
        guard let taxRate else { return 0 }
        let net = Decimal(lineSubtotalCents) / 100
        let tax = net * taxRate
        return CartMath.toCents(tax)
    }
}
