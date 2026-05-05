import AppIntents
import Foundation
#if os(iOS)

/// AppEntity wrapping the `Ticket` model, exposed to Shortcuts + Siri.
/// Uses `String` id because `AppEntity.ID` must conform to `EntityIdentifierConvertible`,
/// and the primitive conformances available are `String` and `Int`.
@available(iOS 16, *)
public struct TicketEntity: AppEntity, Sendable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ticket")
    public static let defaultQuery = TicketEntityQuery()

    public let id: String
    /// Numeric database id, preserved separately for API calls.
    public let numericId: Int64
    public let displayId: String
    public let customerName: String
    public let status: String
    public let deviceSummary: String?

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayId) — \(customerName)",
            subtitle: "\(status)\(deviceSummary.map { " · \($0)" } ?? "")"
        )
    }

    public init(from ticket: Ticket) {
        self.id = String(ticket.id)
        self.numericId = ticket.id
        self.displayId = ticket.displayId
        self.customerName = ticket.customerName
        self.status = ticket.status.displayName
        self.deviceSummary = ticket.deviceSummary
    }

    /// Memberwise init for query / test construction.
    public init(
        id: Int64,
        displayId: String,
        customerName: String,
        status: String,
        deviceSummary: String? = nil
    ) {
        self.id = String(id)
        self.numericId = id
        self.displayId = displayId
        self.customerName = customerName
        self.status = status
        self.deviceSummary = deviceSummary
    }
}
#endif // os(iOS)
