import Foundation
import Observation
import Core
import Networking

// §63 ext — InvoiceCreateViewModel (Phase 2)
// Creates a new invoice via POST /api/v1/invoices.

public let PendingSyncInvoiceId: Int64 = -1

@MainActor
@Observable
public final class InvoiceCreateViewModel {

    // MARK: — Form fields

    public var customerId: Int64?
    public var customerDisplayName: String = ""
    public var ticketId: Int64?
    public var notes: String = ""
    public var dueOn: String = ""
    public var paymentTerms: String = ""           // §7.3 payment terms
    public var footerText: String = ""             // §7.3 footer text
    public var depositRequired: Bool = false       // §7.3 deposit required flag
    public var lineItems: [DraftLineItem] = []     // §7.3 line items
    public var cartDiscount: Double = 0            // §7.3 cart-level discount ($)
    public var sendOnCreate: Bool = false          // §7.3 send now checkbox

    public struct DraftLineItem: Identifiable, Sendable {
        public var id = UUID()
        public var description: String = ""
        public var quantity: Int = 1
        public var unitPrice: Double = 0
        public var taxAmount: Double = 0
        public var lineDiscount: Double = 0
        public var inventoryItemId: Int64? = nil

        public var isValid: Bool {
            !description.trimmingCharacters(in: .whitespaces).isEmpty && quantity > 0 && unitPrice >= 0
        }

        public var lineTotal: Double { unitPrice * Double(quantity) - lineDiscount + taxAmount }
    }

    // MARK: — Submit state

    public internal(set) var isSubmitting: Bool = false
    public internal(set) var errorMessage: String?
    public internal(set) var createdId: Int64?
    public internal(set) var queuedOffline: Bool = false

    // §63 ext — draft recovery
    public internal(set) var _draftRecord: DraftRecord?
    public internal(set) var _pendingDraft: InvoiceDraft?
    public internal(set) var validationErrors: [String: String] = [:]

    // §7.3+ Draft auto-save indicator — updated each time a push completes
    public private(set) var draftSavedAt: Date?

    @ObservationIgnored internal let _draftStoreValue: DraftStore = DraftStore()
    @ObservationIgnored internal lazy var _draftAutoSaverValue: DraftAutoSaver<InvoiceDraft> =
        DraftAutoSaver(screen: "invoice.create", store: _draftStoreValue)

    @ObservationIgnored private let api: APIClient
    /// §7.3 Idempotency key — generated once per create session.
    /// Passed as `idempotency_key` in the request body so the server can
    /// deduplicate retries from flaky networks.
    @ObservationIgnored private let idempotencyKey: String = UUID().uuidString

    public init(api: APIClient) { self.api = api }

    // MARK: — Validation

    public var isValid: Bool {
        customerId != nil && lineItems.allSatisfy { $0.isValid }
    }

    // MARK: — Line item helpers (§7.3)

    public func addLineItem() {
        lineItems.append(DraftLineItem())
        scheduleAutoSave()
    }

    public func removeLineItem(id: UUID) {
        lineItems.removeAll { $0.id == id }
        scheduleAutoSave()
    }

    /// Computed subtotal (before cart discount).
    public var lineItemsSubtotal: Double {
        lineItems.reduce(0) { $0 + $1.lineTotal }
    }

    /// Total after cart discount.
    public var computedTotal: Double {
        max(0, lineItemsSubtotal - cartDiscount)
    }

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

        let requestLineItems = lineItems.map { item in
            InvoiceLineItemRequest(
                inventoryItemId: item.inventoryItemId,
                description: item.description,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                taxAmount: item.taxAmount,
                lineDiscount: item.lineDiscount
            )
        }
        let body = CreateInvoiceRequest(
            customerId: cid,
            ticketId: ticketId,
            notes: notes.isEmpty ? nil : notes,
            dueOn: dueOn.isEmpty ? nil : dueOn,
            discount: cartDiscount > 0 ? cartDiscount : nil,
            lineItems: requestLineItems,
            idempotencyKey: idempotencyKey
        )

        do {
            let created = try await api.createInvoice(body)
            createdId = created.id
            await _draftAutoSaverValue.clear()
        } catch {
            let appError = AppError.from(error)
            AppLog.ui.error("Invoice create failed: \(error.localizedDescription, privacy: .public)")
            await handleAppError(appError)
        }
    }
}

// MARK: — DraftRecoverable

@MainActor
extension InvoiceCreateViewModel: DraftRecoverable {
    public typealias Draft = InvoiceDraft
    public nonisolated static let screenId = "invoice.create"
}

// MARK: — Draft lifecycle

extension InvoiceCreateViewModel {

    public func onAppear() async {
        do {
            if let draft = try await _draftStoreValue.load(
                InvoiceDraft.self,
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
                "InvoiceCreateVM draft load error: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func restoreDraft() {
        guard let d = _pendingDraft else { return }
        customerId = d.customerId.flatMap { Int64($0) }
        customerDisplayName = d.customerDisplayName ?? ""
        ticketId = d.ticketId.flatMap { Int64($0) }
        notes = d.notes
        dueOn = d.dueOn
        lineItems = d.lineItems.map { li in
            var item = DraftLineItem()
            item.description = li.description
            item.quantity = max(1, Int(li.quantity.rounded()))
            item.unitPrice = li.unitPrice
            return item
        }
        _pendingDraft = nil
        _draftRecord  = nil
    }

    public func discardDraft() {
        _pendingDraft = nil
        _draftRecord  = nil
        Task { await _draftAutoSaverValue.clear() }
    }

    public func currentDraft() -> InvoiceDraft {
        InvoiceDraft(
            customerId: customerId.map { String($0) },
            customerDisplayName: customerDisplayName.isEmpty ? nil : customerDisplayName,
            ticketId: ticketId.map { String($0) },
            notes: notes,
            dueOn: dueOn,
            lineItems: lineItems.map { InvoiceDraft.LineItemDraft(
                description: $0.description,
                quantity: Double($0.quantity),
                unitPrice: $0.unitPrice
            )},
            updatedAt: Date()
        )
    }

    public func scheduleAutoSave() {
        _draftAutoSaverValue.push(currentDraft())
        // §7.3+ Record the moment so the view can show "Draft saved HH:mm"
        draftSavedAt = Date()
    }
}

// MARK: — AppError mapping

extension InvoiceCreateViewModel {

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
            errorMessage = "Invoice already exists. Pull to refresh?"
        default:
            if let suggestion = appError.recoverySuggestion {
                errorMessage = "\(appError.errorDescription ?? "Error"). \(suggestion)"
            } else {
                errorMessage = appError.errorDescription
            }
        }
    }
}
