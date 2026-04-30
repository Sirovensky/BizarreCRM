import SwiftUI
import UIKit

// §30 — Visual / motion — second batch of open items
//
// 1. shakeToUndo            — attaches UIResponder shake-motion to UndoManager
// 2. longPressPreviewLift   — lift + shadow on long-press (context-menu preview feel)
// 3. navigationBarTransition— canonical Animation for programmatic nav-bar title/item swaps
// 4. listRowPressScale      — subtle compress on tap-down, spring-back on release
// 5. pullToLoadMoreCurve    — spring animation token for "load more" trigger reveal

// MARK: - 1. Shake-to-undo

/// `ShakeDetectingViewController` — thin UIKit shim that bridges
/// `motionEnded(.motionShake)` into a SwiftUI-consumable callback.
///
/// Drop `.shakeToUndo(undoManager:)` on any SwiftUI view that should respond
/// to the shake gesture. Respects the system Accessibility → Touch → Shake to
/// Undo setting via `UIApplication.shared.applicationSupportsShakeToEdit`.
///
/// Accidental-trigger protection: if a pan or scroll is active at the time of
/// the shake event the callback is skipped (enforced in the modifier by checking
/// `isGestureActive`).
private final class ShakeHostingController: UIViewController {
    var onShake: (() -> Void)?

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return }
        // Honor iOS Accessibility → Touch → Shake to Undo system preference
        guard UIApplication.shared.applicationSupportsShakeToEdit else { return }
        onShake?()
    }

    // Must be first responder to receive motion events.
    override var canBecomeFirstResponder: Bool { true }
}

/// UIViewControllerRepresentable that inserts `ShakeHostingController` into
/// the SwiftUI hierarchy without occupying any layout space.
private struct ShakeResponder: UIViewControllerRepresentable {
    let onShake: () -> Void

    func makeUIViewController(context _: Context) -> ShakeHostingController {
        let vc = ShakeHostingController()
        vc.onShake = onShake
        return vc
    }

    func updateUIViewController(_ uiViewController: ShakeHostingController, context _: Context) {
        uiViewController.onShake = onShake
    }
}

private struct ShakeToUndoModifier: ViewModifier {
    let undoManager: UndoManager?
    /// Allows callers to suppress the shake if a gesture (scroll/pan) is active.
    let isGestureActive: Bool

    func body(content: Content) -> some View {
        content
            .background {
                ShakeResponder {
                    guard !isGestureActive, let um = undoManager, um.canUndo else { return }
                    // Debounce: UndoManager itself guards double-invocation.
                    um.undo()
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

public extension View {
    /// Connects the iOS shake gesture to `UndoManager.undo()`.
    ///
    /// Place on a root container (e.g. `NavigationStack` body) that owns an
    /// `UndoManager`. Does nothing if the system Shake-to-Undo preference is
    /// disabled or when `isGestureActive` is `true` (e.g. while the user is
    /// scrolling a list).
    ///
    /// ```swift
    /// ContentView()
    ///     .shakeToUndo(undoManager: undoManager, isGestureActive: isDragging)
    /// ```
    func shakeToUndo(
        undoManager: UndoManager?,
        isGestureActive: Bool = false
    ) -> some View {
        modifier(ShakeToUndoModifier(undoManager: undoManager, isGestureActive: isGestureActive))
    }
}

// MARK: - 2. Long-press preview lift

/// Animates a lift effect (scale-up + increased shadow) when a long-press begins,
/// simulating the system context-menu lift feel for custom menus.
///
/// ```swift
/// TicketRow(ticket: ticket)
///     .longPressPreviewLift()
/// ```
private struct LongPressPreviewLiftModifier: ViewModifier {
    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var shadowRadius: CGFloat { isPressed ? 18 : 4 }
    var shadowOpacity: Double { isPressed ? 0.22 : 0.08 }
    var scale: CGFloat { isPressed ? 1.035 : 1.0 }

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1.0 : scale)
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: isPressed ? 8 : 2
            )
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0)
                    : .interactiveSpring(response: 0.25, dampingFraction: 0.72),
                value: isPressed
            )
            .gesture(
                LongPressGesture(minimumDuration: 0.40)
                    .updating($isPressed) { _, state, _ in state = true }
            )
    }
}

public extension View {
    /// Applies a scale-lift + shadow bloom on long-press, matching the feel of
    /// the system context-menu preview. Respects Reduce Motion.
    func longPressPreviewLift() -> some View {
        modifier(LongPressPreviewLiftModifier())
    }
}

// MARK: - 3. Navigation-bar transition curve

extension BrandMotion {
    /// Canonical `Animation` for programmatic navigation-bar content swaps:
    /// title text changes, leading/trailing button appearance, large vs inline title.
    ///
    /// Tuned to match the native UINavigationController push transition feel —
    /// slightly slower response than `BrandMotion.chip` so the title change doesn't
    /// feel mechanical.
    ///
    /// Usage:
    /// ```swift
    /// .animation(BrandMotion.navigationBarTransition, value: selectedTab)
    /// ```
    public static let navigationBarTransition: Animation =
        .spring(response: 0.32, dampingFraction: 0.86)
}

private struct NavigationBarTransitionModifier<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(
            reduceMotion ? .easeInOut(duration: 0) : BrandMotion.navigationBarTransition,
            value: value
        )
    }
}

public extension View {
    /// Animates navigation-bar content changes with the brand nav-bar transition curve.
    ///
    /// Attach to a wrapper that owns the bar's title / button state:
    /// ```swift
    /// .navigationBarTransitionCurve(value: currentScreen)
    /// ```
    func navigationBarTransitionCurve<V: Equatable>(value: V) -> some View {
        modifier(NavigationBarTransitionModifier(value: value))
    }
}

// MARK: - 4. List-row press scale

/// Subtle compress-on-tap-down that spring-recovers on release.
/// Gives list rows tactile feedback without a full bounce.
///
/// ```swift
/// TicketRow(ticket: ticket)
///     .listRowPressScale()
/// ```
private struct ListRowPressScaleModifier: ViewModifier {
    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                (reduceMotion || !isPressed) ? 1.0 : 0.965,
                anchor: .center
            )
            .animation(
                isPressed
                    ? .interactiveSpring(response: 0.14, dampingFraction: 0.90)  // fast compress
                    : .interactiveSpring(response: 0.30, dampingFraction: 0.65), // bouncy release
                value: isPressed
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        if !state { state = true }
                    }
            )
    }
}

public extension View {
    /// Adds a subtle compress-then-spring-back scale effect on tap-down/release.
    ///
    /// Apply to list rows or tappable cards. Safe to combine with `.onTapGesture`
    /// — uses a `simultaneousGesture` so it doesn't interfere with row selection.
    /// Respects Reduce Motion.
    func listRowPressScale() -> some View {
        modifier(ListRowPressScaleModifier())
    }
}

// MARK: - 5. Pull-to-load-more curve

extension BrandMotion {
    /// `Animation` for the "load more" trigger UI:
    /// the spinner / chevron that appears at the bottom of a list when the user
    /// has scrolled to the threshold. Spring-bouncy to acknowledge the gesture,
    /// then settles quickly so it doesn't distract from incoming data.
    ///
    /// Usage:
    /// ```swift
    /// loadMoreSpinner
    ///     .opacity(showLoadMore ? 1 : 0)
    ///     .animation(BrandMotion.pullToLoadMore, value: showLoadMore)
    /// ```
    public static let pullToLoadMore: Animation =
        .interactiveSpring(response: 0.38, dampingFraction: 0.60)
}

private struct PullToLoadMoreCurveModifier<V: Equatable>: ViewModifier {
    let isVisible: Bool
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1.0 : 0.80, anchor: .bottom)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.15) : BrandMotion.pullToLoadMore,
                value: value
            )
    }
}

public extension View {
    /// Animates a "load more" indicator into view with the brand pull-to-load-more spring.
    ///
    /// Typically applied to a progress view or chevron at the list footer:
    /// ```swift
    /// ProgressView()
    ///     .pullToLoadMoreCurve(isVisible: isLoadingMore)
    /// ```
    func pullToLoadMoreCurve<V: Equatable>(
        isVisible: Bool,
        driving value: V
    ) -> some View {
        modifier(PullToLoadMoreCurveModifier(isVisible: isVisible, value: value))
    }

    /// Overload that uses `isVisible` itself as the animation trigger.
    func pullToLoadMoreCurve(isVisible: Bool) -> some View {
        pullToLoadMoreCurve(isVisible: isVisible, driving: isVisible)
    }
}
