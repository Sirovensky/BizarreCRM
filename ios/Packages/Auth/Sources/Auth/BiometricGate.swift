import Foundation
import LocalAuthentication
import Core
import Persistence

/// §2.6 — Biometric unlock chain.
///
/// - `isAvailable` — device has Face ID / Touch ID enrolled and the app is
///   allowed to use it (no "locked out" flag on LAContext).
/// - `kind` — which modality so UI can render the right icon/label.
/// - `tryUnlock(reason:)` — async throws-guarded wrapper around
///   `evaluatePolicy`. Returns `false` (not throws) on user cancel so the
///   caller can silently fall through to the PIN keypad.
///
/// Opt-in state lives in `BiometricPreference.shared`. When the user tapped
/// "Enable" on the biometric offer step, we persist a flag so that on next
/// cold start the locked phase can auto-prompt instead of forcing PIN.
public enum BiometricGate {

    public enum Kind: Sendable {
        case none
        case touchID
        case faceID
        case opticID

        public var label: String {
            switch self {
            case .none:    return ""
            case .touchID: return "Touch ID"
            case .faceID:  return "Face ID"
            case .opticID: return "Optic ID"
            }
        }

        public var sfSymbol: String {
            switch self {
            case .none:    return "lock.fill"
            case .touchID: return "touchid"
            case .faceID:  return "faceid"
            case .opticID: return "opticid"
            }
        }
    }

    public static var kind: Kind {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .none:    return .none
        case .touchID: return .touchID
        case .faceID:  return .faceID
        case .opticID: return .opticID
        @unknown default: return .none
        }
    }

    public static var isAvailable: Bool {
        let ctx = LAContext()
        var err: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    public static func tryUnlock(reason: String = "Unlock Bizarre CRM") async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            AppLog.auth.info("Biometrics not available: \(err?.localizedDescription ?? "nil", privacy: .public)")
            return false
        }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            AppLog.auth.info("Biometric evaluation failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

// `BiometricPreference` moved to Persistence so Settings can reach it
// without pulling Auth. Re-exported here so existing `import Auth`
// call sites stay working.
public typealias BiometricPreference = Persistence.BiometricPreference
