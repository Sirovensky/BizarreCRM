import XCTest
@testable import Notifications
import Core

// MARK: - Stub TelemetryFlusher

final class CapturingTelemetryFlusher: TelemetryFlusher, @unchecked Sendable {
    var flushedBatches: [[TelemetryRecord]] = []
    func flush(_ events: [TelemetryRecord]) async throws {
        flushedBatches.append(events)
    }
}

// MARK: - Tests

final class SilentPushMetricsTests: XCTestCase {

    private func makeMetrics() -> SilentPushMetrics {
        SilentPushMetrics()
    }

    // MARK: - Initial state

    func test_initialState_allCountersAreZero() async {
        let m = makeMetrics()
        let received   = await m.totalReceived
        let processed  = await m.totalProcessed
        let duplicates = await m.totalDuplicates
        let expired    = await m.totalExpired
        let hitRate    = await m.hitRate
        XCTAssertEqual(received, 0)
        XCTAssertEqual(processed, 0)
        XCTAssertEqual(duplicates, 0)
        XCTAssertEqual(expired, 0)
        XCTAssertEqual(hitRate, 0)
    }

    // MARK: - recordReceived

    func test_recordReceived_incrementsTotal() async {
        let m = makeMetrics()
        await m.recordReceived(kind: "sms")
        await m.recordReceived(kind: "ticket")
        let total = await m.totalReceived
        XCTAssertEqual(total, 2)
    }

    func test_recordReceived_populatesKindSnapshot() async {
        let m = makeMetrics()
        await m.recordReceived(kind: "sms")
        await m.recordReceived(kind: "sms")
        await m.recordReceived(kind: "ticket")
        let snapshot = await m.receivedByKindSnapshot
        XCTAssertEqual(snapshot["sms"], 2)
        XCTAssertEqual(snapshot["ticket"], 1)
    }

    // MARK: - recordProcessed / recordDuplicate / recordExpired

    func test_recordProcessed_incrementsProcessed() async {
        let m = makeMetrics()
        await m.recordReceived(kind: "sms")
        await m.recordProcessed(kind: "sms")
        let processed = await m.totalProcessed
        XCTAssertEqual(processed, 1)
    }

    func test_recordDuplicate_incrementsDuplicates() async {
        let m = makeMetrics()
        await m.recordDuplicate(kind: "sms")
        let dup = await m.totalDuplicates
        XCTAssertEqual(dup, 1)
    }

    func test_recordExpired_incrementsExpired() async {
        let m = makeMetrics()
        await m.recordExpired(kind: "sms")
        let exp = await m.totalExpired
        XCTAssertEqual(exp, 1)
    }

    // MARK: - hitRate

    func test_hitRate_isZeroWhenNothingReceived() async {
        let m = makeMetrics()
        let rate = await m.hitRate
        XCTAssertEqual(rate, 0)
    }

    func test_hitRate_computedCorrectly() async {
        let m = makeMetrics()
        // 4 received, 3 processed
        for _ in 0..<4 { await m.recordReceived(kind: "ticket") }
        for _ in 0..<3 { await m.recordProcessed(kind: "ticket") }
        let rate = await m.hitRate
        XCTAssertEqual(rate, 0.75, accuracy: 0.001)
    }

    func test_hitRate_isOneWhenAllProcessed() async {
        let m = makeMetrics()
        for _ in 0..<5 { await m.recordReceived(kind: "sync") }
        for _ in 0..<5 { await m.recordProcessed(kind: "sync") }
        let rate = await m.hitRate
        XCTAssertEqual(rate, 1.0, accuracy: 0.001)
    }

    // MARK: - Timers

    func test_startStopTimer_recordsMeanDuration() async {
        let m = makeMetrics()
        let token = await m.startTimer(kind: "sms")
        // Simulate a tiny delay without sleeping — just call stop immediately;
        // elapsed will be near-zero but positive.
        await m.stopTimer(token, kind: "sms")
        let mean = await m.meanDuration(for: "sms")
        XCTAssertNotNil(mean)
        XCTAssertGreaterThanOrEqual(mean!, 0)
    }

    func test_meanDuration_nilBeforeAnyTimerStopped() async {
        let m = makeMetrics()
        let mean = await m.meanDuration(for: "ticket")
        XCTAssertNil(mean)
    }

    func test_meanDuration_averagesMultipleSamples() async {
        let m = makeMetrics()
        for _ in 0..<3 {
            let t = await m.startTimer(kind: "ticket")
            await m.stopTimer(t, kind: "ticket")
        }
        let mean = await m.meanDuration(for: "ticket")
        XCTAssertNotNil(mean)
        XCTAssertGreaterThanOrEqual(mean!, 0)
    }

    func test_stoppingUnknownToken_doesNotCrash() async {
        let m = makeMetrics()
        // Start a timer on a different instance (orphaned token)
        let other = makeMetrics()
        let token = await other.startTimer(kind: "sms")
        // Stopping on `m` — token unknown, must be a no-op
        await m.stopTimer(token, kind: "sms")
        let mean = await m.meanDuration(for: "sms")
        XCTAssertNil(mean)
    }

    // MARK: - reset

    func test_reset_clearsAllCounters() async {
        let m = makeMetrics()
        await m.recordReceived(kind: "sms")
        await m.recordProcessed(kind: "sms")
        await m.recordDuplicate(kind: "sms")
        await m.recordExpired(kind: "sms")
        let t = await m.startTimer(kind: "sms")
        await m.stopTimer(t, kind: "sms")
        await m.reset()

        let received  = await m.totalReceived
        let processed = await m.totalProcessed
        let dup       = await m.totalDuplicates
        let exp       = await m.totalExpired
        let mean      = await m.meanDuration(for: "sms")
        let snapshot  = await m.receivedByKindSnapshot

        XCTAssertEqual(received,  0)
        XCTAssertEqual(processed, 0)
        XCTAssertEqual(dup,       0)
        XCTAssertEqual(exp,       0)
        XCTAssertNil(mean)
        XCTAssertTrue(snapshot.isEmpty)
    }

    // MARK: - flush

    func test_flush_noOp_whenNothingReceived() async {
        let flusher = CapturingTelemetryFlusher()
        let buffer  = TelemetryBuffer(flusher: flusher, startTimer: false)
        let m = makeMetrics()
        await m.setTelemetryBuffer(buffer)
        await m.flush()
        XCTAssertTrue(flusher.flushedBatches.isEmpty)
    }

    func test_flush_emitsMetricsRecord_toBuffer() async {
        let flusher = CapturingTelemetryFlusher()
        let buffer  = TelemetryBuffer(flusher: flusher, startTimer: false)
        let m = makeMetrics()
        await m.setTelemetryBuffer(buffer)

        await m.recordReceived(kind: "sms")
        await m.recordProcessed(kind: "sms")
        await m.flush()

        // Flush the buffer so events reach the flusher.
        await buffer.flush()

        XCTAssertFalse(flusher.flushedBatches.isEmpty)
        let allRecords = flusher.flushedBatches.flatMap { $0 }
        let metricsRecord = allRecords.first { $0.name == "silent_push.metrics" }
        XCTAssertNotNil(metricsRecord)
        XCTAssertEqual(metricsRecord?.properties["received"],  "1")
        XCTAssertEqual(metricsRecord?.properties["processed"], "1")
    }

    func test_flush_emitsDurationRecord_whenTimerWasStopped() async {
        let flusher = CapturingTelemetryFlusher()
        let buffer  = TelemetryBuffer(flusher: flusher, startTimer: false)
        let m = makeMetrics()
        await m.setTelemetryBuffer(buffer)

        await m.recordReceived(kind: "ticket")
        let t = await m.startTimer(kind: "ticket")
        await m.stopTimer(t, kind: "ticket")
        await m.flush()
        await buffer.flush()

        let allRecords = flusher.flushedBatches.flatMap { $0 }
        let durationRecord = allRecords.first { $0.name == "silent_push.duration" }
        XCTAssertNotNil(durationRecord)
        XCTAssertEqual(durationRecord?.properties["kind"], "ticket")
    }

    func test_flush_resetsCounters() async {
        let m = makeMetrics()
        await m.recordReceived(kind: "sms")
        await m.flush()
        let received = await m.totalReceived
        XCTAssertEqual(received, 0)
    }

    func test_flush_worksWithoutBuffer() async {
        let m = makeMetrics()
        await m.recordReceived(kind: "sms")
        // No buffer injected — should not crash.
        await m.flush()
        let received = await m.totalReceived
        XCTAssertEqual(received, 0)
    }
}
