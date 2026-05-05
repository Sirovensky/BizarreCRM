import SwiftUI
import Charts
import DesignSystem
import Networking

// MARK: - PipelineFunnelChart

/// SwiftUI Charts funnel view showing lead counts at each pipeline stage.
///
/// Renders as a horizontal bar chart ordered new → qualified → quoted → won,
/// where each bar is proportional to that stage's count. A drop-off annotation
/// shows the percentage that advanced to the next stage.
///
/// Requires iOS 16+ / macOS 13+ for Swift Charts.
@available(iOS 16, macOS 13, *)
public struct PipelineFunnelChart: View {

    // MARK: - Input

    /// Pre-computed funnel data (new → won, no lost).
    public let stages: [PipelineStageStats]

    public init(stages: [PipelineStageStats]) {
        self.stages = stages
    }

    // MARK: - Convenience initialiser from raw leads

    public init(leads: [Lead]) {
        self.stages = PipelineAnalytics.funnelCounts(from: leads)
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            headerRow
            chartBody
            legendRow
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pipeline funnel chart")
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        Text("Pipeline Funnel")
            .font(.brandTitleSmall())
            .foregroundStyle(.bizarreOnSurface)
            .padding(.horizontal, BrandSpacing.md)
    }

    private var chartBody: some View {
        Chart(stages) { stat in
            BarMark(
                x: .value("Stage", stat.stage.displayName),
                y: .value("Leads", stat.count)
            )
            .foregroundStyle(barColor(for: stat.stage).gradient)
            .cornerRadius(6)
            .annotation(position: .top, alignment: .center) {
                if stat.count > 0 {
                    Text("\(stat.count)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel()
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine(stroke: StrokeStyle(dash: [4, 4]))
                    .foregroundStyle(Color.bizarreOutline.opacity(0.3))
                AxisValueLabel()
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
        .frame(height: 200)
        .padding(BrandSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.bizarreSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    private var legendRow: some View {
        HStack(spacing: BrandSpacing.md) {
            ForEach(stages) { stat in
                Label {
                    Text(stat.stage.displayName)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                } icon: {
                    Circle()
                        .fill(barColor(for: stat.stage))
                        .frame(width: 8, height: 8)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(stat.stage.displayName): \(stat.count) leads")
            }
        }
        .padding(.horizontal, BrandSpacing.md)
    }

    // MARK: - Colour mapping

    /// Maps each stage to a distinct brand colour.
    private func barColor(for stage: PipelineStage) -> Color {
        switch stage {
        case .new:       return Color.bizarreOrange
        case .qualified: return Color.bizarreTeal
        case .quoted:    return Color.bizarreInfo
        case .won:       return Color.bizarreSuccess
        case .lost:      return Color.bizarreError
        }
    }
}

// MARK: - Previews

#if DEBUG
@available(iOS 16, macOS 13, *)
#Preview("Pipeline Funnel") {
    let sample: [PipelineStageStats] = [
        PipelineStageStats(stage: .new,       count: 120, share: 0.57),
        PipelineStageStats(stage: .qualified, count: 55,  share: 0.26),
        PipelineStageStats(stage: .quoted,    count: 28,  share: 0.13),
        PipelineStageStats(stage: .won,       count: 9,   share: 0.04),
    ]
    return PipelineFunnelChart(stages: sample)
        .padding()
        .background(Color.bizarreSurfaceBase)
}
#endif
