import Foundation
import UserNotifications
import Core

// MARK: - SmsPushHandler
//
// §12.11 Push notification for new inbound SMS.
//
// Registers notification category `SMS_INBOUND` with three actions:
//   • Reply    — inline text input via UNTextInputNotificationAction
//   • Call     — launches phone call to the thread sender
//   • Open     — deep-links to the SMS thread
//
// Category registration: call `SmsPushHandler.registerCategory()` once on app
// launch (before `UIApplication.registerForRemoteNotifications()`).
//
// Deep-link tap: when the user taps the notification body (not an action),
// `handleResponse(_:)` fires `openSmsThread(phone:)` via NotificationCenter.

public struct SmsPushHandler: Sendable {

    // MARK: - Category identifier

    public static let categoryIdentifier = "SMS_INBOUND"
    public static let actionReply   = "SMS_REPLY"
    public static let actionCall    = "SMS_CALL"
    public static let actionOpen    = "SMS_OPEN"

    // MARK: - Notification name for deep-link broadcast

    /// Posted on `NotificationCenter.default` with `userInfo["phone": String]`
    /// so the navigation layer can push the SMS thread.
    public static let openThreadNotification = Notification.Name("com.bizarrecrm.sms.openThread")

    // MARK: - Registration

    /// Register the `SMS_INBOUND` category. Call once at app launch.
    public static func registerCategory() {
        let replyAction = UNTextInputNotificationAction(
            identifier: actionReply,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message…"
        )
        let callAction = UNNotificationAction(
            identifier: actionCall,
            title: "Call",
            options: .foreground
        )
        let openAction = UNNotificationAction(
            identifier: actionOpen,
            title: "Open",
            options: .foreground
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [replyAction, callAction, openAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Response handling

    /// Call from `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:)`.
    ///
    /// - For `.actionReply`: sends the inline reply text via the SMS repository
    ///   (caller must supply a `SmsThreadRepository` reference).
    /// - For `.actionCall` / `.actionOpen` / body tap: posts `openThreadNotification`.
    public static func handleResponse(
        _ response: UNNotificationResponse,
        send: ((_ phone: String, _ text: String) -> Void)? = nil
    ) {
        let userInfo = response.notification.request.content.userInfo
        let phone = userInfo["phone"] as? String ?? ""

        switch response.actionIdentifier {
        case actionReply:
            if let text = (response as? UNTextInputNotificationResponse)?.userText,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                send?(phone, text)
            }
            // Also open thread so user sees the sent message
            broadcastOpen(phone: phone)

        case actionCall:
            // Deep-link to call; navigation layer converts bizarrecrm://call/:phone
            broadcastOpen(phone: phone, action: "call")

        case actionOpen,
             UNNotificationDefaultActionIdentifier:
            broadcastOpen(phone: phone)

        default:
            break
        }
    }

    // MARK: - Private

    private static func broadcastOpen(phone: String, action: String = "open") {
        NotificationCenter.default.post(
            name: openThreadNotification,
            object: nil,
            userInfo: ["phone": phone, "action": action]
        )
    }
}
