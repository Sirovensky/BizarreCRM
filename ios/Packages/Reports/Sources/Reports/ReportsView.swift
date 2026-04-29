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

    public init(repository: ReportsRepository,
                onTapSaleRecord: @escaping (Int64) -> Void = { _ in }) {
        _vm = State(wrappedValue: ReportsViewModel(repository: repository))
        self.exportService = ReportExportService(repository: repository)
        self.csvService = ReportCSVService()
        self.onTapSaleRecord = onTapSaleRecord
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
                        heroTile
                            .padding(.horizontal, BrandSpacing.base)
                        if vm.isLoading {
                            loadingPlaceholders
                        } else {
                            cardStack
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
                        heroTile
                            .padding(.horizontal, BrandSpacing.base)
                        if vm.isLoading {
                            loadingPlaceholders
                        } else {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: BrandSpacing.md),
                                    GridItem(.flexible(), spacing: BrandSpacing.md),
                                    GridItem(.flexible(), spacing: BrandSpacing.md)
                                ],
                                spacing: BrandSpacing.md
                            ) {
                                cardItems
                            }
                            .padding(.horizontal, BrandSpacing.base)
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
                .accessibilityHint("Generates a PDF of the current report and opens the share sheet")

                Button {
                    Task { await exportCSV() }
                } label: {
                    Label("Export CSV", systemImage: "doc.plaintext")
                }
                .accessibilityLabel("Export CSV report")
                .accessibilityHint("Generates a CSV spreadsheet of the current report data")

                Button {
                    showEmailSheet = true
                } label: {
                    Label("Email Report", systemImage: "envelope")
                }
                .accessibilityLabel("Email report")
                .accessibilityHint("Opens a dialog to enter a recipient email address")

                Button {
                    showScheduled = true
                } label: {
                    Label("Scheduled Reports", systemImage: "clock")
                }
                .accessibilityLabel("Scheduled reports settings")
                .accessibilityHint("Opens scheduled report delivery settings")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .brandGlass(.clear, in: Circle())
            .accessibilityLabel("Report actions")
            .accessibilityHint("Double tap to open export and scheduling options")
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
            .frame(minHeight: 44)
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
        .frame(minHeight: 44)
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

    // MARK: - Phone card stack (single column)

    private var cardStack: some View {
        VStack(spacing: BrandSpacing.md) {
            cardItems
        }
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: - Card items (shared between phone/iPad)

    @ViewBuilder
    private var cardItems: some View {
        // §15.2 Revenue chart — line + bar via /reports/sales
        RevenueChartCard(points: vm.revenue, periodChangePct: vm.salesTotals.revenueChangePct) { pt in
            drillContext = .revenue(date: pt.date)
        }

        // §15.9 Expenses chart — bar via /reports/dashboard-kpis
        ExpensesChartCard(report: vm.expensesReport)

        // §15.5 Inventory movement chart — bar via /reports/inventory
        InventoryMovementCard(report: vm.inventoryReport)

        // §15.3 Tickets by status
        TicketsByStatusCard(points: vm.ticketsByStatus)

        // §15.2 Avg ticket value KPI
        AvgTicketValueCard(value: vm.avgTicketValue)

        // §15.4 Employee performance
        TopEmployeesCard(employees: vm.employeePerf)

        // §15.5 Inventory turnover (category table)
        InventoryTurnoverCard(rows: vm.inventoryTurnover)

        // §15.7 CSAT + NPS
        CSATScoreCard(score: vm.csatScore) {
            showCSATDetail = true
        }

        NPSScoreCard(score: vm.npsScore) {
            showNPSDetail = true
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

