import Foundation
#if canImport(Networking)
import Networking
#endif

// §7 line 1282 — Customer communication: fee-applied notification with payment link.
//
// Pure formatter that produces the SMS / email body once a late fee has been
// applied, plus a thin POST wrapper. Server-side templates may override; the
// client formatter is used for in-app preview + offline drafting.
//
// Server endpoint: POST /api/v1/invoices/:id/late-fee-applied-notification
//   Body: { fee_cents, new_balance_cents, payment_link_url, channel }

public enum LateFeeAppliedNotificationService {

    /// Renders the customer-facing message body.
    /// Pure — fully testable.
    public static func formatMessage(
        invoiceDisplayId: String,
        feeCents: Cents,
        newBalanceCents: Cents,
        paymentLinkURL: String,
        locale: Locale = .current
    ) -> String {
        let fee  = formatCents(feeCents,  locale: locale)
        let bal  = formatCents(newBalanceCents, locale: locale)
        return """
        A late fee of \(fee) has been added to invoice \(invoiceDisplayId). \
        New balance: \(bal). Pay now: \(paymentLinkURL)
        """
    }

    private static func formatCents(_ cents: Cents, locale: Locale) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        return f.string(from: NSNumber(value: Double(cents) / 100.0))
            ?? String(format: "$%.2f", Double(cents) / 100.0)
    }
}

// MARK: - Network DTOs

public struct LateFeeAppliedNotificationRequest: Encodable, Sendable {
    public enum Channel: String, Encodable, Sendable { case sms, email, both }

    public let feeCents: Cents
    public let newBalanceCents: Cents
    public let paymentLinkURL: String
    public let channel: Channel

    public init(feeCents: Cents, newBalanceCents: Cents, paymentLinkURL: String, channel: Channel) {
        self.feeCents = feeCents
        self.newBalanceCents = newBalanceCents
        self.paymentLinkURL = paymentLinkURL
        self.channel = channel
    }

    enum CodingKeys: String, CodingKey {
        case feeCents          = "fee_cents"
        case newBalanceCents   = "new_balance_cents"
        case paymentLinkURL    = "payment_link_url"
        case channel
    }
}

public struct LateFeeAppliedNotificationResponse: Decodable, Sendable {
    public let success: Bool?
    public let sentAt: String?
    public let messageId: String?

    enum CodingKeys: String, CodingKey {
        case success
        case sentAt    = "sent_at"
        case messageId = "message_id"
    }
}

#if canImport(Networking)
public extension APIClient {
    /// `POST /api/v1/invoices/:id/late-fee-applied-notification`
    func sendLateFeeAppliedNotification(
        invoiceId: Int64,
        body: LateFeeAppliedNotificationRequest
    ) async throws -> LateFeeAppliedNotificationResponse {
        try await post(
            "/api/v1/invoices/\(invoiceId)/late-fee-applied-notification",
            body: body,
            as: LateFeeAppliedNotificationResponse.self
        )
    }
}
#endif
