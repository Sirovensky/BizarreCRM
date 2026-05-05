import SwiftUI
import DesignSystem

// MARK: - §18.2 Per-list scoped search bar
//
// Every list view (Tickets, Customers, Inventory, Invoices, etc.) gets a
// top-sticky glass search bar + filter chip row.  This file provides the
// reusable components so every list is consistent without duplicating code.
//
// Usage in a list view:
//
//   .modifier(ScopedSearchModifier(
//       query: $query,
//       filters: $activeFilter,
//       filterOptions: TicketFilter.allCases,
//       sortOptions: TicketSort.allCases,
//       activeSort: $activeSort,
//       onQueryChanged: { vm.search($0) },
//       onFilterChanged: { vm.filter($0) },
//       onSortChanged: { vm.sort($0) }
//   ))
//
// The modifier injects a searchable bar via `.searchable`, a filter chip bar
// as a `safeAreaInset(edge: .top)`, and a sort menu in the toolbar.
//
// iPad: search stays in the list column; chips adapt to the available width.

// MARK: - ScopedFilterOption protocol

/// Adopted by per-list filter enums (e.g. `TicketFilter`, `CustomerFilter`).
public protocol ScopedFilterOption: Identifiable, Hashable, CaseIterable {
    /// Short label shown on the chip.
    var chipLabel: String { get }
    /// SF Symbol for the chip icon.
    var chipIcon: String { get }
}

// MARK: - ScopedSortOption protocol

/// Adopted by per-list sort enums.
public protocol ScopedSortOption: Identifiable, Hashable, CaseIterable {
    /// Menu label, e.g. "Newest first".
    var menuLabel: String { get }
    /// SF Symbol for the sort icon.
    var menuIcon: String { get }
}

// MARK: - ScopedSearchBar

/// A self-contained top-sticky glass search field + filter chips.
/// Embedded as a `safeAreaInset(edge: .top)` by `ScopedSearchModifier`.
public struct ScopedSearchBar<Filter: ScopedFilterOption>: View {

    let query: Binding<String>
    let filters: Binding<Filter?>
    let filterOptions: [Filter]
    var prompt: String = "Search…"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        query: Binding<String>,
        filters: Binding<Filter?>,
        filterOptions: [Filter],
        prompt: String = "Search…"
    ) {
        self.query = query
        self.filters = filters
        self.filterOptions = filterOptions
        self.prompt = prompt
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                TextField(prompt, text: query)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Search")
                if !query.wrappedValue.isEmpty {
                    Button {
                        withAnimation(reduceMotion ? .none : BrandMotion.snappy) {
                            query.wrappedValue = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.sm)

            // Filter chip row
            if !filterOptions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BrandSpacing.xs) {
                        // "All" chip
                        chipButton(
                            label: "All",
                            icon: "line.3.horizontal.decrease",
                            isSelected: filters.wrappedValue == nil
                        ) {
                            withAnimation(reduceMotion ? .none : BrandMotion.snappy) {
                                filters.wrappedValue = nil
                            }
                        }
                        ForEach(filterOptions, id: \.id) { option in
                            chipButton(
                                label: option.chipLabel,
                                icon: option.chipIcon,
                                isSelected: filters.wrappedValue?.id == option.id
                            ) {
                                withAnimation(reduceMotion ? .none : BrandMotion.snappy) {
                                    filters.wrappedValue = option
                                }
                            }
                        }
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.xs)
                }
            }

            Divider()
                .background(Color.bizarreSurface2)
        }
        .brandGlass(in: Rectangle())
    }

    private func chipButton(
        label: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .background(
                    isSelected
                        ? Color.bizarreOrange.opacity(0.15)
                        : Color.bizarreSurface2,
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Selected" : "Tap to filter by \(label)")
    }
}

// MARK: - ScopedSearchModifier

/// View modifier that adds `ScopedSearchBar` + sort menu toolbar item to any list.
///
/// Apply via `.modifier(ScopedSearchModifier(...))` inside `NavigationStack` /
/// `NavigationSplitView`.
///
/// The modifier adds the chip bar as a `.safeAreaInset(edge: .top)` so it sticks
/// above the list scroll area and is visually separated by a glass background.
public struct ScopedSearchModifier<Filter: ScopedFilterOption, Sort: ScopedSortOption>: ViewModifier {

    @Binding var query: String
    @Binding var activeFilter: Filter?
    let filterOptions: [Filter]
    @Binding var activeSort: Sort?
    let sortOptions: [Sort]
    var prompt: String = "Search…"
    var onQueryChanged: ((String) -> Void)?
    var onSortChanged: ((Sort?) -> Void)?

    public init(
        query: Binding<String>,
        activeFilter: Binding<Filter?>,
        filterOptions: [Filter],
        activeSort: Binding<Sort?>,
        sortOptions: [Sort],
        prompt: String = "Search…",
        onQueryChanged: ((String) -> Void)? = nil,
        onSortChanged: ((Sort?) -> Void)? = nil
    ) {
        self._query = query
        self._activeFilter = activeFilter
        self.filterOptions = filterOptions
        self._activeSort = activeSort
        self.sortOptions = sortOptions
        self.prompt = prompt
        self.onQueryChanged = onQueryChanged
        self.onSortChanged = onSortChanged
    }

    public func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                ScopedSearchBar(
                    query: Binding(
                        get: { query },
                        set: { newValue in
                            query = newValue
                            onQueryChanged?(newValue)
                        }
                    ),
                    filters: $activeFilter,
                    filterOptions: filterOptions,
                    prompt: prompt
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
            }
    }

    @ViewBuilder
    private var sortMenu: some View {
        if !sortOptions.isEmpty {
            Menu {
                ForEach(sortOptions, id: \.id) { option in
                    Button {
                        activeSort = option
                        onSortChanged?(option)
                    } label: {
                        Label(option.menuLabel, systemImage: option.menuIcon)
                    }
                }
                Divider()
                Button {
                    activeSort = nil
                    onSortChanged?(nil)
                } label: {
                    Label("Default order", systemImage: "arrow.up.arrow.down")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle\(activeSort != nil ? ".fill" : "")")
                    .accessibilityLabel("Sort")
                    .accessibilityHint(activeSort.map { "Sorted by \($0.menuLabel)" } ?? "Default order")
            }
        }
    }
}

// MARK: - View extension for ergonomics

public extension View {
    /// Attach a scoped search bar + filter chips + sort menu to a list view.
    func scopedSearch<F: ScopedFilterOption, S: ScopedSortOption>(
        query: Binding<String>,
        activeFilter: Binding<F?>,
        filterOptions: [F],
        activeSort: Binding<S?>,
        sortOptions: [S],
        prompt: String = "Search…",
        onQueryChanged: ((String) -> Void)? = nil,
        onSortChanged: ((S?) -> Void)? = nil
    ) -> some View {
        modifier(ScopedSearchModifier(
            query: query,
            activeFilter: activeFilter,
            filterOptions: filterOptions,
            activeSort: activeSort,
            sortOptions: sortOptions,
            prompt: prompt,
            onQueryChanged: onQueryChanged,
            onSortChanged: onSortChanged
        ))
    }
}
