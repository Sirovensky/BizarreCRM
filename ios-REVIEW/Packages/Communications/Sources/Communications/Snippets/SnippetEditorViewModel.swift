import Foundation
import Observation
import Core
import Networking

// MARK: - SnippetEditorViewModel

@MainActor
@Observable
public final class SnippetEditorViewModel {

    // MARK: - Form fields

    public var shortcode: String
    public var title: String
    public var content: String
    public var category: String

    // MARK: - State

    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var savedSnippet: Snippet?

    // MARK: - Known variables for insertion

    /// Variables using {{name}} style that the server's snippets feature supports.
    /// Snippets use double-brace syntax per convention to distinguish from template vars.
    public static let knownVariables: [String] = [
        "{{first_name}}", "{{last_name}}", "{{company}}",
        "{{ticket_no}}", "{{amount}}", "{{date}}", "{{phone}}"
    ]

    // MARK: - Computed

    /// Extracted `{{var}}` tokens from current content.
    public var extractedVariables: [String] {
        SnippetVariableParser.extract(from: content)
    }

    /// Live preview: replaces {{var}} with sample values.
    public var livePreview: String {
        SnippetVariableParser.renderSample(content)
    }

    public var isValid: Bool {
        let sc = shortcode.trimmingCharacters(in: .whitespaces)
        let t = title.trimmingCharacters(in: .whitespaces)
        let c = content.trimmingCharacters(in: .whitespaces)
        guard !sc.isEmpty, !t.isEmpty, !c.isEmpty else { return false }
        guard sc.count <= 50 else { return false }
        guard t.count <= 200 else { return false }
        guard c.count <= 10_000 else { return false }
        // shortcode: [a-zA-Z0-9_-] only
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return sc.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let existingId: Int64?
    @ObservationIgnored private let onSave: (Snippet) -> Void

    public init(
        snippet: Snippet? = nil,
        api: APIClient,
        onSave: @escaping (Snippet) -> Void
    ) {
        self.api = api
        self.existingId = snippet?.id
        self.onSave = onSave
        shortcode = snippet?.shortcode ?? ""
        title = snippet?.title ?? ""
        content = snippet?.content ?? ""
        category = snippet?.category ?? ""
    }

    // MARK: - Save

    public func save() async {
        guard isValid else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let saved: Snippet
            let trimmedCategory: String? = category.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : category.trimmingCharacters(in: .whitespaces)

            if let id = existingId {
                saved = try await api.updateSnippet(
                    id: id,
                    UpdateSnippetRequest(
                        shortcode: shortcode.trimmingCharacters(in: .whitespaces),
                        title: title.trimmingCharacters(in: .whitespaces),
                        content: content,
                        category: trimmedCategory
                    )
                )
            } else {
                saved = try await api.createSnippet(
                    CreateSnippetRequest(
                        shortcode: shortcode.trimmingCharacters(in: .whitespaces),
                        title: title.trimmingCharacters(in: .whitespaces),
                        content: content,
                        category: trimmedCategory
                    )
                )
            }
            savedSnippet = saved
            onSave(saved)
        } catch {
            let appError = AppError.from(error)
            errorMessage = appError.errorDescription
            AppLog.ui.error("Snippet save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether this is a new snippet (no existing ID).
    public var isNewSnippet: Bool { existingId == nil }
}
