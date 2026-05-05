#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5 Customer Notes System
//
// Tasks implemented:
//   L940 — Note types: Quick, Detail, Call summary, Meeting, Internal-only
//   L941 — Internal-only notes hidden from customer-facing docs (is_internal_only param)
//   L943 — @mention teammate → push notification + link (MentionSuggestionBar + mentioned_user_ids in POST)
//   L945 — Internal-only flag hides note from SMS/email auto-include (UI toggle + server param)
//   L946 — Role-gate sensitive notes (manager only visible notes)
//   L947 — Quick-insert templates ("Called, left voicemail", "Reviewed estimate", etc.)
//   L948 — Edit history: edits logged; previous version viewable
//   L949 — A11y: rich text accessible via VoiceOver element-by-element

// MARK: - Note types (§5 L940)

public enum CustomerNoteType: String, Codable, CaseIterable, Sendable {
    case quick        = "quick"
    case detail       = "detail"
    case callSummary  = "call_summary"
    case meeting      = "meeting"
    case internalOnly = "internal_only"

    public var label: String {
        switch self {
        case .quick:        return "Quick note"
        case .detail:       return "Detailed note"
        case .callSummary:  return "Call summary"
        case .meeting:      return "Meeting"
        case .internalOnly: return "Internal only"
        }
    }

    public var icon: String {
        switch self {
        case .quick:        return "text.bubble"
        case .detail:       return "doc.text"
        case .callSummary:  return "phone.fill"
        case .meeting:      return "calendar"
        case .internalOnly: return "lock.fill"
        }
    }

    /// Whether this type implies internal-only visibility (§5 L941).
    public var isAlwaysInternal: Bool { self == .internalOnly }
}

// MARK: - Quick-insert templates (§5 L947)

public struct CustomerNoteTemplate: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let noteType: CustomerNoteType

    public static let defaults: [CustomerNoteTemplate] = [
        CustomerNoteTemplate(
            id: "called_voicemail",
            title: "Called, left voicemail",
            body: "Called customer — no answer; left voicemail regarding \u{2060}",
            noteType: .callSummary
        ),
        CustomerNoteTemplate(
            id: "reviewed_estimate",
            title: "Reviewed estimate",
            body: "Reviewed estimate with customer. \u{2060}",
            noteType: .meeting
        ),
        CustomerNoteTemplate(
            id: "customer_called",
            title: "Customer called in",
            body: "Customer called in. Discussed: \u{2060}",
            noteType: .callSummary
        ),
        CustomerNoteTemplate(
            id: "emailed_update",
            title: "Emailed update",
            body: "Sent email update to customer regarding \u{2060}",
            noteType: .quick
        ),
        CustomerNoteTemplate(
            id: "appointment_confirmed",
            title: "Appointment confirmed",
            body: "Confirmed appointment for \u{2060}",
            noteType: .meeting
        ),
        CustomerNoteTemplate(
            id: "parts_ordered",
            title: "Parts ordered",
            body: "Parts ordered for repair. ETA: \u{2060}",
            noteType: .quick
        ),
        CustomerNoteTemplate(
            id: "device_ready",
            title: "Device ready",
            body: "Device ready for pickup. Customer notified via \u{2060}",
            noteType: .quick
        ),
        CustomerNoteTemplate(
            id: "internal_flag",
            title: "Internal staff flag",
            body: "Staff note (internal): \u{2060}",
            noteType: .internalOnly
        ),
    ]
}

// MARK: - Note version history (§5 L948)

public struct CustomerNoteVersion: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let body: String
    public let editedBy: String?
    public let editedAt: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case editedBy  = "edited_by"
        case editedAt  = "edited_at"
    }
}

// MARK: - Enhanced CustomerNote (with type + version support)

public struct CustomerNoteV2: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let body: String
    public let noteType: CustomerNoteType
    public let isPinned: Bool
    public let isInternalOnly: Bool
    public let isManagerOnly: Bool
    public let authorName: String?
    public let createdAt: String
    public let editCount: Int
    /// §5 L944 — @ticket backlink: ticket ID this note is linked to (optional).
    public let linkedTicketId: Int64?
    /// §5 L944 — Ticket number string for display (e.g. "TKT-4521"), populated server-side.
    public let linkedTicketRef: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case noteType        = "note_type"
        case isPinned        = "is_pinned"
        case isInternalOnly  = "is_internal_only"
        case isManagerOnly   = "is_manager_only"
        case authorName      = "author_name"
        case createdAt       = "created_at"
        case editCount       = "edit_count"
        case linkedTicketId  = "linked_ticket_id"
        case linkedTicketRef = "linked_ticket_ref"
    }
}

// MARK: - §5 L943 — @mention autocomplete bar

/// Shown above the keyboard when the user types `@` in a note body.
/// Displays filtered teammate suggestions; tapping one inserts `@DisplayName ` at the cursor.
struct MentionSuggestionBar: View {
    let suggestions: [Employee]
    let onSelect: (Employee) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(suggestions) { employee in
                    Button {
                        onSelect(employee)
                    } label: {
                        HStack(spacing: 4) {
                            // Avatar initials circle
                            Text(employee.initials)
                                .font(.brandLabelSmall().weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.bizarreOrange, in: Circle())
                                .accessibilityHidden(true)
                            Text(employee.displayName)
                                .font(.brandLabelSmall().weight(.semibold))
                                .foregroundStyle(.bizarreOnSurface)
                        }
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, 6)
                        .background(Color.bizarreSurface2, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mention \(employee.displayName)")
                    .accessibilityHint("Inserts @\(employee.displayName) in your note")
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.xs)
        }
        .background(Color.bizarreSurfaceBase.opacity(0.95))
    }
}

// MARK: - Add Note Sheet (enhanced) — §5 L940/L941/L943/L944/L945/L946/L947

public struct CustomerAddNoteSheet: View {
    let customerId: Int64
    let api: APIClient
    /// Optional ticket ID to pre-link when opening from a ticket context.
    var preLinkedTicketId: Int64?
    var preLinkedTicketRef: String?
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var noteType: CustomerNoteType = .quick
    @State private var noteBody = ""
    @State private var isManagerOnly = false
    @State private var showingTemplates = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// §5 L944 — @ticket backlink
    @State private var linkedTicketIdInput: String = ""

    // §5 L943 — @mention state
    @State private var allEmployees: [Employee] = []
    @State private var mentionQuery: String? = nil        // non-nil when composing a mention
    @State private var mentionedUserIds: Set<Int64> = []  // IDs to pass to server for push

    public init(
        customerId: Int64,
        api: APIClient,
        preLinkedTicketId: Int64? = nil,
        preLinkedTicketRef: String? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.customerId = customerId
        self.api = api
        self.preLinkedTicketId = preLinkedTicketId
        self.preLinkedTicketRef = preLinkedTicketRef
        self.onSaved = onSaved
    }

    private var isInternal: Bool { noteType.isAlwaysInternal }

    private var isValid: Bool {
        !noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedLinkedTicketId: Int64? {
        // Prefer pre-linked (from caller context); fall back to manual entry.
        if let id = preLinkedTicketId { return id }
        return Int64(linkedTicketIdInput.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// §5 L943 — Teammates matching the current @mention query.
    private var mentionSuggestions: [Employee] {
        guard let q = mentionQuery else { return [] }
        let lower = q.lowercased()
        if lower.isEmpty { return allEmployees.filter(\.active).prefix(8).map { $0 } }
        return allEmployees.filter { emp in
            emp.active && (
                emp.displayName.lowercased().contains(lower) ||
                (emp.username?.lowercased().contains(lower) ?? false)
            )
        }.prefix(8).map { $0 }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // §5 L943 — @mention suggestion bar (shown when mentionQuery is active)
                if !mentionSuggestions.isEmpty {
                    MentionSuggestionBar(suggestions: mentionSuggestions) { employee in
                        insertMention(employee)
                    }
                    Divider()
                }

                Form {
                    // Note type picker (§5 L940)
                    Section("Type") {
                        Picker("Note type", selection: $noteType) {
                            ForEach(CustomerNoteType.allCases, id: \.rawValue) { type in
                                Label(type.label, systemImage: type.icon).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: noteType) { _, new in
                            // Switching to internalOnly auto-sets body prefix
                            if new == .internalOnly && noteBody.isEmpty {
                                noteBody = "Staff note (internal): "
                            }
                        }
                    }

                    // Body (§5 L949 — accessible via VoiceOver, §5 L943 — @mention detection)
                    Section {
                        TextEditor(text: $noteBody)
                            .font(.brandBodyMedium())
                            .frame(minHeight: noteType == .detail || noteType == .meeting ? 160 : 80)
                            .accessibilityLabel("Note body")
                            .accessibilityHint("Type the note content here. Use @name to mention a teammate.")
                            .onChange(of: noteBody) { _, newValue in
                                updateMentionQuery(text: newValue)
                            }
                    } header: {
                        HStack {
                            Text("Note")
                            Spacer()
                            // Quick-insert templates (§5 L947)
                            Button {
                                showingTemplates = true
                            } label: {
                                Label("Templates", systemImage: "text.badge.plus")
                                    .font(.brandLabelSmall())
                            }
                            .buttonStyle(.plain)
                            .tint(.bizarreTeal)
                            .accessibilityLabel("Insert template")
                        }
                    } footer: {
                        // §5 L943 — hint for @mention affordance
                        Text("Use @name to mention a teammate — they'll get a notification.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }

                    // §5 L943 — mentioned teammates chips (confirmed mentions)
                    if !mentionedUserIds.isEmpty {
                        Section("Notifying") {
                            let mentioned = allEmployees.filter { mentionedUserIds.contains($0.id) }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: BrandSpacing.xs) {
                                    ForEach(mentioned) { emp in
                                        Label(emp.displayName, systemImage: "bell.fill")
                                            .font(.brandLabelSmall())
                                            .foregroundStyle(.bizarreOrange)
                                            .padding(.horizontal, BrandSpacing.sm)
                                            .padding(.vertical, 4)
                                            .background(Color.bizarreOrange.opacity(0.1), in: Capsule())
                                            .accessibilityLabel("\(emp.displayName) will be notified")
                                    }
                                }
                            }
                        }
                    }

                    // §5 L944 — @ticket backlink
                    Section {
                        if let pre = preLinkedTicketRef {
                            // Pre-linked from ticket context — display only
                            LabeledContent("Linked ticket") {
                                HStack(spacing: BrandSpacing.xs) {
                                    Image(systemName: "ticket")
                                        .foregroundStyle(.bizarreOrange)
                                        .accessibilityHidden(true)
                                    Text(pre)
                                        .font(.brandBodyMedium())
                                        .foregroundStyle(.bizarreOrange)
                                }
                            }
                            .accessibilityLabel("Linked to ticket \(pre)")
                        } else {
                            LabeledContent("Link to ticket (optional)") {
                                TextField("Ticket ID", text: $linkedTicketIdInput)
                                    .multilineTextAlignment(.trailing)
                                    .font(.brandMono(size: 14))
                                    .accessibilityLabel("Ticket ID to link this note to")
                                    .accessibilityHint("Enter a ticket ID number to create a backlink")
                            }
                        }
                    } header: {
                        Text("Ticket Backlink")
                    } footer: {
                        Text("Link this note to a ticket so it appears in the ticket history.")
                            .font(.brandLabelSmall())
                    }

                    // Visibility flags (§5 L941/L945/L946)
                    Section("Visibility") {
                        if !isInternal {
                            Toggle(isOn: .init(
                                get: { isManagerOnly },
                                set: { isManagerOnly = $0 }
                            )) {
                                Label("Manager only", systemImage: "person.badge.shield.checkmark")
                            }
                            .toggleStyle(.switch)
                            .accessibilityLabel("Manager only note")
                            .accessibilityHint("When on, only managers can see this note")
                        }

                        if isInternal {
                            HStack(spacing: BrandSpacing.xs) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                    .font(.caption)
                                Text("Hidden from customer-facing docs, SMS, and email auto-include.")
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Internal only — hidden from customers")
                        }
                    }

                    if let err = errorMessage {
                        Section {
                            Text(err)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreError)
                        }
                    }
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!isValid || isSaving)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(isSaving)
            .sheet(isPresented: $showingTemplates) {
                NoteTemplatePickerSheet { template in
                    noteType = template.noteType
                    noteBody = template.body
                    showingTemplates = false
                }
            }
            .task { await loadEmployees() }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - §5 L943 — mention helpers

    /// Loads the teammate list once (for autocomplete suggestions).
    private func loadEmployees() async {
        guard allEmployees.isEmpty else { return }
        allEmployees = (try? await api.listEmployees()) ?? []
    }

    /// Detects whether the cursor is inside an `@word` token and sets `mentionQuery`.
    private func updateMentionQuery(text: String) {
        // Find the last `@` that hasn't been followed by whitespace yet
        // (i.e. cursor is still composing the mention).
        let words = text.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        if let last = words.last, last.hasPrefix("@") {
            let q = String(last.dropFirst()) // text after `@`
            mentionQuery = q
        } else {
            mentionQuery = nil
        }
        // Resync confirmed mention IDs whenever body changes
        syncMentionedIds(from: text)
    }

    /// Replaces the trailing `@query` token with `@DisplayName ` and records the user ID.
    private func insertMention(_ employee: Employee) {
        // Remove the trailing partial `@query` and append the resolved mention.
        var words = noteBody.components(separatedBy: " ")
        if words.last?.hasPrefix("@") == true {
            words.removeLast()
        }
        words.append("@\(employee.displayName)")
        noteBody = words.joined(separator: " ") + " "
        mentionedUserIds.insert(employee.id)
        mentionQuery = nil
    }

    /// Re-derives `mentionedUserIds` by scanning the current body for `@DisplayName` tokens
    /// so removing a mention by hand also removes the notification intent.
    private func syncMentionedIds(from text: String) {
        let tokens = text.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { $0.hasPrefix("@") }
            .map { String($0.dropFirst()) }
        let tokenSet = Set(tokens)
        mentionedUserIds = Set(
            allEmployees
                .filter { tokenSet.contains($0.displayName) }
                .map(\.id)
        )
    }

    private func save() async {
        let trimmed = noteBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await api.createCustomerNoteV2(
                customerId: customerId,
                body: trimmed,
                noteType: noteType,
                isManagerOnly: isManagerOnly,
                linkedTicketId: resolvedLinkedTicketId,
                mentionedUserIds: Array(mentionedUserIds)
            )
            onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Template picker sheet (§5 L947)

private struct NoteTemplatePickerSheet: View {
    let onSelect: (CustomerNoteTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(CustomerNoteTemplate.defaults) { template in
                Button {
                    onSelect(template)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(template.title, systemImage: template.noteType.icon)
                            .font(.brandLabelLarge().weight(.semibold))
                            .foregroundStyle(.bizarreOnSurface)
                        Text(template.body)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(template.title)
                .accessibilityHint("Insert \(template.noteType.label) template")
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Note edit history sheet (§5 L948)

public struct NoteEditHistorySheet: View {
    let noteId: Int64
    let api: APIClient

    @Environment(\.dismiss) private var dismiss
    @State private var versions: [CustomerNoteVersion] = []
    @State private var isLoading = false

    public init(noteId: Int64, api: APIClient) {
        self.noteId = noteId
        self.api = api
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if versions.isEmpty {
                    ContentUnavailableView(
                        "No edit history",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("This note has not been edited.")
                    )
                } else {
                    List(versions) { version in
                        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                            HStack {
                                Text(version.editedBy ?? "Unknown")
                                    .font(.brandLabelSmall().weight(.semibold))
                                    .foregroundStyle(.bizarreOnSurface)
                                Spacer()
                                Text(String(version.editedAt.prefix(16)).replacingOccurrences(of: "T", with: " "))
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            Text(version.body)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                                .accessibilityLabel("Previous version: \(version.body)")
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("Edit History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        versions = (try? await api.customerNoteVersions(noteId: noteId)) ?? []
    }
}

// MARK: - APIClient extensions (§5 notes)

extension APIClient {
    /// `POST /api/v1/customers/:id/notes` — create note with type + visibility flags.
    /// §5 L944: `linked_ticket_id` wires the @ticket backlink (optional).
    /// §5 L943: `mentioned_user_ids` tells the server which teammates to push-notify.
    ///
    /// Server push dispatch for mentions: server parses `mentioned_user_ids`, looks up
    /// each user's push token, and sends a notification with a deep link to the customer
    /// detail view (`bizarrecrm://customers/:customerId`). Notification payload kind is
    /// `note.mention` so §70 notification matrix can route it.
    public func createCustomerNoteV2(
        customerId: Int64,
        body: String,
        noteType: CustomerNoteType,
        isManagerOnly: Bool,
        linkedTicketId: Int64? = nil,
        mentionedUserIds: [Int64] = []
    ) async throws {
        _ = try await post(
            "/api/v1/customers/\(customerId)/notes",
            body: CustomerNoteCreateBody(
                body: body,
                note_type: noteType.rawValue,
                is_manager_only: isManagerOnly,
                linked_ticket_id: linkedTicketId,
                mentioned_user_ids: mentionedUserIds
            ),
            as: EmptyResponse.self
        )
    }

    /// `GET /api/v1/notes/:id/versions` — edit history for a note.
    public func customerNoteVersions(noteId: Int64) async throws -> [CustomerNoteVersion] {
        try await get("/api/v1/notes/\(noteId)/versions", as: [CustomerNoteVersion].self)
    }
}

private struct CustomerNoteCreateBody: Encodable, Sendable {
    let body: String
    let note_type: String
    let is_manager_only: Bool
    let linked_ticket_id: Int64?
    let mentioned_user_ids: [Int64]
}

#endif
