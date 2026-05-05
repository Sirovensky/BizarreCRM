import Foundation

// MARK: - WeightPriceCalculator
//
// §17 Scale: "Rate-by-weight pricing rule ('$/lb') with auto-computed total"
//
// Stateless calculator. Inject the tenant's preferred unit and rate-per-unit.
// POS calls `total(for:)` when an item's pricing method is `.byWeight`.

/// Computes a line-item total for a weighed product.
///
/// Example ($/lb pricing):
/// ```swift
/// let calc = WeightPriceCalculator(ratePerUnit: 3.99, unit: .pounds)
/// let weight = Weight(grams: 227)     // ≈ 0.5 lb
/// let total = calc.total(for: weight) // ≈ $1.995 → 199 cents
/// ```
public struct WeightPriceCalculator: Sendable {

    // MARK: - Configuration

    /// Price per unit (e.g. $3.99 per pound).
    public let ratePerUnit: Decimal

    /// The unit that `ratePerUnit` is denominated in.
    public let unit: WeightUnit

    // MARK: - Init

    public init(ratePerUnit: Decimal, unit: WeightUnit) {
        self.ratePerUnit = ratePerUnit
        self.unit = unit
    }

    // MARK: - Calculation

    /// Returns the total price in **fractional dollars** (Decimal, 4 d.p.) for a given weight.
    ///
    /// Callers should round to 2 d.p. for display; use `totalCents(for:)` for integer cent storage.
    public func total(for weight: Weight) -> Decimal {
        let unitValue = Decimal(unit.unitValue(forGrams: weight.grams))
        return unitValue * ratePerUnit
    }

    /// Returns the total in **cents** (rounded half-up), suitable for server storage.
    public func totalCents(for weight: Weight) -> Int {
        let dollars = total(for: weight)
        // Multiply by 100 and round half-up.
        var rounded = Decimal()
        var source = dollars * 100
        NSDecimalRound(&rounded, &source, 0, .plain)
        return (rounded as NSDecimalNumber).intValue
    }

    // MARK: - Display

    /// Human-readable summary: "3.5 lb × $2.99/lb = $10.47"
    public func lineItemDescription(for weight: Weight) -> String {
        let qty = unit.formatted(weight)
        let rate = String(format: "$%.2f/\(unit.shortLabel)", (ratePerUnit as NSDecimalNumber).doubleValue)
        let cents = totalCents(for: weight)
        let totalStr = String(format: "$%.2f", Double(cents) / 100.0)
        return "\(qty) × \(rate) = \(totalStr)"
    }
}

// MARK: - WeightPricingRule

/// A persisted pricing rule attached to an inventory item.
///
/// Stored in GRDB as JSON on the item's `pricing_json` column.
public struct WeightPricingRule: Codable, Sendable, Hashable {

    /// Rate per unit (stored as string to preserve decimal precision).
    public let rateString: String
    /// Unit system this rate applies to.
    public let unit: WeightUnit

    public init(ratePerUnit: Decimal, unit: WeightUnit) {
        self.rateString = "\(ratePerUnit)"
        self.unit = unit
    }

    // MARK: - Derived

    public var ratePerUnit: Decimal {
        Decimal(string: rateString) ?? .zero
    }

    public func calculator() -> WeightPriceCalculator {
        WeightPriceCalculator(ratePerUnit: ratePerUnit, unit: unit)
    }
}
