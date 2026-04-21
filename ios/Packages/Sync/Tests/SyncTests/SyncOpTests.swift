import XCTest
@testable import Sync

/// Tests for `SyncOp` (the convenience type callers use to enqueue work).
final class SyncOpTests: XCTestCase {

    func test_init_fullForm_preservesAllFields() {
        let payload = Data("{}".utf8)
        let sut = SyncOp(
            op: "update",
            entity: "tickets",
            entityLocalId: "local-1",
            entityServerId: "server-42",
            payload: payload,
            idempotencyKey: "key-abc"
        )
        XCTAssertEqual(sut.op, "update")
        XCTAssertEqual(sut.entity, "tickets")
        XCTAssertEqual(sut.entityLocalId, "local-1")
        XCTAssertEqual(sut.entityServerId, "server-42")
        XCTAssertEqual(sut.payload, payload)
        XCTAssertEqual(sut.idempotencyKey, "key-abc")
        XCTAssertEqual(sut.kind, "tickets.update")
    }

    func test_init_legacyKind_parsesEntityAndOp() {
        let sut = SyncOp(kind: "customers.create", payload: Data())
        XCTAssertEqual(sut.entity, "customers")
        XCTAssertEqual(sut.op, "create")
        XCTAssertEqual(sut.kind, "customers.create")
    }

    func test_init_legacyKind_noDot_usesKindAsEntity() {
        let sut = SyncOp(kind: "flush", payload: Data())
        XCTAssertEqual(sut.entity, "flush")
        XCTAssertEqual(sut.op, "unknown")
    }

    func test_init_defaultIdempotencyKey_isNonEmpty() {
        let sut = SyncOp(op: "delete", entity: "inventory", payload: Data())
        XCTAssertFalse(sut.idempotencyKey.isEmpty)
    }

    func test_twoDefaultInits_haveDifferentIdempotencyKeys() {
        let a = SyncOp(op: "delete", entity: "inventory", payload: Data())
        let b = SyncOp(op: "delete", entity: "inventory", payload: Data())
        XCTAssertNotEqual(a.idempotencyKey, b.idempotencyKey)
    }
}
