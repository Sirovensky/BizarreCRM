import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - GoalSettingsView
//
// §46.1 — Manager configures goals per employee or shared team goal.
// Settings → Team → Goals.
// Tenant-level toggle to disable goals entirely.
// iPhone: Form. iPad: Form in NavigationSplitView detail.

@MainActor
@Observable
public final class GoalSettingsViewModel {
    /// Tenant-level toggle — persisted to server (PUT /api/v1/settings/goals).
    public var goalsEnabled: Bool = true
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // GET /api/v1/settings/goals — returns { goals_enabled: bool }
            // §74 gap: endpoint may not exist yet; tolerate 404.
            let resp = try await api.getGoalSettings()
            goalsEnabled = resp.goalsEnabled
        } catch {
            AppLog.ui.error("GoalSettings load failed: \(error.localizedDescription, privacy: .public)")
            // Non-fatal — keep default enabled.
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await api.updateGoalSettings(enabled: goalsEnabled)
        } catch {
            AppLog.ui.error("GoalSettings save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct GoalSettingsView: View {
    @State private var vm: GoalSettingsViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: GoalSettingsViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section {
                Toggle(isOn: $vm.goalsEnabled) {
                    Label("Enable Goals", systemImage: "target")
                }
                .onChange(of: vm.goalsEnabled) { _, _ in
                    Task { await vm.save() }
                }
                .accessibilityLabel("Enable goal tracking for this shop")

                if !vm.goalsEnabled {
                    Text("Goals and leaderboards are disabled for all staff.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityLabel("Goals disabled notice")
                }
            } header: {
                Text("Goal Tracking")
            } footer: {
                Text("When disabled, no goals, progress rings, or milestone notifications will appear for any employee.")
                    .font(.brandLabelSmall())
            }

            if vm.goalsEnabled {
                Section("Gamification Safety") {
                    Label("Milestone celebrations (50%, 75%, 100%)", systemImage: "star")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("Milestone celebrations enabled")
                    Label("Supportive miss messages — no guilt language", systemImage: "heart")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("Supportive miss messages — no guilt language")
                    Label("No daily push notifications on missed goals", systemImage: "bell.slash")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("No daily push notifications on missed goals")
                }
            }

            if let err = vm.errorMessage {
                Section {
                    Text(err).foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(err)")
                }
            }
        }
        .navigationTitle("Goals Settings")
        .task { await vm.load() }
        .overlay {
            if vm.isSaving { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }
}

// MARK: - GoalTrajectoryView

/// §46.1 — Historical vs target vs forecast curve for a single goal.
/// Uses a simple linear projection as forecast (no ML needed).
public struct GoalTrajectoryView: View {
    public let goal: Goal
    /// Daily value observations: [(date, actualValue)], sorted ascending.
    public let history: [(date: Date, value: Double)]

    public init(goal: Goal, history: [(date: Date, value: Double)]) {
        self.goal = goal
        self.history = history
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Trajectory")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)

            // Simple bar chart approximation using GeometryReader.
            GeometryReader { geo in
                let barWidth = max(4, geo.size.width / CGFloat(max(history.count, 1)) - 2)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, pair in
                        let fraction = goal.targetValue > 0
                            ? min(pair.value / goal.targetValue, 1.0)
                            : 0
                        VStack(spacing: 0) {
                            Spacer()
                            RoundedRectangle(cornerRadius: 2)
                                .fill(fraction >= 1.0 ? Color.green : Color.bizarreOrange)
                                .frame(width: barWidth, height: max(2, geo.size.height * CGFloat(fraction)))
                        }
                    }
                    // Forecast bar
                    if let forecast = forecastValue {
                        let frac = min(forecast / goal.targetValue, 1.0)
                        VStack(spacing: 0) {
                            Spacer()
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.bizarreOnSurfaceMuted.opacity(0.4))
                                .frame(width: barWidth, height: max(2, geo.size.height * CGFloat(frac)))
                        }
                        .accessibilityLabel("Forecast: \(Int(frac * 100))%")
                    }
                }
            }
            .frame(height: 60)
            .accessibilityLabel("Goal trajectory chart, \(history.count) data points")

            // Miss message
            if isMissed {
                Text("Tomorrow's a new day. Keep going!")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Supportive message: Tomorrow's a new day. Keep going!")
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private var isMissed: Bool {
        goal.status == .missed
    }

    private var forecastValue: Double? {
        guard history.count >= 2 else { return nil }
        let totalDays = goal.endDate.timeIntervalSince(goal.startDate) / 86400
        guard totalDays > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(goal.startDate) / 86400
        let rate = (history.last?.value ?? 0) / max(elapsed, 1)
        return rate * totalDays
    }
}

// MARK: - APIClient extensions for goal settings

public struct GoalSettingsResponse: Decodable, Sendable {
    public let goalsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case goalsEnabled = "goals_enabled"
    }
}

public extension APIClient {
    func getGoalSettings() async throws -> GoalSettingsResponse {
        try await get("/api/v1/settings/goals", as: GoalSettingsResponse.self)
    }

    func updateGoalSettings(enabled: Bool) async throws {
        _ = try await patch("/api/v1/settings/goals", body: GoalSettingsBody(goalsEnabled: enabled), as: GoalSettingsResponse.self)
    }
}

private struct GoalSettingsBody: Encodable, Sendable {
    let goalsEnabled: Bool
    enum CodingKeys: String, CodingKey { case goalsEnabled = "goals_enabled" }
}
