import Foundation
import Observation
import Core
import Networking

/// Drives `TicketEditView`. The server's PUT /tickets/:id accepts a narrow
/// set of metadata fields — device/notes edits go through separate
/// endpoints and are out of scope for this form (same as Customers Phase 2,
/// which intentionally skipped tag/note edits).
@MainActor
@Observable
public final class TicketEditViewModel {
    public let ticketId: Int64

    public var discountText: String
    public var discountReason: String
    public var source: String
    public var referralSource: String
    public var dueOn: String            // YYYY-MM-DD free-text (matches Android)

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didSave: Bool = false
    public private(set) var queuedOffline: Bool = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient, ticket: TicketDetail) {
        self.api = api
        self.ticketId = ticket.id
        self.discountText = Self.formatDiscount(ticket.discount)
        self.discountReason = ticket.discountReason ?? ""
        self.source = ""                // server field is "source"; not on TicketDetail — user edits fresh
        self.referralSource = ticket.howDidUFindUs ?? ""
        self.dueOn = ""                 // server stores due_on but TicketDetail doesn't expose it yet
    }

    /// Discount field is always optional; we never require it. The only
    /// validation is that it parses as a non-negative number when present.
    public var isValid: Bool {
        guard !discountText.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        guard let value = parsedDiscount else { return false }
        return value >= 0
    }

    public var parsedDiscount: Double? {
        let trimmed = discountText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        didSave = false
        queuedOffline = false

        let discountString = discountText.trimmingCharacters(in: .whitespaces)
        if !discountString.isEmpty, parsedDiscount == nil {
            errorMessage = "Discount must be a number."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let req = buildRequest()

        do {
            _ = try await api.updateTicket(id: ticketId, req)
            didSave = true
        } catch {
            if TicketOfflineQueue.isNetworkError(error) {
                await enqueueOffline(req)
            } else {
                AppLog.ui.error("Ticket update failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    private func buildRequest() -> UpdateTicketRequest {
        UpdateTicketRequest(
            discount: parsedDiscount,
            discountReason: trim(discountReason),
            source: trim(source),
            referralSource: trim(referralSource),
            dueOn: trim(dueOn)
        )
    }

    private func enqueueOffline(_ req: UpdateTicketRequest) async {
        do {
            let payload = try TicketOfflineQueue.encode(req)
            await TicketOfflineQueue.enqueue(
                op: "update",
                entityServerId: ticketId,
                payload: payload
            )
            didSave = true
            queuedOffline = true
            errorMessage = nil
        } catch {
            AppLog.sync.error("Ticket update encode failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func trim(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Discount renders back-and-forth with two decimals unless the
    /// number is already an integer (so "$5" doesn't become "5.00" in
    /// the field).
    private static func formatDiscount(_ value: Double?) -> String {
        guard let value, value != 0 else { return "" }
        if value == floor(value) { return String(Int(value)) }
        return String(format: "%.2f", value)
    }
}
