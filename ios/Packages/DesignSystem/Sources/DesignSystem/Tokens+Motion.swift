import SwiftUI

// §30 — Tokens+Motion
// New motion tokens required by §30 polish pass.
// APPEND-ONLY to BrandMotion — never rename or remove existing tokens.
// Reduce Motion alternatives are provided via ReduceMotionFallback (§67.3).

// MARK: - BrandMotion §30 additions

public extension BrandMotion {

    // MARK: §30.1 — Sheet presentation

    /// Used for sheet / modal enter transitions.
    /// Reduce Motion alt: instant (.nil via ReduceMotionFallback.animation).
    static let sheetPresent: Animation = .interactiveSpring(response: 0.38, dampingFraction: 0.86)

    // MARK: §30.2 — Button tap

    /// Micro-spring for button press scale feedback.
    /// Reduce Motion alt: no animation (ReduceMotionFallback returns nil).
    static let buttonTap: Animation = .spring(response: 0.22, dampingFraction: 0.80)

    // MARK: §30.3 — List-item appear

    /// Stagger animation for list row entrance (combine with `.delay`).
    /// Reduce Motion alt: fade (.easeInOut 0.15 via ReduceMotionFallback.fadeOrFull).
    static let listItemAppear: Animation = .easeOut(duration: 0.28)

    // MARK: §30.4 — Card hover (iPad .hoverEffect companion)

    /// Scale/shadow animation for card lift on hover (iPad pointer).
    /// Fire on `.onHover` with `isHovered` flag.
    /// Reduce Motion alt: no animation.
    static let cardHover: Animation = .interactiveSpring(response: 0.20, dampingFraction: 0.90)
}

// MARK: - ReduceMotionFallback §30 convenience

public extension ReduceMotionFallback {

    /// Pre-resolved token for sheet presentation, honouring Reduce Motion.
    ///
    /// Example:
    /// ```swift
    /// @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// withAnimation(ReduceMotionFallback.sheetPresent(reduced: reduceMotion)) { isShowing = true }
    /// ```
    static func sheetPresent(reduced: Bool) -> Animation? {
        animation(BrandMotion.sheetPresent, reduced: reduced)
    }

    /// Pre-resolved token for button tap, honouring Reduce Motion.
    static func buttonTap(reduced: Bool) -> Animation? {
        animation(BrandMotion.buttonTap, reduced: reduced)
    }

    /// Pre-resolved token for list item appear. Uses fade fallback so items
    /// still reveal themselves (just without the slide).
    static func listItemAppear(reduced: Bool) -> Animation {
        fadeOrFull(BrandMotion.listItemAppear, reduced: reduced)
    }

    /// Pre-resolved token for card hover. Returns nil when reduced so the
    /// hover state change is instant (pointer users see immediate response).
    static func cardHover(reduced: Bool) -> Animation? {
        animation(BrandMotion.cardHover, reduced: reduced)
    }
}
