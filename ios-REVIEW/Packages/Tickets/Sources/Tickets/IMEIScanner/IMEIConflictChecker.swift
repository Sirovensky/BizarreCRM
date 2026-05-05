import Foundation
import Networking

/// Checks the server for existing open tickets that have the same IMEI.
/// Performs `GET /api/v1/tickets/by-imei/:imei`.
public actor IMEIConflictChecker {

    public struct ConflictResult: Sendable {
        public let ticketId: Int64
        public let orderId: String
        public let statusName: String?
    }

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// Returns a conflict result if an open ticket already tracks this IMEI,
    /// or `nil` if the IMEI is clear.
    public func check(imei: String) async throws -> ConflictResult? {
        guard IMEIValidator.isValid(imei) else { return nil }
        let resp = try await api.getEnvelope(
            "/api/v1/tickets/by-imei/\(imei)",
            query: nil,
            as: IMEIConflictPayload.self
        )
        guard resp.success, let payload = resp.data, let ticket = payload.ticket else {
            return nil
        }
        return ConflictResult(
            ticketId: ticket.id,
            orderId: ticket.orderId,
            statusName: ticket.statusName
        )
    }
}

// MARK: - Response types

private struct IMEIConflictPayload: Decodable, Sendable {
    let ticket: TicketRef?

    struct TicketRef: Decodable, Sendable {
        let id: Int64
        let orderId: String
        let statusName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case orderId = "order_id"
            case statusName = "status_name"
        }
    }
}
