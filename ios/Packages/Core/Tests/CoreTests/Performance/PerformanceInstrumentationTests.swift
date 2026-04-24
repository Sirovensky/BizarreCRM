import XCTest
@testable import Core

// §29 Performance instrumentation — unit + concurrency tests.
//
// TDD: tests were written before the implementation (RED), then the
// implementation was written to make them pass (GREEN).
//
// Coverage areas:
//   1. PerformanceBudget — threshold values, boundary pass/fail
//   2. BudgetGuard       — predicate correctness (no assertionFailure in tests)
//   3. TraceSession      — begin/end lifecycle, unknown-token safety, concurrency
//   4. PerfEventReporter — rolling window, aggregation, p95

// MARK: - 1. PerformanceBudget Tests

final class PerformanceBudgetTests: XCTestCase {

    // Every operation must have a finite, positive threshold.
    func test_allOperations_havePositiveThreshold() {
        for op in PerformanceOperation.allCases {
            let t = PerformanceBudget.threshold(for: op)
            XCTAssertGreaterThan(t, 0, "\(op.rawValue) threshold should be > 0")
            XCTAssertFalse(t.isInfinite, "\(op.rawValue) should have an explicit threshold")
        }
    }

    func test_launchTTI_threshold_is800ms() {
        XCTAssertEqual(PerformanceBudget.threshold(for: .launchTTI), 800)
    }

    func test_listScroll60fps_threshold_isApprox16_7ms() {
        let t = PerformanceBudget.threshold(for: .listScroll60fps)
        XCTAssertEqual(t, 16.7, accuracy: 0.1)
    }

    func test_detailOpen_threshold_is300ms() {
        XCTAssertEqual(PerformanceBudget.threshold(for: .detailOpenMs), 300)
    }

    func test_saleTransaction_threshold_is2000ms() {
        XCTAssertEqual(PerformanceBudget.threshold(for: .saleTransactionMs), 2_000)
    }

    func test_smsSend_threshold_is3000ms() {
        XCTAssertEqual(PerformanceBudget.threshold(for: .smsSendMs), 3_000)
    }

    // isWithinBudget — boundary cases
    func test_isWithinBudget_exactlyAtThreshold_returnsTrue() {
        let budget = PerformanceBudget.threshold(for: .launchTTI)
        XCTAssertTrue(PerformanceBudget.isWithinBudget(budget, for: .launchTTI))
    }

    func test_isWithinBudget_oneMillisecondOverThreshold_returnsFalse() {
        let budget = PerformanceBudget.threshold(for: .launchTTI)
        XCTAssertFalse(PerformanceBudget.isWithinBudget(budget + 1, for: .launchTTI))
    }

    func test_isWithinBudget_zeroElapsed_returnsTrue() {
        XCTAssertTrue(PerformanceBudget.isWithinBudget(0, for: .launchTTI))
    }
}

// MARK: - 2. BudgetGuard Tests

final class BudgetGuardTests: XCTestCase {

    // We use `isWithinBudget` (the predicate path) so that we never trigger
    // the `assertionFailure` path inside DEBUG builds during tests.

    func test_isWithinBudget_belowThreshold_returnsTrue() {
        XCTAssertTrue(BudgetGuard.isWithinBudget(100, for: .launchTTI))
    }

    func test_isWithinBudget_aboveThreshold_returnsFalse() {
        XCTAssertFalse(BudgetGuard.isWithinBudget(900, for: .launchTTI))
    }

    func test_isWithinBudget_exactlyAtThreshold_returnsTrue() {
        let budget = PerformanceBudget.threshold(for: .saleTransactionMs)
        XCTAssertTrue(BudgetGuard.isWithinBudget(budget, for: .saleTransactionMs))
    }

    func test_check_withinBudget_doesNotAssert() {
        // Should not crash. The implementation only fires assertionFailure when
        // elapsedMs > budget; this value is well within budget.
        BudgetGuard.check(.smsSendMs, elapsedMs: 100)
    }

    func test_isWithinBudget_allOperations_withZero() {
        for op in PerformanceOperation.allCases {
            XCTAssertTrue(BudgetGuard.isWithinBudget(0, for: op), "\(op.rawValue) should pass 0 ms")
        }
    }
}

// MARK: - 3. TraceSession Tests

final class TraceSessionTests: XCTestCase {

    func test_begin_returnsToken_thenEnd_returnsElapsed() async {
        let session = TraceSession()
        let token = await session.begin(.detailOpenMs)
        let elapsed = await session.end(.detailOpenMs, token: token)
        XCTAssertNotNil(elapsed)
        XCTAssertGreaterThanOrEqual(elapsed!, 0)
    }

    func test_inflightCount_incrementsOnBegin_decrementsOnEnd() async {
        let session = TraceSession()
        XCTAssertEqual(await session.inflightCount, 0)

        let token = await session.begin(.smsSendMs)
        XCTAssertEqual(await session.inflightCount, 1)

        await session.end(.smsSendMs, token: token)
        XCTAssertEqual(await session.inflightCount, 0)
    }

    func test_end_withUnknownToken_returnsNil() async {
        let session = TraceSession()
        // Create a token that was never registered in this session.
        let orphanToken = TraceSession.Token(signpostID: .exclusive)
        let result = await session.end(.launchTTI, token: orphanToken)
        XCTAssertNil(result)
    }

    func test_concurrentBegin_allTokensAreUnique() async {
        let session = TraceSession()
        // Launch 20 concurrent begins and verify all tokens are unique.
        var tokens: [TraceSession.Token] = []
        await withTaskGroup(of: TraceSession.Token.self) { group in
            for _ in 0 ..< 20 {
                group.addTask { await session.begin(.listScroll60fps) }
            }
            for await token in group {
                tokens.append(token)
            }
        }
        XCTAssertEqual(tokens.count, 20)
        let uniqueIDs = Set(tokens.map(\.id))
        XCTAssertEqual(uniqueIDs.count, 20, "All tokens must have unique UUIDs")
    }

    func test_concurrentBeginEnd_inflightCountReturnsToZero() async {
        let session = TraceSession()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    let token = await session.begin(.saleTransactionMs)
                    await session.end(.saleTransactionMs, token: token)
                }
            }
        }
        let remaining = await session.inflightCount
        XCTAssertEqual(remaining, 0, "All in-flight intervals should be ended")
    }

    func test_multipleOperations_trackedIndependently() async {
        let session = TraceSession()
        let t1 = await session.begin(.launchTTI)
        let t2 = await session.begin(.smsSendMs)
        XCTAssertEqual(await session.inflightCount, 2)

        await session.end(.launchTTI, token: t1)
        XCTAssertEqual(await session.inflightCount, 1)

        await session.end(.smsSendMs, token: t2)
        XCTAssertEqual(await session.inflightCount, 0)
    }
}

// MARK: - 4. PerfEventReporter Tests

final class PerfEventReporterTests: XCTestCase {

    func test_aggregated_noSamples_returnsEmpty() async {
        let reporter = PerfEventReporter(windowSize: 10)
        let m = await reporter.aggregated(for: .launchTTI)
        XCTAssertEqual(m, .empty)
        XCTAssertEqual(m.count, 0)
    }

    func test_record_oneSample_aggregatesCorrectly() async {
        let reporter = PerfEventReporter(windowSize: 10)
        await reporter.record(.launchTTI, elapsedMs: 400)
        let m = await reporter.aggregated(for: .launchTTI)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m.min, 400)
        XCTAssertEqual(m.max, 400)
        XCTAssertEqual(m.mean, 400)
        XCTAssertEqual(m.p95, 400)
    }

    func test_record_multipleSamples_meanIsCorrect() async {
        let reporter = PerfEventReporter(windowSize: 100)
        let values: [Double] = [100, 200, 300, 400, 500]
        for v in values { await reporter.record(.detailOpenMs, elapsedMs: v) }
        let m = await reporter.aggregated(for: .detailOpenMs)
        XCTAssertEqual(m.count, 5)
        XCTAssertEqual(m.mean, 300, accuracy: 0.01)
        XCTAssertEqual(m.min, 100)
        XCTAssertEqual(m.max, 500)
    }

    func test_record_windowFull_oldestSampleEvicted() async {
        let reporter = PerfEventReporter(windowSize: 3)
        await reporter.record(.smsSendMs, elapsedMs: 1)
        await reporter.record(.smsSendMs, elapsedMs: 2)
        await reporter.record(.smsSendMs, elapsedMs: 3)
        // Window is full; next record evicts the first sample (1 ms).
        await reporter.record(.smsSendMs, elapsedMs: 4)
        let m = await reporter.aggregated(for: .smsSendMs)
        XCTAssertEqual(m.count, 3)
        XCTAssertEqual(m.min, 2)
        XCTAssertEqual(m.max, 4)
    }

    func test_p95_twentySamples() async {
        let reporter = PerfEventReporter(windowSize: 100)
        // Insert 1…20 ms.
        for i in 1 ... 20 { await reporter.record(.saleTransactionMs, elapsedMs: Double(i)) }
        let m = await reporter.aggregated(for: .saleTransactionMs)
        // p95 of [1..20]: ceil(20*0.95) = 19 → index 18 → value 19.
        XCTAssertEqual(m.p95, 19, accuracy: 0.01)
    }

    func test_allAggregated_returnsOnlyRecordedOperations() async {
        let reporter = PerfEventReporter(windowSize: 10)
        await reporter.record(.launchTTI, elapsedMs: 600)
        await reporter.record(.smsSendMs, elapsedMs: 1_200)
        let all = await reporter.allAggregated()
        XCTAssertEqual(all.count, 2)
        XCTAssertNotNil(all[.launchTTI])
        XCTAssertNotNil(all[.smsSendMs])
    }

    func test_reset_clearsAllSamples() async {
        let reporter = PerfEventReporter(windowSize: 10)
        await reporter.record(.launchTTI, elapsedMs: 300)
        await reporter.reset()
        let m = await reporter.aggregated(for: .launchTTI)
        XCTAssertEqual(m, .empty)
    }

    func test_differentOperations_trackedSeparately() async {
        let reporter = PerfEventReporter(windowSize: 10)
        await reporter.record(.launchTTI, elapsedMs: 700)
        await reporter.record(.smsSendMs, elapsedMs: 1_500)
        let launch = await reporter.aggregated(for: .launchTTI)
        let sms = await reporter.aggregated(for: .smsSendMs)
        XCTAssertEqual(launch.mean, 700, accuracy: 0.01)
        XCTAssertEqual(sms.mean, 1_500, accuracy: 0.01)
    }
}
