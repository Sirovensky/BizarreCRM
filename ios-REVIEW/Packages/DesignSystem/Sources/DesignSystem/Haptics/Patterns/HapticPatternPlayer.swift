import Foundation
#if canImport(CoreHaptics)
import CoreHaptics
#endif

// §66 — HapticPatternPlayer
// Protocol + real implementation that wraps CHHapticEngine.
// Designed to be injectable for testing via the protocol.

// MARK: - HapticPatternPlaying (protocol)

/// Plays a `HapticPatternDescriptor`, returning whether playback succeeded.
///
/// Conforming types wrap a hardware haptic engine. In tests, use
/// `MockHapticPatternPlayer` (defined in the test target) to assert
/// playback without requiring real hardware.
public protocol HapticPatternPlaying: Sendable {
    /// Attempts to play `descriptor`. Returns `true` on success.
    func play(_ descriptor: HapticPatternDescriptor) async -> Bool
}

// MARK: - HapticPatternPlayer (real implementation)

/// Actor-isolated wrapper around `CHHapticEngine` that plays
/// `HapticPatternDescriptor` values from `HapticPatternLibrary`.
///
/// Lifecycle notes:
/// - The engine is created and started lazily on first `play(_:)` call.
/// - On engine stoppage the `isRunning` flag is cleared; the next `play(_:)`
///   call restarts it automatically.
/// - `reset()` clears the engine entirely — useful in unit tests or when
///   the audio session is invalidated at the app level.
public actor HapticPatternPlayer: HapticPatternPlaying {

    // MARK: Shared instance

    public static let shared = HapticPatternPlayer()

    // MARK: Private state

#if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
    private var isRunning: Bool = false
#endif

    // MARK: Init

    public init() {}

    // MARK: HapticPatternPlaying

    /// Plays `descriptor` using CoreHaptics.
    /// Returns `false` when:
    /// - the device does not support haptics,
    /// - the engine cannot be started, or
    /// - the pattern is malformed.
    public func play(_ descriptor: HapticPatternDescriptor) async -> Bool {
#if canImport(CoreHaptics)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return false
        }
        guard let pattern = descriptor.makePattern() else {
            return false
        }
        await ensureRunning()
        guard let engine else { return false }
        do {
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
#else
        return false
#endif
    }

    // MARK: Public lifecycle

    /// Starts the underlying engine if it is not already running.
    public func start() async {
#if canImport(CoreHaptics)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        if engine == nil {
            guard let newEngine = buildEngine() else { return }
            engine = newEngine
        }
        await startEngine()
#endif
    }

    /// Stops and releases the underlying engine.
    /// The next `play(_:)` call will recreate it.
    public func reset() {
#if canImport(CoreHaptics)
        engine = nil
        isRunning = false
#endif
    }

    // MARK: Private helpers

#if canImport(CoreHaptics)
    private func ensureRunning() async {
        if !isRunning {
            await start()
        }
    }

    private func startEngine() async {
        guard let engine, !isRunning else { return }
        do {
            try await engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    private func buildEngine() -> CHHapticEngine? {
        do {
            let e = try CHHapticEngine()
            e.stoppedHandler = { [weak self] _ in
                guard let self else { return }
                Task { await self.handleStopped() }
            }
            e.resetHandler = { [weak self] in
                guard let self else { return }
                Task { await self.handleReset() }
            }
            return e
        } catch {
            return nil
        }
    }

    private func handleStopped() {
        isRunning = false
    }

    private func handleReset() {
        isRunning = false
        Task { await startEngine() }
    }
#endif
}
