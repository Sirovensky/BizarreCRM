import Foundation

// MARK: - CrossReportDrillTarget
//
// Describes the destination report section + the filters that should be
// pre-applied when a user jumps from one chart to a related one.
// §15.9: Cross-report drilling — jump into related report with same filters applied.

public struct CrossReportDrillTarget: Sendable, Identifiable {
    public let id: String
    /// Human-readable label for the breadcrumb / button.
    public let label: String
    /// The `ReportSubTab` the drill lands on.
    public let targetSubTab: ReportSubTab
    /// Optional pre-filtered date range (from / to ISO-8601 strings).
    public let fromDate: String?
    public let toDate: String?
    /// Optional entity filter (e.g. tech ID, customer ID) forwarded as context.
    public let entityFilter: String?

    public init(
        id: String,
        label: String,
        targetSubTab: ReportSubTab,
        fromDate: String? = nil,
        toDate: String? = nil,
        entityFilter: String? = nil
    ) {
        self.id = id
        self.label = label
        self.targetSubTab = targetSubTab
        self.fromDate = fromDate
        self.toDate = toDate
        self.entityFilter = entityFilter
    }
}

// MARK: - CrossReportDrillService
//
// Pure value-type service: given the current drill-through context, returns a
// list of possible related-report targets the user can jump to. The caller
// (ReportsView) applies the returned target by switching sub-tab and
// optionally calling applyCustomRange.
//
// No network calls here — this is a routing decision layer only.

public struct CrossReportDrillService: Sendable {

    public init() {}

    /// Returns the set of cross-report drill targets available from the given
    /// `DrillThroughContext` and current `fromDate`/`toDate` window.
    public func targets(
        for context: DrillThroughContext,
        fromDate: String,
        toDate: String
    ) -> [CrossReportDrillTarget] {
        switch context {
        case .revenue(let date):
            return [
                CrossReportDrillTarget(
                    id: "tickets-on-\(date)",
                    label: "Tickets on \(date)",
                    targetSubTab: .tickets,
                    fromDate: date,
                    toDate: date
                ),
                CrossReportDrillTarget(
                    id: "employees-period",
                    label: "Employee performance — same period",
                    targetSubTab: .employees,
                    fromDate: fromDate,
                    toDate: toDate
                ),
                CrossReportDrillTarget(
                    id: "inventory-period",
                    label: "Inventory movement — same period",
                    targetSubTab: .inventory,
                    fromDate: fromDate,
                    toDate: toDate
                ),
            ]

        case .ticketStatus(let status, let date):
            return [
                CrossReportDrillTarget(
                    id: "revenue-on-\(date)",
                    label: "Revenue on \(date)",
                    targetSubTab: .sales,
                    fromDate: date,
                    toDate: date
                ),
                CrossReportDrillTarget(
                    id: "employees-\(status)-\(date)",
                    label: "\(status.capitalized) tickets by tech on \(date)",
                    targetSubTab: .employees,
                    fromDate: date,
                    toDate: date
                ),
            ]
        }
    }
}
