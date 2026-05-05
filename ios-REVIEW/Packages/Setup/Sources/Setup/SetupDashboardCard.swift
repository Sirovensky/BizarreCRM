#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - §36.4 Setup dashboard card

/// A compact progress card shown on the Dashboard for the tenant admin
/// when the Setup Wizard has not been completed.
///
/// Displays "Setup N of 13" with a progress bar and a tap-to-resume CTA.
/// Disappears once the wizard is marked complete.
///
/// **Usage:**
/// ```swift
/// SetupDashboardCard(
///     currentStep: vm.currentStep,
///     completedSteps: vm.completedSteps,
///     totalSteps: SetupStep.totalCount
/// ) {
///     showSetupWizard = true
/// }
/// ```
public struct SetupDashboardCard: View {

    // MARK: - Input

    /// The wizard's current step (1-based). Used to display "Setup N of 13".
    public let currentStep: Int

    /// Set of completed step indices.
    public let completedSteps: Set<Int>

    /// Total number of wizard steps (typically 15 incl. welcome + done).
    public let totalSteps: Int

    /// Called when the user taps "Resume" or the card itself.
    public let onResume: () -> Void

    // MARK: - Init

    public init(
        currentStep: Int,
        completedSteps: Set<Int>,
        totalSteps: Int = SetupStep.totalCount,
        onResume: @escaping () -> Void
    ) {
        self.currentStep = currentStep
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
        self.onResume = onResume
    }

    // MARK: - Derived

    /// Number of completed steps (clamped, excludes the "Complete" terminal step).
    private var doneCount: Int {
        min(completedSteps.count, totalSteps - 1)
    }

    /// Count of actionable steps (total − 1 for the "Done" step).
    private var actionableTotal: Int {
        max(1, totalSteps - 1)
    }

    private var fraction: Double {
        Double(doneCount) / Double(actionableTotal)
    }

    private var isComplete: Bool {
        doneCount >= actionableTotal
    }

    // MARK: - Body

    public var body: some View {
        if !isComplete {
            card
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Setup \(doneCount) of \(actionableTotal) steps completed. Tap to resume.")
                .accessibilityAddTraits(.isButton)
        }
    }

    private var card: some View {
        Button(action: onResume) {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                // Header row
                HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.xs) {
                    Image(systemName: "checklist")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.bizarreOrange)
                        .accessibilityHidden(true)

                    Text("Setup \(doneCount) of \(actionableTotal)")
                        .font(.brandLabelLarge().bold())
                        .foregroundStyle(Color.bizarreOnSurface)

                    Spacer()

                    Text("Resume →")
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreOrange)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(Color.bizarreOnSurface.opacity(0.12))
                            .frame(height: 6)

                        // Fill
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.bizarreOrange, Color.bizarreOrange.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * fraction, height: 6)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: fraction)
                    }
                }
                .frame(height: 6)

                // Subtitle
                Text(subtitleText)
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }
            .padding(BrandSpacing.md)
            .brandGlass(
                .regular,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg),
                tint: Color.bizarreOrange.opacity(0.06),
                interactive: true
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subtitle

    private var subtitleText: String {
        let remaining = actionableTotal - doneCount
        if remaining <= 0 { return "All steps complete — tap to review." }
        if remaining == 1 { return "1 step remaining to complete your setup." }
        return "\(remaining) steps remaining to complete your setup."
    }
}

// MARK: - SetupDashboardCard (ViewModel convenience)

public extension SetupDashboardCard {
    /// Convenience init that reads progress directly from a `SetupWizardViewModel`.
    @MainActor
    init(viewModel: SetupWizardViewModel, onResume: @escaping () -> Void) {
        self.init(
            currentStep: viewModel.currentStep.rawValue,
            completedSteps: viewModel.completedSteps,
            totalSteps: SetupStep.totalCount,
            onResume: onResume
        )
    }
}

#endif
