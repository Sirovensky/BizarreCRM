import SwiftUI
import Charts
import DesignSystem

// MARK: - TicketsByStatusCard
//
// §91.3 fixes applied:
//  [x] 1. Horizontal bar chart; status labels on left Y-axis, OUTSIDE bars.
//  [x] 2. X-axis numbers no longer overlap status names (Y-axis carries labels).
//  [x] 3. Each bar uses the tenant status hex from `TicketStatusPoint.color`
//         (falls back to cycling brand palette when server sends nil).

public struct TicketsByStatusCard: View {
    public let points: [TicketStatusPoint]
    /// When `true` (default), the entire card is hidden if all counts are zero.
    /// §91.12 (3): SLA Breaches card must not appear when there are zero breaches.
    public let hidesWhenAllZero: Bool

    public init(points: [TicketStatusPoint], hidesWhenAllZero: Bool = true) {
        self.points = points
        self.hidesWhenAllZero = hidesWhenAllZero
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Brand palette fallback — cycles for statuses whose server color is nil.
    private static let fallbackColors: [Color] = [
        .bizarreOrange, .bizarreTeal, .bizarreMagenta, .bizarreSuccess, .bizarreWarning
    ]

    /// Resolve display color for a status point, preferring the server hex value.
    private func barColor(for point: TicketStatusPoint, at index: Int) -> Color {
        if let hex = point.color, let resolved = Color(hex: hex) {
            return resolved
        }
        return Self.fallbackColors[index % Self.fallbackColors.count]
    }

    /// §91.12 (3): true when every data point has count == 0.
    private var allCountsAreZero: Bool {
        !points.isEmpty && points.allSatisfy { $0.count == 0 }
    }

    public var body: some View {
        // §91.12 (3): suppress the whole card rather than showing unlabelled zero bars
        if hidesWhenAllZero && allCountsAreZero {
            EmptyView()
        } else {
            cardBody
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if points.isEmpty {
                emptySparklineSilhouette
                    .frame(height: 160)
            } else {
                chart
                    // Height scales with number of status rows so bars stay readable.
                    .frame(height: max(120, CGFloat(points.count) * 40))
                    // X-axis: numeric count labels — no overlap since Y carries status names.
                    .chartXAxis {
                        AxisMarks(position: .bottom) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let v = value.as(Int.self) {
                                    Text("\(v)")
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                }
                            }
                        }
                    }
                    // Y-axis: status name labels on the leading side, OUTSIDE bars.
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel(anchor: .trailing) {
                                if let label = value.as(String.self) {
                                    Text(label)
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOnSurface)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .chartXAxisLabel("Count", alignment: .center)
                    .chartYAxisLabel("Status", position: .leading)
                    // §91.13 — bump axis font + contrast for a11y.
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisGridLine()
                            AxisValueLabel()
                                .font(.system(size: 12))
                                .foregroundStyle(Color.bizarreOnSurface)
                        }
                    }
                    .accessibilityChartDescriptor(TicketStatusChartDescriptor(points: points))
                legendRow
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    private var cardHeader: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.bizarreTeal)
                .accessibilityHidden(true)
            Text("Tickets by Status")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var chart: some View {
        Chart(points.indices, id: \.self) { idx in
            let pt = points[idx]
            let color = barColor(for: pt, at: idx)
            BarMark(
                x: .value("Count", pt.count),
                y: .value("Status", pt.status)
            )
            .foregroundStyle(color)
            .cornerRadius(DesignTokens.Radius.xs)
            // Count annotation placed OUTSIDE (trailing) the bar.
            .annotation(position: .trailing, alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("\(pt.count)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.smooth), value: points.count)
    }

    // MARK: - Legend

    /// Color-name + count pairs for each status bar (§91.13 item 4).
    private var legendRow: some View {
        let chips = points.indices.map { idx -> (String, Color, Int) in
            let pt = points[idx]
            let color = Self.statusColors[idx % Self.statusColors.count]
            return (pt.status, color, pt.count)
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(chips.indices, id: \.self) { idx in
                    let (status, color, count) = chips[idx]
                    HStack(spacing: BrandSpacing.xxs) {
                        Circle().fill(color).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text("\(status) \(count)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Chart legend: " + chips.map { "\($0.0) \($0.2)" }.joined(separator: ", ")
        )
    }

    // MARK: - Empty state

    /// Dashed sparkline silhouette when zero data points (§91.13 item 5).
    private var emptySparklineSilhouette: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Horizontal bar silhouette
            Path { path in
                let barHeights: [CGFloat] = [0.3, 0.55, 0.45, 0.2, 0.65]
                let step = h / CGFloat(barHeights.count + 1)
                for (i, frac) in barHeights.enumerated() {
                    let y = step * CGFloat(i + 1)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w * frac, y: y))
                }
            }
            .stroke(
                Color.bizarreOnSurface.opacity(0.18),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [8, 4])
            )
        }
        .overlay(alignment: .center) {
            Text("No data")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityLabel("No ticket status data for this period")
    }

    private var emptyState: some View {
        ContentUnavailableView("No Ticket Data",
                               systemImage: "chart.bar.fill",
                               description: Text("No ticket status data for this period."))
    }
}

// MARK: - Color(hex:) helper (mirrors Dashboard/OpenTicketsByStatusWidget)

private extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard h.count == 6 || h.count == 8 else { return nil }
        if h.count == 6 { h = "FF" + h }
        guard let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255,
            opacity: Double((val >> 24) & 0xFF) / 255
        )
    }
}

// MARK: - AXChartDescriptor

private struct TicketStatusChartDescriptor: AXChartDescriptorRepresentable {
    let points: [TicketStatusPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Status", categoryOrder: points.map(\.status))
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Count",
            range: 0...Double(points.map(\.count).max() ?? 1),
            gridlinePositions: []
        ) { "\(Int($0))" }
        let series = AXDataSeriesDescriptor(
            name: "Tickets by Status",
            isContinuous: false,
            dataPoints: points.map { pt in
                AXDataPoint(x: pt.status, y: Double(pt.count))
            }
        )
        return AXChartDescriptor(
            title: "Tickets by Status",
            summary: "Horizontal bar chart showing ticket count per status",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
