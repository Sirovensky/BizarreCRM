import Foundation
import Networking

// MARK: - §41.8 Analytics models

/// Per-link analytics. All counters are integers; money in cents.
public struct PaymentLinkAnalytics: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64         // paymentLinkId
    public let sent: Int
    public let opened: Int
    public let clicked: Int
    public let paid: Int
    /// Median milliseconds from first open to payment. `nil` when no paid conversions.
    public let openedToPaidMs: Int64?

    /// Conversion rate from open to paid, 0…1.
    public var openToPaidRate: Double {
        guard opened > 0 else { return 0 }
        return min(1, Double(paid) / Double(opened))
    }

    enum CodingKeys: String, CodingKey {
        case id           = "payment_link_id"
        case sent, opened, clicked, paid
        case openedToPaidMs = "opened_to_paid_ms"
    }

    public init(
        id: Int64,
        sent: Int,
        opened: Int,
        clicked: Int,
        paid: Int,
        openedToPaidMs: Int64? = nil
    ) {
        self.id = id
        self.sent = sent
        self.opened = opened
        self.clicked = clicked
        self.paid = paid
        self.openedToPaidMs = openedToPaidMs
    }
}

/// Aggregate metrics across all payment links for the tenant.
public struct PaymentLinksAggregate: Codable, Sendable {
    public let totalLinks: Int
    public let totalSent: Int
    public let totalOpened: Int
    public let totalClicked: Int
    public let totalPaid: Int
    public let totalRevenueCents: Int
    /// Aggregate conversion rate open → paid, 0…1.
    public var overallConversionRate: Double {
        guard totalOpened > 0 else { return 0 }
        return min(1, Double(totalPaid) / Double(totalOpened))
    }

    enum CodingKeys: String, CodingKey {
        case totalLinks        = "total_links"
        case totalSent         = "total_sent"
        case totalOpened       = "total_opened"
        case totalClicked      = "total_clicked"
        case totalPaid         = "total_paid"
        case totalRevenueCents = "total_revenue_cents"
    }

    public init(
        totalLinks: Int,
        totalSent: Int,
        totalOpened: Int,
        totalClicked: Int,
        totalPaid: Int,
        totalRevenueCents: Int
    ) {
        self.totalLinks = totalLinks
        self.totalSent = totalSent
        self.totalOpened = totalOpened
        self.totalClicked = totalClicked
        self.totalPaid = totalPaid
        self.totalRevenueCents = totalRevenueCents
    }
}

/// Top-level response envelope from `GET /payment-links/analytics`.
public struct PaymentLinksAnalyticsResponse: Codable, Sendable {
    public let aggregate: PaymentLinksAggregate
    public let perLink: [PaymentLinkAnalytics]

    enum CodingKeys: String, CodingKey {
        case aggregate
        case perLink = "per_link"
    }

    public init(aggregate: PaymentLinksAggregate, perLink: [PaymentLinkAnalytics]) {
        self.aggregate = aggregate
        self.perLink = perLink
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `GET /payment-links/analytics`
    func getPaymentLinksAnalytics() async throws -> PaymentLinksAnalyticsResponse {
        try await get("/api/v1/payment-links/analytics", as: PaymentLinksAnalyticsResponse.self)
    }
}
