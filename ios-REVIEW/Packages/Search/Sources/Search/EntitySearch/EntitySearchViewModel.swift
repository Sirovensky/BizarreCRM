import Foundation
import Observation
import Core

/// §18.4 — ViewModel for entity-scoped search.
/// Debounces input 200ms, cancels prior tasks, publishes `[SearchHit]`.
@MainActor
@Observable
public final class EntitySearchViewModel {

    // MARK: - Observable state

    public private(set) var hits: [SearchHit] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    public var query: String = "" {
        didSet { scheduleSearch() }
    }

    public var selectedFilter: EntityFilter = .all {
        didSet { scheduleSearch() }
    }

    // MARK: - Private

    @ObservationIgnored private let store: FTSIndexStore
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private let debounceNanoseconds: UInt64

    // MARK: - Init

    public init(store: FTSIndexStore, debounceMs: UInt64 = 200) {
        self.store = store
        self.debounceNanoseconds = debounceMs * 1_000_000
    }

    // MARK: - Public API

    public func onQueryChanged(_ new: String) {
        query = new
    }

    public func clearQuery() {
        query = ""
        hits = []
        errorMessage = nil
    }

    // MARK: - Private

    private func scheduleSearch() {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            hits = []
            errorMessage = nil
            isLoading = false
            return
        }
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            if Task.isCancelled { return }
            await self.performSearch(query: trimmed)
        }
    }

    private func performSearch(query: String) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let filter: EntityFilter? = selectedFilter == .all ? nil : selectedFilter
            let results = try await store.search(query: query, entity: filter, limit: 50)
            hits = results
        } catch {
            AppLog.ui.error("EntitySearchViewModel: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            hits = []
        }
    }
}
