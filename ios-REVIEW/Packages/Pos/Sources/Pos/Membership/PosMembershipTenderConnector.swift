// MARK: - Module placement guard
// ─────────────────────────────────────────────────────────────────────────────
// This file wires MembershipViewModel into the tender flow.
// It MUST only be instantiated from the tender-method-picker or the
// tender amount bar — never from cart, catalog, or inspector views.
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - PosMembershipTenderConnector (§16.15)

/// Bridges `MembershipViewModel` into the tender flow.
///
/// Responsibilities:
/// 1. Load the customer's loyalty account on `.task` when `customerId` is set.
/// 2. Auto-apply the tier discount to `cart` once the account loads.
/// 3. Supply `MembershipBenefitBanner` with the redeem-points sheet.
/// 4. Propagate `pointsToEarn` into the receipt payload's `loyaltyDelta`.
///
/// Layout: this view renders only the `MembershipBenefitBanner` (and the
/// `RedeemPointsSheet` sheet trigger). Embed it in the tender screen's
/// scroll content between the total header and the method grid.
///
/// Usage:
/// ```swift
/// PosMembershipTenderConnector(
///     customerId: cart.customer?.id,
///     cart: cart,
///     cartSubtotalCents: CartMath.totals(from: cart).subtotalCents
/// )
/// ```
public struct PosMembershipTenderConnector: View {

    // MARK: - Inputs

    let customerId: Int64?
    let cart: Cart
    let cartSubtotalCents: Int
    /// Pass the invoice ID once the invoice is created (for audit trail).
    var invoiceId: Int64? = nil

    // MARK: - State

    @State private var membershipVM: MembershipViewModel
    @State private var showingRedeemSheet: Bool = false
    @State private var memberDiscountApplied: Bool = false

    // MARK: - Init

    public init(
        customerId: Int64?,
        cart: Cart,
        cartSubtotalCents: Int,
        invoiceId: Int64? = nil,
        repository: LoyaltyRepository? = nil
    ) {
        self.customerId = customerId
        self.cart = cart
        self.cartSubtotalCents = cartSubtotalCents
        self.invoiceId = invoiceId
        let repo = repository ?? DefaultLoyaltyRepository()
        _membershipVM = State(initialValue: MembershipViewModel(repository: repo))
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if membershipVM.isLoading {
                loadingBanner
            } else if membershipVM.account?.isMember == true {
                MembershipBenefitBanner(vm: membershipVM) {
                    showingRedeemSheet = true
                }
                .sheet(isPresented: $showingRedeemSheet) {
                    RedeemPointsSheet(
                        vm: membershipVM,
                        invoiceId: invoiceId
                    )
                }
            }
            // No account / walk-in → renders nothing (EmptyView equivalent)
        }
        .task(id: customerId) {
            await loadAccount()
        }
        .onChange(of: cartSubtotalCents) { _, newValue in
            membershipVM.cartSubtotalCents = newValue
        }
    }

    // MARK: - Loading

    private var loadingBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.bizarreOrange)
            Text("Loading membership info…")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityLabel("Loading membership information")
    }

    // MARK: - Load and auto-apply

    private func loadAccount() async {
        guard let customerId, customerId > 0 else { return }

        membershipVM.cartSubtotalCents = cartSubtotalCents
        await membershipVM.load(customerId: customerId)

        // §16.15 Auto-apply member tier discount to cart at tender entry.
        if let account = membershipVM.account, account.isMember, !memberDiscountApplied {
            let cartCopy = cart   // @MainActor-captured reference
            await MainActor.run {
                let discPct = account.discountPercent
                guard discPct > 0 else { return }
                let fraction = Double(discPct) / 100.0
                let existing = cartCopy.cartDiscountPercent ?? 0.0
                if fraction > existing {
                    cartCopy.setCartDiscountPercent(fraction)
                    AppLog.pos.info(
                        "PosMembershipTenderConnector: auto-applied \(discPct)% member discount"
                    )
                }
                memberDiscountApplied = true
            }
        }
    }
}

// MARK: - DefaultLoyaltyRepository (fall-through when no DI)

/// Minimal stub repository used when no real repo is injected.
/// Returns nil (no membership) for all customers.
private final class DefaultLoyaltyRepository: LoyaltyRepository {
    func fetchAccount(customerId: Int64) async throws -> LoyaltyAccount? {
        return nil
    }

    func redeemPoints(customerId: Int64, points: Int, invoiceId: Int64?) async throws -> Int {
        throw APITransportError.httpStatus(501, message: nil)
    }
}

// MARK: - ReceiptPayload helper (§16.15 points earned on receipt)

/// Convenience to build the loyalty receipt fields from a `MembershipViewModel`
/// after a completed sale. Call this from `PosPostSaleViewModel.buildPayload()`.
///
/// ```swift
/// let loyaltyFields = PosMembershipReceiptBuilder.fields(
///     from: membershipVM,
///     saleSubtotalCents: CartMath.totals(from: cart).subtotalCents
/// )
/// payload = PosReceiptPayload(
///     ...
///     loyaltyDelta:           loyaltyFields.delta,
///     loyaltyTierBefore:      loyaltyFields.tierBefore,
///     loyaltyTierAfter:       loyaltyFields.tierAfter,
///     loyaltyPointsTotal:     loyaltyFields.pointsTotal,
///     loyaltyNextTierPoints:  loyaltyFields.nextTierPoints
/// )
/// ```
public struct PosMembershipReceiptFields: Sendable {
    public let delta: Int?
    public let tierBefore: String?
    public let tierAfter: String?
    public let pointsTotal: Int?
    public let nextTierPoints: Int?
}

public enum PosMembershipReceiptBuilder {
    /// Extract receipt-ready loyalty fields from a `MembershipViewModel`.
    ///
    /// `delta` is `vm.pointsToEarn` — the client-side estimate of points
    /// earned this sale. The server is authoritative after the sale completes.
    @MainActor
    public static func fields(
        from vm: MembershipViewModel
    ) -> PosMembershipReceiptFields {
        guard let account = vm.account, account.isMember else {
            return PosMembershipReceiptFields(
                delta: nil,
                tierBefore: nil,
                tierAfter: nil,
                pointsTotal: nil,
                nextTierPoints: nil
            )
        }
        return PosMembershipReceiptFields(
            delta: vm.pointsToEarn > 0 ? vm.pointsToEarn : nil,
            tierBefore: account.tier.displayName,
            tierAfter: account.tier.displayName,   // server confirms tier-up post-sale
            pointsTotal: account.pointsBalance + vm.pointsToEarn,
            nextTierPoints: account.pointsToNextTier
        )
    }
}
#endif
