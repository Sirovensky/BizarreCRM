import Foundation
import Observation

// MARK: - HelpSearchViewModel

/// `@Observable` view-model for the Help Center search. Indexes article
/// keywords and runs a debounced query so the list updates smoothly.
@MainActor
@Observable
public final class HelpSearchViewModel {

    // MARK: - Public state

    /// Current search query (bound to TextField).
    public var query: String = "" {
        didSet { scheduleSearch() }
    }

    /// Filtered articles matching the current query.
    public private(set) var results: [HelpArticle] = []

    /// True when a search is in-flight (debounce pending).
    public private(set) var isSearching: Bool = false

    // MARK: - Private

    private let catalog: [HelpArticle]
    private let debounceInterval: Duration
    private var debounceTask: Task<Void, Never>?

    // Keyword index: article id → normalized tokens for fast lookup.
    private let index: [String: Set<String>]

    // MARK: - Init

    public init(
        catalog: [HelpArticle] = HelpArticleCatalog.all,
        debounceInterval: Duration = .milliseconds(250)
    ) {
        self.catalog = catalog
        self.debounceInterval = debounceInterval
        self.index = Self.buildIndex(catalog)
        self.results = catalog
    }

    // MARK: - Public API

    /// Clear the query and reset results to the full catalog.
    public func clear() {
        query = ""
        debounceTask?.cancel()
        debounceTask = nil
        isSearching = false
        results = catalog
    }

    // MARK: - Private helpers

    private func scheduleSearch() {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isSearching = false
            results = catalog
            return
        }
        isSearching = true
        debounceTask = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            await performSearch(query: trimmed)
        }
    }

    private func performSearch(query: String) async {
        let tokens = Self.tokenize(query)
        let filtered = catalog.filter { article in
            let articleTokens = index[article.id] ?? []
            return tokens.allSatisfy { token in
                articleTokens.contains { $0.hasPrefix(token) }
            }
        }
        results = filtered
        isSearching = false
    }

    // MARK: - Index building

    private static func buildIndex(_ catalog: [HelpArticle]) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for article in catalog {
            var tokens: Set<String> = []
            // Title words
            tokens.formUnion(tokenize(article.title))
            // Category
            tokens.formUnion(tokenize(article.category.rawValue))
            // Tags
            for tag in article.tags { tokens.formUnion(tokenize(tag)) }
            // First 200 chars of markdown body (avoid heavy indexing)
            let body = String(article.markdown.prefix(200))
            tokens.formUnion(tokenize(body))
            result[article.id] = tokens
        }
        return result
    }

    static func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }
}
