import Foundation

// §71 Privacy-first Analytics — event mapper

// MARK: - AnalyticsEventMapper

/// Converts a strongly-typed `PrivacyEvent` into a `TelemetryRecord` that is
/// safe to enqueue in `TelemetryBuffer`.
///
/// The mapper is the **only** place that creates `TelemetryRecord` values from
/// `PrivacyEvent`s.  It performs two passes of PII protection:
///
/// 1. **Key rejection** — properties whose keys appear in
///    `AnalyticsPIIGuard.forbiddenFieldNames` are dropped before scrubbing.
/// 2. **Value redaction** — the remaining dictionary is passed through
///    `TelemetryRedactor.scrub(_:)`, which strips embedded PII patterns
///    (email addresses, phone numbers, credit-card PANs, SSNs, tokens).
///
/// The `safeMarker` parameter requires a `SafeValue<PIISafe>` — obtained only
/// through `AnalyticsPIIGuard.markSafe(_:)` or `AnalyticsPIIGuard.scrubAndMark(_:)`.
/// This compile-time constraint makes it impossible to accidentally pass an
/// unguarded value.
///
/// ## Usage
/// ```swift
/// let marker = AnalyticsPIIGuard.markSafe("dispatch-context")
/// let record = AnalyticsEventMapper.buildRecord(for: .ticketCreated(priority: "high"),
///                                               safeMarker: marker)
/// await telemetryBuffer.enqueue(record)
/// ```
public enum AnalyticsEventMapper {

    // MARK: - Public API

    /// Build a redacted `TelemetryRecord` from a typed `PrivacyEvent`.
    ///
    /// - Parameters:
    ///   - event: The analytics event to convert.
    ///   - safeMarker: A phantom-typed token proving the caller has gone through
    ///     `AnalyticsPIIGuard`. Its `rawString` is appended under `"_dispatch_ctx"`
    ///     for trace-back purposes (optional; ignored if empty).
    ///   - timestamp: Defaults to `Date.now`; injectable for testing.
    /// - Returns: A fully-scrubbed `TelemetryRecord` ready for `TelemetryBuffer`.
    public static func buildRecord(
        for event: PrivacyEvent,
        safeMarker: SafeValue<PIISafe>,
        timestamp: Date = .now
    ) -> TelemetryRecord {
        var raw = event.properties

        // Drop forbidden keys before scrubbing (belt-and-suspenders).
        for key in raw.keys where AnalyticsPIIGuard.isForbiddenField(key) {
            raw.removeValue(forKey: key)
        }

        // Scrub remaining values for embedded PII patterns.
        var scrubbed = TelemetryRedactor.scrub(raw)

        // Attach the dispatch context marker if non-empty (useful for log correlation).
        if !safeMarker.rawString.isEmpty {
            scrubbed["_dispatch_ctx"] = safeMarker.rawString
        }

        return TelemetryRecord(
            category: event.telemetryCategory,
            name: event.name,
            properties: scrubbed,
            timestamp: timestamp
        )
    }

    /// Convenience overload that auto-generates a `PIISafe` marker.
    ///
    /// Use when you don't need to attach a custom dispatch context.
    public static func buildRecord(
        for event: PrivacyEvent,
        timestamp: Date = .now
    ) -> TelemetryRecord {
        buildRecord(
            for: event,
            safeMarker: AnalyticsPIIGuard.markSafe(""),
            timestamp: timestamp
        )
    }
}
