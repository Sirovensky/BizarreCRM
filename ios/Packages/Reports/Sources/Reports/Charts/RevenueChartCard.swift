import SwiftUI
import Charts
import DesignSystem

// MARK: - RevenueChartCard
//
// Wired to GET /api/v1/reports/sales.
// Shows AreaMark + LineMark (period mode) or BarMark (bar mode) toggled by
// the user on iPhone. iPad shows 3 columns: trend chart | bar-by-period | KPI panel.
//
// §91.12 (1): The card is context-aware. When displayed inside the Inventory tab,
// pass `.inventory` so the title and data reflect inventory revenue only.
// Pass `.hidden` to suppress the card entirely from the Inventory tab when no
// inventory-specific revenue series is available.

public enum RevenueCardContext: Sendable {
    /// Standard sales-tab revenue (default).
    case sales
    /// Inventory-tab revenue — title changes and a note is shown.
    case inventory
    /// Card is fully suppressed; callers should not render it at all.
    case hidden
}

public struct RevenueChartCard: View {
    public let points: [RevenuePoint]
    /// Period-over-period change % from server totals (nil when unavailable).
    public let periodChangePct: Double?
    /// Which dashboard tab is hosting this card (§91.12 item 1).
    public let context: RevenueCardContext
    public let onDrillThrough: (RevenuePoint) -> Void

    public init(points: [RevenuePoint],
                periodChangePct: Double? = nil,
                context: RevenueCardContext = .sales,
                onDrillThrough: @escaping (RevenuePoint) -> Void) {
        self.points = points
        self.periodChangePct = periodChangePct
        self.context = context
        self.onDrillThrough = onDrillThrough
    }

    /// Returns `nil` (suppress card) when context is `.hidden`.
    public var isVisible: Bool { context != .hidden }

    private var cardTitle: String {
        switch context {
        case .sales:      return "Revenue"
        case .inventory:  return "Inventory Revenue"
        case .hidden:     return "Revenue"
        }
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var chartMode: RevenueChartMode = .line

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPoint: RevenuePoint?

    public var body: some View {
        // iPad: 3-column layout — trend chart | bar-by-period | KPI panel
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
                .brandChartAxisStyle()
                .chartXAxisLabel("Date", alignment: .center)
                .chartYAxisLabel("Revenue ($K)", position: .leading)
                .accessibilityChartDescriptor(RevenueChartDescriptor(points: points))
                .chartOverlay { proxy in drillOverlay(proxy: proxy) }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - iPad 3-column layout: chart | legend | KPI panel

    private var ipadBody: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                // Column 1 — line chart
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Trend")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    lineChart
                        .frame(height: 200)
                        .brandChartAxisStyle()
                        .chartXAxisLabel("Date", alignment: .center)
                        .chartYAxisLabel("Revenue ($K)", position: .leading)
                        .accessibilityChartDescriptor(RevenueChartDescriptor(points: points))
                        .chartOverlay { proxy in drillOverlay(proxy: proxy) }
                }
                .frame(maxWidth: .infinity)

                // Column 2 — bar chart (acts as period legend)
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("By Period")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    barChart
                        .frame(height: 200)
                        .brandChartAxisStyle()
                        .chartXAxisLabel("Date", alignment: .center)
                        .chartYAxisLabel("Revenue ($K)", position: .leading)
                        .accessibilityLabel("Revenue bar chart by period")
                }
                .frame(maxWidth: .infinity)

                // Column 3 — KPI side panel
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    Text("KPIs")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityAddTraits(.isHeader)
                    kpiPanel
                }
                .frame(minWidth: 140, maxWidth: 180)
                .padding(.top, BrandSpacing.xxs)
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - KPI panel (iPad column 3)

    @ViewBuilder
    private var kpiPanel: some View {
        let total = points.reduce(0.0) { $0 + $1.amountDollars }
        let avg   = points.isEmpty ? 0.0 : total / Double(points.count)
        let peak  = points.max(by: { $0.amountDollars < $1.amountDollars })

        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            revenueKpiCell(label: "Total", value: total, color: .bizarreOrange)
            Divider()
            revenueKpiCell(label: "Avg / period", value: avg, color: .bizarreTeal)
            Divider()
            if let p = peak {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    // §91.10: label primary, value uses unified brandKpiValue
                    Text("Peak")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(p.amountDollars, format: .currency(code: "USD"))
                        .font(.brandKpiValue())
                        .monospacedDigit()
                        .foregroundStyle(.bizarreSuccess)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(p.date)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Peak revenue \(String(format: "$%.2f", p.amountDollars)) on \(p.date)")
            }
            if let pct = periodChangePct {
                Divider()
                periodBadge(pct: pct)
            }
        }
    }

    private func revenueKpiCell(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            // §91.10: label = primary text, value = semantic color (not reversed)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurface)
            Text(value, format: .currency(code: "USD"))
                .font(.brandKpiValue())
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(String(format: "$%.2f", value))")
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
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(cardTitle)
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
            // §91.12 (1): inventory-tab note so users know this is scoped revenue
            if context == .inventory {
                Text("Showing inventory product revenue only — not service revenue.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cardTitle) chart. Tap a data point to drill through.")
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
