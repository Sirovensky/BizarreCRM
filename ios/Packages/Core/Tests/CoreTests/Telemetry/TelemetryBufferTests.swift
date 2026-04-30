import XCTest
@testable import Core

// §32 Telemetry Sovereignty Guardrails — TelemetryBuffer unit tests

// MARK: - Spy flusher

/// Captures flush calls without hitting the network.
actor SpyFlusher: TelemetryFlusher {

    private(set) var flushCallCount = 0
    private(set) var flushedBatches: [[TelemetryRecord]] = []
    var shouldThrow = false

    func flush(_ events: [TelemetryRecord]) async throws {
        flushCallCount += 1
        if shouldThrow {
            throw URLError(.notConnectedToInternet)
        }
        flushedBatches.append(events)
    }

    var allFlushedEvents: [TelemetryRecord] {
        flushedBatches.flatMap { $0 }
    }
}

// MARK: - Helpers

extension TelemetryRecord {
    static func stub(
        category: TelemetryCategory = .domain,
        name: String = "test.event",
        properties: [String: String] = [:]
    ) -> TelemetryRecord {
        TelemetryRecord(category: category, name: name, properties: properties)
    }
}

// MARK: - TelemetryBufferTests

final class TelemetryBufferTests: XCTestCase {

    // MARK: - Threshold flush

    func test_bufferFlushes_whenCapacityReached() async {
        let spy = SpyFlusher()
        let buffer = TelemetryBuffer(flusher: spy, capacity: 3, startTimer: false)

        await buffer.enqueue(.stub(name: "e1"))
        await buffer.enqueue(.stub(name: "e2"))
        // Not yet flushed
        let countBefore = await spy.flushCallCount
        XCTAssertEqual(countBefore, 0)

        await buffer.enqueue(.stub(name: "e3"))   // triggers flush at capacity 3
        let countAfter = await spy.flushCallCount
        XCTAssertEqual(countAfter, 1, "Flush must fire exactly when capacity is reached")
    }

    func test_bufferSendsBatchWithAllEvents_onThresholdFlush() async {
        let spy = SpyFlusher()
        let buffer = TelemetryBuffer(flusher: spy, capacity: 2, startTimer: false)

        await buffer.enqueue(.stub(name: "alpha"))
        await buffer.enqueue(.stub(name: "beta"))

        let batches = await spy.flushedBatches
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].map(\.name), ["alpha", "beta"])
    }

    func test_bufferIsEmpty_afterThresholdFlush() async {
        let spy = SpyFlusher()
        let buffer = TelemetryBuffer(flusher: spy, capacity: 2, startTimer: false)

        await buffer.enqueue(.stub())
        await buffer.enqueue(.stub())

        let pending = await buffer.pendingCount
        XCTAssertEqual(pending, 0)
    }

    func test_additionalEventsAfterFlush_doNotIncludeAlreadyFlushed() async {
        let spy = SpyFlusher()
        let buffer = TelemetryBuffer(flusher: spy, capacity: 2, startTimer: false)

        await buffer.enqueue(.stub(name: "first"))
        await buffer.enqueue(.stub(name: "second"))   // flush fires
        await buffer.enqueue(.stub(name: "third"))    // new accumulation

        await buffer.flush()

        let all = await spy.allFlushedEvents
        let names = all.map(\.name)
        // first batch: [first, second]; second batch: [third]
        XCTAssertEqual(names.filter { $0 == "first" }.count, 1)
        XCTAssertEqual(names.filter { $0 == "third" }.count, 1)
    }

    // MARK: - Manual flush

    func test_manualFlush_sendsAllPendingEvents() async {
        let spy = SpyFlusher()
        let buffer = TelemetryBuffer(flusher: spy, capacity: 100, startTimer: false)

        for i in 1...5 {
            await buffer.enqueue(.stub(name: "event\(i)"))
        }
        let beforeFlushCallCount = await spy.flushCallCount
        XCTAssertEqual(beforeFlushCallCount, 0)

        await buffer.flush()

        let callCount = await spy.flushCallCount
        XCTAssertEqual(callCount, 1)
        let events = await spy.allFlushedEvents
        XCTAssertEqual(events.count, 5)
    }

    func test_manualFlush_onEmptyBuffer_isNoop() async {
        let spy = SpyFlusher()
        let buffer = TelemetryBuffer(flusher: spy, capacity: 50, startTimer: false)

        await buffer.flush()

        let callCount = await spy.flushCallCount
        XCTAssertEqual(callCount, 0, "Flush on empty buffer must not call flusher")
    }

    func test_pendingCount_reflectsBufferSize() async {
        let spy = SpyFlusher()
        let buffer = TelemetryBuffer(flusher: spy, capacity: 100, startTimer: false)

        let count0 = await buffer.pendingCount
        XCTAssertEqual(count0, 0)
        await buffer.enqueue(.stub())
        let count1 = await buffer.pendingCount
        XCTAssertEqual(count1, 1)
        await buffer.enqueue(.stub())
        let count2 = await buffer.pendingCount
        XCTAssertEqual(count2, 2)
    }

    // MARK: - Error handling / re-queue

    func test_onFlusherFailure_eventsAreRequeued() async {
        let spy = SpyFlusher()
        await spy.setShouldThrow(true)

        let buffer = TelemetryBuffer(flusher: spy, capacity: 100, startTimer: false)
        await buffer.enqueue(.stub(name: "will_fail"))
        await buffer.flush()

        let pending = await buffer.pendingCount
        XCTAssertEqual(pending, 1, "Failed event must be re-queued")
    }

    func test_onFlusherFailure_bufferCappedAt2xCapacity() async {
        let spy = SpyFlusher()
        await spy.setShouldThrow(true)

        let buffer = TelemetryBuffer(flusher: spy, capacity: 3, startTimer: false)
        // Enqueue 7 events — first 3 trigger a flush, which fails and re-queues 3.
        // Then 4 more are enqueued, totalling 7. Second flush fails, re-queues 7.
        // Cap is 3*2 = 6, so 1 oldest event should be dropped.
        for i in 1...7 {
            await buffer.enqueue(.stub(name: "e\(i)"))
        }
        await buffer.flush() // triggers with partial batch; test just checks cap

        let pending = await buffer.pendingCount
        XCTAssertLessThanOrEqual(pending, 6, "Buffer must not exceed capacity * 2 after repeated failures")
    }
}

// MARK: - Actor extension for test mutation

private extension SpyFlusher {
    func setShouldThrow(_ value: Bool) {
        shouldThrow = value
    }
}
