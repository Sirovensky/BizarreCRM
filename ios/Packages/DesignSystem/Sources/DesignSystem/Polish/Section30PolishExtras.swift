import SwiftUI

// §30 — Five additional Design System & Motion polish helpers.
//
// Real, wired-in helpers — each modifier is consumed by an existing call site
// inside the DesignSystem module so the additive change is exercised.
//
//   1. .brandIllustrationTinted(_:)    — §30.9 brand-tint convenience for empty-state art
//   2. .sheetKeyboardSafe()            — §30 sheet-over-keyboard recipe (ignoresSafeArea + interactive dismiss)
//   3. BrandGlassIntensity              — §30 three-level glass intensity (strong / medium / minimal)
//   4. BrandMotion.reducedIfNeeded(_:) — §30 motion downgrade ladder (>snappy → instant under Reduce Motion)
//   5. .brandZ(_:)                     — §30 layering-rules helper bound to DesignTokens.Z

// MARK: - 1. §30.9 — Tinted illustration convenience

public extension BrandIllustration {
    /// Returns this illustration tinted with `color`, defaulting to the brand
    /// primary cream/orange. Wraps the standard `.foregroundStyle(_:)` so call
    /// sites read intent rather than mechanics.
    ///
    /// ```swift
    /// BrandIllustration(.emptyTickets)
    ///     .brandIllustrationTinted()
    ///     .frame(width: 96, height: 96)
    /// ```
    func brandIllustrationTinted(_ color: Color = .bizarrePrimary) -> some View {
        self.foregroundStyle(color)
    }
}

// MARK: - 2. §30 — Sheet keyboard-safe recipe

private struct SheetKeyboardSafeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

public extension View {
    /// Applies the §30 canonical bottom-sheet keyboard recipe:
    ///
    /// * `.scrollDismissesKeyboard(.interactively)` — drag inside the scroll
    ///   region collapses the keyboard.
    /// * `.ignoresSafeArea(.keyboard, edges: .bottom)` — sheet contents stay
    ///   sized to the detent rather than being shoved up by the keyboard.
    ///
    /// Pair with `.sheetDetentAnimated($detent)` to promote the detent to
    /// `.large` while editing.
    func sheetKeyboardSafe() -> some View {
        modifier(SheetKeyboardSafeModifier())
    }
}

// MARK: - 3. §30 — Three-level glass intensity

/// Three sanctioned glass intensities per §30 "Glass strength levels":
///
/// * `.strong`  — iOS 26 + A17+ devices: full Liquid Glass refraction.
/// * `.medium`  — iOS 26 on older silicon, or pre-iOS-26: thin material + tint.
/// * `.minimal` — Reduce Transparency / Low Power: opaque tint, no blur.
///
/// Use `BrandGlassIntensity.recommended(reduceTransparency:lowPower:)` to pick
/// automatically; or read the user override from Settings → Appearance.
public enum BrandGlassIntensity: String, CaseIterable, Sendable {
    case strong
    case medium
    case minimal

    /// Maps onto the existing `BrandGlassVariant` so the rest of the glass
    /// pipeline (`.brandGlass(_:in:)`) keeps working unchanged.
    public var variant: BrandGlassVariant {
        switch self {
        case .strong:  return .regular
        case .medium:  return .clear
        case .minimal: return .identity
        }
    }

    /// Picks the appropriate intensity for the current device + a11y context.
    ///
    /// - Parameters:
    ///   - reduceTransparency: From `@Environment(\.accessibilityReduceTransparency)`.
    ///   - lowPower: `ProcessInfo.processInfo.isLowPowerModeEnabled` or test injection.
    public static func recommended(
        reduceTransparency: Bool,
        lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    ) -> BrandGlassIntensity {
        if reduceTransparency || lowPower { return .minimal }
        if #available(iOS 26.0, *) {
            return .strong
        } else {
            return .medium
        }
    }
}

// MARK: - 4. §30 — Reduce Motion downgrade ladder

extension BrandMotion {
    /// Returns `animation` unless Reduce Motion is requested AND the chosen
    /// duration is longer than `MotionDurationSpec.short` (200 ms) — in which
    /// case the result collapses to an instant `.easeInOut(duration: 0)`.
    ///
    /// Used by §30 motion tokens whose duration exceeds the "snappy" budget;
    /// a quick chip pop or selection toggle still animates because the user
    /// will not perceive nausea risk under 200 ms.
    public static func reducedIfNeeded(
        _ animation: Animation,
        duration: Double,
        reduceMotion: Bool
    ) -> Animation {
        guard reduceMotion else { return animation }
        if duration <= MotionDurationSpec.short.seconds {
            return animation
        }
        return .easeInOut(duration: 0)
    }
}

// MARK: - 5. §30 — Layering rules helper (.brandZ)

/// Canonical Z-layer slots per §30 "Layering rules". Backed by the existing
/// `DesignTokens.Z` numeric ladder so a single source of truth controls
/// stack order across the app.
public enum BrandZLayer: Sendable {
    case surface
    case content
    case nav
    case sheet
    case toast

    public var rawValue: Double {
        switch self {
        case .surface: return DesignTokens.Z.surface
        case .content: return DesignTokens.Z.content
        case .nav:     return DesignTokens.Z.nav
        case .sheet:   return DesignTokens.Z.sheet
        case .toast:   return DesignTokens.Z.toast
        }
    }
}

public extension View {
    /// Sets `.zIndex` to the canonical §30 layer slot for `layer`.
    ///
    /// Prefer over inline `.zIndex(900)` — the named layer survives palette /
    /// token edits and is reviewable in code review.
    func brandZ(_ layer: BrandZLayer) -> some View {
        zIndex(layer.rawValue)
    }
}
