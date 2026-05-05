import UserNotifications

// MARK: - NotificationCategoryID

/// Stable string identifiers for every APNs notification category.
/// The raw values match the `category` field the server includes in the APNs
/// payload `aps` dictionary, so the OS can attach the correct action set.
public enum NotificationCategoryID: String, Sendable, CaseIterable {
    case ticketUpdate          = "bizarre.ticket.update"
    case smsReply              = "bizarre.sms.reply"
    case lowStock              = "bizarre.lowstock"
    case appointmentReminder   = "bizarre.appointment.reminder"
    case paymentReceived       = "bizarre.payment.received"
    case paymentFailed         = "bizarre.payment.failed"
    case deadLetterAlert       = "bizarre.deadletter"
    case mention               = "bizarre.mention"
    case scheduleChange        = "bizarre.schedule.change"
}

// MARK: - Action identifiers

/// String constants for notification action identifiers.
/// Keep in one place so `NotificationHandler` can pattern-match them
/// without stringly-typed literals scattered through the codebase.
public enum NotificationActionID {
    // ticket.update
    public static let ticketReply    = "bizarre.ticket.reply"
    public static let ticketView     = "bizarre.ticket.view"
    public static let ticketSnooze1h = "bizarre.ticket.snooze1h"

    // sms.reply
    public static let smsQuickReply  = "bizarre.sms.quickreply"
    public static let smsView        = "bizarre.sms.view"

    // low.stock
    public static let stockReorder   = "bizarre.stock.reorder"
    public static let stockDismiss   = "bizarre.stock.dismiss"

    // appointment.reminder
    public static let apptCall       = "bizarre.appt.call"
    public static let apptSms        = "bizarre.appt.sms"
    public static let apptReschedule = "bizarre.appt.reschedule"

    // payment.received
    public static let paymentView    = "bizarre.payment.view"
    public static let paymentPrint   = "bizarre.payment.print"

    // payment.failed
    public static let paymentFailedOpen  = "bizarre.payment.failed.open"
    public static let paymentRetry       = "bizarre.payment.failed.retry"

    // deadletter.alert
    public static let dlView         = "bizarre.dl.view"
    public static let dlDismiss      = "bizarre.dl.dismiss"

    // mention
    public static let mentionReply   = "bizarre.mention.reply"
    public static let mentionMarkRead = "bizarre.mention.markread"

    // schedule.change
    public static let scheduleView   = "bizarre.schedule.view"
    public static let scheduleAccept = "bizarre.schedule.accept"
}

// MARK: - NotificationCategories

/// Builds the full set of `UNNotificationCategory` objects and registers
/// them with `UNUserNotificationCenter`.
///
/// Call `NotificationCategories.registerAll()` on app launch (after auth).
/// The function is pure and returns the built set so it can be tested
/// without a live `UNUserNotificationCenter`.
public enum NotificationCategories {

    // MARK: - Public API

    /// Build all categories and register them with the notification centre.
    public static func registerWithSystem() {
        let categories = registerAll()
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    /// Build and return all categories without touching `UNUserNotificationCenter`.
    /// This is the testable entry-point.
    public static func registerAll() -> Set<UNNotificationCategory> {
        Set([
            ticketUpdateCategory(),
            smsReplyCategory(),
            lowStockCategory(),
            appointmentReminderCategory(),
            paymentReceivedCategory(),
            paymentFailedCategory(),
            deadLetterAlertCategory(),
            mentionCategory(),
            scheduleChangeCategory()
        ])
    }

    // MARK: - Category builders

    /// `bizarre.ticket.update` — text-input reply + open ticket + snooze 1h.
    private static func ticketUpdateCategory() -> UNNotificationCategory {
        let replyAction = UNTextInputNotificationAction(
            identifier: NotificationActionID.ticketReply,
            title: "Reply to Ticket",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Write a reply…"
        )
        let viewAction = UNNotificationAction(
            identifier: NotificationActionID.ticketView,
            title: "Open Ticket",
            options: [.foreground]
        )
        let snoozeAction = UNNotificationAction(
            identifier: NotificationActionID.ticketSnooze1h,
            title: "Snooze 1 Hour",
            options: []
        )
        return UNNotificationCategory(
            identifier: NotificationCategoryID.ticketUpdate.rawValue,
            actions: [replyAction, viewAction, snoozeAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Ticket update",
            options: [.customDismissAction]
        )
    }

    /// `bizarre.sms.reply` — quick text reply + open thread.
    private static func smsReplyCategory() -> UNNotificationCategory {
        let quickReply = UNTextInputNotificationAction(
            identifier: NotificationActionID.smsQuickReply,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Reply…"
        )
        let viewAction = UNNotificationAction(
            identifier: NotificationActionID.smsView,
            title: "Open Thread",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: NotificationCategoryID.smsReply.rawValue,
            actions: [quickReply, viewAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "New message",
            options: [.customDismissAction]
        )
    }

    /// `bizarre.lowstock` — reorder + dismiss.
    private static func lowStockCategory() -> UNNotificationCategory {
        let reorder = UNNotificationAction(
            identifier: NotificationActionID.stockReorder,
            title: "Reorder",
            options: [.foreground]
        )
        let dismiss = UNNotificationAction(
            identifier: NotificationActionID.stockDismiss,
            title: "Dismiss",
            options: [.destructive]
        )
        return UNNotificationCategory(
            identifier: NotificationCategoryID.lowStock.rawValue,
            actions: [reorder, dismiss],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Low-stock alert",
            options: []
        )
    }

    /// `bizarre.appointment.reminder` — call / SMS / reschedule.
    private static func appointmentReminderCategory() -> UNNotificationCategory {
        let call = UNNotificationAction(
            identifier: NotificationActionID.apptCall,
            title: "Call",
            options: [.foreground]
        )
        let sms = UNNotificationAction(
            identifier: NotificationActionID.apptSms,
            title: "SMS",
            options: [.foreground]
        )
        let reschedule = UNNotificationAction(
            identifier: NotificationActionID.apptReschedule,
            title: "Reschedule",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: NotificationCategoryID.appointmentReminder.rawValue,
            actions: [call, sms, reschedule],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Appointment reminder",
            options: []
        )
    }

    /// `bizarre.payment.received` — view invoice + print receipt.
    private static func paymentReceivedCategory() -> UNNotificationCategory {
        let view = UNNotificationAction(
            identifier: NotificationActionID.paymentView,
            title: "View Invoice",
            options: [.foreground]
        )
        let print_ = UNNotificationAction(
            identifier: NotificationActionID.paymentPrint,
            title: "Print Receipt",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: NotificationCategoryID.paymentReceived.rawValue,
            actions: [view, print_],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Payment received",
            options: []
        )
    }

    /// `bizarre.payment.failed` — open invoice + retry charge.
    private static func paymentFailedCategory() -> UNNotificationCategory {
        let open = UNNotificationAction(
            identifier: NotificationActionID.paymentFailedOpen,
            title: "Open Invoice",
            options: [.foreground]
        )
        let retry = UNNotificationAction(
            identifier: NotificationActionID.paymentRetry,
            title: "Retry Charge",
            options: [.foreground, .authenticationRequired]
        )
        return UNNotificationCategory(
            identifier: NotificationCategoryID.paymentFailed.rawValue,
            actions: [open, retry],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Payment failed",
            options: []
        )
    }

    /// `bizarre.deadletter` — view dead-letter queue + dismiss.
    private static func deadLetterAlertCategory() -> UNNotificationCategory {
        let view = UNNotificationAction(
            identifier: NotificationActionID.dlView,
            title: "View Sync Issues",
            options: [.foreground]
        )
        let dismiss = UNNotificationAction(
            identifier: NotificationActionID.dlDismiss,
            title: "Dismiss",
            options: [.destructive]
        )
        return UNNotificationCategory(
            identifier: NotificationCategoryID.deadLetterAlert.rawValue,
            actions: [view, dismiss],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Sync alert",
            options: []
        )
    }

    /// `bizarre.mention` — text-input reply + mark read.
    private static func mentionCategory() -> UNNotificationCategory {
        let reply = UNTextInputNotificationAction(
            identifier: NotificationActionID.mentionReply,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Reply to mention…"
        )
        let markRead = UNNotificationAction(
            identifier: NotificationActionID.mentionMarkRead,
            title: "Mark as Read",
            options: []
        )
        return UNNotificationCategory(
            identifier: NotificationCategoryID.mention.rawValue,
            actions: [reply, markRead],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Mention",
            options: [.customDismissAction]
        )
    }

    /// `bizarre.schedule.change` — view schedule + accept shift.
    private static func scheduleChangeCategory() -> UNNotificationCategory {
        let view = UNNotificationAction(
            identifier: NotificationActionID.scheduleView,
            title: "View Schedule",
            options: [.foreground]
        )
        let accept = UNNotificationAction(
            identifier: NotificationActionID.scheduleAccept,
            title: "Accept Shift",
            options: []
        )
        return UNNotificationCategory(
            identifier: NotificationCategoryID.scheduleChange.rawValue,
            actions: [view, accept],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Schedule change",
            options: []
        )
    }
}
