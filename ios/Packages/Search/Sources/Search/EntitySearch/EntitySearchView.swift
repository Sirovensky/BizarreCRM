import SwiftUI
import Core
import DesignSystem

/// §18.4 — Search scoped to one entity type, selected via chip bar.
public struct EntitySearchView: View {

    @State private var vm: EntitySearchViewModel
    @State private var queryText: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: FTSIndexStore, prefilledQuery: String = "", initialFilter: EntityFilter = .all) {
        let vm = EntitySearchViewModel(store: store)
        _vm = State(wrappedValue: vm)
        _queryText = State(wrappedValue: prefilledQuery)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterChipBar
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.xs)
                    .brandGlass(in: Rectangle())

                ZStack {
                    Color.bizarreSurfaceBase.ignoresSafeArea()
                    resultContent
                }
            }
            .navigationTitle("Search")
            .searchable(text: $queryText, prompt: "Search \(vm.selectedFilter.displayName)…")
            .onChange(of: queryText) { _, new in vm.onQueryChanged(new) }
        }
    }

    // MARK: - Filter chips

    private var filterChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(EntityFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        label: filter.displayName,
                        icon: filter.systemImage,
                        isSelected: vm.selectedFilter == filter
                    ) {
                        withAnimation(reduceMotion ? .none : BrandMotion.snappy) {
                            vm.selectedFilter = filter
                        }
                    }
                    .accessibilityAddTraits(vm.selectedFilter == filter ? .isSelected : [])
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }
    }

    // MARK: - Result content

    @ViewBuilder
    private var resultContent: some View {
        if queryText.isEmpty {
            emptyQueryPlaceholder
        } else if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorView(err)
        } else if vm.hits.isEmpty {
            noResultsView
        } else {
            hitList
        }
    }

    private var emptyQueryPlaceholder: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Type to search \(vm.selectedFilter.displayName.lowercased())")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var noResultsView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No results for \"\(queryText)\"")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Try different spelling or broaden the entity filter.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results for \(queryText)")
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Search failed")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search failed. \(message)")
    }

    private var hitList: some View {
        List {
            ForEach(vm.hits) { hit in
                SearchHitRow(hit: hit)
                    .listRowBackground(Color.bizarreSurface1)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.plain)
        #endif
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .brandGlass(isSelected ? .identity : .regular, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(isSelected ? "Selected" : "Tap to filter by \(label)")
    }
}

// MARK: - Search Hit Row

struct SearchHitRow: View {
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(hit.title)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
            if !hit.snippet.isEmpty {
                Text(hit.snippet)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)
            }
            Text(hit.entity.capitalized)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOrange)
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hit.title). \(hit.entity). \(hit.snippet)")
    }
}
