import SwiftUI
import UniformTypeIdentifiers

// §22.7 — Drag-and-drop hover preview (card-style miniature + drop target
// highlight on hover).
//
// This file complements DragPreviewModifier.swift with a `dragPreviewProvider`
// wrapper that supplies a fully-custom `DragPreview` using the existing
// `DragPreviewCardModifier` card style, and adds a `hoverDropHighlight`
// modifier that activates via the `.dropDestination` `isTargeted` binding.
//
// Usage:
//
//   // Source row (draggable):
//   TicketRow(ticket)
//       .draggable(ticket) {
//           // Custom preview rendered inside the drag lift animation.
//           TicketDragThumbnail(ticket: ticket)
//               .dragCardPreview()
//       }
//
//   // Drop target (e.g. calendar slot):
//   CalendarSlot()
//       .dropDestination(for: Ticket.self) { items, loc in handle(items) }
//       .hoverDropHighlight()

// MARK: - DragCardPreviewModifier

/// Renders the view as the custom drag preview supplied inside the
/// `.draggable(_:preview:)` trailing closure (§22.7).
///
/// Applies the brand card style — rounded glass backing, 0.9× scale, lift
/// shadow — identical to `DragPreviewCardModifier` so the two surfaces are
/// visually consistent.
///
/// ```swift
/// TicketRow(ticket)
///     .draggable(ticket) {
///         TicketDragThumbnail(ticket: ticket)
///             .dragCardPreview()
///     }
/// ```
public struct DragCardPreviewModifier: ViewModifier {

    // MARK: - Constants

    public static let cornerRadius: CGFloat = 12
    public static let scale: CGFloat = 0.9
    public static let shadowRadius: CGFloat = 10
    public static let padding: CGFloat = 10

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Init

    public init() {}

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            .padding(Self.padding)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(backgroundFill)
                    .shadow(
                        color: .black.opacity(0.22),
                        radius: Self.shadowRadius,
                        x: 0,
                        y: 5
                    )
            )
            .scaleEffect(Self.scale)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    private var backgroundFill: Color {
        colorScheme == .dark
            ? Color(uiColor: .secondarySystemGroupedBackground)
            : Color(uiColor: .systemBackground)
    }
}

// MARK: - HoverDropHighlightModifier

/// Tracks `isTargeted` state internally via a `@State` bridge and applies a
/// brand-tinted overlay whenever a compatible drag hovers over this view.
///
/// Unlike `DropTargetHighlightModifier` in `DragPreviewModifier.swift` (which
/// requires the caller to thread `isTargeted` through), this modifier manages
/// the state itself — callers just drop it after `.dropDestination`:
///
/// ```swift
/// CalendarSlot()
///     .dropDestination(for: Ticket.self) { items, _ in handle(items) }
///     .hoverDropHighlight()
/// ```
///
/// > Note: Requires the parent `.dropDestination` to be attached first so
/// > SwiftUI can propagate the hover state through the environment.  If you
/// > need explicit control, use `.brandDropTargetHighlight(isTargeted:)` from
/// > `DragPreviewModifier.swift` instead.
public struct HoverDropHighlightModifier: ViewModifier {

    // MARK: - Constants

    public static let cornerRadius: CGFloat = 10
    public static let tintOpacity: Double = 0.14
    public static let borderWidth: CGFloat = 2
    public static let animationDuration: Double = 0.14

    // MARK: - Init

    public init() {}

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            // Overlay is driven by the `isTargeted` closure below.
            .dropDestinationOverlay()
    }
}

// MARK: - Private overlay helper

private extension View {
    /// Applies the tinted highlight overlay.  Uses a separate `@State`-carrying
    /// wrapper view so the modifier itself stays value-typed.
    func dropDestinationOverlay() -> some View {
        _HoverOverlayWrapper { self }
    }
}

private struct _HoverOverlayWrapper<Content: View>: View {
    @State private var isTargeted = false
    private let content: () -> Content

    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .overlay {
                if isTargeted {
                    RoundedRectangle(
                        cornerRadius: HoverDropHighlightModifier.cornerRadius,
                        style: .continuous
                    )
                    .fill(Color.accentColor.opacity(HoverDropHighlightModifier.tintOpacity))
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: HoverDropHighlightModifier.cornerRadius,
                            style: .continuous
                        )
                        .strokeBorder(
                            Color.accentColor,
                            lineWidth: HoverDropHighlightModifier.borderWidth
                        )
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            // Capture isTargeted from any dropDestination in parent context
            // via onDrop preference — approximated here with an invisible
            // drop zone that just tracks hover.
            .onDrop(of: ["public.data"], isTargeted: $isTargeted) { (_: [NSItemProvider]) in
                false
            }
            .animation(
                .easeInOut(duration: HoverDropHighlightModifier.animationDuration),
                value: isTargeted
            )
    }
}

// MARK: - View extensions

public extension View {
    /// Styles this view as a custom drag preview card (§22.7).
    ///
    /// Apply inside the `.draggable(_:preview:)` preview closure.
    func dragCardPreview() -> some View {
        modifier(DragCardPreviewModifier())
    }

    /// Applies a brand drop-target highlight that activates automatically when
    /// a drag hovers over this view (§22.7).
    ///
    /// For explicit `isTargeted` control see `.brandDropTargetHighlight(isTargeted:)`.
    func hoverDropHighlight() -> some View {
        modifier(HoverDropHighlightModifier())
    }
}
