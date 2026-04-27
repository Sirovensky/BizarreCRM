import XCTest
@testable import Leads

// MARK: - §9.1 Lead stage navigation helper tests

final class LeadStageNavigationTests: XCTestCase {

    // MARK: - nextStage

    func test_nextStage_new_isContacted() {
        XCTAssertEqual(LeadListViewModel.nextStage(after: "new"), "contacted")
    }

    func test_nextStage_contacted_isScheduled() {
        XCTAssertEqual(LeadListViewModel.nextStage(after: "contacted"), "scheduled")
    }

    func test_nextStage_scheduled_isQualified() {
        XCTAssertEqual(LeadListViewModel.nextStage(after: "scheduled"), "qualified")
    }

    func test_nextStage_qualified_isProposal() {
        XCTAssertEqual(LeadListViewModel.nextStage(after: "qualified"), "proposal")
    }

    func test_nextStage_proposal_isNil_terminalGate() {
        // Terminal states (converted/won/lost) require explicit action — not auto-advance
        XCTAssertNil(LeadListViewModel.nextStage(after: "proposal"))
    }

    func test_nextStage_converted_isNil() {
        XCTAssertNil(LeadListViewModel.nextStage(after: "converted"))
    }

    func test_nextStage_won_isNil() {
        XCTAssertNil(LeadListViewModel.nextStage(after: "won"))
    }

    func test_nextStage_lost_isNil() {
        XCTAssertNil(LeadListViewModel.nextStage(after: "lost"))
    }

    func test_nextStage_unknown_isNil() {
        XCTAssertNil(LeadListViewModel.nextStage(after: "bogus"))
    }

    func test_nextStage_isCaseInsensitive() {
        XCTAssertEqual(LeadListViewModel.nextStage(after: "NEW"), "contacted")
        XCTAssertEqual(LeadListViewModel.nextStage(after: "Contacted"), "scheduled")
    }

    // MARK: - previousStage

    func test_previousStage_contacted_isNew() {
        XCTAssertEqual(LeadListViewModel.previousStage(before: "contacted"), "new")
    }

    func test_previousStage_scheduled_isContacted() {
        XCTAssertEqual(LeadListViewModel.previousStage(before: "scheduled"), "contacted")
    }

    func test_previousStage_qualified_isScheduled() {
        XCTAssertEqual(LeadListViewModel.previousStage(before: "qualified"), "scheduled")
    }

    func test_previousStage_proposal_isQualified() {
        XCTAssertEqual(LeadListViewModel.previousStage(before: "proposal"), "qualified")
    }

    func test_previousStage_new_isNil() {
        XCTAssertNil(LeadListViewModel.previousStage(before: "new"))
    }

    func test_previousStage_unknown_isNil() {
        XCTAssertNil(LeadListViewModel.previousStage(before: "bogus"))
    }

    func test_previousStage_isCaseInsensitive() {
        XCTAssertEqual(LeadListViewModel.previousStage(before: "CONTACTED"), "new")
    }

    // MARK: - stageOrder integrity

    func test_stageOrder_hasExpectedCount() {
        XCTAssertEqual(LeadListViewModel.stageOrder.count, 8)
    }

    func test_stageOrder_startsWithNew() {
        XCTAssertEqual(LeadListViewModel.stageOrder.first, "new")
    }

    func test_stageOrder_lastIsLost() {
        XCTAssertEqual(LeadListViewModel.stageOrder.last, "lost")
    }

    func test_stageOrder_hasNoDuplicates() {
        let arr = LeadListViewModel.stageOrder
        XCTAssertEqual(arr.count, Set(arr).count, "stageOrder contains duplicates")
    }

    func test_nextThenPrevious_roundTrips() {
        let start = "contacted"
        let next = LeadListViewModel.nextStage(after: start)!
        let back = LeadListViewModel.previousStage(before: next)
        XCTAssertEqual(back, start)
    }
}
