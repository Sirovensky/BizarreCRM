import XCTest
@testable import Tickets

@MainActor
final class BulkEditSelectionTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isInactive_withEmptySelection() {
        let sut = BulkEditSelection()
        XCTAssertFalse(sut.isActive)
        XCTAssertTrue(sut.selectedIDs.isEmpty)
        XCTAssertEqual(sut.count, 0)
        XCTAssertFalse(sut.hasSelection)
    }

    // MARK: - toggleMode

    func test_toggleMode_activatesWhenInactive() {
        let sut = BulkEditSelection()
        sut.toggleMode()
        XCTAssertTrue(sut.isActive)
    }

    func test_toggleMode_deactivatesAndClearsWhenActive() {
        let sut = BulkEditSelection()
        sut.activateMode()
        sut.toggle(1)
        sut.toggle(2)
        sut.toggleMode() // deactivate
        XCTAssertFalse(sut.isActive)
        XCTAssertTrue(sut.selectedIDs.isEmpty)
    }

    // MARK: - activateMode / deactivate

    func test_activateMode_setsIsActiveTrue() {
        let sut = BulkEditSelection()
        sut.activateMode()
        XCTAssertTrue(sut.isActive)
    }

    func test_deactivate_clearsSelectionAndMode() {
        let sut = BulkEditSelection()
        sut.activateMode()
        sut.toggle(10)
        sut.deactivate()
        XCTAssertFalse(sut.isActive)
        XCTAssertTrue(sut.selectedIDs.isEmpty)
    }

    // MARK: - toggle

    func test_toggle_addsIDWhenNotPresent() {
        let sut = BulkEditSelection()
        sut.toggle(42)
        XCTAssertTrue(sut.selectedIDs.contains(42))
        XCTAssertEqual(sut.count, 1)
    }

    func test_toggle_removesIDWhenPresent() {
        let sut = BulkEditSelection()
        sut.toggle(42)
        sut.toggle(42)
        XCTAssertFalse(sut.selectedIDs.contains(42))
        XCTAssertEqual(sut.count, 0)
    }

    func test_toggle_multipleIDsAccumulate() {
        let sut = BulkEditSelection()
        sut.toggle(1)
        sut.toggle(2)
        sut.toggle(3)
        XCTAssertEqual(sut.count, 3)
        XCTAssertTrue(sut.hasSelection)
    }

    // MARK: - selectAll / clearAll

    func test_selectAll_replacesSelectionWithProvidedIDs() {
        let sut = BulkEditSelection()
        sut.toggle(99)
        sut.selectAll([1, 2, 3])
        XCTAssertEqual(sut.selectedIDs, [1, 2, 3])
    }

    func test_clearAll_emptiesSelectionWithoutDeactivating() {
        let sut = BulkEditSelection()
        sut.activateMode()
        sut.toggle(1)
        sut.toggle(2)
        sut.clearAll()
        XCTAssertTrue(sut.isActive, "Mode should remain active after clearAll")
        XCTAssertTrue(sut.selectedIDs.isEmpty)
    }

    // MARK: - replace

    func test_replace_swapsSelectionImmutably() {
        let sut = BulkEditSelection()
        sut.toggle(5)
        let newSet: Set<Int64> = [10, 20, 30]
        sut.replace(with: newSet)
        XCTAssertEqual(sut.selectedIDs, newSet)
    }

    // MARK: - hasSelection

    func test_hasSelection_falseWhenEmpty() {
        let sut = BulkEditSelection()
        XCTAssertFalse(sut.hasSelection)
    }

    func test_hasSelection_trueAfterToggle() {
        let sut = BulkEditSelection()
        sut.toggle(7)
        XCTAssertTrue(sut.hasSelection)
    }
}
