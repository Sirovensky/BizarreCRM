import Foundation
import UserNotifications

// MARK: - NotificationContentExtensionConfig (§13.2)
//
// Configuration model for the Notification Content Extension (NCE) target.
//
// The NCE renders a custom UI inside the iOS notification preview when the user
// long-presses (3D Touch / Haptic Touch) a banner or expands a notification in
// Notification Centre.  This file centralises the per-category extension config
// so the NCE Info.plist values, `hiddenPreviewsBodyPlaceholder` strings, and
// the matching `UNNotificationCategory` are all derived from a single source of
// truth.
//
// ## Wiring
//
// 1. Create a new **Notification Content Extension** target in Xcode.
//    - Target name: `BizarreCRMNotificationContent`
//    - Bundle ID: `com.bizarrecrm.app.NotificationContent`
// 2. Set the NCE target's Info.plist `NSExtension → NSExtensionAttributes →
//    UNNotificationExtensionCategory` to the array of `categoryIdentifier`
//    values from `NotificationContentExtensionConfig.all`.
// 3. Set `UNNotificationExtensionInitialContentSizeRatio` per
//    `contentSizeRatio` below (controls the preview height as a fraction of
//    the view width).
// 4. Set `UNNotificationExtensionDefaultContentHidden` to `YES` for categories
//    that completely replace the default body with custom UI.
// 5. In the NCE's `NotificationViewController.didReceive(_:)`, call
//    `NotificationContentExtensionConfig.config(forCategory:)` to obtain the
//    rendering parameters without duplicating the switch.
//
// ## Privacy
//
// `hiddenPreviewsBodyPlaceholder` is shown on the Lock Screen when the device
// privacy setting is "When Unlocked" or "Never".  Strings must not reveal
// entity-specific data (ticket IDs, phone numbers, amounts).  Each category
// below uses a generic placeholder appropriate for that alert type.

// MARK: - Config model

/// Per-category configuration for the Notification Content Extension.
public struct NotificationContentExtensionConfig: Sendable {

    /// The category identifier this config applies to.  Must match the
    /// `UNNotificationCategory.identifier` registered in `NotificationCategories`.
    public let categoryIdentifier: String

    /// Displayed on the Lock Screen when the system privacy level hides
    /// notification previews.  Must NOT contain entity-specific details.
    public let hiddenPreviewsBodyPlaceholder: String

    /// Initial height of the custom content view as a fraction of its width.
    /// Set in `UNNotificationExtensionInitialContentSizeRatio` in Info.plist.
    /// Typical values: 0.5 (landscape card), 1.0 (square), 1.5 (portrait card).
    public let contentSizeRatio: Double

    /// When `true`, the NCE replaces the default title/body UI entirely
    /// (`UNNotificationExtensionDefaultContentHidden = YES`).
    /// When `false`, custom content appears below the standard header.
    public let hidesDefaultContent: Bool

    /// Human-readable label used in Xcode / build scripts when populating
    /// the NCE Info.plist automatically.
    public let displayName: String

    public init(
        categoryIdentifier: String,
        hiddenPreviewsBodyPlaceholder: String,
        contentSizeRatio: Double,
        hidesDefaultContent: Bool,
        displayName: String
    ) {
        self.categoryIdentifier = categoryIdentifier
        self.hiddenPreviewsBodyPlaceholder = hiddenPreviewsBodyPlaceholder
        self.contentSizeRatio = contentSizeRatio
        self.hidesDefaultContent = hidesDefaultContent
        self.displayName = displayName
    }
}

// MARK: - Registry

public extension NotificationContentExtensionConfig {

    /// Canonical config for every push category that has a custom preview.
    ///
    /// Categories not listed here do not use the NCE and rely on the default
    /// system preview rendering.
    static let all: [NotificationContentExtensionConfig] = [
        ticketUpdate,
        smsReply,
        appointmentReminder,
        paymentReceived,
        paymentFailed,
        mention,
    ]

    /// Look up the config for a given category identifier.
    ///
    /// Returns `nil` for categories that do not use the content extension.
    static func config(forCategory categoryIdentifier: String) -> NotificationContentExtensionConfig? {
        all.first { $0.categoryIdentifier == categoryIdentifier }
    }

    // MARK: - Per-category configs

    /// Ticket update — shows ticket status card with assignee avatar + status chip.
    static let ticketUpdate = NotificationContentExtensionConfig(
        categoryIdentifier: NotificationCategoryID.ticketUpdate.rawValue,
        hiddenPreviewsBodyPlaceholder: "Ticket update",
        contentSizeRatio: 0.6,
        hidesDefaultContent: false,
        displayName: "Ticket Update"
    )

    /// SMS inbound — shows message bubble preview with sender avatar.
    static let smsReply = NotificationContentExtensionConfig(
        categoryIdentifier: NotificationCategoryID.smsReply.rawValue,
        hiddenPreviewsBodyPlaceholder: "New message",
        contentSizeRatio: 0.5,
        hidesDefaultContent: false,
        displayName: "SMS Message"
    )

    /// Appointment reminder — shows appointment card: customer name, time, device.
    static let appointmentReminder = NotificationContentExtensionConfig(
        categoryIdentifier: NotificationCategoryID.appointmentReminder.rawValue,
        hiddenPreviewsBodyPlaceholder: "Appointment reminder",
        contentSizeRatio: 0.55,
        hidesDefaultContent: false,
        displayName: "Appointment Reminder"
    )

    /// Payment received — shows invoice summary card with amount and customer.
    static let paymentReceived = NotificationContentExtensionConfig(
        categoryIdentifier: NotificationCategoryID.paymentReceived.rawValue,
        hiddenPreviewsBodyPlaceholder: "Payment received",
        contentSizeRatio: 0.45,
        hidesDefaultContent: false,
        displayName: "Payment Received"
    )

    /// Payment failed — shows invoice + failure reason; retry CTA prominent.
    static let paymentFailed = NotificationContentExtensionConfig(
        categoryIdentifier: NotificationCategoryID.paymentFailed.rawValue,
        hiddenPreviewsBodyPlaceholder: "Payment failed",
        contentSizeRatio: 0.45,
        hidesDefaultContent: false,
        displayName: "Payment Failed"
    )

    /// Mention — shows note excerpt with author name.
    static let mention = NotificationContentExtensionConfig(
        categoryIdentifier: NotificationCategoryID.mention.rawValue,
        hiddenPreviewsBodyPlaceholder: "Mention",
        contentSizeRatio: 0.5,
        hidesDefaultContent: false,
        displayName: "Mention"
    )
}

// MARK: - Info.plist generation helper

public extension NotificationContentExtensionConfig {

    /// Returns an array of category identifiers suitable for the
    /// `UNNotificationExtensionCategory` key in the NCE Info.plist.
    ///
    /// Use this from a build-phase script to keep the plist in sync:
    ///
    /// ```bash
    /// swift run NotificationContentExtensionPlistUpdater
    /// ```
    static var categoryIdentifiers: [String] {
        all.map(\.categoryIdentifier)
    }
}
