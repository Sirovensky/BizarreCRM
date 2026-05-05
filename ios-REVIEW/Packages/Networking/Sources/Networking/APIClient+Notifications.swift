import Foundation

// MARK: - APIClient+Notifications (§21/§13)
//
// Append-only extension. Add new notification-related endpoints here;
// never modify existing function signatures.
//
// Device-token registration is already covered in DeviceTokenEndpoints.swift.
// This file owns the notification-list + notification-preferences surface.

// ---------------------------------------------------------------------------
// Notification list DTOs (re-exported from NotificationsEndpoints.swift via
// APIClient protocol extension so callers only import Networking).
// The DTOs themselves live in NotificationsEndpoints.swift to avoid duplication.
// ---------------------------------------------------------------------------

public extension APIClient {

    // MARK: - Unread count

    /// GET `/api/v1/notifications/unread-count`
    /// Envelope: `{ success, data: { count: Int } }`.
    func fetchUnreadNotificationCount() async throws -> Int {
        let response = try await get(
            "/api/v1/notifications/unread-count",
            as: UnreadCountPayload.self
        )
        return response.count
    }

    // MARK: - Focus policies (§21 FocusFilter integration)

    /// GET `/api/v1/notifications/focus-policies`
    func fetchFocusPolicies() async throws -> FocusPoliciesPayload {
        try await get(
            "/api/v1/notifications/focus-policies",
            as: FocusPoliciesPayload.self
        )
    }

    /// PUT `/api/v1/notifications/focus-policies`
    func updateFocusPolicies(_ body: FocusPoliciesPayload) async throws {
        // Server returns `{ success: true, data: null }` — we discard data.
        _ = try await put(
            "/api/v1/notifications/focus-policies",
            body: body,
            as: NullPayload.self
        )
    }
}

// MARK: - Supporting DTOs

/// `data` shape for GET /notifications/unread-count.
public struct UnreadCountPayload: Decodable, Sendable {
    public let count: Int
    public init(count: Int) { self.count = count }
}

/// Opaque policies blob — the server stores and returns whatever JSON the
/// client sends.  iOS FocusFilterDescriptor serialises into/out of this.
public struct FocusPoliciesPayload: Codable, Sendable {
    public let policies: [FocusPolicyEntry]

    public init(policies: [FocusPolicyEntry]) {
        self.policies = policies
    }
}

public struct FocusPolicyEntry: Codable, Sendable {
    public let eventType: String
    public let suppressed: Bool

    public init(eventType: String, suppressed: Bool) {
        self.eventType = eventType
        self.suppressed = suppressed
    }

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case suppressed
    }
}

/// Placeholder `data` type for endpoints whose server response has `data: null`.
private struct NullPayload: Decodable, Sendable {}
