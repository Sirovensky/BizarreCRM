import Foundation
import UserNotifications
import Core
import Networking

// MARK: - DeepLinkHandling

/// Protocol that `DeepLinkRouter` (App target) conforms to.
/// Keeps this package free of a direct App target dependency.
public protocol DeepLinkHandling: AnyObject, Sendable {
    @MainActor func handle(_ url: URL)
}

// MARK: - NotificationReplyPoster

/// Protocol for posting inline reply actions back to the server.
/// Implemented by feature repositories that already import the Networking stack.
public protocol NotificationReplyPoster: Sendable {
    /// Post an inline reply triggered from a notification action.
    func postReply(categoryID: String, entityId: String?, text: String) async throws
}

// MARK: - NotificationHandler

/// `UNUserNotificationCenterDelegate` implementation.
///
/// Wire from `BizarreCRMApp.swift` or `AppDelegate`:
/// ```swift
/// // 1. Create once and retain:
/// let notificationHandler = NotificationHandler(deepLinkRouter: DeepLinkRouter.shared)
///
/// // 2. Register on UNUserNotificationCenter BEFORE app finishes launching:
/// UNUserNotificationCenter.current().delegate = notificationHandler
///
/// // 3. Register categories on launch:
/// NotificationCategories.registerWithSystem()
/// ```
///
/// Entitlements + Info.plist required (documented in PushRegistrar.swift):
/// - `aps-environment` in `BizarreCRM.entitlements`
/// - `remote-notification` in `UIBackgroundModes` (already present in write-info-plist.sh)
@MainActor
public final class NotificationHandler: NSObject, @preconcurrency UNUserNotificationCenterDelegate, Sendable {

    // MARK: - Shared

    public static let shared = NotificationHandler()

    // MARK: - Dependencies

    private weak var deepLinkRouter: (any DeepLinkHandling)?
    private var replyPoster: (any NotificationReplyPoster)?

    // MARK: - Init

    public init(
        deepLinkRouter: (any DeepLinkHandling)? = nil,
        replyPoster: (any NotificationReplyPoster)? = nil
    ) {
        self.deepLinkRouter = deepLinkRouter
        self.replyPoster = replyPoster
        super.init()
    }

    /// Set dependencies after creation (avoids circular init dependency).
    public func configure(
        deepLinkRouter: any DeepLinkHandling,
        replyPoster: (any NotificationReplyPoster)? = nil
    ) {
        self.deepLinkRouter = deepLinkRouter
        self.replyPoster = replyPoster
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners in the foreground.
    ///
    /// §13.2 Quiet hours — when the user is inside their configured quiet-hours
    /// window, non-time-sensitive banners are suppressed (the badge still
    /// updates so the unread count stays accurate). Time-sensitive / critical
    /// events bypass quiet hours via `QuietHoursGate.shouldSuppress`.
    ///
    /// §13.2 Notification-summary — for time-sensitive event types (overdue
    /// invoice, SLA breach, payment declined, security event, etc.), iOS 15+
    /// `interruptionLevel: .timeSensitive` is set on the incoming content so
    /// the notification escapes Focus / Scheduled Summary.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let eventType = userInfo["event_type"] as? String ?? ""

        // §13.2 Notification-summary: stamp .timeSensitive on the live content
        // for time-sensitive events so iOS Scheduled Summary releases it
        // immediately. (Server-pushed APNs already carries this via the NSE
        // bridge, but local re-fires and synthetic foreground events go through
        // `willPresent` without traversing the NSE.)
        if #available(iOS 15.0, *) {
            let level = NotificationInterruptionLevelMapper.level(for: eventType)
            if let mutable = notification.request.content.mutableCopy() as? UNMutableNotificationContent,
               mutable.interruptionLevel != level {
                mutable.interruptionLevel = level
            }
        }

        // §13.2 Quiet hours gate. Suppress banner + sound for non-critical
        // events when inside the user's quiet-hours window. Badge still
        // updates so unread counts remain accurate; the user will see the
        // notification in the list without an audible interrupt.
        if #available(iOS 15.0, *), QuietHoursGate.shouldSuppress(eventType: eventType) {
            AppLog.ui.debug("Notification suppressed by quiet-hours: \(eventType, privacy: .public)")
            completionHandler([.badge])
            return
        }

        // Always show banner + sound + badge while app is in foreground.
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle user taps + inline action buttons.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo
        let actionID = response.actionIdentifier
        let categoryID = response.notification.request.content.categoryIdentifier
        let entityId = userInfo["entityId"] as? String ?? userInfo["entity_id"] as? String

        switch actionID {

        // Default tap → deep-link
        case UNNotificationDefaultActionIdentifier:
            handleDeepLink(userInfo: userInfo)

        // Ticket: inline reply text
        case NotificationActionID.ticketReply:
            if let textResponse = response as? UNTextInputNotificationResponse {
                Task {
                    await postReply(
                        categoryID: categoryID,
                        entityId: entityId,
                        text: textResponse.userText
                    )
                }
            }

        // Ticket: snooze 1 hour
        case NotificationActionID.ticketSnooze1h:
            scheduleSnooze(for: response.notification, delay: 3600)

        // SMS quick reply
        case NotificationActionID.smsQuickReply:
            if let textResponse = response as? UNTextInputNotificationResponse {
                Task {
                    await postReply(
                        categoryID: categoryID,
                        entityId: entityId,
                        text: textResponse.userText
                    )
                }
            }

        // Mention inline reply
        case NotificationActionID.mentionReply:
            if let textResponse = response as? UNTextInputNotificationResponse {
                Task {
                    await postReply(
                        categoryID: categoryID,
                        entityId: entityId,
                        text: textResponse.userText
                    )
                }
            }

        // Mention mark read — foreground open then mark
        case NotificationActionID.mentionMarkRead:
            handleDeepLink(userInfo: userInfo)

        // All foreground-open actions — view / call / sms / reorder / accept / print
        case NotificationActionID.ticketView,
             NotificationActionID.smsView,
             NotificationActionID.apptCall,
             NotificationActionID.apptSms,
             NotificationActionID.apptReschedule,
             NotificationActionID.stockReorder,
             NotificationActionID.paymentView,
             NotificationActionID.paymentPrint,
             NotificationActionID.dlView,
             NotificationActionID.scheduleView,
             NotificationActionID.scheduleAccept:
            handleDeepLink(userInfo: userInfo)

        // Dismiss actions — nothing to do
        case NotificationActionID.stockDismiss, NotificationActionID.dlDismiss:
            break

        default:
            AppLog.ui.debug("NotificationHandler: unhandled action '\(actionID, privacy: .public)'")
        }
    }

    // MARK: - Helpers

    private func handleDeepLink(userInfo: [AnyHashable: Any]) {
        guard let deepLinkString = userInfo["deepLink"] as? String,
              let url = URL(string: deepLinkString),
              let router = deepLinkRouter
        else { return }
        router.handle(url)
    }

    private func postReply(categoryID: String, entityId: String?, text: String) async {
        guard let poster = replyPoster else {
            AppLog.ui.error("NotificationHandler: no replyPoster configured for inline reply")
            return
        }
        do {
            try await poster.postReply(categoryID: categoryID, entityId: entityId, text: text)
        } catch {
            AppLog.ui.error("NotificationHandler: reply post failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Schedule a local notification to re-fire after `delay` seconds.
    private func scheduleSnooze(for notification: UNNotification, delay: TimeInterval) {
        let content = notification.request.content.mutableCopy() as! UNMutableNotificationContent
        // §13.2 Notification-summary — preserve / promote the interruption
        // level on the snoozed re-fire so overdue / SLA-breach events still
        // bypass Focus & Scheduled Summary when they reappear.
        if #available(iOS 15.0, *) {
            let eventType = content.userInfo["event_type"] as? String ?? ""
            content.interruptionLevel = NotificationInterruptionLevelMapper.level(for: eventType)
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let id = "snooze-\(notification.request.identifier)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLog.ui.error("Snooze schedule failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
