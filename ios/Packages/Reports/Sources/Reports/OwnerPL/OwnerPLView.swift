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
    }

    // MARK: - Time-series chart (Revenue vs Expenses, Swift Charts BarMark)

    private func timeSeriesCard(_ s: OwnerPLSummary) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("Revenue vs Expenses")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }

            if s.timeSeries.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.bar",
                    description: Text("No time-series data for this period.")
                )
                .frame(height: 200)
            } else {
                Chart(s.timeSeries) { bucket in
                    BarMark(
                        x: .value("Period", bucket.bucket),
                        y: .value("Revenue ($K)", bucket.revenueDollars / 1000.0),
                        width: .ratio(0.4)
                    )
                    .foregroundStyle(Color.bizarreOrange.opacity(0.8))
                    .position(by: .value("Series", "Revenue"))
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
                    "Revenue": Color.bizarreOrange,
                    "Expenses": Color.bizarreError
                ])
                .chartXAxisLabel("Period", alignment: .center)
                .chartYAxisLabel("$K", position: .leading)
                .frame(height: 220)
                .accessibilityLabel("Revenue vs expenses bar chart by period")
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
    }

    // MARK: - KPI cards (shared between phone/iPad)

    @ViewBuilder
    private func kpiCards(_ s: OwnerPLSummary) -> some View {
        plKpiCard(
            title: "Gross Revenue",
            value: s.revenue.grossDollars,
            icon: "dollarsign.circle.fill",
            color: .bizarreOrange
        )
        plKpiCard(
            title: "Net Profit",
            value: s.netProfit.dollars,
            icon: "chart.line.uptrend.xyaxis",
            color: s.netProfit.cents >= 0 ? .bizarreSuccess : .bizarreError,
            badge: String(format: "%.1f%% margin", s.netProfit.marginPct)
        )
        plKpiCard(
            title: "Gross Profit",
            value: s.grossProfit.dollars,
            icon: "checkmark.seal.fill",
            color: s.grossProfit.cents >= 0 ? .bizarreTeal : .bizarreError,
            badge: String(format: "%.1f%% margin", s.grossProfit.marginPct)
        )
        plKpiCard(
            title: "Total Expenses",
            value: s.expenses.totalDollars,
            icon: "minus.circle.fill",
            color: .bizarreWarning
        )
        plKpiCard(
            title: "AR Outstanding",
            value: s.ar.outstandingDollars,
            icon: "clock.badge.exclamationmark",
            color: s.ar.overdueCents > 0 ? .bizarreError : .bizarreOnSurfaceMuted,
            badge: s.ar.overdueDollars > 0
                ? String(format: "$%.0f overdue", s.ar.overdueDollars) : nil
        )
        plKpiCard(
            title: "Tax Outstanding",
            value: s.taxLiability.outstandingDollars,
            icon: "building.columns.fill",
            color: s.taxLiability.outstandingCents > 0 ? .bizarreWarning : .bizarreSuccess
        )
    }

    private func plKpiCard(
        title: String,
        value: Double,
        icon: String,
        color: Color,
        badge: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Text(value, format: .currency(code: "USD"))
                .font(.brandTitleMedium())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let badge {
                Text(badge)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(strokeBorder)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(String(format: "$%.2f", value))\(badge.map { ", \($0)" } ?? "")")
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

    private var strokeBorder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
    }
}
