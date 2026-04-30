import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class CompanyInfoViewModel: Sendable {

    var legalName: String = ""
    var dba: String = ""
    var address: String = ""
    var city: String = ""
    var state: String = ""
    var zip: String = ""
    var phone: String = ""
    var website: String = ""
    var ein: String = ""

    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var successMessage: String?

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let api else { return }
        do {
            let info = try await api.fetchCompanyInfo()
            legalName = info.legalName ?? ""
            dba = info.dba ?? ""
            address = info.address ?? ""
            city = info.city ?? ""
            state = info.state ?? ""
            zip = info.zip ?? ""
            phone = info.phone ?? ""
            website = info.website ?? ""
            ein = info.ein ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let api else { return }
        do {
            let body = CompanyInfoDTO(
                legalName: legalName, dba: dba,
                address: address, city: city, state: state, zip: zip,
                phone: phone, website: website, ein: ein
            )
            _ = try await api.saveCompanyInfo(body)
            successMessage = "Company info saved."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct CompanyInfoPage: View {
    @State private var vm: CompanyInfoViewModel

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: CompanyInfoViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section("Legal") {
                TextField("Legal name", text: $vm.legalName)
                    .accessibilityLabel("Legal name")
                    .accessibilityIdentifier("company.legalName")
                TextField("DBA (doing business as)", text: $vm.dba)
                    .accessibilityLabel("DBA")
                    .accessibilityIdentifier("company.dba")
                TextField("EIN / Tax ID", text: $vm.ein)
                    #if canImport(UIKit)
                    .textContentType(.organizationName)
                    #endif
                    .accessibilityLabel("EIN or Tax ID")
                    .accessibilityIdentifier("company.ein")
            }

            Section("Address") {
                TextField("Street address", text: $vm.address)
                    #if canImport(UIKit)
                    .textContentType(.streetAddressLine1)
                    #endif
                    .accessibilityLabel("Street address")
                    .accessibilityIdentifier("company.address")
                TextField("City", text: $vm.city)
                    #if canImport(UIKit)
                    .textContentType(.addressCity)
                    #endif
                    .accessibilityLabel("City")
                    .accessibilityIdentifier("company.city")
                TextField("State", text: $vm.state)
                    #if canImport(UIKit)
                    .textContentType(.addressState)
                    #endif
                    .accessibilityLabel("State")
                    .accessibilityIdentifier("company.state")
                TextField("ZIP", text: $vm.zip)
                    #if canImport(UIKit)
                    .textContentType(.postalCode)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                    .accessibilityLabel("ZIP code")
                    .accessibilityIdentifier("company.zip")
            }

            Section("Contact") {
                TextField("Phone", text: $vm.phone)
                    #if canImport(UIKit)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    #endif
                    .accessibilityLabel("Phone")
                    .accessibilityIdentifier("company.phone")
                TextField("Website", text: $vm.website)
                    #if canImport(UIKit)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    #endif
                    .accessibilityLabel("Website")
                    .accessibilityIdentifier("company.website")
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
        .navigationTitle("Company Info")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await vm.save() } }
                    .disabled(vm.isSaving)
                    .accessibilityIdentifier("company.save")
            }
        }
        .task { await vm.load() }
        .overlay {
            if vm.isLoading {
                ProgressView().accessibilityLabel("Loading company info")
            }
        }
    }
}
