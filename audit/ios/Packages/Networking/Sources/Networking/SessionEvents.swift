import Foundation

/// Broadcast channel for session-lifecycle events. APIClient posts
/// `sessionRevoked` when an authenticated request returns 401 — AppState
/// listens and flips the user back to the login screen.
///
/// Single-subscriber (AppState). Continuation buffers the latest event only.
public enum SessionEvents {
    public enum Event: Sendable {
        case sessionRevoked
    }

    private static let pair: (stream: AsyncStream<Event>, continuation: AsyncStream<Event>.Continuation) = {
        AsyncStream.makeStream(of: Event.self, bufferingPolicy: .bufferingNewest(1))
    }()

    public static var stream: AsyncStream<Event> { pair.stream }

    public static func post(_ event: Event) {
        pair.continuation.yield(event)
    }
}
