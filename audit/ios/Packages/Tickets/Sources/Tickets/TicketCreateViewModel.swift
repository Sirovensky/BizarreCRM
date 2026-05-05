import Foundation
import Observation
import Core
import Networking
import Customers

/// Sentinel id returned by `TicketCreateViewModel` when the create was
/// queued for offline sync instead of persisted server-side. Callers that
/// navigate immediately to detail should not use this id — it will resolve
/// to a real server id once the drain loop succeeds.
public let PendingSyncTicketId: Int64 = -1

@MainActor
@Observable
public final class TicketCreateViewModel {
    public var selectedCustomer: CustomerSummary?

    public var deviceName: String = ""
    public var imei: String = ""
    public var serial: String = ""
    public var additionalNotes: String = ""
    public var priceText: String = ""

    public internal(set) var isSubmitting = false
    public internal(set) var errorMessage: String?
    public internal(set) var createdId: Int64?
    public internal(set) var queuedOffline: Bool = false

    // §63 ext — draft recovery
    public internal(set) var _draftRecord: DraftRecord?
    public var draftRecord: DraftRecord? { _draftRecord }
    public internal(set) var _pendingDraft: TicketDraft?
    public internal(set) var validationErrors: [String: String] = [:]

    @ObservationIgnored internal let _draftStoreValue: DraftStore = DraftStore()
    @ObservationIgnored internal lazy var _draftAutoSaverValue: DraftAutoSaver<TicketDraft> =
        DraftAutoSaver(screen: "ticket.create", store: _draftStoreValue)

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public var price: Double { Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    public var isValid: Bool {
        selectedCustomer != nil
    }

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        queuedOffline = false
        guard let customer = selectedCustomer else {
            errorMessage = "Pick a customer first."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }

        let req = buildRequest(customerId: customer.id)

        do {
            let created = try await api.createTicket(req)
            createdId = created.id
            await clearDraftAfterSubmit()
        } catch {
            let appError = AppError.from(error)
            if case .offline = appError {
                await enqueueOffline(req)
                await handleAppError(appError)
            } else if TicketOfflineQueue.isNetworkError(error) {
                await enqueueOffline(req)
            } else {
                AppLog.ui.error("Ticket create failed: \(error.localizedDescription, privacy: .public)")
                await handleAppError(appError)
            }
        }
    }

    private func buildRequest(customerId: Int64) -> CreateTicketRequest {
        let device = CreateTicketRequest.NewDevice(
            deviceName: deviceName.trimmingCharacters(in: .whitespaces),
            imei: nilIfEmpty(imei),
            serial: nilIfEmpty(serial),
            additionalNotes: nilIfEmpty(additionalNotes),
            price: price
        )
        return CreateTicketRequest(customerId: customerId, devices: [device])
    }

    private func enqueueOffline(_ req: CreateTicketRequest) async {
        do {
            let payload = try TicketOfflineQueue.encode(req)
            await TicketOfflineQueue.enqueue(op: "create", payload: payload)
            createdId = PendingSyncTicketId
            queuedOffline = true
            errorMessage = nil
        } catch {
            AppLog.sync.error("Ticket create encode failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func nilIfEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
