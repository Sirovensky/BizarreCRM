import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - DataImportView (wizard entry)

/// Entry point for the Data Import wizard.
/// - iPhone: NavigationStack linear flow with step chips in the toolbar.
/// - iPad: NavigationSplitView with step sidebar + content detail.
public struct DataImportView: View {
    @State private var vm: ImportWizardViewModel
    private let onDismiss: () -> Void

    public init(repository: ImportRepository, onDismiss: @escaping () -> Void = {}) {
        _vm = State(wrappedValue: ImportWizardViewModel(repository: repository))
        self.onDismiss = onDismiss
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneWizard
            } else {
                iPadWizard
            }
        }
        .tint(.bizarreOrange)
    }

    // MARK: - iPhone: NavigationStack wizard

    private var iPhoneWizard: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                stepContent
            }
            .navigationTitle(vm.currentStep.title)
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.reset()
                        onDismiss()
                    }
                    .accessibilityIdentifier("import.cancel")
                }
                ToolbarItemGroup(placement: .principal) {
                    stepChips
                }
            }
            #if canImport(UIKit)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
        }
    }

    // MARK: - iPad: NavigationSplitView with sidebar

    private var iPadWizard: some View {
        NavigationSplitView {
            List(ImportWizardStep.wizardSteps, id: \.self, selection: Binding(
                get: { vm.currentStep },
                set: { _ in } // wizard drives navigation, not sidebar tap
            )) { step in
                sidebarRow(step)
            }
            .listStyle(.sidebar)
            .navigationTitle("Import Data")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.reset()
                        onDismiss()
                    }
                    .accessibilityIdentifier("import.cancel")
                }
            }
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                stepContent
                    .navigationTitle(vm.currentStep.title)
                    #if canImport(UIKit)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Step content dispatcher

    @ViewBuilder
    private var stepContent: some View {
        switch vm.currentStep {
        case .chooseSource:
            ImportSourcePickerView(selectedSource: $vm.selectedSource) {
                vm.confirmSource()
            }
        case .upload:
            ImportUploadView(vm: vm)
        case .preview:
            ImportPreviewView(vm: vm)
        case .mapping:
            ImportColumnMappingView(vm: vm)
        case .start:
            ImportStartView(vm: vm)
        case .progress:
            ImportProgressView(vm: vm)
        case .done:
            doneView
        case .errors:
            ImportErrorsView(vm: vm)
        }
    }

    // MARK: - Step chips (iPhone toolbar)

    private var stepChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(ImportWizardStep.wizardSteps, id: \.self) { step in
                    stepChip(step)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wizard steps")
    }

    private func stepChip(_ step: ImportWizardStep) -> some View {
        let isActive = vm.currentStep == step
        let isPast = stepIndex(step) < stepIndex(vm.currentStep)

        return HStack(spacing: DesignTokens.Spacing.xs) {
            if isPast {
                Image(systemName: "checkmark")
                    .font(.caption2.bold())
                    .accessibilityHidden(true)
            }
            Text(step.title)
                .font(.brandLabelSmall())
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .foregroundStyle(isActive ? Color.white : (isPast ? Color.bizarreSuccess : Color.bizarreOnSurfaceMuted))
        .background(
            Capsule().fill(isActive ? Color.bizarreOrange : (isPast ? Color.bizarreSuccess.opacity(0.2) : Color.bizarreSurface1))
        )
        .accessibilityLabel(step.title + (isActive ? ", current step" : (isPast ? ", completed" : "")))
    }

    // MARK: - Sidebar row (iPad)

    private func sidebarRow(_ step: ImportWizardStep) -> some View {
        let isActive = vm.currentStep == step
        let isPast = stepIndex(step) < stepIndex(vm.currentStep)

        return Label {
            Text(step.title)
                .font(.brandBodyMedium())
                .foregroundStyle(isActive ? Color.bizarreOrange : .bizarreOnSurface)
        } icon: {
            Image(systemName: isPast ? "checkmark.circle.fill" : step.systemImage)
                .foregroundStyle(isPast ? Color.bizarreSuccess : (isActive ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted))
        }
        .accessibilityLabel(step.title + (isActive ? ", current step" : (isPast ? ", completed" : "")))
    }

    // MARK: - Done view

    private var doneView: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("Import Complete")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            if let j = vm.job {
                Text("\(j.processedRows) customers imported · \(j.errorCount) errors")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("\(j.processedRows) customers imported with \(j.errorCount) errors")
            }
            if let j = vm.job, j.errorCount > 0 {
                Button("Review Errors") { Task { await vm.viewErrors() } }
                    .buttonStyle(.brandGlass)
                    .accessibilityIdentifier("import.done.reviewErrors")
            }
            Button("Done") {
                vm.reset()
                onDismiss()
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .accessibilityIdentifier("import.done.close")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Helpers

    private func stepIndex(_ step: ImportWizardStep) -> Int {
        ImportWizardStep.wizardSteps.firstIndex(of: step) ?? 99
    }
}
