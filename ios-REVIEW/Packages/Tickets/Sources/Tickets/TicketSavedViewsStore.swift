import Foundation
import Networking

// §4.1 — Saved views: pin filter combos as named chips.
// Stored in UserDefaults (server-backed when endpoint exists per spec).
// Each saved view bundles a TicketListFilter + optional keyword + display name.

/// A pinned filter combo that appears as a named chip in the Tickets list.
public struct TicketSavedView: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var filter: TicketListFilter
    public var keyword: String

    public init(id: UUID = UUID(), name: String, filter: TicketListFilter, keyword: String = "") {
        self.id = id
        self.name = name
        self.filter = filter
        self.keyword = keyword
    }
}

/// Reads and writes saved views from UserDefaults.
/// Thread-safe via `@MainActor` — views are a UI-layer concern.
@MainActor
public final class TicketSavedViewsStore: @unchecked Sendable {

    public static let shared = TicketSavedViewsStore()

    private let key = "com.bizarrecrm.tickets.savedViews"

    /// Currently stored saved views. Observe via `@Observable` wrapper if needed;
    /// here we expose a simple getter/setter pair for the list view.
    public private(set) var savedViews: [TicketSavedView] = []

    private init() {
        load()
    }

    // MARK: - CRUD

    public func add(_ view: TicketSavedView) {
        savedViews.append(view)
        persist()
    }

    public func remove(id: UUID) {
        savedViews.removeAll { $0.id == id }
        persist()
    }

    public func rename(id: UUID, newName: String) {
        guard let idx = savedViews.firstIndex(where: { $0.id == id }) else { return }
        savedViews[idx].name = newName
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([TicketSavedView].self, from: data)
        else { return }
        savedViews = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(savedViews) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
