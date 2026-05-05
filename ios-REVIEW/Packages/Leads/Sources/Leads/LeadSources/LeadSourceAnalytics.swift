import Foundation
import Networking

// MARK: - LeadSourceStats

/// Per-source analytics: conversion rate + average value in cents.
public struct LeadSourceStats: Sendable, Identifiable, Hashable {
    public let id: String
    public let source: LeadSource
    /// Total number of leads from this source.
    public let totalLeads: Int
    /// Number of leads marked "won".
    public let convertedLeads: Int
    /// Conversion rate 0–1. Returns 0 if totalLeads is 0.
    public var conversionRate: Double {
        totalLeads > 0 ? Double(convertedLeads) / Double(totalLeads) : 0
    }
    /// Formatted percentage, e.g. "42%".
    public var conversionRateLabel: String {
        String(format: "%.0f%%", conversionRate * 100)
    }

    public init(source: LeadSource, totalLeads: Int, convertedLeads: Int) {
        self.id = source.rawValue
        self.source = source
        self.totalLeads = totalLeads
        self.convertedLeads = convertedLeads
    }
}

// MARK: - LeadSourceAnalytics

/// Pure calculator: given a flat list of `Lead`s, computes per-source stats.
/// No I/O, no side effects — safe to unit test.
public enum LeadSourceAnalytics {

    // MARK: - API

    /// Compute `LeadSourceStats` for every known `LeadSource` from `leads`.
    public static func computeStats(from leads: [Lead]) -> [LeadSourceStats] {
        // Build a mutable accumulator.
        var total:     [LeadSource: Int] = [:]
        var converted: [LeadSource: Int] = [:]

        for source in LeadSource.allCases {
            total[source] = 0
            converted[source] = 0
        }

        for lead in leads {
            let src = LeadSource.from(lead.source)
            total[src, default: 0] += 1
            if lead.status?.lowercased() == "won" {
                converted[src, default: 0] += 1
            }
        }

        return LeadSource.allCases.map { source in
            LeadSourceStats(
                source: source,
                totalLeads: total[source] ?? 0,
                convertedLeads: converted[source] ?? 0
            )
        }
        .sorted { $0.conversionRate > $1.conversionRate }
    }

    /// Returns the top-converting `LeadSource`, or `nil` if all sources have no leads.
    public static func topSource(from leads: [Lead]) -> LeadSource? {
        let stats = computeStats(from: leads)
        return stats.first(where: { $0.totalLeads > 0 })?.source
    }
}
