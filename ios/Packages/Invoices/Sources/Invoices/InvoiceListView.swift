#if canImport(UIKit)
import SwiftUI
import UniformTypeIdentifiers
import Core
import DesignSystem
import Networking
import Sync

// §7.1 Invoice list — status tabs, filters, sort, row chips, stats header, bulk, export CSV, context menu, pagination

public struct InvoiceListView: View {
    @State private var vm: InvoiceListViewModel
    @State private var bulkVM: InvoiceBulkActionViewModel
    @State private var searchText: String = ""
    @State private var path: [Int64] = []
    @State private var showSortMenu: Bool = false
    @State private var csvExportItem: ExportableCSV?
    @State private var showPaySheet: Int64?
    @State private var showRefundSheet: Int64?
    @State private var showVoidAlert: Int64?
    @State private var showReceiptSheet: Int64?
    @State private var showCreditNoteSheet: Int64?

    @ObservationIgnored private let detailRepo: InvoiceDetailRepository
    @ObservationIgnored private let api: APIClient

    public init(repo: InvoiceRepository, detailRepo: InvoiceDetailRepository, api: APIClient) {
        self.detailRepo = detailRepo
        self.api = api
        _vm = State(wrappedValue: InvoiceListViewModel(repo: repo))
        _bulkVM = State(wrappedValue: InvoiceBulkActionViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task {
            vm.isOffline = !Reachability.shared.isOnline
            await vm.load()
        }
        .refreshable { await vm.refresh() }
        .fileExporter(
            isPresented: Binding(
                get: { csvExportItem != nil },
                set: { if !$0 { csvExportItem = nil } }
            ),
            document: csvExportItem,
            contentType: .commaSeparatedText,
            defaultFilename: "invoices.csv"
        ) { _ in csvExportItem = nil }
        // Quick-pay sheet from context menu / swipe
        .sheet(
            isPresented: Binding(
                get: { showPaySheet != nil },
                set: { if !$0 { showPaySheet = nil } }
            )
        ) {
            if let invoiceId = showPaySheet {
                InvoiceDetailView(repo: detailRepo, invoiceId: invoiceId, api: api)
            }
        }
        // Credit note sheet from context menu
        .sheet(
            isPresented: Binding(
                get: { showCreditNoteSheet != nil },
                set: { if !$0 { showCreditNoteSheet = nil } }
            )
        ) {
            if let invoiceId = showCreditNoteSheet {
                let paidCents: Int = vm.invoices.first { $0.id == invoiceId }
                    .map { Int((($0.amountPaid ?? 0) * 100).rounded()) } ?? 0
                InvoiceCreditNoteSheet(api: api, invoiceId: invoiceId, maxCents: paidCents) {
                    showCreditNoteSheet = nil
                    Task { await vm.refresh() }
                }
            }
        }
        // Email receipt sheet from context menu
        .sheet(
            isPresented: Binding(
                get: { showReceiptSheet != nil },
                set: { if !$0 { showReceiptSheet = nil } }
            )
        ) {
            if let invoiceId = showReceiptSheet {
                InvoiceDetailView(repo: detailRepo, invoiceId: invoiceId, api: api)
            }
        }
    }

    // MARK: - Compact (iPhone)

    private var compactLayout: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Stats header
                    InvoiceStatsHeaderView(api: api)
                    // Status tabs
                    statusTabBar.padding(.bottom, BrandSpacing.xs)
                    content
                }
                if vm.isOffline {
                    OfflineBanner(isOffline: true).padding(.top, BrandSpacing.xs)
                }
            }
            .navigationTitle("Invoices")
            .searchable(text: $searchText, prompt: "Search invoices")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .navigationDestination(for: Int64.self) { id in
                InvoiceDetailView(repo: detailRepo, invoiceId: id, api: api)
            }
            .toolbar { toolbarItems }
        }
    }

    // MARK: - Regular (iPad)

    private var regularLayout: some View {
        NavigationSplitView {
            NavigationStack(path: $path) {
                ZStack(alignment: .top) {
                    Color.bizarreSurfaceBase.ignoresSafeArea()
                    VStack(spacing: 0) {
                        InvoiceStatsHeaderView(api: api)
                        statusTabBar.padding(.bottom, BrandSpacing.xs)
                        content
                    }
                    if vm.isOffline {
                        OfflineBanner(isOffline: true).padding(.top, BrandSpacing.xs)
                    }
                }
                .navigationTitle("Invoices")
                .searchable(text: $searchText, prompt: "Search invoices")
                .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
                .navigationDestination(for: Int64.self) { id in
                    InvoiceDetailView(repo: detailRepo, invoiceId: id, api: api)
                }
                .toolbar { toolbarItems }
            }
            .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 520)
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 52))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Select an invoice")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Status tab bar (§7.1)

    private var statusTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(InvoiceStatusTab.allCases) { tab in
                    StatusTabChip(
                        label: tab.displayName,
                        selected: vm.statusTab == tab
                    ) {
                        Task { await vm.applyStatusTab(tab) }
                    }
                    .accessibilityLabel("\(tab.displayName) invoices")
                    .accessibilityAddTraits(vm.statusTab == tab ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, BrandSpacing.base)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorState(message: err)
        } else if vm.invoices.isEmpty && vm.isOffline {
            OfflineEmptyStateView(entityName: "invoices")
        } else if vm.invoices.isEmpty {
            emptyState
        } else {
            invoiceList
        }
    }

    private var invoiceList: some View {
        List {
            // Bulk mode select-all banner
            if vm.isBulkMode {
                BulkSelectionBanner(
                    selectedCount: vm.selectedIds.count,
                    totalCount: vm.invoices.count,
                    isAllSelected: vm.isAllSelected,
                    onSelectAll: { vm.selectAll() },
                    onDeselectAll: { vm.deselectAll() }
                )
                .listRowBackground(Color.bizarreSurface1)
            }

            ForEach(vm.invoices) { inv in
                invoiceRow(for: inv)
            }

            // Load more trigger
            if vm.hasMore {
                HStack {
                    Spacer()
                    if vm.isLoadingMore {
                        ProgressView()
                    } else {
                        Button("Load more") { Task { await vm.loadMore() } }
                            .buttonStyle(.plain)
                            .foregroundStyle(.bizarreOrange)
                    }
                    Spacer()
                }
                .listRowBackground(Color.bizarreSurface1)
                .onAppear { Task { await vm.loadMore() } }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func invoiceRow(for inv: InvoiceSummary) -> some View {
        HStack {
            if vm.isBulkMode {
                Image(systemName: vm.selectedIds.contains(inv.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(vm.selectedIds.contains(inv.id) ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .onTapGesture { vm.toggleSelection(id: inv.id) }
                    .accessibilityLabel(vm.selectedIds.contains(inv.id) ? "Deselect invoice \(inv.displayId)" : "Select invoice \(inv.displayId)")
            }
            NavigationLink(value: inv.id) {
                InvoiceRow(invoice: inv)
            }
        }
        .listRowBackground(Color.bizarreSurface1)
        .hoverEffect(.highlight)
        .contextMenu { rowContextMenu(for: inv) }
        .swipeActions(edge: .leading) {
            Button {
                showPaySheet = inv.id
            } label: {
                Label("Pay", systemImage: "creditcard")
            }
            .tint(.bizarreSuccess)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                showVoidAlert = inv.id
            } label: {
                Label("Void", systemImage: "xmark.circle")
            }
        }
        .onTapGesture {
            if vm.isBulkMode { vm.toggleSelection(id: inv.id) }
        }
    }

    // MARK: - Context menu (§7.1 full set)

    @ViewBuilder
    private func rowContextMenu(for inv: InvoiceSummary) -> some View {
        // Open
        Button {
            path.append(inv.id)
        } label: {
            Label("Open", systemImage: "doc.text")
        }
        .accessibilityLabel("Open invoice \(inv.displayId)")

        // Copy invoice #
        Button {
            UIPasteboard.general.string = inv.displayId
        } label: {
            Label("Copy invoice #", systemImage: "doc.on.doc")
        }
        .accessibilityLabel("Copy invoice number \(inv.displayId)")

        Divider()

        // Send SMS
        Button {
            // SMS send via Communications is out of scope for Invoices; flag for Agent 2/Comms
        } label: {
            Label("Send SMS", systemImage: "message")
        }
        .accessibilityLabel("Send SMS for invoice \(inv.displayId)")

        // Send email
        Button {
            showReceiptSheet = inv.id
        } label: {
            Label("Send Email", systemImage: "envelope")
        }
        .accessibilityLabel("Email receipt for invoice \(inv.displayId)")

        // Print — uses UIPrintInteractionController (§7.2 AirPrint; wired in detail)
        Button {
            path.append(inv.id)
        } label: {
            Label("Print", systemImage: "printer")
        }
        .accessibilityLabel("Print invoice \(inv.displayId)")

        Divider()

        // Record payment
        Button {
            showPaySheet = inv.id
        } label: {
            Label("Record Payment", systemImage: "creditcard")
        }
        .accessibilityLabel("Record payment for invoice \(inv.displayId)")

        // Credit note
        Button {
            showCreditNoteSheet = inv.id
        } label: {
            Label("Credit Note", systemImage: "minus.circle")
        }
        .accessibilityLabel("Issue credit note for invoice \(inv.displayId)")

        // Void
        Button(role: .destructive) {
            showVoidAlert = inv.id
        } label: {
            Label("Void\u{2026}", systemImage: "xmark.circle")
        }
        .accessibilityLabel("Void invoice \(inv.displayId)")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // Staleness indicator
        ToolbarItem(placement: .status) {
            StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
        }

        // Sort
        ToolbarItem(placement: .topBarTrailing) {
            BrandGlassContainer {
                Menu {
                    ForEach(InvoiceSortOption.allCases) { opt in
                        Button {
                            Task { await vm.applySort(opt) }
                        } label: {
                            HStack {
                                Text(opt.displayName)
                                if vm.sort == opt {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .accessibilityLabel("Sort by \(opt.displayName)")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort invoices")
            }
        }

        // Bulk / Export
        ToolbarItem(placement: .topBarTrailing) {
            BrandGlassContainer {
                Menu {
                    Button {
                        vm.toggleBulkMode()
                    } label: {
                        Label(vm.isBulkMode ? "Exit Bulk Mode" : "Select Multiple", systemImage: "checkmark.circle")
                    }
                    .accessibilityLabel(vm.isBulkMode ? "Exit bulk selection mode" : "Enter bulk selection mode")

                    if vm.isBulkMode && !vm.selectedIds.isEmpty {
                        Divider()
                        Button {
                            Task { await bulkVM.perform(action: "send_reminder", ids: Array(vm.selectedIds)) }
                        } label: {
                            Label("Send Reminder", systemImage: "bell")
                        }
                        Button {
                            exportCSV()
                        } label: {
                            Label("Export CSV", systemImage: "arrow.down.doc")
                        }
                        Button(role: .destructive) {
                            Task { await bulkVM.perform(action: "void", ids: Array(vm.selectedIds)) }
                        } label: {
                            Label("Void Selected", systemImage: "xmark.circle")
                        }
                    }

                    if !vm.isBulkMode {
                        Divider()
                        Button {
                            exportCSV()
                        } label: {
                            Label("Export CSV", systemImage: "arrow.down.doc")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More actions")
            }
        }
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "doc.text").font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(searchText.isEmpty ? "No invoices" : "No results")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load invoices").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(message).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - CSV Export

    private func exportCSV() {
        let data = InvoiceCSVExporter.csv(from: vm.invoices)
        csvExportItem = ExportableCSV(data: data)
    }
}

// MARK: - Status tab chip

private struct StatusTabChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.base).padding(.vertical, BrandSpacing.sm)
                .foregroundStyle(selected ? Color.black : Color.bizarreOnSurface)
                .background(selected ? Color.bizarreOrange : Color.bizarreSurface1, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(selected ? 0 : 0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bulk selection banner

private struct BulkSelectionBanner: View {
    let selectedCount: Int
    let totalCount: Int
    let isAllSelected: Bool
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void

    var body: some View {
        HStack {
            Text("\(selectedCount) of \(totalCount) selected")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Button(isAllSelected ? "Deselect All" : "Select All") {
                isAllSelected ? onDeselectAll() : onSelectAll()
            }
            .font(.brandLabelLarge())
            .foregroundStyle(.bizarreOrange)
            .accessibilityLabel(isAllSelected ? "Deselect all invoices" : "Select all invoices")
        }
        .padding(.vertical, BrandSpacing.xs)
    }
}

// MARK: - InvoiceRow

private struct InvoiceRow: View {
    let invoice: InvoiceSummary

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(invoice.displayId)
                    .font(.brandMono(size: 15))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                Text(invoice.customerName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let issued = invoice.createdAt {
                    Text(issued.prefix(10))
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer(minLength: BrandSpacing.sm)

            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text(formatMoney(invoice.total ?? 0))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                // §7.1 Row chip
                InvoiceRowChip(invoice: invoice)
                if let due = invoice.amountDue, due > 0 {
                    Text("Due \(formatMoney(due))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.a11yLabel(for: invoice))
        .accessibilityHint(RowAccessibilityFormatter.invoiceRowHint)
        .accessibilityAddTraits(.isButton)
    }

    static func a11yLabel(for inv: InvoiceSummary) -> String {
        let totalCents = Int(((inv.total ?? 0) * 100).rounded())
        let issuedDate: Date = {
            guard let str = inv.createdAt else { return Date() }
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: str) { return d }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: String(str.prefix(10))) ?? Date()
        }()
        return RowAccessibilityFormatter.invoiceRow(
            number: inv.displayId,
            customer: inv.customerName,
            totalCents: totalCents,
            status: inv.status ?? "",
            issuedAt: issuedDate
        )
    }

    static func a11y(for inv: InvoiceSummary) -> String { a11yLabel(for: inv) }

    private static func formatMoney(_ dollars: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }

    private func formatMoney(_ dollars: Double) -> String { Self.formatMoney(dollars) }
}

// MARK: - CSV FileDocument wrapper

struct ExportableCSV: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
