#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.17 — Editable list of applied tenders. Each row is removable.
/// After checkout is committed a manager PIN is required (see `ManagerPinSheet`).
public struct AppliedTendersListView: View {
    let cart:              Cart
    /// Whether checkout has been committed (manager PIN required to remove).
    let checkoutCommitted: Bool
    /// Called when a tender is removed. Caller may trigger a re-auth flow.
    let onTenderRemoved:   (UUID) -> Void
    /// Called when the edit-amount button is tapped for a specific tender.
    let onEditAmount:      (UUID) -> Void

    @State private var pendingRemoveId:  UUID? = nil
    @State private var showManagerPin:   Bool  = false

    public init(
        cart: Cart,
        checkoutCommitted: Bool = false,
        onTenderRemoved:   @escaping (UUID) -> Void,
        onEditAmount:      @escaping (UUID) -> Void
    ) {
        self.cart              = cart
        self.checkoutCommitted = checkoutCommitted
        self.onTenderRemoved   = onTenderRemoved
        self.onEditAmount      = onEditAmount
    }

    public var body: some View {
        VStack(spacing: 0) {
            if cart.appliedTenders.isEmpty {
                emptyState
            } else {
                ForEach(cart.appliedTenders) { tender in
                    tenderRow(tender)
                    if tender.id != cart.appliedTenders.last?.id {
                        Divider().padding(.leading, BrandSpacing.base)
                    }
                }
            }
        }
        .sheet(isPresented: $showManagerPin) {
            ManagerPinSheet { approved in
                if approved, let id = pendingRemoveId {
                    cart.removeTender(id: id)
                    onTenderRemoved(id)
                }
                pendingRemoveId = nil
            }
        }
        .accessibilityIdentifier("appliedTenders.list")
    }

    // MARK: - Row

    private func tenderRow(_ tender: AppliedTender) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: iconName(tender.kind))
                .foregroundStyle(.bizarreOrange)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(tender.label)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let ref = tender.reference {
                    Text(ref)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            // Edit-amount inline button
            Button {
                onEditAmount(tender.id)
            } label: {
                Text(CartMath.formatCents(tender.amountCents))
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .underline()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit amount for \(tender.label): \(CartMath.formatCents(tender.amountCents))")
            .accessibilityIdentifier("appliedTenders.edit.\(tender.id)")

            // Remove button
            Button(role: .destructive) {
                remove(id: tender.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.bizarreError)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(tender.label)")
            .accessibilityIdentifier("appliedTenders.remove.\(tender.id)")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tender.label), \(CartMath.formatCents(tender.amountCents))")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack {
            Text("No tenders applied")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityIdentifier("appliedTenders.empty")
    }

    // MARK: - Actions

    private func remove(id: UUID) {
        if checkoutCommitted {
            // Require manager PIN to remove a tender after checkout is committed.
            pendingRemoveId = id
            showManagerPin  = true
        } else {
            cart.removeTender(id: id)
            onTenderRemoved(id)
        }
    }

    private func iconName(_ kind: AppliedTender.Kind) -> String {
        switch kind {
        case .giftCard:    return "giftcard"
        case .storeCredit: return "banknote"
        }
    }
}
#endif
