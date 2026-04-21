import Foundation
import Networking

// MARK: - Request / response DTOs

/// §16.15 — Request body for `POST /shifts/:id/close`.
public struct CloseShiftRequest: Encodable, Sendable {
    public let closingCashCents: Int
    public let notes:            String?

    public init(closingCashCents: Int, notes: String? = nil) {
        self.closingCashCents = closingCashCents
        self.notes            = notes
    }
}

/// §16.15 — Server response for shift close (canonical summary).
public struct CloseShiftResponse: Decodable, Sendable {
    public let shiftId:             String
    public let startedAt:           Date
    public let endedAt:             Date
    public let cashierId:           Int64
    public let openingCashCents:    Int
    public let closingCashCents:    Int
    public let calculatedCashCents: Int
    public let driftCents:          Int
    public let saleCount:           Int
    public let totalRevenueCents:   Int
    public let tendersBreakdown:    [String: Int]
    public let refundsCents:        Int
    public let voidsCents:          Int
    public let averageTicketCents:  Int
}

// MARK: - APIClient extension

public extension APIClient {
    /// `POST /shifts/:id/close` — close a shift and receive the canonical summary.
    func closeShift(id: String, request: CloseShiftRequest) async throws -> ShiftSummary {
        let dto = try await post("/shifts/\(id)/close", body: request, as: CloseShiftResponse.self)
        return ShiftSummary(
            shiftId:             dto.shiftId,
            startedAt:           dto.startedAt,
            endedAt:             dto.endedAt,
            cashierId:           dto.cashierId,
            openingCashCents:    dto.openingCashCents,
            closingCashCents:    dto.closingCashCents,
            calculatedCashCents: dto.calculatedCashCents,
            driftCents:          dto.driftCents,
            saleCount:           dto.saleCount,
            totalRevenueCents:   dto.totalRevenueCents,
            tendersBreakdown:    dto.tendersBreakdown,
            refundsCents:        dto.refundsCents,
            voidsCents:          dto.voidsCents,
            averageTicketCents:  dto.averageTicketCents
        )
    }
}
