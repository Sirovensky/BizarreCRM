import Foundation

public enum Currency {
    public static func formatCents(_ cents: Int, code: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.string(from: NSDecimalNumber(value: Double(cents) / 100.0))
            ?? "$\(Double(cents) / 100.0)"
    }
}
