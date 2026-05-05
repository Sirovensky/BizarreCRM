import Foundation
import Observation
import Core
import Networking

// §5.9 Tag management ViewModel — multi-select tag editor with autosuggest.

@MainActor
@Observable
public final class CustomerTagEditorViewModel {

    // MARK: - State

    /// Currently assigned tags on the customer (mutable during edit).
    public var selectedTags: [String]

    /// Free-text entry in the search field.
    public var query: String = "" {
        didSet { scheduleAutosuggest() }
    }

    /// Server-side + computed suggestions.
    public private(set) var suggestions: [String] = []
    public private(set) var isSuggesting: Bool = false
    public private(set) var isSaving: Bool = false
    public private(set) var saveError: String? = nil
    public private(set) var savedSuccessfully: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let customerId: Int64
    @ObservationIgnored private var suggestTask: Task<Void, Never>? = nil

    // MARK: - Init

    public init(api: APIClient, customerId: Int64, initialTags: [String]) {
        self.api = api
        self.customerId = customerId
        self.selectedTags = initialTags
    }

    // MARK: - Tag toggling

    public func toggleTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = selectedTags.firstIndex(of: trimmed) {
            selectedTags.remove(at: idx)
        } else if selectedTags.count < 20 {
            selectedTags = selectedTags + [trimmed]
        }
    }

    public func addQueryAsTag() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        toggleTag(trimmed)
        query = ""
    }

    public func removeTag(_ tag: String) {
        selectedTags = selectedTags.filter { $0 != tag }
    }

    // MARK: - Autosuggest

    private func scheduleAutosuggest() {
        suggestTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            suggestions = []
            return
        }
        suggestTask = Task {
            // Small debounce.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await fetchSuggestions(q: q)
        }
    }

    private func fetchSuggestions(q: String) async {
        isSuggesting = true
        defer { isSuggesting = false }
        do {
            let raw = try await api.suggestCustomerTags(query: q)
            // Filter out already-selected.
            suggestions = raw.filter { !selectedTags.contains($0) }
        } catch {
            suggestions = []
        }
    }

    // MARK: - Save

    public func save() async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        savedSuccessfully = false
        defer { isSaving = false }

        let req = SetCustomerTagsRequest(tags: selectedTags)
        do {
            _ = try await api.setCustomerTags(id: customerId, req)
            savedSuccessfully = true
        } catch {
            saveError = AppError.from(error).localizedDescription
        }
    }
}
