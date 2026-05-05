import Foundation
import Observation
import Core
import Inventory
import Networking

/// Drives the inventory picker panel on the left side of the POS split
/// view (and the "scan or search" section on iPhone). Keeps the cart
/// independent from the catalog plumbing — the cart only sees `CartItem`.
@MainActor
@Observable
public final class PosSearchViewModel {
    public private(set) var results: [InventoryListItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public var query: String = ""

    @ObservationIgnored private let repo: InventoryRepository
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: InventoryRepository) {
        self.repo = repo
    }

    /// Called on initial appear. Pre-loads the first page of recent items
    /// so the picker isn't blank on open.
    public func load() async {
        if results.isEmpty { isLoading = true }
        defer { isLoading = false }
        await fetch()
    }

    public func onQueryChange(_ newValue: String) {
        query = newValue
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await fetch()
        }
    }

    private func fetch() async {
        errorMessage = nil
        do {
            let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
            results = try await repo.list(filter: .all, keyword: keyword.isEmpty ? nil : keyword)
        } catch {
            AppLog.ui.error("POS search failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

/// Map an inventory row to a cart line. Price defaults to `0` when the
/// server didn't hand us a retail price (admin-gated cost-only items) —
/// the cashier then edits the row manually, which is fine.
public enum PosCartMapper {
    public static func cartItem(from inv: InventoryListItem) -> CartItem {
        let price: Decimal
        if let retail = inv.retailPrice {
            price = Decimal(retail)
        } else {
            price = 0
        }
        return CartItem(
            inventoryItemId: inv.id,
            name: inv.displayName,
            sku: inv.sku,
            quantity: 1,
            unitPrice: price
        )
    }
}
