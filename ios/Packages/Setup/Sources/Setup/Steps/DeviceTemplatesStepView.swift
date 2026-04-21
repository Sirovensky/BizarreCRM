import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - ViewModel

@MainActor
@Observable
final class DeviceTemplatesViewModel {

    // MARK: State

    var selectedFamilies: Set<DeviceFamily> = []

    // MARK: Helpers

    var isNextEnabled: Bool {
        Step11Validator.isNextEnabled(selected: selectedFamilies)
    }

    func toggleFamily(_ family: DeviceFamily) {
        if selectedFamilies.contains(family) {
            selectedFamilies.remove(family)
        } else {
            selectedFamilies.insert(family)
        }
    }

    func selectAll() {
        selectedFamilies = Set(DeviceFamily.allCases)
    }

    func selectNone() {
        selectedFamilies = []
    }
}

// MARK: - View  (§36.2 Step 11 — Device Templates)

@MainActor
public struct DeviceTemplatesStepView: View {
    let onValidityChanged: (Bool) -> Void
    let onNext: (Set<DeviceFamily>) -> Void

    @State private var vm = DeviceTemplatesViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping (Set<DeviceFamily>) -> Void
    ) {
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
    }

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: BrandSpacing.md)
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                header
                helperButtons
                familyGrid
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { onValidityChanged(vm.isNextEnabled) }
        .onChange(of: vm.isNextEnabled) { _, valid in onValidityChanged(valid) }
    }

    // MARK: Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Device Templates")
                .font(.brandHeadlineMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .padding(.top, BrandSpacing.lg)
                .accessibilityAddTraits(.isHeader)

            Text("Select the device families you repair. This pre-loads models and service options for your ticket create screen.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
    }

    private var helperButtons: some View {
        HStack(spacing: BrandSpacing.sm) {
            Button("Add all") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    vm.selectAll()
                }
            }
            .buttonStyle(.brandGlass)
            .accessibilityLabel("Select all device families")

            Button("Select none") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    vm.selectNone()
                }
            }
            .buttonStyle(.brandGlass)
            .accessibilityLabel("Deselect all device families")

            Spacer()

            if !vm.selectedFamilies.isEmpty {
                Text("\(vm.selectedFamilies.count) selected")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityLabel("\(vm.selectedFamilies.count) families selected")
            }
        }
    }

    private var familyGrid: some View {
        LazyVGrid(columns: columns, spacing: BrandSpacing.md) {
            ForEach(DeviceFamily.allCases, id: \.self) { family in
                familyCard(family)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Device family selection grid")
    }

    private func familyCard(_ family: DeviceFamily) -> some View {
        let isSelected = vm.selectedFamilies.contains(family)
        return Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.2)) {
                vm.toggleFamily(family)
            }
        } label: {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: family.systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)

                Text(family.displayName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(isSelected ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)

                if family.preloadedModelCount > 0 {
                    Text("\(family.preloadedModelCount) models")
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.bizarreOrange)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(BrandSpacing.md)
            .background(
                isSelected ? Color.bizarreOrange.opacity(0.1) : Color.bizarreSurface1.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.bizarreOrange.opacity(0.6) : Color.bizarreOutline.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(family.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to \(isSelected ? "deselect" : "select") \(family.displayName)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
