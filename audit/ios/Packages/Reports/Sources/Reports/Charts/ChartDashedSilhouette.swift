import SwiftUI
import DesignSystem

// MARK: - ChartDashedSilhouette
//
// §91.11 — shared empty-state visual used by all 8 chart cards.
// Renders a dashed rounded rectangle silhouette with a centered icon + label,
// matching the "no data" pattern spec.

public struct ChartDashedSilhouette: View {
    public let systemImage: String
    public let label: String

    public init(systemImage: String, label: String) {
        self.systemImage = systemImage
        self.label = label
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.bizarreOnSurfaceMuted.opacity(0.5))
                .accessibilityHidden(true)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(BrandSpacing.base)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(
                    Color.bizarreOutline.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Empty chart: \(label)")
    }
}
