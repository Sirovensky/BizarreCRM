#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §40.1 — POS gift card sell sheet.
///
/// Two tabs: **Physical** (scan + activate) and **Virtual** (email / SMS).
///
/// iPhone: standard sheet with `.medium`/`.large` detents.
/// iPad: centred at 520 pt fixed width.
struct GiftCardSellSheet: View {
    @Environment(\.dismiss) private var dismiss
    let api: APIClient

    @State private var viewModel: GiftCardSellViewModel

    init(api: APIClient) {
        self.api = api
        _viewModel = State(wrappedValue: GiftCardSellViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            Form {
                modePickerSection
                switch viewModel.sellMode {
                case .physical: physicalSection
                case .virtual:  virtualSection
                }
                if case .failure(let msg) = viewModel.state {
                    Section {
                        Text(msg)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                    }
                }
                if case .sent(let card) = viewModel.state {
                    successSection(card: card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Sell Gift Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .frame(idealWidth: 520) // iPad centered sheet
    }

    // MARK: - Mode picker

    private var modePickerSection: some View {
        Section {
            Picker("Mode", selection: $viewModel.sellMode) {
                Text("Physical card").tag(GiftCardSellViewModel.SellMode.physical)
                Text("Virtual (email)").tag(GiftCardSellViewModel.SellMode.virtual)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Physical

    @ViewBuilder
    private var physicalSection: some View {
        Section("Scan or type card barcode") {
            HStack(spacing: BrandSpacing.sm) {
                TextField("Card code", text: $viewModel.barcodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .monospaced()
                    .accessibilityIdentifier("giftCardSell.barcode")
                lookupButton
            }
            if let card = viewModel.scannedCard {
                physicalCardInfo(card: card)
            }
        }

        if viewModel.isUnissued {
            Section("Activation amount") {
                HStack {
                    Text("$")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    TextField("Amount in cents", text: $viewModel.activationAmountInput)
                        .keyboardType(.numberPad)
                        .monospacedDigit()
                        .accessibilityIdentifier("giftCardSell.activationAmount")
                }
                activateButton
            }
        }
    }

    private var lookupButton: some View {
        Button {
            Task { await viewModel.lookupCard() }
        } label: {
            if case .scanning = viewModel.state {
                ProgressView()
            } else {
                Text("Look up")
            }
        }
        .buttonStyle(.bordered)
        .tint(.bizarreOrange)
        .disabled(
            viewModel.barcodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || viewModel.state == .scanning
        )
        .accessibilityIdentifier("giftCardSell.lookup")
    }

    private func physicalCardInfo(card: GiftCard) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
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
                Text("Status")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                if viewModel.isUnissued {
                    Text("Unissued — ready to activate")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreSuccess)
                } else {
                    Text(card.active ? "Active" : "Inactive")
                        .font(.brandLabelLarge())
                        .foregroundStyle(card.active ? .bizarreSuccess : .bizarreError)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Card \(card.code), status \(viewModel.isUnissued ? "unissued" : card.active ? "active" : "inactive")")
    }

    private var activateButton: some View {
        Button {
            Task { await viewModel.activateCard() }
        } label: {
            HStack {
                if case .activating = viewModel.state { ProgressView().tint(.black) }
                else { Image(systemName: "creditcard.fill") }
                Text("Activate Card")
                    .font(.brandTitleSmall())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.xs)
            .foregroundStyle(.black)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(!viewModel.canActivate)
        .accessibilityIdentifier("giftCardSell.activate")
    }

    // MARK: - Virtual

    @ViewBuilder
    private var virtualSection: some View {
        Section("Recipient") {
            TextField("Name", text: $viewModel.recipientName)
                .textContentType(.name)
                .accessibilityIdentifier("giftCardSell.recipientName")
            TextField("Email", text: $viewModel.recipientEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("giftCardSell.recipientEmail")
        }
        Section("Amount") {
            HStack {
                Text("$")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                TextField("Amount in cents", text: $viewModel.virtualAmountInput)
                    .keyboardType(.numberPad)
                    .monospacedDigit()
                    .accessibilityIdentifier("giftCardSell.virtualAmount")
            }
        }
        Section("Message (optional)") {
            TextField("Personal message", text: $viewModel.message, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("giftCardSell.message")
        }
        Section {
            sendVirtualButton
        }
    }

    private var sendVirtualButton: some View {
        Button {
            Task { await viewModel.sendVirtualCard() }
        } label: {
            HStack {
                if case .activating = viewModel.state { ProgressView().tint(.black) }
                else { Image(systemName: "envelope.fill") }
                Text("Send Gift Card")
                    .font(.brandTitleSmall())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.xs)
            .foregroundStyle(.black)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(!viewModel.canSendVirtual)
        .accessibilityIdentifier("giftCardSell.send")
    }

    // MARK: - Success

    private func successSection(card: GiftCard) -> some View {
        Section {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.bizarreSuccess)
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
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            Button("Issue Another") {
                viewModel.reset()
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("giftCardSell.issueAnother")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gift card issued. Code \(card.code), balance \(CartMath.formatCents(card.balanceCents))")
    }
}
#endif
