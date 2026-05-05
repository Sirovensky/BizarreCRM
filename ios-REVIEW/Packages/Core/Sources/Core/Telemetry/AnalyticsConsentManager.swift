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
    ///
    /// Fires `settings.analytics.opted_in` **after** setting the flag so the
    /// event itself is permitted by the newly-granted consent.
    public func optIn() {
        isOptedIn = true
        defaults.set(true, forKey: Self.defaultsKey)
        // §32 Opt-in flow telemetry — record the consent decision.
        // The event is emitted after `isOptedIn` is `true` so the dispatcher
        // allows it through immediately.
        Analytics.track(.analyticsOptedIn, properties: [
            "source": .string("settings")
        ])
    }

    /// Opt the user out of analytics collection. Persists immediately.
    ///
    /// Fires `settings.analytics.opted_out` **before** clearing the flag so the
    /// opt-out acknowledgement itself can still be transmitted.
    public func optOut() {
        // §32 Opt-in flow telemetry — emit while still opted-in so the event
        // is transmitted (consent is cleared on the next line).
        Analytics.track(.analyticsOptedOut, properties: [
            "source": .string("settings")
        ])
        isOptedIn = false
        defaults.set(false, forKey: Self.defaultsKey)
    }

    /// Toggle current consent state.
    public func toggle() {
        if isOptedIn { optOut() } else { optIn() }
    }

    // MARK: — §28.13 Consent reset on logout

    /// Resets analytics consent to the default opt-out state when the user signs out.
    ///
    /// Called by the logout path (via `Notification.Name.userDidSignOut`) so that
    /// a new user signing in on the same device always starts from the privacy-safe
    /// default (opted out), rather than inheriting the previous user's choice.
    ///
    /// Does **not** fire an opt-out analytics event — the session has already ended.
    public func resetForLogout() {
        isOptedIn = false
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}

// MARK: — Notification

public extension Notification.Name {
    /// Posted by the logout path (SettingsView, LoginFlow) so that observers
    /// such as `AnalyticsConsentManager` can reset per-user consent to the
    /// opt-out default (§28.13 consent reset on logout).
    ///
    /// Posting this notification is sufficient — the App module wires the
    /// observer at startup via `NotificationCenter.default.addObserver`.
    static let userDidSignOut = Notification.Name("com.bizarrecrm.auth.userDidSignOut")
}
