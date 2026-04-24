import Foundation

// MARK: - Clock-entries list model
//
// Server route: GET /api/v1/timesheet/clock-entries
// Query: user_id?, from_date?, to_date?
// Returns: { success, data: [ClockEntry] }
// Auth: non-manager callers see only their own entries; manager sees all.
//
// Server route: PATCH /api/v1/timesheet/clock-entries/:id
// Body: { clock_in?, clock_out?, reason (required), notes? }
// Returns: { success, data: ClockEntry }
// Auth: manager/admin only. `reason` is mandatory (audit log).

/// Request body for PATCH /api/v1/timesheet/clock-entries/:id
/// `reason` is mandatory per server audit policy.
public struct ClockEntryEditRequest: Encodable, Sendable {
    public let clockIn: String?
    public let clockOut: String?
    public let notes: String?
    /// Mandatory for every manager edit. Server returns 400 if blank.
    public let reason: String

    public init(
        clockIn: String? = nil,
        clockOut: String? = nil,
        notes: String? = nil,
        reason: String
    ) {
        self.clockIn  = clockIn
        self.clockOut = clockOut
        self.notes    = notes
        self.reason   = reason
    }

    enum CodingKeys: String, CodingKey {
        case reason, notes
        case clockIn  = "clock_in"
        case clockOut = "clock_out"
    }
}

// MARK: - APIClient extensions

public extension APIClient {

    // MARK: - Timesheet clock-entries list

    /// GET /api/v1/timesheet/clock-entries
    ///
    /// Non-managers always see only their own entries (server enforces).
    /// Managers may pass `userId` to filter by employee; omit for all employees.
    /// `fromDate` / `toDate` are ISO-8601 date strings ("yyyy-MM-dd").
    func listClockEntries(
        userId: Int64? = nil,
        fromDate: String? = nil,
        toDate: String? = nil
    ) async throws -> [ClockEntry] {
        var query: [URLQueryItem] = []
        if let u    = userId   { query.append(URLQueryItem(name: "user_id",   value: "\(u)")) }
        if let from = fromDate { query.append(URLQueryItem(name: "from_date", value: from)) }
        if let to   = toDate   { query.append(URLQueryItem(name: "to_date",   value: to)) }
        return try await get(
            "/api/v1/timesheet/clock-entries",
            query: query.isEmpty ? nil : query,
            as: [ClockEntry].self
        )
    }

    // MARK: - Timesheet clock-entry edit (manager)

    /// PATCH /api/v1/timesheet/clock-entries/:id
    ///
    /// Manager/admin only. `reason` is mandatory and written to the audit table.
    func editClockEntry(entryId: Int64, edit: ClockEntryEditRequest) async throws -> ClockEntry {
        try await patch(
            "/api/v1/timesheet/clock-entries/\(entryId)",
            body: edit,
            as: ClockEntry.self
        )
    }
}
