import Foundation

// §7 line 1283 — Jurisdiction limits: some jurisdictions cap late fees by law.
//
// Pure data + validator. The library does NOT claim to be legal advice; it
// surfaces commonly-cited statutory caps for a handful of US jurisdictions
// so admin UIs can warn the operator if the configured policy exceeds the
// statutory cap. Tenant policy still wins on the wire — server is authoritative.

/// Jurisdiction-specific cap on late fees.
public struct LateFeeJurisdictionLimit: Sendable, Equatable, Hashable {
    /// ISO-style region code: e.g. "US-CA", "US-NY", "US-TX".
    public let regionCode: String
    /// Human-readable name (e.g. "California").
    public let displayName: String
    /// Statutory maximum percentage of the invoice that may be charged as a
    /// late fee (e.g. 10.0 = 10%). nil = no documented percentage cap.
    public let maxPercentOfInvoice: Double?
    /// Statutory maximum flat fee in cents (nil = no documented flat cap).
    public let maxFlatFeeCents: Cents?
    /// Statutory maximum APR (annualised %) when computed as percent-per-day.
    /// nil = no documented APR cap.
    public let maxAnnualPercentRate: Double?
    /// Source citation for the cap (e.g. "CA Civ. Code § 1671"). For UI display only.
    public let citation: String

    public init(
        regionCode: String,
        displayName: String,
        maxPercentOfInvoice: Double? = nil,
        maxFlatFeeCents: Cents? = nil,
        maxAnnualPercentRate: Double? = nil,
        citation: String
    ) {
        self.regionCode = regionCode
        self.displayName = displayName
        self.maxPercentOfInvoice = maxPercentOfInvoice
        self.maxFlatFeeCents = maxFlatFeeCents
        self.maxAnnualPercentRate = maxAnnualPercentRate
        self.citation = citation
    }
}

/// Built-in lookup of common US jurisdiction caps. Not exhaustive; not legal
/// advice. Used for client-side warning UI only.
public enum LateFeeJurisdictionRegistry {
    public static let all: [LateFeeJurisdictionLimit] = [
        .init(regionCode: "US-CA", displayName: "California",
              maxPercentOfInvoice: 10.0,
              maxAnnualPercentRate: 10.0,
              citation: "CA Civ. Code § 1671 — fee must be a reasonable estimate of damages"),
        .init(regionCode: "US-NY", displayName: "New York",
              maxAnnualPercentRate: 16.0,
              citation: "NY Gen. Oblig. Law § 5-501 (civil usury cap)"),
        .init(regionCode: "US-TX", displayName: "Texas",
              maxAnnualPercentRate: 18.0,
              citation: "TX Fin. Code § 302.001"),
        .init(regionCode: "US-FL", displayName: "Florida",
              maxAnnualPercentRate: 18.0,
              citation: "FL Stat. § 687.03"),
        .init(regionCode: "US-IL", displayName: "Illinois",
              maxAnnualPercentRate: 9.0,
              citation: "815 ILCS 205/4")
    ]

    public static func limit(for regionCode: String) -> LateFeeJurisdictionLimit? {
        all.first { $0.regionCode.caseInsensitiveCompare(regionCode) == .orderedSame }
    }
}

// MARK: - Validator

/// Validates a tenant's `LateFeePolicy` against a jurisdiction cap.
/// Pure — fully testable, no side effects.
public enum LateFeeJurisdictionValidator {

    public struct Warning: Sendable, Equatable {
        public let kind: Kind
        public let message: String

        public enum Kind: String, Sendable, Equatable {
            case flatFeeExceedsCap
            case percentExceedsCap
            case aprExceedsCap
            case maxFeeExceedsCap
        }

        public init(kind: Kind, message: String) {
            self.kind = kind
            self.message = message
        }
    }

    /// Returns warnings, one per violation. Empty array = compliant (per known caps).
    public static func validate(
        policy: LateFeePolicy,
        invoiceTotalCents: Cents,
        limit: LateFeeJurisdictionLimit
    ) -> [Warning] {
        var warnings: [Warning] = []

        if let flat = policy.flatFeeCents,
           let capPctOfInvoice = limit.maxPercentOfInvoice,
           invoiceTotalCents > 0 {
            let pct = (Double(flat) / Double(invoiceTotalCents)) * 100.0
            if pct > capPctOfInvoice {
                warnings.append(.init(
                    kind: .flatFeeExceedsCap,
                    message: "Flat fee is \(String(format: "%.1f", pct))% of invoice — \(limit.displayName) cap is \(String(format: "%.1f", capPctOfInvoice))% (\(limit.citation))."
                ))
            }
        }

        if let pctPerDay = policy.percentPerDay {
            let apr = pctPerDay * 365.0
            if let aprCap = limit.maxAnnualPercentRate, apr > aprCap {
                warnings.append(.init(
                    kind: .aprExceedsCap,
                    message: "Daily \(String(format: "%.4f", pctPerDay))% ≈ \(String(format: "%.1f", apr))% APR — \(limit.displayName) cap is \(String(format: "%.1f", aprCap))% (\(limit.citation))."
                ))
            }
        }

        if let cap = limit.maxFlatFeeCents,
           let max = policy.maxFeeCents,
           max > cap {
            warnings.append(.init(
                kind: .maxFeeExceedsCap,
                message: "Max-fee cap exceeds \(limit.displayName) statutory cap (\(limit.citation))."
            ))
        }

        return warnings
    }
}
