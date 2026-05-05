import Foundation

// MARK: - §2.5 Mandatory PIN rotation policy

/// Enforces optional tenant-wide mandatory PIN rotation every N days.
///
/// When `rotationDays` is non-nil (set by tenant admin), each enrolled user's
/// PIN age is tracked in UserDefaults (the timestamp itself is not a secret).
/// If the PIN is older than `rotationDays` days the user must update their PIN
/// before accessing the app.
///
/// **Security design**
/// - Only the PIN-last-set timestamp is stored here; PIN material lives in Keychain.
/// - Tenant policy fetched from `GET /auth/pin-policy`; cached in `configure(rotationDays:)`.
/// - The default recommendation is 90 days; tenants can shorten this.
///
/// Integration:
/// ```swift
/// // Apply tenant policy on auth:
/// await PinRotationPolicy.shared.configure(rotationDays: tenantPolicy.pinRotationDays)
///
/// // After user sets a new PIN:
/// PinRotationPolicy.shared.recordPINSet(userId: userId)
///
/// // On app launch / after PIN unlock:
/// if PinRotationPolicy.shared.isRotationRequired(userId: userId) {
///     // Present ChangePINView
/// }
/// ```
public actor PinRotationPolicy {

    // MARK: - Singleton

    public static let shared = PinRotationPolicy()

    // MARK: - Constants

    /// Default rotation period. Tenant can shorten; cannot be infinite.
    public static let defaultRotationDays: Int = 90

    // MARK: - State

    /// `nil` = rotation disabled. Set by calling `configure(rotationDays:)`.
    public private(set) var rotationDays: Int? = nil

    private let defaults: UserDefaults

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Configuration

    /// Apply tenant policy. Pass `nil` to disable rotation enforcement.
    public func configure(rotationDays: Int?) {
        self.rotationDays = rotationDays
    }

    // MARK: - Public API

    /// Record that `userId` just set or changed their PIN. Stores current timestamp.
    public func recordPINSet(userId: String) {
        let key = storageKey(for: userId)
        defaults.set(Date().timeIntervalSince1970, forKey: key)
    }

    /// Returns `true` if the user's PIN has exceeded the configured rotation period.
    /// Always returns `false` when rotation is disabled (`rotationDays == nil`).
    public func isRotationRequired(userId: String) -> Bool {
        guard let days = rotationDays, days > 0 else { return false }
        let key = storageKey(for: userId)
        let ts = defaults.double(forKey: key)

        // No record → treat as very old; require rotation.
        guard ts > 0 else { return true }

        let pinSetDate = Date(timeIntervalSince1970: ts)
        let ageInDays = Date().timeIntervalSince(pinSetDate) / 86400
        return ageInDays >= Double(days)
    }

    /// Days since the PIN was last set for `userId`, or `nil` if no record.
    public func pinAgeDays(userId: String) -> Int? {
        let key = storageKey(for: userId)
        let ts = defaults.double(forKey: key)
        guard ts > 0 else { return nil }
        let pinSetDate = Date(timeIntervalSince1970: ts)
        return max(0, Int(Date().timeIntervalSince(pinSetDate) / 86400))
    }

    /// Clears the rotation record for `userId` (e.g. on account removal).
    public func clearRecord(userId: String) {
        defaults.removeObject(forKey: storageKey(for: userId))
    }

    // MARK: - Private

    private func storageKey(for userId: String) -> String {
        "com.bizarrecrm.auth.pin_rotation.\(userId)"
    }
}
