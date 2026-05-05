import Foundation
import Observation

// §34 Crisis Recovery helpers — SafeMode
// Reduced-functionality app state: disables sync, drafts preserved, read-only.

/// The reason SafeMode was activated.
public enum SafeModeReason: String, Codable, Sendable, CaseIterable {
    /// Activated because a crash loop was detected by `CrashLoopDetector`.
    case crashLoop
    /// Activated manually by a manager or support action.
    case manual
    /// Activated because the network has been unavailable for an extended period.
    case networkFailure
}

/// Reduced-functionality app state activated during a crisis.
///
/// When `isActive` is `true`:
/// - Background sync is disabled — the app becomes read-only for remote data.
/// - Draft writes are still allowed so in-progress work is not lost.
/// - All mutation endpoints (create / update / delete) must refuse to send
///   network requests; callers should gate on `SafeMode.shared.isActive`.
///
/// Persistence: state survives process restart so that a crash-loop cycle cannot
/// escape safe mode by force-quitting.
@Observable
@MainActor
public final class SafeMode {

    // MARK: — Singleton

    public static let shared = SafeMode()

    // MARK: — Storage keys

    private let defaults: UserDefaults
    private static let activeKey  = "com.bizarrecrm.crisis.safeMode.isActive"
    private static let reasonKey  = "com.bizarrecrm.crisis.safeMode.reason"
    private static let activatedAtKey = "com.bizarrecrm.crisis.safeMode.activatedAt"

    // MARK: — Observable state

    /// `true` while the app is in safe (reduced-functionality) mode.
    public private(set) var isActive: Bool

    /// The reason safe mode is active; `nil` when inactive.
    public private(set) var reason: SafeModeReason?

    /// When safe mode was last activated; `nil` if currently inactive.
    public private(set) var activatedAt: Date?

    // MARK: — Derived convenience

    /// Sync operations are forbidden in safe mode.
    public var isSyncDisabled: Bool { isActive }

    /// Remote mutations are forbidden in safe mode.
    public var isReadOnly: Bool { isActive }

    // MARK: — Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isActive = defaults.bool(forKey: Self.activeKey)
        self.activatedAt = defaults.object(forKey: Self.activatedAtKey) as? Date
        if let raw = defaults.string(forKey: Self.reasonKey) {
            self.reason = SafeModeReason(rawValue: raw)
        } else {
            self.reason = nil
        }
    }

    // MARK: — Public API

    /// Activate safe mode for the given reason.
    /// Idempotent: calling again with a different reason updates the reason.
    public func activate(reason: SafeModeReason) {
        let now = Date()
        isActive = true
        self.reason = reason
        activatedAt = now
        defaults.set(true, forKey: Self.activeKey)
        defaults.set(reason.rawValue, forKey: Self.reasonKey)
        defaults.set(now, forKey: Self.activatedAtKey)
        AppLog.app.warning("SafeMode: activated — reason=\(reason.rawValue)")
    }

    /// Deactivate safe mode.
    /// Idempotent: safe to call when already inactive.
    public func deactivate() {
        guard isActive else { return }
        isActive = false
        reason = nil
        activatedAt = nil
        defaults.removeObject(forKey: Self.activeKey)
        defaults.removeObject(forKey: Self.reasonKey)
        defaults.removeObject(forKey: Self.activatedAtKey)
        AppLog.app.info("SafeMode: deactivated")
    }
}
