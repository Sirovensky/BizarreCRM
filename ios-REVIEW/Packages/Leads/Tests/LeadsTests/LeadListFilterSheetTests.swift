import XCTest
@testable import Leads

// MARK: - §9.1 Lead filter + sort tests

final class LeadListFilterSheetTests: XCTestCase {

    // MARK: LeadSortOrder

    func test_sortOrder_allCases_count() {
        // 8 sort orders defined
        XCTAssertEqual(LeadSortOrder.allCases.count, 8)
    }

    func test_sortOrder_name_rawValue() {
        XCTAssertEqual(LeadSortOrder.name.rawValue, "Name A–Z")
    }

    func test_sortOrder_nameDesc_rawValue() {
        XCTAssertEqual(LeadSortOrder.nameDesc.rawValue, "Name Z–A")
    }

    func test_sortOrder_createdDesc_rawValue() {
        XCTAssertEqual(LeadSortOrder.createdDesc.rawValue, "Newest")
    }

    func test_sortOrder_createdAsc_rawValue() {
        XCTAssertEqual(LeadSortOrder.createdAsc.rawValue, "Oldest")
    }

    func test_sortOrder_leadScoreDesc_rawValue() {
        XCTAssertEqual(LeadSortOrder.leadScoreDesc.rawValue, "Score ↓")
    }

    func test_sortOrder_leadScoreAsc_rawValue() {
        XCTAssertEqual(LeadSortOrder.leadScoreAsc.rawValue, "Score ↑")
    }

    func test_sortOrder_lastActivity_rawValue() {
        XCTAssertEqual(LeadSortOrder.lastActivity.rawValue, "Last activity")
    }

    func test_sortOrder_nextAction_rawValue() {
        XCTAssertEqual(LeadSortOrder.nextAction.rawValue, "Next action")
    }

    func test_sortOrder_isSendable() {
        // Compile-time guarantee via Sendable conformance
        let _: any Sendable = LeadSortOrder.name
    }

    func test_sortOrder_isCaseIterable() {
        // All cases reachable via allCases
        let all = LeadSortOrder.allCases
        XCTAssertTrue(all.contains(.name))
        XCTAssertTrue(all.contains(.leadScoreDesc))
        XCTAssertTrue(all.contains(.nextAction))
    }
}
