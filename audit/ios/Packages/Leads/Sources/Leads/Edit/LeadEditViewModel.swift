import Foundation
import Observation
import Core
import Networking

// MARK: - LeadEditViewModel

/// §9 Phase 4 — ViewModel for editing a lead's status, score override, notes,
/// assignee, and source. Calls `PUT /api/v1/leads/{id}`.
@MainActor
@Observable
public final class LeadEditViewModel {

    // MARK: - State

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

    // MARK: - Editable fields

    /// Given name.
    public var firstName: String
    /// Family name.
    public var lastName: String
    /// Phone number (raw; normalised on server).
    public var phone: String
    /// Email address.
    public var email: String
    /// Pipeline status: new | contacted | scheduled | qualified | proposal | lost
    public var status: String
    /// Free-text notes (supports @mentions per ActionPlan).
    public var notes: String
    /// Lead source: walk_in | phone | web | referral | campaign | other
    public var source: String
    /// Assigned user ID (nil = unassigned).
    public var assignedTo: Int?
    /// Required when `status == "lost"`.
    public var lostReason: String

    // MARK: - Read-only state

    public private(set) var state: State = .idle

    // MARK: - Private

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let leadId: Int64

    // MARK: - Init

    public init(api: APIClient, lead: LeadDetail) {
        self.api = api
        self.leadId = lead.id
        self.firstName = lead.firstName ?? ""
        self.lastName  = lead.lastName  ?? ""
        self.phone     = lead.phone     ?? ""
        self.email     = lead.email     ?? ""
        self.status    = lead.status    ?? "new"
        self.notes     = lead.notes     ?? ""
        self.source    = lead.source    ?? ""
        self.assignedTo = nil   // not exposed in LeadDetail; user selects from picker
        self.lostReason = ""
    }

    // MARK: - Actions

    /// Submits the edit to `PUT /api/v1/leads/{id}`. Guards against double-tap.
    public func save() async {
        guard case .idle = state else { return }
        state = .submitting
        let body = LeadUpdateBody(
            status:     status.isEmpty ? nil : status,
            notes:      notes.isEmpty ? nil : notes,
            assignedTo: assignedTo,
            source:     source.isEmpty ? nil : source,
            lostReason: lostReason.isEmpty ? nil : lostReason,
            firstName:  firstName.isEmpty ? nil : firstName,
            lastName:   lastName.isEmpty ? nil : lastName,
            email:      email.isEmpty ? nil : email,
            phone:      phone.isEmpty ? nil : phone
        )
        do {
            let updated = try await api.updateLead(id: leadId, body: body)
            state = .saved(updated)
        } catch {
            AppLog.ui.error("Lead edit failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Resets to `.idle` so the sheet can be re-used (e.g. after dismissing an
    /// error toast and retrying).
    public func reset() { state = .idle }
}
