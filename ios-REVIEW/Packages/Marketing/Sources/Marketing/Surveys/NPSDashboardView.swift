import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
#if canImport(Charts)
import Charts
#endif

// MARK: - §37.3 NPS Dashboard — score + trend + themes

// MARK: - Models

public struct NPSSummary: Decodable, Sendable {
    /// Computed NPS score: % promoters − % detractors (−100…100).
    public let score: Int
    public let promoterPct: Double
    public let passivePct: Double
    public let detractorPct: Double
    public let responseCount: Int
    public let trend: [NPSTrendPoint]?
    public let themes: [String]?

    public init(score: Int, promoterPct: Double, passivePct: Double, detractorPct: Double,
                responseCount: Int, trend: [NPSTrendPoint]? = nil, themes: [String]? = nil) {
        self.score = score
        self.promoterPct = promoterPct
        self.passivePct = passivePct
        self.detractorPct = detractorPct
        self.responseCount = responseCount
        self.trend = trend
        self.themes = themes
    }

    enum CodingKeys: String, CodingKey {
        case score, themes
        case promoterPct   = "promoter_pct"
        case passivePct    = "passive_pct"
        case detractorPct  = "detractor_pct"
        case responseCount = "response_count"
        case trend
    }
}

public struct NPSTrendPoint: Decodable, Sendable, Identifiable {
    public var id: String { period }
    public let period: String  // "2025-03", "2025-04" etc.
    public let score: Int

    public init(period: String, score: Int) {
        self.period = period
        self.score = score
    }
}

// MARK: - Networking

extension APIClient {
    /// `GET /api/v1/surveys/nps-summary`
    public func npsSummary() async throws -> NPSSummary {
        try await get("/api/v1/surveys/nps-summary", as: NPSSummary.self)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class NPSDashboardViewModel {
    public private(set) var summary: NPSSummary?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func load() async {
        if summary == nil { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            summary = try await api.npsSummary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

#if canImport(UIKit)

public struct NPSDashboardView: View {
    @State private var vm: NPSDashboardViewModel
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: NPSDashboardViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.errorMessage {
                    errorView(err)
                } else if let s = vm.summary {
                    ScrollView {
                        VStack(spacing: BrandSpacing.lg) {
                            scoreCard(s)
                            distributionCard(s)
                            if let trend = s.trend, !trend.isEmpty {
                                trendCard(trend)
                            }
                            if let themes = s.themes, !themes.isEmpty {
                                themesCard(themes)
                            }
                        }
                        .padding(BrandSpacing.base)
                    }
                } else {
                    Text("No NPS data yet.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("NPS Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: Score card

    private func scoreCard(_ s: NPSSummary) -> some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("\(s.score > 0 ? "+" : "")\(s.score)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(npsColor(s.score))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel("NPS score \(s.score)")

            Text("Net Promoter Score")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            Text("from \(s.responseCount) response\(s.responseCount == 1 ? "" : "s")")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.lg)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(npsColor(s.score).opacity(0.3), lineWidth: 1))
    }

    // MARK: Distribution card

    private func distributionCard(_ s: NPSSummary) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Distribution")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: BrandSpacing.sm) {
                pctPill("Promoters", pct: s.promoterPct, color: .bizarreSuccess, range: "9–10")
                pctPill("Passives", pct: s.passivePct, color: .bizarreWarning, range: "7–8")
                pctPill("Detractors", pct: s.detractorPct, color: .bizarreError, range: "0–6")
            }

            // Visual bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Capsule()
                        .fill(Color.bizarreSuccess)
                        .frame(width: geo.size.width * CGFloat(s.promoterPct / 100), height: 12)
                    Capsule()
                        .fill(Color.bizarreWarning)
                        .frame(width: geo.size.width * CGFloat(s.passivePct / 100), height: 12)
                    Capsule()
                        .fill(Color.bizarreError)
                        .frame(width: geo.size.width * CGFloat(s.detractorPct / 100), height: 12)
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func pctPill(_ label: String, pct: Double, color: Color, range: String) -> some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text("\(Int(pct.rounded()))%")
                .font(.brandTitleMedium())
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurface)
            Text(range)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrandSpacing.sm)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(Int(pct.rounded()))% (scores \(range))")
    }

    // MARK: Trend card

    @ViewBuilder
    private func trendCard(_ trend: [NPSTrendPoint]) -> some View {
#if canImport(Charts)
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Trend")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            Chart(trend) { pt in
                LineMark(
                    x: .value("Period", pt.period),
                    y: .value("NPS", pt.score)
                )
                .foregroundStyle(Color.bizarreOrange)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Period", pt.period),
                    yStart: .value("Base", -100),
                    yEnd: .value("NPS", pt.score)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.bizarreOrange.opacity(0.25), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
            .chartYScale(domain: -100...100)
            .chartYAxis {
                AxisMarks(values: [-100, -50, 0, 50, 100]) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.bizarreOutline.opacity(0.4))
                    AxisValueLabel {
                        if let v = val.as(Int.self) {
                            Text("\(v > 0 ? "+" : "")\(v)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                }
            }
            .frame(height: 160)
            .accessibilityLabel("NPS trend over time: \(trend.map { "\($0.period): \($0.score)" }.joined(separator: ", "))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
#else
        EmptyView()
#endif
    }

    // MARK: Themes card

    private func themesCard(_ themes: [String]) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Common Themes")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            FlowThemeTags(themes: themes)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Common themes: \(themes.joined(separator: ", "))")
    }

    // MARK: Error view

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func npsColor(_ score: Int) -> Color {
        if score >= 50 { return .bizarreSuccess }
        if score >= 0  { return .bizarreWarning }
        return .bizarreError
    }
}

// MARK: - Flow layout for themes

private struct FlowThemeTags: View {
    let themes: [String]

    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 100), spacing: BrandSpacing.xs)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: BrandSpacing.xs) {
            ForEach(themes, id: \.self) { theme in
                Text(theme)
                    .font(.brandLabelLarge())
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .foregroundStyle(.bizarreOnSurface)
                    .background(Color.bizarreSurface2, in: Capsule())
                    .lineLimit(1)
            }
        }
    }
}

#endif
