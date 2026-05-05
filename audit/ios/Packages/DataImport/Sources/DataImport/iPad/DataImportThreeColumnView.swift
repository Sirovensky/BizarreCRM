import SwiftUI
import Core
import DesignSystem

// MARK: - DataImportThreeColumnView

/// iPad-specific 3-column layout for the data import wizard.
///
/// Column layout:
/// 1. **Step sidebar** — `ImportStepSidebar`; 240 pt wide; Liquid Glass chrome.
/// 2. **Current step** — the existing wizard step views.
/// 3. **Live preview pane** — `ImportLivePreviewPane`; visible once a preview
///    is available (after the upload step completes).
///
/// The live preview column slides in once `vm.preview` is non-nil and collapses
/// back to nothing when the wizard is on steps that don't need a preview
/// (e.g. progress, done, errors).
///
/// Keyboard shortcuts are registered here via `dataImportKeyboardShortcuts`.
public struct DataImportThreeColumnView: View {

    // MARK: - State

    @Bindable var vm: ImportWizardViewModel
    private let onDismiss: () -> Void

    // MARK: - Init

    public init(vm: ImportWizardViewModel, onDismiss: @escaping () -> Void) {
        self.vm = vm
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Column 1 — step sidebar
            sidebarColumn
        } content: {
            // Column 2 — active wizard step
            stepColumn
        } detail: {
            // Column 3 — live preview pane (conditional)
            previewColumn
        }
        .navigationSplitViewStyle(.balanced)
        .dataImportKeyboardShortcuts(vm: vm, onDismiss: onDismiss)
        .tint(.bizarreOrange)
    }

    // MARK: - Column 1: Sidebar

    private var sidebarColumn: some View {
        ImportStepSidebar(
            steps: ImportWizardStep.wizardSteps,
            currentStep: vm.currentStep,
            onJumpTo: { step in
                // Jump is allowed only for completed steps; the sidebar enforces
                // this via disabled() but we double-check here for safety.
                if stepIndex(step) < stepIndex(vm.currentStep) {
                    vm.jumpToStep(step)
                }
            }
        )
        .navigationTitle("Import Data")
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    vm.reset()
                    onDismiss()
                }
                .accessibilityIdentifier("import.cancel")
                .keyboardShortcut("w", modifiers: .command)
            }
        }
        #if canImport(UIKit)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
    }

    // MARK: - Column 2: Step content

    private var stepColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            stepContent
                .navigationTitle(vm.currentStep.title)
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                #endif
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 480)
    }

    // MARK: - Column 3: Live preview

    @ViewBuilder
    private var previewColumn: some View {
        if let preview = vm.preview, showPreviewColumn {
            ImportLivePreviewPane(
                preview: preview,
                columnMapping: vm.columnMapping
            )
            .navigationTitle("Preview")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
            .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } else {
            // Placeholder keeps column stable in the split view
            Color.bizarreSurfaceBase
                .ignoresSafeArea()
                .overlay {
                    if !showPreviewColumn {
                        VStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 32))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityHidden(true)
                            Text("Preview unavailable\nat this step")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        VStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: "arrow.up.doc")
                                .font(.system(size: 32))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityHidden(true)
                            Text("Upload a file to\nsee a live preview")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 280)
        }
    }

    // MARK: - Step content dispatcher

    @ViewBuilder
    private var stepContent: some View {
        switch vm.currentStep {
        case .chooseSource:
            ImportSourcePickerView(selectedSource: $vm.selectedSource) {
                vm.confirmSource()
            }
        case .chooseEntity:
            ImportEntityPickerView(selectedEntity: $vm.selectedEntity) {
                vm.confirmEntity()
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

    // MARK: - Done view (inline)

    private var doneView: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            Spacer()

            Image(systemName: vm.job?.status == .rolledBack
                  ? "arrow.uturn.backward.circle.fill"
                  : "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(vm.job?.status == .rolledBack ? .bizarreWarning : .bizarreSuccess)
                .accessibilityHidden(true)

            Text(vm.job?.status == .rolledBack ? "Import Rolled Back" : "Import Complete")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)

            if let j = vm.job, j.status != .rolledBack {
                Text("\(j.processedRows) \(j.entityType.displayName.lowercased()) imported · \(j.errorCount) errors")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            VStack(spacing: DesignTokens.Spacing.md) {
                if let j = vm.job, j.errorCount > 0, j.status != .rolledBack {
                    Button("Review Errors") { Task { await vm.viewErrors() } }
                        .buttonStyle(.brandGlass)
                        .accessibilityIdentifier("import.done.reviewErrors")
                }

                if vm.job?.canRollback == true, vm.job?.status != .rolledBack {
                    Button {
                        Task { await vm.rollback() }
                    } label: {
                        if vm.isRollingBack {
                            HStack(spacing: DesignTokens.Spacing.sm) {
                                ProgressView().tint(.white)
                                Text("Rolling Back…")
                            }
                        } else {
                            Label("Undo Import", systemImage: "arrow.uturn.backward.circle")
                        }
                    }
                    .buttonStyle(.brandGlass)
                    .disabled(vm.isRollingBack)
                    .accessibilityIdentifier("import.done.rollback")
                }

                Button("Done") {
                    vm.reset()
                    onDismiss()
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .accessibilityIdentifier("import.done.close")
                .keyboardShortcut(.return, modifiers: .command)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// Whether the live preview column should be shown (has relevant content).
    private var showPreviewColumn: Bool {
        switch vm.currentStep {
        case .preview, .mapping, .start:
            return true
        default:
            return false
        }
    }

    private func stepIndex(_ step: ImportWizardStep) -> Int {
        ImportWizardStep.wizardSteps.firstIndex(of: step) ?? 99
    }
}
