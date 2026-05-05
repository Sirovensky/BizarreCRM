import XCTest
@testable import Core

// MARK: - WindowSceneStateTests

/// Tests for `WindowSceneState` encode/decode round-trips,
/// immutable update helpers, and default-value behaviour.
final class WindowSceneStateTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // =========================================================================
    // MARK: - 1. Encode / decode round-trips
    // =========================================================================

    func test_encodeDecode_allFields_roundTrips() throws {
        let original = WindowSceneState(
            activeTab: .tickets,
            selectedTicketId: "T-42",
            selectedCustomerId: "C-7",
            searchQuery: "widget"
        )
        let data = try encoder.encode(original)
        let restored = try decoder.decode(WindowSceneState.self, from: data)
        XCTAssertEqual(original, restored)
    }

    func test_encodeDecode_nilOptionals_roundTrips() throws {
        let original = WindowSceneState(activeTab: .dashboard)
        let data = try encoder.encode(original)
        let restored = try decoder.decode(WindowSceneState.self, from: data)
        XCTAssertEqual(original, restored)
        XCTAssertNil(restored.selectedTicketId)
        XCTAssertNil(restored.selectedCustomerId)
        XCTAssertNil(restored.searchQuery)
    }

    func test_encodeDecode_activeTab_customers_roundTrips() throws {
        let original = WindowSceneState(activeTab: .customers, selectedCustomerId: "C-99")
        let data = try encoder.encode(original)
        let restored = try decoder.decode(WindowSceneState.self, from: data)
        XCTAssertEqual(restored.activeTab, .customers)
        XCTAssertEqual(restored.selectedCustomerId, "C-99")
    }

    func test_encodeDecode_allActiveTabs_roundTrip() throws {
        for tab in ActiveTab.allCases {
            let state = WindowSceneState(activeTab: tab)
            let data = try encoder.encode(state)
            let restored = try decoder.decode(WindowSceneState.self, from: data)
            XCTAssertEqual(restored.activeTab, tab, "Round-trip failed for tab \(tab)")
        }
    }

    func test_encodeDecode_emptySearchQuery_roundTrips() throws {
        let original = WindowSceneState(activeTab: .tickets, searchQuery: "")
        let data = try encoder.encode(original)
        let restored = try decoder.decode(WindowSceneState.self, from: data)
        XCTAssertEqual(restored.searchQuery, "")
    }

    // =========================================================================
    // MARK: - 2. Default values
    // =========================================================================

    func test_defaultInit_activeTab_isDashboard() {
        let state = WindowSceneState()
        XCTAssertEqual(state.activeTab, .dashboard)
    }

    func test_defaultInit_optionals_areNil() {
        let state = WindowSceneState()
        XCTAssertNil(state.selectedTicketId)
        XCTAssertNil(state.selectedCustomerId)
        XCTAssertNil(state.searchQuery)
    }

    // =========================================================================
    // MARK: - 3. Immutable updaters
    // =========================================================================

    func test_withActiveTab_returnsNewInstance() {
        let original = WindowSceneState(activeTab: .dashboard)
        let updated = original.withActiveTab(.reports)
        XCTAssertEqual(updated.activeTab, .reports)
        XCTAssertEqual(original.activeTab, .dashboard, "Original must not be mutated")
    }

    func test_withSelectedTicketId_preservesOtherFields() {
        let original = WindowSceneState(
            activeTab: .tickets,
            selectedCustomerId: "C-1",
            searchQuery: "query"
        )
        let updated = original.withSelectedTicketId("T-5")
        XCTAssertEqual(updated.selectedTicketId, "T-5")
        XCTAssertEqual(updated.activeTab, .tickets)
        XCTAssertEqual(updated.selectedCustomerId, "C-1")
        XCTAssertEqual(updated.searchQuery, "query")
    }

    func test_withSelectedCustomerId_preservesOtherFields() {
        let original = WindowSceneState(activeTab: .customers, selectedTicketId: "T-1")
        let updated = original.withSelectedCustomerId("C-99")
        XCTAssertEqual(updated.selectedCustomerId, "C-99")
        XCTAssertEqual(updated.selectedTicketId, "T-1")
        XCTAssertEqual(updated.activeTab, .customers)
    }

    func test_withSearchQuery_preservesOtherFields() {
        let original = WindowSceneState(activeTab: .tickets, selectedTicketId: "T-1")
        let updated = original.withSearchQuery("crm")
        XCTAssertEqual(updated.searchQuery, "crm")
        XCTAssertEqual(updated.selectedTicketId, "T-1")
        XCTAssertEqual(updated.activeTab, .tickets)
    }

    func test_withSearchQuery_nil_clearsQuery() {
        let original = WindowSceneState(activeTab: .tickets, searchQuery: "old")
        let updated = original.withSearchQuery(nil)
        XCTAssertNil(updated.searchQuery)
    }

    // =========================================================================
    // MARK: - 4. Equatable
    // =========================================================================

    func test_equatable_identicalStates_areEqual() {
        let a = WindowSceneState(activeTab: .pos, selectedTicketId: "T-1")
        let b = WindowSceneState(activeTab: .pos, selectedTicketId: "T-1")
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentTab_notEqual() {
        let a = WindowSceneState(activeTab: .dashboard)
        let b = WindowSceneState(activeTab: .settings)
        XCTAssertNotEqual(a, b)
    }

    func test_equatable_differentTicketId_notEqual() {
        let a = WindowSceneState(activeTab: .tickets, selectedTicketId: "T-1")
        let b = WindowSceneState(activeTab: .tickets, selectedTicketId: "T-2")
        XCTAssertNotEqual(a, b)
    }
}
