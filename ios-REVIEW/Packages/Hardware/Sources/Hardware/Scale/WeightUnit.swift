import Foundation

// MARK: - WeightUnit
//
// §17 Scale: "Precision units: grams / ounces / pounds / kilograms"
//            "Tenant chooses unit system"
//
// Authoritative internal storage is always grams (integer).
// WeightUnit formats a `Weight` value for display and POS line items.

/// The display unit system for weight readings and pricing.
///
/// Persisted per-tenant in UserDefaults via `WeightUnitStore`.
public enum WeightUnit: String, CaseIterable, Sendable, Codable {
    case grams      = "g"
    case ounces     = "oz"
    case pounds     = "lb"
    case kilograms  = "kg"

    // MARK: - Display name

    public var displayName: String {
        switch self {
        case .grams:     return "Grams (g)"
        case .ounces:    return "Ounces (oz)"
        case .pounds:    return "Pounds (lb)"
        case .kilograms: return "Kilograms (kg)"
        }
    }

    public var shortLabel: String { rawValue }

    // MARK: - Conversion from grams

    /// Convert raw gram value to this unit.
    public func value(from grams: Int) -> Double {
        switch self {
        case .grams:    return Double(grams)
        case .ounces:   return Double(grams) * 0.035_274
        case .pounds:   return Double(grams) * 0.002_204_6
        case .kilograms: return Double(grams) / 1000.0
        }
    }

    // MARK: - Formatting

    /// Format a `Weight` in this unit for display (2 decimal places where meaningful).
    public func formatted(_ weight: Weight) -> String {
        let v = value(from: weight.grams)
        switch self {
        case .grams:
            return "\(weight.grams) g"
        case .ounces:
            return String(format: "%.2f oz", v)
        case .pounds:
            return String(format: "%.3f lb", v)
        case .kilograms:
            return String(format: "%.3f kg", v)
        }
    }

    // MARK: - Grams to unit (for pricing calcs)

    /// Convert grams to this unit (Double) for pricing.
    public func unitValue(forGrams grams: Int) -> Double {
        value(from: grams)
    }
}

// MARK: - WeightUnitStore

/// Persists the tenant-selected weight unit in UserDefaults.
///
/// Inject via DI container; read in POS + Scale settings.
public struct WeightUnitStore: Sendable {

    private static let udKey = "com.bizarrecrm.scale.weightUnit"

    public init() {}

    /// The currently-selected unit (defaults to `.grams` if unset).
    public var selectedUnit: WeightUnit {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.udKey),
                  let unit = WeightUnit(rawValue: raw) else {
                return .grams
            }
            return unit
        }
        nonmutating set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.udKey)
        }
    }
}
