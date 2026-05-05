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

    private let endpoint: URL
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

    public init(
        endpoint: URL,
        consentManager: AnalyticsConsentManager,
        session: any AnalyticsURLSessionProtocol = URLSession.shared,
        batchSize: Int = 50
    ) {
        self.endpoint = endpoint
        self.consentManager = consentManager
        self.session = session
        self.batchSize = batchSize
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
        guard let body = try? Self.encoder.encode(batch) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        // Fire-and-forget: ignore errors
        _ = try? await session.data(for: request)
    }
}
