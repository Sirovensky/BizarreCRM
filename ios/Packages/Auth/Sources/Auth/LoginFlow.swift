import Foundation
import Observation
import Core
import Networking
import Persistence

@MainActor
@Observable
public final class LoginFlow {
    public enum Step: Equatable, Sendable {
        case credentials
        case twoFactor(challenge: String)
        case pinSetup
        case pinVerify
        case biometricOffer
        case done
    }

    public var step: Step = .credentials
    public var email: String = ""
    public var password: String = ""
    public var totpCode: String = ""
    public var pin: String = ""
    public var confirmPin: String = ""
    public var errorMessage: String?
    public var isSubmitting: Bool = false

    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func submitCredentials() async {
        isSubmitting = true; defer { isSubmitting = false }
        errorMessage = nil

        do {
            let resp = try await api.post(
                "/api/v1/auth/login",
                body: LoginRequest(email: email, password: password),
                as: LoginResponse.self
            )
            if resp.requires2fa, let challenge = resp.challenge {
                step = .twoFactor(challenge: challenge)
            } else if let access = resp.accessToken, let refresh = resp.refreshToken {
                TokenStore.shared.save(access: access, refresh: refresh)
                await api.setAuthToken(access)
                step = PINStore.shared.isEnrolled ? .biometricOffer : .pinSetup
            } else {
                errorMessage = "Server returned an unexpected response."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func submit2FA() async {
        guard case let .twoFactor(challenge) = step else { return }
        isSubmitting = true; defer { isSubmitting = false }
        errorMessage = nil

        do {
            let pair = try await api.post(
                "/api/v1/auth/2fa/verify",
                body: Verify2FARequest(challenge: challenge, code: totpCode),
                as: TokenPair.self
            )
            TokenStore.shared.save(access: pair.accessToken, refresh: pair.refreshToken)
            await api.setAuthToken(pair.accessToken)
            step = PINStore.shared.isEnrolled ? .biometricOffer : .pinSetup
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func enrollPIN() {
        errorMessage = nil
        guard pin.count >= 4, pin.count <= 6 else {
            errorMessage = "PIN must be 4–6 digits."; return
        }
        guard pin == confirmPin else {
            errorMessage = "PINs do not match."; return
        }
        do {
            try PINStore.shared.enrol(pin: pin)
            step = .biometricOffer
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func verifyPIN() -> Bool {
        errorMessage = nil
        if PINStore.shared.verify(pin: pin) {
            step = .done
            return true
        }
        errorMessage = "Incorrect PIN."
        return false
    }

    public func skipBiometric() { step = .done }
}
