import Foundation
import Networking

// MARK: - BreakActionRequest

private struct BreakStartRequest: Encodable, Sendable {
    let shiftId: Int64
    let kind: String

    enum CodingKeys: String, CodingKey {
        case shiftId = "shift_id"
        case kind
    }
}

private struct BreakEndRequest: Encodable, Sendable {
    // Body may be empty; server identifies by breakId in path.
}

// MARK: - APIClient extensions

public extension APIClient {
    /// POST `/api/v1/timeclock/breaks/start`
    func startBreak(employeeId: Int64, shiftId: Int64, kind: BreakKind) async throws -> BreakEntry {
        let body = BreakStartRequest(shiftId: shiftId, kind: kind.rawValue)
        return try await post(
            "/api/v1/timeclock/breaks/start",
            body: body,
            as: BreakEntry.self
        )
    }

    /// POST `/api/v1/timeclock/breaks/end`
    func endBreak(breakId: Int64) async throws -> BreakEntry {
        return try await post(
            "/api/v1/timeclock/breaks/\(breakId)/end",
            body: BreakEndRequest(),
            as: BreakEntry.self
        )
    }
}
