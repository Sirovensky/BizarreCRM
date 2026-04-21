import Foundation

// MARK: - SetupStep enum
// §36: 13-step first-run onboarding wizard.
// Steps 1–3 are fully implemented; 4–13 show PlaceholderStepView.

public enum SetupStep: Int, CaseIterable, Sendable {
    case welcome       = 1
    case companyInfo   = 2
    case logo          = 3
    // Steps 4–13 — placeholder until subsequent PRs
    case theme         = 4
    case hours         = 5
    case payment       = 6
    case tax           = 7
    case sms           = 8
    case locations     = 9
    case deviceTemplates = 10
    case teammates     = 11
    case dataImport    = 12
    case complete      = 13

    public var title: String {
        switch self {
        case .welcome:         return "Welcome"
        case .companyInfo:     return "Company Info"
        case .logo:            return "Logo"
        case .theme:           return "Theme"
        case .hours:           return "Business Hours"
        case .payment:         return "Payment"
        case .tax:             return "Tax"
        case .sms:             return "SMS"
        case .locations:       return "Locations"
        case .deviceTemplates: return "Device Templates"
        case .teammates:       return "Teammates"
        case .dataImport:      return "Data Import"
        case .complete:        return "Complete"
        }
    }

    public var isImplemented: Bool {
        switch self {
        case .welcome, .companyInfo, .logo: return true
        default: return false
        }
    }

    public static let totalCount: Int = SetupStep.allCases.count

    public var next: SetupStep? {
        SetupStep(rawValue: rawValue + 1)
    }

    public var previous: SetupStep? {
        SetupStep(rawValue: rawValue - 1)
    }
}
