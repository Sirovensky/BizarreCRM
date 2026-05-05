import Foundation

// §4.9 — Bench workflow actions.
//
// Maps bench-specific UX gestures to TicketTransition values.
// Only transitions that are legal on the state machine are surfaced.
// Uses PATCH /api/v1/tickets/:id/status via changeTicketStatus(id:statusId:).

/// High-level bench workflow actions a technician can take while working on a ticket.
///
/// Each case maps to one or more `TicketTransition` values — the VM resolves
/// the concrete transition based on the ticket's current status.
public enum BenchAction: String, CaseIterable, Sendable, Hashable {

    /// Begin diagnosing — intake → diagnosing.
    case startDiagnostic

    /// Pause active work by placing ticket on hold.
    case pauseWork

    /// Resume work from on-hold — onHold → diagnosing.
    case resumeWork

    /// Order parts needed for the repair — diagnosing/inRepair → awaitingParts.
    case partsOrdered

    /// Mark repair complete, ticket ready for customer pickup — inRepair → readyForPickup.
    case readyForPickup

    /// Advance inRepair straight to readyForPickup alias — same as `readyForPickup`.
    /// Kept separate so the UI can show "Finish Repair" on the bench HUD.
    case finishRepair

    // MARK: - Presentation

    public var displayName: String {
        switch self {
        case .startDiagnostic: return "Start Diagnostic"
        case .pauseWork:        return "Pause Work"
        case .resumeWork:       return "Resume Work"
        case .partsOrdered:     return "Parts Ordered"
        case .readyForPickup:   return "Mark Ready for Pickup"
        case .finishRepair:     return "Finish Repair"
        }
    }

    public var systemImage: String {
        switch self {
        case .startDiagnostic: return "stethoscope"
        case .pauseWork:        return "pause.circle.fill"
        case .resumeWork:       return "play.circle.fill"
        case .partsOrdered:     return "cart.fill"
        case .readyForPickup:   return "hand.raised.fill"
        case .finishRepair:     return "checkmark.circle.fill"
        }
    }

    // MARK: - State-machine mapping

    /// Returns the `TicketTransition` that corresponds to this action
    /// given the ticket's current `TicketStatus`, or `nil` when the action
    /// is not legal in the current state.
    public func transition(from current: TicketStatus) -> TicketTransition? {
        let candidate: TicketTransition
        switch self {
        case .startDiagnostic: candidate = .diagnose
        case .pauseWork:        candidate = .hold
        case .resumeWork:       candidate = .resume
        case .partsOrdered:     candidate = .orderParts
        case .readyForPickup:   candidate = .finishRepair
        case .finishRepair:     candidate = .finishRepair
        }
        let allowed = TicketStateMachine.allowedTransitions(from: current)
        return allowed.contains(candidate) ? candidate : nil
    }

    // MARK: - Context-aware action list

    /// Returns bench actions that are currently legal given `status`.
    /// Ordered for display: primary action first, destructive last.
    public static func availableActions(for status: TicketStatus) -> [BenchAction] {
        allCases.filter { $0.transition(from: status) != nil }
    }
}
