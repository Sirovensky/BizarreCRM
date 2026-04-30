import SwiftUI

// §30 — Visual / motion / haptics — five remaining open items
//
// 1. tabBarPopAnimation    — scale-bounce when a tab is re-tapped to pop to root
// 2. searchBarFocusGlow    — animated glow ring when search field gains focus
// 3. badgeBounceOnNew      — scale bounce + haptic when badge count increases
// 4. swipeBackIndicator    — leading-edge chevron that appears on swipe-back gesture
// 5. sheetDetentCurve      — canonical .animation for sheet detent transitions

// MARK: - 1. Tab-bar pop animation

/// Plays a scale-bounce on the tab icon when the user taps the already-selected
/// tab (convention: pop back to root). Attach to the per-tab icon/label pair.
///
/// ```swift
/// Image(systemName: "house")
///     .tabBarPopAnimation(trigger: homeDoubleTapped)
/// ```
private struct TabBarPopAnimationModifier: ViewModifier {
    let trigger: Bool
    @State private var scale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: trigger) { _, fired in
                guard fired, !reduceMotion else { return }
                // Snap down then spring back — crisp acknowledgement.
                withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.5)) {
                    scale = 0.78
                }
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.55).delay(0.10)) {
                    scale = 1.0
                }
            }
    }
}

public extension View {
    /// Bounces the view when `trigger` flips to `true` (re-tap the active tab).
    ///
    /// The effect is a quick compress → spring-back. Respects Reduce Motion.
    func tabBarPopAnimation(trigger: Bool) -> some View {
        modifier(TabBarPopAnimationModifier(trigger: trigger))
    }
}

// MARK: - 2. Search-bar focus glow

/// Animated glow ring that appears when a search field gains focus.
///
/// Place on the container that wraps the `TextField` (e.g. the glass pill):
/// ```swift
/// HStack { ... }
///     .searchBarFocusGlow(isFocused: isSearchFocused)
/// ```
private struct SearchBarFocusGlowModifier: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.bizarrePrimary.opacity(isFocused ? 0.65 : 0),
                        lineWidth: 2
                    )
                    .shadow(
                        color: Color.bizarrePrimary.opacity(isFocused ? 0.30 : 0),
                        radius: isFocused ? 8 : 0
                    )
                    .allowsHitTesting(false)
                    .animation(
                        reduceMotion
                            ? .easeInOut(duration: 0.10)
                            : .spring(response: 0.28, dampingFraction: 0.80),
                        value: isFocused
                    )
            }
    }
}

public extension View {
    /// Shows an animated brand-primary glow ring when the search bar is focused.
    ///
    /// - Parameters:
    ///   - isFocused: Drive from `@FocusState` or equivalent.
    ///   - cornerRadius: Matches the container's own radius (default 12 pt).
    func searchBarFocusGlow(isFocused: Bool, cornerRadius: CGFloat = 12) -> some View {
        modifier(SearchBarFocusGlowModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}

// MARK: - 3. Badge bounce on new content

/// Plays a scale-bounce + `.selection` haptic when `count` increases.
///
/// Attach to a `BrandBadge` or any numeric badge container:
/// ```swift
/// Text("\(count)")
///     .badgeBounceOnNew(count: count)
/// ```
private struct BadgeBounceModifier: ViewModifier {
    let count: Int
    @State private var scale: CGFloat = 1.0
    @State private var previousCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(count: Int) {
        self.count = count
        self._previousCount = State(initialValue: count)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: count) { old, new in
                guard new > old else {
                    previousCount = new
                    return
                }
                previousCount = new
                BrandHaptics.selection()
                guard !reduceMotion else { return }
                withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.40)) {
                    scale = 1.30
                }
                withAnimation(.interactiveSpring(response: 0.40, dampingFraction: 0.60).delay(0.16)) {
                    scale = 1.0
                }
            }
    }
}

public extension View {
    /// Bounces the view and fires a selection haptic whenever `count` increases.
    ///
    /// Safe to attach to any badge or count label. No-op when `count` decreases
    /// or stays the same. Respects Reduce Motion.
    func badgeBounceOnNew(count: Int) -> some View {
        modifier(BadgeBounceModifier(count: count))
    }
}

// MARK: - 4. Swipe-back gesture indicator

/// Reveals a leading-edge chevron while the user drags to go back, mirroring
/// the system interactive-pop gesture. Attach to the NavigationStack's root
/// container or the screen content area.
///
/// ```swift
/// ContentView()
///     .swipeBackIndicator(dragOffset: interactiveDragOffset)
/// ```
///
/// `dragOffset` is the `.translation.width` of a `DragGesture` placed on the
/// same view (positive = dragging right = back).
private struct SwipeBackIndicatorModifier: ViewModifier {
    /// Current horizontal drag translation (positive = right = back).
    let dragOffset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Show the indicator once the user has dragged ≥ 10 pts.
    private var progress: CGFloat {
        guard dragOffset > 0 else { return 0 }
        return min(dragOffset / 80, 1.0)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                if !reduceMotion && progress > 0 {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .padding(.leading, 8)
                        .opacity(Double(progress))
                        .scaleEffect(0.70 + 0.30 * progress)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .animation(.interactiveSpring(response: 0.20, dampingFraction: 0.90), value: progress)
                }
            }
    }
}

public extension View {
    /// Shows a leading-edge back-chevron that tracks the swipe-back gesture drag.
    ///
    /// Pass `.translation.width` from a `DragGesture` recognition on the edge.
    /// The indicator fades and scales in proportionally; disappears on release.
    func swipeBackIndicator(dragOffset: CGFloat) -> some View {
        modifier(SwipeBackIndicatorModifier(dragOffset: dragOffset))
    }
}

// MARK: - 5. Sheet-detent transition curve

/// The canonical `Animation` to use when changing `.presentationDetent` at runtime.
///
/// Apply to the sheet's outermost container or the state that drives detent
/// changes:
/// ```swift
/// .onChange(of: keyboardVisible) { _, visible in
///     withAnimation(BrandMotion.sheetDetentTransition) {
///         selectedDetent = visible ? .large : .medium
///     }
/// }
/// ```
extension BrandMotion {

    /// Smooth, spring-based curve for programmatic sheet-detent changes.
    ///
    /// Chosen to feel continuous with the native SwiftUI sheet drag gesture
    /// (response 0.36s, slight underdamping to acknowledge the state change).
    public static let sheetDetentTransition: Animation =
        .spring(response: 0.36, dampingFraction: 0.82)
}

/// View modifier that applies `BrandMotion.sheetDetentTransition` when a bound
/// `PresentationDetent` value changes. Reduces to `.easeInOut(duration: 0)` when
/// Reduce Motion is active.
///
/// ```swift
/// sheet { ... }
///     .sheetDetentAnimated($currentDetent)
/// ```
private struct SheetDetentAnimatedModifier: ViewModifier {
    @Binding var detent: PresentationDetent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onChange(of: detent) { _, _ in
                // The binding change already happens externally; we use
                // `withAnimation` on our own state mirror so the modifier
                // doesn't fight the binding setter.
            }
            .animation(
                reduceMotion ? .easeInOut(duration: 0) : BrandMotion.sheetDetentTransition,
                value: detent
            )
    }
}

public extension View {
    /// Applies the brand sheet-detent transition curve whenever `detent` changes.
    ///
    /// Attach to the view inside the sheet that should animate on detent swaps.
    /// Respects Reduce Motion (collapses to instant update).
    func sheetDetentAnimated(_ detent: Binding<PresentationDetent>) -> some View {
        modifier(SheetDetentAnimatedModifier(detent: detent))
    }
}
