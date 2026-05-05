import XCTest
import SwiftUI
@testable import DesignSystem

// MARK: - §22 iPad Polish — unit tests
// Covers the five items shipped in this commit:
//   1. SplitViewSizeConstraint   — constant assertions
//   2. PointerSemantics          — enum values + HoverHighlightModifier init
//   3. NamespacedScrollPosition  — scroll helpers (iOS 17+)
//   4. DragPreviewCardModifier   — constant assertions
//   5. DropTargetHighlightModifier — constant assertions

// MARK: - 1. SplitViewSizeConstants

final class SplitViewSizeConstantsTests: XCTestCase {

    func testMinWidthIs700() {
        XCTAssertEqual(SplitViewSizeConstants.minWidth, 700,
                       "Stage Manager min width must be 700 pt per §22.7")
    }

    func testMinHeightIs500() {
        XCTAssertEqual(SplitViewSizeConstants.minHeight, 500,
                       "Stage Manager min height must be 500 pt per §22.7")
    }

    func testModifierInstantiates() {
        let modifier = SplitViewMinSizeModifier()
        let _: any ViewModifier = modifier
        XCTAssertTrue(true)
    }

    func testViewExtensionInstantiates() {
        let view = Text("Root").splitViewMinSize()
        let _: some View = view
        XCTAssertTrue(true)
    }
}

// MARK: - 2. PointerSemantics + HoverHighlightModifier

final class PointerSemanticsTests: XCTestCase {

    func testDefaultPointerIsDefault() {
        let modifier = HoverHighlightModifier()
        XCTAssertEqual(modifier.pointer, .default)
    }

    func testLinkPointerStored() {
        let modifier = HoverHighlightModifier(pointer: .link)
        XCTAssertEqual(modifier.pointer, .link)
    }

    func testDefaultAndLinkAreNotEqual() {
        XCTAssertNotEqual(PointerSemantics.default, PointerSemantics.link)
    }

    func testBrandHoverDefaultInstantiates() {
        let view = Text("Row").brandHover()
        let _: some View = view
        XCTAssertTrue(true)
    }

    func testBrandHoverLinkInstantiates() {
        let view = Text("Link").brandHover(pointer: .link)
        let _: some View = view
        XCTAssertTrue(true)
    }

    func testBrandLinkHoverInstantiates() {
        let view = Text("URL").brandLinkHover()
        let _: some View = view
        XCTAssertTrue(true)
    }
}

// MARK: - 3. NamespacedScrollPosition (iOS 17+)

@available(iOS 17.0, *)
final class NamespacedScrollPositionTests: XCTestCase {

    func testInitialPositionCreated() {
        let pos = NamespacedScrollPosition()
        // Just verify it can be created without crash.
        let _: NamespacedScrollPosition = pos
        XCTAssertTrue(true)
    }

    func testScrollToTopDoesNotCrash() {
        var pos = NamespacedScrollPosition()
        pos.scrollToTop()
        XCTAssertTrue(true)
    }

    func testScrollToBottomDoesNotCrash() {
        var pos = NamespacedScrollPosition()
        pos.scrollToBottom()
        XCTAssertTrue(true)
    }

    func testScrollToIdDoesNotCrash() {
        var pos = NamespacedScrollPosition()
        pos.scrollTo("ticket-42")
        XCTAssertTrue(true)
    }

    func testTwoDefaultPositionsAreEqual() {
        let a = NamespacedScrollPosition()
        let b = NamespacedScrollPosition()
        XCTAssertEqual(a, b, "Equatable conformance required for @State change detection")
    }

    func testViewExtensionInstantiates() {
        var pos = NamespacedScrollPosition()
        let binding = Binding(get: { pos }, set: { pos = $0 })
        let view = ScrollView { Text("Content") }
            .brandScrollPosition(binding)
        let _: some View = view
        XCTAssertTrue(true)
    }
}

// MARK: - 4. DragPreviewCardModifier

final class DragPreviewCardModifierTests: XCTestCase {

    func testCornerRadiusIs12() {
        XCTAssertEqual(DragPreviewCardModifier.cornerRadius, 12)
    }

    func testPreviewScaleIs0_9() {
        XCTAssertEqual(DragPreviewCardModifier.previewScale, 0.9, accuracy: 0.001)
    }

    func testShadowRadiusIs8() {
        XCTAssertEqual(DragPreviewCardModifier.shadowRadius, 8)
    }

    func testModifierInstantiates() {
        let modifier = DragPreviewCardModifier()
        let _: any ViewModifier = modifier
        XCTAssertTrue(true)
    }

    func testViewExtensionInstantiates() {
        let view = Text("Ticket #1").brandDragPreview()
        let _: some View = view
        XCTAssertTrue(true)
    }
}

// MARK: - 5. DropTargetHighlightModifier

final class DropTargetHighlightModifierTests: XCTestCase {

    func testCornerRadiusIs10() {
        XCTAssertEqual(DropTargetHighlightModifier.cornerRadius, 10)
    }

    func testTintOpacityIs0_15() {
        XCTAssertEqual(DropTargetHighlightModifier.tintOpacity, 0.15, accuracy: 0.001)
    }

    func testBorderWidthIs2() {
        XCTAssertEqual(DropTargetHighlightModifier.borderWidth, 2)
    }

    func testIsTargetedStoredTrue() {
        let modifier = DropTargetHighlightModifier(isTargeted: true)
        XCTAssertTrue(modifier.isTargeted)
    }

    func testIsTargetedStoredFalse() {
        let modifier = DropTargetHighlightModifier(isTargeted: false)
        XCTAssertFalse(modifier.isTargeted)
    }

    func testViewExtensionTargetedInstantiates() {
        let view = Color.blue.brandDropTargetHighlight(isTargeted: true)
        let _: some View = view
        XCTAssertTrue(true)
    }

    func testViewExtensionUntargetedInstantiates() {
        let view = Color.blue.brandDropTargetHighlight(isTargeted: false)
        let _: some View = view
        XCTAssertTrue(true)
    }
}
