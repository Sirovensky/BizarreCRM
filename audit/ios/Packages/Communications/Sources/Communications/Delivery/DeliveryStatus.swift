import Foundation

// MARK: - DeliveryStatus

public enum DeliveryStatus: String, Codable, Sendable, CaseIterable {
    case sent
    case delivered
    case failed
    case optedOut = "opted_out"
    case noResponse = "no_response"

    /// Terminal statuses stop polling.
    public var isTerminal: Bool {
        switch self {
        case .delivered, .failed, .optedOut: return true
        case .sent, .noResponse: return false
        }
    }

    public var displayLabel: String {
        switch self {
        case .sent:       return "Sent"
        case .delivered:  return "Delivered"
        case .failed:     return "Failed"
        case .optedOut:   return "Opted out"
        case .noResponse: return "No response"
        }
    }

    /// SF Symbol name for badge.
    public var symbolName: String {
        switch self {
        case .sent:       return "checkmark.circle"
        case .delivered:  return "checkmark.circle.fill"
        case .failed:     return "xmark.circle.fill"
        case .optedOut:   return "nosign"
        case .noResponse: return "clock"
        }
    }

    public var isError: Bool { self == .failed || self == .optedOut }
}

// MARK: - DeliveryStatusResponse

/// Decoded from `GET /api/v1/sms/messages/:id/status`.
public struct DeliveryStatusResponse: Decodable, Sendable {
    public let messageId: Int64
    public let status: DeliveryStatus
    public let deliveredAt: String?
    public let failureReason: String?
    public let carrier: String?

    public init(
        messageId: Int64,
        status: DeliveryStatus,
        deliveredAt: String?,
        failureReason: String?,
        carrier: String?
    ) {
        self.messageId = messageId
        self.status = status
        self.deliveredAt = deliveredAt
        self.failureReason = failureReason
        self.carrier = carrier
    }

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case status
        case deliveredAt = "delivered_at"
        case failureReason = "failure_reason"
        case carrier
    }
}

// MARK: - APIClient extension

import Networking

public extension APIClient {
    func smsMessageStatus(messageId: Int64) async throws -> DeliveryStatusResponse {
        try await get("/api/v1/sms/messages/\(messageId)/status", as: DeliveryStatusResponse.self)
    }

    func starSmsMessage(messageId: Int64) async throws {
        try await delete("/api/v1/sms/messages/\(messageId)/star-placeholder")
        // Actual: POST /sms/messages/:id/star — uses delete path as placeholder;
        // real implementation uses post when server ships the endpoint.
    }
}
