import Foundation

// MARK: - §28.7 Crash logs — PII scrubbing via symbolication hooks
//
// Apple's crash reporter captures stack frames and breadcrumb context that
// our app supplies. Frames themselves never contain PII, but
// breadcrumbs / `setKeyValue` payloads / log lines that ride along do.
// This scrubber is the single sanitiser invoked from the crash-reporter's
// `beforeSend`-equivalent hook before a crash payload is uploaded.
//
// Wired by `CrashReporter` (existing) before symbolication output and
// before any breadcrumb is persisted.

/// Pure-function PII redactor for crash-bound strings. Never throws,
/// never allocates additional resources beyond the resulting string.
public enum CrashLogPIIScrubber: Sendable {

    // MARK: - Patterns

    /// Email — RFC-5322 simplified.
    private static let email = try? NSRegularExpression(
        pattern: #"[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}"#,
        options: []
    )

    /// Phone — North-American & E.164. Conservative to avoid eating ticket IDs.
    private static let phone = try? NSRegularExpression(
        pattern: #"\+?1?[\s.-]?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b"#,
        options: []
    )

    /// PAN-shaped digit run (13–19 digits, optionally space/dash separated).
    /// We never handle PAN per §28 but if a third-party SDK ever leaks one
    /// into a log line we still want it scrubbed.
    private static let pan = try? NSRegularExpression(
        pattern: #"\b(?:\d[ -]*?){13,19}\b"#,
        options: []
    )

    /// JWT — three base64url segments separated by dots.
    private static let jwt = try? NSRegularExpression(
        pattern: #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#,
        options: []
    )

    /// Bearer / Basic / API-key auth headers that may appear in log strings.
    private static let bearerHeader = try? NSRegularExpression(
        pattern: #"(?i)\b(Bearer|Basic|Token)\s+[A-Za-z0-9._\-+/=]+"#,
        options: []
    )

    // MARK: - Public API

    /// Returns `input` with all known PII patterns replaced by typed
    /// placeholders (`<email>`, `<phone>`, `<pan>`, `<jwt>`, `<auth>`).
    /// The placeholder choice is deliberate so triage engineers can still
    /// see *what* was scrubbed without seeing *who*.
    public static func scrub(_ input: String) -> String {
        var s = input
        s = replace(s, regex: jwt, with: "<jwt>")
        s = replace(s, regex: bearerHeader, with: "<auth>")
        s = replace(s, regex: email, with: "<email>")
        s = replace(s, regex: phone, with: "<phone>")
        s = replace(s, regex: pan, with: "<pan>")
        return s
    }

    /// Convenience for breadcrumb maps. Keys are preserved (they're
    /// engineer-authored), values are scrubbed.
    public static func scrub(metadata: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        out.reserveCapacity(metadata.count)
        for (k, v) in metadata {
            out[k] = scrub(v)
        }
        return out
    }

    // MARK: - Private

    private static func replace(_ input: String, regex: NSRegularExpression?, with template: String) -> String {
        guard let regex else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(
            in: input,
            options: [],
            range: range,
            withTemplate: template
        )
    }
}
