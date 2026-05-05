import Foundation
import Networking

// MARK: - GroupSendRequest

/// `POST /api/v1/sms/group-send` body.
public struct GroupSendRequest: Encodable, Sendable {
    public let recipients: [String]
    public let body: String
    public let scheduledAt: String?

    public init(recipients: [String], body: String, scheduledAt: String? = nil) {
        self.recipients = recipients
        self.body = body
        self.scheduledAt = scheduledAt
    }

    enum CodingKeys: String, CodingKey {
        case recipients, body
        case scheduledAt = "scheduled_at"
    }
}

// MARK: - GroupSendAck

/// Acknowledgement from `POST /sms/group-send`.
public struct GroupSendAck: Decodable, Sendable {
    public let queued: Int
    public let failed: Int

    public init(queued: Int, failed: Int) {
        self.queued = queued
        self.failed = failed
    }
}

// MARK: - APIClient extension

public extension APIClient {
    func groupSend(request: GroupSendRequest) async throws -> GroupSendAck {
        try await post("/api/v1/sms/group-send", body: request, as: GroupSendAck.self)
    }
}
