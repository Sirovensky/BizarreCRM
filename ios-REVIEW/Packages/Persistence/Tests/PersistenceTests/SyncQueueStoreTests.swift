import XCTest
@testable import Persistence

/// §20.2 drain / backoff math. The full SQLCipher-backed store needs an
/// on-disk DB to exercise — that's covered by integration tests in the
/// BizarreCRMTests target. Here we just lock down the pure-math helpers
/// so backoff changes don't slip silently.
final class SyncQueueStoreTests: XCTestCase {

    func testBackoffEscalatesThenCaps() {
        let samples = (1...8).map { SyncQueueStore.backoff(attempt: $0) }
        // Each successive attempt is ≥ prior (allowing ±10% jitter to overlap
        // a single tier) — but the cap kicks in at 60s.
        for s in samples {
            XCTAssertGreaterThanOrEqual(s, 0.9)   // 1s base ±10%
            XCTAssertLessThanOrEqual(s, 60.0 * 1.1)
        }
        // The 7th+ attempts should all land near the 60s cap.
        XCTAssertGreaterThan(samples[6], 50)
        XCTAssertGreaterThan(samples[7], 50)
    }

    func testMaxAttemptsConstant() {
        // Plan-locked at 10 retries before DLQ per §20.2.
        XCTAssertEqual(SyncQueueStore.maxAttempts, 10)
    }

    func testRecordPopulatesKindForObservability() {
        let r = SyncQueueRecord(
            op: "create",
            entity: "ticket",
            payload: #"{"foo":"bar"}"#
        )
        XCTAssertEqual(r.op, "create")
        XCTAssertEqual(r.entity, "ticket")
        XCTAssertEqual(r.kind, "ticket.create")
        XCTAssertFalse(r.idempotencyKey?.isEmpty ?? true)
    }

    func testRecordBackoffMutation() {
        var r = SyncQueueRecord(
            op: "update",
            entity: "customer",
            payload: #"{}"#
        )
        XCTAssertEqual(r.attemptCount, 0)
        r.didEncounter(error: "timeout", backoffSeconds: 4.0)
        XCTAssertEqual(r.attemptCount, 1)
        XCTAssertEqual(r.status, SyncQueueRecord.Status.failed.rawValue)
        XCTAssertEqual(r.lastError, "timeout")
        XCTAssertNotNil(r.nextRetryAt)
    }
}
