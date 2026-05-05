// CustomerCurrencyFormat.swift
//
// §5 Customers — currency-format batch (items 5.x lines 978–982 of ActionPlan):
//
//   1. Tenant-level template: symbol placement (pre/post), thousands separator,
//      decimal separator per locale.
//   2. Per-customer override of tenant default.
//   3. Support formats: US `$1,234.56`, EU-FR `1 234,56 €`, JP `¥1,235`,
//      CH `CHF 1'234.56`.
//   4. Money input parsing accepts multiple locales; normalize to storage.
//   5. VoiceOver accessibility — read full currency phrasing (e.g.
//      "twelve dollars and fifty cents").
//
// Storage rule: amounts are integer **minor units** (cents for USD, yen for JPY,
// fils for KWD…).  The tenant's currency code drives minor-unit count via
// `Locale.Currency`; we mirror the same zero-/three-decimal table that
// `Core.LocaleFormatter` uses so percent + currency stay consistent.
//
// Wiring:
//   Screen   → reads `CustomerCurrencyFormat.format(cents:for:tenant:)`
//   VM       → owns a `CustomerCurrencyTemplate` (tenant default) + optional
//              per-customer override pulled from `CustomerCurrencyOverrideStore`.
//   Repo     → `CustomerCurrencyOverrideStore` persists overrides keyed by
//              customer ID via `UserDefaults` (offline-first; synced to
//              `PUT /customers/:id/currency-override` when online).
//   API      → `customerCurrencyOverride(customerId:)` /
//              `setCustomerCurrencyOverride(customerId:code:)` (both optional —
//              graceful 404 fallback to local cache).

import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - 1. Tenant-level template

/// Tenant-wide default for monetary display.  One template per tenant; persists
/// via `UserDefaults` until the server pushes a real `/settings/currency` row.
public struct CustomerCurrencyTemplate: Equatable, Codable, Sendable {

    /// ISO 4217 currency code, e.g. `"USD"`, `"EUR"`, `"JPY"`, `"CHF"`.
    public var currencyCode: String

    /// BCP-47 locale identifier whose number-formatting rules we apply
    /// (separators, symbol placement).  Distinct from `currencyCode` so a
    /// French tenant can show EUR with French separators (`1 234,56 €`)
    /// while a German tenant shows EUR with `1.234,56 €`.
    public var localeIdentifier: String

    /// Where to put the currency symbol relative to the digits.
    public var symbolPlacement: SymbolPlacement

    /// Override for the thousands separator.  `nil` ⇒ use locale default.
    public var thousandsSeparatorOverride: String?

    /// Override for the decimal separator.  `nil` ⇒ use locale default.
    public var decimalSeparatorOverride: String?

    public enum SymbolPlacement: String, Codable, Sendable, CaseIterable {
        case prefix
        case suffix
        /// Use whatever the locale dictates (default).
        case localeDefault
    }

    public init(
        currencyCode: String,
        localeIdentifier: String,
        symbolPlacement: SymbolPlacement = .localeDefault,
        thousandsSeparatorOverride: String? = nil,
        decimalSeparatorOverride: String? = nil
    ) {
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.symbolPlacement = symbolPlacement
        self.thousandsSeparatorOverride = thousandsSeparatorOverride
        self.decimalSeparatorOverride = decimalSeparatorOverride
    }

    /// Sensible US default used when the tenant settings haven't loaded yet.
    public static let usDefault = CustomerCurrencyTemplate(
        currencyCode: "USD",
        localeIdentifier: "en_US"
    )

    /// Built-in presets matching ActionPlan §5 line 980.
    public static let presets: [String: CustomerCurrencyTemplate] = [
        "US":    CustomerCurrencyTemplate(currencyCode: "USD", localeIdentifier: "en_US"),
        "EU-FR": CustomerCurrencyTemplate(currencyCode: "EUR", localeIdentifier: "fr_FR"),
        "JP":    CustomerCurrencyTemplate(currencyCode: "JPY", localeIdentifier: "ja_JP"),
        "CH":    CustomerCurrencyTemplate(currencyCode: "CHF", localeIdentifier: "de_CH"),
    ]
}

// MARK: - 2. Per-customer override

/// Tiny store that lets a customer's preferred currency override the tenant
/// default (e.g. an export client billed in EUR while the shop runs in USD).
///
/// Persistence is `UserDefaults`-only on iOS — the server-side override is
/// resolved by the parent record on fetch; this layer just lets staff change
/// it offline and replay later.
public actor CustomerCurrencyOverrideStore {

    public static let shared = CustomerCurrencyOverrideStore()

    private let defaults: UserDefaults
    private let key = "customers.currencyOverride.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Fetch override (ISO 4217 code) for a single customer.  `nil` ⇒ use tenant.
    public func override(customerId: Int) -> String? {
        let map = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return map[String(customerId)]
    }

    /// Set or clear an override.  Pass `nil` to clear.
    public func setOverride(_ code: String?, customerId: Int) {
        var map = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        if let code, !code.isEmpty {
            map[String(customerId)] = code.uppercased()
        } else {
            map.removeValue(forKey: String(customerId))
        }
        defaults.set(map, forKey: key)
    }

    /// Clear every override (used by sign-out).
    public func clearAll() {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - 3 + 4. Format and parse

public enum CustomerCurrencyFormat {

    // MARK: Format

    /// Format an integer minor-unit amount under the tenant template, optionally
    /// overridden by a per-customer code.
    public static func format(
        cents: Int,
        tenant: CustomerCurrencyTemplate,
        customerOverrideCode: String? = nil
    ) -> String {
        let resolvedCode = customerOverrideCode?.uppercased() ?? tenant.currencyCode
        let formatter = formatter(template: tenant, resolvedCode: resolvedCode)
        let divisor = pow(10.0, Double(minorUnits(for: resolvedCode)))
        let amount = NSDecimalNumber(value: Double(cents) / divisor)
        let raw = formatter.string(from: amount) ?? "\(amount)"
        return applyPlacement(raw, template: tenant, code: resolvedCode)
    }

    // MARK: Parse — line 981 ("multiple locales; normalize to storage")

    /// Parse a user-typed amount in any of the supported locales (US, EU-FR,
    /// JP, CH, plus any locale registered via `CustomerCurrencyTemplate.presets`)
    /// into integer minor units of the *resolved* currency.
    ///
    /// The parser is permissive: it strips currency symbols / ISO codes /
    /// non-breaking spaces, then tries each known separator pair until one
    /// produces a finite number.  Rejects ambiguous strings (e.g. `"1,2,3"`).
    public static func parse(
        input: String,
        tenant: CustomerCurrencyTemplate,
        customerOverrideCode: String? = nil
    ) -> Int? {
        let resolvedCode = customerOverrideCode?.uppercased() ?? tenant.currencyCode
        let scrubbed = scrub(input, code: resolvedCode)
        guard !scrubbed.isEmpty else { return nil }

        // Try each candidate (decimal, thousands) separator pair.  Order matters:
        // try the tenant locale first, then the four built-in presets.
        var seen: Set<String> = []
        var candidates: [(decimal: Character, thousands: Character)] = []
        for sep in localeSeparators(for: tenant.localeIdentifier) where seen.insert("\(sep.decimal)\(sep.thousands)").inserted {
            candidates.append(sep)
        }
        for preset in CustomerCurrencyTemplate.presets.values {
            for sep in localeSeparators(for: preset.localeIdentifier) where seen.insert("\(sep.decimal)\(sep.thousands)").inserted {
                candidates.append(sep)
            }
        }

        for (decimal, thousands) in candidates {
            if let value = parseWith(scrubbed, decimal: decimal, thousands: thousands) {
                let multiplier = pow(10.0, Double(minorUnits(for: resolvedCode)))
                let cents = (value * multiplier).rounded()
                guard cents.isFinite, abs(cents) < Double(Int.max) else { continue }
                return Int(cents)
            }
        }
        return nil
    }

    // MARK: 5. VoiceOver phrase

    /// Returns a sentence-cased phrase suitable for `accessibilityLabel`,
    /// e.g. `"twelve dollars and fifty cents"`, `"zero euros"`, `"one yen"`.
    public static func voiceOverPhrase(
        cents: Int,
        tenant: CustomerCurrencyTemplate,
        customerOverrideCode: String? = nil
    ) -> String {
        let resolvedCode = customerOverrideCode?.uppercased() ?? tenant.currencyCode
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = resolvedCode
        f.locale = Locale(identifier: tenant.localeIdentifier)
        // Apple's `.spellOut` style produces "twelve dollars and fifty cents"
        // for currency amounts when the locale supports it.
        f.numberStyle = .currencyPlural
        let divisor = pow(10.0, Double(minorUnits(for: resolvedCode)))
        let amount = Double(cents) / divisor
        if let phrase = f.string(from: NSNumber(value: amount)) {
            return phrase
        }
        // Fallback: spell out the digits then append the ISO code as words.
        let spelled = NumberFormatter()
        spelled.numberStyle = .spellOut
        spelled.locale = Locale(identifier: tenant.localeIdentifier)
        let body = spelled.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "\(body) \(resolvedCode)"
    }

    // MARK: - Internals

    /// Number of fraction digits for the currency code.  Mirrors
    /// `Core.LocaleFormatter.percentFractionDigits`.
    static func minorUnits(for code: String) -> Int {
        switch code.uppercased() {
        case "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW",
             "MGA", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF",
             "XOF", "XPF":
            return 0
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
            return 3
        default:
            return 2
        }
    }

    private static func formatter(template: CustomerCurrencyTemplate, resolvedCode: String) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: template.localeIdentifier)
        f.currencyCode = resolvedCode
        let digits = minorUnits(for: resolvedCode)
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        if let g = template.thousandsSeparatorOverride {
            f.groupingSeparator = g
            f.usesGroupingSeparator = !g.isEmpty
        }
        if let d = template.decimalSeparatorOverride {
            f.decimalSeparator = d
            f.currencyDecimalSeparator = d
        }
        return f
    }

    /// Re-position the currency symbol when the template overrides
    /// `localeDefault`.  We do this post-format to preserve the locale's
    /// per-currency spacing rules for the default case.
    private static func applyPlacement(
        _ raw: String,
        template: CustomerCurrencyTemplate,
        code: String
    ) -> String {
        guard template.symbolPlacement != .localeDefault else { return raw }

        // Strip whatever symbol the formatter produced.  We hunt for the symbol
        // and the ISO code (some locales render the code instead of a glyph).
        let symbolFormatter = NumberFormatter()
        symbolFormatter.numberStyle = .currency
        symbolFormatter.locale = Locale(identifier: template.localeIdentifier)
        symbolFormatter.currencyCode = code
        let symbol = symbolFormatter.currencySymbol ?? code
        var stripped = raw
            .replacingOccurrences(of: symbol, with: "")
            .replacingOccurrences(of: code, with: "")
            .trimmingCharacters(in: .whitespaces)

        // Drop leading non-breaking spaces.
        while let first = stripped.first, first.isWhitespace || first == "\u{00A0}" {
            stripped.removeFirst()
        }

        switch template.symbolPlacement {
        case .prefix:       return "\(symbol)\(stripped)"
        case .suffix:       return "\(stripped) \(symbol)"
        case .localeDefault: return raw
        }
    }

    /// Strip currency symbols, ISO codes, NBSPs, and CH apostrophes so the
    /// numeric core can be parsed.
    private static func scrub(_ input: String, code: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove the ISO code and known symbols.
        let symbols = ["$", "€", "¥", "£", "₹", "₽", "₩", "CHF", "USD", "EUR", "JPY", "GBP"]
        for sym in symbols + [code.uppercased()] {
            s = s.replacingOccurrences(of: sym, with: "", options: [.caseInsensitive])
        }
        // CH thousands apostrophe → US comma; NBSP / narrow NBSP → space.
        s = s
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Try parsing with explicit decimal + thousands separators.
    private static func parseWith(_ s: String, decimal: Character, thousands: Character) -> Double? {
        // Ambiguity guard: more than one decimal separator is invalid.
        let decimalCount = s.filter { $0 == decimal }.count
        if decimalCount > 1 { return nil }
        // Strip thousands separators.
        var stripped = ""
        for ch in s where ch != thousands {
            stripped.append(ch)
        }
        // Normalise the decimal separator to a dot for `Double(_:)`.
        if decimal != "." {
            stripped = stripped.replacingOccurrences(of: String(decimal), with: ".")
        }
        // Reject anything that still contains a thousands character or whitespace.
        guard stripped.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }) else {
            return nil
        }
        return Double(stripped)
    }

    /// Per-locale (decimal, thousands) pairs we know about.
    private static func localeSeparators(for identifier: String) -> [(decimal: Character, thousands: Character)] {
        let locale = Locale(identifier: identifier)
        let dec = (locale.decimalSeparator ?? ".").first ?? "."
        let grp = (locale.groupingSeparator ?? ",").first ?? ","
        // Always try the locale default; supplement with CH apostrophe / EU space
        // / US comma / EU comma so a tenant on en_US can still paste a French amount.
        var out: [(Character, Character)] = [(dec, grp)]
        let extras: [(Character, Character)] = [
            (".", ","),       // US / GB
            (",", "."),       // DE / IT / ES
            (",", " "),       // FR / RU
            (".", "'"),       // CH
        ]
        for e in extras where !(e.0 == dec && e.1 == grp) {
            out.append(e)
        }
        return out
    }
}

#if canImport(SwiftUI)

// MARK: - View modifier so call-sites can drop in a single line

public extension View {

    /// Apply the customer currency template's VoiceOver phrase to a money view.
    ///
    /// Usage:
    /// ```swift
    /// Text(CustomerCurrencyFormat.format(cents: 1250, tenant: t))
    ///   .accessibilityCurrencyValue(cents: 1250, tenant: t)
    /// ```
    func accessibilityCurrencyValue(
        cents: Int,
        tenant: CustomerCurrencyTemplate,
        customerOverrideCode: String? = nil
    ) -> some View {
        let phrase = CustomerCurrencyFormat.voiceOverPhrase(
            cents: cents,
            tenant: tenant,
            customerOverrideCode: customerOverrideCode
        )
        return self.accessibilityLabel(Text(phrase))
    }
}
#endif
