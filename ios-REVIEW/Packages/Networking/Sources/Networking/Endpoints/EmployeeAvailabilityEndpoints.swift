import Foundation

// MARK: - Employee availability slots

public struct AvailabilitySlot: Decodable, Sendable, Identifiable, Hashable {
    public let start: String    // ISO-8601
    public let end: String      // ISO-8601

    public var id: String { start }

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }
}

public struct EmployeeAvailabilityResponse: Decodable, Sendable {
    public let slots: [AvailabilitySlot]

    public init(slots: [AvailabilitySlot]) {
        self.slots = slots
    }
}

public extension APIClient {
    func fetchEmployeeAvailability(employeeId: Int64, date: String) async throws -> [AvailabilitySlot] {
        let items = [URLQueryItem(name: "date", value: date)]
        return try await get(
            "/api/v1/employees/\(employeeId)/availability",
            query: items,
            as: EmployeeAvailabilityResponse.self
        ).slots
    }
}
