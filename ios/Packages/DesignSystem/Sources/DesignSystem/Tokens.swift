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

    // MARK: - Radius (§80.2)
    public enum Radius {
        public static let xs: CGFloat = 4       // small chip
        public static let sm: CGFloat = 8       // button
        public static let md: CGFloat = 12      // input field
        public static let lg: CGFloat = 16      // card
        public static let xl: CGFloat = 24      // sheet
        public static let pill: CGFloat = 999   // fully rounded
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
}
