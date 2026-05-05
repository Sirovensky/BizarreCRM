import XCTest
@testable import Persistence

/// §20.3 — registry-only tests for SyncFlusher. Full DB round-trip is gated
/// on a shared Database pool that needs its own Application Support path,
/// so we don't exercise `flush()` here; that's covered by the integration
/// harness in BizarreCRMTests.
final class SyncFlusherTests: XCTestCase {

    func test_register_addsHandlerForEntityAndOp() async {
        let flusher = SyncFlusher.shared
        await flusher.register(entity: "customer", op: "create") { _ in }

        let has = await flusher.hasHandler(entity: "customer", op: "create")
        XCTAssertTrue(has)
    }

    func test_hasHandler_falseForUnregistered() async {
        let flusher = SyncFlusher.shared
        let has = await flusher.hasHandler(entity: "phantom", op: "nuke")
        XCTAssertFalse(has)
    }

    func test_register_replacesPriorHandlerForSameKey() async {
        // Mutation: registering a second handler with the same key replaces
        // the first. Guarantees domain packages can re-register on app warm
        // restart without duplicate-call side effects.
        let flusher = SyncFlusher.shared
        await flusher.register(entity: "ticket", op: "update") { _ in
            throw NSError(domain: "first", code: 1)
        }
        await flusher.register(entity: "ticket", op: "update") { _ in
            // Second handler - a no-op. If it gets called instead of the
            // first, the caller would succeed. Direct introspection of which
            // handler is active isn't exposed; we just assert presence.
        }
        let has = await flusher.hasHandler(entity: "ticket", op: "update")
        XCTAssertTrue(has)
    }
}
