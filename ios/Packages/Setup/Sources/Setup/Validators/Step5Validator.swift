import Foundation

// MARK: - Step5Validator  (Business Hours)
// At least one day must be open.

public enum Step5Validator {

    public static func isNextEnabled(hours: [BusinessDay]) -> Bool {
        hours.contains { $0.isOpen }
    }

    /// Returns a validation result for the overall business hours configuration.
    public static func validate(hours: [BusinessDay]) -> ValidationResult {
        guard !hours.isEmpty else {
            return .invalid("Business hours configuration is empty.")
        }
        guard hours.contains(where: { $0.isOpen }) else {
            return .invalid("At least one day must be marked as open.")
        }
        // Validate that open-time < close-time for all open days
        for day in hours where day.isOpen {
            if let openHour = day.openAt.hour, let closeHour = day.closeAt.hour {
                let openMin = openHour * 60 + (day.openAt.minute ?? 0)
                let closeMin = closeHour * 60 + (day.closeAt.minute ?? 0)
                if openMin >= closeMin {
                    return .invalid("\(day.weekdayName): open time must be before close time.")
                }
            }
        }
        return .valid
    }
}
