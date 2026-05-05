import Foundation

// MARK: - §43.5 Template Validator

/// Validates DeviceTemplateEditorView form fields. Pure / static — easy to unit test.
public enum DeviceTemplateValidator {

    public enum ValidationError: LocalizedError, Equatable {
        case nameEmpty
        case nameTooLong
        case familyEmpty
        case serviceNameEmpty(index: Int)
        case servicePriceInvalid(index: Int)

        public var errorDescription: String? {
            switch self {
            case .nameEmpty:
                return "Model name is required."
            case .nameTooLong:
                return "Model name must be 120 characters or fewer."
            case .familyEmpty:
                return "Device family is required."
            case .serviceNameEmpty(let i):
                return "Service \(i + 1) name is required."
            case .servicePriceInvalid(let i):
                return "Service \(i + 1) price must be a valid number greater than zero."
            }
        }

        public static func == (lhs: ValidationError, rhs: ValidationError) -> Bool {
            switch (lhs, rhs) {
            case (.nameEmpty, .nameEmpty),
                 (.nameTooLong, .nameTooLong),
                 (.familyEmpty, .familyEmpty):
                return true
            case (.serviceNameEmpty(let a), .serviceNameEmpty(let b)):  return a == b
            case (.servicePriceInvalid(let a), .servicePriceInvalid(let b)): return a == b
            default: return false
            }
        }
    }

    /// Validate a template form and return list of errors (empty = valid).
    public static func validate(
        name: String,
        family: String,
        inlineServices: [InlineService]
    ) -> [ValidationError] {
        var errors: [ValidationError] = []

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { errors.append(.nameEmpty) }
        else if trimmedName.count > 120 { errors.append(.nameTooLong) }

        let trimmedFamily = family.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedFamily.isEmpty { errors.append(.familyEmpty) }

        for (i, svc) in inlineServices.enumerated() {
            if svc.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.serviceNameEmpty(index: i))
            }
            if svc.priceCents == nil {
                errors.append(.servicePriceInvalid(index: i))
            }
        }

        return errors
    }
}
