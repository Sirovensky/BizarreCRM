import SwiftUI
import Charts
import DesignSystem

// MARK: - TicketsByTechCard
//
// §91.11 — horizontal bar chart of tickets closed per technician.
// Data source: EmployeePerf rows from GET /api/v1/reports/employees.
// Supports tap interaction via .chartGesture → onTap callback.

public struct TicketsByTechCard: View {
    public let employees: [EmployeePerf]
    public let maxRows: Int
    /// Called when the user taps a bar; receives the tapped technician name.
    public let onTap: ((String) -> Void)?

    public init(employees: [EmployeePerf],
                maxRows: Int = 8,
                onTap: ((String) -> Void)? = nil) {
        self.employees = employees
        self.maxRows = maxRows
        self.onTap = onTap
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var topTechs: [EmployeePerf] {
        Array(employees.sorted { $0.ticketsClosed > $1.ticketsClosed }.prefix(maxRows))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if topTechs.isEmpty {
                ChartDashedSilhouette(systemImage: "wrench.and.screwdriver", label: "No technician ticket data for this period.")
            } else {
                chart
                    .frame(height: max(140, Double(topTechs.count) * 28))
                    .chartXAxisLabel("Tickets Closed", alignment: .center)
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .foregroundStyle(Color.bizarreOnSurface.opacity(0.85))
                        }
                    }
                    .accessibilityChartDescriptor(TicketsByTechDescriptor(employees: topTechs))
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

    // MARK: - Card header

    private var cardHeader: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(.bizarreTeal)
                .accessibilityHidden(true)
            Text("Tickets by Tech")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Text("Closed")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Bar chart

    private var chart: some View {
        Chart(topTechs) { emp in
            BarMark(
                x: .value("Tickets Closed", emp.ticketsClosed),
                y: .value("Technician", emp.employeeName)
            )
            .foregroundStyle(Color.bizarreTeal.opacity(0.75))
            .cornerRadius(DesignTokens.Radius.xs)
            .annotation(position: .trailing) {
                Text("\(emp.ticketsClosed)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.smooth), value: topTechs.count)
        .chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { value in
                    guard let name: String = proxy.value(atY: value.location.y) else { return }
                    onTap?(name)
                }
        }
    }

    // MARK: - Legend row

    private var legendRow: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Circle().fill(Color.bizarreTeal.opacity(0.75)).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("Tickets closed")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: tickets closed per technician")
    }
}

// MARK: - AXChartDescriptor

private struct TicketsByTechDescriptor: AXChartDescriptorRepresentable {
    let employees: [EmployeePerf]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Technician",
            categoryOrder: employees.map(\.employeeName)
        )
        let maxVal = Double(employees.map(\.ticketsClosed).max() ?? 1)
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Tickets Closed",
            range: 0...maxVal,
            gridlinePositions: []
        ) { "\(Int($0))" }
        let series = AXDataSeriesDescriptor(
            name: "Tickets by Tech",
            isContinuous: false,
            dataPoints: employees.map { emp in
                AXDataPoint(x: emp.employeeName, y: Double(emp.ticketsClosed))
            }
        )
        return AXChartDescriptor(
            title: "Tickets by Technician",
            summary: "Horizontal bar chart showing tickets closed per technician",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
