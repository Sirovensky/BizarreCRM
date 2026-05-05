import Foundation

/// Computes estimated SMS campaign cost.
/// Pure, value-based — no dependencies; trivially testable.
public enum EstimatedCostCalculator {
    public static let pricePerRecipient: Double = 0.025
    public static let approvalThreshold: Int = 100

    /// Returns cost as a formatted string like "~$8.55".
    public static func formattedCost(recipients: Int) -> String {
        let cost = Double(recipients) * pricePerRecipient
        return "~\(formatted(cost))"
    }

    /// Raw cost value.
    public static func cost(recipients: Int) -> Double {
        Double(recipients) * pricePerRecipient
    }

    /// Whether this campaign requires manager approval.
    public static func requiresApproval(recipients: Int) -> Bool {
        recipients > approvalThreshold
    }

    private static func formatted(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }
}
