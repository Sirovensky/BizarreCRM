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
/// - `footer` is overridden with return-policy copy (includes return-by date from options)
///
/// **Why pure?** Zero system I/O means tests are deterministic and coverage
/// is cheap. The caller (UI + print dispatch) decides what to do with the payload.
public enum GiftReceiptGenerator {

    /// Returns a `PosReceiptRenderer.Payload` with all price data stripped.
    ///
    /// - Parameters:
    ///   - sale:    The completed sale record.
    ///   - options: Gift-receipt configuration (partial line selection, return-by days).
    ///              Defaults to `.default` (all lines, 30-day window).
    /// - Returns: A gift-receipt payload where all monetary fields are zero
    ///   and the header reads "GIFT RECEIPT".
    public static func buildPayload(
        sale: SaleRecord,
        options: GiftReceiptOptions = .default
    ) -> PosReceiptRenderer.Payload {
        // Filter to included lines (empty set = all lines).
        let sourceLines: [SaleLineRecord]
        if options.includedLineIds.isEmpty {
            sourceLines = sale.lines
        } else {
            sourceLines = sale.lines.filter { options.includedLineIds.contains($0.id) }
        }

        let lines = sourceLines.map { line in
            PosReceiptRenderer.Payload.Line(
                name: line.name,
                sku: line.sku,
                quantity: line.quantity,
                unitPriceCents: 0,       // price stripped
                discountCents: 0,        // discount stripped
                lineTotalCents: 0        // line total stripped
            )
        }

        // Build footer with return-by date from options.
        let returnByDate = options.returnByDateString(from: sale.date)
        let creditNote: String
        switch options.returnCredit {
        case .storeCredit:
            creditNote = "Gift returns are credited as store credit."
        case .originalCard:
            creditNote = "Gift returns are refunded to the original card on file."
        }
        let footer = "Return or exchange by \(returnByDate). No price information is displayed at the request of the gift giver. \(creditNote)"

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
            footer: footer
        )
    }

    // MARK: - Internal helpers (visible for testing)

    /// The default return-policy footer (used when no options are provided).
    static let giftReceiptFooter = "This item may be returned or exchanged within 30 days with this receipt. No price information is displayed at the request of the gift giver."
}
