import XCTest
@testable import Pos

final class HeldCartStoreTests: XCTestCase {

    // Fresh UserDefaults suite per-test for isolation. Each test creates its
    // own local store via `makeStore()` to avoid actor-isolation data-race
    // warnings in Swift 6 strict concurrency.
    private var suiteName: String = ""

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "HeldCartStoreTests_\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        let s = makeStore()
        await s.deleteAll()
        try await super.tearDown()
    }

    private func makeStore() -> HeldCartStore {
        HeldCartStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    // MARK: - save & loadAll

    func test_save_and_loadAll_roundtrips() async {
        let store = makeStore()
        let held  = makeHeldCart(note: "Table 4")
        await store.save(held)
        let loaded = await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, held.id)
        XCTAssertEqual(loaded.first?.note, "Table 4")
    }

    func test_loadAll_emptyStore_returnsEmpty() async {
        let store  = makeStore()
        let loaded = await store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    func test_save_multiple_loadAll_returnsSortedNewestFirst() async {
        let store  = makeStore()
        let first  = makeHeldCart(note: "First",  savedAt: Date(timeIntervalSinceNow: -100))
        let second = makeHeldCart(note: "Second", savedAt: Date(timeIntervalSinceNow: -50))
        let third  = makeHeldCart(note: "Third",  savedAt: Date())
        await store.save(first)
        await store.save(second)
        await store.save(third)
        let loaded = await store.loadAll()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[0].note, "Third")
        XCTAssertEqual(loaded[1].note, "Second")
        XCTAssertEqual(loaded[2].note, "First")
    }

    func test_save_duplicateId_replaces() async {
        let store   = makeStore()
        let held    = makeHeldCart(note: "Original")
        let updated = HeldCart(id: held.id, cart: held.cart, note: "Updated")
        await store.save(held)
        await store.save(updated)
        let loaded = await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.note, "Updated")
    }

    // MARK: - delete

    func test_delete_removesById() async {
        let store = makeStore()
        let a     = makeHeldCart(note: "A")
        let b     = makeHeldCart(note: "B")
        await store.save(a)
        await store.save(b)
        await store.delete(id: a.id)
        let loaded = await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, b.id)
    }

    func test_delete_unknownId_isNoOp() async {
        let store = makeStore()
        let held  = makeHeldCart(note: "Kept")
        await store.save(held)
        await store.delete(id: UUID())
        let loaded = await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
    }

    // MARK: - deleteAll

    func test_deleteAll_clearsStore() async {
        let store = makeStore()
        await store.save(makeHeldCart())
        await store.save(makeHeldCart())
        await store.deleteAll()
        let loaded = await store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Expiry

    func test_loadAll_expiredCarts_pruned() async {
        let store       = makeStore()
        let expiredDate = Date(timeIntervalSinceNow: -(25 * 60 * 60))
        let expired     = makeHeldCart(note: "Old",   savedAt: expiredDate)
        let fresh       = makeHeldCart(note: "Fresh", savedAt: Date())
        await store.save(expired)
        await store.save(fresh)
        let loaded = await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.note, "Fresh")
    }

    func test_heldCart_isExpired_trueWhenOld() {
        let old = makeHeldCart(savedAt: Date(timeIntervalSinceNow: -(25 * 60 * 60)))
        XCTAssertTrue(old.isExpired)
    }

    func test_heldCart_isExpired_falseWhenFresh() {
        let fresh = makeHeldCart(savedAt: Date())
        XCTAssertFalse(fresh.isExpired)
    }

    // MARK: - Helpers

    private func makeHeldCart(note: String? = nil, savedAt: Date = Date()) -> HeldCart {
        let snapshot = CartSnapshot(
            items: [
                CartSnapshot.Item(
                    id: UUID().uuidString,
                    inventoryItemId: nil,
                    name: "Widget",
                    sku: nil,
                    quantity: 1,
                    unitPriceCents: 999,
                    taxRateBps: nil,
                    discountCents: 0,
                    notes: nil
                )
            ],
            customer: nil,
            cartDiscountCents: 0,
            cartDiscountPercent: nil,
            tipCents: 0,
            feesCents: 0,
            feesLabel: nil,
            savedAt: savedAt
        )
        return HeldCart(savedAt: savedAt, cart: snapshot, note: note)
    }
}
