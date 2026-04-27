import SwiftUI
import Charts
import DesignSystem

// MARK: - YoYGrowthCard
//
// §15.2 — Year-over-year growth comparison.
// Shows current-year vs prior-year revenue per period using BarMark grouped.
// Data is derived client-side by comparing two SalesReportResponse snapshots.

public struct YoYDataPoint: Sendable, Identifiable {
    public let id: String
    /// Period label, e.g. "Jan", "Q1", or "2024-01".
    public let period: String
    /// Current-period revenue in dollars.
    public let currentRevenue: Double
    /// Prior-year revenue for the same period in dollars.
    public let priorRevenue: Double
    /// Growth % (current - prior) / prior × 100. nil when prior == 0.
    public var growthPct: Double? {
        guard priorRevenue > 0 else { return nil }
        return ((currentRevenue - priorRevenue) / priorRevenue) * 100.0
    }

    public init(period: String, currentRevenue: Double, priorRevenue: Double) {
        self.id = period
        self.period = period
        self.currentRevenue = currentRevenue
        self.priorRevenue = priorRevenue
    }
}

public struct YoYGrowthCard: View {
    public let points: [YoYDataPoint]
    /// Overall period growth percentage (nil when unavailable).
    public let overallGrowthPct: Double?

    public init(points: [YoYDataPoint], overallGrowthPct: Double? = nil) {
        self.points = points
        self.overallGrowthPct = overallGrowthPct
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if points.isEmpty {
                emptyState
            } else {
                chart
                    .frame(height: 180)
                    .chartXAxisLabel("Period", alignment: .center)
                    .chartYAxisLabel("Revenue ($K)", position: .leading)
                    .accessibilityChartDescriptor(YoYChartDescriptor(points: points))
                legend
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.bizarreTeal)
                .accessibilityHidden(true)
            Text("Year-over-Year Growth")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            if let pct = overallGrowthPct {
                growthBadge(pct: pct)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Year-over-Year Growth chart" + (overallGrowthPct.map { pct in
            ". Overall: \(String(format: "%.1f", abs(pct)))% \(pct >= 0 ? "growth" : "decline")"
        } ?? ""))
    }

    // MARK: - Chart (grouped BarMark)

    private var chart: some View {
        Chart {
            ForEach(points) { pt in
                BarMark(
                    x: .value("Period", pt.period),
                    y: .value("Revenue ($K)", pt.priorRevenue / 1_000.0),
                    width: .ratio(0.4)
                )
                .foregroundStyle(Color.bizarreOnSurfaceMuted.opacity(0.55))
                .position(by: .value("Year", "Prior Year"))
                .cornerRadius(DesignTokens.Radius.xxs)

                BarMark(
                    x: .value("Period", pt.period),
                    y: .value("Revenue ($K)", pt.currentRevenue / 1_000.0),
                    width: .ratio(0.4)
                )
                .foregroundStyle(Color.bizarreOrange)
                .position(by: .value("Year", "Current"))
                .cornerRadius(DesignTokens.Radius.xxs)
                .annotation(position: .top) {
                    if let pct = pt.growthPct {
                        Text(String(format: "%+.0f%%", pct))
                            .font(.brandLabelSmall())
                            .foregroundStyle(pct >= 0 ? Color.bizarreSuccess : Color.bizarreError)
                            .fixedSize()
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.smooth),
                   value: points.count)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: BrandSpacing.md) {
            legendDot(color: Color.bizarreOnSurfaceMuted.opacity(0.55), label: "Prior Year")
            legendDot(color: Color.bizarreOrange, label: "Current Year")
        }
        .font(.brandLabelSmall())
        .foregroundStyle(.bizarreOnSurfaceMuted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: gray = Prior Year, orange = Current Year")
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: BrandSpacing.xxs) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: - Growth badge

    private func growthBadge(pct: Double) -> some View {
        let isUp = pct >= 0
        return HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(String(format: "%.1f%%", abs(pct)))
                .font(.brandLabelLarge())
        }
        .foregroundStyle(isUp ? Color.bizarreSuccess : Color.bizarreError)
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background((isUp ? Color.bizarreSuccess : Color.bizarreError).opacity(0.12),
                    in: Capsule())
        .accessibilityLabel(isUp
            ? "Up \(String(format: "%.1f", abs(pct))) percent year-over-year"
            : "Down \(String(format: "%.1f", abs(pct))) percent year-over-year")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No YoY Data",
            systemImage: "chart.bar.xaxis",
            description: Text("Year-over-year comparison requires data from two periods.")
        )
    }
}

// MARK: - AXChartDescriptor

private struct YoYChartDescriptor: AXChartDescriptorRepresentable {
    let points: [YoYDataPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Period",
            categoryOrder: points.map(\.period)
        )
        let maxVal = max(
            points.map(\.currentRevenue).max() ?? 0,
            points.map(\.priorRevenue).max() ?? 0
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Revenue (USD)",
            range: 0...maxVal,
            gridlinePositions: []
        ) { String(format: "$%.2f", $0) }

        let current = AXDataSeriesDescriptor(
            name: "Current Year", isContinuous: false,
            dataPoints: points.map { AXDataPoint(x: $0.period, y: $0.currentRevenue) }
        )
        let prior = AXDataSeriesDescriptor(
            name: "Prior Year", isContinuous: false,
            dataPoints: points.map { AXDataPoint(x: $0.period, y: $0.priorRevenue) }
        )
        return AXChartDescriptor(
            title: "Year-over-Year Revenue Growth",
            summary: "Grouped bar chart comparing current year vs prior year revenue per period",
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [current, prior]
        )
    }
}
