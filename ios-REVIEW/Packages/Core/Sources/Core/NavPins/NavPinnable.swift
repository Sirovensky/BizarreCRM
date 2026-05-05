import SwiftUI

// §1.5 Pin-from-overflow drag — NavPinnable
//
// Protocol + View extension helpers that wire `.draggable` and
// `.dropDestination` for NavPinItem onto any SwiftUI View.
//
// Usage (More menu row):
//   Text(item.title)
//       .navPinDraggable(item)
//
// Usage (primary nav drop zone):
//   sidebar
//       .navPinDropDestination { dropped in store.pin(dropped) }

// MARK: - Protocol

/// Conformers can be represented as a `NavPinItem` for drag-and-drop pinning.
public protocol NavPinnable {
    var navPinItem: NavPinItem { get }
}

// MARK: - View modifiers

/// Makes a view draggable as a `NavPinItem`.
@available(iOS 16.0, *)
public struct NavPinDraggableModifier: ViewModifier {
    let item: NavPinItem

    public func body(content: Content) -> some View {
        content
            .draggable(item) {
                // Drag preview: compact label
                Label(item.title, systemImage: item.systemImage)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
    }
}

/// Makes a view a drop target for `NavPinItem`.
@available(iOS 16.0, *)
public struct NavPinDropDestinationModifier: ViewModifier {
    let onDrop: (NavPinItem) -> Void
    @State private var isTargeted: Bool = false

    public func body(content: Content) -> some View {
        content
            .dropDestination(for: NavPinItem.self) { items, _ in
                guard let first = items.first else { return false }
                onDrop(first)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.tint, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - View extension

@available(iOS 16.0, *)
extension View {
    /// Attach drag capability for pinning this item to the primary nav.
    public func navPinDraggable(_ item: NavPinItem) -> some View {
        modifier(NavPinDraggableModifier(item: item))
    }

    /// Attach drop-destination capability to accept a pinned `NavPinItem`.
    /// `onDrop` fires on the main actor with the received item.
    public func navPinDropDestination(onDrop: @escaping @MainActor (NavPinItem) -> Void) -> some View {
        modifier(NavPinDropDestinationModifier(onDrop: onDrop))
    }
}
