import Foundation
import CryptoKit
import Core

/// §2.5 — PIN storage + failure-lockout state machine.
///
/// Enrollment and raw hash still live behind Keychain
/// (`accessibility: afterFirstUnlockThisDeviceOnly`). Adds an escalating
/// lockout so brute-forcing the 4–6 digit space is infeasible:
///
/// | failure count | lockout on next failure      |
/// | ------------- | ---------------------------- |
/// | 0 … 4         | none — try again             |
/// | 5             | 30 s                         |
/// | 6             | 1 min                        |
/// | 7             | 5 min                        |
/// | 8             | 15 min                       |
/// | 9             | 1 hr                         |
/// | 10            | **revoked** — full re-auth   |
///
/// State persists across cold starts so a killed-then-relaunched attacker
/// can't reset the counter for free.
@MainActor
public final class PINStore {
    public static let shared = PINStore()
    public static let maxFailuresBeforeRevoke = 10

    /// Returned by `verify(pin:)`.
    public enum VerifyResult: Equatable, Sendable {
        /// PIN matched; counter reset.
        case ok
        /// PIN wrong but retries remain; `remainingBeforeLockout` counts
        /// how many more wrongs until the next lockout.
        case wrong(remainingBeforeLockout: Int)
        /// Temporary lockout in effect until `until`.
        case lockedOut(until: Date)
        /// 10+ failures — the user must re-authenticate fully.
        case revoked
    }

    private init() {}

    public var isEnrolled: Bool { KeychainStore.shared.get(.pinHash) != nil }

    /// Currently-active lockout window, if any. Nil when the user can try.
    public var lockoutEndsAt: Date? {
        guard let raw = KeychainStore.shared.get(.pinLockUntil),
              let ts = TimeInterval(raw)
        else { return nil }
        let date = Date(timeIntervalSince1970: ts)
        return date > Date() ? date : nil
    }

    public var failCount: Int {
        Int(KeychainStore.shared.get(.pinFailCount) ?? "0") ?? 0
    }

    public func enrol(pin: String) throws {
        let hashed = Self.hash(pin)
        try KeychainStore.shared.set(hashed, for: .pinHash)
        try KeychainStore.shared.set(String(pin.count), for: .pinLength)
        resetFailures()
    }

    /// Length of the currently-enrolled PIN, if any. UI reads this so the
    /// dot row matches what the user actually typed at enrollment (4-6
    /// digits). Returns nil when nothing is enrolled.
    public var enrolledLength: Int? {
        guard let raw = KeychainStore.shared.get(.pinLength),
              let n = Int(raw),
              n >= 4, n <= 6
        else { return nil }
        return n
    }

    /// Attempt to verify the PIN. Applies escalating lockout on failure.
    /// The result dictates what the caller (usually `PINUnlockView`) renders.
    public func verify(pin: String) -> VerifyResult {
        // 1. Hard-revoked: any wrong attempts after max, or lockout still
        //    in the future — report first.
        let count = failCount
        if count >= Self.maxFailuresBeforeRevoke {
            return .revoked
        }
        if let until = lockoutEndsAt {
            return .lockedOut(until: until)
        }

        // 2. Happy path.
        if isEnrolled, let stored = KeychainStore.shared.get(.pinHash),
           Self.hash(pin) == stored {
            resetFailures()
            return .ok
        }

        // 3. Wrong. Bump the counter + compute next lockout if we just hit a
        //    gate. The counter persists even if the user force-quits the app.
        let newCount = count + 1
        try? KeychainStore.shared.set(String(newCount), for: .pinFailCount)

        if newCount >= Self.maxFailuresBeforeRevoke {
            // Blow away the stored PIN so even a guess matching the hash
            // after this point is rejected at the gate above.
            try? KeychainStore.shared.remove(.pinHash)
            return .revoked
        }
        if let delay = Self.lockoutSeconds(for: newCount) {
            let until = Date().addingTimeInterval(delay)
            try? KeychainStore.shared.set(String(until.timeIntervalSince1970),
                                           for: .pinLockUntil)
            return .lockedOut(until: until)
        }
        return .wrong(remainingBeforeLockout: max(0, 5 - newCount))
    }

    public func reset() {
        try? KeychainStore.shared.remove(.pinHash)
        try? KeychainStore.shared.remove(.pinLength)
        resetFailures()
    }

    /// Clear only the failure counter + lockout. Used after a biometric
    /// unlock succeeds so the user's PIN attempts aren't poisoned by
    /// stale failed tries from before the biometric fallback.
    public func clearFailures() {
        resetFailures()
    }

    private func resetFailures() {
        try? KeychainStore.shared.remove(.pinFailCount)
        try? KeychainStore.shared.remove(.pinLockUntil)
    }

    /// Static so tests can assert exact seconds per tier without reaching
    /// into an instance.
    static func lockoutSeconds(for count: Int) -> TimeInterval? {
        switch count {
        case 5:  return 30
        case 6:  return 60
        case 7:  return 5 * 60
        case 8:  return 15 * 60
        case 9:  return 60 * 60
        default: return nil
        }
    }

    /// Note: replace with Argon2id in a follow-up pass. SHA-256 here keeps
    /// Phase 0 moving without dragging in a native crypto dep; PIN is behind
    /// Keychain already, so the risk surface is small.
    private static func hash(_ pin: String) -> String {
        let salt = "bizarre-v1"
        let digest = SHA256.hash(data: Data((pin + salt).utf8))
        return Data(digest).base64EncodedString()
    }
}
