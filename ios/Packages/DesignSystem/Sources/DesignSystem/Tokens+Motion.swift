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

    // MARK: §30.5 — Named spring (§30.6 spec)

    /// Canonical brand spring: response 0.3s, damping 0.75.
    /// Specified in §30.6 as the shared interactive-spring baseline.
    /// Reduce Motion alt: nil (instant) via ReduceMotionFallback.
    static let brandSpring: Animation = .interactiveSpring(response: 0.30, dampingFraction: 0.75)

    // MARK: §30.6 — Page-transition spring

    /// Spring for full-page push/pop transitions (NavigationStack column or ZStack pager).
    /// response 0.36 / damping 0.82 — slightly heavier than brandSpring to feel
    /// anchored when content fills the whole screen.
    /// Paired transition: `BrandTransition.page(reduceMotion:)`.
    /// Reduce Motion alt: nil (instant) via ReduceMotionFallback.
    static let pageTransition: Animation = .interactiveSpring(response: 0.36, dampingFraction: 0.82)

    // MARK: §30.7 — Progress-arc animation

    /// Easing used when animating a circular progress arc (e.g., payment ring,
    /// CoreNFC progress, hold-to-confirm ring).
    /// 0.55s ease-in-out keeps the arc feel smooth but not sluggish.
    /// Reduce Motion alt: instant via ReduceMotionFallback.animation.
    static let progressArc: Animation = .easeInOut(duration: 0.55)

    // MARK: §30.8 — FAB scale-in

    /// Scale-in spring for the floating action button appearance.
    /// response 0.26 / damping 0.68 — snappier than the base spring so the FAB
    /// "pops" into place rather than drifting.
    /// Reduce Motion alt: nil (instant) via ReduceMotionFallback.
    static let fabScaleIn: Animation = .interactiveSpring(response: 0.26, dampingFraction: 0.68)

    // MARK: §29.8 — Responsive interactive spring (perf budget)

    /// `.interactiveSpring` tuned for "responsiveness over polish" — used on
    /// gesture-driven interactions (drag tracks, slider thumbs, swipe-row
    /// reveals) where the UI must follow the finger with no perceptible lag.
    ///
    /// Per §29.8 Animations: prefer `.interactiveSpring` for responsiveness.
    /// Lower response (0.18) than `brandSpring` so the spring resolves quickly
    /// when the user releases — no overshoot lingering past the touch.
    ///
    /// Reduce Motion alt: nil (instant) via ReduceMotionFallback.
    static let responsive: Animation = .interactiveSpring(response: 0.18, dampingFraction: 0.86)
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

    /// Pre-resolved token for the canonical brand spring, honouring Reduce Motion.
    static func brandSpring(reduced: Bool) -> Animation? {
        animation(BrandMotion.brandSpring, reduced: reduced)
    }

    /// Pre-resolved token for page-transition spring, honouring Reduce Motion.
    static func pageTransition(reduced: Bool) -> Animation? {
        animation(BrandMotion.pageTransition, reduced: reduced)
    }

    /// Pre-resolved token for progress-arc animation, honouring Reduce Motion.
    static func progressArc(reduced: Bool) -> Animation? {
        animation(BrandMotion.progressArc, reduced: reduced)
    }

    /// Pre-resolved token for FAB scale-in spring, honouring Reduce Motion.
    static func fabScaleIn(reduced: Bool) -> Animation? {
        animation(BrandMotion.fabScaleIn, reduced: reduced)
    }

    /// Pre-resolved token for the §29.8 responsive interactive spring,
    /// honouring Reduce Motion. Returns nil when reduced so gesture-tracking
    /// updates apply instantly.
    static func responsive(reduced: Bool) -> Animation? {
        animation(BrandMotion.responsive, reduced: reduced)
    }
}
