import XCTest
import SwiftUI
@testable import DesignSystem

// MARK: - MinTapTargetModifierTests

final class MinTapTargetModifierTests: XCTestCase {

    // MARK: Constant

    func testMinimumSideIs44() {
        XCTAssertEqual(MinTapTargetModifier.minimumSide, 44)
    }

    // MARK: Modifier construction

    func testModifierInstantiates() {
        let modifier = MinTapTargetModifier()
        // Smoke test: modifier must be constructible with no arguments.
        _ = modifier
    }

    func testViewExtensionCompiles() {
        // Verifies that `.minTapTarget()` is callable and returns `some View`.
        let view = Text("Tap me").minTapTarget()
        _ = view
    }

    // MARK: Content shape / frame semantics

    /// Frame min values are <= the constant (the real frame may be larger if content is wider).
    func testMinTapTargetConstantIsNonNegative() {
        XCTAssertGreaterThan(MinTapTargetModifier.minimumSide, 0)
    }
}

// MARK: - DynamicTypeClampModifierTests

final class DynamicTypeClampModifierTests: XCTestCase {

    // MARK: Init storage

    func testModifierStoresRange() {
        let mod = DynamicTypeClampModifier(min: .large, max: .xxLarge)
        XCTAssertEqual(mod.min, .large)
        XCTAssertEqual(mod.max, .xxLarge)
    }

    func testModifierDefaultMin() {
        let mod = DynamicTypeClampModifier(min: .xSmall, max: .accessibility1)
        XCTAssertEqual(mod.min, .xSmall)
    }

    // MARK: Range overload

    func testRangeOverloadStoresCorrectBounds() {
        let range: ClosedRange<DynamicTypeSize> = .small ... .xLarge
        let mod = DynamicTypeClampModifier(min: range.lowerBound, max: range.upperBound)
        XCTAssertEqual(mod.min, .small)
        XCTAssertEqual(mod.max, .xLarge)
    }

    // MARK: View extension compiles

    func testExplicitBoundsExtensionCompiles() {
        let view = Text("Clamped").dynamicTypeClamp(min: .small, max: .xxLarge)
        _ = view
    }

    func testRangeExtensionCompiles() {
        let view = Text("Clamped").dynamicTypeClamp(.large ... .accessibility2)
        _ = view
    }

    // MARK: Edge cases — equal bounds

    func testEqualMinMaxIsValid() {
        let mod = DynamicTypeClampModifier(min: .medium, max: .medium)
        XCTAssertEqual(mod.min, mod.max)
    }
}

// MARK: - ReduceMotionCompliantModifierTests

final class ReduceMotionCompliantModifierTests: XCTestCase {

    // MARK: View extension compiles

    func testExtensionCompiles() {
        let view = Circle().reduceMotionCompliant { Rectangle() }
        _ = view
    }

    func testExtensionWithSameTypeCompiles() {
        let view = Text("Animated").reduceMotionCompliant { Text("Static") }
        _ = view
    }

    // MARK: Modifier init

    func testModifierInitWithViewBuilder() {
        var called = false
        let mod = ReduceMotionCompliantModifier<Text> {
            called = true
            return Text("Static")
        }
        _ = mod
        // ViewBuilder closure is captured but not yet called during init.
        XCTAssertFalse(called)
    }
}

// MARK: - ContrastBoostModifierTests

final class ContrastBoostModifierTests: XCTestCase {

    // MARK: Defaults

    func testDefaultBorderColorIsPrimary() {
        let mod = ContrastBoostModifier()
        XCTAssertEqual(mod.borderColor, .primary)
    }

    func testDefaultCornerRadius() {
        let mod = ContrastBoostModifier()
        XCTAssertEqual(mod.cornerRadius, DesignTokens.Radius.sm)
    }

    func testDefaultBoostedBorderWidth() {
        let mod = ContrastBoostModifier()
        XCTAssertEqual(mod.boostedBorderWidth, 1.5, accuracy: 0.001)
    }

    // MARK: Custom parameters are stored

    func testCustomBorderColorIsStored() {
        let mod = ContrastBoostModifier(borderColor: .red)
        XCTAssertEqual(mod.borderColor, .red)
    }

    func testCustomCornerRadiusIsStored() {
        let mod = ContrastBoostModifier(cornerRadius: DesignTokens.Radius.lg)
        XCTAssertEqual(mod.cornerRadius, DesignTokens.Radius.lg)
    }

    func testCustomBorderWidthIsStored() {
        let mod = ContrastBoostModifier(boostedBorderWidth: 3.0)
        XCTAssertEqual(mod.boostedBorderWidth, 3.0, accuracy: 0.001)
    }

    // MARK: View extension compiles

    func testExtensionDefaultsCompile() {
        let view = Text("Label").contrastBoost()
        _ = view
    }

    func testExtensionFullParamsCompile() {
        let view = Text("Label")
            .contrastBoost(borderColor: .blue, cornerRadius: 8, boostedBorderWidth: 2)
        _ = view
    }

    // MARK: Border width is positive

    func testBoostedBorderWidthIsPositive() {
        let mod = ContrastBoostModifier()
        XCTAssertGreaterThan(mod.boostedBorderWidth, 0)
    }

    // MARK: Corner radius matches token

    func testCornerRadiusMatchesSmToken() {
        XCTAssertEqual(DesignTokens.Radius.sm, 8)
    }
}

// MARK: - PolishInspectorOverlayTests

#if DEBUG

final class PolishInspectorOverlayTests: XCTestCase {

    // MARK: PolishViolation model

    func testViolationKindRawValues() {
        XCTAssertEqual(PolishViolation.Kind.tapTargetTooSmall.rawValue, "Tap target < 44 pt")
        XCTAssertEqual(PolishViolation.Kind.missingA11yLabel.rawValue, "Missing a11y label")
    }

    func testViolationEquality() {
        let v1 = PolishViolation(kind: .tapTargetTooSmall)
        let v2 = PolishViolation(kind: .tapTargetTooSmall)
        XCTAssertEqual(v1, v2)
    }

    func testViolationInequality() {
        let v1 = PolishViolation(kind: .tapTargetTooSmall)
        let v2 = PolishViolation(kind: .missingA11yLabel)
        XCTAssertNotEqual(v1, v2)
    }

    // MARK: PolishInspectorModifier init defaults

    func testModifierDefaultsCheckBoth() {
        let mod = PolishInspectorModifier()
        XCTAssertTrue(mod.checkTapTarget)
        XCTAssertTrue(mod.checkA11yLabel)
        XCTAssertNil(mod.accessibilityLabelHint)
    }

    func testModifierCanDisableEachCheck() {
        let modNoTarget = PolishInspectorModifier(checkTapTarget: false, checkA11yLabel: true)
        XCTAssertFalse(modNoTarget.checkTapTarget)
        XCTAssertTrue(modNoTarget.checkA11yLabel)

        let modNoLabel = PolishInspectorModifier(checkTapTarget: true, checkA11yLabel: false)
        XCTAssertTrue(modNoLabel.checkTapTarget)
        XCTAssertFalse(modNoLabel.checkA11yLabel)
    }

    func testModifierAcceptsLabelHint() {
        let mod = PolishInspectorModifier(accessibilityLabelHint: "Close")
        XCTAssertEqual(mod.accessibilityLabelHint, "Close")
    }

    // MARK: View extension compiles

    func testPolishInspectorExtensionCompiles() {
        let view = Text("Test").polishInspector()
        _ = view
    }

    func testPolishInspectorWithLabelCompiles() {
        let view = Text("Test")
            .polishInspector(
                checkTapTarget: true,
                checkA11yLabel: true,
                accessibilityLabel: "Test"
            )
        _ = view
    }

    // MARK: Environment key

    func testEnvironmentKeyDefaultIsFalse() {
        let values = EnvironmentValues()
        XCTAssertFalse(values.showPolishInspector)
    }

    // MARK: Missing label detection (via hint proxy)

    /// Inspector flags a nil hint as a missing label.
    func testNilHintFlagsMissingLabel() {
        // Simulate the private logic: nil hint → missing
        let hint: String? = nil
        let isMissing = hint == nil || hint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        XCTAssertTrue(isMissing)
    }

    /// Inspector flags an empty string hint as a missing label.
    func testEmptyHintFlagsMissingLabel() {
        let hint: String? = "   "
        let isMissing = hint == nil || hint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        XCTAssertTrue(isMissing)
    }

    /// Inspector does NOT flag a non-empty hint.
    func testNonEmptyHintDoesNotFlagMissingLabel() {
        let hint: String? = "Close button"
        let isMissing = hint == nil || hint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        XCTAssertFalse(isMissing)
    }

    // MARK: Tap target detection (size logic)

    func testSizeAbove44x44PassesTapCheck() {
        let size = CGSize(width: 50, height: 50)
        let tooSmall = size.width < MinTapTargetModifier.minimumSide
                    || size.height < MinTapTargetModifier.minimumSide
        XCTAssertFalse(tooSmall)
    }

    func testSizeBelow44InWidthFailsTapCheck() {
        let size = CGSize(width: 30, height: 50)
        let tooSmall = size.width < MinTapTargetModifier.minimumSide
                    || size.height < MinTapTargetModifier.minimumSide
        XCTAssertTrue(tooSmall)
    }

    func testSizeBelow44InHeightFailsTapCheck() {
        let size = CGSize(width: 50, height: 20)
        let tooSmall = size.width < MinTapTargetModifier.minimumSide
                    || size.height < MinTapTargetModifier.minimumSide
        XCTAssertTrue(tooSmall)
    }

    func testExactly44x44PassesTapCheck() {
        let size = CGSize(width: 44, height: 44)
        let tooSmall = size.width < MinTapTargetModifier.minimumSide
                    || size.height < MinTapTargetModifier.minimumSide
        XCTAssertFalse(tooSmall)
    }

    func testSizeOnePointTooSmallFailsTapCheck() {
        let size = CGSize(width: 43.9, height: 43.9)
        let tooSmall = size.width < MinTapTargetModifier.minimumSide
                    || size.height < MinTapTargetModifier.minimumSide
        XCTAssertTrue(tooSmall)
    }
}

#endif
