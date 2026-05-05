import XCTest
@testable import Core

// DraftStore uses UserDefaults; each test gets a unique suite name for full isolation.
final class DraftStoreTests: XCTestCase {

    private struct TicketDraft: Codable, Sendable, Equatable {
        var title: String
        var notes: String
    }

    private func makeStore() -> DraftStore {
        // Unique suite per call → tests never share state.
        DraftStore(suiteName: "test.\(UUID().uuidString)")
    }

    // MARK: — save / load

    func test_save_load_roundtrip() async throws {
        let store = makeStore()
        let draft = TicketDraft(title: "Replace screen", notes: "Customer: John")

        try await store.save(draft, screen: "ticket.edit", entityId: "42")
        let loaded = try await store.load(TicketDraft.self, screen: "ticket.edit", entityId: "42")

        XCTAssertEqual(loaded, draft)
    }

    func test_load_returnsNil_whenNoDraft() async throws {
        let store = makeStore()
        let loaded = try await store.load(TicketDraft.self, screen: "ticket.edit", entityId: "99")
        XCTAssertNil(loaded)
    }

    func test_save_noEntityId_roundtrip() async throws {
        let store = makeStore()
        let draft = TicketDraft(title: "New ticket", notes: "")
        try await store.save(draft, screen: "ticket.create", entityId: nil)
        let loaded = try await store.load(TicketDraft.self, screen: "ticket.create", entityId: nil)
        XCTAssertEqual(loaded, draft)
    }

    func test_save_overwritesPreviousDraft() async throws {
        let store = makeStore()
        let v1 = TicketDraft(title: "v1", notes: "")
        let v2 = TicketDraft(title: "v2", notes: "updated")

        try await store.save(v1, screen: "ticket.edit", entityId: "1")
        try await store.save(v2, screen: "ticket.edit", entityId: "1")

        let loaded = try await store.load(TicketDraft.self, screen: "ticket.edit", entityId: "1")
        XCTAssertEqual(loaded, v2)
    }

    // MARK: — clear

    func test_clear_removesExistingDraft() async throws {
        let store = makeStore()
        let draft = TicketDraft(title: "temp", notes: "")
        try await store.save(draft, screen: "ticket.edit", entityId: "7")
        await store.clear(screen: "ticket.edit", entityId: "7")

        let loaded = try await store.load(TicketDraft.self, screen: "ticket.edit", entityId: "7")
        XCTAssertNil(loaded)
    }

    func test_clear_nonExistentDraft_doesNotCrash() async {
        let store = makeStore()
        await store.clear(screen: "ticket.edit", entityId: "999")
    }

    // MARK: — allDrafts

    func test_allDrafts_returnsAllSavedRecords() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "A", notes: ""), screen: "ticket.edit", entityId: "1")
        try await store.save(TicketDraft(title: "B", notes: ""), screen: "ticket.create", entityId: nil)
        try await store.save(TicketDraft(title: "C", notes: ""), screen: "customer.edit", entityId: "5")

        let all = await store.allDrafts()
        XCTAssertEqual(all.count, 3)
    }

    func test_allDrafts_sortedMostRecentFirst() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "old", notes: ""), screen: "a", entityId: nil)
        // secondsSince1970 preserves sub-second precision; 10ms is sufficient.
        try await Task.sleep(nanoseconds: 10_000_000)
        try await store.save(TicketDraft(title: "new", notes: ""), screen: "b", entityId: nil)

        let all = await store.allDrafts()
        XCTAssertEqual(all.first?.screen, "b", "most-recent draft should be first")
    }

    func test_allDrafts_afterClear_doesNotIncludeCleared() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "keep", notes: ""), screen: "ticket.edit", entityId: "1")
        try await store.save(TicketDraft(title: "gone", notes: ""), screen: "ticket.edit", entityId: "2")
        await store.clear(screen: "ticket.edit", entityId: "2")

        let all = await store.allDrafts()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.entityId, "1")
    }

    // MARK: — prune

    func test_prune_removesOldDrafts() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "old", notes: ""), screen: "ticket.edit", entityId: "old")
        // Use interval = -1 so all drafts are immediately "old".
        await store.prune(olderThan: -1)

        let all = await store.allDrafts()
        XCTAssertTrue(all.isEmpty, "all drafts should have been pruned")
    }

    func test_prune_keepsRecentDrafts() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "new", notes: ""), screen: "ticket.edit", entityId: "1")
        // Prune only drafts older than 30 days — a just-created draft survives.
        await store.prune(olderThan: 30 * 86_400)

        let all = await store.allDrafts()
        XCTAssertEqual(all.count, 1, "recent draft should NOT be pruned")
    }

    func test_prune_emptyStore_doesNotCrash() async {
        let store = makeStore()
        await store.prune(olderThan: -1)
        let all = await store.allDrafts()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: — DraftRecord

    func test_draftRecord_id_isComposite() {
        let record = DraftRecord(screen: "ticket.edit", entityId: "42", updatedAt: Date(), bytes: 100)
        XCTAssertEqual(record.id, "ticket.edit|42")
    }

    func test_draftRecord_id_nilEntityId() {
        let record = DraftRecord(screen: "ticket.create", entityId: nil, updatedAt: Date(), bytes: 50)
        XCTAssertEqual(record.id, "ticket.create|")
    }

    func test_allDrafts_returnsCorrectBytes() async throws {
        let store = makeStore()
        let draft = TicketDraft(title: "Check bytes", notes: "some notes here")
        try await store.save(draft, screen: "ticket.edit", entityId: "99")

        let all = await store.allDrafts()
        XCTAssertEqual(all.count, 1)
        XCTAssertGreaterThan(all[0].bytes, 0)
    }
}
