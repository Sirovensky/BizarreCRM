import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - ViewModel

@MainActor
@Observable
final class CompanyInfoViewModel {
    var name: String = ""
    var address: String = ""
    var phone: String = ""
    var website: String = ""
    var ein: String = ""

    var nameError: String? = nil
    var phoneError: String? = nil
    var websiteError: String? = nil
    var einError: String? = nil

    var isNextEnabled: Bool {
        CompanyInfoValidator.isNextEnabled(name: name, phone: phone)
    }

    var asPayload: [String: String] {
        var d: [String: String] = ["name": name]
        if !address.isEmpty  { d["address"]  = address }
        if !phone.isEmpty    { d["phone"]    = phone }
        if !website.isEmpty  { d["website"]  = website }
        if !ein.isEmpty      { d["ein"]      = ein }
        return d
    }

    func onNameBlur() {
        let r = CompanyInfoValidator.validateName(name)
        nameError = r.isValid ? nil : r.errorMessage
    }

    func onPhoneChange(_ raw: String) {
        let digits = raw.filter(\.isNumber)
        if digits.count >= 10 {
            phone = CompanyInfoValidator.formatPhone(raw)
        } else {
            phone = raw
        }
    }

    func onPhoneBlur() {
        guard !phone.isEmpty else { phoneError = nil; return }
        let r = CompanyInfoValidator.validatePhone(phone)
        phoneError = r.isValid ? nil : r.errorMessage
        if r.isValid { phone = CompanyInfoValidator.formatPhone(phone) }
    }

    func onWebsiteBlur() {
        guard !website.isEmpty else { websiteError = nil; return }
        let r = CompanyInfoValidator.validateWebsite(website)
        websiteError = r.isValid ? nil : r.errorMessage
    }

    func onEINBlur() {
        guard !ein.isEmpty else { einError = nil; return }
        let r = CompanyInfoValidator.validateEIN(ein)
        einError = r.isValid ? nil : r.errorMessage
    }
}

// MARK: - View  (§36.2 Step 2 — Company Info)

public struct CompanyInfoStepView: View {
    let onValidityChanged: (Bool) -> Void
    let onNext: ([String: String]) -> Void

    @State private var vm = CompanyInfoViewModel()
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case name, address, phone, website, ein
    }

    public init(
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping ([String: String]) -> Void
    ) {
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                Text("Company Info")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .padding(.top, BrandSpacing.lg)
                    .accessibilityAddTraits(.isHeader)

                Group {
                    // Name (required)
                    brandField(
                        label: "Company Name",
                        hint: "Required",
                        text: $vm.name,
                        field: .name,
                        error: vm.nameError,
                        onBlur: vm.onNameBlur
                    )
                    #if canImport(UIKit)
                    .keyboardType(.default)
                    .textContentType(.organizationName)
                    #endif

                    // Address — plain TextField
                    // TODO: Replace with MKLocalSearchCompleter-backed picker for autocomplete
                    brandField(
                        label: "Address",
                        hint: "Optional — start typing your address",
                        text: $vm.address,
                        field: .address,
                        error: nil,
                        onBlur: nil
                    )
                    #if canImport(UIKit)
                    .textContentType(.fullStreetAddress)
                    #endif

                    // Phone (required)
                    brandField(
                        label: "Phone",
                        hint: "Required — (XXX) XXX-XXXX",
                        text: Binding(
                            get: { vm.phone },
                            set: { vm.onPhoneChange($0) }
                        ),
                        field: .phone,
                        error: vm.phoneError,
                        onBlur: vm.onPhoneBlur
                    )
                    #if canImport(UIKit)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    #endif

                    // Website (optional)
                    brandField(
                        label: "Website",
                        hint: "Optional — https://example.com",
                        text: $vm.website,
                        field: .website,
                        error: vm.websiteError,
                        onBlur: vm.onWebsiteBlur
                    )
                    #if canImport(UIKit)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    #endif

                    // EIN (optional)
                    brandField(
                        label: "EIN",
                        hint: "Optional — XX-XXXXXXX",
                        text: $vm.ein,
                        field: .ein,
                        error: vm.einError,
                        onBlur: vm.onEINBlur
                    )
                    #if canImport(UIKit)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: vm.isNextEnabled) { _, valid in
            onValidityChanged(valid)
        }
        .onAppear {
            onValidityChanged(vm.isNextEnabled)
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
                .submitLabel(nextSubmitLabel(for: field))
                .onSubmit { advanceFocus(from: field) }
                .onChange(of: focus) { old, new in
                    if old == field && new != field {
                        onBlur?()
                    }
                }
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(error != nil ? Color.bizarreError : Color.bizarreOutline.opacity(0.5), lineWidth: 1)
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

    private func nextSubmitLabel(for field: Field) -> SubmitLabel {
        field == .ein ? .done : .next
    }

    private func advanceFocus(from field: Field) {
        switch field {
        case .name:    focus = .address
        case .address: focus = .phone
        case .phone:   focus = .website
        case .website: focus = .ein
        case .ein:
            focus = nil
            if vm.isNextEnabled { onNext(vm.asPayload) }
        }
    }
}
