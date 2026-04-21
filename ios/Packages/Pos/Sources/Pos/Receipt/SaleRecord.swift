import Foundation

/// §16 — Minimal sale record used by the gift-receipt and reprint flows.
/// This is a local read model populated from the server response to
/// `POST /pos/sale/finalize` or from the `GET /sales/search` endpoint.
///
/// All money is in cents (never `Double`).
public struct SaleRecord: Identifiable, Equatable, Sendable {
    public let id: Int64
    /// Server-assigned human-readable receipt number (e.g. "R-20240420-0001").
    public let receiptNumber: String
    public let date: Date
    public let customerName: String?
    public let customerPhone: String?
    public let lines: [SaleLineRecord]
    public let subtotalCents: Int
    public let discountCents: Int
    public let taxCents: Int
    public let tipCents: Int
    public let feesCents: Int
    public let totalCents: Int
    public let tenders: [SaleTenderRecord]
    public let currencyCode: String

    public init(
        id: Int64,
        receiptNumber: String,
        date: Date,
        customerName: String? = nil,
        customerPhone: String? = nil,
        lines: [SaleLineRecord],
        subtotalCents: Int,
        discountCents: Int = 0,
        taxCents: Int = 0,
        tipCents: Int = 0,
        feesCents: Int = 0,
        totalCents: Int,
        tenders: [SaleTenderRecord] = [],
        currencyCode: String = "USD"
    ) {
        self.id            = id
        self.receiptNumber = receiptNumber
        self.date          = date
        self.customerName  = customerName
        self.customerPhone = customerPhone
        self.lines         = lines
        self.subtotalCents = subtotalCents
        self.discountCents = discountCents
        self.taxCents      = taxCents
        self.tipCents      = tipCents
        self.feesCents     = feesCents
        self.totalCents    = totalCents
        self.tenders       = tenders
        self.currencyCode  = currencyCode
    }
}

// MARK: - SaleLineRecord

public struct SaleLineRecord: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let sku: String?
    public let quantity: Int
    public let unitPriceCents: Int
    public let discountCents: Int
    public let lineTotalCents: Int

    public init(
        id: Int64,
        name: String,
        sku: String? = nil,
        quantity: Int,
        unitPriceCents: Int,
        discountCents: Int = 0,
        lineTotalCents: Int
    ) {
        self.id            = id
        self.name          = name
        self.sku           = sku
        self.quantity      = quantity
        self.unitPriceCents = unitPriceCents
        self.discountCents = discountCents
        self.lineTotalCents = lineTotalCents
    }
}

// MARK: - SaleTenderRecord

public struct SaleTenderRecord: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let method: String
    public let amountCents: Int
    public let last4: String?

    public init(id: Int64, method: String, amountCents: Int, last4: String? = nil) {
        self.id          = id
        self.method      = method
        self.amountCents = amountCents
        self.last4       = last4
    }
}

// MARK: - SaleSummary (search results)

/// Lightweight version of a sale for display in the reprint search list.
public struct SaleSummary: Identifiable, Equatable, Hashable, Sendable {
    public let id: Int64
    public let receiptNumber: String
    public let date: Date
    public let customerName: String?
    public let totalCents: Int

    public init(id: Int64, receiptNumber: String, date: Date, customerName: String?, totalCents: Int) {
        self.id            = id
        self.receiptNumber = receiptNumber
        self.date          = date
        self.customerName  = customerName
        self.totalCents    = totalCents
    }
}

// MARK: - Codable conformances for API decoding

extension SaleRecord: Codable {}
extension SaleLineRecord: Codable {}
extension SaleTenderRecord: Codable {}
extension SaleSummary: Codable {}
