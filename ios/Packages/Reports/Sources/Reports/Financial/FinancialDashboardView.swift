#if canImport(UIKit)
import SwiftUI
import Charts
import Core
import DesignSystem
import Networking

// MARK: - FinancialDashboardView

public struct FinancialDashboardView: View {
    @State private var vm: FinancialDashboardViewModel
    @State private var showTaxYear: Bool = false
    @State private var showExport: Bool = false
    @State private var exportCSV: String?
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: FinancialDashboardViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
    }

    // MARK: iPhone

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Financial Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .onChange(of: vm.period) { _, _ in Task { await vm.load() } }
            .sheet(isPresented: $showTaxYear) { TaxYearReportView(api: api) }
        }
    }

    // MARK: iPad

    private var regularLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Financial Dashboard")
            .toolbar { toolbarContent }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .onChange(of: vm.period) { _, _ in Task { await vm.load() } }
            .sheet(isPresented: $showTaxYear) { TaxYearReportView(api: api) }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Picker("Period", selection: $vm.period) {
                ForEach(FinancialPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button { showTaxYear = true } label: {
                    Label("Tax Year Report", systemImage: "doc.text")
                }
                Button {
                    if case .loaded(let data) = vm.loadState {
                        exportCSV = FinancialExportService.exportCSV(data: data, period: vm.period.rawValue)
                        showExport = true
                    }
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More actions")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        if vm.isAccessDenied {
            accessDeniedView
        } else {
            switch vm.loadState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                errorView(msg)
            case .loaded(let data):
                if Platform.isCompact {
                    dashboardScroll(data)
                } else {
                    dashboardGrid(data)
                }
            }
        }
    }

    // MARK: iPhone scroll layout

    private func dashboardScroll(_ data: FinancialDashboardData) -> some View {
        ScrollView {
            LazyVStack(spacing: BrandSpacing.md) {
                pnlHeroTile(data.pnl)
                cashFlowTile(data.cashFlow)
                agedReceivablesTile(data.agedReceivables)
                topCustomersTile(data.topCustomers)
                topSkusTile(data.topSkus)
            }
            .padding(BrandSpacing.md)
        }
    }

    // MARK: iPad 3-column grid

    private func dashboardGrid(_ data: FinancialDashboardData) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: BrandSpacing.md),
                    GridItem(.flexible(), spacing: BrandSpacing.md),
                    GridItem(.flexible(), spacing: BrandSpacing.md)
                ],
                spacing: BrandSpacing.md
            ) {
                pnlHeroTile(data.pnl)
                    .gridCellColumns(3)
                cashFlowTile(data.cashFlow)
                    .gridCellColumns(2)
                agedReceivablesTile(data.agedReceivables)
                topCustomersTile(data.topCustomers)
                topSkusTile(data.topSkus)
            }
            .padding(BrandSpacing.md)
        }
    }

    // MARK: - P&L Hero tile (Liquid Glass chrome)

    private func pnlHeroTile(_ pnl: PnLSnapshot) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            Text("Profit & Loss")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            HStack(spacing: BrandSpacing.xl) {
                pnlMetric("Revenue",     cents: pnl.revenueCents,      color: .bizarreOrange)
                pnlMetric("COGS",        cents: pnl.cogsCents,          color: .bizarreWarning)
                pnlMetric("Expenses",    cents: pnl.expensesCents,      color: .bizarreError)
                pnlMetric("Net",         cents: pnl.netCents,           color: pnl.netCents >= 0 ? .bizarreSuccess : .bizarreError)
            }
            HStack(spacing: BrandSpacing.md) {
                Text("Gross Margin: \(String(format: "%.1f%%", pnl.grossMarginPct * 100))")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Net Margin: \(String(format: "%.1f%%", pnl.netMarginPct * 100))")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .brandGlass(.identity, in: RoundedRectangle(cornerRadius: 16), tint: .bizarreOrange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("P&L: Revenue \(pnl.revenueCents.financialString), Net \(pnl.netCents.financialString)")
    }

    private func pnlMetric(_ label: String, cents: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(cents.financialString)
                .font(.brandTitleMedium())
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    // MARK: - Cash Flow tile

    private func cashFlowTile(_ points: [CashFlowPoint]) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Cash Flow")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            if points.isEmpty {
                Text("No data for this period")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(height: 160)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Inflow", Double(point.inflowCents) / 100.0)
                        )
                        .foregroundStyle(.bizarreSuccess)
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Outflow", Double(point.outflowCents) / 100.0)
                        )
                        .foregroundStyle(.bizarreError)
                    }
                }
                .chartForegroundStyleScale([
                    "Inflow": Color.bizarreSuccess,
                    "Outflow": Color.bizarreError
                ])
                .frame(height: 160)
                .accessibilityChartDescriptor(cashFlowChartDescriptor(points))
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private func cashFlowChartDescriptor(_ points: [CashFlowPoint]) -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Date",
            categoryOrder: points.map(\.id)
        )
        let yAxis = AXNumericDataAxisDescriptor(title: "Amount ($)", range: 0...1, gridlinePositions: []) { _ in "" }
        let inflows = AXDataSeriesDescriptor(
            name: "Inflows",
            isContinuous: true,
            dataPoints: points.map {
                AXDataPoint(x: $0.id, y: Double($0.inflowCents) / 100.0)
            }
        )
        let outflows = AXDataSeriesDescriptor(
            name: "Outflows",
            isContinuous: true,
            dataPoints: points.map {
                AXDataPoint(x: $0.id, y: Double($0.outflowCents) / 100.0)
            }
        )
        return AXChartDescriptor(
            title: "Cash Flow",
            summary: "\(points.count) data points",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [inflows, outflows]
        )
    }

    // MARK: - Aged Receivables tile

    private func agedReceivablesTile(_ ar: AgedReceivablesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Aged Receivables")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Chart {
                ForEach(ar.buckets, id: \.label) { bucket in
                    BarMark(
                        x: .value("Bucket", bucket.label),
                        y: .value("Amount", Double(bucket.totalCents) / 100.0)
                    )
                    .foregroundStyle(arBucketColor(bucket.label))
                    .annotation(position: .top) {
                        Text(bucket.invoiceCount > 0 ? "\(bucket.invoiceCount)" : "")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            .frame(height: 140)
            .accessibilityChartDescriptor(arChartDescriptor(ar))
            Text("Total outstanding: \(ar.totalCents.financialString)")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private func arBucketColor(_ label: String) -> Color {
        switch label {
        case "0-30":  return .bizarreSuccess
        case "31-60": return .bizarreWarning
        case "61-90": return .bizarreOrange
        default:      return .bizarreError
        }
    }

    private func arChartDescriptor(_ ar: AgedReceivablesSnapshot) -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Age bucket",
            categoryOrder: ar.buckets.map(\.label)
        )
        let yAxis = AXNumericDataAxisDescriptor(title: "Amount ($)", range: 0...1, gridlinePositions: []) { _ in "" }
        let series = AXDataSeriesDescriptor(
            name: "Aged Receivables",
            isContinuous: false,
            dataPoints: ar.buckets.map {
                AXDataPoint(x: $0.label, y: Double($0.totalCents) / 100.0,
                            additionalValues: [.number(Double($0.invoiceCount))])
            }
        )
        return AXChartDescriptor(
            title: "Aged Receivables",
            summary: "Total outstanding \(ar.totalCents.financialString)",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    // MARK: - Top Customers tile

    private func topCustomersTile(_ customers: [TopCustomer]) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Top Customers by Revenue")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            if customers.isEmpty {
                Text("No data").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                Chart {
                    ForEach(customers.prefix(10)) { c in
                        BarMark(
                            x: .value("Revenue", Double(c.revenueCents) / 100.0),
                            y: .value("Customer", c.name)
                        )
                        .foregroundStyle(.bizarreOrange)
                    }
                }
                .frame(height: CGFloat(min(customers.count, 10)) * 28 + 20)
                .accessibilityChartDescriptor(topCustomersDescriptor(customers))
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private func topCustomersDescriptor(_ customers: [TopCustomer]) -> AXChartDescriptor {
        let xAxis = AXNumericDataAxisDescriptor(title: "Revenue ($)", range: 0...1, gridlinePositions: []) { _ in "" }
        let yAxis = AXCategoricalDataAxisDescriptor(title: "Customer", categoryOrder: customers.map(\.name))
        let series = AXDataSeriesDescriptor(
            name: "Top Customers",
            isContinuous: false,
            dataPoints: customers.map {
                AXDataPoint(x: Double($0.revenueCents) / 100.0, y: $0.name)
            }
        )
        return AXChartDescriptor(title: "Top Customers", summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }

    // MARK: - Top SKUs tile

    private func topSkusTile(_ skus: [TopSkuByMargin]) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Top SKUs by Margin")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            if skus.isEmpty {
                Text("No data").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(skus.prefix(10)) { sku in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sku.name)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Text(sku.sku)
                                .font(.brandMono(size: 12))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(sku.marginCents.financialString)
                                .font(.brandTitleMedium())
                                .monospacedDigit()
                                .foregroundStyle(.bizarreSuccess)
                            Text(String(format: "%.1f%%", sku.marginPct * 100))
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(sku.name), margin \(sku.marginCents.financialString)")
                    Divider()
                }
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Access denied

    private var accessDeniedView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreError)
            Text("Owner access required")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("The Financial Dashboard is only visible to users with the owner role.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Access denied. Owner role required.")
    }

    // MARK: - Error view

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
            Text("Couldn't load financial data")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cents formatter

extension Int {
    fileprivate var financialString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(self) / 100.0)) ?? "$0.00"
    }
}
#endif
