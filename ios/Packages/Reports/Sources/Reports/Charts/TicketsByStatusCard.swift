import SwiftUI
import Charts
import DesignSystem

// MARK: - TicketsByStatusCard

public struct TicketsByStatusCard: View {
    public let points: [TicketStatusPoint]

    public init(points: [TicketStatusPoint]) {
        self.points = points
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Brand palette per status slot (cycles for unknown statuses)
    private static let statusColors: [Color] = [
        .bizarreOrange, .bizarreTeal, .bizarreMagenta, .bizarreSuccess, .bizarreWarning
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if points.isEmpty {
                emptySparklineSilhouette
                    .frame(height: 160)
            } else {
                chart
                    .frame(height: 160)
                    .chartXAxisLabel("Count", alignment: .center)
                    .chartYAxisLabel("Status", position: .leading)
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
            let color = Self.statusColors[idx % Self.statusColors.count]
            BarMark(
                x: .value("Count", pt.count),
                y: .value("Status", pt.status)
            )
            .foregroundStyle(color)
            .cornerRadius(DesignTokens.Radius.xs)
            .annotation(position: .trailing) {
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

// MARK: - AXChartDescriptor

private struct TicketStatusChartDescriptor: AXChartDescriptorRepresentable {
    let points: [TicketStatusPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        // x is categorical (status label), y is the count value.
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Status", categoryOrder: points.map(\.status))
        let yAxis = AXNumericDataAxisDescriptor(title: "Count", range: 0...Double(points.map(\.count).max() ?? 1), gridlinePositions: []) { "\(Int($0))" }
        let series = AXDataSeriesDescriptor(name: "Tickets by Status", isContinuous: false, dataPoints: points.map { pt in
            AXDataPoint(x: pt.status, y: Double(pt.count))
        })
        return AXChartDescriptor(title: "Tickets by Status", summary: "Horizontal bar chart showing ticket count per status", xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}
