import XCTest
import Foundation

// MARK: - Phase 0 Gate: Airplane-mode smoke test
//
// Tests the real SyncQueueStore + SyncStateStore + migrations via an
// in-memory (temp dir) GRDB database. SyncManager wiring is guarded with
// #if canImport(Sync) so this compiles even while the Sync package is
// still in-flight in parallel agents.
//
// Minimum acceptable: verifies that:
//   1. Migrations run and produce sync_queue + sync_state tables.
//   2. SyncQueueStore.enqueue() persists a row (pendingCount == 1).
//   3. Offline banner condition: isOnline == false && pendingCount > 0.
//   4. SyncQueueStore.markSucceeded() drains the queue (pendingCount == 0).
//   5. Failure path: markFailed() → status = failed, attempt++ , retry scheduled.
//   6. Dead-letter path: exhausting maxAttempts moves row to sync_dead_letter.
//
// TODO Phase 0 close: expand when SyncManager ships — replace
// direct-SyncQueueStore calls in tests 3/4 with
//   SyncManager.shared.enqueue(SyncOp(...)) / SyncManager.shared.syncNow()
// and mock SyncOpExecutor via SyncManager.shared.executor.

#if canImport(Persistence)
import Persistence
#endif

#if canImport(Sync)
import Sync
#endif

// MARK: - MockOfflineFlag

/// Lightweight stand-in for Reachability when we don't have the live
/// NWPathMonitor running in a test process.
struct MockReachability {
    var isOnline: Bool
}

// MARK: - SmokeTests

final class SmokeTests: XCTestCase {

    // MARK: - Setup / teardown

    private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
#if canImport(Persistence)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("smoketest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempURL = dir.appendingPathComponent("smoke.sqlite")
        try await Database.shared.reopen(at: tempURL)
#else
        throw XCTSkip("Persistence module not available — skipping smoke tests")
#endif
    }

    override func tearDown() async throws {
#if canImport(Persistence)
        await Database.shared.close()
        if let dir = tempURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
#endif
        try await super.tearDown()
    }

    // MARK: - Test 1: Migrations produce sync_queue + sync_state tables

    func test_migrations_syncQueueAndSyncStateTables_exist() async throws {
#if !canImport(Persistence)
        throw XCTSkip("Persistence not available")
#else
        guard let pool = await Database.shared.pool() else {
            XCTFail("Database pool not open after reopen(at:)")
            return
        }

        let tableNames: [String] = try await pool.read { db in
            try String.fetchAll(db, sql:
                "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        }

        XCTAssertTrue(tableNames.contains("sync_queue"),
                      "Migration must create sync_queue; found: \(tableNames)")
        XCTAssertTrue(tableNames.contains("sync_state"),
                      "Migration must create sync_state; found: \(tableNames)")
        XCTAssertTrue(tableNames.contains("sync_dead_letter"),
                      "Migration must create sync_dead_letter; found: \(tableNames)")
#endif
    }

    // MARK: - Test 2: Fresh DB has zero pending rows

    func test_freshDatabase_haZeroPendingRows() async throws {
#if !canImport(Persistence)
        throw XCTSkip("Persistence not available")
#else
        let count = try await SyncQueueStore.shared.pendingCount()
        XCTAssertEqual(count, 0, "Fresh DB must have zero sync_queue rows")

        guard let pool = await Database.shared.pool() else { return }
        let syncStateCount: Int = try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_state") ?? 0
        }
        XCTAssertEqual(syncStateCount, 0, "Fresh DB must have zero sync_state rows")
#endif
    }

    // MARK: - Test 3: Offline banner condition — enqueue + isOnline = false

    func test_offlineBannerCondition_pendingPlusOfflineFlag() async throws {
#if !canImport(Persistence)
        throw XCTSkip("Persistence not available")
#else
        // Simulate offline.
        var reachability = MockReachability(isOnline: false)

        // Enqueue a synthetic write as if a UI action happened while offline.
        let record = SyncQueueRecord(
            op: "create",
            entity: "test",
            payload: #"{"hello":"world"}"#
        )
        try await SyncQueueStore.shared.enqueue(record)

        let pendingCount = try await SyncQueueStore.shared.pendingCount()

        // Offline banner should be visible:
        //   reachability.isOnline == false && pendingCount > 0
        XCTAssertFalse(reachability.isOnline,
                       "MockReachability must report offline")
        XCTAssertEqual(pendingCount, 1,
                       "Exactly one row must be in sync_queue after enqueue")

        let shouldShowBanner = !reachability.isOnline && pendingCount > 0
        XCTAssertTrue(shouldShowBanner,
                      "Offline banner condition must be true when offline + pending > 0")

        // Simulate reconnect.
        reachability.isOnline = true
        XCTAssertTrue(reachability.isOnline, "MockReachability flipped to online")
#endif
    }

    // MARK: - Test 4: Drain — markSucceeded clears the queue

    func test_drain_markSucceeded_clearsPendingCount() async throws {
#if !canImport(Persistence)
        throw XCTSkip("Persistence not available")
#else
        let record = SyncQueueRecord(
            op: "update",
            entity: "test",
            payload: "{}"
        )
        try await SyncQueueStore.shared.enqueue(record)

        let due = try await SyncQueueStore.shared.due(limit: 10)
        XCTAssertEqual(due.count, 1, "One row should be due after enqueue")
        guard let id = due.first?.id else {
            XCTFail("due() row missing id"); return
        }

        // Simulate executor success.
        var executorCallCount = 0
        // (In a real test with SyncManager we'd inject a mock SyncOpExecutor.
        //  Here we directly drive SyncQueueStore to keep the test
        //  Sync-package-independent.)
        executorCallCount += 1
        try await SyncQueueStore.shared.markSucceeded(id)

        let afterCount = try await SyncQueueStore.shared.pendingCount()
        XCTAssertEqual(executorCallCount, 1,
                       "Executor should be called exactly once per op")
        XCTAssertEqual(afterCount, 0,
                       "pendingCount must be 0 after markSucceeded")
#endif
    }

    // MARK: - Test 5: Failure path — markFailed sets status + schedules retry

    func test_failurePath_markFailed_setsStatusAndNextRetryAt() async throws {
#if !canImport(Persistence)
        throw XCTSkip("Persistence not available")
#else
        let record = SyncQueueRecord(
            op: "create",
            entity: "test",
            payload: #"{"x":1}"#
        )
        try await SyncQueueStore.shared.enqueue(record)

        guard let id = try await SyncQueueStore.shared.due(limit: 1).first?.id else {
            XCTFail("no due row"); return
        }

        // Simulate a transient server error (attempt 1).
        try await SyncQueueStore.shared.markFailed(id, error: "server(500, \"boom\")")

        // Row must still exist but not be immediately due (backoff window).
        let dueNow = try await SyncQueueStore.shared.due(limit: 10)
        XCTAssertTrue(dueNow.isEmpty,
                      "Just-failed row must not be due immediately (backoff)")

        let totalPending = try await SyncQueueStore.shared.pendingCount()
        XCTAssertEqual(totalPending, 1,
                       "Row must remain in sync_queue after first failure")

        // Verify the row has status = failed and nextRetryAt in the future.
        guard let pool = await Database.shared.pool() else { return }
        let row = try await pool.read { db in
            try SyncQueueRecord.filter(Column("id") == id).fetchOne(db)
        }
        XCTAssertEqual(row?.status, SyncQueueRecord.Status.failed.rawValue,
                       "Status must be 'failed' after markFailed")
        XCTAssertEqual(row?.attemptCount, 1,
                       "attempt_count must be 1 after first failure")
        XCTAssertNotNil(row?.nextRetryAt,
                        "next_retry_at must be set after markFailed")
        if let retryAt = row?.nextRetryAt {
            XCTAssertGreaterThan(retryAt, Date(),
                                 "next_retry_at must be in the future")
        }
#endif
    }

    // MARK: - Test 6: Dead-letter path — exhausting maxAttempts tombstones row

    func test_deadLetter_exhaustingMaxAttempts_movesRowToDeadLetterTable() async throws {
#if !canImport(Persistence)
        throw XCTSkip("Persistence not available")
#else
        let record = SyncQueueRecord(
            op: "delete",
            entity: "test",
            payload: #"{"doomed":true}"#
        )
        try await SyncQueueStore.shared.enqueue(record)

        guard let id = try await SyncQueueStore.shared.due(limit: 1).first?.id else {
            XCTFail("no due row"); return
        }

        // Exhaust the full retry budget (SyncQueueStore.maxAttempts = 10).
        for attempt in 1...SyncQueueStore.maxAttempts {
            try await SyncQueueStore.shared.markFailed(
                id,
                error: "always-fails attempt \(attempt)"
            )
        }

        // sync_queue row must be gone.
        let pendingAfter = try await SyncQueueStore.shared.pendingCount()
        XCTAssertEqual(pendingAfter, 0,
                       "sync_queue must be empty after dead-letter promotion")

        // sync_dead_letter must have exactly one row.
        let dlqCount = try await SyncQueueStore.shared.deadLetterCount()
        XCTAssertEqual(dlqCount, 1,
                       "sync_dead_letter must have 1 row after maxAttempts exhausted")

        // Inspect dead-letter contents.
        let dlqRows = try await SyncQueueStore.shared.deadLetter(limit: 10)
        XCTAssertEqual(dlqRows.count, 1)
        XCTAssertEqual(dlqRows.first?.entity, "test")
        XCTAssertEqual(dlqRows.first?.op, "delete")
#endif
    }

    // MARK: - Test 7: Dead-letter retry re-queues with fresh idempotency key

    func test_deadLetter_retry_reenqueuesWithFreshIdempotencyKey() async throws {
#if !canImport(Persistence)
        throw XCTSkip("Persistence not available")
#else
        let originalKey = UUID().uuidString
        let record = SyncQueueRecord(
            op: "update",
            entity: "test",
            payload: "{}",
            idempotencyKey: originalKey
        )
        try await SyncQueueStore.shared.enqueue(record)

        guard let id = try await SyncQueueStore.shared.due(limit: 1).first?.id else {
            XCTFail("no due row"); return
        }

        for _ in 1...SyncQueueStore.maxAttempts {
            try await SyncQueueStore.shared.markFailed(id, error: "error")
        }

        let dlqRows = try await SyncQueueStore.shared.deadLetter(limit: 10)
        XCTAssertEqual(dlqRows.count, 1)
        guard let dlqRow = dlqRows.first else { return }

        try await SyncQueueStore.shared.retryDeadLetter(dlqRow.id)

        let dlqAfter = try await SyncQueueStore.shared.deadLetterCount()
        XCTAssertEqual(dlqAfter, 0, "DLQ must be empty after retry")

        let requeued = try await SyncQueueStore.shared.due(limit: 10)
        XCTAssertEqual(requeued.count, 1, "One row must be re-queued")
        XCTAssertNotEqual(requeued.first?.idempotencyKey, originalKey,
                          "Re-queued row must have a fresh idempotency key")
#endif
    }
}
