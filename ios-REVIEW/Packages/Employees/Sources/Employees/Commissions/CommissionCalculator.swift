import Foundation
import Networking

// MARK: - CommissionCalculator

/// Pure, stateless helper. No I/O. Fully testable without mocks.
///
/// Matching logic (in order):
/// 1. Find all rules that match the sale (by serviceCategory, productCategory, role, condition).
/// 2. For each matched rule, compute raw commission.
/// 3. Apply per-rule cap if set.
/// 4. Sum across all matched rules.
public enum CommissionCalculator: Sendable {

    // MARK: - Public entry point

    public static func calculate(
        employeeId: String,
        period: DateInterval,
        rules: [CommissionRule],
        salesData: [Sale],
        employeeTenureMonths: Int = 0
    ) -> CommissionReport {
        let inPeriod = salesData.filter { period.contains($0.date) }
        var lineItems: [CommissionLineItem] = []

        for sale in inPeriod {
            for rule in rules {
                guard matches(rule: rule, sale: sale, tenureMonths: employeeTenureMonths) else { continue }
                let raw = computeRaw(rule: rule, saleAmount: sale.amount)
                let capped = cap(raw: raw, rule: rule)
                guard capped > 0 else { continue }
                lineItems.append(CommissionLineItem(
                    id: "\(sale.id)-\(rule.id)",
                    saleId: sale.id,
                    ruleId: rule.id,
                    saleAmount: sale.amount,
                    commissionAmount: capped,
                    description: describe(rule: rule, saleAmount: sale.amount)
                ))
            }
        }

        return CommissionReport(employeeId: employeeId, period: period, lineItems: lineItems)
    }

    // MARK: - Internal helpers

    static func matches(rule: CommissionRule, sale: Sale, tenureMonths: Int) -> Bool {
        // Category match (nil = any)
        if let sc = rule.serviceCategory, !sc.isEmpty {
            guard sale.serviceCategory?.caseInsensitiveCompare(sc) == .orderedSame else { return false }
        }
        if let pc = rule.productCategory, !pc.isEmpty {
            guard sale.productCategory?.caseInsensitiveCompare(pc) == .orderedSame else { return false }
        }
        // Condition checks
        if let cond = rule.condition {
            if let minVal = cond.minTicketValue, sale.amount < minVal { return false }
            if let minTenure = cond.tenureMonths, tenureMonths < minTenure { return false }
        }
        return true
    }

    static func computeRaw(rule: CommissionRule, saleAmount: Double) -> Double {
        switch rule.ruleType {
        case .percentage:
            return saleAmount * (rule.value / 100.0)
        case .flat:
            return rule.value
        }
    }

    static func cap(raw: Double, rule: CommissionRule) -> Double {
        if let cap = rule.capAmount, cap > 0 {
            return min(raw, cap)
        }
        return raw
    }

    private static func describe(rule: CommissionRule, saleAmount: Double) -> String {
        switch rule.ruleType {
        case .percentage:
            return String(format: "%.1f%% of $%.2f", rule.value, saleAmount)
        case .flat:
            return String(format: "$%.2f flat", rule.value)
        }
    }
}
