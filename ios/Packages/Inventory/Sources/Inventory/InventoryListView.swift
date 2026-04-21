#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

public struct InventoryListView: View {
    @State private var vm: InventoryListViewModel
    @State private var searchText: String = ""
    @State private var path: [Int64] = []
    @State private var selected: Int64?
    @State private var showingCreate: Bool = false
    @State private var showingLowStock: Bool = false
    @State private var showingReceiving: Bool = false
    @State private var showingStocktake: Bool = false
    @State private var showingBatchEdit: Bool = false
    @State private var multiSelection: Set<Int64> = []
    @State private var isBatchSelectMode: Bool = false
    private let detailRepo: InventoryDetailRepository
    private let api: APIClient?

    public init(repo: InventoryRepository, detailRepo: InventoryDetailRepository, api: APIClient? = nil) {
        self.detailRepo = detailRepo
        self.api = api
        _vm = State(wrappedValue: InventoryListViewModel(repo: repo))
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

    // MARK: - iPhone (compact)

    private var compactLayout: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterChips
                        .padding(.vertical, BrandSpacing.sm)
                    if isBatchSelectMode {
                        batchSelectionBanner
                    }
                    listContent { id in path.append(id) }
                }
                if vm.isOffline {
                    OfflineBanner(isOffline: true)
                        .padding(.top, BrandSpacing.xs)
                }
            }
            .navigationTitle("Inventory")
            .searchable(text: $searchText, prompt: "Search by name, SKU, UPC")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task {
                vm.isOffline = !Reachability.shared.isOnline
                await vm.load()
            }
            .refreshable { await vm.refresh() }
            .navigationDestination(for: Int64.self) { id in
                InventoryDetailView(repo: detailRepo, itemId: id, api: api)
            }
            .toolbar { listToolbar }
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
    }

    // MARK: - iPad (regular)

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterChips
                        .padding(.vertical, BrandSpacing.sm)
                    if isBatchSelectMode {
                        batchSelectionBanner
                    }
                    listContent { id in selected = id }
                }
                if vm.isOffline {
                    OfflineBanner(isOffline: true)
                        .padding(.top, BrandSpacing.xs)
                }
            }
            .navigationTitle("Inventory")
            .searchable(text: $searchText, prompt: "Search by name, SKU, UPC")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task {
                vm.isOffline = !Reachability.shared.isOnline
                await vm.load()
            }
            .refreshable { await vm.refresh() }
            .toolbar { listToolbar }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
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
        } detail: {
            if let id = selected {
                NavigationStack {
                    InventoryDetailView(repo: detailRepo, itemId: id, api: api)
                }
            } else {
                EmptyInventoryDetailPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Batch selection banner (Liquid Glass chrome)

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
        .brandGlass(.regular, tint: .bizarreOrange.opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 0, style: .continuous))
    }

    // MARK: - Shared toolbar

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingCreate = true } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("N", modifiers: .command)
            .accessibilityLabel("New item")
            .disabled(api == nil)
        }
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
                Label(isBatchSelectMode ? "Cancel select" : "Select items",
                      systemImage: isBatchSelectMode ? "xmark.circle" : "checkmark.circle")
            }
            .keyboardShortcut("E", modifiers: [.command, .shift])
            .accessibilityLabel(isBatchSelectMode ? "Cancel batch selection" : "Select items for batch edit")
            .disabled(api == nil)
        }
        ToolbarItem(placement: .status) {
            StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func listContent(onSelect: @escaping (Int64) -> Void) -> some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            InventoryErrorState(message: err) { Task { await vm.load() } }
        } else if vm.items.isEmpty && vm.isOffline {
            OfflineEmptyStateView(entityName: "inventory items")
        } else if vm.items.isEmpty {
            InventoryEmptyState(isSearching: !searchText.isEmpty)
        } else {
            List(selection: isBatchSelectMode
                 ? $multiSelection
                 : Binding<Set<Int64>>(
                    get: { selected.map { [$0] } ?? [] },
                    set: { if let id = $0.first { selected = id } }
                 )
            ) {
                ForEach(vm.items) { item in
                    row(for: item, onSelect: onSelect)
                        .listRowBackground(Color.bizarreSurface1)
                        .tag(item.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, isBatchSelectMode ? .constant(.active) : .constant(.inactive))
        }
    }

    @ViewBuilder
    private func row(for item: InventoryListItem, onSelect: @escaping (Int64) -> Void) -> some View {
        if isBatchSelectMode {
            InventoryRow(item: item)
                .contentShape(Rectangle())
                .onTapGesture {
                    if multiSelection.contains(item.id) {
                        multiSelection.remove(item.id)
                    } else {
                        multiSelection.insert(item.id)
                    }
                }
                .overlay(alignment: .leading) {
                    if multiSelection.contains(item.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreOrange)
                            .padding(.leading, BrandSpacing.sm)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.displayName)\(multiSelection.contains(item.id) ? ", selected" : "")")
                .accessibilityAddTraits(multiSelection.contains(item.id) ? .isSelected : [])
        } else if Platform.isCompact {
            NavigationLink(value: item.id) {
                InventoryRow(item: item)
            }
            .hoverEffect(.highlight)
            .contextMenu { rowContextMenu(for: item) }
        } else {
            Button { onSelect(item.id) } label: {
                InventoryRow(item: item)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .tag(item.id)
            .contextMenu { rowContextMenu(for: item) }
        }
    }

    @ViewBuilder
    private func rowContextMenu(for item: InventoryListItem) -> some View {
        // Open / Edit
        Button {
            selected = item.id
        } label: {
            Label("Open", systemImage: "arrow.up.forward.square")
        }
        .accessibilityLabel("Open \(item.displayName)")

        Button {
            selected = item.id
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .accessibilityLabel("Edit \(item.displayName)")

        Divider()

        // §22 domain-relevant actions
        if api != nil {
            Button {
                selected = item.id
                showingAdjust = true
            } label: {
                Label("Adjust Stock", systemImage: "slider.horizontal.3")
            }
            .accessibilityLabel("Adjust stock for \(item.displayName)")

            Button {
                // TODO: POST /inventory/:id/reorder — Phase 4
            } label: {
                Label("Reorder", systemImage: "cart.badge.plus")
            }
            .accessibilityLabel("Reorder \(item.displayName)")

            Button {
                // TODO: navigate to stock history — Phase 4
            } label: {
                Label("View History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityLabel("View stock history for \(item.displayName)")

            Divider()

            Button {
                // TODO: PATCH /inventory/:id { archived: true } — Phase 4
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .accessibilityLabel("Archive \(item.displayName)")
        }

        Divider()

        Button {
            multiSelection = [item.id]
            isBatchSelectMode = true
            showingBatchEdit = true
        } label: {
            Label("Batch Edit", systemImage: "checkmark.circle")
        }
        .disabled(api == nil)
        .accessibilityLabel("Batch edit \(item.displayName)")
    }

    @State private var showingAdjust: Bool = false

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(InventoryFilter.allCases) { option in
                    InventoryFilterChip(label: option.displayName, selected: vm.filter == option) {
                        Task { await vm.applyFilter(option) }
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
        }
    }
}

// MARK: - Row

private struct InventoryRow: View {
    let item: InventoryListItem

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
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
                } else if let type = item.itemType, !type.isEmpty {
                    Text(type.capitalized)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
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
                stockBadge
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.displayName)\(item.sku.map { ", SKU \($0)" } ?? ""). \(stockAccessibilityLabel)"
        )
    }

    @ViewBuilder
    private var stockBadge: some View {
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

    private var stockAccessibilityLabel: String {
        let stock = item.inStock ?? 0
        if item.isLowStock { return "Low stock, \(stock) remaining" }
        if stock > 0 { return "\(stock) in stock" }
        return "Out of stock"
    }

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents / 100)"
    }
}

// MARK: - Filter chip

private struct InventoryFilterChip: View {
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
                .overlay(
                    Capsule().strokeBorder(
                        Color.bizarreOutline.opacity(selected ? 0 : 0.6), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) filter\(selected ? ", selected" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Empty / Error states

private struct InventoryErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
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
            Button("Try again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InventoryEmptyState: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(isSearching ? "No results" : "No items")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyInventoryDetailPlaceholder: View {
    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Select an item")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Pick an inventory item from the list to see full details.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }
        }
    }
}
#endif
