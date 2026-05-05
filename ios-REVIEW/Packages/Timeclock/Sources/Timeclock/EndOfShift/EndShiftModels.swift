import Foundation

// MARK: - CashDenomination

/// A US-currency denomination with a count entered by the cashier.
public struct CashDenomination: Identifiable, Equatable, Sendable {
    public let id: Int         // cents value
    public let label: String
    public var count: Int

    public init(id: Int, label: String, count: Int = 0) {
        self.id    = id
        self.label = label
        self.count = count
    }

    /// Computed total in cents.
    public var totalCents: Int { id * count }

    /// Canonical US denominations from largest to smallest.
    public static let defaultDenominations: [CashDenomination] = [
        CashDenomination(id: 10_000, label: "$100"),
        CashDenomination(id:  5_000, label: "$50"),
        CashDenomination(id:  2_000, label: "$20"),
        CashDenomination(id:  1_000, label: "$10"),
        CashDenomination(id:    500, label: "$5"),
        CashDenomination(id:    200, label: "$2"),
        CashDenomination(id:    100, label: "$1"),
        CashDenomination(id:     25, label: "25¢"),
        CashDenomination(id:     10, label: "10¢"),
        CashDenomination(id:      5, label: "5¢"),
        CashDenomination(id:      1, label: "1¢"),
    ]
}

// MARK: - EndShiftSummary

/// Result of a completed cashier shift closure.
///
/// Sovereignty: all fields are computed on-device from server-sourced data.
/// Nothing leaves the tenant server.
public struct EndShiftSummary: Sendable, Equatable {
    public let salesCount: Int
    public let grossCents: Int
    public let tipsCents: Int
    public let cashExpectedCents: Int
    public let cashCountedCents: Int
    public let itemsSold: Int
    public let voidCount: Int

    public init(
        salesCount: Int,
        grossCents: Int,
        tipsCents: Int,
        cashExpectedCents: Int,
        cashCountedCents: Int,
        itemsSold: Int,
        voidCount: Int
    ) {
        self.salesCount        = salesCount
        self.grossCents        = grossCents
        self.tipsCents         = tipsCents
        self.cashExpectedCents = cashExpectedCents
        self.cashCountedCents  = cashCountedCents
        self.itemsSold         = itemsSold
        self.voidCount         = voidCount
    }

    /// Over (positive) or short (negative) in cents.
    public var overShortCents: Int { cashCountedCents - cashExpectedCents }

    public var overShortLabel: String {
        let abs = overShortCents < 0 ? -overShortCents : overShortCents
        let dollars = String(format: "$%.2f", Double(abs) / 100)
        return overShortCents >= 0 ? "+\(dollars) (over)" : "-\(dollars) (short)"
    }

    /// True when the absolute over/short exceeds $2.00 — manager sign-off required.
    public var requiresManagerSignOff: Bool { abs(overShortCents) > 200 }

    public func formatted(cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }
}

// MARK: - OverShortCalculator

/// Pure engine. Testable without any SwiftUI or network.
///
/// - Parameter denominations: cashier-entered counts (from `CashDenomination.count`).
/// - Parameter expectedCents: server-reported expected cash from sales.
/// - Returns: (counted, overShort) in cents.
public struct OverShortCalculator: Sendable {
    public init() {}

    public func compute(
        denominations: [CashDenomination],
        expectedCents: Int
    ) -> (countedCents: Int, overShortCents: Int) {
        let counted = denominations.reduce(0) { $0 + $1.totalCents }
        return (counted, counted - expectedCents)
    }
}

// MARK: - EndShiftRequest / Response

/// POST /api/v1/timeclock/shifts/close — cashier submits shift-close.
public struct EndShiftRequest: Encodable, Sendable {
    public let cashCountedCents: Int
    public let overShortCents: Int
    public let overShortReason: String?
    public let managerPinVerified: Bool

    public init(
        cashCountedCents: Int,
        overShortCents: Int,
        overShortReason: String?,
        managerPinVerified: Bool
    ) {
        self.cashCountedCents  = cashCountedCents
        self.overShortCents    = overShortCents
        self.overShortReason   = overShortReason
        self.managerPinVerified = managerPinVerified
    }

    enum CodingKeys: String, CodingKey {
        case cashCountedCents   = "cash_counted_cents"
        case overShortCents     = "over_short_cents"
        case overShortReason    = "over_short_reason"
        case managerPinVerified = "manager_pin_verified"
    }
}

public struct EndShiftResponse: Decodable, Sendable {
    public let shiftId: Int64
    public let zReportId: Int64?

    enum CodingKeys: String, CodingKey {
        case shiftId    = "shift_id"
        case zReportId  = "z_report_id"
    }
}

// MARK: - ShiftHandoffRequest

/// Data transferred to the next cashier's opening count.
public struct ShiftHandoffRequest: Encodable, Sendable {
    public let openingCashCents: Int

    public init(openingCashCents: Int) {
        self.openingCashCents = openingCashCents
    }

    enum CodingKeys: String, CodingKey {
        case openingCashCents = "opening_cash_cents"
    }
}
