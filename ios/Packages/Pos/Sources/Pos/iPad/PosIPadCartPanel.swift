#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// Pinned right-column cart panel for the iPad POS register layout.
///
/// Renders the running-total summary (subtotal / discount / tax / tip / fees /
/// total / applied tenders / remaining) at the top, a tender-picker row in the
/// middle, and the Charge CTA at the bottom — all inside the glass-backed
/// cart column produced by `PosRegisterLayout`.
///
/// **Not a replacement for `PosCartPanel`** — `PosCartPanel` is the full
/// list-of-lines view shared by both iPhone and the iPad detail column in the
/// legacy `NavigationSplitView` path. `PosIPadCartPanel` is the *condensed*
/// totals + charge side-panel used exclusively in the new full-screen
/// `PosRegisterLayout` where the catalog takes the left 70 % and this panel
/// occupies the right 30 %.
public struct PosIPadCartPanel: View {

    // MARK: - Inputs

    @Bindable var cart: Cart

    /// Called when the cashier taps Charge / Complete.
    let onCharge: () -> Void

    /// Called when the cashier wants to open a quick tender picker row.
    let onSelectTender: () -> Void

    /// Scroll to the cart list (provided by parent as a focus trigger).
    var onShowCartList: (() -> Void)?

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            cartSummaryHeader
            Divider().background(.bizarreOutline)
            // Cart line list — scrollable, fills available space
            cartLineList
            // Coupon row pinned at bottom of the list area (per mockup screen 2)
            couponRow
            Divider().background(.bizarreOutline)
            tenderPickerRow
            Divider().background(.bizarreOutline)
            totalsBlock
            Divider().background(.bizarreOutline)
            chargeFooter
        }
        .accessibilityIdentifier("pos.ipad.cartPanel")
    }

    // MARK: - Cart line list

    /// Scrollable list of cart lines. Each row has a `.hoverEffect(.highlight)`
    /// for pointer devices and a `.contextMenu` with quick actions per
    /// CLAUDE.md requirement.
    private var cartLineList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(cart.items) { item in
                    cartLineRow(item)
                    Divider()
                        .padding(.leading, BrandSpacing.md + 28 + BrandSpacing.sm)
                        .background(Color.bizarreOutline.opacity(0.3))
                }
            }
        }
    }

    @ViewBuilder
    private func cartLineRow(_ item: CartItem) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            // Icon area
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(Color.bizarreOrangeContainer.opacity(0.25))
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.bizarreOrange)
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(item.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let sku = item.sku, !sku.isEmpty {
                    Text(sku)
                        .font(.brandMono(size: 10))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                        .textSelection(.enabled)     // per CLAUDE.md SKUs are text-selectable
                }
            }

            Spacer(minLength: BrandSpacing.xxs)

            Text(CartMath.formatCents(item.lineSubtotalCents))
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(Rectangle())
        // Hover highlight for pointer/trackpad per CLAUDE.md
        .hoverEffect(.highlight)
        // Context menu with quick edit actions per CLAUDE.md
        .contextMenu {
            Button {
                BrandHaptics.tap()
                onShowCartList?()
            } label: {
                Label("Edit line", systemImage: "pencil")
            }
            Button(role: .destructive) {
                BrandHaptics.tap()
                cart.removeLine(id: item.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(CartMath.formatCents(item.lineSubtotalCents))")
        .accessibilityIdentifier("pos.ipad.cartLine.\(item.id)")
    }

    // MARK: - Coupon row

    /// Glass-card coupon entry pinned at the bottom of the cart body area
    /// (per mockup screen 2, line ~2215).
    private var couponRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "tag.fill")
                .font(.system(size: 14))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            TextField("Coupon code", text: $couponCode)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier("pos.ipad.couponField")

            if !couponCode.isEmpty {
                Button {
                    BrandHaptics.tapMedium()
                    // TODO: wire to coupon validation endpoint
                } label: {
                    Text("APPLY")
                        .font(.brandLabelLarge().weight(.bold))
                        .foregroundStyle(.bizarreTeal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apply coupon code")
                .accessibilityIdentifier("pos.ipad.applyCoupon")
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(
            Color.bizarreSurface1.opacity(0.7),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .brandGlass(.clear, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, BrandSpacing.md)
        .padding(.bottom, BrandSpacing.sm)
        .accessibilityIdentifier("pos.ipad.couponRow")
    }

    // MARK: - Coupon entry state

    /// Local coupon code state — owned by the cart panel on iPad.
    @State private var couponCode: String = ""

    // MARK: - Sections

    /// Item count chip + "View cart" link at the top.
    private var cartSummaryHeader: some View {
        HStack(spacing: BrandSpacing.sm) {
            ZStack {
                Circle().fill(Color.bizarreOrange)
                Text("\(cart.itemQuantity)")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnOrange)
                    .monospacedDigit()
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(cart.isEmpty ? "Cart empty" : "\(cart.lineCount) \(cart.lineCount == 1 ? "line" : "lines")")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                if !cart.isEmpty {
                    Text("\(cart.itemQuantity) items")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer(minLength: BrandSpacing.xs)

            if let onShowCartList, !cart.isEmpty {
                Button {
                    BrandHaptics.tap()
                    onShowCartList()
                } label: {
                    Text("View")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOrange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View cart lines")
                .accessibilityIdentifier("pos.ipad.viewCartLines")
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
    }

    /// Quick tender-type picker row. Tapping opens the full tender select sheet.
    private var tenderPickerRow: some View {
        Button {
            BrandHaptics.tap()
            onSelectTender()
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("Choose tender")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: BrandSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, BrandSpacing.md)
            .frame(minHeight: DesignTokens.Touch.minTargetSide)
        }
        .buttonStyle(.plain)
        .disabled(cart.isEmpty)
        .accessibilityIdentifier("pos.ipad.chooseTender")
    }

    /// Running totals block — mirrors `PosCartPanel.totalsFooter` but without
    /// the items list (the catalog grid occupies the left panel for that).
    private var totalsBlock: some View {
        VStack(spacing: BrandSpacing.sm) {
            totalsRow(label: "Subtotal", cents: cart.subtotalCents)

            if cart.effectiveDiscountCents > 0 {
                let label = cart.cartDiscountPercent
                    .map { "\(Int($0 * 100))% discount" } ?? "Discount"
                totalsRow(label: label, cents: -cart.effectiveDiscountCents, color: .bizarreOrange)
            }

            if cart.couponDiscountCents > 0 {
                totalsRow(label: "Coupon", cents: -cart.couponDiscountCents, color: .bizarreOrange)
            }

            if cart.pricingSavingCents > 0 {
                totalsRow(label: "Promo savings", cents: -cart.pricingSavingCents, color: .bizarreTeal)
            }

            totalsRow(label: "Tax", cents: cart.taxCents)

            if cart.tipCents > 0 {
                totalsRow(label: "Tip", cents: cart.tipCents)
            }

            if cart.feesCents > 0 {
                totalsRow(label: cart.feesLabel ?? "Fee", cents: cart.feesCents)
            }

            Divider().background(.bizarreOutline)

            totalsRow(label: "Total", cents: cart.totalCents, emphasized: true)

            // Applied tenders (gift cards / store credit)
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
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
    }

    /// Charge CTA at the very bottom.
    private var chargeFooter: some View {
        PosChargeButton(
            totalCents: cart.appliedTenders.isEmpty ? cart.totalCents : cart.remainingCents,
            isComplete: cart.isFullyTendered,
            isEnabled: !cart.isEmpty,
            action: onCharge
        )
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.md)
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
            Text(isNegative ? "-\(CartMath.formatCents(-cents))" : CartMath.formatCents(cents))
                .font(emphasized ? .brandHeadlineMedium() : .brandBodyLarge())
                .foregroundStyle(color ?? (emphasized ? .bizarreOnSurface : .bizarreOnSurface))
                .monospacedDigit()
        }
    }
}

// MARK: - Preview

#Preview("iPad Cart Panel") {
    let cart = Cart()
    cart.add(CartItem(name: "Widget A", unitPrice: Decimal(string: "29.99")!, taxRate: 0.08))
    cart.add(CartItem(name: "Widget B", unitPrice: Decimal(string: "14.50")!))

    return PosIPadCartPanel(
        cart: cart,
        onCharge: {},
        onSelectTender: {}
    )
    .frame(width: 320)
    .background(Color.bizarreSurface1)
    .preferredColorScheme(.dark)
}
#endif
