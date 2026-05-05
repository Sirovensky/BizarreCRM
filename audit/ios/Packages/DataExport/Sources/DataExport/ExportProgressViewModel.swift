import Foundation
import Observation

// MARK: - ExportProgressViewModel

@Observable
@MainActor
public final class ExportProgressViewModel {

    // MARK: - Published state

    public private(set) var job: ExportJob
    public private(set) var isPolling: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let repository: ExportRepository
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        job: ExportJob,
        repository: ExportRepository,
        pollInterval: Duration = .seconds(3)
    ) {
        self.job = job
        self.repository = repository
        self.pollInterval = pollInterval
    }

    // Note: Task is cancelled on stopPolling() — no deinit needed for @MainActor types.

    // MARK: - Public API

    public func startPolling() {
        guard !isPolling, !job.status.isTerminal else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    // MARK: - Private

    private func pollLoop() async {
        while !Task.isCancelled && !job.status.isTerminal {
            do {
                try await Task.sleep(for: pollInterval)
                guard !Task.isCancelled else { break }
                let updated = try await repository.pollExport(id: job.id)
                apply(updated)
            } catch is CancellationError {
                break
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
        isPolling = false
    }

    /// Merge polled partial job back while preserving original scope.
    private func apply(_ polled: ExportJob) {
        job = ExportJob(
            id: job.id,
            scope: job.scope,
            status: polled.status,
            progressPct: polled.progressPct,
            downloadUrl: polled.downloadUrl,
            errorMessage: polled.errorMessage,
            createdAt: job.createdAt
        )
    }
}
