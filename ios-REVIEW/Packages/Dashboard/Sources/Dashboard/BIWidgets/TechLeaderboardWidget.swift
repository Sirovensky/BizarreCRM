import SwiftUI
import Observation
import DesignSystem

// MARK: - TechLeaderboardWidget
//
// Technician leaderboard from:
//   GET /api/v1/reports/tech-leaderboard?period=month
//   (reports.routes.ts line 2178)

// MARK: - ViewModel

@MainActor
@Observable
public final class TechLeaderboardViewModel {
    public let title = "Tech Leaderboard"
    public private(set) var state: BIWidgetState<TechLeaderboardPayload> = .idle
    public var period: TechLeaderboardPeriod = .month {
        didSet { Task { await reload() } }
    }

    private let repo: DashboardBIRepository

    public init(repo: DashboardBIRepository) {
        self.repo = repo
    }

    public func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let payload = try await repo.fetchTechLeaderboard(period: period)
            state = .loaded(payload)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func reload() async {
        state = .idle
        await load()
    }
}

// MARK: - View

public struct TechLeaderboardWidget: View, BIWidgetView {
    public let widgetTitle = "Tech Leaderboard"
    @State private var vm: TechLeaderboardViewModel

    public init(vm: TechLeaderboardViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        BIWidgetChrome(title: widgetTitle, systemImage: "person.text.rectangle") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let payload):
                if payload.leaderboard.isEmpty {
                    BIWidgetEmptyState(message: "No technician data for this period.")
                } else {
                    LeaderboardContent(payload: payload, selectedPeriod: $vm.period)
                }
            case .failed(let msg):
                BIWidgetErrorState(message: msg) {
                    Task { await vm.reload() }
                }
            }
        }
        .task { await vm.load() }
        .accessibilityLabel(widgetTitle)
    }
}

// MARK: - LeaderboardContent

private struct LeaderboardContent: View {
    let payload: TechLeaderboardPayload
    @Binding var selectedPeriod: TechLeaderboardPeriod

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: $selectedPeriod) {
                Text("Week").tag(TechLeaderboardPeriod.week)
                Text("Month").tag(TechLeaderboardPeriod.month)
                Text("Quarter").tag(TechLeaderboardPeriod.quarter)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 10)

            ForEach(Array(payload.leaderboard.prefix(5).enumerated()), id: \.element.id) { idx, entry in
                TechRow(entry: entry, rank: idx + 1, formatter: Self.currencyFormatter)
                if idx < min(4, payload.leaderboard.count - 1) {
                    Divider().overlay(Color.bizarreOutline.opacity(0.2))
                }
            }
        }
    }
}

private struct TechRow: View {
    let entry: TechLeaderboardEntry
    let rank: Int
    let formatter: NumberFormatter

    private var revenueString: String {
        formatter.string(from: NSNumber(value: entry.revenue)) ?? "$\(Int(entry.revenue))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.brandLabelSmall())
                .foregroundStyle(rankColor)
                .frame(width: 18, alignment: .trailing)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 10))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("\(entry.ticketsClosed) closed")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    if let csat = entry.csatAvg {
                        Text("·")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .font(.brandLabelSmall())
                        Text(String(format: "%.1f★", csat))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            Spacer(minLength: 4)
            Text(revenueString)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank). \(entry.name)")
        .accessibilityValue("\(revenueString) revenue, \(entry.ticketsClosed) tickets closed")
    }

    private var rankColor: Color {
        switch rank {
        case 1: return Color(.systemYellow)
        case 2: return Color(.systemGray)
        case 3: return Color(.systemOrange)
        default: return .bizarreOnSurfaceMuted
        }
    }
}
