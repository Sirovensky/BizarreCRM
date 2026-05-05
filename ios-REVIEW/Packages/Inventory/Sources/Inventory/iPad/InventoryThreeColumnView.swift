#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

/// iPad-only 3-column NavigationSplitView:
///   column 1 — category sidebar (All / Products / Parts / Low Stock)
///   column 2 — item list (InventoryTableView in table mode, list otherwise)
///   column 3 — item detail (InventoryDetailView)
///
/// Ownership: §22 iPad polish (Inventory).
/// ONLY instantiated when `!Platform.isCompact`.
public struct InventoryThreeColumnView: View {
    // MARK: - Dependencies

    private let repo: InventoryRepository
    private let detailRepo: InventoryDetailRepository
    private let api: APIClient?

    // MARK: - State

    @State private var vm: InventoryListViewModel
    @State private var selectedFilter: InventoryFilter = .all
    @State private var selectedItemId: Int64?
    @State private var searchText: String = ""
    @State private var showingCreate: Bool = false
    @State private var showingLowStock: Bool = false
    @State private var showingReceiving: Bool = false
    @State private var showingStocktake: Bool = false
    @State private var showingBatchEdit: Bool = false
    @State private var multiSelection: Set<Int64> = []
    @State private var isBatchSelectMode: Bool = false
    @State private var useTableStyle: Bool = true

    // MARK: - Init

    public init(
        repo: InventoryRepository,
        detailRepo: InventoryDetailRepository,
        api: APIClient? = nil
    ) {
        self.repo = repo
        self.detailRepo = detailRepo
        self.api = api
        _vm = State(wrappedValue: InventoryListViewModel(repo: repo))
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            categorySidebar
        } content: {
            itemListColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            vm.isOffline = !Reachability.shared.isOnline
            await vm.load()
        }
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
            if let api { InventoryCreateView(api: api) }
        }
        .sheet(isPresented: $showingLowStock) {
            if let api { InventoryLowStockView(api: api) }
        }
        .sheet(isPresented: $showingReceiving) {
            if let api { ReceivingListView(api: api) }
        }
        .sheet(isPresented: $showingStocktake) {
            if let api { StocktakeStartView(api: api) }
        }
        .sheet(isPresented: $showingBatchEdit, onDismiss: {
            isBatchSelectMode = false
            multiSelection = []
            Task { await vm.refresh() }
        }) {
            if let api {
                BatchEditSheet(api: api, selectedIds: Array(multiSelection))
            }
        }
    }

    // MARK: - Column 1: Category sidebar

    @ViewBuilder
    private func filterRow(_ filter: InventoryFilter) -> some View {
        let isSelected = selectedFilter == filter
        Button {
            selectedFilter = filter
        } label: {
            HStack {
                Label(filter.displayName, systemImage: filterIcon(filter))
                    .font(.brandBodyLarge())
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurface)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.bizarreOrange)
                }
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.bizarreOrange.opacity(0.12) : Color.clear)
        .hoverEffect(.highlight)
        .accessibilityLabel(filter.displayName + " filter" + (isSelected ? ", selected" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var categorySidebar: some View {
        ZStack(alignment: .top) {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            List {
                ForEach(InventoryFilter.allCases, id: \.self) { filter in
                    filterRow(filter)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            if vm.isOffline {
                OfflineBanner(isOffline: true)
                    .padding(.top, BrandSpacing.xs)
            }
        }
        .navigationTitle("Inventory")
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreate = true } label: {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("N", modifiers: .command)
                .accessibilityLabel("New item")
                .disabled(api == nil)
            }
        }
        .onChange(of: selectedFilter) { _, newFilter in
            Task { await vm.applyFilter(newFilter) }
        }
    }

    // MARK: - Column 2: Item list

    private var itemListColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                listStyleToggle
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)

                if isBatchSelectMode {
                    batchSelectionBanner
                }

                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.errorMessage {
                    inventoryErrorState(message: err)
                } else if vm.items.isEmpty && vm.isOffline {
                    OfflineEmptyStateView(entityName: "inventory items")
                } else if vm.items.isEmpty {
                    inventoryEmptyState
                } else if useTableStyle {
                    InventoryTableView(
                        items: vm.items,
                        selectedItemId: $selectedItemId,
                        multiSelection: isBatchSelectMode ? $multiSelection : .constant([]),
                        isBatchSelectMode: isBatchSelectMode,
                        api: api,
                        onAdjustStock: { item in
                            selectedItemId = item.id
                        }
                    )
                } else {
                    listStyleContent
                }
            }
        }
        .navigationTitle(selectedFilter.displayName)
        .searchable(text: $searchText, prompt: "Search by name, SKU, UPC")
        .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
        .refreshable { await vm.refresh() }
        .navigationSplitViewColumnWidth(min: 360, ideal: 480, max: 640)
        .toolbar { contentToolbar }
    }

    // MARK: - Column 3: Detail

    private var detailColumn: some View {
        Group {
            if let id = selectedItemId {
                NavigationStack {
                    InventoryDetailView(repo: detailRepo, itemId: id, api: api)
                }
            } else {
                emptyDetailPlaceholder
            }
        }
    }

    // MARK: - List style toggle

    private var listStyleToggle: some View {
        HStack {
            Spacer()
            Picker("View style", selection: $useTableStyle) {
                Image(systemName: "tablecells").tag(true)
                    .accessibilityLabel("Table view")
                Image(systemName: "list.bullet").tag(false)
                    .accessibilityLabel("List view")
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            .accessibilityLabel("Switch between table and list view")
        }
    }

    // MARK: - Batch banner (Liquid Glass chrome)

    private var batchSelectionBanner: some View {
        HStack(spacing: BrandSpacing.sm) {
            Text("\(multiSelection.count) selected")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("\(multiSelection.count) items selected")
            Spacer()
            Button("Edit batch") {
                guard !multiSelection.isEmpty else { return }
                showingBatchEdit = true
            }
            .buttonStyle(BrandGlassButtonStyle())
            .disabled(multiSelection.isEmpty)
            .accessibilityLabel("Edit selected items in batch")
            Button("Cancel") {
                isBatchSelectMode = false
                multiSelection = []
            }
            .buttonStyle(.plain)
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .accessibilityLabel("Cancel batch selection")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular,
                    in: RoundedRectangle(cornerRadius: 0, style: .continuous),
                    tint: .bizarreOrange.opacity(0.3))
    }

    // MARK: - List style content (fallback)

    private var listStyleContent: some View {
        List(selection: isBatchSelectMode
             ? $multiSelection
             : Binding<Set<Int64>>(
                get: { selectedItemId.map { [$0] } ?? [] },
                set: { if let id = $0.first { selectedItemId = id } }
             )
        ) {
            ForEach(vm.items) { item in
                InventoryContextMenu(
                    item: item,
                    api: api,
                    onOpen: { selectedItemId = item.id },
                    onAdjustStock: { selectedItemId = item.id },
                    onArchive: { /* §22 stub — Phase 4 */ }
                ) {
                    ThreeColListRow(item: item, isSelected: selectedItemId == item.id) {
                        selectedItemId = item.id
                    }
                }
                .listRowBackground(Color.bizarreSurface1)
                .tag(item.id)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, isBatchSelectMode ? .constant(.active) : .constant(.inactive))
    }

    // MARK: - Empty / error states

    private var inventoryEmptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(searchText.isEmpty ? "No items" : "No results")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func inventoryErrorState(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
            Text("Couldn't load inventory")
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

    private var emptyDetailPlaceholder: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Select an item")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Pick an inventory item to see full details.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var contentToolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button { showingLowStock = true } label: {
                Label("Low stock", systemImage: "exclamationmark.triangle")
            }
            .keyboardShortcut("L", modifiers: [.command, .shift])
            .accessibilityLabel("View low stock items")
            .disabled(api == nil)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button { showingReceiving = true } label: {
                Label("Receiving", systemImage: "shippingbox.and.arrow.backward")
            }
            .keyboardShortcut("R", modifiers: [.command, .shift])
            .accessibilityLabel("Open receiving orders")
            .disabled(api == nil)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button { showingStocktake = true } label: {
                Label("Stocktake", systemImage: "checklist")
            }
            .keyboardShortcut("T", modifiers: [.command, .shift])
            .accessibilityLabel("Start stocktake")
            .disabled(api == nil)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                isBatchSelectMode.toggle()
                if !isBatchSelectMode { multiSelection = [] }
            } label: {
                Label(
                    isBatchSelectMode ? "Cancel select" : "Select items",
                    systemImage: isBatchSelectMode ? "xmark.circle" : "checkmark.circle"
                )
            }
            .keyboardShortcut("E", modifiers: [.command, .shift])
            .accessibilityLabel(isBatchSelectMode ? "Cancel batch selection" : "Select items for batch edit")
            .disabled(api == nil)
        }
        ToolbarItem(placement: .status) {
            StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
        }
    }

    // MARK: - Helpers

    private func filterIcon(_ filter: InventoryFilter) -> String {
        switch filter {
        case .all:      return "shippingbox"
        case .product:  return "tag"
        case .part:     return "wrench.and.screwdriver"
        case .lowStock: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Simple list row for non-table mode

private struct ThreeColListRow: View {
    let item: InventoryListItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(item.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                    if let sku = item.sku, !sku.isEmpty {
                        Text("SKU \(sku)")
                            .font(.brandMono(size: 13))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: BrandSpacing.sm)
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    if let cents = item.priceCents {
                        Text(formatMoney(cents))
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                    stockLabel
                }
            }
            .padding(.vertical, BrandSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var stockLabel: some View {
        let stock = item.inStock ?? 0
        if item.isLowStock {
            Text("Low · \(stock)")
                .font(.brandLabelSmall())
                .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                .foregroundStyle(.black)
                .background(.bizarreError, in: Capsule())
        } else if stock > 0 {
            Text("\(stock) in stock")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreSuccess)
        } else {
            Text("Out of stock")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents / 100)"
    }
}
#endif
