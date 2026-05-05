import SwiftUI
import DesignSystem

/// §18 — "Save Search" sheet presented from the live search bar.
///
/// Pre-fills the current query and entity filter. The user supplies a name,
/// then taps Save. Duplicate names surface an inline error.
public struct SaveSearchSheet: View {

    // MARK: - Input

    private let query: String
    private let entity: EntityFilter
    private let store: SavedSearchStore
    private let onSaved: (SavedSearch) -> Void

    // MARK: - State

    @State private var name: String = ""
    @State private var selectedEntity: EntityFilter
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false
    @Environment(\.dismiss) private var dismiss

    // MARK: - Init

    /// - Parameters:
    ///   - query:    Pre-filled search query from the caller.
    ///   - entity:   Pre-filled entity scope from the caller.
    ///   - store:    The store to persist into.
    ///   - onSaved:  Called (on the main actor) after the search is saved.
    public init(
        query: String,
        entity: EntityFilter = .all,
        store: SavedSearchStore,
        onSaved: @escaping (SavedSearch) -> Void = { _ in }
    ) {
        self.query = query
        self.entity = entity
        self.store = store
        self.onSaved = onSaved
        self._selectedEntity = State(initialValue: entity)
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                previewSection
                nameSection
                entitySection
                if let msg = errorMessage {
                    Section {
                        Text(msg)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Save Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var previewSection: some View {
        Section("Query") {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(query.isEmpty ? "Empty query" : query)
                    .font(.brandBodyLarge())
                    .foregroundStyle(query.isEmpty ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                    .lineLimit(2)
            }
            .listRowBackground(Color.bizarreSurface1)
        }
    }

    private var nameSection: some View {
        Section("Name") {
            TextField("e.g. Open tickets this week", text: $name)
                .font(.brandBodyLarge())
                .accessibilityLabel("Saved search name")
                .submitLabel(.done)
                .onSubmit {
                    if canSave { Task { await save() } }
                }
                .listRowBackground(Color.bizarreSurface1)
        }
    }

    private var entitySection: some View {
        Section("Entity scope") {
            Picker("Entity", selection: $selectedEntity) {
                ForEach(EntityFilter.allCases, id: \.self) { filter in
                    Label(filter.displayName, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }
            .pickerStyle(.menu)
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityLabel("Entity scope picker")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(!canSave)
                .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Helpers

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !query.isEmpty
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        let search = SavedSearch(
            name: name.trimmingCharacters(in: .whitespaces),
            query: query,
            entity: selectedEntity
        )
        do {
            try await store.save(search)
            isSaving = false
            onSaved(search)
            dismiss()
        } catch SavedSearchStore.SavedSearchStoreError.duplicateName(let existing) {
            isSaving = false
            errorMessage = "A saved search named \"\(existing)\" already exists. Choose a different name."
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}
