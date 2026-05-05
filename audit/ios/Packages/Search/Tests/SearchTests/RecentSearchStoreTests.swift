import XCTest
@testable import Search

final class RecentSearchStoreTests: XCTestCase {

    // Each test uses a fresh store backed by a test-specific UserDefaults suite
    // so tests don't bleed into one another.

    private func makeStore(suiteName: String = #function) -> RecentSearchStore {
        // Clear the suite before constructing to start fresh
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        // RecentSearchStore uses UserDefaults.standard; we swap via swizzling
        // isn't practical here, so we rely on clear() being called in setUp.
        return RecentSearchStore()
    }

    override func setUp() async throws {
        // Clear standard defaults key used by RecentSearchStore
        UserDefaults.standard.removeObject(forKey: "bizarrecrm.recentSearches")
    }

    // MARK: - add

    func test_add_singleQuery_stored() async {
        let store = makeStore()
        await store.add("iphone crack")
        let all = await store.all
        XCTAssertEqual(all, ["iphone crack"])
    }

    func test_add_multipleQueries_mostRecentFirst() async {
        let store = makeStore()
        await store.add("first")
        await store.add("second")
        let all = await store.all
        XCTAssertEqual(all.first, "second")
    }

    func test_add_empty_ignored() async {
        let store = makeStore()
        await store.add("")
        await store.add("   ")
        let all = await store.all
        XCTAssertTrue(all.isEmpty)
    }

    func test_add_duplicate_deduplicates_and_moves_to_front() async {
        let store = makeStore()
        await store.add("crack")
        await store.add("screen")
        await store.add("crack")  // duplicate
        let all = await store.all
        XCTAssertEqual(all.first, "crack")
        XCTAssertEqual(all.count, 2, "Duplicate should not add a second entry")
    }

    func test_add_caseInsensitiveDeduplicate() async {
        let store = makeStore()
        await store.add("iPhone")
        await store.add("iphone")
        let all = await store.all
        XCTAssertEqual(all.count, 1)
    }

    func test_add_evictsOldestPast20() async {
        let store = makeStore()
        for i in 1...25 {
            await store.add("query\(i)")
        }
        let all = await store.all
        XCTAssertEqual(all.count, 20)
        XCTAssertTrue(all.contains("query25"), "Newest should be present")
        XCTAssertFalse(all.contains("query1"), "Oldest should be evicted")
    }

    // MARK: - remove

    func test_remove_deletesQuery() async {
        let store = makeStore()
        await store.add("remove-me")
        await store.add("keep-me")
        await store.remove("remove-me")
        let all = await store.all
        XCTAssertFalse(all.contains("remove-me"))
        XCTAssertTrue(all.contains("keep-me"))
    }

    func test_remove_nonExistent_noError() async {
        let store = makeStore()
        await store.remove("ghost")  // should not throw
    }

    // MARK: - clear

    func test_clear_removesAll() async {
        let store = makeStore()
        await store.add("a")
        await store.add("b")
        await store.clear()
        let all = await store.all
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Persistence

    func test_persistence_surviveReinit() async {
        let store1 = makeStore()
        await store1.add("persistent-query")
        // Construct a new instance pointing at the same UserDefaults.standard
        let store2 = RecentSearchStore()
        let all = await store2.all
        XCTAssertTrue(all.contains("persistent-query"))
    }
}
