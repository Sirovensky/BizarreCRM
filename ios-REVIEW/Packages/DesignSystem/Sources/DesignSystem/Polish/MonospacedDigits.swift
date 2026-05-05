import SwiftUI

// MARK: - MonospacedDigits modifier

/// Combines `.monospacedDigit()` with `.contentTransition(.numericText())`
/// for counters, badges, currency amounts, and any number that animates.
///
/// Respects Reduce Motion — disables the numeric roll animation when on.
///
/// **Usage:**
/// ```swift
/// Text(formattedAmount)
///     .monoNumeric()
///
/// // With explicit font:
/// Text("\(count)")
///     .font(.title2)
///     .monoNumeric()
/// ```
public struct MonospacedDigitsModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        if reduceMotion {
            content
                .monospacedDigit()
                .contentTransition(.identity)
        } else {
            content
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

// MARK: - View extension

public extension View {
    /// Applies monospaced digit rendering + numeric content transition.
    /// Use on all counters, badges, currency displays.
    func monoNumeric() -> some View {
        modifier(MonospacedDigitsModifier())
    }
}

// MARK: - Cents formatting helpers

/// Format an `Int` value in cents as a localized currency string.
///
/// All monetary values in BizarreCRM are stored as integer cents.
/// Never convert via Double — use these helpers at display sites only.
public enum CentsFormatter {
    /// Returns a `Decimal` from integer cents. Use with `Decimal.FormatStyle`.
    public static func decimal(fromCents cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    /// Formats cents as currency string using tenant/locale currency code.
    ///
    /// ```swift
    /// Text(CentsFormatter.string(cents: ticket.totalCents, currencyCode: "USD"))
    ///     .monoNumeric()
    /// ```
    public static func string(cents: Int, currencyCode: String, locale: Locale = .current) -> String {
        let value = decimal(fromCents: cents)
        let style = Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
        return value.formatted(style)
    }
}
