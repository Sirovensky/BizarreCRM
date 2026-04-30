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
}
