import XCTest
@testable import Reports

// MARK: - ZoomPanChartStateTests
//
// §15.9: Swift Charts with zoom / pan / compare periods

final class ZoomPanChartStateTests: XCTestCase {

    // MARK: - Init

    func test_init_showsAllPoints() {
        let state = ZoomPanChartState(totalCount: 10)
        XCTAssertEqual(state.visibleRange, 0 ... 9)
    }

    func test_init_emptyPoints_rangeIsZeroToZero() {
        let state = ZoomPanChartState(totalCount: 0)
        XCTAssertEqual(state.visibleRange.lowerBound, 0)
    }

    // MARK: - Zoom In

    func test_zoomIn_halvesVisibleSpan() {
        let state = ZoomPanChartState(totalCount: 20)
        // Full span = 0..19 (20 pts), half-delta = 5
        state.zoomIn()
        let span = state.visibleRange.upperBound - state.visibleRange.lowerBound
        XCTAssertLessThan(span, 19, "Zoom in should reduce span")
    }

    func test_zoomIn_doesNotGoBelow2Points() {
        let state = ZoomPanChartState(totalCount: 5)
        // Zoom in many times
        for _ in 0..<10 { state.zoomIn() }
        let span = state.visibleRange.upperBound - state.visibleRange.lowerBound
        XCTAssertGreaterThanOrEqual(span, 2)
    }

    // MARK: - Zoom Out

    func test_zoomOut_expandsSpan() {
        let state = ZoomPanChartState(totalCount: 20)
        // First zoom in to create a smaller window, then zoom out
        state.visibleRange = 5 ... 10
        let spanBefore = state.visibleRange.upperBound - state.visibleRange.lowerBound
        state.zoomOut()
        let spanAfter = state.visibleRange.upperBound - state.visibleRange.lowerBound
        XCTAssertGreaterThan(spanAfter, spanBefore)
    }

    func test_zoomOut_doesNotExceedTotalCount() {
        let state = ZoomPanChartState(totalCount: 10)
        for _ in 0..<10 { state.zoomOut() }
        XCTAssertEqual(state.visibleRange, 0 ... 9)
    }

    // MARK: - Pan Left

    func test_panLeft_shiftsRangeLeft() {
        let state = ZoomPanChartState(totalCount: 20)
        state.visibleRange = 8 ... 15
        state.panLeft()
        XCTAssertLessThan(state.visibleRange.lowerBound, 8)
    }

    func test_panLeft_clampedAtZero() {
        let state = ZoomPanChartState(totalCount: 20)
        state.visibleRange = 0 ... 7
        let before = state.visibleRange
        state.panLeft()
        // Should not move past zero
        XCTAssertEqual(state.visibleRange, before, "Pan left at zero should not change range")
    }

    // MARK: - Pan Right

    func test_panRight_shiftsRangeRight() {
        let state = ZoomPanChartState(totalCount: 20)
        state.visibleRange = 4 ... 11
        state.panRight()
        XCTAssertGreaterThan(state.visibleRange.lowerBound, 4)
    }

    func test_panRight_clampedAtMax() {
        let state = ZoomPanChartState(totalCount: 20)
        state.visibleRange = 12 ... 19
        let before = state.visibleRange
        state.panRight()
        XCTAssertEqual(state.visibleRange, before, "Pan right at max should not change range")
    }

    // MARK: - Reset

    func test_resetZoom_restoresFullRange() {
        let state = ZoomPanChartState(totalCount: 30)
        state.visibleRange = 5 ... 10
        state.resetZoom()
        XCTAssertEqual(state.visibleRange, 0 ... 29)
    }

    // MARK: - Sync

    func test_sync_updatesRangeWhenCountChanges() {
        let state = ZoomPanChartState(totalCount: 10)
        state.visibleRange = 2 ... 7
        state.sync(to: 20)
        XCTAssertEqual(state.totalCount, 20)
        XCTAssertEqual(state.visibleRange, 0 ... 19, "Sync to new count should reset range")
    }

    func test_sync_noOpWhenCountUnchanged() {
        let state = ZoomPanChartState(totalCount: 10)
        state.visibleRange = 2 ... 7
        state.sync(to: 10)
        XCTAssertEqual(state.visibleRange, 2 ... 7, "Sync with same count should leave range intact")
    }

    // MARK: - visible(from:)

    func test_visible_returnsCorrectSlice() {
        let state = ZoomPanChartState(totalCount: 5)
        state.visibleRange = 1 ... 3
        let pts = ["a", "b", "c", "d", "e"]
        let visible = state.visible(from: pts)
        XCTAssertEqual(visible, ["b", "c", "d"])
    }

    func test_visible_emptyInputReturnsEmpty() {
        let state = ZoomPanChartState(totalCount: 5)
        let pts: [String] = []
        let visible = state.visible(from: pts)
        XCTAssertTrue(visible.isEmpty)
    }
}

// MARK: - CrossReportDrillServiceTests

final class CrossReportDrillServiceTests: XCTestCase {

    private let service = CrossReportDrillService()
    private let from = "2024-01-01"
    private let to   = "2024-01-31"

    func test_revenueContext_hasThreeTargets() {
        let targets = service.targets(for: .revenue(date: "2024-01-15"), fromDate: from, toDate: to)
        XCTAssertEqual(targets.count, 3)
    }

    func test_revenueContext_firstTargetIsTickets() {
        let targets = service.targets(for: .revenue(date: "2024-01-15"), fromDate: from, toDate: to)
        XCTAssertEqual(targets.first?.targetSubTab, .tickets)
    }

    func test_revenueContext_ticketTargetDateMatchesClickedDate() {
        let date = "2024-01-15"
        let targets = service.targets(for: .revenue(date: date), fromDate: from, toDate: to)
        let ticketTarget = targets.first { $0.targetSubTab == .tickets }
        XCTAssertEqual(ticketTarget?.fromDate, date)
        XCTAssertEqual(ticketTarget?.toDate, date)
    }

    func test_ticketStatusContext_hasTargets() {
        let targets = service.targets(
            for: .ticketStatus(status: "open", date: "2024-01-10"),
            fromDate: from,
            toDate: to
        )
        XCTAssertFalse(targets.isEmpty)
    }

    func test_ticketStatusContext_containsRevenueTarget() {
        let targets = service.targets(
            for: .ticketStatus(status: "closed", date: "2024-01-10"),
            fromDate: from,
            toDate: to
        )
        let revTarget = targets.first { $0.targetSubTab == .sales }
        XCTAssertNotNil(revTarget, "Should contain a revenue sub-tab target")
    }

    func test_allTargetIds_areUnique() {
        let targets = service.targets(for: .revenue(date: "2024-01-15"), fromDate: from, toDate: to)
        let ids = targets.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All target IDs must be unique")
    }
}
