import Foundation

// MARK: - Estimate convert-to-ticket

/// `POST /api/v1/estimates/:id/convert-to-ticket`
/// Returns `{ ticketId: Int64 }`.
public struct ConvertEstimateResponse: Decodable, Sendable {
    public let ticketId: Int64

    public init(ticketId: Int64) {
        self.ticketId = ticketId
    }

    enum CodingKeys: String, CodingKey {
        case ticketId = "ticketId"
    }
}

private struct _EstimateConvertEmptyBody: Encodable, Sendable {}

public extension APIClient {
    func convertEstimateToTicket(estimateId: Int64) async throws -> ConvertEstimateResponse {
        return try await post(
            "/api/v1/estimates/\(estimateId)/convert-to-ticket",
            body: _EstimateConvertEmptyBody(),
            as: ConvertEstimateResponse.self
        )
    }
}
