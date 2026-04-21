import Foundation
import Observation
import Core
import Networking

// §63 ext — EstimateCreateViewModel (Phase 2)
// Creates a new estimate via POST /api/v1/estimates.

public let PendingSyncEstimateId: Int64 = -1

@MainActor
@Observable
public final class EstimateCreateViewModel {

    // MARK: — Form fields

    public var customerId: Int64?
    public var customerDisplayName: String = ""
    public var subject: String = ""
    public var notes: String = ""
    public var validUntil: String = ""   // YYYY-MM-DD

    // MARK: — Submit state

    public internal(set) var isSubmitting: Bool = false
    public internal(set) var errorMessage: String?
    public internal(set) var createdId: Int64?
    public internal(set) var queuedOffline: Bool = false

    // §63 ext — draft recovery
    public internal(set) var _draftRecord: DraftRecord?
    public internal(set) var _pendingDraft: EstimateDraft?
    public internal(set) var validationErrors: [String: String] = [:]

    @ObservationIgnored internal let _draftStoreValue: DraftStore = DraftStore()
    @ObservationIgnored internal lazy var _draftAutoSaverValue: DraftAutoSaver<EstimateDraft> =
        DraftAutoSaver(screen: "estimate.create", store: _draftStoreValue)

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    // MARK: — Validation

    public var isValid: Bool { customerId != nil }

    // MARK: — Submit

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        queuedOffline = false
        guard let cid = customerId else {
            errorMessage = "Pick a customer first."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }

        let body = CreateEstimateRequest(
            customerId: cid,
            subject: subject.isEmpty ? nil : subject,
            notes: notes.isEmpty ? nil : notes,
            validUntil: validUntil.isEmpty ? nil : validUntil
        )

        do {
            let created = try await api.createEstimate(body)
            createdId = created.id
            await _draftAutoSaverValue.clear()
        } catch {
            let appError = AppError.from(error)
            AppLog.ui.error("Estimate create failed: \(error.localizedDescription, privacy: .public)")
            await handleAppError(appError)
        }
    }
}

// MARK: — DraftRecoverable

@MainActor
extension EstimateCreateViewModel: DraftRecoverable {
    public typealias Draft = EstimateDraft
    public nonisolated static let screenId = "estimate.create"
}

// MARK: — Draft lifecycle

extension EstimateCreateViewModel {

    public func onAppear() async {
        do {
            if let draft = try await _draftStoreValue.load(
                EstimateDraft.self,
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
                "EstimateCreateVM draft load error: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func restoreDraft() {
        guard let d = _pendingDraft else { return }
        customerId          = d.customerId.flatMap { Int64($0) }
        customerDisplayName = d.customerDisplayName ?? ""
        subject             = d.subject
        notes               = d.notes
        validUntil          = d.validUntil
        _pendingDraft = nil
        _draftRecord  = nil
    }

    public func discardDraft() {
        _pendingDraft = nil
        _draftRecord  = nil
        Task { await _draftAutoSaverValue.clear() }
    }

    public func currentDraft() -> EstimateDraft {
        EstimateDraft(
            customerId: customerId.map { String($0) },
            customerDisplayName: customerDisplayName.isEmpty ? nil : customerDisplayName,
            subject: subject,
            notes: notes,
            validUntil: validUntil,
            updatedAt: Date()
        )
    }

    public func scheduleAutoSave() {
        _draftAutoSaverValue.push(currentDraft())
    }
}

// MARK: — AppError mapping

extension EstimateCreateViewModel {

    public func handleAppError(_ appError: AppError) async {
        switch appError {
        case .offline:
            _draftAutoSaverValue.push(currentDraft())
            queuedOffline = true
            errorMessage = "You're offline. Your draft will sync when you reconnect."
        case .validation(let fieldErrors):
            validationErrors = fieldErrors
            errorMessage = fieldErrors.values.first
        case .conflict:
            errorMessage = "Estimate already exists. Pull to refresh?"
        default:
            if let suggestion = appError.recoverySuggestion {
                errorMessage = "\(appError.errorDescription ?? "Error"). \(suggestion)"
            } else {
                errorMessage = appError.errorDescription
            }
        }
    }
}
