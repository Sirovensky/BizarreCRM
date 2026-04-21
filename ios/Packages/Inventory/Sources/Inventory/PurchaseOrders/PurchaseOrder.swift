import Foundation

// MARK: - PurchaseOrder

/// §58 – Purchase Order domain model. All money in cents.
public struct PurchaseOrder: Codable, Sendable, Identifiable {
    public let id: Int64
    public let supplierId: Int64
    public let status: POStatus
    public let createdAt: Date
    public let expectedDate: Date?
    public let items: [POLineItem]
    public let totalCents: Int
    public let notes: String?

    public init(
        id: Int64,
        supplierId: Int64,
        status: POStatus,
        createdAt: Date,
        expectedDate: Date? = nil,
        items: [POLineItem],
        totalCents: Int,
        notes: String? = nil
    ) {
        self.id = id
        self.supplierId = supplierId
        self.status = status
        self.createdAt = createdAt
        self.expectedDate = expectedDate
        self.items = items
        self.totalCents = totalCents
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case supplierId   = "supplier_id"
        case status
        case createdAt    = "created_at"
        case expectedDate = "expected_date"
        case items
        case totalCents   = "total_cents"
        case notes
    }
}

// MARK: - POStatus

public enum POStatus: String, Codable, Sendable, CaseIterable {
    case draft      = "draft"
    case submitted  = "submitted"
    case partial    = "partial"
    case received   = "received"
    case cancelled  = "cancelled"

    public var displayName: String {
        switch self {
        case .draft:      return "Draft"
        case .submitted:  return "Submitted"
        case .partial:    return "Partial"
        case .received:   return "Received"
        case .cancelled:  return "Cancelled"
        }
    }

    /// True if the PO is still actionable.
    public var isOpen: Bool {
        switch self {
        case .draft, .submitted, .partial: return true
        case .received, .cancelled:        return false
        }
    }
}
