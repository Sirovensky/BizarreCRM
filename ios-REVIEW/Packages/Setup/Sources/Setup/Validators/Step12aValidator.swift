import Foundation

// MARK: - Step12aValidator  (Theme)
// Theme must be one of three valid values.

public enum AppThemeChoice: String, CaseIterable, Sendable, Equatable {
    case system = "system"
    case dark   = "dark"
    case light  = "light"

    public var displayName: String {
        switch self {
        case .system: return "System (recommended)"
        case .dark:   return "Dark"
        case .light:  return "Light"
        }
    }
}

public enum Step12aValidator {

    public static func validate(_ theme: AppThemeChoice) -> ValidationResult {
        // All three enum cases are valid; the type system enforces this,
        // but we keep an explicit validator for the TDD contract.
        return .valid
    }

    public static func isNextEnabled(theme: AppThemeChoice) -> Bool {
        validate(theme).isValid
    }
}
