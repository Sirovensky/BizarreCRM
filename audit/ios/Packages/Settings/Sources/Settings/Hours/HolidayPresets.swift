import Foundation

// MARK: - §19 HolidayPresets

/// Built-in US holiday presets. Users can bulk-add these to their tenant
/// holiday list. All dates use 2026 as the reference year; recurrence is
/// `.yearly` so they fire every year.
public enum HolidayPresets {

    // MARK: - Preset list

    public static let usHolidays: [HolidayPreset] = [
        HolidayPreset(
            id: "us.newyear",
            name: "New Year's Day",
            month: 1, day: 1
        ),
        HolidayPreset(
            id: "us.mlkday",
            name: "MLK Day",
            month: 1, day: 19 // 3rd Monday Jan — approximated; real rule is nth-weekday
        ),
        HolidayPreset(
            id: "us.memorial",
            name: "Memorial Day",
            month: 5, day: 25 // last Monday of May — approximated
        ),
        HolidayPreset(
            id: "us.juneteenth",
            name: "Juneteenth",
            month: 6, day: 19
        ),
        HolidayPreset(
            id: "us.independence",
            name: "Independence Day",
            month: 7, day: 4
        ),
        HolidayPreset(
            id: "us.labor",
            name: "Labor Day",
            month: 9, day: 7 // 1st Monday of September — approximated
        ),
        HolidayPreset(
            id: "us.veterans",
            name: "Veterans Day",
            month: 11, day: 11
        ),
        HolidayPreset(
            id: "us.thanksgiving",
            name: "Thanksgiving Day",
            month: 11, day: 26 // 4th Thursday of November — approximated
        ),
        HolidayPreset(
            id: "us.christmas",
            name: "Christmas Day",
            month: 12, day: 25
        )
    ]

    // MARK: - Factory

    /// Converts a preset into a concrete ``HolidayException`` for a given year.
    public static func makeException(
        from preset: HolidayPreset,
        year: Int = Calendar.current.component(.year, from: Date()),
        isOpen: Bool = false
    ) -> HolidayException? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        var dc = DateComponents()
        dc.year = year
        dc.month = preset.month
        dc.day = preset.day
        guard let date = cal.date(from: dc) else { return nil }

        return HolidayException(
            id: "\(preset.id)-\(year)",
            date: date,
            isOpen: isOpen,
            openAt: nil,
            closeAt: nil,
            reason: preset.name,
            recurring: .yearly
        )
    }

    /// Converts all presets to ``HolidayException`` values for the current year.
    public static func allExceptions(
        isOpen: Bool = false
    ) -> [HolidayException] {
        usHolidays.compactMap { makeException(from: $0, isOpen: isOpen) }
    }
}

// MARK: - HolidayPreset model

public struct HolidayPreset: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let month: Int
    public let day: Int

    public init(id: String, name: String, month: Int, day: Int) {
        self.id = id
        self.name = name
        self.month = month
        self.day = day
    }
}
