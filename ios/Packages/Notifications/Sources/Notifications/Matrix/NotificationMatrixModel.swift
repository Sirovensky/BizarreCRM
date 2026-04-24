import Foundation

// MARK: - NotificationMatrixModel
//
// §70 Granular Per-Event Notification Matrix
//
// Represents the full event × channel toggle matrix.
// Immutable — always produce new copies; never mutate in place.

// MARK: - MatrixChannel

/// The three delivery channels exposed in the §70 matrix UI.
/// In-App is always on (managed separately by the app) and is not surfaced here.
public enum MatrixChannel: String, Sendable, CaseIterable, Identifiable, Codable {
    case push  = "push"
    case email = "email"
    case sms   = "sms"

    public var id: String { rawValue }

    /// Human-readable label for column headers.
    public var displayLabel: String {
        switch self {
        case .push:  return "Push"
        case .email: return "Email"
        case .sms:   return "SMS"
        }
    }

    /// SF Symbol name for the channel icon.
    public var symbolName: String {
        switch self {
        case .push:  return "bell.fill"
        case .email: return "envelope.fill"
        case .sms:   return "message.fill"
        }
    }
}

// MARK: - MatrixEventCategory

/// Ordered categories matching §70 requirements:
/// Tickets / Invoices / Customers / POS / System (+others from NotificationEvent).
public enum MatrixEventCategory: String, Sendable, CaseIterable, Identifiable {
    case tickets        = "Tickets"
    case invoices       = "Invoices"
    case customers      = "Customers"
    case pos            = "POS"
    case system         = "System"
    case communications = "Communications"
    case appointments   = "Appointments"
    case inventory      = "Inventory"
    case staff          = "Staff"
    case marketing      = "Marketing"

    public var id: String { rawValue }

    /// SF Symbol name for the category sidebar icon.
    public var symbolName: String {
        switch self {
        case .tickets:        return "wrench.and.screwdriver"
        case .invoices:       return "doc.text.fill"
        case .customers:      return "person.fill"
        case .pos:            return "creditcard.fill"
        case .system:         return "gear.badge"
        case .communications: return "message.fill"
        case .appointments:   return "calendar"
        case .inventory:      return "shippingbox.fill"
        case .staff:          return "person.2.fill"
        case .marketing:      return "megaphone.fill"
        }
    }

    /// Map from the existing EventCategory to MatrixEventCategory.
    /// Billing → invoices; admin → system; all others map directly.
    static func from(_ category: EventCategory) -> MatrixEventCategory {
        switch category {
        case .tickets:        return .tickets
        case .communications: return .communications
        case .customers:      return .customers
        case .billing:        return .invoices
        case .appointments:   return .appointments
        case .inventory:      return .inventory
        case .pos:            return .pos
        case .staff:          return .staff
        case .marketing:      return .marketing
        case .admin:          return .system
        }
    }
}

// MARK: - MatrixRow

/// One row in the matrix: a single event × all three channel states.
/// Immutable value type.
public struct MatrixRow: Sendable, Identifiable, Equatable {
    public let event: NotificationEvent
    public let pushEnabled: Bool
    public let emailEnabled: Bool
    public let smsEnabled: Bool
    public let quietHours: QuietHours?

    public var id: String { event.rawValue }

    public var category: MatrixEventCategory {
        MatrixEventCategory.from(event.category)
    }

    public init(
        event: NotificationEvent,
        pushEnabled: Bool,
        emailEnabled: Bool,
        smsEnabled: Bool,
        quietHours: QuietHours? = nil
    ) {
        self.event = event
        self.pushEnabled = pushEnabled
        self.emailEnabled = emailEnabled
        self.smsEnabled = smsEnabled
        self.quietHours = quietHours
    }

    // MARK: - Derived from existing NotificationPreference

    /// Build a MatrixRow from the richer NotificationPreference type.
    public init(from pref: NotificationPreference) {
        self.init(
            event: pref.event,
            pushEnabled: pref.pushEnabled,
            emailEnabled: pref.emailEnabled,
            smsEnabled: pref.smsEnabled,
            quietHours: pref.quietHours
        )
    }

    // MARK: - Immutable toggle

    /// Returns a new MatrixRow with the specified channel toggled. Never mutates self.
    public func toggling(_ channel: MatrixChannel) -> MatrixRow {
        MatrixRow(
            event: event,
            pushEnabled:  channel == .push  ? !pushEnabled  : pushEnabled,
            emailEnabled: channel == .email ? !emailEnabled : emailEnabled,
            smsEnabled:   channel == .sms   ? !smsEnabled   : smsEnabled,
            quietHours: quietHours
        )
    }

    /// Returns a new MatrixRow with updated quiet hours. Never mutates self.
    public func withQuietHours(_ qh: QuietHours?) -> MatrixRow {
        MatrixRow(
            event: event,
            pushEnabled: pushEnabled,
            emailEnabled: emailEnabled,
            smsEnabled: smsEnabled,
            quietHours: qh
        )
    }

    /// Whether the channel is currently enabled.
    public func isEnabled(_ channel: MatrixChannel) -> Bool {
        switch channel {
        case .push:  return pushEnabled
        case .email: return emailEnabled
        case .sms:   return smsEnabled
        }
    }

    // MARK: - Conversion back to NotificationPreference (for repository save)

    /// Convert back to a NotificationPreference for use with the existing repository.
    /// In-app is preserved from the original or set to default.
    public func toPreference(inAppEnabled: Bool = true) -> NotificationPreference {
        NotificationPreference(
            event: event,
            pushEnabled: pushEnabled,
            inAppEnabled: inAppEnabled,
            emailEnabled: emailEnabled,
            smsEnabled: smsEnabled,
            quietHours: quietHours
        )
    }
}

// MARK: - NotificationMatrixModel

/// Full event × channel matrix. Organises MatrixRow values by category.
/// Immutable snapshot — new model produced on each save/load cycle.
public struct NotificationMatrixModel: Sendable, Equatable {

    public let rows: [MatrixRow]

    public init(rows: [MatrixRow]) {
        self.rows = rows
    }

    // MARK: - Factories

    /// Build from an array of NotificationPreference values (full matrix from repository).
    public static func build(from preferences: [NotificationPreference]) -> NotificationMatrixModel {
        // Index preferences for O(1) lookup.
        var indexed: [NotificationEvent: NotificationPreference] = [:]
        for pref in preferences { indexed[pref.event] = pref }

        // Keep event order canonical (allCases order).
        let rows = NotificationEvent.allCases.map { event in
            if let pref = indexed[event] {
                return MatrixRow(from: pref)
            }
            // Fallback to defaults if server didn't return the event.
            let def = NotificationPreference.defaultPreference(for: event)
            return MatrixRow(from: def)
        }
        return NotificationMatrixModel(rows: rows)
    }

    /// Build the factory-default matrix (all server defaults).
    public static var defaults: NotificationMatrixModel {
        build(from: NotificationEvent.allCases.map { .defaultPreference(for: $0) })
    }

    // MARK: - Queries

    /// Rows for a given category, in canonical event order.
    public func rows(for category: MatrixEventCategory) -> [MatrixRow] {
        rows.filter { $0.category == category }
    }

    /// Produce a new model with a single row replaced. Immutable.
    public func replacing(row: MatrixRow) -> NotificationMatrixModel {
        let updated = rows.map { $0.event == row.event ? row : $0 }
        return NotificationMatrixModel(rows: updated)
    }

    /// Convert all rows back to NotificationPreference for batch repository save.
    public func toPreferences(originalPreferences: [NotificationPreference] = []) -> [NotificationPreference] {
        // Preserve inAppEnabled from originals when available.
        var inAppMap: [NotificationEvent: Bool] = [:]
        for pref in originalPreferences { inAppMap[pref.event] = pref.inAppEnabled }

        return rows.map { row in
            let inApp = inAppMap[row.event] ?? true
            return row.toPreference(inAppEnabled: inApp)
        }
    }
}
