import Foundation
import Core

// §17.3 BlockChyp ChargeCoordinator — Phase 5
//
// High-level wrapper shown at POS checkout. Pure logic + closure-based
// presentation — POS owns the UI; this class coordinates the terminal
// interaction and returns a result.
//
// Sovereignty: uses BlockChypTerminal (api.blockchyp.com) directly.
// POS is NOT modified; this class is injected via DI.

// MARK: - ChargeCoordinatorError

public enum ChargeCoordinatorError: Error, LocalizedError, Sendable {
    case noTerminalPaired
    case chargeDeclined(String?)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noTerminalPaired:
            return "No card terminal is paired. Go to Settings → Hardware to pair a BlockChyp terminal."
        case .chargeDeclined(let msg):
            return msg.map { "Card declined: \($0)" } ?? "Card declined."
        case .cancelled:
            return "The charge was cancelled."
        }
    }
}

// MARK: - ChargeCoordinator

/// Coordinates a card charge through the active `CardTerminal`.
///
/// Usage (from POS):
/// ```swift
/// let coordinator = ChargeCoordinator(terminal: container.blockChypTerminal)
/// let txn = try await coordinator.coordinateCharge(
///     amountCents: cart.totalCents,
///     tipCents: cart.tipCents,
///     metadata: ["orderRef": invoiceId]
/// )
/// ```
///
/// Thread safety: actor-isolated; all public methods are safe to call
/// from any context.
public actor ChargeCoordinator {

    // MARK: - Dependencies

    private let terminal: any CardTerminal

    // MARK: - Init

    public init(terminal: any CardTerminal) {
        self.terminal = terminal
    }

    // MARK: - Public API

    /// Coordinate a charge for a cart total.
    ///
    /// - Parameters:
    ///   - amountCents: Total charge amount in cents.
    ///   - tipCents: Tip amount in cents (0 if no tip prompt).
    ///   - metadata: Optional metadata passed to BlockChyp (orderRef, description, etc.).
    /// - Returns: Approved `TerminalTransaction`.
    /// - Throws: `ChargeCoordinatorError` or re-throws `TerminalError` / `AppError`.
    public func coordinateCharge(
        amountCents: Int,
        tipCents: Int = 0,
        metadata: [String: String] = [:]
    ) async throws -> TerminalTransaction {
        let paired = await terminal.isPaired
        guard paired else {
            throw ChargeCoordinatorError.noTerminalPaired
        }

        AppLog.hardware.info("ChargeCoordinator: coordinating charge \(amountCents)¢ + tip \(tipCents)¢")

        let txn = try await terminal.charge(
            amountCents: amountCents,
            tipCents: tipCents,
            metadata: metadata
        )

        if !txn.approved {
            throw ChargeCoordinatorError.chargeDeclined(txn.errorMessage)
        }

        AppLog.hardware.info("ChargeCoordinator: charge approved txnId=\(txn.id, privacy: .private)")
        return txn
    }

    /// Cancel an in-flight charge (e.g. user pressed Cancel in the POS UI).
    public func cancelCharge() async {
        AppLog.hardware.info("ChargeCoordinator: cancelling charge")
        await terminal.cancel()
    }

    /// Reverse / refund a previous transaction.
    ///
    /// - Parameters:
    ///   - transactionId: The `id` from the original `TerminalTransaction`.
    ///   - amountCents: Amount to reverse (may be less than original for partial).
    public func reverseCharge(
        transactionId: String,
        amountCents: Int
    ) async throws -> TerminalTransaction {
        let paired = await terminal.isPaired
        guard paired else {
            throw ChargeCoordinatorError.noTerminalPaired
        }
        AppLog.hardware.info("ChargeCoordinator: reversing \(transactionId, privacy: .private) \(amountCents)¢")
        return try await terminal.reverse(transactionId: transactionId, amountCents: amountCents)
    }

    /// Ping the terminal.
    public func ping() async throws -> TerminalPingResult {
        let paired = await terminal.isPaired
        guard paired else {
            throw ChargeCoordinatorError.noTerminalPaired
        }
        return try await terminal.ping()
    }
}
