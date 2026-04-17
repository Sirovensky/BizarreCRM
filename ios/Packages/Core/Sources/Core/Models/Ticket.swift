import Foundation

public struct Ticket: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let displayId: String
    public let customerId: Int64
    public let customerName: String
    public let status: TicketStatus
    public let deviceSummary: String?
    public let diagnosis: String?
    public let totalCents: Int
    public let createdAt: Date
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

public enum TicketStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case intake
    case diagnosing
    case awaitingParts = "awaiting_parts"
    case inProgress = "in_progress"
    case ready
    case completed
    case archived

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
