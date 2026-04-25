#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosRepairSymptomView (Frame 1c)
//
// Step 2 of the repair intake flow. Captures symptom text, device condition
// from a dropdown, five quick-pick chips, and optional internal notes.
// A progress bar at the top shows 50% completion.
//
// Server wiring: data is batched and sent in PosRepairFlowCoordinator when
// `advance()` is called (POST /api/v1/tickets/:id/notes, type=diagnostic).

@MainActor
@Observable
public final class PosRepairSymptomViewModel {

    // MARK: - State

    public var symptomText: String = ""
    public var selectedCondition: DeviceCondition? = nil
    public var selectedChips: Set<RepairSymptomChip> = []
    public var internalNotes: String = ""

    // MARK: - Validation

    /// True when symptom text contains at least one non-whitespace character.
    public var isValid: Bool {
        !symptomText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    public func toggleChip(_ chip: RepairSymptomChip) {
        if selectedChips.contains(chip) {
            selectedChips.remove(chip)
        } else {
            selectedChips.insert(chip)
        }
    }

    /// Sync current state back into the coordinator draft.
    public func commitToDraft(coordinator: PosRepairFlowCoordinator) {
        coordinator.setSymptom(
            text: symptomText,
            condition: selectedCondition,
            chips: selectedChips,
            internalNotes: internalNotes
        )
    }
}

// MARK: - View

public struct PosRepairSymptomView: View {

    @Bindable private var coordinator: PosRepairFlowCoordinator
    @State private var vm = PosRepairSymptomViewModel()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(coordinator: PosRepairFlowCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                progressHeader

                symptomTextSection

                conditionSection

                quickChipsSection

                internalNotesSection
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .safeAreaInset(edge: .bottom) {
            ctaBar
        }
        .navigationTitle(RepairStep.describeIssue.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    vm.commitToDraft(coordinator: coordinator)
                    coordinator.goBack()
                }
                .accessibilityLabel("Back to device picker")
                .accessibilityIdentifier("repairFlow.symptom.back")
            }
        }
        .onAppear {
            // Restore from draft when navigating back.
            symptomText = coordinator.draft.symptomText
            selectedCondition = coordinator.draft.condition
            selectedChips = coordinator.draft.quickChips
            internalNotes = coordinator.draft.internalNotes
        }
    }

    // MARK: - Sub-views

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            ProgressView(value: RepairStep.describeIssue.progressPercent, total: 100)
                .progressViewStyle(.linear)
                .tint(.bizarreOrange)
                .accessibilityLabel(RepairStep.describeIssue.accessibilityDescription)
                .accessibilityValue("\(Int(RepairStep.describeIssue.progressPercent))%")

            Text("Describe the issue")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, BrandSpacing.md)
    }

    private var symptomTextSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Label("What's wrong?", systemImage: "text.bubble")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            TextEditor(text: $symptomText)
                .frame(minHeight: 100, maxHeight: 160)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                    symptomText.isEmpty ? Color.bizarreOutline.opacity(0.4) : Color.bizarreOrange,
                    lineWidth: 1
                ))
                .onChange(of: symptomText) { _, _ in
                    vm.symptomText = symptomText
                }
                .accessibilityLabel("Symptom description")
                .accessibilityHint("Describe the issue reported by the customer")
                .accessibilityIdentifier("repairFlow.symptom.text")
        }
    }

    private var conditionSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Label("Device condition", systemImage: "gauge.medium")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            Menu {
                ForEach(DeviceCondition.allCases, id: \.self) { condition in
                    Button(condition.displayName) {
                        selectedCondition = condition
                        vm.selectedCondition = condition
                    }
                }
            } label: {
                HStack {
                    Text(selectedCondition?.displayName ?? "Select condition…")
                        .font(.brandBodyMedium())
                        .foregroundStyle(selectedCondition == nil ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 1))
            }
            .accessibilityLabel("Device condition: \(selectedCondition?.displayName ?? "not selected")")
            .accessibilityHint("Tap to choose the physical condition of the device")
            .accessibilityIdentifier("repairFlow.symptom.condition")
        }
    }

    private var quickChipsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Label("Quick picks", systemImage: "bolt.horizontal")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            FlowLayout(spacing: BrandSpacing.sm) {
                ForEach(RepairSymptomChip.allCases, id: \.self) { chip in
                    chipButton(chip)
                }
            }
        }
    }

    private func chipButton(_ chip: RepairSymptomChip) -> some View {
        let isSelected = selectedChips.contains(chip)
        return Button {
            if isSelected {
                selectedChips.remove(chip)
            } else {
                selectedChips.insert(chip)
            }
            vm.selectedChips = selectedChips
            BrandHaptics.tap()
        } label: {
            Label(chip.displayLabel, systemImage: chip.systemImage)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .background(
                    isSelected ? Color.bizarreOrange : Color.bizarreSurface2,
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.white : Color.bizarreOnSurface)
                .overlay(Capsule().strokeBorder(
                    isSelected ? Color.clear : Color.bizarreOutline.opacity(0.4),
                    lineWidth: 1
                ))
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : BrandMotion.snappy, value: isSelected)
        .accessibilityLabel(chip.displayLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Selected — tap to deselect" : "Tap to select")
        .accessibilityIdentifier("repairFlow.symptom.chip.\(chip.rawValue)")
    }

    private var internalNotesSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Label("Internal notes", systemImage: "lock.doc")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            TextEditor(text: $internalNotes)
                .frame(minHeight: 72, maxHeight: 120)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 1))
                .onChange(of: internalNotes) { _, _ in
                    vm.internalNotes = internalNotes
                }
                .accessibilityLabel("Internal notes")
                .accessibilityHint("Notes not visible to the customer")
                .accessibilityIdentifier("repairFlow.symptom.internalNotes")
        }
    }

    private var ctaBar: some View {
        VStack(spacing: BrandSpacing.xs) {
            if let error = coordinator.errorMessage {
                Text(error)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.md)
            }

            Button {
                vm.commitToDraft(coordinator: coordinator)
                coordinator.advance()
                BrandHaptics.tapMedium()
            } label: {
                HStack {
                    if coordinator.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Continue → quote")
                            .font(.brandTitleSmall())
                        Image(systemName: "chevron.right")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(!vm.isValid || coordinator.isLoading)
            .accessibilityLabel("Continue to diagnostic quote")
            .accessibilityHint("Advances to step 3 of 4")
            .accessibilityIdentifier("repairFlow.symptom.continue")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.bottom, BrandSpacing.md)
        .background(.ultraThinMaterial)
    }

    // MARK: - Binding bridges for onChange

    @State private var symptomText: String = ""
    @State private var selectedCondition: DeviceCondition? = nil
    @State private var selectedChips: Set<RepairSymptomChip> = []
    @State private var internalNotes: String = ""
}

// MARK: - FlowLayout
// Simple wrapping HStack for chips. Kept private to this file.

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
#endif
