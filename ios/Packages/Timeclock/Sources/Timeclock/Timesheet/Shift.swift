import Foundation

// MARK: - Shift

/// A single worked shift (clock-in → clock-out pair).
///
/// Duration is in rational minutes (Int) per architectural rule.
public struct Shift: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let employeeId: Int64
    /// ISO-8601 UTC string.
    public let clockIn: String
    /// ISO-8601 UTC string; `nil` while shift is ongoing.
    public let clockOut: String?
    /// Total minutes worked as reported by the server (after server-side
    /// break deductions). Client uses this for display; `OvertimeCalculator`
    /// accepts raw minutes and deducts unpaid breaks itself.
    public let totalMinutes: Int?
    /// Designates whether this shift falls on a holiday date.
    public let isHoliday: Bool

    public init(
        id: Int64,
        employeeId: Int64,
        clockIn: String,
        clockOut: String? = nil,
        totalMinutes: Int? = nil,
        isHoliday: Bool = false
    ) {
        self.id = id
        self.employeeId = employeeId
        self.clockIn = clockIn
        self.clockOut = clockOut
        self.totalMinutes = totalMinutes
        self.isHoliday = isHoliday
    }

    enum CodingKeys: String, CodingKey {
        case id
        case employeeId  = "employee_id"
        case clockIn     = "clock_in"
        case clockOut    = "clock_out"
        case totalMinutes = "total_minutes"
        case isHoliday   = "is_holiday"
    }

    // MARK: - Computed helpers

    /// Raw duration in minutes derived purely from clock-in/out timestamps.
    /// Returns `nil` when shift is still open or timestamps are unparseable.
    public var rawDurationMinutes: Int? {
        guard let out = clockOut,
              let inDate = ShiftTimestampParser.parse(clockIn),
              let outDate = ShiftTimestampParser.parse(out)
        else { return nil }
        return max(0, Int(outDate.timeIntervalSince(inDate) / 60))
    }

    /// Calendar day of clock-in (UTC). Used by `OvertimeCalculator`.
    public func clockInDayComponents(calendar: Calendar = .autoupdatingCurrent) -> DateComponents? {
        guard let d = ShiftTimestampParser.parse(clockIn) else { return nil }
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.dateComponents([.year, .month, .day, .weekday], from: d)
    }
}

// MARK: - ShiftTimestampParser

/// BUGHUNT-2026-05-18: `ISO8601DateFormatter()` with default options rejects
/// both Node `Date.toISOString()` millisecond strings (`...123Z`) AND SQLite's
/// SQL-style `YYYY-MM-DD HH:MM:SS` (no T, no Z) that the server emits from
/// `datetime('now')` / `CURRENT_TIMESTAMP`. The clock_entries column accumulates
/// BOTH formats (server has a `parseSqliteTs` helper that normalises them).
/// Without this, `rawDurationMinutes` always returned nil and
/// `OvertimeCalculator` bucketed every shift under "unknown" dayKey — daily +
/// weekly OT thresholds were never applied, employees saw zero overtime no
/// matter how many hours they worked.
enum ShiftTimestampParser {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let sqlUTC: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        isoFractional.date(from: raw)
            ?? isoPlain.date(from: raw)
            ?? sqlUTC.date(from: raw)
    }
}
