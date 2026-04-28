#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import UniformTypeIdentifiers

// MARK: - ReconciliationDashboardViewModel

/// §39.4 — ViewModel for the full reconciliation dashboard.
///
/// Surfaces:
///  - Daily tie-out status
///  - Variance per period (weekly / monthly roll-up)
///  - Monthly reconciliation report
///  - Accounting export (QuickBooks / Xero)
///  - Variance drill-down
@MainActor
@Observable
public final class ReconciliationDashboardViewModel {

    // MARK: - State

    public private(set) var dailyRecords: [DailyReconciliation] = []
    public private(set) var periodSummaries: [ReconciliationPeriodSummary] = []
    public private(set) var monthlyRecords: [MonthlyReconciliation] = []
    public private(set) var drillEntries: [VarianceDrillEntry] = []
    public private(set) var isLoading: Bool = false
    public private(set) var exportData: Data?
    public private(set) var exportFilename: String = ""
    public var exportFormat: AccountingExportFormat = .quickBooksCSV
    public var showExporter: Bool = false
    public var selectedDrillEntry: VarianceDrillEntry?
    public var selectedTab: Tab = .daily

    public enum Tab: String, CaseIterable, Identifiable {
        case daily    = "Daily"
        case periodic = "Periodic"
        case monthly  = "Monthly"
        case export   = "Export"
        case drill    = "Drill-down"
        public var id: String { rawValue }
        public var icon: String {
            switch self {
            case .daily:    return "calendar.badge.checkmark"
            case .periodic: return "chart.bar.fill"
            case .monthly:  return "calendar"
            case .export:   return "arrow.up.doc.fill"
            case .drill:    return "magnifyingglass.circle.fill"
            }
        }
    }

    private let tieOutValidator = DailyTieOutValidator()
    private let exportGenerator = AccountingExportGenerator()
    private var sampleTransactions: [ReconciliationRow] = []

    public init() {}

    // MARK: - Actions

    public func load(
        daily: [DailyReconciliation] = [],
        periods: [ReconciliationPeriodSummary] = [],
        monthly: [MonthlyReconciliation] = [],
        drill: [VarianceDrillEntry] = [],
        transactions: [ReconciliationRow] = []
    ) {
        dailyRecords = daily
        periodSummaries = periods
        monthlyRecords = monthly
        drillEntries = drill
        sampleTransactions = transactions
    }

    public func generateExport() {
        let content = exportGenerator.generate(
            rows: sampleTransactions,
            format: exportFormat
        )
        exportData = content.data(using: .utf8)
        exportFilename = exportGenerator.filename(for: exportFormat)
        showExporter = true
    }

    public func tieOutFailures(for record: DailyReconciliation) -> [String] {
        tieOutValidator.validate(record)
    }
}

// MARK: - ReconciliationDashboardView

/// §39.4 — Full reconciliation dashboard.
///
/// Tab layout:
///   Daily — daily tie-out status list (sales + payments + cash + deposit)
///   Periodic — variance-per-period chart (weekly / monthly bars)
///   Monthly — full monthly reconciliation table (revenue / COGS / AR / AP)
///   Export — QuickBooks / Xero format picker + export trigger
///   Drill-down — variance investigation list with audit-log links
///
/// iPhone: TabView.
/// iPad: NavigationSplitView sidebar.
@MainActor
public struct ReconciliationDashboardView: View {

    @State var vm: ReconciliationDashboardViewModel

    @Environment(\.dismiss) private var dismiss

    public init(vm: ReconciliationDashboardViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                padLayout
            }
        }
        .fileExporter(
            isPresented: $vm.showExporter,
            document: ReconciliationExportDocument(
                data: vm.exportData ?? Data(),
                format: vm.exportFormat
            ),
            contentType: vm.exportFormat == .quickBooksIIF ? .plainText : .commaSeparatedText,
            defaultFilename: vm.exportFilename
        ) { result in
            if case .failure(let err) = result {
                AppLog.pos.error("Reconciliation export failed: \(err.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Phone layout

    private var phoneLayout: some View {
        NavigationStack {
            TabView(selection: $vm.selectedTab) {
                ForEach(ReconciliationDashboardViewModel.Tab.allCases) { tab in
                    tabContent(tab)
                        .tabItem { Label(tab.rawValue, systemImage: tab.icon) }
                        .tag(tab)
                }
            }
            .navigationTitle("Reconciliation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("reconciliation.done")
                }
            }
        }
    }

    // MARK: - iPad layout

    private var padLayout: some View {
        NavigationSplitView {
            List(selection: $vm.selectedTab) {
                ForEach(ReconciliationDashboardViewModel.Tab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                        .accessibilityIdentifier("reconciliation.sidebar.\(tab.rawValue)")
                }
            }
            .navigationTitle("Reconciliation")
        } detail: {
            tabContent(vm.selectedTab)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    // MARK: - Tab content router

    @ViewBuilder
    private func tabContent(_ tab: ReconciliationDashboardViewModel.Tab) -> some View {
        switch tab {
        case .daily:    dailyTab
        case .periodic: periodicTab
        case .monthly:  monthlyTab
        case .export:   exportTab
        case .drill:    drillTab
        }
    }

    // MARK: - Daily tab

    private var dailyTab: some View {
        List {
            if vm.dailyRecords.isEmpty {
                emptyState(
                    icon: "calendar.badge.checkmark",
                    title: "No daily records",
                    subtitle: "Daily reconciliation data will appear here after shifts close."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(vm.dailyRecords) { record in
                    dailyRow(record)
                        .listRowBackground(Color.bizarreSurface1)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Daily Tie-Out")
    }

    private func dailyRow(_ record: DailyReconciliation) -> some View {
        let failures = vm.tieOutFailures(for: record)
        let isTiedOut = failures.isEmpty
        return VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text(Self.shortDate(record.date))
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Label(isTiedOut ? "Tied out" : "Variance",
                      systemImage: isTiedOut ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.brandLabelSmall())
                    .foregroundStyle(isTiedOut ? .bizarreSuccess : .bizarreError)
                    .accessibilityIdentifier("reconDaily.status.\(record.id)")
            }

            if !isTiedOut {
                ForEach(failures, id: \.self) { reason in
                    Text("• \(reason)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                }
            }

            HStack(spacing: BrandSpacing.lg) {
                miniStat("Sales", CartMath.formatCents(record.totalSalesCents))
                miniStat("Payments", CartMath.formatCents(record.totalPaymentsCents))
                miniStat("Cash", CartMath.formatCents(record.cashCloseCents))
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reconDaily.row.\(record.id)")
    }

    // MARK: - Periodic tab

    private var periodicTab: some View {
        List {
            if vm.periodSummaries.isEmpty {
                emptyState(
                    icon: "chart.bar.fill",
                    title: "No period data",
                    subtitle: "Weekly and monthly variance summaries appear here."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(vm.periodSummaries) { period in
                    periodRow(period)
                        .listRowBackground(Color.bizarreSurface1)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Variance by Period")
    }

    private func periodRow(_ period: ReconciliationPeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text(period.label)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                varianceChip(period.varianceCents)
            }
            HStack(spacing: BrandSpacing.lg) {
                miniStat("Revenue", CartMath.formatCents(period.revenueCents))
                miniStat("Sessions", "\(period.sessionCount)")
                // Tie-out ratio bar
                HStack(spacing: 4) {
                    Text("Tied out")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    ProgressView(value: period.tiedOutPercent)
                        .frame(width: 60)
                        .tint(.bizarreSuccess)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(period.label), revenue \(CartMath.formatCents(period.revenueCents)), variance \(CartMath.formatCents(period.varianceCents))")
        .accessibilityIdentifier("reconPeriod.row.\(period.id)")
    }

    // MARK: - Monthly tab

    private var monthlyTab: some View {
        List {
            if vm.monthlyRecords.isEmpty {
                emptyState(
                    icon: "calendar",
                    title: "No monthly reports",
                    subtitle: "Full monthly reconciliation (revenue, COGS, AR aging, AP aging) will appear here once the month closes."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(vm.monthlyRecords) { month in
                    monthlyRow(month)
                        .listRowBackground(Color.bizarreSurface1)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Monthly Reports")
    }

    private func monthlyRow(_ month: MonthlyReconciliation) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(Self.monthLabel(month.month))
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: BrandSpacing.sm) {
                miniStat("Revenue",      CartMath.formatCents(month.revenueCents))
                miniStat("COGS",         CartMath.formatCents(month.cogsCents))
                miniStat("Gross profit", CartMath.formatCents(month.grossProfitCents))
                miniStat("Adjustments",  CartMath.formatCents(month.adjustmentsCents))
                miniStat("AR aging",     CartMath.formatCents(month.arAgingCents))
                miniStat("AP aging",     CartMath.formatCents(month.apAgingCents))
            }
            HStack {
                Text("Net")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(CartMath.formatCents(month.netCents))
                    .font(.brandTitleMedium())
                    .foregroundStyle(month.netCents >= 0 ? .bizarreSuccess : .bizarreError)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityIdentifier("reconMonthly.row.\(month.id)")
    }

    // MARK: - Export tab

    private var exportTab: some View {
        Form {
            Section {
                Picker("Format", selection: $vm.exportFormat) {
                    ForEach(AccountingExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("reconciliation.export.format")
            } header: {
                Text("Accounting software")
            } footer: {
                Text("The export file is generated on your device and shared via the system share sheet. No data is sent to third-party servers.")
                    .font(.brandLabelSmall())
            }

            Section {
                Button {
                    vm.generateExport()
                } label: {
                    Label("Export \(vm.exportFormat.rawValue)", systemImage: "arrow.up.doc.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("reconciliation.export.trigger")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Export")
    }

    // MARK: - Drill-down tab

    private var drillTab: some View {
        List {
            if vm.drillEntries.isEmpty {
                emptyState(
                    icon: "magnifyingglass.circle.fill",
                    title: "No variance entries",
                    subtitle: "Tap a day with a variance flag on the Daily tab to drill into specific transactions."
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    HStack {
                        Text("Total variance")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text(CartMath.formatCents(vm.drillEntries.reduce(0) { $0 + $1.varianceCents }))
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreError)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Summary")
                }
                .listRowBackground(Color.bizarreSurface1)

                Section {
                    ForEach(vm.drillEntries) { entry in
                        drillRow(entry)
                            .listRowBackground(Color.bizarreSurface1)
                    }
                } header: {
                    Text("Transactions")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Variance Drill-Down")
    }

    private func drillRow(_ entry: VarianceDrillEntry) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text(entry.label)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Spacer()
                varianceChip(entry.varianceCents)
            }
            HStack {
                Text("Invoice #\(entry.id) · \(entry.tenderMethod)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(Self.shortDateTime(entry.timestamp))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            HStack(spacing: BrandSpacing.lg) {
                miniStat("Expected", CartMath.formatCents(entry.expectedCents))
                miniStat("Actual", CartMath.formatCents(entry.actualCents))
            }
            // Audit log link
            if let auditURL = entry.auditURL {
                Link(destination: auditURL) {
                    Label("View in audit log", systemImage: "arrow.up.right.square")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreTeal)
                }
                .accessibilityIdentifier("reconDrill.audit.\(entry.id)")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Invoice \(entry.id), \(entry.label), variance \(CartMath.formatCents(entry.varianceCents))")
        .accessibilityIdentifier("reconDrill.row.\(entry.id)")
    }

    // MARK: - Shared components

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOutline)
                .padding(.top, BrandSpacing.xxl)
                .accessibilityHidden(true)
            Text(title)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(subtitle)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, BrandSpacing.xxl)
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
    }

    private func varianceChip(_ cents: Int) -> some View {
        let color: Color = cents == 0 ? .bizarreSuccess : .bizarreError
        let text: String = cents == 0 ? "✓ Tied" : (cents > 0 ? "+\(CartMath.formatCents(cents))" : "-\(CartMath.formatCents(-cents))")
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Date formatters

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    private static func shortDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }

    private static func monthLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: d)
    }
}

// MARK: - Export document wrapper

struct ReconciliationExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    let data: Data
    let format: AccountingExportFormat

    init(data: Data, format: AccountingExportFormat) {
        self.data = data
        self.format = format
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        format = .quickBooksCSV
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Preview

#Preview("Reconciliation Dashboard — Phone") {
    let vm = ReconciliationDashboardViewModel()
    let today = Date()
    let cal = Calendar.current
    vm.load(
        daily: [
            DailyReconciliation(id: "2026-04-26", date: today,
                totalSalesCents: 148_50, totalPaymentsCents: 148_50,
                cashCloseCents: 45_00, bankDepositCents: 45_00),
            DailyReconciliation(id: "2026-04-25", date: cal.date(byAdding: .day, value: -1, to: today)!,
                totalSalesCents: 201_99, totalPaymentsCents: 199_00,
                cashCloseCents: 38_00, bankDepositCents: 38_00),
        ],
        periods: [
            ReconciliationPeriodSummary(id: "2026-W17", label: "Apr 21–27",
                revenueCents: 1_240_00, varianceCents: -299, sessionCount: 5, tiedOutCount: 4),
        ],
        monthly: [
            MonthlyReconciliation(id: "2026-04", month: today,
                revenueCents: 4_800_00, cogsCents: 1_920_00,
                adjustmentsCents: -50_00, arAgingCents: 350_00,
                apAgingCents: 120_00, netCents: 2_830_00),
        ],
        drill: [
            VarianceDrillEntry(id: 1042, timestamp: today, label: "iPhone Screen Repair",
                tenderMethod: "card", expectedCents: 14_999, actualCents: 14_700),
        ],
        transactions: []
    )
    return ReconciliationDashboardView(vm: vm)
        .preferredColorScheme(.dark)
}
#endif
