import Foundation

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
}
