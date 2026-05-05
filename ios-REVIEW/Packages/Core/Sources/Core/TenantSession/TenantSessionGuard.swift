import Foundation

// §79 Multi-Tenant Session management — mid-flight tenant change guard

/// Gate protocol that feature operations adopt to detect tenant changes
/// that occur while a long-running operation is in flight.
///
/// Usage pattern:
/// ```swift
/// let guard = TenantOperationGuard(switcher: switcher)
/// guard.snapshot()                       // capture tenant at op start
/// // … do async work …
/// try guard.assertTenantUnchanged()      // throws if tenant changed
/// ```
public protocol TenantSessionGuard {
    /// Records the current tenant so it can be compared later.
    @MainActor mutating func snapshot()
    /// Throws `TenantSessionGuardError.tenantChanged` if the active tenant
    /// has changed since `snapshot()` was last called.
    @MainActor func assertTenantUnchanged() throws
}

// MARK: — Concrete implementation

/// Concrete guard that compares tenant IDs between snapshot and check.
public struct TenantOperationGuard: TenantSessionGuard {

    private let switcher: TenantSwitcher
    /// Tenant ID captured at `snapshot()` call.
    private var snapshotTenantID: String?

    public init(switcher: TenantSwitcher) {
        self.switcher = switcher
    }

    /// Captures the currently active tenant's ID.
    /// Must be called from `@MainActor` context (where `TenantSwitcher` lives).
    @MainActor
    public mutating func snapshot() {
        snapshotTenantID = switcher.activeTenant?.id
    }

    /// Compares the current active tenant ID to the snapshotted ID.
    /// Must be called from `@MainActor` context.
    @MainActor
    public func assertTenantUnchanged() throws {
        let currentID = switcher.activeTenant?.id
        guard currentID == snapshotTenantID else {
            throw TenantSessionGuardError.tenantChanged(
                snapshotID: snapshotTenantID,
                currentID: currentID
            )
        }
    }
}

// MARK: — Error

/// Errors thrown by `TenantSessionGuard` implementations.
public enum TenantSessionGuardError: Error, Equatable {
    /// The active tenant changed between `snapshot()` and `assertTenantUnchanged()`.
    case tenantChanged(snapshotID: String?, currentID: String?)
}
