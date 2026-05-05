import SwiftUI
import Observation
import Charts
import Core
import DesignSystem
import Networking

// MARK: - ScorecardVisibility
//
// §46.4 — Scorecard private by default: only self + direct manager see it;
// owner sees all. This enum is set by the caller based on the current
// viewer's role; ScorecardViewModel enforces access before showing data.

public enum ScorecardVisibilityRole: Sendable {
    case `self`     // Viewing own scorecard — always allowed.
    case manager    // Manager viewing their direct report — allowed.
    case owner      // Owner / admin — sees all.
    case other      // No access — shows access-denied state.
}

// MARK: - ScorecardViewModel

@MainActor
@Observable
public final class ScorecardViewModel {
    public var selectedWindow: ScorecardWindow = .thirtyDays
    public private(set) var scorecard: EmployeeScorecard?
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    /// Viewer role gate — set by the host before calling `load()`.
    public var visibilityRole: ScorecardVisibilityRole = .self

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let employeeId: String

    public init(api: APIClient, employeeId: String, visibilityRole: ScorecardVisibilityRole = .self) {
        self.api = api
        self.employeeId = employeeId
        self.visibilityRole = visibilityRole
    }

    public func load() async {
        // §46.4 — Private by default: block access for 'other' roles.
        guard visibilityRole != .other else {
            errorMessage = "You don't have permission to view this scorecard."
            return
        }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            scorecard = try await api.fetchScorecard(employeeId: employeeId, windowDays: selectedWindow.rawValue)
        } catch {
            AppLog.ui.error("Scorecard load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public var compositeScore: Double {
        scorecard.map { ScorecardAggregator.compositeScore($0) } ?? 0
    }
}

// MARK: - ScorecardView

public struct ScorecardView: View {
    @State private var vm: ScorecardViewModel

    public init(api: APIClient, employeeId: String) {
        _vm = State(wrappedValue: ScorecardViewModel(api: api, employeeId: employeeId))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .onChange(of: vm.selectedWindow) { _, _ in Task { await vm.load() } }
    }

    // MARK: - Compact

    @ViewBuilder private var compactLayout: some View {
        NavigationStack {
            scorecardContent
                .navigationTitle("Scorecard")
                .toolbar { windowPicker }
        }
    }

    // MARK: - Regular (iPad)

    @ViewBuilder private var regularLayout: some View {
        NavigationSplitView {
            scorecardContent
                .navigationTitle("Scorecard")
                .toolbar { windowPicker }
        } detail: {
            if let sc = vm.scorecard {
                ScorecardDetailGrid(scorecard: sc)
            }
        }
    }

    // MARK: - Shared content

    @ViewBuilder private var scorecardContent: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let sc = vm.scorecard {
            List {
                Section("Overall") {
                    HStack {
                        Text("Composite Score")
                        Spacer()
                        Text(String(format: "%.0f / 100", vm.compositeScore))
                            .font(.headline)
                            .foregroundStyle(scoreColor(vm.compositeScore))
                    }
                }

                Section("Metrics") {
                    metricRow("Ticket Close Rate", value: String(format: "%.0f%%", sc.ticketCloseRate * 100))
                    metricRow("SLA Compliance",    value: String(format: "%.0f%%", sc.slaCompliance * 100))
                    metricRow("Avg Rating",        value: String(format: "%.1f / 5.0", sc.avgCustomerRating))
                    metricRow("Revenue",           value: sc.revenueAttributed.formatted(.currency(code: "USD")))
                    metricRow("Commission",        value: sc.commissionEarned.formatted(.currency(code: "USD")))
                    metricRow("Hours Worked",      value: String(format: "%.1f h", sc.hoursWorked))
                    metricRow("Breaks Taken",      value: "\(sc.breaksTaken)")
                    metricRow("Voids",             value: "\(sc.voidsTriggered)")
                    metricRow("Overrides",         value: "\(sc.overridesTriggered)")
                }
            }
        } else if let err = vm.errorMessage {
            ContentUnavailableView("Error", systemImage: "exclamationmark.circle",
                                   description: Text(err))
        }
    }

    @ViewBuilder private func metricRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value).foregroundStyle(.secondary)
        }
    }

    @ToolbarContentBuilder private var windowPicker: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Window", selection: $vm.selectedWindow) {
                ForEach(ScorecardWindow.allCases, id: \.self) { w in
                    Text(w.displayName).tag(w)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 75...: return .green
        case 50..<75: return .orange
        default: return .red
        }
    }
}

// MARK: - ScorecardDetailGrid (iPad detail column)

private struct ScorecardDetailGrid: View {
    let scorecard: EmployeeScorecard

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())],
                      spacing: DesignTokens.Spacing.lg) {
                metricCard("Ticket Close", String(format: "%.0f%%", scorecard.ticketCloseRate * 100), systemImage: "checkmark.seal")
                metricCard("SLA", String(format: "%.0f%%", scorecard.slaCompliance * 100), systemImage: "clock")
                metricCard("Avg Rating", String(format: "%.1f", scorecard.avgCustomerRating), systemImage: "star.fill")
                metricCard("Revenue", scorecard.revenueAttributed.formatted(.currency(code: "USD")), systemImage: "dollarsign")
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }

    @ViewBuilder private func metricCard(_ label: String, _ value: String, systemImage: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.xl)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }
}
