import Foundation

// MARK: - HandoffActivityType

/// Typed activity-type identifiers used with `NSUserActivity` for Handoff
/// and Spotlight integration.
///
/// Each case maps to a unique reverse-DNS activity type string registered
/// in the app's `NSUserActivityTypes` Info.plist key.
///
/// Thread-safe: value-type enum with no mutable state.
public enum HandoffActivityType: String, Sendable, CaseIterable {

    // MARK: - Detail screens (Handoff-eligible per `HandoffEligibility`)

    /// Viewing a service ticket.
    case ticketDetail = "com.bizarrecrm.ticket.detail"

    /// Viewing a customer record.
    case customerDetail = "com.bizarrecrm.customer.detail"

    /// Viewing an invoice.
    case invoiceDetail = "com.bizarrecrm.invoice.detail"

    /// Viewing an estimate.
    case estimateDetail = "com.bizarrecrm.estimate.detail"

    // MARK: - Convenience

    /// The raw activity-type string suitable for `NSUserActivity.activityType`.
    public var activityTypeIdentifier: String { rawValue }
}

// MARK: - HandoffActivityType + init(destination:)

extension HandoffActivityType {

    /// Returns the activity type for a given `DeepLinkDestination`, or `nil`
    /// when the destination does not map to a known Handoff activity.
    ///
    /// Only detail screens for tickets, customers, invoices, and estimates
    /// are Handoff-eligible; other destinations return `nil`.
    public init?(destination: DeepLinkDestination) {
        switch destination {
        case .ticket:    self = .ticketDetail
        case .customer:  self = .customerDetail
        case .invoice:   self = .invoiceDetail
        case .estimate:  self = .estimateDetail
        default:         return nil
        }
    }
}
