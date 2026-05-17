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

    /// Production initialiser — reads the current bearer token from an
    /// in-process Keychain-backed cache populated by `SessionBootstrapper`.
    ///
    /// BUGHUNT-2026-05-17: previously read from
    /// `UserDefaults.standard.string(forKey: "telemetry.access_token_shadow")`.
    /// UserDefaults is an unencrypted plist on disk — mirroring the bearer
    /// token there exposed it to any process that can read app storage
    /// (jailbroken devices, sideloaded debug tools, iCloud backups, etc.).
    /// Replaced with a process-local atomic so the token never touches disk.
    /// The wiring contract is unchanged: SessionBootstrapper calls
    /// `updateTokenShadow(_:)` on auth and `clearTokenShadow()` on logout.
    public init() {
        self.tokenProvider = { Self.cachedToken.value }
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

    /// Process-local atomic cache. Holds the active bearer token in memory
    /// only — never written to disk. Wiped on app launch (cold start) and on
    /// explicit `clearTokenShadow()`.
    private static let cachedToken = AtomicToken()

    /// Stash the active token in the in-process cache so telemetry sinks
    /// can pick it up without importing Persistence/KeychainStore.
    ///
    /// Called by `SessionBootstrapper` on successful login / token refresh.
    public static func updateTokenShadow(_ token: String?) {
        cachedToken.value = token
    }

    /// Clear the cache on logout — ensures no stale token is used post-sign-out.
    ///
    /// Called by `SessionBootstrapper` on sign-out / session revocation.
    public static func clearTokenShadow() {
        cachedToken.value = nil
    }
}

// MARK: - AtomicToken

/// NSLock-guarded box so the static cache is safe to read/write from any
/// concurrency context — telemetry sinks live on background actors while
/// SessionBootstrapper writes from MainActor.
private final class AtomicToken: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}
