import Foundation

// MARK: - DeadLetterStoreProtocol

/// Protocol seam that `DeadLetterActionCoordinator` and the UI layer
/// depend on instead of the concrete `DeadLetterRepository` actor.
/// This makes views and coordinators fully testable without GRDB.
public protocol DeadLetterStoreProtocol: Sendable {
    /// Fetch all dead-letter items (newest first, up to `limit`).
    func fetchAll(limit: Int) async throws -> [DeadLetterItem]
    /// Fetch a single item including its JSON payload.
    func fetchDetail(_ id: Int64) async throws -> DeadLetterItem?
    /// Re-queue item for another attempt.
    func retry(_ id: Int64) async throws
    /// Permanently remove item.
    func discard(_ id: Int64) async throws
    /// Total count for badge display.
    func count() async throws -> Int
}

// MARK: - Conformance on the real repository

extension DeadLetterRepository: DeadLetterStoreProtocol {}
