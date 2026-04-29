import SwiftUI
import Charts
import DesignSystem

// MARK: - NPSScoreCard

public struct NPSScoreCard: View {
    public let score: NPSScore?
    public let onDetail: (() -> Void)?

    public init(score: NPSScore?, onDetail: (() -> Void)? = nil) {
        self.score = score
        self.onDetail = onDetail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if let s = score {
                if s.respondentCount < 10 {
                    insufficientDataView(s)
                } else {
                    gaugeRow(s)
                    splitBar(s)
                    themeChips(s.themes)
                }
            } else {
                HStack(spacing: BrandSpacing.sm) {
                    ProgressView()
                    Text("Loading…")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, BrandSpacing.sm)
                .accessibilityLabel("Loading NPS score")
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .onTapGesture { onDetail?() }
    }

    private var cardHeader: some View {
        HStack {
            Image(systemName: "heart.fill")
                .foregroundStyle(.bizarreMagenta)
                .accessibilityHidden(true)
            Text("NPS")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            if onDetail != nil {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func insufficientDataView(_ s: NPSScore) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .imageScale(.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not enough data")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Need 10+ responses · \(s.respondentCount) so far")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityLabel("NPS not enough data. Need 10 or more responses. \(s.respondentCount) received so far.")
    }

    private func gaugeRow(_ s: NPSScore) -> some View {
        HStack(spacing: BrandSpacing.lg) {
            Gauge(value: Double(s.current + 100), in: 0...200) {
                EmptyView()
            } currentValueLabel: {
                Text("\(s.current)")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(npsColor(s.current))
            .frame(width: 72, height: 72)
            .accessibilityLabel("NPS score \(s.current)")

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Score: \(s.current)")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                trendLabel(s)
            }
        }
    }

    @ViewBuilder
    private func trendLabel(_ s: NPSScore) -> some View {
        let delta = s.current - s.previous
        let isUp = delta >= 0
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(isUp ? "+\(delta)" : "\(delta)")
                .font(.brandLabelLarge())
        }
        .foregroundStyle(isUp ? Color.bizarreSuccess : Color.bizarreError)
        .accessibilityLabel("NPS trend: \(isUp ? "up" : "down") \(abs(delta)) points from prior period")
    }

    @ViewBuilder
    private func splitBar(_ s: NPSScore) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Color.bizarreSuccess)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: s.promoterPct / 100.0, anchor: .leading)
                    .frame(height: 8)
                Rectangle()
                    .fill(Color.bizarreWarning.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: s.passivePct / 100.0, anchor: .leading)
                    .frame(height: 8)
                Rectangle()
                    .fill(Color.bizarreError)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: s.detractorPct / 100.0, anchor: .leading)
                    .frame(height: 8)
            }
            .clipShape(Capsule())
            .accessibilityHidden(true)

            HStack {
                legendChip("Promoters", pct: s.promoterPct, color: .bizarreSuccess)
                legendChip("Passives", pct: s.passivePct, color: .bizarreWarning)
                legendChip("Detractors", pct: s.detractorPct, color: .bizarreError)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "NPS legend: Promoters (green) \(String(format: "%.0f", s.promoterPct))%, Passives (amber) \(String(format: "%.0f", s.passivePct))%, Detractors (red) \(String(format: "%.0f", s.detractorPct))%"
            )
        }
    }

    private func legendChip(_ label: String, pct: Double, color: Color) -> some View {
        HStack(spacing: BrandSpacing.xxs) {
            Circle().fill(color).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text("\(label) \(String(format: "%.0f%%", pct))")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func themeChips(_ themes: [String]) -> some View {
        if !themes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.xs) {
                    ForEach(themes, id: \.self) { theme in
                        Text(theme)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurface)
                            .padding(.horizontal, BrandSpacing.sm)
                            .padding(.vertical, BrandSpacing.xxs)
                            .background(Color.bizarreSurface2, in: Capsule())
                    }
                }
                .padding(.horizontal, BrandSpacing.xs)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Themes: \(themes.joined(separator: ", "))")
        }
    }

    private func npsColor(_ nps: Int) -> Color {
        if nps >= 50 { return .bizarreSuccess }
        if nps >= 0  { return .bizarreWarning }
        return .bizarreError
    }
}
