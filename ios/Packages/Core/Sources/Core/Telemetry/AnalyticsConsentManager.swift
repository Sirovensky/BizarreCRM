import Foundation
import Observation

// §71 Privacy-first analytics — consent management

// MARK: — AnalyticsConsentManager

/// Observable consent manager for analytics opt-in/out.
///
/// **Default: opted-OUT** per privacy-first principle.
/// User opts in via Settings → Privacy → "Share usage analytics".
///
/// Persists the preference to `UserDefaults` so it survives app restarts.
@Observable
@MainActor
public final class AnalyticsConsentManager {

    // MARK: — Storage

    private let defaults: UserDefaults
    private static let defaultsKey = "analytics.consent.optedIn"

    // MARK: — Public state

    /// `true` iff the user has explicitly opted in to analytics.
    public private(set) var isOptedIn: Bool

    /// Convenience — mirrors `isOptedIn`. Sink implementations check this before transmitting.
    public var shouldSendEvents: Bool { isOptedIn }

    // MARK: — Init

    /// - Parameter defaults: Injected for testability; defaults to `UserDefaults.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default is false (opt-out) — `bool(forKey:)` returns false for missing keys.
        self.isOptedIn = defaults.bool(forKey: Self.defaultsKey)
    }

    // MARK: — Mutations

    /// Opt the user in to analytics collection. Persists immediately.
    public func optIn() {
        isOptedIn = true
        defaults.set(true, forKey: Self.defaultsKey)
    }

    /// Opt the user out of analytics collection. Persists immediately.
    public func optOut() {
        isOptedIn = false
        defaults.set(false, forKey: Self.defaultsKey)
    }

    /// Toggle current consent state.
    public func toggle() {
        if isOptedIn { optOut() } else { optIn() }
    }
}
