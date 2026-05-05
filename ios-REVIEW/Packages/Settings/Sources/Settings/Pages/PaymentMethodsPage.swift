import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - Models

public struct PaymentMethodSettings: Equatable, Sendable {
    public var cashEnabled: Bool
    public var cardEnabled: Bool
    public var giftCardEnabled: Bool
    public var storeCreditEnabled: Bool
    public var checkEnabled: Bool
    public var blockChypApiKey: String
    public var blockChypTerminalName: String
    // §19.9 — surcharge, tipping, manual-keyed card
    /// Enable a card-processing surcharge passed to the customer.
    public var cardSurchargeEnabled: Bool
    /// Show tipping prompt at checkout.
    public var tippingEnabled: Bool
    /// Preset tip percentages (e.g. [10, 15, 20]) shown to the customer.
    public var tipPresets: [Int]
    /// Allow manual keyed-entry of card numbers (card-not-present; higher interchange).
    public var manualKeyedCardAllowed: Bool

    public static let `default` = PaymentMethodSettings(
        cashEnabled: true, cardEnabled: true,
        giftCardEnabled: false, storeCreditEnabled: false,
        checkEnabled: false, blockChypApiKey: "", blockChypTerminalName: "",
        cardSurchargeEnabled: false,
        tippingEnabled: false,
        tipPresets: [10, 15, 20],
        manualKeyedCardAllowed: false
    )
}

// MARK: - ViewModel

@MainActor
@Observable
public final class PaymentMethodsViewModel: Sendable {

    var settings: PaymentMethodSettings = .default
    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var successMessage: String?
    var showBlockChypKey: Bool = false

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let api else { return }
        do {
            let resp = try await api.fetchPaymentSettings()
            settings = PaymentMethodSettings(
                cashEnabled: resp.cashEnabled ?? true,
                cardEnabled: resp.cardEnabled ?? true,
                giftCardEnabled: resp.giftCardEnabled ?? false,
                storeCreditEnabled: resp.storeCreditEnabled ?? false,
                checkEnabled: resp.checkEnabled ?? false,
                blockChypApiKey: resp.blockChypApiKey ?? "",
                blockChypTerminalName: resp.blockChypTerminalName ?? "",
                cardSurchargeEnabled: resp.cardSurchargeEnabled ?? false,
                tippingEnabled: resp.tippingEnabled ?? false,
                tipPresets: resp.tipPresets ?? [10, 15, 20],
                manualKeyedCardAllowed: resp.manualKeyedCardAllowed ?? false
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let api else { return }
        do {
            let body = PaymentSettingsDTO(
                cashEnabled: settings.cashEnabled,
                cardEnabled: settings.cardEnabled,
                giftCardEnabled: settings.giftCardEnabled,
                storeCreditEnabled: settings.storeCreditEnabled,
                checkEnabled: settings.checkEnabled,
                blockChypApiKey: settings.blockChypApiKey,
                blockChypTerminalName: settings.blockChypTerminalName,
                cardSurchargeEnabled: settings.cardSurchargeEnabled,
                tippingEnabled: settings.tippingEnabled,
                tipPresets: settings.tipPresets,
                manualKeyedCardAllowed: settings.manualKeyedCardAllowed
            )
            _ = try await api.savePaymentSettings(body)
            successMessage = "Payment settings saved."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct PaymentMethodsPage: View {
    @State private var vm: PaymentMethodsViewModel

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: PaymentMethodsViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section("Accept payments via") {
                Toggle("Cash", isOn: $vm.settings.cashEnabled)
                    .accessibilityIdentifier("payment.cash")
                Toggle("Card (BlockChyp)", isOn: $vm.settings.cardEnabled)
                    .accessibilityIdentifier("payment.card")
                Toggle("Gift card", isOn: $vm.settings.giftCardEnabled)
                    .accessibilityIdentifier("payment.giftCard")
                Toggle("Store credit", isOn: $vm.settings.storeCreditEnabled)
                    .accessibilityIdentifier("payment.storeCredit")
                Toggle("Check", isOn: $vm.settings.checkEnabled)
                    .accessibilityIdentifier("payment.check")
            }

            if vm.settings.cardEnabled {
                Section {
                    TextField("Terminal name", text: $vm.settings.blockChypTerminalName)
                        .accessibilityLabel("BlockChyp terminal name")
                        .accessibilityIdentifier("payment.terminalName")

                    HStack {
                        if vm.showBlockChypKey {
                            TextField("API key", text: $vm.settings.blockChypApiKey)
                                #if canImport(UIKit)
                                .textContentType(.password)
                                .autocapitalization(.none)
                                #endif
                                .accessibilityLabel("BlockChyp API key")
                        } else {
                            SecureField("API key", text: $vm.settings.blockChypApiKey)
                                .accessibilityLabel("BlockChyp API key")
                        }
                        Button {
                            vm.showBlockChypKey.toggle()
                        } label: {
                            Image(systemName: vm.showBlockChypKey ? "eye.slash" : "eye")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        .accessibilityLabel(vm.showBlockChypKey ? "Hide API key" : "Show API key")
                        .accessibilityIdentifier("payment.toggleKeyVisibility")
                    }
                } header: {
                    Text("BlockChyp pairing")
                } footer: {
                    Text("Pair a terminal: enter terminal name + API key from BlockChyp merchant portal.")
                }
            }

            // MARK: §19.9 — Card surcharge + manual-keyed card
            if vm.settings.cardEnabled {
                Section {
                    Toggle("Card surcharge", isOn: $vm.settings.cardSurchargeEnabled)
                        .accessibilityIdentifier("payment.cardSurcharge")
                    Toggle("Allow manual card entry", isOn: $vm.settings.manualKeyedCardAllowed)
                        .accessibilityIdentifier("payment.manualKeyedCard")
                } header: {
                    Text("Card rules")
                } footer: {
                    Text("Surcharge passes the processing fee to the customer (check local regulations). Manual entry allows keyed card numbers when no terminal is present.")
                }

                // MARK: §19.9 — Tipping
                Section {
                    Toggle("Enable tipping at checkout", isOn: $vm.settings.tippingEnabled)
                        .accessibilityIdentifier("payment.tippingEnabled")

                    if vm.settings.tippingEnabled {
                        HStack(spacing: BrandSpacing.sm) {
                            Text("Presets")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            ForEach([10, 15, 20, 25], id: \.self) { pct in
                                let selected = vm.settings.tipPresets.contains(pct)
                                Button {
                                    if selected {
                                        vm.settings.tipPresets.removeAll { $0 == pct }
                                    } else {
                                        vm.settings.tipPresets.append(pct)
                                        vm.settings.tipPresets.sort()
                                    }
                                } label: {
                                    Text("\(pct)%")
                                        .font(.brandLabelLarge())
                                        .padding(.horizontal, BrandSpacing.xs)
                                        .padding(.vertical, BrandSpacing.xxs)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(selected ? Color.bizarreOrange : Color.bizarreSurface1)
                                        )
                                        .foregroundStyle(selected ? Color.white : Color.bizarreOnSurface)
                                }
                                .accessibilityLabel("\(pct)% tip preset, \(selected ? "selected" : "not selected")")
                                .accessibilityIdentifier("payment.tipPreset.\(pct)")
                            }
                        }
                        .padding(.vertical, BrandSpacing.xxs)
                        .accessibilityElement(children: .contain)
                    }
                } header: {
                    Text("Tipping")
                } footer: {
                    Text("Tap percentage chips to toggle preset tip amounts shown to customers at checkout.")
                }
            }

            if let msg = vm.errorMessage {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(msg)")
                }
            }

            if let msg = vm.successMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle")
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityLabel(msg)
                }
            }
        }
        .navigationTitle("Payment Methods")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await vm.save() } }
                    .disabled(vm.isSaving)
                    .accessibilityIdentifier("payment.save")
            }
        }
        .task { await vm.load() }
        .overlay {
            if vm.isLoading {
                ProgressView().accessibilityLabel("Loading payment settings")
            }
        }
    }
}
