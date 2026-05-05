import Foundation

/// §16.15 — Pure, testable shift-summary aggregator. No UIKit, no
/// side-effects. All money in cents. Tests ≥ 80% required.
public enum ShiftSummaryCalculator {

    // MARK: - Input types

    /// Minimal projection of a completed sale for aggregation.
    public struct SaleRecord: Sendable {
        public let revenueCents:     Int
        public let refundCents:      Int     // positive value = money back to customer
        public let voidCents:        Int     // positive value = voided amount
        public let tenders:          [String: Int]  // label → cents
        public let isCashSale:       Bool

        public init(
            revenueCents:  Int,
            refundCents:   Int        = 0,
            voidCents:     Int        = 0,
            tenders:       [String: Int] = [:],
            isCashSale:    Bool       = false
        ) {
            self.revenueCents  = revenueCents
            self.refundCents   = refundCents
            self.voidCents     = voidCents
            self.tenders       = tenders
            self.isCashSale    = isCashSale
        }
    }

    // MARK: - Aggregation

    /// Build a `ShiftSummary` from a slice of sale records + shift metadata.
    ///
    /// - Parameters:
    ///   - records:           All sales (including refunds/voids) during the shift.
    ///   - shiftId:           Server-assigned shift identifier.
    ///   - startedAt:         Shift open time.
    ///   - endedAt:           Shift close time (nil if still open).
    ///   - cashierId:         Employee id of the cashier.
    ///   - openingCashCents:  Float at shift open.
    ///   - closingCashCents:  Cash counted at close.
    public static func aggregate(
        records:           [SaleRecord],
        shiftId:           String,
        startedAt:         Date,
        endedAt:           Date?  = nil,
        cashierId:         Int64,
        openingCashCents:  Int,
        closingCashCents:  Int
    ) -> ShiftSummary {
        let saleCount       = records.count
        let totalRevenue    = records.reduce(0) { $0 + $1.revenueCents }
        let totalRefunds    = records.reduce(0) { $0 + $1.refundCents }
        let totalVoids      = records.reduce(0) { $0 + $1.voidCents }

        // Tender breakdown: merge all sale tender maps.
        var breakdown: [String: Int] = [:]
        for record in records {
            for (key, cents) in record.tenders {
                breakdown[key, default: 0] += cents
            }
        }

        // Expected cash = opening float + total cash collected − cash refunds.
        let cashCollected   = records
            .filter { $0.isCashSale }
            .reduce(0) { $0 + $1.revenueCents - $1.refundCents }
        let calculatedCash  = openingCashCents + cashCollected
        let drift           = closingCashCents - calculatedCash

        let average         = saleCount > 0 ? totalRevenue / saleCount : 0

        return ShiftSummary(
            shiftId:             shiftId,
            startedAt:           startedAt,
            endedAt:             endedAt,
            cashierId:           cashierId,
            openingCashCents:    openingCashCents,
            closingCashCents:    closingCashCents,
            calculatedCashCents: calculatedCash,
            driftCents:          drift,
            saleCount:           saleCount,
            totalRevenueCents:   totalRevenue,
            tendersBreakdown:    breakdown,
            refundsCents:        totalRefunds,
            voidsCents:          totalVoids,
            averageTicketCents:  average
        )
    }
}
