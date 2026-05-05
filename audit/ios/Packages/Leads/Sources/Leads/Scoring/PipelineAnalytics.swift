import Foundation
import Networking

// MARK: - PipelineStageStats

/// Immutable snapshot of lead counts for a single pipeline stage.
public struct PipelineStageStats: Sendable, Equatable, Identifiable {
    public let stage: PipelineStage
    public let count: Int
    /// Fraction of all pipeline leads that are in this stage (0–1).
    public let share: Double

    public var id: String { stage.rawValue }

    public init(stage: PipelineStage, count: Int, share: Double) {
        self.stage = stage
        self.count = count
        self.share = share
    }
}

// MARK: - PipelineConversionStats

/// Conversion metrics for a lead pipeline snapshot.
public struct PipelineConversionStats: Sendable, Equatable {
    /// Total leads considered (excluding no-stage).
    public let totalLeads: Int
    /// Leads in the "won" stage.
    public let wonLeads: Int
    /// Leads in the "lost" stage.
    public let lostLeads: Int
    /// Leads still active (not won or lost).
    public let activeLeads: Int
    /// Closed-won rate: wonLeads / (wonLeads + lostLeads). 0 when no closed leads.
    public let winRate: Double
    /// Overall conversion rate: wonLeads / totalLeads. 0 when totalLeads == 0.
    public let overallConversionRate: Double

    public init(
        totalLeads: Int,
        wonLeads: Int,
        lostLeads: Int,
        activeLeads: Int,
        winRate: Double,
        overallConversionRate: Double
    ) {
        self.totalLeads             = totalLeads
        self.wonLeads               = wonLeads
        self.lostLeads              = lostLeads
        self.activeLeads            = activeLeads
        self.winRate                = winRate
        self.overallConversionRate  = overallConversionRate
    }

    /// Formatted win rate, e.g. "42%".
    public var winRateLabel: String {
        String(format: "%.0f%%", winRate * 100)
    }

    /// Formatted overall conversion rate, e.g. "18%".
    public var overallConversionRateLabel: String {
        String(format: "%.0f%%", overallConversionRate * 100)
    }
}

// MARK: - PipelineAnalytics

/// Pure pipeline analytics calculator.
/// No I/O, no side effects — instantiated per-computation.
public enum PipelineAnalytics {

    // MARK: - Counts by stage

    /// Returns per-stage counts for every `PipelineStage`, ordered by the
    /// canonical funnel sequence (new → qualified → quoted → won → lost).
    public static func stageCounts(from leads: [Lead]) -> [PipelineStageStats] {
        var counts: [PipelineStage: Int] = [:]
        for stage in PipelineStage.allCases {
            counts[stage] = 0
        }
        for lead in leads {
            let stage = PipelineStage.from(status: lead.status)
            counts[stage, default: 0] += 1
        }
        let total = leads.count
        return PipelineStage.allCases.map { stage in
            let count = counts[stage] ?? 0
            let share = total > 0 ? Double(count) / Double(total) : 0.0
            return PipelineStageStats(stage: stage, count: count, share: share)
        }
    }

    // MARK: - Conversion rate

    /// Computes win rate and overall conversion stats from a flat lead list.
    public static func conversionStats(from leads: [Lead]) -> PipelineConversionStats {
        var wonCount    = 0
        var lostCount   = 0
        var activeCount = 0

        for lead in leads {
            switch lead.status?.lowercased() {
            case "won":
                wonCount += 1
            case "lost":
                lostCount += 1
            default:
                activeCount += 1
            }
        }

        let closedCount = wonCount + lostCount
        let winRate     = closedCount > 0 ? Double(wonCount) / Double(closedCount) : 0.0
        let total       = leads.count
        let overall     = total > 0 ? Double(wonCount) / Double(total) : 0.0

        return PipelineConversionStats(
            totalLeads:            total,
            wonLeads:              wonCount,
            lostLeads:             lostCount,
            activeLeads:           activeCount,
            winRate:               winRate,
            overallConversionRate: overall
        )
    }

    // MARK: - Funnel drop-off

    /// Ordered funnel stages (excludes "lost" which is a side branch).
    public static let funnelOrder: [PipelineStage] = [.new, .qualified, .quoted, .won]

    /// Returns stage counts in funnel order (new → won), suitable for a
    /// `PipelineFunnelChart`. Lost leads are excluded from the funnel.
    public static func funnelCounts(from leads: [Lead]) -> [PipelineStageStats] {
        let allCounts = stageCounts(from: leads)
        let countsByStage = Dictionary(uniqueKeysWithValues: allCounts.map { ($0.stage, $0) })
        // Re-compute share against funnel-only total (no lost).
        let funnelTotal = funnelOrder.reduce(0) { $0 + (countsByStage[$1]?.count ?? 0) }
        return funnelOrder.map { stage in
            let count = countsByStage[stage]?.count ?? 0
            let share = funnelTotal > 0 ? Double(count) / Double(funnelTotal) : 0.0
            return PipelineStageStats(stage: stage, count: count, share: share)
        }
    }
}
