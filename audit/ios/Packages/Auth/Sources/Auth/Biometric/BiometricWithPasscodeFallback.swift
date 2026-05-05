import Foundation
import LocalAuthentication
import Core

// MARK: - §28.10 LAContext — biometryAny preferred, fallback to device PIN
//
// `BiometricAuthService` (in this module) uses
// `.deviceOwnerAuthenticationWithBiometrics` which does NOT fall back to
// the device passcode when biometry is locked out / not enrolled. For
// step-up flows (sensitive screen reauth, void > $X) we want
// `.deviceOwnerAuthentication` instead — that policy first prompts for
// biometry (Face ID / Touch ID / Optic ID — "biometryAny"), then offers
// the device passcode as a system-managed fallback when biometry fails.
//
// This is a thin, focused helper so callers don't have to know which
// `LAPolicy` to choose.

/// Prefers biometry, falls back to device passcode. Use for step-up
/// reauth where forcing biometry-only would lock out users whose finger
/// is wet, mask is on, or who only enrolled a passcode.
@MainActor
public final class BiometricWithPasscodeFallback {

    public enum Outcome: Sendable, Equatable {
        /// Authenticated with biometry.
        case biometry
        /// Authenticated with device passcode (biometry was unavailable
        /// or rejected). Treated as a successful auth at the OS layer.
        case devicePasscode
        /// User cancelled / fell through both prompts.
        case cancelled
    }

    private let context: LAContextProtocol

    public init(context: LAContextProtocol = SystemLAContext()) {
        self.context = context
    }

    /// Prompt the user. Uses `.deviceOwnerAuthentication` so iOS automatically
    /// routes biometryAny → passcode if biometry fails.
    ///
    /// - Parameter reason: Localised string shown in the system sheet.
    /// - Returns: `.biometry` / `.devicePasscode` / `.cancelled`.
    /// - Throws: `BiometricAuthError` for any other LA failure.
    public func authenticate(reason: String) async throws -> Outcome {
        // First check if either path is available at all. If neither
        // biometry nor passcode is set up, `.deviceOwnerAuthentication`
        // immediately fails.
        let (canEval, error) = context.canEvaluate(policy: .deviceOwnerAuthentication)
        guard canEval else {
            if let laError = error as? LAError {
                switch laError.code {
                case .passcodeNotSet:
                    throw BiometricAuthError.notAvailable
                default:
                    throw BiometricAuthError.underlyingError(laError.errorCode)
                }
            }
            throw BiometricAuthError.notAvailable
        }

        // Snapshot biometry availability so we can attribute the outcome.
        let biometryAvailableBefore: Bool = {
            let (ok, _) = context.canEvaluate(policy: .deviceOwnerAuthenticationWithBiometrics)
            return ok
        }()

        do {
            let ok = try await context.evaluate(
                policy: .deviceOwnerAuthentication,
                localizedReason: reason
            )
            guard ok else { return .cancelled }
            return biometryAvailableBefore ? .biometry : .devicePasscode
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .systemCancel, .appCancel:
                return .cancelled
            case .userFallback:
                // User explicitly tapped "Enter passcode" — iOS handles the
                // passcode sheet itself; if we land here without success
                // it's a cancel.
                return .cancelled
            default:
                throw BiometricAuthError.underlyingError(laError.errorCode)
            }
        }
    }
}
