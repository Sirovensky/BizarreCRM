import SwiftUI
import DesignSystem

// MARK: - ReportsGrid  (§91.16 item 3)
//
// Shared container that wraps all card-grid layouts so column counts, row heights,
// and horizontal padding stay consistent across iPhone and iPad regardless of which
// caller assembles the cards.
//
// iPhone:  1 column, cards in a plain VStack.
// iPad 9":  2 columns.
// iPad 12"+ (regular width ≥ 1024 pt): 3 columns.
//
// `cardMinHeight` controls the uniform minimum row height so taller cards don't cause
// visual thrash. Cards may grow taller but will never be clipped below the minimum.

public struct ReportsGrid<Content: View>: View {

    // Minimum height applied to every grid row.
    private static var cardMinHeight: CGFloat { 160 }

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    public var body: some View {
        GeometryReader { geo in
            let columns = columnCount(for: geo.size.width)
            if columns == 1 {
                // iPhone: single column; use VStack so cards expand to full width.
                VStack(spacing: BrandSpacing.md) {
                    content
                }
                .padding(.horizontal, BrandSpacing.base)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: BrandSpacing.md),
                        count: columns
                    ),
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
public struct ReportsCard<Content: View>: View {

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(minHeight: 160, alignment: .top)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
    }
}
