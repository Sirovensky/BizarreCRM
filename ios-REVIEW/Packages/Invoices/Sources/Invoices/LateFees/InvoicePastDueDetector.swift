import Foundation
#if canImport(Networking)
import Networking
#endif

// §7 line 1278 — Status change to "Past due" triggers reminder.
//
// Pure detection helper: derives whether an invoice should transition to
// "past_due" status (server-authoritative, but client uses to decide whether
// to surface "Send past-due reminder" CTA).
//
// Server endpoint: POST /api/v1/invoices/:id/past-due-reminder
//   Body: { channel: "sms" | "email" | "both" }

// MARK: - Detector (pure)

public enum InvoicePastDueDetector {

    /// Why an invoice is or is not past-due as of `asOf`.
    public struct Result: Sendable, Equatable {
        public let isPastDue: Bool
        public let daysPastDue: Int
        public let shouldSendReminder: Bool

        public init(isPastDue: Bool, daysPastDue: Int, shouldSendReminder: Bool) {
            self.isPastDue = isPastDue
            self.daysPastDue = daysPastDue
            self.shouldSendReminder = shouldSendReminder
        }
    }

    /// Default cadence for re-sending past-due reminders (in days).
    /// Server cron will gate at 1 / 7 / 14 / 30 — client uses this only for
    /// disabling the manual button when a recent reminder was sent.
    public static let kReminderCooldownDays: Int = 3

    /// Derives past-due state. Pure.
    ///
    /// - Parameters:
    ///   - balanceCents: Outstanding balance.
    ///   - dueDate: Invoice due date; nil → never past due.
    ///   - status: Current server status (e.g. "unpaid", "partial", "paid", "void", "past_due").
    ///   - asOf: Evaluation moment.
    ///   - lastReminderSentAt: When the last past-due reminder was sent (nil if never).
    public static func evaluate(
        balanceCents: Cents,
        dueDate: Date?,
        status: String?,
        asOf: Date,
        lastReminderSentAt: Date? = nil,
        calendar: Calendar = .current
    ) -> Result {
        let normalizedStatus = (status ?? "").lowercased()
        guard normalizedStatus != "void", normalizedStatus != "paid" else {
            return Result(isPastDue: false, daysPastDue: 0, shouldSendReminder: false)
        }
        guard balanceCents > 0, let due = dueDate else {
            return Result(isPastDue: false, daysPastDue: 0, shouldSendReminder: false)
        }
        let dueMidnight = calendar.startOfDay(for: due)
        let asMidnight  = calendar.startOfDay(for: asOf)
        let days = calendar.dateComponents([.day], from: dueMidnight, to: asMidnight).day ?? 0
        guard days > 0 else {
            return Result(isPastDue: false, daysPastDue: 0, shouldSendReminder: false)
        }
        let cooldownPassed: Bool = {
            guard let last = lastReminderSentAt else { return true }
            let lastMid = calendar.startOfDay(for: last)
            let sinceLast = calendar.dateComponents([.day], from: lastMid, to: asMidnight).day ?? 0
            return sinceLast >= kReminderCooldownDays
        }()
        return Result(isPastDue: true, daysPastDue: days, shouldSendReminder: cooldownPassed)
    }
}

// MARK: - Network DTOs

public struct PastDueReminderRequest: Encodable, Sendable {
    public enum Channel: String, Encodable, Sendable {
        case sms, email, both
    }
    public let channel: Channel

    public init(channel: Channel) { self.channel = channel }
}

public struct PastDueReminderResponse: Decodable, Sendable {
    public let success: Bool?
    public let sentAt: String?

    enum CodingKeys: String, CodingKey {
        case success
        case sentAt = "sent_at"
    }
}

#if canImport(Networking)
public extension APIClient {
    /// `POST /api/v1/invoices/:id/past-due-reminder`
    func sendPastDueReminder(invoiceId: Int64, body: PastDueReminderRequest) async throws -> PastDueReminderResponse {
        try await post(
            "/api/v1/invoices/\(invoiceId)/past-due-reminder",
            body: body,
            as: PastDueReminderResponse.self
        )
    }
}
#endif
