import XCTest
@testable import Core

// §71 Privacy-first Analytics — unit tests for AnalyticsDispatcher

// MARK: - Spy TelemetryFlusher

/// Captures enqueued events without hitting the network.
private actor SpyAnalyticsFlusher: TelemetryFlusher {
    private(set) var receivedBatches: [[TelemetryRecord]] = []

    func flush(_ events: [TelemetryRecord]) async throws {
        receivedBatches.append(events)
    }

    var allEvents: [TelemetryRecord] {
        receivedBatches.flatMap { $0 }
    }
}

// MARK: - AnalyticsDispatcherTests

final class AnalyticsDispatcherTests: XCTestCase {

    // We create a fresh buffer for each test to avoid state bleed.
    private var spy: SpyAnalyticsFlusher!
    private var buffer: TelemetryBuffer!

    override func setUp() async throws {
        try await super.setUp()
        spy = SpyAnalyticsFlusher()
        // capacity=1 so every enqueue triggers an immediate flush.
        buffer = TelemetryBuffer(flusher: spy, capacity: 1, startTimer: false)
        AnalyticsDispatcher._replaceBuffer(buffer)
    }

    override func tearDown() async throws {
        AnalyticsDispatcher._replaceBuffer(nil)
        try await super.tearDown()
    }

    // MARK: - log(_:)

    func test_log_whenConfigured_enqueuesEvent() async throws {
        AnalyticsDispatcher.log(.customerCreated)

        // Task is detached — yield to let it run.
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms

        let events = await spy.allEvents
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.name, "customer.created")
    }

    func test_log_setsCorrectCategory() async throws {
        AnalyticsDispatcher.log(.appLaunched(coldStart: true))
        try await Task.sleep(nanoseconds: 50_000_000)

        let events = await spy.allEvents
        XCTAssertEqual(events.first?.category, .appLifecycle)
    }

    func test_log_multipleEvents_allEnqueued() async throws {
        // capacity=1 flushes per event; we bump capacity to accumulate.
        let bigSpy = SpyAnalyticsFlusher()
        let bigBuffer = TelemetryBuffer(flusher: bigSpy, capacity: 100, startTimer: false)
        AnalyticsDispatcher._replaceBuffer(bigBuffer)

        AnalyticsDispatcher.log(.ticketCreated(priority: "high"))
        AnalyticsDispatcher.log(.ticketCreated(priority: "low"))
        AnalyticsDispatcher.log(.customerCreated)

        try await Task.sleep(nanoseconds: 50_000_000)
        await bigBuffer.flush()

        let events = await bigSpy.allEvents
        XCTAssertEqual(events.count, 3)
    }

    // MARK: - log with marker

    func test_log_withMarker_attachesDispatchCtx() async throws {
        let marker = AnalyticsPIIGuard.markSafe("test-context")
        AnalyticsDispatcher.log(.saleCompleted(totalCents: 100, itemCount: 1), marker: marker)
        try await Task.sleep(nanoseconds: 50_000_000)

        let events = await spy.allEvents
        XCTAssertEqual(events.first?.properties["_dispatch_ctx"], "test-context")
    }

    // MARK: - not configured (nil buffer)

    func test_log_whenNotConfigured_isNoop() async throws {
        AnalyticsDispatcher._replaceBuffer(nil)
        // Should not crash:
        AnalyticsDispatcher.log(.appBackgrounded)
        try await Task.sleep(nanoseconds: 20_000_000)
        // No assertion needed — no crash = pass.
    }

    // MARK: - flush

    func test_flush_drainsPendingEvents() async throws {
        let drainSpy = SpyAnalyticsFlusher()
        let drainBuffer = TelemetryBuffer(flusher: drainSpy, capacity: 100, startTimer: false)
        AnalyticsDispatcher._replaceBuffer(drainBuffer)

        AnalyticsDispatcher.log(.commandPaletteOpened)
        AnalyticsDispatcher.log(.commandExecuted(commandId: "cmd_new"))
        try await Task.sleep(nanoseconds: 20_000_000) // let log Tasks enqueue

        AnalyticsDispatcher.flush()
        try await Task.sleep(nanoseconds: 50_000_000) // let flush Task run

        let events = await drainSpy.allEvents
        XCTAssertEqual(events.count, 2,
                       "flush() must drain all pending events")
    }

    func test_flush_whenNotConfigured_isNoop() async throws {
        AnalyticsDispatcher._replaceBuffer(nil)
        AnalyticsDispatcher.flush() // Must not crash
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    // MARK: - PII is redacted before enqueue

    func test_log_redactsEmbeddedEmailInEventProperties() async throws {
        // errorPresented domain can carry an embedded email if caller makes a mistake
        AnalyticsDispatcher.log(.errorPresented(domain: "user@leak.com", code: 400))
        try await Task.sleep(nanoseconds: 50_000_000)

        let events = await spy.allEvents
        if let domain = events.first?.properties["error_domain"] {
            XCTAssertFalse(domain.contains("@"),
                           "Email in error_domain must be redacted before storage, got: \(domain)")
        }
    }

    // MARK: - configure(buffer:)

    func test_configure_replacesBuffer() async throws {
        let newSpy = SpyAnalyticsFlusher()
        let newBuffer = TelemetryBuffer(flusher: newSpy, capacity: 1, startTimer: false)
        AnalyticsDispatcher.configure(buffer: newBuffer)

        AnalyticsDispatcher.log(.featureFirstUse(featureId: "roles_editor"))
        try await Task.sleep(nanoseconds: 50_000_000)

        let originalEvents = await spy.allEvents
        let newEvents = await newSpy.allEvents

        XCTAssertEqual(originalEvents.count, 0, "Original spy should not receive events after reconfigure")
        XCTAssertEqual(newEvents.count, 1)
        XCTAssertEqual(newEvents.first?.name, "feature.first_use")
    }
}
