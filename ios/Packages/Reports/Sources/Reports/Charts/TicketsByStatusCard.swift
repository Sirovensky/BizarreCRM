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
                emptyState
            } else {
                chart
                    .frame(height: 160)
                    .chartXAxisLabel("Count", alignment: .center)
                    .chartYAxisLabel("Status", position: .leading)
                    .accessibilityChartDescriptor(TicketStatusChartDescriptor(points: points))
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
