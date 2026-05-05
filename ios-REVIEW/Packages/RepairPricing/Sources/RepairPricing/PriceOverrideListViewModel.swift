import Foundation
import Observation
import Networking

// MARK: - §43.3 Price Override List ViewModel

/// Backing ViewModel for `PriceOverrideListView` (admin settings screen).
@MainActor
@Observable
public final class PriceOverrideListViewModel {

    // MARK: - State
    public private(set) var overrides: [PriceOverride] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public API

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            overrides = try await api.listPriceOverrides()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func delete(override item: PriceOverride) async {
        do {
            try await api.deletePriceOverride(id: item.id)
            overrides = overrides.filter { $0.id != item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
