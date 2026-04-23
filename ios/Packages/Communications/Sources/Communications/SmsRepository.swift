import Foundation
import Networking

// MARK: - SmsRepository

public protocol SmsRepository: Sendable {
    func listConversations(keyword: String?) async throws -> [SmsConversation]
    /// Marks the thread's inbound messages as read for the current user.
    func markRead(phone: String) async throws
    /// Toggles the flagged state; returns the new flag value.
    func toggleFlag(phone: String) async throws -> Bool
    /// Toggles the pinned state; returns the new pin value.
    func togglePin(phone: String) async throws -> Bool
}

// MARK: - SmsRepositoryImpl

public actor SmsRepositoryImpl: SmsRepository {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func listConversations(keyword: String?) async throws -> [SmsConversation] {
        try await api.listSmsConversations(keyword: keyword)
    }

    public func markRead(phone: String) async throws {
        try await api.markSmsThreadRead(phone: phone)
    }

    public func toggleFlag(phone: String) async throws -> Bool {
        let result = try await api.toggleSmsConversationFlag(phone: phone)
        return result.isFlagged
    }

    public func togglePin(phone: String) async throws -> Bool {
        let result = try await api.toggleSmsConversationPin(phone: phone)
        return result.isPinned
    }
}
