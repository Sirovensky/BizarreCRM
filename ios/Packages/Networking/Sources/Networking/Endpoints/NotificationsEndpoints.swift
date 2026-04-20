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

    public init(id: Int64, type: String?, title: String?, message: String?,
                entityType: String?, entityId: Int64?, isRead: Int?, createdAt: String?) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.entityType = entityType
        self.entityId = entityId
        self.isRead = isRead
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, type, title, message
        case entityType = "entity_type"
        case entityId = "entity_id"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

/// `POST /api/v1/notifications/mark-all-read` returns `{ message, updated }`.
/// We keep `updated` so the UI can confirm a count with a toast.
public struct MarkAllReadResponse: Decodable, Sendable {
    public let message: String?
    public let updated: Int?
}

/// Empty request body for `POST /mark-all-read` — server ignores it but
/// our APIClient's `post` signature requires one.
public struct EmptyBody: Encodable, Sendable { public init() {} }

public extension APIClient {
    func listNotifications(page: Int = 1) async throws -> [NotificationItem] {
        try await get("/api/v1/notifications",
                      query: [URLQueryItem(name: "page", value: String(page))],
                      as: NotificationsListResponse.self).notifications
    }

    /// PATCH `/api/v1/notifications/:id/read`. Server returns the mutated
    /// row; callers typically just toggle a local `read` flag rather than
    /// re-render off the response.
    func markNotificationRead(id: Int64) async throws -> NotificationItem {
        try await patch("/api/v1/notifications/\(id)/read",
                        body: EmptyBody(),
                        as: NotificationItem.self)
    }

    /// POST `/api/v1/notifications/mark-all-read`. Returns how many rows
    /// were flipped — useful for a "Marked N as read" success toast.
    func markAllNotificationsRead() async throws -> MarkAllReadResponse {
        try await post("/api/v1/notifications/mark-all-read",
                       body: EmptyBody(),
                       as: MarkAllReadResponse.self)
    }
}
