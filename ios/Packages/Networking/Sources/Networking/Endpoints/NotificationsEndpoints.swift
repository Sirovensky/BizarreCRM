import Foundation

/// `GET /api/v1/notifications` — wrapped: `{ notifications: [...], pagination: {...} }`.
public struct NotificationsListResponse: Decodable, Sendable {
    public let notifications: [NotificationItem]
    public init(notifications: [NotificationItem]) { self.notifications = notifications }
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
    public init(message: String?, updated: Int?) {
        self.message = message
        self.updated = updated
    }
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

// ---------------------------------------------------------------------------
// Notification Preferences — /api/v1/notification-preferences
// Server routes: GET /me, PUT /me
// ---------------------------------------------------------------------------

/// Single row in the full 20-event × 4-channel matrix returned by GET /me.
public struct NotificationPrefRow: Decodable, Sendable {
    public let eventType: String
    public let channel: String
    public let enabled: Bool
    /// Quiet-hours blob. Structure: `{ start: Int, end: Int, allowCriticalOverride: Bool }`.
    public let quietHours: NotificationPrefQuietHours?

    public init(
        eventType: String, channel: String,
        enabled: Bool, quietHours: NotificationPrefQuietHours?
    ) {
        self.eventType = eventType
        self.channel = channel
        self.enabled = enabled
        self.quietHours = quietHours
    }

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case channel
        case enabled
        case quietHours = "quiet_hours"
    }
}

/// Quiet-hours window as returned from the server preferences endpoint.
public struct NotificationPrefQuietHours: Codable, Sendable {
    public let start: Int
    public let end: Int
    public let allowCriticalOverride: Bool

    public init(start: Int, end: Int, allowCriticalOverride: Bool) {
        self.start = start
        self.end = end
        self.allowCriticalOverride = allowCriticalOverride
    }

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case allowCriticalOverride = "allow_critical_override"
    }
}

/// Full response for GET /api/v1/notification-preferences/me.
public struct NotificationPrefsResponse: Decodable, Sendable {
    public let preferences: [NotificationPrefRow]
    public let eventTypes: [String]
    public let channels: [String]

    public init(preferences: [NotificationPrefRow], eventTypes: [String], channels: [String]) {
        self.preferences = preferences
        self.eventTypes = eventTypes
        self.channels = channels
    }

    enum CodingKeys: String, CodingKey {
        case preferences
        case eventTypes = "event_types"
        case channels
    }
}

/// Single-item upsert body for PUT /api/v1/notification-preferences/me.
/// The server expects an array under `preferences`.
public struct NotificationPrefUpdateItem: Encodable, Sendable {
    public let eventType: String
    public let channel: String
    public let enabled: Bool
    public let quietHours: NotificationPrefQuietHours?

    public init(eventType: String, channel: String, enabled: Bool,
                quietHours: NotificationPrefQuietHours? = nil) {
        self.eventType = eventType
        self.channel = channel
        self.enabled = enabled
        self.quietHours = quietHours
    }

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case channel
        case enabled
        case quietHours = "quiet_hours"
    }
}

public struct NotificationPrefUpdateBody: Encodable, Sendable {
    public let preferences: [NotificationPrefUpdateItem]
    public init(preferences: [NotificationPrefUpdateItem]) {
        self.preferences = preferences
    }
}

public extension APIClient {
    /// GET `/api/v1/notification-preferences/me` — full 20×4 matrix.
    func fetchNotificationPreferences() async throws -> NotificationPrefsResponse {
        try await get("/api/v1/notification-preferences/me",
                      query: nil,
                      as: NotificationPrefsResponse.self)
    }

    /// PUT `/api/v1/notification-preferences/me` — batch-upsert one or more rows.
    /// Returns the refreshed full matrix on success.
    func updateNotificationPreferences(
        _ items: [NotificationPrefUpdateItem]
    ) async throws -> NotificationPrefsResponse {
        try await put(
            "/api/v1/notification-preferences/me",
            body: NotificationPrefUpdateBody(preferences: items),
            as: NotificationPrefsResponse.self
        )
    }
}
