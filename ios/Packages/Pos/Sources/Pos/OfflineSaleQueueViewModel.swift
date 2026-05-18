import Foundation
import Observation
import Core
import Persistence
import Sync

// MARK: - OfflineSaleQueueViewModel

/// Observable view model that loads and manages the list of pending POS sync ops
/// from `SyncQueueStore`. Only surfaces ops whose `entity` is `"pos"`.
@MainActor
@Observable
public final class OfflineSaleQueueViewModel {
    public private(set) var ops: [SyncQueueRecord] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String? = nil

    public init() {}

    /// Reload the pending pos.* ops from GRDB.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await SyncQueueStore.shared.due(limit: 200)
            ops = all.filter { Self.isPosRecord($0) }
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: view popped or refresh re-fired mid-load.
            // Don't paint a fake error — next .task / pull-refresh retries.
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Trigger an immediate drain of all pending ops.
    public func retryAll() async {
        await SyncManager.shared.syncNow()
        await load()
    }

    /// Returns `true` if the record belongs to the POS domain.
    /// Extracted for testability without a live GRDB pool.
    /// `nonisolated` so tests can call it without `await`.
    public nonisolated static func isPosRecord(_ record: SyncQueueRecord) -> Bool {
        let entity = record.entity ?? ""
        let kind = record.kind ?? "\(entity).\(record.op ?? "")"
        return kind.hasPrefix("pos.")
    }
}
