import Foundation
#if canImport(Networking)
import Networking
#endif

// §7 line 1281 — Customer communication: reminder SMS/email before fee
// applied (1-3 day lead).
//
// Pure scheduler: given an invoice's due date and the policy grace window,
// computes the optimal pre-fee reminder window.
//
// Server endpoint: POST /api/v1/invoices/:id/pre-late-fee-reminder
//   Body: { lead_days, channel }

public enum LateFeeReminderScheduler {

    /// Result of the scheduling computation.
    public struct Window: Sendable, Equatable {
        /// Date on which the reminder should be sent.
        public let sendOn: Date
        /// Days between `sendOn` and the moment the late fee will first apply.
        public let leadDays: Int
        /// `true` when the current `asOf` date is exactly within the send window
        /// — the calling view-model uses this to enable the "Send pre-fee reminder" CTA.
        public let isInWindow: Bool

        public init(sendOn: Date, leadDays: Int, isInWindow: Bool) {
            self.sendOn = sendOn
            self.leadDays = leadDays
            self.isInWindow = isInWindow
        }
    }

    /// Default lead range (1-3 days) per ActionPlan spec.
    public static let kDefaultLeadDays: Int = 2
    public static let kMinLeadDays: Int = 1
    public static let kMaxLeadDays: Int = 3

    /// Computes the reminder window.
    ///
    /// - Parameters:
    ///   - dueDate: invoice due date.
    ///   - gracePeriodDays: from `LateFeePolicy.gracePeriodDays`.
    ///   - leadDays: how many days before fee-eligibility to send (clamped to 1...3).
    ///   - asOf: evaluation date.
    /// - Returns: nil when `dueDate` is nil or already past fee-eligibility.
    public static func computeWindow(
        dueDate: Date?,
        gracePeriodDays: Int,
        leadDays: Int = kDefaultLeadDays,
        asOf: Date,
        calendar: Calendar = .current
    ) -> Window? {
        guard let dueDate else { return nil }
        let lead = max(kMinLeadDays, min(kMaxLeadDays, leadDays))

        let dueMid = calendar.startOfDay(for: dueDate)
        // Fee-eligibility moment = due + grace days + 1 day.
        guard
            let feeStart = calendar.date(byAdding: .day, value: gracePeriodDays + 1, to: dueMid),
            let sendOn  = calendar.date(byAdding: .day, value: -lead, to: feeStart)
        else { return nil }

        let asMid = calendar.startOfDay(for: asOf)
        if asMid > feeStart { return nil } // already past fee-eligibility — out of scope

        let inWindow = asMid >= sendOn && asMid <= feeStart
        return Window(sendOn: sendOn, leadDays: lead, isInWindow: inWindow)
    }
}

// MARK: - Network DTOs

public struct PreLateFeeReminderRequest: Encodable, Sendable {
    public enum Channel: String, Encodable, Sendable { case sms, email, both }
    public let leadDays: Int
    public let channel: Channel

    public init(leadDays: Int, channel: Channel) {
        self.leadDays = leadDays
        self.channel = channel
    }

    enum CodingKeys: String, CodingKey {
        case leadDays = "lead_days"
        case channel
    }
}

public struct PreLateFeeReminderResponse: Decodable, Sendable {
    public let success: Bool?
    public let sentAt: String?

    enum CodingKeys: String, CodingKey {
        case success
        case sentAt = "sent_at"
    }
}

#if canImport(Networking)
public extension APIClient {
    /// `POST /api/v1/invoices/:id/pre-late-fee-reminder`
    func sendPreLateFeeReminder(
        invoiceId: Int64,
        body: PreLateFeeReminderRequest
    ) async throws -> PreLateFeeReminderResponse {
        try await post(
            "/api/v1/invoices/\(invoiceId)/pre-late-fee-reminder",
            body: body,
            as: PreLateFeeReminderResponse.self
        )
    }
}
#endif
