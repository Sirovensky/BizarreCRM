import Foundation

// §7.10 Credit Notes

// MARK: - CreditNoteStatus

public enum CreditNoteStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case open     = "open"
    case applied  = "applied"
    case void     = "void"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .open:    return "Open"
        case .applied: return "Applied"
        case .void:    return "Void"
        }
    }
}

// MARK: - CreditNote

/// A credit note represents a financial credit issued to a customer.
/// It may be standalone or tied to a specific invoice.
public struct CreditNote: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let customerId: Int64
    /// Nil when the credit note is standalone (not linked to an invoice).
    public let originalInvoiceId: Int64?
    /// Credit amount in cents (positive integer).
    public let amountCents: Int
    /// Free-text reason for the credit.
    public let reason: String
    /// Date the credit was issued (YYYY-MM-DD or ISO-8601 from server).
    public let issueDate: String
    public let status: CreditNoteStatus
    /// Server-assigned display reference, e.g. "CN-0042".
    public let referenceNumber: String?

    public init(
        id: Int64,
        customerId: Int64,
        originalInvoiceId: Int64? = nil,
        amountCents: Int,
        reason: String,
        issueDate: String,
        status: CreditNoteStatus = .open,
        referenceNumber: String? = nil
    ) {
        self.id = id
        self.customerId = customerId
        self.originalInvoiceId = originalInvoiceId
        self.amountCents = amountCents
        self.reason = reason
        self.issueDate = issueDate
        self.status = status
        self.referenceNumber = referenceNumber
    }

    enum CodingKeys: String, CodingKey {
        case id, status, reason
        case customerId        = "customer_id"
        case originalInvoiceId = "original_invoice_id"
        case amountCents       = "amount_cents"
        case issueDate         = "issue_date"
        case referenceNumber   = "reference_number"
    }
}

// MARK: - Create DTO

public struct CreateCreditNoteRequest: Encodable, Sendable {
    public let customerId: Int64
    public let originalInvoiceId: Int64?
    public let amountCents: Int
    public let reason: String
    public let issueDate: String

    public init(
        customerId: Int64,
        originalInvoiceId: Int64? = nil,
        amountCents: Int,
        reason: String,
        issueDate: String
    ) {
        self.customerId = customerId
        self.originalInvoiceId = originalInvoiceId
        self.amountCents = amountCents
        self.reason = reason
        self.issueDate = issueDate
    }

    enum CodingKeys: String, CodingKey {
        case reason
        case customerId        = "customer_id"
        case originalInvoiceId = "original_invoice_id"
        case amountCents       = "amount_cents"
        case issueDate         = "issue_date"
    }
}

// MARK: - Apply DTO

public struct ApplyCreditNoteRequest: Encodable, Sendable {
    public let creditNoteId: Int64
    /// The invoice to which the credit will be applied.
    public let targetInvoiceId: Int64
    /// Amount to apply (≤ min(creditNote.amountCents, invoice.balanceCents)).
    public let applyCents: Int

    public init(creditNoteId: Int64, targetInvoiceId: Int64, applyCents: Int) {
        self.creditNoteId = creditNoteId
        self.targetInvoiceId = targetInvoiceId
        self.applyCents = applyCents
    }

    enum CodingKeys: String, CodingKey {
        case creditNoteId    = "credit_note_id"
        case targetInvoiceId = "target_invoice_id"
        case applyCents      = "apply_cents"
    }
}
