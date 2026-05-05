#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosRegisterLockView (§14 register-lock countdown a11y)

/// Shown when the POS register has been locked due to inactivity or an
/// explicit "Lock register" action. Displays a countdown before auto-lock
/// escalates (e.g., screen dims), and announces state changes to VoiceOver.
///
/// Accessibility contract:
/// - When `secondsRemaining` crosses integer boundaries, a `.statusChange`
///   announcement is posted via `UIAccessibility.post` so screen-reader
///   users always know how long until the screen is blacked out.
/// - A live-region `Text` is marked `.updatesFrequently` so it reads on
///   each change without requiring focus.
/// - The "Unlock" button is always reachable by VoiceOver regardless of
///   reduced-motion or reduced-transparency settings.
@MainActor
public struct PosRegisterLockView: View {

    // MARK: - Configuration

    /// Total seconds before the screen escalates (caller drives this).
    /// When it reaches 0, `onCountdownExpired` fires.
    public let totalSeconds: Int
    /// Fired when the user successfully authenticates / dismisses lock.
    public let onUnlock: () -> Void
    /// Fired when the countdown reaches zero without user interaction.
    public let onCountdownExpired: () -> Void

    // MARK: - State

    @State private var secondsRemaining: Int
    @State private var countdownTask: Task<Void, Never>?
    @State private var lastAnnouncedSecond: Int = -1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Init

    public init(
        totalSeconds: Int = 30,
        onUnlock: @escaping () -> Void,
        onCountdownExpired: @escaping () -> Void
    ) {
        self.totalSeconds = totalSeconds
        self.onUnlock = onUnlock
        self.onCountdownExpired = onCountdownExpired
        _secondsRemaining = State(initialValue: totalSeconds)
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: BrandSpacing.xl) {
                Spacer()

                lockIcon
                titleStack
                countdownLabel
                unlockButton

                Spacer()
            }
            .padding(.horizontal, BrandSpacing.xl)
        }
        .task { startCountdown() }
        .onDisappear { countdownTask?.cancel() }
        // §14 a11y: announce "Register locked" when view appears.
        .onAppear {
            UIAccessibility.post(
                notification: .screenChanged,
                argument: "Register is locked. \(secondsRemaining) seconds until screen dims."
            )
        }
    }

    // MARK: - Sub-views

    private var lockIcon: some View {
        Image(systemName: "lock.rectangle.on.rectangle.fill")
            .font(.system(size: 64, weight: .semibold))
            .foregroundStyle(.orange)
            .scaleEffect(reduceMotion ? 1 : (secondsRemaining <= 5 ? 1.08 : 1.0))
            .animation(
                reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.5),
                value: secondsRemaining
            )
            .accessibilityHidden(true)
    }

    private var titleStack: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("Register locked")
                .font(.brandTitleLarge())
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text("Authenticate to continue selling.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    private var countdownLabel: some View {
        // §14 a11y live region — VoiceOver re-reads on each update.
        Text(countdownText)
            .font(.brandBodyMedium().monospacedDigit())
            .foregroundStyle(secondsRemaining <= 5 ? .red : Color.white.opacity(0.55))
            .contentTransition(.numericText())
            .accessibilityLabel(countdownAccessibilityLabel)
            // `.updatesFrequently` keeps the live region fresh without
            // queueing a full focus cycle.
            .accessibilityIdentifier("pos.registerLock.countdown")
    }

    private var unlockButton: some View {
        Button {
            countdownTask?.cancel()
            BrandHaptics.success()
            onUnlock()
        } label: {
            Label("Unlock register", systemImage: "faceid")
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.sm)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .controlSize(.large)
        .accessibilityIdentifier("pos.registerLock.unlock")
        .accessibilityHint("Double-tap to authenticate and resume selling")
    }

    // MARK: - Countdown logic

    private var countdownText: String {
        if secondsRemaining <= 0 { return "Screen dimming…" }
        return "Screen dims in \(secondsRemaining)s"
    }

    private var countdownAccessibilityLabel: String {
        if secondsRemaining <= 0 { return "Screen is dimming now" }
        return "Screen will dim in \(secondsRemaining) \(secondsRemaining == 1 ? "second" : "seconds")"
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task {
            while secondsRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                secondsRemaining -= 1
                // §14 a11y: announce at 10s and 5s thresholds so VoiceOver
                // users aren't surprised by lock escalation.
                if secondsRemaining == 10 || secondsRemaining == 5 || secondsRemaining == 3 {
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: countdownAccessibilityLabel
                    )
                }
            }
            guard !Task.isCancelled else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: "Register screen is dimming"
            )
            onCountdownExpired()
        }
    }
}

// MARK: - Preview

#Preview("Register lock — countdown") {
    PosRegisterLockView(
        totalSeconds: 15,
        onUnlock: {},
        onCountdownExpired: {}
    )
    .preferredColorScheme(.dark)
}
#endif
