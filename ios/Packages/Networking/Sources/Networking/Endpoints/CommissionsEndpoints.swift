import Foundation

// MARK: - Commission models

public enum CommissionRuleType: String, Codable, CaseIterable, Sendable {
    case percentage = "percentage"
    case flat = "flat"
}

public struct CommissionCondition: Codable, Sendable, Identifiable, Hashable {
    public let id: String   // synthetic (type+value string)
    public var minTicketValue: Double?
    public var tenureMonths: Int?

    public init(minTicketValue: Double? = nil, tenureMonths: Int? = nil) {
        self.id = "cond-\(minTicketValue ?? 0)-\(tenureMonths ?? 0)"
        self.minTicketValue = minTicketValue
        self.tenureMonths = tenureMonths
    }

    enum CodingKeys: String, CodingKey {
        case minTicketValue = "min_ticket_value"
        case tenureMonths = "tenure_months"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.minTicketValue = try c.decodeIfPresent(Double.self, forKey: .minTicketValue)
        self.tenureMonths = try c.decodeIfPresent(Int.self, forKey: .tenureMonths)
        self.id = "cond-\(minTicketValue ?? 0)-\(tenureMonths ?? 0)"
    }
}

public struct CommissionRule: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public var role: String?
    public var serviceCategory: String?
    public var productCategory: String?
    public var ruleType: CommissionRuleType
    public var value: Double        // percentage (0-100) or flat dollar amount
    public var capAmount: Double?
    public var condition: CommissionCondition?
    public let createdAt: String?

    public init(
        id: Int64,
        role: String? = nil,
        serviceCategory: String? = nil,
        productCategory: String? = nil,
        ruleType: CommissionRuleType,
        value: Double,
        capAmount: Double? = nil,
        condition: CommissionCondition? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.role = role
        self.serviceCategory = serviceCategory
        self.productCategory = productCategory
        self.ruleType = ruleType
        self.value = value
        self.capAmount = capAmount
        self.condition = condition
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, role, condition
        case serviceCategory = "service_category"
        case productCategory = "product_category"
        case ruleType = "rule_type"
        case value
        case capAmount = "cap_amount"
        case createdAt = "created_at"
    }
}

// MARK: - Commission payout / report

public struct Sale: Sendable {
    public let id: String
    public let amount: Double
    public let serviceCategory: String?
    public let productCategory: String?
    public let date: Date

    public init(
        id: String,
        amount: Double,
        serviceCategory: String? = nil,
        productCategory: String? = nil,
        date: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.serviceCategory = serviceCategory
        self.productCategory = productCategory
        self.date = date
    }
}

public struct CommissionLineItem: Sendable, Identifiable {
    public let id: String
    public let saleId: String
    public let ruleId: Int64
    public let saleAmount: Double
    public let commissionAmount: Double
    public let description: String

    public init(id: String, saleId: String, ruleId: Int64, saleAmount: Double, commissionAmount: Double, description: String) {
        self.id = id
        self.saleId = saleId
        self.ruleId = ruleId
        self.saleAmount = saleAmount
        self.commissionAmount = commissionAmount
        self.description = description
    }
}

public struct CommissionReport: Sendable {
    public let employeeId: String
    public let period: DateInterval
    public let lineItems: [CommissionLineItem]
    public var total: Double { lineItems.reduce(0) { $0 + $1.commissionAmount } }

    public init(employeeId: String, period: DateInterval, lineItems: [CommissionLineItem]) {
        self.employeeId = employeeId
        self.period = period
        self.lineItems = lineItems
    }
}

public struct CommissionPayout: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let employeeId: Int64
    public let amount: Double
    public let period: String
    public let paidAt: String?
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, period, notes
        case employeeId = "employee_id"
        case paidAt = "paid_at"
    }
}

public struct CommissionPayoutsResponse: Decodable, Sendable {
    public let payouts: [CommissionPayout]
}

public struct CommissionRulesListResponse: Decodable, Sendable {
    public let rules: [CommissionRule]
}

// MARK: - Request bodies

public struct CreateCommissionRuleRequest: Encodable, Sendable {
    public let role: String?
    public let serviceCategory: String?
    public let productCategory: String?
    public let ruleType: CommissionRuleType
    public let value: Double
    public let capAmount: Double?

    public init(role: String?, serviceCategory: String?, productCategory: String?, ruleType: CommissionRuleType, value: Double, capAmount: Double?) {
        self.role = role
        self.serviceCategory = serviceCategory
        self.productCategory = productCategory
        self.ruleType = ruleType
        self.value = value
        self.capAmount = capAmount
    }

    enum CodingKeys: String, CodingKey {
        case role, value
        case serviceCategory = "service_category"
        case productCategory = "product_category"
        case ruleType = "rule_type"
        case capAmount = "cap_amount"
    }
}

public struct UpdateCommissionRuleRequest: Encodable, Sendable {
    public let role: String?
    public let serviceCategory: String?
    public let productCategory: String?
    public let ruleType: CommissionRuleType
    public let value: Double
    public let capAmount: Double?

    public init(role: String?, serviceCategory: String?, productCategory: String?, ruleType: CommissionRuleType, value: Double, capAmount: Double?) {
        self.role = role
        self.serviceCategory = serviceCategory
        self.productCategory = productCategory
        self.ruleType = ruleType
        self.value = value
        self.capAmount = capAmount
    }

    enum CodingKeys: String, CodingKey {
        case role, value
        case serviceCategory = "service_category"
        case productCategory = "product_category"
        case ruleType = "rule_type"
        case capAmount = "cap_amount"
    }
}

// MARK: - APIClient extensions

public extension APIClient {
    func listCommissionRules() async throws -> [CommissionRule] {
        try await get("/api/v1/commissions/rules", as: CommissionRulesListResponse.self).rules
    }

    func createCommissionRule(_ req: CreateCommissionRuleRequest) async throws -> CommissionRule {
        try await post("/api/v1/commissions/rules", body: req, as: CommissionRule.self)
    }

    func updateCommissionRule(id: Int64, _ req: UpdateCommissionRuleRequest) async throws -> CommissionRule {
        try await patch("/api/v1/commissions/rules/\(id)", body: req, as: CommissionRule.self)
    }

    func deleteCommissionRule(id: Int64) async throws {
        try await delete("/api/v1/commissions/rules/\(id)")
    }

    func fetchCommissionReport(employeeId: Int64) async throws -> [CommissionPayout] {
        try await get(
            "/api/v1/commissions/reports/\(employeeId)",
            as: CommissionPayoutsResponse.self
        ).payouts
    }
}
