import Foundation

// §7.1 Invoice list — sort options

public enum InvoiceSortOption: String, CaseIterable, Sendable, Identifiable, Hashable {
    case dateDesc     = "date_desc"
    case dateAsc      = "date_asc"
    case amountDesc   = "amount_desc"
    case amountAsc    = "amount_asc"
    case dueDateAsc   = "due_date_asc"
    case dueDateDesc  = "due_date_desc"
    case status       = "status"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dateDesc:    return "Newest first"
        case .dateAsc:     return "Oldest first"
        case .amountDesc:  return "Amount (high → low)"
        case .amountAsc:   return "Amount (low → high)"
        case .dueDateAsc:  return "Due date (earliest)"
        case .dueDateDesc: return "Due date (latest)"
        case .status:      return "Status"
        }
    }

    public var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "sort", value: rawValue)]
    }
}
