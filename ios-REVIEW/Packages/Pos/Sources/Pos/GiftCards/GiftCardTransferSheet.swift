#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §40.1 — Transfer balance from one gift card to another.
///
/// Cashier looks up source + target cards (by typing or scanning), enters
/// an amount, and taps Transfer. The server moves the balance and creates
/// an audit entry automatically.
struct GiftCardTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    let api: APIClient

    @State private var viewModel: GiftCardTransferViewModel

    init(api: APIClient) {
        self.api = api
        _viewModel = State(wrappedValue: GiftCardTransferViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                targetSection
                amountSection
                if let err = viewModel.validationError, !isTerminalState {
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
                    }
                }
                if case .success(let response) = viewModel.state {
                    successSection(response: response)
                } else {
                    transferButton
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Transfer Gift Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .frame(idealWidth: 520)
    }

    // MARK: - Source

    private var sourceSection: some View {
        Section("Source card") {
            HStack(spacing: BrandSpacing.sm) {
                TextField("Source card code", text: $viewModel.sourceCodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .monospaced()
                    .accessibilityIdentifier("giftCardTransfer.sourceCode")
                Button {
                    Task { await viewModel.lookupSource() }
                } label: {
                    if case .lookingUpSource = viewModel.state {
                        ProgressView()
                    } else {
                        Text("Look up")
                    }
                }
                .buttonStyle(.bordered)
                .tint(.bizarreOrange)
                .disabled(
                    viewModel.sourceCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.state == .lookingUpSource
                )
                .accessibilityIdentifier("giftCardTransfer.lookupSource")
            }
            if let source = viewModel.sourceCard {
                cardSummaryRow(card: source, label: "Balance")
            }
        }
    }

    // MARK: - Target

    private var targetSection: some View {
        Section("Target card") {
            HStack(spacing: BrandSpacing.sm) {
                TextField("Target card code", text: $viewModel.targetCodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .monospaced()
                    .accessibilityIdentifier("giftCardTransfer.targetCode")
                Button {
                    Task { await viewModel.lookupTarget() }
                } label: {
                    if case .lookingUpTarget = viewModel.state {
                        ProgressView()
                    } else {
                        Text("Look up")
                    }
                }
                .buttonStyle(.bordered)
                .tint(.bizarreOrange)
                .disabled(
                    viewModel.targetCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.state == .lookingUpTarget
                )
                .accessibilityIdentifier("giftCardTransfer.lookupTarget")
            }
            if let target = viewModel.targetCard {
                cardSummaryRow(card: target, label: "Current balance")
            }
        }
    }

    // MARK: - Amount

    private var amountSection: some View {
        Section("Transfer amount") {
            HStack {
                Text("$")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                TextField("Cents to transfer", text: $viewModel.amountInput)
                    .keyboardType(.numberPad)
                    .monospacedDigit()
                    .accessibilityIdentifier("giftCardTransfer.amount")
            }
        }
    }

    // MARK: - Actions

    private var transferButton: some View {
        Section {
            Button {
                Task { await viewModel.transfer() }
            } label: {
                HStack {
                    if case .transferring = viewModel.state { ProgressView().tint(.black) }
                    else { Image(systemName: "arrow.left.arrow.right") }
                    Text("Transfer Balance")
                        .font(.brandTitleSmall())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(!viewModel.canTransfer)
            .accessibilityIdentifier("giftCardTransfer.transfer")
        }
    }

    // MARK: - Success

    private func successSection(response: TransferGiftCardResponse) -> some View {
        Section {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.bizarreSuccess)
                Text("Transfer Complete")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                HStack {
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text("Source remaining")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text(CartMath.formatCents(response.sourceBalanceCents))
                            .font(.brandBodyMedium())
                            .monospacedDigit()
                            .foregroundStyle(.bizarreOnSurface)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                        Text("Target new balance")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text(CartMath.formatCents(response.targetBalanceCents))
                            .font(.brandBodyMedium())
                            .monospacedDigit()
                            .foregroundStyle(.bizarreOrange)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            Button("Done") { dismiss() }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("giftCardTransfer.done")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transfer complete. Source remaining \(CartMath.formatCents(response.sourceBalanceCents)), target new balance \(CartMath.formatCents(response.targetBalanceCents))")
    }

    // MARK: - Helpers

    private func cardSummaryRow(card: GiftCard, label: String) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(CartMath.formatCents(card.balanceCents))
                .font(.brandTitleMedium())
                .monospacedDigit()
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(CartMath.formatCents(card.balanceCents))")
    }

    private var isTerminalState: Bool {
        if case .success = viewModel.state { return true }
        return false
    }
}
#endif
