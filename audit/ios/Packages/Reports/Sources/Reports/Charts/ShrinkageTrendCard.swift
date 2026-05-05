import SwiftUI
import Charts
import DesignSystem

// MARK: - §15.5 Shrinkage Trend Card
//
// Tracks inventory shrinkage (theft, damage, write-offs) over time.
// Endpoint: GET /api/v1/reports/inventory-shrinkage?from_date=&to_date=
// Server shape:
//   { rows: [{ period: String, shrinkageUnits: Int, shrinkageCostDollars: Double, reason: String? }] }
//   summary: { totalUnits: Int, totalCostDollars: Double, shrinkagePct: Double }
//
// iPhone: stacked BarMark by reason + KPI tiles below.
// iPad: chart (left 60%) + KPI summary (right 40%).

// MARK: - Models

public struct ShrinkagePoint: Decodable, Sendable, Identifiable {
    public let id: String
    /// ISO-8601 date bucket.
    public let period: String
    /// Units lost.
    public let shrinkageUnits: Int
    /// Cost value of lost inventory in dollars.
    public let shrinkageCostDollars: Double
    /// Reason category: "theft" | "damage" | "expiry" | "admin_error" | "other"
    public let reason: String

    public init(period: String, shrinkageUnits: Int,
                shrinkageCostDollars: Double, reason: String) {
        self.id = "\(period)-\(reason)"
        self.period = period
        self.shrinkageUnits = shrinkageUnits
        self.shrinkageCostDollars = shrinkageCostDollars
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.period = (try? c.decode(String.self, forKey: .period)) ?? ""
        self.shrinkageUnits = (try? c.decode(Int.self, forKey: .shrinkageUnits)) ?? 0
        self.shrinkageCostDollars = (try? c.decode(Double.self, forKey: .shrinkageCostDollars)) ?? 0
        self.reason = (try? c.decode(String.self, forKey: .reason)) ?? "other"
        self.id = "\(period)-\(reason)"
    }

    enum CodingKeys: String, CodingKey {
        case period
        case shrinkageUnits       = "shrinkage_units"
        case shrinkageCostDollars = "shrinkage_cost"
        case reason
    }

    var reasonDisplayName: String {
        switch reason {
        case "theft":       return "Theft"
        case "damage":      return "Damage"
        case "expiry":      return "Expiry"
        case "admin_error": return "Admin Error"
        default:            return "Other"
        }
    }

    var reasonColor: Color {
        switch reason {
        case "theft":       return .bizarreError
        case "damage":      return .bizarreWarning
        case "expiry":      return Color(red: 0.6, green: 0.3, blue: 0.8)
        case "admin_error": return .bizarreInfo
        default:            return .bizarreOnSurfaceMuted
        }
    }
}

public struct ShrinkageSummary: Decodable, Sendable {
    public let totalUnits: Int
    public let totalCostDollars: Double
    /// % of total inventory value lost to shrinkage.
    public let shrinkagePct: Double

    public init(totalUnits: Int, totalCostDollars: Double, shrinkagePct: Double) {
        self.totalUnits = totalUnits
        self.totalCostDollars = totalCostDollars
        self.shrinkagePct = shrinkagePct
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.totalUnits = (try? c.decode(Int.self, forKey: .totalUnits)) ?? 0
        self.totalCostDollars = (try? c.decode(Double.self, forKey: .totalCostDollars)) ?? 0
        self.shrinkagePct = (try? c.decode(Double.self, forKey: .shrinkagePct)) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case totalUnits       = "total_units"
        case totalCostDollars = "total_cost"
        case shrinkagePct     = "shrinkage_pct"
    }
}

public struct ShrinkageReport: Decodable, Sendable {
    public let rows: [ShrinkagePoint]
    public let summary: ShrinkageSummary?

    public init(rows: [ShrinkagePoint], summary: ShrinkageSummary? = nil) {
        self.rows = rows
        self.summary = summary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.rows = (try? c.decode([ShrinkagePoint].self, forKey: .rows)) ?? []
        self.summary = try? c.decode(ShrinkageSummary.self, forKey: .summary)
    }

    enum CodingKeys: String, CodingKey { case rows, summary }
}

// MARK: - Card View

public struct ShrinkageTrendCard: View {
    public let report: ShrinkageReport?

    public init(report: ShrinkageReport?) {
        self.report = report
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var rows: [ShrinkagePoint] { report?.rows ?? [] }
    private var summary: ShrinkageSummary? { report?.summary }

    // Unique reason keys for legend + color scale.
    private var reasons: [String] {
        Array(Set(rows.map(\.reason))).sorted()
    }

    public var body: some View {
        if sizeClass == .regular {
            ipadLayout
        } else {
            phoneLayout
        }
    }

    // MARK: - iPhone layout

    private var phoneLayout: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            headerRow
            if rows.isEmpty {
                emptyState
            } else {
                shrinkageChart.frame(height: 180)
                Divider()
                kpiGrid
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - iPad layout (chart left, KPI right)

    private var ipadLayout: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                headerRow
                if rows.isEmpty {
                    emptyState
                } else {
                    shrinkageChart.frame(height: 200)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Period Summary")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityAddTraits(.isHeader)
                kpiGrid
                legendStack
            }
            .frame(width: 200)
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - Chart

    private var shrinkageChart: some View {
        Chart(rows) { point in
            BarMark(
                x: .value("Period", point.period),
                y: .value("Units", point.shrinkageUnits)
            )
            .foregroundStyle(by: .value("Reason", point.reasonDisplayName))
        }
        .chartForegroundStyleScale(
            domain: reasons.map { reasonDisplayName(for: $0) },
            range: reasons.map { reasonColor(for: $0) }
        )
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day(), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text("\(v)u") }
                }
            }
        }
        .chartLegend(.hidden)
        .accessibilityChartDescriptor(ShrinkageChartDescriptor(rows: rows))
        .accessibilityLabel(axLabel)
    }

    // MARK: - KPI tiles

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  spacing: BrandSpacing.sm) {
            kpiTile(label: "Units Lost",
                    value: "\(summary?.totalUnits ?? rows.reduce(0) { $0 + $1.shrinkageUnits })",
                    icon: "minus.circle.fill",
                    color: .bizarreError)
            kpiTile(label: "Cost",
                    value: dollarString(summary?.totalCostDollars ?? rows.reduce(0) { $0 + $1.shrinkageCostDollars }),
                    icon: "dollarsign.circle.fill",
                    color: .bizarreWarning)
            if let pct = summary?.shrinkagePct {
                kpiTile(label: "Shrinkage %",
                        value: String(format: "%.2f%%", pct),
                        icon: "percent",
                        color: pct > 2.0 ? .bizarreError : .bizarreWarning)
                    .gridCellColumns(2)
            }
        }
    }

    private func kpiTile(label: String, value: String,
                         icon: String, color: Color) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(value)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface2,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Legend

    private var legendStack: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            ForEach(reasons, id: \.self) { r in
                HStack(spacing: BrandSpacing.xs) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(reasonColor(for: r))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    Text(reasonDisplayName(for: r))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurface)
                }
            }
        }
    }

    // MARK: - Header / empty / border

    private var headerRow: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Inventory Shrinkage Trend")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 32))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("No shrinkage recorded this period.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrandSpacing.lg)
        .accessibilityLabel("No shrinkage recorded this period")
    }

    private var strokeBorder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
    }

    // MARK: - Helpers

    private func reasonDisplayName(for r: String) -> String {
        rows.first { $0.reason == r }?.reasonDisplayName ?? r.capitalized
    }

    private func reasonColor(for r: String) -> Color {
        rows.first { $0.reason == r }?.reasonColor ?? .bizarreOnSurfaceMuted
    }

    private var axLabel: String {
        let total = rows.reduce(0) { $0 + $1.shrinkageUnits }
        return "Shrinkage trend chart. \(total) total units lost across \(rows.count) periods."
    }

    private func dollarString(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - AX Chart Descriptor

private struct ShrinkageChartDescriptor: AXChartDescriptorRepresentable {
    let rows: [ShrinkagePoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Period",
            categoryOrder: rows.map(\.period)
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Units Lost",
            range: 0...Double(rows.map(\.shrinkageUnits).max() ?? 1),
            gridlinePositions: []
        ) { "\($0) units" }

        let series = AXDataSeriesDescriptor(
            name: "Shrinkage",
            isContinuous: false,
            dataPoints: rows.map { p in
                AXDataPoint(x: p.period, y: Double(p.shrinkageUnits),
                            additionalValues: [],
                            label: "\(p.reasonDisplayName): \(p.shrinkageUnits) units")
            }
        )
        return AXChartDescriptor(title: "Inventory Shrinkage Trend",
                                 summary: "\(rows.count) data points",
                                 xAxis: xAxis, yAxis: yAxis, series: [series])
    }
}
