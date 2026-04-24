import XCTest
import SwiftUI
@testable import DesignSystem

final class SkeletonTextLineTests: XCTestCase {

    // MARK: - Constants

    func testDefaultLineHeightIs14() {
        XCTAssertEqual(SkeletonTextLine.defaultLineHeight, 14)
    }

    func testMinimumWidthFractionIsPositive() {
        XCTAssertGreaterThan(SkeletonTextLine.minimumWidthFraction, 0)
    }

    func testMaximumWidthFractionIsOne() {
        XCTAssertEqual(SkeletonTextLine.maximumWidthFraction, 1.0)
    }

    func testMinimumWidthFractionIsLessThanMaximum() {
        XCTAssertLessThan(SkeletonTextLine.minimumWidthFraction, SkeletonTextLine.maximumWidthFraction)
    }

    // MARK: - Default init

    func testDefaultInitWidthFractionIsOne() {
        let line = SkeletonTextLine()
        XCTAssertEqual(line.widthFraction, 1.0, accuracy: 0.001)
    }

    func testDefaultInitLineHeightMatchesConstant() {
        let line = SkeletonTextLine()
        XCTAssertEqual(line.lineHeight, SkeletonTextLine.defaultLineHeight)
    }

    // MARK: - Custom init — width fraction clamping

    func testWidthFractionStoredCorrectly() {
        let line = SkeletonTextLine(widthFraction: 0.75)
        XCTAssertEqual(line.widthFraction, 0.75, accuracy: 0.001)
    }

    func testWidthFractionClampedToMinimum() {
        let line = SkeletonTextLine(widthFraction: 0.0)
        XCTAssertEqual(line.widthFraction, SkeletonTextLine.minimumWidthFraction)
    }

    func testWidthFractionClampedToMaximum() {
        let line = SkeletonTextLine(widthFraction: 2.0)
        XCTAssertEqual(line.widthFraction, SkeletonTextLine.maximumWidthFraction)
    }

    func testNegativeWidthFractionClampedToMinimum() {
        let line = SkeletonTextLine(widthFraction: -1.0)
        XCTAssertEqual(line.widthFraction, SkeletonTextLine.minimumWidthFraction)
    }

    func testWidthFractionAtExactMinimumIsPreserved() {
        let line = SkeletonTextLine(widthFraction: SkeletonTextLine.minimumWidthFraction)
        XCTAssertEqual(line.widthFraction, SkeletonTextLine.minimumWidthFraction, accuracy: 0.001)
    }

    func testWidthFractionAtExactMaximumIsPreserved() {
        let line = SkeletonTextLine(widthFraction: 1.0)
        XCTAssertEqual(line.widthFraction, 1.0, accuracy: 0.001)
    }

    // MARK: - Custom init — line height

    func testCustomLineHeightStoredCorrectly() {
        let line = SkeletonTextLine(widthFraction: 0.5, lineHeight: 18)
        XCTAssertEqual(line.lineHeight, 18)
    }

    func testLineHeightClampedToMinimumOfOne() {
        // Zero or negative line height is not meaningful.
        let line = SkeletonTextLine(widthFraction: 0.5, lineHeight: 0)
        XCTAssertGreaterThanOrEqual(line.lineHeight, 1)
    }

    func testNegativeLineHeightClampedToMinimumOfOne() {
        let line = SkeletonTextLine(widthFraction: 0.5, lineHeight: -5)
        XCTAssertGreaterThanOrEqual(line.lineHeight, 1)
    }

    // MARK: - View conformance

    func testConformsToView() {
        let line = SkeletonTextLine(widthFraction: 0.8)
        let _: any View = line
        XCTAssertTrue(true)
    }

    func testFullWidthLineConformsToView() {
        let line = SkeletonTextLine()
        let _: any View = line
        XCTAssertTrue(true)
    }

    func testNarrowLineConformsToView() {
        let line = SkeletonTextLine(widthFraction: 0.3, lineHeight: 11)
        let _: any View = line
        XCTAssertTrue(true)
    }
}
