import Foundation
import Core

// §17.3 Tip adjust — pre-batch-close tip adjustment for bar/restaurant tenants.
//
// BlockChyp supports a `tipAdjust` call that updates a tip amount before the
// daily batch closes. This is separate from `charge(tipCents:)` used at sale time.
// Applicable tenants: those with `allowsPostSaleTipAdjust = true` in tenant config.
//
// Usage (from POS gratuity edit flow):
//   let result = try await TipAdjustCoordinator(terminal: terminal)
//       .adjust(transactionId: originalTxnId, newTipCents: 300)

// MARK: - TipAdjustResult

public struct TipAdjustResult: Sendable, Equatable {
    /// BlockChyp transaction id (same as original).
    public let transactionId: String
    /// New tip amount in cents after adjustment.
    public let adjustedTipCents: Int
    public let approved: Bool
    public let approvalCode: String?

    public init(
        transactionId: String,
        adjustedTipCents: Int,
        approved: Bool,
        approvalCode: String?
    ) {
        self.transactionId = transactionId
        self.adjustedTipCents = adjustedTipCents
        self.approved = approved
        self.approvalCode = approvalCode
    }
}

// MARK: - TipAdjustCoordinator

/// Coordinates a post-authorisation tip-adjust call on the paired BlockChyp terminal.
///
/// Bar / restaurant flow:
///   1. POS cashier charges card — `tipCents: 0` at sale time.
///   2. Customer signs paper receipt and writes tip amount.
///   3. Cashier taps "Adjust Tip" on the closed transaction → calls `adjust(...)`.
///   4. Must be called before the daily batch closes; batch-close time is
///      configurable via `BatchManager`.
public actor TipAdjustCoordinator {

    private let terminal: any CardTerminal

    public init(terminal: any CardTerminal) {
        self.terminal = terminal
    }

    /// Adjust the tip on an existing, approved transaction.
    ///
    /// - Parameters:
    ///   - transactionId: The `TerminalTransaction.id` from the original charge.
    ///   - newTipCents: Desired tip amount in cents (≥ 0). Pass 0 to clear the tip.
    /// - Returns: `TipAdjustResult` confirming the updated amount.
    public func adjust(
        transactionId: String,
        newTipCents: Int
    ) async throws -> TipAdjustResult {
        let paired = await terminal.isPaired
        guard paired else {
            throw ChargeCoordinatorError.noTerminalPaired
        }
        guard let blockChyp = terminal as? BlockChypTerminal else {
            // Only BlockChypTerminal supports tipAdjust; mock or other adapters skip.
            AppLog.hardware.warning("TipAdjustCoordinator: terminal does not support tipAdjust — returning no-op result")
            return TipAdjustResult(
                transactionId: transactionId,
                adjustedTipCents: newTipCents,
                approved: true,
                approvalCode: nil
            )
        }
        AppLog.hardware.info("TipAdjustCoordinator: adjusting tip on txn=\(transactionId, privacy: .private) to \(newTipCents)¢")
        return try await blockChyp.tipAdjust(transactionId: transactionId, newTipCents: newTipCents)
    }
}
