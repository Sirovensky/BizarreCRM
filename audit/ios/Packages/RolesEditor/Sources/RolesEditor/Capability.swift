import Foundation

// MARK: - Capability

public struct Capability: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let domain: String
    public let label: String
    public let description: String

    // Identifiable conformance — id already satisfies the requirement
    // but we alias for clarity at call sites.
    public var id_: String { id }

    public init(id: String, domain: String, label: String, description: String) {
        self.id = id
        self.domain = domain
        self.label = label
        self.description = description
    }
}

// MARK: - CapabilityDomain

public enum CapabilityDomain: String, CaseIterable, Sendable {
    case tickets     = "Tickets"
    case customers   = "Customers"
    case inventory   = "Inventory"
    case invoices    = "Invoices"
    case sms         = "SMS"
    case reports     = "Reports"
    case settings    = "Settings"
    case hardware    = "Hardware"
    case audit       = "Audit"
    case data        = "Data"
    case team        = "Team"
    case marketing   = "Marketing"
    case danger      = "Danger"
}
