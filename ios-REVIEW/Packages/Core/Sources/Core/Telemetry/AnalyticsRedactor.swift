import Foundation

// §71 Privacy-first analytics — PII redaction

/// Scrubs analytics property dictionaries before they leave the device.
///
/// Two passes:
/// 1. **Key rejection** — drops any entry whose key exactly matches a known PII
///    field name (case-insensitive).
/// 2. **String-value redaction** — passes every remaining string value through
///    `LogRedactor.redact(_:)` to strip embedded PII patterns (emails, phones, etc.)
///
/// Non-string values (`int`, `double`, `bool`, `null`) are returned unchanged.
public enum AnalyticsRedactor {

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

    /// Return a new dictionary with PII keys removed and string values redacted.
    ///
    /// This function is pure — the input dictionary is not mutated.
    public static func scrub(_ properties: [String: AnalyticsValue]) -> [String: AnalyticsValue] {
        var result: [String: AnalyticsValue] = [:]
        result.reserveCapacity(properties.count)

        for (key, value) in properties {
            guard !isBlockedKey(key) else { continue }
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
        return .string(LogRedactor.redact(raw))
    }
}
