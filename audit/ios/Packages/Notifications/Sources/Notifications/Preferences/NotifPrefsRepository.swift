import Foundation
import Networking
import Core

// MARK: - NotifPrefsRepository protocol

/// Repository backed by `GET/PUT /api/v1/notification-preferences/me`.
/// Distinct from the legacy `NotificationPreferencesRepository` which targets
/// a now-removed `/users/me/notification-preferences` path.
public protocol NotifPrefsRepository: Sendable {
    /// Fetch the full 20-event × 4-channel preference matrix.
    func fetchAll() async throws -> [NotificationPreference]
    /// Batch-upsert one or more preferences. Returns refreshed matrix.
    func batchUpdate(_ preferences: [NotificationPreference]) async throws -> [NotificationPreference]
}

// MARK: - NotifPrefsRepositoryImpl

/// Live implementation wired to `/api/v1/notification-preferences/me`.
public final class NotifPrefsRepositoryImpl: NotifPrefsRepository, Sendable {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - NotifPrefsRepository

    public func fetchAll() async throws -> [NotificationPreference] {
        let response = try await api.fetchNotificationPreferences()
        return buildDomainPreferences(from: response.preferences)
    }

    public func batchUpdate(_ preferences: [NotificationPreference]) async throws -> [NotificationPreference] {
        let items = preferences.flatMap { pref -> [NotificationPrefUpdateItem] in
            NotificationChannel.allCases.map { channel in
                NotificationPrefUpdateItem(
                    eventType: pref.event.rawValue,
                    channel: serverChannel(channel),
                    enabled: channelEnabled(pref, channel: channel),
                    quietHours: pref.quietHours.map { qh in
                        NotificationPrefQuietHours(
                            start: qh.startMinutesFromMidnight,
                            end: qh.endMinutesFromMidnight,
                            allowCriticalOverride: qh.allowCriticalOverride
                        )
                    }
                )
            }
        }
        let response = try await api.updateNotificationPreferences(items)
        return buildDomainPreferences(from: response.preferences)
    }

    // MARK: - Private helpers

    private func buildDomainPreferences(from rows: [NotificationPrefRow]) -> [NotificationPreference] {
        // Index stored rows by "event_type:channel"
        var indexed: [String: NotificationPrefRow] = [:]
        for row in rows {
            indexed["\(row.eventType):\(row.channel)"] = row
        }

        // Build one NotificationPreference per event, backfilling missing rows with defaults.
        return NotificationEvent.allCases.map { event in
            let push   = indexed["\(event.rawValue):push"]
            let inApp  = indexed["\(event.rawValue):in_app"]
            let email  = indexed["\(event.rawValue):email"]
            let sms    = indexed["\(event.rawValue):sms"]

            // Use quiet hours from push row if present (they share the same window per event).
            let quietHours = (push ?? inApp ?? email ?? sms).flatMap { row -> QuietHours? in
                guard let qh = row.quietHours else { return nil }
                return QuietHours(
                    startMinutesFromMidnight: qh.start,
                    endMinutesFromMidnight: qh.end,
                    allowCriticalOverride: qh.allowCriticalOverride
                )
            }

            return NotificationPreference(
                event: event,
                pushEnabled:  push?.enabled  ?? event.defaultPush,
                inAppEnabled: inApp?.enabled  ?? event.defaultInApp,
                emailEnabled: email?.enabled  ?? event.defaultEmail,
                smsEnabled:   sms?.enabled    ?? event.defaultSms,
                quietHours: quietHours
            )
        }
    }

    private func serverChannel(_ channel: NotificationChannel) -> String {
        switch channel {
        case .push:   return "push"
        case .inApp:  return "in_app"
        case .email:  return "email"
        case .sms:    return "sms"
        }
    }

    private func channelEnabled(_ pref: NotificationPreference, channel: NotificationChannel) -> Bool {
        switch channel {
        case .push:   return pref.pushEnabled
        case .inApp:  return pref.inAppEnabled
        case .email:  return pref.emailEnabled
        case .sms:    return pref.smsEnabled
        }
    }
}
