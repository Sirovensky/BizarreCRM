#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosIPadCartPanel

/// Persistent right-column cart panel for the iPad POS register layout.
///
/// Mockup spec (iPad screen 2):
///   - Customer header — avatar + name + phone + line-count chip
///   - Scrollable list of cart rows (tap → inspector)
///   - Coupon field pinned at the bottom of the cart body
///   - Totals block (Subtotal / Discount / Tax / Total)
///   - Charge CTA (full-width, cream, keyboard shortcut ⌘P)
///
/// When an item is selected for the inspector (`editingItemId != nil`),
/// the Charge button is replaced with "Save edit first" (disabled).
public struct PosIPadCartPanel: View {

    // MARK: - Inputs

    @Bindable var cart: Cart

    /// Called when the cashier taps Charge / Complete.
    let onCharge: () -> Void

    /// Called when a cart row is tapped (opens inspector).
    var onEditItem: ((CartItem) -> Void)?

    /// The item currently being inspected — highlights that row.
    var editingItemId: UUID?

    /// Called when the cashier wants to open the coupon sheet.
    var onShowCoupon: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Customer header
            if let customer = cart.customer {
                cartCustomerHeader(customer: customer)
                Divider().background(.bizarreOutline)
            }

            // Scrollable cart rows + coupon field
            ScrollView {
                VStack(spacing: 0) {
                    if cart.isEmpty {
                        emptyCartMessage
                    } else {
                        ForEach(cart.items) { item in
                            iPadCartRow(item: item)
                            Divider().background(.bizarreOutline.opacity(0.5))
                        }
                    }

                    // Coupon field pinned in cart body (mockup: bottom of cart-body div)
                    couponField
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                        .padding(.bottom, 14)
                }
            }

            Divider().background(.bizarreOutline)

            // Totals
            totalsBlock
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)

            Divider().background(.bizarreOutline)

            // Charge / Save-edit-first footer
            chargeFooter
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.md)
        }
        .accessibilityIdentifier("pos.ipad.cartPanel")
    }

    // MARK: - Customer header

    private func cartCustomerHeader(customer: PosCustomer) -> some View {
        HStack(spacing: BrandSpacing.md) {
            // 42pt teal avatar with strokeBorder ring (mockup: box-shadow 0 0 0 1px rgba(255,255,255,0.12))
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x4DB8C9), Color(hex: 0x2F6F78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.bizarreOnSurface.opacity(0.12), lineWidth: 1)
                    )
                Text(customer.initials)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x002D35))
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(customer.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let sub = customerSubtitle(customer) {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BrandSpacing.xs)

            // Line count chip (primary / cream)
            if cart.lineCount > 0 {
                Text("\(cart.lineCount) \(cart.lineCount == 1 ? "line" : "lines")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x2B1400))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: 0xFDEED0), in: Capsule())
                    .accessibilityLabel("\(cart.lineCount) cart lines")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func customerSubtitle(_ customer: PosCustomer) -> String? {
        if customer.isWalkIn { return "Walk-in" }
        if let p = customer.phone, !p.isEmpty { return p }
        if let e = customer.email, !e.isEmpty { return e }
        return nil
    }

    // MARK: - Cart row (iPad)

    private func iPadCartRow(item: CartItem) -> some View {
        let isEditing = item.id == editingItemId
        return Button {
            BrandHaptics.tap()
            onEditItem?(item)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // Icon (mockup: bg rgba(255,255,255,0.04) + border rgba(255,255,255,0.08), 38pt)
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.bizarreOnSurface.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.bizarreOnSurface.opacity(0.08), lineWidth: 1)
                        )
                    Image(systemName: item.inventoryItemId == nil ? "pencil" : "shippingbox.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let sku = item.sku, !sku.isEmpty {
                            Text(sku)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        Text("· Qty \(item.quantity)")
                            .font(.system(size: 11))
                            .foregroundStyle(isEditing ? .bizarreOrange : .bizarreOnSurfaceMuted)
                        if isEditing {
                            Text("editing ›")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.bizarreOrange)
                        }
                    }
                }

                Spacer(minLength: BrandSpacing.xs)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(CartMath.formatCents(CartMath.toCents(item.unitPrice * Decimal(item.quantity))))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.bizarreOrange)
                        .monospacedDigit()
                    if item.discountCents > 0 {
                        let orig = CartMath.toCents(item.unitPrice * Decimal(item.quantity)) + item.discountCents
                        Text(CartMath.formatCents(orig))
                            .font(.system(size: 11))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .strikethrough()
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(isEditing ? Color.bizarreOrange.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("\(item.name), qty \(item.quantity)" + (isEditing ? ", being edited" : "") + ". Tap to inspect.")
        .accessibilityIdentifier("pos.ipad.cartRow.\(item.id)")
    }

    // MARK: - Coupon field

    private var couponField: some View {
        Button {
            BrandHaptics.tap()
            onShowCoupon?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "tag")
                    .font(.system(size: 13))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Coupon code")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text("APPLY")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.bizarreTeal)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.bizarreSurface2.opacity(colorScheme == .dark ? 0.04 : 0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.bizarreOutline.opacity(colorScheme == .dark ? 0.08 : 0.10), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Enter or scan coupon code")
        .accessibilityIdentifier("pos.ipad.couponField")
    }

    // MARK: - Empty cart message

    private var emptyCartMessage: some View {
        Text("Cart is empty")
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .frame(maxWidth: .infinity)
            .padding(.top, BrandSpacing.lg)
    }

    // MARK: - Totals block

    private var totalsBlock: some View {
        VStack(spacing: BrandSpacing.sm) {
            totalsRow(label: "Subtotal", cents: cart.subtotalCents)

            if cart.effectiveDiscountCents > 0 {
                let label = cart.cartDiscountPercent
                    .map { "\(Int($0 * 100))% discount" } ?? "Discount"
                totalsRow(label: label, cents: -cart.effectiveDiscountCents, color: Color(hex: 0x34C47E))
            }

            if cart.couponDiscountCents > 0 {
                totalsRow(label: "Coupon", cents: -cart.couponDiscountCents, color: Color(hex: 0x34C47E))
            }

            if cart.pricingSavingCents > 0 {
                totalsRow(label: "Promo savings", cents: -cart.pricingSavingCents, color: .bizarreTeal)
            }

            totalsRow(label: "Tax · 8.5%", cents: cart.taxCents)

            if cart.tipCents > 0 {
                totalsRow(label: "Tip", cents: cart.tipCents)
            }

            if cart.feesCents > 0 {
                totalsRow(label: cart.feesLabel ?? "Fee", cents: cart.feesCents)
            }

            Divider().background(.bizarreOutline)

            // Total — large (mockup: .ttotal .tl uppercase muted + .ta large)
            HStack(alignment: .lastTextBaseline) {
                Text("TOTAL")
                    .font(.system(size: 13))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(CartMath.formatCents(cart.totalCents))
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }

            // Applied tenders
            ForEach(cart.appliedTenders) { tender in
                HStack {
                    Text(tender.label)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                    Spacer()
                    Text("-\(CartMath.formatCents(tender.amountCents))")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOrange)
                        .monospacedDigit()
                    Button {
                        BrandHaptics.tap()
                        cart.removeTender(id: tender.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(tender.label)")
                }
            }

            if !cart.appliedTenders.isEmpty {
                Divider().background(.bizarreOutline)
                totalsRow(label: "Remaining", cents: cart.remainingCents, emphasized: true)
            }
        }
    }

    // MARK: - Charge footer

    private var chargeFooter: some View {
        let isEditing = editingItemId != nil
        return Group {
            if isEditing {
                // Inspector open — Charge disabled (mockup: "Save edit first")
                Text("Save edit first")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.bizarreSurface2.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
                    )
                    .accessibilityIdentifier("pos.ipad.chargeDisabled")
            } else {
                Button {
                    BrandHaptics.tapMedium()
                    onCharge()
                } label: {
                    HStack(spacing: BrandSpacing.sm) {
                        Text(cart.isFullyTendered ? "Complete" : "Charge")
                            .font(.brandTitleMedium())
                        Text(CartMath.formatCents(
                            cart.appliedTenders.isEmpty ? cart.totalCents : cart.remainingCents
                        ))
                        .font(.brandTitleMedium())
                        .monospacedDigit()
                        Spacer()
                        Text("⌘ P")
                            .font(.system(size: 14))
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(.vertical, 17)
                    .padding(.horizontal, 16)
                    .foregroundStyle(Color(hex: 0x2B1400))
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0xFFF7E0), Color(hex: 0xFDEED0)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .overlay(
                        // Top specular highlight (mockup: radial-gradient ellipse at 50% 0%)
                        RadialGradient(
                            colors: [Color.bizarreOnSurface.opacity(0.42), Color.clear],
                            center: UnitPoint(x: 0.5, y: 0),
                            startRadius: 0,
                            endRadius: 60
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.bizarreOnSurface.opacity(0.30), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(cart.isEmpty)
                .keyboardShortcut("p", modifiers: .command)
                .accessibilityLabel("Charge \(CartMath.formatCents(cart.totalCents))")
                .accessibilityIdentifier("pos.ipad.chargeButton")
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func totalsRow(
        label: String,
        cents: Int,
        emphasized: Bool = false,
        color: Color? = nil
    ) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? .brandTitleMedium() : .brandBodyMedium())
                .foregroundStyle(emphasized ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
            Spacer()
            let isNegative = cents < 0
            Text(isNegative ? "− \(CartMath.formatCents(-cents))" : CartMath.formatCents(cents))
                .font(emphasized ? .brandHeadlineMedium() : .brandBodyLarge())
                .foregroundStyle(color ?? (emphasized ? .bizarreOnSurface : .bizarreOnSurfaceMuted))
                .monospacedDigit()
        }
    }
}

// MARK: - Color(hex:) helper

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

#Preview("iPad Cart Panel") {
    PreviewCartPanel()
}

private struct PreviewCartPanel: View {
    private let cart: Cart = {
        let c = Cart()
        c.add(CartItem(name: "iPhone 14 Pro Screen", sku: "IPH14P-S", unitPrice: Decimal(string: "189.00")!))
        c.add(CartItem(name: "Labor · screen replacement", unitPrice: Decimal(string: "60.00")!))
        c.add(CartItem(name: "USB-C 3 ft cable", sku: "USB-C3", unitPrice: Decimal(string: "14.00")!))
        return c
    }()

    var body: some View {
        PosIPadCartPanel(
            cart: cart,
            onCharge: {},
            onEditItem: { _ in }
        )
        .frame(width: 420)
        .background(Color.bizarreSurface1)
        .preferredColorScheme(.dark)
    }
}
#endif
