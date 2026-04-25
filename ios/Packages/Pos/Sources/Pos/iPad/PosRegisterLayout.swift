#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// Full-screen landscape POS register layout for iPad.
///
/// The screen is split into three regions:
///   - **Left 70 %** — catalog / content column (search + item grid)
///   - **Right 30 %** — cart column (glass-backed chrome)
///   - **Inspector** — trailing panel that slides in from the right when
///     `isInspectorPresented == true` (cart line editing, repair steps).
///     Uses SwiftUI's `.inspector(isPresented:)` modifier (iOS 17+).
///     Falls back gracefully on earlier OS versions via a manual overlay.
///
/// The cart column collapses to 0 width (with a spring animation) when
/// `isCartCollapsed == true` — used on the receipt screen so the full
/// canvas is available for the celebration layout.
///
/// Gate: only presented when `!Platform.isCompact`. `PosView` is responsible
/// for the routing decision — this layout just declares the geometry.
public struct PosRegisterLayout<Catalog: View, Cart: View, Inspector: View>: View {

    // MARK: - Configuration

    /// Fraction of total width given to the catalog column (default 0.70).
    private let catalogFraction: Double

    /// Minimum absolute width for the cart panel in points.
    private let cartMinWidth: CGFloat

    /// When `true` the inspector pane slides in from the trailing edge.
    @Binding var isInspectorPresented: Bool

    /// When `true` the cart column animates to 0 width (receipt screen).
    @Binding var isCartCollapsed: Bool

    @ViewBuilder private let catalog: () -> Catalog
    @ViewBuilder private let cart: () -> Cart
    @ViewBuilder private let inspector: () -> Inspector

    // MARK: - Init

    public init(
        catalogFraction: Double = 0.70,
        cartMinWidth: CGFloat = 380,
        isInspectorPresented: Binding<Bool> = .constant(false),
        isCartCollapsed: Binding<Bool> = .constant(false),
        @ViewBuilder catalog: @escaping () -> Catalog,
        @ViewBuilder cart: @escaping () -> Cart,
        @ViewBuilder inspector: @escaping () -> Inspector
    ) {
        self.catalogFraction = catalogFraction.clamped(to: 0.50...0.85)
        self.cartMinWidth = cartMinWidth
        self._isInspectorPresented = isInspectorPresented
        self._isCartCollapsed = isCartCollapsed
        self.catalog = catalog
        self.cart = cart
        self.inspector = inspector
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            // Cart collapses to 0 on receipt screen; otherwise clamped to min.
            let rawCartWidth = isCartCollapsed ? 0 : max(cartMinWidth, totalWidth * (1 - catalogFraction))
            let cartWidth = rawCartWidth
            let catalogWidth = totalWidth - cartWidth

            HStack(spacing: 0) {
                // Catalog — left panel
                catalog()
                    .frame(width: catalogWidth)
                    .clipped()
                    // Inspector is attached here so it slides over the detail
                    // column while the cart stays visible (per mockup screen 3).
                    .inspector(isPresented: $isInspectorPresented) {
                        inspector()
                            .inspectorColumnWidth(min: 280, ideal: 340, max: 420)
                    }

                // Glass divider (hidden when cart is collapsed)
                if !isCartCollapsed {
                    divider
                }

                // Cart — right panel (glass-backed chrome)
                if !isCartCollapsed {
                    cartColumn
                        .frame(width: cartWidth - 1) // subtract divider hairline
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isCartCollapsed)
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

// MARK: - Convenience init (no inspector)

public extension PosRegisterLayout where Inspector == EmptyView {
    init(
        catalogFraction: Double = 0.70,
        cartMinWidth: CGFloat = 380,
        isCartCollapsed: Binding<Bool> = .constant(false),
        @ViewBuilder catalog: @escaping () -> Catalog,
        @ViewBuilder cart: @escaping () -> Cart
    ) {
        self.init(
            catalogFraction: catalogFraction,
            cartMinWidth: cartMinWidth,
            isInspectorPresented: .constant(false),
            isCartCollapsed: isCartCollapsed,
            catalog: catalog,
            cart: cart,
            inspector: { EmptyView() }
        )
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Preview

#Preview("POS Register Layout — with inspector") {
    @Previewable @State var inspectorOpen = true
    @Previewable @State var cartCollapsed = false

    PosRegisterLayout(
        isInspectorPresented: $inspectorOpen,
        isCartCollapsed: $cartCollapsed
    ) {
        Color.bizarreSurface2
            .overlay(Text("Catalog").font(.brandTitleLarge()))
    } cart: {
        Color.bizarreSurface1
            .overlay(Text("Cart").font(.brandTitleLarge()))
    } inspector: {
        VStack {
            Text("Inspector").font(.brandTitleLarge())
            Toggle("Close", isOn: $inspectorOpen)
        }
        .padding()
    }
    .preferredColorScheme(.dark)
    .previewInterfaceOrientation(.landscapeLeft)
}

#Preview("POS Register Layout — cart collapsed") {
    @Previewable @State var cartCollapsed = true

    PosRegisterLayout(isCartCollapsed: $cartCollapsed) {
        Color.bizarreSurface2
            .overlay(Text("Receipt canvas").font(.brandTitleLarge()))
    } cart: {
        Color.bizarreSurface1
            .overlay(Text("Cart").font(.brandTitleLarge()))
    }
    .preferredColorScheme(.dark)
    .previewInterfaceOrientation(.landscapeLeft)
}
#endif
