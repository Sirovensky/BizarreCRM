import Foundation
import Core
import Networking

// MARK: - Repair-pricing setup selection

/// The three pricing paths offered during first-run setup. The server remains
/// the source of truth for the actual `repair_prices` rows and calculator
/// settings; this model only captures the admin's setup choice on-device.
public enum SetupRepairPricingMode: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case tiered
    case spreadsheet
    case autoMargin = "auto_margin"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tiered:      return "Tiered"
        case .spreadsheet: return "Spreadsheet"
        case .autoMargin:  return "Auto margin"
        }
    }

    public var systemImage: String {
        switch self {
        case .tiered:      return "square.grid.3x3"
        case .spreadsheet: return "tablecells"
        case .autoMargin:  return "percent"
        }
    }
}

public struct SetupRepairPricingSelection: Codable, Sendable, Equatable {
    public var mode: SetupRepairPricingMode
    public var tierDefaults: RepairPricingSeedPricing
    public var spreadsheetPrices: [SetupSpreadsheetPriceDraft]
    public var autoMarginPreset: RepairPricingAutoMarginPreset
    public var autoMarginTargetType: RepairPricingAutoMarginTargetType
    public var targetMarginPct: Double
    public var targetProfitAmount: Double
    public var calculationBasis: RepairPricingAutoMarginBasis
    public var roundingMode: RepairPricingRoundingMode
    public var capPct: Double
    public var autoMarginRules: [RepairPricingAutoMarginRule]

    public init(
        mode: SetupRepairPricingMode = .tiered,
        tierDefaults: RepairPricingSeedPricing = Self.defaultTierDefaults,
        spreadsheetPrices: [SetupSpreadsheetPriceDraft] = [],
        autoMarginPreset: RepairPricingAutoMarginPreset = .midTraffic,
        autoMarginTargetType: RepairPricingAutoMarginTargetType = .percent,
        targetMarginPct: Double = 100,
        targetProfitAmount: Double = 80,
        calculationBasis: RepairPricingAutoMarginBasis = .markup,
        roundingMode: RepairPricingRoundingMode = .ending99,
        capPct: Double = 25,
        autoMarginRules: [RepairPricingAutoMarginRule] = Self.defaultAutoMarginRules(for: .midTraffic, targetType: .percent)
    ) {
        self.mode = mode
        self.tierDefaults = tierDefaults
        self.spreadsheetPrices = spreadsheetPrices
        self.autoMarginPreset = autoMarginPreset
        self.autoMarginTargetType = autoMarginTargetType
        self.targetMarginPct = targetMarginPct
        self.targetProfitAmount = targetProfitAmount
        self.calculationBasis = calculationBasis
        self.roundingMode = roundingMode
        self.capPct = capPct
        self.autoMarginRules = autoMarginRules
    }

    public static let defaultServiceOrder: [String] = [
        "screen",
        "battery",
        "charge_port",
        "back_glass",
        "camera"
    ]

    public static let defaultTierOrder: [String] = [
        RepairPricingTierKey.tierA.rawValue,
        RepairPricingTierKey.tierB.rawValue,
        RepairPricingTierKey.tierC.rawValue
    ]

    public static let defaultTierDefaults: RepairPricingSeedPricing = [
        "screen": [
            RepairPricingTierKey.tierA.rawValue: 200,
            RepairPricingTierKey.tierB.rawValue: 120,
            RepairPricingTierKey.tierC.rawValue: 80
        ],
        "battery": [
            RepairPricingTierKey.tierA.rawValue: 80,
            RepairPricingTierKey.tierB.rawValue: 60,
            RepairPricingTierKey.tierC.rawValue: 45
        ],
        "charge_port": [
            RepairPricingTierKey.tierA.rawValue: 120,
            RepairPricingTierKey.tierB.rawValue: 90,
            RepairPricingTierKey.tierC.rawValue: 70
        ],
        "back_glass": [
            RepairPricingTierKey.tierA.rawValue: 180,
            RepairPricingTierKey.tierB.rawValue: 110,
            RepairPricingTierKey.tierC.rawValue: 70
        ],
        "camera": [
            RepairPricingTierKey.tierA.rawValue: 140,
            RepairPricingTierKey.tierB.rawValue: 90,
            RepairPricingTierKey.tierC.rawValue: 60
        ]
    ]

    public static let autoMarginServiceSlugs: [String] = [
        "screen-replacement",
        "battery-replacement",
        "charging-port",
        "back-glass",
        "camera-repair"
    ]

    public static func defaultAutoMarginRules(
        for preset: RepairPricingAutoMarginPreset,
        targetType: RepairPricingAutoMarginTargetType = .percent
    ) -> [RepairPricingAutoMarginRule] {
        let percentValues: [String: Double]
        let fixedValues: [String: Double]
        switch preset {
        case .highTraffic, .value:
            percentValues = [
                "screen-replacement": 75,
                "battery-replacement": 60,
                "charging-port": 90,
                "back-glass": 120,
                "camera-repair": 100
            ]
            fixedValues = [
                "screen-replacement": 60,
                "battery-replacement": 35,
                "charging-port": 55,
                "back-glass": 75,
                "camera-repair": 60
            ]
        case .midTraffic, .balanced, .custom:
            percentValues = [
                "screen-replacement": 100,
                "battery-replacement": 80,
                "charging-port": 120,
                "back-glass": 180,
                "camera-repair": 150
            ]
            fixedValues = [
                "screen-replacement": 80,
                "battery-replacement": 50,
                "charging-port": 75,
                "back-glass": 105,
                "camera-repair": 90
            ]
        case .lowTraffic, .premium:
            percentValues = [
                "screen-replacement": 150,
                "battery-replacement": 100,
                "charging-port": 180,
                "back-glass": 300,
                "camera-repair": 250
            ]
            fixedValues = [
                "screen-replacement": 110,
                "battery-replacement": 70,
                "charging-port": 100,
                "back-glass": 150,
                "camera-repair": 125
            ]
        }

        return autoMarginServiceSlugs.map { slug in
            let percent = percentValues[slug] ?? 100
            let fixed = fixedValues[slug] ?? 80
            RepairPricingAutoMarginRule(
                id: "setup.\(slug)",
                scope: .repairService,
                label: serviceTitle(slug),
                repairServiceSlug: slug,
                targetType: targetType,
                targetMarginPct: percent,
                targetProfitAmount: fixed,
                calculationBasis: .markup,
                roundingMode: .ending99,
                capPct: 25,
                enabled: true
            )
        }
    }

    public static func serviceTitle(_ key: String) -> String {
        switch key {
        case "screen":      return "Screen"
        case "battery":     return "Battery"
        case "charge_port": return "Charge port"
        case "back_glass":  return "Back glass"
        case "camera":      return "Camera"
        case "screen-replacement":  return "Screen"
        case "battery-replacement": return "Battery"
        case "charging-port":       return "Charge port"
        case "back-glass":          return "Back glass"
        case "camera-repair":       return "Camera"
        default:
            return key
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    public static func tierTitle(_ key: String) -> String {
        switch key {
        case RepairPricingTierKey.tierA.rawValue: return "A"
        case RepairPricingTierKey.tierB.rawValue: return "B"
        case RepairPricingTierKey.tierC.rawValue: return "C"
        default: return key
        }
    }

    public static func encodeTierDefaults(_ pricing: RepairPricingSeedPricing) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(pricing) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func encodeSpreadsheetPrices(_ prices: [SetupSpreadsheetPriceDraft]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(prices) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public var seedDefaultsRequest: RepairPricingSeedDefaultsRequest {
        RepairPricingSeedDefaultsRequest(
            category: "phone",
            pricing: tierDefaults,
            overwriteCustom: false
        )
    }

    public var autoMarginSettings: RepairPricingAutoMarginSettings {
        RepairPricingAutoMarginSettings(
            preset: autoMarginPreset,
            targetType: autoMarginTargetType,
            targetMarginPct: targetMarginPct,
            targetProfitAmount: targetProfitAmount,
            calculationBasis: calculationBasis,
            roundingMode: roundingMode,
            capPct: capPct,
            rules: autoMarginRules
        )
    }
}

public struct SetupSpreadsheetPriceDraft: Codable, Sendable, Equatable, Identifiable {
    public let deviceModelId: Int64
    public let deviceModelName: String
    public let manufacturerName: String
    public let repairServiceId: Int64
    public let repairServiceName: String
    public let repairServiceSlug: String
    public let priceId: Int64?
    public var laborPrice: Double?
    public var originalLaborPrice: Double?
    public var isEdited: Bool

    public var id: String {
        "\(deviceModelId)-\(repairServiceId)"
    }

    public init(
        deviceModelId: Int64,
        deviceModelName: String,
        manufacturerName: String,
        repairServiceId: Int64,
        repairServiceName: String,
        repairServiceSlug: String,
        priceId: Int64?,
        laborPrice: Double?,
        originalLaborPrice: Double? = nil,
        isEdited: Bool = false
    ) {
        self.deviceModelId = deviceModelId
        self.deviceModelName = deviceModelName
        self.manufacturerName = manufacturerName
        self.repairServiceId = repairServiceId
        self.repairServiceName = repairServiceName
        self.repairServiceSlug = repairServiceSlug
        self.priceId = priceId
        self.laborPrice = laborPrice
        self.originalLaborPrice = originalLaborPrice ?? laborPrice
        self.isEdited = isEdited
    }

    public var shouldPersist: Bool {
        guard isEdited, let laborPrice else { return false }
        return laborPrice >= 0
    }
}

public struct DeviceTemplatesSetupSelection: Sendable, Equatable {
    public var families: Set<DeviceFamily>
    public var repairPricing: SetupRepairPricingSelection

    public init(
        families: Set<DeviceFamily>,
        repairPricing: SetupRepairPricingSelection = SetupRepairPricingSelection()
    ) {
        self.families = families
        self.repairPricing = repairPricing
    }
}

public extension RepairPricingRoundingMode {
    var setupTitle: String {
        switch self {
        case .none:        return "None"
        case .ending99:    return "0.99"
        case .wholeDollar: return "1.00"
        case .ending98:    return "0.98"
        }
    }
}

public extension RepairPricingAutoMarginPreset {
    var setupTitle: String {
        switch self {
        case .highTraffic: return "High traffic"
        case .midTraffic:  return "Mid traffic"
        case .lowTraffic:  return "Low traffic"
        case .value:       return "Value"
        case .balanced:    return "Balanced"
        case .premium:     return "Premium"
        case .custom:      return "Custom"
        }
    }
}

public extension RepairPricingAutoMarginTargetType {
    var setupTitle: String {
        switch self {
        case .percent:     return "%"
        case .fixedAmount: return "$"
        }
    }
}

public extension RepairPricingAutoMarginBasis {
    var setupTitle: String {
        switch self {
        case .grossMargin: return "Gross margin"
        case .markup:      return "Markup"
        }
    }
}
