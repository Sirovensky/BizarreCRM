import Foundation

// §4.3 + §4.5 — Ticket state machine
// Encodes the legal lifecycle graph as a pure value type so the same
// transition rules power:
//   - §4.6 TicketStatusTransitionSheet (which transitions to show)
//   - §4.4 TicketEditView transition picker
//   - Server-side guard echoed on the client for fast inline validation

// MARK: - Status

/// Canonical lifecycle states for a ticket.
/// Raw values are stable identifiers used in serialisation and deep-links.
public enum TicketStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case intake             = "intake"
    case diagnosing         = "diagnosing"
    case awaitingParts      = "awaitingParts"
    case awaitingApproval   = "awaitingApproval"
    case inRepair           = "inRepair"
    case readyForPickup     = "readyForPickup"
    case completed          = "completed"
    case canceled           = "canceled"
    case onHold             = "onHold"

    public var displayName: String {
        switch self {
        case .intake:           return "Intake"
        case .diagnosing:       return "Diagnosing"
        case .awaitingParts:    return "Awaiting Parts"
        case .awaitingApproval: return "Awaiting Approval"
        case .inRepair:         return "In Repair"
        case .readyForPickup:   return "Ready for Pickup"
        case .completed:        return "Completed"
        case .canceled:         return "Canceled"
        case .onHold:           return "On Hold"
        }
    }

    /// True for terminal states that no transition can leave.
    public var isTerminal: Bool {
        switch self {
        case .completed, .canceled: return true
        default: return false
        }
    }
}

// MARK: - Transition

/// Named actions that advance the lifecycle.
public enum TicketTransition: String, Sendable, CaseIterable, Hashable {
    case diagnose           = "diagnose"
    case orderParts         = "orderParts"
    case requestApproval    = "requestApproval"
    case approveAndRepair   = "approveAndRepair"
    case finishRepair       = "finishRepair"
    case pickup             = "pickup"
    case cancel             = "cancel"
    case hold               = "hold"
    case resume             = "resume"

    public var displayName: String {
        switch self {
        case .diagnose:         return "Start Diagnosing"
        case .orderParts:       return "Order Parts"
        case .requestApproval:  return "Request Approval"
        case .approveAndRepair: return "Approve & Start Repair"
        case .finishRepair:     return "Finish Repair"
        case .pickup:           return "Mark Picked Up"
        case .cancel:           return "Cancel"
        case .hold:             return "Put On Hold"
        case .resume:           return "Resume"
        }
    }

    /// SF Symbol name used on transition buttons and timeline event rows.
    public var systemImage: String {
        switch self {
        case .diagnose:         return "stethoscope"
        case .orderParts:       return "cart.fill"
        case .requestApproval:  return "checkmark.seal"
        case .approveAndRepair: return "wrench.fill"
        case .finishRepair:     return "checkmark.circle.fill"
        case .pickup:           return "hand.raised.fill"
        case .cancel:           return "xmark.circle.fill"
        case .hold:             return "pause.circle.fill"
        case .resume:           return "play.circle.fill"
        }
    }
}

// MARK: - Error

public enum StateMachineError: Error, Sendable, Equatable {
    case illegalTransition(from: TicketStatus, transition: TicketTransition)
}

extension StateMachineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .illegalTransition(from, transition):
            return "Cannot \(transition.displayName.lowercased()) from \"\(from.displayName)\"."
        }
    }
}

// MARK: - State machine

/// Pure-value state machine encoding the ticket lifecycle graph.
///
/// Immutable — `apply` returns a *new* status rather than mutating anything,
/// keeping callers safe under Swift 6 strict concurrency.
public struct TicketStateMachine: Sendable {

    private init() {}

    // MARK: — Allowed transitions

    /// Returns the transitions that are legal from `from`, ordered for display.
    public static func allowedTransitions(from: TicketStatus) -> [TicketTransition] {
        switch from {
        case .intake:
            return [.diagnose, .hold, .cancel]
        case .diagnosing:
            return [.orderParts, .requestApproval, .approveAndRepair, .hold, .cancel]
        case .awaitingParts:
            return [.approveAndRepair, .hold, .cancel]
        case .awaitingApproval:
            return [.approveAndRepair, .hold, .cancel]
        case .inRepair:
            return [.finishRepair, .orderParts, .hold, .cancel]
        case .readyForPickup:
            return [.pickup, .cancel]
        case .completed:
            return []   // terminal
        case .canceled:
            return []   // terminal
        case .onHold:
            return [.resume, .cancel]
        }
    }

    // MARK: — Apply

    /// Apply `transition` to `current`, returning the next status or an error.
    public static func apply(
        _ transition: TicketTransition,
        to current: TicketStatus
    ) -> Result<TicketStatus, StateMachineError> {
        let allowed = allowedTransitions(from: current)
        guard allowed.contains(transition) else {
            return .failure(.illegalTransition(from: current, transition: transition))
        }
        return .success(nextStatus(for: transition))
    }

    // MARK: — Private mapping

    /// Maps a transition to its target status regardless of source.
    /// Guard is always checked by `apply` before this is called.
    private static func nextStatus(for transition: TicketTransition) -> TicketStatus {
        switch transition {
        case .diagnose:         return .diagnosing
        case .orderParts:       return .awaitingParts
        case .requestApproval:  return .awaitingApproval
        case .approveAndRepair: return .inRepair
        case .finishRepair:     return .readyForPickup
        case .pickup:           return .completed
        case .cancel:           return .canceled
        case .hold:             return .onHold
        case .resume:           return .diagnosing   // resumes at last active state
        }
    }
}
