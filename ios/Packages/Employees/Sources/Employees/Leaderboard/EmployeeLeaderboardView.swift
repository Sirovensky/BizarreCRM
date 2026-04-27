import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EmployeeLeaderboardView
//
// §14.7 — Leaderboard ranked by tickets closed / revenue / commission.
// Period filter: week / month / YTD.
// iPhone: NavigationStack list with medal badges.
// iPad: wider table.

public enum LeaderboardMetric: String, CaseIterable, Sendable {
    case ticketsClosed = "Tickets Closed"
    case revenue       = "Revenue"

    func value(from p: EmployeePerformance) -> Double {
        switch self {
        case .ticketsClosed: return Double(p.closedTickets)
        case .revenue:       return p.totalRevenue
        }
    }

    func formatted(_ v: Double) -> String {
        switch self {
        case .ticketsClosed: return "\(Int(v))"
        case .revenue:       return "$\(String(format: "%.0f", v))"
        }
    }
}

public enum LeaderboardPeriod: String, CaseIterable, Sendable {
    case week  = "Week"
    case month = "Month"
    case ytd   = "YTD"

    var dateRange: (from: String, to: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let cal = Calendar.current
        let to = fmt.string(from: now)
        switch self {
        case .week:
            let s = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            return (fmt.string(from: s), to)
        case .month:
            let s = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            return (fmt.string(from: s), to)
        case .ytd:
            let s = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            return (fmt.string(from: s), to)
        }
    }
}

public struct LeaderboardEntry: Identifiable, Sendable {
    public let id: Int64
    public let displayName: String
    public let initials: String
    public let role: String?
    public let value: Double
    public let rank: Int
}

@MainActor
@Observable
public final class EmployeeLeaderboardViewModel {
    public private(set) var entries: [LeaderboardEntry] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    public var metric: LeaderboardMetric = .ticketsClosed { didSet { Task { await load() } } }
    public var period: LeaderboardPeriod = .week          { didSet { Task { await load() } } }

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let employees = try await api.listEmployees()
            let range = period.dateRange
            var raw: [(emp: Employee, value: Double)] = []
            for emp in employees {
                if let perf = try? await api.getEmployeePerformance(
                    id: emp.id, fromDate: range.from, toDate: range.to
                ) {
                    raw.append((emp, metric.value(from: perf)))
                }
            }
            let sorted = raw.sorted { $0.value > $1.value }
            entries = sorted.enumerated().map { idx, pair in
                LeaderboardEntry(
                    id: pair.emp.id,
                    displayName: pair.emp.displayName,
                    initials: pair.emp.initials,
                    role: pair.emp.role,
                    value: pair.value,
                    rank: idx + 1
                )
            }
        } catch {
            AppLog.ui.error("Leaderboard load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct EmployeeLeaderboardView: View {
    @State private var vm: EmployeeLeaderboardViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: EmployeeLeaderboardViewModel(api: api))
    }

    public var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                ContentUnavailableView(
                    "Couldn't Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else if vm.entries.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("No performance data for this period.")
                )
            } else {
                leaderboardList
            }
        }
        .navigationTitle("Leaderboard")
        .toolbar { pickerToolbar }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ToolbarContentBuilder
    private var pickerToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Metric", selection: $vm.metric) {
                ForEach(LeaderboardMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Select metric")
        }
        ToolbarItem(placement: .automatic) {
            Picker("Period", selection: $vm.period) {
                ForEach(LeaderboardPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Select time period")
        }
    }

    private var leaderboardList: some View {
        List {
            ForEach(vm.entries) { entry in
                LeaderboardRow(entry: entry, metric: vm.metric)
                    .listRowBackground(Color.bizarreSurface1)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - LeaderboardRow

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let metric: LeaderboardMetric

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle().fill(rankColor.opacity(0.15)).frame(width: 40, height: 40)
                if entry.rank <= 3 {
                    Text(medalEmoji).font(.system(size: 22))
                } else {
                    Text("\(entry.rank)")
                        .font(.brandBodyLarge().monospacedDigit())
                        .foregroundStyle(rankColor)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(entry.displayName)
                    .font(entry.rank == 1 ? .brandBodyLarge().weight(.semibold) : .brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface).lineLimit(1)
                if let role = entry.role, !role.isEmpty {
                    Text(role.capitalized).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            Text(metric.formatted(entry.value))
                .font(.brandBodyLarge().monospacedDigit())
                .foregroundStyle(entry.rank == 1 ? Color.bizarreOrange : Color.bizarreOnSurface)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rank \(entry.rank): \(entry.displayName). \(metric.rawValue): \(metric.formatted(entry.value))."
        )
    }

    private var rankColor: Color {
        switch entry.rank {
        case 1:  return .yellow
        case 2:  return Color(white: 0.7)
        case 3:  return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .bizarreOnSurfaceMuted
        }
    }

    private var medalEmoji: String {
        switch entry.rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "\(entry.rank)"
        }
    }
}
