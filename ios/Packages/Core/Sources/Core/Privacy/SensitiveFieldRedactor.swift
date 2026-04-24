import Foundation

// §28 Security & Privacy helpers — Per-category PII redaction
// Extends §32 TelemetryRedactor patterns with DataHandlingCategory awareness.

// MARK: - SensitiveFieldRedactor

/// Stateless PII redactor that applies per-``DataHandlingCategory`` regex
/// patterns to a raw string, replacing matches with placeholder tokens.
///
/// ## Relationship to TelemetryRedactor (§32)
/// ``TelemetryRedactor`` operates on `[String: String]` property dictionaries
/// and runs a fixed rule set.  `SensitiveFieldRedactor` is the complementary
/// surface-level primitive:
/// - It operates on a single `String` value.
/// - The caller selects which ``DataHandlingCategory`` patterns to apply.
/// - It is composable with `TelemetryRedactor` — pass the output through
///   `TelemetryRedactor.scrub(_:)` for an additional key-drop pass if needed.
///
/// ## Usage
/// ```swift
/// let redacted = SensitiveFieldRedactor.redact(
///     "Contact alice@example.com or +1 (555) 123-4567",
///     categories: [.email, .phone]
/// )
/// // → "Contact <email> or <phone>"
/// ```
public enum SensitiveFieldRedactor {

    // MARK: - Private rule type

    private struct Rule: Sendable {
        let pattern: String
        let placeholder: String
        let regex: NSRegularExpression

        init(_ pattern: String, _ placeholder: String) {
            // Force-try: compile-time constant patterns; a typo is a programmer error.
            // swiftlint:disable:next force_try
            self.regex       = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.pattern     = pattern
            self.placeholder = placeholder
        }
    }

    // MARK: - Per-category rule sets

    private static let rulesByCategory: [DataHandlingCategory: [Rule]] = {
        var map = [DataHandlingCategory: [Rule]]()

        map[.email] = [
            Rule(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "<email>"),
        ]

        map[.phone] = [
            // US/CA phone numbers: +1 (555) 123-4567 / 555-123-4567 / 5551234567
            Rule(#"(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#, "<phone>"),
            // International E.164: +44 7700 900123
            Rule(#"\+\d{1,3}[\s\-]?\d{1,4}[\s\-]?\d{3,4}[\s\-]?\d{3,4}"#, "<phone>"),
        ]

        map[.name] = [
            // Match "First Last" pairs of title-cased words (heuristic — low false-positive
            // approach suitable for form-field display redaction, not general NLP).
            Rule(#"\b[A-Z][a-z]{1,20}\s[A-Z][a-z]{1,20}\b"#, "<name>"),
        ]

        map[.address] = [
            // US street address: 123 Main St / 4500 Oak Avenue
            Rule(#"\b\d{1,5}\s+[A-Za-z0-9\s,\.]{5,60}(?:St|Ave|Rd|Blvd|Dr|Ln|Way|Ct|Pl|Terr|Ter)\b\.?"#, "<address>"),
            // US ZIP code (standalone)
            Rule(#"\b\d{5}(?:-\d{4})?\b"#, "<zip>"),
        ]

        map[.paymentCard] = [
            // PAN: 13-19 contiguous or space/dash-separated digits
            Rule(#"\b(?:\d[ \-]?){12,18}\d\b"#, "<pan>"),
            // CVV: 3-4 digit cluster that looks like a security code
            Rule(#"\bCVV?2?:?\s*\d{3,4}\b"#, "<cvv>"),
        ]

        map[.deviceID] = [
            // UUID v4 (IDFA/IDFV format)
            Rule(#"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-4[0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}\b"#, "<device-id>"),
            // Generic device serial: alphanumeric 8-20 chars after "serial" keyword
            Rule(#"\b(?:serial[:\s]+)[A-Z0-9]{8,20}\b"#, "<serial>"),
        ]

        map[.locationCoarse] = [
            // Decimal lat/lng pair: -90.0000 to 90.0000, -180.0000 to 180.0000
            Rule(#"-?\d{1,3}\.\d{1,6},\s*-?\d{1,3}\.\d{1,6}"#, "<location>"),
        ]

        return map
    }()

    // MARK: - Public API

    /// Redact PII patterns belonging to the requested categories in `text`.
    ///
    /// Rules are applied in ``DataHandlingCategory/sensitivityLevel`` order —
    /// highest sensitivity first — so more-specific patterns (e.g. `.paymentCard`)
    /// run before more-general ones (e.g. `.phone`).
    ///
    /// - Parameters:
    ///   - text:       The raw string that may contain PII.
    ///   - categories: The set of categories whose patterns should be applied.
    ///                 Passing an empty array returns `text` unchanged.
    /// - Returns: A new string with matched PII patterns replaced by tokens.
    public static func redact(_ text: String, categories: [DataHandlingCategory]) -> String {
        guard !categories.isEmpty else { return text }

        // Sort by descending sensitivity so critical patterns are applied first.
        let ordered = categories.sorted { $0.sensitivityLevel > $1.sensitivityLevel }

        var result = text
        for category in ordered {
            guard let rules = rulesByCategory[category] else { continue }
            for rule in rules {
                let range = NSRange(result.startIndex..., in: result)
                result = rule.regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: range,
                    withTemplate: rule.placeholder
                )
            }
        }
        return result
    }

    /// Convenience overload accepting a `Set<DataHandlingCategory>`.
    public static func redact(_ text: String, categories: Set<DataHandlingCategory>) -> String {
        redact(text, categories: Array(categories))
    }

    /// Redact all known PII categories from `text`.
    ///
    /// Equivalent to `redact(text, categories: DataHandlingCategory.allCases)`.
    public static func redactAll(_ text: String) -> String {
        redact(text, categories: DataHandlingCategory.allCases)
    }
}
