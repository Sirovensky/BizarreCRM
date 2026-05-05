import Foundation

/// Monetary formatting utilities for BizarreCRM.
///
/// All monetary amounts in the app are stored as **integer US cents** to avoid
/// floating-point rounding errors.  Use these helpers whenever a cent value
/// must be shown to the user — never divide by 100.0 and use `String(format:)`
/// directly, as that bypasses locale-aware grouping separators and currency
/// symbols.
///
/// ## Example
/// ```swift
/// let label = Currency.formatCents(1250)   // "$12.50" in en_US
/// let euroLabel = Currency.formatCents(1250, code: "EUR") // "€12.50"
/// ```
public enum Currency {
    /// Format an integer cent value as a locale-aware currency string.
    ///
    /// Uses `NumberFormatter` with `.currency` style so the output respects the
    /// user's locale (grouping separators, decimal mark, symbol position).
    ///
    /// - Parameters:
    ///   - cents: The amount in the smallest currency unit (e.g. US cents).
    ///     Negative values are formatted with a minus sign.
    ///   - code:  ISO 4217 currency code.  Defaults to `"USD"`.
    /// - Returns: A formatted string such as `"$12.50"` or `"€12,50"`.
    public static func formatCents(_ cents: Int, code: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.string(from: NSDecimalNumber(value: Double(cents) / 100.0))
            ?? "$\(Double(cents) / 100.0)"
    }
}
