import Foundation

// MARK: - OwnerPLModels
//
// Mirrors GET /api/v1/owner-pl/summary response envelope.
// Server shape confirmed from packages/server/src/routes/ownerPl.routes.ts.
// All monetary values arrive as INTEGER cents (SEC-H34).

// MARK: - OwnerPLSummary

public struct OwnerPLSummary: Decodable, Sendable {
    public let period: PLPeriod
    public let revenue: PLRevenue
    public let cogs: PLCogs
    public let grossProfit: PLProfit
    public let expenses: PLExpenses
    public let netProfit: PLProfit
    public let taxLiability: PLTax
    public let ar: PLAr
    public let inventoryValue: PLInventoryValue
    public let timeSeries: [PLTimeBucket]
    public let topCustomers: [PLTopCustomer]
    public let topServices: [PLTopService]
    /// YoY delta in revenue cents vs same period prior year (nil if unavailable).
    public let yoyRevenueDeltaCents: Int?
    /// YoY delta in net-profit cents vs same period prior year (nil if unavailable).
    public let yoyNetProfitDeltaCents: Int?

    /// Percentage revenue change vs prior year period; nil when prior is unknown.
    public var yoyRevenuePct: Double? {
        guard let delta = yoyRevenueDeltaCents else { return nil }
        let prior = revenue.grossCents - delta
        guard prior != 0 else { return nil }
        return Double(delta) / Double(prior)
    }

    /// Percentage net-profit change vs prior year period; nil when prior is unknown.
    public var yoyNetProfitPct: Double? {
        guard let delta = yoyNetProfitDeltaCents else { return nil }
        let prior = netProfit.cents - delta
        guard prior != 0 else { return nil }
        return Double(delta) / Double(prior)
    }

    enum CodingKeys: String, CodingKey {
        case period
        case revenue
        case cogs
        case grossProfit              = "gross_profit"
        case expenses
        case netProfit                = "net_profit"
        case taxLiability             = "tax_liability"
        case ar
        case inventoryValue           = "inventory_value"
        case timeSeries               = "time_series"
        case topCustomers             = "top_customers"
        case topServices              = "top_services"
        case yoyRevenueDeltaCents     = "yoy_revenue_delta_cents"
        case yoyNetProfitDeltaCents   = "yoy_net_profit_delta_cents"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        period                  = (try? c.decode(PLPeriod.self,           forKey: .period))         ?? PLPeriod()
        revenue                 = (try? c.decode(PLRevenue.self,          forKey: .revenue))        ?? PLRevenue()
        cogs                    = (try? c.decode(PLCogs.self,             forKey: .cogs))           ?? PLCogs()
        grossProfit             = (try? c.decode(PLProfit.self,           forKey: .grossProfit))    ?? PLProfit()
        expenses                = (try? c.decode(PLExpenses.self,         forKey: .expenses))       ?? PLExpenses()
        netProfit               = (try? c.decode(PLProfit.self,           forKey: .netProfit))      ?? PLProfit()
        taxLiability            = (try? c.decode(PLTax.self,              forKey: .taxLiability))   ?? PLTax()
        ar                      = (try? c.decode(PLAr.self,               forKey: .ar))             ?? PLAr()
        inventoryValue          = (try? c.decode(PLInventoryValue.self,   forKey: .inventoryValue)) ?? PLInventoryValue()
        timeSeries              = (try? c.decode([PLTimeBucket].self,     forKey: .timeSeries))     ?? []
        topCustomers            = (try? c.decode([PLTopCustomer].self,    forKey: .topCustomers))   ?? []
        topServices             = (try? c.decode([PLTopService].self,     forKey: .topServices))    ?? []
        yoyRevenueDeltaCents    = try? c.decode(Int.self, forKey: .yoyRevenueDeltaCents)
        yoyNetProfitDeltaCents  = try? c.decode(Int.self, forKey: .yoyNetProfitDeltaCents)
    }
}

// MARK: - PLPeriod

public struct PLPeriod: Decodable, Sendable {
    public let from: String
    public let to: String
    public let days: Int

    enum CodingKeys: String, CodingKey { case from, to, days }

    public init(from: String = "", to: String = "", days: Int = 0) {
        self.from = from; self.to = to; self.days = days
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = (try? c.decode(String.self, forKey: .from)) ?? ""
        to   = (try? c.decode(String.self, forKey: .to))   ?? ""
        days = (try? c.decode(Int.self,    forKey: .days))  ?? 0
    }
}

// MARK: - PLRevenue

public struct PLRevenue: Decodable, Sendable {
    public let grossCents: Int
    public let netCents: Int
    public let refundsCents: Int
    public let discountsCents: Int

    public var grossDollars: Double   { Double(grossCents) / 100.0 }
    public var netDollars: Double     { Double(netCents) / 100.0 }
    public var refundsDollars: Double { Double(refundsCents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case grossCents    = "gross_cents"
        case netCents      = "net_cents"
        case refundsCents  = "refunds_cents"
        case discountsCents = "discounts_cents"
    }
    public init(grossCents: Int = 0, netCents: Int = 0,
                refundsCents: Int = 0, discountsCents: Int = 0) {
        self.grossCents = grossCents; self.netCents = netCents
        self.refundsCents = refundsCents; self.discountsCents = discountsCents
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grossCents     = (try? c.decode(Int.self, forKey: .grossCents))     ?? 0
        netCents       = (try? c.decode(Int.self, forKey: .netCents))       ?? 0
        refundsCents   = (try? c.decode(Int.self, forKey: .refundsCents))   ?? 0
        discountsCents = (try? c.decode(Int.self, forKey: .discountsCents)) ?? 0
    }
}

// MARK: - PLCogs

public struct PLCogs: Decodable, Sendable {
    public let inventoryCents: Int
    public let laborCents: Int
    public var totalCents: Int { inventoryCents + laborCents }
    public var totalDollars: Double { Double(totalCents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case inventoryCents = "inventory_cents"
        case laborCents     = "labor_cents"
    }
    public init(inventoryCents: Int = 0, laborCents: Int = 0) {
        self.inventoryCents = inventoryCents; self.laborCents = laborCents
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inventoryCents = (try? c.decode(Int.self, forKey: .inventoryCents)) ?? 0
        laborCents     = (try? c.decode(Int.self, forKey: .laborCents))     ?? 0
    }
}

// MARK: - PLProfit (shared by gross_profit and net_profit)

public struct PLProfit: Decodable, Sendable {
    public let cents: Int
    public let marginPct: Double
    public var dollars: Double { Double(cents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case cents
        case marginPct = "margin_pct"
    }
    public init(cents: Int = 0, marginPct: Double = 0) {
        self.cents = cents; self.marginPct = marginPct
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cents     = (try? c.decode(Int.self,    forKey: .cents))     ?? 0
        marginPct = (try? c.decode(Double.self, forKey: .marginPct)) ?? 0
    }
}

// MARK: - PLExpenses

public struct PLExpenseCategoryRow: Decodable, Sendable, Identifiable {
    public let category: String
    public let cents: Int
    public var id: String { category }
    public var dollars: Double { Double(cents) / 100.0 }

    enum CodingKeys: String, CodingKey { case category, cents }
    public init(category: String, cents: Int) {
        self.category = category; self.cents = cents
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = (try? c.decode(String.self, forKey: .category)) ?? ""
        cents    = (try? c.decode(Int.self,    forKey: .cents))    ?? 0
    }
}

public struct PLExpenses: Decodable, Sendable {
    public let totalCents: Int
    public let byCategory: [PLExpenseCategoryRow]
    public var totalDollars: Double { Double(totalCents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case totalCents  = "total_cents"
        case byCategory  = "by_category"
    }
    public init(totalCents: Int = 0, byCategory: [PLExpenseCategoryRow] = []) {
        self.totalCents = totalCents; self.byCategory = byCategory
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalCents  = (try? c.decode(Int.self, forKey: .totalCents)) ?? 0
        byCategory  = (try? c.decode([PLExpenseCategoryRow].self, forKey: .byCategory)) ?? []
    }
}

// MARK: - PLTax

public struct PLTax: Decodable, Sendable {
    public let collectedCents: Int
    public let remittedCents: Int
    public let outstandingCents: Int
    public var outstandingDollars: Double { Double(outstandingCents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case collectedCents    = "collected_cents"
        case remittedCents     = "remitted_cents"
        case outstandingCents  = "outstanding_cents"
    }
    public init(collectedCents: Int = 0, remittedCents: Int = 0, outstandingCents: Int = 0) {
        self.collectedCents = collectedCents
        self.remittedCents = remittedCents
        self.outstandingCents = outstandingCents
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collectedCents   = (try? c.decode(Int.self, forKey: .collectedCents))   ?? 0
        remittedCents    = (try? c.decode(Int.self, forKey: .remittedCents))    ?? 0
        outstandingCents = (try? c.decode(Int.self, forKey: .outstandingCents)) ?? 0
    }
}

// MARK: - PLAr

public struct PLAgingBuckets: Decodable, Sendable {
    public let bucket0to30: Int
    public let bucket31to60: Int
    public let bucket61to90: Int
    public let bucket91plus: Int

    enum CodingKeys: String, CodingKey {
        case bucket0to30  = "0_30"
        case bucket31to60 = "31_60"
        case bucket61to90 = "61_90"
        case bucket91plus = "91_plus"
    }
    public init(bucket0to30: Int = 0, bucket31to60: Int = 0,
                bucket61to90: Int = 0, bucket91plus: Int = 0) {
        self.bucket0to30 = bucket0to30; self.bucket31to60 = bucket31to60
        self.bucket61to90 = bucket61to90; self.bucket91plus = bucket91plus
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bucket0to30  = (try? c.decode(Int.self, forKey: .bucket0to30))  ?? 0
        bucket31to60 = (try? c.decode(Int.self, forKey: .bucket31to60)) ?? 0
        bucket61to90 = (try? c.decode(Int.self, forKey: .bucket61to90)) ?? 0
        bucket91plus = (try? c.decode(Int.self, forKey: .bucket91plus)) ?? 0
    }
}

public struct PLAr: Decodable, Sendable {
    public let outstandingCents: Int
    public let overdueCents: Int
    public let agingBuckets: PLAgingBuckets
    public let truncated: Bool
    public var outstandingDollars: Double { Double(outstandingCents) / 100.0 }
    public var overdueDollars: Double     { Double(overdueCents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case outstandingCents = "outstanding_cents"
        case overdueCents     = "overdue_cents"
        case agingBuckets     = "aging_buckets"
        case truncated
    }
    public init(outstandingCents: Int = 0, overdueCents: Int = 0,
                agingBuckets: PLAgingBuckets = PLAgingBuckets(), truncated: Bool = false) {
        self.outstandingCents = outstandingCents; self.overdueCents = overdueCents
        self.agingBuckets = agingBuckets; self.truncated = truncated
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        outstandingCents = (try? c.decode(Int.self, forKey: .outstandingCents)) ?? 0
        overdueCents     = (try? c.decode(Int.self, forKey: .overdueCents))     ?? 0
        agingBuckets     = (try? c.decode(PLAgingBuckets.self, forKey: .agingBuckets)) ?? PLAgingBuckets()
        truncated        = (try? c.decode(Bool.self, forKey: .truncated)) ?? false
    }
}

// MARK: - PLInventoryValue

public struct PLInventoryValue: Decodable, Sendable {
    public let cents: Int
    public let skuCount: Int
    public var dollars: Double { Double(cents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case cents
        case skuCount = "sku_count"
    }
    public init(cents: Int = 0, skuCount: Int = 0) {
        self.cents = cents; self.skuCount = skuCount
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cents    = (try? c.decode(Int.self, forKey: .cents))    ?? 0
        skuCount = (try? c.decode(Int.self, forKey: .skuCount)) ?? 0
    }
}

// MARK: - PLTimeBucket

public struct PLTimeBucket: Decodable, Sendable, Identifiable {
    public let bucket: String
    public let revenueCents: Int
    public let expenseCents: Int
    public let netCents: Int
    /// Year-over-year revenue delta in cents vs same bucket in prior year.
    /// Nil when the server omits prior-year data (e.g. first operating year).
    public let yoyRevenueDeltaCents: Int?
    public var id: String { bucket }
    public var revenueDollars: Double { Double(revenueCents) / 100.0 }
    public var expenseDollars: Double { Double(expenseCents) / 100.0 }
    public var netDollars: Double     { Double(netCents) / 100.0 }
    /// Percentage change vs prior year, nil if no prior data.
    public var yoyRevenuePct: Double? {
        guard let delta = yoyRevenueDeltaCents else { return nil }
        let prior = revenueCents - delta
        guard prior != 0 else { return nil }
        return Double(delta) / Double(prior)
    }

    enum CodingKeys: String, CodingKey {
        case bucket
        case revenueCents       = "revenue_cents"
        case expenseCents       = "expense_cents"
        case netCents           = "net_cents"
        case yoyRevenueDeltaCents = "yoy_revenue_delta_cents"
    }
    public init(bucket: String, revenueCents: Int, expenseCents: Int, netCents: Int,
                yoyRevenueDeltaCents: Int? = nil) {
        self.bucket = bucket; self.revenueCents = revenueCents
        self.expenseCents = expenseCents; self.netCents = netCents
        self.yoyRevenueDeltaCents = yoyRevenueDeltaCents
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bucket                = (try? c.decode(String.self, forKey: .bucket))                ?? ""
        revenueCents          = (try? c.decode(Int.self,    forKey: .revenueCents))          ?? 0
        expenseCents          = (try? c.decode(Int.self,    forKey: .expenseCents))          ?? 0
        netCents              = (try? c.decode(Int.self,    forKey: .netCents))              ?? 0
        yoyRevenueDeltaCents  = try? c.decode(Int.self,    forKey: .yoyRevenueDeltaCents)
    }
}

// MARK: - PLTopCustomer

public struct PLTopCustomer: Decodable, Sendable, Identifiable {
    public let customerId: Int
    public let name: String
    public let revenueCents: Int
    public var id: Int { customerId }
    public var revenueDollars: Double { Double(revenueCents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case customerId   = "customer_id"
        case name
        case revenueCents = "revenue_cents"
    }
    public init(customerId: Int, name: String, revenueCents: Int) {
        self.customerId = customerId; self.name = name; self.revenueCents = revenueCents
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customerId   = (try? c.decode(Int.self,    forKey: .customerId))   ?? 0
        name         = (try? c.decode(String.self, forKey: .name))         ?? ""
        revenueCents = (try? c.decode(Int.self,    forKey: .revenueCents)) ?? 0
    }
}

// MARK: - PLTopService

public struct PLTopService: Decodable, Sendable, Identifiable {
    public let service: String
    public let count: Int
    public let revenueCents: Int
    public var id: String { service }
    public var revenueDollars: Double { Double(revenueCents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case service
        case count
        case revenueCents = "revenue_cents"
    }
    public init(service: String, count: Int, revenueCents: Int) {
        self.service = service; self.count = count; self.revenueCents = revenueCents
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        service      = (try? c.decode(String.self, forKey: .service))      ?? ""
        count        = (try? c.decode(Int.self,    forKey: .count))        ?? 0
        revenueCents = (try? c.decode(Int.self,    forKey: .revenueCents)) ?? 0
    }
}
