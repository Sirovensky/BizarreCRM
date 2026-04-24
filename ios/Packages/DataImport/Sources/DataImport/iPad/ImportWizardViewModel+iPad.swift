import Foundation

// MARK: - iPad-specific ViewModel extensions

extension ImportWizardViewModel {

    // MARK: - Row actions (ImportContextMenu)

    /// Optimistically clear the error entry for `row`, signalling a retry request.
    /// The UI re-renders immediately; server-side state is not changed here.
    public func retryRow(_ row: Int) {
        rowErrors = rowErrors.filter { $0.row != row }
    }

    /// Remove `row` from the error list, marking it as skipped in the UI.
    public func skipRow(_ row: Int) {
        rowErrors = rowErrors.filter { $0.row != row }
    }

    // MARK: - Step jump (sidebar)

    /// Jump back to a previously-completed step.
    ///
    /// Because `currentStep` uses `private(set)` the setter is file-private to
    /// `ImportWizardViewModel.swift`. Supported backward jumps:
    ///
    /// - `.mapping` — calls `loadPreview()` which fetches the preview and
    ///   transitions the VM to `.mapping` once the network call completes.
    ///
    /// Other backward jumps are surfaced as no-ops; the sidebar disables
    /// tapping on steps that cannot be safely re-entered without data loss.
    ///
    /// - Parameter step: A completed step to return to.
    public func jumpToStep(_ step: ImportWizardStep) {
        let wizardSteps = ImportWizardStep.wizardSteps
        guard
            let targetIdx  = wizardSteps.firstIndex(of: step),
            let currentIdx = wizardSteps.firstIndex(of: currentStep),
            targetIdx < currentIdx
        else { return }

        switch step {
        case .mapping:
            // Re-run loadPreview() — it re-fetches and transitions to .mapping.
            guard jobId != nil else { return }
            Task { await loadPreview() }

        default:
            // Other steps are shown as informational-only in the sidebar.
            break
        }
    }
}
