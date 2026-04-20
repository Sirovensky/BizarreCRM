import Foundation
import Observation
import Core
import Networking
import Persistence

@MainActor
@Observable
public final class LoginFlow {
    public enum Step: Equatable, Sendable {
        case server                          // user enters shop slug or self-hosted URL
        case register                        // cloud signup (creates new shop)
        case credentials                     // username + password
        case setPassword(challenge: String)  // forced on first login
        case twoFactorSetup(challenge: String, qrPNGBase64: String?)
        case twoFactorVerify(challenge: String)
        case forgotPassword                  // request reset email
        case pinSetup                        // iOS-only: local unlock PIN
        case pinVerify                       // returning user
        case biometricOffer                  // iOS-only
        case done
    }

    public var step: Step = .server

    // SERVER
    public var shopSlug: String = ""
    public var serverUrlRaw: String = ""
    public var useSelfHosted: Bool = false
    public var resolvedServerName: String? = nil

    // REGISTER
    public var registerShopName: String = ""
    public var registerEmail: String = ""
    public var registerPassword: String = ""

    // CREDENTIALS
    public var username: String = ""
    public var password: String = ""

    // SET_PASSWORD
    public var newPassword: String = ""
    public var confirmPassword: String = ""

    // 2FA
    public var totpCode: String = ""
    public var backupCodes: [String] = []

    /// User flipped the 2FA verify panel to "I lost my authenticator".
    /// When true, `submitTwoFactor` routes to the backup-code endpoint.
    /// Always false on the 2FA *setup* step — setup requires the live code.
    public var useBackupCode: Bool = false
    public var backupCodeInput: String = ""

    /// Remaining backup codes after a successful backup-code login.
    /// Drives a warning banner on the post-login landing screen.
    public var remainingBackupCodes: Int? = nil

    // FORGOT PASSWORD
    public var forgotEmail: String = ""
    public var forgotMessage: String? = nil

    // PIN
    public var pin: String = ""
    public var confirmPin: String = ""

    // shared
    public var errorMessage: String?
    public var isSubmitting: Bool = false

    private let api: APIClient
    private let cloudDomain: String

    public init(api: APIClient, cloudDomain: String = "bizarrecrm.com") {
        self.api = api
        self.cloudDomain = cloudDomain

        // Skip the SERVER picker when the URL is already saved. Users
        // kicked back to the login flow (401, revoked PIN, sign-out)
        // don't need to re-identify their shop on every round-trip —
        // the base URL survives so we can land directly on credentials.
        if let saved = ServerURLStore.load() {
            self.step = .credentials
            self.resolvedServerName = saved.host
        }
    }

    // MARK: - Step A · SERVER

    public func submitServer() async {
        isSubmitting = true; defer { isSubmitting = false }
        errorMessage = nil

        let candidate: URL?
        if useSelfHosted {
            var trimmed = serverUrlRaw.trimmingCharacters(in: .whitespaces)
            // Assume https:// if the user omits the scheme (very common
            // "just the hostname" input). Reject anything non-http(s) so
            // a `javascript:` / `data:` URL can't sneak through.
            if !trimmed.lowercased().hasPrefix("http://") &&
                !trimmed.lowercased().hasPrefix("https://") {
                trimmed = "https://" + trimmed
            }
            candidate = URL(string: trimmed).flatMap { url in
                let scheme = url.scheme?.lowercased() ?? ""
                return (scheme == "https" || scheme == "http") && url.host != nil ? url : nil
            }
        } else {
            let slug = shopSlug
                .lowercased()
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            guard slug.count >= 3 else {
                errorMessage = "Shop name must be at least 3 characters."; return
            }
            candidate = URL(string: "https://\(slug).\(cloudDomain)")
        }

        guard let url = candidate else {
            errorMessage = useSelfHosted
                ? "Could not read that URL. Try https://… format."
                : "That shop name isn't valid."
            return
        }

        await api.setBaseURL(url)

        do {
            struct PortalConfig: Decodable, Sendable { let name: String? }
            let envelope = try await api.getEnvelope("/api/v1/portal/embed/config", query: nil, as: PortalConfig.self)
            resolvedServerName = envelope.data?.name
            ServerURLStore.save(url)
            step = .credentials
        } catch APITransportError.httpStatus(let code, _) where code == 404 {
            // 404 = reachable but unnamed — still a valid server
            ServerURLStore.save(url)
            step = .credentials
        } catch {
            errorMessage = useSelfHosted
                ? "Could not connect: \(error.localizedDescription)"
                : "Shop not found. Check the name and try again."
        }
    }

    public func beginRegister() { errorMessage = nil; step = .register }

    // MARK: - Step B · REGISTER (cloud)

    public func submitRegister() async {
        isSubmitting = true; defer { isSubmitting = false }
        errorMessage = nil

        let slug = shopSlug.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard slug.count >= 3 else { errorMessage = "Shop name must be at least 3 characters."; return }
        guard !registerShopName.isEmpty else { errorMessage = "Shop display name is required."; return }
        guard registerEmail.contains("@") else { errorMessage = "Enter a valid email."; return }
        guard registerPassword.count >= 8 else { errorMessage = "Password must be at least 8 characters."; return }

        struct SignupReq: Encodable, Sendable {
            let slug: String
            let shopName: String
            let adminEmail: String
            let adminPassword: String

            // Server reads these as snake_case (signup.routes.ts). Other
            // endpoints use camelCase — hence the explicit mapping here
            // instead of a global encoder strategy.
            enum CodingKeys: String, CodingKey {
                case slug
                case shopName = "shop_name"
                case adminEmail = "admin_email"
                case adminPassword = "admin_password"
            }
        }
        struct SignupResp: Decodable, Sendable {}

        do {
            await api.setBaseURL(URL(string: "https://\(cloudDomain)"))
            _ = try await api.post("/api/v1/signup", body: SignupReq(
                slug: slug,
                shopName: registerShopName,
                adminEmail: registerEmail,
                adminPassword: registerPassword
            ), as: SignupResp.self)

            // Success — point base URL at the new shop and drop into credentials
            let shopURL = URL(string: "https://\(slug).\(cloudDomain)")!
            await api.setBaseURL(shopURL)
            ServerURLStore.save(shopURL)
            username = registerEmail
            step = .credentials
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Step C · CREDENTIALS

    public func submitCredentials() async {
        isSubmitting = true; defer { isSubmitting = false }
        errorMessage = nil

        // Shapes mirror packages/server/src/routes/auth.routes.ts:569–701
        // Server field names (not guessed): challengeToken, totpEnabled,
        // requires2faSetup, requiresPasswordSetup, trustedDevice, accessToken,
        // refreshToken. `totpEnabled` is the 2FA-verify signal; the wire name
        // is NOT `requires2fa`.
        struct LoginReq: Encodable, Sendable { let username: String; let password: String }
        struct LoginResp: Decodable, Sendable {
            let accessToken: String?
            let refreshToken: String?
            let challengeToken: String?
            let requiresPasswordSetup: Bool?
            let requires2faSetup: Bool?
            let totpEnabled: Bool?
            let trustedDevice: Bool?
        }

        do {
            let resp = try await api.post("/api/v1/auth/login",
                                          body: LoginReq(username: username, password: password),
                                          as: LoginResp.self)

            // Priority matches server response branches:
            // 1. Trusted-device bypass — tokens come back directly
            // 2. First-login password setup
            // 3. 2FA setup pending (new user or newly-required)
            // 4. 2FA verify (existing user with TOTP enabled)
            if let access = resp.accessToken, let refresh = resp.refreshToken {
                finishAuth(access: access, refresh: refresh)
            } else if resp.requiresPasswordSetup == true, let challenge = resp.challengeToken {
                step = .setPassword(challenge: challenge)
            } else if resp.requires2faSetup == true, let challenge = resp.challengeToken {
                await runTwoFactorSetup(challenge: challenge)
            } else if resp.totpEnabled == true, let challenge = resp.challengeToken {
                step = .twoFactorVerify(challenge: challenge)
            } else if let challenge = resp.challengeToken {
                // Fallback: challenge issued but no flags set — treat as 2FA verify.
                step = .twoFactorVerify(challenge: challenge)
            } else {
                errorMessage = "Unexpected response — check with your admin."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Step D · SET_PASSWORD

    public func submitNewPassword() async {
        guard case let .setPassword(challenge) = step else { return }
        isSubmitting = true; defer { isSubmitting = false }
        errorMessage = nil

        guard newPassword.count >= 8 else { errorMessage = "Password must be at least 8 characters."; return }
        guard newPassword == confirmPassword else { errorMessage = "Passwords don't match."; return }

        struct SetPwReq: Encodable, Sendable { let challengeToken: String; let password: String }
        struct SetPwResp: Decodable, Sendable { let challengeToken: String }

        do {
            let resp = try await api.post("/api/v1/auth/login/set-password",
                                          body: SetPwReq(challengeToken: challenge, password: newPassword),
                                          as: SetPwResp.self)
            await runTwoFactorSetup(challenge: resp.challengeToken)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Step E · 2FA_SETUP

    private func runTwoFactorSetup(challenge: String) async {
        // Server response shape (auth.routes.ts:770):
        //   { qr, secret, manualEntry, challengeToken }
        // The QR field is `qr` (not `qrCode`), value is a full
        // "data:image/png;base64,..." URL.
        struct SetupReq: Encodable, Sendable { let challengeToken: String }
        struct SetupResp: Decodable, Sendable {
            let challengeToken: String
            let qr: String?
            let secret: String?
        }
        do {
            let resp = try await api.post("/api/v1/auth/login/2fa-setup",
                                          body: SetupReq(challengeToken: challenge),
                                          as: SetupResp.self)
            // Strip the "data:image/png;base64," prefix for rendering.
            let raw = resp.qr.flatMap { $0.components(separatedBy: ",").last }
            step = .twoFactorSetup(challenge: resp.challengeToken, qrPNGBase64: raw)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func confirmTwoFactorSetup() async {
        guard case let .twoFactorSetup(challenge, _) = step else { return }
        await submitTwoFactor(challenge: challenge)
    }

    // MARK: - Step F · 2FA_VERIFY

    public func submitTwoFactorVerify() async {
        guard case let .twoFactorVerify(challenge) = step else { return }
        if useBackupCode {
            await submitBackupCode(challenge: challenge)
        } else {
            await submitTwoFactor(challenge: challenge)
        }
    }

    /// Flip the 2FA verify panel to/from "use a backup code".
    /// Clears both inputs so stale digits don't post to the wrong endpoint.
    public func toggleBackupCode() {
        useBackupCode.toggle()
        totpCode = ""
        backupCodeInput = ""
        errorMessage = nil
    }

    private func submitTwoFactor(challenge: String) async {
        isSubmitting = true; defer { isSubmitting = false }
        errorMessage = nil

        let code = totpCode.filter(\.isNumber)
        guard code.count == 6 else { errorMessage = "Enter the 6-digit code."; return }

        struct TwoFAReq: Encodable, Sendable { let challengeToken: String; let code: String }
        struct TwoFAResp: Decodable, Sendable {
            let accessToken: String
            let refreshToken: String
            let backupCodes: [String]?
        }

        do {
            let resp = try await api.post("/api/v1/auth/login/2fa-verify",
                                          body: TwoFAReq(challengeToken: challenge, code: code),
                                          as: TwoFAResp.self)
            if let codes = resp.backupCodes, !codes.isEmpty {
                backupCodes = codes
            }
            finishAuth(access: resp.accessToken, refresh: resp.refreshToken)
        } catch {
            totpCode = ""
            errorMessage = error.localizedDescription
        }
    }

    /// POSTs to `/auth/login/2fa-backup`. Server returns tokens + how many
    /// backup codes remain. When that number drops to 0 the landing screen
    /// should force the user to regenerate new backup codes — we surface
    /// `remainingBackupCodes` so Dashboard can act on it.
    private func submitBackupCode(challenge: String) async {
        isSubmitting = true; defer { isSubmitting = false }
        errorMessage = nil

        // Backup codes are Crockford base32 (SEC-L44) — alphanumeric, no
        // case preserved. Strip whitespace + dashes + uppercase.
        let code = backupCodeInput
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        guard code.count >= 8 else { errorMessage = "Enter your full backup code."; return }

        struct BackupReq: Encodable, Sendable { let challengeToken: String; let code: String }
        struct BackupResp: Decodable, Sendable {
            let accessToken: String
            let refreshToken: String
            let remainingBackupCodes: Int?
        }

        do {
            let resp = try await api.post("/api/v1/auth/login/2fa-backup",
                                          body: BackupReq(challengeToken: challenge, code: code),
                                          as: BackupResp.self)
            remainingBackupCodes = resp.remainingBackupCodes
            finishAuth(access: resp.accessToken, refresh: resp.refreshToken)
        } catch {
            backupCodeInput = ""
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Step G · FORGOT_PASSWORD

    public func beginForgotPassword() { errorMessage = nil; forgotMessage = nil; step = .forgotPassword }

    public func submitForgotPassword() async {
        isSubmitting = true; defer { isSubmitting = false }
        errorMessage = nil; forgotMessage = nil

        guard forgotEmail.contains("@") else { errorMessage = "Enter a valid email."; return }

        struct ForgotReq: Encodable, Sendable { let email: String }
        struct ForgotResp: Decodable, Sendable { let message: String? }

        do {
            let resp = try await api.post("/api/v1/auth/forgot-password",
                                          body: ForgotReq(email: forgotEmail),
                                          as: ForgotResp.self)
            forgotMessage = resp.message
                ?? "If an account with that email exists, a reset link has been sent."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Step H · iOS PIN + Biometric

    public func enrollPIN() {
        errorMessage = nil
        guard pin.count >= 4, pin.count <= 6 else { errorMessage = "PIN must be 4–6 digits."; return }
        guard pin == confirmPin else { errorMessage = "PINs don't match."; return }
        do {
            try PINStore.shared.enrol(pin: pin)
            step = .biometricOffer
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Called from the biometric-offer step "Not now" button.
    /// Does NOT persist an opt-in — biometrics stays off.
    public func skipBiometric() {
        BiometricPreference.shared.disable()
        step = .done
    }

    /// Called after a successful `BiometricGate.tryUnlock(...)` on the offer
    /// step. Only then do we persist the opt-in so subsequent cold starts
    /// can prompt automatically.
    public func acceptBiometric() {
        BiometricPreference.shared.enable()
        step = .done
    }

    // MARK: - Navigation helpers

    public func back() {
        errorMessage = nil
        switch step {
        case .register, .credentials:         step = .server
        case .forgotPassword:                 step = .credentials
        case .setPassword, .twoFactorSetup,
             .twoFactorVerify:                step = .credentials
        default: break
        }
    }

    // MARK: - Internal

    private func finishAuth(access: String, refresh: String) {
        TokenStore.shared.save(access: access, refresh: refresh)
        Task { await api.setAuthToken(access) }
        step = PINStore.shared.isEnrolled ? .biometricOffer : .pinSetup
    }
}

// NOTE: ServerURLStore moved to Networking/ServerURLStore.swift.
// This comment stays so grep users know where it went.
