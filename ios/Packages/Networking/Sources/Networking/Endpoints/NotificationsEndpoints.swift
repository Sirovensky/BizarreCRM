import Foundation

/// `GET /api/v1/notifications` — wrapped: `{ notifications: [...], pagination: {...} }`.
public struct NotificationsListResponse: Decodable, Sendable {
    public let notifications: [NotificationItem]
}

public struct NotificationItem: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let type: String?
    public let title: String?
    public let message: String?
    public let entityType: String?
    public let entityId: Int64?
    public let isRead: Int?
    public let createdAt: String?

    public var read: Bool { (isRead ?? 0) != 0 }

    enum CodingKeys: String, CodingKey {
        case id, type, title, message
        case entityType = "entity_type"
        case entityId = "entity_id"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

public extension APIClient {
    func listNotifications(page: Int = 1) async throws -> [NotificationItem] {
        try await get("/api/v1/notifications",
                      query: [URLQueryItem(name: "page", value: String(page))],
                      as: NotificationsListResponse.self).notifications
    }
}
