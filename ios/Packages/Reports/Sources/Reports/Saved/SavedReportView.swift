import Foundation

// MARK: - ReportKind

/// Identifies which analytics report this saved view represents.
public enum ReportKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case revenue     = "revenue"
    case tickets     = "tickets"
    case employees   = "employees"
    case inventory   = "inventory"
    case expenses    = "expenses"
    case csat        = "csat"
    case nps         = "nps"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .revenue:   return "Revenue"
        case .tickets:   return "Tickets"
        case .employees: return "Employees"
        case .inventory: return "Inventory"
        case .expenses:  return "Expenses"
        case .csat:      return "CSAT"
        case .nps:       return "NPS"
        }
    }

    public var systemImageName: String {
        switch self {
        case .revenue:   return "chart.line.uptrend.xyaxis"
        case .tickets:   return "ticket"
        case .employees: return "person.3"
        case .inventory: return "shippingbox"
        case .expenses:  return "dollarsign.circle"
        case .csat:      return "star.fill"
        case .nps:       return "person.badge.plus"
        }
    }
}

// MARK: - SavedReportFilters

/// Snapshot of any active filters at save time.
/// Kept as a flat value type so it remains trivially Codable.
public struct SavedReportFilters: Codable, Sendable, Equatable {
    /// Custom from-date ISO-8601 string, nil when a preset was used.
    public let customFromDate: String?
    /// Custom to-date ISO-8601 string, nil when a preset was used.
    public let customToDate: String?
    /// Free-form key/value extras (e.g. employee ID, category).
    public let extras: [String: String]

    public init(
        customFromDate: String? = nil,
        customToDate: String? = nil,
        extras: [String: String] = [:]
    ) {
        self.customFromDate = customFromDate
        self.customToDate = customToDate
        self.extras = extras
    }

    public static let empty = SavedReportFilters()
}

// MARK: - SavedReportView

/// A pure value type describing one saved report configuration.
///
/// Persisted via `SavedReportStore`. Immutable after creation —
/// editing produces a new value.
///
/// `DateRangePreset` is `String`-backed but not declared `Codable` in the
/// existing model file. We encode it via its `rawValue` String manually.
public struct SavedReportView: Sendable, Identifiable, Equatable {
    // MARK: Stored properties

    /// Stable UUID assigned at creation.
    public let id: UUID
    /// User-chosen display name, e.g. "Q1 Revenue".
    public let name: String
    /// Which report type this view applies to.
    public let reportKind: ReportKind
    /// The date-range preset active when this view was saved.
    public let dateRange: DateRangePreset
    /// Any additional filters / overrides.
    public let filters: SavedReportFilters
    /// Wall-clock time the user pressed Save.
    public let createdDate: Date

    // MARK: Init

    public init(
        id: UUID = UUID(),
        name: String,
        reportKind: ReportKind,
        dateRange: DateRangePreset,
        filters: SavedReportFilters = .empty,
        createdDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.reportKind = reportKind
        self.dateRange = dateRange
        self.filters = filters
        self.createdDate = createdDate
    }

    // MARK: Derived

    /// Human-readable creation date, e.g. "Apr 23, 2026".
    public var formattedCreatedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: createdDate)
    }
}

// MARK: - Codable (manual — DateRangePreset lacks Codable conformance)

extension SavedReportView: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, reportKind, dateRangeRawValue, filters, createdDate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,              forKey: .id)
        name        = try c.decode(String.self,            forKey: .name)
        reportKind  = try c.decode(ReportKind.self,        forKey: .reportKind)
        filters     = try c.decode(SavedReportFilters.self, forKey: .filters)
        createdDate = try c.decode(Date.self,              forKey: .createdDate)
        let rawValue = try c.decode(String.self, forKey: .dateRangeRawValue)
        dateRange = DateRangePreset(rawValue: rawValue) ?? .thirtyDays
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,               forKey: .id)
        try c.encode(name,             forKey: .name)
        try c.encode(reportKind,       forKey: .reportKind)
        try c.encode(dateRange.rawValue, forKey: .dateRangeRawValue)
        try c.encode(filters,          forKey: .filters)
        try c.encode(createdDate,      forKey: .createdDate)
    }
}
