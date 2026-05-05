import Foundation
import Networking

// MARK: - ReminderEndpoints

public extension APIClient {
    /// `PATCH /api/v1/tenant/appointment-reminder-policy`
    func updateAppointmentReminderPolicy(_ settings: AppointmentReminderSettings) async throws -> AppointmentReminderSettings {
        try await patch("/api/v1/tenant/appointment-reminder-policy", body: settings, as: AppointmentReminderSettings.self)
    }

    /// `GET /api/v1/tenant/appointment-reminder-policy`
    func fetchAppointmentReminderPolicy() async throws -> AppointmentReminderSettings {
        try await get("/api/v1/tenant/appointment-reminder-policy", as: AppointmentReminderSettings.self)
    }
}
