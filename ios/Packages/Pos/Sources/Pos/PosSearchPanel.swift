#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Inventory
import Networking

// MARK: - PosSearchPanel

/// Item-picker column. Houses the search bar, category filter chips,
/// a 2-column tile grid of results (matching mockup screen 2), and the
/// "Add custom line" entry point. On iPhone this is the full catalog tab;
/// on iPad it is the leading column of the register layout.
struct PosSearchPanel: View {
    @Bindable var search: PosSearchViewModel
    let onPick: (InventoryListItem) -> Void
    let onAddCustom: () -> Void
    var showsCustomerCTAs: Bool = false
    var onWalkIn: (() -> Void)? = nil
    var onCreateCustomer: (() -> Void)? = nil
    var onFindCustomer: (() -> Void)? = nil

    /// IDs currently in the cart — drives the "In cart" badge on tiles.
    var cartItemInventoryIds: Set<Int64> = []

    /// §16.2 — Favorites + recently-sold + filter chips wiring.
    /// Pass the PosViewModel from PosView for full feature integration.
    var posVM: PosViewModel? = nil

    /// When set, the panel is waiting for results matching a scanned
    /// barcode so it can auto-pick the first hit.
    @State private var pendingScanCode: String?
    @State private var showingScanSheet: Bool = false

    /// iPad only: active filter chip. `nil` = "All" (no filter).
    @State private var activeFilter: String? = nil

    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
                    .padding(.bottom, BrandSpacing.xs)
                // iPad screen 2: filter chip row above catalog when results exist.
                if hSizeClass == .regular, !search.results.isEmpty {
                    filterChipRow
                }
                resultsContent
            }
        }
        .sheet(isPresented: $showingScanSheet) {
            PosScanSheet { code in
                handleScan(code)
            }
        }
        // §16.2 — Long-press quick-preview sheet.
        .sheet(item: $previewItem) { item in
            PosCatalogTilePreviewSheet(
                item: item,
                isFavorite: posVM?.isFavorite(itemId: item.id) ?? false,
                onAddToCart: {
                    BrandHaptics.success()
                    onPick(item)
                },
                onToggleFavorite: {
                    posVM?.toggleFavorite(itemId: item.id)
                }
            )
        }
        // §16.2 — Extended filter sheet.
        .sheet(isPresented: $showingFilterSheet) {
            if let posVM {
                PosCatalogFilterSheet(filter: Binding(
                    get: { posVM.catalogFilter },
                    set: { posVM.catalogFilter = $0 }
                ))
            }
        }
        // §16.2 — Repair services: load when Services chip is tapped.
        .onChange(of: activeCategory) { _, newCat in
            if newCat == "service" || newCat == "Services" {
                Task { await posVM?.loadRepairServicesIfNeeded() }
            }
        }
        .onChange(of: search.results) { _, newResults in
            guard let scanCode = pendingScanCode, !search.isLoading else { return }
            _ = scanCode
            if let first = newResults.first {
                pendingScanCode = nil
                BrandHaptics.success()
                onPick(first)
            } else {
                pendingScanCode = nil
            }
        }
    }

    private func handleScan(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingScanCode = trimmed
        search.onQueryChange(trimmed)
    }

    // MARK: - Search field

    /// Prominent glass-styled search field. 48pt minimum thumb-friendly height.
    private var searchField: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            TextField("Search items or scan", text: Binding(
                get: { search.query },
                set: { search.onQueryChange($0) }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("pos.searchField")
            if !search.query.isEmpty {
                Button {
                    search.onQueryChange("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            Button {
                BrandHaptics.tap()
                showingScanSheet = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .foregroundStyle(.bizarreOrange)
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan barcode")
            .accessibilityIdentifier("pos.scanButton")
        }
        .padding(.horizontal, BrandSpacing.md)
        .frame(minHeight: 48)
        .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
    }

    // MARK: - Filter chips (mockup: chip-row / items-filters)

    @ViewBuilder
    private var filterChips: some View {
        // Build chip labels: first chip is "Matches · N" when results exist, else "All"
        let categories = derivedCategories
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All / Matches" chip — clears all chip filters.
                let matchLabel = search.results.isEmpty
                    ? "All"
                    : (search.query.isEmpty ? "All" : "Matches · \(filteredResults.count)")
                PosFilterChip(
                    label: matchLabel,
                    isActive: activeCategory == nil && !showingFavoritesOnly && !showingRecentlySoldOnly
                ) {
                    activeCategory = nil
                    showingFavoritesOnly = false
                    showingRecentlySoldOnly = false
                }

                // §16.2 Favorites chip — shown when posVM is available.
                if let posVM, !posVM.favoriteItemIds.isEmpty {
                    PosFilterChip(
                        label: "★ Favorites",
                        isActive: showingFavoritesOnly
                    ) {
                        showingFavoritesOnly.toggle()
                        showingRecentlySoldOnly = false
                        activeCategory = nil
                    }
                }

                // §16.2 Recently sold chip — top 10 sold on this register.
                if let posVM, !posVM.recentlySoldIds.isEmpty {
                    PosFilterChip(
                        label: "Recent",
                        isActive: showingRecentlySoldOnly
                    ) {
                        showingRecentlySoldOnly.toggle()
                        showingFavoritesOnly = false
                        activeCategory = nil
                    }
                }

                // Category chips derived from search results.
                ForEach(categories, id: \.self) { cat in
                    PosFilterChip(
                        label: cat,
                        isActive: activeCategory == cat && !showingFavoritesOnly && !showingRecentlySoldOnly
                    ) {
                        activeCategory = cat
                        showingFavoritesOnly = false
                        showingRecentlySoldOnly = false
                    }
                }

                // §16.2 Extended filter button — funnel icon.
                if posVM != nil {
                    let isFilterActive = posVM?.catalogFilter.isFiltered ?? false
                    Button {
                        showingFilterSheet = true
                    } label: {
                        Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isFilterActive ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                            .frame(width: 34, height: 34)
                            .background(Color.bizarreSurface2.opacity(0.6), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityLabel(isFilterActive ? "Filters active — tap to change" : "Filter catalog")
                    .accessibilityIdentifier("pos.filterButton")
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, 10)
        }
    }

    /// Derive category labels from search results using itemType as category.
    private var derivedCategories: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in search.results {
            if let cat = item.itemType, !cat.isEmpty, !seen.contains(cat) {
                seen.insert(cat)
                result.append(cat)
            }
        }
        return result
    }

    /// Apply all active chip filters + posVM client-side filters.
    private var filteredResults: [InventoryListItem] {
        var items = search.results

        // §16.2 Favorites chip
        if showingFavoritesOnly, let posVM {
            items = items.filter { posVM.isFavorite(itemId: $0.id) }
        }

        // §16.2 Recently sold chip
        if showingRecentlySoldOnly, let posVM {
            let recentSet = Set(posVM.recentlySoldIds)
            items = items.filter { recentSet.contains($0.id) }
        }

        // Category chip (derived from itemType)
        if let cat = activeCategory, !showingFavoritesOnly, !showingRecentlySoldOnly {
            items = items.filter { $0.itemType == cat }
        }

        // §16.2 Extended filter sheet (price, in-stock, taxable)
        if let posVM {
            items = posVM.applyClientFilters(to: items)
            // Sort: favorites float first.
            items = posVM.sorted(items)
        }

        return items
    }

    // MARK: - Results area

    @ViewBuilder
    private var resultsContent: some View {
        if search.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = search.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreError)
                Text("Couldn't load items")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
                Button("Try again") {
                    Task { await search.load() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if search.results.isEmpty {
            emptyOrHome
        } else {
            // 2-column tile grid (mockup: grid-template-columns: 1fr 1fr)
            catalogGrid
        }
    }

    // MARK: - iPad filter chip row

    /// Horizontal scrollable category filter chips above the catalog grid.
    /// Matches iPad mockup screen 2: "Matches · N / Screens / Batteries / …"
    /// Categories are derived from distinct `category` values in current results.
    private var filterChipRow: some View {
        let categories = distinctCategories
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                // "Matches · N" all-results chip
                FilterChip(
                    label: "Matches · \(search.results.count)",
                    isActive: activeFilter == nil
                ) {
                    BrandHaptics.tap()
                    activeFilter = nil
                }

                ForEach(categories, id: \.self) { cat in
                    FilterChip(label: cat, isActive: activeFilter == cat) {
                        BrandHaptics.tap()
                        activeFilter = activeFilter == cat ? nil : cat
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
        }
        .accessibilityIdentifier("pos.catalogFilterChips")
    }

    /// Unique item-type labels from the current result set, preserving order
    /// of first appearance. Nil / empty item types are dropped.
    private var distinctCategories: [String] {
        var seen = Set<String>()
        return search.results.compactMap { item -> String? in
            guard let type_ = item.itemType, !type_.isEmpty else { return nil }
            let label = type_.capitalized
            return seen.insert(label).inserted ? label : nil
        }
    }

    /// Three-button customer-attach stack shown on the POS home screen
    /// when no customer is attached yet. Matches desktop's walk-in /
    /// find / create workflow so staff have an obvious starting point.
    private var customerCTAStack: some View {
        VStack(spacing: BrandSpacing.sm) {
            if let onWalkIn {
                ctaButton(
                    icon: "person.fill.questionmark",
                    title: "Walk-in customer",
                    subtitle: "Guest checkout — no record",
                    identifier: "pos.attachWalkIn",
                    action: onWalkIn
                )
            }
            if let onFindCustomer {
                ctaButton(
                    icon: "magnifyingglass",
                    title: "Find existing customer",
                    subtitle: "Search by name or phone",
                    identifier: "pos.findCustomer",
                    action: onFindCustomer
                )
            }
            if let onCreateCustomer {
                ctaButton(
                    icon: "person.crop.circle.badge.plus",
                    title: "Create new customer",
                    subtitle: "Save contact + attach",
                    identifier: "pos.createCustomer",
                    action: onCreateCustomer
                )
            }
        }
        .frame(maxWidth: 420)
    }

    private func ctaButton(icon: String, title: String, subtitle: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(subtitle)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .frame(minHeight: 56)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle).")
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - FilterChip

/// Pill-shaped filter chip for the iPad catalog filter row (mockup screen 2).
private struct FilterChip: View {
    let label: String
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(isActive ? Color.bizarreOnOrange : .bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xs)
                .background(
                    isActive
                        ? Color.bizarreOrange
                        : Color.bizarreSurface1.opacity(0.6),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        isActive ? Color.bizarreOrange : Color.bizarreOutline.opacity(0.5),
                        lineWidth: isActive ? 0 : 0.5
                    )
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("\(label) filter\(isActive ? ", selected" : "")")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// Result row in the POS picker — shows name + SKU + price. No stock
/// colour coding at scaffold level; coming in §16.2.
struct PosSearchRow: View {
    let item: InventoryListItem

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(item.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)
                if let sku = item.sku, !sku.isEmpty {
                    Text("SKU \(sku)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            if let cents = item.priceCents {
                Text(CartMath.formatCents(cents))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOrange)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
    }
}

#endif
