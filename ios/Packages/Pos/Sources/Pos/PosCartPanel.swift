#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosCartPanel

/// Cart column — list of `CartItem` rows with swipe-to-void, tap-to-edit,
/// totals footer, coupon field, and the floating Charge CTA.
/// Shared by the iPhone compact layout (shown as a sheet) and the iPad
/// split-view trailing column.
struct PosCartPanel: View {
    @Bindable var cart: Cart
    let onCharge: () -> Void
    let onOpenDrawer: () -> Void
    /// §16.4: tap on the attached-customer chip opens this to swap / find
    /// a different customer. Optional so call sites that don't wire the
    /// picker can omit it — the chip still renders without a Change CTA.
    var onChangeCustomer: (() -> Void)?
    /// §16.4: detach the currently attached customer without clearing the
    /// cart. Backed by `cart.detachCustomer()` at the call site.
    var onRemoveCustomer: (() -> Void)?
    @Binding var editQuantityFor: CartItem?
    @Binding var editPriceFor: CartItem?
    /// §16.3: show/hide each adjustment sheet
    var onShowDiscount: (() -> Void)?
    var onShowTip: (() -> Void)?
    var onShowFees: (() -> Void)?
    /// §16.4: show/hide coupon input
    var onShowCoupon: (() -> Void)?
    /// §16.4: customer context banners (group discount, tax-exempt, loyalty).
    var customerContext: PosCustomerContext = .empty
    /// §16.4: pre-computed loyalty earn preview points; nil when inactive.
    var loyaltyEarnedPoints: Int? = nil

    @Environment(\.colorScheme) private var colorScheme

    /// Line-edit sheet state — the item currently being edited inline.
    @State private var editingLineItem: CartItem?

    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                // Compact customer strip (mockup: avatar + name + phone/meta + chip/total)
                if let customer = cart.customer {
                    PosCartStrip(
                        customer: customer,
                        cart: cart,
                        onChange: onChangeCustomer,
                        onRemove: onRemoveCustomer
                    )
                    // §16.4 — Customer context banners (tax-exempt, group discount, loyalty).
                    if customerContext != .empty {
                        PosCustomerContextBanners(
                            context: customerContext,
                            cartTotalCents: cart.totalCents,
                            earnedPoints: loyaltyEarnedPoints
                        )
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.bottom, BrandSpacing.xs)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(BrandMotion.snappy, value: customerContext)
                    }
                }
                cartContent
                totalsFooter
            }
            // §16.22 — Dimmed-background overlay when line-edit sheet is open.
            // Cart rows visible but dim to 0.35 opacity and ignore taps (per mockup).
            if editingLineItem != nil {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(BrandMotion.snappy, value: editingLineItem != nil)
                    .accessibilityHidden(true)
            }
        }
        // Line-edit bottom sheet — mockup screen 4
        .sheet(item: $editingLineItem) { item in
            PosLineEditSheet(
                item: item,
                onSave: { newQty, newDiscCents, _ in
                    // Cart.update(id:notes:) doesn't exist yet — qty + discount
                    // are the actionable edits; note is shown as UI only.
                    cart.update(id: item.id, quantity: newQty)
                    if newDiscCents != item.discountCents {
                        cart.update(id: item.id, discountCents: newDiscCents)
                    }
                },
                onRemove: {
                    cart.remove(id: item.id)
                }
            )
        }
    }

    @ViewBuilder
    private var cartContent: some View {
        if cart.isEmpty {
            emptyState
        } else {
            List {
                ForEach(cart.items) { item in
                    PosCartRow(item: item) {
                        // Tap → line-edit sheet
                        BrandHaptics.tap()
                        editingLineItem = item
                    } onIncrement: {
                        BrandHaptics.tap()
                        cart.update(id: item.id, quantity: item.quantity + 1)
                    } onDecrement: {
                        BrandHaptics.tap()
                        cart.update(id: item.id, quantity: item.quantity - 1)
                    }
                    .listRowBackground(rowBackground(for: item))
                    .listRowInsets(EdgeInsets())
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            BrandHaptics.tap()
                            cart.remove(id: item.id)
                        } label: {
                            Label("Void", systemImage: "trash")
                        }
                        .accessibilityLabel("Remove \(item.name) from cart")
                    }
                    .contextMenu {
                        Button {
                            editQuantityFor = item
                        } label: {
                            Label("Edit quantity", systemImage: "number")
                        }
                        Button {
                            editPriceFor = item
                        } label: {
                            Label("Edit price", systemImage: "dollarsign")
                        }
                        Button(role: .destructive) {
                            cart.remove(id: item.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }

                // Quick-action row: + Misc / + Discount / + Note
                // (mockup: 3 ghost buttons below the line list)
                quickActionRow
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))

                // Ticket link chip — §16.3
                HStack(spacing: BrandSpacing.sm) {
                    PosCartTicketLinkChip(cart: cart)
                    Spacer(minLength: 0)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))

                // Coupon section
                couponSection
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 14, trailing: 16))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Row highlight

    @ViewBuilder
    private func rowBackground(for item: CartItem) -> some View {
        let isLast = cart.items.last?.id == item.id
        if isLast && !cart.isEmpty {
            // Most-recently-added line gets the subtle tint + left-accent border
            // matching the mockup highlight (dark: rgba(253,238,208,0.06); light: rgba(194,65,12,0.05))
            ZStack(alignment: .leading) {
                Color.bizarreOrange.opacity(colorScheme == .dark ? 0.06 : 0.05)
                Rectangle()
                    .fill(Color.bizarreOrange)
                    .frame(width: 3)
            }
        } else {
            Color.bizarreSurface1
        }
    }

    // MARK: - Quick-action buttons

    private var quickActionRow: some View {
        HStack(spacing: 8) {
            quickActionBtn("+ Misc") { onShowFees?() }
            quickActionBtn("+ Discount") { onShowDiscount?() }
            quickActionBtn("+ Note") { /* note for cart, not line */ }
        }
    }

    private func quickActionBtn(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            Color.bizarreOnSurface.opacity(0.14),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    // MARK: - Coupon section

    private var couponSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Coupon")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .textCase(.uppercase)
                .kerning(0.8)

            Button {
                BrandHaptics.tap()
                onShowCoupon?()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "tag")
                        .font(.system(size: 14))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("Enter code or scan")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.bizarreOrange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Enter or scan coupon code")
            .accessibilityIdentifier("pos.cart.couponField")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "cart")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("Cart is empty")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Tap an item on the left, scan a barcode, or use Add custom line.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Totals footer (pinned at bottom — safeAreaInset in mockup)

    private var totalsFooter: some View {
        VStack(spacing: BrandSpacing.sm) {
            totalsRow(label: "Subtotal", cents: cart.subtotalCents)

            // §16.3 — discount row (only when non-zero)
            if cart.effectiveDiscountCents > 0 {
                adjustmentRow(
                    label: cart.cartDiscountPercent.map { "\(Int($0 * 100))% discount" } ?? "Discount",
                    cents: -cart.effectiveDiscountCents,
                    onEdit: onShowDiscount,
                    onRemove: { cart.clearCartDiscount() }
                )
            }

            totalsRow(label: "Tax · \(taxRateLabel)", cents: cart.taxCents)

            // §16.3 — tip row (only when non-zero)
            if cart.tipCents > 0 {
                adjustmentRow(
                    label: "Tip",
                    cents: cart.tipCents,
                    onEdit: onShowTip,
                    onRemove: { cart.setTip(cents: 0) }
                )
            }

            // §16.3 — fees row (only when non-zero)
            if cart.feesCents > 0 {
                adjustmentRow(
                    label: cart.feesLabel ?? "Fee",
                    cents: cart.feesCents,
                    onEdit: onShowFees,
                    onRemove: { cart.setFees(cents: 0) }
                )
            }

            // Total line (bolder)
            HStack(alignment: .lastTextBaseline) {
                Text("Total")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(CartMath.formatCents(cart.totalCents))
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }

            // §40 — applied tenders
            if !cart.appliedTenders.isEmpty {
                ForEach(cart.appliedTenders) { tender in
                    tenderRow(tender: tender)
                }
                Divider().background(.bizarreOutline)
                totalsRow(label: "Remaining", cents: cart.remainingCents, emphasized: true)
            }

            PosChargeButton(
                totalCents: cart.appliedTenders.isEmpty ? cart.totalCents : cart.remainingCents,
                isComplete: cart.isFullyTendered,
                isEnabled: !cart.isEmpty,
                action: onCharge
            )
            .padding(.top, BrandSpacing.xs)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.top, BrandSpacing.sm)
        .padding(.bottom, BrandSpacing.lg)
        .background(
            // Glass gradient — matches mockup's tender-safearea
            LinearGradient(
                colors: [Color.bizarreSurfaceBase.opacity(0), Color.bizarreSurfaceBase.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .overlay(alignment: .top) {
            Divider().background(.bizarreOutline)
        }
    }

    private var taxRateLabel: String {
        // Show the effective tax rate if we can derive it from the first taxed item
        if let item = cart.items.first(where: { $0.taxRate != nil }),
           let rate = item.taxRate {
            let pct = Int(truncating: (rate * 100) as NSDecimalNumber)
            return "\(pct)%"
        }
        return "8.5%"
    }

    @ViewBuilder
    private func totalsRow(label: String, cents: Int, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? .brandTitleMedium() : .brandBodyMedium())
                .foregroundStyle(emphasized ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
            Spacer()
            Text(CartMath.formatCents(cents))
                .font(emphasized ? .brandHeadlineMedium() : .brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
    }

    /// §16.3 — Adjustment row (discount / tip / fee). Negative `cents`
    /// renders in success green (matching mockup's `color: var(--success)`);
    /// positive renders normally.
    @ViewBuilder
    private func adjustmentRow(
        label: String,
        cents: Int,
        onEdit: (() -> Void)?,
        onRemove: (() -> Void)?
    ) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(1)
            Spacer()
            let isNegative = cents < 0
            Text(isNegative ? "− \(CartMath.formatCents(-cents))" : CartMath.formatCents(cents))
                .font(.brandBodyLarge())
                .foregroundStyle(isNegative ? Color(hex: 0x34C47E) : .bizarreOnSurface)
                .monospacedDigit()
            if let onEdit {
                Button {
                    BrandHaptics.tap()
                    onEdit()
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(label)")
            }
            if let onRemove {
                Button {
                    BrandHaptics.tap()
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(label)")
            }
        }
    }

    /// §40 — Negative reduction row for an applied tender.
    @ViewBuilder
    private func tenderRow(tender: AppliedTender) -> some View {
        HStack {
            Text(tender.label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
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
            .accessibilityIdentifier("pos.cart.removeTender")
        }
    }
}

// MARK: - PosCartStrip
// Compact customer banner pinned below the nav bar (mockup: cart-strip).
// Shows avatar + name + phone (catalog tab) or name + ticket-label + chip (cart tab).

struct PosCartStrip: View {
    let customer: PosCustomer
    @Bindable var cart: Cart
    var onChange: (() -> Void)?
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            // 26pt teal avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x4DB8C9), Color(hex: 0x2F6F78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(customer.initials)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x002D35))
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(customer.displayName)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let sub = stripSubtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Right side: cream Capsule chip showing line count (mockup: .chip.primary)
            if cart.lineCount > 0 {
                Text(cart.lineCount == 1 ? "1 line" : "\(cart.lineCount) lines")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.bizarreOnOrange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.bizarreOrange, in: Capsule())
                    .accessibilityLabel("\(cart.lineCount) cart lines")
            }

            // Remove customer
            if let onRemove {
                Button {
                    BrandHaptics.tap()
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove customer")
                .accessibilityIdentifier("pos.cart.removeCustomer")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color.bizarreSurface1.opacity(0.35)
                .background(.ultraThinMaterial)
        )
        .overlay(alignment: .bottom) {
            Divider().background(.bizarreOutline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Customer \(customer.displayName)")
        .accessibilityIdentifier("pos.cart.customerStrip")
    }

    private var stripSubtitle: String? {
        if customer.isWalkIn { return "Guest checkout" }
        if let p = customer.phone, !p.isEmpty { return p }
        if let e = customer.email, !e.isEmpty { return e }
        return nil
    }
}

// MARK: - PosCartRow
// Mockup layout: icon 38pt · name (bold) + SKU/qty (muted) · price (cream, Barlow)

struct PosCartRow: View {
    let item: CartItem
    let onTap: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                // Icon square — 38pt, matches mockup .cr-icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.bizarreSurface2.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.bizarreOutline.opacity(0.7), lineWidth: 0.5)
                        )
                    Image(systemName: item.inventoryItemId == nil ? "pencil" : "shippingbox.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                }
                .frame(width: 38, height: 38)
                .frame(width: 38, height: 38)

                // Name + meta
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        if let sku = item.sku, !sku.isEmpty {
                            Text("SKU \(sku)")
                                .font(.brandMono(size: 11))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        } else if item.inventoryItemId == nil {
                            Text("Custom")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOrange)
                        }
                        Text("· Qty \(item.quantity)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Spacer(minLength: BrandSpacing.sm)

                // Price column — cream, Barlow Condensed
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CartMath.formatCents(CartMath.toCents(item.unitPrice * Decimal(item.quantity))))
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOrange)
                        .monospacedDigit()
                    // Strike-through original if discounted
                    if item.discountCents > 0 {
                        let orig = CartMath.toCents(item.unitPrice * Decimal(item.quantity)) + item.discountCents
                        Text(CartMath.formatCents(orig))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .strikethrough()
                            .monospacedDigit()
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), quantity \(item.quantity), \(CartMath.formatCents(item.lineSubtotalCents)). Tap to edit.")
        .accessibilityIdentifier("pos.cartRow.\(item.id)")
    }
}

// MARK: - PosCartCustomerChip
// Full glass chip used in standalone cart panel header when a full chip is
// needed (legacy path, kept for iPad cart panel header).

struct PosCartCustomerChip: View {
    let customer: PosCustomer
    var onChange: (() -> Void)?
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle().fill(Color.bizarreOrangeContainer)
                if customer.isWalkIn {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.bizarreOnOrange)
                } else {
                    Text(customer.initials)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnOrange)
                }
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(customer.displayName)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let sub = subtitle {
                    Text(sub)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BrandSpacing.sm)

            if let onChange {
                Button {
                    BrandHaptics.tap()
                    onChange()
                } label: {
                    Text("Change")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOrange)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pos.cart.changeCustomer")
            }

            if let onRemove {
                Button {
                    BrandHaptics.tap()
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove customer from cart")
                .accessibilityIdentifier("pos.cart.removeCustomerChip")
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurface1.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Customer \(customer.displayName)")
        .accessibilityIdentifier("pos.cart.customerChip")
    }

    private var subtitle: String? {
        if customer.isWalkIn { return "Guest checkout" }
        if let e = customer.email, !e.isEmpty { return e }
        if let p = customer.phone, !p.isEmpty { return p }
        return nil
    }
}

// MARK: - PosQuantityStepper

/// "- N +" stepper. Decrement below 1 is handled by caller.
struct PosQuantityStepper: View {
    let quantity: Int
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Decrease quantity")

            Text("\(quantity)")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .frame(minWidth: 24)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.bizarreOrange)
            .accessibilityLabel("Increase quantity")
        }
    }
}

// MARK: - PosChargeButton

/// Charge CTA — the only "chrome over content" glass on the POS screen,
/// per CLAUDE.md guidance. Cream fill, dark text, full-width.
struct PosChargeButton: View {
    let totalCents: Int
    var isComplete: Bool = false
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.sm) {
                Text(isComplete ? "Complete" : "Charge")
                    .font(.brandTitleMedium())
                Text(CartMath.formatCents(totalCents))
                    .font(.brandTitleMedium())
                    .monospacedDigit()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, 18)
            .padding(.horizontal, 18)
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
                // Inset white-glow stroke (mockup: inset 0 1.5px 0 rgba(255,255,255,0.50) + border)
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.bizarreOnSurface.opacity(0.30), lineWidth: 1.5)
            )
            .shadow(color: Color(hex: 0xFDEED0).opacity(0.12), radius: 20, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("\(isComplete ? "Complete" : "Charge") total \(CartMath.formatCents(totalCents))")
        .accessibilityIdentifier("pos.chargeButton")
    }
}

// MARK: - Color(hex:) private helper

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

#endif
