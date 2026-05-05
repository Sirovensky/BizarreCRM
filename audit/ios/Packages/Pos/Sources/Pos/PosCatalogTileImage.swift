#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - PosCatalogTileImage

/// Thumbnail image box used in `PosCatalogTile`.
///
/// Displays a 52×52-pt (iPad: 60×60-pt) image square:
/// - When `imageURL` is non-nil, loads lazily via `AsyncImage` (phase-aware).
/// - When loading or the URL is nil, falls back to the SF Symbol placeholder.
/// - Overlaps a subtle inner shadow on the loaded image so it blends with the tile card.
///
/// The view is designed to be inserted into the top-left of the tile card,
/// replacing the bare-SF-Symbol box used before §16.2.
///
/// ## Accessibility
/// The image is decorative (`accessibilityHidden(true)`) — the tile's outer
/// `accessibilityLabel` already names the product.
public struct PosCatalogTileImage: View {
    /// Remote thumbnail URL.  Nil shows the SF Symbol placeholder instantly.
    public let imageURL: URL?
    /// SF Symbol fallback name (derived from `InventoryListItem.itemType`).
    public let placeholderSymbol: String
    /// Whether to use the larger iPad size (60 pt) vs iPhone (52 pt).
    public var isPad: Bool = false

    private var size: CGFloat { isPad ? 60 : 52 }
    private var cornerRadius: CGFloat { isPad ? 10 : 9 }

    public init(imageURL: URL?, placeholderSymbol: String, isPad: Bool = false) {
        self.imageURL       = imageURL
        self.placeholderSymbol = placeholderSymbol
        self.isPad          = isPad
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.bizarreSurface2.opacity(0.55))
                .frame(width: size, height: size)

            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    case .failure:
                        symbolPlaceholder
                    case .empty:
                        shimmer
                    @unknown default:
                        symbolPlaceholder
                    }
                }
            } else {
                symbolPlaceholder
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Sub-views

    private var symbolPlaceholder: some View {
        Image(systemName: placeholderSymbol)
            .font(.system(size: isPad ? 22 : 18))
            .foregroundStyle(Color.bizarreOnSurfaceMuted.opacity(0.7))
    }

    private var shimmer: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.bizarreSurface2.opacity(0.3))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.bizarreOnSurface.opacity(0.04), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
    }
}
#endif
