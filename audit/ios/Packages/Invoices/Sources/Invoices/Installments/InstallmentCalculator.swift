import Foundation

// §7.9 InstallmentCalculator — pure; no UIKit dependency; fully testable.

/// A computed installment item without a server-assigned id.
public struct ComputedInstallmentItem: Sendable, Equatable {
    public let dueDate: Date
    /// Scheduled amount in cents for this installment.
    public let amountCents: Int

    public init(dueDate: Date, amountCents: Int) {
        self.dueDate = dueDate
        self.amountCents = amountCents
    }
}

public enum InstallmentCalculator {

    // MARK: - distribute

    /// Splits `totalCents` into `count` installments starting on `startDate`,
    /// spaced by `interval`. Any rounding remainder is added to the last installment.
    ///
    /// - Parameters:
    ///   - totalCents: Total invoice amount in whole cents. Must be > 0.
    ///   - count:      Number of installments. Must be ≥ 1.
    ///   - startDate:  Due date of the first installment.
    ///   - interval:   Calendar component that separates consecutive installments
    ///                 (`.month`, `.weekOfYear`, `.year`, etc.).
    ///   - calendar:   Calendar used for date arithmetic. Defaults to `.current`.
    /// - Returns:      Array of `count` items whose `amountCents` sums to `totalCents`.
    public static func distribute(
        totalCents: Int,
        count: Int,
        startDate: Date,
        interval: Calendar.Component,
        calendar: Calendar = .current
    ) -> [ComputedInstallmentItem] {
        guard count >= 1, totalCents > 0 else { return [] }

        let base = totalCents / count
        let remainder = totalCents % count

        return (0 ..< count).map { index in
            let dueDate = calendar.date(
                byAdding: interval,
                value: index,
                to: startDate
            ) ?? startDate

            // Remainder goes onto the last installment so total is exact.
            let extra = (index == count - 1) ? remainder : 0
            return ComputedInstallmentItem(dueDate: dueDate, amountCents: base + extra)
        }
    }

    // MARK: - Validation helpers

    /// Returns true when the supplied items' `amountCents` sum equals `expectedTotal`.
    public static func isBalanced(
        items: [ComputedInstallmentItem],
        expectedTotal: Int
    ) -> Bool {
        items.reduce(0) { $0 + $1.amountCents } == expectedTotal
    }

    /// Returns true when all items have `amountCents > 0` and are sorted
    /// chronologically (no two items share the same due date).
    public static func isValid(items: [ComputedInstallmentItem]) -> Bool {
        guard !items.isEmpty else { return false }
        guard items.allSatisfy({ $0.amountCents > 0 }) else { return false }
        let sorted = items.sorted { $0.dueDate < $1.dueDate }
        for i in 1 ..< sorted.count {
            if sorted[i].dueDate == sorted[i - 1].dueDate { return false }
        }
        return true
    }
}
