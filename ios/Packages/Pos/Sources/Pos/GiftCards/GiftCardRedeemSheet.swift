#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §40 — Apply a gift card as tender at POS.
///
/// `POST /api/v1/gift-cards/:id/redeem`
///
/// Caller passes the already-looked-up `GiftCard` (e.g. from `GiftCardLookupView`).
/// The sheet lets the cashier enter the amount to redeem (up to the card
/// balance) and optionally an invoice id / reason.
///
/// iPhone: `.medium`/`.large` sheet detents.
/// iPad: centred panel at 520 pt; `.medium` detent only for overlay feel.
///
/// On success the `onRedeemed` closure fires with the remaining balance in
/// cents so the POS cart can record the tender without a second network call.
struct GiftCardRedeemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let card: GiftCard
    let api: APIClient
    /// Called with the remaining balance (in cents) after a successful redeem.
    var onRedeemed: ((Int) -> Void)?

    @State private var viewModel: GiftCardRedeemViewModel

    init(
        card: GiftCard,
        api: APIClient,
        onRedeemed: ((Int) -> Void)? = nil
    ) {
        self.card = card
        self.api = api
        self.onRedeemed = onRedeemed
        var vm = GiftCardRedeemViewModel(api: api)
        vm.card = card
        _viewModel = State(wrappedValue: vm)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if Platform.isCompact {
                    redeemForm
                } else {
                    // iPad: two-column feel with the balance card pinned left.
                    padLayout
                }
            }
            .navigationTitle("Redeem Gift Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.medium])
        .presentationDragIndicator(.visible)
        .frame(idealWidth: Platform.isCompact ? nil : 520)
    }

    // MARK: - iPad layout

    private var padLayout: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                GiftCardBalanceCard(card: card, prominent: true)
                    .padding(.horizontal, BrandSpacing.base)
                redeemForm
            }
            .padding(.top, BrandSpacing.sm)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Form

    private var redeemForm: some View {
        Form {
            if Platform.isCompact {
                Section {
                    GiftCardBalanceCard(card: card, prominent: false)
                        .padding(.vertical, BrandSpacing.xs)
                }
            }

            amountSection
            optionsSection

            if let err = viewModel.validationError, !viewModel.amountInput.isEmpty {
                Section {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                }
            }
            if case .failure(let msg) = viewModel.state {
                Section {
                    Text(msg)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .accessibilityIdentifier("giftCardRedeem.error")
                }
            }
            if case .redeemed(let remaining) = viewModel.state {
                successSection(remaining: remaining)
            } else {
                redeemButtonSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Amount

    private var amountSection: some View {
        Section("Amount to redeem") {
            HStack(spacing: BrandSpacing.xs) {
                Text("$")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                TextField("Cents (e.g. 1000 = $10.00)", text: $viewModel.amountInput)
                    .keyboardType(.numberPad)
                    .monospacedDigit()
                    .accessibilityIdentifier("giftCardRedeem.amount")
            }

            if let remaining = viewModel.previewRemainingCents {
                HStack {
                    Text("Remaining after")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text(CartMath.formatCents(remaining))
                        .font(.brandTitleSmall())
                        .monospacedDigit()
                        .foregroundStyle(remaining > 0 ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                }
            }
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        Section("Options (optional)") {
            TextField("Reason / reference", text: $viewModel.reason)
                .autocorrectionDisabled()
                .accessibilityIdentifier("giftCardRedeem.reason")
        }
    }

    // MARK: - Redeem button

    private var redeemButtonSection: some View {
        Section {
            Button {
                Task { await redeemAndCallback() }
            } label: {
                HStack {
                    if case .redeeming = viewModel.state {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    Text("Apply as Tender")
                        .font(.brandTitleSmall())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(!viewModel.canRedeem)
            .accessibilityIdentifier("giftCardRedeem.redeem")
        }
    }

    // MARK: - Success

    private func successSection(remaining: Int) -> some View {
        Section {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.bizarreSuccess)
                Text("Tender Applied")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                HStack(spacing: BrandSpacing.base) {
                    VStack(spacing: BrandSpacing.xxs) {
                        Text("Redeemed")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text(CartMath.formatCents(viewModel.amountCents))
                            .font(.brandTitleSmall())
                            .monospacedDigit()
                            .foregroundStyle(.bizarreOrange)
                    }
                    Divider()
                    VStack(spacing: BrandSpacing.xxs) {
                        Text("Remaining")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text(CartMath.formatCents(remaining))
                            .font(.brandTitleSmall())
                            .monospacedDigit()
                            .foregroundStyle(.bizarreOnSurface)
                    }
                }
                Button("Done") { dismiss() }
                    .padding(.top, BrandSpacing.xs)
                    .accessibilityIdentifier("giftCardRedeem.done")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Tender applied. Redeemed \(CartMath.formatCents(viewModel.amountCents)). "
            + "Remaining balance \(CartMath.formatCents(remaining))."
        )
    }

    // MARK: - Helpers

    private func redeemAndCallback() async {
        await viewModel.redeem()
        if case .redeemed(let remaining) = viewModel.state {
            onRedeemed?(remaining)
        }
    }
}
#endif
