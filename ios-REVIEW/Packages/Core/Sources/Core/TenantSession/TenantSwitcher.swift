import Combine
import Foundation

// §79 Multi-Tenant Session management — active-session switcher

/// Manages the single "active" tenant session and broadcasts changes
/// via both a `CurrentValueSubject` (Combine) and `NotificationCenter`.
///
/// Callers that own a `TenantSwitcher` receive the authoritative active
/// descriptor and can react to switches in real time.
@MainActor
public final class TenantSwitcher: ObservableObject {

    // MARK: — Published state

    /// The currently active tenant, or `nil` if no session is live.
    @Published public private(set) var activeTenant: TenantSessionDescriptor?

    /// Combine stream of `TenantSessionEvent` for non-`@Published` consumers.
    public let events: AnyPublisher<TenantSessionEvent, Never>

    // MARK: — Private

    private let eventsSubject = PassthroughSubject<TenantSessionEvent, Never>()
    private let store: TenantSessionStore
    private let notificationCenter: NotificationCenter

    // MARK: — Init

    public init(
        store: TenantSessionStore,
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.notificationCenter = notificationCenter
        self.events = eventsSubject.eraseToAnyPublisher()
    }

    // MARK: — Public API

    /// Switches the active session to `descriptor`.
    ///
    /// - The `descriptor`'s `lastUsedAt` is updated to now before being
    ///   upserted into the store, keeping the roster ordering correct.
    /// - Emits `.tenantDidChange` on both Combine and NotificationCenter.
    public func switchTo(_ descriptor: TenantSessionDescriptor) async throws {
        let previous = activeTenant
        let touched = descriptor.touchingLastUsed()

        // Persist update (actor-isolated, safe to `await`).
        try await store.upsert(touched)

        activeTenant = touched

        let event = TenantSessionEvent.tenantDidChange(from: previous, to: touched)
        eventsSubject.send(event)
        event.post(on: notificationCenter)
    }

    /// Clears the active session without touching the persisted roster.
    ///
    /// Use this for screen-lock or "switch account" UI that shows a picker
    /// but doesn't remove any stored credentials.
    public func clearActive() {
        activeTenant = nil
        let event = TenantSessionEvent.sessionCleared
        eventsSubject.send(event)
        event.post(on: notificationCenter)
    }

    /// Removes a tenant from the roster and clears the active session
    /// if it matches the removed tenant.
    public func removeTenant(id: String) async throws {
        try await store.remove(id: id)
        if activeTenant?.id == id {
            clearActive()
        }
    }
}
