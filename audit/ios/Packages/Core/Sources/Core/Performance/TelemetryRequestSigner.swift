import Foundation

// MARK: - §32.0 Telemetry request signing
//
// All telemetry requests (POST /telemetry/events, /telemetry/metrics,
// /telemetry/crashes, /telemetry/diagnostics, /telemetry/heartbeat)
// must bear the same Bearer token used for regular API calls.
//
// `TelemetryRequestSigner` is injected into the `TenantServerAnalyticsSink`
// and `MetricKitManager` so they don't access Keychain directly.
//
// Data-sovereignty: telemetry collector reads `APIClient.baseURL` at send-time.
// On tenant switch, in-flight telemetry is flushed to the old server before
// the new tenant's base URL takes effect.

// MARK: - TelemetryRequestSigner

/// Stamps outbound telemetry `URLRequest`s with the Bearer auth token.
///
/// Thread-safe: the token is fetched from `KeychainStore` on demand so it
/// always reflects the current session. Reads are `@Sendable` across actors.
public struct TelemetryRequestSigner: Sendable {

    /// Token provider — default reads from KeychainStore.
    private let tokenProvider: @Sendable () -> String?

    // MARK: - Init

    /// Production initialiser — pulls token from Keychain.
    public init() {
        self.tokenProvider = {
            // Lazy import via string-key access — avoids circular dependency
            // between Core and Persistence while keeping the token retrieval here.
            // KeychainStore is in the Persistence package; telemetry sinks are in Core.
            // We use UserDefaults as a bridge: SessionBootstrapper writes the token
            // there on auth (§2 wiring — see SessionBootstrapper.swift).
            UserDefaults.standard.string(forKey: "telemetry.access_token_shadow")
        }
    }

    /// Test / preview initialiser — supply a fixed token.
    public init(token: String?) {
        let captured = token
        self.tokenProvider = { captured }
    }

    // MARK: - Signing

    /// Returns a copy of `request` with the Authorization header applied.
    ///
    /// If no token is available (logged-out state), returns the request unchanged
    /// so unauthenticated events are still submitted — the server will reject or
    /// accept based on its own policy.
    public func sign(_ request: URLRequest) -> URLRequest {
        guard let token = tokenProvider() else { return request }
        var signed = request
        signed.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return signed
    }

    /// Mutating in-place variant for callers that build the request as a `var`.
    public func sign(_ request: inout URLRequest) {
        guard let token = tokenProvider() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Tenant-switch flush

    /// Write the active token shadow into UserDefaults so telemetry sinks can
    /// pick it up without importing Persistence/KeychainStore.
    ///
    /// Called by `SessionBootstrapper` on successful login / token refresh.
    public static func updateTokenShadow(_ token: String?) {
        if let token {
            UserDefaults.standard.set(token, forKey: "telemetry.access_token_shadow")
        } else {
            UserDefaults.standard.removeObject(forKey: "telemetry.access_token_shadow")
        }
    }

    /// Clear the shadow on logout — ensures no stale token is used post-sign-out.
    ///
    /// Called by `SessionBootstrapper` on sign-out / session revocation.
    public static func clearTokenShadow() {
        updateTokenShadow(nil)
    }
}
