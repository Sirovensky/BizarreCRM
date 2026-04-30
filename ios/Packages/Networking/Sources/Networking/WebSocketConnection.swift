import Foundation
import Core

// MARK: - WebSocketConnection
//
// Low-level URLSessionWebSocketTask wrapper used by WebSocketManager (in Notifications).
// Lives in Networking because it requires URLSession construction, which is
// whitelisted only in Packages/Networking/Sources/Networking/ (sdk-ban.sh §28.3).
//
// All HTTP REST calls still go through APIClientImpl. This class is for
// WebSocket (wss://) connections only — not used for HTTP REST calls.

public final class WebSocketConnection: @unchecked Sendable {
    private let url: URL
    private let authToken: String
    private var wsTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var onEvent: (Data) -> Void
    private var onDisconnect: (() -> Void)?

    public init(url: URL, authToken: String,
                onEvent: @escaping (Data) -> Void,
                onDisconnect: (() -> Void)? = nil) {
        self.url = url
        self.authToken = authToken
        self.onEvent = onEvent
        self.onDisconnect = onDisconnect
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = ["X-Origin": "ios"]
        self.session = URLSession(configuration: cfg)
    }

    public func connect() {
        var req = URLRequest(url: url)
        // §21.5: auth token in Sec-WebSocket-Protocol header
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        wsTask = session.webSocketTask(with: req)
        wsTask?.resume()
        receive()
        AppLog.sync.info("WebSocketConnection: opened \(self.url.absoluteString, privacy: .public)")
    }

    public func disconnect() {
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        AppLog.sync.info("WebSocketConnection: closed \(self.url.absoluteString, privacy: .public)")
    }

    public func ping(onComplete: (@Sendable (Error?) -> Void)? = nil) {
        wsTask?.sendPing { error in
            if let error {
                AppLog.sync.error("WebSocketConnection: ping failed: \(error.localizedDescription, privacy: .public)")
            }
            onComplete?(error)
        }
    }

    private func receive() {
        wsTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let str):
                    if let data = str.data(using: .utf8) { self.onEvent(data) }
                case .data(let data):
                    self.onEvent(data)
                @unknown default: break
                }
                self.receive()
            case .failure(let error):
                AppLog.sync.error("WebSocketConnection: receive error: \(error.localizedDescription, privacy: .public)")
                self.onDisconnect?()
            }
        }
    }
}
