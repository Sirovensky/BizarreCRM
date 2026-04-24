import Foundation
import Observation
import Core
import Networking

// MARK: - LeadStatusNoteViewModel

/// Lightweight ViewModel for inline status-change + optional note on the lead
/// detail screen (task §9.3 — lead status transitions + notes).
///
/// Calls `PUT /api/v1/leads/{id}` with only the changed fields so the server
/// state-machine guard (LEGAL_LEAD_TRANSITIONS) can enforce valid transitions.
/// The VM itself mirrors the server's allowed-transition map so the UI can
/// disable illegal destination statuses before the network call.
@MainActor
@Observable
public final class LeadStatusNoteViewModel {

    // MARK: - Types

    public enum State: Sendable {
        case idle
        case submitting
        case saved(LeadDetail)
        case failed(String)

        public var isSubmitting: Bool {
            if case .submitting = self { return true }
            return false
        }
    }

    // MARK: - Server-mirrored transition map
    //
    // Matches LEGAL_LEAD_TRANSITIONS in packages/server/src/routes/leads.routes.ts.
    // Unknown source statuses fall through permissively (custom tenant states).

    private static let legalTransitions: [String: [String]] = [
        "new":       ["contacted", "scheduled", "qualified", "lost"],
        "contacted": ["scheduled", "qualified", "proposal", "lost"],
        "scheduled": ["contacted", "qualified", "proposal", "lost"],
        "qualified": ["proposal", "contacted", "scheduled", "lost"],
        "proposal":  ["converted", "qualified", "lost"],
        "lost":      ["new", "contacted"],
        "converted": [],
    ]

    // MARK: - Editable state

    /// Currently selected destination status.
    public var selectedStatus: String
    /// Optional note to append (sent alongside the status update).
    public var note: String = ""
    /// Required when `selectedStatus == "lost"`.
    public var lostReason: String = ""

    // MARK: - Read-only

    public private(set) var state: State = .idle
    /// Source status the lead currently has.
    public let currentStatus: String

    // MARK: - Private

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let leadId: Int64

    // MARK: - Init

    public init(api: APIClient, lead: LeadDetail) {
        self.api = api
        self.leadId = lead.id
        self.currentStatus = lead.status ?? "new"
        self.selectedStatus = lead.status ?? "new"
    }

    // MARK: - Queries

    /// All destination statuses the server permits from `currentStatus`.
    /// Returns the full ordered list for unknown source statuses (permissive).
    public var allowedTransitions: [String] {
        Self.legalTransitions[currentStatus] ?? allStatuses
    }

    private let allStatuses = ["new", "contacted", "scheduled", "qualified", "proposal", "lost"]

    /// True when the save button should be enabled.
    public var canSave: Bool {
        guard !state.isSubmitting else { return false }
        guard selectedStatus != currentStatus else { return false }
        if selectedStatus == "lost" { return !lostReason.isEmpty }
        return true
    }

    // MARK: - Actions

    /// Submits `PUT /api/v1/leads/{id}` with the new status (and optional note).
    public func save() async {
        guard case .idle = state, canSave else { return }
        state = .submitting

        let body = LeadUpdateBody(
            status:     selectedStatus,
            notes:      note.isEmpty ? nil : note,
            lostReason: lostReason.isEmpty ? nil : lostReason
        )
        do {
            let updated = try await api.updateLead(id: leadId, body: body)
            state = .saved(updated)
        } catch {
            AppLog.ui.error("Status update failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Resets to `.idle` so the panel can be reused after error.
    public func reset() { state = .idle }
}
