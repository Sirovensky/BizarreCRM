import Foundation
import Observation
import Core

// MARK: - DeadLetterActionCoordinator

/// Manages retry-one / retry-all / discard-one / discard-all operations
/// on the dead-letter queue. Uses `DeadLetterStoreProtocol` so the concrete
/// `DeadLetterRepository` is never imported directly — fully testable.
///
/// `@Observable` so views react to `inFlight` / `lastError` automatically.
@Observable
@MainActor
public final class DeadLetterActionCoordinator {

    // MARK: - Observable state

    /// Set of item IDs that have an in-flight operation.
    public private(set) var inFlight: Set<Int64> = []

    /// Set when a bulk operation (retry all / discard all) is running.
    public private(set) var isBulkInFlight: Bool = false

    /// Last error from any operation. Consumers should display and clear.
    public private(set) var lastError: String?

    // MARK: - Dependencies

    private let store: any DeadLetterStoreProtocol

    /// Called after any successful mutation so callers can refresh their list.
    public var onMutated: (@MainActor @Sendable () async -> Void)?

    // MARK: - Init

    public init(store: any DeadLetterStoreProtocol = DeadLetterRepository.shared) {
        self.store = store
    }

    // MARK: - Single-item actions

    /// Re-queue a single dead-letter item.
    public func retryOne(id: Int64) async {
        guard !inFlight.contains(id), !isBulkInFlight else { return }
        inFlight.insert(id)
        lastError = nil
        defer { inFlight.remove(id) }
        do {
            try await store.retry(id)
            await SyncManager.shared.syncNow()
            await onMutated?()
            AppLog.sync.info("DeadLetterActionCoordinator: retried \(id, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            AppLog.sync.error("DeadLetterActionCoordinator retryOne(\(id, privacy: .public)) failed: \(error, privacy: .public)")
        }
    }

    /// Permanently discard a single dead-letter item.
    public func discardOne(id: Int64) async {
        guard !inFlight.contains(id), !isBulkInFlight else { return }
        inFlight.insert(id)
        lastError = nil
        defer { inFlight.remove(id) }
        do {
            try await store.discard(id)
            await onMutated?()
            AppLog.sync.info("DeadLetterActionCoordinator: discarded \(id, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            AppLog.sync.error("DeadLetterActionCoordinator discardOne(\(id, privacy: .public)) failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Bulk actions

    /// Re-queue all items in `ids` sequentially.
    /// Items that fail individually are collected; first error is reported.
    public func retryAll(ids: [Int64]) async {
        guard !ids.isEmpty, !isBulkInFlight else { return }
        isBulkInFlight = true
        lastError = nil
        defer { isBulkInFlight = false }
        var firstError: String?
        for id in ids {
            do {
                try await store.retry(id)
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
                AppLog.sync.error("DeadLetterActionCoordinator retryAll item \(id, privacy: .public) failed: \(error, privacy: .public)")
            }
        }
        if let err = firstError { lastError = err }
        await SyncManager.shared.syncNow()
        await onMutated?()
        AppLog.sync.info("DeadLetterActionCoordinator: retryAll completed for \(ids.count, privacy: .public) items")
    }

    /// Permanently discard all items in `ids` sequentially.
    public func discardAll(ids: [Int64]) async {
        guard !ids.isEmpty, !isBulkInFlight else { return }
        isBulkInFlight = true
        lastError = nil
        defer { isBulkInFlight = false }
        var firstError: String?
        for id in ids {
            do {
                try await store.discard(id)
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
                AppLog.sync.error("DeadLetterActionCoordinator discardAll item \(id, privacy: .public) failed: \(error, privacy: .public)")
            }
        }
        if let err = firstError { lastError = err }
        await onMutated?()
        AppLog.sync.info("DeadLetterActionCoordinator: discardAll completed for \(ids.count, privacy: .public) items")
    }

    // MARK: - Helpers

    /// Whether a given item ID has an active in-flight operation or bulk is running.
    public func isInFlight(_ id: Int64) -> Bool {
        inFlight.contains(id) || isBulkInFlight
    }

    /// Clears the last reported error.
    public func clearError() {
        lastError = nil
    }
}
