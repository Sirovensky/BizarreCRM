import SwiftUI
import Charts
import DesignSystem

// MARK: - NPSTechBreakdown (anonymized per §37)

public struct NPSTechBreakdown: Codable, Sendable, Identifiable {
    /// Anonymized identifier — display "Tech A", "Tech B", etc.
    public let id: Int64
    public let anonymizedLabel: String
    public let npsScore: Int
    public let promoterPct: Double
    public let detractorPct: Double
    public let responseCount: Int

    public var passivePct: Double { max(0, 100.0 - promoterPct - detractorPct) }

    enum CodingKeys: String, CodingKey {
        case id
        case anonymizedLabel  = "anonymized_label"
        case npsScore         = "nps_score"
        case promoterPct      = "promoter_pct"
        case detractorPct     = "detractor_pct"
        case responseCount    = "response_count"
    }

    public init(id: Int64, anonymizedLabel: String, npsScore: Int,
                promoterPct: Double, detractorPct: Double, responseCount: Int) {
        self.id = id
        self.anonymizedLabel = anonymizedLabel
        self.npsScore = npsScore
        self.promoterPct = promoterPct
        self.detractorPct = detractorPct
        self.responseCount = responseCount
    }
}

// MARK: - NPSDetailView

public struct NPSDetailView: View {
    public let score: NPSScore
    /// Per-tech breakdown — anonymized by default (§37 privacy).
    public let techBreakdown: [NPSTechBreakdown]

    public init(score: NPSScore, techBreakdown: [NPSTechBreakdown] = []) {
        self.score = score
        self.techBreakdown = techBreakdown
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        summaryCard
                        splitSection
                        themeSection
                        if !techBreakdown.isEmpty { techSection }
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("NPS Detail")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        HStack(spacing: BrandSpacing.xl) {
            Gauge(value: Double(score.current + 100), in: 0...200) {
                EmptyView()
            } currentValueLabel: {
                Text("\(score.current)")
                    .font(.brandHeadlineMedium())
            }
            .gaugeStyle(.accessoryCircular)
            .tint(npsColor(score.current))
            .frame(width: 80, height: 80)
            .accessibilityLabel("NPS score \(score.current)")

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Score: \(score.current)")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                trendLabel
            }
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var trendLabel: some View {
        let delta = score.current - score.previous
        let isUp = delta >= 0
        return HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(isUp ? "+\(delta) vs prior period" : "\(delta) vs prior period")
                .font(.brandLabelLarge())
        }
        .foregroundStyle(isUp ? Color.bizarreSuccess : Color.bizarreError)
        .accessibilityLabel("NPS trend: \(isUp ? "up" : "down") \(abs(delta)) points from prior period")
    }

    // MARK: - Promoter/Passive/Detractor

    @ViewBuilder
    private var splitSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Promoter / Passive / Detractor")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            let segments: [(label: String, pct: Double, color: Color)] = [
                ("Promoters",  score.promoterPct,  .bizarreSuccess),
                ("Passives",   score.passivePct,   .bizarreWarning),
                ("Detractors", score.detractorPct, .bizarreError)
            ]
            Chart(segments, id: \.label) { seg in
                BarMark(
                    x: .value("Percent", seg.pct),
                    y: .value("Category", seg.label)
                )
                .foregroundStyle(seg.color)
                .annotation(position: .trailing) {
                    Text(String(format: "%.1f%%", seg.pct))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .frame(height: 120)
            .chartXAxisLabel("Percentage", alignment: .center)
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.system(size: 12))
                        .foregroundStyle(Color.bizarreOnSurface)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.smooth), value: score.current)
            .accessibilityChartDescriptor(NPSSplitDescriptor(score: score))
            // Legend with color-name pairs (§91.13 item 4)
            HStack(spacing: BrandSpacing.md) {
                ForEach(segments, id: \.label) { seg in
                    HStack(spacing: BrandSpacing.xxs) {
                        Circle().fill(seg.color).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(seg.label)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "NPS legend: Promoters (green) \(String(format: "%.1f", score.promoterPct))%, Passives (amber) \(String(format: "%.1f", score.passivePct))%, Detractors (red) \(String(format: "%.1f", score.detractorPct))%"
            )
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Themes

    @ViewBuilder
    private var themeSection: some View {
        if !score.themes.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Top Themes")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)

                FlowLayout(spacing: BrandSpacing.sm) {
                    ForEach(score.themes, id: \.self) { theme in
                        Text(theme)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurface)
                            .padding(.horizontal, BrandSpacing.sm)
                            .padding(.vertical, BrandSpacing.xxs)
                            .background(Color.bizarreTeal.opacity(0.15), in: Capsule())
                    }
                }
            }
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Top themes: \(score.themes.joined(separator: ", "))")
        }
    }

    // MARK: - Per-tech (anonymized)

    @ViewBuilder
    private var techSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Per-Tech Breakdown")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Anonymized")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            ForEach(techBreakdown) { tech in
                techRow(tech)
                Divider()
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func techRow(_ tech: NPSTechBreakdown) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(tech.anonymizedLabel)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(tech.responseCount) responses")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Text("NPS \(tech.npsScore)")
                .font(.brandTitleSmall())
                .foregroundStyle(npsColor(tech.npsScore))
        }
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tech.anonymizedLabel): NPS \(tech.npsScore), \(tech.responseCount) responses.")
    }

    private func npsColor(_ nps: Int) -> Color {
        if nps >= 50 { return .bizarreSuccess }
        if nps >= 0  { return .bizarreWarning }
        return .bizarreError
    }
}

// MARK: - FlowLayout (simple horizontal wrapping)

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

// MARK: - AXChartDescriptor

private struct NPSSplitDescriptor: AXChartDescriptorRepresentable {
    let score: NPSScore

    func makeChartDescriptor() -> AXChartDescriptor {
        let labels = ["Promoters", "Passives", "Detractors"]
        let values = [score.promoterPct, score.passivePct, score.detractorPct]
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Category", categoryOrder: labels)
        let yAxis = AXNumericDataAxisDescriptor(title: "Percentage", range: 0...100, gridlinePositions: []) { "\(Int($0))%" }
        let series = AXDataSeriesDescriptor(name: "NPS Split", isContinuous: false, dataPoints: zip(labels, values).map { label, pct in
            AXDataPoint(x: label, y: pct)
        })
        return AXChartDescriptor(title: "NPS Promoter/Passive/Detractor Split", summary: "Horizontal bar chart of NPS segment percentages", xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}
