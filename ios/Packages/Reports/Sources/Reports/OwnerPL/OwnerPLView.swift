import SwiftUI
import Charts
import DesignSystem
import Core

// MARK: - OwnerPLView
//
// Owner P&L summary — GET /api/v1/owner-pl/summary (admin-only).
// iPhone: single-column scroll.
// iPad: 3-column LazyVGrid for KPI cards; time-series chart spans full width.
// Liquid Glass on toolbar + date chrome only; never on chart surfaces.

public struct OwnerPLView: View {
    @State private var vm: OwnerPLViewModel
    /// Whether the export-to-CSV copy share sheet is presented.
    public init(repository: OwnerPLRepository) {
        _vm = State(wrappedValue: OwnerPLViewModel(repository: repository))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                ipadLayout
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: - iPhone layout (single column)

    private var phoneLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: BrandSpacing.md) {
                        controls.padding(.horizontal, BrandSpacing.base)
                        if vm.isLoading {
                            loadingPlaceholders
                        } else if let err = vm.errorMessage {
                            errorBanner(err)
                                .padding(.horizontal, BrandSpacing.base)
                        } else if let s = vm.summary {
                            phoneCards(s).padding(.horizontal, BrandSpacing.base)
                        }
                    }
                    .padding(.bottom, BrandSpacing.xxl)
                }
            }
            .navigationTitle("Owner P&L")
            .toolbar { toolbarChrome }
        }
    }

    // MARK: - iPad layout (3-col grid + full-width chart)

    private var ipadLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: BrandSpacing.md) {
                        controls.padding(.horizontal, BrandSpacing.base)
                        if vm.isLoading {
                            loadingPlaceholders
                        } else if let err = vm.errorMessage {
                            errorBanner(err)
                                .padding(.horizontal, BrandSpacing.base)
                        } else if let s = vm.summary {
                            // Full-width time-series chart
                            timeSeriesCard(s)
                                .padding(.horizontal, BrandSpacing.base)

                            // 3-column KPI grid
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: BrandSpacing.md),
                                    GridItem(.flexible(), spacing: BrandSpacing.md),
                                    GridItem(.flexible(), spacing: BrandSpacing.md)
                                ],
                                spacing: BrandSpacing.md
                            ) {
                                kpiCards(s)
                            }
                            .padding(.horizontal, BrandSpacing.base)

                            // Top customers + services side by side on iPad
                            HStack(alignment: .top, spacing: BrandSpacing.md) {
                                topCustomersCard(s).frame(maxWidth: .infinity)
                                topServicesCard(s).frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, BrandSpacing.base)
                        }
                    }
                    .padding(.bottom, BrandSpacing.xxl)
                }
            }
            .navigationTitle("Owner P&L")
            .toolbar { toolbarChrome }
        }
    }

    // MARK: - Phone card stack

    @ViewBuilder
    private func phoneCards(_ s: OwnerPLSummary) -> some View {
        timeSeriesCard(s)
        kpiCards(s)
        topCustomersCard(s)
        topServicesCard(s)
        expensesBreakdownCard(s)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: BrandSpacing.sm) {
            Picker("Date Range", selection: $vm.selectedPreset) {
                ForEach(DateRangePreset.allCases) { p in
                    Text(p.displayLabel).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: vm.selectedPreset) { _, _ in Task { await vm.load() } }
            .accessibilityLabel("Select date range")

            Picker("Rollup", selection: $vm.rollup) {
                ForEach(OwnerPLRollup.allCases) { r in
                    Text(r.displayLabel).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: vm.rollup) { _, _ in Task { await vm.load() } }
            .accessibilityLabel("Select time bucket granularity")

            // §59 Gross-vs-net revenue toggle
            Picker("Revenue", selection: $vm.showNetRevenue) {
                Text("Gross").tag(false)
                Text("Net").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Show gross or net revenue")
        }
    }

    // MARK: - Toolbar chrome (Liquid Glass)

    @ToolbarContentBuilder
    private var toolbarChrome: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            if vm.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        // §59 Export-to-CSV copy: ShareLink presents native share sheet with RFC-4180 CSV
        ToolbarItem(placement: .navigationBarTrailing) {
            if let s = vm.summary {
                let csv = OwnerPLCSVExporter.export(summary: s, showNetRevenue: vm.showNetRevenue)
                ShareLink(
                    item: csv,
                    subject: Text("Owner P&L Export"),
                    message: Text("BizarreCRM Owner P&L — \(s.period.from) to \(s.period.to)")
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel("Export P&L as CSV")
                }
            } else {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Export P&L as CSV (loading)")
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Time-series chart (Revenue vs Expenses, Swift Charts BarMark)

    private func timeSeriesCard(_ s: OwnerPLSummary) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                // §59 Gross-vs-net toggle reflected in chart title
                Text(vm.showNetRevenue ? "Net Revenue vs Expenses" : "Revenue vs Expenses")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                // §59 YoY delta chip for total revenue across period
                if let pct = s.yoyRevenuePct {
                    YoYDeltaChip(pct: pct)
                }
            }

            if s.timeSeries.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.bar",
                    description: Text("No time-series data for this period.")
                )
                .frame(height: 200)
            } else {
                // §59 Gross-vs-net: show net cents when toggle is active
                Chart(s.timeSeries) { bucket in
                    let revenueValue = vm.showNetRevenue
                        ? (bucket.revenueDollars - Double(bucket.expenseCents) / 100.0) / 1000.0
                        : bucket.revenueDollars / 1000.0
                    BarMark(
                        x: .value("Period", bucket.bucket),
                        y: .value(vm.showNetRevenue ? "Net Revenue ($K)" : "Revenue ($K)", revenueValue),
                        width: .ratio(0.4)
                    )
                    .foregroundStyle(Color.bizarreOrange.opacity(0.8))
                    .position(by: .value("Series", vm.showNetRevenue ? "Net Revenue" : "Revenue"))
                    .cornerRadius(DesignTokens.Radius.xs)

                    BarMark(
                        x: .value("Period", bucket.bucket),
                        y: .value("Expenses ($K)", bucket.expenseDollars / 1000.0),
                        width: .ratio(0.4)
                    )
                    .foregroundStyle(Color.bizarreError.opacity(0.7))
                    .position(by: .value("Series", "Expenses"))
                    .cornerRadius(DesignTokens.Radius.xs)
                }
                .chartForegroundStyleScale([
                    vm.showNetRevenue ? "Net Revenue" : "Revenue": Color.bizarreOrange,
                    "Expenses": Color.bizarreError
                ])
                .chartXAxisLabel("Period", alignment: .center)
                .chartYAxisLabel("$K", position: .leading)
                .frame(height: 220)
                .accessibilityLabel("\(vm.showNetRevenue ? "Net revenue" : "Revenue") vs expenses bar chart by period")
                .accessibilityChartDescriptor(OwnerPLChartDescriptor(buckets: s.timeSeries))
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - KPI cards (shared between phone/iPad)

    @ViewBuilder
    private func kpiCards(_ s: OwnerPLSummary) -> some View {
        // §59 Gross-vs-net toggle: show net or gross revenue tile
        plKpiCard(
            title: vm.showNetRevenue ? "Net Revenue" : "Gross Revenue",
            value: vm.showNetRevenue ? s.revenue.netDollars : s.revenue.grossDollars,
            icon: "dollarsign.circle.fill",
            color: KPIColorState.revenue(
                cents: vm.showNetRevenue ? s.revenue.netCents : s.revenue.grossCents
            ).color,
            yoyPct: s.yoyRevenuePct
        )
        plKpiCard(
            title: "Net Profit",
            value: s.netProfit.dollars,
            icon: "chart.line.uptrend.xyaxis",
            color: KPIColorState.profit(cents: s.netProfit.cents, marginPct: s.netProfit.marginPct).color,
            marginPct: s.netProfit.marginPct,
            yoyPct: s.yoyNetProfitPct
        )
        plKpiCard(
            title: "Gross Profit",
            value: s.grossProfit.dollars,
            icon: "checkmark.seal.fill",
            color: KPIColorState.profit(cents: s.grossProfit.cents, marginPct: s.grossProfit.marginPct).color,
            marginPct: s.grossProfit.marginPct
        )
        plKpiCard(
            title: "Total Expenses",
            value: s.expenses.totalDollars,
            icon: "minus.circle.fill",
            color: KPIColorState.expenses(
                cents: s.expenses.totalCents,
                revenueRef: vm.showNetRevenue ? s.revenue.netCents : s.revenue.grossCents
            ).color
        )
        plKpiCard(
            title: "AR Outstanding",
            value: s.ar.outstandingDollars,
            icon: "clock.badge.exclamationmark",
            color: KPIColorState.ar(overdueCents: s.ar.overdueCents).color,
            badge: s.ar.overdueDollars > 0
                ? String(format: "$%.0f overdue", s.ar.overdueDollars) : nil
        )
        plKpiCard(
            title: "Tax Outstanding",
            value: s.taxLiability.outstandingDollars,
            icon: "building.columns.fill",
            color: KPIColorState.tax(outstandingCents: s.taxLiability.outstandingCents).color
        )
    }

    private func plKpiCard(
        title: String,
        value: Double,
        icon: String,
        color: Color,
        marginPct: Double? = nil,
        badge: String? = nil,
        yoyPct: Double? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                // §59 YoY delta chip
                if let yoyPct {
                    YoYDeltaChip(pct: yoyPct)
                }
            }
            Text(value, format: .currency(code: "USD"))
                .font(.brandTitleMedium())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: BrandSpacing.xs) {
                // §59 P&L margin badge
                if let marginPct {
                    MarginBadge(marginPct: marginPct)
                }
                if let badge {
                    Text(badge)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        // §59 KPI tile tinted background reflects color state
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(plKpiAccessibilityLabel(title: title, value: value, marginPct: marginPct, badge: badge, yoyPct: yoyPct))
    }

    private func plKpiAccessibilityLabel(
        title: String,
        value: Double,
        marginPct: Double?,
        badge: String?,
        yoyPct: Double?
    ) -> String {
        var label = "\(title): \(String(format: "$%.2f", value))"
        if let marginPct {
            label += String(format: ", %.1f%% margin", marginPct * 100)
        }
        if let badge {
            label += ", \(badge)"
        }
        if let yoyPct {
            let sign = yoyPct >= 0 ? "up" : "down"
            label += String(format: ", %@ %.1f%% year over year", sign, abs(yoyPct * 100))
        }
        return label
    }

    // MARK: - Expenses breakdown card (pie-like BarChart)

    private func expensesBreakdownCard(_ s: OwnerPLSummary) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Expenses by Category")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            if s.expenses.byCategory.isEmpty {
                Text("No expense data")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                Chart(s.expenses.byCategory) { row in
                    BarMark(
                        x: .value("Amount ($K)", row.dollars / 1000.0),
                        y: .value("Category", row.category)
                    )
                    .foregroundStyle(Color.bizarreOrange.opacity(0.75))
                    .cornerRadius(DesignTokens.Radius.xs)
                    .annotation(position: .trailing) {
                        Text(String(format: "$%.0fK", row.dollars / 1000.0))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .frame(height: CGFloat(max(80, s.expenses.byCategory.count * 36)))
                .chartXAxisLabel("Amount ($K)", alignment: .center)
                .accessibilityLabel("Expenses by category horizontal bar chart")
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - Top customers

    private func topCustomersCard(_ s: OwnerPLSummary) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Top Customers")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            if s.topCustomers.isEmpty {
                Text("No customer data")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(s.topCustomers.prefix(10)) { customer in
                    HStack {
                        Text(customer.name.isEmpty ? "Customer #\(customer.customerId)" : customer.name)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text(customer.revenueDollars, format: .currency(code: "USD"))
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreSuccess)
                    }
                    .frame(minHeight: DesignTokens.Touch.minTargetSide)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(customer.name): \(String(format: "$%.2f", customer.revenueDollars))")

                    Divider()
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - Top services

    private func topServicesCard(_ s: OwnerPLSummary) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Top Services")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            if s.topServices.isEmpty {
                Text("No service data")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(s.topServices.prefix(10)) { svc in
                    HStack {
                        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                            Text(svc.service)
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            Text("\(svc.count) repairs")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        Spacer()
                        Text(svc.revenueDollars, format: .currency(code: "USD"))
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreSuccess)
                    }
                    .frame(minHeight: DesignTokens.Touch.minTargetSide)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(svc.service): \(svc.count) repairs, \(String(format: "$%.2f", svc.revenueDollars))")

                    Divider()
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - Loading placeholders

    private var loadingPlaceholders: some View {
        VStack(spacing: BrandSpacing.md) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(Color.bizarreSurface1)
                    .frame(height: 100)
                    .opacity(0.5)
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .accessibilityLabel("Loading Owner P&L…")
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - Helpers

    private func accessibilityLabel(title: String, value: Double, marginPct: Double?, badge: String?, yoyPct: Double?) -> String {
        var s = "\(title): \(String(format: "$%.2f", value))"
        if let m = marginPct { s += String(format: ", %.1f%% margin", m * 100) }
        if let b = badge     { s += ", \(b)" }
        if let p = yoyPct    { s += String(format: ", %@ %.1f%% year over year", p >= 0 ? "up" : "down", abs(p * 100)) }
        return s
    }

    private var strokeBorder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
    }
}

// MARK: - KPI color state (§59 KPI tile color states)

/// Semantic color token selection for each KPI tile type.
/// Thresholds are intentionally conservative — amber at borderline, red only at clear negative.
private enum KPIColorState {
    case good, caution, bad

    var color: Color {
        switch self {
        case .good:    return .bizarreSuccess
        case .caution: return .bizarreWarning
        case .bad:     return .bizarreError
        }
    }

    /// Revenue tile: orange when positive (neutral brand tone), error when zero/negative.
    static func revenue(cents: Int) -> KPIColorState {
        cents > 0 ? .good : .bad
    }

    /// Profit tile: green above 15% margin, amber 5-15%, red below 5% or loss.
    static func profit(cents: Int, marginPct: Double) -> KPIColorState {
        guard cents >= 0 else { return .bad }
        if marginPct >= 0.15 { return .good }
        if marginPct >= 0.05 { return .caution }
        return .bad
    }

    /// Expenses tile: green if below 60% of revenue, amber 60-80%, red above 80%.
    static func expenses(cents: Int, revenueRef: Int) -> KPIColorState {
        guard revenueRef > 0 else { return .caution }
        let ratio = Double(cents) / Double(revenueRef)
        if ratio < 0.60 { return .good }
        if ratio < 0.80 { return .caution }
        return .bad
    }

    /// AR tile: green if no overdue, amber if overdue < 20% outstanding, red otherwise.
    static func ar(overdueCents: Int) -> KPIColorState {
        overdueCents == 0 ? .good : .bad
    }

    /// Tax tile: green if fully remitted, amber if outstanding.
    static func tax(outstandingCents: Int) -> KPIColorState {
        outstandingCents == 0 ? .good : .caution
    }
}

// MARK: - MarginBadge (§59 P&L margin badge)

/// Pill-shaped badge showing margin percentage with semantic colour.
private struct MarginBadge: View {
    let marginPct: Double

    var body: some View {
        let pct = marginPct * 100
        let color: Color = {
            if pct >= 15 { return .bizarreSuccess }
            if pct >= 5  { return .bizarreWarning }
            return .bizarreError
        }()
        Text(String(format: "%.1f%% margin", pct))
            .font(.brandLabelSmall())
            .foregroundStyle(color)
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 0.5))
            .accessibilityLabel(String(format: "%.1f percent margin", pct))
    }
}

// MARK: - YoYDeltaChip (§59 year-over-year delta chip)

/// Compact chip showing YoY percentage change with directional arrow.
private struct YoYDeltaChip: View {
    let pct: Double   // e.g. 0.12 = +12%

    private var isPositive: Bool { pct >= 0 }
    private var color: Color { isPositive ? .bizarreSuccess : .bizarreError }
    private var arrowIcon: String { isPositive ? "arrow.up.right" : "arrow.down.right" }
    private var label: String { String(format: "%@%.1f%% YoY", isPositive ? "+" : "", pct * 100) }

    var body: some View {
        Label(label, systemImage: arrowIcon)
            .font(.brandLabelSmall())
            .foregroundStyle(color)
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, 2)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
            .accessibilityLabel(
                String(format: "%.1f percent %@ year over year",
                       abs(pct * 100), isPositive ? "increase" : "decrease")
            )
    }
}

// MARK: - AXChartDescriptorRepresentable for Owner P&L time-series chart

private struct OwnerPLChartDescriptor: AXChartDescriptorRepresentable {
    let buckets: [PLTimeBucket]

    func makeChartDescriptor() -> AXChartDescriptor {
        let revenueAxis = AXNumericDataAxisDescriptor(
            title: "Revenue ($)",
            range: 0...max(1, Double(buckets.map(\.revenueCents).max() ?? 0) / 100.0),
            gridlinePositions: []
        ) { value in String(format: "$%.0f", value) }

        let expensesAxis = AXNumericDataAxisDescriptor(
            title: "Expenses ($)",
            range: 0...max(1, Double(buckets.map(\.expenseCents).max() ?? 0) / 100.0),
            gridlinePositions: []
        ) { value in String(format: "$%.0f", value) }

        let revenueSeries = AXDataSeriesDescriptor(
            name: "Revenue",
            isContinuous: false,
            dataPoints: buckets.map { b in
                AXDataPoint(x: b.bucket, y: b.revenueDollars,
                            label: "\(b.bucket): \(String(format: "$%.0f", b.revenueDollars)) revenue")
            }
        )
        let expensesSeries = AXDataSeriesDescriptor(
            name: "Expenses",
            isContinuous: false,
            dataPoints: buckets.map { b in
                AXDataPoint(x: b.bucket, y: b.expenseDollars,
                            label: "\(b.bucket): \(String(format: "$%.0f", b.expenseDollars)) expenses")
            }
        )

        return AXChartDescriptor(
            title: "Revenue vs Expenses by Period",
            summary: "Grouped bar chart comparing revenue and expenses across \(buckets.count) periods.",
            xAxis: AXCategoricalDataAxisDescriptor(title: "Period", categoryOrder: buckets.map(\.bucket)),
            yAxis: revenueAxis,
            additionalAxes: [expensesAxis],
            series: [revenueSeries, expensesSeries]
        )
    }
}
