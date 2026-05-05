import Testing
import Foundation
@testable import CommandPalette

// MARK: - CommandPaletteFavoritesStoreTests

@Suite("CommandPaletteFavoritesStore")
struct CommandPaletteFavoritesStoreTests {

    // MARK: - Helpers

    /// Returns a store bound to a unique UserDefaults key so tests are isolated.
    private func makeStore() -> CommandPaletteFavoritesStore {
        let key = "test.favorites.\(UUID().uuidString)"
        return CommandPaletteFavoritesStore(userDefaultsKey: key)
    }

    private func makeCatalog() -> [CommandAction] {
        [
            CommandAction(id: "new-ticket", title: "New Ticket", icon: "ticket", handler: {}),
            CommandAction(id: "open-pos", title: "Open POS", icon: "cart.fill", handler: {}),
            CommandAction(id: "clock-in", title: "Clock In", icon: "clock.badge.checkmark", handler: {}),
            CommandAction(id: "open-dashboard", title: "Open Dashboard", icon: "gauge", handler: {})
        ]
    }

    // MARK: - Initial state

    @Test("New store has no pinned IDs")
    func newStoreHasNoPinnedIDs() {
        let store = makeStore()
        #expect(store.pinnedIDs.isEmpty)
    }

    @Test("isPinned returns false for unknown ID")
    func isPinnedFalseForUnknownID() {
        let store = makeStore()
        #expect(!store.isPinned(id: "new-ticket"))
    }

    // MARK: - Pin

    @Test("Pinning an ID adds it to pinnedIDs")
    func pinAddsID() {
        let store = makeStore()
        store.pin(id: "new-ticket")
        #expect(store.pinnedIDs == ["new-ticket"])
        #expect(store.isPinned(id: "new-ticket"))
    }

    @Test("Pinning the same ID twice is idempotent")
    func pinIdempotent() {
        let store = makeStore()
        store.pin(id: "new-ticket")
        store.pin(id: "new-ticket")
        #expect(store.pinnedIDs.count == 1)
    }

    @Test("Pinning multiple IDs preserves insertion order")
    func pinPreservesOrder() {
        let store = makeStore()
        store.pin(id: "new-ticket")
        store.pin(id: "clock-in")
        store.pin(id: "open-pos")
        #expect(store.pinnedIDs == ["new-ticket", "clock-in", "open-pos"])
    }

    // MARK: - Unpin

    @Test("Unpinning removes the ID")
    func unpinRemovesID() {
        let store = makeStore()
        store.pin(id: "new-ticket")
        store.unpin(id: "new-ticket")
        #expect(store.pinnedIDs.isEmpty)
        #expect(!store.isPinned(id: "new-ticket"))
    }

    @Test("Unpinning unknown ID is a no-op")
    func unpinUnknownIsNoOp() {
        let store = makeStore()
        store.pin(id: "new-ticket")
        store.unpin(id: "ghost-id")
        #expect(store.pinnedIDs == ["new-ticket"])
    }

    @Test("Unpin preserves order of remaining IDs")
    func unpinPreservesOrder() {
        let store = makeStore()
        store.pin(id: "A")
        store.pin(id: "B")
        store.pin(id: "C")
        store.unpin(id: "B")
        #expect(store.pinnedIDs == ["A", "C"])
    }

    // MARK: - Toggle

    @Test("Toggle pins an unpinned ID and returns true")
    func togglePinsUnpinned() {
        let store = makeStore()
        let result = store.toggle(id: "new-ticket")
        #expect(result == true)
        #expect(store.isPinned(id: "new-ticket"))
    }

    @Test("Toggle unpins a pinned ID and returns false")
    func toggleUnpinsPinned() {
        let store = makeStore()
        store.pin(id: "new-ticket")
        let result = store.toggle(id: "new-ticket")
        #expect(result == false)
        #expect(!store.isPinned(id: "new-ticket"))
    }

    // MARK: - pinnedActions

    @Test("pinnedActions returns actions in pin order")
    func pinnedActionsPreservesOrder() {
        let store = makeStore()
        let catalog = makeCatalog()

        store.pin(id: "clock-in")
        store.pin(id: "new-ticket")

        let actions = store.pinnedActions(from: catalog)
        #expect(actions.count == 2)
        #expect(actions[0].id == "clock-in")
        #expect(actions[1].id == "new-ticket")
    }

    @Test("pinnedActions silently drops IDs not in catalog")
    func pinnedActionsDropsMissingIDs() {
        let store = makeStore()
        let catalog = makeCatalog()

        store.pin(id: "ghost-id")
        store.pin(id: "new-ticket")

        let actions = store.pinnedActions(from: catalog)
        #expect(actions.count == 1)
        #expect(actions[0].id == "new-ticket")
    }

    @Test("pinnedActions returns empty for no pinned IDs")
    func pinnedActionsEmptyWhenNoPins() {
        let store = makeStore()
        let actions = store.pinnedActions(from: makeCatalog())
        #expect(actions.isEmpty)
    }

    // MARK: - Persistence across instances (same key)

    @Test("Pins persist across separate store instances with the same key")
    func pinsPersistAcrossInstances() {
        let sharedKey = "test.favorites.persistence.\(UUID().uuidString)"
        let store1 = CommandPaletteFavoritesStore(userDefaultsKey: sharedKey)
        store1.pin(id: "new-ticket")

        let store2 = CommandPaletteFavoritesStore(userDefaultsKey: sharedKey)
        #expect(store2.isPinned(id: "new-ticket"))

        // Cleanup
        store2._resetForTesting()
    }

    // MARK: - Reset

    @Test("_resetForTesting clears all pins")
    func resetClearsAllPins() {
        let store = makeStore()
        store.pin(id: "A")
        store.pin(id: "B")
        store._resetForTesting()
        #expect(store.pinnedIDs.isEmpty)
    }
}
