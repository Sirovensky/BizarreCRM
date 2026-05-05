import Foundation
import Observation

/// View model for settings search. Debounces user input, runs fuzzy filter,
/// and publishes `results` to the UI.
///
/// - `@Observable` → SwiftUI tracks `results` and `isSearching` automatically.
/// - `@MainActor` → all mutations on main thread; safe to bind directly to SwiftUI.
@MainActor
@Observable
public final class SettingsSearchViewModel: Sendable {

    // MARK: - Published state

    /// Current search query entered by the user.
    public var query: String = "" {
        didSet { scheduleDebounce() }
    }

    /// Filtered results to display. Empty when `query` is empty.
    public private(set) var results: [SettingsEntry] = []

    /// `true` while the debounce timer is running (input just changed).
    public private(set) var isSearching: Bool = false

    // MARK: - Configuration

    /// Debounce delay in seconds.
    private let debounceInterval: TimeInterval

    // MARK: - Internal state

    private var debounceTask: Task<Void, Never>?

    // MARK: - Init

    public init(debounceInterval: TimeInterval = 0.2) {
        self.debounceInterval = debounceInterval
    }

    // MARK: - Public API

    /// Clears the search query and results immediately.
    public func clear() {
        debounceTask?.cancel()
        query = ""
        results = []
        isSearching = false
    }

    // MARK: - Private

    private func scheduleDebounce() {
        debounceTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(debounceInterval))
            guard !Task.isCancelled else { return }
            self.runFilter(query: q)
        }
    }

    private func runFilter(query: String) {
        results = SettingsSearchIndex.filter(query: query)
        isSearching = false
    }
}
