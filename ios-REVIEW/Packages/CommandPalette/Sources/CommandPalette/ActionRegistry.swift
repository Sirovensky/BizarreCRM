import Foundation

// MARK: - CommandActionProvider

/// Feature packages implement this protocol and register with `ActionRegistry`
/// at app startup. CommandPalette never imports feature modules directly —
/// the app shell wires the dependency inversion.
///
/// Example (in the app shell, not in this package):
/// ```swift
/// ActionRegistry.shared.register(TicketsCommandProvider())
/// ActionRegistry.shared.register(CustomerCommandProvider())
/// let palette = CommandPaletteViewModel(
///     actions: ActionRegistry.shared.allActions(),
///     context: .none
/// )
/// ```
public protocol CommandActionProvider: AnyObject, Sendable {
    /// Stable identifier for this provider (e.g. "tickets", "customers").
    /// Used for de-duplication when a provider re-registers.
    var providerID: String { get }

    /// The actions this provider contributes.
    /// Called on registration and on `ActionRegistry.allActions()`.
    func actions() -> [CommandAction]
}

// MARK: - ActionRegistry

/// Central registry where feature packages deposit their `CommandAction`s.
///
/// The registry itself lives in `CommandPalette` and is entirely protocol-based,
/// so no feature package is imported here. Each feature package defines a
/// concrete `CommandActionProvider` in its own module and registers it at
/// app-shell startup time.
///
/// Thread-safety: all mutations are serialised through `@MainActor`.
@MainActor
public final class ActionRegistry {

    // MARK: - Singleton

    public static let shared = ActionRegistry()

    // MARK: - Private storage

    /// Ordered list of providers. `providerID` is the dedup key.
    private var providers: [any CommandActionProvider] = []

    // MARK: - Registration

    /// Register a provider. If a provider with the same `providerID` already
    /// exists it is replaced (idempotent re-registration at scene reconnect).
    public func register(_ provider: any CommandActionProvider) {
        providers.removeAll { $0.providerID == provider.providerID }
        providers.append(provider)
    }

    /// Remove the provider with the given ID. No-op if not registered.
    public func unregister(providerID: String) {
        providers.removeAll { $0.providerID == providerID }
    }

    /// Returns a flat list of all actions from all registered providers,
    /// preserving provider registration order.
    public func allActions() -> [CommandAction] {
        providers.flatMap { $0.actions() }
    }

    /// Returns all actions from a specific provider, or `[]` if not registered.
    public func actions(for providerID: String) -> [CommandAction] {
        providers.first { $0.providerID == providerID }?.actions() ?? []
    }

    /// The number of currently registered providers.
    public var providerCount: Int { providers.count }

    // MARK: - Reset (test helper)

    /// Remove all providers. Exposed for unit tests; do not call in production.
    public func _resetForTesting() {
        providers.removeAll()
    }
}
