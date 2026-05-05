#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class SupplierEditorViewModel {
    public var name: String
    public var contactName: String
    public var email: String
    public var phone: String
    public var address: String
    public var paymentTerms: String
    public var leadTimeDaysText: String

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let repo: SupplierRepository
    @ObservationIgnored private let existingId: Int64?

    public init(supplier: Supplier?, repo: SupplierRepository) {
        self.repo = repo
        self.existingId = supplier?.id
        self.name           = supplier?.name ?? ""
        self.contactName    = supplier?.contactName ?? ""
        self.email          = supplier?.email ?? ""
        self.phone          = supplier?.phone ?? ""
        self.address        = supplier?.address ?? ""
        self.paymentTerms   = supplier?.paymentTerms ?? "Net 30"
        self.leadTimeDaysText = supplier.map { String($0.leadTimeDays) } ?? "7"
    }

    public var isValid: Bool {
        !name.isEmpty && !email.isEmpty && !phone.isEmpty
    }

    public func save() async -> Bool {
        guard !isSubmitting, isValid else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let body = SupplierRequest(
            name: name,
            contactName: contactName.isEmpty ? nil : contactName,
            email: email,
            phone: phone,
            address: address,
            paymentTerms: paymentTerms,
            leadTimeDays: Int(leadTimeDaysText) ?? 7
        )
        do {
            if let id = existingId {
                _ = try await repo.update(id: id, body)
            } else {
                _ = try await repo.create(body)
            }
            return true
        } catch {
            AppLog.ui.error("Supplier save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - Sheet

public struct SupplierEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: SupplierEditorViewModel
    private let onSuccess: () -> Void

    public init(supplier: Supplier?, api: APIClient, onSuccess: @escaping () -> Void) {
        self.onSuccess = onSuccess
        _vm = State(wrappedValue: SupplierEditorViewModel(
            supplier: supplier,
            repo: LiveSupplierRepository(api: api)
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section("Basic Info") {
                        TextField("Company name", text: $vm.name)
                            .accessibilityLabel("Company name")
                        TextField("Contact name", text: $vm.contactName)
                            .accessibilityLabel("Contact name")
                    }
                    Section("Contact") {
                        TextField("Email", text: $vm.email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .accessibilityLabel("Email address")
                        TextField("Phone", text: $vm.phone)
                            .keyboardType(.phonePad)
                            .accessibilityLabel("Phone number")
                        TextField("Address", text: $vm.address, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityLabel("Address")
                    }
                    Section("Terms") {
                        TextField("Payment terms (e.g. Net 30)", text: $vm.paymentTerms)
                            .accessibilityLabel("Payment terms")
                        TextField("Lead time (days)", text: $vm.leadTimeDaysText)
                            .keyboardType(.numberPad)
                            .accessibilityLabel("Lead time in days")
                    }
                    if let msg = vm.errorMessage {
                        Section {
                            Text(msg).foregroundStyle(.bizarreError).font(.brandBodyMedium())
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(vm.name.isEmpty ? "New Supplier" : vm.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSubmitting {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                let ok = await vm.save()
                                if ok { onSuccess(); dismiss() }
                            }
                        }
                        .disabled(!vm.isValid)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
