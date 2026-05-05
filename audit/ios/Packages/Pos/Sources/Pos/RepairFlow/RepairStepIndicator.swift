#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - RepairStepIndicator
//
// Easy-to-track step indicator for the POS repair flow. Renders a horizontal
// row of N numbered circles connected by lines:
//
//   (✓)──(✓)──( 3 )──( 4 )
//   Past   Past Current Future
//
// Past steps fill cream and show a checkmark. The current step fills cream
// with its 1-based index. Future steps render hollow with a muted index.
// The connector line between two completed steps fills cream; otherwise it
// stays muted.
//
// Tapping a *past* step calls `onTap(step)` so callers can wire backwards
// navigation (e.g. coordinator.back(to:)). Future + current steps are
// non-interactive.

public struct RepairStepIndicator: View {
    public let steps: [RepairStep]
    public let current: RepairStep
    public var onTapPastStep: ((RepairStep) -> Void)? = nil

    public init(
        steps: [RepairStep] = RepairStep.allCases,
        current: RepairStep,
        onTapPastStep: ((RepairStep) -> Void)? = nil
    ) {
        self.steps = steps
        self.current = current
        self.onTapPastStep = onTapPastStep
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                stepCircle(step, index: index)
                if step != steps.last {
                    connector(after: step)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current.accessibilityDescription)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func stepCircle(_ step: RepairStep, index: Int) -> some View {
        let state = state(for: step)
        Group {
            switch state {
            case .past:
                Button {
                    onTapPastStep?(step)
                } label: {
                    circle(filled: true, content: AnyView(checkmark))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(index + 1) — \(step.navigationTitle), completed. Tap to go back.")

            case .current:
                circle(filled: true, content: AnyView(numberLabel(index + 1, onPrimary: true)))

            case .future:
                circle(filled: false, content: AnyView(numberLabel(index + 1, onPrimary: false)))
            }
        }
        .overlay(alignment: .bottom) {
            Text(step.navigationTitle)
                .font(.brandLabelSmall())
                .foregroundStyle(state == .future ? Color.bizarreOnSurfaceMuted : Color.bizarreOnSurface)
                .lineLimit(1)
                .fixedSize()
                .offset(y: 22)
        }
    }

    @ViewBuilder
    private func circle(filled: Bool, content: AnyView) -> some View {
        ZStack {
            Circle()
                .fill(filled ? Color.bizarrePrimary : Color.clear)
                .frame(width: 28, height: 28)
            Circle()
                .strokeBorder(
                    filled ? Color.bizarrePrimary : Color.bizarreOnSurface.opacity(0.25),
                    lineWidth: 1.5
                )
                .frame(width: 28, height: 28)
            content
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.bizarreOnPrimary)
    }

    private func numberLabel(_ n: Int, onPrimary: Bool) -> some View {
        Text("\(n)")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(onPrimary ? Color.bizarreOnPrimary : Color.bizarreOnSurfaceMuted)
            .monospacedDigit()
    }

    @ViewBuilder
    private func connector(after step: RepairStep) -> some View {
        Rectangle()
            .fill(state(for: step) == .past ? Color.bizarrePrimary : Color.bizarreOnSurface.opacity(0.20))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
    }

    // MARK: - State

    private enum StepState { case past, current, future }

    private func state(for step: RepairStep) -> StepState {
        if step.rawValue < current.rawValue { return .past }
        if step == current                  { return .current }
        return .future
    }
}

// MARK: - Preview

#if DEBUG
#Preview("RepairStepIndicator — pickDevice") {
    VStack(spacing: 40) {
        RepairStepIndicator(current: .pickDevice)
        RepairStepIndicator(current: .describeIssue)
        RepairStepIndicator(current: .diagnosticQuote)
        RepairStepIndicator(current: .deposit)
    }
    .padding(40)
    .background(Color.bizarreSurfaceBase)
    .preferredColorScheme(.dark)
}
#endif
#endif
