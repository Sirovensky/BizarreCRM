import SwiftUI

// MARK: - BurnInNudgeModifier

/// §55 Screen-burn prevention: applies a subtle 1pt translation every 30s
/// on static elements. Disabled when Reduce Motion is on.
public struct BurnInNudgeModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let intervalSeconds: TimeInterval
    @State private var offset: CGSize = .zero
    @State private var timer: Timer?

    /// Visible range of shift (±0.5 pt by default)
    private let amplitude: CGFloat

    public init(intervalSeconds: TimeInterval = 30, amplitude: CGFloat = 0.5) {
        self.intervalSeconds = intervalSeconds
        self.amplitude = amplitude
    }

    public func body(content: Content) -> some View {
        content
            .offset(offset)
            .onAppear {
                guard !reduceMotion else { return }
                startTimer()
            }
            .onDisappear {
                stopTimer()
            }
            .onChange(of: reduceMotion) { _, newValue in
                if newValue {
                    stopTimer()
                    offset = .zero
                } else {
                    startTimer()
                }
            }
    }

    // MARK: - Computed nudge offset

    /// Deterministic 1pt shift cycling through 4 positions.
    static func nudgeOffset(for tick: Int, amplitude: CGFloat) -> CGSize {
        let offsets: [CGSize] = [
            .zero,
            CGSize(width: amplitude, height: 0),
            CGSize(width: 0, height: amplitude),
            CGSize(width: -amplitude, height: 0)
        ]
        return offsets[tick % offsets.count]
    }

    // MARK: - Private

    private func startTimer() {
        var tick = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { _ in
            tick += 1
            let newOffset = BurnInNudgeModifier.nudgeOffset(for: tick, amplitude: amplitude)
            Task { @MainActor in
                withAnimation(.linear(duration: 2)) {
                    offset = newOffset
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - View extension

public extension View {
    /// Applies subtle 1pt positional drift every `intervalSeconds` to prevent
    /// OLED burn-in on static kiosk screens. No-ops when Reduce Motion is on.
    func burnInNudge(every intervalSeconds: TimeInterval = 30) -> some View {
        modifier(BurnInNudgeModifier(intervalSeconds: intervalSeconds))
    }
}
