import Foundation

/// A service-job (repair) ticket in the BizarreCRM system.
///
/// Tickets are the central entity in the repair workflow.  They track a device
/// from customer drop-off through diagnosis, repair, and pick-up.  The full
/// state machine is described in **§88.1** of the iOS Action Plan:
///
/// ```
/// Intake → Diagnosing → Awaiting Parts → In Progress → Ready → Completed → Archived
/// ```
///
/// ## Monetary values
/// ``totalCents`` is stored in **integer US cents**.  Format for display with
/// ``Currency/formatCents(_:code:)``.
///
/// ## Identifiers
/// - ``id``: internal database primary key; used in API paths (`/tickets/:id`).
/// - ``displayId``: human-readable ticket number shown to staff and customers
///   (e.g. `"T-4821"`).  Never use `id` directly in UI.
///
/// ## Codable
/// Decoded from the `GET /tickets` and `GET /tickets/:id` server responses.
/// Dates are ISO 8601 strings decoded with `.iso8601` strategy.
///
/// ## See Also
/// - ``TicketStatus`` for all valid status values and their display names.
/// - `TicketRepository` (Tickets package) for CRUD operations.
public struct Ticket: Identifiable, Hashable, Codable, Sendable {
    /// Internal database primary key.  Used in API paths; do not surface in UI.
    public let id: Int64
    /// Human-readable ticket identifier shown to staff and customers (e.g. `"T-4821"`).
    public let displayId: String
    /// Foreign key to the associated ``Customer``.
    public let customerId: Int64
    /// Denormalized customer full name for fast list rendering without a join.
    public let customerName: String
    /// Current stage in the repair workflow.  See ``TicketStatus``.
    public let status: TicketStatus
    /// Short summary of the device(s) on the ticket (e.g. `"iPhone 15 Pro"`).
    /// `nil` when no device has been added yet.
    public let deviceSummary: String?
    /// Tech's diagnostic notes.  `nil` until diagnosis has been entered.
    public let diagnosis: String?
    /// Ticket total in US cents, including parts, labor, and tax.
    /// Format with ``Currency/formatCents(_:code:)`` before display.
    public let totalCents: Int
    /// When the ticket was first created on the server (UTC).
    public let createdAt: Date
    /// When any field was last modified on the server (UTC).
    public let updatedAt: Date

    public init(
        id: Int64,
        displayId: String,
        customerId: Int64,
        customerName: String,
        status: TicketStatus,
        deviceSummary: String? = nil,
        diagnosis: String? = nil,
        totalCents: Int = 0,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.displayId = displayId
        self.customerId = customerId
        self.customerName = customerName
        self.status = status
        self.deviceSummary = deviceSummary
        self.diagnosis = diagnosis
        self.totalCents = totalCents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// All valid states in the ticket lifecycle (§88.1).
///
/// Raw values match the strings returned by the server's `status` field and
/// used in `PATCH /tickets/:id/status` requests.  Do not change raw values
/// without coordinating a server migration.
///
/// Allowed transitions are enforced server-side; the client renders forward
/// actions based on the current status (see `TicketRowSwipeActions` and the
/// "Mark Ready" / status-change sheet in TicketDetailView).
public enum TicketStatus: String, Codable, CaseIterable, Hashable, Sendable {
    /// Device has just been received from the customer; intake form incomplete.
    case intake
    /// Tech is actively diagnosing the device.
    case diagnosing
    /// Diagnosis complete; waiting for ordered parts to arrive.
    case awaitingParts = "awaiting_parts"
    /// Parts in hand; repair is underway.
    case inProgress = "in_progress"
    /// Repair complete; customer has been notified for pick-up.
    case ready
    /// Customer collected the device; ticket closed.
    case completed
    /// Ticket archived (soft-deleted from active views).
    case archived

    /// Localized label suitable for status chips, filter pills, and detail headers.
    public var displayName: String {
        switch self {
        case .intake:         return "Intake"
        case .diagnosing:     return "Diagnosing"
        case .awaitingParts:  return "Awaiting Parts"
        case .inProgress:     return "In Progress"
        case .ready:          return "Ready"
        case .completed:      return "Completed"
        case .archived:       return "Archived"
        }
    }
}
