import Foundation
import Networking

// MARK: - SmsListFilter
//
// Client-side filter state for the SMS conversation list.
// The server's GET /api/v1/sms/conversations supports keyword, include_archived.
// Remaining filters (Unread, Flagged, Pinned, Assigned) are applied client-side
// after the full list loads, keeping request overhead minimal.
//
// §12.1 Filters — All / Unread / Flagged / Pinned / Archived / Assigned to me / Unassigned.

public enum SmsListFilterTab: String, CaseIterable, Sendable, Identifiable {
    case all        = "All"
    case unread     = "Unread"
    case flagged    = "Flagged"
    case pinned     = "Pinned"
    case archived   = "Archived"
    case assignedMe = "Assigned to me"
    case unassigned = "Unassigned"
    /// §12.1 Team inbox — shared inbox (when tenant has it enabled).
    case teamInbox  = "Team Inbox"

    public var id: String { rawValue }

    public var label: String { rawValue }

    /// System image for filter chip icon.
    public var icon: String {
        switch self {
        case .all:        return "bubble.left.and.bubble.right"
        case .unread:     return "circle.fill"
        case .flagged:    return "flag"
        case .pinned:     return "pin"
        case .archived:   return "archivebox"
        case .assignedMe: return "person.crop.circle.badge.checkmark"
        case .unassigned: return "person.crop.circle.badge.questionmark"
        case .teamInbox:  return "tray.full"
        }
    }
}

public struct SmsListFilter: Equatable, Sendable {
    public var tab: SmsListFilterTab
    /// Current user's employee ID — used to compute `assignedMe` filter.
    /// Nil when the user's ID is not yet known (filter is a no-op).
    public var currentUserId: Int64?

    public init(tab: SmsListFilterTab = .all, currentUserId: Int64? = nil) {
        self.tab = tab
        self.currentUserId = currentUserId
    }

    public var isDefault: Bool { tab == .all }

    // MARK: - Application

    /// Filters `conversations` according to the selected tab.
    public func apply(to conversations: [SmsConversation]) -> [SmsConversation] {
        switch tab {
        case .all:
            return conversations.filter { !$0.isArchived }
        case .unread:
            return conversations.filter { $0.unreadCount > 0 && !$0.isArchived }
        case .flagged:
            return conversations.filter { $0.isFlagged && !$0.isArchived }
        case .pinned:
            return conversations.filter { $0.isPinned && !$0.isArchived }
        case .archived:
            return conversations.filter { $0.isArchived }
        case .assignedMe:
            // assignedUserId is not yet in the SmsConversation model (server gap).
            // Pass-through with no-op until server adds the field.
            return conversations.filter { !$0.isArchived }
        case .unassigned:
            // Similarly, "assigned" concept maps to assignedUserId == nil.
            // Pass-through until server adds the field.
            return conversations.filter { !$0.isArchived }
        case .teamInbox:
            // §12.1 Team inbox — all non-archived conversations (shared inbox view).
            // Server-side assignee field will narrow this when available.
            return conversations.filter { !$0.isArchived }
        }
    }
}
