import SwiftUI
import Charts
import DesignSystem

// MARK: - TicketDayPoint
//
// §15.3 — Opened vs closed per day (stacked bar).
// Derived from GET /api/v1/reports/tickets with daily breakdown.

public struct TicketDayPoint: Codable, Sendable, Identifiable {
    public let id: String
    /// ISO-8601 date or period string.
    public let date: String
    public let opened: Int
    public let closed: Int
    /// Close rate for the day (0.0–1.0). nil when opened == 0.
    public var closeRate: Double? {
        guard opened > 0 else { return nil }
        return Double(closed) / Double(opened)
    }
    /// Avg turnaround hours for the day (server-derived).
    public let avgTurnaroundHours: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case opened
        case closed
        case avgTurnaroundHours = "avg_turnaround_hours"
    }

    public init(date: String, opened: Int, closed: Int,
                avgTurnaroundHours: Double? = nil) {
        self.id = date
        self.date = date
        self.opened = opened
        self.closed = closed
        self.avgTurnaroundHours = avgTurnaroundHours
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.date = (try? c.decode(String.self, forKey: .date)) ?? ""
        self.id = self.date
        self.opened = (try? c.decode(Int.self, forKey: .opened)) ?? 0
        self.closed = (try? c.decode(Int.self, forKey: .closed)) ?? 0
        self.avgTurnaroundHours = try? c.decode(Double.self, forKey: .avgTurnaroundHours)
    }
}

// MARK: - TicketsTrendCard
//
// Stacked BarMark: opened (teal, bottom) + closed (orange, top).
// iPhone: single-column scroll. iPad: chart + KPI side panel.

public struct TicketsTrendCard: View {
    public let points: [TicketDayPoint]
    /// Overall close rate across the period (nil when no data).
    public var overallCloseRate: Double? {
        let totalOpened = points.reduce(0) { $0 + $1.opened }
        let totalClosed = points.reduce(0) { $0 + $1.closed }
        guard totalOpened > 0 else { return nil }
        return Double(totalClosed) / Double(totalOpened) * 100.0
    }
    /// Avg turnaround hours across the period.
    public var avgTurnaround: Double? {
        let values = points.compactMap(\.avgTurnaroundHours)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public init(points: [TicketDayPoint]) {
        self.points = points
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if points.isEmpty {
                emptyState
            } else if sizeClass == .regular {
                ipadLayout
            } else {
                phoneLayout
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
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.bizarreTeal)
                .accessibilityHidden(true)
            Text("Tickets: Opened vs Closed")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Phone layout

    private var phoneLayout: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            stackedBarChart
                .frame(height: 160)
                .chartXAxisLabel("Date", alignment: .center)
                .chartYAxisLabel("Count", position: .leading)
                .accessibilityChartDescriptor(TicketsTrendDescriptor(points: points))
            legend
            kpiRow
        }
    }

    // MARK: - iPad layout

    private var ipadLayout: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            stackedBarChart
                .frame(height: 200)
                .chartXAxisLabel("Date", alignment: .center)
                .chartYAxisLabel("Count", position: .leading)
                .accessibilityChartDescriptor(TicketsTrendDescriptor(points: points))
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                legend
                kpiColumn
            }
            .frame(minWidth: 130, maxWidth: 160)
        }
    }

    // MARK: - Stacked bar chart

    private var stackedBarChart: some View {
        Chart {
            ForEach(points) { pt in
                // Opened — bottom layer
                BarMark(
                    x: .value("Date", pt.date),
                    y: .value("Opened", pt.opened)
                )
                .foregroundStyle(by: .value("Type", "Opened"))
                .cornerRadius(DesignTokens.Radius.xxs)

                // Closed — stacked on top
                BarMark(
                    x: .value("Date", pt.date),
                    y: .value("Closed", pt.closed)
                )
                .foregroundStyle(by: .value("Type", "Closed"))
                .cornerRadius(DesignTokens.Radius.xxs)
            }
        }
        .chartForegroundStyleScale([
            "Opened": Color.bizarreTeal,
            "Closed": Color.bizarreOrange
        ])
        .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.smooth),
                   value: points.count)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: BrandSpacing.md) {
            legendDot(color: .bizarreTeal, label: "Opened")
            legendDot(color: .bizarreOrange, label: "Closed")
        }
        .font(.brandLabelSmall())
        .foregroundStyle(.bizarreOnSurfaceMuted)
        .accessibilityHidden(true)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: BrandSpacing.xxs) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: - KPI row (phone)

    private var kpiRow: some View {
        HStack(spacing: BrandSpacing.md) {
            if let rate = overallCloseRate {
                kpiTile(label: "Close Rate", value: String(format: "%.0f%%", rate),
                        color: rate >= 80 ? .bizarreSuccess : .bizarreWarning)
            }
            if let avg = avgTurnaround {
                kpiTile(label: "Avg Turnaround", value: formatHours(avg),
                        color: .bizarreTeal)
            }
        }
    }

    // MARK: - KPI column (iPad)

    private var kpiColumn: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Summary")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
            if let rate = overallCloseRate {
                kpiTile(label: "Close Rate",
                        value: String(format: "%.0f%%", rate),
                        color: rate >= 80 ? .bizarreSuccess : .bizarreWarning)
            }
            if let avg = avgTurnaround {
                kpiTile(label: "Avg Turnaround",
                        value: formatHours(avg),
                        color: .bizarreTeal)
            }
            let totalOpened = points.reduce(0) { $0 + $1.opened }
            let totalClosed = points.reduce(0) { $0 + $1.closed }
            kpiTile(label: "Total Opened", value: "\(totalOpened)", color: .bizarreTeal)
            kpiTile(label: "Total Closed", value: "\(totalClosed)", color: .bizarreOrange)
        }
    }

    private func kpiTile(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value)
                .font(.brandTitleSmall())
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No Ticket Trend Data",
            systemImage: "chart.bar.fill",
            description: Text("No opened/closed ticket data for this period.")
        )
    }

    // MARK: - Helpers

    private func formatHours(_ h: Double) -> String {
        if h < 1 { return String(format: "%.0fm", h * 60) }
        if h < 24 { return String(format: "%.1fh", h) }
        return String(format: "%.1fd", h / 24)
    }
}

// MARK: - AXChartDescriptor

private struct TicketsTrendDescriptor: AXChartDescriptorRepresentable {
    let points: [TicketDayPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Date",
            categoryOrder: points.map(\.date)
        )
        let maxVal = Double(max(
            points.map(\.opened).max() ?? 0,
            points.map(\.closed).max() ?? 0
        ))
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Count", range: 0...max(maxVal, 1), gridlinePositions: []
        ) { "\(Int($0))" }

        let opened = AXDataSeriesDescriptor(
            name: "Opened", isContinuous: false,
            dataPoints: points.map { AXDataPoint(x: $0.date, y: Double($0.opened)) }
        )
        let closed = AXDataSeriesDescriptor(
            name: "Closed", isContinuous: false,
            dataPoints: points.map { AXDataPoint(x: $0.date, y: Double($0.closed)) }
        )
        return AXChartDescriptor(
            title: "Tickets Opened vs Closed",
            summary: "Stacked bar chart of tickets opened and closed per period",
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [opened, closed]
        )
    }
}
