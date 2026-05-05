#if canImport(AuthenticationServices)
import AuthenticationServices
import Foundation
import Core

// TODO: Before shipping to TestFlight, ensure app.bizarrecrm.com hosts
//       /.well-known/apple-app-site-association with:
//       { "webcredentials": { "apps": ["<TeamID>.com.bizarrecrm"] } }
//       This associates the relying party with the app for iCloud Keychain
//       passkey sync across all Apple devices. See ios/CLAUDE.md — "Bundle + domain".

// MARK: - Testable controller abstraction

/// Protocol over ASAuthorizationController so PasskeyManager can be
/// integration-tested without a real OS sheet.
public protocol AuthorizationControllerProtocol: AnyObject, Sendable {
    @MainActor
    func performRequests(_ requests: [ASAuthorizationRequest]) async throws -> ASAuthorization
}

/// Live implementation that delegates straight to the OS.
@MainActor
public final class LiveAuthorizationController: NSObject, AuthorizationControllerProtocol, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?

    public override init() {}

    public func performRequests(_ requests: [ASAuthorizationRequest]) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { [weak self] cont in
            guard let self else {
                cont.resume(throwing: AppError.cancelled)
                return
            }
            self.continuation = cont
            let ctrl = ASAuthorizationController(authorizationRequests: requests)
            ctrl.delegate = self
            ctrl.presentationContextProvider = self
            self.controller = ctrl
            ctrl.performRequests()
        }
    }

    // MARK: ASAuthorizationControllerDelegate

    nonisolated public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            continuation?.resume(returning: authorization)
            continuation = nil
        }
    }

    nonisolated public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    // MARK: ASAuthorizationControllerPresentationContextProviding

    @MainActor public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        // Walk the scene hierarchy for the key window.
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes.compactMap { $0.windows.first(where: { $0.isKeyWindow }) }.first
        let anyWindow = scenes.compactMap { $0.windows.first }.first
        return keyWindow ?? anyWindow ?? UIWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

// MARK: - PasskeyManager

/// Wraps the ASAuthorizationController lifecycle with Swift async/await.
///
/// Relying-party identifier: `app.bizarrecrm.com`
/// The OS sheet (Face ID / Touch ID prompt) handles all layout on both
/// iPhone and iPad — no custom branch needed here.
///
/// Swift 6: @MainActor to own the UI presentation context.
@MainActor
public final class PasskeyManager: Sendable {
    public static let relyingPartyIdentifier = "app.bizarrecrm.com"

    private let controller: AuthorizationControllerProtocol

    /// Designated init. Pass a custom controller in tests.
    public init(controller: AuthorizationControllerProtocol = LiveAuthorizationController()) {
        self.controller = controller
    }

    // MARK: - Registration

    /// Begins a passkey registration ceremony.
    ///
    /// - Parameters:
    ///   - username: The account identifier used server-side.
    ///   - displayName: Human-readable name shown in the OS sheet (e.g. "John Doe").
    ///   - challenge: Base64url-encoded challenge bytes from `register/begin`.
    ///   - userId: Base64url-encoded user handle from `register/begin`.
    /// - Returns: `PasskeyRegistration` containing raw credential bytes.
    /// - Throws: `AppError.cancelled` when the user dismisses the sheet;
    ///           `AppError.unknown` for platform errors.
    public func registerPasskey(
        username: String,
        displayName: String,
        challenge: Data,
        userId: Data
    ) async throws -> PasskeyRegistration {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: Self.relyingPartyIdentifier
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: username,
            userID: userId
        )
        request.displayName = displayName

        let authorization: ASAuthorization
        do {
            authorization = try await controller.performRequests([request])
        } catch let err as ASAuthorizationError where err.code == .canceled {
            throw AppError.cancelled
        } catch {
            throw AppError.unknown(underlying: error)
        }

        guard let credential = authorization.credential
                as? ASAuthorizationPlatformPublicKeyCredentialRegistration
        else {
            throw AppError.unknown(underlying: nil)
        }

        return PasskeyRegistration(
            credentialId: credential.credentialID,
            attestation: credential.rawAttestationObject ?? Data(),
            clientDataJSON: credential.rawClientDataJSON
        )
    }

    // MARK: - Authentication

    /// Begins a passkey authentication ceremony.
    ///
    /// - Parameters:
    ///   - username: Optional account identifier. Pass `nil` for discoverable
    ///               credential (resident key) flow — the OS lists all eligible
    ///               passkeys for the relying party.
    ///   - challenge: Base64url-encoded challenge bytes from `authenticate/begin`.
    /// - Returns: `PasskeySignInResult` with assertion bytes for server verification.
    /// - Throws: `AppError.cancelled` when the user dismisses the sheet.
    public func signInWithPasskey(
        username: String?,
        challenge: Data
    ) async throws -> PasskeySignInResult {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: Self.relyingPartyIdentifier
        )
        let request = provider.createCredentialAssertionRequest(challenge: challenge)

        let authorization: ASAuthorization
        do {
            authorization = try await controller.performRequests([request])
        } catch let err as ASAuthorizationError where err.code == .canceled {
            throw AppError.cancelled
        } catch {
            throw AppError.unknown(underlying: error)
        }

        guard let credential = authorization.credential
                as? ASAuthorizationPlatformPublicKeyCredentialAssertion
        else {
            throw AppError.unknown(underlying: nil)
        }

        return PasskeySignInResult(
            credentialId: credential.credentialID,
            assertion: credential.rawAuthenticatorData,
            userId: credential.userID,
            clientDataJSON: credential.rawClientDataJSON
        )
    }
}

// MARK: - Data helpers

extension Data {
    /// Encode to base64url without padding — per FIDO2 / WebAuthn spec.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

#endif
