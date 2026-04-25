#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Inventory
import Networking

/// Item-picker column. Houses the search bar, the results list, and the
/// "Add custom line" entry point. On iPhone this sits under the cart; on
/// iPad it's the leading column of the split view.
struct PosSearchPanel: View {
    @Bindable var search: PosSearchViewModel
    let onPick: (InventoryListItem) -> Void
    let onAddCustom: () -> Void
    var showsCustomerCTAs: Bool = false
    var onWalkIn: (() -> Void)? = nil
    var onCreateCustomer: (() -> Void)? = nil
    var onFindCustomer: (() -> Void)? = nil

    /// When set, the panel is waiting for results matching a scanned
    /// barcode so it can auto-pick the first hit. Cleared as soon as
    /// that pick fires or the results finish loading empty.
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
        .onChange(of: search.results) { _, newResults in
            // When the scan-driven fetch lands, auto-add the first row
            // and clear the pending flag. If the scan produced zero
            // matches we still drop the flag so a stale code doesn't
            // re-trigger on the next organic fetch.
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

    /// Prominent glass-styled search field. Tall 48pt minimum so thumb
    /// accuracy is ok at the top of a larger-screen iPhone. Trailing
    /// `barcode.viewfinder` button opens the §17.2 DataScannerViewController
    /// sheet; on a matched payload we stuff the query and auto-add the
    /// first search result to the cart.
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
            // Empty state doubles as the POS home screen — feature scan +
            // customer-attach + custom-line entry points so staff have
            // somewhere to tap without scrolling through an error-looking
            // placeholder.
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
        } else {
            List(search.results) { item in
                Button {
                    BrandHaptics.success()
                    onPick(item)
                } label: {
                    PosSearchRow(item: item)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityLabel("Add \(item.displayName) to cart")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
    }
}
#endif
