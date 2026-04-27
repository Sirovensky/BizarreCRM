import SwiftUI
import DesignSystem

// MARK: - §70.1 Default labels in notification preference matrix
//
// Each preference row shows "(default)" in a muted label next to the toggle
// until the user flips it away from the default. Once flipped, the "(default)"
// label disappears and a "Reset" micro-button appears.
//
// Default rule (§70): app-push + in-app for most events; SMS and Email off.
// Critical events (backup failed, security, out of stock, payment declined)
// default push + in-app; never email/SMS by default.

// MARK: - Default preference matrix

public struct NotificationDefaults {
    /// Returns the shipped default preference for a given event.
    public static func `default`(for event: NotificationEvent) -> NotificationPreference {
        let (push, inApp) = defaultDelivery(event)
        return NotificationPreference(
            event: event,
            pushEnabled: push,
            inAppEnabled: inApp,
            emailEnabled: false,
            smsEnabled: false
        )
    }

    private static func defaultDelivery(_ event: NotificationEvent) -> (push: Bool, inApp: Bool) {
        // Per §70 table
        switch event {
        case .ticketAssigned:              return (true,  true)
        case .ticketStatusChangedMine:     return (true,  true)
        case .ticketStatusChangedAnyone:   return (false, true)  // admin-visible only
        case .smsInbound:                  return (true,  true)
        case .smsDeliveryFailed:           return (true,  true)
        case .newCustomerCreated:          return (false, true)
        case .invoiceOverdue:              return (true,  true)
        case .invoicePaid:                 return (true,  true)
        case .estimateApproved:            return (true,  true)
        case .estimateDeclined:            return (true,  true)
        case .appointmentReminder24h:      return (false, true)
        case .appointmentReminder1h:       return (true,  true)
        case .appointmentCanceled:         return (true,  true)
        case .mentionInNote:               return (true,  true)
        case .lowStock:                    return (false, true)
        case .outOfStock:                  return (true,  true)
        case .paymentDeclined:             return (true,  true)
        case .refundProcessed:             return (false, true)
        case .cashRegisterShort:           return (true,  true)
        case .shiftStartedEnded:           return (false, true)
        case .goalAchieved:                return (true,  true)
        case .ptoApprovedDenied:           return (true,  true)
        case .campaignSent:                return (false, true)
        case .npsDetractor:                return (true,  true)
        case .setupWizardIncomplete:       return (false, true)
        case .subscriptionRenewal:         return (false, true)
        case .integrationDisconnected:     return (true,  true)
        case .backupFailed:                return (true,  true)
        case .securityEvent:               return (true,  true)
        }
    }
}

// MARK: - Default label modifier

/// Attaches a "(default)" label to a preference row toggle when the current
/// value matches the shipped default.
public struct NotificationDefaultBadge: View {
    public let event: NotificationEvent
    public let current: NotificationPreference
    public let onReset: () -> Void

    private var isDefault: Bool {
        let def = NotificationDefaults.default(for: event)
        return current.pushEnabled == def.pushEnabled
            && current.inAppEnabled == def.inAppEnabled
            && current.emailEnabled == def.emailEnabled
            && current.smsEnabled == def.smsEnabled
    }

    public init(event: NotificationEvent, current: NotificationPreference, onReset: @escaping () -> Void) {
        self.event = event
        self.current = current
        self.onReset = onReset
    }

    public var body: some View {
        if isDefault {
            Text("(default)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityLabel("Default setting")
        } else {
            Button("Reset", action: onReset)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOrange)
                .buttonStyle(.plain)
                .accessibilityLabel("Reset to default")
                .accessibilityIdentifier("notif.pref.reset.\(event.rawValue)")
        }
    }
}

// MARK: - A11y VoiceOver announcement for preferences count

/// Announces when focus enters the preferences matrix (§70.1 a11y requirement).
public struct NotificationPreferencesCountAnnouncement: View {
    let total: Int
    let modified: Int

    public init(total: Int, modified: Int) {
        self.total = total
        self.modified = modified
    }

    public var body: some View {
        Text(a11yText)
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .accessibilityLabel(a11yText)
    }

    private var a11yText: String {
        if modified == 0 {
            return "\(total) notification events; all at default"
        } else {
            return "\(total) notification events; \(modified) modified from default"
        }
    }
}
