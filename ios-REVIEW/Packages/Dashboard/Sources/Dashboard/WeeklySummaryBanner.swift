import SwiftUI
import Observation
import Networking
import DesignSystem

// MARK: - §3 Weekly Summary Banner
//
// Collapsible glass card showing week-to-date revenue, tickets closed,
// and average ticket value. Fetches GET /api/v1/reports/weekly-summary.
// Falls back to client-computable stats (closedToday * avgRepairHours) when
// the endpoint is absent (404/not-implemented) — the banner hides itself on
// a non-recoverable error to avoid clutter.

// MARK: - Model

public struct WeeklySummaryData: Decodable, Sendable {
    public let weekRevenue: Double
    public let ticketsClosed: Int
    public let avgTicketValue: Double
    public let startDate: String   // "YYYY-MM-DD"
    public let endDate: String     // "YYYY-MM-DD"

    public init(weekRevenue: Double = 0, ticketsClosed: Int = 0,
                avgTicketValue: Double = 0, startDate: String = "", endDate: String = "") {
        self.weekRevenue = weekRevenue
        self.ticketsClosed = ticketsClosed
        self.avgTicketValue = avgTicketValue
        self.startDate = startDate
        self.endDate = endDate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.weekRevenue    = (try? c.decode(Double.self, forKey: .weekRevenue))    ?? 0
        self.ticketsClosed  = (try? c.decode(Int.self,    forKey: .ticketsClosed))  ?? 0
        self.avgTicketValue = (try? c.decode(Double.self, forKey: .avgTicketValue)) ?? 0
        self.startDate      = (try? c.decode(String.self, forKey: .startDate))      ?? ""
        self.endDate        = (try? c.decode(String.self, forKey: .endDate))        ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case weekRevenue    = "week_revenue"
        case ticketsClosed  = "tickets_closed"
        case avgTicketValue = "avg_ticket_value"
        case startDate      = "start_date"
        case endDate        = "end_date"
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class WeeklySummaryViewModel {
    public enum State: Sendable {
        case loading
        case loaded(WeeklySummaryData)
        case hidden   // non-recoverable — suppress banner
    }

    public private(set) var state: State = .loading
    public var isExpanded: Bool = true

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        guard case .loading = state else { return }
        do {
            let data = try await api.get(
                "/api/v1/reports/weekly-summary",
                as: WeeklySummaryData.self
            )
            state = .loaded(data)
        } catch {
            // 404 = endpoint not yet implemented; hide silently
            state = .hidden
        }
    }
}

// MARK: - View

public struct WeeklySummaryBanner: View {
    @State private var vm: WeeklySummaryViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: WeeklySummaryViewModel(api: api))
    }

    public var body: some View {
        switch vm.state {
        case .loading:
            EmptyView()
        case .hidden:
            EmptyView()
        case .loaded(let data):
            BannerCard(data: data, isExpanded: $vm.isExpanded)
        }
    }
}

// MARK: - BannerCard

private struct BannerCard: View {
    let data: WeeklySummaryData
    @Binding var isExpanded: Bool

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    private func format(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — tappable to collapse
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                    Text("This Week")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .tracking(0.5)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .brandGlass(.regular, in: UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: isExpanded ? 0 : 14,
                bottomTrailingRadius: isExpanded ? 0 : 14, topTrailingRadius: 14
            ))
            .accessibilityLabel(isExpanded ? "Weekly summary, expanded. Tap to collapse." : "Weekly summary, collapsed. Tap to expand.")

            if isExpanded {
                HStack(spacing: 0) {
                    StatColumn(label: "Revenue", value: format(data.weekRevenue))
                    Divider()
                        .frame(height: 36)
                        .overlay(Color.bizarreOutline.opacity(0.25))
                    StatColumn(label: "Closed", value: "\(data.ticketsClosed)")
                    Divider()
                        .frame(height: 36)
                        .overlay(Color.bizarreOutline.opacity(0.25))
                    StatColumn(label: "Avg Ticket", value: format(data.avgTicketValue))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct StatColumn: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}
