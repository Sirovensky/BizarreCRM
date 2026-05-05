#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §40.1 — Reload an existing gift card.
///
/// Caller passes an already-looked-up `GiftCard` (e.g. from the redeem flow).
/// Amount validation enforces $500 cap and active-card requirement client-side
/// before the POST fires; server enforces the same rules authoritatively.
struct GiftCardReloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    let card: GiftCard
    let api: APIClient

    @State private var viewModel: GiftCardReloadViewModel

    init(card: GiftCard, api: APIClient) {
        self.card = card
        self.api = api
        var vm = GiftCardReloadViewModel(api: api)
        vm.card = card
        _viewModel = State(wrappedValue: vm)
    }

    var body: some View {
        NavigationStack {
            Form {
                cardInfoSection
                amountSection
                if let err = viewModel.validationError {
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
                if case .success(let newBalance) = viewModel.state {
                    successSection(newBalance: newBalance)
                } else {
                    reloadButton
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Reload Gift Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .frame(idealWidth: 520)
    }

    // MARK: - Card info

    private var cardInfoSection: some View {
        Section("Card") {
            HStack {
                Text("Code")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(card.code)
                    .font(.brandBodyMedium())
                    .monospaced()
                    .foregroundStyle(.bizarreOnSurface)
            }
            HStack {
                Text("Current balance")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(CartMath.formatCents(card.balanceCents))
                    .font(.brandTitleMedium())
                    .monospacedDigit()
                    .foregroundStyle(.bizarreOnSurface)
            }
            HStack {
                Text("Status")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(card.active ? "Active" : "Inactive")
                    .font(.brandLabelLarge())
                    .foregroundStyle(card.active ? .bizarreSuccess : .bizarreError)
            }
        }
    }

    // MARK: - Amount

    private var amountSection: some View {
        Section("Reload amount") {
            HStack {
                Text("$")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                TextField("Cents to add", text: $viewModel.amountInput)
                    .keyboardType(.numberPad)
                    .monospacedDigit()
                    .accessibilityIdentifier("giftCardReload.amount")
            }
            if viewModel.amountCents > 0, viewModel.validationError == nil {
                HStack {
                    Text("New balance")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text(CartMath.formatCents(card.balanceCents + viewModel.amountCents))
                        .font(.brandTitleMedium())
                        .monospacedDigit()
                        .foregroundStyle(.bizarreOrange)
                }
            }
        }
    }

    // MARK: - Actions

    private var reloadButton: some View {
        Section {
            Button {
                Task { await viewModel.reload() }
            } label: {
                HStack {
                    if case .loading = viewModel.state { ProgressView().tint(.black) }
                    else { Image(systemName: "arrow.up.circle.fill") }
                    Text("Reload Card")
                        .font(.brandTitleSmall())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(!viewModel.canReload)
            .accessibilityIdentifier("giftCardReload.reload")
        }
    }

    // MARK: - Success

    private func successSection(newBalance: Int) -> some View {
        Section {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.bizarreSuccess)
                Text("Card Reloaded")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("New balance: \(CartMath.formatCents(newBalance))")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            Button("Done") { dismiss() }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("giftCardReload.done")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Card reloaded. New balance \(CartMath.formatCents(newBalance))")
    }
}
#endif
