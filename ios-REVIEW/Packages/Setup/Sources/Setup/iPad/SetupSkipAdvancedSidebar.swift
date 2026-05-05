import SwiftUI
import Core
import DesignSystem

// MARK: - SetupSkipAdvancedSidebar  (§22 iPad polish)
//
// Sidebar for the iPad 3-col layout that groups optional (advanced) steps
// behind a collapsible "Advanced" disclosure section, reducing visual noise
// for users who just want to click through quickly.
//
// Classification:
//   Core steps    — always visible, listed first.
//   Advanced steps — optional steps (smsSetup, deviceTemplates, dataImport,
//                    sampleData). Hidden behind a disclosure group that starts
//                    collapsed. Expands automatically when the active step is
//                    inside the advanced group.
//
// Accessibility: each row is labelled with its title, completion state, and
// whether it is the current step. The "Advanced" header announces its
// expanded/collapsed state.

// MARK: - Step classification

extension SetupStep {
    /// Steps surfaced inside the "Advanced" disclosure group.
    public static let advancedSteps: Set<SetupStep> = [
        .smsSetup, .deviceTemplates, .dataImport, .sampleData
    ]

    /// True when this step is optional / advanced.
    public var isAdvanced: Bool { Self.advancedSteps.contains(self) }
}

// MARK: - View

public struct SetupSkipAdvancedSidebar: View {

    // MARK: - Properties

    public let currentStep: SetupStep
    public let completedSteps: Set<Int>

    @State private var advancedExpanded: Bool

    // MARK: - Init

    public init(currentStep: SetupStep, completedSteps: Set<Int>) {
        self.currentStep = currentStep
        self.completedSteps = completedSteps
        // Auto-expand when the current step is advanced.
        _advancedExpanded = State(
            initialValue: currentStep.isAdvanced
        )
    }

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sidebarHeader
                coreStepsList
                advancedGroup
                Spacer(minLength: BrandSpacing.lg)
            }
            .padding(.bottom, BrandSpacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityLabel("Setup steps")
        // Auto-expand when navigation jumps into the advanced section.
        .onChange(of: currentStep) { _, newStep in
            if newStep.isAdvanced {
                advancedExpanded = true
            }
        }
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        Text("Setup")
            .font(.brandTitleLarge())
            .foregroundStyle(Color.bizarreOnSurface)
            .padding(.horizontal, BrandSpacing.md)
            .padding(.top, BrandSpacing.lg)
            .padding(.bottom, BrandSpacing.md)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Core steps

    private var coreStepsList: some View {
        ForEach(coreSteps, id: \.rawValue) { step in
            SidebarStepRow(
                step: step,
                isCurrent: step == currentStep,
                isCompleted: completedSteps.contains(step.rawValue)
            )
        }
    }

    // MARK: - Advanced group

    private var advancedGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            advancedDisclosureHeader
            if advancedExpanded {
                advancedStepsList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: advancedExpanded)
    }

    private var advancedDisclosureHeader: some View {
        Button {
            advancedExpanded.toggle()
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: advancedExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .frame(width: 14)
                    .accessibilityHidden(true)

                Text("Advanced")
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)

                Spacer()
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(advancedExpanded ? "Advanced, expanded" : "Advanced, collapsed")
        .accessibilityAddTraits(.isButton)
        .padding(.horizontal, BrandSpacing.xs)
        .padding(.top, BrandSpacing.xs)
    }

    private var advancedStepsList: some View {
        ForEach(advancedSteps, id: \.rawValue) { step in
            SidebarStepRow(
                step: step,
                isCurrent: step == currentStep,
                isCompleted: completedSteps.contains(step.rawValue)
            )
            .padding(.leading, BrandSpacing.md)
        }
    }

    // MARK: - Computed step lists

    private var coreSteps: [SetupStep] {
        SetupStep.allCases.filter { !$0.isAdvanced && $0 != .complete }
    }

    private var advancedSteps: [SetupStep] {
        SetupStep.allCases.filter(\.isAdvanced)
    }
}

// MARK: - SidebarStepRow

/// A single row in the sidebar. Extracted so SetupSkipAdvancedSidebar
/// stays under 200 lines, and to keep the row reusable.
struct SidebarStepRow: View {

    let step: SetupStep
    let isCurrent: Bool
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            stepBadge
            Text(step.title)
                .font(.brandLabelLarge())
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? Color.bizarreOrange : Color.bizarreOnSurface)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(
            isCurrent ? Color.bizarreOrange.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .padding(.horizontal, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .hoverEffect(.highlight)
    }

    // MARK: - Sub-views

    private var stepBadge: some View {
        ZStack {
            Circle()
                .fill(
                    isCurrent   ? Color.bizarreOrange :
                    isCompleted ? Color.bizarreTeal   :
                                  Color.bizarreOutline.opacity(0.3)
                )
                .frame(width: 22, height: 22)
            if isCompleted && !isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(step.rawValue)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isCurrent ? .white : Color.bizarreOnSurface)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Helpers

    private var accessibilityLabel: String {
        var parts = [step.title]
        if isCompleted { parts.append("completed") }
        if isCurrent   { parts.append("current step") }
        return parts.joined(separator: ", ")
    }
}
