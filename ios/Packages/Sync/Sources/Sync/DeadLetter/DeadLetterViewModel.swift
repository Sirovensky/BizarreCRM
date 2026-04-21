import Foundation
import Observation
import Core

// MARK: - DeadLetterViewModel

/// `@Observable` view model for DeadLetterListView.
/// Load, retry, and discard dead-lettered sync ops.
@Observable
@MainActor
public final class DeadLetterViewModel {
    // MARK: - State

    public private(set) var items: [DeadLetterItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    private let repository: DeadLetterRepository

    // MARK: - Init

    public init(repository: DeadLetterRepository = .shared) {
        self.repository = repository
    }

    // MARK: - Load

    /// Fetch all dead-letter rows from the DB.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
            AppLog.sync.error("DeadLetterViewModel.load failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Retry

    /// Re-queue the dead-letter op and refresh the list.
    public func retry(id: Int64) async {
        do {
            try await repository.retry(id)
            items.removeAll { $0.id == id }
            // Kick the drain loop through SyncManager.
            await SyncManager.shared.syncNow()
        } catch {
            errorMessage = error.localizedDescription
            AppLog.sync.error("DeadLetterViewModel.retry \(id, privacy: .public) failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Discard

    /// Permanently remove the dead-letter row.
    public func discard(id: Int64) async {
        do {
            try await repository.discard(id)
            items.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
            AppLog.sync.error("DeadLetterViewModel.discard \(id, privacy: .public) failed: \(error, privacy: .public)")
        }
    }
}
