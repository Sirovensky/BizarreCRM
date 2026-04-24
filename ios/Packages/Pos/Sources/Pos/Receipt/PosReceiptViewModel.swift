import Foundation
import Observation
import Networking
import Core

/// §Agent-E — Observable view model for the receipt confirmation screen.
///
/// Responsibilities:
/// - Pre-picks the default share channel: SMS when the customer has a phone
///   on file, Print otherwise.
/// - Coordinates the four share channels (SMS, Email, Print, AirDrop).
/// - Drives the post-sale action row (view ticket, customer profile, refund,
///   next sale).
/// - Fires the SMS / email server endpoints and surfaces send status.
///
/// Wiring: inject `PosReceiptPayload` produced by `PosTenderCoordinator`
/// when the transaction settles. The `APIClient` is optional so the type
/// remains testable without a live server.
@MainActor
@Observable
public final class PosReceiptViewModel {

    // MARK: - Share channel

    /// The four share channels available on the receipt screen.
    public enum ShareChannel: CaseIterable, Sendable, Equatable {
        case sms
        case email
        case print
        case airDrop
    }

    /// Status of an in-flight or completed send operation.
    public enum SendStatus: Equatable, Sendable {
        case idle
        case sending
        case sent(String)
        case failed(String)
    }

    // MARK: - State

    public let payload: PosReceiptPayload
    public private(set) var defaultChannel: ShareChannel
    public private(set) var sendStatus: SendStatus = .idle

    /// `true` after `nextSale()` fires so the host can dismiss + clear cart.
    public private(set) var didRequestNextSale: Bool = false

    /// `true` after `startRefund()` fires so the host can push the refund flow.
    public private(set) var didRequestRefund: Bool = false

    /// `true` after `viewTicket()` fires so the host can navigate to the ticket.
    public private(set) var didRequestViewTicket: Bool = false

    /// `true` after `viewCustomerProfile()` fires.
    public private(set) var didRequestCustomerProfile: Bool = false

    // MARK: - Deps

    @ObservationIgnored private let api: (any APIClient)?
    @ObservationIgnored private let onNextSale: @MainActor () -> Void
    @ObservationIgnored private let onRefund: @MainActor () -> Void
    @ObservationIgnored private let onViewTicket: @MainActor () -> Void
    @ObservationIgnored private let onViewCustomerProfile: @MainActor () -> Void

    // MARK: - Init

    public init(
        payload: PosReceiptPayload,
        api: (any APIClient)? = nil,
        onNextSale: @escaping @MainActor () -> Void = {},
        onRefund: @escaping @MainActor () -> Void = {},
        onViewTicket: @escaping @MainActor () -> Void = {},
        onViewCustomerProfile: @escaping @MainActor () -> Void = {}
    ) {
        self.payload = payload
        self.api = api
        self.onNextSale = onNextSale
        self.onRefund = onRefund
        self.onViewTicket = onViewTicket
        self.onViewCustomerProfile = onViewCustomerProfile

        // Pre-select SMS when the customer has a phone; fall back to Print.
        if let phone = payload.customerPhone, !phone.isEmpty {
            self.defaultChannel = .sms
        } else {
            self.defaultChannel = .print
        }
    }

    // MARK: - Share

    /// Initiates a share action on the given channel. SMS and email are
    /// server-dispatched; Print and AirDrop are local and handled by the
    /// SwiftUI layer via `PosShareLinkAdapter` — calling this for those
    /// channels is a no-op (the view wires them directly).
    public func share(channel: ShareChannel) {
        switch channel {
        case .sms:
            Task { await sendSms() }
        case .email:
            Task { await sendEmail() }
        case .print, .airDrop:
            // Print and AirDrop are handled locally by the view layer.
            AppLog.pos.debug("PosReceiptViewModel: local share channel \(String(describing: channel))")
        }
    }

    // MARK: - Post-sale actions

    public func nextSale() {
        didRequestNextSale = true
        onNextSale()
    }

    public func startRefund() {
        didRequestRefund = true
        onRefund()
    }

    public func viewTicket() {
        didRequestViewTicket = true
        onViewTicket()
    }

    public func viewCustomerProfile() {
        didRequestCustomerProfile = true
        onViewCustomerProfile()
    }

    // MARK: - SMS send

    private func sendSms() async {
        guard let phone = payload.customerPhone, !phone.isEmpty else {
            sendStatus = .failed("No customer phone on file.")
            return
        }
        sendStatus = .sending
        guard let api else {
            AppLog.pos.debug("PosReceiptViewModel: no APIClient — SMS stub")
            sendStatus = .sent("Receipt sent via SMS (stub).")
            return
        }
        do {
            let body = SendReceiptSmsRequest(invoice_id: payload.invoiceId, phone: phone)
            _ = try await api.post(
                "receipts/send-sms",
                body: body,
                as: EmptyResponse.self
            )
            sendStatus = .sent("Receipt sent to \(phone).")
        } catch {
            AppLog.pos.error("PosReceiptViewModel: SMS send failed — \(error.localizedDescription)")
            sendStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: - Email send

    private func sendEmail() async {
        guard let email = payload.customerEmail, !email.isEmpty else {
            sendStatus = .failed("No customer email on file.")
            return
        }
        sendStatus = .sending
        guard let api else {
            AppLog.pos.debug("PosReceiptViewModel: no APIClient — email stub")
            sendStatus = .sent("Receipt sent via email (stub).")
            return
        }
        do {
            let body = SendReceiptEmailRequest(invoice_id: payload.invoiceId, email: email)
            _ = try await api.post(
                "receipts/send-email",
                body: body,
                as: EmptyResponse.self
            )
            sendStatus = .sent("Receipt sent to \(email).")
        } catch {
            AppLog.pos.error("PosReceiptViewModel: email send failed — \(error.localizedDescription)")
            sendStatus = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Request types

/// Request body for `POST /api/v1/receipts/send-sms`.
private struct SendReceiptSmsRequest: Encodable, Sendable {
    let invoice_id: Int64
    let phone: String
}

/// Request body for `POST /api/v1/receipts/send-email`.
private struct SendReceiptEmailRequest: Encodable, Sendable {
    let invoice_id: Int64
    let email: String
}

/// Generic empty-data response envelope used when the server returns
/// `{ success: true }` with no `data` field.
private struct EmptyResponse: Decodable, Sendable {
    let success: Bool
}
