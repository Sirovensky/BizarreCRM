import Foundation
import Observation
import Core
import Networking

// MARK: - AppointmentCancelViewModel

/// Drives the cancel confirmation sheet.
///
/// Offers two cancel paths:
///  1. Soft-delete via DELETE `/api/v1/leads/appointments/:id`
///  2. Status-update to `"cancelled"` via PUT (preserves the row for audit;
///     use this when `notifyCustomer` is true so the server's SMS hook fires).
///
/// The server side treats DELETE as a hard soft-delete (`is_deleted = 1`),
/// while PUT status=cancelled keeps the row visible in the audit log.
/// We always DELETE here (matches the server endpoint) — the "notify" flag
/// fires an SMS via a separate `POST /sms/send` call.
@MainActor
@Observable
public final class AppointmentCancelViewModel {

    // MARK: - Form

    public var notifyCustomer: Bool = true
    public var cancelReason: String = ""

    // MARK: - State

    public private(set) var isCancelling: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var cancelled: Bool = false

    // MARK: - Source

    public let appointment: Appointment

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(appointment: Appointment, api: APIClient) {
        self.appointment = appointment
        self.api = api
    }

    // MARK: - Cancel

    /// Cancels the appointment.
    ///
    /// Flow:
    /// 1. PUT status = "cancelled" (keeps audit row; required if notifying customer)
    /// 2. If `notifyCustomer` == true, fire SMS via `/sms/send` with the
    ///    cancellation template. (SMS endpoint is owned by Communications package;
    ///    we call the raw API path rather than importing Communications.)
    public func cancel() async {
        guard !isCancelling else { return }
        isCancelling = true
        errorMessage = nil
        defer { isCancelling = false }

        do {
            // Mark cancelled via status update (audit-safe)
            let statusReq = UpdateAppointmentRequest(status: AppointmentStatus.cancelled.rawValue)
            _ = try await api.updateAppointment(id: appointment.id, statusReq)

            // Optionally send SMS notification to customer
            if notifyCustomer, let customerId = appointment.customerId {
                try await sendCancellationSMS(customerId: customerId)
            }

            cancelled = true
        } catch {
            let appError = AppError.from(error)
            errorMessage = Self.message(for: appError)
            AppLog.ui.error("Appt cancel failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private func sendCancellationSMS(customerId: Int64) async throws {
        struct SMSBody: Encodable, Sendable {
            let customer_id: Int64
            let message: String
        }
        let body = SMSBody(
            customer_id: customerId,
            message: "Your appointment \"\(appointment.title ?? "")\" has been cancelled. Please contact us to reschedule."
        )
        // Fire-and-forget; ignore SMS errors so the cancel itself succeeds
        _ = try? await api.post(
            "/api/v1/sms/send",
            body: body,
            as: EmptyResponse.self
        )
    }

    private static func message(for error: AppError) -> String {
        switch error {
        case .notFound:
            return "Appointment not found — it may have already been cancelled."
        case .forbidden:
            return "You don't have permission to cancel this appointment."
        case .offline:
            return "You're offline. Connect and try again."
        case .conflict:
            return "A conflict occurred. Please refresh and try again."
        case .validation(let fieldErrors):
            return fieldErrors.values.first ?? "Check the form fields."
        default:
            return error.errorDescription ?? "An unexpected error occurred."
        }
    }
}

// MARK: - EmptyResponse

private struct EmptyResponse: Decodable, Sendable {}
