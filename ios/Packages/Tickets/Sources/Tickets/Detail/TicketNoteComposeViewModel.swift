import Foundation
import Observation
import Core
import Networking

// §4.6 — Note compose view model (platform-agnostic).
// Separated from TicketNoteComposeView so macOS test targets can test it.
//
// §4.6 line 690 — @ trigger: detects the `@` character followed by a partial
// name and exposes `mentionQuery` + `mentionSuggestions` for the view to render.
// Selecting a suggestion calls `pickMention(_:)` which replaces the partial
// `@query` token with `@{displayName}` and clears the suggestion list.

@MainActor
@Observable
public final class TicketNoteComposeViewModel {
    public var type: NoteType = .internal_
    public var content: String = "" {
        didSet { handleContentChange(content) }
    }
    public var isFlagged: Bool = false
    public var deviceId: Int64? = nil

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didPost: Bool = false

    // MARK: — § 4.6 @ mention state (line 690)

    /// The partial name being typed after `@` — nil when not in mention mode.
    public private(set) var mentionQuery: String? = nil
    /// Filtered employee suggestions for the current `mentionQuery`.
    public private(set) var mentionSuggestions: [Employee] = []
    /// All employees fetched once on first `@` keystroke.
    private var allEmployees: [Employee] = []

    /// Inserts `@DisplayName ` at the position of the active `@query` token.
    public func pickMention(_ employee: Employee) {
        guard let query = mentionQuery else { return }
        let token = "@\(query)"
        let replacement = "@\(employee.displayName) "
        // Replace last occurrence of the partial token (rightmost, since user is typing).
        if let range = content.range(of: token, options: .backwards) {
            content = content.replacingCharacters(in: range, with: replacement)
        }
        mentionQuery = nil
        mentionSuggestions = []
    }

    /// Dismisses the mention picker without inserting.
    public func dismissMention() {
        mentionQuery = nil
        mentionSuggestions = []
    }

    public enum NoteType: String, CaseIterable, Sendable, Identifiable {
        case internal_   = "internal"
        case customer    = "customer"
        case diagnostic  = "diagnostic"
        case sms         = "sms"
        case email       = "email"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .internal_:  return "Internal"
            case .customer:   return "Customer visible"
            case .diagnostic: return "Diagnostic"
            case .sms:        return "SMS"
            case .email:      return "Email"
            }
        }

        public var systemImage: String {
            switch self {
            case .internal_:  return "lock.fill"
            case .customer:   return "person.fill"
            case .diagnostic: return "stethoscope"
            case .sms:        return "message.fill"
            case .email:      return "envelope.fill"
            }
        }
    }

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let ticketId: Int64

    public init(api: APIClient, ticketId: Int64) {
        self.api = api
        self.ticketId = ticketId
    }

    public var isValid: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func post() async {
        guard !isSubmitting, isValid else {
            if !isValid { errorMessage = "Note content cannot be empty." }
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let req = AddTicketNoteRequest(
            type: type.rawValue,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            isFlagged: isFlagged,
            ticketDeviceId: deviceId
        )

        do {
            _ = try await api.addTicketNote(ticketId: ticketId, req)
            didPost = true
        } catch {
            AppLog.ui.error("Note post failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = AppError.from(error).errorDescription ?? error.localizedDescription
        }
    }

    // MARK: — Private: @ mention detection (§4.6 line 690)

    /// Called on every content keystroke. Extracts the partial mention query
    /// if the last word in the text starts with `@`, then filters suggestions.
    private func handleContentChange(_ text: String) {
        // Split by whitespace/newline and examine the last token.
        // If it starts with `@` but contains no subsequent space, we're in mention mode.
        let lastToken: String? = text.components(separatedBy: .whitespacesAndNewlines).last
        if let token = lastToken, token.hasPrefix("@") {
            let query = String(token.dropFirst()) // everything after @
            mentionQuery = query
            loadMentionSuggestions(query: query)
        } else {
            clearMentionIfNeeded(text)
        }
    }

    private func clearMentionIfNeeded(_ text: String) {
        if mentionQuery != nil {
            mentionQuery = nil
            mentionSuggestions = []
        }
    }

    private func loadMentionSuggestions(query: String) {
        if allEmployees.isEmpty {
            // First keystroke after @ — fetch the employee list once.
            Task { @MainActor in
                do {
                    allEmployees = try await api.ticketAssigneeCandidates()
                    filterSuggestions(query: query)
                } catch {
                    AppLog.ui.error("Mention employee load failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            filterSuggestions(query: query)
        }
    }

    private func filterSuggestions(query: String) {
        if query.isEmpty {
            mentionSuggestions = Array(allEmployees.filter(\.active).prefix(6))
        } else {
            let lower = query.lowercased()
            mentionSuggestions = allEmployees.filter(\.active).filter {
                $0.displayName.lowercased().contains(lower)
            }.prefix(6).map { $0 }
        }
    }
}
