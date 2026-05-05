import Foundation
import Networking

// MARK: - InvoiceSummary

/// Lightweight invoice record used for client-side LTV calculation.
/// Populated from `CustomerAnalytics` or a future invoices-per-customer endpoint.
public struct InvoiceSummary: Sendable, Equatable {
    /// Invoice total in dollars (always non-negative).
    public let totalDollars: Double
    /// ISO-8601 date the invoice was issued.
    public let issuedAt: String?

    public init(totalDollars: Double, issuedAt: String? = nil) {
        self.totalDollars = max(0, totalDollars)
        self.issuedAt     = issuedAt
    }

    /// Convenience: construct from cents integer.
    public init(totalCents: Int64, issuedAt: String? = nil) {
        self.init(totalDollars: Double(totalCents) / 100.0, issuedAt: issuedAt)
    }
}

// MARK: - CustomerLTVResult

/// Lifetime-value computation output.
///
/// ## Computation
///
/// 1. If the server has already stored `lifetime_value_cents` on `CustomerDetail`
///    that value is used directly (server is source of truth).
/// 2. Otherwise `lifetimeDollars` is summed from an array of `InvoiceSummary`.
/// 3. `CustomerAnalytics.lifetimeValue` (in dollars) is accepted as a
///    secondary server-provided source.
///
/// ## Tier assignment
/// Delegates to the existing `LTVCalculator` / `LTVThresholds` types:
///   - bronze   < $500
///   - silver   $500 – $1 499.99
///   - gold     $1 500 – $4 999.99
///   - platinum ≥ $5 000
public struct CustomerLTVResult: Sendable, Equatable {
    /// LTV in dollars (rounded to two decimal places).
    public let lifetimeDollars: Double
    /// Tier classification.
    public let tier: LTVTier
    /// Number of invoices included in the sum (0 when calculated from server totals).
    public let invoiceCount: Int

    public init(lifetimeDollars: Double, tier: LTVTier, invoiceCount: Int) {
        self.lifetimeDollars = round(lifetimeDollars * 100) / 100
        self.tier            = tier
        self.invoiceCount    = invoiceCount
    }

    // MARK: - Factories

    /// Compute from a detail object (uses server `ltv_cents` or `totalSpentCents`).
    public static func from(detail: CustomerDetail, thresholds: LTVThresholds = .default) -> CustomerLTVResult? {
        if let cents = detail.ltvCents, cents > 0 {
            let dollars = Double(cents) / 100.0
            return CustomerLTVResult(
                lifetimeDollars: dollars,
                tier: LTVCalculator.tier(forCentsInt64: cents, thresholds: thresholds),
                invoiceCount: 0
            )
        }
        if let cents = detail.totalSpentCents, cents > 0 {
            let dollars = Double(cents) / 100.0
            return CustomerLTVResult(
                lifetimeDollars: dollars,
                tier: LTVCalculator.tier(forCentsInt64: cents, thresholds: thresholds),
                invoiceCount: 0
            )
        }
        return nil
    }

    /// Compute from a `CustomerAnalytics` snapshot.
    public static func from(analytics: CustomerAnalytics, thresholds: LTVThresholds = .default) -> CustomerLTVResult {
        let dollars = analytics.lifetimeValue
        return CustomerLTVResult(
            lifetimeDollars: dollars,
            tier: LTVCalculator.tier(forDollars: dollars, thresholds: thresholds),
            invoiceCount: analytics.totalTickets
        )
    }

    /// Compute from an explicit array of invoice summaries (empty → bronze, $0).
    public static func from(invoices: [InvoiceSummary], thresholds: LTVThresholds = .default) -> CustomerLTVResult {
        let total = invoices.reduce(0.0) { $0 + $1.totalDollars }
        return CustomerLTVResult(
            lifetimeDollars: total,
            tier: LTVCalculator.tier(forDollars: total, thresholds: thresholds),
            invoiceCount: invoices.count
        )
    }

    // MARK: - Formatted display

    /// Currency-formatted LTV string (e.g. "$1,249.50").
    public var formatted: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = lifetimeDollars.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return f.string(from: NSNumber(value: lifetimeDollars)) ?? "$\(Int(lifetimeDollars))"
    }
}
