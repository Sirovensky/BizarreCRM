import Foundation
import Networking

/// §16.5 / §6 — Protocol abstracting the card-terminal payment flow.
///
/// The concrete implementation calls `POST /api/v1/blockchyp/process-payment`.
/// The protocol exists so:
///   1. `CashTenderViewModel` (and any future card-VM) can be tested without
///      a real BlockChyp terminal or network.
///   2. The POS package does not take a hard dependency on a `Hardware`
///      package (forbidden by ownership rules).
///   3. A stub can be shipped while BlockChyp wiring is in progress —
///      the UI is never orphaned.
///
/// Conforming types MUST be `Sendable` so they cross actor boundaries safely.
public protocol PosTerminalService: Sendable {
    /// Charge `amountCents` against the already-created `invoiceId` on the
    /// connected BlockChyp terminal.
    ///
    /// - Parameters:
    ///   - invoiceId: The server-side invoice to record the payment against.
    ///   - amountCents: Amount to charge (total due, tip already included).
    ///   - idempotencyKey: UUID string for server-side deduplication. The
    ///     caller is responsible for generating a stable, unique key per
    ///     charge attempt (retry with the SAME key replays; a new key retries).
    ///   - tipCents: Optional tip amount in cents included in `amountCents`.
    /// - Returns: A `PosTerminalResult` describing the outcome.
    /// - Throws: Any network or transport error (not a payment decline — those
    ///   are returned as `PosTerminalResult.declined`).
    func charge(
        invoiceId: Int64,
        amountCents: Int,
        idempotencyKey: String,
        tipCents: Int
    ) async throws -> PosTerminalResult
}

// MARK: - Result type

/// Outcome of a `PosTerminalService.charge` call.
public enum PosTerminalResult: Sendable, Equatable {
    /// Terminal approved — the invoice is now paid (or partially paid).
    case approved(
        transactionId: String?,
        cardLabel: String?,      // e.g. "Visa ••••1234"
        authCode: String?
    )
    /// Terminal declined the card.
    case declined(reason: String)
    /// Charge was sent but the outcome is unknown (terminal timeout +
    /// reconciliation query failed). The caller MUST surface a
    /// "Verify with manager" message and not retry automatically.
    case pendingReconciliation(transactionRef: String?)

    /// True only for `.approved`.
    public var isApproved: Bool {
        if case .approved = self { return true }
        return false
    }

    /// Human-readable one-liner for toasts and receipts.
    public var displayMessage: String {
        switch self {
        case .approved(_, let card, let auth):
            let parts = [card, auth.map { "Auth: \($0)" }].compactMap { $0 }
            return parts.isEmpty ? "Approved" : parts.joined(separator: " · ")
        case .declined(let reason):
            return "Declined: \(reason)"
        case .pendingReconciliation:
            return "Outcome unknown — verify with manager before retrying."
        }
    }
}

// MARK: - Live implementation

/// Live `PosTerminalService` backed by `POST /api/v1/blockchyp/process-payment`.
public struct LivePosTerminalService: PosTerminalService {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func charge(
        invoiceId: Int64,
        amountCents: Int,
        idempotencyKey: String,
        tipCents: Int
    ) async throws -> PosTerminalResult {
        let tipDollars: Double? = tipCents > 0 ? Double(tipCents) / 100.0 : nil
        let request = BlockChypPaymentRequest(
            invoiceId: invoiceId,
            idempotencyKey: idempotencyKey,
            tip: tipDollars
        )
        let response = try await api.blockChypProcessPayment(request)

        if response.isPendingReconciliation {
            return .pendingReconciliation(transactionRef: response.transactionRef)
        }
        if response.success {
            let cardLabel: String? = {
                guard let type = response.cardType, let last4 = response.last4 else { return nil }
                return "\(type) ••••\(last4)"
            }()
            return .approved(
                transactionId: response.transactionId,
                cardLabel: cardLabel,
                authCode: response.authCode
            )
        }
        return .declined(reason: "Payment did not complete")
    }
}

// MARK: - Stub (for previews + tests)

/// No-op stub that immediately returns a declined result.
/// Replace with `SimulatedPosTerminalService` in tests that need
/// configurable outcomes.
public struct StubPosTerminalService: PosTerminalService {
    public init() {}

    public func charge(
        invoiceId: Int64,
        amountCents: Int,
        idempotencyKey: String,
        tipCents: Int
    ) async throws -> PosTerminalResult {
        .declined(reason: "No terminal configured (stub)")
    }
}
