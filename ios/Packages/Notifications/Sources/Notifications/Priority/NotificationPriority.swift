import Foundation
import SwiftUI
import DesignSystem

// MARK: - NotificationPriority

/// Priority levels for in-app notifications and APNs delivery.
/// The server sends `apns-priority` header (10 = high, 5 = normal);
/// the client maps that to this enum and renders a `PriorityBadge`.
public enum NotificationPriority: Int, Sendable, CaseIterable, Codable, Comparable {
    case low           = 0
    case normal        = 1
    case timeSensitive = 2
    case critical      = 3

    // MARK: - Comparable

    public static func < (lhs: NotificationPriority, rhs: NotificationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .low:           return "Low"
        case .normal:        return "Normal"
        case .timeSensitive: return "Time Sensitive"
        case .critical:      return "Critical"
        }
    }

    /// SF Symbol name for each priority level.
    public var iconName: String {
        switch self {
        case .low:           return "arrow.down.circle"
        case .normal:        return "circle"
        case .timeSensitive: return "exclamationmark.circle"
        case .critical:      return "exclamationmark.triangle.fill"
        }
    }

    /// Brand color token for each priority level.
    public var color: Color {
        switch self {
        case .low:           return Color.bizarreOnSurfaceMuted
        case .normal:        return Color.bizarreTeal
        case .timeSensitive: return Color.bizarreWarning
        case .critical:      return Color.bizarreError
        }
    }

    /// VoiceOver-friendly label announcing priority to assistive tech.
    public var accessibilityLabel: String {
        switch self {
        case .low:           return "Low priority"
        case .normal:        return "Normal priority"
        case .timeSensitive: return "Time sensitive"
        case .critical:      return "Critical alert"
        }
    }

    // MARK: - §70 event mapping

    /// Map a `NotificationEvent` to its default priority per §70 matrix.
    public static func defaultPriority(for event: NotificationEvent) -> NotificationPriority {
        switch event {
        // Critical: immediate action required
        case .backupFailed, .securityEvent, .paymentDeclined, .outOfStock:
            return .critical

        // Time-sensitive: SLA / real-time
        case .ticketAssigned, .smsInbound, .appointmentReminder1h,
             .cashRegisterShort, .mentionInNote, .invoiceOverdue:
            return .timeSensitive

        // Normal: routine operational
        case .ticketStatusChangeMine, .ticketStatusChangeAny, .smsDeliveryFailed,
             .invoicePaid, .estimateApproved, .estimateDeclined,
             .appointmentReminder24h, .appointmentCanceled,
             .lowStock, .refundProcessed, .shiftStartedEnded,
             .goalAchieved, .ptoApprovedDenied, .npsDetractor,
             .integrationDisconnected:
            return .normal

        // Low: informational / digest-ready
        case .newCustomerCreated, .campaignSent, .setupWizardIncomplete,
             .subscriptionRenewal:
            return .low
        }
    }

    // MARK: - APNs priority header

    /// `apns-priority` header value (5 = low/normal, 10 = high).
    /// Critical / timeSensitive → 10; low / normal → 5.
    public var apnsPriorityHeader: Int {
        switch self {
        case .low, .normal:           return 5
        case .timeSensitive, .critical: return 10
        }
    }
}
