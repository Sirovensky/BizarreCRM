import Foundation
import Observation
import Networking
import Core

/// §Agent-E / §16.24 — Observable view model for the receipt confirmation screen.
///
/// Responsibilities:
/// - Pre-picks the default share channel: SMS when the customer has a phone
///   on file, Print otherwise.
/// - Coordinates the four share channels (SMS, Email, Print, AirDrop).
/// - Drives the post-sale action row (view ticket, customer profile, refund,
///   next sale).
/// - Fires the send-receipt server endpoint and surfaces send status.
/// - §16.24: Auto-dismiss countdown (10s); cancelable by user interaction.
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

    // MARK: - §16.24 — Auto-dismiss countdown

    /// Seconds remaining before auto-navigating to `PosEntryView`.
    /// Counts down from `autoDismissTotalSeconds`. Nil when cancelled.
    public private(set) var autoDismissSecondsRemaining: Int? = nil

    /// Total countdown duration (10 seconds per §16.24).
    public let autoDismissTotalSeconds: Int = 10

    @ObservationIgnored private var countdownTask: Task<Void, Never>?

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
        cancelAutoDismiss()
        switch channel {
        case .sms:
            Task { await sendViaNotificationsEndpoint(channel: "sms") }
        case .email:
            Task { await sendViaNotificationsEndpoint(channel: "email") }
        case .print, .airDrop:
            // Print and AirDrop are handled locally by the view layer.
            AppLog.pos.debug("PosReceiptViewModel: local share channel \(String(describing: channel))")
        }
    }

    // MARK: - Post-sale actions

    public func nextSale() {
        cancelAutoDismiss()
        didRequestNextSale = true
        onNextSale()
    }

    public func startRefund() {
        cancelAutoDismiss()
        didRequestRefund = true
        onRefund()
    }

    public func viewTicket() {
        cancelAutoDismiss()
        didRequestViewTicket = true
        onViewTicket()
    }

    public func viewCustomerProfile() {
        cancelAutoDismiss()
        didRequestCustomerProfile = true
        onViewCustomerProfile()
    }

    // MARK: - §16.24 — Auto-dismiss

    /// Start the 10-second countdown. Fires `onNextSale` when it reaches 0.
    /// Any user interaction should call `cancelAutoDismiss()`.
    public func startAutoDismissCountdown() {
        guard countdownTask == nil else { return }
        autoDismissSecondsRemaining = autoDismissTotalSeconds
        countdownTask = Task {
            var remaining = autoDismissTotalSeconds
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
                autoDismissSecondsRemaining = remaining
            }
            guard !Task.isCancelled else { return }
            // Countdown complete — navigate to next sale.
            AppLog.pos.info("PosReceiptViewModel: auto-dismiss countdown complete")
            nextSale()
        }
    }

    /// Cancel the countdown (user tapped somewhere).
    public func cancelAutoDismiss() {
        countdownTask?.cancel()
        countdownTask = nil
        autoDismissSecondsRemaining = nil
    }

    // MARK: - §16.24 — Send receipt via notifications endpoint
    //
    // Server: POST /api/v1/notifications/send-receipt
    // Body: { invoiceId, channel: 'email'|'sms', destination }
    // SMS: disabled until POS-SMS-001. Email: enabled.

    private func sendViaNotificationsEndpoint(channel: String) async {
        let destination: String?
        switch channel {
        case "sms":   destination = payload.customerPhone
        case "email": destination = payload.customerEmail
        default:      destination = nil
        }

        guard let dest = destination, !dest.isEmpty else {
            sendStatus = .failed("No contact on file for \(channel).")
            return
        }

        sendStatus = .sending

        guard let api else {
            AppLog.pos.debug("PosReceiptViewModel: no APIClient — \(channel) stub")
            sendStatus = .sent("Receipt sent via \(channel) (stub).")
            return
        }

        do {
            // Typed wrapper in APIClient+CashRegister.swift (§20 containment).
            _ = try await api.postSendReceipt(
                invoiceId: payload.invoiceId,
                channel: channel,
                destination: dest
            )
            sendStatus = .sent("Receipt sent to \(dest).")
            AppLog.pos.info("PosReceiptViewModel: receipt sent via \(channel, privacy: .public) invoice=\(self.payload.invoiceId, privacy: .public)")
        } catch {
            AppLog.pos.error("PosReceiptViewModel: \(channel) send failed — \(error.localizedDescription)")
            sendStatus = .failed(error.localizedDescription)
        }
    }
}
