import Foundation
import Networking
import Core

// MARK: - ConflictResolutionRepositoryProtocol

/// Testable interface for the conflict resolution data layer.
public protocol ConflictResolutionRepositoryProtocol: Sendable {
    /// Fetch a paginated list of conflicts from `GET /api/v1/sync/conflicts`.
    func listConflicts(
        status: ConflictStatus?,
        entityKind: String?,
        page: Int,
        pageSize: Int
    ) async throws -> ConflictListEnvelope

    /// Fetch a single conflict with full JSON payloads from `GET /api/v1/sync/conflicts/:id`.
    func conflictDetail(id: Int) async throws -> ConflictItem

    /// Resolve a conflict via `POST /api/v1/sync/conflicts/:id/resolve`.
    func resolveConflict(id: Int, resolution: Resolution, notes: String?) async throws -> ResolveConflictResult
}

// MARK: - ConflictResolutionRepository

/// Live implementation backed by `APIClient`.
///
/// Usage: inject via `ConflictResolutionRepositoryProtocol` in the ViewModel;
/// use `.shared` in production.
public actor ConflictResolutionRepository: ConflictResolutionRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - List

    /// `GET /api/v1/sync/conflicts`
    public func listConflicts(
        status: ConflictStatus? = nil,
        entityKind: String? = nil,
        page: Int = 1,
        pageSize: Int = 25
    ) async throws -> ConflictListEnvelope {
        do {
            return try await client.listConflicts(
                status: status,
                entityKind: entityKind,
                page: page,
                pageSize: pageSize
            )
        } catch {
            AppLog.sync.error("ConflictResolutionRepository.listConflicts failed: \(error, privacy: .public)")
            throw error
        }
    }

    // MARK: - Detail

    /// `GET /api/v1/sync/conflicts/:id`
    public func conflictDetail(id: Int) async throws -> ConflictItem {
        do {
            return try await client.conflictDetail(id: id)
        } catch {
            AppLog.sync.error("ConflictResolutionRepository.conflictDetail(\(id, privacy: .public)) failed: \(error, privacy: .public)")
            throw error
        }
    }

    // MARK: - Resolve

    /// `POST /api/v1/sync/conflicts/:id/resolve`
    ///
    /// Resolution is **declarative only** — the server records the decision for
    /// audit but does NOT write the chosen version back to the entity table.
    /// After calling this, the caller must replay the winning version via the
    /// relevant entity endpoint (e.g. `PUT /api/v1/tickets/:id`).
    public func resolveConflict(
        id: Int,
        resolution: Resolution,
        notes: String? = nil
    ) async throws -> ResolveConflictResult {
        do {
            let result = try await client.resolveConflict(
                id: id,
                resolution: resolution,
                notes: notes
            )
            AppLog.sync.info("Conflict \(id, privacy: .public) resolved: \(resolution.rawValue, privacy: .public)")
            return result
        } catch {
            AppLog.sync.error("ConflictResolutionRepository.resolveConflict(\(id, privacy: .public)) failed: \(error, privacy: .public)")
            throw error
        }
    }
}
