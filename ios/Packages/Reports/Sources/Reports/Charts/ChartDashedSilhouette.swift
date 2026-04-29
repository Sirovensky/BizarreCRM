import SwiftUI
import DesignSystem

// MARK: - ChartDashedSilhouette
//
// §91.11 — shared empty-state visual used by all chart cards.
// Renders a dashed rounded rectangle silhouette with a centered icon + label,
// matching the "no data" pattern spec.
//
// §91.16 item 4 — each empty card should suggest the next step.
// Pass `ctaLabel` + `ctaAction` to render an inline tappable action beneath
// the label (e.g. "Add inventory items" → tap routes to inventory create).

public struct ChartDashedSilhouette: View {
    public let systemImage: String
    public let label: String
    /// Optional CTA label shown below the empty-state description (§91.16).
    public let ctaLabel: String?
    /// Action fired when the CTA button is tapped.  Ignored when `ctaLabel` is nil.
    public let ctaAction: (() -> Void)?

    public init(
        systemImage: String,
        label: String,
        ctaLabel: String? = nil,
        ctaAction: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.label = label
        self.ctaLabel = ctaLabel
        self.ctaAction = ctaAction
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
            // §91.16: optional next-step CTA — guides user toward populating data
            if let ctaLabel, let ctaAction {
                Button(action: ctaAction) {
                    Text(ctaLabel)
                        .font(.brandLabelLarge())
                        .padding(.horizontal, BrandSpacing.md)
                        .padding(.vertical, BrandSpacing.xs)
                }
                .buttonStyle(.bordered)
                .tint(.bizarreOrange)
                .accessibilityLabel(ctaLabel)
                .padding(.top, BrandSpacing.xxs)
            }
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
        .accessibilityLabel(
            ctaLabel != nil
                ? "Empty chart: \(label). \(ctaLabel!)."
                : "Empty chart: \(label)"
        )
    }
}
