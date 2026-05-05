import XCTest
@testable import Hardware

// MARK: - Mock Engine

/// Controllable mock: can be told to fail N times before succeeding.
final class MockPrintEngine: PrintEngine, @unchecked Sendable {
    nonisolated(unsafe) var failCount: Int
    nonisolated(unsafe) var printCallCount: Int = 0
    nonisolated(unsafe) var lastJob: PrintJob?
    nonisolated(unsafe) var lastPrinter: Printer?

    init(failCount: Int = 0) {
        self.failCount = failCount
    }

    func discover() async throws -> [Printer] { [] }

    func print(_ job: PrintJob, on printer: Printer) async throws {
        printCallCount += 1
        lastJob = job
        lastPrinter = printer

        if printCallCount <= failCount {
            throw PrintEngineError.printerNotReachable("mock-fail-\(printCallCount)")
        }
    }
}

// MARK: - PrintJobQueueTests

final class PrintJobQueueTests: XCTestCase {

    // MARK: - Helpers

    private static let samplePrinter = Printer(
        id: "test-printer",
        name: "Test Printer",
        kind: .thermalReceipt,
        connection: .network(host: "192.168.1.100", port: 9100)
    )

    private static func sampleJob() -> PrintJob {
        let payload = ReceiptPayload(
            tenantName: "Shop",
            tenantAddress: "1 Main St",
            tenantPhone: "555-0000",
            receiptNumber: "R-\(Int.random(in: 1000...9999))",
            createdAt: Date(),
            lineItems: [],
            subtotalCents: 100,
            taxCents: 10,
            tipCents: 0,
            totalCents: 110,
            paymentTender: "Cash",
            cashierName: "Bot"
        )
        return PrintJob(kind: .receipt, payload: .receipt(payload))
    }

    // MARK: - enqueue + immediate success

    func test_enqueue_successfulPrint_clearsQueue() async {
        let engine = MockPrintEngine(failCount: 0)
        let queue = PrintJobQueue(engine: engine, policy: .default)
        let job = Self.sampleJob()

        await queue.enqueue(job, to: Self.samplePrinter)

        let pending = await queue.pendingCount
        let deadLetter = await queue.deadLetterCount
        XCTAssertEqual(pending, 0, "Queue should be empty after successful print")
        XCTAssertEqual(deadLetter, 0, "No dead-letter entries on success")
        XCTAssertEqual(engine.printCallCount, 1)
    }

    func test_enqueue_callsEngineWithCorrectJobAndPrinter() async {
        let engine = MockPrintEngine(failCount: 0)
        let queue = PrintJobQueue(engine: engine, policy: .default)
        let job = Self.sampleJob()

        await queue.enqueue(job, to: Self.samplePrinter)

        XCTAssertEqual(engine.lastJob?.id, job.id)
        XCTAssertEqual(engine.lastPrinter?.id, Self.samplePrinter.id)
    }

    // MARK: - retry on failure

    func test_enqueue_retriesOnTransientFailure_andSucceeds() async {
        // Fail first attempt, succeed on second
        let engine = MockPrintEngine(failCount: 1)
        let policy = PrintJobQueue.Policy(maxAttempts: 3, baseBackoffSeconds: 0.01)
        let queue = PrintJobQueue(engine: engine, policy: policy)

        await queue.enqueue(Self.sampleJob(), to: Self.samplePrinter)

        let pending = await queue.pendingCount
        let deadLetter = await queue.deadLetterCount
        XCTAssertEqual(pending, 0)
        XCTAssertEqual(deadLetter, 0)
        XCTAssertEqual(engine.printCallCount, 2, "Should have retried once")
    }

    func test_enqueue_retriesTwiceAndSucceeds() async {
        let engine = MockPrintEngine(failCount: 2)
        let policy = PrintJobQueue.Policy(maxAttempts: 3, baseBackoffSeconds: 0.01)
        let queue = PrintJobQueue(engine: engine, policy: policy)

        await queue.enqueue(Self.sampleJob(), to: Self.samplePrinter)

        let pending = await queue.pendingCount
        let deadLetter = await queue.deadLetterCount
        XCTAssertEqual(pending, 0)
        XCTAssertEqual(deadLetter, 0)
        XCTAssertEqual(engine.printCallCount, 3, "Should have made 3 attempts total")
    }

    // MARK: - dead-letter

    func test_enqueue_deadLettersAfterMaxAttempts() async {
        let engine = MockPrintEngine(failCount: 99) // always fails
        let policy = PrintJobQueue.Policy(maxAttempts: 3, baseBackoffSeconds: 0.01)
        let queue = PrintJobQueue(engine: engine, policy: policy)

        await queue.enqueue(Self.sampleJob(), to: Self.samplePrinter)

        let pending = await queue.pendingCount
        let deadLetter = await queue.deadLetterCount
        XCTAssertEqual(pending, 0, "Failed job must leave pending queue")
        XCTAssertEqual(deadLetter, 1, "Failed job must end up in dead-letter queue")
        XCTAssertEqual(engine.printCallCount, 3, "Should have tried maxAttempts times")
    }

    func test_deadLetterJob_preservesJobId() async {
        let engine = MockPrintEngine(failCount: 99)
        let policy = PrintJobQueue.Policy(maxAttempts: 1, baseBackoffSeconds: 0.01)
        let queue = PrintJobQueue(engine: engine, policy: policy)
        let job = Self.sampleJob()

        await queue.enqueue(job, to: Self.samplePrinter)

        let deadLetterJobs = await queue.deadLetterJobs
        XCTAssertEqual(deadLetterJobs.first?.id, job.id)
    }

    func test_deadLetterJob_hasLastErrorSet() async {
        let engine = MockPrintEngine(failCount: 99)
        let policy = PrintJobQueue.Policy(maxAttempts: 1, baseBackoffSeconds: 0.01)
        let queue = PrintJobQueue(engine: engine, policy: policy)

        await queue.enqueue(Self.sampleJob(), to: Self.samplePrinter)

        let deadLetterJobs = await queue.deadLetterJobs
        XCTAssertNotNil(deadLetterJobs.first?.lastError, "Dead-letter entry must record last error")
    }

    // MARK: - retry dead-letter

    func test_retryDeadLetter_reEnqueuesAndSucceedsOnRetry() async {
        let engine = MockPrintEngine(failCount: 1)
        let policy = PrintJobQueue.Policy(maxAttempts: 1, baseBackoffSeconds: 0.01)
        let queue = PrintJobQueue(engine: engine, policy: policy)
        let job = Self.sampleJob()

        // First enqueue — will fail and dead-letter
        await queue.enqueue(job, to: Self.samplePrinter)

        let deadLetterCount = await queue.deadLetterCount
        XCTAssertEqual(deadLetterCount, 1)

        // Now retry with higher maxAttempts (simulate recovery)
        // engine's failCount is 1 and printCallCount is 1, so next attempt succeeds
        await queue.retryDeadLetter(id: job.id)

        let finalDeadLetter = await queue.deadLetterCount
        let finalPending = await queue.pendingCount
        XCTAssertEqual(finalDeadLetter, 0, "Successful retry should remove from dead-letter")
        XCTAssertEqual(finalPending, 0)
    }

    // MARK: - discard dead-letter

    func test_discardDeadLetter_removesEntry() async {
        let engine = MockPrintEngine(failCount: 99)
        let policy = PrintJobQueue.Policy(maxAttempts: 1, baseBackoffSeconds: 0.01)
        let queue = PrintJobQueue(engine: engine, policy: policy)
        let job = Self.sampleJob()

        await queue.enqueue(job, to: Self.samplePrinter)
        let beforeCount = await queue.deadLetterCount
        XCTAssertEqual(beforeCount, 1)

        await queue.discardDeadLetter(id: job.id)

        let afterCount = await queue.deadLetterCount
        XCTAssertEqual(afterCount, 0)
    }

    func test_clearDeadLetterQueue_removesAll() async {
        let engine = MockPrintEngine(failCount: 99)
        let policy = PrintJobQueue.Policy(maxAttempts: 1, baseBackoffSeconds: 0.01)
        let queue = PrintJobQueue(engine: engine, policy: policy)

        // Enqueue 3 jobs — all will dead-letter
        for _ in 0..<3 {
            await queue.enqueue(Self.sampleJob(), to: Self.samplePrinter)
        }

        let beforeCount = await queue.deadLetterCount
        XCTAssertEqual(beforeCount, 3)

        await queue.clearDeadLetterQueue()

        let afterCount = await queue.deadLetterCount
        XCTAssertEqual(afterCount, 0)
    }

    // MARK: - policy

    func test_policy_defaultValues() {
        let policy = PrintJobQueue.Policy.default
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertEqual(policy.baseBackoffSeconds, 1.0)
    }

    func test_policy_clampsMaxAttemptsToMinimumOne() {
        let policy = PrintJobQueue.Policy(maxAttempts: 0, baseBackoffSeconds: 0.1)
        XCTAssertEqual(policy.maxAttempts, 1)
    }

    func test_policy_clampsBackoffToMinimum() {
        let policy = PrintJobQueue.Policy(maxAttempts: 3, baseBackoffSeconds: 0)
        XCTAssertGreaterThanOrEqual(policy.baseBackoffSeconds, 0.1)
    }

    // MARK: - Printer.withStatus

    func test_printer_withStatus_returnsNewInstance_notMutating() {
        let printer = Self.samplePrinter
        let updated = printer.withStatus(.printing)
        XCTAssertEqual(printer.status, .idle, "Original must remain unchanged")
        XCTAssertEqual(updated.status, .printing)
        XCTAssertEqual(updated.id, printer.id, "ID must be preserved")
    }

    // MARK: - Copies support (§17 reprint options)

    func test_enqueue_2copies_callsEngineExactlyTwice() async {
        let engine = MockPrintEngine(failCount: 0)
        let queue = PrintJobQueue(engine: engine, policy: .default)
        let job = PrintJob(
            kind: .receipt,
            payload: Self.sampleJob().payload,
            copies: 2
        )
        await queue.enqueue(job, to: Self.samplePrinter)

        let pending = await queue.pendingCount
        XCTAssertEqual(pending, 0, "All copies should have printed")
        XCTAssertEqual(engine.printCallCount, 2, "Engine should be called once per copy")
    }

    func test_enqueue_3copies_callsEngineExactlyThreeTimes() async {
        let engine = MockPrintEngine(failCount: 0)
        let queue = PrintJobQueue(engine: engine, policy: .default)
        let job = PrintJob(
            kind: .label,
            payload: Self.sampleJob().payload,
            copies: 3
        )
        await queue.enqueue(job, to: Self.samplePrinter)

        XCTAssertEqual(engine.printCallCount, 3)
    }

    func test_enqueue_copiesZero_treatedAs1() async {
        let engine = MockPrintEngine(failCount: 0)
        let queue = PrintJobQueue(engine: engine, policy: .default)
        let job = PrintJob(
            kind: .receipt,
            payload: Self.sampleJob().payload,
            copies: 0   // should be clamped to 1 in PrintJob.init
        )
        // copies == 0 is clamped to 1 by PrintJob, so engine called once.
        await queue.enqueue(job, to: Self.samplePrinter)
        XCTAssertEqual(engine.printCallCount, 1)
    }

    func test_enqueue_firstCopyKeepsOriginalJobId() async {
        let engine = MockPrintEngine(failCount: 0)
        let queue = PrintJobQueue(engine: engine, policy: .default)
        let originalJob = PrintJob(kind: .receipt, payload: Self.sampleJob().payload, copies: 1)
        await queue.enqueue(originalJob, to: Self.samplePrinter)
        XCTAssertEqual(engine.lastJob?.id, originalJob.id, "First (and only) copy must keep original UUID")
    }
}
