import Foundation
import Networking

// MARK: - FinancialDashboardModels
//
// View-layer models for §59 Financial Dashboard (owner home screen lens).
//
// Grounded against:
//   packages/server/src/routes/ownerPl.routes.ts
//   GET /api/v1/owner-pl/summary?from=YYYY-MM-DD&to=YYYY-MM-DD&rollup=day|week|month
//
// Wire DTOs (OwnerPLSummaryWire etc.) live in Networking/DashboardEndpoints.swift
// so they can be decoded without a circular dependency. This file converts
// those wire types into human-readable Dollar-denominated view models.
//
// NOTE: §15 Reports owns the full OwnerPLReport screen. This file only
// declares the Dashboard-lens subset for the owner home screen.

// MARK: - View-layer models (dollars, not cents)

/// Human-readable revenue for the KPI row.
public struct FinancialRevenue: Sendable, Equatable {
    public let gross: Double
    public let net: Double
    public let refunds: Double
    public let discounts: Double

    public init(gross: Double, net: Double, refunds: Double, discounts: Double) {
        self.gross = gross
        self.net = net
        self.refunds = refunds
        self.discounts = discounts
    }

    init(wire: OwnerPLRevenueCentsWire) {
        self.init(
            gross: Double(wire.grossCents) / 100.0,
            net: Double(wire.netCents) / 100.0,
            refunds: Double(wire.refundsCents) / 100.0,
            discounts: Double(wire.discountsCents) / 100.0
        )
    }
}

/// Gross-profit view model.
public struct FinancialGrossProfit: Sendable, Equatable {
    public let value: Double
    public let marginPct: Double

    public init(value: Double, marginPct: Double) {
        self.value = value
        self.marginPct = marginPct
    }

    init(wire: OwnerPLProfitWire) {
        self.init(value: Double(wire.cents) / 100.0, marginPct: wire.marginPct)
    }
}

/// Net-profit view model.
public struct FinancialNetProfit: Sendable, Equatable {
    public let value: Double
    public let marginPct: Double

    public init(value: Double, marginPct: Double) {
        self.value = value
        self.marginPct = marginPct
    }

    init(wire: OwnerPLProfitWire) {
        self.init(value: Double(wire.cents) / 100.0, marginPct: wire.marginPct)
    }
}

/// AR / cash-position card model.
public struct FinancialCashPosition: Sendable, Equatable {
    public let outstanding: Double
    public let overdue: Double
    /// True when the server truncated the AR scan at 10 000 rows —
    /// values are approximate. Show a disclosure label in the UI.
    public let isApproximate: Bool

    public init(outstanding: Double, overdue: Double, isApproximate: Bool) {
        self.outstanding = outstanding
        self.overdue = overdue
        self.isApproximate = isApproximate
    }

    init(wire: OwnerPLARWire) {
        self.init(
            outstanding: Double(wire.outstandingCents) / 100.0,
            overdue: Double(wire.overdueCents) / 100.0,
            isApproximate: wire.truncated
        )
    }
}

/// A single row in the top-customers list.
public struct FinancialTopCustomer: Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let revenue: Double

    public init(id: Int, name: String, revenue: Double) {
        self.id = id
        self.name = name
        self.revenue = revenue
    }

    init(wire: OwnerPLTopCustomerWire) {
        self.init(
            id: wire.customerId,
            name: wire.name.isEmpty ? "Unknown" : wire.name,
            revenue: Double(wire.revenueCents) / 100.0
        )
    }
}

/// The assembled view snapshot passed to `FinancialDashboardView`.
public struct FinancialDashboardSnapshot: Sendable, Equatable {
    public let periodFrom: String
    public let periodTo: String
    public let periodDays: Int
    public let revenue: FinancialRevenue
    public let grossProfit: FinancialGrossProfit
    public let netProfit: FinancialNetProfit
    public let cashPosition: FinancialCashPosition
    public let topCustomers: [FinancialTopCustomer]

    public init(
        periodFrom: String,
        periodTo: String,
        periodDays: Int,
        revenue: FinancialRevenue,
        grossProfit: FinancialGrossProfit,
        netProfit: FinancialNetProfit,
        cashPosition: FinancialCashPosition,
        topCustomers: [FinancialTopCustomer]
    ) {
        self.periodFrom = periodFrom
        self.periodTo = periodTo
        self.periodDays = periodDays
        self.revenue = revenue
        self.grossProfit = grossProfit
        self.netProfit = netProfit
        self.cashPosition = cashPosition
        self.topCustomers = topCustomers
    }

    /// Convert wire DTO → view-layer snapshot (immutable; returns new value).
    public static func from(wire: OwnerPLSummaryWire) -> FinancialDashboardSnapshot {
        FinancialDashboardSnapshot(
            periodFrom: wire.period.from,
            periodTo: wire.period.to,
            periodDays: wire.period.days,
            revenue: FinancialRevenue(wire: wire.revenue),
            grossProfit: FinancialGrossProfit(wire: wire.grossProfit),
            netProfit: FinancialNetProfit(wire: wire.netProfit),
            cashPosition: FinancialCashPosition(wire: wire.ar),
            topCustomers: wire.topCustomers.map { FinancialTopCustomer(wire: $0) }
        )
    }
}

// MARK: - Query parameters

/// Date range + rollup for the owner-PL summary request.
public struct FinancialQueryParams: Sendable, Equatable {
    public let from: String
    public let to: String
    public let rollup: FinancialRollup

    public init(from: String, to: String, rollup: FinancialRollup = .day) {
        self.from = from
        self.to = to
        self.rollup = rollup
    }

    /// Default: last 30 days, daily rollup.
    public static var defaultLast30Days: FinancialQueryParams {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -30, to: today) else {
            return FinancialQueryParams(from: "", to: "", rollup: .day)
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        return FinancialQueryParams(from: fmt.string(from: start), to: fmt.string(from: today))
    }
}

public enum FinancialRollup: String, Sendable, CaseIterable {
    case day, week, month
}
