import XCTest
@testable import Persistence

/// §20.2 / §20.3 — full-stack integration tests that exercise the real
/// SQLite pool, migrations, enqueue path, backoff, and dead-letter
/// promotion. Each test opens a unique temp-dir DB so runs don't share
/// state — important because the actor-level SyncQueueStore keeps the
/// migration + index definitions singleton.
final class SyncQueueIntegrationTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-queue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempURL = dir.appendingPathComponent("test.sqlite")
        try await Database.shared.reopen(at: tempURL)
    }

    override func tearDown() async throws {
        await Database.shared.close()
        if let url = tempURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Enqueue + due

    func test_enqueue_writesRow_andDueReturnsIt() async throws {
        let record = SyncQueueRecord(op: "create", entity: "customer", payload: #"{"x":1}"#)
        try await SyncQueueStore.shared.enqueue(record)

        let due = try await SyncQueueStore.shared.due(limit: 10)
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.op, "create")
        XCTAssertEqual(due.first?.entity, "customer")
        XCTAssertEqual(due.first?.status, SyncQueueRecord.Status.queued.rawValue)
    }

    func test_enqueue_idempotent_onSameKey() async throws {
        let key = UUID().uuidString
        let r1 = SyncQueueRecord(op: "create", entity: "ticket", payload: "{}",
                                  idempotencyKey: key)
        let r2 = SyncQueueRecord(op: "create", entity: "ticket", payload: "{}",
                                  idempotencyKey: key)
        try await SyncQueueStore.shared.enqueue(r1)
        try await SyncQueueStore.shared.enqueue(r2)
        let count = try await SyncQueueStore.shared.pendingCount()
        XCTAssertEqual(count, 1, "Duplicate idempotency key must dedupe on second enqueue")
    }

    // MARK: - Lifecycle transitions

    func test_markSucceeded_deletesRow() async throws {
        let record = SyncQueueRecord(op: "update", entity: "inventory",
                                     entityServerId: "42",
                                     payload: "{}")
        try await SyncQueueStore.shared.enqueue(record)
        guard let id = try await SyncQueueStore.shared.due(limit: 1).first?.id else {
            XCTFail("due() returned nothing"); return
        }
        try await SyncQueueStore.shared.markSucceeded(id)

        let remaining = try await SyncQueueStore.shared.pendingCount()
        XCTAssertEqual(remaining, 0)
    }

    func test_markFailed_underMaxAttempts_pushesToNextRetry() async throws {
        try await SyncQueueStore.shared.enqueue(
            SyncQueueRecord(op: "create", entity: "customer", payload: "{}")
        )
        guard let id = try await SyncQueueStore.shared.due(limit: 1).first?.id else {
            XCTFail("no row"); return
        }
        try await SyncQueueStore.shared.markFailed(id, error: "transient")

        // Row should still exist with status 'failed' + a future next_retry_at.
        let due = try await SyncQueueStore.shared.due(limit: 10)
        // due() returns rows where next_retry_at <= now; first backoff is ~1s
        // so the freshly-failed row won't be due yet.
        XCTAssertTrue(due.isEmpty, "Just-failed row shouldn't be due within backoff window")
        let total = try await SyncQueueStore.shared.pendingCount()
        XCTAssertEqual(total, 1)
    }

    func test_markFailed_atMaxAttempts_movesToDeadLetter() async throws {
        try await SyncQueueStore.shared.enqueue(
            SyncQueueRecord(op: "create", entity: "customer", payload: #"{"name":"Doomed"}"#)
        )
        guard let id = try await SyncQueueStore.shared.due(limit: 1).first?.id else {
            XCTFail("no row"); return
        }

        // Burn through the 10-attempt budget.
        for _ in 0..<SyncQueueStore.maxAttempts {
            try await SyncQueueStore.shared.markFailed(id, error: "still broken")
        }

        // Queue row gone; dead-letter row exists.
        let pending = try await SyncQueueStore.shared.pendingCount()
        XCTAssertEqual(pending, 0)
        let dlqCount = try await SyncQueueStore.shared.deadLetterCount()
        XCTAssertEqual(dlqCount, 1)
    }

    // MARK: - Dead-letter triage

    func test_retryDeadLetter_reenqueuesWithFreshKey() async throws {
        // Seed a dead-letter row by force-failing past max attempts.
        try await SyncQueueStore.shared.enqueue(
            SyncQueueRecord(op: "update", entity: "ticket",
                            entityServerId: "7", payload: "{}",
                            idempotencyKey: "stale-key")
        )
        guard let id = try await SyncQueueStore.shared.due(limit: 1).first?.id else {
            XCTFail("no row"); return
        }
        for _ in 0..<SyncQueueStore.maxAttempts {
            try await SyncQueueStore.shared.markFailed(id, error: "e")
        }
        let dlq = try await SyncQueueStore.shared.deadLetter(limit: 10)
        XCTAssertEqual(dlq.count, 1)
        guard let dlqRow = dlq.first else { return }

        try await SyncQueueStore.shared.retryDeadLetter(dlqRow.id)

        // Dead-letter row is gone; a new queue row exists with a fresh key.
        let dlqAfter = try await SyncQueueStore.shared.deadLetterCount()
        XCTAssertEqual(dlqAfter, 0)
        let queued = try await SyncQueueStore.shared.due(limit: 10)
        XCTAssertEqual(queued.count, 1)
        XCTAssertNotEqual(queued.first?.idempotencyKey, "stale-key")
    }

    func test_discardDeadLetter_removesWithoutRequeue() async throws {
        try await SyncQueueStore.shared.enqueue(
            SyncQueueRecord(op: "delete", entity: "customer",
                            entityServerId: "9", payload: "{}")
        )
        guard let id = try await SyncQueueStore.shared.due(limit: 1).first?.id else {
            XCTFail("no row"); return
        }
        for _ in 0..<SyncQueueStore.maxAttempts {
            try await SyncQueueStore.shared.markFailed(id, error: "e")
        }
        let dlq = try await SyncQueueStore.shared.deadLetter(limit: 10)
        guard let dlqRow = dlq.first else { XCTFail("dead-letter empty"); return }

        try await SyncQueueStore.shared.discardDeadLetter(dlqRow.id)

        let dlqAfter = try await SyncQueueStore.shared.deadLetterCount()
        let pending = try await SyncQueueStore.shared.pendingCount()
        XCTAssertEqual(dlqAfter, 0)
        XCTAssertEqual(pending, 0)
    }
}
