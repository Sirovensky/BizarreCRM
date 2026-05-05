import Foundation

// §7.12 LateFeeCalculator — pure; no UIKit dependency; fully testable.
// Tests cover: flat, percent, compound, grace window per task spec.

public typealias Cents = Int

/// Simple invoice value object for fee calculation purposes.
/// Decoupled from the full `InvoiceDetail` to keep the calculator testable
/// without needing the entire Networking graph.
public struct InvoiceForFeeCalc: Sendable {
    /// Balance still outstanding (unpaid amount) in cents.
    public let balanceCents: Cents
    /// Invoice due date. Nil means the invoice has no due date — no late fee applies.
    public let dueDate: Date?

    public init(balanceCents: Cents, dueDate: Date?) {
        self.balanceCents = balanceCents
        self.dueDate = dueDate
    }
}

public enum LateFeeCalculator {

    // MARK: - compute

    /// Calculates the late fee in cents for an invoice as of a given date.
    ///
    /// Rules applied in order:
    /// 1. If `dueDate` is nil → no fee.
    /// 2. If `asOf` ≤ `dueDate + gracePeriodDays` → no fee (still in grace period).
    /// 3. If `flatFeeCents` is set → return that (capped by `maxFeeCents`).
    /// 4. If `percentPerDay` is set → accumulate daily for each overdue day past grace.
    ///    - Non-compound: fee = balance × rate × overdueDays
    ///    - Compound: fee = balance × ((1 + rate/100)^overdueDays - 1), rounded to cents
    /// 5. Apply `maxFeeCents` cap if present.
    ///
    /// - Parameters:
    ///   - invoice: An `InvoiceForFeeCalc` with balance and due date.
    ///   - asOf:    The date at which the fee is computed.
    ///   - policy:  The `LateFeePolicy` governing the calculation.
    ///   - calendar: Calendar used for day arithmetic. Defaults to `.current`.
    /// - Returns: Fee amount in whole cents. Always ≥ 0.
    public static func compute(
        invoice: InvoiceForFeeCalc,
        asOf: Date,
        policy: LateFeePolicy,
        calendar: Calendar = .current
    ) -> Cents {
        guard let dueDate = invoice.dueDate, invoice.balanceCents > 0 else { return 0 }

        // Normalise to start-of-day for comparison.
        let dueMidnight = calendar.startOfDay(for: dueDate)
        let asMidnight  = calendar.startOfDay(for: asOf)

        let totalDaysLate = calendar.dateComponents([.day], from: dueMidnight, to: asMidnight).day ?? 0
        guard totalDaysLate > policy.gracePeriodDays else { return 0 }

        let overdueDays = totalDaysLate - policy.gracePeriodDays

        var feeCents: Cents

        if let flat = policy.flatFeeCents {
            // Flat fee takes precedence when set.
            feeCents = flat
        } else if let pct = policy.percentPerDay {
            let rate = pct / 100.0
            if policy.compoundDaily {
                // Compound: balance × ((1 + r)^n - 1)
                let multiplier = pow(1.0 + rate, Double(overdueDays)) - 1.0
                feeCents = Cents((Double(invoice.balanceCents) * multiplier).rounded())
            } else {
                // Simple: balance × r × n
                feeCents = Cents((Double(invoice.balanceCents) * rate * Double(overdueDays)).rounded())
            }
        } else {
            // No policy configured.
            return 0
        }

        // Apply cap.
        if let cap = policy.maxFeeCents {
            feeCents = min(feeCents, cap)
        }

        return max(0, feeCents)
    }
}
