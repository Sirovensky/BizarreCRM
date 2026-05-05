import Foundation
import Networking

// MARK: - Response containers

public struct ScorecardResponse: Decodable, Sendable {
    public let scorecard: EmployeeScorecard
}

// MARK: - APIClient extensions

public extension APIClient {
    func fetchScorecard(employeeId: String, windowDays: Int = 30) async throws -> EmployeeScorecard {
        let query = [URLQueryItem(name: "window_days", value: "\(windowDays)")]
        return try await get("/employees/\(employeeId)/scorecard",
                             query: query,
                             as: ScorecardResponse.self).scorecard
    }
}
