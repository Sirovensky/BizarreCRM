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
}
