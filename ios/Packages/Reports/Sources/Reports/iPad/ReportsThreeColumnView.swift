import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

// MARK: - ReportCategory

/// The four top-level report categories shown in the sidebar column.
public enum ReportCategory: String, CaseIterable, Sendable, Identifiable {
    case revenue   = "Revenue"
    case expenses  = "Expenses"
    case inventory = "Inventory"
    case ownerPL   = "Owner P&L"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var systemImage: String {
        switch self {
        case .revenue:   return "arrow.up.right.circle.fill"
        case .expenses:  return "arrow.down.left.circle.fill"
        case .inventory: return "shippingbox.fill"
        case .ownerPL:   return "chart.bar.doc.horizontal.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .revenue:   return .bizarreSuccess
        case .expenses:  return .bizarreError
        case .inventory: return .bizarreTeal
        case .ownerPL:   return .bizarreOrange
        }
    }
}

// MARK: - ReportsThreeColumnView

/// iPad-only 3-column Reports layout:
///   Col 1 (sidebar)  — report category list (Revenue / Expenses / Inventory / Owner P&L)
///   Col 2 (content)  — chart for the selected category
///   Col 3 (detail)   — drill-through inspector pane
///
/// Liquid Glass only on toolbar chrome; never on chart surfaces (per CLAUDE.md).
public struct ReportsThreeColumnView: View {
    @State private var vm: ReportsViewModel
    @State private var selectedCategory: ReportCategory = .revenue
    @State private var drillContext: DrillThroughContext?
    @State private var showLegend: Bool = false
    @State private var exportURL: URL?
    @State private var showExportShare: Bool = false
    @State private var exportError: String?

    private let exportService: ReportExportService
    private let onTapSaleRecord: (Int64) -> Void

    public init(
        repository: ReportsRepository,
        onTapSaleRecord: @escaping (Int64) -> Void = { _ in }
    ) {
        _vm = State(wrappedValue: ReportsViewModel(repository: repository))
        self.exportService = ReportExportService(repository: repository)
        self.onTapSaleRecord = onTapSaleRecord
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebarColumn
        } content: {
            chartColumn
        } detail: {
            drillPane
        }
        .task { await vm.loadAll() }
        .refreshable { await vm.loadAll() }
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ShareLink(item: url)
            }
        }
        .alert(
            "Export Error",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - Sidebar Column

    private var sidebarColumn: some View {
        List {
            ForEach(ReportCategory.allCases, id: \.self) { category in
                Button {
                    selectedCategory = category
                } label: {
                    ReportCategorySidebarRow(
                        category: category,
                        isSelected: selectedCategory == category
                    )
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel("Report category: " + category.displayName)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Reports")
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
            }
        }
    }

    // MARK: - Chart Column

    private var chartColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.md) {
                    dateRangePicker
                        .padding(.horizontal, BrandSpacing.base)
                    if vm.isLoading {
                        loadingPlaceholders
                    } else {
                        chartContent
                            .padding(.horizontal, BrandSpacing.base)
                    }
                }
                .padding(.bottom, BrandSpacing.xxl)
            }
        }
        .navigationTitle(selectedCategory.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { chartToolbarItems }
    }

    @ViewBuilder
    private var chartContent: some View {
        switch selectedCategory {
        case .revenue:
            RevenueChartCard(
                points: vm.revenue,
                periodChangePct: vm.salesTotals.revenueChangePct
            ) { pt in
                drillContext = .revenue(date: pt.date)
            }
        case .expenses:
            ExpensesChartCard(report: vm.expensesReport)
        case .inventory:
            VStack(spacing: BrandSpacing.md) {
                InventoryMovementCard(report: vm.inventoryReport)
                InventoryTurnoverCard(rows: vm.inventoryTurnover)
            }
        case .ownerPL:
            // Owner P&L summary tile — displays top employee revenue as proxy
            TopEmployeesCard(employees: vm.employeePerf)
        }
    }

    @ToolbarContentBuilder
    private var chartToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            BrandGlassContainer {
                HStack(spacing: BrandSpacing.sm) {
                    Button {
                        showLegend.toggle()
                    } label: {
                        Label(
                            showLegend ? "Hide Legend" : "Show Legend",
                            systemImage: showLegend
                                ? "list.bullet.rectangle.fill"
                                : "list.bullet.rectangle"
                        )
                    }
                    .brandGlass(.clear, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .accessibilityLabel(showLegend ? "Hide legend" : "Show legend")

                    Button {
                        Task { await exportCurrentPDF() }
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                    }
                    .brandGlass(.clear, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .keyboardShortcut("e", modifiers: .command)
                    .accessibilityLabel("Export report as PDF")

                    Button {
                        Task { await vm.loadAll() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .brandGlass(.clear, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityLabel("Refresh reports")
                }
            }
        }
    }

    // MARK: - Drill-Through Pane (detail column)

    @ViewBuilder
    private var drillPane: some View {
        if let ctx = drillContext {
            DrillThroughSheet(
                context: ctx,
                repository: vm.repository,
                onTapSale: { id in
                    drillContext = nil
                    onTapSaleRecord(id)
                }
            )
        } else if showLegend {
            ReportLegendInspector(
                category: selectedCategory,
                vm: vm
            )
        } else {
            drillPlaceholder
        }
    }

    private var drillPlaceholder: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ContentUnavailableView(
                "Select a data point",
                systemImage: "chart.xyaxis.line",
                description: Text("Tap a chart bar or point to inspect details here.")
            )
        }
    }

    // MARK: - Date Range Picker

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
            .accessibilityLabel("Select chart granularity")
        }
    }

    // MARK: - Loading Placeholders

    private var loadingPlaceholders: some View {
        VStack(spacing: BrandSpacing.md) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(Color.bizarreSurface1)
                    .frame(height: 140)
                    .opacity(0.5)
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .accessibilityLabel("Loading reports…")
    }

    // MARK: - Export

    private func exportCurrentPDF() async {
        let snapshot = ReportSnapshot(
            title: "BizarreCRM – \(selectedCategory.displayName)",
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
}

// MARK: - ReportCategorySidebarRow

private struct ReportCategorySidebarRow: View {
    let category: ReportCategory
    let isSelected: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: category.systemImage)
                .font(.system(size: 20))
                .foregroundStyle(category.accentColor)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            Text(category.displayName)
                .font(.brandLabelLarge())
                .foregroundStyle(
                    isSelected ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted
                )

            Spacer()
        }
        .padding(.vertical, BrandSpacing.xs)
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
        .contentShape(Rectangle())
    }
}
