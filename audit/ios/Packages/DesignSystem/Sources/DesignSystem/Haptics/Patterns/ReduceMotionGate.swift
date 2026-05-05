import Foundation
#if canImport(UIKit)
import UIKit
#endif

// §66 — ReduceMotionGate
// Respects system Reduce Motion and Reduce Transparency accessibility settings.
// When the user requests a calm UI, haptics are suppressed.

// MARK: - AccessibilityFlagsProviding (protocol)

/// Abstraction over UIKit accessibility flags.
/// Provides `reduceMotion` and `reduceTransparency` in a testable, platform-
/// independent way without importing UIKit in tests.
public protocol AccessibilityFlagsProviding: Sendable {
    /// Mirrors `UIAccessibility.isReduceMotionEnabled`.
    var isReduceMotionEnabled: Bool { get }
    /// Mirrors `UIAccessibility.isReduceTransparencyEnabled`.
    var isReduceTransparencyEnabled: Bool { get }
}

// MARK: - SystemAccessibilityFlags

/// Production implementation backed by `UIAccessibility`.
public struct SystemAccessibilityFlags: AccessibilityFlagsProviding {

    public init() {}

    public var isReduceMotionEnabled: Bool {
        #if canImport(UIKit)
        return MainActor.assumeIsolated { UIAccessibility.isReduceMotionEnabled }
        #else
        return false
        #endif
    }

    public var isReduceTransparencyEnabled: Bool {
        #if canImport(UIKit)
        return MainActor.assumeIsolated { UIAccessibility.isReduceTransparencyEnabled }
        #else
        return false
        #endif
    }
}

// MARK: - ReduceMotionGate

/// Guards haptic playback behind the system accessibility calm-UI flags.
///
/// Per Apple HIG, apps should avoid haptics when the user has requested
/// a "calmer" interface (`isReduceMotionEnabled`) or when transparency
/// reductions suggest they may be sensitive to sensory stimuli
/// (`isReduceTransparencyEnabled`).
///
/// Usage:
/// ```swift
/// let gate = ReduceMotionGate()
/// guard gate.isHapticAllowed else { return }
/// await HapticPatternPlayer.shared.play(HapticPatternLibrary.success)
/// ```
///
/// Inject a custom `AccessibilityFlagsProviding` in tests to drive
/// both branches without requiring a live device.
public struct ReduceMotionGate: Sendable {

    // MARK: Properties

    private let flags: any AccessibilityFlagsProviding

    // MARK: Init

    /// - Parameter flags: Accessibility flag source. Defaults to
    ///   `SystemAccessibilityFlags()` (UIKit-backed).
    public init(flags: any AccessibilityFlagsProviding = SystemAccessibilityFlags()) {
        self.flags = flags
    }

    // MARK: Public API

    /// `true` when haptics may fire — neither Reduce Motion nor Reduce
    /// Transparency is enabled.
    public var isHapticAllowed: Bool {
        !flags.isReduceMotionEnabled && !flags.isReduceTransparencyEnabled
    }

    /// `true` when the gate suppresses haptics due to Reduce Motion.
    public var isReduceMotionActive: Bool {
        flags.isReduceMotionEnabled
    }

    /// `true` when the gate suppresses haptics due to Reduce Transparency.
    public var isReduceTransparencyActive: Bool {
        flags.isReduceTransparencyEnabled
    }

    // MARK: Convenience player wrapper

    /// Plays `descriptor` via `player` only when `isHapticAllowed`.
    /// Returns `false` when gated out.
    public func play(
        _ descriptor: HapticPatternDescriptor,
        using player: any HapticPatternPlaying
    ) async -> Bool {
        guard isHapticAllowed else { return false }
        return await player.play(descriptor)
    }

    /// Plays `cue` via `cuePlayer` only when `isHapticAllowed`.
    /// Returns `0` when gated out.
    public func play(
        _ cue: HapticPatternCue,
        using cuePlayer: HapticPatternCuePlayer
    ) async -> Int {
        guard isHapticAllowed else { return 0 }
        return await cuePlayer.play(cue)
    }
}
