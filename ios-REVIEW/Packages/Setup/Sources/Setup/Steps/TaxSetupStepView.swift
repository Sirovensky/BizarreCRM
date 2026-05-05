import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - ViewModel

@MainActor
@Observable
final class TaxSetupViewModel {
    var taxName: String = "Sales Tax"
    var rateText: String = ""
    var applyTo: TaxApply = .allItems

    var nameError: String?  = nil
    var rateError: String?  = nil

    /// Pre-filled from company address (step 2).
    var companyAddress: String = ""

    var isNextEnabled: Bool {
        Step6Validator.isNextEnabled(name: taxName, rateText: rateText)
    }

    var jurisdictionHint: String {
        let address = companyAddress.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return "" }
        // Extract region (last meaningful component after comma)
        let parts = address.components(separatedBy: ",")
        let region = parts.last?.trimmingCharacters(in: .whitespaces) ?? address
        return "Based on your address: \(region)"
    }

    func onNameBlur() {
        let r = Step6Validator.validateName(taxName)
        nameError = r.isValid ? nil : r.errorMessage
    }

    func onRateBlur() {
        let r = Step6Validator.validateRate(rateText)
        rateError = r.isValid ? nil : r.errorMessage
    }

    func onRateChange(_ raw: String) {
        // Allow only numeric characters and a single decimal point
        let filtered = raw.filter { $0.isNumber || $0 == "." }
        // Prevent more than one decimal point
        let dotCount = filtered.filter { $0 == "." }.count
        rateText = dotCount > 1 ? rateText : filtered
    }

    var asTaxRate: TaxRate? {
        guard isNextEnabled, let rate = Double(rateText) else { return nil }
        return TaxRate(name: taxName.trimmingCharacters(in: .whitespaces),
                       ratePct: rate, applyTo: applyTo)
    }
}

// MARK: - View  (§36.2 Step 6 — Tax Setup)

@MainActor
public struct TaxSetupStepView: View {
    let companyAddress: String
    let onValidityChanged: (Bool) -> Void
    let onNext: (TaxRate?) -> Void

    @State private var vm = TaxSetupViewModel()
    @FocusState private var focus: Field?

    enum Field: Hashable { case name, rate }

    public init(
        companyAddress: String,
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping (TaxRate?) -> Void
    ) {
        self.companyAddress = companyAddress
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                Text("Tax Setup")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .padding(.top, BrandSpacing.lg)
                    .accessibilityAddTraits(.isHeader)

                Text("Add your first tax rate. You can add more rates later in Settings.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)

                // MARK: Jurisdiction hint

                if !vm.jurisdictionHint.isEmpty {
                    HStack(spacing: BrandSpacing.xs) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(Color.bizarreOrange)
                            .font(.caption)
                            .accessibilityHidden(true)
                        Text(vm.jurisdictionHint)
                            .font(.brandBodyMedium())
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    }
                    .padding(BrandSpacing.sm)
                    .background(Color.bizarreSurface1.opacity(0.5),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel(vm.jurisdictionHint)
                }

                // MARK: Tax name

                fieldStack(label: "Tax Name", hint: "e.g. Sales Tax, GST, VAT", error: vm.nameError) {
                    TextField("Tax name", text: $vm.taxName)
                        .font(.brandBodyLarge())
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .rate }
                        .onChange(of: focus) { old, new in
                            if old == .name && new != .name { vm.onNameBlur() }
                        }
                        .accessibilityLabel("Tax name")
                        .accessibilityHint("e.g. Sales Tax, GST, VAT")
                }

                // MARK: Tax rate

                fieldStack(label: "Rate (%)", hint: "Enter a value between 0 and 30", error: vm.rateError) {
                    HStack {
                        TextField("0.00", text: Binding(
                            get: { vm.rateText },
                            set: { vm.onRateChange($0) }
                        ))
                        .font(.brandBodyLarge())
                        .focused($focus, equals: .rate)
                        .submitLabel(.done)
                        .onSubmit { focus = nil }
                        .onChange(of: focus) { old, new in
                            if old == .rate && new != .rate { vm.onRateBlur() }
                        }
                        #if canImport(UIKit)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityLabel("Tax rate percentage")
                        .accessibilityHint("Enter a value between 0 and 30")
                        .accessibilityValue(vm.rateText.isEmpty ? "Empty" : "\(vm.rateText) percent")

                        Text("%")
                            .font(.brandBodyLarge())
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                    }
                }

                // MARK: Apply to

                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Apply To")
                        .font(.brandLabelLarge())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)

                    Picker("Apply to", selection: $vm.applyTo) {
                        ForEach(TaxApply.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Apply tax to")
                    .accessibilityValue(vm.applyTo.displayName)
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            vm.companyAddress = companyAddress
            onValidityChanged(vm.isNextEnabled)
        }
        .onChange(of: vm.isNextEnabled) { _, valid in
            onValidityChanged(valid)
        }
    }

    // MARK: Field builder

    @ViewBuilder
    private func fieldStack<Content: View>(
        label: String,
        hint: String,
        error: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            content()
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1.opacity(0.7),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            error != nil ? Color.bizarreError : Color.bizarreOutline.opacity(0.5),
                            lineWidth: 1
                        )
                )

            if let error {
                Text(error)
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreError)
                    .accessibilityLabel("Error: \(error)")
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: error)
    }
}
