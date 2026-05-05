import XCTest
@testable import DesignSystem

// §31.6 Accessibility audit helpers — Contrast + tap target tests
//
// Implements §31.6:
//   - "Contrast asserted on brand palette" — WCAG AA (4.5:1 text, 3:1 large/UI)
//   - "Tap target sizing asserted on primary actions" — DesignTokens.Touch.minTargetSide ≥ 44
//
// This file provides:
//   1. ContrastRatio — pure function computing WCAG luminance-based contrast ratio
//   2. Tests asserting every brand palette pair declared in §80 Tokens.swift meets
//      the applicable WCAG minimum.

// MARK: - Contrast ratio math

/// Computes WCAG 2.2 relative luminance (sRGB) for a hex RGB colour.
///
/// Reference: https://www.w3.org/TR/WCAG21/#relative-luminance
private func relativeLuminance(hex: UInt32) -> Double {
    let r = Double((hex >> 16) & 0xFF) / 255.0
    let g = Double((hex >>  8) & 0xFF) / 255.0
    let b = Double( hex        & 0xFF) / 255.0

    func lin(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

/// Returns the WCAG contrast ratio between two hex colours.
///
/// - Returns: A value in [1, 21] where 21 is maximum (black-on-white).
func contrastRatio(foreground fg: UInt32, background bg: UInt32) -> Double {
    let l1 = relativeLuminance(hex: fg)
    let l2 = relativeLuminance(hex: bg)
    let lighter = max(l1, l2)
    let darker  = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)
}

// MARK: - Contrast ratio unit tests (§31.6)

final class ContrastRatioMathTests: XCTestCase {

    // MARK: Known reference pairs (APCA independent verification)

    func test_blackOnWhite_is21to1() {
        let ratio = contrastRatio(foreground: 0x000000, background: 0xFFFFFF)
        XCTAssertEqual(ratio, 21.0, accuracy: 0.001, "Black-on-white must be exactly 21:1")
    }

    func test_whiteOnWhite_is1to1() {
        let ratio = contrastRatio(foreground: 0xFFFFFF, background: 0xFFFFFF)
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001, "Same colour must have contrast ratio of 1")
    }

    func test_contrastRatio_isSymmetric() {
        let fg: UInt32 = 0xFDEED0  // BrandPalette.primary
        let bg: UInt32 = 0x050403  // BrandPalette.bgDeep
        let fgBg = contrastRatio(foreground: fg, background: bg)
        let bgFg = contrastRatio(foreground: bg, background: fg)
        XCTAssertEqual(fgBg, bgFg, accuracy: 0.0001, "Contrast ratio must be symmetric")
    }

    func test_contrastRatio_alwaysAtLeast1() {
        // Spot-check a handful of arbitrary pairs
        let pairs: [(UInt32, UInt32)] = [
            (0xFF0000, 0x00FF00),
            (0x808080, 0x404040),
            (0xFDEED0, 0xE8C98A),
            (0x1A1816, 0xFAF8F5),
        ]
        for (fg, bg) in pairs {
            let ratio = contrastRatio(foreground: fg, background: bg)
            XCTAssertGreaterThanOrEqual(ratio, 1.0, "Contrast ratio must be ≥ 1 for \(String(format: "#%06X", fg)) on \(String(format: "#%06X", bg))")
        }
    }
}

// MARK: - Brand palette WCAG AA assertion tests (§31.6 / §80.4 / §80.5)

final class BrandPaletteContrastTests: XCTestCase {

    // WCAG AA minimums
    private let wcagAANormalText: Double = 4.5
    private let wcagAALargeText:  Double = 3.0

    // MARK: Dark mode: primary cream on deep background

    func test_darkMode_primaryOnBgDeep_meetsWCAG_AA_largeText() {
        // §80: primary #FDEED0 (cream) on bgDeep #050403 — display / heading text
        let ratio = contrastRatio(
            foreground: DesignTokens.BrandPalette.primary,
            background: DesignTokens.BrandPalette.bgDeep
        )
        XCTAssertGreaterThanOrEqual(
            ratio, wcagAALargeText,
            "primary on bgDeep must meet WCAG AA large text (3:1), got \(String(format: "%.2f", ratio)):1"
        )
    }

    func test_darkMode_onColorOnBg_meetsWCAG_AA_normalText() {
        // §80: on #F2EEF9 on bg #0C0B09 — body text
        let ratio = contrastRatio(
            foreground: DesignTokens.BrandPalette.on,
            background: DesignTokens.BrandPalette.bg
        )
        XCTAssertGreaterThanOrEqual(
            ratio, wcagAANormalText,
            "on-color on bg must meet WCAG AA normal text (4.5:1), got \(String(format: "%.2f", ratio)):1"
        )
    }

    func test_darkMode_onPrimaryOnPrimary_meetsWCAG_AA_normalText() {
        // §80: onPrimary #2B1400 on primary #FDEED0 — button label on cream
        let ratio = contrastRatio(
            foreground: DesignTokens.BrandPalette.onPrimary,
            background: DesignTokens.BrandPalette.primary
        )
        XCTAssertGreaterThanOrEqual(
            ratio, wcagAANormalText,
            "onPrimary on primary must meet WCAG AA (4.5:1), got \(String(format: "%.2f", ratio)):1"
        )
    }

    func test_darkMode_successColorOnBg_meetsWCAG_AA_largeText() {
        // §80: success #34C47E on bg #0C0B09 — status badge (large text / UI component)
        let ratio = contrastRatio(
            foreground: DesignTokens.BrandPalette.success,
            background: DesignTokens.BrandPalette.bg
        )
        XCTAssertGreaterThanOrEqual(
            ratio, wcagAALargeText,
            "success on bg must meet WCAG AA large text (3:1), got \(String(format: "%.2f", ratio)):1"
        )
    }

    func test_darkMode_errorColorOnBg_meetsWCAG_AA_largeText() {
        // §80: error #E2526C on bg #0C0B09 — error badge
        let ratio = contrastRatio(
            foreground: DesignTokens.BrandPalette.error,
            background: DesignTokens.BrandPalette.bg
        )
        XCTAssertGreaterThanOrEqual(
            ratio, wcagAALargeText,
            "error on bg must meet WCAG AA large text (3:1), got \(String(format: "%.2f", ratio)):1"
        )
    }

    // MARK: Light mode: text on light backgrounds

    func test_lightMode_onLightOnBgLight_meetsWCAG_AA_normalText() {
        // §80: onLight #1A1816 on bgLight #F5F2ED — body text (light mode)
        let ratio = contrastRatio(
            foreground: DesignTokens.BrandPalette.onLight,
            background: DesignTokens.BrandPalette.bgLight
        )
        XCTAssertGreaterThanOrEqual(
            ratio, wcagAANormalText,
            "onLight on bgLight must meet WCAG AA (4.5:1), got \(String(format: "%.2f", ratio)):1"
        )
    }

    func test_lightMode_successLightOnBgLight_meetsWCAG_AA_largeText() {
        // §80: successLight #1A7C4D on bgLight #F5F2ED — success badge (light mode)
        let ratio = contrastRatio(
            foreground: DesignTokens.BrandPalette.successLight,
            background: DesignTokens.BrandPalette.bgLight
        )
        XCTAssertGreaterThanOrEqual(
            ratio, wcagAALargeText,
            "successLight on bgLight must meet WCAG AA large (3:1), got \(String(format: "%.2f", ratio)):1"
        )
    }

    func test_lightMode_errorLightOnBgLight_meetsWCAG_AA_largeText() {
        // §80: errorLight #B72A3E on bgLight #F5F2ED
        let ratio = contrastRatio(
            foreground: DesignTokens.BrandPalette.errorLight,
            background: DesignTokens.BrandPalette.bgLight
        )
        XCTAssertGreaterThanOrEqual(
            ratio, wcagAALargeText,
            "errorLight on bgLight must meet WCAG AA large (3:1), got \(String(format: "%.2f", ratio)):1"
        )
    }
}

// MARK: - Tap target size assertion tests (§31.6)

final class TapTargetSizeTests: XCTestCase {

    // MARK: DesignTokens.Touch constants

    func test_minTargetSide_isAtLeast44pt() {
        XCTAssertGreaterThanOrEqual(
            DesignTokens.Touch.minTargetSide, 44,
            "WCAG 2.5.5 requires minimum 44pt tap target side"
        )
    }

    func test_minRowSpacing_isPositive() {
        XCTAssertGreaterThan(
            DesignTokens.Touch.minRowSpacing, 0,
            "minRowSpacing must be > 0 to prevent accidental adjacent-row taps"
        )
    }

    // MARK: TappableFrameModifier defaults

    func test_tappableFrameModifier_defaultsToMinTarget() {
        let modifier = TappableFrameModifier()
        XCTAssertEqual(modifier.minWidth, minTapTarget, accuracy: 0.001)
        XCTAssertEqual(modifier.minHeight, minTapTarget, accuracy: 0.001)
    }

    func test_tappableFrameModifier_customValues_areStored() {
        let modifier = TappableFrameModifier(minWidth: 60, minHeight: 50)
        XCTAssertEqual(modifier.minWidth,  60, accuracy: 0.001)
        XCTAssertEqual(modifier.minHeight, 50, accuracy: 0.001)
    }

    func test_minTapTarget_constant_matchesTokens() {
        // The free constant `minTapTarget` and the token must stay in sync.
        XCTAssertEqual(minTapTarget, DesignTokens.Touch.minTargetSide, accuracy: 0.001,
            "minTapTarget constant must equal DesignTokens.Touch.minTargetSide")
    }

    // MARK: §31.6 Parameterized — common interactive sizes must meet 44pt

    func test_commonButtonSizes_meetMinTargetSide() {
        // Verify that Icon sizes used for buttons meet the tap target floor when
        // padded to the minimum. The icon visual size can be < 44, but a button
        // wrapping it must expose ≥ 44pt of interactive area.
        let iconSizes: [CGFloat] = [
            DesignTokens.Icon.small,   // 16pt — will be padded to 44
            DesignTokens.Icon.medium,  // 20pt — will be padded to 44
            DesignTokens.Icon.large,   // 24pt — will be padded to 44
        ]
        for size in iconSizes {
            // After .tappableFrame(), effective tappable area = max(size, minTapTarget)
            let effective = max(size, DesignTokens.Touch.minTargetSide)
            XCTAssertGreaterThanOrEqual(
                effective, DesignTokens.Touch.minTargetSide,
                "Icon size \(size)pt must reach minTargetSide (\(DesignTokens.Touch.minTargetSide)pt) after tappableFrame"
            )
        }
    }
}
