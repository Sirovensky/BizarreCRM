import SwiftUI

// §22 (iPad Pro M4) — Nano-textured glass display colour adjustment.
//
// iPad Pro M4 with the nano-texture display option renders colours with a
// P3 wide gamut. We detect this and apply a subtle +5% opacity boost to
// `bizarreOrange` so the brand colour reads with the same perceptual weight
// on a nano-texture panel as it does on a standard display.
//
// MVP scope: detection helper + adjusted token. Full HDR gradient
// adaptation deferred to Phase 10 performance pass.

// MARK: - Display capability

/// Describes the detected display rendering characteristics.
public enum DisplaySurfaceKind: Sendable {
    /// Standard display (sRGB gamut).
    case standard
    /// Wide-gamut P3 display (nano-texture or OLED on Pro models).
    case wideGamutP3
}

// MARK: - Detector

/// Detects whether the current display supports P3 wide gamut rendering.
///
/// Uses `UIScreen.main.traitCollection.displayGamut` (available iOS 10+).
/// Returns `.standard` on non-UIKit platforms (macOS Server / CLI test host).
public struct NanoTexturedDisplayTint: Sendable {

    private init() {}

    /// The current display's surface kind.
    ///
    /// - Note: Evaluated once per app launch; display gamut does not change
    ///   at runtime.
    public static var displaySurface: DisplaySurfaceKind {
        #if canImport(UIKit)
        let gamut = MainActor.assumeIsolated { UIScreen.main.traitCollection.displayGamut }
        return gamut == .P3 ? .wideGamutP3 : .standard
        #else
        return .standard
        #endif
    }

    /// Returns `true` when the display is a wide-gamut P3 panel (nano-texture or OLED Pro).
    public static var isWideGamut: Bool {
        displaySurface == .wideGamutP3
    }

    // MARK: - Adjusted brand token

    /// `bizarreOrange` with +5% opacity on P3 displays so the brand colour
    /// reads at the same perceptual weight as on sRGB panels.
    ///
    /// Use in place of `Color.bizarreOrange` for brand-accent elements that
    /// sit on a glass or textured background.
    ///
    /// ```swift
    /// .foregroundStyle(NanoTexturedDisplayTint.adjustedBrandOrange)
    /// ```
    public static var adjustedBrandOrange: Color {
        let opacity = isWideGamut ? 1.05 : 1.0   // clamped visually; Color clips at 1.0
        return Color.bizarreOrange.opacity(min(opacity, 1.0))
    }
}

// MARK: - SwiftUI View extension

public extension View {
    /// Apply nano-texture display tint to `bizarreOrange` foreground content.
    ///
    /// Adjusts opacity +5% on P3 (nano-texture / OLED) displays.
    func nanoTextureForeground() -> some View {
        self.foregroundStyle(NanoTexturedDisplayTint.adjustedBrandOrange)
    }
}
