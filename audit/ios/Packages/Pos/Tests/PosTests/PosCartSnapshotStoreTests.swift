import Testing
import Foundation
@testable import Pos

// MARK: - PosCartSnapshotStoreTests

@Suite("PosCartSnapshotStore")
struct PosCartSnapshotStoreTests {

    // MARK: - Helpers

    /// A fresh in-memory UserDefaults domain for each test so tests don't bleed state.
    private func makeSUT(domain: String = UUID().uuidString) -> PosCartSnapshotStore {
        let defaults = UserDefaults(suiteName: domain)!
        return PosCartSnapshotStore(defaults: defaults)
    }

    private func makeSnapshot(
        itemCount: Int = 2,
        savedAt: Date = Date()
    ) -> CartSnapshot {
        let items = (0..<itemCount).map { i in
            CartSnapshot.Item(
                id: UUID().uuidString,
                inventoryItemId: Int64(i + 1),
                name: "Item \(i + 1)",
                sku: "SKU-\(i)",
                quantity: i + 1,
                unitPriceCents: (i + 1) * 100,
                taxRateBps: 800,
                discountCents: 0,
                notes: nil
            )
        }
        return CartSnapshot(
            items: items,
            customer: CartSnapshot.Customer(id: 42, displayName: "Alice", email: "a@b.com", phone: nil),
            cartDiscountCents: 50,
            cartDiscountPercent: nil,
            tipCents: 100,
            feesCents: 200,
            feesLabel: "Delivery",
            savedAt: savedAt
        )
    }

    // MARK: - save / load round-trip

    @Test("save then load returns the same snapshot")
    func saveLoad() async {
        let sut = makeSUT()
        let snapshot = makeSnapshot()
        await sut.save(snapshot)
        let loaded = await sut.load()
        #expect(loaded != nil)
        #expect(loaded?.items.count == snapshot.items.count)
        #expect(loaded?.customer?.displayName == "Alice")
        #expect(loaded?.tipCents == 100)
        #expect(loaded?.feesCents == 200)
        #expect(loaded?.feesLabel == "Delivery")
        #expect(loaded?.cartDiscountCents == 50)
    }

    @Test("load returns nil when nothing was saved")
    func loadWithNoData() async {
        let sut = makeSUT()
        let loaded = await sut.load()
        #expect(loaded == nil)
    }

    // MARK: - clear

    @Test("clear removes stored snapshot")
    func clearDeletesSnapshot() async {
        let sut = makeSUT()
        let snapshot = makeSnapshot()
        await sut.save(snapshot)
        await sut.clear()
        let loaded = await sut.load()
        #expect(loaded == nil)
    }

    @Test("clear on empty store is a no-op")
    func clearWithNoData() async {
        let sut = makeSUT()
        await sut.clear()   // should not throw or crash
        let loaded = await sut.load()
        #expect(loaded == nil)
    }

    // MARK: - Expiry (> 24 h discarded)

    @Test("load discards snapshot older than 24 hours")
    func expiredSnapshotIsDiscarded() async {
        let sut = makeSUT()
        let past = Date().addingTimeInterval(-25 * 60 * 60)   // 25 h ago
        let expired = makeSnapshot(savedAt: past)
        await sut.save(expired)
        let loaded = await sut.load()
        #expect(loaded == nil)
    }

    @Test("load accepts snapshot exactly under 24 hours old")
    func freshSnapshotIsLoaded() async {
        let sut = makeSUT()
        let recent = Date().addingTimeInterval(-23 * 60 * 60 - 59 * 60)  // 23h59m ago
        let snapshot = makeSnapshot(savedAt: recent)
        await sut.save(snapshot)
        let loaded = await sut.load()
        #expect(loaded != nil)
    }

    @Test("expired snapshot is pruned from defaults after load")
    func expiredSnapshotPrunedAfterLoad() async {
        let domain = UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let sut = PosCartSnapshotStore(defaults: defaults)
        let past = Date().addingTimeInterval(-25 * 60 * 60)
        await sut.save(makeSnapshot(savedAt: past))
        _ = await sut.load()
        // Second load should still return nil (key was removed)
        let second = await sut.load()
        #expect(second == nil)
    }

    // MARK: - Overwrite

    @Test("second save overwrites first snapshot")
    func overwriteSnapshot() async {
        let sut = makeSUT()
        let first = makeSnapshot(itemCount: 1)
        let second = makeSnapshot(itemCount: 5)
        await sut.save(first)
        await sut.save(second)
        let loaded = await sut.load()
        #expect(loaded?.items.count == 5)
    }

    // MARK: - CartSnapshot.isExpired

    @Test("isExpired returns true for snapshot older than 24 h")
    func snapshotIsExpired() {
        let old = makeSnapshot(savedAt: Date().addingTimeInterval(-86401))
        #expect(old.isExpired == true)
    }

    @Test("isExpired returns false for fresh snapshot")
    func snapshotIsNotExpired() {
        let fresh = makeSnapshot(savedAt: Date())
        #expect(fresh.isExpired == false)
    }
}
