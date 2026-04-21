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
            "<email>"
        ),
        // Card PANs — 13–19 contiguous or space/dash-separated digits
        // Matches Visa/MC/Amex/Discover card number shapes.
        Rule(
            #"\b(?:\d[ \-]?){12,18}\d\b"#,
            "<pan>"
        ),
        // US SSN  ddd-dd-dddd  or  ddddddddd
        Rule(
            #"\b(?!000|666|9\d{2})\d{3}[-\s]?(?!00)\d{2}[-\s]?(?!0000)\d{4}\b"#,
            "<ssn>"
        ),
        // Phone numbers — US-centric but broad enough to catch most formats.
        // Examples: +1 (555) 123-4567 / 555-123-4567 / 5551234567
        Rule(
            #"(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#,
            "<phone>"
        ),
        // Bearer / API tokens — "Bearer <long token>"
        Rule(
            #"Bearer\s+[A-Za-z0-9\-._~+/]+=*"#,
            "Bearer <token>"
        ),
        // Generic long base64-ish secrets (32+ chars of base64url without whitespace)
        Rule(
            #"\b[A-Za-z0-9+/\-_]{32,}={0,2}\b"#,
            "<secret>"
        ),
    ]
}
