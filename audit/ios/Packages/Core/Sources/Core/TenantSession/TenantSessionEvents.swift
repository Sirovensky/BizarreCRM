import Foundation

// §79 Multi-Tenant Session management — typed NotificationCenter events

/// Typed events emitted throughout the tenant session lifecycle.
public enum TenantSessionEvent: Sendable {

    /// Fired when a new active tenant is selected.
    case tenantDidChange(from: TenantSessionDescriptor?, to: TenantSessionDescriptor)

    /// Fired when the active session is cleared (e.g. global sign-out).
    case sessionCleared
}

// MARK: — Notification names

public extension Notification.Name {
    /// Posted by `TenantSwitcher` after the active tenant changes.
    static let tenantSessionDidChange = Notification.Name(
        "com.bizarrecrm.tenantSession.didChange"
    )
    /// Posted by `TenantSwitcher` after the active session is cleared.
    static let tenantSessionCleared = Notification.Name(
        "com.bizarrecrm.tenantSession.cleared"
    )
}

// MARK: — Notification user-info keys

public enum TenantSessionNotificationKey {
    /// `TenantSessionDescriptor?` — the tenant that was active before the switch.
    public static let previousTenant = "previousTenant"
    /// `TenantSessionDescriptor` — the tenant that is now active.
    public static let currentTenant  = "currentTenant"
}

// MARK: — Convenience posting helpers

extension TenantSessionEvent {

    /// Posts the corresponding `Notification` on the given center.
    func post(on center: NotificationCenter = .default) {
        switch self {
        case let .tenantDidChange(from, to):
            var info: [String: Any] = [TenantSessionNotificationKey.currentTenant: to]
            if let prev = from {
                info[TenantSessionNotificationKey.previousTenant] = prev
            }
            center.post(
                name: .tenantSessionDidChange,
                object: nil,
                userInfo: info
            )
        case .sessionCleared:
            center.post(name: .tenantSessionCleared, object: nil)
        }
    }
}
