import AppIntents
import Foundation
#if os(iOS)

/// Injected repository protocol for TicketEntity lookups.
/// Conforming type lives in the Tickets feature package.
public protocol TicketEntityRepository: Sendable {
    func tickets(matching query: String) async throws -> [TicketEntity]
    func tickets(for stringIds: [String]) async throws -> [TicketEntity]
}

// MARK: - Registry (module-internal singleton)
enum TicketEntityQueryRegistry: @unchecked Sendable {
    nonisolated(unsafe) static var repo: TicketEntityRepository = EmptyTicketEntityRepository()
}

private struct EmptyTicketEntityRepository: TicketEntityRepository {
    func tickets(matching query: String) async throws -> [TicketEntity] { [] }
    func tickets(for stringIds: [String]) async throws -> [TicketEntity] { [] }
}

/// Public configuration entry-point; call at app launch / DI bootstrap.
public enum TicketEntityQueryConfig {
    public static func register(_ repo: TicketEntityRepository) {
        TicketEntityQueryRegistry.repo = repo
    }
}

@available(iOS 16, *)
public struct TicketEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [TicketEntity] {
        try await TicketEntityQueryRegistry.repo.tickets(for: identifiers)
    }

    public func suggestedEntities() async throws -> [TicketEntity] {
        try await TicketEntityQueryRegistry.repo.tickets(matching: "")
    }
}

@available(iOS 16, *)
extension TicketEntityQuery: EntityStringQuery {
    public func entities(matching string: String) async throws -> [TicketEntity] {
        try await TicketEntityQueryRegistry.repo.tickets(matching: string)
    }
}
#endif // os(iOS)
