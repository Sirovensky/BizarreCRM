import Foundation

// MARK: - Step11Validator  (Device Templates)
// Zero selections is OK — step is skippable.

public enum DeviceFamily: String, CaseIterable, Sendable, Equatable, Hashable {
    case iPhone         = "iphone"
    case iPad           = "ipad"
    case mac            = "mac"
    case samsungGalaxy  = "samsung_galaxy"
    case samsungTablet  = "samsung_tablet"
    case pixel          = "pixel"
    case watch          = "watch"
    case gamingConsole  = "gaming_console"
    case custom         = "custom"

    public var displayName: String {
        switch self {
        case .iPhone:         return "iPhone"
        case .iPad:           return "iPad"
        case .mac:            return "Mac"
        case .samsungGalaxy:  return "Samsung Galaxy"
        case .samsungTablet:  return "Samsung Tablet"
        case .pixel:          return "Pixel"
        case .watch:          return "Watch"
        case .gamingConsole:  return "Gaming Console"
        case .custom:         return "Custom"
        }
    }

    public var systemImage: String {
        switch self {
        case .iPhone:         return "iphone"
        case .iPad:           return "ipad"
        case .mac:            return "laptopcomputer"
        case .samsungGalaxy:  return "smartphone"
        case .samsungTablet:  return "rectangle.portrait"
        case .pixel:          return "smartphone"
        case .watch:          return "applewatch"
        case .gamingConsole:  return "gamecontroller"
        case .custom:         return "wrench.and.screwdriver"
        }
    }

    /// Approximate count of preloaded models for display.
    public var preloadedModelCount: Int {
        switch self {
        case .iPhone:        return 24
        case .iPad:          return 12
        case .mac:           return 8
        case .samsungGalaxy: return 18
        case .samsungTablet: return 10
        case .pixel:         return 9
        case .watch:         return 6
        case .gamingConsole: return 5
        case .custom:        return 0
        }
    }
}

public enum Step11Validator {

    /// Always valid — zero selections is allowed.
    public static func isNextEnabled(selected: Set<DeviceFamily>) -> Bool {
        true
    }
}
