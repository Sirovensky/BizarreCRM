import SwiftUI
import Charts
import DesignSystem

// MARK: - TicketsByTechPoint
//
// §15.3 — Tickets by tech bar chart.
// Derived from GET /api/v1/reports/employees (reuses EmployeePerf model).

public struct TicketsByTechPoint: Sendable, Identifiable {
    public let id: Int64
    public let techName: String
    /// Number of tickets assigned in the period.
    public let assigned: Int
    /// Number of tickets closed in the period.
    public let closed: Int

    public var closeRate: Double {
        guard assigned > 0 else { return 0 }
        return Double(closed) / Double(assigned) * 100.0
    }

    public init(id: Int64, techName: String, assigned: Int, closed: Int) {
        self.id = id
        self.techName = techName
        self.assigned = assigned
        self.closed = closed
    }

    /// Convenience init from EmployeePerf.
    public init(from perf: EmployeePerf) {
        self.id = perf.id
        self.techName = perf.employeeName
        self.assigned = perf.ticketsAssigned
        self.closed = perf.ticketsClosed
    }
}

// MARK: - TicketsByTechCard

public struct TicketsByTechCard: View {
    public let points: [TicketsByTechPoint]
    public let onTapTech: (Int64) -> Void

    public init(points: [TicketsByTechPoint],
                onTapTech: @escaping (Int64) -> Void = { _ in }) {
        self.points = points
        self.onTapTech = onTapTech
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if points.isEmpty {
                emptyState
            } else {
                chart
                    .frame(height: max(CGFloat(points.count) * 36, 120))
                    .chartXAxisLabel("Tickets", alignment: .center)
                    .accessibilityChartDescriptor(TicketsByTechDescriptor(points: points))
                tapHint
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
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Tickets by Technician")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Grouped BarMark chart

    private var chart: some View {
        Chart {
            ForEach(points) { pt in
                // Assigned bar (lighter)
                BarMark(
                    x: .value("Count", pt.assigned),
                    y: .value("Tech", pt.techName)
                )
                .foregroundStyle(Color.bizarreOrange.opacity(0.35))
                .cornerRadius(DesignTokens.Radius.xxs)
                .annotation(position: .trailing) {
                    Text("\(pt.assigned)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                // Closed bar (solid)
                BarMark(
                    x: .value("Count", pt.closed),
                    y: .value("Tech", pt.techName)
                )
                .foregroundStyle(Color.bizarreOrange)
                .cornerRadius(DesignTokens.Radius.xxs)
            }
        }
        .chartForegroundStyleScale([
            "Assigned": Color.bizarreOrange.opacity(0.35),
            "Closed": Color.bizarreOrange
        ])
        .chartOverlay { proxy in tapOverlay(proxy: proxy) }
        .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.smooth),
                   value: points.count)
    }

    // MARK: - Tap overlay (drill to per-tech detail)

    private func tapOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onTapGesture { location in
                    guard let techName: String = proxy.value(
                        atY: location.y - geo.frame(in: .local).minY
                    ) else { return }
                    if let pt = points.first(where: { $0.techName == techName }) {
                        onTapTech(pt.id)
                    }
                }
        }
    }

    // MARK: - Tap hint

    private var tapHint: some View {
        Text("Tap a bar to view technician details")
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .accessibilityHidden(true)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No Technician Ticket Data",
            systemImage: "wrench.and.screwdriver",
            description: Text("No tickets assigned to technicians in this period.")
        )
    }
}

// MARK: - Per-tech detail sheet (§15.4 drill)

public struct TechDetailSheet: View {
    public let row: TechnicianPerfRow

    public init(row: TechnicianPerfRow) {
        self.row = row
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.md) {
                        heroTile
                        statsGrid
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle(row.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Hero tile

    private var heroTile: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name)
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(String(format: "%.0f%% close rate", row.closeRate))
                        .font(.brandBodyMedium())
                        .foregroundStyle(row.closeRate >= 80 ? Color.bizarreSuccess : Color.bizarreWarning)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name): \(String(format: "%.0f", row.closeRate)) percent close rate")
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: BrandSpacing.md
        ) {
            statTile(
                label: "Tickets Assigned",
                value: "\(row.ticketsAssigned)",
                icon: "ticket",
                color: .bizarreTeal
            )
            statTile(
                label: "Tickets Closed",
                value: "\(row.ticketsClosed)",
                icon: "checkmark.circle.fill",
                color: .bizarreSuccess
            )
            statTile(
                label: "Revenue",
                value: formatCurrency(row.revenueGenerated),
                icon: "dollarsign.circle.fill",
                color: .bizarreOrange
            )
            statTile(
                label: "Commission",
                value: formatCurrency(row.commissionDollars),
                icon: "percent",
                color: .bizarreMagenta
            )
            statTile(
                label: "Hours Worked",
                value: String(format: "%.1f h", row.hoursWorked),
                icon: "clock.fill",
                color: .bizarreWarning
            )
            statTile(
                label: "Close Rate",
                value: String(format: "%.0f%%", row.closeRate),
                icon: "chart.bar.fill",
                color: row.closeRate >= 80 ? .bizarreSuccess : .bizarreWarning
            )
        }
    }

    private func statTile(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Spacer()
            }
            Text(value)
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - AXChartDescriptor

private struct TicketsByTechDescriptor: AXChartDescriptorRepresentable {
    let points: [TicketsByTechPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Tickets",
            range: 0...Double(points.map(\.assigned).max() ?? 1),
            gridlinePositions: []
        ) { "\(Int($0))" }
        let yAxis = AXCategoricalDataAxisDescriptor(
            title: "Technician",
            categoryOrder: points.map(\.techName)
        )
        let assigned = AXDataSeriesDescriptor(
            name: "Assigned", isContinuous: false,
            dataPoints: points.map { AXDataPoint(x: Double($0.assigned), y: 0, label: $0.techName) }
        )
        let closed = AXDataSeriesDescriptor(
            name: "Closed", isContinuous: false,
            dataPoints: points.map { AXDataPoint(x: Double($0.closed), y: 0, label: $0.techName) }
        )
        return AXChartDescriptor(
            title: "Tickets by Technician",
            summary: "Horizontal bar chart showing assigned and closed tickets per technician",
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [assigned, closed]
        )
    }
}
