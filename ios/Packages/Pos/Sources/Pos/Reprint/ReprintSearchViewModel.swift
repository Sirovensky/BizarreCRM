import Foundation
import Observation
import Core
import Networking

/// §16 Reprint — drives `ReprintSearchView`.
///
/// Searches past sales by receipt number, customer phone, or customer name.
/// Endpoint: `GET /sales/search?q=<query>` — returns `[SaleSummary]`
/// wrapped in the standard `{ success, data, message }` envelope.
///
/// **State machine:**
/// `.idle` → user types → `.searching` → API returns → `.results([])` or `.results([…])` or `.error(…)`.
/// Debounce: 400 ms so we don't hammer the server on every keystroke.
/// API calls go through `ReprintRepository` (§20 containment).
@MainActor
@Observable
public final class ReprintSearchViewModel {

    // MARK: - Published state

    public enum SearchState: Equatable {
        case idle
        case searching
        case results([SaleSummary])
        case error(String)
    }

    public private(set) var searchState: SearchState = .idle
    public var query: String = "" {
        didSet { scheduleSearch() }
    }

    // MARK: - Dependencies

    private let repository: any ReprintRepository

    // MARK: - Private

    private var debounceTask: Task<Void, Never>?
    /// BUGHUNT-2026-05-17: the previous version launched an untracked `Task`
    /// inside `performSearch`, so cancelling the debounce did not cancel the
    /// in-flight network call. When a slow search for "iPhone" finished
    /// AFTER a fast search for "iPhone 14", the older results overwrote the
    /// newer ones in `searchState`. Tracking the task lets us cancel it
    /// before starting the next search.
    private var searchTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(400)

    /// Designated init — accepts any `ReprintRepository`.
    public init(repository: any ReprintRepository) {
        self.repository = repository
    }

    /// Convenience init for live production use.
    public convenience init(api: APIClient) {
        self.init(repository: ReprintRepositoryImpl(api: api))
    }

    // MARK: - Public API

    /// Explicitly trigger a search (e.g. on Return key press).
    public func search() {
        debounceTask?.cancel()
        debounceTask = nil
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchState = .idle
            return
        }
        performSearch(query: query)
    }

    /// Clear results and reset to idle.
    public func clear() {
        debounceTask?.cancel()
        debounceTask = nil
        searchTask?.cancel()
        searchTask = nil
        query = ""
        searchState = .idle
    }

    // MARK: - Debounce

    private func scheduleSearch() {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchState = .idle
            return
        }
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            self.performSearch(query: trimmed)
        }
    }

    // MARK: - Repository call (§20 containment — no direct APIClient here)

    private func performSearch(query: String) {
        // Cancel any in-flight search so an out-of-order completion can't
        // clobber the newest query's results.
        searchTask?.cancel()
        searchState = .searching
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await repository.searchSales(query: query)
                if Task.isCancelled { return }
                self.searchState = .results(results)
                AppLog.pos.info("ReprintSearchVM: \(results.count, privacy: .public) results for query")
            } catch is CancellationError {
                return
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                return
            } catch {
                if Task.isCancelled { return }
                let message = (error as? AppError)?.localizedDescription ?? error.localizedDescription
                self.searchState = .error(message)
                AppLog.pos.error("ReprintSearchVM: search failed — \(message, privacy: .public)")
            }
        }
    }
}
