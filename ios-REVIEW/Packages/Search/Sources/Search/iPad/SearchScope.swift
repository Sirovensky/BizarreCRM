import Foundation

/// §22 — iPad-specific scope enum for the 3-column search layout.
/// Covers the six scopes shown in the scope sidebar.
public enum SearchScope: String, CaseIterable, Hashable, Sendable, Codable {
    case all
    case customers
    case tickets
    case inventory
    case invoices
    case notes

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .all:       return "All"
        case .customers: return "Customers"
        case .tickets:   return "Tickets"
        case .inventory: return "Inventory"
        case .invoices:  return "Invoices"
        case .notes:     return "Notes"
        }
    }

    public var systemImage: String {
        switch self {
        case .all:       return "magnifyingglass"
        case .customers: return "person.fill"
        case .tickets:   return "wrench.and.screwdriver.fill"
        case .inventory: return "shippingbox.fill"
        case .invoices:  return "doc.text.fill"
        case .notes:     return "note.text"
        }
    }

    /// Keyboard shortcut digit (nil for .all which uses ⌘F).
    public var shortcutDigit: Int? {
        switch self {
        case .all:       return nil
        case .customers: return 1
        case .tickets:   return 2
        case .inventory: return 3
        case .invoices:  return 4
        case .notes:     return 5
        }
    }

    /// Map to the underlying `EntityFilter` used by `FTSIndexStore`.
    /// Notes maps to the nearest available entity; returns nil for `.all`.
    public var entityFilter: EntityFilter? {
        switch self {
        case .all:       return nil
        case .customers: return .customers
        case .tickets:   return .tickets
        case .inventory: return .inventory
        case .invoices:  return .invoices
        case .notes:     return nil   // notes is not an FTS5 entity in this version
        }
    }
}
