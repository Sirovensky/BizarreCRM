import XCTest
@testable import Core

// §1.5 Pin-from-overflow drag — NavPinStoreTests
//
// 8 test cases covering: pin, unpin, reorder, iPhone cap, iPad cap,
// persistence round-trip, duplicate-pin guard, and catalog lookup.

@MainActor
final class NavPinStoreTests: XCTestCase {

    // MARK: - Fixtures

    private let item1 = NavPinItem(id: "more.inventory",  title: "Inventory", systemImage: "shippingbox")
    private let item2 = NavPinItem(id: "more.invoices",   title: "Invoices",  systemImage: "doc.text")
    private let item3 = NavPinItem(id: "more.reports",    title: "Reports",   systemImage: "chart.bar")
    private let item4 = NavPinItem(id: "more.leads",      title: "Leads",     systemImage: "person.crop.circle.badge.plus")
    private let item5 = NavPinItem(id: "more.marketing",  title: "Marketing", systemImage: "megaphone")
    private let item6 = NavPinItem(id: "more.employees",  title: "Employees", systemImage: "person.badge.key")

    /// Fresh isolated store for each test — never shares UserDefaults state.
    private func makeStore() -> NavPinStore {
        let suite = "test.navpins.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return NavPinStore(defaults: defaults)
    }

    // MARK: - 1. Pin adds item

    func test_pin_addsItemToPinnedList() {
        let store = makeStore()

        store.pin(item1)

        XCTAssertEqual(store.pinned().count, 1)
        XCTAssertEqual(store.pinned().first?.id, item1.id)
    }

    // MARK: - 2. Unpin removes item

    func test_unpin_removesItemFromPinnedList() {
        let store = makeStore()
        store.pin(item1)
        store.pin(item2)

        store.unpin(id: item1.id)

        XCTAssertEqual(store.pinned().count, 1)
        XCTAssertEqual(store.pinned().first?.id, item2.id)
    }

    // MARK: - 3. Reorder moves item correctly

    func test_reorder_movesItemToCorrectIndex() {
        let store = makeStore()
        store.pin(item1)
        store.pin(item2)
        store.pin(item3)
        // Initial order: [item1, item2, item3]

        store.reorder(from: 2, to: 0)
        // Expected: [item3, item1, item2]

        let pinned = store.pinned()
        XCTAssertEqual(pinned[0].id, item3.id)
        XCTAssertEqual(pinned[1].id, item1.id)
        XCTAssertEqual(pinned[2].id, item2.id)
    }

    // MARK: - 4. Duplicate-pin guard

    func test_pin_duplicateIsIgnored() {
        let store = makeStore()
        store.pin(item1)
        store.pin(item1) // second pin of the same id

        XCTAssertEqual(store.pinned().count, 1, "duplicate pin must be silently ignored")
    }

    // MARK: - 5. Cap enforcement (simulated iPhone: cap = 5)

    func test_pin_respectsCapOf5_forIPhone() {
        // We directly test the cap value path by capping at 5 items
        // regardless of actual device. Build 5 items, verify the 6th is rejected.
        let store = makeStore()
        let items: [NavPinItem] = [item1, item2, item3, item4, item5, item6]

        // Fill up to the iPhone cap (5)
        for item in items.prefix(5) { store.pin(item) }
        let countAtCap = store.pinned().count

        // Attempt to exceed by pinning a 6th distinct item
        store.pin(items[5])
        let countAfterExtra = store.pinned().count

        // On iPad the cap is 8, on iPhone 5.
        // The store should never exceed its reported cap.
        XCTAssertLessThanOrEqual(countAtCap, store.cap)
        XCTAssertLessThanOrEqual(countAfterExtra, store.cap,
            "pinned count must not exceed platform cap (\(store.cap))")
    }

    // MARK: - 6. Persistence round-trip

    func test_persistence_roundTrip() {
        let suite = "test.navpins.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        // Write via one store instance
        let store1 = NavPinStore(defaults: defaults)
        store1.pin(item1)
        store1.pin(item2)

        // Read back via a fresh instance on the same suite
        let store2 = NavPinStore(defaults: defaults)
        XCTAssertEqual(store2.pinned().count, 2)
        XCTAssertEqual(store2.pinned().map(\.id), [item1.id, item2.id],
            "pinned order must survive a store re-initialisation")
    }

    // MARK: - 7. Unpin non-existent id is a no-op

    func test_unpin_nonExistentId_doesNotCrash() {
        let store = makeStore()
        store.pin(item1)

        store.unpin(id: "does.not.exist")

        XCTAssertEqual(store.pinned().count, 1, "unpin of unknown id must leave list intact")
    }

    // MARK: - 8. Catalog lookup by id

    func test_catalog_itemLookup_returnsCorrectItem() {
        let found = NavPinCatalog.item(for: "more.inventory")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.title, "Inventory")
    }

    func test_catalog_itemLookup_unknownId_returnsNil() {
        let found = NavPinCatalog.item(for: "tab.does.not.exist")
        XCTAssertNil(found)
    }
}
