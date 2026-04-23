import SwiftUI
import Charts
import DesignSystem

// MARK: - RevenueChartCard
//
// Wired to GET /api/v1/reports/sales.
// Shows AreaMark + LineMark (period mode) or BarMark (bar mode) toggled by
// the user. iPad shows both variants side-by-side at the same time (2-up).

public struct RevenueChartCard: View {
    public let points: [RevenuePoint]
    /// Period-over-period change % from server totals (nil when unavailable).
    public let periodChangePct: Double?
    public let onDrillThrough: (RevenuePoint) -> Void

    public init(points: [RevenuePoint],
                periodChangePct: Double? = nil,
                onDrillThrough: @escaping (RevenuePoint) -> Void) {
        self.points = points
        self.periodChangePct = periodChangePct
        self.onDrillThrough = onDrillThrough
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var chartMode: RevenueChartMode = .line

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPoint: RevenuePoint?

    public var body: some View {
        // iPad 2-up: show line and bar charts side-by-side
        if sizeClass == .regular {
            ipadBody
        } else {
            phoneBody
        }
    }

    // MARK: - iPhone layout

    private var phoneBody: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            modeToggle
            chartContent
                .frame(height: 180)
                .chartXAxisLabel("Date", alignment: .center)
                .chartYAxisLabel("Revenue ($K)", position: .leading)
                .accessibilityChartDescriptor(RevenueChartDescriptor(points: points))
                .chartOverlay { proxy in drillOverlay(proxy: proxy) }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - iPad 2-up layout

    private var ipadBody: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                lineChart
                    .frame(height: 200)
                    .chartXAxisLabel("Date", alignment: .center)
                    .chartYAxisLabel("Revenue ($K)", position: .leading)
                    .accessibilityChartDescriptor(RevenueChartDescriptor(points: points))
                    .chartOverlay { proxy in drillOverlay(proxy: proxy) }
                    .frame(maxWidth: .infinity)

                barChart
                    .frame(height: 200)
                    .chartXAxisLabel("Date", alignment: .center)
                    .chartYAxisLabel("Revenue ($K)", position: .leading)
                    .accessibilityLabel("Revenue bar chart")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - Chart mode toggle (iPhone only)

    private var modeToggle: some View {
        Picker("Chart Mode", selection: $chartMode) {
            ForEach(RevenueChartMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Revenue chart display mode")
    }

    // MARK: - Chart content (phone)

    @ViewBuilder
    private var chartContent: some View {
        if points.isEmpty {
            emptyState
        } else {
            switch chartMode {
            case .line: lineChart
            case .bar:  barChart
            }
        }
    }

    // MARK: - Line chart (AreaMark + LineMark)

    private var lineChart: some View {
        Group {
            if points.isEmpty {
                emptyState
            } else {
                Chart(points) { pt in
                    AreaMark(
                        x: .value("Date", pt.date),
                        y: .value("Revenue ($K)", pt.amountDollars / 1000.0)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.bizarreOrange.opacity(0.35), Color.bizarreOrange.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", pt.date),
                        y: .value("Revenue ($K)", pt.amountDollars / 1000.0)
                    )
                    .foregroundStyle(Color.bizarreOrange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    if selectedPoint?.id == pt.id {
                        PointMark(
                            x: .value("Date", pt.date),
                            y: .value("Revenue ($K)", pt.amountDollars / 1000.0)
                        )
                        .foregroundStyle(Color.bizarreOrange)
                        .symbolSize(80)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: DesignTokens.Motion.smooth), value: points.count)
            }
        }
    }

    // MARK: - Bar chart (BarMark by period)

    private var barChart: some View {
        Group {
            if points.isEmpty {
                emptyState
            } else {
                Chart(points) { pt in
                    BarMark(
                        x: .value("Date", pt.date),
                        y: .value("Revenue ($K)", pt.amountDollars / 1000.0)
                    )
                    .foregroundStyle(
                        selectedPoint?.id == pt.id
                            ? Color.bizarreOrange
                            : Color.bizarreOrange.opacity(0.65)
                    )
                    .cornerRadius(DesignTokens.Radius.xs)
                }
                .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.smooth), value: points.count)
            }
        }
    }

    // MARK: - Card header

    @ViewBuilder
    private var cardHeader: some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Revenue")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            // Period-over-period badge when available
            if let pct = periodChangePct {
                periodBadge(pct: pct)
            } else if let pt = selectedPoint {
                Text(pt.amountDollars, format: .currency(code: "USD"))
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreTeal)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Revenue chart. Tap a data point to drill through.")
    }

    @ViewBuilder
    private func periodBadge(pct: Double) -> some View {
        let isUp = pct >= 0
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(String(format: "%.1f%%", abs(pct)))
                .font(.brandLabelLarge())
        }
        .foregroundStyle(isUp ? Color.bizarreSuccess : Color.bizarreError)
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background((isUp ? Color.bizarreSuccess : Color.bizarreError).opacity(0.12), in: Capsule())
        .accessibilityLabel(isUp ? "Up \(String(format: "%.1f", abs(pct))) percent vs prior period"
                                 : "Down \(String(format: "%.1f", abs(pct))) percent vs prior period")
    }

    // MARK: - Drill overlay

    @ViewBuilder
    private func drillOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let date: String = proxy.value(atX: value.location.x - geo.frame(in: .local).minX) else { return }
                            selectedPoint = points.first(where: { $0.date.hasPrefix(date.prefix(10)) })
                        }
                        .onEnded { _ in
                            if let pt = selectedPoint { onDrillThrough(pt) }
                            selectedPoint = nil
                        }
                )
        }
    }

    // MARK: - Shared helpers

    private var emptyState: some View {
        ContentUnavailableView("No Revenue Data",
                               systemImage: "chart.line.uptrend.xyaxis",
                               description: Text("No revenue data for this period."))
    }

    private var strokeBorder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
    }
}

// MARK: - RevenueChartMode

public enum RevenueChartMode: String, CaseIterable, Identifiable, Sendable {
    case line = "Line"
    case bar  = "Bar"

    public var id: String { rawValue }
    public var label: String { rawValue }
}

// MARK: - AXChartDescriptor

private struct RevenueChartDescriptor: AXChartDescriptorRepresentable {
    let points: [RevenuePoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Date", categoryOrder: points.map(\.date))
        let yAxis = AXNumericDataAxisDescriptor(title: "Revenue (USD)", range: 0...Double(points.map(\.amountCents).max() ?? 0) / 100.0, gridlinePositions: []) { val in
            String(format: "$%.2f", val)
        }
        let series = AXDataSeriesDescriptor(name: "Revenue", isContinuous: true, dataPoints: points.map { pt in
            AXDataPoint(x: pt.date, y: pt.amountDollars)
        })
        return AXChartDescriptor(title: "Revenue Chart", summary: "Area chart of revenue over time", xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}
