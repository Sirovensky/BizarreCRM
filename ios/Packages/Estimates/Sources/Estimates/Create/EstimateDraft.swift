import Foundation

// §63 ext — Estimate create draft model (Phase 2)

/// Persisted snapshot of in-progress estimate create form fields.
public struct EstimateDraft: Codable, Sendable, Equatable {
    public var customerId: String?
    public var customerDisplayName: String?
    public var subject: String
    public var notes: String
    public var validUntil: String   // YYYY-MM-DD or empty
    public var updatedAt: Date

    public init(
        customerId: String? = nil,
        customerDisplayName: String? = nil,
        subject: String = "",
        notes: String = "",
        validUntil: String = "",
        updatedAt: Date = Date()
    ) {
        self.customerId          = customerId
        self.customerDisplayName = customerDisplayName
        self.subject             = subject
        self.notes               = notes
        self.validUntil          = validUntil
        self.updatedAt           = updatedAt
    }
}
