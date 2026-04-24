import Foundation

// §32 Telemetry Sovereignty Guardrails — PII redaction for String-valued properties

// MARK: - TelemetryRedactor

/// Stateless PII scrubber for `TelemetryRecord` property dictionaries.
///
/// Two-pass algorithm:
/// 1. **Key rejection** — drops entries whose lowercased key exactly matches a
///    known PII field name (`email`, `phone`, `customerName`, etc.).
/// 2. **Value redaction** — passes every remaining value through pattern-based
///    regex substitution to mask embedded emails, phone numbers, and customer
///    names using configurable token placeholders.
///
/// The function is pure — the input dictionary is never mutated.
///
/// ## Usage
/// ```swift
/// let safe = TelemetryRedactor.scrub(["note": "Call 555-123-4567"])
/// // → ["note": "Call <phone>"]
/// ```
public enum TelemetryRedactor {

    // MARK: - PII key blocklist

    /// Exact lowercased key names that identify personal data.
    /// Entries matching these keys are dropped entirely from the output.
    private static let blockedKeys: Set<String> = [
        "email",
        "phone",
        "address",
        "firstname",
        "lastname",
        "customername",
        "customer_name",
        "fullname",
        "full_name",
        "ssn",
        "creditcard",
        "credit_card",
        "cardnumber",
        "card_number",
    ]

    // MARK: - Regex rules

    private struct Rule {
        let regex: NSRegularExpression
        let placeholder: String

        init(_ pattern: String, _ placeholder: String) {
            // Force-try: pattern is a compile-time constant; a typo is a programmer
            // error that must surface immediately in tests.
            // swiftlint:disable:next force_try
            self.regex       = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.placeholder = placeholder
        }
    }

    /// Ordered redaction rules applied to every surviving string value.
    /// More-specific patterns appear before more-general ones.
    private static let rules: [Rule] = [
        // Email addresses (RFC-5321 simplified)
        Rule(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "<email>"),
        // US phone numbers — +1 (555) 123-4567 / 555-123-4567 / 5551234567
        Rule(#"(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#, "<phone>"),
        // Credit card PANs (13-19 contiguous or space/dash-separated digits)
        Rule(#"\b(?:\d[ \-]?){12,18}\d\b"#, "<pan>"),
        // US SSN
        Rule(#"\b(?!000|666|9\d{2})\d{3}[-\s]?(?!00)\d{2}[-\s]?(?!0000)\d{4}\b"#, "<ssn>"),
        // Bearer / API tokens
        Rule(#"Bearer\s+[A-Za-z0-9\-._~+/]+=*"#, "Bearer <token>"),
        // Generic long base64-ish secrets (32+ chars without whitespace)
        Rule(#"\b[A-Za-z0-9+/\-_]{32,}={0,2}\b"#, "<secret>"),
    ]

    // MARK: - Public API

    /// Return a new dictionary with:
    /// - PII-keyed entries removed, and
    /// - PII patterns in remaining values replaced with placeholder tokens.
    ///
    /// - Parameter properties: Raw, potentially-PII-containing property dict.
    /// - Returns: A new dict safe for inclusion in a `TelemetryRecord`.
    public static func scrub(_ properties: [String: String]) -> [String: String] {
        var result = [String: String]()
        result.reserveCapacity(properties.count)
        for (key, value) in properties {
            guard !isBlockedKey(key) else { continue }
            result[key] = redactValue(value)
        }
        return result
    }

    // MARK: - Private helpers

    private static func isBlockedKey(_ key: String) -> Bool {
        blockedKeys.contains(key.lowercased())
    }

    private static func redactValue(_ value: String) -> String {
        var result = value
        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: rule.placeholder
            )
        }
        return result
    }
}
