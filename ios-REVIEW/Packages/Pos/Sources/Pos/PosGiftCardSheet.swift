#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §40 — "Gift card & store credit" sheet. Cashier types / pastes a gift
/// card code, we look it up, and the sheet shows balance + expiry + an
/// amount field defaulted to `min(remaining, balance)`. Redeem POSTs the
/// amount; on success we append an `AppliedTender` to the cart.
///
/// When `cart.customer.id` is non-nil we also fetch the store-credit
/// balance on appear and render a second section with a one-tap Apply.
///
/// All money is cents. All formatting routes through `CartMath.formatCents`
/// so the brand mono digit string stays consistent with the rest of POS.
struct PosGiftCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var cart: Cart
    let api: APIClient

    @State private var viewModel: PosGiftCardSheetViewModel

    init(cart: Cart, api: APIClient) {
        self.cart = cart
        self.api = api
        _viewModel = State(wrappedValue: PosGiftCardSheetViewModel(
            api: api,
            remainingCents: cart.remainingCents,
            customerId: cart.customer?.id
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                giftCardSection
                if viewModel.storeCreditSectionEnabled {
                    storeCreditSection
                }
                if let err = viewModel.errorMessage {
                    Section {
                        Text(err)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Gift card & credit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await viewModel.loadStoreCreditIfNeeded() }
            .onChange(of: cart.remainingCents) { _, new in
                viewModel.remainingChanged(to: new)
            }
        }
    }

    private var giftCardSection: some View {
        Section("Gift card") {
            HStack(spacing: BrandSpacing.sm) {
                TextField("Enter code", text: $viewModel.codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .monospaced()
                    .accessibilityIdentifier("pos.giftCard.codeField")
                Button {
                    Task { await viewModel.lookup() }
                } label: {
                    if viewModel.isLookingUp { ProgressView() } else { Text("Look up") }
                }
                .buttonStyle(.bordered)
                .tint(.bizarreOrange)
                .disabled(viewModel.codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLookingUp)
                .accessibilityIdentifier("pos.giftCard.lookup")
            }

            // §16.6 — "Check balance only" — lets cashier (or customer) verify
            // remaining balance without committing the card to a tender leg.
            // Only shown when a valid active card is loaded and no apply is in
            // progress, so it doesn't clutter the idle state.
            if let card = viewModel.card, viewModel.balanceCheckResult == nil {
                Button {
                    viewModel.checkBalanceOnly(card: card)
                    BrandHaptics.tap()
                } label: {
                    Label("Check balance only", systemImage: "creditcard.and.123")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOrange)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pos.giftCard.checkBalance")
            }

            // Balance-check result pill — dismisses on next lookup or code change.
            if let result = viewModel.balanceCheckResult {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: result.active ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .foregroundStyle(result.active ? Color.bizarreSuccess : Color.bizarreError)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Balance: \(CartMath.formatCents(result.balanceCents))")
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                        if let expiry = PosGiftCardSheetViewModel.formattedExpiry(result.expiresAt) {
                            Text(result.active ? "Expires \(expiry)" : "Expired \(expiry)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        } else {
                            Text(result.active ? "Active" : "Inactive")
                                .font(.brandLabelSmall())
                                .foregroundStyle(result.active ? Color.bizarreSuccess : Color.bizarreError)
                        }
                    }
                    Spacer()
                    Button {
                        viewModel.dismissBalanceCheck()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss balance result")
                }
                .padding(BrandSpacing.sm)
                .background(
                    result.active ? Color.bizarreSuccess.opacity(0.10) : Color.bizarreError.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Gift card balance \(CartMath.formatCents(result.balanceCents)). \(result.active ? "Active" : "Inactive").")
                .accessibilityIdentifier("pos.giftCard.balanceResult")
            }

            if let card = viewModel.card {
                giftCardBody(card: card)
            }
        }
    }

    @ViewBuilder
    private func giftCardBody(card: GiftCard) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text("Balance")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(CartMath.formatCents(card.balanceCents))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            HStack {
                Text(card.active ? "Active" : "Inactive")
                    .font(.brandLabelLarge())
                    .foregroundStyle(card.active ? .bizarreSuccess : .bizarreOnSurfaceMuted)
                Spacer()
                if let when = PosGiftCardSheetViewModel.formattedExpiry(card.expiresAt) {
                    Text("Expires \(when)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xxs)

        TextField("Amount (cents)", text: $viewModel.applyCentsInput)
            .keyboardType(.numberPad)
            .monospacedDigit()
            .accessibilityIdentifier("pos.giftCard.amountField")
        Text("Default applies \(CartMath.formatCents(viewModel.defaultApplyCents(for: card))) — the lesser of remaining and balance.")
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)

        Button {
            Task { await viewModel.redeem(intoCart: cart) }
        } label: {
            HStack {
                if viewModel.isRedeeming { ProgressView().tint(.black) }
                else { Image(systemName: "creditcard.fill") }
                Text("Apply \(CartMath.formatCents(viewModel.parsedApplyCents(for: card)))")
                    .font(.brandTitleSmall())
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.xs)
            .foregroundStyle(.black)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(!viewModel.canRedeem(card: card))
        .accessibilityIdentifier("pos.giftCard.apply")
    }

    @ViewBuilder
    private var storeCreditSection: some View {
        Section("Store credit") {
            if viewModel.isLoadingStoreCredit {
                HStack {
                    ProgressView()
                    Text("Loading balance…")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } else if let credit = viewModel.storeCredit {
                HStack {
                    Text("Available")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text(CartMath.formatCents(credit.balanceCents))
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                Button {
                    if let tender = viewModel.applyStoreCredit() {
                        cart.apply(tender: tender)
                        BrandHaptics.success()
                    }
                } label: {
                    HStack {
                        Image(systemName: "wallet.pass.fill")
                        Text("Apply \(CartMath.formatCents(viewModel.applicableStoreCreditCents()))")
                            .font(.brandTitleSmall())
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.xs)
                    .foregroundStyle(.black)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .disabled(viewModel.applicableStoreCreditCents() == 0)
                .accessibilityIdentifier("pos.storeCredit.apply")
            }
        }
    }
}
#endif
