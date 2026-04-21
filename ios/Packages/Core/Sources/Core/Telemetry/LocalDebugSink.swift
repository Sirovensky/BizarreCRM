import Foundation

// §71 Privacy-first analytics — local debug sink

#if DEBUG

/// Debug-only sink that logs analytics events via `AppLog.telemetry`.
///
/// Only compiled in `DEBUG` builds; never ships to end users.
public struct LocalDebugSink: Sendable {
    public init() {}

    /// Log the event to the telemetry OSLog channel.
    public func log(_ payload: AnalyticsEventPayload) {
        AppLog.telemetry.debug(
            "[Analytics] \(payload.event.rawValue) session=\(payload.sessionId) props=\(payload.properties.debugDescription)"
        )
    }
}

#endif
