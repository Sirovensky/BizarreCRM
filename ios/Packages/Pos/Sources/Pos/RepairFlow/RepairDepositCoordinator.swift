#if canImport(UIKit)
import Foundation
import Observation

// MARK: - RepairDepositCoordinator (stub)
//
// Local stub that mirrors the shape expected by Agent D's `PosTenderCoordinator`
// so PosRepairDepositView compiles standalone before Agent D lands.
//
// TODO: Replace this stub with a real import once Agent D's TenderV2 module
// is merged. The deposit-mode flag will wire into PosTenderCoordinator's
// `isDepositMode` initialiser parameter.

/// Minimal tender state needed by the deposit step.
@MainActor
@Observable
public final class RepairDepositCoordinator {

    // MARK: - State

    /// Total amount due for the repair (estimate in cents).
    public let totalCents: Int

    /// Amount the cashier will collect as deposit (cents). Editable.
    public var depositCents: Int

    /// `true` while the tender call is in flight.
    public private(set) var isProcessing: Bool = false

    /// Non-nil when an error occurs.
    public private(set) var errorMessage: String?

    /// Set to `true` once the deposit has been tendered successfully.
    public private(set) var isComplete: Bool = false

    // MARK: - Callbacks

    public var onTendered: ((Int) -> Void)?
    public var onCancel: (() -> Void)?

    // MARK: - Init

    public init(totalCents: Int, defaultDepositCents: Int) {
        self.totalCents = totalCents
        self.depositCents = defaultDepositCents
    }

    // MARK: - Derived

    /// Balance due at pickup after deposit.
    public var balanceDueCents: Int {
        max(0, totalCents - depositCents)
    }

    /// Formatted deposit string, e.g. "Deposit $50 of $327"
    public var depositHeaderText: String {
        "Deposit \(Self.formatCurrency(cents: depositCents)) of \(Self.formatCurrency(cents: totalCents))"
    }

    /// Formatted balance, e.g. "Balance due at pickup: $277"
    public var balanceFooterText: String {
        "Balance due at pickup: \(Self.formatCurrency(cents: balanceDueCents))"
    }

    // MARK: - Actions

    public func confirmDeposit() {
        guard !isProcessing else { return }
        guard depositCents > 0 else {
            errorMessage = "Deposit amount must be greater than zero."
            return
        }
        isProcessing = true
        errorMessage = nil
        // TODO: Replace with real tender call (PosTenderCoordinator.charge())
        // For now, simulate a successful deposit after calling back.
        isProcessing = false
        isComplete = true
        onTendered?(depositCents)
    }

    public func cancelDeposit() {
        onCancel?()
    }

    // MARK: - Helpers

    public static func formatCurrency(cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0.00"
    }
}
#endif
