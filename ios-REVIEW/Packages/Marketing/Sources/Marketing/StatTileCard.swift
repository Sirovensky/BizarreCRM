import SwiftUI
import DesignSystem

/// Metric tile for post-send reports. Matches Dashboard StatTileCard pattern.
public struct StatTileCard: View {
    let icon: String
    let label: String
    let value: String
    let accent: Color

    public init(icon: String, label: String, value: String, accent: Color) {
        self.icon = icon
        self.label = label
        self.value = value
        self.accent = accent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon)
                    .foregroundStyle(accent)
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Text(value)
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
