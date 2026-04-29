import SwiftUI

// §22.7 — Drag preview customization.
//
// Previews: drag preview = card-style miniature; drop target highlights on
// hover.  (ActionPlan line 3693)
//
// `brandDragPreview()` renders the receiving view inside a rounded glass card
// at 0.9× scale so the drag thumbnail feels deliberate and distinct from the
// source row.
//
// `brandDropTargetHighlight(isTargeted:)` applies a coloured overlay when a
// drag is hovering over a potential drop target, satisfying the "drop target
// highlights on hover" requirement.
//
// Usage:
//   TicketRow(ticket)
//       .draggable(ticket)
//       .brandDragPreview()
//
//   CalendarSlot()
//       .dropDestination(for: Ticket.self) { ... }
//       .brandDropTargetHighlight(isTargeted: isTargeted)

// MARK: - DragPreviewCardModifier

/// Wraps the view in a card-style drag thumbnail: rounded rectangle glass
/// background, 0.9× scale, subtle shadow.
///
/// Attach *after* `.draggable(...)` so SwiftUI uses this view as the
/// drag preview.
///
/// ```swift
/// TicketRow(ticket)
///     .draggable(ticket)
///     .brandDragPreview()
/// ```
public struct DragPreviewCardModifier: ViewModifier {

    // MARK: - Constants

    /// Corner radius of the preview card.
    public static let cornerRadius: CGFloat = 12
    /// Scale applied to the preview so it reads as a "lifted" miniature.
    public static let previewScale: CGFloat = 0.9
    /// Shadow radius for the lifted effect.
    public static let shadowRadius: CGFloat = 8

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Init

    public init() {}

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            .padding(BrandSpacing.small)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(cardFill)
                    .shadow(
                        color: .black.opacity(0.18),
                        radius: Self.shadowRadius,
                        x: 0,
                        y: 4
                    )
            )
            .scaleEffect(Self.previewScale)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    // MARK: - Helpers

    private var cardFill: some ShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(
                Color(uiColor: .secondarySystemGroupedBackground)
                    .opacity(0.96)
            )
        } else {
            return AnyShapeStyle(
                Color(uiColor: .systemBackground)
                    .opacity(0.97)
            )
        }
    }
}

// MARK: - DropTargetHighlightModifier

/// Overlays a translucent brand-tinted border and background when a dragged
/// item is hovering over this view (satisfies "drop target highlights on
/// hover", §22.7).
///
/// ```swift
/// CalendarSlot()
///     .dropDestination(for: Ticket.self) { items, _ in … }
///     .brandDropTargetHighlight(isTargeted: isTargeted)
/// ```
public struct DropTargetHighlightModifier: ViewModifier {

    // MARK: - Properties

    /// `true` while a compatible drag is hovering over this view.
    public let isTargeted: Bool

    // MARK: - Constants

    /// Corner radius for the highlight overlay.
    public static let cornerRadius: CGFloat = 10
    /// Tint opacity when targeted.
    public static let tintOpacity: Double = 0.15
    /// Border width when targeted.
    public static let borderWidth: CGFloat = 2

    // MARK: - Init

    public init(isTargeted: Bool) {
        self.isTargeted = isTargeted
    }

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(Self.tintOpacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: Self.borderWidth)
                        )
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}

// MARK: - View extensions

public extension View {
    /// Wraps the view in a card-style drag preview (§22.7).
    ///
    /// Apply after `.draggable(...)`.  Uses a rounded glass card at 0.9× scale
    /// with a subtle lift shadow.
    func brandDragPreview() -> some View {
        modifier(DragPreviewCardModifier())
    }

    /// Applies a drop-target highlight overlay when `isTargeted` is `true`.
    ///
    /// Pair with the `isTargeted` closure parameter from `.dropDestination`.
    ///
    /// - Parameter isTargeted: Whether a compatible drag is currently hovering.
    func brandDropTargetHighlight(isTargeted: Bool) -> some View {
        modifier(DropTargetHighlightModifier(isTargeted: isTargeted))
    }
}
