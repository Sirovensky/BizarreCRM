import Foundation

// §71 Privacy-first analytics — tenant-server sink

// MARK: — TenantServerAnalyticsSink

/// Batches analytics events and POSTs them to the tenant's own server.
///
/// - Flushes automatically when the buffer reaches `batchSize` (default 50).
/// - A timer-based flush every 60 seconds is wired at the call site (e.g. `SinkDispatcher`).
/// - On network failure the batch is **dropped** (fire-and-forget). No retry queue.
/// - Events are silently dropped when the user has not opted in to analytics.
///
/// Thread-safety: all mutable state is confined to the actor.
public actor TenantServerAnalyticsSink {

    // MARK: — Dependencies

    /// Resolves the destination URL at send-time so we always egress to the
    /// tenant the user is currently signed in to (§32.0 single-sink rule).
    /// Returning `nil` means "no tenant configured yet" — the batch is dropped.
    public typealias EndpointProvider = @Sendable () -> URL?

    private let endpointProvider: EndpointProvider
    private let consentManager: AnalyticsConsentManager
    private let session: any AnalyticsURLSessionProtocol
    private let batchSize: Int

    // MARK: — Mutable state (actor-isolated)

    private var buffer: [AnalyticsEventPayload] = []

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    // MARK: — Init

    /// Static-endpoint init (legacy / tests). Prefer the `endpointProvider:`
    /// overload in production so the sink follows tenant switches.
    public init(
        endpoint: URL,
        consentManager: AnalyticsConsentManager,
        session: any AnalyticsURLSessionProtocol = URLSession.shared,
        batchSize: Int = 50
    ) {
        self.endpointProvider = { endpoint }
        self.consentManager = consentManager
        self.session = session
        self.batchSize = batchSize
    }

    /// §32.0 single-sink init — resolves the destination URL **at every flush**
    /// so when the user switches tenants (or signs in for the first time), all
    /// subsequent telemetry egresses to the new `APIClient.baseURL`.  Pass a
    /// closure that reads the canonical base URL (e.g. from `UserDefaults` key
    /// `com.bizarrecrm.apiBaseURL` and appends `/telemetry/events`).
    public init(
        endpointProvider: @escaping EndpointProvider,
        consentManager: AnalyticsConsentManager,
        session: any AnalyticsURLSessionProtocol = URLSession.shared,
        batchSize: Int = 50
    ) {
        self.endpointProvider = endpointProvider
        self.consentManager = consentManager
        self.session = session
        self.batchSize = batchSize
    }

    // MARK: — §32.0 Default endpoint provider

    /// Default §32.0 provider — reads the same `UserDefaults` key the rest of
    /// the app (`CrashReporter`, etc.) uses for the tenant base URL and appends
    /// `/telemetry/events`. Returns `nil` when no tenant has been configured;
    /// callers must guard for that case (the sink will simply drop the batch).
    public static func defaultEndpointProvider(
        userDefaults: UserDefaults = .standard,
        baseURLKey: String = "com.bizarrecrm.apiBaseURL",
        path: String = "telemetry/events"
    ) -> EndpointProvider {
        return {
            guard let raw = userDefaults.string(forKey: baseURLKey),
                  let base = URL(string: raw) else { return nil }
            return base.appendingPathComponent(path)
        }
    }

    // MARK: — Public API

    /// Buffer an event. If the buffer reaches `batchSize`, flushes immediately.
    public func enqueue(_ payload: AnalyticsEventPayload) async {
        let allowed = await consentManager.shouldSendEvents
        guard allowed else { return }
        buffer.append(payload)
        if buffer.count >= batchSize {
            await flush()
        }
    }

    /// Send all buffered events immediately. No-op if the buffer is empty.
    public func flush() async {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer = []
        await post(batch)
    }

    // MARK: — Private

    private func post(_ batch: [AnalyticsEventPayload]) async {
        // §32.0 — Resolve the egress URL at send-time so tenant switches take
        // effect immediately. If no tenant is configured, drop the batch
        // (better than POSTing to a stale or hardcoded URL).
        guard let endpoint = endpointProvider() else { return }
        guard let body = try? Self.encoder.encode(batch) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        // Fire-and-forget: ignore errors
        _ = try? await session.data(for: request)
    }
}
