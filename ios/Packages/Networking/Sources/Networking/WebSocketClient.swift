import Foundation
import Starscream
import Observation
import Core

/// Server → client push channel. Per §13 we use Starscream over
/// `URLSessionWebSocketTask` because of its cleaner reconnection + TLS pinning story.
@MainActor
@Observable
public final class WebSocketClient {
    public enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case failed(String)
    }

    public private(set) var connectionState: ConnectionState = .disconnected

    private let url: URL
    private var socket: WebSocket?
    private var continuation: AsyncStream<WSEvent>.Continuation?
    private var reconnectAttempt: Int = 0
    private var intentionallyClosed: Bool = false

    public let events: AsyncStream<WSEvent>

    public init(url: URL) {
        self.url = url
        var cont: AsyncStream<WSEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    public func connect(authToken: String?) {
        intentionallyClosed = false
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if let authToken {
            req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("ios", forHTTPHeaderField: "X-Origin")

        let socket = WebSocket(request: req)
        socket.respondToPingWithPong = true
        socket.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
        self.socket = socket
        self.connectionState = .connecting
        socket.connect()
    }

    public func disconnect() {
        intentionallyClosed = true
        socket?.disconnect()
        connectionState = .disconnected
    }

    private func handle(_ event: WebSocketEvent) {
        switch event {
        case .connected:
            reconnectAttempt = 0
            connectionState = .connected
            AppLog.ws.info("WebSocket connected")
        case .disconnected(let reason, _):
            connectionState = .disconnected
            AppLog.ws.info("WebSocket disconnected: \(reason, privacy: .public)")
            if !intentionallyClosed { scheduleReconnect() }
        case .text(let string):
            if let data = string.data(using: .utf8), let decoded = decodeEvent(data) {
                continuation?.yield(decoded)
            }
        case .binary:
            break
        case .ping, .pong, .viabilityChanged, .reconnectSuggested:
            break
        case .cancelled:
            connectionState = .disconnected
        case .error(let err):
            connectionState = .failed(err?.localizedDescription ?? "unknown")
            AppLog.ws.error("WebSocket error: \(err?.localizedDescription ?? "unknown", privacy: .public)")
            scheduleReconnect()
        case .peerClosed:
            connectionState = .disconnected
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard !intentionallyClosed else { return }
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), 30.0)
        connectionState = .reconnecting(attempt: reconnectAttempt)
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !intentionallyClosed { self.socket?.connect() }
        }
    }

    private func decodeEvent(_ data: Data) -> WSEvent? {
        try? JSONDecoder.bizarre.decode(WSEvent.self, from: data)
    }
}

public enum WSEvent: Decodable, Sendable {
    case ticketCreated(TicketDTO)
    case ticketUpdated(TicketDTO)
    case smsReceived(SmsDTO)
    /// §12.2 Typing indicator — `String` is the phone number of the person currently typing.
    case smsTyping(String)
    case invoicePaid(InvoiceDTO)
    case notification(NotificationDTO)
    case unknown(String)

    enum CodingKeys: String, CodingKey { case type, data }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "ticket.created": self = .ticketCreated(try c.decode(TicketDTO.self, forKey: .data))
        case "ticket.updated": self = .ticketUpdated(try c.decode(TicketDTO.self, forKey: .data))
        case "sms.received":   self = .smsReceived(try c.decode(SmsDTO.self, forKey: .data))
        case "sms.typing":     self = .smsTyping(try c.decode(String.self, forKey: .data))
        case "invoice.paid":   self = .invoicePaid(try c.decode(InvoiceDTO.self, forKey: .data))
        case "notification":   self = .notification(try c.decode(NotificationDTO.self, forKey: .data))
        default:               self = .unknown(type)
        }
    }
}

public struct TicketDTO: Decodable, Sendable      { public let id: Int64; public let displayId: String; public let status: String; public let updatedAt: Date }
public struct SmsDTO: Decodable, Sendable         { public let id: Int64; public let threadId: Int64; public let body: String; public let createdAt: Date }
public struct InvoiceDTO: Decodable, Sendable     { public let id: Int64; public let displayId: String; public let totalCents: Int; public let paidAt: Date? }
public struct NotificationDTO: Decodable, Sendable{ public let id: Int64; public let title: String; public let body: String; public let createdAt: Date }

public extension JSONDecoder {
    static let bizarre: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
