#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// Adaptive catalog grid for the iPad POS catalog column.
///
/// Uses a `LazyVGrid` whose column count is derived from the container width:
///
/// | Container width | Tile min | Columns |
/// |-----------------|----------|---------|
/// | < 400 pt        |  min 2   |  ≥ 2    |
/// | 400 – 700 pt    |  ~160 pt |  3 – 4  |
/// | > 700 pt        |  ~160 pt |  4 – 5  |
///
/// Tile sizes are computed using `GridItem(.adaptive(minimum:maximum:))` so
/// SwiftUI fills available width without fractional leftovers.
///
/// The grid is embedded inside `PosSearchPanel`'s results path when the caller
/// passes `layout: .grid`; the list/row path used on iPhone remains the default.
public struct PosCatalogGrid: View {

    // MARK: - Properties

    let items: [InventoryListItem]
    let onPick: (InventoryListItem) -> Void

    /// Minimum tile width used for adaptive grid sizing (pts).
    private let tileMinWidth: CGFloat

    /// Maximum tile width — prevents tiles from being too wide on large pads.
    private let tileMaxWidth: CGFloat

    // MARK: - Init

    public init(
        items: [InventoryListItem],
        tileMinWidth: CGFloat = 140,
        tileMaxWidth: CGFloat = 220,
        onPick: @escaping (InventoryListItem) -> Void
    ) {
        self.items = items
        self.tileMinWidth = tileMinWidth
        self.tileMaxWidth = tileMaxWidth
        self.onPick = onPick
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { proxy in
            let columns = gridColumns(for: proxy.size.width)
            ScrollView {
                LazyVGrid(columns: columns, spacing: BrandSpacing.sm) {
                    ForEach(items) { item in
                        PosCatalogTile(item: item) {
                            BrandHaptics.success()
                            onPick(item)
                        }
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.sm)
                .padding(.bottom, BrandSpacing.xl)
            }
            .frame(width: proxy.size.width)
        }
        .accessibilityIdentifier("pos.ipad.catalogGrid")
    }

    // MARK: - Helpers

    /// Build adaptive grid columns for `containerWidth`.
    private func gridColumns(for containerWidth: CGFloat) -> [GridItem] {
        let usableWidth = containerWidth - BrandSpacing.base * 2
        // Adaptive sizing: SwiftUI picks how many tiles fit in `usableWidth`
        // given the min/max constraint. We derive the minimum from our token.
        let minWidth = max(tileMinWidth, usableWidth / 5) // never more than 5 wide
        return [GridItem(.adaptive(minimum: minWidth, maximum: tileMaxWidth), spacing: BrandSpacing.sm)]
    }
}

// MARK: - Tile

/// A single catalog tile for the grid. Square-ish with rounded corners, item
/// name, SKU, and price. Hover-highlighted for pointer devices.
struct PosCatalogTile: View {
    let item: InventoryListItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                // Icon placeholder — inventory images are not yet fetched in
                // this layer; the icon area provides visual rhythm.
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(Color.bizarreOrangeContainer.opacity(0.35))
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                }
                .frame(height: 64)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(item.displayName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let sku = item.sku, !sku.isEmpty {
                        Text(sku)
                            .font(.brandMono(size: 11))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }

                    if let cents = item.priceCents {
                        Text(CartMath.formatCents(cents))
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                }
            }
            .padding(BrandSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Add \(item.displayName) to cart\(item.priceCents.map { ", \(CartMath.formatCents($0))" } ?? "")")
        .accessibilityIdentifier("pos.catalogTile.\(item.id)")
    }
}

// MARK: - Preview

private func makePreviewItem(id: Int, name: String, sku: String, price: Double) -> InventoryListItem {
    let json = """
    {"id":\(id),"name":"\(name)","sku":"\(sku)","retail_price":\(price)}
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(InventoryListItem.self, from: json)
}

#Preview("Catalog Grid — iPad") {
    let items = (1...12).map { i in
        makePreviewItem(id: i, name: "Product \(i)", sku: "SKU-\(1000 + i)", price: Double(99 + i * 111) / 100)
    }
    ScrollView {
        PosCatalogGrid(items: items, onPick: { _ in })
    }
    .background(Color.bizarreSurface2)
    .preferredColorScheme(.dark)
    .previewInterfaceOrientation(.landscapeLeft)
}
#endif
