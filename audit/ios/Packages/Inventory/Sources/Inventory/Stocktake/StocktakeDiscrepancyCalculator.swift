import Foundation
import Networking

// MARK: - Discrepancy model

/// One discrepancy entry: a scanned row where actual ≠ expected.
public struct StocktakeDiscrepancy: Sendable, Identifiable, Equatable {
    public let id: UUID = UUID()
    public let sku: String
    public let name: String
    public let expectedQty: Int
    public let actualQty: Int
    /// Write-off reason entered by the operator (required for shortage lines).
    public var writeOffReason: String?

    public var delta: Int { actualQty - expectedQty }
    public var isSurplus: Bool { delta > 0 }
    public var isShortage: Bool { delta < 0 }

    public init(sku: String, name: String, expectedQty: Int,
                actualQty: Int, writeOffReason: String? = nil) {
        self.sku = sku
        self.name = name
        self.expectedQty = expectedQty
        self.actualQty = actualQty
        self.writeOffReason = writeOffReason
    }

    public static func == (lhs: StocktakeDiscrepancy, rhs: StocktakeDiscrepancy) -> Bool {
        lhs.sku == rhs.sku
            && lhs.expectedQty == rhs.expectedQty
            && lhs.actualQty == rhs.actualQty
    }
}

// MARK: - Summary

/// Aggregated totals for a stocktake session.
public struct StocktakeSummary: Sendable, Equatable {
    public let totalRows: Int
    public let countedRows: Int
    public let discrepancyCount: Int
    public let totalSurplus: Int
    public let totalShortage: Int

    public var netVariance: Int { totalSurplus - totalShortage }

    public init(totalRows: Int, countedRows: Int, discrepancyCount: Int,
                totalSurplus: Int, totalShortage: Int) {
        self.totalRows = totalRows
        self.countedRows = countedRows
        self.discrepancyCount = discrepancyCount
        self.totalSurplus = totalSurplus
        self.totalShortage = totalShortage
    }
}

// MARK: - Calculator (pure, no UIKit, fully testable)

/// Pure arithmetic helper for stocktake discrepancy calculation.
/// No UIKit or network dependencies — inject rows, get discrepancies back.
public enum StocktakeDiscrepancyCalculator {

    /// Build the list of discrepant rows from the full set of stocktake rows.
    /// - Parameters:
    ///   - rows: All `StocktakeRow` objects in the session.
    ///   - onlyCountedRows: When `true`, uncounted rows (nil actualQty) are excluded from
    ///     the discrepancy list. When `false`, uncounted rows are treated as 0.
    public static func discrepancies(
        from rows: [StocktakeRow],
        onlyCountedRows: Bool = true
    ) -> [StocktakeDiscrepancy] {
        rows.compactMap { row -> StocktakeDiscrepancy? in
            let actual: Int
            if let a = row.actualQty {
                actual = a
            } else if onlyCountedRows {
                return nil
            } else {
                actual = 0
            }
            guard actual != row.expectedQty else { return nil }
            return StocktakeDiscrepancy(
                sku: row.sku,
                name: row.productName ?? row.sku,
                expectedQty: row.expectedQty,
                actualQty: actual
            )
        }
    }

    /// Compute aggregate summary for a session.
    public static func summary(from rows: [StocktakeRow]) -> StocktakeSummary {
        let counted = rows.filter { $0.actualQty != nil }
        var surplus = 0
        var shortage = 0
        var discrepancies = 0
        for row in counted {
            guard let actual = row.actualQty else { continue }
            let delta = actual - row.expectedQty
            if delta > 0 {
                surplus += delta
                discrepancies += 1
            } else if delta < 0 {
                shortage += (-delta)
                discrepancies += 1
            }
        }
        return StocktakeSummary(
            totalRows: rows.count,
            countedRows: counted.count,
            discrepancyCount: discrepancies,
            totalSurplus: surplus,
            totalShortage: shortage
        )
    }
}
