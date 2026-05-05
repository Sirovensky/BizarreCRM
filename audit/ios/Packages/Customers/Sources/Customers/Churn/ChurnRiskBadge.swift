#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - ChurnRiskBadge

/// §44.3 — Visual churn risk indicator rendered on `CustomerDetailView` header.
///
/// Taps reveal a popover with factor list.
/// Glass background via `.brandGlass`.
/// Reduce Motion respected on entry animation.
public struct ChurnRiskBadge: View {
    public let score: ChurnScore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingFactors = false
    @State private var appeared = false

    public init(score: ChurnScore) {
        self.score = score
    }

    public var body: some View {
        Button {
            showingFactors = true
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: score.riskLevel.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(riskColor)
                    .accessibilityHidden(true)
                Text(score.riskLevel.label)
                    .font(.brandLabelLarge())
                    .foregroundStyle(riskColor)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .brandGlass(.regular, in: Capsule(), tint: riskColor)
        }
        .buttonStyle(.plain)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: DesignTokens.Motion.snappy, dampingFraction: 0.75)) {
                    appeared = true
                }
            }
        }
        .popover(isPresented: $showingFactors) {
            factorsPopover
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(score.factors.isEmpty ? "" : "Double-tap to see risk factors")
    }

    // MARK: Factors popover

    private var factorsPopover: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Churn Risk Factors")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.top, BrandSpacing.md)

            Divider()

            if score.factors.isEmpty {
                Text("No negative signals detected.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(score.factors, id: \.self) { factor in
                    HStack(spacing: BrandSpacing.sm) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(riskColor)
                            .font(.system(size: 13))
                            .accessibilityHidden(true)
                        Text(factor)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                }
            }

            HStack {
                Text("Probability")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text("\(score.probability0to100)%")
                    .font(.brandMono(size: 14))
                    .foregroundStyle(riskColor)
            }
        }
        .padding(BrandSpacing.base)
        .frame(minWidth: 240)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: Helpers

    private var riskColor: Color {
        switch score.riskLevel {
        case .low:      return .bizarreSuccess
        case .medium:   return .bizarreWarning
        case .high:     return .bizarreError
        case .critical: return .bizarreMagenta
        }
    }

    private var accessibilityText: String {
        var text = "Churn risk: \(score.riskLevel.label), \(score.probability0to100)%"
        if !score.factors.isEmpty {
            text += ". Factors: \(score.factors.joined(separator: ", "))"
        }
        return text
    }
}
#endif
