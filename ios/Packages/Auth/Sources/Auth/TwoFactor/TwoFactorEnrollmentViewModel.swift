import Foundation
import Observation
import Core

// MARK: - Enrollment state machine

@MainActor
@Observable
public final class TwoFactorEnrollmentViewModel {

    // MARK: State

    public enum EnrollState: Equatable {
        case idle           // Step 1: explanation
        case enrolling      // loading: calling /2fa/enroll
        case showingQR      // Step 2: QR + secret shown
        case verifying      // loading: calling /2fa/verify
        case showingCodes   // Step 4: backup codes
        case done           // Step 5: finished
        case error(String)  // inline error
    }

    public internal(set) var state: EnrollState = .idle

    // Step 2 data (set after enroll succeeds)
    public private(set) var otpauthURI: String = ""
    public private(set) var secret: String = ""

    // Step 3 — user's input
    public var verifyCode: String = ""
    public var verifyFieldError: String? = nil

    // Step 4 — backup codes (in-memory only, never persisted)
    public private(set) var recoveryCodeList: RecoveryCodeList = RecoveryCodeList(codes: [])
    public var hasSavedCodes: Bool = false

    // Shared
    public private(set) var isLoading: Bool = false

    // MARK: - Private

    private let repository: TwoFactorRepository

    // MARK: Init

    public init(repository: TwoFactorRepository) {
        self.repository = repository
    }

    // MARK: - Step 1 → 2: Enroll

    public func continueFromIntro() async {
        guard state == .idle else { return }
        isLoading = true
        state = .enrolling
        do {
            let resp = try await repository.enroll()
            otpauthURI = resp.otpauthURI
            secret = resp.secret
            recoveryCodeList = RecoveryCodeList(codes: resp.backupCodes)
            state = .showingQR
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: nav cancels enroll POST; server may
            // have generated a pending 2FA secret. Reset to .idle so
            // retap creates a fresh enrollment (server should overwrite
            // pending) rather than painting an error.
            state = .idle
            isLoading = false
            return
        } catch let appError as AppError {
            state = .error(appError.errorDescription ?? "Enrollment failed.")
        } catch {
            state = .error(AppError.from(error).errorDescription ?? "Enrollment failed.")
        }
        isLoading = false
    }

    // MARK: - Step 3: Verify

    public func submitVerifyCode() async {
        // BUGHUNT-2026-05-17: re-entry guard. Without this, a double-tap on
        // "Verify" sends two POST /2fa/verify with the same 6-digit code.
        // The server marks TOTP windows as used on first verify, so the
        // second call 401s — and the catch branch sets verifyFieldError +
        // state back to .showingQR even though enrollment actually succeeded.
        // The user sees "wrong code" on a code that was just accepted.
        guard !isLoading else { return }
        let digits = verifyCode.filter(\.isNumber)
        guard digits.count == 6 else {
            verifyFieldError = "Enter the 6-digit code from your authenticator."
            return
        }
        verifyFieldError = nil
        isLoading = true
        state = .verifying
        do {
            _ = try await repository.verify(code: digits)
            state = .showingCodes
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: nav cancels verify POST, but server
            // may have committed (2FA activated). Painting "wrong code"
            // tempts the user to re-enter the same 6-digit code, which
            // the server will reject (TOTP window used/elapsed), locking
            // them out of finishing setup. Stay silent on cancel.
            state = .showingQR
            isLoading = false
            return
        } catch let appError as AppError {
            if case .validation(let fields) = appError {
                verifyFieldError = fields["code"] ?? appError.errorDescription
            } else {
                verifyFieldError = appError.errorDescription
            }
            state = .showingQR
        } catch {
            verifyFieldError = AppError.from(error).errorDescription
            state = .showingQR
        }
        isLoading = false
    }

    // MARK: - Step 4 → Done

    public func confirmSaved() {
        guard hasSavedCodes else { return }
        state = .done
    }

    // MARK: - Reset

    public func reset() {
        state = .idle
        otpauthURI = ""
        secret = ""
        verifyCode = ""
        verifyFieldError = nil
        recoveryCodeList = RecoveryCodeList(codes: [])
        hasSavedCodes = false
        isLoading = false
    }
}
