#if canImport(UIKit)
import Foundation
import Observation
import Networking

/// §41 — view-model backing `PosPaymentLinkSheet`. Owns the create flow,
/// the status polling loop, and the derived UI state (phase, error).
///
/// Polling rationale: the server does not publish a dedicated `/status`
/// endpoint (§74 mismatch), so we re-read `GET /payment-links/:id` at a
/// 10 s cadence while the sheet is open. When the row flips to `paid`
/// the loop cancels itself and the sheet shows the success card +
/// auto-dismisses after 3 s.
@MainActor
@Observable
public final class PosPaymentLinkViewModel {

    // MARK: - Inputs (editable fields)

    public var amountCents: Int
    public var customerEmail: String
    public var customerPhone: String
    public var description: String
    /// Days until the link expires. The sheet exposes a segmented picker
    /// (1 / 3 / 7 / 14 / 30) — 7 is the default per §41.
    public var expiryDays: Int
    public var customerId: Int64?

    // MARK: - Derived state

    public enum Phase: Equatable, Sendable {
        case editing
        case creating
        case ready(PaymentLink)
        case paid(PaymentLink)
    }

    public private(set) var phase: Phase = .editing
    public private(set) var errorMessage: String?

    /// Last polled link — kept separately from `phase.ready(...)` so
    /// transient GET failures during polling don't drop us back to the
    /// pre-create state.
    public private(set) var current: PaymentLink?

    private let api: APIClient
    private var pollTask: Task<Void, Never>?

    /// Poll interval in nanoseconds. 10 000 ms by default; tests can pass
    /// 0 to run the loop as fast as possible.
    public let pollIntervalNanos: UInt64

    public init(
        api: APIClient,
        amountCents: Int,
        customerEmail: String = "",
        customerPhone: String = "",
        customerId: Int64? = nil,
        description: String = "Invoice from BizarreCRM",
        expiryDays: Int = 7,
        pollIntervalNanos: UInt64 = 10_000_000_000
    ) {
        self.api = api
        self.amountCents = amountCents
        self.customerEmail = customerEmail
        self.customerPhone = customerPhone
        self.customerId = customerId
        self.description = description
        self.expiryDays = expiryDays
        self.pollIntervalNanos = pollIntervalNanos
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - Create

    /// Hit the server to create a link, swap `phase` to `.ready`, and
    /// kick off the polling loop. Idempotent: a second call while a link
    /// is already staged short-circuits.
    public func create() async {
        if case .creating = phase { return }
        if case .ready = phase { return }
        if case .paid = phase { return }

        phase = .creating
        errorMessage = nil
        let request = CreatePaymentLinkRequest(
            amountCents: amountCents,
            customerId: customerId,
            description: description.isEmpty ? nil : description,
            expiresAt: Self.expiryISO(daysFromNow: expiryDays),
            invoiceId: nil
        )
        do {
            let created = try await api.createPaymentLink(request)
            current = created
            phase = .ready(created)
            startPolling(id: created.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not create payment link. Please try again."
            phase = .editing
        }
    }

    // MARK: - Polling

    /// Kick off the long-lived poll loop. 10 s interval by default —
    /// conservative to avoid thrashing the server when the customer has
    /// the public page open in another tab. Cancellation-safe.
    public func startPolling(id: Int64) {
        pollTask?.cancel()
        let interval = pollIntervalNanos
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { break }
                await self?.pollOnce(id: id)
                if await self?.isTerminal() == true { break }
            }
        }
    }

    public func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func isTerminal() -> Bool {
        if case .paid = phase { return true }
        return false
    }

    private func pollOnce(id: Int64) async {
        do {
            let fresh = try await api.getPaymentLink(id: id, fallbackToken: current?.shortId)
            current = fresh
            if fresh.isPaid {
                phase = .paid(fresh)
            } else if case .ready = phase {
                // Keep phase in sync with the most recent row so the
                // status chip (active / expired / cancelled) reflects
                // what the server has.
                phase = .ready(fresh)
            }
        } catch {
            // Swallow transient errors so the poll loop keeps trying —
            // the sheet already shows "Waiting for payment" chrome.
        }
    }

    // MARK: - Helpers

    /// Build an ISO-8601 timestamp `daysFromNow` days in the future (UTC).
    /// Exposed for tests and the sheet footer.
    public static func expiryISO(daysFromNow days: Int) -> String {
        let secs = Double(max(1, days) * 86_400)
        let date = Date().addingTimeInterval(secs)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: date)
    }
}
#endif
