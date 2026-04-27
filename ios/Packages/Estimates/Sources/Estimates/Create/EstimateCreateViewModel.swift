import Foundation
import Observation
import Core
import Networking

// §8 Phase 4 — EstimateCreateViewModel
// Creates a new estimate via POST /api/v1/estimates.

public let PendingSyncEstimateId: Int64 = -1

@MainActor
@Observable
public final class EstimateCreateViewModel {

    // MARK: - Header fields

    public var customerId: Int64?
    public var customerDisplayName: String = ""
    public var notes: String = ""
    public var validUntil: String = ""   // YYYY-MM-DD
    public var discountText: String = "" // decimal string

    // MARK: - Line items

    public var lineItems: [EstimateDraft.LineItemDraft] = []

    // MARK: - Submit state

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

    /// §8.3 — Prefill from a lead detail: customer identity carried over; no line items yet.
    /// The lead's linked customer is pre-selected so the user only needs to add line items + validity.
    ///
    /// Uses `LeadDetail` (rather than `Lead`) because only the detail response carries `customerId`.
    public init(api: APIClient, prefillFromLeadDetail lead: LeadDetail) {
        self.api = api
        // Map lead detail fields to estimate create fields
        self.customerId = lead.customerId
        let nameParts = [lead.firstName, lead.lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        let displayName = nameParts.isEmpty ? "Lead #\(lead.id)" : nameParts.joined(separator: " ")
        self.customerDisplayName = displayName
        self.notes = "Estimate created from lead #\(lead.id)."
        // Validity: default 30 days from today — tenant can configure
        let thirtyDays = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        self.validUntil = fmt.string(from: thirtyDays)
    }

    /// §8.3 — Lightweight prefill from `Lead` summary (no customerId available).
    /// Used when navigating from the lead list where detail has not been fetched.
    /// `customerId` will be nil — user must re-select from the customer picker.
    public init(api: APIClient, prefillFromLead lead: Lead) {
        self.api = api
        self.customerDisplayName = lead.displayName
        self.notes = "Estimate created from lead \(lead.orderId ?? "#\(lead.id)")."
        let thirtyDays = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        self.validUntil = fmt.string(from: thirtyDays)
    }

    // MARK: - Validation

    public var isValid: Bool {
        guard customerId != nil else { return false }
        // All line items present must have a valid description, positive quantity, and non-negative price
        let allItemsValid = lineItems.allSatisfy { item in
            !item.description.trimmingCharacters(in: .whitespaces).isEmpty &&
            (Double(item.unitPrice) != nil) &&
            (Int(item.quantity).map { $0 > 0 } ?? false)
        }
        return allItemsValid
    }

    // MARK: - Computed totals

    public var computedSubtotal: Double {
        lineItems.reduce(0) { acc, item in
            let qty = Double(item.quantity) ?? 0
            let price = Double(item.unitPrice) ?? 0
            return acc + qty * price
        }
    }

    public var computedTax: Double {
        lineItems.reduce(0) { acc, item in
            let tax = Double(item.taxAmount) ?? 0
            return acc + tax
        }
    }

    public var computedDiscount: Double { Double(discountText) ?? 0 }

    public var computedTotal: Double {
        max(0, computedSubtotal - computedDiscount + computedTax)
    }

    // MARK: - Line item mutations

    public func addLineItem() {
        lineItems.append(EstimateDraft.LineItemDraft())
        scheduleAutoSave()
    }

    public func removeLineItem(at offsets: IndexSet) {
        lineItems.remove(atOffsets: offsets)
        scheduleAutoSave()
    }

    public func removeLineItem(id: UUID) {
        lineItems.removeAll { $0.id == id }
        scheduleAutoSave()
    }

    // MARK: - Submit

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        validationErrors = [:]
        queuedOffline = false
        guard let cid = customerId else {
            errorMessage = "Pick a customer first."
            return
        }
        guard isValid else {
            errorMessage = "Check all line items — description and price are required."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let requestLineItems: [EstimateLineItemRequest]? = lineItems.isEmpty ? nil :
            lineItems.compactMap { $0.toRequest() }
        let discountValue: Double? = discountText.isEmpty ? nil : Double(discountText)

        let body = CreateEstimateRequest(
            customerId: cid,
            notes: notes.isEmpty ? nil : notes,
            validUntil: validUntil.isEmpty ? nil : validUntil,
            discount: discountValue,
            lineItems: requestLineItems
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

// MARK: - DraftRecoverable

@MainActor
extension EstimateCreateViewModel: DraftRecoverable {
    public typealias Draft = EstimateDraft
    public nonisolated static let screenId = "estimate.create"
}

// MARK: - Draft lifecycle

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
        notes               = d.notes
        validUntil          = d.validUntil
        discountText        = d.discount
        lineItems           = d.lineItems
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
            notes: notes,
            validUntil: validUntil,
            discount: discountText,
            lineItems: lineItems,
            updatedAt: Date()
        )
    }

    public func scheduleAutoSave() {
        _draftAutoSaverValue.push(currentDraft())
    }
}

// MARK: - AppError mapping

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
