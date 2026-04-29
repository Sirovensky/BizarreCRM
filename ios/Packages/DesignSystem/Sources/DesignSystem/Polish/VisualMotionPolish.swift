import SwiftUI

// §30 — Visual / motion / haptics pass
// Five modifiers + one component shipped in this file:
//   1. drawerOpenHaptic(isOpen:)      — fires drawerOpen haptic on open
//   2. successCheckmark(isActive:)    — draw-on checkmark for generic success
//   3. errorShake(trigger:)           — horizontal shake + .error haptic
//   4. loadingShimmer(isLoading:)     — inline shimmer overlay (no redaction)
//   5. ScrollToTopButton              — fade-in FAB; ScrollToTopFadeModifier

// MARK: - 1. Drawer open haptic

/// Fires a medium-heavy haptic when a drawer (side panel / bottom sheet) opens.
///
/// Attach to the outermost container that moves during the open transition:
/// ```swift
/// SideDrawerView(isOpen: $isOpen)
///     .drawerOpenHaptic(isOpen: isOpen)
/// ```
/// The haptic fires on the leading edge of the `isOpen = true` state change.
/// No haptic on close — matches native `.sheet` behaviour.
private struct DrawerOpenHapticModifier: ViewModifier {
    let isOpen: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isOpen) { _, opened in
                guard opened else { return }
                Task { await HapticCatalog.play(.drawerOpen) }
            }
    }
}

// MARK: - 2. Success checkmark animation

/// Animates a circle-draw checkmark centered over any view on success.
///
/// Distinct from `paymentApprovedCheck` (POS-specific). Use this for generic
/// form saves, sync completions, etc.
/// ```swift
/// SaveButton()
///     .successCheckmark(isActive: didSave)
/// ```
private struct SuccessCheckmarkModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GenericCheckmarkView(reduceMotion: reduceMotion)
                        .allowsHitTesting(false)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale))
                        .accessibilityLabel("Success")
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .onChange(of: isActive) { _, active in
                guard active else { return }
                Task { await HapticCatalog.play(.successConfirm) }
            }
    }
}

private struct GenericCheckmarkView: View {
    let reduceMotion: Bool
    @State private var ringProgress: CGFloat = 0
    @State private var checkOpacity: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    Color(red: 0.20, green: 0.77, blue: 0.49),  // --success token
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(-90))

            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.20, green: 0.77, blue: 0.49))
                .opacity(checkOpacity)
        }
        .onAppear {
            if reduceMotion {
                ringProgress = 1
                checkOpacity = 1
            } else {
                withAnimation(.easeOut(duration: 0.40)) { ringProgress = 1 }
                withAnimation(.easeIn(duration: 0.15).delay(0.35)) { checkOpacity = 1 }
            }
        }
    }
}

// MARK: - 3. Error shake

/// Applies a horizontal shake animation when `trigger` is `true`, then fires
/// `.errorShake` haptic. Caller must reset `trigger` to `false` after the
/// animation completes (e.g. via `.onAnimationComplete` or a 0.5s DispatchQueue).
///
/// ```swift
/// @State private var shakeError = false
///
/// TextField("Email", text: $email)
///     .errorShake(trigger: shakeError)
///     .onChange(of: shakeError) { _, v in
///         guard v else { return }
///         DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shakeError = false }
///     }
/// ```
private struct ErrorShakeModifier: ViewModifier {
    let trigger: Bool
    @State private var shakeOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: trigger) { _, firing in
                guard firing else { return }
                Task { await HapticCatalog.play(.errorShake) }
                guard !reduceMotion else { return }
                shake()
            }
    }

    private func shake() {
        let offsets: [CGFloat] = [8, -8, 6, -6, 4, -4, 0]
        var delay = 0.0
        for offset in offsets {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.06)) {
                    shakeOffset = offset
                }
            }
            delay += 0.06
        }
    }
}

// MARK: - 4. Loading shimmer (non-redacting)

/// Overlays an animated shimmer gradient on content that is refreshing.
/// Unlike `skeletonShimmer()`, this variant does NOT apply `.redacted` —
/// it overlays the real content so the user can still see stale data while
/// a background refresh is in flight.
///
/// ```swift
/// TicketList(tickets: cached)
///     .loadingShimmer(isLoading: viewModel.isRefreshing)
/// ```
private struct LoadingShimmerModifier: ViewModifier {
    let isLoading: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isLoading && !reduceMotion {
                    RefreshShimmerOverlay()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isLoading)
    }
}

private struct RefreshShimmerOverlay: View {
    @State private var phase: CGFloat = -1.0

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.18), location: 0.5),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: w * 2)
            .offset(x: phase * w)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
        }
    }
}

// MARK: - 5. Scroll-to-top fade button

/// A "scroll to top" FAB that fades in once the user scrolls past a threshold.
///
/// Wrap a `ScrollView` + inner content using `ScrollViewReader`, then pass a
/// `scrolledPastThreshold` binding driven by a `GeometryReader` proxy or
/// preference key. The button scrolls to the anchor `id` you supply.
///
/// ```swift
/// ScrollView {
///     ScrollViewReader { proxy in
///         Color.clear.frame(height: 1).id("top")
///         content
///             .overlay(alignment: .bottomTrailing) {
///                 ScrollToTopButton(
///                     isVisible: scrolledFar,
///                     action: { proxy.scrollTo("top", anchor: .top) }
///                 )
///                 .padding(.trailing, DesignTokens.Spacing.lg)
///                 .padding(.bottom, DesignTokens.Spacing.xl)
///             }
///     }
/// }
/// ```
public struct ScrollToTopButton: View {
    public let isVisible: Bool
    public let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isVisible: Bool, action: @escaping () -> Void) {
        self.isVisible = isVisible
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
                .shadow(radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scroll to top")
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible || reduceMotion ? 1 : 0.7)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.30, dampingFraction: 0.75),
            value: isVisible
        )
    }
}

/// Convenience modifier: tracks scroll offset and provides an `isScrolledFar` binding.
///
/// Attach to the content inside a `ScrollView`. The modifier reads a
/// `GeometryReader` preference key to detect when the top anchor moves more than
/// `threshold` points off-screen.
///
/// ```swift
/// ScrollView {
///     content
///         .scrollToTopFade(threshold: 300) { isFar in
///             scrolledFar = isFar
///         }
/// }
/// ```
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollToTopFadeModifier: ViewModifier {
    let threshold: CGFloat
    let onChange: (Bool) -> Void
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: ScrollOffsetKey.self,
                            value: geo.frame(in: .named("scrollCoordSpace")).minY
                        )
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { y in
                let scrolledFar = y < -threshold
                if scrolledFar != (offset < -threshold) {
                    onChange(scrolledFar)
                }
                offset = y
            }
    }
}

// MARK: - Public View extensions

public extension View {

    /// Fires a medium-heavy haptic when `isOpen` transitions to `true`.
    func drawerOpenHaptic(isOpen: Bool) -> some View {
        modifier(DrawerOpenHapticModifier(isOpen: isOpen))
    }

    /// Overlays an animated circle-draw checkmark on success. Also fires
    /// `.successConfirm` haptic. Caller controls `isActive`.
    func successCheckmark(isActive: Bool) -> some View {
        modifier(SuccessCheckmarkModifier(isActive: isActive))
    }

    /// Shakes the view horizontally and fires `.errorShake` haptic.
    /// Caller is responsible for resetting `trigger` to `false`.
    func errorShake(trigger: Bool) -> some View {
        modifier(ErrorShakeModifier(trigger: trigger))
    }

    /// Overlays a translucent shimmer sweep during a background refresh.
    /// Does not redact content — use `skeletonShimmer()` for initial loads.
    func loadingShimmer(isLoading: Bool) -> some View {
        modifier(LoadingShimmerModifier(isLoading: isLoading))
    }

    /// Reports whether the enclosing `ScrollView` has scrolled past `threshold`
    /// points. Coordinate space must be named `"scrollCoordSpace"` on the
    /// `ScrollView`.
    ///
    /// ```swift
    /// ScrollView {
    ///     content
    ///         .scrollToTopFade(threshold: 300) { scrolledFar = $0 }
    /// }
    /// .coordinateSpace(name: "scrollCoordSpace")
    /// ```
    func scrollToTopFade(threshold: CGFloat = 300, onChange: @escaping (Bool) -> Void) -> some View {
        modifier(ScrollToTopFadeModifier(threshold: threshold, onChange: onChange))
    }
}
