import Foundation
import Observation
import Core
import Networking

// §7.2 Send by SMS ViewModel — calls POST /api/v1/sms/send with pre-filled invoice link.
// Payment-link generation is a pure URL compose step (no math); safe to implement.

@MainActor
@Observable
public final class InvoiceSMSViewModel {

    public var phone: String
    public var messageBody: String

    public enum State: Sendable, Equatable {
        case idle
        case sending
        case success
        case failed(String)
    }

    public private(set) var state: State = .idle

    @ObservationIgnored private let api: APIClient
    public let invoiceId: Int64

    /// `baseMessage` is pre-filled on init; caller may customise before sending.
    public init(api: APIClient, invoiceId: Int64, orderId: String?, customerPhone: String?, paymentLinkURL: String?) {
        self.api = api
        self.invoiceId = invoiceId
        self.phone = customerPhone ?? ""
        let displayId = orderId?.isEmpty == false ? orderId! : "your invoice"
        if let url = paymentLinkURL, !url.isEmpty {
            self.messageBody = "Hi! Please pay \(displayId) here: \(url)"
        } else {
            self.messageBody = "Hi! Your invoice \(displayId) is ready. Please contact us to pay."
        }
    }

    public var isValid: Bool {
        !phone.trimmingCharacters(in: .whitespaces).isEmpty &&
        !messageBody.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func send() async {
        guard isValid else {
            state = .failed("Enter a phone number and message.")
            return
        }
        guard case .idle = state else { return }
        state = .sending
        do {
            _ = try await api.sendSms(to: phone.trimmingCharacters(in: .whitespaces),
                                      message: messageBody.trimmingCharacters(in: .whitespaces))
            state = .success
        } catch {
            AppLog.ui.error("Invoice SMS send failed: \(error.localizedDescription, privacy: .public)")
            let appError = AppError.from(error)
            state = .failed(appError.errorDescription ?? "Failed to send SMS.")
        }
    }

    public func resetToIdle() {
        if case .failed = state { state = .idle }
    }
}
