import SwiftUI
import DesignSystem

// MARK: - TypingIndicatorView
//
// §12.2 Typing indicator — shows animated "…" bubble when the remote party
// is composing a reply. Driven by a WS `sms:typing` event (server-conditional).
//
// Animation: three dots bounce in sequence (staggered opacity + offset).
// Respects Reduce Motion: dots switch to a static "…" label.
//
// Usage:
//   TypingIndicatorView(isVisible: vm.isRemoteTyping)

public struct TypingIndicatorView: View {
    public let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    public init(isVisible: Bool) {
        self.isVisible = isVisible
    }

    public var body: some View {
        if isVisible {
            HStack(alignment: .bottom, spacing: 0) {
                bubble
                Spacer(minLength: 40)
            }
            .accessibilityLabel("Contact is typing")
            .accessibilityAddTraits(.updatesFrequently)
            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottomLeading)))
        }
    }

    @ViewBuilder
    private var bubble: some View {
        HStack(spacing: 4) {
            if reduceMotion {
                Text("…")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.bizarreOnSurfaceMuted)
                        .frame(width: 7, height: 7)
                        .offset(y: dotOffset(for: i))
                }
                .onAppear { startAnimation() }
                .onDisappear { phase = 0 }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func dotOffset(for index: Int) -> CGFloat {
        let delay = Double(index) * (1.0 / 3.0)
        let adjusted = (phase - delay).truncatingRemainder(dividingBy: 1.0)
        let norm = adjusted < 0 ? adjusted + 1.0 : adjusted
        // Sine wave: max upward offset -5pt at peak
        return -5 * sin(norm * .pi)
    }

    private func startAnimation() {
        guard !reduceMotion else { return }
        let animation = Animation.linear(duration: 1.2).repeatForever(autoreverses: false)
        withAnimation(animation) { phase = 1.0 }
    }
}

// MARK: - SmsThreadViewModel extension for typing state

public extension SmsThreadViewModel {
    // Stored via associated object pattern — Swift 6 @Observable doesn't allow
    // stored properties in extensions. Declare on the class; we extend here for
    // the WS hook only.

    /// Starts listening for `sms:typing` WS events and updates `isRemoteTyping`.
    /// The typing flag auto-clears after 5 seconds without a new event.
    func handleTypingEvent() {
        isRemoteTyping = true
        typingClearTask?.cancel()
        typingClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
            self?.isRemoteTyping = false
        }
    }
}
