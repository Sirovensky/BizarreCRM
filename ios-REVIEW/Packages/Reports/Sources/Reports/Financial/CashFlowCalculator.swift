import Foundation

// MARK: - CashFlowCalculator

/// Pure, stateless cash-flow series builder. All values in cents.
public enum CashFlowCalculator {

    public enum GroupBy: Sendable {
        case day, week, month
    }

    /// Build a cash flow series by bucketing inflows and outflows into periods.
    /// - Parameters:
    ///   - inflows:  Events that increase cash (payments received, deposits). Date + amountCents.
    ///   - outflows: Events that decrease cash (PO payments, expenses). Date + amountCents.
    ///   - groupBy:  Bucket granularity.
    /// - Returns: Sorted array of `CashFlowPoint` (oldest first).
    public static func buildSeries(
        inflows: [(date: Date, amountCents: Int)],
        outflows: [(date: Date, amountCents: Int)],
        groupBy: GroupBy = .day,
        calendar: Calendar = .current
    ) -> [CashFlowPoint] {

        var buckets: [String: (inflow: Int, outflow: Int)] = [:]

        for item in inflows {
            let key = periodKey(for: item.date, groupBy: groupBy, calendar: calendar)
            var bucket = buckets[key] ?? (inflow: 0, outflow: 0)
            bucket.inflow += item.amountCents
            buckets[key] = bucket
        }
        for item in outflows {
            let key = periodKey(for: item.date, groupBy: groupBy, calendar: calendar)
            var bucket = buckets[key] ?? (inflow: 0, outflow: 0)
            bucket.outflow += item.amountCents
            buckets[key] = bucket
        }

        return buckets
            .sorted { $0.key < $1.key }
            .map { key, value in
                CashFlowPoint(
                    id: key,
                    date: dateFromKey(key, groupBy: groupBy, calendar: calendar),
                    inflowCents: value.inflow,
                    outflowCents: value.outflow
                )
            }
    }

    /// Net cash position (cumulative) over the series.
    public static func cumulativeNet(series: [CashFlowPoint]) -> [CashFlowPoint] {
        var running = 0
        return series.map { point in
            running += point.netCents
            return CashFlowPoint(
                id: point.id,
                date: point.date,
                inflowCents: running + point.outflowCents,
                outflowCents: point.outflowCents
            )
        }
    }

    // MARK: - Private helpers

    private static func periodKey(for date: Date, groupBy: GroupBy, calendar: Calendar) -> String {
        switch groupBy {
        case .day:
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d",
                          comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
        case .week:
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        }
    }

    private static func dateFromKey(_ key: String, groupBy: GroupBy, calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        switch groupBy {
        case .day:
            formatter.dateFormat = "yyyy-MM-dd"
        case .week:
            formatter.dateFormat = "yyyy-'W'ww"
        case .month:
            formatter.dateFormat = "yyyy-MM"
        }
        return formatter.date(from: key) ?? Date.distantPast
    }
}
