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
        // §32 Network error redactor — strip credentials and query params from URLs
        // before they reach any log sink or telemetry payload.
        //
        // 1. Userinfo in URLs: scheme://user:pass@host → scheme://*SECRET*@host
        Rule(
            #"([a-zA-Z][a-zA-Z0-9+\-.]*://)([^@/\s]+:[^@/\s]+)@"#,
            "$1*SECRET*@"
        ),
        // 2. Query-string values: ?key=VALUE&key2=VALUE2 → ?key=*REDACTED*&…
        //    Preserves key names (useful for routing) but masks values (may be tokens / IDs).
        Rule(
            #"(?<=[?&])([^=&\s]+)=([^&\s#]+)"#,
            "$1=*REDACTED*"
        ),
        // 3. URL fragments that look like tokens (# followed by base64-ish segment)
        Rule(
            #"#[A-Za-z0-9+/\-_]{16,}={0,2}\b"#,
            "#*SECRET*"
        ),
        // Email addresses  (RFC-5321 simplified)
        Rule(
            #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
            "*CUSTOMER_EMAIL*"
        ),
        // §32.6 Credit-card BIN (first 6 digits of a PAN that appears in
        // structured log fields labelled "bin:" / "card_bin:" / "issuer_bin:").
        // Must run before the full-PAN rule so "bin:412345" → "*CARD_BIN*",
        // not left as a prefix of a larger *PAN* match.
        Rule(
            #"(?i)(?:bin|card_bin|issuer_bin)[:\s]*(\d{6})\b"#,
            "*CARD_BIN*"
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
        // §32.6 Auth / OTP codes — labelled "otp:", "auth_code:", "2fa_code:" etc.
        // 4–8 digit codes that appear alongside an explicit label.
        Rule(
            #"(?i)(?:otp|auth_code|2fa_code|verification_code|one.time)[:\s]*(\d{4,8})\b"#,
            "*AUTH_CODE*"
        ),
        // §32.6 Street addresses — "123 Main St", "42 Elm Avenue", etc.
        // Heuristic: leading number + word(s) + street-type abbreviation.
        Rule(
            #"\b\d{1,5}\s+[A-Za-z0-9\s]{2,30}\s+(?:st|ave|blvd|rd|dr|ln|ct|pl|way|cir|ter|hwy|pkwy|suite|ste|apt|unit)\.?\b"#,
            "*ADDRESS*",
            options: [.caseInsensitive]
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

    /// Replace an email body with the §32.6 placeholder.
    public static func redactEmailBody(_ input: String) -> String {
        input.isEmpty ? input : "*EMAIL_BODY*"
    }

    /// Replace a free-form address field with the §32.6 placeholder.
    /// Use when you know the string is a postal address — regex coverage is
    /// intentionally broad but misses many international formats.
    public static func redactAddress(_ input: String) -> String {
        input.isEmpty ? input : "*ADDRESS*"
    }

    // MARK: — §32.6 Field-shape detection fallback (`*LIKELY_PII*`)

    /// §32.6 — Defensive redaction pass for untagged / legacy call sites.
    ///
    /// First runs the standard `redact(_:)` rule table (which covers known
    /// labelled patterns: emails, PANs, phones, tokens, etc.), then applies a
    /// looser fallback that substitutes any remaining string still shaped like
    /// PII with the catch-all placeholder `*LIKELY_PII*`.
    ///
    /// False positives are acceptable; raw PII leaks are not.  Use this when a
    /// string is being serialized into a telemetry payload but the call site
    /// did not declare the field type up front.
    public static func redactWithLikelyPIIFallback(_ input: String) -> String {
        var result = redact(input)
        for rule in fallbackRules {
            result = rule.regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: rule.placeholder
            )
        }
        return result
    }

    /// Looser shape-detection rules. They run *after* the strict table so
    /// labelled / well-known patterns keep their canonical placeholders.
    private static let fallbackRules: [Rule] = [
        // Phone-shaped: any 7+ contiguous digit run that survived the strict
        // pass (e.g. partially-formatted numbers without separators).
        Rule(
            #"\b\d{7,}\b"#,
            "*LIKELY_PII*"
        ),
        // Email-shaped without TLD enforcement (catches obfuscated "user[at]domain")
        Rule(
            #"[A-Za-z0-9._%+\-]+\s*(?:\[?(?:at|@)\]?)\s*[A-Za-z0-9.\-]+"#,
            "*LIKELY_PII*"
        ),
        // Token-shaped: 20+ char alphanumeric mixed-case-or-with-digits run
        // (catches pre-base64 secrets the strict 32+ rule missed).
        Rule(
            #"\b(?=[A-Za-z0-9]{20,}\b)(?=.*\d)(?=.*[A-Za-z])[A-Za-z0-9]{20,}\b"#,
            "*LIKELY_PII*"
        ),
    ]
}
