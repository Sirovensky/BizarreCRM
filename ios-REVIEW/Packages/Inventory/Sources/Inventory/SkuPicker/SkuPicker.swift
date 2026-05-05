import Foundation
import Observation
import Core
import Networking

// MARK: - ViewModel

/// §6.8 — Reusable SKU search + recent-10 picker ViewModel.
/// Referenced by POS, service part mapping, and inventory write flows.
@MainActor
@Observable
public final class SkuPickerViewModel {
    public var searchText: String = "" {
        didSet { scheduleSearch() }
    }
    public private(set) var results: [SkuSearchResult] = []
    public private(set) var isSearching: Bool = false
    public private(set) var recentSkus: [SkuSearchResult] = []

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    private static let recentDefaultsKey = "sku.picker.recent"
    private static let maxRecent = 10

    public init(api: APIClient) {
        self.api = api
        loadRecents()
    }

    // MARK: Debounced search (300ms)

    private func scheduleSearch() {
        debounceTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            isSearching = false
            return
        }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard !Task.isCancelled, let self else { return }
            await self.performSearch(query: query)
        }
    }

    /// Internal — exposed to tests via `_performSearchForTesting`.
    func _performSearch(query: String) async {
        await performSearch(query: query)
    }

    private func performSearch(query: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await api.searchSkus(keyword: query)
        } catch {
            AppLog.ui.error("SKU search failed: \(error.localizedDescription, privacy: .public)")
            results = []
        }
    }

    // MARK: Selection & recents

    /// Call when user selects a result. Records it to the recent list.
    public func select(_ result: SkuSearchResult) {
        recordRecent(result)
    }

    private func recordRecent(_ result: SkuSearchResult) {
        var list = recentSkus.filter { $0.id != result.id }
        list.insert(result, at: 0)
        if list.count > Self.maxRecent { list = Array(list.prefix(Self.maxRecent)) }
        recentSkus = list
        persistRecents(list)
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentDefaultsKey),
              let decoded = try? JSONDecoder().decode([SkuSearchResult].self, from: data)
        else { return }
        recentSkus = decoded
    }

    private func persistRecents(_ list: [SkuSearchResult]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentDefaultsKey)
    }

    public func clearSearch() {
        searchText = ""
        results = []
    }
}

// Make SkuSearchResult Encodable so we can persist recents.
// Uses a local CodingKeys enum since the one in Networking is file-private.
private enum SkuResultKeys: String, CodingKey {
    case id, sku, name
    case inStock = "in_stock"
    case retailPrice = "retail_price"
}

extension SkuSearchResult: Encodable {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: SkuResultKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sku, forKey: .sku)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(inStock, forKey: .inStock)
        try c.encodeIfPresent(retailPrice, forKey: .retailPrice)
    }
}

// MARK: - View

#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// §6.8 — Reusable SKU picker component.
/// Presents a search field with 300ms debounce + barcode scan button + Recent 10.
/// Usage: embed in a sheet or navigation destination; pass `onSelect` to get the result.
public struct SkuPicker: View {
    @State private var vm: SkuPickerViewModel
    @State private var showingBarcodeScanner: Bool = false
    let onSelect: (SkuSearchResult) -> Void

    public init(api: APIClient, onSelect: @escaping (SkuSearchResult) -> Void) {
        _vm = State(wrappedValue: SkuPickerViewModel(api: api))
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
            Divider()
            resultsList
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .sheet(isPresented: $showingBarcodeScanner) {
            InventoryBarcodeScanSheet { value in
                vm.searchText = value
                showingBarcodeScanner = false
            }
        }
    }

    // MARK: - Search bar (Liquid Glass chrome)

    private var searchBar: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            TextField("Search SKU or name…", text: $vm.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search SKU or item name")

            if vm.isSearching {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Searching")
            } else if !vm.searchText.isEmpty {
                Button { vm.clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            Button {
                showingBarcodeScanner = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .foregroundStyle(.bizarreOrange)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Scan barcode")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if vm.searchText.isEmpty {
            recentsSection
        } else if vm.results.isEmpty && !vm.isSearching {
            noResultsState
        } else {
            List(vm.results) { result in
                skuRow(result)
                    .listRowBackground(Color.bizarreSurface1)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var recentsSection: some View {
        if vm.recentSkus.isEmpty {
            Spacer()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "clock")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("No recent SKUs")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Spacer()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
                List(vm.recentSkus) { result in
                    skuRow(result)
                        .listRowBackground(Color.bizarreSurface1)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func skuRow(_ result: SkuSearchResult) -> some View {
        Button {
            vm.select(result)
            onSelect(result)
        } label: {
            HStack(spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(result.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(result.sku)
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer(minLength: BrandSpacing.sm)
                if let stock = result.inStock {
                    Text("\(stock)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(stock > 0 ? .bizarreSuccess : .bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, BrandSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.displayName), SKU \(result.sku), in stock: \(result.inStock.map(String.init) ?? "unknown")")
    }

    private var noResultsState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36)).foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No results for \"\(vm.searchText)\"")
                .font(.brandBodyLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
