import Foundation

// MARK: - Step7Validator  (Payment Methods)
// At least one method must be enabled.

public enum Step7Validator {

    public static func isNextEnabled(methods: Set<PaymentMethod>) -> Bool {
        !methods.isEmpty
    }

    public static func validate(methods: Set<PaymentMethod>) -> ValidationResult {
        guard !methods.isEmpty else {
            return .invalid("At least one payment method must be enabled.")
        }
        return .valid
    }
}
