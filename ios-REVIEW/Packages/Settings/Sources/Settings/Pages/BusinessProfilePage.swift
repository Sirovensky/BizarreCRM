import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

/// §19 Business Profile page — wraps GET/PUT /settings/store.
/// Edits the store's public-facing identity fields (name, address, phone,
/// email, timezone, currency, receipt header/footer).
@MainActor
@Observable
public final class BusinessProfileViewModel: Sendable {

    // MARK: Form fields

    var storeName: String = ""
    var address: String = ""
    var phone: String = ""
    var email: String = ""
    var timezone: String = ""
    var currency: String = "USD"
    var receiptHeader: String = ""
    var receiptFooter: String = ""

    // MARK: State

    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var successMessage: String?

    // MARK: Validation

    var isValid: Bool {
        !storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Init

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    // MARK: API

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let api else { return }
        do {
            let cfg = try await api.fetchStoreConfig()
            storeName      = cfg.storeName      ?? ""
            address        = cfg.address        ?? ""
            phone          = cfg.phone          ?? ""
            email          = cfg.email          ?? ""
            timezone       = cfg.timezone       ?? ""
            currency       = cfg.currency       ?? "USD"
            receiptHeader  = cfg.receiptHeader  ?? ""
            receiptFooter  = cfg.receiptFooter  ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        guard isValid else {
            errorMessage = "Store name is required."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        guard let api else { return }
        do {
            let body = StoreConfigRequest(
                storeName:     storeName,
                address:       address,
                phone:         phone,
                email:         email,
                timezone:      timezone,
                currency:      currency,
                receiptHeader: receiptHeader,
                receiptFooter: receiptFooter
            )
            _ = try await api.updateStoreConfig(body)
            successMessage = "Business profile saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct BusinessProfilePage: View {
    @State private var vm: BusinessProfileViewModel

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: BusinessProfileViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section("Business identity") {
                TextField("Store name", text: $vm.storeName)
                    .accessibilityLabel("Store name")
                    .accessibilityIdentifier("business.storeName")
                TextField("Address", text: $vm.address)
                    #if canImport(UIKit)
                    .textContentType(.streetAddressLine1)
                    #endif
                    .accessibilityLabel("Address")
                    .accessibilityIdentifier("business.address")
            }

            Section("Contact") {
                TextField("Phone", text: $vm.phone)
                    #if canImport(UIKit)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    #endif
                    .accessibilityLabel("Phone")
                    .accessibilityIdentifier("business.phone")
                TextField("Email", text: $vm.email)
                    #if canImport(UIKit)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    #endif
                    .accessibilityLabel("Email")
                    .accessibilityIdentifier("business.email")
            }

            Section("Locale") {
                TextField("Timezone (IANA)", text: $vm.timezone)
                    .autocorrectionDisabled()
                    #if canImport(UIKit)
                    .autocapitalization(.none)
                    #endif
                    .accessibilityLabel("Timezone")
                    .accessibilityIdentifier("business.timezone")
                TextField("Currency (ISO, e.g. USD)", text: $vm.currency)
                    .autocorrectionDisabled()
                    #if canImport(UIKit)
                    .autocapitalization(.allCharacters)
                    #endif
                    .accessibilityLabel("Currency code")
                    .accessibilityIdentifier("business.currency")
            }

            Section("Receipt text") {
                TextField("Header", text: $vm.receiptHeader, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityLabel("Receipt header")
                    .accessibilityIdentifier("business.receiptHeader")
                TextField("Footer", text: $vm.receiptFooter, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityLabel("Receipt footer")
                    .accessibilityIdentifier("business.receiptFooter")
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
                        .accessibilityLabel("Success: \(msg)")
                }
            }
        }
        .navigationTitle("Business Profile")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await vm.save() } }
                    .disabled(vm.isSaving || !vm.isValid)
                    .accessibilityIdentifier("business.save")
            }
        }
        .task { await vm.load() }
        .overlay {
            if vm.isLoading {
                ProgressView().accessibilityLabel("Loading business profile")
            }
        }
    }
}
