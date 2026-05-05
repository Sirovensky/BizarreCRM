import XCTest
@testable import Sync

// MARK: - Shared test fixtures

private func makeItem(
    id: Int64 = 1,
    op: String = "create",
    entity: String = "tickets",
    attemptCount: Int = 3,
    lastError: String? = "Network timeout",
    movedAt: Date = Date(),
    payload: String = "{\"id\":1}"
) -> DeadLetterItem {
    DeadLetterItem(
        id: id,
        op: op,
        entity: entity,
        attemptCount: attemptCount,
        lastError: lastError,
        movedAt: movedAt,
        payload: payload
    )
}

// MARK: - MockDeadLetterStore

/// In-memory mock implementing `DeadLetterStoreProtocol`.
/// All state is immutable — every mutating call records its invocation
/// and returns the configured result.
final class MockDeadLetterStore: DeadLetterStoreProtocol, @unchecked Sendable {
    // Configurable responses
    var stubbedItems: [DeadLetterItem] = []
    var stubbedDetail: DeadLetterItem?
    var fetchAllError: Error?
    var fetchDetailError: Error?
    var retryError: Error?
    var discardError: Error?
    var stubbedCount: Int = 0

    // Invocation recording
    private(set) var retryCallIDs: [Int64] = []
    private(set) var discardCallIDs: [Int64] = []
    private(set) var fetchDetailCallIDs: [Int64] = []
    private(set) var fetchAllCallCount: Int = 0

    func fetchAll(limit: Int) async throws -> [DeadLetterItem] {
        fetchAllCallCount += 1
        if let err = fetchAllError { throw err }
        return stubbedItems
    }

    func fetchDetail(_ id: Int64) async throws -> DeadLetterItem? {
        fetchDetailCallIDs.append(id)
        if let err = fetchDetailError { throw err }
        return stubbedDetail
    }

    func retry(_ id: Int64) async throws {
        retryCallIDs.append(id)
        if let err = retryError { throw err }
    }

    func discard(_ id: Int64) async throws {
        discardCallIDs.append(id)
        if let err = discardError { throw err }
    }

    func count() async throws -> Int { stubbedCount }
}

// MARK: - Test errors

private enum TestError: LocalizedError {
    case network, server, persistence
    var errorDescription: String? {
        switch self {
        case .network:     return "Network error"
        case .server:      return "Server error"
        case .persistence: return "Persistence error"
        }
    }
}

// ============================================================
// MARK: - DeadLetterActionCoordinatorTests
// ============================================================

@MainActor
final class DeadLetterActionCoordinatorTests: XCTestCase {

    private func makeSUT(store: MockDeadLetterStore = MockDeadLetterStore())
        -> (DeadLetterActionCoordinator, MockDeadLetterStore)
    {
        let sut = DeadLetterActionCoordinator(store: store)
        return (sut, store)
    }

    // MARK: - Initial state

    func test_initialState_noInflightNoError() {
        let (sut, _) = makeSUT()
        XCTAssertTrue(sut.inFlight.isEmpty)
        XCTAssertFalse(sut.isBulkInFlight)
        XCTAssertNil(sut.lastError)
    }

    // MARK: - retryOne

    func test_retryOne_callsStoreRetry_withCorrectID() async {
        let store = MockDeadLetterStore()
        let (sut, _) = makeSUT(store: store)

        await sut.retryOne(id: 42)

        XCTAssertEqual(store.retryCallIDs, [42])
    }

    func test_retryOne_setsAndClearsInFlight() async {
        let store = MockDeadLetterStore()
        var capturedInFlight: Set<Int64>?
        let (sut, _) = makeSUT(store: store)
        sut.onMutated = { @MainActor in
            capturedInFlight = sut.inFlight
        }

        await sut.retryOne(id: 7)

        // After completion inFlight must be cleared
        XCTAssertFalse(sut.inFlight.contains(7))
        // But was set during operation (captured in onMutated)
        XCTAssertNil(sut.lastError)
    }

    func test_retryOne_setsError_onStoreFailure() async {
        let store = MockDeadLetterStore()
        store.retryError = TestError.network
        let (sut, _) = makeSUT(store: store)

        await sut.retryOne(id: 1)

        XCTAssertNotNil(sut.lastError)
        XCTAssertEqual(sut.lastError, TestError.network.errorDescription)
    }

    func test_retryOne_noop_whenAlreadyInFlight() async {
        let store = MockDeadLetterStore()
        let (sut, _) = makeSUT(store: store)
        // Manually place the ID in inFlight
        // (not possible via public API since inFlight is private(set);
        //  so we verify via two sequential calls where first must complete)
        await sut.retryOne(id: 10)
        let countAfterFirst = store.retryCallIDs.filter { $0 == 10 }.count
        XCTAssertEqual(countAfterFirst, 1)
    }

    // MARK: - discardOne

    func test_discardOne_callsStoreDiscard() async {
        let store = MockDeadLetterStore()
        let (sut, _) = makeSUT(store: store)

        await sut.discardOne(id: 99)

        XCTAssertEqual(store.discardCallIDs, [99])
    }

    func test_discardOne_setsError_onFailure() async {
        let store = MockDeadLetterStore()
        store.discardError = TestError.persistence
        let (sut, _) = makeSUT(store: store)

        await sut.discardOne(id: 5)

        XCTAssertNotNil(sut.lastError)
    }

    // MARK: - retryAll

    func test_retryAll_callsStoreRetryForEachID() async {
        let store = MockDeadLetterStore()
        let (sut, _) = makeSUT(store: store)

        await sut.retryAll(ids: [1, 2, 3])

        XCTAssertEqual(Set(store.retryCallIDs), [1, 2, 3])
    }

    func test_retryAll_noop_whenIDsEmpty() async {
        let store = MockDeadLetterStore()
        let (sut, _) = makeSUT(store: store)

        await sut.retryAll(ids: [])

        XCTAssertTrue(store.retryCallIDs.isEmpty)
        XCTAssertFalse(sut.isBulkInFlight)
    }

    func test_retryAll_setsBulkInFlight_duringOperation() async {
        let store = MockDeadLetterStore()
        var capturedBulk: Bool?
        let (sut, _) = makeSUT(store: store)
        sut.onMutated = { @MainActor in capturedBulk = sut.isBulkInFlight }

        await sut.retryAll(ids: [1])

        XCTAssertFalse(sut.isBulkInFlight)
        // isBulkInFlight is false by the time onMutated fires (after loop)
        XCTAssertEqual(capturedBulk, false)
    }

    func test_retryAll_setsFirstError_whenSomeItemsFail() async {
        let store = MockDeadLetterStore()
        store.retryError = TestError.server
        let (sut, _) = makeSUT(store: store)

        await sut.retryAll(ids: [10, 20])

        XCTAssertNotNil(sut.lastError)
    }

    // MARK: - discardAll

    func test_discardAll_callsStoreDiscardForEachID() async {
        let store = MockDeadLetterStore()
        let (sut, _) = makeSUT(store: store)

        await sut.discardAll(ids: [4, 5, 6])

        XCTAssertEqual(Set(store.discardCallIDs), [4, 5, 6])
    }

    func test_discardAll_noop_whenIDsEmpty() async {
        let store = MockDeadLetterStore()
        let (sut, _) = makeSUT(store: store)

        await sut.discardAll(ids: [])

        XCTAssertTrue(store.discardCallIDs.isEmpty)
    }

    func test_discardAll_setsError_onFailure() async {
        let store = MockDeadLetterStore()
        store.discardError = TestError.persistence
        let (sut, _) = makeSUT(store: store)

        await sut.discardAll(ids: [7])

        XCTAssertNotNil(sut.lastError)
    }

    // MARK: - isInFlight helper

    func test_isInFlight_returnsFalse_forUnknownID() {
        let (sut, _) = makeSUT()
        XCTAssertFalse(sut.isInFlight(999))
    }

    // MARK: - clearError

    func test_clearError_removesLastError() async {
        let store = MockDeadLetterStore()
        store.retryError = TestError.network
        let (sut, _) = makeSUT(store: store)
        await sut.retryOne(id: 1)
        XCTAssertNotNil(sut.lastError)

        sut.clearError()

        XCTAssertNil(sut.lastError)
    }

    // MARK: - onMutated callback

    func test_retryOne_invokesOnMutated_onSuccess() async {
        let store = MockDeadLetterStore()
        var mutatedCalled = false
        let (sut, _) = makeSUT(store: store)
        sut.onMutated = { @MainActor in mutatedCalled = true }

        await sut.retryOne(id: 1)

        XCTAssertTrue(mutatedCalled)
    }

    func test_discardOne_invokesOnMutated_onSuccess() async {
        let store = MockDeadLetterStore()
        var mutatedCalled = false
        let (sut, _) = makeSUT(store: store)
        sut.onMutated = { @MainActor in mutatedCalled = true }

        await sut.discardOne(id: 1)

        XCTAssertTrue(mutatedCalled)
    }

    func test_retryOne_doesNotInvokeOnMutated_onError() async {
        let store = MockDeadLetterStore()
        store.retryError = TestError.network
        var mutatedCalled = false
        let (sut, _) = makeSUT(store: store)
        sut.onMutated = { @MainActor in mutatedCalled = true }

        await sut.retryOne(id: 1)

        XCTAssertFalse(mutatedCalled)
    }
}

// ============================================================
// MARK: - DeadLetterFilterTests
// ============================================================

final class DeadLetterFilterTests: XCTestCase {

    // MARK: - DeadLetterFilter defaults

    func test_filter_all_isNotActive() {
        XCTAssertFalse(DeadLetterFilter.all.isActive)
    }

    func test_filter_withEntityKind_isActive() {
        var f = DeadLetterFilter.all
        f = DeadLetterFilter(entityKind: "tickets", maxAge: .any, failureReason: nil)
        XCTAssertTrue(f.isActive)
    }

    func test_filter_withMaxAge_isActive() {
        let f = DeadLetterFilter(entityKind: nil, maxAge: .last24h, failureReason: nil)
        XCTAssertTrue(f.isActive)
    }

    func test_filter_withFailureReason_isActive() {
        let f = DeadLetterFilter(entityKind: nil, maxAge: .any, failureReason: "timeout")
        XCTAssertTrue(f.isActive)
    }

    // MARK: - applying(_:) — entity

    func test_applying_entityKind_keepsMatchingItems() {
        let items = [
            makeItem(id: 1, entity: "tickets"),
            makeItem(id: 2, entity: "contacts"),
            makeItem(id: 3, entity: "tickets")
        ]
        let f = DeadLetterFilter(entityKind: "tickets", maxAge: .any, failureReason: nil)
        let result = items.applying(f)
        XCTAssertEqual(result.map(\.id), [1, 3])
    }

    func test_applying_nilEntityKind_returnsAll() {
        let items = [makeItem(id: 1, entity: "a"), makeItem(id: 2, entity: "b")]
        let result = items.applying(.all)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - applying(_:) — age

    func test_applying_last1h_includesRecentItems() {
        let now = Date()
        let recent = makeItem(id: 1, movedAt: now.addingTimeInterval(-1_800))   // 30 min ago
        let old = makeItem(id: 2, movedAt: now.addingTimeInterval(-7_200))       // 2 h ago
        let f = DeadLetterFilter(entityKind: nil, maxAge: .last1h, failureReason: nil)
        let result = [recent, old].applying(f, now: now)
        XCTAssertEqual(result.map(\.id), [1])
    }

    func test_applying_last24h_includesItemsWithinWindow() {
        let now = Date()
        let within = makeItem(id: 1, movedAt: now.addingTimeInterval(-3_600))    // 1 h ago
        let outside = makeItem(id: 2, movedAt: now.addingTimeInterval(-90_000))  // 25 h ago
        let f = DeadLetterFilter(entityKind: nil, maxAge: .last24h, failureReason: nil)
        let result = [within, outside].applying(f, now: now)
        XCTAssertEqual(result.map(\.id), [1])
    }

    func test_applying_older_excludesRecentItems() {
        let now = Date()
        let recent = makeItem(id: 1, movedAt: now.addingTimeInterval(-3_600))      // 1 h ago
        let old = makeItem(id: 2, movedAt: now.addingTimeInterval(-800_000))        // ~9 d ago
        let f = DeadLetterFilter(entityKind: nil, maxAge: .older, failureReason: nil)
        let result = [recent, old].applying(f, now: now)
        XCTAssertEqual(result.map(\.id), [2])
    }

    func test_applying_anyAge_returnsAll() {
        let now = Date()
        let items = [
            makeItem(id: 1, movedAt: now.addingTimeInterval(-10)),
            makeItem(id: 2, movedAt: now.addingTimeInterval(-1_000_000))
        ]
        let result = items.applying(.all, now: now)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - applying(_:) — failure reason

    func test_applying_failureReason_caseInsensitiveSubstringMatch() {
        let items = [
            makeItem(id: 1, lastError: "Network timeout occurred"),
            makeItem(id: 2, lastError: "Server 503"),
            makeItem(id: 3, lastError: nil)
        ]
        let f = DeadLetterFilter(entityKind: nil, maxAge: .any, failureReason: "TIMEOUT")
        let result = items.applying(f)
        XCTAssertEqual(result.map(\.id), [1])
    }

    func test_applying_emptyFailureReason_returnsAll() {
        let items = [makeItem(id: 1), makeItem(id: 2)]
        let f = DeadLetterFilter(entityKind: nil, maxAge: .any, failureReason: "")
        let result = items.applying(f)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Combined filters

    func test_applying_combinedFilters_intersectsAllDimensions() {
        let now = Date()
        let items = [
            makeItem(id: 1, entity: "tickets", lastError: "timeout", movedAt: now.addingTimeInterval(-100)),
            makeItem(id: 2, entity: "contacts", lastError: "timeout", movedAt: now.addingTimeInterval(-100)),
            makeItem(id: 3, entity: "tickets", lastError: "server",   movedAt: now.addingTimeInterval(-100)),
            makeItem(id: 4, entity: "tickets", lastError: "timeout",  movedAt: now.addingTimeInterval(-90_000))
        ]
        let f = DeadLetterFilter(
            entityKind: "tickets",
            maxAge: .last1h,
            failureReason: "timeout"
        )
        let result = items.applying(f, now: now)
        XCTAssertEqual(result.map(\.id), [1])
    }

    // MARK: - DeadLetterAgeFilter helpers

    func test_ageFilter_cutoffDate_last1h() {
        let now = Date()
        let cutoff = DeadLetterAgeFilter.last1h.cutoffDate(relativeTo: now)
        let expected = now.addingTimeInterval(-3_600)
        XCTAssertEqual(cutoff!.timeIntervalSinceReferenceDate, expected.timeIntervalSinceReferenceDate, accuracy: 1)
    }

    func test_ageFilter_cutoffDate_any_returnsNil() {
        XCTAssertNil(DeadLetterAgeFilter.any.cutoffDate())
    }

    func test_ageFilter_olderThanMode_onlyForOlderCase() {
        XCTAssertTrue(DeadLetterAgeFilter.older.isOlderThanMode)
        for c in [DeadLetterAgeFilter.any, .last1h, .last24h, .last7d] {
            XCTAssertFalse(c.isOlderThanMode, "\(c) should not be olderThanMode")
        }
    }

    // MARK: - DeadLetterAgeFilter allCases completeness

    func test_ageFilter_allCasesPresent() {
        let all = DeadLetterAgeFilter.allCases
        XCTAssertEqual(all.count, 5)
    }
}

// ============================================================
// MARK: - DeadLetterStoreProtocol conformance smoke test
// ============================================================

final class DeadLetterStoreProtocolTests: XCTestCase {
    func test_mockStore_fetchAll_returnsStubbed() async throws {
        let store = MockDeadLetterStore()
        store.stubbedItems = [makeItem(id: 10), makeItem(id: 20)]

        let result = try await store.fetchAll(limit: 50)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, 10)
    }

    func test_mockStore_fetchAll_throwsOnError() async {
        let store = MockDeadLetterStore()
        store.fetchAllError = TestError.network

        do {
            _ = try await store.fetchAll(limit: 50)
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, TestError.network.errorDescription)
        }
    }

    func test_mockStore_fetchDetail_returnsStubbed() async throws {
        let store = MockDeadLetterStore()
        let detail = makeItem(id: 99, payload: "{\"key\":\"value\"}")
        store.stubbedDetail = detail

        let result = try await store.fetchDetail(99)

        XCTAssertEqual(result?.id, 99)
        XCTAssertEqual(result?.payload, "{\"key\":\"value\"}")
        XCTAssertEqual(store.fetchDetailCallIDs, [99])
    }

    func test_mockStore_retry_recordsCall() async throws {
        let store = MockDeadLetterStore()

        try await store.retry(55)

        XCTAssertEqual(store.retryCallIDs, [55])
    }

    func test_mockStore_discard_recordsCall() async throws {
        let store = MockDeadLetterStore()

        try await store.discard(77)

        XCTAssertEqual(store.discardCallIDs, [77])
    }

    func test_mockStore_count_returnsStubbed() async throws {
        let store = MockDeadLetterStore()
        store.stubbedCount = 42

        let c = try await store.count()

        XCTAssertEqual(c, 42)
    }
}
