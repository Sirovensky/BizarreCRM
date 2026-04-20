#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

public struct InventoryListView: View {
    @State private var vm: InventoryListViewModel
    @State private var searchText: String = ""
    @State private var path: [Int64] = []
    @State private var selected: Int64?
    @State private var showingCreate: Bool = false
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
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterChips
                        .padding(.vertical, BrandSpacing.sm)
                    listContent { id in path.append(id) }
                }
            }
            .navigationTitle("Inventory")
            .searchable(text: $searchText, prompt: "Search by name, SKU, UPC")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .navigationDestination(for: Int64.self) { id in
                InventoryDetailView(repo: detailRepo, itemId: id, api: api)
            }
            .toolbar { newItemToolbar }
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
                if let api {
                    InventoryCreateView(api: api)
                }
            }
        }
    }

    // MARK: - iPad (regular)

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterChips
                        .padding(.vertical, BrandSpacing.sm)
                    listContent { id in selected = id }
                }
            }
            .navigationTitle("Inventory")
            .searchable(text: $searchText, prompt: "Search by name, SKU, UPC")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .toolbar { newItemToolbar }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
                if let api {
                    InventoryCreateView(api: api)
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

    // MARK: - Shared toolbar / content

    private var newItemToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingCreate = true } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("N", modifiers: .command)
            .accessibilityLabel("New item")
            .disabled(api == nil)
        }
    }

    @ViewBuilder
    private func listContent(onSelect: @escaping (Int64) -> Void) -> some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            InventoryErrorState(message: err) { Task { await vm.load() } }
        } else if vm.items.isEmpty {
            InventoryEmptyState(isSearching: !searchText.isEmpty)
        } else {
            List(selection: Binding<Int64?>(
                get: { Platform.isCompact ? nil : selected },
                set: { if let id = $0 { selected = id } }
            )) {
                ForEach(vm.items) { item in
                    row(for: item, onSelect: onSelect)
                        .listRowBackground(Color.bizarreSurface1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func row(for item: InventoryListItem, onSelect: @escaping (Int64) -> Void) -> some View {
        if Platform.isCompact {
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
        Button {
            selected = item.id
        } label: {
            Label("Open", systemImage: "arrow.up.forward.square")
        }
        // "Edit" is a deep-link into the detail sheet — the detail view owns
        // the edit sheet state. We jump there by selecting the row.
        Button {
            selected = item.id
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        // Stock-adjust endpoint exists on the server but is gated behind an
        // admin/manager permission; wire it in a later phase. Shown disabled
        // so operators know it's coming without expecting it to work yet.
        Button {} label: {
            Label("Adjust stock", systemImage: "slider.horizontal.3")
        }
        .disabled(true)
    }

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

