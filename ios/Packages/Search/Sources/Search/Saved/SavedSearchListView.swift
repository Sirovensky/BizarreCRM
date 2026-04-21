import SwiftUI
import Core
import DesignSystem

/// §18.5 — Settings → Saved Searches. CRUD list; tap opens EntitySearchView.
public struct SavedSearchListView: View {

    @State private var searches: [SavedSearch] = []
    @State private var showingAdd: Bool = false
    @State private var newName: String = ""
    @State private var newQuery: String = ""
    @State private var newEntity: EntityFilter = .all
    @State private var editingId: String? = nil
    @State private var renameText: String = ""

    private let store: SavedSearchStore
    private let ftsStore: FTSIndexStore

    public init(store: SavedSearchStore, ftsStore: FTSIndexStore) {
        self.store = store
        self.ftsStore = ftsStore
    }

    public var body: some View {
        NavigationStack {
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add saved search")
                }
            }
            .sheet(isPresented: $showingAdd) {
                addSheet
            }
            .task {
                await loadSearches()
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await deleteSearch(id: search.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Add sheet

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Search details") {
                    TextField("Name", text: $newName)
                        .accessibilityLabel("Saved search name")
                    TextField("Query", text: $newQuery)
                        .accessibilityLabel("Search query")
                }
                Section("Entity") {
                    Picker("Entity", selection: $newEntity) {
                        ForEach(EntityFilter.allCases, id: \.self) { filter in
                            Label(filter.displayName, systemImage: filter.systemImage)
                                .tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("New Saved Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetAddForm()
                        showingAdd = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await addSearch() }
                    }
                    .disabled(newName.isEmpty || newQuery.isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadSearches() async {
        searches = await store.all
    }

    private func addSearch() async {
        let search = SavedSearch(name: newName, query: newQuery, entity: newEntity)
        await store.save(search)
        resetAddForm()
        showingAdd = false
        await loadSearches()
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

    private func resetAddForm() {
        newName = ""
        newQuery = ""
        newEntity = .all
    }
}
