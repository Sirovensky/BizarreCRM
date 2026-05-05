#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5.7 Star-pin important notes to customer header
//
// Max 3 pinned notes visible across ticket/invoice/SMS contexts.
// Each note can be pinned/unpinned via star button.
// Pinned notes appear at the top of the customer header.

// MARK: - Model

public struct PinnedCustomerNote: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let body: String
    public let isPinned: Bool
    public let isInternalOnly: Bool
    public let authorName: String?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case isPinned        = "is_pinned"
        case isInternalOnly  = "is_internal_only"
        case authorName      = "author_name"
        case createdAt       = "created_at"
    }
}

// MARK: - Pinned notes header banner

/// Shows up to 3 pinned notes in a glass card above the customer detail header.
/// Visible across ticket / invoice / SMS contexts (pass in from parent).
public struct CustomerPinnedNotesBanner: View {
    let customerId: Int64
    let api: APIClient

    @State private var pinnedNotes: [PinnedCustomerNote] = []
    @State private var isLoading = false
    @State private var expanded = true

    public init(customerId: Int64, api: APIClient) {
        self.customerId = customerId
        self.api = api
    }

    public var body: some View {
        Group {
            if !pinnedNotes.isEmpty {
                bannerCard
            }
        }
        .task { await load() }
    }

    private var bannerCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Image(systemName: "pin.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityHidden(true)
                Text("Pinned Notes")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel(expanded ? "Collapse pinned notes" : "Expand pinned notes")
            }

            if expanded {
                ForEach(pinnedNotes.prefix(3)) { note in
                    pinnedRow(note)
                }
            }
        }
        .padding(BrandSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreWarning.opacity(0.3), lineWidth: 0.5)
        )
    }

    private func pinnedRow(_ note: PinnedCustomerNote) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.xs) {
            if note.isInternalOnly {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            Text(note.body)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await unpin(note) }
            } label: {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bizarreWarning)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unpin note")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.isInternalOnly ? "Internal. " : "")\(note.body). Pinned.")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let notes = try? await api.customerPinnedNotes(customerId: customerId) {
            pinnedNotes = notes
        }
    }

    private func unpin(_ note: PinnedCustomerNote) async {
        do {
            try await api.setCustomerNotePinned(
                customerId: customerId, noteId: note.id, pinned: false)
            pinnedNotes.removeAll { $0.id == note.id }
        } catch { /* non-critical */ }
    }
}

// MARK: - Notes list view (for customers section)

/// Full note list with star-pin toggle on each row.
public struct CustomerNotesListView: View {
    let customerId: Int64
    let api: APIClient

    @State private var notes: [PinnedCustomerNote] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddSheet = false
    @State private var draftBody = ""

    public init(customerId: Int64, api: APIClient) {
        self.customerId = customerId
        self.api = api
    }

    private var pinnedCount: Int { notes.filter(\.isPinned).count }

    public var body: some View {
        Group {
            if isLoading, notes.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else {
                notesList
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingAddSheet) {
            addNoteSheet
        }
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Notes")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Add note")
            }

            if notes.isEmpty {
                Text("No notes yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(notes) { note in
                    noteRow(note)
                    if note.id != notes.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func noteRow(_ note: PinnedCustomerNote) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if note.isInternalOnly {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let author = note.authorName {
                        Text(author)
                            .font(.brandLabelSmall().weight(.semibold))
                            .foregroundStyle(.bizarreOrange)
                    }
                    Text(String(note.createdAt.prefix(10)))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Text(note.body)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            Spacer(minLength: 0)

            // Star-pin toggle — max 3 pinned
            Button {
                Task { await togglePin(note) }
            } label: {
                Image(systemName: note.isPinned ? "star.fill" : "star")
                    .font(.system(size: 16))
                    .foregroundStyle(note.isPinned ? .bizarreWarning : .bizarreOnSurfaceMuted)
            }
            .buttonStyle(.plain)
            .disabled(!note.isPinned && pinnedCount >= 3)
            .accessibilityLabel(note.isPinned ? "Unpin note" : "Pin note")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.isInternalOnly ? "Internal. " : "")\(note.body). \(note.isPinned ? "Pinned." : "")")
    }

    private var addNoteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                TextEditor(text: $draftBody)
                    .font(.brandBodyMedium())
                    .frame(minHeight: 120)
                    .padding(BrandSpacing.sm)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                Spacer()
            }
            .padding(BrandSpacing.base)
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await saveNote() } }
                        .fontWeight(.semibold)
                        .disabled(draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let loaded = try? await api.customerNotes(customerId: customerId) {
            notes = loaded
        }
    }

    private func togglePin(_ note: PinnedCustomerNote) async {
        let newPinned = !note.isPinned
        do {
            try await api.setCustomerNotePinned(
                customerId: customerId, noteId: note.id, pinned: newPinned)
            await load()
        } catch { /* best-effort */ }
    }

    private func saveNote() async {
        let body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        do {
            try await api.createPinnedCustomerNote(customerId: customerId, body: body)
            draftBody = ""
            showingAddSheet = false
            await load()
        } catch { /* error display TBD */ }
    }
}

// MARK: - APIClient extension

extension APIClient {
    /// `GET /api/v1/customers/:id/notes` — all notes for a customer.
    public func customerNotes(customerId: Int64) async throws -> [PinnedCustomerNote] {
        try await get("/api/v1/customers/\(customerId)/notes", as: [PinnedCustomerNote].self)
    }

    /// `GET /api/v1/customers/:id/notes?pinned=true` — pinned notes only.
    public func customerPinnedNotes(customerId: Int64) async throws -> [PinnedCustomerNote] {
        let q = [URLQueryItem(name: "pinned", value: "true")]
        return try await get("/api/v1/customers/\(customerId)/notes", query: q,
                             as: [PinnedCustomerNote].self)
    }

    /// `PATCH /api/v1/customers/:id/notes/:noteId` — set pinned state.
    public func setCustomerNotePinned(customerId: Int64, noteId: Int64, pinned: Bool) async throws {
        _ = try await patch(
            "/api/v1/customers/\(customerId)/notes/\(noteId)",
            body: PinnedNoteBody(is_pinned: pinned),
            as: EmptyResponse.self
        )
    }

    /// `POST /api/v1/customers/:id/notes` — create a new note.
    public func createPinnedCustomerNote(customerId: Int64, body: String) async throws {
        _ = try await post(
            "/api/v1/customers/\(customerId)/notes",
            body: PinnedNoteCreateBody(body: body),
            as: EmptyResponse.self
        )
    }
}

private struct PinnedNoteBody: Encodable, Sendable { let is_pinned: Bool }
private struct PinnedNoteCreateBody: Encodable, Sendable { let body: String }

#endif
