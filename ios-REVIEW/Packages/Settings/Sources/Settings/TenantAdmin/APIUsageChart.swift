import SwiftUI
import Charts
import DesignSystem

// MARK: - APIUsageChart

/// Bar chart of API requests per day over the last 30 days.
/// Uses Swift Charts (iOS 16+). Rendered inside `TenantAdminView`.
public struct APIUsageChart: View {

    let buckets: [ChartBucket]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(dailyBuckets: [DailyBucket]) {
        self.buckets = Self.process(dailyBuckets)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("API Requests — Last 30 Days")
                .font(.footnote)
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)

            if buckets.isEmpty {
                emptyState
            } else {
                chart
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart(buckets) { bucket in
            BarMark(
                x: .value("Date", bucket.label),
                y: .value("Requests", bucket.count)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.bizarreOrange, Color.bizarreTeal],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .cornerRadius(DesignTokens.Radius.xs)
            .accessibilityLabel("\(bucket.label): \(bucket.count) requests")
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 7)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 160)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: DesignTokens.Motion.smooth),
            value: buckets.map(\.count)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bar chart of API requests over the last 30 days")
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            Text("No data")
                .font(.caption)
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
        }
        .frame(height: 160)
    }

    // MARK: - Data processing

    static func process(_ input: [DailyBucket]) -> [ChartBucket] {
        // Fill in any missing days within the last 30 calendar days
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -29, to: today) else {
            return input.map { ChartBucket(date: $0.date, count: $0.count) }
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var dict: [String: Int] = [:]
        for bucket in input { dict[bucket.date] = bucket.count }

        var result: [ChartBucket] = []
        var cursor = start
        while cursor <= today {
            let key = formatter.string(from: cursor)
            // Short label: "Apr 1"
            let label = shortLabel(from: cursor)
            result.append(ChartBucket(date: key, label: label, count: dict[key] ?? 0))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return result
    }

    private static func shortLabel(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

// MARK: - Supporting types

/// Processed bucket ready for charting.
public struct ChartBucket: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let count: Int

    public init(date: String, label: String? = nil, count: Int) {
        self.id = date
        self.label = label ?? date
        self.count = count
    }
}

/// Input alias matching `APIUsageStats.DailyBucket` interface.
public typealias DailyBucket = APIUsageStats.DailyBucket
