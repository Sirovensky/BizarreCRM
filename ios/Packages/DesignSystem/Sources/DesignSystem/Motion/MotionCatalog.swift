import SwiftUI

// §67 — Motion Catalog
// All timing tokens for the app. Callers must not define ad-hoc Animation
// values; reference these constants instead.

// MARK: - BrandMotion (extended §67 tokens)

// Note: BrandMotion is already defined in BrandMotion.swift with some values.
// The §67 spec adds the full catalog; extend the existing enum rather than
// redefining it to preserve backward compatibility.
public extension BrandMotion {

    // §67.1 — §67.2 duration + curve tokens

    /// 120ms — chip toggle.
    static let chipToggle: Animation = .interactiveSpring(response: 0.12)

    /// 160ms — FAB appear.
    static let fabAppear: Animation = .easeOut(duration: 0.16)

    /// 200ms — banner slide.
    static let bannerSlide: Animation = .easeOut(duration: 0.20)

    /// 220ms — tab switch.
    static let tabSwitch: Animation = .interactiveSpring(response: 0.22)

    /// 280ms — push navigation.
    static let pushNav: Animation = .interactiveSpring(response: 0.28)

    /// 340ms — modal sheet.
    static let modalSheet: Animation = .interactiveSpring(response: 0.34)

    /// 420ms — shared element transition.
    static let sharedElement: Animation = .interactiveSpring(response: 0.42)

    /// 600ms — pulse / confetti.
    static let pulse: Animation = .easeInOut(duration: 0.60).repeatCount(1)

    // §67.2 — curve aliases for common use-cases

    /// Default spring for most interactive elements.
    static let defaultSpring: Animation = .interactiveSpring(response: 0.30)

    /// Appearance (one-way reveal).
    static let appear: Animation = .easeOut(duration: 0.20)

    /// Dismissal (one-way hide).
    static let dismiss: Animation = .easeIn(duration: 0.16)
}
