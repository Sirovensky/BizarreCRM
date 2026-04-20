import SwiftUI
import DesignSystem

/// §2.3 — Strength meter + rule checklist for the Set-Password panel.
///
/// Pure presentation: caller hands in the evaluation produced by
/// `PasswordStrengthEvaluator`. Keeps `LoginFlowView` lean and lets us
/// snapshot-test this widget in isolation.
///
/// A11y: the bar reports a single `accessibilityValue` ("Fair strength")
/// so VoiceOver users hear one label per update. Each rule row announces
/// "Met" / "Not met" so the checklist is usable without sight.
struct PasswordStrengthMeter: View {
    let evaluation: PasswordEvaluation
    let showRules: Bool

    init(evaluation: PasswordEvaluation, showRules: Bool = true) {
        self.evaluation = evaluation
        self.showRules = showRules
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            strengthBar
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Password strength")
                .accessibilityValue("\(evaluation.strength.label)")

            if showRules {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    ruleRow("At least 8 characters", met: evaluation.rules.hasMinLength)
                    ruleRow("Upper and lower case",  met: evaluation.rules.hasMixedCase)
                    ruleRow("At least one number",   met: evaluation.rules.hasDigit)
                    ruleRow("At least one symbol",   met: evaluation.rules.hasSymbol)
                    ruleRow("Not a common password", met: evaluation.rules.notCommon)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Password rules")
            }
        }
    }

    private var strengthBar: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack(spacing: BrandSpacing.xxs) {
                ForEach(0..<4, id: \.self) { idx in
                    Capsule()
                        .fill(segmentColor(index: idx))
                        .frame(maxWidth: .infinity, maxHeight: 6)
                }
            }
            .frame(height: 6)
            .animation(BrandMotion.snappy, value: evaluation.strength)

            Text(evaluation.strength.label)
                .font(.brandLabelSmall())
                .foregroundStyle(strengthLabelColor)
                .animation(.none, value: evaluation.strength)
        }
    }

    private func segmentColor(index: Int) -> Color {
        // Each of the 4 segments lights up as strength climbs.
        // veryWeak=0 filled, weak=1, fair=2, strong=3, veryStrong=4.
        let filled = evaluation.strength.rawValue > index
        guard filled else { return .bizarreOutline.opacity(0.35) }
        return strengthLabelColor
    }

    private var strengthLabelColor: Color {
        switch evaluation.strength {
        case .veryWeak:   return .bizarreError
        case .weak:       return .bizarreWarning
        case .fair:       return .bizarreWarning
        case .strong:     return .bizarreSuccess
        case .veryStrong: return .bizarreSuccess
        }
    }

    private func ruleRow(_ text: String, met: Bool) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? .bizarreSuccess : .bizarreOnSurfaceMuted)
                .imageScale(.small)
            Text(text)
                .font(.brandLabelSmall())
                .foregroundStyle(met ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                .strikethrough(met, color: .bizarreOnSurfaceMuted)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityValue(met ? "Met" : "Not met")
    }
}
