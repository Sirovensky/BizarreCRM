import Foundation
import Observation
import Core
import Networking

// §7.6 Email Receipt ViewModel — separated from View so it's testable without UIKit.

public struct EmailReceiptRequest: Encodable, Sendable {
    public let email: String
    public let message: String?
}

public struct SmsReceiptRequest: Encodable, Sendable {
    public let phone: String?
}

public struct ReceiptSentResult: Decodable, Sendable {
    public let success: Bool?
}

@MainActor
@Observable
public final class InvoiceEmailReceiptViewModel {

    public var emailAddress: String
    public var message: String = ""
    public var sendSmsCopy: Bool = false
    public var customerPhone: String?

    public enum State: Sendable {
        case idle
        case sending
        case success
        case failed(String)
    }

    public private(set) var state: State = .idle

    @ObservationIgnored private let api: APIClient
    public let invoiceId: Int64

    public init(api: APIClient, invoiceId: Int64, customerEmail: String? = nil, customerPhone: String? = nil) {
        self.api = api
        self.invoiceId = invoiceId
        self.emailAddress = customerEmail ?? ""
        self.customerPhone = customerPhone
    }

    public var isValid: Bool {
        let trimmed = emailAddress.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.contains("@")
    }

    public func send() async {
        guard isValid else {
            state = .failed("Enter a valid email address.")
            return
        }
        guard case .idle = state else { return }
        state = .sending

        do {
            let emailBody = EmailReceiptRequest(
                email: emailAddress.trimmingCharacters(in: .whitespaces),
                message: message.isEmpty ? nil : message
            )
            _ = try await api.post(
                "/api/v1/invoices/\(invoiceId)/email-receipt",
                body: emailBody,
                as: ReceiptSentResult.self
            )

            if sendSmsCopy {
                let smsBody = SmsReceiptRequest(phone: customerPhone)
                _ = try? await api.post(
                    "/api/v1/invoices/\(invoiceId)/sms-receipt",
                    body: smsBody,
                    as: ReceiptSentResult.self
                )
            }

            state = .success
        } catch {
            AppLog.ui.error("Email receipt failed: \(error.localizedDescription, privacy: .public)")
            let appError = AppError.from(error)
            state = .failed(appError.errorDescription ?? "Failed to send receipt.")
        }
    }

    public func resetToIdle() {
        if case .failed = state { state = .idle }
    }
}
