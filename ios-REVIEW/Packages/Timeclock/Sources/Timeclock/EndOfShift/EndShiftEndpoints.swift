import Foundation
import Networking

// MARK: - APIClient + EndOfShift

public extension APIClient {

    /// GET `/api/v1/timeclock/shifts/current-summary` — fetches live shift stats
    /// for the cashier currently clocked in on this register (sales count, gross,
    /// tips, expected cash, items sold, voids).
    ///
    /// Sovereignty: computed on tenant server; no third-party egress.
    func getCurrentShiftSummary(employeeId: Int64) async throws -> EndShiftSummaryDTO {
        try await get(
            "/api/v1/timeclock/shifts/current-summary",
            query: [URLQueryItem(name: "employee_id", value: "\(employeeId)")],
            as: EndShiftSummaryDTO.self
        )
    }

    /// POST `/api/v1/timeclock/shifts/close` — cashier submits end-of-shift data.
    /// Creates an audit entry with cashier_id + manager_id (if sign-off occurred).
    @discardableResult
    func closeShift(employeeId: Int64, body: EndShiftRequest) async throws -> EndShiftResponse {
        try await post(
            "/api/v1/timeclock/shifts/close",
            body: body,
            as: EndShiftResponse.self
        )
    }

    /// POST `/api/v1/timeclock/shifts/handoff` — closing cashier sets opening
    /// cash for the next session; next cashier receives pre-filled count.
    @discardableResult
    func submitShiftHandoff(employeeId: Int64, body: ShiftHandoffRequest) async throws -> EmptySuccess {
        try await post(
            "/api/v1/timeclock/shifts/handoff",
            body: body,
            as: EmptySuccess.self
        )
    }
}

// MARK: - DTO

/// Decodable representation of current-shift stats from the server.
/// Sovereignty: all computation lives on the tenant server.
public struct EndShiftSummaryDTO: Decodable, Sendable {
    public let salesCount: Int
    public let grossCents: Int
    public let tipsCents: Int
    public let cashExpectedCents: Int
    public let itemsSold: Int
    public let voidCount: Int

    enum CodingKeys: String, CodingKey {
        case salesCount        = "sales_count"
        case grossCents        = "gross_cents"
        case tipsCents         = "tips_cents"
        case cashExpectedCents = "cash_expected_cents"
        case itemsSold         = "items_sold"
        case voidCount         = "void_count"
    }
}

// MARK: - Helpers

public struct EmptySuccess: Decodable, Sendable {
    public let success: Bool
}
