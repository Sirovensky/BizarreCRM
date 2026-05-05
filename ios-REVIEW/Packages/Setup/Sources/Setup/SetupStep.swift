import Foundation

// MARK: - SetupStep enum
// §36: 15-step first-run onboarding wizard.
// Steps 1–8 fully implemented in §36.2 Phase 1.
// Steps 9–15 implemented in §36 Phase 2 (this PR).

public enum SetupStep: Int, CaseIterable, Sendable {
    case welcome           = 1
    case companyInfo       = 2
    case logo              = 3
    case timezoneLocale    = 4   // §36.2 Step 4 — TZ + currency + locale
    case businessHours     = 5   // §36.2 Step 5 — Business hours
    case taxSetup          = 6   // §36.2 Step 6 — Tax setup
    case paymentMethods    = 7   // §36.2 Step 7 — Payment methods
    case firstLocation     = 8   // §36.2 Step 8 — First location
    case firstEmployee     = 9   // §36 Step 9 — First employee (POST /settings/users)
    case smsSetup          = 10  // §36.2 Step 10 — SMS setup
    case deviceTemplates   = 11  // §36.2 Step 11 — Device templates
    case dataImport        = 12  // §36.2 Step 12 — Import data
    case theme             = 13  // §36.2 Step 12a — Theme (12a = step 13 in sequence)
    case sampleData        = 14  // §36 Step 14 — Sample data opt-in (POST /onboarding/sample-data)
    case complete          = 15  // §36.2 Step 15 — Done

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
        case .firstEmployee:     return "First Employee"
        case .smsSetup:          return "SMS Setup"
        case .deviceTemplates:   return "Device Templates"
        case .dataImport:        return "Data Import"
        case .theme:             return "Theme"
        case .sampleData:        return "Sample Data"
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
