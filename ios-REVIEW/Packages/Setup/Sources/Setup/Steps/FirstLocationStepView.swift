import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - ViewModel

@MainActor
@Observable
final class FirstLocationViewModel {
    // MARK: State

    var locationName: String = ""
    var address: String = ""
    var phone: String = ""
    var sameAsCompany: Bool = false

    // MARK: Errors

    var nameError: String? = nil
    var addressError: String? = nil

    // MARK: Company pre-fill (from step 2)

    var companyName: String = ""
    var companyAddress: String = ""
    var companyPhone: String = ""

    // MARK: Validation

    var isNextEnabled: Bool {
        Step8Validator.isNextEnabled(name: locationName, address: address)
    }

    // MARK: Pre-fill helpers

    /// Pre-fills from company data (called on appear).
    func applyCompanyDefaults() {
        if locationName.isEmpty { locationName = companyName }
        if address.isEmpty      { address      = companyAddress }
        if phone.isEmpty        { phone        = companyPhone }
    }

    func toggleSameAsCompany() {
        sameAsCompany.toggle()
        if sameAsCompany {
            address = companyAddress
        }
    }

    // MARK: Blur handlers

    func onNameBlur() {
        let r = Step8Validator.validateName(locationName)
        nameError = r.isValid ? nil : r.errorMessage
    }

    func onAddressBlur() {
        let r = Step8Validator.validateAddress(address)
        addressError = r.isValid ? nil : r.errorMessage
    }

    // MARK: Output

    var asLocation: SetupLocation {
        SetupLocation(
            name: locationName.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespaces),
            phone: phone.trimmingCharacters(in: .whitespaces)
        )
    }
}

// MARK: - View  (§36.2 Step 8 — First Location)

@MainActor
public struct FirstLocationStepView: View {
    let companyName: String
    let companyAddress: String
    let companyPhone: String
    let onValidityChanged: (Bool) -> Void
    let onNext: (SetupLocation) -> Void

    @State private var vm = FirstLocationViewModel()
    @FocusState private var focus: Field?

    enum Field: Hashable { case name, address, phone }

    public init(
        companyName: String,
        companyAddress: String,
        companyPhone: String,
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping (SetupLocation) -> Void
    ) {
        self.companyName    = companyName
        self.companyAddress = companyAddress
        self.companyPhone   = companyPhone
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                Text("First Location")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .padding(.top, BrandSpacing.lg)
                    .accessibilityAddTraits(.isHeader)

                Text("Set up your first repair shop location. You can add more locations later.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)

                // MARK: Location name

                brandField(
                    label: "Location Name",
                    hint: "e.g. Main Street, Downtown",
                    text: $vm.locationName,
                    field: .name,
                    error: vm.nameError,
                    onBlur: vm.onNameBlur
                )
                #if canImport(UIKit)
                .textContentType(.organizationName)
                #endif

                // MARK: Same as company toggle

                Toggle(isOn: Binding(
                    get: { vm.sameAsCompany },
                    set: { _ in vm.toggleSameAsCompany() }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Same address as company")
                            .font(.brandBodyMedium())
                            .foregroundStyle(Color.bizarreOnSurface)
                        if !companyAddress.isEmpty {
                            Text(companyAddress)
                                .font(.brandLabelSmall())
                                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                                .lineLimit(2)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(.bizarreOrange)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Same address as company")
                .accessibilityValue(vm.sameAsCompany ? "On" : "Off")

                // MARK: Address

                brandField(
                    label: "Address",
                    hint: "Required",
                    text: $vm.address,
                    field: .address,
                    error: vm.addressError,
                    onBlur: vm.onAddressBlur
                )
                .disabled(vm.sameAsCompany)
                .opacity(vm.sameAsCompany ? 0.6 : 1.0)
                #if canImport(UIKit)
                .textContentType(.fullStreetAddress)
                #endif

                // MARK: Phone

                brandField(
                    label: "Phone",
                    hint: "Optional",
                    text: $vm.phone,
                    field: .phone,
                    error: nil,
                    onBlur: nil
                )
                #if canImport(UIKit)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                #endif
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            vm.companyName    = companyName
            vm.companyAddress = companyAddress
            vm.companyPhone   = companyPhone
            vm.applyCompanyDefaults()
            onValidityChanged(vm.isNextEnabled)
        }
        .onChange(of: vm.isNextEnabled) { _, valid in
            onValidityChanged(valid)
        }
    }

    // MARK: Field builder

    @ViewBuilder
    private func brandField(
        label: String,
        hint: String,
        text: Binding<String>,
        field: Field,
        error: String?,
        onBlur: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            TextField(hint, text: text)
                .font(.brandBodyLarge())
                .focused($focus, equals: field)
                .submitLabel(field == .phone ? .done : .next)
                .onSubmit { advanceFocus(from: field) }
                .onChange(of: focus) { old, new in
                    if old == field && new != field { onBlur?() }
                }
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
                .accessibilityLabel(label)
                .accessibilityHint(hint)

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

    private func advanceFocus(from field: Field) {
        switch field {
        case .name:    focus = .address
        case .address: focus = .phone
        case .phone:   focus = nil
        }
    }
}
