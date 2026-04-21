import Foundation

// MARK: - Step8Validator  (First Location)
// Name and address are required.

public enum Step8Validator {

    public static func validateName(_ name: String) -> ValidationResult {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid("Location name is required.")
        }
        return .valid
    }

    public static func validateAddress(_ address: String) -> ValidationResult {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid("Location address is required.")
        }
        return .valid
    }

    public static func isNextEnabled(name: String, address: String) -> Bool {
        validateName(name).isValid && validateAddress(address).isValid
    }
}
