import Foundation
import Networking

// MARK: - SetupPayload
// Accumulated wizard state across all steps. Each step view writes its fields
// here; SetupWizardViewModel serialises the relevant subset on submission.

public struct SetupPayload: Sendable {

    // MARK: Step 2 — Company Info (read by later steps for pre-fill)
    public var companyName: String = ""
    public var companyAddress: String = ""
    public var companyPhone: String = ""

    // MARK: Step 4 — Timezone + Currency + Locale
    public var timezone: String? = nil
    public var currency: String? = nil
    public var locale: String? = nil

    // MARK: Step 5 — Business Hours
    public var hours: [BusinessDay] = BusinessDay.defaults

    // MARK: Step 6 — Tax Setup
    public var taxRate: TaxRate? = nil

    // MARK: Step 7 — Payment Methods
    public var paymentMethods: Set<PaymentMethod> = [.cash]

    // MARK: Step 8 — First Location
    public var firstLocation: SetupLocation? = nil

    // MARK: Step 9 — Invite Teammates
    public var invitees: [InvitePayload] = []

    // MARK: Step 10 — SMS Setup
    public var smsProvider: String? = nil
    public var smsFromNumber: String? = nil

    // MARK: Step 11 — Device Templates
    public var enabledDeviceFamilies: Set<String> = []
    public var repairPricingMode: SetupRepairPricingMode = .tiered
    public var repairPricingTierDefaults: RepairPricingSeedPricing = SetupRepairPricingSelection.defaultTierDefaults
    public var repairPricingSpreadsheetPrices: [SetupSpreadsheetPriceDraft] = []
    public var repairPricingAutoMarginPreset: RepairPricingAutoMarginPreset = .midTraffic
    public var repairPricingAutoMarginTargetType: RepairPricingAutoMarginTargetType = .percent
    public var repairPricingTargetMarginPct: Double = 100
    public var repairPricingTargetProfitAmount: Double = 80
    public var repairPricingCalculationBasis: RepairPricingAutoMarginBasis = .markup
    public var repairPricingRoundingMode: RepairPricingRoundingMode = .ending99
    public var repairPricingCapPct: Double = 25
    public var repairPricingAutoMarginRules: [RepairPricingAutoMarginRule] = SetupRepairPricingSelection.defaultAutoMarginRules(for: .midTraffic, targetType: .percent)

    // MARK: Step 12 — Import Data
    public var importSource: String? = nil
    public var skipImport: Bool = false

    // MARK: Step 12a — Theme
    public var theme: String = "system"

    // MARK: Step 9 — First Employee (POST /api/v1/settings/users)
    public var firstEmployeeFirstName: String? = nil
    public var firstEmployeeLastName: String? = nil
    public var firstEmployeeEmail: String? = nil
    public var firstEmployeeRole: String? = nil
    /// Whether to also send an SMS invite to the first employee.
    public var firstEmployeeSendSMS: Bool = false

    // MARK: Step 14 — Sample Data Opt-In (POST /api/v1/onboarding/sample-data)
    public var sampleDataOptIn: Bool? = nil

    public init() {}
}

// MARK: - BusinessDay

public struct BusinessDay: Identifiable, Sendable, Equatable {
    /// ISO weekday: 1 = Monday … 7 = Sunday
    public let id: Int
    public var isOpen: Bool
    /// Hour/minute components for open time
    public var openAt: DateComponents
    /// Hour/minute components for close time
    public var closeAt: DateComponents

    public init(weekday: Int, isOpen: Bool, openAt: DateComponents, closeAt: DateComponents) {
        self.id = weekday
        self.isOpen = isOpen
        self.openAt = openAt
        self.closeAt = closeAt
    }

    public var weekdayName: String {
        switch id {
        case 1: return "Monday"
        case 2: return "Tuesday"
        case 3: return "Wednesday"
        case 4: return "Thursday"
        case 5: return "Friday"
        case 6: return "Saturday"
        case 7: return "Sunday"
        default: return "Day \(id)"
        }
    }

    /// Default 9AM–6PM open, formatted as DateComponents.
    public static var defaultOpen: DateComponents {
        DateComponents(hour: 9, minute: 0)
    }

    public static var defaultClose: DateComponents {
        DateComponents(hour: 18, minute: 0)
    }

    /// Returns a Mon–Sun week with weekdays (1-5) open 9-6, weekend closed.
    public static var defaults: [BusinessDay] {
        (1...7).map { weekday in
            BusinessDay(
                weekday: weekday,
                isOpen: weekday <= 5,
                openAt: defaultOpen,
                closeAt: defaultClose
            )
        }
    }
}

// MARK: - TaxRate

public struct TaxRate: Sendable, Equatable {
    public var name: String
    public var ratePct: Double
    public var applyTo: TaxApply

    public init(name: String, ratePct: Double, applyTo: TaxApply) {
        self.name = name
        self.ratePct = ratePct
        self.applyTo = applyTo
    }
}

public enum TaxApply: String, CaseIterable, Sendable, Equatable {
    case allItems    = "all"
    case taxableOnly = "taxable"

    public var displayName: String {
        switch self {
        case .allItems:    return "All items"
        case .taxableOnly: return "Taxable items only"
        }
    }
}

// MARK: - PaymentMethod

public enum PaymentMethod: String, CaseIterable, Sendable, Equatable, Hashable {
    case cash        = "cash"
    case card        = "card"
    case giftCard    = "gift_card"
    case storeCredit = "store_credit"
    case check       = "check"

    public var displayName: String {
        switch self {
        case .cash:        return "Cash"
        case .card:        return "Card (BlockChyp)"
        case .giftCard:    return "Gift Card"
        case .storeCredit: return "Store Credit"
        case .check:       return "Check"
        }
    }

    public var systemImage: String {
        switch self {
        case .cash:        return "banknote"
        case .card:        return "creditcard"
        case .giftCard:    return "gift"
        case .storeCredit: return "storefront"
        case .check:       return "doc.text"
        }
    }
}

// MARK: - SetupLocation

public struct SetupLocation: Sendable, Equatable {
    public var name: String
    public var address: String
    public var phone: String

    public init(name: String, address: String, phone: String) {
        self.name = name
        self.address = address
        self.phone = phone
    }
}

// MARK: - Serialisation helpers (flat [String:String] for SetupRepository)

public extension SetupPayload {
    func timezoneLocalePayload() -> [String: String] {
        var d: [String: String] = [:]
        if let tz = timezone   { d["timezone"] = tz }
        if let cu = currency   { d["currency"] = cu }
        if let lo = locale     { d["locale"]   = lo }
        return d
    }

    func businessHoursPayload() -> [String: String] {
        // Encode as "hours_1_open", "hours_1_close", "hours_1_isOpen", etc.
        var d: [String: String] = [:]
        for day in hours {
            let prefix = "hours_\(day.id)"
            d["\(prefix)_isOpen"] = day.isOpen ? "1" : "0"
            d["\(prefix)_open"]  = "\(day.openAt.hour ?? 9):\(String(format: "%02d", day.openAt.minute ?? 0))"
            d["\(prefix)_close"] = "\(day.closeAt.hour ?? 18):\(String(format: "%02d", day.closeAt.minute ?? 0))"
        }
        return d
    }

    func taxRatePayload() -> [String: String] {
        guard let tax = taxRate else { return [:] }
        return [
            "tax_name":    tax.name,
            "tax_rate":    String(format: "%.2f", tax.ratePct),
            "tax_apply_to": tax.applyTo.rawValue
        ]
    }

    func paymentMethodsPayload() -> [String: String] {
        ["payment_methods": paymentMethods.map(\.rawValue).sorted().joined(separator: ",")]
    }

    func firstLocationPayload() -> [String: String] {
        guard let loc = firstLocation else { return [:] }
        var d: [String: String] = ["location_name": loc.name, "location_address": loc.address]
        if !loc.phone.isEmpty { d["location_phone"] = loc.phone }
        return d
    }

    func inviteesPayload() -> [String: String] {
        var d: [String: String] = [:]
        for (idx, invite) in invitees.enumerated() {
            d["invitee_\(idx)_email"]   = invite.email
            d["invitee_\(idx)_role"]    = invite.role.rawValue
            d["invitee_\(idx)_sendSMS"] = invite.sendSMS ? "1" : "0"
        }
        d["invitee_count"] = "\(invitees.count)"
        return d
    }

    func smsPayload() -> [String: String] {
        var d: [String: String] = [:]
        if let provider = smsProvider { d["sms_provider"] = provider }
        if let number = smsFromNumber  { d["sms_from_number"] = number }
        return d
    }

    func deviceFamiliesPayload() -> [String: String] {
        var d: [String: String] = [
            "device_families": enabledDeviceFamilies.sorted().joined(separator: ","),
            "repair_pricing_mode": repairPricingMode.rawValue,
            "repair_pricing_auto_margin_preset": repairPricingAutoMarginPreset.rawValue,
            "repair_pricing_auto_margin_target_type": repairPricingAutoMarginTargetType.rawValue,
            "repair_pricing_target_margin_pct": String(format: "%.2f", repairPricingTargetMarginPct),
            "repair_pricing_target_profit_amount": String(format: "%.2f", repairPricingTargetProfitAmount),
            "repair_pricing_calculation_basis": repairPricingCalculationBasis.rawValue,
            "repair_pricing_rounding_mode": repairPricingRoundingMode.rawValue,
            "repair_pricing_cap_pct": String(format: "%.2f", repairPricingCapPct)
        ]
        if let defaults = SetupRepairPricingSelection.encodeTierDefaults(repairPricingTierDefaults) {
            d["repair_pricing_tier_defaults"] = defaults
        }
        if let prices = SetupRepairPricingSelection.encodeSpreadsheetPrices(repairPricingSpreadsheetPrices) {
            d["repair_pricing_spreadsheet_prices"] = prices
        }
        if let data = try? JSONEncoder().encode(repairPricingAutoMarginRules),
           let rules = String(data: data, encoding: .utf8) {
            d["repair_pricing_auto_margin_rules"] = rules
        }
        return d
    }

    func importPayload() -> [String: String] {
        if skipImport { return ["import_skip": "1"] }
        guard let src = importSource else { return ["import_skip": "1"] }
        return ["import_source": src]
    }

    func themePayload() -> [String: String] {
        ["theme": theme]
    }

    func firstEmployeePayload() -> [String: String] {
        var d: [String: String] = [:]
        if let fn = firstEmployeeFirstName, !fn.isEmpty { d["first_name"]   = fn }
        if let ln = firstEmployeeLastName,  !ln.isEmpty { d["last_name"]    = ln }
        if let em = firstEmployeeEmail,     !em.isEmpty { d["email"]        = em }
        if let ro = firstEmployeeRole,      !ro.isEmpty { d["role"]         = ro }
        d["send_sms_invite"] = firstEmployeeSendSMS ? "1" : "0"
        return d
    }

    func sampleDataPayload() -> [String: String] {
        guard let optIn = sampleDataOptIn else { return [:] }
        return ["sample_data_opt_in": optIn ? "1" : "0"]
    }
}
