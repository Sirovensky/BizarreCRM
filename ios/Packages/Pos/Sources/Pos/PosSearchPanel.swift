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

    /// When set, the panel is waiting for results matching a scanned
    /// barcode so it can auto-pick the first hit.
    @State private var pendingScanCode: String?
    @State private var showingScanSheet: Bool = false

    /// Active category filter — nil means "All" / "Matches" pseudo-chip.
    @State private var activeCategory: String? = nil

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
        if !categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "All / Matches" chip
                    let matchLabel = search.results.isEmpty
                        ? "All"
                        : (search.query.isEmpty ? "All" : "Matches · \(search.results.count)")
                    PosFilterChip(
                        label: matchLabel,
                        isActive: activeCategory == nil
                    ) {
                        activeCategory = nil
                    }
                    ForEach(categories, id: \.self) { cat in
                        PosFilterChip(
                            label: cat,
                            isActive: activeCategory == cat
                        ) {
                            activeCategory = cat
                        }
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, 10)
            }
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

    /// Filter the results by active category (itemType).
    private var filteredResults: [InventoryListItem] {
        guard let cat = activeCategory else { return search.results }
        return search.results.filter { $0.itemType == cat }
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
                        isInCart: cartItemInventoryIds.contains(item.id)
                    ) {
                        BrandHaptics.success()
                        onPick(item)
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

/// Single category filter chip. Active state uses cream fill.
struct PosFilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color(hex: 0x2B1400) : .bizarreOnSurface)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isActive
                        ? Color(hex: 0xFDEED0)
                        : Color.bizarreSurface2.opacity(0.6),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        isActive ? Color(hex: 0xFDEED0) : Color.bizarreOutline.opacity(0.9),
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

/// Single catalog tile — 110pt min height, 2-column grid.
/// Shows: "In cart" badge (top-right) · icon · name · price (cream) · stock count.
/// Matches mockup .tile class exactly.
struct PosCatalogTile: View {
    let item: InventoryListItem
    var isInCart: Bool = false
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Card body
                VStack(alignment: .leading, spacing: 6) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.bizarreSurface2.opacity(0.6))
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                    }
                    .frame(width: 34, height: 34)

                    Text(item.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    // Price + stock row (pinned to bottom)
                    HStack(alignment: .lastTextBaseline) {
                        if let cents = item.priceCents {
                            // Cream/primary price — Barlow Condensed in mockup
                            Text(CartMath.formatCents(cents))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color(hex: 0xFDEED0))
                                .monospacedDigit()
                        }
                        Spacer()
                        stockBadge
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isInCart
                                ? Color(hex: colorScheme == .dark ? 0xFDEED0 : 0xC2410C, alpha: colorScheme == .dark ? 0.35 : 0.30)
                                : Color.bizarreOutline.opacity(0.4),
                            lineWidth: isInCart ? 1 : 0.5
                        )
                )

                // "In cart" badge — top-right corner
                if isInCart {
                    Text("In cart")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color(hex: 0x2B1400))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color(hex: 0xFDEED0), in: Capsule())
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(
            "\(item.displayName)\(isInCart ? ", in cart" : "")" +
            (item.priceCents.map { ", \(CartMath.formatCents($0))" } ?? "")
        )
        .accessibilityAddTraits(isInCart ? [.isSelected] : [])
        .accessibilityIdentifier("pos.catalogTile.\(item.id)")
    }

    @ViewBuilder
    private var stockBadge: some View {
        // InventoryListItem.inStock is the quantity on hand; nil = service/unknown
        if let qty = item.inStock {
            let isLow = item.isLowStock || qty <= 3
            if isLow {
                Text("\(qty) low")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color(hex: 0xE8A33D)) // warning
            } else {
                Text("\(qty)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color(hex: 0x34C47E)) // success
            }
        } else {
            // No stock field = service item
            Text("Service")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color(hex: 0x34C47E))
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
                        // CLAUDE.md iPad-affordance: text-selectable IDs/SKUs (no-op on iPhone)
                        .textSelection(.enabled)
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

// MARK: - Color(hex:) helper

private extension Color {
    init(hex: Int, alpha: Double = 1) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double((hex >>  0) & 0xFF) / 255,
            opacity: alpha
        )
    }
}
#endif
