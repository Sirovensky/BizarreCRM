// Core/Localization/PluralFormat.swift
//
// §27 i18n groundwork — stringsdict-friendly plural helper.
//
// Swift's built-in `String(format:)` only supports `%d` / `%@` style
// substitution and has no knowledge of plural rules.  The platform solution
// is `.stringsdict` files (which define one/few/many/other CLDR rules) in
// combination with `String.localizedStringWithFormat`.
//
// This file provides:
//   1. `PluralFormat.string(key:count:)` — the primary one-count helper.
//   2. `PluralFormat.string(key:values:)` — multi-argument variant.
//   3. `PluralFormat.string(key:count:bundle:)` — explicit bundle override
//      (useful for per-package stringsdict files).
//
// .stringsdict schema (create in Resources/en.lproj/):
//   <key>plural.items</key>
//   <dict>
//     <key>NSStringLocalizedFormatKey</key>
//     <string>%#@items@</string>
//     <key>items</key>
//     <dict>
//       <key>NSStringFormatSpecTypeKey</key>  <string>NSStringPluralRuleType</string>
//       <key>NSStringFormatValueTypeKey</key> <string>d</string>
//       <key>one</key>   <string>%d item</string>
//       <key>other</key> <string>%d items</string>
//     </dict>
//   </dict>
//
// Usage:
//   PluralFormat.string(key: "plural.items", count: 1)   // "1 item"
//   PluralFormat.string(key: "plural.items", count: 5)   // "5 items"

import Foundation

// MARK: - PluralFormat

/// Stringsdict-aware plural formatter.
///
/// All helpers are static because there is no per-instance state; the heavy
/// lifting is done by `String.localizedStringWithFormat` which reads from
/// `.stringsdict` files baked into the app bundle.
public enum PluralFormat {

    // MARK: - Primary helpers

    /// Returns a localised string for `key` from the main bundle's `.stringsdict`,
    /// substituting `count` into the format string.
    ///
    /// - Parameters:
    ///   - key:    The key defined in a `.stringsdict` file.
    ///   - count:  The integer value used to select the correct plural rule.
    ///   - bundle: The bundle to search.  Defaults to `.main`.
    /// - Returns:  The localised and plural-resolved string.
    public static func string(key: String, count: Int, bundle: Bundle = .main) -> String {
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        return String.localizedStringWithFormat(format, count)
    }

    /// Returns a localised string for `key`, substituting multiple values.
    ///
    /// Use this when the `.stringsdict` entry has more than one variable, e.g.
    /// `"%1$d tickets assigned to %2$@"`.
    ///
    /// - Parameters:
    ///   - key:    The key defined in a `.stringsdict` file.
    ///   - values: CVarArg values to substitute in order.
    ///   - bundle: The bundle to search.  Defaults to `.main`.
    public static func string(key: String, values: CVarArg..., bundle: Bundle = .main) -> String {
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        return String.localizedStringWithFormat(format, values)
    }

    // MARK: - Common domain helpers

    /// `"N item(s)"` — convenience wrapper for item count strings.
    ///
    /// Requires a `.stringsdict` key `"plural.items"` in the bundle.
    public static func items(count: Int, bundle: Bundle = .main) -> String {
        string(key: PluralKeys.items, count: count, bundle: bundle)
    }

    /// `"N result(s)"` — convenience wrapper for search result counts.
    ///
    /// Requires a `.stringsdict` key `"plural.results"` in the bundle.
    public static func results(count: Int, bundle: Bundle = .main) -> String {
        string(key: PluralKeys.results, count: count, bundle: bundle)
    }

    /// `"N ticket(s)"` — convenience wrapper.
    ///
    /// Requires a `.stringsdict` key `"plural.tickets"` in the bundle.
    public static func tickets(count: Int, bundle: Bundle = .main) -> String {
        string(key: PluralKeys.tickets, count: count, bundle: bundle)
    }

    /// `"N day(s)"` — convenience wrapper.
    ///
    /// Requires a `.stringsdict` key `"plural.days"` in the bundle.
    public static func days(count: Int, bundle: Bundle = .main) -> String {
        string(key: PluralKeys.days, count: count, bundle: bundle)
    }

    // MARK: - Key constants

    /// String constants for known `.stringsdict` keys.
    ///
    /// Adding a new key here encourages a single point of truth and makes it
    /// straightforward to grep for usages.
    public enum PluralKeys {
        public static let items   = "plural.items"
        public static let results = "plural.results"
        public static let tickets = "plural.tickets"
        public static let days    = "plural.days"
    }
}

// MARK: - String extension convenience

public extension String {
    /// Returns `self` pluralised using `count` and the app's `.stringsdict`.
    ///
    /// Thin convenience so call-sites can write:
    /// ```swift
    /// "plural.tickets".pluralised(count: n)
    /// ```
    func pluralised(count: Int, bundle: Bundle = .main) -> String {
        PluralFormat.string(key: self, count: count, bundle: bundle)
    }
}
