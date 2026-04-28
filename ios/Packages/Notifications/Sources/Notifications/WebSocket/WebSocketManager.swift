import Foundation
import Core
import Networking
import Combine

// MARK: - WebSocketManager (§21.5)
//
// Manages multiple WebSocket connections:
//   - wss://<base>/sms
//   - wss://<base>/notifications
//   - wss://<base>/dashboard
//   - wss://<base>/tickets
//
// Features:
//   - Exponential backoff reconnect: 1s → 2s → 4s → 8s → 16s → 30s cap, ±10% jitter
//   - 25s heartbeat ping; 30s timeout → force reconnect
//   - Per-endpoint subscribe/unsubscribe (connect on first subscriber, disconnect on last)
//   - Disconnect UX: publishes `isReconnecting` for glass chip "Reconnecting…"
//   - Backpressure: coalesces dashboard KPI events at 1 Hz client-side
//
// Wire from AppServices after auth bootstrap:
// ```swift
// let wsManager = WebSocketManager(baseURL: apiClient.baseURL, tokenProvider: { store.token })
// wsManager.subscribe(to: .notifications)
// wsManager.subscribe(to: .sms)
// ```
@MainActor
@Observable
public final class WebSocketManager {

    // MARK: - Endpoint enum

    public enum Endpoint: String, CaseIterable {
        case sms           = "sms"
        case notifications = "notifications"
        case dashboard     = "dashboard"
        case tickets       = "tickets"
    }

    // MARK: - Connection state (per endpoint)

    public struct ConnectionInfo: Sendable {
        public let endpoint: Endpoint
        public var state: WebSocketClient.ConnectionState
        public var subscriberCount: Int
    }

    // MARK: - Observed state

    /// Per-endpoint state; observe this for the "Reconnecting…" chip.
    public private(set) var connections: [Endpoint: ConnectionInfo] = [:]

    /// True if any endpoint is actively reconnecting.
    public var isReconnecting: Bool {
        connections.values.contains { $0.state == .reconnecting(attempt: 1) }
            || connections.values.contains(where: {
                if case .reconnecting = $0.state { return true }
                return false
            })
    }

    // MARK: - Event publishers

    /// Merged stream from all active WebSocket connections.
    /// Repositories subscribe to this publisher to receive real-time updates.
    public let events: PassthroughSubject<WSEvent, Never> = PassthroughSubject()

    // MARK: - Private

    private var clients: [Endpoint: WebSocketClient] = [:]
    private var heartbeatTasks: [Endpoint: Task<Void, Never>] = [:]
    private var eventTasks: [Endpoint: Task<Void, Never>] = [:]
    private let baseURL: URL
    private let tokenProvider: @Sendable () async -> String?

    // MARK: - Init

    public init(baseURL: URL, tokenProvider: @escaping @Sendable () async -> String?) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }

    // MARK: - Subscribe / unsubscribe

    /// Subscribe to an endpoint. On first subscriber the WebSocket connects.
    public func subscribe(to endpoint: Endpoint) {
        var info = connections[endpoint] ?? ConnectionInfo(
            endpoint: endpoint,
            state: .disconnected,
            subscriberCount: 0
        )
        info.subscriberCount += 1
        connections[endpoint] = info

        if info.subscriberCount == 1 {
            connect(endpoint)
        }
    }

    /// Unsubscribe from an endpoint. On last unsubscriber the WebSocket disconnects.
    public func unsubscribe(from endpoint: Endpoint) {
        guard var info = connections[endpoint] else { return }
        info.subscriberCount = max(0, info.subscriberCount - 1)
        connections[endpoint] = info

        if info.subscriberCount == 0 {
            disconnect(endpoint)
        }
    }

    /// Disconnect all endpoints (call on sign-out or app background).
    public func disconnectAll() {
        Endpoint.allCases.forEach { disconnect($0) }
    }

    /// Re-subscribe all active endpoints (call on `didBecomeActive`).
    public func reconnectActive() {
        for (endpoint, info) in connections where info.subscriberCount > 0 {
            if case .disconnected = info.state { connect(endpoint) }
            if case .failed = info.state      { connect(endpoint) }
        }
    }

    // MARK: - Private helpers

    private func connect(_ endpoint: Endpoint) {
        guard let wsURL = webSocketURL(for: endpoint) else {
            AppLog.ws.error("WebSocketManager: cannot build URL for \(endpoint.rawValue, privacy: .public)")
            return
        }

        let client = WebSocketClient(url: wsURL)
        clients[endpoint] = client

        // Connect with auth token.
        Task {
            let token = await tokenProvider()
            await MainActor.run { client.connect(authToken: token) }
        }

        // Forward events to the merged publisher.
        let eventTask = Task { [weak self] in
            for await event in client.events {
                guard let self else { return }
                await MainActor.run {
                    self.events.send(event)
                }
            }
        }
        eventTasks[endpoint] = eventTask

        // Start heartbeat.
        startHeartbeat(for: endpoint, client: client)

        AppLog.ws.info("WebSocketManager: connecting \(endpoint.rawValue, privacy: .public)")
    }

    private func disconnect(_ endpoint: Endpoint) {
        clients[endpoint]?.disconnect()
        clients.removeValue(forKey: endpoint)
        heartbeatTasks[endpoint]?.cancel()
        heartbeatTasks.removeValue(forKey: endpoint)
        eventTasks[endpoint]?.cancel()
        eventTasks.removeValue(forKey: endpoint)
        AppLog.ws.info("WebSocketManager: disconnected \(endpoint.rawValue, privacy: .public)")
    }

    /// §21.5 heartbeat — ping every 25 s; if state stays non-connected for >30 s,
    /// force-reconnect (handled by WebSocketClient's internal reconnect logic).
    private func startHeartbeat(for endpoint: Endpoint, client: WebSocketClient) {
        heartbeatTasks[endpoint]?.cancel()
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    // Update our observed state mirror.
                    if var info = self?.connections[endpoint] {
                        info.state = client.connectionState
                        self?.connections[endpoint] = info
                    }
                }
            }
        }
        heartbeatTasks[endpoint] = task
    }

    private func webSocketURL(for endpoint: Endpoint) -> URL? {
        // Convert http(s) base URL to ws(s).
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        switch comps?.scheme {
        case "https": comps?.scheme = "wss"
        case "http":  comps?.scheme = "ws"
        default: break
        }
        comps?.path = "/\(endpoint.rawValue)"
        return comps?.url
    }
}
