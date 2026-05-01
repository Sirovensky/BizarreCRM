#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - PosCatalogGrid

/// Adaptive catalog grid for the iPad POS catalog column.
///
/// Layout (top → bottom):
/// 1. Horizontal-scrolling filter chip row (when `filterChips` is non-empty).
/// 2. Adaptive `LazyVGrid` of catalog tiles.
///
/// Tile column count is derived from the container width:
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

    /// Optional filter chips shown in a horizontal scroll row above the grid.
    /// Each chip is a `(label: String, isActive: Bool)` pair. The parent owns
    /// the selection state and passes the tap handler.
    let filterChips: [CatalogFilterChip]
    let onFilterChipTap: ((CatalogFilterChip) -> Void)?

    /// Minimum tile width used for adaptive grid sizing (pts).
    private let tileMinWidth: CGFloat

    /// Maximum tile width — prevents tiles from being too wide on large pads.
    private let tileMaxWidth: CGFloat

    // MARK: - Init

    public init(
        items: [InventoryListItem],
        filterChips: [CatalogFilterChip] = [],
        onFilterChipTap: ((CatalogFilterChip) -> Void)? = nil,
        tileMinWidth: CGFloat = 140,
        tileMaxWidth: CGFloat = 220,
        cartItemInventoryIds: Set<Int64> = [],
        onPick: @escaping (InventoryListItem) -> Void
    ) {
        self.items = items
        self.filterChips = filterChips
        self.onFilterChipTap = onFilterChipTap
        self.tileMinWidth = tileMinWidth
        self.tileMaxWidth = tileMaxWidth
        self.cartItemInventoryIds = cartItemInventoryIds
        self.onPick = onPick
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Filter chip row — only shown when chips are provided.
            if !filterChips.isEmpty {
                filterChipRow
            }

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
        }
        .accessibilityIdentifier("pos.ipad.catalogGrid")
    }

    // MARK: - Filter chip row

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(filterChips) { chip in
                    Button {
                        BrandHaptics.tap()
                        onFilterChipTap?(chip)
                    } label: {
                        Text(chip.label)
                            .font(.brandLabelLarge())
                            .foregroundStyle(chip.isActive ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                            .padding(.horizontal, BrandSpacing.md)
                            .padding(.vertical, BrandSpacing.xs)
                            .background(
                                chip.isActive
                                    ? Color.bizarreOrange.opacity(0.15)
                                    : Color.bizarreSurface1,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        chip.isActive
                                            ? Color.bizarreOrange.opacity(0.55)
                                            : Color.bizarreOutline.opacity(0.4),
                                        lineWidth: chip.isActive ? 1.5 : 0.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityLabel(chip.label)
                    .accessibilityAddTraits(chip.isActive ? .isSelected : [])
                    .accessibilityIdentifier("pos.catalogFilter.\(chip.id)")
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
        }
        .accessibilityIdentifier("pos.ipad.filterChipRow")
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

// MARK: - CatalogFilterChip model

/// A single filter chip for the horizontal chip row above the catalog grid.
public struct CatalogFilterChip: Identifiable, Equatable, Hashable {
    public let id: String
    public let label: String
    public var isActive: Bool

    public init(id: String, label: String, isActive: Bool = false) {
        self.id = id
        self.label = label
        self.isActive = isActive
    }
}

// MARK: - Tile

/// A single catalog tile for the grid. Square-ish with rounded corners, item
/// name, SKU (text-selectable for pointer users), and price.
/// Hover-highlighted for pointer devices per CLAUDE.md requirement.
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
                            // CLAUDE.md: .textSelection(.enabled) on IDs/SKUs
                            .textSelection(.enabled)
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
        // CLAUDE.md: .hoverEffect(.lift) on catalog tiles
        .hoverEffect(.lift)
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

#Preview("Catalog Grid — iPad with filter chips") {
    @Previewable @State var chips: [CatalogFilterChip] = [
        CatalogFilterChip(id: "all", label: "Matches · 4", isActive: true),
        CatalogFilterChip(id: "screens", label: "Screens"),
        CatalogFilterChip(id: "batteries", label: "Batteries"),
        CatalogFilterChip(id: "labor", label: "Labor"),
        CatalogFilterChip(id: "accessories", label: "Accessories"),
        CatalogFilterChip(id: "services", label: "Services"),
        CatalogFilterChip(id: "warranty", label: "Warranty applied"),
    ]
    let items = (1...12).map { i in
        makePreviewItem(id: i, name: "Product \(i)", sku: "SKU-\(1000 + i)", price: Double(99 + i * 111) / 100)
    }
    PosCatalogGrid(
        items: items,
        filterChips: chips,
        onFilterChipTap: { tapped in
            chips = chips.map { chip in
                CatalogFilterChip(id: chip.id, label: chip.label, isActive: chip.id == tapped.id)
            }
        },
        onPick: { _ in }
    )
    .background(Color.bizarreSurface2)
    .preferredColorScheme(.dark)
    .previewInterfaceOrientation(.landscapeLeft)
}
#endif
