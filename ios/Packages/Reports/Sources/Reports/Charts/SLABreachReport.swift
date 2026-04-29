import Foundation

// §91.3 — SLA breach report model. Stub until server endpoint lands.

public struct SLABreachReport: Codable, Sendable {
    public let breachCount: Int
    public let breachTypes: [SLABreachType]

    public init(breachCount: Int, breachTypes: [SLABreachType]) {
        self.breachCount = breachCount
        self.breachTypes = breachTypes
    }

    public var hasBreaches: Bool { breachCount > 0 }
}

public struct SLABreachType: Codable, Sendable, Identifiable {
    public let id: String
    public let type: String
    public let count: Int

    public init(id: String, type: String, count: Int) {
        self.id = id
        self.type = type
        self.count = count
    }
}

public struct TicketsByTechPoint: Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let ticketsClosed: Int
    public let ticketsAssigned: Int

    public init(id: Int64, name: String, ticketsClosed: Int, ticketsAssigned: Int = 0) {
        self.id = id
        self.name = name
        self.ticketsClosed = ticketsClosed
        self.ticketsAssigned = ticketsAssigned
    }

    public init(from perf: EmployeePerf) {
        self.id = perf.id
        self.name = perf.employeeName
        self.ticketsClosed = perf.ticketsClosed
        self.ticketsAssigned = perf.ticketsAssigned
    }
}
