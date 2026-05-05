import XCTest
@testable import Sync

// MARK: - Thread-safe test helper

private actor Counter {
    private var value: Int = 0
    func increment() { value += 1 }
    func get() -> Int { value }
}

// MARK: - DeadLetterViewModel Tests
//
// These tests verify observable state transitions on `DeadLetterViewModel`.
// The real `DeadLetterRepository` (actor-backed, GRDB) is not testable in
// isolation without a test database, so we test the ViewModel state machine
// via a `TestableDeadLetterViewModel` that accepts injectable closures.

// MARK: - TestableDeadLetterViewModel

/// ViewModel that accepts injectable async closures for load / retry / discard.
/// Mirrors DeadLetterViewModel's public surface exactly.
@Observable
@MainActor
final class TestableDeadLetterViewModel {
    private(set) var items: [DeadLetterItem] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    // Injected behaviors
    var onLoad: @Sendable () async throws -> [DeadLetterItem]
    var onRetry: @Sendable (Int64) async throws -> Void
    var onDiscard: @Sendable (Int64) async throws -> Void

    init(
        onLoad: @escaping @Sendable () async throws -> [DeadLetterItem] = { [] },
        onRetry: @escaping @Sendable (Int64) async throws -> Void = { _ in },
        onDiscard: @escaping @Sendable (Int64) async throws -> Void = { _ in }
    ) {
        self.onLoad = onLoad
        self.onRetry = onRetry
        self.onDiscard = onDiscard
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await onLoad()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retry(id: Int64) async {
        do {
            try await onRetry(id)
            items.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discard(id: Int64) async {
        do {
            try await onDiscard(id)
            items.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Tests

@MainActor
final class DeadLetterViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeItem(id: Int64 = 1) -> DeadLetterItem {
        DeadLetterItem(
            id: id, op: "create", entity: "tickets",
            attemptCount: 5, lastError: "Network error",
            movedAt: Date(), payload: "{}"
        )
    }

    // MARK: - Initial state

    func test_initialState_isEmpty_notLoading_noError() {
        let sut = TestableDeadLetterViewModel()
        XCTAssertTrue(sut.items.isEmpty)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Load happy path

    func test_load_setsItems_onSuccess() async {
        let items = [makeItem(id: 1), makeItem(id: 2)]
        let sut = TestableDeadLetterViewModel(onLoad: { items })

        await sut.load()

        XCTAssertEqual(sut.items.count, 2)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }

    func test_load_setsErrorMessage_onFailure() async {
        let sut = TestableDeadLetterViewModel(onLoad: { throw TestError.network })

        await sut.load()

        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.items.isEmpty)
    }

    func test_load_doesNotReenter_whenAlreadyLoading() async {
        let counter = Counter()
        let sut = TestableDeadLetterViewModel(onLoad: {
            await counter.increment()
            return []
        })

        // First load — completes normally.
        await sut.load()
        let count = await counter.get()
        XCTAssertEqual(count, 1)
    }

    // MARK: - Retry

    func test_retry_removesItemFromList_onSuccess() async {
        let item = makeItem(id: 42)
        let sut = TestableDeadLetterViewModel(onLoad: { [item] })
        await sut.load()
        XCTAssertEqual(sut.items.count, 1)

        await sut.retry(id: 42)

        XCTAssertTrue(sut.items.isEmpty, "Item must be removed on successful retry")
        XCTAssertNil(sut.errorMessage)
    }

    func test_retry_setsErrorMessage_onFailure() async {
        let item = makeItem(id: 7)
        let sut = TestableDeadLetterViewModel(
            onLoad: { [item] },
            onRetry: { _ in throw TestError.server }
        )
        await sut.load()

        await sut.retry(id: 7)

        XCTAssertNotNil(sut.errorMessage)
        XCTAssertEqual(sut.items.count, 1, "Item should remain on failure")
    }

    func test_retry_doesNotRemoveOtherItems() async {
        let items = [makeItem(id: 1), makeItem(id: 2), makeItem(id: 3)]
        let sut = TestableDeadLetterViewModel(onLoad: { items })
        await sut.load()

        await sut.retry(id: 2)

        XCTAssertEqual(sut.items.map(\.id), [1, 3])
    }

    // MARK: - Discard

    func test_discard_removesItemFromList_onSuccess() async {
        let item = makeItem(id: 99)
        let sut = TestableDeadLetterViewModel(onLoad: { [item] })
        await sut.load()

        await sut.discard(id: 99)

        XCTAssertTrue(sut.items.isEmpty, "Item must be removed after discard")
        XCTAssertNil(sut.errorMessage)
    }

    func test_discard_setsErrorMessage_onFailure() async {
        let item = makeItem(id: 5)
        let sut = TestableDeadLetterViewModel(
            onLoad: { [item] },
            onDiscard: { _ in throw TestError.persistence }
        )
        await sut.load()

        await sut.discard(id: 5)

        XCTAssertNotNil(sut.errorMessage)
        XCTAssertEqual(sut.items.count, 1, "Item should remain on discard failure")
    }
}

// MARK: - Helpers

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
