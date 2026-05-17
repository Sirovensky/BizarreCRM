#if canImport(UIKit)
import SwiftUI
import DesignSystem

// §4.9 — Bench timer HUD.
//
// Pure local stopwatch — no server call. The technician starts/stops it
// manually. Intended as a floating overlay inside BenchWorkflowView.

// MARK: - Timer state

/// Local-only stopwatch state. All mutations happen on the MainActor.
@MainActor
@Observable
final class BenchTimerState {

    // MARK: State

    enum Phase: Sendable, Equatable { case idle, running, paused }

    private(set) var phase: Phase = .idle
    /// Accumulated elapsed seconds across all start/pause cycles.
    private(set) var elapsed: TimeInterval = 0
    /// Monotonically incremented by the Timer to force @Observable re-evaluation
    /// of `displayTime`. The value itself is not surfaced in the UI.
    private var _tick: Int = 0

    // MARK: Private

    private var startedAt: Date?
    private var timer: Timer?

    // MARK: Actions

    func start() {
        guard phase != .running else { return }
        startedAt = Date()
        phase = .running
        // Tick every 0.5 s for smooth display without over-firing.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func pause() {
        guard phase == .running else { return }
        timer?.invalidate()
        timer = nil
        if let start = startedAt {
            elapsed += Date().timeIntervalSince(start)
        }
        startedAt = nil
        phase = .paused
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        elapsed = 0
        startedAt = nil
        phase = .idle
    }

    /// Invalidate the underlying Timer without resetting elapsed/phase.
    /// Call from view `onDisappear` so the Timer stops firing when the
    /// HUD leaves the screen.
    ///
    /// BUGHUNT-2026-05-17: previously the Timer was only invalidated by
    /// `pause()` and `reset()`. If the user started the bench timer and
    /// navigated away from the ticket without explicitly pausing, the
    /// Timer kept firing every 0.5 s on the RunLoop for the rest of the
    /// app process — each tick allocated a Task that immediately no-op'd
    /// (via [weak self]) but the wake-ups were pure waste.
    func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Private

    private func tick() {
        guard phase == .running else { return }
        // Mutate _tick so @Observable re-evaluates displayTime on next render.
        _tick += 1
    }

    // MARK: Display

    var displayTime: String {
        // Reference _tick so the @Observable macro tracks it; the value itself
        // is only a heartbeat counter and is not displayed.
        _ = _tick
        let total: TimeInterval
        if phase == .running, let start = startedAt {
            total = elapsed + Date().timeIntervalSince(start)
        } else {
            total = elapsed
        }
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = Int(total) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

}

// MARK: - View

/// Small floating HUD showing elapsed bench time with start/pause/reset controls.
/// Attach inside `BenchWorkflowView` as an overlay or inline section.
///
/// Pass an external `BenchTimerState` when the parent needs to observe elapsed
/// time in its own UI (e.g., the `BenchTimerToggleCard` header counter).
/// When no state is supplied the view manages its own local instance.
struct BenchTimerView: View {

    // §4.2 — If the caller provides a shared state object, use it; otherwise
    // fall back to a locally-owned instance. We store the injected reference
    // directly so `@Observable` re-renders propagate from the shared object.
    private var timer: BenchTimerState

    init(state: BenchTimerState? = nil) {
        self.timer = state ?? BenchTimerState()
    }

    var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            timerDisplay
            controls
        }
        .padding(BrandSpacing.base)
        // Liquid Glass on chrome layer only — this is a HUD/toolbar element.
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bench timer")
        // BUGHUNT-2026-05-17: stop the Timer when the HUD leaves the screen so
        // it doesn't keep firing on the RunLoop for the rest of the process.
        .onDisappear { timer.stopTicking() }
    }

    // MARK: - Sub-views

    private var timerDisplay: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "timer")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(timerColor)
                .accessibilityHidden(true)

            Text(timer.displayTime)
                .font(.system(.title2, design: .monospaced, weight: .semibold))
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.3), value: timer.displayTime)
                .accessibilityLabel("Elapsed time: \(timer.displayTime)")
        }
    }

    private var controls: some View {
        HStack(spacing: BrandSpacing.md) {
            // Start / Pause toggle
            Button {
                if timer.phase == .running {
                    timer.pause()
                } else {
                    timer.start()
                }
            } label: {
                Label(
                    timer.phase == .running ? "Pause" : "Start",
                    systemImage: timer.phase == .running ? "pause.fill" : "play.fill"
                )
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .brandGlass(
                    timer.phase == .running ? .identity : .clear,
                    in: Capsule(),
                    tint: timer.phase == .running ? .bizarreOrange : nil,
                    interactive: true
                )
            }
            .accessibilityLabel(timer.phase == .running ? "Pause timer" : "Start timer")
            .accessibilityHint(timer.phase == .running ? "Pauses the bench stopwatch" : "Starts the bench stopwatch")

            // Reset
            if timer.phase != .idle {
                Button {
                    timer.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(BrandSpacing.sm)
                        .brandGlass(.clear, in: Circle(), interactive: true)
                }
                .accessibilityLabel("Reset timer")
                .accessibilityHint("Clears the bench stopwatch to zero")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: timer.phase == .idle)
    }

    // MARK: - Helpers

    private var timerColor: Color {
        switch timer.phase {
        case .idle:    return .bizarreOnSurfaceMuted
        case .running: return .bizarreOrange
        case .paused:  return .bizarreOnSurfaceMuted
        }
    }
}

#Preview("Bench Timer") {
    ZStack {
        Color.bizarreSurfaceBase.ignoresSafeArea()
        BenchTimerView()
            .padding()
    }
}
#endif
