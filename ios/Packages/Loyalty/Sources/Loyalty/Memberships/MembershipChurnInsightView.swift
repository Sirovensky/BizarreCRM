import SwiftUI
import Charts
import DesignSystem
import Networking
import Core

// §38 — Churn insight report: expiring soon / at risk / churned members.
// Surfaces in Loyalty → Memberships → Churn tab.

// MARK: - Models

public struct MembershipChurnCohort: Decodable, Sendable {
    /// Members whose membership expires within 30 days.
    public let expiringSoon: [ChurnMemberRow]
    /// Members who have not used their membership in > 60 days (at-risk).
    public let atRisk: [ChurnMemberRow]
    /// Members who lapsed / churned in the last 90 days.
    public let churned: [ChurnMemberRow]
    /// Count-over-time data points for the churn trend sparkline.
    public let trendPoints: [ChurnTrendPoint]

    enum CodingKeys: String, CodingKey {
        case expiringSoon = "expiring_soon"
        case atRisk       = "at_risk"
        case churned
        case trendPoints  = "trend_points"
    }
}

public struct ChurnMemberRow: Decodable, Sendable, Identifiable {
    public let id: Int64             // membership id
    public let customerId: Int64
    public let customerName: String
    public let planName: String
    public let expiresAt: String?
    public let lastActivityAt: String?
    public let ltvCents: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case customerId    = "customer_id"
        case customerName  = "customer_name"
        case planName      = "plan_name"
        case expiresAt     = "expires_at"
        case lastActivityAt = "last_activity_at"
        case ltvCents      = "ltv_cents"
    }
}

public struct ChurnTrendPoint: Decodable, Sendable, Identifiable {
    public let id: String { periodLabel }
    public let periodLabel: String    // e.g. "Apr 2026"
    public let churnedCount: Int
    public let newCount: Int

    enum CodingKeys: String, CodingKey {
        case periodLabel   = "period_label"
        case churnedCount  = "churned_count"
        case newCount      = "new_count"
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class MembershipChurnInsightViewModel {
    public enum State: Sendable, Equatable {
        case loading, loaded, failed(String)
    }

    public private(set) var state: State = .loading
    public private(set) var cohort: MembershipChurnCohort?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        state = .loading
        do {
            cohort = try await api.membershipChurnCohort()
            state = .loaded
        } catch {
            AppLog.ui.error("Churn cohort load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - View

public struct MembershipChurnInsightView: View {
    @State private var vm: MembershipChurnInsightViewModel
    @State private var selectedTab: ChurnTab = .expiringSoon

    public init(api: APIClient) {
        _vm = State(wrappedValue: MembershipChurnInsightViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            switch vm.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle",
                                       description: Text(msg))
            case .loaded:
                if let cohort = vm.cohort {
                    loadedContent(cohort)
                }
            }
        }
        .navigationTitle("Churn Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private func loadedContent(_ cohort: MembershipChurnCohort) -> some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                summaryTiles(cohort)
                if !cohort.trendPoints.isEmpty {
                    trendChart(cohort.trendPoints)
                }
                tabPicker
                cohortList(cohort)
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: Summary tiles

    private func summaryTiles(_ cohort: MembershipChurnCohort) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: BrandSpacing.sm) {
            ChurnTile(label: "Expiring soon", count: cohort.expiringSoon.count, color: .bizarreWarning)
            ChurnTile(label: "At risk", count: cohort.atRisk.count, color: .bizarreOrange)
            ChurnTile(label: "Churned (90d)", count: cohort.churned.count, color: .bizarreError)
        }
    }

    // MARK: Trend chart

    @ViewBuilder
    private func trendChart(_ points: [ChurnTrendPoint]) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Churn vs New members (last 6 mo)")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
            Chart(points) { p in
                BarMark(x: .value("Period", p.periodLabel),
                        y: .value("Churned", p.churnedCount))
                .foregroundStyle(Color.bizarreError.opacity(0.7))
                BarMark(x: .value("Period", p.periodLabel),
                        y: .value("New", p.newCount))
                .foregroundStyle(Color.bizarreTeal.opacity(0.7))
            }
            .chartXAxis { AxisMarks(values: .automatic) { AxisValueLabel().font(.brandLabelSmall()) } }
            .chartYAxis { AxisMarks(values: .automatic) { AxisValueLabel().font(.brandLabelSmall()) } }
            .frame(height: 140)
            .accessibilityLabel("Churn versus new members bar chart over the last 6 months")
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Tab picker

    private var tabPicker: some View {
        Picker("Cohort", selection: $selectedTab) {
            ForEach(ChurnTab.allCases, id: \.self) { tab in
                Text(tab.displayName).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Churn cohort picker")
    }

    // MARK: Cohort list

    @ViewBuilder
    private func cohortList(_ cohort: MembershipChurnCohort) -> some View {
        let rows: [ChurnMemberRow] = {
            switch selectedTab {
            case .expiringSoon: return cohort.expiringSoon
            case .atRisk:       return cohort.atRisk
            case .churned:      return cohort.churned
            }
        }()

        if rows.isEmpty {
            Text("No members in this cohort.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(BrandSpacing.xl)
        } else {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    ChurnMemberRowView(row: row, tab: selectedTab)
                    Divider().overlay(Color.bizarreOutline.opacity(0.2))
                }
            }
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Supporting types

public enum ChurnTab: String, CaseIterable {
    case expiringSoon, atRisk, churned

    public var displayName: String {
        switch self {
        case .expiringSoon: return "Expiring"
        case .atRisk:       return "At Risk"
        case .churned:      return "Churned"
        }
    }
}

private struct ChurnTile: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: BrandSpacing.xs) {
            Text("\(count)")
                .font(.brandTitleLarge())
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.md)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(count)")
    }
}

private struct ChurnMemberRowView: View {
    let row: ChurnMemberRow
    let tab: ChurnTab

    private var dateLabel: String {
        switch tab {
        case .expiringSoon:
            return row.expiresAt.map { "Expires \(shortDate($0))" } ?? "—"
        case .atRisk:
            return row.lastActivityAt.map { "Last active \(shortDate($0))" } ?? "—"
        case .churned:
            return row.expiresAt.map { "Lapsed \(shortDate($0))" } ?? "—"
        }
    }

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.customerName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Text(row.planName)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: BrandSpacing.sm)
            Text(dateLabel)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.customerName), \(row.planName), \(dateLabel)")
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        guard let d = f.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: d)
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `GET /api/v1/memberships/churn-cohort` — expiring / at-risk / churned member lists.
    func membershipChurnCohort() async throws -> MembershipChurnCohort {
        try await get("/api/v1/memberships/churn-cohort", as: MembershipChurnCohort.self)
    }
}
