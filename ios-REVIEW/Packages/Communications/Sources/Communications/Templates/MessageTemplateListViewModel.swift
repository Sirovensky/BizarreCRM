import Foundation
import Observation
import Core
import Networking

// MARK: - MessageTemplateListViewModel

@MainActor
@Observable
public final class MessageTemplateListViewModel {

    // MARK: - State

    public internal(set) var templates: [MessageTemplate] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Filter

    public var filterChannel: MessageChannel? = nil
    public var filterCategory: MessageTemplateCategory? = nil
    public var searchQuery: String = ""

    public var filtered: [MessageTemplate] {
        templates.filter { t in
            let matchChannel = filterChannel.map { $0 == t.channel } ?? true
            let matchCat = filterCategory.map { $0 == t.category } ?? true
            let q = searchQuery.trimmingCharacters(in: .whitespaces)
            let matchSearch = q.isEmpty
                || t.name.localizedCaseInsensitiveContains(q)
                || t.body.localizedCaseInsensitiveContains(q)
            return matchChannel && matchCat && matchSearch
        }
    }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    /// Optional: closure called when user picks a template (from SMS compose).
    @ObservationIgnored public var onPick: ((MessageTemplate) -> Void)?

    public init(api: APIClient, onPick: ((MessageTemplate) -> Void)? = nil) {
        self.api = api
        self.onPick = onPick
    }

    // MARK: - Actions

    public func load() async {
        if templates.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            templates = try await api.listMessageTemplates()
        } catch {
            AppLog.ui.error("Templates load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func delete(template: MessageTemplate) async {
        let id = template.id
        // Optimistic removal
        templates.removeAll { $0.id == id }
        do {
            try await api.deleteMessageTemplate(id: id)
        } catch {
            AppLog.ui.error("Template delete failed: \(error.localizedDescription, privacy: .public)")
            // Revert on failure
            await load()
            errorMessage = error.localizedDescription
        }
    }

    public func pick(_ template: MessageTemplate) {
        onPick?(template)
    }
}
