import Foundation

// §71 Privacy-first Analytics — static dispatcher facade

// MARK: - AnalyticsDispatcher

/// Static, fire-and-forget facade for logging strongly-typed analytics events.
///
/// Feature code calls `AnalyticsDispatcher.log(...)` without needing to know
/// about `TelemetryBuffer`, `TelemetryRecord`, or PII scrubbing.  All of that
/// is handled internally.
///
/// ## Lifecycle
///
/// Configure once at app startup (before any `log` calls):
///
/// ```swift
/// AnalyticsDispatcher.configure(buffer: myTelemetryBuffer)
/// ```
///
/// ## Usage
///
/// ```swift
/// AnalyticsDispatcher.log(.openedDetail(entity: .ticket, id: "t_abc"))
/// AnalyticsDispatcher.log(.saleCompleted(totalCents: 4999, itemCount: 3))
/// AnalyticsDispatcher.log(.formSubmitted(formName: "new_ticket", fieldCount: 5))
/// ```
///
/// ## Privacy guarantee
///
/// `AnalyticsDispatcher.log` converts the event via `AnalyticsEventMapper`,
/// which applies `TelemetryRedactor.scrub(_:)` before enqueueing.  No raw PII
/// can reach the `TelemetryBuffer`.
///
/// ## Thread safety
///
/// The underlying `TelemetryBuffer` is an `actor`; all enqueue calls are
/// dispatched asynchronously via a detached `Task`.  `log` is synchronous
/// from the call-site's perspective (fire-and-forget).
public enum AnalyticsDispatcher {

    // MARK: - Configuration

    /// The shared buffer. Replaced in tests via `configure(buffer:)`.
    nonisolated(unsafe) private static var _buffer: TelemetryBuffer?

    /// Wire up the shared `TelemetryBuffer`.  Call once at app startup.
    ///
    /// - Parameter buffer: The actor-isolated buffer to route events into.
    public static func configure(buffer: TelemetryBuffer) {
        _buffer = buffer
    }

    /// Replace the shared buffer with a test double. Use only in unit tests.
    ///
    /// Passing `nil` disables dispatching (useful to reset state between tests).
    public static func _replaceBuffer(_ buffer: TelemetryBuffer?) {
        _buffer = buffer
    }

    // MARK: - Logging

    /// Log a strongly-typed analytics event.
    ///
    /// The call returns immediately; the event is enqueued in the background.
    /// No-op if `configure(buffer:)` has not been called.
    ///
    /// - Parameter event: The event to log.
    public static func log(_ event: PrivacyEvent) {
        guard let buffer = _buffer else { return }
        let record = AnalyticsEventMapper.buildRecord(for: event)
        Task {
            await buffer.enqueue(record)
        }
    }

    /// Log a strongly-typed analytics event with a custom `PIISafe` dispatch
    /// context marker (useful for trace-back in multi-feature flows).
    ///
    /// - Parameters:
    ///   - event: The event to log.
    ///   - marker: A `SafeValue<PIISafe>` attached as `_dispatch_ctx` on the record.
    public static func log(_ event: PrivacyEvent, marker: SafeValue<PIISafe>) {
        guard let buffer = _buffer else { return }
        let record = AnalyticsEventMapper.buildRecord(for: event, safeMarker: marker)
        Task {
            await buffer.enqueue(record)
        }
    }

    // MARK: - Flush

    /// Flush all buffered events immediately.
    ///
    /// Call when the app transitions to the background (`scenePhase == .background`).
    /// No-op if not configured.
    public static func flush() {
        guard let buffer = _buffer else { return }
        Task {
            await buffer.flush()
        }
    }
}
