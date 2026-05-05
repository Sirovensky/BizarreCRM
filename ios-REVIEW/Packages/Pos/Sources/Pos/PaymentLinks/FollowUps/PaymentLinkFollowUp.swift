import Foundation
import Networking

// MARK: - §41.3 Follow-up model

/// A scheduled reminder sent to the customer on an unpaid payment link.
/// `triggerAfterHours` is relative to link creation time. `sentAt` /
/// `deliveredAt` are nil until the server processes the job.
public struct PaymentLinkFollowUp: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let paymentLinkId: Int64
    /// Hours after link creation before this follow-up fires.
    public let triggerAfterHours: Int
    public let templateId: Int64?
    public let channel: Channel
    public let sentAt: String?
    public let deliveredAt: String?
    public let status: Status

    public enum Channel: String, Codable, Sendable, CaseIterable {
        case sms
        case email
    }

    public enum Status: String, Codable, Sendable {
        case scheduled
        case sent
        case delivered
        case failed
        case cancelled
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw.lowercased()) ?? .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case paymentLinkId     = "payment_link_id"
        case triggerAfterHours = "trigger_after_hours"
        case templateId        = "template_id"
        case channel, status
        case sentAt            = "sent_at"
        case deliveredAt       = "delivered_at"
    }

    public init(
        id: Int64,
        paymentLinkId: Int64,
        triggerAfterHours: Int,
        templateId: Int64?,
        channel: Channel,
        sentAt: String?,
        deliveredAt: String?,
        status: Status
    ) {
        self.id = id
        self.paymentLinkId = paymentLinkId
        self.triggerAfterHours = triggerAfterHours
        self.templateId = templateId
        self.channel = channel
        self.sentAt = sentAt
        self.deliveredAt = deliveredAt
        self.status = status
    }
}

// MARK: - Create request

public struct CreateFollowUpRequest: Encodable, Sendable {
    public let triggerAfterHours: Int
    public let templateId: Int64?
    public let channel: PaymentLinkFollowUp.Channel

    public init(
        triggerAfterHours: Int,
        templateId: Int64? = nil,
        channel: PaymentLinkFollowUp.Channel
    ) {
        self.triggerAfterHours = triggerAfterHours
        self.templateId = templateId
        self.channel = channel
    }

    enum CodingKeys: String, CodingKey {
        case triggerAfterHours = "trigger_after_hours"
        case templateId        = "template_id"
        case channel
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `POST /payment-links/:id/followups`
    func createFollowUp(
        linkId: Int64,
        request: CreateFollowUpRequest
    ) async throws -> PaymentLinkFollowUp {
        try await post(
            "/api/v1/payment-links/\(linkId)/followups",
            body: request,
            as: PaymentLinkFollowUp.self
        )
    }

    /// `GET /payment-links/:id/followups`
    func listFollowUps(linkId: Int64) async throws -> [PaymentLinkFollowUp] {
        try await get("/api/v1/payment-links/\(linkId)/followups", as: [PaymentLinkFollowUp].self)
    }
}
