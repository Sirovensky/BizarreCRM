/// §18.3 — Entity scope for FTS5 search queries.
public enum EntityFilter: String, CaseIterable, Hashable, Sendable, Codable {
    case all
    case tickets
    case customers
    case inventory
    case invoices
    case estimates
    case appointments

    public var displayName: String {
        switch self {
        case .all:          return "All"
        case .tickets:      return "Tickets"
        case .customers:    return "Customers"
        case .inventory:    return "Inventory"
        case .invoices:     return "Invoices"
        case .estimates:    return "Estimates"
        case .appointments: return "Appointments"
        }
    }

    public var systemImage: String {
        switch self {
        case .all:          return "magnifyingglass"
        case .tickets:      return "wrench.and.screwdriver.fill"
        case .customers:    return "person.fill"
        case .inventory:    return "shippingbox.fill"
        case .invoices:     return "doc.text.fill"
        case .estimates:    return "doc.badge.plus"
        case .appointments: return "calendar"
        }
    }
}
