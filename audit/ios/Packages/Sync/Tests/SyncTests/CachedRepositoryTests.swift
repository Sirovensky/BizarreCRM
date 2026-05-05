import XCTest
@testable import Sync

// MARK: - Test Entity

private struct FakeItem: Sendable, Equatable {
    let id: String
    let name: String
}

// MARK: - Thread-safe counter for Swift 6

private actor Counter {
    private var value: Int = 0
    func increment() { value += 1 }
    func get() -> Int { value }
}

private actor ItemAccumulator {
    private var items: [FakeItem] = []
    func append(contentsOf new: [FakeItem]) { items.append(contentsOf: new) }
    func get() -> [FakeItem] { items }
    func contains(_ item: FakeItem) -> Bool { items.contains(item) }
}

private actor StringAccumulator {
    private var values: [String] = []
    func append(_ s: String) { values.append(s) }
    func get() -> [String] { values }
}

// MARK: - CachedResult Tests

final class CachedResultTests: XCTestCase {

    func test_init_preservesAllProperties() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let sut = CachedResult(
            value: [1, 2, 3],
            source: .remote,
            lastSyncedAt: date,
            isStale: false
        )
        XCTAssertEqual(sut.value, [1, 2, 3])
        XCTAssertEqual(sut.source, .remote)
        XCTAssertEqual(sut.lastSyncedAt, date)
        XCTAssertFalse(sut.isStale)
    }

    func test_cacheSource_rawValues() {
        XCTAssertEqual(CacheSource.cache.rawValue, "cache")
        XCTAssertEqual(CacheSource.remote.rawValue, "remote")
        XCTAssertEqual(CacheSource.merged.rawValue, "merged")
    }

    func test_isStale_true_whenSet() {
        let sut = CachedResult(value: [String](), source: .cache, lastSyncedAt: nil, isStale: true)
        XCTAssertTrue(sut.isStale)
    }

    func test_isStale_false_whenNotStale() {
        let sut = CachedResult(value: [String](), source: .cache, lastSyncedAt: Date(), isStale: false)
        XCTAssertFalse(sut.isStale)
    }
}

// MARK: - AbstractCachedRepository Tests

final class AbstractCachedRepositoryTests: XCTestCase {

    // MARK: - Helpers

    private func makeItem(id: String = "1", name: String = "Test") -> FakeItem {
        FakeItem(id: id, name: name)
    }

    private typealias Repo = AbstractCachedRepository<FakeItem, String>

    private func makeRepo(
        localItems: [FakeItem] = [],
        syncedAt: Date? = nil,
        upsertAcc: ItemAccumulator? = nil,
        deleteAcc: StringAccumulator? = nil
    ) -> Repo {
        return Repo(
            entityName: "fakes",
            localFetch: { _ in localItems },
            remoteFetch: { _ in [] },
            localUpsert: { items in
                await upsertAcc?.append(contentsOf: items)
            },
            localDelete: { id in
                await deleteAcc?.append(id)
            },
            syncOpBuilder: { item, op in
                SyncOp(
                    op: op,
                    entity: "fakes",
                    entityLocalId: item.id,
                    payload: Data("{\"id\":\"\(item.id)\"}".utf8),
                    idempotencyKey: "\(item.id)-\(op)"
                )
            },
            idExtractor: { $0.id },
            lastSyncedAt: { _ in syncedAt }
        )
    }

    // MARK: - list(filter:maxAgeSeconds:)

    func test_list_returnsCachedItems_immediately() async throws {
        let cached = [makeItem(id: "1"), makeItem(id: "2")]
        let repo = makeRepo(localItems: cached, syncedAt: Date())
        let result = try await repo.list(filter: "", maxAgeSeconds: 3600)
        XCTAssertEqual(result.value, cached)
    }

    func test_list_isStale_whenNeverSynced() async throws {
        let repo = makeRepo(syncedAt: nil)
        let result = try await repo.list(filter: "", maxAgeSeconds: 60)
        XCTAssertTrue(result.isStale)
    }

    func test_list_notStale_whenFreshEnough() async throws {
        let repo = makeRepo(syncedAt: Date().addingTimeInterval(-30))
        let result = try await repo.list(filter: "", maxAgeSeconds: 3600)
        XCTAssertFalse(result.isStale)
    }

    func test_list_isStale_whenExpired() async throws {
        let repo = makeRepo(syncedAt: Date().addingTimeInterval(-7200))
        let result = try await repo.list(filter: "", maxAgeSeconds: 60)
        XCTAssertTrue(result.isStale)
    }

    func test_list_source_isCache_whenDataFromLocal() async throws {
        let repo = makeRepo(localItems: [makeItem()], syncedAt: Date())
        let result = try await repo.list(filter: "", maxAgeSeconds: 3600)
        XCTAssertEqual(result.source, .cache)
    }

    func test_list_lastSyncedAt_matches_injected() async throws {
        let date = Date(timeIntervalSince1970: 500_000)
        let repo = makeRepo(syncedAt: date)
        let result = try await repo.list(filter: "", maxAgeSeconds: 3600)
        XCTAssertEqual(result.lastSyncedAt, date)
    }

    // MARK: - create

    func test_create_callsLocalUpsert() async throws {
        let acc = ItemAccumulator()
        let repo = makeRepo(upsertAcc: acc)
        let item = makeItem(id: "new-1")

        _ = try await repo.create(item)

        let upserted = await acc.get()
        XCTAssertTrue(upserted.contains(item))
    }

    func test_create_returnsOriginalEntity() async throws {
        let repo = makeRepo()
        let item = makeItem(id: "x")
        let result = try await repo.create(item)
        XCTAssertEqual(result, item)
    }

    // MARK: - update

    func test_update_callsLocalUpsert() async throws {
        let acc = ItemAccumulator()
        let repo = makeRepo(upsertAcc: acc)
        let item = makeItem(id: "upd-1", name: "Updated")

        _ = try await repo.update(item)

        let upserted = await acc.get()
        XCTAssertTrue(upserted.contains(item))
    }

    func test_update_returnsOriginalEntity() async throws {
        let repo = makeRepo()
        let item = makeItem(id: "upd-2", name: "Changed")
        let result = try await repo.update(item)
        XCTAssertEqual(result, item)
    }

    // MARK: - delete

    func test_delete_callsLocalDelete_withCorrectId() async throws {
        let acc = StringAccumulator()
        let repo = makeRepo(deleteAcc: acc)

        try await repo.delete(id: "del-99")

        let deleted = await acc.get()
        XCTAssertEqual(deleted, ["del-99"])
    }

    func test_delete_multipleIds_eachCalled() async throws {
        let acc = StringAccumulator()
        let repo = makeRepo(deleteAcc: acc)

        try await repo.delete(id: "a")
        try await repo.delete(id: "b")

        let deleted = await acc.get()
        XCTAssertEqual(deleted, ["a", "b"])
    }
}
