import SwiftUI
import DesignSystem

// MARK: - SLABreachesCard
//
// §91.3 fix 6:
//  - Hidden entirely when breach count is zero (or report unavailable).
//  - When non-zero: surfaces total count + a row per breach type.

public struct SLABreachesCard: View {
    public let report: SLABreachReport?

    public init(report: SLABreachReport?) {
        self.report = report
    }

    public var body: some View {
        // Render nothing when there are no breaches (or endpoint stub returns nil).
        guard let report, report.hasBreaches else { return AnyView(EmptyView()) }
        return AnyView(cardContent(report))
    }

    private func cardContent(_ report: SLABreachReport) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader(count: report.breachCount)
            Divider()
            if report.breachTypes.isEmpty {
                Text("\(report.breachCount) breach\(report.breachCount == 1 ? "" : "es") recorded")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(report.breachTypes) { bt in
                    breachTypeRow(bt)
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreError.opacity(0.5), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private func cardHeader(count: Int) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("SLA Breaches")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Text("\(count)")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreError)
                .accessibilityLabel("\(count) SLA breach\(count == 1 ? "" : "es")")
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func breachTypeRow(_ bt: SLABreachType) -> some View {
        HStack {
            Text(bt.type)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Text("\(bt.count)")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreError)
        }
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bt.type): \(bt.count) breach\(bt.count == 1 ? "" : "es")")
    }
}
