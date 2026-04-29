// Core/Localization/LocaleFormatter.swift
//
// §27 i18n groundwork — date, number, and currency formatters keyed by Locale.
//
// Design notes:
//   - All formatter instances are cached per (locale, style) tuple to avoid
//     expensive re-creation on every call.
//   - "Tenant region" is threaded in as an explicit Locale override so that
//     any caller can pass `TenantRegion.locale` without coupling Core to the
//     tenant settings package.
//   - No mutation: every public API returns a new value; the internal cache
//     is write-once per key and is protected with a simple NSLock.

import Foundation

// MARK: - Public interface

/// Locale-aware formatters for dates, numbers, and currencies.
///
/// ```swift
/// let fmt = LocaleFormatter(locale: Locale(identifier: "fr_FR"))
/// fmt.formatDate(Date(), style: .medium)        // "23 avr. 2026"
/// fmt.formatCurrency(1_999.99, currencyCode: "EUR")  // "1 999,99 €"
/// fmt.formatNumber(12_345.6)                    // "12 345,6"
/// ```
public struct LocaleFormatter: Sendable {

    // MARK: Properties

    public let locale: Locale

    // MARK: Init

    public init(locale: Locale) {
        self.locale = locale
    }

    // MARK: - Date formatting

    /// Format a `Date` using the named style.
    public func formatDate(_ date: Date, style: DateFormatter.Style = .medium) -> String {
        let formatter = FormatterCache.shared.dateFormatter(locale: locale, dateStyle: style, timeStyle: .none)
        return formatter.string(from: date)
    }

    /// Format a `Date` showing both date and time with the named styles.
    public func formatDateTime(
        _ date: Date,
        dateStyle: DateFormatter.Style = .medium,
        timeStyle: DateFormatter.Style = .short
    ) -> String {
        let formatter = FormatterCache.shared.dateFormatter(
            locale: locale,
            dateStyle: dateStyle,
            timeStyle: timeStyle
        )
        return formatter.string(from: date)
    }

    /// Format a `Date` using a custom Unicode date format string.
    public func formatDate(_ date: Date, template: String) -> String {
        let localisedTemplate = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale) ?? template
        let formatter = FormatterCache.shared.dateFormatter(locale: locale, formatString: localisedTemplate)
        return formatter.string(from: date)
    }

    // MARK: - Number formatting

    /// Format a plain decimal number.
    public func formatNumber(_ value: Double, fractionDigits: Int = 2) -> String {
        let formatter = FormatterCache.shared.numberFormatter(
            locale: locale,
            style: .decimal,
            fractionDigits: fractionDigits
        )
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Format a value as a percentage (0.0–1.0 range expected).
    public func formatPercent(_ value: Double) -> String {
        let formatter = FormatterCache.shared.numberFormatter(
            locale: locale,
            style: .percent,
            fractionDigits: 1
        )
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Format a value as a percentage with fraction-digit precision derived from
    /// the minor unit of `currencyCode`.
    ///
    /// Currencies with zero minor units (JPY, KWD whole-number tier, etc.) produce
    /// integer percentages; currencies with 2 minor units produce one decimal place
    /// (the standard); 3-minor-unit currencies (JOD, KWD sub-unit) get two
    /// decimal places.
    ///
    /// This ensures discount/tax-rate displays are consistent with the surrounding
    /// monetary values — e.g. a ¥ cart never shows "10.0 %" while prices show "¥10".
    ///
    /// - Parameters:
    ///   - value:        Fraction in 0.0 – 1.0 range (e.g. `0.075` → "7.5 %").
    ///   - currencyCode: ISO 4217 currency code (e.g. `"JPY"`, `"USD"`, `"JOD"`).
    public func formatPercent(_ value: Double, currencyCode: String) -> String {
        let fractionDigits = Self.percentFractionDigits(for: currencyCode)
        let formatter = FormatterCache.shared.numberFormatter(
            locale: locale,
            style: .percent,
            fractionDigits: fractionDigits
        )
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: - Currency minor-unit helpers (internal)

    /// Returns the appropriate number of fraction digits for a percentage that
    /// accompanies `currencyCode` amounts.
    ///
    /// Mapping rules:
    /// - 0 minor units → 0 fraction digits (whole-number percent)
    /// - 2 minor units → 1 fraction digit  (standard)
    /// - 3 minor units → 2 fraction digits (high-precision)
    internal static func percentFractionDigits(for currencyCode: String) -> Int {
        switch currencyCode.uppercased() {
        // Zero-decimal currencies (ISO 4217 exponent = 0)
        case "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW",
             "MGA", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF",
             "XOF", "XPF":
            return 0
        // Three-decimal currencies (ISO 4217 exponent = 3)
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
            return 2
        // Standard two-decimal currencies
        default:
            return 1
        }
    }

    // MARK: - Currency formatting

    /// Format a `Double` amount with an explicit currency code.
    ///
    /// Pass the tenant's currency code (e.g. `"EUR"`) to override whatever the
    /// device locale would produce by default.
    public func formatCurrency(_ amount: Double, currencyCode: String) -> String {
        let formatter = FormatterCache.shared.currencyFormatter(locale: locale, currencyCode: currencyCode)
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    /// Format an integer cent amount (divide by 100 internally) with an explicit
    /// currency code.  Useful when amounts are stored as cents in the database.
    public func formatCents(_ cents: Int, currencyCode: String) -> String {
        formatCurrency(Double(cents) / 100.0, currencyCode: currencyCode)
    }
}

// MARK: - Convenience factory keyed by Locale identifier

public extension LocaleFormatter {
    /// Return a formatter for a locale identifier string, e.g. `"ar_SA"`.
    static func forIdentifier(_ identifier: String) -> LocaleFormatter {
        LocaleFormatter(locale: Locale(identifier: identifier))
    }

    /// Well-known pre-built formatters for the four test locales.
    static let enUS = LocaleFormatter(locale: Locale(identifier: "en_US"))
    static let frFR = LocaleFormatter(locale: Locale(identifier: "fr_FR"))
    static let arSA = LocaleFormatter(locale: Locale(identifier: "ar_SA"))
    static let jaJP = LocaleFormatter(locale: Locale(identifier: "ja_JP"))
}

// MARK: - Internal cache

/// Thread-safe cache that avoids allocating new `DateFormatter` /
/// `NumberFormatter` instances on every call.
private final class FormatterCache: @unchecked Sendable {

    static let shared = FormatterCache()

    private let lock = NSLock()

    // Key tuples encoded as strings for dictionary keying.
    private var dateFormatters:   [String: DateFormatter]   = [:]
    private var numberFormatters: [String: NumberFormatter] = [:]

    private init() {}

    // MARK: DateFormatter

    func dateFormatter(
        locale: Locale,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> DateFormatter {
        let key = "date|\(locale.identifier)|\(dateStyle.rawValue)|\(timeStyle.rawValue)"
        return cachedDateFormatter(key: key) {
            let f = DateFormatter()
            f.locale     = locale
            f.dateStyle  = dateStyle
            f.timeStyle  = timeStyle
            return f
        }
    }

    func dateFormatter(locale: Locale, formatString: String) -> DateFormatter {
        let key = "dateCustom|\(locale.identifier)|\(formatString)"
        return cachedDateFormatter(key: key) {
            let f = DateFormatter()
            f.locale        = locale
            f.dateFormat    = formatString
            return f
        }
    }

    private func cachedDateFormatter(key: String, make: () -> DateFormatter) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let cached = dateFormatters[key] { return cached }
        let formatter = make()
        dateFormatters[key] = formatter
        return formatter
    }

    // MARK: NumberFormatter

    func numberFormatter(
        locale: Locale,
        style: NumberFormatter.Style,
        fractionDigits: Int
    ) -> NumberFormatter {
        let key = "num|\(locale.identifier)|\(style.rawValue)|\(fractionDigits)"
        return cachedNumberFormatter(key: key) {
            let f = NumberFormatter()
            f.locale              = locale
            f.numberStyle         = style
            f.minimumFractionDigits = fractionDigits
            f.maximumFractionDigits = fractionDigits
            return f
        }
    }

    func currencyFormatter(locale: Locale, currencyCode: String) -> NumberFormatter {
        let key = "cur|\(locale.identifier)|\(currencyCode)"
        return cachedNumberFormatter(key: key) {
            let f = NumberFormatter()
            f.locale        = locale
            f.numberStyle   = .currency
            f.currencyCode  = currencyCode
            return f
        }
    }

    private func cachedNumberFormatter(key: String, make: () -> NumberFormatter) -> NumberFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let cached = numberFormatters[key] { return cached }
        let formatter = make()
        numberFormatters[key] = formatter
        return formatter
    }
}
