import Foundation

/// §3.11 — Timeclock DTOs + APIClient wrappers.
///
/// Server routes in `packages/server/src/routes/employees.routes.ts`:
///   • `POST /api/v1/employees/:id/clock-in`  – body `{ pin }` → creates
///     `clock_entries` row; returns `{ success, data: ClockEntry }`.
///   • `POST /api/v1/employees/:id/clock-out` – body `{ pin }` → closes
///     open entry; returns `{ success, data: ClockEntry }`.
///   • There is no dedicated `/clock-status` endpoint — status is embedded
///     in `GET /api/v1/employees/:id` under `is_clocked_in` +
///     `current_clock_entry`. `getClockStatus` calls that endpoint and
///     projects the relevant fields; returns `nil` on 404.
///
/// TODO(auth/me): `userId` is currently hard-coded to `0` at the call site
/// because the `/auth/me` endpoint is not yet plumbed in iOS (pending §2.x).
/// Replace the placeholder once that route lands.

// MARK: - DTOs

/// A single clock-entries row returned by the server.
public struct ClockEntry: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int64
    public let userId: Int64
    /// ISO-8601 string; server stores as TEXT in UTC.
    public let clockIn: String
    public let clockOut: String?
    /// Hours from clock-in to now — only present while clocked in (some
    /// server builds omit it on the active row; `ClockInOutViewModel` derives
    /// elapsed locally instead).
    public let runningHours: Double?
    /// Final hours written on clock-out (after lunch deduction, if any).
    public let totalHours: Double?

    public init(
        id: Int64,
        userId: Int64,
        clockIn: String,
        clockOut: String? = nil,
        runningHours: Double? = nil,
        totalHours: Double? = nil
    ) {
        self.id = id
        self.userId = userId
        self.clockIn = clockIn
        self.clockOut = clockOut
        self.runningHours = runningHours
        self.totalHours = totalHours
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId       = "user_id"
        case clockIn      = "clock_in"
        case clockOut     = "clock_out"
        case runningHours = "running_hours"
        case totalHours   = "total_hours"
    }
}

/// Projection of the employee endpoint relevant to clock status.
public struct ClockStatus: Decodable, Sendable {
    public let isClockedIn: Bool
    public let entry: ClockEntry?

    public init(isClockedIn: Bool, entry: ClockEntry? = nil) {
        self.isClockedIn = isClockedIn
        self.entry = entry
    }

    enum CodingKeys: String, CodingKey {
        case isClockedIn        = "is_clocked_in"
        case entry              = "current_clock_entry"
    }
}

// MARK: - Request bodies

private struct ClockActionRequest: Encodable, Sendable {
    let pin: String

    enum CodingKeys: String, CodingKey {
        case pin
    }
}

// MARK: - APIClient wrappers

public extension APIClient {
    /// POST `/api/v1/employees/:id/clock-in`.
    /// Verifies PIN server-side; creates a `clock_entries` row.
    func clockIn(userId: Int64, pin: String) async throws -> ClockEntry {
        try await post(
            "/api/v1/employees/\(userId)/clock-in",
            body: ClockActionRequest(pin: pin),
            as: ClockEntry.self
        )
    }

    /// POST `/api/v1/employees/:id/clock-out`.
    /// Closes the open clock-entries row and returns the completed entry.
    func clockOut(userId: Int64, pin: String) async throws -> ClockEntry {
        try await post(
            "/api/v1/employees/\(userId)/clock-out",
            body: ClockActionRequest(pin: pin),
            as: ClockEntry.self
        )
    }

    /// Derives clock status from `GET /api/v1/employees/:id`.
    /// Returns `nil` when the endpoint responds 404 (employee not found or
    /// endpoint not yet deployed). Callers treat `nil` as "status unknown".
    func getClockStatus(userId: Int64) async throws -> ClockStatus? {
        do {
            return try await get(
                "/api/v1/employees/\(userId)",
                as: ClockStatus.self
            )
        } catch let APITransportError.httpStatus(code, _) where code == 404 {
            return nil
        }
    }
}
