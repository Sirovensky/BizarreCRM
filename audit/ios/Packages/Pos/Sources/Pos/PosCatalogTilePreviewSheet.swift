#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Inventory
import Networking

// MARK: - PosCatalogTilePreviewSheet
//
// §16.2 Long-press quick-preview. Shows price, stock level, location,
// and last sold date for a catalog item without committing it to the cart.
//
// Presented as a `.medium` detent sheet. On iPad the tile is large enough
// that a long-press recogniser produces a natural context-menu equivalent;
// on iPhone it is the primary discovery gesture since tiles are smaller.
//
// Layout (per mockup)
//   ┌────────────────────┐
//   │  Icon  Name        │  ← header
//   │  $29.99            │  ← price
//   ├────────────────────┤
//   │  Stock  ·  Low     │  ← data row
//   │  Location: A-3     │
//   │  Last sold: 2d ago │
//   ├────────────────────┤
//   │  [Add to cart]     │  ← CTA
//   └────────────────────┘

public struct PosCatalogTilePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: InventoryListItem
    let isFavorite: Bool
    let onAddToCart: () -> Void
    let onToggleFavorite: () -> Void

    public init(
        item: InventoryListItem,
        isFavorite: Bool,
        onAddToCart: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void
    ) {
        self.item = item
        self.isFavorite = isFavorite
        self.onAddToCart = onAddToCart
        self.onToggleFavorite = onToggleFavorite
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        Divider().background(.bizarreOutline)
                        dataRows
                        Divider().background(.bizarreOutline)
                        addToCartButton
                    }
                    .padding(.bottom, BrandSpacing.xl)
                }
            }
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("catalogPreview.done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onToggleFavorite()
                        BrandHaptics.tap()
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? .bizarreOrange : .bizarreOnSurfaceMuted)
                    }
                    .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                    .accessibilityIdentifier("catalogPreview.favorite")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header (icon + price)

    private var header: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            // Placeholder icon — photo thumbnail deferred to Nuke integration.
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(Color.bizarreSurface2)
                Image(systemName: itemSystemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(item.displayName)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let sku = item.sku, !sku.isEmpty {
                    Text("SKU: \(sku)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                if let cents = item.priceCents {
                    Text(CartMath.formatCents(cents))
                        .font(.brandHeadlineLarge())
                        .foregroundStyle(.bizarreOrange)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.lg)
    }

    // MARK: - Data rows

    private var dataRows: some View {
        VStack(spacing: 0) {
            dataRow(
                icon: "shippingbox",
                label: "Stock",
                value: stockText,
                valueColor: stockColor
            )
            Divider().background(.bizarreOutline).padding(.leading, 48)

            dataRow(
                icon: "mappin.and.ellipse",
                label: "Location",
                value: "—"  // server field pending
            )
            Divider().background(.bizarreOutline).padding(.leading, 48)

            dataRow(
                icon: "clock.arrow.circlepath",
                label: "Last sold",
                value: lastSoldText
            )

            if let cat = item.itemType, !cat.isEmpty {
                Divider().background(.bizarreOutline).padding(.leading, 48)
                dataRow(
                    icon: "tag",
                    label: "Category",
                    value: cat.capitalized
                )
            }
        }
    }

    private func dataRow(
        icon: String,
        label: String,
        value: String,
        valueColor: Color = .bizarreOnSurface
    ) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandBodyLarge())
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.sm)
        .frame(minHeight: 44)
    }

    // MARK: - Add to cart CTA

    private var addToCartButton: some View {
        Button {
            BrandHaptics.success()
            onAddToCart()
            dismiss()
        } label: {
            Label("Add to cart", systemImage: "cart.badge.plus")
                .font(.brandTitleSmall())
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.top, BrandSpacing.lg)
        .accessibilityIdentifier("catalogPreview.addToCart")
    }

    // MARK: - Derived display values

    private var stockText: String {
        guard let qty = item.inStock else { return "Service" }
        if qty == 0 { return "Out of stock" }
        if qty <= 3 { return "\(qty) — Low" }
        return "\(qty) in stock"
    }

    private var stockColor: Color {
        guard let qty = item.inStock else { return .bizarreSuccess }
        if qty == 0 { return .bizarreError }
        if qty <= 3 { return .bizarreWarning }
        return .bizarreSuccess
    }

    // Last sold date is not yet in `InventoryListItem` (server gap).
    // Show a placeholder until the field lands.
    private var lastSoldText: String { "—" }

    private var itemSystemImage: String {
        switch item.itemType?.lowercased() {
        case "service":     return "wrench.and.screwdriver"
        case "part":        return "puzzlepiece"
        case "accessory":   return "cable.connector"
        default:            return "shippingbox.fill"
        }
    }
}

// MARK: - Convenience modifier on PosCatalogTile
//
// Wrap the existing `PosCatalogTile` with a long-press context menu that
// surfaces the quick-preview sheet. Applied in `PosSearchPanel.catalogGrid`.

extension InventoryListItem {
    /// True when the item is classified as a service (no stock tracking).
    var isService: Bool { itemType?.lowercased() == "service" }
}

#endif
