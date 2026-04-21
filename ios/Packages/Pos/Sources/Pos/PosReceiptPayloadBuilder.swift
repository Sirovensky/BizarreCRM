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

    @MainActor
    static func build(cart: Cart, date: Date = Date(), currencyCode: String = "USD") -> PosReceiptRenderer.Payload {
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

        return PosReceiptRenderer.Payload(
            merchant: PosReceiptRenderer.Payload.Merchant(name: merchantName),
            date: date,
            customerName: cart.customer?.displayName,
            orderNumber: nil,
            lines: lines,
            subtotalCents: cart.subtotalCents,
            discountCents: 0,
            feesCents: 0,
            taxCents: cart.taxCents,
            tipCents: 0,
            totalCents: cart.totalCents,
            tenders: [
                PosReceiptRenderer.Payload.Tender(
                    method: "Placeholder — pending §17.3",
                    amountCents: cart.totalCents
                )
            ],
            currencyCode: currencyCode,
            footer: "Thank you!"
        )
    }
}
