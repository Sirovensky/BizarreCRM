import Foundation

// MARK: - StaffNotificationCategoryExclusions

/// Enforces §70 "Default SMS/Email off" rule for staff-self notifications.
///
/// Certain event × channel combinations carry an explicit warning because:
/// - SMS-to-self on high-volume events clutters personal inboxes.
/// - Users may not realize the app already pushes the event.
///
/// Call `checkExclusion(event:channel:)` before applying a toggle.
/// If a non-nil `ExclusionWarning` is returned, show it to the user and
/// require confirmation before enabling the channel.
public enum StaffNotificationCategoryExclusions {

    // MARK: - ExclusionWarning

    public struct ExclusionWarning: Sendable, Equatable {
        /// Short title for an alert or confirmation dialog.
        public let title: String
        /// Detailed explanation shown in the alert body.
        public let message: String
        /// If true the toggle should be blocked (cannot enable at all).
        /// If false it's a warning requiring user confirmation.
        public let isHardBlock: Bool

        public init(title: String, message: String, isHardBlock: Bool = false) {
            self.title = title
            self.message = message
            self.isHardBlock = isHardBlock
        }
    }

    // MARK: - Public API

    /// Returns a warning if enabling `channel` for `event` requires user confirmation,
    /// or `nil` if the toggle is unrestricted.
    public static func checkExclusion(
        event: NotificationEvent,
        channel: NotificationChannel,
        enabling: Bool
    ) -> ExclusionWarning? {
        guard enabling else { return nil }

        switch channel {
        case .sms:
            return smsWarning(for: event)
        case .email:
            return emailWarning(for: event)
        case .push, .inApp:
            return nil
        }
    }

    // MARK: - SMS exclusion rules

    private static func smsWarning(for event: NotificationEvent) -> ExclusionWarning? {
        if event.isHighVolumeForSMS {
            return ExclusionWarning(
                title: "High SMS Volume",
                message: """
                "\(event.displayName)" can fire many times per day. \
                Enabling SMS will send texts to your personal number and may incur charges. \
                The app already delivers push notifications for this event — SMS is rarely needed.
                """,
                isHardBlock: false
            )
        }

        // Specific event-level blocks
        switch event {
        case .ticketAssigned:
            return ExclusionWarning(
                title: "SMS for Ticket Assignments",
                message: """
                Every ticket assignment sends an SMS to your personal number. \
                In busy shops this may generate 20+ texts per shift. \
                Consider using push notifications instead.
                """,
                isHardBlock: false
            )
        default:
            return nil
        }
    }

    // MARK: - Email exclusion rules

    private static func emailWarning(for event: NotificationEvent) -> ExclusionWarning? {
        switch event {
        case .ticketStatusChangeAny:
            return ExclusionWarning(
                title: "High Email Volume",
                message: """
                "\(event.displayName)" fires on every status change for all tickets. \
                In a busy shop this may flood your inbox. \
                Use In-App or Push notifications instead.
                """,
                isHardBlock: false
            )
        default:
            return nil
        }
    }
}
