import Foundation

// MARK: - Step10Validator  (SMS Setup)
// If provider != .skip, fromNumber is required.

public enum SmsProvider: String, CaseIterable, Sendable, Equatable {
    case twilio      = "twilio"
    case managed     = "bizarrecrm"
    case bandwidth   = "bandwidth"
    case skip        = "skip"

    public var displayName: String {
        switch self {
        case .twilio:    return "Twilio"
        case .managed:   return "BizarreCRM Managed"
        case .bandwidth: return "Bandwidth"
        case .skip:      return "Skip for now"
        }
    }
}

public enum Step10Validator {

    public static func validateFromNumber(_ number: String, provider: SmsProvider) -> ValidationResult {
        guard provider != .skip else { return .valid }
        let trimmed = number.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid("A from-number is required for the selected provider.")
        }
        return .valid
    }

    public static func isNextEnabled(fromNumber: String, provider: SmsProvider) -> Bool {
        validateFromNumber(fromNumber, provider: provider).isValid
    }
}
