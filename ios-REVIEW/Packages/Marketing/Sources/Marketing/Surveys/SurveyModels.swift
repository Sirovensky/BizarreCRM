import Foundation

// MARK: - CSAT

public struct CSATSubmitRequest: Encodable, Sendable {
    public let customerId: String
    public let ticketId: String
    public let score: Int
    public let comment: String

    public init(customerId: String, ticketId: String, score: Int, comment: String) {
        self.customerId = customerId
        self.ticketId = ticketId
        self.score = score
        self.comment = comment
    }
}

// MARK: - NPS

public enum NPSCategory: String, Sendable {
    case detractor  // 0-6
    case passive    // 7-8
    case promoter   // 9-10

    public init(score: Int) {
        if score >= 9 { self = .promoter }
        else if score >= 7 { self = .passive }
        else { self = .detractor }
    }
}

public struct NPSSubmitRequest: Encodable, Sendable {
    public let customerId: String
    public let score: Int
    public let themes: [String]
    public let comment: String

    public init(customerId: String, score: Int, themes: [String], comment: String) {
        self.customerId = customerId
        self.score = score
        self.themes = themes
        self.comment = comment
    }
}

// MARK: - Shared response

public struct SurveySubmitResponse: Decodable, Sendable {
    public let received: Bool

    public init(received: Bool) {
        self.received = received
    }
}
