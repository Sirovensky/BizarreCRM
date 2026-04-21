import Foundation

// MARK: - Estimate

/// Canonical domain model for a repair estimate / quote.
/// Wire DTO: Networking/Endpoints/EstimatesEndpoints.swift (Estimate).
public struct Estimate: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let orderId: String?
    public let customerId: Int64?
    public let status: EstimateStatus
    public let totalCents: Cents
    public let validUntil: Date?
    public let lineItems: [EstimateLineItem]
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: Int64,
        orderId: String? = nil,
        customerId: Int64? = nil,
        status: EstimateStatus = .draft,
        totalCents: Cents = 0,
        validUntil: Date? = nil,
        lineItems: [EstimateLineItem] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.orderId = orderId
        self.customerId = customerId
        self.status = status
        self.totalCents = totalCents
        self.validUntil = validUntil
        self.lineItems = lineItems
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayId: String { orderId?.isEmpty == false ? orderId! : "EST-\(id)" }

    public var isExpired: Bool {
        guard let v = validUntil else { return false }
        return v < Date() && status != .accepted && status != .rejected
    }
}

// MARK: - EstimateStatus

public enum EstimateStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case draft
    case sent
    case accepted
    case rejected
    case expired
    case converted // converted to ticket/invoice

    public var displayName: String {
        switch self {
        case .draft:     return "Draft"
        case .sent:      return "Sent"
        case .accepted:  return "Accepted"
        case .rejected:  return "Rejected"
        case .expired:   return "Expired"
        case .converted: return "Converted"
        }
    }
}

// MARK: - EstimateLineItem

public struct EstimateLineItem: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let estimateId: Int64?
    public let inventoryItemId: Int64?
    public let itemName: String?
    public let description: String?
    public let quantity: Double
    public let unitPriceCents: Cents
    public let totalCents: Cents

    public init(
        id: Int64,
        estimateId: Int64? = nil,
        inventoryItemId: Int64? = nil,
        itemName: String? = nil,
        description: String? = nil,
        quantity: Double = 1,
        unitPriceCents: Cents = 0,
        totalCents: Cents = 0
    ) {
        self.id = id
        self.estimateId = estimateId
        self.inventoryItemId = inventoryItemId
        self.itemName = itemName
        self.description = description
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
        self.totalCents = totalCents
    }

    public var displayName: String {
        if let n = itemName, !n.isEmpty { return n }
        if let d = description, !d.isEmpty { return d }
        return "Item"
    }
}
