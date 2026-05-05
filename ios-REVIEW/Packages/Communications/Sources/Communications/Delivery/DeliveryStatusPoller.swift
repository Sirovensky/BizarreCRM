import Foundation
import Observation
import Networking
import Core

// MARK: - DeliveryStatusPoller

/// Polls `GET /sms/messages/:id/status` on a fixed interval for up to `maxDuration`
/// seconds after send, then stops automatically. Stops early when a terminal status is reached.
///
/// Thread model: `@Observable` + `@MainActor` so SwiftUI can bind directly.
@MainActor
@Observable
public final class DeliveryStatusPoller: Sendable {

    // MARK: - State

    public private(set) var currentStatus: DeliveryStatus = .sent
    public private(set) var isPolling: Bool = false
    public private(set) var deliveryResponse: DeliveryStatusResponse?

    // MARK: - Config

    private let messageId: Int64
    private let api: APIClient
    private let pollInterval: TimeInterval
    private let maxDuration: TimeInterval

    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        messageId: Int64,
        api: APIClient,
        pollInterval: TimeInterval = 5.0,
        maxDuration: TimeInterval = 30.0
    ) {
        self.messageId = messageId
        self.api = api
        self.pollInterval = pollInterval
        self.maxDuration = maxDuration
    }

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - Control

    /// Starts polling. Safe to call multiple times — cancels any existing poll.
    public func startPolling() async {
        pollingTask?.cancel()
        isPolling = true

        pollingTask = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(self.maxDuration)
            while Date() < deadline, !Task.isCancelled {
                do {
                    let resp = try await self.api.smsMessageStatus(messageId: self.messageId)
                    await MainActor.run {
                        self.deliveryResponse = resp
                        self.currentStatus = resp.status
                    }
                    if resp.status.isTerminal {
                        break
                    }
                } catch {
                    AppLog.ui.error("DeliveryStatusPoller fetch error: \(error.localizedDescription, privacy: .public)")
                }
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
            await MainActor.run { self.isPolling = false }
        }
    }

    /// Cancels polling immediately.
    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }
}
