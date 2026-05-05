// DesignSystem/Tips/TipPresenterView.swift
//
// A SwiftUI container that attaches a BrandTip popover to any wrapped content.
//
// Use this when you need to pass a tip as a view-builder argument (e.g. inside
// a `List` row, a toolbar item, or a FAB), rather than calling `.brandTip()`
// directly on the host view.
//
// Two usage patterns:
//
//   1. As a wrapper view:
//      ```swift
//      TipPresenterView(tip: TipsCatalog.firstTicket) {
//          CreateTicketButton()
//      }
//      ```
//
//   2. Via the `.tipPresenter(tip:arrowEdge:)` convenience modifier:
//      ```swift
//      CreateTicketButton()
//          .tipPresenter(tip: TipsCatalog.firstTicket)
//      ```
//
// §69 In-App Help / Tips

import SwiftUI
#if canImport(TipKit)
import TipKit

// MARK: - TipPresenterView

/// A transparent SwiftUI container that anchors a `BrandTip` popover to
/// its wrapped content using TipKit's `.popoverTip` modifier.
///
/// On iOS < 17 the view renders as a plain pass-through with no tip visible.
@available(iOS 17, *)
public struct TipPresenterView<TipType: BrandTip, Content: View>: View {
    private let tip: TipType
    private let arrowEdge: Edge
    private let content: () -> Content

    /// Creates a presenter that wraps `content` and attaches `tip` as a popover.
    ///
    /// - Parameters:
    ///   - tip: A `BrandTip`-conforming value, typically from `TipsCatalog`.
    ///   - arrowEdge: The edge of the anchor view that the popover arrow points
    ///     from. Defaults to `.top`.
    ///   - content: The view to which the tip popover is anchored.
    public init(
        tip: TipType,
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tip = tip
        self.arrowEdge = arrowEdge
        self.content = content
    }

    public var body: some View {
        content()
            .brandTip(tip, arrowEdge: arrowEdge)
    }
}

// MARK: - View convenience modifier

public extension View {
    /// Attaches a `BrandTip` popover to this view, identical to `.brandTip(_:arrowEdge:)`
    /// but reads as "this view presents a tip" at the call site — making intent explicit.
    ///
    /// - Parameters:
    ///   - tip: A `BrandTip`-conforming value, typically from `TipsCatalog`.
    ///   - arrowEdge: Preferred popover arrow direction (default `.top`).
    @available(iOS 17, *)
    func tipPresenter(_ tip: some BrandTip, arrowEdge: Edge = .top) -> some View {
        self.brandTip(tip, arrowEdge: arrowEdge)
    }
}

// MARK: - Inline tip card (for onboarding banners)

/// A standalone card that renders a `BrandTip`'s content inline — no popover.
///
/// Use this for full-width onboarding banners (e.g. empty-state coaching marks)
/// where a popover anchor isn't available.
///
/// The card respects the user's Reduce Transparency accessibility setting.
@available(iOS 17, *)
public struct TipCardView<TipType: BrandTip>: View {
    private let tip: TipType
    private let onDismiss: (() -> Void)?

    /// Creates an inline tip card.
    ///
    /// - Parameters:
    ///   - tip: A `BrandTip`-conforming value.
    ///   - onDismiss: Optional closure called when the user taps the dismiss
    ///     button. If `nil`, no dismiss button is shown.
    public init(tip: TipType, onDismiss: (() -> Void)? = nil) {
        self.tip = tip
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            if let image = tip.image {
                image
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                tip.title
                    .font(.headline)

                if let message = tip.message {
                    message
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if let dismiss = onDismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text("Dismiss tip"))
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
    }
}
#endif // canImport(TipKit)
