import Foundation
import Observation

// §34 Crisis Recovery helpers — CrisisMode
// Locks the app to POS-only screens when enabled (offline catastrophe backup).

/// Observable toggle that locks the app to POS-only screens in an offline catastrophe.
///
/// When `isActive` is set to `true`, the app should restrict navigation to the
/// point-of-sale flow only. All non-POS routes must gate on `CrisisMode.shared.isActive`.
///
/// Persistence: the active flag survives process restart via `UserDefaults` so a
/// force-quit during a crisis does not accidentally re-open full navigation.
///
/// Thread-safety: mutations are always performed on the `@MainActor`; readers off
/// the main actor should access the value through `await MainActor.run { … }`.
@Observable
@MainActor
public final class CrisisMode {

    // MARK: — Singleton

    public static let shared = CrisisMode()

    // MARK: — Persisted state

    private let defaults: UserDefaults
    private static let activeKey = "com.bizarrecrm.crisis.isActive"
    private static let activatedAtKey = "com.bizarrecrm.crisis.activatedAt"

    // MARK: — Observable properties

    /// `true` while the app is in POS-only crisis mode.
    public private(set) var isActive: Bool

    /// When crisis mode was last activated; `nil` if never (or after deactivation).
    public private(set) var activatedAt: Date?

    // MARK: — Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isActive = defaults.bool(forKey: Self.activeKey)
        self.activatedAt = defaults.object(forKey: Self.activatedAtKey) as? Date
    }

    // MARK: — Public API

    /// Activate crisis mode, locking navigation to POS-only screens.
    /// Safe to call when already active (idempotent).
    public func activate() {
        guard !isActive else { return }
        let now = Date()
        isActive = true
        activatedAt = now
        defaults.set(true, forKey: Self.activeKey)
        defaults.set(now, forKey: Self.activatedAtKey)
        AppLog.app.warning("CrisisMode: activated at \(now.timeIntervalSince1970)")
    }

    /// Deactivate crisis mode, restoring full navigation.
    /// Safe to call when already inactive (idempotent).
    public func deactivate() {
        guard isActive else { return }
        isActive = false
        activatedAt = nil
        defaults.removeObject(forKey: Self.activeKey)
        defaults.removeObject(forKey: Self.activatedAtKey)
        AppLog.app.info("CrisisMode: deactivated")
    }
}
