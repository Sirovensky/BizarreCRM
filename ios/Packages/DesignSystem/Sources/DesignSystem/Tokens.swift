import SwiftUI

/// §80 Master design tokens. Single source.
///
/// **Hard rule** (per `ios/agent-ownership.md` → Independence rules):
/// no inline hex, no raw point values, no magic radii, no arbitrary
/// durations. Every view pulls from here. SwiftLint rule
/// `forbid_inline_design_values` enforces this in CI.
///
/// Colors live in `BrandColors.swift` + `Assets.xcassets` (light/dark
/// variants). This file owns spacing / radius / shadow / motion / z-index.
public enum DesignTokens {

    // MARK: - Spacing (8-pt grid — per §80.1)
    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs:  CGFloat = 4
        public static let sm:  CGFloat = 8
        public static let md:  CGFloat = 12
        public static let lg:  CGFloat = 16
        public static let xl:  CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let xxxl: CGFloat = 32
        public static let huge: CGFloat = 48
    }

    // MARK: - Radius (§80.2 / §30.3)
    public enum Radius {
        public static let xs: CGFloat = 4       // small chip
        public static let sm: CGFloat = 8       // button
        public static let md: CGFloat = 12      // input field
        public static let lg: CGFloat = 16      // card
        public static let xl: CGFloat = 24      // sheet
        public static let pill: CGFloat = 999   // fully rounded
        /// Alias for `pill` — use `.clipShape(Capsule())` in SwiftUI; this value
        /// is for contexts that require a numeric CGFloat (e.g. UIKit, CGPath).
        public static let capsule: CGFloat = 999
    }

    // MARK: - Density mode (§30.2)
    public enum Density {
        /// Compact multiplier — multiply all spacing tokens by this in compact mode.
        public static let compactMultiplier: CGFloat = 0.85
        /// Returns `value × compactMultiplier` when `isCompact` is true, else `value`.
        public static func scaled(_ value: CGFloat, compact isCompact: Bool) -> CGFloat {
            isCompact ? value * compactMultiplier : value
        }
    }

    // MARK: - Shadow (§80.3)
    public struct Shadow: Sendable {
        public let y: CGFloat
        public let blur: CGFloat
        public let opacityDark: Double
        public let opacityLight: Double

        public init(y: CGFloat, blur: CGFloat, opacityDark: Double, opacityLight: Double) {
            self.y = y
            self.blur = blur
            self.opacityDark = opacityDark
            self.opacityLight = opacityLight
        }
    }

    public enum Shadows {
        public static let none = Shadow(y: 0, blur: 0,  opacityDark: 0,    opacityLight: 0)
        public static let xs   = Shadow(y: 1, blur: 2,  opacityDark: 0.25, opacityLight: 0.04)
        public static let sm   = Shadow(y: 2, blur: 4,  opacityDark: 0.35, opacityLight: 0.06)
        public static let md   = Shadow(y: 4, blur: 12, opacityDark: 0.45, opacityLight: 0.10)
        public static let lg   = Shadow(y: 8, blur: 24, opacityDark: 0.55, opacityLight: 0.14)
    }

    // MARK: - Motion timing (§80.6, §66 curves)
    public enum Motion {
        public static let instant: Double = 0.0      // no animation
        public static let quick:   Double = 0.150    // selection / hover
        public static let snappy:  Double = 0.220    // chip pop / toast show
        public static let smooth:  Double = 0.350    // nav push / sheet present
        public static let gentle:  Double = 0.500    // celebratory success
        public static let slow:    Double = 0.800    // decorative, onboarding
    }

    // MARK: - Glass budget (§30 + §1.4)
    public enum Glass {
        /// Max concurrent `.brandGlass` instances per screen. Debug-build
        /// assertion in `BrandGlassModifier` trips when exceeded.
        public static let maxPerScreen: Int = 6
    }

    // MARK: - Icon sizes (§30.8)
    //
    // Three canonical sizes aligned to the iOS HIG tap-target grid.
    // Rule: navigation bar icons → .medium; tab bar → .medium;
    //       inline row leading icons → .small; hero / FAB → .large.
    // Fill vs outline rule: navigation = outline; active/selected = fill.
    public enum Icon {
        /// 16 pt — tight contexts: chips, row trailing badges, sub-labels.
        public static let small:  CGFloat = 16
        /// 20 pt — standard row leading icon, nav bar, tab bar.
        public static let medium: CGFloat = 20
        /// 24 pt — hero cards, FABs, empty-state illustration supplements.
        public static let large:  CGFloat = 24
    }

    // MARK: - Z-index rhythm (§80.x overlay hierarchy)
    public enum Z {
        public static let surface: Double = 0
        public static let content: Double = 10
        public static let nav:     Double = 500
        public static let sheet:   Double = 900
        public static let toast:   Double = 1000
    }

    // MARK: - List-row / touch target (§26.7)
    public enum Touch {
        /// WCAG minimum tappable side (pt). Debug assert at render time.
        public static let minTargetSide: CGFloat = 44
        /// Min spacing between adjacent tappable rows.
        public static let minRowSpacing: CGFloat = 8
    }

    // MARK: - Brand palette (cream wave — §16.27, 2026-04-24)
    // Source of truth: ios/pos-iphone-mockups.html <style> :root block.
    // Android parity: ui/theme/Theme.kt lines 100–154.
    // Use `.bizarrePrimary` asset-catalog token in views; these static values
    // are for programmatic use (e.g. tests, non-SwiftUI rendering).
    public enum BrandPalette {
        // Primary action — cream in dark mode; adaptive via BrandPrimary asset.
        public static let primary:       UInt32 = 0xFDEED0  // --primary (dark)
        public static let primaryLight:  UInt32 = 0xE8C98A  // --primary (light, contrast tint)
        public static let onPrimary:     UInt32 = 0x2B1400  // --on-primary (AAA on cream)
        // Warm Zinc backgrounds (dark mode)
        public static let bgDeep:        UInt32 = 0x050403  // --bg-deep
        public static let bg:            UInt32 = 0x0C0B09  // --bg
        public static let surfaceSolid:  UInt32 = 0x141211  // --surface-solid
        public static let surfaceElev:   UInt32 = 0x1B1917  // --surface-elev
        // Light mode backgrounds
        public static let bgDeepLight:   UInt32 = 0xFAF8F5  // --bg-deep (light)
        public static let bgLight:       UInt32 = 0xF5F2ED  // --bg (light)
        // Text
        public static let on:            UInt32 = 0xF2EEF9  // --on (dark)
        public static let onLight:       UInt32 = 0x1A1816  // --on (light)
        public static let muted:         UInt32 = 0xA8A4A0  // --muted (dark)
        public static let mutedLight:    UInt32 = 0x5A5550  // --muted (light)
        // Semantic
        public static let success:       UInt32 = 0x34C47E  // --success (dark)
        public static let successLight:  UInt32 = 0x1A7C4D  // --success (light)
        public static let warning:       UInt32 = 0xE8A33D  // --warning (dark)
        public static let warningLight:  UInt32 = 0xA15B00  // --warning (light)
        public static let error:         UInt32 = 0xE2526C  // --error (dark)
        public static let errorLight:    UInt32 = 0xB72A3E  // --error (light)
        public static let teal:          UInt32 = 0x4DB8C9  // --teal (dark)
        public static let tealLight:     UInt32 = 0x0B5260  // --teal (light)
    }
}
