import Foundation

// MARK: - §43.3 Price Override Models

/// Scope of a price override.
public enum OverrideScope: String, Codable, Sendable, CaseIterable {
    case tenant, customer
}

/// A per-tenant or per-customer price override for a repair service.
public struct PriceOverride: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let serviceId: String
    public let scope: OverrideScope
    public let customerId: String?
    public let priceCents: Int
    public let reason: String?
    public let createdAt: Date

    public init(
        id: String,
        serviceId: String,
        scope: OverrideScope,
        customerId: String? = nil,
        priceCents: Int,
        reason: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.serviceId = serviceId
        self.scope = scope
        self.customerId = customerId
        self.priceCents = priceCents
        self.reason = reason
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, scope, reason
        case serviceId   = "service_id"
        case customerId  = "customer_id"
        case priceCents  = "price_cents"
        case createdAt   = "created_at"
    }
}

// MARK: - Request body

/// POST /repair-pricing/overrides body.
public struct CreatePriceOverrideRequest: Encodable, Sendable {
    let serviceId: String
    let scope: OverrideScope
    let customerId: String?
    let priceCents: Int
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case scope, reason
        case serviceId  = "service_id"
        case customerId = "customer_id"
        case priceCents = "price_cents"
    }
}
