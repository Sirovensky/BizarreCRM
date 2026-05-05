import Foundation
import Observation
import Networking

// MARK: - SmsComposerViewModel

/// @Observable ViewModel for the SMS Composer.
/// Handles cursor-position tracking, chip insertion, live preview, and segment counting.
@MainActor
@Observable
public final class SmsComposerViewModel: Sendable {

    // MARK: - Known dynamic-variable chips

    public static let knownVars: [String] = [
        "{first_name}", "{ticket_no}", "{total}", "{due_date}",
        "{tech_name}", "{appointment_time}", "{shop_name}"
    ]

    // MARK: - State

    /// The current draft text.
    public var draft: String

    /// Current cursor offset inside `draft`. Nil means "end of string".
    /// Views should set this whenever the text selection changes.
    public var cursorOffset: Int?

    // MARK: - Derived

    /// Character count (raw, pre-substitution).
    public var charCount: Int { draft.count }

    /// Number of 160-character SMS segments needed.
    public var smsSegmentCount: Int {
        guard !draft.isEmpty else { return 0 }
        return Int(ceil(Double(draft.count) / 160.0))
    }

    /// Live preview with sample data substituted.
    public var livePreview: String {
        guard !draft.isEmpty else { return "" }
        return TemplateRenderer.render(draft, variables: .sample)
    }

    /// Whether the draft is ready to send.
    public var isValid: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Context

    public let phoneNumber: String

    // MARK: - Init

    public init(phoneNumber: String, prefillBody: String = "") {
        self.phoneNumber = phoneNumber
        self.draft = prefillBody
        self.cursorOffset = prefillBody.isEmpty ? nil : prefillBody.count
    }

    // MARK: - Chip insertion

    /// Inserts `token` at `cursorOffset`, or appends if cursor is nil / out of range.
    /// After insertion, advances `cursorOffset` past the inserted token.
    public func insertAtCursor(_ token: String) {
        let insertIndex: Int
        if let offset = cursorOffset, offset >= 0, offset <= draft.count {
            insertIndex = offset
        } else {
            insertIndex = draft.count
        }
        let idx = draft.index(draft.startIndex, offsetBy: insertIndex)
        draft.insert(contentsOf: token, at: idx)
        cursorOffset = insertIndex + token.count
    }

    // MARK: - Template loading

    /// Replaces the current draft with the template body and resets cursor to end.
    public func loadTemplate(_ template: MessageTemplate) {
        draft = template.body
        cursorOffset = draft.count
    }
}
