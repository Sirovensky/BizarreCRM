import Foundation

// MARK: - ReceiptLineItem

/// A single parsed line item from a receipt.
public struct ReceiptLineItem: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let description: String
    public let amountCents: Int?

    public init(id: UUID = UUID(), description: String, amountCents: Int?) {
        self.id = id
        self.description = description
        self.amountCents = amountCents
    }
}

// MARK: - ReceiptOCRResult

/// Structured data extracted from a receipt image.
public struct ReceiptOCRResult: Sendable {
    public let merchantName: String?
    public let totalCents: Int?
    public let taxCents: Int?
    public let subtotalCents: Int?
    public let transactionDate: Date?
    public let lineItems: [ReceiptLineItem]?
    public let rawText: String

    public init(
        merchantName: String? = nil,
        totalCents: Int? = nil,
        taxCents: Int? = nil,
        subtotalCents: Int? = nil,
        transactionDate: Date? = nil,
        lineItems: [ReceiptLineItem]? = nil,
        rawText: String
    ) {
        self.merchantName = merchantName
        self.totalCents = totalCents
        self.taxCents = taxCents
        self.subtotalCents = subtotalCents
        self.transactionDate = transactionDate
        self.lineItems = lineItems
        self.rawText = rawText
    }
}
