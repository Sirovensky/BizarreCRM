#if DEBUG
import Foundation

// §31 Test Fixtures Helpers — ISO8601Factory
// Deterministic date builders for fixture data.
// All dates are in UTC so tests pass regardless of the device's locale.

/// Builds ISO 8601 date strings suitable for fixture JSON payloads.
///
/// All output is UTC (`Z` suffix) so fixtures produce identical `Date` values
/// on every device and CI runner, regardless of the system time zone.
///
/// Usage:
/// ```swift
/// let payload = """
///     { "createdAt": "\(ISO8601Factory.daysAgo(3))",
///       "updatedAt": "\(ISO8601Factory.hoursAgo(1))" }
/// """
/// ```
public enum ISO8601Factory {

    // MARK: — Formatter

    /// Build a fresh formatter per call to avoid Sendable issues with
    /// ISO8601DateFormatter (not Sendable in Swift 6).
    private static func makeFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")!
        return f
    }

    // MARK: — Public API

    /// Returns an ISO 8601 string representing the current instant (UTC).
    ///
    /// Note: uses `Date()` at call time, so repeated calls produce different strings.
    /// Prefer the offset helpers (`hoursAgo`, `daysAgo`) when you need a stable value.
    public static func now() -> String {
        makeFormatter().string(from: Date())
    }

    /// Returns an ISO 8601 string for `n` hours before the call instant (UTC).
    ///
    /// - Parameter n: Number of hours to subtract. Must be ≥ 0.
    public static func hoursAgo(_ n: Int) -> String {
        let date = Date(timeIntervalSinceNow: -Double(n) * 3600)
        return makeFormatter().string(from: date)
    }

    /// Returns an ISO 8601 string for `n` calendar days before the call instant (UTC).
    ///
    /// - Parameter n: Number of days to subtract. Must be ≥ 0.
    public static func daysAgo(_ n: Int) -> String {
        let date = Date(timeIntervalSinceNow: -Double(n) * 86_400)
        return makeFormatter().string(from: date)
    }

    /// Returns an ISO 8601 string for midnight UTC on a specific absolute date.
    ///
    /// Useful when you need a completely stable, human-readable fixture date.
    ///
    /// - Parameters:
    ///   - year:  Four-digit year.
    ///   - month: Month (1-12).
    ///   - day:   Day (1-31).
    /// - Returns: `"<year>-<month>-<day>T00:00:00.000Z"` or `nil` if the components
    ///            don't form a valid date.
    public static func utcMidnight(year: Int, month: Int, day: Int) -> String? {
        var components = DateComponents()
        components.year   = year
        components.month  = month
        components.day    = day
        components.hour   = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let calendar = Calendar(identifier: .iso8601)
        guard let date = calendar.date(from: components) else { return nil }
        return makeFormatter().string(from: date)
    }

    // MARK: — Convenience Date accessors

    /// Returns a `Date` for `n` hours ago (avoids string round-tripping in tests
    /// that work purely with `Date` values).
    public static func dateHoursAgo(_ n: Int) -> Date {
        Date(timeIntervalSinceNow: -Double(n) * 3600)
    }

    /// Returns a `Date` for `n` days ago.
    public static func dateDaysAgo(_ n: Int) -> Date {
        Date(timeIntervalSinceNow: -Double(n) * 86_400)
    }
}
#endif
