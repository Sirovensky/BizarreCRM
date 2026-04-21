import SwiftUI
import DesignSystem
import Networking

// MARK: - ReferralRuleEditorViewModel

@Observable
@MainActor
public final class ReferralRuleEditorViewModel {
    public var ruleType: ReferralRuleType = .flat
    public var senderCreditDollars: String = "5.00"
    public var receiverCreditDollars: String = "5.00"
    public var percentageString: String = "5"
    public var minSaleDollars: String = "0.00"
    public var isSaving = false
    public var errorMessage: String?
    public var didSave = false

    private let api: APIClient

    public init(api: APIClient, existingRule: ReferralRule? = nil) {
        self.api = api
        if let rule = existingRule {
            ruleType = rule.type
            senderCreditDollars = String(format: "%.2f", Double(rule.senderCreditCents) / 100)
            receiverCreditDollars = String(format: "%.2f", Double(rule.receiverCreditCents) / 100)
            percentageString = String(rule.percentageBps / 100)
            minSaleDollars = String(format: "%.2f", Double(rule.minSaleCents) / 100)
        }
    }

    public var currentRule: ReferralRule? {
        guard let minSale = parseCents(minSaleDollars) else { return nil }
        switch ruleType {
        case .flat:
            guard let sender = parseCents(senderCreditDollars),
                  let receiver = parseCents(receiverCreditDollars) else { return nil }
            return ReferralRule(type: .flat, senderCreditCents: sender, receiverCreditCents: receiver, minSaleCents: minSale, percentageBps: 0)
        case .percentage:
            guard let pct = Int(percentageString.trimmingCharacters(in: .whitespaces)), pct > 0, pct <= 100 else { return nil }
            return ReferralRule(type: .percentage, senderCreditCents: 0, receiverCreditCents: 0, minSaleCents: minSale, percentageBps: pct * 100)
        }
    }

    public var canSave: Bool { currentRule != nil && !isSaving }

    public func save() async {
        guard let rule = currentRule else { return }
        isSaving = true
        errorMessage = nil
        do {
            _ = try await api.post("referrals/rule", body: rule, as: ReferralRule.self)
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func parseCents(_ string: String) -> Int? {
        guard let value = Double(string.trimmingCharacters(in: .whitespaces)), value >= 0 else { return nil }
        return Int(value * 100)
    }
}

// MARK: - ReferralRuleEditorView

/// Admin editor for the global referral credit rule (flat / percentage / min-sale threshold).
public struct ReferralRuleEditorView: View {
    @State private var vm: ReferralRuleEditorViewModel
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient, existingRule: ReferralRule? = nil) {
        _vm = State(initialValue: ReferralRuleEditorViewModel(api: api, existingRule: existingRule))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Rule Type") {
                    Picker("Type", selection: $vm.ruleType) {
                        ForEach(ReferralRuleType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Referral rule type")
                }

                if vm.ruleType == .flat {
                    Section("Credits (USD)") {
                        LabeledContent("Sender Credit") {
                            TextField("0.00", text: $vm.senderCreditDollars)
                                #if canImport(UIKit)
                                .keyboardType(.decimalPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                        }
                        .accessibilityLabel("Sender credit amount")
                        LabeledContent("Receiver Credit") {
                            TextField("0.00", text: $vm.receiverCreditDollars)
                                #if canImport(UIKit)
                                .keyboardType(.decimalPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                        }
                        .accessibilityLabel("Receiver credit amount")
                    }
                } else {
                    Section("Percentage") {
                        LabeledContent("Percentage (%)") {
                            TextField("5", text: $vm.percentageString)
                                #if canImport(UIKit)
                                .keyboardType(.numberPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                        }
                        .accessibilityLabel("Credit percentage")
                    }
                }

                Section("Minimum Sale") {
                    LabeledContent("Min Sale (USD)") {
                        TextField("0.00", text: $vm.minSaleDollars)
                            #if canImport(UIKit)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityLabel("Minimum qualifying sale amount")
                }

                if let preview = vm.currentRule {
                    Section("Preview") {
                        previewRow(rule: preview)
                    }
                }

                if let error = vm.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.bizarreError)
                            .accessibilityLabel("Error: \(error)")
                    }
                }
            }
            .navigationTitle("Edit Referral Rule")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await vm.save() } }
                        .disabled(!vm.canSave)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .onChange(of: vm.didSave) { _, saved in
                if saved { dismiss() }
            }
            .overlay {
                if vm.isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    private func previewRow(rule: ReferralRule) -> some View {
        let sale = Sale(amountCents: 10_000) // $100 example
        let credits = ReferralCreditCalculator.credit(onSale: sale, rule: rule)
        return VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("On a $100 sale:")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("Sender earns \(String(format: "$%.2f", Double(credits.senderCents) / 100))")
                .font(.brandBodyMedium())
            Text("Receiver earns \(String(format: "$%.2f", Double(credits.receiverCents) / 100))")
                .font(.brandBodyMedium())
        }
        .accessibilityElement(children: .combine)
    }
}
