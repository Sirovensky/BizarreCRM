import SwiftUI
import DesignSystem

/// §18 — Settings → Saved Searches. CRUD list. Tap runs the search;
/// swipe-left reveals delete; long-press offers rename.
public struct SavedSearchListView: View {

    @State private var searches: [SavedSearch] = []
    @State private var errorMessage: String? = nil
    @State private var renameTarget: SavedSearch? = nil
    @State private var renameText: String = ""

    private let store: SavedSearchStore
    private let ftsStore: FTSIndexStore

    public init(store: SavedSearchStore, ftsStore: FTSIndexStore) {
        self.store = store
        self.ftsStore = ftsStore
    }

    public var body: some View {
        List {
            ForEach(searches) { search in
                savedRow(search)
            }
            .onDelete(perform: delete)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.plain)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Saved Searches")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            #endif
        }
        .alert("Rename Search", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") { Task { await commitRename() } }
                .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
        .task { await loadSearches() }
        .overlay {
            if searches.isEmpty {
                ContentUnavailableView(
                    "No Saved Searches",
                    systemImage: "bookmark.slash",
                    description: Text("Save a search to reuse it later.")
                )
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func savedRow(_ search: SavedSearch) -> some View {
        NavigationLink(
            destination: EntitySearchView(
                store: ftsStore,
                prefilledQuery: search.query,
                initialFilter: search.entity
            )
        ) {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: search.entity.systemImage)
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(search.name)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(search.query)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
                Spacer()
                Text(search.entity.displayName)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding(.vertical, BrandSpacing.xxs)
        }
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(search.name), \(search.entity.displayName), query: \(search.query)")
        .accessibilityHint("Double-tap to open search")
        .swipeActions(edge: .leading) {
            Button {
                renameText = search.name
                renameTarget = search
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.bizarreOrange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await deleteSearch(id: search.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                renameText = search.name
                renameTarget = search
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                Task { await deleteSearch(id: search.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            Task { await store.recordUse(id: search.id) }
        })
    }

    // MARK: - Actions

    private func loadSearches() async {
        searches = await store.all
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { searches[$0] }
        Task {
            for item in toDelete { await store.delete(id: item.id) }
            await loadSearches()
        }
    }

    private func deleteSearch(id: String) async {
        await store.delete(id: id)
        await loadSearches()
    }

    private func commitRename() async {
        guard let target = renameTarget else { return }
        do {
            try await store.rename(id: target.id, newName: renameText)
            renameTarget = nil
            await loadSearches()
        } catch SavedSearchStore.SavedSearchStoreError.duplicateName(let existing) {
            errorMessage = "A saved search named \"\(existing)\" already exists."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
