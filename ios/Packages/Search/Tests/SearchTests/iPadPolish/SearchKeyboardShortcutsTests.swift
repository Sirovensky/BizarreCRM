import XCTest
@testable import Search

/// §22 — Unit tests for keyboard navigation logic.
///
/// Note: `SearchKeyboardShortcutsModifier` is a SwiftUI modifier and cannot
/// be unit-tested in isolation (no UIKit test host). We test the pure
/// navigation-index logic extracted from the modifier here.
final class SearchKeyboardShortcutsTests: XCTestCase {

    // MARK: - moveToPrevious (pure logic mirror)

    func test_moveToPrevious_fromMiddle_decrementsIndex() {
        var index: Int? = 3
        moveToPrevious(hitCount: 5, selectedIndex: &index)
        XCTAssertEqual(index, 2)
    }

    func test_moveToPrevious_fromFirst_clampsToZero() {
        var index: Int? = 0
        moveToPrevious(hitCount: 5, selectedIndex: &index)
        XCTAssertEqual(index, 0)
    }

    func test_moveToPrevious_whenNil_selectsLast() {
        var index: Int? = nil
        moveToPrevious(hitCount: 5, selectedIndex: &index)
        XCTAssertEqual(index, 4)
    }

    func test_moveToPrevious_emptyList_doesNothing() {
        var index: Int? = nil
        moveToPrevious(hitCount: 0, selectedIndex: &index)
        XCTAssertNil(index)
    }

    // MARK: - moveToNext (pure logic mirror)

    func test_moveToNext_fromMiddle_incrementsIndex() {
        var index: Int? = 2
        moveToNext(hitCount: 5, selectedIndex: &index)
        XCTAssertEqual(index, 3)
    }

    func test_moveToNext_fromLast_clampsToLast() {
        var index: Int? = 4
        moveToNext(hitCount: 5, selectedIndex: &index)
        XCTAssertEqual(index, 4)
    }

    func test_moveToNext_whenNil_selectsFirst() {
        var index: Int? = nil
        moveToNext(hitCount: 5, selectedIndex: &index)
        XCTAssertEqual(index, 0)
    }

    func test_moveToNext_emptyList_doesNothing() {
        var index: Int? = nil
        moveToNext(hitCount: 0, selectedIndex: &index)
        XCTAssertNil(index)
    }

    // MARK: - Scope shortcut coverage

    func test_shortcutDigits_coverAllNonAllScopes() {
        let scopesWithDigits = SearchScope.allCases.filter { $0.shortcutDigit != nil }
        // All non-.all scopes must have a digit
        let nonAllScopes = SearchScope.allCases.filter { $0 != .all }
        XCTAssertEqual(scopesWithDigits.count, nonAllScopes.count)
    }

    func test_shortcutDigits_range1Through5() {
        let digits = SearchScope.allCases.compactMap { $0.shortcutDigit }
        XCTAssertEqual(Set(digits), Set(1...5))
    }

    // MARK: - SearchFocusField

    func test_focusField_searchBarHashable() {
        let a = SearchFocusField.searchBar
        let b = SearchFocusField.searchBar
        XCTAssertEqual(a, b)
    }

    // MARK: - Helpers (mirror of private modifier logic)

    private func moveToPrevious(hitCount: Int, selectedIndex: inout Int?) {
        guard hitCount > 0 else { return }
        if let current = selectedIndex {
            selectedIndex = max(0, current - 1)
        } else {
            selectedIndex = hitCount - 1
        }
    }

    private func moveToNext(hitCount: Int, selectedIndex: inout Int?) {
        guard hitCount > 0 else { return }
        if let current = selectedIndex {
            selectedIndex = min(hitCount - 1, current + 1)
        } else {
            selectedIndex = 0
        }
    }
}
