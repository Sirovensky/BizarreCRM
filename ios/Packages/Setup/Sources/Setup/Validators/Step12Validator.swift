import Foundation

// MARK: - Step12Validator  (Import Data)
// Any state is valid — skip is also an explicit action.

public enum ImportSource: String, CaseIterable, Sendable, Equatable {
    case repairDesk = "repairdesk"
    case shopr      = "shopr"
    case mra        = "mra"
    case csv        = "csv"
    case skip       = "skip"

    public var displayName: String {
        switch self {
        case .repairDesk: return "RepairDesk"
        case .shopr:      return "Shopr"
        case .mra:        return "MRA"
        case .csv:        return "CSV"
        case .skip:       return "Skip for now"
        }
    }

    public var systemImage: String {
        switch self {
        case .repairDesk: return "arrow.down.doc"
        case .shopr:      return "arrow.down.doc"
        case .mra:        return "arrow.down.doc"
        case .csv:        return "tablecells"
        case .skip:       return "forward"
        }
    }
}

public enum Step12Validator {

    /// Always valid — any source selection (including skip) is accepted.
    public static func isNextEnabled(source: ImportSource?) -> Bool {
        true
    }
}
