import Foundation
import Observation
import Networking

// MARK: - §43.4 Service Part Mapping ViewModel

@MainActor
@Observable
public final class ServicePartMappingViewModel {

    // MARK: - SKU search
    public var skuQuery: String = ""
    public private(set) var searchResults: [InventorySearchResult] = []
    public private(set) var isSearching: Bool = false

    // MARK: - Selection
    /// Primary (single-part) SKU.
    public var primarySku: InventorySearchResult?

    /// Multi-part bundle toggle.
    public var isBundleMode: Bool = false

    /// Bundle rows — each skuId + qty.
    public var bundle: [ServicePartBundle] = []

    // MARK: - Save state
    public private(set) var isSaving: Bool = false
    public private(set) var saveError: String?
    public private(set) var savedService: RepairService?

    // MARK: - Private
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let serviceId: Int64
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(api: APIClient, serviceId: Int64) {
        self.api = api
        self.serviceId = serviceId
    }

    // MARK: - Search

    /// Debounced 250 ms inventory search.
    public func onSkuQueryChange(_ query: String) {
        skuQuery = query
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    /// Allow the view to clear search results after selection without bypassing private setter.
    public func clearSearchResults() {
        searchResults = []
    }

    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await api.searchInventoryItems(query: trimmed)
        } catch {
            searchResults = []
        }
    }

    // MARK: - Bundle management (immutable pattern)

    public func addBundleRow() {
        // Start new blank row; user must fill in the SKU via picker
        let newRow = ServicePartBundle(skuId: "", qty: 1)
        bundle = bundle + [newRow]
    }

    public func removeBundleRow(at index: Int) {
        guard bundle.indices.contains(index) else { return }
        var updated = bundle
        updated.remove(at: index)
        bundle = updated
    }

    public func updateBundleRow(at index: Int, skuId: String? = nil, qty: Int? = nil) {
        guard bundle.indices.contains(index) else { return }
        var updated = bundle
        let row = updated[index]
        updated[index] = ServicePartBundle(skuId: skuId ?? row.skuId, qty: qty ?? row.qty)
        bundle = updated
    }

    // MARK: - Save

    /// PATCH service with collected SKU / bundle data.
    public func save() async {
        saveError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let effectiveBundle: [ServicePartBundle] = isBundleMode
                ? bundle.filter { !$0.skuId.isEmpty }
                : []
            let req = UpdateServicePartsRequest(
                primarySkuId: isBundleMode ? nil : primarySku?.sku,
                bundle: effectiveBundle
            )
            savedService = try await api.updateServiceParts(serviceId: serviceId, body: req)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
