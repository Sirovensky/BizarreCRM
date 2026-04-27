import Foundation

// MARK: - APIClient+NotifPrefs
//
// §21.1 / §70 — Notification preference persistence.
// Server endpoints:
//   GET  /api/v1/notifications/preferences
//   PUT  /api/v1/notifications/preferences
//
// Per §70, default is push + in-app per event; email/SMS off.
// Server persists per-user deltas from the shipped default.

// MARK: - Wire types

/// Per-event preference as sent to / received from the server.
public struct NotifPreferenceWire: Codable, Sendable {
    public let event: String
    public let pushEnabled: Bool
    public let inAppEnabled: Bool
    public let emailEnabled: Bool
    public let smsEnabled: Bool

    public init(event: String, pushEnabled: Bool, inAppEnabled: Bool,
                emailEnabled: Bool, smsEnabled: Bool) {
        self.event = event
        self.pushEnabled = pushEnabled
        self.inAppEnabled = inAppEnabled
        self.emailEnabled = emailEnabled
        self.smsEnabled = smsEnabled
    }
}

struct NotifPrefsBody: Encodable {
    let preferences: [NotifPreferenceWire]
}

public extension APIClient {
    /// Fetch the current user's notification preferences from the server.
    func getNotifPreferences() async throws -> [NotifPreferenceWire] {
        try await get("/api/v1/notifications/preferences", as: [NotifPreferenceWire].self)
    }

    /// Persist the user's notification preference overrides.
    func putNotifPreferences(_ prefs: [NotifPreferenceWire]) async throws {
        _ = try await put(
            "/api/v1/notifications/preferences",
            body: NotifPrefsBody(preferences: prefs),
            as: StatusPayload.self
        )
    }

    struct StatusPayload: Decodable {
        let success: Bool
    }
}
