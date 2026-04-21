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

private func makeEntry(id: String = "1", actorName: String = "Alice", action: String = "ticket.update") -> AuditLogEntry {
    AuditLogEntry(
        id: id,
        createdAt: Date(),
        actorId: "actor-\(id)",
        actorName: actorName,
        action: action,
        entityType: "ticket",
        entityId: "t-\(id)"
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
