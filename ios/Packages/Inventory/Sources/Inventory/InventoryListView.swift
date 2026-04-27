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
    @State private var showingImport: Bool = false
    @State private var showingReceiveItems: Bool = false
    @State private var showingFilterDrawer: Bool = false
    @State private var multiSelection: Set<Int64> = []
    @State private var isBatchSelectMode: Bool = false
    @State private var showingAdjust: Bool = false
    @State private var adjustTargetId: Int64?
    @State private var adjustTargetName: String = ""
    /// §6.5 HID scanner — toast shown when barcode resolves to nothing
    @State private var hidScanErrorMessage: String?
    /// §6.5 Tab-bar / toolbar quick scan — presents camera scanner sheet
    @State private var showingQuickScan: Bool = false
    /// §6.1 Columns picker (iPad/Mac) — persisted column visibility set
    @State private var columnSet: InventoryColumnSet = .load()
    @State private var showingColumnsPicker: Bool = false
    private let detailRepo: InventoryDetailRepository
    private let api: APIClient?

    // §6.1 Tab: All / Products / Parts (not Services — services use Settings).
    private enum ItemTypeTab: String, CaseIterable {
        case all      = "All"
        case products = "Products"
        case parts    = "Parts"

        var inventoryFilter: InventoryFilter {
            switch self {
            case .all:      return .all
            case .products: return .product
            case .parts:    return .part
            }
        }
    }
    @State private var selectedTab: ItemTypeTab = .all

    public init(repo: InventoryRepository, detailRepo: InventoryDetailRepository, api: APIClient? = nil) {
        self.detailRepo = detailRepo
        self.api = api
        _vm = State(wrappedValue: InventoryListViewModel(repo: repo, api: api))
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
                // §6.5 HID scanner — invisible field captures external Bluetooth scanner input
                #if canImport(UIKit)
                HIDScannerField { code in
                    Task { @MainActor in
                        await handleHIDScan(code: code, appendPath: { id in path.append(id) })
                    }
                }
                .frame(width: 0, height: 0)
                #endif
                VStack(spacing: 0) {
                    // §6.1 Tab bar — All / Products / Parts
                    itemTypeTabBar
                        .padding(.vertical, BrandSpacing.xs)
                    // §6.1 Collapsible filter drawer
                    InventoryFilterDrawer(
                        filter: filterBinding,
                        isExpanded: $showingFilterDrawer,
                        onApply: { Task { await vm.load() } }
                    )
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
            .searchable(text: $searchText, prompt: "Search by name, SKU, UPC, manufacturer")
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
            .sheet(isPresented: adjustSheetBinding) {
                if let api, let targetId = adjustTargetId {
                    InventoryAdjustSheet(
                        itemId: targetId,
                        itemName: adjustTargetName,
                        api: api,
                        onSuccess: { Task { await vm.refresh() } }
                    )
                }
            }
            // §6.5 Quick scan sheet
            .sheet(isPresented: $showingQuickScan) {
                if let api {
                    InventoryQuickScanSheet(api: api)
                }
            }
            // §6.1 Import CSV/JSON sheet
            .sheet(isPresented: $showingImport, onDismiss: { Task { await vm.refresh() } }) {
                if let api { InventoryImportCSVSheet(api: api) }
            }
            // §6.1 Receive items quick modal
            .sheet(isPresented: $showingReceiveItems, onDismiss: { Task { await vm.refresh() } }) {
                if let api { InventoryReceiveItemsSheet(api: api) }
            }
        }
    }

    // MARK: - iPad (regular)

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    itemTypeTabBar
                        .padding(.vertical, BrandSpacing.xs)
                    InventoryFilterDrawer(
                        filter: filterBinding,
                        isExpanded: $showingFilterDrawer,
                        onApply: { Task { await vm.load() } }
                    )
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
            .searchable(text: $searchText, prompt: "Search by name, SKU, UPC, manufacturer")
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
            .sheet(isPresented: adjustSheetBinding) {
                if let api, let targetId = adjustTargetId {
                    InventoryAdjustSheet(
                        itemId: targetId,
                        itemName: adjustTargetName,
                        api: api,
                        onSuccess: { Task { await vm.refresh() } }
                    )
                }
            }
            // §6.1 Columns picker sheet (iPad/Mac)
            .sheet(isPresented: $showingColumnsPicker) {
                InventoryColumnsPickerSheet(columnSet: $columnSet)
                    .presentationDetents([.medium])
            }
            // §6.5 Quick scan sheet
            .sheet(isPresented: $showingQuickScan) {
                if let api {
                    InventoryQuickScanSheet(api: api)
                }
            }
            // §6.1 Import CSV/JSON sheet (iPad)
            .sheet(isPresented: $showingImport, onDismiss: { Task { await vm.refresh() } }) {
                if let api { InventoryImportCSVSheet(api: api) }
            }
            // §6.1 Receive items quick modal (iPad)
            .sheet(isPresented: $showingReceiveItems, onDismiss: { Task { await vm.refresh() } }) {
                if let api { InventoryReceiveItemsSheet(api: api) }
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

    // MARK: - §6.1 Item-type tab bar (All / Products / Parts)

    private var itemTypeTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(ItemTypeTab.allCases, id: \.rawValue) { tab in
                    InventoryFilterChip(
                        label: tab.rawValue,
                        selected: selectedTab == tab
                    ) {
                        guard selectedTab != tab else { return }
                        selectedTab = tab
                        Task { await vm.applyFilter(tab.inventoryFilter) }
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
        }
        .accessibilityLabel("Item type filter tabs")
    }

    // MARK: - Adjust sheet binding

    private var adjustSheetBinding: Binding<Bool> {
        Binding(
            get: { showingAdjust && adjustTargetId != nil },
            set: { if !$0 { showingAdjust = false } }
        )
    }

    // MARK: - Filter binding passthrough

    private var filterBinding: Binding<InventoryAdvancedFilter> {
        Binding(
            get: { vm.advanced },
            set: { vm.advanced = $0 }
        )
    }

    // MARK: - §6.5 HID scanner handler

    /// Resolves a scanned barcode string to an inventory item and navigates to its detail.
    /// Fires a haptic via `HIDScannerField` before this is called.
    @MainActor
    private func handleHIDScan(code: String, appendPath: @escaping (Int64) -> Void) async {
        guard let api else { return }
        do {
            let item = try await api.inventoryItemByBarcode(code)
            appendPath(item.id)
        } catch {
            // Not found — surface briefly
            hidScanErrorMessage = "No item found for code "\(code)""
            AppLog.ui.notice("HID scan no match: \(code, privacy: .public)")
        }
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
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 0, style: .continuous),
                    tint: .bizarreOrange.opacity(0.3))
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
        // §6.5 Tab-bar / toolbar quick scan — opens camera scanner to resolve barcode → item detail
        ToolbarItem(placement: .primaryAction) {
            Button { showingQuickScan = true } label: {
                Image(systemName: "barcode.viewfinder")
            }
            .keyboardShortcut("B", modifiers: [.command, .shift])
            .accessibilityLabel("Quick scan barcode")
            .accessibilityIdentifier("inventory.quickscan")
            .disabled(api == nil)
        }
        // §6.1 Sort menu
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Picker("Sort by", selection: Binding(
                    get: { vm.sort },
                    set: { newSort in Task { await vm.applySort(newSort) } }
                )) {
                    ForEach(InventorySortOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort inventory list")
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
        // §6.1 Receive items quick modal (scan/manual, no PO required)
        ToolbarItem(placement: .secondaryAction) {
            Button { showingReceiveItems = true } label: {
                Label("Receive items", systemImage: "arrow.down.circle")
            }
            .accessibilityLabel("Receive items into stock")
            .disabled(api == nil)
        }
        // §6.1 Import CSV
        ToolbarItem(placement: .secondaryAction) {
            Button { showingImport = true } label: {
                Label("Import CSV", systemImage: "doc.badge.plus")
            }
            .accessibilityLabel("Import inventory from CSV file")
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
        // §6.1 Columns picker — iPad/Mac only
        if !Platform.isCompact {
            ToolbarItem(placement: .secondaryAction) {
                Button { showingColumnsPicker = true } label: {
                    Label("Columns", systemImage: "tablecells")
                }
                .accessibilityLabel("Choose visible columns")
                .accessibilityIdentifier("inventory.columns")
            }
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
            // §6.1 Enhanced empty state with CTAs
            InventoryEmptyState(
                isSearching: !searchText.isEmpty,
                hasFilters: vm.hasActiveAdvancedFilters,
                onImport: { showingImport = true },
                onCreate: { showingCreate = true }
            )
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
            InventoryRow(item: item, agingTier: vm.agingTierMap[item.id], onAdjust: nil)
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
                // §6.1 Quick stock adjust inline — only if api available
                InventoryRow(item: item, agingTier: vm.agingTierMap[item.id], onAdjust: api != nil ? {
                    adjustTargetId = item.id
                    adjustTargetName = item.displayName
                    showingAdjust = true
                } : nil)
            }
            .hoverEffect(.highlight)
            .contextMenu { rowContextMenu(for: item) }
        } else {
            Button { onSelect(item.id) } label: {
                InventoryRow(item: item, agingTier: vm.agingTierMap[item.id], onAdjust: api != nil ? {
                    adjustTargetId = item.id
                    adjustTargetName = item.displayName
                    showingAdjust = true
                } : nil)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .tag(item.id)
            .contextMenu { rowContextMenu(for: item) }
        }
    }

    // MARK: - §6.1 Context menu (Open / Copy SKU / Adjust stock / Create PO / Deactivate / Delete)

    @ViewBuilder
    private func rowContextMenu(for item: InventoryListItem) -> some View {
        Button {
            selected = item.id
        } label: {
            Label("Open", systemImage: "arrow.up.forward.square")
        }
        .accessibilityLabel("Open \(item.displayName)")

        if let sku = item.sku, !sku.isEmpty {
            Button {
                UIPasteboard.general.string = sku
            } label: {
                Label("Copy SKU", systemImage: "doc.on.clipboard")
            }
            .accessibilityLabel("Copy SKU \(sku)")
        }

        Divider()

        if api != nil {
            Button {
                adjustTargetId = item.id
                adjustTargetName = item.displayName
                showingAdjust = true
            } label: {
                Label("Adjust stock", systemImage: "slider.horizontal.3")
            }
            .accessibilityLabel("Adjust stock for \(item.displayName)")

            Button {
                // Handled by §58 PO compose — opens via nav; for now navigate to item detail
                selected = item.id
            } label: {
                Label("Create PO", systemImage: "cart.badge.plus")
            }
            .accessibilityLabel("Create purchase order for \(item.displayName)")

            Divider()

            // §6.4 Deactivate
            Button(role: .destructive) {
                // TODO(phase-4): PATCH /inventory/:id { archived: true }
            } label: {
                Label("Deactivate", systemImage: "archivebox")
            }
            .accessibilityLabel("Deactivate \(item.displayName)")
        }

        Divider()

        Button {
            multiSelection = [item.id]
            isBatchSelectMode = true
            showingBatchEdit = true
        } label: {
            Label("Batch edit", systemImage: "checkmark.circle")
        }
        .disabled(api == nil)
        .accessibilityLabel("Batch edit \(item.displayName)")
    }
}

// MARK: - Row

private struct InventoryRow: View {
    let item: InventoryListItem
    /// §6.8 Aging tier — non-nil when AgeReport data is loaded; nil = still loading or fresh.
    let agingTier: AgingTier?
    /// Non-nil when quick stock-adjust is available (requires api).
    let onAdjust: (() -> Void)?

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
                        .textSelection(.enabled)
                        .lineLimit(1)
                } else if let type = item.itemType, !type.isEmpty {
                    Text(type.capitalized)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                // §6.8 Stale / Dead aging badge
                agingBadge
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

                // §6.1 Quick stock adjust inline +/-
                if let onAdjust {
                    Button(action: onAdjust) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14))
                            .foregroundStyle(.bizarreOrange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quick adjust stock for \(item.displayName)")
                    .padding(.top, BrandSpacing.xxs)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            RowAccessibilityFormatter.inventoryRow(
                sku: item.sku,
                name: item.displayName,
                stock: item.inStock ?? 0,
                retailCents: item.priceCents,
                isLowStock: item.isLowStock
            )
        )
        .accessibilityHint(RowAccessibilityFormatter.inventoryRowHint)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - §6.8 Aging badge (Stale / Dead / Obsolete)

    @ViewBuilder
    private var agingBadge: some View {
        switch agingTier {
        case .slow:
            agingChip(label: "Stale", color: .bizarreWarning)
        case .dead:
            agingChip(label: "Dead", color: .bizarreError)
        case .obsolete:
            agingChip(label: "Obsolete", color: Color.gray)
        default:
            EmptyView()
        }
    }

    private func agingChip(label: String, color: Color) -> some View {
        Text(label)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
            .accessibilityLabel("\(label) stock")
    }

    // MARK: - §6.1 Stock badge: low-stock (critical-low pulse respects Reduce Motion)

    @ViewBuilder
    private var stockBadge: some View {
        let stock = item.inStock ?? 0
        let reorder = item.reorderLevel ?? 0
        let isCriticalLow = item.isLowStock && reorder > 0 && stock == 0

        if isCriticalLow {
            // Out of stock — show "Out of stock" chip
            Text("Out of stock")
                .font(.brandLabelSmall())
                .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                .foregroundStyle(.black)
                .background(.bizarreError, in: Capsule())
                .modifier(CriticalLowPulse())
        } else if item.isLowStock {
            // Low stock — red badge with qty
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

// MARK: - §6.1 Critical-low pulse animation (respects Reduce Motion)

private struct CriticalLowPulse: ViewModifier {
    @State private var pulsing: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1.0 : (pulsing ? 0.5 : 1.0))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { if !reduceMotion { pulsing = true } }
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

// MARK: - §6.1 Enhanced empty state with CTAs

private struct InventoryEmptyState: View {
    let isSearching: Bool
    let hasFilters: Bool
    let onImport: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            if isSearching {
                Text("No results")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Try a different search term.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else if hasFilters {
                Text("No items match your filters")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Adjust or clear filters to see more items.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                Text("No items yet")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Import a CSV or create items manually.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)

                // §6.1 CTAs: Import CSV + Add manually
                HStack(spacing: BrandSpacing.sm) {
                    Button(action: onImport) {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
                            .font(.brandLabelLarge())
                    }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Import inventory items from CSV file")

                    Button(action: onCreate) {
                        Label("Add item", systemImage: "plus")
                            .font(.brandLabelLarge())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Create a new inventory item")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrandSpacing.lg)
    }
}

// MARK: - Error state

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

// MARK: - iPad placeholder

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
