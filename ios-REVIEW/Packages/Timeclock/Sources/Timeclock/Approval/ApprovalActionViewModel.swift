import Foundation
import Observation
import Networking
import Core

// MARK: - §14 ApprovalActionViewModel
//
// Owns the approve / reject state machine for a single clock entry.
// Approve and reject both call PATCH /api/v1/timesheet/clock-entries/:id with a
// standardised reason prefix so the audit trail records the manager's intent.
//
// Design contract:
//  - `reason` field is pre-populated on approve; must be non-empty on reject.
//  - Immutable state transitions: each action produces a new `ActionState` value.
//  - `@Observable` so SwiftUI picks up changes without Combine.

@MainActor
@Observable
public final class ApprovalActionViewModel {

    // MARK: - State

    public enum ActionState: Sendable, Equatable {
        case idle
        case processing
        case approved
        case rejected
        case failed(String)
    }

    public private(set) var actionState: ActionState = .idle

    /// Free-text reason shown in the reject sheet and written to the audit log.
    /// Pre-populated with "[APPROVED]" sentinel when the sheet opens for approval.
    public var reason: String = ""

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let entry: ClockEntry

    // MARK: - Init

    public init(entry: ClockEntry, api: APIClient) {
        self.entry = entry
        self.api   = api
    }

    // MARK: - Validation

    /// Approve requires no user-typed reason — the prefix is sufficient.
    public var canApprove: Bool { actionState == .idle || actionState == .failed("") }

    /// Reject requires a non-empty, user-supplied reason.
    public var canReject: Bool {
        !reason.trimmingCharacters(in: .whitespaces).isEmpty
            && (actionState == .idle || actionState.isFailed)
    }

    // MARK: - Actions

    /// PATCH /api/v1/timesheet/clock-entries/:id
    /// Reason written to audit log: "[APPROVED] <optional extra text>"
    public func approve(extraNote: String = "") async {
        guard actionState == .idle || actionState.isFailed else { return }
        let auditReason = extraNote.trimmingCharacters(in: .whitespaces).isEmpty
            ? ApprovalReasonPrefix.approved
            : "\(ApprovalReasonPrefix.approved) \(extraNote.trimmingCharacters(in: .whitespaces))"
        await performEdit(auditReason: auditReason, successState: .approved)
    }

    /// PATCH /api/v1/timesheet/clock-entries/:id
    /// Reason written to audit log: "[REJECTED] <reason>"
    /// `reason` must be non-empty — validated before calling.
    public func reject() async {
        let trimmed = reason.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            actionState = .failed("A rejection reason is required.")
            return
        }
        let auditReason = "\(ApprovalReasonPrefix.rejected) \(trimmed)"
        await performEdit(auditReason: auditReason, successState: .rejected)
    }

    // MARK: - Private

    private func performEdit(auditReason: String, successState: ActionState) async {
        actionState = .processing
        let edit = ClockEntryEditRequest(reason: auditReason)
        do {
            _ = try await api.editClockEntry(entryId: entry.id, edit: edit)
            actionState = successState
        } catch {
            AppLog.ui.error(
                "ApprovalActionVM edit failed: \(error.localizedDescription, privacy: .public)"
            )
            actionState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - ActionState helpers

private extension ApprovalActionViewModel.ActionState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
