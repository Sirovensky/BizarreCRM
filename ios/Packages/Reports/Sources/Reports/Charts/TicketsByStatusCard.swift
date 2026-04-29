import SwiftUI
import Charts
import DesignSystem

// MARK: - TicketsByStatusCard

public struct TicketsByStatusCard: View {
    public let points: [TicketStatusPoint]
    /// Called when the user taps a bar; receives the tapped status label.
    public let onTap: ((String) -> Void)?

    public init(points: [TicketStatusPoint], onTap: ((String) -> Void)? = nil) {
        self.points = points
        self.onTap = onTap
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
                ChartDashedSilhouette(systemImage: "chart.bar.fill", label: "No ticket status data for this period.")
            } else {
                chart
                    .frame(height: 160)
                    .chartXAxisLabel("Count", alignment: .center)
                    .chartYAxisLabel("Status", position: .leading)
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .foregroundStyle(Color.bizarreOnSurface.opacity(0.85))
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
        .chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { value in
                    guard let status: String = proxy.value(atY: value.location.y) else { return }
                    onTap?(status)
                }
        }
    }

    // MARK: - Legend row

    private var legendRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(points.indices, id: \.self) { idx in
                    let pt = points[idx]
                    let color = Self.statusColors[idx % Self.statusColors.count]
                    HStack(spacing: BrandSpacing.xxs) {
                        Circle().fill(color).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text("\(pt.status) \(pt.count)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(points.map { "\($0.status): \($0.count)" }.joined(separator: ", "))
    }
}

// MARK: - AXChartDescriptor (TicketsByStatus)

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
