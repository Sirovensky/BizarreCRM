#if canImport(UIKit)
import Foundation
import UserNotifications
import Core

// MARK: - §10.5 Appointment Local Notification Handler
//
// Handles silent APNs that arrive when app is foregrounded.
// Shows actionable `UNUserNotificationCenter` banners with
// "Call / SMS / Mark arrived" buttons.
//
// Server cron sends APNs N min before appointment. The push
// carries category "APPOINTMENT_REMINDER" so the system
// can offer inline actions when in background.
//
// This actor is called by the app delegate's
// `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`.

public actor AppointmentLocalNotificationHandler {

    // MARK: - Notification category identifier

    public static let categoryIdentifier = "APPOINTMENT_REMINDER"

    // MARK: - Action identifiers

    public enum ActionIdentifier: String {
        case call    = "APPT_CALL"
        case sms     = "APPT_SMS"
        case arrive  = "APPT_MARK_ARRIVED"
    }

    // MARK: - Registration

    /// Register the appointment reminder notification category with actions.
    /// Call this on app launch before requesting push authorization.
    public static func registerCategory() {
        let callAction = UNNotificationAction(
            identifier: ActionIdentifier.call.rawValue,
            title: "Call customer",
            options: .foreground
        )
        let smsAction = UNNotificationAction(
            identifier: ActionIdentifier.sms.rawValue,
            title: "SMS customer",
            options: .foreground
        )
        let arrivedAction = UNNotificationAction(
            identifier: ActionIdentifier.arrive.rawValue,
            title: "Mark arrived",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [callAction, smsAction, arrivedAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Appointment reminder",
            options: .customDismissAction
        )

        UNUserNotificationCenter.current()
            .setNotificationCategories([category])
    }

    // MARK: - Silent push handler

    /// Called from app delegate's silent-push handler.
    /// Parses the push payload and shows a local banner when the app is foregrounded.
    ///
    /// - Returns: The appointment ID extracted from the payload (for deep-link routing).
    @discardableResult
    public static func handleSilentPush(
        userInfo: [AnyHashable: Any]
    ) async -> Int64? {
        guard let aps = userInfo["aps"] as? [String: Any],
              let contentAvailable = aps["content-available"] as? Int,
              contentAvailable == 1 else { return nil }

        guard let apptId = userInfo["appointment_id"].flatMap({ Int64("\($0)") }),
              let customerName = userInfo["customer_name"] as? String,
              let apptTime = userInfo["appointment_time"] as? String,
              let minutesBefore = userInfo["minutes_before"].flatMap({ Int("\($0)") })
        else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming appointment"
        content.body = "\(customerName) — \(apptTime) (in \(minutesBefore) min)"
        content.categoryIdentifier = categoryIdentifier
        content.sound = .default
        content.userInfo = ["appointment_id": apptId]

        let request = UNNotificationRequest(
            identifier: "appt-reminder-\(apptId)",
            content: content,
            trigger: nil     // immediate local delivery
        )

        try? await UNUserNotificationCenter.current().add(request)
        AppLog.notifications.info(
            "Queued local appointment reminder for appt \(apptId, privacy: .public)"
        )
        return apptId
    }
}

// MARK: - §10.5 Live Activity support note
//
// "Next appt in 15 min" Live Activity is implemented in `App/Intents/` (Agent 9 domain).
// The Appointments package exposes the appointment data; the Intents target wires
// the `ActivityKit` Live Activity. A `LiveActivityStartRequest` is posted here when
// the silent push fires with minutes_before == 15.

public struct AppointmentLiveActivityStartRequest: Sendable {
    public let appointmentId: Int64
    public let customerName: String
    public let appointmentTime: Date
    public let minutesRemaining: Int

    public init(
        appointmentId: Int64,
        customerName: String,
        appointmentTime: Date,
        minutesRemaining: Int
    ) {
        self.appointmentId = appointmentId
        self.customerName = customerName
        self.appointmentTime = appointmentTime
        self.minutesRemaining = minutesRemaining
    }
}
#endif
