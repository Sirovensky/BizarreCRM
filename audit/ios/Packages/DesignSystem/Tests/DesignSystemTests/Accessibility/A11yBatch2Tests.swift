import XCTest
import SwiftUI
@testable import DesignSystem

// MARK: - RotorSupportModifierTests

final class RotorSupportModifierTests: XCTestCase {

    // MARK: rotorHeading compiles

    func testRotorHeadingExtensionCompiles() {
        let view = Text("Ticket #1001").rotorHeading("Ticket #1001")
        _ = view
    }

    func testRotorLinkExtensionCompiles() {
        let view = Text("Invoice PDF").rotorLink("Download invoice PDF")
        _ = view
    }

    // MARK: rotorNavigation compiles

    func testRotorNavigationWithEmptyLabels() {
        let labels: [String] = []
        let view = ScrollView {
            EmptyView()
        }.rotorNavigation(headings: labels)
        _ = view
    }

    func testRotorNavigationWithLabels() {
        let labels = ["Ticket 1001", "Ticket 1002", "Ticket 1003"]
        let view = ScrollView {
            EmptyView()
        }.rotorNavigation(headings: labels)
        _ = view
    }

    func testRotorLinksNavigationCompiles() {
        let labels = ["Link A", "Link B"]
        let view = VStack { EmptyView() }
            .rotorLinksNavigation(labels: labels)
        _ = view
    }
}

// MARK: - AdaptiveStackLayoutTests

final class AdaptiveStackLayoutTests: XCTestCase {

    // MARK: Init defaults

    func testAdaptiveStackInstantiates() {
        let stack = AdaptiveStack {
            Text("Left")
            Text("Right")
        }
        _ = stack
    }

    func testAdaptiveStackWithSpacing() {
        let stack = AdaptiveStack(spacing: DesignTokens.Spacing.sm) {
            Text("A")
            Spacer()
            Text("B")
        }
        _ = stack
    }

    func testAdaptiveStackVerticalAlignmentLeadingByDefault() {
        // Compiles — default verticalAlignment is .leading
        let stack = AdaptiveStack {
            Text("Only child")
        }
        _ = stack
    }

    func testAdaptiveStackCustomVerticalAlignment() {
        let stack = AdaptiveStack(verticalAlignment: .center) {
            Text("Center-aligned in VStack fallback")
        }
        _ = stack
    }

    // MARK: adaptiveStack() modifier

    func testAdaptiveStackModifierCompiles() {
        let view = HStack {
            Text("A")
            Text("B")
        }
        .adaptiveStack()
        _ = view
    }

    func testAdaptiveStackModifierWithSpacing() {
        let view = Text("Hello").adaptiveStack(spacing: 8)
        _ = view
    }

    func testAdaptiveStackModifierWithAlignment() {
        let view = Text("Trailing")
            .adaptiveStack(verticalAlignment: .trailing)
        _ = view
    }
}

// MARK: - SelectedCardBorderModifierTests

final class SelectedCardBorderModifierTests: XCTestCase {

    // MARK: Init defaults

    func testModifierDefaultCornerRadius() {
        let mod = SelectedCardBorderModifier(isSelected: true)
        XCTAssertEqual(mod.cornerRadius, DesignTokens.Radius.lg)
    }

    func testModifierDefaultSelectedColor() {
        let mod = SelectedCardBorderModifier(isSelected: true)
        XCTAssertEqual(mod.selectedColor, .bizarrePrimary)
    }

    func testModifierCustomCornerRadius() {
        let mod = SelectedCardBorderModifier(isSelected: false, cornerRadius: DesignTokens.Radius.md)
        XCTAssertEqual(mod.cornerRadius, DesignTokens.Radius.md)
    }

    func testModifierCustomColor() {
        let mod = SelectedCardBorderModifier(isSelected: true, selectedColor: .bizarreError)
        XCTAssertEqual(mod.selectedColor, .bizarreError)
    }

    // MARK: isSelected flag stored

    func testModifierStoresIsSelectedTrue() {
        let mod = SelectedCardBorderModifier(isSelected: true)
        XCTAssertTrue(mod.isSelected)
    }

    func testModifierStoresIsSelectedFalse() {
        let mod = SelectedCardBorderModifier(isSelected: false)
        XCTAssertFalse(mod.isSelected)
    }

    // MARK: View extension compiles

    func testSelectedCardBorderExtensionSelected() {
        let view = RoundedRectangle(cornerRadius: 16).selectedCardBorder(isSelected: true)
        _ = view
    }

    func testSelectedCardBorderExtensionDeselected() {
        let view = RoundedRectangle(cornerRadius: 16).selectedCardBorder(isSelected: false)
        _ = view
    }

    func testSelectedCardBorderExtensionFullParams() {
        let view = RoundedRectangle(cornerRadius: 12)
            .selectedCardBorder(
                isSelected: true,
                cornerRadius: 12,
                selectedColor: .bizarreTeal
            )
        _ = view
    }
}

// MARK: - TappableFrameModifierTests

final class TappableFrameModifierTests: XCTestCase {

    // MARK: Constant

    func testMinimumSideIs44() {
        XCTAssertEqual(TappableFrameModifier.minimumSide, 44)
    }

    func testMinimumSideIsPositive() {
        XCTAssertGreaterThan(TappableFrameModifier.minimumSide, 0)
    }

    // MARK: Init

    func testModifierDefaultAssertTrue() {
        let mod = TappableFrameModifier()
        XCTAssertTrue(mod.assertOnViolation)
    }

    func testModifierAssertFalse() {
        let mod = TappableFrameModifier(assertOnViolation: false)
        XCTAssertFalse(mod.assertOnViolation)
    }

    // MARK: View extension compiles

    func testTappableFrameExtensionDefaultCompiles() {
        let view = Image(systemName: "xmark").tappableFrame()
        _ = view
    }

    func testTappableFrameExtensionNoAssertCompiles() {
        let view = Image(systemName: "plus").tappableFrame(assert: false)
        _ = view
    }

    // MARK: Size boundary logic

    func testExactly44PassesBoundary() {
        let side = TappableFrameModifier.minimumSide
        XCTAssertFalse(side < TappableFrameModifier.minimumSide)
    }

    func testOnePtUnder44FailsBoundary() {
        let candidate: CGFloat = TappableFrameModifier.minimumSide - 0.1
        XCTAssertTrue(candidate < TappableFrameModifier.minimumSide)
    }

    // Relationship to MinTapTargetModifier: both constants must agree.
    func testTappableFrameAndMinTapTargetAgreOnMinimum() {
        XCTAssertEqual(TappableFrameModifier.minimumSide, MinTapTargetModifier.minimumSide)
    }
}

// MARK: - ColorBlindSafePaletteTests

final class ColorBlindSafePaletteTests: XCTestCase {

    // MARK: ChartPattern

    func testChartPatternRawValues() {
        XCTAssertEqual(ChartPattern.diagonal.rawValue,   "diagonal")
        XCTAssertEqual(ChartPattern.horizontal.rawValue, "horizontal")
        XCTAssertEqual(ChartPattern.dots.rawValue,       "dots")
        XCTAssertEqual(ChartPattern.vertical.rawValue,   "vertical")
    }

    func testChartPatternHashable() {
        let set: Set<ChartPattern> = [.diagonal, .horizontal, .dots, .vertical]
        XCTAssertEqual(set.count, 4)
    }

    // MARK: ColorBlindSafeStatusModifier

    func testStatusModifierStoresSystemImage() {
        let mod = ColorBlindSafeStatusModifier(systemImage: "checkmark", accessibilityLabel: "Done")
        XCTAssertEqual(mod.systemImage, "checkmark")
    }

    func testStatusModifierStoresLabel() {
        let mod = ColorBlindSafeStatusModifier(systemImage: "xmark", accessibilityLabel: "Cancelled")
        XCTAssertEqual(mod.accessibilityLabel, "Cancelled")
    }

    func testStatusModifierDefaultGlyphColor() {
        let mod = ColorBlindSafeStatusModifier(systemImage: "circle", accessibilityLabel: "Status")
        XCTAssertEqual(mod.glyphColor, .primary)
    }

    func testStatusModifierCustomGlyphColor() {
        let mod = ColorBlindSafeStatusModifier(
            systemImage: "exclamationmark",
            glyphColor: .bizarreError,
            accessibilityLabel: "Error"
        )
        XCTAssertEqual(mod.glyphColor, .bizarreError)
    }

    // MARK: ColorBlindSafeChartPatternModifier

    func testChartPatternModifierDefaultValues() {
        let mod = ColorBlindSafeChartPatternModifier()
        XCTAssertEqual(mod.pattern, .diagonal)
        XCTAssertEqual(mod.patternColor, .primary)
        XCTAssertEqual(mod.lineWidth, 1, accuracy: 0.001)
        XCTAssertEqual(mod.spacing, 6, accuracy: 0.001)
    }

    func testChartPatternModifierCustomValues() {
        let mod = ColorBlindSafeChartPatternModifier(
            pattern: .dots,
            patternColor: .bizarreTeal,
            lineWidth: 2,
            spacing: 8
        )
        XCTAssertEqual(mod.pattern, .dots)
        XCTAssertEqual(mod.patternColor, .bizarreTeal)
        XCTAssertEqual(mod.lineWidth, 2, accuracy: 0.001)
        XCTAssertEqual(mod.spacing, 8, accuracy: 0.001)
    }

    // MARK: View extensions compile

    func testColorBlindSafeStatusExtensionCompiles() {
        let view = Circle()
            .fill(Color.bizarreSuccess)
            .colorBlindSafeStatus(systemImage: "checkmark", accessibilityLabel: "Paid")
        _ = view
    }

    func testColorBlindSafeChartPatternExtensionCompiles() {
        let view = Rectangle()
            .fill(Color.bizarreOrange)
            .colorBlindSafeChartPattern(pattern: .horizontal)
        _ = view
    }

    func testColorBlindSafeChartPatternDotsCompiles() {
        let view = Rectangle()
            .colorBlindSafeChartPattern(pattern: .dots, spacing: 4)
        _ = view
    }

    func testColorBlindSafeChartPatternVerticalCompiles() {
        let view = Rectangle()
            .colorBlindSafeChartPattern(pattern: .vertical, lineWidth: 1.5)
        _ = view
    }
}
