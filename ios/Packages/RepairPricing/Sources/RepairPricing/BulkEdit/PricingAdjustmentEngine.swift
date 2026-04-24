import Foundation

// MARK: - §43 Bulk Edit — Pricing Adjustment Engine

/// The kind of adjustment to apply to a set of prices.
public enum PricingAdjustmentKind: String, Sendable, Equatable, CaseIterable {
    /// Multiply each price by (1 + pct/100). E.g. +10 means +10%.
    case percentage
    /// Add a flat dollar amount to each price. May be negative (discount).
    case fixed
}

/// A rule describing how prices should be adjusted.
public struct PricingAdjustmentRule: Sendable, Equatable {
    /// Whether the value is a percentage or a fixed-dollar amount.
    public let kind: PricingAdjustmentKind
    /// The delta to apply.
    ///  - For `.percentage`: value 10 means +10%, −5 means −5%.
    ///  - For `.fixed`: value 5.00 means +$5, −2.50 means −$2.50.
    public let value: Double
    /// Whether final prices should be rounded to 2 decimal places.
    public let roundToCents: Bool

    /// Maximum allowed percentage (server caps at ±50%).
    public static let maxPct: Double = 50
    /// Maximum allowed fixed-dollar delta (mirrors server MAX_REPAIR_PRICE).
    public static let maxFixed: Double = 100_000

    public init(kind: PricingAdjustmentKind, value: Double, roundToCents: Bool = true) {
        self.kind = kind
        self.value = value
        self.roundToCents = roundToCents
    }
}

/// Validation error for a `PricingAdjustmentRule`.
public enum PricingAdjustmentRuleError: Error, LocalizedError, Sendable, Equatable {
    case valueIsNaN
    case valueIsInfinite
    case percentageOutOfRange     // |pct| > 50
    case fixedOutOfRange          // |fixed| > 100_000
    case zeroValueNotAllowed

    public var errorDescription: String? {
        switch self {
        case .valueIsNaN:            return "Adjustment value must be a number."
        case .valueIsInfinite:       return "Adjustment value must be finite."
        case .percentageOutOfRange:  return "Percentage must be between −50% and +50%."
        case .fixedOutOfRange:       return "Fixed amount must be between −\(Int(PricingAdjustmentRule.maxFixed)) and +\(Int(PricingAdjustmentRule.maxFixed))."
        case .zeroValueNotAllowed:   return "Adjustment value must be non-zero."
        }
    }
}

/// A single input price item fed to the engine.
public struct PriceInputItem: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let name: String
    /// Labor price in dollars (not cents) — mirrors `repair_prices.labor_price`.
    public let laborPrice: Double

    public init(id: Int64, name: String, laborPrice: Double) {
        self.id = id
        self.name = name
        self.laborPrice = laborPrice
    }
}

/// The computed result for one price item after applying a rule.
public struct PriceAdjustmentResult: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let name: String
    public let originalPrice: Double
    public let newPrice: Double

    /// The dollar change (positive = increase, negative = decrease).
    public var delta: Double { newPrice - originalPrice }

    public init(id: Int64, name: String, originalPrice: Double, newPrice: Double) {
        self.id = id
        self.name = name
        self.originalPrice = originalPrice
        self.newPrice = newPrice
    }
}

// MARK: - Engine (pure functions)

/// Pure, side-effect-free pricing adjustment engine.
///
/// All functions are `static` so callers can use them directly without
/// instantiation. No state is held — this is a pure computation module.
public enum PricingAdjustmentEngine {

    // MARK: - Validation

    /// Validates a `PricingAdjustmentRule`, returning the first error found or `nil`.
    public static func validate(rule: PricingAdjustmentRule) -> PricingAdjustmentRuleError? {
        guard !rule.value.isNaN else { return .valueIsNaN }
        guard rule.value.isFinite else { return .valueIsInfinite }
        guard rule.value != 0 else { return .zeroValueNotAllowed }
        switch rule.kind {
        case .percentage:
            guard abs(rule.value) <= PricingAdjustmentRule.maxPct else { return .percentageOutOfRange }
        case .fixed:
            guard abs(rule.value) <= PricingAdjustmentRule.maxFixed else { return .fixedOutOfRange }
        }
        return nil
    }

    // MARK: - Single-price computation

    /// Applies `rule` to a single `basePrice` and returns the new price.
    ///
    /// The resulting price is clamped to `[0, MAX_REPAIR_PRICE]` so that
    /// negative discounts cannot drive a price below zero.
    ///
    /// - Parameters:
    ///   - basePrice: The original price in dollars.
    ///   - rule: A **pre-validated** adjustment rule.
    /// - Returns: The adjusted price.
    public static func apply(basePrice: Double, rule: PricingAdjustmentRule) -> Double {
        var result: Double
        switch rule.kind {
        case .percentage:
            result = basePrice * (1.0 + rule.value / 100.0)
        case .fixed:
            result = basePrice + rule.value
        }
        // Clamp to valid range
        result = max(0, min(PricingAdjustmentRule.maxFixed, result))
        if rule.roundToCents {
            result = (result * 100).rounded() / 100
        }
        return result
    }

    // MARK: - Batch computation

    /// Computes `PriceAdjustmentResult`s for every item in `items` using `rule`.
    ///
    /// Returns an empty array if the rule fails validation (caller should
    /// validate first with `validate(rule:)` before calling this).
    ///
    /// - Parameters:
    ///   - items: Price items to adjust.
    ///   - rule: A pre-validated adjustment rule.
    /// - Returns: One result per input item, preserving order.
    public static func preview(
        items: [PriceInputItem],
        rule: PricingAdjustmentRule
    ) -> [PriceAdjustmentResult] {
        items.map { item in
            PriceAdjustmentResult(
                id: item.id,
                name: item.name,
                originalPrice: item.laborPrice,
                newPrice: apply(basePrice: item.laborPrice, rule: rule)
            )
        }
    }

    // MARK: - CSV parsing

    /// Parses a CSV string representing a service price catalog.
    ///
    /// Expected header row (case-insensitive):
    /// ```
    /// name,slug,category,labor_price
    /// ```
    /// Additional columns are silently ignored.
    /// Rows with a missing `name` or an invalid `labor_price` are skipped and
    /// recorded in the returned error list so the caller can surface them.
    ///
    /// - Parameter csv: Raw CSV text (UTF-8).
    /// - Returns: A tuple of successfully parsed items and row-level parse errors.
    public static func parseServiceCatalogCSV(
        _ csv: String
    ) -> (items: [ServiceCatalogCSVRow], errors: [CSVParseError]) {
        var rows: [ServiceCatalogCSVRow] = []
        var parseErrors: [CSVParseError] = []

        let lines = csv.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return ([], []) }

        // Determine column indices from header
        let headerCols = lines[0].split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        let idxName        = headerCols.firstIndex(of: "name")
        let idxSlug        = headerCols.firstIndex(of: "slug")
        let idxCategory    = headerCols.firstIndex(of: "category")
        let idxLaborPrice  = headerCols.firstIndex(of: "labor_price")

        guard idxName != nil || idxLaborPrice != nil else {
            parseErrors.append(CSVParseError(row: 1, message: "Header must contain at least 'name' and 'labor_price' columns."))
            return ([], parseErrors)
        }

        for (lineOffset, line) in lines.dropFirst().enumerated() {
            let rowNumber = lineOffset + 2 // 1-based, header is row 1
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            func col(_ idx: Int?) -> String? {
                guard let i = idx, i < cols.count else { return nil }
                let s = cols[i]
                return s.isEmpty ? nil : s
            }

            let name = col(idxName) ?? ""
            guard !name.isEmpty else {
                parseErrors.append(CSVParseError(row: rowNumber, message: "Missing 'name' — row skipped."))
                continue
            }

            let rawPrice = col(idxLaborPrice) ?? ""
            guard let price = Double(rawPrice), price >= 0, price.isFinite else {
                parseErrors.append(CSVParseError(row: rowNumber, message: "Invalid labor_price '\(rawPrice)' for '\(name)' — row skipped."))
                continue
            }

            rows.append(ServiceCatalogCSVRow(
                name: name,
                slug: col(idxSlug),
                category: col(idxCategory),
                laborPrice: price
            ))
        }

        return (rows, parseErrors)
    }
}

// MARK: - CSV Supporting Types

/// One successfully-parsed row from a service catalog CSV.
public struct ServiceCatalogCSVRow: Sendable, Equatable, Identifiable {
    public var id: String { slug ?? name }
    public let name: String
    public let slug: String?
    public let category: String?
    /// Labor price in dollars (not cents).
    public let laborPrice: Double

    public init(name: String, slug: String? = nil, category: String? = nil, laborPrice: Double) {
        self.name = name
        self.slug = slug
        self.category = category
        self.laborPrice = laborPrice
    }
}

/// A row-level error encountered during CSV parsing.
public struct CSVParseError: Sendable, Equatable, LocalizedError {
    /// 1-based row number in the source file.
    public let row: Int
    public let message: String

    public init(row: Int, message: String) {
        self.row = row
        self.message = message
    }

    public var errorDescription: String? { "Row \(row): \(message)" }
}
