import XCTest
@testable import Core

// §20 Draft Recovery — UserDefaultsDraftStore tests
// Covers: encoding round-trip, key collision isolation, expiration (prune),
// listPending ordering, delete, concurrent saves.

final class UserDefaultsDraftStoreTests: XCTestCase {

    // MARK: — Fixture

    private struct TicketDraft: Codable, Sendable, Equatable {
        var title: String
        var priority: Int
    }

    private struct CustomerDraft: Codable, Sendable, Equatable {
        var name: String
    }

    /// Each call returns a store backed by a fresh, isolated UserDefaults suite.
    private func makeStore() -> UserDefaultsDraftStore {
        UserDefaultsDraftStore(suiteName: "test.udd.\(UUID().uuidString)")
    }

    // MARK: — Encoding round-trip

    func test_save_load_roundtrip_withId() async throws {
        let store = makeStore()
        let draft = TicketDraft(title: "Broken pipe", priority: 2)
        let key   = DraftKey.ticketEdit(id: "100")

        try await store.save(draft, forKey: key)
        let loaded = try await store.load(TicketDraft.self, forKey: key)

        XCTAssertEqual(loaded, draft)
    }

    func test_save_load_roundtrip_nilId() async throws {
        let store = makeStore()
        let draft = TicketDraft(title: "New ticket", priority: 1)

        try await store.save(draft, forKey: .ticketCreate)
        let loaded = try await store.load(TicketDraft.self, forKey: .ticketCreate)

        XCTAssertEqual(loaded, draft)
    }

    func test_load_returnsNil_whenNoDraftExists() async throws {
        let store = makeStore()
        let loaded = try await store.load(TicketDraft.self, forKey: .ticketEdit(id: "999"))
        XCTAssertNil(loaded)
    }

    func test_save_overwritesPreviousDraft() async throws {
        let store = makeStore()
        let v1 = TicketDraft(title: "v1", priority: 0)
        let v2 = TicketDraft(title: "v2", priority: 3)

        try await store.save(v1, forKey: .ticketEdit(id: "5"))
        try await store.save(v2, forKey: .ticketEdit(id: "5"))

        let loaded = try await store.load(TicketDraft.self, forKey: .ticketEdit(id: "5"))
        XCTAssertEqual(loaded, v2)
    }

    // MARK: — Key collision isolation

    func test_isolation_differentIds_doNotCross() async throws {
        let store = makeStore()
        let draftA = TicketDraft(title: "A", priority: 1)
        let draftB = TicketDraft(title: "B", priority: 2)

        try await store.save(draftA, forKey: .ticketEdit(id: "1"))
        try await store.save(draftB, forKey: .ticketEdit(id: "2"))

        let loadedA = try await store.load(TicketDraft.self, forKey: .ticketEdit(id: "1"))
        let loadedB = try await store.load(TicketDraft.self, forKey: .ticketEdit(id: "2"))

        XCTAssertEqual(loadedA, draftA, "id:1 slot must not be polluted by id:2 save")
        XCTAssertEqual(loadedB, draftB, "id:2 slot must not be polluted by id:1 save")
    }

    func test_isolation_createVsEdit_doNotCross() async throws {
        let store = makeStore()
        let create = TicketDraft(title: "create", priority: 0)
        let edit   = TicketDraft(title: "edit", priority: 1)

        try await store.save(create, forKey: .ticketCreate)
        try await store.save(edit,   forKey: .ticketEdit(id: "1"))

        let loadedCreate = try await store.load(TicketDraft.self, forKey: .ticketCreate)
        let loadedEdit   = try await store.load(TicketDraft.self, forKey: .ticketEdit(id: "1"))

        XCTAssertEqual(loadedCreate, create)
        XCTAssertEqual(loadedEdit,   edit)
    }

    func test_isolation_differentEntityKinds_doNotCross() async throws {
        let store = makeStore()
        let ticket   = TicketDraft(title: "ticket", priority: 0)
        let customer = CustomerDraft(name: "Acme")

        try await store.save(ticket,   forKey: .ticketCreate)
        try await store.save(customer, forKey: .customerCreate)

        let loadedTicket   = try await store.load(TicketDraft.self,   forKey: .ticketCreate)
        let loadedCustomer = try await store.load(CustomerDraft.self, forKey: .customerCreate)

        XCTAssertEqual(loadedTicket,   ticket)
        XCTAssertEqual(loadedCustomer, customer)
    }

    // MARK: — delete

    func test_delete_removesExistingDraft() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "bye", priority: 0), forKey: .ticketCreate)
        await store.delete(forKey: .ticketCreate)

        let loaded = try await store.load(TicketDraft.self, forKey: .ticketCreate)
        XCTAssertNil(loaded)
    }

    func test_delete_removesFromListPending() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "keep", priority: 0), forKey: .ticketEdit(id: "1"))
        try await store.save(TicketDraft(title: "gone", priority: 0), forKey: .ticketEdit(id: "2"))

        await store.delete(forKey: .ticketEdit(id: "2"))

        let all = await store.listPending()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.entityId, "1")
    }

    func test_delete_nonExistent_doesNotCrash() async {
        let store = makeStore()
        await store.delete(forKey: .ticketEdit(id: "no-such-id"))
    }

    // MARK: — listPending ordering

    func test_listPending_sortedNewestFirst() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "old", priority: 0), forKey: .ticketCreate)
        // Ensure measurable time difference.
        try await Task.sleep(nanoseconds: 15_000_000) // 15 ms
        try await store.save(TicketDraft(title: "new", priority: 0), forKey: .customerCreate)

        let all = await store.listPending()
        XCTAssertEqual(all.first?.screen, "customer.create", "newest draft must be first")
    }

    func test_listPending_returnsAllSavedKeys() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "a", priority: 0), forKey: .ticketCreate)
        try await store.save(TicketDraft(title: "b", priority: 0), forKey: .ticketEdit(id: "1"))
        try await store.save(CustomerDraft(name: "Acme"),           forKey: .customerCreate)

        let all = await store.listPending()
        XCTAssertEqual(all.count, 3)
    }

    func test_listPending_empty_whenNoDrafts() async {
        let store = makeStore()
        let all = await store.listPending()
        XCTAssertTrue(all.isEmpty)
    }

    func test_listPending_recordContainsCorrectMetadata() async throws {
        let store = makeStore()
        let draft = TicketDraft(title: "meta-check", priority: 5)
        try await store.save(draft, forKey: .ticketEdit(id: "77"))

        let all = await store.listPending()
        XCTAssertEqual(all.count, 1)
        let record = try XCTUnwrap(all.first)
        XCTAssertEqual(record.screen,   "ticket.edit")
        XCTAssertEqual(record.entityId, "77")
        XCTAssertGreaterThan(record.bytes, 0)
    }

    // MARK: — Expiration (prune)

    func test_prune_removesExpiredDrafts() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "stale", priority: 0), forKey: .ticketCreate)

        // olderThan: -1 means the cutoff is 1 second in the *future*, so any draft
        // created before now is older than the cutoff.
        await store.prune(olderThan: -1)

        let all = await store.listPending()
        XCTAssertTrue(all.isEmpty, "stale draft must be pruned")
    }

    func test_prune_keepsRecentDrafts() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "fresh", priority: 0), forKey: .ticketCreate)

        await store.prune(olderThan: DraftLifecycle.defaultExpirationInterval)

        let all = await store.listPending()
        XCTAssertEqual(all.count, 1, "a just-created draft must survive a 30-day prune")
    }

    func test_prune_onlyRemovesExpired_keepsRecent() async throws {
        let store = makeStore()
        // Save two drafts with a deliberate delay so their timestamps differ.
        try await store.save(TicketDraft(title: "will-stay", priority: 0), forKey: .ticketEdit(id: "1"))
        try await Task.sleep(nanoseconds: 20_000_000)
        try await store.save(TicketDraft(title: "also-stays", priority: 0), forKey: .ticketEdit(id: "2"))

        // 30-day threshold — both drafts are fresh.
        await store.prune(olderThan: DraftLifecycle.defaultExpirationInterval)

        let all = await store.listPending()
        XCTAssertEqual(all.count, 2)
    }

    func test_prune_emptyStore_doesNotCrash() async {
        let store = makeStore()
        await store.prune(olderThan: -1)
        let all = await store.listPending()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: — DraftRecord metadata integrity

    func test_draftRecord_compositeId_withId() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "x", priority: 0), forKey: .ticketEdit(id: "42"))

        let all = await store.listPending()
        let record = try XCTUnwrap(all.first)
        XCTAssertEqual(record.id, "ticket.edit|42")
    }

    func test_draftRecord_compositeId_nilId() async throws {
        let store = makeStore()
        try await store.save(TicketDraft(title: "x", priority: 0), forKey: .ticketCreate)

        let all = await store.listPending()
        let record = try XCTUnwrap(all.first)
        XCTAssertEqual(record.id, "ticket.create|")
    }
}
