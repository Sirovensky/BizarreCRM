import AppIntents
import Foundation
#if os(iOS)

/// Injected repository protocol for AppointmentEntity lookups.
public protocol AppointmentEntityRepository: Sendable {
    func appointments(for stringIds: [String]) async throws -> [AppointmentEntity]
    func nextAppointment() async throws -> AppointmentEntity?
}

enum AppointmentEntityQueryRegistry: @unchecked Sendable {
    nonisolated(unsafe) static var repo: AppointmentEntityRepository = EmptyAppointmentEntityRepository()
}

private struct EmptyAppointmentEntityRepository: AppointmentEntityRepository {
    func appointments(for stringIds: [String]) async throws -> [AppointmentEntity] { [] }
    func nextAppointment() async throws -> AppointmentEntity? { nil }
}

public enum AppointmentEntityQueryConfig {
    public static func register(_ repo: AppointmentEntityRepository) {
        AppointmentEntityQueryRegistry.repo = repo
    }

    static var repo: AppointmentEntityRepository { AppointmentEntityQueryRegistry.repo }
}

@available(iOS 16, *)
public struct AppointmentEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [AppointmentEntity] {
        try await AppointmentEntityQueryRegistry.repo.appointments(for: identifiers)
    }

    public func suggestedEntities() async throws -> [AppointmentEntity] {
        guard let next = try await AppointmentEntityQueryRegistry.repo.nextAppointment() else {
            return []
        }
        return [next]
    }
}
#endif // os(iOS)
