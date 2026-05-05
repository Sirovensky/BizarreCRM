import SwiftUI
import Charts
import DesignSystem

// MARK: - CSATScoreCard

public struct CSATScoreCard: View {
    public let score: CSATScore?
    public let onDetail: (() -> Void)?

    public init(score: CSATScore?, onDetail: (() -> Void)? = nil) {
        self.score = score
        self.onDetail = onDetail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if let s = score {
                gaugeRow(s)
                trendRow(s)
            } else {
                ChartDashedSilhouette(systemImage: "star.fill", label: "No CSAT data for this period.")
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
            Image(systemName: "star.fill")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            Text("CSAT")
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
    private func gaugeRow(_ s: CSATScore) -> some View {
        HStack(spacing: BrandSpacing.lg) {
            Gauge(value: s.current, in: 1...5) {
                EmptyView()
            } currentValueLabel: {
                Text(String(format: "%.1f", s.current))
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(gaugeColor(s.current))
            .frame(width: 72, height: 72)
            .accessibilityLabel("CSAT score \(String(format: "%.1f", s.current)) out of 5")

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(String(format: "%.1f / 5.0", s.current))
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(s.responseCount) responses")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    private func trendRow(_ s: CSATScore) -> some View {
        let isUp = s.trendPct >= 0
        return HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(String(format: "%.1f%%", abs(s.trendPct)))
                .font(.brandLabelLarge())
            Text("vs prior period")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .foregroundStyle(isUp ? Color.bizarreSuccess : Color.bizarreError)
        .accessibilityLabel(
            "CSAT trend: \(isUp ? "up" : "down") \(String(format: "%.1f", abs(s.trendPct))) percent vs prior period"
        )
    }

    private func gaugeColor(_ value: Double) -> Color {
        if value >= 4.5 { return .bizarreSuccess }
        if value >= 3.5 { return .bizarreWarning }
        return .bizarreError
    }
}
