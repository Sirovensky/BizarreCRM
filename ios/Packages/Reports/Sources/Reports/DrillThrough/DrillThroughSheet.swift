import SwiftUI
import DesignSystem
import Networking

// MARK: - DrillThroughContext

public enum DrillThroughContext: Sendable {
    case revenue(date: String)
    case ticketStatus(status: String, date: String)
    /// §91.11 — drill by ticket status label (period-level, no specific date).
    case ticketStatusFilter(status: String)
    /// §91.11 — drill by technician name.
    case employee(name: String)
    /// Drill from any KPI tile by metric identifier (e.g. "avg_ticket_value", "utilisation", etc.).
    case metric(id: String, label: String)

    var metric: String {
        switch self {
        case .revenue:                  return "revenue"
        case .ticketStatus:             return "tickets"
        case .ticketStatusFilter:       return "tickets"
        case .employee:                 return "employee_tickets"
        case .metric(let id, _):        return id
        }
    }

    var date: String {
        switch self {
        case .revenue(let d):          return d
        case .ticketStatus(_, let d):  return d
        case .ticketStatusFilter:      return ""
        case .employee:                return ""
        case .metric:                  return ""
        }
    }

    var title: String {
        switch self {
        case .revenue(let d):                 return "Revenue on \(d)"
        case .ticketStatus(let s, let d):     return "\(s) Tickets on \(d)"
        case .ticketStatusFilter(let s):      return "\(s) Tickets"
        case .employee(let n):                return "\(n) — Tickets"
        case .metric(_, let label):           return label
        }
    }
}

// MARK: - DrillThroughSheet

public struct DrillThroughSheet: View {
    public let context: DrillThroughContext
    public let repository: ReportsRepository
    public let onTapSale: (Int64) -> Void
    /// Called when user taps a cross-report drill target. Parent switches sub-tab + date range.
    public let onCrossReportDrill: ((CrossReportDrillTarget) -> Void)?

    // §15.9 cross-report drill from the current context+window
    public let fromDate: String
    public let toDate: String

    private let crossDrillService = CrossReportDrillService()

    public init(context: DrillThroughContext,
                repository: ReportsRepository,
                fromDate: String = "",
                toDate: String = "",
                onTapSale: @escaping (Int64) -> Void,
                onCrossReportDrill: ((CrossReportDrillTarget) -> Void)? = nil) {
        self.context = context
        self.repository = repository
        self.fromDate = fromDate
        self.toDate = toDate
        self.onTapSale = onTapSale
        self.onCrossReportDrill = onCrossReportDrill
    }

    @State private var records: [DrillThroughRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle(context.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading…")
                .accessibilityLabel("Loading drill-through records")
        } else if let msg = errorMessage {
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle",
                                   description: Text(msg))
        } else {
            List {
                // §15.9 Cross-report drill targets section
                let targets = crossDrillService.targets(for: context, fromDate: fromDate, toDate: toDate)
                if !targets.isEmpty, let handler = onCrossReportDrill {
                    Section("Jump to related report") {
                        ForEach(targets) { target in
                            Button {
                                handler(target)
                            } label: {
                                HStack {
                                    Label(target.label, systemImage: "arrow.up.right.square")
                                        .font(.brandBodyMedium())
                                        .foregroundStyle(.bizarreOrange)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .imageScale(.small)
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: DesignTokens.Touch.minTargetSide)
                            }
                            .accessibilityLabel("Jump to \(target.label)")
                        }
                    }
                }

                // Drill-through records section
                if records.isEmpty {
                    ContentUnavailableView("No Records",
                                           systemImage: "doc.text.magnifyingglass",
                                           description: Text("No records found for this data point."))
                } else {
                    Section("Records") {
                        ForEach(records) { record in
                            drillRow(record)
                        }
                    }
                }
            }
            .listStyle(.grouped)
        }
    }

    private func drillRow(_ record: DrillThroughRecord) -> some View {
        Button {
            onTapSale(record.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(record.label)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let detail = record.detail {
                        Text(detail)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                if let dollars = record.amountDollars {
                    Text(dollars, format: .currency(code: "USD"))
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreSuccess)
                }
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, BrandSpacing.xs)
            .frame(minHeight: DesignTokens.Touch.minTargetSide)
        }
        .accessibilityLabel("\(record.label)\(record.detail.map { ", \($0)" } ?? "")\(record.amountDollars.map { String(format: ", $%.2f", $0) } ?? "")")
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            records = try await repository.getDrillThrough(metric: context.metric, date: context.date)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
