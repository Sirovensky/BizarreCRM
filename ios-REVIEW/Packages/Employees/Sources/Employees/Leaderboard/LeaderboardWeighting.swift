import Foundation

// MARK: - LeaderboardWeighting
//
// §46.6 Leaderboard fairness: normalize raw metric values by hours worked so
// part-time employees are not unfairly compared to full-time employees.
// Also excludes single big-ticket outliers (>3× the median) to prevent one
// unusual transaction from skewing the ranking.
//
// Algorithm:
//   1. For each entry compute `weightedValue = rawValue / max(hoursWorked, 1)`.
//   2. Compute median of weightedValues.
//   3. Any entry whose weightedValue > outlierThreshold × median is excluded.
//      Excluded entries appear greyed-out at the bottom of the list (not removed)
//      with an info tooltip explaining the exclusion.
//   4. Sort remaining entries descending by weightedValue.

public struct LeaderboardEntry: Sendable, Identifiable {
    public let id: Int64            // employeeId
    public let displayName: String
    public let rawValue: Double     // tickets closed or revenue $
    public let hoursWorked: Double  // shift hours in the leaderboard period
    public let isOptedOut: Bool     // per §46.6 per-user opt-out

    public var weightedValue: Double {
        rawValue / max(hoursWorked, 1.0)
    }

    public init(
        id: Int64,
        displayName: String,
        rawValue: Double,
        hoursWorked: Double,
        isOptedOut: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.rawValue = rawValue
        self.hoursWorked = hoursWorked
        self.isOptedOut = isOptedOut
    }
}

public struct RankedLeaderboardEntry: Sendable, Identifiable {
    public let id: Int64
    public let entry: LeaderboardEntry
    public let rank: Int?           // nil if excluded as outlier
    public let isOutlier: Bool

    public var isVisible: Bool { !entry.isOptedOut }
}

public struct LeaderboardWeighting: Sendable {

    /// Threshold: an entry is an outlier if its `weightedValue` exceeds
    /// this multiplier times the median. Default 3.0 per spec.
    public var outlierThreshold: Double = 3.0

    public init(outlierThreshold: Double = 3.0) {
        self.outlierThreshold = outlierThreshold
    }

    /// Rank entries with normalization + outlier exclusion.
    ///
    /// - Parameter entries: raw entries (already filtered for current period).
    /// - Returns: sorted entries with ranks assigned; outliers have `rank = nil`.
    public func rank(_ entries: [LeaderboardEntry]) -> [RankedLeaderboardEntry] {
        guard !entries.isEmpty else { return [] }

        let active = entries.filter { !$0.isOptedOut }
        let weighted = active.map { $0.weightedValue }
        let median = Self.median(of: weighted)

        var normalEntries: [LeaderboardEntry] = []
        var outlierEntries: [LeaderboardEntry] = []

        for e in active {
            if median > 0, e.weightedValue > outlierThreshold * median {
                outlierEntries.append(e)
            } else {
                normalEntries.append(e)
            }
        }

        let sorted = normalEntries.sorted { $0.weightedValue > $1.weightedValue }
        var result: [RankedLeaderboardEntry] = sorted.enumerated().map { idx, e in
            RankedLeaderboardEntry(id: e.id, entry: e, rank: idx + 1, isOutlier: false)
        }
        for e in outlierEntries {
            result.append(RankedLeaderboardEntry(id: e.id, entry: e, rank: nil, isOutlier: true))
        }
        // Opted-out entries appended last without rank
        for e in entries where e.isOptedOut {
            result.append(RankedLeaderboardEntry(id: e.id, entry: e, rank: nil, isOutlier: false))
        }
        return result
    }

    // MARK: - Private

    static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }
}
