import SwiftUI
import Charts
import DesignSystem

// MARK: - RevenueChartCard
//
// Wired to GET /api/v1/reports/sales.
// Shows AreaMark + LineMark (period mode) or BarMark (bar mode) toggled by
// the user on iPhone. iPad shows 3 columns: trend chart | bar-by-period | KPI panel.

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
                .chartXAxisLabel("Date", alignment: .center)
                // §91.2-5: show "$K" suffix on Y-axis tick values instead of bare numbers
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("$\(String(format: "%.0fK", v))")
                                    .font(.brandLabelSmall())
                            }
                        }
                        AxisGridLine()
                    }
                }
                .accessibilityChartDescriptor(RevenueChartDescriptor(points: points))
                .chartOverlay { proxy in drillOverlay(proxy: proxy) }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - iPad layout: primary Trend chart | KPI panel; By Period behind DisclosureGroup
    // §91.2-4: avoid duplicating Trend + By Period simultaneously — secondary chart
    // is now collapsed behind a DisclosureGroup so the primary chart dominates.

    @State private var showByPeriod = false

    private var ipadBody: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                // Column 1 — primary line chart (Trend)
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Trend")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    lineChart
                        .frame(height: 200)
                        .chartXAxisLabel("Date", alignment: .center)
                        // §91.2-5: label Y-axis with $K unit
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("$\(String(format: "%.0fK", v))")
                                            .font(.brandLabelSmall())
                                    }
                                }
                                AxisGridLine()
                            }
                        }
                        .accessibilityChartDescriptor(RevenueChartDescriptor(points: points))
                        .chartOverlay { proxy in drillOverlay(proxy: proxy) }
                }
                .frame(maxWidth: .infinity)

                // Column 2 — KPI side panel (primary)
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

            // §91.2-4: "By Period" bar chart hidden by default; user can expand.
            DisclosureGroup(isExpanded: $showByPeriod) {
                barChart
                    .frame(height: 160)
                    .chartXAxisLabel("Date", alignment: .center)
                    // §91.2-5: label Y-axis with $K unit
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("$\(String(format: "%.0fK", v))")
                                        .font(.brandLabelSmall())
                                }
                            }
                            AxisGridLine()
                        }
                    }
                    .accessibilityLabel("Revenue bar chart by period")
                    .padding(.top, BrandSpacing.xs)
            } label: {
                Text("By Period")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel(showByPeriod ? "By Period chart, expanded" : "By Period chart, collapsed")
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
                    Text("Peak")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(p.amountDollars, format: .currency(code: "USD"))
                        .font(.brandTitleSmall())
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
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value, format: .currency(code: "USD"))
                .font(.brandTitleSmall())
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
        .frame(minHeight: 44)
        .accessibilityLabel("Revenue chart display mode")
    }

    // MARK: - Chart content (phone)

    @ViewBuilder
    private var chartContent: some View {
        if points.isEmpty {
            emptySparklineSilhouette
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
                emptySparklineSilhouette
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
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel()
                            .font(.system(size: 12))
                            .foregroundStyle(Color.bizarreOnSurface)
                    }
                }
            }
        }
    }

    // MARK: - Bar chart (BarMark by period)

    private var barChart: some View {
        Group {
            if points.isEmpty {
                emptySparklineSilhouette
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
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel()
                            .font(.system(size: 12))
                            .foregroundStyle(Color.bizarreOnSurface)
                    }
                }
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

    // §91.2-1: flat delta (0.0%) → neutral dash, not green up-arrow.
    @ViewBuilder
    private func periodBadge(pct: Double) -> some View {
        let isFlat = (pct == 0.0)
        let isUp   = pct > 0
        let icon: String = isFlat ? "minus" : (isUp ? "arrow.up.right" : "arrow.down.right")
        let label: String = isFlat
            ? "Unchanged vs prior period"
            : (isUp ? "Up \(String(format: "%.1f", abs(pct))) percent vs prior period"
                    : "Down \(String(format: "%.1f", abs(pct))) percent vs prior period")
        let displayText: String = isFlat ? "–" : String(format: "%.1f%%", abs(pct))
        let badgeColor: Color = isFlat ? .bizarreOnSurfaceMuted : (isUp ? .bizarreSuccess : .bizarreError)

        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: icon)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(displayText)
                .font(.brandLabelLarge())
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(badgeColor.opacity(0.12), in: Capsule())
        .accessibilityLabel(label)
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

    /// Dashed sparkline silhouette rendered when there are zero data points (§91.13 item 5).
    private var emptySparklineSilhouette: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Gentle wave path simulating a flat-ish trend line
            Path { path in
                path.move(to: CGPoint(x: 0, y: h * 0.65))
                path.addCurve(
                    to: CGPoint(x: w * 0.5, y: h * 0.45),
                    control1: CGPoint(x: w * 0.2, y: h * 0.55),
                    control2: CGPoint(x: w * 0.3, y: h * 0.4)
                )
                path.addCurve(
                    to: CGPoint(x: w, y: h * 0.5),
                    control1: CGPoint(x: w * 0.7, y: h * 0.5),
                    control2: CGPoint(x: w * 0.85, y: h * 0.55)
                )
            }
            .stroke(
                Color.bizarreOnSurface.opacity(0.18),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4], dashPhase: 0)
            )
        }
        .overlay(alignment: .center) {
            Text("No data")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityLabel("No revenue data for this period")
    }

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
