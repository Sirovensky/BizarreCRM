import XCTest
import SwiftUI
@testable import DesignSystem

final class SkeletonListRowTests: XCTestCase {

    // MARK: - Constants

    func testAvatarDiameterIs40() {
        XCTAssertEqual(SkeletonListRow.avatarDiameter, 40)
    }

    func testTitleLineHeightIs14() {
        XCTAssertEqual(SkeletonListRow.titleLineHeight, 14)
    }

    func testSubtitleLineHeightIs11() {
        XCTAssertEqual(SkeletonListRow.subtitleLineHeight, 11)
    }

    func testSubtitleHeightSmallerThanTitle() {
        XCTAssertLessThan(SkeletonListRow.subtitleLineHeight, SkeletonListRow.titleLineHeight)
    }

    func testBadgeWidthIsPositive() {
        XCTAssertGreaterThan(SkeletonListRow.badgeWidth, 0)
    }

    func testBadgeHeightIsPositive() {
        XCTAssertGreaterThan(SkeletonListRow.badgeHeight, 0)
    }

    func testBadgeWidthIsGreaterThanBadgeHeight() {
        // Badge is wider than tall (landscape pill shape).
        XCTAssertGreaterThan(SkeletonListRow.badgeWidth, SkeletonListRow.badgeHeight)
    }

    // MARK: - Default init

    func testDefaultInitTrailingBadgeIsFalse() {
        let row = SkeletonListRow()
        XCTAssertFalse(row.showTrailingBadge)
    }

    // MARK: - Custom init

    func testTrailingBadgeTrueStoredCorrectly() {
        let row = SkeletonListRow(showTrailingBadge: true)
        XCTAssertTrue(row.showTrailingBadge)
    }

    func testTrailingBadgeFalseStoredCorrectly() {
        let row = SkeletonListRow(showTrailingBadge: false)
        XCTAssertFalse(row.showTrailingBadge)
    }

    // MARK: - View conformance

    func testConformsToView() {
        let row = SkeletonListRow()
        let _: any View = row
        XCTAssertTrue(true)
    }

    func testWithBadgeConformsToView() {
        let row = SkeletonListRow(showTrailingBadge: true)
        let _: any View = row
        XCTAssertTrue(true)
    }

    // MARK: - Avatar diameter matches WCAG minimum touch target

    func testAvatarDiameterMeetsMinimumVisibility() {
        // Avatar must be large enough to be clearly visible (>= 24pt).
        XCTAssertGreaterThanOrEqual(SkeletonListRow.avatarDiameter, 24)
    }
}
