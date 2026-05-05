import Foundation

/// Serializable snapshot written by the main app into the shared App Group
/// UserDefaults and consumed read-only by the widget extension.
///
/// App Group suite name: `group.com.bizarrecrm`
public struct WidgetSnapshot: Codable, Sendable, Equatable {

    // MARK: - Nested types

    public struct TicketSummary: Codable, Sendable, Equatable, Identifiable {
        public let id: Int64
        public let displayId: String
        public let customerName: String
        public let status: String          // TicketStatus.rawValue
        public let deviceSummary: String?

        public init(
            id: Int64,
            displayId: String,
            customerName: String,
            status: String,
            deviceSummary: String? = nil
        ) {
            self.id = id
            self.displayId = displayId
            self.customerName = customerName
            self.status = status
            self.deviceSummary = deviceSummary
        }
    }

    public struct AppointmentSummary: Codable, Sendable, Equatable, Identifiable {
        public let id: Int64
        public let customerName: String
        public let scheduledAt: Date

        public init(id: Int64, customerName: String, scheduledAt: Date) {
            self.id = id
            self.customerName = customerName
            self.scheduledAt = scheduledAt
        }
    }

    // MARK: - Properties

    /// Number of non-completed, non-archived open tickets.
    public let openTicketCount: Int

    /// Up to 10 most-recent open tickets (sorted by updatedAt desc).
    public let latestTickets: [TicketSummary]

    /// Revenue total for today in cents.
    public let revenueTodayCents: Int

    /// Revenue total for yesterday in cents (for delta calculation).
    public let revenueYesterdayCents: Int

    /// Next 3 appointments sorted by scheduledAt asc.
    public let nextAppointments: [AppointmentSummary]

    /// Up to 5 tickets currently assigned to the signed-in technician (my queue).
    /// Written by the main app on sync using the current user's employee ID.
    /// Empty when no user is signed in or no tickets are assigned.
    public let myQueueTickets: [TicketSummary]

    /// Timestamp of last successful write.
    public let lastUpdated: Date

    // MARK: - Init

    public init(
        openTicketCount: Int,
        latestTickets: [TicketSummary] = [],
        revenueTodayCents: Int,
        revenueYesterdayCents: Int,
        nextAppointments: [AppointmentSummary] = [],
        myQueueTickets: [TicketSummary] = [],
        lastUpdated: Date
    ) {
        self.openTicketCount = openTicketCount
        self.latestTickets = Array(latestTickets.prefix(10))
        self.revenueTodayCents = revenueTodayCents
        self.revenueYesterdayCents = revenueYesterdayCents
        self.nextAppointments = Array(nextAppointments.prefix(3))
        self.myQueueTickets = Array(myQueueTickets.prefix(5))
        self.lastUpdated = lastUpdated
    }

    // MARK: - Derived

    /// Revenue delta in cents vs yesterday (positive = up).
    public var revenueDeltaCents: Int {
        revenueTodayCents - revenueYesterdayCents
    }

    /// Human-readable formatted revenue (e.g. "$1,234.56").
    public func formattedRevenue(cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
    }
}
