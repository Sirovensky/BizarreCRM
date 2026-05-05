import Foundation

// MARK: - QuietHours

/// User-configured quiet hours window. Deliveries outside critical events are
/// suppressed during this window. Stored as wall-clock offsets from midnight.
public struct QuietHours: Codable, Sendable, Equatable {
    /// Minutes from midnight for quiet period start (e.g. 22*60 = 10 PM).
    public let startMinutesFromMidnight: Int
    /// Minutes from midnight for quiet period end (e.g. 7*60 = 7 AM).
    public let endMinutesFromMidnight: Int
    /// When true, critical-level events still fire during quiet hours.
    public let allowCriticalOverride: Bool

    public init(
        startMinutesFromMidnight: Int = 22 * 60,
        endMinutesFromMidnight: Int = 7 * 60,
        allowCriticalOverride: Bool = true
    ) {
        self.startMinutesFromMidnight = startMinutesFromMidnight
        self.endMinutesFromMidnight = endMinutesFromMidnight
        self.allowCriticalOverride = allowCriticalOverride
    }
}

// MARK: - NotificationPreference

/// Per-user per-event notification preference. Immutable — always create new instances.
public struct NotificationPreference: Identifiable, Codable, Sendable, Equatable {
    public let event: NotificationEvent
    public let pushEnabled: Bool
    public let inAppEnabled: Bool
    public let emailEnabled: Bool
    public let smsEnabled: Bool
    public let quietHours: QuietHours?

    public var id: String { event.rawValue }

    public init(
        event: NotificationEvent,
        pushEnabled: Bool,
        inAppEnabled: Bool,
        emailEnabled: Bool,
        smsEnabled: Bool,
        quietHours: QuietHours? = nil
    ) {
        self.event = event
        self.pushEnabled = pushEnabled
        self.inAppEnabled = inAppEnabled
        self.emailEnabled = emailEnabled
        self.smsEnabled = smsEnabled
        self.quietHours = quietHours
    }

    /// Build the default preference for an event per the §70 matrix.
    public static func defaultPreference(for event: NotificationEvent) -> NotificationPreference {
        NotificationPreference(
            event: event,
            pushEnabled: event.defaultPush,
            inAppEnabled: event.defaultInApp,
            emailEnabled: event.defaultEmail,
            smsEnabled: event.defaultSms
        )
    }

    /// Return a copy with one field toggled — immutable pattern.
    public func toggling(_ channel: NotificationChannel) -> NotificationPreference {
        NotificationPreference(
            event: event,
            pushEnabled:  channel == .push   ? !pushEnabled   : pushEnabled,
            inAppEnabled: channel == .inApp  ? !inAppEnabled  : inAppEnabled,
            emailEnabled: channel == .email  ? !emailEnabled  : emailEnabled,
            smsEnabled:   channel == .sms    ? !smsEnabled    : smsEnabled,
            quietHours: quietHours
        )
    }

    /// Return a copy with updated quiet hours.
    public func withQuietHours(_ qh: QuietHours?) -> NotificationPreference {
        NotificationPreference(
            event: event,
            pushEnabled: pushEnabled,
            inAppEnabled: inAppEnabled,
            emailEnabled: emailEnabled,
            smsEnabled: smsEnabled,
            quietHours: qh
        )
    }
}

// MARK: - NotificationChannel

public enum NotificationChannel: String, Sendable, CaseIterable, Identifiable {
    case push   = "Push"
    case inApp  = "In-App"
    case email  = "Email"
    case sms    = "SMS"

    public var id: String { rawValue }
}
