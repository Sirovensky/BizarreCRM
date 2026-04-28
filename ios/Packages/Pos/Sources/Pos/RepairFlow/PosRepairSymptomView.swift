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
        VStack(spacing: 0) {
            // Step 2/4 progress bar pinned directly below nav bar (3pt strip, 33%)
            // Gradient: primary (orange) → primary-bright, left → right per mockup.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.bizarreOnSurface.opacity(0.06))
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.bizarreOrange, Color.bizarreOrangeBright],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.33)
                }
            }
            .frame(height: 3)
            .accessibilityLabel("Step 2 of 4, 33% complete")

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    symptomTextSection
                        .padding(.top, 14)

                    conditionSection
                        .padding(.top, 8)

                    quickChipsSection
                        .padding(.top, 8)

                    internalNotesSection
                        .padding(.top, 8)

                    Spacer().frame(height: 16)
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.xxl)
            }
        }
        .safeAreaInset(edge: .bottom) {
            ctaBar
        }
        .navigationTitle("Issue · Step 2/4")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("Auto-save")
                    .font(.caption)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.bizarreSurface1, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5))
                    .accessibilityHidden(true)
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

    private var symptomTextSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            // Section label: "What's the problem?" (matches mockup)
            Text("What's the problem?")
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            TextEditor(text: $symptomText)
                .frame(minHeight: 80, maxHeight: 160)
                .font(.system(size: 13.5))
                .lineSpacing(3) // line-height: 1.5 on 13px
                .foregroundStyle(.bizarreOnSurface)
                .padding(12)
                .background(Color.bizarreOnSurface.opacity(0.03), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
                    symptomText.isEmpty
                        ? Color.bizarreOrange.opacity(0.35)
                        : Color.bizarreOrange.opacity(0.35),
                    lineWidth: 1.5
                ))
                .onChange(of: symptomText) { _, _ in
                    vm.symptomText = symptomText
                }
                .accessibilityLabel("Symptom description")
                .accessibilityHint("Describe the issue reported by the customer")
                .accessibilityIdentifier("repairFlow.symptom.text")

            // Char count row (87 / 2000 style per mockup)
            HStack {
                // Dictate button — teal color per mockup
                Button {
                    // TODO: trigger speech recognition
                } label: {
                    Label("Dictate", systemImage: "mic.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.bizarreTeal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dictate symptom")

                Spacer()

                Text("\(symptomText.count) / 2000")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
            .padding(.top, 4)
        }
    }

    private var conditionSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Device condition")
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
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
                    Text(selectedCondition.map { $0.displayName } ?? "Select condition…")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(selectedCondition == nil ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    Spacer(minLength: 0)
                    Text("⌄")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 1))
            }
            .accessibilityLabel("Device condition: \(selectedCondition?.displayName ?? "not selected")")
            .accessibilityHint("Tap to choose the physical condition of the device")
            .accessibilityIdentifier("repairFlow.symptom.condition")
        }
    }

    private var quickChipsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Quick-pick symptom")
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            FlowLayout(spacing: 8) {
                ForEach(RepairSymptomChip.allCases, id: \.self) { chip in
                    chipButton(chip)
                }
            }
        }
    }

    private func chipButton(_ chip: RepairSymptomChip) -> some View {
        let isSelected = selectedChips.contains(chip)
        let bgFill: Color = isSelected
            ? Color.bizarreOrange.opacity(0.14)
            : Color.bizarreOnSurface.opacity(0.04)
        let strokeFill: Color = isSelected
            ? Color.bizarreOrange.opacity(0.45)
            : Color.bizarreOnSurface.opacity(0.1)
        return Button {
            if isSelected {
                selectedChips.remove(chip)
            } else {
                selectedChips.insert(chip)
            }
            vm.selectedChips = selectedChips
            BrandHaptics.tap()
        } label: {
            Text(chip.displayLabel)
                .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(bgFill, in: Capsule())
                .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                .overlay(
                    Capsule().strokeBorder(strokeFill, lineWidth: isSelected ? 1.5 : 1)
                )
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
            Text("Internal notes (tech-only)")
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            TextEditor(text: $internalNotes)
                .frame(minHeight: 60, maxHeight: 100)
                .font(.system(size: 13))
                .foregroundStyle(.bizarreOnSurface)
                .padding(12)
                // Dashed amber border per mockup: rgba(232,163,61,0.45) — use bizarreWarning token.
                .background(Color.bizarreWarning.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            Color.bizarreWarning.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                        )
                )
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
                HStack(spacing: 6) {
                    if coordinator.isLoading {
                        ProgressView()
                            .tint(Color.bizarreOnPrimary)
                    } else {
                        Text("Next → diagnostic quote")
                            .font(.brandTitleSmall())
                        Text("›")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.sm)
                .background(
                    (!vm.isValid || coordinator.isLoading)
                        ? Color.bizarreOrange.opacity(0.4)
                        : Color.bizarreOrange,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .foregroundStyle(Color.bizarreOnPrimary)
            }
            .buttonStyle(.plain)
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
