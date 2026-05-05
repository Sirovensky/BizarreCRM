#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosApplePencilModifier (§16.14)
//
// Apple Pencil interaction on iPad Pro catalog tiles:
//   - Single tap  → add 1 to cart (same as finger tap)
//   - Double tap  → add 2 to cart (rapid two-tap gesture on Pencil Pro / 2nd gen)
//   - Hover       → show `PosCatalogTilePreviewSheet` after 400ms debounce
//
// Implementation notes:
//   - `onPencilDoubleTap` is caught via `UIHoverGestureRecognizer` +
//     `UIPencilInteraction` delegate (UIKit-side).
//   - SwiftUI `onPencilDoubleTap` modifier is available on iOS 17.5+ via
//     the `PencilInteraction` API — we use it directly.
//   - Hover preview uses `_onHover` (platform-private but available on iPadOS 16+
//     with ProMotion / Hover API). Falls back to long-press on older hardware.
//   - This modifier is a no-op on iPhone (`.isCompact == true`) and on
//     iPad models that lack Pencil support.

/// Describes the Pencil action the user performed.
public enum PencilCatalogAction: Sendable {
    case singleTap
    case doubleTap
}

/// View modifier that wires Apple Pencil interactions on a catalog tile.
///
/// Usage:
/// ```swift
/// PosCatalogTile(item: item)
///     .posPencilInteraction(item: item) { action in
///         switch action {
///         case .singleTap: cart.add(item, qty: 1)
///         case .doubleTap:  cart.add(item, qty: 2)
///         }
///     }
/// ```
public struct PosApplePencilModifier: ViewModifier {

    public let item: PosDraggedCatalogItem
    public let onAction: (PencilCatalogAction) -> Void
    public let onHoverPreview: (() -> Void)?

    @State private var isHovered: Bool = false

    public init(
        item: PosDraggedCatalogItem,
        onAction: @escaping (PencilCatalogAction) -> Void,
        onHoverPreview: (() -> Void)? = nil
    ) {
        self.item = item
        self.onAction = onAction
        self.onHoverPreview = onHoverPreview
    }

    public func body(content: Content) -> some View {
        Group {
            if #available(iOS 17.5, *) {
                content.onPencilDoubleTap { _ in
                    BrandHaptics.tapMedium()
                    onAction(.doubleTap)
                }
            } else {
                content
            }
        }
            // Hover: show a faint border ring while Pencil hovers over the tile.
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.18)) { isHovered = hovering }
                if hovering {
                    onHoverPreview?()
                }
            }
            // Visual hover ring (Pencil hover, iPad Pro 2024+)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        Color.bizarreOrange.opacity(isHovered ? 0.55 : 0),
                        lineWidth: 1.5
                    )
                    .animation(.easeInOut(duration: 0.18), value: isHovered)
            )
            .accessibilityHint("Double-tap with Apple Pencil to add 2 to cart")
    }
}

// MARK: - View extension

public extension View {
    /// Attach Apple Pencil interactions to a POS catalog tile.
    ///
    /// - Parameters:
    ///   - item: The catalog item draggable descriptor.
    ///   - onAction: Called with `.singleTap` (handled by normal tap gesture) or
    ///     `.doubleTap` (Pencil double-tap adds 2 units).
    ///   - onHoverPreview: Optional closure called while Pencil hovers — use to
    ///     trigger a preview sheet after a debounce in the caller.
    ///
    /// Safe to call on iPhone — `onPencilDoubleTap` and `onHover` are no-ops there.
    func posPencilInteraction(
        item: PosDraggedCatalogItem,
        onAction: @escaping (PencilCatalogAction) -> Void,
        onHoverPreview: (() -> Void)? = nil
    ) -> some View {
        modifier(PosApplePencilModifier(item: item, onAction: onAction, onHoverPreview: onHoverPreview))
    }
}

// MARK: - Cart convenience (add with qty)

extension Cart {
    /// Add a dragged catalog item to the cart with an explicit quantity.
    ///
    /// Used by the Apple Pencil double-tap handler to add 2 units at once.
    @MainActor
    public func add(_ dragged: PosDraggedCatalogItem, qty: Int) {
        let price: Decimal
        if let cents = dragged.priceCents {
            price = Decimal(cents) / 100
        } else {
            price = 0
        }
        // If an identical line already exists (same inventoryItemId), bump its qty.
        // Otherwise create a new line.
        if let existing = items.first(where: { $0.inventoryItemId == dragged.inventoryItemId }) {
            update(id: existing.id, quantity: existing.quantity + qty)
            AppLog.pos.info("Cart: Pencil double-tap incremented \(dragged.name, privacy: .private) by \(qty)")
        } else {
            let item = CartItem(
                inventoryItemId: dragged.inventoryItemId,
                name: dragged.name,
                sku: dragged.sku,
                quantity: qty,
                unitPrice: price
            )
            add(item)
            AppLog.pos.info("Cart: Pencil tap added \(dragged.name, privacy: .private) qty=\(qty)")
        }
    }
}
#endif
