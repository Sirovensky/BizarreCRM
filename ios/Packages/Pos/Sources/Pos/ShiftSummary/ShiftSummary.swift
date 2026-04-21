import Foundation

/// §16.15 — Canonical end-of-shift record. All money in cents.
public struct ShiftSummary: Equatable, Sendable, Codable {
    public let shiftId:             String
    public let startedAt:           Date
    public let endedAt:             Date?
    public let cashierId:           Int64
    public let openingCashCents:    Int
    public let closingCashCents:    Int
    /// Expected cash = opening float + cash sales − cash refunds.
    public let calculatedCashCents: Int
    /// Drift = closingCash − calculatedCash. Positive = over, negative = short.
    public let driftCents:          Int
    public let saleCount:           Int
    public let totalRevenueCents:   Int
    /// Breakdown of revenue by tender type label. Keyed by tender label string.
    public let tendersBreakdown:    [String: Int]
    public let refundsCents:        Int
    public let voidsCents:          Int
    /// Average ticket in cents. 0 when saleCount == 0.
    public let averageTicketCents:  Int

    public init(
        shiftId:             String,
        startedAt:           Date,
        endedAt:             Date?      = nil,
        cashierId:           Int64,
        openingCashCents:    Int,
        closingCashCents:    Int,
        calculatedCashCents: Int,
        driftCents:          Int,
        saleCount:           Int,
        totalRevenueCents:   Int,
        tendersBreakdown:    [String: Int] = [:],
        refundsCents:        Int,
        voidsCents:          Int,
        averageTicketCents:  Int
    ) {
        self.shiftId             = shiftId
        self.startedAt           = startedAt
        self.endedAt             = endedAt
        self.cashierId           = cashierId
        self.openingCashCents    = openingCashCents
        self.closingCashCents    = closingCashCents
        self.calculatedCashCents = calculatedCashCents
        self.driftCents          = driftCents
        self.saleCount           = saleCount
        self.totalRevenueCents   = totalRevenueCents
        self.tendersBreakdown    = tendersBreakdown
        self.refundsCents        = refundsCents
        self.voidsCents          = voidsCents
        self.averageTicketCents  = averageTicketCents
    }
}
