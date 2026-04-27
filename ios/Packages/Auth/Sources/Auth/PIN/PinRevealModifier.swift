import SwiftUI
import DesignSystem

// MARK: - §2.5 PIN "Show" tap-hold reveal

/// A view modifier that reveals a masked PIN string briefly while the user
/// long-presses a "Show" button.
///
/// Security constraints:
/// - `privacySensitive()` on the container ensures the system masks the view
///   in the app switcher and when a screenshot is taken.
/// - Reveal duration is bounded by `revealDuration` (default 2 s); after that
///   the PIN re-masks regardless of whether the press is held.
/// - Tapping once shows the PIN; releasing or after the timeout it re-masks.
///
/// Usage:
/// ```swift
/// Text("••••")
///     .pinReveal(pin: "1234")
/// ```
public struct PinRevealModifier: ViewModifier {

    public let pin: String
    public var revealDuration: TimeInterval = 2.0

    @State private var isRevealed = false
    @State private var revealTask: Task<Void, Never>?

    public func body(content: Content) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Group {
                if isRevealed {
                    Text(pin)
                        .font(.brandMono(size: 16).bold())
                        .foregroundStyle(Color.bizarreOnSurface)
                        .transition(.opacity)
                } else {
                    Text(String(repeating: "•", count: min(pin.count, 6)))
                        .font(.brandMono(size: 16))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isRevealed)

            Button {
                // No-op — long-press handled below
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.1)
                    .onEnded { _ in reveal() }
            )
            .accessibilityLabel(isRevealed ? "Hide PIN" : "Show PIN (hold)")
            .accessibilityHint("Tap and hold to reveal the PIN briefly")
        }
        .privacySensitive()
    }

    // MARK: - Private

    private func reveal() {
        revealTask?.cancel()
        isRevealed = true
        revealTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(revealDuration * 1_000_000_000))
            if !Task.isCancelled {
                isRevealed = false
            }
        }
    }
}

public extension View {
    /// Adds a tap-hold "Show" button that reveals `pin` for `revealDuration` seconds.
    func pinReveal(pin: String, revealDuration: TimeInterval = 2.0) -> some View {
        modifier(PinRevealModifier(pin: pin, revealDuration: revealDuration))
    }
}
