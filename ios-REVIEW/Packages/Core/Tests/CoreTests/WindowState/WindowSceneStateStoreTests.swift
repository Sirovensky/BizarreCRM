import XCTest
@testable import Core

// MARK: - WindowSceneStateStoreTests

/// Tests for `WindowSceneStateStore`: save/load, key isolation between
/// sessions, removal helpers, and corrupt-data resilience.
@MainActor
final class WindowSceneStateStoreTests: XCTestCase {

    // MARK: - Fixtures

    /// An isolated `UserDefaults` suite so tests never touch `.standard`.
    private var defaults: UserDefaults!
    private var store: WindowSceneStateStore!

    private let sessionA = "session-aaaaaaaa-0000-0000-0000-000000000001"
    private let sessionB = "session-bbbbbbbb-0000-0000-0000-000000000002"

    override func setUp() {
        super.setUp()
        let suiteName = "com.bizarrecrm.tests.WindowSceneStateStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = WindowSceneStateStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        defaults = nil
        store = nil
        super.tearDown()
    }

    // =========================================================================
    // MARK: - 1. Save and load
    // =========================================================================

    func test_save_load_roundTrips() {
        let state = WindowSceneState(
            activeTab: .tickets,
            selectedTicketId: "T-1",
            selectedCustomerId: nil,
            searchQuery: "urgent"
        )
        store.save(state, for: sessionA)
        let loaded = store.load(for: sessionA)
        XCTAssertEqual(loaded, state)
    }

    func test_load_noEntry_returnsNil() {
        let result = store.load(for: "unknown-session-id")
        XCTAssertNil(result)
    }

    func test_save_overwrite_returnsLatestValue() {
        let first = WindowSceneState(activeTab: .dashboard)
        let second = WindowSceneState(activeTab: .settings, searchQuery: "tax")
        store.save(first, for: sessionA)
        store.save(second, for: sessionA)
        XCTAssertEqual(store.load(for: sessionA), second)
    }

    // =========================================================================
    // MARK: - 2. Key isolation between sessions
    // =========================================================================

    func test_keyIsolation_twoSessions_storeIndependently() {
        let stateA = WindowSceneState(activeTab: .tickets, selectedTicketId: "T-99")
        let stateB = WindowSceneState(activeTab: .customers, selectedCustomerId: "C-42")

        store.save(stateA, for: sessionA)
        store.save(stateB, for: sessionB)

        XCTAssertEqual(store.load(for: sessionA), stateA)
        XCTAssertEqual(store.load(for: sessionB), stateB)
    }

    func test_keyIsolation_removingSessionA_leavesSessionBIntact() {
        let stateA = WindowSceneState(activeTab: .pos)
        let stateB = WindowSceneState(activeTab: .reports)

        store.save(stateA, for: sessionA)
        store.save(stateB, for: sessionB)

        store.remove(for: sessionA)

        XCTAssertNil(store.load(for: sessionA))
        XCTAssertEqual(store.load(for: sessionB), stateB)
    }

    func test_keyIsolation_thirdSession_notAffectedByFirstTwo() {
        let sessionC = "session-cccccccc-0000-0000-0000-000000000003"
        let stateA = WindowSceneState(activeTab: .tickets)
        let stateC = WindowSceneState(activeTab: .settings)

        store.save(stateA, for: sessionA)
        store.save(stateC, for: sessionC)

        XCTAssertNil(store.load(for: sessionB), "Session B was never written")
        XCTAssertEqual(store.load(for: sessionC), stateC)
    }

    // =========================================================================
    // MARK: - 3. Removal helpers
    // =========================================================================

    func test_remove_existingEntry_makesLoadReturnNil() {
        store.save(WindowSceneState(activeTab: .tickets), for: sessionA)
        store.remove(for: sessionA)
        XCTAssertNil(store.load(for: sessionA))
    }

    func test_remove_nonExistentEntry_isNoOp() {
        // Should not throw or crash.
        store.remove(for: "nonexistent-session")
    }

    func test_removeAll_clearsAllManagedKeys() {
        store.save(WindowSceneState(activeTab: .dashboard), for: sessionA)
        store.save(WindowSceneState(activeTab: .pos), for: sessionB)

        store.removeAll()

        XCTAssertNil(store.load(for: sessionA))
        XCTAssertNil(store.load(for: sessionB))
    }

    func test_removeAll_doesNotRemoveUnrelatedKeys() {
        let unrelatedKey = "com.bizarrecrm.other"
        defaults.set("preserved", forKey: unrelatedKey)

        store.save(WindowSceneState(activeTab: .tickets), for: sessionA)
        store.removeAll()

        XCTAssertEqual(defaults.string(forKey: unrelatedKey), "preserved")
    }

    // =========================================================================
    // MARK: - 4. Key prefix
    // =========================================================================

    func test_keyPrefix_savedValueUsesExpectedKey() {
        store.save(WindowSceneState(activeTab: .reports), for: sessionA)
        let expectedKey = "\(WindowSceneStateStore.keyPrefix)\(sessionA)"
        XCTAssertNotNil(defaults.data(forKey: expectedKey),
                        "Value should be stored under the prefixed key")
    }

    // =========================================================================
    // MARK: - 5. Resilience
    // =========================================================================

    func test_load_corruptData_returnsNil() {
        let corruptKey = "\(WindowSceneStateStore.keyPrefix)\(sessionA)"
        defaults.set(Data([0xFF, 0xFE, 0x00]), forKey: corruptKey)
        XCTAssertNil(store.load(for: sessionA))
    }
}
