import Foundation
import LocalAuthentication
import Core

public enum BiometricGate {
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
