import Foundation
import Networking

// MARK: - PublishWeekBody

private struct PublishWeekBody: Encodable, Sendable {
    let weekStart: String
    enum CodingKeys: String, CodingKey { case weekStart = "week_start" }
}

// MARK: - APIClient extensions

public extension APIClient {
    /// GET `/api/v1/team/shifts` — weekly schedule
    func getSchedule(weekStart: String) async throws -> [ScheduledShift] {
        try await get(
            "/api/v1/team/shifts",
            query: [URLQueryItem(name: "week_start", value: weekStart)],
            as: [ScheduledShift].self
        )
    }

    /// POST `/api/v1/team/shifts`
    func createScheduledShift(body: CreateScheduledShiftBody) async throws -> ScheduledShift {
        try await post("/api/v1/team/shifts", body: body, as: ScheduledShift.self)
    }

    /// POST `/api/v1/team/shifts/publish`
    func publishSchedule(weekStart: String) async throws {
        try await delete("/api/v1/team/shifts/publish?week_start=\(weekStart)")
    }
}
