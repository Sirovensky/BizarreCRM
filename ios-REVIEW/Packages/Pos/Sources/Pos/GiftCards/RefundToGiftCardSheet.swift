#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §40.1 — Invoice refund with optional gift-card issuance.
///
/// Surfaced from the invoice refund flow (Phase 4 D invoices). Two tender
/// options:
///   • Original tender — returns money to original payment method.
///   • New gift card — server issues a fresh gift card for the refund amount.
///
/// iPhone: medium/large sheet.
/// iPad: centered at 520 pt.
struct RefundToGiftCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let api: APIClient

    @State private var viewModel: RefundToGiftCardViewModel

    init(invoiceId: Int64, amountCents: Int, api: APIClient) {
        self.api = api
        _viewModel = State(
            wrappedValue: RefundToGiftCardViewModel(
                invoiceId: invoiceId,
                amountCents: amountCents,
                api: api
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                tenderSection
                if case .failure(let msg) = viewModel.state {
                    Section {
                        Text(msg)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                    }
                }
                if case .success(let response) = viewModel.state {
                    successSection(response: response)
                } else {
                    refundButton
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Issue Refund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .frame(idealWidth: 520)
    }

    // MARK: - Amount

    private var amountSection: some View {
        Section("Refund amount") {
            HStack {
                Text("Amount")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(CartMath.formatCents(viewModel.amountCents))
                    .font(.brandTitleMedium())
                    .monospacedDigit()
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
    }

    // MARK: - Tender picker

    private var tenderSection: some View {
        Section("Refund to") {
            tenderRow(
                title: "Original tender",
                subtitle: "Returns to original payment method",
                icon: "arrow.uturn.backward.circle",
                isSelected: !viewModel.toGiftCard
            ) {
                viewModel.toGiftCard = false
            }
            tenderRow(
                title: "New gift card",
                subtitle: "Issues a fresh gift card for the refund amount",
                icon: "giftcard.fill",
                isSelected: viewModel.toGiftCard
            ) {
                viewModel.toGiftCard = true
            }
        }
    }

    private func tenderRow(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(title)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(subtitle)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityLabel("Selected")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Refund button

    private var refundButton: some View {
        Section {
            Button {
                Task { await viewModel.submitRefund() }
            } label: {
                HStack {
                    if case .processing = viewModel.state { ProgressView().tint(.black) }
                    else { Image(systemName: viewModel.toGiftCard ? "giftcard.fill" : "arrow.uturn.backward.circle") }
                    Text(viewModel.toGiftCard ? "Issue Gift Card" : "Process Refund")
                        .font(.brandTitleSmall())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(!viewModel.canRefund)
            .accessibilityIdentifier("refundToGiftCard.submit")
        }
    }

    // MARK: - Success

    private func successSection(response: InvoiceRefundResponse) -> some View {
        Section {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.bizarreSuccess)
                if let card = response.issuedGiftCard {
                    Text("Gift Card Issued")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Code: \(card.code)")
                        .font(.brandBodyMedium())
                        .monospaced()
                        .foregroundStyle(.bizarreOnSurface)
                    Text(CartMath.formatCents(card.balanceCents))
                        .font(.brandTitleLarge())
                        .monospacedDigit()
                        .foregroundStyle(.bizarreOrange)
                } else {
                    Text("Refund Processed")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(CartMath.formatCents(viewModel.amountCents))
                        .font(.brandTitleLarge())
                        .monospacedDigit()
                        .foregroundStyle(.bizarreOnSurface)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            Button("Done") { dismiss() }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("refundToGiftCard.done")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(response.issuedGiftCard != nil
            ? "Gift card issued with code \(response.issuedGiftCard!.code)"
            : "Refund of \(CartMath.formatCents(viewModel.amountCents)) processed")
    }
}
#endif
