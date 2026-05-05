import Foundation
import Networking

// MARK: - TimesheetResponse

public struct TimesheetResponse: Decodable, Sendable {
    public let shifts: [Shift]
    public let breaks: [BreakEntry]

    public init(shifts: [Shift], breaks: [BreakEntry]) {
        self.shifts = shifts
        self.breaks = breaks
    }
}

// MARK: - TimesheetEditRequest

public struct TimesheetEditRequest: Encodable, Sendable {
    public let clockIn: String?
    public let clockOut: String?
    public let reason: String

    public init(clockIn: String? = nil, clockOut: String? = nil, reason: String) {
        self.clockIn = clockIn
        self.clockOut = clockOut
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case clockIn  = "clock_in"
        case clockOut = "clock_out"
        case reason
    }
}

// MARK: - APIClient extensions

public extension APIClient {
    /// GET `/api/v1/timeclock/timesheet/:employeeId`
    func getTimesheet(employeeId: Int64, period: PayPeriod) async throws -> TimesheetResponse {
        let iso = ISO8601DateFormatter()
        let query: [URLQueryItem] = [
            URLQueryItem(name: "start", value: iso.string(from: period.start)),
            URLQueryItem(name: "end",   value: iso.string(from: period.end))
        ]
        return try await get(
            "/api/v1/timeclock/timesheet/\(employeeId)",
            query: query,
            as: TimesheetResponse.self
        )
    }

    /// GET `/api/v1/timeclock/timesheets` — manager sees all employees
    func getTeamTimesheets(period: PayPeriod, employeeId: Int64? = nil) async throws -> [TimesheetResponse] {
        let iso = ISO8601DateFormatter()
        var query: [URLQueryItem] = [
            URLQueryItem(name: "start", value: iso.string(from: period.start)),
            URLQueryItem(name: "end",   value: iso.string(from: period.end))
        ]
        if let eid = employeeId {
            query.append(URLQueryItem(name: "employee_id", value: "\(eid)"))
        }
        return try await get(
            "/api/v1/timeclock/timesheets",
            query: query,
            as: [TimesheetResponse].self
        )
    }

    /// PATCH `/api/v1/timeclock/shifts/:shiftId` — manager correction, audit logged
    func editShift(shiftId: Int64, edit: TimesheetEditRequest) async throws -> Shift {
        try await patch(
            "/api/v1/timeclock/shifts/\(shiftId)",
            body: edit,
            as: Shift.self
        )
    }
}
