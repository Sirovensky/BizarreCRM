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

    public static let `default` = PaymentMethodSettings(
        cashEnabled: true, cardEnabled: true,
        giftCardEnabled: false, storeCreditEnabled: false,
        checkEnabled: false, blockChypApiKey: "", blockChypTerminalName: ""
    )
}

struct PaymentSettingsResponse: Codable, Sendable {
    var cashEnabled: Bool?
    var cardEnabled: Bool?
    var giftCardEnabled: Bool?
    var storeCreditEnabled: Bool?
    var checkEnabled: Bool?
    var blockChypApiKey: String?
    var blockChypTerminalName: String?
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
            let resp: PaymentSettingsResponse = try await api.get("/settings/payment", as: PaymentSettingsResponse.self)
            settings = PaymentMethodSettings(
                cashEnabled: resp.cashEnabled ?? true,
                cardEnabled: resp.cardEnabled ?? true,
                giftCardEnabled: resp.giftCardEnabled ?? false,
                storeCreditEnabled: resp.storeCreditEnabled ?? false,
                checkEnabled: resp.checkEnabled ?? false,
                blockChypApiKey: resp.blockChypApiKey ?? "",
                blockChypTerminalName: resp.blockChypTerminalName ?? ""
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
            let body = PaymentSettingsResponse(
                cashEnabled: settings.cashEnabled,
                cardEnabled: settings.cardEnabled,
                giftCardEnabled: settings.giftCardEnabled,
                storeCreditEnabled: settings.storeCreditEnabled,
                checkEnabled: settings.checkEnabled,
                blockChypApiKey: settings.blockChypApiKey,
                blockChypTerminalName: settings.blockChypTerminalName
            )
            _ = try await api.put("/settings/payment", body: body, as: PaymentSettingsResponse.self)
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
