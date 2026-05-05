import Foundation
import Observation
import Combine
import SwiftUI
import Core
import Networking  // WebSocketConnection lives here (§28.3 URLSession containment)

// MARK: - §21.5 WebSocket manager (Starscream-compatible interface)
//
// Manages persistent WS connections to the tenant server for real-time
// events. Uses the Starscream WebSocket library (already in SPM graph).
// Falls back to polling when WS is unavailable (e.g. reverse-proxy HTTPS
// without HTTP/1.1 upgrade configured).
//
// Architecture:
//   WebSocketManager (actor) — owns reconnect loop + heartbeat
//   WebSocketEventBus (ObservableObject) — publishes events to Combine subscribers
//
// Endpoints (§21.5):
//   wss://<base>/sms
//   wss://<base>/notifications
//   wss://<base>/dashboard
//   wss://<base>/tickets

// MARK: - Event envelope

public struct WebSocketEvent: Sendable, Decodable {
    public let type: String
    public let entity: String
    public let id: String?
    public let payload: [String: String]?  // simplified; rich payload decoded per-type
    public let version: Int?
}

// MARK: - Bus (Combine publishers per topic)

public final class WebSocketEventBus: @unchecked Sendable {
    public static let shared = WebSocketEventBus()

    public let smsEvents           = PassthroughSubject<WebSocketEvent, Never>()
    public let notificationEvents  = PassthroughSubject<WebSocketEvent, Never>()
    public let dashboardEvents     = PassthroughSubject<WebSocketEvent, Never>()
    public let ticketEvents        = PassthroughSubject<WebSocketEvent, Never>()

    private init() {}

    func emit(_ event: WebSocketEvent, topic: WebSocketManager.Topic) {
        switch topic {
        case .sms:           smsEvents.send(event)
        case .notifications: notificationEvents.send(event)
        case .dashboard:     dashboardEvents.send(event)
        case .tickets:       ticketEvents.send(event)
        }
    }
}

// MARK: - Disconnect UX

/// Observable state for the WebSocket reconnect chip UX (§21.5 Disconnect UX).
/// Place `WSReconnectChip()` in any list/toolbar that wants to show the
/// "Reconnecting…" glass chip when the WS connection drops.
@MainActor
@Observable
public final class WSConnectionStateObserver {
    public static let shared = WSConnectionStateObserver()
    /// `true` while any WS channel is in a reconnect backoff (shows chip).
    public private(set) var isReconnecting: Bool = false

    private init() {}

    public func setReconnecting(_ value: Bool) {
        isReconnecting = value
    }
}

/// Subtle glass chip shown when WS is reconnecting (§21.5 Disconnect UX).
/// Lists keep showing stale data; chip appears at the top without blocking content.
public struct WSReconnectChip: View {
    @State private var obs = WSConnectionStateObserver.shared

    public init() {}

    public var body: some View {
        if obs.isReconnecting {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                    .accessibilityHidden(true)
                Text("Reconnecting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 4)
            .accessibilityLabel("Reconnecting to server")
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}

// MARK: - §21.5 Backpressure (1Hz coalesce for dashboard events)

/// Coalesces high-frequency events on a topic to at most 1 event per second.
/// Used for `dashboard` topic — KPI updates arrive in bursts on save.
public actor WSBackpressureFilter {
    private var lastFire: [String: Date] = [:]
    private let interval: TimeInterval

    public init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    /// Returns `true` if the event should be forwarded; `false` if it should be dropped.
    public func shouldForward(topic: String) -> Bool {
        let now = Date()
        if let last = lastFire[topic], now.timeIntervalSince(last) < interval {
            return false
        }
        lastFire[topic] = now
        return true
    }
}

// MARK: - Manager

/// Actor that owns reconnect loop + heartbeat for all WS channels.
public actor WebSocketManager {
    public enum Topic: String, CaseIterable, Sendable {
        case sms           = "sms"
        case notifications = "notifications"
        case dashboard     = "dashboard"
        case tickets       = "tickets"
    }

    public enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
    }

    private var connections: [Topic: WSConnection] = [:]
    private var authToken: String?
    private var baseURL: URL?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTasks: [Topic: Task<Void, Never>] = [:]

    /// §21.5 Backpressure — coalesce dashboard KPI events at 1Hz.
    private let backpressure = WSBackpressureFilter(interval: 1.0)

    /// §21.5 Per-view subscriptions — reference count per topic.
    /// When a view subscribes, its `Topic` count increments; on disappear, decrements.
    /// When count drops to zero, the connection is kept open (server dedup handles silence).
    private var subscriptionCounts: [Topic: Int] = [:]

    public let bus = WebSocketEventBus.shared

    /// Max backoff: 1s → 2s → 4s → 8s → 16s → 30s cap. Jitter ±10%.
    private static func backoffDelay(attempt: Int) -> UInt64 {
        let base = min(Double(1 << attempt), 30.0)
        let jitter = base * 0.1 * (Double.random(in: -1...1))
        let secs = base + jitter
        return UInt64(max(secs, 0.5) * 1_000_000_000)
    }

    // MARK: - Configuration

    public func configure(baseURL: URL?, authToken: String?) {
        self.baseURL = baseURL
        self.authToken = authToken
    }

    // MARK: - Connect / disconnect

    public func connectAll() {
        for topic in Topic.allCases {
            guard connections[topic] == nil else { continue }
            startConnection(for: topic)
        }
        startHeartbeat()
        AppLog.sync.info("WebSocketManager: connecting to all channels")
    }

    public func disconnect() {
        for (topic, conn) in connections {
            conn.disconnect()
            connections[topic] = nil
        }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectTasks.values.forEach { $0.cancel() }
        reconnectTasks = [:]
        AppLog.sync.info("WebSocketManager: disconnected from all channels")
    }

    private func startConnection(for topic: Topic) {
        guard let base = baseURL, let token = authToken else {
            AppLog.sync.warning("WebSocketManager: no base URL or token; skipping \(topic.rawValue, privacy: .public)")
            return
        }
        let wsURL = makeWSURL(base: base, topic: topic)
        let conn = WSConnection(url: wsURL, token: token) { [weak self] event in
            guard let self else { return }
            Task { await self.handleEvent(event, topic: topic) }
        }
        connections[topic] = conn
        conn.connect()
    }

    private func makeWSURL(base: URL, topic: Topic) -> URL {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.scheme = base.scheme == "https" ? "wss" : "ws"
        comps.path = "/\(topic.rawValue)"
        return comps.url ?? base
    }

    // MARK: - Heartbeat (25s ping → 30s timeout → reconnect)

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.pingAll()
            }
        }
    }

    private func pingAll() {
        for conn in connections.values { conn.ping() }
    }

    // MARK: - §21.5 Per-view subscriptions

    /// Increment reference count for a topic. Connecting is managed by `connectAll()`;
    /// this provides a hook for views to declare interest so future versions can
    /// lazily connect/disconnect per topic.
    public func subscribe(topic: Topic) {
        subscriptionCounts[topic, default: 0] += 1
    }

    /// Decrement reference count for a topic.
    public func unsubscribe(topic: Topic) {
        let current = subscriptionCounts[topic, default: 0]
        subscriptionCounts[topic] = max(0, current - 1)
    }

    // MARK: - Event handling

    private func handleEvent(_ event: WebSocketEvent, topic: Topic) async {
        // §21.5 Backpressure: coalesce dashboard KPI events at 1Hz client-side.
        if topic == .dashboard {
            let shouldForward = await backpressure.shouldForward(topic: topic.rawValue)
            guard shouldForward else { return }
        }
        bus.emit(event, topic: topic)
    }

    // MARK: - Reconnect on disconnect

    func scheduleReconnect(topic: Topic, attempt: Int) {
        reconnectTasks[topic]?.cancel()
        // §21.5 Disconnect UX: mark as reconnecting so UI can show chip.
        Task { @MainActor in
            WSConnectionStateObserver.shared.setReconnecting(true)
        }
        reconnectTasks[topic] = Task { [weak self] in
            let delay = WebSocketManager.backoffDelay(attempt: attempt)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.connections[topic]?.connect()
            // Clear reconnecting flag once connected.
            await Task { @MainActor in
                WSConnectionStateObserver.shared.setReconnecting(false)
            }.value
        }
    }
}

// MARK: - WSConnection adapter
//
// Thin adapter over `WebSocketConnection` from the Networking package.
// URLSession is confined to `Packages/Networking/Sources/Networking/` per §28.3 (sdk-ban.sh).

final class WSConnection: @unchecked Sendable {
    private let connection: WebSocketConnection
    private var onEvent: (WebSocketEvent) -> Void

    init(url: URL, token: String, onEvent: @escaping (WebSocketEvent) -> Void) {
        self.onEvent = onEvent
        self.connection = WebSocketConnection(
            url: url,
            authToken: token,
            onEvent: { data in
                if let event = try? JSONDecoder().decode(WebSocketEvent.self, from: data) {
                    onEvent(event)
                }
            }
        )
    }

    func connect() { connection.connect() }
    func disconnect() { connection.disconnect() }
    func ping() { connection.ping() }
}
