#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.12 Late Fee Policy Editor — admin-only view

@MainActor
@Observable
final class LateFeePolicyEditorViewModel {
    // Policy toggles
    var useFlatFee: Bool = false
    var flatFeeString: String = ""
    var flatFeeCents: Int = 0

    var usePercentPerDay: Bool = false
    var percentPerDayString: String = ""
    var percentPerDay: Double = 0.0

    var gracePeriodDays: Int = 7
    var compoundDaily: Bool = false

    var useMaxFee: Bool = false
    var maxFeeString: String = ""
    var maxFeeCents: Int = 0

    // §7 (1283) Jurisdiction selection (e.g. "US-CA"). nil = no validation.
    var jurisdictionCode: String? = nil
    /// Reference invoice total in cents used for percent-of-invoice cap checks
    /// when validating flat fees. Defaults to $1 000 = 100 000 cents.
    var referenceInvoiceTotalCents: Int = 100_000

    var isSubmitting: Bool = false
    var errorMessage: String?
    var didSave: Bool = false

    @ObservationIgnored private let api: APIClient

    init(api: APIClient, existing: LateFeePolicy? = nil) {
        self.api = api
        if let p = existing {
            useFlatFee = p.flatFeeCents != nil
            flatFeeCents = p.flatFeeCents ?? 0
            flatFeeString = useFlatFee ? String(format: "%.2f", Double(flatFeeCents) / 100.0) : ""

            usePercentPerDay = p.percentPerDay != nil
            percentPerDay = p.percentPerDay ?? 0.0
            percentPerDayString = usePercentPerDay ? String(format: "%.4f", percentPerDay) : ""

            gracePeriodDays = p.gracePeriodDays
            compoundDaily = p.compoundDaily

            useMaxFee = p.maxFeeCents != nil
            maxFeeCents = p.maxFeeCents ?? 0
            maxFeeString = useMaxFee ? String(format: "%.2f", Double(maxFeeCents) / 100.0) : ""
        }
    }

    /// §7 (1283) Compliance warnings against the selected jurisdiction.
    /// Returns empty when no jurisdiction is selected.
    var jurisdictionWarnings: [LateFeeJurisdictionValidator.Warning] {
        guard
            let code = jurisdictionCode,
            let limit = LateFeeJurisdictionRegistry.limit(for: code)
        else { return [] }
        return LateFeeJurisdictionValidator.validate(
            policy: currentPolicy,
            invoiceTotalCents: referenceInvoiceTotalCents,
            limit: limit
        )
    }

    var currentPolicy: LateFeePolicy {
        LateFeePolicy(
            flatFeeCents: useFlatFee ? flatFeeCents : nil,
            percentPerDay: usePercentPerDay ? percentPerDay : nil,
            gracePeriodDays: gracePeriodDays,
            compoundDaily: compoundDaily,
            maxFeeCents: useMaxFee ? maxFeeCents : nil
        )
    }

    func updateFlatFee(from string: String) {
        flatFeeString = string
        if let d = Double(string.filter { $0.isNumber || $0 == "." }) {
            flatFeeCents = Int((d * 100).rounded())
        }
    }

    func updatePercent(from string: String) {
        percentPerDayString = string
        percentPerDay = Double(string) ?? 0.0
    }

    func updateMaxFee(from string: String) {
        maxFeeString = string
        if let d = Double(string.filter { $0.isNumber || $0 == "." }) {
            maxFeeCents = Int((d * 100).rounded())
        }
    }

    func save() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            _ = try await api.patch(
                "/api/v1/settings/late-fee-policy",
                body: currentPolicy,
                as: LateFeePolicy.self
            )
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct LateFeePolicyEditorView: View {
    @State private var vm: LateFeePolicyEditorViewModel
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient, existing: LateFeePolicy? = nil) {
        _vm = State(wrappedValue: LateFeePolicyEditorViewModel(api: api, existing: existing))
    }

    public var body: some View {
        Form {
            Section("Flat fee") {
                Toggle("Charge flat fee", isOn: $vm.useFlatFee)
                    .accessibilityLabel("Enable flat late fee")
                if vm.useFlatFee {
                    HStack {
                        Text("Amount (USD)")
                        Spacer()
                        TextField("0.00", text: $vm.flatFeeString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: vm.flatFeeString) { _, new in vm.updateFlatFee(from: new) }
                            .accessibilityLabel("Flat fee amount in dollars")
                    }
                }
            }

            Section("Daily percentage") {
                Toggle("Charge daily %", isOn: $vm.usePercentPerDay)
                    .accessibilityLabel("Enable daily percentage late fee")
                if vm.usePercentPerDay {
                    HStack {
                        Text("% per day")
                        Spacer()
                        TextField("0.05", text: $vm.percentPerDayString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: vm.percentPerDayString) { _, new in vm.updatePercent(from: new) }
                            .accessibilityLabel("Percentage per overdue day")
                    }
                    Toggle("Compound daily", isOn: $vm.compoundDaily)
                        .disabled(!vm.usePercentPerDay)
                        .accessibilityLabel("Compound interest daily")
                }
            }

            Section("Grace period") {
                Stepper("Grace period: \(vm.gracePeriodDays) day\(vm.gracePeriodDays == 1 ? "" : "s")",
                        value: $vm.gracePeriodDays, in: 0...90)
                    .accessibilityLabel("Grace period before fee applies, \(vm.gracePeriodDays) days")
            }

            Section("Cap") {
                Toggle("Maximum fee", isOn: $vm.useMaxFee)
                    .accessibilityLabel("Enable maximum fee cap")
                if vm.useMaxFee {
                    HStack {
                        Text("Max (USD)")
                        Spacer()
                        TextField("0.00", text: $vm.maxFeeString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: vm.maxFeeString) { _, new in vm.updateMaxFee(from: new) }
                            .accessibilityLabel("Maximum late fee cap in dollars")
                    }
                }
            }

            // §7 (1283) Jurisdiction limits — surface warnings when the
            // configured policy exceeds known statutory caps.
            Section("Jurisdiction") {
                Picker("Jurisdiction", selection: Binding(
                    get: { vm.jurisdictionCode ?? "" },
                    set: { vm.jurisdictionCode = $0.isEmpty ? nil : $0 }
                )) {
                    Text("None").tag("")
                    ForEach(LateFeeJurisdictionRegistry.all, id: \.regionCode) { lim in
                        Text("\(lim.displayName) (\(lim.regionCode))").tag(lim.regionCode)
                    }
                }
                .accessibilityLabel("Tenant jurisdiction for late-fee compliance check")

                ForEach(vm.jurisdictionWarnings, id: \.kind) { w in
                    HStack(alignment: .top, spacing: BrandSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreWarning)
                        Text(w.message)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                    .accessibilityLabel("Compliance warning: \(w.message)")
                }
            }

            if let err = vm.errorMessage {
                Section {
                    Text(err)
                        .foregroundStyle(.bizarreError)
                        .font(.brandBodyMedium())
                }
            }
        }
        .navigationTitle("Late Fee Policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task {
                        await vm.save()
                        if vm.didSave { dismiss() }
                    }
                }
                .disabled(vm.isSubmitting)
                .accessibilityLabel("Save late fee policy")
            }
        }
    }
}
#endif
