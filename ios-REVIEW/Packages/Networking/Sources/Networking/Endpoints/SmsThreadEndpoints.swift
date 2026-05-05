import Foundation

/// `GET /api/v1/sms/conversations/:phone` response (unwrapped).
/// Server: packages/server/src/routes/sms.routes.ts:312.
public struct SmsThread: Decodable, Sendable {
    public let messages: [SmsMessage]
    public let customer: ResolvedCustomer?
    public let recentTickets: [ThreadRecentTicket]?

    public struct ResolvedCustomer: Decodable, Sendable, Hashable {
        public let id: Int64?
        public let firstName: String?
        public let lastName: String?
        public let phone: String?
        public let mobile: String?
        public let email: String?

        public var displayName: String {
            let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
            return parts.isEmpty ? "Unknown" : parts.joined(separator: " ")
        }

        enum CodingKeys: String, CodingKey {
            case id, phone, mobile, email
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    public struct ThreadRecentTicket: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let orderId: String?
        public let statusName: String?
        public let statusColor: String?
        public let deviceName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case orderId = "order_id"
            case statusName = "status_name"
            case statusColor = "status_color"
            case deviceName = "device_name"
        }
    }

    enum CodingKeys: String, CodingKey {
        case messages, customer
        case recentTickets = "recent_tickets"
    }
}

public struct SmsMessage: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let message: String?
    public let direction: String?
    public let status: String?
    public let fromNumber: String?
    public let toNumber: String?
    public let convPhone: String?
    public let messageType: String?
    public let createdAt: String?
    /// §12.2 Read receipts — ISO-8601 timestamp when the remote party read this
    /// outbound message. Nil when server does not support read receipts.
    public let readAt: String?

    public var isOutbound: Bool { direction?.lowercased() == "outbound" }

    public var statusLabel: String? {
        switch status?.lowercased() {
        case "sent":      return "Sent"
        case "delivered": return "Delivered"
        case "queued":    return "Queued"
        case "failed":    return "Failed"
        case "pending":   return "Sending…"
        case "sending":   return "Sending…"
        case "scheduled": return "Scheduled"
        case "simulated": return "Simulated"
        default:          return nil
        }
    }

    public var failed: Bool { status?.lowercased() == "failed" }

    enum CodingKeys: String, CodingKey {
        case id, message, direction, status
        case fromNumber = "from_number"
        case toNumber = "to_number"
        case convPhone = "conv_phone"
        case messageType = "message_type"
        case createdAt = "created_at"
        case readAt = "read_at"
    }
}

/// `POST /api/v1/sms/send` body (immediate send).
public struct SmsSendRequest: Encodable, Sendable {
    public let to: String
    public let message: String

    public init(to: String, message: String) {
        self.to = to
        self.message = message
    }
}

/// `POST /api/v1/sms/send` body with scheduled delivery (§12.2 Schedule send).
/// Server: sms.routes.ts — accepts `send_at` as an ISO-8601 string with explicit
/// timezone offset (e.g. "2026-04-30T14:00:00Z"). Server returns status="scheduled".
public struct SmsSendScheduledRequest: Encodable, Sendable {
    public let to: String
    public let message: String
    /// ISO-8601 with explicit timezone offset. Required by the server for scheduled sends.
    public let sendAt: String

    public init(to: String, message: String, sendAt: String) {
        self.to = to
        self.message = message
        self.sendAt = sendAt
    }

    enum CodingKeys: String, CodingKey {
        case to, message
        case sendAt = "send_at"
    }
}

public extension APIClient {
    func smsThread(phone: String) async throws -> SmsThread {
        let encoded = phone.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? phone
        return try await get("/api/v1/sms/conversations/\(encoded)", as: SmsThread.self)
    }

    func sendSms(to: String, message: String) async throws -> SmsMessage {
        try await post("/api/v1/sms/send", body: SmsSendRequest(to: to, message: message), as: SmsMessage.self)
    }

    /// §12.2 Schedule send — `POST /api/v1/sms/send` with `send_at`.
    /// Server (sms.routes.ts:565) stores the message with status="scheduled"
    /// and fires it via the scheduler cron at the specified UTC instant.
    func sendSmsScheduled(to: String, message: String, sendAt: String) async throws -> SmsMessage {
        let body = SmsSendScheduledRequest(to: to, message: message, sendAt: sendAt)
        return try await post("/api/v1/sms/send", body: body, as: SmsMessage.self)
    }
}
