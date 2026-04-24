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
//
// Matches server status workflow (ENR-INV6):
//   draft → pending → ordered → partial → received  (terminal)
//   ordered → backordered → ordered (cycle)
//   Any non-terminal → cancelled                     (terminal)

public enum POStatus: String, Codable, Sendable, CaseIterable {
    case draft        = "draft"
    case pending      = "pending"
    case ordered      = "ordered"
    case backordered  = "backordered"
    case partial      = "partial"
    case received     = "received"
    case cancelled    = "cancelled"

    public var displayName: String {
        switch self {
        case .draft:        return "Draft"
        case .pending:      return "Pending"
        case .ordered:      return "Ordered"
        case .backordered:  return "Backordered"
        case .partial:      return "Partial"
        case .received:     return "Received"
        case .cancelled:    return "Cancelled"
        }
    }

    /// True if the PO is still actionable (non-terminal).
    public var isOpen: Bool {
        switch self {
        case .draft, .pending, .ordered, .backordered, .partial: return true
        case .received, .cancelled:                               return false
        }
    }

    /// True if the PO can be approved (moved to pending from draft).
    public var canApprove: Bool { self == .draft }
}
