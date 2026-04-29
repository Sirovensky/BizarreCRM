import SwiftUI
import Charts
import DesignSystem

// MARK: - CSATSurveyResponse (local model for detail view)

public struct CSATSurveyResponse: Codable, Sendable, Identifiable {
    public let id: Int64
    public let score: Int       // 1–5
    public let comment: String?
    public let respondedAt: String

    enum CodingKeys: String, CodingKey {
        case id, score, comment
        case respondedAt = "responded_at"
    }

    public init(id: Int64, score: Int, comment: String?, respondedAt: String) {
        self.id = id
        self.score = score
        self.comment = comment
        self.respondedAt = respondedAt
    }
}

// MARK: - CSATDetailView

public struct CSATDetailView: View {
    public let score: CSATScore
    /// Optional drill-through responses; caller passes if pre-fetched.
    public let responses: [CSATSurveyResponse]

    public init(score: CSATScore, responses: [CSATSurveyResponse] = []) {
        self.score = score
        self.responses = responses
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scoreBuckets: [(score: Int, count: Int)] {
        let all = responses.map(\.score)
        return (1...5).map { s in (score: s, count: all.filter { $0 == s }.count) }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        summaryCard
                        scoreDistChart
                        if !responses.isEmpty { commentsList }
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("CSAT Detail")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var summaryCard: some View {
        HStack(spacing: BrandSpacing.xl) {
            Gauge(value: score.current, in: 1...5) {
                EmptyView()
            } currentValueLabel: {
                Text(String(format: "%.1f", score.current))
                    .font(.brandHeadlineMedium())
            }
            .gaugeStyle(.accessoryCircular)
            .tint(gaugeColor(score.current))
            .frame(width: 80, height: 80)
            .accessibilityLabel("CSAT score \(String(format: "%.1f", score.current)) out of 5")

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(String(format: "%.1f / 5.0", score.current))
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(score.responseCount) responses")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                trendBadge
            }
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var trendBadge: some View {
        let isUp = score.trendPct >= 0
        return HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(String(format: "%.1f%% vs prior period", abs(score.trendPct)))
                .font(.brandLabelLarge())
        }
        .foregroundStyle(isUp ? Color.bizarreSuccess : Color.bizarreError)
        .accessibilityLabel("Trend: \(isUp ? "up" : "down") \(String(format: "%.1f", abs(score.trendPct))) percent")
    }

    @ViewBuilder
    private var scoreDistChart: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Score Distribution")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            if scoreBuckets.isEmpty {
                emptySparklineSilhouette
                    .frame(height: 160)
            } else {
                Chart(scoreBuckets, id: \.score) { bucket in
                    BarMark(
                        x: .value("Score", "\(bucket.score) ★"),
                        y: .value("Count", bucket.count)
                    )
                    .foregroundStyle(barColor(bucket.score))
                    .cornerRadius(DesignTokens.Radius.xs)
                }
                .frame(height: 160)
                .chartXAxisLabel("Score", alignment: .center)
                .chartYAxisLabel("Responses", position: .leading)
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel()
                            .font(.system(size: 12))
                            .foregroundStyle(Color.bizarreOnSurface)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.smooth), value: scoreBuckets.map(\.count))
                .accessibilityChartDescriptor(CSATDistChartDescriptor(buckets: scoreBuckets))
                // Legend with color names (§91.13 item 4)
                csatLegend
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    @ViewBuilder
    private var commentsList: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Comments")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            ForEach(responses.filter { $0.comment != nil }) { r in
                commentCard(r)
            }
        }
    }

    private func commentCard(_ r: CSATSurveyResponse) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Text("\(r.score)★")
                .font(.brandLabelLarge())
                .foregroundStyle(barColor(r.score))
                .frame(width: BrandSpacing.xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                if let comment = r.comment {
                    Text(comment)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                Text(r.respondedAt)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.score) stars. \(r.comment ?? "No comment"). \(r.respondedAt).")
    }

    // MARK: - CSAT chart legend + empty silhouette

    private var csatLegend: some View {
        let entries: [(String, Color)] = [
            ("5★ (green)", .bizarreSuccess),
            ("4★ (teal)", .bizarreTeal),
            ("3★ (amber)", .bizarreWarning),
            ("2★ (orange)", .bizarreOrange),
            ("1★ (red)", .bizarreError),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(entries, id: \.0) { (label, color) in
                    HStack(spacing: BrandSpacing.xxs) {
                        Circle().fill(color).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(label)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chart legend: 5 stars green, 4 stars teal, 3 stars amber, 2 stars orange, 1 star red")
    }

    private var emptySparklineSilhouette: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let barHeights: [CGFloat] = [0.2, 0.35, 0.6, 0.85, 0.45]
            let barW = w / CGFloat(barHeights.count * 2)
            Path { path in
                for (i, frac) in barHeights.enumerated() {
                    let x = CGFloat(i) * barW * 2 + barW * 0.5
                    let barH = h * frac
                    path.addRoundedRect(
                        in: CGRect(x: x, y: h - barH, width: barW, height: barH),
                        cornerSize: CGSize(width: 3, height: 3)
                    )
                }
            }
            .stroke(
                Color.bizarreOnSurface.opacity(0.18),
                style: StrokeStyle(lineWidth: 2, dash: [5, 3])
            )
        }
        .overlay(alignment: .center) {
            Text("No data")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityLabel("No CSAT score distribution data")
    }

    private func gaugeColor(_ v: Double) -> Color {
        if v >= 4.5 { return .bizarreSuccess }
        if v >= 3.5 { return .bizarreWarning }
        return .bizarreError
    }

    private func barColor(_ score: Int) -> Color {
        switch score {
        case 5:   return .bizarreSuccess
        case 4:   return .bizarreTeal
        case 3:   return .bizarreWarning
        case 2:   return .bizarreOrange
        default:  return .bizarreError
        }
    }
}

// MARK: - AXChartDescriptor

private struct CSATDistChartDescriptor: AXChartDescriptorRepresentable {
    let buckets: [(score: Int, count: Int)]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Score", categoryOrder: buckets.map { "\($0.score) ★" })
        let yAxis = AXNumericDataAxisDescriptor(title: "Responses", range: 0...Double(buckets.map(\.count).max() ?? 1), gridlinePositions: []) { "\(Int($0))" }
        let series = AXDataSeriesDescriptor(name: "Responses per Score", isContinuous: false, dataPoints: buckets.map { b in
            AXDataPoint(x: "\(b.score) ★", y: Double(b.count))
        })
        return AXChartDescriptor(title: "CSAT Score Distribution", summary: "Bar chart of survey responses by score 1 to 5", xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}
