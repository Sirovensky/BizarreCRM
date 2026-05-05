import Foundation

// §66 — HapticPatternCue
// Composes one or more HapticPatternDescriptor values into a named flow.
// Examples: sale tap → success double-bump, device connect → scan confirm.

// MARK: - HapticPatternCue

/// A named sequence of `HapticPatternDescriptor` values that are played
/// in order, with optional delays between steps.
///
/// `HapticPatternCue` is a pure value type — it carries no engine reference.
/// Pass it to `HapticPatternCuePlayer` (or your test mock) to execute it.
///
/// Usage:
/// ```swift
/// let cue = HapticPatternCue.saleTap
/// await HapticPatternCuePlayer.shared.play(cue)
/// ```
public struct HapticPatternCue: Sendable, Equatable {

    // MARK: Step

    /// One element in a cue sequence.
    public struct Step: Sendable, Equatable {
        /// Pattern to play.
        public let descriptor: HapticPatternDescriptor
        /// Delay before this step fires, relative to the previous step's start.
        public let delay: TimeInterval

        public init(descriptor: HapticPatternDescriptor, delay: TimeInterval = 0) {
            self.descriptor = descriptor
            self.delay = delay
        }
    }

    // MARK: Properties

    /// Human-readable identifier — used in logs and tests.
    public let name: String

    /// Ordered steps that make up the cue.
    public let steps: [Step]

    // MARK: Init

    public init(name: String, steps: [Step]) {
        self.name = name
        self.steps = steps
    }

    // MARK: Equatable

    public static func == (lhs: HapticPatternCue, rhs: HapticPatternCue) -> Bool {
        lhs.name == rhs.name && lhs.steps == rhs.steps
    }
}

// MARK: - Predefined cues

public extension HapticPatternCue {

    /// Card tap followed by a success double-bump (POS checkout confirmation).
    static var saleTap: HapticPatternCue {
        HapticPatternCue(
            name: "saleTap",
            steps: [
                Step(descriptor: HapticPatternLibrary.cardTap, delay: 0),
                Step(descriptor: HapticPatternLibrary.success, delay: 0.15)
            ]
        )
    }

    /// Barcode scanned, then a short success confirmation.
    static var scanAndConfirm: HapticPatternCue {
        HapticPatternCue(
            name: "scanAndConfirm",
            steps: [
                Step(descriptor: HapticPatternLibrary.barcodeScanned, delay: 0),
                Step(descriptor: HapticPatternLibrary.success, delay: 0.12)
            ]
        )
    }

    /// Device connects with a ramp, then a notification pulse.
    static var deviceConnectWelcome: HapticPatternCue {
        HapticPatternCue(
            name: "deviceConnectWelcome",
            steps: [
                Step(descriptor: HapticPatternLibrary.deviceConnected, delay: 0),
                Step(descriptor: HapticPatternLibrary.notification, delay: 0.2)
            ]
        )
    }

    /// Error followed by a second warning to emphasise urgency.
    static var criticalAlert: HapticPatternCue {
        HapticPatternCue(
            name: "criticalAlert",
            steps: [
                Step(descriptor: HapticPatternLibrary.error, delay: 0),
                Step(descriptor: HapticPatternLibrary.warning, delay: 0.25)
            ]
        )
    }

    /// Single-step wrappers for simple one-shot usage.
    static func single(_ descriptor: HapticPatternDescriptor) -> HapticPatternCue {
        HapticPatternCue(
            name: "single.\(descriptor.name)",
            steps: [Step(descriptor: descriptor, delay: 0)]
        )
    }
}

// MARK: - HapticPatternCuePlayer

/// Executes a `HapticPatternCue` step-by-step, using a `HapticPatternPlaying`
/// instance for each step.
///
/// The player is actor-isolated to serialise concurrent playback requests —
/// a new `play(_:)` call cancels any in-progress cue via structured concurrency.
public actor HapticPatternCuePlayer {

    // MARK: Shared instance

    public static let shared = HapticPatternCuePlayer()

    // MARK: Stored state

    private let hapticPlayer: any HapticPatternPlaying

    // MARK: Init

    /// - Parameter hapticPlayer: The underlying player. Defaults to
    ///   `HapticPatternPlayer.shared`. Pass a mock in tests.
    public init(hapticPlayer: any HapticPatternPlaying = HapticPatternPlayer.shared) {
        self.hapticPlayer = hapticPlayer
    }

    // MARK: Public API

    /// Plays all steps of `cue` in order, honouring `step.delay` before each.
    ///
    /// Returns the number of steps that successfully triggered a hardware
    /// response (`true` from `HapticPatternPlaying.play(_:)`).
    @discardableResult
    public func play(_ cue: HapticPatternCue) async -> Int {
        var successCount = 0
        for step in cue.steps {
            if step.delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(step.delay * 1_000_000_000))
            }
            let played = await hapticPlayer.play(step.descriptor)
            if played { successCount += 1 }
        }
        return successCount
    }
}
