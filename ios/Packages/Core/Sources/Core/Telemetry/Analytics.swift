import Foundation

// §71 Privacy-first analytics — static entry point

// MARK: — Analytics

/// Static entry point for fire-and-forget event tracking.
///
/// Feature code calls `Analytics.track(...)` — no import of sinks required.
///
/// ```swift
/// Analytics.track(.ticketCreated, properties: ["priority": .string("high")])
/// ```
///
/// The call is non-blocking (Task detached). PII is scrubbed automatically via
/// `AnalyticsRedactor` inside `SinkDispatcher`. Properties must NOT contain raw
/// user-identifying data — callers are responsible for not passing PII keys.
public enum Analytics {

    // MARK: — Shared dispatcher

    /// Shared dispatcher. Replace in tests or at app startup via `configure(...)`.
    nonisolated(unsafe) private static var _dispatcher: SinkDispatcher?

    /// Configure the shared dispatcher. Call once at app startup.
    public static func configure(_ dispatcher: SinkDispatcher) {
        _dispatcher = dispatcher
    }

    // MARK: — Track

    /// Fire-and-forget event tracking. No-op if analytics not configured or user opted out.
    public static func track(
        _ event: AnalyticsEvent,
        properties: [String: AnalyticsValue] = [:]
    ) {
        guard let dispatcher = _dispatcher else { return }
        Task {
            await dispatcher.track(event, properties: properties)
        }
    }

    /// Flush all pending events (call on `scenePhase == .background`).
    public static func flush() {
        guard let dispatcher = _dispatcher else { return }
        Task { await dispatcher.flush() }
    }

    // MARK: — §32 WebSocket connectivity events

    /// §32 — Record a WebSocket channel connection.
    ///
    /// Call this when the push-channel WebSocket handshake completes.
    ///
    /// - Parameters:
    ///   - urlHost: The hostname of the WebSocket server (no path, query, or credentials).
    ///   - latencyMs: Optional round-trip handshake latency in milliseconds.
    public static func trackWebSocketConnected(urlHost: String, latencyMs: Int? = nil) {
        var props: [String: AnalyticsValue] = ["url_host": .string(urlHost)]
        if let ms = latencyMs { props["latency_ms"] = .int(ms) }
        track(.webSocketConnected, properties: props)
    }

    /// §32 — Record a WebSocket channel disconnection.
    ///
    /// Call this in the `URLSessionWebSocketTask` delegate when the connection closes.
    ///
    /// - Parameters:
    ///   - code: RFC 6455 close code integer (e.g. `1001` for "going away").
    ///   - reason: Machine-readable label derived from the close code. Must not contain
    ///     user data. Derive from a fixed mapping rather than passing the raw server reason.
    public static func trackWebSocketDisconnected(code: Int? = nil, reason: String? = nil) {
        var props: [String: AnalyticsValue] = [:]
        if let c = code   { props["code"]   = .int(c) }
        if let r = reason { props["reason"] = .string(r) }
        track(.webSocketDisconnected, properties: props)
    }

    // MARK: — §32 Deep-link source attribution

    /// §32 — Record that the app was launched or foregrounded via a deep link.
    ///
    /// Fire this immediately after resolving the incoming URL/activity before
    /// navigating the user. `screen` is the destination screen name only — never
    /// include URL parameters, query strings, or any user-typed text.
    ///
    /// - Parameters:
    ///   - source: How the link arrived. Use one of the canonical labels:
    ///     `"push_notification"`, `"universal_link"`, `"url_scheme"`, `"spotlight"`,
    ///     `"widget"`, `"siri_shortcut"`, `"qr_code"`, or `"unknown"`.
    ///   - screen: PII-free destination screen name, e.g. `"ticket_detail"`. Pass `nil` if
    ///     the destination cannot be determined without resolving user data.
    public static func trackDeepLinkAttributed(source: String, screen: String? = nil) {
        var props: [String: AnalyticsValue] = ["source": .string(source)]
        if let s = screen { props["screen"] = .string(s) }
        track(.deepLinkAttributed, properties: props)
    }

    // MARK: — §32 App-update available event

    /// §32 — Record that an app update was detected as available.
    ///
    /// Suitable for wiring to an `SKStoreProductViewController` or any in-app
    /// update prompt. Only the version strings are transmitted — no user data.
    ///
    /// - Parameters:
    ///   - currentVersion: The CFBundleShortVersionString of the running build.
    ///   - availableVersion: The version string returned by the App Store or TestFlight.
    public static func trackAppUpdateAvailable(currentVersion: String, availableVersion: String) {
        track(.appUpdateAvailable, properties: [
            "current_version":   .string(currentVersion),
            "available_version": .string(availableVersion),
        ])
    }

    // MARK: — §32 Device health events

    /// §32 — Record that available disk space fell below the low-disk threshold.
    ///
    /// Call this when `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` drops
    /// below your chosen threshold (recommended: 500 MB). No filesystem paths or file
    /// names should appear in the event.
    ///
    /// - Parameters:
    ///   - freeBytes: Bytes available for important usage (from `URLResourceKey`).
    ///   - thresholdBytes: The threshold that was crossed, e.g. `524_288_000` for 500 MB.
    public static func trackLowDiskSpace(freeBytes: Int, thresholdBytes: Int) {
        track(.lowDiskSpace, properties: [
            "free_bytes":      .int(freeBytes),
            "threshold_bytes": .int(thresholdBytes),
        ])
    }

    /// §32 — Record that an `NSCache` evicted its contents due to memory pressure.
    ///
    /// Wire this to `UIApplication.didReceiveMemoryWarningNotification` in each
    /// `NSCache`-owning type. `cacheName` must be a developer-defined literal
    /// (e.g. `"ThumbnailCache"`); never pass user-derived strings.
    ///
    /// - Parameters:
    ///   - cacheName: Developer-defined identifier for the cache, e.g. `"ThumbnailCache"`.
    ///   - evictedCount: Optional count of objects removed (if tracked by the cache owner).
    public static func trackNSCacheMemoryPressure(cacheName: String, evictedCount: Int? = nil) {
        var props: [String: AnalyticsValue] = ["cache_name": .string(cacheName)]
        if let n = evictedCount { props["evicted_count"] = .int(n) }
        track(.nsCacheMemoryPressure, properties: props)
    }

    // MARK: — §32 Domain convenience helpers

    /// §32 — Record a payment-approved event.
    ///
    /// - Parameters:
    ///   - tender: Payment method string, e.g. `"card"`, `"cash"`, `"gift_card"`.
    ///   - amountCents: Integer amount in the smallest currency unit; never PII.
    public static func trackPaymentApproved(tender: String, amountCents: Int) {
        track(.paymentApproved, properties: [
            "tender": .string(tender),
            "amount_cents": .int(amountCents),
        ])
    }

    /// §32 — Record a payment-failed event.
    ///
    /// - Parameters:
    ///   - tender: Payment method string.
    ///   - reason: Machine-readable failure code (e.g. `"insufficient_funds"`).
    ///             Must NOT contain customer text; pass through `AnalyticsRedactor` if unsure.
    public static func trackPaymentFailed(tender: String, reason: String) {
        track(.paymentFailed, properties: [
            "tender": .string(tender),
            "reason": .string(AnalyticsRedactor.scrubString(reason)),
        ])
    }

    /// §32 — Record a sync conflict telemetry event.
    ///
    /// - Parameters:
    ///   - entityType: The domain entity type that conflicted, e.g. `"ticket"`, `"customer"`.
    ///   - resolution: How the conflict was resolved: `"server_wins"`, `"client_wins"`, `"merged"`.
    ///   - deltaCount: Number of fields that differed.
    public static func trackSyncConflict(
        entityType: String,
        resolution: String,
        deltaCount: Int
    ) {
        track(.syncConflictResolved, properties: [
            "entity_type": .string(entityType),
            "resolution": .string(resolution),
            "delta_count": .int(deltaCount),
        ])
    }

    /// §32 — Record a hardware printer connectivity event.
    ///
    /// - Parameters:
    ///   - online: `true` when the printer came online, `false` when it went offline.
    ///   - peripheralType: Optional peripheral type string, e.g. `"bluetooth"`, `"usb"`, `"network"`.
    public static func trackPrinterConnectivity(online: Bool, peripheralType: String? = nil) {
        let event: AnalyticsEvent = online ? .printerOnline : .printerOffline
        var props: [String: AnalyticsValue] = [:]
        if let type_ = peripheralType {
            props["peripheral_type"] = .string(type_)
        }
        track(event, properties: props)
    }

    // MARK: — §32.8 Feature-flag toggle event

    /// §32.8 — Record that a feature flag was toggled.
    ///
    /// Fired whenever a flag changes in either direction so the server can
    /// correlate flag adoption with downstream metrics (e.g. task completion rate).
    ///
    /// - Parameters:
    ///   - flagKey: Stable identifier for the flag, e.g. `"new_checkout_flow"`.
    ///     Must be a developer-defined literal; never pass user-supplied text.
    ///   - enabled: `true` when the flag was switched on, `false` when switched off.
    ///   - source: Who changed the flag: `"server"` (remote payload), `"local_override"` (dev
    ///     build), or `"default"` (first-run initialisation). Defaults to `"server"`.
    public static func trackFeatureFlagToggled(
        flagKey: String,
        enabled: Bool,
        source: String = "server"
    ) {
        track(.featureFlagToggled, properties: [
            "flag_key": .string(flagKey),
            "enabled": .bool(enabled),
            "source": .string(source)
        ])
    }

    // MARK: — §32 Server-error event helpers

    /// §32 — Record a server error received from the tenant backend.
    ///
    /// Use this at API call sites when the server responds with a 4xx/5xx status
    /// so the tenant can audit error rates by endpoint and HTTP status code.
    ///
    /// - Parameters:
    ///   - endpoint: Path-only endpoint identifier, e.g. `"/api/v1/tickets"`.
    ///     Strip query parameters; never include customer data.
    ///   - statusCode: HTTP status code, e.g. `500`, `422`, `401`.
    ///   - errorCode: Machine-readable error code from the response body, e.g.
    ///     `"validation_failed"`. Pass `nil` if not available. Never pass free-form
    ///     server error messages — those may contain PII.
    ///   - requestId: Opaque request correlation ID from the `X-Request-Id` response
    ///     header. Pass `nil` if not present. Used to correlate client + server logs.
    public static func trackServerError(
        endpoint: String,
        statusCode: Int,
        errorCode: String? = nil,
        requestId: String? = nil
    ) {
        var props: [String: AnalyticsValue] = [
            "endpoint": .string(endpoint),
            "status_code": .int(statusCode)
        ]
        if let code = errorCode {
            props["error_code"] = .string(code)
        }
        if let rid = requestId {
            props["request_id"] = .string(rid)
        }
        track(.serverErrorReceived, properties: props)
    }

    /// §32 — Record a server-returned 429 rate-limit hit.
    ///
    /// Helps the tenant tune rate limits if clients are hitting them unexpectedly.
    ///
    /// - Parameters:
    ///   - endpoint: Path-only endpoint identifier.
    ///   - retryAfterSeconds: Value of the `Retry-After` header, if present.
    public static func trackRateLimitHit(endpoint: String, retryAfterSeconds: Int? = nil) {
        var props: [String: AnalyticsValue] = [
            "endpoint": .string(endpoint),
            "status_code": .int(429)
        ]
        if let delay = retryAfterSeconds {
            props["retry_after_seconds"] = .int(delay)
        }
        track(.serverRateLimited, properties: props)
    }

    /// §32 — Record a network timeout waiting for the tenant server.
    ///
    /// - Parameters:
    ///   - endpoint: Path-only endpoint identifier.
    ///   - timeoutSeconds: The timeout interval that elapsed (from `URLRequest.timeoutInterval`).
    public static func trackServerTimeout(endpoint: String, timeoutSeconds: Double) {
        track(.serverTimeout, properties: [
            "endpoint": .string(endpoint),
            "timeout_seconds": .double(timeoutSeconds)
        ])
    }

    // MARK: — §32 Server response-time histogram

    /// §32 — Record a server response time with a histogram bucket label.
    ///
    /// Call this at every API call-site where you measure round-trip latency.
    /// The `bucket` label is computed automatically from `durationMs` using
    /// `ServerResponseTimeBucket.classify(_:)`, allowing the server to
    /// aggregate latency distributions without raw data.
    ///
    /// - Parameters:
    ///   - endpoint: Path-only endpoint identifier (no query params, no PII).
    ///   - durationMs: Round-trip time in milliseconds.
    ///   - statusCode: HTTP status code of the response.
    public static func trackServerResponseTime(
        endpoint: String,
        durationMs: Int,
        statusCode: Int
    ) {
        let bucket = ServerResponseTimeBucket.classify(durationMs)
        track(.serverResponseTime, properties: [
            "endpoint":    .string(endpoint),
            "duration_ms": .int(durationMs),
            "bucket":      .string(bucket.rawValue),
            "status_code": .int(statusCode),
        ])
    }
}

// MARK: — §32 ServerResponseTimeBucket

/// Histogram bucket labels for server round-trip latency.
///
/// Buckets mirror the P50/P75/P95/P99 breakpoints used by the BizarreCRM
/// server dashboard so client and server charts share the same X-axis labels.
///
/// | Bucket     | Range          |
/// |------------|----------------|
/// | `fast`     | < 200 ms       |
/// | `ok`       | 200 – 499 ms   |
/// | `slow`     | 500 – 999 ms   |
/// | `very_slow`| 1000 – 2999 ms |
/// | `timeout`  | ≥ 3000 ms      |
public enum ServerResponseTimeBucket: String, Sendable {
    case fast      = "fast"       // < 200 ms
    case ok        = "ok"         // 200–499 ms
    case slow      = "slow"       // 500–999 ms
    case verySlow  = "very_slow"  // 1000–2999 ms
    case timeout   = "timeout"    // ≥ 3000 ms

    /// Classify a round-trip duration in milliseconds into a bucket label.
    public static func classify(_ ms: Int) -> ServerResponseTimeBucket {
        switch ms {
        case ..<200:    return .fast
        case 200..<500: return .ok
        case 500..<1000: return .slow
        case 1000..<3000: return .verySlow
        default:        return .timeout
        }
    }
}
