import Foundation
import Core

// §63 ext — CustomerCreateViewModel draft auto-save + AppError recovery (Phase 2)

@MainActor
extension CustomerCreateViewModel: DraftRecoverable {
    public typealias Draft = CustomerDraft
    public nonisolated static let screenId = "customer.create"
}

// MARK: — Draft lifecycle

extension CustomerCreateViewModel {

    /// Call from `.task {}` in the view to check for a saved draft.
    public func onAppear() async {
        do {
            if let draft = try await _draftStoreValue.load(
                CustomerDraft.self,
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
                "CustomerCreateVM draft load error: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Restore saved draft into live form fields.
    public func restoreDraft() {
        guard let d = _pendingDraft else { return }
        firstName    = d.firstName
        lastName     = d.lastName
        email        = d.email
        phone        = d.phone
        mobile       = d.mobile
        organization = d.organization
        address1     = d.address1
        city         = d.city
        state        = d.state
        postcode     = d.postcode
        notes        = d.notes
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
    public func currentDraft() -> CustomerDraft {
        CustomerDraft(
            firstName: firstName,
            lastName: lastName,
            email: email,
            phone: phone,
            mobile: mobile,
            organization: organization,
            address1: address1,
            city: city,
            state: state,
            postcode: postcode,
            notes: notes,
            updatedAt: Date()
        )
    }

    /// Trigger debounced auto-save (call from onChange modifiers).
    public func scheduleAutoSave() {
        _draftAutoSaverValue.push(currentDraft())
    }
}

// MARK: — AppError mapping

extension CustomerCreateViewModel {

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
            errorMessage = "Customer already exists. Pull to refresh?"
        default:
            if let suggestion = appError.recoverySuggestion {
                errorMessage = "\(appError.errorDescription ?? "Error"). \(suggestion)"
            } else {
                errorMessage = appError.errorDescription
            }
        }
    }
}
