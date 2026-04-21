#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// Cart column — list of `CartItem` rows with inc/dec controls, totals
/// footer, and the floating Charge CTA. Shared by the iPhone compact
/// layout and the iPad split-view trailing column.
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

    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                if let customer = cart.customer {
                    PosCartCustomerChip(
                        customer: customer,
                        onChange: onChangeCustomer,
                        onRemove: onRemoveCustomer
                    )
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
                }
                cartContent
                totalsFooter
            }
        }
    }

    @ViewBuilder
    private var cartContent: some View {
        if cart.isEmpty {
            emptyState
        } else {
            List {
                ForEach(cart.items) { item in
                    PosCartRow(
                        item: item,
                        onIncrement: {
                            BrandHaptics.tap()
                            cart.update(id: item.id, quantity: item.quantity + 1)
                        },
                        onDecrement: {
                            BrandHaptics.tap()
                            cart.update(id: item.id, quantity: item.quantity - 1)
                        }
                    )
                    .listRowBackground(Color.bizarreSurface1)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            cart.remove(id: item.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
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
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

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

    private var totalsFooter: some View {
        VStack(spacing: BrandSpacing.sm) {
            totalsRow(label: "Subtotal", cents: cart.subtotalCents)
            totalsRow(label: "Tax", cents: cart.taxCents)
            Divider().background(.bizarreOutline)
            totalsRow(label: "Total", cents: cart.totalCents, emphasized: true)
            // §40 — applied tenders render as negative rows followed by a
            // Remaining row. Hidden with no tenders so the 90%+ of sales
            // without store value keep the familiar totals layout.
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

            Button {
                BrandHaptics.tap()
                onOpenDrawer()
            } label: {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "tray.and.arrow.up")
                    Text("Open drawer")
                }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityLabel("Open cash drawer")
            .accessibilityHint("Pair a receipt printer first")
            .overlay(alignment: .bottom) {
                Text("Pair a receipt printer first")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .offset(y: 18)
            }
            .padding(.bottom, BrandSpacing.lg)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.top, BrandSpacing.sm)
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

    /// §40 — Negative reduction row for an applied tender. Tap "x" to
    /// remove; the Cart re-computes `remainingCents` without closing
    /// the sheet.
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

/// Single cart row. Inc/dec buttons are sized for thumb reach; tapping
/// the row surface is a no-op so the swipe + context-menu are the only
/// entry points for destructive edits.
struct PosCartRow: View {
    let item: CartItem
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(item.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)
                HStack(spacing: BrandSpacing.sm) {
                    Text(CartMath.formatCents(CartMath.toCents(item.unitPrice * Decimal(item.quantity))))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                    if let sku = item.sku, !sku.isEmpty {
                        Text(sku)
                            .font(.brandMono(size: 12))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    } else if item.inventoryItemId == nil {
                        Text("Custom")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOrange)
                    }
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            PosQuantityStepper(
                quantity: item.quantity,
                onIncrement: onIncrement,
                onDecrement: onDecrement
            )
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), quantity \(item.quantity), line total \(CartMath.formatCents(item.lineSubtotalCents))")
    }
}

/// "- N +" stepper. Decrement below 1 removes the row (handled by Cart).
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

/// Customer chip pinned to the top of the cart panel once a customer is
/// attached (§16.4). Avatar initials + display name + contact line +
/// Change / Remove affordance. Walk-in renders the ghost icon instead of
/// initials and says "Guest checkout" below the name. Uses `.brandGlass`
/// because it's navigation-layer chrome, not a row.
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
                .accessibilityIdentifier("pos.cart.removeCustomer")
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

/// Charge CTA — the only "chrome over content" glass on the POS screen,
/// per CLAUDE.md guidance.
struct PosChargeButton: View {
    let totalCents: Int
    var isComplete: Bool = false
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "creditcard.fill")
                Text("\(isComplete ? "Complete" : "Charge") \(CartMath.formatCents(totalCents))")
                    .font(.brandTitleMedium())
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            .foregroundStyle(.black)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .controlSize(.large)
        .disabled(!isEnabled)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("\(isComplete ? "Complete" : "Charge") total \(CartMath.formatCents(totalCents))")
    }
}
#endif
