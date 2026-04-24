#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// Full-screen landscape POS register layout for iPad.
///
/// The screen is split into two regions:
///   - **Left 70 %** — catalog panel (search + item grid)
///   - **Right 30 %** — cart column (running total + tender picker)
///
/// The split respects a minimum width on the cart side so the totals footer
/// always fits without wrapping. A glass divider drawn on the leading edge of
/// the cart column reinforces the visual separation.
///
/// Gate: only presented when `!Platform.isCompact`. `PosView` is responsible
/// for the routing decision — this layout just declares the geometry.
public struct PosRegisterLayout<Catalog: View, Cart: View>: View {

    // MARK: - Configuration

    /// Fraction of total width given to the catalog column (default 0.70).
    private let catalogFraction: Double

    /// Minimum absolute width for the cart panel in points.
    private let cartMinWidth: CGFloat

    @ViewBuilder private let catalog: () -> Catalog
    @ViewBuilder private let cart: () -> Cart

    // MARK: - Init

    public init(
        catalogFraction: Double = 0.70,
        cartMinWidth: CGFloat = 280,
        @ViewBuilder catalog: @escaping () -> Catalog,
        @ViewBuilder cart: @escaping () -> Cart
    ) {
        self.catalogFraction = catalogFraction.clamped(to: 0.50...0.85)
        self.cartMinWidth = cartMinWidth
        self.catalog = catalog
        self.cart = cart
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let cartWidth = max(cartMinWidth, totalWidth * (1 - catalogFraction))
            let catalogWidth = totalWidth - cartWidth

            HStack(spacing: 0) {
                // Catalog — left panel
                catalog()
                    .frame(width: catalogWidth)
                    .clipped()

                // Glass divider
                divider

                // Cart — right panel (glass-backed chrome)
                cartColumn
                    .frame(width: cartWidth - 1) // subtract divider hairline
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .ignoresSafeArea(edges: .horizontal)
    }

    // MARK: - Subviews

    private var divider: some View {
        Rectangle()
            .fill(Color.bizarreOutline.opacity(0.35))
            .frame(width: 1)
    }

    private var cartColumn: some View {
        ZStack {
            // Liquid Glass chrome on the cart column per CLAUDE.md requirement.
            Color.bizarreSurface1.opacity(0.60)
                .ignoresSafeArea()
                .brandGlass(.regular, in: Rectangle())

            cart()
        }
        .accessibilityIdentifier("pos.ipad.cartColumn")
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Preview

#Preview("POS Register Layout") {
    PosRegisterLayout {
        Color.bizarreSurface2
            .overlay(Text("Catalog").font(.brandTitleLarge()))
    } cart: {
        Color.bizarreSurface1
            .overlay(Text("Cart").font(.brandTitleLarge()))
    }
    .preferredColorScheme(.dark)
    .previewInterfaceOrientation(.landscapeLeft)
}
#endif
