import Foundation

// §71 Privacy-first analytics — PII redaction

/// Scrubs analytics property dictionaries before they leave the device.
///
/// Three passes:
/// 1. **Custom-dimension allowlist** — only keys declared in `allowedDimensions`
///    (or in `blockedKeys` for immediate rejection) survive. Unknown keys are
///    stripped rather than redacted-through, per the §32.6 "allowlist not blocklist"
///    rule. Pass `nil` to bypass allowlist enforcement (legacy / uncatalogued events).
/// 2. **Key rejection** — drops any entry whose key exactly matches a known PII
///    field name (case-insensitive).
/// 3. **String-value redaction** — passes every remaining string value through
///    `LogRedactor.redact(_:)` to strip embedded PII patterns (emails, phones, etc.)
///
/// Non-string values (`int`, `double`, `bool`, `null`) are returned unchanged.
public enum AnalyticsRedactor {

    // MARK: — §32.6 Custom dimension allowlist

    /// The canonical set of property keys that events are permitted to include.
    ///
    /// Any key **not** in this set will be stripped by `scrub(_:allowlist:)` when
    /// an allowlist is passed. This enforces the §32.6 rule: "events ship only
    /// fields declared in their schema; unknown fields stripped at serializer."
    ///
    /// Add new keys here when extending the event taxonomy in §32.4.
    public static let allowedDimensions: Set<String> = [
        // Universal / envelope fields
        "session_id", "tenant_slug", "app_version", "platform",
        // Timing
        "duration_ms", "timeout_seconds", "retry_after_seconds",
        "bucket", "duration_bucket",
        // Network / server
        "endpoint", "status_code", "error_code", "request_id",
        // Payment
        "tender", "amount_cents",
        // Sync
        "delta_count", "reason",
        // Entity type
        "entity_type", "resolution",
        // Hardware / device health
        "peripheral_type",
        "free_bytes", "threshold_bytes",
        "cache_name", "evicted_count",
        // WebSocket
        "url_host", "latency_ms", "code",
        // App updates
        "current_version", "available_version",
        // Feature flags
        "flag_key", "enabled", "source",
        // Action taps / mutations
        "screen", "action", "entity_id_hash",
        // Performance
        "cold_launch_ms", "first_paint_ms",
        // POS
        "total_cents", "item_count",
        // §32.4 Sync / launch trigger tags
        "trigger", "launch_kind",
        // Error
        "crash_type",
    ]

    // MARK: — PII key blocklist

    /// Keys that are considered personal data identifiers and must never be sent.
    private static let blockedKeys: Set<String> = [
        "email", "phone", "address",
        "firstname", "lastname",
        "ssn", "creditcard"
    ]

    // MARK: — Public API

    /// Redact a single string value, masking any PII patterns.
    ///
    /// Useful for scrubbing an individual string before embedding it as a property value.
    public static func scrubString(_ value: String) -> String {
        LogRedactor.redact(value)
    }

    /// Return a new dictionary with unknown keys stripped, PII keys removed, and
    /// string values redacted.
    ///
    /// - Parameters:
    ///   - properties: Raw properties dict from the call site.
    ///   - allowlist: Set of permitted keys. Pass `nil` to skip allowlist enforcement
    ///     (legacy paths only). Defaults to `allowedDimensions`.
    ///
    /// This function is pure — the input dictionary is not mutated.
    public static func scrub(
        _ properties: [String: AnalyticsValue],
        allowlist: Set<String>? = allowedDimensions
    ) -> [String: AnalyticsValue] {
        var result: [String: AnalyticsValue] = [:]
        result.reserveCapacity(properties.count)

        for (key, value) in properties {
            // 1. Allowlist gate — strip keys not declared in the schema.
            if let al = allowlist, !al.contains(key) { continue }
            // 2. PII blocklist — hard-reject known PII keys.
            guard !isBlockedKey(key) else { continue }
            // 3. Value redaction.
            result[key] = redactValue(value)
        }
        return result
    }

    // MARK: — Private helpers

    private static func isBlockedKey(_ key: String) -> Bool {
        blockedKeys.contains(key.lowercased())
    }

    private static func redactValue(_ value: AnalyticsValue) -> AnalyticsValue {
        guard case .string(let raw) = value else { return value }
        // §32.6 — untagged / legacy property values run through the
        // shape-detection fallback so anything that *looks* like PII becomes
        // `*LIKELY_PII*` rather than leaking through.
        return .string(LogRedactor.redactWithLikelyPIIFallback(raw))
    }
}
