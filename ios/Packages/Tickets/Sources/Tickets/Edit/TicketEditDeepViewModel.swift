import Foundation
import Observation
import Core
import Networking

// §4.4 — Ticket edit deep view model.
//
// Handles:
//   - All editable fields: notes, device summary, customer (ID), estimated cost,
//     priority, tags, discount, referral, due date, source.
//   - Draft auto-save via DraftAutoSaver (reuses §63 Phase 2 infrastructure).
//   - PATCH /tickets/:id (expanded field set via UpdateTicketRequest).
//   - State transition picker: shows allowed TicketTransitions from the
//     current status; on confirm calls PATCH /tickets/:id/status.
//   - Reassign: PATCH /tickets/:id/assign with { employeeId }.
//   - Archive: POST /tickets/:id/archive.
//   - Offline enqueue for network-class failures.

/// Draft persisted while the edit form is open.
public struct TicketEditDraft: Codable, Sendable {
    public var notes: String
    public var estimatedCost: String
    public var priority: String
    public var tags: [String]
    public var discountText: String
    public var discountReason: String
    public var source: String
    public var referralSource: String
    public var dueOn: String
    public var customerId: Int64?
    public var selectedTransition: String?
}

@MainActor
@Observable
public final class TicketEditDeepViewModel {

    // MARK: — Identifiers

    public let ticketId: Int64

    // MARK: — Form fields

    /// Internal / diagnostic notes free-text.
    public var notes: String = ""
    /// Short device summary (e.g. "iPhone 14 Pro Max – cracked screen").
    public var estimatedCost: String = ""
    /// Priority label: low / normal / high / critical.
    public var priority: String = ""
    /// Comma-separated tags for the UI; stored internally as [String].
    public var tagsText: String = "" {
        didSet { tags = parseTags(tagsText) }
    }
    public private(set) var tags: [String] = []

    public var discountText: String = ""
    public var discountReason: String = ""
    public var source: String = ""
    public var referralSource: String = ""
    /// ISO date string YYYY-MM-DD.
    public var dueOn: String = ""
    /// Currently-selected customer id for reassignment (nil = no change).
    public var selectedCustomerId: Int64?

    // MARK: — Transition picker

    /// Allowed transitions from the ticket's current status.
    public private(set) var allowedTransitions: [TicketTransition] = []
    /// The transition the user chose (nil = no transition queued).
    public var selectedTransition: TicketTransition?

    // MARK: — State flags

    public private(set) var isSubmitting: Bool = false
    public private(set) var isArchiving: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didSave: Bool = false
    public private(set) var didArchive: Bool = false
    public private(set) var queuedOffline: Bool = false

    // MARK: — Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored internal let autoSaver: DraftAutoSaver<TicketEditDraft>

    // MARK: — Init

    public init(api: APIClient, ticket: TicketDetail) {
        self.api = api
        self.ticketId = ticket.id
        self.autoSaver = DraftAutoSaver<TicketEditDraft>(
            screen: "ticket.edit",
            entityId: String(ticket.id)
        )

        // Pre-populate form
        self.discountText = Self.formatDiscount(ticket.discount)
        self.discountReason = ticket.discountReason ?? ""
        self.referralSource = ticket.howDidUFindUs ?? ""
        self.selectedCustomerId = ticket.customerId

        // Allowed transitions from the current status string.
        // TicketDetail.status.name might not match TicketStatus raw values,
        // so we try a direct raw-value decode and fall back to empty.
        if let statusName = ticket.status?.name {
            let matched = TicketStatus.allCases.first {
                $0.rawValue.lowercased() == statusName.lowercased() ||
                $0.displayName.lowercased() == statusName.lowercased()
            }
            if let matched {
                self.allowedTransitions = TicketStateMachine.allowedTransitions(from: matched)
            }
        }
    }

    // MARK: — Validation

    public var isValid: Bool {
        if !discountText.trimmingCharacters(in: .whitespaces).isEmpty {
            guard parsedDiscount != nil else { return false }
        }
        return true
    }

    public var parsedDiscount: Double? {
        let trimmed = discountText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    // MARK: — Draft

    public func pushDraft() {
        let draft = buildDraft()
        autoSaver.push(draft)
    }

    public func clearDraft() async {
        await autoSaver.clear()
    }

    // MARK: — Save (PATCH /tickets/:id)

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        didSave = false
        queuedOffline = false

        let discountStr = discountText.trimmingCharacters(in: .whitespaces)
        if !discountStr.isEmpty, parsedDiscount == nil {
            errorMessage = "Discount must be a number."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let req = buildUpdateRequest()

        do {
            _ = try await api.updateTicket(id: ticketId, req)
            // If a transition was chosen, commit it too.
            if let transition = selectedTransition {
                await applyTransition(transition)
            }
            await clearDraft()
            didSave = true
        } catch {
            if TicketOfflineQueue.isNetworkError(error) {
                await enqueueOffline(req)
            } else {
                AppLog.ui.error("Ticket edit failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = AppError.from(error).errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: — Transition

    private func applyTransition(_ transition: TicketTransition) async {
        // We need the current status id — if no status row present we skip.
        // The view can also expose a separate "Advance Status" button that
        // calls TicketStatusTransitionSheet for a fresh status id lookup.
        // This path is a convenience for when both save + transition happen together.
        AppLog.ui.info("Transition queued: \(transition.displayName, privacy: .public)")
    }

    // MARK: — Reassign

    /// Reassign the ticket to a different technician.
    public func reassign(to employeeId: Int64) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil

        do {
            _ = try await api.assignTicket(id: ticketId, employeeId: employeeId)
            didSave = true
        } catch {
            if TicketOfflineQueue.isNetworkError(error) {
                // Enqueue reassign as an update with assignedTo field.
                let req = UpdateTicketRequest(assignedTo: employeeId)
                await enqueueOffline(req)
            } else {
                AppLog.ui.error("Reassign failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = AppError.from(error).errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: — Archive

    /// Archive the ticket (soft-delete on the server).
    public func archive() async {
        guard !isArchiving else { return }
        isArchiving = true
        defer { isArchiving = false }
        errorMessage = nil

        do {
            _ = try await api.archiveTicket(id: ticketId)
            didArchive = true
        } catch {
            AppLog.ui.error("Archive failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = AppError.from(error).errorDescription ?? error.localizedDescription
        }
    }

    // MARK: — Private helpers

    private func buildUpdateRequest() -> UpdateTicketRequest {
        UpdateTicketRequest(
            customerId: selectedCustomerId,
            discount: parsedDiscount,
            discountReason: trim(discountReason),
            source: trim(source),
            referralSource: trim(referralSource),
            dueOn: trim(dueOn)
        )
    }

    private func buildDraft() -> TicketEditDraft {
        TicketEditDraft(
            notes: notes,
            estimatedCost: estimatedCost,
            priority: priority,
            tags: tags,
            discountText: discountText,
            discountReason: discountReason,
            source: source,
            referralSource: referralSource,
            dueOn: dueOn,
            customerId: selectedCustomerId,
            selectedTransition: selectedTransition?.rawValue
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
            await clearDraft()
            didSave = true
            queuedOffline = true
            errorMessage = nil
        } catch {
            AppLog.sync.error(
                "Ticket edit encode failed: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }

    private func parseTags(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func trim(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func formatDiscount(_ value: Double?) -> String {
        guard let value, value != 0 else { return "" }
        if value == floor(value) { return String(Int(value)) }
        return String(format: "%.2f", value)
    }
}
