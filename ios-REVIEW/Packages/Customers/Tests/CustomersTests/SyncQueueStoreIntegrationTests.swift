import XCTest
@testable import Customers
import Persistence

/// §20.2 — spot-check that enqueuing a SyncQueueRecord lands where the
/// drainer will pick it up.
///
/// TODO(phase-3): The full enqueue→`due(limit:)` round-trip needs a
/// migrated SQLite file at `applicationSupportDirectory/bizarrecrm.sqlite`.
/// The shared `Database.open()` writes to the user's Application Support
/// folder, which a `swift test` run does not clean up between invocations
/// — so running this test against the real shared database would pollute
/// dev state and race with concurrent test runs. Persistence's own test
/// target (`PersistenceTests`) covers the backoff/DLQ math. The piece we
/// actually care about here — constructing a well-formed record — is
/// exercised below.
final class SyncQueueStoreIntegrationTests: XCTestCase {

    func test_record_forCustomerCreate_hasExpectedShape() {
        let record = SyncQueueRecord(
            op: "create",
            entity: "customer",
            payload: "{}"
        )
        XCTAssertEqual(record.op, "create")
        XCTAssertEqual(record.entity, "customer")
        XCTAssertEqual(record.kind, "customer.create")
        XCTAssertEqual(record.status, SyncQueueRecord.Status.queued.rawValue)
        XCTAssertFalse(record.idempotencyKey?.isEmpty ?? true,
                       "idempotency key must default to a UUID so retries dedupe")
    }

    func test_record_forCustomerUpdate_carriesServerId() {
        let record = SyncQueueRecord(
            op: "update",
            entity: "customer",
            entityLocalId: nil,
            entityServerId: "42",
            payload: "{}"
        )
        XCTAssertEqual(record.op, "update")
        XCTAssertEqual(record.entity, "customer")
        XCTAssertEqual(record.entityServerId, "42")
        XCTAssertEqual(record.kind, "customer.update")
    }
}
