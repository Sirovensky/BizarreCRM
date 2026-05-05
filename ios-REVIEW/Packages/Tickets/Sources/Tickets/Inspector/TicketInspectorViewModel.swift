import Foundation
import Observation
import Core
import Networking

// §22.1 — iPad Inspector pane view model.
//
// Holds the active ticket being inspected and handles quick-edit
// PATCH operations via the existing ticket API surface:
//   - Status change  → PATCH /tickets/:id/status (changeTicketStatus)
//   - Assignee       → PUT  /tickets/:id         (UpdateTicketRequest assignedTo)
//   - Priority       → field stored locally until server adds the column
//   - Tags           → field stored locally until server adds the column
//
// The VM does not re-fetch the full TicketDetail after a save. The caller
// (TicketDetailView / TicketsThreeColumnView) is responsible for refreshing
// the source of truth via the `onSaved` callback.

// MARK: - ViewModel

@MainActor
@Observable
public final class TicketInspectorViewModel {

    // MARK: — Source data

    /// The ticket currently open in the inspector.
    public private(set) var ticket: TicketDetail

    // MARK: — Editable fields

    /// ID of the status the user has chosen. Starts from the ticket's current statusId.
    public var selectedStatusId: Int64?

    /// Display name of the selected status (drives the picker label).
    public var selectedStatusName: String = ""

    /// Assignee employee ID. nil means "unassigned".
    public var assigneeId: Int64?

    /// Display name for the assignee field (populated by a picker callback).
    public var assigneeName: String = ""

    /// Priority free-text: "low", "normal", "high", "critical".
    /// TODO: wire to server field when UpdateTicketRequest exposes priority.
    public var priority: String = ""

    /// Tags as a comma-separated string.
    /// TODO: wire to server field when UpdateTicketRequest exposes tags.
    public var tagsText: String = ""

    // MARK: — Async state

    public private(set) var isLoadingStatuses: Bool = false
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didSave: Bool = false

    // MARK: — Status list (for the picker)

    public private(set) var availableStatuses: [TicketStatusRow] = []

    // MARK: — Dependencies

    @ObservationIgnored private let api: any APIClient
    public let onSaved: @MainActor @Sendable () -> Void

    // MARK: — Init

    public init(
        ticket: TicketDetail,
        api: any APIClient,
        onSaved: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.ticket = ticket
        self.api = api
        self.onSaved = onSaved
        resetFields(from: ticket)
    }

    // MARK: — Public interface

    /// Call when the parent view changes the active ticket (e.g. user selects a
    /// different row in the list column).
    public func setTicket(_ newTicket: TicketDetail) {
        ticket = newTicket
        resetFields(from: newTicket)
        didSave = false
        errorMessage = nil
    }

    /// Load available statuses for the picker.
    public func loadStatuses() async {
        guard availableStatuses.isEmpty, !isLoadingStatuses else { return }
        isLoadingStatuses = true
        defer { isLoadingStatuses = false }
        do {
            availableStatuses = try await api.listTicketStatuses()
        } catch {
            AppLog.ui.error("Inspector: status list failed: \(error.localizedDescription, privacy: .public)")
            // Non-fatal — inspector still works, status picker is degraded.
        }
    }

    /// Persist the current field values.
    public func save() async {
        guard !isSaving else { return }
        errorMessage = nil
        didSave = false

        isSaving = true
        defer { isSaving = false }

        do {
            // 1. Status change — only when the user picked a different status
            if let newStatusId = selectedStatusId, newStatusId != ticket.statusId {
                _ = try await api.changeTicketStatus(id: ticket.id, statusId: newStatusId)
            }

            // 2. Assignee change — only when the assignee was modified
            //    Priority and tags are not yet server-side fields; they are
            //    stored locally and will be persisted in a future sprint when
            //    UpdateTicketRequest exposes them.
            let currentAssignee = ticket.assignedTo
            if assigneeId != currentAssignee {
                let req = UpdateTicketRequest(assignedTo: assigneeId)
                _ = try await api.updateTicket(id: ticket.id, req)
            }

            didSave = true
            onSaved()
        } catch {
            AppLog.ui.error("Inspector save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Reset all fields to the current ticket values (cancel edits).
    public func cancel() {
        resetFields(from: ticket)
        errorMessage = nil
        didSave = false
    }

    // MARK: — Private

    private func resetFields(from source: TicketDetail) {
        selectedStatusId = source.statusId
        selectedStatusName = source.status?.name ?? ""
        assigneeId = source.assignedTo
        assigneeName = source.assignedUser?.fullName ?? ""
        priority = ""
        tagsText = ""
    }
}
