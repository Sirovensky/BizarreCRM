import Foundation

// MARK: - SetupStep enum
// §36: 13-step first-run onboarding wizard.
// Steps 1–3 are fully implemented; 4–13 show PlaceholderStepView.

public enum SetupStep: Int, CaseIterable, Sendable {
    case welcome           = 1
    case companyInfo       = 2
    case logo              = 3
    // Steps 4–13 implemented progressively
    case timezoneLocale    = 4   // §36.2 Step 4 — TZ + currency + locale
    case businessHours     = 5   // §36.2 Step 5 — Business hours
    case taxSetup          = 6   // §36.2 Step 6 — Tax setup
    case paymentMethods    = 7   // §36.2 Step 7 — Payment methods
    case firstLocation     = 8   // §36.2 Step 8 — First location
    case teammates         = 9
    case smsSetup          = 10
    case deviceTemplates   = 11
    case dataImport        = 12
    case complete          = 13

    public var title: String {
        switch self {
        case .welcome:           return "Welcome"
        case .companyInfo:       return "Company Info"
        case .logo:              return "Logo"
        case .timezoneLocale:    return "Timezone & Locale"
        case .businessHours:     return "Business Hours"
        case .taxSetup:          return "Tax Setup"
        case .paymentMethods:    return "Payment Methods"
        case .firstLocation:     return "First Location"
        case .teammates:         return "Teammates"
        case .smsSetup:          return "SMS Setup"
        case .deviceTemplates:   return "Device Templates"
        case .dataImport:        return "Data Import"
        case .complete:          return "Complete"
        }
    }

    public var isImplemented: Bool {
        switch self {
        case .welcome, .companyInfo, .logo,
             .timezoneLocale, .businessHours, .taxSetup,
             .paymentMethods, .firstLocation:
            return true
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
