import Foundation

// §1.5 Pin-from-overflow drag — NavPinStore
//
// Single source of truth for the user's pinned primary-nav order.
// Persists to UserDefaults at key `nav.primaryOrder` (JSON array of NavPinItem).
//
// Hard caps:
//   - iPhone (isCompact): 5 pins
//   - iPad / Mac:         8 pins
//
// NEXT-STEP: In RootView.swift / MainShellView, inject NavPinStore.shared and
// read `store.pinnedItems` to build the dynamic primary tab list.  Observe via
// `@State private var store = NavPinStore.shared` (already @Observable).

import SwiftUI

private let kDefaultsKey = "nav.primaryOrder"

/// Observable, @MainActor store that manages the ordered list of pinned nav destinations.
///
/// `@Observable` lets SwiftUI views react to `pinnedItems` changes automatically.
/// All mutations are synchronous on the main actor — no concurrency surprises.
@MainActor
@Observable
public final class NavPinStore {

    // MARK: - Shared instance

    public static let shared = NavPinStore()

    // MARK: - State (observed by SwiftUI automatically via @Observable)

    public private(set) var pinnedItems: [NavPinItem] = []

    // MARK: - Private

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Init

    /// Public memberwise init for testing with an isolated UserDefaults suite.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.pinnedItems = load()
    }

    // MARK: - Public API

    /// Returns the currently pinned items in display order.
    public func pinned() -> [NavPinItem] {
        pinnedItems
    }

    /// Pin `item` at the end of the primary nav, respecting the platform cap.
    /// Silent no-op if already pinned or the cap is reached.
    public func pin(_ item: NavPinItem) {
        guard !pinnedItems.contains(where: { $0.id == item.id }) else { return }
        guard pinnedItems.count < cap else { return }
        pinnedItems.append(item)
        persist()
    }

    /// Remove the item with the given id from primary nav.
    /// Silent no-op if not pinned.
    public func unpin(id: String) {
        let before = pinnedItems.count
        pinnedItems.removeAll { $0.id == id }
        if pinnedItems.count != before { persist() }
    }

    /// Move a pinned item from `fromIndex` to `toIndex`.
    /// Out-of-range indices are silently ignored.
    public func reorder(from fromIndex: Int, to toIndex: Int) {
        guard pinnedItems.indices.contains(fromIndex),
              pinnedItems.indices.contains(toIndex),
              fromIndex != toIndex
        else { return }
        let item = pinnedItems.remove(at: fromIndex)
        pinnedItems.insert(item, at: toIndex)
        persist()
    }

    // MARK: - Cap

    /// Maximum number of pinned items for the current platform.
    public var cap: Int {
        Platform.isCompact ? 5 : 8
    }

    // MARK: - Persistence

    private func load() -> [NavPinItem] {
        guard let data = defaults.data(forKey: kDefaultsKey),
              let items = try? decoder.decode([NavPinItem].self, from: data)
        else { return [] }
        return items
    }

    private func persist() {
        guard let data = try? encoder.encode(pinnedItems) else { return }
        defaults.set(data, forKey: kDefaultsKey)
    }

    // MARK: - Testing helpers (internal)

    /// Wipe persisted state and in-memory list. Used in tests.
    func _resetForTesting() {
        pinnedItems = []
        defaults.removeObject(forKey: kDefaultsKey)
    }
}
