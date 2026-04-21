import Foundation

// MARK: - SetupStep enum
// §36: 14-step first-run onboarding wizard (12a = Theme is a full step).
// Steps 1–8 are fully implemented; 9–14 implemented in §36.2 phase 2 PR.

public enum SetupStep: Int, CaseIterable, Sendable {
    case welcome           = 1
    case companyInfo       = 2
    case logo              = 3
    case timezoneLocale    = 4   // §36.2 Step 4 — TZ + currency + locale
    case businessHours     = 5   // §36.2 Step 5 — Business hours
    case taxSetup          = 6   // §36.2 Step 6 — Tax setup
    case paymentMethods    = 7   // §36.2 Step 7 — Payment methods
    case firstLocation     = 8   // §36.2 Step 8 — First location
    case teammates         = 9   // §36.2 Step 9 — Invite teammates
    case smsSetup          = 10  // §36.2 Step 10 — SMS setup
    case deviceTemplates   = 11  // §36.2 Step 11 — Device templates
    case dataImport        = 12  // §36.2 Step 12 — Import data
    case theme             = 13  // §36.2 Step 12a — Theme (12a = step 13 in sequence)
    case complete          = 14  // §36.2 Step 13 — Done

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
        case .theme:             return "Theme"
        case .complete:          return "Complete"
        }
    }

    public var isImplemented: Bool {
        // All steps are now implemented
        true
    }

    public static let totalCount: Int = SetupStep.allCases.count

    public var next: SetupStep? {
        SetupStep(rawValue: rawValue + 1)
    }

    public var previous: SetupStep? {
        SetupStep(rawValue: rawValue - 1)
    }
}
