import SwiftUI

public extension Color {
    static let bizarreSurfaceBase        = Color("SurfaceBase",           bundle: .main)
    static let bizarreSurface1           = Color("Surface1",              bundle: .main)
    static let bizarreSurface2           = Color("Surface2",              bundle: .main)
    /// Elevated surface — one step above `Surface2`. Used as the opaque solid
    /// replacement for `.brandGlass` when Reduce Transparency is active (§1.4).
    /// Maps to `SurfaceElevated` in the asset catalog (warm-zinc ramp).
    static let bizarreSurfaceElevated    = Color("SurfaceElevated",       bundle: .main)
    static let bizarreOutline            = Color("Outline",               bundle: .main)
    static let bizarreOnSurface          = Color("OnSurface",             bundle: .main)
    static let bizarreOnSurfaceMuted     = Color("OnSurfaceMuted",        bundle: .main)
    /// Adaptive primary — cream `#fdeed0` in dark mode, deep-orange `#c2410c` in light.
    /// Use this instead of `bizarreOrange` for all brand-primary interactive elements.
    static let bizarrePrimary            = Color("BrandPrimary",          bundle: .main)
    /// On-primary text — dark brown `#2b1400` (AAA on cream; white on deep-orange).
    static let bizarreOnPrimary          = Color("OnBrandOrange",         bundle: .main)
    static let bizarreOrange             = Color("BrandOrange",           bundle: .main)
    static let bizarreOrangeContainer    = Color("BrandOrangeContainer",  bundle: .main)
    static let bizarreOnOrange           = Color("OnBrandOrange",         bundle: .main)
    static let bizarreTeal               = Color("BrandTeal",             bundle: .main)
    static let bizarreMagenta            = Color("BrandMagenta",          bundle: .main)
    static let bizarreSuccess            = Color("SuccessGreen",          bundle: .main)
    static let bizarreWarning            = Color("WarningAmber",          bundle: .main)
    static let bizarreError              = Color("ErrorRose",             bundle: .main)
    // §30 — Semantic badge additions
    static let bizarreDanger             = Color("DangerRed",             bundle: .main)
    static let bizarreInfo               = Color("InfoBlue",              bundle: .main)

    // MARK: - §30.1 Dividers
    /// Subtle 1pt separator between list rows and surface sections.
    static let bizarreDivider           = Color("Divider",              bundle: .main)
    /// Stronger 1-2pt separator for section breaks and card edges.
    static let bizarreDividerStrong     = Color("DividerStrong",        bundle: .main)

    // MARK: - §30.1 Glass tints
    /// Dark-mode glass tint overlay — very low opacity brand-warm dark.
    static let bizarreGlassTintDark     = Color("GlassTintDark",        bundle: .main)
    /// Light-mode glass tint overlay — very low opacity warm cream.
    static let bizarreGlassTintLight    = Color("GlassTintLight",       bundle: .main)

    // MARK: - §30.1 Text semantic aliases
    /// Primary foreground text — alias of `bizarreOnSurface`.
    static let bizarreText              = Color("OnSurface",            bundle: .main)
    /// Secondary / muted text — alias of `bizarreOnSurfaceMuted`.
    static let bizarreTextSecondary     = Color("OnSurfaceMuted",       bundle: .main)
    /// Tertiary / disabled text — lower opacity OnSurface.
    static let bizarreTextTertiary      = Color("TextTertiary",         bundle: .main)
    /// Text on brand-primary fill.
    static let bizarreTextOnBrand       = Color("OnBrandOrange",        bundle: .main)
    /// Placeholder / inactive muted text.
    static let bizarreTextMuted         = Color("OnSurfaceMuted",       bundle: .main)
    /// Primary text — alias of bizarreOnSurface.
    static let bizarreTextPrimary       = Color("OnSurface",            bundle: .main)

    // MARK: - POS primary / on-primary aliases
    // Used by the repair-flow and tender CTAs to express colour intent without
    // hard-coding dark/light hex values. Wired to the existing orange tokens.

    /// Lighter/brighter variant of the brand orange used in gradient stops.
    /// Alias of `bizarreOrangeContainer` which holds the container/bright swatch.
    static let bizarreOrangeBright       = bizarreOrangeContainer
}

// Mirror the brand colors onto ShapeStyle so dot-syntax works at call
// sites like `.foregroundStyle(.bizarreOrange)` and `.fill(.bizarreTeal)`.
public extension ShapeStyle where Self == Color {
    static var bizarreSurfaceBase:     Color { .bizarreSurfaceBase }
    static var bizarreSurface1:        Color { .bizarreSurface1 }
    static var bizarreSurface2:        Color { .bizarreSurface2 }
    static var bizarreSurfaceElevated: Color { .bizarreSurfaceElevated }
    static var bizarreOutline:         Color { .bizarreOutline }
    static var bizarreOnSurface:       Color { .bizarreOnSurface }
    static var bizarreOnSurfaceMuted:  Color { .bizarreOnSurfaceMuted }
    static var bizarrePrimary:         Color { .bizarrePrimary }
    static var bizarreOnPrimary:       Color { .bizarreOnPrimary }
    static var bizarreOrange:          Color { .bizarreOrange }
    static var bizarreOrangeContainer: Color { .bizarreOrangeContainer }
    static var bizarreOnOrange:        Color { .bizarreOnOrange }
    static var bizarreTeal:            Color { .bizarreTeal }
    static var bizarreMagenta:         Color { .bizarreMagenta }
    static var bizarreSuccess:         Color { .bizarreSuccess }
    static var bizarreWarning:         Color { .bizarreWarning }
    static var bizarreError:           Color { .bizarreError }
    // §30 — Semantic badge additions
    static var bizarreDanger:          Color { .bizarreDanger }
    static var bizarreInfo:            Color { .bizarreInfo }
    static var bizarreOrangeBright:    Color { .bizarreOrangeBright }
    // §30.1 Dividers
    static var bizarreDivider:         Color { .bizarreDivider }
    static var bizarreDividerStrong:   Color { .bizarreDividerStrong }
    // §30.1 Glass tints
    static var bizarreGlassTintDark:   Color { .bizarreGlassTintDark }
    static var bizarreGlassTintLight:  Color { .bizarreGlassTintLight }
    // §30.1 Text semantic aliases
    static var bizarreText:            Color { .bizarreText }
    static var bizarreTextSecondary:   Color { .bizarreTextSecondary }
    static var bizarreTextTertiary:    Color { .bizarreTextTertiary }
    static var bizarreTextOnBrand:     Color { .bizarreTextOnBrand }
    static var bizarreTextMuted:       Color { .bizarreTextMuted }
}
