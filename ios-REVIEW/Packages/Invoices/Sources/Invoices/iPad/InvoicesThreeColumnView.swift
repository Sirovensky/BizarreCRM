#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

// §22 — iPad 3-column layout: filter sidebar | invoice list | detail+inspector

/// Full-width iPad layout using `NavigationSplitView` with three columns:
///
/// 1. **Sidebar** — `InvoiceFilter` picker with Liquid Glass chrome.
/// 2. **Content** — `InvoiceListColumn` (search + list).
/// 3. **Detail** — `InvoiceDetailView` + trailing `InvoiceInspector`.
///
/// Gate: only instantiate this view when `!Platform.isCompact`. The existing
/// `InvoiceListView` continues to own the compact (iPhone) path.
public struct InvoicesThreeColumnView: View {

    // MARK: - State

    @State private var vm: InvoiceListViewModel
    @State private var searchText: String = ""
    @State private var selectedFilter: InvoiceFilter = .all
    @State private var selectedId: Int64?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showNewInvoice: Bool = false

    // MARK: - Dependencies (stored, not @State, because they are injected)

    @ObservationIgnored private let detailRepo: InvoiceDetailRepository
    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(repo: InvoiceRepository, detailRepo: InvoiceDetailRepository, api: APIClient) {
        self.detailRepo = detailRepo
        self.api = api
        _vm = State(wrappedValue: InvoiceListViewModel(repo: repo))
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            filterSidebar
        } content: {
            invoiceListColumn
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        // Keyboard shortcuts live at the root so they fire regardless of focus.
        .modifier(InvoiceKeyboardShortcuts(
            onNew: { showNewInvoice = true },
            onSearch: { columnVisibility = .all },
            onRefresh: { Task { await vm.refresh() } },
            onPrint: { /* print handled inside detail pane */ }
        ))
        .task {
            vm.isOffline = !Reachability.shared.isOnline
            await vm.load()
        }
        .refreshable { await vm.refresh() }
    }

    // MARK: - Sidebar (column 1)

    private var filterSidebar: some View {
        ZStack(alignment: .top) {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                offlineBannerIfNeeded
                List(InvoiceFilter.allCases) { filter in
                    InvoiceFilterRow(filter: filter, selected: selectedFilter == filter) {
                        selectedFilter = filter
                        Task { await vm.applyFilter(filter) }
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    .hoverEffect(.highlight)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Invoices")
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                BrandGlassContainer {
                    Button {
                        showNewInvoice = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New invoice")
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
        }
    }

    // MARK: - Invoice list (column 2)

    private var invoiceListColumn: some View {
        ZStack(alignment: .top) {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            invoiceListContent
        }
        .navigationTitle(selectedFilter.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search invoices")
        .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
        .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 500)
        .toolbar {
            ToolbarItem(placement: .status) {
                StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
            }
        }
    }

    @ViewBuilder
    private var invoiceListContent: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorState(message: err)
        } else if vm.invoices.isEmpty && vm.isOffline {
            OfflineEmptyStateView(entityName: "invoices")
        } else if vm.invoices.isEmpty {
            emptyState
        } else {
            List(vm.invoices, selection: $selectedId) { inv in
                InvoiceContextMenu(invoice: inv, api: api) {
                    Task { await vm.refresh() }
                } content: {
                    InvoiceThreeColRow(invoice: inv, isSelected: selectedId == inv.id)
                        .tag(inv.id)
                }
                .listRowBackground(
                    selectedId == inv.id
                        ? Color.bizarreOrange.opacity(0.12)
                        : Color.bizarreSurface1
                )
                .hoverEffect(.highlight)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Detail pane (column 3)

    @ViewBuilder
    private var detailPane: some View {
        if let id = selectedId {
            iPadDetailWithInspector(invoiceId: id)
        } else {
            emptyDetailPlaceholder
        }
    }

    private func iPadDetailWithInspector(invoiceId: Int64) -> some View {
        HStack(spacing: 0) {
            InvoiceDetailView(repo: detailRepo, invoiceId: invoiceId, api: api)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            InvoiceInspector(invoiceId: invoiceId, repo: detailRepo)
                .frame(width: 280)
        }
    }

    // MARK: - Helper views

    @ViewBuilder
    private var offlineBannerIfNeeded: some View {
        if vm.isOffline {
            OfflineBanner(isOffline: true)
        }
    }

    private var emptyDetailPlaceholder: some View {
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
                Text("Choose an invoice from the list to view its details.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xxl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(searchText.isEmpty ? "No invoices" : "No results")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load invoices")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
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

// MARK: - Filter Sidebar Row

private struct InvoiceFilterRow: View {
    let filter: InvoiceFilter
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: filter.systemIcon)
                    .frame(width: 24)
                    .foregroundStyle(selected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                Text(filter.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(selected ? Color.bizarreOrange : Color.bizarreOnSurface)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.displayName) invoices filter")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

private extension InvoiceFilter {
    var systemIcon: String {
        switch self {
        case .all:     return "tray.2"
        case .paid:    return "checkmark.circle"
        case .unpaid:  return "circle"
        case .partial: return "circle.lefthalf.filled"
        case .overdue: return "exclamationmark.circle"
        }
    }
}

// MARK: - 3-Col List Row

private struct InvoiceThreeColRow: View {
    let invoice: InvoiceSummary
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(invoice.displayId)
                    .font(.brandMono(size: 14))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                Spacer(minLength: BrandSpacing.sm)
                Text(formatMoney(invoice.total ?? 0))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }

            HStack(alignment: .center) {
                Text(invoice.customerName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Spacer()
                statusCapsule
            }

            if let issued = invoice.createdAt {
                Text(String(issued.prefix(10)))
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var statusCapsule: some View {
        let (bg, fg) = statusColors(for: invoice.statusKind)
        let name = invoice.status.map { $0.capitalized } ?? "—"
        return Text(name)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
            .accessibilityLabel("Status: \(name)")
    }

    private func statusColors(for kind: InvoiceSummary.Status) -> (Color, Color) {
        switch kind {
        case .paid:    return (.bizarreSuccess, .black)
        case .partial: return (.bizarreWarning, .black)
        case .unpaid:  return (.bizarreError,   .black)
        case .void_:   return (.bizarreOnSurfaceMuted, .bizarreSurfaceBase)
        case .other:   return (.bizarreSurface2, .bizarreOnSurface)
        }
    }

    private var a11yLabel: String {
        let amount = formatMoney(invoice.total ?? 0)
        let status = invoice.status.map { $0.capitalized } ?? "Unknown"
        let date = invoice.createdAt.map { String($0.prefix(10)) } ?? ""
        return "\(invoice.displayId), \(invoice.customerName), \(amount), \(status), issued \(date)"
    }

    private func formatMoney(_ dollars: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }
}
#endif
