import XCTest
@testable import Core
import Factory

// MARK: - Sendable sentinel for DI tests

/// `NSObject` is not `Sendable`; wrap it in an `@unchecked` box.
private final class SentinelObject: @unchecked Sendable {}

// MARK: - ContainerRegistrationsTests
//
// Smoke-tests for Container+Registrations (§1 DI architecture).
// These tests verify:
//   - `registerAllServices()` completes without crashing.
//   - The Container can have concrete registrations applied.
//   - Factory key paths are accessible.

final class ContainerRegistrationsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset shared container between tests to avoid test pollution.
        Container.shared.reset()
    }

    // MARK: - registerAllServices

    func testRegisterAllServicesSmokeTest() {
        // Should not crash or throw.
        XCTAssertNoThrow(Container.registerAllServices())
    }

    func testRegisterAllServicesCalledTwiceIsIdempotent() {
        // Double call is safe — log line runs twice but no crash.
        XCTAssertNoThrow(Container.registerAllServices())
        XCTAssertNoThrow(Container.registerAllServices())
    }

    // MARK: - Custom registrations

    func testCanRegisterAndResolveCustomFactory() {
        let sentinel = SentinelObject()
        Container.shared.apiClient.register { sentinel }
        let resolved = Container.shared.apiClient()
        XCTAssertIdentical(resolved as AnyObject, sentinel)
    }

    func testCanRegisterTokenStore() {
        let sentinel = SentinelObject()
        Container.shared.tokenStore.register { sentinel }
        XCTAssertIdentical(Container.shared.tokenStore() as AnyObject, sentinel)
    }

    func testCanRegisterPinStore() {
        let sentinel = SentinelObject()
        Container.shared.pinStore.register { sentinel }
        XCTAssertIdentical(Container.shared.pinStore() as AnyObject, sentinel)
    }

    func testCanRegisterSyncQueueStore() {
        let sentinel = SentinelObject()
        Container.shared.syncQueueStore.register { sentinel }
        XCTAssertIdentical(Container.shared.syncQueueStore() as AnyObject, sentinel)
    }

    func testCanRegisterSyncStateStore() {
        let sentinel = SentinelObject()
        Container.shared.syncStateStore.register { sentinel }
        XCTAssertIdentical(Container.shared.syncStateStore() as AnyObject, sentinel)
    }

    func testCanRegisterSyncManager() {
        let sentinel = SentinelObject()
        Container.shared.syncManager.register { sentinel }
        XCTAssertIdentical(Container.shared.syncManager() as AnyObject, sentinel)
    }

    // MARK: - Unregistered factories throw fatalError (guarded test)

    // Note: We do NOT call an unregistered factory here because it would
    // fatalError the test process. The production behaviour is intentional:
    // an unregistered service is a programming error, not a recoverable condition.
    // The CI build gate catches this via integration tests in the host app.
}
