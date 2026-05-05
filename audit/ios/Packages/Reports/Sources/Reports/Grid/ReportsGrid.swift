import SwiftUI
import DesignSystem

// MARK: - ReportsGrid  (§91.16 items 3 + elevation-audit)
//
// Shared container that wraps all card-grid layouts so column counts, row heights,
// and horizontal padding stay consistent across iPhone and iPad regardless of which
// caller assembles the cards.
//
// iPhone:  1 column, cards in a plain VStack.
// iPad 9-inch / split-view:  2 columns.
// iPad 12-inch full screen (width ≥ 900 pt): 3 columns.
//
// Row-alignment audit (§91.16):
//  • LazyVGrid uses `.flexible()` items so all cells in a row get equal width.
//  • `alignment: .top` on each GridItem pins cards to the row top edge — prevents
//    a short card floating to the vertical midpoint of a taller neighbour.
//  • `cardMinHeight` enforces a floor so the shortest card never looks like a stub.

public struct ReportsGrid<Content: View>: View {

    // Minimum height applied to every grid row.
    private static var cardMinHeight: CGFloat { 160 }

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geo in
            let columns = columnCount(for: geo.size.width)
            if columns == 1 {
                // iPhone: single column; VStack expands cards to full width.
                VStack(spacing: BrandSpacing.md) {
                    content
                }
                .padding(.horizontal, BrandSpacing.base)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(
                            .flexible(),
                            spacing: BrandSpacing.md,
                            // Top-align so short cards don't float to midpoint of a taller row.
                            alignment: .top
                        ),
                        count: columns
                    ),
                    alignment: .leading,
                    spacing: BrandSpacing.md
                ) {
                    content
                }
                .padding(.horizontal, BrandSpacing.base)
            }
        }
        // Let the geometry reader shrink to its content height.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Column count

    private func columnCount(for width: CGFloat) -> Int {
        switch width {
        case ..<600:  return 1   // iPhone portrait + compact
        case ..<900:  return 2   // iPad 9-inch, split view
        default:      return 3   // iPad 12-inch, full screen
        }
    }
}

// MARK: - ReportsCard

/// Container applied to every individual report card to enforce uniform
/// minimum height, corner radius, background, and stroke border.
///
/// Surface elevation (§91.16 audit):
///   `DesignTokens.SemanticColor.cardSurface` → Surface1 asset (one step above
///   page background). Cards must NOT use `bizarreSurface2` or inline hex for
///   their outermost background. Inner skeleton/chip fills inside a card use
///   `DesignTokens.SemanticColor.surfaceRaised` (Surface2) so they sit one rung
///   above the card surface itself.
public struct ReportsCard<Content: View>: View {

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(minHeight: 160, alignment: .top)
            .padding(BrandSpacing.base)
            .background(
                DesignTokens.SemanticColor.cardSurface,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
    }
}
