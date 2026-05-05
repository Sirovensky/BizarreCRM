import Foundation
import Networking

// §7.9 Installment reminder — auto-send 3 days before each installment due date.

private struct ReminderResponseEmpty: Decodable, Sendable {}

/// Value-type descriptor for a pending installment reminder job.
/// The server is authoritative for scheduling; this type is used on the
/// client to preview or manually trigger reminders.
public struct InstallmentReminderRequest: Encodable, Sendable {
    /// The specific installment item to remind about.
    public let installmentId: Int64
    /// Lead time in days before `dueDate` to send the reminder.
    public let daysBeforeDue: Int

    public init(installmentId: Int64, daysBeforeDue: Int = 3) {
        self.installmentId = installmentId
        self.daysBeforeDue = max(0, daysBeforeDue)
    }

    enum CodingKeys: String, CodingKey {
        case installmentId = "installment_id"
        case daysBeforeDue = "days_before_due"
    }
}

public extension APIClient {
    /// `POST /api/v1/invoices/installment-plans/:planId/reminders`
    /// Schedules (or immediately sends) a reminder for one installment.
    func scheduleInstallmentReminder(
        planId: Int64,
        request: InstallmentReminderRequest
    ) async throws {
        _ = try await post(
            "/api/v1/invoices/installment-plans/\(planId)/reminders",
            body: request,
            as: ReminderResponseEmpty.self
        )
    }

    /// `GET /api/v1/invoices/:invoiceId/installment-plans`
    /// Returns the active installment plan for an invoice.
    /// Throws (typically 404) when no plan has been set up yet.
    func invoiceInstallmentPlan(invoiceId: Int64) async throws -> InstallmentPlan {
        try await get(
            "/api/v1/invoices/\(invoiceId)/installment-plans",
            as: InstallmentPlan.self
        )
    }
}
