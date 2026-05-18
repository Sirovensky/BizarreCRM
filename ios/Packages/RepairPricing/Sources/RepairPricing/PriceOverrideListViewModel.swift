import Foundation
import Observation
import Networking
import Core

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
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: DELETE may have already reached the server
            // when the task is torn down (sheet dismissed / row swiped away
            // and the list reloaded mid-flight). A red banner would falsely
            // imply the override survives — but the next list reload may
            // show it gone. Stay silent; the next `load()` reconciles.
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
