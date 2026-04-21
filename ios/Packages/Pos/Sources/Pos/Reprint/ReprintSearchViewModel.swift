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

    private let api: APIClient

    // MARK: - Private

    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(400)

    public init(api: APIClient) {
        self.api = api
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

    // MARK: - API call

    private func performSearch(query: String) {
        searchState = .searching
        Task { [weak self] in
            guard let self else { return }
            do {
                let queryItems = [URLQueryItem(name: "q", value: query)]
                let results = try await api.get("/sales/search", query: queryItems, as: [SaleSummary].self)
                self.searchState = .results(results)
                AppLog.pos.info("ReprintSearchVM: \(results.count, privacy: .public) results for query")
            } catch {
                let message = (error as? AppError)?.localizedDescription ?? error.localizedDescription
                self.searchState = .error(message)
                AppLog.pos.error("ReprintSearchVM: search failed — \(message, privacy: .public)")
            }
        }
    }
}
