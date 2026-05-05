import Foundation

// §22.G — Rail sidebar primary destinations.
// The 8 top-level navigation destinations that the rail owns.
// `ShellLayout` consumes this type as the selection binding.

public enum RailDestination: String, CaseIterable, Hashable, Sendable {
    case dashboard  = "dashboard"
    case tickets    = "tickets"
    case customers  = "customers"
    case pos        = "pos"
    case inventory  = "inventory"
    case sms        = "sms"
    case reports    = "reports"
    case settings   = "settings"
}
