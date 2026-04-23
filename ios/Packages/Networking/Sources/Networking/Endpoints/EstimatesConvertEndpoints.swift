import Foundation

// MARK: - Estimate convert-to-ticket

/// `POST /api/v1/estimates/:id/convert`
/// Server: packages/server/src/routes/estimates.routes.ts  (router.post '/:id/convert')
/// Returns envelope `{ success, data: { ticket: {...}, message: "..." } }`.
/// We extract only `ticket.id` for navigation.
public struct ConvertEstimateResponse: Decodable, Sendable {
    public let ticketId: Int64

    public init(ticketId: Int64) {
        self.ticketId = ticketId
    }

    // Server returns { ticket: { id: N, ... }, message: "..." }
    // We decode `ticket.id` → ticketId.
    private struct _Ticket: Decodable, Sendable {
        let id: Int64
    }

    private enum CodingKeys: String, CodingKey {
        case ticket
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ticket = try container.decode(_Ticket.self, forKey: .ticket)
        self.ticketId = ticket.id
    }
}

private struct _EstimateConvertEmptyBody: Encodable, Sendable {}

public extension APIClient {
    /// `POST /api/v1/estimates/:id/convert`
    /// Converts an approved (or any non-converted) estimate to a service ticket.
    func convertEstimateToTicket(estimateId: Int64) async throws -> ConvertEstimateResponse {
        return try await post(
            "/api/v1/estimates/\(estimateId)/convert",
            body: _EstimateConvertEmptyBody(),
            as: ConvertEstimateResponse.self
        )
    }
}
