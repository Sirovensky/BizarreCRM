import Foundation

// MARK: - RetryAfterParser

/// Parses the value of an HTTP `Retry-After` header.
///
/// Supports two formats per RFC 7231 §7.1.3:
/// - **Delta-seconds**: `120`
/// - **HTTP-date**: `Wed, 21 Oct 2015 07:28:00 GMT`
///
/// This is a pure value-type namespace (all members are static).
public enum RetryAfterParser {

    // MARK: Public API

    /// Parse a `Retry-After` header value and return the delay in seconds
    /// from `now` (or the `referenceDate` supplied in tests).
    ///
    /// Returns `nil` if the value is empty, unparseable, or the resolved date
    /// is already in the past.
    ///
    /// - Parameters:
    ///   - headerValue: Raw string value of the `Retry-After` header.
    ///   - referenceDate: "now" reference for HTTP-date calculation. Defaults to `Date()`.
    /// - Returns: Positive delay in seconds, or `nil`.
    public static func parse(
        _ headerValue: String,
        referenceDate: Date = Date()
    ) -> TimeInterval? {
        let trimmed = headerValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Attempt 1: delta-seconds (pure digits, possibly with leading space)
        if let seconds = parseSeconds(trimmed) {
            return seconds > 0 ? seconds : nil
        }

        // Attempt 2: HTTP-date
        if let date = parseHTTPDate(trimmed) {
            let delay = date.timeIntervalSince(referenceDate)
            return delay > 0 ? delay : nil
        }

        return nil
    }

    // MARK: Private helpers

    /// Parses a non-negative integer string as seconds.
    private static func parseSeconds(_ value: String) -> TimeInterval? {
        guard let integer = Int(value), integer >= 0 else { return nil }
        return TimeInterval(integer)
    }

    /// Parses an HTTP-date string using the three formats mandated by RFC 7231.
    private static func parseHTTPDate(_ value: String) -> Date? {
        for formatter in httpDateFormatters {
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    // MARK: HTTP-date formatters (RFC 7231 §7.1.1.1)

    /// All three HTTP-date formats: preferred (IMF-fixdate), RFC 850, asctime.
    private static let httpDateFormatters: [DateFormatter] = {
        // All HTTP-date formats are locale- and timezone-independent.
        let locale = Locale(identifier: "en_US_POSIX")
        let tz = TimeZone(abbreviation: "GMT")!

        func make(_ format: String) -> DateFormatter {
            let f = DateFormatter()
            f.locale = locale
            f.timeZone = tz
            f.dateFormat = format
            return f
        }

        return [
            // IMF-fixdate: Mon, 02 Jan 2006 15:04:05 GMT
            make("EEE, dd MMM yyyy HH:mm:ss zzz"),
            // RFC 850: Monday, 02-Jan-06 15:04:05 GMT
            make("EEEE, dd-MMM-yy HH:mm:ss zzz"),
            // asctime: Mon Jan  2 15:04:05 2006  (two spaces before single-digit day)
            make("EEE MMM d HH:mm:ss yyyy"),
        ]
    }()
}
