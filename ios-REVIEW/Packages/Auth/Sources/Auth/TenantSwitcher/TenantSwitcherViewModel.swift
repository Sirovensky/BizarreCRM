import Foundation
import Observation
import Core

// MARK: - View state

public enum TenantSwitcherState: Equatable, Sendable {
    case idle
    case loading
    case loaded([Tenant])
    case switching(tenantId: String)
    case failed(String)

    public static func == (lhs: TenantSwitcherState, rhs: TenantSwitcherState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading):
            return true
        case (.loaded(let a), .loaded(let b)):
            return a == b
        case (.switching(let a), .switching(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - ViewModel

/// `@Observable` ViewModel driving `TenantSwitcherView` and `TenantPickerSheet`.
///
/// Isolated to `@MainActor` so all `@Observable` state mutations are safe from SwiftUI.
@Observable
@MainActor
public final class TenantSwitcherViewModel {
    // MARK: Published state

    public private(set) var state: TenantSwitcherState = .idle
    /// Set when the user taps a tenant row — drives the confirmation alert.
    public var pendingTenant: Tenant? = nil
    /// Drives `.isPresented` of the confirmation alert.
    public var showConfirmation: Bool = false

    // MARK: Derived

    public var tenants: [Tenant] {
        if case .loaded(let list) = state { return list }
        return []
    }

    public var activeTenantId: String? {
        get async { await store.active?.id }
    }

    public var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    public var isSwitching: Bool {
        if case .switching = state { return true }
        return false
    }

    public var errorMessage: String? {
        if case .failed(let msg) = state { return msg }
        return nil
    }

    // MARK: Dependencies

    private let store: TenantStore

    // MARK: Init

    public init(store: TenantStore) {
        self.store = store
    }

    // MARK: - Intents

    /// Load tenant list from server (or return cached if already loaded).
    public func loadIfNeeded() async {
        guard case .idle = state else { return }
        await load()
    }

    public func reload() async {
        await load()
    }

    private func load() async {
        state = .loading
        do {
            let tenants = try await store.load()
            state = .loaded(tenants)
        } catch {
            state = .failed(AppError.from(error).localizedDescription)
        }
    }

    /// User tapped a tenant row — store it and show confirmation.
    public func requestSwitch(to tenant: Tenant) {
        pendingTenant = tenant
        showConfirmation = true
    }

    /// User confirmed the switch in the alert.
    public func confirmSwitch() async {
        guard let tenant = pendingTenant else { return }
        showConfirmation = false
        pendingTenant = nil

        state = .switching(tenantId: tenant.id)
        do {
            try await store.switchTo(tenant: tenant)
            // After switch, reload to reflect last-accessed ordering.
            let refreshed = try await store.load()
            state = .loaded(refreshed)
        } catch {
            state = .failed(AppError.from(error).localizedDescription)
        }
    }

    /// User cancelled the confirmation.
    public func cancelSwitch() {
        showConfirmation = false
        pendingTenant = nil
    }
}
