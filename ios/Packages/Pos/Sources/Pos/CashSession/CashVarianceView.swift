#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// §39 — Standalone expected-vs-counted variance display card.
///
/// Extracted from `CloseRegisterSheet`'s inline badge so it can be:
///   - embedded in Z-report history rows
///   - shown as a summary tile in any register-management screen
///   - tested in Xcode Previews in isolation
///
/// All values are in **cents**. Pass zeros when data is not yet loaded.
public struct CashVarianceView: View {

    // MARK: - Properties

    public let expectedCents: Int
    public let countedCents: Int

    /// If provided, shows a formatted label. Pass `nil` to hide the header.
    public var title: String? = "Variance"

    public init(expectedCents: Int, countedCents: Int, title: String? = "Variance") {
        self.expectedCents = expectedCents
        self.countedCents = countedCents
        self.title = title
    }

    // MARK: - Derived

    private var varianceCents: Int { countedCents - expectedCents }
    private var band: CashVariance.Band { CashVariance.band(cents: varianceCents) }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            if let title {
                HStack(spacing: BrandSpacing.sm) {
                    Circle()
                        .fill(band.color)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer(minLength: 0)
                    Text(band.shortLabel)
                        .font(.brandLabelSmall())
                        .foregroundStyle(band.color)
                }
            }

            Text(formattedVariance)
                .font(.brandHeadlineLarge())
                .foregroundStyle(band.color)
                .monospacedDigit()
                .accessibilityLabel("Variance \(formattedVariance)")

            HStack(spacing: BrandSpacing.xl) {
                amountCell("Expected", CartMath.formatCents(expectedCents))
                    .accessibilityIdentifier("cashVariance.expected")
                amountCell("Counted", CartMath.formatCents(countedCents))
                    .accessibilityIdentifier("cashVariance.counted")
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(Color.bizarreSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .strokeBorder(band.color.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cashVarianceView")
    }

    // MARK: - Private helpers

    private var formattedVariance: String {
        CloseRegisterSheet.formatSigned(cents: varianceCents)
    }

    private func amountCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
    }
}

// MARK: - Preview

#Preview("Balanced") {
    CashVarianceView(expectedCents: 15_000, countedCents: 15_000)
        .padding()
}

#Preview("Amber variance") {
    CashVarianceView(expectedCents: 15_000, countedCents: 15_300)
        .padding()
}

#Preview("Red variance") {
    CashVarianceView(expectedCents: 15_000, countedCents: 13_200)
        .padding()
}

#endif // canImport(UIKit)
