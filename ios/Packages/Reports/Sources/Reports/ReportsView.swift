import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

// MARK: - ReportsView

/// Full Reports dashboard — Phase 8 §15.
///
/// iPhone: single-column card scroll.
/// iPad: 3-column `LazyVGrid`.
///
/// Liquid Glass only on toolbar and hero tile chrome; never on chart surfaces.
public struct ReportsView: View {
    @State private var vm: ReportsViewModel
    private let exportService: ReportExportService

    // Sheet routing
    @State private var drillContext: DrillThroughContext?
    @State private var showCSATDetail = false
    @State private var showNPSDetail  = false
    @State private var showScheduled  = false
    @State private var exportURL: URL?
    @State private var showExportShare = false
    @State private var exportError: String?
    @State private var emailRecipient = ""
    @State private var showEmailSheet  = false

    private let csvService: ReportCSVService
    private let onTapSaleRecord: (Int64) -> Void
    /// Navigation callback used by `TenantZeroStateView` and per-card POS CTAs.
    private let onGoToPOS: (() -> Void)?

    public init(repository: ReportsRepository,
                onTapSaleRecord: @escaping (Int64) -> Void = { _ in },
                onGoToPOS: (() -> Void)? = nil) {
        _vm = State(wrappedValue: ReportsViewModel(repository: repository))
        self.exportService = ReportExportService(repository: repository)
        self.csvService = ReportCSVService()
        self.onTapSaleRecord = onTapSaleRecord
        self.onGoToPOS = onGoToPOS
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                ipadLayout
            }
        }
        .task { await vm.loadAll() }
        .refreshable { await vm.loadAll() }
        .sheet(item: $drillContext) { ctx in
            DrillThroughSheet(
                context: ctx,
                repository: vm.repository,
                onTapSale: { id in drillContext = nil; onTapSaleRecord(id) }
            )
        }
        .sheet(isPresented: $showCSATDetail) {
            if let csat = vm.csatScore {
                CSATDetailView(score: csat)
            }
        }
        .sheet(isPresented: $showNPSDetail) {
            if let nps = vm.npsScore {
                NPSDetailView(score: nps)
            }
        }
        .sheet(isPresented: $showScheduled) {
            ScheduledReportsSettingsView(repository: vm.repository)
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ShareLink(item: url)
            }
        }
        .alert("Email Report", isPresented: $showEmailSheet) {
            TextField("Recipient email", text: $emailRecipient)
                .autocorrectionDisabled()
            Button("Send") { Task { await sendEmail() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Export Error", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - iPhone Layout

    private var phoneLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: BrandSpacing.md) {
                        dateRangePicker
                            .padding(.horizontal, BrandSpacing.base)
                        if !vm.isTenantZeroState {
                            heroTile
                                .padding(.horizontal, BrandSpacing.base)
                        }
                        if vm.isLoading {
                            loadingPlaceholders
                        } else if vm.isTenantZeroState {
                            // §91.16 item 1: tenant zero-state replaces the entire card surface
                            HStack {
                                Spacer()
                                TenantZeroStateView(onGoToPOS: onGoToPOS)
                                Spacer()
                            }
                            .padding(.top, BrandSpacing.xxl)
                        } else {
                            // §91.16 item 3: shared ReportsGrid container
                            ReportsGrid {
                                cardItems
                            }
                        }
                    }
                    .padding(.bottom, BrandSpacing.xxl)
                }
            }
            .navigationTitle("Reports")
            .toolbar { toolbarItems }
        }
    }

    // MARK: - iPad Layout

    private var ipadLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: BrandSpacing.md) {
                        dateRangePicker
                            .padding(.horizontal, BrandSpacing.base)
                        if !vm.isTenantZeroState {
                            heroTile
                                .padding(.horizontal, BrandSpacing.base)
                        }
                        if vm.isLoading {
                            loadingPlaceholders
                        } else if vm.isTenantZeroState {
                            // §91.16 item 1: tenant zero-state replaces the entire card surface
                            HStack {
                                Spacer()
                                TenantZeroStateView(onGoToPOS: onGoToPOS)
                                Spacer()
                            }
                            .padding(.top, BrandSpacing.xxl)
                        } else {
                            // §91.16 item 3: shared ReportsGrid container
                            ReportsGrid {
                                cardItems
                            }
                        }
                    }
                    .padding(.bottom, BrandSpacing.xxl)
                }
            }
            .navigationTitle("Reports")
            .toolbar { toolbarItems }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    Task { await exportPDF() }
                } label: {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
                .accessibilityLabel("Export PDF report")

                Button {
                    Task { await exportCSV() }
                } label: {
                    Label("Export CSV", systemImage: "doc.plaintext")
                }
                .accessibilityLabel("Export CSV report")

                Button {
                    showEmailSheet = true
                } label: {
                    Label("Email Report", systemImage: "envelope")
                }
                .accessibilityLabel("Email report")

                Button {
                    showScheduled = true
                } label: {
                    Label("Scheduled Reports", systemImage: "clock")
                }
                .accessibilityLabel("Scheduled reports settings")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .brandGlass(.clear, in: Circle())
            .accessibilityLabel("Report actions")
        }
    }

    // MARK: - Date Range Picker + Granularity Toggle

    private var dateRangePicker: some View {
        VStack(spacing: BrandSpacing.sm) {
            Picker("Date Range", selection: $vm.selectedPreset) {
                ForEach(DateRangePreset.allCases) { preset in
                    Text(preset.displayLabel).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: vm.selectedPreset) { _, _ in
                Task { await vm.loadAll() }
            }
            .accessibilityLabel("Select date range preset")

            granularityToggle
        }
    }

    private var granularityToggle: some View {
        Picker("Granularity", selection: $vm.granularity) {
            ForEach(ReportGranularity.allCases) { g in
                Text(g.displayLabel).tag(g)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: vm.granularity) { _, _ in
            Task { await vm.loadAll() }
        }
        .accessibilityLabel("Select chart granularity: day, week, or month")
    }

    // MARK: - Hero Tile (Liquid Glass on chrome)

    @ViewBuilder
    private var heroTile: some View {
        HStack(spacing: BrandSpacing.base) {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Revenue")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(vm.revenueTotalDollars, format: .currency(code: "USD"))
                    .font(.brandHeadlineLarge())
                    .foregroundStyle(.bizarreOnSurface)
                HStack(spacing: BrandSpacing.sm) {
                    sparklineView
                    if let atv = vm.avgTicketValue {
                        trendArrow(pct: atv.trendPct)
                    }
                }
            }
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOrange.opacity(0.5))
                .accessibilityHidden(true)
        }
        .padding(BrandSpacing.base)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Total revenue for period: \(String(format: "$%.2f", vm.revenueTotalDollars))"
        )
    }

    @ViewBuilder
    private var sparklineView: some View {
        if !vm.revenue.isEmpty {
            SparklineView(points: vm.revenue.map { Double($0.amountCents) })
                .frame(width: 80, height: 24)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func trendArrow(pct: Double) -> some View {
        let isUp = pct >= 0
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(String(format: "%.1f%%", abs(pct)))
                .font(.brandLabelLarge())
        }
        .foregroundStyle(isUp ? Color.bizarreSuccess : Color.bizarreError)
    }

    // MARK: - Loading Placeholders

    private var loadingPlaceholders: some View {
        VStack(spacing: BrandSpacing.md) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(Color.bizarreSurface1)
                    .frame(height: 120)
                    .shimmer()
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .accessibilityLabel("Loading reports…")
    }

    // MARK: - Card items (shared between phone/iPad via ReportsGrid)
    //
    // §91.16 item 4: each empty card surfaces a CTA that guides the operator
    // toward the action that will generate the missing data.

    @ViewBuilder
    private var cardItems: some View {
        // §15.2 Revenue chart — line + bar via /reports/sales
        VStack(spacing: BrandSpacing.sm) {
            RevenueChartCard(points: vm.revenue, periodChangePct: vm.salesTotals.revenueChangePct) { pt in
                drillContext = .revenue(date: pt.date)
            }
            if vm.revenue.isEmpty {
                ReportCardCTA(spec: .revenue(action: onGoToPOS))
                    .padding(.horizontal, BrandSpacing.base)
            }
        }

        // §15.9 Expenses chart — bar via /reports/dashboard-kpis
        VStack(spacing: BrandSpacing.sm) {
            ExpensesChartCard(report: vm.expensesReport)
            if vm.expensesReport == nil {
                ReportCardCTA(spec: .expenses())
                    .padding(.horizontal, BrandSpacing.base)
            }
        }

        // §15.5 Inventory movement chart — bar via /reports/inventory
        InventoryMovementCard(report: vm.inventoryReport)

        // §15.3 Tickets by status
        VStack(spacing: BrandSpacing.sm) {
            TicketsByStatusCard(points: vm.ticketsByStatus)
            if vm.ticketsByStatus.isEmpty {
                ReportCardCTA(spec: .tickets())
                    .padding(.horizontal, BrandSpacing.base)
            }
        }

        // §15.2 Avg ticket value KPI
        AvgTicketValueCard(value: vm.avgTicketValue)

        // §15.4 Employee performance
        VStack(spacing: BrandSpacing.sm) {
            TopEmployeesCard(employees: vm.employeePerf)
            if vm.employeePerf.isEmpty {
                ReportCardCTA(spec: .employeePerformance())
                    .padding(.horizontal, BrandSpacing.base)
            }
        }

        // §15.5 Inventory turnover (category table)
        VStack(spacing: BrandSpacing.sm) {
            InventoryTurnoverCard(rows: vm.inventoryTurnover)
            if vm.inventoryTurnover.isEmpty {
                ReportCardCTA(spec: .inventoryHealth())
                    .padding(.horizontal, BrandSpacing.base)
            }
        }

        // §15.7 CSAT + NPS
        VStack(spacing: BrandSpacing.sm) {
            CSATScoreCard(score: vm.csatScore) {
                showCSATDetail = true
            }
            if vm.csatScore == nil {
                ReportCardCTA(spec: .customerSatisfaction())
                    .padding(.horizontal, BrandSpacing.base)
            }
        }

        VStack(spacing: BrandSpacing.sm) {
            NPSScoreCard(score: vm.npsScore) {
                showNPSDetail = true
            }
            if vm.npsScore == nil {
                ReportCardCTA(spec: .customerSatisfaction())
                    .padding(.horizontal, BrandSpacing.base)
            }
        }
    }

    // MARK: - Export

    private func exportPDF() async {
        let snapshot = ReportSnapshot(
            title: "BizarreCRM Report",
            period: "\(vm.fromDateString) – \(vm.toDateString)",
            revenue: vm.revenue,
            ticketsByStatus: vm.ticketsByStatus,
            avgTicketValue: vm.avgTicketValue,
            topEmployees: Array(vm.employeePerf.prefix(5)),
            inventoryTurnover: vm.inventoryTurnover,
            csatScore: vm.csatScore,
            npsScore: vm.npsScore
        )
        do {
            exportURL = try await exportService.generatePDF(report: snapshot)
            showExportShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportCSV() async {
        let snapshot = ReportSnapshot(
            title: "BizarreCRM Report",
            period: "\(vm.fromDateString) – \(vm.toDateString)",
            revenue: vm.revenue,
            ticketsByStatus: vm.ticketsByStatus,
            avgTicketValue: vm.avgTicketValue,
            topEmployees: Array(vm.employeePerf.prefix(5)),
            inventoryTurnover: vm.inventoryTurnover,
            csatScore: vm.csatScore,
            npsScore: vm.npsScore
        )
        do {
            exportURL = try await csvService.generateSnapshotCSV(report: snapshot)
            showExportShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func sendEmail() async {
        let snapshot = ReportSnapshot(
            title: "BizarreCRM Report",
            period: "\(vm.fromDateString) – \(vm.toDateString)",
            revenue: vm.revenue,
            ticketsByStatus: vm.ticketsByStatus,
            avgTicketValue: vm.avgTicketValue,
            topEmployees: Array(vm.employeePerf.prefix(5)),
            inventoryTurnover: vm.inventoryTurnover,
            csatScore: vm.csatScore,
            npsScore: vm.npsScore
        )
        do {
            let url = try await exportService.generatePDF(report: snapshot)
            try await exportService.emailReport(pdf: url, recipient: emailRecipient)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - SparklineView

private struct SparklineView: View {
    let points: [Double]

    var body: some View {
        GeometryReader { geo in
            let (minV, maxV) = (points.min() ?? 0, points.max() ?? 1)
            let range = max(maxV - minV, 1)
            let w = geo.size.width / max(Double(points.count - 1), 1)
            let h = geo.size.height

            Path { path in
                for (idx, val) in points.enumerated() {
                    let x = Double(idx) * w
                    let y = h - ((val - minV) / range * h)
                    if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.bizarreOrange, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}

// MARK: - Shimmer placeholder modifier

private extension View {
    func shimmer() -> some View {
        self.opacity(0.5)
    }
}

// MARK: - DrillThroughContext Identifiable

extension DrillThroughContext: Identifiable {
    public var id: String { "\(metric)-\(date)" }
}

