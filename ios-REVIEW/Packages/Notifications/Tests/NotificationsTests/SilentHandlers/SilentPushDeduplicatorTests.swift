import XCTest
@testable import Notifications

final class SilentPushDeduplicatorTests: XCTestCase {

    // Uses InMemoryDeduplicatorStore for test isolation (no UserDefaults pollution).

    private func makeDeduplicator(windowDuration: TimeInterval = 3600) -> SilentPushDeduplicator {
        SilentPushDeduplicator(
            windowDuration: windowDuration,
            store: InMemoryDeduplicatorStore()
        )
    }

    // MARK: - First-time ID

    func test_isDuplicate_returnsFalse_forFirstSeenId() async {
        let dedup = makeDeduplicator()
        let result = await dedup.isDuplicate("msg-001")
        XCTAssertFalse(result)
    }

    // MARK: - Duplicate ID

    func test_isDuplicate_returnsTrue_forAlreadySeenId() async {
        let dedup = makeDeduplicator()
        _ = await dedup.isDuplicate("msg-002")       // first time → false + record
        let result = await dedup.isDuplicate("msg-002") // second time → true
        XCTAssertTrue(result)
    }

    // MARK: - Different IDs not confused

    func test_isDuplicate_differentIds_notConfused() async {
        let dedup = makeDeduplicator()
        let a = await dedup.isDuplicate("msg-a")
        let b = await dedup.isDuplicate("msg-b")
        XCTAssertFalse(a)
        XCTAssertFalse(b)
    }

    // MARK: - trackedCount

    func test_trackedCount_incrementsAfterNewIds() async {
        let dedup = makeDeduplicator()
        _ = await dedup.isDuplicate("id-1")
        _ = await dedup.isDuplicate("id-2")
        let count = await dedup.trackedCount
        XCTAssertEqual(count, 2)
    }

    func test_trackedCount_doesNotIncrementOnDuplicate() async {
        let dedup = makeDeduplicator()
        _ = await dedup.isDuplicate("id-1")
        _ = await dedup.isDuplicate("id-1")   // duplicate
        let count = await dedup.trackedCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - Eviction of expired entries

    func test_eviction_removesEntriesOlderThanWindow() async {
        // Use a 0-second window — every entry is immediately "expired".
        let dedup = SilentPushDeduplicator(
            windowDuration: 0,
            store: InMemoryDeduplicatorStore()
        )
        // First call records "id-x".
        _ = await dedup.isDuplicate("id-x")
        // Second call: evicts "id-x" (age >= window=0), then records fresh.
        let result = await dedup.isDuplicate("id-x")
        // After eviction the ID is gone, so it's treated as new → not duplicate.
        XCTAssertFalse(result)
    }

    func test_eviction_keepsEntriesWithinWindow() async {
        let dedup = makeDeduplicator(windowDuration: 3600)
        _ = await dedup.isDuplicate("msg-keep")
        let result = await dedup.isDuplicate("msg-keep")
        XCTAssertTrue(result, "Entry within window must be flagged as duplicate")
    }

    // MARK: - reset()

    func test_reset_clearsAllTrackedIds() async {
        let dedup = makeDeduplicator()
        _ = await dedup.isDuplicate("id-r1")
        _ = await dedup.isDuplicate("id-r2")
        await dedup.reset()
        let count = await dedup.trackedCount
        XCTAssertEqual(count, 0)
    }

    func test_reset_allowsReuseOfPreviouslySeenId() async {
        let dedup = makeDeduplicator()
        _ = await dedup.isDuplicate("id-reuse")
        await dedup.reset()
        let result = await dedup.isDuplicate("id-reuse")
        XCTAssertFalse(result)
    }

    // MARK: - Persistence via store

    func test_persistence_survives_rehydration() async {
        let store = InMemoryDeduplicatorStore()

        // First deduplicator instance records an ID.
        let dedup1 = SilentPushDeduplicator(windowDuration: 3600, store: store)
        _ = await dedup1.isDuplicate("persistent-id")

        // Second instance loads from the same store.
        let dedup2 = SilentPushDeduplicator(windowDuration: 3600, store: store)
        let result = await dedup2.isDuplicate("persistent-id")
        XCTAssertTrue(result, "Persisted ID must be flagged as duplicate after rehydration")
    }

    // MARK: - InMemoryDeduplicatorStore isolation

    func test_separateStores_doNotShareState() async {
        let dedup1 = makeDeduplicator()
        let dedup2 = makeDeduplicator()

        _ = await dedup1.isDuplicate("shared-id")
        let result = await dedup2.isDuplicate("shared-id")
        XCTAssertFalse(result, "Separate stores must not share state")
    }
}
