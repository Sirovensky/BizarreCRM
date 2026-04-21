import Foundation

// MARK: - QuietHoursWindow

public struct QuietHoursWindow: Sendable, Equatable {
    /// Start hour (0–23) of the quiet period.
    public var startHour: Int
    /// End hour (0–23) of the quiet period. May be less than `startHour` for overnight windows.
    public var endHour: Int

    public init(startHour: Int, endHour: Int) {
        self.startHour = startHour
        self.endHour = endHour
    }
}

// MARK: - AppointmentReminderSettings

/// Per-tenant configuration for appointment reminders.
public struct AppointmentReminderSettings: Codable, Sendable, Equatable {
    /// How many hours before the appointment to send the reminder.
    public var offsetHours: Int
    /// The SMS/push message template. Use `{{customer_name}}` and `{{time}}` tokens.
    public var messageTemplate: String
    /// Optional quiet-hours window — reminders will not be sent during this time.
    public var quietHours: QuietHoursWindow?

    public static let defaultTemplate = "Hi {{customer_name}}, reminder: your appointment is at {{time}}. Reply STOP to cancel."

    public init(
        offsetHours: Int = 24,
        messageTemplate: String = AppointmentReminderSettings.defaultTemplate,
        quietHours: QuietHoursWindow? = nil
    ) {
        self.offsetHours = offsetHours
        self.messageTemplate = messageTemplate
        self.quietHours = quietHours
    }

    enum CodingKeys: String, CodingKey {
        case offsetHours    = "offset_hours"
        case messageTemplate = "message_template"
        case quietHours     = "quiet_hours"
    }
}

// MARK: - QuietHoursWindow + Codable

extension QuietHoursWindow: Codable {
    enum CodingKeys: String, CodingKey {
        case startHour = "start_hour"
        case endHour   = "end_hour"
    }
}
