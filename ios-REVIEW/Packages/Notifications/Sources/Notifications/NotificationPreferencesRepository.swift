import Foundation
import Networking
import Core

// MARK: - NotificationPreferencesRepository protocol

public protocol NotificationPreferencesRepository: Sendable {
    func fetchAll() async throws -> [NotificationPreference]
    func update(_ preference: NotificationPreference) async throws -> NotificationPreference
}

// MARK: - API shapes

private struct PreferencesListResponse: Decodable, Sendable {
    let preferences: [NotificationPreferenceDTO]?
}

private struct NotificationPreferenceDTO: Codable, Sendable {
    let event: String
    let pushEnabled: Bool
    let inAppEnabled: Bool
    let emailEnabled: Bool
    let smsEnabled: Bool
    let quietHoursStart: Int?
    let quietHoursEnd: Int?
    let quietHoursCriticalOverride: Bool?

    func toDomain() -> NotificationPreference? {
        guard let event = NotificationEvent(rawValue: self.event) else { return nil }
        let qh: QuietHours?
        if let start = quietHoursStart, let end = quietHoursEnd {
            qh = QuietHours(
                startMinutesFromMidnight: start,
                endMinutesFromMidnight: end,
                allowCriticalOverride: quietHoursCriticalOverride ?? true
            )
        } else {
            qh = nil
        }
        return NotificationPreference(
            event: event,
            pushEnabled: pushEnabled,
            inAppEnabled: inAppEnabled,
            emailEnabled: emailEnabled,
            smsEnabled: smsEnabled,
            quietHours: qh
        )
    }
}

private struct UpdatePreferenceRequest: Encodable, Sendable {
    let pushEnabled: Bool
    let inAppEnabled: Bool
    let emailEnabled: Bool
    let smsEnabled: Bool
    let quietHoursStart: Int?
    let quietHoursEnd: Int?
    let quietHoursCriticalOverride: Bool?

    init(from pref: NotificationPreference) {
        self.pushEnabled = pref.pushEnabled
        self.inAppEnabled = pref.inAppEnabled
        self.emailEnabled = pref.emailEnabled
        self.smsEnabled = pref.smsEnabled
        self.quietHoursStart = pref.quietHours?.startMinutesFromMidnight
        self.quietHoursEnd = pref.quietHours?.endMinutesFromMidnight
        self.quietHoursCriticalOverride = pref.quietHours?.allowCriticalOverride
    }
}

// MARK: - NotificationPreferencesRepositoryImpl

public final class NotificationPreferencesRepositoryImpl: NotificationPreferencesRepository, Sendable {

    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    /// `GET /users/me/notification-preferences`
    public func fetchAll() async throws -> [NotificationPreference] {
        let list = try await api.get(
            "/users/me/notification-preferences",
            as: [NotificationPreferenceDTO].self
        )
        let domain = list.compactMap { $0.toDomain() }

        // Merge: events not returned by server get the default preference.
        var merged: [String: NotificationPreference] = [:]
        for pref in domain { merged[pref.event.rawValue] = pref }
        for event in NotificationEvent.allCases where merged[event.rawValue] == nil {
            merged[event.rawValue] = .defaultPreference(for: event)
        }
        return NotificationEvent.allCases.compactMap { merged[$0.rawValue] }
    }

    /// `PATCH /users/me/notification-preferences/:event`
    public func update(_ preference: NotificationPreference) async throws -> NotificationPreference {
        let path = "/users/me/notification-preferences/\(preference.event.rawValue)"
        let body = UpdatePreferenceRequest(from: preference)
        let dto = try await api.patch(path, body: body, as: NotificationPreferenceDTO.self)
        return dto.toDomain() ?? preference
    }
}
