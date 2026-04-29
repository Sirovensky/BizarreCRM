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
    // §19.9 — Refund policy + auto-batch close
    /// Maximum days since sale that a refund can be processed (0 = no limit).
    public var refundMaxDaysSinceSale: Int
    /// Refunds above this dollar amount require manager approval (0 = always allowed).
    public var refundManagerApprovalAbove: Double
    /// Auto-close card batch enabled (mirrors `batchCloseMinuteOfDay != nil`).
    public var batchCloseEnabled: Bool
    /// Minute-of-day (0–1439) when auto-close fires; `0` = midnight.
    public var batchCloseMinuteOfDay: Int

    public static let `default` = PaymentMethodSettings(
        cashEnabled: true, cardEnabled: true,
        giftCardEnabled: false, storeCreditEnabled: false,
        checkEnabled: false, blockChypApiKey: "", blockChypTerminalName: "",
        cardSurchargeEnabled: false,
        tippingEnabled: false,
        tipPresets: [10, 15, 20],
        manualKeyedCardAllowed: false,
        refundMaxDaysSinceSale: 30,
        refundManagerApprovalAbove: 100,
        batchCloseEnabled: false,
        batchCloseMinuteOfDay: 23 * 60   // 11 PM default
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
                manualKeyedCardAllowed: resp.manualKeyedCardAllowed ?? false,
                refundMaxDaysSinceSale: resp.refundMaxDaysSinceSale ?? 30,
                refundManagerApprovalAbove: resp.refundManagerApprovalAbove ?? 100,
                batchCloseEnabled: resp.batchCloseMinuteOfDay != nil,
                batchCloseMinuteOfDay: resp.batchCloseMinuteOfDay ?? (23 * 60)
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
                manualKeyedCardAllowed: settings.manualKeyedCardAllowed,
                refundMaxDaysSinceSale: settings.refundMaxDaysSinceSale,
                refundManagerApprovalAbove: settings.refundManagerApprovalAbove,
                batchCloseMinuteOfDay: settings.batchCloseEnabled ? settings.batchCloseMinuteOfDay : nil
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

            // MARK: §19.9 — Refund policy
            Section {
                Stepper(
                    "Max days since sale: \(vm.settings.refundMaxDaysSinceSale == 0 ? "No limit" : "\(vm.settings.refundMaxDaysSinceSale)")",
                    value: $vm.settings.refundMaxDaysSinceSale, in: 0...365
                )
                .accessibilityIdentifier("payment.refundMaxDays")

                HStack {
                    Text("Manager approval above")
                    Spacer()
                    TextField("0", value: $vm.settings.refundManagerApprovalAbove,
                              format: .currency(code: "USD"))
                        #if canImport(UIKit)
                        .keyboardType(.decimalPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .accessibilityIdentifier("payment.refundManagerThreshold")
                }
            } header: {
                Text("Refund policy")
            } footer: {
                Text("0 days = no time limit. Refunds above the threshold prompt for manager PIN at checkout.")
            }

            // MARK: §19.9 — Auto-close card batch
            if vm.settings.cardEnabled {
                Section {
                    Toggle("Auto-close batch daily", isOn: $vm.settings.batchCloseEnabled)
                        .accessibilityIdentifier("payment.batchCloseEnabled")

                    if vm.settings.batchCloseEnabled {
                        DatePicker(
                            "Close at",
                            selection: Binding(
                                get: { batchCloseDate(minuteOfDay: vm.settings.batchCloseMinuteOfDay) },
                                set: { vm.settings.batchCloseMinuteOfDay = minuteOfDay(from: $0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .accessibilityIdentifier("payment.batchCloseTime")
                    }
                } header: {
                    Text("Card batch close")
                } footer: {
                    Text("BlockChyp settles the day's transactions automatically at this time. Disable to close manually each evening.")
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

    // MARK: §19.9 — minute-of-day ↔ Date helpers

    private func batchCloseDate(minuteOfDay: Int) -> Date {
        let cal = Calendar.current
        let mod = max(0, min(1439, minuteOfDay))
        let h = mod / 60
        let m = mod % 60
        return cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    private func minuteOfDay(from date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}
