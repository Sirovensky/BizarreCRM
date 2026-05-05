import Testing
import SwiftUI
@testable import DesignSystem

// MARK: - Helper: extract RGBA components from a SwiftUI Color

/// Resolves a SwiftUI `Color` to sRGB components via `UIColor` or
/// `NSColor` depending on the platform, returning `(r, g, b, a)` in
/// the range 0…1.  Accurate to ±0.002 (1 step in 8-bit).
private func rgba(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
#if canImport(UIKit)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return (Double(r), Double(g), Double(b), Double(a))
#elseif canImport(AppKit)
    guard let c = NSColor(color).usingColorSpace(.sRGB) else {
        return (0, 0, 0, 0)
    }
    return (Double(c.redComponent), Double(c.greenComponent),
            Double(c.blueComponent), Double(c.alphaComponent))
#else
    return (0, 0, 0, 0)
#endif
}

/// Convert a CSS 0-255 channel value to the 0-1 range used by the
/// assertion tolerance check.
private func ch(_ value: Int) -> Double { Double(value) / 255.0 }

/// Maximum tolerated difference when comparing an 8-bit channel to the
/// resolved `Double` value from SwiftUI/CoreGraphics.
private let tolerance: Double = 0.002   // ≈ 0.51 / 255

@Suite("POSThemeTokens — hex values match HTML spec")
struct POSThemeTokensTests {

    // MARK: - Dark tokens

    @Test("dark.bgDeep == #050403")
    func darkBgDeep() {
        let c = rgba(POSThemeTokens.dark.bgDeep)
        #expect(abs(c.r - ch(0x05)) < tolerance)
        #expect(abs(c.g - ch(0x04)) < tolerance)
        #expect(abs(c.b - ch(0x03)) < tolerance)
        #expect(abs(c.a - 1.0) < tolerance)
    }

    @Test("dark.bg == #0C0B09")
    func darkBg() {
        let c = rgba(POSThemeTokens.dark.bg)
        #expect(abs(c.r - ch(0x0C)) < tolerance)
        #expect(abs(c.g - ch(0x0B)) < tolerance)
        #expect(abs(c.b - ch(0x09)) < tolerance)
    }

    @Test("dark.surfaceSolid == #141211")
    func darkSurfaceSolid() {
        let c = rgba(POSThemeTokens.dark.surfaceSolid)
        #expect(abs(c.r - ch(0x14)) < tolerance)
        #expect(abs(c.g - ch(0x12)) < tolerance)
        #expect(abs(c.b - ch(0x11)) < tolerance)
    }

    @Test("dark.surfaceElev == #1B1917")
    func darkSurfaceElev() {
        let c = rgba(POSThemeTokens.dark.surfaceElev)
        #expect(abs(c.r - ch(0x1B)) < tolerance)
        #expect(abs(c.g - ch(0x19)) < tolerance)
        #expect(abs(c.b - ch(0x17)) < tolerance)
    }

    @Test("dark.surfaceGlass == rgba(28,25,22,0.48)")
    func darkSurfaceGlass() {
        let c = rgba(POSThemeTokens.dark.surfaceGlass)
        #expect(abs(c.r - ch(28)) < tolerance)
        #expect(abs(c.g - ch(25)) < tolerance)
        #expect(abs(c.b - ch(22)) < tolerance)
        #expect(abs(c.a - 0.48) < tolerance)
    }

    @Test("dark.outline == rgba(255,250,240,0.08)")
    func darkOutline() {
        let c = rgba(POSThemeTokens.dark.outline)
        #expect(abs(c.r - ch(255)) < tolerance)
        #expect(abs(c.g - ch(250)) < tolerance)
        #expect(abs(c.b - ch(240)) < tolerance)
        #expect(abs(c.a - 0.08) < tolerance)
    }

    @Test("dark.on == #F2EEF9")
    func darkOn() {
        let c = rgba(POSThemeTokens.dark.on)
        #expect(abs(c.r - ch(0xF2)) < tolerance)
        #expect(abs(c.g - ch(0xEE)) < tolerance)
        #expect(abs(c.b - ch(0xF9)) < tolerance)
    }

    @Test("dark.muted == #A8A4A0")
    func darkMuted() {
        let c = rgba(POSThemeTokens.dark.muted)
        #expect(abs(c.r - ch(0xA8)) < tolerance)
        #expect(abs(c.g - ch(0xA4)) < tolerance)
        #expect(abs(c.b - ch(0xA0)) < tolerance)
    }

    @Test("dark.muted2 == #7E7A76")
    func darkMuted2() {
        let c = rgba(POSThemeTokens.dark.muted2)
        #expect(abs(c.r - ch(0x7E)) < tolerance)
        #expect(abs(c.g - ch(0x7A)) < tolerance)
        #expect(abs(c.b - ch(0x76)) < tolerance)
    }

    @Test("dark.primary == #FDEED0 (cream)")
    func darkPrimary() {
        let c = rgba(POSThemeTokens.dark.primary)
        #expect(abs(c.r - ch(0xFD)) < tolerance)
        #expect(abs(c.g - ch(0xEE)) < tolerance)
        #expect(abs(c.b - ch(0xD0)) < tolerance)
    }

    @Test("dark.primaryBright == #FFF7E0")
    func darkPrimaryBright() {
        let c = rgba(POSThemeTokens.dark.primaryBright)
        #expect(abs(c.r - ch(0xFF)) < tolerance)
        #expect(abs(c.g - ch(0xF7)) < tolerance)
        #expect(abs(c.b - ch(0xE0)) < tolerance)
    }

    @Test("dark.primarySoft == rgba(253,238,208,0.14)")
    func darkPrimarySoft() {
        let c = rgba(POSThemeTokens.dark.primarySoft)
        #expect(abs(c.r - ch(253)) < tolerance)
        #expect(abs(c.g - ch(238)) < tolerance)
        #expect(abs(c.b - ch(208)) < tolerance)
        #expect(abs(c.a - 0.14) < tolerance)
    }

    @Test("dark.onPrimary == #2B1400")
    func darkOnPrimary() {
        let c = rgba(POSThemeTokens.dark.onPrimary)
        #expect(abs(c.r - ch(0x2B)) < tolerance)
        #expect(abs(c.g - ch(0x14)) < tolerance)
        #expect(abs(c.b - ch(0x00)) < tolerance)
    }

    @Test("dark.success == #34C47E")
    func darkSuccess() {
        let c = rgba(POSThemeTokens.dark.success)
        #expect(abs(c.r - ch(0x34)) < tolerance)
        #expect(abs(c.g - ch(0xC4)) < tolerance)
        #expect(abs(c.b - ch(0x7E)) < tolerance)
    }

    @Test("dark.warning == #E8A33D")
    func darkWarning() {
        let c = rgba(POSThemeTokens.dark.warning)
        #expect(abs(c.r - ch(0xE8)) < tolerance)
        #expect(abs(c.g - ch(0xA3)) < tolerance)
        #expect(abs(c.b - ch(0x3D)) < tolerance)
    }

    @Test("dark.error == #E2526C")
    func darkError() {
        let c = rgba(POSThemeTokens.dark.error)
        #expect(abs(c.r - ch(0xE2)) < tolerance)
        #expect(abs(c.g - ch(0x52)) < tolerance)
        #expect(abs(c.b - ch(0x6C)) < tolerance)
    }

    @Test("dark.teal == #4DB8C9")
    func darkTeal() {
        let c = rgba(POSThemeTokens.dark.teal)
        #expect(abs(c.r - ch(0x4D)) < tolerance)
        #expect(abs(c.g - ch(0xB8)) < tolerance)
        #expect(abs(c.b - ch(0xC9)) < tolerance)
    }

    // MARK: - Light tokens

    @Test("light.bgDeep == #FAF8F5")
    func lightBgDeep() {
        let c = rgba(POSThemeTokens.light.bgDeep)
        #expect(abs(c.r - ch(0xFA)) < tolerance)
        #expect(abs(c.g - ch(0xF8)) < tolerance)
        #expect(abs(c.b - ch(0xF5)) < tolerance)
    }

    @Test("light.bg == #F5F2ED")
    func lightBg() {
        let c = rgba(POSThemeTokens.light.bg)
        #expect(abs(c.r - ch(0xF5)) < tolerance)
        #expect(abs(c.g - ch(0xF2)) < tolerance)
        #expect(abs(c.b - ch(0xED)) < tolerance)
    }

    @Test("light.surfaceSolid == #FFFFFF")
    func lightSurfaceSolid() {
        let c = rgba(POSThemeTokens.light.surfaceSolid)
        #expect(abs(c.r - 1.0) < tolerance)
        #expect(abs(c.g - 1.0) < tolerance)
        #expect(abs(c.b - 1.0) < tolerance)
    }

    @Test("light.surfaceElev == #FAF7F2")
    func lightSurfaceElev() {
        let c = rgba(POSThemeTokens.light.surfaceElev)
        #expect(abs(c.r - ch(0xFA)) < tolerance)
        #expect(abs(c.g - ch(0xF7)) < tolerance)
        #expect(abs(c.b - ch(0xF2)) < tolerance)
    }

    @Test("light.surfaceGlass == rgba(255,250,245,0.78)")
    func lightSurfaceGlass() {
        let c = rgba(POSThemeTokens.light.surfaceGlass)
        #expect(abs(c.r - ch(255)) < tolerance)
        #expect(abs(c.g - ch(250)) < tolerance)
        #expect(abs(c.b - ch(245)) < tolerance)
        #expect(abs(c.a - 0.78) < tolerance)
    }

    @Test("light.outline == rgba(30,24,16,0.10)")
    func lightOutline() {
        let c = rgba(POSThemeTokens.light.outline)
        #expect(abs(c.r - ch(30)) < tolerance)
        #expect(abs(c.g - ch(24)) < tolerance)
        #expect(abs(c.b - ch(16)) < tolerance)
        #expect(abs(c.a - 0.10) < tolerance)
    }

    @Test("light.on == #1A1816")
    func lightOn() {
        let c = rgba(POSThemeTokens.light.on)
        #expect(abs(c.r - ch(0x1A)) < tolerance)
        #expect(abs(c.g - ch(0x18)) < tolerance)
        #expect(abs(c.b - ch(0x16)) < tolerance)
    }

    @Test("light.muted == #5A5550")
    func lightMuted() {
        let c = rgba(POSThemeTokens.light.muted)
        #expect(abs(c.r - ch(0x5A)) < tolerance)
        #expect(abs(c.g - ch(0x55)) < tolerance)
        #expect(abs(c.b - ch(0x50)) < tolerance)
    }

    @Test("light.primary == #C2410C (deep orange)")
    func lightPrimary() {
        let c = rgba(POSThemeTokens.light.primary)
        #expect(abs(c.r - ch(0xC2)) < tolerance)
        #expect(abs(c.g - ch(0x41)) < tolerance)
        #expect(abs(c.b - ch(0x0C)) < tolerance)
    }

    @Test("light.primaryBright == #E2600F")
    func lightPrimaryBright() {
        let c = rgba(POSThemeTokens.light.primaryBright)
        #expect(abs(c.r - ch(0xE2)) < tolerance)
        #expect(abs(c.g - ch(0x60)) < tolerance)
        #expect(abs(c.b - ch(0x0F)) < tolerance)
    }

    @Test("light.primarySoft == rgba(194,65,12,0.12)")
    func lightPrimarySoft() {
        let c = rgba(POSThemeTokens.light.primarySoft)
        #expect(abs(c.r - ch(194)) < tolerance)
        #expect(abs(c.g - ch(65)) < tolerance)
        #expect(abs(c.b - ch(12)) < tolerance)
        #expect(abs(c.a - 0.12) < tolerance)
    }

    @Test("light.onPrimary == #FFFFFF")
    func lightOnPrimary() {
        let c = rgba(POSThemeTokens.light.onPrimary)
        #expect(abs(c.r - 1.0) < tolerance)
        #expect(abs(c.g - 1.0) < tolerance)
        #expect(abs(c.b - 1.0) < tolerance)
    }

    @Test("light.success == #1A7C4D")
    func lightSuccess() {
        let c = rgba(POSThemeTokens.light.success)
        #expect(abs(c.r - ch(0x1A)) < tolerance)
        #expect(abs(c.g - ch(0x7C)) < tolerance)
        #expect(abs(c.b - ch(0x4D)) < tolerance)
    }

    @Test("light.warning == #A15B00")
    func lightWarning() {
        let c = rgba(POSThemeTokens.light.warning)
        #expect(abs(c.r - ch(0xA1)) < tolerance)
        #expect(abs(c.g - ch(0x5B)) < tolerance)
        #expect(abs(c.b - ch(0x00)) < tolerance)
    }

    @Test("light.error == #B72A3E")
    func lightError() {
        let c = rgba(POSThemeTokens.light.error)
        #expect(abs(c.r - ch(0xB7)) < tolerance)
        #expect(abs(c.g - ch(0x2A)) < tolerance)
        #expect(abs(c.b - ch(0x3E)) < tolerance)
    }

    @Test("light.teal == #0B5260")
    func lightTeal() {
        let c = rgba(POSThemeTokens.light.teal)
        #expect(abs(c.r - ch(0x0B)) < tolerance)
        #expect(abs(c.g - ch(0x52)) < tolerance)
        #expect(abs(c.b - ch(0x60)) < tolerance)
    }

    // MARK: - Structural invariants

    @Test("dark and light primaries are different (dark = cream, light = orange)")
    func darkAndLightPrimaryDiffer() {
        // cream vs deep-orange — they must never be equal
        let darkP = rgba(POSThemeTokens.dark.primary)
        let lightP = rgba(POSThemeTokens.light.primary)
        #expect(abs(darkP.r - lightP.r) > 0.1,
                "dark.primary.red ≈ \(darkP.r) vs light.primary.red ≈ \(lightP.r)")
    }

    @Test("POSThemeTokens conforms to Sendable")
    func sendableConformance() {
        // Compile-time: assignment to a Sendable-typed variable must succeed.
        let _: any Sendable = POSThemeTokens.dark
        #expect(true)
    }
}
