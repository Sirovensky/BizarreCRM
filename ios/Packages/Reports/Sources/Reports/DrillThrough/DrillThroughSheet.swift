import SwiftUI
import DesignSystem
import Networking

// MARK: - DrillThroughContext

public enum DrillThroughContext: Sendable {
    case revenue(date: String)
    case ticketStatus(status: String, date: String)

    var metric: String {
        switch self {
        case .revenue:      return "revenue"
        case .ticketStatus: return "tickets"
        }
    }

    var date: String {
        switch self {
        case .revenue(let d):          return d
        case .ticketStatus(_, let d):  return d
        }
    }

    var title: String {
        switch self {
        case .revenue(let d):           return "Revenue on \(d)"
        case .ticketStatus(let s, let d): return "\(s) Tickets on \(d)"
        }
    }
}

// MARK: - DrillThroughSheet

public struct DrillThroughSheet: View {
    public let context: DrillThroughContext
    public let repository: ReportsRepository
    public let onTapSale: (Int64) -> Void

    public init(context: DrillThroughContext,
                repository: ReportsRepository,
                onTapSale: @escaping (Int64) -> Void) {
        self.context = context
        self.repository = repository
        self.onTapSale = onTapSale
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
        } else if records.isEmpty {
            ContentUnavailableView("No Records",
                                   systemImage: "doc.text.magnifyingglass",
                                   description: Text("No records found for this data point."))
        } else {
            List(records) { record in
                drillRow(record)
            }
            .listStyle(.plain)
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
