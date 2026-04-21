import AppIntents
import Foundation
#if os(iOS)

/// Injected repository protocol for CustomerEntity lookups.
public protocol CustomerEntityRepository: Sendable {
    func customers(matching query: String) async throws -> [CustomerEntity]
    func customers(for stringIds: [String]) async throws -> [CustomerEntity]
}

// MARK: - Registry (module-internal singleton)
enum CustomerEntityQueryRegistry: @unchecked Sendable {
    nonisolated(unsafe) static var repo: CustomerEntityRepository = EmptyCustomerEntityRepository()
}

private struct EmptyCustomerEntityRepository: CustomerEntityRepository {
    func customers(matching query: String) async throws -> [CustomerEntity] { [] }
    func customers(for stringIds: [String]) async throws -> [CustomerEntity] { [] }
}

/// Public configuration entry-point; call at app launch / DI bootstrap.
public enum CustomerEntityQueryConfig {
    public static func register(_ repo: CustomerEntityRepository) {
        CustomerEntityQueryRegistry.repo = repo
    }
}

@available(iOS 16, *)
public struct CustomerEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [CustomerEntity] {
        try await CustomerEntityQueryRegistry.repo.customers(for: identifiers)
    }

    public func suggestedEntities() async throws -> [CustomerEntity] {
        try await CustomerEntityQueryRegistry.repo.customers(matching: "")
    }
}

@available(iOS 16, *)
extension CustomerEntityQuery: EntityStringQuery {
    public func entities(matching string: String) async throws -> [CustomerEntity] {
        try await CustomerEntityQueryRegistry.repo.customers(matching: string)
    }
}
#endif // os(iOS)
