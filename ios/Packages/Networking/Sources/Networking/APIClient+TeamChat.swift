import Foundation

// MARK: - Team chat wire types
//
// Grounded against packages/server/src/routes/teamChat.routes.ts.
// Mounted at /api/v1/team-chat. Polling-based; WS hookup is server-side §74
// gap (event types defined in WebSocketClient.WSEvent are forward-compatible).
//
// Confirmed routes (server today):
//   GET    /api/v1/team-chat/channels[?kind=]                  → { success, data: [TeamChannelRow] }
//   POST   /api/v1/team-chat/channels                          → { success, data: TeamChannelRow }
//   DELETE /api/v1/team-chat/channels/:id                      → { success, data: { id } }
//   GET    /api/v1/team-chat/channels/:id/messages?after=&limit= → { success, data: [TeamMessageRow] }
//   POST   /api/v1/team-chat/channels/:id/messages             → { success, data: TeamMessageRow }
//   DELETE /api/v1/team-chat/channels/:cid/messages/:mid       → { success, data: { id } }
//
// SERVER GAP §74 — pin and attachment columns/endpoints not yet present.
// iOS pin-state is persisted locally (UserDefaults, see PinnedMessagesStore);
// attachments embed a signed URL fragment in the message body following the
// `[[attach:<url>|<mime>|<filename>]]` convention so they round-trip until the
// server adds first-class columns.

public struct TeamChannelRow: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let kind: String
    public let ticketId: Int64?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case ticketId = "ticket_id"
        case createdAt = "created_at"
    }

    public init(id: Int64, name: String, kind: String, ticketId: Int64?, createdAt: String) {
        self.id = id; self.name = name; self.kind = kind
        self.ticketId = ticketId; self.createdAt = createdAt
    }
}

public struct TeamMessageRow: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let channelId: Int64
    public let userId: Int64
    public let body: String
    public let createdAt: String
    public let firstName: String?
    public let lastName: String?
    public let username: String?

    enum CodingKeys: String, CodingKey {
        case id, body, username
        case channelId = "channel_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case firstName = "first_name"
        case lastName = "last_name"
    }

    public init(id: Int64, channelId: Int64, userId: Int64, body: String,
                createdAt: String, firstName: String?, lastName: String?, username: String?) {
        self.id = id; self.channelId = channelId; self.userId = userId
        self.body = body; self.createdAt = createdAt
        self.firstName = firstName; self.lastName = lastName; self.username = username
    }

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? (username ?? "User #\(userId)") : parts.joined(separator: " ")
    }
}

public struct CreateTeamChannelBody: Encodable, Sendable {
    public let name: String
    public let kind: String
    public let ticketId: Int64?
    enum CodingKeys: String, CodingKey { case name, kind; case ticketId = "ticket_id" }
    public init(name: String, kind: String, ticketId: Int64? = nil) {
        self.name = name; self.kind = kind; self.ticketId = ticketId
    }
}

public struct PostTeamMessageBody: Encodable, Sendable {
    public let body: String
    public init(body: String) { self.body = body }
}

public struct DeletedTeamMessageResult: Decodable, Sendable { public let id: Int64 }

public extension APIClient {

    /// `GET /api/v1/team-chat/channels` — lists visible channels for the caller.
    func listTeamChannels(kind: String? = nil) async throws -> [TeamChannelRow] {
        var query: [URLQueryItem]? = nil
        if let kind { query = [URLQueryItem(name: "kind", value: kind)] }
        return try await get("/api/v1/team-chat/channels", query: query, as: [TeamChannelRow].self)
    }

    /// `POST /api/v1/team-chat/channels` — admin creates a general/direct channel
    /// (or any user creates a ticket channel). Returns existing row if a ticket
    /// channel already exists for the same ticket id.
    func createTeamChannel(name: String, kind: String, ticketId: Int64? = nil) async throws -> TeamChannelRow {
        let body = CreateTeamChannelBody(name: name, kind: kind, ticketId: ticketId)
        return try await post("/api/v1/team-chat/channels", body: body, as: TeamChannelRow.self)
    }

    /// `GET /api/v1/team-chat/channels/:id/messages?after=` — incremental fetch.
    /// Pass the last seen message id as `after` to get only newer rows.
    func listTeamMessages(channelId: Int64, after: Int64 = 0, limit: Int = 50) async throws -> [TeamMessageRow] {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "after", value: String(after)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await get("/api/v1/team-chat/channels/\(channelId)/messages",
                             query: query, as: [TeamMessageRow].self)
    }

    /// `POST /api/v1/team-chat/channels/:id/messages` — body up to 2000 chars.
    /// Server parses `@username` tokens and writes to `team_mentions`.
    func postTeamMessage(channelId: Int64, body: String) async throws -> TeamMessageRow {
        let payload = PostTeamMessageBody(body: body)
        return try await post("/api/v1/team-chat/channels/\(channelId)/messages",
                              body: payload, as: TeamMessageRow.self)
    }

    /// `DELETE /api/v1/team-chat/channels/:cid/messages/:mid` — author or admin.
    func deleteTeamMessage(channelId: Int64, messageId: Int64) async throws {
        try await delete("/api/v1/team-chat/channels/\(channelId)/messages/\(messageId)")
    }
}
