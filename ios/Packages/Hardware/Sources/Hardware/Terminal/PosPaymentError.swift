import Foundation

// §17.11 BlockChyp parity — `PosPaymentError`
// ----------------------------------------------------------------------------
// Single error surface for every card-payment call POS makes through the
// Hardware layer. The action plan requires:
//
//   "all `BlockChypService` errors are mapped to `PosPaymentError` cases —
//    `.declined(reason:)`, `.timeout`, `.networkUnavailable`, `.terminalBusy`,
//    `.voidNotAllowed` (cross-batch). Each case has a localized user-facing
//    message and a recommended action."
//
// The repository / service layer maps low-level `TerminalError` + URL /
// transport failures into these cases so POS view models never see vendor
// strings or raw HTTP codes. Cashiers see plain English; admins see the
// action hint directly under the alert title.

/// User-facing card-payment error surfaced to POS.
///
/// All cases conform to `LocalizedError` so SwiftUI alert presenters
/// (`Alert(error:)`, `.alert(_:isPresented:)`) pick up the strings without
/// extra wiring. Pair with ``recommendedAction`` for the one-line "what now?"
/// hint shown beneath the alert title.
public enum PosPaymentError: Error, LocalizedError, Sendable, Equatable {

    /// Terminal accepted the card but the issuer declined. `reason` is the
    /// terminal-supplied human string (e.g. "INSUFFICIENT_FUNDS"); the
    /// localized message paraphrases it for the cashier.
    case declined(reason: String)

    /// No response from the terminal within the configured charge timeout
    /// (default 60s). The cancel signal has already been sent.
    case timeout

    /// iPad has no internet path to BlockChyp cloud-relay (or local LAN
    /// route to the terminal in local mode).
    case networkUnavailable

    /// Terminal is busy with another transaction or stuck on a prior
    /// approval screen. Caller should wait and retry rather than re-charge.
    case terminalBusy

    /// Void requested for a transaction that has already been batched.
    /// Caller should fall through to refund-via-token instead.
    case voidNotAllowed

    /// Tip-adjust attempted after the batch was closed.
    case tipAdjustAfterBatchClose

    /// Generic / unexpected error. `detail` is preserved for logs but never
    /// shown raw to the cashier.
    case unknown(detail: String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .declined(let reason):
            return "Card declined — \(reason)"
        case .timeout:
            return "Card reader timed out"
        case .networkUnavailable:
            return "Card reader unavailable offline"
        case .terminalBusy:
            return "Card reader is busy"
        case .voidNotAllowed:
            return "Void not allowed on this transaction"
        case .tipAdjustAfterBatchClose:
            return "Tip adjustment is no longer possible"
        case .unknown:
            return "Card payment failed"
        }
    }

    // MARK: - Recommended action (one-line hint)

    /// Short hint shown below the error title. POS uses this to direct the
    /// cashier to the next sensible step rather than just acknowledging.
    public var recommendedAction: String {
        switch self {
        case .declined:
            return "Ask the customer for another payment method, or retry the same card."
        case .timeout:
            return "Check that the terminal is powered on, then try the charge again."
        case .networkUnavailable:
            return "Use cash, or park the cart and retry once the network is back."
        case .terminalBusy:
            return "Wait a moment for the terminal to finish, then try again."
        case .voidNotAllowed:
            return "Issue a refund instead — the original sale has already been batched."
        case .tipAdjustAfterBatchClose:
            return "Process a separate adjustment via the cardholder's bank, or refund and re-charge."
        case .unknown:
            return "Try again. If the issue persists, contact your administrator."
        }
    }

    // MARK: - Equatable

    public static func == (lhs: PosPaymentError, rhs: PosPaymentError) -> Bool {
        switch (lhs, rhs) {
        case (.declined(let a),       .declined(let b)):       return a == b
        case (.timeout,               .timeout):               return true
        case (.networkUnavailable,    .networkUnavailable):    return true
        case (.terminalBusy,          .terminalBusy):          return true
        case (.voidNotAllowed,        .voidNotAllowed):        return true
        case (.tipAdjustAfterBatchClose, .tipAdjustAfterBatchClose): return true
        case (.unknown(let a),        .unknown(let b)):        return a == b
        default: return false
        }
    }
}

// MARK: - Mapping from low-level TerminalError

extension PosPaymentError {
    /// Convenience converter so call sites can `throw PosPaymentError(from: terminalError)`
    /// without sprinkling `switch` blocks across the codebase.
    public init(from terminalError: TerminalError) {
        switch terminalError {
        case .notPaired:
            self = .unknown(detail: "Terminal not paired")
        case .pairingFailed(let detail):
            self = .unknown(detail: "Pairing failed: \(detail)")
        case .chargeFailed(let detail):
            // Treat any charge-failed string from BlockChyp as a decline so
            // the cashier sees a card-friendly message rather than raw API
            // copy. Caller can override before throwing if it has more
            // signal (timeout vs decline vs unknown).
            self = .declined(reason: detail)
        case .reversalFailed(let detail):
            self = .voidNotAllowed
            _ = detail // keep for future log routing
        case .pingFailed:
            self = .networkUnavailable
        case .unreachable:
            self = .networkUnavailable
        }
    }
}
