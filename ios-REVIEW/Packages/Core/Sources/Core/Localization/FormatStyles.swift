// Core/Localization/FormatStyles.swift
//
// §27.2 Locale-aware formatters — modern Swift `FormatStyle` and
// `MeasurementFormatter` / `RelativeDateTimeFormatter` wrappers keyed by
// `Locale`.
//
// These complement the older `DateFormatter` / `NumberFormatter` APIs in
// `LocaleFormatter.swift` with:
//   - `Date.FormatStyle.dateTime` for declarative date+time output
//   - `Decimal.FormatStyle.Currency(code:)` for cash-safe Decimal currency
//   - `IntegerFormatStyle<Int>` / `FloatingPointFormatStyle<Double>` for plain numbers
//   - `.percent` `FormatStyle` for percentages (0.0–1.0 input)
//   - `MeasurementFormatter` for distances (rare, e.g. driving directions)
//   - `RelativeDateTimeFormatter` for "2 min ago" UI strings
//
// All caches are thread-safe and avoid re-allocating formatters across calls.

import Foundation

// MARK: - LocaleFormatter extensions (FormatStyle path)

public extension LocaleFormatter {

    // MARK: Dates — Date.FormatStyle.dateTime

    /// Format a `Date` using `Date.FormatStyle.dateTime` with this formatter's
    /// `Locale`.
    ///
    /// Pass a closure to compose fields, e.g. `.day().month().year()`.
    ///
    /// ```swift
    /// fmt.formatDateTime(Date()) { $0.day().month(.abbreviated).year() }
    /// ```
    @available(iOS 15.0, macOS 12.0, *)
    func formatDateTime(_ date: Date,
                        configure: (Date.FormatStyle) -> Date.FormatStyle = { $0 }) -> String {
        let base = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
        return configure(base).format(date)
    }

    // MARK: Currency — Decimal.FormatStyle.Currency

    /// Format a `Decimal` amount in the given currency using
    /// `Decimal.FormatStyle.Currency(code:)`.
    ///
    /// Prefer this over the `Double`-based `formatCurrency` for any value that
    /// originated from monetary calculations: `Decimal` avoids the binary
    /// floating-point rounding errors that bite POS/payment code.
    @available(iOS 15.0, macOS 12.0, *)
    func formatCurrency(_ amount: Decimal, currencyCode: String) -> String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }

    // MARK: Numbers — IntegerFormatStyle / FloatingPointFormatStyle

    /// Format an `Int` using the locale's grouping separator.
    @available(iOS 15.0, macOS 12.0, *)
    func formatNumber(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// Format a `Double` using the locale's grouping separator and a fraction
    /// digit range.
    @available(iOS 15.0, macOS 12.0, *)
    func formatNumber(_ value: Double, fractionDigits range: ClosedRange<Int>) -> String {
        value.formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(range))
        )
    }

    // MARK: Percent — FormatStyle path

    /// Format a fraction (0.0–1.0) as a locale-aware percent using
    /// `FloatingPointFormatStyle.Percent`.
    @available(iOS 15.0, macOS 12.0, *)
    func formatPercentStyle(_ value: Double, fractionDigits: Int = 1) -> String {
        value.formatted(
            .percent
                .locale(locale)
                .precision(.fractionLength(fractionDigits))
        )
    }

    // MARK: Distance — MeasurementFormatter

    /// Format a `Measurement<UnitLength>` (e.g. driving distance) using the
    /// locale's preferred unit system.
    ///
    /// Rarely surfaced in repair-shop UI but used for "X km away" branch
    /// pickers and shipping ETAs.
    func formatDistance(_ measurement: Measurement<UnitLength>,
                        unitOptions: MeasurementFormatter.UnitOptions = .naturalScale) -> String {
        let formatter = FormatStyleCache.shared.measurementFormatter(
            locale: locale,
            unitOptions: unitOptions
        )
        return formatter.string(from: measurement)
    }

    /// Convenience: format a distance given in meters.  Picks miles for `en_US`
    /// and similar locales, kilometers elsewhere via `.naturalScale`.
    func formatDistance(meters: Double) -> String {
        formatDistance(Measurement(value: meters, unit: UnitLength.meters))
    }

    // MARK: Relative — RelativeDateTimeFormatter

    /// Format a `Date` relative to `referenceDate` (default: now), e.g.
    /// "2 minutes ago", "in 3 days".
    ///
    /// Uses `RelativeDateTimeFormatter` keyed by this formatter's `Locale`.
    func formatRelative(_ date: Date,
                        relativeTo referenceDate: Date = Date(),
                        style: RelativeDateTimeFormatter.UnitsStyle = .full) -> String {
        let formatter = FormatStyleCache.shared.relativeDateTimeFormatter(
            locale: locale,
            unitsStyle: style
        )
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}

// MARK: - Internal cache for Measurement / Relative formatters

private final class FormatStyleCache: @unchecked Sendable {

    static let shared = FormatStyleCache()

    private let lock = NSLock()
    private var measurementFormatters: [String: MeasurementFormatter]   = [:]
    private var relativeFormatters:    [String: RelativeDateTimeFormatter] = [:]

    private init() {}

    func measurementFormatter(
        locale: Locale,
        unitOptions: MeasurementFormatter.UnitOptions
    ) -> MeasurementFormatter {
        let key = "meas|\(locale.identifier)|\(unitOptions.rawValue)"
        lock.lock(); defer { lock.unlock() }
        if let cached = measurementFormatters[key] { return cached }
        let f = MeasurementFormatter()
        f.locale       = locale
        f.unitOptions  = unitOptions
        f.unitStyle    = .medium
        f.numberFormatter.locale = locale
        f.numberFormatter.maximumFractionDigits = 1
        measurementFormatters[key] = f
        return f
    }

    func relativeDateTimeFormatter(
        locale: Locale,
        unitsStyle: RelativeDateTimeFormatter.UnitsStyle
    ) -> RelativeDateTimeFormatter {
        let key = "rel|\(locale.identifier)|\(unitsStyle.rawValue)"
        lock.lock(); defer { lock.unlock() }
        if let cached = relativeFormatters[key] { return cached }
        let f = RelativeDateTimeFormatter()
        f.locale     = locale
        f.unitsStyle = unitsStyle
        relativeFormatters[key] = f
        return f
    }
}
