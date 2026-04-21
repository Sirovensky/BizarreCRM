import Foundation

// MARK: - Step6Validator  (Tax Setup)
// Name non-empty; rate in [0, 30].

public enum Step6Validator {

    public static func validateName(_ name: String) -> ValidationResult {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid("Tax name is required.")
        }
        guard trimmed.count <= 100 else {
            return .invalid("Tax name is too long (max 100 characters).")
        }
        return .valid
    }

    public static func validateRate(_ rateText: String) -> ValidationResult {
        let trimmed = rateText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid("Tax rate is required.")
        }
        guard let value = Double(trimmed) else {
            return .invalid("Enter a numeric rate (e.g. 8.25).")
        }
        guard value >= 0 else {
            return .invalid("Tax rate cannot be negative.")
        }
        guard value <= 30 else {
            return .invalid("Tax rate cannot exceed 30%.")
        }
        return .valid
    }

    public static func isNextEnabled(name: String, rateText: String) -> Bool {
        validateName(name).isValid && validateRate(rateText).isValid
    }
}
