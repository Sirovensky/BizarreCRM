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
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
                    .padding(.bottom, BrandSpacing.xs)
                resultsContent
            }
        }
    }

    /// Prominent glass-styled search field. Tall 48pt minimum so thumb
    /// accuracy is ok at the top of a larger-screen iPhone. No scan icon
    /// yet — DataScannerViewController lands in §17.2. When it arrives,
    /// drop a trailing Button(label: Image("barcode.viewfinder")) here.
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
            // custom-line entry points so staff have somewhere to tap
            // without scrolling through an error-looking placeholder.
            ScrollView {
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: search.query.isEmpty ? "barcode.viewfinder" : "questionmark.folder")
                        .font(.system(size: 44))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text(search.query.isEmpty ? "Scan or search to add items" : "No matches")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if search.query.isEmpty {
                        Text("Type a name, SKU, or barcode — or tap below to add a one-off line.")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BrandSpacing.lg)
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
                .padding(.top, BrandSpacing.xxl)
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
