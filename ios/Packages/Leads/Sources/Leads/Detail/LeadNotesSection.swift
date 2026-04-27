#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §9.3 Lead detail — Notes section with @mention support

/// Displays and manages notes on a lead record.
/// Notes are loaded from `GET /leads/:id/notes` and created via `POST /leads/:id/notes`.
/// @mention syntax (`@Name`) is highlighted in the note body.
public struct LeadNotesSection: View {
    let leadId: Int64
    let api: APIClient

    @State private var notes: [LeadNote] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingAdd = false

    public init(leadId: Int64, api: APIClient) {
        self.leadId = leadId
        self.api = api
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Header
            HStack {
                Text("NOTES")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button {
                    showingAdd = true
                } label: {
                    Label("Add note", systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 18))
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Add note to lead")
            }

            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .accessibilityLabel("Loading notes")
            } else if let err = error {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            } else if notes.isEmpty {
                Text("No notes yet. Tap + to add one.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.vertical, BrandSpacing.sm)
            } else {
                VStack(spacing: BrandSpacing.sm) {
                    ForEach(notes) { note in
                        LeadNoteRow(note: note) {
                            Task { await deleteNote(id: note.id) }
                        }
                    }
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .task { await load() }
        .sheet(isPresented: $showingAdd) {
            LeadAddNoteSheet(leadId: leadId, api: api) { newNote in
                notes.insert(newNote, at: 0)
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            notes = try await api.leadNotes(id: leadId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteNote(id: Int64) async {
        do {
            try await api.deleteLeadNote(leadId: leadId, noteId: id)
            notes.removeAll { $0.id == id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct LeadNoteRow: View {
    let note: LeadNote
    var onDelete: () -> Void
    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            mentionHighlightedText(note.body)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)

            HStack {
                if let author = note.authorName, !author.isEmpty {
                    Text(author)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOrange)
                }
                if let date = note.createdAt {
                    Text(String(date.prefix(16)))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.bizarreError.opacity(0.7))
                }
                .accessibilityLabel("Delete note")
                .confirmationDialog("Delete this note?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { onDelete() }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Note: \(note.body). \(note.authorName ?? "")")
    }

    /// Renders note body with @mentions highlighted in orange.
    private func mentionHighlightedText(_ text: String) -> some View {
        let parts = splitMentions(text)
        return parts.reduce(Text("")) { result, part in
            if part.hasPrefix("@") {
                return result + Text(part).foregroundColor(.bizarreOrange).fontWeight(.semibold)
            }
            return result + Text(part)
        }
    }

    private func splitMentions(_ text: String) -> [String] {
        // Split around @word patterns; keep the @ token.
        var result: [String] = []
        var current = ""
        for word in text.components(separatedBy: " ") {
            if word.hasPrefix("@") {
                if !current.isEmpty { result.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
                result.append(word)
            } else {
                current += (current.isEmpty ? "" : " ") + word
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

// MARK: - Add note sheet

private struct LeadAddNoteSheet: View {
    let leadId: Int64
    let api: APIClient
    var onAdded: (LeadNote) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BrandSpacing.base) {
                Text("Use @name to mention a teammate.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                TextEditor(text: $noteText)
                    .font(.brandBodyMedium())
                    .frame(minHeight: 140)
                    .padding(BrandSpacing.sm)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
                    .accessibilityLabel("Note body")

                if let err = error {
                    Text(err).font(.brandLabelSmall()).foregroundStyle(.bizarreError)
                }
                Spacer()
            }
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() }
                    else {
                        Button("Save") { Task { await save() } }
                            .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let note = try await api.createLeadNote(leadId: leadId, body: trimmed)
            onAdded(note)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Model

public struct LeadNote: Identifiable, Decodable, Sendable {
    public let id: Int64
    public let body: String
    public let authorName: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case authorName = "author_name"
        case createdAt  = "created_at"
    }
}

// MARK: - Endpoints

extension APIClient {
    /// `GET /leads/:id/notes`
    public func leadNotes(id: Int64) async throws -> [LeadNote] {
        try await get("/leads/\(id)/notes", as: [LeadNote].self)
    }

    /// `POST /leads/:id/notes`
    public func createLeadNote(leadId: Int64, body: String) async throws -> LeadNote {
        struct Req: Encodable { let body: String }
        return try await post("/leads/\(leadId)/notes", body: Req(body: body), as: LeadNote.self)
    }

    /// `DELETE /leads/:id/notes/:noteId`
    public func deleteLeadNote(leadId: Int64, noteId: Int64) async throws {
        try await delete("/leads/\(leadId)/notes/\(noteId)")
    }
}

#endif
