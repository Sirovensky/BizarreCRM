import Foundation

// MARK: - ComparePeriod
//
// Describes which prior period to overlay on the current chart.
// Used by CompareOverlay and ComparisonVariance to derive the prior
// date window from a given current window — without any new network
// calls (the prior window is fetched through the same ReportsRepository
// methods the main ViewModel already uses).

public enum ComparePeriod: Sendable, Hashable {
    /// The same-length window ending exactly 7 days before the current window start.
    case previousWeek
    /// The same-length window ending exactly 30 days before the current window start.
    case previousMonth
    /// The same-length window ending exactly 365 days before the current window start.
    case previousYear
    /// Caller-supplied arbitrary interval.
    case custom(DateInterval)

    // MARK: - Display

    public var displayLabel: String {
        switch self {
        case .previousWeek:   return "Prev Week"
        case .previousMonth:  return "Prev Month"
        case .previousYear:   return "Prev Year"
        case .custom:         return "Custom"
        }
    }

    // MARK: - Date math

    /// Returns the prior `DateInterval` given the *current* interval.
    ///
    /// - For `.previousWeek` / `.previousMonth` / `.previousYear` the prior
    ///   interval has the same duration as `current` but is shifted back by
    ///   7 / 30 / 365 days respectively.  This keeps the point-count equal so
    ///   the chart lines align visually.
    /// - For `.custom` the stored interval is returned unchanged.
    public func priorInterval(relativeTo current: DateInterval) -> DateInterval {
        switch self {
        case .previousWeek:
            return shifted(current, by: -7 * 86400)
        case .previousMonth:
            return shifted(current, by: -30 * 86400)
        case .previousYear:
            return shifted(current, by: -365 * 86400)
        case .custom(let interval):
            return interval
        }
    }

    // MARK: - ISO-8601 helpers

    /// Returns (from, to) ISO-8601 full-date strings for the prior period.
    public func priorDateStrings(
        relativeTo current: DateInterval,
        formatter: ISO8601DateFormatter = ISO8601DateFormatter.compareFullDate()
    ) -> (from: String, to: String) {
        let prior = priorInterval(relativeTo: current)
        return (formatter.string(from: prior.start), formatter.string(from: prior.end))
    }

    // MARK: - Private

    private func shifted(_ interval: DateInterval, by seconds: TimeInterval) -> DateInterval {
        DateInterval(
            start: interval.start.addingTimeInterval(seconds),
            duration: interval.duration
        )
    }
}

// MARK: - Equatable (needed because DateInterval is not auto-synthesised for enums)

extension ComparePeriod: Equatable {
    public static func == (lhs: ComparePeriod, rhs: ComparePeriod) -> Bool {
        switch (lhs, rhs) {
        case (.previousWeek,  .previousWeek):  return true
        case (.previousMonth, .previousMonth): return true
        case (.previousYear,  .previousYear):  return true
        case (.custom(let a), .custom(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - ISO8601DateFormatter convenience

extension ISO8601DateFormatter {
    /// Full-date formatter (YYYY-MM-DD) — shared default for the Compare layer.
    public static func compareFullDate() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }
}
