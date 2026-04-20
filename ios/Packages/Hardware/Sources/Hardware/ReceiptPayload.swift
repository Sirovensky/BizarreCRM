import Foundation

/// Pure data model for a POS receipt. Shared between the Pos package
/// (renders receipts for SMS/email/PDF) and the §17.4 receipt printer
/// adapter when it lands (MFi printers ingest the same struct via a
/// `ReceiptRenderer` → `Receipt.Line` adapter).
///
/// Money is always cents-as-Int — never Double. The server receives and
/// returns totals in dollars, but the app canonicalizes to cents the
/// instant a value enters our layer so summation never drifts.
///
/// Fields that are unknown at send time are `nil` rather than empty
/// strings so the renderer can collapse the row entirely ("no discount"
/// → omit the line instead of printing `$0.00`).
public struct ReceiptPayload: Sendable, Equatable {

    /// Merchant display block. Rendered as the top band of the receipt.
    public struct Merchant: Sendable, Equatable {
        public let name: String
        public let address: String?
        public let phone: String?

        public init(name: String, address: String? = nil, phone: String? = nil) {
            self.name = name
            self.address = address
            self.phone = phone
        }
    }

    /// One printed/emailed line. Discount is optional so the renderer can
    /// skip an "includes 0.00 off" row entirely.
    public struct Line: Sendable, Equatable {
        public let name: String
        public let sku: String?
        public let quantity: Int
        public let unitPriceCents: Int
        public let discountCents: Int
        public let lineTotalCents: Int

        public init(
            name: String,
            sku: String? = nil,
            quantity: Int,
            unitPriceCents: Int,
            discountCents: Int = 0,
            lineTotalCents: Int
        ) {
            self.name = name
            self.sku = sku
            self.quantity = max(1, quantity)
            self.unitPriceCents = max(0, unitPriceCents)
            self.discountCents = max(0, discountCents)
            self.lineTotalCents = lineTotalCents
        }
    }

    /// One tender row in the payment breakdown. Card / cash / gift card /
    /// store credit / check all render through the same struct — the
    /// renderer only cares about the label + amount + optional last4.
    public struct Tender: Sendable, Equatable {
        public let method: String
        public let amountCents: Int
        public let last4: String?
        public let authCode: String?

        public init(method: String, amountCents: Int, last4: String? = nil, authCode: String? = nil) {
            self.method = method
            self.amountCents = amountCents
            self.last4 = last4
            self.authCode = authCode
        }
    }

    public let merchant: Merchant
    /// ISO8601 or human-readable — the renderer does not reformat.
    public let date: Date
    /// Invoice/order id. `nil` means "placeholder — real charge pending".
    public let invoiceId: Int64?
    public let orderNumber: String?

    public let lines: [Line]
    public let subtotalCents: Int
    public let discountCents: Int
    public let feesCents: Int
    public let taxCents: Int
    public let tipCents: Int
    public let totalCents: Int

    public let tenders: [Tender]
    public let customerName: String?
    public let footer: String?
    public let currencyCode: String

    public init(
        merchant: Merchant,
        date: Date = Date(),
        invoiceId: Int64? = nil,
        orderNumber: String? = nil,
        lines: [Line],
        subtotalCents: Int,
        discountCents: Int = 0,
        feesCents: Int = 0,
        taxCents: Int,
        tipCents: Int = 0,
        totalCents: Int,
        tenders: [Tender] = [],
        customerName: String? = nil,
        footer: String? = nil,
        currencyCode: String = "USD"
    ) {
        self.merchant = merchant
        self.date = date
        self.invoiceId = invoiceId
        self.orderNumber = orderNumber
        self.lines = lines
        self.subtotalCents = subtotalCents
        self.discountCents = discountCents
        self.feesCents = feesCents
        self.taxCents = taxCents
        self.tipCents = tipCents
        self.totalCents = totalCents
        self.tenders = tenders
        self.customerName = customerName
        self.footer = footer
        self.currencyCode = currencyCode
    }
}
