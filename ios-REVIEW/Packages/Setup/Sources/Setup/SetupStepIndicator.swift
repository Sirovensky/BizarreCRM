import SwiftUI
import DesignSystem

// MARK: - SetupStepIndicator
// §36.1 — glass chip at top of wizard: 13 dots + progress bar.

public struct SetupStepIndicator: View {
    let currentStep: SetupStep
    let completedSteps: Set<Int>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(currentStep: SetupStep, completedSteps: Set<Int>) {
        self.currentStep = currentStep
        self.completedSteps = completedSteps
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.xs) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.bizarreOutline.opacity(0.35))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.bizarreOrange)
                        .frame(
                            width: geo.size.width * CGFloat(currentStep.rawValue - 1) / CGFloat(SetupStep.totalCount - 1),
                            height: 3
                        )
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: currentStep.rawValue)
                }
            }
            .frame(height: 3)

            // Dots
            HStack(spacing: 4) {
                ForEach(SetupStep.allCases, id: \.rawValue) { step in
                    stepDot(for: step)
                }
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: Capsule())
        // §36.1 a11y — expose the composite chip as a single progress element.
        // The outer element announces current progress; individual dots get
        // their own traits so VoiceOver swipe can traverse them.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Step \(currentStep.rawValue) of \(SetupStep.totalCount): \(currentStep.title)")
    }

    @ViewBuilder
    private func stepDot(for step: SetupStep) -> some View {
        let isCompleted = completedSteps.contains(step.rawValue)
        let isCurrent   = step == currentStep

        Circle()
            .fill(dotColor(completed: isCompleted, current: isCurrent))
            .frame(width: isCurrent ? 10 : 6, height: isCurrent ? 10 : 6)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isCurrent)
            // Per-dot a11y: VoiceOver can swipe to individual steps.
            .accessibilityLabel(dotAccessibilityLabel(step: step, completed: isCompleted, current: isCurrent))
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    private func dotAccessibilityLabel(step: SetupStep, completed: Bool, current: Bool) -> String {
        var parts = ["Step \(step.rawValue)", step.title]
        if current    { parts.append("current") }
        if completed  { parts.append("completed") }
        return parts.joined(separator: ", ")
    }

    private func dotColor(completed: Bool, current: Bool) -> Color {
        if current   { return .bizarreOrange }
        if completed { return .bizarreTeal }
        return Color.bizarreOutline.opacity(0.5)
    }
}
