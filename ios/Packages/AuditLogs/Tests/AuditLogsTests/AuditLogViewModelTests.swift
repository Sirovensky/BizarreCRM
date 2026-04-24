import Testing
import Foundation
@testable import AuditLogs
import Networking
import Core

// MARK: - Test doubles

/// A mock `APIClient` that returns configurable `AuditLogPage` responses.
actor MockAPIClient: APIClient {

    // Configurable response
    var pageToReturn: AuditLogPage = .init(entries: [], nextCursor: nil)
    var errorToThrow: Error? = nil
    var callCount = 0

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        callCount += 1
        if let error = errorToThrow { throw error }
        guard let result = pageToReturn as? T else {
            throw APITransportError.decoding("MockAPIClient: wrong type")
        }
        return result
    }
    func get<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        try await get(path, query: nil, as: type)
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { fatalError() }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { fatalError() }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { fatalError() }
    func delete(_ path: String) async throws { fatalError() }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { fatalError() }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Fixtures

private func makeEntry(
    id: String = "1",
    actorFirstName: String = "Alice",
    actorLastName: String? = nil,
    action: String = "ticket.update",
    entityKind: String = "ticket",
    createdAt: Date = Date()
) -> AuditLogEntry {
    AuditLogEntry(
        id: id,
        createdAt: createdAt,
        actorUserId: Int(id),
        actorFirstName: actorFirstName,
        actorLastName: actorLastName,
        action: action,
        entityKind: entityKind,
        entityId: Int(id)
    )
}

// MARK: - Tests

@Suite("AuditLogViewModel")
@MainActor
struct AuditLogViewModelTests {

    // MARK: ACL gate

    @Test func deniedAccess_doesNotLoadAndSetsHasAccessFalse() async {
        let mock = MockAPIClient()
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { false })
        await vm.load()
        #expect(vm.hasAccess == false)
        let count = await mock.callCount
        #expect(count == 0)
    }

    @Test func allowedAccess_setsHasAccessTrue() async {
        let mock = MockAPIClient()
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        await vm.load()
        #expect(vm.hasAccess == true)
    }

    // MARK: Initial load

    @Test func load_populatesEntries() async {
        let mock = MockAPIClient()
        await mock.setPageToReturn(.init(entries: [makeEntry(id: "1"), makeEntry(id: "2")], nextCursor: nil))
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        await vm.load()
        #expect(vm.entries.count == 2)
        #expect(vm.errorMessage == nil)
        #expect(vm.hasMore == false)
    }

    @Test func load_withCursor_setsHasMoreTrue() async {
        let mock = MockAPIClient()
        await mock.setPageToReturn(.init(entries: [makeEntry()], nextCursor: "cursor123"))
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        await vm.load()
        #expect(vm.hasMore == true)
        #expect(vm.nextCursor == "cursor123")
    }

    @Test func load_onError_setsErrorMessage() async {
        let mock = MockAPIClient()
        await mock.setErrorToThrow(APITransportError.noBaseURL)
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(vm.entries.isEmpty)
    }

    @Test func load_clearsErrorOnSuccess() async {
        let mock = MockAPIClient()
        await mock.setErrorToThrow(APITransportError.noBaseURL)
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        await vm.load()
        #expect(vm.errorMessage != nil)

        await mock.setErrorToThrow(nil)
        await mock.setPageToReturn(.init(entries: [makeEntry()], nextCursor: nil))
        await vm.load()
        #expect(vm.errorMessage == nil)
    }

    // MARK: Pagination

    @Test func loadMore_appendsEntries() async {
        let mock = MockAPIClient()
        await mock.setPageToReturn(.init(entries: [makeEntry(id: "1")], nextCursor: "c1"))
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        await vm.load()
        #expect(vm.entries.count == 1)

        await mock.setPageToReturn(.init(entries: [makeEntry(id: "2")], nextCursor: nil))
        await vm.loadMore()
        #expect(vm.entries.count == 2)
        #expect(vm.hasMore == false)
    }

    @Test func loadMore_whenNoMore_doesNothing() async {
        let mock = MockAPIClient()
        await mock.setPageToReturn(.init(entries: [makeEntry()], nextCursor: nil))
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        await vm.load()
        let countBefore = await mock.callCount
        await vm.loadMore()
        let countAfter = await mock.callCount
        #expect(countAfter == countBefore)
    }

    // MARK: loadMoreIfNeeded

    @Test func loadMoreIfNeeded_nearEnd_triggersLoadMore() async {
        let entries = (1...10).map { makeEntry(id: "\($0)") }
        let mock = MockAPIClient()
        await mock.setPageToReturn(.init(entries: entries, nextCursor: "next"))
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        await vm.load()
        let countAfterLoad = await mock.callCount

        await mock.setPageToReturn(.init(entries: [], nextCursor: nil))
        vm.loadMoreIfNeeded(entryId: "8")  // index 7, threshold = 5
        // Allow Task to run
        try? await Task.sleep(nanoseconds: 10_000_000)
        let countAfterNeed = await mock.callCount
        #expect(countAfterNeed > countAfterLoad)
    }

    @Test func loadMoreIfNeeded_earlyRow_doesNotTrigger() async {
        let entries = (1...10).map { makeEntry(id: "\($0)") }
        let mock = MockAPIClient()
        await mock.setPageToReturn(.init(entries: entries, nextCursor: "next"))
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        await vm.load()
        let countAfterLoad = await mock.callCount

        vm.loadMoreIfNeeded(entryId: "1")  // index 0, well before threshold
        try? await Task.sleep(nanoseconds: 10_000_000)
        let countAfterNeed = await mock.callCount
        #expect(countAfterNeed == countAfterLoad)
    }

    // MARK: Filter state

    @Test func emptyFilters_isNotActive() {
        let mock = MockAPIClient()
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        #expect(vm.filters.isActive == false)
    }

    @Test func applyDateRange_last24h_setsSinceUntil() async {
        let mock = MockAPIClient()
        await mock.setPageToReturn(.init(entries: [], nextCursor: nil))
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        vm.applyDateRange(.last24h)
        // Give debounce task time to start (it's a Task inside applyDateRange)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(vm.filters.since != nil)
        #expect(vm.filters.until != nil)
        #expect(vm.selectedRange == .last24h)
    }

    @Test func clearFilters_resetsFiltersToEmpty() async {
        let mock = MockAPIClient()
        await mock.setPageToReturn(.init(entries: [], nextCursor: nil))
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        vm.applyDateRange(.last24h)
        try? await Task.sleep(nanoseconds: 10_000_000)
        vm.clearFilters()
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(vm.filters == .empty)
        #expect(vm.selectedRange == nil)
    }

    @Test func applyFilters_updatesFilters() async {
        let mock = MockAPIClient()
        await mock.setPageToReturn(.init(entries: [], nextCursor: nil))
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        let updated = AuditLogFilters(actions: ["ticket.update"], entityType: "ticket")
        vm.applyFilters(updated)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(vm.filters.actions == ["ticket.update"])
        #expect(vm.filters.entityType == "ticket")
    }

    @Test func queryChange_updatesFilterQuery() {
        let mock = MockAPIClient()
        let repo = AuditLogRepository(api: mock)
        let vm = AuditLogViewModel(repository: repo, accessPolicy: { true })
        vm.onQueryChange("alice")
        #expect(vm.filters.query == "alice")
    }

    // MARK: Date range presets

    @Test func dateRange_last24h_intervalIsApproximately24Hours() {
        let now = Date()
        let interval = AuditDateRange.last24h.dateInterval(now: now)
        #expect(interval != nil)
        let diff = interval!.until.timeIntervalSince(interval!.since)
        #expect(abs(diff - 86_400) < 1)
    }

    @Test func dateRange_custom_returnsNil() {
        #expect(AuditDateRange.custom.dateInterval() == nil)
    }

    @Test func dateRange_thisWeek_sinceIsBeforeNow() {
        let now = Date()
        let interval = AuditDateRange.thisWeek.dateInterval(now: now)
        #expect(interval != nil)
        #expect(interval!.since <= now)
        #expect(interval!.until <= now.addingTimeInterval(1))
    }
}

// MARK: - Actor helpers on MockAPIClient

private extension MockAPIClient {
    func setPageToReturn(_ page: AuditLogPage) {
        self.pageToReturn = page
    }
    func setErrorToThrow(_ error: Error?) {
        self.errorToThrow = error
    }
}

// MARK: - AuditLogEntry model tests

@Suite("AuditLogEntry model")
struct AuditLogEntryModelTests {

    @Test func actorName_firstAndLastName() {
        let entry = makeEntry(actorFirstName: "Alice", actorLastName: "Smith")
        #expect(entry.actorName == "Alice Smith")
    }

    @Test func actorName_firstNameOnly() {
        let entry = makeEntry(actorFirstName: "Bob", actorLastName: nil)
        #expect(entry.actorName == "Bob")
    }

    @Test func actorName_bothNil_fallsBackToSystem() {
        let entry = AuditLogEntry(
            id: "99", createdAt: Date(),
            actorUserId: nil, actorFirstName: nil, actorLastName: nil,
            action: "system.event", entityKind: "system"
        )
        #expect(entry.actorName == "System")
    }

    @Test func actorName_emptyStrings_fallsBackToSystem() {
        let entry = AuditLogEntry(
            id: "100", createdAt: Date(),
            actorUserId: nil, actorFirstName: "", actorLastName: "",
            action: "system.event", entityKind: "system"
        )
        #expect(entry.actorName == "System")
    }

    @Test func entityId_isOptionalInt() {
        let withId = makeEntry(id: "5")
        #expect(withId.entityId == 5)
        let noId = AuditLogEntry(
            id: "6", createdAt: Date(),
            action: "ticket.delete", entityKind: "ticket", entityId: nil
        )
        #expect(noId.entityId == nil)
    }

    @Test func jsonDecoding_fromServerShape() throws {
        // Mirrors the exact shape the server sends inside `data.events[...]`
        let json = """
        {
            "id": 42,
            "actor_user_id": 7,
            "entity_kind": "ticket",
            "entity_id": 99,
            "action": "ticket.update",
            "metadata": {"status": "active"},
            "created_at": "2025-01-15T10:00:00Z",
            "actor_first_name": "Jane",
            "actor_last_name": "Doe"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(AuditLogEntry.self, from: json)
        #expect(entry.id == "42")
        #expect(entry.actorUserId == 7)
        #expect(entry.entityKind == "ticket")
        #expect(entry.entityId == 99)
        #expect(entry.action == "ticket.update")
        #expect(entry.actorFirstName == "Jane")
        #expect(entry.actorLastName == "Doe")
        #expect(entry.actorName == "Jane Doe")
        #expect(entry.metadata?["status"] == .string("active"))
    }

    @Test func jsonDecoding_nullableFields() throws {
        let json = """
        {
            "id": 1,
            "actor_user_id": null,
            "entity_kind": "system",
            "entity_id": null,
            "action": "system.boot",
            "metadata": null,
            "created_at": "2025-01-15T10:00:00Z",
            "actor_first_name": null,
            "actor_last_name": null
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(AuditLogEntry.self, from: json)
        #expect(entry.actorUserId == nil)
        #expect(entry.entityId == nil)
        #expect(entry.metadata == nil)
        #expect(entry.actorName == "System")
    }
}

// MARK: - AuditLogRepository client-side filtering tests

@Suite("AuditLogRepository client-side filtering")
struct AuditLogRepositoryFilterTests {

    // Helper: make an entry at a specific date.
    private func entry(id: String, action: String = "ticket.update", entityKind: String = "ticket", daysAgo: Double = 0) -> AuditLogEntry {
        let date = Date(timeIntervalSinceNow: -daysAgo * 86_400)
        return AuditLogEntry(
            id: id, createdAt: date,
            actorFirstName: "Test", action: action, entityKind: entityKind
        )
    }

    @Test func dateFilter_since_excludesOlderEntries() async throws {
        let mock = MockAPIClient()
        let old = entry(id: "1", daysAgo: 5)
        let recent = entry(id: "2", daysAgo: 1)
        await mock.setPageToReturn(.init(entries: [old, recent], nextCursor: nil))
        let repo = AuditLogRepository(api: mock)
        let filters = AuditLogFilters(since: Date(timeIntervalSinceNow: -2 * 86_400))
        let page = try await repo.fetch(filters: filters)
        #expect(page.entries.count == 1)
        #expect(page.entries[0].id == "2")
    }

    @Test func dateFilter_until_excludesNewerEntries() async throws {
        let mock = MockAPIClient()
        let old = entry(id: "1", daysAgo: 10)
        let recent = entry(id: "2", daysAgo: 0)
        await mock.setPageToReturn(.init(entries: [old, recent], nextCursor: nil))
        let repo = AuditLogRepository(api: mock)
        let filters = AuditLogFilters(until: Date(timeIntervalSinceNow: -3 * 86_400))
        let page = try await repo.fetch(filters: filters)
        #expect(page.entries.count == 1)
        #expect(page.entries[0].id == "1")
    }

    @Test func actionFilter_excludesNonMatchingActions() async throws {
        let mock = MockAPIClient()
        let ticketEntry  = entry(id: "1", action: "ticket.update")
        let invoiceEntry = entry(id: "2", action: "invoice.create")
        await mock.setPageToReturn(.init(entries: [ticketEntry, invoiceEntry], nextCursor: nil))
        let repo = AuditLogRepository(api: mock)
        let filters = AuditLogFilters(actions: ["ticket.update"])
        let page = try await repo.fetch(filters: filters)
        #expect(page.entries.count == 1)
        #expect(page.entries[0].action == "ticket.update")
    }

    @Test func actionFilter_multipleActions_keepsAllMatching() async throws {
        let mock = MockAPIClient()
        let e1 = entry(id: "1", action: "ticket.update")
        let e2 = entry(id: "2", action: "invoice.create")
        let e3 = entry(id: "3", action: "customer.delete")
        await mock.setPageToReturn(.init(entries: [e1, e2, e3], nextCursor: nil))
        let repo = AuditLogRepository(api: mock)
        let filters = AuditLogFilters(actions: ["ticket.update", "invoice.create"])
        let page = try await repo.fetch(filters: filters)
        #expect(page.entries.count == 2)
    }

    @Test func queryFilter_matchesActorName() async throws {
        let mock = MockAPIClient()
        let alice = AuditLogEntry(id: "1", createdAt: Date(), actorFirstName: "Alice", action: "ticket.update", entityKind: "ticket")
        let bob   = AuditLogEntry(id: "2", createdAt: Date(), actorFirstName: "Bob",   action: "ticket.update", entityKind: "ticket")
        await mock.setPageToReturn(.init(entries: [alice, bob], nextCursor: nil))
        let repo = AuditLogRepository(api: mock)
        let filters = AuditLogFilters(query: "alice")
        let page = try await repo.fetch(filters: filters)
        #expect(page.entries.count == 1)
        #expect(page.entries[0].actorFirstName == "Alice")
    }

    @Test func queryFilter_caseInsensitive() async throws {
        let mock = MockAPIClient()
        let entry = AuditLogEntry(id: "1", createdAt: Date(), actorFirstName: "Alice", action: "ticket.update", entityKind: "ticket")
        await mock.setPageToReturn(.init(entries: [entry], nextCursor: nil))
        let repo = AuditLogRepository(api: mock)
        let filters = AuditLogFilters(query: "ALICE")
        let page = try await repo.fetch(filters: filters)
        #expect(page.entries.count == 1)
    }

    @Test func noFilters_returnsAllEntries() async throws {
        let mock = MockAPIClient()
        let entries = (1...5).map { self.entry(id: "\($0)") }
        await mock.setPageToReturn(.init(entries: entries, nextCursor: nil))
        let repo = AuditLogRepository(api: mock)
        let page = try await repo.fetch(filters: .empty)
        #expect(page.entries.count == 5)
    }

    @Test func nextCursor_isPreservedAfterFiltering() async throws {
        let mock = MockAPIClient()
        let entries = (1...3).map { self.entry(id: "\($0)") }
        await mock.setPageToReturn(.init(entries: entries, nextCursor: "cursor42"))
        let repo = AuditLogRepository(api: mock)
        let page = try await repo.fetch(filters: .empty)
        #expect(page.nextCursor == "cursor42")
    }
}
