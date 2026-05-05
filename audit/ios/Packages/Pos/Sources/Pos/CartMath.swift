import Foundation

/// Money math helpers. Wraps `Decimal` rounding + `NumberFormatter` so the
/// cart, display, and tests agree on exactly one rounding mode.
///
/// We use `.bankers` (banker's rounding / half-to-even) because it avoids
/// the cumulative upward bias of `.plain` across many line items. Bankers
/// matches the server's financial rounding policy — if we drift from it the
/// POS total and the invoice total diverge on closing.
public enum CartMath {

    /// Round a `Decimal` (dollars) to the nearest cent and return that as
    /// an `Int` count of cents. `NaN` or negative-zero collapses to `0`.
    public static func toCents(_ decimal: Decimal) -> Int {
        var input = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .bankers)
        let cents = rounded * 100
        var centsRounded = Decimal()
        var centsInput = cents
        NSDecimalRound(&centsRounded, &centsInput, 0, .bankers)
        return NSDecimalNumber(decimal: centsRounded).intValue
    }

    /// Format an integer cent count as a localized currency string. Used
    /// across cart rows, totals footer, and totals overlays. Always
    /// `.monospacedDigit()` on the display side.
    public static func formatCents(_ cents: Int, currencyCode: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        let decimal = Decimal(cents) / 100
        let number = NSDecimalNumber(decimal: decimal)
        return formatter.string(from: number) ?? "$\(cents / 100).\(String(format: "%02d", abs(cents) % 100))"
    }
}
