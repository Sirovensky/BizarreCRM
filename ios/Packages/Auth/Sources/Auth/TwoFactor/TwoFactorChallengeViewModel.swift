import Foundation
import Observation
import Core

// MARK: - Challenge state

@MainActor
@Observable
public final class TwoFactorChallengeViewModel {

    // MARK: Types

    public enum ChallengeResult: Equatable {
        case success(accessToken: String, refreshToken: String)
        case recoverySuccess(accessToken: String, refreshToken: String, codesRemaining: Int?)
    }

    public enum InputMode: Equatable {
        case totp       // default: 6-digit TOTP
        case recovery   // one-time backup code
    }

    // MARK: State

    public private(set) var inputMode: InputMode = .totp

    /// 6 individual digit slots for the segmented input.
    public var digits: [String] = Array(repeating: "", count: 6)

    /// Recovery code text field content (active when inputMode == .recovery).
    public var recoveryCodeInput: String = ""

    public private(set) var isLoading: Bool = false
    public internal(set) var errorMessage: String? = nil

    /// Remaining backup codes (shown after successful recovery login).
    public private(set) var codesRemaining: Int? = nil

    /// When non-nil, challenge has resolved. Caller dismisses and finishes auth.
    public private(set) var result: ChallengeResult? = nil

    // MARK: Lockout

    private static let maxAttempts: Int = 3
    private static let lockoutDuration: TimeInterval = 30

    public internal(set) var failedAttempts: Int = 0
    public internal(set) var lockedUntil: Date? = nil

    public var isLockedOut: Bool {
        guard let until = lockedUntil else { return false }
        return Date() < until
    }

    public var lockoutSecondsRemaining: Int {
        guard let until = lockedUntil else { return 0 }
        return max(0, Int(until.timeIntervalSinceNow))
    }

    // MARK: Derived

    public var totpCode: String {
        digits.joined()
    }

    public var isTOTPComplete: Bool {
        totpCode.filter(\.isNumber).count == 6
    }

    public var canSubmit: Bool {
        !isLoading && !isLockedOut
    }

    // MARK: - Private

    private let repository: TwoFactorRepository
    private let challengeToken: String

    // MARK: Init

    public init(repository: TwoFactorRepository, challengeToken: String) {
        self.repository = repository
        self.challengeToken = challengeToken
    }

    // MARK: - Input mode

    public func switchToRecovery() {
        inputMode = .recovery
        digits = Array(repeating: "", count: 6)
        errorMessage = nil
    }

    public func switchToTOTP() {
        inputMode = .totp
        recoveryCodeInput = ""
        errorMessage = nil
    }

    // MARK: - Submit TOTP

    public func submitTOTP() async {
        // BUGHUNT-2026-05-17: re-entry guard. Two rapid taps on Verify would
        // both POST the same TOTP — first succeeds and stores `result`, second
        // 401s (server marks the TOTP window used), invokes recordFailure(),
        // and `errorMessage` is set on top of the success state. The view's
        // `.disabled(!canSubmit)` only blocks once `isLoading` propagates.
        guard !isLoading else { return }
        guard !isLockedOut else {
            errorMessage = "Too many attempts. Try again in \(lockoutSecondsRemaining) seconds."
            return
        }
        let code = totpCode.filter(\.isNumber)
        guard code.count == 6 else {
            errorMessage = "Enter all 6 digits."
            return
        }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let resp = try await repository.challenge(challengeToken: challengeToken, code: code)
            result = .success(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: TOTP verify cancelled mid-flight (user
            // navigated, app backgrounded). If the POST landed first, the
            // server has already consumed the TOTP code window. Calling
            // recordFailure() and clearing digits would bump the operator
            // toward lockout AND tempt a re-tap that 401s because the same
            // code can't be reused, painting "Code invalid" on a session
            // that was actually verified. Stay silent on cancellation; the
            // operator can tap Verify again only if they choose to.
            digits = Array(repeating: "", count: 6)
            return
        } catch {
            recordFailure()
            errorMessage = AppError.from(error).errorDescription
            digits = Array(repeating: "", count: 6)
        }
    }

    // MARK: - Submit recovery

    public func submitRecovery() async {
        // BUGHUNT-2026-05-17: re-entry guard. Recovery codes are single-use
        // server-side. A double-tap silently burns two — first one returns
        // tokens and decrements `codesRemaining`, second one 401s because
        // the same code was already invalidated, and the user sees an error
        // banner over a successful login that the result struct hasn't
        // propagated to the view yet.
        guard !isLoading else { return }
        let code = recoveryCodeInput
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        guard code.count >= 8 else {
            errorMessage = "Enter your full backup code."
            return
        }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let resp = try await repository.verifyRecovery(code: code)
            codesRemaining = resp.codesRemaining
            result = .recoverySuccess(
                accessToken: resp.accessToken,
                refreshToken: resp.refreshToken,
                codesRemaining: resp.codesRemaining
            )
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: recovery codes are single-use server-side.
            // A cancellation toast tempted a re-tap with the same code that
            // had already been consumed — server 401s, "code invalid"
            // appears on screen, and the user thinks their backup codes
            // are broken. They're not — that one is gone forever. Stay
            // silent; the operator can paste a fresh code if needed.
            recoveryCodeInput = ""
            return
        } catch {
            errorMessage = AppError.from(error).errorDescription
            recoveryCodeInput = ""
        }
    }

    // MARK: - Lockout tracking

    private func recordFailure() {
        failedAttempts += 1
        if failedAttempts >= Self.maxAttempts {
            lockedUntil = Date().addingTimeInterval(Self.lockoutDuration)
        }
    }

    /// Clear lockout after duration has elapsed (call from a timer in the View).
    public func clearLockoutIfExpired() {
        guard let until = lockedUntil, Date() >= until else { return }
        lockedUntil = nil
        failedAttempts = 0
        errorMessage = nil
    }
}
