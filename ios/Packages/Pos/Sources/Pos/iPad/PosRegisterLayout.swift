#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosRegisterLayout

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

    /// Fraction of the non-rail, non-cart width used for the catalog.
    private let catalogFraction: Double

    /// Fixed width of the cart column in points.
    private let cartWidth: CGFloat

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
        // The outer iPadShell already supplies the 64pt custom rail. Drawing
        // another 64pt rail here doubled the leading inset and pushed the
        // inspector pane off-screen during the repair flow ("blurred items
        // + cart + no device picker"). Render only the catalog / cart /
        // inspector columns; the rail stays an iPadShell concern.
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            // Cart collapses to 0 on receipt screen; otherwise clamped to min.
            let rawCartWidth = isCartCollapsed ? 0 : max(cartMinWidth, totalWidth * (1 - catalogFraction))
            let cartWidth = rawCartWidth
            let catalogWidth = totalWidth - cartWidth

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
        .ignoresSafeArea(edges: .horizontal)
    }

    // MARK: - Glass divider

    private var divider: some View {
        Rectangle()
            .fill(Color.bizarreOutline.opacity(0.35))
    }

    // MARK: - Cart column (glass-backed)

    private var cartColumn: some View {
        ZStack {
            Color.bizarreSurface1.opacity(0.60)
                .ignoresSafeArea()
                .brandGlass(.regular, in: Rectangle())
            cart()
        }
        .accessibilityIdentifier("pos.ipad.cartColumn")
    }

    // MARK: - Inspector column (glass-backed, slides in)

    private var inspectorColumn: some View {
        ZStack {
            Color.bizarreSurface1
                .opacity(0.75)
            inspector()
        }
        .brandGlass(.identity, in: Rectangle())
        .accessibilityIdentifier("pos.ipad.inspectorPane")
    }
}

// MARK: - Convenience init (no inspector)

extension PosRegisterLayout where Inspector == EmptyView {
    /// Two-column init (catalog + cart). No inspector.
    public init(
        catalogFraction: Double = 0.70,
        cartWidth: CGFloat = 420,
        @ViewBuilder topbar: @escaping () -> Topbar,
        @ViewBuilder catalog: @escaping () -> Catalog,
        @ViewBuilder cart: @escaping () -> Cart
    ) {
        self.init(
            catalogFraction: catalogFraction,
            cartWidth: cartWidth,
            inspectorWidth: 360,
            inspectorActive: false,
            topbar: topbar,
            catalog: catalog,
            cart: cart,
            inspector: { EmptyView() }
        )
    }
}

// MARK: - PosIPadInspectorPane
// Right-side line-edit inspector for iPad (screen 3). NOT a sheet.
// Matches mockup: header(title + SKU + ✕) · body(qty/price/discount/note/audit) · footer(Remove / Save).

public struct PosIPadInspectorPane: View {

    // MARK: - Inputs

    let item: CartItem
    let onClose: () -> Void
    let onSave: (Int, Int, String?) -> Void
    let onRemove: () -> Void

    @State private var qty: Int
    @State private var discountText: String
    @State private var note: String
    @State private var showingDiscountField: Bool
    @State private var showingNoteField: Bool

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Init

    public init(
        item: CartItem,
        onClose: @escaping () -> Void,
        onSave: @escaping (Int, Int, String?) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.item = item
        self.onClose = onClose
        self.onSave = onSave
        self.onRemove = onRemove
        _qty = State(initialValue: item.quantity)
        let discCents = item.discountCents
        _discountText = State(initialValue: discCents > 0 ? String(format: "%.2f", Double(discCents) / 100) : "")
        _note = State(initialValue: item.notes ?? "")
        _showingDiscountField = State(initialValue: item.discountCents > 0)
        _showingNoteField = State(initialValue: !(item.notes ?? "").isEmpty)
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Header: title + SKU + close button
            inspectorHeader

            Divider().background(.bizarreOutline)

            // Scrollable body
            ScrollView {
                VStack(spacing: 0) {
                    // Qty row
                    inspectorRow {
                        Text("Qty")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        PosQuantityStepper(
                            quantity: qty,
                            onIncrement: { BrandHaptics.tap(); qty += 1 },
                            onDecrement: { BrandHaptics.tap(); if qty > 1 { qty -= 1 } }
                        )
                    }
                    Divider().background(.bizarreOutline.opacity(0.5))

                    // Unit price (display-only)
                    inspectorRow {
                        Text("Unit price")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        Text(CartMath.formatCents(CartMath.toCents(item.unitPrice)))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                    Divider().background(.bizarreOutline.opacity(0.5))

                    // Line discount
                    if showingDiscountField {
                        inspectorRow {
                            Text("Line discount")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("$")
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                TextField("0.00", text: $discountText)
                                    .keyboardType(.decimalPad)
                                    .font(.brandBodyLarge())
                                    .foregroundStyle(.bizarreOnSurface)
                                    .monospacedDigit()
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    .accessibilityIdentifier("pos.inspector.discount")
                            }
                        }
                    } else {
                        inspectorRow {
                            Text("Line discount")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            Button {
                                BrandHaptics.tap()
                                withAnimation(.spring(response: 0.22)) { showingDiscountField = true }
                            } label: {
                                Text("+ Apply")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.bizarreTeal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Divider().background(.bizarreOutline.opacity(0.5))

                    // Note row
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        if showingNoteField {
                            TextField("Add a note for the receipt…", text: $note, axis: .vertical)
                                .font(.system(size: 13))
                                .foregroundStyle(.bizarreOnSurface)
                                .lineLimit(2...4)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.bizarreSurface2.opacity(colorScheme == .dark ? 0.04 : 0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(Color.bizarreOutline.opacity(0.08), lineWidth: 1)
                                        )
                                )
                                .accessibilityIdentifier("pos.inspector.note")
                        } else {
                            Button {
                                BrandHaptics.tap()
                                withAnimation(.spring(response: 0.22)) { showingNoteField = true }
                            } label: {
                                Text("Add a note for the receipt…")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.bizarreSurface2.opacity(colorScheme == .dark ? 0.04 : 0.03))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .strokeBorder(Color.bizarreOutline.opacity(0.08), lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().background(.bizarreOutline.opacity(0.5))

                    // Audit row
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Audit")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text("No edit history.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }

            Divider().background(.bizarreOutline)

            // Footer: Remove + Save
            inspectorFooter
        }
        .accessibilityIdentifier("pos.ipad.inspectorPane")
    }

    // MARK: - Subviews

    private var inspectorHeader: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let sku = item.sku, !sku.isEmpty {
                        Text("SKU")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text(sku)
                            .font(.brandMono(size: 12))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .textSelection(.enabled)
                    }
                }
            }
            Spacer()
            Button {
                BrandHaptics.tap()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 28, height: 28)
                    .background(Color.bizarreSurface2.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close inspector")
            .accessibilityIdentifier("pos.inspector.close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func inspectorRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: BrandSpacing.sm) {
            content()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }

    private var inspectorFooter: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                BrandHaptics.tap()
                onRemove()
                onClose()
            } label: {
                Text("Remove")
                    .font(.brandTitleSmall())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.bizarreError)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.bizarreError.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.bizarreError.opacity(0.35), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pos.inspector.remove")

            Button {
                BrandHaptics.success()
                let discCents: Int = {
                    guard showingDiscountField,
                          let v = Double(discountText.trimmingCharacters(in: .whitespacesAndNewlines)),
                          v > 0 else { return 0 }
                    return Int((v * 100).rounded())
                }()
                let noteVal = note.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(qty, discCents, noteVal.isEmpty ? nil : noteVal)
                onClose()
            } label: {
                Text("Save · \(saveLabel)")
                    .font(.brandTitleSmall())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(Color.bizarreOnPrimary)
                    .background(
                        LinearGradient(
                            colors: [Color.bizarreOrange.opacity(0.92), Color.bizarreOrange],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pos.inspector.save")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var saveLabel: String {
        let discCents: Int = {
            guard showingDiscountField,
                  let v = Double(discountText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  v > 0 else { return 0 }
            return Int((v * 100).rounded())
        }()
        let subtotal = CartMath.toCents(item.unitPrice * Decimal(qty))
        return CartMath.formatCents(max(0, subtotal - discCents))
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

private extension Color {
    init(hex: Int, alpha: Double = 1) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double((hex >>  0) & 0xFF) / 255,
            opacity: alpha
        )
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
