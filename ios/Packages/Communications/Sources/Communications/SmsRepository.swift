import Foundation
import Networking

public protocol SmsRepository: Sendable {
    func listConversations(keyword: String?) async throws -> [SmsConversation]
}

public actor SmsRepositoryImpl: SmsRepository {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func listConversations(keyword: String?) async throws -> [SmsConversation] {
        try await api.listSmsConversations(keyword: keyword)
    }
}
