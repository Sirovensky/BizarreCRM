import Foundation

/// Bridge between the in-memory `Cart` and `PosReceiptRenderer.Payload`.
/// Kept in its own file so the renderer and the Cart can stay independent —
/// the payload builder is the single place that knows how to spell a POS
/// cart for a receipt surface.
///
/// Used by `PosView.buildPostSaleViewModel` right before charge. The
/// returned payload is immutable, so the post-sale sheet survives any
/// subsequent cart mutation (e.g. the Next-sale clear).
enum PosReceiptPayloadBuilder {

    static let merchantName = "BizarreCRM"

    /// Build a receipt payload from the current cart.
    ///
    /// - Parameters:
    ///   - cart: The cart being checked out.
    ///   - date: Transaction date (defaults to now).
    ///   - currencyCode: ISO 4217 currency code.
    ///   - methodLabel: The cash/card method label (e.g. "Cash", "Visa ••••1234").
    ///     Pass `nil` when all payment was covered by `appliedTenders`.
    ///   - methodAmountCents: Amount paid via the primary payment rail (cash or card).
    ///   - orderNumber: Server-assigned order number once the invoice is created.
    @MainActor
    static func build(
        cart: Cart,
        date: Date = Date(),
        currencyCode: String = "USD",
        methodLabel: String? = nil,
        methodAmountCents: Int? = nil,
        orderNumber: String? = nil
    ) -> PosReceiptRenderer.Payload {
        let lines = cart.items.map { item in
            PosReceiptRenderer.Payload.Line(
                name: item.name,
                sku: item.sku,
                quantity: item.quantity,
                unitPriceCents: CartMath.toCents(item.unitPrice),
                discountCents: item.discountCents,
                lineTotalCents: item.lineSubtotalCents
            )
        }

        // Build the tender list from what's actually on the cart.
        // Applied tenders (gift cards, store credit) are listed first;
        // if the cart is fully tendered with those, the remaining amount
        // is zero and no additional payment-rail row is needed.
        // When a cash or card tender was used the caller passes `methodLabel`
        // and `methodAmountCents` to build the final row.
        var tenders: [PosReceiptRenderer.Payload.Tender] = cart.appliedTenders.map { t in
            PosReceiptRenderer.Payload.Tender(method: t.label, amountCents: t.amountCents)
        }
        if let label = methodLabel, let amount = methodAmountCents, amount > 0 {
            tenders.append(PosReceiptRenderer.Payload.Tender(method: label, amountCents: amount))
        } else if tenders.isEmpty {
            // Fall-through guard: receipt must always have at least one tender row.
            tenders = [PosReceiptRenderer.Payload.Tender(method: "Paid", amountCents: cart.totalCents)]
        }

        return PosReceiptRenderer.Payload(
            merchant: PosReceiptRenderer.Payload.Merchant(name: merchantName),
            date: date,
            customerName: cart.customer?.displayName,
            orderNumber: orderNumber,
            lines: lines,
            subtotalCents: cart.subtotalCents,
            discountCents: cart.effectiveDiscountCents + cart.couponDiscountCents + cart.pricingSavingCents,
            feesCents: cart.feesCents,
            taxCents: cart.taxCents,
            tipCents: cart.tipCents,
            totalCents: cart.totalCents,
            tenders: tenders,
            currencyCode: currencyCode,
            footer: "Thank you!"
        )
    }
}
