import XCTest
import SwiftUI
@testable import DesignSystem

/// §80 master-tokens smoke checks. Tokens are constants; tests guard against
/// accidental reorderings or renames that would ripple through views.
final class DesignTokensTests: XCTestCase {

    func testSpacingScale() {
        XCTAssertEqual(DesignTokens.Spacing.xxs, 2)
        XCTAssertEqual(DesignTokens.Spacing.xs, 4)
        XCTAssertEqual(DesignTokens.Spacing.sm, 8)
        XCTAssertEqual(DesignTokens.Spacing.md, 12)
        XCTAssertEqual(DesignTokens.Spacing.lg, 16)
        XCTAssertEqual(DesignTokens.Spacing.xl, 20)
        XCTAssertEqual(DesignTokens.Spacing.xxl, 24)
        XCTAssertEqual(DesignTokens.Spacing.xxxl, 32)
        XCTAssertEqual(DesignTokens.Spacing.huge, 48)

        // Scale should stay on an 8pt grid for lg and up (§80.1).
        XCTAssertEqual(Int(DesignTokens.Spacing.lg) % 8, 0)
        XCTAssertEqual(Int(DesignTokens.Spacing.xxl) % 8, 0)
        XCTAssertEqual(Int(DesignTokens.Spacing.xxxl) % 8, 0)
    }

    func testRadiusScale() {
        XCTAssertEqual(DesignTokens.Radius.xs, 4)
        XCTAssertEqual(DesignTokens.Radius.sm, 8)
        XCTAssertEqual(DesignTokens.Radius.md, 12)
        XCTAssertEqual(DesignTokens.Radius.lg, 16)
        XCTAssertEqual(DesignTokens.Radius.xl, 24)
        XCTAssertEqual(DesignTokens.Radius.pill, 999)
    }

    func testShadowOpacities() {
        // Dark mode shadows must be stronger than light per §80.3.
        XCTAssertGreaterThan(DesignTokens.Shadows.md.opacityDark, DesignTokens.Shadows.md.opacityLight)
        XCTAssertGreaterThan(DesignTokens.Shadows.lg.opacityDark, DesignTokens.Shadows.md.opacityDark)
    }

    func testMotionDurations() {
        // §80.6 ordering — each subsequent tier is longer than the prior.
        XCTAssertLessThan(DesignTokens.Motion.instant, DesignTokens.Motion.quick)
        XCTAssertLessThan(DesignTokens.Motion.quick, DesignTokens.Motion.snappy)
        XCTAssertLessThan(DesignTokens.Motion.snappy, DesignTokens.Motion.smooth)
        XCTAssertLessThan(DesignTokens.Motion.smooth, DesignTokens.Motion.gentle)
        XCTAssertLessThan(DesignTokens.Motion.gentle, DesignTokens.Motion.slow)
    }

    func testGlassBudget() {
        // Plan-locked ceiling — any increase should be a spec change + PR.
        XCTAssertEqual(DesignTokens.Glass.maxPerScreen, 6)
    }

    func testTouchTargets() {
        // WCAG / §26.7 floor.
        XCTAssertEqual(DesignTokens.Touch.minTargetSide, 44)
        XCTAssertEqual(DesignTokens.Touch.minRowSpacing, 8)
    }

    func testZIndexRhythm() {
        // Strict ascending (§80.z) — surface < content < nav < sheet < toast.
        XCTAssertLessThan(DesignTokens.Z.surface, DesignTokens.Z.content)
        XCTAssertLessThan(DesignTokens.Z.content, DesignTokens.Z.nav)
        XCTAssertLessThan(DesignTokens.Z.nav, DesignTokens.Z.sheet)
        XCTAssertLessThan(DesignTokens.Z.sheet, DesignTokens.Z.toast)
    }

    func testSectionDividerWeightOpacityRhythm() {
        // SectionDivider depends on this token being present and ordered.
        XCTAssertLessThan(DesignTokens.SectionDividerWeight.hairline.opacity,
                          DesignTokens.SectionDividerWeight.subtle.opacity)
        XCTAssertLessThan(DesignTokens.SectionDividerWeight.subtle.opacity,
                          DesignTokens.SectionDividerWeight.strong.opacity)
    }

    func testSemanticColorAliasesCompile() {
        // §80.9 promised this namespace; downstream packages use these aliases.
        let aliases: [Color] = [
            DesignTokens.SemanticColor.accent,
            DesignTokens.SemanticColor.danger,
            DesignTokens.SemanticColor.warning,
            DesignTokens.SemanticColor.success,
            DesignTokens.SemanticColor.info,
            DesignTokens.SemanticColor.surfaceBase,
            DesignTokens.SemanticColor.cardSurface,
            DesignTokens.SemanticColor.surfaceInset,
            DesignTokens.SemanticColor.surfaceRaised,
            DesignTokens.SemanticColor.surfaceGlass,
            DesignTokens.SemanticColor.textPrimary,
            DesignTokens.SemanticColor.textSecondary,
            DesignTokens.SemanticColor.textMuted,
            DesignTokens.SemanticColor.textInverse,
            DesignTokens.SemanticColor.borderSubtle,
            DesignTokens.SemanticColor.borderStrong,
            DesignTokens.SemanticColor.borderAccent
        ]
        XCTAssertEqual(aliases.count, 17)
    }

    // MARK: - §16.27 Cream primary token

    func testBrandPalettePrimary() {
        // §16.27 — cream primary must be #FDEED0 (cream-wave 2026-04-24).
        XCTAssertEqual(DesignTokens.BrandPalette.primary, 0xFDEED0,
                       "BrandPalette.primary must be #FDEED0 (cream dark-mode token)")
    }

    func testBrandPaletteOnPrimary() {
        // §16.27 — on-primary must be dark brown #2B1400 for AAA contrast.
        XCTAssertEqual(DesignTokens.BrandPalette.onPrimary, 0x2B1400,
                       "BrandPalette.onPrimary must be #2B1400 (AAA on cream)")
    }

    func testBrandPalettePrimaryLight() {
        // §16.27 — light-mode tint darker than cream for contrast.
        XCTAssertEqual(DesignTokens.BrandPalette.primaryLight, 0xE8C98A,
                       "BrandPalette.primaryLight must be #E8C98A (light-mode contrast tint)")
    }
}
