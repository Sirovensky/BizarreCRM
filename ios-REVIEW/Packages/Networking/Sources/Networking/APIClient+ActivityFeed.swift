import Foundation

// MARK: - APIClient+ActivityFeed
//
// §3.6 Activity feed — chronological list of recent events shown on the dashboard.
// Server endpoint: GET /api/v1/activity?limit=20
// Falls back to a stitched union of tickets/invoices/sms updated_at if missing.

// MARK: - Wire types

/// A single activity event from GET /api/v1/activity.
/// `entityType` drives the icon and deep-link destination.
public struct ActivityEvent: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let entityType: String      // "ticket" | "invoice" | "sms" | "customer" | "payment"
    public let entityId: Int64?
    public let title: String
    public let subtitle: String?
    public let actorName: String?
    public let occurredAt: String      // ISO-8601

    public init(
        id: Int64 = 0,
        entityType: String = "",
        entityId: Int64? = nil,
        title: String = "",
        subtitle: String? = nil,
        actorName: String? = nil,
        occurredAt: String = ""
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.title = title
        self.subtitle = subtitle
        self.actorName = actorName
        self.occurredAt = occurredAt
    }
}

public extension APIClient {
    /// §3.6 — Recent activity feed.
    /// `GET /api/v1/activity?limit=N`
    func activityFeed(limit: Int = 20) async throws -> [ActivityEvent] {
        let query = [URLQueryItem(name: "limit", value: "\(limit)")]
        return try await get("/api/v1/activity", query: query, as: [ActivityEvent].self)
    }
}
