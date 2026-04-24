import XCTest
import SwiftUI
@testable import DesignSystem

// MARK: - AdaptiveContentWidthBreakpoint Tests

final class AdaptiveContentWidthBreakpointTests: XCTestCase {

    // MARK: - maxWidth values

    func testCompactBreakpointMaxWidth() {
        XCTAssertEqual(AdaptiveContentWidthBreakpoint.compact.maxWidth, 560)
    }

    func testRegularBreakpointMaxWidth() {
        XCTAssertEqual(AdaptiveContentWidthBreakpoint.regular.maxWidth, 680)
    }

    func testWideBreakpointMaxWidth() {
        XCTAssertEqual(AdaptiveContentWidthBreakpoint.wide.maxWidth, 720)
    }

    // MARK: - Equatability

    func testCompactEquality() {
        XCTAssertEqual(AdaptiveContentWidthBreakpoint.compact, .compact)
    }

    func testWideNotEqualRegular() {
        XCTAssertNotEqual(AdaptiveContentWidthBreakpoint.wide, .regular)
    }
}

// MARK: - resolveAdaptiveBreakpoint Tests

final class ResolveAdaptiveBreakpointTests: XCTestCase {

    // MARK: - Compact size class always yields .compact

    func testCompactSizeClassNarrowContainer() {
        let result = resolveAdaptiveBreakpoint(sizeClass: .compact, containerWidth: 320)
        XCTAssertEqual(result, .compact)
    }

    func testCompactSizeClassWideContainer() {
        // Even if the container is somehow wide, compact class overrides.
        let result = resolveAdaptiveBreakpoint(sizeClass: .compact, containerWidth: 1200)
        XCTAssertEqual(result, .compact)
    }

    func testNilSizeClassTreatedAsCompact() {
        let result = resolveAdaptiveBreakpoint(sizeClass: nil, containerWidth: 800)
        XCTAssertEqual(result, .compact)
    }

    // MARK: - Regular size class, narrow container → .regular

    func testRegularSizeClassBelow900() {
        let result = resolveAdaptiveBreakpoint(sizeClass: .regular, containerWidth: 768)
        XCTAssertEqual(result, .regular)
    }

    func testRegularSizeClassExactly899() {
        let result = resolveAdaptiveBreakpoint(sizeClass: .regular, containerWidth: 899)
        XCTAssertEqual(result, .regular)
    }

    // MARK: - Regular size class, wide container → .wide

    func testRegularSizeClassExactly900() {
        let result = resolveAdaptiveBreakpoint(sizeClass: .regular, containerWidth: 900)
        XCTAssertEqual(result, .wide)
    }

    func testRegularSizeClassAbove900() {
        // 13" iPad landscape is ~1024 pt wide.
        let result = resolveAdaptiveBreakpoint(sizeClass: .regular, containerWidth: 1024)
        XCTAssertEqual(result, .wide)
    }

    // MARK: - Boundary: exactly at 900

    func testBoundaryAt900IsWide() {
        let result = resolveAdaptiveBreakpoint(sizeClass: .regular, containerWidth: 900)
        XCTAssertEqual(result, .wide)
        XCTAssertEqual(result.maxWidth, 720)
    }

    func testBoundaryJustBelow900IsRegular() {
        let result = resolveAdaptiveBreakpoint(sizeClass: .regular, containerWidth: 899.9)
        XCTAssertEqual(result, .regular)
        XCTAssertEqual(result.maxWidth, 680)
    }
}

// MARK: - MaxContentWidthModifier Tests

final class MaxContentWidthModifierTests: XCTestCase {

    // MARK: - Default init

    func testDefaultMaxWidthIs720() {
        let modifier = MaxContentWidthModifier()
        XCTAssertEqual(modifier.maxWidth, 720)
    }

    func testDefaultPaddingIsBrandBase() {
        let modifier = MaxContentWidthModifier()
        XCTAssertEqual(modifier.horizontalPadding, BrandSpacing.base)
    }

    // MARK: - Custom init

    func testCustomMaxWidthStored() {
        let modifier = MaxContentWidthModifier(maxWidth: 560)
        XCTAssertEqual(modifier.maxWidth, 560)
    }

    func testCustomPaddingStored() {
        let modifier = MaxContentWidthModifier(maxWidth: 720, horizontalPadding: 24)
        XCTAssertEqual(modifier.horizontalPadding, 24)
    }

    func testZeroPaddingAllowed() {
        let modifier = MaxContentWidthModifier(maxWidth: 720, horizontalPadding: 0)
        XCTAssertEqual(modifier.horizontalPadding, 0)
    }

    // MARK: - View conformance (instantiation smoke-test)

    func testModifierConformsToViewModifier() {
        let modifier = MaxContentWidthModifier()
        let _: any ViewModifier = modifier
        XCTAssertTrue(true)
    }

    func testViewExtensionInstantiates() {
        let view = Text("Hello").maxContentWidth()
        let _: some View = view
        XCTAssertTrue(true)
    }

    func testViewExtensionCustomWidthInstantiates() {
        let view = Text("Hello").maxContentWidth(560, padding: 12)
        let _: some View = view
        XCTAssertTrue(true)
    }
}

// MARK: - AdaptiveContentWidthModifier Tests

final class AdaptiveContentWidthModifierTests: XCTestCase {

    // MARK: - Default init

    func testDefaultPaddingIsBrandBase() {
        let modifier = AdaptiveContentWidthModifier()
        XCTAssertEqual(modifier.horizontalPadding, BrandSpacing.base)
    }

    func testCustomPaddingStored() {
        let modifier = AdaptiveContentWidthModifier(horizontalPadding: 32)
        XCTAssertEqual(modifier.horizontalPadding, 32)
    }

    // MARK: - View conformance

    func testModifierConformsToViewModifier() {
        let modifier = AdaptiveContentWidthModifier()
        let _: any ViewModifier = modifier
        XCTAssertTrue(true)
    }

    func testViewExtensionInstantiates() {
        let view = Text("Hello").adaptiveContentWidth()
        let _: some View = view
        XCTAssertTrue(true)
    }

    func testViewExtensionCustomPaddingInstantiates() {
        let view = Text("Hello").adaptiveContentWidth(padding: 24)
        let _: some View = view
        XCTAssertTrue(true)
    }
}
