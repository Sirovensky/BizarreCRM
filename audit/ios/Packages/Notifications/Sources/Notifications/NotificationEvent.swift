import Foundation

// MARK: - NotificationEvent

/// All events from §70 notification matrix (~30 cases).
/// Raw values are stable server-side identifiers.
public enum NotificationEvent: String, Sendable, CaseIterable, Identifiable, Codable {

    // Tickets
    case ticketAssigned             = "ticket.assigned"
    case ticketStatusChangeMine     = "ticket.status_change.mine"
    case ticketStatusChangeAny      = "ticket.status_change.any"

    // SMS / Communications
    case smsInbound                 = "sms.inbound"
    case smsDeliveryFailed          = "sms.delivery_failed"

    // Customers
    case newCustomerCreated         = "customer.created"

    // Invoices
    case invoiceOverdue             = "invoice.overdue"
    case invoicePaid                = "invoice.paid"

    // Estimates
    case estimateApproved           = "estimate.approved"
    case estimateDeclined           = "estimate.declined"

    // Appointments
    case appointmentReminder24h     = "appointment.reminder.24h"
    case appointmentReminder1h      = "appointment.reminder.1h"
    case appointmentCanceled        = "appointment.canceled"

    // Collaboration
    case mentionInNote              = "mention.note"

    // Inventory
    case lowStock                   = "inventory.low_stock"
    case outOfStock                 = "inventory.out_of_stock"

    // POS / Payments
    case paymentDeclined            = "payment.declined"
    case refundProcessed            = "payment.refund"
    case cashRegisterShort          = "pos.cash_short"

    // Timeclock
    case shiftStartedEnded          = "timeclock.shift"

    // Goals / HR
    case goalAchieved               = "goal.achieved"
    case ptoApprovedDenied          = "hr.pto_decision"

    // Marketing
    case campaignSent               = "marketing.campaign_sent"

    // CRM
    case npsDetractor               = "crm.nps_detractor"

    // Setup / Admin
    case setupWizardIncomplete      = "setup.wizard_incomplete"
    case subscriptionRenewal        = "billing.subscription_renewal"
    case integrationDisconnected    = "integration.disconnected"
    case backupFailed               = "backup.failed"
    case securityEvent              = "security.event"

    // MARK: - Identifiable

    public var id: String { rawValue }

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .ticketAssigned:             return "Ticket assigned to me"
        case .ticketStatusChangeMine:     return "Ticket status change (mine)"
        case .ticketStatusChangeAny:      return "Ticket status change (anyone)"
        case .smsInbound:                 return "New SMS from customer"
        case .smsDeliveryFailed:          return "SMS delivery failed"
        case .newCustomerCreated:         return "New customer created"
        case .invoiceOverdue:             return "Invoice overdue"
        case .invoicePaid:                return "Invoice paid"
        case .estimateApproved:           return "Estimate approved"
        case .estimateDeclined:           return "Estimate declined"
        case .appointmentReminder24h:     return "Appointment reminder 24h"
        case .appointmentReminder1h:      return "Appointment reminder 1h"
        case .appointmentCanceled:        return "Appointment canceled"
        case .mentionInNote:              return "@mention in note/chat"
        case .lowStock:                   return "Low stock"
        case .outOfStock:                 return "Out of stock"
        case .paymentDeclined:            return "Payment declined"
        case .refundProcessed:            return "Refund processed"
        case .cashRegisterShort:          return "Cash register short"
        case .shiftStartedEnded:          return "Shift started / ended"
        case .goalAchieved:               return "Goal achieved"
        case .ptoApprovedDenied:          return "PTO approved / denied"
        case .campaignSent:               return "Campaign sent"
        case .npsDetractor:               return "NPS detractor"
        case .setupWizardIncomplete:      return "Setup wizard incomplete (24h)"
        case .subscriptionRenewal:        return "Subscription renewal"
        case .integrationDisconnected:    return "Integration disconnected"
        case .backupFailed:               return "Backup failed"
        case .securityEvent:              return "Security event"
        }
    }

    public var category: EventCategory {
        switch self {
        case .ticketAssigned, .ticketStatusChangeMine, .ticketStatusChangeAny:
            return .tickets
        case .smsInbound, .smsDeliveryFailed, .mentionInNote:
            return .communications
        case .newCustomerCreated:
            return .customers
        case .invoiceOverdue, .invoicePaid, .estimateApproved, .estimateDeclined:
            return .billing
        case .appointmentReminder24h, .appointmentReminder1h, .appointmentCanceled:
            return .appointments
        case .lowStock, .outOfStock:
            return .inventory
        case .paymentDeclined, .refundProcessed, .cashRegisterShort:
            return .pos
        case .shiftStartedEnded, .goalAchieved, .ptoApprovedDenied:
            return .staff
        case .campaignSent, .npsDetractor:
            return .marketing
        case .setupWizardIncomplete, .subscriptionRenewal, .integrationDisconnected, .backupFailed, .securityEvent:
            return .admin
        }
    }

    // MARK: - Default state per §70 matrix

    public var defaultPush: Bool {
        switch self {
        case .ticketAssigned, .ticketStatusChangeMine, .smsInbound, .smsDeliveryFailed,
             .invoiceOverdue, .invoicePaid, .estimateApproved, .estimateDeclined,
             .appointmentReminder1h, .appointmentCanceled, .mentionInNote,
             .outOfStock, .paymentDeclined, .cashRegisterShort, .goalAchieved, .ptoApprovedDenied,
             .npsDetractor, .integrationDisconnected, .backupFailed, .securityEvent:
            return true
        default:
            return false
        }
    }

    public var defaultInApp: Bool { true } // All events have in-app on by default

    public var defaultEmail: Bool { false } // All email off by default per §70

    public var defaultSms: Bool { false }   // All SMS off by default per §70

    // MARK: - High-volume events (warn on SMS enable)

    public var isHighVolumeForSMS: Bool {
        switch self {
        case .ticketStatusChangeAny, .smsInbound, .newCustomerCreated:
            return true
        default:
            return false
        }
    }

    // MARK: - Critical (timeSensitive) per §70.4

    public var isCritical: Bool {
        switch self {
        case .backupFailed, .securityEvent, .outOfStock, .paymentDeclined:
            return true
        default:
            return false
        }
    }
}

// MARK: - EventCategory

public enum EventCategory: String, Sendable, CaseIterable, Hashable {
    case tickets        = "Tickets"
    case communications = "Communications"
    case customers      = "Customers"
    case billing        = "Billing"
    case appointments   = "Appointments"
    case inventory      = "Inventory"
    case pos            = "POS"
    case staff          = "Staff"
    case marketing      = "Marketing"
    case admin          = "Admin"
}
