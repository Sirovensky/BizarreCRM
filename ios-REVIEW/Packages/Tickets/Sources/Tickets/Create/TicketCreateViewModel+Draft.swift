import Foundation
import Core

// §63 ext — TicketCreateViewModel draft auto-save + AppError recovery (Phase 2)

@MainActor
extension TicketCreateViewModel: DraftRecoverable {
    public typealias Draft = TicketDraft
    public nonisolated static let screenId = "ticket.create"
}

// MARK: — Draft lifecycle

extension TicketCreateViewModel {

    /// Call from `.task {}` in the view to check for a saved draft.
    public func onAppear() async {
        do {
            if let draft = try await _draftStoreValue.load(
                TicketDraft.self,
                screen: Self.screenId,
                entityId: nil
            ) {
                _pendingDraft = draft
                _draftRecord = DraftRecord(
                    screen: Self.screenId,
                    entityId: nil,
                    updatedAt: draft.updatedAt,
                    bytes: 0
                )
            }
        } catch {
            AppLog.ui.error(
                "TicketCreateVM draft load error: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Restore saved draft into live form fields.
    public func restoreDraft() {
        guard let d = _pendingDraft else { return }
        deviceName      = d.deviceName
        imei            = d.imei
        serial          = d.serial
        additionalNotes = d.notes
        priceText       = d.priceText
        _pendingDraft = nil
        _draftRecord  = nil
    }

    /// Discard saved draft and clear the store.
    public func discardDraft() {
        _pendingDraft = nil
        _draftRecord  = nil
        Task { await _draftAutoSaverValue.clear() }
    }

    /// Build a snapshot from current field values.
    public func currentDraft() -> TicketDraft {
        TicketDraft(
            customerId: selectedCustomer.map { String($0.id) },
            customerDisplayName: selectedCustomer?.displayName,
            deviceName: deviceName,
            imei: imei,
            serial: serial,
            notes: additionalNotes,
            priceText: priceText,
            updatedAt: Date()
        )
    }

    /// Trigger debounced auto-save (call from onChange modifiers).
    public func scheduleAutoSave() {
        _draftAutoSaverValue.push(currentDraft())
    }

    /// Clear draft after successful submit.
    public func clearDraftAfterSubmit() async {
        await _draftAutoSaverValue.clear()
    }
}

// MARK: — AppError mapping

extension TicketCreateViewModel {

    /// Map an `AppError` to a user-facing `errorMessage`.
    public func handleAppError(_ appError: AppError) async {
        switch appError {
        case .offline:
            _draftAutoSaverValue.push(currentDraft())
            errorMessage = "You're offline. Your draft will sync when you reconnect."
        case .validation(let fieldErrors):
            validationErrors = fieldErrors
            errorMessage = fieldErrors.values.first
        case .conflict:
            errorMessage = "Ticket already exists. Pull to refresh?"
        default:
            if let suggestion = appError.recoverySuggestion {
                errorMessage = "\(appError.errorDescription ?? "Error"). \(suggestion)"
            } else {
                errorMessage = appError.errorDescription
            }
        }
    }
}
