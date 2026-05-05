import SwiftUI
import DesignSystem

// MARK: - TutorialStep

public struct TutorialStep: Sendable {
    public let id: Int
    public let message: String

    public init(id: Int, message: String) {
        self.id = id
        self.message = message
    }
}

// MARK: - Default tutorial steps (MVP stub — 3 steps for ticket intake)

public extension TutorialStep {
    static let defaultSteps: [TutorialStep] = [
        TutorialStep(id: 0, message: "Tap here to create a new ticket"),
        TutorialStep(id: 1, message: "Add customer details and device info"),
        TutorialStep(id: 2, message: "Assign a technician and save the ticket")
        // TODO: Full tutorial library is out of scope for this PR
    ]
}

// MARK: - TutorialOverlayView

/// §51.3 Tutorial overlay — MVP stub with 3 steps.
/// Displays a tooltip with Skip/Next buttons.
/// Full tutorial library is deferred (TODO).
public struct TutorialOverlayView: View {
    let steps: [TutorialStep]
    @State private var currentIndex: Int = 0
    var onDismiss: () -> Void

    public init(
        steps: [TutorialStep] = TutorialStep.defaultSteps,
        onDismiss: @escaping () -> Void
    ) {
        self.steps = steps
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Dim backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {} // absorb taps

            // Tooltip card
            if currentIndex < steps.count {
                tooltipCard(for: steps[currentIndex])
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentIndex)
    }

    @ViewBuilder
    private func tooltipCard(for step: TutorialStep) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            HStack {
                Text("Step \(step.id + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Skip") { onDismiss() }
                    .font(.caption.weight(.semibold))
                    .accessibilityLabel("Skip tutorial")
            }

            Text(step.message)
                .font(.body)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dynamicTypeSize(.xSmall ... .accessibility3)

            HStack {
                Spacer()
                Button {
                    if currentIndex + 1 < steps.count {
                        currentIndex += 1
                    } else {
                        onDismiss()
                    }
                } label: {
                    Text(currentIndex + 1 < steps.count ? "Next" : "Done")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.orange)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .accessibilityElement(children: .combine)
    }
}
