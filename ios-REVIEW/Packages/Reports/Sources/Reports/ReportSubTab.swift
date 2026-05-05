import Foundation
import SwiftUI

// MARK: - ReportSubTab
//
// §15.1 — Sales / Tickets / Employees / Inventory / Tax / Insights segmented picker.
// Drives which card group is shown in ReportsView.

public enum ReportSubTab: String, CaseIterable, Identifiable, Sendable {
    case sales      = "Sales"
    case tickets    = "Tickets"
    case employees  = "Employees"
    case inventory  = "Inventory"
    case tax        = "Tax"
    case insights   = "Insights"

    public var id: String { rawValue }
    public var displayLabel: String { rawValue }

    public var systemImage: String {
        switch self {
        case .sales:      return "dollarsign.circle"
        case .tickets:    return "wrench.and.screwdriver"
        case .employees:  return "person.3"
        case .inventory:  return "shippingbox"
        case .tax:        return "percent"
        case .insights:   return "lightbulb"
        }
    }

    // MARK: - Keyboard shortcuts (⌘1 … ⌘6)
    //
    // Standard Mac/iPad pattern: ⌘ + digit jumps directly to a named tab.
    // Assigned in declaration order so the mapping is stable.

    /// The `KeyEquivalent` character for this tab's ⌘N shortcut.
    public var keyEquivalentCharacter: Character {
        switch self {
        case .sales:      return "1"
        case .tickets:    return "2"
        case .employees:  return "3"
        case .inventory:  return "4"
        case .tax:        return "5"
        case .insights:   return "6"
        }
    }

    /// Convenience accessor as a `KeyEquivalent` value.
    public var keyEquivalent: KeyEquivalent {
        KeyEquivalent(keyEquivalentCharacter)
    }
}
