import Foundation

/// Persists the user's biometric opt-in decision. UserDefaults-backed,
/// zero PII — actual biometric data stays in Secure Enclave.
///
/// Lives in Persistence so Settings (and any future "Security" surface)
/// can read/toggle without taking a dependency on Auth. Auth's
/// `BiometricGate` still owns the LAContext prompt; this type only owns
/// the "has the user opted in?" flag.
@MainActor
public final class BiometricPreference {
    public static let shared = BiometricPreference()
    private let defaultsKey = "auth.biometric_enabled"

    private init() {}

    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Called by the biometric-offer step when the user taps "Enable" AND
    /// the LAContext eval succeeded. Persisting only on a successful first
    /// prompt means we never accidentally flag biometrics enabled when the
    /// user actually cancelled Face ID.
    public func enable() { isEnabled = true }

    /// Settings → Disable biometrics / sign-out. Wipes the flag so the
    /// next launch falls back to PIN-only.
    public func disable() { isEnabled = false }
}
