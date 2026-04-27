#if canImport(UIKit)
import SwiftUI
import DesignSystem
#endif
import Foundation
import Observation
import Core
import Networking

// §4.12 — Handoff modal view model.
//
// Required reason + assignee picker. On confirm:
//   PUT /api/v1/tickets/:id with { assigned_to } + auto-logs a handoff note.
//
// Route confirmed: tickets.routes.ts:1804 (PUT /tickets/:id).

/// Handoff reason options — matches the spec verbatim.
public enum HandoffReason: String, CaseIterable, Sendable, Identifiable {
    case shiftChange   = "shift_change"
    case escalation    = "escalation"
    case outOfExpertise = "out_of_expertise"
    case other         = "other"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .shiftChange:    return "Shift change"
        case .escalation:     return "Escalation"
        case .outOfExpertise: return "Out of expertise"
        case .other:          return "Other"
        }
    }
}

@MainActor
@Observable
public final class TicketHandoffViewModel {

    // MARK: - State

    public private(set) var employees: [Employee] = []
    public private(set) var isLoadingEmployees: Bool = false
    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didSucceed: Bool = false

    // Form fields
    public var selectedReason: HandoffReason = .shiftChange
    public var otherReasonText: String = ""
    public var selectedEmployee: Employee?

    // Validation
    public var canSubmit: Bool {
        guard selectedEmployee != nil else { return false }
        if selectedReason == .other { return !otherReasonText.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    // MARK: - Private

    private let ticketId: Int64
    private let api: APIClient

    // MARK: - Init

    public init(ticketId: Int64, api: APIClient) {
        self.ticketId = ticketId
        self.api = api
    }

    // MARK: - Load employees

    public func loadEmployees() async {
        isLoadingEmployees = true
        defer { isLoadingEmployees = false }
        do {
            employees = try await api.ticketAssigneeCandidates()
        } catch {
            errorMessage = "Could not load employees: \(error.localizedDescription)"
        }
    }

    // MARK: - Submit handoff

    /// Assigns the ticket to `selectedEmployee` and auto-logs a note.
    /// Route: PUT /api/v1/tickets/:id with `{ assigned_to }`.
    public func submit() async {
        guard canSubmit, let employee = selectedEmployee else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let reason = selectedReason == .other
            ? otherReasonText.trimmingCharacters(in: .whitespaces)
            : selectedReason.displayName

        do {
            // Assign to new employee
            let body = HandoffBody(assignedTo: employee.id)
            _ = try await api.put(
                "/api/v1/tickets/\(ticketId)",
                body: body,
                as: TicketDetail.self
            )

            // Auto-log a handoff note (best-effort — don't fail if note fails)
            let noteBody = AddTicketNoteRequest(
                type: "internal",
                content: "Handoff to \(employee.displayName). Reason: \(reason)",
                isFlagged: false
            )
            try? await api.post(
                "/api/v1/tickets/\(ticketId)/notes",
                body: noteBody,
                as: TicketNoteResponse.self
            )

            didSucceed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - DTOs

private struct HandoffBody: Encodable, Sendable {
    let assignedTo: Int64

    enum CodingKeys: String, CodingKey {
        case assignedTo = "assigned_to"
    }
}

private struct TicketNoteResponse: Decodable, Sendable {
    let id: Int64?
}
