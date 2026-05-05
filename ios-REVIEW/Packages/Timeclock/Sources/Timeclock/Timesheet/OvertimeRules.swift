import Foundation

// MARK: - OvertimeRules

/// Per-tenant configurable overtime rules.
///
/// Federal default: 40 hr/wk OT at 1.5x; no daily OT; no holiday OT.
/// California example: 8 hr/day OT, 12 hr/day double-time, 40 hr/wk OT.
public struct OvertimeRules: Sendable, Hashable {

    // MARK: Weekly thresholds (minutes)

    /// Minutes per week before weekly OT kicks in. Federal default: 2400 (40 hrs).
    public let weeklyOvertimeThresholdMinutes: Int
    /// Multiplier for weekly OT hours (federal: 1.5).
    public let weeklyOvertimeMultiplier: Double

    // MARK: Daily thresholds (minutes)

    /// Minutes per day before daily OT kicks in. 0 = no daily OT (federal).
    public let dailyOvertimeThresholdMinutes: Int
    /// Multiplier for daily OT hours (CA: 1.5).
    public let dailyOvertimeMultiplier: Double

    /// Minutes per day before double-time kicks in. 0 = no double-time (federal).
    public let dailyDoubleTimeThresholdMinutes: Int
    /// Multiplier for double-time hours (CA: 2.0).
    public let dailyDoubleTimeMultiplier: Double

    // MARK: Holiday

    /// Multiplier for hours worked on designated holidays. 1.0 = no holiday premium.
    public let holidayMultiplier: Double
    /// Set of calendar dates designated as holidays (year-agnostic: month+day only).
    public let holidayMonthDays: Set<MonthDay>

    // MARK: - Federal US defaults

    public static let federal = OvertimeRules(
        weeklyOvertimeThresholdMinutes: 2400,   // 40 hours
        weeklyOvertimeMultiplier: 1.5,
        dailyOvertimeThresholdMinutes: 0,       // no daily OT
        dailyOvertimeMultiplier: 1.5,
        dailyDoubleTimeThresholdMinutes: 0,     // no double-time
        dailyDoubleTimeMultiplier: 2.0,
        holidayMultiplier: 1.0,
        holidayMonthDays: []
    )

    // MARK: - California defaults

    public static let california = OvertimeRules(
        weeklyOvertimeThresholdMinutes: 2400,   // 40 hours
        weeklyOvertimeMultiplier: 1.5,
        dailyOvertimeThresholdMinutes: 480,     // 8 hours
        dailyOvertimeMultiplier: 1.5,
        dailyDoubleTimeThresholdMinutes: 720,   // 12 hours
        dailyDoubleTimeMultiplier: 2.0,
        holidayMultiplier: 1.0,
        holidayMonthDays: []
    )

    public init(
        weeklyOvertimeThresholdMinutes: Int = 2400,
        weeklyOvertimeMultiplier: Double = 1.5,
        dailyOvertimeThresholdMinutes: Int = 0,
        dailyOvertimeMultiplier: Double = 1.5,
        dailyDoubleTimeThresholdMinutes: Int = 0,
        dailyDoubleTimeMultiplier: Double = 2.0,
        holidayMultiplier: Double = 1.0,
        holidayMonthDays: Set<MonthDay> = []
    ) {
        self.weeklyOvertimeThresholdMinutes = weeklyOvertimeThresholdMinutes
        self.weeklyOvertimeMultiplier = weeklyOvertimeMultiplier
        self.dailyOvertimeThresholdMinutes = dailyOvertimeThresholdMinutes
        self.dailyOvertimeMultiplier = dailyOvertimeMultiplier
        self.dailyDoubleTimeThresholdMinutes = dailyDoubleTimeThresholdMinutes
        self.dailyDoubleTimeMultiplier = dailyDoubleTimeMultiplier
        self.holidayMultiplier = holidayMultiplier
        self.holidayMonthDays = holidayMonthDays
    }
}

// MARK: - MonthDay

/// A month+day pair for year-agnostic holiday comparisons.
public struct MonthDay: Sendable, Hashable {
    public let month: Int  // 1-12
    public let day: Int    // 1-31

    public init(month: Int, day: Int) {
        self.month = month
        self.day = day
    }
}
