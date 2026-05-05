import Foundation

// MARK: - LastRouteStore

/// Persists the most recent deep-link destination across process terminations
/// so the app can restore navigation context on cold launch.
///
/// ## Cold-launch restore flow
/// 1. On every successful deep-link navigation, call `save(_:)`.
/// 2. In `SessionBootstrapper.restoreSession()` — after confirming the user is
///    authenticated — call `consume()` to read and clear the stored route.
/// 3. Feed the returned destination to `DeepLinkRouter` as if it had just
///    arrived, which causes `RootView` to navigate normally.
///
/// ## Security
/// The stored payload is a plain URL string in `UserDefaults` (not a token
/// or credential).  On sign-out, call `clear()` to wipe the value so it
/// cannot be replayed by a different user who logs into the same device.
///
/// Thread-safe: all state lives in `UserDefaults` which is thread-safe for
/// the read/write patterns used here.
public enum LastRouteStore {

    private static let key = "com.bizarrecrm.lastRoute.url"

    // MARK: - Persistence

    /// Persist `destination` as a `bizarrecrm://` URL so it survives process death.
    ///
    /// Only destinations with a tenant slug are persisted; tenant-agnostic
    /// auth routes (`.resetPassword`, `.setupInvite`) are intentionally skipped
    /// to prevent replaying one-shot tokens on cold launch.
    public static func save(_ destination: DeepLinkDestination) {
        switch destination {
        case .resetPassword, .setupInvite, .magicLink:
            // One-shot tokens must not be replayed on cold launch.
            return
        default:
            break
        }

        guard let url = DeepLinkBuilder.build(destination, form: .customScheme) else { return }
        UserDefaults.standard.set(url.absoluteString, forKey: key)
    }

    /// Read (and atomically clear) the stored route.
    ///
    /// Returns `nil` if nothing was stored or the stored URL can no longer be
    /// parsed (e.g. after a schema migration that removed a route case).
    @discardableResult
    public static func consume() -> DeepLinkDestination? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        // Always clear, even if parse fails — stale data should not block launch.
        UserDefaults.standard.removeObject(forKey: key)
        guard let url = URL(string: raw) else { return nil }
        return DeepLinkURLParser.parse(url)
    }

    /// Peek at the stored destination without clearing it.
    ///
    /// Prefer `consume()` for actual restore; use `peek()` for the debug overlay.
    public static func peek() -> DeepLinkDestination? {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let url = URL(string: raw) else { return nil }
        return DeepLinkURLParser.parse(url)
    }

    /// Wipe the stored route.  Call on sign-out to prevent cross-user replay.
    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Whether a restore candidate is currently stored.
    public static var hasPendingRestore: Bool {
        UserDefaults.standard.string(forKey: key) != nil
    }
}
