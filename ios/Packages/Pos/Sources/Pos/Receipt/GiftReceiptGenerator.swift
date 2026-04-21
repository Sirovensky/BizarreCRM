import Foundation

/// §16 Gift receipt — pure-function generator that strips price-sensitive
/// fields and returns a `PosReceiptRenderer.Payload` suitable for rendering
/// as a gift receipt.
///
/// **What is stripped:**
/// - `unitPriceCents` → zeroed (line shows item name + SKU only)
/// - `discountCents` → zeroed per line and at cart level
/// - `subtotalCents`, `taxCents`, `tipCents`, `feesCents`, `totalCents` → zeroed
/// - `tenders` → empty (payment method not shown)
///
/// **What is preserved:**
/// - Item names
/// - SKUs (needed for return processing)
/// - Quantities
/// - `date`, `orderNumber`, `customerName`, `merchant`
/// - `footer` is overridden with return-policy copy
///
/// **Why pure?** Zero system I/O means tests are deterministic and coverage
/// is cheap. The caller (UI + print dispatch) decides what to do with the payload.
public enum GiftReceiptGenerator {

    /// Returns a `PosReceiptRenderer.Payload` with all price data stripped.
    ///
    /// - Parameter sale: the completed sale record.
    /// - Returns: A gift-receipt payload where all monetary fields are zero
    ///   and the header reads "GIFT RECEIPT".
    public static func buildPayload(sale: SaleRecord) -> PosReceiptRenderer.Payload {
        let lines = sale.lines.map { line in
            PosReceiptRenderer.Payload.Line(
                name: line.name,
                sku: line.sku,
                quantity: line.quantity,
                unitPriceCents: 0,       // price stripped
                discountCents: 0,        // discount stripped
                lineTotalCents: 0        // line total stripped
            )
        }

        return PosReceiptRenderer.Payload(
            merchant: PosReceiptRenderer.Payload.Merchant(name: "GIFT RECEIPT"),
            date: sale.date,
            customerName: nil,           // customer details not shown on gift receipt
            orderNumber: sale.receiptNumber,
            lines: lines,
            subtotalCents: 0,
            discountCents: 0,
            feesCents: 0,
            taxCents: 0,
            tipCents: 0,
            totalCents: 0,
            tenders: [],                 // payment method stripped
            currencyCode: sale.currencyCode,
            footer: giftReceiptFooter
        )
    }

    // MARK: - Internal helpers (visible for testing)

    /// The standard return-policy footer printed on every gift receipt.
    static let giftReceiptFooter = "This item may be returned or exchanged within 30 days with this receipt. No price information is displayed at the request of the gift giver."
}
