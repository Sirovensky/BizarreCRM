import SwiftUI
import Core
import DesignSystem

// MARK: - ImportStepSidebar

/// Progressive step indicator for the iPad 3-column import wizard.
///
/// - Completed steps show a filled checkmark and can be tapped to jump back.
/// - The active step is highlighted with the brand orange tint and glass chrome.
/// - Future steps are dimmed and non-interactive.
public struct ImportStepSidebar: View {

    // MARK: - Input

    /// All steps shown in the sidebar (use `ImportWizardStep.wizardSteps`).
    public let steps: [ImportWizardStep]

    /// The step that is currently active in the wizard.
    public let currentStep: ImportWizardStep

    /// Called when the user taps a completed step to jump back to it.
    public let onJumpTo: (ImportWizardStep) -> Void

    // MARK: - Init

    public init(
        steps: [ImportWizardStep],
        currentStep: ImportWizardStep,
        onJumpTo: @escaping (ImportWizardStep) -> Void
    ) {
        self.steps = steps
        self.currentStep = currentStep
        self.onJumpTo = onJumpTo
    }

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                    stepRow(step: step, index: index)

                    // Connector line between steps (not after last)
                    if index < steps.count - 1 {
                        connectorLine(forStep: step)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Import wizard steps")
    }

    // MARK: - Step row

    private func stepRow(step: ImportWizardStep, index: Int) -> some View {
        let state = stepState(step)
        // Only `.mapping` supports safe backward jump (calls loadPreview()).
        let isJumpable = state == .completed && step == .mapping

        return Button {
            if isJumpable {
                onJumpTo(step)
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                stepBadge(step: step, state: state, index: index)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(step.title)
                        .font(.brandBodyMedium())
                        .foregroundStyle(labelColor(state))
                        .lineLimit(1)

                    if state == .active {
                        Text("In progress")
                            .font(.system(size: 11))
                            .foregroundStyle(.bizarreOrange)
                    } else if isJumpable {
                        Text("Tap to revisit")
                            .font(.system(size: 11))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Spacer()

                if isJumpable {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .padding(.vertical, DesignTokens.Spacing.sm)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .background {
                if state == .active {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md), tint: .bizarreOrange)
                }
            }
        }
        .disabled(!isJumpable)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(step: step, state: state))
        .accessibilityHint(state == .completed ? "Double tap to jump back to this step" : "")
        .accessibilityAddTraits(state == .active ? [.isSelected] : [])
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
    }

    // MARK: - Step badge

    private func stepBadge(step: ImportWizardStep, state: StepState, index: Int) -> some View {
        ZStack {
            Circle()
                .fill(badgeBackground(state))
                .frame(width: 32, height: 32)

            if state == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.bizarreSuccess)
            } else {
                Image(systemName: step.systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(state == .active ? .bizarreOrange : .bizarreOnSurfaceMuted)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Connector line

    private func connectorLine(forStep step: ImportWizardStep) -> some View {
        HStack {
            Rectangle()
                .fill(stepState(step) == .completed ? Color.bizarreSuccess.opacity(0.6) : Color.bizarreOnSurfaceMuted.opacity(0.2))
                .frame(width: 2, height: 20)
                .padding(.leading, DesignTokens.Spacing.lg + DesignTokens.Spacing.sm) // align with badge center
            Spacer()
        }
        .accessibilityHidden(true)
    }

    // MARK: - Helpers

    enum StepState { case completed, active, upcoming }

    private func stepState(_ step: ImportWizardStep) -> StepState {
        let currentIdx = steps.firstIndex(of: currentStep) ?? 0
        let stepIdx = steps.firstIndex(of: step) ?? 0
        if stepIdx < currentIdx { return .completed }
        if step == currentStep  { return .active }
        return .upcoming
    }

    private func labelColor(_ state: StepState) -> Color {
        switch state {
        case .completed: return .bizarreOnSurface
        case .active:    return .bizarreOrange
        case .upcoming:  return .bizarreOnSurfaceMuted
        }
    }

    private func badgeBackground(_ state: StepState) -> Color {
        switch state {
        case .completed: return .bizarreSuccess.opacity(0.15)
        case .active:    return .bizarreOrange.opacity(0.15)
        case .upcoming:  return Color.bizarreSurface1
        }
    }

    private func accessibilityLabel(step: ImportWizardStep, state: StepState) -> String {
        switch state {
        case .completed: return "\(step.title), completed"
        case .active:    return "\(step.title), current step"
        case .upcoming:  return "\(step.title), upcoming"
        }
    }
}
