import SwiftUI
import Core
import Charts
import DesignSystem

// MARK: - §15.9 Built-in BI Report Models and Cards
//
// Revenue/margin by category/tech/customer segment,
// repeat customer rate + time-to-repeat, avg ticket value trend,
// conversion funnel (lead→estimate→ticket→invoice→paid),
// labor utilization by tech.

// MARK: - RevenueByCategoryRow

public struct RevenueByCategoryRow: Decodable, Sendable, Identifiable {
    public let id: String
    /// Category name (e.g. "Screen Repair", "Battery", "Accessories").
    public let category: String
    /// Revenue in dollars.
    public let revenueDollars: Double
    /// Cost of goods sold in dollars (for margin calc).
    public let cogsDollars: Double
    public var grossMarginPct: Double {
        guard revenueDollars > 0 else { return 0 }
        return ((revenueDollars - cogsDollars) / revenueDollars) * 100.0
    }

    enum CodingKeys: String, CodingKey {
        case category
        case revenue
        case cogs
    }

    public init(category: String, revenueDollars: Double, cogsDollars: Double) {
        self.id = category
        self.category = category
        self.revenueDollars = revenueDollars
        self.cogsDollars = cogsDollars
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.category = (try? c.decode(String.self, forKey: .category)) ?? ""
        self.id = category
        self.revenueDollars = (try? c.decode(Double.self, forKey: .revenue)) ?? 0
        self.cogsDollars = (try? c.decode(Double.self, forKey: .cogs)) ?? 0
    }
}

// MARK: - RepeatCustomerStats

public struct RepeatCustomerStats: Decodable, Sendable {
    /// % of customers who returned within the period.
    public let repeatRatePct: Double
    /// Average days between first and second visit.
    public let avgDaysToRepeat: Double
    /// Count of one-time customers (never returned).
    public let oneTimeCount: Int
    /// Count of repeat customers.
    public let repeatCount: Int

    enum CodingKeys: String, CodingKey {
        case repeatRatePct  = "repeat_rate_pct"
        case avgDaysToRepeat = "avg_days_to_repeat"
        case oneTimeCount   = "one_time_count"
        case repeatCount    = "repeat_count"
    }

    public init(repeatRatePct: Double, avgDaysToRepeat: Double,
                oneTimeCount: Int, repeatCount: Int) {
        self.repeatRatePct = repeatRatePct
        self.avgDaysToRepeat = avgDaysToRepeat
        self.oneTimeCount = oneTimeCount
        self.repeatCount = repeatCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.repeatRatePct = (try? c.decode(Double.self, forKey: .repeatRatePct)) ?? 0
        self.avgDaysToRepeat = (try? c.decode(Double.self, forKey: .avgDaysToRepeat)) ?? 0
        self.oneTimeCount = (try? c.decode(Int.self, forKey: .oneTimeCount)) ?? 0
        self.repeatCount = (try? c.decode(Int.self, forKey: .repeatCount)) ?? 0
    }
}

// MARK: - AvgTicketValueTrendPoint

public struct AvgTicketValueTrendPoint: Decodable, Sendable, Identifiable {
    public let id: String
    public let period: String
    public let avgValueDollars: Double

    enum CodingKeys: String, CodingKey {
        case period
        case avgValue = "avg_value"
    }

    public init(period: String, avgValueDollars: Double) {
        self.id = period
        self.period = period
        self.avgValueDollars = avgValueDollars
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.period = (try? c.decode(String.self, forKey: .period)) ?? ""
        self.id = period
        self.avgValueDollars = (try? c.decode(Double.self, forKey: .avgValue)) ?? 0
    }
}

// MARK: - ConversionFunnelStats

public struct ConversionFunnelStats: Decodable, Sendable {
    public let leadsCount: Int
    public let estimatesCount: Int
    public let ticketsCount: Int
    public let invoicesCount: Int
    public let paidCount: Int

    public var leadsToEstimatesPct: Double {
        guard leadsCount > 0 else { return 0 }
        return Double(estimatesCount) / Double(leadsCount) * 100.0
    }
    public var estimatesToTicketsPct: Double {
        guard estimatesCount > 0 else { return 0 }
        return Double(ticketsCount) / Double(estimatesCount) * 100.0
    }
    public var ticketsToInvoicesPct: Double {
        guard ticketsCount > 0 else { return 0 }
        return Double(invoicesCount) / Double(ticketsCount) * 100.0
    }
    public var invoicesToPaidPct: Double {
        guard invoicesCount > 0 else { return 0 }
        return Double(paidCount) / Double(invoicesCount) * 100.0
    }
    public var overallConversionPct: Double {
        guard leadsCount > 0 else { return 0 }
        return Double(paidCount) / Double(leadsCount) * 100.0
    }

    enum CodingKeys: String, CodingKey {
        case leadsCount     = "leads_count"
        case estimatesCount = "estimates_count"
        case ticketsCount   = "tickets_count"
        case invoicesCount  = "invoices_count"
        case paidCount      = "paid_count"
    }

    public init(leadsCount: Int, estimatesCount: Int, ticketsCount: Int,
                invoicesCount: Int, paidCount: Int) {
        self.leadsCount = leadsCount
        self.estimatesCount = estimatesCount
        self.ticketsCount = ticketsCount
        self.invoicesCount = invoicesCount
        self.paidCount = paidCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.leadsCount = (try? c.decode(Int.self, forKey: .leadsCount)) ?? 0
        self.estimatesCount = (try? c.decode(Int.self, forKey: .estimatesCount)) ?? 0
        self.ticketsCount = (try? c.decode(Int.self, forKey: .ticketsCount)) ?? 0
        self.invoicesCount = (try? c.decode(Int.self, forKey: .invoicesCount)) ?? 0
        self.paidCount = (try? c.decode(Int.self, forKey: .paidCount)) ?? 0
    }
}

// MARK: - LaborUtilizationRow

public struct LaborUtilizationRow: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let techName: String
    /// Booked hours (scheduled/assigned).
    public let bookedHours: Double
    /// Productive hours (actively on job).
    public let productiveHours: Double
    public var utilizationPct: Double {
        guard bookedHours > 0 else { return 0 }
        return (productiveHours / bookedHours) * 100.0
    }

    enum CodingKeys: String, CodingKey {
        case id
        case techName        = "tech_name"
        case bookedHours     = "booked_hours"
        case productiveHours = "productive_hours"
    }

    public init(id: Int64, techName: String, bookedHours: Double, productiveHours: Double) {
        self.id = id
        self.techName = techName
        self.bookedHours = bookedHours
        self.productiveHours = productiveHours
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        self.techName = (try? c.decode(String.self, forKey: .techName)) ?? ""
        self.bookedHours = (try? c.decode(Double.self, forKey: .bookedHours)) ?? 0
        self.productiveHours = (try? c.decode(Double.self, forKey: .productiveHours)) ?? 0
    }
}

// MARK: - RevenueByCategoryCard (§15.9)

public struct RevenueByCategoryCard: View {
    public let rows: [RevenueByCategoryRow]

    public init(rows: [RevenueByCategoryRow]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            if rows.isEmpty {
                emptyState
            } else {
                chart
                if Platform.isCompact {
                    compactLegend
                } else {
                    fullLegend
                }
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
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Revenue & Margin by Category")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var chart: some View {
        let sorted = rows.sorted { $0.revenueDollars > $1.revenueDollars }.prefix(8)
        return Chart(Array(sorted)) { row in
            BarMark(
                x: .value("Revenue", row.revenueDollars),
                y: .value("Category", row.category)
            )
            .foregroundStyle(Color.bizarreOrange.opacity(0.85))
            .annotation(position: .trailing, alignment: .leading) {
                Text(String(format: "%.0f%%", row.grossMarginPct))
                    .font(.brandLabelSmall())
                    .foregroundStyle(row.grossMarginPct > 40 ? Color.bizarreSuccess : Color.bizarreWarning)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("\(row.category): \(String(format: "$%.0f", row.revenueDollars)) revenue, \(String(format: "%.0f%%", row.grossMarginPct)) margin")
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "$%.0f", d)) } }
            }
        }
        .frame(height: min(CGFloat(min(8, rows.count)) * 30 + 20, 260))
        .accessibilityChartDescriptor(RevenueByCategoryAX(rows: Array(sorted)))
    }

    private var compactLegend: some View {
        HStack {
            Image(systemName: "info.circle").foregroundStyle(.bizarreOnSurfaceMuted).imageScale(.small)
            Text("% = gross margin").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityHidden(true)
    }

    private var fullLegend: some View {
        HStack(spacing: BrandSpacing.lg) {
            let totalRevenue = rows.reduce(0.0) { $0 + $1.revenueDollars }
            let avgMargin = rows.isEmpty ? 0.0
                : rows.reduce(0.0) { $0 + $1.grossMarginPct } / Double(rows.count)
            VStack(alignment: .leading, spacing: 2) {
                Text(totalRevenue, format: .currency(code: "USD"))
                    .font(.brandHeadlineLarge()).monospacedDigit()
                    .foregroundStyle(.bizarreOnSurface)
                Text("total revenue")
                    .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel(String(format: "Total revenue $%.2f", totalRevenue))
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f%%", avgMargin))
                    .font(.brandHeadlineLarge()).monospacedDigit()
                    .foregroundStyle(avgMargin > 40 ? Color.bizarreSuccess : Color.bizarreWarning)
                Text("avg margin")
                    .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel(String(format: "Average gross margin %.1f%%", avgMargin))
            Spacer()
        }
    }

    private var emptyState: some View {
        Text("No category revenue data in selected period")
            .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            .accessibilityLabel("No category revenue data")
    }
}

private struct RevenueByCategoryAX: AXChartDescriptorRepresentable {
    let rows: [RevenueByCategoryRow]
    func makeChartDescriptor() -> AXChartDescriptor {
        let series = AXDataSeriesDescriptor(name: "Revenue", isContinuous: false,
            dataPoints: rows.map { AXDataPoint(x: $0.category, y: $0.revenueDollars) })
        return AXChartDescriptor(
            title: "Revenue by Category",
            summary: "\(rows.count) categories",
            xAxis: AXCategoricalDataAxisDescriptor(title: "Category", categoryOrder: rows.map(\.category)),
            yAxis: AXNumericDataAxisDescriptor(title: "Revenue",
                                               range: 0...max(1, rows.map(\.revenueDollars).max() ?? 1),
                                               gridlinePositions: [],
                                               valueDescriptionProvider: { String(format: "%.0f", $0) }),
            series: [series]
        )
    }
}

// MARK: - RepeatCustomerRateCard (§15.9)

public struct RepeatCustomerRateCard: View {
    public let stats: RepeatCustomerStats?

    public init(stats: RepeatCustomerStats?) {
        self.stats = stats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            if let s = stats {
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
            Image(systemName: "arrow.clockwise.heart.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Repeat Customer Rate")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func content(_ s: RepeatCustomerStats) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            HStack(spacing: BrandSpacing.xl) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f%%", s.repeatRatePct))
                        .font(.brandHeadlineLarge()).monospacedDigit()
                        .foregroundStyle(s.repeatRatePct > 40 ? Color.bizarreSuccess : Color.bizarreWarning)
                    Text("repeat rate")
                        .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel(String(format: "Repeat customer rate: %.1f%%", s.repeatRatePct))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f d", s.avgDaysToRepeat))
                        .font(.brandHeadlineLarge()).monospacedDigit()
                        .foregroundStyle(.bizarreOnSurface)
                    Text("avg return time")
                        .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel(String(format: "Average days to repeat: %.0f", s.avgDaysToRepeat))
                Spacer()
            }
            // Split bar: one-time vs repeat
            let total = s.oneTimeCount + s.repeatCount
            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.bizarreOrange)
                            .frame(
                                width: geo.size.width * CGFloat(s.repeatCount) / CGFloat(total),
                                height: 12
                            )
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.bizarreOutline.opacity(0.4))
                            .frame(height: 12)
                    }
                }
                .frame(height: 12)
                .accessibilityLabel("\(s.repeatCount) repeat customers, \(s.oneTimeCount) one-time customers")
                HStack {
                    HStack(spacing: 4) {
                        Circle().fill(Color.bizarreOrange).frame(width: 8, height: 8)
                        Text("Repeat (\(s.repeatCount))")
                            .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.bizarreOutline.opacity(0.5)).frame(width: 8, height: 8)
                        Text("One-time (\(s.oneTimeCount))")
                            .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Spacer()
                }
                .accessibilityHidden(true)
            }
        }
    }

    private var skeletonState: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.bizarreSurface2).frame(height: 20)
            }
        }
        .accessibilityLabel("Repeat customer data loading")
    }
}

// MARK: - AvgTicketValueTrendCard (§15.9)

public struct AvgTicketValueTrendCard: View {
    public let points: [AvgTicketValueTrendPoint]

    public init(points: [AvgTicketValueTrendPoint]) {
        self.points = points
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            if points.isEmpty {
                Text("No trend data in selected period")
                    .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No avg ticket value trend data")
            } else {
                kpiBand
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
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Avg Ticket Value Trend")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var kpiBand: some View {
        let current = points.last?.avgValueDollars ?? 0
        let first = points.first?.avgValueDollars ?? 0
        let trendPct = first > 0 ? ((current - first) / first) * 100.0 : 0
        return HStack(spacing: BrandSpacing.xl) {
            VStack(alignment: .leading, spacing: 2) {
                Text(current, format: .currency(code: "USD"))
                    .font(.brandHeadlineLarge()).monospacedDigit()
                    .foregroundStyle(.bizarreOnSurface)
                Text("current period")
                    .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel(String(format: "Current average ticket value $%.2f", current))
            HStack(spacing: 4) {
                Image(systemName: trendPct >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .foregroundStyle(trendPct >= 0 ? Color.bizarreSuccess : Color.bizarreError)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(String(format: "%.1f%% vs start", trendPct))
                    .font(.brandLabelLarge())
                    .foregroundStyle(trendPct >= 0 ? Color.bizarreSuccess : Color.bizarreError)
            }
            .accessibilityLabel(String(format: "Trend: %.1f%% vs start of period", trendPct))
            Spacer()
        }
    }

    private var chart: some View {
        Chart(points) { pt in
            LineMark(
                x: .value("Period", pt.period),
                y: .value("Avg Value", pt.avgValueDollars)
            )
            .foregroundStyle(Color.bizarreOrange)
            .interpolationMethod(.catmullRom)
            AreaMark(
                x: .value("Period", pt.period),
                y: .value("Avg Value", pt.avgValueDollars)
            )
            .foregroundStyle(Color.bizarreOrange.opacity(0.12))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { v in
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(String(format: "$%.0f", d)) }
                }
            }
        }
        .frame(height: 80)
        .accessibilityChartDescriptor(AvgTicketTrendAX(points: points))
    }
}

private struct AvgTicketTrendAX: AXChartDescriptorRepresentable {
    let points: [AvgTicketValueTrendPoint]
    func makeChartDescriptor() -> AXChartDescriptor {
        let series = AXDataSeriesDescriptor(name: "Avg Ticket Value", isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.period, y: $0.avgValueDollars) })
        return AXChartDescriptor(
            title: "Average Ticket Value Trend",
            summary: "\(points.count) data points",
            xAxis: AXCategoricalDataAxisDescriptor(title: "Period", categoryOrder: points.map(\.period)),
            yAxis: AXNumericDataAxisDescriptor(title: "Value ($)",
                                               range: 0...max(1, points.map(\.avgValueDollars).max() ?? 1),
                                               gridlinePositions: [],
                                               valueDescriptionProvider: { String(format: "%.2f", $0) }),
            series: [series]
        )
    }
}

// MARK: - ConversionFunnelCard (§15.9)

public struct ConversionFunnelCard: View {
    public let stats: ConversionFunnelStats?

    public init(stats: ConversionFunnelStats?) {
        self.stats = stats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            if let s = stats {
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
            Image(systemName: "arrow.down.to.line.alt")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Conversion Funnel")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func content(_ s: ConversionFunnelStats) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            funnelStep(label: "Leads", count: s.leadsCount, rate: nil, color: .bizarreOrange)
            stepArrow(pct: s.leadsToEstimatesPct)
            funnelStep(label: "Estimates", count: s.estimatesCount,
                       rate: s.leadsToEstimatesPct, color: .bizarreOrange.opacity(0.85))
            stepArrow(pct: s.estimatesToTicketsPct)
            funnelStep(label: "Tickets", count: s.ticketsCount,
                       rate: s.estimatesToTicketsPct, color: .bizarreOrange.opacity(0.7))
            stepArrow(pct: s.ticketsToInvoicesPct)
            funnelStep(label: "Invoices", count: s.invoicesCount,
                       rate: s.ticketsToInvoicesPct, color: .bizarreOrange.opacity(0.55))
            stepArrow(pct: s.invoicesToPaidPct)
            funnelStep(label: "Paid", count: s.paidCount,
                       rate: s.invoicesToPaidPct, color: .bizarreSuccess)
            Divider().padding(.vertical, BrandSpacing.xs)
            HStack {
                Image(systemName: "flag.checkered").foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(String(format: "Overall conversion: %.1f%%", s.overallConversionPct))
                    .font(.brandLabelLarge())
                    .foregroundStyle(s.overallConversionPct > 20 ? Color.bizarreSuccess : Color.bizarreWarning)
            }
            .accessibilityLabel(String(format: "Overall conversion rate: %.1f%%", s.overallConversionPct))
        }
    }

    private func funnelStep(label: String, count: Int, rate: Double?, color: Color) -> some View {
        GeometryReader { geo in
            HStack(spacing: BrandSpacing.sm) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(color)
                    .frame(width: max(40, geo.size.width * 0.5 * CGFloat(rate ?? 100) / 100.0), height: 28)
                    .overlay(alignment: .leading) {
                        Text("\(count)")
                            .font(.brandLabelLarge()).monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.leading, 8)
                    }
                Text(label)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
            }
        }
        .frame(height: 28)
        .accessibilityLabel("\(label): \(count)\(rate != nil ? String(format: " (%.0f%% conversion)", rate!) : "")")
    }

    private func stepArrow(pct: Double) -> some View {
        HStack {
            Image(systemName: "chevron.down")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(String(format: "%.0f%%", pct))
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.leading, BrandSpacing.sm)
        .accessibilityHidden(true)
    }

    private var skeletonState: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.bizarreSurface2).frame(height: 24)
            }
        }
        .accessibilityLabel("Conversion funnel data loading")
    }
}

// MARK: - LaborUtilizationCard (§15.9)

public struct LaborUtilizationCard: View {
    public let rows: [LaborUtilizationRow]

    public init(rows: [LaborUtilizationRow]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            if rows.isEmpty {
                Text("No labor utilization data in selected period")
                    .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No labor utilization data")
            } else {
                avgUtilizationBadge
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
            Image(systemName: "gauge.with.needle.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Labor Utilization by Tech")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var avgUtilizationBadge: some View {
        let avg = rows.isEmpty ? 0.0
            : rows.reduce(0.0) { $0 + $1.utilizationPct } / Double(rows.count)
        return HStack(spacing: BrandSpacing.xs) {
            Text(String(format: "%.0f%%", avg))
                .font(.brandHeadlineLarge()).monospacedDigit()
                .foregroundStyle(avg > 70 ? Color.bizarreSuccess : Color.bizarreWarning)
            Text("avg utilization")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityLabel(String(format: "Average labor utilization: %.0f%%", avg))
    }

    private var chart: some View {
        Chart(rows) { row in
            BarMark(
                x: .value("Utilization", row.utilizationPct),
                y: .value("Tech", row.techName)
            )
            .foregroundStyle(row.utilizationPct > 70 ? Color.bizarreSuccess.opacity(0.8) : Color.bizarreWarning.opacity(0.8))
            .annotation(position: .trailing, alignment: .leading) {
                Text(String(format: "%.0f%%", row.utilizationPct))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("\(row.techName): \(String(format: "%.0f%%", row.utilizationPct)) utilization")
        }
        .chartXScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%.0f%%", d)) } }
            }
        }
        .frame(height: min(CGFloat(rows.count) * 32 + 24, 240))
        .accessibilityChartDescriptor(LaborUtilizationAX(rows: rows))
    }
}

private struct LaborUtilizationAX: AXChartDescriptorRepresentable {
    let rows: [LaborUtilizationRow]
    func makeChartDescriptor() -> AXChartDescriptor {
        let series = AXDataSeriesDescriptor(name: "Utilization %", isContinuous: false,
            dataPoints: rows.map { AXDataPoint(x: $0.techName, y: $0.utilizationPct) })
        return AXChartDescriptor(
            title: "Labor Utilization by Tech",
            summary: "Percentage of booked hours spent productively per technician",
            xAxis: AXCategoricalDataAxisDescriptor(title: "Technician", categoryOrder: rows.map(\.techName)),
            yAxis: AXNumericDataAxisDescriptor(title: "Utilization %",
                                               range: 0...100,
                                               gridlinePositions: [25, 50, 75],
                                               valueDescriptionProvider: { String(format: "%.0f%%", $0) }),
            series: [series]
        )
    }
}
