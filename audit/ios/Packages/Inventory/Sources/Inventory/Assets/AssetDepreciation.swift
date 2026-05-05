import Foundation
import Networking

// MARK: - §6.8 Asset Depreciation
//
// Pure helpers + dashboard-tile data model for loaner/asset book-value reporting.
//
// The Dashboard (Agent 9) renders the tile; this file owns the data contract +
// arithmetic so that calculations stay in the domain package and remain testable
// without UIKit. The dashboard tile only consumes `AssetBookValueDashboardData`.
//
// Server endpoint:
//   GET /api/v1/loaners/book-value-summary
//   →  AssetBookValueSummary  (dashboard tile feed)

// MARK: - Methods

/// Two depreciation schedules supported by the iOS surface. Server can extend
/// this list, but iOS only renders a number; the picker for the schedule lives
/// in Settings (admin-only).
public enum DepreciationMethod: String, Codable, Sendable, CaseIterable {
    /// Linear / straight-line: cost spread evenly across `usefulLifeMonths`.
    case linear              = "linear"
    /// Double-declining balance: each period depreciates `2 / usefulLifeMonths`
    /// of the *current* book value (never below salvage value).
    case decliningBalance    = "declining_balance"

    public var displayName: String {
        switch self {
        case .linear:           return "Linear"
        case .decliningBalance: return "Declining balance"
        }
    }
}

// MARK: - Input

/// Per-asset depreciation inputs. Cents to keep arithmetic exact.
public struct AssetDepreciationInput: Sendable, Hashable {
    public let costCents: Int
    public let salvageValueCents: Int
    public let usefulLifeMonths: Int
    public let monthsInService: Int
    public let method: DepreciationMethod

    public init(
        costCents: Int,
        salvageValueCents: Int,
        usefulLifeMonths: Int,
        monthsInService: Int,
        method: DepreciationMethod
    ) {
        self.costCents = costCents
        self.salvageValueCents = salvageValueCents
        self.usefulLifeMonths = usefulLifeMonths
        self.monthsInService = monthsInService
        self.method = method
    }
}

// MARK: - Pure calculator

public enum AssetDepreciationCalculator {

    /// Current book value in cents — clamped to `[salvageValue, cost]` and never
    /// negative. Returns `cost` when `usefulLifeMonths <= 0` (defensive).
    public static func bookValueCents(_ input: AssetDepreciationInput) -> Int {
        guard input.usefulLifeMonths > 0 else { return input.costCents }
        let months = max(0, input.monthsInService)

        switch input.method {
        case .linear:
            // depreciable base = cost - salvage
            let depreciableBase = max(0, input.costCents - input.salvageValueCents)
            let life = Double(input.usefulLifeMonths)
            let elapsed = min(Double(months), life)
            let depreciation = Double(depreciableBase) * (elapsed / life)
            let book = Double(input.costCents) - depreciation
            return clampToBounds(Int(book.rounded()), input: input)

        case .decliningBalance:
            // Double-declining: rate = 2 / life applied each month to running book
            let rate = 2.0 / Double(input.usefulLifeMonths)
            var book = Double(input.costCents)
            let salvage = Double(input.salvageValueCents)
            for _ in 0 ..< months {
                let next = book * (1.0 - rate)
                if next <= salvage { book = salvage; break }
                book = next
            }
            return clampToBounds(Int(book.rounded()), input: input)
        }
    }

    /// Total depreciation taken to date, in cents. Always ≥ 0.
    public static func accumulatedDepreciationCents(_ input: AssetDepreciationInput) -> Int {
        max(0, input.costCents - bookValueCents(input))
    }

    /// Average monthly depreciation rate over the elapsed period (cents/month).
    /// Returns 0 if `monthsInService == 0`.
    public static func monthlyDepreciationCents(_ input: AssetDepreciationInput) -> Int {
        let months = max(0, input.monthsInService)
        guard months > 0 else { return 0 }
        return accumulatedDepreciationCents(input) / months
    }

    private static func clampToBounds(_ value: Int, input: AssetDepreciationInput) -> Int {
        min(max(value, input.salvageValueCents), input.costCents)
    }
}

// MARK: - Dashboard data (tile feed)

/// Aggregated asset book-value summary returned by the server, ready for the
/// dashboard tile (Agent 9).
public struct AssetBookValueSummary: Codable, Sendable, Equatable {
    /// Total cost basis across the active fleet.
    public let totalCostCents: Int
    /// Sum of current book value across the active fleet.
    public let totalBookValueCents: Int
    /// Number of active (non-retired) assets.
    public let activeAssetCount: Int
    /// Number of fully depreciated assets (book value == salvage).
    public let fullyDepreciatedCount: Int
    /// ISO 8601 timestamp of the snapshot.
    public let snapshotAt: Date

    public init(
        totalCostCents: Int,
        totalBookValueCents: Int,
        activeAssetCount: Int,
        fullyDepreciatedCount: Int,
        snapshotAt: Date
    ) {
        self.totalCostCents = totalCostCents
        self.totalBookValueCents = totalBookValueCents
        self.activeAssetCount = activeAssetCount
        self.fullyDepreciatedCount = fullyDepreciatedCount
        self.snapshotAt = snapshotAt
    }

    enum CodingKeys: String, CodingKey {
        case totalCostCents         = "total_cost_cents"
        case totalBookValueCents    = "total_book_value_cents"
        case activeAssetCount       = "active_asset_count"
        case fullyDepreciatedCount  = "fully_depreciated_count"
        case snapshotAt             = "snapshot_at"
    }

    /// Aggregate accumulated depreciation across the fleet.
    public var accumulatedDepreciationCents: Int {
        max(0, totalCostCents - totalBookValueCents)
    }

    /// Fraction depreciated (0…1). Returns 0 if cost is zero.
    public var depreciationFraction: Double {
        guard totalCostCents > 0 else { return 0 }
        return min(1.0, Double(accumulatedDepreciationCents) / Double(totalCostCents))
    }
}

// MARK: - Endpoints

public extension APIClient {

    /// GET /api/v1/loaners/book-value-summary — dashboard tile feed (§6.8).
    func assetBookValueSummary() async throws -> AssetBookValueSummary {
        try await get("/api/v1/loaners/book-value-summary", as: AssetBookValueSummary.self)
    }
}
