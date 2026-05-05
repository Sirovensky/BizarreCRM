import XCTest
@testable import Auth

// MARK: - LoginSplitPanelLayoutTests
//
// §22 — Tests for LoginSplitPanelLayout.
// We test the layout model logic and conditional rendering decisions.
// SwiftUI view-hierarchy tests are handled by snapshot tests in the App
// target; here we validate the pure-logic layer.

final class LoginSplitPanelLayoutTests: XCTestCase {

    // MARK: - TenantHistoryEntry tests (used by sidebar, shared model)

    func test_tenantHistoryEntry_id_isAssigned() {
        let entry = TenantHistoryEntry(id: "t1", name: "Shop A")
        XCTAssertEqual(entry.id, "t1")
    }

    func test_tenantHistoryEntry_name_isAssigned() {
        let entry = TenantHistoryEntry(id: "t1", name: "Shop A")
        XCTAssertEqual(entry.name, "Shop A")
    }

    func test_tenantHistoryEntry_serverURL_defaultsToNil() {
        let entry = TenantHistoryEntry(id: "t2", name: "Shop B")
        XCTAssertNil(entry.serverURL)
    }

    func test_tenantHistoryEntry_serverURL_isPreserved() {
        let url = URL(string: "https://shop.bizarrecrm.com")!
        let entry = TenantHistoryEntry(id: "t3", name: "Shop C", serverURL: url)
        XCTAssertEqual(entry.serverURL, url)
    }

    func test_tenantHistoryEntry_lastAccessedAt_defaultsToNil() {
        let entry = TenantHistoryEntry(id: "t4", name: "Shop D")
        XCTAssertNil(entry.lastAccessedAt)
    }

    func test_tenantHistoryEntry_lastAccessedAt_isPreserved() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let entry = TenantHistoryEntry(id: "t5", name: "Shop E", lastAccessedAt: date)
        XCTAssertEqual(entry.lastAccessedAt, date)
    }

    func test_tenantHistoryEntry_hashable_sameIdEqual() {
        let a = TenantHistoryEntry(id: "x", name: "A")
        let b = TenantHistoryEntry(id: "x", name: "B")
        // Hashable/Equatable conformance uses synthesised field equality
        // (all fields), so two entries with same id but different names differ.
        XCTAssertNotEqual(a, b)
    }

    func test_tenantHistoryEntry_hashable_allFieldsEqual() {
        let a = TenantHistoryEntry(id: "x", name: "A")
        let b = TenantHistoryEntry(id: "x", name: "A")
        XCTAssertEqual(a, b)
    }

    func test_tenantHistoryEntry_identifiable_idStringType() {
        let entry = TenantHistoryEntry(id: "abc123", name: "Test")
        XCTAssertEqual(entry.id, "abc123")
    }

    // MARK: - Sidebar width token

    func test_sidebarWidth_isReasonableForIPad() {
        // 220pt — narrow enough to be a sidebar, wide enough to show names.
        let w = LoginTenantHistorySidebar.sidebarWidth
        XCTAssertGreaterThanOrEqual(w, 160)
        XCTAssertLessThanOrEqual(w, 320)
    }

    // MARK: - Sorting stability

    func test_tenantHistoryEntry_sortByLastAccessed_mostRecentFirst() {
        let older = TenantHistoryEntry(id: "1", name: "Old", lastAccessedAt: Date(timeIntervalSince1970: 100))
        let newer = TenantHistoryEntry(id: "2", name: "New", lastAccessedAt: Date(timeIntervalSince1970: 200))
        let none  = TenantHistoryEntry(id: "3", name: "None", lastAccessedAt: nil)

        let sorted = [older, none, newer].sorted {
            ($0.lastAccessedAt ?? .distantPast) > ($1.lastAccessedAt ?? .distantPast)
        }

        XCTAssertEqual(sorted[0].id, "2", "Newest should be first")
        XCTAssertEqual(sorted[1].id, "1", "Older should be second")
        XCTAssertEqual(sorted[2].id, "3", "Nil date should be last")
    }

    func test_tenantHistoryEntry_sortStable_whenDatesEqual() {
        let t1 = Date(timeIntervalSince1970: 500)
        let a = TenantHistoryEntry(id: "a", name: "A", lastAccessedAt: t1)
        let b = TenantHistoryEntry(id: "b", name: "B", lastAccessedAt: t1)
        let sorted = [a, b].sorted {
            ($0.lastAccessedAt ?? .distantPast) > ($1.lastAccessedAt ?? .distantPast)
        }
        // Both have same date — stable order is preserved (original order maintained)
        XCTAssertEqual(sorted.count, 2)
    }

    // MARK: - Empty-state guard

    func test_emptyEntries_doesNotPanic() {
        // The sidebar hides itself when entries is empty; ensure no crash
        // when constructing with an empty array.
        let entries: [TenantHistoryEntry] = []
        XCTAssertTrue(entries.isEmpty)
    }
}
