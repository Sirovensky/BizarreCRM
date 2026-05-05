import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - SnippetsListView

/// Categorised list of SMS snippets with search filter and CRUD actions.
/// iPhone: `NavigationStack` + `List`; iPad: split-view-ready with wider rows and hover effects.
public struct SnippetsListView: View {
    @State private var vm: SnippetsListViewModel
    @State private var showEditor: Bool = false
    @State private var editingSnippet: Snippet?
    @State private var searchText: String = ""

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient, onPick: ((Snippet) -> Void)? = nil) {
        self.api = api
        _vm = State(wrappedValue: SnippetsListViewModel(api: api, onPick: onPick))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showEditor, onDismiss: { editingSnippet = nil }) {
            SnippetEditorSheet(snippet: editingSnippet, api: api) { _ in
                showEditor = false
                Task { await vm.load() }
            }
        }
    }

    // MARK: - iPhone layout

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("SMS Snippets")
            .searchable(text: $searchText, prompt: "Search snippets")
            .onChange(of: searchText) { _, q in vm.searchQuery = q }
            .toolbar { toolbarItems }
        }
    }

    // MARK: - iPad layout

    private var regularLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("SMS Snippets")
            .searchable(text: $searchText, prompt: "Search snippets")
            .onChange(of: searchText) { _, q in vm.searchQuery = q }
            .toolbar { toolbarItems }
        }
    }

    // MARK: - Content switcher

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorView(err)
        } else if vm.filtered.isEmpty {
            emptyView
        } else {
            snippetList
        }
    }

    // MARK: - List

    private var snippetList: some View {
        List {
            categoryFilterBar
            ForEach(vm.groupedFiltered, id: \.category) { group in
                Section(header: categoryHeader(group.category)) {
                    ForEach(group.snippets) { snippet in
                        SnippetRow(snippet: snippet, isPicker: vm.onPick != nil)
                            .listRowBackground(Color.bizarreSurface1)
                            .hoverEffect(.highlight)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                deleteButton(for: snippet)
                                editButton(for: snippet)
                            }
                            .contextMenu {
                                Button {
                                    editingSnippet = snippet
                                    showEditor = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    Task { await vm.delete(snippet: snippet) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .onTapGesture {
                                if vm.onPick != nil {
                                    vm.pick(snippet)
                                } else {
                                    editingSnippet = snippet
                                    showEditor = true
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func categoryHeader(_ category: String) -> some View {
        Text(category.isEmpty ? "Uncategorised" : category.capitalized)
            .font(.brandLabelLarge())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .textCase(nil)
    }

    private var categoryFilterBar: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    FilterChip(
                        label: "All",
                        isActive: vm.filterCategory == nil
                    ) { vm.filterCategory = nil }

                    ForEach(vm.allCategories, id: \.self) { cat in
                        FilterChip(
                            label: cat.capitalized,
                            isActive: vm.filterCategory == cat
                        ) { vm.filterCategory = cat }
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: BrandSpacing.md, bottom: 0, trailing: BrandSpacing.md))
        }
    }

    // MARK: - Swipe actions

    private func deleteButton(for snippet: Snippet) -> some View {
        Button(role: .destructive) {
            Task { await vm.delete(snippet: snippet) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityLabel("Delete snippet \(snippet.title)")
    }

    private func editButton(for snippet: Snippet) -> some View {
        Button {
            editingSnippet = snippet
            showEditor = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(.bizarreOrange)
        .accessibilityLabel("Edit snippet \(snippet.title)")
    }

    // MARK: - Empty / error

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "text.quote")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No snippets")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            if vm.onPick == nil {
                Button("Create your first snippet") {
                    editingSnippet = nil
                    showEditor = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load snippets")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if vm.onPick == nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingSnippet = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New snippet")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelSmall())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(isActive ? Color.white : .bizarreOnSurface)
                .background(
                    isActive ? Color.bizarreOrange : Color.bizarreSurface2,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityLabel("\(label) filter\(isActive ? ", selected" : "")")
    }
}

// MARK: - SnippetRow

private struct SnippetRow: View {
    let snippet: Snippet
    let isPicker: Bool

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            Image(systemName: "text.quote")
                .font(.system(size: 18))
                .foregroundStyle(.bizarreOrange)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack(spacing: BrandSpacing.xs) {
                    Text(snippet.title)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    Text("/\(snippet.shortcode)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
                Text(snippet.content)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)

                if let cat = snippet.category, !cat.isEmpty {
                    Text(cat.capitalized)
                        .font(.brandLabelSmall())
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, BrandSpacing.xxs)
                        .foregroundStyle(.bizarreOnSurface)
                        .background(Color.bizarreSurface2, in: Capsule())
                }
            }
            Spacer()
            if isPicker {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snippet.title). /\(snippet.shortcode). \(snippet.content)")
    }
}
