#if canImport(UIKit)
import SwiftUI
import Charts
import Core
import DesignSystem
import Networking

// MARK: - DiscountEffectivenessView (§16 discount reporting)

/// Manager-facing report showing discount usage, revenue impact, and margin impact.
///
/// Accessible via **Settings → Pricing rules → Effectiveness** and also
/// surfaced as a dashboard card in the manager POS shift summary.
///
/// **Metrics displayed:**
/// - Total discount events (count of redemptions per rule)
/// - Revenue impact ($ total discounted off)
/// - Margin impact (estimated margin reduction, when COGS is available)
/// - Top 5 rules by usage
/// - Trend chart (daily discount totals, last 30 days)
///
/// iPhone: stacked list + bar chart.
/// iPad: 2-column grid (metrics | chart).
///
/// Data: `GET /pos/discount-effectiveness?from=&to=` → `DiscountEffectivenessResponse`.
@MainActor
public struct DiscountEffectivenessView: View {

    // MARK: - ViewModel

    @State private var vm: DiscountEffectivenessViewModel

    // MARK: - Init

    public init(api: APIClient? = nil) {
        _vm = State(wrappedValue: DiscountEffectivenessViewModel(api: api))
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                padLayout
            }
        }
        .navigationTitle("Discount Effectiveness")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { periodPicker }
        .task { await vm.load() }
    }

    // MARK: - Phone layout

    private var phoneLayout: some View {
        List {
            if vm.isLoading {
                loadingSection
            } else if let error = vm.error {
                errorSection(error)
            } else {
                summarySection
                trendSection
                rulesSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - iPad layout

    private var padLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            List {
                if vm.isLoading {
                    loadingSection
                } else if let error = vm.error {
                    errorSection(error)
                } else {
                    summarySection
                    rulesSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .frame(minWidth: 300, idealWidth: 360)

            Divider()

            List {
                if vm.isLoading {
                    loadingSection
                } else if vm.error == nil {
                    trendSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        }
    }

    // MARK: - Loading

    private var loadingSection: some View {
        Section {
            HStack {
                ProgressView()
                Text("Loading discount data…")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityIdentifier("discount.effectiveness.loading")
        }
    }

    // MARK: - Error

    private func errorSection(_ msg: String) -> some View {
        Section {
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreWarning)
                .accessibilityIdentifier("discount.effectiveness.error")
        }
    }

    // MARK: - Summary KPI cards

    @ViewBuilder
    private var summarySection: some View {
        Section("Summary") {
            kpiRow(
                title: "Total events",
                value: "\(vm.summary.totalEvents)",
                subtitle: "discount redemptions",
                icon: "tag.fill",
                color: BrandPalette.primary
            )
            kpiRow(
                title: "Revenue impact",
                value: CartMath.formatCents(vm.summary.totalDiscountedCents),
                subtitle: "total discounted off",
                icon: "dollarsign.circle.fill",
                color: .bizarreError
            )
            if vm.summary.marginImpactCents > 0 {
                kpiRow(
                    title: "Margin impact",
                    value: CartMath.formatCents(vm.summary.marginImpactCents),
                    subtitle: "estimated margin reduction",
                    icon: "chart.line.downtrend.xyaxis",
                    color: .bizarreWarning
                )
            }
        }
    }

    private func kpiRow(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(title)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(value)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                Text(subtitle)
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value), \(subtitle)")
    }

    // MARK: - Trend chart (last 30 days)

    @ViewBuilder
    private var trendSection: some View {
        Section("Daily discount trend (30 days)") {
            if vm.dailyPoints.isEmpty {
                Text("No data for selected period")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityIdentifier("discount.effectiveness.noTrend")
            } else {
                Chart(vm.dailyPoints) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Discounted ($)", Double(point.discountedCents) / 100.0)
                    )
                    .foregroundStyle(BrandPalette.primary.gradient)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text("$\(Int(d))")
                                    .font(.brandBodySmall())
                            }
                        }
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Bar chart of daily discount totals over the last 30 days")
                .accessibilityIdentifier("discount.effectiveness.chart")
            }
        }
    }

    // MARK: - Top rules

    @ViewBuilder
    private var rulesSection: some View {
        Section("Top discount rules") {
            if vm.topRules.isEmpty {
                Text("No rules in selected period")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(vm.topRules) { rule in
                    ruleRow(rule)
                }
            }
        }
    }

    private func ruleRow(_ rule: DiscountRuleStats) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(rule.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                HStack(spacing: BrandSpacing.xs) {
                    Text("\(rule.usageCount) uses")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("·")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("-\(CartMath.formatCents(rule.totalDiscountedCents))")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreError)
                        .monospacedDigit()
                }
            }
            Spacer()
            if rule.marginImpactCents > 0 {
                Text("-\(CartMath.formatCents(rule.marginImpactCents)) margin")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreWarning)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.name): \(rule.usageCount) uses, \(CartMath.formatCents(rule.totalDiscountedCents)) discounted")
        .accessibilityIdentifier("discount.effectiveness.rule.\(rule.id)")
    }

    // MARK: - Period picker toolbar

    @ToolbarContentBuilder
    private var periodPicker: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(DiscountEffectivenessViewModel.Period.allCases) { period in
                    Button(period.label) {
                        Task { await vm.changePeriod(period) }
                    }
                }
            } label: {
                Label(vm.selectedPeriod.label, systemImage: "calendar")
            }
            .accessibilityIdentifier("discount.effectiveness.periodPicker")
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class DiscountEffectivenessViewModel {

    // MARK: - Types

    enum Period: String, CaseIterable, Identifiable, Sendable {
        case today = "today"
        case week  = "week"
        case month = "month"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: return "Today"
            case .week:  return "Last 7 days"
            case .month: return "Last 30 days"
            }
        }

        var fromDate: Date {
            let cal = Calendar.current
            switch self {
            case .today: return cal.startOfDay(for: .now)
            case .week:  return cal.date(byAdding: .day, value: -7, to: .now) ?? .now
            case .month: return cal.date(byAdding: .day, value: -30, to: .now) ?? .now
            }
        }
    }

    // MARK: - State

    var isLoading = false
    var error: String?
    var summary: DiscountEffectivenessSummary = .empty
    var dailyPoints: [DailyDiscountPoint] = []
    var topRules: [DiscountRuleStats] = []
    var selectedPeriod: Period = .month

    @ObservationIgnored let api: APIClient?

    init(api: APIClient?) {
        self.api = api
    }

    // MARK: - Load

    func load() async {
        guard let api else {
            error = "No server connection."
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let resp = try await api.getDiscountEffectiveness(
                from: selectedPeriod.fromDate,
                to: .now
            )
            summary = resp.summary
            dailyPoints = resp.daily
            topRules = resp.topRules
        } catch let APITransportError.httpStatus(code, _) where code == 404 || code == 501 {
            error = "Discount analytics not yet enabled on this server."
            summary = .empty
        } catch {
            self.error = error.localizedDescription
        }
    }

    func changePeriod(_ period: Period) async {
        selectedPeriod = period
        await load()
    }
}

// MARK: - Models

public struct DiscountEffectivenessSummary: Sendable {
    public let totalEvents: Int
    public let totalDiscountedCents: Int
    public let marginImpactCents: Int

    public static let empty = DiscountEffectivenessSummary(
        totalEvents: 0, totalDiscountedCents: 0, marginImpactCents: 0
    )

    public init(totalEvents: Int, totalDiscountedCents: Int, marginImpactCents: Int) {
        self.totalEvents = totalEvents
        self.totalDiscountedCents = totalDiscountedCents
        self.marginImpactCents = marginImpactCents
    }
}

public struct DailyDiscountPoint: Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let discountedCents: Int

    public init(date: Date, discountedCents: Int) {
        self.id = UUID()
        self.date = date
        self.discountedCents = discountedCents
    }
}

public struct DiscountRuleStats: Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let usageCount: Int
    public let totalDiscountedCents: Int
    public let marginImpactCents: Int
}

private struct DiscountEffectivenessResponse: Decodable {
    let summary: DiscountEffectivenessSummary
    let daily: [DailyDiscountPoint]
    let topRules: [DiscountRuleStats]

    enum CodingKeys: String, CodingKey {
        case summary
        case daily
        case topRules = "top_rules"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawSummary = try c.decode(RawSummary.self, forKey: .summary)
        summary = DiscountEffectivenessSummary(
            totalEvents: rawSummary.totalEvents,
            totalDiscountedCents: rawSummary.totalDiscountedCents,
            marginImpactCents: rawSummary.marginImpactCents ?? 0
        )
        let rawDaily = try c.decode([RawDaily].self, forKey: .daily)
        daily = rawDaily.compactMap { d -> DailyDiscountPoint? in
            guard let date = ISO8601DateFormatter().date(from: d.date) else { return nil }
            return DailyDiscountPoint(date: date, discountedCents: d.discountedCents)
        }
        topRules = try c.decode([DiscountRuleStats].self, forKey: .topRules)
    }

    struct RawSummary: Decodable {
        let totalEvents: Int
        let totalDiscountedCents: Int
        let marginImpactCents: Int?
        enum CodingKeys: String, CodingKey {
            case totalEvents        = "total_events"
            case totalDiscountedCents = "total_discounted_cents"
            case marginImpactCents  = "margin_impact_cents"
        }
    }

    struct RawDaily: Decodable {
        let date: String
        let discountedCents: Int
        enum CodingKeys: String, CodingKey {
            case date
            case discountedCents = "discounted_cents"
        }
    }
}

extension DiscountRuleStats: Decodable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case usageCount       = "usage_count"
        case totalDiscountedCents = "total_discounted_cents"
        case marginImpactCents = "margin_impact_cents"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        usageCount = try c.decode(Int.self, forKey: .usageCount)
        totalDiscountedCents = try c.decode(Int.self, forKey: .totalDiscountedCents)
        marginImpactCents = (try? c.decodeIfPresent(Int.self, forKey: .marginImpactCents)) ?? 0
    }
}

// MARK: - APIClient extension

private extension APIClient {
    func getDiscountEffectiveness(from: Date, to: Date) async throws -> DiscountEffectivenessResponse {
        let fmt = ISO8601DateFormatter()
        return try await get(
            "/api/v1/pos/discount-effectiveness",
            query: [
                URLQueryItem(name: "from", value: fmt.string(from: from)),
                URLQueryItem(name: "to",   value: fmt.string(from: to))
            ],
            as: DiscountEffectivenessResponse.self
        )
    }
}
#endif
