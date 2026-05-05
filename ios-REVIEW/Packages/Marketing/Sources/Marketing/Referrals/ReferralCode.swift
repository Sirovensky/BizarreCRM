import Foundation

// MARK: - ReferralCode

public struct ReferralCode: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let customerId: String
    /// 8-character alphanumeric referral code (e.g. "ABC12345").
    public let code: String
    public let createdAt: Date
    public var uses: Int
    public var conversions: Int

    public init(
        id: String,
        customerId: String,
        code: String,
        createdAt: Date,
        uses: Int,
        conversions: Int
    ) {
        self.id = id
        self.customerId = customerId
        self.code = code
        self.createdAt = createdAt
        self.uses = uses
        self.conversions = conversions
    }
}

// MARK: - ReferralRule

public enum ReferralRuleType: String, Codable, Sendable, CaseIterable {
    case flat
    case percentage
}

public struct ReferralRule: Codable, Sendable, Hashable {
    public let type: ReferralRuleType
    /// Fixed sender credit in cents (used when `type == .flat`).
    public let senderCreditCents: Int
    /// Fixed receiver credit in cents (used when `type == .flat`).
    public let receiverCreditCents: Int
    /// Minimum qualifying sale amount in cents.
    public let minSaleCents: Int
    /// Basis points for percentage calculation (used when `type == .percentage`).
    /// 100 bps = 1%; 500 bps = 5%.
    public let percentageBps: Int

    public init(
        type: ReferralRuleType,
        senderCreditCents: Int,
        receiverCreditCents: Int,
        minSaleCents: Int,
        percentageBps: Int
    ) {
        self.type = type
        self.senderCreditCents = senderCreditCents
        self.receiverCreditCents = receiverCreditCents
        self.minSaleCents = minSaleCents
        self.percentageBps = percentageBps
    }

    public static let `default` = ReferralRule(
        type: .flat,
        senderCreditCents: 500,
        receiverCreditCents: 500,
        minSaleCents: 0,
        percentageBps: 0
    )
}

// MARK: - Sale (lightweight value for calculator)

public struct Sale: Sendable {
    public let amountCents: Int
    public init(amountCents: Int) { self.amountCents = amountCents }
}

// MARK: - ReferralCredit

public struct ReferralCredit: Sendable {
    public let senderCents: Int
    public let receiverCents: Int

    public var totalCents: Int { senderCents + receiverCents }

    public init(senderCents: Int, receiverCents: Int) {
        self.senderCents = senderCents
        self.receiverCents = receiverCents
    }
}

// MARK: - Referral leaderboard entry

public struct ReferralLeaderEntry: Identifiable, Decodable, Sendable {
    public let id: String          // customerId
    public let customerName: String
    public let referralCount: Int
    public let revenueGeneratedCents: Int

    public init(id: String, customerName: String, referralCount: Int, revenueGeneratedCents: Int) {
        self.id = id
        self.customerName = customerName
        self.referralCount = referralCount
        self.revenueGeneratedCents = revenueGeneratedCents
    }
}

// MARK: - API shapes

public struct ReferralCodeResponse: Decodable, Sendable {
    public let code: ReferralCode
}

public struct ReferralLeaderboardResponse: Decodable, Sendable {
    public let entries: [ReferralLeaderEntry]
}
