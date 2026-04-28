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

    // §2.2 Trust-this-device (2FA step)
    public var trustDevice: Bool = false

    // §2.1 Setup probe
    public var isProbing: Bool = false
    public var setupProbeResult: SetupProbeResult? = nil

    // §2.2 Rate-limit countdown — seconds remaining when server returns 429
    public var rateLimitRetryAfter: TimeInterval? = nil

    // §2.11 Current user loaded from /auth/me on cold start
    public var currentUser: MeResponse? = nil

    // §2.11 Session revoked banner
    public var sessionRevokedMessage: String? = nil

    // §2.12 Account-locked modal
    public var isAccountLocked: Bool = false

    // §2.13 Challenge-token expiry task — cancelled when challenge resolves
    @ObservationIgnored private var challengeExpiryTask: Task<Void, Never>? = nil

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

            // §2.6 Login-time biometric — if "Remember me" + biometric enabled,
            // auto-POST /auth/login using stored credentials. We defer the
            // actual attempt to `attemptBiometricLogin()` so the view can
            // trigger it after the UI is ready.
            prefillRememberedUsername()
        }
    }

    // MARK: - §2.6 Prefill remembered username

    private func prefillRememberedUsername() {
        // `LastUsernameStore.lastUsername()` is synchronous under the hood
        // (it calls `storage.getUsername()` which is not async). The actor
        // hop is the only async part; we schedule a Task so init stays sync.
        Task { @MainActor in
            if let saved = await LastUsernameStore.shared.lastUsername() {
                username = saved
            }
        }
    }

    // MARK: - §2.6 Login-time biometric shortcut

    /// Attempt to decrypt stored credentials via biometric and auto-sign-in.
    /// Called from the view on `.onAppear` when `step == .credentials` and
    /// biometric + remember-me are both enabled.
    ///
    /// The `BiometricLoginShortcutModifier` handles the full UX overlay for
    /// the credentials panel. This method is the thin glue in `LoginFlow`
    /// that the modifier's `onSuccess` closure calls back into.
    public func loginWithBiometricCredentials(username: String, password: String) async {
        self.username = username
        self.password = password
        await submitCredentials()
    }

    // MARK: - §2.11 Cold-start /auth/me validation

    /// Validate the stored token on cold start. Call before rendering the main shell.
    /// On success loads current role/permissions into `currentUser`.
    /// On 401 the global `SessionEvents.sessionRevoked` path handles re-auth.
    public func validateSessionOnColdStart() async {
        do {
            let me = try await api.fetchMe()
            currentUser = me
        } catch APITransportError.httpStatus(let code, let msg) where code == 401 {
            // Token already expired — let session-revoked path handle it.
            sessionRevokedMessage = msg
        } catch {
            // Non-auth error — log, don't block UX (network may be flaky).
            AppLog.auth.info("Cold-start /auth/me failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - §2.12 Session-revoked banner handler

    /// Wire into the `SessionEvents.stream` listener in AppState.
    /// Surfaces a glass banner explaining why the user was signed out.
    public func handleSessionRevoked(message: String?) {
        sessionRevokedMessage = message ?? "Your session was revoked on another device."
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
            await runSetupProbe()
        } catch APITransportError.httpStatus(let code, _) where code == 404 {
            // 404 = reachable but unnamed — still a valid server
            ServerURLStore.save(url)
            await runSetupProbe()
        } catch {
            let isOffline: Bool = {
                let ns = error as NSError
                return ns.domain == NSURLErrorDomain &&
                    (ns.code == NSURLErrorNotConnectedToInternet ||
                     ns.code == NSURLErrorNetworkConnectionLost)
            }()
            if isOffline {
                errorMessage = "You're offline. Connect to reach your server."
            } else {
                errorMessage = useSelfHosted
                    ? "Can't reach this server. Check the address."
                    : "Shop not found. Check the name and try again."
            }
        }
    }

    // MARK: - §2.1 Setup probe (runs after server URL confirmed)

    private func runSetupProbe() async {
        isProbing = true
        defer { isProbing = false }

        // Use Keychain directly to check for a saved tenant ID — TenantStore.shared
        // is an actor and we don't want to hold a cross-actor reference here.
        let hasSavedTenant = KeychainStore.shared.get(.activeTenantId) != nil

        let probe = SetupStatusProbe(api: api, hasSavedTenant: hasSavedTenant)
        let result = await probe.run()
        setupProbeResult = result

        switch result {
        case .needsSetup:
            // InitialSetupFlow handles itself — caller observes `setupProbeResult`
            // and pushes the setup wizard view. We stay at `.server` step so
            // the login shell doesn't flash credentials behind the wizard.
            break
        case .needsTenantPicker:
            // TenantPickerSheet will be shown by the caller via `setupProbeResult`.
            step = .credentials
        case .proceedToLogin, .failed:
            step = .credentials
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
        rateLimitRetryAfter = nil
        isAccountLocked = false

        // §2.2 Form validation — CTA is disabled in the view when fields are
        // empty, but guard here too so the actor state is always consistent.
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your username and password."
            return
        }

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
                cancelChallengeExpiry()
                finishAuth(access: access, refresh: refresh)
            } else if resp.requiresPasswordSetup == true, let challenge = resp.challengeToken {
                startChallengeExpiry()
                step = .setPassword(challenge: challenge)
            } else if resp.requires2faSetup == true, let challenge = resp.challengeToken {
                startChallengeExpiry()
                await runTwoFactorSetup(challenge: challenge)
            } else if resp.totpEnabled == true, let challenge = resp.challengeToken {
                startChallengeExpiry()
                step = .twoFactorVerify(challenge: challenge)
            } else if let challenge = resp.challengeToken {
                // Fallback: challenge issued but no flags set — treat as 2FA verify.
                startChallengeExpiry()
                step = .twoFactorVerify(challenge: challenge)
            } else {
                errorMessage = "Unexpected response — check with your admin."
            }
        } catch APITransportError.httpStatus(let code, _) where code == 401 {
            // §2.12 Wrong password — inline error + shake (view observes `errorMessage`)
            errorMessage = "Username or password incorrect."
        } catch APITransportError.httpStatus(let code, _) where code == 423 {
            // §2.12 Account locked
            isAccountLocked = true
        } catch APITransportError.httpStatus(let code, let body) where code == 429 {
            // §2.2 Rate-limit — parse delta-seconds from the server's message or use default
            let retryInterval: TimeInterval
            if let msg = body, let parsed = RetryAfterParser.parse(msg) {
                retryInterval = parsed
            } else {
                retryInterval = 60
            }
            rateLimitRetryAfter = retryInterval
            let retrySeconds = Int(retryInterval.rounded())
            errorMessage = "Too many attempts. Wait \(humanDuration(retrySeconds)) before trying again."
        } catch {
            errorMessage = localizedNetworkError(error)
        }
    }

    // MARK: - §2.2 Rate-limit human-readable duration

    private func humanDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) seconds" }
        let minutes = (seconds + 59) / 60
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    // MARK: - §2.12 Network error localisation

    private func localizedNetworkError(_ error: Error) -> String {
        if let transport = error as? APITransportError {
            switch transport {
            case .noBaseURL:
                return "No server configured. Check the server address."
            case .networkUnavailable:
                return "You're offline. Connect to sign in."
            case .certificatePinFailed:
                return "This server's certificate doesn't match the pinned certificate. Contact your admin."
            case .invalidResponse, .envelopeFailure:
                return "Can't reach this server. Check the address."
            case .decoding:
                return "Unexpected server response. Contact your admin."
            case .httpStatus, .unauthorized, .notImplemented:
                return transport.errorDescription ?? "Request failed."
            }
        }
        // URLError — covers "The Internet connection appears to be offline." etc.
        let underlying = (error as NSError)
        if underlying.domain == NSURLErrorDomain {
            switch underlying.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "You're offline. Connect to sign in."
            case NSURLErrorCannotConnectToHost, NSURLErrorTimedOut:
                return "Can't reach this server. Check the address."
            default:
                return underlying.localizedDescription
            }
        }
        return error.localizedDescription
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

    // MARK: - §2.13 Challenge token expiry

    /// Start the 10-minute expiry clock for any challenge-based step.
    /// Cancel any existing task first so only one clock runs at a time.
    private func startChallengeExpiry() {
        challengeExpiryTask?.cancel()
        challengeExpiryTask = ChallengeTokenExpiry.start { [weak self] in
            guard let self else { return }
            self.step = .credentials
            self.errorMessage = "Session expired. Please sign in again."
        }
    }

    private func cancelChallengeExpiry() {
        challengeExpiryTask?.cancel()
        challengeExpiryTask = nil
    }

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

        // §2.2 Trust-this-device — sends the flag only when the checkbox is on.
        struct TwoFAReq: Encodable, Sendable {
            let challengeToken: String
            let code: String
            let trustDevice: Bool?
        }
        struct TwoFAResp: Decodable, Sendable {
            let accessToken: String
            let refreshToken: String
            let backupCodes: [String]?
        }

        do {
            let resp = try await api.post("/api/v1/auth/login/2fa-verify",
                                          body: TwoFAReq(
                                            challengeToken: challenge,
                                            code: code,
                                            trustDevice: trustDevice ? true : nil
                                          ),
                                          as: TwoFAResp.self)
            if let codes = resp.backupCodes, !codes.isEmpty {
                backupCodes = codes
            }
            finishAuth(access: resp.accessToken, refresh: resp.refreshToken)
        } catch {
            totpCode = ""
            errorMessage = localizedNetworkError(error)
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
        cancelChallengeExpiry()
        TokenStore.shared.save(access: access, refresh: refresh)
        Task { await api.setAuthToken(access) }
        step = PINStore.shared.isEnrolled ? .biometricOffer : .pinSetup
    }
}

// NOTE: ServerURLStore moved to Networking/ServerURLStore.swift.
// This comment stays so grep users know where it went.
