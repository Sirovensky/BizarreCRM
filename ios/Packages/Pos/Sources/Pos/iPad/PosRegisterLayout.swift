#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosRegisterLayout

/// Full-screen landscape POS register layout for iPad.
///
/// Mockup grid (iPad screen 2 — no inspector):
///   rail(64) | items(flex) | cart(420)
///
/// Mockup grid (iPad screen 3 — inspector active):
///   rail(64) | items(flex, blurred) | cart(420, dimmed) | inspector(360)
///
/// The inspector is NOT a sheet — it slides in as a 4th column from the
/// right edge while the catalog and cart stay visible (per CLAUDE.md and
/// mockup caption: "cart + items stay visible"). This is the primary
/// iPad-vs-iPhone difference: iPhone uses a bottom sheet, iPad uses a
/// persistent side pane.
///
/// Column widths:
///   - Rail:       64 pt (icon-only sidebar, glass-backed)
///   - Cart:       420 pt (fixed)
///   - Inspector:  360 pt (slides in when active)
///   - Items:      remaining width (flex)
///
/// The top bar spans all columns (topbar area in grid-template-areas).
public struct PosRegisterLayout<
    Topbar: View,
    Catalog: View,
    Cart: View,
    Inspector: View
>: View {

    // MARK: - Configuration

    /// Fraction of the non-rail, non-cart width used for the catalog.
    private let catalogFraction: Double

    /// Fixed width of the cart column in points.
    private let cartWidth: CGFloat

    /// Fixed width of the inspector pane in points.
    private let inspectorWidth: CGFloat

    /// When true, the inspector column is visible and the catalog + cart dim.
    let inspectorActive: Bool

    @ViewBuilder private let topbar: () -> Topbar
    @ViewBuilder private let catalog: () -> Catalog
    @ViewBuilder private let cart: () -> Cart
    @ViewBuilder private let inspector: () -> Inspector

    // MARK: - Init

    public init(
        catalogFraction: Double = 0.70,
        cartWidth: CGFloat = 420,
        inspectorWidth: CGFloat = 360,
        inspectorActive: Bool = false,
        @ViewBuilder topbar: @escaping () -> Topbar,
        @ViewBuilder catalog: @escaping () -> Catalog,
        @ViewBuilder cart: @escaping () -> Cart,
        @ViewBuilder inspector: @escaping () -> Inspector
    ) {
        self.catalogFraction = catalogFraction.clamped(to: 0.40...0.85)
        self.cartWidth = cartWidth
        self.inspectorWidth = inspectorWidth
        self.inspectorActive = inspectorActive
        self.topbar = topbar
        self.catalog = catalog
        self.cart = cart
        self.inspector = inspector
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let totalHeight = proxy.size.height
            let topbarHeight: CGFloat = 60
            let railWidth: CGFloat = 64

            // Content width excluding rail
            let contentWidth = totalWidth - railWidth
            // Cart is fixed; catalog takes whatever is left
            let effectiveCartWidth = min(cartWidth, contentWidth * 0.38)
            let catalogContentWidth = contentWidth - effectiveCartWidth
            // When inspector is active, catalog gets narrower
            let effectiveInspectorWidth = inspectorActive ? min(inspectorWidth, contentWidth * 0.32) : 0

            ZStack(alignment: .topLeading) {
                Color.bizarreSurfaceBase.ignoresSafeArea()

                // ─── Rail (leftmost column, full height)
                railColumn
                    .frame(width: railWidth, height: totalHeight)
                    .position(x: railWidth / 2, y: totalHeight / 2)

                // ─── Topbar (spans across catalog + cart + inspector)
                topbar()
                    .frame(width: contentWidth, height: topbarHeight)
                    .position(x: railWidth + contentWidth / 2, y: topbarHeight / 2)
                    .zIndex(10)

                // ─── Catalog area (below topbar)
                let catalogX = railWidth + catalogContentWidth / 2
                let catalogY = topbarHeight + (totalHeight - topbarHeight) / 2
                let catalogH = totalHeight - topbarHeight

                catalog()
                    .frame(width: catalogContentWidth, height: catalogH)
                    .position(x: catalogX, y: catalogY)
                    // Dim + blur when inspector is active (mockup opacity: 0.42)
                    .opacity(inspectorActive ? 0.42 : 1)
                    .blur(radius: inspectorActive ? 8 : 0)
                    .saturation(inspectorActive ? 0.75 : 1)
                    .allowsHitTesting(!inspectorActive)
                    .animation(BrandMotion.snappy, value: inspectorActive)

                // Glass divider between catalog and cart
                divider
                    .frame(width: 1, height: catalogH)
                    .position(x: railWidth + catalogContentWidth, y: catalogY)

                // ─── Cart column
                let cartX = railWidth + catalogContentWidth + 1 + effectiveCartWidth / 2
                let cartY = topbarHeight + (totalHeight - topbarHeight) / 2
                let cartH = totalHeight - topbarHeight

                cartColumn
                    .frame(width: effectiveCartWidth, height: cartH)
                    .position(x: cartX, y: cartY)
                    // Dim slightly when inspector is active (mockup opacity: 0.65)
                    .opacity(inspectorActive ? 0.65 : 1)
                    .blur(radius: inspectorActive ? 3 : 0)
                    .saturation(inspectorActive ? 0.8 : 1)
                    .allowsHitTesting(!inspectorActive)
                    .animation(BrandMotion.snappy, value: inspectorActive)

                // ─── Inspector pane (slides in from right)
                if inspectorActive {
                    let inspX = railWidth + catalogContentWidth + 1 + effectiveCartWidth + effectiveInspectorWidth / 2
                    let inspY = topbarHeight + (totalHeight - topbarHeight) / 2
                    let inspH = totalHeight - topbarHeight

                    // Glass divider between cart and inspector
                    divider
                        .frame(width: 1, height: inspH)
                        .position(x: railWidth + catalogContentWidth + 1 + effectiveCartWidth, y: inspY)
                        .transition(.opacity)

                    inspectorColumn
                        .frame(width: effectiveInspectorWidth, height: inspH)
                        .position(x: inspX, y: inspY)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal:   .move(edge: .trailing).combined(with: .opacity)
                            )
                        )
                }
            }
            .animation(BrandMotion.snappy, value: inspectorActive)
        }
        .ignoresSafeArea(edges: .horizontal)
    }

    // MARK: - Rail

    private var railColumn: some View {
        ZStack {
            Color.bizarreSurface1.opacity(0.55)
                .background(.ultraThinMaterial)
            Rectangle()
                .fill(Color.bizarreOutline.opacity(0.35))
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("pos.ipad.rail")
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
                    .foregroundStyle(Color(hex: 0x2B1400))
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0xFFF7E0), Color(hex: 0xFDEED0)],
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

#Preview("POS Register Layout — no inspector") {
    PosRegisterLayout(
        topbar: {
            Color.bizarreSurface1
                .overlay(Text("Topbar").font(.brandTitleLarge()))
        },
        catalog: {
            Color.bizarreSurface2
                .overlay(Text("Catalog").font(.brandTitleLarge()))
        },
        cart: {
            Color.bizarreSurface1
                .overlay(Text("Cart").font(.brandTitleLarge()))
        }
    )
    .preferredColorScheme(.dark)
    .previewInterfaceOrientation(.landscapeLeft)
}

#Preview("POS Register Layout — inspector active") {
    let item = CartItem(name: "USB-C 3 ft cable", sku: "USB-C3", unitPrice: Decimal(string: "14.00")!)
    PosRegisterLayout(
        inspectorActive: true,
        topbar: {
            Color.bizarreSurface1.overlay(Text("Topbar").font(.brandTitleLarge()))
        },
        catalog: {
            Color.bizarreSurface2.overlay(Text("Catalog").font(.brandTitleLarge()))
        },
        cart: {
            Color.bizarreSurface1.overlay(Text("Cart").font(.brandTitleLarge()))
        },
        inspector: {
            PosIPadInspectorPane(
                item: item,
                onClose: {},
                onSave: { _, _, _ in },
                onRemove: {}
            )
        }
    )
    .preferredColorScheme(.dark)
    .previewInterfaceOrientation(.landscapeLeft)
}
#endif
