import XCTest
import Combine
@testable import Core

// §79 Multi-Tenant Session management — guard tests

@MainActor
final class TenantSessionGuardTests: XCTestCase {

    // MARK: — Fixtures

    private var store: TenantSessionStore!
    private var switcher: TenantSwitcher!

    override func setUp() async throws {
        try await super.setUp()
        store = TenantSessionStore(keychain: InMemoryKeychainStore())
        switcher = TenantSwitcher(store: store, notificationCenter: NotificationCenter())
    }

    private func descriptor(id: String) -> TenantSessionDescriptor {
        TenantSessionDescriptor(
            id: id,
            displayName: "Tenant \(id)",
            baseURL: URL(string: "https://\(id).example.com")!
        )
    }

    // MARK: — No active tenant (nil → nil)

    func test_assertUnchanged_passes_whenNoTenantActiveAndNoneSet() throws {
        var guard_ = TenantOperationGuard(switcher: switcher)
        guard_.snapshot()
        XCTAssertNoThrow(try guard_.assertTenantUnchanged())
    }

    // MARK: — Tenant unchanged

    func test_assertUnchanged_passes_whenSameTenantActive() async throws {
        try await switcher.switchTo(descriptor(id: "acme"))

        var guard_ = TenantOperationGuard(switcher: switcher)
        guard_.snapshot()

        XCTAssertNoThrow(try guard_.assertTenantUnchanged())
    }

    // MARK: — Tenant changed mid-flight

    func test_assertUnchanged_throws_whenTenantSwitchedAfterSnapshot() async throws {
        try await switcher.switchTo(descriptor(id: "first"))

        var guard_ = TenantOperationGuard(switcher: switcher)
        guard_.snapshot()

        // Simulate tenant change while the "operation" is running.
        try await switcher.switchTo(descriptor(id: "second"))

        XCTAssertThrowsError(try guard_.assertTenantUnchanged()) { error in
            guard case let TenantSessionGuardError.tenantChanged(snapshotID, currentID) = error else {
                XCTFail("Expected .tenantChanged, got \(error)")
                return
            }
            XCTAssertEqual(snapshotID, "first")
            XCTAssertEqual(currentID, "second")
        }
    }

    func test_assertUnchanged_throws_whenTenantClearedAfterSnapshot() async throws {
        try await switcher.switchTo(descriptor(id: "acme"))

        var guard_ = TenantOperationGuard(switcher: switcher)
        guard_.snapshot()

        // Clear the session (e.g. screen lock / sign-out).
        switcher.clearActive()

        XCTAssertThrowsError(try guard_.assertTenantUnchanged()) { error in
            guard case let TenantSessionGuardError.tenantChanged(snapshotID, currentID) = error else {
                XCTFail("Expected .tenantChanged, got \(error)")
                return
            }
            XCTAssertEqual(snapshotID, "acme")
            XCTAssertNil(currentID, "active tenant must be nil after clearActive")
        }
    }

    func test_assertUnchanged_throws_whenTenantSetAfterNilSnapshot() async throws {
        // No active tenant at snapshot time.
        var guard_ = TenantOperationGuard(switcher: switcher)
        guard_.snapshot()

        // Tenant becomes active mid-flight.
        try await switcher.switchTo(descriptor(id: "new"))

        XCTAssertThrowsError(try guard_.assertTenantUnchanged()) { error in
            guard case let TenantSessionGuardError.tenantChanged(snapshotID, currentID) = error else {
                XCTFail("Expected .tenantChanged, got \(error)")
                return
            }
            XCTAssertNil(snapshotID)
            XCTAssertEqual(currentID, "new")
        }
    }

    // MARK: — Multiple snapshots (re-snapshot resets baseline)

    func test_assertUnchanged_passes_afterReSnapshot() async throws {
        try await switcher.switchTo(descriptor(id: "first"))

        var guard_ = TenantOperationGuard(switcher: switcher)
        guard_.snapshot()

        // Switch happens.
        try await switcher.switchTo(descriptor(id: "second"))

        // Re-snapshot to align the guard to the new tenant.
        guard_.snapshot()

        XCTAssertNoThrow(try guard_.assertTenantUnchanged())
    }

    // MARK: — Error equality

    func test_guardError_equality() {
        let e1 = TenantSessionGuardError.tenantChanged(snapshotID: "a", currentID: "b")
        let e2 = TenantSessionGuardError.tenantChanged(snapshotID: "a", currentID: "b")
        let e3 = TenantSessionGuardError.tenantChanged(snapshotID: "a", currentID: "c")

        XCTAssertEqual(e1, e2)
        XCTAssertNotEqual(e1, e3)
    }
}
