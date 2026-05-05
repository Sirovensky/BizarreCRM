import AppIntents
import Foundation
#if os(iOS)

// MARK: - CustomerIntentResolver

/// Protocol seam for resolving a `CustomerEntity` from a raw string input
/// (name, phone, or email). The concrete implementation lives in the Customers
/// feature package and is wired at app launch via `CustomerIntentResolverConfig`.
public protocol CustomerIntentResolver: Sendable {
    /// Return the best-matching customer for `input`, or `nil` if none found.
    func resolveCustomer(for input: String) async throws -> CustomerEntity?

    /// Return all customers whose names or phone numbers contain `query`.
    func suggestCustomers(matching query: String) async throws -> [CustomerEntity]
}

// MARK: Registry

enum CustomerIntentResolverRegistry: @unchecked Sendable {
    nonisolated(unsafe) static var resolver: CustomerIntentResolver = NoOpCustomerIntentResolver()
}

private struct NoOpCustomerIntentResolver: CustomerIntentResolver {
    func resolveCustomer(for input: String) async throws -> CustomerEntity? { nil }
    func suggestCustomers(matching query: String) async throws -> [CustomerEntity] { [] }
}

/// Public configuration entry-point; call at app launch / DI bootstrap before
/// any Shortcuts or Siri invocation can reach the intent.
public enum CustomerIntentResolverConfig {
    public static func register(_ resolver: CustomerIntentResolver) {
        CustomerIntentResolverRegistry.resolver = resolver
    }
}

// MARK: - TicketIntentResolver

/// Protocol seam for resolving a `TicketEntity` from a raw order-ID string.
/// The concrete implementation lives in the Tickets feature package and is
/// wired at app launch via `TicketIntentResolverConfig`.
public protocol TicketIntentResolver: Sendable {
    /// Return the ticket matching the given order ID (e.g. "T-042"), or `nil`.
    func resolveTicket(forOrderId orderId: String) async throws -> TicketEntity?

    /// Return recently-accessed or open tickets for Shortcuts suggestions.
    func suggestTickets() async throws -> [TicketEntity]
}

// MARK: Registry

enum TicketIntentResolverRegistry: @unchecked Sendable {
    nonisolated(unsafe) static var resolver: TicketIntentResolver = NoOpTicketIntentResolver()
}

private struct NoOpTicketIntentResolver: TicketIntentResolver {
    func resolveTicket(forOrderId orderId: String) async throws -> TicketEntity? { nil }
    func suggestTickets() async throws -> [TicketEntity] { [] }
}

/// Public configuration entry-point; call at app launch / DI bootstrap.
public enum TicketIntentResolverConfig {
    public static func register(_ resolver: TicketIntentResolver) {
        TicketIntentResolverRegistry.resolver = resolver
    }
}
#endif // os(iOS)
