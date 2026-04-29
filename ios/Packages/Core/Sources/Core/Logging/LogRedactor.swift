import Foundation

// §32.6 PII / secrets redaction
// Phase 0 foundation

/// Stateless PII redactor.  Pass any log string through `redact(_:)` before it
/// enters an event payload, OSLog message, or diagnostic bundle.
///
/// Patterns applied in order; all matches are replaced with placeholder tokens.
/// False positives are acceptable; raw PII leaks are not.
public enum LogRedactor {

    // MARK: — Public API

    /// Return a copy of `input` with all known PII patterns replaced by placeholders.
    public static func redact(_ input: String) -> String {
        var result = input
        for rule in rules {
            result = rule.regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: rule.placeholder
            )
        }
        return result
    }

    // MARK: — Private rule table

    private struct Rule {
        let regex: NSRegularExpression
        let placeholder: String

        init(_ pattern: String, _ placeholder: String, options: NSRegularExpression.Options = [.caseInsensitive]) {
            // Force-try is intentional: patterns are compile-time constants; a typo
            // is a programming error that should crash tests immediately.
            // swiftlint:disable:next force_try
            self.regex = try! NSRegularExpression(pattern: pattern, options: options)
            self.placeholder = placeholder
        }
    }

    // Patterns are ordered: more-specific before more-general.
    private static let rules: [Rule] = [
        // Email addresses  (RFC-5321 simplified)
        Rule(
            #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
            "*CUSTOMER_EMAIL*"
        ),
        // Card PANs — 13–19 contiguous or space/dash-separated digits
        // Matches Visa/MC/Amex/Discover card number shapes.
        Rule(
            #"\b(?:\d[ \-]?){12,18}\d\b"#,
            "*PAN*"
        ),
        // US SSN  ddd-dd-dddd  or  ddddddddd
        Rule(
            #"\b(?!000|666|9\d{2})\d{3}[-\s]?(?!00)\d{2}[-\s]?(?!0000)\d{4}\b"#,
            "*SSN*"
        ),
        // Phone numbers — US-centric but broad enough to catch most formats.
        // Examples: +1 (555) 123-4567 / 555-123-4567 / 5551234567
        Rule(
            #"(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#,
            "*CUSTOMER_PHONE*"
        ),
        // IMEI — 15 consecutive digits (Luhn-valid shape; false-positive rate is low enough)
        Rule(
            #"\b\d{15}\b"#,
            "*IMEI*"
        ),
        // Device serial — common Apple serial format: 10–14 alphanumeric chars labelled "serial:" or "sn:"
        Rule(
            #"(?i)(?:serial|sn)[:\s#]*([A-Z0-9]{10,14})\b"#,
            "*DEVICE_SERIAL*"
        ),
        // Apple push token — 64-char hex string (APNs device token)
        Rule(
            #"\b[0-9a-fA-F]{64}\b"#,
            "*PUSH_TOKEN*"
        ),
        // Pairing / unlock codes — 4-to-8 digit PIN blocks after labelled keys
        Rule(
            #"(?i)(?:passcode|pin|code)[:\s]*\d{4,8}\b"#,
            "*DEVICE_PASSCODE*"
        ),
        // Bearer / API tokens — "Bearer <long token>"
        Rule(
            #"Bearer\s+[A-Za-z0-9\-._~+/]+=*"#,
            "Bearer *SECRET*"
        ),
        // Generic long base64-ish secrets (32+ chars of base64url without whitespace)
        Rule(
            #"\b[A-Za-z0-9+/\-_]{32,}={0,2}\b"#,
            "*SECRET*"
        ),
    ]

    // MARK: — §32.6 Convenience wrappers for fields without reliable regex shape

    /// Replace a customer name field with the §32.6 placeholder.
    /// Use when you know the string is a customer name — names have no reliable regex.
    public static func redactCustomerName(_ input: String) -> String {
        input.isEmpty ? input : "*CUSTOMER_NAME*"
    }

    /// Replace a free-form note / memo body with the §32.6 placeholder.
    public static func redactNoteBody(_ input: String) -> String {
        input.isEmpty ? input : "*NOTE_BODY*"
    }

    /// Replace a free-form search query with the §32.6 placeholder.
    public static func redactQuery(_ input: String) -> String {
        input.isEmpty ? input : "*QUERY*"
    }

    /// Replace an SMS / email message body with the §32.6 placeholder.
    public static func redactMessageBody(_ input: String) -> String {
        input.isEmpty ? input : "*SMS_BODY*"
    }
}
