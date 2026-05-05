import Foundation

// MARK: - NotificationFilterChip

/// Filter options available in the notification list toolbar.
/// `.all` is the default. Filter chips are mutually exclusive except that
/// a type filter (`byType`) may combine with the `.unread` filter — handled
/// in the view-model.
public enum NotificationFilterChip: Hashable, Sendable, Identifiable {
    case all
    case unread
    case byType(NotificationTypeFilter)

    public var id: String {
        switch self {
        case .all:              return "all"
        case .unread:           return "unread"
        case .byType(let t):    return "type_\(t.rawValue)"
        }
    }

    public var label: String {
        switch self {
        case .all:              return "All"
        case .unread:           return "Unread"
        case .byType(let t):    return t.displayName
        }
    }

    /// Primary chips always shown in the toolbar.
    public static let primary: [NotificationFilterChip] = [.all, .unread]

    /// Type-filter chips derived from `NotificationTypeFilter`.
    public static let typeChips: [NotificationFilterChip] = NotificationTypeFilter.allCases
        .map { .byType($0) }
}

// MARK: - NotificationTypeFilter helpers
// (Canonical enum lives in NotificationFilterView.swift.)

public extension NotificationTypeFilter {
    var displayName: String {
        switch self {
        case .ticket:      return "Tickets"
        case .sms:         return "SMS"
        case .invoice:     return "Invoices"
        case .payment:     return "Payments"
        case .appointment: return "Appointments"
        case .mention:     return "Mentions"
        case .system:      return "System"
        }
    }

    /// Returns `true` if `typeString` from the server belongs to this filter bucket.
    func matches(_ typeString: String?) -> Bool {
        guard let t = typeString?.lowercased() else { return self == .system }
        switch self {
        case .ticket:      return t.contains("ticket")
        case .sms:         return t.contains("sms")
        case .invoice:     return t.contains("invoice") || t.contains("estimate")
        case .payment:     return t.contains("payment") || t.contains("refund")
        case .appointment: return t.contains("appoint")
        case .mention:     return t.contains("mention")
        case .system:
            return !["ticket", "sms", "invoice", "estimate", "payment",
                     "refund", "appoint", "mention"].contains(where: t.contains)
        }
    }
}
