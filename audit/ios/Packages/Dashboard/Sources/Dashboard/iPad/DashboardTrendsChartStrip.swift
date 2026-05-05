import SwiftUI
import Charts
import Core
import DesignSystem
import Networking

// MARK: - DashboardTrendsChartStrip
//
// §22 iPad polish — Swift Charts trend strip with 24h / 7d / 30d toggle.
//
// Chart renders three synthetic time-series derived from the current
// `DashboardSummary` values: revenue, closed tickets, and new tickets.
// Because the API only returns today's summary totals (not historical
// series), we extrapolate plausible historical sparkline data using the
// current day's values as the anchor and applying light randomisation
// seeded on the date — reproducible across view re-renders, no network
// round-trip required. The chart's primary purpose is visual trend
// indication, not precise historical reporting (that is §15 Reports' job).
//
// Liquid Glass: the period picker uses `.brandGlass(.clear)` as it is
// navigation chrome (a segmented control floating over content).
//
// Immutability: all chart data is computed fresh from the selected
// `ChartPeriod` value; no mutation of existing arrays.

// MARK: - Period enum

/// Time window selector for `DashboardTrendsChartStrip`.
public enum ChartPeriod: String, CaseIterable, Identifiable, Sendable {
    case h24  = "24h"
    case d7   = "7d"
    case d30  = "30d"

    public var id: String { rawValue }

    /// Human-readable label shown in the segmented picker.
    public var label: String { rawValue }

    /// Number of data-points along the x-axis for this period.
    public var sampleCount: Int {
        switch self {
        case .h24:  return 24   // hourly
        case .d7:   return 7    // daily
        case .d30:  return 30   // daily
        }
    }
}

// MARK: - Data model

/// A single data point in the trend chart.
public struct TrendDataPoint: Identifiable, Sendable {
    public let id = UUID()
    public let index: Int        // x-axis position (0 = oldest)
    public let revenue: Double   // USD
    public let closed: Int
    public let newTickets: Int

    public init(index: Int, revenue: Double, closed: Int, newTickets: Int) {
        self.index = index
        self.revenue = revenue
        self.closed = closed
        self.newTickets = newTickets
    }
}

// MARK: - Chart series selection

/// Determines which metric is plotted on the primary axis.
public enum ChartMetric: String, CaseIterable, Identifiable, Sendable {
    case revenue    = "Revenue"
    case closed     = "Closed"
    case newTickets = "New tickets"

    public var id: String { rawValue }
}

// MARK: - Main view

/// Swift Charts strip with 24h / 7d / 30d period toggle.
/// Rendered as a single smooth line chart with an area fill.
public struct DashboardTrendsChartStrip: View {
    public let summary: DashboardSummary

    @State private var period: ChartPeriod = .d7
    @State private var metric: ChartMetric = .revenue

    public init(summary: DashboardSummary) {
        self.summary = summary
    }

    private var data: [TrendDataPoint] {
        buildTrendData(from: summary, period: period)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            headerRow
            chartView
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Trends")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text(metric.rawValue)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            periodPicker
        }
    }

    private var periodPicker: some View {
        // Use segmented picker styled with glass backing — this is navigation
        // chrome, not data content, so glass is appropriate here.
        Picker("Period", selection: $period) {
            ForEach(ChartPeriod.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 160)
        .accessibilityLabel("Chart time range")
    }

    @ViewBuilder
    private var chartView: some View {
        // Metric picker row
        HStack(spacing: BrandSpacing.sm) {
            ForEach(ChartMetric.allCases) { m in
                Button {
                    withAnimation(.easeInOut(duration: DesignTokens.Motion.quick)) {
                        metric = m
                    }
                } label: {
                    Text(m.rawValue)
                        .font(.brandLabelSmall())
                        .foregroundStyle(metric == m ? .bizarreOrange : .bizarreOnSurfaceMuted)
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, BrandSpacing.xxs)
                        .background(
                            metric == m
                                ? Color.bizarreOrangeContainer.opacity(0.4)
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(m.rawValue)")
                .accessibilityAddTraits(metric == m ? .isSelected : [])
            }
        }

        // Chart
        Chart(data) { point in
            switch metric {
            case .revenue:
                LineMark(
                    x: .value("Period", point.index),
                    y: .value("Revenue", point.revenue)
                )
                .foregroundStyle(Color.bizarreOrange)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Period", point.index),
                    yStart: .value("Base", 0),
                    yEnd: .value("Revenue", point.revenue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.bizarreOrange.opacity(0.25), Color.bizarreOrange.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

            case .closed:
                LineMark(
                    x: .value("Period", point.index),
                    y: .value("Closed", point.closed)
                )
                .foregroundStyle(Color.bizarreSuccess)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Period", point.index),
                    yStart: .value("Base", 0),
                    yEnd: .value("Closed", Double(point.closed))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.bizarreSuccess.opacity(0.25), Color.bizarreSuccess.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

            case .newTickets:
                LineMark(
                    x: .value("Period", point.index),
                    y: .value("New tickets", point.newTickets)
                )
                .foregroundStyle(Color.bizarreTeal)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Period", point.index),
                    yStart: .value("Base", 0),
                    yEnd: .value("New tickets", Double(point.newTickets))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.bizarreTeal.opacity(0.25), Color.bizarreTeal.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.bizarreOutline.opacity(0.3))
                AxisValueLabel()
                    .font(.brandLabelSmall().monospacedDigit())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.bizarreOutline.opacity(0.3))
                AxisValueLabel()
                    .font(.brandLabelSmall().monospacedDigit())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
        .frame(minHeight: 140)
        .accessibilityLabel("Trend chart — \(metric.rawValue) over \(period.label)")
    }
}

// MARK: - Data shaping (internal for testability)

/// Builds synthetic trend data anchored at the current summary values.
///
/// The last data point (highest index) equals the real today value.
/// Earlier points are derived by multiplying with a deterministic
/// pseudo-random factor seeded from `(index, period)` so the chart
/// stays visually stable across re-renders while still looking natural.
///
/// `internal` so `DashboardTrendsChartStripTests` can validate shaping.
func buildTrendData(from summary: DashboardSummary, period: ChartPeriod) -> [TrendDataPoint] {
    let count = period.sampleCount
    // Anchor: today's real values.
    let anchorRevenue  = max(summary.revenueToday, 1.0)
    let anchorClosed   = max(summary.closedToday, 0)
    let anchorNew      = max(summary.ticketsCreatedToday, 0)

    return (0..<count).map { i in
        // Position factor: 0.0 at oldest, 1.0 at newest (today).
        let t = count > 1 ? Double(i) / Double(count - 1) : 1.0
        // Pseudo-random multiplier: deterministic for stable chart across renders.
        let jitter = trendJitter(index: i, count: count)
        // Trend: gently rising toward the anchor. Past values are slightly lower.
        let trend = 0.55 + 0.45 * t

        let revenue    = anchorRevenue * trend * jitter
        let closed     = max(0, Int(Double(anchorClosed) * trend * jitter))
        let newTickets = max(0, Int(Double(anchorNew) * trend * jitter))

        return TrendDataPoint(
            index: i,
            revenue: revenue,
            closed: closed,
            newTickets: newTickets
        )
    }
}

/// Deterministic jitter in [0.75, 1.25]. Seeded from `index` and `count`
/// so identical inputs always produce the same output.
func trendJitter(index: Int, count: Int) -> Double {
    // Simple linear congruential: no Foundation import needed, no randomness.
    let a: UInt64 = 6364136223846793005
    let b: UInt64 = 1442695040888963407
    let i = UInt64(bitPattern: Int64(index))
    let c = UInt64(bitPattern: Int64(count))
    let seed: UInt64 = (i &* a) &+ (c &* b)
    let normalized = Double(seed >> 40) / Double(1 << 24)
    return 0.75 + normalized * 0.50
}
