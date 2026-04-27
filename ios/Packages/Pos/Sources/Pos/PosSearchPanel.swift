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

    /// §16.2 — Active category filter — nil means "All" / "Matches" pseudo-chip.
    @State private var activeCategory: String? = nil

    /// §16.2 — Preview sheet for long-press quick-preview.
    @State private var previewItem: InventoryListItem? = nil

    /// §16.2 — Extended filter sheet.
    @State private var showingFilterSheet: Bool = false

    /// §16.2 — "Favorites" chip selected.
    @State private var showingFavoritesOnly: Bool = false

    /// §16.2 — "Recently sold" chip selected.
    @State private var showingRecentlySoldOnly: Bool = false

    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
                    .padding(.bottom, BrandSpacing.xs)
                filterChips
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

    // MARK: - Catalog tile grid

    private var catalogGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(filteredResults) { item in
                    PosCatalogTile(
                        item: item,
                        isInCart: cartItemInventoryIds.contains(item.id),
                        isFavorite: posVM?.isFavorite(itemId: item.id) ?? false
                    ) {
                        BrandHaptics.success()
                        onPick(item)
                    } onLongPress: {
                        // §16.2 Long-press → quick-preview sheet.
                        BrandHaptics.tap()
                        previewItem = item
                    } onToggleFavorite: {
                        // §16.2 Star tap on tile toggles favorite.
                        posVM?.toggleFavorite(itemId: item.id)
                        BrandHaptics.tap()
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, 4)
            .padding(.bottom, BrandSpacing.xl)
        }
    }

    // MARK: - Empty / home state

    private var emptyOrHome: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: search.query.isEmpty ? "barcode.viewfinder" : "questionmark.folder")
                    .font(.system(size: 44))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(search.query.isEmpty ? "Start a sale" : "No matches")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if search.query.isEmpty {
                    Text("Type a name, SKU, or barcode to add items. Attach a customer first to track history.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.lg)
                }

                if showsCustomerCTAs, search.query.isEmpty {
                    customerCTAStack
                        .padding(.top, BrandSpacing.sm)
                }

                Button {
                    onAddCustom()
                } label: {
                    Label("Add a custom line", systemImage: "plus.circle.fill")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOrange)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .background(Color.bizarreSurface1, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.bizarreOrange.opacity(0.35), lineWidth: 0.5))
                .accessibilityIdentifier("pos.addCustomLine")
                .accessibilityLabel("Add a custom line to cart")
            }
            .padding(.top, BrandSpacing.xl)
            .padding(.horizontal, BrandSpacing.base)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Customer CTAs

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

// MARK: - PosFilterChip

/// Single category filter chip. Active state uses bizarreOrange fill
/// (cream in dark mode, dark-amber in light mode via the adaptive token).
struct PosFilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color.bizarreOnOrange : .bizarreOnSurface)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isActive
                        ? Color.bizarreOrange
                        : Color.bizarreSurface2.opacity(0.6),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        isActive ? Color.bizarreOrange : Color.bizarreOutline.opacity(0.9),
                        lineWidth: 0.5
                    )
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(label + (isActive ? ", selected" : ""))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityIdentifier("pos.filter.\(label)")
    }
}

// MARK: - PosCatalogTile (iPhone 2-col + iPad grid)

/// Single catalog tile — matches mockup `.tile` class exactly.
///
/// - iPhone: 12pt padding, 110pt min-height, 34×34 icon box, 20pt price, badge inset 8/8.
/// - iPad:   14pt padding, 132pt min-height, bare 22pt icon (no box), 24pt price, badge inset 9/9.
///
/// Set `isPad = true` when rendering inside `PosCatalogGrid`.
struct PosCatalogTile: View {
    let item: InventoryListItem
    var isInCart: Bool = false
    /// Whether this item is in the cashier's favorites list.
    var isFavorite: Bool = false
    /// Pass `true` from `PosCatalogGrid` to engage iPad sizing/layout.
    var isPad: Bool = false
    let onTap: () -> Void
    /// §16.2 Long-press → quick-preview sheet.
    var onLongPress: (() -> Void)? = nil
    /// §16.2 Star button tap → toggle favorite.
    var onToggleFavorite: (() -> Void)? = nil
    /// §16.15 When true this is a member-only product.
    var isMemberOnly: Bool = false
    /// §16.15 Whether a qualifying member is attached to the cart.
    /// When `isMemberOnly == true` and `hasMemberAttached == false`, the tile
    /// is dimmed and tapping is blocked with an explanatory label.
    var hasMemberAttached: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    // MARK: Layout constants (mockup-derived)
    private var tilePadding:    CGFloat { isPad ? 14 : 12 }
    private var tileMinHeight:  CGFloat { isPad ? 132 : 110 }
    private var priceFontSize:  CGFloat { isPad ? 24 : 20 }
    private var badgeInset:     CGFloat { isPad ? 9 : 8 }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Card body
                VStack(alignment: .leading, spacing: 6) {
                    // Icon row — box on iPhone, bare system image on iPad.
                    HStack(alignment: .top) {
                        if isPad {
                            Image(systemName: tileSystemImage)
                                .font(.system(size: 22))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityHidden(true)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.bizarreSurface2.opacity(0.6))
                                Image(systemName: tileSystemImage)
                                    .font(.system(size: 18))
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                    .accessibilityHidden(true)
                            }
                            .frame(width: 34, height: 34)
                        }
                        Spacer(minLength: 0)
                        // §16.2 Favorite star — top-right of icon row.
                        if let onToggleFavorite {
                            Button {
                                onToggleFavorite()
                            } label: {
                                Image(systemName: isFavorite ? "star.fill" : "star")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isFavorite ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                            .accessibilityIdentifier("pos.tile.favorite.\(item.id)")
                        }
                    }

                    Text(item.displayName)
                        .font(.system(size: isPad ? 13.5 : 13, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    // Price + stock row (pinned to bottom)
                    HStack(alignment: .lastTextBaseline) {
                        if let cents = item.priceCents {
                            // Primary price — cream in dark mode, dark-amber in light mode.
                            Text(CartMath.formatCents(cents))
                                .font(.system(size: priceFontSize, weight: .bold))
                                .foregroundStyle(.bizarreOrange)
                                .monospacedDigit()
                        }
                        Spacer()
                        stockBadge
                    }
                }
                .padding(tilePadding)
                .frame(maxWidth: .infinity, minHeight: tileMinHeight, alignment: .leading)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isInCart
                                ? Color.bizarreOrange.opacity(colorScheme == .dark ? 0.35 : 0.30)
                                : Color.bizarreOutline.opacity(0.4),
                            lineWidth: isInCart ? 1 : 0.5
                        )
                )

                // "In cart" badge — top-right corner (only when no favorite star above).
                if isInCart && onToggleFavorite == nil {
                    Text("In cart")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color.bizarreOnOrange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, isPad ? 3 : 2)
                        .background(Color.bizarreOrange, in: Capsule())
                        .padding(.top, badgeInset)
                        .padding(.trailing, badgeInset)
                }
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        // §16.2 Long-press → quick preview.
        .onLongPressGesture(minimumDuration: 0.4) {
            onLongPress?()
        }
        // §16.15 Member-only overlay: dim tile + lock interaction when no member.
        .overlay(alignment: .center) {
            if isMemberOnly && !hasMemberAttached {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.bizarreSurfaceBase.opacity(0.72))
                    .overlay {
                        VStack(spacing: 3) {
                            Image(systemName: "star.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.bizarreOrange.opacity(0.8))
                            Text("Members only")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .multilineTextAlignment(.center)
                        }
                    }
            }
        }
        .allowsHitTesting(!(isMemberOnly && !hasMemberAttached))
        .accessibilityLabel(
            "\(item.displayName)\(isInCart ? ", in cart" : "")\(isFavorite ? ", favorited" : "")" +
            (isMemberOnly && !hasMemberAttached ? ", members only" : "") +
            (item.priceCents.map { ", \(CartMath.formatCents($0))" } ?? "")
        )
        .accessibilityAddTraits(isInCart ? [.isSelected] : [])
        .accessibilityIdentifier("pos.catalogTile.\(item.id)")
    }

    private var tileSystemImage: String {
        switch item.itemType?.lowercased() {
        case "service":     return "wrench.and.screwdriver"
        case "part":        return "puzzlepiece"
        case "accessory":   return "cable.connector"
        default:            return "shippingbox.fill"
        }
    }

    @ViewBuilder
    private var stockBadge: some View {
        // InventoryListItem.inStock is the quantity on hand; nil = service/unknown
        if let qty = item.inStock {
            let isLow = item.isLowStock || qty <= 3
            if isLow {
                Text("\(qty) low")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.bizarreWarning)
            } else {
                Text("\(qty)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.bizarreSuccess)
            }
        } else {
            // No stock field = service item
            Text("Service")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.bizarreSuccess)
        }
    }
}

// MARK: - PosSearchRow (list fallback, kept for reference)

/// Result row in the POS picker — list style fallback (not used when grid is active).
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
