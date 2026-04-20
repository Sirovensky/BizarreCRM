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

    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                searchField
                addCustomLineButton
                Divider().background(.bizarreOutline)
                resultsContent
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField("Search items", text: Binding(
                get: { search.query },
                set: { search.onQueryChange($0) }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
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
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
    }

    private var addCustomLineButton: some View {
        Button {
            onAddCustom()
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.bizarreOrange)
                Text("Add custom line")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Add custom line to cart")
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
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 44))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(search.query.isEmpty ? "Start searching" : "No results")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
