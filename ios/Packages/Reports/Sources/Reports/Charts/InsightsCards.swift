import SwiftUI
import Core
import Charts
import DesignSystem

// MARK: - §15.7 Insight Models
//
// Models and chart cards for warranty claims trend, device-models repaired,
// parts usage, technician hours, stalled tickets, and customer acquisition/churn.

// MARK: - WarrantyClaimsPoint

public struct WarrantyClaimsPoint: Decodable, Sendable, Identifiable {
    public let id: String
    /// ISO-8601 date bucket (day/week/month).
    public let period: String
    /// Number of warranty claims opened in this period.
    public let claimsCount: Int
    /// Number resolved/closed.
    public let resolvedCount: Int
    /// Average days to resolve.
    public let avgResolutionDays: Double

    public var unresolvedCount: Int { max(0, claimsCount - resolvedCount) }

    enum CodingKeys: String, CodingKey {
        case period
        case claimsCount    = "claims_count"
        case resolvedCount  = "resolved_count"
        case avgResolutionDays = "avg_resolution_days"
    }

    public init(period: String, claimsCount: Int, resolvedCount: Int,
                avgResolutionDays: Double) {
        self.id = period
        self.period = period
        self.claimsCount = claimsCount
        self.resolvedCount = resolvedCount
        self.avgResolutionDays = avgResolutionDays
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.period = (try? c.decode(String.self, forKey: .period)) ?? ""
        self.id = period
        self.claimsCount = (try? c.decode(Int.self, forKey: .claimsCount)) ?? 0
        self.resolvedCount = (try? c.decode(Int.self, forKey: .resolvedCount)) ?? 0
        self.avgResolutionDays = (try? c.decode(Double.self, forKey: .avgResolutionDays)) ?? 0
    }
}

// MARK: - DeviceModelRepaired

public struct DeviceModelRepaired: Decodable, Sendable, Identifiable {
    public let id: String
    public let model: String
    public let repairCount: Int
    /// Revenue from repairs for this model in dollars.
    public let revenueDollars: Double

    enum CodingKeys: String, CodingKey {
        case model
        case repairCount  = "repair_count"
        case revenue
    }

    public init(model: String, repairCount: Int, revenueDollars: Double) {
        self.id = model
        self.model = model
        self.repairCount = repairCount
        self.revenueDollars = revenueDollars
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.model = (try? c.decode(String.self, forKey: .model)) ?? ""
        self.id = model
        self.repairCount = (try? c.decode(Int.self, forKey: .repairCount)) ?? 0
        self.revenueDollars = (try? c.decode(Double.self, forKey: .revenue)) ?? 0
    }
}

// MARK: - PartUsageRow

public struct PartUsageRow: Decodable, Sendable, Identifiable {
    public let id: String
    public let partName: String
    public let sku: String?
    /// Units consumed in the period.
    public let unitsUsed: Int
    /// Total cost of consumption in dollars.
    public let totalCostDollars: Double

    enum CodingKeys: String, CodingKey {
        case partName  = "part_name"
        case sku
        case unitsUsed = "units_used"
        case totalCost = "total_cost"
    }

    public init(partName: String, sku: String?, unitsUsed: Int, totalCostDollars: Double) {
        self.id = partName
        self.partName = partName
        self.sku = sku
        self.unitsUsed = unitsUsed
        self.totalCostDollars = totalCostDollars
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.partName = (try? c.decode(String.self, forKey: .partName)) ?? ""
        self.id = partName
        self.sku = try? c.decode(String.self, forKey: .sku)
        self.unitsUsed = (try? c.decode(Int.self, forKey: .unitsUsed)) ?? 0
        self.totalCostDollars = (try? c.decode(Double.self, forKey: .totalCost)) ?? 0
    }
}

// MARK: - TechHoursRow

public struct TechHoursRow: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let techName: String
    /// Billable hours in the period.
    public let billableHours: Double
    /// Non-billable hours.
    public let nonBillableHours: Double
    /// Total hours = billable + non-billable.
    public var totalHours: Double { billableHours + nonBillableHours }
    /// Utilization rate: billable / total * 100.
    public var utilizationPct: Double {
        guard totalHours > 0 else { return 0 }
        return (billableHours / totalHours) * 100.0
    }

    enum CodingKeys: String, CodingKey {
        case id
        case techName       = "tech_name"
        case billableHours  = "billable_hours"
        case nonBillableHours = "non_billable_hours"
    }

    public init(id: Int64, techName: String, billableHours: Double, nonBillableHours: Double) {
        self.id = id
        self.techName = techName
        self.billableHours = billableHours
        self.nonBillableHours = nonBillableHours
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        self.techName = (try? c.decode(String.self, forKey: .techName)) ?? ""
        self.billableHours = (try? c.decode(Double.self, forKey: .billableHours)) ?? 0
        self.nonBillableHours = (try? c.decode(Double.self, forKey: .nonBillableHours)) ?? 0
    }
}

// MARK: - StalledTicketsSummary

public struct StalledTicketsSummary: Decodable, Sendable {
    public let stalledCount: Int
    public let overdueCount: Int
    public let avgDaysStalled: Double
    public let topStalledTech: String?

    enum CodingKeys: String, CodingKey {
        case stalledCount   = "stalled_count"
        case overdueCount   = "overdue_count"
        case avgDaysStalled = "avg_days_stalled"
        case topStalledTech = "top_stalled_tech"
    }

    public init(stalledCount: Int, overdueCount: Int,
                avgDaysStalled: Double, topStalledTech: String? = nil) {
        self.stalledCount = stalledCount
        self.overdueCount = overdueCount
        self.avgDaysStalled = avgDaysStalled
        self.topStalledTech = topStalledTech
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.stalledCount = (try? c.decode(Int.self, forKey: .stalledCount)) ?? 0
        self.overdueCount = (try? c.decode(Int.self, forKey: .overdueCount)) ?? 0
        self.avgDaysStalled = (try? c.decode(Double.self, forKey: .avgDaysStalled)) ?? 0
        self.topStalledTech = try? c.decode(String.self, forKey: .topStalledTech)
    }
}

// MARK: - CustomerAcquisitionChurn

public struct CustomerAcquisitionChurn: Decodable, Sendable {
    /// New customers acquired this period.
    public let newCustomers: Int
    /// Customers who haven't purchased since >90d (churned).
    public let churnedCustomers: Int
    /// Returning customers (purchased after gap > 30d).
    public let returningCustomers: Int
    /// Net growth = new - churned.
    public var netGrowth: Int { newCustomers - churnedCustomers }
    /// Churn rate % = churned / (new + churned) * 100.
    public var churnRatePct: Double {
        let base = newCustomers + churnedCustomers
        guard base > 0 else { return 0 }
        return Double(churnedCustomers) / Double(base) * 100.0
    }

    enum CodingKeys: String, CodingKey {
        case newCustomers      = "new_customers"
        case churnedCustomers  = "churned_customers"
        case returningCustomers = "returning_customers"
    }

    public init(newCustomers: Int, churnedCustomers: Int, returningCustomers: Int) {
        self.newCustomers = newCustomers
        self.churnedCustomers = churnedCustomers
        self.returningCustomers = returningCustomers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.newCustomers = (try? c.decode(Int.self, forKey: .newCustomers)) ?? 0
        self.churnedCustomers = (try? c.decode(Int.self, forKey: .churnedCustomers)) ?? 0
        self.returningCustomers = (try? c.decode(Int.self, forKey: .returningCustomers)) ?? 0
    }
}

// MARK: - WarrantyClaimsTrendCard (§15.7)

public struct WarrantyClaimsTrendCard: View {
    public let points: [WarrantyClaimsPoint]

    public init(points: [WarrantyClaimsPoint]) {
        self.points = points
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if points.isEmpty {
                emptyState
            } else {
                kpiRow
                chart
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private var cardHeader: some View {
        HStack {
            Image(systemName: "shield.checkered")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Warranty Claims Trend")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var kpiRow: some View {
        HStack(spacing: BrandSpacing.xl) {
            let totalClaims = points.reduce(0) { $0 + $1.claimsCount }
            let avgDays = points.isEmpty ? 0.0
                : points.reduce(0.0) { $0 + $1.avgResolutionDays } / Double(points.count)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(totalClaims)")
                    .font(.brandHeadlineLarge()).monospacedDigit()
                    .foregroundStyle(.bizarreOnSurface)
                Text("total claims")
                    .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("\(totalClaims) total warranty claims")
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f d", avgDays))
                    .font(.brandHeadlineLarge()).monospacedDigit()
                    .foregroundStyle(.bizarreOnSurface)
                Text("avg resolution")
                    .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel(String(format: "Average resolution %.1f days", avgDays))
            Spacer()
        }
    }

    private var chart: some View {
        Chart(points) { pt in
            BarMark(
                x: .value("Period", pt.period),
                y: .value("Claims", pt.claimsCount),
                stacking: .normalized
            )
            .foregroundStyle(Color.bizarreError.opacity(0.7))
            .accessibilityLabel("\(pt.period): \(pt.claimsCount) claims")
            BarMark(
                x: .value("Period", pt.period),
                y: .value("Resolved", pt.resolvedCount),
                stacking: .normalized
            )
            .foregroundStyle(Color.bizarreSuccess.opacity(0.8))
        }
        .chartXAxis(.hidden)
        .frame(height: 80)
        .accessibilityChartDescriptor(WarrantyClaimsChartAX(points: points))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            // Sparkline outline placeholder — communicates shape even when no data
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(
                        Color.bizarreOutline.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                    .frame(height: 56)
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.5))
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text("No claims in selected period")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .accessibilityLabel("No warranty claims data in the selected period")
    }
}

private struct WarrantyClaimsChartAX: AXChartDescriptorRepresentable {
    let points: [WarrantyClaimsPoint]
    func makeChartDescriptor() -> AXChartDescriptor {
        let series = AXDataSeriesDescriptor(name: "Claims", isContinuous: false,
            dataPoints: points.map {
                AXDataPoint(x: $0.period, y: Double($0.claimsCount))
            })
        return AXChartDescriptor(title: "Warranty Claims Trend",
                                  summary: "\(points.reduce(0) { $0 + $1.claimsCount }) total claims",
                                  xAxis: AXCategoricalDataAxisDescriptor(title: "Period",
                                                                          categoryOrder: points.map(\.period)),
                                  yAxis: AXNumericDataAxisDescriptor(title: "Count",
                                                                      range: 0...Double(points.map(\.claimsCount).max() ?? 1),
                                                                      gridlinePositions: [],
                                                                      valueDescriptionProvider: { String(format: "%.0f", $0) }),
                                  series: [series])
    }
}

// MARK: - DeviceModelsRepairedCard (§15.7)

public struct DeviceModelsRepairedCard: View {
    public let rows: [DeviceModelRepaired]

    public init(rows: [DeviceModelRepaired]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            if rows.isEmpty {
                Text("No device repair data in selected period")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No device repair data")
            } else {
                chart
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack {
            Image(systemName: "iphone.and.arrow.forward")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Device Models Repaired")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var chart: some View {
        // Sort descending by frequency so highest-volume model appears at top
        let topRows = Array(rows.sorted { $0.repairCount > $1.repairCount }.prefix(8))
        return Chart(topRows) { row in
            BarMark(
                x: .value("Repairs", row.repairCount),
                y: .value("Model", row.model)
            )
            .foregroundStyle(Color.bizarreOrange.opacity(0.8))
            .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                Text("\(row.repairCount)")
                    .font(.brandLabelSmall()).monospacedDigit()
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("\(row.model): \(row.repairCount) repairs")
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .frame(height: min(CGFloat(topRows.count) * 28 + 20, 220))
        .accessibilityChartDescriptor(DeviceModelsChartAX(rows: topRows))
    }
}

private struct DeviceModelsChartAX: AXChartDescriptorRepresentable {
    let rows: [DeviceModelRepaired]
    func makeChartDescriptor() -> AXChartDescriptor {
        let series = AXDataSeriesDescriptor(name: "Repairs", isContinuous: false,
            dataPoints: rows.map { AXDataPoint(x: $0.model, y: Double($0.repairCount)) })
        return AXChartDescriptor(title: "Device Models Repaired",
                                  summary: "\(rows.reduce(0) { $0 + $1.repairCount }) total repairs",
                                  xAxis: AXCategoricalDataAxisDescriptor(title: "Model",
                                                                          categoryOrder: rows.map(\.model)),
                                  yAxis: AXNumericDataAxisDescriptor(title: "Count",
                                                                      range: 0...Double(rows.map(\.repairCount).max() ?? 1),
                                                                      gridlinePositions: [],
                                                                      valueDescriptionProvider: { String(format: "%.0f", $0) }),
                                  series: [series])
    }
}

// MARK: - PartsUsageCard (§15.7)

public struct PartsUsageCard: View {
    public let rows: [PartUsageRow]

    public init(rows: [PartUsageRow]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            if rows.isEmpty {
                Text("No parts usage data in selected period")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No parts usage data")
            } else {
                kpiBand
                partsList
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack {
            Image(systemName: "wrench.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Parts Usage Analysis")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var kpiBand: some View {
        let totalUnits = rows.reduce(0) { $0 + $1.unitsUsed }
        let totalCost = rows.reduce(0.0) { $0 + $1.totalCostDollars }
        return HStack(spacing: BrandSpacing.xl) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(totalUnits)")
                    .font(.brandHeadlineLarge()).monospacedDigit()
                    .foregroundStyle(.bizarreOnSurface)
                Text("units consumed")
                    .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("\(totalUnits) total units consumed")
            VStack(alignment: .leading, spacing: 2) {
                Text(totalCost, format: .currency(code: "USD"))
                    .font(.brandHeadlineLarge()).monospacedDigit()
                    .foregroundStyle(.bizarreOnSurface)
                Text("total cost")
                    .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel(String(format: "Total cost $%.2f", totalCost))
            Spacer()
        }
    }

    private var partsList: some View {
        let topParts = Array(rows.sorted { $0.unitsUsed > $1.unitsUsed }.prefix(5))
        return VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            ForEach(topParts) { part in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(part.partName)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        if let sku = part.sku {
                            Text("SKU: \(sku)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(part.unitsUsed) units")
                            .font(.brandLabelLarge()).monospacedDigit()
                            .foregroundStyle(.bizarreOnSurface)
                        Text(part.totalCostDollars, format: .currency(code: "USD"))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(part.partName): \(part.unitsUsed) units, cost \(String(format: "$%.2f", part.totalCostDollars))")
                if part.id != topParts.last?.id {
                    Divider()
                }
            }
        }
    }
}

// MARK: - TechHoursCard (§15.7)

public struct TechHoursCard: View {
    public let rows: [TechHoursRow]

    public init(rows: [TechHoursRow]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            if rows.isEmpty {
                Text("No hours data in selected period")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No hours data")
            } else {
                chart
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack {
            Image(systemName: "clock.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Technician Hours Worked")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var chart: some View {
        Chart(rows) { row in
            BarMark(
                x: .value("Billable", row.billableHours),
                y: .value("Tech", row.techName),
                stacking: .standard
            )
            .foregroundStyle(Color.bizarreSuccess.opacity(0.8))
            .accessibilityLabel("\(row.techName): \(String(format: "%.1f", row.billableHours)) billable hours")
            BarMark(
                x: .value("Non-billable", row.nonBillableHours),
                y: .value("Tech", row.techName),
                stacking: .standard
            )
            .foregroundStyle(Color.bizarreOutline.opacity(0.5))
            .accessibilityLabel("\(row.techName): \(String(format: "%.1f", row.nonBillableHours)) non-billable hours")
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%.0fh", d)) } }
            }
        }
        .frame(height: min(CGFloat(rows.count) * 32 + 24, 240))
        .accessibilityChartDescriptor(TechHoursChartAX(rows: rows))
    }
}

private struct TechHoursChartAX: AXChartDescriptorRepresentable {
    let rows: [TechHoursRow]
    func makeChartDescriptor() -> AXChartDescriptor {
        let billable = AXDataSeriesDescriptor(name: "Billable", isContinuous: false,
            dataPoints: rows.map { AXDataPoint(x: $0.techName, y: $0.billableHours) })
        let nonBillable = AXDataSeriesDescriptor(name: "Non-billable", isContinuous: false,
            dataPoints: rows.map { AXDataPoint(x: $0.techName, y: $0.nonBillableHours) })
        let maxHours = rows.map(\.totalHours).max() ?? 1
        return AXChartDescriptor(
            title: "Technician Hours Worked",
            summary: "\(rows.reduce(0.0) { $0 + $1.totalHours }) total hours across \(rows.count) techs",
            xAxis: AXCategoricalDataAxisDescriptor(title: "Technician", categoryOrder: rows.map(\.techName)),
            yAxis: AXNumericDataAxisDescriptor(title: "Hours",
                                               range: 0...maxHours,
                                               gridlinePositions: [],
                                               valueDescriptionProvider: { String(format: "%.1f", $0) }),
            series: [billable, nonBillable]
        )
    }
}

// MARK: - StalledTicketsCard (§15.7)

public struct StalledTicketsCard: View {
    public let summary: StalledTicketsSummary?

    public init(summary: StalledTicketsSummary?) {
        self.summary = summary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            if let s = summary {
                content(s)
            } else {
                skeletonState
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack {
            Image(systemName: "hourglass.bottomhalf.filled")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            Text("Stalled & Overdue Tickets")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func content(_ s: StalledTicketsSummary) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            HStack(spacing: BrandSpacing.xl) {
                kpiTile(value: "\(s.stalledCount)", label: "stalled",
                        color: s.stalledCount > 0 ? .bizarreWarning : .bizarreSuccess)
                kpiTile(value: "\(s.overdueCount)", label: "overdue",
                        color: s.overdueCount > 0 ? .bizarreError : .bizarreSuccess)
                kpiTile(value: String(format: "%.1f d", s.avgDaysStalled),
                        label: "avg stall", color: .bizarreOnSurface)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(s.stalledCount) stalled, \(s.overdueCount) overdue, average \(String(format: "%.1f", s.avgDaysStalled)) days stalled")

            if let tech = s.topStalledTech {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "person.badge.clock")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Most stalled: \(tech)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Most stalled technician: \(tech)")
            }
        }
    }

    private func kpiTile(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.brandHeadlineLarge()).monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var skeletonState: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.bizarreSurface2).frame(height: 20)
            }
        }
        .accessibilityLabel("Stalled tickets data loading")
    }
}

// MARK: - CustomerAcquisitionChurnCard (§15.7)

public struct CustomerAcquisitionChurnCard: View {
    public let data: CustomerAcquisitionChurn?

    public init(data: CustomerAcquisitionChurn?) {
        self.data = data
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            if let d = data {
                content(d)
            } else {
                skeletonState
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack {
            Image(systemName: "person.2.wave.2.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Customer Acquisition & Churn")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func content(_ d: CustomerAcquisitionChurn) -> some View {
        // When all three values are zero, render a single aggregate empty state
        // instead of three colored zeros which create misleading visual noise.
        if d.newCustomers == 0 && d.churnedCustomers == 0 && d.returningCustomers == 0 {
            return AnyView(allZeroState)
        }
        return AnyView(
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                // KPI row
                HStack(spacing: BrandSpacing.lg) {
                    kpiTile(value: "+\(d.newCustomers)", label: "new", color: .bizarreSuccess)
                    kpiTile(value: "-\(d.churnedCustomers)", label: "churned", color: .bizarreError)
                    kpiTile(value: "\(d.returningCustomers)", label: "returning", color: .bizarreOrange)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(d.newCustomers) new, \(d.churnedCustomers) churned, \(d.returningCustomers) returning customers")

                // Net growth chip
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: d.netGrowth >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .foregroundStyle(d.netGrowth >= 0 ? Color.bizarreSuccess : Color.bizarreError)
                        .accessibilityHidden(true)
                    Text("Net: \(d.netGrowth >= 0 ? "+" : "")\(d.netGrowth) customers")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text(String(format: "%.1f%% churn rate", d.churnRatePct))
                        .font(.brandLabelLarge())
                        .foregroundStyle(d.churnRatePct > 15 ? Color.bizarreError : Color.bizarreWarning)
                }
                .accessibilityLabel("Net growth \(d.netGrowth), churn rate \(String(format: "%.1f%%", d.churnRatePct))")
            }
        )
    }

    private var allZeroState: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "person.2.slash")
                .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.5))
                .imageScale(.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("No customer activity yet")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Acquisition and churn data will appear once customers are recorded")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityLabel("No customer activity in selected period. Acquisition and churn data will appear once customers are recorded.")
    }

    private func kpiTile(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.brandHeadlineLarge()).monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var skeletonState: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.bizarreSurface2).frame(height: 20)
            }
        }
        .accessibilityLabel("Customer acquisition data loading")
    }
}
