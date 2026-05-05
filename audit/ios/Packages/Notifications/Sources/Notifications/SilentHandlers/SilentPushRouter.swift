import Foundation
import Core

// MARK: - SilentPushHandlerProtocol

/// Protocol that feature packages implement and register with `SilentPushRouter`
/// to respond to typed silent push payloads.
///
/// Handlers are registered at app bootstrap (DI phase) and must be `Sendable`
/// so the router can call them from any actor context.
///
/// ```swift
/// // In the Tickets feature package:
/// struct TicketsRefreshHandler: SilentPushHandlerProtocol {
///     func canHandle(_ payload: SilentPushPayloadType) -> Bool {
///         if case .dataRefresh(let e) = payload { return e.kind == "ticket" }
///         return false
///     }
///     func handle(_ payload: SilentPushPayloadType) async {
///         await TicketsRepository.shared.refresh(entityId: payload.envelope.entityId)
///     }
/// }
/// ```
public protocol SilentPushHandlerProtocol: Sendable {

    /// Return `true` when this handler is responsible for the given payload.
    /// The router calls handlers in registration order and stops at the first match.
    func canHandle(_ payload: SilentPushPayloadType) -> Bool

    /// Perform the work for the payload. Called only when `canHandle` returned `true`.
    /// Must complete within iOS's 30-second background-task budget.
    func handle(_ payload: SilentPushPayloadType) async
}

// MARK: - SilentPushRouter

/// Actor-isolated registry + dispatcher for typed silent push payloads.
///
/// Feature packages register handlers at DI bootstrap:
/// ```swift
/// await SilentPushRouter.shared.register(TicketsRefreshHandler())
/// await SilentPushRouter.shared.register(SmsRefreshHandler())
/// ```
///
/// The app-delegate (or `SilentPushHandler.handle`) calls:
/// ```swift
/// let routed = await SilentPushRouter.shared.route(payload)
/// ```
///
/// Routing is *first-match*: handlers are tried in registration order.
/// Unknown payloads fall through to a configurable fallback closure (defaults
/// to a debug log only so production is always safe).
public actor SilentPushRouter {

    // MARK: - Shared

    public static let shared = SilentPushRouter()

    // MARK: - State

    private var handlers: [any SilentPushHandlerProtocol] = []

    /// Optional fallback invoked when no registered handler accepts the payload.
    /// Set by the app shell if a full-sync fallback is desired.
    private var fallback: (@Sendable (SilentPushPayloadType) async -> Void)?

    // MARK: - Init

    public init() {}

    // MARK: - Registration

    /// Register a handler. Appended at the end of the match chain.
    public func register(_ handler: some SilentPushHandlerProtocol) {
        handlers.append(handler)
    }

    /// Replace all registered handlers (useful in tests).
    public func resetHandlers() {
        handlers = []
    }

    /// Set a fallback closure invoked when no handler matches.
    public func setFallback(_ closure: @escaping @Sendable (SilentPushPayloadType) async -> Void) {
        fallback = closure
    }

    // MARK: - Routing

    /// Decode the APNs `userInfo` and route to the first matching handler.
    ///
    /// - Returns: `true` if a handler accepted the payload; `false` if the
    ///   fallback was invoked or the push was not a silent push.
    @discardableResult
    public func route(userInfo: [AnyHashable: Any]) async -> Bool {
        guard let payload = SilentPushPayloadType.decode(from: userInfo) else {
            AppLog.sync.debug("SilentPushRouter: ignored non-silent push")
            return false
        }
        return await route(payload)
    }

    /// Route a pre-decoded payload. Exposed for unit testing.
    @discardableResult
    public func route(_ payload: SilentPushPayloadType) async -> Bool {
        // Discard expired payloads immediately.
        guard !payload.envelope.isExpired else {
            AppLog.sync.debug(
                "SilentPushRouter: dropped expired payload kind=\(payload.envelope.kind, privacy: .public)"
            )
            return false
        }

        for handler in handlers where handler.canHandle(payload) {
            AppLog.sync.info(
                "SilentPushRouter: routing kind=\(payload.envelope.kind, privacy: .public) to \(String(describing: type(of: handler)), privacy: .public)"
            )
            await handler.handle(payload)
            return true
        }

        // No handler matched — invoke fallback or log.
        if let fallback {
            AppLog.sync.info(
                "SilentPushRouter: no handler for kind=\(payload.envelope.kind, privacy: .public), invoking fallback"
            )
            await fallback(payload)
        } else {
            AppLog.sync.debug(
                "SilentPushRouter: no handler and no fallback for kind=\(payload.envelope.kind, privacy: .public)"
            )
        }
        return false
    }
}
