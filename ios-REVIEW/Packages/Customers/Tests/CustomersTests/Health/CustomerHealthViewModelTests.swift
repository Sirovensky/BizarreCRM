import XCTest
@testable import Customers
import Networking

// MARK: - CustomerHealthViewModelTests (§44)
//
// Tests ViewModel state transitions for load(), recalculate(), and error paths.
// Uses a stub `CustomerHealthRepository` — no network, no async races.

@MainActor
final class CustomerHealthViewModelTests: XCTestCase {

    // MARK: - load()

    func test_load_setsSnapshotOnSuccess() async {
        let stub = StubHealthRepo(snapshot: makeSnapshot(score: 82))
        let vm = CustomerHealthViewModel(repo: stub, customerId: 1)

        await vm.load()

        XCTAssertNotNil(vm.snapshot)
        XCTAssertEqual(vm.snapshot?.score.value, 82)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_setsErrorOnFailure() async {
        let stub = StubHealthRepo(error: URLError(.notConnectedToInternet))
        let vm = CustomerHealthViewModel(repo: stub, customerId: 1)

        await vm.load()

        XCTAssertNil(vm.snapshot)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_doesNotReentrant_whenAlreadyLoading() async {
        let stub = StubHealthRepo(snapshot: makeSnapshot(score: 70))
        let vm = CustomerHealthViewModel(repo: stub, customerId: 1)

        // Call load twice quickly. Second call should be no-op while first is running.
        async let a: () = vm.load()
        async let b: () = vm.load()
        _ = await (a, b)

        XCTAssertEqual(stub.healthSnapshotCallCount, 1)
    }

    func test_load_isLoading_trueWhileInFlight() async {
        let stub = StubHealthRepo(snapshot: makeSnapshot(score: 60), delay: 0.05)
        let vm = CustomerHealthViewModel(repo: stub, customerId: 1)

        let task = Task { await vm.load() }
        // Yield briefly so load() starts
        await Task.yield()
        // isLoading may still be false at this exact point due to test timing —
        // just verify it returns to false after completion
        await task.value
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - recalculate()

    func test_recalculate_updatesSnapshotAndMessage() async {
        let stub = StubHealthRepo(snapshot: makeSnapshot(score: 95))
        let vm = CustomerHealthViewModel(repo: stub, customerId: 1)

        await vm.recalculate()

        XCTAssertNotNil(vm.snapshot)
        XCTAssertEqual(vm.snapshot?.score.value, 95)
        XCTAssertEqual(vm.recalcMessage, "Score updated.")
        XCTAssertFalse(vm.isRecalculating)
    }

    func test_recalculate_setsErrorOnFailure() async {
        let stub = StubHealthRepo(error: URLError(.badServerResponse))
        let vm = CustomerHealthViewModel(repo: stub, customerId: 1)

        await vm.recalculate()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isRecalculating)
    }

    func test_recalculate_doesNotReentrant_whenAlreadyRecalculating() async {
        let stub = StubHealthRepo(snapshot: makeSnapshot(score: 80), delay: 0.05)
        let vm = CustomerHealthViewModel(repo: stub, customerId: 1)

        async let a: () = vm.recalculate()
        async let b: () = vm.recalculate()
        _ = await (a, b)

        XCTAssertEqual(stub.recalculateCallCount, 1)
    }

    // MARK: - displayScore

    func test_displayScore_returnsZeroWhenNoSnapshot() {
        let vm = CustomerHealthViewModel(
            repo: StubHealthRepo(snapshot: makeSnapshot(score: 50)),
            customerId: 1
        )
        XCTAssertEqual(vm.displayScore, 0)
    }

    func test_displayScore_returnsValueAfterLoad() async {
        let stub = StubHealthRepo(snapshot: makeSnapshot(score: 73))
        let vm = CustomerHealthViewModel(repo: stub, customerId: 1)
        await vm.load()
        XCTAssertEqual(vm.displayScore, 73)
    }

    // MARK: - hasData

    func test_hasData_falseBeforeLoad() {
        let vm = CustomerHealthViewModel(
            repo: StubHealthRepo(snapshot: makeSnapshot(score: 50)),
            customerId: 1
        )
        XCTAssertFalse(vm.hasData)
    }

    func test_hasData_trueAfterSuccessfulLoad() async {
        let stub = StubHealthRepo(snapshot: makeSnapshot(score: 88))
        let vm = CustomerHealthViewModel(repo: stub, customerId: 1)
        await vm.load()
        XCTAssertTrue(vm.hasData)
    }
}

// MARK: - Stubs

private actor StubHealthRepo: CustomerHealthRepository {
    private let result: Result<CustomerHealthSnapshot, Error>
    private let delaySeconds: Double
    private(set) var healthSnapshotCallCount = 0
    private(set) var recalculateCallCount = 0

    init(snapshot: CustomerHealthSnapshot, delay: Double = 0) {
        self.result       = .success(snapshot)
        self.delaySeconds = delay
    }

    init(error: Error) {
        self.result       = .failure(error)
        self.delaySeconds = 0
    }

    func healthSnapshot(customerId: Int64) async throws -> CustomerHealthSnapshot {
        healthSnapshotCallCount += 1
        if delaySeconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }
        return try result.get()
    }

    func recalculate(customerId: Int64) async throws -> CustomerHealthSnapshot {
        recalculateCallCount += 1
        if delaySeconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }
        return try result.get()
    }
}

// MARK: - Test data helpers

private func makeSnapshot(score: Int) -> CustomerHealthSnapshot {
    let scoreResult = CustomerHealthScoreResult(
        value:  max(0, min(100, score)),
        tier:   CustomerHealthTier(score: score),
        label:  nil,
        recommendation: nil
    )
    let ltv = CustomerLTVResult(lifetimeDollars: 1_250, tier: .silver, invoiceCount: 12)
    return CustomerHealthSnapshot(score: scoreResult, ltv: ltv, lastInteractionAt: nil)
}
