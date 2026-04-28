import Foundation
import Networking

// §7.1 Invoice list — full status tab set (All / Unpaid / Partial / Overdue / Paid / Void)
// Extends InvoiceFilter with the missing "void" tab for the tab-bar display.
// InvoiceFilter (defined in Networking) is the server query enum; we map to it.

public enum InvoiceStatusTab: String, CaseIterable, Sendable, Identifiable, Hashable {
    case all     = "all"
    case unpaid  = "unpaid"
    case partial = "partial"
    case overdue = "overdue"
    case paid    = "paid"
    case void_   = "void"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:     return "All"
        case .unpaid:  return "Unpaid"
        case .partial: return "Partial"
        case .overdue: return "Overdue"
        case .paid:    return "Paid"
        case .void_:   return "Void"
        }
    }

    /// Maps to the server `status` query parameter value (nil = no filter).
    public var serverStatus: String? {
        switch self {
        case .all:    return nil
        case .unpaid: return "unpaid"
        case .partial: return "partial"
        case .overdue: return "overdue"
        case .paid:    return "paid"
        case .void_:   return "void"
        }
    }

    /// Converts to the legacy `InvoiceFilter` used by the cached repository.
    public var legacyFilter: InvoiceFilter {
        switch self {
        case .all:     return .all
        case .unpaid:  return .unpaid
        case .partial: return .partial
        case .overdue: return .overdue
        case .paid:    return .paid
        case .void_:   return .all  // server returns void via status param; map to .all + custom status
        }
    }
}
