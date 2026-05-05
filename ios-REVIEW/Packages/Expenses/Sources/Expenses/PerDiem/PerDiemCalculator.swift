import Foundation

// MARK: - PerDiemCalculator

/// Pure stateless per-diem calculator.
/// Calendar: Gregorian; locale: en_US_POSIX. No mutation of inputs.
public enum PerDiemCalculator {

    // MARK: - Day counting

    /// Returns the number of calendar days covered by `[startDate, endDate]`
    /// (inclusive on both ends). Returns 0 if `endDate < startDate`.
    public static func days(from startDate: Date, to endDate: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let start = cal.startOfDay(for: startDate)
        let end   = cal.startOfDay(for: endDate)
        guard end >= start else { return 0 }
        let components = cal.dateComponents([.day], from: start, to: end)
        return (components.day ?? 0) + 1  // inclusive
    }

    // MARK: - Total

    /// Returns total reimbursement in cents: `days × ratePerDayCents`.
    public static func totalCents(days: Int, ratePerDayCents: Int) -> Int {
        max(0, days) * ratePerDayCents
    }

    /// Convenience: takes date range and rate, returns (days, totalCents).
    public static func calculate(
        from startDate: Date,
        to endDate: Date,
        ratePerDayCents: Int
    ) -> (days: Int, totalCents: Int) {
        let d = days(from: startDate, to: endDate)
        return (d, totalCents(days: d, ratePerDayCents: ratePerDayCents))
    }
}
