import Foundation
import Observation
import Core
import Networking

// MARK: - SnippetsListViewModel

@MainActor
@Observable
public final class SnippetsListViewModel {

    // MARK: - State

    public internal(set) var snippets: [Snippet] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Filter

    /// The active category filter. `nil` means show all.
    public var filterCategory: String? = nil
    public var searchQuery: String = ""

    public var allCategories: [String] {
        let cats = snippets.compactMap(\.category).filter { !$0.isEmpty }
        return Array(Set(cats)).sorted()
    }

    public var filtered: [Snippet] {
        snippets.filter { snippet in
            let matchCat = filterCategory.map { snippet.category == $0 } ?? true
            let q = searchQuery.trimmingCharacters(in: .whitespaces)
            let matchSearch = q.isEmpty
                || snippet.title.localizedCaseInsensitiveContains(q)
                || snippet.shortcode.localizedCaseInsensitiveContains(q)
                || snippet.content.localizedCaseInsensitiveContains(q)
            return matchCat && matchSearch
        }
    }

    /// Snippets grouped by category for sectioned display. Uncategorised snippets
    /// are placed under the empty-string key "".
    public var groupedFiltered: [(category: String, snippets: [Snippet])] {
        var dict: [String: [Snippet]] = [:]
        for snippet in filtered {
            let key = snippet.category ?? ""
            dict[key, default: []].append(snippet)
        }
        let sorted = dict.keys.sorted { lhs, rhs in
            if lhs.isEmpty { return false }
            if rhs.isEmpty { return true }
            return lhs < rhs
        }
        return sorted.map { cat in (category: cat, snippets: dict[cat]!) }
    }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    /// Optional: closure called when user picks a snippet (from SMS composer).
    @ObservationIgnored public var onPick: ((Snippet) -> Void)?

    public init(api: APIClient, onPick: ((Snippet) -> Void)? = nil) {
        self.api = api
        self.onPick = onPick
    }

    // MARK: - Actions

    public func load() async {
        if snippets.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            snippets = try await api.listSnippets()
        } catch {
            AppLog.ui.error("Snippets load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func delete(snippet: Snippet) async {
        let id = snippet.id
        // Optimistic removal — immutable: replace entire array
        snippets = snippets.filter { $0.id != id }
        do {
            try await api.deleteSnippet(id: id)
        } catch {
            AppLog.ui.error("Snippet delete failed: \(error.localizedDescription, privacy: .public)")
            // Revert on failure
            await load()
            errorMessage = error.localizedDescription
        }
    }

    public func pick(_ snippet: Snippet) {
        onPick?(snippet)
    }
}
