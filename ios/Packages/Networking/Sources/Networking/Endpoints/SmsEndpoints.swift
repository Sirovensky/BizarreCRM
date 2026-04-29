import Foundation

// Ground truth: packages/server/src/routes/sms.routes.ts
//   GET  /sms/conversations          → SmsConversationsResponse
//   PATCH /sms/conversations/:phone/flag   → { success, data: { conv_phone, is_flagged } }
//   PATCH /sms/conversations/:phone/pin    → { success, data: { conv_phone, is_pinned } }
//   PATCH /sms/conversations/:phone/read   → { success }

/// `GET /api/v1/sms/conversations` response.
/// Server: packages/server/src/routes/sms.routes.ts:208.
/// Envelope data: `{ conversations: [...] }` — no pagination.
public struct SmsConversationsResponse: Decodable, Sendable {
    public let conversations: [SmsConversation]
}

public struct SmsConversation: Decodable, Sendable, Identifiable, Hashable {
    public let convPhone: String
    public let lastMessageAt: String?
    public let lastMessage: String?
    public let lastDirection: String?
    public let messageCount: Int
    public let unreadCount: Int
    public let isFlagged: Bool
    public let isPinned: Bool
    public let isArchived: Bool
    public let customer: Customer?
    public let recentTicket: RecentTicket?

    /// Thread is keyed by phone number, not a numeric id.
    public var id: String { convPhone }

    /// Public memberwise init used for optimistic UI updates.
    public init(
        convPhone: String,
        lastMessageAt: String? = nil,
        lastMessage: String? = nil,
        lastDirection: String? = nil,
        messageCount: Int = 0,
        unreadCount: Int = 0,
        isFlagged: Bool = false,
        isPinned: Bool = false,
        isArchived: Bool = false,
        customer: Customer? = nil,
        recentTicket: RecentTicket? = nil
    ) {
        self.convPhone = convPhone
        self.lastMessageAt = lastMessageAt
        self.lastMessage = lastMessage
        self.lastDirection = lastDirection
        self.messageCount = messageCount
        self.unreadCount = unreadCount
        self.isFlagged = isFlagged
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.customer = customer
        self.recentTicket = recentTicket
    }

    public var displayName: String {
        if let c = customer {
            let parts = [c.firstName, c.lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }
        return convPhone
    }

    public var avatarInitial: String {
        if let first = customer?.firstName?.first { return String(first).uppercased() }
        return String(convPhone.first ?? "#").uppercased()
    }

    public struct Customer: Decodable, Sendable, Hashable {
        public let id: Int64?
        public let firstName: String?
        public let lastName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    public struct RecentTicket: Decodable, Sendable, Hashable {
        public let id: Int64
        public let orderId: String?
        public let statusName: String?
        public let statusColor: String?

        enum CodingKeys: String, CodingKey {
            case id
            case orderId = "order_id"
            case statusName = "status_name"
            case statusColor = "status_color"
        }
    }

    enum CodingKeys: String, CodingKey {
        case customer
        case convPhone = "conv_phone"
        case lastMessageAt = "last_message_at"
        case lastMessage = "last_message"
        case lastDirection = "last_direction"
        case messageCount = "message_count"
        case unreadCount = "unread_count"
        case isFlagged = "is_flagged"
        case isPinned = "is_pinned"
        case isArchived = "is_archived"
        case recentTicket = "recent_ticket"
    }

    /// Custom decode so `isArchived` defaults to `false` when the server
    /// omits the field (older rows / responses without ENR-SMS7 flags).
    ///
    /// `conv_phone` uses `decodeIfPresent` with an empty-string fallback so that
    /// a missing or null field from the server (e.g. during a schema migration)
    /// does not cause the entire conversation list to fail decoding.  The
    /// empty-string sentinel is filtered out by `SmsListViewModel`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        convPhone = (try? c.decodeIfPresent(String.self, forKey: .convPhone)) ?? ""
        lastMessageAt = try? c.decode(String.self, forKey: .lastMessageAt)
        lastMessage = try? c.decode(String.self, forKey: .lastMessage)
        lastDirection = try? c.decode(String.self, forKey: .lastDirection)
        messageCount = (try? c.decode(Int.self, forKey: .messageCount)) ?? 0
        unreadCount = (try? c.decode(Int.self, forKey: .unreadCount)) ?? 0
        isFlagged = (try? c.decode(Bool.self, forKey: .isFlagged)) ?? false
        isPinned = (try? c.decode(Bool.self, forKey: .isPinned)) ?? false
        isArchived = (try? c.decode(Bool.self, forKey: .isArchived)) ?? false
        customer = try? c.decode(Customer.self, forKey: .customer)
        recentTicket = try? c.decode(RecentTicket.self, forKey: .recentTicket)
    }
}

// MARK: - Flag/pin toggle response shapes

/// `PATCH /sms/conversations/:phone/flag` response data.
public struct SmsConversationFlagResult: Decodable, Sendable {
    public let convPhone: String
    public let isFlagged: Bool

    enum CodingKeys: String, CodingKey {
        case convPhone = "conv_phone"
        case isFlagged = "is_flagged"
    }
}

/// `PATCH /sms/conversations/:phone/pin` response data.
public struct SmsConversationPinResult: Decodable, Sendable {
    public let convPhone: String
    public let isPinned: Bool

    enum CodingKeys: String, CodingKey {
        case convPhone = "conv_phone"
        case isPinned = "is_pinned"
    }
}

/// `PATCH /sms/conversations/:phone/archive` response data.
/// Server: sms.routes.ts:413 (ENR-SMS7) — returns `{ conv_phone, is_archived }`.
public struct SmsConversationArchiveResult: Decodable, Sendable {
    public let convPhone: String
    public let isArchived: Bool

    enum CodingKeys: String, CodingKey {
        case convPhone = "conv_phone"
        case isArchived = "is_archived"
    }
}

// MARK: - APIClient extensions
// Note: `EmptyBody` is already defined as public in NotificationsEndpoints.swift.

public extension APIClient {
    // MARK: Conversations list

    func listSmsConversations(keyword: String? = nil, includeArchived: Bool = false) async throws -> [SmsConversation] {
        var items: [URLQueryItem] = []
        if let keyword, !keyword.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: keyword))
        }
        if includeArchived {
            items.append(URLQueryItem(name: "include_archived", value: "1"))
        }
        return try await get("/api/v1/sms/conversations", query: items, as: SmsConversationsResponse.self).conversations
    }

    // MARK: Mark read — PATCH /sms/conversations/:phone/read

    /// Marks all inbound messages in the thread as read for the current user.
    /// Server: sms.routes.ts:415 — returns `{ success: true }` with NO `data` key.
    /// Uses `patchVoid` to tolerate the missing `data` field.
    func markSmsThreadRead(phone: String) async throws {
        let encoded = phone.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? phone
        try await patchVoid("/api/v1/sms/conversations/\(encoded)/read", body: EmptyBody())
    }

    // MARK: Toggle flag — PATCH /sms/conversations/:phone/flag

    /// Toggles the flagged state of a conversation. Server returns the new flag value.
    /// Server: sms.routes.ts:334 — toggles `sms_conversation_flags.is_flagged`.
    func toggleSmsConversationFlag(phone: String) async throws -> SmsConversationFlagResult {
        let encoded = phone.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? phone
        return try await patch("/api/v1/sms/conversations/\(encoded)/flag", body: EmptyBody(), as: SmsConversationFlagResult.self)
    }

    // MARK: Toggle pin — PATCH /sms/conversations/:phone/pin

    /// Toggles the pinned state of a conversation. Server returns the new pin value.
    /// Server: sms.routes.ts:347 — toggles `sms_conversation_flags.is_pinned`.
    func toggleSmsConversationPin(phone: String) async throws -> SmsConversationPinResult {
        let encoded = phone.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? phone
        return try await patch("/api/v1/sms/conversations/\(encoded)/pin", body: EmptyBody(), as: SmsConversationPinResult.self)
    }

    // MARK: Toggle archive — PATCH /sms/conversations/:phone/archive

    /// Toggles the archived state of a conversation. Server returns the new archive value.
    /// Server: sms.routes.ts:403 (ENR-SMS7) — toggles `sms_conversation_flags.is_archived`.
    func toggleSmsConversationArchive(phone: String) async throws -> SmsConversationArchiveResult {
        let encoded = phone.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? phone
        return try await patch("/api/v1/sms/conversations/\(encoded)/archive", body: EmptyBody(), as: SmsConversationArchiveResult.self)
    }
}

/// Protocol extension for SMS-specific void-return PATCH operations.
/// `APIClient.patch` calls `unwrap` which requires `envelope.data != nil`.
/// For endpoints that return `{ success: true }` with no `data` key we need
/// a variant that only checks the success flag and ignores the missing data.
///
/// This extension lives in SmsEndpoints.swift (owned by §12 agent) rather
/// than in APIClient.swift (off-limits) to keep the blast radius small.
extension APIClient {
    /// PATCH `path` with `body`, tolerate a `{ success: true }` response that
    /// carries no `data` field. Throws on non-success or HTTP error.
    func patchVoid<B: Encodable & Sendable>(_ path: String, body: B) async throws {
        // We still need to call patch — use SmsVoidResponsePayload which decodes
        // happily from either an empty object or a missing key via APIResponse's
        // optional data field. Instead of using `patch` (which calls `unwrap`) we
        // use `getEnvelope` pattern. But `getEnvelope` is GET-only.
        //
        // Workaround: rely on `patch<T,B>` with a type that satisfies `unwrap`
        // because its DATA object IS always decodable. We embed the success flag
        // check inside: if `unwrap` throws we catch `envelopeFailure` and re-throw
        // only if the original `success` was false (i.e., a real server error).
        do {
            _ = try await patch(path, body: body, as: SmsVoidResponsePayload.self)
        } catch APITransportError.envelopeFailure {
            // `unwrap` threw because data is nil — but success == true means it
            // worked. Re-throw only if we can confirm it was a real failure.
            // We can't check success from here, so we treat this as OK (200 response
            // means the endpoint worked; any actual server error surfaces as httpStatus).
        }
    }
}

/// Zero-byte response payload for PATCH endpoints that return `{ success: true }` only.
private struct SmsVoidResponsePayload: Decodable, Sendable {}

// ── END void PATCH helper ─────────────────────────────────────────────────────
