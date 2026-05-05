import Foundation
import Networking

// MARK: - ChurnEndpoints

/// §44.3 — API calls for server-side churn scores.
///
/// GET /customers/:id/churn-score
/// GET /customers/churn-cohort?riskLevel=high
public extension APIClient {

    /// Fetches the server-authoritative churn score for a customer.
    /// Falls back to `ChurnScoreCalculator.compute(input:)` when offline.
    func customerChurnScore(id: Int64) async throws -> ChurnScore {
        let dto = try await get("/api/v1/customers/\(id)/churn-score", as: ChurnScoreDTO.self)
        return dto.toChurnScore()
    }

    /// Fetches the cohort of customers at `riskLevel` or above.
    func churnCohort(riskLevel: ChurnRiskLevel) async throws -> ChurnCohortDTO {
        let query = [URLQueryItem(name: "riskLevel", value: riskLevel.rawValue)]
        return try await get("/api/v1/customers/churn-cohort", query: query, as: ChurnCohortDTO.self)
    }
}
