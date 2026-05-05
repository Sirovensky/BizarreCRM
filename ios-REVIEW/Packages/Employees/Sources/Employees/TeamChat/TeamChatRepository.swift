import Foundation
import Networking

// MARK: - TeamChatRepository
//
// §14.5 Team chat — channel-less surface backed by the server's general
// channel (the only `kind='general'` row, seeded by migration 096). Direct
// messages and ticket channels reuse the same primitives but are exposed
// elsewhere; this repository is the one the Employees tab embeds.
//
// Real-time: server WS push for `chat.message` is a §74 gap. We poll every
// 4 s while the view is on screen. Once the server emits the event, the
// `WSEvent.chatMessage` decoder already handles it (see WebSocketClient).

public protocol TeamChatRepository: Sendable {
    /// Resolves the global "general" channel id, creating it on first use if
    /// the seed row was wiped (defence-in-depth — fresh installs always have it).
    func ensureGeneralChannel() async throws -> TeamChannelRow
    /// Lists messages for a channel, optionally only newer than `after`.
    func listMessages(channelId: Int64, after: Int64) async throws -> [TeamMessageRow]
    /// Posts a message and returns the inserted row (with author fields joined).
    func postMessage(channelId: Int64, body: String) async throws -> TeamMessageRow
    /// Deletes a message (server enforces author/admin gate).
    func deleteMessage(channelId: Int64, messageId: Int64) async throws
}

public actor TeamChatRepositoryImpl: TeamChatRepository {
    private let api: APIClient
    private var cachedGeneralChannel: TeamChannelRow?

    public init(api: APIClient) { self.api = api }

    public func ensureGeneralChannel() async throws -> TeamChannelRow {
        if let cached = cachedGeneralChannel { return cached }
        let channels = try await api.listTeamChannels(kind: "general")
        if let existing = channels.first(where: { $0.kind == "general" }) {
            cachedGeneralChannel = existing
            return existing
        }
        // Seed missing — only admins can create. If non-admin and there's no
        // row, surface the server's 403 to the caller for graceful UI.
        let created = try await api.createTeamChannel(name: "general", kind: "general")
        cachedGeneralChannel = created
        return created
    }

    public func listMessages(channelId: Int64, after: Int64) async throws -> [TeamMessageRow] {
        try await api.listTeamMessages(channelId: channelId, after: after, limit: 100)
    }

    public func postMessage(channelId: Int64, body: String) async throws -> TeamMessageRow {
        try await api.postTeamMessage(channelId: channelId, body: body)
    }

    public func deleteMessage(channelId: Int64, messageId: Int64) async throws {
        try await api.deleteTeamMessage(channelId: channelId, messageId: messageId)
    }
}
