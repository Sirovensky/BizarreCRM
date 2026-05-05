#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - §2.13 Session timeout countdown ring

/// A circular progress ring that shows how much time remains in the warning
/// window. Displayed inside the "Still there?" overlay during the final 60 s.
///
/// - Animates smoothly as `secondsRemaining` decreases.
/// - Reduces to a static ring on Reduce Motion.
/// - Accessible: reports remaining time as a `ProgressView`-style label.
public struct SessionTimeoutCountdownRing: View {

    /// Seconds remaining. Clamps to [0, warningWindowSeconds].
    public let secondsRemaining: TimeInterval

    /// Total warning window in seconds (default 60).
    public var warningWindowSeconds: TimeInterval = 60

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(secondsRemaining: TimeInterval, warningWindowSeconds: TimeInterval = 60) {
        self.secondsRemaining = secondsRemaining
        self.warningWindowSeconds = warningWindowSeconds
    }

    private var fraction: Double {
        guard warningWindowSeconds > 0 else { return 0 }
        return max(0, min(1, secondsRemaining / warningWindowSeconds))
    }

    private var ringColor: Color {
        if fraction > 0.5 { return Color.bizarreWarning }
        if fraction > 0.25 { return Color.bizarreOrange }
        return Color.bizarreError
    }

    private var displaySeconds: Int {
        max(0, Int(secondsRemaining.rounded()))
    }

    public var body: some View {
        ZStack {
            // Track ring
            Circle()
                .stroke(Color.bizarreOnSurface.opacity(0.15), lineWidth: 4)

            // Progress arc — clockwise drain as time runs out
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? .none : .linear(duration: 1),
                    value: fraction
                )

            // Countdown label
            Text("\(displaySeconds)")
                .font(.brandMono(size: 14).bold())
                .foregroundStyle(ringColor)
                .contentTransition(.numericText())
                .animation(reduceMotion ? .none : .linear(duration: 1), value: displaySeconds)
        }
        .frame(width: 52, height: 52)
        .accessibilityLabel("Session expires in \(displaySeconds) seconds")
        .accessibilityValue("\(Int(fraction * 100))%")
        .accessibilityIdentifier("auth.sessionCountdownRing")
    }
}

// MARK: - Updated SessionTimeoutWarningBanner with countdown ring

/// Extended version of the warning banner that includes the countdown ring.
/// Replaces the plain text-only banner when the ring is needed.
public struct SessionTimeoutWarningBannerWithRing: View {

    public let secondsRemaining: TimeInterval
    public let onExtend: () async -> Void
    public let onSignOut: () async -> Void

    private var isVisible: Bool { secondsRemaining > 0 && secondsRemaining <= 60 }

    public init(
        secondsRemaining: TimeInterval,
        onExtend: @escaping () async -> Void,
        onSignOut: @escaping () async -> Void
    ) {
        self.secondsRemaining = secondsRemaining
        self.onExtend = onExtend
        self.onSignOut = onSignOut
    }

    public var body: some View {
        if isVisible {
            banner
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        }
    }

    private var banner: some View {
        HStack(spacing: BrandSpacing.md) {
            // Countdown ring
            SessionTimeoutCountdownRing(secondsRemaining: secondsRemaining)
                .frame(width: 52, height: 52)

            // Text column
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Still there?")
                    .font(.brandLabelLarge().bold())
                    .foregroundStyle(Color.bizarreOnSurface)

                Text("Session expires in \(max(0, Int(secondsRemaining.rounded()))) seconds.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer()

            // Action buttons
            VStack(spacing: BrandSpacing.xs) {
                Button {
                    Task { await onExtend() }
                } label: {
                    Text("Stay")
                        .font(.brandLabelSmall().bold())
                        .foregroundStyle(Color.bizarreOrange)
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, BrandSpacing.xxs)
                        .brandGlass(.regular, in: Capsule(), interactive: true)
                }
                .accessibilityLabel("Extend session")

                Button {
                    Task { await onSignOut() }
                } label: {
                    Text("Sign out")
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Sign out now")
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(
            .regular,
            in: RoundedRectangle(cornerRadius: 14),
            tint: Color.bizarreWarning.opacity(0.10)
        )
        .padding(.horizontal, BrandSpacing.base)
        .padding(.top, BrandSpacing.xs)
    }
}

#endif
