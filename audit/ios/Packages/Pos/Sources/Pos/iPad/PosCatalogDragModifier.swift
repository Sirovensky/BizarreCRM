#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - PosCatalogDragModifier (§16.14 Drag items from catalog to cart)

/// Makes a catalog tile draggable on iPad.
///
/// Attach to any `PosCatalogTile` (or its container) with
/// `.posCatalogDraggable(item:)`. The modifier encodes the item's id + name
/// + priceCents into a `NSItemProvider` using `UTType.posInventoryItem`.
///
/// The drop target on `PosIPadCartPanel` (or any view) uses
/// `.posCartDropTarget(onDrop:)` to accept the item and add it to the cart.
///
/// Haptic feedback:
///   - Drag begin  → `BrandHaptics.tap()`
///   - Drop accept → `BrandHaptics.success()`
///   - Drop reject → `BrandHaptics.error()`

// MARK: - Transfer item

/// Lightweight, Transferable item sent during drag from catalog → cart.
public struct PosDraggedCatalogItem: Codable, Sendable, Equatable, Transferable {

    public let inventoryItemId: Int64
    public let name: String
    public let sku: String?
    public let priceCents: Int?
    public let isMemberOnly: Bool

    public init(
        inventoryItemId: Int64,
        name: String,
        sku: String? = nil,
        priceCents: Int? = nil,
        isMemberOnly: Bool = false
    ) {
        self.inventoryItemId = inventoryItemId
        self.name = name
        self.sku = sku
        self.priceCents = priceCents
        self.isMemberOnly = isMemberOnly
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .posInventoryItem)
    }
}

// MARK: - Custom UTType

import UniformTypeIdentifiers

extension UTType {
    /// UTI for dragging a POS catalog item.
    /// Must match the string used in `Info.plist` if exported.
    public static let posInventoryItem = UTType(
        exportedAs: "com.bizarrecrm.pos.inventory-item"
    )
}

// MARK: - Draggable modifier

public struct PosCatalogDraggableModifier: ViewModifier {

    let item: PosDraggedCatalogItem

    public func body(content: Content) -> some View {
        content
            .draggable(item) {
                // Drag preview: mini glass card showing name + price
                dragPreview
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { _ in }
                    .onEnded { _ in BrandHaptics.tap() }
            )
    }

    private var dragPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
            if let cents = item.priceCents {
                Text(CartMath.formatCents(cents))
                    .font(.brandBodyMedium().monospacedDigit())
                    .foregroundStyle(.bizarreOrange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bizarreSurface1)
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .padding(4)     // extra padding so shadow isn't clipped
        .accessibilityHidden(true)
    }
}

public extension View {
    /// Make a catalog tile draggable (iPad only).
    ///
    /// On iPhone this is a no-op — the modifier compiles and runs but
    /// draggable() is effectively inactive because the layout doesn't
    /// have a drop target adjacent to the tile.
    func posCatalogDraggable(item: PosDraggedCatalogItem) -> some View {
        modifier(PosCatalogDraggableModifier(item: item))
    }

    /// Build `PosDraggedCatalogItem` from an `InventoryListItem` and attach.
    func posCatalogDraggable(_ inventoryItem: InventoryListItem) -> some View {
        let dragged = PosDraggedCatalogItem(
            inventoryItemId: inventoryItem.id,
            name: inventoryItem.displayName,
            sku: inventoryItem.sku,
            priceCents: inventoryItem.priceCents
        )
        return modifier(PosCatalogDraggableModifier(item: dragged))
    }
}

// MARK: - Drop target modifier (for cart panel)

/// Attach to the cart `List` or `ScrollView` to receive dragged catalog items.
///
/// ```swift
/// PosIPadCartPanel(...)
///     .posCartDropTarget { dragged in
///         posVM.addToCart(dragged)
///         BrandHaptics.success()
///     }
/// ```
public struct PosCartDropTargetModifier: ViewModifier {

    let onDrop: (PosDraggedCatalogItem) -> Void
    @State private var isTargeted: Bool = false

    public func body(content: Content) -> some View {
        content
            .dropDestination(for: PosDraggedCatalogItem.self) { items, _ in
                guard let item = items.first else { return false }
                BrandHaptics.success()
                onDrop(item)
                return true
            } isTargeted: { targeted in
                withAnimation(.spring(response: 0.22)) { isTargeted = targeted }
            }
            // Visual cue: highlight cart drop zone when dragging over it
            .overlay(alignment: .top) {
                if isTargeted {
                    dropTargetBanner
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                }
            }
    }

    private var dropTargetBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
            Text("Drop to add to cart")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.bizarreOrange.opacity(0.12))
                .overlay(Capsule().strokeBorder(Color.bizarreOrange.opacity(0.4), lineWidth: 1))
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }
}

public extension View {
    /// Make the cart panel a drop target for dragged catalog items.
    func posCartDropTarget(onDrop: @escaping (PosDraggedCatalogItem) -> Void) -> some View {
        modifier(PosCartDropTargetModifier(onDrop: onDrop))
    }
}

// MARK: - Cart convenience (add dragged item)

extension Cart {
    /// Add a dragged catalog item to the cart.
    ///
    /// Delegates price/name resolution to `CartItem`; the price in
    /// `PosDraggedCatalogItem` is the display price already in cents.
    @MainActor
    public func add(_ dragged: PosDraggedCatalogItem) {
        let price: Decimal
        if let cents = dragged.priceCents {
            price = Decimal(cents) / 100
        } else {
            price = 0
        }
        let item = CartItem(
            inventoryItemId: dragged.inventoryItemId,
            name: dragged.name,
            sku: dragged.sku,
            quantity: 1,
            unitPrice: price
        )
        add(item)
        AppLog.pos.info("Cart: drag-added \(dragged.name, privacy: .private)")
    }
}
#endif
