import Foundation
import Hardware

// MARK: - PosPaymentError
//
// §17.11 — Typed payment-error surface for the POS tender layer.
//
// `BlockChypTerminal` / `ChargeCoordinator` already speak `TerminalError` and
// `ChargeCoordinatorError`, both of which carry vendor-flavoured strings. The
// POS UI must never show a raw vendor message ("E_DECLINE_05") to a cashier,
// nor must ViewModels branch on string-pattern matching to decide whether to
// re-enable the "Card" tile vs. switch to cash.
//
// `PosPaymentError` is the canonical, exhaustive enum the tender layer maps
// every lower-level error onto. Each case carries:
//   • `errorDescription`        — a short, cashier-facing line.
//   • `recommendedAction`       — verb-first guidance ("Retry", "Switch to cash").
//   • `allowsRetry`             — drives the "Retry" button's enabled state.
//   • `requiresManagerOverride` — true for cross-batch refunds + voids the cashier
//                                 isn't authorised to perform.

public enum PosPaymentError: Error, LocalizedError, Sendable, Equatable {
    /// Card was declined by the issuer.
    case declined(reason: String)

    /// Terminal stopped responding within the timeout window (default 60s).
    case timeout

    /// iPad has no path to the BlockChyp gateway and the terminal is in
    /// cloud-relay mode. Local-relay terminals may still succeed.
    case networkUnavailable

    /// Terminal is mid-charge or mid-batch-close; can't accept a second job.
    case terminalBusy

    /// Tried to void a transaction whose batch has already settled.
    case voidNotAllowed

    /// No terminal paired in Settings → Hardware → Terminal.
    case notPaired

    /// Terminal is paired but the heartbeat reports it offline.
    case terminalOffline

    /// Operator pressed Cancel on the iPad or the terminal.
    case cancelled

    /// Catch-all for unmapped vendor errors — passes the raw vendor text
    /// through so support can read it from the audit log later.
    case unknown(detail: String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .declined(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Card declined." : "Card declined — \(trimmed)."
        case .timeout:
            return "The card reader didn't respond. Try again or use another tender."
        case .networkUnavailable:
            return "No network connection to the card processor. Card payments are unavailable until you're back online."
        case .terminalBusy:
            return "The card reader is busy with another transaction. Wait a moment and retry."
        case .voidNotAllowed:
            return "This transaction has already settled. Issue a refund instead of a void."
        case .notPaired:
            return "No card reader is paired. Go to Settings → Hardware → Terminal to set one up."
        case .terminalOffline:
            return "The card reader is offline. Check power and network, then retry."
        case .cancelled:
            return "Charge cancelled."
        case .unknown(let detail):
            return detail.isEmpty ? "Unexpected card-reader error." : "Card reader error: \(detail)"
        }
    }

    // MARK: - UX guidance

    public var recommendedAction: String {
        switch self {
        case .declined:           return "Try a different card or use cash."
        case .timeout:            return "Retry, or switch to another tender."
        case .networkUnavailable: return "Use cash, check, or park the cart for later."
        case .terminalBusy:       return "Wait 5 seconds and retry."
        case .voidNotAllowed:     return "Use the Refund flow instead."
        case .notPaired:          return "Pair a terminal in Settings."
        case .terminalOffline:    return "Check terminal power and network, then retry."
        case .cancelled:          return "Resume by tapping Charge again."
        case .unknown:            return "Retry. If the error repeats, contact support."
        }
    }

    public var allowsRetry: Bool {
        switch self {
        case .declined, .timeout, .terminalBusy, .terminalOffline, .cancelled, .unknown:
            return true
        case .networkUnavailable, .voidNotAllowed, .notPaired:
            return false
        }
    }

    public var requiresManagerOverride: Bool {
        switch self {
        case .voidNotAllowed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Mapping from lower layers

public extension PosPaymentError {

    /// Map an `Error` from the Hardware layer onto a tender-friendly case.
    /// Always falls back to `.unknown(detail:)` rather than throwing, so the
    /// tender flow has a deterministic UI state for every error path.
    static func from(_ error: Error) -> PosPaymentError {
        if let posError = error as? PosPaymentError { return posError }

        if let charge = error as? ChargeCoordinatorError {
            switch charge {
            case .noTerminalPaired:        return .notPaired
            case .chargeDeclined(let msg): return .declined(reason: msg ?? "")
            case .cancelled:               return .cancelled
            }
        }

        if let terminal = error as? TerminalError {
            switch terminal {
            case .notPaired:                       return .notPaired
            case .pairingFailed(let detail):       return .unknown(detail: detail)
            case .chargeFailed(let detail):        return PosPaymentError.classifyChargeFailure(detail)
            case .reversalFailed(let detail):      return PosPaymentError.classifyReversalFailure(detail)
            case .pingFailed:                      return .terminalOffline
            case .unreachable:                     return .terminalOffline
            }
        }

        // URLError → networkUnavailable for offline cases.
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .dataNotAllowed,
                 .internationalRoamingOff:
                return .networkUnavailable
            case .timedOut:
                return .timeout
            case .cancelled:
                return .cancelled
            default:
                return .unknown(detail: urlError.localizedDescription)
            }
        }

        return .unknown(detail: error.localizedDescription)
    }

    private static func classifyChargeFailure(_ detail: String) -> PosPaymentError {
        let lower = detail.lowercased()
        if lower.contains("timeout") || lower.contains("timed out") {
            return .timeout
        }
        if lower.contains("busy") || lower.contains("in use") {
            return .terminalBusy
        }
        if lower.contains("network") || lower.contains("offline") || lower.contains("unreachable") {
            return .networkUnavailable
        }
        if lower.contains("decline") || lower.contains("denied") || lower.contains("insufficient") {
            return .declined(reason: detail)
        }
        return .unknown(detail: detail)
    }

    private static func classifyReversalFailure(_ detail: String) -> PosPaymentError {
        let lower = detail.lowercased()
        if lower.contains("settled") || lower.contains("batch closed") || lower.contains("not found") {
            return .voidNotAllowed
        }
        return .unknown(detail: detail)
    }
}
