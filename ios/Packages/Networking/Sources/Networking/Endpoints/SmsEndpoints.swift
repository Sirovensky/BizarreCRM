import Foundation

/// `GET /api/v1/sms/conversations` response.
/// Server: packages/server/src/routes/sms.routes.ts:160.
/// Envelope data: `{ conversations: [...] }` — no pagination.
public struct SmsConversationsResponse: Decodable, Sendable {
    public let conversations: [SmsConversation]
}

public struct SmsConversation: Decodable, Sendable, Identifiable, Hashable {
    public let convPhone: String
    public let lastMessageAt: String?
    public let lastMessage: String?
    public let lastDirection: String?
    public let messageCount: Int
    public let unreadCount: Int
    public let isFlagged: Bool
    public let isPinned: Bool
    public let customer: Customer?
    public let recentTicket: RecentTicket?

    /// Thread is keyed by phone number, not a numeric id.
    public var id: String { convPhone }

    public var displayName: String {
        if let c = customer {
            let parts = [c.firstName, c.lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }
        return convPhone
    }

    public var avatarInitial: String {
        if let first = customer?.firstName?.first { return String(first).uppercased() }
        return String(convPhone.first ?? "#").uppercased()
    }

    public struct Customer: Decodable, Sendable, Hashable {
        public let id: Int64?
        public let firstName: String?
        public let lastName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    public struct RecentTicket: Decodable, Sendable, Hashable {
        public let id: Int64
        public let orderId: String?
        public let statusName: String?
        public let statusColor: String?

        enum CodingKeys: String, CodingKey {
            case id
            case orderId = "order_id"
            case statusName = "status_name"
            case statusColor = "status_color"
        }
    }

    enum CodingKeys: String, CodingKey {
        case customer
        case convPhone = "conv_phone"
        case lastMessageAt = "last_message_at"
        case lastMessage = "last_message"
        case lastDirection = "last_direction"
        case messageCount = "message_count"
        case unreadCount = "unread_count"
        case isFlagged = "is_flagged"
        case isPinned = "is_pinned"
        case recentTicket = "recent_ticket"
    }
}

public extension APIClient {
    func listSmsConversations(keyword: String? = nil, includeArchived: Bool = false) async throws -> [SmsConversation] {
        var items: [URLQueryItem] = []
        if let keyword, !keyword.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: keyword))
        }
        if includeArchived {
            items.append(URLQueryItem(name: "include_archived", value: "1"))
        }
        return try await get("/api/v1/sms/conversations", query: items, as: SmsConversationsResponse.self).conversations
    }
}
