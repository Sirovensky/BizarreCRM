import SwiftUI
import Charts
import DesignSystem

// MARK: - RevenueChartCard

public struct RevenueChartCard: View {
    public let points: [RevenuePoint]
    public let onDrillThrough: (RevenuePoint) -> Void

    public init(points: [RevenuePoint], onDrillThrough: @escaping (RevenuePoint) -> Void) {
        self.points = points
        self.onDrillThrough = onDrillThrough
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPoint: RevenuePoint?

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            chart
                .frame(height: 180)
                .chartXAxisLabel("Date", alignment: .center)
                .chartYAxisLabel("Revenue ($K)", position: .leading)
                .accessibilityChartDescriptor(RevenueChartDescriptor(points: points))
                .chartOverlay { proxy in
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
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

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
            if let pt = selectedPoint {
                Text(pt.amountDollars, format: .currency(code: "USD"))
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreTeal)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Revenue area chart. Tap a data point to drill through.")
    }

    @ViewBuilder
    private var chart: some View {
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

    private var emptyState: some View {
        ContentUnavailableView("No Revenue Data",
                               systemImage: "chart.line.uptrend.xyaxis",
                               description: Text("No revenue data for this period."))
    }
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
