#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - PosCatalogGrid

/// Adaptive catalog grid for the iPad POS catalog column.
///
/// Column count is adaptive:
///
/// | Container width | Tile min | Target cols |
/// |-----------------|----------|-------------|
/// | < 400 pt        | min 2    | ≥ 2         |
/// | 400 – 700 pt    | ~160 pt  | 3 – 4       |
/// | > 700 pt        | ~160 pt  | 4 – 5       |
///
/// When `inspectorActive` is true the items area dims + blurs
/// (matching mockup `has-inspector` → `.items { opacity: 0.42; filter: blur(8px) }`)
/// — the dimming is applied by the parent `PosRegisterLayout`; the grid
/// itself just supplies the content.
public struct PosCatalogGrid: View {

    // MARK: - Properties

    let items: [InventoryListItem]
    let onPick: (InventoryListItem) -> Void

    /// IDs currently in the cart — drives "In cart" badge on tiles.
    var cartItemInventoryIds: Set<Int64> = []

    /// Minimum tile width used for adaptive grid sizing (pts).
    private let tileMinWidth: CGFloat

    /// Maximum tile width — prevents tiles from being too wide on large pads.
    private let tileMaxWidth: CGFloat

    // MARK: - Init

    public init(
        items: [InventoryListItem],
        tileMinWidth: CGFloat = 140,
        tileMaxWidth: CGFloat = 220,
        cartItemInventoryIds: Set<Int64> = [],
        onPick: @escaping (InventoryListItem) -> Void
    ) {
        self.items = items
        self.tileMinWidth = tileMinWidth
        self.tileMaxWidth = tileMaxWidth
        self.cartItemInventoryIds = cartItemInventoryIds
        self.onPick = onPick
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { proxy in
            let columns = gridColumns(for: proxy.size.width)
            ScrollView {
                LazyVGrid(columns: columns, spacing: BrandSpacing.sm) {
                    ForEach(items) { item in
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
