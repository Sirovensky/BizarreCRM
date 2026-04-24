import SwiftUI

/// POS design-system colour tokens.
///
/// Two static providers mirror the CSS `:root` (dark) and `.light-mode`
/// blocks in `ios/pos-iphone-mockups.html` / `ios/pos-ipad-mockups.html`
/// exactly.  Views read the active theme via
/// `@Environment(\.posTheme) private var theme`.
///
/// Sendable conformance is safe because `Color` is itself `Sendable` in
/// SwiftUI and all stored properties are immutable value types.
public struct POSThemeTokens: Sendable {

    // MARK: - Background surfaces

    /// Deepest background; used for the page / window fill.
    public let bgDeep: Color

    /// Primary background of the chrome / navigation layer.
    public let bg: Color

    /// Opaque card / list-row surface.
    public let surfaceSolid: Color

    /// Slightly elevated opaque surface (sheet header, popover body).
    public let surfaceElev: Color

    /// Glass / translucent surface — pair with `.ultraThinMaterial`
    /// or `GlassKit.brandGlass(…)` for the blur layer.
    public let surfaceGlass: Color

    // MARK: - Outlines

    /// Default separator / border stroke.
    public let outline: Color

    /// Stronger border used for focused inputs or highlighted rows.
    public let outlineBright: Color

    // MARK: - Foreground

    /// Primary text / icon colour on backgrounds.
    public let on: Color

    /// Secondary / de-emphasised text.
    public let muted: Color

    /// Tertiary text — dates, captions, placeholder fill.
    public let muted2: Color

    // MARK: - Brand primary

    /// Primary interactive colour (cream in dark mode, deep orange in light).
    public let primary: Color

    /// Brighter variant used in gradients and hover states.
    public let primaryBright: Color

    /// Low-opacity wash for selected backgrounds.
    public let primarySoft: Color

    /// Foreground colour on top of `primary`-filled elements.
    public let onPrimary: Color

    // MARK: - Semantic status

    public let success: Color
    public let warning: Color
    public let error: Color
    public let teal: Color

    // MARK: - Memberwise init

    public init(
        bgDeep: Color,
        bg: Color,
        surfaceSolid: Color,
        surfaceElev: Color,
        surfaceGlass: Color,
        outline: Color,
        outlineBright: Color,
        on: Color,
        muted: Color,
        muted2: Color,
        primary: Color,
        primaryBright: Color,
        primarySoft: Color,
        onPrimary: Color,
        success: Color,
        warning: Color,
        error: Color,
        teal: Color
    ) {
        self.bgDeep = bgDeep
        self.bg = bg
        self.surfaceSolid = surfaceSolid
        self.surfaceElev = surfaceElev
        self.surfaceGlass = surfaceGlass
        self.outline = outline
        self.outlineBright = outlineBright
        self.on = on
        self.muted = muted
        self.muted2 = muted2
        self.primary = primary
        self.primaryBright = primaryBright
        self.primarySoft = primarySoft
        self.onPrimary = onPrimary
        self.success = success
        self.warning = warning
        self.error = error
        self.teal = teal
    }
}

// MARK: - Static providers

public extension POSThemeTokens {

    /// Dark-mode tokens — cream primary on warm near-black surfaces.
    ///
    /// Source: `ios/pos-iphone-mockups.html` + `ios/pos-ipad-mockups.html`
    /// `:root` block.
    static let dark = POSThemeTokens(
        bgDeep:        Color(hex: 0x050403),
        bg:            Color(hex: 0x0C0B09),
        surfaceSolid:  Color(hex: 0x141211),
        surfaceElev:   Color(hex: 0x1B1917),
        surfaceGlass:  Color(red: 28/255, green: 25/255, blue: 22/255, opacity: 0.48),
        outline:       Color(red: 1.0, green: 250/255, blue: 240/255, opacity: 0.08),
        outlineBright: Color(red: 1.0, green: 250/255, blue: 240/255, opacity: 0.14),
        on:            Color(hex: 0xF2EEF9),
        muted:         Color(hex: 0xA8A4A0),
        muted2:        Color(hex: 0x7E7A76),
        primary:       Color(hex: 0xFDEED0),
        primaryBright: Color(hex: 0xFFF7E0),
        primarySoft:   Color(red: 253/255, green: 238/255, blue: 208/255, opacity: 0.14),
        onPrimary:     Color(hex: 0x2B1400),
        success:       Color(hex: 0x34C47E),
        warning:       Color(hex: 0xE8A33D),
        error:         Color(hex: 0xE2526C),
        teal:          Color(hex: 0x4DB8C9)
    )

    /// Light-mode tokens — deep orange primary on warm near-white surfaces.
    ///
    /// Source: `ios/pos-iphone-mockups.html` + `ios/pos-ipad-mockups.html`
    /// `.light-mode` block.
    static let light = POSThemeTokens(
        bgDeep:        Color(hex: 0xFAF8F5),
        bg:            Color(hex: 0xF5F2ED),
        surfaceSolid:  Color(hex: 0xFFFFFF),
        surfaceElev:   Color(hex: 0xFAF7F2),
        surfaceGlass:  Color(red: 1.0, green: 250/255, blue: 245/255, opacity: 0.78),
        outline:       Color(red: 30/255, green: 24/255, blue: 16/255, opacity: 0.10),
        outlineBright: Color(red: 30/255, green: 24/255, blue: 16/255, opacity: 0.18),
        on:            Color(hex: 0x1A1816),
        muted:         Color(hex: 0x5A5550),
        muted2:        Color(hex: 0x8A847C),
        primary:       Color(hex: 0xC2410C),
        primaryBright: Color(hex: 0xE2600F),
        primarySoft:   Color(red: 194/255, green: 65/255, blue: 12/255, opacity: 0.12),
        onPrimary:     Color(hex: 0xFFFFFF),
        success:       Color(hex: 0x1A7C4D),
        warning:       Color(hex: 0xA15B00),
        error:         Color(hex: 0xB72A3E),
        teal:          Color(hex: 0x0B5260)
    )
}

// MARK: - Color(hex:) convenience

private extension Color {
    /// Initialise from a 6-digit (RGB) hex integer, e.g. `Color(hex: 0xFF00CC)`.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
