import XCTest
import SwiftUI
@testable import DesignSystem

// MARK: - SkeletonShapeKind Tests

final class SkeletonShapeKindTests: XCTestCase {

    // MARK: - Rectangle default corner radius

    func testRectangleDefaultCornerRadius() {
        let kind = SkeletonShapeKind.rectangle()
        XCTAssertEqual(kind.cornerRadius, DesignTokens.Radius.xs)
    }

    func testRectangleCustomCornerRadius() {
        let kind = SkeletonShapeKind.rectangle(cornerRadius: 8)
        XCTAssertEqual(kind.cornerRadius, 8)
    }

    func testRectangleZeroCornerRadius() {
        let kind = SkeletonShapeKind.rectangle(cornerRadius: 0)
        XCTAssertEqual(kind.cornerRadius, 0)
    }

    // MARK: - Circle corner radius

    func testCircleCornerRadiusIsZero() {
        let kind = SkeletonShapeKind.circle
        XCTAssertEqual(kind.cornerRadius, 0)
    }

    // MARK: - Capsule corner radius

    func testCapsuleCornerRadiusIsZero() {
        let kind = SkeletonShapeKind.capsule
        XCTAssertEqual(kind.cornerRadius, 0)
    }

    // MARK: - Equatability

    func testRectangleEqualSameRadius() {
        XCTAssertEqual(SkeletonShapeKind.rectangle(cornerRadius: 4),
                       SkeletonShapeKind.rectangle(cornerRadius: 4))
    }

    func testRectangleNotEqualDifferentRadius() {
        XCTAssertNotEqual(SkeletonShapeKind.rectangle(cornerRadius: 4),
                          SkeletonShapeKind.rectangle(cornerRadius: 8))
    }

    func testCircleEquality() {
        XCTAssertEqual(SkeletonShapeKind.circle, SkeletonShapeKind.circle)
    }

    func testCapsuleEquality() {
        XCTAssertEqual(SkeletonShapeKind.capsule, SkeletonShapeKind.capsule)
    }

    func testCircleNotEqualCapsule() {
        XCTAssertNotEqual(SkeletonShapeKind.circle, SkeletonShapeKind.capsule)
    }

    func testCircleNotEqualRectangle() {
        XCTAssertNotEqual(SkeletonShapeKind.circle, SkeletonShapeKind.rectangle())
    }
}

// MARK: - SkeletonShape Init Tests

final class SkeletonShapeTests: XCTestCase {

    // MARK: - Default init

    func testDefaultInitStoresRectangleKind() {
        let shape = SkeletonShape()
        if case .rectangle = shape.kind { /* ok */ } else {
            XCTFail("Expected .rectangle, got \(shape.kind)")
        }
    }

    func testDefaultInitStoresDefaultSize() {
        let shape = SkeletonShape()
        XCTAssertEqual(shape.size, CGSize(width: 200, height: 14))
    }

    // MARK: - Custom init

    func testCircleKindStoredCorrectly() {
        let shape = SkeletonShape(.circle, size: CGSize(width: 40, height: 40))
        XCTAssertEqual(shape.kind, .circle)
    }

    func testCapsuleKindStoredCorrectly() {
        let shape = SkeletonShape(.capsule, size: CGSize(width: 80, height: 24))
        XCTAssertEqual(shape.kind, .capsule)
    }

    func testCustomSizeStoredCorrectly() {
        let s = CGSize(width: 120, height: 18)
        let shape = SkeletonShape(.rectangle(cornerRadius: 6), size: s)
        XCTAssertEqual(shape.size, s)
    }

    func testRectangleWithCustomRadiusStoredCorrectly() {
        let shape = SkeletonShape(.rectangle(cornerRadius: 12), size: CGSize(width: 100, height: 16))
        if case .rectangle(let r) = shape.kind {
            XCTAssertEqual(r, 12)
        } else {
            XCTFail("Expected .rectangle")
        }
    }

    // MARK: - Constants

    func testBaseFillOpacityIsPositive() {
        XCTAssertGreaterThan(SkeletonShape.baseFillOpacity, 0)
    }

    func testBaseFillOpacityIsBelowOne() {
        XCTAssertLessThan(SkeletonShape.baseFillOpacity, 1)
    }

    func testShimmerHighlightOpacityIsPositive() {
        XCTAssertGreaterThan(SkeletonShape.shimmerHighlightOpacity, 0)
    }

    func testShimmerHighlightOpacityIsAboveBaseFill() {
        // Highlight must be brighter than the base tone.
        XCTAssertGreaterThan(SkeletonShape.shimmerHighlightOpacity, SkeletonShape.baseFillOpacity)
    }

    func testShimmerDurationIsPositive() {
        XCTAssertGreaterThan(SkeletonShape.shimmerDuration, 0)
    }

    func testShimmerDurationIsReasonable() {
        // Guard against accidentally setting a multi-second or zero duration.
        XCTAssertGreaterThanOrEqual(SkeletonShape.shimmerDuration, 0.5)
        XCTAssertLessThanOrEqual(SkeletonShape.shimmerDuration, 5.0)
    }

    // MARK: - View conformance

    func testSkeletonShapeConformsToView() {
        let shape = SkeletonShape(.rectangle(), size: CGSize(width: 100, height: 20))
        let _: any View = shape
        XCTAssertTrue(true)
    }

    func testSkeletonShapeInstantiatesCircle() {
        let shape = SkeletonShape(.circle, size: CGSize(width: 44, height: 44))
        let _: any View = shape
        XCTAssertTrue(true)
    }

    func testSkeletonShapeInstantiatesCapsule() {
        let shape = SkeletonShape(.capsule, size: CGSize(width: 80, height: 28))
        let _: any View = shape
        XCTAssertTrue(true)
    }
}

// MARK: - SkeletonShimmerOverlay Tests

final class SkeletonShimmerOverlayTests: XCTestCase {

    func testOverlayInstantiatesWithDefaultParams() {
        let overlay = SkeletonShimmerOverlay(
            highlightOpacity: SkeletonShape.shimmerHighlightOpacity,
            duration: SkeletonShape.shimmerDuration
        )
        let _: any View = overlay
        XCTAssertTrue(true)
    }

    func testOverlayAcceptsCustomOpacity() {
        let overlay = SkeletonShimmerOverlay(highlightOpacity: 0.5, duration: 1.0)
        let _: any View = overlay
        XCTAssertTrue(true)
    }

    func testHighlightOpacityStoredCorrectly() {
        let overlay = SkeletonShimmerOverlay(highlightOpacity: 0.25, duration: 1.4)
        XCTAssertEqual(overlay.highlightOpacity, 0.25, accuracy: 0.001)
    }

    func testDurationStoredCorrectly() {
        let overlay = SkeletonShimmerOverlay(highlightOpacity: 0.3, duration: 2.0)
        XCTAssertEqual(overlay.duration, 2.0, accuracy: 0.001)
    }
}
