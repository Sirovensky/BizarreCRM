import XCTest
@testable import Search

/// §18 — Unit tests for SavedSearchStore.
///
/// Each test injects an isolated UserDefaults suite so tests never bleed into
/// one another (or into the real App Group suite).
final class SavedSearchStoreTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a fresh store backed by an isolated UserDefaults suite.
    private func makeStore(label: String = #function) -> SavedSearchStore {
        let suite = "com.bizarrecrm.test.\(label)"
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        return SavedSearchStore(defaults: ud)
    }

    private func makeSuite(label: String = #function) -> UserDefaults {
        let suite = "com.bizarrecrm.test.\(label)"
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        return ud
    }

    private func search(
        name: String = "My Search",
        query: String = "cracked screen",
        entity: EntityFilter = .all,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) -> SavedSearch {
        SavedSearch(
            name: name,
            query: query,
            entity: entity,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt
        )
    }

    // MARK: - save

    func test_save_singleSearch_appearsInAll() async throws {
        let store = makeStore()
        let s = search(name: "Alpha")
        try await store.save(s)
        let all = await store.all
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "Alpha")
    }

    func test_save_multipleSearches_storedAll() async throws {
        let store = makeStore()
        try await store.save(search(name: "Alpha"))
        try await store.save(search(name: "Beta"))
        let all = await store.all
        XCTAssertEqual(all.count, 2)
    }

    // MARK: - name uniqueness

    func test_save_duplicateName_throws() async throws {
        let store = makeStore()
        try await store.save(search(name: "Tickets Today"))
        do {
            try await store.save(search(name: "Tickets Today"))
            XCTFail("Expected duplicateName error to be thrown")
        } catch SavedSearchStore.SavedSearchStoreError.duplicateName(let existing) {
            XCTAssertEqual(existing, "Tickets Today")
        }
    }

    func test_save_duplicateNameCaseInsensitive_throws() async throws {
        let store = makeStore()
        try await store.save(search(name: "open tickets"))
        do {
            try await store.save(search(name: "Open Tickets"))
            XCTFail("Expected duplicateName error to be thrown")
        } catch SavedSearchStore.SavedSearchStoreError.duplicateName {
            // pass
        }
    }

    func test_save_duplicateNameLeadingTrailingSpace_throws() async throws {
        let store = makeStore()
        try await store.save(search(name: "invoices"))
        do {
            try await store.save(search(name: "  invoices  "))
            XCTFail("Expected duplicateName error to be thrown")
        } catch SavedSearchStore.SavedSearchStoreError.duplicateName {
            // pass
        }
    }

    func test_save_sameId_updatesInPlace_noError() async throws {
        let store = makeStore()
        let id = UUID().uuidString
        let original = SavedSearch(id: id, name: "Old Name", query: "q1")
        try await store.save(original)
        let updated = SavedSearch(id: id, name: "Old Name", query: "q2")
        // Same id → upsert, not a duplicate
        try await store.save(updated)
        let all = await store.all
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].query, "q2")
    }

    // MARK: - delete

    func test_delete_removesSearch() async throws {
        let store = makeStore()
        let s = search(name: "To Delete")
        try await store.save(s)
        await store.delete(id: s.id)
        let all = await store.all
        XCTAssertTrue(all.isEmpty)
    }

    func test_delete_nonExistentId_noError() async {
        let store = makeStore()
        await store.delete(id: "ghost-id")  // should not crash
    }

    func test_delete_onlyRemovesTargeted() async throws {
        let store = makeStore()
        let a = search(name: "Alpha")
        let b = search(name: "Beta")
        try await store.save(a)
        try await store.save(b)
        await store.delete(id: a.id)
        let all = await store.all
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "Beta")
    }

    // MARK: - rename

    func test_rename_changesName() async throws {
        let store = makeStore()
        let s = search(name: "Old")
        try await store.save(s)
        try await store.rename(id: s.id, newName: "New")
        let all = await store.all
        XCTAssertEqual(all[0].name, "New")
    }

    func test_rename_toDuplicateName_throws() async throws {
        let store = makeStore()
        let a = search(name: "Alpha")
        let b = search(name: "Beta")
        try await store.save(a)
        try await store.save(b)
        do {
            try await store.rename(id: b.id, newName: "Alpha")
            XCTFail("Expected duplicateName error")
        } catch SavedSearchStore.SavedSearchStoreError.duplicateName(let existing) {
            XCTAssertEqual(existing, "Alpha")
        }
    }

    func test_rename_sameName_noError() async throws {
        let store = makeStore()
        let s = search(name: "Alpha")
        try await store.save(s)
        // Renaming to same value should not throw
        try await store.rename(id: s.id, newName: "Alpha")
    }

    func test_rename_nonExistentId_noError() async throws {
        let store = makeStore()
        // Should not crash
        try await store.rename(id: "ghost", newName: "Anything")
    }

    // MARK: - sort by last-used

    func test_all_sortsByLastUsedAtDescending() async throws {
        let store = makeStore()
        let now = Date()
        let a = SavedSearch(id: UUID().uuidString, name: "A", query: "a",
                            lastUsedAt: now.addingTimeInterval(-300))
        let b = SavedSearch(id: UUID().uuidString, name: "B", query: "b",
                            lastUsedAt: now.addingTimeInterval(-100))
        let c = SavedSearch(id: UUID().uuidString, name: "C", query: "c",
                            lastUsedAt: now.addingTimeInterval(-10))
        try await store.save(a)
        try await store.save(b)
        try await store.save(c)
        let all = await store.all
        XCTAssertEqual(all.map(\.name), ["C", "B", "A"])
    }

    func test_all_neverUsedSearchesSortByCreatedAtDescending() async throws {
        let store = makeStore()
        let now = Date()
        let older = SavedSearch(id: UUID().uuidString, name: "Older", query: "x",
                                createdAt: now.addingTimeInterval(-200), lastUsedAt: nil)
        let newer = SavedSearch(id: UUID().uuidString, name: "Newer", query: "y",
                                createdAt: now.addingTimeInterval(-50), lastUsedAt: nil)
        try await store.save(older)
        try await store.save(newer)
        let all = await store.all
        XCTAssertEqual(all.first?.name, "Newer")
    }

    func test_all_usedSearchesRankAboveUnused() async throws {
        let store = makeStore()
        let now = Date()
        let unused = SavedSearch(id: UUID().uuidString, name: "Unused", query: "u",
                                 createdAt: now.addingTimeInterval(-10), lastUsedAt: nil)
        let used = SavedSearch(id: UUID().uuidString, name: "Used", query: "u",
                               createdAt: now.addingTimeInterval(-200),
                               lastUsedAt: now.addingTimeInterval(-1))
        try await store.save(unused)
        try await store.save(used)
        let all = await store.all
        XCTAssertEqual(all.first?.name, "Used")
    }

    // MARK: - recordUse

    func test_recordUse_updatesLastUsedAt() async throws {
        let store = makeStore()
        let s = search(name: "Track Me")
        try await store.save(s)
        let before = Date()
        await store.recordUse(id: s.id)
        let all = await store.all
        let updated = all.first { $0.id == s.id }
        XCTAssertNotNil(updated?.lastUsedAt)
        XCTAssertGreaterThanOrEqual(updated!.lastUsedAt!, before)
    }

    func test_recordUse_nonExistentId_noError() async {
        let store = makeStore()
        await store.recordUse(id: "ghost")  // should not crash
    }

    // MARK: - persistence

    func test_persistence_survivesReinit() async throws {
        let ud = makeSuite()
        let store1 = SavedSearchStore(defaults: ud)
        try await store1.save(search(name: "Persisted", query: "persist-test"))
        let store2 = SavedSearchStore(defaults: ud)
        let all = await store2.all
        XCTAssertTrue(all.contains { $0.name == "Persisted" })
    }

    func test_persistence_deleteSurvivesReinit() async throws {
        let ud = makeSuite()
        let store1 = SavedSearchStore(defaults: ud)
        let s = search(name: "Gone")
        try await store1.save(s)
        await store1.delete(id: s.id)
        let store2 = SavedSearchStore(defaults: ud)
        let all = await store2.all
        XCTAssertTrue(all.isEmpty)
    }

    func test_persistence_renameSurvivesReinit() async throws {
        let ud = makeSuite()
        let store1 = SavedSearchStore(defaults: ud)
        let s = search(name: "Before")
        try await store1.save(s)
        try await store1.rename(id: s.id, newName: "After")
        let store2 = SavedSearchStore(defaults: ud)
        let all = await store2.all
        XCTAssertEqual(all.first?.name, "After")
    }

    func test_persistence_lastUsedAtSurvivesReinit() async throws {
        let ud = makeSuite()
        let store1 = SavedSearchStore(defaults: ud)
        let s = search(name: "UseMe")
        try await store1.save(s)
        await store1.recordUse(id: s.id)
        let store2 = SavedSearchStore(defaults: ud)
        let all = await store2.all
        XCTAssertNotNil(all.first?.lastUsedAt)
    }

    // MARK: - SavedSearch value type

    func test_savedSearch_codableRoundTrip() throws {
        let original = SavedSearch(
            id: "abc123",
            name: "Round-trip",
            query: "iphone repair",
            entity: .tickets,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastUsedAt: Date(timeIntervalSince1970: 1_700_100_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedSearch.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.query, original.query)
        XCTAssertEqual(decoded.entity, original.entity)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
        XCTAssertEqual(decoded.lastUsedAt, original.lastUsedAt)
    }

    func test_savedSearch_defaultLastUsedAtIsNil() {
        let s = SavedSearch(name: "Fresh", query: "new")
        XCTAssertNil(s.lastUsedAt)
    }
}
