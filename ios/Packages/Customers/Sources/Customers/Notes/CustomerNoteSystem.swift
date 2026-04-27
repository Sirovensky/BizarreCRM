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

    enum CodingKeys: String, CodingKey {
        case id, body
        case noteType      = "note_type"
        case isPinned      = "is_pinned"
        case isInternalOnly = "is_internal_only"
        case isManagerOnly = "is_manager_only"
        case authorName    = "author_name"
        case createdAt     = "created_at"
        case editCount     = "edit_count"
    }
}

// MARK: - Add Note Sheet (enhanced) — §5 L940/L941/L945/L946/L947

public struct CustomerAddNoteSheet: View {
    let customerId: Int64
    let api: APIClient
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var noteType: CustomerNoteType = .quick
    @State private var body = ""
    @State private var isManagerOnly = false
    @State private var showingTemplates = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    public init(customerId: Int64, api: APIClient, onSaved: (() -> Void)? = nil) {
        self.customerId = customerId
        self.api = api
        self.onSaved = onSaved
    }

    private var isInternal: Bool { noteType.isAlwaysInternal }

    private var isValid: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        NavigationStack {
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
                        if new == .internalOnly && body.isEmpty {
                            body = "Staff note (internal): "
                        }
                    }
                }

                // Body (§5 L949 — accessible via VoiceOver)
                Section {
                    TextEditor(text: $body)
                        .font(.brandBodyMedium())
                        .frame(minHeight: noteType == .detail || noteType == .meeting ? 160 : 80)
                        .accessibilityLabel("Note body")
                        .accessibilityHint("Type the note content here")
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
                    body = template.body
                    showingTemplates = false
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await api.createCustomerNoteV2(
                customerId: customerId,
                body: trimmed,
                noteType: noteType,
                isManagerOnly: isManagerOnly
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
    public func createCustomerNoteV2(
        customerId: Int64,
        body: String,
        noteType: CustomerNoteType,
        isManagerOnly: Bool
    ) async throws {
        struct Body: Encodable {
            let body: String
            let note_type: String
            let is_manager_only: Bool
            // is_internal_only is derived server-side from note_type == "internal_only"
        }
        try await post(
            "/api/v1/customers/\(customerId)/notes",
            body: Body(
                body: body,
                note_type: noteType.rawValue,
                is_manager_only: isManagerOnly
            ),
            as: EmptyResponse.self
        )
    }

    /// `GET /api/v1/notes/:id/versions` — edit history for a note.
    public func customerNoteVersions(noteId: Int64) async throws -> [CustomerNoteVersion] {
        try await get("/api/v1/notes/\(noteId)/versions", as: [CustomerNoteVersion].self)
    }
}

#endif
