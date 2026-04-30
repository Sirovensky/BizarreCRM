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

/// §8 — Convert request body that locks the conversion to a specific approved version.
///
/// When the customer approved v2 but the estimate was later edited to v3,
/// we want the ticket to reference the approved version, not the latest draft.
/// Sending `approvedVersionId` tells the server to use that version's line items.
private struct _EstimateConvertWithVersionBody: Encodable, Sendable {
    let approvedVersionId: Int64?

    enum CodingKeys: String, CodingKey {
        case approvedVersionId = "approved_version_id"
    }
}

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

    /// `POST /api/v1/estimates/:id/convert`
    ///
    /// §8 — Convert using a specific approved version number as the reference.
    /// The server pins the line items from `approvedVersionId` to the new ticket
    /// so downstream changes to the estimate don't affect the ticket that was
    /// created from the customer's signed version.
    func convertEstimateToTicketWithVersion(
        estimateId: Int64,
        approvedVersionId: Int64?
    ) async throws -> ConvertEstimateResponse {
        let body = _EstimateConvertWithVersionBody(approvedVersionId: approvedVersionId)
        return try await post(
            "/api/v1/estimates/\(estimateId)/convert",
            body: body,
            as: ConvertEstimateResponse.self
        )
    }
}
