import Foundation

// §32.5 Crash recovery pipeline — Boot-time crash recovery
// Phase 11

/// Boot-time crash detection and recovery coordinator.
///
/// On cold start, call `checkForPriorCrash()` to detect whether the previous
/// session ended abnormally. If `willRestartAfterCrash` is `true`, present the
/// recovery sheet to the user, then call `clearCrashFlag()` after display.
///
/// **Detection strategy**: MetricKit delivers `MXDiagnosticPayload` payloads
/// asynchronously (often next launch). `CrashReporter.didReceive(_:)` calls
/// `markCrashed()` when a crash diagnostic is received. A persistent flag is
/// checked on the *following* cold start.
///
/// Separate from `CrashReporter` (MetricKit actor) to avoid a MetricKit
/// dependency in unit tests.
public final class CrashRecovery: @unchecked Sendable {

    // MARK: — Singleton

    public static let shared = CrashRecovery()

    // MARK: — Storage

    private let defaults: UserDefaults
    private static let flagKey = "com.bizarrecrm.crash.didCrashLastSession"

    // MARK: — Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: — Public API

    /// `true` if the previous session ended in a crash reported via MetricKit.
    ///
    /// Check this at app launch (after `CrashReporter.start()` has been called
    /// and MetricKit delegates have had a chance to fire). In practice, MetricKit
    /// delivers diagnostics on the *next* launch, so this will be `true` on the
    /// launch *after* the crash.
    public var willRestartAfterCrash: Bool {
        defaults.bool(forKey: Self.flagKey)
    }

    /// Called by `CrashReporter` when a `MXCrashDiagnostic` is received.
    /// Persists the crash flag so it survives the next cold start.
    public func markCrashed() {
        defaults.set(true, forKey: Self.flagKey)
    }

    /// Call after the recovery sheet has been shown to reset state.
    public func clearCrashFlag() {
        defaults.removeObject(forKey: Self.flagKey)
    }
}
