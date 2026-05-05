import Foundation
import Core
import os
import Core
#if canImport(DeviceCheck)
import DeviceCheck
#endif

// §28.11 Jailbreak / integrity — App Attest (DeviceCheck)
//
// Verifies device integrity via DCAppAttestService before high-value sessions.
// The attestation key is generated once per install, persisted in Keychain, and
// reused for subsequent assertion calls. A fresh challenge nonce must be fetched
// from the server before each assertion to prevent replay attacks.
//
// Lifecycle:
//   1. `prepare()` — generate (or reuse) the attestation key ID; call once at
//      cold start or after a fresh install.
//   2. `attest(challenge:)` — produce a DER-encoded attestation object for the
//      given server-supplied challenge; send the result to POST /auth/attest.
//   3. `assert(challenge:clientData:)` — generate a per-request assertion that
//      the same key signed an action; used for step-up auth on sensitive ops.
//
// On simulators / devices where App Attest is unsupported the service degrades
// gracefully and returns `.unsupported`; callers MUST NOT block UX on this.

// MARK: - AppAttestResult

/// Outcome of an App Attest or assertion call.
public enum AppAttestResult: Sendable {
    /// Device is attested. `data` is the DER-encoded attestation / assertion object.
    case attested(data: Data)
    /// App Attest is not available on this device / environment (simulator, older OS).
    case unsupported
    /// The service returned an error; `error` surfaces the DCError code.
    case failed(Error)
}

// MARK: - AppAttestService

/// §28.11 — Device-integrity attestation via Apple's DCAppAttestService.
///
/// Inject via DI; use ``MockAppAttestService`` in unit tests.
public actor AppAttestService {

    // MARK: - Types

    private enum KeychainKey {
        static let keyID = "com.bizarrecrm.appattest.keyid"
    }

    // MARK: - State

    /// Cached attestation key ID (generated once per install).
    private var cachedKeyID: String?

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Returns `true` when the current device + OS combination supports App Attest.
    public var isSupported: Bool {
        #if canImport(DeviceCheck)
        if #available(iOS 14.0, *) {
            return DCAppAttestService.shared.isSupported
        }
        #endif
        return false
    }

    /// Generates (or reuses) the per-install attestation key ID.
    ///
    /// Safe to call multiple times; subsequent calls return the persisted key ID
    /// from Keychain without hitting the DCAppAttestService.
    ///
    /// - Returns: The key ID string, or `nil` if attestation is unsupported.
    public func prepare() async -> String? {
        guard isSupported else { return nil }

        // Return cached value from this session.
        if let id = cachedKeyID { return id }

        // Attempt to read from Keychain.
        if let stored = keychainRead(key: KeychainKey.keyID) {
            cachedKeyID = stored
            AppLog.auth.debug("AppAttest: reusing existing key ID")
            return stored
        }

        // Generate a fresh attestation key.
        #if canImport(DeviceCheck)
        if #available(iOS 14.0, *) {
            do {
                let keyID = try await DCAppAttestService.shared.generateKey()
                keychainWrite(key: KeychainKey.keyID, value: keyID)
                cachedKeyID = keyID
                AppLog.auth.debug("AppAttest: generated new key ID")
                return keyID
            } catch {
                AppLog.auth.error("AppAttest: key generation failed — \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        #endif
        return nil
    }

    /// Produces a DER-encoded attestation object for the server-supplied challenge.
    ///
    /// The challenge must be a fresh, server-generated nonce (at least 16 bytes of
    /// random data hashed with SHA-256 before being passed here as raw 32 bytes).
    /// Send the returned data to `POST /auth/attest` for server-side verification.
    ///
    /// - Parameter challenge: 32-byte SHA-256 hash of the server nonce.
    /// - Returns: An ``AppAttestResult`` describing the outcome.
    public func attest(challenge: Data) async -> AppAttestResult {
        guard isSupported else { return .unsupported }
        guard let keyID = await prepare() else { return .unsupported }

        #if canImport(DeviceCheck)
        if #available(iOS 14.0, *) {
            do {
                let attestation = try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: challenge)
                AppLog.auth.info("AppAttest: attestation produced (\(attestation.count, privacy: .public) bytes)")
                return .attested(data: attestation)
            } catch {
                AppLog.auth.error("AppAttest: attestation failed — \(error.localizedDescription, privacy: .public)")
                return .failed(error)
            }
        }
        #endif
        return .unsupported
    }

    /// Generates a per-request assertion proving the attested key signed `clientData`.
    ///
    /// Use this for step-up verification on sensitive server-side operations
    /// (e.g., bulk delete, void > threshold, admin config change) after the initial
    /// attestation has been accepted by the server.
    ///
    /// - Parameters:
    ///   - challenge:   32-byte SHA-256 hash of the server-issued per-request nonce.
    ///   - clientData:  The SHA-256 hash of the action payload that the server will
    ///                  validate (e.g., SHA-256 of the JSON body).
    /// - Returns: An ``AppAttestResult`` describing the outcome.
    public func assert(challenge: Data, clientData: Data) async -> AppAttestResult {
        guard isSupported else { return .unsupported }
        guard let keyID = await prepare() else { return .unsupported }

        #if canImport(DeviceCheck)
        if #available(iOS 14.0, *) {
            do {
                // Combine challenge + clientData into the hash the framework expects.
                // Convention: server and client must agree on this construction.
                var combined = challenge
                combined.append(clientData)
                let assertion = try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: combined)
                AppLog.auth.info("AppAttest: assertion generated (\(assertion.count, privacy: .public) bytes)")
                return .attested(data: assertion)
            } catch {
                AppLog.auth.error("AppAttest: assertion failed — \(error.localizedDescription, privacy: .public)")
                return .failed(error)
            }
        }
        #endif
        return .unsupported
    }

    // MARK: - Keychain helpers (internal, minimal, avoids full KeychainStore dep)

    private func keychainRead(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: "com.bizarrecrm.appattest",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private func keychainWrite(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: "com.bizarrecrm.appattest",
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data,
        ]
        // Delete any existing entry first to allow upsert.
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: "com.bizarrecrm.appattest",
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            AppLog.auth.error("AppAttest: Keychain write failed, status=\(status, privacy: .public)")
        }
    }
}

// MARK: - MockAppAttestService

/// Test double — inject in unit / UI tests to avoid real DeviceCheck calls.
public actor MockAppAttestService {

    public enum Behavior {
        case alwaysAttest
        case alwaysUnsupported
        case alwaysFail(Error)
    }

    private let behavior: Behavior

    public init(behavior: Behavior = .alwaysAttest) {
        self.behavior = behavior
    }

    public var isSupported: Bool {
        if case .alwaysUnsupported = behavior { return false }
        return true
    }

    public func prepare() async -> String? {
        guard isSupported else { return nil }
        return "mock-key-id"
    }

    public func attest(challenge: Data) async -> AppAttestResult {
        switch behavior {
        case .alwaysAttest:       return .attested(data: Data("mock-attestation".utf8))
        case .alwaysUnsupported:  return .unsupported
        case .alwaysFail(let e):  return .failed(e)
        }
    }

    public func assert(challenge: Data, clientData: Data) async -> AppAttestResult {
        switch behavior {
        case .alwaysAttest:       return .attested(data: Data("mock-assertion".utf8))
        case .alwaysUnsupported:  return .unsupported
        case .alwaysFail(let e):  return .failed(e)
        }
    }
}
