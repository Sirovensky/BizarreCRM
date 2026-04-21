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
}
