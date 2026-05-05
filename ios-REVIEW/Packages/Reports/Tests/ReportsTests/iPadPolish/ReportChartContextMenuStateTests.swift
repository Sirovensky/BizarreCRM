import XCTest
@testable import Reports

// MARK: - ReportChartContextMenuStateTests
//
// Tests the observable state holder used by ReportChartContextMenu.
// Covers: URL lifecycle, error lifecycle, legend toggle.

@MainActor
final class ReportChartContextMenuStateTests: XCTestCase {

    // MARK: - Initial state

    func test_initial_isLegendVisible_isFalse() {
        let state = ReportChartContextMenuState()
        XCTAssertFalse(state.isLegendVisible)
    }

    func test_initial_pendingShareURL_isNil() {
        let state = ReportChartContextMenuState()
        XCTAssertNil(state.pendingShareURL)
    }

    func test_initial_exportError_isNil() {
        let state = ReportChartContextMenuState()
        XCTAssertNil(state.exportError)
    }

    // MARK: - setPendingShare

    func test_setPendingShare_setsURL() throws {
        let state = ReportChartContextMenuState()
        let url = try XCTUnwrap(URL(string: "file:///tmp/report.pdf"))
        state.setPendingShare(url: url)
        XCTAssertEqual(state.pendingShareURL, url)
    }

    func test_clearPendingShare_nilsURL() throws {
        let state = ReportChartContextMenuState()
        let url = try XCTUnwrap(URL(string: "file:///tmp/report.pdf"))
        state.setPendingShare(url: url)
        XCTAssertNotNil(state.pendingShareURL)
        state.clearPendingShare()
        XCTAssertNil(state.pendingShareURL)
    }

    // MARK: - setExportError

    func test_setExportError_setsMessage() {
        let state = ReportChartContextMenuState()
        state.setExportError("PDF render failed")
        XCTAssertEqual(state.exportError, "PDF render failed")
    }

    func test_clearExportError_nilsMessage() {
        let state = ReportChartContextMenuState()
        state.setExportError("some error")
        state.clearExportError()
        XCTAssertNil(state.exportError)
    }

    // MARK: - isLegendVisible toggle

    func test_isLegendVisible_canBeToggled() {
        let state = ReportChartContextMenuState()
        XCTAssertFalse(state.isLegendVisible)
        state.isLegendVisible = true
        XCTAssertTrue(state.isLegendVisible)
        state.isLegendVisible = false
        XCTAssertFalse(state.isLegendVisible)
    }

    // MARK: - Independence of URL and error state

    func test_errorDoesNotClearURL() throws {
        let state = ReportChartContextMenuState()
        let url = try XCTUnwrap(URL(string: "file:///tmp/report.pdf"))
        state.setPendingShare(url: url)
        state.setExportError("oops")
        XCTAssertNotNil(state.pendingShareURL)
        XCTAssertNotNil(state.exportError)
    }

    func test_clearPendingShare_doesNotClearError() {
        let state = ReportChartContextMenuState()
        state.setExportError("render error")
        state.clearPendingShare()
        XCTAssertEqual(state.exportError, "render error")
    }

    func test_clearExportError_doesNotClearURL() throws {
        let state = ReportChartContextMenuState()
        let url = try XCTUnwrap(URL(string: "file:///tmp/report.pdf"))
        state.setPendingShare(url: url)
        state.clearExportError()
        XCTAssertEqual(state.pendingShareURL, url)
    }
}
