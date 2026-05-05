import Foundation
import Factory

// MARK: - Container+Registrations
//
// Central DI wiring for BizarreCRM.
//
// Rule: Core cannot import Persistence/Networking/Sync directly (acyclic dep
// graph). Registrations therefore use a "registration closure" pattern:
//   - Core declares the protocol (or uses AnyObject).
//   - The host App (or feature package) calls `Container.shared.register(...)` to
//     supply the concrete implementation at startup.
//   - For types that already live in Core (Platform, AppLog), we register the
//     concrete type directly.
//
// Call order at app startup:
//   1. `Database.shared.open()` (Persistence — run before everything else)
//   2. `Container.registerAllServices()` (this file)
//   3. `ContainerBootstrap.registerDefaults()` (log line)
//   4. Feature-package init hooks (each pkg appends its own registrations here
//      under the "Feature package owns this registration" comments below).
//
// Advisory lock: Packages/Core/Sources/Core/Container+Registrations.swift
// Claim in GitHub comment before editing: "Claiming Container+Registrations.swift for §<N>"

// MARK: - APIClientKey

/// Type-erased key for APIClient.
/// Avoids importing Networking inside Core.
public struct APIClientKey: @unchecked Sendable {}

// MARK: - Container Extensions

public extension Container {

    // MARK: Networking layer (owned by §1 APIClient internals)
    // Concrete: Networking.APIClientImpl
    // Host App registers: Container.shared.apiClient.register { APIClientImpl() }
    var apiClient: Factory<AnyObject> {
        self { fatalError("apiClient not registered — call Container.registerAllServices()") }
            .singleton
    }

    // MARK: Persistence stores (owned by §1 DI / §20 Sync)

    // TokenStore — registered by App, concrete type lives in Persistence.
    // Feature code: @Injected(\.tokenStore) — resolves as AnyObject, cast as needed.
    var tokenStore: Factory<AnyObject> {
        self { fatalError("tokenStore not registered") }
            .singleton
    }

    // PINStore — owned by §2 Auth
    var pinStore: Factory<AnyObject> {
        self { fatalError("pinStore not registered") }
            .singleton
    }

    // SyncQueueStore — owned by §20 Sync
    var syncQueueStore: Factory<AnyObject> {
        self { fatalError("syncQueueStore not registered") }
            .singleton
    }

    // SyncStateStore — owned by §20 Sync
    var syncStateStore: Factory<AnyObject> {
        self { fatalError("syncStateStore not registered") }
            .singleton
    }

    // SyncManager — owned by §20 Sync
    var syncManager: Factory<AnyObject> {
        self { fatalError("syncManager not registered") }
            .singleton
    }

    // MARK: Domain repository placeholders
    // Each feature package (§3–§18) extends Container in its own file and
    // registers the concrete repository. These placeholders document intent
    // without creating hard import edges from Core → feature packages.
    //
    // Pattern a feature package follows:
    //   extension Container {
    //       var ticketRepository: Factory<any TicketRepositoryProtocol> {
    //           self { TicketRepositoryImpl(api: Container.shared.apiClient() as! APIClient) }
    //               .singleton
    //       }
    //   }
    //
    // §4 Tickets — see Packages/Tickets/Sources/Tickets/DIRegistrations.swift
    // §5 Customers — see Packages/Customers/Sources/Customers/DIRegistrations.swift
    // §6 Inventory — see Packages/Inventory/Sources/Inventory/DIRegistrations.swift
    // §7 Invoices — see Packages/Invoices/Sources/Invoices/DIRegistrations.swift
    // §8 Estimates — see Packages/Estimates/Sources/Estimates/DIRegistrations.swift
    // §9 Leads — see Packages/Leads/Sources/Leads/DIRegistrations.swift
    // §10 Appointments — see Packages/Appointments/Sources/Appointments/DIRegistrations.swift
    // §11 Expenses — see Packages/Expenses/Sources/Expenses/DIRegistrations.swift
    // §14 Employees — see Packages/Employees/Sources/Employees/DIRegistrations.swift
    // §39 CashSession — see Packages/Pos/Sources/Pos/DIRegistrations.swift
}

// MARK: - registerAllServices

public extension Container {

    /// Call once at app launch (before any DI resolution).
    ///
    /// Registers the foundational layer only — everything that lives in Core
    /// itself, plus wires that the host App provides via closures.
    /// Feature packages call their own `registerDomainServices()` after this.
    ///
    /// Implementation note: concrete types (Persistence, Networking) are
    /// registered from `App/AppServices.swift`, which CAN import those packages.
    /// This method is the call-site hook so the App knows where to plug in.
    static func registerAllServices() {
        // Log registration so CI / diagnostics output shows the DI layer
        // initialised correctly. Platform is in Core so we can call it directly.
        AppLog.app.info(
            "DI: Container.registerAllServices — app=\(Platform.appVersion) build=\(Platform.buildNumber)"
        )

        // Concrete registrations for types fully owned by Core:
        // (currently none — Core types use static singletons)

        // Feature package registrations are called from App/AppServices.swift
        // AFTER this returns, in phase order:
        //   Phase 0: Networking, Persistence, Sync
        //   Phase 1: Auth
        //   Phase 3+: domain repositories
    }
}
